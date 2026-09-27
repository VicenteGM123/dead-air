// Runtime for baked SDF characters (ARCHITECTURE §8/§12 compatible).
//   buildCharacter(defOrId, opts) -> { group, rig, animator, skinnedMesh, slots, face, hairBounds, parts, def, update }
//   opts: { envMap, globals (game.mats.uniforms: shares uRimAmbient/uHeroFade), heroFade, animator: true|false|style,
//           layer (render layer; zombies default LAYERS.ZOMBIES), shadows: true (cast), receiveShadow: false }
// receiveShadow defaults to FALSE: at game shadow-map resolution a character's own jaw/hair/arm shadows alias into dark
// smudges (e.g. under the jaw on the neck); the baked AO already darkens those contacts softly (STYLE_GUIDE §6).
// The SkinnedMesh is bound to the SAME joints createRig() makes (src/core/rig.js), in the bake's bind pose (A-pose), so
// the engine Animator animates it unchanged. animator.update is wrapped to (1) add the character's rest offsets
// (def.armOut: arms clear the torso; def.poseOffset: {joint:[x,y,z]} additive) and (2) update the face.
// Geometry/materials are cached per character id and shared between instances (zombie crowds).
// Draw calls (perf): opts.merge (heroes) folds the baked rigid parts (brows, headbands, afro) into the body and merges
// the rigid attachments per material (mergeAttachments below; zombie builders call it themselves). Every character
// skeleton re-uploads its bone texture only when a bone matrix changed (charOpt.dedupe). charOpt flags are live
// toggles for A/B measurements (tools/scenarios/perf_char_*.cjs): merge applies to characters built afterwards.
import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { Animator } from '../core/rig.js';
import { LAYERS } from '../core/config.js';
import { decodeBaked } from './bakedFormat.js';
import { buildRig, applyBindPose, resetPose } from './rigBuild.js';
import { createCharMaterial } from './charMaterial.js';
import { makeAttachBuilder, FaceController } from './face.js';
import BAKED from '../../assets/baked/registry.js';
import DEFS from './chars/index.js';

const geoCache = new Map();
const matCache = new Map();

// Live perf flags. merge: characters built with opts.merge (and the zombie builders) merge parts + attachments;
// dedupe: skeletons skip the bone-texture upload when no bone moved; gen: bumped by A/B tools to invalidate model pools;
// crowd: Tuned-In attachments of the whole crowd drawn as one batch per look and material (zombieTypes.js).
export const charOpt = { merge: true, dedupe: true, gen: 0, crowd: true };

const srgbToLinear = (c) => (c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4));
const LUT = new Float32Array(256).map((_, i) => srgbToLinear(i / 255));

export function characterIds() { return Object.keys(DEFS).filter((id) => BAKED[id]); }
export function getDef(id) { return DEFS[id]; }

function decoded(id) {
  let d = geoCache.get(id);
  if (d) return d;
  const bin = BAKED[id];
  if (!bin) throw new Error(`charRuntime: '${id}' is not baked (node tools/bake/bake.mjs ${id})`);
  const { header, arrays } = decodeBaked(bin);
  d = { header, arrays, body: makeGeometry(header, arrays, '', header.qbox, true), parts: {} };
  for (const [name, p] of Object.entries(header.parts || {})) d.parts[name] = makeGeometry(header, arrays, `part_${name}_`, p.qbox, false);
  geoCache.set(id, d);
  return d;
}

function makeGeometry(header, A, pre, qbox, skinned) {
  const g = new THREE.BufferGeometry();
  const q = A[pre + 'pos'].array;
  const n = q.length / 3;
  const pos = new Float32Array(n * 3);
  for (let i = 0; i < n; i++) for (let c = 0; c < 3; c++) pos[i * 3 + c] = qbox[c] + (q[i * 3 + c] / 65535) * qbox[c + 3];
  g.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  g.setAttribute('normal', new THREE.BufferAttribute(A[pre + 'nrm'].array, 3, true));
  const cb = A[pre + 'col'].array;
  const col = new Float32Array(n * 3);
  for (let i = 0; i < n * 3; i++) col[i] = LUT[cb[i]];
  g.setAttribute('color', new THREE.BufferAttribute(col, 3));
  g.setAttribute('aux', new THREE.BufferAttribute(A[pre + 'aux'].array, 4, false));
  g.setAttribute('pco', new THREE.BufferAttribute(A[pre + 'pco'].array, 3));
  g.setAttribute('pw', new THREE.BufferAttribute(A[pre + 'pw'].array, 4, true));
  g.setAttribute('flow', new THREE.BufferAttribute(A[pre + 'flow'].array, 4, true));
  if (skinned && A[pre + 'skinIndex']) {
    g.setAttribute('skinIndex', new THREE.BufferAttribute(A[pre + 'skinIndex'].array, 4, false));
    g.setAttribute('skinWeight', new THREE.BufferAttribute(A[pre + 'skinWeight'].array, 4, true));
  }
  g.setIndex(new THREE.BufferAttribute(A[pre + 'index'].array, 1));
  if (skinned && header.morphs && header.morphs.length) {
    const mp = [], mn = [], mc = [];
    const hasColor = header.morphs.some((name) => A[`morph_${name}_dc`]);
    for (const name of header.morphs) {
      const ids = A[`morph_${name}_ids`].array, dp = A[`morph_${name}_dp`].array, dn = A[`morph_${name}_dn`].array;
      const dc = A[`morph_${name}_dc`] ? A[`morph_${name}_dc`].array : null;
      const P = new Float32Array(n * 3), N = new Float32Array(n * 3), C = hasColor ? new Float32Array(n * 3) : null;
      for (let k = 0; k < ids.length; k++) {
        const v = ids[k];
        for (let c = 0; c < 3; c++) { P[v * 3 + c] = dp[k * 3 + c] / 20000; N[v * 3 + c] = dn[k * 3 + c] / 63; }
        if (dc) for (let c = 0; c < 3; c++) C[v * 3 + c] = dc[k * 3 + c] / 32767;
      }
      const pa = new THREE.BufferAttribute(P, 3); pa.name = name;
      const na = new THREE.BufferAttribute(N, 3); na.name = name;
      mp.push(pa); mn.push(na);
      if (C) { const ca = new THREE.BufferAttribute(C, 3); ca.name = name; mc.push(ca); }
    }
    g.morphAttributes.position = mp;
    g.morphAttributes.normal = mn;
    if (hasColor) g.morphAttributes.color = mc;   // morph colors (relative): mouths open/close with the right color
    g.morphTargetsRelative = true;
  }
  g.computeBoundingBox();
  g.computeBoundingSphere();
  return g;
}

function material(id, header, def, opts) {
  const key = `${id}|${opts.envMap ? opts.envMap.uuid : ''}|${opts.heroFade ? 1 : 0}|${opts.globals ? 1 : 0}`;
  let m = matCache.get(key);
  if (!m) {
    m = createCharMaterial({ header, rim: def.rim, envMap: opts.envMap || null, globals: opts.globals || null, heroFade: !!opts.heroFade });
    matCache.set(key, m);
  }
  return m;
}

export function buildCharacter(defOrId, opts = {}) {
  const def = typeof defOrId === 'string' ? DEFS[defOrId] : defOrId;
  if (!def) throw new Error(`charRuntime: unknown character '${defOrId}'`);
  const id = def.id;
  const D = decoded(id);
  const header = D.header;
  const R = buildRig(def);
  const rig = R.rig;
  const J = R.joints;

  // Bone inverses in the bake's bind pose (root at identity).
  applyBindPose(R);
  const bones = R.bones.map((n) => J[n]);
  const inverses = bones.map((b) => b.matrixWorld.clone().invert());
  const bindWorld = Object.fromEntries(R.bones.map((n) => [n, J[n].matrixWorld.clone()]));
  resetPose(R);

  const mat = material(id, header, def, opts);
  const mesh = new THREE.SkinnedMesh(D.body, mat);
  mesh.name = `char:${id}`;
  rig.root.add(mesh);
  mesh.bind(optimizeSkeleton(new THREE.Skeleton(bones, inverses)), new THREE.Matrix4());
  mesh.castShadow = opts.shadows !== false;
  mesh.receiveShadow = !!opts.receiveShadow;
  const bb = D.body.boundingBox;
  mesh.boundingSphere = new THREE.Sphere(new THREE.Vector3(0, (bb.min.y + bb.max.y) / 2, 0), (bb.max.y - bb.min.y) * 0.75);
  mesh.frustumCulled = true;

  const face = new FaceController();
  if (D.body.morphAttributes.position) { mesh.updateMorphTargets(); face.setMesh(mesh); }

  // Rigid baked parts (brows, props): world bind geometry, re-expressed in the joint's local frame via a pivot.
  const parts = {};
  const partList = [];   // [{ name, pivot, mesh, bone }] for mergeCharacter
  for (const [name, p] of Object.entries(header.parts || {})) {
    const joint = J[p.bone] || J.head;
    const inv = bindWorld[p.bone || 'head'].clone().invert();
    const pivotW = new THREE.Vector3(...p.pivot);
    const pivotL = pivotW.clone().applyMatrix4(inv);
    const pivot = new THREE.Group();
    pivot.name = `part:${name}`;
    pivot.position.copy(pivotL);
    const pm = new THREE.Mesh(D.parts[name], mat);
    pm.name = name;
    // mesh local = inv(bind) * world, then minus pivot
    const m4 = new THREE.Matrix4().makeTranslation(-pivotL.x, -pivotL.y, -pivotL.z).multiply(inv);
    m4.decompose(pm.position, pm.quaternion, pm.scale);
    pm.castShadow = opts.shadows !== false;
    pm.receiveShadow = !!opts.receiveShadow;
    pivot.add(pm);
    joint.add(pivot);
    parts[name] = pivot;
    partList.push({ name, pivot, mesh: pm, bone: J[p.bone] ? p.bone : 'head', brow: /^brow/.test(name) });
    if (/^brow/.test(name)) face.addBrow(pivot, name.endsWith('L') ? 'L' : 'R');
  }

  // Attachments
  const builder = makeAttachBuilder({ joints: J, face, globals: opts.globals, envMap: opts.envMap, receiveShadow: !!opts.receiveShadow, rimColor: def.rim?.color || (def.kind === 'zombie' ? '#8FF3FF' : '#FFD9A0') });
  const ctx = { dims: rig.dims, header, A: def.anchors ? def.anchors({ dims: rig.dims }) : {} };
  if (def.attachments) def.attachments(builder, ctx);

  // Slots (ARCHITECTURE §12)
  const dims = rig.dims;
  const slot = (parent, name, pos) => {
    const o = new THREE.Object3D();
    o.name = `slot:${name}`;
    o.position.set(...pos);
    (parent || rig.root).add(o);
    return o;
  };
  const hb = hairInfo(D, R.bones.indexOf('head'), bindWorld.head);
  const S = def.slots || {};
  const slots = R.humanoid ? {
    head: slot(J.head, 'head', S.head || [0, hb.top, hb.cz]),
    handL: slot(J.handL, 'handL', S.handL || [0, -0.07, 0]),
    handR: slot(J.handR, 'handR', S.handR || [0, -0.07, 0]),
    footL: slot(J.footL, 'footL', S.footL || [0, -0.04, -0.05]),
    footR: slot(J.footR, 'footR', S.footR || [0, -0.04, -0.05]),
    back: slot(J.chest, 'back', S.back || [0, dims.torso * 0.15, 0.13]),
    wristL: slot(J.elbowL, 'wristL', S.wristL || [0, -dims.foreArm * 0.85, 0]),
    wristR: slot(J.elbowR, 'wristR', S.wristR || [0, -dims.foreArm * 0.85, 0]),
    neck: slot(J.neck, 'neck', S.neck || [0, 0, 0]),
    belt: slot(J.hips, 'belt', S.belt || [0, 0.05, -0.12]),
  } : Object.fromEntries(Object.entries(S).map(([k, v]) => [k, slot(J[v.joint], k, v.pos || [0, 0, 0])]));

  // Animator (humanoids use the engine Animator unchanged, wrapped for rest offsets + face)
  let animator = null;
  if (R.humanoid && opts.animator !== false) {
    const style = typeof opts.animator === 'string' || typeof opts.animator === 'object' ? opts.animator : (def.animStyle || (def.kind === 'zombie' ? 'zombie' : 'hero'));
    animator = new Animator(rig, style);
    const orig = animator.update.bind(animator);
    const armOut = def.armOut ?? 0.15;
    // [joint, [x, y, z]] pairs resolved once (was Object.entries per frame)
    const offs = def.poseOffset ? Object.entries(def.poseOffset).filter(([n]) => J[n]).map(([n, e]) => [J[n], e]) : null;
    animator.update = (dt, st) => {
      orig(dt, st);
      applyRestOffsets(J, armOut, offs);
      face.update(dt);
    };
  } else if (def.createAnimator) {
    animator = def.createAnimator(rig, { face, THREE });
  }

  const group = new THREE.Group();
  group.name = `char:${id}`;
  group.add(rig.root);
  const layer = opts.layer ?? (def.kind === 'zombie' ? LAYERS.ZOMBIES : null);
  if (layer != null) group.traverse((o) => o.layers.set(layer));
  group.traverse((o) => { if (o.isMesh) o.userData.keepColor = true; });

  const res = {
    group, rig, animator, skinnedMesh: mesh, slots, face, hairBounds: hb.radius, parts, def, header,
    update(dt, state = {}) { if (animator) animator.update(dt, state); else face.update(dt); },
  };
  if (opts.merge && charOpt.merge) {
    try {
      mergeCharacter(res, D, R.bones, partList);
    } catch (err) {
      console.warn(`[charRuntime] merge '${id}' failed (drawn unmerged)`, err);
    }
  }
  return res;
}

// Arms: push out from the torso while hanging (fades as the arm swings up/forward); plus custom offsets.
function applyRestOffsets(J, armOut, offs) {
  if (armOut) {
    const fl = Math.max(0, 1 - Math.abs(J.shoulderL.rotation.x) / 1.3);
    const fr = Math.max(0, 1 - Math.abs(J.shoulderR.rotation.x) / 1.3);
    J.shoulderL.rotation.z -= armOut * fl;
    J.shoulderR.rotation.z += armOut * fr;
  }
  if (offs) for (let i = 0; i < offs.length; i++) {
    const j = offs[i][0], e = offs[i][1];
    j.rotation.x += e[0]; j.rotation.y += e[1]; j.rotation.z += e[2];
  }
}

// Head-bound vertices -> slot height and bounding radius for head costumes (GDD §4: hair bounds x 1.05).
function hairInfo(D, headIdx, headBind) {
  if (D.hair) return D.hair;
  const g = D.body;
  const P = g.attributes.position, SI = g.attributes.skinIndex, SW = g.attributes.skinWeight;
  const inv = headBind.clone().invert();
  const v = new THREE.Vector3();
  let top = 0.3, cz = 0, n = 0, r = 0.2;
  const pts = [];
  if (SI && headIdx >= 0) {
    for (let i = 0; i < P.count; i++) {
      let w = 0;
      for (let k = 0; k < 4; k++) if (SI.array[i * 4 + k] === headIdx) w += SW.array[i * 4 + k];
      if (w < 200) continue;
      v.fromBufferAttribute(P, i).applyMatrix4(inv);
      pts.push(v.clone());
    }
  }
  if (pts.length) {
    top = Math.max(...pts.map((p) => p.y));
    cz = pts.reduce((a, p) => a + p.z, 0) / pts.length;
    const c = new THREE.Vector3(0, top * 0.55, cz);
    r = Math.max(...pts.map((p) => p.distanceTo(c)));
    n = pts.length;
  }
  D.hair = { top, cz, radius: r, n };
  return D.hair;
}

// ---------------------------------------------------------------------------------------------------------------
// Skeleton upload dedupe: a patched Skeleton.update that flags the bone texture for upload only when a bone matrix
// changed. three updates a skeleton once per render() call it is drawn in (screens' feed passes + the main pass), so
// the same pose used to be re-uploaded several times a frame, and frozen / paused characters every frame.
const _bm = new THREE.Matrix4();
const _ident = new THREE.Matrix4();
const protoUpdate = THREE.Skeleton.prototype.update;
function dedupeUpdate() {
  if (!charOpt.dedupe) { protoUpdate.call(this); return; }
  const bones = this.bones, inv = this.boneInverses, out = this.boneMatrices;
  let changed = false;
  for (let i = 0, n = bones.length; i < n; i++) {
    _bm.multiplyMatrices(bones[i] ? bones[i].matrixWorld : _ident, inv[i]);
    const e = _bm.elements, o = i * 16;
    for (let k = 0; k < 16; k++) {
      const v = Math.fround(e[k]);
      if (out[o + k] !== v) { out[o + k] = v; changed = true; }
    }
  }
  if (changed && this.boneTexture !== null) this.boneTexture.needsUpdate = true;
}
export function optimizeSkeleton(skeleton) {
  if (skeleton && skeleton.update !== dedupeUpdate) skeleton.update = dedupeUpdate;
  return skeleton;
}
// Patches the skeletons of every SkinnedMesh under root (e.g. after geo.skinRig).
export function optimizeSkeletons(root) {
  root.traverse((o) => { if (o.isSkinnedMesh && o.skeleton) optimizeSkeleton(o.skeleton); });
}

// Replaces the body's skeleton by one with extra bones appended (existing skin indices stay valid). Every skinned
// mesh already bound to the old skeleton (listed in c._skinned) follows.
function extendSkeleton(c, nodes, inverses) {
  const body = c.skinnedMesh;
  const old = body.skeleton;
  const sk = optimizeSkeleton(new THREE.Skeleton(old.bones.concat(nodes), old.boneInverses.concat(inverses)));
  for (const m of [body, ...(c._skinned || [])]) if (m.skeleton === old) m.skeleton = sk;
  return sk;
}

// Hero merge (buildCharacter opts.merge): rigid baked parts join the body mesh (brow pivots become extra bones, static
// parts ride their joint), then the attachments merge per material (animated face nodes = extra bones).
function mergeCharacter(c, D, boneNames, partList) {
  const body = c.skinnedMesh;
  const face = c.face;
  const faceBones = [];
  for (const e of face.eyes) faceBones.push(e.ball, e.upper, e.lower);
  // parts -> body geometry (computed first: nothing in the scene changes if this throws)
  const specs = [];
  const browBones = [], browInv = [];
  for (const p of partList) {
    if (!p.mesh.parent || !D.parts[p.name]) continue;
    if (p.brow) {
      p.mesh.updateMatrix();
      browBones.push(p.pivot);
      browInv.push(p.mesh.matrix.clone());   // pivot world x mesh local = the part's world transform
      specs.push({ name: p.name, bi: boneNames.length + browBones.length - 1, mesh: p.mesh });
    } else {
      const bi = boneNames.indexOf(p.bone);
      if (bi >= 0) specs.push({ name: p.name, bi, mesh: p.mesh });
    }
  }
  const merged = specs.length ? mergedBody(D, specs) : null;
  if (browBones.length) extendSkeleton(c, browBones, browInv);
  if (merged) {
    body.geometry = merged;
    body.updateMorphTargets();
    for (const s of specs) s.mesh.removeFromParent();
  }
  mergeAttachments(c, { bones: faceBones, flagProxy: true });
}

const normMax = (T) => (T === Uint8Array ? 255 : T === Uint16Array ? 65535 : T === Int8Array ? 127 : T === Int16Array ? 32767 : 1);

// Body geometry + rigid part geometries (all in the bake's bind space) in one skinned geometry, cached per character.
// Parts get skinIndex = their bone, weight 1, zero morph deltas; vertex data is copied bit for bit.
function mergedBody(D, specs) {
  const key = specs.map((s) => `${s.name}:${s.bi}`).join(',');
  D.mergedBodies = D.mergedBodies || {};
  if (D.mergedBodies[key]) return D.mergedBodies[key];
  const B = D.body;
  const srcs = [B, ...specs.map((s) => D.parts[s.name])];
  const counts = srcs.map((g) => g.attributes.position.count);
  const total = counts.reduce((a, b) => a + b, 0);
  const g = new THREE.BufferGeometry();
  for (const [name, attr] of Object.entries(B.attributes)) {
    const T = attr.array.constructor, n = attr.itemSize;
    const arr = new T(total * n);
    arr.set(attr.array, 0);
    let off = counts[0];
    specs.forEach((s, k) => {
      const pa = srcs[k + 1].attributes[name];
      const cnt = counts[k + 1];
      if (pa) {
        if (pa.itemSize !== n || pa.array.constructor !== T || pa.normalized !== attr.normalized || pa.isInterleavedBufferAttribute) throw new Error(`part ${s.name}: '${name}' layout differs`);
        arr.set(pa.array, off * n);
      } else if (name === 'skinIndex') {
        for (let i = 0; i < cnt; i++) arr[(off + i) * n] = s.bi;
      } else if (name === 'skinWeight') {
        const one = attr.normalized ? normMax(T) : 1;
        for (let i = 0; i < cnt; i++) arr[(off + i) * n] = one;
      } else throw new Error(`part ${s.name} lacks '${name}'`);
      off += cnt;
    });
    g.setAttribute(name, new THREE.BufferAttribute(arr, n, attr.normalized));
  }
  for (const [name, list] of Object.entries(B.morphAttributes)) {
    g.morphAttributes[name] = list.map((ma) => {
      const arr = new ma.array.constructor(total * ma.itemSize);
      arr.set(ma.array, 0);
      const a = new THREE.BufferAttribute(arr, ma.itemSize, ma.normalized);
      a.name = ma.name;
      return a;
    });
  }
  g.morphTargetsRelative = B.morphTargetsRelative;
  const idxTotal = srcs.reduce((a, s) => a + s.index.count, 0);
  const I = total > 65535 ? new Uint32Array(idxTotal) : new Uint16Array(idxTotal);
  let io = 0, vo = 0;
  srcs.forEach((s, k) => {
    const si = s.index.array;
    for (let i = 0; i < si.length; i++) I[io + i] = si[i] + vo;
    io += si.length;
    vo += counts[k];
  });
  g.setIndex(new THREE.BufferAttribute(I, 1));
  g.computeBoundingBox();
  g.computeBoundingSphere();
  g.name = 'char+parts';
  D.mergedBodies[key] = g;
  return g;
}

// ---------------------------------------------------------------------------------------------------------------
// mergeAttachments(c, { bones, flagProxy }) -> merged meshes. Call right after buildCharacter (rest pose), after
// setting materials / shadow flags. Every rigid attachment mesh under a joint (through static groups; anything flagged
// userData.dynamic / noMerge, hidden, with children, multi-material, skinned, instanced or morphing is left alone)
// joins one mesh per (material, shadow flags, layers, renderOrder, frustumCulled):
//   - all members driven by ONE node (a joint, or an animated node listed in opts.bones): a plain Mesh under that
//     node, geometry in its space (same transforms as before, no skinning);
//   - members driven by several nodes (eyeballs, lids, pupils, casters...): a SkinnedMesh bound to the BODY's
//     skeleton (animated nodes appended as extra bones), so a character keeps one skeleton / one bone upload.
// opts.flagProxy (heroes): the largest source mesh stays in place, hidden, and the merged mesh reads castShadow /
// receiveShadow / frustumCulled from it, so code that walks the hero setting those flags per mesh (player shadow
// sizing, the menu's set) gets the same result as on the separate meshes.
const _mA = new THREE.Matrix4();
const _mB = new THREE.Matrix4();
const _v = new THREE.Vector3();
function attachGeometry(mesh, matrix, withColor, boneIndex) {
  const src = mesh.geometry;
  const n = src.attributes.position.count;
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', src.attributes.position.clone());
  if (src.attributes.normal) g.setAttribute('normal', src.attributes.normal.clone());
  g.setAttribute('uv', src.attributes.uv ? src.attributes.uv.clone() : new THREE.BufferAttribute(new Float32Array(n * 2), 2));
  if (withColor) g.setAttribute('color', src.attributes.color ? src.attributes.color.clone() : new THREE.BufferAttribute(new Float32Array(n * 3).fill(1), 3));
  if (src.index) g.setIndex(src.index.clone());
  else { const I = new Uint32Array(n); for (let i = 0; i < n; i++) I[i] = i; g.setIndex(new THREE.BufferAttribute(I, 1)); }
  if (!g.attributes.normal) g.computeVertexNormals();
  g.applyMatrix4(matrix);
  if (matrix.determinant() < 0) {
    const idx = g.index.array;
    for (let i = 0; i < idx.length; i += 3) { const t = idx[i + 1]; idx[i + 1] = idx[i + 2]; idx[i + 2] = t; }
  }
  if (boneIndex >= 0) {
    const si = new Uint16Array(n * 4), sw = new Float32Array(n * 4);
    for (let i = 0; i < n; i++) { si[i * 4] = boneIndex; sw[i * 4] = 1; }
    g.setAttribute('skinIndex', new THREE.Uint16BufferAttribute(si, 4));
    g.setAttribute('skinWeight', new THREE.Float32BufferAttribute(sw, 4));
  }
  return g;
}

function worldRadius(o) {
  const g = o.geometry;
  if (!g.boundingSphere) g.computeBoundingSphere();
  o.getWorldScale(_v);
  return g.boundingSphere.radius * Math.max(Math.abs(_v.x), Math.abs(_v.y), Math.abs(_v.z));
}

export function mergeAttachments(c, opts = {}) {
  const body = c.skinnedMesh, rig = c.rig, root = rig.root;
  const out = [];
  if (!body || !body.skeleton) return out;
  const extra = (opts.bones || []).filter(Boolean);
  const boneSet = new Set([...Object.values(rig.joints), ...extra]);
  root.updateMatrixWorld(true);
  const groups = new Map();
  root.traverse((o) => {
    if (!o.isMesh || o === body || o.isSkinnedMesh || o.isInstancedMesh || o.isBatchedMesh) return;
    if (Array.isArray(o.material) || !o.material || o.children.length || o.morphTargetInfluences) return;
    const u = o.material.userData && o.material.userData.uniforms;
    if (u && u.uMatA) return;   // char-material parts (custom vertex attributes): mergeCharacter's job
    let p = o;
    for (; p && !boneSet.has(p); p = p.parent) if (!p.visible || p.userData.dynamic || p.userData.noMerge) return;
    if (!p) return;
    const k = `${o.material.uuid}|${o.castShadow}|${o.receiveShadow}|${o.layers.mask}|${o.renderOrder}|${o.frustumCulled}`;
    let list = groups.get(k);
    if (!list) groups.set(k, (list = []));
    list.push([o, p]);
  });
  // plan (and build every geometry) before touching the scene
  const skel0 = body.skeleton;
  const need = [];
  const plan = [];
  for (const list of groups.values()) {
    if (list.length < 2) continue;
    const owners = new Set(list.map((e) => e[1]));
    const skinned = owners.size > 1;
    if (skinned) for (const ow of owners) if (!skel0.bones.includes(ow) && !need.includes(ow)) need.push(ow);
    plan.push({ list, skinned, owner: list[0][1] });
  }
  if (!plan.length) return out;
  const allBones = skel0.bones.concat(need);
  const allInv = skel0.boneInverses.concat(need.map(() => new THREE.Matrix4()));
  for (const P of plan) {
    const mat = P.list[0][0].material;
    const geos = P.list.map(([o, ow]) => {
      _mA.copy(ow.matrixWorld).invert().multiply(o.matrixWorld);   // mesh -> driving node
      if (!P.skinned) return attachGeometry(o, _mA, !!mat.vertexColors, -1);
      const bi = allBones.indexOf(ow);
      // body joints: into the bake's bind space (their bone inverse is the inverse bind matrix); extra bones: identity
      _mB.copy(allInv[bi]).invert().multiply(_mA);
      return attachGeometry(o, _mB, !!mat.vertexColors, bi);
    });
    P.geo = mergeGeometries(geos, false);
    geos.forEach((x) => x.dispose());
    if (!P.geo) throw new Error('mergeAttachments: incompatible attributes');
  }
  // apply
  const sk = need.length ? extendSkeleton(c, need, allInv.slice(skel0.bones.length)) : skel0;
  for (const P of plan) {
    const src = P.list[0][0];
    const mat = src.material;
    let m;
    if (P.skinned) {
      m = new THREE.SkinnedMesh(P.geo, mat);
      root.add(m);
      m.bind(sk, new THREE.Matrix4());
      m.boundingSphere = body.boundingSphere ? body.boundingSphere.clone() : null;
      (c._skinned || (c._skinned = [])).push(m);
    } else {
      P.geo.computeBoundingSphere();
      m = new THREE.Mesh(P.geo, mat);
      P.owner.add(m);
    }
    m.name = `merged:${mat.name || mat.type}`;
    m.castShadow = src.castShadow;
    m.receiveShadow = src.receiveShadow;
    m.frustumCulled = src.frustumCulled;
    m.layers.mask = src.layers.mask;
    m.renderOrder = src.renderOrder;
    Object.assign(m.userData, src.userData);
    m.userData.mergedFrom = P.list.length;
    let rep = null;
    if (opts.flagProxy) {
      let best = -1;
      for (const [o] of P.list) { const r = worldRadius(o); if (r > best) { best = r; rep = o; } }
      // The proxy is never drawn: code that toggles `visible` on every hero mesh (player.js hide-on-fade, the
      // sponsors' commercial camera) must not bring it back on top of the merged mesh (glints / lenses would
      // blend twice). Clones (perks.cloneHero, SkeletonUtils) copy the plain value false.
      Object.defineProperty(rep, 'visible', { get: () => false, set: () => {}, configurable: true, enumerable: true });
      // Setters are ignored on purpose: a walk that sets the flag on every mesh reaches the proxy too (player.js
      // setShadowCasting: radius rule on the proxy, "skinned always casts" would wrongly hit the merged mesh).
      for (const k of ['castShadow', 'receiveShadow', 'frustumCulled']) {
        Object.defineProperty(m, k, { get: () => rep[k], set: () => {}, configurable: true, enumerable: true });
      }
    }
    for (const [o] of P.list) if (o !== rep) o.removeFromParent();
    out.push(m);
  }
  return out;
}
