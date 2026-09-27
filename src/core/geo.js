// Geometry helpers (ARCHITECTURE §6): cached primitive builders, fake-AO baking, static merging (per area, or
// per rig joint via mergeRig, or rigid-skinned per material via skinRig) and a mesh() convenience factory.
// Cached geometries are SHARED: never mutate one you got from here (clone it first). Everything is bevelled/rounded by default in keeping with GDD §3.4.

import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';

const cache = new Map();
const r3 = (n) => Math.round(n * 1000) / 1000;

function cachedGeo(key, make) {
  let g = cache.get(key);
  if (!g) {
    g = make();
    g.name = key;
    cache.set(key, g);
  }
  return g;
}

export function roundedBox(w, h, d, r = 0.05, seg = 3) {
  return cachedGeo(`rbox|${r3(w)}|${r3(h)}|${r3(d)}|${r3(r)}|${seg}`, () => new RoundedBoxGeometry(w, h, d, seg, r));
}

export function box(w, h, d) {
  return cachedGeo(`box|${r3(w)}|${r3(h)}|${r3(d)}`, () => new THREE.BoxGeometry(w, h, d));
}

// Capsule along Y; total height = len + 2r.
export function capsule(r, len, cap = 8, rad = 12) {
  return cachedGeo(`caps|${r3(r)}|${r3(len)}|${cap}|${rad}`, () => new THREE.CapsuleGeometry(r, len, cap, rad));
}

export function cylinder(rt, rb, h, seg = 16) {
  return cachedGeo(`cyl|${r3(rt)}|${r3(rb)}|${r3(h)}|${seg}`, () => new THREE.CylinderGeometry(rt, rb, h, seg));
}

export function sphere(r, ws = 20, hs = 14) {
  return cachedGeo(`sph|${r3(r)}|${ws}|${hs}`, () => new THREE.SphereGeometry(r, ws, hs));
}

export function torus(r, tube, rs = 10, ts = 24, arc = Math.PI * 2) {
  return cachedGeo(`tor|${r3(r)}|${r3(tube)}|${rs}|${ts}|${r3(arc)}`, () => new THREE.TorusGeometry(r, tube, rs, ts, arc));
}

export function plane(w, h, sx = 1, sy = 1) {
  return cachedGeo(`plane|${r3(w)}|${r3(h)}|${sx}|${sy}`, () => new THREE.PlaneGeometry(w, h, sx, sy));
}

// Lathe around Y. points: [[radius, y], ...] or Vector2[] (bottom to top).
export function lathe(points, seg = 24) {
  const pts = points.map((p) => (p.isVector2 ? [p.x, p.y] : p));
  return cachedGeo(`lathe|${JSON.stringify(pts)}|${seg}`, () =>
    new THREE.LatheGeometry(pts.map(([x, y]) => new THREE.Vector2(x, y)), seg));
}

// Tube through points ([[x,y,z], ...] or Vector3[]) along a Catmull-Rom curve.
export function tube(points, r, seg = 24, radial = 8, closed = false) {
  const pts = points.map((p) => (p.isVector3 ? [p.x, p.y, p.z] : p));
  return cachedGeo(`tube|${JSON.stringify(pts)}|${r3(r)}|${seg}|${radial}|${closed}`, () => {
    const curve = new THREE.CatmullRomCurve3(pts.map(([x, y, z]) => new THREE.Vector3(x, y, z)), closed);
    return new THREE.TubeGeometry(curve, seg, r, radial, closed);
  });
}

// Extruded shape with a soft bevel (not cached: shapes are objects; cache the result yourself if reused).
export function extrudeShape(shape, depth, bevel = 0.02) {
  const g = new THREE.ExtrudeGeometry(shape, {
    depth, bevelEnabled: bevel > 0, bevelThickness: bevel, bevelSize: bevel, bevelSegments: 3, curveSegments: 16,
  });
  g.translate(0, 0, -depth / 2);
  return g;
}

// Fake AO (GDD §3.5): returns a cached copy of `geometry` with vertex colors darkening its bottom part.
// Use with a material created with { vertexColors:true }. y0/y1 are local heights of the fade band.
export function withAO(geometry, { y0 = null, y1 = null, strength = 0.45, tint = '#3A2A5A' } = {}) {
  return cachedGeo(`ao|${geometry.uuid}|${y0}|${y1}|${strength}|${tint}`, () => {
    const g = geometry.clone();
    g.computeBoundingBox();
    const bb = g.boundingBox;
    const a = y0 ?? bb.min.y;
    const b = y1 ?? bb.min.y + (bb.max.y - bb.min.y) * 0.3;
    const pos = g.attributes.position;
    const col = new Float32Array(pos.count * 3);
    const t = new THREE.Color(tint);
    const c = new THREE.Color();
    for (let i = 0; i < pos.count; i++) {
      const k = 1 - THREE.MathUtils.smoothstep(pos.getY(i), a, b);
      c.setRGB(1, 1, 1).lerp(t, k * strength);
      col[i * 3] = c.r; col[i * 3 + 1] = c.g; col[i * 3 + 2] = c.b;
    }
    g.setAttribute('color', new THREE.BufferAttribute(col, 3));
    return g;
  });
}

// Mesh factory. opts: { pos:[x,y,z], rot:[x,y,z], scale:number|[x,y,z], cast=true, receive=true, name }
export function mesh(geo, mat, opts = {}) {
  const m = new THREE.Mesh(geo, mat);
  const { pos, rot, scale, cast = true, receive = true, name } = opts;
  if (pos) m.position.set(pos[0], pos[1], pos[2]);
  if (rot) m.rotation.set(rot[0], rot[1], rot[2]);
  if (scale !== undefined) {
    if (typeof scale === 'number') m.scale.setScalar(scale);
    else m.scale.set(scale[0], scale[1], scale[2]);
  }
  m.castShadow = cast;
  m.receiveShadow = receive;
  if (name) m.name = name;
  return m;
}

// ---------------------------------------------------------------------------------------------------------
// Static merging: one mesh per (material, shadow flags, layers) under `root`. Meshes flagged
// userData.dynamic / userData.noMerge (or under such an ancestor), meshes with children, instanced,
// skinned or morphing meshes are left alone. Returns the number of source meshes merged away.

const _inv = new THREE.Matrix4();
const _m = new THREE.Matrix4();

function blocked(o, root) {
  for (let p = o; p && p !== root; p = p.parent) {
    if (p.userData.dynamic || p.userData.noMerge) return true;
  }
  return false;
}

function prepare(mesh, wantColor) {
  const src = mesh.geometry;
  const g = new THREE.BufferGeometry();
  const count = src.attributes.position.count;
  g.setAttribute('position', src.attributes.position.clone());
  if (src.attributes.normal) g.setAttribute('normal', src.attributes.normal.clone());
  g.setAttribute('uv', src.attributes.uv ? src.attributes.uv.clone() : new THREE.BufferAttribute(new Float32Array(count * 2), 2));
  if (wantColor) {
    g.setAttribute('color', src.attributes.color ? src.attributes.color.clone()
      : new THREE.BufferAttribute(new Float32Array(count * 3).fill(1), 3));
  }
  if (src.index) g.setIndex(src.index.clone());
  else g.setIndex([...Array(count).keys()]);
  if (!g.attributes.normal) g.computeVertexNormals();
  _m.multiplyMatrices(_inv, mesh.matrixWorld);
  g.applyMatrix4(_m);
  if (_m.determinant() < 0) {
    // Mirrored transform: restore winding so faces stay front-facing.
    const idx = g.index.array;
    for (let i = 0; i < idx.length; i += 3) { const t = idx[i + 1]; idx[i + 1] = idx[i + 2]; idx[i + 2] = t; }
  }
  return g;
}

export function mergeByMaterial(root) {
  root.updateMatrixWorld(true);
  _inv.copy(root.matrixWorld).invert();
  const groups = new Map();
  root.traverse((o) => {
    if (o === root || !o.isMesh || o.isInstancedMesh || o.isSkinnedMesh || o.isBatchedMesh) return;
    if (Array.isArray(o.material) || o.children.length || !o.visible || o.morphTargetInfluences) return;
    if (blocked(o, root)) return;
    const key = `${o.material.uuid}|${o.castShadow}|${o.receiveShadow}|${o.layers.mask}|${o.renderOrder}`;
    let list = groups.get(key);
    if (!list) groups.set(key, (list = []));
    list.push(o);
  });
  let merged = 0;
  for (const list of groups.values()) {
    if (list.length < 2) continue;
    const src = list[0];
    const geos = list.map((m) => prepare(m, !!src.material.vertexColors));
    const g = mergeGeometries(geos, false);
    geos.forEach((x) => x.dispose());
    if (!g) continue;
    g.computeBoundingSphere();
    const out = new THREE.Mesh(g, src.material);
    out.name = `merged:${src.material.name || src.material.type}`;
    out.castShadow = src.castShadow;
    out.receiveShadow = src.receiveShadow;
    out.layers.mask = src.layers.mask;
    out.renderOrder = src.renderOrder;
    root.add(out);
    for (const m of list) m.parent.remove(m);
    merged += list.length;
  }
  return merged;
}

// Merges every rig joint's own static meshes per material, in that joint's space, so an animated character
// costs one draw call per joint and material instead of one per primitive. Meshes under a nested joint stay
// with that joint; anything flagged userData.dynamic / noMerge (springy hair, swappable parts) is kept as is.
export function mergeRig(rig) {
  const joints = Object.values(rig.joints);
  const saved = joints.map((j) => j.userData.noMerge);
  for (const j of joints) j.userData.noMerge = true;
  let merged = 0;
  for (const j of joints) merged += mergeByMaterial(j);
  joints.forEach((j, i) => { j.userData.noMerge = saved[i]; });
  return merged;
}

// Rigid skinning merge (cheaper than mergeRig): every static mesh under the rig's joints goes into ONE SkinnedMesh
// per (material, shadow flags, layers, renderOrder), each vertex bound 100% to its nearest joint, so an animated
// character costs one draw call per material instead of one per joint and material. The joints stay the bones
// (the Animator drives them unchanged). Meshes flagged userData.dynamic / noMerge (or under such a node), meshes
// with children, instanced / skinned / morphing meshes are left alone; Groups and slots stay where they are.
// Call it right after building, with the rig in its rest pose. opts.radius = bounding-sphere radius (default
// 0.75 x rig height). opts.recolor = a vertex-coloured material (e.g. mats.toon('#fff', {vertexColors:true, ...})):
// every opaque, untextured toon mesh is merged into it with its colour baked per vertex (one draw for all of
// them; roughness/rim differences are dropped). Returns the SkinnedMeshes it created.
export function skinRig(rig, { radius, recolor = null } = {}) {
  const names = Object.keys(rig.joints);
  const bones = names.map((n) => rig.joints[n]);
  const index = new Map(bones.map((b, i) => [b, i]));
  rig.root.updateMatrixWorld(true);
  _inv.copy(rig.root.matrixWorld).invert();
  const groups = new Map();
  for (const bone of bones) {
    bone.traverse((o) => {
      if (!o.isMesh || o.isSkinnedMesh || o.isInstancedMesh || o.isBatchedMesh) return;
      if (Array.isArray(o.material) || o.children.length || !o.visible || o.morphTargetInfluences) return;
      let p = o;
      for (; p && !index.has(p); p = p.parent) if (p.userData.dynamic || p.userData.noMerge) return;
      if (p !== bone) return;
      const mm = o.material;
      const rc = recolor && mm.userData.daToon && !mm.map && !mm.transparent && mm !== recolor;
      const key = `${rc ? recolor.uuid : mm.uuid}|${o.castShadow}|${o.receiveShadow}|${o.layers.mask}|${o.renderOrder}`;
      let list = groups.get(key);
      if (!list) groups.set(key, (list = []));
      list.push([o, index.get(bone), rc]);
    });
  }
  const inverses = bones.map((b) => new THREE.Matrix4().multiplyMatrices(_inv, b.matrixWorld).invert());
  const skeleton = new THREE.Skeleton(bones, inverses);
  const h = rig.dims ? rig.dims.height : 1.7;
  const sphere = new THREE.Sphere(new THREE.Vector3(0, h * 0.5, 0), radius ?? h * 0.75);
  const out = [];
  for (const list of groups.values()) {
    const src = list[0][0];
    const mat = list[0][2] ? recolor : src.material;
    const geos = list.map(([o, bi, rc]) => {
      const g = prepare(o, !!mat.vertexColors);
      if (rc) {
        const c = g.attributes.color.array, k = o.material.color;
        for (let i = 0; i < c.length; i += 3) { c[i] *= k.r; c[i + 1] *= k.g; c[i + 2] *= k.b; }
      }
      const n = g.attributes.position.count;
      const si = new Uint16Array(n * 4), sw = new Float32Array(n * 4);
      for (let i = 0; i < n; i++) { si[i * 4] = bi; sw[i * 4] = 1; }
      g.setAttribute('skinIndex', new THREE.Uint16BufferAttribute(si, 4));
      g.setAttribute('skinWeight', new THREE.Float32BufferAttribute(sw, 4));
      return g;
    });
    const g = mergeGeometries(geos, false);
    geos.forEach((x) => x.dispose());
    if (!g) continue;
    const m = new THREE.SkinnedMesh(g, mat);
    m.name = `skinned:${mat.name || mat.type}`;
    m.castShadow = src.castShadow;
    m.receiveShadow = src.receiveShadow;
    m.layers.mask = src.layers.mask;
    m.renderOrder = src.renderOrder;
    Object.assign(m.userData, src.userData);
    rig.root.add(m);
    m.bind(skeleton, new THREE.Matrix4());
    m.boundingSphere = sphere.clone();
    for (const [o] of list) o.parent.remove(o);
    out.push(m);
  }
  return out;
}
