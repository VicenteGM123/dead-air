// Shared sculpting helpers for character definitions (hashed into every bake).
// STYLE_GUIDE.md compliant building blocks: clean flaps (collars, lapels, pockets) from 2D footprints, molded-toy
// hair locks WITHOUT grooves, a carved cartoon mouth with teeth/tongue whose shape follows the expression.
export const DEG = Math.PI / 180;

// Point on an ellipsoid {c, r} at azimuth az (deg; 0 = front -z, 90 = +x, 180 = back) and elevation el (deg).
export function onEllipsoid(E, az, el, lift = 0) {
  const a = az * DEG, e = el * DEG;
  return [
    E.c[0] + Math.sin(a) * Math.cos(e) * E.r[0] * (1 + lift),
    E.c[1] + Math.sin(e) * E.r[1] * (1 + lift),
    E.c[2] - Math.cos(a) * Math.cos(e) * E.r[2] * (1 + lift),
  ];
}

// Hair lock laid on a surface: path in (az, el) on the guide ellipsoid, snapped onto `node`, as a flattened worm.
// o: { r (profile), flat, lift (m, <0 embeds), liftRoot, liftTip, grooves, k, up, segs, tip (color2) }
// Molded-toy default: NO grooves (STYLE_GUIDE §3). Pass grooves: { n, depth } explicitly only for yarn/fur.
export function lock(sd, node, E, path, o = {}) {
  // lift profile: roots buried, tips lifting off the mass (layered feathers)
  const l0 = o.liftRoot ?? -0.012, l1 = o.liftTip ?? 0.004, lm = o.lift ?? 0;
  const lifts = path.map((p, i) => {
    if (p[2] != null) return p[2];
    const u = i / (path.length - 1);
    return lm + l0 * (1 - u) * (1 - u) + l1 * u * u;
  });
  const pts = sd.snapAll(node, path.map(([az, el]) => onEllipsoid(E, az, el, 0.05)), lifts);
  // flat face lies on the surface: per-point surface normals
  const ups = o.up ? null : pts.map((p) => sd.normalAt(node, p));
  return sd.worm({ pts, r: o.r || [0.026, 0.036, 0.03, 0.016], flat: o.flat ?? 0.5, up: o.up || ups[0], ups, grooves: o.grooves ?? null, k: o.k, segs: o.segs || 16, color2: o.tip });
}

// Convex 2D footprint extruded along an axis (a prism made of planes), for use inside op:'int' groups (collar
// flaps, lapels, pockets, patches: shell-of-the-garment ∩ prism) or inside sd.paint (painted necklines, placket).
//   pts: [[u, v], ...] convex polygon (any winding) in the plane ⟂ axis ('z': u=x v=y | 'x': u=z v=y | 'y': u=x v=z)
//   o: { axis = 'z', min, max (bounds along the axis, optional), k (corner rounding, m), op, blend, name }
// Returns the group node. Example (front-only V neckline paint):
//   sd.paint({ mat: 'skin', only: ['shirt'] }, () => prism(sd, [[0, 1.05], [0.09, 1.25], [-0.09, 1.25]], { max: -0.02 }));
export function prism(sd, pts, o = {}) {
  const ax = o.axis || 'z';
  const to3 = (u, v, w) => (ax === 'z' ? [u, v, w] : ax === 'x' ? [w, v, u] : [u, w, v]);
  const cu = pts.reduce((a, p) => a + p[0], 0) / pts.length, cv = pts.reduce((a, p) => a + p[1], 0) / pts.length;
  const k = o.k ?? 0.01;
  return sd.group({ name: o.name || 'prism', op: o.op, blend: o.blend, k: 0 }, () => {
    let first = true;
    const P = (n, d) => { sd.plane({ n, d, op: first ? 'add' : 'int', k: first ? 0 : k }); first = false; };
    for (let i = 0; i < pts.length; i++) {
      const [au, av] = pts[i], [bu, bv] = pts[(i + 1) % pts.length];
      let nu = bv - av, nv = -(bu - au);
      const l = Math.hypot(nu, nv) || 1;
      nu /= l; nv /= l;
      if (nu * (cu - au) + nv * (cv - av) > 0) { nu = -nu; nv = -nv; } // outward
      P(to3(nu, nv, 0), nu * au + nv * av);
    }
    if (o.max != null) P(to3(0, 0, 1), o.max);
    if (o.min != null) P(to3(0, 0, -1), -o.min);
  });
}

// Carved cartoon mouth (STYLE_GUIDE §4): a clean D/crescent opening with dark interior (cutMat), upper teeth and a
// tongue. Call it LAST inside the head group (after every additive head shape). Re-run per expression (morphs):
//   m: { y (center), w (half width), h (half height below center), top (upper-lip line at x=0),
//        R (>0 corners curve UP = smile radius; <0 corners DOWN = frown; null = round O), z (face surface z at the
//        mouth), depth, teeth (0..1 visible height factor), tongue (bool),
//        roll (rad, optional: tilts the whole mouth so one corner sits higher = smirk; + raises the +x corner),
//        clip (bool, optional: teeth + tongue are intersected with the opening, so they can never poke through the
//        lips outside it; recommended for every new character) }
//   mats: { cut: 'mouth', teeth: 'teeth', tongue: 'tongue' }
export function cartoonMouth(sd, m, mats = {}) {
  if (m.roll || m.clip) return cartoonMouth2(sd, m, mats);
  const z = m.z, depth = m.depth ?? 0.034;
  sd.group({ name: 'mouthCut', op: 'sub', blend: m.soft ?? 0.006, cutMat: mats.cut || 'mouth', k: 0 }, () => {
    sd.ellipsoid({ pos: [0, m.y, z], r: [m.w, m.h, depth] });
    if (m.R != null && m.R > 0) sd.sphere({ op: 'sub', k: 0.004, pos: [0, m.top + m.R, z], r: m.R });
    else if (m.R != null && m.R < 0) sd.sphere({ op: 'int', k: 0.004, pos: [0, m.top + m.R, z], r: -m.R });
  });
  const top = m.R == null ? m.y + m.h : m.top;
  if (mats.teeth !== null && (m.teeth ?? 1) > 0) {
    const th = 0.0105 * (m.teeth ?? 1);
    sd.ellipsoid({ mat: mats.teeth || 'teeth', pos: [0, top - th * 0.35, z + 0.022], r: [m.w * 0.8, th + 0.004, 0.02], k: 0.002 });
  }
  if (mats.tongue !== null && m.tongue !== false) {
    sd.ellipsoid({ mat: mats.tongue || 'tongue', pos: [0, m.y - m.h * 0.75, z + 0.024], r: [m.w * 0.62, 0.012, 0.02], k: 0.004 });
  }
}

// roll / clip variant (same shapes, in a frame centered on the mouth)
function cartoonMouth2(sd, m, mats) {
  const depth = m.depth ?? 0.034;
  const top = (m.R == null ? m.y + m.h : m.top) - m.y;   // mouth-local
  const opening = (shrink) => {
    sd.ellipsoid({ pos: [0, 0, 0], r: [m.w - shrink, m.h - shrink, depth] });
    if (m.R != null && m.R > 0) sd.sphere({ op: 'sub', k: 0.004, pos: [0, top + m.R, 0], r: m.R + shrink });
    else if (m.R != null && m.R < 0) sd.sphere({ op: 'int', k: 0.004, pos: [0, top + m.R, 0], r: -m.R - shrink });
  };
  sd.frame({ pos: [0, m.y, m.z], rot: [0, 0, m.roll || 0] }, () => {
    sd.group({ name: 'mouthCut', op: 'sub', blend: m.soft ?? 0.006, cutMat: mats.cut || 'mouth', k: 0 }, () => opening(0));
    const clipped = (mat, fn) => sd.group({ name: 'mouthFill', mat, blend: 0.002, k: 0 }, () => {
      fn();
      if (m.clip) sd.group({ op: 'int', k: 0.002 }, () => opening(0.0015));
    });
    if (mats.teeth !== null && (m.teeth ?? 1) > 0) {
      const th = 0.0105 * (m.teeth ?? 1);
      clipped(mats.teeth || 'teeth', () => sd.ellipsoid({ pos: [0, top - th * 0.35, 0.022], r: [m.w * 0.84, th + 0.004, 0.02] }));
    }
    if (mats.tongue !== null && m.tongue !== false) {
      clipped(mats.tongue || 'tongue', () => sd.ellipsoid({ pos: [0, -m.h * 0.75, 0.024], r: [m.w * 0.62, 0.012, 0.02] }));
    }
  });
}
