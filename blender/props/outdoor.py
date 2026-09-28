"""DEAD AIR — props: YARD & EXTERIOR (docs/PROPKIT.md, GDD §5.7 Transmitter Yard). Owner: outdoor prop artist.
Port of src/props/outdoor.js (same names, same numbers, same seeded randomness; see blender/README.md kit guide).
Shoot: node tools/propview/shoot.cjs category:outdoor category:outdoor_city --params "bg=%231B1E4A"   (night bg)
       scenes: scene:out_yard scene:out_street scene:out_tower_base scene:out_van_rear

  yard      (category 'outdoor')
            yd_tower (hero) · yd_hut (hero, nests hut_tubes + 2 feed CRTs) · yd_news_van (hero) · yd_sodium_post
            yd_fence · yd_fence_post · yd_fence_gate · yd_neon_wztv (wall) · yd_oil_drum · yd_drum_group · yd_crate
            yd_crate_stack · yd_film_cans · yd_stones · yd_puddle · yd_gravel_patch · yd_weeds
  skyline   (category 'outdoor_city') sky_building · sky_water_tower · sky_billboard · sky_moon · sky_skyline
            far backdrop: no colliders, low tris, canvas facades + additive lit windows, materials ignore fog
            (opts.fog = true to let the yard fog eat them)
  street    (category 'outdoor_city') st_sidewalk · st_street_lamp · st_car_70s · st_hydrant · st_mailbox · st_motel_sign
  runtime   setTowerBeacons(game, g, on, color) (1 Hz blink / rainbow after EE step 4) · setNeon(game, g, on)
            -> Godot runtime code (NOT ported here); they rely on userData.parts.beacons / neonPink / neonBlue /
            haloPink / haloBlue, which are kept.

TEXT GOTCHA: seen from the front (-z) the viewer's right is -x. decal() planes already read correctly; anything laid
out as geometry (neon strokes...) must run from +x to -x (see yd_neon_wztv's X(u) = -u).
VEHICLES (yd_news_van, st_car_70s): length along x, FRONT (cab) at -x; the van's open rear is at +x (GDD layout).
PLACEMENT CONVENTIONS (see each prop's meta.desc):
  floor props : kit default. Floor at y = 0, centered on x/z, FRONT = -z.
  'wall' tag  : origin = the point ON THE WALL under the prop's bottom edge (back at z = 0, prop extends toward -z).
                Place with pos = [x, bottomHeight, zOnWall] and rotY so local -z points away from the wall.
  'backdrop'  : skyline pieces (sky_*) have no colliders, low tris, rich textures; meant for 30..150 m away.
  Ground decals (yd_puddle, yd_gravel_patch, yd_stones, yd_weeds) have no colliders.
Light fixtures expose their glowing meshes as userData.parts.* (noMerge) so the engine can switch/flicker them;
opts.lit = false builds them dark.

Port notes (JS -> Python):
  * Material fields the JS sets after creation (fence mesh `alphaToCoverage = true`, billboard `emissiveMap =
    map`) are also recorded in the material spec (`extra`), so Godot's materials.gd can honour them.
  * sky_billboard embeds the sponsor logo cards with cards.js drawTo(); the Python drawTo needs the pre-rendered
    card PNG (dalib/cards/<id>.png or godot/assets/cards/<id>.png).
"""
import math
import random

import numpy as np

from dalib import kit as K
from dalib.kit import registerProp, registerScene, PAL, THREE
from dalib.mathutils3 import JSObj, js_round, js_str, js_to_fixed, js_sign, clamp, lerp
from dalib.rng import mulberry32

TAU = math.pi * 2
UP = THREE.Vector3(0, 1, 0)
CAT = 'outdoor'


# =================================================================================================== helpers
_geo = {}


def cg(key, make):
    g = _geo.get(key)
    if g is None:
        g = make()
        _geo[key] = g
    return g


def v3(a):
    return THREE.Vector3(a[0], a[1], a[2])


# tinted copy (kit geometries are cached/shared: always clone before tinting)
def tc(geo, color):
    return K.tint(geo.clone(), color)


# tinted mesh shortcut
def tm(geo, mat, color=None, o=None):
    return K.m(tc(geo, color) if color else geo, mat, o)


def hexMul(hex_, k):
    return '#' + THREE.Color(hex_).multiplyScalar(k).getHexString()


def hexMix(a, b, t):
    return '#' + THREE.Color(a).lerp(THREE.Color(b), t).getHexString()


# transformed copy of a geometry: { pos, rot:[x,y,z], quat, scale }
def xf(geo, o=None):
    o = o or {}
    g = geo.clone()
    q = o.get('quat') or THREE.Quaternion().setFromEuler(THREE.Euler(*(o.get('rot') or [0, 0, 0])))
    sc = o.get('scale')
    s = THREE.Vector3(1, 1, 1) if sc is None else THREE.Vector3(sc, sc, sc) if isinstance(sc, (int, float)) else v3(sc)
    g.applyMatrix4(THREE.Matrix4().compose(v3(o['pos']) if o.get('pos') else THREE.Vector3(), q, s))
    return g


# merges geometries with mixed attributes/indexing into one (position, normal, uv, color, index)
def mergeList(geos):
    lst = []
    for g0 in geos:
        if g0 is None:
            continue
        g = THREE.BufferGeometry()
        n = g0.attributes.position.count
        if not g0.attributes.normal:
            g0.computeVertexNormals()
        g.setAttribute('position', g0.attributes.position)
        g.setAttribute('normal', g0.attributes.normal)
        g.setAttribute('uv', g0.attributes.uv or THREE.BufferAttribute(np.zeros((n, 2)), 2))
        g.setAttribute('color', g0.attributes.color or THREE.BufferAttribute(np.ones((n, 3)), 3))
        g.setIndex(g0.index if g0.index is not None else list(range(n)))
        lst.append(g)
    return THREE.mergeGeometries(lst, False)


# 44-tri chamfered box (flat bevels read as soft edges at small/medium sizes). UVs 0..1 per face.
def cbox(w, h, d, c=0.006):
    def make():
        hx, hy, hz = w / 2, h / 2, d / 2
        cc = min(c, hx * 0.45, hy * 0.45, hz * 0.45)
        pts = []
        for sx in (-1, 1):
            for sy in (-1, 1):
                for sz in (-1, 1):
                    pts.extend([THREE.Vector3(sx * hx, sy * (hy - cc), sz * (hz - cc)),
                                THREE.Vector3(sx * (hx - cc), sy * hy, sz * (hz - cc)),
                                THREE.Vector3(sx * (hx - cc), sy * (hy - cc), sz * hz)])
        g = THREE.ConvexGeometry(pts)
        p = np.asarray(g.attributes.position, dtype=np.float64)
        n = np.asarray(g.attributes.normal, dtype=np.float64)
        uv = np.zeros((len(p), 2))
        for i in range(len(p)):
            nx, ny, nz = n[i, 0], n[i, 1], n[i, 2]
            ax, ay, az = abs(nx), abs(ny), abs(nz)
            x, y, z = p[i, 0] / w + 0.5, p[i, 1] / h + 0.5, p[i, 2] / d + 0.5
            if az >= ax and az >= ay:
                u = 1 - x if nz < 0 else x
                v = y
            elif ax >= ay:
                u = 1 - z if nx > 0 else z
                v = y
            else:
                u = x
                v = 1 - z if ny > 0 else z
            uv[i, 0] = u
            uv[i, 1] = v
        g.setAttribute('uv', THREE.BufferAttribute(uv, 2))
        return g
    return cg('cbox|%s|%s|%s|%s' % (js_to_fixed(w, 4), js_to_fixed(h, 4), js_to_fixed(d, 4), js_str(c)), make)


# basis that maps +y to (b - a) and +z toward `nrm` (projected), origin at a
def basis(a, b, nrm=None):
    A, B = v3(a), v3(b)
    dir_ = B.clone().sub(A)
    ln = dir_.length()
    dir_.normalize()
    z = v3(nrm) if nrm is not None else THREE.Vector3(0, 0, 1)
    z.addScaledVector(dir_, -z.dot(dir_))
    if z.lengthSq() < 1e-6:
        z = THREE.Vector3(1, 0, 0.3)
        z.addScaledVector(dir_, -z.dot(dir_))
    z.normalize()
    x = THREE.Vector3().crossVectors(dir_, z)
    return {'m': THREE.Matrix4().makeBasis(x, dir_, z).setPosition(A), 'len': ln}


# flat bar / beam from a to b (w across, d thick along nrm), baked into a geometry
def beamGeo(w, d, a, b, nrm, c=0.006):
    bs = basis(a, b, nrm)
    m, ln = bs['m'], bs['len']
    g = cbox(w, ln, d, c).clone()
    g.translate(0, ln / 2, 0)
    g.applyMatrix4(m)
    return g


# open (or capped) round pipe from a to b, baked
def pipeGeo(r, a, b, radial=8, caps=False, rb=None):
    rb = r if rb is None else rb
    bs = basis(a, b)
    m, ln = bs['m'], bs['len']
    g = THREE.CylinderGeometry(r, rb, ln, radial, 1, not caps)
    g.translate(0, ln / 2, 0)
    g.applyMatrix4(m)
    return g


# any +y-growing geometry (cyl/lathe, base at 0) placed from a toward b
def alongGeo(geo, a, b, nrm=None):
    m = basis(a, b, nrm)['m']
    return geo.clone().applyMatrix4(m)


# mesh with its local +y pointing from a to b
def span(geo, mat, a, b):
    A, B = v3(a), v3(b)
    msh = K.m(geo, mat)
    msh.position.copy(A)
    msh.quaternion.setFromUnitVectors(UP, B.sub(A).normalize())
    return msh


def rod(r, a, b, mat, o=None):
    o = o or {}
    ln = v3(a).distanceTo(v3(b))
    g = K.cyl(r, o['rb'] if o.get('rb') is not None else r, ln,
              {'seg': o['seg'] if o.get('seg') is not None else 10,
               'bevel': o['bevel'] if o.get('bevel') is not None else min(0.004, r * 0.4)})
    return span(tc(g, o['color']) if o.get('color') else g, mat, a, b)


def ring(r, n, y=0, a0=0, a1=TAU, closed=True):
    pts = []
    cnt = n if closed else n + 1
    for i in range(cnt):
        a = a0 + (i / n) * (a1 - a0)
        pts.append([math.sin(a) * r, y, math.cos(a) * r])
    return pts


def puck(r, h, round_=0.02, seg=24):
    return K.lathe([[0, 0], [r, 0], [r, h], [0, h]], {'round': min(round_, h / 2 - 1e-3, r / 2), 'seg': seg, 'steps': 2})


# lathe with UVs u = angle, v = y / vh (so painted bands/labels line up with the profile heights)
def latheY(profile, seg=24, vh=None):
    g = THREE.LatheGeometry([THREE.Vector2(max(0, x), y) for x, y in profile], seg)
    p, uv = g.attributes.position, g.attributes.uv
    top = vh if vh is not None else max(q[1] for q in profile)
    for i in range(p.count):
        uv.setY(i, p.getY(i) / top)
    return g


# flat decal facing -z (reads correctly from the front); rect = [u0, v0, u1, v1]
def decal(w, h, rect=None):
    g = THREE.PlaneGeometry(w, h)
    g.rotateY(math.pi)
    if rect:
        K.uvRect(g, *rect)
    return g


# flat decal facing +y (ground), rect as above; u along +x, v along -z
def groundDecal(w, d, rect=None):
    g = THREE.PlaneGeometry(w, d)
    g.rotateX(-math.pi / 2)
    if rect:
        K.uvRect(g, *rect)
    return g


# soft blurred glow card texture of polylines (for neon halos): strokes in [-1,1] units of the card
def haloTex(key, strokes, o=None):
    o = o or {}
    w, h = o.get('w', 256), o.get('h', 128)
    blur, width, circles = o.get('blur', 10), o.get('width', 14), o.get('circles', [])

    def draw(ctx, *_):
        ctx.fillStyle = '#000'
        ctx.fillRect(0, 0, w, h)
        ctx.filter = 'blur(%spx)' % js_str(blur)
        ctx.strokeStyle = '#fff'
        ctx.lineWidth = width
        ctx.lineCap = 'round'
        ctx.lineJoin = 'round'
        for st in strokes:
            ctx.beginPath()
            for j, (x, y) in enumerate(st):
                px, py = (x * 0.5 + 0.5) * w, (0.5 - y * 0.5) * h
                if j:
                    ctx.lineTo(px, py)
                else:
                    ctx.moveTo(px, py)
            ctx.stroke()
        for cx, cy, r in circles:
            ctx.beginPath()
            ctx.arc((cx * 0.5 + 0.5) * w, (0.5 - cy * 0.5) * h, r * w * 0.5, 0, TAU)
            ctx.stroke()
        ctx.filter = 'none'
    return K.tex.canvas('out_halo|%s' % key, w, h, draw, {'repeat': False})


# transparent stencil/decal atlas painter: cells drawn by fn(ctx, x, y, w, h, i)
def atlasTex(key, w, h, draw, fonts=True):
    return K.tex.canvas('out_atlas|%s' % key, w, h, draw, {'repeat': False, 'fonts': fonts})


def font(ctx, px, face='Bungee'):
    ctx.font = '%spx "%s", "Arial Black", sans-serif' % (js_str(px), face)


def fitText(ctx, text, maxW, px, face='Bungee'):
    font(ctx, px, face)
    while ctx.measureText(text).width > maxW and px > 6:
        px *= 0.94
        font(ctx, px, face)
    return px


# rough spray-paint stencil: text with gaps (stencil bridges) and soft overspray
def stencilText(ctx, text, x, y, px, color, face='Bungee', rand=random.random):
    ctx.save()
    font(ctx, px, face)
    ctx.textAlign = 'center'
    ctx.textBaseline = 'middle'
    ctx.fillStyle = color
    ctx.globalAlpha = 0.18
    ctx.filter = 'blur(2px)'
    ctx.fillText(text, x, y)
    ctx.filter = 'none'
    ctx.globalAlpha = 0.92
    ctx.fillText(text, x, y)
    # stencil bridges + chips
    ctx.globalCompositeOperation = 'destination-out'
    tw = ctx.measureText(text).width
    for i in range(len(text)):
        cx = x - tw / 2 + (i + 0.5) * (tw / len(text))
        ctx.fillRect(cx - px * 0.03, y - px * 0.55, px * 0.06, px * 0.22)
    for i in range(40):
        ctx.globalAlpha = 0.3 + rand() * 0.6
        ctx.beginPath()
        ctx.arc(x + (rand() - 0.5) * tw, y + (rand() - 0.5) * px, 0.5 + rand() * 2.2, 0, TAU)
        ctx.fill()
    ctx.restore()


def grime(ctx, w, h, rand, n=40, color='#2A1E14', alpha=0.08):
    ctx.save()
    for i in range(n):
        ctx.globalAlpha = alpha * (0.4 + rand())
        ctx.fillStyle = color
        ctx.beginPath()
        ctx.ellipse(rand() * w, rand() * h, 4 + rand() * 30, 3 + rand() * 18, rand() * 3, 0, TAU)
        ctx.fill()
    ctx.restore()


def rustStreaks(ctx, x0, y0, w, h, rand, n=10, color='#8A4A22'):
    ctx.save()
    for i in range(n):
        x, ln, wd = x0 + rand() * w, h * (0.2 + rand() * 0.8), 1 + rand() * 4
        gr = ctx.createLinearGradient(0, y0, 0, y0 + ln)
        gr.addColorStop(0, color)
        gr.addColorStop(1, 'rgba(0,0,0,0)')
        ctx.globalAlpha = 0.25 + rand() * 0.35
        ctx.fillStyle = gr
        ctx.fillRect(x, y0, wd, ln)
    ctx.restore()


# planar box-projected wood UVs with a per-plank offset (variation), grain along the plank length
def woodUV(geo, perM, alongX, rand=None):
    g = K.uvBox(geo, perM, {'swap': alongX})
    du = rand() * 7 if rand else 0
    dv = rand() * 7 if rand else 0
    uv = g.attributes.uv
    a = np.asarray(uv, dtype=np.float64)
    uv[:, 0] = a[:, 0] + du
    uv[:, 1] = a[:, 1] + dv
    return g


# lumpy stone: subdivided icosahedron, noise-displaced, flattened
def stoneGeo(r, seed, flat=0.55):
    rnd = mulberry32(seed * 131 + 7)
    g = THREE.IcosahedronGeometry(r, 1)
    p = g.attributes.position
    ph = [rnd() * 6, rnd() * 6, rnd() * 6]
    vtx = THREE.Vector3()
    seen = {}
    for i in range(p.count):
        vtx.fromBufferAttribute(p, i)
        k = '%s,%s,%s' % (js_to_fixed(vtx.x, 4), js_to_fixed(vtx.y, 4), js_to_fixed(vtx.z, 4))
        s = seen.get(k)
        if s is None:
            n = vtx.clone().normalize()
            s = 1 + 0.18 * math.sin(n.x * 3.1 + ph[0]) * math.cos(n.z * 2.7 + ph[1]) + \
                0.1 * math.sin(n.y * 4.3 + ph[2]) + (rnd() - 0.5) * 0.08
            seen[k] = s
        p.setXYZ(i, vtx.x * s, vtx.y * s * flat, vtx.z * s * (0.8 + 0.2 * math.cos(ph[0])))
    g.computeVertexNormals()
    K.weldNormals(g)
    return g


# smooth random blob outline (closed), radius ~r, n points
def blob(r, seed, n=28, wob=0.22, sx=1, sz=1):
    rnd = mulberry32(seed * 977 + 3)
    a1, a2, a3 = rnd() * 6, rnd() * 6, rnd() * 6
    pts = []
    for i in range(n):
        a = (i / n) * TAU
        k = 1 + wob * (0.55 * math.sin(a * 2 + a1) + 0.3 * math.sin(a * 3 + a2) + 0.15 * math.sin(a * 5 + a3))
        pts.append(THREE.Vector2(math.cos(a) * r * k * sx, math.sin(a) * r * k * sz))
    return pts


# shared colors
C = JSObj(
    red='#D8402F', white='#F2EEE4', blue=PAL.wztvBlue, cream=PAL.cream, gold=PAL.harvestGold, orange=PAL.burntOrange,
    avocado=PAL.avocado, choc=PAL.chocolate, galv='#AEB5BE', galvDark='#7E8792', concrete='#B9B2A6',
    concreteDark='#8E877D', rubber='#2A2430', ink='#241A2E', pine='#C99A5E', sodium=PAL.sodium, pink=PAL.neonPink,
    plum=PAL.plum,
)


def _floor(x):
    return int(math.floor(x))


# =================================================================================================== OIL DRUMS
DRUM_STYLES = {
    'blue': {'c': '#2F5BD3', 'label': 'wztv', 'ink': '#F4F1E8'},
    'red': {'c': '#C8382E', 'label': 'flammable', 'ink': '#F4F1E8'},
    'yellow': {'c': '#E8A92E', 'label': 'caution', 'ink': '#2A1D3A'},
    'green': {'c': '#6E8A3A', 'label': 'diesel', 'ink': '#F4F1E8'},
    'orange': {'c': '#E3662B', 'label': 'wztv', 'ink': '#2A1D3A'},
    'black': {'c': '#3A3444', 'label': 'oil', 'ink': '#E8A92E'},
}
DR, DH = 0.29, 0.88


def drumTex(style):
    st = DRUM_STYLES.get(style) or DRUM_STYLES['blue']

    def draw(ctx, w, h, rand):
        sideH = h * 0.8  # v 0..0.8 = side (y/H), v 0.8..1 = lid tile (canvas top 64 px)
        # side (canvas y is flipped: v=1 at the top of the canvas)
        y0 = h - sideH
        ctx.fillStyle = st['c']
        ctx.fillRect(0, y0, w, sideH)
        for i in range(26):
            ctx.globalAlpha = 0.08 + rand() * 0.08
            ctx.fillStyle = '#000' if rand() < 0.5 else '#fff'
            ctx.fillRect(rand() * w, y0, 2 + rand() * 18, sideH)
        ctx.globalAlpha = 1
        # label panel on the front (u ~ 0.25 faces -z with the lathe seam at +z... see drumParts: rotated so u=0.5
        # is front)
        cx, cy = w * 0.5, y0 + sideH * 0.5
        ctx.save()
        if st['label'] == 'wztv':
            ctx.fillStyle = st['ink']
            ctx.globalAlpha = 0.95
            ctx.beginPath()
            ctx.arc(cx, cy - 40, 30, 0, TAU)
            ctx.fill()
            ctx.fillStyle = st['c']
            font(ctx, 30)
            ctx.textAlign = 'center'
            ctx.textBaseline = 'middle'
            ctx.fillText('13', cx, cy - 38)
            stencilText(ctx, 'WZTV', cx, cy + 10, 34, st['ink'], 'Bungee', rand)
            stencilText(ctx, 'PROPERTY', cx, cy + 42, 18, st['ink'], 'Bungee', rand)
        elif st['label'] == 'flammable':
            ctx.translate(cx, cy - 8)
            ctx.rotate(math.pi / 4)
            ctx.fillStyle = '#F4F1E8'
            ctx.fillRect(-44, -44, 88, 88)
            ctx.fillStyle = '#C8382E'
            ctx.fillRect(-38, -38, 76, 76)
            ctx.rotate(-math.pi / 4)
            ctx.fillStyle = '#F4F1E8'
            ctx.beginPath()
            ctx.moveTo(0, -30)
            ctx.bezierCurveTo(18, -8, 16, 8, 0, 18)
            ctx.bezierCurveTo(-16, 8, -14, -6, -4, -14)
            ctx.bezierCurveTo(-4, -2, 4, -2, 0, -30)
            ctx.fill()
            ctx.setTransform(1, 0, 0, 1, 0, 0)
            stencilText(ctx, 'FLAMMABLE', cx, cy + 62, 20, st['ink'], 'Bungee', rand)
        elif st['label'] == 'caution':
            for i in range(-6, 7):
                ctx.fillStyle = '#2A1D3A'
                ctx.beginPath()
                ctx.moveTo(cx + i * 22, y0 + 18)
                ctx.lineTo(cx + i * 22 + 11, y0 + 18)
                ctx.lineTo(cx + i * 22 + 1, y0 + 34)
                ctx.lineTo(cx + i * 22 - 10, y0 + 34)
                ctx.fill()
            stencilText(ctx, 'CAUTION', cx, cy - 4, 34, st['ink'], 'Bungee', rand)
            stencilText(ctx, 'STAGE FOG', cx, cy + 30, 18, st['ink'], 'Bungee', rand)
        elif st['label'] == 'diesel':
            stencilText(ctx, 'DIESEL', cx, cy - 12, 38, st['ink'], 'Bungee', rand)
            stencilText(ctx, 'GENERATOR 2', cx, cy + 24, 17, st['ink'], 'Bungee', rand)
        else:
            stencilText(ctx, 'MOTOR OIL', cx, cy - 8, 28, st['ink'], 'Bungee', rand)
            stencilText(ctx, 'SAE 30', cx, cy + 24, 18, st['ink'], 'Bungee', rand)
        ctx.restore()
        # small back stencil
        stencilText(ctx, '55 GAL', w * 0.02 + 40, cy + 60, 14, st['ink'], 'Bungee', rand)
        stencilText(ctx, '55 GAL', w * 0.98 - 40, cy + 60, 14, st['ink'], 'Bungee', rand)

        # rust at the chimes/hoops (y/H 0.0, 0.33, 0.67, 1.0)
        def vy(t):
            return h - t * sideH
        rustStreaks(ctx, 0, vy(1) + 2, w, sideH * 0.35, rand, 26, '#7A3A1A')
        rustStreaks(ctx, 0, vy(0.67), w, sideH * 0.2, rand, 12, '#7A3A1A')
        rustStreaks(ctx, 0, vy(0.33), w, sideH * 0.2, rand, 12, '#7A3A1A')
        ctx.save()
        ctx.globalAlpha = 0.5
        ctx.fillStyle = '#5A3420'
        ctx.fillRect(0, vy(0.03), w, sideH * 0.03)
        ctx.restore()
        grime(ctx, w, sideH, rand, 30, '#20141C', 0.06)
        # lid tile (top 64 px): paint with concentric pressing rings
        ctx.fillStyle = st['c']
        ctx.fillRect(0, 0, w, h - sideH)
        ctx.globalAlpha = 0.15
        ctx.fillStyle = '#000'
        ctx.fillRect(0, 0, w, 4)
        ctx.globalAlpha = 1
        grime(ctx, w, h - sideH, rand, 10, '#20141C', 0.1)
    return K.tex.canvas('out_drum|%s' % style, 512, 320, draw)


# adds one drum's geometry into the geos map under a transform (so groups bake/merge once)
def drumParts(out, style, xform, seed=1, o=None):
    o = o or {}
    rnd = mulberry32(seed * 91 + 5)
    prof = [[0, 0.012], [0.262, 0.006], [0.279, 0.0], [0.291, 0.012], [0.292, 0.028], [0.284, 0.036],
            [0.284, 0.272], [0.294, 0.283], [0.294, 0.301], [0.284, 0.312],
            [0.284, 0.566], [0.294, 0.577], [0.294, 0.595], [0.284, 0.606],
            [0.284, 0.846], [0.291, 0.853], [0.293, 0.868], [0.284, 0.88], [0.272, 0.875], [0.266, 0.862]]
    side = latheY(prof, 30, DH / 0.8)
    # dents (seeded): push vertices inward near a random point on the side
    p = side.attributes.position
    dents = []
    for i in range(o['dents'] if o.get('dents') is not None else 2):
        dents.append([rnd() * TAU, 0.15 + rnd() * 0.6, 0.02 + rnd() * 0.025])
    for i in range(p.count):
        x, y, z = p.getX(i), p.getY(i), p.getZ(i)
        rr = math.hypot(x, z)
        if rr < 0.2:
            continue
        a = math.atan2(x, z)
        k = 0
        for da, dy, dd in dents:
            dA = abs(a - da)
            dA = min(dA, TAU - dA)
            d2 = (dA * DR) ** 2 + (y - dy) ** 2
            k += dd * math.exp(-d2 / 0.006)
        if k > 0:
            s = (rr - k) / rr
            p.setX(i, x * s)
            p.setZ(i, z * s)
    side.computeVertexNormals()
    K.weldNormals(side)
    # lid: flat disc with planar UVs into the lid tile (v 0.8..1)
    lid = THREE.CircleGeometry(0.268, 30)
    lid.rotateX(-math.pi / 2)
    lid.translate(0, 0.862, 0)
    luv, lp = lid.attributes.uv, lid.attributes.position
    for i in range(luv.count):
        luv.setXY(i, 0.1 + (lp.getX(i) / 0.6 + 0.5) * 0.3, 0.82 + (lp.getZ(i) / 0.6 + 0.5) * 0.16)
    # rotate so the label (u = 0.5) faces -z: lathe u=0 is at +z (sin/cos), u=0.5 at -z already
    out['body'].extend([xf(side, xform), xf(lid, xform)])
    # bungs (2" and 3/4") + a pressed ring on the lid
    out['metal'].append(xf(K.cyl(0.035, 0.038, 0.018, {'seg': 12, 'bevel': 0.005}).clone().translate(0.16, 0.862, -0.06),
                           xform))
    out['metal'].append(xf(K.cyl(0.018, 0.02, 0.014, {'seg': 10, 'bevel': 0.004}).clone().translate(-0.17, 0.862, 0.08),
                           xform))
    out['body'].append(xf(THREE.TorusGeometry(0.2, 0.006, 4, 30).rotateX(math.pi / 2).translate(0, 0.863, 0), xform))


def drumMats(game, styles):
    body = {}
    for s in styles:
        body[s] = K.mat(game, 'lacquer', '#ffffff', {'map': drumTex(s), 'rough': 0.44})
    return {'body': body, 'metal': K.mat(game, 'metal', '#9AA0A8')}


def drumXform(pos, rotY=0, tipped=False):
    if not tipped:
        return {'pos': pos, 'rot': [0, rotY, 0]}
    # lying on its side along local x (rolled a bit so the label shows)
    q = THREE.Quaternion().setFromEuler(THREE.Euler(0, rotY, 0))
    q.multiply(THREE.Quaternion().setFromEuler(THREE.Euler(0.35, 0, math.pi / 2)))
    off = THREE.Vector3(0, DH / 2, 0).applyQuaternion(q)
    return {'pos': [pos[0] - off.x, 0.293, pos[2] - off.z], 'quat': q}


def addDrum(g, M, style, xform, seed=1, o=None):
    out = {'body': [], 'metal': []}
    drumParts(out, style, xform, seed, o)
    g.add(K.m(mergeList(out['body']), M['body'][style]))
    g.add(K.m(mergeList(out['metal']), M['metal']))


def _oil_drum(game, opts=None):
    opts = opts or {}
    g = K.prop('yd_oil_drum')
    style = opts.get('color') if DRUM_STYLES.get(opts.get('color')) else 'blue'
    M = drumMats(game, [style])
    tipped = bool(opts.get('tipped'))
    addDrum(g, M, style, drumXform([0, 0, 0], 0, tipped), opts['seed'] if opts.get('seed') is not None else 1,
            {'dents': opts.get('dents')})
    g.userData.colliders = [{'min': [-DH / 2, 0, -DR], 'max': [DH / 2, DR * 2, DR]}] if tipped else \
        [{'min': [-DR, 0, -DR], 'max': [DR, DH, DR]}]
    return K.finish(game, g)


registerProp('yd_oil_drum', _oil_drum,
             {'category': CAT, 'tags': ['yard', 'drum', 'clutter'], 'size': [0.59, 0.88, 0.59],
              'desc': '55-gal steel drum, painted + stenciled, dents and rust (opts.color blue|red|yellow|green|orange|'
                      'black, opts.tipped, opts.seed)'})


def _drum_group(game, opts=None):
    opts = opts or {}
    g = K.prop('yd_drum_group')
    set_ = ['red', 'yellow', 'black', 'red'] if opts.get('set') == 'b' else ['blue', 'green', 'orange', 'blue']
    M = drumMats(game, list(dict.fromkeys(set_)))
    # wooden pallet under the two standing drums
    wood = K.mat(game, 'teak', '#ffffff', {'map': K.tex.wood('#A87A48', {'dark': 0.4, 'wear': 0.4})})
    rnd = mulberry32(51)
    PW, PD, px, pz = 1.2, 1.0, -0.18, 0.08
    for i in range(7):
        g.add(K.m(woodUV(cbox(PW, 0.022, 0.12, 0.004), 1.4, True, rnd), wood,
                  {'pos': [px, 0.133, pz - PD / 2 + 0.06 + i * ((PD - 0.12) / 6)]}))
    for s in (-1, 0, 1):
        g.add(K.m(woodUV(cbox(0.1, 0.1, PD, 0.006), 1.4, False, rnd), wood, {'pos': [px + s * (PW / 2 - 0.05), 0.072, pz]}))
    for i in range(3):
        g.add(K.m(woodUV(cbox(PW, 0.022, 0.1, 0.004), 1.4, True, rnd), wood,
                  {'pos': [px, 0.011, pz - PD / 2 + 0.05 + i * ((PD - 0.1) / 2)]}))
    top = 0.144
    addDrum(g, M, set_[0], {'pos': [px - 0.3, top, pz + 0.18], 'rot': [0, 0.4, 0]}, 3)
    addDrum(g, M, set_[1], {'pos': [px + 0.3, top, pz + 0.16], 'rot': [0, -1.1, 0]}, 4)
    addDrum(g, M, set_[2], {'pos': [px + 0.05, top, pz - 0.28], 'rot': [0, 2.6, 0]}, 5, {'dents': 1})
    # one tipped over in front, rolled away
    addDrum(g, M, set_[3], drumXform([0.55, 0, -0.62], -0.5, True), 6, {'dents': 3})
    g.userData.colliders = [
        {'min': [px - PW / 2, 0, pz - PD / 2], 'max': [px + PW / 2, top + DH, pz + PD / 2]},
        {'min': [0.05, 0, -1.05], 'max': [1.05, DR * 2, -0.2]},
    ]
    return K.finish(game, g)


registerProp('yd_drum_group', _drum_group,
             {'category': CAT, 'tags': ['yard', 'drum', 'clutter', 'group'], 'size': [1.9, 1.03, 1.6],
              'desc': 'three drums on a pallet + one tipped over (opts.set a|b)'})

# =================================================================================================== CRATES
CRATE_SIZES = {'lg': [1.2, 0.9, 0.9], 'md': [0.9, 0.7, 0.7], 'sm': [0.6, 0.45, 0.5], 'long': [1.8, 0.5, 0.6]}


def crateStencils():
    # 4x2 atlas of transparent stencils (256x128 each)
    def draw(ctx, W, H, _rand):
        rand = mulberry32(77)

        def cell(i, f):
            ctx.save()
            ctx.translate((i % 4) * 256, _floor(i / 4) * 128)
            f()
            ctx.restore()
        ink, red, blue = '#2A1D2A', '#B8332A', '#2A4AA8'

        def c0():
            stencilText(ctx, 'WZTV-13', 128, 52, 46, ink, 'Bungee', rand)
            stencilText(ctx, 'CHANNEL 13 · TRI-COUNTY', 128, 96, 15, ink, 'Bungee', rand)
        cell(0, c0)

        def c1():
            ctx.strokeStyle = red
            ctx.lineWidth = 6
            ctx.globalAlpha = 0.9
            ctx.strokeRect(22, 24, 212, 80)
            stencilText(ctx, 'FRAGILE', 128, 64, 42, red, 'Bungee', rand)
        cell(1, c1)

        def c2():
            ctx.fillStyle = ink
            ctx.globalAlpha = 0.9
            for x in (88, 168):
                ctx.beginPath()
                ctx.moveTo(x, 18)
                ctx.lineTo(x + 26, 50)
                ctx.lineTo(x + 10, 50)
                ctx.lineTo(x + 10, 84)
                ctx.lineTo(x - 10, 84)
                ctx.lineTo(x - 10, 50)
                ctx.lineTo(x - 26, 50)
                ctx.fill()
            stencilText(ctx, 'THIS SIDE UP', 128, 106, 17, ink, 'Bungee', rand)
        cell(2, c2)

        def c3():
            stencilText(ctx, 'FILM', 128, 44, 44, blue, 'Bungee', rand)
            stencilText(ctx, 'KEEP DRY · KEEP COOL', 128, 92, 15, blue, 'Bungee', rand)
        cell(3, c3)

        def c4():
            # wine-glass "fragile" icon
            ctx.strokeStyle = ink
            ctx.lineWidth = 7
            ctx.globalAlpha = 0.9
            ctx.lineCap = 'round'
            ctx.beginPath()
            ctx.moveTo(100, 20)
            ctx.quadraticCurveTo(100, 64, 128, 66)
            ctx.quadraticCurveTo(156, 64, 156, 20)
            ctx.stroke()
            ctx.beginPath()
            ctx.moveTo(128, 66)
            ctx.lineTo(128, 100)
            ctx.moveTo(108, 104)
            ctx.lineTo(148, 104)
            ctx.stroke()
        cell(4, c4)

        def c5():
            stencilText(ctx, 'NO. 1313', 128, 50, 34, ink, 'Bungee', rand)
            stencilText(ctx, 'STUDIO B · PROPS', 128, 92, 16, ink, 'Bungee', rand)
        cell(5, c5)

        def c6():
            stencilText(ctx, 'HANDLE', 128, 44, 34, red, 'Bungee', rand)
            stencilText(ctx, 'WITH CARE', 128, 88, 30, red, 'Bungee', rand)
        cell(6, c6)

        def c7():
            # shipping label (paper)
            ctx.globalAlpha = 1
            ctx.fillStyle = '#EFE4C8'
            ctx.fillRect(40, 14, 176, 100)
            ctx.fillStyle = '#E3662B'
            ctx.fillRect(40, 14, 176, 20)
            ctx.fillStyle = '#F4F1E8'
            font(ctx, 13)
            ctx.textAlign = 'center'
            ctx.fillText('RAILWAY EXPRESS', 128, 29)
            ctx.fillStyle = '#3A2A30'
            font(ctx, 12, 'Titan One')
            ctx.textAlign = 'left'
            ctx.fillText('TO: WZTV CH.13', 50, 54)
            ctx.fillText('ATTN: B. VON STATIC', 50, 74)
            ctx.fillText('ETERNA-VISION INC.', 50, 94)
            ctx.globalAlpha = 0.25
            ctx.fillStyle = '#6A4A2A'
            ctx.fillRect(40, 100, 176, 14)
        cell(7, c7)
    return atlasTex('crate_stencils', 1024, 256, draw)


def crateParts(g, M, size, xform, seed, stencils=None):
    W, H, D = size
    stencils = [0, 2, 1, 3] if stencils is None else stencils
    rnd = mulberry32(seed * 313 + 11)
    grp = THREE.Group()
    if xform.get('pos'):
        grp.position.fromArray(xform['pos'])
    if xform.get('rot'):
        grp.rotation.set(*xform['rot'])
    g.add(grp)
    T = 0.022  # board thickness
    woodCols = ['#FFFFFF', '#F2E6D6', '#FFF4E4', '#E8D8C4', '#F8EEDC']

    def wc():
        return woodCols[_floor(rnd() * len(woodCols))]
    # dark core (reads through the gaps)
    grp.add(tm(cbox(W - 0.03, H - 0.03, D - 0.03, 0.01), M['core'], None, {'pos': [0, H / 2, 0]}))
    # sheathing planks: horizontal on the 4 sides, along x on the top
    nP = max(2, js_round(H / 0.16))
    gap, ph = 0.012, None
    ph = (H - 0.02 - gap * (nP - 1)) / nP
    for i in range(nP):
        y = 0.01 + ph / 2 + i * (ph + gap)
        for s in (-1, 1):
            grp.add(tm(woodUV(cbox(W - 0.004, ph, T, 0.005), 1.3, True, rnd), M['wood'], wc(),
                       {'pos': [0, y, s * (D / 2 - T / 2)]}))
            grp.add(tm(woodUV(cbox(T, ph, D - 2 * T - 0.004, 0.005), 1.3, True, rnd), M['wood'], wc(),
                       {'pos': [s * (W / 2 - T / 2), y, 0]}))
    nT = max(2, js_round(D / 0.15))
    tp = (D - gap * (nT - 1)) / nT
    for i in range(nT):
        grp.add(tm(woodUV(cbox(W, T, tp - 0.002, 0.005), 1.3, True, rnd), M['wood'], wc(),
                   {'pos': [0, H - T / 2 + 0.002, -D / 2 + tp / 2 + i * (tp + gap)]}))
    # cleats (frame boards) on front/back and sides, a diagonal brace on the long faces
    cw, ct = 0.075, 0.02
    for s in (-1, 1):
        z = s * (D / 2 + ct / 2 - 0.002)
        for x in (-1, 1):
            grp.add(tm(woodUV(cbox(cw, H - 0.004, ct, 0.006), 1.3, False, rnd), M['wood'], wc(),
                       {'pos': [x * (W / 2 - cw / 2), H / 2, z]}))
        for y in (cw / 2 + 0.002, H - cw / 2 - 0.002):
            grp.add(tm(woodUV(cbox(W - 2 * cw, cw, ct, 0.006), 1.3, True, rnd), M['wood'], wc(), {'pos': [0, y, z]}))
        if W > 0.8:
            a, b = [-W / 2 + cw, cw, z], [W / 2 - cw, H - cw, z]
            grp.add(tm(K.uvBox(beamGeo(cw, ct, a, b, [0, 0, s], 0.006), 1.3, {'swap': False}), M['wood'], wc()))
        x = s * (W / 2 + ct / 2 - 0.002)
        for zz in (-1, 1):
            grp.add(tm(woodUV(cbox(ct, H - 0.004, cw, 0.006), 1.3, False, rnd), M['wood'], wc(),
                       {'pos': [x, H / 2, zz * (D / 2 - cw / 2 + 0.02)]}))
        for y in (cw / 2 + 0.002, H - cw / 2 - 0.002):
            grp.add(tm(woodUV(cbox(ct, cw, D - 2 * cw + 0.04, 0.006), 1.3, True, rnd), M['wood'], wc(),
                       {'pos': [x, y, 0]}))
    # steel corner caps on the top corners
    for sx in (-1, 1):
        for sz in (-1, 1):
            grp.add(K.m(cbox(0.07, 0.05, 0.07, 0.008), M['metal'],
                        {'pos': [sx * (W / 2 - 0.02), H - 0.02, sz * (D / 2 - 0.02)]}))

    # stencils: front (-z), right side (+x), back, top
    def cellR(i):
        return [(i % 4) / 4, 1 - (_floor(i / 4) + 1) / 2, (i % 4 + 1) / 4, 1 - _floor(i / 4) / 2]
    sw = min(W - 0.2, 0.62)
    sh = sw / 2
    f = grp
    f.add(K.m(decal(sw, sh, cellR(stencils[0])), M['sten'], {'pos': [rnd() * 0.06 - 0.03, H * 0.52, -D / 2 - ct - 0.004]}))
    ss = min(D - 0.18, 0.5)
    f.add(K.m(decal(ss, ss / 2, cellR(stencils[1])), M['sten'],
              {'pos': [W / 2 + ct + 0.004, H * 0.55, 0], 'rot': [0, -math.pi / 2, 0]}))
    f.add(K.m(decal(sw * 0.8, sw * 0.4, cellR(stencils[2])), M['sten'],
              {'pos': [0, H * 0.5, D / 2 + ct + 0.004], 'rot': [0, math.pi, 0]}))
    lab = K.m(groundDecal(0.34, 0.17, cellR(stencils[3] if len(stencils) > 3 and stencils[3] is not None else 7)),
              M['sten'], {'pos': [W * 0.18, H + 0.009, D * 0.1], 'rot': [0, 0.2, 0]})
    f.add(lab)


def crateMats(game):
    return {
        'wood': K.mat(game, 'teak', '#ffffff', {'map': K.tex.wood('#C99A5E', {'dark': 0.36, 'wear': 0.35})}),
        'core': K.mat(game, 'paint', '#3A2A22'),
        'metal': K.mat(game, 'metal', '#8A9098'),
        'sten': K.mat(game, 'paint', '#ffffff', {'map': crateStencils(), 'transparent': True, 'depthWrite': False}),
    }


def _js_index(arr, i):
    """arr[i] with JS semantics (undefined -> None for negative / fractional / out-of-range indices)."""
    if isinstance(i, float) and not i.is_integer():
        return None
    i = int(i)
    return arr[i] if 0 <= i < len(arr) else None


def _crate(game, opts=None):
    opts = opts or {}
    g = K.prop('yd_crate')
    size = CRATE_SIZES.get(opts.get('size')) or CRATE_SIZES['md']
    M = crateMats(game)
    seed = opts['seed'] if opts.get('seed') is not None else 1
    st = [3, 4, 1, 7] if opts.get('film') else _js_index([[0, 2, 1, 3], [5, 6, 0, 7], [0, 1, 2, 3]], math.fmod(seed, 3))
    crateParts(g, M, size, {}, seed, st)
    g.userData.colliders = [{'min': [-size[0] / 2 - 0.03, 0, -size[2] / 2 - 0.03],
                             'max': [size[0] / 2 + 0.03, size[1], size[2] / 2 + 0.03]}]
    return K.finish(game, g)


registerProp('yd_crate', _crate,
             {'category': CAT, 'tags': ['yard', 'crate', 'clutter'], 'size': [0.96, 0.7, 0.76],
              'desc': 'slatted pine shipping crate with cleats, steel corners, spray stencils (opts.size lg|md|sm|long, '
                      'opts.seed, opts.film)'})


def _crate_stack(game, opts=None):
    g = K.prop('yd_crate_stack')
    M = crateMats(game)
    lw, lh, ld = CRATE_SIZES['lg']
    mw, mh, md = CRATE_SIZES['md']
    sw, sh, sd = CRATE_SIZES['sm']
    crateParts(g, M, CRATE_SIZES['lg'], {'pos': [-0.25, 0, 0.1], 'rot': [0, 0.05, 0]}, 2, [0, 2, 1, 7])
    crateParts(g, M, CRATE_SIZES['md'], {'pos': [-0.3, lh + 0.003, 0.15], 'rot': [0, -0.18, 0]}, 3, [5, 6, 0, 3])
    crateParts(g, M, CRATE_SIZES['md'], {'pos': [0.72, 0, -0.05], 'rot': [0, 0.35, 0]}, 4, [3, 4, 1, 7])
    crateParts(g, M, CRATE_SIZES['sm'], {'pos': [0.62, mh + 0.003, 0.0], 'rot': [0, 0.1, 0]}, 5, [1, 0, 2, 3])
    g.userData.colliders = [
        {'min': [-0.25 - lw / 2 - 0.05, 0, 0.1 - ld / 2 - 0.05], 'max': [-0.25 + lw / 2 + 0.05, lh + mh, 0.1 + ld / 2 + 0.05]},
        {'min': [0.72 - 0.55, 0, -0.05 - 0.52], 'max': [0.72 + 0.55, mh + sh, -0.05 + 0.52]},
    ]
    return K.finish(game, g)


registerProp('yd_crate_stack', _crate_stack,
             {'category': CAT, 'tags': ['yard', 'crate', 'clutter', 'group'], 'size': [2.2, 1.6, 1.3],
              'desc': 'stack of four shipping crates (big + medium on top, medium + small beside)'})


# =================================================================================================== FILM CANS
def filmLabels():
    def draw(ctx, *_):
        rand = mulberry32(19)
        labels = [['PRECINCT 13', 'REEL 2 of 3'], ['SPOOKTACULAR', 'ep. 113 · MASTER'], ["HOOTIE'S", 'PUPPET HOUR 41'],
                  ['NEWS FILM', 'JUNE 1977'], ['DO NOT AIR!!', 'B.v.S.'], ['BOOGIE DOWN', 'SAT. 9PM'],
                  ['STATION ID', '1971 · COLOR'], ['SIGN-OFF', 'ANTHEM · 16mm']]
        for i, (a, b) in enumerate(labels):
            x, y = (i % 4) * 128, _floor(i / 4) * 128
            ctx.save()
            ctx.translate(x + 64, y + 64)
            ctx.rotate((rand() - 0.5) * 0.08)
            ctx.fillStyle = '#F6D84A' if i == 4 else '#EFE4C4'
            ctx.fillRect(-60, -24, 120, 48)
            ctx.globalAlpha = 0.18
            ctx.fillStyle = '#7A5A30'
            ctx.fillRect(-60, 16, 120, 8)
            ctx.fillRect(-60, -24, 4, 48)
            ctx.globalAlpha = 1
            ctx.fillStyle = '#C8201E' if i == 4 else '#2A2A6A'
            ctx.textAlign = 'center'
            ctx.textBaseline = 'middle'
            fitText(ctx, a, 108, 17, 'Titan One')
            ctx.fillText(a, 0, -8)
            fitText(ctx, b, 108, 12, 'Titan One')
            ctx.fillStyle = '#5A3A3A'
            ctx.fillText(b, 0, 12)
            ctx.restore()
    return atlasTex('film_labels', 512, 256, draw)


def reelTex():
    def draw(ctx, w, *_):
        ctx.fillStyle = '#000'
        ctx.clearRect(0, 0, w, w)
        c = w / 2
        # film pack (brown) + silver 3-spoke reel flange with holes
        ctx.fillStyle = '#5A3424'
        ctx.beginPath()
        ctx.arc(c, c, c * 0.8, 0, TAU)
        ctx.fill()
        ctx.strokeStyle = 'rgba(0,0,0,0.25)'
        ctx.lineWidth = 1
        r = c * 0.3
        while r < c * 0.8:
            ctx.beginPath()
            ctx.arc(c, c, r, 0, TAU)
            ctx.stroke()
            r += 3
        ctx.fillStyle = '#C8CDD4'
        ctx.beginPath()
        ctx.arc(c, c, c * 0.3, 0, TAU)
        ctx.fill()
        ctx.fillStyle = '#8A9098'
        ctx.beginPath()
        ctx.arc(c, c, c * 0.08, 0, TAU)
        ctx.fill()
    return K.tex.canvas('out_film_reel', 256, 256, draw, {'repeat': False})


def _film_cans(game, opts=None):
    opts = opts or {}
    g = K.prop('yd_film_cans')
    rnd = mulberry32((opts['seed'] if opts.get('seed') is not None else 1) * 7 + 2)
    tin = K.mat(game, 'metal', '#ffffff', {'rough': 0.38})
    lab = K.mat(game, 'paint', '#ffffff', {'map': filmLabels(), 'rough': 0.8})
    film = K.mat(game, 'plastic', '#ffffff', {'map': reelTex(), 'rough': 0.5})
    R0, HC = 0.19, 0.052
    prof = [[0, 0], [0.176, 0], [0.188, 0.007], [0.188, 0.036], [0.195, 0.039], [0.195, HC - 0.004], [0.186, HC], [0, HC]]
    canGeo = cg('film_can', lambda: K.lathe(prof, {'seg': 20}))
    canCols = ['#C9CED6', '#B8BEC6', '#D9463A', '#3A6AC8', '#D8A030', '#C9CED6', '#7FA05A', '#B8BEC6']
    geos, lgeos = [], []
    st = {'li': 0}

    def addCan(x, y, z, rx, ry, rz, col, withLabel=True):
        q = THREE.Quaternion().setFromEuler(THREE.Euler(rx, ry, rz))
        geos.append(K.tint(xf(canGeo, {'pos': [x, y, z], 'quat': q}), col))
        if withLabel:
            i = st['li'] % 8
            st['li'] += 1
            d = groundDecal(0.16, 0.064, [(i % 4) / 4, 1 - (_floor(i / 4) + 1) / 2, (i % 4 + 1) / 4, 1 - _floor(i / 4) / 2])
            d.rotateY((rnd() - 0.5) * 0.6)
            d.translate(0, HC + 0.0015, 0.04)
            lgeos.append(xf(d, {'pos': [x, y, z], 'quat': q}))
    # three stacks, slightly askew
    stacks = [[-0.28, 0.12, 6], [0.2, 0.2, 4], [0.05, -0.28, 3]]
    for si, (sx, sz, n) in enumerate(stacks):
        for i in range(n):
            top = i == n - 1
            addCan(sx + (rnd() - 0.5) * 0.04, i * (HC + 0.001), sz + (rnd() - 0.5) * 0.04, 0, rnd() * TAU,
                   (rnd() - 0.5) * 0.02, canCols[(si * 3 + i) % len(canCols)], top or rnd() < 0.3)
    # one leaning against the tall stack, one flat on the floor, open, with its reel
    addCan(-0.28 + 0.26, 0.19, 0.12 - 0.02, 0, 0.3, 1.2, '#D9463A')
    ox, oz = 0.46, -0.2
    # open can: bottom tray + lid leaning off to the side
    geos.append(K.tint(xf(K.lathe([[0, 0], [0.176, 0], [0.188, 0.007], [0.188, 0.034], [0.18, 0.036], [0.18, 0.006],
                                   [0, 0.006]], {'seg': 20}), {'pos': [ox, 0, oz]}), '#B8BEC6'))
    geos.append(K.tint(xf(canGeo, {'pos': [ox + 0.28, 0.012, oz + 0.14], 'rot': [0.25, 0.5, -0.06]}), '#B8BEC6'))
    # reel in the open tray
    reel = THREE.CircleGeometry(0.17, 28)
    reel.rotateX(-math.pi / 2)
    g.add(K.m(reel, film, {'pos': [ox, 0.03, oz]}))
    g.add(tm(K.cyl(0.17, 0.17, 0.022, {'seg': 24, 'bevel': 0.004}), tin, '#4A2A1E', {'pos': [ox, 0.007, oz]}))

    # a loop of film spilling out: ribbon along a curve with sprocket texture
    def draw_strip(ctx, w, h, rand):
        ctx.clearRect(0, 0, w, h)
        ctx.fillStyle = '#3A2418'
        ctx.fillRect(0, 0, w, h)
        ctx.fillStyle = '#7A4A2A'
        y = 8
        while y < h:
            ctx.fillRect(12, y, w - 24, 32)
            y += 42
        ctx.fillStyle = 'rgba(0,0,0,1)'
        ctx.globalCompositeOperation = 'destination-out'
        y = 2
        while y < h:
            ctx.fillRect(2, y, 6, 5)
            ctx.fillRect(w - 8, y, 6, 5)
            y += 10
    filmTex = K.tex.canvas('out_film_strip', 64, 256, draw_strip)
    curve = THREE.CatmullRomCurve3([v3(p) for p in [[ox - 0.12, 0.028, oz - 0.08], [ox - 0.3, 0.004, oz - 0.2],
                                                    [ox - 0.12, 0.004, oz - 0.42], [ox + 0.16, 0.05, oz - 0.36],
                                                    [ox + 0.1, 0.004, oz - 0.2], [ox + 0.36, 0.004, oz - 0.3]]])
    N, wF = 40, 0.035
    pos, uvs, idx = [], [], []
    for i in range(N + 1):
        t = i / N
        pt, tan = curve.getPoint(t), curve.getTangent(t)
        side = THREE.Vector3(-tan.z, 0, tan.x).normalize().multiplyScalar(wF / 2)
        tw = math.sin(t * 5) * 0.6
        lift = THREE.Vector3(0, abs(math.sin(tw)) * wF * 0.5, 0)
        pos.extend([pt.x + side.x * math.cos(tw), pt.y + 0.002 + lift.y, pt.z + side.z * math.cos(tw),
                    pt.x - side.x * math.cos(tw), pt.y + 0.002 - lift.y + 0.004, pt.z - side.z * math.cos(tw)])
        uvs.extend([0, t * 12, 1, t * 12])
        if i < N:
            a = i * 2
            idx.extend([a, a + 2, a + 1, a + 1, a + 2, a + 3])
    rib = THREE.BufferGeometry()
    rib.setAttribute('position', THREE.Float32BufferAttribute(pos, 3))
    rib.setAttribute('uv', THREE.Float32BufferAttribute(uvs, 2))
    rib.setIndex(idx)
    rib.computeVertexNormals()
    ribMesh = K.m(rib, K.mat(game, 'plastic', '#ffffff', {'map': filmTex, 'alphaTest': 0.5, 'side': THREE.DoubleSide,
                                                          'rough': 0.3}))
    ribMesh.userData.noOcclude = True
    g.add(ribMesh)
    g.add(K.m(mergeList(geos), tin))
    g.add(K.m(mergeList(lgeos), lab))
    g.userData.colliders = [{'min': [-0.5, 0, -0.5], 'max': [0.4, 0.34, 0.42]}]
    return K.finish(game, g)


registerProp('yd_film_cans', _film_cans,
             {'category': CAT, 'tags': ['yard', 'film', 'clutter', 'tabletop'], 'size': [1.2, 0.34, 1.0],
              'desc': 'pile of 35mm film cans: askew stacks, taped labels, an open can with reel and a spilled film '
                      'loop (opts.seed)'})

# =================================================================================================== GRAVEL DETAILS
STONE_COLS = ['#9C958C', '#B4ADA2', '#8A8480', '#A89A88', '#C2B8A8', '#8E8A94', '#A8846A']


def _stones(game, opts=None):
    opts = opts or {}
    g = K.prop('yd_stones')
    seed = opts['seed'] if opts.get('seed') is not None else 1
    rnd = mulberry32(seed * 37 + 1)
    mat = K.mat(game, 'paint', '#ffffff', {'rough': 0.85})
    geos = []
    n = opts['count'] if opts.get('count') is not None else 14
    R = opts['radius'] if opts.get('radius') is not None else 0.7
    for i in range(n):
        big = i < 3
        r = 0.09 + rnd() * 0.08 if big else 0.025 + rnd() * 0.04
        a, d = rnd() * TAU, math.sqrt(rnd()) * R * (0.5 if big else 1)
        s = stoneGeo(r, seed * 50 + i, 0.6 if big else 0.5 + rnd() * 0.25)
        col = STONE_COLS[_floor(rnd() * len(STONE_COLS))]
        geos.append(K.tint(xf(s, {'pos': [math.cos(a) * d, r * 0.18, math.sin(a) * d],
                                  'rot': [(rnd() - 0.5) * 0.4, rnd() * TAU, (rnd() - 0.5) * 0.4]}), col))
    g.add(K.m(mergeList(geos), mat))
    g.userData.colliders = []
    return K.finish(game, g, {'ao': {'dist': 0.12}})


registerProp('yd_stones', _stones,
             {'category': CAT, 'tags': ['yard', 'ground', 'decal'], 'size': [1.4, 0.12, 1.4],
              'desc': 'cluster of chunky gravel stones and pebbles, no collider (opts.seed, opts.count, opts.radius)'})


def _puddle(game, opts=None):
    opts = opts or {}
    g = K.prop('yd_puddle')
    seed = opts['seed'] if opts.get('seed') is not None else 1
    r = opts['size'] if opts.get('size') is not None else 0.8
    # rough enough that a nearby lamp gives a glint, not a white disc
    water = K.mat(game, 'crt', '#262A52', {'rough': 0.34, 'env': 0.12, 'rim': 0.5, 'rimColor': '#9FB6FF', 'rimPower': 3})

    def draw_wet(ctx, w, h, rand):
        gr = ctx.createRadialGradient(w / 2, h / 2, 0, w / 2, h / 2, w / 2)
        gr.addColorStop(0, 'rgba(40,34,52,1)')
        gr.addColorStop(0.72, 'rgba(46,40,58,0.9)')
        gr.addColorStop(1, 'rgba(46,40,58,0)')
        ctx.fillStyle = gr
        ctx.fillRect(0, 0, w, h)
    wet = K.mat(game, 'paint', '#ffffff', {'map': K.tex.canvas('out_wet_rim', 128, 128, draw_wet, {'repeat': False}),
                                           'transparent': True, 'depthWrite': False, 'rough': 0.7})
    sh = THREE.Shape(blob(r, seed, 36, 0.25, 1.25, 0.85))
    wg = THREE.ShapeGeometry(sh, 2)
    wg.rotateX(-math.pi / 2)
    # wet dark margin: a soft disc under the water
    mg = THREE.PlaneGeometry(r * 3.3, r * 2.4)
    mg.rotateX(-math.pi / 2)
    mm = K.m(mg, wet, {'pos': [0, 0.004, 0]})
    mm.userData.noAO = True
    g.add(mm)
    wm = K.m(wg, water, {'pos': [0, 0.008, 0]})
    wm.userData.noAO = True
    g.add(wm)
    # a few pebbles poking through the water
    stones = K.mat(game, 'paint', '#ffffff', {'rough': 0.5})
    rnd = mulberry32(seed * 3 + 1)
    geos = []
    for i in range(4):
        geos.append(K.tint(xf(stoneGeo(0.03 + rnd() * 0.03, seed * 9 + i, 0.5),
                              {'pos': [(rnd() - 0.5) * r * 1.8, 0.004, (rnd() - 0.5) * r * 1.1]}), STONE_COLS[i % 5]))
    g.add(K.m(mergeList(geos), stones))
    g.userData.colliders = []
    return K.finish(game, g, {'ao': False})


registerProp('yd_puddle', _puddle,
             {'category': CAT, 'tags': ['yard', 'ground', 'decal'], 'size': [2.2, 0.02, 1.6],
              'desc': 'rain puddle: glossy dark water with a moonlit rim sheen, wet margin, pebbles; no collider '
                      '(opts.size, opts.seed)'})


def gravelTex():
    def draw(ctx, w, h, rand):
        ctx.clearRect(0, 0, w, h)
        c = w / 2
        for i in range(5200):
            a, d = rand() * TAU, math.sqrt(rand()) * c * 0.98
            x, y = c + math.cos(a) * d, c + math.sin(a) * d
            edge = 1 - d / c
            if rand() > edge * 3.2:
                continue
            r = 2 + rand() * 5
            col = STONE_COLS[_floor(rand() * len(STONE_COLS))]
            ctx.globalAlpha = 1
            ctx.fillStyle = hexMul(col, 0.45)
            ctx.beginPath()
            ctx.ellipse(x + 1.2, y + 1.6, r, r * 0.75, rand() * 3, 0, TAU)
            ctx.fill()
            ctx.fillStyle = col
            ctx.beginPath()
            ctx.ellipse(x, y, r, r * 0.75, rand() * 3, 0, TAU)
            ctx.fill()
            ctx.fillStyle = 'rgba(255,255,255,0.25)'
            ctx.beginPath()
            ctx.ellipse(x - r * 0.25, y - r * 0.3, r * 0.4, r * 0.25, 0, 0, TAU)
            ctx.fill()
    return K.tex.canvas('out_gravel_patch', 512, 512, draw, {'repeat': False})


def _gravel_patch(game, opts=None):
    opts = opts or {}
    g = K.prop('yd_gravel_patch')
    s = opts['size'] if opts.get('size') is not None else 2.2
    mat = K.mat(game, 'paint', '#ffffff', {'map': gravelTex(), 'alphaTest': 0.4, 'rough': 0.9})
    m = K.m(groundDecal(s, s), mat, {'pos': [0, 0.006, 0],
                                     'rot': [0, (opts['seed'] if opts.get('seed') is not None else 0) * 1.3, 0]})
    m.userData.noAO = True
    g.add(m)
    g.userData.colliders = []
    return K.finish(game, g, {'ao': False})


registerProp('yd_gravel_patch', _gravel_patch,
             {'category': CAT, 'tags': ['yard', 'ground', 'decal'], 'size': [2.2, 0.01, 2.2],
              'desc': 'loose coarse-gravel ground decal with a ragged edge; no collider (opts.size, opts.seed rotates it)'})


def _weeds(game, opts=None):
    opts = opts or {}
    g = K.prop('yd_weeds')
    seed = opts['seed'] if opts.get('seed') is not None else 1
    rnd = mulberry32(seed * 17 + 9)
    leafMat = K.mat(game, 'leaf', '#ffffff')
    geos = []
    tufts = opts['tufts'] if opts.get('tufts') is not None else 3
    greens = ['#7C9A3A', '#94A83E', '#6A8A34', '#A8A84A']
    for t in range(tufts):
        a = rnd() * TAU
        d = 0.12 + rnd() * 0.25 if t else 0
        x, z = math.cos(a) * d, math.sin(a) * d
        cl = K.leafCluster({'count': 9 + _floor(rnd() * 5), 'len': [0.16, 0.34], 'width': 0.035, 'a0': [1.2, 1.5],
                            'a1': [0.2, 0.9], 'fold': 0.5, 'seed': seed * 10 + t, 'spread': 0.015, 'vary': 0.3})
        geos.append(K.tint(xf(cl, {'pos': [x, 0, z], 'scale': 0.7 + rnd() * 0.6}), greens[t % len(greens)]))
    # a dandelion or two (stalk + yellow puff)
    flowers = []
    for i in range(2):
        x, z, h = (rnd() - 0.5) * 0.3, (rnd() - 0.5) * 0.3, 0.22 + rnd() * 0.12
        geos.append(K.tint(pipeGeo(0.004, [x, 0, z], [x + 0.02, h, z], 4, False), '#6A8A34'))
        flowers.append(xf(THREE.IcosahedronGeometry(0.024, 1), {'pos': [x + 0.02, h + 0.01, z], 'scale': [1, 0.6, 1]}))
    g.add(K.m(mergeList(geos), leafMat))
    g.add(K.m(mergeList(flowers), K.mat(game, 'plastic', '#F4D03A', {'rough': 0.8})))
    g.userData.colliders = []
    return K.finish(game, g, {'ao': {'dist': 0.1, 'height': 0.1}})


registerProp('yd_weeds', _weeds,
             {'category': CAT, 'tags': ['yard', 'ground', 'plant', 'decal'], 'size': [0.7, 0.35, 0.7],
              'desc': 'tufts of weeds poking through the gravel + dandelions; no collider (opts.seed, opts.tufts)'})


# =================================================================================================== shared (tower, hut, van...)
def lerp3(a, b, t):
    return [lerp(a[0], b[0], t), lerp(a[1], b[1], t), lerp(a[2], b[2], t)]


# canvas pixel rect -> uvRect (v measured from the bottom: CanvasTexture flipY). Mutates g.
def pxUV(g, x0, y0, x1, y1, W, H):
    return K.uvRect(g, x0 / W, 1 - y1 / H, x1 / W, 1 - y0 / H)


# 12-tri box beam from a to b (w across, d along nrm): the cheap LOD member
def boxBeam(w, d, a, b, nrm):
    bs = basis(a, b, nrm)
    m, ln = bs['m'], bs['len']
    g = THREE.BoxGeometry(w, ln, d)
    g.translate(0, ln / 2, 0)
    g.applyMatrix4(m)
    return g


# 16-tri chamfered bar (octagonal section, open ends) from a to b: w across, d along nrm, chamfer c
def bar8(w, d, a, b, nrm, c=0.012):
    bs = basis(a, b, nrm)
    m, ln = bs['m'], bs['len']
    hw, hd = w / 2, d / 2
    cc = min(c, hw * 0.45, hd * 0.45)
    sec = [[hw - cc, hd], [hw, hd - cc], [hw, -hd + cc], [hw - cc, -hd], [-hw + cc, -hd], [-hw, -hd + cc], [-hw, hd - cc],
           [-hw + cc, hd]]
    pos, uv = [], []
    for i in range(8):
        x0, z0 = sec[i]
        x1, z1 = sec[(i + 1) % 8]
        u0, u1 = i / 8, (i + 1) / 8
        pos.extend([x0, 0, z0, x1, 0, z1, x1, ln, z1, x0, 0, z0, x1, ln, z1, x0, ln, z0])
        uv.extend([u0, 0, u1, 0, u1, ln, u0, 0, u1, ln, u0, ln])
    g = THREE.BufferGeometry()
    g.setAttribute('position', THREE.Float32BufferAttribute(pos, 3))
    g.setAttribute('uv', THREE.Float32BufferAttribute(uv, 2))
    g.computeVertexNormals()
    g.applyMatrix4(m)
    return g


def concreteTex(base=None):
    base = C.concrete if base is None else base

    def draw(ctx, w, h, rand):
        ctx.fillStyle = base
        ctx.fillRect(0, 0, w, h)
        for i in range(1800):
            ctx.globalAlpha = 0.1 + rand() * 0.22
            ctx.fillStyle = hexMul(base, 0.72) if rand() < 0.55 else hexMix(base, '#ffffff', 0.4)
            ctx.beginPath()
            ctx.arc(rand() * w, rand() * h, 0.5 + rand() * 1.5, 0, TAU)
            ctx.fill()
        grime(ctx, w, h, rand, 16, '#3A3040', 0.05)
        ctx.globalAlpha = 1
    return K.tex.canvas('out_concrete|%s' % base, 256, 256, draw)


# glowing bulb/lens material pair for switchable lights: lit glow vs dark glass
def lensMats(game, color, intensity=2.4):
    return {'on': K.glow(game, color, intensity), 'off': K.mat(game, 'crt', hexMul(color, 0.35), {'rough': 0.15, 'rim': 0.5})}


def ensureCol(root):
    def f(o):
        if getattr(o, 'isMesh', False) and o.material is not None and o.material.vertexColors \
                and not o.geometry.attributes.color:
            o.geometry = o.geometry.clone()
            o.geometry.setAttribute('color', THREE.BufferAttribute(np.ones((o.geometry.attributes.position.count, 3)), 3))
    root.traverse(f)
    return root


def lightMesh(geo, mat, o=None):
    b = K.m(geo, mat, o)
    b.userData.noMerge = True
    b.userData.noAO = True
    b.userData.noOcclude = True
    b.userData.noShadow = True
    return b


# =================================================================================================== TOWER
# Red/white lattice transmitter tower (GDD §5.7): base 4 x 4 m (legs at ±1.8 m on concrete piers), lattice to 27 m,
# batwing TV antenna mast + big red beacon on top (~31.6 m). Detailed lower 8 m: bolted leg flanges, chunky X-bracing,
# caged ladder on the -z face, a work platform at 8 m, coax line down the -x/+z leg toward the hut, signs (DANGER on
# the +z face above the kill-switch cage spot, the WZTV 13 shield on -x, ASR plate). Upper part = cheap LOD (12-tri
# members) in parts.upper. parts.beacons = [top, mid x4] glow meshes (noMerge): setTowerBeacons(game, g, on, color).
TW = JSObj(base=1.8, top=0.42, latH=27, bands=7, low=[0.38, 2, 4, 6, 8], up=[8, 11.2, 14.4, 17.6, 20.8, 24, 27])
TW.bandH = TW.latH / TW.bands
TWR = JSObj(red='#D8402F', white='#F4EEE2')


def twHW(y):
    return lerp(TW.base, TW.top, clamp(y / TW.latH, 0, 1))


def twCol(y):
    return TWR.red if math.fmod(min(TW.bands - 1, math.floor(y / TW.bandH)), 2) == 0 else TWR.white


TW_CORN = [[-1, -1], [1, -1], [1, 1], [-1, 1]]


def twP(c, y):
    return [c[0] * twHW(y), y, c[1] * twHW(y)]


# splits a->b at the paint band boundaries: [[a', b', color], ...]
def twBands(a, b):
    ts = [0, 1]
    y0, y1 = a[1], b[1]
    if abs(y1 - y0) > 1e-5:
        lo, hi = min(y0, y1), max(y0, y1)
        k = math.ceil(lo / TW.bandH)
        while k * TW.bandH < hi:
            y = k * TW.bandH
            if y > lo + 1e-4 and y < hi - 1e-4:
                ts.append((y - y0) / (y1 - y0))
            k += 1
    ts.sort()
    out = []
    for i in range(len(ts) - 1):
        pa, pb = lerp3(a, b, ts[i]), lerp3(a, b, ts[i + 1])
        out.append([pa, pb, twCol((pa[1] + pb[1]) / 2)])
    return out


def towerSigns():
    def draw(ctx, *_):
        rand = mulberry32(1313)
        ctx.textAlign = 'center'
        ctx.textBaseline = 'middle'
        # DANGER / HIGH VOLTAGE (0,0)-(512,352)
        ctx.fillStyle = '#F4F1E8'
        ctx.beginPath()
        ctx.roundRect(4, 4, 504, 344, 26)
        ctx.fill()
        ctx.strokeStyle = '#2A1D2A'
        ctx.lineWidth = 8
        ctx.beginPath()
        ctx.roundRect(16, 16, 480, 320, 18)
        ctx.stroke()
        ctx.fillStyle = '#2A1D2A'
        ctx.beginPath()
        ctx.roundRect(28, 28, 456, 112, 12)
        ctx.fill()
        ctx.fillStyle = '#E23B3B'
        ctx.beginPath()
        ctx.ellipse(256, 84, 206, 44, 0, 0, TAU)
        ctx.fill()
        ctx.fillStyle = '#F4F1E8'
        fitText(ctx, 'DANGER', 360, 70)
        ctx.fillText('DANGER', 256, 88)
        ctx.fillStyle = '#2A1D2A'
        fitText(ctx, 'HIGH VOLTAGE', 440, 54)
        ctx.fillText('HIGH VOLTAGE', 256, 190)
        fitText(ctx, 'KEEP OFF THE TOWER', 420, 30, 'Titan One')
        ctx.fillText('KEEP OFF THE TOWER', 256, 250)
        ctx.fillStyle = '#E8A92E'
        ctx.beginPath()
        ctx.moveTo(250, 272)
        ctx.lineTo(222, 312)
        ctx.lineTo(248, 310)
        ctx.lineTo(236, 336)
        ctx.lineTo(284, 294)
        ctx.lineTo(258, 296)
        ctx.lineTo(276, 272)
        ctx.closePath()
        ctx.fill()
        ctx.globalAlpha = 0.16
        ctx.fillStyle = '#7A4A2A'
        for i in range(20):
            ctx.beginPath()
            ctx.arc(rand() * 512, rand() * 352, 3 + rand() * 14, 0, TAU)
            ctx.fill()
        ctx.globalAlpha = 1
        # WZTV 13 shield (512,0)-(896,384)
        cx, cy = 704, 192
        ctx.fillStyle = '#E23B3B'
        ctx.beginPath()
        ctx.arc(cx, cy, 190, 0, TAU)
        ctx.fill()
        ctx.fillStyle = '#F4F1E8'
        ctx.beginPath()
        ctx.arc(cx, cy, 168, 0, TAU)
        ctx.fill()
        ctx.fillStyle = '#2F5BD3'
        ctx.beginPath()
        ctx.arc(cx, cy, 150, 0, TAU)
        ctx.fill()
        ctx.strokeStyle = 'rgba(255,255,255,0.35)'
        ctx.lineWidth = 6
        ctx.beginPath()
        ctx.arc(cx, cy, 132, math.pi * 1.1, math.pi * 1.6)
        ctx.stroke()
        ctx.fillStyle = '#F4F1E8'
        font(ctx, 150, 'Titan One')
        ctx.fillText('13', cx, cy + 22)
        ctx.fillStyle = '#FFD23A'
        fitText(ctx, 'WZTV', 170, 44)
        ctx.fillText('WZTV', cx, cy - 92)
        # ASR plate (0,384)-(384,512)
        ctx.fillStyle = '#F4F1E8'
        ctx.fillRect(0, 384, 384, 128)
        ctx.strokeStyle = '#2A1D2A'
        ctx.lineWidth = 5
        ctx.strokeRect(8, 392, 368, 112)
        ctx.fillStyle = '#2A1D2A'
        fitText(ctx, 'ASR 1013777', 330, 44)
        ctx.fillText('ASR 1013777', 192, 432)
        fitText(ctx, 'FCC ANTENNA STRUCTURE · WZTV-TV', 340, 18, 'Titan One')
        ctx.fillText('FCC ANTENNA STRUCTURE · WZTV-TV', 192, 478)
        # deck grating (512,384)-(1024,512): dark slots on galvanized grey
        ctx.fillStyle = '#9CA3AD'
        ctx.fillRect(512, 384, 512, 128)
        ctx.fillStyle = '#4A4656'
        y = 392
        while y < 508:
            x = 520
            while x < 1016:
                ctx.beginPath()
                ctx.roundRect(x, y, 32, 7, 3)
                ctx.fill()
                x += 40
            y += 14
    return atlasTex('tower_signs', 1024, 512, draw)


# setTowerBeacons(game, g, on, color): runtime (Godot) — swaps parts.beacons between lensMats(color, 2.6).on/.off.


def _tower(game, opts=None):
    opts = opts or {}
    g = K.prop('yd_tower')
    paint = K.mat(game, 'lacquer', '#ffffff', {'rough': 0.42})
    galv = K.mat(game, 'metal', C.galv, {'rough': 0.5})
    conc = K.mat(game, 'paint', '#ffffff', {'map': concreteTex(), 'rough': 0.92})
    signs = K.mat(game, 'paint', '#ffffff', {'map': towerSigns(), 'rough': 0.55})
    rubber = K.mat(game, 'rubber', '#3A3446')
    lens = lensMats(game, PAL.onAirRed, 2.6)
    lit = opts.get('lit') is not False
    G = {'paint': [], 'galv': [], 'conc': [], 'signs': [], 'rubber': []}
    U = {'paint': [], 'galv': []}           # upper LOD

    def push(arr, geo, col=None):
        arr.append(K.tint(geo, col) if col else geo)
    # --- piers, base plates, anchor bolts
    for c in TW_CORN:
        x, z = c[0] * TW.base, c[1] * TW.base
        push(G['conc'], xf(K.taper(K.box(0.74, 0.44, 0.74, 0.014), {'axis': 'y', 'k': 0.82}), {'pos': [x, 0.2, z]}))
        push(G['galv'], xf(cbox(0.42, 0.04, 0.42, 0.008), {'pos': [x, 0.42, z]}))
        for bx, bz in [[-1, -1], [1, -1], [1, 1], [-1, 1]]:
            push(G['galv'], xf(THREE.CylinderGeometry(0.028, 0.03, 0.05, 6), {'pos': [x + bx * 0.15, 0.45, z + bz * 0.15]}))

    # --- legs (tapered pipes split at the paint bands; flanges at the lower joints)
    def legR(y):
        return lerp(0.105, 0.06, y / TW.latH)
    for c in TW_CORN:
        lv = TW.low + TW.up[1:]
        for i in range(len(lv) - 1):
            upper = lv[i] >= TW.low[-1]
            for pa, pb, col in twBands(twP(c, lv[i]), twP(c, lv[i + 1])):
                push(U['paint'] if upper else G['paint'], pipeGeo(legR(pb[1]), pa, pb, 7 if upper else 12, False, legR(pa[1])),
                     col)
            if not upper and i > 0:
                p, q = twP(c, lv[i]), twP(c, lv[i] + 0.3)
                push(G['paint'], alongGeo(THREE.CylinderGeometry(legR(lv[i]) + 0.045, legR(lv[i]) + 0.045, 0.07, 10), p, q),
                     twCol(lv[i] + 0.01))
        push(U['paint'], xf(THREE.CylinderGeometry(legR(TW.latH) * 0.8, legR(TW.latH), 0.06, 7), {'pos': twP(c, TW.latH)}),
             twCol(TW.latH - 0.1))
    # --- bracing: X per face per section + girt on top of each section
    faces = []
    for i, c0 in enumerate(TW_CORN):
        c1 = TW_CORN[(i + 1) % 4]
        faces.append({'c0': c0, 'c1': c1, 'n': [js_sign(c0[0] + c1[0]), 0, js_sign(c0[1] + c1[1])]})

    def brace(levels, upper):
        for i in range(len(levels) - 1):
            ya = 0.55 if levels[i] == TW.low[0] else levels[i]
            yb = levels[i + 1]
            for f in faces:
                members = [[twP(f['c0'], ya), twP(f['c1'], yb)], [twP(f['c1'], ya), twP(f['c0'], yb)],
                           [twP(f['c0'], yb), twP(f['c1'], yb)]]
                for a, b in members:
                    for pa, pb, col in twBands(a, b):
                        if upper:
                            U['paint'].append(K.tint(boxBeam(0.085, 0.045, pa, pb, f['n']), col))
                        else:
                            G['paint'].append(K.tint(bar8(0.12, 0.055, pa, pb, f['n'], 0.014), col))
    brace(TW.low, False)
    brace(TW.up, True)
    push(U['paint'], xf(cbox(1.1, 0.12, 1.1, 0.02), {'pos': [0, TW.latH + 0.06, 0]}), TWR.red)

    # --- caged ladder on the -z face (lower detailed, upper cheap)
    def lz(y, off=0.3):
        return -(twHW(y) + off)

    def railL(y0, y1, x, arr, cheap):
        a, b = [x, y0, lz(y0)], [x, y1, lz(y1)]
        arr.append(boxBeam(0.05, 0.03, a, b, [0, 0, -1]) if cheap else bar8(0.06, 0.035, a, b, [0, 0, -1], 0.008))
    railL(0.02, 9.1, -0.22, G['galv'], False)
    railL(0.02, 9.1, 0.22, G['galv'], False)
    y = 0.3
    while y < 8.9:
        push(G['galv'], pipeGeo(0.017, [-0.22, y, lz(y)], [0.22, y, lz(y)], 6, False))
        y += 0.3
    railL(9.1, TW.latH - 0.6, -0.2, U['galv'], True)
    railL(9.1, TW.latH - 0.6, 0.2, U['galv'], True)
    y = 9.5
    while y < TW.latH - 0.8:
        U['galv'].append(boxBeam(0.4, 0.03, [0, y - 0.015, lz(y)], [0, y + 0.015, lz(y)], [0, 0, -1]))
        y += 0.6
    for y in (2, 4, 6):
        for x in (-0.22, 0.22):
            push(G['galv'], bar8(0.05, 0.03, [x, y, lz(y)], [x * 0.5, y, -twHW(y)], [0, 1, 0], 0.006))
    y = 2.4
    while y <= 7.4:
        z0 = lz(y)
        pts = [[-0.3, y, z0 + 0.02]]
        for k in range(9):
            a = math.pi * (k / 8)
            pts.append([-math.cos(a) * 0.36, y, z0 - 0.32 - math.sin(a) * 0.36])
        pts.append([0.3, y, z0 + 0.02])
        push(G['galv'], K.tube(pts, 0.016, {'seg': 8, 'radial': 4}))
        y += 0.7
    for a in (0.35, 1.2, 1.95, 2.8):
        x, dz = -math.cos(a) * 0.36, -0.32 - math.sin(a) * 0.36
        push(G['galv'], pipeGeo(0.013, [x, 2.4, lz(2.4) + dz], [x, 7.3, lz(7.3) + dz], 5, False))
    # --- work platform at 8 m
    PY = 8
    Pi, Po = twHW(PY) - 0.04, twHW(PY) + 0.78
    PW, PM = Po - Pi, (Po + Pi) / 2

    def grate(geo):
        return pxUV(geo, 520, 390, 1016, 506, 1024, 512)
    halfW = Po - 0.35
    for s in (-1, 1):
        G['signs'].append(grate(xf(cbox(halfW, 0.06, PW, 0.012).clone(), {'pos': [s * (0.35 + halfW / 2), PY, -PM]})))
    G['signs'].append(grate(xf(cbox(2 * Po, 0.06, PW, 0.012).clone(), {'pos': [0, PY, PM]})))
    for s in (-1, 1):
        G['signs'].append(grate(xf(cbox(2 * Pi, 0.06, PW, 0.012).clone(), {'pos': [s * PM, PY, 0], 'rot': [0, math.pi / 2, 0]})))
    for c in TW_CORN:
        push(G['galv'], bar8(0.07, 0.04, twP(c, PY - 1.1), [c[0] * (Po - 0.1), PY - 0.04, c[1] * (Po - 0.1)], [c[0], 0, -c[1]],
                             0.006))
    for s in (-1, 1):
        push(G['paint'], xf(cbox(2 * Po, 0.12, 0.03, 0.008), {'pos': [0, PY + 0.09, s * (Po - 0.015)]}), '#F2C230')
        push(G['paint'], xf(cbox(0.03, 0.12, 2 * Po, 0.008), {'pos': [s * (Po - 0.015), PY + 0.09, 0]}), '#F2C230')
    for c in TW_CORN:
        for ux, uz in [[c[0], c[1]], [0, c[1]], [c[0], 0]]:
            if ux == 0 and uz == -1:
                continue
            x, z = ux * (Po - 0.05), uz * (Po - 0.05)
            push(G['galv'], pipeGeo(0.024, [x, PY, z], [x, PY + 1.08, z], 7, False))
    for y in (PY + 0.55, PY + 1.08):
        push(G['galv'], K.tube(K.roundRectPath(2 * Po - 0.1, 2 * Po - 0.1, 0.14, y, 2), 0.026,
                               {'seg': 24, 'radial': 5, 'closed': True}))
    for x in (-0.22, 0.22):
        push(G['galv'], K.tube([[x, 9.0, lz(9.0)], [x, 9.6, lz(9.6)], [x * 1.1, 9.8, lz(9.8) + 0.15],
                                [x * 1.1, 9.4, lz(9.4) + 0.4]], 0.02, {'seg': 6, 'radial': 4}))
    # --- microwave drum on the -x face (12.6 m) + coax line down the -x/+z leg
    y = 12.6
    x = -twHW(y) - 0.55
    drum = K.lathe([[0, -0.2], [0.5, -0.2], [0.53, -0.16], [0.53, 0.16], [0.5, 0.21], [0.36, 0.25], [0, 0.26]],
                   {'seg': 16}).clone()
    drum.rotateZ(math.pi / 2)
    push(U['galv'], xf(drum, {'pos': [x, y, 0.3]}), '#EEE8DA')
    push(U['galv'], xf(THREE.CircleGeometry(0.42, 18).rotateY(-math.pi / 2), {'pos': [x - 0.265, y, 0.3]}), '#B8B2C4')
    push(U['galv'], pipeGeo(0.05, [x + 0.2, y - 0.5, 0.3], [x + 0.2, y + 0.5, 0.3], 6, True))
    U['galv'].append(boxBeam(0.06, 0.06, [x + 0.2, y + 0.4, 0.3], [-twHW(y + 0.4), y + 0.4, twHW(y + 0.4) * 0.2], [0, 1, 0]))
    U['galv'].append(boxBeam(0.06, 0.06, [x + 0.2, y - 0.4, 0.3], [-twHW(y - 0.4), y - 0.4, twHW(y - 0.4) * 0.2], [0, 1, 0]))

    def coax(y):
        h = twHW(y) + 0.16
        return [-h, y, h]
    push(G['rubber'], pipeGeo(0.05, coax(1.2), coax(8.4), 8, False))
    push(G['rubber'], K.tube([coax(1.25), [-TW.base - 0.3, 0.7, TW.base + 0.3], [-TW.base - 0.75, 0.12, TW.base + 0.75],
                              [-TW.base - 0.95, -0.05, TW.base + 0.95]], 0.05, {'seg': 10, 'radial': 8}))
    U['galv'].append(K.tint(pipeGeo(0.045, coax(8.4), coax(TW.latH - 0.3), 5, False), '#3A3446'))
    y = 1.8
    while y < 8:
        push(G['galv'], xf(cbox(0.1, 0.07, 0.1, 0.01), {'pos': coax(y)}))
        y += 1.6
    # --- antenna mast: 3 batwing bays + the big beacon
    MY = TW.latH + 0.12
    MT = MY + 4.1
    push(U['galv'], pipeGeo(0.11, [0, MY, 0], [0, MT, 0], 10, False, 0.13))
    wing = THREE.Shape([THREE.Vector2(x_, y_) for x_, y_ in [[0.12, -0.4], [0.62, -0.32], [0.62, 0.32], [0.12, 0.4]]])
    wing.holes.append(THREE.Path([THREE.Vector2(x_, y_) for x_, y_ in [[0.22, -0.26], [0.52, -0.21], [0.52, 0.21],
                                                                       [0.22, 0.26]]]))
    wingGeo = K.extrude(wing, 0.035, {'bevel': 0, 'curveSeg': 1})
    for b in range(3):
        y = MY + 0.75 + b * 1.15
        for k in range(4):
            push(U['galv'], xf(wingGeo, {'pos': [0, y, 0], 'rot': [0, k * math.pi / 2, 0]}))
        push(U['galv'], xf(THREE.CylinderGeometry(0.16, 0.16, 0.08, 10), {'pos': [0, y, 0]}), '#C9CED6')
    push(U['paint'], xf(K.lathe([[0, 0], [0.26, 0], [0.26, 0.08], [0.2, 0.12], [0, 0.12]], {'seg': 14, 'round': 0.02,
                                                                                               'steps': 1}),
                        {'pos': [0, MT, 0]}), TWR.red)
    beacons = []

    def beaconGeo(r):
        return K.lathe([[0, 0], [r, 0], [r * 1.02, r * 0.5], [r * 0.85, r * 1.15], [r * 0.45, r * 1.5], [0, r * 1.58]],
                       {'seg': 10, 'round': r * 0.2, 'steps': 1})

    def addBeacon(pos, r, name):
        b = lightMesh(beaconGeo(r), lens['on'] if lit else lens['off'], {'pos': pos, 'name': name})
        g.add(b)
        beacons.append(b)
        k = 0
        while r > 0.2 and k < 3:
            pts = []
            for s in range(7):
                a = (s / 6) * math.pi
                pts.append([math.cos(a) * r * 1.2, math.sin(a) * r * 1.7, 0])
            push(U['galv'], xf(K.tube(pts, r * 0.05, {'seg': 8, 'radial': 3}), {'pos': pos, 'rot': [0, (k * math.pi) / 3, 0]}))
            k += 1
        push(U['paint'], xf(THREE.CylinderGeometry(r * 1.1, r * 1.15, r * 0.25, 12), {'pos': [pos[0], pos[1] - r * 0.125,
                                                                                              pos[2]]}), TWR.red)
        return b
    top = addBeacon([0, MT + 0.12, 0], 0.24, 'beacon_top')
    for y, cs in [[9.9, [[-1, -1], [1, 1]]], [18.6, [[1, -1], [-1, 1]]]]:
        for c in cs:
            p = twP(c, y)
            q = [p[0] + c[0] * 0.32, y, p[2] + c[1] * 0.32]
            U['galv'].append(boxBeam(0.05, 0.05, p, q, [0, 1, 0]))
            addBeacon([q[0], y + 0.02, q[2]], 0.13, 'beacon_mid')
    # --- signs
    y = 2.55
    z = twHW(y) + 0.045
    G['signs'].append(xf(pxUV(decal(0.78, 0.54), 0, 0, 512, 352, 1024, 512), {'pos': [0, y, z + 0.002], 'rot': [0, math.pi, 0]}))
    push(G['galv'], xf(cbox(0.84, 0.6, 0.03, 0.01), {'pos': [0, y, z - 0.018]}))
    y2 = 5.1
    x2 = -twHW(y2) - 0.08
    shield = THREE.CircleGeometry(0.62, 28)
    G['signs'].append(xf(pxUV(shield, 512, 0, 896, 384, 1024, 512), {'pos': [x2 - 0.032, y2, 0], 'rot': [0, -math.pi / 2, 0]}))
    push(G['paint'], xf(THREE.CylinderGeometry(0.66, 0.66, 0.06, 28), {'pos': [x2 + 0.03, y2, 0], 'rot': [0, 0, math.pi / 2]}),
         TWR.white)
    for dy in (-0.35, 0.35):
        push(G['galv'], beamGeo(0.06, 0.04, [x2 + 0.03, y2 + dy, 0], [-twHW(y2 + dy), y2 + dy, 0], [0, 1, 0], 0.006))
    y3 = 1.55
    z3 = -twHW(y3) - 0.05
    G['signs'].append(xf(pxUV(decal(0.45, 0.15), 0, 384, 384, 512, 1024, 512), {'pos': [0.72, y3, z3 - 0.012]}))
    push(G['galv'], xf(cbox(0.48, 0.18, 0.02, 0.006), {'pos': [0.72, y3, z3]}))
    # --- assemble: lower merged per material, upper in its own (noMerge) group merged locally
    g.add(K.m(mergeList(G['paint']), paint))
    g.add(K.m(mergeList(G['galv']), galv))
    g.add(K.m(mergeList(G['conc']), conc))
    g.add(K.m(mergeList(G['signs']), signs))
    g.add(K.m(mergeList(G['rubber']), rubber))
    upper = THREE.Group()
    upper.name = 'upper'
    upper.userData.noMerge = True
    upper.add(K.m(mergeList(U['paint']), paint), K.m(mergeList(U['galv']), galv))
    g.add(upper)
    g.userData.parts = {'upper': upper, 'beacons': beacons, 'beaconTop': top}
    g.userData.lightAnchors = [
        {'pos': [0, MT + 0.3, 0], 'color': PAL.onAirRed, 'intensity': 3, 'distance': 14, 'flicker': 0},
        {'pos': [0, 10.2, 0], 'color': PAL.onAirRed, 'intensity': 1.4, 'distance': 6, 'flicker': 0},
    ] if lit else []
    bb = TW.base + 0.4
    g.userData.colliders = [{'min': [-bb, 0, -bb], 'max': [bb, 3, bb]}]
    return K.finish(game, g, {'ao': {'res': 150, 'dist': 0.45, 'rays': 8, 'height': 0.5, 'heightStrength': 0.3}})


registerProp('yd_tower', _tower,
             {'category': CAT, 'tags': ['yard', 'tower', 'landmark'], 'size': [4.4, 31.7, 4.4], 'hero': True,
              'desc': 'red/white lattice transmitter tower, 4 m base, batwing mast + beacons; parts.upper (LOD), '
                      'parts.beacons (setTowerBeacons); +z face kept clear for the kill-switch cage (opts.lit)'})

registerScene('out_tower_base', {
    'floor': '#4A4652', 'wall': '#1E2344', 'room': [40, 40], 'wallH': 0.01, 'hemi': 0.8,
    'items': [{'id': 'yd_tower', 'pos': [0, 4]}],
    'cam': {'pos': [-5.5, 3.2, -7.5], 'target': [0, 4.6, 3.2], 'fov': 60},
})

# @@PART3@@
