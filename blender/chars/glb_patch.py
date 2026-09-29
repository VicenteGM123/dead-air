"""GLB post-pass for character meshes (FORMAT.md §4): the Blender glTF exporter reorders vertices and cannot write
our per-vertex channels / morph normals exactly, so after export the body and part primitives are rewritten from
the bake arrays. Each Blender vertex carries its original index in the UV map `vid` (exported as TEXCOORD_0).

    patch_glb(path, meshes)   meshes: {gltf mesh name: O(data=per-vertex dict, morphs=[(name, dp, dn)])}
meshes[name].index (optional): the bake triangle list (original vertex ids), written as the primitive's indices.
per-vertex dict keys: NORMAL (n,3) f32, COLOR_0 (n,4) f32, TEXCOORD_0..7 (n,2) f32 (indexed by ORIGINAL vertex).
"""
import json
import struct
import numpy as np

CT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NC = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}


def read_glb(path):
    with open(path, 'rb') as f:
        data = f.read()
    magic, ver, length = struct.unpack('<III', data[:12])
    assert magic == 0x46546C67
    off = 12
    js = None
    binc = b''
    while off < length:
        clen, ctype = struct.unpack('<II', data[off:off + 8])
        chunk = data[off + 8:off + 8 + clen]
        if ctype == 0x4E4F534A:
            js = json.loads(chunk.decode('utf-8'))
        elif ctype == 0x004E4942:
            binc = chunk
        off += 8 + clen
    return js, bytearray(binc)


def write_glb(path, js, binc):
    jb = json.dumps(js, separators=(',', ':')).encode('utf-8')
    jb += b' ' * ((-len(jb)) % 4)
    bb = bytes(binc) + b'\0' * ((-len(binc)) % 4)
    total = 12 + 8 + len(jb) + 8 + len(bb)
    with open(path, 'wb') as f:
        f.write(struct.pack('<III', 0x46546C67, 2, total))
        f.write(struct.pack('<II', len(jb), 0x4E4F534A))
        f.write(jb)
        f.write(struct.pack('<II', len(bb), 0x004E4942))
        f.write(bb)


def read_accessor(js, binc, ai):
    a = js['accessors'][ai]
    bv = js['bufferViews'][a['bufferView']]
    dt = np.dtype(CT[a['componentType']])
    nc = NC[a['type']]
    off = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
    stride = bv.get('byteStride', 0)
    cnt = a['count']
    if stride and stride != nc * dt.itemsize:
        raw = np.frombuffer(bytes(binc[off:off + stride * cnt]), np.uint8).reshape(cnt, stride)[:, :nc * dt.itemsize]
        arr = np.frombuffer(raw.tobytes(), dt).reshape(cnt, nc)
    else:
        arr = np.frombuffer(bytes(binc[off:off + cnt * nc * dt.itemsize]), dt).reshape(cnt, nc)
    return arr


class _Writer:
    def __init__(self, js, binc):
        self.js = js
        self.bin = binc

    def add(self, arr, typ, target=34962, minmax=False):
        arr = np.ascontiguousarray(arr)
        pad = (-len(self.bin)) % 4
        self.bin += b'\0' * pad
        off = len(self.bin)
        self.bin += arr.tobytes()
        self.js['bufferViews'].append({'buffer': 0, 'byteOffset': off, 'byteLength': arr.nbytes, 'target': target})
        ct = {np.dtype(np.float32): 5126, np.dtype(np.uint8): 5121, np.dtype(np.uint16): 5123, np.dtype(np.uint32): 5125}[arr.dtype]
        acc = {'bufferView': len(self.js['bufferViews']) - 1, 'componentType': ct, 'count': int(arr.shape[0]), 'type': typ}
        if minmax:
            acc['min'] = [float(v) for v in arr.reshape(arr.shape[0], -1).min(0)]
            acc['max'] = [float(v) for v in arr.reshape(arr.shape[0], -1).max(0)]
        self.js['accessors'].append(acc)
        return len(self.js['accessors']) - 1


def _compact(js, binc):
    """Drop unused accessors / bufferViews and rebuild the binary chunk."""
    used = set()
    for m in js.get('meshes', []):
        for p in m['primitives']:
            used.update(p['attributes'].values())
            if 'indices' in p:
                used.add(p['indices'])
            for t in p.get('targets', []):
                used.update(t.values())
    for s in js.get('skins', []):
        if 'inverseBindMatrices' in s:
            used.add(s['inverseBindMatrices'])
    for a in js.get('animations', []):
        for smp in a['samplers']:
            used.add(smp['input'])
            used.add(smp['output'])
    amap = {}
    accs = []
    for i, a in enumerate(js['accessors']):
        if i in used:
            amap[i] = len(accs)
            accs.append(a)
    usedv = set(a['bufferView'] for a in accs if 'bufferView' in a)
    for img in js.get('images', []):
        if 'bufferView' in img:
            usedv.add(img['bufferView'])
    vmap = {}
    views = []
    nb = bytearray()
    for i, v in enumerate(js['bufferViews']):
        if i not in usedv:
            continue
        nb += b'\0' * ((-len(nb)) % 8)
        off = v.get('byteOffset', 0)
        chunk = binc[off:off + v['byteLength']]
        v2 = dict(v)
        v2['byteOffset'] = len(nb)
        nb += chunk
        vmap[i] = len(views)
        views.append(v2)
    for a in accs:
        if 'bufferView' in a:
            a['bufferView'] = vmap[a['bufferView']]
    for img in js.get('images', []):
        if 'bufferView' in img:
            img['bufferView'] = vmap[img['bufferView']]
    for m in js.get('meshes', []):
        for p in m['primitives']:
            p['attributes'] = {k: amap[v] for k, v in p['attributes'].items()}
            if 'indices' in p:
                p['indices'] = amap[p['indices']]
            if 'targets' in p:
                p['targets'] = [{k: amap[v] for k, v in t.items()} for t in p['targets']]
    for s in js.get('skins', []):
        if 'inverseBindMatrices' in s:
            s['inverseBindMatrices'] = amap[s['inverseBindMatrices']]
    for a in js.get('animations', []):
        for smp in a['samplers']:
            smp['input'] = amap[smp['input']]
            smp['output'] = amap[smp['output']]
    js['accessors'] = accs
    js['bufferViews'] = views
    js['buffers'] = [{'byteLength': len(nb)}]
    return nb


def patch_glb(path, meshes):
    js, binc = read_glb(path)
    W = _Writer(js, binc)
    done = []
    for m in js.get('meshes', []):
        spec = meshes.get(m.get('name'))
        if spec is None:
            continue
        for p in m['primitives']:
            at = p['attributes']
            if 'TEXCOORD_0' not in at:
                raise RuntimeError('glb_patch: mesh %s has no vid channel' % m.get('name'))
            vid = read_accessor(js, W.bin, at['TEXCOORD_0'])[:, 0]
            ids = np.floor(vid.astype(np.float64) + 0.5).astype(np.int64)
            newat = {}
            for k in ('POSITION', 'JOINTS_0', 'WEIGHTS_0'):
                if k in at:
                    newat[k] = at[k]
            D = spec['data']
            newat['NORMAL'] = W.add(D['NORMAL'][ids].astype(np.float32), 'VEC3')
            newat['COLOR_0'] = W.add(D['COLOR_0'][ids].astype(np.float32), 'VEC4')
            for c in range(8):
                k = 'TEXCOORD_%d' % c
                newat[k] = W.add(D[k][ids].astype(np.float32), 'VEC2')
            p['attributes'] = newat
            if spec.get('index') is not None and len(m['primitives']) == 1:
                # the exact bake triangle list (JS order): Blender merges duplicate faces (meshopt leaves back-to-back
                # twin triangles where a thin sheet collapsed: collars, lapels, hair tips), which opened holes.
                # Any exported copy of an original vertex carries the same data (all channels come from `ids`).
                inv = np.full(int(ids.max()) + 1 if len(ids) else 0, -1, np.int64)
                inv[ids[::-1]] = np.arange(len(ids))[::-1]
                bi = np.asarray(spec['index'], np.int64).reshape(-1)
                if bi.size and bi.max() < len(inv) and (inv[bi] >= 0).all():
                    p['indices'] = W.add(inv[bi].astype(np.uint32), 'SCALAR', target=34963)
                else:
                    print('[glb_patch] %s: bake index not representable, keeping the exported one' % m.get('name'))
            if spec.get('morphs'):
                targets = []
                for (name, dp, dn) in spec['morphs']:
                    targets.append({'POSITION': W.add(dp[ids].astype(np.float32), 'VEC3', minmax=True),
                                    'NORMAL': W.add(dn[ids].astype(np.float32), 'VEC3')})
                p['targets'] = targets
                m['weights'] = [0.0] * len(targets)
                m.setdefault('extras', {})['targetNames'] = [t[0] for t in spec['morphs']]
            elif 'targets' in p:
                del p['targets']
        done.append(m.get('name'))
    nb = _compact(js, W.bin)
    write_glb(path, js, nb)
    return done
