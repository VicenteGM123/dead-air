# World kit: the thin layer the world ports (architecture.py, exterior.py, doors.py, windows.py, surfaces.py) build
# with, on top of the shared dalib (SPEC §5): the three.js-like scene graph of dalib/scene.py (Group, Mesh,
# Material; three.js coordinates, converted to Blender by scene.to_blender), the exact three.js geometry port
# dalib/three_geo.py and the cached helpers of src/core/geo.js (dalib/geo.py).
#
#   Group(name) / Mesh(geo, mat)       dalib.scene (THREE.Group / THREE.Mesh)
#   mesh(geo, mat, pos, rot, scale, cast, receive, name)   geo.mesh() of src/core/geo.js (cast=true by default)
#   Mats                                game.mats: dalib.kit.Materials (mats.toon / glow / basic / glass / variant of
#                                       src/core/materials.js as dalib.scene.Material specs, SPEC §5.5)
#   tex_from_canvas(canvas, key)        a dalib.tex.Texture for a canvas drawn here (world surfaces, moon)
#   mergeByMaterial(root)               geo.mergeByMaterial: static meshes merged per (material, castShadow)
#   geometry(pos, nrm, uv, col, idx)    a BufferGeometry from raw arrays (batch buckets, stars)
#   export_glb(root, path, name)        dalib.export.export_graph (fresh scene -> glTF, SPEC §5.3 settings)

import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from dalib import three_geo as THREE  # noqa: E402
from dalib import geo  # noqa: E402,F401  (re-exported: roundedBox, box, cylinder, sphere, torus, plane, tube)
from dalib import tex as dtex  # noqa: E402
from dalib.scene import Group, Mesh, Material, FrontSide, BackSide, DoubleSide, AdditiveBlending  # noqa: E402,F401
from dalib.kit import Materials  # noqa: E402
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


class Mats(Materials):
    """game.mats of the world build: dalib.kit.Materials (the shared JS-factory shim: toon / glow / basic / glass /
    variant, cached like the JS) + 'side' given by name + tagged() (extra top-level spec keys: surface, tile)."""

    def toon(self, color='#ffffff', opts=None):
        return super().toon(color, _opts(opts))

    def glow(self, color='#ffffff', intensity=2, opts=None):
        return super().glow(color, intensity, _opts(opts))

    def basic(self, color='#ffffff', opts=None):
        return super().basic(color, _opts(opts))

    def glass(self, color='#CFE8FF', opts=None):
        return super().glass(color, _opts(opts))

    def tagged(self, mat, **extra):
        mat.extra.update(extra)
        return mat


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
        k = (id(o.material), bool(o.castShadow), bool(o.receiveShadow), o.renderOrder)
        if k not in groups:
            groups[k] = []
            order.append(k)
        groups[k].append(o)
    n = 0
    for k in order:
        lst = groups[k]
        if len(lst) < 2:
            continue
        wantColor = bool(lst[0].material.vertexColors)
        geos = []
        for o in lst:
            g = o.geometry.clone()
            for a in list(g.attributes.keys()):
                if a not in ('position', 'normal', 'uv', 'color') or (a == 'color' and not wantColor):
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
        mm.receiveShadow = k[2]
        mm.renderOrder = k[3]
        root.add(mm)
        n += len(lst) - 1
    return n


# ---------------------------------------------------------------------------------------------- export
def texture_file(t):
    return dtex.texture_file(t)


def export_glb(root, path, root_name=None, save_blend=False):
    """Builds `root` into a fresh, empty Blender scene and exports it as GLB (dalib.export.export_graph: SPEC §5.3
    settings, textures linked to the shared PNGs of godot/assets/textures). save_blend -> blender/out/<name>.blend."""
    from dalib import export as dexport
    blend = None
    if save_blend:
        blend = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'out',
                             'world_' + os.path.splitext(os.path.basename(path))[0] + '.blend')
    os.makedirs(os.path.dirname(path), exist_ok=True)
    dexport.export_graph(root, path, root_name=root_name, save_blend=blend)
    return path
