# Windows and Yard entries (port of the geometry half of src/world/windows.js, GDD §5.4, §5.9): frames per window
# style, the six scenery-flat board meshes (one per slice of the board atlas), the fence-climb spots and the ajar
# chain-link vehicle gate. The board instances, their rest poses (Math.random jitter) and the tear/repair
# animations are runtime work: godot/scripts/world/windows.gd (one MultiMeshInstance3D per slice).
#
# buildWindows(ctx) -> { 'boards': [6 board meshes boards_0..boards_5] }   ctx = { game, surf, group(areaId) }
#   Frames go into their area group as window_<id> (glass shards, hazard stripe, dock bumpers included), fence
#   climbs as climb_<id> (pallet + oil drum), the gate as gate_<id> (posts, two chain-link leaves — the east one
#   ajar — and the hanging chain).

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from world import wk  # noqa: E402
from world.wk import geo, THREE  # noqa: E402
from world.layout import WINDOWS, WALL_T, FENCE_H  # noqa: E402
from world.surfaces import AREA_STYLE  # noqa: E402

PI = math.pi
H = WALL_T / 2
SLICES = 6
BOARD_H = 0.22
BOARD_T = 0.05


def buildWindows(ctx):
    boarded = [w for w in WINDOWS if w['type'] == 'boarded']
    boards = boardMeshes(ctx, len(boarded))
    for w in WINDOWS:
        pivot = _pivot(w)
        if w['type'] == 'boarded':
            buildFrame(ctx, w, pivot)
        elif w['type'] == 'fence':
            buildClimb(ctx, w, pivot)
        else:
            buildGate(ctx, w, pivot)
    return {'boards': boards}


def _pivot(w):
    nx, nz = w['inside'][0] - w['outside'][0], w['inside'][2] - w['outside'][2]
    ln = math.hypot(nx, nz)
    return {'pos': [w['wall'][0], 0, w['wall'][1]], 'rotY': math.atan2(nx / ln, nz / ln)}


# ------------------------------------------------------------------------------------------ board meshes
def boardMeshes(ctx, count):
    """BoardSet: one mesh per scenery slice (the runtime instances them, one instance per boarded window)."""
    mat = ctx['surf'].plain('boards')
    out = []
    for k in range(SLICES):
        ln = 2.05 if k < 4 else 2.15
        m = wk.Mesh(boardGeometry(ln, k), mat)
        m.name = 'boards_%d' % k
        m.castShadow = True
        m.receiveShadow = True
        m.userData.dynamic = True
        m.userData.instances = count
        out.append(m)
    return out


# A plank with the scenery slice on its two big faces and raw plywood on the edges (texture band 6).
def boardGeometry(ln, slice_):
    g = geo.roundedBox(ln, BOARD_H, BOARD_T, 0.015, 2).clone()
    uv, n = g.attributes.uv, g.attributes.normal
    for i in range(uv.count):
        face = abs(n.getZ(i)) > 0.7
        band = slice_ if face else 6
        uv.setY(i, 1 - (band + 1) / 7 + (0.06 + uv.getY(i) * 0.88) / 7)
    return g


# ---------------------------------------------------------------------------------------------- frames
def frameMaterial(ctx, w):
    M = ctx['game']['mats']
    if w['style'] == 'glass_door':
        return M.toon('#6E5A44', {'metal': 0.55, 'rough': 0.35, 'rimColor': '#FFC98A'})
    if w['style'] == 'window':
        return ctx['surf'].plain(AREA_STYLE[w['area']]['wall']['baseboard'])
    return ctx['surf'].plain('trim_steel')


def shard(M, pts):
    s = THREE.Shape()
    s.moveTo(pts[0], pts[1])
    for i in range(2, len(pts), 2):
        s.lineTo(pts[i], pts[i + 1])
    m = wk.Mesh(THREE.ShapeGeometry(s), M.glass('#CFE8FF', {'opacity': 0.35}))
    return m     # new THREE.Mesh: castShadow / receiveShadow false


# Frame: jambs + head wrapping the wall ends, FRAME_PROUD proud of both faces (deeper than any wall trim), the
# inner faces FRAME_INSET inside the opening (architecture.py does not draw the jamb caps, soffit and sill top
# they cover: drawn in the same planes they z-fought). The jambs stand on the sill board and stop under the head
# (no overlapping, coplanar corner blocks).
FRAME_PROUD = 0.05
FRAME_INSET = 0.005
FRAME_W = 0.12


def _place(g, pivot):
    g.position.set(*pivot['pos'])
    g.rotation.set(0, pivot['rotY'], 0)


def buildFrame(ctx, w, pivot):
    M = ctx['game']['mats']
    g = wk.group('window_' + w['id'])
    _place(g, pivot)
    mat = frameMaterial(ctx, w)
    I, W, D = FRAME_INSET, w['width'], 2 * (H + FRAME_PROUD)
    jy0, jy1, jw = w['sill'], w['top'] - I, FRAME_W + I
    for s in [-1, 1]:
        g.add(wk.mesh(geo.roundedBox(jw, jy1 - jy0, D, 0.02, 2), mat, pos=[s * (W / 2 - I + jw / 2), (jy0 + jy1) / 2, 0]))
    g.add(wk.mesh(geo.roundedBox(W + 2 * FRAME_W, FRAME_W + I, D, 0.02, 2), mat, pos=[0, jy1 + (FRAME_W + I) / 2, 0]))
    if w['sill'] > 0:
        g.add(wk.mesh(geo.roundedBox(W + 0.34, 0.06, D + 0.14, 0.02, 2), mat, pos=[0, w['sill'] - 0.03, 0.07]))
    else:
        g.add(wk.mesh(geo.roundedBox(W - 2 * I, 0.04, D, 0.01, 1), mat, pos=[0, 0.02, 0]))
    if w['style'] == 'glass_door':
        # Storefront door remains: the aluminium kick rail and broken glass along the frame.
        g.add(wk.mesh(geo.roundedBox(W - 2 * I, 0.3, 0.05, 0.02, 2), mat, pos=[0, 0.2, -0.02]))
    if w['style'] in ('loading', 'dock'):
        # Hazard stripe decal under the sill, 6 mm off the wall (4 mm shimmered across Studio A).
        hz = M.toon('#ffffff', {'map': ctx['game']['tex'].stripes(['#F4C21E', '#231E24'], True, 12), 'rough': 0.6, 'rim': 0})
        g.add(wk.mesh(geo.plane(W + 0.2, 0.14), hz, pos=[0, w['sill'] - 0.13, H + 0.006], cast=False))
    if w['style'] == 'dock':
        rubber = M.toon('#231E24', {'rough': 0.9})
        for s in [-1, 1]:
            g.add(wk.mesh(geo.roundedBox(0.25, 0.3, 0.14, 0.04, 2), rubber, pos=[s * 0.62, w['sill'] - 0.2, -(H + 0.07)]))
    x0, x1, y0, y1 = -W / 2, W / 2, w['sill'], w['top']
    for pts in [
        [x0, y1, x0 + 0.45, y1, x0, y1 - 0.35],
        [x1, y1, x1, y1 - 0.5, x1 - 0.22, y1],
        [x0, y0, x0, y0 + 0.3, x0 + 0.18, y0],
        [x1, y0 + 0.02, x1 - 0.4, y0 + 0.02, x1 - 0.1, y0 + 0.22],
    ]:
        m = shard(M, pts)
        m.position.z = -0.01
        g.add(m)
    ctx['group'](w['area']).add(g)


# Fence climb: a pallet leaning on the chain-link outside and an oil drum to step on.
def buildClimb(ctx, w, pivot):
    M = ctx['game']['mats']
    g = wk.group('climb_' + w['id'])
    _place(g, pivot)
    wood = M.toon('#A8784A', {'map': ctx['game']['tex'].woodPanel('#A8784A'), 'rough': 0.7})
    pallet = wk.group()
    for i in range(5):
        pallet.add(wk.mesh(geo.roundedBox(0.16, 1.2, 0.03, 0.01, 1), wood, pos=[-0.48 + i * 0.24, 0, 0]))
    for y in [-0.5, 0, 0.5]:
        pallet.add(wk.mesh(geo.roundedBox(1.1, 0.1, 0.1, 0.02, 1), wood, pos=[0, y, -0.06]))
    pallet.position.set(-0.2, 0.62, -0.3)
    pallet.rotation.set(-0.28, 0, 0.04)
    g.add(pallet)
    drum = M.toon('#B5472A', {'metal': 0.4, 'rough': 0.5})
    g.add(wk.mesh(geo.cylinder(0.29, 0.29, 0.88, 18), drum, pos=[0.55, 0.44, -0.55]))
    for y in [0.25, 0.63]:
        g.add(wk.mesh(geo.torus(0.295, 0.02, 6, 24), drum, pos=[0.55, y, -0.55], rot=[PI / 2, 0, 0]))
    ctx['group'](w['area']).add(g)


# Vehicle gate: two chain-link leaves; the east leaf hangs ajar into the Yard leaving a squeeze gap.
def buildGate(ctx, w, pivot):
    M = ctx['game']['mats']
    g = wk.group('gate_' + w['id'])
    _place(g, pivot)
    steel = ctx['surf'].plain('galvanized')
    link = ctx['surf'].plain('chainlink')
    W = w['width']
    lw, lh = W / 2 - 0.08, FENCE_H - 0.25
    for s in [-1, 1]:
        g.add(wk.mesh(geo.cylinder(0.075, 0.075, FENCE_H + 0.25, 12), steel, pos=[s * W / 2, (FENCE_H + 0.25) / 2, 0]))

    def leaf(s):
        hinge = wk.group('gate_leaf_%s' % ('w' if s < 0 else 'e'))
        hinge.position.set(s * (W / 2 - 0.05), 0, 0)
        c = -s * lw / 2

        def tube(ln, pos, rot=None):
            hinge.add(wk.mesh(geo.cylinder(0.035, 0.035, ln, 8), steel, pos=pos, rot=rot))
        tube(lh, [-s * 0.02, 0.1 + lh / 2, 0])
        tube(lh, [-s * lw, 0.1 + lh / 2, 0])
        for y in [0.1, 0.1 + lh]:
            tube(lw, [c, y, 0], [0, 0, PI / 2])
        tube(math.hypot(lw, lh), [c, 0.1 + lh / 2, 0], [0, 0, s * math.atan2(lw, lh)])
        cl = THREE.PlaneGeometry(lw, lh)
        uv = cl.attributes.uv
        for i in range(uv.count):
            uv.setXY(i, uv.getX(i) * lw / 0.5, uv.getY(i) * lh / 0.5)
        hinge.add(wk.mesh(cl, link, pos=[c, 0.1 + lh / 2, 0], cast=False))
        g.add(hinge)
        return hinge
    leaf(-1)
    leaf(1).rotation.y = 0.42
    chain = M.toon('#9AA0A8', {'metal': 0.85, 'rough': 0.3})
    for i in range(7):
        m = wk.mesh(geo.torus(0.035, 0.009, 6, 10), chain, pos=[-0.03, 1.25 - i * 0.07, 0.04], cast=False)
        m.rotation.y = PI / 2 if i % 2 else 0
        g.add(m)
    ctx['group'](w['area']).add(g)
