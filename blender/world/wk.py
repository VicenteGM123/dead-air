# World kit: the thin layer the world ports (architecture.py, exterior.py, doors.py, windows.py, surfaces.py) build
# with, on top of the shared dalib (SPEC §5): the three.js-like scene graph of dalib/scene.py (Group, Mesh,
# Material; three.js coordinates, converted to Blender by scene.to_blender), the exact three.js geometry port
# dalib/three_geo.py and the cached helpers of src/core/geo.js (dalib/geo.py).
#
#   Group(name) / Mesh(geo, mat)       dalib.scene (THREE.Group / THREE.Mesh)
#   mesh(geo, mat, pos, rot, scale, cast, receive, name)   geo.mesh() of src/core/geo.js (cast=true by default)
#   Mats                                mats.toon / glow / basic / glass / variant of src/core/materials.js as
#                                       dalib.scene.Material specs (SPEC §5.5; glow intensity in opts.intensity)
#   tex_from_canvas(canvas, key)        a dalib.tex.Texture for a canvas drawn here (world surfaces, moon)
#   mergeByMaterial(root)               geo.mergeByMaterial: static meshes merged per (material, castShadow)
#   geometry(pos, nrm, uv, col, idx)    a BufferGeometry from raw arrays (batch buckets, stars)
#   export_glb(root, path, name)        fresh scene -> scene.to_blender -> glTF (SPEC §5.3 settings)

import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from dalib import three_geo as THREE  # noqa: E402
from dalib import geo  # noqa: E402,F401  (re-exported: roundedBox, box, cylinder, sphere, torus, plane, tube)
from dalib import tex as dtex  # noqa: E402
from dalib.scene import Group, Mesh, Material, FrontSide, BackSide, DoubleSide, AdditiveBlending  # noqa: E402,F401
from dalib.mathutils3 import Vector3, Matrix4, Quaternion, Euler, Color  # noqa: E402,F401

PI = 3.141592653589793


def group(name=''):
    g = Group()
    g.name = name
    return g


def mesh(g, mat, pos=None, rot=None, scale=None, cast=True, receive=True, name=None):
    """geo.mesh(geo, mat, { pos:[x,y,z], rot:[x,y,z], scale:number|[x,y,z], cast=true, receive=true, name })"""
    m = Mesh(g, mat)
    if pos is not None:
        m.position.set(pos[0], pos[1], pos[2])
    if rot is not None:
        m.rotation.set(rot[0], rot[1], rot[2])
    if scale is not None:
        if isinstance(scale, (int, float)):
            m.scale.setScalar(scale)
        else:
            m.scale.set(scale[0], scale[1], scale[2])
    m.castShadow = cast
    m.receiveShadow = receive
    if name:
        m.name = name
    return m


def geometry(pos, nrm=None, uv=None, col=None, idx=None, uv1=None):
    g = THREE.Geometry()
    g.setAttribute('position', np.asarray(pos, dtype=np.float64).reshape(-1, 3), 3)
    if nrm is not None:
        g.setAttribute('normal', np.asarray(nrm, dtype=np.float64).reshape(-1, 3), 3)
    if uv is not None:
        g.setAttribute('uv', np.asarray(uv, dtype=np.float64).reshape(-1, 2), 2)
    if uv1 is not None:
        g.setAttribute('uv1', np.asarray(uv1, dtype=np.float64).reshape(-1, 2), 2)
    if col is not None:
        g.setAttribute('color', np.asarray(col, dtype=np.float64).reshape(-1, 3), 3)
    if idx is not None:
        g.setIndex([int(i) for i in idx])
    return g


def tex_from_canvas(canvas, key, repeat=True, ns='w'):
    return dtex.Texture(canvas, key, repeat, ns)


# -------------------------------------------------------------------------------------------- materials
_SIDES = {'front': FrontSide, 'back': BackSide, 'double': DoubleSide}


def _opts(o):
    o = dict(o or {})
    if isinstance(o.get('side'), str):
        o['side'] = _SIDES[o['side']]
    return o


class Mats:
    """src/core/materials.js factories as specs. Identical calls return the same Material (the JS caches them)."""

    def __init__(self):
        self._cache = {}

    def _get(self, kind, color, opts, extra=None):
        o = _opts(opts)
        tex = o.get('map')
        key = json.dumps([kind, color, {k: (('tex', v.key) if getattr(v, 'isTexture', False) else v) for k, v in o.items()},
                          extra or {}], sort_keys=True, default=str)
        m = self._cache.get(key)
        if m is None:
            fields = {}
            if o.get('additive'):
                fields['blending'] = AdditiveBlending
                fields['transparent'] = True
                fields['depthWrite'] = False
            m = Material(kind, color, o, extra=extra, **fields)
            if tex is not None:
                m.map = tex
            self._cache[key] = m
        return m

    def toon(self, color='#ffffff', opts=None):
        return self._get('toon', color, opts)

    def glow(self, color='#ffffff', intensity=2, opts=None):
        o = dict(opts or {})
        o['intensity'] = intensity
        return self._get('glow', color, o)

    def basic(self, color='#ffffff', opts=None):
        return self._get('basic', color, opts)

    def glass(self, color='#CFE8FF', opts=None):
        """mats.glass = toon(color, {rough .05, transparent, opacity, rim .6, rimColor #fff, rimPower 2, env 1.2,
        depthWrite false, keepColor, side (default double), name 'glass'})."""
        o = opts or {}
        return self.toon(color, {
            'rough': 0.05, 'transparent': True, 'opacity': o.get('opacity', 0.22), 'rim': 0.6, 'rimColor': '#ffffff',
            'rimPower': 2.0, 'env': 1.2, 'depthWrite': False, 'keepColor': o.get('keepColor', True),
            'side': o.get('side', 'double'), 'name': 'glass',
        })

    def variant(self, mat, extra):
        if mat.kind != 'toon':
            return mat
        o = dict(mat.opts)
        o.update(extra)
        return self._get('toon', mat.hex, o, mat.extra or None)

    def tagged(self, mat, **extra):
        """The same material with extra top-level spec keys (surface, tile)."""
        e = dict(mat.extra or {})
        e.update(extra)
        return self._get(mat.kind, mat.hex, mat.opts, e)


# ---------------------------------------------------------------------------------------------- merging
def _blocked(o, root):
    p = o
    while p is not None and p is not root:
        if p.userData.get('dynamic') or p.userData.get('noMerge'):
            return True
        p = p.parent
    return False


def mergeByMaterial(root, prefix='merged'):
    """geo.mergeByMaterial(root): one mesh per (material, castShadow) under root for the static meshes (visible, no
    children, one material, not noMerge/dynamic on them or an ancestor). Returns the number merged away."""
    root.updateMatrixWorld(True)
    inv = Matrix4().copy(root.matrixWorld).invert()
    found = []

    def visit(o):
        if o is root or not getattr(o, 'isMesh', False) or getattr(o, 'isInstancedMesh', False) or o.children:
            return
        if not o.visible or isinstance(o.material, list) or _blocked(o, root):
            return
        found.append(o)
    root.traverse(visit)
    groups = {}
    order = []
    for o in found:
        k = (id(o.material), bool(o.castShadow))
        if k not in groups:
            groups[k] = []
            order.append(k)
        groups[k].append(o)
    n = 0
    for k in order:
        lst = groups[k]
        if len(lst) < 2:
            continue
        wantColor = any(o.geometry.attributes.get('color') is not None for o in lst)
        geos = []
        for o in lst:
            g = o.geometry.clone()
            for a in list(g.attributes.keys()):
                if a not in ('position', 'normal', 'uv', 'color'):
                    g.deleteAttribute(a)
            if g.attributes.get('uv') is None:
                g.setAttribute('uv', np.zeros((g.attributes.position.count, 2)), 2)
            if wantColor and g.attributes.get('color') is None:
                g.setAttribute('color', np.ones((g.attributes.position.count, 3)), 3)
            if g.index is None:
                g.setIndex(list(range(g.attributes.position.count)))
            m = Matrix4().multiplyMatrices(inv, o.matrixWorld)
            g.applyMatrix4(m)
            if m.determinant() < 0:
                idx = np.asarray(g.index).reshape(-1, 3).copy()
                idx[:, [1, 2]] = idx[:, [2, 1]]
                g.setIndex([int(i) for i in idx.reshape(-1)])
            geos.append(g)
            o.removeFromParent()
        mg = THREE.mergeGeometries(geos)
        mm = Mesh(mg, lst[0].material)
        mm.name = '%s_%d' % (prefix, len(root.children))
        mm.castShadow = k[1]
        mm.receiveShadow = True
        root.add(mm)
        n += len(lst) - 1
    return n


# ---------------------------------------------------------------------------------------------- export
def texture_file(t):
    return dtex.texture_file(t)


def export_glb(root, path, root_name=None, save_blend=False):
    """Builds `root` into a fresh, empty Blender scene and exports it as GLB (SPEC §5.3)."""
    import bpy
    from dalib.scene import to_blender, assign_names
    try:
        from dalib import export as dexport
    except Exception:
        dexport = None
    if dexport is not None and hasattr(dexport, 'export_graph'):
        return dexport.export_graph(root, path, root_name=root_name, save_blend=save_blend)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    names = assign_names(root, root_name)
    to_blender(root, names, texture_file, root_name)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    kw = dict(filepath=path, export_format='GLB', export_extras=True, export_yup=True, export_apply=True,
              export_attributes=True, export_texcoords=True, export_normals=True, export_materials='EXPORT',
              export_image_format='AUTO', export_cameras=False, export_lights=False)
    for k, v in (('export_vertex_color', 'ACTIVE'), ('export_all_vertex_colors', True)):
        kw[k] = v
    try:
        bpy.ops.export_scene.gltf(**kw)
    except TypeError:
        kw.pop('export_vertex_color', None)
        kw.pop('export_all_vertex_colors', None)
        kw['export_colors'] = True
        bpy.ops.export_scene.gltf(**kw)
    if save_blend:
        out = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'out')
        os.makedirs(out, exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out, os.path.splitext(os.path.basename(path))[0] + '.blend'))
    return path
