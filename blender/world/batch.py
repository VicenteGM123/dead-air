# World-space UV batching for the station graybox (port of src/world/batch.js). Faces, boxes and planar polygons
# are collected per (group, surface) bucket and baked into ONE mesh per bucket whose UVs are world metres divided
# by the surface's tile size: textures run continuously across wall pieces, corners and floors of any size,
# nothing stretches, and coplanar pieces shade identically (no visible seams or z-fight between them).
# Every vertex carries a color used as fake AO (GDD §3.5): wall faces darken toward the floor (and slightly
# under the ceiling), floors and ceilings darken along their edges, tinted plum instead of black.
#
# UV convention (u to the viewer's right, v up; floors: v = north):
#   +x face u=-z  -x face u=z  +z face u=x  -z face u=-x  (v=y)   +y face u=x v=-z   -y face u=x v=z
# (three.js UVs: the mesh writer stores them for glTF so Godot sees exactly these values, SPEC §5.3.)
#
# API (same as batch.js; three.js coordinates)
#   Batch(surfaces)              surfaces.get(key) -> { 'mat', 'tile': [u, v] } (materials use vertexColors)
#   vface(group, key, axis, at, sign, a0, a1, y0, y1, ao=0, top=None, topAo=0.18)
#   hface(group, key, x0, z0, x1, z1, y, up, border=0, ao=0)
#   box(group, key, min, max, skip={px,nx,py,ny,pz,nz}, ao=0)
#   poly(group, key, pts, normal, ao=None)
#   build(emit(group, key, arrays)) -> list of what emit returned, one per non-empty bucket
#       arrays = { 'pos': [x,y,z,...], 'nrm': [...], 'uv': [u,v,...], 'col': [r,g,b,...] (LINEAR), 'idx': [...] }
#   AO_TINT (linear rgb), AO_H

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from dalib.mathutils3 import Color  # noqa: E402  (three.js Color: '#hex' -> LINEAR components)

AO_H = 0.9
_t = Color('#3A2A5A')
AO_TINT = (_t.r, _t.g, _t.b)


def smooth(e0, e1, x):
    t = min(1, max(0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


class Batch:
    def __init__(self, surfaces):
        self.surfaces = surfaces
        self.buckets = {}   # insertion order = the JS Map order

    def _bucket(self, group, key):
        bid = '%s|%s' % (group, key)
        b = self.buckets.get(bid)
        if b is None:
            b = {'group': group, 'key': key, 'tile': self.surfaces.get(key)['tile'],
                 'pos': [], 'nrm': [], 'uv': [], 'col': [], 'idx': []}
            self.buckets[bid] = b
        return b

    # One vertex: position, normal, world UV from the normal's dominant axis, AO darkening k (0..1).
    def _vert(self, b, x, y, z, nx, ny, nz, k):
        tu, tv = b['tile']
        ax, ay, az = abs(nx), abs(ny), abs(nz)
        if ay >= ax and ay >= az:
            u = x
            v = -z if ny > 0 else z
        elif ax >= az:
            u = -z if nx > 0 else z
            v = y
        else:
            u = x if nz > 0 else -x
            v = y
        b['pos'] += [x, y, z]
        b['nrm'] += [nx, ny, nz]
        b['uv'] += [u / tu, v / tv]
        b['col'] += [1 + (AO_TINT[0] - 1) * k, 1 + (AO_TINT[1] - 1) * k, 1 + (AO_TINT[2] - 1) * k]
        return len(b['pos']) // 3 - 1

    # Quad from 4 vertex indices in counter-clockwise order seen from the front.
    def _quad(self, b, a, c, d, e):
        b['idx'] += [a, c, d, a, d, e]

    def vface(self, group, key, axis, at, sign, a0, a1, y0, y1, ao=0, top=None, topAo=0.18):
        if y1 - y0 < 1e-4 or a1 - a0 < 1e-4:
            return
        b = self._bucket(group, key)
        ys = [y0]
        if ao > 0 and AO_H > y0 and AO_H < y1:
            ys.append(AO_H)
        if top is not None and top - 0.6 > ys[-1] + 1e-3 and top - 0.6 < y1:
            ys.append(top - 0.6)
        ys.append(y1)

        def kAt(y):
            return min(0.85, ao * (1 - smooth(0, AO_H, y)) + (topAo * smooth(top - 0.6, top, y) if top is not None else 0))
        nx = sign if axis == 'x' else 0
        nz = sign if axis == 'z' else 0
        # Along-axis endpoints ordered so the winding faces +normal.
        flip = sign > 0 if axis == 'x' else sign < 0
        s0, s1 = (a1, a0) if flip else (a0, a1)

        def P(s, y):
            return (at, y, s) if axis == 'x' else (s, y, at)
        prev = None
        for y in ys:
            k = kAt(y)
            p, q = P(s0, y), P(s1, y)
            row = [self._vert(b, *p, nx, 0, nz, k), self._vert(b, *q, nx, 0, nz, k)]
            if prev:
                self._quad(b, prev[0], prev[1], row[1], row[0])
            prev = row

    def hface(self, group, key, x0, z0, x1, z1, y, up, border=0, ao=0):
        if x1 - x0 < 1e-4 or z1 - z0 < 1e-4:
            return
        b = self._bucket(group, key)
        bx = min(border, (x1 - x0) / 2 - 1e-3)
        bz = min(border, (z1 - z0) / 2 - 1e-3)
        xs = [x0, x0 + bx, x1 - bx, x1] if border > 0 else [x0, x1]
        zs = [z0, z0 + bz, z1 - bz, z1] if border > 0 else [z0, z1]
        ny = 1 if up else -1
        grid = []
        for j, z in enumerate(zs):
            row = []
            for i, x in enumerate(xs):
                edge = i == 0 or j == 0 or i == len(xs) - 1 or j == len(zs) - 1
                row.append(self._vert(b, x, y, z, 0, ny, 0, ao if border > 0 and edge else 0))
            grid.append(row)
        for j in range(len(zs) - 1):
            for i in range(len(xs) - 1):
                a, c, d, e = grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]
                # Seen from +y the (x->, z down) grid runs clockwise; flip for the up-facing side.
                if up:
                    self._quad(b, a, e, d, c)
                else:
                    self._quad(b, a, c, d, e)

    def box(self, group, key, mn, mx, skip=None, ao=0):
        skip = skip or {}
        x0, y0, z0 = mn
        x1, y1, z1 = mx
        if not skip.get('py'):
            self.hface(group, key, x0, z0, x1, z1, y1, True)
        if not skip.get('ny'):
            self.hface(group, key, x0, z0, x1, z1, y0, False)
        if not skip.get('px'):
            self.vface(group, key, 'x', x1, 1, z0, z1, y0, y1, ao=ao)
        if not skip.get('nx'):
            self.vface(group, key, 'x', x0, -1, z0, z1, y0, y1, ao=ao)
        if not skip.get('pz'):
            self.vface(group, key, 'z', z1, 1, x0, x1, y0, y1, ao=ao)
        if not skip.get('nz'):
            self.vface(group, key, 'z', z0, -1, x0, x1, y0, y1, ao=ao)

    def poly(self, group, key, pts, normal, ao=None):
        b = self._bucket(group, key)
        ln = math.sqrt(normal[0] ** 2 + normal[1] ** 2 + normal[2] ** 2) or 1
        n = (normal[0] / ln, normal[1] / ln, normal[2] / ln)
        ids = [self._vert(b, p[0], p[1], p[2], n[0], n[1], n[2], ao[i] if ao else 0) for i, p in enumerate(pts)]
        # Wind the fan so it faces `normal` whatever order the points came in.
        e1 = [pts[1][i] - pts[0][i] for i in range(3)]
        e2 = [pts[2][i] - pts[0][i] for i in range(3)]
        cr = (e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0])
        flip = cr[0] * n[0] + cr[1] * n[1] + cr[2] * n[2] < 0
        for i in range(1, len(ids) - 1):
            if flip:
                b['idx'] += [ids[0], ids[i + 1], ids[i]]
            else:
                b['idx'] += [ids[0], ids[i], ids[i + 1]]

    def build(self, emit):
        out = []
        for b in self.buckets.values():
            if not b['idx']:
                continue
            out.append(emit(b['group'], b['key'], b))
        self.buckets.clear()
        return out
