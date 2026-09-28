"""DEAD AIR — static meshes the menus built at runtime (SPEC §4/§5), exported as Blender assets.

Port of the static geometry of src/ui/menu.js (the living room of the title / character select and the hero sets
shown on its TV), line by line against dalib.kit / dalib.three_geo / dalib.scene. The Godot module
(godot/scripts/ui/menu.gd) instances these GLBs; every material carries its "da" spec (materials.gd fromSpec builds
the same shader the JS factory built). Two GLBs in godot/assets/runtime/menu/:

    room.glb   _buildRoom: the shell (shag floor, the four walnut-paneled walls with the window hole in the left one,
               baseboards and cornices, ceiling), the window (walnut frame, sill, glazing bars), the night outside
               ('night': a basic plane with the _nightTexture canvas: moon, stars, skyline, the WZTV tower),
               'beacon' (the tower's blinking red light: menu.gd toggles it), the two corduroy curtains and the brass
               rod, 'popcorn' (_popcorn: red bowl + 26 puffs) and 'guide' (the TV Weekly magazine, card
               magazine_tv_weekly). The props (Telly, rug, lamps, sofa …) come from the prop library at runtime.
    sets.glb   _buildSet: 'set_back_<hero>' (the curved cyclorama flat with the promo_<hero> card, tint
               Color(0.82, 0.8, 0.86), fog off) and 'set_floor_<hero>' (CircleGeometry(3.2, 40) scaled 1.3 x: Roxy's
               disco floor canvas, Duke's checker canvas, Penny's brushed steel, Skip's teak planks) for the four
               heroes, and 'goldBadge' (_goldBadge: the gold 13 medal worn with the persistent unlock).

The dust motes (random per run, a shader-animated points cloud), the lights, the cameras, the TV compositor and the
heroes are built by menu.gd at runtime.

Run: python3 blender/build_all.py --only runtime   (calls build(save_blend)), or standalone:
     cd /home/user/dead-air && python3 blender/runtime/menu.py [--save-blend]
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
from dalib.canvas2d import Canvas  # noqa: E402
from dalib.scene import Group, Mesh  # noqa: E402

REPO = os.path.dirname(_BLENDER)
OUT_DIR = os.path.join(REPO, 'godot', 'assets', 'runtime', 'menu')
PI = math.pi

FONTS_HUD = '"Titan One", "Arial Black", sans-serif'   # ui/fonts.js FONTS.hud
HEROES = ['skip', 'roxy', 'penny', 'duke']            # CHANNELS order


def canvas(w, h):
    return Canvas(w, h)


def canvas_texture(cv, key, repeat=False):
    """new THREE.CanvasTexture(canvas) (sRGB); a stable key names the PNG."""
    t = TEX.Texture(cv, key, repeat, 'menu')
    return t


# ============================================================================================ living room
def buildRoom(game):
    """menu.js _buildRoom: everything static the room builds itself (the props come from the prop library)."""
    M = game.mats
    root = Group()
    root.name = 'menu_room'

    # ---- shell: shag floor, paneled walls (window hole on the left), baseboards, ceiling
    X0, X1, Z0, Z1, H = -3, 3, -3.3, 2.1, 3.0
    floorMat = M.toon('#ffffff', {'rough': 1, 'rim': 0.1, 'map': K.tex.shag('#C8562A', '#E8A92E')})
    fg = THREE.PlaneGeometry(X1 - X0, Z1 - Z0)
    K.uvScale(fg, (X1 - X0) * 1.1, (Z1 - Z0) * 1.1)
    floor = Mesh(fg, floorMat)
    floor.name = 'floor'
    floor.rotation.x = -PI / 2
    floor.position.set(0, 0, (Z0 + Z1) / 2)
    floor.receiveShadow = True
    root.add(floor)
    wallMat = M.toon('#ffffff', {'rough': 0.5, 'rim': 0.12, 'map': TEX.woodPanel('#7A4A2A')})
    trim = M.toon('#4A2E1C', {'rough': 0.4, 'rim': 0.15})
    win = {'z': -0.55, 'y': 1.42, 'w': 1.34, 'h': 1.12}

    def wall(ln, rotY, pos, hole=None, name='wall'):
        if hole:
            s = THREE.Shape()
            s.moveTo(-ln / 2, 0)
            s.lineTo(ln / 2, 0)
            s.lineTo(ln / 2, H)
            s.lineTo(-ln / 2, H)
            s.closePath()
            hp = THREE.Path()
            hp.moveTo(hole['x'] - hole['w'] / 2, hole['y'] - hole['h'] / 2)
            hp.lineTo(hole['x'] + hole['w'] / 2, hole['y'] - hole['h'] / 2)
            hp.lineTo(hole['x'] + hole['w'] / 2, hole['y'] + hole['h'] / 2)
            hp.lineTo(hole['x'] - hole['w'] / 2, hole['y'] + hole['h'] / 2)
            hp.closePath()
            s.holes.append(hp)
            geo = THREE.ShapeGeometry(s)
            uv = geo.attributes.uv
            for i in range(uv.count):
                uv.setXY(i, (uv.getX(i) + ln / 2) / 1.2, uv.getY(i) / 2.4)
        else:
            geo = THREE.PlaneGeometry(ln, H)
            geo.translate(0, H / 2, 0)
            K.uvScale(geo, ln / 1.2, H / 2.4)
        w = Mesh(geo, wallMat)
        w.name = name
        w.position.set(pos[0], 0, pos[2])
        w.rotation.y = rotY
        w.receiveShadow = True
        root.add(w)
        bb = Mesh(K.box(ln, 0.12, 0.03, 0.008), trim)
        bb.name = name + '_baseboard'
        bb.position.set(pos[0], 0.06, pos[2])
        bb.rotation.y = rotY
        bb.translateZ(0.015)
        bb.receiveShadow = True
        root.add(bb)
        cr = Mesh(K.box(ln, 0.08, 0.05, 0.01), trim)
        cr.name = name + '_cornice'
        cr.position.set(pos[0], H - 0.04, pos[2])
        cr.rotation.y = rotY
        cr.translateZ(0.025)
        root.add(cr)

    wall(X1 - X0, PI, [0, 0, Z1], name='wall_back')
    wall(Z1 - Z0, PI / 2, [X0, 0, (Z0 + Z1) / 2],
         {'x': -(win['z'] - (Z0 + Z1) / 2), 'y': win['y'], 'w': win['w'], 'h': win['h']}, name='wall_left')
    wall(Z1 - Z0, -PI / 2, [X1, 0, (Z0 + Z1) / 2], name='wall_right')
    wall(X1 - X0, 0, [0, 0, Z0], name='wall_front')
    ceil = Mesh(THREE.PlaneGeometry(X1 - X0, Z1 - Z0), M.toon('#3A2A22', {'rough': 0.95, 'rim': 0}))
    ceil.name = 'ceiling'
    ceil.rotation.x = PI / 2
    ceil.position.set(0, H, (Z0 + Z1) / 2)
    root.add(ceil)

    # ---- the window: walnut frame, sill, glass, the night outside (moon, skyline, the WZTV tower), curtains
    wood = M.toon('#ffffff', {'rough': 0.45, 'rim': 0.15, 'map': K.tex.wood(PAL.walnut, {'dark': 0.4})})
    fw = 0.08
    nb = [0]

    def addB(w, h, d, x, y, z, mat=None):
        m = Mesh(K.box(w, h, d, 0.015), wood if mat is None else mat)
        m.name = 'window_%d' % nb[0]
        nb[0] += 1
        m.position.set(x, y, z)
        m.castShadow = True
        m.receiveShadow = True
        root.add(m)
        return m

    addB(0.14, win['h'] + fw * 2, fw, X0 + 0.03, win['y'], win['z'] - win['w'] / 2 - fw / 2).rotation.y = PI / 2
    addB(0.14, win['h'] + fw * 2, fw, X0 + 0.03, win['y'], win['z'] + win['w'] / 2 + fw / 2).rotation.y = PI / 2
    addB(0.14, fw, win['w'], X0 + 0.03, win['y'] + win['h'] / 2 + fw / 2, win['z'])
    addB(0.26, 0.05, win['w'] + 0.3, X0 + 0.09, win['y'] - win['h'] / 2 - 0.025, win['z'])
    addB(0.05, win['h'], 0.035, X0 + 0.02, win['y'], win['z'])
    addB(0.05, 0.035, win['w'], X0 + 0.02, win['y'], win['z'])
    night = Mesh(THREE.PlaneGeometry(3.2, 2.4), M.basic('#ffffff', {'map': nightTexture(), 'fog': False}))
    night.name = 'night'
    night.position.set(X0 - 0.9, win['y'] + 0.2, win['z'])
    night.rotation.y = PI / 2
    root.add(night)
    beacon = Mesh(THREE.SphereGeometry(0.018, 8, 6), M.glow('#FF3B30', 5))
    beacon.name = 'beacon'
    beacon.position.set(X0 - 0.88, win['y'] + 0.47, win['z'] - 0.42)
    root.add(beacon)
    curtain = M.toon('#ffffff', {'rough': 0.9, 'rim': 0.4, 'map': K.tex.weave('#E8A92E', {'pattern': 'cord'})})
    for s in (-1, 1):
        c = Mesh(K.cushion(0.46, win['h'] + 0.5, 0.1, {'puff': 0.03}), curtain)
        c.name = 'curtain_%s' % ('l' if s < 0 else 'r')
        c.position.set(X0 + 0.14, win['y'] + 0.05, win['z'] + s * (win['w'] / 2 + 0.18))
        c.rotation.y = PI / 2
        c.castShadow = True
        root.add(c)
    rod = addB(0.05, 0.05, win['w'] + 1.2, X0 + 0.14, win['y'] + win['h'] / 2 + 0.3, win['z'],
               M.toon('#C8963C', {'rough': 0.3, 'metal': 0.8, 'rim': 0.3}))
    rod.name = 'curtain_rod'

    # ---- the popcorn bowl and the TV guide on the coffee table
    root.add(popcorn(game, [0.42, 0.49, -0.5]))
    guide = Mesh(THREE.BoxGeometry(0.2, 0.012, 0.27),
                 M.toon('#ffffff', {'rough': 0.6, 'rim': 0.1, 'map': K.getCard('magazine_tv_weekly', {})}))
    guide.name = 'guide'
    guide.position.set(-0.28, 0.486, -0.62)
    guide.rotation.y = 0.35
    guide.castShadow = True
    root.add(guide)
    return root


def popcorn(game, pos):
    """menu.js _popcorn."""
    grp = Group()
    grp.name = 'popcorn'
    bowl = Mesh(K.lathe([[0, 0], [0.06, 0], [0.11, 0.035], [0.13, 0.085], [0.125, 0.09], [0.1, 0.05], [0, 0.045]],
                        {'seg': 20, 'round': 0.01}),
                game.mats.toon('#E23B3B', {'rough': 0.35, 'rim': 0.3}))
    bowl.name = 'bowl'
    bowl.castShadow = True
    grp.add(bowl)
    pop = game.mats.toon('#FFF3D0', {'rough': 0.9, 'rim': 0.45, 'rimColor': '#FFE6A0', 'wrap': 0.8})
    pg = THREE.IcosahedronGeometry(0.022, 1)
    for i in range(26):
        a, r = i * 2.4, 0.02 + (i % 7) * 0.013
        m = Mesh(pg, pop)
        m.name = 'puff_%d' % i
        m.position.set(math.cos(a) * r, 0.075 + (i % 3) * 0.014 + (0.1 - r) * 0.25, math.sin(a) * r)
        m.rotation.set(i, i * 1.7, i * 0.3)
        m.scale.setScalar(0.8 + (i % 4) * 0.12)
        grp.add(m)
    grp.position.set(pos[0], pos[1], pos[2])
    return grp


def nightTexture():
    """menu.js _nightTexture: the night outside the window (512 x 384)."""
    c = canvas(512, 384)
    x = c.getContext('2d')
    gr = x.createLinearGradient(0, 0, 0, 384)
    gr.addColorStop(0, '#0A0E2E')
    gr.addColorStop(0.55, '#1B1E4A')
    gr.addColorStop(1, '#3A3478')
    x.fillStyle = gr
    x.fillRect(0, 0, 512, 384)
    st = [7]

    def rnd():
        st[0] = (st[0] * 16807) % 2147483647
        return st[0] / 2147483647
    for i in range(90):
        x.fillStyle = 'rgba(255,244,214,%s)' % _js_num(0.3 + rnd() * 0.7)
        r = rnd() * 1.4 + 0.4
        x.beginPath()
        x.arc(rnd() * 512, rnd() * 230, r, 0, 7)
        x.fill()
    mg = x.createRadialGradient(360, 90, 10, 360, 90, 110)
    mg.addColorStop(0, 'rgba(255,244,214,.55)')
    mg.addColorStop(1, 'rgba(255,244,214,0)')
    x.fillStyle = mg
    x.fillRect(200, 0, 312, 220)
    x.fillStyle = '#FFF4D6'
    x.beginPath()
    x.arc(360, 90, 30, 0, 7)
    x.fill()
    x.fillStyle = '#1B1E4A'
    x.beginPath()
    x.arc(372, 82, 26, 0, 7)
    x.fill()
    # skyline + tower
    x.fillStyle = '#120E26'
    bx = 0
    while bx < 512:
        w = 26 + rnd() * 40
        h = 40 + rnd() * 90
        x.fillRect(bx, 384 - h, w, h)
        wy = 384 - h + 8
        while wy < 380:
            wx = bx + 5
            while wx < bx + w - 5:
                if rnd() < 0.18:
                    x.fillStyle = '#FFC98A'
                    x.fillRect(wx, wy, 4, 5)
                    x.fillStyle = '#120E26'
                wx += 9
            wy += 12
        bx += w + 2
    x.strokeStyle = '#161230'
    x.lineWidth = 3
    x.beginPath()
    x.moveTo(150, 384)
    x.lineTo(170, 170)
    x.lineTo(190, 384)
    x.moveTo(158, 300)
    x.lineTo(182, 300)
    x.moveTo(163, 240)
    x.lineTo(177, 240)
    x.stroke()
    return canvas_texture(c, 'menu_night')


def _js_num(v):
    """String(number) like JS (shortest round-trip repr, no trailing .0)."""
    s = repr(float(v))
    if s.endswith('.0'):
        s = s[:-2]
    return s


# ============================================================================================ hero sets (on TV)
def buildSets(game):
    """menu.js _buildSet: the static half of each channel's set (backdrop + floor) and the unlock's gold badge."""
    M = game.mats
    root = Group()
    root.name = 'menu_sets'
    for hero in HEROES:
        # backdrop: the show's promo art, gently curved like a cyclorama flat
        bg = THREE.PlaneGeometry(5.6, 4.2, 24, 1)
        p = bg.attributes.position
        for i in range(p.count):
            p.setZ(i, -0.09 * p.getX(i) * p.getX(i))
        bg.computeVertexNormals()
        tex = K.getCard('promo_%s' % hero, {'osd': False})
        tint = '#' + THREE.Color(0.82, 0.8, 0.86).getHexString()
        back = Mesh(bg, M.basic(tint, {'map': tex, 'fog': False}))
        back.name = 'set_back_%s' % hero
        back.position.set(0, 1.75, -2.0)
        root.add(back)
        # floor per show
        if hero == 'roxy':
            floorMat = M.basic('#ffffff', {'map': discoFloor(), 'fog': False})
        elif hero == 'duke':
            floorMat = M.toon('#ffffff', {'rough': 0.45, 'rim': 0.1, 'map': checker('#2A2E5A', '#3A4FA0')})
        elif hero == 'penny':
            floorMat = M.toon('#6E7684', {'rough': 0.38, 'metal': 0.55, 'rim': 0.2})
        else:
            floorMat = M.toon('#ffffff', {'rough': 0.6, 'rim': 0.1, 'map': K.tex.wood('#B07A45', {'planks': 5})})
        floor = Mesh(THREE.CircleGeometry(3.2, 40), floorMat)
        floor.name = 'set_floor_%s' % hero
        floor.rotation.x = -PI / 2
        floor.receiveShadow = True
        floor.scale.set(1.3, 1, 1)
        root.add(floor)
    root.add(goldBadge(game))
    return root


def discoFloor():
    """menu.js _discoFloor (256 x 256, repeat 2 x 2; menu.gd animates the offset)."""
    c = canvas(256, 256)
    x = c.getContext('2d')
    cols = ['#FF4FA0', '#5FE3FF', '#FFD23A', '#52D24A', '#E3662B', '#D64FD6', '#3A58E4']
    for j in range(8):
        for i in range(8):
            x.fillStyle = '#2A1830' if (i + j) % 3 == 0 else cols[(i * 3 + j * 5) % len(cols)]
            x.fillRect(i * 32 + 1, j * 32 + 1, 30, 30)
    t = canvas_texture(c, 'menu_disco', True)
    t.repeat.set(2, 2)
    return t


def checker(a, b):
    """menu.js _checker (128 x 128, repeat 5 x 5)."""
    c = canvas(128, 128)
    x = c.getContext('2d')
    for j in range(4):
        for i in range(4):
            x.fillStyle = a if (i + j) % 2 else b
            x.fillRect(i * 32, j * 32, 32, 32)
    t = canvas_texture(c, 'menu_checker_%s_%s' % (a[1:], b[1:]), True)
    t.repeat.set(5, 5)
    return t


def goldBadge(game):
    """menu.js _goldBadge: the medal (menu.gd pins it on the hero's torso / neck slot)."""
    c = canvas(128, 128)
    x = c.getContext('2d')
    gr = x.createRadialGradient(50, 44, 6, 64, 64, 62)
    gr.addColorStop(0, '#FFF1A0')
    gr.addColorStop(0.6, '#E8B84A')
    gr.addColorStop(1, '#8A5A18')
    x.fillStyle = gr
    x.beginPath()
    x.arc(64, 64, 60, 0, 7)
    x.fill()
    x.lineWidth = 6
    x.strokeStyle = '#6A4010'
    x.stroke()
    x.font = '64px %s' % FONTS_HUD
    x.textAlign = 'center'
    x.textBaseline = 'middle'
    x.fillStyle = '#6A3A10'
    x.fillText('13', 64, 68)
    t = canvas_texture(c, 'menu_gold_badge')
    m = Mesh(THREE.CircleGeometry(0.06, 24),
             game.mats.toon('#ffffff', {'map': t, 'rough': 0.3, 'metal': 0.4, 'rim': 0.4, 'keepColor': True}))
    m.name = 'goldBadge'
    return m


def _assets():
    game = K.Game()
    return {'room': buildRoom(game), 'sets': buildSets(game)}


# ------------------------------------------------------------------------------------------ export
def build(save_blend=False, only=None, godot=None):
    """Builds the menu runtime assets into godot/assets/runtime/menu/. Returns the written paths."""
    from dalib import export as EX
    out_dir = OUT_DIR if godot is None else os.path.join(godot, 'assets', 'runtime', 'menu')
    os.makedirs(out_dir, exist_ok=True)
    written = []
    for name, root in _assets().items():
        if only and name not in only:
            continue
        path = os.path.join(out_dir, name + '.glb')
        blend = os.path.join(_BLENDER, 'out', 'runtime_menu_%s.blend' % name) if save_blend else None
        EX.export_graph(root, path, root_name=root.name, save_blend=blend)
        written.append(path)
        print('[runtime/menu] %s' % path)
    return written


if __name__ == '__main__':
    args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
    build(save_blend='--save-blend' in args)
