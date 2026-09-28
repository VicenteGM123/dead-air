"""DEAD AIR — room-local geometry of Studio A, Studio B and the Transmitter Yard (SPEC §4/§5, ROOMS_CONTEXT).

Port of the mesh-building half of src/world/rooms/studio_a.js, studio_b.js and yard.js, line by line against the
three.js-like graph (dalib.scene), the prop kit (dalib.kit, same names as src/props/kit.js) and the exact three
geometry port (dalib.three_geo). Everything the rooms place, animate, switch or register (props, colliders, light
anchors, pools, screens, toys, power) is GDScript: godot/scripts/world/rooms/studio_a.gd / studio_b.gd / yard.gd,
which load these GLBs from godot/assets/runtime/rooms_studios_yard/ and take their children by name:

  studio_a.glb   root 'rooms_studio_a'. Local builders at the origin (placed by studio_a.gd with the JS pos / rotY /
                 colliders, their userData — colliders ... — is the child's "da"):
                   sa_tomb1 sa_tomb2 (tombstone) · sa_pumpkin_<seed> (pumpkin(r, seed), seeds 1..6) · sa_fog ·
                   sa_cue1 sa_cue2 (cueCard) · sa_leg1 sa_leg2 (curtainLeg) · sa_valance · sa_backdrop (banner) ·
                   sa_bat_<i> (bat(s) + its string, i = the JS loop index; skipped indices have none) ·
                   sa_banner_<region> (operators pledge thanks goal studio quiet poster1..3) · sa_sandbag ·
                   monitor_stand_mon_studio_a_stand (standMonitor's stand)
                 Loose meshes the JS added straight to the area root (world coordinates, added as they are):
                   sa_webs (the two cobwebs) · sa_litter (litter(A, spots, 13))
                 Runtime meshes studio_a.gd animates: sa_specks_floor (disc at the origin; the JS puts it at
                   [4, 0.025, -21] and spins it), sa_specks_wall (the wall band, world coordinates; its texture
                   offset scrolls), sa_beam (the gel beam cone: CylinderGeometry(0.9, 0.12, 1, 20, 1, true)
                   translated / rotated like the JS; studio_a.gd clones it per gel and gives it the beam shader).
  studio_b.glb   root 'rooms_studio_b':
                   sb_countdown · sb_tree_feet · sb_easel · sb_flat (the Hullabaloo Hills flat) · sb_toy_piano ·
                   sb_sunflower_1 sb_sunflower_2 (cutout) · sb_toy_chest · sb_banner_<region> (clap logo poster
                   peanut signB) · sb_drawings · sb_cue · sb_costume_rack · monitor_stand_mon_studio_b_stand ·
                   sb_launch (launch-pad ring at the origin; studio_b.gd puts it on the rocket)
                   loose (world coordinates): sb_cuts · sb_confetti · sb_spikes · sb_socks · sb_bunting · sb_fairy_wire
                   runtime: sb_fairy_0 sb_fairy_1 (bulb meshes, world coordinates; their colour breathes) ·
                   sb_balloons_<i> (clusters at the origin, i = spot index) · sb_mobile_<i> (mobile groups at the
                   origin, the rotating child is sb_mobile_<i>_spin) · sb_sil_owl / sock / dragon (golden silhouette
                   planes at the origin) · sb_beam (CylinderGeometry(0.75, 0.1, ...))
  yard.glb       root 'rooms_yard': yd_apron (DY landing slab + decal top) · yd_posters (wheat-pasted cards) ·
                 yd_hose (bib + coiled hose) · yd_trench (coax trench covers, coax, the crew cable) · yd_wires (the
                 utility wires between the poles + the service drop) — all world coordinates — and yd_hut_mast
                 (SkyCam's roof mast, hut-local coordinates: yard.gd adds it to the hut).

Materials the Godot side retunes (names in the spec opts): 'sa_beam' / 'sb_beam' (replaced by the additive beam
shader), 'sb_glowcut' / 'sb_silmat' (colours > 1 of the JS MeshBasicMaterials are re-applied in GDScript).
The yard's own registered props (yard_cone ... yard_sign) are blender/props/rooms_studios_yard.py.

Run: python3 blender/build_all.py --only runtime   (build(save_blend)), or standalone:
     cd /home/user/dead-air && python3 blender/runtime/rooms_studios_yard.py [--save-blend] [--only studio_a,yard]
"""
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
from dalib.mathutils3 import JSObj, js_round, js_str  # noqa: E402
from dalib.rng import mulberry32  # noqa: E402
from dalib.three_geo import mergeGeometries  # noqa: E402
from world.layout import ANCHORS, DOORS, AREAS  # noqa: E402

REPO = os.path.dirname(_BLENDER)
OUT_DIR = os.path.join(REPO, 'godot', 'assets', 'runtime', 'rooms_studios_yard')
BLEND_DIR = os.path.join(_BLENDER, 'out', 'runtime', 'rooms_studios_yard')
PI = math.pi
TAU = PI * 2
HP = PI / 2


def mulberry(a):
    """studio_a.js / studio_b.js mulberry(a): the same stream as core/rng.js mulberry32."""
    return mulberry32(a)


def _num(v):
    return js_str(v)


# ================================================================================================ shared kit
def yawTo(a, b):
    return math.atan2(-(b[0] - a[0]), -(b[2] - a[2]))


def v3(p):
    return p.clone() if isinstance(p, THREE.Vector3) else THREE.Vector3(p[0], p[1] if len(p) > 1 and p[1] is not None else 0, p[2])


_MATS = {}


def studioMats(game):
    """Cached kit materials (white + vertex colors: tinted geometry of every studio prop)."""
    m = _MATS.get(id(game))
    if m is not None:
        return m

    def basicV(k, o=None):
        p = {'color': THREE.Color(k, k, k), 'vertexColors': True}
        p.update(o or {})
        return THREE.MeshBasicMaterial(p)
    m = JSObj(
        lac=K.mat(game, 'lacquer', '#ffffff'),
        paint=K.mat(game, 'paint', '#ffffff'),
        plastic=K.mat(game, 'plastic', '#ffffff'),
        felt=K.mat(game, 'felt', '#ffffff'),
        chrome=K.mat(game, 'chrome', '#A8B0BA'),
        velvet=K.mat(game, 'fabric', '#ffffff', {'map': K.tex.weave('#B81E3A', {'pattern': 'cord', 'scale': 3})}),
        glow=basicV(1),          # vertex-colored HDR glow (candles, baked bulbs, fairy lights)
        glowDim=basicV(0.3),
        beam=beamMaterial('sa_beam'),
    )
    _MATS[id(game)] = m
    return m


def beamMaterial(name):
    """The JS soft additive light-cone ShaderMaterial (fresnel edge fade, fades along the cone). Exported as an
    additive unlit spec named `name`; the room script swaps in the beam shader (uColor / uI per beam)."""
    return K.material('basic', '#ffffff', {'blending': 'additive', 'transparent': True, 'depthWrite': False,
                                           'side': THREE.DoubleSide, 'fog': False, 'name': name},
                      type='ShaderMaterial', transparent=True, depthWrite=False, side=THREE.DoubleSide,
                      blending=THREE.AdditiveBlending, name=name)


def tg(geo, color):
    """tinted copy of a (possibly cached) geometry"""
    return K.tint(geo.clone(), color)


def quad(w, h, uvr=None, color='#ffffff'):
    """flat quad facing -z showing an atlas rect [u0,v0,u1,v1]"""
    g = THREE.PlaneGeometry(w, h)
    g.rotateY(PI)
    if uvr:
        K.uvRect(g, *uvr)
    return K.tint(g, color)


def makeAtlas(game, key, size, regions, draw):
    """Canvas atlas shared by a room: regions {name: [x, y, w, h]} (px, top-left origin)."""
    def d(ctx, w, h, rand):
        ctx.clearRect(0, 0, w, h)
        draw(ctx, lambda n: regions[n], rand)
    tex = K.tex.canvas(key, size, size, d, {'repeat': False, 'fonts': True})
    tex.anisotropy = 8

    def uv(n):
        x, y, w, h = regions[n]
        return [x / size, 1 - (y + h) / size, (x + w) / size, 1 - y / size]
    return JSObj(
        tex=tex, uv=uv,
        mat=K.mat(game, 'paint', '#ffffff', {'map': tex, 'rough': 0.7}),
        gloss=K.mat(game, 'lacquer', '#ffffff', {'map': tex}),
        glow=K.glow(game, '#ffffff', 1.35, {'map': tex}),
        cut=K.mat(game, 'paint', '#ffffff', {'map': tex, 'alphaTest': 0.5, 'side': THREE.DoubleSide}),
    )


# Canvas text helpers (Bungee / Titan One / Shrikhand are bundled)
FONT = JSObj(
    sign='"Bungee", Impact, "Arial Black", sans-serif',
    round='"Titan One", "Arial Rounded MT Bold", "Arial Black", sans-serif',
    groovy='"Shrikhand", "Cooper Black", Georgia, serif',
)


def rr(ctx, x, y, w, h, r):
    ctx.beginPath()
    ctx.roundRect(x, y, w, h, r)


def txt(ctx, s, x, y, o=None):
    o = o or {}
    font = o.get('font', FONT.sign)
    size = o.get('size', 40)
    fill = o.get('fill', '#fff')
    stroke = o.get('stroke')
    lw = o.get('lw', 0)
    align = o.get('align', 'center')
    maxW = o.get('maxW', 0)
    shadow = o.get('shadow')
    rot = o.get('rot', 0)
    ctx.save()
    ctx.translate(x, y)
    if rot:
        ctx.rotate(rot)
    px = size
    ctx.font = '%spx %s' % (_num(px), font)
    if maxW:
        while ctx.measureText(s).width > maxW and px > 6:
            px *= 0.94
            ctx.font = '%spx %s' % (_num(px), font)
    ctx.textAlign = align
    ctx.textBaseline = 'middle'
    ctx.lineJoin = 'round'
    if shadow:
        ctx.fillStyle = shadow
        ctx.fillText(s, px * 0.05, px * 0.08)
    if stroke:
        ctx.lineWidth = lw
        ctx.strokeStyle = stroke
        ctx.strokeText(s, 0, 0)
    ctx.fillStyle = fill
    ctx.fillText(s, 0, 0)
    ctx.restore()


def starPath(ctx, cx, cy, ro, ri, n=5, a0=-HP):
    ctx.beginPath()
    for i in range(n * 2):
        a = a0 + (i / (n * 2)) * TAU
        r = ri if i % 2 else ro
        if i:
            ctx.lineTo(cx + math.cos(a) * r, cy + math.sin(a) * r)
        else:
            ctx.moveTo(cx + math.cos(a) * r, cy + math.sin(a) * r)
    ctx.closePath()


def _drawTo(ctx, card, w, h):
    K.drawTo(ctx, card, w, h)


def standMonitorStand(game, anchorId):
    """standMonitor(): the rolling AV stand (the monitor itself is the bc_rack_monitor prop, placed by the room)."""
    a = ANCHORS[anchorId]
    M = studioMats(game)
    size = 19.6
    s = size / 14
    topY = a['pos'][1] - (0.37 * s) * 0.57              # monitor base so the screen center is at a.pos.y
    stand = K.prop('sa_monitor_stand')
    ink, steel = '#2A2230', '#8A8F9A'
    for r in [0.35, -0.35]:
        stand.add(K.m(tg(K.box(0.72, 0.06, 0.08, 0.02), ink), M.lac, {'pos': [0, 0.1, 0], 'rot': [0, r + 0.4, 0]}))
    for i in range(4):
        ang = 0.4 + (i / 4) * TAU + 0.35 * (-1 if i % 2 else 1)
        stand.add(K.m(tg(K.cyl(0.035, 0.035, 0.05, {'seg': 10}), '#1E1A22').rotateZ(HP), M.lac, {'pos': [math.cos(ang) * 0.34, 0.035, math.sin(ang) * 0.34]}))
    stand.add(K.m(tg(K.cyl(0.03, 0.035, topY - 0.14, {'seg': 12}), steel), M.chrome, {'pos': [0, 0.13, 0]}))
    stand.add(K.m(tg(K.box(0.62, 0.05, 0.5, 0.02), '#D9A520'), M.lac, {'pos': [0, topY - 0.025, 0.02]}))
    stand.add(K.m(tg(K.box(0.14, 0.18, 0.14, 0.03), ink), M.lac, {'pos': [0, topY - 0.12, 0]}))
    # cable dropping to the floor
    stand.add(K.m(tg(K.tube([[0.08, topY - 0.05, 0.2], [0.1, topY - 0.4, 0.26], [0.06, 0.5, 0.12], [0.1, 0.05, 0.3], [0.4, 0.012, 0.55]], 0.012, {'seg': 16, 'radial': 4}), ink), M.lac))
    K.finish(game, stand, {'ao': {'res': 40}})
    stand.userData.topY = topY
    stand.name = 'monitor_stand_' + anchorId
    return stand


def stringTo(M, x, y0, z, y1, color='#2A2230', r=0.005):
    """Hanging string from a point up to the grid"""
    return K.m(tg(K.cyl(r, r, max(0.05, y1 - y0), {'seg': 5}), color), M.lac, {'pos': [x, y0, z]})


def _named(g, name):
    g.name = name
    return g


def _loose(name, *objs):
    g = THREE.Group()
    g.name = name
    for o in objs:
        g.add(o)
    return g


# =============================================================================================== Studio A deco
def bat(game, s=1):
    """Cute cardboard bat (hangs on a string): extruded silhouette + big googly eyes. Local: body center at origin."""
    M = studioMats(game)
    g = K.prop('sa_bat')
    half = [[0, 0.1], [0.035, 0.15], [0.06, 0.07], [0.17, 0.12], [0.3, 0.21], [0.34, 0.1], [0.28, 0.075], [0.25, 0.0],
            [0.19, 0.045], [0.15, -0.035], [0.09, -0.01], [0.04, -0.08], [0, -0.09]]
    pts = [[x * s, y * s] for x, y in (half + [[-x, y] for x, y in list(reversed(half[1:-1]))])]
    g.add(K.m(tg(K.extrude(pts, 0.018 * s, {'bevel': 0.006 * s, 'bevelSeg': 1}), '#3A2440'), M.lac, {'pos': [0, 0, -0.009 * s]}))
    for x in [-0.028, 0.028]:
        g.add(K.m(tg(THREE.SphereGeometry(0.024 * s, 10, 8), '#FFF8E8'), M.lac, {'pos': [x * s, 0.035 * s, -0.018 * s]}))
        g.add(K.m(tg(THREE.SphereGeometry(0.012 * s, 8, 6), '#1E1530'), M.lac, {'pos': [(x + 0.004) * s, 0.03 * s, -0.035 * s]}))
    for x in [-0.012, 0.012]:
        g.add(K.m(tg(THREE.ConeGeometry(0.006 * s, 0.018 * s, 5).rotateX(PI), '#FFFFFF'), M.lac, {'pos': [x * s, -0.012 * s, -0.02 * s]}))
    g.userData.colliders = []
    return K.finish(game, g, {'ao': False})


def pumpkin(game, r=0.24, seed=1):
    """Jack-o'-lantern with a glowing carved face (candle glow, always on)."""
    M = studioMats(game)
    g = K.prop('sa_pumpkin')
    body = THREE.SphereGeometry(r, 24, 14)
    p = body.attributes.position
    col = np.zeros((p.count, 3))
    cA, cB, c = THREE.Color('#F08A24'), THREE.Color('#B8501A'), THREE.Color()
    for i in range(p.count):
        x, y, z = p.getX(i), p.getY(i), p.getZ(i)
        th = math.atan2(z, x)
        f = abs(math.cos(th * 4))
        k = 0.92 + 0.08 * math.sqrt(f)
        flat = 0.9 if y < -r * 0.6 else 1
        p.setXYZ(i, x * k, y * 0.78 * flat, z * k)
        c.copy(cB).lerp(cA, math.pow(f, 0.35))
        col[i] = (c.r, c.g, c.b)
    body.setAttribute('color', THREE.BufferAttribute(col, 3))
    body.computeVertexNormals()
    g.add(K.m(body, M.lac, {'pos': [0, r * 0.78, 0]}))
    g.add(K.m(tg(K.cyl(r * 0.1, r * 0.13, r * 0.35, {'seg': 7}), '#5A6A2A'), M.lac, {'pos': [0, r * 1.45, 0], 'rot': [0.2, 0, 0.25 * (1 if seed % 2 else -1)]}))
    face = THREE.Group()
    eye = K.extrude([[-0.07, -0.04], [0.07, -0.04], [0, 0.07]], 0.01, {'bevel': 0.003})
    glowC = '#FFB347'
    for s in [-1, 1]:
        face.add(K.m(tg(eye, glowC), M.glow, {'pos': [s * r * 0.36, r * 0.95, -r * 0.93], 'scale': r / 0.24}))
    mouth = [[-0.13, 0.02], [-0.08, -0.02], [-0.05, 0.01], [0, -0.035], [0.05, 0.01], [0.08, -0.02], [0.13, 0.02], [0.06, -0.06], [0, -0.075], [-0.06, -0.06]]
    face.add(K.m(tg(K.extrude(mouth, 0.01, {'bevel': 0.003}), glowC), M.glow, {'pos': [0, r * 0.62, -r * 0.9], 'scale': r / 0.24}))
    for o in face.children:
        o.userData.noAO = True
        o.material = M.glow
        o.geometry = K.tint(o.geometry.clone(), THREE.Color(1.9, 1.9, 1.9))
    for o in list(face.children):
        g.add(o)
    g.userData.colliders = []
    return K.finish(game, g, {'ao': {'res': 32}})


def tombstone(game, A, region, w=0.62, h=0.86):
    """Cartoon cardboard tombstone with an atlas epitaph + a grass tuft"""
    M = studioMats(game)
    g = K.prop('sa_tombstone')
    s = THREE.Shape()
    s.moveTo(-w / 2, 0)
    s.lineTo(w / 2, 0)
    s.lineTo(w / 2, h - w / 2)
    s.absarc(0, h - w / 2, w / 2, 0, PI, False)
    s.closePath()
    g.add(K.m(tg(K.extrude(s, 0.12, {'bevel': 0.03, 'bevelSeg': 2, 'curveSeg': 14}), '#8C829E'), M.lac, {'pos': [0, 0.02, -0.06]}))
    g.add(K.m(quad(w * 0.8, w * 0.8, A.uv(region)), A.mat, {'pos': [0, h * 0.52, -0.095]}))
    for x, sc in [[-0.18, 1], [0.05, 0.8], [0.22, 0.9]]:
        g.add(K.m(tg(THREE.SphereGeometry(0.1 * sc, 10, 6, 0, TAU, 0, HP), '#58A83E').scale(1.3, 0.6, 1), M.lac, {'pos': [x, 0, -0.12]}))
    g.userData.colliders = [{'min': [-w / 2, 0, -0.14], 'max': [w / 2, h, 0.08]}]
    return K.finish(game, g, {'ao': {'res': 36}})


def curtainLeg(game, w, h, seed=1):
    """Pleated velvet curtain leg (w x h, hangs from y = h), gold fringe hem; faces -z."""
    M = studioMats(game)
    g = K.prop('sa_curtain_leg')
    pl = THREE.PlaneGeometry(w, h, 26, 6)
    p = pl.attributes.position
    for i in range(p.count):
        x, y = p.getX(i), p.getY(i)
        gather = 1 - 0.1 * ((y + h / 2) / h)
        p.setX(i, x * gather)
        p.setZ(i, math.sin((x / w) * PI * 9 + seed) * 0.06 + (0.03 if y < -h / 2 + 0.3 else 0))
    pl.rotateY(PI)
    pl.computeVertexNormals()
    K.uvScale(pl, w * 0.9, h * 0.9)
    g.add(K.m(K.tint(pl, '#ffffff'), M.velvet, {'pos': [0, h / 2, 0]}))
    g.add(K.m(tg(K.tube([[-w * 0.47, 0.06, -0.02], [0, 0.07, -0.05], [w * 0.47, 0.06, -0.02]], 0.03, {'seg': 12, 'radial': 5}), PAL.harvestGold), M.lac))
    g.add(K.m(tg(K.box(w + 0.1, 0.16, 0.16, 0.03), '#2A1D2A'), M.lac, {'pos': [0, h, 0.02]}))
    g.userData.colliders = []
    return K.finish(game, g, {'ao': False})


def valance(game, w, depthH=0.8):
    """Scalloped velvet valance with gold fringe (w wide, hangs down from y = 0), faces -z."""
    M = studioMats(game)
    g = K.prop('sa_valance')
    n = int(js_round(w / 1.4))
    pl = THREE.PlaneGeometry(w, depthH, n * 6, 3)
    p = pl.attributes.position
    hem = []
    for i in range(p.count):
        x, y = p.getX(i), p.getY(i)
        ph = math.fmod((x / w + 0.5) * n, 1)
        sag = math.sin(ph * PI) * 0.28
        t = (depthH / 2 - y) / depthH
        p.setY(i, y - sag * t)
        p.setZ(i, -math.sin(ph * PI) * 0.12 * t + math.sin((x / w) * PI * n * 4) * 0.02)
        if y < -depthH / 2 + 1e-4:
            hem.append([x, y - sag - depthH / 2, p.getZ(i)])
    pl.rotateY(PI)
    pl.computeVertexNormals()
    K.uvScale(pl, w * 0.9, 1)
    g.add(K.m(K.tint(pl, '#ffffff'), M.velvet, {'pos': [0, -depthH / 2, 0]}))
    hem.sort(key=lambda a: a[0])
    g.add(K.m(tg(K.tube([[-x, y + depthH / 2 - depthH / 2, -z - 0.01] for x, y, z in hem], 0.028, {'seg': n * 10, 'radial': 5}), PAL.harvestGold), M.lac, {'pos': [0, 0, 0]}))
    g.add(K.m(tg(K.box(w + 0.1, 0.14, 0.14, 0.03), '#2A1D2A'), M.lac, {'pos': [0, 0.02, 0.05]}))
    g.userData.colliders = []
    return K.finish(game, g, {'ao': False})


def bannerA(game, A, region, w, h, hang=0, color='#2A1D2A'):
    """Hanging or wall banner: board with an atlas face (both sides printed when hanging); strings to `hangTo` height."""
    M = studioMats(game)
    g = K.prop('sa_banner')
    g.add(K.m(tg(K.box(w + 0.08, h + 0.08, 0.04, 0.02), color), M.lac, {'pos': [0, 0, 0]}))
    g.add(K.m(quad(w, h, A.uv(region)), A.mat, {'pos': [0, 0, -0.022]}))
    if hang:
        back = quad(w, h, A.uv(region))
        back.rotateY(PI)
        g.add(K.m(back, A.mat, {'pos': [0, 0, 0.022]}))
        for s in [-1, 1]:
            g.add(stringTo(M, s * (w / 2 - 0.2), h / 2 + 0.04, 0, h / 2 + hang))
    g.userData.colliders = []
    return K.finish(game, g, {'ao': False})


def fogMachine(game, A):
    """Fog machine (FOG-O-MATIC) with a hose and a cable"""
    M = studioMats(game)
    g = K.prop('sa_fog')
    g.add(K.m(tg(K.box(0.56, 0.26, 0.32, 0.04), '#3A3348'), M.lac, {'pos': [0, 0.16, 0]}))
    g.add(K.m(tg(K.box(0.6, 0.04, 0.36, 0.015), '#2A2230'), M.lac, {'pos': [0, 0.02, 0]}))
    g.add(K.m(quad(0.34, 0.085, A.uv('fog')), A.mat, {'pos': [0, 0.18, -0.162]}))
    g.add(K.m(tg(K.cyl(0.05, 0.06, 0.14, {'seg': 12}).rotateX(-HP), '#A8B0BA'), M.chrome, {'pos': [0.16, 0.2, -0.16]}))
    g.add(K.m(tg(K.box(0.2, 0.06, 0.12, 0.02), PAL.channelRed), M.lac, {'pos': [-0.12, 0.31, 0.04]}))
    g.add(K.m(tg(K.tube([[0.28, 0.1, 0.12], [0.5, 0.02, 0.3], [0.9, 0.012, 0.35], [1.3, 0.012, 0.6]], 0.012, {'seg': 16, 'radial': 4}), '#2A2230'), M.lac))
    g.userData.colliders = [{'min': [-0.3, 0, -0.2], 'max': [0.3, 0.36, 0.2]}]
    return K.finish(game, g, {'ao': {'res': 32}})


def cueCard(game, A, region):
    """Cue card (hand-lettered) lying on the floor / leaning"""
    M = studioMats(game)
    g = K.prop('sa_cue')
    g.add(K.m(tg(K.box(0.62, 0.46, 0.02, 0.008), '#F4F1E8'), M.lac, {'pos': [0, 0, 0]}))
    g.add(K.m(quad(0.58, 0.42, A.uv(region)), A.mat, {'pos': [0, 0, -0.012]}))
    g.userData.colliders = []
    return K.finish(game, g, {'ao': False})


def litter(game, A, spots, seed=1):
    """Floor litter: pledge slips (atlas), paper cups, popcorn."""
    M = studioMats(game)
    rnd = mulberry(seed)
    g = K.prop('sa_litter')
    slip = quad(0.14, 0.18, A.uv('slip')).rotateX(-HP)
    cup = K.lathe([[0, 0], [0.032, 0], [0.042, 0.1], [0.044, 0.105], [0, 0.105]], {'seg': 12})
    corn = THREE.IcosahedronGeometry(0.022, 0)
    for s in spots:
        cx, cy, cz = s['at']
        r0 = s.get('r0', 0)
        rs = s.get('r', 1)
        for i in range(s.get('slips', 0)):
            a = rnd() * TAU
            r = r0 + rnd() * rs
            g.add(K.m(slip, A.mat, {'pos': [cx + math.cos(a) * r, cy + 0.006 + i * 0.0004, cz + math.sin(a) * r], 'rot': [0, rnd() * TAU, 0]}))
        for i in range(s.get('cups', 0)):
            a = rnd() * TAU
            r = r0 + rnd() * rs
            tip = rnd() < 0.5
            m = K.m(tg(cup, '#F4F1E8' if i % 2 else '#FFE9C8'), M.plastic, {'pos': [cx + math.cos(a) * r, cy + (0.044 if tip else 0), cz + math.sin(a) * r]})
            if tip:
                m.rotation.set(HP, rnd() * TAU, 0, 'YXZ')
            g.add(m)
            g.add(K.m(tg(K.cyl(0.045, 0.045, 0.012, {'seg': 12}), PAL.channelRed), M.plastic, {'pos': m.position.toArray(), 'rot': [m.rotation.x, m.rotation.y, 0], 'scale': 0.001 if tip else 1}))
        for i in range(s.get('corn', 0)):
            a = rnd() * TAU
            r = r0 + math.sqrt(rnd()) * rs
            g.add(K.m(tg(corn, '#F4D06A' if rnd() < 0.25 else '#FFF6DC'), M.plastic, {'pos': [cx + math.cos(a) * r, cy + 0.015, cz + math.sin(a) * r], 'rot': [rnd() * 3, rnd() * 3, 0], 'scale': 0.8 + rnd() * 0.6}))
    g.userData.colliders = []
    return K.finish(game, g, {'ao': False})


def sandbag(game):
    """Sandbag (stand weights)"""
    M = studioMats(game)
    g = K.prop('sa_sandbag')
    g.add(K.m(tg(K.cushion(0.36, 0.14, 0.24, {'puff': 0.035}), '#7A6A48'), M.felt, {'pos': [0, 0.07, 0]}))
    g.add(K.m(tg(K.tube([[-0.12, 0.13, 0], [0, 0.2, 0], [0.12, 0.13, 0]], 0.012, {'seg': 8, 'radial': 4}), '#5A4A30'), M.felt))
    g.userData.colliders = []
    return K.finish(game, g, {'ao': {'res': 24}})


# ------------------------------------------------------------------------------------------ Studio A atlas
REG_A = {
    'backdrop': [0, 0, 1024, 300],
    'pledge': [0, 300, 1024, 120],
    'thanks': [0, 420, 1024, 120],
    'operators': [0, 540, 1024, 120],
    'poster1': [0, 660, 180, 240], 'poster2': [180, 660, 180, 240], 'poster3': [360, 660, 180, 240],
    'tomb1': [540, 660, 128, 128], 'tomb2': [668, 660, 128, 128],
    'studio': [796, 660, 228, 110], 'quiet': [796, 770, 228, 70],
    'cue1': [540, 788, 128, 96], 'cue2': [668, 788, 128, 96],
    'slip': [796, 840, 56, 72], 'fog': [852, 840, 172, 44], 'web': [852, 884, 120, 120],
    'goal': [0, 900, 540, 124],
}


def drawStudioA(ctx, R, rand):
    C = JSObj(plum='#6B3A6E', deep='#2A1740', gold='#FFC23A', orange='#E3662B', cream='#F6E7C8', red='#E23B3B', blue='#2F5BD3')
    # ---- backdrop: spooky-cute night over the WZTV tower, giant SPOOKTACULAR title, the Baron's portrait
    x, y, w, h = R('backdrop')
    ctx.save(); ctx.translate(x, y)
    g = ctx.createLinearGradient(0, 0, 0, h)
    g.addColorStop(0, '#1B1238'); g.addColorStop(0.55, '#4A2466'); g.addColorStop(1, '#A8406A')
    ctx.fillStyle = g; ctx.fillRect(0, 0, w, h)
    for i in range(70):
        ctx.fillStyle = 'rgba(255,244,214,%s)' % _num(0.4 + rand() * 0.6)
        starPath(ctx, rand() * w, rand() * h * 0.55, 2 + rand() * 3, 1, 4)
        ctx.fill()
    # moon with a 13
    ctx.fillStyle = '#FFF4D6'; ctx.beginPath(); ctx.arc(120, 92, 62, 0, TAU); ctx.fill()
    ctx.fillStyle = 'rgba(200,180,140,0.35)'
    for cx, cy, r in [[98, 70, 12], [140, 118, 9], [150, 76, 6]]:
        ctx.beginPath(); ctx.arc(cx, cy, r, 0, TAU); ctx.fill()
    txt(ctx, '13', 120, 96, {'font': FONT.round, 'size': 54, 'fill': '#E3662B', 'stroke': '#6B3A6E', 'lw': 5})
    # hills + the tower
    ctx.fillStyle = '#2A1740'
    ctx.beginPath(); ctx.moveTo(0, h); ctx.lineTo(0, 230); ctx.quadraticCurveTo(160, 190, 330, 236); ctx.quadraticCurveTo(520, 270, 700, 226); ctx.quadraticCurveTo(880, 196, w, 240); ctx.lineTo(w, h); ctx.fill()
    ctx.strokeStyle = '#E23B3B'; ctx.lineWidth = 3
    tx, ty = 860, 215
    ctx.beginPath(); ctx.moveTo(tx - 26, ty); ctx.lineTo(tx, ty - 150); ctx.lineTo(tx + 26, ty); ctx.stroke()
    for i in range(7):
        yy = ty - i * 21
        hw = 26 * (1 - i / 7.2)
        ctx.beginPath(); ctx.moveTo(tx - hw, yy); ctx.lineTo(tx + hw * 0.8, yy - 21); ctx.stroke()
    ctx.fillStyle = '#FF3B30'; ctx.beginPath(); ctx.arc(tx, ty - 152, 7, 0, TAU); ctx.fill()
    ctx.fillStyle = 'rgba(255,59,48,0.25)'; ctx.beginPath(); ctx.arc(tx, ty - 152, 18, 0, TAU); ctx.fill()
    # bats
    ctx.fillStyle = '#1B1238'
    for bx, by, bs in [[260, 60, 1], [320, 40, 0.7], [700, 50, 0.9], [760, 90, 0.6], [560, 30, 0.6]]:
        ctx.beginPath(); ctx.moveTo(bx, by)
        ctx.quadraticCurveTo(bx - 18 * bs, by - 16 * bs, bx - 34 * bs, by - 4 * bs); ctx.quadraticCurveTo(bx - 22 * bs, by, bx - 18 * bs, by + 6 * bs)
        ctx.quadraticCurveTo(bx - 8 * bs, by + 2 * bs, bx, by + 8 * bs)
        ctx.quadraticCurveTo(bx + 8 * bs, by + 2 * bs, bx + 18 * bs, by + 6 * bs); ctx.quadraticCurveTo(bx + 22 * bs, by, bx + 34 * bs, by - 4 * bs)
        ctx.quadraticCurveTo(bx + 18 * bs, by - 16 * bs, bx, by); ctx.fill()
    # title
    txt(ctx, '13-HOUR', 512, 50, {'font': FONT.sign, 'size': 40, 'fill': C.cream, 'stroke': C.deep, 'lw': 8, 'track': 2})
    g = ctx.createLinearGradient(0, 80, 0, 190); g.addColorStop(0, '#FFF2B0'); g.addColorStop(0.5, '#FFC23A'); g.addColorStop(1, '#FF7A2A')
    txt(ctx, 'Spooktacular', 512, 132, {'font': FONT.groovy, 'size': 118, 'fill': g, 'stroke': '#2A1030', 'lw': 16, 'maxW': 700, 'shadow': 'rgba(0,0,0,0.45)'})
    txt(ctx, 'TELETHON', 512, 212, {'font': FONT.sign, 'size': 50, 'fill': '#F4F1E8', 'stroke': '#2A1030', 'lw': 9})
    txt(ctx, 'STAY UP WITH THE BARON • CALL 555-1313', 512, 268, {'font': FONT.round, 'size': 24, 'fill': C.gold, 'stroke': C.deep, 'lw': 5, 'maxW': 640})
    # host portrait
    ctx.save(); ctx.translate(900, 40)
    rr(ctx, -8, -8, 116, 150, 14); ctx.fillStyle = C.gold; ctx.fill()
    try:
        _drawTo(ctx, 'portrait_baron', 100, 134)
    except Exception:
        pass  # card missing: keep the frame
    ctx.restore()
    txt(ctx, 'YOUR HOST', 950, 196, {'font': FONT.sign, 'size': 18, 'fill': C.cream, 'stroke': C.deep, 'lw': 4})
    ctx.restore()

    # ---- long banners
    def band(name, bg, fg, stroke, main, sub, deco):
        x, y, w, h = R(name)
        ctx.save(); ctx.translate(x, y)
        rr(ctx, 2, 2, w - 4, h - 4, 18); ctx.fillStyle = bg; ctx.fill()
        ctx.lineWidth = 8; ctx.strokeStyle = stroke; rr(ctx, 10, 10, w - 20, h - 20, 12); ctx.stroke()
        for i in range(2):
            ctx.fillStyle = deco
            starPath(ctx, w - 58 if i else 58, h / 2, 30, 13)
            ctx.fill()
        txt(ctx, main, w / 2, h / 2 - (12 if sub else 0), {'font': FONT.sign, 'size': 58, 'fill': fg, 'stroke': stroke, 'lw': 8, 'maxW': w - 180})
        if sub:
            txt(ctx, sub, w / 2, h / 2 + 36, {'font': FONT.round, 'size': 22, 'fill': fg, 'maxW': w - 200})
        ctx.restore()
    band('pledge', C.cream, C.red, C.blue, 'PLEDGE NOW!  ☎ 555-1313', 'KEEP CHANNEL 13 ON THE AIR ALL NIGHT', C.gold)
    band('thanks', C.orange, C.cream, '#5A2A22', 'THANK YOU FOR PLEDGING!', None, C.gold)
    band('operators', C.blue, '#FFF4DC', '#1B2F7A', 'OPERATORS ARE STANDING BY', 'CALL NOW • 555-1313', C.red)
    # ---- posters (cards.js art)
    for n, cid in [['poster1', 'poster_spooktacular'], ['poster2', 'sponsor_poster_double_vision'], ['poster3', 'poster_boogie_down']]:
        x, y, w, h = R(n)
        ctx.save(); ctx.translate(x, y)
        try:
            _drawTo(ctx, cid, w, h)
        except Exception:
            ctx.fillStyle = C.plum; ctx.fillRect(0, 0, w, h)
        ctx.restore()
    # ---- tomb epitaphs
    for n, a, b in [['tomb1', 'R.I.P.', 'DEAD AIR'], ['tomb2', 'R.I.P.', 'RERUNS']]:
        x, y, w, h = R(n)
        ctx.fillStyle = '#9A90AC'; ctx.fillRect(x, y, w, h)
        for i in range(40):
            ctx.fillStyle = 'rgba(%s,0.08)' % ('255,255,255' if rand() < 0.5 else '40,30,60')
            ctx.fillRect(x + rand() * w, y + rand() * h, 3 + rand() * 6, 2)
        txt(ctx, a, x + w / 2, y + 40, {'font': FONT.sign, 'size': 30, 'fill': '#4A3A5E'})
        txt(ctx, b, x + w / 2, y + 80, {'font': FONT.round, 'size': 18, 'fill': '#4A3A5E', 'maxW': w - 16})
        txt(ctx, '1977', x + w / 2, y + 106, {'font': FONT.round, 'size': 14, 'fill': '#5A4A6E'})
    # ---- signs
    x, y, w, h = R('studio')
    ctx.fillStyle = '#E8A92E'; ctx.fillRect(x, y, w, h)
    ctx.fillStyle = '#2A1D2A'
    for i in range(12):
        ctx.beginPath(); ctx.moveTo(x + i * 22, y + h); ctx.lineTo(x + i * 22 + 11, y + h); ctx.lineTo(x + i * 22 + 25, y + h - 14); ctx.lineTo(x + i * 22 + 14, y + h - 14); ctx.fill()
    txt(ctx, 'STUDIO A', x + w / 2, y + 46, {'font': FONT.sign, 'size': 52, 'fill': '#2A1D2A', 'maxW': w - 20})
    x, y, w, h = R('quiet')
    rr(ctx, x + 2, y + 2, w - 4, h - 4, 12); ctx.fillStyle = '#E23B3B'; ctx.fill()
    txt(ctx, 'QUIET ON THE SET', x + w / 2, y + h / 2, {'font': FONT.sign, 'size': 26, 'fill': '#FFF4DC', 'maxW': w - 20})
    for n, s, col in [['cue1', 'APPLAUSE!', '#E23B3B'], ['cue2', 'SCREAM!', '#6B3A6E']]:
        x, y, w, h = R(n)
        ctx.fillStyle = '#FFFBEF'; ctx.fillRect(x, y, w, h)
        txt(ctx, s, x + w / 2, y + h / 2, {'font': FONT.round, 'size': 30, 'fill': col, 'maxW': w - 12, 'rot': -0.06})
    x, y, w, h = R('slip')
    ctx.fillStyle = '#FFFBEF'; ctx.fillRect(x, y, w, h)
    ctx.fillStyle = '#E23B3B'; ctx.fillRect(x, y, w, 14)
    ctx.fillStyle = 'rgba(60,90,200,0.4)'
    yy = y + 26
    while yy < y + h - 4:
        ctx.fillRect(x + 6, yy, w - 12, 2)
        yy += 10
    txt(ctx, '$13', x + 22, y + 40, {'font': FONT.round, 'size': 16, 'fill': '#2A2A8A', 'rot': -0.2})
    x, y, w, h = R('fog')
    ctx.fillStyle = '#2A2230'; ctx.fillRect(x, y, w, h)
    txt(ctx, 'FOG-O-MATIC', x + w / 2, y + h / 2, {'font': FONT.sign, 'size': 22, 'fill': '#9FE8FF', 'maxW': w - 10})
    x, y, w, h = R('web')
    ctx.save(); ctx.translate(x, y)
    ctx.strokeStyle = 'rgba(240,236,255,0.95)'; ctx.lineWidth = 2.2
    for i in range(7):
        a = (i / 6) * HP
        ctx.beginPath(); ctx.moveTo(0, 0); ctx.lineTo(math.cos(a) * w, math.sin(a) * h); ctx.stroke()
    for k in range(1, 6):
        r = k * (w / 5.4)
        ctx.beginPath()
        for i in range(7):
            a = (i / 6) * HP
            px, py = math.cos(a) * r, math.sin(a) * r
            if i:
                ctx.quadraticCurveTo(math.cos(a - HP / 12) * r * 0.86, math.sin(a - HP / 12) * r * 0.86, px, py)
            else:
                ctx.moveTo(px, py)
        ctx.stroke()
    ctx.restore()
    x, y, w, h = R('goal')
    rr(ctx, x + 2, y + 2, w - 4, h - 4, 20); ctx.fillStyle = '#1B2F7A'; ctx.fill()
    ctx.lineWidth = 6; ctx.strokeStyle = C.gold; rr(ctx, x + 10, y + 10, w - 20, h - 20, 14); ctx.stroke()
    txt(ctx, 'TONIGHT\'S GOAL  $13,000', x + w / 2, y + 46, {'font': FONT.sign, 'size': 38, 'fill': C.gold, 'maxW': w - 40})
    txt(ctx, 'HELP KEEP WZTV 13 ON THE AIR!', x + w / 2, y + 90, {'font': FONT.round, 'size': 22, 'fill': C.cream, 'maxW': w - 40})


def discoSpeckTexture():
    """props/sets.js discoSpeckTexture() (the sets port's, when importable: same canvas key)."""
    try:
        from props.sets import discoSpeckTexture as dst
        return dst()
    except Exception:
        pass

    def draw(ctx, w, h, rand):
        ctx.fillStyle = '#000'
        ctx.fillRect(0, 0, w, h)
        for i in range(160):
            x, y, r = rand() * w, rand() * h, 1.5 + rand() * 3
            gr = ctx.createRadialGradient(x, y, 0, x, y, r * 2)
            gr.addColorStop(0, 'rgba(255,255,255,1)'); gr.addColorStop(0.5, 'rgba(255,255,255,0.6)'); gr.addColorStop(1, 'rgba(255,255,255,0)')
            ctx.fillStyle = gr
            ctx.fillRect(x - r * 2, y - r * 2, r * 4, r * 4)
    return K.tex.canvas('sets.disco_specks', 256, 256, draw, {'repeat': False})


def buildStudioA(game):
    """The local geometry of studio_a.js build() (see the module docstring for the node names)."""
    root = THREE.Group()
    root.name = 'rooms_studio_a'
    M = studioMats(game)
    A = makeAtlas(game, 'sa_atlas_v1', 1024, REG_A, drawStudioA)
    GRID_Y = 6.5
    area = [a for a in AREAS if a['id'] == 'studio_a'][0]

    # spooky telethon stage dressing: tombstones, jack-o'-lanterns, fog machine, cue cards, curtains, backdrop
    root.add(_named(tombstone(game, A, 'tomb1'), 'sa_tomb1'))
    root.add(_named(tombstone(game, A, 'tomb2', 0.52, 0.74), 'sa_tomb2'))
    for x, y, z, r, s in [[-2.55, 0.6, -26.45, 0.26, 1], [-1.95, 0.6, -26.3, 0.18, 2], [7.35, 0.6, -29.2, 0.2, 3],
                          [-6.2, 0, -25.6, 0.22, 4], [-5.7, 0, -25.4, 0.16, 5], [11.6, 0, -24.9, 0.2, 6]]:
        root.add(_named(pumpkin(game, r, s), 'sa_pumpkin_%d' % s))
    root.add(_named(fogMachine(game, A), 'sa_fog'))
    root.add(_named(cueCard(game, A, 'cue1'), 'sa_cue1'))
    root.add(_named(cueCard(game, A, 'cue2'), 'sa_cue2'))
    root.add(_named(curtainLeg(game, 1.5, 5.9, 1), 'sa_leg1'))
    root.add(_named(curtainLeg(game, 1.5, 5.9, 2), 'sa_leg2'))
    root.add(_named(valance(game, 14.2), 'sa_valance'))
    root.add(_named(bannerA(game, A, 'backdrop', 11.2, 3.28, color='#1B1238'), 'sa_backdrop'))
    # cobwebs in the stage back corners (alpha cut-out)
    webs = []
    for x, s in [[-2.9, 1], [10.9, -1]]:
        w = K.m(quad(1.1, 1.1, A.uv('web')), A.cut, {'pos': [x + s * 0.02, 1.25, -29.83]})
        w.scale.x = s
        w.rotation.z = 0
        webs.append(w)
    root.add(_loose('sa_webs', *webs))

    # telethon goal sign on the carousel's east side? (kept clear: the ring). Pledge litter around the desk.
    toteA = ANCHORS['ee_tote_board']
    root.add(_named(litter(game, A, [
        {'at': [toteA['pos'][0], 0, toteA['pos'][2]], 'slips': 16, 'r0': 2.2, 'r': 1.6, 'cups': 3},
        {'at': [-2.5, 0, -15.1], 'corn': 60, 'r': 1.4, 'cups': 2, 'slips': 3},
        {'at': [10.5, 0, -15.0], 'corn': 45, 'r': 1.2, 'cups': 2, 'slips': 2},
        {'at': [4, 0, -25.2], 'slips': 4, 'r': 3},
    ], 13), 'sa_litter'))

    # disco specks: a rotating floor disc + a sliding band on the walls (additive), after power
    speckTex = discoSpeckTexture()
    floorTex = speckTex.clone()
    floorTex.wrapS = floorTex.wrapT = THREE.RepeatWrapping
    floorTex.repeat.set(3, 3)
    wallTex = speckTex.clone()
    wallTex.wrapS = wallTex.wrapT = THREE.RepeatWrapping
    wallTex.repeat.set(10, 1.4)

    def speckMat(tex, k, name):
        return THREE.MeshBasicMaterial({'map': tex, 'color': THREE.Color(k, k * 0.92, k * 1.05),
                                        'blending': THREE.AdditiveBlending, 'transparent': True, 'depthWrite': False,
                                        'fog': False, 'name': name})
    specksFloor = THREE.Mesh(THREE.CircleGeometry(8.5, 48).rotateX(-HP), speckMat(floorTex, 0.55, 'sa_specks_floor'))
    specksFloor.name = 'sa_specks_floor'
    wallGeo = []
    x0, z0, x1, z1 = area['rect']
    # The band skips door openings (D4, D6); above the door head it continues.
    BAND_Y0, BAND_Y1 = 1.3, 5.5
    doorsHere = [d for d in DOORS if (area.get('id') or 'studio_a') in d['areas']]

    def piece(ax, az, bx, bz, len_, s0, s1, y0, y1):
        w = s1 - s0
        hgt = y1 - y0
        if w < 0.05 or hgt < 0.05:
            return
        q = THREE.PlaneGeometry(w, hgt)
        q.rotateY(math.atan2(-(bz - az), bx - ax))
        t = (s0 + s1) / 2 / len_
        q.translate(ax + (bx - ax) * t, (y0 + y1) / 2, az + (bz - az) * t)
        uv = q.attributes.uv
        for i in range(uv.count):
            uv.setX(i, (s0 + uv.getX(i) * w) / 22)
            uv.setY(i, (y0 - BAND_Y0 + uv.getY(i) * hgt) / (BAND_Y1 - BAND_Y0))
        wallGeo.append(q)
    for ax, az, bx, bz in [[x0 + 0.16, z1 - 0.16, x0 + 0.16, z0 + 0.16], [x0 + 0.16, z0 + 0.16, x1 - 0.16, z0 + 0.16],
                           [x1 - 0.16, z0 + 0.16, x1 - 0.16, z1 - 0.16], [x1 - 0.16, z1 - 0.16, x0 + 0.16, z1 - 0.16]]:
        len_ = math.hypot(bx - ax, bz - az)
        alongX = abs(bx - ax) > abs(bz - az)
        wallAt = az if alongX else ax
        # door spans on this wall, as distances s from (ax, az)
        cuts = []
        for d in doorsHere:
            axis, at = d['line']
            if (axis == 'z') != alongX or abs(at - wallAt) > 0.6:
                continue
            a = (d['span'][0] - ax) / (bx - ax) * len_ if alongX else (d['span'][0] - az) / (bz - az) * len_
            b = (d['span'][1] - ax) / (bx - ax) * len_ if alongX else (d['span'][1] - az) / (bz - az) * len_
            cuts.append([max(0, min(a, b) - 0.15), min(len_, max(a, b) + 0.15), d['height'] + 0.15])
        cuts.sort(key=lambda m: m[0])
        sPos = 0
        for c0, c1, top in cuts:
            piece(ax, az, bx, bz, len_, sPos, c0, BAND_Y0, BAND_Y1)
            piece(ax, az, bx, bz, len_, c0, c1, max(BAND_Y0, top), BAND_Y1)
            sPos = c1
        piece(ax, az, bx, bz, len_, sPos, len_, BAND_Y0, BAND_Y1)
    specksWall = THREE.Mesh(mergeGeometries(wallGeo, False), speckMat(wallTex, 0.4, 'sa_specks_wall'))
    specksWall.material.side = THREE.DoubleSide
    specksWall.material.opts['side'] = THREE.DoubleSide
    specksWall.name = 'sa_specks_wall'
    for s in [specksFloor, specksWall]:
        s.visible = False
        s.renderOrder = 2
        s.castShadow = False
        s.userData.noMerge = True
        root.add(s)

    # gel beams: the cone geometry (the room aims / scales one clone per gel Fresnel)
    beam = THREE.Mesh(THREE.CylinderGeometry(0.9, 0.12, 1, 20, 1, True).translate(0, 0.5, 0).rotateX(HP), M.beam)
    beam.name = 'sa_beam'
    beam.visible = False
    beam.renderOrder = 3
    beam.castShadow = False
    root.add(beam)

    # hanging bats over the audience + the carousel
    rb = mulberry(77)
    for i in range(14):
        x, z, y = -5 + rb() * 18, -27 + rb() * 12, 4.6 + rb() * 1.2
        if math.hypot(x - 4, z + 21) < 1.2:
            continue
        s = 1.4 + rb() * 1.2
        b = bat(game, s)
        b.add(stringTo(studioMats(game), 0, 0.02 * s, 0, GRID_Y - y))
        rb()   # rotY (studio_a.gd draws the same stream)
        rb()   # rotation.z
        root.add(_named(b, 'sa_bat_%d' % i))
    # hanging telethon banner ("operators are standing by") over the east aisle
    root.add(_named(bannerA(game, A, 'operators', 6.4, 0.75, hang=GRID_Y - 4.9 - 0.375, color='#1B2F7A'), 'sa_banner_operators'))
    # walls
    root.add(_named(bannerA(game, A, 'pledge', 9.2, 1.08, color='#E23B3B'), 'sa_banner_pledge'))
    root.add(_named(bannerA(game, A, 'thanks', 7.2, 0.84, color='#5A2A22'), 'sa_banner_thanks'))
    root.add(_named(bannerA(game, A, 'goal', 5.4, 1.24, color='#1B2F7A'), 'sa_banner_goal'))
    root.add(_named(bannerA(game, A, 'studio', 2.6, 1.26, color='#2A1D2A'), 'sa_banner_studio'))
    root.add(_named(bannerA(game, A, 'quiet', 1.5, 0.46, color='#2A1D2A'), 'sa_banner_quiet'))
    for reg in ['poster1', 'poster2', 'poster3']:
        root.add(_named(bannerA(game, A, reg, 0.78, 1.04, color=PAL.harvestGold), 'sa_banner_' + reg))
    # floor gear: the feed monitor's stand, the sandbags of the light stands
    root.add(standMonitorStand(game, 'mon_studio_a_stand'))
    root.add(_named(sandbag(game), 'sa_sandbag'))
    return root


# ============================================================================================ Studio B atlas
GRID_Y_B = 5.0                       # surfaces.js studio_b gridY (pipes along x at 5.0, along z at 5.09)
GX = [16.67, 18.8, 20.93, 23.07, 25.2, 27.33]      # z-running pipes (x fixed)
GZ = [-26.33, -24.2, -22.07, -19.93, -17.8, -15.67]  # x-running pipes (z fixed)
WB = JSObj(w=15.155, e=28.845, n=-27.845, s=-14.155)  # inner wall faces
PASTEL = ['#FF8FB8', '#FFB347', '#FFE45C', '#8CE07A', '#6FD3F0', '#9E8CFF', '#FF6F91']

REG_B = {
    'logo': [0, 0, 1024, 300],
    'peanut': [640, 300, 384, 96],
    'clap': [640, 396, 384, 104],
    'drawings': [0, 500, 480, 240],
    'sunflower': [480, 500, 176, 280],
    'poster': [656, 500, 144, 192],
    'cloud': [800, 500, 224, 128],
    'star': [800, 628, 72, 72],
    'moon': [872, 628, 72, 72],
    'note': [944, 628, 80, 72],
    'saturn': [656, 692, 160, 96],
    'raindrop': [816, 700, 64, 80],
    'spike': [880, 700, 72, 72],
    'heart': [952, 700, 72, 72],
    'launch': [0, 740, 256, 256],
    'cue1': [256, 740, 160, 112],
    'cue2': [256, 852, 160, 112],
    'piano': [416, 780, 240, 56],
    'pianoLbl': [416, 836, 240, 40],
    'chest': [416, 876, 240, 104],
    'signB': [656, 788, 240, 112],
    'countdown': [656, 900, 240, 112],
    'sock': [896, 780, 128, 128],
    'eyes': [896, 908, 128, 104],
    'white': [1000, 1014, 24, 10],
}
WHITE_UV = [(1000 + 12) / 1024, 1 - (1014 + 5) / 1024]


def solidUV(geo):
    """uv of every vertex -> the white atlas block (vertex-coloured sticks merge with the atlas cut-outs)"""
    uv = geo.attributes.uv
    for i in range(uv.count):
        uv.setXY(i, WHITE_UV[0], WHITE_UV[1])
    uv.needsUpdate = True
    return geo


def drawingUV(A, i):
    """sub-cell of the drawings region (3 x 2 cells of 160 x 120)"""
    x, y = REG_B['drawings'][0], REG_B['drawings'][1]
    cx, cy, S = x + (i % 3) * 160, y + (i // 3) * 120, 1024
    return [cx / S, 1 - (cy + 120) / S, (cx + 160) / S, 1 - cy / S]


def owlFace(ctx, x, y, s, body='#8A5A3A', belly='#C89A6A'):
    ctx.save(); ctx.translate(x, y); ctx.scale(s, s)
    ctx.fillStyle = body
    ctx.beginPath(); ctx.moveTo(-40, -30); ctx.lineTo(-52, -70); ctx.lineTo(-14, -48); ctx.lineTo(14, -48); ctx.lineTo(52, -70); ctx.lineTo(40, -30); ctx.closePath(); ctx.fill()
    ctx.beginPath(); ctx.ellipse(0, 0, 58, 54, 0, 0, TAU); ctx.fill()
    ctx.fillStyle = belly; ctx.beginPath(); ctx.ellipse(0, 22, 30, 26, 0, 0, TAU); ctx.fill()
    for sd in [-1, 1]:
        ctx.fillStyle = '#FFF8E8'; ctx.beginPath(); ctx.arc(sd * 24, -8, 22, 0, TAU); ctx.fill()
        ctx.strokeStyle = '#F4A020'; ctx.lineWidth = 5; ctx.stroke()
        ctx.fillStyle = '#2A1D3A'; ctx.beginPath(); ctx.arc(sd * 21, -6, 11, 0, TAU); ctx.fill()
        ctx.fillStyle = '#fff'; ctx.beginPath(); ctx.arc(sd * 17, -11, 4, 0, TAU); ctx.fill()
    ctx.fillStyle = '#F4A020'; ctx.beginPath(); ctx.moveTo(-9, 12); ctx.lineTo(9, 12); ctx.lineTo(0, 27); ctx.closePath(); ctx.fill()
    ctx.restore()


def crayonLine(ctx, pts, color, w=5, rand=None):
    import random
    rand = rand or random.random
    ctx.strokeStyle = color; ctx.lineWidth = w; ctx.lineCap = 'round'; ctx.lineJoin = 'round'
    for pass_ in range(2):
        ctx.globalAlpha = 0.55 if pass_ else 0.9
        ctx.beginPath()
        for i, (x, y) in enumerate(pts):
            jx, jy = (rand() - 0.5) * 2.4, (rand() - 0.5) * 2.4
            if i:
                ctx.lineTo(x + jx, y + jy)
            else:
                ctx.moveTo(x + jx, y + jy)
        ctx.stroke()
    ctx.globalAlpha = 1


def circlePts(cx, cy, r, n=18, ry=None):
    ry = r if ry is None else ry
    return [[cx + math.cos((i / n) * TAU) * r, cy + math.sin((i / n) * TAU) * ry] for i in range(n + 1)]


def hillsTex():
    """Painted "Hullabaloo Hills" flat (own 1024x576 canvas): sky, smiling sun, clouds, rainbow, rolling hills,
    flowers, the WZTV tower on a far hill. Drawn in a 1024x300 design space, scaled."""
    def draw(ctx, W0, H0, rand):
        ink = '#3A1E2E'
        x, y, w, h = 0, 0, W0, 300
        ctx.save(); ctx.translate(x, y); ctx.scale(1, H0 / 300)
        g = ctx.createLinearGradient(0, 0, 0, h)
        g.addColorStop(0, '#7CC8FF'); g.addColorStop(0.6, '#BFE6FF'); g.addColorStop(1, '#E6F6FF')
        ctx.fillStyle = g; ctx.fillRect(0, 0, w, h)
        # brush texture on the sky
        for i in range(80):
            ctx.strokeStyle = 'rgba(255,255,255,%s)' % _num(0.05 + rand() * 0.08)
            ctx.lineWidth = 2 + rand() * 4
            xx, yy = rand() * w, rand() * h * 0.6
            ctx.beginPath(); ctx.moveTo(xx, yy); ctx.lineTo(xx + 30 + rand() * 60, yy + (rand() - 0.5) * 6); ctx.stroke()
        # rainbow behind the hills
        rc = ['#FF6F6F', '#FFB347', '#FFE45C', '#8CE07A', '#6FD3F0', '#9E8CFF']
        for i, c in enumerate(rc):
            ctx.strokeStyle = c; ctx.lineWidth = 13; ctx.beginPath(); ctx.arc(700, 300, 190 - i * 13, PI, TAU); ctx.stroke()
        # smiling sun with rays
        sx, sy = 150, 92
        ctx.fillStyle = '#FFB347'
        for i in range(14):
            a = (i / 14) * TAU
            ctx.beginPath(); ctx.moveTo(sx + math.cos(a - 0.12) * 60, sy + math.sin(a - 0.12) * 60); ctx.lineTo(sx + math.cos(a) * 92, sy + math.sin(a) * 92); ctx.lineTo(sx + math.cos(a + 0.12) * 60, sy + math.sin(a + 0.12) * 60); ctx.fill()
        ctx.fillStyle = '#FFD23A'; ctx.beginPath(); ctx.arc(sx, sy, 62, 0, TAU); ctx.fill()
        ctx.strokeStyle = '#F29A1E'; ctx.lineWidth = 5; ctx.stroke()
        ctx.fillStyle = ink
        for sd in [-1, 1]:
            ctx.beginPath(); ctx.ellipse(sx + sd * 20, sy - 10, 7, 11, 0, 0, TAU); ctx.fill()
        ctx.fillStyle = 'rgba(255,110,120,0.5)'
        for sd in [-1, 1]:
            ctx.beginPath(); ctx.arc(sx + sd * 36, sy + 10, 10, 0, TAU); ctx.fill()
        ctx.strokeStyle = ink; ctx.lineWidth = 5; ctx.lineCap = 'round'; ctx.beginPath(); ctx.arc(sx, sy + 6, 24, 0.2, PI - 0.2); ctx.stroke()

        # puffy clouds
        def cloud(cx, cy, s):
            ctx.fillStyle = '#FFFFFF'
            for dx, dy, r in [[-38, 6, 24], [-12, -10, 32], [20, -4, 28], [44, 8, 20], [0, 12, 26]]:
                ctx.beginPath(); ctx.arc(cx + dx * s, cy + dy * s, r * s, 0, TAU); ctx.fill()
            ctx.fillStyle = 'rgba(150,190,230,0.35)'; ctx.fillRect(cx - 60 * s, cy + 22 * s, 120 * s, 6 * s)
        cloud(420, 70, 1.1); cloud(880, 58, 0.95); cloud(640, 118, 0.7)

        # hills (back to front) with scalloped tops
        def hill(y0, amp, col, ph, dark):
            ctx.fillStyle = col; ctx.beginPath(); ctx.moveTo(0, h)
            xx = 0
            while xx <= w:
                ctx.lineTo(xx, y0 - math.sin(xx * 0.006 + ph) * amp - math.sin(xx * 0.017 + ph * 2) * amp * 0.25)
                xx += 8
            ctx.lineTo(w, h); ctx.closePath(); ctx.fill()
            ctx.strokeStyle = dark; ctx.lineWidth = 4; ctx.beginPath()
            xx = 0
            while xx <= w:
                yy = y0 - math.sin(xx * 0.006 + ph) * amp - math.sin(xx * 0.017 + ph * 2) * amp * 0.25
                if xx:
                    ctx.lineTo(xx, yy)
                else:
                    ctx.moveTo(xx, yy)
                xx += 8
            ctx.stroke()
        hill(205, 34, '#9ED86A', 0.4, '#7DBE52')
        # the WZTV tower on the far hill (station in-joke)
        tx, ty = 905, 172
        ctx.strokeStyle = '#E23B3B'; ctx.lineWidth = 3; ctx.beginPath(); ctx.moveTo(tx - 12, ty); ctx.lineTo(tx, ty - 70); ctx.lineTo(tx + 12, ty); ctx.stroke()
        for i in range(1, 5):
            ctx.beginPath(); ctx.moveTo(tx - 12 + i * 2.4, ty - i * 14); ctx.lineTo(tx + 12 - i * 2.4, ty - i * 14); ctx.stroke()
        ctx.fillStyle = '#FF3B30'; ctx.beginPath(); ctx.arc(tx, ty - 72, 5, 0, TAU); ctx.fill()
        hill(236, 28, '#7FCB55', 2.2, '#63AE43')
        hill(270, 22, '#62B845', 4.1, '#4E9A36')
        # winding path + flowers + a little mushroom house
        ctx.fillStyle = '#F2D9A6'; ctx.beginPath(); ctx.moveTo(460, h); ctx.bezierCurveTo(520, 270, 420, 250, 520, 228); ctx.lineTo(532, 230); ctx.bezierCurveTo(450, 256, 560, 272, 520, h); ctx.fill()
        for i in range(70):
            fx, fy, c, r = rand() * w, 225 + rand() * 70, ['#FF8FB8', '#FFE45C', '#FFFFFF', '#FF6F6F', '#B9A2FF'][i % 5], 3 + rand() * 3
            ctx.fillStyle = c
            for k in range(5):
                a = (k / 5) * TAU
                ctx.beginPath(); ctx.arc(fx + math.cos(a) * r, fy + math.sin(a) * r, r * 0.75, 0, TAU); ctx.fill()
            ctx.fillStyle = '#FFB347'; ctx.beginPath(); ctx.arc(fx, fy, r * 0.55, 0, TAU); ctx.fill()
        mx, my = 300, 250
        ctx.fillStyle = '#FFF4DC'; rr(ctx, mx - 18, my - 10, 36, 34, 8); ctx.fill()
        ctx.fillStyle = '#E23B3B'; ctx.beginPath(); ctx.ellipse(mx, my - 12, 40, 26, 0, PI, TAU); ctx.fill()
        ctx.fillStyle = '#FFF'
        for dx, dy in [[-18, -22], [8, -28], [22, -16]]:
            ctx.beginPath(); ctx.arc(mx + dx, my + dy, 5, 0, TAU); ctx.fill()
        ctx.fillStyle = '#8A5A3A'; rr(ctx, mx - 6, my + 6, 12, 18, 5); ctx.fill()
        ctx.restore()
        # painted border
        ctx.lineWidth = 12; ctx.strokeStyle = '#FF8FB8'; rr(ctx, 6, 6, W0 - 12, H0 - 12, 26); ctx.stroke()
    return K.tex.canvas('sb_hills_v1', 1024, 576, draw, {'repeat': False, 'fonts': False})


def drawStudioB(ctx, R, rand):
    ink = '#3A1E2E'
    # ---- show logo banner
    x, y, w0, h0 = R('logo')
    w, h = 640, 200
    ctx.save(); ctx.translate(x, y); ctx.scale(w0 / w, h0 / h)
    rr(ctx, 4, 4, w - 8, h - 8, 44); ctx.fillStyle = '#FF8FB8'; ctx.fill()
    ctx.lineWidth = 10; ctx.strokeStyle = '#FFE45C'; rr(ctx, 14, 14, w - 28, h - 28, 36); ctx.stroke()
    for i in range(26):
        ctx.fillStyle = 'rgba(255,255,255,%s)' % _num(0.25 + rand() * 0.3)
        starPath(ctx, 30 + rand() * (w - 60), 26 + rand() * (h - 52), 5 + rand() * 4, 2)
        ctx.fill()
    owlFace(ctx, 110, 108, 1.15)
    txt(ctx, "Hootie's", 380, 62, {'font': FONT.groovy, 'size': 58, 'fill': '#FFE45C', 'stroke': '#5A1E3E', 'lw': 9, 'shadow': 'rgba(0,0,0,0.25)'})
    word = 'HULLABALOO!'
    cols = ['#E23B3B', '#FF8A2A', '#FFD23A', '#52D24A', '#3FD6E0', '#3A58E4', '#B05AD6']
    ctx.font = '64px %s' % FONT.round
    total = ctx.measureText(word).width * 0.92
    cx = 380 - total / 2
    for i, ch in enumerate(word):
        cw = ctx.measureText(ch).width * 0.92
        txt(ctx, ch, cx + cw / 2, 136 + math.sin(i * 1.1) * 7, {'font': FONT.round, 'size': 64, 'fill': cols[i % len(cols)], 'stroke': '#FFFFFF', 'lw': 9, 'rot': math.sin(i * 1.7) * 0.12, 'shadow': 'rgba(90,30,62,0.45)'})
        cx += cw
    ctx.restore()
    # ---- PEANUT GALLERY plank
    x, y, w, h = R('peanut')
    ctx.save(); ctx.translate(x, y)
    rr(ctx, 2, 2, w - 4, h - 4, 30); ctx.fillStyle = '#C8904E'; ctx.fill()
    for i in range(16):
        ctx.strokeStyle = 'rgba(90,50,20,0.22)'; ctx.lineWidth = 1.5
        yy = 10 + rand() * (h - 20)
        ctx.beginPath(); ctx.moveTo(10, yy); ctx.bezierCurveTo(w * 0.3, yy + 4, w * 0.6, yy - 4, w - 10, yy + 2); ctx.stroke()
    ctx.lineWidth = 6; ctx.strokeStyle = '#7A4A2A'; rr(ctx, 8, 8, w - 16, h - 16, 24); ctx.stroke()

    def peanut(px, py, r):
        ctx.save(); ctx.translate(px, py); ctx.rotate(r); ctx.fillStyle = '#E8C27A'; ctx.beginPath(); ctx.ellipse(0, -9, 10, 12, 0, 0, TAU); ctx.ellipse(0, 10, 11, 13, 0, 0, TAU); ctx.fill(); ctx.strokeStyle = '#9A6A3A'; ctx.lineWidth = 2; ctx.stroke(); ctx.restore()
    peanut(34, h / 2, 0.4); peanut(w - 34, h / 2, -0.4)
    txt(ctx, 'PEANUT GALLERY', w / 2, h / 2 + 2, {'font': FONT.round, 'size': 40, 'fill': '#FFF6E0', 'stroke': '#5A3A22', 'lw': 7, 'maxW': w - 100})
    ctx.restore()
    # ---- CLAP ALONG! sign
    x, y, w, h = R('clap')
    ctx.save(); ctx.translate(x, y)
    rr(ctx, 3, 3, w - 6, h - 6, 26); ctx.fillStyle = '#3A58E4'; ctx.fill()
    ctx.lineWidth = 7; ctx.strokeStyle = '#FFE45C'; rr(ctx, 11, 11, w - 22, h - 22, 20); ctx.stroke()
    for i in range(12):
        ctx.fillStyle = '#FFE45C' if i % 2 else '#FF8FB8'
        ctx.beginPath(); ctx.arc(24 + i * ((w - 48) / 11), 11, 5, 0, TAU); ctx.fill()
        ctx.beginPath(); ctx.arc(24 + i * ((w - 48) / 11), h - 11, 5, 0, TAU); ctx.fill()
    txt(ctx, 'CLAP ALONG!', w / 2, h / 2 + 2, {'font': FONT.sign, 'size': 44, 'fill': '#FFFFFF', 'stroke': '#1B2F7A', 'lw': 6, 'maxW': w - 60})
    ctx.restore()
    # ---- kid drawings (6 cells)
    x0, y0 = R('drawings')[0], R('drawings')[1]
    papers = ['#FFFBEF', '#FFF0F6', '#EFF8FF', '#FFFBE0', '#F2FFEF', '#FFF4E8']
    for i in range(6):
        x, y = x0 + (i % 3) * 160, y0 + (i // 3) * 120
        ctx.save(); ctx.translate(x, y)
        ctx.fillStyle = papers[i]; ctx.fillRect(0, 0, 160, 120)
        ctx.fillStyle = 'rgba(0,0,0,0.05)'; ctx.fillRect(0, 116, 160, 4)
        if i == 0:  # Hootie
            crayonLine(ctx, circlePts(80, 64, 34, 16, 30), '#8A5A3A', 7, rand)
            crayonLine(ctx, circlePts(66, 58, 10), '#3A2A2A', 4, rand); crayonLine(ctx, circlePts(94, 58, 10), '#3A2A2A', 4, rand)
            crayonLine(ctx, [[74, 74], [86, 74], [80, 84], [74, 74]], '#F4A020', 5, rand)
            crayonLine(ctx, [[54, 40], [50, 22], [66, 36]], '#8A5A3A', 5, rand); crayonLine(ctx, [[106, 40], [110, 22], [94, 36]], '#8A5A3A', 5, rand)
            txt(ctx, 'HOOTIE', 80, 108, {'font': FONT.round, 'size': 17, 'fill': '#E23B3B', 'rot': -0.05})
        elif i == 1:  # house + sun
            crayonLine(ctx, [[40, 100], [40, 60], [80, 34], [120, 60], [120, 100], [40, 100]], '#E23B3B', 5, rand)
            crayonLine(ctx, [[70, 100], [70, 78], [88, 78], [88, 100]], '#3A58E4', 4, rand)
            crayonLine(ctx, circlePts(136, 22, 12), '#FFB020', 5, rand)
            for k in range(8):
                a = (k / 8) * TAU
                crayonLine(ctx, [[136 + math.cos(a) * 16, 22 + math.sin(a) * 16], [136 + math.cos(a) * 24, 22 + math.sin(a) * 24]], '#FFB020', 3, rand)
            crayonLine(ctx, [[8, 108], [152, 108]], '#52C24A', 6, rand)
        elif i == 2:  # Telly the TV with legs (a kid who knows)
            crayonLine(ctx, [[46, 30], [114, 30], [118, 84], [42, 84], [46, 30]], '#8A5A3A', 6, rand)
            crayonLine(ctx, [[56, 40], [104, 40], [104, 74], [56, 74], [56, 40]], '#6FD3F0', 5, rand)
            crayonLine(ctx, [[68, 52], [70, 54]], '#222', 5, rand); crayonLine(ctx, [[92, 52], [94, 54]], '#222', 5, rand)
            crayonLine(ctx, [[68, 64], [80, 70], [92, 64]], '#222', 4, rand)
            crayonLine(ctx, [[60, 84], [56, 110]], '#8A5A3A', 5, rand); crayonLine(ctx, [[100, 84], [104, 110]], '#8A5A3A', 5, rand)
            crayonLine(ctx, [[70, 30], [56, 10]], '#999', 3, rand); crayonLine(ctx, [[90, 30], [104, 10]], '#999', 3, rand)
        elif i == 3:  # rocket
            crayonLine(ctx, [[80, 12], [96, 40], [96, 88], [64, 88], [64, 40], [80, 12]], '#E23B3B', 5, rand)
            crayonLine(ctx, circlePts(80, 54, 9), '#3A58E4', 4, rand)
            crayonLine(ctx, [[64, 70], [48, 94], [64, 88]], '#FF8A2A', 4, rand); crayonLine(ctx, [[96, 70], [112, 94], [96, 88]], '#FF8A2A', 4, rand)
            crayonLine(ctx, [[70, 92], [74, 112], [80, 96], [86, 112], [90, 92]], '#FFB020', 5, rand)
            for k in range(5):
                ctx.fillStyle = '#FFD23A'
                starPath(ctx, 20 + rand() * 30 + (k % 2) * 100, 20 + rand() * 80, 6, 2.5)
                ctx.fill()
        elif i == 4:  # tower + lightning
            crayonLine(ctx, [[64, 110], [80, 18], [96, 110]], '#E23B3B', 5, rand)
            for k in range(1, 5):
                crayonLine(ctx, [[64 + k * 3.5, 110 - k * 20], [96 - k * 3.5, 110 - k * 20]], '#E23B3B', 3, rand)
            crayonLine(ctx, [[120, 16], [108, 44], [124, 44], [110, 76]], '#FFC020', 5, rand)
            crayonLine(ctx, circlePts(80, 16, 5), '#FF3B30', 5, rand)
        else:  # rainbow + I <3 13
            rc = ['#E23B3B', '#FF8A2A', '#FFD23A', '#52C24A', '#3A58E4']
            for k, c in enumerate(rc):
                crayonLine(ctx, [[80 + math.cos(PI + (j / 12) * PI) * (54 - k * 7), 76 + math.sin(PI + (j / 12) * PI) * (48 - k * 7)] for j in range(13)], c, 5, rand)
            txt(ctx, 'I ♥ 13', 80, 100, {'font': FONT.round, 'size': 22, 'fill': '#B05AD6', 'rot': 0.04})
        ctx.restore()
    # ---- sunflower cut-out (smiling)
    x, y, w, h = R('sunflower')
    ctx.save(); ctx.translate(x, y)
    ctx.fillStyle = '#4E9A36'; rr(ctx, w / 2 - 7, 88, 14, h - 90, 7); ctx.fill()
    for ly, sd in [[170, -1], [215, 1]]:
        ctx.save(); ctx.translate(w / 2, ly); ctx.scale(sd, 1); ctx.fillStyle = '#62B845'; ctx.beginPath(); ctx.moveTo(0, 0); ctx.quadraticCurveTo(40, -34, 74, -10); ctx.quadraticCurveTo(40, 12, 0, 0); ctx.fill(); ctx.strokeStyle = '#3E7A2C'; ctx.lineWidth = 3; ctx.stroke(); ctx.restore()
    fx, fy = w / 2, 76
    for i in range(14):
        a = (i / 14) * TAU
        ctx.save(); ctx.translate(fx + math.cos(a) * 44, fy + math.sin(a) * 44); ctx.rotate(a); ctx.fillStyle = '#FFD23A' if i % 2 else '#FFC020'; ctx.beginPath(); ctx.ellipse(0, 0, 26, 12, 0, 0, TAU); ctx.fill(); ctx.strokeStyle = '#E89A10'; ctx.lineWidth = 2.5; ctx.stroke(); ctx.restore()
    ctx.fillStyle = '#8A5230'; ctx.beginPath(); ctx.arc(fx, fy, 34, 0, TAU); ctx.fill()
    ctx.fillStyle = 'rgba(0,0,0,0.12)'
    for i in range(30):
        ctx.beginPath(); ctx.arc(fx + (rand() - 0.5) * 50, fy + (rand() - 0.5) * 50, 2, 0, TAU); ctx.fill()
    ctx.fillStyle = '#2A1D2A'
    for sd in [-1, 1]:
        ctx.beginPath(); ctx.ellipse(fx + sd * 11, fy - 6, 4.5, 7, 0, 0, TAU); ctx.fill()
    ctx.strokeStyle = '#2A1D2A'; ctx.lineWidth = 4; ctx.lineCap = 'round'; ctx.beginPath(); ctx.arc(fx, fy + 2, 14, 0.25, PI - 0.25); ctx.stroke()
    ctx.fillStyle = 'rgba(255,120,120,0.55)'
    for sd in [-1, 1]:
        ctx.beginPath(); ctx.arc(fx + sd * 20, fy + 8, 6, 0, TAU); ctx.fill()
    ctx.restore()
    # ---- Hootie poster (cards.js art)
    x, y, w, h = R('poster')
    ctx.save(); ctx.translate(x, y)
    try:
        _drawTo(ctx, 'poster_hootie', w, h)
    except Exception:
        ctx.fillStyle = '#FF8FB8'; ctx.fillRect(0, 0, w, h); owlFace(ctx, w / 2, h / 2, 0.8)
    ctx.restore()
    # ---- cloud with a face
    x, y, w, h = R('cloud')
    ctx.save(); ctx.translate(x, y)
    blobs = [[60, 72, 40], [104, 52, 48], [150, 66, 40], [186, 84, 28], [34, 92, 26], [112, 90, 38]]
    ctx.fillStyle = '#B8D8F8'
    for bx, by, r in blobs:
        ctx.beginPath(); ctx.arc(bx, by + 4, r + 5, 0, TAU); ctx.fill()
    ctx.fillStyle = '#FFFFFF'
    for bx, by, r in blobs:
        ctx.beginPath(); ctx.arc(bx, by, r, 0, TAU); ctx.fill()
    ctx.fillStyle = '#3A2A48'
    for sd in [-1, 1]:
        ctx.beginPath(); ctx.ellipse(110 + sd * 18, 70, 5, 7, 0, 0, TAU); ctx.fill()
    ctx.strokeStyle = '#3A2A48'; ctx.lineWidth = 4; ctx.lineCap = 'round'; ctx.beginPath(); ctx.arc(110, 78, 10, 0.3, PI - 0.3); ctx.stroke()
    ctx.fillStyle = 'rgba(255,140,170,0.6)'
    for sd in [-1, 1]:
        ctx.beginPath(); ctx.arc(110 + sd * 32, 82, 7, 0, TAU); ctx.fill()
    ctx.restore()
    # ---- small cut-outs: star, sleepy moon, music note, saturn, raindrop, spike X, heart
    x, y, w, h = R('star')
    ctx.fillStyle = '#FFD23A'; starPath(ctx, x + w / 2, y + h / 2 + 2, 33, 14); ctx.fill(); ctx.lineWidth = 4; ctx.strokeStyle = '#E8901A'; ctx.stroke()
    x, y, w, h = R('moon')
    cx, cy = x + w / 2, y + h / 2
    ctx.save(); ctx.beginPath(); ctx.arc(cx, cy, 32, 0, TAU); ctx.arc(cx + 17, cy - 9, 27, 0, TAU, True); ctx.fillStyle = '#FFF2C4'; ctx.fill('evenodd'); ctx.restore()
    ctx.strokeStyle = '#8A7A5A'; ctx.lineWidth = 3; ctx.lineCap = 'round'; ctx.beginPath(); ctx.arc(cx - 14, cy + 2, 5, 0.1, PI - 0.1); ctx.stroke()
    ctx.fillStyle = 'rgba(255,140,140,0.6)'; ctx.beginPath(); ctx.arc(cx - 10, cy + 13, 4, 0, TAU); ctx.fill()
    x, y = R('note')[0], R('note')[1]
    ctx.fillStyle = '#FF6F91'; ctx.beginPath(); ctx.ellipse(x + 26, y + 56, 14, 10, -0.4, 0, TAU); ctx.fill(); ctx.beginPath(); ctx.ellipse(x + 58, y + 48, 14, 10, -0.4, 0, TAU); ctx.fill(); ctx.fillRect(x + 36, y + 10, 6, 46); ctx.fillRect(x + 68, y + 4, 6, 44); ctx.beginPath(); ctx.moveTo(x + 36, y + 10); ctx.lineTo(x + 74, y + 2); ctx.lineTo(x + 74, y + 14); ctx.lineTo(x + 36, y + 22); ctx.fill()
    x, y, w, h = R('saturn')
    cx, cy = x + w / 2, y + h / 2
    ctx.save(); ctx.translate(cx, cy); ctx.rotate(-0.25)
    ctx.strokeStyle = '#B9A2FF'; ctx.lineWidth = 9; ctx.beginPath(); ctx.ellipse(0, 0, 70, 18, 0, PI, TAU); ctx.stroke()
    ctx.fillStyle = '#FFB347'; ctx.beginPath(); ctx.arc(0, 0, 32, 0, TAU); ctx.fill()
    ctx.save(); ctx.beginPath(); ctx.arc(0, 0, 32, 0, TAU); ctx.clip(); ctx.fillStyle = '#FF8A5A'; ctx.fillRect(-40, -14, 80, 8); ctx.fillRect(-40, 6, 80, 7); ctx.restore()
    ctx.strokeStyle = '#B9A2FF'; ctx.lineWidth = 9; ctx.beginPath(); ctx.ellipse(0, 0, 70, 18, 0, 0, PI); ctx.stroke()
    ctx.restore()
    x, y, w, h = R('raindrop')
    cx = x + w / 2
    ctx.fillStyle = '#6FB8F0'; ctx.beginPath(); ctx.moveTo(cx, y + 6); ctx.bezierCurveTo(cx + 30, y + 44, cx + 26, y + 74, cx, y + 74); ctx.bezierCurveTo(cx - 26, y + 74, cx - 30, y + 44, cx, y + 6); ctx.fill(); ctx.fillStyle = 'rgba(255,255,255,0.6)'; ctx.beginPath(); ctx.ellipse(cx - 9, y + 46, 5, 9, 0.3, 0, TAU); ctx.fill()
    x, y, w, h = R('spike')
    ctx.save(); ctx.translate(x + w / 2, y + h / 2)
    for a in [0.785, -0.785]:
        ctx.save(); ctx.rotate(a); ctx.fillStyle = '#FF5FA2'; ctx.fillRect(-32, -6, 64, 12); ctx.fillStyle = 'rgba(255,255,255,0.2)'; ctx.fillRect(-32, -6, 64, 2); ctx.restore()
    ctx.restore()
    x, y, w, h = R('heart')
    cx, cy = x + w / 2, y + h / 2
    ctx.fillStyle = '#FF6F91'; ctx.beginPath(); ctx.moveTo(cx, cy + 26); ctx.bezierCurveTo(cx - 44, cy - 2, cx - 20, cy - 36, cx, cy - 14); ctx.bezierCurveTo(cx + 20, cy - 36, cx + 44, cy - 2, cx, cy + 26); ctx.fill(); ctx.fillStyle = 'rgba(255,255,255,0.45)'; ctx.beginPath(); ctx.ellipse(cx - 13, cy - 8, 5, 8, -0.5, 0, TAU); ctx.fill()
    # ---- launch pad ring (painted on the floor around the rocket): red ring, countdown numbers, stars
    x, y, w, h = R('launch')
    cx, cy = x + w / 2, y + h / 2
    Ro = w / 2 - 2
    Ri = Ro * 0.6
    ctx.save()
    ctx.beginPath(); ctx.arc(cx, cy, Ro, 0, TAU); ctx.arc(cx, cy, Ri, 0, TAU, True); ctx.fillStyle = '#FFE45C'; ctx.fill('evenodd')
    ctx.beginPath(); ctx.arc(cx, cy, Ro - 8, 0, TAU); ctx.arc(cx, cy, Ri + 8, 0, TAU, True); ctx.fillStyle = '#E23B3B'; ctx.fill('evenodd')
    for i in range(10):
        a, r = -HP + (i / 10) * TAU, (Ro + Ri) / 2
        txt(ctx, str(10 - i), cx + math.cos(a) * r, cy + math.sin(a) * r, {'font': FONT.round, 'size': 17, 'fill': '#FFF6E0', 'rot': a + HP})
        ctx.fillStyle = '#FFE45C'; starPath(ctx, cx + math.cos(a + TAU / 20) * r, cy + math.sin(a + TAU / 20) * r, 7, 3); ctx.fill()
    ctx.restore()
    # ---- cue cards
    for n, s, col, rot in [['cue1', 'WAVE HI!', '#E23B3B', -0.05], ['cue2', 'SING ALONG!', '#3A58E4', 0.04]]:
        x, y, w, h = R(n)
        ctx.fillStyle = '#FFFBEF'; ctx.fillRect(x, y, w, h)
        ctx.fillStyle = 'rgba(60,90,200,0.25)'
        yy = y + 20
        while yy < y + h - 6:
            ctx.fillRect(x + 6, yy, w - 12, 2)
            yy += 16
        txt(ctx, s, x + w / 2, y + h / 2 - 4, {'font': FONT.round, 'size': 30, 'fill': col, 'maxW': w - 14, 'rot': rot})
        ctx.fillStyle = '#FFD23A'; starPath(ctx, x + w - 18, y + h - 16, 9, 4); ctx.fill()
    # ---- toy piano keys + label
    x, y, w, h = R('piano')
    ctx.fillStyle = '#2A1D2A'; ctx.fillRect(x, y, w, h)
    n = 15
    kw = w / n
    for i in range(n):
        rr(ctx, x + i * kw + 1, y + 1, kw - 2, h - 2, 3); ctx.fillStyle = '#FFFBEF'; ctx.fill()
    for i in range(n - 1):
        if i in [2, 6, 9, 13]:
            continue
        rr(ctx, x + (i + 1) * kw - kw * 0.3, y, kw * 0.6, h * 0.6, 2); ctx.fillStyle = '#2A1D2A'; ctx.fill()
    x, y, w, h = R('pianoLbl')
    rr(ctx, x + 2, y + 2, w - 4, h - 4, 10); ctx.fillStyle = '#8A2A4A'; ctx.fill()
    txt(ctx, "Hootie's Toy Piano", x + w / 2, y + h / 2 + 1, {'font': FONT.groovy, 'size': 24, 'fill': '#FFE45C', 'maxW': w - 20})
    # ---- toy chest front
    x, y, w, h = R('chest')
    ctx.save(); ctx.translate(x, y)
    ctx.fillStyle = '#7FC8F0'; ctx.fillRect(0, 0, w, h)
    ctx.fillStyle = 'rgba(255,255,255,0.18)'
    for i in range(8):
        ctx.fillRect(i * 34, 0, 14, h)
    ctx.lineWidth = 8; ctx.strokeStyle = '#FFE45C'; rr(ctx, 8, 8, w - 16, h - 16, 16); ctx.stroke()
    letters = [['T', '#E23B3B'], ['O', '#52C24A'], ['Y', '#FF8A2A'], ['S', '#B05AD6']]
    for i, (c, col) in enumerate(letters):
        txt(ctx, c, 62 + i * 40, h / 2 + 4 + (-5 if i % 2 else 5), {'font': FONT.round, 'size': 50, 'fill': col, 'stroke': '#FFFFFF', 'lw': 7, 'rot': (0.14 if i % 2 else -0.12)})
    for sx in [24, w - 24]:
        ctx.fillStyle = '#FFE45C'; starPath(ctx, sx, h / 2, 13, 6); ctx.fill()
    ctx.restore()
    # ---- STUDIO B sign (same family as Studio A's)
    x, y, w, h = R('signB')
    ctx.fillStyle = '#E8A92E'; ctx.fillRect(x, y, w, h)
    ctx.fillStyle = '#2A1D2A'
    for i in range(12):
        ctx.beginPath(); ctx.moveTo(x + i * 22, y + h); ctx.lineTo(x + i * 22 + 11, y + h); ctx.lineTo(x + i * 22 + 25, y + h - 14); ctx.lineTo(x + i * 22 + 14, y + h - 14); ctx.fill()
    txt(ctx, 'STUDIO B', x + w / 2, y + 48, {'font': FONT.sign, 'size': 50, 'fill': '#2A1D2A', 'maxW': w - 20})
    # ---- countdown sign (kid-lettered cardboard)
    x, y, w, h = R('countdown')
    ctx.fillStyle = '#D8B27A'; ctx.fillRect(x, y, w, h)
    ctx.fillStyle = 'rgba(120,80,40,0.25)'
    for i in range(20):
        ctx.fillRect(x, y + 4 + i * 5.5, w, 1.5)
    txt(ctx, '3 · 2 · 1', x + w / 2, y + 34, {'font': FONT.round, 'size': 34, 'fill': '#E23B3B', 'stroke': '#FFF6E0', 'lw': 5, 'rot': -0.03})
    txt(ctx, 'BLAST OFF!', x + w / 2, y + 78, {'font': FONT.sign, 'size': 32, 'fill': '#3A58E4', 'stroke': '#FFF6E0', 'lw': 5, 'rot': 0.03, 'maxW': w - 20})
    # ---- Sockette sock (stripes on cream, heel + toe)
    x, y, w, h = R('sock')
    ctx.save(); ctx.translate(x, y)
    ctx.beginPath(); ctx.moveTo(40, 4); ctx.lineTo(84, 4); ctx.lineTo(84, 76); ctx.quadraticCurveTo(84, 122, 36, 122); ctx.quadraticCurveTo(6, 120, 8, 100); ctx.quadraticCurveTo(10, 84, 40, 78); ctx.closePath()
    ctx.save(); ctx.clip()
    ctx.fillStyle = '#F4F1E8'; ctx.fillRect(0, 0, w, h)
    sc = ['#E23B3B', '#F4E03A', '#3A58E4']
    for i in range(5):
        ctx.fillStyle = sc[i % 3]; ctx.fillRect(0, 10 + i * 14, w, 8)
    ctx.fillStyle = '#E23B3B'; ctx.beginPath(); ctx.arc(22, 106, 18, 0, TAU); ctx.fill()
    ctx.fillStyle = '#F4E03A'; ctx.fillRect(0, 0, w, 7)
    ctx.restore()
    ctx.lineWidth = 3; ctx.strokeStyle = 'rgba(60,30,50,0.5)'; ctx.stroke()
    ctx.restore()
    # ---- solid white block (uv target for sticks and strings drawn with the cut-out material)
    x, y, w, h = R('white')
    ctx.fillStyle = '#FFFFFF'; ctx.fillRect(x, y, w, h)
    # ---- googly eyes pair
    x, y = R('eyes')[0], R('eyes')[1]
    for ex, px in [[36, 42], [88, 82]]:
        ctx.fillStyle = '#FFFFFF'; ctx.beginPath(); ctx.arc(x + ex, y + 52, 26, 0, TAU); ctx.fill(); ctx.lineWidth = 3; ctx.strokeStyle = '#2A1D2A'; ctx.stroke(); ctx.fillStyle = '#1E1530'; ctx.beginPath(); ctx.arc(x + px, y + 60, 12, 0, TAU); ctx.fill()


def silhouetteTex():
    """Golden puppet silhouettes (same shapes as the puppet theater apron's dashed outlines), 3 cells of 170 px."""
    def draw(ctx, w, h, rand):
        ctx.clearRect(0, 0, w, h)
        cells = [[85, 128], [256, 128], [427, 128]]
        cy = 0  # silhouettes drawn around (cx, cy) exactly like the apron paths (cy = apron center line)

        def paint():
            g = ctx.createLinearGradient(0, -80, 0, 80); g.addColorStop(0, '#FFF2A0'); g.addColorStop(1, '#FFB020'); ctx.fillStyle = g; ctx.fill(); ctx.lineWidth = 7; ctx.strokeStyle = '#FFFFFF'; ctx.stroke()
        for k, (x, y) in enumerate(cells):
            ctx.save(); ctx.translate(x, y)
            c = 0
            ctx.beginPath()
            if k == 0:  # owl
                ctx.ellipse(c, cy + 10, 50, 62, 0, 0, TAU); ctx.moveTo(c - 40, cy - 34); ctx.lineTo(c - 46, cy - 72); ctx.lineTo(c - 14, cy - 50); ctx.moveTo(c + 40, cy - 34); ctx.lineTo(c + 46, cy - 72); ctx.lineTo(c + 14, cy - 50)
            elif k == 1:  # sock
                ctx.moveTo(c - 28, cy - 80); ctx.lineTo(c + 26, cy - 80); ctx.lineTo(c + 26, cy + 20); ctx.quadraticCurveTo(c + 26, cy + 72, c - 30, cy + 70); ctx.quadraticCurveTo(c - 74, cy + 66, c - 60, cy + 38); ctx.lineTo(c - 28, cy + 26); ctx.closePath()
            else:  # dragon
                ctx.moveTo(c - 50, cy + 60); ctx.quadraticCurveTo(c - 60, cy - 10, c - 10, cy - 30); ctx.lineTo(c - 4, cy - 70); ctx.lineTo(c + 10, cy - 40); ctx.lineTo(c + 22, cy - 76); ctx.lineTo(c + 28, cy - 36); ctx.quadraticCurveTo(c + 78, cy - 36, c + 72, cy - 6); ctx.quadraticCurveTo(c + 40, cy + 4, c + 36, cy + 20); ctx.quadraticCurveTo(c + 40, cy + 60, c + 20, cy + 60); ctx.closePath()
            paint()
            ctx.fillStyle = 'rgba(255,255,255,0.8)'
            for i in range(4):
                starPath(ctx, -40 + i * 27, -86 + (i % 2) * 10, 6, 2.5)
                ctx.fill()
            ctx.restore()
    return K.tex.canvas('sb_silhouettes_v1', 512, 256, draw, {'repeat': False, 'fonts': False})


# ============================================================================================ local builders
def flat(game, tex, w, h):
    """Painted plywood flat standing on the floor (front faces -z), with two stage jacks + sandbags behind."""
    M = studioMats(game)
    g = K.prop('sb_flat')
    g.add(K.m(tg(K.box(w + 0.1, h + 0.1, 0.06, 0.02), '#E8D2B0'), M.lac, {'pos': [0, h / 2 + 0.05, 0.02]}))
    g.add(K.m(quad(w, h), K.mat(game, 'paint', '#ffffff', {'map': tex, 'rough': 0.7}), {'pos': [0, h / 2 + 0.05, -0.012]}))
    for s in [-0.34, 0.34]:
        jack = K.extrude([[0, 0], [0.5, 0], [0, h * 0.8]], 0.04, {'bevel': 0.008})
        m = K.m(tg(jack, '#B89868'), M.lac, {'pos': [s * w - 0.02, 0.02, 0.06], 'rot': [0, -HP, 0]})
        g.add(m)
        g.add(K.m(tg(K.cushion(0.34, 0.13, 0.22, {'puff': 0.03}), '#7A6A48'), M.felt, {'pos': [s * w, 0.07, 0.36]}))
    g.userData.colliders = [{'min': [-w / 2 - 0.05, 0, -0.05], 'max': [w / 2 + 0.05, h + 0.1, 0.55]}]
    return K.finish(game, g, {'ao': {'res': 40}})


def bannerB(game, A, region, w, h, color='#2A1D2A', hang=0, glossy=False):
    """Framed sign / banner (front faces -z), optionally hanging from strings."""
    M = studioMats(game)
    g = K.prop('sb_banner')
    g.add(K.m(tg(K.box(w + 0.08, h + 0.08, 0.04, 0.02), color), M.lac))
    g.add(K.m(quad(w, h, A.uv(region)), A.gloss if glossy else A.mat, {'pos': [0, 0, -0.022]}))
    if hang:
        for s in [-1, 1]:
            g.add(K.m(tg(K.cyl(0.005, 0.005, hang, {'seg': 5}), '#2A2230'), M.lac, {'pos': [s * (w / 2 - 0.15), h / 2 + 0.04, 0]}))
    g.userData.colliders = []
    return K.finish(game, g, {'ao': False})


def starShape(ro, ri, n=5):
    p = []
    for i in range(n * 2):
        a = HP + (i / (n * 2)) * TAU
        r = ri if i % 2 else ro
        p.append([math.cos(a) * r, math.sin(a) * r])
    return p


def toyChest(game, A):
    """Toy chest with the lid open and toys spilling out (front faces -z)."""
    M = studioMats(game)
    g = K.prop('sb_toy_chest')
    Wd, Hh, D = 1.0, 0.5, 0.55
    g.add(K.m(tg(K.box(Wd, Hh, D, 0.04), '#6FB8E8'), M.lac, {'pos': [0, Hh / 2 + 0.04, 0]}))
    g.add(K.m(quad(Wd - 0.08, Hh - 0.1, A.uv('chest')), A.mat, {'pos': [0, Hh / 2 + 0.04, -D / 2 - 0.004]}))
    g.add(K.m(tg(K.box(Wd + 0.04, 0.05, D + 0.04, 0.02), '#FFE45C'), M.lac, {'pos': [0, Hh + 0.05, 0]}))
    for x, z in [[-0.42, -0.2], [0.42, -0.2], [-0.42, 0.2], [0.42, 0.2]]:
        g.add(K.m(tg(THREE.SphereGeometry(0.045, 10, 8), '#FF8FB8'), M.lac, {'pos': [x, 0.03, z]}))
    lid = K.m(tg(K.box(Wd + 0.04, 0.06, D + 0.04, 0.025), '#6FB8E8'), M.lac)
    lid.geometry.translate(0, 0, -(D + 0.04) / 2)
    lid.position.set(0, Hh + 0.08, D / 2 + 0.02)
    lid.rotation.x = -1.95
    g.add(lid)
    # teddy peeking out
    bear = '#C8905A'
    g.add(K.m(tg(THREE.SphereGeometry(0.15, 16, 12), bear), M.felt, {'pos': [-0.22, Hh + 0.16, 0.02]}))
    for s in [-1, 1]:
        g.add(K.m(tg(THREE.SphereGeometry(0.055, 10, 8), bear), M.felt, {'pos': [-0.22 + s * 0.11, Hh + 0.29, 0.03]}))
    g.add(K.m(tg(THREE.SphereGeometry(0.06, 10, 8), '#F0D2A8'), M.felt, {'pos': [-0.22, Hh + 0.12, -0.12]}))
    g.add(K.m(tg(THREE.SphereGeometry(0.022, 8, 6), '#2A1D2A'), M.lac, {'pos': [-0.22, Hh + 0.14, -0.175]}))
    for s in [-1, 1]:
        g.add(K.m(tg(THREE.SphereGeometry(0.018, 8, 6), '#2A1D2A'), M.lac, {'pos': [-0.22 + s * 0.055, Hh + 0.2, -0.13]}))
    g.add(K.m(tg(K.box(0.14, 0.05, 0.05, 0.02), '#E23B3B'), M.felt, {'pos': [-0.22, Hh + 0.05, -0.13]}))
    # striped ball + jack-in-the-box spring + star wand
    ball = THREE.SphereGeometry(0.13, 18, 12)
    K.tint(ball, lambda x, y, z: THREE.Color('#FFFFFF' if abs(y) < 0.04 else ('#E23B3B' if y > 0 else '#3A58E4')))
    g.add(K.m(ball, M.plastic, {'pos': [0.18, Hh + 0.13, 0.08]}))
    g.add(K.m(tg(K.box(0.18, 0.18, 0.18, 0.03), '#FFE45C'), M.lac, {'pos': [0.36, Hh + 0.05, -0.08], 'rot': [0, 0.3, 0]}))
    spring = []
    for i in range(41):
        a = (i / 40) * TAU * 5
        spring.append([math.cos(a) * 0.035, i * 0.006, math.sin(a) * 0.035])
    g.add(K.m(tg(K.tube(spring, 0.007, {'seg': 80, 'radial': 4}), '#C0C6D0'), M.chrome, {'pos': [0.36, Hh + 0.14, -0.08]}))
    g.add(K.m(tg(THREE.SphereGeometry(0.075, 14, 10), '#FFD8B8'), M.lac, {'pos': [0.36, Hh + 0.44, -0.08]}))
    g.add(K.m(tg(THREE.ConeGeometry(0.07, 0.14, 12), '#B05AD6'), M.lac, {'pos': [0.36, Hh + 0.55, -0.08], 'rot': [0.2, 0, 0.3]}))
    g.add(K.m(tg(THREE.SphereGeometry(0.016, 8, 6), '#2A1D2A'), M.lac, {'pos': [0.335, Hh + 0.46, -0.15]}))
    g.add(K.m(tg(THREE.SphereGeometry(0.016, 8, 6), '#2A1D2A'), M.lac, {'pos': [0.385, Hh + 0.46, -0.15]}))
    g.add(K.m(tg(THREE.SphereGeometry(0.02, 8, 6), '#E23B3B'), M.lac, {'pos': [0.36, Hh + 0.43, -0.16]}))
    g.add(K.m(tg(K.cyl(0.01, 0.01, 0.5, {'seg': 6}), '#FF8FB8'), M.lac, {'pos': [0.02, Hh, 0.12], 'rot': [0.35, 0, -0.5]}))
    g.add(K.m(tg(K.extrude(starShape(0.08, 0.035), 0.025, {'bevel': 0.006}), '#FFD23A'), M.lac, {'pos': [0.24, Hh + 0.46, 0.27], 'rot': [0.35, 0, -0.5]}))
    g.userData.colliders = [{'min': [-Wd / 2, 0, -D / 2], 'max': [Wd / 2, Hh + 0.12, D / 2]}]
    return K.finish(game, g, {'ao': {'res': 40}})


def toyPiano(game, A):
    """Pastel upright toy piano + stool (front = keyboard side, faces -z)."""
    M = studioMats(game)
    g = K.prop('sb_toy_piano')
    Wd, pink, cream = 1.2, '#FF9EC4', '#FFF1DC'
    for x, z in [[-0.52, -0.14], [0.52, -0.14], [-0.52, 0.16], [0.52, 0.16]]:
        g.add(K.m(tg(K.cyl(0.035, 0.028, 0.34, {'seg': 10}), cream), M.lac, {'pos': [x, 0, z]}))
    g.add(K.m(tg(K.box(Wd, 0.5, 0.42, 0.05), pink), M.lac, {'pos': [0, 0.6, 0.02]}))
    g.add(K.m(tg(K.box(Wd, 0.46, 0.14, 0.04), pink), M.lac, {'pos': [0, 1.08, 0.16]}))
    g.add(K.m(tg(K.box(Wd + 0.06, 0.05, 0.22, 0.02), cream), M.lac, {'pos': [0, 1.33, 0.14]}))
    # keyboard shelf + keys (atlas) + key cheeks
    g.add(K.m(tg(K.box(Wd - 0.04, 0.05, 0.24, 0.015), '#2A1D2A'), M.lac, {'pos': [0, 0.86, -0.14]}))
    keys = quad(Wd - 0.18, 0.2, A.uv('piano')).rotateX(-HP)
    g.add(K.m(keys, A.gloss, {'pos': [0, 0.887, -0.14]}))
    for s in [-1, 1]:
        g.add(K.m(tg(K.box(0.07, 0.1, 0.26, 0.02), pink), M.lac, {'pos': [s * (Wd / 2 - 0.05), 0.9, -0.14]}))
    g.add(K.m(quad(0.72, 0.12, A.uv('pianoLbl')), A.gloss, {'pos': [0, 0.6, -0.195]}))
    # music stand with a song sheet + a floating note cut-out
    g.add(K.m(tg(K.box(0.5, 0.3, 0.02, 0.008), '#FFFBEF'), M.lac, {'pos': [0, 1.06, 0.07], 'rot': [-0.25, 0, 0]}))
    for i in range(4):
        g.add(K.m(tg(K.box(0.42, 0.006, 0.004, 0.001), '#6A6A8A'), M.lac, {'pos': [0, 0.97 + i * 0.05, 0.055 - i * 0.012], 'rot': [-0.25, 0, 0]}))
    note = K.m(quad(0.2, 0.18, A.uv('note')), A.cut, {'pos': [0.34, 1.52, 0.14], 'rot': [0, 0, 0.2]})
    g.add(note)
    g.add(K.m(tg(K.cyl(0.004, 0.004, 0.18, {'seg': 4}), '#2A2230'), M.lac, {'pos': [0.34, 1.34, 0.14]}))
    # stool
    g.add(K.m(tg(K.cyl(0.03, 0.04, 0.42, {'seg': 10}), cream), M.lac, {'pos': [0.05, 0, -0.62]}))
    g.add(K.m(tg(K.cyl(0.18, 0.2, 0.03, {'seg': 16}), cream), M.lac, {'pos': [0.05, 0, -0.62]}))
    g.add(K.m(tg(K.cushion(0.36, 0.08, 0.36, {'puff': 0.03}), '#B05AD6'), M.felt, {'pos': [0.05, 0.46, -0.62]}))
    g.userData.colliders = [{'min': [-Wd / 2, 0, -0.27], 'max': [Wd / 2, 1.36, 0.25]}, {'min': [-0.15, 0, -0.82], 'max': [0.25, 0.5, -0.42]}]
    return K.finish(game, g, {'ao': {'res': 44}})


def costumeRack(game):
    """Rolling wardrobe rack with Hootie's owl costume on a hanger and the big owl head on a hatbox (front faces -z)."""
    M = studioMats(game)
    g = K.prop('sb_costume_rack')
    Wd, H, chromeC = 1.2, 1.72, '#C0C6D0'
    for s in [-1, 1]:
        g.add(K.m(tg(K.cyl(0.02, 0.02, H, {'seg': 10}), chromeC), M.chrome, {'pos': [s * Wd / 2, 0.08, 0]}))
        g.add(K.m(tg(K.cyl(0.018, 0.018, 0.5, {'seg': 8}).clone().rotateX(HP).translate(0, 0, -0.25), chromeC), M.chrome, {'pos': [s * Wd / 2, 0.1, 0.25]}))
        for z in [-0.24, 0.24]:
            g.add(K.m(tg(THREE.SphereGeometry(0.04, 10, 8), '#2A2230'), M.lac, {'pos': [s * Wd / 2, 0.04, z]}))
    g.add(K.m(tg(K.cyl(0.018, 0.018, Wd, {'seg': 10}).clone().rotateZ(HP).translate(Wd / 2, 0, 0), chromeC), M.chrome, {'pos': [-Wd / 2, H + 0.06, 0]}))
    # hangers + owl suit (felt body, cream belly, wings) + a striped sock-puppet costume
    brown = '#8A5A3A'
    for x, w in [[-0.18, 1], [0.34, 0.8]]:
        g.add(K.m(tg(K.tube([[x - 0.18 * w, H - 0.08, 0], [x, H, 0], [x + 0.18 * w, H - 0.08, 0]], 0.008, {'seg': 8, 'radial': 4}), '#C8A06A'), M.lac))
        g.add(K.m(tg(K.tube([[x, H, 0], [x, H + 0.06, 0]], 0.006, {'seg': 2, 'radial': 4}), chromeC), M.chrome))
    suit = THREE.SphereGeometry(0.3, 18, 14)
    suit.scale(1, 1.55, 0.55)
    g.add(K.m(tg(suit, brown), M.felt, {'pos': [-0.18, H - 0.52, 0]}))
    belly = THREE.SphereGeometry(0.2, 16, 12)
    belly.scale(1, 1.4, 0.4)
    g.add(K.m(tg(belly, '#E8C89A'), M.felt, {'pos': [-0.18, H - 0.6, -0.1]}))
    for s in [-1, 1]:
        wing = THREE.SphereGeometry(0.16, 12, 10)
        wing.scale(0.55, 1.5, 0.35)
        g.add(K.m(tg(wing, '#6E4428'), M.felt, {'pos': [-0.18 + s * 0.3, H - 0.55, 0.02], 'rot': [0, 0, s * 0.25]}))
    for i in range(5):
        g.add(K.m(tg(THREE.SphereGeometry(0.03, 8, 6), '#FFE45C'), M.plastic, {'pos': [-0.18, H - 0.35 - i * 0.1, -0.2]}))
    sock = THREE.CylinderGeometry(0.15, 0.13, 0.85, 16, 6)
    K.tint(sock, lambda x, y, z: THREE.Color(['#E23B3B', '#F4E03A', '#3A58E4', '#F4F1E8'][int(math.floor((y + 0.43) / 0.14)) % 4]))
    g.add(K.m(sock, M.felt, {'pos': [0.34, H - 0.55, 0], 'rot': [0, 0, 0.04]}))
    # hatbox + the big owl head
    g.add(K.m(tg(K.cyl(0.26, 0.26, 0.34, {'seg': 20}), '#FF8FB8'), M.lac, {'pos': [0.95, 0, -0.05]}))
    g.add(K.m(tg(K.cyl(0.275, 0.275, 0.05, {'seg': 20}), '#FFE45C'), M.lac, {'pos': [0.95, 0.33, -0.05]}))
    hx, hy, hz = 0.95, 0.68, -0.05
    head = THREE.SphereGeometry(0.3, 20, 16)
    head.scale(1, 0.92, 0.95)
    g.add(K.m(tg(head, brown), M.felt, {'pos': [hx, hy, hz]}))
    ring = [[math.cos((i / 16) * TAU) * 0.11, math.sin((i / 16) * TAU) * 0.11, 0] for i in range(17)]
    for s in [-1, 1]:
        # feathery ear tufts + the heart-shaped cream facial disc that makes it read as an owl
        tuft = THREE.ConeGeometry(0.075, 0.24, 10)
        tuft.scale(1, 1, 0.45)
        g.add(K.m(tg(tuft, '#6E4428'), M.felt, {'pos': [hx + s * 0.2, hy + 0.3, hz + 0.02], 'rot': [0, 0, -s * 0.55]}))
        disc = THREE.SphereGeometry(0.15, 16, 12)
        disc.scale(1, 1.12, 0.32)
        g.add(K.m(tg(disc, '#F0DDB8'), M.felt, {'pos': [hx + s * 0.1, hy + 0.01, hz - 0.2]}))
        g.add(K.m(tg(THREE.SphereGeometry(0.1, 14, 10), '#FFF8E8'), M.lac, {'pos': [hx + s * 0.11, hy + 0.04, hz - 0.22]}))
        g.add(K.m(tg(K.tube(ring, 0.018, {'seg': 24, 'radial': 5, 'closed': True}), '#F4A020'), M.lac, {'pos': [hx + s * 0.11, hy + 0.04, hz - 0.26]}))
        g.add(K.m(tg(THREE.SphereGeometry(0.045, 10, 8), '#2A1D3A'), M.lac, {'pos': [hx + s * 0.1, hy + 0.03, hz - 0.31]}))
    g.add(K.m(tg(THREE.ConeGeometry(0.05, 0.12, 10).rotateX(-HP * 1.2), '#F4A020'), M.lac, {'pos': [hx, hy - 0.07, hz - 0.3]}))
    g.userData.colliders = [{'min': [-Wd / 2 - 0.05, 0, -0.3], 'max': [Wd / 2 + 0.05, H + 0.1, 0.3]}, {'min': [0.66, 0, -0.34], 'max': [1.24, 1.0, 0.24]}]
    return K.finish(game, g, {'ao': {'res': 40}})


def cutout(game, A, region, w, h, stake=0, stakeColor='#4E9A36'):
    """Cut-out on a stake (sunflower) — front faces -z."""
    M = studioMats(game)
    g = K.prop('sb_cutout')
    g.add(K.m(quad(w, h, A.uv(region)), A.cut, {'pos': [0, h / 2 + stake, 0]}))
    if stake:
        g.add(K.m(tg(K.box(0.05, stake + h * 0.3, 0.03, 0.01), stakeColor), M.lac, {'pos': [0, (stake + h * 0.3) / 2, 0.03]}))
    g.userData.colliders = []
    return K.finish(game, g, {'ao': False})


def balloonCluster(game, seed, n=5, rise=1.0):
    """Balloon cluster: tie point at the origin, balloons floating 0.8..1.5 m above (one mesh, one draw)."""
    M = studioMats(game)
    rnd = mulberry(seed)
    g = THREE.Group()
    g.name = 'sb_balloons'
    cols = ['#FF5F7F', '#FFD23A', '#6FD3F0', '#8CE07A', '#B9A2FF', '#FF9A3C', '#FF8FB8']
    for i in range(n):
        a = (i / n) * TAU + rnd() * 0.6
        r = 0.14 + rnd() * 0.16
        y = rise + rnd() * 0.5
        top = THREE.Vector3(math.cos(a) * r, y, math.sin(a) * r)
        b = THREE.SphereGeometry(0.16, 14, 11)
        b.scale(1, 1.18, 1)
        col = cols[(i + seed) % len(cols)]
        g.add(K.m(tg(b, col), M.plastic, {'pos': [top.x, top.y + 0.19, top.z]}))
        g.add(K.m(tg(THREE.ConeGeometry(0.03, 0.05, 8).rotateX(PI), col), M.plastic, {'pos': [top.x, top.y - 0.005, top.z]}))
        mid = top.clone().multiplyScalar(0.5).add(THREE.Vector3((rnd() - 0.5) * 0.08, 0, (rnd() - 0.5) * 0.08))
        g.add(K.m(tg(K.tube([[0, 0, 0], [mid.x, mid.y, mid.z], [top.x, top.y - 0.03, top.z]], 0.004, {'seg': 8, 'radial': 3}), '#FFFFFF'), M.plastic))
    K.merge(g)

    def f(o):
        if getattr(o, 'isMesh', False):
            o.castShadow = False
            o.receiveShadow = True
    g.traverse(f)
    g.userData.noMerge = True
    return g


def mobile(game, A, items, drop=0.9, bar=1.2, glowMat=None, name='sb_mobile'):
    """Hanging mobile: string from the grid to a crossbar, cut-outs dangling (rotates as one piece)."""
    g = THREE.Group()
    g.name = name + '_spin'
    barY = -drop

    def stick(geo, color):
        return solidUV(tg(geo, color))
    g.add(K.m(stick(K.cyl(0.004, 0.004, drop, {'seg': 4}), '#2A2230'), A.cut, {'pos': [0, barY, 0]}))
    g.add(K.m(stick(K.cyl(0.012, 0.012, bar, {'seg': 6}).clone().rotateZ(HP).translate(bar / 2, 0, 0), '#F4F1E8'), A.cut, {'pos': [0, barY, 0]}))
    g.add(K.m(stick(K.cyl(0.012, 0.012, bar * 0.7, {'seg': 6}).clone().rotateX(HP).translate(0, 0, -bar * 0.35), '#FF8FB8'), A.cut, {'pos': [0, barY, 0]}))
    for it in items:
        x, z = it['at']
        y = barY - it['hang']
        g.add(K.m(stick(K.cyl(0.003, 0.003, it['hang'], {'seg': 4}), '#2A2230'), A.cut, {'pos': [x, y, z]}))
        q = K.m(quad(it['w'], it['h'], A.uv(it['region'])), glowMat if (it.get('glow') and glowMat) else A.cut, {'pos': [x, y - it['h'] / 2 + 0.02, z], 'rot': [0, it.get('rot', 0), 0]})
        g.add(q)
    grp = THREE.Group()
    grp.name = name
    grp.add(g)
    K.merge(g)

    def f(o):
        if getattr(o, 'isMesh', False):
            o.castShadow = False
            o.receiveShadow = False
    g.traverse(f)
    grp.userData.noMerge = True
    grp.userData.spin = g
    return grp


def sagPts(a, b, sag, n=12):
    """Sagging catenary points between a and b"""
    pts = []
    for i in range(n + 1):
        t = i / n
        pts.append([a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t - math.sin(t * PI) * sag, a[2] + (b[2] - a[2]) * t])
    return pts


def sampleAlong(pts, step):
    out = []
    acc = 0
    for i in range(1, len(pts)):
        a, b = v3(pts[i - 1]), v3(pts[i])
        d = a.distanceTo(b)
        while acc <= d:
            out.append(JSObj(p=a.clone().lerp(b, acc / d), dir=b.clone().sub(a).normalize()))
            acc += step
        acc -= d
    return out


def bunting(game, into, a, b, sag, seed=0):
    """Rainbow pennant bunting (string + triangles) added to `into`."""
    M = studioMats(game)
    pts = sagPts(a, b, sag, 16)
    into.add(K.m(tg(K.tube(pts, 0.006, {'seg': 32, 'radial': 3}), '#F4F1E8'), M.lac, {'cast': False}))
    tri = THREE.BufferGeometry()
    tri.setAttribute('position', THREE.Float32BufferAttribute([-0.11, 0, 0, 0.11, 0, 0, 0, -0.28, 0], 3))
    tri.setAttribute('uv', THREE.Float32BufferAttribute([0, 1, 1, 1, 0.5, 0], 2))
    tri.computeVertexNormals()
    flags = sampleAlong(pts, 0.3)
    for i, f in enumerate(flags):
        if i == 0:
            continue
        m = K.m(tg(tri.clone(), PASTEL[(i + seed) % len(PASTEL)]), M.felt, {'pos': [f.p.x, f.p.y - 0.01, f.p.z], 'cast': False})
        m.rotation.y = math.atan2(-f.dir.z, f.dir.x)
        into.add(m)


def fairyLights(game):
    """buildFairyLights(): the green wire runs (static) + the two alternating bulb meshes (sb_fairy_0 / _1)."""
    M = studioMats(game)
    runs = [
        [[15.4, 4.25, WB.n + 0.05], [22.9, 4.3, WB.n + 0.05], 0.4],
        [[WB.w + 0.05, 3.4, -27.5], [WB.w + 0.05, 3.4, -22.0], 0.32],
        [[WB.e - 0.05, 3.5, -20.6], [WB.e - 0.05, 3.5, -15.0], 0.3],
        [[15.6, 4.72, WB.s - 0.05], [24.5, 4.72, WB.s - 0.05], 0.3],
    ]
    wire = THREE.Group()
    wire.name = 'sb_fairy_wire'
    bulbs = [[], []]
    cols = ['#FF5F7F', '#FFD23A', '#6FD3F0', '#8CE07A', '#B9A2FF', '#FF9A3C']
    n = 0
    for a, b, sag in runs:
        pts = []
        segs = 4
        for s in range(segs):
            A_ = [v + (b[i] - v) * (s / segs) for i, v in enumerate(a)]
            B_ = [v + (b[i] - v) * ((s + 1) / segs) for i, v in enumerate(a)]
            sp = sagPts(A_, B_, sag * 0.6, 8)
            pts.extend(sp[1:] if s else sp)
        wire.add(K.m(tg(K.tube(pts, 0.005, {'seg': len(pts) * 2, 'radial': 3}), '#2A4A2A'), M.lac, {'cast': False}))
        for f in sampleAlong(pts, 0.26):
            c = THREE.Color(cols[n % len(cols)]).multiplyScalar(2.2)
            geo = THREE.IcosahedronGeometry(0.032, 1)
            geo.translate(f.p.x, f.p.y - 0.035, f.p.z)
            K.tint(geo, c)
            bulbs[n % 2].append(geo)
            n += 1
    meshes = []
    for i, lst in enumerate(bulbs):
        merged = mergeGeometries(lst, False)
        mat = THREE.MeshBasicMaterial({'vertexColors': True, 'color': THREE.Color(0.55, 0.55, 0.55), 'fog': True,
                                       'name': 'sb_fairy_%d' % i})
        mesh = THREE.Mesh(merged, mat)
        mesh.name = 'sb_fairy_%d' % i
        mesh.castShadow = False
        mesh.userData.noMerge = True
        meshes.append(mesh)
    return wire, meshes


def buildStudioB(game):
    """The local geometry of studio_b.js build() (see the module docstring for the node names)."""
    root = THREE.Group()
    root.name = 'rooms_studio_b'
    M = studioMats(game)
    A = makeAtlas(game, 'sb_atlas_v1', 1024, REG_B, drawStudioB)
    pennantMat = K.mat(game, 'felt', '#ffffff', {'side': THREE.DoubleSide})
    glowCut = THREE.MeshBasicMaterial({'map': A.tex, 'alphaTest': 0.5, 'side': THREE.DoubleSide,
                                       'color': THREE.Color(0.95, 1.0, 1.15), 'fog': True, 'name': 'sb_glowcut'})

    # ---- rocket: painted launch-pad ring on the floor + the kid-lettered countdown sign on a stake
    ring = THREE.PlaneGeometry(3.9, 3.9).rotateX(-HP)
    K.uvRect(ring, *A.uv('launch'))
    root.add(_named(K.m(ring, A.cut, {'cast': False}), 'sb_launch'))
    sign = K.prop('sb_countdown')
    sign.add(K.m(tg(K.box(0.05, 1.2, 0.04, 0.012), '#B89868'), M.lac, {'pos': [0, 0.6, 0.03]}))
    sign.add(K.m(tg(K.box(0.84, 0.44, 0.03, 0.012), '#C8A06A'), M.lac, {'pos': [0, 1.2, 0.012], 'rot': [0, 0, 0.04]}))
    sign.add(K.m(quad(0.8, 0.4, A.uv('countdown')), A.mat, {'pos': [0, 1.2, -0.006], 'rot': [0, 0, 0.04]}))
    sign.userData.colliders = [{'min': [-0.06, 0, -0.05], 'max': [0.06, 1.0, 0.07]}]
    K.finish(game, sign, {'ao': {'res': 28}})
    root.add(_named(sign, 'sb_countdown'))

    # ---- treehouse: cardboard mushrooms + flowers at the trunk's feet
    deco = K.prop('sb_tree_feet')
    for dx, dz, s, c in [[-2.05, 0.1, 1, '#E23B3B'], [-1.7, -0.25, 0.7, '#FF8FB8'], [1.9, -0.1, 0.85, '#FFB347']]:
        deco.add(K.m(tg(K.cyl(0.07 * s, 0.09 * s, 0.26 * s, {'seg': 10}), '#FFF4DC'), M.lac, {'pos': [dx, 0, dz]}))
        cap = THREE.SphereGeometry(0.2 * s, 16, 8, 0, TAU, 0, HP)
        cap.scale(1, 0.62, 1)
        deco.add(K.m(tg(cap, c), M.lac, {'pos': [dx, 0.24 * s, dz]}))
        for k in range(4):
            an = k * 1.7 + dx
            deco.add(K.m(tg(THREE.SphereGeometry(0.03 * s, 8, 6), '#FFFFFF'), M.lac, {'pos': [dx + math.cos(an) * 0.12 * s, 0.24 * s + 0.1 * s, dz + math.sin(an) * 0.12 * s]}))
    deco.userData.colliders = []
    K.finish(game, deco, {'ao': {'res': 32}})
    root.add(_named(deco, 'sb_tree_feet'))

    # ---- puppet theater: golden silhouette overlays (studio_b.gd places them on the apron)
    silTex = silhouetteTex()
    silMat = THREE.MeshBasicMaterial({'map': silTex, 'alphaTest': 0.4, 'color': THREE.Color(1.15, 1.02, 0.78), 'fog': True,
                                      'name': 'sb_silmat'})
    AW = 2.1
    for i, k in enumerate(['owl', 'sock', 'dragon']):
        s = 170 / 512 * AW
        g = THREE.PlaneGeometry(s, s)     # faces +z = the theater front (rotY PI)
        cx0 = [85, 256, 427][i]
        K.uvRect(g, (cx0 - 85) / 512, 1 - (128 + 85) / 256, (cx0 + 85) / 512, 1 - (128 - 85) / 256)
        sil = THREE.Mesh(g, silMat)
        sil.name = 'sb_sil_%s' % k
        sil.visible = False
        sil.castShadow = False
        sil.userData.noMerge = True
        root.add(sil)

    # ---- feed camera corner: the stand + a cue-card easel beside the camera
    root.add(standMonitorStand(game, 'mon_studio_b_stand'))
    easel = K.prop('sb_easel')
    for x, z, rx, rz in [[-0.2, 0, 0.12, 0.14], [0.2, 0, 0.12, -0.14], [0, 0.28, -0.3, 0]]:
        easel.add(K.m(tg(K.cyl(0.015, 0.015, 1.25, {'seg': 6}), '#B89868'), M.lac, {'pos': [x, 0, z], 'rot': [rx, 0, rz]}))
    easel.add(K.m(tg(K.box(0.62, 0.04, 0.08, 0.01), '#B89868'), M.lac, {'pos': [0, 0.72, -0.1]}))
    easel.add(K.m(tg(K.box(0.62, 0.46, 0.02, 0.006), '#FFFBEF'), M.lac, {'pos': [0, 0.98, -0.1], 'rot': [-0.12, 0, 0]}))
    easel.add(K.m(quad(0.58, 0.42, A.uv('cue1')), A.mat, {'pos': [0, 0.98, -0.112], 'rot': [-0.12, 0, 0]}))
    easel.userData.colliders = [{'min': [-0.26, 0, -0.18], 'max': [0.26, 1.2, 0.3]}]
    K.finish(game, easel, {'ao': {'res': 28}})
    root.add(_named(easel, 'sb_easel'))

    # ---- west wall corner
    root.add(_named(flat(game, hillsTex(), 5.0, 2.8), 'sb_flat'))
    root.add(_named(toyPiano(game, A), 'sb_toy_piano'))
    # ---- north wall
    root.add(_named(cutout(game, A, 'sunflower', 1.36, 2.16, stake=0.2), 'sb_sunflower_1'))
    root.add(_named(cutout(game, A, 'sunflower', 1.2, 1.9, stake=0.1), 'sb_sunflower_2'))
    root.add(_named(toyChest(game, A), 'sb_toy_chest'))
    root.add(_named(bannerB(game, A, 'clap', 1.6, 0.43, color='#1B2F7A'), 'sb_banner_clap'))

    # ---- south + east walls
    root.add(_named(bannerB(game, A, 'logo', 5.0, 1.47, color='#FF8FB8', glossy=True), 'sb_banner_logo'))
    # kid drawings pinned on a pastel pin board
    board = K.prop('sb_drawings')
    board.add(K.m(tg(K.box(2.3, 0.95, 0.04, 0.02), '#FFD8E8'), M.lac))
    board.add(K.m(tg(K.box(2.38, 0.05, 0.06, 0.02), '#FFE45C'), M.lac, {'pos': [0, 0.5, -0.01]}))
    board.add(K.m(tg(K.box(2.38, 0.05, 0.06, 0.02), '#FFE45C'), M.lac, {'pos': [0, -0.5, -0.01]}))
    rnd = mulberry(31)
    for i in range(6):
        x, y = -0.74 + (i % 3) * 0.74, 0.2 - (i // 3) * 0.42
        q = quad(0.5, 0.375, drawingUV(A, i))
        m = K.m(q, A.mat, {'pos': [x + (rnd() - 0.5) * 0.06, y + (rnd() - 0.5) * 0.04, -0.024 - i * 0.0005], 'rot': [0, 0, (rnd() - 0.5) * 0.14]})
        board.add(m)
        board.add(K.m(tg(THREE.SphereGeometry(0.016, 8, 6), PASTEL[i]), M.plastic, {'pos': [m.position.x, m.position.y + 0.16, -0.035]}))
    board.userData.colliders = []
    K.finish(game, board, {'ao': False})
    root.add(_named(board, 'sb_drawings'))
    root.add(_named(bannerB(game, A, 'poster', 0.72, 0.96, color='#FFE45C'), 'sb_banner_poster'))
    root.add(_named(bannerB(game, A, 'peanut', 1.9, 0.48, color='#7A4A2A'), 'sb_banner_peanut'))
    root.add(_named(bannerB(game, A, 'signB', 1.5, 0.7, color='#2A1D2A'), 'sb_banner_signB'))
    # cut-outs pinned high on the walls (clouds, stars, the sleepy moon, a heart, a note) + star confetti on the floor
    cuts = [
        ['cloud', 0.9, 0.52, [WB.w + 0.02, 4.45, -26.6], -HP], ['cloud', 0.7, 0.4, [WB.w + 0.02, 4.05, -23.3], -HP],
        ['star', 0.3, 0.3, [WB.w + 0.02, 4.62, -24.9], -HP], ['star', 0.22, 0.22, [WB.w + 0.02, 3.9, -22.2], -HP],
        ['cloud', 0.9, 0.52, [WB.e - 0.02, 4.4, -26.1], HP], ['moon', 0.5, 0.5, [WB.e - 0.02, 4.6, -24.3], HP],
        ['star', 0.28, 0.28, [WB.e - 0.02, 4.12, -23.1], HP], ['star', 0.24, 0.24, [20.25, 3.5, WB.n + 0.02], PI],
        ['heart', 0.26, 0.26, [21.0, 3.28, WB.n + 0.02], PI], ['note', 0.3, 0.27, [19.55, 3.62, WB.n + 0.02], PI],
        ['star', 0.26, 0.26, [WB.e - 0.02, 3.95, -15.6], HP], ['heart', 0.22, 0.22, [WB.e - 0.02, 4.35, -16.4], HP],
    ]
    cutsG = _loose('sb_cuts')
    for reg, w, hh, pos, ry in cuts:
        cutsG.add(K.m(quad(w, hh, A.uv(reg)), A.cut, {'pos': pos, 'rot': [0, ry, math.fmod(pos[0] + pos[2], 0.3) - 0.15], 'cast': False}))
    root.add(cutsG)
    rc = mulberry(1977)
    conf = _loose('sb_confetti')
    for i in range(34):
        x, z = 15.8 + rc() * 12.4, -27.0 + rc() * 12.4
        if math.hypot(x - 22, z + 21) < 2.0 or (z < -26.5 and x > 22.8):
            continue
        s2 = 0.07 + rc() * 0.06
        q = THREE.PlaneGeometry(s2, s2).rotateX(-HP)
        K.uvRect(q, *A.uv('star' if i % 3 else 'heart'))
        K.tint(q, PASTEL[i % len(PASTEL)])
        conf.add(K.m(q, A.cut, {'pos': [x, 0.009, z], 'rot': [0, rc() * TAU, 0], 'cast': False}))
    root.add(conf)
    # floor spike marks (tape)
    spikes = _loose('sb_spikes')
    for x, z, r, s in [[26.0, -25.75, 0.2, 0.55], [20.55, -23.35, 0.7, 0.45], [24.35, -18.4, 0.1, 0.5], [22.0, -16.9, 0.4, 0.4]]:
        q = THREE.PlaneGeometry(s, s).rotateX(-HP)
        K.uvRect(q, *A.uv('spike'))
        spikes.add(K.m(q, A.cut, {'pos': [x, 0.011, z], 'rot': [0, r, 0], 'cast': False}))
    root.add(spikes)
    # leaning cue card against block 1
    cue = K.prop('sb_cue')
    cue.add(K.m(tg(K.box(0.62, 0.46, 0.02, 0.008), '#FFFBEF'), M.lac))
    cue.add(K.m(quad(0.58, 0.42, A.uv('cue2')), A.mat, {'pos': [0, 0, -0.012]}))
    cue.userData.colliders = []
    K.finish(game, cue, {'ao': False})
    root.add(_named(cue, 'sb_cue'))

    root.add(_named(costumeRack(game), 'sb_costume_rack'))

    # ---- sockette clothesline
    socks = _loose('sb_socks')
    a, b = [WB.w + 0.02, 3.35, -24.9], [16.35, 3.2, WB.n + 0.02]
    pts = sagPts(a, b, 0.28, 14)
    socks.add(K.m(tg(K.tube(pts, 0.008, {'seg': 28, 'radial': 4}), '#F4E6C8'), M.lac, {'cast': False}))
    for p in [a, b]:
        socks.add(K.m(tg(K.box(0.05, 0.05, 0.05, 0.012), '#C0C6D0'), M.chrome, {'pos': p}))
    at = sampleAlong(pts, 0.42)
    rnd = mulberry(77)
    for i, f in enumerate(at[1:-1]):
        yaw = math.atan2(-f.dir.z, f.dir.x)
        s = 0.85 + rnd() * 0.3
        sock = K.m(quad(0.3 * s, 0.3 * s, A.uv('sock')), A.cut, {'pos': [f.p.x, f.p.y - 0.15 * s - 0.02, f.p.z], 'rot': [0, yaw + (PI if i % 2 else 0), (rnd() - 0.5) * 0.3], 'cast': False})
        socks.add(sock)
        if i == 1 or i == 4:
            socks.add(K.m(quad(0.12 * s, 0.1 * s, A.uv('eyes')), A.cut, {'pos': [f.p.x + math.sin(yaw) * 0.012, f.p.y - 0.1, f.p.z + math.cos(yaw) * 0.012], 'rot': [0, yaw + (PI if i % 2 else 0), 0], 'cast': False}))
        socks.add(K.m(tg(K.box(0.02, 0.06, 0.02, 0.005), PASTEL[i % len(PASTEL)]), M.plastic, {'pos': [f.p.x, f.p.y - 0.01, f.p.z], 'cast': False}))
    root.add(socks)

    # ---- overhead: bunting
    bg = _loose('sb_bunting')
    bunting(game, bg, [16.0, GRID_Y_B - 0.05, GZ[0]], [27.9, GRID_Y_B - 0.05, GZ[0]], 0.55, 0)
    bunting(game, bg, [15.6, GRID_Y_B - 0.05, GZ[5]], [28.3, GRID_Y_B - 0.05, GZ[5]], 0.5, 3)
    bunting(game, bg, [GX[5], GRID_Y_B + 0.04, -22.6], [GX[5], GRID_Y_B + 0.04, -15.2], 0.45, 5)
    bunting(game, bg, [GX[0], GRID_Y_B + 0.04, -26.0], [GX[0], GRID_Y_B + 0.04, -17.6], 0.45, 1)

    def pen(o):
        if getattr(o, 'isMesh', False) and o.material is M.felt:
            o.material = pennantMat
    bg.traverse(pen)
    root.add(bg)

    # ---- fairy lights
    wire, meshes = fairyLights(game)
    root.add(wire)
    for mm in meshes:
        root.add(mm)

    # ---- mobiles (moon lantern + stars, planets, clouds + raindrops); studio_b.gd hangs them at the JS spots
    specs = [
        {'drop': 0.95, 'bar': 1.3, 'items': [
            {'region': 'moon', 'w': 0.62, 'h': 0.62, 'at': [0, 0], 'hang': 0.25, 'glow': True},
            {'region': 'star', 'w': 0.34, 'h': 0.34, 'at': [0.62, 0], 'hang': 0.45},
            {'region': 'star', 'w': 0.28, 'h': 0.28, 'at': [-0.6, 0], 'hang': 0.6, 'rot': 0.8},
            {'region': 'cloud', 'w': 0.62, 'h': 0.36, 'at': [0, -0.4], 'hang': 0.35, 'rot': 1.2},
            {'region': 'star', 'w': 0.22, 'h': 0.22, 'at': [0, 0.42], 'hang': 0.8, 'rot': 2.1},
        ]},
        {'drop': 0.85, 'bar': 1.4, 'items': [
            {'region': 'saturn', 'w': 0.8, 'h': 0.48, 'at': [0.68, 0], 'hang': 0.3},
            {'region': 'star', 'w': 0.3, 'h': 0.3, 'at': [-0.68, 0], 'hang': 0.5, 'rot': 0.5},
            {'region': 'moon', 'w': 0.36, 'h': 0.36, 'at': [0, -0.45], 'hang': 0.62, 'rot': 2.4},
            {'region': 'heart', 'w': 0.26, 'h': 0.26, 'at': [0, 0.46], 'hang': 0.4, 'rot': 1.0},
        ]},
        {'drop': 0.62, 'bar': 1.3, 'items': [
            {'region': 'cloud', 'w': 0.8, 'h': 0.46, 'at': [0.6, 0], 'hang': 0.25},
            {'region': 'raindrop', 'w': 0.18, 'h': 0.22, 'at': [-0.62, 0], 'hang': 0.55, 'rot': 0.3},
            {'region': 'raindrop', 'w': 0.16, 'h': 0.2, 'at': [0, -0.44], 'hang': 0.75, 'rot': 1.3},
            {'region': 'star', 'w': 0.26, 'h': 0.26, 'at': [0, 0.45], 'hang': 0.5, 'rot': 2.2},
        ]},
    ]
    for i, s in enumerate(specs):
        root.add(mobile(game, A, s['items'], drop=s['drop'], bar=s['bar'], glowMat=glowCut, name='sb_mobile_%d' % i))

    # ---- balloon clusters (studio_b.gd hangs them at the JS spots)
    spots = [[19.0, 2.35, -25.72, 11, 5, 1.0, True], [16.95, 1.25, -21.95, 23, 6, 0.9, True], [15.55, 1.36, -23.7, 5, 4, 0.8, False], [23.35, 3.45, -27.1, 17, 4, 0.55, False]]
    for i, (x, y, z, seed, n, rise, sway) in enumerate(spots):
        root.add(_named(balloonCluster(game, seed, n, rise), 'sb_balloons_%d' % i))

    # ---- lighting: the soft beam cone (studio_b.gd clones it for the theater and Hootie's TV)
    beam = THREE.Mesh(THREE.CylinderGeometry(0.75, 0.1, 1, 20, 1, True).translate(0, 0.5, 0).rotateX(HP), beamMaterial('sb_beam'))
    beam.name = 'sb_beam'
    beam.visible = False
    beam.renderOrder = 3
    beam.castShadow = False
    root.add(beam)
    return root


# ================================================================================================== Yard
HUT_S = 0.85


def buildYard(game):
    """The local geometry of yard.js (buildHut's mast, buildMcWall, buildTrench, buildBeyond's wires)."""
    from props.rooms_studios_yard import apronTex, tm
    root = THREE.Group()
    root.name = 'rooms_yard'
    rand = mulberry32(0x9a2d13)

    # ---- hut + SkyCam: SkyCam rides a mast on the roof's back-east corner (hut-local coordinates)
    RT = 3.05                                   # roof top in hut space (HUT.H 2.75 + 0.1 + 0.2)
    galv = K.mat(game, 'metal', '#A8B0BA', {'rough': 0.45})
    mast = THREE.Group()
    mast.name = 'yd_hut_mast'
    mast.add(K.m(K.cyl(0.13, 0.15, 0.06, {'seg': 12, 'bevel': 0.015}), galv, {'pos': [1.5, RT, 0.95]}))
    mast.add(K.m(K.cyl(0.045, 0.05, 0.42, {'seg': 10, 'bevel': 0.008}), galv, {'pos': [1.5, RT + 0.05, 0.95]}))
    root.add(mast)

    # ---- MC exterior wall (x = 35)
    WX = 35.15
    # DY landing apron: concrete slab with the hazard band and a KEEP CLEAR stencil
    apron = K.mat(game, 'paint', '#ffffff', {'map': apronTex(), 'rough': 0.85})
    slab = K.box(2.4, 0.04, 3.8, 0.012).clone()
    ap = _loose('yd_apron')
    ap.add(K.m(slab, apron, {'pos': [WX + 1.2, 0.02, -8.0]}))
    # top face UVs of a rounded box are box-projected poorly: lay a decal plane on top
    top = THREE.PlaneGeometry(2.34, 3.74).rotateX(-PI / 2)
    ap.add(K.m(top, apron, {'pos': [WX + 1.2, 0.044, -8.0]}))
    root.add(ap)
    # wheat-pasted posters on the block wall
    posters = _loose('yd_posters')

    def poster(card, z, y, w, tilt):
        tex = K.getCard(card)
        m = K.mat(game, 'paint', '#ffffff', {'map': tex, 'rough': 0.7})
        h = w * 4 / 3
        posters.add(K.m(THREE.PlaneGeometry(w, h).rotateY(PI / 2), m, {'pos': [WX + 0.012, y, z], 'rot': [tilt, 0, 0]}))
    poster('poster_spooktacular', -13.55, 1.55, 0.72, 0.03)
    poster('poster_boogie_down', -6.1, 1.35, 0.5, -0.04)
    root.add(posters)
    # hose bib + coiled garden hose under the south wall pack
    rub = K.mat(game, 'rubber', '#4E8A3A', {'rough': 0.6})
    hose = _loose('yd_hose')
    hose.add(K.m(K.cyl(0.03, 0.03, 0.12, {'seg': 8}).clone().rotateZ(-PI / 2), galv, {'pos': [WX, 0.6, -6.0]}))
    coil = []
    for i in range(41):
        a = (i / 40) * TAU * 2.6
        coil.append([WX + 0.28 + math.cos(a) * 0.2, 0.05 + i * 0.0035, -5.95 + math.sin(a) * 0.2])
    hose.add(K.m(K.tube([[WX + 0.1, 0.6, -6.0], [WX + 0.2, 0.35, -6.0]] + coil, 0.018, {'seg': 120, 'radial': 5}), rub))
    root.add(hose)

    # ---- ground detail: the stones / weeds rotations draw from the room stream first (same order as yard.js)
    for _ in range(7):
        rand()
    for _ in range(9):
        rand()

    # ---- coax trench hut -> tower
    conc = K.mat(game, 'paint', '#ffffff', {'map': apronTex(), 'rough': 0.9})
    rubT = K.mat(game, 'rubber', '#2E2A36', {'rough': 0.7})
    tr = _loose('yd_trench')
    a = THREE.Vector2(39.95, -5.1)
    b = THREE.Vector2(42.3, -9.3)
    dir_ = b.clone().sub(a)
    len_ = dir_.length()
    dir_.normalize()
    yaw = math.atan2(dir_.x, dir_.y)
    n = int(math.floor(len_ / 0.52))
    slab2 = K.box(0.44, 0.05, 0.5, 0.012)
    for i in range(n):
        if i == 5:
            continue                           # one cover missing: the cables show
        t = (i + 0.5) / n
        x, z = a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t
        j = (rand() - 0.5) * 0.08
        tr.add(tm(slab2, conc, '#C8C2BA' if i % 3 == 0 else '#B4AEA6', {'pos': [x, 0.018, z], 'rot': [(rand() - 0.5) * 0.04, yaw + j, (rand() - 0.5) * 0.05]}))
    # three coax lines running along under the covers (visible at both ends and in the gap)
    for k in range(3):
        off = (k - 1) * 0.08
        pts = []
        for s in range(9):
            t = s / 8
            pts.append([a.x + (b.x - a.x) * t + dir_.y * off, 0.015, a.y + (b.y - a.y) * t - dir_.x * off])
        pts.insert(0, [a.x - dir_.x * 0.3 + dir_.y * off, 0.0, a.y - dir_.y * 0.3 - dir_.x * off])
        tr.add(K.m(K.tube(pts, 0.03, {'seg': 36, 'radial': 6}), rubT))
    # crew cable: van rear -> hut door, snaking over the gravel
    snake = [[45.7, 0.03, -3.0], [46.2, 0.02, -4.4], [45.4, 0.02, -5.0], [43.9, 0.02, -4.97], [42.8, 0.02, -4.93], [41.8, 0.02, -4.95], [40.4, 0.02, -4.9], [40.1, 0.02, -4.3], [39.98, 0.02, -3.8], [39.8, 0.13, -3.5]]
    tr.add(K.m(K.tube(snake, 0.022, {'seg': 60, 'radial': 5}), K.mat(game, 'rubber', '#E3662B', {'rough': 0.6})))
    root.add(tr)

    # ---- beyond the fence: utility wires between the poles (yard_utility_pole userData.wires, placed as yard.gd
    # places the poles: pos + rotY, the default height 9.2 -> wires at AY + 0.2 = 8.85 m)
    wireMat = K.mat(game, 'rubber', '#241E2C', {'rough': 0.6})
    polesAt = [[37.5, -24.5, 0.05, False], [47.0, -24.5, 0, True], [56.5, -18.5, PI / 2 - 0.5, False], [57.0, -6.0, PI / 2, False], [57.0, 6.5, PI / 2, True]]
    AY = 9.2 - 0.55
    wiresLocal = [[-1.0, AY + 0.2, 0], [-0.35, AY + 0.2, 0], [1.0, AY + 0.2, 0]]

    def world(p, local):
        x, z, r = p[0], p[1], p[2]
        return THREE.Vector3(*local).applyAxisAngle(THREE.Vector3(0, 1, 0), r).add(THREE.Vector3(x, 0, z))
    wires = _loose('yd_wires')
    for i in range(len(polesAt) - 1):
        pa, pb = polesAt[i], polesAt[i + 1]
        for k in range(3):
            A_, B_ = world(pa, wiresLocal[k]), world(pb, wiresLocal[k])
            pts = []
            for s in range(11):
                t = s / 10
                pts.append([A_.x + (B_.x - A_.x) * t, A_.y + (B_.y - A_.y) * t - math.sin(t * PI) * 0.75, A_.z + (B_.z - A_.z) * t])
            wires.add(K.m(K.tube(pts, 0.016, {'seg': 20, 'radial': 4}), wireMat, {'cast': False}))
    # service drop from the NE pole to the tower (feeds the transmitter)
    A_ = world(polesAt[1], wiresLocal[2])
    B_ = THREE.Vector3(46.2, 8.2, -13.2)
    pts = []
    for s in range(11):
        t = s / 10
        pts.append([A_.x + (B_.x - A_.x) * t, A_.y + (B_.y - A_.y) * t - math.sin(t * PI) * 1.1, A_.z + (B_.z - A_.z) * t])
    wires.add(K.m(K.tube(pts, 0.018, {'seg': 20, 'radial': 4}), wireMat, {'cast': False}))
    root.add(wires)
    return root


# ================================================================================================== export
def _assets():
    game = K.Game()
    return {
        'studio_a': lambda: buildStudioA(game),
        'studio_b': lambda: buildStudioB(game),
        'yard': lambda: buildYard(game),
    }


def build(save_blend=False, only=None):
    """Builds the three room GLBs into godot/assets/runtime/rooms_studios_yard/. Returns the written paths."""
    import props  # noqa: F401  (the yard's registered-prop helpers)
    from dalib import export as EX
    written = []
    for name, make in _assets().items():
        if only and name not in only:
            continue
        root = make()
        path = os.path.join(OUT_DIR, name + '.glb')
        blend = os.path.join(BLEND_DIR, name + '.blend') if save_blend else None
        EX.export_graph(root, path, root_name=root.name, save_blend=blend)
        written.append(path)
        print('[runtime/rooms_studios_yard] %s' % path)
    return written


if __name__ == '__main__':
    args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
    only = None
    if '--only' in args:
        only = args[args.index('--only') + 1].split(',')
    build(save_blend='--save-blend' in args, only=only)
