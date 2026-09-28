"""DEAD AIR — static meshes and canvas textures src/game/telly.js built at runtime (SPEC §4/§5), as Blender assets.

Ports, line by line against the kit (dalib.kit = src/props/kit.js) and the three.js geometry port (dalib.three_geo):

    ee_tape_reel.glb   telly.js buildTapeReel(game): the EE 2-inch quad videotape reel (0.36 m aluminium flanges
                       with three holes, gold tape pack, hub, spindle, white label 'ee_reel_label_v1' with a marker
                       "13"), faces -z, centred at the origin; K.finish with its AO bake. godot/scripts/game/telly.gd
                       buildTapeReel(game) instantiates it (the egg re-uses it for VTR #2).
    telly_coin.glb     the refund coin: CylinderGeometry(0.05, 0.05, 0.012, 20).rotateX(PI / 2) with
                       game.mats.toon('#E8B84A', {rough 0.25, metal 0.85, keepColor, emissive '#6A4A10' x0.4}).

Static canvas textures (PNG, godot/assets/runtime/telly/, drawn with dalib/canvas2d.py from the same JS code):

    zzz.png            telly.js zzzTexture(): the 64x64 "Z" sprite of the dozing Telly (glow stroke, eaten flecks)
    dot.png            telly.js dotTexture(): the 64x64 afterglow dot of the CRT power-off / relocation
    weave_<HEX>.png    K.tex.weave(base, {pattern:'plain', scale:3}) for the lamp language materials telly.js swaps
                       onto the telly_lamp shade (_warmMats / _purpleMats / props setLampLevel): F2C45A (lit),
                       BE9442 (off), 9A5AD0 (purple), E9B64A (the prop's own shade)

Per-frame geometry (the stretchy arm tube, the display-model outline hull, the rubber-glass bubble shader) is built by
godot/scripts/game/telly.gd. The 'telly', 'telly_lamp', 'telly_rug', 'telly_cord' props are the machines prop port.

Run: python3 blender/build_all.py --only runtime   (build_all calls build(save_blend)), or standalone:
     cd /home/user/dead-air && python3 blender/runtime/telly.py [--save-blend]
"""
import math
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
_BLENDER = os.path.dirname(_HERE)
if _BLENDER not in sys.path:
    sys.path.insert(0, _BLENDER)

from dalib import kit as K  # noqa: E402
from dalib.kit import THREE, PAL  # noqa: E402
from dalib import tex as TEX  # noqa: E402
from dalib.scene import Mesh, Material  # noqa: E402

REPO = os.path.dirname(_BLENDER)
OUT_DIR = os.path.join(REPO, 'godot', 'assets', 'runtime', 'telly')
BLEND_OUT = os.path.join(_BLENDER, 'out')
PI = math.pi
TAU = PI * 2
TAPE_ID = 'ee_tape_reel'
# the weave bases of the lamp language (telly.js _warmMats / _purpleMats, machines.js lampShadeMat)
WEAVES = ['#F2C45A', '#BE9442', '#9A5AD0', '#E9B64A']


# ------------------------------------------------------------------------------------------------ tape reel
def buildTapeReel(game):
    """The EE 2-inch quad videotape reel: 0.36 m aluminium reel, gold tape pack, white label with a marker "13".
    Faces -z, centred at the origin (hub axis = z)."""
    g = K.prop(TAPE_ID)
    kc = {'keepColor': True}
    alu = K.mat(game, 'chrome', '#C9D1DB', kc)
    tape = K.mat(game, 'plastic', '#C99532', dict({'rough': 0.32}, **kc))
    dark = K.mat(game, 'plastic', '#3A2C3E', kc)

    def draw(ctx, W, H, rand):
        ctx.fillStyle = '#F7F4EA'
        ctx.beginPath()
        ctx.arc(W / 2, H / 2, W / 2, 0, TAU)
        ctx.fill()
        ctx.strokeStyle = '#D9D2C0'
        ctx.lineWidth = 6
        ctx.stroke()
        ctx.strokeStyle = 'rgba(40,60,160,0.35)'
        ctx.lineWidth = 2
        for i in range(4):
            ctx.beginPath()
            ctx.moveTo(40, 78 + i * 34)
            ctx.lineTo(216, 78 + i * 34)
            ctx.stroke()
        ctx.fillStyle = '#1B2A8A'
        ctx.textAlign = 'center'
        ctx.textBaseline = 'middle'
        ctx.font = 'bold 120px "Permanent Marker", "Comic Sans MS", "Titan One", sans-serif'
        ctx.save()
        ctx.translate(W / 2, H / 2 + 6)
        ctx.rotate(-0.12)
        ctx.fillText('13', 0, 0)
        ctx.restore()
        ctx.font = '22px "Titan One", sans-serif'
        ctx.fillStyle = '#B5472A'
        ctx.fillText('SIGN-OFF', W / 2, 46)
    label = K.mat(game, 'plastic', '#ffffff', dict({'map': K.tex.canvas('ee_reel_label_v1', 256, 256, draw,
                                                                        {'repeat': False, 'fonts': True})}, **kc))
    R, gap = 0.18, 0.056
    flange = THREE.Shape()
    flange.absarc(0, 0, R, 0, TAU, False)
    for i in range(3):
        a = (i / 3) * TAU + 0.3
        hole = THREE.Path()
        hole.absarc(math.cos(a) * 0.105, math.sin(a) * 0.105, 0.045, 0, TAU, True)
        flange.holes.append(hole)
    for z in (-gap / 2, gap / 2):
        g.add(K.m(K.extrude(flange, 0.007, {'bevel': 0.002, 'curveSeg': 24}), alu, {'pos': [0, 0, z]}))
    g.add(K.m(K.cyl(0.15, 0.15, gap - 0.004, {'bevel': 0.003, 'seg': 32}), tape,
              {'rot': [PI / 2, 0, 0], 'pos': [0, 0, -(gap - 0.004) / 2]}))
    g.add(K.m(K.cyl(0.042, 0.042, gap + 0.03, {'bevel': 0.006, 'seg': 20}), alu,
              {'rot': [PI / 2, 0, 0], 'pos': [0, 0, -(gap + 0.03) / 2]}))
    g.add(K.m(K.cyl(0.016, 0.016, gap + 0.034, {'bevel': 0.002, 'seg': 12}), dark,
              {'rot': [PI / 2, 0, 0], 'pos': [0, 0, -(gap + 0.034) / 2]}))
    lg = THREE.CircleGeometry(0.068, 28).rotateY(PI)
    g.add(K.m(lg, label, {'pos': [0.1, -0.02, -gap / 2 - 0.0045], 'rot': [0, 0, 0]}))
    g.userData.colliders = []
    return K.finish(game, g, {'ao': {'floor': False, 'height': 0, 'strength': 0.6, 'res': 40}})


# ------------------------------------------------------------------------------------------------ refund coin
def buildCoin(game):
    """telly.js _buildTelly: the refund coin the glove flicks back (world-space prop, scaled by SCALE at runtime)."""
    coinMat = game.mats.toon('#E8B84A', {'rough': 0.25, 'metal': 0.85, 'keepColor': True, 'emissive': '#6A4A10',
                                         'emissiveIntensity': 0.4})
    root = THREE.Group()
    root.name = 'telly_coin'
    coin = Mesh(THREE.CylinderGeometry(0.05, 0.05, 0.012, 20).rotateX(PI / 2), coinMat)
    coin.name = 'coin'
    coin.castShadow = True
    root.add(coin)
    return root


# ------------------------------------------------------------------------------------------------ sprite textures
def zzzTexture():
    """telly.js zzzTexture (spriteTexture 64x64). Math.random flecks: seeded here (cosmetic)."""
    def draw(x, W, H, rand):
        x.lineJoin = 'round'
        x.lineCap = 'round'
        x.shadowColor = '#7FE7FF'
        x.shadowBlur = 8
        x.strokeStyle = '#E6FDFF'
        x.lineWidth = 10
        x.beginPath()
        x.moveTo(15, 15)
        x.lineTo(49, 15)
        x.lineTo(15, 49)
        x.lineTo(49, 49)
        x.stroke()
        x.shadowBlur = 0
        x.globalCompositeOperation = 'destination-out'
        for i in range(160):
            x.fillStyle = 'rgba(0,0,0,%s)' % (0.25 + rand() * 0.6)
            x.fillRect(rand() * W, rand() * W, 2, 2)
    return TEX.canvasTex('telly.zzz', 64, 64, draw, {'repeat': False})


def dotTexture():
    """telly.js dotTexture (spriteTexture 64x64)."""
    def draw(x, W, H, rand):
        g = x.createRadialGradient(W / 2, W / 2, 0, W / 2, W / 2, W / 2)
        g.addColorStop(0, 'rgba(255,255,255,1)')
        g.addColorStop(0.18, 'rgba(235,252,255,1)')
        g.addColorStop(0.4, 'rgba(127,231,255,0.45)')
        g.addColorStop(1, 'rgba(127,231,255,0)')
        x.fillStyle = g
        x.fillRect(0, 0, W, W)
    return TEX.canvasTex('telly.dot', 64, 64, draw, {'repeat': False})


def weaveTexture(base):
    """K.tex.weave(base, {pattern:'plain', scale:3}) (the lamp shade fabric)."""
    return K.tex.weave(base, {'pattern': 'plain', 'scale': 3})


def _save_png(t, name):
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, name)
    t.image.save_png(path)
    imp = path + '.import'
    if not os.path.exists(imp):
        with open(imp, 'w') as f:
            f.write(TEX.IMPORT_FILE)
    return path


# ------------------------------------------------------------------------------------------------ build
def _assets(game):
    return {'ee_tape_reel': buildTapeReel(game), 'telly_coin': buildCoin(game)}


def build(save_blend=False, only=None):
    """Builds every Telly runtime asset into godot/assets/runtime/telly/. Returns the written paths."""
    from dalib import export as EX
    game = K.Game()
    written = []
    for name, root in _assets(game).items():
        if only and name not in only:
            continue
        path = os.path.join(OUT_DIR, name + '.glb')
        blend = os.path.join(BLEND_OUT, 'runtime_telly_%s.blend' % name) if save_blend else None
        EX.export_graph(root, path, root_name=name, save_blend=blend)
        written.append(path)
        print('[runtime/telly] %s' % path)
    textures = [('zzz.png', zzzTexture()), ('dot.png', dotTexture())]
    textures += [('weave_%s.png' % b.lstrip('#').upper(), weaveTexture(b)) for b in WEAVES]
    for fname, t in textures:
        if only and fname not in only:
            continue
        written.append(_save_png(t, fname))
        print('[runtime/telly] %s' % written[-1])
    return written


if __name__ == '__main__':
    args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
    build(save_blend='--save-blend' in args)
