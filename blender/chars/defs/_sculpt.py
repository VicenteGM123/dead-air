"""Shared sculpting helpers for character definitions (port of src/art/chars/_sculpt.js).
STYLE_GUIDE.md compliant building blocks: clean flaps (collars, lapels, pockets) from 2D footprints, molded-toy
hair locks WITHOUT grooves, a carved cartoon mouth with teeth/tongue whose shape follows the expression."""
import math

from ..jsutil import O, nz

DEG = math.pi / 180


def onEllipsoid(E, az, el, lift=0):
    """Point on an ellipsoid {c, r} at azimuth az (deg; 0 = front -z, 90 = +x, 180 = back) and elevation el (deg)."""
    a, e = az * DEG, el * DEG
    return [
        E['c'][0] + math.sin(a) * math.cos(e) * E['r'][0] * (1 + lift),
        E['c'][1] + math.sin(e) * E['r'][1] * (1 + lift),
        E['c'][2] - math.cos(a) * math.cos(e) * E['r'][2] * (1 + lift),
    ]


def lock(sd, node, E, path, o=None):
    """Hair lock laid on a surface: path in (az, el) on the guide ellipsoid, snapped onto `node`, as a flattened worm.
    o: { r (profile), flat, lift (m, <0 embeds), liftRoot, liftTip, grooves, k, up, segs, tip (color2) }
    Molded-toy default: NO grooves (STYLE_GUIDE §3). Pass grooves: { n, depth } explicitly only for yarn/fur."""
    o = O(o or {})
    # lift profile: roots buried, tips lifting off the mass (layered feathers)
    l0, l1, lm = nz(o.liftRoot, -0.012), nz(o.liftTip, 0.004), nz(o.lift, 0)
    lifts = []
    for i, p in enumerate(path):
        if len(p) > 2 and p[2] is not None:
            lifts.append(p[2])
            continue
        u = i / (len(path) - 1)
        lifts.append(lm + l0 * (1 - u) * (1 - u) + l1 * u * u)
    pts = sd.snapAll(node, [onEllipsoid(E, p[0], p[1], 0.05) for p in path], lifts)
    # flat face lies on the surface: per-point surface normals
    ups = None if o.up else [sd.normalAt(node, p) for p in pts]
    return sd.worm(pts=pts, r=o.r or [0.026, 0.036, 0.03, 0.016], flat=nz(o.flat, 0.5), up=o.up or ups[0], ups=ups,
                   grooves=nz(o.grooves, None), k=o.k, segs=o.segs or 16, color2=o.tip)


def prism(sd, pts, o=None):
    """Convex 2D footprint extruded along an axis (a prism made of planes), for use inside op:'int' groups (collar
    flaps, lapels, pockets, patches: shell-of-the-garment ∩ prism) or inside sd.paint (painted necklines, placket).
      pts: [[u, v], ...] convex polygon (any winding) in the plane ⟂ axis ('z': u=x v=y | 'x': u=z v=y | 'y': u=x v=z)
      o: { axis = 'z', min, max (bounds along the axis, optional), k (corner rounding, m), op, blend, name }"""
    o = O(o or {})
    ax = o.axis or 'z'

    def to3(u, v, w):
        return [u, v, w] if ax == 'z' else [w, v, u] if ax == 'x' else [u, w, v]
    cu = sum(p[0] for p in pts) / len(pts)
    cv = sum(p[1] for p in pts) / len(pts)
    k = nz(o.k, 0.01)

    def body():
        st = {'first': True}

        def P(n, d):
            sd.plane(n=n, d=d, op='add' if st['first'] else 'int', k=0 if st['first'] else k)
            st['first'] = False
        for i in range(len(pts)):
            au, av = pts[i]
            bu, bv = pts[(i + 1) % len(pts)]
            nu, nv = bv - av, -(bu - au)
            ln = math.hypot(nu, nv) or 1
            nu /= ln
            nv /= ln
            if nu * (cu - au) + nv * (cv - av) > 0:   # outward
                nu, nv = -nu, -nv
            P(to3(nu, nv, 0), nu * au + nv * av)
        if o.max is not None:
            P(to3(0, 0, 1), o.max)
        if o.min is not None:
            P(to3(0, 0, -1), -o.min)
    return sd.group({'name': o.name or 'prism', 'op': o.op, 'blend': o.blend, 'k': 0}, body)


def cartoonMouth(sd, m, mats=None):
    """Carved cartoon mouth (STYLE_GUIDE §4): a clean D/crescent opening with dark interior (cutMat), upper teeth and a
    tongue. Call it LAST inside the head group (after every additive head shape). Re-run per expression (morphs).
      m: { y, w, h, top, R (>0 smile radius; <0 frown; None = round O), z, depth, teeth, tongue, roll, clip }
      mats: { cut: 'mouth', teeth: 'teeth', tongue: 'tongue' }"""
    m = O(m)
    mats = O(mats or {})
    if m.roll or m.clip:
        return cartoonMouth2(sd, m, mats)
    z, depth = m.z, nz(m.depth, 0.034)

    def cut():
        sd.ellipsoid(pos=[0, m.y, z], r=[m.w, m.h, depth])
        if m.R is not None and m.R > 0:
            sd.sphere(op='sub', k=0.004, pos=[0, m.top + m.R, z], r=m.R)
        elif m.R is not None and m.R < 0:
            sd.sphere(op='int', k=0.004, pos=[0, m.top + m.R, z], r=-m.R)
    sd.group({'name': 'mouthCut', 'op': 'sub', 'blend': nz(m.soft, 0.006), 'cutMat': mats.cut or 'mouth', 'k': 0}, cut)
    top = m.y + m.h if m.R is None else m.top
    if ('teeth' not in mats or mats.teeth is not None) and nz(m.teeth, 1) > 0:
        th = 0.0105 * nz(m.teeth, 1)
        sd.ellipsoid(mat=mats.teeth or 'teeth', pos=[0, top - th * 0.35, z + 0.022], r=[m.w * 0.8, th + 0.004, 0.02], k=0.002)
    if ('tongue' not in mats or mats.tongue is not None) and m.tongue is not False:
        sd.ellipsoid(mat=mats.tongue or 'tongue', pos=[0, m.y - m.h * 0.75, z + 0.024], r=[m.w * 0.62, 0.012, 0.02], k=0.004)


def cartoonMouth2(sd, m, mats):
    """roll / clip variant (same shapes, in a frame centered on the mouth)"""
    depth = nz(m.depth, 0.034)
    top = (m.y + m.h if m.R is None else m.top) - m.y   # mouth-local

    def opening(shrink):
        sd.ellipsoid(pos=[0, 0, 0], r=[m.w - shrink, m.h - shrink, depth])
        if m.R is not None and m.R > 0:
            sd.sphere(op='sub', k=0.004, pos=[0, top + m.R, 0], r=m.R + shrink)
        elif m.R is not None and m.R < 0:
            sd.sphere(op='int', k=0.004, pos=[0, top + m.R, 0], r=-m.R - shrink)

    with sd.frame(pos=[0, m.y, m.z], rot=[0, 0, m.roll or 0]):
        sd.group({'name': 'mouthCut', 'op': 'sub', 'blend': nz(m.soft, 0.006), 'cutMat': mats.cut or 'mouth', 'k': 0}, lambda: opening(0))

        def clipped(mat, fn):
            with sd.group(name='mouthFill', mat=mat, blend=0.002, k=0):
                fn()
                if m.clip:
                    sd.group({'op': 'int', 'k': 0.002}, lambda: opening(0.0015))
        if ('teeth' not in mats or mats.teeth is not None) and nz(m.teeth, 1) > 0:
            th = 0.0105 * nz(m.teeth, 1)
            clipped(mats.teeth or 'teeth', lambda: sd.ellipsoid(pos=[0, top - th * 0.35, 0.022], r=[m.w * 0.84, th + 0.004, 0.02]))
        if ('tongue' not in mats or mats.tongue is not None) and m.tongue is not False:
            clipped(mats.tongue or 'tongue', lambda: sd.ellipsoid(pos=[0, -m.h * 0.75, 0.024], r=[m.w * 0.62, 0.012, 0.02]))
