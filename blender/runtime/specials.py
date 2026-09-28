"""DEAD AIR — static meshes the special zombie types built at runtime (SPEC §4/§5), exported as Blender assets.

Ports of the static geometry of src/actors/types/sock_hopper.js, forecaster.js and big_shot.js, line by line against
the three.js-like graph (dalib.scene) and the exact three geometry port (dalib.three_geo / dalib.geo). The Godot
modules (godot/scripts/actors/types/*.gd) load the meshes by node name and create the materials with the same JS
factory calls; the material specs here (SPEC §5.5) give the assets their look in Blender. Each asset is one GLB in
godot/assets/runtime/specials/:

    sock_button.glb        sock_hopper.js buttonAssets: the death button, CylinderGeometry(0.03, 0.03, 0.01, 18)
                           with materials [side, cap, cap] -> two meshes 'sock_button_side' (group 0) and
                           'sock_button_cap' (groups 1 + 2) under the group 'sock_button' (the Godot module joins
                           them back into one two-surface mesh)
    fc_umbrella.glb        forecaster.js buildUmbrella: group 'fc_umbrella' -> 'canopy' (y 0.42: 'canopyMesh' lathe
                           with the polka-dot texture, chrome 'tip'), chrome 'shaft', wooden 'hook'
    fc_disc.glb            forecaster.js baseModel: the lightning shadow disc 'fc_shadowDisc' (CircleGeometry(1, 40)
                           rotated flat)
    fc_rainbow.glb         forecaster.js rainbowGeometry: 'fc_rainbow', six half-torus bands merged with LINEAR
                           vertex colours (mergeList)
    bs_lens.glb            big_shot.js buildModel: lens glow disc 'bs_lensGlow' (CircleGeometry(0.098, 28)), iris
                           'bs_blades' (bladeGeometry: six boxes merged by mergeSimple), flash card 'bs_flare'
                           (PlaneGeometry(1, 1))
    bs_plug.glb            big_shot.js getPlugAssets / buildModel: group 'bs_plug' -> 'bs_plugBody' (geo.roundedBox),
                           'bs_prongs' (two boxes merged), 'bs_halo' (PlaneGeometry(0.32, 0.32) at z -0.08)

Canvas textures (drawn with dalib/canvas2d.py, same code as the JS canvases; the Godot modules redraw them at
runtime with DACanvas, SPEC §6): sock button cap, forecaster shadow disc and umbrella dots, big shot flare.
Per-frame meshes (the lightning ribbons, the Big Shot cable tube and film spaghetti) are built by the GDScript
modules. The JS art=0 / missing-bake placeholder models are not ported (SPEC §0.2).

Run: python3 blender/build_all.py --only runtime   (build_all calls build(save_blend)), or standalone:
     cd /home/user/dead-air && python3 blender/runtime/specials.py [--save-blend]
"""
import math
import os
import sys

import numpy as np

_HERE = os.path.dirname(os.path.abspath(__file__))
_BLENDER = os.path.dirname(_HERE)
if _BLENDER not in sys.path:
    sys.path.insert(0, _BLENDER)

from dalib import three_geo as THREE  # noqa: E402
from dalib import geo  # noqa: E402
from dalib import tex as TEX  # noqa: E402
from dalib.scene import Group, Mesh, Material, DoubleSide, AdditiveBlending  # noqa: E402

REPO = os.path.dirname(_BLENDER)
OUT_DIR = os.path.join(REPO, 'godot', 'assets', 'runtime', 'specials')
PI = math.pi
LAYER_ZOMBIES = 1   # Config.LAYERS.ZOMBIES
RAINBOW = ['#E4473A', '#F08A24', '#F4E03A', '#52D24A', '#3FA8E0', '#8A5AD6']


# ------------------------------------------------------------------------------------------ materials (game.mats)
def toon(color, opts=None):
    """game.mats.toon(color, opts) -> the spec the Godot side rebuilds."""
    return Material('toon', color, dict(opts or {}))


def basic(color, opts=None, **fields):
    """new THREE.MeshBasicMaterial({...}) (color: hex; LINEAR multipliers go in opts['colorScale'] for Blender's
    preview only — the Godot modules create these materials themselves)."""
    o = dict(opts or {})
    return Material('basic', color, o, type='MeshBasicMaterial', **fields)


# ------------------------------------------------------------------------------------------ canvas textures
def buttonCapTexture():
    """sock_hopper.js buttonAssets: the 64x64 button cap."""
    def draw(x, w, h, rand):
        x.fillStyle = '#E8A92E'
        x.fillRect(0, 0, 64, 64)
        x.strokeStyle = '#B97A14'
        x.lineWidth = 6
        x.beginPath()
        x.arc(32, 32, 24, 0, PI * 2)
        x.stroke()
        x.fillStyle = '#6B4A12'
        for dx, dy in [[-7, -7], [7, -7], [-7, 7], [7, 7]]:
            x.beginPath()
            x.arc(32 + dx, 32 + dy, 4, 0, PI * 2)
            x.fill()
    t = TEX.canvasTex('specials.sockButtonCap', 64, 64, draw, {'repeat': False})
    return t


def discTexture():
    """forecaster.js discTexture: the telegraph shadow circle (256)."""
    def draw(g, w, h, rand):
        grd = g.createRadialGradient(128, 128, 10, 128, 128, 124)
        grd.addColorStop(0, 'rgba(30,22,52,0.78)')
        grd.addColorStop(0.72, 'rgba(34,26,62,0.62)')
        grd.addColorStop(0.86, 'rgba(60,44,110,0.5)')
        grd.addColorStop(0.9, 'rgba(210,200,255,0.95)')
        grd.addColorStop(0.95, 'rgba(160,140,255,0.55)')
        grd.addColorStop(1, 'rgba(120,100,220,0)')
        g.fillStyle = grd
        g.fillRect(0, 0, 256, 256)
        # dashed inner ring
        g.strokeStyle = 'rgba(200,190,255,0.55)'
        g.lineWidth = 5
        g.setLineDash([14, 12])
        g.beginPath()
        g.arc(128, 128, 70, 0, PI * 2)
        g.stroke()
    return TEX.canvasTex('specials.fcDisc', 256, 256, draw, {'repeat': False})


def dotsTexture():
    """forecaster.js dotsTexture: the polka-dot umbrella canopy (256x128, wrapS repeat, repeat (2, 1))."""
    def draw(g, w, h, rand):
        g.fillStyle = '#E23B3B'
        g.fillRect(0, 0, 256, 128)
        g.fillStyle = '#FFF4DE'
        for y in range(5):
            for x in range(9):
                g.beginPath()
                g.arc(x * 30 + (y % 2) * 15 + 6, y * 28 + 12, 6.5 - y * 0.6, 0, PI * 2)
                g.fill()
        # scalloped darker hem band
        g.fillStyle = '#B8262A'
        g.fillRect(0, 118, 256, 10)
    t = TEX.canvasTex('specials.fcDots', 256, 128, draw, {'repeat': True})
    t.wrapS = TEX.RepeatWrapping
    t.wrapT = TEX.ClampToEdgeWrapping
    t.repeat.set(2, 1)
    return t


def flareTexture():
    """big_shot.js flareTexture: the flash / plug halo sprite (128)."""
    def draw(g, w, h, rand):
        grd = g.createRadialGradient(64, 64, 0, 64, 64, 64)
        grd.addColorStop(0, 'rgba(255,255,255,1)')
        grd.addColorStop(0.2, 'rgba(255,250,235,0.9)')
        grd.addColorStop(0.5, 'rgba(255,236,200,0.35)')
        grd.addColorStop(1, 'rgba(255,230,190,0)')
        g.fillStyle = grd
        g.fillRect(0, 0, 128, 128)
        # 6-point star streaks
        g.globalCompositeOperation = 'lighter'
        g.strokeStyle = 'rgba(255,255,255,0.55)'
        g.lineWidth = 3
        for i in range(3):
            a = (i * PI) / 3
            g.beginPath()
            g.moveTo(64 - math.cos(a) * 62, 64 - math.sin(a) * 62)
            g.lineTo(64 + math.cos(a) * 62, 64 + math.sin(a) * 62)
            g.stroke()
    return TEX.canvasTex('specials.bsFlare', 128, 128, draw, {'repeat': False})


# ------------------------------------------------------------------------------------------ geometry helpers
def _subset(src, groups):
    """A copy of `src` keeping only the triangles of the given draw groups (three multi-material groups)."""
    g = src.clone()
    idx = np.asarray(src.index.array).reshape(-1)
    keep = []
    for gr in src.groups:
        if gr.materialIndex in groups:
            keep.append(idx[int(gr.start):int(gr.start) + int(gr.count)])
    g.setIndex(np.concatenate(keep).astype(np.int64).tolist())
    g.clearGroups()
    return g


def mergeList(lst):
    """forecaster.js mergeList: tiny local merge (position/normal/uv/color, indexed)."""
    pos, nrm, col, uv, idx = [], [], [], [], []
    ov = 0
    for g in lst:
        n = g.attributes.position.count
        pos.append(np.asarray(g.attributes.position.array).reshape(-1, 3))
        nrm.append(np.asarray(g.attributes.normal.array).reshape(-1, 3))
        if g.attributes.color:
            col.append(np.asarray(g.attributes.color.array).reshape(-1, 3))
        else:
            col.append(np.ones((n, 3)))
        if g.attributes.uv:
            uv.append(np.asarray(g.attributes.uv.array).reshape(-1, 2))
        else:
            uv.append(np.zeros((n, 2)))
        idx.append(np.asarray(g.index.array).reshape(-1) + ov)
        ov += n
    out = THREE.Geometry()
    out.setAttribute('position', THREE.Float32BufferAttribute(np.concatenate(pos).ravel().tolist(), 3))
    out.setAttribute('normal', THREE.Float32BufferAttribute(np.concatenate(nrm).ravel().tolist(), 3))
    out.setAttribute('color', THREE.Float32BufferAttribute(np.concatenate(col).ravel().tolist(), 3))
    out.setAttribute('uv', THREE.Float32BufferAttribute(np.concatenate(uv).ravel().tolist(), 2))
    out.setIndex(np.concatenate(idx).astype(np.int64).tolist())
    return out


def mergeSimple(lst):
    """big_shot.js mergeSimple: position/normal, indexed."""
    pos, nrm, idx = [], [], []
    ov = 0
    for g in lst:
        pos.append(np.asarray(g.attributes.position.array).reshape(-1, 3))
        nrm.append(np.asarray(g.attributes.normal.array).reshape(-1, 3))
        idx.append(np.asarray(g.index.array).reshape(-1) + ov)
        ov += g.attributes.position.count
    out = THREE.Geometry()
    out.setAttribute('position', THREE.Float32BufferAttribute(np.concatenate(pos).ravel().tolist(), 3))
    out.setAttribute('normal', THREE.Float32BufferAttribute(np.concatenate(nrm).ravel().tolist(), 3))
    out.setIndex(np.concatenate(idx).astype(np.int64).tolist())
    return out


def _zombieLayer(root):
    def f(o):
        if getattr(o, 'isMesh', False):
            o.layers.set(LAYER_ZOMBIES)
    root.traverse(f)


# ------------------------------------------------------------------------------------------ sock_hopper.js
def buildButton():
    """buttonAssets(): CylinderGeometry(0.03, 0.03, 0.01, 18) with [side, cap, cap]; mesh 'sock:button'."""
    tex = buttonCapTexture()
    side = toon('#D99A22', {'rough': 0.35, 'keepColor': True, 'rim': 0.4})
    cap = toon('#ffffff', {'rough': 0.35, 'keepColor': True, 'map': tex, 'rim': 0.3, 'name': 'sockButtonCap'})
    buttonGeo = THREE.CylinderGeometry(0.03, 0.03, 0.01, 18)
    grp = Group()
    grp.name = 'sock_button'
    ms = Mesh(_subset(buttonGeo, [0]), side)
    ms.name = 'sock_button_side'
    mc = Mesh(_subset(buttonGeo, [1, 2]), cap)
    mc.name = 'sock_button_cap'
    for m in (ms, mc):
        m.castShadow = False
        grp.add(m)
    _zombieLayer(grp)
    return grp


# ------------------------------------------------------------------------------------------ forecaster.js
def buildUmbrella():
    """umbrellaAssets() + buildUmbrella()."""
    prof = [[0.0, 0.34], [0.12, 0.33], [0.25, 0.29], [0.36, 0.22], [0.44, 0.13], [0.5, 0.03], [0.51, 0.0]]
    U = {
        'canopy': THREE.LatheGeometry([THREE.Vector2(x, y) for x, y in prof], 16),
        'canopyMat': toon('#ffffff', {'map': dotsTexture(), 'side': DoubleSide, 'rough': 0.5, 'rim': 0.4,
                                      'keepColor': True, 'name': 'fcUmbrella'}),
        'shaft': THREE.CylinderGeometry(0.011, 0.011, 0.82, 8),
        'hook': THREE.TorusGeometry(0.05, 0.012, 6, 14, PI),
        'tip': THREE.SphereGeometry(0.022, 10, 8),
        'wood': toon('#8A5A36', {'rough': 0.45, 'keepColor': True}),
        'chrome': toon('#D9DDE3', {'metal': 1, 'rough': 0.2, 'keepColor': True}),
    }
    g = Group()
    g.name = 'fc_umbrella'
    canopy = Group()
    canopy.name = 'canopy'
    canopy.position.y = 0.42
    g.add(canopy)
    cm = Mesh(U['canopy'], U['canopyMat'])
    cm.name = 'canopyMesh'
    canopy.add(cm)
    tip = Mesh(U['tip'], U['chrome'])
    tip.name = 'tip'
    tip.position.y = 0.36
    canopy.add(tip)
    shaft = Mesh(U['shaft'], U['chrome'])
    shaft.name = 'shaft'
    g.add(shaft)
    hook = Mesh(U['hook'], U['wood'])
    hook.name = 'hook'
    hook.position.set(0.05, -0.41, 0)
    hook.rotation.z = PI
    g.add(hook)

    def f(o):
        if getattr(o, 'isMesh', False):
            o.castShadow = False
            o.layers.set(LAYER_ZOMBIES)
    g.traverse(f)
    return g


def buildDisc():
    """baseModel(): the shadow disc (CircleGeometry(1, 40).rotateX(-PI / 2)), MeshBasicMaterial with the disc map."""
    discMat = basic('#ffffff', {'map': discTexture(), 'transparent': True, 'depthWrite': False, 'fog': False,
                                'polygonOffset': True, 'polygonOffsetFactor': -4, 'polygonOffsetUnits': -4},
                    name='fcShadowDisc')
    disc = Mesh(THREE.CircleGeometry(1, 40).rotateX(-PI / 2), discMat)
    disc.name = 'fc_shadowDisc'
    disc.renderOrder = 2
    disc.castShadow = False
    disc.layers.set(LAYER_ZOMBIES)
    return disc


def buildRainbow():
    """rainbowGeometry(): six half-torus bands with vertex colours (LINEAR, like THREE.Color(hex))."""
    parts = []
    for i, col in enumerate(RAINBOW):
        g = THREE.TorusGeometry(0.62 - i * 0.07, 0.036, 6, 36, PI)
        c = THREE.Color(col)
        n = g.attributes.position.count
        arr = np.tile(np.array([c.r, c.g, c.b], dtype=np.float64), n)
        g.setAttribute('color', THREE.Float32BufferAttribute(arr.tolist(), 3))
        parts.append(g)
    rbMat = basic('#ffffff', {'vertexColors': True, 'transparent': True, 'opacity': 1, 'depthWrite': False,
                              'fog': False, 'side': DoubleSide})
    rb = Mesh(mergeList(parts), rbMat)
    rb.name = 'fc_rainbow'
    rb.castShadow = False
    rb.layers.set(LAYER_ZOMBIES)
    return rb


# ------------------------------------------------------------------------------------------ big_shot.js
def bladeGeometry():
    parts = []
    for i in range(6):
        a = (i / 6) * PI * 2
        g = THREE.BoxGeometry(0.075, 0.016, 0.004)
        g.translate(0, 0.075, 0)
        g.rotateZ(a + 0.5)
        parts.append(g)
    return mergeSimple(parts)


def buildLens():
    """buildModel(): lens glow disc, iris blades, flash card (the lens-local offsets are set by the module)."""
    grp = Group()
    grp.name = 'bs_lens'
    glowMat = basic('#3F4A59', {'transparent': True, 'opacity': 0.95, 'depthWrite': False, 'fog': False},
                    name='bsLensGlow')
    glow = Mesh(THREE.CircleGeometry(0.098, 28), glowMat)
    glow.name = 'bs_lensGlow'
    glow.castShadow = False
    grp.add(glow)
    bladeMat = toon('#14171F', {'rough': 0.35, 'metal': 0.4, 'keepColor': True, 'rim': 0.2})
    blades = Mesh(bladeGeometry(), bladeMat)
    blades.name = 'bs_blades'
    blades.castShadow = False
    grp.add(blades)
    flareMat = basic('#ffffff', {'map': flareTexture(), 'transparent': True, 'depthWrite': False, 'fog': False},
                     name='bsFlare', blending=AdditiveBlending)
    flare = Mesh(THREE.PlaneGeometry(1, 1), flareMat)
    flare.name = 'bs_flare'
    flare.renderOrder = 5
    flare.castShadow = False
    grp.add(flare)
    _zombieLayer(grp)
    return grp


def buildPlug():
    """getPlugAssets() + the plug group of buildModel()."""
    P = {
        'body': geo.roundedBox(0.075, 0.062, 0.1, 0.02, 2),
        'prong': mergeSimple([THREE.BoxGeometry(0.012, 0.028, 0.05).translate(s * 0.018, 0, -0.07) for s in (-1, 1)]),
        'rubber': toon('#26232A', {'rough': 0.6, 'keepColor': True, 'rim': 0.35}),
    }
    plug = Group()
    plug.name = 'bs_plug'
    body = Mesh(P['body'], P['rubber'])
    body.name = 'bs_plugBody'
    plug.add(body)
    prongMat = basic('#FFB23A', {}, name='bsProng')
    prongs = Mesh(P['prong'], prongMat)
    prongs.name = 'bs_prongs'
    plug.add(prongs)
    haloMat = basic('#FFA030', {'map': flareTexture(), 'transparent': True, 'depthWrite': False, 'fog': False},
                    blending=AdditiveBlending)
    halo = Mesh(THREE.PlaneGeometry(0.32, 0.32), haloMat)
    halo.name = 'bs_halo'
    halo.position.z = -0.08
    plug.add(halo)

    def f(o):
        if getattr(o, 'isMesh', False):
            o.castShadow = False
    plug.traverse(f)
    _zombieLayer(plug)
    return plug


def _assets():
    return {
        'sock_button': buildButton(),
        'fc_umbrella': buildUmbrella(),
        'fc_disc': buildDisc(),
        'fc_rainbow': buildRainbow(),
        'bs_lens': buildLens(),
        'bs_plug': buildPlug(),
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
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out, 'runtime_specials_%s.blend' % name))
    return path


def build(save_blend=False, only=None):
    """Builds every specials runtime asset into godot/assets/runtime/specials/. Returns the written paths."""
    written = []
    for name, root in _assets().items():
        if only and name not in only:
            continue
        root.name = name
        path = os.path.join(OUT_DIR, name + '.glb')
        _export_glb(root, name, path, save_blend)
        written.append(path)
        print('[runtime/specials] %s' % path)
    return written


if __name__ == '__main__':
    args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
    build(save_blend='--save-blend' in args)
