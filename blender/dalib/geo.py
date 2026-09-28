"""Port of the geometry helpers of src/core/geo.js (ARCHITECTURE §6): cached primitive builders and fake-AO baking.

Cached geometries are SHARED: never mutate one you got from here (clone() it first). Everything is bevelled /
rounded by default in keeping with GDD §3.4. Cache keys are the JS keys character for character (JS number
formatting), and like the JS `cachedGeo` sets `geometry.name = key`.

Not ported here (scene-level, see blender/dalib/scene.py / kit.py owned by the kit agent): `mesh()` (-> kit.m),
`mergeByMaterial`, `mergeRig`, `skinRig` (draw-call merging is engine plumbing, SPEC §0.2).
"""

import numpy as np

from .three_geo import (RoundedBoxGeometry, BoxGeometry, CapsuleGeometry, CylinderGeometry, SphereGeometry,
                        TorusGeometry, PlaneGeometry, LatheGeometry, CatmullRomCurve3, TubeGeometry,
                        ExtrudeGeometry, Vector2, Vector3, mergeGeometries)  # noqa: F401
from .mathutils3 import Color, js_round, js_str, js_json, js_defaults

__all__ = ['cache', 'cachedGeo', 'roundedBox', 'box', 'capsule', 'cylinder', 'sphere', 'torus', 'plane', 'lathe',
           'tube', 'extrudeShape', 'withAO', 'r3', 'mergeGeometries']

cache = {}


def r3(n):
    """Math.round(n * 1000) / 1000"""
    return js_round(n * 1000) / 1000


def _k(*parts):
    return '|'.join(js_str(p) for p in parts)


def cachedGeo(key, make):
    g = cache.get(key)
    if g is None:
        g = make()
        g.name = key
        cache[key] = g
    return g


@js_defaults
def roundedBox(w, h, d, r=0.05, seg=3):
    return cachedGeo(_k('rbox', r3(w), r3(h), r3(d), r3(r), seg), lambda: RoundedBoxGeometry(w, h, d, seg, r))


@js_defaults
def box(w, h, d):
    return cachedGeo(_k('box', r3(w), r3(h), r3(d)), lambda: BoxGeometry(w, h, d))


@js_defaults
def capsule(r, len_, cap=8, rad=12):
    """Capsule along Y; total height = len + 2r."""
    return cachedGeo(_k('caps', r3(r), r3(len_), cap, rad), lambda: CapsuleGeometry(r, len_, cap, rad))


@js_defaults
def cylinder(rt, rb, h, seg=16):
    return cachedGeo(_k('cyl', r3(rt), r3(rb), r3(h), seg), lambda: CylinderGeometry(rt, rb, h, seg))


@js_defaults
def sphere(r, ws=20, hs=14):
    return cachedGeo(_k('sph', r3(r), ws, hs), lambda: SphereGeometry(r, ws, hs))


@js_defaults
def torus(r, tube_, rs=10, ts=24, arc=np.pi * 2):
    return cachedGeo(_k('tor', r3(r), r3(tube_), rs, ts, r3(arc)), lambda: TorusGeometry(r, tube_, rs, ts, arc))


@js_defaults
def plane(w, h, sx=1, sy=1):
    return cachedGeo(_k('plane', r3(w), r3(h), sx, sy), lambda: PlaneGeometry(w, h, sx, sy))


@js_defaults
def lathe(points, seg=24):
    """Lathe around Y. points: [[radius, y], ...] or Vector2[] (bottom to top)."""
    pts = [[p.x, p.y] if getattr(p, 'isVector2', False) else p for p in points]
    return cachedGeo('lathe|' + js_json(pts) + '|' + js_str(seg),
                     lambda: LatheGeometry([Vector2(p[0], p[1]) for p in pts], seg))


@js_defaults
def tube(points, r, seg=24, radial=8, closed=False):
    """Tube through points ([[x,y,z], ...] or Vector3[]) along a Catmull-Rom curve."""
    pts = [[p.x, p.y, p.z] if getattr(p, 'isVector3', False) else p for p in points]

    def make():
        curve = CatmullRomCurve3([Vector3(p[0], p[1], p[2]) for p in pts], closed)
        return TubeGeometry(curve, seg, r, radial, closed)

    return cachedGeo('tube|' + js_json(pts) + '|' + _k(r3(r), seg, radial, closed), make)


@js_defaults
def extrudeShape(shape, depth, bevel=0.02):
    """Extruded shape with a soft bevel (not cached: shapes are objects; cache the result yourself if reused)."""
    g = ExtrudeGeometry(shape, {
        'depth': depth, 'bevelEnabled': bevel > 0, 'bevelThickness': bevel, 'bevelSize': bevel,
        'bevelSegments': 3, 'curveSegments': 16,
    })
    g.translate(0, 0, -depth / 2)
    return g


def withAO(geometry, opts=None, **kw):
    """Fake AO (GDD §3.5): returns a cached copy of `geometry` with vertex colors darkening its bottom part.
    Use with a material created with {vertexColors: true}. y0/y1 are local heights of the fade band.
    opts (dict or kwargs): y0=None, y1=None, strength=0.45, tint='#3A2A5A'. Colors are LINEAR (like three)."""
    o = dict(opts or {})
    o.update(kw)
    y0 = o.get('y0')
    y1 = o.get('y1')
    strength = o.get('strength')
    strength = 0.45 if strength is None else strength
    tint = o.get('tint')
    tint = '#3A2A5A' if tint is None else tint

    def make():
        g = geometry.clone()
        g.computeBoundingBox()
        bb = g.boundingBox
        a = y0 if y0 is not None else bb.min.y
        b = y1 if y1 is not None else bb.min.y + (bb.max.y - bb.min.y) * 0.3
        pos = g.attributes.position
        y = pos.view(np.ndarray)[:, 1]
        # k = 1 - MathUtils.smoothstep(y, a, b)
        with np.errstate(divide='ignore', invalid='ignore'):
            x = (y - a) / (b - a)
            ss = np.where(y <= a, 0.0, np.where(y >= b, 1.0, x * x * (3 - 2 * x)))
        k = 1 - ss
        t = Color(tint)
        alpha = k * strength
        # c.setRGB(1, 1, 1).lerp(t, alpha): c.r += (t.r - c.r) * alpha
        col = np.stack([1 + (t.r - 1) * alpha, 1 + (t.g - 1) * alpha, 1 + (t.b - 1) * alpha], axis=1)
        g.setAttribute('color', col, 3)
        return g

    key = _k('ao', geometry.uuid, y0, y1, strength, tint)
    return cachedGeo(key, make)
