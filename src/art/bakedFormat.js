// Binary container for baked characters (assets/baked/<id>.bin), shared by the baker (encode) and runtime (decode).
// Layout: 'DAC1' | u32 headerBytes | header JSON (utf8, padded to 4) | buffers (each 4-byte aligned).
// header.buffers = [{ name, type, count, itemSize, offset, byteLength, normalized }] ; header.* = metadata
// (materials, bones, bindPose, stitches, morphs, bounds, stats...).

const TYPES = {
  f32: Float32Array, u16: Uint16Array, u32: Uint32Array, i16: Int16Array, u8: Uint8Array, i8: Int8Array,
};
const typeName = (arr) => {
  for (const [k, T] of Object.entries(TYPES)) if (arr instanceof T) return k;
  throw new Error('bakedFormat: unsupported array type');
};

export function encodeBaked(header, buffers) {
  const list = [];
  let off = 0;
  for (const [name, b] of Object.entries(buffers)) {
    const arr = b.array || b;
    const byteLength = arr.byteLength;
    list.push({ name, type: typeName(arr), count: arr.length / (b.itemSize || 1), itemSize: b.itemSize || 1, offset: off, byteLength, normalized: !!b.normalized });
    off += Math.ceil(byteLength / 4) * 4;
  }
  const h = { ...header, buffers: list };
  const json = new TextEncoder().encode(JSON.stringify(h));
  const hb = Math.ceil(json.length / 4) * 4;
  const total = 8 + hb + off;
  const out = new Uint8Array(total);
  out.set([68, 65, 67, 49], 0); // DAC1
  new DataView(out.buffer).setUint32(4, hb, true);
  out.set(json, 8);
  for (let i = json.length; i < hb; i++) out[8 + i] = 32;
  const base = 8 + hb;
  for (const e of list) {
    const b = buffers[e.name];
    const arr = b.array || b;
    out.set(new Uint8Array(arr.buffer, arr.byteOffset, arr.byteLength), base + e.offset);
  }
  return out;
}

export function decodeBaked(u8) {
  if (u8[0] !== 68 || u8[1] !== 65 || u8[2] !== 67 || u8[3] !== 49) throw new Error('bakedFormat: bad magic');
  const dv = new DataView(u8.buffer, u8.byteOffset, u8.byteLength);
  const hb = dv.getUint32(4, true);
  const header = JSON.parse(new TextDecoder().decode(u8.subarray(8, 8 + hb)));
  const base = u8.byteOffset + 8 + hb;
  // Copy into an aligned buffer (esbuild's binary loader gives an arbitrary offset).
  const body = new Uint8Array(u8.byteLength - 8 - hb);
  body.set(new Uint8Array(u8.buffer, base, body.length));
  const arrays = {};
  for (const e of header.buffers) {
    const T = TYPES[e.type];
    arrays[e.name] = { array: new T(body.buffer, e.offset, e.byteLength / T.BYTES_PER_ELEMENT), itemSize: e.itemSize, normalized: e.normalized };
  }
  return { header, arrays };
}
