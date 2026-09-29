"""DEAD AIR — the meshes the NEWSROOM and MASTER CONTROL dressing code added straight under the room root (port of the
static geometry of build() in src/world/rooms/newsroom.js and src/world/rooms/master_control.js, line by line, in
world coordinates like the JS; the placed library / room props are NOT here: the room scripts place them).

godot/assets/runtime/rooms_newsroom_mc/newsroom.glb  root 'newsroom_dressing'
    nr_wash                   the backdrop's additive blue wash (washMat, renderOrder 2; level switched by power)
    nr_slats_0 / nr_slats_1   the moonlight slats on the floor under B4 / B5 (slatMat, renderOrder 1)
    nr_map_slats              the slats across the weather map (slatMat, renderOrder 3)
    merged_*                  everything static (batten drop rods, paper stacks, crumpled balls, floor papers and
                              decals, the teletype corner's fan-fold pile + newspaper bundles, the west-wall
                              assignment board, schedule / QUIET / promo sheets, the tipped cup, the floor cable)
                              merged per material like the JS level merge (kit.merge)
godot/assets/runtime/rooms_newsroom_mc/master_control.glb  root 'master_control_dressing'
    mc_leds                   the rack status LED speckle (one mesh, UVs into a N x 1 live canvas: runtime texture,
                              rooms/master_control.gd draws it)
    mc_vtr2_tape              VTR #2's threaded tape bands (VTR-local coordinates, hidden: the room script moves it
                              under the VTR)
    mc_wall_steel             hidden carrier of the monitor wall's dark brushed-steel material (swap target)
    merged_*                  everything static (signs, the Perpetua ad + tape clips + the floor copy, decals, the
                              tipped mug, papers, the cable looms from the trays, the anti-static floor mats, the LED
                              strip bars)
The additive washes / slats are exported as MeshBasicMaterial specs with their base colour (the room script clones
them and sets the level: colour x level); decals keep the JS toon spec (no polygonOffset in Godot).

Run: python3 blender/build_all.py --only runtime (build(save_blend)), or standalone:
     cd /home/user/dead-air && python3 blender/runtime/rooms_newsroom_mc.py [--save-blend] [--godot DIR]
"""
import json
import math
import os
import sys

import numpy as np

_HERE = os.path.dirname(os.path.abspath(__file__))
_BLENDER = os.path.dirname(_HERE)
if _BLENDER not in sys.path:
    sys.path.insert(0, _BLENDER)

from dalib import kit as K  # noqa: E402
from dalib.kit import THREE, PAL  # noqa: E402
from dalib.rng import mulberry32  # noqa: E402
from dalib.tex import RuntimeTexture  # noqa: E402
from props.rooms_newsroom_mc import (stdMats, atlas, mcAtlas, quad, qf, ribbon, tc, additive, slatTex, washTex,  # noqa: E402
                                     hash_, WALL)

REPO = os.path.dirname(_BLENDER)
GODOT = os.path.join(REPO, 'godot')
OUT_DIR = os.path.join(GODOT, 'assets', 'runtime', 'rooms_newsroom_mc')
BLEND_DIR = os.path.join(_BLENDER, 'out')
PI = math.pi
HP = PI / 2
TAU = PI * 2
DESK_TOP = 0.76


def _layoutArea(areaId):
    try:
        with open(os.path.join(GODOT, 'data', 'layout.json'), 'r', encoding='utf-8') as f:
            d = json.load(f)
        for a in d.get('AREAS', []):
            if a.get('id') == areaId:
                return a
    except (OSError, ValueError):
        pass
    return {'id': areaId}


def _ensureColors(root):
    """master_control.js ensureColors (and what the JS level merge does for the newsroom meshes): meshes whose
    material wants vertex colours get a white colour attribute."""
    def f(o):
        if not getattr(o, 'isMesh', False) or o.material is None or isinstance(o.material, list) or not o.material.vertexColors:
            return
        g = o.geometry
        if g is None or g.attributes.color is not None:
            return
        c = g.clone()
        c.setAttribute('color', THREE.BufferAttribute(np.ones((c.attributes.position.count, 3)), 3))
        o.geometry = c
    root.traverse(f)


# ================================================================================================= newsroom
def buildNewsroom(game):
    root = THREE.Group()
    root.name = 'newsroom_dressing'
    mt = stdMats(game)
    A = atlas(game)
    rnd = mulberry32(1313)

    def add(mesh):
        root.add(mesh)
        return mesh

    def floorDecal(name, x, z, s, rot=0):
        return add(K.m(quad(s, s, A.dcell(name)), A.decal, {'pos': [x, 0.004, z], 'rot': [-HP, 0, rot], 'cast': False, 'receive': True}))

    def sheet(cellName, x, y, z, w, h, rot=0, tilt=-HP):
        return add(K.m(quad(w, h, A.cell(cellName)), A.mat, {'pos': [x, y, z], 'rot': [tilt, 0, rot], 'cast': False}))

    # -------------------------------------------------------------------------------- anchor riser (hero)
    # batten drop rods (the batten and its Fresnels are placed props)
    batY = 3.52
    for z in [-1.3, 1.3]:
        add(K.m(K.cyl(0.015, 0.015, 4.0 - batY, {'seg': 8}), mt.chrome, {'pos': [18.1, batY, z]}))

    # ------------------------------------------------------------------------ skyline backdrop + world clocks
    skyZ, skyW = 0.5, 4.2
    washMat = additive(washTex(), '#2E6BD9', 0)
    wash = add(K.m(quad(skyW, 3.2), washMat, {'pos': [22.7, 1.95, skyZ], 'rot': [0, -HP, 0], 'cast': False, 'receive': False}))
    wash.userData.noMerge = True
    wash.renderOrder = 2
    wash.name = 'nr_wash'

    # --------------------------------------------------------------------------------------- reporter desks
    def stack(x, z, n, r0):
        for i in range(n):
            add(K.m(quad(0.22, 0.28, A.cell('page' if i == n - 1 else 'cream')), A.mat,
                    {'pos': [x, DESK_TOP + 0.003 + i * 0.004, z], 'rot': [-HP, 0, r0 + (rnd() - 0.5) * 0.15], 'cast': False}))
    stack(10.35, -3.85, 5, 0.3)

    # floor clutter: papers, crumpled balls, trash cans (placed props), a spilled folder
    def ball(x, z):
        return add(K.m(tc(THREE.IcosahedronGeometry(0.045, 1), '#F4EEDC'), mt.paint, {'pos': [x, 0.04, z], 'rot': [rnd() * 3, rnd() * 3, 0]}))
    for x, z in [[12.3, -4.4], [12.05, -4.55], [14.2, -2.2], [9.6, -0.6], [17.2, -1.4], [16.4, 0.2]]:
        ball(x, z)
    for i, (x, z, r) in enumerate([[12.6, -2.1, 0.4], [13.4, -1.8, -0.8], [14.8, -0.7, 1.2], [9.9, -1.9, 2.4], [17.0, -2.4, 0.2], [16.6, -0.3, -1.0], [11.4, -0.4, 0.9]]):
        add(K.m(quad(0.22, 0.28, A.cell('news' if i % 3 == 0 else 'page')), A.mat, {'pos': [x, 0.006 + i * 0.0006, z], 'rot': [-HP, 0, r], 'cast': False}))
    floorDecal('scuff', 13.2, -1.2, 2.2, 0.3)
    floorDecal('scuff', 17.2, 0.6, 1.8, 1.6)
    floorDecal('dust', 9.2, -4.9, 1.6, 0)

    # ----------------------------------------------------------------------------- teletype corner (NW)
    # fan-fold printout pile + newspaper bundles beside it
    for i in range(7):
        add(K.m(tc(K.box(0.36, 0.022, 0.28, 'xs'), '#F4EBC8' if i % 2 else '#E9DFB8'), mt.paint,
                {'pos': [7.55, 0.011 + i * 0.022, -5.45], 'rot': [0, (rnd() - 0.5) * 0.3, 0]}))
    add(K.m(quad(0.36, 0.28, A.cell('wire')), A.mat, {'pos': [7.55, 0.17, -5.45], 'rot': [-HP, 0, 0.1], 'cast': False}))
    for i in range(3):
        bx = 7.62 + (0.05 if i == 2 else 0)
        by = 0.14 if i == 2 else 0
        bz = -4.7 + (0.33 if i == 1 else 0)
        add(K.m(tc(K.box(0.42, 0.14, 0.3, 'sm'), '#E6DECB'), mt.paint, {'pos': [bx, 0.07 + by, bz], 'rot': [0, 0.2 * (i - 1), 0]}))
        add(K.m(quad(0.4, 0.28, A.cell('news')), A.mat, {'pos': [bx, 0.142 + by, bz], 'rot': [-HP, 0, 0.2 * (i - 1)], 'cast': False}))
        add(K.m(tc(K.box(0.02, 0.145, 0.31, 'xs'), '#B5472A'), mt.paint, {'pos': [bx, 0.072 + by, bz], 'rot': [0, 0.2 * (i - 1), 0]}))
    # west wall: assignment board (cabinet, cork board, coat tree, clock are placed props)
    add(K.m(tc(K.box(1.16, 0.84, 0.05, 'sm'), '#7A4A2A'), mt.lacquer, {'pos': [7.19, 1.92, -3.0], 'rot': [0, HP, 0]}))
    sheet('assign', 7.225, 1.92, -3.0, 1.04, 0.72, 0, 0).rotation.set(0, HP, 0)

    # ------------------------------------------------------------------------------------- north wall
    floorDecal('stain', 10.1, -5.0, 0.55, 0.8)
    add(K.m(tc(THREE.CylinderGeometry(0.028, 0.02, 0.07, 10, 1, True), '#F4F1E8'), mt.plastic, {'pos': [9.8, 0.02, -4.95], 'rot': [HP, 0, 0.6]}))
    sheet('sched', 14.1, 2.45, -5.83, 0.75, 0.75, 0, 0).rotation.set(0, 0, 0.02)
    sheet('quiet', 11.95, 3.02, -5.83, 0.55, 0.55, 0, 0)

    # ------------------------------------------------------------------------------ south wall + camera
    sheet('promo', 20.6, 2.35, 3.83, 0.8, 0.8, 0, 0).rotation.set(0, PI, 0)
    add(K.m(ribbon([[16.9, 0.02, 2.5], [16.6, 0.012, 2.9], [16.1, 0.012, 3.1], [15.8, 0.012, 3.7]], 0.04, {'seg': 16}), K.mat(game, 'rubber', '#2A2230'), {'cast': False}))

    # ------------------------------------------------------------------------------ moonlight slats (B4/B5)
    slatMat = additive(slatTex(6), '#9FB6FF', 0.5)
    for i, x in enumerate([14, 19]):
        m = add(K.m(quad(1.7, 2.3), slatMat, {'pos': [x + 0.25, 0.012, 2.65], 'rot': [-HP, 0, 0.12], 'cast': False, 'receive': False}))
        m.renderOrder = 1
        m.userData.noMerge = True
        m.name = 'nr_slats_%d' % i
    mapSlats = add(K.m(quad(2.3, 1.7), slatMat, {'pos': [17.6, 1.95, -5.8], 'rot': [0, 0, 0.5], 'cast': False, 'receive': False}))
    mapSlats.renderOrder = 3
    mapSlats.userData.noMerge = True
    mapSlats.name = 'nr_map_slats'

    _ensureColors(root)
    K.merge(root)
    return root


# ============================================================================================ master control
def loom(root, mt, a, b, sag=0.25, seed=1):
    """A drooping cable loom from (a) down to (b) (world coords, added under root): 4 coloured strands."""
    cols = ['#2A2231', '#E3662B', '#2F5BD3', '#E8A92E']
    for i, c in enumerate(cols):
        o = (i - 1.5) * 0.028
        mid = [(a[0] + b[0]) / 2 + o, max(a[1], b[1]) - (abs(a[1] - b[1]) * 0.45) - sag * (1 + hash_(seed + i) * 0.3), (a[2] + b[2]) / 2 + o]
        root.add(K.m(tc(K.tube([[a[0] + o, a[1], a[2] + o], mid, [b[0] + o, b[1], b[2] + o]], 0.013, {'seg': 14, 'radial': 5}), c), mt.rubber, {'cast': False}))


# Anti-static rubber floor mat: ribbed dark slate with a yellow safety edge (walkable, no collider).
def mcMatTex():
    def draw(ctx, w, h, rand):
        ctx.fillStyle = '#3C4556'
        ctx.fillRect(0, 0, w, h)
        y = 0
        while y < h:
            ctx.fillStyle = 'rgba(255,255,255,0.06)'
            ctx.fillRect(0, y, w, 3)
            ctx.fillStyle = 'rgba(0,0,0,0.12)'
            ctx.fillRect(0, y + 4, w, 2)
            y += 8
    return K.tex.canvas('rooms.mc.floormat.v1', 128, 128, draw, {'repeat': True})


def floorMat(game, root, mt, x0, z0, x1, z1):
    w, d = x1 - x0, z1 - z0
    mp = mcMatTex()
    m = K.mat(game, 'rubber', '#ffffff', {'map': mp, 'rim': 0})
    g = THREE.PlaneGeometry(w, d).rotateX(-HP)
    K.uvScale(g, w * 1.2, d * 1.2)
    root.add(K.m(tc(g, '#ffffff'), m, {'pos': [(x0 + x1) / 2, 0.005, (z0 + z1) / 2], 'cast': False}))
    e = 0.05
    for cx, cz, sx, sz in [[(x0 + x1) / 2, z0 + e / 2, w, e], [(x0 + x1) / 2, z1 - e / 2, w, e], [x0 + e / 2, (z0 + z1) / 2, e, d], [x1 - e / 2, (z0 + z1) / 2, e, d]]:
        root.add(K.m(tc(THREE.PlaneGeometry(sx, sz).rotateX(-HP), '#E8B820'), mt.paint, {'pos': [cx, 0.007, cz], 'cast': False}))


# The rack status LED strips (master_control.js ledSpeckle, geometry half): the bar mesh (static) and ONE merged
# LED mesh whose UVs index a N x 1 canvas (1 px per LED; the live canvas is drawn by rooms/master_control.gd).
LED_STRIPS = [
    {'pos': [23.64, 2.02, WALL.n + 0.6], 'rot': PI, 'len': 0.56, 'n': 8},
    {'pos': [24.28, 2.02, WALL.n + 0.6], 'rot': PI, 'len': 0.56, 'n': 8},
] + [{'pos': [WALL.w + 0.6, 2.02, z], 'rot': -HP, 'len': 0.56, 'n': 8} for z in [-9.3, -8.66, -8.02]] + [
    {'pos': [WALL.e - 0.42, 1.1, -10.55], 'rot': HP, 'len': 0.5, 'n': 6},
]


def ledSpeckle(game, root, strips):
    N = sum(s['n'] for s in strips)
    tex = RuntimeTexture('rooms_mc_leds')
    tex.magFilter = THREE.NearestFilter
    tex.minFilter = THREE.NearestFilter
    tex.generateMipmaps = False
    mt = stdMats(game)
    geos, bars = [], []
    led = THREE.SphereGeometry(0.011, 6, 4)
    k = 0
    for s in strips:
        dr = THREE.Vector3(math.cos(s['rot']), 0, -math.sin(s['rot']))        # along the strip (local +x rotated)
        out = THREE.Vector3(-math.sin(s['rot']), 0, -math.cos(s['rot']))     # strip front (local -z rotated)
        bar = K.box(s['len'], 0.05, 0.05, 0.01).clone().rotateY(s['rot']).translate(s['pos'][0], s['pos'][1], s['pos'][2])
        bars.append(tc(bar, '#2A2231'))
        for i in range(s['n']):
            t = (i + 0.5) / s['n'] - 0.5
            g = led.clone()
            uv = g.attributes.uv
            for j in range(uv.count):
                uv.setXY(j, (k + 0.5) / N, 0.5)
            g.translate(s['pos'][0] + dr.x * t * (s['len'] - 0.06) + out.x * 0.026, s['pos'][1] + 0.005, s['pos'][2] + dr.z * t * (s['len'] - 0.06) + out.z * 0.026)
            geos.append(g)
            k += 1
    root.add(K.m(THREE.mergeGeometries(bars, False), mt.plastic, {'cast': False}))
    mesh = K.m(THREE.mergeGeometries(geos, False), game.mats.glow('#ffffff', 1.6, {'map': tex}), {'cast': False})
    mesh.userData.noMerge = True
    mesh.name = 'mc_leds'
    root.add(mesh)
    return mesh


def buildMasterControl(game):
    root = THREE.Group()
    root.name = 'master_control_dressing'
    area = _layoutArea('master_control')
    mt = stdMats(game)
    NA = atlas(game)
    MA = mcAtlas(game)

    def add(m):
        root.add(m)
        return m

    # ------------------------------------------------------------------------------------ the 4 x 3 monitor wall
    # the wall's bright brushed aluminium is swapped for this darker steel by the room script (JS: wall.traverse
    # material === bright -> steel); a hidden carrier mesh exports the material.
    steel = K.mat(game, 'metal', '#ffffff', {'map': K.tex.brushed('#707B8E'), 'env': 0.22, 'rim': 0.16})
    carrier = add(K.m(K.box(0.01, 0.01, 0.01, 0), steel, {'pos': [31.4, -1, WALL.n + 0.26], 'cast': False}))
    carrier.name = 'mc_wall_steel'
    carrier.visible = False
    carrier.userData.noMerge = True

    # ------------------------------------------------------------------------------------ west wall: patch bays
    add(K.m(qf(0.24, 0.24, MA.cell('nosmoke')), MA.mat, {'pos': [WALL.w + 0.005, 2.5, -9.75], 'rot': [0, -HP, 0]}))

    # ------------------------------------------------------------------------------------ south wall: quad VTRs
    vz = WALL.s - 0.43
    add(K.m(qf(1.2, 0.3, MA.cell('vtrbay')), MA.mat, {'pos': [26.75, 2.5, WALL.s - 0.03]}))
    add(K.m(tc(K.box(1.26, 0.34, 0.03, 0.012), '#2A2231'), mt.plastic, {'pos': [26.75, 2.5, WALL.s - 0.012]}))
    # VTR #2 (EE step 5): the threaded tape bands (VTR-local; rooms/master_control.gd moves the group under VTR #2)
    tape = THREE.Group()
    tape.name = 'mc_vtr2_tape'
    tape.visible = False
    tape.userData.noMerge = True

    def band(a, b):
        va, vb = THREE.Vector3(a[0], a[1], a[2]), THREE.Vector3(b[0], b[1], b[2])
        ln = va.distanceTo(vb)
        m = K.m(tc(K.box(0.006, ln, 0.05, 0.002), '#A8823A'), mt.plastic, {'cast': False})
        m.position.copy(va).lerp(vb, 0.5)
        m.rotation.z = math.atan2(vb.y - va.y, vb.x - va.x) - HP
        tape.add(m)
    tz = -0.53
    band([-0.32, 1.16, tz], [-0.18, 1.06, tz])
    band([-0.18, 1.045, tz], [0.18, 1.045, tz])
    band([0.18, 1.06, tz], [0.32, 1.22, tz])
    root.add(tape)
    del vz

    # ------------------------------------------------------------------------------------ east wall: scopes, crate
    add(K.m(quad(0.5, 0.5, NA.cell('eng')).rotateY(-HP), NA.mat, {'pos': [WALL.e - 0.005, 2.05, -10.55]}))
    ad = K.getCard('perpetua_ad')
    adMat = K.mat(game, 'paint', '#ffffff', {'map': ad, 'rim': 0.1})
    add(K.m(THREE.PlaneGeometry(0.6, 0.8).rotateY(-HP), adMat, {'pos': [WALL.e - 0.006, 1.5, -4.1], 'rot': [0.03, 0, 0]}))
    for dy, dz in [[0.38, -0.28], [0.38, 0.28], [-0.38, -0.28], [-0.38, 0.28]]:
        add(K.m(tc(K.box(0.004, 0.05, 0.12, 0.002), '#9A9284'), mt.paint, {'pos': [WALL.e - 0.008, 1.5 + dy, -4.1 + dz], 'rot': [dz * 1.5, 0, 0], 'cast': False}))
    add(K.m(THREE.PlaneGeometry(0.34, 0.45).rotateX(-HP), adMat, {'pos': [32.7, 0.006, -4.75], 'rot': [0, 0.5, 0], 'cast': False}))

    # ------------------------------------------------------------------------------------ centre: toys + chairs
    # spilled coffee by the console + a tipped mug, papers
    add(K.m(quad(0.7, 0.7, NA.dcell('stain')), NA.decal, {'pos': [30.8, 0.004, -6.7], 'rot': [-HP, 0, 0.6], 'cast': False}))
    add(K.m(tc(K.lathe([[0, 0], [0.036, 0], [0.04, 0.09], [0.036, 0.09], [0.032, 0.008], [0, 0.008]], {'seg': 14}), PAL.wztvBlue), mt.lacquer, {'pos': [30.55, 0.04, -6.85], 'rot': [HP, 0.4, 0]}))
    for cell, x, z, r in [['page', 27.7, -6.6, 0.4], ['wire', 25.4, -6.0, -0.7], ['sched', 32.3, -8.9, 1.1], ['page', 24.6, -10.4, 2.2]]:
        add(K.m(quad(0.22, 0.28, NA.cell(cell)), NA.mat, {'pos': [x, 0.006, z], 'rot': [-HP, 0, r], 'cast': False}))
    add(K.m(quad(1.6, 1.6, NA.dcell('scuff')), NA.decal, {'pos': [26.8, 0.004, -5.0], 'rot': [-HP, 0, 0.2], 'cast': False}))
    add(K.m(quad(1.2, 1.2, NA.dcell('tapeX')), NA.decal, {'pos': [29.0, 0.004, -11.3], 'rot': [-HP, 0, 0.1], 'cast': False}))

    # ------------------------------------------------------------------------------------ overhead cable trays
    ceil = area['ceilY'] if area.get('ceilY') is not None else 3.6
    trayY = ceil - 0.36
    loom(root, mt, [30.4, trayY, -11.3], [30.4, 3.52, -13.45], 0.12, 1)
    loom(root, mt, [33.6, trayY, -11.3], [33.6, 3.52, -13.45], 0.12, 2)
    loom(root, mt, [29.0, trayY, -11.1], [29.0, 1.22, -9.7], 0.2, 3)
    loom(root, mt, [23.75, trayY, -12.9], [23.95, 1.99, -13.2], 0.1, 4)
    for z in [-9.3, -8.66, -8.02]:
        loom(root, mt, [23.75, trayY, z], [23.5, 1.99, z], 0.08, 5 + z)
    for x in [25.25, 26.75, 28.25]:
        loom(root, mt, [x - 0.3, ceil - 0.02, -2.4], [x - 0.3, 2.02, -2.45], 0.04, 9 + x)

    # ------------------------------------------------------------------------------------ floor mats
    floorMat(game, root, mt, 26.3, -11.5, 31.8, -6.7)
    floorMat(game, root, mt, 24.4, -4.7, 29.2, -3.25)
    floorMat(game, root, mt, 28.6, -13.3, 34.3, -11.75)

    # status LED speckle on the racks + scope cart (blinks after power)
    ledSpeckle(game, root, LED_STRIPS)

    _ensureColors(root)
    K.merge(root)
    return root


def _assets():
    game = K.Game()
    return {'newsroom': lambda: buildNewsroom(game), 'master_control': lambda: buildMasterControl(game)}


def build(save_blend=False, only=None, godot=None):
    """Builds both rooms' dressing GLBs into godot/assets/runtime/rooms_newsroom_mc/. Returns the written paths.
    godot: another Godot project root to write into (tests)."""
    from dalib import export as EX
    from dalib import tex as T
    out = OUT_DIR
    if godot:
        godot = os.path.abspath(godot)
        out = os.path.join(godot, 'assets', 'runtime', 'rooms_newsroom_mc')
        T.OUT_DIR = os.path.join(godot, 'assets', 'textures')
        T._index = None
    written = []
    for name, make in _assets().items():
        if only and name not in only:
            continue
        root = make()
        os.makedirs(out, exist_ok=True)
        path = os.path.join(out, name + '.glb')
        blend = os.path.join(BLEND_DIR, 'runtime_rooms_%s.blend' % name) if save_blend else None
        EX.export_graph(root, path, root_name=root.name, save_blend=blend)
        written.append(path)
        print('[runtime/rooms_newsroom_mc] %s' % path)
    return written


if __name__ == '__main__':
    args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
    only = args[args.index('--only') + 1].split(',') if '--only' in args else None
    gd = args[args.index('--godot') + 1] if '--godot' in args else None
    build(save_blend='--save-blend' in args, only=only, godot=gd)
