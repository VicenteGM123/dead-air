"""DEAD AIR — static meshes the wonder-weapon system (src/game/wonder.js) built at runtime (SPEC §4/§5).

Ports (line by line, three.js coordinates, dalib.three_geo / dalib.geo / dalib.kit materials) of wonder.js's geometry
builders and of the static groups it assembled from geo.* primitives. godot/scripts/game/wonder.gd loads them and
puts its own materials on them (the R.* materials of _buildResources: every mesh node carries userData.mat = the R key
in its "da" custom property; the exported materials are the same specs, for the Blender preview).

Output in godot/assets/runtime/wonder/:
  meshes.glb    one mesh node per wonder.js geometry resource (node name = the JS `res` key, identity transform):
                ring (RingGeometry(0.88, 1, 48)), ringBold (RingGeometry(0.7, 1, 48)), tumble (tumbleweedGeo()),
                gel (gelatinGeo()), blobGeo (geo.sphere(1, 20, 14)), puddle (blobShapeGeo(11)), puddleSheen
                (blobShapeGeo(23, 18)), squig (squiggleGeo()), flameOuter (flameGeo(1)), flameInner (flameGeo(0.62)),
                dot (geo.sphere(0.06, 12, 8)), cube (geo.roundedBox(1, 1, 1, 0.18, 2))
  battery.glb   the spent Zapper battery of _popBattery (cell + ink cap)
  gelatin.glb   the cooking gag's plate + head-shaped gelatin mold (nodes 'plate' and 'mold'; _gagCooking)
  bunny.glb     the nature gag's bunny (_buildBunny: root -> 'body' -> parts + 'earL' / 'earR' groups)

Run: python3 blender/build_all.py --only runtime   (build_all calls build(save_blend)), or standalone:
     cd /home/user/dead-air && python3 blender/runtime/wonder.py [--save-blend]
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
from dalib.rng import mulberry32  # noqa: E402

REPO = os.path.dirname(_BLENDER)
OUT_DIR = os.path.join(REPO, 'godot', 'assets', 'runtime', 'wonder')
PI = math.pi
TAU = PI * 2


def rng(seed):
    """wonder.js rng(seed): mulberry32."""
    return mulberry32(seed)


# ------------------------------------------------------------------------------------------ geometry builders
def tumbleweedGeo():
    r = rng(7)
    geos = []
    for k in range(10):
        u = THREE.Vector3(r() - 0.5, r() - 0.5, r() - 0.5).normalize()
        v = THREE.Vector3(r() - 0.5, r() - 0.5, r() - 0.5).cross(u).normalize()
        pts = []
        ph = r() * TAU
        rr = 0.3 + r() * 0.06
        for i in range(28):
            a = (i / 28) * TAU
            w = rr * (1 + 0.14 * math.sin(a * 3 + ph) + 0.06 * math.sin(a * 7 + k))
            pts.append(THREE.Vector3().addScaledVector(u, math.cos(a) * w).addScaledVector(v, math.sin(a) * w)
                       .add(THREE.Vector3(r() - 0.5, r() - 0.5, r() - 0.5).multiplyScalar(0.05)))
        geos.append(THREE.TubeGeometry(THREE.CatmullRomCurve3(pts, True), 56, 0.013 + r() * 0.008, 4, True))
    g = THREE.mergeGeometries(geos, False)
    return g


# A head-shaped, fluted gelatin mold (cooking gag), bottom at y=0, ~0.62 m tall.
def gelatinGeo():
    prof = []
    n = 22
    for i in range(n + 1):
        t = i / n
        y = t * 0.62
        if t < 0.12:
            rr = 0.26 + t * 0.5                        # flared base
        elif t < 0.3:
            rr = 0.31 - (t - 0.12) * 0.25              # first tier
        else:
            rr = 0.3 * math.sqrt(max(0, 1 - ((t - 0.3) / 0.7) ** 2)) * 1.02 + 0.001   # dome (the "head")
        prof.append(THREE.Vector2(max(0.001, rr), y))
    prof.append(THREE.Vector2(0.0001, 0.62))
    g = THREE.LatheGeometry(prof, 40)
    p = g.attributes.position
    for i in range(p.count):
        x, z, y = p.getX(i), p.getZ(i), p.getY(i)
        a = math.atan2(z, x)
        k = 1 + 0.07 * math.cos(a * 10) * min(1, y / 0.1) * (1 if y < 0.55 else 0.3)
        p.setX(i, x * k)
        p.setZ(i, z * k)
    g.computeVertexNormals()
    return g


def blobShapeGeo(seed, n=26):
    r = rng(seed)
    shape = THREE.Shape()
    ph = r() * TAU
    for i in range(n + 1):
        a = (i / n) * TAU
        rr = 1 + 0.12 * math.sin(a * 3 + ph) + 0.07 * math.sin(a * 5 + ph * 2) + ((r() - 0.5) * 0.06 if i < n else 0)
        x, y = math.cos(a) * rr, math.sin(a) * rr
        if i == 0:
            shape.moveTo(x, y)
        elif i == n:
            shape.closePath()
        else:
            shape.lineTo(x, y)
    g = THREE.ShapeGeometry(shape, 4)
    g.rotateX(-PI / 2)
    return g


def squiggleGeo():
    pts = []
    for i in range(17):
        t = i / 16
        pts.append(THREE.Vector3(math.sin(t * TAU * 1.5) * 0.045, math.cos(t * TAU * 1.5) * 0.02, (t - 0.5) * 0.34))
    return THREE.TubeGeometry(THREE.CatmullRomCurve3(pts), 32, 0.016, 5, False)


def flameGeo(scale=1):
    pts = [THREE.Vector2(x * scale, y * scale) for x, y in
           [[0, 0], [0.1, 0.03], [0.15, 0.12], [0.14, 0.22], [0.1, 0.33], [0.05, 0.45], [0.001, 0.58]]]
    return THREE.LatheGeometry(pts, 14)


# ------------------------------------------------------------------------------------------ materials (R.*)
def resources(game):
    """wonder.js _buildResources materials (the Godot side re-creates them; here they are the Blender preview)."""
    M = game.mats
    keep = {'keepColor': True}

    def kk(o):
        d = dict(keep)
        d.update(o)
        return d
    R = {}
    R['mTumble'] = M.toon('#C79A55', kk({'rough': 0.85, 'rim': 0.5, 'rimColor': '#FFE2A8'}))
    R['mGel'] = M.toon('#38C850', kk({'rough': 0.05, 'transparent': True, 'opacity': 0.86, 'rim': 0.7, 'rimColor': '#DFFFD8',
                                      'rimPower': 2.2, 'emissive': '#1B7A2E', 'emissiveIntensity': 0.12, 'env': 0.7,
                                      'name': 'wonder_gel'}))
    R['mGelEye'] = M.toon('#1E7A30', kk({'rough': 0.2, 'rim': 0.4}))
    R['mPlate'] = M.toon('#F4F1E8', kk({'rough': 0.25, 'rim': 0.3, 'env': 0.4}))
    R['mCherry'] = M.toon('#E23B3B', kk({'rough': 0.15, 'rim': 0.6, 'env': 0.6}))
    R['mBunny'] = M.toon('#FFFFFF', kk({'rough': 0.95, 'rim': 0.75, 'rimColor': '#FFFFFF', 'wrap': 0.8}))
    R['mPink'] = M.toon('#FF9EC4', kk({'rough': 0.7, 'rim': 0.4}))
    R['mInk'] = M.toon('#2A1D3A', kk({'rough': 0.3, 'rim': 0.2}))
    R['mGoo'] = M.toon(PAL.chromaBlue, kk({'rough': 0.08, 'rim': 0.9, 'rimColor': '#BFD4FF', 'emissive': PAL.chromaBlue,
                                           'emissiveIntensity': 0.5, 'env': 0.9}))
    R['mPuddle'] = M.toon('#1440D0', kk({'rough': 0.34, 'rim': 0.2, 'emissive': PAL.chromaBlue, 'emissiveIntensity': 0.26,
                                         'env': 0.1, 'name': 'wonder_puddle'}))
    R['mPuddleSheen'] = M.toon('#4F7BFF', kk({'rough': 0.12, 'rim': 0.3, 'emissive': '#3E6BFF', 'emissiveIntensity': 0.32,
                                              'env': 0.3, 'name': 'wonder_puddle_sheen'}))
    R['mFlame'] = M.glow('#FF7A2E', 2.6, {'additive': True})
    R['mFlameIn'] = M.glow('#FFE14D', 3.2, {'additive': True})
    R['mWhite'] = M.glow('#FFFFFF', 3.2)
    R['mIce'] = M.toon('#5DB8EC', kk({'rough': 0.3, 'rim': 0.45, 'rimColor': '#E6F7FF', 'rimPower': 2.2, 'emissive': '#16508A',
                                      'emissiveIntensity': 0.1, 'env': 0.3, 'steps': 3, 'name': 'wonder_ice'}))
    R['mBattery'] = M.toon('#F4C81E', kk({'rough': 0.35, 'rim': 0.4}))
    R['mAdd'] = Material('basic', '#ffffff', {'transparent': True, 'depthWrite': False, 'side': 'double', 'fog': False},
                         type='MeshBasicMaterial', name='wonder_rings')
    return R


def _mesh(geometry, mat, key, name=None, opts=None):
    """kit.m (geo.mesh) + userData.mat = the wonder.gd material key."""
    me = K.m(geometry, mat, opts or {})
    me.userData.mat = key
    if name:
        me.name = name
    return me


# ------------------------------------------------------------------------------------------ graphs
def buildMeshes(game):
    R = resources(game)
    root = Group()
    root.name = 'wonder_meshes'
    items = [
        ('ring', THREE.RingGeometry(0.88, 1, 48), R['mAdd'], 'ring'),
        ('ringBold', THREE.RingGeometry(0.7, 1, 48), R['mAdd'], 'ringBold'),
        ('tumble', tumbleweedGeo(), R['mTumble'], 'mTumble'),
        ('gel', gelatinGeo(), R['mGel'], 'mGel'),
        ('blobGeo', geo.sphere(1, 20, 14), R['mGoo'], 'mGoo'),
        ('puddle', blobShapeGeo(11), R['mPuddle'], 'mPuddle'),
        ('puddleSheen', blobShapeGeo(23, 18), R['mPuddleSheen'], 'mPuddleSheen'),
        ('squig', squiggleGeo(), R['mAdd'], 'squig'),
        ('flameOuter', flameGeo(1), R['mFlame'], 'mFlame'),
        ('flameInner', flameGeo(0.62), R['mFlameIn'], 'mFlameIn'),
        ('dot', geo.sphere(0.06, 12, 8), R['mWhite'], 'mWhite'),
        ('cube', geo.roundedBox(1, 1, 1, 0.18, 2), R['mIce'], 'mIce'),
    ]
    for name, g, mat, key in items:
        root.add(_mesh(g, mat, key, name))
    return root


# The spent battery (wonder.js _popBattery).
def buildBattery(game):
    R = resources(game)
    bat = Group()
    bat.name = 'battery'
    bat.add(_mesh(geo.cylinder(0.02, 0.02, 0.1, 12), R['mBattery'], 'mBattery', 'mBattery_cell', {'rot': [PI / 2, 0, 0]}))
    bat.add(_mesh(geo.cylinder(0.021, 0.021, 0.025, 12), R['mInk'], 'mInk', 'mInk_cap', {'pos': [0, 0, -0.05], 'rot': [PI / 2, 0, 0]}))
    return bat


# The cooking gag's mold on its plate (wonder.js _gagCooking; the holder / wob groups are made by wonder.gd).
def buildGelatin(game):
    R = resources(game)
    root = Group()
    root.name = 'gelatin'
    mold = Group()
    mold.name = 'mold'
    jelly = Mesh(gelatinGeo(), R['mGel'])
    jelly.name = 'mGel_jelly'
    jelly.userData.mat = 'mGel'
    jelly.castShadow = True
    mold.add(jelly)
    for s in (-1, 1):
        mold.add(_mesh(geo.sphere(0.055, 12, 8), R['mGelEye'], 'mGelEye', None, {'pos': [s * 0.1, 0.4, -0.235], 'scale': [1, 1.2, 0.5]}))
    mold.add(_mesh(geo.torus(0.05, 0.016, 6, 14), R['mGelEye'], 'mGelEye', None, {'pos': [0, 0.27, -0.27], 'rot': [0.25, 0, 0], 'scale': [1, 0.7, 1]}))
    mold.add(_mesh(geo.sphere(0.05, 14, 10), R['mCherry'], 'mCherry', None, {'pos': [0, 0.655, 0]}))
    mold.add(_mesh(geo.cylinder(0.005, 0.005, 0.08, 5), R['mInk'], 'mInk', None, {'pos': [0.015, 0.72, 0], 'rot': [0, 0, -0.4]}))
    plate = _mesh(geo.cylinder(0.42, 0.36, 0.03, 28), R['mPlate'], 'mPlate', 'plate', {'pos': [0, 0.015, 0]})
    root.add(plate)
    root.add(mold)
    return root


# The nature gag's bunny (wonder.js _buildBunny).
def buildBunny(game):
    R = resources(game)
    b = Group()
    b.name = 'bunny'
    body = Group()
    body.name = 'body'
    b.add(body)

    def m(g, mat, o):
        x = _mesh(g, R[mat], mat, None, o)
        body.add(x)
        return x
    m(geo.sphere(0.2, 18, 14), 'mBunny', {'pos': [0, 0.2, 0.02], 'scale': [1, 0.88, 1.12]})
    m(geo.sphere(0.15, 18, 14), 'mBunny', {'pos': [0, 0.4, -0.15]})
    m(geo.sphere(0.075, 12, 10), 'mBunny', {'pos': [0, 0.22, 0.24]})
    for s in (-1, 1):
        m(geo.sphere(0.075, 12, 10), 'mBunny', {'pos': [s * 0.12, 0.05, -0.08], 'scale': [0.8, 0.55, 1.3]})
        m(geo.sphere(0.026, 10, 8), 'mInk', {'pos': [s * 0.065, 0.44, -0.28]})
        m(geo.sphere(0.036, 10, 8), 'mPink', {'pos': [s * 0.085, 0.36, -0.27], 'scale': [1, 0.6, 0.4]})
        ear = Group()
        ear.position.set(s * 0.06, 0.52, -0.13)
        ear.rotation.z = -s * 0.2
        ear.name = 'earL' if s < 0 else 'earR'
        ear.add(_mesh(geo.capsule(0.045, 0.17), R['mBunny'], 'mBunny', None, {'pos': [0, 0.12, 0]}))
        ear.add(_mesh(geo.capsule(0.022, 0.13), R['mPink'], 'mPink', None, {'pos': [0, 0.12, -0.03]}))
        body.add(ear)
    m(geo.sphere(0.022, 10, 8), 'mPink', {'pos': [0, 0.39, -0.3]})
    return b


# ------------------------------------------------------------------------------------------ export
def graphs():
    game = K.Game()
    return {
        'meshes': lambda: buildMeshes(game),
        'battery': lambda: buildBattery(game),
        'gelatin': lambda: buildGelatin(game),
        'bunny': lambda: buildBunny(game),
    }


def build(save_blend=False, only=None):
    """Builds every wonder runtime asset into godot/assets/runtime/wonder/. Returns the written paths."""
    from dalib import export as EX
    os.makedirs(OUT_DIR, exist_ok=True)
    written = []
    for name, make in graphs().items():
        if only and name not in only:
            continue
        root = make()
        path = os.path.join(OUT_DIR, name + '.glb')
        blend = os.path.join(_BLENDER, 'out', 'runtime_wonder_%s.blend' % name) if save_blend else None
        EX.export_graph(root, path, root_name=root.name or name, save_blend=blend)
        written.append(path)
        print('[runtime/wonder] %s' % path)
    return written


if __name__ == '__main__':
    args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
    build(save_blend='--save-blend' in args)
