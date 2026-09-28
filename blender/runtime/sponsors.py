"""DEAD AIR — static meshes the sponsors / perks systems built at runtime (SPEC §4/§5), exported as Blender assets.

Ports of the gag-prop builders of src/game/sponsors.js (the commercial pantomimes) and of the referee whistle of
src/game/perks.js (_dropWhistle), line by line against the three.js-like graph (dalib.scene) and the exact three
geometry port (dalib.three_geo). Each asset is one GLB in godot/assets/runtime/sponsors/:

    gag_peel.glb    buildPeel     banana peel (4 petals)
    gag_spoon.glb   buildSpoon    chrome spoon + the green gelatin cube (node 'jelly')
    gag_glove.glb   buildGlove    boxing glove on a scissor lattice: node 'glove' (fist, thumb, cuff, lace),
                                  14 slats 'slat_0'..'slat_13' (unit-length boxes laid out at runtime by
                                  sponsors.gd setExtend) and the spring box 'box'
    gag_pot.glb     buildPot      glass coffee pot (glass body, coffee, orange collar + lid, knob, handle)
    gag_brush.glb   buildBrush    striped toothbrush with a blob of paste
    gag_gun.glb     fallbackGun   the placeholder revolver (used only when weapons.buildModel is missing)
    whistle.glb     _dropWhistle  the Replay-Ade referee whistle (body, mouth piece, gold cord loop)

Materials are the JS factory specs (SPEC §5.5): toon(g, color, o) = g.mats.toon(color, {keepColor, rough: 0.4, ...o})
-> Material('toon', color, opts); the coffee pot body is g.mats.glass('#FFE8C8', {opacity: 0.35}).
The gag meshes cast shadows (sponsors.js _ensureGags sets castShadow = true on every gag mesh).

Run: python3 blender/build_all.py --only runtime   (build_all calls build(save_blend)), or standalone:
     cd /home/user/dead-air && python3 blender/runtime/sponsors.py [--save-blend]
"""
import math
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
_BLENDER = os.path.dirname(_HERE)
if _BLENDER not in sys.path:
    sys.path.insert(0, _BLENDER)

from dalib import three_geo as THREE  # noqa: E402
from dalib.scene import Group, Mesh, Material, DoubleSide  # noqa: E402,F401

REPO = os.path.dirname(_BLENDER)
OUT_DIR = os.path.join(REPO, 'godot', 'assets', 'runtime', 'sponsors')
TAU = math.pi * 2


# ------------------------------------------------------------------------------------------ materials (g.mats)
class _Mats:
    """The two JS material factories the gag builders call (the spec objects the Godot side rebuilds)."""

    def toon(self, color, opts=None):
        return Material('toon', color, dict(opts or {}))

    def glass(self, color, opts=None):
        return Material('glass', color, dict(opts or {}), type='MeshPhysicalMaterial', transparent=True)


class _Game:
    def __init__(self):
        self.mats = _Mats()


def toon(g, color, o=None):
    opts = {'keepColor': True, 'rough': 0.4}
    opts.update(o or {})
    return g.mats.toon(color, opts)


def _mesh(geo, mat, name=''):
    m = Mesh(geo, mat)
    if name:
        m.name = name
    return m


# ------------------------------------------------------------------------------------------ gag props (sponsors.js)
def buildPeel(g):
    grp = Group()
    yel = toon(g, '#F6D23A', {'rough': 0.45})
    inner = toon(g, '#FFF3C4', {'rough': 0.6})
    tip = toon(g, '#6B4A22')
    base = Mesh(THREE.SphereGeometry(0.045, 14, 10), yel)
    base.scale.set(1, 0.75, 1)
    base.position.y = 0.03
    grp.add(base)
    for i in range(4):
        a = (i / 4) * TAU + 0.4
        petal = Group()
        skin = Mesh(THREE.SphereGeometry(1, 12, 8, 0, TAU, 0, math.pi / 2), yel)
        skin.scale.set(0.042, 0.018, 0.13)
        skin.position.set(0, 0.0, 0.1)
        skin.rotation.x = -0.18
        lining = Mesh(THREE.SphereGeometry(1, 12, 8, 0, TAU, 0, math.pi / 2), inner)
        lining.scale.set(0.034, 0.012, 0.11)
        lining.position.set(0, 0.006, 0.1)
        lining.rotation.x = -0.18
        petal.add(skin, lining)
        petal.rotation.y = a
        petal.position.y = 0.02
        grp.add(petal)
    t = Mesh(THREE.CylinderGeometry(0.012, 0.018, 0.06, 8), tip)
    t.position.y = 0.075
    t.rotation.z = 0.3
    grp.add(t)
    return grp


def buildSpoon(g):
    grp = Group()
    chrome = toon(g, '#C8D0DA', {'metal': 1, 'rough': 0.2})
    handle = Mesh(THREE.CylinderGeometry(0.008, 0.012, 0.2, 8), chrome)
    handle.position.y = -0.08
    bowl = Mesh(THREE.SphereGeometry(0.035, 14, 8, 0, TAU, math.pi / 2, math.pi / 2), chrome)
    bowl.scale.set(1, 0.45, 1.35)
    bowl.position.y = 0.035
    jelly = Mesh(THREE.BoxGeometry(0.045, 0.04, 0.045), toon(g, '#18B54E', {
        'transparent': True, 'opacity': 0.85, 'rough': 0.1, 'emissive': '#0A6A2A', 'emissiveIntensity': 0.6}))
    jelly.name = 'jelly'
    jelly.position.y = 0.05
    jelly.rotation.y = 0.5
    grp.add(handle, bowl, jelly)
    return {'grp': grp, 'jelly': jelly}


def buildGlove(g):
    grp = Group()
    red = toon(g, '#E23B3B', {'rough': 0.3})
    white = toon(g, '#F4F1E8', {'rough': 0.5})
    wood = toon(g, '#B07A45', {'rough': 0.6})
    glove = Group()
    glove.name = 'glove'
    fist = Mesh(THREE.SphereGeometry(0.13, 18, 14), red)
    fist.scale.set(1.15, 0.95, 1)
    thumb = Mesh(THREE.SphereGeometry(0.055, 12, 10), red)
    thumb.position.set(-0.02, 0.075, 0.07)
    thumb.scale.set(1.2, 0.8, 0.9)
    cuff = Mesh(THREE.CylinderGeometry(0.085, 0.095, 0.1, 16).rotateZ(math.pi / 2), white)
    cuff.position.x = 0.15
    lace = Mesh(THREE.BoxGeometry(0.1, 0.012, 0.02), white)
    lace.position.set(0.1, 0.06, 0.08)
    glove.add(fist, thumb, cuff, lace)
    grp.add(glove)
    # scissor lattice (the accordion): pairs of crossing slats, laid out by setExtend()
    slatGeo = THREE.BoxGeometry(1, 0.018, 0.025)
    slats = []
    for i in range(14):
        s = Mesh(slatGeo, wood)
        s.name = 'slat_%d' % i
        grp.add(s)
        slats.append(s)
    box = Mesh(THREE.BoxGeometry(0.22, 0.26, 0.22), toon(g, '#2F5BD3', {'rough': 0.45}))
    box.name = 'box'
    grp.add(box)
    return {'grp': grp, 'glove': glove, 'slats': slats, 'box': box}


def buildPot(g):
    grp = Group()
    glass = g.mats.glass('#FFE8C8', {'opacity': 0.35}) if hasattr(g.mats, 'glass') else \
        toon(g, '#FFE8C8', {'transparent': True, 'opacity': 0.35})
    coffee = toon(g, '#4A2410', {'rough': 0.2})
    orange = toon(g, '#E3662B', {'rough': 0.35})
    black = toon(g, '#2A2230', {'rough': 0.4})
    prof = [[0, 0], [0.07, 0.005], [0.085, 0.04], [0.085, 0.08], [0.06, 0.13], [0.045, 0.15], [0.05, 0.17]]
    body = Mesh(THREE.LatheGeometry([THREE.Vector2(x, y) for x, y in prof], 20), glass)
    fill = Mesh(THREE.LatheGeometry([THREE.Vector2(x, y) for x, y in
                                     [[0, 0.004], [0.066, 0.008], [0.08, 0.04], [0.08, 0.075], [0, 0.075]]], 18), coffee)
    collar = Mesh(THREE.TorusGeometry(0.052, 0.014, 8, 18).rotateX(math.pi / 2), orange)
    collar.position.y = 0.155
    lid = Mesh(THREE.CylinderGeometry(0.03, 0.05, 0.03, 16), orange)
    lid.position.y = 0.185
    knob = Mesh(THREE.SphereGeometry(0.014, 8, 6), black)
    knob.position.y = 0.205
    handle = Mesh(THREE.TorusGeometry(0.045, 0.012, 8, 14, math.pi * 1.2), black)
    handle.position.set(0.085, 0.11, 0)
    handle.rotation.z = -math.pi * 0.6
    grp.add(body, fill, collar, lid, knob, handle)
    return grp


def buildBrush(g):
    grp = Group()
    cols = ['#E23B3B', '#F7F3EA', '#2F5BD3']
    for i in range(6):
        seg = Mesh(THREE.BoxGeometry(0.02, 0.035, 0.014), toon(g, cols[i % 3], {'rough': 0.3}))
        seg.position.y = -0.1 + i * 0.035
        grp.add(seg)
    head = Mesh(THREE.BoxGeometry(0.022, 0.06, 0.012), toon(g, '#F7F3EA', {'rough': 0.3}))
    head.position.y = 0.13
    bristles = Mesh(THREE.BoxGeometry(0.02, 0.05, 0.022), toon(g, '#7FE7FF', {'rough': 0.5}))
    bristles.position.set(0, 0.13, 0.016)
    paste = Mesh(THREE.CapsuleGeometry(0.008, 0.035, 4, 8).rotateX(math.pi / 2), toon(g, '#FFFFFF', {'rough': 0.3}))
    paste.rotation.x = math.pi / 2
    paste.position.set(0, 0.13, 0.03)
    grp.add(head, bristles, paste)
    return grp


def fallbackGun(g):
    grp = Group()
    steel = toon(g, '#5A6068', {'metal': 0.8, 'rough': 0.3})
    wood = toon(g, '#7A4A2A')
    barrel = Mesh(THREE.BoxGeometry(0.03, 0.035, 0.2), steel)
    barrel.position.set(0, 0.03, -0.1)
    grip = Mesh(THREE.BoxGeometry(0.03, 0.1, 0.045), wood)
    grip.position.set(0, -0.03, 0.01)
    grip.rotation.x = 0.3
    grp.add(barrel, grip)
    return grp


# ------------------------------------------------------------------------------------------ perks.js _dropWhistle
def buildWhistle(g):
    chrome = g.mats.toon('#B8C0CA', {'metal': 1, 'rough': 0.25, 'keepColor': True})
    grp = Group()
    body = Mesh(THREE.CylinderGeometry(0.03, 0.03, 0.05, 14).rotateZ(math.pi / 2), chrome)
    mouth = Mesh(THREE.BoxGeometry(0.045, 0.018, 0.06), chrome)
    mouth.position.set(0, 0.02, -0.04)
    cord = Mesh(THREE.TorusGeometry(0.05, 0.006, 5, 16), g.mats.toon('#F4C81E', {'keepColor': True}))
    cord.position.set(0, 0.06, 0)
    grp.add(body, mouth, cord)
    return grp


# ------------------------------------------------------------------------------------------ assets
def _gags(g):
    """name -> root Group of every asset (the same objects the JS built; castShadow as sponsors.js sets it)."""
    out = {
        'gag_peel': buildPeel(g),
        'gag_spoon': buildSpoon(g)['grp'],
        'gag_glove': buildGlove(g)['grp'],
        'gag_pot': buildPot(g),
        'gag_brush': buildBrush(g),
        'gag_gun': fallbackGun(g),
    }
    for root in out.values():
        root.traverse(lambda m: setattr(m, 'castShadow', True) if getattr(m, 'isMesh', False) else None)
        root.traverse(lambda m: setattr(m, 'receiveShadow', False) if getattr(m, 'isMesh', False) else None)
    # the whistle: default shadow flags (the JS never set them: a Mesh does not cast)
    out['whistle'] = buildWhistle(g)
    return out


def _export_glb(root, name, path, save_blend=False):
    """Exports one graph as a GLB. Uses the kit's exporter (dalib.export) when present, else the SPEC §5.3 settings
    directly (fresh empty scene, dalib.scene.to_blender, bpy glTF export)."""
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
    SC.to_blender(root, names, None, name)
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
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out, 'runtime_sponsors_%s.blend' % name))
    return path


def build(save_blend=False, only=None):
    """Builds every sponsors runtime asset into godot/assets/runtime/sponsors/. Returns the written paths."""
    g = _Game()
    written = []
    for name, root in _gags(g).items():
        if only and name not in only:
            continue
        root.name = name
        path = os.path.join(OUT_DIR, name + '.glb')
        _export_glb(root, name, path, save_blend)
        written.append(path)
        print('[runtime/sponsors] %s' % path)
    return written


if __name__ == '__main__':
    args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
    build(save_blend='--save-blend' in args)
