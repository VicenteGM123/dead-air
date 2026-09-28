"""Compares dalib.three_geo / geo / mathutils3 / rng / pal against the real three.js (r186) + src/core JS.

    python3 blender/dalib/tests/test_three_geo.py            # runs dump_three.mjs with node, then compares
    python3 blender/dalib/tests/test_three_geo.py ref.json   # compare against an existing dump
    options: -v (print every case), -k <substring> (only matching cases)

Geometry cases compare every attribute (position, normal, uv, color ...), index, groups, type, name (cache keys),
bounding box / sphere with |diff| <= 1e-5; value cases (curves, earcut, math, color, rng, JS formatting, config)
with |diff| <= 1e-9 * max(1, |x|). Exit code 1 on any failure.
"""

import json
import math
import os
import re
import subprocess
import sys
import tempfile

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(os.path.dirname(HERE)))  # blender/

from dalib import three_geo as THREE  # noqa: E402
from dalib import geo as G  # noqa: E402
from dalib import rng as R  # noqa: E402
from dalib import pal  # noqa: E402
from dalib.mathutils3 import js_str, js_json, js_to_fixed, js_round  # noqa: E402

PI = math.pi
TAU = math.pi * 2
V2 = THREE.Vector2
V3 = THREE.Vector3
GEO_TOL = 1e-5
VAL_TOL = 1e-9


# ------------------------------------------------------------------------------------------ serialisation
def geo(g):
    if g is None:
        return {'kind': 'geo', 'none': True}
    attrs = {k: {'itemSize': a.itemSize, 'array': np.asarray(a, dtype=float).reshape(-1)} for k, a in
             g.attributes.items()}
    g.computeBoundingBox()
    g.computeBoundingSphere()
    params = None
    if g.parameters is not None:
        params = {k: v for k, v in g.parameters.items() if isinstance(v, (int, float, bool))}
    return {
        'kind': 'geo', 'type': g.type, 'name': g.name, 'attrs': attrs,
        'index': None if g.index is None else np.asarray(g.index).reshape(-1).tolist(),
        'groups': [{'start': x['start'], 'count': x['count'], 'materialIndex': x['materialIndex']} for x in g.groups],
        'parameters': params,
        'bbox': [list(g.boundingBox.min), list(g.boundingBox.max)],
        'bsphere': [list(g.boundingSphere.center), g.boundingSphere.radius],
    }


def vec(v):
    if v is None:
        return None
    return [v.x, v.y, v.z] if getattr(v, 'isVector3', False) else [v.x, v.y]


def vecs(a):
    return [vec(v) for v in a]


# ------------------------------------------------------------------------------------------ SIMPLE (DSL) cases
def arg(a):
    if isinstance(a, dict) and 'v2' in a:
        return [V2(x, y) for x, y in a['v2']]
    if isinstance(a, dict) and 'pi' in a:
        return a['pi'] * PI
    return a


CTORS = {k: getattr(THREE, k) for k in dir(THREE) if k.endswith('Geometry')}


def applyOps(g, ops):
    for op_ in ops:
        op, A = op_[0], [arg(x) for x in op_[1:]]
        if op == 'toNonIndexed':
            g = g.toNonIndexed()
        elif op == 'mergeVertices':
            g = THREE.mergeVertices(g, A[0])
        elif op == 'q':
            g.applyQuaternion(THREE.Quaternion(A[0], A[1], A[2], A[3]))
        elif op == 'm4euler':
            g.applyMatrix4(THREE.Matrix4().makeRotationFromEuler(THREE.Euler(A[0], A[1], A[2], A[3])))
        elif op == 'm4compose':
            g.applyMatrix4(THREE.Matrix4().compose(V3(A[0], A[1], A[2]),
                                                   THREE.Quaternion().setFromEuler(THREE.Euler(A[3], A[4], A[5])),
                                                   V3(A[6], A[7], A[8])))
        elif op == 'lookAt':
            g.lookAt(V3(A[0], A[1], A[2]))
        elif op == 'warpY':
            p = g.attributes.position
            for i in range(p.count):
                p.setY(i, p.getY(i) + A[0] * p.getX(i) * p.getZ(i) + 0.05 * math.sin(p.getX(i) * 7))
        elif op == 'clone':
            g = g.clone()
        else:
            getattr(g, op)(*A)
    return g


# ------------------------------------------------------------------------------------------ helpers (kit.js copies)
def roundRect(w, h, r=0.02):
    s = THREE.Shape()
    x = -w / 2
    y = -h / 2
    r = min(r, w / 2 - 1e-4, h / 2 - 1e-4)
    s.moveTo(x + r, y)
    s.lineTo(x + w - r, y); s.quadraticCurveTo(x + w, y, x + w, y + r)
    s.lineTo(x + w, y + h - r); s.quadraticCurveTo(x + w, y + h, x + w - r, y + h)
    s.lineTo(x + r, y + h); s.quadraticCurveTo(x, y + h, x, y + h - r)
    s.lineTo(x, y + r); s.quadraticCurveTo(x, y, x + r, y)
    return s


def kitExtrude(s, depth, opts=None):
    opts = opts or {}
    bevel = min(opts.get('bevel', 0.008), depth / 2 - 1e-4)
    g = THREE.ExtrudeGeometry(s, {
        'depth': max(1e-4, depth - bevel * 2), 'bevelEnabled': bevel > 0, 'bevelThickness': bevel,
        'bevelSize': bevel, 'bevelOffset': -bevel, 'bevelSegments': opts.get('bevelSeg', 2),
        'curveSegments': opts.get('curveSeg', 12)})
    g.translate(0, 0, -(depth - bevel * 2) / 2)
    g.computeVertexNormals()
    return g


def rrShape4(w, h, rads, cu=0, cv=0):
    bl, br, tr, tl = rads
    x0, x1, y0, y1 = cu - w / 2, cu + w / 2, cv - h / 2, cv + h / 2
    s = THREE.Shape()
    s.moveTo(x0 + bl, y0)
    s.lineTo(x1 - br, y0); s.absarc(x1 - br, y0 + br, br, -PI / 2, 0, False)
    s.lineTo(x1, y1 - tr); s.absarc(x1 - tr, y1 - tr, tr, 0, PI / 2, False)
    s.lineTo(x0 + tl, y1); s.absarc(x0 + tl, y1 - tl, tl, PI / 2, PI, False)
    s.lineTo(x0, y0 + bl); s.absarc(x0 + bl, y0 + bl, bl, PI, PI * 1.5, False)
    return s


def gearShape():
    teeth = []
    nT, rG = 28, 0.72
    for i in range(nT * 2):
        a = (i / (nT * 2)) * TAU
        r = rG if i % 2 else rG + 0.05
        teeth.append([math.cos(a) * r, math.sin(a) * r])
    s = THREE.Shape([V2(x, y) for x, y in teeth])
    ring = []
    for i in range(20):
        a = (i / 20) * TAU
        ring.append([math.cos(a) * 0.4, math.sin(a) * 0.4])
    s.holes.append(THREE.Path([V2(x, y) for x, y in ring]))
    return s


def circlePts(r, n, cx=0, cy=0, rev=False):
    p = []
    for i in range(n):
        a = (i / n) * TAU * (-1 if rev else 1)
        p.append(V2(cx + math.cos(a) * r, cy + math.sin(a) * r * 0.8))
    return p


def cboxPts(w, h, d, c):
    hx, hy, hz = w / 2, h / 2, d / 2
    cc = min(c, hx * 0.45, hy * 0.45, hz * 0.45)
    pts = []
    for sx in (-1, 1):
        for sy in (-1, 1):
            for sz in (-1, 1):
                pts += [V3(sx * hx, sy * (hy - cc), sz * (hz - cc)), V3(sx * (hx - cc), sy * hy, sz * (hz - cc)),
                        V3(sx * (hx - cc), sy * (hy - cc), sz * hz)]
    return pts


def cboxBroadcast(w, h, d, c=0.004):
    c = max(1e-4, min(c, w / 2 - 1e-4, h / 2 - 1e-4, d / 2 - 1e-4))
    hx, hy, hz = w / 2, h / 2, d / 2
    pts = []
    for sx in (-1, 1):
        for sy in (-1, 1):
            for sz in (-1, 1):
                pts += [V3(sx * hx, sy * (hy - c), sz * (hz - c)), V3(sx * (hx - c), sy * hy, sz * (hz - c)),
                        V3(sx * (hx - c), sy * (hy - c), sz * hz)]
    return pts


# ------------------------------------------------------------------------------------------ COMPLEX cases
C = {}


def case(fn):
    C[fn.__name__] = fn
    return fn


@case
def tube_catmull():
    return THREE.TubeGeometry(THREE.CatmullRomCurve3([V3(0, 0, 0), V3(0.1, 0.3, 0), V3(0.3, 0.35, 0.1),
                                                      V3(0.5, 0.2, -0.1)]), 24, 0.02, 8, False)


@case
def tube_closed():
    loop = []
    for i in range(9):
        a = (i / 9) * TAU
        loop.append(V3(math.cos(a) * 0.1, math.sin(a * 2) * 0.02, math.sin(a) * 0.08))
    return THREE.TubeGeometry(THREE.CatmullRomCurve3(loop, True, 'centripetal'), 48, 0.0082, 6, True)


@case
def tube_chordal():
    return THREE.TubeGeometry(THREE.CatmullRomCurve3([V3(0, 0, 0), V3(0.2, 0.5, 0.1), V3(0.4, 0.5, 0.3), V3(1, 0, 0),
                                                      V3(1.2, -0.3, 0.2)], False, 'chordal'), 32, 0.05, 5, False)


@case
def tube_catmullrom():
    return THREE.TubeGeometry(THREE.CatmullRomCurve3([V3(0, 0, 0), V3(0.2, 0.5, 0.1), V3(0.4, 0.5, 0.3), V3(1, 0, 0)],
                                                     False, 'catmullrom', 0.3), 20, 0.05, 7, False)


@case
def tube_bezier3():
    return THREE.TubeGeometry(THREE.CubicBezierCurve3(V3(0, 0, 0), V3(0, 0.4, 0.1), V3(0.3, 0.5, -0.2),
                                                      V3(0.6, 0.1, 0)), 16, 0.01, 6, False)


@case
def tube_line3():
    return THREE.TubeGeometry(THREE.LineCurve3(V3(0, 0, 0), V3(0.3, 1, 0.2)), 4, 0.03, 8, False)


@case
def tube_straight_y():
    return THREE.TubeGeometry(THREE.CatmullRomCurve3([V3(0, 0, 0), V3(0, 0.5, 0), V3(0, 1, 0)]), 6, 0.02, 6, False)


@case
def tube_dup_points():
    return THREE.TubeGeometry(THREE.CatmullRomCurve3([V3(0, 0, 0), V3(0, 0, 0), V3(0.2, 0.1, 0), V3(0.4, 0.1, 0.1)]),
                              10, 0.02, 4, False)


@case
def shape_roundrect():
    return THREE.ShapeGeometry(roundRect(0.6, 0.4, 0.05), 4)


@case
def shape_roundrect_rot():
    return THREE.ShapeGeometry(roundRect(0.36, 0.26, 0.1 * 0.7), 4).rotateY(PI)


@case
def shape_holes():
    s = roundRect(1, 0.8, 0.1)
    s.holes.append(THREE.Path(roundRect(0.6, 0.4, 0.035).getPoints(8)))
    s.holes.append(THREE.Path(circlePts(0.05, 10, 0.38, 0.3, True)))
    return THREE.ShapeGeometry(s, 6)


@case
def shape_rr4():
    return THREE.ShapeGeometry(rrShape4(0.8, 0.5, [0.05, 0.05, 0.2, 0.2], 0.1, 0.3), 12)


@case
def shape_array():
    return THREE.ShapeGeometry([roundRect(0.3, 0.2, 0.05), rrShape4(0.4, 0.4, [0.1, 0.02, 0.1, 0.02], 1, 0)], 5)


@case
def shape_bigcircle():
    return THREE.ShapeGeometry(THREE.Shape(circlePts(0.5, 120)), 12)


@case
def shape_bigcircle_hole():
    s = THREE.Shape(circlePts(0.5, 100))
    s.holes.append(THREE.Path(circlePts(0.2, 60, 0.05, 0)))
    s.holes.append(THREE.Path(circlePts(0.05, 12, -0.3, 0.1)))
    return THREE.ShapeGeometry(s, 12)


@case
def shape_gear():
    return THREE.ShapeGeometry(gearShape(), 4)


@case
def shape_path_mix():
    s = THREE.Shape()
    s.moveTo(0, 0); s.lineTo(0.5, 0); s.bezierCurveTo(0.6, 0.1, 0.6, 0.3, 0.5, 0.4)
    s.quadraticCurveTo(0.25, 0.6, 0, 0.4)
    s.splineThru([V2(-0.1, 0.3), V2(-0.05, 0.15), V2(-0.1, 0.05)]); s.lineTo(0, 0)
    h = THREE.Path()
    h.absellipse(0.25, 0.2, 0.08, 0.05, 0, TAU, True, 0.3)
    s.holes.append(h)
    return THREE.ShapeGeometry(s, 7)


@case
def shape_arc_rel():
    s = THREE.Shape()
    s.moveTo(0.1, 0); s.lineTo(0.4, 0); s.arc(0, 0.1, 0.1, -PI / 2, PI / 2, False); s.lineTo(0.1, 0.2)
    s.ellipse(0, -0.1, 0.1, 0.1, PI / 2, PI * 1.5, False)
    return THREE.ShapeGeometry(s, 5)


@case
def shape_cw_input():
    return THREE.ShapeGeometry(THREE.Shape([V2(0, 0), V2(0, 1), V2(1, 1), V2(1, 0)]), 1)


@case
def shape_selfintersect():
    return THREE.ShapeGeometry(THREE.Shape([V2(0, 0), V2(1, 1), V2(1, 0), V2(0, 1), V2(0.5, 1.5), V2(-0.2, 0.7)]), 1)


@case
def extrude_geo():
    return G.extrudeShape(roundRect(0.5, 0.3, 0.04), 0.05)


@case
def extrude_geo_nobevel():
    return G.extrudeShape(roundRect(0.5, 0.3, 0.04), 0.05, 0)


@case
def extrude_kit():
    return kitExtrude(roundRect(0.4, 0.8, 0.03), 0.04)


@case
def extrude_kit_frame():
    s = roundRect(0.6, 0.5, 0.03)
    s.holes.append(THREE.Path(roundRect(0.6 - 0.08, 0.5 - 0.08, 0.012).getPoints(4)))
    return kitExtrude(s, 0.03, {'bevel': min(0.008, 0.03 * 0.4, 0.04 * 0.35), 'bevelSeg': 1, 'curveSeg': 4})


@case
def extrude_gear():
    g = kitExtrude(gearShape(), 0.1, {'bevel': 0.012, 'bevelSeg': 1, 'curveSeg': 4})
    g.rotateX(-PI / 2)
    return g


@case
def extrude_nobevel_steps():
    return THREE.ExtrudeGeometry(roundRect(0.3, 0.2, 0.02), {'depth': 0.002, 'bevelEnabled': False,
                                                             'curveSegments': 6, 'steps': 3})


@case
def extrude_penny():
    return THREE.ExtrudeGeometry(roundRect(0.2, 0.3, 0.06), {
        'depth': 0.01, 'bevelEnabled': True, 'bevelThickness': 0.01 * 0.35, 'bevelSize': 0.02 * 0.22,
        'bevelSegments': 2, 'curveSegments': 40})


@case
def extrude_zombie():
    return THREE.ExtrudeGeometry(rrShape4(0.1, 0.06, [0.01, 0.01, 0.03, 0.03]), {
        'depth': 0.016, 'bevelEnabled': True, 'bevelThickness': 0.006, 'bevelSize': 0.006, 'bevelSegments': 1})


@case
def extrude_holes_default():
    s = THREE.Shape(circlePts(0.5, 90))
    s.holes.append(THREE.Path(circlePts(0.2, 30, 0.1, 0)))
    return THREE.ExtrudeGeometry(s, {'depth': 0.2, 'bevelThickness': 0.05, 'bevelSize': 0.03})


@case
def extrude_path():
    return THREE.ExtrudeGeometry(roundRect(0.1, 0.05, 0.01), {
        'steps': 12, 'bevelEnabled': False, 'curveSegments': 3,
        'extrudePath': THREE.CatmullRomCurve3([V3(0, 0, 0), V3(0.2, 0.3, 0), V3(0.5, 0.3, 0.2), V3(0.8, 0, 0.1)])})


@case
def extrude_multi():
    return THREE.ExtrudeGeometry([roundRect(0.3, 0.2, 0.05), rrShape4(0.2, 0.2, [0.02, 0.02, 0.05, 0.05], 0.5, 0)], {
        'depth': 0.05, 'bevelEnabled': True, 'bevelThickness': 0.01, 'bevelSize': 0.01, 'bevelSegments': 2,
        'curveSegments': 5})


@case
def extrude_dup_ends():
    return THREE.ExtrudeGeometry(THREE.Shape([V2(0, 0), V2(1, 0), V2(1, 1), V2(0, 1), V2(0, 0)]),
                                 {'depth': 0.3, 'bevelEnabled': False})


@case
def extrude_collinear():
    return THREE.ExtrudeGeometry(THREE.Shape([V2(0, 0), V2(0.5, 0), V2(1, 0), V2(1, 1), V2(0.5, 1.0000000001),
                                              V2(0, 1)]), {'depth': 0.3, 'bevelSegments': 2, 'bevelSize': 0.05,
                                                           'bevelThickness': 0.05})


@case
def extrude_mergev():
    return THREE.mergeVertices(kitExtrude(roundRect(0.3, 0.2, 0.03), 0.02), 1e-5)


@case
def convex_cbox_furn():
    return THREE.ConvexGeometry(cboxPts(0.2, 0.03, 0.14, 0.004))


@case
def convex_cbox_out():
    return THREE.ConvexGeometry(cboxPts(0.41, 0.12, 0.7, 0.006))


@case
def convex_cbox_bc():
    return THREE.ConvexGeometry(cboxBroadcast(0.05, 0.02, 0.3))


@case
def convex_cbox_tiny():
    return THREE.ConvexGeometry(cboxBroadcast(0.001, 0.5, 0.004, 0.004))


@case
def convex_random():
    r = R.mulberry32(99)
    p = [V3(r() - 0.5, r() - 0.5, r() - 0.5) for _ in range(60)]
    return THREE.ConvexGeometry(p)


@case
def convex_sphere_pts():
    s = THREE.SphereGeometry(0.4, 9, 7)
    a = s.attributes.position
    return THREE.ConvexGeometry([V3().fromBufferAttribute(a, i) for i in range(a.count)])


@case
def convex_cbox_uv():
    w, h, d = 0.3, 0.05, 0.2
    g = THREE.ConvexGeometry(cboxPts(w, h, d, 0.004))
    p, n = g.attributes.position, g.attributes.normal
    uv = np.zeros(p.count * 2)
    for i in range(p.count):
        ax, ay, az = abs(n.getX(i)), abs(n.getY(i)), abs(n.getZ(i))
        x, y, z = p.getX(i) / w + 0.5, p.getY(i) / h + 0.5, p.getZ(i) / d + 0.5
        if az >= ax and az >= ay:
            u = 1 - x if n.getZ(i) < 0 else x
            v = y
        elif ax >= ay:
            u = 1 - z if n.getX(i) > 0 else z
            v = y
        else:
            u = x
            v = 1 - z if n.getY(i) > 0 else z
        uv[i * 2] = u
        uv[i * 2 + 1] = v
    g.setAttribute('uv', THREE.BufferAttribute(uv, 2))
    return g


@case
def merge_indexed():
    return THREE.mergeGeometries([THREE.BoxGeometry(1, 1, 1), THREE.SphereGeometry(0.5, 8, 6).translate(1, 0, 0),
                                  THREE.CylinderGeometry(0.1, 0.1, 1, 6)], False)


@case
def merge_groups():
    return THREE.mergeGeometries([THREE.BoxGeometry(1, 1, 1), THREE.PlaneGeometry(1, 1).translate(0, 0, 1)], True)


@case
def merge_nonindexed():
    return THREE.mergeGeometries([THREE.RoundedBoxGeometry(0.2, 0.3, 0.4, 1, 0.02),
                                  THREE.BoxGeometry(1, 1, 1).toNonIndexed()], True)


@case
def merge_fail_mixed():
    return THREE.mergeGeometries([THREE.BoxGeometry(1, 1, 1), THREE.RoundedBoxGeometry(0.2, 0.3, 0.4, 1, 0.02)], False)


@case
def merge_fail_attrs():
    return THREE.mergeGeometries([G.withAO(THREE.BoxGeometry(1, 1, 1)), THREE.BoxGeometry(1, 1, 1)], False)


@case
def merge_colors():
    return THREE.mergeGeometries([G.withAO(THREE.BoxGeometry(1, 1, 1)),
                                  G.withAO(THREE.SphereGeometry(0.4, 6, 4), {'strength': 0.8, 'tint': '#102030'})],
                                 False)


@case
def merge_then_mergev():
    return THREE.mergeVertices(THREE.mergeGeometries([THREE.PlaneGeometry(1, 1),
                                                      THREE.PlaneGeometry(1, 1).translate(1, 0, 0)], False), 1e-4)


@case
def geo_roundedBox():
    return G.roundedBox(0.4, 0.3, 0.2)


@case
def geo_roundedBox2():
    return G.roundedBox(1.23456, 0.3, 0.2, 0.012, 2)


@case
def geo_box():
    return G.box(0.1, 0.2, 0.3)


@case
def geo_capsule():
    return G.capsule(0.05, 0.2)


@case
def geo_cylinder():
    return G.cylinder(0.1, 0.12, 0.3)


@case
def geo_sphere():
    return G.sphere(0.3)


@case
def geo_torus():
    return G.torus(0.3, 0.05)


@case
def geo_torus_arc():
    return G.torus(0.3, 0.05, 6, 16, PI)


@case
def geo_plane():
    return G.plane(2, 1, 2, 3)


@case
def geo_lathe():
    return G.lathe([[0, 0], [0.2, 0], [0.25, 0.1], [0.1, 0.3], [0, 0.3]])


@case
def geo_lathe_v2():
    return G.lathe([V2(0.1, 0), V2(0.2, 0.1)], 12)


@case
def geo_tube():
    return G.tube([[0, 0, 0], [0.1, 0.2, 0], [0.3, 0.3, 0.1]], 0.02)


@case
def geo_tube_closed():
    return G.tube([V3(0, 0, 0), V3(0.1, 0.2, 0), V3(0.3, 0.3, 0.1), V3(0.2, 0, 0.1)], 0.015, 30, 6, True)


@case
def geo_ao_default():
    return G.withAO(G.cylinder(0.1, 0.12, 0.3))


@case
def geo_ao_opts():
    return G.withAO(G.roundedBox(0.4, 0.3, 0.2), {'y0': -0.05, 'y1': 0.1, 'strength': 0.6, 'tint': '#102040'})


@case
def geo_ao_flat():
    return G.withAO(G.plane(1, 1))



# ------------------------------------------------------------------------------------------ FUZZ (mirror of the JS)
def fuzz_cases():
    out = {}
    r = R.mulberry32(20240928)

    def F(a, b):
        return a + (b - a) * r()

    def I(a, b):
        return a + math.floor(r() * (b - a + 1))

    def ops(g):
        n = I(0, 3)
        for _ in range(n):
            o = I(0, 7)
            if o == 0:
                g.rotateX(F(-3, 3))
            elif o == 1:
                g.rotateY(F(-3, 3))
            elif o == 2:
                g.rotateZ(F(-3, 3))
            elif o == 3:
                g.translate(F(-1, 1), F(-1, 1), F(-1, 1))
            elif o == 4:
                g.scale(F(-2, 2), F(0.1, 2), F(0.5, 1.5))
            elif o == 5:
                g.computeVertexNormals()
            elif o == 6:
                g = g.toNonIndexed() if g.index is not None else g
            else:
                g = THREE.mergeVertices(g, [1e-4, 1e-5, 1e-3][I(0, 2)])
        return g

    for i in range(30):
        out['fuzz_rbox_%d' % i] = ops(THREE.RoundedBoxGeometry(F(0.005, 1.5), F(0.005, 1.5), F(0.005, 1.5), I(0, 3),
                                                               F(0, 0.12)))
    for i in range(25):
        n = I(2, 7)
        pts = []
        y = F(-0.2, 0.2)
        for k in range(n):
            pts.append(V2(0 if ((k == 0 or k == n - 1) and r() < 0.5) else F(0, 0.5), y))
            y += F(0, 0.3)
        seg = I(3, 32)
        ps = F(0, 3) if r() < 0.3 else 0
        pl = F(0.5, 7) if r() < 0.3 else TAU
        out['fuzz_lathe_%d' % i] = ops(THREE.LatheGeometry(pts, seg, ps, pl))
    for i in range(25):
        n = I(2, 6)
        pts = [V3(F(-1, 1), F(-1, 1), F(-1, 1)) for _ in range(n)]
        closed = r() < 0.3
        typ = ['centripetal', 'chordal', 'catmullrom'][I(0, 2)]
        curve = THREE.CatmullRomCurve3(pts, closed, typ, F(0, 1))
        ts = I(2, 40)
        rad = F(0.001, 0.1)
        rs = I(3, 10)
        out['fuzz_tube_%d' % i] = ops(THREE.TubeGeometry(curve, ts, rad, rs, closed))
    for i in range(30):
        w, h = F(0.05, 1), F(0.05, 1)
        s = roundRect(w, h, F(0, 0.3))
        if r() < 0.5:
            s.holes.append(THREE.Path(roundRect(w * 0.5, h * 0.5, F(0, 0.1)).getPoints(I(1, 8))))
        if r() < 0.2:
            rr_ = min(w, h) * 0.1
            nn = I(3, 20)
            s.holes.append(THREE.Path(circlePts(rr_, nn, w * 0.35, h * 0.35, r() < 0.5)))
        bev = r() < 0.7
        t = F(0.001, 0.05)
        o = {'depth': F(0.001, 0.3), 'bevelEnabled': bev, 'bevelThickness': t, 'bevelSize': F(0.001, 0.02)}
        o['bevelOffset'] = -F(0, 0.01) if r() < 0.3 else 0
        o['bevelSegments'] = I(1, 4)
        o['curveSegments'] = I(1, 16)
        o['steps'] = I(1, 3)
        out['fuzz_extrude_%d' % i] = ops(THREE.ExtrudeGeometry(s, o))
    for i in range(20):
        s = roundRect(F(0.05, 1), F(0.05, 1), F(0, 0.3))
        out['fuzz_shape_%d' % i] = ops(THREE.ShapeGeometry(s, I(1, 20)))
    for i in range(20):
        a = 0 if r() < 0.2 else F(0, 1)
        b = 0 if r() < 0.2 else F(0, 1)
        h = F(0.01, 2)
        rs = I(3, 32)
        hs = I(1, 4)
        oe = r() < 0.2
        t0 = F(0, 6) if r() < 0.3 else 0
        tl = F(0.1, 6.28) if r() < 0.3 else TAU
        out['fuzz_cyl_%d' % i] = ops(THREE.CylinderGeometry(a, b, h, rs, hs, oe, t0, tl))
    for i in range(20):
        rad = F(0.01, 1)
        ws = I(3, 32)
        hs = I(2, 20)
        p0 = F(0, 6) if r() < 0.3 else 0
        pl = F(0.1, 6.28) if r() < 0.3 else TAU
        t0 = F(0, 3) if r() < 0.3 else 0
        tl = F(0.1, 3.14) if r() < 0.3 else PI
        out['fuzz_sphere_%d' % i] = ops(THREE.SphereGeometry(rad, ws, hs, p0, pl, t0, tl))
    for i in range(15):
        a, b, c, d = F(0.05, 1), F(0.005, 0.2), I(3, 16), I(3, 48)
        arc = F(0.1, 6.28) if r() < 0.4 else TAU
        out['fuzz_torus_%d' % i] = ops(THREE.TorusGeometry(a, b, c, d, arc))
    for i in range(15):
        a, b, c, d, e = F(0.01, 0.5), F(0, 1), I(1, 8), I(3, 16), I(1, 3)
        out['fuzz_capsule_%d' % i] = ops(THREE.CapsuleGeometry(a, b, c, d, e))
    for i in range(15):
        a, b, c, d = F(0.002, 1), F(0.002, 1), F(0.002, 1), F(0.001, 0.02)
        out['fuzz_convex_%d' % i] = THREE.ConvexGeometry(cboxPts(a, b, c, d))
    for i in range(10):
        a, b = F(0.1, 1), I(0, 3)
        out['fuzz_ico_%d' % i] = ops(THREE.IcosahedronGeometry(a, b))
    for i in range(10):
        a, b, c, d, e = F(0.05, 1), F(0.05, 1), F(0.05, 1), F(0.005, 0.05), I(1, 3)
        base = G.roundedBox(a, b, c, d, e)
        if r() < 0.5:
            opts = {}
        else:
            y0 = F(-0.5, 0)
            y1 = F(0, 0.5)
            opts = {'y0': y0, 'y1': y1, 'strength': F(0, 1)}
        out['fuzz_geo_ao_%d' % i] = G.withAO(base, opts)
    return out

# ------------------------------------------------------------------------------------------ VALUE cases
def value_cases():
    V = {}
    cr = THREE.CatmullRomCurve3([V3(0, 0, 0), V3(0.1, 0.3, 0), V3(0.3, 0.35, 0.1), V3(0.5, 0.2, -0.1)])
    V['curve_cr_points'] = vecs(cr.getPoints(10))
    V['curve_cr_spaced'] = vecs(cr.getSpacedPoints(10))
    V['curve_cr_len'] = cr.getLength()
    V['curve_cr_u2t'] = [cr.getUtoTmapping(u) for u in [0, 0.1, 0.33, 0.5, 0.77, 1]]
    V['curve_cr_tan'] = [vec(cr.getTangentAt(u)) for u in [0, 0.25, 0.5, 1]]
    V['curve_cr_tan_t'] = [vec(cr.getTangent(t)) for t in [0, 0.25, 0.5, 1]]
    f = cr.computeFrenetFrames(8, False)
    V['curve_cr_frames'] = {'t': vecs(f.tangents), 'n': vecs(f.normals), 'b': vecs(f.binormals)}
    c = THREE.CatmullRomCurve3([V3(0, 0, 0), V3(1, 0, 0), V3(1, 1, 0.3), V3(0, 1, 0)], True)
    f = c.computeFrenetFrames(12, True)
    V['curve_cr_frames_closed'] = {'t': vecs(f.tangents), 'n': vecs(f.normals), 'b': vecs(f.binormals)}
    V['curve_cr_closed_pts'] = vecs(THREE.CatmullRomCurve3([V3(0, 0, 0), V3(1, 0, 0), V3(1, 1, 0.3), V3(0, 1, 0)],
                                                           True).getPoints(9))
    bz = THREE.CubicBezierCurve3(V3(0, 0, 0), V3(0, 1, 0), V3(1, 1, 0), V3(1, 0, 0.5))
    V['curve_bz3'] = {'pts': vecs(bz.getPoints(7)), 'at': [vec(bz.getPointAt(u)) for u in [0.1, 0.6]],
                      'tan': vec(bz.getTangent(0.3)), 'len': bz.getLength()}
    qb3 = THREE.QuadraticBezierCurve3(V3(0, 0, 0), V3(0, 1, 0), V3(1, 1, 0))
    V['curve_qb3'] = {'pts': vecs(qb3.getPoints(5)), 'len': qb3.getLength()}
    ln3 = THREE.LineCurve3(V3(0, 0, 0), V3(1, 2, 3))
    V['curve_line3'] = {'pts': vecs(ln3.getPoints(4)), 'sp': vecs(ln3.getSpacedPoints(3)), 'len': ln3.getLength(),
                        'tan': vec(ln3.getTangentAt(0.5))}
    V['curve_ellipse_cw'] = vecs(THREE.EllipseCurve(0.1, 0.2, 0.5, 0.3, 0.3, 2.5, True, 0.4).getPoints(8))
    V['curve_ellipse_full'] = vecs(THREE.EllipseCurve(0, 0, 1, 1, 0, TAU, False, 0).getPoints(6))
    V['curve_ellipse_same'] = vecs(THREE.EllipseCurve(0, 0, 1, 1, 1, 1, True, 0).getPoints(3))
    V['curve_ellipse_neg'] = vecs(THREE.EllipseCurve(0, 0, 1, 2, 5, -3, False, 0).getPoints(5))
    V['curve_arc'] = vecs(THREE.ArcCurve(0, 0, 2, 0, PI, True).getPoints(4))
    V['curve_spline2'] = vecs(THREE.SplineCurve([V2(0, 0), V2(1, 1), V2(2, 0), V2(3, 1)]).getPoints(9))
    path = THREE.Path()
    path.moveTo(0, 0); path.lineTo(1, 0); path.quadraticCurveTo(1.5, 0.5, 1, 1)
    path.bezierCurveTo(0.7, 1.2, 0.3, 1.2, 0, 1); path.absarc(0, 0.5, 0.5, PI / 2, PI * 1.5, False)
    V['path_points'] = vecs(path.getPoints())
    V['path_points5'] = vecs(path.getPoints(5))
    V['path_spaced'] = vecs(path.getSpacedPoints(20))
    V['path_len'] = path.getLength()
    V['path_curvelens'] = path.getCurveLengths()
    path2 = THREE.Path([V2(0, 0), V2(1, 0), V2(1, 1)])
    path2.closePath()
    path2.autoClose = True
    V['path_autoclose'] = {'pts': vecs(path2.getPoints()), 'sp': vecs(path2.getSpacedPoints(6))}
    s = roundRect(0.5, 0.4, 0.05)
    s.holes.append(THREE.Path(circlePts(0.1, 8)))
    e = s.extractPoints(6)
    V['shape_extract'] = {'shape': vecs(e.shape), 'holes': [vecs(h) for h in e.holes]}
    pts = circlePts(1, 7)
    V['shapeutils'] = {'area': THREE.ShapeUtils.area(pts), 'cw': THREE.ShapeUtils.isClockWise(pts),
                       'tri': THREE.ShapeUtils.triangulateShape(circlePts(1, 7), [circlePts(0.3, 5, 0, 0, True)])}
    V['earcut_square'] = THREE.ShapeUtils.triangulateShape([V2(0, 0), V2(1, 0), V2(1, 1), V2(0, 1)], [])
    d = [0, 0, 10, 0, 10, 10, 0, 10, 2, 2, 4, 2, 4, 4, 2, 4, 6, 6, 8, 6, 8, 8, 6, 8]
    P = lambda idx: [V2(d[i * 2], d[i * 2 + 1]) for i in idx]  # noqa: E731
    V['earcut_raw_holes'] = THREE.ShapeUtils.triangulateShape(P([0, 1, 2, 3]), [P([4, 7, 6, 5]), P([8, 11, 10, 9])])
    r = R.mulberry32(5)
    p = []
    for i in range(150):
        a = (i / 150) * TAU
        rr = 1 + 0.3 * r()
        p.append(V2(math.cos(a) * rr, math.sin(a) * rr))
    V['earcut_hashed'] = THREE.ShapeUtils.triangulateShape(p, [circlePts(0.3, 40, 0.1, 0.1, True),
                                                               circlePts(0.2, 12, -0.5, 0, True)])
    V['earcut_collinear_hole_touch'] = THREE.ShapeUtils.triangulateShape(
        [V2(0, 0), V2(4, 0), V2(4, 4), V2(0, 4)],
        [[V2(0, 1), V2(1, 2), V2(1, 1)][::-1], [V2(2, 2), V2(3, 2), V2(3, 3), V2(2, 3)][::-1],
         [V2(2, 2), V2(2, 1), V2(3, 1)]])
    E = THREE.Euler(0.3, -1.2, 2.1)
    orders = ['XYZ', 'YXZ', 'ZXY', 'ZYX', 'YZX', 'XZY']
    V['m4_euler'] = [THREE.Matrix4().makeRotationFromEuler(THREE.Euler(0.3, -1.2, 2.1, o)).elements for o in orders]
    V['q_euler'] = [THREE.Quaternion().setFromEuler(THREE.Euler(0.3, -1.2, 2.1, o)).toArray() for o in orders]
    V['euler_from_q'] = []
    for o in orders:
        eu = THREE.Euler().setFromQuaternion(THREE.Quaternion(0.1, 0.7, -0.3, 0.64).normalize(), o)
        V['euler_from_q'].append([eu.x, eu.y, eu.z])
    V['euler_gimbal'] = []
    for o in orders:
        eu = THREE.Euler().setFromRotationMatrix(
            THREE.Matrix4().makeRotationFromEuler(THREE.Euler(PI / 2, PI / 2, 0.3, o)), o)
        V['euler_gimbal'].append([eu.x, eu.y, eu.z])
    comp = lambda: THREE.Matrix4().compose(V3(1, 2, 3), THREE.Quaternion().setFromEuler(E), V3(1, -2, 0.5))  # noqa
    V['m4_compose'] = comp().elements
    pp, qq, ss = V3(), THREE.Quaternion(), V3()
    comp().decompose(pp, qq, ss)
    V['m4_decompose'] = [pp.toArray(), qq.toArray(), ss.toArray()]
    V['m4_invert'] = comp().invert().elements
    V['m4_det'] = comp().determinant()
    V['m4_lookat'] = [THREE.Matrix4().lookAt(V3(1, 2, 3), V3(0, 0, 0), V3(0, 1, 0)).elements,
                      THREE.Matrix4().lookAt(V3(0, 5, 0), V3(0, 0, 0), V3(0, 1, 0)).elements]
    V['m4_axis'] = THREE.Matrix4().makeRotationAxis(V3(1, 2, 3).normalize(), 0.7).elements
    V['m4_mul'] = THREE.Matrix4().makeRotationX(0.3).multiply(THREE.Matrix4().makeTranslation(1, 2, 3)).premultiply(
        THREE.Matrix4().makeScale(2, 3, 4)).elements
    V['m3_normal'] = THREE.Matrix3().getNormalMatrix(comp()).elements
    V['q_unit'] = [THREE.Quaternion().setFromUnitVectors(V3(0, 1, 0), V3(1, 2, 3).normalize()).toArray(),
                   THREE.Quaternion().setFromUnitVectors(V3(0, 1, 0), V3(0, -1, 0)).toArray(),
                   THREE.Quaternion().setFromUnitVectors(V3(1, 0, 0), V3(-1, 0, 0)).toArray()]
    V['q_slerp'] = [THREE.Quaternion().setFromEuler(E).slerp(THREE.Quaternion(0, 0, 0.6, 0.8), t).toArray()
                    for t in [0, 0.3, 1]]
    V['q_slerp_close'] = THREE.Quaternion(0, 0, 0.6, 0.8).slerp(
        THREE.Quaternion(0, 0.0001, 0.6, 0.8).normalize(), 0.5).toArray()
    V['q_axis'] = THREE.Quaternion().setFromAxisAngle(V3(0, 1, 0), 1.3).multiply(
        THREE.Quaternion().setFromAxisAngle(V3(1, 0, 0), -0.4)).toArray()
    V['q_from_m'] = THREE.Quaternion().setFromRotationMatrix(
        THREE.Matrix4().makeRotationFromEuler(THREE.Euler(3, 0.1, -3))).toArray()
    a, b = V3(1, 2, 3), V3(-0.5, 0.2, 4)
    persp = THREE.Matrix4().makePerspective(-1, 1, 1, -1, 0.1, 100)
    V['v3_ops'] = [a.clone().cross(b).toArray(), a.angleTo(b), a.clone().applyEuler(E).toArray(),
                   a.clone().applyAxisAngle(V3(0, 0, 1), 0.5).toArray(), a.clone().lerp(b, 0.3).toArray(),
                   a.clone().projectOnVector(b).toArray(), a.clone().reflect(V3(0, 1, 0)).toArray(),
                   a.clone().setLength(2).toArray(),
                   a.clone().transformDirection(THREE.Matrix4().makeRotationY(1)).toArray(), a.distanceTo(b),
                   a.clone().applyMatrix4(persp).toArray()]
    a2, b2 = V2(1, 2), V2(-0.5, 0.2)
    V['v2_ops'] = [a2.angle(), a2.clone().rotateAround(b2, 0.8).toArray(), a2.cross(b2),
                   a2.clone().normalize().toArray(), a2.angleTo(b2)]
    bb = THREE.Box3().setFromPoints([V3(1, 2, 3), V3(-1, 0.5, 2), V3(0, -3, 1)])
    cb = bb.clone().applyMatrix4(THREE.Matrix4().makeRotationFromEuler(E))
    V['box3'] = [bb.min.toArray(), bb.max.toArray(), bb.getCenter(V3()).toArray(), bb.getSize(V3()).toArray(),
                 cb.min.toArray(), cb.max.toArray()]
    MU = THREE.MathUtils
    V['mathutils'] = [MU.clamp(5, 0, 1), MU.lerp(2, 5, 0.3), MU.smoothstep(0.3, 0.1, 0.9), MU.smoothstep(-1, 0, 1),
                      MU.damp(1, 5, 3, 0.016), MU.degToRad(33), MU.radToDeg(1.1), MU.euclideanModulo(-7.5, 3),
                      MU.mapLinear(3, 0, 10, -1, 1), MU.pingpong(3.7, 2), MU.smootherstep(0.4, 0, 1),
                      MU.inverseLerp(2, 6, 3), MU.ceilPowerOfTwo(300), MU.floorPowerOfTwo(300),
                      MU.isPowerOfTwo(256), MU.isPowerOfTwo(300), MU.seededRandom(77), MU.seededRandom(),
                      MU.seededRandom()]
    COLS = ['#3A2A5A', '#FF2A1E', '#F6F1FF', '#2E2836', '#150F1C', '#000000', '#FFFFFF', '#010203', '#7FE7FF', '#abc',
            'white', 'Crimson', 'rgb(10, 200, 30)', 'rgb(10%, 50%, 100%)', 'hsl(200, 40%, 60%)',
            'hsla(30, 100%, 50%, 1)']
    V['color_parse'] = []
    for s_ in COLS:
        c = THREE.Color(s_)
        V['color_parse'].append([c.r, c.g, c.b, c.getHex(), c.getHexString(), c.getStyle()])
    c = THREE.Color('#3A2A5A')
    hsl = c.getHSL({})

    def shade(hx, amt):
        k = THREE.Color(hx)
        if amt >= 0:
            k.lerp(THREE.Color(1, 1, 1), amt)
        else:
            k.multiplyScalar(1 + amt)
        return '#' + k.getHexString()

    V['color_ops'] = [[hsl['h'], hsl['s'], hsl['l']], THREE.Color().setHSL(0.3, 0.6, 0.4).toArray(),
                      THREE.Color('#E8A92E').offsetHSL(0.05, -0.1, 0.1).toArray(), THREE.Color(0x2F5BD3).toArray(),
                      THREE.Color(1, 0.5, 0.25).getHexString(), THREE.Color(3, 3, 3).getHex(),
                      THREE.Color('#FF7A2E').lerpHSL(THREE.Color('#1E5BFF'), 0.4).toArray(),
                      shade('#7A4A2A', 0.3), shade('#7A4A2A', -0.4), shade('#F4F1E8', 0.12),
                      THREE.Color('#8C9A3A').convertLinearToSRGB().toArray(),
                      THREE.Color().setRGB(0.5, 0.5, 0.5, 'srgb').toArray(), THREE.Color('#123456').getStyle()]
    V['rng_mulberry'] = []
    for sd in [0, 1, 42, 123456789, 4294967295, -5, 3.7, 2 ** 40 + 7, 0x6D2B79F5]:
        rr = R.mulberry32(sd)
        V['rng_mulberry'].append([rr() for _ in range(12)])
    HS = ['', 'a', 'rbox|0.4|0.3', 'tex:crt|512|256', 'Ümlaut ñ 日本', '\U0001F600emoji', 'wood_grain|walnut|0.35']
    V['rng_hashstr'] = [R.hashStr(s_) for s_ in HS]
    V['rng_seeded'] = []
    for s_ in HS:
        rr = R.seeded(s_)
        V['rng_seeded'].append([rr(), rr(), rr()])
    rr = R.mulberry32(1234)
    V['rng_helpers'] = [R.range(2, 5, rr), R.rangeInt(1, 6, rr), R.pick(['a', 'b', 'c', 'd'], rr), R.chance(0.5, rr),
                        R.shuffle([1, 2, 3, 4, 5, 6, 7], rr), R.weighted({'b': 1, 'a': 3, '10': 2, '2': 1}, rr),
                        R.weighted({'x': 0}, rr), R.hash1(3.3), R.noise1(7.25), R.noise1(-2.7)]
    V['js_str'] = [js_str(x) for x in [0.1 + 0.2, 1 / 3, 1e-7, 5e-7, 123456789.123, 1e21, 1.5e21, -0.0, 100, 2.5e-6,
                                        0.000001, 1234.5678e10]]
    V['js_json'] = js_json([[0, 0], [0.2, 0.1], [1 / 3, -0.0], [1e-7, 1e21]])
    V['js_fixed'] = [js_to_fixed(x, d_) for x, d_ in [[0.125, 2], [1.005, 2], [-0.001, 2], [2.5, 0], [-2.5, 0],
                                                      [1234.5678, 4], [0.1 + 0.2, 10], [1e-10, 3]]]
    V['js_round'] = [js_round(x) for x in [2.5, -2.5, 0.49999999999999994, -0.5, 1.4999999999999998, 123.5, -123.5]]
    V['config'] = {'PAL': pal.PAL, 'T': pal.T, 'LAYERS': pal.LAYERS}
    return V



# ------------------------------------------------------------------------------------------ python-only checks
def py_checks():
    """BufferAttribute float32-store semantics and API conveniences (no JS twin)."""
    f32 = lambda v: float(np.float32(v))  # noqa: E731
    out = []
    a = THREE.BufferAttribute(np.array([0.1, 0.2, 0.3, 0.4, 0.5, 0.6]), 3)
    out.append(('ctor rounds', a.getX(0) == f32(0.1) and a.count == 2 and a.itemSize == 3))
    a.setXYZ(1, 0.7, 0.8, 0.9)
    out.append(('setXYZ rounds', a.getZ(1) == f32(0.9)))
    a[0, 1] = 1 / 3
    out.append(('setitem rounds', a[0, 1] == f32(1 / 3)))
    a[:, 2] *= 1.1
    out.append(('slice augassign rounds', a[0, 2] == f32(f32(0.3) * 1.1)))
    a *= 3.3
    out.append(('inplace ufunc rounds', a[1, 0] == f32(f32(0.7) * 3.3)))
    x0 = a[0, 0]
    np.add.at(a, (np.array([0, 0]), np.array([0, 0])), 0.123)
    out.append(('ufunc.at rounds', a[0, 0] == f32(x0 + 0.123 + 0.123)))
    arr = a.array
    arr[4] = 0.1
    out.append(('flat .array view writes + rounds', a[1, 1] == f32(0.1) and arr.shape == (6,)))
    out.append(('derived arrays are plain', type(a * 2) is np.ndarray and type(a[:, 0]) is np.ndarray))
    out.append(('always truthy', bool(THREE.BufferAttribute(np.zeros(3), 3))))
    g = THREE.BoxGeometry()
    out.append(('missing attribute is None', g.attributes.color is None and g.getAttribute('color') is None))
    out.append(('index int + flat', g.index.dtype.kind == 'i' and g.index.ndim == 1 and g.index.getX(3) == 2))
    c = g.clone()
    out.append(('clone keeps class/params', type(c) is THREE.BoxGeometry and c.parameters.width == 1 and
                c.uuid != g.uuid))
    t = THREE.TubeGeometry()
    out.append(('tube clone keeps frames', t.clone().tangents is t.tangents))
    mn, mx = g.computeBoundingBox()
    out.append(('bbox unpack', mn.x == -0.5 and mx.y == 0.5))
    out.append(('None -> JS default', THREE.SphereGeometry(1, None, None).parameters.widthSegments == 32 and
                G.sphere(0.5, None).name == 'sph|0.5|20|14'))
    out.append(('int-valued float segments', THREE.TubeGeometry(None, 8.0, 1, 4.0).attributes.position.count == 45))
    out.append(('geo cache shared', G.box(1, 2, 3) is G.box(1, 2, 3) and G.box(1, 2, 3).name == 'box|1|2|3'))
    out.append(('pal', pal.PAL.shadow == '#3A2A5A' and pal.BARS[6] == '#3A58E4' and pal.T.telly.channels['2'] ==
                'revolver_38'))
    return out


# ------------------------------------------------------------------------------------------ comparison
class Diff(Exception):
    pass


def cmp_value(a, b, path='', tol=VAL_TOL, stats=None):
    """a = reference (JSON), b = python."""
    if isinstance(b, np.ndarray):
        b = b.tolist()
    if isinstance(b, tuple):
        b = list(b)
    if a is None or b is None:
        if a is not b and not (a is None and b is None):
            raise Diff('%s: %r != %r' % (path, a, b))
        return
    if isinstance(a, bool) or isinstance(b, bool):
        if bool(a) != bool(b):
            raise Diff('%s: %r != %r' % (path, a, b))
        return
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        d = abs(float(a) - float(b))
        if not (d <= tol * max(1.0, abs(float(a)))) and not (math.isnan(float(a)) and math.isnan(float(b))):
            raise Diff('%s: %r != %r (diff %.3g)' % (path, a, b, d))
        if stats is not None:
            stats['max'] = max(stats['max'], d)
        return
    if isinstance(a, str):
        if a != b:
            raise Diff('%s: %r != %r' % (path, a, b))
        return
    if isinstance(a, list):
        if not isinstance(b, list) or len(a) != len(b):
            raise Diff('%s: length %s != %s' % (path, len(a), len(b) if isinstance(b, list) else type(b)))
        for i, (x, y) in enumerate(zip(a, b)):
            cmp_value(x, y, '%s[%d]' % (path, i), tol, stats)
        return
    if isinstance(a, dict):
        if not isinstance(b, dict):
            raise Diff('%s: not a dict (%r)' % (path, type(b)))
        ka, kb = list(a.keys()), [str(k) for k in b.keys()]
        if sorted(ka) != sorted(kb):
            raise Diff('%s: keys %s != %s' % (path, sorted(ka), sorted(kb)))
        bb = {str(k): v for k, v in b.items()}
        for k in ka:
            cmp_value(a[k], bb[k], '%s.%s' % (path, k), tol, stats)
        return
    raise Diff('%s: unsupported %r / %r' % (path, a, b))


def cmp_geo(ref, g):
    st = {'max': 0.0, 'exact': True}
    if ref.get('none'):
        if g is not None:
            raise Diff('expected null (merge failure), got a geometry')
        return st
    if g is None:
        raise Diff('got None, expected a geometry')
    py = geo(g)
    if py['type'] != ref['type']:
        raise Diff('type %s != %s' % (py['type'], ref['type']))
    uu = re.compile(r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}')  # random uuids in keys
    if uu.sub('UUID', py['name']) != uu.sub('UUID', ref['name']):
        raise Diff('name %r != %r' % (py['name'], ref['name']))
    if list(py['attrs'].keys()) != list(ref['attrs'].keys()):
        raise Diff('attributes %s != %s' % (list(py['attrs'].keys()), list(ref['attrs'].keys())))
    for k, ra in ref['attrs'].items():
        pa = py['attrs'][k]
        if pa['itemSize'] != ra['itemSize']:
            raise Diff('%s.itemSize %s != %s' % (k, pa['itemSize'], ra['itemSize']))
        A = np.asarray(ra['array'], dtype=float)
        B = pa['array']
        if A.shape != B.shape:
            raise Diff('%s: count %d != %d' % (k, len(B) // pa['itemSize'], len(A) // ra['itemSize']))
        if len(A):
            d = np.abs(A - B)
            m = float(np.nanmax(d)) if not np.all(np.isnan(d)) else 0.0
            nanmis = np.isnan(A) != np.isnan(B)
            if m > GEO_TOL or nanmis.any():
                i = int(np.nanargmax(d))
                raise Diff('%s[%d] (vertex %d): js %r py %r (max diff %.3g)' % (
                    k, i, i // ra['itemSize'], A[i], B[i], m))
            st['max'] = max(st['max'], m)
            if m != 0:
                st['exact'] = False
    if ref['index'] != py['index']:
        ri, pi_ = ref['index'], py['index']
        if ri is None or pi_ is None:
            raise Diff('index %s != %s' % ('null' if ri is None else len(ri), 'None' if pi_ is None else len(pi_)))
        if len(ri) != len(pi_):
            raise Diff('index length %d != %d' % (len(pi_), len(ri)))
        i = next(i for i, (x, y) in enumerate(zip(ri, pi_)) if x != y)
        raise Diff('index[%d]: js %d py %d' % (i, ri[i], pi_[i]))
    if ref['groups'] != py['groups']:
        raise Diff('groups %s != %s' % (py['groups'], ref['groups']))
    cmp_value(ref['bbox'], py['bbox'], 'bbox', GEO_TOL)
    cmp_value(ref['bsphere'], py['bsphere'], 'bsphere', GEO_TOL)
    if ref.get('parameters') is not None:
        cmp_value(ref['parameters'], py['parameters'] or {}, 'parameters', VAL_TOL)
    return st


def main(argv):
    verbose = '-v' in argv
    only = None
    if '-k' in argv:
        only = argv[argv.index('-k') + 1]
    files = [a for a in argv if a.endswith('.json')]
    if files:
        ref_path = files[0]
        with open(ref_path) as fh:
            ref = json.load(fh)
    else:
        with tempfile.TemporaryDirectory(prefix='three_ref_') as tmp:
            ref_path = os.path.join(tmp, 'three_ref.json')
            subprocess.run(['node', os.path.join(HERE, 'dump_three.mjs'), ref_path], check=True,
                           cwd=os.path.dirname(os.path.dirname(os.path.dirname(HERE))), stderr=subprocess.DEVNULL,
                           stdout=subprocess.DEVNULL)
            with open(ref_path) as fh:
                ref = json.load(fh)

    builders = {}
    for name, ctor, args, ops in ref['__simple']:
        builders[name] = (lambda ctor=ctor, args=args, ops=ops:
                          applyOps(CTORS[ctor](*[arg(a) for a in args]), ops))
    builders.update(C)
    fz = fuzz_cases()
    builders.update({k: (lambda g=g: g) for k, g in fz.items()})
    values = value_cases()

    passed, failed, exact = [], [], 0
    for name, r in ref.items():
        if name == '__simple' or (only and only not in name):
            continue
        try:
            if r['kind'] == 'geo':
                if name not in builders:
                    raise Diff('no python builder')
                import io
                import contextlib
                err = io.StringIO()
                with contextlib.redirect_stderr(err):
                    g = builders[name]()
                st = cmp_geo(r, g)
                exact += st['exact']
                info = 'max|d|=%.2g%s' % (st['max'], ' bit-exact' if st['exact'] else '')
            else:
                if name not in values:
                    raise Diff('no python value')
                st = {'max': 0.0}
                cmp_value(r['value'], values[name], name, VAL_TOL, st)
                info = 'max|d|=%.2g' % st['max']
            passed.append(name)
            if verbose:
                print('PASS %-32s %s' % (name, info))
        except Diff as e:
            failed.append(name)
            print('FAIL %-32s %s' % (name, e))
        except Exception as e:  # noqa
            import traceback
            failed.append(name)
            print('ERROR %-31s %s: %s' % (name, type(e).__name__, e))
            if verbose:
                traceback.print_exc()
    for label, ok in py_checks():
        if only and only not in 'py:' + label:
            continue
        (passed if ok else failed).append('py:' + label)
        if not ok or verbose:
            print('%s py:%s' % ('PASS' if ok else 'FAIL', label))
    ngeo = sum(1 for n in passed if n in ref and ref[n]['kind'] == 'geo')
    print('\n%d passed (%d geometry cases, %d of them bit-exact float32), %d failed' % (
        len(passed), ngeo, exact, len(failed)))
    if failed:
        print('failed: ' + ', '.join(failed))
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
