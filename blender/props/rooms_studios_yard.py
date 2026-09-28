"""DEAD AIR — props registered by the Transmitter Yard room (src/world/rooms/yard.js, category 'rooms_yard').
Owner: rooms-studios_yard. Port of the registerProp() builders at the top of yard.js, line by line (same ids, same
opts, same numbers; see blender/README.md kit guide):

    yard_cone           traffic cone with reflective bands
    yard_lawn_chair     70s webbed aluminum lawn chair (opts.colors)
    yard_cooler         red steel-belted picnic cooler
    yard_wallpack       WALL: caged sodium wall-pack light (parts.lens; opts.color / intensity / distance)
    yard_service_panel  WALL: electrical service panel, meter socket and conduits (origin at the wall foot)
    yard_utility_pole   wooden utility pole with crossarm and glass insulators (userData.wires = attach points;
                        opts.height, opts.transformer)
    yard_sign           fence sign (opts.kind trespass|danger|wztv|gate, opts.w); origin at its center, face -z

The canvas textures signTex(kind) / apronTex() of yard.js live here too (the room's runtime meshes, built by
blender/runtime/rooms_studios_yard.py, reuse apronTex()).
The rest of yard.js (placement, the tower beacons, neon, SkyCam, radio toy, critters) is runtime code:
godot/scripts/world/rooms/yard.gd.
"""
import math

from dalib import kit as K
from dalib.kit import registerProp, PAL, THREE

TAU = math.pi * 2
PI = math.pi
CAT = 'rooms_yard'


# ------------------------------------------------------------------------------------------ local helpers
def tm(geo, mat, color=None, o=None):
    return K.m(K.tint(geo.clone(), color) if color else geo, mat, o)


def hexMul(hex_, k):
    return '#' + THREE.Color(hex_).multiplyScalar(k).getHexString()


def glowPart(o):
    o.userData.noMerge = True
    o.userData.noAO = True
    o.userData.noOcclude = True
    o.userData.noShadow = True
    return o


def signTex(kind):
    def draw(ctx, w, h, rand):
        ctx.textAlign = 'center'
        ctx.textBaseline = 'middle'

        def round_(x, y, ww, hh, r):
            ctx.beginPath()
            ctx.roundRect(x, y, ww, hh, r)

        def font(s, f='Bungee'):
            ctx.font = '%spx "%s", "Arial Black", sans-serif' % (_num(s), f)

        def fit(t, max_, s, f='Bungee'):
            font(s, f)
            while ctx.measureText(t).width > max_ and s > 6:
                s *= 0.93
                font(s, f)

        if kind == 'danger':
            ctx.fillStyle = '#F4F1E8'; round_(2, 2, w - 4, h - 4, 14); ctx.fill()
            ctx.fillStyle = '#1E1530'; round_(10, 10, w - 20, 50, 8); ctx.fill()
            ctx.fillStyle = '#E23B3B'; ctx.beginPath(); ctx.ellipse(w / 2, 35, 96, 20, 0, 0, TAU); ctx.fill()
            ctx.fillStyle = '#F4F1E8'; fit('DANGER', 170, 34); ctx.fillText('DANGER', w / 2, 37)
            ctx.fillStyle = '#1E1530'; fit('HIGH VOLTAGE', 220, 30); ctx.fillText('HIGH VOLTAGE', w / 2, 90)
            fit('KEEP OUT · RF RADIATION', 220, 16, 'Titan One'); ctx.fillText('KEEP OUT · RF RADIATION', w / 2, 128)
        elif kind == 'wztv':
            ctx.fillStyle = '#2F5BD3'; round_(2, 2, w - 4, h - 4, 14); ctx.fill()
            ctx.fillStyle = '#F4F1E8'; ctx.beginPath(); ctx.arc(58, 80, 44, 0, TAU); ctx.fill()
            ctx.fillStyle = '#E23B3B'; ctx.beginPath(); ctx.arc(58, 80, 37, 0, TAU); ctx.fill()
            ctx.fillStyle = '#F4F1E8'; font(40, 'Titan One'); ctx.fillText('13', 58, 84)
            ctx.fillStyle = '#FFD23A'; fit('WZTV', 130, 42); ctx.fillText('WZTV', 172, 62)
            ctx.fillStyle = '#F4F1E8'; fit('TRANSMITTER SITE', 136, 17, 'Titan One'); ctx.fillText('TRANSMITTER SITE', 172, 102)
            fit('AUTHORIZED ONLY', 130, 13, 'Titan One'); ctx.fillText('AUTHORIZED ONLY', 172, 126)
        elif kind == 'gate':
            ctx.fillStyle = '#F2C230'; round_(2, 2, w - 4, h - 4, 14); ctx.fill()
            ctx.strokeStyle = '#2A1D2A'; ctx.lineWidth = 6; round_(10, 10, w - 20, h - 20, 8); ctx.stroke()
            ctx.fillStyle = '#2A1D2A'; fit('KEEP GATE', 200, 34); ctx.fillText('KEEP GATE', w / 2, 56)
            fit('CLOSED', 200, 44); ctx.fillText('CLOSED', w / 2, 106)
        else:
            ctx.fillStyle = '#F4F1E8'; round_(2, 2, w - 4, h - 4, 14); ctx.fill()
            ctx.fillStyle = '#C8201E'; round_(8, 8, w - 16, 50, 8); ctx.fill()
            ctx.fillStyle = '#F4F1E8'; fit('NO TRESPASSING', 220, 28); ctx.fillText('NO TRESPASSING', w / 2, 34)
            ctx.fillStyle = '#2A1D2A'; fit('WZTV PROPERTY', 220, 28, 'Titan One'); ctx.fillText('WZTV PROPERTY', w / 2, 92)
            fit('VIOLATORS WILL BE PROSECUTED', 220, 13, 'Titan One'); ctx.fillText('VIOLATORS WILL BE PROSECUTED', w / 2, 128)
        ctx.globalAlpha = 0.12
        ctx.fillStyle = '#7A4A2A'
        for i in range(14):
            ctx.beginPath(); ctx.arc(rand() * w, rand() * h, 2 + rand() * 9, 0, TAU); ctx.fill()
        ctx.globalAlpha = 1
    return K.tex.canvas('yard_sign|%s' % kind, 256, 160, draw, {'repeat': False, 'fonts': True})


def _num(s):
    """JS number -> string in a CSS font ('34px', '31.62px')."""
    from dalib.mathutils3 import js_str
    return js_str(s)


def apronTex():
    def draw(ctx, w, h, rand):
        ctx.fillStyle = '#A9A39C'; ctx.fillRect(0, 0, w, h)
        for i in range(2200):
            ctx.globalAlpha = 0.06 + rand() * 0.12
            ctx.fillStyle = '#7E7870' if rand() < 0.5 else '#D2CCC2'
            ctx.fillRect(rand() * w, rand() * h, 1.5 + rand() * 2, 1.5 + rand() * 2)
        ctx.globalAlpha = 0.25; ctx.strokeStyle = '#6E6860'; ctx.lineWidth = 3
        ctx.beginPath(); ctx.moveTo(0, h / 2); ctx.lineTo(w, h / 2); ctx.stroke()
        ctx.globalAlpha = 1
        # yellow/black hazard band on the yard edge (+u = +x) and the KEEP CLEAR stencil
        bw = 34
        ctx.save(); ctx.beginPath(); ctx.rect(w - bw, 0, bw, h); ctx.clip()
        ctx.fillStyle = '#F2C230'; ctx.fillRect(w - bw, 0, bw, h)
        ctx.fillStyle = '#2A1D2A'
        y = -40
        while y < h + 40:
            ctx.beginPath(); ctx.moveTo(w - bw, y); ctx.lineTo(w, y + 22); ctx.lineTo(w, y + 44); ctx.lineTo(w - bw, y + 22); ctx.fill()
            y += 44
        ctx.restore()
        ctx.save(); ctx.translate(w * 0.52, h / 2); ctx.rotate(-PI / 2)
        ctx.fillStyle = 'rgba(242,194,48,0.85)'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle'
        ctx.font = '64px "Bungee", "Arial Black", sans-serif'; ctx.fillText('KEEP', 0, -40)
        ctx.fillText('CLEAR', 0, 36)
        ctx.restore()
        for i in range(40):
            ctx.globalAlpha = 0.05 + rand() * 0.08
            ctx.fillStyle = '#4A443E'
            ctx.beginPath(); ctx.ellipse(rand() * w, rand() * h, 4 + rand() * 18, 2 + rand() * 8, rand() * 3, 0, TAU); ctx.fill()
        ctx.globalAlpha = 1
    return K.tex.canvas('yard_apron', 256, 512, draw, {'repeat': False, 'fonts': True})


# ------------------------------------------------------------------------------------------ local props
# Registered once (module load) in the shared prop registry under 'yard_*' ids so placeProp wires colliders,
# light anchors and cloning. Conventions as PROPKIT: floor at y = 0, front faces -z; 'wall' props have their origin
# on the wall and extend toward -z.

def _yard_cone(game, opts=None):
    g = K.prop('yard_cone')
    pl = K.mat(game, 'plastic', '#ffffff', {'rough': 0.45})
    g.add(tm(K.box(0.42, 0.05, 0.42, 0.02), pl, '#B8481E', {'pos': [0, 0.025, 0]}))

    def r(y):
        return 0.15 - (0.108 / 0.6) * y
    g.add(tm(K.lathe([[0.155, 0], [0.15, 0.02], [0.042, 0.6], [0.028, 0.64], [0, 0.645]], {'seg': 16, 'round': 0.012}), pl, PAL.burntOrange, {'pos': [0, 0.045, 0]}))
    for a, b in [[0.22, 0.31], [0.38, 0.44]]:
        g.add(tm(K.lathe([[r(a) + 0.005, a], [r(b) + 0.005, b]], {'seg': 16}), pl, '#F4F1E8', {'pos': [0, 0.045, 0]}))
    g.userData.colliders = [{'min': [-0.18, 0, -0.18], 'max': [0.18, 0.68, 0.18]}]
    return K.finish(game, g, {'ao': {'res': 24}})


registerProp('yard_cone', _yard_cone, {'category': CAT, 'tags': ['yard', 'clutter'], 'size': [0.42, 0.69, 0.42],
                                       'desc': 'traffic cone with reflective bands'})


def _yard_lawn_chair(game, opts=None):
    opts = opts or {}
    g = K.prop('yard_lawn_chair')
    alu = K.mat(game, 'chrome', '#B8C0CA')
    web = K.mat(game, 'plastic', '#ffffff', {'rough': 0.55})
    cols = opts.get('colors') if opts.get('colors') is not None else [PAL.burntOrange, '#F4F1E8', PAL.harvestGold, PAL.avocado]
    W, SY, SD = 0.56, 0.36, 0.44
    hw = W / 2

    def T(pts, r=0.013):
        g.add(K.m(K.tube(pts, r, {'seg': max(8, len(pts) * 6), 'radial': 6}), alu))
    # seat frame, back frame, arms, legs
    T([[-hw, SY, -SD / 2], [hw, SY, -SD / 2]])
    T([[-hw, SY, SD / 2], [hw, SY, SD / 2]])
    for s in [-1, 1]:
        T([[s * hw, SY, -SD / 2], [s * hw, SY, SD / 2]])
        T([[s * hw, SY, SD / 2], [s * hw, 0.62, SD / 2 + 0.1], [s * hw, 0.9, SD / 2 + 0.2]])
        T([[s * hw, 0.02, -SD / 2 - 0.04], [s * hw, 0.3, -SD / 2 + 0.02], [s * hw, 0.56, -SD / 2 + 0.02]])
        T([[s * hw, 0.02, SD / 2 + 0.06], [s * hw, SY, SD / 2 - 0.02]])
        g.add(tm(K.box(0.07, 0.03, SD + 0.1, 0.012), web, '#F4F1E8', {'pos': [s * (hw + 0.005), 0.575, 0.02]}))
    T([[-hw, 0.9, SD / 2 + 0.2], [hw, 0.9, SD / 2 + 0.2]])
    T([[-hw, 0.02, -SD / 2 - 0.04], [hw, 0.02, -SD / 2 - 0.04]], 0.011)
    # woven webbing: seat
    for i in range(5):
        z = -SD / 2 + 0.05 + i * ((SD - 0.1) / 4)
        g.add(tm(K.box(W, 0.012, 0.062, 0.005), web, cols[i % len(cols)], {'pos': [0, SY + 0.004 + (i % 2) * 0.004, z]}))
    for i in range(4):
        x = -hw + 0.09 + i * ((W - 0.18) / 3)
        g.add(tm(K.box(0.058, 0.012, SD, 0.005), web, cols[(i + 1) % len(cols)], {'pos': [x, SY + 0.006, 0]}))
    # woven webbing: back (reclined plane)
    back = THREE.Group()
    back.position.set(0, SY + 0.02, SD / 2 + 0.01)
    back.rotation.x = -0.36
    for i in range(5):
        back.add(tm(K.box(W, 0.062, 0.012, 0.005), web, cols[(i + 2) % len(cols)], {'pos': [0, 0.07 + i * 0.105, (i % 2) * 0.004]}))
    for i in range(4):
        back.add(tm(K.box(0.058, 0.52, 0.012, 0.005), web, cols[(i + 3) % len(cols)], {'pos': [-hw + 0.09 + i * ((W - 0.18) / 3), 0.28, 0.003]}))
    g.add(back)
    g.userData.colliders = [{'min': [-hw - 0.05, 0, -SD / 2 - 0.08], 'max': [hw + 0.05, 0.9, SD / 2 + 0.22]}]
    return K.finish(game, g, {'ao': {'res': 36}})


registerProp('yard_lawn_chair', _yard_lawn_chair, {'category': CAT, 'tags': ['yard', 'seat', 'clutter'],
                                                   'size': [0.66, 0.92, 0.75], 'desc': '70s webbed aluminum lawn chair'})


def _yard_cooler(game, opts=None):
    g = K.prop('yard_cooler')
    pl = K.mat(game, 'plastic', '#ffffff', {'rough': 0.4})
    chrome = K.mat(game, 'chrome', '#A8B0BA')
    g.add(tm(K.box(0.62, 0.34, 0.38, 0.05), pl, '#C8342A', {'pos': [0, 0.19, 0]}))
    g.add(tm(K.box(0.64, 0.06, 0.4, 0.03), pl, '#F4F1E8', {'pos': [0, 0.035, 0]}))
    g.add(tm(K.box(0.64, 0.085, 0.4, 0.035), pl, '#F4F1E8', {'pos': [0, 0.4, 0]}))
    g.add(tm(K.box(0.5, 0.05, 0.012, 0.006), pl, '#F4F1E8', {'pos': [0, 0.2, -0.193]}))
    g.add(K.m(K.tube([[-0.24, 0.43, 0], [-0.24, 0.5, 0], [0.24, 0.5, 0], [0.24, 0.43, 0]], 0.012, {'seg': 16, 'radial': 6}), chrome))
    for s in [-1, 1]:
        g.add(K.m(K.box(0.03, 0.06, 0.12, 0.01), chrome, {'pos': [s * 0.315, 0.3, 0]}))
    g.add(K.m(K.box(0.07, 0.05, 0.02, 0.008), chrome, {'pos': [0, 0.36, -0.2]}))
    return K.finish(game, g, {'ao': {'res': 30}})


registerProp('yard_cooler', _yard_cooler, {'category': CAT, 'tags': ['yard', 'clutter'], 'size': [0.64, 0.5, 0.4],
                                           'desc': 'red steel-belted picnic cooler'})


def _yard_wallpack(game, opts=None):
    opts = opts or {}
    g = K.prop('yard_wallpack')
    body = K.mat(game, 'metal', '#5A4E48', {'rough': 0.5})
    galv = K.mat(game, 'metal', '#A8B0BA', {'rough': 0.45})
    color = opts.get('color') if opts.get('color') is not None else PAL.sodium
    g.add(K.m(K.box(0.36, 0.3, 0.05, 0.015), body, {'pos': [0, 0.15, -0.025]}))
    g.add(K.m(K.taper(K.box(0.34, 0.22, 0.24, 0.035), {'axis': 'z', 'k': 0.8}), body, {'pos': [0, 0.2, -0.16]}))
    g.add(K.m(K.box(0.4, 0.035, 0.3, 0.012), body, {'pos': [0, 0.32, -0.16], 'rot': [-0.16, 0, 0]}))
    lens = glowPart(K.m(K.box(0.28, 0.1, 0.18, 0.02), K.glow(game, color, 2.4), {'pos': [0, 0.085, -0.18], 'name': 'lens'}))
    g.add(lens)
    for k in range(3):
        x = (k - 1) * 0.1
        pts = []
        for s in range(7):
            a = (s / 6) * PI
            pts.append([x, 0.09 - math.sin(a) * 0.07, -0.08 - (1 - math.cos(a)) * 0.1])
        g.add(K.m(K.tube(pts, 0.006, {'seg': 10, 'radial': 4}), galv))
    g.add(K.m(K.tube([[0.12, 0.05, -0.02], [0.14, -0.2, -0.03], [0.14, -1.2, -0.03]], 0.018, {'seg': 10, 'radial': 6}), galv))
    g.userData.parts = {'lens': lens}
    g.userData.lightAnchors = [{'pos': [0, -0.15, -0.55], 'color': color,
                                'intensity': opts.get('intensity') if opts.get('intensity') is not None else 2.2,
                                'distance': opts.get('distance') if opts.get('distance') is not None else 7,
                                'flicker': 0.02}]
    g.userData.colliders = []
    return K.finish(game, g, {'ao': {'res': 30, 'height': 0}})


registerProp('yard_wallpack', _yard_wallpack, {'category': CAT, 'tags': ['yard', 'light', 'wall'],
                                               'size': [0.4, 0.36, 0.34],
                                               'desc': 'WALL: caged sodium wall-pack light (parts.lens)'})


def _yard_service_panel(game, opts=None):
    g = K.prop('yard_service_panel')
    grey = K.mat(game, 'metal', '#8E959E', {'rough': 0.5})
    galv = K.mat(game, 'metal', '#A8B0BA', {'rough': 0.45})
    label = K.mat(game, 'paint', '#ffffff', {'map': signTex('danger')})
    Y0, PW, PH, PD = 1.25, 0.72, 0.95, 0.22
    g.add(K.m(K.box(PW, PH, PD, 0.03), grey, {'pos': [0, Y0 + PH / 2, -PD / 2]}))
    g.add(K.m(K.box(PW - 0.08, PH - 0.08, 0.02, 0.008), grey, {'pos': [0, Y0 + PH / 2, -PD - 0.005]}))
    g.add(K.m(K.box(0.03, 0.14, 0.03, 0.01), galv, {'pos': [0.26, Y0 + 0.45, -PD - 0.03]}))
    lp = THREE.PlaneGeometry(0.34, 0.21).rotateY(PI)
    g.add(K.m(lp, label, {'pos': [-0.05, Y0 + 0.66, -PD - 0.018]}))
    # meter socket beside it
    g.add(K.m(K.box(0.26, 0.4, 0.14, 0.02), grey, {'pos': [-0.56, Y0 + 0.2, -0.07]}))
    g.add(tm(K.cyl(0.085, 0.09, 0.08, {'seg': 16, 'bevel': 0.01}).clone().rotateX(-PI / 2), galv, '#E8EEF2', {'pos': [-0.56, Y0 + 0.24, -0.14]}))
    # conduits: three up to the coping, one down into the gravel, one across toward the door frame
    for x, top in [[-0.22, 4.35], [0, 4.35], [0.22, 4.35]]:
        g.add(K.m(K.tube([[x, Y0 + PH, -0.1], [x, Y0 + PH + 0.25, -0.07], [x, top, -0.07]], 0.028, {'seg': 8, 'radial': 6}), galv))
        y = Y0 + PH + 0.5
        while y < top:
            g.add(K.m(K.box(0.09, 0.04, 0.05, 0.01), galv, {'pos': [x, y, -0.05]}))
            y += 0.9
    g.add(K.m(K.tube([[-0.56, Y0, -0.07], [-0.56, 0.2, -0.07], [-0.56, -0.1, -0.2]], 0.03, {'seg': 8, 'radial': 6}), galv))
    g.add(K.m(K.tube([[0.3, Y0 + 0.2, -0.1], [0.7, Y0 + 0.2, -0.07], [2.2, Y0 + 0.2, -0.07]], 0.022, {'seg': 10, 'radial': 6}), galv))
    g.userData.colliders = [{'min': [-0.72, 0, -0.18], 'max': [-0.4, Y0 + 0.4, 0]}]
    return K.finish(game, g, {'ao': {'res': 40, 'height': 0}})


registerProp('yard_service_panel', _yard_service_panel, {
    'category': CAT, 'tags': ['yard', 'wall'], 'size': [1.5, 4.4, 0.25],
    'desc': 'WALL: electrical service panel, meter socket and conduits (origin at the wall foot)'})


def _yard_utility_pole(game, opts=None):
    opts = opts or {}
    g = K.prop('yard_utility_pole')
    wood = K.mat(game, 'teak', '#ffffff', {'map': K.tex.wood('#6E5238', {'dark': 0.45, 'wear': 0.3})})
    galv = K.mat(game, 'metal', '#8A9098', {'rough': 0.5})
    glass = K.mat(game, 'crt', '#5FA88A', {'rough': 0.12, 'rim': 0.6, 'rimColor': '#9FFFD0'})
    H = opts.get('height') if opts.get('height') is not None else 9.2
    AY = H - 0.55
    g.add(K.m(K.cyl(0.12, 0.16, H, {'seg': 12, 'bevel': 0.03}), wood))
    g.add(K.m(K.box(2.3, 0.12, 0.13, 0.02, {'uv': 1.2, 'swap': True}), wood, {'pos': [0, AY, 0]}))
    for s in [-1, 1]:
        g.add(K.m(K.tube([[s * 0.8, AY - 0.05, 0.08], [0, AY - 0.8, 0.13]], 0.02, {'seg': 4, 'radial': 4}), galv))
    for x in [-1.0, -0.35, 1.0]:
        g.add(K.m(K.cyl(0.012, 0.012, 0.1, {'seg': 6}), galv, {'pos': [x, AY + 0.06, 0]}))
        g.add(K.m(K.lathe([[0, 0], [0.05, 0], [0.055, 0.03], [0.035, 0.05], [0.042, 0.08], [0.02, 0.12], [0, 0.125]], {'seg': 10}), glass, {'pos': [x, AY + 0.1, 0]}))
    if opts.get('transformer'):
        g.add(tm(K.cyl(0.24, 0.24, 0.62, {'seg': 16, 'bevel': 0.03}), galv, '#9AA2AC', {'pos': [0.3, AY - 1.5, 0]}))
        g.add(tm(K.cyl(0.26, 0.2, 0.08, {'seg': 16, 'bevel': 0.02}), galv, '#9AA2AC', {'pos': [0.3, AY - 0.88, 0]}))
        g.add(K.m(K.box(0.08, 0.3, 0.08, 0.01), galv, {'pos': [0.08, AY - 1.2, 0]}))
    y = 2.4
    while y < AY - 0.6:
        g.add(K.m(K.cyl(0.012, 0.012, 0.2, {'seg': 5}).clone().rotateZ(PI / 2), galv, {'pos': [0.12 if math.fmod(y * 7, 2) > 1 else -0.12, y, 0]}))
        y += 0.45
    g.userData.colliders = []
    g.userData.wires = [[-1.0, AY + 0.2, 0], [-0.35, AY + 0.2, 0], [1.0, AY + 0.2, 0]]
    return K.finish(game, g, {'ao': False})


registerProp('yard_utility_pole', _yard_utility_pole, {
    'category': CAT, 'tags': ['yard', 'backdrop'], 'size': [2.3, 9.3, 0.3],
    'desc': 'wooden utility pole with crossarm and glass insulators (userData.wires = attach points)'})


def _yard_sign(game, opts=None):
    opts = opts or {}
    g = K.prop('yard_sign')
    kind = opts.get('kind') if opts.get('kind') is not None else 'trespass'
    galv = K.mat(game, 'metal', '#A8B0BA', {'rough': 0.45})
    face = K.mat(game, 'paint', '#ffffff', {'map': signTex(kind), 'rough': 0.5})
    w = opts.get('w') if opts.get('w') is not None else 0.72
    h = w * 0.625
    g.add(K.m(K.box(w + 0.03, h + 0.03, 0.018, 0.006), galv, {'pos': [0, 0, 0.012]}))
    g.add(K.m(THREE.PlaneGeometry(w, h).rotateY(PI), face, {'pos': [0, 0, 0.0]}))
    for x, y in [[-1, 1], [1, 1], [-1, -1], [1, -1]]:
        g.add(K.m(K.cyl(0.008, 0.008, 0.03, {'seg': 5}).clone().rotateX(PI / 2), galv, {'pos': [x * (w / 2 - 0.03), y * (h / 2 - 0.03), 0.02]}))
    g.userData.colliders = []
    return K.finish(game, g, {'ao': False})


registerProp('yard_sign', _yard_sign, {
    'category': CAT, 'tags': ['yard', 'sign'], 'size': [0.75, 0.48, 0.03],
    'desc': 'fence sign (opts.kind trespass|danger|wztv|gate); origin at its center, face toward -z'})
