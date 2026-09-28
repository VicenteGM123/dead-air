"""DEAD AIR — static meshes the ScreenManager built at runtime (SPEC §4/§5), exported as a Blender asset.

Port of the static geometry of src/game/screens.js _buildInsert(): the Uplink insert studio (the set the 'satellite'
source films, layer 3, at [200, 0, 200] in the scene). godot/scripts/game/screens.gd instantiates the GLB under its
'insert_studio' node (placed at INSERT.pos) and adds the turntable pivot, the insert camera and the LIVE VIA
SATELLITE super itself. One GLB: godot/assets/runtime/screens/insert_studio.glb with the root 'insert_studio' and

    insert_dome    cyclorama dome: SphereGeometry(7, 32, 16), rotation.y PI/2, y 1, MeshBasicMaterial (BackSide,
                   fog false) with the 512x256 canvas: deep blue night gradient, a soft 24-ray starburst behind the
                   turntable, 90 stars
    insert_drum    turntable: chrome drum CylinderGeometry(0.62, 0.7, 0.9, 40), y 0.45
    insert_top     red top CylinderGeometry(0.66, 0.66, 0.08, 40), y 0.94
    insert_rim     glowing rim TorusGeometry(0.66, 0.018, 8, 48), rotation.x PI/2, y 0.98 (glow crtCyan 2.2)
    insert_floor   floor disc CircleGeometry(3.2, 40), rotation.x -PI/2

Run: python3 blender/build_all.py --only runtime   (build_all calls build(save_blend)), or standalone:
     cd /home/user/dead-air && python3 blender/runtime/screens.py [--save-blend]
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
from dalib.canvas2d import Canvas  # noqa: E402
from dalib.scene import Group, Mesh  # noqa: E402

REPO = os.path.dirname(_BLENDER)
OUT_DIR = os.path.join(REPO, 'godot', 'assets', 'runtime', 'screens')
PI = math.pi
TAU = PI * 2


def domeTexture():
    """The cyclorama canvas (screens.js _buildInsert, line by line)."""
    cv = Canvas(512, 256)
    c = cv.getContext('2d')
    grd = c.createLinearGradient(0, 0, 0, 256)
    grd.addColorStop(0, '#0B0A2A')
    grd.addColorStop(0.55, '#1B2A7A')
    grd.addColorStop(0.72, '#2F5BD3')
    grd.addColorStop(1, '#101030')
    c.fillStyle = grd
    c.fillRect(0, 0, 512, 256)
    c.save()
    c.translate(256, 150)
    for i in range(24):
        c.rotate(TAU / 24)
        c.fillStyle = 'rgba(127,231,255,0.10)' if i % 2 else 'rgba(255,95,162,0.08)'
        c.beginPath()
        c.moveTo(0, 0)
        c.lineTo(-18, -300)
        c.lineTo(18, -300)
        c.closePath()
        c.fill()
    c.restore()
    for i in range(90):
        x, y, r = (i * 97.13) % 512, (i * 41.7) % 120, (1.8 if i % 7 == 0 else 0.9)
        c.fillStyle = 'rgba(255,244,214,%s)' % _num(0.35 + (i % 5) * 0.12)
        c.beginPath()
        c.arc(x, y, r, 0, TAU)
        c.fill()
    tex = THREE.CanvasTexture(cv)
    tex.colorSpace = THREE.SRGBColorSpace
    tex.key = 'screens_insert_cyclorama'
    tex.name = tex.key
    return tex


def _num(v):
    """JS number -> string (template literal formatting)."""
    s = repr(float(v))
    return s[:-2] if s.endswith('.0') else s


def buildInsert(game):
    """_buildInsert(): the static set (set-local coordinates; screens.gd places it at INSERT.pos)."""
    M = game.mats
    st = Group()
    st.name = 'insert_studio'
    dome = Mesh(THREE.SphereGeometry(7, 32, 16),
                THREE.MeshBasicMaterial({'map': domeTexture(), 'side': THREE.BackSide, 'fog': False}))
    dome.name = 'insert_dome'
    dome.rotation.y = PI / 2
    dome.position.y = 1
    st.add(dome)
    # turntable: chrome drum, red bumper ring, a glowing rim
    drum = Mesh(THREE.CylinderGeometry(0.62, 0.7, 0.9, 40), M.toon('#C9CED8', {'metal': 0.7, 'rough': 0.28, 'keepColor': True}))
    drum.name = 'insert_drum'
    drum.position.y = 0.45
    top = Mesh(THREE.CylinderGeometry(0.66, 0.66, 0.08, 40), M.toon('#E23B3B', {'rough': 0.35, 'keepColor': True}))
    top.name = 'insert_top'
    top.position.y = 0.94
    rim = Mesh(THREE.TorusGeometry(0.66, 0.018, 8, 48), M.glow(PAL.crtCyan, 2.2))
    rim.name = 'insert_rim'
    rim.rotation.x = PI / 2
    rim.position.y = 0.98
    floor = Mesh(THREE.CircleGeometry(3.2, 40), M.toon('#1B1E4A', {'rough': 0.2, 'keepColor': True}))
    floor.name = 'insert_floor'
    floor.rotation.x = -PI / 2
    for o in (drum, top, rim, floor):
        st.add(o)
    return st


def _assets():
    game = K.Game()
    return {'insert_studio': buildInsert(game)}


def build(save_blend=False, only=None):
    """Builds the screens runtime asset into godot/assets/runtime/screens/. Returns the written paths."""
    from dalib import export as EX
    written = []
    for name, root in _assets().items():
        if only and name not in only:
            continue
        path = os.path.join(OUT_DIR, name + '.glb')
        os.makedirs(OUT_DIR, exist_ok=True)
        blend = os.path.join(_BLENDER, 'out', 'runtime_screens_%s.blend' % name) if save_blend else None
        EX.export_graph(root, path, root_name=name, save_blend=blend)
        written.append(path)
        print('[runtime/screens] %s' % path)
    return written


if __name__ == '__main__':
    args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
    build(save_blend='--save-blend' in args)
