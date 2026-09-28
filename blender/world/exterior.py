# Everything outside the walls (port of src/world/exterior.js; always visible, never portal-culled): lawn, the
# station parking lot with stall lines, the front sidewalk and curb, the night street with its dashed centre line
# and sodium lamps (additive light pools), a row of neon-signed 70s storefronts across the street (what the lobby
# and newsroom windows look out on), a ring of skyline blocks with lit window grids, the night sky (gradient dome
# with a warm city glow on the horizon, twinkling stars, the moon and its halo; it follows the camera) and the
# transmitter tower placeholder (red/white lattice with blinking beacons, GDD §5.7).
#
# buildExterior(ctx) -> { 'sky': Group, 'beacons': Mesh }   ctx = { game, batch, surf, group(name) }  batch group /
#   mesh root: 'ext'.
# Node names the Godot side uses (godot/scripts/world/exterior.gd, the yard room): 'tower' (the lattice group),
# 'tower_beacons' (userData.mats = {dark, lit} specs), 'sky' -> 'sky_dome' (SphereGeometry(150, 32, 16); its shader
# is exterior.gd's), 'sky_stars' (900 stars as point quads: 4 vertices on the star, uv = corner, uv1 = (aSize,
# aPhase)), 'sky_moon' (26 m plane, moon texture), lamp_lenses / lamp_pools (renderOrder 2), skyline_beacons,
# sign_<text> (neon storefront signs).

import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from world import wk  # noqa: E402
from world.wk import geo, THREE, Vector3, Quaternion  # noqa: E402
from world.layout import ANCHORS  # noqa: E402
from dalib.rng import mulberry32  # noqa: E402
from dalib.pal import PAL  # noqa: E402
from dalib.canvas2d import Canvas  # noqa: E402

PI = math.pi
G = 'ext'
CITY = (22, -12)
SKY_R = 150


def buildExterior(ctx):
    rand = mulberry32(0x0d13a1)
    ground(ctx)
    street(ctx, rand)
    storefronts(ctx)
    skyline(ctx, rand)
    beacons = tower(ctx)
    sky = skyDome(ctx, rand)
    return {'sky': sky, 'beacons': beacons}


# --------------------------------------------------------------------------------------------------- ground
def ground(ctx):
    batch = ctx['batch']
    batch.hface(G, 'grass', -240, -260, 280, 11, -0.03, True)
    batch.hface(G, 'grass', -240, 23.5, 280, 220, -0.03, True)
    batch.hface(G, 'asphalt', -34, -48, 62, 6.15, -0.02, True)
    batch.hface(G, 'sidewalk', -34, 6.15, 62, 11, -0.01, True)
    batch.vface(G, 'sidewalk', 'z', 11, 1, -34, 62, -0.13, -0.01)
    # Parking stalls west of the station and along the service lane behind the studios.
    for i in range(7):
        x = -30 + i * 3
        for z0, z1 in [[-25, -20], [-12, -7], [2, 5.5]]:
            batch.hface(G, 'paint_line', x - 0.06, z0, x + 0.06, z1, -0.01, True)
    for i in range(11):
        x = -4 + i * 3
        batch.hface(G, 'paint_line', x - 0.06, -46, x + 0.06, -41, -0.01, True)   # paint 1 cm over the asphalt (5 mm shimmered far off)


# --------------------------------------------------------------------------------------------------- street
def street(ctx, rand):
    game, batch, group = ctx['game'], ctx['batch'], ctx['group']
    batch.hface(G, 'asphalt', -240, 11, 280, 20, -0.13, True)
    x = -236
    while x < 280:
        batch.hface(G, 'paint_yellow', x, 15.42, x + 3, 15.58, -0.12, True)
        x += 6
    batch.hface(G, 'sidewalk', -240, 20, 280, 23.5, -0.01, True)
    batch.vface(G, 'sidewalk', 'z', 20, -1, -240, 280, -0.13, -0.01)
    root = group(G)
    M = game['mats']
    pole = M.toon('#3A3440', {'metal': 0.4, 'rough': 0.5, 'rimColor': '#9FB6FF'})
    lens = M.glow(PAL.sodium, 2.4)
    pool = M.glow(PAL.sodium, 0.55, {'map': game['tex'].radial(), 'additive': True})
    lenses, pools = [], []

    def lamp(x, z, dir):
        root.add(wk.mesh(geo.cylinder(0.07, 0.1, 6.2, 10), pole, pos=[x, 3.1, z], cast=False))
        root.add(wk.mesh(geo.cylinder(0.05, 0.05, 1.5, 8), pole, pos=[x, 6.1, z + dir * 0.7], rot=[PI / 2, 0, 0], cast=False))
        root.add(wk.mesh(geo.roundedBox(0.34, 0.16, 0.62, 0.06, 2), pole, pos=[x, 6.05, z + dir * 1.45], cast=False))
        lenses.append(THREE.PlaneGeometry(0.26, 0.5).rotateX(PI / 2).translate(x, 5.965, z + dir * 1.45))
        pools.append(THREE.PlaneGeometry(9, 9).rotateX(-PI / 2).translate(x, 0.004, z + dir * 1.2))
    x = -30
    while x <= 62:
        lamp(x, 10.4, 1)
        x += 15
    x = -22.5
    while x <= 70:
        lamp(x + (rand() - 0.5), 21.1, -1)
        x += 15
    lm = wk.Mesh(THREE.mergeGeometries(lenses), lens)
    pm = wk.Mesh(THREE.mergeGeometries(pools), pool)
    lm.name = 'lamp_lenses'
    pm.name = 'lamp_pools'
    pm.renderOrder = 2
    lm.userData.noMerge = pm.userData.noMerge = True
    root.add(lm, pm)


# ---------------------------------------------------------------------------------------------- storefronts
SHOPS = [
    [-44, -27, 7.0, 'brick', 'BOWL-O-RAMA', '#FF5FA2'],
    [-26, -16, 5.5, 'stucco_teal', 'DINER', '#7FE7FF'],
    [-15, -2, 8.0, 'stucco_cream', 'TV REPAIR', '#FFC23A'],
    [-1, 9, 6.0, 'brick', None, None],
    [10, 23, 9.0, 'stucco_rust', 'MOTEL', '#FF3B30'],
    [24, 34, 6.5, 'stucco_cream', 'LIQUORS', '#52E04A'],
    [35, 49, 7.5, 'brick', 'DISCO', '#D64FD6'],
    [50, 64, 5.5, 'stucco_teal', None, None],
]


def storefronts(ctx):
    game, batch, group = ctx['game'], ctx['batch'], ctx['group']
    T = game['tex']
    root = group(G)
    M = game['mats']
    z0, z1 = 23.5, 34
    for x0, x1, h, key, sign, color in SHOPS:
        batch.box(G, key, [x0, 0, z0], [x1, h, z1], skip={'ny': True, 'pz': True}, ao=0.3)
        batch.box(G, 'trim_coping', [x0 - 0.1, h, z0 - 0.1], [x1 + 0.1, h + 0.25, z1], skip={'ny': True, 'pz': True})
        # Lit shop window band and, on the taller blocks, an upper floor of apartments.
        batch.vface(G, 'storefront', 'z', z0 - 0.02, -1, x0 + 0.8, x1 - 0.8, 0.7, 2.7)
        if h > 6.2:
            batch.vface(G, 'storefront', 'z', z0 - 0.02, -1, x0 + 0.8, x1 - 0.8, 3.9, h - 1.3)
        if not sign:
            continue
        w = min(x1 - x0 - 2, 1.1 * len(sign) + 1.2)
        face = T.labelTex(sign, {'w': 512, 'h': 128, 'fg': '#FFFFFF', 'bg': '#140E1C', 'border': color, 'pad': 0.14})
        m = wk.mesh(geo.plane(w, w / 4), M.glow(color, 1.8, {'map': face}), pos=[(x0 + x1) / 2, 3.35, z0 - 0.08],
                    rot=[0, PI, 0], cast=False, name='sign_' + sign)
        m.userData.noMerge = True
        root.add(m)
        if sign in ('DINER', 'MOTEL'):
            awning = M.toon('#ffffff', {'map': T.stripes(['#E23B3B' if color == '#FF3B30' else '#2E8C8C', '#F4F1E8'], True, 10), 'rough': 0.7})
            root.add(wk.mesh(geo.roundedBox(x1 - x0 - 1, 0.12, 1.6, 0.04, 2), awning, pos=[(x0 + x1) / 2, 2.95, z0 - 0.7],
                             rot=[-0.28, 0, 0], cast=False))


# ---------------------------------------------------------------------------------------------------- skyline
def skyline(ctx, rand):
    game, batch, group = ctx['game'], ctx['batch'], ctx['group']
    tops = []
    N = 46
    for i in range(N):
        a = (i / N) * PI * 2 + (rand() - 0.5) * 0.08
        north = max(0, -math.sin(a))
        r = 150 + rand() * 40
        x, z = CITY[0] + math.cos(a) * r, CITY[1] + math.sin(a) * r
        w, d = 10 + rand() * 14, 10 + rand() * 12
        h = 14 + rand() * 30 + north * 40 * rand()
        batch.box(G, 'skyline', [x - w / 2, -0.5, z - d / 2], [x + w / 2, h, z + d / 2], skip={'ny': True})
        tops.append([x, h, z])
    tops.sort(key=lambda p: -p[1])
    beacons = [THREE.SphereGeometry(0.6, 8, 6).translate(x, h + 1.2, z) for x, h, z in tops[:8]]
    m = wk.Mesh(THREE.mergeGeometries(beacons), game['mats'].glow('#FF3B30', 2.2, {'fog': False}))
    m.name = 'skyline_beacons'
    m.userData.noMerge = True
    group(G).add(m)


# ------------------------------------------------------------------------------------------------------ tower
def tower(ctx):
    game, group = ctx['game'], ctx['group']
    M = game['mats']
    x0, z0, x1, z1 = ANCHORS['tower_base']['rect']
    cx, cz, half = (x0 + x1) / 2, (z0 + z1) / 2, (x1 - x0) / 2
    HGT, TOP, LEVELS = ANCHORS['tower_base']['height'], 0.45, 10
    red = M.toon('#E23B3B', {'rough': 0.45, 'rimColor': '#9FB6FF', 'rim': 0.25})
    white = M.toon('#F4F1E8', {'rough': 0.45, 'rimColor': '#9FB6FF', 'rim': 0.25})
    concrete = M.toon('#8C8894', {'rough': 0.9})
    g = wk.group('tower')
    up = Vector3(0, 1, 0)

    def strut(a, b, r, mat):
        d = Vector3().subVectors(b, a)
        m = wk.mesh(geo.cylinder(r, r, d.length(), 6), mat, cast=r > 0.06)
        m.position.addVectors(a, b).multiplyScalar(0.5)
        m.quaternion.setFromUnitVectors(up, d.normalize())
        g.add(m)

    def corner(i, lvl):
        k = lvl / LEVELS
        s = half + (TOP - half) * k
        sx = -1 if i == 0 or i == 3 else 1
        sz = -1 if i < 2 else 1
        return Vector3(cx + sx * s, HGT * k, cz + sz * s)
    for lvl in range(LEVELS):
        mat = white if lvl % 2 else red
        for i in range(4):
            j = (i + 1) % 4
            strut(corner(i, lvl), corner(i, lvl + 1), 0.1 - lvl * 0.005, mat)
            strut(corner(i, lvl + 1), corner(j, lvl + 1), 0.04, mat)
            strut(corner(i, lvl), corner(j, lvl + 1), 0.035, mat)
            strut(corner(j, lvl), corner(i, lvl + 1), 0.035, mat)
    for i in range(4):
        c = corner(i, 0)
        g.add(wk.mesh(geo.roundedBox(0.8, 0.45, 0.8, 0.06, 2), concrete, pos=[c.x, 0.2, c.z], cast=False))
    strut(Vector3(cx, HGT, cz), Vector3(cx, HGT + 4, cz), 0.07, white)
    wk.mergeByMaterial(g, 'tower_m')
    group(G).add(g)

    lamps = []
    for lvl in [3.3, 6.6]:
        for i in [0, 2]:
            c = corner(i, lvl)
            lamps.append(THREE.SphereGeometry(0.22, 12, 8).translate(c.x, c.y + 0.25, c.z))
    lamps.append(THREE.SphereGeometry(0.3, 12, 8).translate(cx, HGT + 4.2, cz))
    dark = M.toon('#7A2222', {'rough': 0.3})
    lit = M.glow('#FF3B30', 3.2)
    beacon = wk.Mesh(THREE.mergeGeometries(lamps), dark)
    beacon.name = 'tower_beacons'
    beacon.userData.noMerge = True
    beacon.userData.mats = {'dark': dark.spec(), 'lit': lit.spec()}
    group(G).add(beacon)
    return beacon


# ------------------------------------------------------------------------------------------------------- sky
def moonTexture():
    c = Canvas(256, 256)
    x = c.getContext('2d')
    g = x.createRadialGradient(128, 128, 60, 128, 128, 128)
    g.addColorStop(0, 'rgba(255,244,214,0.55)')
    g.addColorStop(0.5, 'rgba(159,182,255,0.14)')
    g.addColorStop(1, 'rgba(159,182,255,0)')
    x.fillStyle = g
    x.fillRect(0, 0, 256, 256)
    x.fillStyle = '#FFF4D6'
    x.beginPath()
    x.arc(128, 128, 62, 0, PI * 2)
    x.fill()
    r = mulberry32(77)
    for _ in range(16):
        a, d, s = r() * PI * 2, r() * 48, 4 + r() * 12
        x.fillStyle = 'rgba(214,196,170,%s)' % _jsnum(0.35 + r() * 0.3)
        x.beginPath()
        x.arc(128 + math.cos(a) * d, 128 + math.sin(a) * d, s, 0, PI * 2)
        x.fill()
    t = wk.tex_from_canvas(c, 'exterior|moon', False, 'ws')
    return t


def _jsnum(v):
    from dalib.mathutils3 import js_str
    return js_str(v)


def skyDome(ctx, rand):
    game = ctx['game']
    M = game['mats']
    sky = wk.group('sky')
    # Dome (its ShaderMaterial is godot/scripts/world/exterior.gd SKY_SHADER: uTop PAL.skyTop, uHorizon PAL.horizon,
    # uGlow #6B3F6E, uGround #120E1E; BackSide, no depth write, no fog, renderOrder -10, never frustum-culled).
    dome = wk.Mesh(THREE.SphereGeometry(SKY_R, 32, 16), wk.Material('sky', PAL.skyTop, {'side': wk.BackSide, 'depthWrite': False, 'fog': False},
                                                                  extra={'horizon': PAL.horizon, 'glow': '#6B3F6E', 'ground': '#120E1E'}))
    dome.name = 'sky_dome'
    dome.renderOrder = -10
    dome.userData.frustumCulled = False
    sky.add(dome)

    n = 900
    pos = np.zeros((n, 3))
    size = np.zeros(n)
    phase = np.zeros(n)
    for i in range(n):
        y = 0.06 + rand() * 0.94
        a = rand() * PI * 2
        rr = math.sqrt(1 - y * y)
        pos[i] = [math.cos(a) * rr * (SKY_R - 10), y * (SKY_R - 10), math.sin(a) * rr * (SKY_R - 10)]
        size[i] = 1.2 + rand() ** 3 * 3.2
        phase[i] = rand()
    pos = np.asarray(np.asarray(pos, dtype=np.float32), dtype=np.float64)   # Float32Array
    # THREE.Points(aSize, aPhase) -> one quad per star (see the header); a 1 mm spread keeps the quads non-degenerate
    # for Blender / glTF (the shader re-centres nothing: 1 mm at 140 m is far below a pixel).
    corners = np.array([[0, 0], [1, 0], [1, 1], [0, 1]], dtype=np.float64)
    qp = np.repeat(pos, 4, axis=0)
    cdir = pos / np.linalg.norm(pos, axis=1)[:, None]
    t1 = np.cross(cdir, np.array([0, 1.0, 0]))
    t1 /= np.maximum(np.linalg.norm(t1, axis=1), 1e-9)[:, None]
    t2 = np.cross(cdir, t1)
    off = (np.tile(corners, (n, 1)) * 2 - 1) * 0.001
    qp += np.repeat(t1, 4, axis=0) * off[:, 0:1] + np.repeat(t2, 4, axis=0) * off[:, 1:2]
    nrm = -np.repeat(cdir, 4, axis=0)
    uv = np.tile(corners, (n, 1))
    uv1 = np.repeat(np.stack([size, phase], axis=1), 4, axis=0)
    idx = (np.arange(n)[:, None] * 4 + np.array([0, 1, 2, 0, 2, 3])[None, :]).reshape(-1)
    stars = wk.Mesh(wk.geometry(qp, nrm, uv, None, idx, uv1=uv1),
                    wk.Material('stars', '#FFF2D1', {'transparent': True, 'depthWrite': False, 'fog': False, 'blending': 'additive'}))
    stars.name = 'sky_stars'
    stars.renderOrder = -9
    stars.userData.frustumCulled = False
    sky.add(stars)

    d = Vector3(0.42, 0.52, -0.74).normalize()
    moon = wk.Mesh(THREE.PlaneGeometry(26, 26), wk.Material('moon', PAL.moon, {'map': moonTexture(), 'transparent': True, 'depthWrite': False,
                                                                             'fog': False, 'colorMul': 1.35}))
    moon.name = 'sky_moon'
    moon.position.copy(d).multiplyScalar(SKY_R - 20)
    sky.add(moon)
    moon.lookAt(0, 0, 0)
    moon.renderOrder = -8
    return sky
