"""DEAD AIR — props: sponsors, costumes & drops (docs/PROPKIT.md; GDD §10.3, §11, §12, §18.9, §18.11).
Port of src/props/sponsors.js (line by line: same names, same numbers, same canvas drawing, same seeds).
Owner: the sponsors prop artist. Everything is full color (keepColor) except the set structure.

category 'sponsors'
  product_<perkId>        the 5 GIANT PRODUCTS (1.2-1.5 m, glossy): replay_ade bottle, wobble_up gelatin mold on a
                          cake stand (parts.jelly wobbles), jump_cut coffee drum + steam bolt, roller_boogie wax tin +
                          rainbow skate, double_vision striped toothpaste tube (parts.cap spins)
  sponsor_set_<perkId>    the set prefab, 5 skins: 3x3 m riser (0.2 m), painted 3x2.6 m backdrop flat, neon sign,
                          rotating pedestal (parts.turntable) with the product, two softboxes, gaffer-tape X, speaker,
                          pedestal camera with tally (Replay-Ade: ENG camera on a tripod) + per-brand dressing.
                          opts { lit=true (powered look), camera=true, product=true }
  sponsor_camera_pedestal · sponsor_camera_eng · sponsor_softbox · sponsor_speaker   (set pieces, placeable alone)
category 'sponsors_costume'  (hero slot pieces, ARCHITECTURE §12 slots; see COSTUME FIT below)
  costume_jelly_helmet · costume_oven_mitt · costume_skates · costume_toothbrush · costume_wristbands (+ '_gold')
category 'sponsors_drop'
  drop_<type>             the 6 power-ups in a 0.6 m glass "screen bubble" over a glowing gold floor ring

Runtime helpers exported by the JS for the game systems (src/game/sponsors.js, powerups.js) are NOT here: they
animate placed props and live in the Godot port (scripts/game/sponsors.gd / powerups.gd):
  setSponsorSetPower(set, on)   swaps sign / tally / softbox materials (dark set before Sign-On)
  setTally(obj, on)             tally light of a set or a camera prop
  setSoldOut(set, on)           Replay-Ade sold out: tape X over the product, camera tipped over, tally off
  animateDrop(drop, t)          bob/spin + the model's own loop (stamp, reel, clapper, needle...)
  animateProduct(prop, t)       product idle (jelly wobble, cap spin) — the set's turntable spins separately
Every part / name / userData key they use is kept (parts.float/model/stamp/reel/clapper/needle/roll, parts.jelly/cap,
parts.turntable/productParts/mirrorball/soldOut/camera/sign/tally/diffuser/bulbs, userData.power/powered/dropType).

COSTUME FIT: each costume group holds userData.parts.<slot> sub-groups, each built around its slot origin
(reparent to hero.slots.<slot>, then reset position/rotation to 0). userData.fit documents the reference size.

Port notes (JS -> Python):
  * `float` (a JS local of the drop shell) is `float_` here; the userData.parts key stays "float".
  * `text()` keeps the JS name (2D text helper); `lambda` builders of registerProp -> nested defs.
  * the `?spprofile=1` console profiling block of buildSponsorSet is browser tooling (SPEC §0.2): not ported.
  * bubbleMat (custom THREE.ShaderMaterial) -> K.material('bubble', …) spec (materials.gd bubble()), cached per game.
"""
import math

from dalib import kit as K
from dalib.kit import registerProp, registerScene, PAL, THREE, getCard
from dalib.mathutils3 import clamp, lerp, smoothstep, js_str, js_round

TAU = math.pi * 2
UP = THREE.Vector3(0, 1, 0)


def V3(a):
    return THREE.Vector3(a[0], a[1], a[2])


# Sponsor colors (kept identical to gfx/cards.js SPONSORS so the 3D matches the posters and logo cards).
SPONSOR_IDS = ['replay_ade', 'wobble_up', 'jump_cut', 'roller_boogie', 'double_vision']
SP = {
    'replay_ade': {'name': 'Replay-Ade', 'sub': 'SPORTS DRINK', 'main': '#F4C81E', 'second': '#2F5BD3', 'deep': '#1B2F7A', 'neon': '#FFD23A', 'neon2': '#3A7BFF'},
    'wobble_up': {'name': 'Wobble-Up', 'sub': 'GELATIN', 'main': '#1FB45A', 'second': '#E23B3B', 'deep': '#0E4A26', 'neon': '#52E04A', 'neon2': '#FF5FA2'},
    'jump_cut': {'name': 'Jump Cut', 'sub': 'COFFEE', 'main': '#E3662B', 'second': '#5A3A22', 'deep': '#4A1E0E', 'neon': '#FF8A2A', 'neon2': '#FFD23A'},
    'roller_boogie': {'name': 'Roller Boogie', 'sub': 'SKATE WAX', 'main': '#FF5FA2', 'second': '#6B3A6E', 'deep': '#3A1440', 'neon': '#FF5FA2', 'neon2': '#5FE3FF'},
    'double_vision': {'name': 'Double Vision', 'sub': 'TOOTHPASTE', 'main': '#3FB8E8', 'second': '#E23B3B', 'deep': '#123A7A', 'neon': '#5FE3FF', 'neon2': '#FF4FA0'},
}
BAR = {'red': '#E4473A', 'yellow': '#F4E03A', 'green': '#52D24A', 'blue': '#3A58E4', 'cyan': '#3FD6E0', 'magenta': '#D64FD6'}
INK = '#2A1D3A'


# =============================================================================================== helpers
# Full-color material (products, costumes, drops skip the pre-power desaturation).
def pm(game, preset, color, extra=None):
    extra = extra if extra is not None else {}
    c = THREE.Color(color)
    pale = False if extra.get('map') else c.r * 0.3 + c.g * 0.55 + c.b * 0.15 > 0.72
    o = {'keepColor': True}
    if pale and 'rim' not in extra:
        o['rim'] = 0.1
    o.update(extra)
    return K.mat(game, preset, color, o)


# Fresh (mutable) lathe around Y with V mapped by HEIGHT (so wrap-around labels are not stretched per point).
def lathe2(profile, opts=None):
    o = opts or {}
    seg = o['seg'] if o.get('seg') is not None else 32
    round_ = o['round'] if o.get('round') is not None else 0
    steps = o['steps'] if o.get('steps') is not None else 2
    v = o['v'] if o.get('v') is not None else True
    pts = K.roundProfile(profile, round_, steps) if round_ else profile
    g = THREE.LatheGeometry([THREE.Vector2(max(0, x), y) for x, y in pts], seg)
    if v:
        vByHeight(g)
    return g


def vByHeight(g, y0=None, y1=None):
    g.computeBoundingBox()
    lo = y0 if y0 is not None else g.boundingBox.min.y
    hi = y1 if y1 is not None else g.boundingBox.max.y
    p, uv = g.attributes.position, g.attributes.uv
    d = (hi - lo) or 1
    for i in range(p.count):
        uv.setY(i, (p.getY(i) - lo) / d)
    uv.needsUpdate = True
    return g


# Radial displacement around Y: fn(theta (0 at +z, toward +x), y, r) -> radius multiplier. In place.
def radial(g, fn):
    p = g.attributes.position
    for i in range(p.count):
        x, y, z = p.getX(i), p.getY(i), p.getZ(i)
        r = math.hypot(x, z)
        if r < 1e-6:
            continue
        k = fn(math.atan2(x, z), y, r)
        p.setX(i, x * k)
        p.setZ(i, z * k)
    g.computeVertexNormals()
    K.weldNormals(g)
    return g


# Generic vertex deform in place: fn(v:Vector3) mutates v.
def deform(g, fn):
    p, v = g.attributes.position, THREE.Vector3()
    for i in range(p.count):
        v.set(p.getX(i), p.getY(i), p.getZ(i))
        fn(v)
        p.setXYZ(i, v.x, v.y, v.z)
    g.computeVertexNormals()
    return g


# Planar UV projection: u from axis a over [a0,a1], v from axis b over [b0,b1] (on your own copy).
def uvPlanar(g, a, a0, a1, b, b0, b1):
    p, uv = g.attributes.position, g.attributes.uv
    ai, bi = 'xyz'.index(a), 'xyz'.index(b)
    c = [0, 0, 0]
    for i in range(p.count):
        c[0] = p.getX(i)
        c[1] = p.getY(i)
        c[2] = p.getZ(i)
        uv.setXY(i, (c[ai] - a0) / (a1 - a0), (c[bi] - b0) / (b1 - b0))
    uv.needsUpdate = True
    return g


# Painted copy of a (possibly cached) geometry: per-vertex color, lets one white material serve many colors.
def paint(geo, color):
    return K.tint(geo.clone(), color)


# Orients a mesh built along +y (base at 0) from a to b.
def span(mesh, a, b):
    A, B = V3(a), V3(b)
    mesh.position.copy(A)
    mesh.quaternion.setFromUnitVectors(UP, B.sub(A).normalize())
    return mesh


def rod(r, a, b, mat, seg=10, bevel=None):
    ln = V3(a).distanceTo(V3(b))
    return span(K.m(K.cyl(r, r, ln, {'bevel': bevel if bevel is not None else r * 0.45, 'seg': seg}), mat), a, b)


def ring(r, n, y=0):
    pts = []
    for i in range(n):
        a = (i / n) * TAU
        pts.append([math.cos(a) * r, y, math.sin(a) * r])
    return pts


# Torus lying flat (ring around Y) at height y.
def flatTorus(r, tube, rs=8, ts=32):
    return THREE.TorusGeometry(r, tube, rs, ts).rotateX(math.pi / 2)


# Superellipse loft: rings of [ax, az, y, n] -> closed-around surface (u = angle, v = ring index / (count-1)).
def loft(rings, seg=48):
    pos, uv, idx = [], [], []
    cols = seg + 1
    for i, rg in enumerate(rings):
        ax, az, y = rg[0], rg[1], rg[2]
        n = rg[3] if len(rg) > 3 and rg[3] is not None else 2
        for j in range(seg + 1):
            th = (j / seg) * TAU
            s, c, e = math.sin(th), math.cos(th), 2 / n
            pos += [ax * _sign(s) * abs(s) ** e, y, az * _sign(c) * abs(c) ** e]
            uv += [j / seg, i / (len(rings) - 1)]
    for i in range(len(rings) - 1):
        for j in range(seg):
            a = i * cols + j
            b = a + 1
            c = a + cols
            d = c + 1
            idx += [a, b, c, b, d, c]
    g = THREE.BufferGeometry()
    g.setAttribute('position', THREE.Float32BufferAttribute(pos, 3))
    g.setAttribute('uv', THREE.Float32BufferAttribute(uv, 2))
    g.setIndex(idx)
    g.computeVertexNormals()
    # make sure normals point outward (mid-ring vertex vs its radial direction); flip winding otherwise
    mid = (len(rings) // 2) * cols + seg // 4
    p, nn = g.attributes.position, g.attributes.normal
    if p.getX(mid) * nn.getX(mid) + p.getZ(mid) * nn.getZ(mid) < 0:
        ia = g.index.array
        for k in range(0, len(ia), 3):
            t = ia[k + 1]
            ia[k + 1] = ia[k + 2]
            ia[k + 2] = t
        g.computeVertexNormals()
    K.weldNormals(g)
    return g


def _sign(x):
    """Math.sign"""
    return 1.0 if x > 0 else -1.0 if x < 0 else x


# Marks every mesh of a nested (already finished) prop so the parent's finish() leaves its bake alone.
def nested(obj):
    obj.userData.noMerge = True

    def f(o):
        if getattr(o, 'isMesh', False):
            o.userData.noAO = True
    obj.traverse(f)
    return obj


# ------------------------------------------------------------------------------------------ 2D drawing
FONT = {'groovy': 'Shrikhand', 'sign': 'Bungee', 'round': 'Titan One', 'mono': 'VT323'}


def font(ctx, px, fam):
    ctx.font = '%spx "%s", "Arial Black", sans-serif' % (js_str(px), fam)


def rrp(ctx, x, y, w, h, r):
    ctx.beginPath()
    ctx.roundRect(x, y, w, h, r)


def starP(ctx, cx, cy, ro, ri, n=5, rot=-math.pi / 2):
    ctx.beginPath()
    for i in range(n * 2):
        a, r = rot + (i / (n * 2)) * TAU, ri if i % 2 else ro
        ctx.lineTo(cx + math.cos(a) * r, cy + math.sin(a) * r)
    ctx.closePath()


# Lightning bolt (pointing down), centered, s = height.
def boltP(ctx, cx, cy, s):
    p = [[0.12, -0.5], [-0.3, 0.06], [-0.04, 0.06], [-0.16, 0.5], [0.3, -0.08], [0.04, -0.08], [0.2, -0.5]]
    ctx.beginPath()
    for i, (x, y) in enumerate(p):
        if i:
            ctx.lineTo(cx + x * s, cy + y * s)
        else:
            ctx.moveTo(cx + x * s, cy + y * s)
    ctx.closePath()


BOLT_PTS = [[0.12, -0.5], [-0.3, 0.06], [-0.04, 0.06], [-0.16, 0.5], [0.3, -0.08], [0.04, -0.08], [0.2, -0.5]]


def rewindP(ctx, cx, cy, s):  # ◀◀ centered, s = height
    ctx.beginPath()
    for k in (0, 1):
        ox = cx + s * (0.5 - k * 0.62)
        ctx.moveTo(ox, cy - s * 0.5)
        ctx.lineTo(ox - s * 0.62, cy)
        ctx.lineTo(ox, cy + s * 0.5)
        ctx.closePath()


# Text with optional outline, 3D depth and drop shadow. Returns the fitted size.
def text(ctx, s, x, y, o=None):
    o = o or {}
    fam = o.get('fam', FONT['sign'])
    px = o.get('px', 40)
    fill = o.get('fill', '#fff')
    stroke = o.get('stroke')
    lw = o.get('lw', 0)
    maxW = o.get('maxW', 0)
    depth = o.get('depth', 0)
    depthFill = o.get('depthFill', INK)
    align = o.get('align', 'center')
    rot = o.get('rot', 0)
    track = o.get('track', 0)
    alpha = o.get('alpha', 1)
    size = px
    font(ctx, size, fam)
    if track:
        ctx.letterSpacing = '%spx' % js_str(track)
    while maxW and ctx.measureText(s).width > maxW and size > 6:
        size *= 0.94
        font(ctx, size, fam)
    ctx.save()
    ctx.globalAlpha = alpha
    ctx.translate(x, y)
    ctx.rotate(rot)
    ctx.textAlign = align
    ctx.textBaseline = 'middle'
    ctx.lineJoin = 'round'
    d = depth
    while d > 0:
        if stroke:
            ctx.lineWidth = lw
            ctx.strokeStyle = depthFill
            ctx.strokeText(s, d * 0.5, d)
        ctx.fillStyle = depthFill
        ctx.fillText(s, d * 0.5, d)
        d -= 1
    if stroke:
        ctx.lineWidth = lw
        ctx.strokeStyle = stroke
        ctx.strokeText(s, 0, 0)
    ctx.fillStyle = fill
    ctx.fillText(s, 0, 0)
    ctx.restore()
    ctx.letterSpacing = '0px'
    return size


def lin(ctx, x0, y0, x1, y1, stops):
    g = ctx.createLinearGradient(x0, y0, x1, y1)
    for i, c in enumerate(stops):
        g.addColorStop(i / (len(stops) - 1), c)
    return g


def rays(ctx, cx, cy, r, n, col, a0=0):
    ctx.fillStyle = col
    for i in range(n):
        a = a0 + (i / n) * TAU
        b = a + TAU / n / 2
        ctx.beginPath()
        ctx.moveTo(cx, cy)
        ctx.lineTo(cx + math.cos(a) * r, cy + math.sin(a) * r)
        ctx.lineTo(cx + math.cos(b) * r, cy + math.sin(b) * r)
        ctx.closePath()
        ctx.fill()


def sparkle(ctx, x, y, r, col='#FFFFFF'):
    ctx.fillStyle = col
    ctx.beginPath()
    for i in range(8):
        a, rr = (i / 8) * TAU - math.pi / 2, r * 0.22 if i % 2 else r
        ctx.lineTo(x + math.cos(a) * rr, y + math.sin(a) * rr)
    ctx.closePath()
    ctx.fill()


def texC(key, w, h, draw, o=None):
    opts = {'repeat': False, 'fonts': True}
    opts.update(o or {})
    return K.tex.canvas('sp.%s' % key, w, h, draw, opts)


def _hsl(h, s, l):
    """`hsl(${h}, ${s}%, ${l}%)` with JS number formatting."""
    return 'hsl(%s, %s%%, %s%%)' % (js_str(h), js_str(s), js_str(l))


# =============================================================================================== PRODUCTS
# All products: floor at y=0, centered, front (logo) toward -z. Glossy full-color toy plastics.

# ------------------------------------------------------------------ Replay-Ade: giant sports-drink bottle
def replayBodyTex():
    def draw(ctx, w, h, rand):
        ctx.fillStyle = lin(ctx, 0, 0, 0, h, ['#FFE55A', '#FFD52E', '#F4B818'])
        ctx.fillRect(0, 0, w, h)

        def Y(v):
            return (1 - v) * h
        # pinstripe bands framing the waist grip
        for v in (0.285, 0.52):
            ctx.fillStyle = SP['replay_ade']['second']
            ctx.fillRect(0, Y(v) - 7, w, 14)
            ctx.fillStyle = '#FFFFFF'
            ctx.fillRect(0, Y(v) - 2, w, 4)
        # bottom stripe + small rewind chevrons around the lower body
        ctx.fillStyle = SP['replay_ade']['second']
        ctx.fillRect(0, Y(0.07), w, 10)
        for i in range(16):
            rewindP(ctx, 32 + i * 64, Y(0.17), 22)
            ctx.fillStyle = 'rgba(27,47,122,0.55)'
            ctx.fill()
        # the label band
        y0, y1 = Y(0.845), Y(0.555)
        ctx.fillStyle = lin(ctx, 0, y0, 0, y1, ['#3F70EA', '#2F5BD3', '#1E3A9A'])
        ctx.fillRect(0, y0, w, y1 - y0)
        ctx.fillStyle = '#FFFFFF'
        ctx.fillRect(0, y0 + 5, w, 5)
        ctx.fillRect(0, y1 - 10, w, 5)
        ctx.fillStyle = '#E3662B'
        ctx.fillRect(0, y0 + 13, w, 5)
        ctx.fillRect(0, y1 - 18, w, 5)
        cy = (y0 + y1) / 2
        # soft starburst behind the wordmark
        ctx.save()
        ctx.beginPath()
        ctx.rect(0, y0 + 20, w, y1 - y0 - 40)
        ctx.clip()
        rays(ctx, 512, cy, 330, 28, 'rgba(255,255,255,0.08)')
        ctx.restore()
        text(ctx, 'Replay-Ade', 512, cy - 12, {'fam': FONT['groovy'], 'px': 84, 'fill': lin(ctx, 0, cy - 50, 0, cy + 30, ['#FFF6B0', '#FFD23A', '#F4B818']), 'stroke': '#10205A', 'lw': 12, 'depth': 6, 'depthFill': '#10205A', 'maxW': 330})
        text(ctx, 'SPORTS DRINK', 512, cy + 42, {'fam': FONT['sign'], 'px': 22, 'fill': '#FFFFFF', 'stroke': '#10205A', 'lw': 5, 'track': 3})
        for s in (-1, 1):
            rewindP(ctx, 512 + s * 232, cy + 4, 44)
            ctx.fillStyle = '#FFD23A'
            ctx.fill()
            ctx.lineWidth = 5
            ctx.strokeStyle = '#10205A'
            ctx.stroke()
            sparkle(ctx, 512 + s * 196, cy - 44, 11)
        # back of the label
        text(ctx, 'GET BACK IN THE GAME!', 0, cy - 12, {'fam': FONT['sign'], 'px': 26, 'fill': '#FFD23A', 'stroke': '#10205A', 'lw': 5})
        text(ctx, 'GET BACK IN THE GAME!', w, cy - 12, {'fam': FONT['sign'], 'px': 26, 'fill': '#FFD23A', 'stroke': '#10205A', 'lw': 5})
        text(ctx, 'INSTANT REPLAY FORMULA', 0, cy + 24, {'fam': FONT['round'], 'px': 18, 'fill': '#FFFFFF'})
        text(ctx, 'INSTANT REPLAY FORMULA', w, cy + 24, {'fam': FONT['round'], 'px': 18, 'fill': '#FFFFFF'})
    return texC('replay.body', 1024, 512, draw)


def _product_replay_ade(game, opts=None):
    g = K.prop('product_replay_ade')
    body = pm(game, 'plastic', '#ffffff', {'map': replayBodyTex(), 'rough': 0.26})
    blue = pm(game, 'plastic', '#2F5BD3', {'rough': 0.3})
    yellow = pm(game, 'plastic', '#FFD23A', {'rough': 0.28})
    H = 1.2
    bg = lathe2([[0, 0], [0.26, 0], [0.305, 0.03], [0.312, 0.09], [0.312, 0.33], [0.29, 0.39], [0.262, 0.47], [0.29, 0.56],
                 [0.312, 0.62], [0.312, 1.0], [0.296, 1.06], [0.235, 1.12], [0.15, 1.162], [0.13, 1.18], [0.13, H], [0, H]],
                {'seg': 36, 'round': 0.03, 'steps': 1})

    def waist(th, y, r):
        w = smoothstep(y, 0.35, 0.41) * (1 - smoothstep(y, 0.53, 0.6))
        return 1 - w * 0.04 * (0.5 + 0.5 * math.cos(th * 10))
    radial(bg, waist)
    g.add(K.m(bg, body))
    # neck ring + ribbed cap
    g.add(K.m(flatTorus(0.137, 0.014, 8, 32), blue, {'pos': [0, 1.185, 0]}))
    cap = lathe2([[0, 0], [0.158, 0], [0.166, 0.02], [0.166, 0.11], [0.15, 0.13], [0.1, 0.136], [0, 0.136]],
                 {'seg': 40, 'round': 0.012, 'steps': 1})
    radial(cap, lambda th, y, r: 1 + 0.035 * max(0, math.cos(th * 20)) * smoothstep(y, 0.02, 0.04) * (1 - smoothstep(y, 0.1, 0.12)))
    g.add(K.m(cap, blue, {'pos': [0, H - 0.005, 0]}))
    g.add(K.m(flatTorus(0.15, 0.012, 6, 32), yellow, {'pos': [0, H + 0.128, 0]}))

    # the rewind-arrow fin on the cap: chunky yellow ◀◀ on a blue plinth (points to the viewer's left = shape +x)
    def tri(ox):
        return [[ox, 0.085], [ox + 0.13, 0], [ox, -0.085]]
    for ox in (-0.125, 0.0):
        g.add(K.m(K.extrude(tri(ox), 0.1, {'bevel': 0.028, 'round': 0.03, 'curveSeg': 4, 'bevelSeg': 2}), yellow, {'pos': [0, H + 0.235, 0]}))
    g.add(K.m(K.cyl(0.075, 0.1, 0.07, {'bevel': 0.018, 'seg': 20}), blue, {'pos': [0, H + 0.125, 0]}))
    # cold condensation droplets on the upper body
    drop = pm(game, 'plastic', '#FFF6C8', {'transparent': True, 'opacity': 0.55, 'rough': 0.05, 'env': 0.25, 'rim': 0.5, 'rimColor': '#FFFFFF'})
    drng = [0.31, 0.72, 1.05, 0.18, 0.88, 0.5, 0.64, 0.95, 0.25, 0.77, 0.4, 0.58]
    for i in range(12):
        a, y, r = math.pi + (i - 5.5) * 0.23 + drng[i] * 0.1, 0.66 + drng[(i + 5) % 12] * 0.34, 0.3155
        d = K.m(THREE.SphereGeometry(0.014 + drng[i] * 0.01, 8, 6), drop, {'pos': [math.sin(a) * r, y, math.cos(a) * r], 'scale': [1, 1.35, 0.5], 'rot': [0, a, 0], 'cast': False})
        d.userData.noAO = True
        g.add(d)
    g.userData.colliders = [{'min': [-0.32, 0, -0.32], 'max': [0.32, 1.5, 0.32]}]
    return K.finish(game, g, {'ao': {'strength': 0.7}})


registerProp('product_replay_ade', _product_replay_ade,
             {'category': 'sponsors', 'tags': ['product', 'replay_ade'], 'size': [0.63, 1.5, 0.63], 'desc': 'Replay-Ade giant sports-drink bottle, rewind-arrow cap', 'hero': True})


# ------------------------------------------------------------------ Wobble-Up: emerald ring mold on a cake stand
def doilyTex():
    def draw(ctx, w, h, rand):
        cx, cy = w / 2, h / 2
        ctx.clearRect(0, 0, w, h)
        ctx.fillStyle = '#FFFFFF'
        ctx.beginPath()
        for i in range(481):
            a = (i / 480) * TAU
            r = 238 + 12 * math.cos(a * 30)
            ctx.lineTo(cx + math.cos(a) * r, cy + math.sin(a) * r)
        ctx.fill()
        ctx.globalCompositeOperation = 'destination-out'
        for k in range(4):
            rr, n = 96 + k * 36, 14 + k * 6
            for i in range(n):
                a = ((i + (k % 2) * 0.5) / n) * TAU
                ctx.beginPath()
                ctx.ellipse(cx + math.cos(a) * rr, cy + math.sin(a) * rr, 10 + k * 1.5, 5 + k, a, 0, TAU)
                ctx.fill()
        for i in range(30):
            a = (i / 30) * TAU
            ctx.beginPath()
            ctx.arc(cx + math.cos(a) * 232, cy + math.sin(a) * 232, 4.5, 0, TAU)
            ctx.fill()
        ctx.globalCompositeOperation = 'source-over'
        ctx.strokeStyle = 'rgba(190,178,160,0.7)'
        ctx.lineWidth = 2.5
        for r in (72, 160, 222):
            ctx.beginPath()
            ctx.arc(cx, cy, r, 0, TAU)
            ctx.stroke()
    return texC('doily', 512, 512, draw)


def flagTex(id, w=256, h=128):
    S = SP[id]

    def draw(ctx, w_, h_, rand):
        ctx.fillStyle = S['main']
        ctx.fillRect(0, 0, w, h)
        ctx.fillStyle = '#FFFFFF'
        ctx.fillRect(0, 8, w, 6)
        ctx.fillRect(0, h - 14, w, 6)
        text(ctx, S['name'], w / 2, h / 2 - 2, {'fam': FONT['groovy'], 'px': 52, 'fill': '#FFFFFF', 'stroke': S['deep'], 'lw': 8, 'depth': 3, 'depthFill': S['deep'], 'maxW': w * 0.86})
    return texC('flag.%s' % id, w, h, draw)


def _product_wobble_up(game, opts=None):
    g = K.prop('product_wobble_up')
    glass = pm(game, 'ceramic', '#EAE3D4', {'rough': 0.3, 'rim': 0.12})       # milk-glass cake stand
    jellyM = pm(game, 'plastic', '#067A30', {'transparent': True, 'opacity': 0.92, 'rough': 0.1, 'env': 0.2,
                                             'emissive': '#046A28', 'emissiveIntensity': 0.6, 'rim': 0.3, 'rimColor': '#6CFFA0', 'rimPower': 2.6})
    fruitM = pm(game, 'lacquer', '#ffffff', {'rough': 0.3})                   # painted per vertex
    creamM = pm(game, 'ceramic', '#FFF6E6', {'rough': 0.55, 'rim': 0.35})
    doily = pm(game, 'paint', '#EDE7DA', {'map': doilyTex(), 'alphaTest': 0.5, 'side': THREE.DoubleSide, 'rim': 0.04})
    pick = pm(game, 'teak', '#E8C890')
    flag = pm(game, 'paint', '#ffffff', {'map': flagTex('wobble_up')})

    # cake stand: scalloped plate, stem with a knop, domed foot
    st = lathe2([[0, 0], [0.3, 0], [0.316, 0.02], [0.29, 0.056], [0.13, 0.12], [0.075, 0.2], [0.075, 0.28], [0.11, 0.33],
                 [0.55, 0.375], [0.62, 0.395], [0.615, 0.42], [0, 0.42]], {'seg': 48, 'round': 0.02, 'steps': 1})
    radial(st, lambda th, y, r: 1 + 0.035 * math.cos(th * 16) * smoothstep(r, 0.5, 0.6))
    g.add(K.m(st, glass))
    g.add(K.m(flatTorus(0.085, 0.024, 8, 24), glass, {'pos': [0, 0.235, 0]}))
    top = 0.42
    g.add(K.m(THREE.CircleGeometry(0.585, 48).rotateX(-math.pi / 2), doily, {'pos': [0, top + 0.003, 0]}))

    # the tiered, fluted ring mold (pivot at its base: parts.jelly squashes/shears for the wobble)
    jelly = THREE.Group()
    jelly.position.y = top + 0.005
    jelly.userData.noMerge = True
    s = 1.15
    jg = lathe2([[r * s, y * s] for r, y in [[0.16, 0], [0.47, 0], [0.485, 0.035], [0.465, 0.2], [0.425, 0.235], [0.402, 0.27], [0.372, 0.42], [0.315, 0.5],
                                             [0.24, 0.545], [0.19, 0.55], [0.155, 0.525], [0.142, 0.46], [0.15, 0.02], [0.16, 0]]],
                {'seg': 60, 'round': 0.02, 'steps': 1, 'v': False})

    def flutes(th, y, r):
        t = smoothstep(y, 0.22 * s, 0.28 * s)
        return 1 + 0.05 * (1 - 0.25 * t) * math.cos(th * 12 + math.pi * t) * smoothstep(r, 0.22 * s, 0.32 * s)
    radial(jg, flutes)
    jelly.add(K.m(jg, jellyM, {'name': 'jelly'}))

    # suspended fruit, close to the surface so it reads through the gelatin
    def sph(r):
        return THREE.SphereGeometry(r, 10, 8)
    FR = [
        lambda: paint(sph(0.052), '#D81E3A'),                                   # maraschino cherry
        lambda: paint(K.box(0.085, 0.06, 0.075, 0.02), '#FFD84A'),              # pineapple chunk
        lambda: paint(THREE.TorusGeometry(0.045, 0.026, 6, 10, math.pi), '#FF9226'),  # mandarin segment
        lambda: paint(sph(0.042), '#8A3C9A'),                                   # grape
    ]

    def put(n, y, rr, a0):
        for i in range(n):
            a = a0 + (i / n) * TAU
            mm = K.m(FR[(i + n) % len(FR)](), fruitM, {'pos': [math.sin(a) * rr, y, math.cos(a) * rr], 'rot': [i * 0.7, a, i * 1.3]})
            jelly.add(mm)
    put(8, 0.11 * s, 0.37 * s, 0.2)
    put(6, 0.35 * s, 0.29 * s, 0.6)
    # whipped-cream rosette in the hole + cherry on top + toothpick flag
    cg = lathe2([[0, 0], [0.215, 0], [0.2, 0.045], [0.15, 0.09], [0.1, 0.13], [0.05, 0.165], [0.012, 0.19], [0, 0.192]], {'seg': 48, 'v': False})
    radial(cg, lambda th, y, r: 1 + 0.13 * math.cos(th * 8 + y * 26))
    creamY = 0.55 * s - 0.07
    jelly.add(K.m(cg, creamM, {'pos': [0, creamY, 0]}))
    jelly.add(K.m(paint(THREE.SphereGeometry(0.065, 16, 12), '#E0183A'), fruitM, {'pos': [0.01, creamY + 0.235, 0]}))
    jelly.add(K.m(paint(K.tube([[0.01, creamY + 0.28, 0], [0.03, creamY + 0.34, 0.01], [0.075, creamY + 0.38, 0.02]], 0.007, {'seg': 8, 'radial': 5}), '#6B8A2A'), fruitM))
    jelly.add(rod(0.006, [-0.06, creamY + 0.08, 0.02], [-0.16, creamY + 0.46, 0.05], pick, 6))
    for back in (0, 1):
        fg = THREE.PlaneGeometry(0.22, 0.11)
        if not back:
            fg.rotateY(math.pi)
        else:
            fg.translate(0, 0, 0.001)
        fl = K.m(fg, flag, {'pos': [-0.28, creamY + 0.39, 0.05], 'rot': [0, 0.35, -0.26]})
        fl.userData.noAO = True
        jelly.add(fl)
    g.add(jelly)
    g.userData.parts = {'jelly': jelly}
    g.userData.colliders = [{'min': [-0.6, 0, -0.6], 'max': [0.6, 1.3, 0.6]}]
    return K.finish(game, g, {'ao': {'strength': 0.7}})


registerProp('product_wobble_up', _product_wobble_up,
             {'category': 'sponsors', 'tags': ['product', 'wobble_up'], 'size': [1.24, 1.35, 1.24], 'desc': 'Wobble-Up emerald ring gelatin mold with fruit on a milk-glass cake stand (parts.jelly wobbles)', 'hero': True})


# ------------------------------------------------------------------ Jump Cut: drum-sized coffee can + steam bolt
def filmStrip(ctx, y, w, hh, col, hole):
    ctx.fillStyle = col
    ctx.fillRect(0, y, w, hh)
    ctx.fillStyle = hole
    n = 32
    step = w / n
    for i in range(n):
        rrp(ctx, i * step + step * 0.22, y + hh * 0.25, step * 0.56, hh * 0.5, 4)
        ctx.fill()


def jumpBodyTex():
    S = SP['jump_cut']

    def draw(ctx, w, h, rand):
        ctx.fillStyle = lin(ctx, 0, 0, 0, h, ['#F27A36', '#E3662B', '#C9531F'])
        ctx.fillRect(0, 0, w, h)
        ctx.save()
        ctx.beginPath()
        ctx.rect(0, 60, w, h - 120)
        ctx.clip()
        rays(ctx, 512, 150, 700, 36, 'rgba(255,214,120,0.16)')
        ctx.restore()
        filmStrip(ctx, 16, w, 40, S['second'], '#F6E7C8')
        filmStrip(ctx, h - 56, w, 40, S['second'], '#F6E7C8')
        ctx.fillStyle = '#F6E7C8'
        ctx.fillRect(0, 60, w, 4)
        ctx.fillRect(0, h - 64, w, 4)
        # emblem: cream roundel with the bolt
        ctx.beginPath()
        ctx.arc(512, 142, 58, 0, TAU)
        ctx.fillStyle = '#F6E7C8'
        ctx.fill()
        ctx.lineWidth = 8
        ctx.strokeStyle = S['second']
        ctx.stroke()
        boltP(ctx, 512, 142, 88)
        ctx.fillStyle = '#FFD23A'
        ctx.fill()
        ctx.lineWidth = 6
        ctx.strokeStyle = S['deep']
        ctx.lineJoin = 'round'
        ctx.stroke()
        text(ctx, 'Jump Cut', 512, 240, {'fam': FONT['groovy'], 'px': 92, 'fill': lin(ctx, 0, 200, 0, 280, ['#FFFFFF', '#FFF0D0', '#F6D9A8']), 'stroke': S['deep'], 'lw': 12, 'depth': 6, 'depthFill': S['deep'], 'maxW': 310})
        # "COFFEE" ribbon
        rrp(ctx, 400, 288, 224, 44, 8)
        ctx.fillStyle = S['second']
        ctx.fill()
        text(ctx, 'COFFEE', 512, 311, {'fam': FONT['sign'], 'px': 32, 'fill': '#FFD23A', 'track': 6})
        # side panels: little steaming cup + copy
        for x in (230, 794):
            ctx.save()
            ctx.translate(x, 190)
            rrp(ctx, -34, -10, 68, 58, 12)
            ctx.fillStyle = '#F6E7C8'
            ctx.fill()
            ctx.lineWidth = 5
            ctx.strokeStyle = S['deep']
            ctx.stroke()
            ctx.beginPath()
            ctx.arc(38, 16, 14, -1.3, 1.3)
            ctx.lineWidth = 7
            ctx.stroke()
            ctx.fillStyle = S['second']
            ctx.fillRect(-28, -4, 56, 10)
            ctx.strokeStyle = 'rgba(255,255,255,0.8)'
            ctx.lineWidth = 5
            ctx.lineCap = 'round'
            for k in (-14, 0, 14):
                ctx.beginPath()
                ctx.moveTo(k, -18)
                ctx.bezierCurveTo(k - 8, -30, k + 8, -40, k, -56)
                ctx.stroke()
            ctx.restore()
            text(ctx, 'VACUUM PACKED' if x < 512 else 'FRESH-CUT ROAST', x, 272, {'fam': FONT['sign'], 'px': 22, 'fill': '#F6E7C8', 'stroke': S['deep'], 'lw': 4})
            text(ctx, 'REGULAR GRIND' if x < 512 else 'NET WT. 200 LBS', x, 302, {'fam': FONT['round'], 'px': 18, 'fill': S['deep']})
        text(ctx, 'SKIP THE WAITING!', 0, 200, {'fam': FONT['sign'], 'px': 26, 'fill': '#FFD23A', 'stroke': S['deep'], 'lw': 5})
        text(ctx, 'SKIP THE WAITING!', w, 200, {'fam': FONT['sign'], 'px': 26, 'fill': '#FFD23A', 'stroke': S['deep'], 'lw': 5})
        # splice marks (the brand's jump-cut gag)
        ctx.strokeStyle = 'rgba(255,255,255,0.55)'
        ctx.lineWidth = 3
        ctx.setLineDash([10, 8])
        for x in (360, 664):
            ctx.beginPath()
            ctx.moveTo(x, 70)
            ctx.lineTo(x - 18, h - 70)
            ctx.stroke()
        ctx.setLineDash([])
    return texC('jump.body', 1024, 416, draw)


def groundsTex():
    def draw(ctx, w, h, rand):
        ctx.fillStyle = '#3A2014'
        ctx.fillRect(0, 0, w, h)
        for i in range(2600):
            ctx.fillStyle = '#24120A' if rand() < 0.5 else '#5A3420'
            ctx.globalAlpha = 0.6
            ctx.fillRect(rand() * w, rand() * h, 2, 2)
        ctx.globalAlpha = 1
    return K.tex.canvas('sp.grounds', 256, 256, draw)


def _product_jump_cut(game, opts=None):
    g = K.prop('product_jump_cut')
    body = pm(game, 'lacquer', '#ffffff', {'map': jumpBodyTex(), 'rough': 0.3})
    tin = pm(game, 'metal', '#C9CED6', {'rough': 0.3})
    lidM = pm(game, 'plastic', '#8A5230', {'rough': 0.38, 'env': 0.03})
    grounds = pm(game, 'soil', '#ffffff', {'map': groundsTex()})
    steam = pm(game, 'fabric', '#E6DCCD', {'emissive': '#FFD9A0', 'emissiveIntensity': 0.05, 'rim': 0.35, 'rimColor': '#FFF4E0'})
    R, H = 0.42, 1.04

    def bead(y):
        return [[R, y - 0.015], [R - 0.013, y], [R, y + 0.015]]
    can = lathe2([[R, 0.03]] + bead(0.085) + bead(0.14) + [[R, 0.2], [R, H - 0.2]] + bead(H - 0.14) + bead(H - 0.085) + [[R, H - 0.03]], {'seg': 48})
    g.add(K.m(can, body))
    inner = lathe2([[R - 0.01, H - 0.02], [R - 0.01, H - 0.12]], {'seg': 48, 'v': False})
    g.add(K.m(inner, tin))
    g.add(K.m(THREE.CircleGeometry(R - 0.008, 40).rotateX(-math.pi / 2), grounds, {'pos': [0, H - 0.1, 0]}))
    g.add(K.m(THREE.CircleGeometry(R, 40).rotateX(math.pi / 2), tin, {'pos': [0, 0.03, 0]}))
    g.add(K.m(flatTorus(R, 0.024, 8, 48), tin, {'pos': [0, 0.03, 0]}))
    g.add(K.m(flatTorus(R, 0.022, 8, 48), tin, {'pos': [0, H - 0.02, 0]}))
    # snap-on lid popped open at the front (hinged on its back edge)
    lid = lathe2([[0, 0], [0.4, 0], [0.43, -0.02], [0.448, -0.012], [0.452, 0.06], [0.436, 0.082], [0.37, 0.09], [0, 0.094]], {'seg': 48, 'round': 0.01, 'steps': 1, 'v': False})
    hinge = THREE.Group()
    hinge.position.set(0, H + 0.004, R)
    hinge.rotation.x = 0.26
    hinge.add(K.m(lid, lidM, {'pos': [0, 0, -R]}))
    hinge.add(K.m(flatTorus(0.34, 0.012, 6, 40), lidM, {'pos': [0, 0.09, -R]}))
    g.add(hinge)

    # steam puffs escaping the gap + the steam lightning bolt
    def puff(x, y, z, r, sx=1, sy=0.8):
        return g.add(K.m(THREE.SphereGeometry(r, 14, 10), steam, {'pos': [x, y, z], 'scale': [sx, sy, sx]}))
    puff(-0.02, H + 0.08, -0.3, 0.11, 1.2, 0.75)
    puff(0.13, H + 0.07, -0.26, 0.085)
    puff(-0.15, H + 0.06, -0.24, 0.08)
    puff(0.05, H + 0.16, -0.3, 0.075)
    boltShape = [[x * 0.66, -y * 0.62] for x, y in BOLT_PTS]
    g.add(K.m(K.extrude(boltShape, 0.17, {'bevel': 0.055, 'round': 0.04, 'curveSeg': 6, 'bevelSeg': 3}), steam, {'pos': [0.02, H + 0.43, -0.3], 'rot': [0.12, 0, -0.12]}))
    # a wind-key soldered on the side (opens the old vacuum strip)
    g.add(K.m(THREE.TorusGeometry(0.045, 0.011, 6, 16), tin, {'pos': [R + 0.075, H - 0.24, 0.1], 'rot': [0, math.pi / 2, 0]}))
    g.add(rod(0.009, [R + 0.005, H - 0.24, 0.1], [R + 0.03, H - 0.24, 0.1], tin, 8))
    g.add(K.m(THREE.CylinderGeometry(0.01, 0.01, 0.32, 8).rotateX(math.pi / 2), tin, {'pos': [R + 0.012, H - 0.24, -0.06]}))
    g.userData.colliders = [{'min': [-0.45, 0, -0.45], 'max': [0.45, 1.5, 0.45]}]
    return K.finish(game, g, {'ao': {'strength': 0.7}})


registerProp('product_jump_cut', _product_jump_cut,
             {'category': 'sponsors', 'tags': ['product', 'jump_cut'], 'size': [0.9, 1.55, 0.9], 'desc': 'Jump Cut Coffee drum-sized orange can, lid popped, steam lightning bolt', 'hero': True})


# ------------------------------------------------------------------ Roller Boogie: wax tin + rainbow roller skate
def tinSideTex():
    S = SP['roller_boogie']

    def draw(ctx, w, h, rand):
        ctx.fillStyle = S['second']
        ctx.fillRect(0, 0, w, h)
        cols = [BAR['red'], '#FF9A2A', BAR['yellow'], BAR['green'], BAR['blue']]
        for i, c in enumerate(cols):
            ctx.fillStyle = c
            ctx.fillRect(0, 22 + i * 9, w, 9)
        for i in range(4):
            text(ctx, 'ROLLER BOOGIE', 128 + i * 256, 96, {'fam': FONT['sign'], 'px': 24, 'fill': '#FFFFFF', 'stroke': S['deep'], 'lw': 4})
            sparkle(ctx, 256 + i * 256, 96, 10, '#5FE3FF')
    return texC('roller.side', 1024, 128, draw)


def tinLidTex():
    S = SP['roller_boogie']

    def draw(ctx, w, h, rand):
        cx, cy = w / 2, h / 2
        ctx.fillStyle = S['main']
        ctx.fillRect(0, 0, w, h)
        ctx.save()
        ctx.beginPath()
        ctx.arc(cx, cy, 250, 0, TAU)
        ctx.clip()
        rays(ctx, cx, cy, 300, 24, 'rgba(255,255,255,0.14)')
        ctx.restore()
        cols = [BAR['blue'], BAR['green'], BAR['yellow'], '#FF9A2A', BAR['red']]
        for i, c in enumerate(cols):
            ctx.beginPath()
            ctx.arc(cx, cy, 250 - i * 9, 0, TAU)
            ctx.lineWidth = 9
            ctx.strokeStyle = c
            ctx.stroke()
        ctx.beginPath()
        ctx.arc(cx, cy, 204, 0, TAU)
        ctx.fillStyle = S['second']
        ctx.fill()

        # arched lettering around the rim
        def arc(s, r, a0, px, col, flip):
            font(ctx, px, FONT['sign'])
            ctx.fillStyle = col
            ctx.textAlign = 'center'
            ctx.textBaseline = 'middle'
            chars = list(s)
            sp = (len(chars) * px * 0.62) / r
            for i, ch in enumerate(chars):
                a = a0 + sp / 2 - (i + 0.5) * (sp / len(chars)) if flip else a0 - sp / 2 + (i + 0.5) * (sp / len(chars))
                ctx.save()
                ctx.translate(cx + math.cos(a) * r, cy + math.sin(a) * r)
                ctx.rotate(a - math.pi / 2 if flip else a + math.pi / 2)
                ctx.lineWidth = 6
                ctx.strokeStyle = S['deep']
                ctx.strokeText(ch, 0, 0)
                ctx.fillText(ch, 0, 0)
                ctx.restore()
        arc('ROLLER BOOGIE', 172, -math.pi / 2, 40, '#FFFFFF', False)
        arc("NEVER STOP ROLLIN'", 176, math.pi / 2, 26, '#5FE3FF', True)
        text(ctx, 'SKATE WAX', cx, cy, {'fam': FONT['groovy'], 'px': 58, 'fill': '#FFD23A', 'stroke': S['deep'], 'lw': 9, 'depth': 4, 'depthFill': S['deep'], 'maxW': 300})
        for x, y, r in [[150, 200, 14], [360, 190, 11], [170, 330, 10], [350, 320, 14]]:
            sparkle(ctx, x, y, r, '#FFFFFF')
    return texC('roller.lid', 512, 512, draw)


def bootTex():
    def draw(ctx, w, h, rand):
        ctx.fillStyle = '#EFE7D8'
        ctx.fillRect(0, 0, w, h)
        cols = [BAR['red'], '#FF9A2A', BAR['yellow'], BAR['green'], BAR['blue'], '#8A4ADC']
        # rainbow swoosh sweeping from the toe (u low, bottom) up to the heel collar (u high, top)
        ctx.lineCap = 'butt'
        for i, c in enumerate(cols):
            o = i * 15
            ctx.beginPath()
            ctx.moveTo(20, 450 - o)
            ctx.bezierCurveTo(250, 450 - o, 360 - o * 0.6, 420 - o, 400 - o * 0.9, 60)
            ctx.lineWidth = 16
            ctx.strokeStyle = c
            ctx.stroke()
        ctx.strokeStyle = 'rgba(90,60,40,0.45)'
        ctx.lineWidth = 2
        ctx.setLineDash([6, 5])
        ctx.beginPath()
        ctx.moveTo(20, 470)
        ctx.bezierCurveTo(250, 470, 372, 440, 412, 60)
        ctx.stroke()
        ctx.beginPath()
        ctx.moveTo(20, 364)
        ctx.bezierCurveTo(250, 364, 300, 330, 316, 60)
        ctx.stroke()
        ctx.beginPath()
        ctx.moveTo(0, 470)
        ctx.lineTo(w, 470)
        ctx.stroke()
        ctx.setLineDash([])
    return texC('roller.boot', 512, 512, draw)


def rollerSkate(game, mats, o=None):
    # local: wheels touch y=0, toe toward -z. mats: { boot, plastic (vertex painted), chrome }
    o = o or {}
    g = THREE.Group()
    boot, plastic, chrome = mats['boot'], mats['plastic'], mats['chrome']
    wheelCols = o.get('wheelCols') or [BAR['red'], BAR['yellow'], BAR['green'], BAR['blue']]
    WR = 0.08
    wheel = K.lathe([[0.028, -0.036], [0.066, -0.036], [0.08, -0.022], [0.08, 0.022], [0.066, 0.036], [0.028, 0.036]], {'seg': 16, 'round': 0.01, 'steps': 1})
    wi = 0
    for z in (-0.22, 0.22):
        for x in (-0.125, 0.125):
            g.add(K.m(paint(wheel, wheelCols[wi % 4]), plastic, {'pos': [x, WR, z], 'rot': [0, 0, math.pi / 2]}))
            wi += 1
            g.add(K.m(THREE.CylinderGeometry(0.03, 0.03, 0.078, 10).rotateZ(math.pi / 2), chrome, {'pos': [x, WR, z]}))
        g.add(K.m(THREE.CylinderGeometry(0.011, 0.011, 0.34, 8).rotateZ(math.pi / 2), chrome, {'pos': [0, WR, z]}))
        g.add(K.m(K.box(0.1, 0.06, 0.07, 0.012), chrome, {'pos': [0, WR + 0.035, z]}))
        g.add(K.m(paint(THREE.CylinderGeometry(0.03, 0.03, 0.03, 10), '#F4E03A'), plastic, {'pos': [0, WR + 0.07, z + (0.035 if z < 0 else -0.035)]}))
    g.add(K.m(K.box(0.17, 0.024, 0.66, 0.01), chrome, {'pos': [0, 0.143, 0]}))
    # sole + heel block (brown), boot on top
    g.add(K.m(paint(K.box(0.3, 0.05, 0.74, 0.02), '#7A4A2A'), plastic, {'pos': [0, 0.18, -0.01]}))
    g.add(K.m(paint(K.box(0.27, 0.07, 0.22, 0.02), '#6B3E22'), plastic, {'pos': [0, 0.235, 0.24]}))
    # the boot: ONE sculpted shell (a subdivided cushion re-mapped to an L profile: low toe box, instep ramp, tall
    # shaft leaning back), so it reads as a single stitched leather boot
    SOLE = 0.205

    def topH(z):
        return 0.13 + 0.07 * smoothstep(z, -0.37, -0.27) + 0.06 * smoothstep(z, -0.28, -0.12) + 0.37 * smoothstep(z, -0.16, 0.1)
    bootG = K.cushion(0.29, 1, 0.74, {'puff': 0.025, 'r': 0.1, 'seg': [6, 12, 13]}).clone()

    def shape_boot(v):
        h = topH(v.z)
        v.y = SOLE + (v.y + 0.5) * h
        toe = smoothstep(-v.z, 0.1, 0.37)
        v.x *= (1 - 0.18 * toe) * (1 - 0.1 * smoothstep(v.y, 0.5, 0.85))
        if v.z < -0.26:
            v.z = -0.26 - (-0.26 - v.z) * math.sqrt(max(0, 1 - (v.x / 0.13) ** 2))
        v.z += max(0, v.y - 0.45) * 0.14
    deform(bootG, shape_boot)
    K.weldNormals(bootG)
    g.add(K.m(uvPlanar(bootG, 'z', -0.42, 0.42, 'y', 0.15, 0.95), boot))

    def ramp(z, lift=0):
        return [SOLE + topH(z) + lift, z + max(0, SOLE + topH(z) - 0.45) * 0.14]
    # padded collar
    collar = THREE.TorusGeometry(0.15, 0.04, 8, 24).rotateX(math.pi / 2)
    collar.scale(0.98, 1, 0.95)
    g.add(K.m(paint(collar, '#FF5FA2'), plastic, {'pos': [0, SOLE + 0.63, 0.27], 'rot': [0.14, 0, 0]}))
    # tongue lying on the instep ramp, poking out above the collar
    tongue = K.cushion(0.15, 0.3, 0.04, {'puff': 0.012}).clone()

    def bend(v):
        v.z += 0.35 * (v.y + 0.15) ** 2
    deform(tongue, bend)
    g.add(K.m(paint(tongue, '#FF8CBE'), plastic, {'pos': [0, 0.7, -0.005], 'rot': [0.5, 0, 0]}))
    # criss-cross laces over the tongue + a bow at the top
    zs = [-0.15, -0.1, -0.05, 0.0, 0.045]
    for i in range(len(zs) - 1):
        y0, z0 = ramp(zs[i], 0.035)
        y1, z1 = ramp(zs[i + 1], 0.035)
        ym, zm = ramp((zs[i] + zs[i + 1]) / 2, 0.06)
        for sx in (-1, 1):
            g.add(K.m(paint(K.tube([[sx * 0.1, y0, z0], [0, ym, zm - 0.012], [-sx * 0.1, y1, z1]], 0.0095, {'seg': 8, 'radial': 4}), '#FF5FA2'), plastic))
    by, bz = ramp(0.06, 0.07)
    for sx in (-1, 1):
        g.add(K.m(paint(THREE.TorusGeometry(0.036, 0.012, 6, 14), '#FF5FA2'), plastic, {'pos': [sx * 0.035, by + 0.01, bz - 0.03], 'rot': [-0.9, sx * 0.5, sx * 0.4], 'scale': [1.25, 0.8, 1]}))
    g.add(K.m(paint(THREE.SphereGeometry(0.018, 8, 6), '#FF5FA2'), plastic, {'pos': [0, by, bz - 0.035]}))
    # pink toe stop on a chrome stem
    g.add(rod(0.014, [0, 0.14, -0.3], [0, 0.1, -0.37], chrome, 8))
    stop = K.lathe([[0, 0], [0.05, 0], [0.056, 0.012], [0.056, 0.06], [0.046, 0.072], [0, 0.072]], {'seg': 16, 'round': 0.01})
    g.add(span(K.m(paint(stop, '#FF4F9A'), plastic), [0, 0.115, -0.35], [0, 0.03, -0.43]))
    return g


def _product_roller_boogie(game, opts=None):
    g = K.prop('product_roller_boogie')
    plastic = pm(game, 'lacquer', '#ffffff', {'rough': 0.3})
    chrome = pm(game, 'chrome', '#98A0AC')
    side = pm(game, 'lacquer', '#ffffff', {'map': tinSideTex(), 'rough': 0.3})
    lidTop = pm(game, 'lacquer', '#ffffff', {'map': tinLidTex(), 'rough': 0.45, 'rim': 0.05, 'env': 0.02})
    boot = pm(game, 'vinyl', '#ffffff', {'map': bootTex(), 'rough': 0.32})
    R = 0.5
    g.add(K.m(lathe2([[0, 0], [R - 0.012, 0], [R, 0.014], [R, 0.25], [R - 0.01, 0.258], [0, 0.258]], {'seg': 40, 'round': 0.006, 'steps': 1}), side))
    g.add(K.m(paint(flatTorus(R - 0.004, 0.012, 5, 40), SP['roller_boogie']['main']), plastic, {'pos': [0, 0.012, 0]}))
    lid = lathe2([[R - 0.004, 0.232], [R + 0.013, 0.24], [R + 0.016, 0.25], [R + 0.016, 0.33], [R + 0.008, 0.346], [R - 0.012, 0.352], [0, 0.353]], {'seg': 40, 'round': 0.006, 'steps': 1, 'v': False})
    g.add(K.m(paint(lid, SP['roller_boogie']['main']), plastic))
    g.add(K.m(THREE.CircleGeometry(R - 0.03, 48).rotateX(-math.pi / 2).rotateY(math.pi), lidTop, {'pos': [0, 0.354, 0]}))
    # the butterfly twist-opener on the side of the tin
    op = THREE.Group()
    op.position.set(R + 0.02, 0.2, -0.02)
    op.add(K.m(K.cyl(0.028, 0.028, 0.03, {'bevel': 0.008, 'seg': 12}), chrome, {'rot': [0, 0, -math.pi / 2]}))
    op.add(K.m(K.extrude([[-0.075, 0.02], [0.075, 0.02], [0.075, -0.02], [-0.075, -0.02]], 0.014, {'bevel': 0.005, 'round': 0.018}), chrome, {'pos': [0.035, 0, 0], 'rot': [0, math.pi / 2, 0.5]}))
    g.add(op)
    sk = rollerSkate(game, {'boot': boot, 'plastic': plastic, 'chrome': chrome})
    sk.scale.setScalar(1.12)
    sk.position.set(0, 0.354, 0.02)
    sk.rotation.y = -0.45
    g.add(sk)
    g.userData.colliders = [{'min': [-0.52, 0, -0.52], 'max': [0.52, 1.3, 0.52]}]
    return K.finish(game, g, {'ao': {'strength': 0.7}})


registerProp('product_roller_boogie', _product_roller_boogie,
             {'category': 'sponsors', 'tags': ['product', 'roller_boogie'], 'size': [1.04, 1.3, 1.04], 'desc': 'Roller Boogie Wax tin with a rainbow roller skate on the lid', 'hero': True})


# ------------------------------------------------------------------ Double Vision: striped toothpaste tube
def tubeTex():
    S = SP['double_vision']

    def draw(ctx, w, h, rand):
        cols = ['#E23B3B', '#F7F3EA', '#2F5BD3']
        P = 128
        bw, sk = P / 3, 0.62 * h
        for k in range(-8, 14):
            for b, c in enumerate(cols):
                x = k * P + b * bw
                ctx.beginPath()
                ctx.moveTo(x, 0)
                ctx.lineTo(x + bw + 0.8, 0)
                ctx.lineTo(x + bw + 0.8 - sk, h)
                ctx.lineTo(x - sk, h)
                ctx.closePath()
                ctx.fillStyle = c
                ctx.fill()
        # white shoulder band and crimp band with ridges + printer registration squares
        ctx.fillStyle = '#F7F3EA'
        ctx.fillRect(0, 0, w, 22)
        ctx.fillStyle = S['deep']
        ctx.fillRect(0, 20, w, 6)
        cy0 = h * 0.86
        ctx.fillStyle = '#F7F3EA'
        ctx.fillRect(0, cy0, w, h - cy0)
        ctx.fillStyle = S['deep']
        ctx.fillRect(0, cy0 - 6, w, 6)
        ctx.strokeStyle = 'rgba(40,40,60,0.28)'
        ctx.lineWidth = 2
        for x in range(0, w, 7):
            ctx.beginPath()
            ctx.moveTo(x, cy0 + 22)
            ctx.lineTo(x, h)
            ctx.stroke()
        for i, c in enumerate([BAR['cyan'], BAR['magenta'], BAR['yellow'], INK]):
            ctx.fillStyle = c
            ctx.fillRect(452 + i * 30, cy0 + 8, 20, 12)
        # front label panel (u = 0.5 faces -z)
        px, py0, py1 = 512, 60, 380
        rrp(ctx, px - 138, py0, 276, py1 - py0, 26)
        ctx.fillStyle = S['deep']
        ctx.fill()
        rrp(ctx, px - 130, py0 + 8, 260, py1 - py0 - 16, 20)
        ctx.fillStyle = '#FFFDF6'
        ctx.fill()
        ctx.save()
        ctx.clip()
        rays(ctx, px, 170, 260, 20, 'rgba(63,184,232,0.14)')
        ctx.restore()
        # smiling tooth mascot with a star glint
        ctx.save()
        ctx.translate(px, 128)
        ctx.beginPath()
        ctx.moveTo(-34, -30)
        ctx.bezierCurveTo(-50, -48, -12, -54, 0, -40)
        ctx.bezierCurveTo(12, -54, 50, -48, 34, -30)
        ctx.bezierCurveTo(44, 0, 30, 20, 22, 44)
        ctx.bezierCurveTo(16, 56, 8, 40, 0, 26)
        ctx.bezierCurveTo(-8, 40, -16, 56, -22, 44)
        ctx.bezierCurveTo(-30, 20, -44, 0, -34, -30)
        ctx.closePath()
        ctx.fillStyle = '#FFFFFF'
        ctx.fill()
        ctx.lineWidth = 5
        ctx.strokeStyle = S['deep']
        ctx.stroke()
        ctx.fillStyle = S['deep']
        for s in (-1, 1):
            ctx.beginPath()
            ctx.ellipse(s * 12, -14, 4.5, 7, 0, 0, TAU)
            ctx.fill()
        ctx.beginPath()
        ctx.arc(0, 0, 14, 0.2, math.pi - 0.2)
        ctx.lineWidth = 4
        ctx.stroke()
        ctx.restore()
        sparkle(ctx, px + 44, 96, 16, '#FFD23A')
        # the ghosted wordmark: cyan + magenta copies drifting apart behind the main one
        for dx, col in [[-6, 'rgba(63,214,224,0.85)'], [6, 'rgba(255,79,160,0.85)'], [0, S['deep']]]:
            text(ctx, 'Double', px + dx, 212, {'fam': FONT['groovy'], 'px': 62, 'fill': col, 'maxW': 236})
            text(ctx, 'Vision', px + dx, 268, {'fam': FONT['groovy'], 'px': 62, 'fill': col, 'maxW': 236})
        rrp(ctx, px - 110, 306, 220, 34, 8)
        ctx.fillStyle = '#E23B3B'
        ctx.fill()
        text(ctx, 'TOOTHPASTE', px, 324, {'fam': FONT['sign'], 'px': 24, 'fill': '#FFFFFF', 'track': 2, 'maxW': 200})
        text(ctx, 'TWICE THE SMILE!', px, 356, {'fam': FONT['round'], 'px': 17, 'fill': S['deep']})
        # back panel
        for ox in (0, w):
            rrp(ctx, ox - 80, 146, 160, 128, 16)
            ctx.fillStyle = S['deep']
            ctx.fill()
            rrp(ctx, ox - 74, 152, 148, 116, 12)
            ctx.fillStyle = '#FFFDF6'
            ctx.fill()
        for x in (0, w):
            text(ctx, 'WITH', x, 180, {'fam': FONT['round'], 'px': 18, 'fill': S['deep']})
            text(ctx, 'SPARKLE', x, 208, {'fam': FONT['sign'], 'px': 22, 'fill': '#E23B3B'})
            text(ctx, 'CRYSTALS', x, 236, {'fam': FONT['sign'], 'px': 22, 'fill': '#2F5BD3'})
    return texC('dv.tube', 1024, 512, draw)


def _product_double_vision(game, opts=None):
    g = K.prop('product_double_vision')
    tubeM = pm(game, 'plastic', '#ffffff', {'map': tubeTex(), 'rough': 0.26})
    plastic = pm(game, 'plastic', '#ffffff', {'rough': 0.28})
    chrome = pm(game, 'chrome', '#98A0AC')
    rings = [[0.36, 0.0, 0.07, 5]]
    N = 30
    for i in range(N + 1):
        t = i / N
        flat = 1 - smoothstep(t, 0.05, 0.5)
        bulge = 0.012 * math.sin(math.pi * clamp((t - 0.45) / 0.55, 0, 1))
        rings.append([lerp(0.27, 0.365, flat) + bulge, lerp(0.27, 0.022, flat ** 1.5) + bulge, 0.07 + t * 1.0, lerp(2, 5, flat ** 1.5)])
    g.add(K.m(loft(rings, 48), tubeM))
    # shoulder + threaded neck
    T = 1.07
    g.add(K.m(paint(lathe2([[0.268, 0], [0.266, 0.02], [0.225, 0.065], [0.14, 0.094], [0.1, 0.1], [0.1, 0.13], [0, 0.13]], {'seg': 40, 'round': 0.012, 'steps': 1, 'v': False}), '#F7F3EA'), plastic, {'pos': [0, T, 0]}))
    for y in (0.107, 0.122):
        g.add(K.m(paint(flatTorus(0.1, 0.006, 5, 24), '#F7F3EA'), plastic, {'pos': [0, T + y, 0]}))
    # spinning fluted cap (parts.cap)
    cap = THREE.Group()
    cap.position.y = T + 0.098
    cap.userData.noMerge = True
    cg = lathe2([[0, 0], [0.13, 0], [0.142, 0.012], [0.142, 0.15], [0.13, 0.168], [0.06, 0.176], [0, 0.176]], {'seg': 48, 'round': 0.01, 'steps': 1, 'v': False})
    radial(cg, lambda th, y, r: 1 + 0.045 * max(0, math.cos(th * 24)) * smoothstep(y, 0.015, 0.03) * (1 - smoothstep(y, 0.14, 0.155)))
    cap.add(K.m(paint(cg, '#2F5BD3'), plastic))
    cap.add(K.m(paint(flatTorus(0.1, 0.012, 6, 32), '#F7F3EA'), plastic, {'pos': [0, 0.172, 0]}))
    cap.add(K.m(paint(K.cyl(0.075, 0.08, 0.02, {'bevel': 0.008, 'seg': 24}), '#E23B3B'), plastic, {'pos': [0, 0.168, 0]}))
    g.add(cap)
    # chrome display clamp holding the crimp
    steel = pm(game, 'metal', '#7A828E', {'rough': 0.42, 'env': 0.12})
    base = lathe2([[0, 0], [0.34, 0], [0.352, 0.018], [0.32, 0.05], [0, 0.056]], {'seg': 40, 'round': 0.01, 'steps': 1, 'v': False})
    base.scale(1.25, 1, 0.62)
    g.add(K.m(base, steel))
    g.add(K.m(K.box(0.84, 0.07, 0.09, 0.025), steel, {'pos': [0, 0.09, 0]}))
    for sx in (-1, 1):
        g.add(K.m(K.cyl(0.02, 0.02, 0.012, {'bevel': 0.005, 'seg': 12}), chrome, {'pos': [sx * 0.3, 0.09, -0.046], 'rot': [math.pi / 2, 0, 0]}))
    g.userData.parts = {'cap': cap}
    g.userData.colliders = [{'min': [-0.43, 0, -0.3], 'max': [0.43, 1.35, 0.3]}]
    return K.finish(game, g, {'ao': {'strength': 0.7}})


registerProp('product_double_vision', _product_double_vision,
             {'category': 'sponsors', 'tags': ['product', 'double_vision'], 'size': [0.86, 1.35, 0.44], 'desc': 'Double Vision striped toothpaste tube in a chrome clamp (parts.cap spins)', 'hero': True})

# =============================================================================================== DROPS
# drop_<type>: the item floats inside a 0.6 m glass "screen bubble" (glossy glass + additive fresnel shell with
# rolling scanlines in the drop's glow color, GDD §12) over a glowing gold floor ring. Local: floor at y=0; the
# bubble center sits at y=1.0 (parts.float). parts.model = the item; animated sub-parts listed per type.
# animateDrop(drop, t) (Godot powerups.gd) runs the bob (0.1 m @ 1 Hz), the 90°/s spin and the item's own loop.
DROP_TYPES = ['cancelled', 'full_reel', 'one_take', 'sweeps_week', 'gaffer_tape', 'please_stand_by']
DROP_GLOW = {'cancelled': '#E3662B', 'full_reel': '#FFC23A', 'one_take': '#FF3B30', 'sweeps_week': '#FF4FA0', 'gaffer_tape': '#DDE3EA', 'please_stand_by': '#EDEDED'}

# BUBBLE_VERT / BUBBLE_FRAG (fresnel edge + scanlines + rolling band, additive, uColor * a * uIntensity) live in
# godot/shaders/bubble.gdshader; the spec here is materials.gd bubble(color, intensity).
_bubbleMats = {}


def bubbleMat(game, color, intensity=1.1):
    m = _bubbleMats.get(id(game))
    if m is None:
        m = _bubbleMats[id(game)] = {}
    key = '%s|%s' % (color, js_str(intensity))
    if key not in m:
        mat = K.material('bubble', color, {'intensity': intensity}, type='ShaderMaterial', transparent=True,
                         blending=THREE.AdditiveBlending, depthWrite=False)
        mat.name = 'bubble:%s' % color
        m[key] = mat
    return m[key]


def radialTex():
    def draw(ctx, w, h, rand):
        g = ctx.createRadialGradient(w / 2, h / 2, 0, w / 2, h / 2, w / 2)
        g.addColorStop(0, 'rgba(255,255,255,0.9)')
        g.addColorStop(0.35, 'rgba(255,255,255,0.35)')
        g.addColorStop(0.72, 'rgba(255,255,255,0.12)')
        g.addColorStop(0.86, 'rgba(255,255,255,0.5)')
        g.addColorStop(0.93, 'rgba(255,255,255,0.08)')
        g.addColorStop(1, 'rgba(255,255,255,0)')
        ctx.fillStyle = g
        ctx.fillRect(0, 0, w, h)
    return K.tex.canvas('sp.radial', 256, 256, draw, {'repeat': False})


# Shared shell: gold floor ring + bubble. Returns { g, float, model }.
def dropShell(game, type):
    g = K.prop('drop_%s' % type)
    glowCol = DROP_GLOW[type]
    # glowing gold floor ring (flat glow ring + soft pool + a glossy gold torus)
    ringG = THREE.Group()
    ringG.add(K.m(THREE.RingGeometry(0.32, 0.375, 40).rotateX(-math.pi / 2), K.glow(game, PAL.marqueeGold, 1.5), {'pos': [0, 0.012, 0], 'cast': False}))
    pool = K.m(THREE.CircleGeometry(0.58, 32).rotateX(-math.pi / 2), K.glow(game, PAL.marqueeGold, 0.7, {'map': radialTex(), 'additive': True}), {'pos': [0, 0.008, 0], 'cast': False})
    ringG.add(pool)
    ringG.add(K.m(flatTorus(0.385, 0.016, 5, 40), pm(game, 'brass', '#D6A13C'), {'pos': [0, 0.018, 0]}))

    def flags(o):
        if getattr(o, 'isMesh', False):
            o.userData.noAO = True
            o.userData.noOcclude = True
            o.userData.noShadow = True
    ringG.traverse(flags)
    g.add(ringG)
    # the floating screen bubble
    float_ = THREE.Group()
    float_.position.y = 1.0
    float_.userData.noMerge = True
    shellG = K.cushion(0.6, 0.6, 0.6, {'r': 0.16, 'puff': 0.04, 'seg': [6, 6, 6]})
    glassM = game.mats.toon('#ffffff', {'transparent': True, 'opacity': 0.07, 'rough': 0.06, 'env': 0.35, 'rim': 0.12, 'rimColor': '#ffffff',
                                        'depthWrite': False, 'keepColor': True, 'name': 'bubble_glass'})
    glass = K.m(shellG, glassM, {'name': 'bubble_glass', 'cast': False})
    rim = K.m(shellG, bubbleMat(game, glowCol), {'name': 'bubble_rim', 'cast': False, 'scale': 1.004})
    for o in (glass, rim):
        o.userData.noAO = True
        o.userData.noShadow = True
        o.renderOrder = 2
    model = THREE.Group()
    model.name = 'model'
    model.scale.setScalar(1.22)
    float_.add(model, glass, rim)
    g.add(float_)
    g.userData.colliders = []
    g.userData.dropType = type
    g.userData.glow = glowCol
    g.userData.lightAnchors = [{'pos': [0, 0.15, 0], 'color': glowCol, 'intensity': 0.8, 'distance': 2.2}]  # floor glow, below the item
    g.userData.parts = {'float': float_, 'model': model, 'bubble': glass, 'rim': rim, 'ring': ringG}
    return {'g': g, 'float': float_, 'model': model}


# AO once, merge the static item meshes, then finish without re-baking.
def finishDrop(game, g, model):
    K.bakeAO(g, {'strength': 0.75, 'height': 0})
    K.merge(model)
    return K.finish(game, g, {'ao': False, 'merge': False, 'cast': 0.1})


# ------------------------------------------------------------------ CANCELLED: rubber stamp over a stamped ticket
def stampTicketTex():
    def draw(ctx, w, h, rand):
        ctx.fillStyle = '#FBF3DE'
        ctx.fillRect(0, 0, w, h)
        ctx.strokeStyle = 'rgba(47,91,211,0.25)'
        ctx.lineWidth = 2
        y = 26
        while y < h:
            ctx.beginPath()
            ctx.moveTo(0, y)
            ctx.lineTo(w, y)
            ctx.stroke()
            y += 18
        ctx.save()
        ctx.translate(w / 2, h / 2)
        ctx.rotate(-0.12)
        ctx.strokeStyle = '#E23B3B'
        ctx.lineWidth = 7
        rrp(ctx, -108, -38, 216, 76, 10)
        ctx.stroke()
        text(ctx, 'CANCELLED', 0, 2, {'fam': FONT['sign'], 'px': 34, 'fill': '#E23B3B', 'maxW': 196})
        ctx.restore()
        ctx.globalCompositeOperation = 'destination-out'
        for i in range(90):
            ctx.globalAlpha = 0.25 + rand() * 0.4
            ctx.beginPath()
            ctx.arc(40 + rand() * 180, 40 + rand() * 80, 1 + rand() * 2.5, 0, TAU)
            ctx.fill()
        ctx.globalCompositeOperation = 'source-over'
        ctx.globalAlpha = 1
    return texC('drop.ticket', 256, 160, draw)


def stampFaceTex():  # the rubber die: raised mirrored letters (seen from below)
    def draw(ctx, w, h, rand):
        ctx.fillStyle = '#9E1E24'
        ctx.fillRect(0, 0, w, h)
        ctx.save()
        ctx.translate(w / 2, h / 2)
        ctx.scale(-1, 1)
        ctx.strokeStyle = '#E8454A'
        ctx.lineWidth = 8
        rrp(ctx, -112, -46, 224, 92, 10)
        ctx.stroke()
        text(ctx, 'CANCELLED', 0, 3, {'fam': FONT['sign'], 'px': 36, 'fill': '#E8454A', 'maxW': 200})
        ctx.restore()
    return texC('drop.stampface', 256, 128, draw)


def _drop_cancelled(game, opts=None):
    sh = dropShell(game, 'cancelled')
    g, model = sh['g'], sh['model']
    red = pm(game, 'lacquer', '#E23B3B', {'rough': 0.24})
    wood = pm(game, 'lacquer', '#ffffff', {'map': K.tex.wood('#8A5A34', {'dark': 0.35})})
    label = pm(game, 'plastic', '#ffffff', {'map': K.tex.label('CANCELLED', {'bg': '#F6E7C8', 'fg': '#E23B3B', 'accent': '#5A3A22', 'w': 512, 'h': 128, 'border': 0.08, 'wear': 0.15})})
    face = pm(game, 'rubber', '#ffffff', {'map': stampFaceTex()})
    paper = pm(game, 'paint', '#ffffff', {'map': stampTicketTex(), 'side': THREE.DoubleSide, 'rim': 0.05})
    brass = pm(game, 'brass', '#C8963C')
    # stamped ticket at the bubble floor
    tk = K.m(THREE.PlaneGeometry(0.3, 0.19, 4, 1).rotateX(-math.pi / 2).rotateY(math.pi), paper, {'pos': [0, -0.2, 0], 'rot': [0, 0.18, 0]})

    def curl(v):
        v.y += 0.012 * math.cos((v.x / 0.15) * 1.6)
    deform(tk.geometry, curl)
    model.add(tk)
    # the stamp (parts.stamp moves down to the ticket)
    stamp = THREE.Group()
    stamp.userData.noMerge = True
    stamp.position.y = -0.1
    stamp.add(K.m(K.box(0.27, 0.022, 0.13, 0.008), face, {'pos': [0, 0.011, 0]}))
    stamp.add(K.m(THREE.PlaneGeometry(0.25, 0.115).rotateX(math.pi / 2), face, {'pos': [0, -0.0005, 0]}))
    stamp.add(K.m(K.box(0.29, 0.07, 0.15, 0.018, {'uv': 3}), wood, {'pos': [0, 0.057, 0]}))
    stamp.add(K.m(K.box(0.24, 0.042, 0.004, 0.002), label, {'pos': [0, 0.057, -0.076]}))
    stamp.add(K.m(K.box(0.24, 0.042, 0.004, 0.002), label, {'pos': [0, 0.057, 0.076], 'rot': [0, math.pi, 0]}))
    stamp.add(K.m(K.lathe([[0, 0], [0.045, 0], [0.032, 0.03], [0.03, 0.06], [0.04, 0.075], [0.028, 0.095], [0, 0.095]], {'seg': 16, 'round': 0.008, 'steps': 1}), wood, {'pos': [0, 0.09, 0]}))
    stamp.add(K.m(flatTorus(0.036, 0.008, 5, 16), brass, {'pos': [0, 0.16, 0]}))
    stamp.add(K.m(K.lathe([[0, 0], [0.04, 0], [0.075, 0.025], [0.085, 0.06], [0.07, 0.095], [0.035, 0.112], [0, 0.114]], {'seg': 20, 'round': 0.012, 'steps': 1}), red, {'pos': [0, 0.18, 0]}))
    model.add(stamp)
    model.rotation.set(0.12, -0.3, 0.05)
    g.userData.parts.stamp = stamp
    return finishDrop(game, g, model)


registerProp('drop_cancelled', _drop_cancelled,
             {'category': 'sponsors_drop', 'tags': ['drop', 'cancelled'], 'size': [0.84, 1.3, 0.84], 'desc': 'CANCELLED drop: red-knob rubber stamp over a stamped ticket (parts.stamp)'})


# ------------------------------------------------------------------ FULL REEL: 2-inch aluminium quad tape reel
def packTex():
    def draw(ctx, w, h, rand):
        ctx.fillStyle = '#6B4630'
        ctx.fillRect(0, 0, w, h)
        r = 20
        while r < 128:
            ctx.strokeStyle = 'rgba(40,22,12,0.5)' if rand() < 0.5 else 'rgba(190,140,100,0.4)'
            ctx.lineWidth = 0.8 + rand()
            ctx.beginPath()
            ctx.arc(w / 2, h / 2, r, 0, TAU)
            ctx.stroke()
            r += 1.6
    return K.tex.canvas('sp.tapepack', 256, 256, draw, {'repeat': False})


def hubTex():
    def draw(ctx, w, h, rand):
        cx, cy = w / 2, h / 2
        ctx.fillStyle = '#FFC23A'
        ctx.beginPath()
        ctx.arc(cx, cy, 126, 0, TAU)
        ctx.fill()
        ctx.strokeStyle = '#8A5A10'
        ctx.lineWidth = 8
        ctx.stroke()
        ctx.fillStyle = '#FFF4D0'
        ctx.beginPath()
        ctx.arc(cx, cy, 40, 0, TAU)
        ctx.fill()
        text(ctx, 'FULL', cx, cy - 72, {'fam': FONT['sign'], 'px': 34, 'fill': '#5A3A10'})
        text(ctx, 'REEL', cx, cy + 74, {'fam': FONT['sign'], 'px': 34, 'fill': '#5A3A10'})
        text(ctx, '2" QUAD', cx, cy, {'fam': FONT['round'], 'px': 18, 'fill': '#8A5A10'})
    return texC('drop.hub', 256, 256, draw)


def reelFlangeShape(R):
    s = THREE.Shape()
    s.absarc(0, 0, R, 0, TAU, False)
    for i in range(3):
        a0 = (i / 3) * TAU + 0.28
        a1 = a0 + TAU / 3 - 0.56
        r0, r1 = R * 0.36, R * 0.86
        p = THREE.Path()
        p.absarc(0, 0, r1, a0, a1, False)
        p.absarc(0, 0, r0, a1, a0, True)
        p.closePath()
        s.holes.append(p)
    return s


def _drop_full_reel(game, opts=None):
    sh = dropShell(game, 'full_reel')
    g, model = sh['g'], sh['model']
    alu = pm(game, 'metal', '#C9CFD8', {'rough': 0.3, 'map': K.tex.brushed('#D8DDE4'), 'side': THREE.DoubleSide})
    pack = pm(game, 'lacquer', '#ffffff', {'map': packTex(), 'rough': 0.25})
    hubM = pm(game, 'plastic', '#ffffff', {'map': hubTex()})
    R, W = 0.2, 0.09
    reel = THREE.Group()
    reel.userData.noMerge = True
    fl = THREE.ShapeGeometry(reelFlangeShape(R), 10)
    K.uvScale(fl, 3, 3)
    reel.add(K.m(fl, alu, {'pos': [0, 0, -W / 2]}), K.m(fl, alu, {'pos': [0, 0, W / 2]}))
    for z in (-W / 2, W / 2):
        reel.add(K.m(THREE.TorusGeometry(R, 0.007, 5, 40), alu, {'pos': [0, 0, z]}))
    # wound tape pack (concentric-ring caps show through the windows) + hub
    pk = THREE.CylinderGeometry(R * 0.8, R * 0.8, W - 0.012, 40, 1).rotateX(math.pi / 2)
    reel.add(K.m(pk, pack))
    reel.add(K.m(THREE.CylinderGeometry(0.065, 0.065, W + 0.03, 24).rotateX(math.pi / 2), alu))
    for s in (-1, 1):
        lab = THREE.CircleGeometry(0.062, 24)
        if s > 0:
            lab.rotateY(math.pi)
        reel.add(K.m(lab, hubM, {'pos': [0, 0, s * -(W / 2 + 0.0155)]}))
    # loose tape tail with a white leader
    reel.add(K.m(paint(K.tube([[R * 0.8, 0, 0], [R * 0.95, -0.08, 0], [R * 0.9, -0.17, 0.01]], 0.01, {'seg': 10, 'radial': 4}), '#3B2A22'), pm(game, 'plastic', '#ffffff')))
    model.add(reel)
    model.rotation.set(0.15, -0.35, 0)
    g.userData.parts.reel = reel
    return finishDrop(game, g, model)


registerProp('drop_full_reel', _drop_full_reel,
             {'category': 'sponsors_drop', 'tags': ['drop', 'full_reel'], 'size': [0.84, 1.3, 0.84], 'desc': 'FULL REEL drop: spinning 2-inch aluminium quad tape reel (parts.reel spins on z)'})


# ------------------------------------------------------------------ ONE TAKE: clapperboard that keeps clapping
def slateTex():
    def draw(ctx, w, h, rand):
        # slate face (top 384 px)
        ctx.fillStyle = '#26222E'
        ctx.fillRect(0, 0, w, 384)
        ctx.strokeStyle = '#F4F1E8'
        ctx.lineWidth = 5
        rrp(ctx, 14, 14, w - 28, 356, 16)
        ctx.stroke()
        ctx.lineWidth = 4
        for y in (96, 196, 290):
            ctx.beginPath()
            ctx.moveTo(14, y)
            ctx.lineTo(w - 14, y)
            ctx.stroke()
        for x in (180, 346):
            ctx.beginPath()
            ctx.moveTo(x, 196)
            ctx.lineTo(x, 290)
            ctx.stroke()
        text(ctx, 'ONE TAKE', w / 2, 56, {'fam': FONT['groovy'], 'px': 60, 'fill': '#FFD23A', 'stroke': '#E23B3B', 'lw': 8})
        text(ctx, 'PROD.', 60, 124, {'fam': FONT['round'], 'px': 20, 'fill': '#CFC8D8'})
        text(ctx, 'DEAD AIR', w / 2 + 30, 150, {'fam': FONT['sign'], 'px': 44, 'fill': '#F4F1E8'})
        for a, b, x in [['ROLL', '13', 97], ['SCENE', '1', 263], ['TAKE', '1', 428]]:
            text(ctx, a, x, 214, {'fam': FONT['round'], 'px': 18, 'fill': '#CFC8D8'})
            text(ctx, b, x, 256, {'fam': FONT['sign'], 'px': 44, 'fill': '#FFD23A' if b == '1' and a == 'TAKE' else '#F4F1E8'})
        text(ctx, 'WZTV 13 · 1977', w / 2, 330, {'fam': FONT['round'], 'px': 24, 'fill': '#F4F1E8'})
        # clapper stripes (bottom 128 px)
        ctx.fillStyle = '#F4F1E8'
        ctx.fillRect(0, 384, w, 128)
        ctx.fillStyle = '#26222E'
        for i in range(-2, 10):
            ctx.beginPath()
            ctx.moveTo(i * 64, 384)
            ctx.lineTo(i * 64 + 32, 384)
            ctx.lineTo(i * 64 + 72, 512)
            ctx.lineTo(i * 64 + 40, 512)
            ctx.closePath()
            ctx.fill()
    return texC('drop.slate', 512, 512, draw)


def _drop_one_take(game, opts=None):
    sh = dropShell(game, 'one_take')
    g, model = sh['g'], sh['model']
    tx = slateTex()
    slateM = pm(game, 'plastic', '#ffffff', {'map': tx, 'rough': 0.5})
    body = pm(game, 'plastic', '#2A2632', {'rough': 0.45})
    chrome = pm(game, 'chrome', '#98A0AC')
    W, H = 0.4, 0.29
    model.add(K.m(K.box(W, H, 0.03, 0.012), body, {'pos': [0, -0.04, 0]}))
    face = K.uvRect(THREE.PlaneGeometry(W - 0.02, H - 0.02), 0, 0.25, 1, 1).rotateY(math.pi)
    model.add(K.m(face, slateM, {'pos': [0, -0.04, -0.0155]}))

    def stick(y):
        s = uvPlanar(K.box(W + 0.01, 0.055, 0.032, 0.01).clone(), 'x', W / 2 + 0.01, -W / 2 - 0.01, 'y', -0.2, 0.2)
        uv = s.attributes.uv
        for i in range(uv.count):
            uv.setY(i, 0.0 + clamp(uv.getY(i), 0, 1) * 0.25 * (0.99))
        return K.m(s, slateM, {'pos': [0, y, 0]})
    model.add(stick(H / 2 - 0.04 + 0.03))
    # hinged top clapper (parts.clapper: rotate z to open, pivot at the left hinge = +x seen from the front)
    clap = THREE.Group()
    clap.userData.noMerge = True
    clap.position.set(W / 2, H / 2 - 0.04 + 0.09, 0)
    top = stick(0)
    top.position.set(-W / 2, 0, 0)
    clap.add(top)
    clap.rotation.z = -0.3
    model.add(clap)
    model.scale.setScalar(1.02)
    model.position.y = -0.035
    model.add(K.m(K.cyl(0.018, 0.018, 0.05, {'bevel': 0.006, 'seg': 12}), chrome, {'pos': [W / 2, H / 2 - 0.04 + 0.06, -0.025], 'rot': [math.pi / 2, 0, 0]}))
    model.rotation.set(0.1, 0.35, 0.06)
    g.userData.parts.clapper = clap
    return finishDrop(game, g, model)


registerProp('drop_one_take', _drop_one_take,
             {'category': 'sponsors_drop', 'tags': ['drop', 'one_take'], 'size': [0.84, 1.3, 0.84], 'desc': 'ONE TAKE drop: clapperboard, hinged clapper (parts.clapper rotates on z)'})


# ------------------------------------------------------------------ SWEEPS WEEK: little TV with ×2 + ratings meter
def x2Tex():
    def draw(ctx, w, h, rand):
        ctx.fillStyle = lin(ctx, 0, 0, 0, h, ['#FF6FB8', '#D8307E'])
        ctx.fillRect(0, 0, w, h)
        rays(ctx, w / 2, h / 2, 220, 16, 'rgba(255,230,150,0.2)')
        text(ctx, '×2', w / 2, h / 2 - 8, {'fam': FONT['groovy'], 'px': 118, 'fill': lin(ctx, 0, 40, 0, 140, ['#FFF6B0', '#FFC23A', '#E89A1A']), 'stroke': '#5A1440', 'lw': 10, 'depth': 5, 'depthFill': '#5A1440'})
        text(ctx, 'SWEEPS WEEK', w / 2, h - 22, {'fam': FONT['sign'], 'px': 22, 'fill': '#FFFFFF', 'stroke': '#5A1440', 'lw': 4})
    return texC('drop.x2', 256, 192, draw)


def meterTex():
    def draw(ctx, w, h, rand):
        ctx.fillStyle = '#FFF4D8'
        ctx.fillRect(0, 0, w, h)
        cx, cy = w / 2, h - 18
        for i in range(21):
            a, r0 = math.pi + (i / 20) * math.pi, 96 if i % 5 else 86
            ctx.strokeStyle = '#E23B3B' if i > 14 else '#E8A92E' if i > 9 else '#3FA34A'
            ctx.lineWidth = 3 if i % 5 else 5
            ctx.beginPath()
            ctx.moveTo(cx + math.cos(a) * r0, cy + math.sin(a) * r0)
            ctx.lineTo(cx + math.cos(a) * 108, cy + math.sin(a) * 108)
            ctx.stroke()
        ctx.lineWidth = 12
        ctx.strokeStyle = 'rgba(226,59,59,0.85)'
        ctx.beginPath()
        ctx.arc(cx, cy, 116, math.pi * 1.72, math.pi * 2)
        ctx.stroke()
        text(ctx, 'RATINGS', cx, cy - 40, {'fam': FONT['sign'], 'px': 22, 'fill': '#2A1D3A'})
        text(ctx, '+', 34, 40, {'fam': FONT['sign'], 'px': 26, 'fill': '#E23B3B'})
    return texC('drop.meter', 256, 144, draw)


def _drop_sweeps_week(game, opts=None):
    sh = dropShell(game, 'sweeps_week')
    g, model = sh['g'], sh['model']
    shell = pm(game, 'plastic', '#F6E7C8', {'rough': 0.3})
    trim = pm(game, 'plastic', '#FF4FA0', {'rough': 0.3})
    dark = pm(game, 'plastic', '#2A2230', {'rough': 0.35})
    scr = K.glow(game, '#ffffff', 1.0, {'map': x2Tex()})
    meter = pm(game, 'plastic', '#ffffff', {'map': meterTex(), 'rough': 0.4})
    W, H, D = 0.34, 0.25, 0.22
    model.add(K.m(K.box(W, H, D, 0.048), shell, {'pos': [0, -0.07, 0]}))
    model.add(K.m(K.taper(K.box(W * 0.8, H * 0.78, 0.1, 0.04), {'axis': 'z', 'k': 0.6}), trim, {'pos': [0, -0.07, D / 2 + 0.03]}))
    bez = K.roundRect(0.25, 0.19, 0.045)
    bez.holes.append(THREE.Path(K.roundRect(0.21, 0.155, 0.035).getPoints(8)))
    model.add(K.m(K.extrude(bez, 0.02, {'bevel': 0.006, 'bevelSeg': 1, 'curveSeg': 6}), trim, {'pos': [-0.03, -0.07, -D / 2 - 0.004]}))
    sg = THREE.PlaneGeometry(0.212, 0.157, 6, 5)

    def dome(v):
        v.z = 0.008 * (1 - (v.x / 0.106) ** 2 * 0.5 - (v.y / 0.078) ** 2 * 0.5)
    deform(sg, dome)
    sg.rotateY(math.pi)
    screen = K.m(sg, scr, {'pos': [-0.03, -0.07, -D / 2 - 0.002], 'cast': False})
    screen.userData.noAO = True
    model.add(screen)
    for dy, mm in [[0.04, dark], [-0.03, trim]]:
        model.add(K.m(K.cyl(0.022, 0.024, 0.02, {'bevel': 0.006, 'seg': 14}), mm, {'pos': [0.132, -0.07 + dy, -D / 2 - 0.004], 'rot': [-math.pi / 2, 0, 0]}))
    model.add(K.m(K.box(0.05, 0.03, 0.006, 0.003), dark, {'pos': [0.132, -0.17, -D / 2 - 0.002]}))
    for sx in (-1, 1):
        model.add(K.m(K.cyl(0.018, 0.022, 0.03, {'bevel': 0.006, 'seg': 10}), dark, {'pos': [sx * 0.11, -0.225, 0]}))
    # the ratings meter perched on top (half-dome housing, printed face, red needle = parts.needle)
    hous = THREE.Group()
    hous.position.set(0, -0.07 + H / 2, 0)
    hous.add(K.m(K.extrude(K.roundRect(0.2, 0.12, 0.05), 0.08, {'bevel': 0.012, 'curveSeg': 8}), trim, {'pos': [0, 0.07, 0]}))
    face = THREE.PlaneGeometry(0.17, 0.095).rotateY(math.pi)
    hous.add(K.m(face, meter, {'pos': [0, 0.07, -0.041]}))
    needle = THREE.Group()
    needle.userData.noMerge = True
    needle.position.set(0, 0.03, -0.047)
    needle.add(K.m(paint(K.box(0.006, 0.085, 0.004, 0.002), '#E23B3B'), pm(game, 'plastic', '#ffffff'), {'pos': [0, 0.042, 0]}))
    needle.add(K.m(THREE.CylinderGeometry(0.009, 0.009, 0.008, 10).rotateX(math.pi / 2), dark))
    needle.rotation.z = -0.95
    hous.add(needle)
    model.add(hous)
    model.rotation.set(0.1, -0.35, 0)
    g.userData.parts.needle = needle
    return finishDrop(game, g, model)


registerProp('drop_sweeps_week', _drop_sweeps_week,
             {'category': 'sponsors_drop', 'tags': ['drop', 'sweeps_week'], 'size': [0.84, 1.3, 0.84], 'desc': 'SWEEPS WEEK drop: little TV showing ×2 with a ratings meter on top (parts.needle)'})


# ------------------------------------------------------------------ GAFFER TAPE: roll of silver gaffer tape
def woundTex():
    def draw(ctx, w, h, rand):
        ctx.fillStyle = '#A9B0BA'
        ctx.fillRect(0, 0, w, h)
        r = 60
        while r < 128:
            ctx.strokeStyle = 'rgba(70,76,88,0.35)' if rand() < 0.5 else 'rgba(235,240,246,0.4)'
            ctx.lineWidth = 0.7 + rand()
            ctx.beginPath()
            ctx.arc(w / 2, h / 2, r, 0, TAU)
            ctx.stroke()
            r += 1.4
    return K.tex.canvas('sp.wound', 256, 256, draw, {'repeat': False})


def _drop_gaffer_tape(game, opts=None):
    sh = dropShell(game, 'gaffer_tape')
    g, model = sh['g'], sh['model']
    cloth = pm(game, 'metal', '#ffffff', {'map': K.tex.weave('#B7BEC8', {'pattern': 'plain', 'scale': 3}), 'rough': 0.5, 'env': 0.25})
    side = pm(game, 'metal', '#ffffff', {'map': woundTex(), 'rough': 0.45, 'env': 0.25})
    core = pm(game, 'paint', '#B8915F', {'rim': 0.08})
    R0, R1, W = 0.085, 0.17, 0.11
    roll = THREE.Group()
    roll.userData.noMerge = True
    tread = THREE.CylinderGeometry(R1, R1, W, 44, 1, True)
    K.uvScale(tread, 5, 1)
    roll.add(K.m(tread, cloth))
    for s in (-1, 1):
        face = THREE.RingGeometry(R0 + 0.005, R1, 44, 1).rotateX(s * -math.pi / 2)
        roll.add(K.m(face, side, {'pos': [0, (s * W) / 2, 0]}))
        roll.add(K.m(flatTorus(R1 - 0.004, 0.006, 5, 44), cloth, {'pos': [0, (s * (W - 0.008)) / 2, 0]}))
    coreG = lathe2([[R0 + 0.008, W / 2 + 0.006], [R0, W / 2 + 0.006], [R0, -W / 2 - 0.006], [R0 + 0.008, -W / 2 - 0.006], [R0 + 0.008, W / 2 + 0.006]], {'seg': 32, 'v': False})
    roll.add(K.m(coreG, core))
    # the torn tail curling off the roll
    # local axis = y (the roll is turned so y faces the viewer); world "down" is local +z
    tail = THREE.PlaneGeometry(W - 0.006, 0.2, 6, 10)
    p = tail.attributes.position
    for i in range(p.count):
        col, row = i % 7, i // 7
        s, s1, y = (row / 10) * 0.2, 0.07, p.getX(i)
        if s < s1:
            a = math.pi / 2 + (s1 - s) / R1
            x = math.sin(a) * (R1 + 0.002)
            z = math.cos(a) * (R1 + 0.002)
        else:
            d = s - s1
            x = R1 + 0.002 + d * 0.2 + d * d * 1.2
            z = d
        if row == 10:
            z += 0.014 if col % 2 else -0.004
        p.setXYZ(i, x, y, z)
    tail.computeVertexNormals()
    tailM = pm(game, 'metal', '#ffffff', {'map': K.tex.weave('#B7BEC8', {'pattern': 'plain', 'scale': 3}), 'rough': 0.5, 'env': 0.25, 'side': THREE.DoubleSide})
    roll.add(K.m(tail, tailM))
    roll.rotation.x = math.pi / 2
    model.add(roll)
    model.rotation.set(0.25, -0.5, 0.15)
    g.userData.parts.roll = roll
    return finishDrop(game, g, model)


registerProp('drop_gaffer_tape', _drop_gaffer_tape,
             {'category': 'sponsors_drop', 'tags': ['drop', 'gaffer_tape'], 'size': [0.84, 1.3, 0.84], 'desc': 'GAFFER TAPE drop: roll of silver cloth tape with a torn tail (parts.roll)'})


# ------------------------------------------------------------------ PLEASE STAND BY: tiny space-age TV with the test card
def _drop_please_stand_by(game, opts=None):
    sh = dropShell(game, 'please_stand_by')
    g, model = sh['g'], sh['model']
    shell = pm(game, 'plastic', '#E23B3B', {'rough': 0.24})
    cream = pm(game, 'plastic', '#F6E7C8', {'rough': 0.3})
    dark = pm(game, 'plastic', '#2A2230', {'rough': 0.35})
    chrome = pm(game, 'chrome', '#98A0AC')
    scr = K.glow(game, '#ffffff', 0.78, {'map': getCard('test_card')})
    # Videosphere-style helmet TV: ball body, cream face ring, chain loop on top, pedestal
    R = 0.16
    ball = THREE.SphereGeometry(R, 22, 15)
    model.add(K.m(ball, shell, {'pos': [0, 0, 0]}))
    ringG = K.extrude(K.roundRect(0.23, 0.19, 0.07), 0.05, {'bevel': 0.014, 'curveSeg': 8})
    model.add(K.m(ringG, cream, {'pos': [0, 0, -R + 0.022]}))
    sg = THREE.PlaneGeometry(0.19, 0.143, 8, 6)

    def dome(v):
        v.z = 0.012 * (1 - (v.x / 0.095) ** 2 * 0.5 - (v.y / 0.072) ** 2 * 0.5)
    deform(sg, dome)
    sg.rotateY(math.pi)
    screen = K.m(sg, scr, {'pos': [0, 0, -R - 0.006], 'cast': False})
    screen.userData.noAO = True
    model.add(screen)
    model.add(K.m(K.box(0.2, 0.012, 0.006, 0.003), dark, {'pos': [0, -0.086, -R + 0.003]}))
    model.add(K.m(THREE.TorusGeometry(0.05, 0.009, 6, 20), chrome, {'pos': [0, R + 0.04, 0]}))
    model.add(K.m(K.cyl(0.03, 0.035, 0.03, {'bevel': 0.008, 'seg': 14}), chrome, {'pos': [0, R - 0.02, 0]}))
    model.add(K.m(K.lathe([[0, 0], [0.11, 0], [0.115, 0.012], [0.08, 0.03], [0.045, 0.05], [0.04, 0.07], [0, 0.07]], {'seg': 24, 'round': 0.008, 'steps': 1}), cream, {'pos': [0, -R - 0.06, 0]}))
    for sx in (-1, 1):
        model.add(K.m(K.cyl(0.018, 0.02, 0.018, {'bevel': 0.005, 'seg': 12}), dark, {'pos': [sx * R * 0.72, -0.02, R * 0.62], 'rot': [0, 0, sx * math.pi / 2]}))
    model.rotation.set(0.12, -0.3, 0)
    model.position.y = 0.03
    return finishDrop(game, g, model)


registerProp('drop_please_stand_by', _drop_please_stand_by,
             {'category': 'sponsors_drop', 'tags': ['drop', 'please_stand_by'], 'size': [0.84, 1.3, 0.84], 'desc': 'PLEASE STAND BY drop: tiny red space-age TV showing the test card'})

# animateDrop(drop, t): runtime (Godot powerups.gd / sponsors.gd), see the module docstring.


# =============================================================================================== COSTUMES
# costume_<name> and costume_<name>_gold (Sign-Off reward: gold leaf). Each root holds userData.parts.<slot>
# (head | handL | footL/footR | back | wristL/wristR/neck), every part built around its SLOT ORIGIN with the
# hero convention (+y up, face toward -z, hero's left = -x). The root lays the parts out for the gallery only:
# reparent a part to hero.slots.<slot> and reset its position/rotation (scale by userData.fit when needed).
# userData.fit = { slot:{...} reference sizes }, userData.perk = perkId. No colliders.
GOLD = {'light': '#F4D885', 'mid': '#E2B04A', 'deep': '#B98232', 'rose': '#EBAE72'}


def goldLeafTex():
    def draw(ctx, w, h, rand):
        ctx.fillStyle = '#F6EEDC'
        ctx.fillRect(0, 0, w, h)
        n = 4
        s = w / n
        for y in range(n):
            for x in range(-1, n):
                ox = (y % 2) * s * 0.5
                ctx.fillStyle = _hsl(38 + rand() * 8, 40 + rand() * 20, 84 + rand() * 12)
                ctx.fillRect(x * s + ox, y * s, s, s)
        ctx.strokeStyle = 'rgba(120,80,20,0.35)'
        ctx.lineWidth = 1.4
        for y in range(n + 1):
            ctx.beginPath()
            ctx.moveTo(0, y * s + rand() * 2)
            ctx.lineTo(w, y * s + rand() * 2)
            ctx.stroke()
        for i in range(260):
            ctx.strokeStyle = 'rgba(255,255,255,0.55)' if rand() < 0.5 else 'rgba(140,96,30,0.35)'
            ctx.lineWidth = 0.6 + rand()
            x, y, a, ln = rand() * w, rand() * h, rand() * TAU, 2 + rand() * 9
            ctx.beginPath()
            ctx.moveTo(x, y)
            ctx.lineTo(x + math.cos(a) * ln, y + math.sin(a) * ln)
            ctx.stroke()
    return K.tex.canvas('sp.goldleaf', 256, 256, draw)


# Material provider: normal preset/color, or gold leaf in a tone that keeps the pattern readable.
def cmat(game, gold):
    def M(preset, color, tone='mid', extra=None):
        extra = extra if extra is not None else {}
        if gold:
            o = {'map': extra['goldMap'] if extra.get('goldMap') is not None else goldLeafTex(), 'keepColor': True, 'rough': 0.28}
            o.update(extra.get('goldExtra') or {})
            return K.mat(game, 'brass', GOLD.get(tone) or tone, o)
        return pm(game, preset, color, extra.get('normal') or {})
    return M


def finishCostume(game, g, parts):
    for p in parts.values():
        p.userData.noMerge = True
        if not p.parent:
            g.add(p)
    K.bakeAO(g, {'floor': False, 'height': 0, 'strength': 0.7, 'dist': 0.12})
    for p in parts.values():
        K.merge(p)
    g.userData.parts = parts
    g.userData.colliders = []
    return K.finish(game, g, {'ao': False, 'merge': False, 'cast': 0.08})


def costumeMeta(perk, slot, gold, desc):
    return {'category': 'sponsors_costume', 'tags': ['costume', perk, slot] + (['gold'] if gold else []),
            'desc': ('GOLD LEAF · ' if gold else '') + desc}


# ------------------------------------------------------------------ Wobble-Up: gelatin ring-mold helmet (head)
def buildJellyHelmet(game, gold):
    id = 'costume_jelly_helmet%s' % ('_gold' if gold else '')
    g = K.prop(id)
    jellyM = pm(game, 'plastic', '#E6A21C', {'transparent': True, 'opacity': 0.86, 'rough': 0.08, 'env': 0.3, 'emissive': '#9A5A08', 'emissiveIntensity': 0.5, 'rim': 0.4, 'rimColor': '#FFE7A0', 'rimPower': 2.4}) \
        if gold else pm(game, 'plastic', '#067A30', {'transparent': True, 'opacity': 0.88, 'rough': 0.1, 'env': 0.2, 'emissive': '#046A28', 'emissiveIntensity': 0.6, 'rim': 0.3, 'rimColor': '#6CFFA0', 'rimPower': 2.6})
    M = cmat(game, gold)
    fruitM = M('', '', 'mid') if gold else pm(game, 'lacquer', '#ffffff', {'rough': 0.3})
    creamM = M('ceramic', '#FFF6E6', 'light', {'normal': {'rough': 0.55}})
    head = THREE.Group()

    def cav(y):
        return math.sqrt(max(0, 0.285 ** 2 - (y + 0.2) ** 2))
    prof = [[0, 0.085], [cav(0.05), 0.05], [cav(0.0), 0.0], [cav(-0.05), -0.05], [cav(-0.1), -0.1], [0.285, -0.128], [0.3, -0.13], [0.312, -0.115],
            [0.318, -0.03], [0.285, -0.004], [0.268, 0.012], [0.248, 0.1], [0.205, 0.145], [0.14, 0.168], [0.1, 0.163], [0.084, 0.13], [0, 0.125]]
    hg = lathe2(prof, {'seg': 40, 'round': 0.012, 'steps': 1, 'v': False})

    def flutes(th, y, r):
        if r < cav(y) + 0.02 or y < -0.128:
            return 1
        t, w = smoothstep(y, -0.02, 0.02), smoothstep(r - cav(y), 0.02, 0.04) * (1 - smoothstep(y, 0.13, 0.16))
        return 1 + 0.055 * w * math.cos(th * 10 + math.pi * t)
    radial(hg, flutes)
    head.add(K.m(hg, jellyM, {'name': 'jelly'}))
    # suspended fruit (gold: gold-leaf flakes) in the thick upper tier
    for i in range(7):
        a, rr, y = (i / 7) * TAU + 0.3, 0.2, 0.05 + (i % 2) * 0.03
        geo = THREE.OctahedronGeometry(0.022, 0) if gold else [lambda: paint(THREE.SphereGeometry(0.024, 8, 6), '#D81E3A'), lambda: paint(K.box(0.04, 0.03, 0.035, 0.01), '#FFD84A'), lambda: paint(THREE.SphereGeometry(0.02, 8, 6), '#8A3C9A')][i % 3]()
        head.add(K.m(geo, fruitM, {'pos': [math.sin(a) * rr, y, math.cos(a) * rr], 'rot': [i, a, i * 0.5]}))
    cg = lathe2([[0, 0], [0.105, 0], [0.098, 0.025], [0.07, 0.05], [0.04, 0.072], [0.01, 0.088], [0, 0.09]], {'seg': 32, 'v': False})
    radial(cg, lambda th, y, r: 1 + 0.13 * math.cos(th * 8 + y * 50))
    head.add(K.m(cg, creamM, {'pos': [0, 0.125, 0]}))
    head.add(K.m(THREE.SphereGeometry(0.035, 14, 10) if gold else paint(THREE.SphereGeometry(0.035, 14, 10), '#E0183A'), M('', '', 'rose') if gold else fruitM, {'pos': [0.005, 0.24, 0]}))
    head.add(K.m(K.tube([[0.005, 0.27, 0], [0.02, 0.31, 0.005], [0.045, 0.33, 0.01]], 0.004, {'seg': 6, 'radial': 4}) if gold else paint(K.tube([[0.005, 0.27, 0], [0.02, 0.31, 0.005], [0.045, 0.33, 0.01]], 0.004, {'seg': 6, 'radial': 4}), '#6B8A2A'), M('', '', 'deep') if gold else fruitM))
    head.position.y = 0.14
    g.userData.fit = {'head': {'anchor': 'crown', 'headRadius': 0.25, 'note': 'scale = hairBounds*1.05/0.25; cavity fits a 0.285 m sphere centered 0.2 m below the crown'}}
    g.userData.perk = 'wobble_up'
    g.userData.wobble = 'parts.head: squash y / stretch xz on hits (damped spring)'
    return finishCostume(game, g, {'head': head})


registerProp('costume_jelly_helmet', lambda game, opts=None: buildJellyHelmet(game, False), costumeMeta('wobble_up', 'head', False, 'translucent emerald gelatin ring-mold helmet with fruit, cream and a cherry'))
registerProp('costume_jelly_helmet_gold', lambda game, opts=None: buildJellyHelmet(game, True), costumeMeta('wobble_up', 'head', True, 'honey-gold gelatin helmet with gold-leaf flakes'))


# ------------------------------------------------------------------ Jump Cut: oversized oven mitt (handL)
def quiltTex(gold):
    def draw(ctx, w, h, rand):
        base = '#F2E2BC' if gold else '#F07A28'
        line = 'rgba(130,86,20,0.55)' if gold else 'rgba(150,50,10,0.55)'
        hi = 'rgba(255,255,255,0.5)' if gold else 'rgba(255,200,150,0.45)'
        ctx.fillStyle = base
        ctx.fillRect(0, 0, w, h)
        ctx.lineWidth = 3
        for k in range(-12, 20):
            for dir in (1, -1):
                ctx.strokeStyle = line
                ctx.setLineDash([7, 4])
                ctx.beginPath()
                ctx.moveTo(k * 36, 0)
                ctx.lineTo(k * 36 + dir * h, h)
                ctx.stroke()
                ctx.strokeStyle = hi
                ctx.setLineDash([])
                ctx.lineWidth = 2
                ctx.beginPath()
                ctx.moveTo(k * 36 + 4, 0)
                ctx.lineTo(k * 36 + 4 + dir * h, h)
                ctx.stroke()
                ctx.lineWidth = 3
        ctx.setLineDash([])
        # logo roundel with the lightning bolt
        cx, cy = w * 0.5, h * 0.52
        ctx.beginPath()
        ctx.arc(cx, cy, 62, 0, TAU)
        ctx.fillStyle = '#FFF6DA' if gold else '#F6E7C8'
        ctx.fill()
        ctx.lineWidth = 9
        ctx.strokeStyle = '#A87428' if gold else '#5A3A22'
        ctx.stroke()
        boltP(ctx, cx, cy, 96)
        ctx.fillStyle = '#C8902E' if gold else '#FFD23A'
        ctx.fill()
        ctx.lineWidth = 6
        ctx.lineJoin = 'round'
        ctx.strokeStyle = '#7A5210' if gold else '#4A1E0E'
        ctx.stroke()
    return texC('quilt.%s' % ('g' if gold else 'n'), 256, 384, draw)


def tickingTex(gold):
    def draw(ctx, w, h, rand):
        ctx.fillStyle = '#F6ECD2' if gold else '#F6E7C8'
        ctx.fillRect(0, 0, w, h)
        ctx.fillStyle = '#B98232' if gold else '#C0392B'
        for x in range(0, w, 16):
            ctx.fillRect(x, 0, 5, h)
            ctx.fillRect(x + 8, 0, 2, h)
    return texC('ticking.%s' % ('g' if gold else 'n'), 128, 64, draw, {'repeat': True})


def buildOvenMitt(game, gold):
    id = 'costume_oven_mitt%s' % ('_gold' if gold else '')
    g = K.prop(id)
    M = cmat(game, gold)
    mitt = M('fabric', '#ffffff', 'mid', {'goldMap': quiltTex(True), 'normal': {'map': quiltTex(False), 'rim': 0.3}})
    cuff = M('fabric', '#ffffff', 'light', {'goldMap': tickingTex(True), 'normal': {'map': tickingTex(False), 'rim': 0.3}})
    loopM = M('fabric', '#5A3A22', 'deep')
    hand = THREE.Group()
    # mitten outline in (u = forward, v = up); fingertips down; thumb forward
    pts = [[-0.075, 0.07], [-0.08, -0.12], [-0.07, -0.2], [-0.035, -0.235], [0.02, -0.235], [0.055, -0.205], [0.07, -0.15],
           [0.07, -0.12], [0.1, -0.135], [0.13, -0.11], [0.132, -0.075], [0.105, -0.035], [0.075, -0.005], [0.07, 0.07]]
    sh = K.extrude(pts, 0.12, {'bevel': 0.045, 'round': 0.03, 'curveSeg': 6, 'bevelSeg': 3})
    uvPlanar(sh, 'x', -0.09, 0.14, 'y', -0.25, 0.08)
    sh.rotateY(math.pi / 2)  # shape u -> -z (forward), thickness along x
    hand.add(K.m(sh, mitt))
    # padded ticking-stripe cuff + hanging loop
    cuffG = THREE.CylinderGeometry(1, 1.06, 0.07, 24, 1, True)
    cuffG.scale(0.074, 1, 0.09)
    K.uvScale(cuffG, 4, 1)
    hand.add(K.m(cuffG, cuff, {'pos': [0, 0.085, 0.005]}))
    roll = THREE.TorusGeometry(1, 0.26, 8, 24).rotateX(math.pi / 2)
    roll.scale(0.08, 0.1, 0.097)
    hand.add(K.m(roll, cuff, {'pos': [0, 0.12, 0.005]}))
    hand.add(K.m(THREE.TorusGeometry(0.022, 0.006, 5, 12), loopM, {'pos': [0, 0.155, 0.09], 'rot': [0, math.pi / 2, 0]}))
    hand.position.set(0, 0.3, 0)
    hand.rotation.y = -0.5
    g.userData.fit = {'handL': {'anchor': 'palm center (hand slot)', 'note': 'fingertips toward -y, thumb toward -z; about 2.3x a 0.14 m hand'}}
    g.userData.perk = 'jump_cut'
    return finishCostume(game, g, {'handL': hand})


registerProp('costume_oven_mitt', lambda game, opts=None: buildOvenMitt(game, False), costumeMeta('jump_cut', 'handL', False, 'oversized quilted orange oven mitt with the Jump Cut lightning-bolt logo'))
registerProp('costume_oven_mitt_gold', lambda game, opts=None: buildOvenMitt(game, True), costumeMeta('jump_cut', 'handL', True, 'gold-leaf oven mitt'))


# ------------------------------------------------------------------ Roller Boogie: roller-skate wheel sets (feet)
def buildSkates(game, gold):
    id = 'costume_skates%s' % ('_gold' if gold else '')
    g = K.prop(id)
    M = cmat(game, gold)
    chrome = M('', '', 'light') if gold else pm(game, 'chrome', '#98A0AC')
    plastic = None if gold else pm(game, 'lacquer', '#ffffff', {'rough': 0.3})
    wheelTone = ['rose', 'light', 'mid', 'deep']
    cols = [BAR['red'], BAR['yellow'], BAR['green'], BAR['blue']]
    WR, WY = 0.05, -0.068
    wheel = K.lathe([[0.02, -0.026], [0.042, -0.026], [0.05, -0.016], [0.05, 0.016], [0.042, 0.026], [0.02, 0.026]], {'seg': 12, 'round': 0.007, 'steps': 1})
    hub = THREE.CylinderGeometry(0.02, 0.02, 0.056, 8).rotateZ(math.pi / 2)
    parts = {}
    for side in ('L', 'R'):
        f = THREE.Group()
        wi = 0
        for z in (-0.088, 0.088):
            for x in (-0.066, 0.066):
                f.add(K.m(wheel if gold else paint(wheel, cols[wi]), M('', '', wheelTone[wi]) if gold else plastic, {'pos': [x, WY, z], 'rot': [0, 0, math.pi / 2]}))
                f.add(K.m(hub if gold else paint(hub, '#F4F1E8'), M('', '', 'light') if gold else plastic, {'pos': [x, WY, z]}))
                wi += 1
            f.add(K.m(THREE.CylinderGeometry(0.006, 0.006, 0.17, 6).rotateZ(math.pi / 2), chrome, {'pos': [0, WY, z]}))
            f.add(K.m(K.box(0.05, 0.04, 0.036, 0.01), chrome, {'pos': [0, -0.036, z]}))
        # pink enamel plate (the "grown" chassis), purple heel strap, big pink toe stop
        f.add(K.m(K.box(0.105, 0.02, 0.28, 0.008) if gold else paint(K.box(0.105, 0.02, 0.28, 0.008), '#FF5FA2'), M('', '', 'mid') if gold else plastic, {'pos': [0, -0.01, 0]}))
        cup = THREE.TorusGeometry(0.066, 0.013, 5, 14, math.pi).rotateX(math.pi / 2)
        cup.scale(1.05, 1, 0.8)
        f.add(K.m(cup if gold else paint(cup, '#8A4ADC'), M('', '', 'deep') if gold else plastic, {'pos': [0, 0.014, 0.075]}))
        stop = K.lathe([[0, 0], [0.032, 0], [0.037, 0.009], [0.037, 0.045], [0.029, 0.054], [0, 0.054]], {'seg': 12, 'round': 0.006, 'steps': 1})
        f.add(span(K.m(stop if gold else paint(stop, '#FF4F9A'), M('', '', 'rose') if gold else plastic), [0, -0.02, -0.13], [0, -0.08, -0.168]))
        f.position.set(-0.13 if side == 'L' else 0.13, 0.12, 0)
        parts['foot' + side] = f
        g.add(f)
    g.userData.fit = {'footL': {'anchor': 'shoe sole center, plate top at y=0', 'lift': 0.118, 'note': 'wheels hang 0.118 m below the sole: raise the hero by lift while worn (or accept a little clipping)'}}
    g.userData.perk = 'roller_boogie'
    return finishCostume(game, g, parts)


registerProp('costume_skates', lambda game, opts=None: buildSkates(game, False), costumeMeta('roller_boogie', 'feet', False, 'retro roller-skate wheel sets per foot: 4 colored wheels + pink toe stop'))
registerProp('costume_skates_gold', lambda game, opts=None: buildSkates(game, True), costumeMeta('roller_boogie', 'feet', True, 'gold-leaf roller-skate wheel sets'))


# ------------------------------------------------------------------ Double Vision: giant striped toothbrush (back)
def brushTex(gold):
    def draw(ctx, w, h, rand):
        cols = ['#E8C06A', '#FFF4D6', '#B98232'] if gold else ['#E23B3B', '#F7F3EA', '#2F5BD3']
        P = 256 / 2
        bw = P / 3
        for k in range(-6, 12):
            for b, c in enumerate(cols):
                y = k * P + b * bw
                ctx.beginPath()
                ctx.moveTo(0, y)
                ctx.lineTo(w, y + w * 0.9)
                ctx.lineTo(w, y + w * 0.9 + bw + 0.8)
                ctx.lineTo(0, y + bw + 0.8)
                ctx.closePath()
                ctx.fillStyle = c
                ctx.fill()
    return texC('brush.%s' % ('g' if gold else 'n'), 256, 512, draw, {'repeat': True})


def buildToothbrush(game, gold):
    id = 'costume_toothbrush%s' % ('_gold' if gold else '')
    g = K.prop(id)
    M = cmat(game, gold)
    handleM = M('plastic', '#ffffff', 'mid', {'goldMap': brushTex(True), 'normal': {'map': brushTex(False), 'rough': 0.25}})
    headM = M('plastic', '#F7F3EA', 'light', {'normal': {'rough': 0.25}})
    bristleM = M('', '', 'light') if gold else pm(game, 'plastic', '#ffffff', {'rough': 0.45})
    leather = M('vinyl', '#7A4A2A', 'deep', {'normal': {'map': K.tex.pebble('#7A4A2A')}})
    brass = M('', '', 'light') if gold else pm(game, 'brass', '#C8963C')
    back = THREE.Group()
    # handle along +y (grip bulge, thinner neck), bristle head at the top
    rings = []
    L = 0.66
    for i in range(17):
        t = i / 16
        grip = 1 + 0.28 * math.sin(math.pi * clamp(t / 0.7, 0, 1)) - 0.25 * smoothstep(t, 0.7, 0.95)
        rings.append([0.038 * grip, 0.021 * grip, -L / 2 + t * L, 3])
    hg = loft(rings, 20)
    K.uvScale(hg, 1, 2.2)
    back.add(K.m(hg, handleM))
    back.add(K.m(THREE.SphereGeometry(1, 16, 10).scale(0.038, 0.03, 0.021), handleM, {'pos': [0, -L / 2, 0]}))
    # head: rounded paddle + bristle tufts facing outward (+z, away from the hero's back)
    headY = L / 2 + 0.09
    back.add(K.m(K.box(0.075, 0.2, 0.035, 0.016), headM, {'pos': [0, headY, 0]}))
    tuft = THREE.CylinderGeometry(0.009, 0.0095, 0.07, 6).rotateX(math.pi / 2)
    for r in range(7):
        for c in range(3):
            geo = tuft if gold else paint(tuft, '#5FE3FF' if r % 3 == 1 else '#FFFFFF')
            back.add(K.m(geo, bristleM, {'pos': [(c - 1) * 0.022, headY - 0.078 + r * 0.026, 0.05 + (r % 2) * 0.004]}))
    # leather holster: back plate + two strap loops around the handle, brass rivets
    patch = K.extrude(K.roundRect(0.13, 0.36, 0.06), 0.02, {'bevel': 0.007, 'curveSeg': 6})
    back.add(K.m(patch, leather, {'pos': [0, -0.02, -0.036]}))
    for y in (-0.15, 0.11):
        band = THREE.TorusGeometry(1, 0.34, 5, 18).rotateX(math.pi / 2)
        band.scale(0.047, 0.045, 0.03)
        back.add(K.m(band, leather, {'pos': [0, y, -0.006]}))
        for sx in (-1, 1):
            back.add(K.m(THREE.SphereGeometry(0.008, 8, 6), brass, {'pos': [sx * 0.05, y, -0.028]}))
    # the slot-space pose lives on an inner group (bristles over the hero's LEFT shoulder = -x, 0.05 m behind the slot);
    # the part itself only carries the gallery transform (turned to show its outside), which the game resets
    brush = THREE.Group()
    brush.add(*list(back.children))
    brush.rotation.z = 0.62
    brush.position.z = 0.05
    back.add(brush)
    back.position.set(0, 0.55, 0)
    back.rotation.y = math.pi
    g.userData.fit = {'back': {'anchor': 'back slot (chest back surface)', 'note': 'diagonal, bristles over the left shoulder, handle toward the right hip, sits 0.05 m behind the slot'}}
    g.userData.perk = 'double_vision'
    return finishCostume(game, g, {'back': back})


registerProp('costume_toothbrush', lambda game, opts=None: buildToothbrush(game, False), costumeMeta('double_vision', 'back', False, 'giant red-white-blue striped toothbrush holstered diagonally on the back'))
registerProp('costume_toothbrush_gold', lambda game, opts=None: buildToothbrush(game, True), costumeMeta('double_vision', 'back', True, 'gold-leaf toothbrush'))


# ------------------------------------------------------------------ Replay-Ade: terry wristbands + whistle lanyard
def terryTex(gold):
    def draw(ctx, w, h, rand):
        base, stripe = ('#F4E2B0', '#B98232') if gold else ('#F4C81E', '#2F5BD3')
        ctx.fillStyle = base
        ctx.fillRect(0, 0, w, h)
        ctx.fillStyle = stripe
        ctx.fillRect(0, h * 0.28, w, h * 0.12)
        ctx.fillRect(0, h * 0.6, w, h * 0.12)
        for i in range(3200):
            ctx.fillStyle = 'rgba(255,255,255,0.25)' if rand() < 0.5 else 'rgba(80,50,0,0.18)'
            ctx.beginPath()
            ctx.arc(rand() * w, rand() * h, 0.8 + rand() * 1.3, 0, TAU)
            ctx.fill()
    return K.tex.canvas('sp.terry.%s' % ('g' if gold else 'n'), 256, 128, draw)


def buildWristbands(game, gold):
    id = 'costume_wristbands%s' % ('_gold' if gold else '')
    g = K.prop(id)
    M = cmat(game, gold)
    terry = M('fabric', '#ffffff', 'mid', {'goldMap': terryTex(True), 'normal': {'map': terryTex(False), 'rim': 0.4}})
    cord = M('fabric', '#F4C81E', 'light', {'normal': {'rim': 0.3}})
    chrome = M('', '', 'light') if gold else pm(game, 'chrome', '#A8B0BA')
    parts = {}
    band = lathe2([[0.058, -0.04], [0.07, -0.042], [0.077, -0.032], [0.079, 0], [0.077, 0.032], [0.07, 0.042], [0.058, 0.04], [0.056, 0], [0.058, -0.04]], {'seg': 24, 'round': 0.008, 'steps': 1})
    K.uvScale(band, 3, 1)
    for side in ('L', 'R'):
        w = THREE.Group()
        w.add(K.m(band, terry))
        w.position.set(-0.2 if side == 'L' else 0.2, 0.06, 0.1)
        parts['wrist' + side] = w
        g.add(w)
    # lanyard: loop around the neck, V down to the whistle on the chest
    neck = THREE.Group()
    pts = [[0, -0.155, -0.13], [-0.05, -0.08, -0.12], [-0.085, 0.0, -0.06], [-0.085, 0.02, 0.02], [-0.04, 0.025, 0.075], [0.04, 0.025, 0.075], [0.085, 0.02, 0.02], [0.085, 0.0, -0.06], [0.05, -0.08, -0.12]]
    neck.add(K.m(K.tube(pts, 0.007, {'seg': 40, 'radial': 5, 'closed': True}), cord))
    wh = THREE.Group()
    wh.position.set(0, -0.19, -0.14)
    wh.add(K.m(THREE.TorusGeometry(0.012, 0.0035, 5, 12), chrome, {'pos': [0, 0.03, 0]}))
    wh.add(K.m(THREE.CylinderGeometry(0.024, 0.024, 0.042, 16).rotateZ(math.pi / 2), chrome, {'pos': [0, 0, 0]}))
    wh.add(K.m(K.box(0.042, 0.014, 0.04, 0.005), chrome, {'pos': [0, 0.018, -0.02]}))
    wh.add(K.m(K.box(0.036, 0.012, 0.035, 0.005), chrome, {'pos': [0, 0.02, -0.055]}))
    wh.add(K.m(K.box(0.014, 0.012, 0.004, 0.002), pm(game, 'plastic', '#2A2230'), {'pos': [0, 0.02, -0.0735]}))
    wh.rotation.set(-0.3, 0.3, 0)
    neck.add(wh)
    neck.position.set(0, 0.34, 0)
    parts['neck'] = neck
    g.add(neck)
    g.userData.fit = {'wristL': {'anchor': 'wrist slot', 'innerRadius': 0.056}, 'neck': {'anchor': 'neck slot', 'loopRadius': 0.085, 'note': 'whistle hangs on the chest ~0.19 m below, 0.14 m forward'}}
    g.userData.perk = 'replay_ade'
    return finishCostume(game, g, parts)


registerProp('costume_wristbands', lambda game, opts=None: buildWristbands(game, False), costumeMeta('replay_ade', 'wrists+neck', False, 'yellow/blue terry wristbands (L+R) + chrome referee whistle on a yellow lanyard'))
registerProp('costume_wristbands_gold', lambda game, opts=None: buildWristbands(game, True), costumeMeta('replay_ade', 'wrists+neck', True, 'gold-leaf wristbands + whistle'))

# @@PART3@@
