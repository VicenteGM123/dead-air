"""DEAD AIR — static meshes the weapons / FX systems built at runtime (SPEC §4/§5), exported as Blender assets.

Ports (line by line, three.js coordinates, dalib.three_geo / dalib.geo / dalib.kit materials):
  * src/fx/fx.js       the 'star' particle mesh: extrudeShape(starShape(1, 0.45), 0.25, 0.08) (fx.gd draws it as a
                       MultiMesh with its own additive material; the exported material is a plain placeholder).
  * src/game/weaponModels.js placeholder(id) — the chunky primitive stand-in used when the prop library has no model
                       (one GLB per LOOKS id; the body box is named 'body': weapon_models.gd swaps it to the
                       Chromacast material for upgraded placeholders, like the JS `upgraded ? chromacast(...)`),
                       plus the buildGrenadeModel / buildTeleModel fallbacks.
Output in godot/assets/runtime/weapons_fx/:
    fx_star.glb, placeholder_<id>.glb (revolver_38 pump_37 mp7 m16a1 m60 zapper boom_mic chroma_key),
    fallback_grenade.glb, fallback_tele.glb
(The FX canvas textures — muzzle star, rings, flash star, decals — are drawn at runtime with the Canvas2D emulation.)

Run: python3 blender/build_all.py --only runtime   (build_all calls build(save_blend)), or standalone:
     cd /home/user/dead-air && python3 blender/runtime/weapons_fx.py [--save-blend]
"""
import math
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
_BLENDER = os.path.dirname(_HERE)
if _BLENDER not in sys.path:
    sys.path.insert(0, _BLENDER)

from dalib import three_geo as THREE  # noqa: E402
from dalib import geo  # noqa: E402
from dalib import kit as K  # noqa: E402
from dalib.scene import Group, Mesh, Material  # noqa: E402
from dalib.pal import PAL  # noqa: E402

REPO = os.path.dirname(_BLENDER)
OUT_DIR = os.path.join(REPO, 'godot', 'assets', 'runtime', 'weapons_fx')
PI = math.pi


# ------------------------------------------------------------------------------------------ fx.js
def starShape(r=1, inner=0.45, n=5):
    s = THREE.Shape()
    for i in range(n * 2 + 1):
        a = (i / (n * 2)) * PI * 2 + PI / 2
        rr = r * inner if i % 2 else r
        if i == 0:
            s.moveTo(math.cos(a) * rr, math.sin(a) * rr)
        else:
            s.lineTo(math.cos(a) * rr, math.sin(a) * rr)
    return s


def buildStar():
    mat = Material('basic', '#ffffff', {}, type='MeshBasicMaterial', name='fx_star')
    root = Group()
    m = Mesh(geo.extrudeShape(starShape(1, 0.45), 0.25, 0.08), mat)
    m.name = 'star'
    m.castShadow = False
    m.receiveShadow = False
    root.add(m)
    return root


# ------------------------------------------------------------------------------------------ weaponModels.js
LOOKS = {
    'revolver_38': {'len': 0.3, 'body': '#3A4A6B', 'stock': PAL.walnut, 'h': 0.08},
    'pump_37': {'len': 0.78, 'body': '#3A4A6B', 'stock': PAL.teak, 'h': 0.07},
    'mp7': {'len': 0.42, 'body': '#62703A', 'stock': '#4B5530', 'h': 0.09},
    'm16a1': {'len': 0.82, 'body': '#39405C', 'stock': '#62868A', 'h': 0.09},
    'm60': {'len': 1.0, 'body': '#5E6838', 'stock': '#3A3A2A', 'h': 0.12},
    'zapper': {'len': 0.4, 'body': '#EBDCBC', 'stock': PAL.walnut, 'h': 0.06},
    'boom_mic': {'len': 1.1, 'body': '#C9CED6', 'stock': '#2A2230', 'h': 0.05},
    'chroma_key': {'len': 0.55, 'body': '#D6D0C4', 'stock': '#5A3A22', 'h': 0.14},
}


def placeholder(id, game):
    M = game.mats
    look = LOOKS.get(id) or LOOKS['revolver_38']
    g = Group()

    def tone(c):
        return M.toon(c, {'keepColor': True, 'rough': 0.45})
    L, h = look['len'], look['h']
    g.add(K.m(geo.roundedBox(0.05, 0.12, 0.06, 0.02, 2), tone(look['stock']), {'pos': [0, -0.03, 0.01], 'rot': [-0.25, 0, 0]}))
    body = K.m(geo.roundedBox(0.07, h, L * 0.45, 0.025, 2), tone(look['body']), {'pos': [0, 0.06, -L * 0.12], 'name': 'body'})
    g.add(body)
    g.add(K.m(geo.cylinder(0.022, 0.022, L * 0.5, 12), tone('#3A4A6B'), {'pos': [0, 0.07, -L * 0.55], 'rot': [PI / 2, 0, 0]}))
    if L > 0.6:
        g.add(K.m(geo.roundedBox(0.06, 0.09, L * 0.3, 0.025, 2), tone(look['stock']), {'pos': [0, 0.03, L * 0.2]}))
    g.userData.muzzle = [0, 0.07, -L * 0.8]
    g.userData.leftHand = [0, 0.03, -L * 0.45] if L > 0.5 else [-0.03, -0.02, 0]
    return g


def fallbackGrenade(game):
    g = Group()
    g.add(K.m(geo.capsule(0.035, 0.07, 6, 10), game.mats.glass('#DDEEFF', {'opacity': 0.4}), {'pos': [0, 0.07, 0]}))
    g.add(K.m(geo.sphere(0.018, 8, 6), game.mats.glow('#FF8A2E', 3), {'pos': [0, 0.07, 0]}))
    g.userData.parts = {}
    return g


def fallbackTele(game):
    g = Group()
    g.add(K.m(geo.roundedBox(0.2, 0.16, 0.16, 0.03, 2), game.mats.toon('#F08A2E', {'keepColor': True}), {'pos': [0, 0.08, 0]}))
    g.add(K.m(geo.roundedBox(0.14, 0.1, 0.01, 0.01, 1), game.mats.glow('#CFE8FF', 1.2), {'pos': [0, 0.09, -0.081]}))
    g.userData.parts = {}
    return g


# ------------------------------------------------------------------------------------------ export
def _export_glb(root, name, path, save_blend=False):
    """One graph -> GLB through the kit exporter (dalib.export.export_graph: SPEC §5.3 settings)."""
    from dalib import export as EX
    blend = os.path.join(_BLENDER, 'out', 'runtime_weapons_fx_%s.blend' % name) if save_blend else None
    EX.export_graph(root, path, root_name=name, save_blend=blend)
    return path


def _out_dir():
    """godot/assets/runtime/weapons_fx (follows build_all --godot DIR through dalib.export.GODOT)."""
    try:
        from dalib import export as EX
        return os.path.join(EX.GODOT, 'assets', 'runtime', 'weapons_fx')
    except Exception:
        return OUT_DIR


def graphs():
    game = K.Game()
    out = {'fx_star': buildStar,
           'fallback_grenade': lambda: fallbackGrenade(game),
           'fallback_tele': lambda: fallbackTele(game)}
    for id in LOOKS:
        out['placeholder_' + id] = (lambda i: (lambda: placeholder(i, game)))(id)
    return out


def build(save_blend=False, only=None, **_kw):
    """Builds every weapons/fx runtime asset into godot/assets/runtime/weapons_fx/. Returns the written paths."""
    out_dir = _out_dir()
    os.makedirs(out_dir, exist_ok=True)
    written = []
    for name, make in graphs().items():
        if only and name not in only:
            continue
        root = make()
        root.name = name
        path = os.path.join(out_dir, name + '.glb')
        _export_glb(root, name, path, save_blend)
        written.append(path)
        print('[runtime/weapons_fx] %s' % path)
    return written


if __name__ == '__main__':
    args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
    build(save_blend='--save-blend' in args)
