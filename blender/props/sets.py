"""DEAD AIR — props: STUDIO SETS & EASTER-EGG OBJECTS (docs/PROPKIT.md, GDD §5.7 / §13).
Port of src/props/sets.js (owner: sets prop artist) — same ids, builders, numbers, textures and seeds.

  Studio A   marquee_arch · pledge_wheel · baron_throne · contestant_podium · ghost_light · pledge_carousel
             tote_board_tower · bleacher_block · disco_ball · applause_sign · chroma_cyc
  Studio B   cardboard_rocket · treehouse_facade · puppet_theater · alphabet_block · rainbow_arch · giant_crayon
             giant_crayons · toy_train_loop · xylophone
  EE         chime_rack · trophy_case · neon_logo_partition · letter_board · weather_map · rundown_board
             kill_switch_cage · perpetua_crate · dressing_room_door

Runtime helpers of the JS file (marqueeChase, setGhostLight, setToteValue, setToteGlow, setPodiumScore, ringPhone,
setNeon, setApplause, setRundownCard, showMagnet) animate PLACED props: they are Godot runtime code (the systems
that drive these props). Every prop keeps its animatable pieces in userData.parts (see each builder's header
comment) and extra JSON anchors in userData.anchors (local [x,y,z]). Texture builders the runtime also needs are
ported here as plain functions (applauseFace(lit) -> 'sets.applause_on' / 'sets.applause_off',
discoSpeckTexture() -> 'sets.disco_specks', writeStripUV() for the tote_digits strips).

Porting notes (JS plumbing only):
  * Math.hypot -> js_hypot (V8's scaled Kahan sum: Python's math.hypot rounds differently, and the build-time
    cloth simulation of the Baron's cape runs on Float32Arrays, emulated with array('f') for bit-exact results).
  * instanceMatrix/instanceColor.needsUpdate and InstancedMesh.computeBoundingSphere() are renderer plumbing.
"""
import math
import re
from array import array

import numpy as np

from dalib import kit as K
from dalib.kit import registerProp, registerScene, PAL, THREE, getCard
from dalib.rng import mulberry32
from dalib.tex import woodPanel
from dalib.mathutils3 import js_round, js_str, js_sign, lerp, clamp

TAU = math.pi * 2
_PI = math.pi


def V3(x=0, y=0, z=0):
    return THREE.Vector3(x, y, z)


UP = V3(0, 1, 0)
CAT = 'sets'


def _nn(v, d):
    """JS `v ?? d`"""
    return v if v is not None else d


def js_hypot(*xs):
    """Math.hypot exactly as V8 computes it (normalize by the max, Kahan-compensated sum of squares)."""
    mx = 0.0
    nan = False
    av = []
    for v in xs:
        v = float(v)
        if v != v:
            nan = True
            av.append(0.0)
        else:
            a = abs(v)
            av.append(a)
            if a > mx:
                mx = a
    if mx == math.inf:
        return math.inf
    if nan:
        return math.nan
    if mx == 0:
        return 0.0
    s = 0.0
    comp = 0.0
    for a in av:
        n = a / mx
        summand = n * n - comp
        pre = s + summand
        comp = (pre - s) - summand
        s = pre
    return math.sqrt(s) * mx


# --------------------------------------------------------------------------------------------- local helpers
FONT = {
    'sign': '"Bungee", Impact, "Arial Black", sans-serif',
    'round': '"Titan One", "Arial Rounded MT Bold", "Arial Black", sans-serif',
    'groovy': '"Shrikhand", "Cooper Black", Georgia, serif',
    'osd': '"VT323", "Courier New", monospace',
    'hand': '"Titan One", "Comic Sans MS", sans-serif',
}


# tinted copy of a (cached) kit geometry: lets one white material carry many colors (fewer draw calls)
def tg(geo, color):
    return K.tint(geo.clone(), color)


# mesh from a tinted geometry
def tm(geo, mat, color=None, o=None):
    return K.m(tg(geo, color) if color else geo, mat, o)


# canvas texture (non repeating, redrawn when fonts load)
def cv(key, w, h, draw, repeat=False):
    return K.tex.canvas('sets.%s' % key, w, h, draw, {'repeat': repeat, 'fonts': True})


def rrect(ctx, x, y, w, h, r):
    ctx.beginPath()
    ctx.roundRect(x, y, w, h, r)


def text(ctx, s, x, y, o=None):
    o = o or {}
    font = o.get('font', FONT['sign'])
    size = o.get('size', 40)
    fill = o.get('fill', '#fff')
    stroke = o.get('stroke')
    lw = o.get('lw', 0)
    align = o.get('align', 'center')
    base = o.get('base', 'middle')
    maxW = o.get('maxW', 0)
    shadow = o.get('shadow')
    rot = o.get('rot', 0)
    track = o.get('track', 0)
    ctx.save()
    ctx.translate(x, y)
    if rot:
        ctx.rotate(rot)
    px = size
    ctx.font = '%spx %s' % (js_str(px), font)
    if track:
        ctx.letterSpacing = '%spx' % js_str(track)
    if maxW:
        while ctx.measureText(s).width > maxW and px > 6:
            px *= 0.94
            ctx.font = '%spx %s' % (js_str(px), font)
    ctx.textAlign = align
    ctx.textBaseline = base
    ctx.lineJoin = 'round'
    if shadow:
        ctx.fillStyle = shadow
        ctx.fillText(s, px * 0.05, px * 0.07)
        if stroke:
            ctx.lineWidth = lw
            ctx.strokeStyle = shadow
            ctx.strokeText(s, px * 0.05, px * 0.07)
    if stroke:
        ctx.lineWidth = lw
        ctx.strokeStyle = stroke
        ctx.strokeText(s, 0, 0)
    ctx.fillStyle = fill
    ctx.fillText(s, 0, 0)
    ctx.restore()


def starPts(cx, cy, ro, ri, n=5, a0=-math.pi / 2):
    p = []
    for i in range(n * 2):
        a = a0 + (i / (n * 2)) * TAU
        r = ri if i % 2 else ro
        p.append([cx + math.cos(a) * r, cy + math.sin(a) * r])
    return p


def poly(ctx, pts):
    ctx.beginPath()
    for i, (x, y) in enumerate(pts):
        if i:
            ctx.lineTo(x, y)
        else:
            ctx.moveTo(x, y)
    ctx.closePath()


def grad(ctx, x0, y0, x1, y1, stops):
    g = ctx.createLinearGradient(x0, y0, x1, y1)
    for i, c in enumerate(stops):
        if isinstance(c, (list, tuple)):
            g.addColorStop(c[0], c[1])
        else:
            g.addColorStop(i / max(1, len(stops) - 1), c)
    return g


def speckle(ctx, w, h, rand, n=400, a=0.06):
    for i in range(n):
        ctx.fillStyle = ('rgba(255,255,255,%s)' % js_str(a)) if rand() < 0.5 else ('rgba(40,20,40,%s)' % js_str(a))
        ctx.fillRect(rand() * w, rand() * h, 1 + rand() * 2, 1 + rand() * 2)


def shadeHex(hex_, amt):
    c = THREE.Color(hex_)
    if amt >= 0:
        c.lerp(THREE.Color(1, 1, 1), amt)
    else:
        c.multiplyScalar(1 + amt)
    return '#' + c.getHexString()


# flat decal facing -Z (prop front) or +Z (back=True)
def decalGeo(w, h, uvr=None, back=False):
    g = THREE.PlaneGeometry(w, h)
    if not back:
        g.rotateY(math.pi)
    if uvr:
        K.uvRect(g, *uvr)
    return g


def _v3(a):
    return V3(*a) if isinstance(a, (list, tuple)) else a


# mesh aligned from a to b; geo built along +Y with base at 0 and unit-less length l (use K.cyl(r, r, l))
def between(geo, mat, a, b):
    A, B = _v3(a), _v3(b)
    m = K.m(geo, mat)
    m.position.copy(A)
    m.quaternion.setFromUnitVectors(UP, B.clone().sub(A).normalize())
    return m


def rodGeo(r, a, b, seg=8, bevel=0.003):
    A, B = _v3(a), _v3(b)
    return K.cyl(r, r, A.distanceTo(B), {'seg': seg, 'bevel': min(bevel, r * 0.5)})


def rod(r, mat, a, b, seg=8):
    return between(rodGeo(r, a, b, seg), mat, a, b)


def ringPts(r, n, y=0, a0=0):
    p = []
    for i in range(n):
        a = a0 + (i / n) * TAU
        p.append([math.cos(a) * r, y, math.sin(a) * r])
    return p


# InstancedMesh from transforms [{pos, rot:[x,y,z], scale:number|[x,y,z]}] with optional per-instance colors
def instanced(geo, mat, xf, colors=None, name=''):
    im = THREE.InstancedMesh(geo, mat, len(xf))
    o = THREE.Object3D()
    for i, t in enumerate(xf):
        o.position.fromArray(t['pos'])
        if t.get('quat') is not None:
            o.quaternion.copy(t['quat'])
        else:
            o.rotation.set(*(t.get('rot') or [0, 0, 0]))
        s = _nn(t.get('scale'), 1)
        if isinstance(s, (int, float)):
            o.scale.setScalar(s)
        else:
            o.scale.set(*s)
        o.updateMatrix()
        im.setMatrixAt(i, o.matrix)
    if colors:
        for i, c in enumerate(colors):
            im.setColorAt(i, c if getattr(c, 'isColor', False) else THREE.Color(c))
    # (instanceMatrix / instanceColor .needsUpdate, computeBoundingSphere: renderer plumbing)
    im.userData.noMerge = True
    im.name = name
    return im


def hdr(hex_, k):
    return THREE.Color(hex_).multiplyScalar(k)


# bulb dome facing -Z (marquee chasers)
def bulbGeo(r=0.06):
    g = THREE.SphereGeometry(r, 8, 4, 0, TAU, 0, math.pi * 0.62)
    g.rotateX(-math.pi / 2)
    return g


def socketGeo(r=0.06):
    g = K.lathe([[0, 0], [r * 1.25, 0], [r * 1.3, r * 0.35], [r * 1.05, r * 0.55], [0, r * 0.55]], {'seg': 10}).clone()
    g.rotateX(-math.pi / 2)
    return g


# sample a polyline by arc length: returns [{p:[x,y], t:[tx,ty]}]
def resample(pts, spacing, offset=0.5, closed=False):
    P = list(pts) + [pts[0]] if closed else pts
    seg = []
    L = 0
    for i in range(1, len(P)):
        ln = js_hypot(P[i][0] - P[i - 1][0], P[i][1] - P[i - 1][1])
        seg.append(ln)
        L += ln
    n = max(1, js_round(L / spacing))
    step = L / n
    out = []
    si, acc = 0, 0
    for k in range(n if closed else n + 1):
        d = (k + (offset if closed else 0)) * step
        if not closed:
            d = min(L - 1e-6, k * step)
        while si < len(seg) - 1 and acc + seg[si] < d:
            acc += seg[si]
            si += 1
        t = (d - acc) / seg[si] if seg[si] > 0 else 0
        a, b = P[si], P[si + 1]
        tx, ty = (b[0] - a[0]) / (seg[si] or 1), (b[1] - a[1]) / (seg[si] or 1)
        out.append({'p': [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t], 't': [tx, ty]})
    return out


def arcPts(cx, cy, r, a0, a1, n):
    p = []
    for i in range(n + 1):
        a = a0 + (a1 - a0) * (i / n)
        p.append([cx + math.cos(a) * r, cy + math.sin(a) * r])
    return p


# flip-digit strip (n quads facing -Z) from the tote_digits atlas; setStrip() (runtime) rewrites its UVs
def toteStripGeo(s, tw, th, pitch):
    n = len(s)
    pos, uv, idx = [], [], []
    for i in range(n):
        x0 = ((n - 1) / 2 - i) * pitch  # -Z facing: first char at +x (viewer's left)
        q = [[x0 + tw / 2, -th / 2], [x0 - tw / 2, -th / 2], [x0 - tw / 2, th / 2], [x0 + tw / 2, th / 2]]
        for x, y in q:
            pos += [x, y, 0]
            uv += [0, 0]
        b = i * 4
        idx += [b, b + 1, b + 2, b, b + 2, b + 3]
    g = THREE.BufferGeometry()
    g.setAttribute('position', THREE.Float32BufferAttribute(pos, 3))
    g.setAttribute('normal', THREE.Float32BufferAttribute([0, 0, -1] * (n * 4), 3))
    g.setAttribute('uv', THREE.Float32BufferAttribute(uv, 2))
    g.setIndex(idx)
    writeStripUV(g, s)
    return g


def writeStripUV(g, s):
    at = getCard('tote_digits').userData.atlas
    uv = g.attributes.uv
    n = uv.count // 4
    for i in range(n):
        ch = s[i] if i < len(s) else ' '
        u0, v0, u1, v1 = [0.001, 0.001, 0.002, 0.002] if ch == ' ' else at.uv(ch)
        e = 0.002
        u0 += e
        u1 -= e
        v0 += e
        v1 -= e
        uv.setXY(i * 4, u0, v0)
        uv.setXY(i * 4 + 1, u1, v0)
        uv.setXY(i * 4 + 2, u1, v1)
        uv.setXY(i * 4 + 3, u0, v1)


# hanging props: no floor contact shading
AO_HANG = {'floor': False, 'height': 0}


# =========================================================================================================
# STUDIO A
# =========================================================================================================

# ---------------------------------------------------------------------------------------- marquee_arch
# Light-bulb marquee arch framing the Studio A stage (inverted-U frame shaped like a CRT screen outline,
# stepped 70s stripes, chrome beads, WZTV 13 pylons, "Spooktacular" crest on a sunburst). opts: { width=14.4, height=4.8 }
# parts.bulbs: InstancedMesh (userData.chase = { count, on, dim }) -> marqueeChase(prop, t, mode).
# Local: arch feet on the stage floor (y=0), opening centered on x, front -Z. Colliders: the two feet only.
def _marquee_arch(game, opts=None):
    opts = opts or {}
    g = K.prop('marquee_arch')
    W, H, B, R, D = _nn(opts.get('width'), 14.4), _nn(opts.get('height'), 4.8), 1.05, 1.9, 0.62
    lac = K.mat(game, 'lacquer', '#ffffff')
    chrome = K.mat(game, 'chrome', '#A8B0BA')

    # U-shaped band (outer w x h, band width b, outer top-corner radius r) as a shape with concentric corners
    def uShape(w, h, b, r):
        s = THREE.Shape()
        x0, x1 = -w / 2, w / 2
        s.moveTo(x0, 0)
        s.lineTo(x0, h - r)
        s.absarc(x0 + r, h - r, r, math.pi, math.pi / 2, True)
        s.lineTo(x1 - r, h)
        s.absarc(x1 - r, h - r, r, math.pi / 2, 0, True)
        s.lineTo(x1, 0)
        s.lineTo(x1 - b, 0)
        s.lineTo(x1 - b, h - r)
        s.absarc(x1 - r, h - r, r - b, 0, math.pi / 2, False)
        s.lineTo(x0 + r, h - b)
        s.absarc(x0 + r, h - r, r - b, math.pi / 2, math.pi, False)
        s.lineTo(x0 + b, 0)
        s.closePath()
        return s

    # stripe inset o from the outer edge, width b
    def stripe(o, b, depth, z, col, bevel=0.025, bs=1):
        return g.add(tm(K.extrude(uShape(W - 2 * o, H - o, b, R - o), depth,
                                  {'bevel': bevel, 'bevelSeg': bs, 'curveSeg': 12}), lac, col, {'pos': [0, 0, z]}))
    stripe(0, B, D, 0, PAL.burntOrange, 0.07, 2)
    stripe(0.06, 0.15, 0.06, -D / 2 - 0.02, PAL.channelRed)
    GB = 0.44
    GO = (B - GB) / 2
    stripe(GO, GB, 0.1, -D / 2 - 0.04, PAL.harvestGold, 0.035, 2)
    stripe(B - 0.2, 0.14, 0.06, -D / 2 - 0.02, PAL.chocolate)

    # chrome beads along the outer and inner front edges
    def edge(w, h, r, y0):
        return [[-w / 2, y0], [-w / 2, h - r]] + arcPts(-w / 2 + r, h - r, r, math.pi, math.pi / 2, 8)[1:] + \
            arcPts(w / 2 - r, h - r, r, math.pi / 2, 0, 8) + [[w / 2, y0]]

    def bead(pts, z):
        return K.tube([[x, y, z] for x, y in pts], 0.035, {'seg': 60, 'radial': 6})
    g.add(K.m(bead(edge(W - 0.03, H - 0.015, R - 0.015, 1.8), -D / 2 + 0.02), chrome))
    g.add(K.m(bead(edge(W - 2 * B + 0.03, H - B + 0.015, R - B + 0.015, 1.8), -D / 2 + 0.02), chrome))
    # back battens (the back side is seen from the stage)
    for s in (-1, 1):
        g.add(tm(K.box(0.12, H - 0.6, 0.06, 0.012), lac, '#8A5A34', {'pos': [s * (W / 2 - B / 2), H / 2, D / 2 + 0.03]}))
    g.add(tm(K.box(W - 2 * R, 0.12, 0.06, 0.012), lac, '#8A5A34', {'pos': [0, H - B / 2, D / 2 + 0.03]}))

    # pylons at the feet with a WZTV 13 roundel
    def draw_badge(ctx, w, h, rand):
        c = w / 2
        poly(ctx, starPts(c, c, 126, 104, 16, 0))
        ctx.fillStyle = PAL.harvestGold
        ctx.fill()
        ctx.fillStyle = PAL.channelRed
        ctx.beginPath()
        ctx.arc(c, c, 98, 0, TAU)
        ctx.fill()
        ctx.fillStyle = PAL.wztvBlue
        ctx.beginPath()
        ctx.arc(c, c, 80, 0, TAU)
        ctx.fill()
        text(ctx, '13', c, c + 8, {'font': FONT['round'], 'size': 104, 'fill': '#F4F1E8', 'stroke': '#1B2F7A', 'lw': 8})
        text(ctx, 'WZTV', c, c - 58, {'font': FONT['sign'], 'size': 22, 'fill': PAL.harvestGold})
    badge = cv('marquee_badge', 256, 256, draw_badge)
    badgeMat = K.mat(game, 'lacquer', '#ffffff', {'map': badge})
    PH = 2.3
    for s in (-1, 1):
        x = s * (W / 2 - B / 2)
        g.add(tm(K.box(B + 0.42, PH, D + 0.4, 0.09), lac, PAL.chocolate, {'pos': [x, PH / 2, 0]}))
        g.add(tm(K.box(B + 0.54, 0.14, D + 0.52, 0.045), lac, PAL.harvestGold, {'pos': [x, PH + 0.02, 0]}))
        g.add(tm(K.box(B + 0.5, 0.1, D + 0.48, 0.014), lac, '#2A1810', {'pos': [x, 0.05, 0]}))
        for i in range(3):
            g.add(tm(K.box(B + 0.44, 0.05, D + 0.42, 0.02), lac, [PAL.burntOrange, PAL.harvestGold, PAL.channelRed][i],
                     {'pos': [x, 0.3 + i * 0.075, 0]}))
        bg = THREE.CircleGeometry(0.46, 32)
        bg.rotateY(math.pi)
        g.add(K.m(bg, badgeMat, {'pos': [x, 1.35, -D / 2 - 0.205]}))

    # crest: rounded plaque on a sunburst fan
    cy, pw, ph = H + 0.25, 4.8, 1.35
    rays = 15
    for i in range(rays):
        a = math.pi * (0.08 + 0.84 * (i / (rays - 1)))
        ln = 1.55 + (i % 2) * 0.3
        ray = K.extrude([[-0.1, 0], [0.1, 0], [0.24, ln], [-0.24, ln]], 0.08, {'bevel': 0.02, 'bevelSeg': 1})
        m = tm(ray, lac, [PAL.channelRed, PAL.harvestGold, PAL.burntOrange][i % 3], {'pos': [0, cy - 0.1, 0.05]})
        m.rotation.z = a - math.pi / 2
        g.add(m)

    def draw_plaque(ctx, w, h, rand):
        rrect(ctx, 0, 0, w, h, 40)
        ctx.fillStyle = grad(ctx, 0, 0, 0, h, ['#6B3A6E', '#3E1E48'])
        ctx.fill()
        ctx.save()
        rrect(ctx, 0, 0, w, h, 40)
        ctx.clip()
        for i in range(3):
            ctx.fillStyle = [PAL.burntOrange, PAL.harvestGold, PAL.channelRed][i]
            ctx.fillRect(0, h - 40 + i * 9, w, 6)
        ctx.fillStyle = 'rgba(255,255,255,0.07)'
        ctx.fillRect(0, 0, w, h * 0.4)
        ctx.restore()
        text(ctx, 'Spooktacular', w / 2, 60, {'font': FONT['groovy'], 'size': 72,
                                              'fill': grad(ctx, 0, 28, 0, 96, ['#FFF2B0', '#FFC23A', '#FF8A2A']),
                                              'stroke': '#2A1030', 'lw': 10, 'maxW': w * 0.9,
                                              'shadow': 'rgba(0,0,0,0.35)'})
        text(ctx, '13-HOUR TELETHON  ·  WZTV 13', w / 2, 114, {'font': FONT['sign'], 'size': 22, 'fill': '#F6E7C8',
                                                               'stroke': '#2A1030', 'lw': 5, 'maxW': w * 0.8,
                                                               'track': 1})
    plaque = cv('marquee_crest2', 512, 160, draw_plaque)
    plaqueMat = K.mat(game, 'lacquer', '#ffffff', {'map': plaque})
    g.add(tm(K.extrude(K.roundRect(pw + 0.24, ph + 0.24, 0.45), 0.2, {'bevel': 0.06, 'bevelSeg': 2}), lac,
             PAL.harvestGold, {'pos': [0, cy, -0.05]}))
    g.add(K.m(decalGeo(pw - 0.02, ph - 0.02), plaqueMat, {'pos': [0, cy, -0.157]}))
    bz = -D / 2 - 0.09 - 0.012
    xf = []
    # bulbs along the gold stripe centerline (pylon tops up; skip the part hidden behind the plaque)
    c, legY0 = GO + GB / 2, PH + 0.3
    pathPts = [[-W / 2 + c, legY0], [-W / 2 + c, H - R]] + \
        arcPts(-W / 2 + R, H - R, R - c, math.pi, math.pi / 2, 16)[1:] + \
        arcPts(W / 2 - R, H - R, R - c, math.pi / 2, 0, 16) + [[W / 2 - c, legY0]]
    for s in resample(pathPts, 0.3):
        if abs(s['p'][0]) < pw / 2 + 0.15 and s['p'][1] > H - 0.7:
            continue
        xf.append({'pos': [s['p'][0], s['p'][1], bz]})
    crestPts = []
    rw, rh, rr = pw / 2 - 0.02, ph / 2 - 0.02, 0.36
    crestPts += arcPts(rw - rr, rh - rr, rr, 0, math.pi / 2, 5) + \
        arcPts(-rw + rr, rh - rr, rr, math.pi / 2, math.pi, 5) + \
        arcPts(-rw + rr, -rh + rr, rr, math.pi, math.pi * 1.5, 5) + \
        arcPts(rw - rr, -rh + rr, rr, math.pi * 1.5, TAU, 5)
    for s in resample(crestPts, 0.28, closed=True):
        xf.append({'pos': [s['p'][0], cy + s['p'][1], -0.28], 'scale': 0.72})
    on = PAL.marqueeGold
    bulbs = instanced(bulbGeo(0.075), K.glow(game, '#ffffff', 1), xf,
                      [hdr(on, 3.2 if i % 3 == 0 else 1.5) for i in range(len(xf))], 'bulbs')
    sockets = instanced(socketGeo(0.075), K.mat(game, 'brass', '#C8963C'),
                        [dict(t, pos=[t['pos'][0], t['pos'][1], t['pos'][2] + 0.035]) for t in xf], None, 'sockets')
    g.add(bulbs, sockets)

    u = g.userData
    u.parts = {'bulbs': bulbs}
    u.chase = {'count': len(xf), 'on': on, 'dim': '#5A3A22'}
    u.colliders = [{'min': [s * (W / 2 - B / 2) - (B + 0.54) / 2, 0, -D / 2 - 0.26],
                    'max': [s * (W / 2 - B / 2) + (B + 0.54) / 2, H, D / 2 + 0.26]} for s in (-1, 1)]
    u.lightAnchors = [
        {'pos': [-W / 2 + 1.4, H - 0.9, -1.2], 'color': PAL.marqueeGold, 'intensity': 2.2, 'distance': 7},
        {'pos': [W / 2 - 1.4, H - 0.9, -1.2], 'color': PAL.marqueeGold, 'intensity': 2.2, 'distance': 7},
    ]
    return K.finish(game, g, {'ao': {'res': 80, 'dist': 0.5}})


registerProp('marquee_arch', _marquee_arch,
             {'category': CAT, 'tags': ['studio_a', 'stage', 'marquee', 'bulbs'], 'size': [14.9, 6.35, 1.2],
              'desc': 'light-bulb marquee arch framing the telethon stage', 'hero': True})

# marqueeChase(prop, t, mode, {speed, bright}): runtime (Godot) — every 3rd bulb runs / flash / on / off / sparkle.


# ---------------------------------------------------------------------------------------- pledge_wheel
# The Wheel of Pledges (ee_prize_wheel / toy_prize_wheel): 4 m vertical prize wheel with 13 painted wedges, brass
# pegs, rim bulbs, a static gold hub with a little perch (Hootie sits there) and a leather flapper.
# parts: wheel (rotate .rotation.z), flapper (pivot at its hinge, rotate .rotation.z), lever (SPIN pull lever).
# anchors.puppet_seat: where the puppet sits (local). Placed as in GDD (pos [4.0,0.6,-29.3], rotY=PI) the SPIN
# lever/interact lands at world [5.8,0.6,-28.8]. userData.wedges: labels clockwise from the top.
WEDGES = ['$13', '$5', '$25', 'DEAD AIR', '$50', '$10', 'BONUS', '$13', '$100', '$20', '$1', 'DOUBLE', '13!']


def _pledge_wheel(game, opts=None):
    g = K.prop('pledge_wheel')
    lac = K.mat(game, 'lacquer', '#ffffff')
    chrome = K.mat(game, 'chrome', '#A8B0BA')
    brass = K.mat(game, 'brass', '#C8963C')
    CY, RW = 2.36, 1.98
    n = len(WEDGES)
    cols = [PAL.channelRed, PAL.harvestGold, PAL.teal, PAL.burntOrange, PAL.plum]

    def draw_face(ctx, w, h, rand):
        cx, cy, R = w / 2, h / 2, w / 2
        for i in range(n):
            a0 = -math.pi / 2 - math.pi / n + (i / n) * TAU
            a1 = a0 + TAU / n
            col = cols[i % len(cols)]
            if WEDGES[i] == 'DEAD AIR':
                col = '#2A1D3A'
            if WEDGES[i] == 'BONUS' or WEDGES[i] == '13!':
                col = '#2F5BD3' if i % 2 else '#8C9A3A'
            gr = ctx.createRadialGradient(cx, cy, R * 0.15, cx, cy, R)
            gr.addColorStop(0, shadeHex(col, -0.25))
            gr.addColorStop(0.55, col)
            gr.addColorStop(0.92, shadeHex(col, 0.12))
            gr.addColorStop(1, shadeHex(col, -0.2))
            ctx.beginPath()
            ctx.moveTo(cx, cy)
            ctx.arc(cx, cy, R, a0, a1)
            ctx.closePath()
            ctx.fillStyle = gr
            ctx.fill()
            # glossy streak
            ctx.save()
            ctx.clip()
            ctx.fillStyle = 'rgba(255,255,255,0.08)'
            ctx.beginPath()
            ctx.moveTo(cx, cy)
            ctx.arc(cx, cy, R, a0, a0 + (a1 - a0) * 0.35)
            ctx.closePath()
            ctx.fill()
            ctx.restore()
            # label along the radius, reading outward
            am = (a0 + a1) / 2
            ctx.save()
            ctx.translate(cx + math.cos(am) * R * 0.6, cy + math.sin(am) * R * 0.6)
            ctx.rotate(am + math.pi)
            lbl = WEDGES[i]
            dark = col == '#2A1D3A'
            text(ctx, lbl, 0, 0, {'font': FONT['sign'] if len(lbl) > 4 else FONT['round'],
                                  'size': 30 if len(lbl) > 4 else 46, 'fill': '#9CFF57' if dark else '#FFF8E6',
                                  'stroke': '#10081A' if dark else shadeHex(col, -0.55), 'lw': 7, 'maxW': R * 0.62,
                                  'shadow': 'rgba(0,0,0,0.25)'})
            if dark:
                text(ctx, '☠', -R * 0.26, 0, {'font': FONT['round'], 'size': 26, 'fill': '#9CFF57'})
            ctx.restore()
        # dividers + dotted border + hub ring
        ctx.strokeStyle = '#FFF4DC'
        ctx.lineWidth = 5
        for i in range(n):
            a = -math.pi / 2 - math.pi / n + (i / n) * TAU
            ctx.beginPath()
            ctx.moveTo(cx + math.cos(a) * R * 0.2, cy + math.sin(a) * R * 0.2)
            ctx.lineTo(cx + math.cos(a) * R, cy + math.sin(a) * R)
            ctx.stroke()
        ctx.beginPath()
        ctx.arc(cx, cy, R * 0.97, 0, TAU)
        ctx.lineWidth = 10
        ctx.strokeStyle = '#3A1E2E'
        ctx.stroke()
        ctx.beginPath()
        ctx.arc(cx, cy, R * 0.24, 0, TAU)
        ctx.fillStyle = '#F6E7C8'
        ctx.fill()
        ctx.lineWidth = 6
        ctx.strokeStyle = '#3A1E2E'
        ctx.stroke()
        for i in range(26):
            a = (i / 26) * TAU
            ctx.beginPath()
            ctx.arc(cx + math.cos(a) * R * 0.2, cy + math.sin(a) * R * 0.2, 4, 0, TAU)
            ctx.fillStyle = PAL.channelRed if i % 2 else PAL.harvestGold
            ctx.fill()
    faceTex = cv('wheel_face', 512, 512, draw_face)
    faceMat = K.mat(game, 'lacquer', '#ffffff', {'map': faceTex})

    # ---- spinning wheel (own group, pre-merged so it stays one draw call per material)
    wheel = THREE.Group()
    wheel.position.set(0, CY, 0)
    body = K.cyl(RW, RW, 0.16, {'bevel': 0.035, 'seg': 48}).clone()
    body.rotateX(-math.pi / 2)
    body.translate(0, 0, 0.08)
    wheel.add(tm(body, lac, PAL.harvestGold))
    wheel.add(K.m(decalGeo(RW * 2 - 0.1, RW * 2 - 0.1), faceMat, {'pos': [0, 0, -0.084]}))

    # replace the square decal by a round one
    def _round_decal():
        c = THREE.CircleGeometry(RW - 0.05, 72)
        c.rotateY(math.pi)
        return c
    wheel.children[1].geometry = _round_decal()
    rim = THREE.TorusGeometry(RW - 0.02, 0.055, 7, 64)
    wheel.add(tm(rim, lac, '#3A1E2E', {'pos': [0, 0, -0.08]}))
    for i in range(n):
        a = math.pi / 2 + math.pi / n - (i / n) * TAU
        peg = K.cyl(0.026, 0.03, 0.13, {'seg': 7, 'bevel': 0.006}).clone()
        peg.rotateX(-math.pi / 2)
        wheel.add(K.m(peg, chrome, {'pos': [math.cos(a) * (RW - 0.02), math.sin(a) * (RW - 0.02), -0.1]}))
    rimBulb = K.glow(game, PAL.marqueeGold, 2.6)
    bg = bulbGeo(0.038)
    for i in range(26):
        a = (i / 26) * TAU + math.pi / 26
        wheel.add(K.m(bg, rimBulb, {'pos': [math.cos(a) * (RW - 0.2), math.sin(a) * (RW - 0.2), -0.09]}))

    def draw_back(ctx, w, h, rand):
        ctx.fillStyle = '#C8A06A'
        ctx.beginPath()
        ctx.arc(128, 128, 128, 0, TAU)
        ctx.fill()
        for i in range(40):
            ctx.strokeStyle = 'rgba(120,80,40,' + js_str(0.1 + rand() * 0.15) + ')'
            ctx.lineWidth = 1 + rand() * 2
            y = rand() * h
            ctx.beginPath()
            ctx.moveTo(0, y)
            ctx.bezierCurveTo(80, y + 6, 170, y - 6, w, y + 3)
            ctx.stroke()
        ctx.fillStyle = '#8A5A34'
        for i in range(4):
            ctx.save()
            ctx.translate(128, 128)
            ctx.rotate(i * math.pi / 4)
            ctx.fillRect(-128, -9, 256, 18)
            ctx.restore()
        ctx.globalAlpha = 0.7
        text(ctx, 'PROPERTY OF WZTV', 128, 190, {'font': FONT['sign'], 'size': 18, 'fill': '#3A2A48'})
        text(ctx, 'STUDIO A - DO NOT SPIN BACKWARDS', 128, 212, {'font': FONT['round'], 'size': 10, 'fill': '#3A2A48'})
        ctx.globalAlpha = 1
    backTex = cv('wheel_back', 256, 256, draw_back)
    wheel.add(K.m(THREE.CircleGeometry(RW - 0.05, 40), K.mat(game, 'paint', '#ffffff', {'map': backTex}),
                  {'pos': [0, 0, 0.162]}))
    K.merge(wheel)
    wheel.userData.noMerge = True
    g.add(wheel)

    # ---- stand: base platform, back post, splayed legs, axle bearing
    g.add(tm(K.box(3.0, 0.34, 1.2, 0.08), lac, PAL.chocolate, {'pos': [0, 0.17, 0.1]}))
    g.add(tm(K.box(3.08, 0.08, 1.28, 0.035), lac, PAL.harvestGold, {'pos': [0, 0.36, 0.1]}))
    g.add(tm(K.box(3.12, 0.05, 1.3, 0.02), lac, '#2A1810', {'pos': [0, 0.025, 0.1]}))

    def draw_sign(ctx, w, h, rand):
        rrect(ctx, 0, 0, w, h, 20)
        ctx.fillStyle = '#F6E7C8'
        ctx.fill()
        ctx.save()
        rrect(ctx, 0, 0, w, h, 20)
        ctx.clip()
        for i, c in enumerate([PAL.channelRed, PAL.harvestGold, PAL.teal]):
            ctx.fillStyle = c
            ctx.fillRect(0, h - 20 + i * 7, w, 5)
        ctx.restore()
        text(ctx, 'WHEEL OF PLEDGES', w / 2, h * 0.42, {'font': FONT['sign'], 'size': 44, 'fill': PAL.channelRed,
                                                        'stroke': '#3A1E2E', 'lw': 6, 'maxW': w * 0.9,
                                                        'shadow': 'rgba(0,0,0,0.2)'})
    signTex = cv('wheel_sign', 512, 96, draw_sign)
    g.add(K.m(decalGeo(2.2, 0.21), K.mat(game, 'lacquer', '#ffffff', {'map': signTex}), {'pos': [0, 0.18, -0.505]}))
    # back post (tapered) + head that carries the flapper
    g.add(tm(K.taper(K.box(0.36, CY + 2.35, 0.26, 0.07), {'axis': 'y', 'k': 0.72}), lac, PAL.teal,
             {'pos': [0, (CY + 2.35) / 2 + 0.3, 0.3]}))
    for s in (-1, 1):
        a, b = V3(s * 1.15, 0.38, 0.35), V3(s * 0.12, CY - 0.2, 0.3)
        leg = K.m(tg(K.taper(K.box(0.2, a.distanceTo(b), 0.16, 0.05), {'axis': 'y', 'k': 0.7}), PAL.teal), lac)
        leg.position.copy(a).add(b).multiplyScalar(0.5)
        leg.quaternion.setFromUnitVectors(UP, b.clone().sub(a).normalize())
        g.add(leg)
        g.add(tm(K.box(0.3, 0.1, 0.26, 0.04), lac, PAL.harvestGold, {'pos': [s * 1.15, 0.42, 0.35]}))
    bearing = K.cyl(0.2, 0.24, 0.2, {'seg': 20, 'bevel': 0.04}).clone()
    bearing.rotateX(math.pi / 2)
    g.add(tm(bearing, lac, PAL.harvestGold, {'pos': [0, CY, 0.12]}))
    # static hub (in front of the wheel) + perch shelf
    hub = K.lathe([[0, 0], [0.4, 0], [0.42, 0.06], [0.36, 0.2], [0.24, 0.26], [0.12, 0.3], [0, 0.31]],
                  {'round': 0.03, 'seg': 24}).clone()
    hub.rotateX(-math.pi / 2)
    g.add(tm(hub, lac, PAL.harvestGold, {'pos': [0, CY, -0.1]}))

    def draw_hub(ctx, w, h, rand):
        ctx.fillStyle = PAL.channelRed
        ctx.beginPath()
        ctx.arc(w / 2, h / 2, w / 2, 0, TAU)
        ctx.fill()
        ctx.fillStyle = PAL.wztvBlue
        ctx.beginPath()
        ctx.arc(w / 2, h / 2, w * 0.4, 0, TAU)
        ctx.fill()
        text(ctx, '13', w / 2, h / 2 + 6, {'font': FONT['round'], 'size': 120, 'fill': '#F4F1E8', 'stroke': '#1B2F7A',
                                           'lw': 10})
    hubCap = cv('wheel_hub', 256, 256, draw_hub)
    capG = THREE.CircleGeometry(0.2, 32)
    capG.rotateY(math.pi)
    g.add(K.m(capG, K.mat(game, 'lacquer', '#ffffff', {'map': hubCap}), {'pos': [0, CY, -0.414]}))
    perch = K.lathe([[0, 0], [0.24, 0], [0.27, 0.04], [0.27, 0.07], [0, 0.07]], {'round': 0.02, 'seg': 24}).clone()
    perch.scale(1, 1, 0.75)
    g.add(tm(perch, lac, PAL.chocolate, {'pos': [0, CY - 0.4, -0.42]}))
    g.add(tm(K.box(0.1, 0.38, 0.1, 0.03), lac, PAL.chocolate, {'pos': [0, CY - 0.57, -0.33]}))

    # flapper on the post head
    g.add(tm(K.box(0.3, 0.2, 0.62, 0.06), lac, PAL.harvestGold, {'pos': [0, CY + RW + 0.3, -0.02]}))
    flapper = THREE.Group()
    flapper.position.set(0, CY + RW + 0.2, -0.2)
    flapper.add(tm(K.extrude([[-0.07, 0], [0.07, 0], [0.03, -0.32], [0, -0.38], [-0.03, -0.32]], 0.04,
                             {'bevel': 0.012, 'round': 0.015}), lac, PAL.channelRed, {'pos': [0, 0, 0]}))
    flapper.add(K.m(K.cyl(0.035, 0.035, 0.14, {'seg': 10}).clone().rotateZ(math.pi / 2), chrome, {'pos': [0.07, 0, 0]}))
    K.merge(flapper)
    flapper.userData.noMerge = True
    g.add(flapper)

    # SPIN pull-lever pedestal (viewer's right)
    LX = -1.78
    g.add(tm(K.taper(K.box(0.42, 0.95, 0.42, 0.06), {'axis': 'y', 'k': 0.8}), lac, PAL.channelRed,
             {'pos': [LX, 0.475, -0.35]}))
    g.add(tm(K.box(0.5, 0.07, 0.5, 0.03), lac, PAL.harvestGold, {'pos': [LX, 0.98, -0.35]}))

    def draw_spin(ctx, w, h, rand):
        rrect(ctx, 0, 0, w, h, 24)
        ctx.fillStyle = '#F6E7C8'
        ctx.fill()
        text(ctx, 'SPIN!', w / 2, h / 2 + 4, {'font': FONT['sign'], 'size': 64, 'fill': PAL.channelRed,
                                              'stroke': '#3A1E2E', 'lw': 6})
    spinTex = cv('wheel_spin', 256, 128, draw_spin)
    g.add(K.m(decalGeo(0.3, 0.15), K.mat(game, 'lacquer', '#ffffff', {'map': spinTex}), {'pos': [LX, 0.65, -0.575]}))
    lever = THREE.Group()
    lever.position.set(LX, 1.02, -0.35)
    lever.add(K.m(K.cyl(0.02, 0.022, 0.5, {'seg': 8}), chrome, {'rot': [0, 0, 0.35]}))
    lever.add(K.m(THREE.SphereGeometry(0.075, 12, 8), lac, {'pos': [-math.sin(0.35) * 0.52, math.cos(0.35) * 0.52, 0]}))
    lever.children[1].geometry = tg(lever.children[1].geometry, PAL.channelRed)
    K.merge(lever)
    lever.userData.noMerge = True
    g.add(lever)

    u = g.userData
    u.parts = {'wheel': wheel, 'flapper': flapper, 'lever': lever}
    u.wedges = WEDGES
    u.anchors = {'puppet_seat': [0, CY - 0.33, -0.44], 'hub': [0, CY, -0.42]}
    u.interact = {'point': [LX, 1.0, -0.6], 'radius': 1.4}
    u.colliders = [{'min': [-1.55, 0, -0.5], 'max': [1.55, CY + RW + 0.2, 0.75]},
                   {'min': [LX - 0.25, 0, -0.6], 'max': [LX + 0.25, 1.1, -0.1]}]
    return K.finish(game, g, {'ao': {'res': 64}})


registerProp('pledge_wheel', _pledge_wheel,
             {'category': CAT, 'tags': ['studio_a', 'stage', 'ee', 'toy', 'wheel'], 'size': [4.0, 4.7, 1.3],
              'desc': 'Wheel of Pledges: 4 m prize wheel with 13 wedges', 'hero': True})


# ---------------------------------------------------------------------------------------- baron_throne
# Deterministic verlet cloth (build time): grid nx*ny, init(u,v)->[x,y,z], pin(i,j)->[x,y,z]|None, colliders = local
# AABBs [{min,max}], floor y=0. Returns an indexed BufferGeometry (uv 0..1).
# p / q are JS Float32Arrays: array('f') stores float32 on every write exactly like them (bit-exact cloth).
def drape(o):
    nx, ny = o.get('nx', 14), o.get('ny', 18)
    init, pin = o['init'], o['pin']
    colliders = o.get('colliders', [])
    iters, relax, gravity = o.get('iters', 220), o.get('relax', 10), o.get('gravity', 9.8)
    floorY, thick = o.get('floorY', 0.012), o.get('thick', 0.02)
    N = nx * ny
    p = array('f', bytes(4 * N * 3))
    q = array('f', bytes(4 * N * 3))
    pinned = [None] * N
    for j in range(ny):
        for i in range(nx):
            k = j * nx + i
            v = init(i / (nx - 1), j / (ny - 1))
            for a in range(3):
                p[k * 3 + a] = v[a]
                q[k * 3 + a] = v[a]
            pp = pin(i, j)
            if pp:
                pinned[k] = pp
    cons = []

    def add(a, b):
        cons.append([a, b, js_hypot(p[a * 3] - p[b * 3], p[a * 3 + 1] - p[b * 3 + 1], p[a * 3 + 2] - p[b * 3 + 2])])
    for j in range(ny):
        for i in range(nx):
            k = j * nx + i
            if i < nx - 1:
                add(k, k + 1)
            if j < ny - 1:
                add(k, k + nx)
            if i < nx - 1 and j < ny - 1:
                add(k, k + nx + 1)
                add(k + 1, k + nx)
            if i < nx - 2:
                add(k, k + 2)
            if j < ny - 2:
                add(k, k + nx * 2)
    dt2 = (1 / 60) ** 2 * gravity
    # pinned[] never changes during the solve: the per-constraint weights are constants (same arithmetic as JS)
    ccons = []
    for a, b, L in cons:
        wa, wb = (0 if pinned[a] else 1), (0 if pinned[b] else 1)
        s = wa + wb
        if not s:
            continue
        ccons.append((a * 3, b * 3, L, wa, wb, s))
    cboxes = [(c['min'][0] - thick, c['max'][0] + thick, c['min'][1] - thick, c['max'][1] + thick,
               c['min'][2] - thick, c['max'][2] + thick) for c in colliders]
    pinned_list = [(k * 3, pinned[k]) for k in range(N) if pinned[k]]
    free = [k * 3 for k in range(N) if not pinned[k]]
    hyp = js_hypot
    for it in range(iters):
        for k in range(N):
            o3 = k * 3
            for a in range(3):
                v = (p[o3 + a] - q[o3 + a]) * 0.97
                q[o3 + a] = p[o3 + a]
                p[o3 + a] += v - (dt2 if a == 1 else 0)
        for r in range(relax):
            for ax, bx, L, wa, wb, s in ccons:
                dx, dy, dz = p[bx] - p[ax], p[bx + 1] - p[ax + 1], p[bx + 2] - p[ax + 2]
                d = hyp(dx, dy, dz) or 1e-6
                f = (d - L) / d
                p[ax] += dx * f * wa / s
                p[ax + 1] += dy * f * wa / s
                p[ax + 2] += dz * f * wa / s
                p[bx] -= dx * f * wb / s
                p[bx + 1] -= dy * f * wb / s
                p[bx + 2] -= dz * f * wb / s
            # (JS walks k in order; pinned vertices only get reset, so resetting them first is equivalent)
            for o3, pv in pinned_list:
                p[o3] = pv[0]
                p[o3 + 1] = pv[1]
                p[o3 + 2] = pv[2]
            for o3 in free:
                if p[o3 + 1] < floorY:
                    p[o3 + 1] = floorY
                    q[o3] = lerp(q[o3], p[o3], 0.6)
                    q[o3 + 2] = lerp(q[o3 + 2], p[o3 + 2], 0.6)
                for x0, x1, y0, y1, z0, z1 in cboxes:
                    x, y, z = p[o3], p[o3 + 1], p[o3 + 2]
                    if x > x0 and x < x1 and y > y0 and y < y1 and z > z0 and z < z1:
                        dd = [x - x0, x1 - x, y - y0, y1 - y, z - z0, z1 - z]
                        bi = 0
                        for t in range(1, 6):
                            if dd[t] < dd[bi]:
                                bi = t
                        ax = bi >> 1
                        sg = 1 if bi & 1 else -1
                        p[o3 + ax] += sg * dd[bi]
    g = THREE.BufferGeometry()
    uv = np.zeros(N * 2)
    idx = []
    for j in range(ny):
        for i in range(nx):
            k = j * nx + i
            uv[k * 2] = i / (nx - 1)
            uv[k * 2 + 1] = 1 - j / (ny - 1)
    for j in range(ny - 1):
        for i in range(nx - 1):
            a = j * nx + i
            b = a + 1
            c = a + nx
            d = c + 1
            idx += [a, c, b, b, c, d]
    g.setAttribute('position', THREE.BufferAttribute(np.array(p, dtype=np.float64), 3))
    g.setAttribute('uv', THREE.BufferAttribute(uv, 2))
    g.setIndex(idx)
    g.computeVertexNormals()
    return g


# The Baron's empty host throne (plum velvet, gothic arched back with antenna crest) with his cape slumped on the
# seat and snagged on a novelty TRAP DOOR lever. GDD pos [-1.5,0.6,-28.3]. parts: lever. anchors.seat.
def _baron_throne(game, opts=None):
    g = K.prop('baron_throne')
    lac = K.mat(game, 'lacquer', '#ffffff')
    brass = K.mat(game, 'brass', '#C8963C')
    chrome = K.mat(game, 'chrome', '#A8B0BA')
    velvet = K.mat(game, 'fabric', '#ffffff', {'map': K.tex.weave('#7A2E6E', {'pattern': 'plain', 'scale': 2})})
    WOOD, GOLD = '#3B2238', '#D9A520'
    SW, SD, SH = 1.04, 0.78, 0.46
    # seat base with a scalloped apron
    g.add(tm(K.box(SW, SH - 0.08, SD, 0.06), lac, WOOD, {'pos': [0, 0.12 + (SH - 0.12) / 2 - 0.02, 0]}))
    g.add(tm(K.box(SW + 0.06, 0.07, SD + 0.06, 0.03), lac, GOLD, {'pos': [0, SH - 0.03, 0]}))
    for i in range(5):
        x = -0.4 + i * 0.2
        g.add(tm(THREE.SphereGeometry(0.05, 10, 8, 0, TAU, 0, math.pi / 2).rotateX(math.pi), lac, GOLD,
                 {'pos': [x, 0.2, -SD / 2 - 0.005]}))
    # ball feet
    for x, z in [[-1, -1], [1, -1], [-1, 1], [1, 1]]:
        g.add(K.m(THREE.SphereGeometry(0.075, 10, 7), brass, {'pos': [x * (SW / 2 - 0.08), 0.075, z * (SD / 2 - 0.08)]}))
        g.add(tm(K.cyl(0.06, 0.07, 0.06, {'seg': 12}), lac, WOOD, {'pos': [x * (SW / 2 - 0.08), 0.13, z * (SD / 2 - 0.08)]}))
    # seat cushion
    g.add(K.m(K.cushion(SW - 0.14, 0.16, SD - 0.12, {'puff': 0.03, 'uv': 3}), velvet, {'pos': [0, SH + 0.07, -0.03]}))

    # gothic back: extruded pointed arch + tufted velvet inset + buttons
    def backShape(w, h0, h1):
        s = THREE.Shape()
        s.moveTo(-w / 2, 0)
        s.lineTo(w / 2, 0)
        s.lineTo(w / 2, h0)
        s.quadraticCurveTo(w / 2, h0 + (h1 - h0) * 0.55, 0, h1)
        s.quadraticCurveTo(-w / 2, h0 + (h1 - h0) * 0.55, -w / 2, h0)
        s.closePath()
        return s
    BZ = SD / 2 - 0.09
    g.add(tm(K.extrude(backShape(SW, 1.25, 1.95), 0.18, {'bevel': 0.05, 'bevelSeg': 2, 'curveSeg': 10}), lac, WOOD,
             {'pos': [0, SH, BZ]}))
    g.add(tm(K.extrude(backShape(SW + 0.06, 1.27, 2.0), 0.08, {'bevel': 0.03, 'bevelSeg': 2, 'curveSeg': 10}), lac,
             '#2A1828', {'pos': [0, SH - 0.01, BZ + 0.08]}))
    outline = [[v.x, SH + v.y, BZ - 0.09] for v in backShape(SW - 0.02, 1.24, 1.93).getPoints(8)]
    g.add(tm(K.tube(outline[1:], 0.022, {'seg': 48, 'radial': 6}), lac, GOLD))
    inset = K.extrude(backShape(SW - 0.24, 1.08, 1.72), 0.12, {'bevel': 0.05, 'bevelSeg': 2, 'curveSeg': 10})
    K.uvScale(inset, 3, 3)
    g.add(K.m(inset, velvet, {'pos': [0, SH + 0.1, BZ - 0.1]}))
    for r in range(4):
        for c in range(3 - (r % 2)):
            x, y = (c - (2 - (r % 2)) / 2) * 0.24, SH + 0.36 + r * 0.3
            g.add(K.m(THREE.SphereGeometry(0.022, 6, 4), brass, {'pos': [x, y, BZ - 0.165]}))
    # spires at the shoulders + crest: medallion with a static bolt and rabbit-ear antennas
    for s in (-1, 1):
        g.add(tm(K.lathe([[0, 0], [0.07, 0], [0.08, 0.05], [0.05, 0.1], [0.06, 0.16], [0.03, 0.26], [0, 0.34]],
                         {'round': 0.015, 'seg': 10, 'steps': 1}), lac, GOLD, {'pos': [s * (SW / 2 - 0.02), SH + 1.25, BZ]}))

    def draw_medal(ctx, w, h, rand):
        ctx.fillStyle = '#2A1030'
        ctx.beginPath()
        ctx.arc(w / 2, h / 2, w / 2, 0, TAU)
        ctx.fill()
        ctx.fillStyle = grad(ctx, 0, 0, 0, h, ['#B08ADA', '#6B3A6E'])
        ctx.beginPath()
        ctx.arc(w / 2, h / 2, w * 0.42, 0, TAU)
        ctx.fill()
        poly(ctx, [[150, 30], [90, 135], [130, 135], [100, 226], [175, 110], [132, 110]])
        ctx.fillStyle = '#9CFF57'
        ctx.fill()
        ctx.lineWidth = 8
        ctx.strokeStyle = '#1E1030'
        ctx.stroke()
    medal = cv('throne_medal', 256, 256, draw_medal)
    mg = THREE.CircleGeometry(0.15, 28)
    mg.rotateY(math.pi)
    g.add(tm(K.cyl(0.18, 0.18, 0.06, {'seg': 20, 'bevel': 0.02}).clone().rotateX(-math.pi / 2), lac, GOLD,
             {'pos': [0, SH + 1.72, BZ - 0.1]}))
    g.add(K.m(mg, K.mat(game, 'lacquer', '#ffffff', {'map': medal}), {'pos': [0, SH + 1.72, BZ - 0.162]}))
    for s in (-1, 1):
        a, b = V3(s * 0.05, SH + 1.93, BZ), V3(s * 0.34, SH + 2.42, BZ + 0.04)
        g.add(rod(0.014, chrome, a, b, 8))
        g.add(tm(THREE.SphereGeometry(0.035, 12, 8), lac, PAL.channelRed, {'pos': b.toArray()}))
    g.add(tm(THREE.SphereGeometry(0.06, 10, 7), lac, GOLD, {'pos': [0, SH + 1.95, BZ]}))
    # armrests with scroll ends
    for s in (-1, 1):
        x = s * (SW / 2 - 0.03)
        g.add(tm(K.box(0.14, 0.34, 0.14, 0.04), lac, WOOD, {'pos': [x, SH + 0.17, -SD / 2 + 0.1]}))
        g.add(tm(K.box(0.16, 0.08, SD - 0.02, 0.035), lac, WOOD, {'pos': [x, SH + 0.36, 0.0]}))
        g.add(K.m(K.cushion(0.12, 0.05, SD - 0.18, {'puff': 0.012}), velvet, {'pos': [x, SH + 0.42, 0.04]}))
        scroll = THREE.TorusGeometry(0.075, 0.035, 6, 12)
        scroll.rotateY(math.pi / 2)
        g.add(tm(scroll, lac, GOLD, {'pos': [x, SH + 0.36, -SD / 2 - 0.02]}))
    # novelty TRAP DOOR lever (viewer's left of the throne, prop +x)
    LX, LZ = 0.98, -0.28
    g.add(tm(K.taper(K.box(0.24, 0.56, 0.24, 0.05), {'axis': 'y', 'k': 0.75}), lac, WOOD, {'pos': [LX, 0.28, LZ]}))
    g.add(tm(K.box(0.3, 0.06, 0.3, 0.025), lac, GOLD, {'pos': [LX, 0.58, LZ]}))
    g.add(tm(K.box(0.3, 0.06, 0.3, 0.025), lac, GOLD, {'pos': [LX, 0.03, LZ]}))

    def draw_trap(ctx, w, h, rand):
        rrect(ctx, 0, 0, w, h, 18)
        ctx.fillStyle = '#F4E03A'
        ctx.fill()
        ctx.save()
        rrect(ctx, 0, 0, w, h, 18)
        ctx.clip()
        for i in range(-4, 12):
            ctx.fillStyle = '#2A1D3A'
            ctx.beginPath()
            ctx.moveTo(i * 36, h)
            ctx.lineTo(i * 36 + 18, h)
            ctx.lineTo(i * 36 + 48, h - 30)
            ctx.lineTo(i * 36 + 30, h - 30)
            ctx.fill()
        ctx.restore()
        text(ctx, 'TRAP DOOR', w / 2, 48, {'font': FONT['sign'], 'size': 38, 'fill': '#2A1D3A', 'maxW': w * 0.86})
        text(ctx, 'DO NOT PULL!', w / 2, 92, {'font': FONT['round'], 'size': 26, 'fill': PAL.channelRed, 'maxW': w * 0.8})
    trap = cv('throne_trap', 256, 160, draw_trap)
    g.add(K.m(decalGeo(0.19, 0.12), K.mat(game, 'lacquer', '#ffffff', {'map': trap}), {'pos': [LX, 0.36, LZ - 0.112]}))
    lever = THREE.Group()
    lever.position.set(LX, 0.62, LZ)
    la = 0.5
    lever.add(K.m(K.cyl(0.018, 0.02, 0.48, {'seg': 8}), chrome, {'rot': [-la, 0, 0]}))
    knobPos = [0, math.cos(la) * 0.5, -math.sin(la) * 0.5]
    lever.add(tm(THREE.SphereGeometry(0.06, 10, 7), lac, PAL.channelRed, {'pos': knobPos}))
    lever.add(K.m(K.cyl(0.05, 0.05, 0.05, {'seg': 12}).clone().rotateZ(math.pi / 2), brass, {'pos': [0.025, 0, 0]}))
    K.merge(lever)
    lever.userData.noMerge = True
    g.add(lever)
    # the cape: slumped on the seat, spilling to the floor, one corner hooked on the lever knob
    knobW = V3(LX, 0.62 + knobPos[1], LZ + knobPos[2])
    nx, ny, CW, CL = 14, 20, 1.45, 2.35
    cols = [
        {'min': [-SW / 2 + 0.04, 0, -SD / 2 + 0.02], 'max': [SW / 2 - 0.04, SH + 0.14, SD / 2 - 0.02]},
        {'min': [-SW / 2 + 0.05, SH, BZ - 0.16], 'max': [SW / 2 - 0.05, SH + 1.2, SD / 2]},
        {'min': [SW / 2 - 0.12, 0, -SD / 2], 'max': [SW / 2 + 0.06, SH + 0.44, SD / 2]},
        {'min': [-SW / 2 - 0.06, 0, -SD / 2], 'max': [-SW / 2 + 0.12, SH + 0.44, SD / 2]},
        {'min': [LX - 0.13, 0, LZ - 0.13], 'max': [LX + 0.13, 0.6, LZ + 0.13]},
    ]
    collarY, collarZ = SH + 1.02, BZ - 0.19

    def init(u_, v_):
        x = (u_ - 0.5) * CW * (0.75 + v_ * 0.4)
        s = v_ * CL
        s1 = collarY - (SH + 0.16)
        s2 = s1 + 0.62
        if s < s1:
            return [x * 0.8, collarY - s, collarZ]
        if s < s2:
            return [x, SH + 0.17, collarZ - (s - s1)]
        return [x, max(0.02, SH + 0.17 - (s - s2)), collarZ - (s2 - s1) - 0.05]

    def pin(i, j):
        if j == 0:
            return [((i / (nx - 1)) - 0.5) * CW * 0.62, collarY + math.sin((i / (nx - 1)) * math.pi) * 0.04,
                    collarZ - math.sin((i / (nx - 1)) * math.pi) * 0.03]
        if i == nx - 1 and j == js_round((ny - 1) * 0.62):
            return knobW.toArray()
        return None
    capeGeo = drape({'nx': nx, 'ny': ny, 'colliders': cols, 'init': init, 'pin': pin})
    capeOut = K.mat(game, 'lacquer', '#2A1A3A', {'side': THREE.BackSide, 'rim': 0.3, 'rimColor': '#B08ADA'})
    capeIn = K.mat(game, 'lacquer', '#C8283C', {'side': THREE.FrontSide})
    g.add(K.m(capeGeo, capeOut), K.m(capeGeo, capeIn))
    # stand-up collar (half cone behind the collar line)
    collar = THREE.CylinderGeometry(0.5, 0.28, 0.42, 12, 1, True, -math.pi * 0.55, math.pi * 1.1)
    p = collar.attributes.position
    for i in range(p.count):
        if p.getY(i) > 0:
            a = math.atan2(p.getX(i), p.getZ(i))
            p.setY(i, p.getY(i) + abs(math.sin(a * 3)) * 0.06)
    collar.computeVertexNormals()
    cIn = K.m(collar, capeIn, {'pos': [0, collarY + 0.2, collarZ + 0.02]})
    cOut = K.m(collar, capeOut, {'pos': [0, collarY + 0.2, collarZ + 0.02]})
    cIn.rotation.x = -0.2
    cOut.rotation.x = -0.2
    g.add(cIn, cOut)

    u = g.userData
    u.parts = {'lever': lever}
    u.anchors = {'seat': [0, SH + 0.16, -0.05]}
    u.colliders = [{'min': [-SW / 2 - 0.06, 0, -SD / 2 - 0.08], 'max': [SW / 2 + 0.06, SH + 2.0, SD / 2 + 0.05]},
                   {'min': [LX - 0.16, 0, LZ - 0.16], 'max': [LX + 0.16, 0.95, LZ + 0.16]}]
    return K.finish(game, g, {'ao': {'res': 60}})


registerProp('baron_throne', _baron_throne,
             {'category': CAT, 'tags': ['studio_a', 'stage', 'baron', 'chair'], 'size': [1.4, 2.9, 1.1],
              'desc': 'the Baron empty host throne, cape snagged on a TRAP DOOR lever', 'hero': True})


# ---------------------------------------------------------------------------------------- contestant_podium
# 70s game-show contestant podium: tapered body, chaser-bulb frame, buzzer, flip-digit score (tote atlas).
# opts: { num=1..3, color, score='$130' }. parts: score (strip mesh; setPodiumScore(prop, '$250')), buzzer.
def _contestant_podium(game, opts=None):
    opts = opts or {}
    num = _nn(opts.get('num'), 1)
    g = K.prop('contestant_podium')
    ci = int(math.fmod(num - 1, 3))
    col = _nn(opts.get('color'), [PAL.channelRed, PAL.harvestGold, PAL.teal][ci] if 0 <= ci < 3 else None)
    lac = K.mat(game, 'lacquer', '#ffffff')
    chrome = K.mat(game, 'chrome', '#A8B0BA')
    Wd, Hh, Dd = 0.84, 1.02, 0.58
    g.add(tm(K.box(Wd + 0.12, 0.1, Dd + 0.12, 0.014), lac, PAL.chocolate, {'pos': [0, 0.05, 0]}))
    g.add(tm(K.taper(K.box(Wd, Hh - 0.12, Dd, 0.07), {'axis': 'y', 'k': 1.14}), lac, col,
             {'pos': [0, 0.1 + (Hh - 0.12) / 2, 0]}))
    # wrap-around racing stripes
    for i in range(3):
        g.add(tm(K.box(Wd * (1.02 + i * 0.03), 0.045, Dd * (1.02 + i * 0.03), 0.014), lac,
                 [PAL.cream, PAL.burntOrange, PAL.chocolate][i], {'pos': [0, 0.26 + i * 0.07, 0]}))
    # counter top + buzzer
    g.add(tm(K.box(Wd * 1.2, 0.08, Dd * 1.18, 0.035), lac, PAL.harvestGold, {'pos': [0, Hh + 0.02, -0.01]}))
    g.add(tm(K.box(Wd * 1.14, 0.03, Dd * 1.1, 0.012), lac, PAL.chocolate, {'pos': [0, Hh + 0.07, -0.01]}))
    g.add(K.m(K.cyl(0.1, 0.11, 0.035, {'seg': 14, 'bevel': 0.01}), chrome, {'pos': [0.18, Hh + 0.08, 0.02]}))
    buzzer = K.m(tg(K.lathe([[0, 0], [0.085, 0], [0.085, 0.02], [0.07, 0.06], [0.03, 0.085], [0, 0.09]],
                            {'round': 0.01, 'seg': 14, 'steps': 1}), PAL.channelRed), lac,
                 {'pos': [0.18, Hh + 0.11, 0.02]})
    buzzer.userData.noMerge = True
    g.add(buzzer)
    # front number plate + chaser frame
    fz = -Dd * 1.07 / 2

    def draw_plate(ctx, w, h, rand):
        rrect(ctx, 0, 0, w, h, 26)
        ctx.fillStyle = PAL.cream
        ctx.fill()
        ctx.save()
        rrect(ctx, 0, 0, w, h, 26)
        ctx.clip()
        for i, c in enumerate([PAL.burntOrange, PAL.harvestGold, PAL.channelRed]):
            ctx.fillStyle = c
            ctx.fillRect(0, h - 40 + i * 12, w, 9)
        ctx.restore()
        st = starPts(w / 2, 78, 64, 28, 5)
        poly(ctx, st)
        ctx.fillStyle = grad(ctx, 0, 14, 0, 142, ['#FFF2B0', '#FFC23A', '#E8862A'])
        ctx.fill()
        ctx.lineWidth = 6
        ctx.strokeStyle = '#6A3A12'
        ctx.stroke()
        text(ctx, js_str(num), w / 2, 88, {'font': FONT['round'], 'size': 64, 'fill': '#3A1E2E'})
        text(ctx, 'CONTESTANT', w / 2, 158, {'font': FONT['sign'], 'size': 20, 'fill': '#3A1E2E', 'maxW': w * 0.8})
    plateTex = cv('podium_plate_%s' % js_str(num), 256, 192, draw_plate)
    g.add(tm(K.box(0.56, 0.44, 0.04, 0.012), lac, PAL.chocolate, {'pos': [0, 0.6, fz - 0.02]}))
    g.add(K.m(decalGeo(0.46, 0.345), K.mat(game, 'lacquer', '#ffffff', {'map': plateTex}), {'pos': [0, 0.6, fz - 0.043]}))
    frame = []
    for i in range(7):
        frame.append([-0.25 + i * (0.5 / 6), 0.6 + 0.2])
    for i in range(1, 4):
        frame.append([-0.25, 0.8 - i * 0.1])
    for i in range(6, -1, -1):
        frame.append([-0.25 + i * (0.5 / 6), 0.6 - 0.2])
    for i in range(1, 4):
        frame.append([0.25, 0.4 + i * 0.1])
    bulbs = instanced(bulbGeo(0.017), K.glow(game, '#ffffff', 1), [{'pos': [x, y, fz - 0.045]} for x, y in frame],
                      [hdr(PAL.marqueeGold, 2.8 if i % 2 else 1.4) for i in range(len(frame))], 'bulbs')
    g.add(bulbs)
    # score window (flip digits)
    score = _nn(opts.get('score'), '$130')
    bez = K.extrude(K.roundRect(0.62, 0.22, 0.05), 0.05, {'bevel': 0.015})
    g.add(tm(bez, lac, '#2A1810', {'pos': [0, Hh - 0.14, fz - 0.03]}))
    strip = K.m(toteStripGeo(score, 0.11, 0.145, 0.125), K.glow(game, '#ffffff', 1.05, {'map': getCard('tote_digits')}),
                {'pos': [0, Hh - 0.14, fz - 0.056]})
    strip.userData.noMerge = True
    g.add(strip)
    u = g.userData
    u.parts = {'score': strip, 'buzzer': buzzer, 'bulbs': bulbs}
    u.chase = {'count': len(frame), 'on': PAL.marqueeGold, 'dim': '#5A3A22'}
    u.score = score
    u.colliders = [{'min': [-0.52, 0, -0.4], 'max': [0.52, Hh + 0.1, 0.4]}]
    return K.finish(game, g, {'ao': {'res': 48}})


registerProp('contestant_podium', _contestant_podium,
             {'category': CAT, 'tags': ['studio_a', 'stage', 'podium', 'game_show'], 'size': [1.0, 1.15, 0.72],
              'desc': 'game-show contestant podium with flip-digit score', 'cache': False})

# setPodiumScore(prop, str): runtime (Godot) — writeStripUV(strip geometry, padded string).


# ---------------------------------------------------------------------------------------- ghost_light
# Theatre ghost light (toy_ghost_light): caged bare bulb on a pipe stand with a weighted caster base, taped cord.
# parts.bulb (setGhostLight(prop, on, game)). lightAnchors[0] = the bulb (warm #FFE0A8).
def _ghost_light(game, opts=None):
    g = K.prop('ghost_light')
    lac = K.mat(game, 'lacquer', '#ffffff')
    chrome = K.mat(game, 'chrome', '#A8B0BA')
    brass = K.mat(game, 'brass', '#C8963C')
    rubber = K.mat(game, 'rubber', '#2A2230')
    BY = 1.72
    g.add(tm(K.lathe([[0, 0.06], [0.3, 0.06], [0.32, 0.09], [0.3, 0.13], [0.2, 0.16], [0.07, 0.19], [0.05, 0.25],
                      [0, 0.25]], {'round': 0.02, 'seg': 20, 'steps': 1}), lac, '#3A2A48'))
    for i in range(3):
        a = (i / 3) * TAU + 0.5
        x, z = math.cos(a) * 0.24, math.sin(a) * 0.24
        g.add(K.m(K.cyl(0.03, 0.03, 0.03, {'seg': 8}), chrome, {'pos': [x, 0.045, z]}))
        wh = K.cyl(0.03, 0.03, 0.022, {'seg': 12, 'bevel': 0.008}).clone()
        wh.rotateZ(math.pi / 2)
        wh.rotateY(a)
        g.add(K.m(wh, rubber, {'pos': [x, 0.03, z]}))
    g.add(K.m(K.cyl(0.022, 0.022, BY - 0.35, {'seg': 12}), chrome, {'pos': [0, 0.22, 0]}))
    g.add(K.m(K.lathe([[0, 0], [0.034, 0], [0.036, 0.02], [0.036, 0.06], [0.03, 0.08], [0, 0.08]],
                      {'round': 0.01, 'seg': 12}), chrome, {'pos': [0, 0.95, 0]}))

    # tape band with label
    def draw_tape(ctx, w, h, rand):
        ctx.fillStyle = '#E8E0C8'
        ctx.fillRect(0, 0, w, h)
        ctx.fillStyle = 'rgba(0,0,0,0.06)'
        for i in range(40):
            ctx.fillRect(i * 7, 0, 1, h)
        text(ctx, 'GHOST LIGHT · DO NOT UNPLUG', w / 2, h / 2 + 2, {'font': FONT['hand'], 'size': 22,
                                                                         'fill': '#2A2A8A', 'maxW': w * 0.95,
                                                                         'rot': -0.02})
    tape = cv('ghost_tape', 256, 64, draw_tape)
    tapeG = THREE.CylinderGeometry(0.027, 0.027, 0.09, 16, 1, True)
    g.add(K.m(tapeG, K.mat(game, 'paint', '#ffffff', {'map': tape}), {'pos': [0, 1.25, 0]}))
    # socket + bulb + cage
    g.add(K.m(K.lathe([[0, 0], [0.03, 0], [0.042, 0.03], [0.045, 0.1], [0.036, 0.12], [0, 0.12]],
                      {'round': 0.01, 'seg': 14}), brass, {'pos': [0, BY - 0.18, 0]}))
    bulb = K.m(K.lathe([[0, 0], [0.024, 0.005], [0.03, 0.03], [0.07, 0.09], [0.078, 0.13], [0.06, 0.19], [0, 0.205]],
                       {'round': 0.02, 'seg': 18}), K.glow(game, '#FFE0A8', 4.5), {'pos': [0, BY - 0.07, 0], 'cast': False})
    bulb.userData.noMerge = True
    bulb.userData.noOcclude = True
    g.add(bulb)
    cageR, cy0, cy1 = 0.13, BY - 0.09, BY + 0.2
    for i in range(6):
        a = (i / 6) * TAU
        pts = [[math.cos(a) * 0.05, cy0, math.sin(a) * 0.05], [math.cos(a) * cageR, cy0 + 0.07, math.sin(a) * cageR],
               [math.cos(a) * cageR, cy1 - 0.07, math.sin(a) * cageR], [math.cos(a) * 0.03, cy1, math.sin(a) * 0.03]]
        g.add(K.m(K.tube(pts, 0.005, {'seg': 12, 'radial': 4}), chrome))
    g.add(K.m(K.tube(ringPts(cageR, 18, 0), 0.006, {'seg': 24, 'radial': 4, 'closed': True}), chrome,
              {'pos': [0, BY + 0.06, 0]}))
    g.add(K.m(K.tube([[-0.06, 0, 0], [-0.06, 0.07, 0], [0.06, 0.07, 0], [0.06, 0, 0]], 0.008, {'seg': 14, 'radial': 5}),
              chrome, {'pos': [0, cy1, 0]}))
    # cord down the pole, coiled on the floor, plug
    cord = [[0.03, BY - 0.12, 0], [0.035, 1.3, 0.005], [0.03, 0.6, 0.02], [0.08, 0.26, 0.05], [0.28, 0.02, 0.12]]
    for i in range(10):
        a = i * 0.7
        cord.append([0.45 + math.cos(a) * 0.16, 0.012 + i * 0.001, 0.1 + math.sin(a) * 0.11])
    cord += [[0.7, 0.012, -0.05], [0.85, 0.012, -0.12]]
    g.add(K.m(K.tube(cord, 0.009, {'seg': 34, 'radial': 4}), rubber))
    g.add(tm(K.box(0.05, 0.03, 0.07, 0.01), lac, '#E8E0C8', {'pos': [0.87, 0.016, -0.14]}))
    u = g.userData
    u.parts = {'bulb': bulb}
    u.lightAnchors = [{'pos': [0, BY + 0.03, 0], 'color': '#FFE0A8', 'intensity': 3, 'distance': 8}]
    u.colliders = [{'min': [-0.2, 0, -0.2], 'max': [0.2, BY + 0.28, 0.2]}]
    u.interact = {'point': [0, 1.0, -0.2], 'radius': 1.2}
    return K.finish(game, g, {'ao': {'res': 48}})


registerProp('ghost_light', _ghost_light,
             {'category': CAT, 'tags': ['studio_a', 'stage', 'toy', 'light'], 'size': [0.64, 2.0, 0.64],
              'desc': 'caged bare-bulb ghost light on a caster stand', 'hero': True})

# setGhostLight(prop, on, game): runtime (Godot) — off = K.mat(game, 'ceramic', '#E8E0D0') frosted glass.


# ---------------------------------------------------------------------------------------- pledge_carousel
# The Carousel: round telethon pledge desk (outer radius 2.0 m, 1.0 m tall, ring open in the middle for the
# tote_board_tower) with 12 rotary phones facing out, pledge slips and a ring lamp per phone.
# parts.handsets: InstancedMesh(12) (base matrices in userData.phones), parts.lamps: InstancedMesh(12).
# ringPhone(prop, i, t) rattles handset i and blinks its lamp (call per frame while ringing; t = seconds).
def _pledge_carousel(game, opts=None):
    g = K.prop('pledge_carousel')
    RO, RI, H = 2.0, 1.2, 1.0
    lac = K.mat(game, 'lacquer', '#ffffff')
    chrome = K.mat(game, 'chrome', '#A8B0BA')
    plastic = K.mat(game, 'plastic', '#ffffff')

    def draw_atlas(ctx, w, h, rand):
        # [0,0]-[256,256]: rotary dial face
        cx, cy = 128, 128
        ctx.fillStyle = '#F4F1E8'
        ctx.beginPath()
        ctx.arc(cx, cy, 124, 0, TAU)
        ctx.fill()
        ctx.strokeStyle = '#B8B0A0'
        ctx.lineWidth = 4
        ctx.stroke()
        for i in range(10):
            a = -math.pi * 0.35 - (i / 10) * math.pi * 1.55
            x, y = cx + math.cos(a) * 84, cy + math.sin(a) * 84
            ctx.fillStyle = '#2A2230'
            ctx.beginPath()
            ctx.arc(x, y, 22, 0, TAU)
            ctx.fill()
            ctx.fillStyle = '#F6E7C8'
            ctx.beginPath()
            ctx.arc(x, y, 17, 0, TAU)
            ctx.fill()
            text(ctx, js_str((i + 1) % 10), x, y + 1, {'font': FONT['round'], 'size': 20, 'fill': '#2A2230'})
        ctx.fillStyle = PAL.channelRed
        ctx.beginPath()
        ctx.arc(cx, cy, 34, 0, TAU)
        ctx.fill()
        text(ctx, '13', cx, cy + 2, {'font': FONT['round'], 'size': 30, 'fill': '#F4F1E8'})
        # [256,0]-[512,256]: pledge slip
        ctx.fillStyle = '#FFFBEF'
        ctx.fillRect(256, 0, 256, 256)
        ctx.fillStyle = PAL.channelRed
        ctx.fillRect(256, 0, 256, 40)
        text(ctx, 'PLEDGE', 384, 22, {'font': FONT['sign'], 'size': 26, 'fill': '#fff'})
        ctx.fillStyle = 'rgba(60,90,200,0.35)'
        y = 70
        while y < 250:
            ctx.fillRect(270, y, 228, 2)
            y += 26
        text(ctx, '$13', 330, 110, {'font': FONT['hand'], 'size': 34, 'fill': '#2A2A8A', 'rot': -0.1})
        # [0,256]-[512,448]: apron band (repeats around)
        by, bh = 256, 192
        ctx.fillStyle = PAL.cream
        ctx.fillRect(0, by, w, bh)
        for c, yy, hh in [[PAL.chocolate, 0, 10], [PAL.burntOrange, 12, 14], [PAL.harvestGold, 28, 10]]:
            ctx.fillStyle = c
            ctx.fillRect(0, by + yy, w, hh)
            ctx.fillRect(0, by + bh - yy - hh, w, hh)
        for i in range(2):
            x0 = i * 256 + 128
            ctx.fillStyle = PAL.wztvBlue
            ctx.beginPath()
            ctx.arc(x0 - 70, by + bh / 2, 38, 0, TAU)
            ctx.fill()
            ctx.strokeStyle = PAL.channelRed
            ctx.lineWidth = 8
            ctx.stroke()
            text(ctx, '13', x0 - 70, by + bh / 2 + 3, {'font': FONT['round'], 'size': 40, 'fill': '#F4F1E8'})
            text(ctx, 'PLEDGE', x0 + 38, by + bh / 2 - 14, {'font': FONT['sign'], 'size': 34, 'fill': PAL.channelRed,
                                                             'maxW': 140})
            text(ctx, 'NOW!', x0 + 38, by + bh / 2 + 24, {'font': FONT['groovy'], 'size': 30, 'fill': PAL.burntOrange,
                                                           'maxW': 120})
    atlas = cv('carousel_atlas', 512, 512, draw_atlas)
    atlas.wrapS = THREE.RepeatWrapping
    atlasMat = K.mat(game, 'lacquer', '#ffffff', {'map': atlas})
    # plinth, apron band, counter top, inner wall
    g.add(tm(K.lathe([[RI + 0.1, 0], [RO - 0.08, 0], [RO - 0.06, 0.1], [RI + 0.1, 0.1]], {'seg': 64}), lac, '#2A1810'))
    band = THREE.CylinderGeometry(RO - 0.03, RO - 0.03, 0.76, 72, 1, True)
    K.uvRect(band, 0, 64 / 512, 1, 256 / 512)
    K.uvScale(band, 6, 1)
    g.add(K.m(band, atlasMat, {'pos': [0, 0.1 + 0.38, 0]}))
    g.add(tm(K.lathe([[RO - 0.06, 0.08], [RO + 0.02, 0.1], [RO + 0.02, 0.14], [RO - 0.06, 0.15]],
                     {'round': 0.02, 'seg': 64}), lac, PAL.harvestGold))
    g.add(tm(K.lathe([[RI - 0.04, H - 0.07], [RO + 0.07, H - 0.07], [RO + 0.1, H - 0.05], [RO + 0.1, H - 0.02],
                      [RO + 0.07, H], [RI - 0.02, H], [RI - 0.05, H - 0.02], [RI - 0.05, H - 0.05], [RI - 0.04, H - 0.07]],
                     {'seg': 48}), lac, PAL.burntOrange))
    g.add(K.m(K.tube(ringPts(RO + 0.1, 40), 0.022, {'seg': 64, 'radial': 5, 'closed': True}), chrome,
              {'pos': [0, H - 0.035, 0]}))
    g.add(tm(K.lathe([[RI, H - 0.07], [RI, 0.02]], {'seg': 48}), lac, PAL.teal))
    g.add(tm(K.lathe([[RO - 0.03, 0.86], [RO + 0.01, 0.88], [RO + 0.01, 0.93], [RO - 0.03, 0.93]], {'seg': 64}), lac,
             PAL.chocolate))

    # phone parts (built once, cloned per station)
    bodyG = K.taper(K.box(0.22, 0.1, 0.25, 0.035), {'axis': 'y', 'k': 0.72})
    bodyG.translate(0, 0.05, 0)
    humpG = K.box(0.15, 0.05, 0.12, 0.014).clone()
    humpG.translate(0, 0.11, 0.035)
    dialG = THREE.CircleGeometry(0.056, 20)
    dialG.rotateY(math.pi)
    K.uvRect(dialG, 0, 0.5, 0.5, 1)
    slipG = K.uvRect(decalGeo(0.1, 0.13), 0.5, 0.5, 1, 1).rotateX(-math.pi / 2)
    prongG = K.box(0.026, 0.05, 0.03, 0.006)  # noqa: F841  (unused in the JS too)
    # handset (instanced): grip + ear/mouth cups, lying along x
    hsParts = [K.tube([[-0.1, 0, 0], [-0.05, 0.025, 0], [0.05, 0.025, 0], [0.1, 0, 0]], 0.019,
                      {'seg': 10, 'radial': 7}).clone()]
    for s in (-1, 1):
        cup = K.lathe([[0, 0], [0.036, 0], [0.038, 0.02], [0.02, 0.045], [0, 0.046]], {'round': 0.008, 'seg': 12}).clone()
        cup.rotateX(math.pi)
        cup.translate(s * 0.1, 0.012, 0)
        hsParts.append(cup)
    hsGeo = mergeGeos(hsParts)
    colors = [PAL.cream, PAL.channelRed, PAL.harvestGold, PAL.cream, '#2A2230', PAL.avocado]
    phones, hsXf, lampXf = [], [], []
    for i in range(12):
        th = (i / 12) * TAU + math.pi / 12
        rot = -th - math.pi / 2
        st = THREE.Group()
        st.position.set(math.cos(th) * 1.6, H, math.sin(th) * 1.6)
        st.rotation.y = rot
        st.scale.setScalar(1.22)
        c = colors[i % len(colors)]
        st.add(tm(bodyG, plastic, c), tm(humpG, plastic, c))
        dial = K.m(dialG, atlasMat, {'pos': [0, 0.075, -0.098]})
        dial.rotation.x = 0.62
        st.add(dial)
        slip = K.m(slipG, atlasMat, {'pos': [0.2, 0.004, -0.02]})
        slip.rotation.y = 0.2 * ((i % 3) - 1)
        st.add(slip)
        # coiled cord from the body side to the handset end
        cord = []
        a0, a1, a2, a3 = V3(-0.11, 0.03, 0.0), V3(-0.2, 0.02, 0.02), V3(-0.16, 0.1, 0.05), V3(-0.1, 0.15, 0.035)
        curve = THREE.CubicBezierCurve3(a0, a1, a2, a3)
        for k in range(27):
            t = k / 26
            p = curve.getPoint(t)
            a = t * TAU * 6
            cord.append([p.x + math.cos(a) * 0.009, p.y + math.sin(a) * 0.009, p.z])
        st.add(tm(K.tube(cord, 0.0045, {'seg': 18, 'radial': 3}), plastic, '#2A2230'))
        st.add(K.m(K.cyl(0.006, 0.008, 0.16, {'seg': 6}), chrome, {'pos': [-0.13, 0, -0.08]}))
        g.add(st)
        st.updateMatrix()
        hp = V3(0, 0.165, 0.035).applyMatrix4(st.matrix)
        hq = THREE.Quaternion().setFromEuler(THREE.Euler(0, rot, 0))
        hsXf.append({'pos': hp.toArray(), 'quat': hq, 'scale': 1.22})
        phones.append({'pos': hp.toArray(), 'rotY': rot, 'color': c})
        lampXf.append({'pos': V3(-0.13, 0.17, -0.08).applyMatrix4(st.matrix).toArray(), 'scale': 1.2})
    handsets = instanced(hsGeo, plastic, hsXf, [ph['color'] for ph in phones], 'handsets')
    lampGeo = THREE.SphereGeometry(0.028, 10, 8)
    lamps = instanced(lampGeo, K.glow(game, '#ffffff', 1), lampXf,
                      [hdr(PAL.onAirRed, 3 if i % 4 == 1 else 0.35) for i in range(len(lampXf))], 'lamps')
    g.add(handsets, lamps)

    u = g.userData
    u.parts = {'handsets': handsets, 'lamps': lamps}
    u.phones = phones
    s = 1.42
    u.colliders = [
        {'min': [-RO - 0.1, 0, -0.85], 'max': [RO + 0.1, H, 0.85]},
        {'min': [-0.85, 0, -RO - 0.1], 'max': [0.85, H, RO + 0.1]},
        {'min': [-s, 0, -s], 'max': [s, H, s]},
    ]
    return K.finish(game, g, {'ao': {'res': 64, 'dist': 0.35}})


registerProp('pledge_carousel', _pledge_carousel,
             {'category': CAT, 'tags': ['studio_a', 'telethon', 'desk', 'phones'], 'size': [4.2, 1.2, 4.2],
              'desc': 'round telethon pledge desk with 12 rotary phones', 'hero': True})


def mergeGeos(lst):
    prep = []
    for g0 in lst:
        g = g0.toNonIndexed() if g0.index is not None else g0.clone()
        for k in list(g.attributes.keys()):
            if k not in ('position', 'normal', 'uv'):
                g.deleteAttribute(k)
        if g.attributes.uv is None:
            g.setAttribute('uv', THREE.BufferAttribute(np.zeros((g.attributes.position.count, 2)), 2))
        prep.append(g)
    return THREE.mergeGeometries(prep, False)

# ringPhone(prop, i, t, ringing): runtime (Godot) — rattles handset i (instance matrix) and blinks lamp i.


# ---------------------------------------------------------------------------------------- tote_board_tower
# 4-sided telethon tote board tower (ee_tote_board), 3.2 m: flip-digit totals ($12,987, tote_digits atlas) on every
# face, a $13,000 goal thermometer per face, chaser crown and a spinning "13" topper. Stands in the carousel ring.
# parts: digits_0..3 (strip meshes), thermo_0..3 (fill pivots, scale.y = value/13000), bulbs (InstancedMesh),
# topper (rotate .rotation.y). setToteValue(prop, 12988), setToteGlow(prop, game, level 0..1).
def _tote_board_tower(game, opts=None):
    opts = opts or {}
    g = K.prop('tote_board_tower')
    lac = K.mat(game, 'lacquer', '#ffffff')
    chrome = K.mat(game, 'chrome', '#A8B0BA')
    glass = game.mats.glass('#DDEFFF', {'opacity': 0.14})
    W = 1.34
    value = _nn(opts.get('value'), 12987)
    sv = fmtTote(value)

    def draw_panel(ctx, w, h, rand):
        # A [0,0 200x392] thermometer panel
        rrect(ctx, 4, 4, 192, 384, 22)
        ctx.fillStyle = PAL.cream
        ctx.fill()
        ctx.lineWidth = 5
        ctx.strokeStyle = PAL.harvestGold
        ctx.stroke()
        rrect(ctx, 12, 12, 176, 58, 14)
        ctx.fillStyle = PAL.channelRed
        ctx.fill()
        text(ctx, 'GOAL', 100, 30, {'font': FONT['sign'], 'size': 22, 'fill': '#FFF4DC'})
        text(ctx, '$13,000', 100, 55, {'font': FONT['round'], 'size': 24, 'fill': '#FFF4DC', 'maxW': 160})
        y0, y1 = 337, 92
        for i in range(14):
            y = lerp(y0, y1, i / 13)
            big = i % 5 == 0 or i == 13
            ctx.fillStyle = '#5A3A22'
            ctx.fillRect(104 if big else 110, y - 2, 30 if big else 16, 4)
            if i == 0 or i == 5 or i == 10 or i == 13:
                text(ctx, '$%sK' % i, 138, y, {'font': FONT['round'], 'size': 17, 'fill': '#5A3A22', 'align': 'left'})
        text(ctx, 'HELP US STAY ON!', 36, 215, {'font': FONT['sign'], 'size': 15, 'fill': PAL.wztvBlue,
                                                'rot': -math.pi / 2, 'maxW': 230})
        # B [200,0 150x228] call card
        rrect(ctx, 204, 4, 142, 220, 16)
        ctx.fillStyle = PAL.wztvBlue
        ctx.fill()
        ctx.lineWidth = 4
        ctx.strokeStyle = PAL.harvestGold
        ctx.stroke()
        text(ctx, 'CALL', 275, 40, {'font': FONT['sign'], 'size': 30, 'fill': '#F4F1E8'})
        text(ctx, 'NOW!', 275, 76, {'font': FONT['groovy'], 'size': 34, 'fill': PAL.marqueeGold, 'stroke': '#1B2F7A',
                                    'lw': 4})
        rrect(ctx, 226, 104, 98, 60, 12)
        ctx.fillStyle = '#F4F1E8'
        ctx.fill()
        text(ctx, '☎', 275, 136, {'font': FONT['round'], 'size': 44, 'fill': PAL.channelRed})
        text(ctx, '555-1313', 275, 196, {'font': FONT['round'], 'size': 24, 'fill': '#F4F1E8', 'maxW': 130})
        # C [200,236 312x58] header
        rrect(ctx, 202, 238, 308, 54, 14)
        ctx.fillStyle = PAL.harvestGold
        ctx.fill()
        text(ctx, 'TOTAL PLEDGED', 356, 266, {'font': FONT['sign'], 'size': 28, 'fill': '#3A1E2E', 'maxW': 290})
        # D [0,400 280x112] crown band
        ctx.fillStyle = PAL.wztvBlue
        ctx.fillRect(0, 400, 280, 112)
        ctx.fillStyle = PAL.channelRed
        ctx.fillRect(0, 400, 280, 10)
        ctx.fillRect(0, 502, 280, 10)
        text(ctx, 'WZTV 13', 140, 438, {'font': FONT['sign'], 'size': 36, 'fill': '#F4F1E8', 'stroke': '#1B2F7A',
                                        'lw': 5, 'maxW': 250})
        text(ctx, 'Telethon', 140, 478, {'font': FONT['groovy'], 'size': 30, 'fill': PAL.marqueeGold,
                                         'stroke': '#1B2F7A', 'lw': 4, 'maxW': 250})
    panel = cv('tote_panels2', 512, 512, draw_panel)

    def px(x, y, w, h):
        return [x / 512, 1 - (y + h) / 512, (x + w) / 512, 1 - y / 512]
    panelMat = K.mat(game, 'lacquer', '#ffffff', {'map': panel})
    digitsMat = K.glow(game, '#ffffff', 1.1, {'map': getCard('tote_digits')})
    # hidden plinth inside the desk ring, column, cornice bands
    g.add(tm(K.box(W - 0.1, 0.95, W - 0.1, 0.05), lac, '#2A1810', {'pos': [0, 0.475, 0]}))
    g.add(tm(K.box(W, 1.95, W, 0.09), lac, PAL.chocolate, {'pos': [0, 0.95 + 0.975, 0]}))
    g.add(tm(K.box(W + 0.08, 0.08, W + 0.08, 0.035), lac, PAL.harvestGold, {'pos': [0, 0.98, 0]}))
    g.add(tm(K.box(W + 0.06, 0.06, W + 0.06, 0.028), lac, PAL.harvestGold, {'pos': [0, 2.1, 0]}))
    # crown: flared cap with the WZTV band + chasers
    g.add(tm(K.taper(K.box(W + 0.02, 0.5, W + 0.02, 0.07), {'axis': 'y', 'k': 1.12}), lac, PAL.wztvBlue,
             {'pos': [0, 2.95, 0]}))
    g.add(tm(K.box(W + 0.24, 0.08, W + 0.24, 0.035), lac, PAL.channelRed, {'pos': [0, 3.22, 0]}))
    g.add(tm(K.box(W - 0.1, 0.07, W - 0.1, 0.03), lac, PAL.chocolate, {'pos': [0, 3.28, 0]}))
    parts = {}
    bulbXf = []
    for side in range(4):
        sg = THREE.Group()
        sg.rotation.y = side * (math.pi / 2)
        fz = -W / 2
        # thermometer panel + tube + fill
        sg.add(K.m(decalGeo(0.46, 0.9, px(0, 0, 200, 392)), panelMat, {'pos': [-0.3, 1.55, fz - 0.004]}))
        sg.add(tm(K.box(0.52, 0.96, 0.03, 0.02), lac, PAL.harvestGold, {'pos': [-0.3, 1.55, fz + 0.005]}))
        tx = -0.25
        tube = THREE.CapsuleGeometry(0.04, 0.56, 4, 10)
        sg.add(K.m(tube, glass, {'pos': [tx, 1.52, fz - 0.06]}))
        sg.add(K.m(THREE.SphereGeometry(0.075, 12, 8), glass, {'pos': [tx, 1.17, fz - 0.06]}))
        redM = K.glow(game, '#FF3B30', 1.25)
        sg.add(K.m(THREE.SphereGeometry(0.06, 10, 7), redM, {'pos': [tx, 1.17, fz - 0.06]}))
        fill = THREE.Group()
        fill.position.set(tx, 1.2, fz - 0.06)
        fc = K.cyl(0.026, 0.026, 0.59, {'seg': 10, 'bevel': 0.01})
        fill.add(K.m(fc, redM))
        fill.scale.y = clamp((value if isinstance(value, (int, float)) else math.nan) / 13000, 0.02, 1)
        fill.userData.noMerge = True
        sg.add(fill)
        parts['thermo_%d' % side] = fill
        for y in (1.3, 1.84):
            sg.add(K.m(K.box(0.12, 0.03, 0.05, 0.01), chrome, {'pos': [tx, y, fz - 0.03]}))
        # pledge-now card beside the thermometer
        sg.add(tm(K.box(0.5, 0.9, 0.035, 0.03), lac, PAL.cream, {'pos': [0.3, 1.55, fz - 0.005]}))
        sg.add(K.m(decalGeo(0.44, 0.67, px(200, 0, 150, 228)), panelMat, {'pos': [0.3, 1.55, fz - 0.025]}))
        # digit board
        sg.add(tm(K.box(1.24, 0.46, 0.06, 0.04), lac, '#2A1810', {'pos': [0, 2.42, fz - 0.01]}))
        sg.add(tm(K.box(1.3, 0.52, 0.03, 0.03), lac, PAL.harvestGold, {'pos': [0, 2.42, fz + 0.01]}))
        sg.add(K.m(decalGeo(0.7, 0.13, px(200, 236, 312, 58)), panelMat, {'pos': [0, 2.72, fz - 0.03]}))
        sg.add(tm(K.box(0.74, 0.16, 0.03, 0.03), lac, PAL.chocolate, {'pos': [0, 2.72, fz - 0.012]}))
        strip = K.m(toteStripGeo(sv, 0.15, 0.2, 0.162), digitsMat, {'pos': [0, 2.4, fz - 0.043]})
        strip.userData.noMerge = True
        sg.add(strip)
        parts['digits_%d' % side] = strip
        # crown band decal
        sg.add(K.m(decalGeo(0.9, 0.36, px(0, 400, 280, 112)), panelMat, {'pos': [0, 2.95, fz - 0.07]}))
        g.add(sg)
        for b in range(9):
            x = -0.64 + b * 0.16
            p = V3(x, 3.22, fz - 0.14).applyAxisAngle(UP, side * (math.pi / 2))
            bulbXf.append({'pos': p.toArray(), 'rot': [0, side * (math.pi / 2), 0]})
    bulbs = instanced(bulbGeo(0.035), K.glow(game, '#ffffff', 1), bulbXf,
                      [hdr(PAL.marqueeGold, 3 if i % 2 else 1.4) for i in range(len(bulbXf))], 'bulbs')
    g.add(bulbs)

    # spinning 13 topper
    def draw_top(ctx, w, h, rand):
        ctx.fillStyle = PAL.channelRed
        ctx.beginPath()
        ctx.arc(128, 128, 126, 0, TAU)
        ctx.fill()
        ctx.fillStyle = PAL.wztvBlue
        ctx.beginPath()
        ctx.arc(128, 128, 100, 0, TAU)
        ctx.fill()
        text(ctx, '13', 128, 136, {'font': FONT['round'], 'size': 130, 'fill': '#F4F1E8', 'stroke': '#1B2F7A', 'lw': 8})
    top = cv('tote_topper', 256, 256, draw_top)
    topMat = K.mat(game, 'lacquer', '#ffffff', {'map': top})
    g.add(K.m(K.cyl(0.03, 0.035, 0.3, {'seg': 10}), chrome, {'pos': [0, 3.25, 0]}))
    topper = THREE.Group()
    topper.position.set(0, 3.78, 0)
    topper.add(tm(K.cyl(0.32, 0.32, 0.07, {'seg': 32, 'bevel': 0.025}).clone().rotateX(math.pi / 2)
                  .translate(0, 0, -0.035), lac, PAL.harvestGold))
    c1 = THREE.CircleGeometry(0.29, 32)
    c1.rotateY(math.pi)
    topper.add(K.m(c1, topMat, {'pos': [0, 0, -0.037]}))
    topper.add(K.m(THREE.CircleGeometry(0.29, 32), topMat, {'pos': [0, 0, 0.037]}))
    K.merge(topper)
    topper.userData.noMerge = True
    g.add(topper)
    parts['bulbs'] = bulbs
    parts['topper'] = topper
    u = g.userData
    u.parts = parts
    u.tote = {'value': value, 'goal': 13000}
    u.colliders = [{'min': [-W / 2 - 0.05, 0, -W / 2 - 0.05], 'max': [W / 2 + 0.05, 3.3, W / 2 + 0.05]}]
    u.lightAnchors = [{'pos': [0, 2.4, 0], 'color': PAL.gelAmber, 'intensity': 1.6, 'distance': 5}]
    return K.finish(game, g, {'ao': {'res': 56}})


registerProp('tote_board_tower', _tote_board_tower,
             {'category': CAT, 'tags': ['studio_a', 'telethon', 'ee', 'tote'], 'size': [1.6, 4.1, 1.6],
              'desc': '4-sided telethon tote board tower with flip digits and goal thermometers', 'hero': True,
              'cache': False})


def fmtTote(v):
    if isinstance(v, str):
        return v
    s = js_str(js_round(v))
    s = re.sub(r'\B(?=(\d{3})+(?!\d))', ',', s)
    return ('$' + s).rjust(7, ' ')[-7:]

# setToteValue(prop, value) / setToteGlow(prop, game, level): runtime (Godot) — fmtTote + writeStripUV on digits_0..3,
# thermo_i.scale.y = clamp(value / goal, 0.02, 1); glow K.glow('#ffffff', 0.25 + 0.85 * level, tote_digits).


# ---------------------------------------------------------------------------------------- bleacher_block
# Studio-audience bleacher block: 3 carpeted tiers (0.45/0.9/1.35 m), molded 70s bucket seats (InstancedMesh,
# alternating colors), stepped end panels with racing stripes, abandoned foam "13" fingers and popcorn tubs.
# opts: { width=8, depth=2.5, seed=1 }. Colliders: the 3 tiers (walkable high ground).
def _bleacher_block(game, opts=None):
    opts = opts or {}
    g = K.prop('bleacher_block')
    W, D, seed = _nn(opts.get('width'), 8), _nn(opts.get('depth'), 2.5), _nn(opts.get('seed'), 1)
    rnd = mulberry32(seed * 131 + 7)
    HT, td = [0.45, 0.9, 1.35], D / 3
    lac = K.mat(game, 'lacquer', '#ffffff')
    chrome = K.mat(game, 'chrome', '#A8B0BA')
    carpet = K.mat(game, 'fabric', '#ffffff', {'map': K.tex.shag('#8A3A22', '#D9A520'), 'rim': 0.12, 'wrap': 0.5})
    vinyl = K.mat(game, 'vinyl', '#ffffff')
    for t in range(3):
        z0 = -D / 2 + t * td
        depth = D - t * td
        g.add(K.m(K.box(W - 0.12, HT[t], depth, 0.03, {'uv': 2.2}), carpet, {'pos': [0, HT[t] / 2, z0 + depth / 2]}))
        g.add(K.m(K.box(W - 0.1, 0.04, 0.05, 0.015), chrome, {'pos': [0, HT[t] - 0.01, z0 + 0.02]}))

    # stepped end panels (70s stripes)
    def stepShape(inset):
        pts = [[-D / 2 + inset, inset], [D / 2 - inset, inset], [D / 2 - inset, HT[2] + 0.08 - inset]]
        for t in range(2, -1, -1):
            z = -D / 2 + t * td + inset
            pts.append([z, HT[t] + 0.08 - inset])
            if t > 0:
                pts.append([z, HT[t - 1] + 0.08 - inset])
        return pts
    for s in (-1, 1):
        x = s * (W / 2 - 0.03)

        def add(inset, th, col, dx):
            geo = K.extrude(stepShape(inset), th, {'bevel': min(0.02, th * 0.4), 'round': 0.04})
            geo.rotateY(-math.pi / 2)
            g.add(tm(geo, lac, col, {'pos': [x + s * dx, 0, 0]}))
        add(0, 0.08, PAL.chocolate, 0)
        add(0.07, 0.03, PAL.burntOrange, 0.05)
        add(0.13, 0.03, PAL.harvestGold, 0.07)
        add(0.19, 0.03, PAL.cream, 0.09)

    # upholstered 70s theater seats (instanced: upholstery tinted per seat + dark frame) on a chrome beam per tier
    def _back():
        b = K.box(0.5, 0.5, 0.11, 0.045, {'seg': 1}).clone()
        b.rotateX(-0.12)
        b.translate(0, 0.72, 0.21)
        return b
    seatGeo = mergeGeos([
        K.box(0.5, 0.11, 0.44, 0.045, {'seg': 1}).clone().translate(0, 0.42, -0.02),
        _back(),
    ])
    frameGeo = mergeGeos([
        K.box(0.07, 0.3, 0.42, 0.025, {'seg': 1}).clone().translate(0.28, 0.52, 0.02),
        K.box(0.12, 0.36, 0.12, 0.02, {'seg': 1}).clone().translate(0, 0.18, 0.04),
    ])
    pitch = 0.56
    n = max(1, int(math.floor((W - 0.5) / pitch)))
    xf, cols = [], []
    palette = [PAL.burntOrange, PAL.harvestGold]
    seatPos = []
    for t in range(3):
        z = -D / 2 + t * td + td * 0.4
        for i in range(n):
            x = (i - (n - 1) / 2) * pitch
            xf.append({'pos': [x, HT[t], z], 'rot': [0, (rnd() - 0.5) * 0.04, 0]})
            cols.append(palette[(i + t) % 2])
            seatPos.append([x, HT[t] + 0.48, z - 0.03])
        g.add(K.m(K.cyl(0.03, 0.03, n * pitch + 0.1, {'seg': 8}).clone().rotateZ(math.pi / 2)
                  .translate((n * pitch + 0.1) / 2, 0, 0), chrome, {'pos': [0, HT[t] + 0.1, z + 0.04]}))
    seats = instanced(seatGeo, vinyl, xf, cols, 'seats')
    frames = instanced(frameGeo, K.mat(game, 'plastic', '#3A2A30'), xf, None, 'seat_frames')
    g.add(seats, frames)

    # foam fingers + popcorn tubs on random seats / steps
    def draw_foam(ctx, w, h, rand):
        ctx.fillStyle = '#fff'
        ctx.fillRect(0, 0, w, h)
        text(ctx, '13', w / 2, h / 2 + 4, {'font': FONT['round'], 'size': 88, 'fill': PAL.wztvBlue, 'stroke': '#fff',
                                           'lw': 2})
    foamTex = cv('foam_13', 128, 128, draw_foam)
    foam = K.mat(game, 'felt', '#ffffff')
    foamPrint = K.mat(game, 'felt', '#ffffff', {'map': foamTex})

    def draw_stripes(ctx, w, h, rand):
        for i in range(8):
            ctx.fillStyle = '#F4F1E8' if i % 2 else PAL.channelRed
            ctx.fillRect(i * 16, 0, 16, h)
        ctx.fillStyle = PAL.wztvBlue
        ctx.fillRect(0, 22, w, 20)
        text(ctx, 'POPCORN', w / 2, 33, {'font': FONT['sign'], 'size': 13, 'fill': '#fff', 'maxW': w * 0.9})
    stripeTex = cv('popcorn_stripes', 128, 64, draw_stripes, True)
    tub = K.mat(game, 'paint', '#ffffff', {'map': stripeTex})
    cornMat = K.mat(game, 'plastic', '#ffffff')
    used = set()

    def pick():
        while True:
            k = int(math.floor(rnd() * len(seatPos)))
            if not (k in used and len(used) < len(seatPos)):
                break
        used.add(k)
        return seatPos[k]
    fingerCols = [PAL.channelRed, PAL.harvestGold, PAL.wztvBlue]
    for f in range(3):
        x, y, z = pick()
        fg = THREE.Group()
        c = fingerCols[f % 3]
        fg.add(tm(K.cushion(0.2, 0.22, 0.08, {'puff': 0.015}), foam, c, {'pos': [0, 0.11, 0]}))
        fg.add(tm(THREE.CapsuleGeometry(0.04, 0.2, 4, 10), foam, c, {'pos': [0.05, 0.35, 0]}))
        fg.add(tm(THREE.CapsuleGeometry(0.035, 0.08, 4, 8), foam, c, {'pos': [-0.1, 0.16, -0.01], 'rot': [0, 0, 0.9]}))
        for dx in (-0.02, -0.07):
            fg.add(tm(THREE.SphereGeometry(0.045, 10, 8), foam, c, {'pos': [dx, 0.22, -0.01]}))
        fg.add(tm(K.cyl(0.08, 0.075, 0.1, {'seg': 14, 'bevel': 0.02}), foam, '#F4F1E8',
                  {'pos': [0, -0.08, 0], 'scale': [1.2, 1, 0.6]}))
        fg.add(K.m(decalGeo(0.15, 0.15), foamPrint, {'pos': [0, 0.1, -0.046]}))
        if f == 0:
            fg.position.set(x, y + 0.14, z)
            fg.rotation.set(-0.15, (rnd() - 0.5) * 0.8, 0.1)
        else:
            fg.position.set(x, y + 0.05, z)
            fg.rotation.set(-math.pi / 2 + 0.2, rnd() * TAU, 0)
        g.add(fg)
    for p in range(3):
        x, y, z = pick()
        pg = THREE.Group()
        pg.add(K.m(K.lathe([[0, 0], [0.07, 0], [0.1, 0.2], [0.095, 0.205], [0, 0.205]], {'seg': 16}), tub))
        pr = mulberry32(seed * 17 + p)
        for k in range(14):
            a, r = pr() * TAU, math.sqrt(pr()) * 0.08
            kk = THREE.IcosahedronGeometry(0.024 + pr() * 0.01, 0)
            pg.add(tm(kk, cornMat, '#F4D06A' if pr() < 0.2 else '#FFF6DC',
                      {'pos': [math.cos(a) * r, 0.2 + pr() * 0.04 + (0.08 - r) * 0.4, math.sin(a) * r]}))
        if p == 2:
            pg.rotation.z = math.pi / 2 - 0.1
            pg.position.set(x, y + 0.02, z)
            for k in range(10):
                pg.add(tm(THREE.IcosahedronGeometry(0.022, 0), cornMat, '#FFF6DC',
                          {'pos': [0.05 + pr() * 0.06, 0.22 + pr() * 0.25, (pr() - 0.5) * 0.25]}))
        else:
            pg.position.set(x + 0.1, y, z - 0.05)
        g.add(pg)
    u = g.userData
    u.parts = {'seats': seats}
    u.colliders = [{'min': [-W / 2, 0, -D / 2 + t * td], 'max': [W / 2, h, D / 2]} for t, h in enumerate(HT)]
    return K.finish(game, g, {'ao': {'res': 72, 'dist': 0.4}})


registerProp('bleacher_block', _bleacher_block,
             {'category': CAT, 'tags': ['studio_a', 'audience', 'bleachers'], 'size': [8, 2.0, 2.5],
              'desc': '3-tier studio audience bleachers with foam fingers and popcorn', 'hero': True})


# ---------------------------------------------------------------------------------------- disco_ball
# Mirror ball on a motor, hung from the lighting grid, with two pin-spots aimed at it.
# Local origin = bottom of the mirror ball (ball center y=0.45, grid mount plate y=1.45). parts.ball (rotate .y).
# userData.spots = [{ pos, target }] for SpotLights; discoSpeckTexture() gives a speck cookie for SpotLight.map.
def _disco_ball(game, opts=None):
    g = K.prop('disco_ball')
    chrome = K.mat(game, 'chrome', '#A8B0BA')
    paint = K.mat(game, 'paint', '#ffffff')

    def draw_tiles(ctx, w, h, rand):
        ctx.fillStyle = '#3A3848'
        ctx.fillRect(0, 0, w, h)
        nx, ny = 40, 20
        tw, th = w / nx, h / ny
        for j in range(ny):
            for i in range(nx):
                v = 150 + rand() * 105
                tint = rand()
                if tint < 0.08:
                    ctx.fillStyle = 'rgb(%s,%s,%s)' % (js_str(v), js_str(v * 0.8), js_str(v))
                elif tint < 0.14:
                    ctx.fillStyle = 'rgb(%s,%s,%s)' % (js_str(v * 0.8), js_str(v * 0.9), js_str(v))
                else:
                    ctx.fillStyle = 'rgb(%s,%s,%s)' % (js_str(v), js_str(v), js_str(v))
                ctx.fillRect(i * tw + 1, j * th + 1, tw - 2, th - 2)
                ctx.fillStyle = 'rgba(255,255,255,0.5)'
                ctx.fillRect(i * tw + 1, j * th + 1, tw - 2, 1.5)
    tiles = cv('disco_tiles', 512, 256, draw_tiles)
    mirror = K.mat(game, 'chrome', '#ffffff', {'map': tiles, 'flat': True, 'rough': 0.12})
    BY, R = -1.0, 0.45
    g.add(K.m(K.cyl(0.12, 0.12, 0.03, {'seg': 16}), chrome, {'pos': [0, -0.03, 0]}))
    g.add(K.m(K.cyl(0.015, 0.015, 0.3, {'seg': 8}), chrome, {'pos': [0, -0.33, 0]}))
    g.add(tm(K.lathe([[0, 0], [0.08, 0], [0.09, 0.04], [0.09, 0.1], [0.06, 0.14], [0, 0.14]],
                     {'round': 0.015, 'seg': 16}), paint, '#2A2230', {'pos': [0, -0.48, 0]}))
    ball = THREE.Group()
    ball.position.set(0, BY, 0)
    ball.add(K.m(THREE.SphereGeometry(R, 28, 18), mirror))
    ball.add(K.m(K.cyl(0.006, 0.006, 0.08, {'seg': 6}), chrome, {'pos': [0, R - 0.02, 0]}))
    ball.userData.noMerge = True
    g.add(ball)
    g.add(K.m(K.cyl(0.004, 0.004, 0.44, {'seg': 5}), chrome, {'pos': [0, BY + R + 0.05, 0]}))
    # clamp pipe + pin spots
    g.add(K.m(K.cyl(0.024, 0.024, 2.0, {'seg': 10}).clone().rotateZ(math.pi / 2).translate(1.0, 0, 0), chrome,
              {'pos': [0, -0.06, 0]}))
    spots = []
    for s in (-1, 1):
        mount = V3(s * 0.85, -0.06, 0)
        pos = V3(s * 0.85, -0.3, 0.05)
        target = V3(0, BY, 0)
        can = THREE.Group()
        can.position.copy(pos)
        can.lookAt(target)
        can.add(tm(K.cyl(0.065, 0.075, 0.22, {'seg': 14, 'bevel': 0.015}).clone().rotateX(math.pi / 2)
                   .translate(0, 0, -0.08), paint, '#2A2230'))
        lens = THREE.CircleGeometry(0.052, 16)
        can.add(K.m(lens, K.glow(game, '#FFF2D8', 3), {'pos': [0, 0, 0.142]}))
        g.add(can)
        g.add(tm(K.box(0.03, 0.26, 0.03, 0.008), paint, '#2A2230', {'pos': [s * 0.85, -0.18, 0.03]}))
        g.add(K.m(K.cyl(0.035, 0.035, 0.05, {'seg': 10}).clone().rotateZ(math.pi / 2), chrome, {'pos': mount.toArray()}))
        spots.append({'pos': pos.toArray(), 'target': target.toArray()})
    # origin = bottom of the ball (placing it at y = 6.5 puts the mount plate at 7.95, just under an 8 m ceiling)
    OFF = -BY + R
    for c in g.children:
        c.position.y += OFF
    for sp in spots:
        sp['pos'][1] += OFF
        sp['target'][1] += OFF
    u = g.userData
    u.parts = {'ball': ball}
    u.spots = spots
    u.anchors = {'mount': [0, OFF, 0], 'ball': [0, R, 0]}
    u.colliders = []
    return K.finish(game, g, {'ao': AO_HANG})


registerProp('disco_ball', _disco_ball,
             {'category': CAT, 'tags': ['studio_a', 'hanging', 'disco'], 'size': [2.0, 1.5, 0.9],
              'desc': 'mirror ball on a motor with two pin-spots (hangs from the grid)'})


def discoSpeckTexture():
    """Speck cookie for the disco pin-spots' SpotLight.map (used by the room at runtime)."""
    def draw(ctx, w, h, rand):
        ctx.fillStyle = '#000'
        ctx.fillRect(0, 0, w, h)
        for i in range(160):
            x, y, r = rand() * w, rand() * h, 1.5 + rand() * 3
            gr = ctx.createRadialGradient(x, y, 0, x, y, r * 2)
            gr.addColorStop(0, 'rgba(255,255,255,1)')
            gr.addColorStop(0.5, 'rgba(255,255,255,0.6)')
            gr.addColorStop(1, 'rgba(255,255,255,0)')
            ctx.fillStyle = gr
            ctx.fillRect(x - r * 2, y - r * 2, r * 4, r * 4)
    return K.tex.canvas('sets.disco_specks', 256, 256, draw, {'repeat': False})


# ---------------------------------------------------------------------------------------- applause_sign
# APPLAUSE light box (ee_applause_sign) on two hanger rods. Local origin = bottom of the box (y=0), the rods rise
# opts.drop (0.6) above it to a ceiling plate. parts.face -> setApplause(prop, game, on).
def applauseFace(lit):
    def draw(ctx, w, h, rand):
        ctx.fillStyle = '#FF5A3C' if lit else '#8A2A2E'
        ctx.fillRect(0, 0, w, h)
        gr = ctx.createRadialGradient(w / 2, h / 2, 10, w / 2, h / 2, w / 2)
        gr.addColorStop(0, 'rgba(255,230,180,0.55)' if lit else 'rgba(255,120,100,0.12)')
        gr.addColorStop(1, 'rgba(0,0,0,0.25)')
        ctx.fillStyle = gr
        ctx.fillRect(0, 0, w, h)
        text(ctx, 'APPLAUSE', w / 2, h / 2 + 4, {'font': FONT['sign'], 'size': 92, 'fill': '#FFF6E0' if lit else '#D8B8A0',
                                                 'stroke': '#FFD0A0' if lit else '#4A1418', 'lw': 3 if lit else 4,
                                                 'maxW': w * 0.92, 'track': 2})
    return cv('applause_%s' % ('on' if lit else 'off'), 512, 128, draw)


def _applause_sign(game, opts=None):
    opts = opts or {}
    g = K.prop('applause_sign')
    lac = K.mat(game, 'lacquer', '#ffffff')
    chrome = K.mat(game, 'chrome', '#A8B0BA')
    Wd, Hh, Dd, drop = 1.9, 0.56, 0.32, _nn(opts.get('drop'), 0.6)
    g.add(tm(K.box(Wd, Hh, Dd, 0.09), lac, '#2A1D2A', {'pos': [0, Hh / 2, 0]}))
    fr = K.roundRect(Wd - 0.04, Hh - 0.04, 0.07)
    fr.holes.append(THREE.Path(K.roundRect(Wd - 0.2, Hh - 0.18, 0.04).getPoints(6)))
    g.add(K.m(K.extrude(fr, 0.05, {'bevel': 0.018, 'bevelSeg': 2, 'curveSeg': 6}), chrome,
              {'pos': [0, Hh / 2, -Dd / 2 - 0.005]}))
    face = K.m(decalGeo(Wd - 0.19, Hh - 0.17), K.mat(game, 'lacquer', '#ffffff', {'map': applauseFace(False)}),
               {'pos': [0, Hh / 2, -Dd / 2 - 0.012]})
    face.userData.noMerge = True
    g.add(face)
    for i in range(6):
        g.add(tm(K.box(0.03, 0.14, 0.02, 0.008), lac, '#15101A', {'pos': [-0.3 + i * 0.12, Hh / 2, Dd / 2 + 0.002]}))
    for s in (-1, 1):
        g.add(K.m(K.cyl(0.016, 0.016, drop, {'seg': 8}), chrome, {'pos': [s * (Wd / 2 - 0.25), Hh - 0.02, 0]}))
        g.add(K.m(K.lathe([[0, 0], [0.05, 0], [0.05, 0.02], [0.03, 0.04], [0, 0.04]], {'seg': 12}), chrome,
                  {'pos': [s * (Wd / 2 - 0.25), Hh - 0.02, 0]}))
        g.add(K.m(K.cyl(0.07, 0.07, 0.025, {'seg': 14}), chrome, {'pos': [s * (Wd / 2 - 0.25), Hh + drop - 0.025, 0]}))
    g.add(K.m(K.tube([[0.3, Hh, 0.05], [0.35, Hh + 0.15, 0.08], [0.2, Hh + 0.35, 0.05], [0.26, Hh + drop, 0.02]], 0.01,
                     {'seg': 16, 'radial': 5}), K.mat(game, 'rubber', '#2A2230')))
    u = g.userData
    u.parts = {'face': face}
    u.colliders = []
    return K.finish(game, g, {'ao': AO_HANG})


registerProp('applause_sign', _applause_sign,
             {'category': CAT, 'tags': ['studio_a', 'ee', 'sign', 'hanging'], 'size': [1.9, 1.2, 0.36],
              'desc': 'APPLAUSE light box on hanger rods'})

# setApplause(prop, game, on): runtime (Godot) — on = K.glow('#ffffff', 1.25, {map: applauseFace(True)}),
# off = K.mat('lacquer', '#ffffff', {map: applauseFace(False)}).


# ---------------------------------------------------------------------------------------- chroma_cyc
# Chroma-key blue cyclorama (Studio B east wall): curved sweep into the floor on a plywood frame, cyc-light batten,
# taped spike X on the floor. opts: { width=4.0, height=3.6 }. Back of the sweep at local z = +0.35 (wall side).
def _chroma_cyc(game, opts=None):
    opts = opts or {}
    g = K.prop('chroma_cyc')
    W, Hh, R, ZB, front = _nn(opts.get('width'), 4.0), _nn(opts.get('height'), 3.6), 0.9, 0.35, 0.7
    lac = K.mat(game, 'lacquer', '#ffffff')
    chrome = K.mat(game, 'chrome', '#A8B0BA')
    teak = K.mat(game, 'teak', '#ffffff', {'map': K.tex.wood('#C8A06A', {'dark': 0.25})})

    def draw_blue(ctx, w, h, rand):
        ctx.fillStyle = PAL.chromaBlue
        ctx.fillRect(0, 0, w, h)
        for i in range(30):
            ctx.fillStyle = 'rgba(%s,0.02)' % ('255,255,255' if rand() < 0.5 else '10,20,80')
            ctx.fillRect(rand() * w, 0, 10 + rand() * 30, h)
        speckle(ctx, w, h, rand, 500, 0.035)
    blueTex = cv('cyc_blue', 256, 256, draw_blue, True)
    blue = K.mat(game, 'paint', '#ffffff', {'map': blueTex, 'rough': 0.85})
    # profile: floor apron -> quarter circle -> vertical
    prof = [[ZB - R - front, 0.004], [ZB - R, 0.004]]
    for i in range(1, 13):
        t = (i / 12) * (math.pi / 2)
        prof.append([ZB - R + R * math.sin(t), R - R * math.cos(t)])
    prof.append([ZB, Hh])
    L = [0]
    for i in range(1, len(prof)):
        L.append(L[i - 1] + js_hypot(prof[i][0] - prof[i - 1][0], prof[i][1] - prof[i - 1][1]))
    pos, uv, idx = [], [], []
    nxs = 4
    for k in range(len(prof)):
        for i in range(nxs + 1):
            x = (i / nxs - 0.5) * W
            pos += [x, prof[k][1], prof[k][0]]
            uv += [(i / nxs) * W / 1.5, L[k] / 1.5]
    for k in range(len(prof) - 1):
        for i in range(nxs):
            a = k * (nxs + 1) + i
            b = a + 1
            c = a + nxs + 1
            d = c + 1
            idx += [a, c, b, b, c, d]
    sweep = THREE.BufferGeometry()
    sweep.setAttribute('position', THREE.Float32BufferAttribute(pos, 3))
    sweep.setAttribute('uv', THREE.Float32BufferAttribute(uv, 2))
    sweep.setIndex(idx)
    sweep.computeVertexNormals()
    g.add(K.m(sweep, blue))
    # side frames (plywood edge showing) + back skin
    side = [[z, y] for z, y in prof[1:]] + [[ZB + 0.12, Hh], [ZB + 0.12, 0]]
    for s in (-1, 1):
        geo = K.extrude([[z, y] for z, y in side], 0.06, {'bevel': 0.012})
        geo.rotateY(-math.pi / 2)
        g.add(K.m(K.uvScale(geo, 2, 2), teak, {'pos': [s * (W / 2 + 0.03), 0, 0]}))
        # stage brace + sandbag
        g.add(tm(K.cushion(0.36, 0.16, 0.26, {'puff': 0.03}), lac, '#6A5A3A', {'pos': [s * (W / 2 + 0.25), 0.08, ZB - 0.2]}))
    g.add(tm(K.box(W + 0.1, Hh, 0.04, 0.012), lac, '#8A7A60', {'pos': [0, Hh / 2, ZB + 0.1]}))
    # cyc-light batten with three floods
    g.add(K.m(K.cyl(0.024, 0.024, W + 0.3, {'seg': 10}).clone().rotateZ(math.pi / 2).translate((W + 0.3) / 2, 0, 0),
              chrome, {'pos': [0, Hh + 0.25, -0.35]}))
    for i in range(3):
        x = (i - 1) * (W / 3)
        fl = THREE.Group()
        fl.position.set(x, Hh + 0.1, -0.35)
        fl.rotation.x = 0.7
        fl.add(tm(K.taper(K.box(0.42, 0.26, 0.24, 0.03), {'axis': 'z', 'k': 0.8}), lac, '#2A2230'))
        fl.add(K.m(decalGeo(0.34, 0.18), K.glow(game, '#E8F0FF', 2.2), {'pos': [0, 0, -0.125]}))
        g.add(fl)
        g.add(K.m(K.cyl(0.012, 0.012, 0.15, {'seg': 6}), chrome, {'pos': [x, Hh + 0.12, -0.35]}))

    # taped spike X + T marks
    def draw_tape(ctx, w, h, rand):
        ctx.clearRect(0, 0, w, h)
        ctx.lineCap = 'butt'
        for a, c in [[0.785, '#FF5FA2'], [-0.785, '#FF5FA2']]:
            ctx.save()
            ctx.translate(w / 2, h / 2)
            ctx.rotate(a)
            ctx.fillStyle = c
            ctx.fillRect(-58, -9, 116, 18)
            ctx.fillStyle = 'rgba(255,255,255,0.18)'
            ctx.fillRect(-58, -9, 116, 3)
            ctx.restore()
    tape = cv('cyc_tape', 128, 128, draw_tape)
    tapeMat = K.mat(game, 'plastic', '#ffffff', {'map': tape, 'alphaTest': 0.5, 'transparent': False})
    xg = THREE.PlaneGeometry(0.7, 0.7)
    xg.rotateX(-math.pi / 2)
    g.add(K.m(xg, tapeMat, {'pos': [0.2, 0.008, ZB - R - 0.2]}))
    tg2 = THREE.PlaneGeometry(0.3, 0.3)
    tg2.rotateX(-math.pi / 2)
    g.add(K.m(tg2, tapeMat, {'pos': [-1.2, 0.008, ZB - R - 0.45], 'rot': [0, 0.3, 0]}))
    u = g.userData
    u.anchors = {'mark': [0.2, 0, ZB - R - 0.2]}
    u.colliders = [{'min': [-W / 2 - 0.1, 0, ZB - 0.3], 'max': [W / 2 + 0.1, Hh, ZB + 0.15]}]
    u.lightAnchors = [{'pos': [0, Hh - 0.2, -0.6], 'color': '#DDE8FF', 'intensity': 1.6, 'distance': 5}]
    return K.finish(game, g, {'ao': {'res': 56}})


registerProp('chroma_cyc', _chroma_cyc,
             {'category': CAT, 'tags': ['studio_b', 'chroma', 'backdrop'], 'size': [4.6, 3.9, 2.1],
              'desc': 'chroma-key blue cyclorama with a taped X'})


# =========================================================================================================
# STUDIO B — HOOTIE'S HULLABALOO
# =========================================================================================================

# vertex colors by normal: faces whose normal is mostly along `axis` get capColor, the rest sideColor
def tintByNormal(geo, capColor, sideColor, axis=2, th=0.7):
    g = geo.toNonIndexed() if geo.index is not None else geo.clone()
    g.computeVertexNormals()
    n = g.attributes.normal
    cA, cB = THREE.Color(capColor), THREE.Color(sideColor)
    na = np.asarray(n, dtype=np.float64)
    cap = np.abs(na[:, axis]) > th
    col = np.empty((n.count, 3))
    col[:] = (cB.r, cB.g, cB.b)
    col[cap] = (cA.r, cA.g, cA.b)
    g.setAttribute('color', THREE.BufferAttribute(col, 3))
    return g


def flameShape(w, h, lean=0):
    return [[-w / 2, 0], [w / 2, 0], [w * 0.42, h * 0.35], [w * 0.18 + lean, h * 0.62], [w * 0.1 + lean * 1.4, h],
            [-w * 0.05 + lean, h * 0.7], [-w * 0.3, h * 0.45], [-w * 0.42, h * 0.3]]


# ---------------------------------------------------------------------------------------- cardboard_rocket
# 5.5 m kids'-show cardboard rocket (the Studio B loop pillar, radius 1.4 with fins): 12 painted cardboard
# panels, masking tape, marker rivets, "HOOTIE-1" hand lettering, porthole with Hootie peeking, cardboard fins
# with corrugated edges, crepe-paper flames. Colliders: a pillar square + fin cross.
def _cardboard_rocket(game, opts=None):
    g = K.prop('cardboard_rocket')

    def draw_body(ctx, w, h, rand):
        ctx.fillStyle = '#E9E4D6'
        ctx.fillRect(0, 0, w, h)
        for i in range(260):
            ctx.fillStyle = 'rgba(%s,0.08)' % ('255,255,255' if rand() < 0.5 else '150,140,120')
            ctx.fillRect(rand() * w, rand() * h, 30 + rand() * 60, 2 + rand() * 3)
        pw = w / 12
        # red bands with stars (v: top of canvas = top of body)
        for y, hh in [[34, 46], [h - 96, 50]]:
            ctx.fillStyle = PAL.channelRed
            ctx.fillRect(0, y, w, hh)
            ctx.fillStyle = 'rgba(0,0,0,0.12)'
            for i in range(30):
                ctx.fillRect(rand() * w, y, 2, hh)
            for i in range(12):
                poly(ctx, starPts(i * pw + pw / 2, y + hh / 2, 13, 5.5))
                ctx.fillStyle = '#FFF4DC'
                ctx.fill()
        # kraft cardboard showing at the panel seams + tape strips across seams
        for i in range(13):
            x = i * pw
            ctx.fillStyle = '#B98A55'
            ctx.fillRect(x - 3, 0, 6, h)
            ctx.fillStyle = 'rgba(80,50,20,0.35)'
            ctx.fillRect(x - 1, 0, 2, h)
            for k in range(4):
                y = 60 + rand() * (h - 120)
                ctx.save()
                ctx.translate(x, y)
                ctx.rotate((rand() - 0.5) * 0.2)
                ctx.fillStyle = 'rgba(232,214,160,0.92)'
                ctx.fillRect(-14, -5, 28, 10)
                ctx.fillStyle = 'rgba(160,130,80,0.25)'
                ctx.fillRect(-14, -5, 28, 2)
                ctx.restore()
            if i % 3 == 0:
                y = 110
                while y < h - 110:
                    ctx.fillStyle = '#5A5A6A'
                    ctx.beginPath()
                    ctx.arc(x + 9, y, 2.4, 0, TAU)
                    ctx.fill()
                    y += 44
        # hand-painted vertical HOOTIE-1 (front panels ~ u 0.70..0.80 face -z) and a door outline on the back
        fx = w * 0.64
        for i, ch in enumerate('HOOTIE-1'):
            text(ctx, ch, fx + math.sin(i * 1.7) * 2, 120 + i * 38, {'font': FONT['round'], 'size': 40,
                                                                     'fill': PAL.wztvBlue, 'stroke': '#F4F1E8', 'lw': 3,
                                                                     'rot': (rand() - 0.5) * 0.15})
        ctx.strokeStyle = '#3A2A48'
        ctx.lineWidth = 4
        ctx.setLineDash([10, 6])
        rrect(ctx, w * 0.2, 250, 70, 150, 30)
        ctx.stroke()
        ctx.setLineDash([])
        ctx.fillStyle = '#D8A83A'
        ctx.beginPath()
        ctx.arc(w * 0.2 + 58, 330, 6, 0, TAU)
        ctx.fill()
        # brush streaks
        for i in range(90):
            ctx.strokeStyle = 'rgba(255,255,255,%s)' % js_str(0.05 + rand() * 0.06)
            ctx.lineWidth = 1 + rand() * 2
            x, y = rand() * w, rand() * h
            ctx.beginPath()
            ctx.moveTo(x, y)
            ctx.lineTo(x + 20 + rand() * 40, y + (rand() - 0.5) * 6)
            ctx.stroke()
    bodyTex = cv('rocket_body', 512, 512, draw_body, True)

    def draw_nose(ctx, w, h, rand):
        ctx.fillStyle = PAL.channelRed
        ctx.fillRect(0, 0, w, h)
        for i in range(160):
            ctx.strokeStyle = 'rgba(%s,0.12)' % ('255,200,180' if rand() < 0.5 else '90,10,20')
            ctx.lineWidth = 1 + rand() * 3
            x, y = rand() * w, rand() * h
            ctx.beginPath()
            ctx.moveTo(x, y)
            ctx.lineTo(x + 10 + rand() * 30, y + 6 + rand() * 10)
            ctx.stroke()
        for i in range(9):
            ctx.fillStyle = '#9A6A3A'
            ctx.fillRect(i * (w / 8) - 2, 0, 4, h)
        for i in range(8):
            ctx.fillStyle = 'rgba(232,214,160,0.9)'
            ctx.fillRect(i * (w / 8) - 10, 60 + (i % 3) * 50, 20, 9)
    noseTex = cv('rocket_nose', 256, 256, draw_nose, True)
    paint = K.mat(game, 'paint', '#ffffff', {'map': bodyTex, 'flat': True})
    nosePaint = K.mat(game, 'paint', '#ffffff', {'map': noseTex, 'flat': True})
    card = K.mat(game, 'paint', '#ffffff')
    chrome = K.mat(game, 'chrome', '#C0C6D0')
    glass = game.mats.glass('#CFE8FF', {'opacity': 0.3})
    # body: 12 flat cardboard panels
    body = THREE.LatheGeometry([THREE.Vector2(r, y) for r, y in [[0.74, 0], [0.8, 0.5], [0.82, 1.2], [0.8, 2.2],
                                                                 [0.72, 3.2]]], 12)
    K.uvScale(body, 1, 1)
    g.add(K.m(body, paint, {'pos': [0, 0.55, 0]}))
    g.add(tm(K.lathe([[0.7, 0], [0.8, 0], [0.8, 0.06], [0.7, 0.06]], {'seg': 12}), card, '#B98A55', {'pos': [0, 0.5, 0]}))
    # nose cone (12 panels) + foil ball
    nose = THREE.LatheGeometry([THREE.Vector2(r, y) for r, y in [[0.74, 0], [0.7, 0.35], [0.55, 0.85], [0.3, 1.3],
                                                                 [0.06, 1.62]]], 12)
    g.add(K.m(nose, nosePaint, {'pos': [0, 3.73, 0]}))
    g.add(K.m(THREE.IcosahedronGeometry(0.11, 1), K.mat(game, 'chrome', '#D8DCE4', {'flat': True}), {'pos': [0, 5.38, 0]}))
    g.add(tm(K.lathe([[0.76, 0], [0.78, 0.04], [0.76, 0.1], [0.7, 0.1]], {'seg': 12}), card, '#E9E4D6',
             {'pos': [0, 3.68, 0]}))

    # porthole with Hootie peeking
    def draw_peek(ctx, w, h, rand):
        ctx.fillStyle = '#1B1E4A'
        ctx.fillRect(0, 0, w, h)
        for i in range(30):
            ctx.fillStyle = '#FFF4D6'
            ctx.fillRect((i * 97) % w, (i * 53) % h, 3, 3)
        ctx.fillStyle = '#8A5A3A'
        ctx.beginPath()
        ctx.ellipse(128, 170, 90, 80, 0, 0, TAU)
        ctx.fill()
        for s in (-1, 1):
            ctx.fillStyle = '#8A5A3A'
            poly(ctx, [[128 + s * 50, 110], [128 + s * 86, 60], [128 + s * 84, 130]])
            ctx.fill()
            ctx.fillStyle = '#FFF8E8'
            ctx.beginPath()
            ctx.arc(128 + s * 36, 150, 30, 0, TAU)
            ctx.fill()
            ctx.fillStyle = '#2A1D3A'
            ctx.beginPath()
            ctx.arc(128 + s * 32, 152, 14, 0, TAU)
            ctx.fill()
            ctx.fillStyle = '#fff'
            ctx.beginPath()
            ctx.arc(128 + s * 28, 146, 5, 0, TAU)
            ctx.fill()
        ctx.fillStyle = '#F4A020'
        poly(ctx, [[116, 180], [140, 180], [128, 204]])
        ctx.fill()
    peek = cv('rocket_peek', 256, 256, draw_peek)
    pz, py = -0.815, 2.75
    ph = THREE.CircleGeometry(0.3, 24)
    ph.rotateY(math.pi)
    g.add(K.m(ph, K.mat(game, 'paint', '#ffffff', {'map': peek}), {'pos': [0, py, pz + 0.01]}))
    ring = THREE.TorusGeometry(0.33, 0.05, 8, 24)
    g.add(K.m(ring, chrome, {'pos': [0, py, pz - 0.01]}))
    for i in range(8):
        a = (i / 8) * TAU
        g.add(K.m(THREE.SphereGeometry(0.018, 6, 4), chrome, {'pos': [math.cos(a) * 0.33, py + math.sin(a) * 0.33,
                                                                      pz - 0.055]}))
    lens = THREE.CircleGeometry(0.3, 24)
    lens.rotateY(math.pi)
    g.add(K.m(lens, glass, {'pos': [0, py, pz - 0.02]}))
    # fins (cardboard: painted faces, kraft corrugated edges) with yellow stars
    finShape = [[0, 0.1], [0.62, -0.05], [0.66, 0.2], [0.34, 1.25], [0, 1.7]]

    def draw_star(ctx, w, h, rand):
        poly(ctx, starPts(64, 66, 58, 24))
        ctx.fillStyle = PAL.barYellow
        ctx.fill()
        ctx.lineWidth = 5
        ctx.strokeStyle = '#8A5A12'
        ctx.stroke()
    starTex = cv('rocket_star', 128, 128, draw_star)
    starMat = K.mat(game, 'paint', '#ffffff', {'map': starTex, 'alphaTest': 0.5})
    for i in range(4):
        a = math.pi / 4 + (i / 4) * TAU
        fin = tintByNormal(K.extrude(finShape, 0.07, {'bevel': 0.015, 'round': 0.05}), PAL.channelRed, '#B98A55')
        fm = K.m(fin, card)
        fm.position.set(math.sin(a) * 0.7, 0.35, math.cos(a) * 0.7)
        fm.rotation.y = a - math.pi / 2
        g.add(fm)
        for sd in (-1, 1):
            st = K.m(THREE.PlaneGeometry(0.34, 0.34), starMat)
            st.position.set(0.33, 0.55, sd * 0.037)
            if sd < 0:
                st.rotation.y = math.pi
            fm.add(st)
    # crepe-paper flames under the body
    for i in range(10):
        a = (i / 10) * TAU
        for w, h, col, r in [[0.42, 0.62, PAL.burntOrange, 0.62], [0.26, 0.42, PAL.barYellow, 0.6]]:
            f = K.m(tg(K.extrude(flameShape(w, h, (0.04 if i % 2 else -0.04)), 0.03, {'bevel': 0.008, 'round': 0.03}),
                       col), card)
            f.position.set(math.sin(a) * r, 0, math.cos(a) * r)
            f.rotation.y = a
            g.add(f)
    g.add(tm(K.cyl(0.66, 0.7, 0.5, {'seg': 12, 'bevel': 0.03}), card, '#3A2A48', {'pos': [0, 0.02, 0]}))
    u = g.userData
    u.colliders = [{'min': [-0.95, 0, -0.95], 'max': [0.95, 5.5, 0.95]}, {'min': [-1.3, 0, -0.3], 'max': [1.3, 2.0, 0.3]},
                   {'min': [-0.3, 0, -1.3], 'max': [0.3, 2.0, 1.3]}]
    return K.finish(game, g, {'ao': {'res': 60}})


registerProp('cardboard_rocket', _cardboard_rocket,
             {'category': CAT, 'tags': ['studio_b', 'kids', 'pillar', 'rocket'], 'size': [2.8, 5.5, 2.8],
              'desc': '5.5 m painted cardboard rocket (HOOTIE-1)', 'hero': True})


# ---------------------------------------------------------------------------------------- treehouse_facade
# Hootie's treehouse facade (Studio B north flat, 5 m wide): cartoon trunk with root flares, pastel plank house,
# scalloped roof, moon night-light window, rope ladder, fairy lights, and Hootie's giant TV in the trunk base
# (screen spawn ss_studio_b: userData.screens[0] {group 'scr_decor', id 'ss_studio_b'}, center local
# [-0.5, 1.0, -0.62] -> world [26.0,1.0,-27.0] when placed at [25.5,0,-27.6] rotY=PI).
def _treehouse_facade(game, opts=None):
    opts = opts or {}
    g = K.prop('treehouse_facade')
    lac = K.mat(game, 'lacquer', '#ffffff')
    paint = K.mat(game, 'paint', '#ffffff')

    def draw_bark(ctx, w, h, rand):
        ctx.fillStyle = '#7A4A2A'
        ctx.fillRect(0, 0, w, h)
        for i in range(26):
            x0 = rand() * w
            ctx.strokeStyle = 'rgba(60,30,15,0.55)' if rand() < 0.5 else 'rgba(170,110,60,0.35)'
            ctx.lineWidth = 3 + rand() * 7
            for off in (0, -w, w):
                ctx.beginPath()
                y = 0
                while y <= h:
                    x = x0 + off + math.sin(y * 0.02 + i) * 8
                    if not y:
                        ctx.moveTo(x, y)
                    else:
                        ctx.lineTo(x, y)
                    y += 16
                ctx.stroke()
        for i in range(5):
            x, y = rand() * w, rand() * h
            ctx.fillStyle = 'rgba(50,25,12,0.5)'
            ctx.beginPath()
            ctx.ellipse(x, y, 10, 16, 0, 0, TAU)
            ctx.fill()
            ctx.strokeStyle = 'rgba(170,110,60,0.5)'
            ctx.lineWidth = 3
            ctx.stroke()
    barkTex = cv('bark', 256, 512, draw_bark, True)
    bark = K.mat(game, 'paint', '#ffffff', {'map': barkTex})

    def draw_planks(ctx, w, h, rand):
        cols = ['#A8D8B8', '#F6E7C8', '#F2B48A', '#9ED8C8', '#FFE0A8']
        bh = 64
        y, r = 0, 0
        while y < h:
            x = -rand() * 120
            while x < w:
                lw = 200 + rand() * 260
                c = cols[(r + int(math.floor(rand() * 2))) % len(cols)]
                ctx.fillStyle = c
                ctx.fillRect(x, y, lw, bh)
                ctx.fillStyle = 'rgba(255,255,255,0.18)'
                ctx.fillRect(x, y + 2, lw, 5)
                ctx.fillStyle = 'rgba(80,40,30,0.35)'
                ctx.fillRect(x, y + bh - 4, lw, 4)
                ctx.fillRect(x + lw - 3, y, 3, bh)
                for k in range(6):
                    ctx.strokeStyle = 'rgba(90,60,40,0.12)'
                    ctx.lineWidth = 1
                    ctx.beginPath()
                    yy = y + 8 + rand() * (bh - 14)
                    ctx.moveTo(x, yy)
                    ctx.lineTo(x + lw, yy + (rand() - 0.5) * 4)
                    ctx.stroke()
                ctx.fillStyle = '#6A5A5A'
                ctx.beginPath()
                ctx.arc(x + 8, y + bh / 2, 3, 0, TAU)
                ctx.fill()
                ctx.beginPath()
                ctx.arc(x + lw - 10, y + bh / 2, 3, 0, TAU)
                ctx.fill()
                x += lw
            y += bh
            r += 1
    planks = cv('treehouse_planks', 512, 512, draw_planks, True)
    plank = K.mat(game, 'paint', '#ffffff', {'map': planks})

    def draw_shingles(ctx, w, h, rand):
        ctx.fillStyle = '#8A3A5A'
        ctx.fillRect(0, 0, w, h)
        for r in range(8):
            for i in range(-1, 9):
                x, y = i * 32 + (r % 2) * 16, r * 32
                ctx.fillStyle = '#C2407A' if r % 2 else '#D8467A'
                ctx.beginPath()
                ctx.moveTo(x, y)
                ctx.lineTo(x + 32, y)
                ctx.lineTo(x + 32, y + 18)
                ctx.arc(x + 16, y + 18, 16, 0, math.pi)
                ctx.closePath()
                ctx.fill()
                ctx.strokeStyle = 'rgba(60,10,30,0.45)'
                ctx.lineWidth = 2
                ctx.beginPath()
                ctx.arc(x + 16, y + 18, 16, 0, math.pi)
                ctx.stroke()
    shingles = cv('treehouse_shingles', 256, 256, draw_shingles, True)
    roofMat = K.mat(game, 'paint', '#ffffff', {'map': shingles})
    PY = 2.85
    # trunk (flattened lathe, root flares) + branches
    trunk = K.lathe([[1.25, 0], [1.05, 0.25], [0.86, 0.7], [0.78, 1.4], [0.74, 2.2], [0.8, PY + 0.2], [0.6, PY + 0.25]],
                    {'seg': 14}).clone()
    trunk.scale(1, 1, 0.42)
    K.uvScale(trunk, 3, 2.5)
    g.add(K.m(trunk, bark, {'pos': [0.35, 0, 0.12]}))
    for x, z, s, r in [[-0.8, -0.1, 0.5, 0.4], [1.45, 0.0, 0.45, -0.5], [0.9, -0.25, 0.38, 0.3]]:
        root = THREE.SphereGeometry(s, 10, 6)
        root.scale(1.4, 0.45, 0.8)
        g.add(K.m(K.uvScale(root.clone(), 2, 1), bark, {'pos': [x + 0.35, 0.06, z], 'rot': [0, r, 0]}))
    for pts, r in [[[[0.9, 2.1, 0], [1.7, 2.45, -0.05], [2.35, 2.7, -0.1]], 0.12],
                   [[[-0.2, 2.2, 0], [-1.0, 2.5, 0], [-1.8, 2.62, -0.05]], 0.11]]:
        g.add(K.m(K.uvScale(K.tube(pts, r, {'seg': 10, 'radial': 8}).clone(), 4, 1), bark))
    # platform deck + braces
    g.add(tm(K.box(4.8, 0.14, 0.95, 0.04), lac, '#9A6A3E', {'pos': [0, PY, -0.05]}))
    for i in range(12):
        g.add(tm(K.box(0.36, 0.05, 0.05, 0.008), lac, '#B08050' if i % 2 else '#8A5A34', {'pos': [-2.2 + i * 0.4, PY - 0.01, -0.52]}))
    for s in (-1, 1):
        a, b = V3(s * 0.55, 1.9, -0.1), V3(s * 1.8, PY - 0.05, -0.1)
        br = K.m(tg(K.box(0.1, a.distanceTo(b), 0.1, 0.025), '#8A5A34'), lac)
        br.position.copy(a).add(b).multiplyScalar(0.5)
        br.quaternion.setFromUnitVectors(UP, b.clone().sub(a).normalize())
        g.add(br)
    # railing
    for i in range(11):
        g.add(tm(K.box(0.06, 0.5, 0.06, 0.012), lac, '#F6E7C8', {'pos': [-2.3 + i * 0.46, PY + 0.32, -0.46]}))
    g.add(tm(K.box(4.72, 0.07, 0.08, 0.025), lac, PAL.channelRed, {'pos': [0, PY + 0.6, -0.46]}))
    # house: plank walls, scalloped roof, round moon window, door
    HW, HH, HY = 3.2, 1.55, PY + 0.07
    g.add(K.m(K.box(HW, HH, 0.5, 0.05, {'uv': 0.55}), plank, {'pos': [0.1, HY + HH / 2, 0.1]}))
    roofL = 2.0
    for s in (-1, 1):
        rf = K.m(K.box(roofL, 0.08, 0.8, 0.03, {'uv': 1.4}), roofMat)
        rf.position.set(0.1 + s * 0.85, HY + HH + 0.48, 0.05)
        rf.rotation.z = -s * 0.52
        g.add(rf)
    g.add(tm(K.box(0.14, 0.14, 0.85, 0.045), lac, PAL.harvestGold, {'pos': [0.1, HY + HH + 0.98, 0.05]}))
    gable = K.extrude([[-HW / 2 + 0.05, 0], [HW / 2 - 0.05, 0], [0, 0.93]], 0.45, {'bevel': 0.02})
    g.add(K.m(K.uvScale(gable, 0.55, 0.55), plank, {'pos': [0.1, HY + HH, 0.12]}))
    # round moon window
    mw = THREE.CircleGeometry(0.32, 28)
    mw.rotateY(math.pi)
    g.add(K.m(mw, K.glow(game, '#9FB6FF', 0.75), {'pos': [-0.7, HY + 0.85, -0.16], 'cast': False}))
    g.add(tm(THREE.TorusGeometry(0.34, 0.06, 6, 24), lac, PAL.harvestGold, {'pos': [-0.7, HY + 0.85, -0.17]}))
    g.add(tm(K.box(0.66, 0.04, 0.04, 0.012), lac, PAL.harvestGold, {'pos': [-0.7, HY + 0.85, -0.18]}),
          tm(K.box(0.04, 0.66, 0.04, 0.012), lac, PAL.harvestGold, {'pos': [-0.7, HY + 0.85, -0.18]}))

    def draw_moon(ctx, w, h, rand):
        ctx.clearRect(0, 0, w, h)
        ctx.fillStyle = '#FFF4D6'
        ctx.beginPath()
        ctx.arc(64, 64, 50, 0, TAU)
        ctx.fill()
        ctx.globalCompositeOperation = 'destination-out'
        ctx.beginPath()
        ctx.arc(88, 50, 44, 0, TAU)
        ctx.fill()
    moonTex = cv('treehouse_moon', 128, 128, draw_moon)
    g.add(K.m(decalGeo(0.3, 0.3), K.glow(game, '#ffffff', 1.25, {'map': moonTex, 'transparent': True}),
              {'pos': [-0.78, HY + 0.9, -0.2], 'cast': False}))
    # arched door + HOOTIE sign
    door = K.extrude([[-0.36, 0], [0.36, 0], [0.36, 0.8], [0, 1.12], [-0.36, 0.8]], 0.06, {'bevel': 0.02, 'round': 0.2})
    g.add(tm(door, lac, PAL.teal, {'pos': [0.85, HY, -0.17]}))
    g.add(tm(THREE.SphereGeometry(0.04, 10, 8), lac, PAL.harvestGold, {'pos': [0.62, HY + 0.5, -0.21]}))

    def draw_sign(ctx, w, h, rand):
        rrect(ctx, 4, 4, w - 8, h - 8, 40)
        ctx.fillStyle = '#FFF4DC'
        ctx.fill()
        ctx.lineWidth = 8
        ctx.strokeStyle = '#8A5A34'
        ctx.stroke()
        cols = [PAL.channelRed, PAL.burntOrange, PAL.harvestGold, PAL.barGreen, PAL.wztvBlue, PAL.plum]
        s = "HOOTIE'S HULLABALOO"
        ctx.font = '44px %s' % FONT['round']
        x = w / 2 - ctx.measureText(s).width / 2
        for i, ch in enumerate(s):
            cw = ctx.measureText(ch).width
            text(ctx, ch, x + cw / 2, h / 2 + 4 + math.sin(i * 0.9) * 5, {'font': FONT['round'], 'size': 44,
                                                                          'fill': cols[i % len(cols)],
                                                                          'stroke': '#3A1E2E', 'lw': 5,
                                                                          'rot': math.sin(i * 1.3) * 0.08})
            x += cw
    signTex = cv('treehouse_sign', 512, 128, draw_sign)
    sign = K.m(decalGeo(2.2, 0.55), K.mat(game, 'paint', '#ffffff', {'map': signTex}), {'pos': [0.1, PY - 0.45, -0.56]})
    g.add(sign)
    g.add(tm(K.box(2.3, 0.6, 0.05, 0.03), lac, '#8A5A34', {'pos': [0.1, PY - 0.45, -0.53]}))
    for s in (-1, 1):
        g.add(tm(K.tube([[0.1 + s * 1.0, PY - 0.17, -0.55], [0.1 + s * 1.0, PY - 0.07, -0.55]], 0.012,
                        {'seg': 2, 'radial': 4}), paint, '#D8B878'))
    # canopy: puffy cartoon leaf blobs behind the house
    leafM = lac
    blobs = [[-2.1, 4.5, 0.25, 0.8], [-1.3, 5.0, 0.3, 0.75], [1.6, 5.05, 0.3, 0.8], [2.3, 4.4, 0.25, 0.7],
             [-2.35, 3.7, 0.25, 0.55], [2.55, 3.55, 0.2, 0.5], [0.4, 5.25, 0.35, 0.6]]
    for i, (x, y, z, r) in enumerate(blobs):
        s = THREE.SphereGeometry(r, 10, 6)
        s.scale(1.15, 0.9, 0.55)
        g.add(tm(s, leafM, ['#6FBF4A', '#58A83E', '#8CD05A'][i % 3], {'pos': [x, y, z]}))
    # rope ladder
    LX2 = 1.85
    for s in (-1, 1):
        g.add(tm(K.tube([[LX2 + s * 0.22, PY, -0.55], [LX2 + s * 0.23, PY * 0.5, -0.6], [LX2 + s * 0.22, 0.05, -0.62]],
                        0.018, {'seg': 10, 'radial': 5}), paint, '#D8B878'))
    for i in range(1, 8):
        g.add(tm(K.box(0.5, 0.04, 0.09, 0.012), lac, '#B08050', {'pos': [LX2, i * (PY / 8), -0.6]}))
    # fairy lights along the railing
    fl = []
    for i in range(22):
        t = i / 21
        fl.append([-2.3 + t * 4.6, PY + 0.55 - math.sin(t * math.pi * 4) ** 2 * 0.12, -0.52])
    g.add(tm(K.tube(fl, 0.006, {'seg': 40, 'radial': 3}), paint, '#2A4A2A'))
    flCols = [PAL.channelRed, PAL.harvestGold, PAL.barGreen, PAL.wztvBlue, PAL.neonPink]
    fairy = instanced(THREE.SphereGeometry(0.032, 6, 5), K.glow(game, '#ffffff', 1),
                      [{'pos': [p[0], p[1] - 0.04, p[2]]} for p in fl], [hdr(flCols[i % 5], 2.2) for i in range(len(fl))],
                      'fairy')
    g.add(fairy)
    # Hootie's giant TV set into the trunk base
    TX, TY, TZ = -0.5, 1.0, -0.6
    g.add(tm(K.box(1.5, 1.28, 0.62, 0.12), lac, '#7A4A2A', {'pos': [TX, TY - 0.02, TZ + 0.3]}))
    g.add(tm(K.box(1.36, 1.12, 0.1, 0.045), lac, '#F6E7C8', {'pos': [TX, TY - 0.02, TZ + 0.02]}))
    bez = K.roundRect(1.08, 0.84, 0.16)
    bez.holes.append(THREE.Path(K.roundRect(0.96, 0.72, 0.12).getPoints(8)))
    g.add(tm(K.extrude(bez, 0.06, {'bevel': 0.02, 'curveSeg': 6}), lac, '#2A2230', {'pos': [TX - 0.08, TY, TZ - 0.02]}))
    scr = K.screen(game, 0.96, 0.72, {'card': _nn(opts.get('card'), 'hullabaloo'), 'group': 'scr_decor', 'dome': 0.03})
    scr.position.set(TX - 0.08, TY, TZ - 0.01)
    g.add(scr)
    for i in range(2):
        g.add(K.m(K.cyl(0.055, 0.06, 0.05, {'seg': 14, 'bevel': 0.012}).clone().rotateX(-math.pi / 2),
                  K.mat(game, 'chrome', '#A8B0BA'), {'pos': [TX + 0.56, TY + 0.18 - i * 0.2, TZ - 0.03]}))
    g.add(tm(K.box(0.14, 0.26, 0.02, 0.008), lac, '#3A3040', {'pos': [TX + 0.56, TY - 0.32, TZ - 0.03]}))
    for s in (-1, 1):
        g.add(rod(0.012, K.mat(game, 'chrome', '#A8B0BA'), [TX + s * 0.1, TY + 0.62, TZ + 0.3],
                  [TX + s * 0.45, TY + 1.25, TZ + 0.25]))
    u = g.userData
    u.screens = [{'mesh': scr, 'group': 'scr_decor', 'id': _nn(opts.get('screenId'), 'ss_studio_b')}]
    u.anchors = {'screen_center': [TX - 0.08, TY, TZ - 0.03]}
    u.colliders = [{'min': [-2.5, 0, -0.62], 'max': [2.5, 5.4, 0.55]}]
    u.lightAnchors = [{'pos': [-0.7, HY + 0.85, -0.6], 'color': '#BFD4FF', 'intensity': 1.5, 'distance': 5}]
    return K.finish(game, g, {'ao': {'res': 72}})


registerProp('treehouse_facade', _treehouse_facade,
             {'category': CAT, 'tags': ['studio_b', 'kids', 'facade', 'screen', 'tv'], 'size': [5.2, 5.6, 1.2],
              'desc': "Hootie's treehouse facade with the giant TV (screen spawn)", 'hero': True})


# ---------------------------------------------------------------------------------------- puppet_theater
# Red-and-yellow striped puppet playhouse (ee_puppet_theater): scalloped valance with pompoms, arched crest,
# gold proscenium, red velvet curtain (parts.curtain_l / curtain_r: pivot at the outer top corner, scale.x 1 ->
# 0.25 opens), and the navy apron with three dashed puppet silhouettes (owl, sock, dragon) + brass hooks.
# anchors.slot_owl/sock/dragon (apron hooks), anchors.stage_owl/sock/dragon (behind the curtain line).
# interact = GDD point [17.75,0,-24.9] r 1.5 when the theater is centered 0.75 m behind it.
def _puppet_theater(game, opts=None):
    g = K.prop('puppet_theater')
    lac = K.mat(game, 'lacquer', '#ffffff')
    brass = K.mat(game, 'brass', '#C8963C')

    def draw_stripes(ctx, w, h, rand):
        for i in range(8):
            ctx.fillStyle = PAL.barYellow if i % 2 else PAL.channelRed
            ctx.fillRect(i * 32, 0, 32, h)
        for i in range(8):
            ctx.fillStyle = 'rgba(0,0,0,0.08)'
            ctx.fillRect(i * 32 + 28, 0, 4, h)
            ctx.fillStyle = 'rgba(255,255,255,0.12)'
            ctx.fillRect(i * 32 + 2, 0, 3, h)
    stripes = cv('theater_stripes', 256, 256, draw_stripes, True)
    stripe = K.mat(game, 'fabric', '#ffffff', {'map': stripes, 'rim': 0.3})
    velvet = K.mat(game, 'fabric', '#ffffff', {'map': K.tex.weave('#B81E3A', {'pattern': 'cord', 'scale': 3})})
    W, D, OB, OT = 2.4, 0.9, 1.3, 2.25
    # booth: striped fabric-covered sides/top, wooden frame posts
    g.add(K.m(K.box(W, OB, D, 0.04, {'uv': 1.6}), stripe, {'pos': [0, OB / 2, 0]}))
    for s in (-1, 1):
        g.add(K.m(K.box(0.35, OT - OB + 0.02, D, 0.03, {'uv': 1.6}), stripe, {'pos': [s * (W / 2 - 0.175), (OB + OT) / 2, 0]}))
    g.add(K.m(K.box(W, 0.45, D, 0.04, {'uv': 1.6}), stripe, {'pos': [0, OT + 0.225, 0]}))
    for s in (-1, 1):
        g.add(tm(K.box(0.1, OT + 0.5, 0.1, 0.03), lac, PAL.harvestGold, {'pos': [s * (W / 2 + 0.02), (OT + 0.5) / 2, -D / 2 + 0.02]}))
    # playboard ledge
    g.add(tm(K.box(W + 0.16, 0.08, 0.3, 0.035), lac, '#9A6A3E', {'pos': [0, OB + 0.02, -D / 2 - 0.08]}))
    g.add(tm(K.box(W + 0.08, 0.05, 0.04, 0.018), lac, PAL.harvestGold, {'pos': [0, OB - 0.03, -D / 2 - 0.22]}))
    # proscenium: gold arched frame
    pw = W - 0.7
    frame = THREE.Shape()
    frame.moveTo(-pw / 2 - 0.12, OB - 0.12)
    frame.lineTo(pw / 2 + 0.12, OB - 0.12)
    frame.lineTo(pw / 2 + 0.12, OT + 0.12)
    frame.quadraticCurveTo(0, OT + 0.32, -pw / 2 - 0.12, OT + 0.12)
    frame.closePath()
    hole = THREE.Path()
    hole.moveTo(-pw / 2, OB)
    hole.lineTo(pw / 2, OB)
    hole.lineTo(pw / 2, OT - 0.02)
    hole.quadraticCurveTo(0, OT + 0.16, -pw / 2, OT - 0.02)
    hole.closePath()
    frame.holes.append(hole)
    g.add(tm(K.extrude(frame, 0.06, {'bevel': 0.014, 'curveSeg': 12}), lac, PAL.harvestGold, {'pos': [0, 0, -D / 2 - 0.03]}))

    # backdrop (night sky) inside the opening
    def draw_sky(ctx, w, h, rand):
        ctx.fillStyle = grad(ctx, 0, 0, 0, h, ['#1B1E4A', '#3A3A8A'])
        ctx.fillRect(0, 0, w, h)
        for i in range(30):
            poly(ctx, starPts(rand() * w, rand() * h * 0.8, 4, 1.6))
            ctx.fillStyle = '#FFF4D6'
            ctx.fill()
        ctx.fillStyle = '#FFF4D6'
        ctx.beginPath()
        ctx.arc(200, 34, 18, 0, TAU)
        ctx.fill()
        ctx.fillStyle = '#58A83E'
        ctx.beginPath()
        ctx.ellipse(60, h + 20, 110, 50, 0, 0, TAU)
        ctx.fill()
        ctx.fillStyle = '#6FBF4A'
        ctx.beginPath()
        ctx.ellipse(200, h + 26, 110, 50, 0, 0, TAU)
        ctx.fill()
    sky = cv('theater_sky', 256, 128, draw_sky)
    g.add(K.m(decalGeo(pw, OT - OB + 0.1), K.mat(game, 'paint', '#ffffff', {'map': sky}),
              {'pos': [0, (OB + OT) / 2, D / 2 - 0.1]}))
    g.add(tm(K.box(pw, 0.04, D - 0.1, 0.012), lac, '#5A3A22', {'pos': [0, OB + 0.02, 0]}))
    # curtain halves (pleated velvet + gold fringe), pivot at the outer top corners
    cw, chh = pw / 2 + 0.03, OT - OB + 0.05
    pleat = THREE.PlaneGeometry(cw, chh, 18, 2)
    p = pleat.attributes.position
    for i in range(p.count):
        p.setZ(i, math.sin((p.getX(i) / cw) * math.pi * 7) * 0.025)
    pleat.rotateY(math.pi)
    pleat.computeVertexNormals()
    K.uvScale(pleat, 2, 2)
    parts = {}
    for s in (-1, 1):
        cg = THREE.Group()
        cg.position.set(s * (pw / 2 + 0.02), OT + 0.05, -D / 2 + 0.03)
        geo = pleat.clone()
        geo.translate(-s * cw / 2, -chh / 2, 0)
        cg.add(K.m(geo, velvet))
        cg.add(tm(K.tube([[0, -chh, 0], [-s * cw, -chh, 0]], 0.022, {'seg': 2, 'radial': 6}), lac, PAL.harvestGold))
        cg.add(tm(K.cyl(0.018, 0.018, 0.1, {'seg': 6}), lac, PAL.harvestGold, {'pos': [-s * cw * 0.8, -chh * 0.55, -0.05]}))
        K.merge(cg)
        cg.userData.noMerge = True
        g.add(cg)
        parts['curtain_r' if s < 0 else 'curtain_l'] = cg  # viewer's left = +x
    # valance: scalloped striped awning + pompoms
    scW, nS = W + 0.2, 9
    sc = [[-scW / 2, 0.3], [scW / 2, 0.3], [scW / 2, 0]]
    for i in range(nS - 1, -1, -1):
        x0 = -scW / 2 + (i + 1) * (scW / nS)
        x1 = x0 - scW / nS
        for k in range(1, 7):
            t = k / 6
            sc.append([lerp(x0, x1, t), -math.sin(t * math.pi) * 0.13])
    val = K.extrude(sc, 0.05, {'bevel': 0.015})
    K.uvScale(val, 1.6, 1.6)
    g.add(K.m(val, stripe, {'pos': [0, OT + 0.28, -D / 2 - 0.1], 'rot': [-0.12, 0, 0]}))
    for i in range(nS):
        g.add(tm(THREE.SphereGeometry(0.045, 10, 8), lac, PAL.barYellow,
                 {'pos': [-scW / 2 + (i + 0.5) * (scW / nS), OT + 0.13, -D / 2 - 0.14]}))
    g.add(tm(K.box(W + 0.24, 0.08, 0.2, 0.03), lac, PAL.harvestGold, {'pos': [0, OT + 0.5, -D / 2 - 0.02]}))

    # crest sign
    def draw_crest(ctx, w, h, rand):
        ctx.clearRect(0, 0, w, h)
        ctx.beginPath()
        ctx.moveTo(10, h - 10)
        ctx.quadraticCurveTo(w / 2, -40, w - 10, h - 10)
        ctx.closePath()
        ctx.fillStyle = PAL.wztvBlue
        ctx.fill()
        ctx.lineWidth = 10
        ctx.strokeStyle = PAL.harvestGold
        ctx.stroke()
        text(ctx, "HOOTIE'S", w / 2, 88, {'font': FONT['groovy'], 'size': 46, 'fill': PAL.barYellow, 'stroke': '#1B2F7A',
                                          'lw': 6})
        text(ctx, 'PUPPET PLAYHOUSE', w / 2, 146, {'font': FONT['sign'], 'size': 34, 'fill': '#F4F1E8',
                                                   'stroke': '#1B2F7A', 'lw': 5, 'maxW': w * 0.8})
    crestTex = cv('theater_crest', 512, 192, draw_crest)
    crest = K.extrude([[-1.05, 0], [1.05, 0], [0.9, 0.35], [0, 0.62], [-0.9, 0.35]], 0.06, {'bevel': 0.02, 'round': 0.3})
    g.add(tm(crest, lac, PAL.harvestGold, {'pos': [0, OT + 0.54, -D / 2 + 0.02]}))
    g.add(K.m(decalGeo(2.0, 0.75), K.mat(game, 'paint', '#ffffff', {'map': crestTex, 'alphaTest': 0.5}),
              {'pos': [0, OT + 0.83, -D / 2 - 0.015]}))
    g.add(tm(K.extrude(starPts(0, 0, 0.2, 0.09), 0.06, {'bevel': 0.015}), lac, PAL.barYellow,
             {'pos': [0, OT + 1.27, -D / 2 + 0.02]}))

    # apron with the three silhouettes
    def draw_apron(ctx, w, h, rand):
        rrect(ctx, 0, 0, w, h, 30)
        ctx.fillStyle = '#23307A'
        ctx.fill()
        ctx.lineWidth = 8
        ctx.strokeStyle = PAL.harvestGold
        rrect(ctx, 8, 8, w - 16, h - 16, 24)
        ctx.stroke()
        for i in range(20):
            poly(ctx, starPts(20 + (i * 83) % (w - 40), 20 + (i * 47) % (h - 40), 5, 2))
            ctx.fillStyle = 'rgba(255,244,214,0.5)'
            ctx.fill()
        ctx.setLineDash([12, 8])
        ctx.lineWidth = 6
        ctx.strokeStyle = '#FFF4DC'
        ctx.fillStyle = 'rgba(255,244,214,0.12)'
        cx, cy = [w * 0.18, w * 0.5, w * 0.82], h * 0.55
        # owl
        ctx.beginPath()
        ctx.ellipse(cx[0], cy + 10, 50, 62, 0, 0, TAU)
        ctx.moveTo(cx[0] - 40, cy - 34)
        ctx.lineTo(cx[0] - 46, cy - 72)
        ctx.lineTo(cx[0] - 14, cy - 50)
        ctx.moveTo(cx[0] + 40, cy - 34)
        ctx.lineTo(cx[0] + 46, cy - 72)
        ctx.lineTo(cx[0] + 14, cy - 50)
        ctx.fill()
        ctx.stroke()
        ctx.beginPath()
        ctx.arc(cx[0] - 20, cy - 12, 15, 0, TAU)
        ctx.moveTo(cx[0] + 35, cy - 12)
        ctx.arc(cx[0] + 20, cy - 12, 15, 0, TAU)
        ctx.stroke()
        # sock
        ctx.beginPath()
        ctx.moveTo(cx[1] - 28, cy - 80)
        ctx.lineTo(cx[1] + 26, cy - 80)
        ctx.lineTo(cx[1] + 26, cy + 20)
        ctx.quadraticCurveTo(cx[1] + 26, cy + 72, cx[1] - 30, cy + 70)
        ctx.quadraticCurveTo(cx[1] - 74, cy + 66, cx[1] - 60, cy + 38)
        ctx.lineTo(cx[1] - 28, cy + 26)
        ctx.closePath()
        ctx.fill()
        ctx.stroke()
        ctx.beginPath()
        ctx.moveTo(cx[1] - 28, cy - 50)
        ctx.lineTo(cx[1] + 26, cy - 50)
        ctx.moveTo(cx[1] - 28, cy - 30)
        ctx.lineTo(cx[1] + 26, cy - 30)
        ctx.stroke()
        # dragon
        ctx.beginPath()
        ctx.moveTo(cx[2] - 50, cy + 60)
        ctx.quadraticCurveTo(cx[2] - 60, cy - 10, cx[2] - 10, cy - 30)
        ctx.lineTo(cx[2] - 4, cy - 70)
        ctx.lineTo(cx[2] + 10, cy - 40)
        ctx.lineTo(cx[2] + 22, cy - 76)
        ctx.lineTo(cx[2] + 28, cy - 36)
        ctx.quadraticCurveTo(cx[2] + 78, cy - 36, cx[2] + 72, cy - 6)
        ctx.quadraticCurveTo(cx[2] + 40, cy + 4, cx[2] + 36, cy + 20)
        ctx.quadraticCurveTo(cx[2] + 40, cy + 60, cx[2] + 20, cy + 60)
        ctx.closePath()
        ctx.fill()
        ctx.stroke()
        ctx.beginPath()
        ctx.arc(cx[2] + 36, cy - 20, 7, 0, TAU)
        ctx.stroke()
        ctx.setLineDash([])
        for i, q in enumerate(['?', '?', '?']):
            text(ctx, q, cx[i], h - 26, {'font': FONT['round'], 'size': 26, 'fill': PAL.barYellow})
    apron = cv('theater_apron', 512, 256, draw_apron)
    AY, AW, AH = 0.72, 2.1, 1.05
    g.add(tm(K.box(AW + 0.08, AH + 0.08, 0.05, 0.04), lac, PAL.harvestGold, {'pos': [0, AY, -D / 2 - 0.02]}))
    g.add(K.m(decalGeo(AW, AH), K.mat(game, 'paint', '#ffffff', {'map': apron}), {'pos': [0, AY, -D / 2 - 0.05]}))
    slotX = [f * AW / 2 / 0.64 * 0.64 for f in [0.64, 0, -0.64]]  # owl (viewer left), sock, dragon
    anchors = {}
    for i, k in enumerate(['owl', 'sock', 'dragon']):
        x = [AW * 0.32, 0, -AW * 0.32][i]
        g.add(K.m(K.tube([[x, AY + 0.42, -D / 2 - 0.05], [x, AY + 0.42, -D / 2 - 0.12], [x, AY + 0.37, -D / 2 - 0.14]],
                         0.012, {'seg': 6, 'radial': 5}), brass))
        anchors['slot_%s' % k] = [x, AY + 0.35, -D / 2 - 0.14]
        anchors['stage_%s' % k] = [x * 0.8, OB + 0.1, -D / 2 + 0.15]
    del slotX
    u = g.userData
    u.parts = parts
    u.anchors = anchors
    u.interact = {'point': [0, 1.0, -0.75], 'radius': 1.5}
    u.colliders = [{'min': [-W / 2 - 0.1, 0, -D / 2 - 0.25], 'max': [W / 2 + 0.1, OT + 1.4, D / 2]}]
    return K.finish(game, g, {'ao': {'res': 60}})


registerProp('puppet_theater', _puppet_theater,
             {'category': CAT, 'tags': ['studio_b', 'kids', 'ee', 'puppets'], 'size': [2.6, 3.7, 1.2],
              'desc': 'striped puppet playhouse with curtain and three empty puppet silhouettes', 'hero': True})


# ---------------------------------------------------------------------------------------- alphabet_block
# 1 m wooden ABC block (rounded maple cube, six painted faces). opts: { variant=0..2 }.
ABC_FACES = [
    ['A', PAL.channelRed, PAL.cream], ['B', PAL.wztvBlue, PAL.cream], ['C', PAL.barGreen, PAL.cream],
    ['H', PAL.burntOrange, '#FFF4DC'], ['13', PAL.cream, PAL.wztvBlue], ['star', PAL.barYellow, PAL.plum],
    ['owl', '#8A5A3A', '#9ED8FF'], ['moon', '#FFF4D6', '#23307A'], ['Z', PAL.plum, '#FFE3A3'],
]


def abcAtlas():
    def draw(ctx, w, h, rand):
        cs = w / 3
        for i, (s, fg, bg) in enumerate(ABC_FACES):
            x, y, c = (i % 3) * cs, math.floor(i / 3) * cs, cs / 2
            ctx.fillStyle = shadeHex(bg, -0.25)
            ctx.fillRect(x, y, cs, cs)
            rrect(ctx, x + 8, y + 8, cs - 16, cs - 16, 18)
            ctx.fillStyle = PAL.channelRed if fg == PAL.cream else shadeHex(fg, 0.1)
            ctx.fill()
            rrect(ctx, x + 18, y + 18, cs - 36, cs - 36, 12)
            ctx.fillStyle = bg
            ctx.fill()
            ctx.fillStyle = 'rgba(255,255,255,0.25)'
            rrect(ctx, x + 18, y + 18, cs - 36, 10, 5)
            ctx.fill()
            if s == 'star':
                poly(ctx, starPts(x + c, y + c + 4, 58, 24))
                ctx.fillStyle = fg
                ctx.fill()
                ctx.lineWidth = 6
                ctx.strokeStyle = shadeHex(fg, -0.5)
                ctx.stroke()
            elif s == 'moon':
                ctx.fillStyle = fg
                ctx.beginPath()
                ctx.arc(x + c, y + c, 50, 0, TAU)
                ctx.fill()
                ctx.fillStyle = bg
                ctx.beginPath()
                ctx.arc(x + c + 26, y + c - 16, 44, 0, TAU)
                ctx.fill()
                poly(ctx, starPts(x + c + 40, y + c + 36, 12, 5))
                ctx.fillStyle = fg
                ctx.fill()
            elif s == 'owl':
                ctx.fillStyle = fg
                ctx.beginPath()
                ctx.ellipse(x + c, y + c + 12, 50, 56, 0, 0, TAU)
                ctx.fill()
                for sd in (-1, 1):
                    poly(ctx, [[x + c + sd * 26, y + c - 30], [x + c + sd * 48, y + c - 64], [x + c + sd * 50, y + c - 20]])
                    ctx.fill()
                    ctx.fillStyle = '#FFF8E8'
                    ctx.beginPath()
                    ctx.arc(x + c + sd * 22, y + c - 4, 19, 0, TAU)
                    ctx.fill()
                    ctx.fillStyle = '#2A1D3A'
                    ctx.beginPath()
                    ctx.arc(x + c + sd * 20, y + c - 2, 9, 0, TAU)
                    ctx.fill()
                    ctx.fillStyle = fg
                ctx.fillStyle = '#F4A020'
                poly(ctx, [[x + c - 9, y + c + 16], [x + c + 9, y + c + 16], [x + c, y + c + 30]])
                ctx.fill()
            else:
                text(ctx, s, x + c, y + c + 6, {'font': FONT['round'], 'size': 88 if len(s) > 1 else 116, 'fill': fg,
                                                'stroke': shadeHex(PAL.wztvBlue if fg == PAL.cream else fg, -0.5),
                                                'lw': 7, 'shadow': 'rgba(0,0,0,0.25)'})
    return cv('abc_atlas', 512, 512, draw)


def _alphabet_block(game, opts=None):
    opts = opts or {}
    v = int(math.fmod(_nn(opts.get('variant'), 0), 3))
    g = K.prop('alphabet_block')
    S = 1.0
    maple = K.mat(game, 'lacquer', '#ffffff', {'map': K.tex.wood('#E8C890', {'dark': 0.22})})
    g.add(K.m(K.box(S, S, S, 0.09, {'uv': 1.2}), maple, {'pos': [0, S / 2, 0]}))
    atlas = K.mat(game, 'lacquer', '#ffffff', {'map': abcAtlas()})
    faces = [[0, 1, 2, 3, 4, 5], [3, 6, 8, 1, 7, 2], [4, 5, 0, 6, 8, 3]][v]

    def cell(i):
        c, r = i % 3, math.floor(i / 3)
        return [c / 3, 1 - (r + 1) / 3, (c + 1) / 3, 1 - r / 3]
    fs, o = S - 0.14, S / 2 + 0.003
    place = [
        [[0, S / 2, -o], [0, 0, 0]], [[-o, S / 2, 0], [0, math.pi / 2, 0]], [[0, S / 2, o], [0, math.pi, 0]],
        [[o, S / 2, 0], [0, -math.pi / 2, 0]],
        [[0, S + 0.003, 0], [math.pi / 2, 0, 0]], [[0, -0.002, 0], [-math.pi / 2, 0, 0]],
    ]
    for i, (p, r) in enumerate(place):
        if i == 5:
            continue  # bottom face hidden
        m = K.m(decalGeo(fs, fs, cell(faces[i])), atlas, {'pos': p})
        m.rotation.set(*r)
        g.add(m)
    u = g.userData
    u.colliders = [{'min': [-S / 2, 0, -S / 2], 'max': [S / 2, S, S / 2]}]
    return K.finish(game, g, {'ao': {'res': 40}})


registerProp('alphabet_block', _alphabet_block,
             {'category': CAT, 'tags': ['studio_b', 'kids', 'block'], 'size': [1, 1, 1],
              'desc': '1 m wooden alphabet block'})


# ---------------------------------------------------------------------------------------- rainbow_arch
# Walk-through pillowy rainbow arch (6 soft bands) standing on two puffy clouds with gold stars.
# Opening ~2.5 m wide x 2.2 m tall. Colliders: the two cloud feet.
def _rainbow_arch(game, opts=None):
    g = K.prop('rainbow_arch')
    plastic = K.mat(game, 'plastic', '#ffffff', {'rough': 0.5})
    cols = [PAL.barRed, PAL.burntOrange, PAL.barYellow, PAL.barGreen, PAL.barBlue, PAL.plum]
    R0, dr, cy, tr = 1.35, 0.21, 0.95, 0.125
    for i, c in enumerate(cols):
        r = R0 + (len(cols) - 1 - i) * dr
        pts = []
        for k in range(21):
            a = (k / 20) * math.pi
            pts.append([math.cos(a) * r, cy + math.sin(a) * r, 0])
        g.add(tm(K.tube(pts, tr, {'seg': 28, 'radial': 8}), plastic, c))
    cloudM = K.mat(game, 'plastic', '#ffffff', {'rough': 0.55})
    for s in (-1, 1):
        cx = s * (R0 + 2.5 * dr)
        for dx, dy, dz, r in [[0, 0.45, 0, 0.55], [0.42, 0.32, 0.08, 0.4], [-0.42, 0.34, -0.05, 0.42],
                              [0.12, 0.85, 0.05, 0.42], [-0.2, 0.25, 0.3, 0.3], [0.25, 0.22, -0.32, 0.3]]:
            sp = THREE.SphereGeometry(r, 12, 9)
            g.add(tm(sp, cloudM, '#FFFFFF' if dy > 0.7 else '#EFE8FF', {'pos': [cx + dx * s, dy, dz]}))
        for k in range(2):
            st = K.extrude(starPts(0, 0, 0.13, 0.055), 0.05, {'bevel': 0.015})
            g.add(tm(st, plastic, PAL.marqueeGold, {'pos': [cx + s * (0.35 - k * 0.6), 1.05 + k * 0.25, -0.45 + k * 0.1],
                                                    'rot': [0, 0, 0.2 * s]}))
    u = g.userData
    fx = R0 + 2.5 * dr
    u.colliders = [{'min': [s * fx - 0.75, 0, -0.55], 'max': [s * fx + 0.75, 1.3, 0.55]} for s in (-1, 1)]
    return K.finish(game, g, {'ao': {'res': 56}})


registerProp('rainbow_arch', _rainbow_arch,
             {'category': CAT, 'tags': ['studio_b', 'kids', 'arch', 'walkthrough'], 'size': [5.6, 3.6, 1.2],
              'desc': 'walk-through pillowy rainbow arch on clouds', 'hero': True})


# ---------------------------------------------------------------------------------------- giant crayons
CRAYONS = [['#E23B3B', 'RED'], ['#3A58E4', 'BLUE'], ['#F4E03A', 'YELLOW'], ['#52D24A', 'GREEN'], ['#B05AD6', 'PURPLE'],
           ['#FF8A2A', 'ORANGE']]


def crayonGroup(game, color, name, len_=1.7):
    r = 0.12
    grp = THREE.Group()
    wax = K.mat(game, 'plastic', '#ffffff', {'rough': 0.55})

    def draw_wrap(ctx, w, h, rand):
        ctx.fillStyle = color
        ctx.fillRect(0, 0, w, h)
        ctx.fillStyle = '#1E1530'
        for y in (10, h - 22):
            ctx.beginPath()
            x = 0
            while x <= w:
                ctx.lineTo(x, y + (12 if (x / 16 % 2) else 0))
                x += 16
            ctx.lineTo(w, y + 4)
            ctx.lineTo(0, y + 4)
            ctx.fill()
        ctx.fillStyle = 'rgba(255,255,255,0.9)'
        rrect(ctx, 20, 38, w - 40, 52, 26)
        ctx.fill()
        text(ctx, 'HOOTIE', w / 2, 56, {'font': FONT['round'], 'size': 20, 'fill': '#1E1530'})
        text(ctx, name, w / 2, 78, {'font': FONT['sign'], 'size': 18, 'fill': shadeHex(color, -0.3), 'maxW': w * 0.6})
    wrapTex = cv('crayon_wrap_%s' % name, 256, 128, draw_wrap, True)
    wrap = K.mat(game, 'paint', '#ffffff', {'map': wrapTex})
    bodyL = len_ * 0.8
    grp.add(tm(K.cyl(r * 0.97, r * 0.97, bodyL, {'seg': 16, 'bevel': 0.02}), wax, color))
    wg = THREE.CylinderGeometry(r + 0.006, r + 0.006, bodyL * 0.72, 16, 1, True)
    K.uvScale(wg, 2, 1)
    grp.add(K.m(wg, wrap, {'pos': [0, bodyL * 0.48, 0]}))
    tip = K.lathe([[r * 0.97, 0], [r * 0.9, 0.03], [r * 0.3, len_ * 0.18], [r * 0.18, len_ * 0.2], [0, len_ * 0.2]],
                  {'seg': 16}).clone()
    # worn flat facet on the tip
    p = tip.attributes.position
    for i in range(p.count):
        x, y = p.getX(i), p.getY(i)
        lim = len_ * 0.2 - 0.06 + x * 0.5
        if y > lim and x > 0:
            p.setY(i, lim)
    tip.computeVertexNormals()
    grp.add(tm(tip, wax, color, {'pos': [0, bodyL, 0]}))
    return grp


def _giant_crayon(game, opts=None):
    opts = opts or {}
    g = K.prop('giant_crayon')
    color, name = CRAYONS[int(math.fmod(_nn(opts.get('color'), 0), len(CRAYONS)))]
    c = crayonGroup(game, color, name, _nn(opts.get('length'), 1.7))
    if _nn(opts.get('pose'), 'lie') == 'lie':
        c.rotation.z = math.pi / 2
        c.position.set(0.85, 0.12, 0)
        c.rotation.x = 0.2
    g.add(c)
    return K.finish(game, g, {'ao': {'res': 40}})


registerProp('giant_crayon', _giant_crayon,
             {'category': CAT, 'tags': ['studio_b', 'kids', 'crayon'], 'size': [1.7, 0.25, 0.25],
              'desc': 'giant wax crayon (opts.color 0..5, pose lie|stand)'})


# Giant open crayon box (HOOTIE CRAYONS) with four crayons standing in it and two on the floor.
def _giant_crayons(game, opts=None):
    g = K.prop('giant_crayons')
    card = K.mat(game, 'paint', '#ffffff')

    def draw_box(ctx, w, h, rand):
        ctx.fillStyle = PAL.barYellow
        ctx.fillRect(0, 0, w, h)
        ctx.fillStyle = PAL.barGreen
        ctx.beginPath()
        ctx.moveTo(0, h * 0.55)
        ctx.quadraticCurveTo(w / 2, h * 0.35, w, h * 0.55)
        ctx.lineTo(w, h)
        ctx.lineTo(0, h)
        ctx.fill()
        ctx.fillStyle = PAL.channelRed
        for i in range(6):
            ctx.beginPath()
            ctx.arc(40 + i * 86, h * 0.9, 20, 0, TAU)
            ctx.fill()
        text(ctx, 'HOOTIE', w / 2, h * 0.2, {'font': FONT['groovy'], 'size': 96, 'fill': PAL.wztvBlue, 'stroke': '#fff',
                                             'lw': 10, 'maxW': w * 0.9})
        text(ctx, 'CRAYONS', w / 2, h * 0.38, {'font': FONT['sign'], 'size': 70, 'fill': PAL.channelRed, 'stroke': '#fff',
                                               'lw': 8, 'maxW': w * 0.9})
        text(ctx, '8 GROOVY COLORS!', w / 2, h * 0.7, {'font': FONT['round'], 'size': 40, 'fill': '#fff',
                                                       'stroke': '#1E4A1E', 'lw': 6, 'maxW': w * 0.9})
    boxTex = cv('crayon_box', 512, 512, draw_box)
    boxMat = K.mat(game, 'paint', '#ffffff', {'map': boxTex})
    BW, BH, BD, th = 0.95, 0.8, 0.42, 0.03
    g.add(K.m(K.box(BW, BH, th, 0.012), boxMat, {'pos': [0, BH / 2, -BD / 2]}))
    g.add(K.m(K.box(BW, BH, th, 0.012), boxMat, {'pos': [0, BH / 2, BD / 2]}))
    for s in (-1, 1):
        g.add(tm(K.box(th, BH, BD, 0.012), card, PAL.barGreen, {'pos': [s * BW / 2, BH / 2, 0]}))
    g.add(tm(K.box(BW, th, BD, 0.012), card, PAL.barGreen, {'pos': [0, th / 2, 0]}))
    # open flap
    flap = K.m(tg(K.box(BW, 0.3, th, 0.012), PAL.barYellow), card)
    flap.position.set(0, BH + 0.13, BD / 2 + 0.06)
    flap.rotation.x = -0.45
    g.add(flap)
    heights = [1.5, 1.72, 1.6, 1.36]
    for i in range(4):
        c, n = CRAYONS[i]
        cr = crayonGroup(game, c, n, heights[i])
        cr.position.set(-0.33 + i * 0.22, 0.03, (0.06 if i % 2 else -0.06))
        cr.rotation.z = (i - 1.5) * 0.06
        g.add(cr)
    for i in range(2):
        c, n = CRAYONS[4 + i]
        cr = crayonGroup(game, c, n, 1.55)
        cr.rotation.z = math.pi / 2
        cr.rotation.y = 0.5 if i else -0.2
        cr.position.set(0.9 if i else 0.6, 0.12, 0.55 if i else -0.62)
        g.add(cr)
    u = g.userData
    u.colliders = [{'min': [-BW / 2, 0, -BD / 2], 'max': [BW / 2, 1.75, BD / 2]}]
    return K.finish(game, g, {'ao': {'res': 56}})


registerProp('giant_crayons', _giant_crayons,
             {'category': CAT, 'tags': ['studio_b', 'kids', 'crayon'], 'size': [1.8, 1.8, 1.4],
              'desc': 'giant open crayon box with crayons'})


# ---------------------------------------------------------------------------------------- toy_train_loop
# Wind-up toy train on a round track (toy_train): chunky loco + block wagon + caboose, cardboard tunnel.
# parts.train: rotate .rotation.y around the loop center (track radius 1.1 m).
def _toy_train_loop(game, opts=None):
    g = K.prop('toy_train_loop')
    lac = K.mat(game, 'lacquer', '#ffffff')
    chrome = K.mat(game, 'chrome', '#A8B0BA')
    RT = 1.1

    def draw_ties(ctx, w, h, rand):
        ctx.clearRect(0, 0, w, h)
        for i in range(16):
            rrect(ctx, i * 32 + 6, 4, 20, h - 8, 5)
            ctx.fillStyle = '#8A5A34' if i % 2 else '#7A4A2A'
            ctx.fill()
            ctx.fillStyle = 'rgba(255,255,255,0.12)'
            ctx.fillRect(i * 32 + 8, 6, 16, 4)
    ties = cv('train_ties', 512, 64, draw_ties, True)
    tieMat = K.mat(game, 'paint', '#ffffff', {'map': ties, 'alphaTest': 0.5})
    rg = THREE.RingGeometry(RT - 0.13, RT + 0.13, 72, 1)
    p, uv = rg.attributes.position, rg.attributes.uv
    for i in range(p.count):
        a = math.atan2(p.getY(i), p.getX(i))
        r = js_hypot(p.getX(i), p.getY(i))
        uv.setXY(i, (a / TAU) * 12, (r - (RT - 0.13)) / 0.26)
    rg.rotateX(-math.pi / 2)
    g.add(K.m(rg, tieMat, {'pos': [0, 0.012, 0]}))
    for r in (RT - 0.07, RT + 0.07):
        t = THREE.TorusGeometry(r, 0.012, 5, 56)
        t.rotateX(math.pi / 2)
        g.add(K.m(t, chrome, {'pos': [0, 0.035, 0]}))

    # tunnel (painted cardboard mountain)
    def draw_tun(ctx, w, h, rand):
        ctx.fillStyle = '#6FBF4A'
        ctx.fillRect(0, 0, w, h)
        ctx.fillStyle = '#58A83E'
        for i in range(12):
            ctx.beginPath()
            ctx.arc((i * 47) % w, 20 + (i * 31) % 80, 14, 0, TAU)
            ctx.fill()
        ctx.fillStyle = '#FFF4DC'
        for i in range(5):
            ctx.beginPath()
            ctx.arc(30 + i * 50, 100 - (i % 2) * 20, 4, 0, TAU)
            ctx.fill()
    tun = cv('train_tunnel', 256, 128, draw_tun, True)
    tunG = THREE.CylinderGeometry(0.34, 0.34, 0.8, 16, 1, True, 0, math.pi)
    tunG.rotateZ(math.pi / 2)
    tunG.rotateY(math.pi / 2)
    tunnel = K.m(tunG, K.mat(game, 'paint', '#ffffff', {'map': tun, 'side': THREE.DoubleSide}))
    tunnel.position.set(-RT, 0, 0.0)
    g.add(tunnel)
    for z in (-0.4, 0.4):
        g.add(tm(THREE.TorusGeometry(0.34, 0.035, 6, 16, math.pi), lac, PAL.channelRed, {'pos': [-RT, 0, z]}))
    # train on the loop
    train = THREE.Group()
    wheelG = K.cyl(0.055, 0.055, 0.03, {'seg': 10, 'bevel': 0.008}).clone()
    wheelG.rotateX(math.pi / 2)

    def car(build, ang):
        cg = THREE.Group()
        cg.position.set(math.cos(ang) * RT, 0.04, -math.sin(ang) * RT)
        cg.rotation.y = ang
        build(cg)
        for x in (-0.12, 0.12):
            for z in (-0.075, 0.075):
                cg.add(tm(wheelG, lac, PAL.barYellow, {'pos': [x, 0.055, z]}))
        train.add(cg)

    # loco (faces -z in its frame = direction of travel for +rotation.y)
    def loco(c):
        c.add(tm(K.box(0.2, 0.08, 0.36, 0.025), lac, '#2A2230', {'pos': [0, 0.1, 0]}))
        boiler = K.cyl(0.085, 0.085, 0.24, {'seg': 16, 'bevel': 0.02}).clone()
        boiler.rotateX(math.pi / 2)
        c.add(tm(boiler, lac, PAL.channelRed, {'pos': [0, 0.22, -0.04 + 0.12]}).translateZ(-0.24))
        c.add(tm(K.box(0.2, 0.2, 0.14, 0.03), lac, PAL.wztvBlue, {'pos': [0, 0.25, 0.12]}))
        c.add(tm(K.box(0.24, 0.035, 0.18, 0.015), lac, PAL.channelRed, {'pos': [0, 0.36, 0.12]}))
        c.add(tm(K.lathe([[0, 0], [0.03, 0], [0.032, 0.08], [0.055, 0.13], [0.05, 0.14], [0, 0.14]], {'seg': 12}), lac,
                 '#2A2230', {'pos': [0, 0.29, -0.14]}))
        c.add(tm(K.extrude([[-0.1, 0], [0.1, 0], [0, 0.09]], 0.08, {'bevel': 0.01}).rotateX(-math.pi / 2), lac,
                 PAL.barYellow, {'pos': [0, 0.07, -0.2]}))
        c.add(K.m(THREE.CircleGeometry(0.03, 12).rotateY(math.pi), K.glow(game, '#FFF2C0', 3), {'pos': [0, 0.22, -0.168]}))
        c.add(K.m(THREE.SphereGeometry(0.05, 10, 8), chrome, {'pos': [0, 0.31, -0.02]}))
    car(loco, 0)

    def wagon(c):
        c.add(tm(K.box(0.22, 0.12, 0.3, 0.03), lac, PAL.barGreen, {'pos': [0, 0.14, 0]}))
        bc = [PAL.channelRed, PAL.barYellow, PAL.wztvBlue]
        for i in range(3):
            c.add(tm(K.box(0.08, 0.08, 0.08, 0.015), lac, bc[i], {'pos': [(i - 1) * 0.05, 0.24, (i - 1) * 0.08],
                                                                  'rot': [0, i * 0.4, 0]}))
    car(wagon, -0.42)

    def caboose(c):
        c.add(tm(K.box(0.22, 0.2, 0.28, 0.035), lac, PAL.burntOrange, {'pos': [0, 0.18, 0]}))
        c.add(tm(K.box(0.26, 0.03, 0.32, 0.012), lac, '#5A3A22', {'pos': [0, 0.3, 0]}))
        c.add(tm(K.box(0.14, 0.08, 0.12, 0.02), lac, PAL.burntOrange, {'pos': [0, 0.35, 0]}))
        for s in (-1, 1):
            c.add(K.m(THREE.CircleGeometry(0.03, 10).rotateY(s * math.pi / 2), K.glow(game, '#FFE3A3', 1.8),
                      {'pos': [s * 0.112, 0.2, 0]}))
    car(caboose, -0.8)
    train.userData.noMerge = True
    K.merge(train)
    g.add(train)
    u = g.userData
    u.parts = {'train': train}
    u.interact = {'point': [0, 0.5, 0], 'radius': 1.6}
    u.colliders = [{'min': [-RT - 0.4, 0, -0.45], 'max': [-RT + 0.4, 0.4, 0.45]}]
    return K.finish(game, g, {'ao': {'res': 56}})


registerProp('toy_train_loop', _toy_train_loop,
             {'category': CAT, 'tags': ['studio_b', 'kids', 'toy', 'train'], 'size': [2.6, 0.45, 2.6],
              'desc': 'toy train on a round track with a cardboard tunnel', 'hero': True})


# ---------------------------------------------------------------------------------------- xylophone
# Giant pull-toy xylophone (toy_xylophone): 8 rainbow bars (parts.bars InstancedMesh, per-bar bounce), wooden
# frame on red wheels, pull cord, two mallets (parts.mallets). Bars at y ~0.6.
def _xylophone(game, opts=None):
    g = K.prop('xylophone')
    lac = K.mat(game, 'lacquer', '#ffffff')
    chrome = K.mat(game, 'chrome', '#A8B0BA')
    maple = K.mat(game, 'lacquer', '#ffffff', {'map': K.tex.wood('#E8C890', {'dark': 0.25})})
    L, BY = 1.4, 0.56
    # trapezoid frame: two converging rails
    wBig, wSmall = 0.82, 0.48
    for s in (-1, 1):
        a, b = V3(-L / 2, BY - 0.06, s * wBig / 2 * 0.62), V3(L / 2, BY - 0.06, s * wSmall / 2 * 0.62)
        rail = K.m(K.box(a.distanceTo(b) + 0.14, 0.1, 0.09, 0.03, {'uv': 2}), maple)
        rail.position.copy(a).add(b).multiplyScalar(0.5)
        rail.rotation.y = -math.atan2(b.z - a.z, b.x - a.x)
        g.add(rail)
    # body skirt + base
    g.add(K.m(K.taper(K.box(L + 0.1, 0.34, 0.66, 0.06, {'uv': 1.5}), {'axis': 'x', 'k': 0.72}), maple, {'pos': [0, 0.3, 0]}))
    g.add(tm(K.taper(K.box(L + 0.14, 0.05, 0.7, 0.02), {'axis': 'x', 'k': 0.72}), lac, PAL.channelRed, {'pos': [0, 0.47, 0]}))
    for x, z in [[-0.55, -0.36], [-0.55, 0.36], [0.55, -0.28], [0.55, 0.28]]:
        wh = K.cyl(0.12, 0.12, 0.07, {'seg': 14, 'bevel': 0.02}).clone()
        wh.rotateX(math.pi / 2)
        g.add(tm(wh, lac, PAL.channelRed, {'pos': [x, 0.12, z]}))
        g.add(K.m(K.cyl(0.035, 0.035, 0.08, {'seg': 10}).clone().rotateX(math.pi / 2), chrome,
                  {'pos': [x, 0.12, z + js_sign(z) * 0.01]}))
    # bars (instanced) + studs
    cols = [PAL.barRed, PAL.burntOrange, PAL.barYellow, PAL.barGreen, PAL.barCyan, PAL.barBlue, PAL.plum, PAL.neonPink]
    barGeo = K.box(0.13, 0.045, 1.0, 0.018)
    xf = []
    for i in range(8):
        t = i / 7
        x = -L / 2 + 0.12 + t * (L - 0.24)
        ln = lerp(0.8, 0.46, t)
        xf.append({'pos': [x, BY + 0.03, 0], 'scale': [1, 1, ln]})
        for s in (-1, 1):
            g.add(K.m(THREE.SphereGeometry(0.014, 6, 4), chrome, {'pos': [x, BY + 0.06, s * ln * 0.38]}))
    bars = instanced(barGeo, K.mat(game, 'metal', '#ffffff', {'rough': 0.35}), xf, cols, 'bars')
    g.add(bars)
    # mallets
    mallets = THREE.Group()
    for s in (-1, 1):
        a, b = V3(-0.1 + s * 0.14, BY + 0.1, -0.1), V3(0.35 + s * 0.12, BY + 0.14, -0.62 - s * 0.05)
        mallets.add(rod(0.012, maple, a, b, 6))
        mallets.add(tm(THREE.SphereGeometry(0.045, 12, 9), lac, PAL.channelRed if s < 0 else PAL.wztvBlue,
                       {'pos': a.toArray()}))
    K.merge(mallets)
    mallets.userData.noMerge = True
    g.add(mallets)
    # pull cord + bead
    g.add(tm(K.tube([[L / 2 + 0.05, 0.3, 0], [L / 2 + 0.3, 0.15, -0.05], [L / 2 + 0.45, 0.02, 0.1],
                     [L / 2 + 0.6, 0.02, 0.25]], 0.008, {'seg': 16, 'radial': 4}), lac, '#E8E0C8'))
    g.add(tm(THREE.SphereGeometry(0.05, 12, 9), lac, PAL.barYellow, {'pos': [L / 2 + 0.62, 0.05, 0.27]}))
    u = g.userData
    u.parts = {'bars': bars, 'mallets': mallets}
    u.bars = [{'pos': t['pos'], 'len': t['scale'][2]} for t in xf]
    u.interact = {'point': [0, 0.6, -0.4], 'radius': 1.3}
    u.colliders = [{'min': [-L / 2 - 0.1, 0, -0.45], 'max': [L / 2 + 0.1, BY + 0.1, 0.45]}]
    return K.finish(game, g, {'ao': {'res': 48}})


registerProp('xylophone', _xylophone,
             {'category': CAT, 'tags': ['studio_b', 'kids', 'toy', 'music'], 'size': [2.2, 0.7, 1.0],
              'desc': 'giant rainbow pull-toy xylophone', 'hero': True})


# =========================================================================================================
# EASTER-EGG OBJECTS
# =========================================================================================================

# ---------------------------------------------------------------------------------------- chime_rack
# Announce-booth electric chime rack (ee_chime_rack): walnut frame, four anodized tubular bars on eye hooks with
# solenoid strikers, control box. Bars left->right as seen from the front: green, blue, red, yellow (GDD §13).
# parts.bar_red / bar_yellow / bar_green / bar_blue: Groups pivoting at the hook (swing = .rotation.x).
# userData.chimes[color] = { len, note, hz, center:[x,y,z] }. Place at [~-6.5, 0, -4.5] with rotY = -PI/2 to get
# the exact GDD z positions (red -4.7, yellow -5.1, green -3.9, blue -4.3).
CHIMES = {'red': {'len': 1.2, 'note': 'G4', 'hz': 392.0, 'col': '#E23B3B', 'x': -0.2},
          'yellow': {'len': 1.05, 'note': 'C5', 'hz': 523.3, 'col': '#F4C81E', 'x': -0.6},
          'green': {'len': 0.9, 'note': 'E5', 'hz': 659.3, 'col': '#3FBF4A', 'x': 0.6},
          'blue': {'len': 0.75, 'note': 'G5', 'hz': 784.0, 'col': '#3A68E4', 'x': 0.2}}


def _chime_rack(game, opts=None):
    g = K.prop('chime_rack')
    walnut = K.mat(game, 'walnut', '#ffffff', {'map': K.tex.wood(PAL.walnut, {'dark': 0.35})})
    brass = K.mat(game, 'brass', '#C8963C')
    chrome = K.mat(game, 'chrome', '#A8B0BA')
    lac = K.mat(game, 'lacquer', '#ffffff')
    W, TOP, HOOK = 1.72, 2.08, 1.96
    g.add(K.m(K.box(W, 0.12, 0.52, 0.035, {'uv': 1.5}), walnut, {'pos': [0, 0.1, 0]}))
    g.add(K.m(K.box(W + 0.06, 0.04, 0.58, 0.015, {'uv': 1.5}), walnut, {'pos': [0, 0.18, 0]}))
    for x, z in [[-1, -1], [1, -1], [-1, 1], [1, 1]]:
        g.add(K.m(K.cyl(0.035, 0.045, 0.04, {'seg': 10}), brass, {'pos': [x * (W / 2 - 0.08), 0, z * 0.2]}))
    for s in (-1, 1):
        g.add(K.m(K.box(0.1, TOP - 0.1, 0.1, 0.025, {'uv': 1.5, 'swap': True}), walnut,
                  {'pos': [s * (W / 2 - 0.08), (TOP - 0.1) / 2 + 0.1, 0]}))
        g.add(K.m(K.lathe([[0, 0], [0.06, 0], [0.065, 0.03], [0.05, 0.06], [0.07, 0.11], [0.04, 0.16], [0, 0.17]],
                          {'round': 0.01, 'seg': 12, 'steps': 1}), brass, {'pos': [s * (W / 2 - 0.08), TOP + 0.06, 0]}))
        # brace
        a, b = V3(s * (W / 2 - 0.08), 0.2, 0.14), V3(s * (W / 2 - 0.08), 0.75, 0.04)
        g.add(between(K.box(0.05, a.distanceTo(b), 0.05, 0.012), walnut, a, b).translateY(a.distanceTo(b) / 2))
    g.add(K.m(K.box(W, 0.13, 0.15, 0.035, {'uv': 1.5}), walnut, {'pos': [0, TOP, 0]}))
    plate = K.tex.label('WZTV  ·  STATION CHIMES', {'bg': '#E8C878', 'fg': '#3A2418', 'accent': '#8A5A20', 'w': 512,
                                                         'h': 64, 'border': 0.1, 'wear': 0.15})
    g.add(K.m(decalGeo(0.72, 0.09), K.mat(game, 'brass', '#ffffff', {'map': plate, 'rough': 0.35}),
              {'pos': [0, TOP, -0.078]}))
    # front striker rail with 4 solenoids
    g.add(K.m(K.cyl(0.012, 0.012, W - 0.2, {'seg': 8}).clone().rotateZ(math.pi / 2).translate((W - 0.2) / 2, 0, 0),
              chrome, {'pos': [0, HOOK - 0.1, -0.12]}))
    parts, chimes = {}, {}
    for name, c in CHIMES.items():
        # solenoid + hammer
        g.add(K.m(K.cyl(0.028, 0.028, 0.09, {'seg': 12, 'bevel': 0.008}), chrome, {'pos': [c['x'], HOOK - 0.15, -0.12]}))
        g.add(tm(K.cyl(0.03, 0.03, 0.02, {'seg': 12, 'bevel': 0.006}), lac, c['col'], {'pos': [c['x'], HOOK - 0.06, -0.12]}))
        g.add(K.m(K.tube([[c['x'], HOOK - 0.15, -0.12], [c['x'], HOOK - 0.19, -0.09], [c['x'], HOOK - 0.2, -0.055]],
                         0.007, {'seg': 6, 'radial': 5}), brass))
        # eye hook
        g.add(K.m(THREE.TorusGeometry(0.018, 0.005, 5, 10), brass, {'pos': [c['x'], HOOK + 0.03, 0], 'rot': [0, math.pi / 2, 0]}))
        bar = THREE.Group()
        bar.position.set(c['x'], HOOK, 0)
        mat = K.mat(game, 'metal', c['col'], {'rough': 0.28, 'env': 0.5, 'rim': 0.3})
        bar.add(K.m(K.cyl(0.033, 0.033, c['len'] - 0.08, {'seg': 12, 'bevel': 0.004}), mat, {'pos': [0, -c['len'] + 0.04, 0]}))
        bar.add(K.m(K.lathe([[0, 0], [0.036, 0], [0.038, 0.012], [0.036, 0.05], [0.02, 0.06], [0, 0.062]], {'seg': 12}),
                    chrome, {'pos': [0, -0.07, 0]}))
        bar.add(K.m(K.lathe([[0, 0], [0.036, 0.004], [0.038, 0.03], [0.036, 0.04], [0, 0.04]], {'seg': 12}), chrome,
                    {'pos': [0, -c['len'], 0]}))
        bar.add(K.m(THREE.TorusGeometry(0.014, 0.005, 5, 10), chrome, {'pos': [0, 0, 0], 'rot': [0, 0, 0]}))
        bar.add(K.m(K.cyl(0.036, 0.036, 0.03, {'seg': 12, 'bevel': 0.004}), chrome, {'pos': [0, -0.24, 0]}))
        K.merge(bar)
        bar.userData.noMerge = True
        g.add(bar)
        parts['bar_%s' % name] = bar
        chimes[name] = {'len': c['len'], 'note': c['note'], 'hz': c['hz'], 'center': [c['x'], HOOK - c['len'] / 2, 0]}
    # control box with four colored buttons
    g.add(tm(K.taper(K.box(0.42, 0.16, 0.26, 0.03), {'axis': 'y', 'k': 0.85}), lac, '#E8DCC0', {'pos': [0.35, 0.28, -0.05]}))
    for i, n in enumerate(['green', 'blue', 'red', 'yellow']):
        g.add(tm(K.cyl(0.025, 0.028, 0.03, {'seg': 10, 'bevel': 0.008}), lac, CHIMES[n]['col'],
                 {'pos': [0.5 - i * 0.1, 0.36, -0.07]}))
    g.add(K.m(K.tube([[0.14, 0.26, 0.0], [0.0, 0.2, 0.05], [-0.4, 0.2, 0.06], [-0.78, 0.5, 0.05], [-0.78, 1.8, 0.05]],
                     0.009, {'seg': 20, 'radial': 4}), K.mat(game, 'rubber', '#2A2230')))
    u = g.userData
    u.parts = parts
    u.chimes = chimes
    u.colliders = [{'min': [-W / 2, 0, -0.28], 'max': [W / 2, TOP + 0.2, 0.28]}]
    return K.finish(game, g, {'ao': {'res': 56}})


registerProp('chime_rack', _chime_rack,
             {'category': CAT, 'tags': ['lobby', 'booth', 'ee', 'chimes'], 'size': [1.8, 2.3, 0.6],
              'desc': 'four-bar electric station chime rack (red/yellow/green/blue)', 'hero': True})


# ---------------------------------------------------------------------------------------- trophy_case
# Lobby trophy case (ee_trophy_case): walnut cabinet, plum velvet back, lit crown, glass shelves, golden winged-TV
# "Telly Award" statuettes and plaques; the glass front door is parts.door (pivot on the viewer's left edge,
# open = rotation.y ~ -1.9). anchors.dudley = the empty middle-shelf spot (GDD [-6.75,1.3,-2.0] against the
# west wall: back at local +z).
def tellyAward(gold, base, s=1):
    g = THREE.Group()
    g.add(K.m(K.box(0.16 * s, 0.05 * s, 0.12 * s, 0.01, {'seg': 1}), base, {'pos': [0, 0.025 * s, 0]}))
    g.add(K.m(K.box(0.12 * s, 0.04 * s, 0.09 * s, 0.008, {'seg': 1}), base, {'pos': [0, 0.07 * s, 0]}))
    g.add(K.m(K.lathe([[0, 0], [0.03, 0], [0.018, 0.03], [0.014, 0.08], [0.03, 0.1], [0, 0.1]], {'seg': 8}), gold,
              {'pos': [0, 0.09 * s, 0], 'scale': s}))
    g.add(K.m(K.box(0.14 * s, 0.11 * s, 0.09 * s, 0.028 * s, {'seg': 2}), gold, {'pos': [0, 0.245 * s, 0]}))
    g.add(K.m(K.box(0.1 * s, 0.075 * s, 0.02 * s, 0.012, {'seg': 1}), base, {'pos': [-0.008 * s, 0.245 * s, -0.04 * s]}))
    for sd in (-1, 1):
        wing = K.extrude([[0, 0], [0.12, 0.05], [0.14, 0.11], [0.1, 0.09], [0.11, 0.14], [0.06, 0.1], [0.05, 0.13],
                          [0.0, 0.07]], 0.016, {'bevel': 0.004, 'bevelSeg': 1})
        wm = K.m(wing, gold, {'pos': [sd * 0.065 * s, 0.22 * s, 0.01 * s], 'scale': [sd * s, s, s]})
        g.add(wm)
    for sd in (-1, 1):
        g.add(K.m(K.cyl(0.004 * s, 0.004 * s, 0.09 * s, {'seg': 5}), gold,
                  {'pos': [sd * 0.02 * s, 0.295 * s, 0], 'rot': [0, 0, -sd * 0.5]}))
    return g


def _trophy_case(game, opts=None):
    g = K.prop('trophy_case')
    walnut = K.mat(game, 'walnut', '#ffffff', {'map': K.tex.wood(PAL.walnut, {'dark': 0.35})})
    velvet = K.mat(game, 'fabric', '#ffffff', {'map': K.tex.weave('#5A2A5E', {'pattern': 'plain', 'scale': 2})})
    gold = K.mat(game, 'brass', '#E0B04A', {'rough': 0.22})
    blackLac = K.mat(game, 'lacquer', '#2A1D2A')
    glass = game.mats.glass('#DDEFFF', {'opacity': 0.09})
    W, H, D, t = 1.6, 2.1, 0.55, 0.06
    # carcass
    g.add(K.m(K.box(W + 0.08, 0.2, D + 0.05, 0.03, {'uv': 1.5}), walnut, {'pos': [0, 0.1, 0]}))
    g.add(K.m(K.box(W + 0.14, 0.14, D + 0.1, 0.04, {'uv': 1.5}), walnut, {'pos': [0, H - 0.07, 0]}))
    g.add(K.m(K.box(W + 0.2, 0.05, D + 0.14, 0.02, {'uv': 1.5}), walnut, {'pos': [0, H + 0.02, 0]}))
    for s in (-1, 1):
        g.add(K.m(K.box(t, H - 0.2, D, 0.02, {'uv': 1.5, 'swap': True}), walnut, {'pos': [s * (W / 2 - t / 2), H / 2, 0]}))
    g.add(K.m(K.box(W - 0.1, H - 0.3, 0.03, 0.01, {'uv': 2.5}), velvet, {'pos': [0, H / 2, D / 2 - 0.03]}))
    g.add(K.m(K.box(W - 0.1, 0.03, D - 0.05, 0.01, {'uv': 2.5}), velvet, {'pos': [0, 0.215, 0]}))
    # lit crown strip
    g.add(K.m(K.box(W - 0.2, 0.025, 0.04, 0.01), K.glow(game, '#FFE6B8', 2.2), {'pos': [0, H - 0.16, -D / 2 + 0.1],
                                                                                 'cast': False}))
    # glass shelves with brass clips
    for y in (0.6, 1.02, 1.47):
        g.add(K.m(K.box(W - 0.14, 0.018, D - 0.12, 0.006), glass, {'pos': [0, y, 0.02]}))
        for s in (-1, 1):
            g.add(K.m(K.box(0.03, 0.02, 0.03, 0.006), gold, {'pos': [s * (W / 2 - 0.08), y - 0.015, 0.02]}))

    # awards
    def addAward(x, y, s, rot=0):
        a = tellyAward(gold, blackLac, s)
        a.position.set(x, y, 0.04)
        a.rotation.y = rot
        g.add(a)
    addAward(0, 1.48, 1.32)
    addAward(0.5, 1.48, 1.12, -0.25)
    addAward(-0.5, 1.48, 1.12, 0.25)
    addAward(0.52, 1.03, 1.18, -0.2)
    addAward(-0.52, 1.03, 1.18, 0.2)

    # plaques + pennant on the bottom shelf
    def draw_plq(ctx, w, h, rand):
        for i in range(2):
            x = i * 128
            rrect(ctx, x + 4, 4, 120, 120, 12)
            ctx.fillStyle = '#6A3A22'
            ctx.fill()
            rrect(ctx, x + 18, 22, 92, 70, 6)
            ctx.fillStyle = grad(ctx, 0, 22, 0, 92, ['#FFF2B0', '#E8B84A', '#B07A16'])
            ctx.fill()
            text(ctx, 'BEST' if i else 'TELLY', x + 64, 44, {'font': FONT['sign'], 'size': 16, 'fill': '#5A3A08'})
            text(ctx, 'HOST' if i else '1976', x + 64, 70, {'font': FONT['sign'], 'size': 18, 'fill': '#5A3A08'})
    plq = cv('trophy_plaques', 256, 128, draw_plq)
    plqMat = K.mat(game, 'lacquer', '#ffffff', {'map': plq})
    for i in range(2):
        p = K.m(K.uvRect(K.box(0.26, 0.26, 0.03, 0.01).clone(), i / 2, 0, (i + 1) / 2, 1), plqMat,
                {'pos': [-0.35 + i * 0.7, 0.74, D / 2 - 0.12], 'rot': [-0.18, -0.15 if i else 0.15, 0]})
        g.add(p)

    def draw_pennant(ctx, w, h, rand):
        ctx.beginPath()
        ctx.moveTo(0, 0)
        ctx.lineTo(w, h / 2)
        ctx.lineTo(0, h)
        ctx.closePath()
        ctx.fillStyle = PAL.channelRed
        ctx.fill()
        ctx.fillStyle = '#F4F1E8'
        ctx.fillRect(0, 0, 22, h)
        text(ctx, 'WZTV 13', 100, h / 2 + 2, {'font': FONT['sign'], 'size': 26, 'fill': '#F4F1E8', 'maxW': 150})
    pennant = cv('trophy_pennant', 256, 96, draw_pennant)
    g.add(K.m(decalGeo(0.7, 0.26), K.mat(game, 'fabric', '#ffffff', {'map': pennant, 'alphaTest': 0.5,
                                                                       'side': THREE.DoubleSide}),
              {'pos': [0, 0.4, D / 2 - 0.05], 'rot': [0, 0, -0.08]}))
    # name plate
    namePlate = K.tex.label('TELLY AWARDS', {'sub': 'WZTV CHANNEL 13 · EXCELLENCE IN BROADCASTING', 'bg': '#E8C878',
                                             'fg': '#3A2418', 'accent': '#8A5A20', 'w': 512, 'h': 128, 'wear': 0.1})
    g.add(K.m(decalGeo(0.56, 0.14), K.mat(game, 'brass', '#ffffff', {'map': namePlate, 'rough': 0.35}),
              {'pos': [0, 0.1, -D / 2 - 0.028]}))
    # glass door (pivot on the viewer's left = +x edge)
    door = THREE.Group()
    door.position.set(W / 2 - 0.03, 0, -D / 2)
    df = K.roundRect(W - 0.06, H - 0.36, 0.03)
    df.holes.append(THREE.Path(K.roundRect(W - 0.2, H - 0.5, 0.02).getPoints(4)))
    door.add(K.m(K.uvScale(K.extrude(df, 0.035, {'bevel': 0.01, 'curveSeg': 4}), 1.5, 1.5), walnut,
                 {'pos': [-(W - 0.06) / 2, H / 2 + 0.02, -0.02]}))
    door.add(K.m(THREE.PlaneGeometry(W - 0.18, H - 0.48), glass, {'pos': [-(W - 0.06) / 2, H / 2 + 0.02, -0.02]}))
    door.add(K.m(K.cyl(0.012, 0.012, 0.14, {'seg': 8}), gold, {'pos': [-(W - 0.06) + 0.05, H / 2 - 0.05, -0.055]}))
    door.userData.noMerge = True
    g.add(door)
    for y in (0.4, H - 0.4):
        g.add(K.m(K.cyl(0.012, 0.012, 0.1, {'seg': 8}), gold, {'pos': [W / 2 - 0.02, y, -D / 2 - 0.02]}))
    u = g.userData
    u.parts = {'door': door}
    u.anchors = {'dudley': [0, 1.3, 0.0], 'door_drop': [0.6, 0, -0.9]}
    u.lightAnchors = [{'pos': [0, H - 0.3, -0.3], 'color': '#FFE6B8', 'intensity': 1.2, 'distance': 3.5}]
    u.colliders = [{'min': [-W / 2 - 0.1, 0, -D / 2 - 0.05], 'max': [W / 2 + 0.1, H + 0.05, D / 2 + 0.07]}]
    return K.finish(game, g, {'ao': {'res': 56}})


registerProp('trophy_case', _trophy_case,
             {'category': CAT, 'tags': ['lobby', 'ee', 'trophy', 'wall'], 'size': [1.8, 2.15, 0.7],
              'desc': 'walnut trophy case with golden winged-TV Telly Awards and a glass door', 'hero': True})


# ---------------------------------------------------------------------------------------- neon_logo_partition
# Lobby partition (4 x 2.4 x 0.3 m, walnut paneling + 70s stripe band) carrying the neon WZTV 13 logo on its
# front: four tube letters W red, Z yellow, T green, V blue + the "13" disc (red neon ring, white 13).
# parts.neon_W/Z/T/V/13 (tube meshes) + halo_W/Z/T/V/13 (additive glow cards). setNeon(prop, game, key, level)
# with level 0..1 (0.2 = dead tube, still visibly colored). opts.state: 'lit' (default) | 'dark' | 'broken'.
NEON = {'W': PAL.neonW, 'Z': PAL.neonZ, 'T': PAL.neonT, 'V': PAL.neonV, '13': '#FFF6E8'}
NEON_PATHS = {
    'W': [[[-0.27, 0.3], [-0.15, -0.3], [0, 0.12], [0.15, -0.3], [0.27, 0.3]]],
    'Z': [[[-0.21, 0.3], [0.22, 0.3], [-0.22, -0.3], [0.22, -0.3]]],
    'T': [[[-0.24, 0.3], [0.24, 0.3]], [[0, 0.3], [0, -0.3]]],
    'V': [[[-0.24, 0.3], [0, -0.3], [0.24, 0.3]]],
    '13': [[[-0.2, 0.12], [-0.12, 0.2], [-0.12, -0.2]],
           [[0.02, 0.14], [0.08, 0.2], [0.17, 0.19], [0.2, 0.1], [0.14, 0.02], [0.08, 0.01], [0.15, -0.01], [0.21, -0.09],
            [0.18, -0.18], [0.09, -0.21], [0.02, -0.15]]],
}


def neonLevelMat(game, key, level):
    q = js_round(clamp(level, 0, 1) * 20) / 20
    return K.glow(game, NEON[key], (0.12 + q ** 1.5 * 2.9) * (0.62 if key == '13' else 1))


def haloMat(game, key, level, map_):
    q = js_round(clamp(level, 0, 1) * 20) / 20
    return K.glow(game, NEON[key], (0.01 + q ** 2 * 0.76) * (0.35 if key == '13' else 1), {'map': map_, 'additive': True})


def _neon_logo_partition(game, opts=None):
    opts = opts or {}
    g = K.prop('neon_logo_partition')
    W, H, D = 4.0, 2.4, 0.3
    lac = K.mat(game, 'lacquer', '#ffffff')
    chrome = K.mat(game, 'chrome', '#A8B0BA')
    panel = K.mat(game, 'walnut', '#ffffff', {'map': woodPanel(PAL.walnut)})
    g.add(K.m(K.uvScale(K.box(W, H - 0.12, D, 0.13, {'uv': 1}).clone(), 0.85, 0.42), panel, {'pos': [0, H / 2 + 0.04, 0]}))
    g.add(tm(K.box(W + 0.04, 0.1, D + 0.04, 0.04), lac, '#2A1810', {'pos': [0, 0.05, 0]}))
    g.add(tm(K.box(W + 0.06, 0.07, D + 0.06, 0.03), lac, PAL.harvestGold, {'pos': [0, H + 0.0, 0]}))
    for c, y in [[PAL.burntOrange, 0.98], [PAL.harvestGold, 0.86], [PAL.chocolate, 0.76]]:
        g.add(tm(K.box(W + 0.02, 0.09, D + 0.02, 0.04), lac, c, {'pos': [0, y, 0]}))
    # backer board for the logo
    BW, BH, BY, fz = 3.5, 0.98, 1.9, -D / 2
    g.add(tm(K.extrude(K.roundRect(BW, BH, 0.2), 0.05, {'bevel': 0.02}), lac, '#1E1530', {'pos': [0, BY, fz - 0.02]}))
    g.add(K.m(K.tube(roundRectLoop(BW + 0.02, BH + 0.02, 0.21), 0.012, {'seg': 80, 'radial': 5, 'closed': True}), chrome,
              {'pos': [0, BY, fz - 0.045]}))
    # halo atlas (soft white glows of each glyph)
    keys = ['W', 'Z', 'T', 'V', '13']

    def draw_halo(ctx, w, h, rand):
        ctx.fillStyle = '#000'
        ctx.fillRect(0, 0, w, h)
        for i, k in enumerate(keys):
            ctx.save()
            ctx.translate(i * 128 + 64, 64)
            ctx.filter = 'blur(9px)'
            ctx.strokeStyle = '#fff'
            ctx.lineWidth = 16
            ctx.lineCap = 'round'
            ctx.lineJoin = 'round'
            for st in NEON_PATHS[k]:
                ctx.beginPath()
                for j, (x, y) in enumerate(st):
                    if j:
                        ctx.lineTo(x * 170, -y * 170)
                    else:
                        ctx.moveTo(x * 170, -y * 170)
                ctx.stroke()
            if k == '13':
                ctx.beginPath()
                ctx.arc(0, 0, 50, 0, TAU)
                ctx.stroke()
            ctx.restore()
    halo = cv('neon_halo', 640, 128, draw_halo)
    state = _nn(opts.get('state'), 'lit')

    def lvl(k):
        return 0.2 if state == 'dark' else (0.2 if state == 'broken' and (k == 'Z' or k == 'T') else 1)
    xs = {'W': 1.28, 'Z': 0.66, 'T': 0.07, 'V': -0.52, '13': -1.24}  # prop x (viewer's left = +x)
    parts = {}

    def tubeMat(k):
        return neonLevelMat(game, k, lvl(k))
    cap = K.mat(game, 'plastic', '#2A2230')
    for k in keys:
        cx = xs[k]
        tg2 = []
        strokes = NEON_PATHS[k]
        for st in strokes:
            pts = [[cx - x * 1.0, BY + y * 1.0, fz - 0.1] for x, y in K.roundProfile(st, 0.035, 3)]
            tg2.append(K.tube(pts, 0.021, {'seg': max(8, len(pts) * 3), 'radial': 7}).clone())
            for e in [st[0], st[len(st) - 1]]:
                g.add(K.m(K.cyl(0.026, 0.026, 0.05, {'seg': 8}).clone().rotateX(math.pi / 2), cap,
                          {'pos': [cx - e[0], BY + e[1], fz - 0.075]}))
            # standoff clips
            mid = st[int(math.floor(len(st) / 2))]
            g.add(K.m(K.cyl(0.008, 0.008, 0.07, {'seg': 6}).clone().rotateX(math.pi / 2), chrome,
                      {'pos': [cx - mid[0], BY + mid[1], fz - 0.08]}))
        if k == '13':
            # blue disc + red neon ring behind the white 13
            g.add(tm(K.cyl(0.34, 0.34, 0.05, {'seg': 32, 'bevel': 0.015}).clone().rotateX(-math.pi / 2), lac, PAL.wztvBlue,
                     {'pos': [cx, BY, fz - 0.04]}))
            ring = K.m(THREE.TorusGeometry(0.32, 0.022, 8, 40), neonLevelMat(game, 'W', lvl(k)), {'pos': [cx, BY, fz - 0.1]})
            ring.userData.noMerge = True
            ring.userData.noOcclude = True
            g.add(ring)
            parts['neon_ring'] = ring
            tube = K.m(mergeGeos(tg2), tubeMat(k))
        else:
            tube = K.m(mergeGeos(tg2) if len(tg2) > 1 else tg2[0], tubeMat(k))
        tube.userData.noMerge = True
        tube.userData.noOcclude = True
        g.add(tube)
        parts['neon_%s' % k] = tube
        i = keys.index(k)
        hl = K.m(decalGeo(0.78, 0.78, [i / 5, 0, (i + 1) / 5, 1]), haloMat(game, k, lvl(k), halo),
                 {'pos': [cx, BY, fz - 0.242 if k == '13' else fz - 0.052], 'cast': False})
        hl.userData.noMerge = True
        hl.userData.noAO = True
        hl.userData.noOcclude = True
        g.add(hl)
        parts['halo_%s' % k] = hl
    u = g.userData
    u.parts = parts
    u.neon = {'keys': keys, 'state': state}
    u.colliders = [{'min': [-W / 2 - 0.03, 0, -D / 2 - 0.12], 'max': [W / 2 + 0.03, H + 0.05, D / 2 + 0.03]}]
    u.lightAnchors = [{'pos': [0, BY, -1.0], 'color': '#FF9AC8', 'intensity': 1.5, 'distance': 5}]
    return K.finish(game, g, {'ao': {'res': 64}})


registerProp('neon_logo_partition', _neon_logo_partition,
             {'category': CAT, 'tags': ['lobby', 'ee', 'neon', 'logo', 'partition'], 'size': [4.1, 2.45, 0.45],
              'desc': 'walnut lobby partition with the neon WZTV 13 logo (4 separately lit letters)', 'cache': False,
              'hero': True})


def roundRectLoop(w, h, r, n=5):
    pts = []
    cs = [[w / 2 - r, h / 2 - r, 0], [-w / 2 + r, h / 2 - r, math.pi / 2], [-w / 2 + r, -h / 2 + r, math.pi],
          [w / 2 - r, -h / 2 + r, math.pi * 1.5]]
    for cx, cy, a0 in cs:
        for i in range(n + 1):
            a = a0 + (i / n) * (math.pi / 2)
            pts.append([cx + math.cos(a) * r, cy + math.sin(a) * r, 0])
    return pts

# setNeon(prop, game, key, level): runtime (Godot) — tube material = neonLevelMat(key, level) (+ neon_ring with 'W'
# for '13'), halo = haloMat(key, level, same map).


# ---------------------------------------------------------------------------------------- letter_board
# Lobby changeable-letter board on a walnut easel (cards.js 'letter_board'): parts.face (swap its map to
# getCard('letter_board', { signOff: true }) after the easter egg), two fallen letters on the floor.
def _letter_board(game, opts=None):
    opts = opts or {}
    g = K.prop('letter_board')
    walnut = K.mat(game, 'walnut', '#ffffff', {'map': K.tex.wood(PAL.walnut, {'dark': 0.35})})
    brass = K.mat(game, 'brass', '#C8963C')
    FW, FH, CY = 1.6, 1.0, 1.45
    face = K.m(decalGeo(FW, FH), K.mat(game, 'felt', '#ffffff', {'map': getCard('letter_board',
                                                                                 {'signOff': K._truthy(opts.get('signOff'))}),
                                                                 'rim': 0.12}), {'pos': [0, CY, -0.02]})
    face.userData.noMerge = True
    g.add(face)
    fr = K.roundRect(FW + 0.14, FH + 0.14, 0.06)
    fr.holes.append(THREE.Path(K.roundRect(FW - 0.1, FH - 0.1, 0.03).getPoints(4)))
    g.add(K.m(K.uvScale(K.extrude(fr, 0.07, {'bevel': 0.02, 'curveSeg': 6}), 1.5, 1.5), walnut, {'pos': [0, CY, -0.01]}))
    g.add(K.m(K.box(FW + 0.1, FH + 0.1, 0.03, 0.01, {'uv': 1.5}), walnut, {'pos': [0, CY, 0.02]}))
    # easel: two front legs + back leg, ledge
    for s in (-1, 1):
        a, b = V3(s * 0.62, 0, -0.12), V3(s * 0.5, CY + FH / 2 + 0.18, 0.04)
        g.add(between(K.box(0.07, a.distanceTo(b), 0.05, 0.015, {'uv': 1.5, 'swap': True}), walnut, a, b)
              .translateY(a.distanceTo(b) / 2))
        g.add(K.m(K.cyl(0.03, 0.035, 0.03, {'seg': 8}), brass, {'pos': [s * 0.62, 0, -0.12]}))
        g.add(K.m(K.lathe([[0, 0], [0.035, 0], [0.04, 0.03], [0, 0.07]], {'round': 0.01, 'seg': 10}), brass,
                  {'pos': [s * 0.5, CY + FH / 2 + 0.2, 0.04]}))
    bl = [V3(0, 0, 0.7), V3(0, CY + FH / 2 + 0.1, 0.06)]
    g.add(between(K.box(0.06, bl[0].distanceTo(bl[1]), 0.045, 0.015, {'uv': 1.5, 'swap': True}), walnut, bl[0], bl[1])
          .translateY(bl[0].distanceTo(bl[1]) / 2))
    g.add(K.m(K.box(FW + 0.2, 0.05, 0.14, 0.018, {'uv': 1.5}), walnut, {'pos': [0, CY - FH / 2 - 0.09, -0.05]}))

    # fallen letters on the floor
    def draw_lt(ctx, w, h, rand):
        ctx.clearRect(0, 0, w, h)
        text(ctx, 'G', 32, 34, {'font': FONT['sign'], 'size': 52, 'fill': '#F4F1E8'})
        text(ctx, 'F', 96, 34, {'font': FONT['sign'], 'size': 52, 'fill': '#F4F1E8'})
    lt = cv('fallen_letters', 128, 64, draw_lt)
    ltMat = K.mat(game, 'plastic', '#ffffff', {'map': lt, 'alphaTest': 0.5})
    for i, x, z, r in [[0, 0.3, -0.45, 0.4], [1, -0.25, -0.62, -0.7]]:
        gg = THREE.PlaneGeometry(0.1, 0.1)
        K.uvRect(gg, i / 2, 0.05, (i + 1) / 2, 0.95)
        gg.rotateX(-math.pi / 2)
        g.add(K.m(gg, ltMat, {'pos': [x, 0.004, z], 'rot': [0, r, 0]}))
    u = g.userData
    u.parts = {'face': face}
    u.colliders = [{'min': [-0.9, 0, -0.2], 'max': [0.9, CY + FH / 2 + 0.3, 0.75]}]
    return K.finish(game, g, {'ao': {'res': 48}})


registerProp('letter_board', _letter_board,
             {'category': CAT, 'tags': ['lobby', 'ee', 'sign'], 'size': [1.8, 2.2, 0.9],
              'desc': 'changeable-letter lobby board on a walnut easel'})


# ---------------------------------------------------------------------------------------- weather_map
# Newsroom magnetic weather map (ee_weather_map), wall mounted (back at local z ~ +0.05): cards.js weather_map
# face in a chunky teal frame, light hood, tray with a pointer and the spare storm magnet.
# parts.magnet_sun_a/sun_b/cloud/rain/bolt/storm (Meshes: slide by moving .position.x/.y on the face plane).
# anchors.tower_icon (face point of the red tower), anchors.face_z; showMagnet(prop, name, [x,y]|None).
MAGNETS = [['sun_a', 'sun', 0.25, 0.38], ['sun_b', 'sun', 0.6, 0.3], ['cloud', 'cloud', 0.43, 0.62],
           ['rain', 'rain', 0.18, 0.72], ['bolt', 'bolt', 0.62, 0.72]]


def _weather_map(game, opts=None):
    g = K.prop('weather_map')
    lac = K.mat(game, 'lacquer', '#ffffff')
    chrome = K.mat(game, 'chrome', '#A8B0BA')
    MW, MH, CY, fz = 2.2, 1.65, 1.55, -0.06
    g.add(K.m(decalGeo(MW, MH), K.mat(game, 'lacquer', '#ffffff', {'map': getCard('weather_map')}), {'pos': [0, CY, fz]}))
    fr = K.roundRect(MW + 0.22, MH + 0.22, 0.1)
    fr.holes.append(THREE.Path(K.roundRect(MW - 0.04, MH - 0.04, 0.05).getPoints(5)))
    g.add(tm(K.extrude(fr, 0.1, {'bevel': 0.03, 'curveSeg': 8}), lac, PAL.teal, {'pos': [0, CY, fz + 0.02]}))
    g.add(tm(K.box(MW + 0.1, MH + 0.1, 0.05, 0.02), lac, '#23307A', {'pos': [0, CY, 0.0]}))
    # light hood with glowing underside + plaque
    hood = THREE.CylinderGeometry(0.16, 0.16, MW + 0.2, 20, 1, False, math.pi * 0.5, math.pi)
    hood.rotateZ(math.pi / 2)
    g.add(tm(hood, lac, PAL.teal, {'pos': [0, CY + MH / 2 + 0.2, fz - 0.12]}))
    g.add(K.m(K.box(MW + 0.1, 0.02, 0.16, 0.008), K.glow(game, '#FFF2D8', 2.0), {'pos': [0, CY + MH / 2 + 0.1, fz - 0.12],
                                                                                 'cast': False}))
    for s in (-1, 1):
        g.add(K.m(K.tube([[s * (MW / 2 - 0.1), CY + MH / 2 + 0.2, fz - 0.05], [s * (MW / 2 - 0.1), CY + MH / 2 + 0.28, fz + 0.03]],
                         0.014, {'seg': 3, 'radial': 6}), chrome))
    plq = K.tex.label('WEATHER WATCH 13', {'bg': PAL.wztvBlue, 'fg': '#F4F1E8', 'accent': PAL.harvestGold, 'w': 512,
                                           'h': 96, 'border': 0.12, 'wear': 0.05})
    g.add(K.m(decalGeo(0.9, 0.17), K.mat(game, 'lacquer', '#ffffff', {'map': plq}), {'pos': [0, CY + MH / 2 + 0.2, fz - 0.285]}))
    # tray, pointer, eraser
    g.add(tm(K.box(MW + 0.1, 0.05, 0.16, 0.02), lac, PAL.teal, {'pos': [0, CY - MH / 2 - 0.14, fz - 0.07]}))
    g.add(tm(K.box(MW + 0.1, 0.06, 0.02, 0.008), lac, PAL.teal, {'pos': [0, CY - MH / 2 - 0.1, fz - 0.15]}))
    g.add(K.m(K.cyl(0.008, 0.012, 0.9, {'seg': 8}).clone().rotateZ(math.pi / 2).translate(0.45, 0, 0),
              K.mat(game, 'teak', '#ffffff', {'map': K.tex.wood(PAL.teak)}), {'pos': [-0.3, CY - MH / 2 - 0.1, fz - 0.07]}))
    g.add(tm(K.box(0.14, 0.05, 0.06, 0.015), lac, PAL.channelRed, {'pos': [0.75, CY - MH / 2 - 0.09, fz - 0.07]}))
    # magnets
    parts = {}

    def place(u_, v_):
        return [(0.5 - u_) * MW, CY + (0.5 - v_) * MH]

    def addMag(name, kind, x, y, z):
        m = K.m(decalGeo(0.3, 0.3), K.mat(game, 'plastic', '#ffffff', {'map': getCard('magnet_%s' % kind), 'alphaTest': 0.35}),
                {'pos': [x, y, z]})
        m.userData.noMerge = True
        m.userData.noOcclude = True
        g.add(m)
        parts['magnet_%s' % name] = m
    for name, kind, u_, v_ in MAGNETS:
        x, y = place(u_, v_)
        addMag(name, kind, x, y, fz - 0.012)
    addMag('storm', 'storm', -0.65, CY - MH / 2 - 0.02, fz - 0.1)
    parts['magnet_storm'].rotation.x = -0.25
    tx, ty = place(400 / 512, (238 - 16) / 384)
    u = g.userData
    u.parts = parts
    u.anchors = {'tower_icon': [tx, ty, fz - 0.012], 'face_z': fz - 0.012, 'face': {'w': MW, 'h': MH, 'cy': CY}}
    u.colliders = [{'min': [-MW / 2 - 0.15, CY - MH / 2 - 0.2, -0.3], 'max': [MW / 2 + 0.15, CY + MH / 2 + 0.4, 0.05]}]
    u.lightAnchors = [{'pos': [0, CY + 0.3, -0.7], 'color': '#FFF2D8', 'intensity': 1.3, 'distance': 4}]
    return K.finish(game, g, {'ao': {'res': 56}})


registerProp('weather_map', _weather_map,
             {'category': CAT, 'tags': ['newsroom', 'ee', 'weather', 'wall'], 'size': [2.45, 2.6, 0.4],
              'desc': 'magnetic Tri-County weather map with sliding magnets'})

# showMagnet(prop, name, pos): runtime (Godot) — hide, or move magnet_<name> onto the face (z = face_z - 0.004).


# ---------------------------------------------------------------------------------------- rundown_board
# Master Control rundown cork board (ee_rundown_board): "SPOOKTACULAR RUNDOWN" header, six empty marker-outlined
# slots with push pins; parts.card_1..card_6 (hidden; setRundownCard(prop, n, true) pins card n with its star).
# opts.filled = how many cards are shown (default 0).
def _rundown_board(game, opts=None):
    opts = opts or {}
    g = K.prop('rundown_board')
    walnut = K.mat(game, 'walnut', '#ffffff', {'map': K.tex.wood(PAL.walnut, {'dark': 0.3})})
    lac = K.mat(game, 'lacquer', '#ffffff')
    BW, BH, CY, fz = 1.8, 1.25, 1.5, -0.03
    slots = []
    for r in range(2):
        for c in range(3):
            slots.append([(1 - c) * 0.56, CY + 0.04 - r * 0.42])

    def draw_cork(ctx, w, h, rand):
        ctx.fillStyle = '#C8955A'
        ctx.fillRect(0, 0, w, h)
        for i in range(5000):
            ctx.fillStyle = 'rgba(120,70,30,0.35)' if rand() < 0.5 else 'rgba(240,200,140,0.3)'
            ctx.fillRect(rand() * w, rand() * h, 1 + rand() * 2.5, 1 + rand() * 2)
        # slot outlines (canvas coords: viewer left = canvas left)
        ctx.setLineDash([10, 7])
        ctx.lineWidth = 4
        ctx.strokeStyle = 'rgba(60,30,60,0.55)'
        for r in range(2):
            for c in range(3):
                x, y = w / 2 + (c - 1) * (0.56 / BW) * w, h / 2 - (0.04 - r * 0.42) / BH * h
                sw, sh = (0.44 / BW) * w, (0.28 / BH) * h
                rrect(ctx, x - sw / 2, y - sh / 2, sw, sh, 8)
                ctx.stroke()
                ctx.setLineDash([])
                text(ctx, js_str(r * 3 + c + 1), x, y + 4, {'font': FONT['hand'], 'size': 34, 'fill': 'rgba(60,30,60,0.35)'})
                ctx.setLineDash([10, 7])
        ctx.setLineDash([])
    cork = cv('rundown_cork', 512, 384, draw_cork)
    g.add(K.m(decalGeo(BW, BH), K.mat(game, 'felt', '#ffffff', {'map': cork, 'rim': 0.12}), {'pos': [0, CY, fz]}))
    fr = K.roundRect(BW + 0.14, BH + 0.14, 0.05)
    fr.holes.append(THREE.Path(K.roundRect(BW - 0.02, BH - 0.02, 0.02).getPoints(4)))
    g.add(K.m(K.uvScale(K.extrude(fr, 0.06, {'bevel': 0.018, 'curveSeg': 5}), 1.5, 1.5), walnut, {'pos': [0, CY, fz + 0.01]}))
    g.add(K.m(K.box(BW + 0.08, BH + 0.08, 0.03, 0.01, {'uv': 1.5}), walnut, {'pos': [0, CY, 0.01]}))
    # header card
    g.add(K.m(decalGeo(0.96, 0.24), K.mat(game, 'paint', '#ffffff', {'map': getCard('rundown_header')}),
              {'pos': [0, CY + BH / 2 - 0.2, fz - 0.006], 'rot': [0, 0, 0.01]}))
    # push pins
    pinCols = [PAL.channelRed, PAL.barYellow, PAL.wztvBlue, PAL.barGreen, PAL.channelRed, PAL.plum]
    pinHead = K.lathe([[0, 0], [0.018, 0], [0.02, 0.012], [0.012, 0.022], [0.016, 0.032], [0, 0.034]],
                      {'round': 0.004, 'seg': 10}).clone()
    pinHead.rotateX(-math.pi / 2)
    for i, (x, y) in enumerate(slots):
        g.add(tm(pinHead, lac, pinCols[i], {'pos': [x, y + 0.11, fz - 0.004]}))
    for x, y in [[-0.43, CY + BH / 2 - 0.2], [0.43, CY + BH / 2 - 0.2]]:
        g.add(tm(pinHead, lac, PAL.channelRed, {'pos': [x, y, fz - 0.01]}))

    # old memo in the corner
    def draw_memo(ctx, w, h, rand):
        ctx.fillStyle = '#FFF6A8'
        ctx.fillRect(0, 0, w, h)
        ctx.fillStyle = 'rgba(0,0,0,0.08)'
        ctx.fillRect(0, h - 10, w, 10)
        for i, ln in enumerate(['SIGN OFF', '12:00 AM', 'DON\'T FORGET', 'THE TAPE!']):
            text(ctx, ln, w / 2, 30 + i * 32, {'font': FONT['hand'], 'size': 18, 'fill': '#2A2A8A', 'rot': -0.04})
    memo = cv('rundown_memo', 128, 160, draw_memo)
    g.add(K.m(decalGeo(0.2, 0.25), K.mat(game, 'paint', '#ffffff', {'map': memo}),
              {'pos': [-BW / 2 + 0.17, CY - BH / 2 + 0.2, fz - 0.005], 'rot': [0, 0, 0.12]}))
    g.add(tm(pinHead, lac, PAL.barGreen, {'pos': [-BW / 2 + 0.17, CY - BH / 2 + 0.3, fz - 0.009]}))
    # the six cards (hidden until earned)
    parts = {}
    filled = _nn(opts.get('filled'), 0)
    for i, (x, y) in enumerate(slots):
        c = K.m(decalGeo(0.42, 0.26), K.mat(game, 'paint', '#ffffff', {'map': getCard('rundown_card_%d' % (i + 1),
                                                                                       {'star': True})}),
                {'pos': [x, y, fz - 0.008]})
        c.rotation.z = ((i * 37) % 7 - 3) * 0.012
        c.visible = i < filled
        c.userData.noMerge = True
        g.add(c)
        parts['card_%d' % (i + 1)] = c
    u = g.userData
    u.parts = parts
    u.anchors = {'slots': [[x, y, fz - 0.008] for x, y in slots]}
    u.colliders = [{'min': [-BW / 2 - 0.08, CY - BH / 2 - 0.08, -0.1], 'max': [BW / 2 + 0.08, CY + BH / 2 + 0.08, 0.04]}]
    return K.finish(game, g, {'ao': {'res': 48, 'floor': False, 'height': 0}})


registerProp('rundown_board', _rundown_board,
             {'category': CAT, 'tags': ['master_control', 'ee', 'board', 'wall'], 'size': [1.95, 1.4, 0.1],
              'desc': 'Spooktacular rundown cork board with six trophy slots'})

# setRundownCard(prop, n, on): runtime (Godot) — parts.card_<n>.visible = on.


# ---------------------------------------------------------------------------------------- kill_switch_cage
# Transmitter kill-switch cage (ee_kill_switch): red steel frame with expanded-metal mesh, hinged padlocked door
# (parts.door, pivot on the viewer's left edge, open = rotation.y ~ -1.7), and inside a giant knife switch on a
# slate panel (parts.switch: pivot at the hinge clips, closed/up = 0, thrown/down = rotation.x ~ +1.9).
# Back of the cage at local +z (against the tower leg). anchors.handle for the hold prompt.
def _kill_switch_cage(game, opts=None):
    g = K.prop('kill_switch_cage')
    lac = K.mat(game, 'lacquer', '#ffffff')
    paint = K.mat(game, 'paint', '#ffffff')
    copper = K.mat(game, 'brass', '#D07A4A', {'rough': 0.3})
    chrome = K.mat(game, 'chrome', '#A8B0BA')
    W, H, D, RED = 1.3, 2.1, 0.8, '#C8282E'

    def draw_mesh(ctx, w, h, rand):
        ctx.clearRect(0, 0, w, h)
        ctx.strokeStyle = '#ffffff'
        ctx.lineWidth = 5
        ctx.lineJoin = 'round'
        y = -32
        while y <= h + 32:
            x = -32
            while x <= w + 32:
                ctx.beginPath()
                ctx.moveTo(x, y + 16)
                ctx.lineTo(x + 16, y)
                ctx.lineTo(x + 32, y + 16)
                ctx.lineTo(x + 16, y + 32)
                ctx.closePath()
                ctx.stroke()
                x += 32
            y += 32
    meshTex = cv('cage_mesh', 128, 128, draw_mesh, True)
    mesh = K.mat(game, 'metal', RED, {'map': meshTex, 'alphaTest': 0.5, 'side': THREE.DoubleSide})

    # concrete pad
    def draw_conc(ctx, w, h, rand):
        ctx.fillStyle = '#9A9490'
        ctx.fillRect(0, 0, w, h)
        speckle(ctx, w, h, rand, 1800, 0.12)
    conc = cv('concrete', 256, 256, draw_conc, True)
    g.add(K.m(K.box(W + 0.4, 0.1, D + 0.4, 0.03, {'uv': 1}), K.mat(game, 'paint', '#ffffff', {'map': conc}),
              {'pos': [0, 0.05, 0]}))
    Y0 = 0.1

    # frame edges (except the front door opening)
    def post(x, z):
        return g.add(tm(K.box(0.06, H, 0.06, 0.012), paint, RED, {'pos': [x, Y0 + H / 2, z]}))
    for x, z in [[-1, -1], [1, -1], [-1, 1], [1, 1]]:
        post(x * (W / 2 - 0.03), z * (D / 2 - 0.03))
    for y in (Y0 + 0.03, Y0 + H - 0.03, Y0 + H / 2):
        g.add(tm(K.box(W, 0.05, 0.05, 0.012), paint, RED, {'pos': [0, y, D / 2 - 0.03]}))
        for s in (-1, 1):
            g.add(tm(K.box(0.05, 0.05, D, 0.012), paint, RED, {'pos': [s * (W / 2 - 0.03), y, 0]}))
    g.add(tm(K.box(W, 0.05, 0.05, 0.012), paint, RED, {'pos': [0, Y0 + H - 0.03, -D / 2 + 0.03]}))
    # mesh panels: sides + top
    for s in (-1, 1):
        p = THREE.PlaneGeometry(D - 0.06, H - 0.06)
        K.uvScale(p, 5, 13)
        p.rotateY(math.pi / 2)
        g.add(K.m(p, mesh, {'pos': [s * (W / 2 - 0.03), Y0 + H / 2, 0]}))
    p = THREE.PlaneGeometry(W - 0.06, D - 0.06)
    K.uvScale(p, 8, 5)
    p.rotateX(-math.pi / 2)
    g.add(K.m(p, mesh, {'pos': [0, Y0 + H - 0.03, 0]}))
    # back panel with the knife switch
    g.add(tm(K.box(W - 0.14, H - 0.3, 0.04, 0.012), paint, '#6A7078', {'pos': [0, Y0 + H / 2 + 0.05, D / 2 - 0.06]}))
    PZ = D / 2 - 0.1
    g.add(tm(K.box(0.56, 0.86, 0.05, 0.02), lac, '#3A3A44', {'pos': [0, Y0 + 1.15, PZ]}))
    g.add(tm(K.box(0.5, 0.8, 0.03, 0.02), lac, '#EDE6D6', {'pos': [0, Y0 + 1.15, PZ - 0.035]}))
    JY, HY, SZ = Y0 + 1.44, Y0 + 0.86, PZ - 0.07
    for x in (-0.11, 0.11):
        for y, hh in [[JY, 0.12], [HY, 0.08]]:
            g.add(K.m(K.box(0.018, hh, 0.07, 0.005), copper, {'pos': [x - 0.028, y, SZ + 0.02]}),
                  K.m(K.box(0.018, hh, 0.07, 0.005), copper, {'pos': [x + 0.028, y, SZ + 0.02]}))
            g.add(K.m(K.box(0.08, 0.03, 0.03, 0.008), copper, {'pos': [x, y - hh / 2, SZ + 0.04]}))
    sw = THREE.Group()
    sw.position.set(0, HY, SZ)
    for x in (-0.11, 0.11):
        sw.add(K.m(K.box(0.03, 0.62, 0.012, 0.005), copper, {'pos': [x, 0.31, 0]}))
    sw.add(K.m(K.cyl(0.016, 0.016, 0.3, {'seg': 8}).clone().rotateZ(math.pi / 2).translate(0.15, 0, 0), chrome,
               {'pos': [0, 0.6, 0]}))
    sw.add(tm(K.box(0.3, 0.06, 0.06, 0.025), lac, PAL.channelRed, {'pos': [0, 0.66, -0.02]}))
    sw.add(tm(K.cyl(0.03, 0.035, 0.18, {'seg': 10, 'bevel': 0.012}).clone().rotateX(-math.pi / 2), lac, PAL.channelRed,
              {'pos': [0, 0.66, -0.04]}))
    sw.add(tm(THREE.SphereGeometry(0.05, 12, 9), lac, PAL.channelRed, {'pos': [0, 0.66, -0.23]}))
    K.merge(sw)
    sw.userData.noMerge = True
    g.add(sw)

    # labels
    def draw_signs(ctx, w, h, rand):
        rrect(ctx, 4, 4, 248, 120, 14)
        ctx.fillStyle = '#F4C81E'
        ctx.fill()
        ctx.lineWidth = 6
        ctx.strokeStyle = '#1E1530'
        ctx.stroke()
        poly(ctx, [[46, 20], [20, 70], [40, 70], [28, 110], [66, 56], [46, 56]])
        ctx.fillStyle = '#1E1530'
        ctx.fill()
        text(ctx, 'DANGER', 160, 44, {'font': FONT['sign'], 'size': 38, 'fill': '#1E1530'})
        text(ctx, 'HIGH VOLTAGE', 160, 90, {'font': FONT['sign'], 'size': 20, 'fill': PAL.channelRed, 'maxW': 170})
        rrect(ctx, 4, 132, 248, 120, 12)
        ctx.fillStyle = '#EDE6D6'
        ctx.fill()
        ctx.lineWidth = 5
        ctx.strokeStyle = PAL.channelRed
        ctx.stroke()
        text(ctx, 'KILL SWITCH', 128, 172, {'font': FONT['sign'], 'size': 30, 'fill': PAL.channelRed, 'maxW': 230})
        text(ctx, 'TRANSMITTER · WZTV 13', 128, 214, {'font': FONT['round'], 'size': 17, 'fill': '#3A3A44', 'maxW': 230})
    signs = cv('killswitch_signs', 256, 256, draw_signs)
    signMat = K.mat(game, 'paint', '#ffffff', {'map': signs})
    g.add(K.m(decalGeo(0.46, 0.22, [0, 0, 1, 0.5]), signMat, {'pos': [0, Y0 + 1.72, PZ - 0.03]}))
    # door (front): frame + mesh + hasp + padlock; pivot at the viewer's left (+x) edge
    door = THREE.Group()
    door.position.set(W / 2 - 0.03, 0, -D / 2 + 0.03)
    dw = W - 0.08
    door.add(tm(K.box(0.05, H - 0.1, 0.05, 0.012), paint, RED, {'pos': [-0.02, Y0 + H / 2, 0]}),
             tm(K.box(0.05, H - 0.1, 0.05, 0.012), paint, RED, {'pos': [-dw + 0.03, Y0 + H / 2, 0]}))
    for y in (Y0 + 0.08, Y0 + H - 0.1, Y0 + H / 2):
        door.add(tm(K.box(dw, 0.05, 0.05, 0.012), paint, RED, {'pos': [-dw / 2, y, 0]}))
    p = THREE.PlaneGeometry(dw - 0.05, H - 0.2)
    K.uvScale(p, 8, 13)
    door.add(K.m(p, mesh, {'pos': [-dw / 2, Y0 + H / 2, 0]}))
    door.add(K.m(decalGeo(0.4, 0.2, [0, 0.5, 1, 1]), signMat, {'pos': [-dw / 2, Y0 + 1.25, -0.03]}))
    door.add(K.m(K.box(0.1, 0.05, 0.03, 0.008), chrome, {'pos': [-dw + 0.02, Y0 + 1.0, -0.03]}))
    door.add(tm(K.box(0.09, 0.1, 0.035, 0.015), lac, '#C8963C', {'pos': [-dw + 0.0, Y0 + 0.9, -0.05]}))
    door.add(K.m(THREE.TorusGeometry(0.03, 0.008, 5, 12, math.pi), chrome, {'pos': [-dw + 0.0, Y0 + 0.95, -0.05]}))
    K.merge(door)
    door.userData.noMerge = True
    g.add(door)
    for y in (Y0 + 0.4, Y0 + H - 0.4):
        g.add(K.m(K.cyl(0.018, 0.018, 0.12, {'seg': 8}), chrome, {'pos': [W / 2 - 0.02, y - 0.06, -D / 2 + 0.03]}))
    # conduits up the tower
    for x in (-0.35, 0.35):
        g.add(tm(K.tube([[x, Y0 + 1.6, PZ], [x, Y0 + H - 0.2, PZ], [x * 0.8, Y0 + H + 0.2, D / 2 - 0.05],
                         [x * 0.8, Y0 + H + 1.2, D / 2 - 0.05]], 0.03, {'seg': 12, 'radial': 6}), paint, '#8A9098'))
    u = g.userData
    u.parts = {'door': door, 'switch': sw}
    u.anchors = {'handle': [0, HY + 0.66, SZ - 0.23]}
    u.interact = {'point': [0, 1.2, -D / 2 - 0.4], 'radius': 1.3}
    u.colliders = [{'min': [-W / 2 - 0.02, 0, -D / 2 - 0.02], 'max': [W / 2 + 0.02, Y0 + H + 0.05, D / 2 + 0.02]}]
    return K.finish(game, g, {'ao': {'res': 60}})


registerProp('kill_switch_cage', _kill_switch_cage,
             {'category': CAT, 'tags': ['yard', 'ee', 'tower', 'switch'], 'size': [1.7, 3.4, 1.2],
              'desc': 'red mesh kill-switch cage with a giant knife switch', 'hero': True})


# ---------------------------------------------------------------------------------------- perpetua_crate
# The opened Perpetua-Tube shipping crate (MC floor [33.8,0,-4.0]): plank crate with stencils and a shipping
# label, lid leaning on its side with nails, golden excelsior straw spilling out (empty tube-shaped nest), crowbar.
def _perpetua_crate(game, opts=None):
    g = K.prop('perpetua_crate')
    wood = K.mat(game, 'teak', '#ffffff', {'map': K.tex.wood('#C89A62', {'dark': 0.28, 'wear': 0.4})})
    lac = K.mat(game, 'lacquer', '#ffffff')
    chrome = K.mat(game, 'chrome', '#A8B0BA')
    W, H, D = 1.0, 0.62, 0.7
    rnd = mulberry32(77)
    # planked walls
    plankH = H / 3
    for i in range(3):
        y = plankH * (i + 0.5)
        for s in (-1, 1):
            g.add(K.m(K.box(W, plankH - 0.012, 0.03, 0.008, {'uv': 1.3, 'swap': True}), wood,
                      {'pos': [0, y, s * (D / 2 - 0.015)], 'rot': [0, 0, (rnd() - 0.5) * 0.01]}))
            g.add(K.m(K.box(0.03, plankH - 0.012, D - 0.06, 0.008, {'uv': 1.3, 'swap': True}), wood,
                      {'pos': [s * (W / 2 - 0.015), y, 0]}))
    g.add(K.m(K.box(W - 0.06, 0.03, D - 0.06, 0.008, {'uv': 1.3}), wood, {'pos': [0, 0.04, 0]}))
    # corner battens (darker)
    for x, z in [[-1, -1], [1, -1], [-1, 1], [1, 1]]:
        g.add(tm(K.box(0.07, H + 0.02, 0.07, 0.012, {'uv': 1.3, 'swap': True}), wood, '#A87A4A',
                 {'pos': [x * (W / 2 - 0.02), H / 2, z * (D / 2 - 0.02)]}))
    for s in (-1, 1):
        g.add(tm(K.box(W + 0.02, 0.07, 0.04, 0.012, {'uv': 1.3}), wood, '#A87A4A', {'pos': [0, H - 0.03, s * (D / 2 + 0.005)]}))

    # stencils + shipping label
    def draw_sten(ctx, w, h, rand):
        ctx.clearRect(0, 0, w, h)
        ctx.globalAlpha = 0.85
        text(ctx, 'PERPETUA-TUBE', w / 2, 44, {'font': FONT['sign'], 'size': 50, 'fill': '#2A5A2A', 'maxW': w * 0.9,
                                               'track': 2})
        text(ctx, 'ETERNAL SIGNAL TUBE CO.', w / 2, 92, {'font': FONT['sign'], 'size': 22, 'fill': '#2A2A2A',
                                                         'maxW': w * 0.8})
        text(ctx, 'FRAGILE', 140, 160, {'font': FONT['sign'], 'size': 42, 'fill': '#B5282A', 'rot': -0.06})
        ctx.strokeStyle = '#2A2A2A'
        ctx.lineWidth = 8
        for x in (360, 420):
            ctx.beginPath()
            ctx.moveTo(x, 200)
            ctx.lineTo(x, 130)
            ctx.moveTo(x - 18, 150)
            ctx.lineTo(x, 128)
            ctx.lineTo(x + 18, 150)
            ctx.stroke()
        text(ctx, 'THIS SIDE UP', 390, 224, {'font': FONT['sign'], 'size': 18, 'fill': '#2A2A2A'})
        ctx.globalAlpha = 1
        # shipping label (bottom-left cell)
        ctx.save()
        ctx.translate(20, 190)
        ctx.rotate(0.03)
        ctx.fillStyle = '#F6EFD8'
        ctx.fillRect(0, 0, 150, 58)
        ctx.fillStyle = PAL.channelRed
        ctx.fillRect(0, 0, 150, 12)
        text(ctx, 'SHIP TO: WZTV CH.13', 75, 26, {'font': FONT['round'], 'size': 11, 'fill': '#2A2A2A'})
        text(ctx, 'TRANSMITTER DEPT.', 75, 42, {'font': FONT['round'], 'size': 11, 'fill': '#2A2A2A'})
        ctx.restore()
    sten = cv('crate_stencils', 512, 256, draw_sten)
    stMat = K.mat(game, 'paint', '#ffffff', {'map': sten, 'alphaTest': 0.3})
    g.add(K.m(decalGeo(0.92, 0.46), stMat, {'pos': [0, H / 2, -D / 2 - 0.032]}))
    g.add(K.m(decalGeo(0.66, 0.33, [0, 0.62, 1, 1]), stMat, {'pos': [W / 2 + 0.032, H / 2 + 0.05, 0], 'rot': [0, -math.pi / 2, 0]}))

    # straw: lumpy golden mound + loose strands spilling over the rim and on the floor
    def draw_straw(ctx, w, h, rand):
        ctx.fillStyle = '#A07A30'
        ctx.fillRect(0, 0, w, h)
        ctx.lineCap = 'round'
        for i in range(700):
            ctx.strokeStyle = ['#F2D07A', '#E0B458', '#C8963C', '#FFE6A0'][int(math.floor(rand() * 4))]
            ctx.globalAlpha = 0.5 + rand() * 0.4
            ctx.lineWidth = 2 + rand() * 2.5
            x, y, a, ln = rand() * w, rand() * h, rand() * TAU, 10 + rand() * 30
            ctx.beginPath()
            ctx.moveTo(x, y)
            ctx.quadraticCurveTo(x + math.cos(a + 1) * ln * 0.5, y + math.sin(a + 1) * ln * 0.5, x + math.cos(a) * ln,
                                 y + math.sin(a) * ln)
            ctx.stroke()
        ctx.globalAlpha = 1
    strawTex = cv('excelsior', 256, 256, draw_straw, True)
    straw = K.mat(game, 'paint', '#ffffff', {'map': strawTex})

    def mound(x, y, z, rx, ry, rz, ph):
        sg2 = THREE.SphereGeometry(1, 14, 8)
        p = sg2.attributes.position
        for i in range(p.count):
            X, Y, Z = p.getX(i), p.getY(i), p.getZ(i)
            k = 1 + 0.16 * math.sin(X * 7 + Z * 5 + ph) * math.cos(Y * 6 - X * 4) + \
                0.12 * math.sin(X * 23 + Y * 17 + ph) * math.sin(Z * 29 - Y * 13)
            p.setXYZ(i, X * k * rx, max(Y, -0.2) * k * ry, Z * k * rz)
        sg2.computeVertexNormals()
        g.add(K.m(K.uvScale(sg2, 3, 1.5), straw, {'pos': [x, y, z]}))
    mound(0, H - 0.04, 0, 0.5, 0.2, 0.33, 0)
    mound(0.36, H - 0.02, -0.22, 0.2, 0.1, 0.16, 2)
    mound(-0.34, H - 0.03, 0.2, 0.2, 0.1, 0.17, 4)
    mound(0.62, 0.04, -0.46, 0.18, 0.09, 0.15, 5)
    mound(-0.2, 0.03, -0.6, 0.14, 0.06, 0.12, 7)
    # empty nest (dark hollow where the tube lay)
    nest = THREE.CircleGeometry(0.2, 18)
    nest.scale(1.8, 1, 1)
    nest.rotateX(-math.pi / 2)
    g.add(K.m(nest, K.mat(game, 'fabric', '#5A3A14'), {'pos': [0, H + 0.13, 0.0]}))
    strawStrand = K.mat(game, 'plastic', '#E8C068', {'rough': 0.7})
    for i in range(22):
        onFloor = i > 13
        a = rnd() * TAU
        x0 = math.cos(a) * (0.6 + rnd() * 0.3) if onFloor else (rnd() - 0.5) * W
        z0 = math.sin(a) * (0.5 + rnd() * 0.25) if onFloor else (-1 if rnd() < 0.5 else 1) * (D / 2)
        y0 = 0.01 if onFloor else H + 0.02
        pts = []
        for k in range(5):
            pts.append([x0 + math.cos(a + k) * 0.03 * k,
                        (0.008 + (k % 2) * 0.004) if onFloor else y0 - k * 0.04 + math.sin(k) * 0.02,
                        z0 + math.sin(a + k * 1.3) * 0.03 * k + (0 if onFloor else js_sign(z0) * k * 0.025)])
        g.add(tm(K.tube(pts, 0.004, {'seg': 8, 'radial': 3}), strawStrand, ['#F2D07A', '#E0B458', '#FFE6A0'][i % 3]))
    # leaning lid with nails
    lid = THREE.Group()
    for i in range(4):
        lid.add(K.m(K.box(0.24, 0.025, D, 0.008, {'uv': 1.3}), wood, {'pos': [-0.36 + i * 0.245, 0, 0]}))
    for s in (-1, 1):
        lid.add(tm(K.box(W, 0.03, 0.08, 0.01, {'uv': 1.3}), wood, '#A87A4A', {'pos': [0, -0.02, s * (D / 2 - 0.08)]}))
    for i in range(6):
        lid.add(K.m(K.cyl(0.004, 0.004, 0.05, {'seg': 4}), chrome,
                    {'pos': [-0.4 + i * 0.16, 0.01, (1 if i % 2 else -1) * (D / 2 - 0.08)]}))
    lid.position.set(-0.93, 0.35, 0.05)
    lid.rotation.set(0, 0, 0.64)
    g.add(lid)
    # crowbar
    g.add(tm(K.tube([[0.35, 0.02, -0.62], [0.9, 0.02, -0.5], [0.97, 0.03, -0.46], [0.99, 0.06, -0.42]], 0.014,
                    {'seg': 12, 'radial': 6}), lac, PAL.channelRed))
    u = g.userData
    u.colliders = [{'min': [-W / 2, 0, -D / 2], 'max': [W / 2, H + 0.1, D / 2]}, {'min': [-1.35, 0, -D / 2], 'max': [-W / 2, 0.6, D / 2]}]
    return K.finish(game, g, {'ao': {'res': 56}})


registerProp('perpetua_crate', _perpetua_crate,
             {'category': CAT, 'tags': ['master_control', 'crate', 'ee'], 'size': [1.5, 0.75, 1.4],
              'desc': 'opened Perpetua-Tube crate with excelsior straw', 'hero': True})


# ---------------------------------------------------------------------------------------- dressing_room_door
# Green-room dressing-room door (fake, in the wall): casing trim, painted slab from cards.js
# 'dressing_room_doors' (star decal + name), brass knob, hinges, sconce bulb above. opts.who: skip | roxy | penny
# | duke | baron (porthole with a brass ring). Back of the casing at local z = 0 (wall plane), front -Z.
def _dressing_room_door(game, opts=None):
    opts = opts or {}
    who = _nn(opts.get('who'), 'skip')
    g = K.prop('dressing_room_door')
    lac = K.mat(game, 'lacquer', '#ffffff')
    brass = K.mat(game, 'brass', '#C8963C')
    SW, SH = 0.9, 2.02
    cas = [[-SW / 2 - 0.12, 0], [-SW / 2, 0], [-SW / 2, SH], [SW / 2, SH], [SW / 2, 0], [SW / 2 + 0.12, 0],
           [SW / 2 + 0.12, SH + 0.12], [-SW / 2 - 0.12, SH + 0.12]]
    g.add(tm(K.extrude(cas, 0.06, {'bevel': 0.018}), lac, '#F6E7C8', {'pos': [0, 0, -0.03]}))
    g.add(tm(K.box(SW + 0.3, 0.06, 0.09, 0.02), lac, '#F6E7C8', {'pos': [0, SH + 0.15, -0.035]}))
    slab = K.m(decalGeo(SW - 0.02, SH - 0.02), K.mat(game, 'lacquer', '#ffffff',
                                                     {'map': getCard('dressing_room_doors', {'who': who})}),
               {'pos': [0, SH / 2 + 0.01, -0.035]})
    g.add(slab)
    g.add(tm(K.box(SW - 0.01, SH - 0.01, 0.04, 0.012), lac, '#3A2A2A', {'pos': [0, SH / 2 + 0.01, -0.012]}))
    # knob + escutcheon (viewer's right = -x), hinges on the left
    g.add(K.m(K.box(0.06, 0.16, 0.012, 0.005), brass, {'pos': [-SW / 2 + 0.1, 1.0, -0.042]}))
    knob = K.lathe([[0, 0], [0.018, 0], [0.018, 0.03], [0.034, 0.05], [0.036, 0.07], [0.02, 0.085], [0, 0.086]],
                   {'round': 0.006, 'seg': 14}).clone()
    knob.rotateX(-math.pi / 2)
    g.add(K.m(knob, brass, {'pos': [-SW / 2 + 0.1, 1.0, -0.046]}))
    for y in (0.3, 1.0, 1.72):
        g.add(K.m(K.cyl(0.012, 0.012, 0.12, {'seg': 8}), brass, {'pos': [SW / 2 - 0.005, y, -0.045]}))
    if who == 'baron':
        py, pr = SH + 0.01 - (110 / 512) * (SH - 0.02), (62 / 256) * (SW - 0.02)
        g.add(K.m(THREE.TorusGeometry(pr + 0.02, 0.028, 8, 28), brass, {'pos': [0, py, -0.05]}))
        gl = THREE.CircleGeometry(pr, 24)
        gl.rotateY(math.pi)
        g.add(K.m(gl, game.mats.glass('#CFE0FF', {'opacity': 0.25}), {'pos': [0, py, -0.056]}))
    # sconce with a bulb above the door
    g.add(K.m(K.lathe([[0, 0], [0.06, 0], [0.065, 0.02], [0.03, 0.05], [0, 0.05]], {'seg': 12}).clone().rotateX(-math.pi / 2),
              brass, {'pos': [0, SH + 0.32, -0.04]}))
    bulb = K.m(THREE.SphereGeometry(0.055, 12, 9), K.glow(game, '#FFD08A', 2.4), {'pos': [0, SH + 0.32, -0.13], 'cast': False})
    bulb.userData.noOcclude = True
    g.add(bulb)
    g.add(K.m(K.cyl(0.012, 0.012, 0.06, {'seg': 8}).clone().rotateX(-math.pi / 2), brass, {'pos': [0, SH + 0.32, -0.07]}))
    u = g.userData
    u.colliders = [{'min': [-SW / 2 - 0.12, 0, -0.08], 'max': [SW / 2 + 0.12, SH + 0.4, 0.0]}]
    u.lightAnchors = [{'pos': [0, SH + 0.3, -0.35], 'color': '#FFD08A', 'intensity': 1.0, 'distance': 3}]
    return K.finish(game, g, {'ao': {'res': 44}})


registerProp('dressing_room_door', _dressing_room_door,
             {'category': CAT, 'tags': ['green_room', 'door', 'wall', 'fake'], 'size': [1.14, 2.45, 0.14],
              'desc': 'dressing-room door with star decal (opts.who)'})


# =========================================================================================================
# PROPVIEW SCENES (set-dressing previews; camera looks toward +z, props face -z)
# =========================================================================================================
registerScene('sets_studio_a', {
    'floor': 'wood', 'floorColor': '#6A4A3A', 'wall': '#2A1C3A', 'room': [17, 15], 'wallH': 7,
    'items': [
        {'id': 'marquee_arch', 'pos': [0, 5.0]},
        {'id': 'pledge_wheel', 'pos': [3.3, 6.3]},
        {'id': 'baron_throne', 'pos': [-1.2, 6.2], 'rotY': 0.15},
        {'id': 'contestant_podium', 'pos': [-4.8, 5.4], 'rotY': 0.2, 'opts': {'num': 1, 'score': '$130'}},
        {'id': 'contestant_podium', 'pos': [-3.7, 5.6], 'rotY': 0.1, 'opts': {'num': 2, 'score': '$ 75'}},
        {'id': 'ghost_light', 'pos': [5.6, 5.2]},
        {'id': 'pledge_carousel', 'pos': [0, 0.4]},
        {'id': 'tote_board_tower', 'pos': [0, 0.4], 'rotY': 0.35},
        {'id': 'bleacher_block', 'pos': [-6.2, -2.8], 'rotY': math.pi / 2},
        {'id': 'disco_ball', 'pos': [2.4, 4.6, 2.0]},
        {'id': 'applause_sign', 'pos': [-7.8, 3.2, -2.8], 'rotY': math.pi / 2},
    ],
    'cam': {'pos': [4.2, 3.6, -8.6], 'target': [-0.2, 1.7, 2.2], 'fov': 56}, 'hemi': 0.7, 'key': 1.1,
})
registerScene('sets_studio_b', {
    'floor': '#E8D8B8', 'wall': '#C9A7FF', 'room': [14, 12], 'wallH': 6,
    'items': [
        {'id': 'treehouse_facade', 'pos': [1.2, 5.3]},
        {'id': 'chroma_cyc', 'pos': [-4.6, 5.0]},
        {'id': 'cardboard_rocket', 'pos': [4.6, 1.8]},
        {'id': 'puppet_theater', 'pos': [-3.6, 1.6], 'rotY': 0.35},
        {'id': 'alphabet_block', 'pos': [-1.2, 3.1], 'rotY': 0.3},
        {'id': 'alphabet_block', 'pos': [-0.3, 3.6], 'rotY': -0.2, 'opts': {'variant': 1}},
        {'id': 'alphabet_block', 'pos': [-0.75, 1.0, 3.35], 'rotY': 0.6, 'opts': {'variant': 2}},
        {'id': 'rainbow_arch', 'pos': [0.8, -1.2]},
        {'id': 'giant_crayons', 'pos': [2.9, 3.6], 'rotY': -0.3},
        {'id': 'toy_train_loop', 'pos': [-1.2, -0.6]},
        {'id': 'xylophone', 'pos': [2.6, 0.2], 'rotY': -0.5},
        {'id': 'giant_crayon', 'pos': [-5.2, -1.2], 'rotY': 0.8, 'opts': {'color': 1}},
    ],
    'cam': {'pos': [1.0, 3.2, -8.8], 'target': [0.2, 1.6, 2.2], 'fov': 56}, 'hemi': 0.95, 'key': 1.2,
})
registerScene('sets_ee', {
    'floor': 'shag', 'floorColor': '#C8562A', 'wall': 'panel', 'room': [14, 10], 'wallH': 3.8,
    'items': [
        {'id': 'neon_logo_partition', 'pos': [-0.8, 1.8], 'opts': {'state': 'broken'}},
        {'id': 'trophy_case', 'pos': [-6.62, -0.6], 'rotY': -math.pi / 2},
        {'id': 'chime_rack', 'pos': [-5.6, 2.2], 'rotY': -math.pi / 3},
        {'id': 'letter_board', 'pos': [2.6, 1.2], 'rotY': -0.3},
        {'id': 'weather_map', 'pos': [4.2, 4.95]},
        {'id': 'rundown_board', 'pos': [1.4, 4.95], 'opts': {'filled': 2}},
        {'id': 'dressing_room_door', 'pos': [-3.6, 5.0], 'opts': {'who': 'roxy'}},
        {'id': 'dressing_room_door', 'pos': [-4.9, 5.0], 'opts': {'who': 'baron'}},
        {'id': 'perpetua_crate', 'pos': [5.2, -0.6], 'rotY': -0.6},
        {'id': 'kill_switch_cage', 'pos': [5.9, 2.6], 'rotY': -0.5},
    ],
    'cam': {'pos': [0.2, 2.6, -7.6], 'target': [-0.2, 1.3, 2.4], 'fov': 60}, 'hemi': 0.9, 'key': 1.1,
})
