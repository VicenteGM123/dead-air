"""DEAD AIR — static meshes BARON VON STATIC's code built at runtime (SPEC §4/§5), exported as Blender assets.

Port of the static geometry of src/actors/boss.js, line by line against the three.js-like graph (dalib.scene), the
prop kit (dalib.kit, same function names as src/props/kit.js) and the exact three geometry port (dalib.three_geo).
The Godot module (godot/scripts/actors/boss.gd) loads the meshes by node name and builds everything that animates or
changes every frame itself (the rubber-glass screen with the animated 'baron' card, the halo / dot / line sprites, the
cape cloth, the static tornado, the sweep beam + fan, the DY wall of static, the static fog discs). Each asset is one
GLB in godot/assets/runtime/boss/:

    baron_head.glb     _buildHead(): prop root 'baron_head' (K.prop, finished with K.finish + AO like the JS):
                       pillowy walnut carcass, puffy lid, brass pinstripe bands, cream bezel with the screen window,
                       dark liner, the control column (chrome channel / volume knobs with pointer bars and brass rings,
                       the 'CH 0' label, brass speaker grille + bars), back panel with vents, brass swivel collar,
                       chrome antenna dome and the two telescoping antenna horns 'antennaR' / 'antennaL' (noMerge
                       groups at their pivots, chrome segments + 'antennaR_tip' / 'antennaL_tip' glow spheres);
                       'baron_crack' (the crack_overlay plane, hidden; noMerge/noAO/noOcclude) and
                       'baron_shimmer_head' (_buildShimmer's box at the head centre, hidden)
    baron_fx.glb       'baron_ball' (the static ball, IcosahedronGeometry(0.28, 2)) and 'baron_shimmer_cone'
                       (_buildShimmer's ConeGeometry(0.6, 3.2, 16, 1, true); boss.gd rotates / places it)
    baron_standin.glb  _standInBody() meshes (used only when the baked 'boss_baron' character is missing), in their
                       joint frames: 'standin_torso' (base), 'standin_upper_L/R' (shoulders), 'standin_fore_L/R'
                       (elbows), 'standin_glove_L/R' (hands)

Run: python3 blender/build_all.py --only runtime   (build_all calls build(save_blend)), or standalone:
     cd /home/user/dead-air && python3 blender/runtime/boss.py [--save-blend]
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
from dalib.scene import Group, Mesh, Material, AdditiveBlending  # noqa: E402

REPO = os.path.dirname(_BLENDER)
OUT_DIR = os.path.join(REPO, 'godot', 'assets', 'runtime', 'boss')
PI = math.pi
TAU = PI * 2


def basic(color, opts=None, **fields):
    """new THREE.MeshBasicMaterial({...}) (boss.gd creates these materials itself; the spec is the Blender look)."""
    return Material('basic', color, dict(opts or {}), type='MeshBasicMaterial', **fields)


# ------------------------------------------------------------------------------------------ the TV head
def buildHead(game):
    """_buildHead(): the walnut console-TV head. Local frame: origin at the neck, y up, front = -z. World units
    (1.6 x 1.3 x 1.2 m)."""
    W, H, D, Y0 = 1.6, 1.3, 1.2, 0.08
    CY = Y0 + H / 2
    SCR = dict(w=0.98, h=0.76, x=0.17, y=CY + 0.03)      # local +x = the viewer's left: screen left, controls right
    grp = K.prop('baron_head')
    kc = {'keepColor': True}
    walnut = K.mat(game, 'walnut', '#ffffff', dict(map=K.tex.wood(PAL.walnut, {'dark': 0.45}), **kc))
    cream = K.mat(game, 'plastic', '#EEDFC0', dict(rough=0.38, **kc))
    liner = K.mat(game, 'plastic', '#241A2C', dict(rough=0.3, **kc))
    chrome = K.mat(game, 'chrome', '#B9C1CB', kc)
    brass = K.mat(game, 'brass', '#C8963C', kc)
    backMat = K.mat(game, 'paint', '#3A2A22', kc)
    grille = K.mat(game, 'fabric', '#ffffff', dict(map=K.tex.weave('#B88A4A', {'pattern': 'cord'}), **kc))
    # carcass: a pillowy walnut box + a puffy lid overhang + a brass pinstripe band
    grp.add(K.m(K.cushion(W, H, D, {'r': 0.17, 'puff': 0.022, 'uv': 1.2}), walnut, {'pos': [0, CY, 0]}))
    grp.add(K.m(K.box(W + 0.05, 0.08, D + 0.05, 0.04, {'uv': 1.2, 'swap': True}), walnut, {'pos': [0, Y0 + H - 0.01, 0]}))
    for y in [Y0 + 0.07, Y0 + H - 0.075]:
        grp.add(K.m(K.box(W + 0.012, 0.018, D + 0.012, 0.008), brass, {'pos': [0, y, 0]}))
    # cream bezel (hole = the screen window) + dark liner tunnel
    bez = K.roundRect(1.48, 1.14, 0.12)
    hole = THREE.Path()
    hx, hy, hw, hh, hr = -SCR['x'], SCR['y'] - CY, SCR['w'] / 2 + 0.03, SCR['h'] / 2 + 0.03, 0.1
    hole.moveTo(hx - hw + hr, hy - hh)
    hole.lineTo(hx + hw - hr, hy - hh)
    hole.quadraticCurveTo(hx + hw, hy - hh, hx + hw, hy - hh + hr)
    hole.lineTo(hx + hw, hy + hh - hr)
    hole.quadraticCurveTo(hx + hw, hy + hh, hx + hw - hr, hy + hh)
    hole.lineTo(hx - hw + hr, hy + hh)
    hole.quadraticCurveTo(hx - hw, hy + hh, hx - hw, hy + hh - hr)
    hole.lineTo(hx - hw, hy - hh + hr)
    hole.quadraticCurveTo(hx - hw, hy - hh, hx - hw + hr, hy - hh)
    bez.holes.append(hole)
    bezel = K.m(K.extrude(bez, 0.05, {'bevel': 0.018}), cream, {'pos': [0, CY, -D / 2 + 0.035], 'rot': [0, PI, 0]})
    grp.add(bezel)
    grp.add(K.m(K.box(SCR['w'] + 0.1, SCR['h'] + 0.1, 0.06, 0.09), liner, {'pos': [SCR['x'], SCR['y'], -D / 2 - 0.005]}))
    # (the screen: rubber glass over the animated 'baron' card, built by boss.gd at (SCR.x, SCR.y, -D/2 - 0.045))
    crackMat = basic('#ffffff', {'map': K.getCard('crack_overlay'), 'transparent': True, 'depthWrite': False,
                                 'toneMapped': False}, name='baronCrack')
    crack = Mesh(THREE.PlaneGeometry(SCR['w'] * 0.98, SCR['h'] * 0.98), crackMat)
    crack.name = 'baron_crack'
    crack.position.set(SCR['x'], SCR['y'], -D / 2 - 0.13)
    crack.rotation.y = PI
    crack.renderOrder = 3
    crack.visible = False
    crack.castShadow = False
    crack.userData.noMerge = True
    crack.userData.noAO = True
    crack.userData.noOcclude = True
    grp.add(crack)
    # control column: channel knob (stuck on "0"), volume knob, the CH 0 window, a brass speaker grille
    kx, kz = -0.53, -D / 2 - 0.02

    def knob(r, y):
        k = K.m(K.cyl(r * 0.92, r, 0.075, {'bevel': 0.015, 'seg': 24}), chrome, {'pos': [kx, y, kz], 'rot': [-PI / 2, 0, 0]})
        grp.add(k)
        grp.add(K.m(K.box(r * 0.2, r * 1.3, 0.03, 0.006), liner, {'pos': [kx, y + r * 0.2, kz - 0.085]}))
        grp.add(K.m(K.cyl(r * 1.18, r * 1.18, 0.012, {'bevel': 0.004, 'seg': 24}), brass,
                    {'pos': [kx, y, kz + 0.01], 'rot': [-PI / 2, 0, 0]}))
    knob(0.12, CY + 0.2)
    knob(0.085, CY - 0.06)
    lab = K.m(THREE.PlaneGeometry(0.2, 0.1),
              K.mat(game, 'plastic', '#ffffff', dict(map=K.tex.label('CH 0', {'bg': '#161826', 'fg': '#5CFF6E', 'accent': '#3A2A22',
                                                                          'w': 256, 'h': 128, 'wear': 0}), rough=0.3, **kc)),
              {'pos': [kx, CY + 0.4, -D / 2 - 0.028], 'rot': [0, PI, 0]})
    grp.add(lab)
    grp.add(K.m(K.box(0.27, 0.27, 0.03, 0.03, {'uv': 4}), grille, {'pos': [kx, CY - 0.33, -D / 2 - 0.012]}))
    for i in range(5):
        grp.add(K.m(K.box(0.27, 0.012, 0.012, 0.004), brass, {'pos': [kx, CY - 0.45 + i * 0.06, -D / 2 - 0.03]}))
    # back panel with vents; brass swivel collar under the cabinet
    grp.add(K.m(K.box(1.28, 0.98, 0.05, 0.03), backMat, {'pos': [0, CY, D / 2 + 0.01]}))
    for i in range(6):
        grp.add(K.m(K.box(0.9, 0.035, 0.03, 0.012), liner, {'pos': [0, CY - 0.28 + i * 0.1, D / 2 + 0.035]}))
    grp.add(K.m(K.cyl(0.27, 0.33, 0.1, {'bevel': 0.02, 'seg': 24}), brass, {'pos': [0, Y0 - 0.1, 0.02]}))
    # antenna horns: telescoping chrome rods from a dome, glowing tips (the halo sprites are boss.gd's)
    top = Y0 + H + 0.03
    grp.add(K.m(THREE.SphereGeometry(0.14, 20, 10, 0, TAU, 0, PI / 2), chrome, {'pos': [0, top, 0.14]}))
    tipMat = game.mats.glow('#D46BFF', 3.2)
    tips = []
    for s in [-1, 1]:
        ant = Group()
        ant.name = 'antennaR' if s < 0 else 'antennaL'
        ant.position.set(s * 0.05, top + 0.05, 0.14)
        ant.rotation.z = -s * 0.62
        ant.rotation.x = 0.1
        ant.userData.noMerge = True
        segs = [[0, 0.5, 0.042], [0.47, 0.95, 0.031], [0.92, 1.36, 0.022]]
        for a, b, r in segs:
            ant.add(K.m(K.cyl(r * 0.9, r, b - a, {'bevel': r * 0.4, 'seg': 10}), chrome, {'pos': [0, a, 0]}))
            ant.add(K.m(THREE.SphereGeometry(r * 1.25, 10, 8), chrome, {'pos': [0, a, 0]}))
        tip = Mesh(THREE.SphereGeometry(0.09, 16, 12), tipMat)
        tip.name = ant.name + '_tip'
        tip.position.set(0, 1.42, 0)
        tip.castShadow = False
        tip.userData.noAO = True
        tip.userData.noOcclude = True
        ant.add(tip)
        grp.add(ant)
        tips.append(tip)
    K.finish(game, grp, {'ao': {'res': 40, 'strength': 0.75, 'floor': False, 'height': 0,
                                'skip': lambda mm: mm is crack or any(mm is t for t in tips)}})
    # _buildShimmer(): the off-air shimmer box (a 10 % additive copy of the cabinet), hidden until OFF-AIR
    shimmer = basic('#B9C6FF', {'transparent': True, 'opacity': 0.1, 'blending': AdditiveBlending, 'depthWrite': False,
                                'fog': False}, name='baronShimmer')
    hb = Mesh(K.box(W, H, D, 0.15), shimmer)
    hb.position.set(0, CY, 0)
    hb.visible = False
    hb.castShadow = False
    hb.name = 'baron_shimmer_head'
    grp.add(hb)
    return grp


# ------------------------------------------------------------------------------------------ fight FX meshes
def buildFx(game):
    """_ballPool() geometry + _buildShimmer()'s cone (materials are boss.gd shaders)."""
    g = Group()
    g.name = 'baron_fx'
    ballMat = basic('#B574FF', {'fog': False}, name='baronBall')
    ball = Mesh(THREE.IcosahedronGeometry(0.28, 2), ballMat)
    ball.name = 'baron_ball'
    ball.castShadow = False
    g.add(ball)
    shimmer = basic('#B9C6FF', {'transparent': True, 'opacity': 0.1, 'blending': AdditiveBlending, 'depthWrite': False,
                                'fog': False}, name='baronShimmer')
    cone = Mesh(THREE.ConeGeometry(0.6, 3.2, 16, 1, True), shimmer)
    cone.name = 'baron_shimmer_cone'
    cone.castShadow = False
    g.add(cone)
    return g


# ------------------------------------------------------------------------------------------ stand-in body
def buildStandIn(game):
    """_standInBody(): the primitive body parts, each in its joint's frame (boss.gd parents them to the joints)."""
    tux = game.mats.toon('#1A1A2E', {'rough': 0.45, 'keepColor': True, 'rim': 0.4, 'rimColor': '#C9A0FF'})
    white = game.mats.toon('#F7F4EC', {'rough': 0.5, 'keepColor': True})
    g = Group()
    g.name = 'baron_standin'
    g.add(K.m(THREE.SphereGeometry(0.22, 20, 14), tux, {'pos': [0, 0.3, 0], 'scale': [1.15, 1.5, 0.75], 'name': 'standin_torso'}))
    for s in ['L', 'R']:
        g.add(K.m(THREE.CapsuleGeometry(0.07, 0.25, 6, 10), tux,
                  {'pos': [-0.075 if s == 'L' else 0.075, -0.15, 0], 'name': 'standin_upper_' + s}))
        g.add(K.m(THREE.CapsuleGeometry(0.06, 0.22, 6, 10), tux,
                  {'pos': [-0.045 if s == 'L' else 0.045, -0.14, -0.02], 'name': 'standin_fore_' + s}))
        g.add(K.m(THREE.SphereGeometry(0.12, 16, 12), white, {'pos': [0, -0.1, 0], 'name': 'standin_glove_' + s}))
    return g


def _assets():
    game = K.Game()
    return {
        'baron_head': buildHead(game),
        'baron_fx': buildFx(game),
        'baron_standin': buildStandIn(game),
    }


# ------------------------------------------------------------------------------------------ export
def _export_glb(root, name, path, save_blend=False):
    """Exports one graph as a GLB. Uses the kit's exporter (dalib.export) when present, else the SPEC §5.3 settings
    directly (fresh empty scene, dalib.scene.to_blender with the kit's texture files, bpy glTF export)."""
    try:
        from dalib import export as EX  # noqa: F401
    except Exception:
        EX = None
    for fn_name in ('export_graph', 'export_root', 'export_object'):
        fn = getattr(EX, fn_name, None) if EX is not None else None
        if callable(fn):
            try:
                return fn(root, path, name=name, save_blend=save_blend)
            except TypeError:
                pass
    import bpy
    from dalib import scene as SC
    bpy.ops.wm.read_factory_settings(use_empty=True)
    names = SC.assign_names(root, name)
    SC.to_blender(root, names, TEX.texture_file, name)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    kw = dict(filepath=path, export_format='GLB', export_extras=True, export_yup=True, export_apply=True,
              export_attributes=True, export_texcoords=True, export_normals=True, export_materials='EXPORT',
              export_image_format='AUTO')
    try:
        bpy.ops.export_scene.gltf(**kw, export_vertex_color='ACTIVE', export_all_vertex_colors=True)
    except TypeError:
        bpy.ops.export_scene.gltf(**kw)
    if save_blend:
        out = os.path.join(_BLENDER, 'out')
        os.makedirs(out, exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out, 'runtime_boss_%s.blend' % name))
    return path


def build(save_blend=False, only=None):
    """Builds every boss runtime asset into godot/assets/runtime/boss/. Returns the written paths."""
    written = []
    for name, root in _assets().items():
        if only and name not in only:
            continue
        root.name = name
        path = os.path.join(OUT_DIR, name + '.glb')
        _export_glb(root, name, path, save_blend)
        written.append(path)
        print('[runtime/boss] %s' % path)
    return written


if __name__ == '__main__':
    args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
    build(save_blend='--save-blend' in args)
