"""DEAD AIR — static meshes src/game/economy.js assembled at runtime (SPEC §4/§5), as Blender assets.

Ports, line by line against the kit (dalib.kit = src/props/kit.js), the three.js geometry port (dalib.three_geo) and
the Canvas 2D emulation (dalib.canvas2d). Output in godot/assets/runtime/economy/ (loaded by
godot/scripts/game/economy.gd through game.props.loadRuntime):

    wallbuy_<weaponId>.glb   WallBuy._build (pump_37, mp7, m16a1): the promo lightbox in POSTER SPACE (origin at the
                             anchor, z = 0 on the wall, front -z): 'frame' (walnut frame bars, chrome lip, dark back
                             panel, brass picture light on two arms with its glowing tungsten tube), 'poster' (the
                             W x H sheet; glow material with the card poster_<gun>; the game swaps in the winked card),
                             'shadow' (the soft contact shadow under the gun, gunShadowTex, renderOrder 1), 'clip_0' /
                             'clip_1' (brass bulldog clips: hinge pivots holding the jaw tab + spring roll; the game
                             re-seats them on the gun's silhouette and swings them about x). Root extras "da":
                             {W, H, len, gh, gd, gcx} — the sheet size comes from the wall-pose gun's length exactly
                             like the JS (W = clamp(len / 0.8, 0.95, 1.3), long rifles overhang, H = W * 4 / 3).
    tube_o_matic.glb         GrenadeCase._build: the "Tube-O-Matic" wall cabinet in CASE SPACE (floor y = 0, back on
                             z = 0, front -z): the kit prop body ('prop_tube_o_matic': walnut cabinet, orange lacquer
                             panel, chrome kick plate, gold pinstripes, chute, coin plate, red button, display box,
                             shelf, sockets, bezel; K.finish with its AO bake), 'panel' (backlit sunburst), 'strip'
                             (warm light tube), 'signBox' + 'sign' (TUBE-O-MATIC label), 'marquee' (22 chasing bulbs:
                             marquee_<i>, the game scales them), 'glass' (the flap, pivot on its hinge, with the two
                             highlight streaks). The four display tubes are prop instances placed by the game.

The gun measurements: when the weapons prop port is registered (blender/props/weapons.py) the 'wall' pose prop is
built and measured like the JS (Box3.setFromObject + the clip slice profile); otherwise the wall-pose bounding boxes
of the JS props (the reference dump) are used.

Run: python3 blender/build_all.py --only runtime   (calls build(save_blend)), or standalone:
     cd /home/user/dead-air && python3 blender/runtime/economy.py [--save-blend]
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
from dalib.kit import THREE, PAL, getCard  # noqa: E402
from dalib.scene import box_from_object  # noqa: E402

REPO = os.path.dirname(_BLENDER)
OUT_DIR = os.path.join(REPO, 'godot', 'assets', 'runtime', 'economy')
BLEND_OUT = os.path.join(_BLENDER, 'out')
PI = math.pi
TAU = PI * 2

WALLBUY_GUNS = ['pump_37', 'mp7', 'm16a1']     # layout.js wb_pump / wb_mp7 / wb_m16 `gives`
# Wall-pose bounding boxes of the JS weapon props (min, max), used while the weapons prop port is not registered.
GUN_BOX = {
    'pump_37': ([-0.5505, -0.1054, -0.074], [0.5505, 0.1054, 0.0]),
    'mp7': ([-0.2697, -0.224, -0.0802], [0.2697, 0.224, 0.0]),
    'm16a1': ([-0.6392, -0.1931, -0.0902], [0.6392, 0.1931, 0.0]),
}


def clamp(x, a, b):
    return a if x < a else b if x > b else x


_rbCache = {}


def roundedBox(w, h, d, r):
    key = '%.4f|%.4f|%.4f|%s' % (w, h, d, r)
    g = _rbCache.get(key)
    if g is None:
        g = K.box(w, h, d, r)
        _rbCache[key] = g
    return g


# ------------------------------------------------------------------------------------------------ gun measure
def sliceProfile(root, x0, x1):
    """Highest y and front-most z (most negative) of a prop's vertices with x in [x0, x1], in the prop's own space."""
    top, front = -math.inf, math.inf
    root.updateMatrixWorld(True)
    inv = np.array(root.matrixWorld.clone().invert().elements, dtype=np.float64).reshape(4, 4).T

    def f(o):
        nonlocal top, front
        geo = getattr(o, 'geometry', None)
        if not getattr(o, 'isMesh', False) or geo is None or getattr(geo.attributes, 'position', None) is None:
            return
        pos = geo.attributes.position
        arr = np.asarray(pos.array, dtype=np.float64).reshape(-1, pos.itemSize)[:, :3]
        m = inv @ np.array(o.matrixWorld.elements, dtype=np.float64).reshape(4, 4).T
        p = (np.c_[arr, np.ones(len(arr))] @ m.T)[:, :3]
        sel = p[(p[:, 0] >= x0) & (p[:, 0] <= x1)]
        if len(sel):
            top = max(top, float(sel[:, 1].max()))
            front = min(front, float(sel[:, 2].min()))
    root.traverse(f)
    return {'top': top, 'front': front}


def measureGun(game, weaponId):
    """Gun in 'wall' pose: side-on, back at z = 0, barrel toward -x. -> (len, gh, gd, gcx, profile(x0, x1) | None)."""
    gun = None
    try:
        from props import load_all
        load_all(verbose=False)
        if weaponId in K.PROPS:
            gun = K.buildProp(weaponId, game, {'pose': 'wall'})
    except Exception as e:  # the weapons port may be missing / incomplete: fall back to the JS measurements
        print('[runtime/economy] %s: wall-pose prop not buildable (%s): JS reference box' % (weaponId, e))
        gun = None
    if gun is not None:
        gun.updateMatrixWorld(True)
        b = box_from_object(gun)
        mn, mx = [b.min.x, b.min.y, b.min.z], [b.max.x, b.max.y, b.max.z]
        return mn, mx, (lambda x0, x1: sliceProfile(gun, x0, x1))
    mn, mx = GUN_BOX[weaponId]
    return mn, mx, None


# ------------------------------------------------------------------------------------------------ textures
def gunShadowTex():
    """Soft contact shadow for a prop gun clipped on a lit poster (the lightbox is unlit, so no real shadow lands)."""
    def draw(x, w, h, rand):
        x.filter = 'blur(9px)'
        x.fillStyle = 'rgba(42,20,52,0.85)'
        x.beginPath()
        x.roundRect(22, 18, 212, 28, 14)
        x.fill()
    return K.tex.canvas('econ.gunShadow', 256, 64, draw, {'repeat': False})


def sunburstTex():
    """Plum velvet back panel with an orange / gold 70s sunburst (the Tube-O-Matic display)."""
    def draw(ctx, w, h, rand):
        ctx.fillStyle = '#4A2A52'
        ctx.fillRect(0, 0, w, h)
        cx, cy = w / 2, h * 0.72
        for i in range(18):
            a0 = (i / 18) * TAU
            a1 = a0 + TAU / 36
            ctx.fillStyle = '#E3662B' if i % 2 else '#E8A92E'
            ctx.globalAlpha = 0.55
            ctx.beginPath()
            ctx.moveTo(cx, cy)
            ctx.lineTo(cx + math.cos(a0) * w, cy + math.sin(a0) * w)
            ctx.lineTo(cx + math.cos(a1) * w, cy + math.sin(a1) * w)
            ctx.closePath()
            ctx.fill()
        ctx.globalAlpha = 1
        gr = ctx.createRadialGradient(cx, cy, 4, cx, cy, w * 0.75)
        gr.addColorStop(0, 'rgba(255,220,150,0.55)')
        gr.addColorStop(1, 'rgba(40,20,50,0.6)')
        ctx.fillStyle = gr
        ctx.fillRect(0, 0, w, h)
    return K.tex.canvas('econ.sunburst', 256, 256, draw, {'repeat': False})


# ------------------------------------------------------------------------------------------------ wall-buy
def buildWallbuy(game, weaponId):
    """WallBuy._build: the lightbox, poster, contact shadow and clips, in poster space (see the module doc)."""
    M = game.mats
    mn, mx, profile = measureGun(game, weaponId)
    len_, gh, gd = mx[0] - mn[0], mx[1] - mn[1], mx[2] - mn[2]
    gcx = (mn[0] + mx[0]) / 2
    # Sheet width from the gun length; long rifles may overhang the walnut frame by a few cm, never the wall.
    W = clamp(len_ / 0.8, 0.95, 1.3)
    if len_ > W + 0.12:
        W = len_ - 0.12
    H = W * 4 / 3
    # The poster's painted mount sits 73% down the sheet: put it at the anchor height (gun centre = anchor y).
    top = 0.73 * H
    inner = THREE.Group()                       # poster space: origin at the anchor, z = 0 on the wall
    inner.name = 'wallbuy_%s' % weaponId
    inner.userData.W = W
    inner.userData.H = H
    inner.userData.len = len_
    inner.userData.gh = gh
    inner.userData.gd = gd
    inner.userData.gcx = gcx

    # Lightbox: walnut frame, chrome lip, backlit poster (unlit glow material so it reads in dark studios).
    cy = top - H / 2
    wood = M.toon(PAL.walnut, {'rough': 0.45, 'rim': 0.25})
    chrome = M.toon('#C9CED8', {'metal': 1, 'rough': 0.22, 'rim': 0.3})
    fw, fd = 0.075, 0.085
    frame = THREE.Group()                       # static lightbox parts
    frame.name = 'frame'
    inner.add(frame)

    def bar(w, h, x, y, mat, d=fd, z=-fd / 2):
        m = THREE.Mesh(roundedBox(w, h, d, 0.018), mat)
        m.position.set(x, y, z)
        m.castShadow = True
        m.receiveShadow = True
        frame.add(m)
        return m
    bar(W + fw * 2, fw, 0, cy + H / 2 + fw / 2, wood)
    bar(W + fw * 2, fw, 0, cy - H / 2 - fw / 2, wood)
    bar(fw, H, -W / 2 - fw / 2, cy, wood)
    bar(fw, H, W / 2 + fw / 2, cy, wood)
    lip = 0.014
    bar(W, lip, 0, cy + H / 2 - lip / 2, chrome, 0.02, -fd + 0.012)
    bar(W, lip, 0, cy - H / 2 + lip / 2, chrome, 0.02, -fd + 0.012)
    bar(lip, H, -W / 2 + lip / 2, cy, chrome, 0.02, -fd + 0.012)
    bar(lip, H, W / 2 - lip / 2, cy, chrome, 0.02, -fd + 0.012)
    back = THREE.Mesh(THREE.PlaneGeometry(W + fw, H + fw), M.toon('#2A1D2E', {'rough': 0.9, 'rim': 0}))
    back.rotation.y = PI
    back.position.set(0, cy, -0.004)
    frame.add(back)

    card = 'poster_%s' % weaponId
    matNormal = M.glow('#ffffff', 0.92, {'map': getCard(card)})
    poster = THREE.Mesh(THREE.PlaneGeometry(W, H), matNormal)
    poster.rotation.y = PI                      # face -z (into the room)
    poster.position.set(0, cy, -0.04)
    poster.name = 'poster'
    inner.add(poster)

    # Picture light: brass bar lamp over the lightbox on two arms, glowing underside.
    brass = M.toon('#C8963C', {'metal': 1, 'rough': 0.3, 'rim': 0.3})
    lampY = cy + H / 2 + fw + 0.06
    lamp = THREE.Mesh(THREE.CylinderGeometry(0.045, 0.045, W * 0.62, 18, 1), brass)
    lamp.rotation.z = PI / 2
    lamp.position.set(0, lampY, -0.2)
    lamp.castShadow = True
    frame.add(lamp)
    tube = THREE.Mesh(THREE.CylinderGeometry(0.022, 0.022, W * 0.58, 10, 1), M.glow(PAL.tungsten, 2.2))
    tube.rotation.z = PI / 2
    tube.position.set(0, lampY - 0.03, -0.215)
    frame.add(tube)
    for s in (-1, 1):
        arm = THREE.Mesh(THREE.CylinderGeometry(0.012, 0.012, 0.22, 8, 1), brass)
        arm.rotation.x = PI / 2
        arm.position.set(s * W * 0.22, lampY, -0.1)
        arm.castShadow = True
        frame.add(arm)

    # The gun (a prop instance the game clips just in front of the poster) casts this soft shadow.
    gunZ = -0.055
    shadow = THREE.Mesh(THREE.PlaneGeometry(len_ * 1.12, max(0.16, gh * 1.25)), THREE.MeshBasicMaterial({
        'map': gunShadowTex(), 'transparent': True, 'depthWrite': False, 'color': '#ffffff'}))
    shadow.rotation.y = PI
    shadow.position.set(len_ * 0.03, -gh * 0.32, -0.043)
    shadow.renderOrder = 1
    shadow.name = 'shadow'
    shadow.castShadow = False
    inner.add(shadow)
    # Brass bulldog clips (plain chrome read as black slabs against the backlit sheet: no bright env to reflect),
    # each hinged just above the gun's real silhouette at its x (a rifle's barrel sits lower than its carry handle).
    clipMat = M.toon('#C8942F', {'metal': 0, 'rough': 0.5, 'rim': 0.28, 'rimColor': '#FFE7B0', 'emissive': '#4A300A',
                                 'emissiveIntensity': 0.12})
    for i, s in enumerate((-1, 1)):
        cx = gcx + s * len_ * 0.24
        prof = profile(cx - 0.03, cx + 0.03) if profile else {'top': math.inf, 'front': math.inf}
        topY = prof['top'] if math.isfinite(prof['top']) else gh / 2
        frontZ = prof['front'] if math.isfinite(prof['front']) else -gd
        hinge = THREE.Group()
        hinge.name = 'clip_%d' % i
        hinge.position.set(cx, topY + 0.03, gunZ + frontZ - 0.006)
        tab = THREE.Mesh(roundedBox(0.05, 0.1, 0.014, 0.006), clipMat)
        tab.position.set(0, -0.045, -0.007)
        tab.castShadow = True
        roll = THREE.Mesh(THREE.CylinderGeometry(0.011, 0.011, 0.058, 10, 1), clipMat)
        roll.rotation.z = PI / 2
        roll.position.set(0, 0.002, -0.004)
        roll.castShadow = True
        hinge.add(tab)
        hinge.add(roll)
        inner.add(hinge)
    return inner


# ------------------------------------------------------------------------------------------------ grenade case
def buildGrenadeCase(game):
    """GrenadeCase._build: the "Tube-O-Matic" cabinet (see the module doc), case space."""
    g = game
    root = THREE.Group()
    root.name = 'tube_o_matic'

    # Floor-standing cabinet against the wall. Local: floor y = 0, back on z = 0, front toward -z. The display
    # window is centred near the anchor height (1.4 m); the base holds the coin plate, the push button and a chute.
    body = K.prop('tube_o_matic')
    walnut = K.mat(g, 'walnut', '#ffffff', {'map': K.tex.wood(PAL.walnut, {'dark': 0.4})})
    chrome = K.mat(g, 'chrome', '#A8B0BA')
    orange = K.mat(g, 'lacquer', PAL.burntOrange)
    gold = K.mat(g, 'lacquer', PAL.harvestGold)
    W, D, baseH, winY0, winY1, Dw = 0.96, 0.5, 1.02, 1.06, 1.74, 0.42

    def add(geo, mat, pos):
        body.add(K.m(geo, mat, {'pos': pos}))
    # base cabinet: walnut box, orange lacquer front panel, chrome kick plate, gold pinstripes
    add(K.box(W, baseH, D, 'lg', {'uv': 1.1}), walnut, [0, baseH / 2, -D / 2])
    add(K.box(W - 0.14, baseH - 0.26, 0.03, 'md'), orange, [0, baseH / 2 + 0.05, -D - 0.005])
    add(K.box(W + 0.02, 0.1, 0.03, 'sm'), chrome, [0, 0.07, -D - 0.005])
    for y in (0.3, 0.86):
        add(K.box(W - 0.1, 0.025, 0.02, 'xs'), gold, [0, y, -D - 0.022])
    # chute (dark mouth with a chrome lip), coin plate, red button
    add(K.box(0.36, 0.16, 0.04, 'sm'), chrome, [0, 0.45, -D - 0.02])
    add(K.box(0.3, 0.1, 0.03, 'sm'), K.mat(g, 'rubber', '#2A2233'), [0, 0.45, -D - 0.035])
    add(K.box(0.2, 0.2, 0.03, 'sm'), chrome, [0, 0.7, -D - 0.022])
    add(K.box(0.05, 0.012, 0.01, 'xs'), K.mat(g, 'plastic', '#2A2233'), [-0.04, 0.74, -D - 0.04])
    add(K.cyl(0.04, 0.044, 0.035, {'bevel': 0.01, 'seg': 18}).clone().rotateX(-PI / 2), K.mat(g, 'plastic', PAL.channelRed),
        [0.045, 0.67, -D - 0.04])
    # display box: walnut shell (the backlit sunburst panel is added after K.finish), chrome shelf + sockets, chrome bezel
    dy, dh = (winY0 + winY1) / 2, winY1 - winY0 + 0.1
    add(K.box(W - 0.02, 0.06, Dw, 'md', {'uv': 1.1}), walnut, [0, winY0 - 0.02, -Dw / 2])
    add(K.box(W - 0.02, 0.07, Dw, 'md', {'uv': 1.1}), walnut, [0, winY1 + 0.03, -Dw / 2])
    for sx in (-1, 1):
        add(K.box(0.07, dh, Dw, 'md', {'uv': 1.1}), walnut, [sx * (W / 2 - 0.045), dy, -Dw / 2])
    add(K.box(W - 0.14, 0.04, Dw - 0.08, 'sm'), chrome, [0, winY0 + 0.1, -Dw / 2 - 0.02])
    for i in range(4):
        x = -0.3 + i * 0.2
        add(K.cyl(0.05, 0.056, 0.035, {'bevel': 0.008, 'seg': 18}), K.mat(g, 'plastic', '#3A2A40'), [x, winY0 + 0.12, -Dw / 2 - 0.02])
    for w, h, x, y in ([W - 0.06, 0.035, 0, winY1 - 0.005], [W - 0.06, 0.035, 0, winY0 + 0.02],
                       [0.035, dh - 0.06, -(W / 2 - 0.05), dy], [0.035, dh - 0.06, W / 2 - 0.05, dy]):
        add(K.box(w, h, 0.03, 'sm'), chrome, [x, y, -Dw - 0.005])
    K.finish(g, body, {'ao': {'strength': 0.75, 'height': 0.25, 'rays': 12, 'res': 56}, 'cast': 0.25})
    root.add(body)

    # Backlit sunburst panel behind the tubes (unlit: the AO bake and the case's own shadow turned felt to mud).
    panel = THREE.Mesh(THREE.PlaneGeometry(W - 0.12, dh - 0.02), g.mats.glow('#ffffff', 0.62, {'map': sunburstTex()}))
    panel.rotation.y = PI
    panel.position.set(0, dy, -0.012)
    panel.name = 'panel'
    root.add(panel)

    # warm strip light inside the display (unlit tube along the top)
    strip = THREE.Mesh(THREE.CylinderGeometry(0.018, 0.018, W - 0.2, 10, 1), g.mats.glow(PAL.tungsten, 2.4))
    strip.rotation.z = PI / 2
    strip.position.set(0, winY1 - 0.04, -Dw + 0.06)
    strip.name = 'strip'
    root.add(strip)

    # Header sign (in-world signage is allowed; the prompt never names anything) with chasing marquee bulbs.
    signY = winY1 + 0.25
    signBox = THREE.Mesh(roundedBox(W + 0.08, 0.34, 0.12, 0.04), g.mats.toon(PAL.walnut, {'rough': 0.45, 'rim': 0.25}))
    signBox.position.set(0, signY, -Dw / 2 - 0.1)
    signBox.castShadow = True
    signBox.name = 'signBox'
    root.add(signBox)
    sign = THREE.Mesh(
        THREE.PlaneGeometry(W - 0.06, 0.24),
        g.mats.glow('#ffffff', 0.95, {'map': K.tex.label('TUBE-O-MATIC', {
            'sub': 'WZTV ENGINEERING', 'bg': '#FFE9B0', 'fg': PAL.chocolate, 'accent': PAL.burntOrange,
            'w': 512, 'h': 128, 'wear': 0.15})}),
    )
    sign.rotation.y = PI
    sign.position.set(0, signY, -Dw / 2 - 0.161)
    sign.name = 'sign'
    root.add(sign)
    # 22 chasing marquee bulbs: one InstancedMesh (an unlit bulb is scaled to a dim pip, not hidden).
    NB = 22
    bulbs = THREE.InstancedMesh(THREE.SphereGeometry(0.018, 10, 8), g.mats.glow(PAL.marqueeGold, 2.2), NB)
    bulbs.name = 'marquee'
    bw, bh = W + 0.02, 0.3
    perim = 2 * (bw + bh)
    m4 = THREE.Matrix4()
    for i in range(NB):
        # walk the rectangle around the sign face
        d = (i / NB) * perim
        if d < bw:
            x, y = -bw / 2 + d, bh / 2
        elif d < bw + bh:
            x, y = bw / 2, bh / 2 - (d - bw)
        elif d < 2 * bw + bh:
            x, y = bw / 2 - (d - bw - bh), -bh / 2
        else:
            x, y = -bw / 2, -bh / 2 + (d - 2 * bw - bh)
        # _setBulbs(0, false): every third bulb dark (scaled to 0.45)
        s = 1 if (i + 0) % 3 != 0 else 0.45
        m4.makeScale(s, s, s).setPosition(x, signY + y, -Dw / 2 - 0.165)
        bulbs.setMatrixAt(i, m4)
    bulbs.castShadow = False
    root.add(bulbs)

    # Cartoon glass front: no reflective sheet (it washed the display out), just two diagonal highlight streaks.
    streak = g.mats.glow('#FFFFFF', 0.9, {'transparent': True, 'opacity': 0.22})
    # The glass is a flap hinged on its top edge: it swings up and out when the tubes pop (economy.gd buy()).
    glass = THREE.Group()
    glass.name = 'glass'
    hingeY, hingeZ = winY1 - 0.01, -Dw - 0.012
    glass.position.set(0, hingeY, hingeZ)
    for w, x in ((0.09, -0.18), (0.035, -0.05)):
        m = THREE.Mesh(THREE.PlaneGeometry(w, dh - 0.16), streak)
        m.rotation.set(0, PI, -0.5)
        m.position.set(x, dy + 0.02 - hingeY, -Dw + 0.005 - hingeZ)
        m.renderOrder = 2
        m.castShadow = False
        glass.add(m)
    root.add(glass)
    return root


# ------------------------------------------------------------------------------------------------ build
def _assets(game):
    out = {'wallbuy_%s' % w: (lambda w=w: buildWallbuy(game, w)) for w in WALLBUY_GUNS}
    out['tube_o_matic'] = lambda: buildGrenadeCase(game)
    return out


def build(save_blend=False, only=None, godot=None, ids=None):
    """Builds every economy runtime asset into godot/assets/runtime/economy/ (or <godot>/assets/runtime/economy/).
    Returns the written paths."""
    from dalib import export as EX
    out_dir = os.path.join(godot, 'assets', 'runtime', 'economy') if godot else OUT_DIR
    only = only or ids
    game = K.Game()
    written = []
    for name, make in _assets(game).items():
        if only and name not in only:
            continue
        root = make()
        path = os.path.join(out_dir, name + '.glb')
        blend = os.path.join(BLEND_OUT, 'runtime_economy_%s.blend' % name) if save_blend else None
        EX.export_graph(root, path, root_name=name, save_blend=blend)
        written.append(path)
        print('[runtime/economy] %s' % path)
    return written


if __name__ == '__main__':
    args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
    build(save_blend='--save-blend' in args)
