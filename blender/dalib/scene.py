"""DEAD AIR — light three.js-like scene graph (pure Python) + its conversion into Blender objects (bpy).

Prop builders port line by line against this graph (THREE.Object3D semantics, three.js coordinates, never Blender
axes — SPEC §5.2):

    g = Group(); g.name = 'drum'
    m = Mesh(geometry, material); m.position.set(0, 1, 0); m.rotation.y = 0.3; m.scale.setScalar(2)
    g.add(m); root.userData.parts.drum = g; m.userData.noMerge = True; m.castShadow = False

Object3D mirrors three r186: position (Vector3), rotation (Euler, synced with quaternion like three), quaternion,
scale, matrix/matrixWorld, up, visible, castShadow, receiveShadow, renderOrder, layers, userData (JSObj: attribute
access, missing keys read as None), children/parent, add/remove/attach/removeFromParent/clear, traverse,
traverseVisible, traverseAncestors, getObjectByName/Property, updateMatrix, updateMatrixWorld, updateWorldMatrix,
localToWorld, worldToLocal, getWorldPosition/Quaternion/Scale/Direction, lookAt, rotateX/Y/Z/OnAxis/OnWorldAxis,
translateX/Y/Z/OnAxis, applyMatrix4, applyQuaternion, clone(recursive), copy. Mesh(geometry, material),
InstancedMesh(geometry, material, count) with setMatrixAt/getMatrixAt/setColorAt/getColorAt, Group, Line, Points.

Materials are Material objects (see Material): the spec the Godot side rebuilds (SPEC §5.5) plus the three fields
builders read (type, transparent, vertexColors, map, userData.daToon, color, opacity, side …).

Blender side: assign_names(root) makes unique, Godot-safe node names; to_blender(root, names) creates the objects
(axis conversion, materials with a Principled BSDF preview + custom property "da", vertex colours, UVs with 1-v,
custom normals, custom property "da" on every node) — used by dalib/export.py.
"""
from __future__ import annotations

import json
import math
import re
import uuid as _uuid

import numpy as np

from .mathutils3 import (JSObj, Vector3, Euler, Quaternion, Matrix4, Matrix3, Color, Box3, Vector2, Vector4)

__all__ = ['Object3D', 'Group', 'Mesh', 'InstancedMesh', 'Line', 'LineSegments', 'Points', 'Layers', 'Material',
           'FrontSide', 'BackSide', 'DoubleSide', 'NormalBlending', 'AdditiveBlending', 'box_from_object',
           'assign_names', 'to_blender', 'jsonable', 'SIDE_NAMES']

FrontSide, BackSide, DoubleSide = 0, 1, 2
SIDE_NAMES = {0: 'front', 1: 'back', 2: 'double'}
NoBlending, NormalBlending, AdditiveBlending, SubtractiveBlending, MultiplyBlending, CustomBlending = 0, 1, 2, 3, 4, 5
BLEND_NAMES = {0: 'none', 1: 'normal', 2: 'additive', 3: 'subtractive', 4: 'multiply', 5: 'custom'}

_id_counter = [0]


def _uid():
    return str(_uuid.uuid4())


# ===================================================================================================== graph
class Layers:
    def __init__(self):
        self.mask = 1

    def set(self, ch):
        self.mask = (1 << ch) & 0xFFFFFFFF

    def enable(self, ch):
        self.mask |= (1 << ch)

    def enableAll(self):
        self.mask = 0xFFFFFFFF

    def toggle(self, ch):
        self.mask ^= (1 << ch)

    def disable(self, ch):
        self.mask &= ~(1 << ch)

    def disableAll(self):
        self.mask = 0

    def test(self, layers):
        return (self.mask & layers.mask) != 0

    def isEnabled(self, ch):
        return (self.mask & (1 << ch)) != 0


_q1 = Quaternion()
_m1 = Matrix4()
_target = Vector3()
_position = Vector3()
_xAxis, _yAxis, _zAxis = Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)


class Object3D:
    isObject3D = True
    DEFAULT_UP = Vector3(0, 1, 0)
    DEFAULT_MATRIX_AUTO_UPDATE = True
    DEFAULT_MATRIX_WORLD_AUTO_UPDATE = True

    def __init__(self):
        _id_counter[0] += 1
        self.id = _id_counter[0]
        self.uuid = _uid()
        self.name = ''
        self.type = 'Object3D'
        self.parent = None
        self.children = []
        self.up = Object3D.DEFAULT_UP.clone()
        self.position = Vector3()
        self.rotation = Euler()
        self.quaternion = Quaternion()
        self.scale = Vector3(1, 1, 1)
        rot, quat = self.rotation, self.quaternion
        rot._onChange(lambda: quat.setFromEuler(rot, False))
        quat._onChange(lambda: rot.setFromQuaternion(quat, None, False))
        self.matrix = Matrix4()
        self.matrixWorld = Matrix4()
        self.matrixAutoUpdate = Object3D.DEFAULT_MATRIX_AUTO_UPDATE
        self.matrixWorldAutoUpdate = Object3D.DEFAULT_MATRIX_WORLD_AUTO_UPDATE
        self.matrixWorldNeedsUpdate = False
        self.layers = Layers()
        self.visible = True
        self.castShadow = False
        self.receiveShadow = False
        self.frustumCulled = True
        self.renderOrder = 0
        self.userData = JSObj()

    # three sets userData to a plain object; keep attribute access when a builder assigns a dict
    def __setattr__(self, k, v):
        if k == 'userData' and isinstance(v, dict) and not isinstance(v, JSObj):
            v = _jsobj(v)
        object.__setattr__(self, k, v)

    def __repr__(self):
        return '<%s %r>' % (self.type, self.name)

    # ------------------------------------------------------------------------------------------ transforms
    def applyMatrix4(self, matrix):
        if self.matrixAutoUpdate:
            self.updateMatrix()
        self.matrix.premultiply(matrix)
        self.matrix.decompose(self.position, self.quaternion, self.scale)
        return self

    def applyQuaternion(self, q):
        self.quaternion.premultiply(q)
        return self

    def setRotationFromAxisAngle(self, axis, angle):
        self.quaternion.setFromAxisAngle(axis, angle)

    def setRotationFromEuler(self, euler):
        self.quaternion.setFromEuler(euler, True)

    def setRotationFromMatrix(self, m):
        self.quaternion.setFromRotationMatrix(m)

    def setRotationFromQuaternion(self, q):
        self.quaternion.copy(q)

    def rotateOnAxis(self, axis, angle):
        _q1.setFromAxisAngle(axis, angle)
        self.quaternion.multiply(_q1)
        return self

    def rotateOnWorldAxis(self, axis, angle):
        _q1.setFromAxisAngle(axis, angle)
        self.quaternion.premultiply(_q1)
        return self

    def rotateX(self, a):
        return self.rotateOnAxis(_xAxis, a)

    def rotateY(self, a):
        return self.rotateOnAxis(_yAxis, a)

    def rotateZ(self, a):
        return self.rotateOnAxis(_zAxis, a)

    def translateOnAxis(self, axis, distance):
        v = Vector3().copy(axis).applyQuaternion(self.quaternion)
        self.position.add(v.multiplyScalar(distance))
        return self

    def translateX(self, d):
        return self.translateOnAxis(_xAxis, d)

    def translateY(self, d):
        return self.translateOnAxis(_yAxis, d)

    def translateZ(self, d):
        return self.translateOnAxis(_zAxis, d)

    def localToWorld(self, vector):
        self.updateWorldMatrix(True, False)
        return vector.applyMatrix4(self.matrixWorld)

    def worldToLocal(self, vector):
        self.updateWorldMatrix(True, False)
        return vector.applyMatrix4(Matrix4().copy(self.matrixWorld).invert())

    def lookAt(self, x, y=None, z=None):
        if getattr(x, 'isVector3', False):
            _target.copy(x)
        else:
            _target.set(x, y, z)
        parent = self.parent
        self.updateWorldMatrix(True, False)
        _position.setFromMatrixPosition(self.matrixWorld)
        if getattr(self, 'isCamera', False) or getattr(self, 'isLight', False):
            _m1.lookAt(_position, _target, self.up)
        else:
            _m1.lookAt(_target, _position, self.up)
        self.quaternion.setFromRotationMatrix(_m1)
        if parent:
            _m1.extractRotation(parent.matrixWorld)
            _q1.setFromRotationMatrix(_m1)
            self.quaternion.premultiply(_q1.invert())

    # ------------------------------------------------------------------------------------------- hierarchy
    def add(self, *objects):
        if len(objects) > 1:
            for o in objects:
                self.add(o)
            return self
        if not objects:
            return self
        o = objects[0]
        if o is self:
            raise ValueError('Object3D.add: object can\'t be added as a child of itself.')
        if o is not None and getattr(o, 'isObject3D', False):
            o.removeFromParent()
            o.parent = self
            self.children.append(o)
        return self

    def remove(self, *objects):
        if len(objects) > 1:
            for o in objects:
                self.remove(o)
            return self
        if not objects:
            return self
        o = objects[0]
        if o in self.children:
            self.children.remove(o)
            o.parent = None
        return self

    def removeFromParent(self):
        if self.parent is not None:
            self.parent.remove(self)
        return self

    def clear(self):
        return self.remove(*list(self.children))

    def attach(self, o):
        self.updateWorldMatrix(True, False)
        m = Matrix4().copy(self.matrixWorld).invert()
        if o.parent is not None:
            o.parent.updateWorldMatrix(True, False)
            m.multiply(o.parent.matrixWorld)
        o.applyMatrix4(m)
        o.removeFromParent()
        o.parent = self
        self.children.append(o)
        o.updateWorldMatrix(False, True)
        return self

    def getObjectById(self, i):
        return self.getObjectByProperty('id', i)

    def getObjectByName(self, name):
        return self.getObjectByProperty('name', name)

    def getObjectByProperty(self, name, value):
        if getattr(self, name, None) == value:
            return self
        for c in self.children:
            o = c.getObjectByProperty(name, value)
            if o is not None:
                return o
        return None

    def getObjectsByProperty(self, name, value, result=None):
        result = [] if result is None else result
        if getattr(self, name, None) == value:
            result.append(self)
        for c in self.children:
            c.getObjectsByProperty(name, value, result)
        return result

    def getWorldPosition(self, target):
        self.updateWorldMatrix(True, False)
        return target.setFromMatrixPosition(self.matrixWorld)

    def getWorldQuaternion(self, target):
        self.updateWorldMatrix(True, False)
        self.matrixWorld.decompose(Vector3(), target, Vector3())
        return target

    def getWorldScale(self, target):
        self.updateWorldMatrix(True, False)
        self.matrixWorld.decompose(Vector3(), Quaternion(), target)
        return target

    def getWorldDirection(self, target):
        self.updateWorldMatrix(True, False)
        e = self.matrixWorld.elements
        return target.set(e[8], e[9], e[10]).normalize()

    def traverse(self, callback):
        callback(self)
        for c in list(self.children):
            c.traverse(callback)

    def traverseVisible(self, callback):
        if not self.visible:
            return
        callback(self)
        for c in list(self.children):
            c.traverseVisible(callback)

    def traverseAncestors(self, callback):
        if self.parent is not None:
            callback(self.parent)
            self.parent.traverseAncestors(callback)

    def iter(self):
        """Python helper: depth-first list of self and every descendant (traverse order)."""
        out = []
        self.traverse(out.append)
        return out

    def updateMatrix(self):
        self.matrix.compose(self.position, self.quaternion, self.scale)
        self.matrixWorldNeedsUpdate = True

    def updateMatrixWorld(self, force=False):
        if self.matrixAutoUpdate:
            self.updateMatrix()
        if self.matrixWorldNeedsUpdate or force:
            if self.matrixWorldAutoUpdate:
                if self.parent is None:
                    self.matrixWorld.copy(self.matrix)
                else:
                    self.matrixWorld.multiplyMatrices(self.parent.matrixWorld, self.matrix)
            self.matrixWorldNeedsUpdate = False
            force = True
        for c in self.children:
            c.updateMatrixWorld(force)

    def updateWorldMatrix(self, updateParents, updateChildren):
        parent = self.parent
        if updateParents and parent is not None:
            parent.updateWorldMatrix(True, False)
        if self.matrixAutoUpdate:
            self.updateMatrix()
        if self.matrixWorldAutoUpdate:
            if self.parent is None:
                self.matrixWorld.copy(self.matrix)
            else:
                self.matrixWorld.multiplyMatrices(self.parent.matrixWorld, self.matrix)
        if updateChildren:
            for c in self.children:
                c.updateWorldMatrix(False, True)

    # ------------------------------------------------------------------------------------------- cloning
    def clone(self, recursive=True):
        o = self.__class__.__new__(self.__class__)
        Object3D.__init__(o)
        o._init_clone(self)
        o.copy(self, recursive)
        return o

    def _init_clone(self, src):
        pass

    def copy(self, source, recursive=True):
        self.name = source.name
        self.type = source.type
        self.up.copy(source.up)
        self.position.copy(source.position)
        self.rotation.order = source.rotation.order
        self.quaternion.copy(source.quaternion)
        self.scale.copy(source.scale)
        self.matrix.copy(source.matrix)
        self.matrixWorld.copy(source.matrixWorld)
        self.matrixAutoUpdate = source.matrixAutoUpdate
        self.matrixWorldAutoUpdate = source.matrixWorldAutoUpdate
        self.matrixWorldNeedsUpdate = source.matrixWorldNeedsUpdate
        self.layers.mask = source.layers.mask
        self.visible = source.visible
        self.castShadow = source.castShadow
        self.receiveShadow = source.receiveShadow
        self.frustumCulled = source.frustumCulled
        self.renderOrder = source.renderOrder
        # three: JSON.parse(JSON.stringify(source.userData))
        self.userData = _jsobj(json.loads(json.dumps(jsonable(source.userData, None, strict=False))))
        if recursive:
            for c in source.children:
                self.add(c.clone())
        return self


class Group(Object3D):
    isGroup = True

    def __init__(self):
        super().__init__()
        self.type = 'Group'


class Mesh(Object3D):
    isMesh = True

    def __init__(self, geometry=None, material=None):
        super().__init__()
        self.type = 'Mesh'
        self.geometry = geometry
        self.material = material if material is not None else Material('basic', '#ffffff', {},
                                                                          type='MeshBasicMaterial')
        self.morphTargetInfluences = None
        self.morphTargetDictionary = None

    def copy(self, source, recursive=True):
        super().copy(source, recursive)
        self.material = source.material
        self.geometry = source.geometry
        self.morphTargetInfluences = source.morphTargetInfluences
        return self

    def _init_clone(self, src):
        self.geometry = None
        self.material = None
        self.morphTargetInfluences = None
        self.morphTargetDictionary = None


class Line(Mesh):
    isLine = True
    isMesh = False

    def __init__(self, geometry=None, material=None):
        super().__init__(geometry, material)
        self.type = 'Line'


class LineSegments(Line):
    isLineSegments = True

    def __init__(self, geometry=None, material=None):
        super().__init__(geometry, material)
        self.type = 'LineSegments'


class Points(Mesh):
    isPoints = True
    isMesh = False

    def __init__(self, geometry=None, material=None):
        super().__init__(geometry, material)
        self.type = 'Points'


class InstancedMesh(Mesh):
    """Exported as a parent node `<name>` ("da": {"instanced": true, "count": n}) with one child `<name>_<i>` per
    instance (SPEC §5.4). instanceColor is multiplied into that instance's vertex colours and kept in its "da"."""
    isInstancedMesh = True

    def __init__(self, geometry=None, material=None, count=1):
        super().__init__(geometry, material)
        self.type = 'InstancedMesh'
        self.count = int(count)
        self.instanceMatrix = [Matrix4() for _ in range(self.count)]
        self.instanceColor = None  # list of Color or None
        self.boundingBox = None
        self.boundingSphere = None

    def _init_clone(self, src):
        super()._init_clone(src)
        self.count = src.count
        self.instanceMatrix = [Matrix4() for _ in range(src.count)]
        self.instanceColor = None
        self.boundingBox = None
        self.boundingSphere = None

    def copy(self, source, recursive=True):
        super().copy(source, recursive)
        self.count = source.count
        self.instanceMatrix = [Matrix4().copy(m) for m in source.instanceMatrix]
        self.instanceColor = [Color().copy(c) for c in source.instanceColor] if source.instanceColor else None
        return self

    def setMatrixAt(self, i, m):
        self.instanceMatrix[i].copy(m)

    def getMatrixAt(self, i, m):
        return m.copy(self.instanceMatrix[i])

    def setColorAt(self, i, c):
        if self.instanceColor is None:
            self.instanceColor = [Color(1, 1, 1) for _ in range(len(self.instanceMatrix))]
        self.instanceColor[i].copy(c)

    def getColorAt(self, i, c):
        if self.instanceColor is None:
            return c.setRGB(1, 1, 1)
        return c.copy(self.instanceColor[i])

    def computeBoundingBox(self):
        g = self.geometry
        if g.boundingBox is None:
            g.computeBoundingBox()
        bb = Box3()
        for i in range(self.count):
            b = g.boundingBox.clone().applyMatrix4(self.instanceMatrix[i])
            bb.union(b)
        self.boundingBox = bb

    def dispose(self):
        pass


def _jsobj(v):
    if isinstance(v, dict):
        return JSObj({k: _jsobj(x) for k, x in v.items()})
    if isinstance(v, list):
        return [_jsobj(x) for x in v]
    return v


# ================================================================================================== Box3 glue
def box_from_object(obj, target=None, precise=False):
    """Box3.setFromObject(obj): world-space AABB of every geometry under obj (three's expandByObject)."""
    target = target if target is not None else Box3()
    target.makeEmpty()
    return _expand_by_object(target, obj, precise)


def _expand_by_object(box, obj, precise=False):
    obj.updateWorldMatrix(False, False)
    geo = getattr(obj, 'geometry', None)
    if geo is not None:
        pos = geo.attributes.position if hasattr(geo, 'attributes') else None
        if precise and pos is not None and not getattr(obj, 'isInstancedMesh', False):
            arr = np.asarray(pos.array, dtype=np.float64).reshape(-1, pos.itemSize)[:, :3]
            e = np.array(obj.matrixWorld.elements, dtype=np.float64).reshape(4, 4).T
            h = np.c_[arr, np.ones(len(arr))] @ e.T
            p = h[:, :3] / h[:, 3:4]
            if len(p):
                mn, mx = p.min(axis=0), p.max(axis=0)
                box.expandByPoint(Vector3(*mn.tolist()))
                box.expandByPoint(Vector3(*mx.tolist()))
        else:
            if getattr(obj, 'isInstancedMesh', False):
                if obj.boundingBox is None:
                    obj.computeBoundingBox()
                b = obj.boundingBox.clone()
            else:
                if geo.boundingBox is None:
                    geo.computeBoundingBox()
                b = geo.boundingBox.clone()
            b.applyMatrix4(obj.matrixWorld)
            box.union(b)
    for c in obj.children:
        _expand_by_object(box, c, precise)
    return box


if not hasattr(Box3, 'setFromObject'):
    def _set_from_object(self, obj, precise=False):
        return box_from_object(obj, self, precise)

    def _expand_obj(self, obj, precise=False):
        return _expand_by_object(self, obj, precise)
    Box3.setFromObject = _set_from_object
    Box3.expandByObject = _expand_obj


# ================================================================================================= materials
class Material:
    """A material SPEC (SPEC §5.5) that behaves enough like a THREE material for the builders.

    kind: 'toon' | 'glow' | 'basic' | 'screen' | 'bubble' | 'chromacast' | … (whatever fromSpec knows)
    color: the colour ARGUMENT of the JS factory (hex string), opts: the JS factory opts (JSON-safe except
    textures, which are Texture objects in opts['map'] and become the texture key). Extra top-level spec keys
    (screen, card, cardOpts, chroma …) go in `extra`. Fields three code reads: type, name, uuid, transparent,
    opacity, side, vertexColors, map, color (THREE.Color), emissive, roughness, metalness, depthWrite, userData.
    """
    isMaterial = True

    def __init__(self, kind, color='#ffffff', opts=None, type='MeshStandardMaterial', extra=None, **fields):
        self.uuid = _uid()
        self.kind = kind
        self.hex = color if isinstance(color, str) else ('#' + Color(color).getHexString())
        self.opts = dict(opts or {})
        self.extra = dict(extra or {})
        self.type = type
        self.name = fields.pop('name', '') or ''
        self.userData = JSObj()
        o = self.opts
        self.transparent = bool(fields.pop('transparent', o.get('transparent', False)))
        self.opacity = fields.pop('opacity', o.get('opacity', 1))
        self.side = fields.pop('side', o.get('side', FrontSide))
        self.vertexColors = bool(fields.pop('vertexColors', o.get('vertexColors', False)))
        self.map = fields.pop('map', o.get('map'))
        self.depthWrite = fields.pop('depthWrite', o.get('depthWrite', True))
        self.alphaTest = fields.pop('alphaTest', o.get('alphaTest', 0))
        self.blending = fields.pop('blending', NormalBlending)
        self.color = fields.pop('colorValue', None) or Color(self.hex)
        self.emissive = Color(o['emissive']) if o.get('emissive') else Color(0, 0, 0)
        self.emissiveIntensity = o.get('emissiveIntensity', 1)
        self.roughness = o.get('rough', 1)
        self.metalness = o.get('metal', 0)
        self.toneMapped = fields.pop('toneMapped', True)
        self.fog = fields.pop('fog', o.get('fog', True))
        self.flatShading = bool(o.get('flat', False))
        self.visible = True
        self.uniforms = fields.pop('uniforms', None)
        for k, v in fields.items():
            setattr(self, k, v)
        self._snap = self._tracked()

    def __repr__(self):
        return '<Material %s %s %s>' % (self.kind, self.hex, self.name)

    def _tracked(self):
        return (self.color.getHex(), self.opacity, self.transparent, self.side, self.vertexColors, id(self.map),
                self.depthWrite, self.emissive.getHex(), self.emissiveIntensity, self.roughness, self.metalness)

    def clone(self):
        m = Material.__new__(Material)
        m.__dict__.update(self.__dict__)
        m.uuid = _uid()
        m.opts = dict(self.opts)
        m.extra = json.loads(json.dumps(self.extra)) if self.extra else {}
        m.userData = _jsobj(json.loads(json.dumps(jsonable(self.userData, None, strict=False))))
        m.color = Color().copy(self.color)
        m.emissive = Color().copy(self.emissive)
        return m

    def dispose(self):
        pass

    # -------------------------------------------------------------------------------------------- spec
    def spec(self):
        """JSON-safe spec dict (SPEC §5.5) — reflects field changes made after creation (e.g. mat.opacity = …)."""
        opts = dict(self.opts)
        if self._tracked() != self._snap:
            # a builder mutated the material after creating it: fold the live values back into the spec
            c0 = Color(self.hex)
            if self.color.getHex() != c0.getHex() and self.kind != 'glow':
                self.hex = '#' + self.color.getHexString()
            if self.opacity != opts.get('opacity', 1):
                opts['opacity'] = self.opacity
            if self.transparent != bool(opts.get('transparent', False)):
                opts['transparent'] = self.transparent
            if self.side != opts.get('side', FrontSide):
                opts['side'] = self.side
            if self.vertexColors != bool(opts.get('vertexColors', False)):
                opts['vertexColors'] = self.vertexColors
            if self.depthWrite != opts.get('depthWrite', True):
                opts['depthWrite'] = self.depthWrite
            if self.map is not opts.get('map'):
                opts['map'] = self.map
            if self.kind == 'toon':
                if self.roughness != opts.get('rough'):
                    opts['rough'] = self.roughness
                if self.metalness != opts.get('metal'):
                    opts['metal'] = self.metalness
                if self.emissive.getHex() != (Color(opts['emissive']).getHex() if opts.get('emissive') else 0):
                    opts['emissive'] = '#' + self.emissive.getHexString()
                if self.emissiveIntensity != opts.get('emissiveIntensity', 1):
                    opts['emissiveIntensity'] = self.emissiveIntensity
        tex = opts.pop('map', None)
        if 'side' in opts:
            opts['side'] = SIDE_NAMES.get(opts['side'], opts['side'])
        if 'blending' in opts and isinstance(opts['blending'], int):
            opts['blending'] = BLEND_NAMES.get(opts['blending'], opts['blending'])
        out = {'kind': self.kind, 'color': self.hex, 'opts': jsonable(opts, None, strict=False)}
        if tex is not None:
            out.update(texture_spec(tex))
        else:
            out['map'] = None
        for k, v in self.extra.items():
            out[k] = jsonable(v, None, strict=False)
        ud = {k: v for k, v in self.userData.items() if k != 'daToon'}
        if ud:
            out['userData'] = jsonable(ud, None, strict=False)
        if self.name and 'name' not in out['opts'] and self.kind not in ('toon',):
            out['name'] = self.name
        return out

    def preview(self):
        """Values for the Blender Principled BSDF preview: base (linear rgb), alpha, rough, metal, emission."""
        o = self.opts
        if self.kind == 'glow':
            c = Color(self.hex)
            return dict(base=(c.r, c.g, c.b), alpha=self.opacity if self.transparent else 1.0, rough=1.0,
                        metal=0.0, emission=(c.r, c.g, c.b), strength=float(o.get('intensity', 1)))
        if self.kind == 'screen':
            return dict(base=(0.02, 0.03, 0.025), alpha=1.0, rough=0.1, metal=0.0, emission=(0.2, 0.3, 0.25),
                        strength=0.5)
        c = self.color
        em = self.emissive
        return dict(base=(c.r, c.g, c.b), alpha=float(self.opacity) if self.transparent else 1.0,
                    rough=float(o.get('rough', 0.75)) if self.kind == 'toon' else 1.0,
                    metal=float(o.get('metal', 0)) if self.kind == 'toon' else 0.0,
                    emission=(em.r, em.g, em.b), strength=float(self.emissiveIntensity) if em.getHex() else 0.0)


def texture_spec(tex):
    """Spec keys for a material map (canvas texture or gfx card)."""
    if getattr(tex, 'isCard', False):
        return {'map': None, 'card': tex.card, 'cardOpts': jsonable(tex.cardOpts, None, strict=False)}
    wrap = 'repeat' if getattr(tex, 'wrapS', 1001) == 1000 else 'clamp'
    filt = 'nearest' if getattr(tex, 'magFilter', 1006) == 1003 else 'linear'
    f = getattr(tex, 'res_path', None)
    f = (f() if callable(f) else f) if f else None   # (also gives anonymous canvas textures their key)
    d = {'map': getattr(tex, 'key', None) or getattr(tex, 'name', None), 'mapWrap': wrap, 'mapFilter': filt,
         'flipY': bool(getattr(tex, 'flipY', True))}
    if f:
        d['mapFile'] = f
    if getattr(tex, 'isRuntime', False):
        d['runtime'] = True
    return d


# ================================================================================================ JSON-safety
def jsonable(v, names=None, strict=True, _depth=0):
    """userData -> JSON-safe value. Object3D -> {"__node": name} (names: dict node->final name), Material ->
    {"__material": spec}, Texture -> {"__texture": key}, Vector/Euler/Quaternion -> lists, Color -> '#hex',
    Matrix -> 16 floats (column-major), numpy -> lists, functions -> None."""
    if _depth > 12:
        return None
    if v is None or isinstance(v, (bool, str)):
        return v
    if isinstance(v, (int, float)):
        if isinstance(v, float) and not math.isfinite(v):
            return None if strict else (1e308 if v > 0 else -1e308) if not math.isnan(v) else None
        return v
    if isinstance(v, (np.integer,)):
        return int(v)
    if isinstance(v, (np.floating,)):
        return float(v)
    if isinstance(v, np.ndarray):
        return v.tolist()
    if getattr(v, 'isObject3D', False):
        if names is None:
            return {'__node': v.name}
        return {'__node': names.get(id(v), v.name)}
    if isinstance(v, Material):
        return {'__material': v.spec()}
    if getattr(v, 'isTexture', False) or getattr(v, 'isCard', False):
        return {'__texture': texture_spec(v)}
    if getattr(v, 'isVector3', False):
        return [v.x, v.y, v.z]
    if getattr(v, 'isVector2', False):
        return [v.x, v.y]
    if getattr(v, 'isVector4', False) or getattr(v, 'isQuaternion', False):
        return [v.x, v.y, v.z, v.w]
    if getattr(v, 'isEuler', False):
        return [v.x, v.y, v.z]
    if getattr(v, 'isColor', False):
        return '#' + v.getHexString()
    if getattr(v, 'isMatrix4', False) or getattr(v, 'isMatrix3', False):
        return list(v.elements)
    if getattr(v, 'isBox3', False):
        return {'min': [v.min.x, v.min.y, v.min.z], 'max': [v.max.x, v.max.y, v.max.z]}
    if isinstance(v, dict):
        return {str(k): jsonable(x, names, strict, _depth + 1) for k, x in v.items()}
    if isinstance(v, (list, tuple)):
        return [jsonable(x, names, strict, _depth + 1) for x in v]
    if getattr(v, 'isBufferGeometry', False) is True:
        return {'__geometry': getattr(v, 'name', '') or getattr(v, 'type', 'BufferGeometry')}
    if callable(v):
        return None
    return str(v)


# ===================================================================================================== names
_BAD = re.compile(r'[^A-Za-z0-9_\-]+')
# Godot's scene importer turns nodes whose name ends with -<hint>/_<hint> (after trailing digits) into colliders,
# wheels … (ResourceImporterScene::_teststr). Names that would trigger a hint get a trailing "_n".
_HINTS = ('noimp', 'col', 'convcol', 'colonly', 'convcolonly', 'rigid', 'rigidbody', 'navmesh', 'occ', 'occonly',
          'loop', 'cycle', 'vehicle', 'wheel', 'sb', 'shape')


def _safe(name):
    n = _BAD.sub('_', name or '').strip('_')
    if not n:
        return ''
    if n[0].isdigit():
        n = 'n' + n
    base = n.rstrip('0123456789 .')
    low = base.lower()
    if '$' in (name or '') or any(low.endswith('-' + h) or low.endswith('_' + h) for h in _HINTS):
        n = n + '_n'
    return n[:60]


def assign_names(root, root_name=None):
    """Unique, deterministic, Godot-safe names for every node (dict id(node) -> name), traverse order. JS names
    are kept (':' '.' '/' etc. become '_'); repeats get _1, _2 …; unnamed nodes get <type>_<n>."""
    names = {}
    used = set()
    counters = {}

    def uniq(base):
        if base not in used:
            used.add(base)
            return base
        i = counters.get(base, 1)
        while '%s_%d' % (base, i) in used:
            i += 1
        counters[base] = i + 1
        n = '%s_%d' % (base, i)
        used.add(n)
        return n

    def visit(o, is_root):
        if is_root:
            n = _safe(root_name or o.name or 'root') or 'root'
        else:
            n = _safe(o.name)
            if not n:
                kind = 'inst' if getattr(o, 'isInstancedMesh', False) else 'mesh' if getattr(o, 'geometry', None) \
                    is not None else 'group'
                n = kind
        names[id(o)] = uniq(n)
        if getattr(o, 'isInstancedMesh', False):
            base = names[id(o)]
            for i in range(o.count):
                names[(id(o), i)] = uniq('%s_%d' % (base, i))
        for c in o.children:
            visit(c, False)
    visit(root, True)
    return names


# ============================================================================================= Blender build
def _b_vec(x, y, z):
    return (x, -z, y)


def _attr_np(attr, width=None):
    if attr is None:
        return None
    a = np.asarray(attr.array)
    n = attr.count
    k = attr.itemSize
    a = a.reshape(-1)[:n * k].reshape(n, k).astype(np.float64)
    if getattr(attr, 'normalized', False):
        dt = np.asarray(attr.array).dtype
        if dt == np.uint8:
            a = a / 255.0
        elif dt == np.uint16:
            a = a / 65535.0
        elif dt == np.int8:
            a = np.maximum(a / 127.0, -1)
        elif dt == np.int16:
            a = np.maximum(a / 32767.0, -1)
    if width is not None and a.shape[1] < width:
        a = np.c_[a, np.ones((n, width - a.shape[1]))]
    return a


def _uv_transform(tex):
    """three texture.updateMatrix(): uvTransform (offset, repeat, rotation, center) as a 3x3 matrix or None."""
    if tex is None or getattr(tex, 'isCard', False):
        return None
    rep = getattr(tex, 'repeat', None)
    off = getattr(tex, 'offset', None)
    rot = getattr(tex, 'rotation', 0) or 0
    cen = getattr(tex, 'center', None)
    rx, ry = (rep.x, rep.y) if rep is not None else (1, 1)
    ox, oy = (off.x, off.y) if off is not None else (0, 0)
    cx, cy = (cen.x, cen.y) if cen is not None else (0, 0)
    if rx == 1 and ry == 1 and ox == 0 and oy == 0 and rot == 0:
        return None
    m = Matrix3().setUvTransform(ox, oy, rx, ry, rot, cx, cy)
    return np.array(m.elements, dtype=np.float64).reshape(3, 3).T  # row-major


class _Builder:
    def __init__(self, names, texture_file, force_names=True):
        import bpy
        self.force_names = force_names
        self.bpy = bpy
        self.names = names
        self.texture_file = texture_file  # tex -> (abs_path, res_path) or None
        self.mats = {}
        self.meshes = {}
        self.coll = bpy.context.scene.collection

    # -------------------------------------------------------------------------------------- materials
    def material(self, m):
        if m is None:
            return None
        key = m.uuid
        bm = self.mats.get(key)
        if bm is not None:
            return bm
        bpy = self.bpy
        spec = m.spec()
        base = m.name or '%s_%s' % (m.kind, m.hex.lstrip('#'))
        bname = _safe(base) or 'mat'
        n, i = bname, 1
        while n in bpy.data.materials:
            n = '%s_%d' % (bname, i)
            i += 1
        bm = bpy.data.materials.new(n)
        bm['da'] = json.dumps(spec, separators=(',', ':'))
        pv = m.preview()
        bm.use_nodes = True
        nt = bm.node_tree
        bsdf = next((nd for nd in nt.nodes if nd.type == 'BSDF_PRINCIPLED'), None)
        if bsdf is not None:
            bsdf.inputs['Base Color'].default_value = (*pv['base'], 1.0)
            bsdf.inputs['Roughness'].default_value = pv['rough']
            bsdf.inputs['Metallic'].default_value = pv['metal']
            if pv['alpha'] < 1.0:
                bsdf.inputs['Alpha'].default_value = pv['alpha']
                try:
                    bm.surface_render_method = 'BLENDED'
                except Exception:
                    pass
            if pv['strength'] > 0:
                ek = 'Emission Color' if 'Emission Color' in bsdf.inputs else 'Emission'
                bsdf.inputs[ek].default_value = (*pv['emission'], 1.0)
                bsdf.inputs['Emission Strength'].default_value = pv['strength']
            tex = m.map
            if tex is not None and not getattr(tex, 'isCard', False) and self.texture_file is not None:
                f = self.texture_file(tex)
                if f:
                    img = bpy.data.images.load(f[0], check_existing=True)
                    tn = nt.nodes.new('ShaderNodeTexImage')
                    tn.image = img
                    tn.interpolation = 'Closest' if spec.get('mapFilter') == 'nearest' else 'Linear'
                    tn.extension = 'REPEAT' if spec.get('mapWrap') == 'repeat' else 'EXTEND'
                    # three CanvasTexture flipY: sample (u, 1 - v) of the three uv (Blender stores 1 - v)
                    uvn = nt.nodes.new('ShaderNodeUVMap')
                    sep = nt.nodes.new('ShaderNodeSeparateXYZ')
                    comb = nt.nodes.new('ShaderNodeCombineXYZ')
                    sub = nt.nodes.new('ShaderNodeMath')
                    sub.operation = 'SUBTRACT'
                    sub.inputs[0].default_value = 1.0
                    nt.links.new(uvn.outputs[0], sep.inputs[0])
                    nt.links.new(sep.outputs[0], comb.inputs[0])
                    nt.links.new(sep.outputs[1], sub.inputs[1])
                    nt.links.new(sub.outputs[0], comb.inputs[1])
                    nt.links.new(comb.outputs[0], tn.inputs[0])
                    if m.kind == 'glow':
                        nt.links.new(tn.outputs['Color'], bsdf.inputs[ek if pv['strength'] > 0 else 'Base Color'])
                    else:
                        mix = nt.nodes.new('ShaderNodeMix')
                        mix.data_type = 'RGBA'
                        mix.blend_type = 'MULTIPLY'
                        mix.inputs['Factor'].default_value = 1.0
                        mix.inputs[7].default_value = (*pv['base'], 1.0)
                        nt.links.new(tn.outputs['Color'], mix.inputs[6])
                        nt.links.new(mix.outputs[2], bsdf.inputs['Base Color'])
                    if m.transparent:
                        nt.links.new(tn.outputs['Alpha'], bsdf.inputs['Alpha'])
        bm.diffuse_color = (*pv['base'], pv['alpha'])
        if m.side == DoubleSide:
            bm.use_backface_culling = False
        else:
            bm.use_backface_culling = True
        self.mats[key] = bm
        return bm

    # ------------------------------------------------------------------------------------------ meshes
    def mesh_data(self, geo, mat, name, inst_color=None):
        key = (id(geo), mat.uuid if mat is not None else None, tuple(inst_color) if inst_color else None)
        me = self.meshes.get(key)
        if me is not None:
            return me
        bpy = self.bpy
        pos = _attr_np(geo.attributes.position)
        n = len(pos)
        if geo.index is not None:
            idx = np.asarray(geo.index.array).reshape(-1)[:geo.index.count].astype(np.int64)
        else:
            idx = np.arange(n - n % 3, dtype=np.int64)
        # three draw range / groups are not used by props; degenerate-by-index triangles are dropped (Blender
        # rejects them; they cover no pixels in three either)
        tris = idx.reshape(-1, 3)
        ok = (tris[:, 0] != tris[:, 1]) & (tris[:, 1] != tris[:, 2]) & (tris[:, 0] != tris[:, 2])
        ok &= (tris < n).all(axis=1)
        tris = tris[ok]
        me = bpy.data.meshes.new(name)
        vb = np.empty((n, 3), dtype=np.float32)
        vb[:, 0], vb[:, 1], vb[:, 2] = pos[:, 0], -pos[:, 2], pos[:, 1]
        me.vertices.add(n)
        me.vertices.foreach_set('co', vb.ravel())
        nl = tris.size
        me.loops.add(nl)
        me.loops.foreach_set('vertex_index', tris.ravel().astype(np.int32))
        me.polygons.add(len(tris))
        me.polygons.foreach_set('loop_start', np.arange(0, nl, 3, dtype=np.int32))
        me.update(calc_edges=True)
        loop_v = tris.ravel()
        # UVs (three uv, texture repeat/offset baked, stored as 1 - v: the glTF exporter flips it back)
        uv = _attr_np(geo.attributes.uv) if geo.attributes.uv is not None else None
        if uv is not None:
            xf = _uv_transform(getattr(mat, 'map', None)) if mat is not None else None
            if xf is not None:
                h = np.c_[uv[:, :2], np.ones(len(uv))] @ xf.T
                uv = h[:, :2]
            lu = uv[loop_v]
            arr = np.empty((nl, 2), dtype=np.float32)
            arr[:, 0] = lu[:, 0]
            arr[:, 1] = 1.0 - lu[:, 1]
            layer = me.uv_layers.new(name='UVMap')
            layer.data.foreach_set('uv', arr.ravel())
        for extra_name in ('uv1', 'uv2'):
            a = getattr(geo.attributes, extra_name, None) if hasattr(geo.attributes, extra_name) else None
            if a is not None:
                u2 = _attr_np(a)[loop_v]
                arr = np.empty((nl, 2), dtype=np.float32)
                arr[:, 0] = u2[:, 0]
                arr[:, 1] = 1.0 - u2[:, 1]
                layer = me.uv_layers.new(name='UV' + extra_name[-1])
                layer.data.foreach_set('uv', arr.ravel())
        # vertex colours (linear, like three's color attribute)
        col = _attr_np(geo.attributes.color, 3) if geo.attributes.color is not None else None
        if inst_color is not None:
            if col is None:
                col = np.ones((n, 3))
            col = col.copy()
            col[:, 0] *= inst_color[0]
            col[:, 1] *= inst_color[1]
            col[:, 2] *= inst_color[2]
        if col is not None:
            rgba = np.ones((n, 4), dtype=np.float32)
            rgba[:, :min(4, col.shape[1])] = col[:, :4]
            if col.shape[1] < 4:
                rgba[:, 3] = 1.0
            ca = me.color_attributes.new('Color', 'FLOAT_COLOR', 'POINT')
            ca.data.foreach_set('color', rgba.ravel())
            me.color_attributes.active_color = ca
            try:
                me.color_attributes.render_color_index = me.color_attributes.active_color_index
            except Exception:
                pass
        # normals: three's per-vertex normals as custom split normals
        nor = _attr_np(geo.attributes.normal) if geo.attributes.normal is not None else None
        if len(tris):
            me.polygons.foreach_set('use_smooth', np.ones(len(tris), dtype=bool))
        if nor is not None and len(tris):
            nb = np.empty((n, 3), dtype=np.float32)
            nb[:, 0], nb[:, 1], nb[:, 2] = nor[:, 0], -nor[:, 2], nor[:, 1]
            ln = np.linalg.norm(nb, axis=1)
            ln[ln == 0] = 1
            nb /= ln[:, None]
            me.normals_split_custom_set_from_vertices(nb.tolist() if False else [tuple(x) for x in nb])
        if mat is not None:
            me.materials.append(self.material(mat))
        self.meshes[key] = me
        return me

    # ----------------------------------------------------------------------------------------- objects
    def node(self, o, parent_bobj, name, data=None):
        bpy = self.bpy
        ob = bpy.data.objects.new(name, data)
        if ob.name != name and self.force_names:  # names are unique per scene: keep ours
            other = bpy.data.objects.get(name)
            if other is not None:
                other.name = name + '__old'
                ob.name = name
        self.coll.objects.link(ob)
        if parent_bobj is not None:
            ob.parent = parent_bobj
        return ob

    @staticmethod
    def set_trs(ob, pos, quat, scale):
        ob.rotation_mode = 'QUATERNION'
        ob.location = _b_vec(pos.x, pos.y, pos.z)
        ob.rotation_quaternion = (quat.w, quat.x, -quat.z, quat.y)
        ob.scale = (scale.x, scale.z, scale.y)


def node_da(o, names, is_root=False):
    """The "da" custom property of a node (child flags / root userData), JSON-safe."""
    ud = o.userData
    d = {}
    if is_root:
        d = root_userdata(o, names)
    else:
        if ud:
            d.update(jsonable(ud, names, strict=False))
    if getattr(o, 'isMesh', False) or getattr(o, 'isLine', False) or getattr(o, 'isPoints', False):
        d['castShadow'] = bool(o.castShadow)
        if not o.receiveShadow:
            d['receiveShadow'] = False
    if not o.visible:
        d['visible'] = False
    if o.renderOrder:
        d['renderOrder'] = o.renderOrder
    if o.layers.mask != 1:
        d['layers'] = o.layers.mask
    if o.rotation.order != 'XYZ':
        d['rotationOrder'] = o.rotation.order
    if getattr(o, 'isLine', False):
        d['primitive'] = 'LineSegments' if getattr(o, 'isLineSegments', False) else 'Line'
    if getattr(o, 'isPoints', False):
        d['primitive'] = 'Points'
    return d


def root_userdata(root, names):
    """Root userData -> SPEC §5.4 JSON: parts {name: node name}, screens [{node, group, id?}], {"__node"} refs."""
    u = root.userData
    out = {}
    for k, v in u.items():
        if k == 'parts' and isinstance(v, dict):
            parts = {}
            for pk, pv in v.items():
                if getattr(pv, 'isObject3D', False):
                    parts[pk] = names.get(id(pv), pv.name)
                else:
                    parts[pk] = jsonable(pv, names, strict=False)
            out['parts'] = parts
        elif k == 'screens' and isinstance(v, list):
            scr = []
            for s in v:
                s2 = {}
                for sk, sv in (s.items() if isinstance(s, dict) else []):
                    if sk == 'mesh':
                        s2['node'] = names.get(id(sv), getattr(sv, 'name', '')) if sv is not None else None
                    else:
                        s2[sk] = jsonable(sv, names, strict=False)
                scr.append(s2)
            out['screens'] = scr
        else:
            out[k] = jsonable(v, names, strict=False)
    return out


def to_blender(root, names=None, texture_file=None, root_name=None, force_names=True):
    """Creates Blender objects for the graph under root (in the current scene). Returns the root bpy object.
    texture_file(tex) -> (abs_png_path, res_path) or None (see dalib/tex.py). force_names: rename clashing
    objects already in the file so ours keep their exact names (export into a fresh scene); False when adding
    to a scene the user is working in (Blender then suffixes .001)."""
    if names is None:
        names = assign_names(root, root_name)
    root.updateMatrixWorld(True)
    B = _Builder(names, texture_file, force_names)

    def visit(o, parent_b, is_root):
        name = names[id(o)]
        inst = getattr(o, 'isInstancedMesh', False)
        geo = getattr(o, 'geometry', None)
        data = None
        mt = getattr(o, 'material', None)
        if isinstance(mt, Material) and mt.kind == 'screen':
            # the CRT spec carries the screen group / id the ScreenManager registers it with
            sc = mt.extra.setdefault('screen', {})
            if o.userData.screenGroup and 'group' not in sc:
                sc['group'] = o.userData.screenGroup
            for s in (root.userData.screens or []):
                if isinstance(s, dict) and s.get('mesh') is o:
                    sc.setdefault('group', s.get('group'))
                    if s.get('id') is not None:
                        sc['id'] = s.get('id')
        if geo is not None and not inst:
            data = B.mesh_data(geo, o.material if not isinstance(o.material, list) else o.material[0], name)
        ob = B.node(o, parent_b, name, data)
        if is_root:
            ob.location = (0, 0, 0)
        B.set_trs(ob, o.position, o.quaternion, o.scale)
        da = node_da(o, names, is_root)
        if inst:
            da['instanced'] = True
            da['count'] = o.count
        if da:
            ob['da'] = json.dumps(da, separators=(',', ':'))
        if not o.visible:
            ob.hide_set(True) if False else None
        if inst:
            p, q, s = Vector3(), Quaternion(), Vector3()
            for i in range(o.count):
                o.instanceMatrix[i].decompose(p, q, s)
                ic = None
                if o.instanceColor is not None:
                    c = o.instanceColor[i]
                    ic = (c.r, c.g, c.b)
                me = B.mesh_data(geo, o.material, '%s_mesh' % name, ic)
                cname = names[(id(o), i)]
                ch = B.node(o, ob, cname, me)
                B.set_trs(ch, p, q, s)
                cd = {'instance': i, 'castShadow': bool(o.castShadow)}
                if ic is not None:
                    cd['instanceColor'] = [c.r, c.g, c.b]
                ch['da'] = json.dumps(cd, separators=(',', ':'))
        for c in o.children:
            visit(c, ob, False)
        return ob
    return visit(root, None, True)
