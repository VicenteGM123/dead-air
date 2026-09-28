"""DEAD AIR — static meshes the Sign-Off ending built at runtime (SPEC §4/§5), exported as Blender assets.

Port of the static geometry of src/game/ending.js (the kid's popcorn bowl, Telly's side-arm hatch, the portrait's
backdrop and stage floor), line by line against dalib.scene / dalib.three_geo. The Godot module
(godot/scripts/game/ending.gd) duplicates the nodes by name and gives them the JS materials itself (game.mats.toon,
the arm's material, the promo card). One GLB: godot/assets/runtime/ending/ending.glb with the top-level nodes

    bowl             _buildKid: 'bowl_shell' (SphereGeometry(0.12, 18, 10, 0, TAU, PI/2, PI/2), scale (1, 0.7, 1),
                     red toon, double-sided) + 22 'popcorn_<i>' puffs (IcosahedronGeometry(0.022, 1)) in the JS spiral
    tellyHatch       _attachSideArm: 'tellyHatch_hole' (CircleGeometry(0.066, 24), vertex colour #150C12) and
                     'tellyHatch_ring' (TorusGeometry(0.07, 0.013, 8, 28), vertex colour #C8963C) (ending.gd turns the
                     group PI/2 about y and gives both the arm's vertex-coloured material)
    portrait_back    _buildPortrait: PlaneGeometry(6.4, 4.8) (the hero's promo card backdrop)
    portrait_floor   _buildPortrait: CircleGeometry(4, 40) (the stage floor; ending.gd lays it flat)

The kid (Skip's sculpted model), the 'z Z z' sprites (canvas), the portrait hero and every light are built by
ending.gd at runtime.

Run: python3 blender/build_all.py --only runtime   (build_all calls build(save_blend)), or standalone:
     cd /home/user/dead-air && python3 blender/runtime/ending.py [--save-blend]
"""
import math
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
_BLENDER = os.path.dirname(_HERE)
if _BLENDER not in sys.path:
    sys.path.insert(0, _BLENDER)

from dalib import kit as K  # noqa: E402
from dalib.kit import THREE  # noqa: E402
from dalib import tex as TEX  # noqa: E402
from dalib.scene import Group, Mesh, Material, DoubleSide  # noqa: E402

REPO = os.path.dirname(_BLENDER)
OUT_DIR = os.path.join(REPO, 'godot', 'assets', 'runtime', 'ending')
PI = math.pi
TAU = PI * 2


def basic(color, opts=None, **fields):
    """new THREE.MeshBasicMaterial({...}) (ending.gd creates the real one)."""
    return Material('basic', color, dict(opts or {}), type='MeshBasicMaterial', **fields)


def buildBowl(game):
    """_buildKid: popcorn bowl in the lap."""
    M = game.mats
    bowl = Group()
    bowl.name = 'bowl'
    b = Mesh(THREE.SphereGeometry(0.12, 18, 10, 0, TAU, PI * 0.5, PI * 0.5),
             M.toon('#E23B3B', {'rough': 0.35, 'rim': 0.3, 'keepColor': True, 'side': DoubleSide}))
    b.name = 'bowl_shell'
    b.scale.set(1, 0.7, 1)
    bowl.add(b)
    pop = M.toon('#FFF3D0', {'rough': 0.9, 'rim': 0.45, 'rimColor': '#FFE6A0', 'wrap': 0.8, 'keepColor': True})
    pg = THREE.IcosahedronGeometry(0.022, 1)
    for i in range(22):
        a, r = i * 2.4, 0.015 + (i % 6) * 0.015
        m = Mesh(pg, pop)
        m.name = 'popcorn_%d' % i
        m.position.set(math.cos(a) * r, -0.015 + (i % 3) * 0.012 + (0.1 - r) * 0.2, math.sin(a) * r)
        m.scale.setScalar(0.8 + (i % 4) * 0.12)
        bowl.add(m)
    return bowl


def buildHatch(game):
    """_attachSideArm: a dark hole in a brass ring, facing out of the wall; vertex-coloured like the arm."""
    armLike = game.mats.toon('#ffffff', {'rough': 0.42, 'keepColor': True, 'vertexColors': True})
    hatch = Group()
    hatch.name = 'tellyHatch'
    hole = Mesh(K.tint(THREE.CircleGeometry(0.066, 24), '#150C12'), armLike)
    hole.name = 'tellyHatch_hole'
    ring = Mesh(K.tint(THREE.TorusGeometry(0.07, 0.013, 8, 28), '#C8963C'), armLike)
    ring.name = 'tellyHatch_ring'
    hatch.add(hole)
    hatch.add(ring)
    return hatch


def buildPortraitBack(game):
    back = Mesh(THREE.PlaneGeometry(6.4, 4.8), basic('#3A2A5A', {'fog': False}, name='portraitBack'))
    back.name = 'portrait_back'
    return back


def buildPortraitFloor(game):
    floor = Mesh(THREE.CircleGeometry(4, 40), game.mats.toon('#6B4A3A', {'rough': 0.8, 'rim': 0.1, 'keepColor': True}))
    floor.name = 'portrait_floor'
    floor.receiveShadow = True
    return floor


def _assets():
    game = K.Game()
    root = Group()
    root.name = 'ending'
    for part in (buildBowl(game), buildHatch(game), buildPortraitBack(game), buildPortraitFloor(game)):
        root.add(part)
    return {'ending': root}


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
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out, 'runtime_ending_%s.blend' % name))
    return path


def build(save_blend=False, only=None):
    """Builds the ending runtime asset into godot/assets/runtime/ending/. Returns the written paths."""
    written = []
    for name, root in _assets().items():
        if only and name not in only:
            continue
        root.name = name
        path = os.path.join(OUT_DIR, name + '.glb')
        _export_glb(root, name, path, save_blend)
        written.append(path)
        print('[runtime/ending] %s' % path)
    return written


if __name__ == '__main__':
    args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
    build(save_blend='--save-blend' in args)
