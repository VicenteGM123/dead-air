"""DEAD AIR — static meshes / textures the zombies system built at runtime (SPEC §4/§5), exported as Blender assets.

Ports of src/actors/zombies.js starGeometry() / ticketTexture() (+ the Tickets quad) and of the two canvas eye textures
of src/actors/zombieTypes.js (makeStarTexture / makeNormalEyeTexture), line by line against the three.js-like graph
(dalib.scene), the exact three geometry port (dalib.three_geo) and the Canvas 2D emulation (dalib.canvas2d).
Output in godot/assets/runtime/zombies/:

    star.glb         the stun / death star (StarRings pool mesh): extruded 5-point star, depth 0.016, bevel 0.006
                     (1 segment), centred. Material 'zombieStars' = MeshBasicMaterial marqueeGold x 1.8 (linear);
                     zombies.gd draws the MultiMesh with its own copy of that material.
    ticket.glb       the fluttering ticket stub (Tickets pool mesh): PlaneGeometry(0.1, 0.055) + the 256 x 140 canvas
                     '13 / ADMIT ONE' (material 'zombieTicket': MeshBasicMaterial, colour 0.9 linear, double sided).
    ticket.png       the same canvas, stored top-down (the runtime material samples it with the quad's UVs).
    eye_star.png     ONE TAKE star eyes (128 x 128): two stacked stars on plum.
    eye_normal.png   feed-camera plain eye (128 x 128): white, brown iris, pupil, highlight.

Run: python3 blender/build_all.py --only runtime   (build_all calls build(save_blend)), or standalone:
     cd /home/user/dead-air && python3 blender/runtime/zombies.py [--save-blend]
"""
import math
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
_BLENDER = os.path.dirname(_HERE)
if _BLENDER not in sys.path:
    sys.path.insert(0, _BLENDER)

from dalib import three_geo as THREE  # noqa: E402
from dalib.scene import Group, Mesh, Material, DoubleSide  # noqa: E402
from dalib.canvas2d import Canvas  # noqa: E402
from dalib.pal import PAL  # noqa: E402

REPO = os.path.dirname(_BLENDER)
OUT_DIR = os.path.join(REPO, 'godot', 'assets', 'runtime', 'zombies')
PI = math.pi


# ------------------------------------------------------------------------------------------ zombies.js FX pools
def starGeometry():
    s = THREE.Shape()
    for i in range(10):
        a = PI / 2 + (i * PI) / 5
        r = 0.024 if i % 2 else 0.058
        if i == 0:
            s.moveTo(math.cos(a) * r, math.sin(a) * r)
        else:
            s.lineTo(math.cos(a) * r, math.sin(a) * r)
    s.closePath()
    g = THREE.ExtrudeGeometry(s, {'depth': 0.016, 'bevelEnabled': True, 'bevelThickness': 0.006, 'bevelSize': 0.006,
                                  'bevelSegments': 1})
    g.center()
    return g


def drawTicket(g):
    g.fillStyle = '#F6E7C8'
    g.fillRect(0, 0, 256, 140)
    g.strokeStyle = '#E23B3B'
    g.lineWidth = 7
    g.strokeRect(14, 14, 228, 112)
    g.fillStyle = '#C9B48E'
    y = 24
    while y < 120:
        g.beginPath()
        g.arc(88, y, 2.5, 0, PI * 2)
        g.fill()
        y += 12
    g.fillStyle = '#E23B3B'
    g.font = '900 64px "Arial Black", Impact, sans-serif'
    g.textAlign = 'center'
    g.textBaseline = 'middle'
    g.fillText('13', 52, 74)
    g.fillStyle = '#2B2238'
    g.font = '900 32px "Arial Black", Impact, sans-serif'
    g.fillText('ADMIT', 166, 52)
    g.fillText('ONE', 166, 92)


def ticketTexture():
    c = Canvas(256, 140)
    drawTicket(c.getContext('2d'))
    return c


# ------------------------------------------------------------------------------------------ zombieTypes.js looks
def makeStarTexture():
    c = Canvas(128, 128)
    g = c.getContext('2d')
    g.fillStyle = '#3B2340'
    g.fillRect(0, 0, 128, 128)

    def star(r0, r1, col):
        g.beginPath()
        for i in range(10):
            a = -PI / 2 + (i * PI) / 5
            r = r1 if i % 2 else r0
            g.lineTo(64 + math.cos(a) * r, 64 + math.sin(a) * r)
        g.closePath()
        g.fillStyle = col
        g.fill()

    star(60, 26, '#FFC23A')
    star(40, 17, '#FFF3B0')
    return c


def makeNormalEyeTexture():
    c = Canvas(128, 128)
    g = c.getContext('2d')
    g.fillStyle = '#F7F4EC'
    g.fillRect(0, 0, 128, 128)
    g.fillStyle = '#5A3A22'
    g.beginPath(); g.arc(64, 64, 26, 0, PI * 2); g.fill()
    g.fillStyle = '#1B1420'
    g.beginPath(); g.arc(64, 64, 13, 0, PI * 2); g.fill()
    g.fillStyle = '#ffffff'
    g.beginPath(); g.arc(56, 55, 6, 0, PI * 2); g.fill()
    return c


def _lin2srgb_hex(v):
    c = v * 12.92 if v <= 0.0031308 else 1.055 * v ** (1 / 2.4) - 0.055
    n = max(0, min(255, int(round(c * 255))))
    return '#%02x%02x%02x' % (n, n, n)


# ------------------------------------------------------------------------------------------ graphs
def buildStar():
    mat = Material('basic', PAL.marqueeGold, {},
                   type='MeshBasicMaterial', name='zombieStars', extra={'colorScale': 1.8})
    root = Group()
    m = Mesh(starGeometry(), mat)
    m.name = 'star'
    m.castShadow = False
    root.add(m)
    return root


def buildTicket():
    from dalib.tex import Texture
    t = Texture(ticketTexture(), 'zombies.ticket', False, 'z')     # THREE.CanvasTexture: clamp to edge
    opts = {'side': 'double', 'map': t}
    mat = Material('basic', _lin2srgb_hex(0.9), opts, type='MeshBasicMaterial', name='zombieTicket', side=DoubleSide)
    root = Group()
    m = Mesh(THREE.PlaneGeometry(0.1, 0.055), mat)
    m.name = 'ticket'
    m.castShadow = False
    root.add(m)
    return root


def _export_glb(root, name, path, save_blend=False):
    """One graph -> GLB (the kit's dalib.export when present, else SPEC §5.3 settings directly)."""
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
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out, 'runtime_zombies_%s.blend' % name))
    return path


def build(save_blend=False, only=None):
    """Builds every zombies runtime asset into godot/assets/runtime/zombies/. Returns the written paths."""
    os.makedirs(OUT_DIR, exist_ok=True)
    written = []
    pngs = {'ticket.png': ticketTexture, 'eye_star.png': makeStarTexture, 'eye_normal.png': makeNormalEyeTexture}
    for fname, make in pngs.items():
        if only and fname.split('.')[0] not in only:
            continue
        path = os.path.join(OUT_DIR, fname)
        make().save_png(path)
        written.append(path)
        print('[runtime/zombies] %s' % path)
    graphs = {'star': buildStar, 'ticket': buildTicket}
    for name, make in graphs.items():
        if only and name not in only:
            continue
        root = make()
        root.name = name
        path = os.path.join(OUT_DIR, name + '.glb')
        _export_glb(root, name, path, save_blend)
        written.append(path)
        print('[runtime/zombies] %s' % path)
    return written


if __name__ == '__main__':
    args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
    build(save_blend='--save-blend' in args)
