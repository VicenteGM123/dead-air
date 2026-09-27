// World-space UV batching for the station graybox (level.js). Faces, boxes and planar polygons are collected
// per (group, surface) bucket and baked into ONE BufferGeometry per bucket whose UVs are world metres divided
// by the surface's tile size: textures run continuously across wall pieces, corners and floors of any size,
// nothing stretches, and coplanar pieces shade identically (no visible seams or z-fight between them).
// Every vertex carries a color used as fake AO (GDD §3.5): wall faces darken toward the floor (and slightly
// under the ceiling), floors and ceilings darken along their edges, tinted plum instead of black.
//
// UV convention (u to the viewer's right, v up; floors: v = north):
//   +x face u=-z  -x face u=z  +z face u=x  -z face u=-x  (v=y)   +y face u=x v=-z   -y face u=x v=z
//
// API
//   new Batch(surfaces)          surfaces.get(key) → { mat, tile:[u,v] } (materials use vertexColors)
//   vface(group, key, axis, at, sign, a0, a1, y0, y1, { ao=0, top=null, topAo=0.18 })
//       vertical rectangle on the plane <axis> = at (axis 'x'|'z'), a0..a1 along the other horizontal axis,
//       y0..y1; sign ±1 = normal direction along <axis>. ao = darkening at y = 0 fading out by AO_H; top =
//       ceiling height (adds a light darkening just under it).
//   hface(group, key, x0, z0, x1, z1, y, up, { border=0, ao=0 })   horizontal rectangle facing up or down;
//       border > 0 adds an inner ring `border` m wide whose outer edge is darkened by `ao`.
//   box(group, key, min, max, { skip:{px,nx,py,ny,pz,nz}, ao=0 })   the faces of an AABB (minus `skip`)
//   poly(group, key, pts:[[x,y,z],...], normal:[x,y,z], ao?:[k...])  convex planar polygon (triangle fan),
//       UVs projected on the plane of the dominant axis of `normal`
//   build(parentOf:(group)=>Object3D, castOf:(group,key)=>bool) → Mesh[]  one mesh per non-empty bucket
//   AO_TINT, AO_H

import * as THREE from 'three';

export const AO_H = 0.9;
export const AO_TINT = new THREE.Color('#3A2A5A');

const smooth = (e0, e1, x) => {
  const t = Math.min(1, Math.max(0, (x - e0) / (e1 - e0)));
  return t * t * (3 - 2 * t);
};

export class Batch {
  constructor(surfaces) {
    this.surfaces = surfaces;
    this.buckets = new Map();
  }

  _bucket(group, key) {
    const id = `${group}|${key}`;
    let b = this.buckets.get(id);
    if (!b) {
      b = { group, key, tile: this.surfaces.get(key).tile, pos: [], nrm: [], uv: [], col: [], idx: [] };
      this.buckets.set(id, b);
    }
    return b;
  }

  // One vertex: position, normal, world UV from the normal's dominant axis, AO darkening k (0..1).
  _vert(b, x, y, z, nx, ny, nz, k) {
    const [tu, tv] = b.tile;
    const ax = Math.abs(nx), ay = Math.abs(ny), az = Math.abs(nz);
    let u, v;
    if (ay >= ax && ay >= az) { u = x; v = ny > 0 ? -z : z; } else if (ax >= az) { u = nx > 0 ? -z : z; v = y; } else { u = nz > 0 ? x : -x; v = y; }
    b.pos.push(x, y, z);
    b.nrm.push(nx, ny, nz);
    b.uv.push(u / tu, v / tv);
    b.col.push(1 + (AO_TINT.r - 1) * k, 1 + (AO_TINT.g - 1) * k, 1 + (AO_TINT.b - 1) * k);
    return b.pos.length / 3 - 1;
  }

  // Quad from 4 vertex indices in counter-clockwise order seen from the front.
  _quad(b, a, c, d, e) {
    b.idx.push(a, c, d, a, d, e);
  }

  vface(group, key, axis, at, sign, a0, a1, y0, y1, opts = {}) {
    if (y1 - y0 < 1e-4 || a1 - a0 < 1e-4) return;
    const { ao = 0, top = null, topAo = 0.18 } = opts;
    const b = this._bucket(group, key);
    const ys = [y0];
    if (ao > 0 && AO_H > y0 && AO_H < y1) ys.push(AO_H);
    if (top !== null && top - 0.6 > ys[ys.length - 1] + 1e-3 && top - 0.6 < y1) ys.push(top - 0.6);
    ys.push(y1);
    const kAt = (y) => Math.min(0.85, ao * (1 - smooth(0, AO_H, y)) + (top !== null ? topAo * smooth(top - 0.6, top, y) : 0));
    const nx = axis === 'x' ? sign : 0, nz = axis === 'z' ? sign : 0;
    // Along-axis endpoints ordered so the winding faces +normal.
    const flip = axis === 'x' ? sign > 0 : sign < 0;
    const s0 = flip ? a1 : a0, s1 = flip ? a0 : a1;
    const P = (s, y) => (axis === 'x' ? [at, y, s] : [s, y, at]);
    let prev = null;
    for (const y of ys) {
      const k = kAt(y);
      const p = P(s0, y), q = P(s1, y);
      const row = [this._vert(b, ...p, nx, 0, nz, k), this._vert(b, ...q, nx, 0, nz, k)];
      if (prev) this._quad(b, prev[0], prev[1], row[1], row[0]);
      prev = row;
    }
  }

  hface(group, key, x0, z0, x1, z1, y, up, opts = {}) {
    if (x1 - x0 < 1e-4 || z1 - z0 < 1e-4) return;
    const { border = 0, ao = 0 } = opts;
    const b = this._bucket(group, key);
    const bx = Math.min(border, (x1 - x0) / 2 - 1e-3), bz = Math.min(border, (z1 - z0) / 2 - 1e-3);
    const xs = border > 0 ? [x0, x0 + bx, x1 - bx, x1] : [x0, x1];
    const zs = border > 0 ? [z0, z0 + bz, z1 - bz, z1] : [z0, z1];
    const ny = up ? 1 : -1;
    const grid = zs.map((z, j) => xs.map((x, i) => {
      const edge = i === 0 || j === 0 || i === xs.length - 1 || j === zs.length - 1;
      return this._vert(b, x, y, z, 0, ny, 0, border > 0 && edge ? ao : 0);
    }));
    for (let j = 0; j < zs.length - 1; j++) {
      for (let i = 0; i < xs.length - 1; i++) {
        const a = grid[j][i], c = grid[j][i + 1], d = grid[j + 1][i + 1], e = grid[j + 1][i];
        // Seen from +y the (x→, z↓) grid runs clockwise; flip for the up-facing side.
        if (up) this._quad(b, a, e, d, c); else this._quad(b, a, c, d, e);
      }
    }
  }

  box(group, key, min, max, opts = {}) {
    const { skip = {}, ao = 0 } = opts;
    const [x0, y0, z0] = min, [x1, y1, z1] = max;
    if (!skip.py) this.hface(group, key, x0, z0, x1, z1, y1, true);
    if (!skip.ny) this.hface(group, key, x0, z0, x1, z1, y0, false);
    if (!skip.px) this.vface(group, key, 'x', x1, 1, z0, z1, y0, y1, { ao });
    if (!skip.nx) this.vface(group, key, 'x', x0, -1, z0, z1, y0, y1, { ao });
    if (!skip.pz) this.vface(group, key, 'z', z1, 1, x0, x1, y0, y1, { ao });
    if (!skip.nz) this.vface(group, key, 'z', z0, -1, x0, x1, y0, y1, { ao });
  }

  poly(group, key, pts, normal, ao = null) {
    const b = this._bucket(group, key);
    const n = new THREE.Vector3(...normal).normalize();
    const ids = pts.map((p, i) => this._vert(b, p[0], p[1], p[2], n.x, n.y, n.z, ao ? ao[i] : 0));
    // Wind the fan so it faces `normal` whatever order the points came in.
    const e1 = new THREE.Vector3().subVectors(new THREE.Vector3(...pts[1]), new THREE.Vector3(...pts[0]));
    const e2 = new THREE.Vector3().subVectors(new THREE.Vector3(...pts[2]), new THREE.Vector3(...pts[0]));
    const flip = e1.cross(e2).dot(n) < 0;
    for (let i = 1; i < ids.length - 1; i++) {
      if (flip) b.idx.push(ids[0], ids[i + 1], ids[i]); else b.idx.push(ids[0], ids[i], ids[i + 1]);
    }
  }

  build(parentOf, castOf = () => false) {
    const meshes = [];
    for (const b of this.buckets.values()) {
      if (!b.idx.length) continue;
      const g = new THREE.BufferGeometry();
      g.setAttribute('position', new THREE.Float32BufferAttribute(b.pos, 3));
      g.setAttribute('normal', new THREE.Float32BufferAttribute(b.nrm, 3));
      g.setAttribute('uv', new THREE.Float32BufferAttribute(b.uv, 2));
      g.setAttribute('color', new THREE.Float32BufferAttribute(b.col, 3));
      g.setIndex(b.idx);
      g.computeBoundingSphere();
      g.computeBoundingBox();
      const m = new THREE.Mesh(g, this.surfaces.get(b.key).mat);
      m.name = `batch:${b.group}:${b.key}`;
      m.castShadow = castOf(b.group, b.key);
      m.receiveShadow = true;
      parentOf(b.group).add(m);
      meshes.push(m);
    }
    this.buckets.clear();
    return meshes;
  }
}
