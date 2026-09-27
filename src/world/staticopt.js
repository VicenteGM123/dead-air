// Static render optimizations run once on a dressed + merged area root (perf pass; level.js calls them).
//
// buildShadowProxies(root) -> Mesh[]
//   Every static shadow caster under `root` (the geo.mergeByMaterial eligibility: no userData.noMerge / dynamic on it
//   or an ancestor, no children, not instanced / skinned / morphing, one material) whose depth render is plain
//   (no alphaTest map, alphaToCoverage, displacement, clipping, custom depth material, wireframe) is copied into one
//   position-only mesh per effective shadow side, and stops casting itself. The proxies are invisible: level.js
//   shows them only while the key light's shadow map renders (render.addMainHook shadow() -> after()), so the main
//   camera and the feed cameras never draw them. Same depth image as before, 1-3 shadow draws per area instead of
//   one per caster (~100-200 in a dressed room), and cast / non-cast copies of a material can now merge.

import * as THREE from 'three';

const SHADOW_SIDE = { [THREE.FrontSide]: THREE.BackSide, [THREE.BackSide]: THREE.FrontSide, [THREE.DoubleSide]: THREE.DoubleSide };
const _inv = new THREE.Matrix4();
const _m = new THREE.Matrix4();
const _v = new THREE.Vector3();

function blocked(o, root) {
  for (let p = o; p && p !== root; p = p.parent) if (p.userData.dynamic || p.userData.noMerge) return true;
  return false;
}

function plainDepth(o) {
  const m = o.material;
  if (!m || Array.isArray(m) || !m.visible || m.wireframe) return false;
  if (o.customDepthMaterial || o.customDistanceMaterial) return false;
  if (m.alphaTest > 0 && (m.map || m.alphaMap)) return false;
  if (m.alphaToCoverage) return false;
  if (m.displacementMap && m.displacementScale !== 0) return false;
  if (Array.isArray(m.clippingPlanes) && m.clippingPlanes.length) return false;
  return true;
}

export function buildShadowProxies(root) {
  root.updateMatrixWorld(true);
  _inv.copy(root.matrixWorld).invert();
  const bySide = new Map();
  root.traverse((o) => {
    if (o === root || !o.isMesh || !o.castShadow || !o.visible) return;
    if (o.isInstancedMesh || o.isSkinnedMesh || o.isBatchedMesh || o.morphTargetInfluences || o.children.length) return;
    if (o.userData.shadowProxy || blocked(o, root) || !plainDepth(o)) return;
    const pos = o.geometry && o.geometry.attributes.position;
    if (!pos) return;
    for (let p = o.parent; p && p !== root; p = p.parent) if (!p.visible) return;
    const m = o.material;
    const side = m.shadowSide !== null && m.shadowSide !== undefined ? m.shadowSide : SHADOW_SIDE[m.side];
    let list = bySide.get(side);
    if (!list) bySide.set(side, (list = []));
    list.push(o);
  });
  const out = [];
  for (const [side, list] of bySide) {
    let nv = 0, ni = 0;
    for (const o of list) {
      const g = o.geometry;
      nv += g.attributes.position.count;
      ni += g.index ? g.index.count : g.attributes.position.count;
    }
    const P = new Float32Array(nv * 3);
    const I = nv > 65535 ? new Uint32Array(ni) : new Uint16Array(ni);
    let vb = 0, ib = 0;
    for (const o of list) {
      const g = o.geometry, pos = g.attributes.position, n = pos.count;
      _m.multiplyMatrices(_inv, o.matrixWorld);
      for (let i = 0; i < n; i++) {
        _v.fromBufferAttribute(pos, i).applyMatrix4(_m);
        P[(vb + i) * 3] = _v.x; P[(vb + i) * 3 + 1] = _v.y; P[(vb + i) * 3 + 2] = _v.z;
      }
      const flip = _m.determinant() < 0; // mirrored: keep the winding the source had in world space
      const idx = g.index;
      const cnt = idx ? idx.count : n;
      for (let i = 0; i < cnt; i += 3) {
        const a = idx ? idx.getX(i) : i, b = idx ? idx.getX(i + 1) : i + 1, c = idx ? idx.getX(i + 2) : i + 2;
        I[ib++] = vb + a;
        I[ib++] = vb + (flip ? c : b);
        I[ib++] = vb + (flip ? b : c);
      }
      vb += n;
      o.castShadow = false;
    }
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.BufferAttribute(P, 3));
    geo.setIndex(new THREE.BufferAttribute(I.subarray(0, ib), 1));
    geo.computeBoundingSphere();
    geo.computeBoundingBox();
    const mat = new THREE.MeshBasicMaterial({ colorWrite: false, depthWrite: false });
    mat.side = THREE.FrontSide;
    mat.shadowSide = side;
    const proxy = new THREE.Mesh(geo, mat);
    proxy.name = 'shadowProxy';
    proxy.castShadow = true;
    proxy.receiveShadow = false;
    proxy.visible = false;
    proxy.userData.shadowProxy = true;
    proxy.userData.noMerge = true;
    proxy.userData.sources = list.length;
    root.add(proxy);
    proxy.updateMatrixWorld(true);
    out.push(proxy);
  }
  return out;
}

// bakeMaterialColors(game, roots) -> { meshes, before, after } (distinct toon materials on those meshes)
//   Static opaque toon meshes under `roots` (the merge eligibility) get their material colour multiplied into a
//   vertex colour attribute and switch to the same toon params with colour white + vertexColors. The shader computes
//   diffuse = colour x map x vColor before any lighting, so the product is the same (float rounding aside), but
//   meshes that differed only by colour now share one cached material, and the next geo.mergeByMaterial() draws
//   an area's props of one finish (lacquer, vinyl, chrome...) in one call instead of one per colour.
const _col = new THREE.Color();

function bakeable(o, root) {
  if (!o.isMesh || o.isInstancedMesh || o.isSkinnedMesh || o.isBatchedMesh || o.morphTargetInfluences || o.children.length) return false;
  if (o.userData.shadowProxy || blocked(o, root)) return false;
  const m = o.material;
  if (!m || Array.isArray(m) || !m.userData.daToon || m.transparent || !m.visible) return false;
  const pos = o.geometry && o.geometry.attributes.position;
  if (!pos || !pos.count) return false;
  const c = o.geometry.attributes.color;
  if (c && c.itemSize !== 3) return false;
  if (!c && m.vertexColors) return false; // three would read a missing attribute as black: leave it alone
  return true;
}

export function bakeMaterialColors(game, roots) {
  const list = [];
  const users = new Map(); // geometry -> mesh count (shared geometries are cloned before baking)
  for (const root of roots) {
    root.traverse((o) => {
      if (o.isMesh && o.geometry) users.set(o.geometry, (users.get(o.geometry) || 0) + 1);
      if (!bakeable(o, root)) return;
      for (let p = o.parent; p && p !== root; p = p.parent) if (!p.visible) return;
      list.push(o);
    });
  }
  const before = new Set(list.map((o) => o.material)).size;
  const clones = new Map();
  const after = new Set();
  for (const o of list) {
    const m = o.material, d = m.userData.daToon;
    _col.copy(m.color);
    const white = _col.r === 1 && _col.g === 1 && _col.b === 1;
    if (white && m.vertexColors) { after.add(m); continue; }
    const key = o.geometry.uuid + '|' + _col.getHexString(THREE.LinearSRGBColorSpace) + '|' + m.vertexColors;
    let g = clones.get(key);
    if (!g) {
      const s = o.geometry;
      const src = m.vertexColors ? s.attributes.color : null;
      if (users.get(s) > 1) {
        // shared geometry: a shallow copy (same attribute buffers) that only gets its own colour attribute
        g = new THREE.BufferGeometry();
        for (const k in s.attributes) if (k !== 'color') g.setAttribute(k, s.attributes[k]);
        g.setIndex(s.index);
        for (const gr of s.groups) g.addGroup(gr.start, gr.count, gr.materialIndex);
        g.drawRange = { ...s.drawRange };
        if (s.boundingSphere) g.boundingSphere = s.boundingSphere.clone();
        if (s.boundingBox) g.boundingBox = s.boundingBox.clone();
      } else g = s;
      const n = g.attributes.position.count;
      const arr = new Float32Array(n * 3);
      for (let i = 0; i < n; i++) {
        const r = src ? src.getX(i) : 1, gg = src ? src.getY(i) : 1, b = src ? src.getZ(i) : 1;
        arr[i * 3] = r * _col.r; arr[i * 3 + 1] = gg * _col.g; arr[i * 3 + 2] = b * _col.b;
      }
      g.setAttribute('color', new THREE.BufferAttribute(arr, 3));
      clones.set(key, g);
    }
    o.geometry = g;
    const nm = game.mats.toon('#ffffff', { ...d.params, vertexColors: true });
    o.material = nm;
    after.add(nm);
  }
  return { meshes: list.length, before, after: after.size };
}


// ================================================================================================ area batches
// buildAreaBatches(game, roots:{areaId: Group}, opts) -> AreaBatches | null   (buildAreaBatchesSteps(..., out) is
//   the same as a step generator for the progressive boot: yields after the texture arrays and after each area)
//   opts: { keep=false (keep the baked originals, hidden, so setEnabled() is a complete A/B toggle),
//           follow=true (also batch the followed objects, see below) }
//   Retained batching of every opaque toon mesh of the areas (props pass). The static merged meshes AND the meshes
//   the merge could not take (animated / switchable noMerge parts, one-off textured props, ceilings) of one area are
//   drawn by a few "batch" meshes, grouped only by the state that changes the shader or the pipeline (side, flat,
//   defines, fog, depth state, texture size / sampler class, receiveShadow, layers, renderOrder):
//   - every per-material value three would upload as a uniform (colour, roughness, metalness, emissive x intensity,
//     envMap intensity, the toon wrap / steps / rim strength, power and colour, keepColor, fog:false, visibility,
//     the map's uv transform and its texture layer) is a row of a small float table the vertex shader reads (flat
//     varyings): the fragment math is the toon material's (materials.js), with the same float32 inputs;
//   - canvas textures go into texture arrays (one per size + sampler state; each canvas is uploaded straight into
//     its layer with the pixel-store state three uses for it, flipY included, and mipmapped the same way): hardware
//     REPEAT / CLAMP, mip selection and anisotropy work per layer exactly as on the source texture;
//   - "baked" objects (merged:* / batch:* static pipeline meshes that do not cast) are copied in area space and their
//     vertices address their material row directly; every other mesh ("followed") keeps its own geometry and gets an
//     object row (area-relative world matrix, normal matrix, material row, visible, castShadow) re-synced from the
//     original Object3D right before any batch mesh of the area draws (onBeforeRender / onBeforeShadow, once per
//     scene render). The original stays in the scene graph (gameplay code still moves, hides, re-materials, raycasts
//     and clones it): its `layers` become a HiddenLayers that no camera matches while the renderer draws.
//   Anything the batch cannot follow (geometry swapped or edited, layers changed, a material swap to a non-batchable
//   or other-class material, a texture redrawn too often or resized, the object moved under another root) drops that
//   object out of the batch for good: its row is hidden and the original draws itself again, as before this pass.
//   Batch meshes with followed casters carry a customDepthMaterial doing the same row transform + visibility; the
//   shadow pass draws only their followed range (the baked part never casts: shadow proxies do).
//   AreaBatches: { areas:{id -> AreaBatch}, stats, dropped, update() (per frame: re-uploads array layers whose source
//   canvas was redrawn), setEnabled(on) (A/B toggle; complete only with keep) }
const NOOP_BR = THREE.Object3D.prototype.onBeforeRender;
const NOOP_AR = THREE.Object3D.prototype.onAfterRender;
const NOOP_BS = THREE.Object3D.prototype.onBeforeShadow;
const NOOP_AS = THREE.Object3D.prototype.onAfterShadow;
const OBJ_W = 8;      // texels per object row: M columns 0-3, normal matrix columns 4-6, flags 7 (matRow, visible, cast)
const MAT_W = 8;      // texels per material row (see writeMatRow)
const MAT_SPARE = 48; // material rows kept free per area for runtime material swaps
const TEX_LIVE = 6;   // a source canvas redrawn more often than this after the build is "live": its followed users leave
const ORDER_TRIES = 300; // syncs to wait for the originals' programs (boot precompile) before ordering without them
const _rel = new THREE.Matrix4();
const _nm = new THREE.Matrix3();
const _sph = new THREE.Sphere();
const _vv = new THREE.Vector3();
const _row = new Float32Array(MAT_W * 4);

// > 0 while WebGLRenderer.render() runs (main pass, shadow maps, feeds, warm draws): HiddenLayers.test() is false then.
let RENDERING = 0;
function hookRenderer(r) {
  if (r.__daBatchHook) return;
  r.__daBatchHook = true;
  const render = r.render;
  r.render = function (scene, camera) {
    RENDERING++;
    try {
      return render.call(this, scene, camera);
    } finally {
      RENDERING--;
    }
  };
}

// Layers of a batched original: no camera matches it while the renderer draws (projection and shadow maps skip it,
// its batch draws it), raycasts and clones see the real channels (mask), and any write to it flags the object so its
// batch lets it go (the new layers apply to the original from then on).
class HiddenLayers extends THREE.Layers {
  constructor(mask) {
    super();
    this._m = mask | 0;
    this.changed = false;
    this.daHidden = true;
  }

  get mask() { return this._m; }

  set mask(v) {
    if (this.daHidden !== true) { this._m = v | 0; return; } // Layers' constructor
    if ((v | 0) !== this._m) { this._m = v | 0; this.changed = true; }
  }

  test(layers) { return RENDERING === 0 && (this._m & layers.mask) !== 0; }
}

// How three colours a followed object's vertices: 0 = its colour attribute (vertexColors material), 1 = white
// (material without vertexColors), 2 = black (vertexColors material on a geometry without colours: the attribute is
// disabled and reads WebGL's default generic value 0,0,0).
function vcMode(m, g) {
  return !m.vertexColors ? 1 : g.attributes.color ? 0 : 2;
}

function plainLayers(mask) {
  const l = new THREE.Layers();
  l.mask = mask;
  return l;
}

function effVisible(o, root) {
  for (let p = o; p && p !== root; p = p.parent) if (!p.visible) return false;
  return true;
}

function texOK(t) {
  if (!t || t.isRenderTargetTexture || t.isVideoTexture || t.isDataTexture || t.isCompressedTexture || t.isCubeTexture) return false;
  if (t.isDataArrayTexture || t.isData3DTexture || t.isDepthTexture || t.isFramebufferTexture) return false;
  const img = t.image;
  if (!img || !(img.width > 0 && img.height > 0) || img.width > 4096 || img.height > 4096) return false;
  const dom = (typeof HTMLCanvasElement !== 'undefined' && img instanceof HTMLCanvasElement)
    || (typeof HTMLImageElement !== 'undefined' && img instanceof HTMLImageElement && img.complete);
  if (!dom) return false;
  if (t.channel !== 0 || t.format !== THREE.RGBAFormat || t.type !== THREE.UnsignedByteType || t.internalFormat) return false;
  if (t.mipmaps && t.mipmaps.length) return false;
  return true;
}

// Sampler + storage state shared by one texture array (per-upload pixel-store state is set per layer).
function texClass(t) {
  return [t.image.width, t.image.height, t.wrapS, t.wrapT, t.magFilter, t.minFilter, t.anisotropy, t.generateMipmaps, t.colorSpace].join(',');
}

// An opaque toon material (materials.js toon program) whose state the batch shader reproduces.
function plainToon(m, envMap, toonKey) {
  if (!m || Array.isArray(m) || !m.isMeshStandardMaterial || m.isMeshPhysicalMaterial || !m.userData.daToon || !m.userData.uniforms) return false;
  if (m.customProgramCacheKey !== toonKey) return false;
  const u = m.userData.uniforms;
  if (!u.uWrap || !u.uSteps || !u.uRimStrength || !u.uRimPower || !u.uRimColor || !u.uKeep || !u.uFogK) return false;
  if (m.transparent || m.alphaTest > 0 || m.alphaToCoverage || m.alphaHash || m.wireframe || m.blending !== THREE.NormalBlending) return false;
  if (!m.depthTest || !m.colorWrite || m.stencilWrite || (m.clippingPlanes && m.clippingPlanes.length)) return false;
  if (m.normalMap || m.bumpMap || m.displacementMap || m.emissiveMap || m.aoMap || m.lightMap || m.alphaMap || m.roughnessMap || m.metalnessMap) return false;
  if (m.envMap && m.envMap !== envMap) return false;
  if (m.map && !texOK(m.map)) return false;
  return true;
}

// Program / pipeline state of a material: batch members must agree on all of it.
function matKey(m) {
  return [m.side, m.shadowSide, m.flatShading, JSON.stringify(m.defines || {}), m.fog, !!m.envMap, m.depthWrite, m.depthFunc,
    m.polygonOffset ? `${m.polygonOffsetFactor}/${m.polygonOffsetUnits}` : 0, m.toneMapped, m.dithering, m.premultipliedAlpha,
    m.map ? texClass(m.map) : '-'].join('|');
}

// ---- texture arrays (one per texClass; layers = every source texture of that class)
class TexArrays {
  constructor(renderer) {
    this.r = renderer;
    this.classes = new Map();
    this.layers = new Map(); // source texture -> { c, index }
    this.leave = new Set();  // source textures whose followed users must leave (resized / live)
    this.frame = -1;
    this.reuploads = 0;
  }

  plan(t) {
    if (this.layers.has(t)) return;
    const k = texClass(t);
    let c = this.classes.get(k);
    if (!c) this.classes.set(k, (c = { key: k, list: [], tex: null, mips: false }));
    this.layers.set(t, { c, index: c.list.length });
    c.list.push({ t, ver: -1, n: 0 });
  }

  build() {
    for (const c of this.classes.values()) if (!c.tex) this._alloc(c);
  }

  _alloc(c) {
    const t0 = c.list[0].t;
    const a = new THREE.DataArrayTexture(null, t0.image.width, t0.image.height, c.list.length);
    a.format = THREE.RGBAFormat;
    a.type = THREE.UnsignedByteType;
    a.colorSpace = t0.colorSpace;
    a.wrapS = t0.wrapS; a.wrapT = t0.wrapT;
    a.magFilter = t0.magFilter; a.minFilter = t0.minFilter;
    a.anisotropy = t0.anisotropy;
    a.generateMipmaps = t0.generateMipmaps;
    a.flipY = false; a.premultiplyAlpha = false; a.unpackAlignment = 4;
    a.name = `abatch:array:${c.key}`;
    a.source.dataReady = false; // three allocates the storage (texStorage3D, full mip chain); layers are uploaded here
    a.needsUpdate = true;
    this.r.initTexture(a);
    c.tex = a;
    c.mips = a.generateMipmaps && a.minFilter !== THREE.NearestFilter && a.minFilter !== THREE.LinearFilter;
    for (let i = 0; i < c.list.length; i++) this._upload(c, i);
    this._mipmap(c);
  }

  // Same pixel-store state three uses for the source texture (WebGLTextures.uploadTexture), into layer i.
  _upload(c, i) {
    const r = this.r, gl = r.getContext(), st = r.state, e = c.list[i], t = e.t, img = t.image;
    st.bindTexture(gl.TEXTURE_2D_ARRAY, r.properties.get(c.tex).__webglTexture, gl.TEXTURE0);
    const CM = THREE.ColorManagement;
    const conv = t.colorSpace === THREE.NoColorSpace || CM.getPrimaries(CM.workingColorSpace) === CM.getPrimaries(t.colorSpace) ? gl.NONE : gl.BROWSER_DEFAULT_WEBGL;
    st.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, t.flipY);
    st.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, t.premultiplyAlpha);
    st.pixelStorei(gl.UNPACK_COLORSPACE_CONVERSION_WEBGL, conv);
    st.pixelStorei(gl.UNPACK_ALIGNMENT, t.unpackAlignment);
    st.pixelStorei(gl.UNPACK_ROW_LENGTH, 0);
    st.pixelStorei(gl.UNPACK_IMAGE_HEIGHT, 0);
    st.pixelStorei(gl.UNPACK_SKIP_PIXELS, 0);
    st.pixelStorei(gl.UNPACK_SKIP_ROWS, 0);
    st.pixelStorei(gl.UNPACK_SKIP_IMAGES, 0);
    gl.texSubImage3D(gl.TEXTURE_2D_ARRAY, 0, 0, 0, i, img.width, img.height, 1, gl.RGBA, gl.UNSIGNED_BYTE, img);
    e.ver = t.version;
  }

  _mipmap(c) {
    if (!c.mips) return;
    const r = this.r, gl = r.getContext();
    r.state.bindTexture(gl.TEXTURE_2D_ARRAY, r.properties.get(c.tex).__webglTexture, gl.TEXTURE0);
    gl.generateMipmap(gl.TEXTURE_2D_ARRAY);
  }

  // A source canvas redrawn (needsUpdate -> version++): upload its layer again (once per renderer frame at most).
  // Resized sources and sources redrawn more than TEX_LIVE times join `leave` (their followed users go back to
  // drawing themselves; baked users keep this refresh).
  refresh(frame) {
    if (frame === this.frame) return 0;
    this.frame = frame;
    let n = 0;
    for (const c of this.classes.values()) {
      if (!c.tex) continue;
      let dirty = false;
      for (let i = 0; i < c.list.length; i++) {
        const e = c.list[i];
        if (e.t.version === e.ver) continue;
        const img = e.t.image;
        if (!img || img.width !== c.tex.image.width || img.height !== c.tex.image.height) {
          e.ver = e.t.version;
          this.leave.add(e.t);
          continue;
        }
        if (++e.n > TEX_LIVE) this.leave.add(e.t);
        this._upload(c, i);
        dirty = true;
        n++;
      }
      if (dirty) this._mipmap(c);
    }
    this.reuploads += n;
    return n;
  }
}

// ---- shaders
const VERT_PARS = /* glsl */`
attribute float daObj;
uniform highp sampler2D uDaObj;
uniform highp sampler2D uDaMat;
flat varying vec4 vDaP0;
flat varying vec4 vDaP1;
flat varying vec4 vDaRim;
flat varying vec4 vDaEm;
flat varying vec4 vDaCol;
#ifdef DA_MAP
varying vec2 vDaUv;
#endif`;

// daObj < 0: a baked vertex whose material row is -daObj - 1 (area space, always shown); else a followed object row.
const VERT_FETCH = /* glsl */`
int daK;
float daVc = 0.0;
mat4 daM = mat4( 1.0 );
mat3 daN = mat3( 1.0 );
bool daHide = false;
if ( daObj < -0.5 ) {
  daK = int( - daObj - 0.5 );
} else {
  int daO = int( daObj + 0.5 );
  daM = mat4( texelFetch( uDaObj, ivec2( 0, daO ), 0 ), texelFetch( uDaObj, ivec2( 1, daO ), 0 ),
    texelFetch( uDaObj, ivec2( 2, daO ), 0 ), texelFetch( uDaObj, ivec2( 3, daO ), 0 ) );
  daN = mat3( texelFetch( uDaObj, ivec2( 4, daO ), 0 ).xyz, texelFetch( uDaObj, ivec2( 5, daO ), 0 ).xyz,
    texelFetch( uDaObj, ivec2( 6, daO ), 0 ).xyz );
  vec4 daF = texelFetch( uDaObj, ivec2( 7, daO ), 0 );
  daK = int( daF.x + 0.5 );
  daHide = daF.y < 0.5;
  daVc = daF.w;
}
vDaP0 = texelFetch( uDaMat, ivec2( 0, daK ), 0 );
vDaP1 = texelFetch( uDaMat, ivec2( 1, daK ), 0 );
vec4 daT2 = texelFetch( uDaMat, ivec2( 2, daK ), 0 );
vDaRim = vec4( daT2.rgb, floor( daT2.a * 0.5 + 0.25 ) );
vDaEm = texelFetch( uDaMat, ivec2( 3, daK ), 0 );
vDaCol = texelFetch( uDaMat, ivec2( 4, daK ), 0 );
daHide = daHide || mod( daT2.a, 2.0 ) < 0.5;
#ifdef DA_MAP
mat3 daUvT = mat3( texelFetch( uDaMat, ivec2( 5, daK ), 0 ).xyz, texelFetch( uDaMat, ivec2( 6, daK ), 0 ).xyz,
  texelFetch( uDaMat, ivec2( 7, daK ), 0 ).xyz );
vDaUv = ( daUvT * vec3( uv, 1.0 ) ).xy;
#endif`;

const FRAG_PARS_B = /* glsl */`
flat varying vec4 vDaP0;
flat varying vec4 vDaP1;
flat varying vec4 vDaRim;
flat varying vec4 vDaEm;
flat varying vec4 vDaCol;
#define uWrap vDaP0.w
#define uSteps vDaP1.x
#define uRimStrength vDaP1.y
#define uRimPower vDaP1.z
#define uRimColor vDaRim.rgb
#define uDaFade vDaRim.w
#define uKeep vDaEm.w
#define uFogK vDaCol.w
#ifdef DA_MAP
uniform highp sampler2DArray uDaMap;
varying vec2 vDaUv;
#endif`;

const ENV_PARS_B = THREE.ShaderChunk.envmap_common_pars_fragment.replace('uniform float envMapIntensity;', '#define envMapIntensity vDaP0.z');

// [search, replacement] pairs applied after the toon patch; every search string must be found.
const VERT_EDITS = [
  ['varying vec3 vDaWorld;', `varying vec3 vDaWorld;\n${VERT_PARS}`],
  ['#include <uv_vertex>', `${VERT_FETCH}\n#include <uv_vertex>`],
  ['#include <color_vertex>', '#include <color_vertex>\nif ( daVc > 0.5 ) vColor.rgb = daVc > 1.5 ? vec3( 0.0 ) : vec3( 1.0 );'],
  ['#include <beginnormal_vertex>', '#include <beginnormal_vertex>\nobjectNormal = daN * objectNormal;'],
  ['#include <begin_vertex>', '#include <begin_vertex>\ntransformed = ( daM * vec4( transformed, 1.0 ) ).xyz;'],
  ['#include <fog_vertex>', '#include <fog_vertex>\nif ( daHide ) gl_Position = vec4( 2.0, 2.0, 2.0, 1.0 );'],
];
const FRAG_EDITS = [
  ['uniform float uWrap;', FRAG_PARS_B],
  ['uniform float uSteps;', ''],
  ['uniform float uRimStrength;', ''],
  ['uniform float uRimPower;', ''],
  ['uniform vec3 uRimColor;', ''],
  ['uniform float uKeep;', ''],
  ['uniform float uFogK;', ''],
  ['uniform float uDaFade;', '', true], // optional (materials.js hero / occlusion fade flag)
  ['vec4 diffuseColor = vec4( diffuse, opacity );', 'vec4 diffuseColor = vec4( vDaCol.rgb, opacity );'],
  ['#include <map_fragment>', '#include <map_fragment>\n#ifdef DA_MAP\n\tdiffuseColor *= texture( uDaMap, vec3( vDaUv, vDaP1.w ) );\n#endif'],
  ['#include <roughnessmap_fragment>', 'float roughnessFactor = vDaP0.x;'],
  ['#include <metalnessmap_fragment>', 'float metalnessFactor = vDaP0.y;'],
  ['vec3 totalEmissiveRadiance = emissive;', 'vec3 totalEmissiveRadiance = vDaEm.rgb;'],
  ['#include <envmap_common_pars_fragment>', ENV_PARS_B],
];
const DEPTH_EDITS = [
  ['#include <common>', '#include <common>\nattribute float daObj;\nuniform highp sampler2D uDaObj;\nuniform highp sampler2D uDaMat;'],
  ['#include <begin_vertex>', `#include <begin_vertex>
bool daHide = true;
if ( daObj > -0.5 ) {
  int daO = int( daObj + 0.5 );
  mat4 daM = mat4( texelFetch( uDaObj, ivec2( 0, daO ), 0 ), texelFetch( uDaObj, ivec2( 1, daO ), 0 ),
    texelFetch( uDaObj, ivec2( 2, daO ), 0 ), texelFetch( uDaObj, ivec2( 3, daO ), 0 ) );
  vec4 daF = texelFetch( uDaObj, ivec2( 7, daO ), 0 );
  daHide = daF.y < 0.5 || daF.z < 0.5 || mod( texelFetch( uDaMat, ivec2( 2, int( daF.x + 0.5 ) ), 0 ).a, 2.0 ) < 0.5;
  transformed = ( daM * vec4( transformed, 1.0 ) ).xyz;
}`],
  ['#include <clipping_planes_vertex>', '#include <clipping_planes_vertex>\nif ( daHide ) gl_Position = vec4( 2.0, 2.0, 2.0, 1.0 );'],
];

function applyEdits(src, edits, missing) {
  let s = src;
  for (const [a, b, optional] of edits) {
    if (!s.includes(a)) { if (!optional) missing.push(a); continue; }
    s = s.replace(a, b);
  }
  return s;
}

// Dry run of the toon + batch edits against three's physical / depth shaders (a three or materials.js change that
// moves an anchor disables batching instead of breaking the level).
function shaderCheck(game) {
  const probe = new THREE.MeshStandardMaterial();
  game.mats._patchToon(probe, { wrap: 0.5, steps: 0, rim: 0.3, rimPower: 2.4, rimColor: '#ffffff', keepColor: false, fog: true });
  const sh = { vertexShader: THREE.ShaderLib.physical.vertexShader, fragmentShader: THREE.ShaderLib.physical.fragmentShader, uniforms: {} };
  probe.onBeforeCompile(sh, game.renderer);
  const missing = [];
  applyEdits(sh.vertexShader, VERT_EDITS, missing);
  const fs = applyEdits(sh.fragmentShader, FRAG_EDITS, missing);
  applyEdits(THREE.ShaderLib.depth.vertexShader, DEPTH_EDITS, missing);
  // the toon patch must carry the IBL branch (envMapIntensity 0 = no environment lookups), the fog uniform and
  // every material uniform the rows replace
  if (!fs.includes('if ( envMapIntensity > 0.0 )')) missing.push('toon IBL branch');
  if (!fs.includes('uFogK')) missing.push('toon uFogK');
  for (const k of ['uWrap', 'uSteps', 'uRimStrength', 'uRimPower', 'uRimColor', 'uKeep', 'uFogK']) if (!sh.uniforms[k]) missing.push(`uniform ${k}`);
  probe.dispose();
  return missing;
}

// Material row: the values three would upload as uniforms for m (same float32 values).
function writeMatRow(m, layer, out) {
  const u = m.userData.uniforms;
  out[0] = m.roughness; out[1] = m.metalness; out[2] = m.envMap ? m.envMapIntensity : 0; out[3] = u.uWrap.value;
  out[4] = u.uSteps.value; out[5] = u.uRimStrength.value; out[6] = u.uRimPower.value; out[7] = layer;
  const rc = u.uRimColor.value;
  out[8] = rc.r; out[9] = rc.g; out[10] = rc.b; out[11] = (m.visible ? 1 : 0) + 2 * (u.uDaFade ? u.uDaFade.value : 0);
  const k = m.emissiveIntensity, e = m.emissive;
  out[12] = e.r * k; out[13] = e.g * k; out[14] = e.b * k; out[15] = u.uKeep.value;
  out[16] = m.color.r; out[17] = m.color.g; out[18] = m.color.b; out[19] = u.uFogK.value;
  const t = m.map;
  if (t) {
    if (t.matrixAutoUpdate) t.updateMatrix();
    const q = t.matrix.elements;
    out[20] = q[0]; out[21] = q[1]; out[22] = q[2]; out[23] = 0;
    out[24] = q[3]; out[25] = q[4]; out[26] = q[5]; out[27] = 0;
    out[28] = q[6]; out[29] = q[7]; out[30] = q[8]; out[31] = 0;
  } else {
    for (let i = 20; i < 32; i++) out[i] = 0;
  }
}

class AreaBatch {
  constructor(game, id, root, arrays, envMap, toonKey) {
    this.game = game;
    this.id = id;
    this.root = root;
    this.arrays = arrays;
    this.envMap = envMap;
    this.toonKey = toonKey;
    this.objs = [];        // followed: { o, hl, row, mat, me, batch, geo, vcm, vis, cast, rowMat, mw, det, vers, dead }
    this.live = [];        // followed objects still in the batch
    this.baked = [];       // baked originals kept for the A/B toggle (keep) [{ o, mask }]
    this.mats = new Map(); // material -> { m, row, cache, map, ver, key, cls, users, baked, bad }
    this.matList = [];
    this.batches = [];     // { key, matKey, cls, mesh, lStart, lCount }
    this.frame = -1;
    this.enabled = true;
    this.rootInv = new THREE.Matrix4();
    this.matCap = 0;
    this.dropped = 0;
    this.warned = false;
    this.keep = false;
    this.ordered = false;
    this.orderTries = 0;
    this.verified = false;
    this.failed = false;
  }

  // Every batch program compiled and linked? (isReady: the parallel compile finished, non-blocking.) A program that
  // failed to link sends the whole area back to three (originals restored) instead of drawing garbage.
  verify() {
    const props = this.game.renderer.properties, gl = this.game.renderer.getContext();
    let pending = false;
    for (const b of this.batches) {
      const mats = [b.mesh.material];
      if (b.shadow) mats.push(b.shadow.customDepthMaterial);
      for (const m of mats) {
        const p = props.has(m) ? props.get(m).currentProgram : null;
        if (!p || !p.program || !p.isReady()) { if (m === b.mesh.material) pending = true; continue; }
        if (gl.getProgramParameter(p.program, gl.LINK_STATUS) === false) { this.fail(); return false; }
      }
    }
    return !pending;
  }

  fail() {
    if (this.failed) return;
    this.failed = true;
    this.enabled = false;
    console.warn(`[abatch:${this.id}] a batch shader failed: the area is drawn unbatched`);
    for (const b of this.batches) {
      b.mesh.visible = false;
      if (b.shadow) b.shadow.geometry.drawRange.count = 0;
    }
    for (const e of this.baked) e.o.layers = plainLayers(e.mask);
    this.baked.length = 0;
    for (const ob of this.live) if (!ob.dead && ob.o.layers === ob.hl) ob.o.layers = plainLayers(ob.hl._m);
  }

  // One-time, once the originals' materials have their programs (the boot precompile compiles every scene
  // material, hidden originals included): each batch's triangles are put in the order three drew the originals
  // (program id, then material id, then scene order), and each batch mesh sorts by its first member among the batches
  // (renderOrder of its class - 0.5 .. - 0.1, i.e. before the non-batched objects of that class, as the toon programs
  // came first). Coplanar surfaces then resolve their depth tie as before: three draws the opaque list by program,
  // then material, and with the LessEqual depth test the later draw wins. Then the baked originals leave the scene
  // (unless keep: they stay, hidden, for the A/B toggle).
  orderBatches() {
    const props = this.game.renderer.properties;
    const prog = (m) => { const p = m && props.has(m) ? props.get(m).currentProgram : null; return p ? p.id : -1; };
    let missing = 0;
    for (const b of this.batches) for (const it of b.items) { it.prog = prog(it.mat); if (it.prog < 0) missing++; }
    if (missing && ++this.orderTries < ORDER_TRIES) return;
    const P = (it) => (it.prog < 0 ? 1e6 : it.prog);
    const out = this.resolveTies(prog);
    for (const b of this.batches) {
      const items = b.items.filter((it) => !out.has(it)).sort((x, y) => (P(x) - P(y)) || (x.mat.id - y.mat.id) || (x.n - y.n));
      const geo = b.mesh.geometry, I = geo.index.array, src = I.slice();
      let k = 0;
      for (const it of items) { I.set(src.subarray(it.i0, it.i1), k); k += it.i1 - it.i0; }
      geo.index.needsUpdate = true;
      geo.drawRange.count = k < I.length ? k : Infinity;
      if (b.shadow) {
        const sg = b.shadow.geometry, S = sg.index.array, ss = S.slice();
        let q = 0;
        for (const it of items) if (it.s1 > it.s0) { S.set(ss.subarray(it.s0, it.s1), q); q += it.s1 - it.s0; }
        sg.index.needsUpdate = true;
        b.sCount = q < S.length ? q : Infinity;
        sg.drawRange.count = this.enabled ? b.sCount : 0;
      }
      let q = 0;
      for (const it of items) { const n = it.i1 - it.i0; it.i0 = q; it.i1 = q += n; }
      q = 0;
      for (const it of items) { const n = it.s1 - it.s0; it.s0 = q; it.s1 = q += n; }
      b.items = items;
      if (!items.length) { b.mesh.visible = false; continue; }
      const f = items[0];
      const key = Math.min(P(f), 999) * 1e6 + Math.min(f.mat.id, 999999);
      b.mesh.renderOrder = b.ro - 0.5 + 0.4 * key / 1e9;
    }
    if (!this.keep) {
      for (const e of this.baked) if (e.o.parent) e.o.parent.remove(e.o);
      this.baked.length = 0;
    }
    this.ties = null;
    this.ordered = true;
  }

  // Coplanar ties (findTies pairs): for every pair of objects whose triangles share a plane and overlap, three drew
  // the one with the lower (renderOrder, program, material id) first and the other won the depth tie. Kept as is when
  // both are in one batch (triangles in that order) or when the winner is drawn by three anyway (after every batch of
  // its class); otherwise the winner leaves its batch and is drawn by three as before. Returns the items that left.
  resolveTies(prog) {
    const out = new Set(), T = this.ties;
    if (!T || !T.pairs.length) return out;
    const objs = T.objs;
    for (const t of objs) t.prog = prog(t.mat);
    // a pair's depth tie is reproduced only between exact copies or objects three draws: the other participants leave
    for (const t of objs) if (t.item && t.self) out.add(t.item);
    for (let k = 0; k < T.pairs.length; k += 2) {
      for (const t of [objs[T.pairs[k]], objs[T.pairs[k + 1]]]) if (t.item && !t.exact) out.add(t.item);
    }
    const cmp = (a, b) => (a.ro - b.ro) || ((a.prog < 0 ? 1e6 : a.prog) - (b.prog < 0 ? 1e6 : b.prog)) || (a.mat.id - b.mat.id);
    let changed = true, guard = 0;
    while (changed && guard++ < 64) {
      changed = false;
      for (let k = 0; k < T.pairs.length; k += 2) {
        let a = objs[T.pairs[k]], b = objs[T.pairs[k + 1]];
        const c = cmp(a, b);
        if (c === 0) continue; // same class, program and material: three orders those by distance
        if (c > 0) { const t = a; a = b; b = t; }
        if (!b.item || out.has(b.item)) continue;
        if (a.item && !out.has(a.item) && a.batch === b.batch) continue;
        out.add(b.item);
        changed = true;
      }
    }
    for (const it of out) {
      if (it.ob) {
        this.drop(it.ob);
        this.dropped--;
      } else {
        it.o.layers = plainLayers(it.o.layers.mask);
        const k = this.baked.findIndex((e) => e.o === it.o);
        if (k >= 0) this.baked.splice(k, 1);
      }
    }
    this.tieOut = out.size;
    if (this.debug) this.debug.tie = new Set([...out].map((it) => it.o));
    return out;
  }

  matRowOf(m) {
    let e = this.mats.get(m);
    if (e) return e;
    if (this.mats.size >= this.matCap) return null;
    const cls = m.map ? this.arrays.layers.get(m.map).c : null;
    e = { m, row: this.mats.size, cache: new Float32Array(MAT_W * 4).fill(NaN), map: m.map, ver: m.version, key: matKey(m), cls, users: [], baked: 0, bad: false };
    this.mats.set(m, e);
    this.matList.push(e);
    if (this.matTex) {
      writeMatRow(m, this.layerOf(m.map), e.cache);
      this.matTex.image.data.set(e.cache, e.row * MAT_W * 4);
      this.matTex.needsUpdate = true;
    }
    return e;
  }

  layerOf(t) {
    if (!t) return 0;
    const l = this.arrays.layers.get(t);
    return l ? l.index : -1;
  }

  // A material (or its texture) that can still be drawn by this material row's batches.
  matOK(m, e) {
    if (!plainToon(m, this.envMap, this.toonKey) || matKey(m) !== e.key) return false;
    if (!m.map) return !e.cls;
    const l = this.arrays.layers.get(m.map);
    return !!l && l.c === e.cls && !this.arrays.leave.has(m.map);
  }

  // Writes every material row that changed; true if the table changed. A material that became incompatible sends
  // its followed users back to three.
  syncMats() {
    const data = this.matTex.image.data, leave = this.arrays.leave;
    let dirty = false;
    for (let i = 0; i < this.matList.length; i++) {
      const e = this.matList[i];
      if (e.bad) continue;
      const m = e.m;
      if (m.version !== e.ver || m.map !== e.map || m.transparent || m.alphaTest > 0 || (m.map && leave.has(m.map))) {
        e.ver = m.version;
        if (!this.matOK(m, e)) {
          e.bad = true;
          for (const ob of e.users) this.drop(ob);
          if (e.baked && !this.warned) { this.warned = true; console.warn(`[abatch:${this.id}] a baked material changed incompatibly (${m.name})`); }
          dirty = true;
          continue;
        }
        e.map = m.map;
      }
      writeMatRow(m, this.layerOf(m.map), _row);
      const c = e.cache;
      let same = true;
      for (let k = 0; k < 32; k++) if (_row[k] !== c[k]) { same = false; break; }
      if (same) continue;
      c.set(_row);
      data.set(_row, e.row * MAT_W * 4);
      dirty = true;
    }
    return dirty;
  }

  writeObjRow(ob) {
    const d = this.objTex.image.data, o = ob.row * OBJ_W * 4;
    _rel.multiplyMatrices(this.rootInv, ob.o.matrixWorld);
    const e = _rel.elements;
    d[o] = e[0]; d[o + 1] = e[1]; d[o + 2] = e[2]; d[o + 3] = 0;
    d[o + 4] = e[4]; d[o + 5] = e[5]; d[o + 6] = e[6]; d[o + 7] = 0;
    d[o + 8] = e[8]; d[o + 9] = e[9]; d[o + 10] = e[10]; d[o + 11] = 0;
    d[o + 12] = e[12]; d[o + 13] = e[13]; d[o + 14] = e[14]; d[o + 15] = 1;
    _nm.getNormalMatrix(_rel);
    const n = _nm.elements;
    d[o + 16] = n[0]; d[o + 17] = n[1]; d[o + 18] = n[2]; d[o + 19] = 0;
    d[o + 20] = n[3]; d[o + 21] = n[4]; d[o + 22] = n[5]; d[o + 23] = 0;
    d[o + 24] = n[6]; d[o + 25] = n[7]; d[o + 26] = n[8]; d[o + 27] = 0;
    d[o + 28] = ob.me.row; d[o + 29] = ob.dead ? 0 : ob.vis; d[o + 30] = ob.cast; d[o + 31] = ob.vcm;
  }

  // Follows the originals. Runs once per scene render (main, shadow, feeds, warm draws), from the first batch mesh of
  // the area that draws: world matrices are current (renderer.render updated them).
  sync() {
    const f = this.game.renderer.info.render.frame;
    if (f === this.frame) return;
    this.frame = f;
    if (!this.enabled) return;
    if (!this.verified) {
      this.verified = this.verify() || (!this.failed && this.orderTries >= ORDER_TRIES);
      if (this.failed) return;
    }
    if (!this.ordered) {
      if (this.verified) this.orderBatches(); else this.orderTries++;
    }
    this.arrays.refresh(f);
    let dirtyO = false;
    const dirtyM = this.syncMats();
    const live = this.live, root = this.root;
    for (let i = live.length - 1; i >= 0; i--) {
      const ob = live[i], o = ob.o;
      let leave = ob.dead || o.layers !== ob.hl || ob.hl.changed || o.geometry !== ob.geo || ob.me.bad || this.versionsChanged(ob);
      if (!leave && o.material !== ob.mat && !this.swap(ob, o.material)) leave = true;
      // visible = the object and every ancestor up to the area root; not under the root: detached (hidden) or
      // moved under another root of the scene (leaves)
      let vis = o.visible ? 1 : 0, at = false, last = o;
      for (let p = o.parent; p; p = p.parent) {
        if (p === root) { at = true; break; }
        if (!p.visible) vis = 0;
        last = p;
      }
      if (!at) {
        if (last.isScene) leave = true;
        vis = 0;
      }
      if (leave) {
        this.drop(ob);
        live.splice(i, 1);
        dirtyO = true;
        continue;
      }
      const cast = o.castShadow ? 1 : 0;
      const vcm = vcMode(ob.mat, ob.geo);
      let changed = vis !== ob.vis || cast !== ob.cast || ob.me.row !== ob.rowMat || vcm !== ob.vcm;
      if (at) {
        const e = o.matrixWorld.elements, mw = ob.mw;
        let moved = false;
        for (let k = 0; k < 16; k++) if (e[k] !== mw[k]) { moved = true; break; }
        if (moved) {
          if ((o.matrixWorld.determinant() < 0) !== ob.det) { this.drop(ob); live.splice(i, 1); dirtyO = true; continue; }
          for (let k = 0; k < 16; k++) mw[k] = e[k];
          this.grow(ob);
          changed = true;
        }
      }
      if (!changed) continue;
      ob.vis = vis; ob.cast = cast; ob.rowMat = ob.me.row; ob.vcm = vcm;
      this.writeObjRow(ob);
      dirtyO = true;
    }
    if (dirtyO) this.objTex.needsUpdate = true;
    if (dirtyM) this.matTex.needsUpdate = true;
  }

  versionsChanged(ob) {
    const a = ob.geo.attributes, v = ob.vers;
    return a.position.version !== v[0] || a.normal.version !== v[1] || (a.uv ? a.uv.version : 0) !== v[2]
      || (a.color ? a.color.version : 0) !== v[3] || (ob.geo.index ? ob.geo.index.version : 0) !== v[4];
  }

  // Material swap on a followed object: fine while the new material batches with the same key.
  swap(ob, m) {
    if (!plainToon(m, this.envMap, this.toonKey) || matKey(m) !== ob.batch.matKey) return false;
    if (m.map) {
      const l = this.arrays.layers.get(m.map);
      if (!l || l.c !== ob.batch.cls || this.arrays.leave.has(m.map)) return false;
    }
    const me = this.matRowOf(m);
    if (!me || me.bad) return false;
    if (!me.users.includes(ob)) me.users.push(ob);
    ob.mat = m;
    ob.me = me;
    return true;
  }

  // The object leaves the batch for good: hidden row, the original is drawn by three again.
  drop(ob) {
    if (ob.dead) return;
    ob.dead = true;
    ob.vis = 0;
    this.writeObjRow(ob);
    this.objTex.needsUpdate = true;
    const o = ob.o;
    if (o.layers === ob.hl) o.layers = plainLayers(ob.hl._m);
    this.dropped++;
  }

  // A followed object moved: keep it inside the batch's bounding sphere (never shrinks).
  grow(ob) {
    const g = ob.geo;
    if (!g.boundingSphere) g.computeBoundingSphere();
    _rel.multiplyMatrices(this.rootInv, ob.o.matrixWorld);
    _sph.copy(g.boundingSphere).applyMatrix4(_rel);
    const bs = ob.batch.mesh.geometry.boundingSphere;
    if (bs.center.distanceTo(_sph.center) + _sph.radius > bs.radius) bs.union(_sph);
  }
}

// ---- coplanar ties
// Two opaque surfaces in the same plane (same facing) that overlap resolve their exact depth tie by draw order: with
// the LessEqual depth test the later draw wins. three orders the opaque list by renderOrder, program, material id;
// the batches change that order for objects that end up in different batches (or batched vs not). findTies() lists
// the pairs of objects (an area's batch candidates, plus the other opaque meshes of the area and of the roots
// tieRoots gives: its doors, the shell) with overlapping coplanar triangles; AreaBatch.resolveTies keeps three's
// winner for each pair. Planes are bucketed by quantized normal (1e-3) and distance (0.5 mm), per object one box per
// plane; pairs = boxes of different objects in one bucket that overlap (+0.2 mm).
const TIE_EPS = 2e-4;
const _tp = [0, 0, 0, 0, 0, 0, 0, 0, 0];

function tieObjects(o, root, cand) {
  if (!o.isMesh || o.isInstancedMesh || o.isSkinnedMesh || o.isBatchedMesh || cand.has(o)) return false;
  if (o.userData.daBatch || o.userData.shadowProxy || !o.geometry || !o.geometry.attributes.position) return false;
  const m = o.material;
  if (!m || Array.isArray(m) || m.transparent || !m.visible || !(o.layers.mask & 3)) return false;
  return effVisible(o, root);
}

function planeBoxes(o, idx, map) {
  const g = o.geometry, pos = g.attributes.position, index = g.index, e = o.matrixWorld.elements;
  const side = o.material.side, flipW = o.matrixWorld.determinant() < 0;
  const cnt = index ? index.count : pos.count;
  const per = new Map();
  const put = (k, P) => {
    let b = per.get(k);
    if (!b) { per.set(k, (b = [Infinity, Infinity, Infinity, -Infinity, -Infinity, -Infinity])); }
    for (let v = 0; v < 9; v += 3) {
      if (P[v] < b[0]) b[0] = P[v]; if (P[v + 1] < b[1]) b[1] = P[v + 1]; if (P[v + 2] < b[2]) b[2] = P[v + 2];
      if (P[v] > b[3]) b[3] = P[v]; if (P[v + 1] > b[4]) b[4] = P[v + 1]; if (P[v + 2] > b[5]) b[5] = P[v + 2];
    }
  };
  const key = (nx, ny, nz, d) => ((Math.round(nx * 1000) + 1000) * 2001 + (Math.round(ny * 1000) + 1000)) * 2001 * 524288
    + (Math.round(nz * 1000) + 1000) * 524288 + (Math.round(d * 2000) + 262144);
  const P = _tp;
  for (let t = 0; t < cnt; t += 3) {
    for (let v = 0; v < 3; v++) {
      const i = index ? index.getX(t + v) : t + v;
      const x = pos.getX(i), y = pos.getY(i), z = pos.getZ(i);
      P[v * 3] = e[0] * x + e[4] * y + e[8] * z + e[12];
      P[v * 3 + 1] = e[1] * x + e[5] * y + e[9] * z + e[13];
      P[v * 3 + 2] = e[2] * x + e[6] * y + e[10] * z + e[14];
    }
    const ux = P[3] - P[0], uy = P[4] - P[1], uz = P[5] - P[2], vx = P[6] - P[0], vy = P[7] - P[1], vz = P[8] - P[2];
    let nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx;
    const len = Math.sqrt(nx * nx + ny * ny + nz * nz);
    if (!(len > 1e-12)) continue;
    const s = (flipW ? -1 : 1) / len;
    nx *= s; ny *= s; nz *= s;
    const d = nx * P[0] + ny * P[1] + nz * P[2];
    if (side !== THREE.BackSide) put(key(nx, ny, nz, d), P);
    if (side !== THREE.FrontSide) put(key(-nx, -ny, -nz, -d), P);
  }
  for (const [k, b] of per) {
    let l = map.get(k);
    if (!l) map.set(k, (l = []));
    l.push(idx, b);
  }
}

// Coplanar triangles of ONE object that overlap (interior, not just a shared edge): its own depth ties / z-fighting.
// Only a batched copy whose vertices go through the exact same float math as three's (a baked mesh already in area
// space) reproduces that pattern bit for bit; other objects with such triangles stay with three.
function sepAxis(A, B, eps) {
  for (let i = 0; i < 3; i++) {
    const j = i === 2 ? 0 : i + 1;
    let nx = A[j * 2 + 1] - A[i * 2 + 1], ny = A[i * 2] - A[j * 2];
    const l = Math.hypot(nx, ny);
    if (!(l > 1e-12)) continue;
    nx /= l; ny /= l;
    let a0 = Infinity, a1 = -Infinity, b0 = Infinity, b1 = -Infinity;
    for (let k = 0; k < 3; k++) {
      const pa = A[k * 2] * nx + A[k * 2 + 1] * ny, pb = B[k * 2] * nx + B[k * 2 + 1] * ny;
      if (pa < a0) a0 = pa; if (pa > a1) a1 = pa; if (pb < b0) b0 = pb; if (pb > b1) b1 = pb;
    }
    if (a1 <= b0 + eps || b1 <= a0 + eps) return true;
  }
  return false;
}

function selfTie(o) {
  const g = o.geometry, pos = g.attributes.position, index = g.index, e = o.matrixWorld.elements;
  const cnt = index ? index.count : pos.count;
  const byPlane = new Map(), P = _tp;
  for (let t = 0; t < cnt; t += 3) {
    for (let v = 0; v < 3; v++) {
      const i = index ? index.getX(t + v) : t + v;
      const x = pos.getX(i), y = pos.getY(i), z = pos.getZ(i);
      P[v * 3] = e[0] * x + e[4] * y + e[8] * z + e[12];
      P[v * 3 + 1] = e[1] * x + e[5] * y + e[9] * z + e[13];
      P[v * 3 + 2] = e[2] * x + e[6] * y + e[10] * z + e[14];
    }
    const ux = P[3] - P[0], uy = P[4] - P[1], uz = P[5] - P[2], vx = P[6] - P[0], vy = P[7] - P[1], vz = P[8] - P[2];
    let nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx;
    const len = Math.sqrt(nx * nx + ny * ny + nz * nz);
    if (!(len > 1e-12)) continue;
    nx /= len; ny /= len; nz /= len;
    const d = nx * P[0] + ny * P[1] + nz * P[2];
    // one bucket per plane whatever the facing (a front face over a back face of a double-sided part ties too)
    const sg = nx + ny * 1.618 + nz * 2.718 < 0 ? -1 : 1;
    const k = ((Math.round(nx * sg * 1000) + 1000) * 2001 + (Math.round(ny * sg * 1000) + 1000)) * 2001 * 524288
      + (Math.round(nz * sg * 1000) + 1000) * 524288 + (Math.round(d * sg * 2000) + 262144);
    const ax = Math.abs(nx), ay = Math.abs(ny), az = Math.abs(nz);
    const c0 = ax >= ay && ax >= az ? 1 : 0, c1 = ax >= ay && ax >= az ? 2 : ay >= az ? 2 : 1;
    const tri = [P[c0], P[c1], P[3 + c0], P[3 + c1], P[6 + c0], P[6 + c1]];
    let l = byPlane.get(k);
    if (!l) byPlane.set(k, (l = []));
    l.push(tri);
  }
  for (const l of byPlane.values()) {
    if (l.length < 2) continue;
    const box = l.map((T) => [Math.min(T[0], T[2], T[4]), Math.max(T[0], T[2], T[4]), Math.min(T[1], T[3], T[5]), Math.max(T[1], T[3], T[5]), T]);
    box.sort((a, b) => a[0] - b[0]);
    for (let i = 0; i < box.length; i++) {
      const A = box[i];
      for (let j = i + 1; j < box.length && box[j][0] < A[1] - 2e-5; j++) {
        const B = box[j];
        if (B[3] <= A[2] + 2e-5 || A[3] <= B[2] + 2e-5) continue;
        if (!sepAxis(A[4], B[4], 2e-5) && !sepAxis(B[4], A[4], 2e-5)) return true;
      }
    }
  }
  return false;
}

// -> { objs:[{ o, mat, ro, slot, exact, self, item:null, batch:null }], pairs:[i, j, ...] }
//   slot: group key or null = not batched; exact: a batched copy draws it bit for bit (baked, already in area space);
//   self: a non-exact candidate with its own coplanar overlaps (selfTie)
function findTies(root, cand, slotOf, extraRoots, exactOf) {
  const objs = [], map = new Map(), cset = new Set(cand);
  for (const o of cand) {
    const exact = exactOf(o);
    objs.push({ o, mat: o.material, ro: o.renderOrder, slot: slotOf(o), exact, self: !exact && selfTie(o), item: null, batch: null });
  }
  const add = (r) => r.traverse((o) => { if (tieObjects(o, r, cset)) objs.push({ o, mat: o.material, ro: o.renderOrder, slot: null, item: null, batch: null }); });
  add(root);
  for (const r of extraRoots) if (r) add(r);
  for (let i = 0; i < cand.length; i++) if (objs[i].self) objs[i].slot = null; // never batched (see selfTie)
  for (let i = 0; i < objs.length; i++) planeBoxes(objs[i].o, i, map);
  const pairs = [], seen = new Set();
  for (const l of map.values()) {
    if (l.length < 4) continue;
    for (let a = 0; a < l.length; a += 2) {
      const ia = l[a], A = l[a + 1], sa = objs[ia].slot;
      for (let b = a + 2; b < l.length; b += 2) {
        const ib = l[b], B = l[b + 1], sb = objs[ib].slot;
        if (ia === ib || (sa === null && sb === null) || (sa !== null && sa === sb)) continue;
        if (A[0] > B[3] + TIE_EPS || B[0] > A[3] + TIE_EPS || A[1] > B[4] + TIE_EPS || B[1] > A[4] + TIE_EPS || A[2] > B[5] + TIE_EPS || B[2] > A[5] + TIE_EPS) continue;
        const k = ia < ib ? ia * 1e6 + ib : ib * 1e6 + ia;
        if (seen.has(k)) continue;
        seen.add(k);
        pairs.push(ia, ib);
      }
    }
  }
  return { objs, pairs };
}

function isIdentity(m) {
  const e = m.elements;
  for (let i = 0; i < 16; i++) if (e[i] !== ((i % 5) === 0 ? 1 : 0)) return false;
  return true;
}

function makeBatchMaterial(game, gr, A) {
  const m0 = gr.m0;
  const bm = new THREE.MeshStandardMaterial({
    color: 0xffffff, roughness: 1, metalness: 0, vertexColors: true, side: m0.side, flatShading: m0.flatShading,
    fog: m0.fog, depthWrite: m0.depthWrite, depthFunc: m0.depthFunc, toneMapped: m0.toneMapped, dithering: m0.dithering,
    premultipliedAlpha: m0.premultipliedAlpha, polygonOffset: m0.polygonOffset, polygonOffsetFactor: m0.polygonOffsetFactor,
    polygonOffsetUnits: m0.polygonOffsetUnits, envMap: m0.envMap ? A.envMap : null,
  });
  bm.shadowSide = m0.shadowSide;
  bm.envMapIntensity = 1;
  game.mats._patchToon(bm, { ...m0.userData.daToon.params });
  bm.defines = { ...(m0.defines || {}), DA_BATCH: '' };
  if (gr.cls) bm.defines.DA_MAP = '';
  const extra = { uDaObj: { value: A.objTex }, uDaMat: { value: A.matTex } };
  if (gr.cls) extra.uDaMap = { value: gr.cls.tex };
  const toon = bm.onBeforeCompile;
  bm.onBeforeCompile = (shader, renderer) => {
    toon(shader, renderer);
    const miss = [];
    shader.vertexShader = applyEdits(shader.vertexShader, VERT_EDITS, miss);
    shader.fragmentShader = applyEdits(shader.fragmentShader, FRAG_EDITS, miss);
    if (miss.length) console.error('[abatch] shader edit anchors missing', miss);
    Object.assign(shader.uniforms, extra);
  };
  const base = m0.customProgramCacheKey();
  bm.customProgramCacheKey = () => `${base}|abatch2`;
  bm.name = `abatch:${A.id}`;
  bm.userData.daBatchMat = true;
  return bm;
}

function makeDepthMaterial(A) {
  const dm = new THREE.MeshDepthMaterial();
  const extra = { uDaObj: { value: A.objTex }, uDaMat: { value: A.matTex } };
  dm.onBeforeCompile = (shader) => {
    const miss = [];
    shader.vertexShader = applyEdits(shader.vertexShader, DEPTH_EDITS, miss);
    if (miss.length) console.error('[abatch] depth shader edit anchors missing', miss);
    Object.assign(shader.uniforms, extra);
  };
  dm.customProgramCacheKey = () => 'dadepth-abatch2';
  dm.name = `abatch:${A.id}:depth`;
  return dm;
}

function batchCandidate(o, root, envMap, toonKey) {
  if (o === root || !o.isMesh || o.isInstancedMesh || o.isSkinnedMesh || o.isBatchedMesh) return false;
  if (o.userData.shadowProxy || o.userData.daBatch || o.userData.daNoBatch) return false;
  if (o.morphTargetInfluences || !o.frustumCulled || o.onBeforeRender !== NOOP_BR || o.onAfterRender !== NOOP_AR) return false;
  if (o.onBeforeShadow !== NOOP_BS || o.onAfterShadow !== NOOP_AS) return false;
  if (o.customDepthMaterial || o.customDistanceMaterial || o.layers.constructor !== THREE.Layers || !o.layers.mask) return false;
  const g = o.geometry;
  if (!g || !g.isBufferGeometry || !g.attributes.position || !g.attributes.normal) return false;
  if (g.attributes.position.itemSize !== 3 || g.attributes.normal.itemSize !== 3) return false;
  if (g.morphAttributes && Object.keys(g.morphAttributes).length) return false;
  if (g.drawRange.start !== 0 || g.drawRange.count !== Infinity) return false;
  if (g.attributes.color && g.attributes.color.itemSize < 3) return false;
  if (g.attributes.uv && g.attributes.uv.itemSize !== 2) return false;
  return plainToon(o.material, envMap, toonKey) && effVisible(o, root);
}

// Static pipeline meshes (level.js's geo.mergeByMaterial / world batch output: direct children of the area root, never
// referenced by gameplay code) that do not cast: copied into the batch in area space (already there: the copy is bit
// for bit), the original leaves the scene once the batches are ordered (or stays hidden with keep). Everything else,
// prop-level merges included, is followed.
function isBaked(o, root) {
  const n = o.name || '';
  return o.parent === root && (n.startsWith('merged:') || n.startsWith('batch:')) && !o.castShadow && !o.children.length && !o.userData.noMerge && !o.userData.dynamic;
}

// One batch mesh from a group of candidates of one area. The triangles are in the order three drew the originals
// within one program (material id, then scene order), so exactly coplanar surfaces of the group still resolve their
// depth tie the same way (three draws opaque objects of one program by material id; the later draw wins a tie).
// Followed casters also get a shadow-only twin (same attributes, index of the followed objects only, visible only
// while the key shadow map renders, like the shadow proxies): the baked part never casts.
function buildBatch(game, A, gr, sync, n, keep) {
  const root = A.root;
  const b = { key: gr.key, matKey: gr.matKey, cls: gr.cls, mesh: null, shadow: null };
  const order = gr.list.map((o, i) => [o, i]);
  order.sort((x, y) => (x[0].material.id - y[0].material.id) || (x[1] - y[1]));
  const items = [];
  let nv = 0, ni = 0, nl = 0, anyCast = false, nBaked = 0;
  for (const [o] of order) {
    const g = o.geometry, at = g.attributes;
    const cnt = g.index ? g.index.count : at.position.count;
    if (isBaked(o, root)) {
      const me = A.matRowOf(o.material);
      me.baked++;
      nBaked++;
      items.push({ o, g, ob: null, me, mat: o.material });
    } else {
      const ob = {
        o, hl: null, row: A.objs.length, mat: o.material, me: null, batch: b, geo: g, vcm: vcMode(o.material, g),
        vis: 1, cast: o.castShadow ? 1 : 0, rowMat: -1, mw: new Float64Array(o.matrixWorld.elements),
        det: o.matrixWorld.determinant() < 0, dead: false,
        vers: [at.position.version, at.normal.version, at.uv ? at.uv.version : 0, at.color ? at.color.version : 0, g.index ? g.index.version : 0],
      };
      ob.me = A.matRowOf(o.material);
      ob.me.users.push(ob);
      ob.rowMat = ob.me.row;
      if (ob.cast) anyCast = true;
      A.objs.push(ob);
      items.push({ o, g, ob, me: ob.me, mat: o.material });
      nl += cnt;
    }
    nv += at.position.count;
    ni += cnt;
  }
  const P = new Float32Array(nv * 3), N = new Float32Array(nv * 3), C = new Float32Array(nv * 3), R = new Float32Array(nv);
  const U = gr.cls ? new Float32Array(nv * 2) : null;
  const big = nv > 65535;
  const I = big ? new Uint32Array(ni) : new Uint16Array(ni);
  const S = anyCast ? (big ? new Uint32Array(nl) : new Uint16Array(nl)) : null;
  const box = new THREE.Box3();
  const spheres = [];
  let vb = 0, ib = 0, sb = 0;
  for (const it of items) {
    const { o, g, ob, me } = it, pos = g.attributes.position, nor = g.attributes.normal, cnt = pos.count;
    let flip = false, bake = null;
    if (!ob) {
      _rel.multiplyMatrices(A.rootInv, o.matrixWorld);
      if (!isIdentity(_rel)) { bake = _rel.clone(); flip = bake.determinant() < 0; }
    } else flip = ob.det;
    const nmat = bake ? new THREE.Matrix3().getNormalMatrix(bake) : null;
    const tag = ob ? ob.row : -(me.row + 1);
    for (let i = 0; i < cnt; i++) {
      const k = (vb + i) * 3;
      if (bake) {
        _vv.fromBufferAttribute(pos, i).applyMatrix4(bake);
        P[k] = _vv.x; P[k + 1] = _vv.y; P[k + 2] = _vv.z;
        _vv.fromBufferAttribute(nor, i).applyNormalMatrix(nmat);
        N[k] = _vv.x; N[k + 1] = _vv.y; N[k + 2] = _vv.z;
      } else {
        P[k] = pos.getX(i); P[k + 1] = pos.getY(i); P[k + 2] = pos.getZ(i);
        N[k] = nor.getX(i); N[k + 1] = nor.getY(i); N[k + 2] = nor.getZ(i);
      }
      R[vb + i] = tag;
    }
    const col = ob || o.material.vertexColors ? g.attributes.color : null;
    for (let i = 0; i < cnt; i++) {
      const k = (vb + i) * 3;
      if (col) { C[k] = col.getX(i); C[k + 1] = col.getY(i); C[k + 2] = col.getZ(i); } else { C[k] = 1; C[k + 1] = 1; C[k + 2] = 1; }
    }
    const uv = U && g.attributes.uv;
    if (uv) for (let i = 0; i < cnt; i++) { U[(vb + i) * 2] = uv.getX(i); U[(vb + i) * 2 + 1] = uv.getY(i); }
    const idx = g.index, ic = idx ? idx.count : cnt;
    const toS = S && ob;
    it.i0 = ib; it.s0 = sb;
    for (let i = 0; i < ic; i += 3) {
      const a = vb + (idx ? idx.getX(i) : i), bb = vb + (idx ? idx.getX(i + 1) : i + 1), c = vb + (idx ? idx.getX(i + 2) : i + 2);
      I[ib++] = a; I[ib++] = flip ? c : bb; I[ib++] = flip ? bb : c;
      if (toS) { S[sb++] = a; S[sb++] = flip ? c : bb; S[sb++] = flip ? bb : c; }
    }
    it.i1 = ib; it.s1 = sb;
    if (!ob) {
      for (let i = vb; i < vb + cnt; i++) box.expandByPoint(_vv.set(P[i * 3], P[i * 3 + 1], P[i * 3 + 2]));
    } else {
      if (!g.boundingSphere) g.computeBoundingSphere();
      _rel.multiplyMatrices(A.rootInv, o.matrixWorld);
      const s = g.boundingSphere.clone().applyMatrix4(_rel);
      spheres.push(s);
      box.expandByPoint(_vv.copy(s.center).addScalar(s.radius));
      box.expandByPoint(_vv.copy(s.center).addScalar(-s.radius));
    }
    vb += cnt;
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.BufferAttribute(P, 3));
  geo.setAttribute('normal', new THREE.BufferAttribute(N, 3));
  geo.setAttribute('color', new THREE.BufferAttribute(C, 3));
  if (U) geo.setAttribute('uv', new THREE.BufferAttribute(U, 2));
  geo.setAttribute('daObj', new THREE.BufferAttribute(R, 1));
  geo.setIndex(new THREE.BufferAttribute(I, 1));
  geo.boundingBox = box;
  const bs = new THREE.Sphere();
  box.getCenter(bs.center);
  let rad = 0;
  for (const s of spheres) rad = Math.max(rad, bs.center.distanceTo(s.center) + s.radius);
  vb = 0;
  for (const it of items) {
    const cnt = it.g.attributes.position.count;
    if (!it.ob) {
      for (let i = vb; i < vb + cnt; i++) {
        const dx = P[i * 3] - bs.center.x, dy = P[i * 3 + 1] - bs.center.y, dz = P[i * 3 + 2] - bs.center.z;
        const d2 = dx * dx + dy * dy + dz * dz;
        if (d2 > rad * rad) rad = Math.sqrt(d2);
      }
    }
    vb += cnt;
  }
  bs.radius = rad;
  geo.boundingSphere = bs;
  const mat = makeBatchMaterial(game, gr, A);
  const mesh = new THREE.Mesh(geo, mat);
  mesh.name = `abatch:${A.id}:${n}`;
  mesh.userData.daBatch = true;
  mesh.userData.noMerge = true;
  mesh.castShadow = false;
  mesh.receiveShadow = gr.receive;
  mesh.layers.mask = gr.layers;
  mesh.renderOrder = gr.renderOrder - 0.5; // before the non-batched objects of its class (see orderBatches)
  mesh.onBeforeRender = sync;
  mesh.raycast = () => {}; // raycasts hit the originals (still in the scene), never the area-space copy
  root.add(mesh);
  mesh.updateMatrixWorld(true);
  mesh.matrixAutoUpdate = false;
  b.mesh = mesh;
  if (S) {
    // shadow-only twin: the followed objects' triangles (rows hide the ones not casting right now)
    const sg = new THREE.BufferGeometry();
    for (const k of ['position', 'normal', 'color', 'uv', 'daObj']) if (geo.attributes[k]) sg.setAttribute(k, geo.attributes[k]);
    sg.setIndex(new THREE.BufferAttribute(S, 1));
    sg.boundingBox = box;
    sg.boundingSphere = bs; // shared: grow() keeps both in step
    const sh = new THREE.Mesh(sg, mat);
    sh.name = `abatch:${A.id}:${n}:shadow`;
    sh.userData.daBatch = true;
    sh.userData.noMerge = true;
    sh.userData.shadowProxy = true;
    sh.castShadow = true;
    sh.receiveShadow = false;
    sh.visible = false;
    sh.layers.mask = gr.layers;
    sh.customDepthMaterial = makeDepthMaterial(A);
    sh.onBeforeRender = sync;
    sh.onBeforeShadow = sync;
    sh.raycast = () => {};
    root.add(sh);
    sh.updateMatrixWorld(true);
    sh.matrixAutoUpdate = false;
    b.shadow = sh;
  }
  // the originals are hidden from cameras; baked ones leave the scene once the batches are ordered (orderBatches
  // reads their programs; with keep they stay, hidden, for the A/B toggle)
  for (const it of items) {
    const o = it.o;
    if (it.ob) {
      it.ob.hl = new HiddenLayers(o.layers.mask);
      o.layers = it.ob.hl;
    } else {
      A.baked.push({ o, mask: o.layers.mask });
      o.layers = new HiddenLayers(o.layers.mask);
    }
  }
  b.baked = nBaked;
  b.items = items.map((it) => ({ mat: it.mat, o: it.o, ob: it.ob, i0: it.i0, i1: it.i1, s0: it.s0, s1: it.s1, n: 0 }));
  b.items.forEach((it, i) => { it.n = i; });
  b.ro = gr.renderOrder;
  return b;
}

export function buildAreaBatches(game, roots, opts = {}) {
  const out = {};
  for (const _ of buildAreaBatchesSteps(game, roots, opts, out)) { /* all now */ }
  return out.result || null;
}

export function* buildAreaBatchesSteps(game, roots, { keep = false, follow = true, ties = true, tieRoots = null } = {}, out = {}) {
  out.result = null;
  const r = game.renderer, mats = game.mats;
  if (!r || !r.capabilities || !r.capabilities.isWebGL2 || !mats || !mats._patchToon || !mats.toon) return;
  const missing = shaderCheck(game);
  if (missing.length) {
    console.warn('[abatch] shader anchors not found, area batching disabled:', missing);
    return;
  }
  hookRenderer(r);
  const toonKey = mats.toon('#ffffff').customProgramCacheKey; // the toon program's key function (shared by all)
  const envMap = mats.envMap;
  const arrays = new TexArrays(r);
  const plan = {};
  const stats = { objects: 0, followed: 0, baked: 0, batches: 0, arrays: 0, layers: 0, areas: {} };
  // 1) candidates of every area, then the texture arrays (one allocation per class)
  for (const id in roots) {
    const root = roots[id];
    root.updateMatrixWorld(true);
    const cand = [];
    root.traverse((o) => {
      if (!batchCandidate(o, root, envMap, toonKey)) return;
      if (!follow && !isBaked(o, root)) return;
      cand.push(o);
      if (o.material.map) arrays.plan(o.material.map);
    });
    plan[id] = cand;
  }
  let k = 0;
  for (const c of arrays.classes.values()) {
    arrays._alloc(c);
    stats.arrays++;
    stats.layers += c.list.length;
    if (++k % 8 === 0) yield;
  }
  yield;
  // 2) batches per area
  const areas = {};
  for (const id in roots) {
    const root = roots[id], cand = plan[id];
    if (!cand.length) continue;
    const A = new AreaBatch(game, id, root, arrays, envMap, toonKey);
    A.keep = keep;
    A.rootInv.copy(root.matrixWorld).invert();
    const groups = new Map();
    const groupKey = (o) => `${matKey(o.material)}|${o.receiveShadow}|${o.layers.mask}|${o.renderOrder}`;
    const exactOf = (o) => isBaked(o, root) && isIdentity(_rel.multiplyMatrices(A.rootInv, o.matrixWorld));
    const T = ties ? findTies(root, cand, groupKey, tieRoots ? tieRoots(id) : [], exactOf) : null;
    const use = T ? cand.filter((o, i) => !T.objs[i].self) : cand; // self-tied objects stay with three
    A.debug = { cand: new Set(cand), self: new Set(cand.filter((o) => !use.includes(o))), tie: null };
    if (!use.length) continue;
    let nFollow = 0;
    for (const o of use) {
      const m = o.material, mk = matKey(m);
      const key = groupKey(o);
      let gr = groups.get(key);
      if (!gr) {
        groups.set(key, (gr = { key, matKey: mk, list: [], cls: m.map ? arrays.layers.get(m.map).c : null, m0: m,
          receive: o.receiveShadow, layers: o.layers.mask, renderOrder: o.renderOrder }));
      }
      gr.list.push(o);
      if (!isBaked(o, root)) nFollow++;
    }
    A.matCap = new Set(use.map((o) => o.material)).size + MAT_SPARE;
    const rows = Math.max(1, nFollow);
    A.objTex = new THREE.DataTexture(new Float32Array(OBJ_W * 4 * rows), OBJ_W, rows, THREE.RGBAFormat, THREE.FloatType);
    A.matTex = new THREE.DataTexture(new Float32Array(MAT_W * 4 * A.matCap), MAT_W, A.matCap, THREE.RGBAFormat, THREE.FloatType);
    for (const t of [A.objTex, A.matTex]) {
      t.minFilter = t.magFilter = THREE.NearestFilter;
      t.generateMipmaps = false;
      t.flipY = false;
      t.unpackAlignment = 1;
      t.needsUpdate = true;
    }
    A.objTex.name = `abatch:${id}:objects`;
    A.matTex.name = `abatch:${id}:materials`;
    const sync = () => A.sync();
    let n = 0;
    for (const gr of groups.values()) A.batches.push(buildBatch(game, A, gr, sync, n++, keep));
    for (const ob of A.objs) A.writeObjRow(ob);
    A.syncMats();
    A.live = A.objs.slice();
    if (T) {
      const where = new Map();
      for (const b of A.batches) for (const it of b.items) where.set(it.o, [b, it]);
      for (const t of T.objs) { const w = where.get(t.o); if (w) { t.batch = w[0]; t.item = w[1]; } }
      A.ties = T;
    }
    const st = { objects: use.length, followed: A.objs.length, batches: A.batches.length, materials: A.mats.size, ties: T ? T.pairs.length / 2 : 0, selfTied: cand.length - use.length };
    stats.areas[id] = st;
    stats.objects += st.objects;
    stats.followed += st.followed;
    stats.baked += st.objects - st.followed;
    stats.batches += st.batches;
    areas[id] = A;
    yield;
  }
  out.result = new AreaBatches(areas, arrays, stats, keep, r);
}

class AreaBatches {
  constructor(areas, arrays, stats, keep, renderer) {
    this.areas = areas;
    this.arrays = arrays;
    this.stats = stats;
    this.keep = keep;
    this.renderer = renderer;
    this.enabled = true;
  }

  // Per frame (level.update): array layers whose source canvas was redrawn since its upload are uploaded again
  // (the batches' sync does it too, for frames rendered outside gameplay).
  update() {
    if (this.enabled) this.arrays.refresh(this.renderer.info.render.frame);
  }

  get dropped() {
    let n = 0;
    for (const id in this.areas) n += this.areas[id].dropped;
    return n;
  }

  get meshes() {
    const out = [];
    for (const id in this.areas) for (const b of this.areas[id].batches) out.push(b.mesh);
    return out;
  }

  // A/B toggle. Complete only with keep (otherwise the baked originals are gone and only the followed ones return).
  setEnabled(on) {
    on = !!on;
    if (on === this.enabled) return;
    this.enabled = on;
    for (const id in this.areas) {
      const A = this.areas[id];
      if (A.failed) continue;
      A.enabled = on;
      A.frame = -1;
      for (const b of A.batches) {
        b.mesh.visible = on;
        if (b.shadow) b.shadow.geometry.drawRange.count = on ? (b.sCount ?? Infinity) : 0;
      }
      for (const e of A.baked) e.o.layers = on ? new HiddenLayers(e.mask) : plainLayers(e.mask);
      for (const ob of A.live) {
        if (ob.dead) continue;
        const o = ob.o;
        if (on) {
          const mask = o.layers.mask;
          ob.hl = new HiddenLayers(mask);
          o.layers = ob.hl;
          ob.vis = -1; // rewrite every row on the next sync
        } else if (o.layers === ob.hl) {
          o.layers = plainLayers(ob.hl._m);
        }
      }
      if (on) for (const e of A.matList) e.cache.fill(NaN);
    }
  }
}
