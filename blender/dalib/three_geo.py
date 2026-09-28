"""Exact Python/numpy port of the three.js (r186) geometry code the game uses. No bpy.

    from dalib import three_geo as THREE
    g = THREE.CylinderGeometry(0.1, 0.1, 0.5, 16)
    g.rotateX(math.pi / 2).translate(0, 0.2, 0)
    p = g.attributes.position              # BufferAttribute: numpy (N, 3) float64 array + three's API
    p.getY(0); p.setXYZ(0, x, y, z); p.count; p.itemSize; p.array (flat view)

Every class keeps three's constructor signature, defaults, vertex order, index, groups, uvs and normals
(verified against node three by dalib/tests/test_three_geo.py).

FLOAT32 EMULATION: three stores attributes in Float32Array. BufferAttribute stores float64 numbers but every
write (constructor, setX/setXY/setXYZ/setXYZW/setComponent, item assignment `a[i, j] = v`, in-place numpy ufuncs
`a *= 2`, np.add.at) rounds to the nearest float32, exactly like a Float32Array store. So reads (getX, a[i, j])
return the same doubles JS reads, and threshold tests / hashing (mergeVertices, `Math.round(x * 1e5)` keys)
behave identically. Views returned by slicing (`a[:, 1]`) are plain numpy arrays: writing through them bypasses the
rounding (assign through the attribute instead: `a[:, 1] = v` rounds). Integer attributes/index are int64.

Truthiness: a BufferAttribute is always truthy (a JS object); `geometry.attributes` is a JSObj (dict with
attribute access) whose missing keys read as None, so `if not g.attributes.color:` ports 1:1; assigning a plain
array to it (`g.attributes['uv'] = arr`) wraps it into a BufferAttribute (itemSize from shape / attribute name).
JS `undefined` arguments: constructors, geo.* helpers, Path.arc/absarc/ellipse/absellipse, getPoints... treat a None
argument as the JS default. Integer-valued float segment counts (24.0) work like ints.

Contents: BufferAttribute (+ Float32/Uint16/Uint32 aliases), Geometry (= BufferGeometry), Box/Plane/Circle/Ring/
Cylinder/Cone/Sphere/Torus/Lathe/Capsule/Polyhedron/Icosahedron/Octahedron/Tetrahedron/Dodecahedron/Tube/Shape/
Extrude geometries, RoundedBoxGeometry and ConvexGeometry (+ ConvexHull) from the addons, Curve machinery
(Curve, LineCurve(3), QuadraticBezierCurve(3), CubicBezierCurve(3), EllipseCurve, ArcCurve, SplineCurve,
CatmullRomCurve3, CurvePath, Path, Shape), ShapeUtils, Earcut, and BufferGeometryUtils mergeGeometries /
mergeAttributes / mergeVertices. The three math classes are re-exported (THREE.Vector3, THREE.MathUtils ...).
"""

import math
import sys
from functools import cmp_to_key

import numpy as np

from .mathutils3 import (  # noqa: F401  (re-exported: THREE.Vector3 ...)
    JSObj, Vector2, Vector3, Vector4, Matrix3, Matrix4, Quaternion, Euler, Color, Box3, Sphere, Line3, Plane,
    Triangle, MathUtils, ColorManagement, SRGBColorSpace, LinearSRGBColorSpace, EPSILON, MAX_VALUE,
    clamp, generateUUID, js_sign, to_int32, js_round, js_str, js_json, js_defaults,
)

_INF = float('inf')
_NAN = float('nan')


def _warn(msg):
    sys.stderr.write('THREE(py): ' + msg + '\n')


def _f32(a):
    """float64 ndarray -> new float64 ndarray holding the float32-rounded values."""
    return np.asarray(a, dtype=np.float64).astype(np.float32).astype(np.float64)


def _f32_inplace(a):
    a[...] = a.astype(np.float32)


def _f32s(v):
    return float(np.float32(v))


# ============================================================================================ BufferAttribute

class BufferAttribute(np.ndarray):
    """THREE.BufferAttribute as a numpy array of shape (count, itemSize) (the index is 1-D, shape (count,)).

    BufferAttribute(array, itemSize=None, normalized=False, dtype=None): `array` = list / ndarray (copied).
    dtype None -> float (float32 emulation) unless `array` is an integer ndarray; 'int' / 'float' to force.
    """
    isBufferAttribute = True

    def __new__(cls, array, itemSize=None, normalized=False, dtype=None, _flat=False):
        src = array
        if isinstance(src, np.ndarray):
            src = src.view(np.ndarray)
        a = np.asarray(src)
        if dtype is None:
            is_int = isinstance(array, np.ndarray) and a.dtype.kind in 'iub'
        else:
            is_int = dtype in ('int', 'i', int) or (not isinstance(dtype, str) and np.dtype(dtype).kind in 'iub')
        if is_int:
            data = np.array(a, dtype=np.int64)
        else:
            data = np.array(a, dtype=np.float64)
            _f32_inplace(data)
        if _flat:
            data = data.reshape(-1)
        else:
            if itemSize is None:
                itemSize = data.shape[1] if data.ndim == 2 else 1
            data = data.reshape(-1, int(itemSize))
        obj = data.view(cls)
        obj.normalized = normalized
        obj.name = ''
        return obj

    def __array_finalize__(self, obj):
        if obj is None:
            return
        self.normalized = getattr(obj, 'normalized', False)
        self.name = getattr(obj, 'name', '')

    # -- float32 rounding on writes ------------------------------------------------------------------------
    def __array_ufunc__(self, ufunc, method, *inputs, out=None, **kwargs):
        args = tuple(x.view(np.ndarray) if isinstance(x, BufferAttribute) else x for x in inputs)
        if out is not None:
            outs = tuple(o.view(np.ndarray) if isinstance(o, BufferAttribute) else o for o in out)
            getattr(ufunc, method)(*args, out=outs, **kwargs)
            for o in out:
                if isinstance(o, BufferAttribute) and o.dtype.kind == 'f':
                    _f32_inplace(o.view(np.ndarray))
            return out[0] if len(out) == 1 else out
        res = getattr(ufunc, method)(*args, **kwargs)
        if method == 'at' and isinstance(inputs[0], BufferAttribute) and inputs[0].dtype.kind == 'f':
            _f32_inplace(inputs[0].view(np.ndarray))
        return res

    def __setitem__(self, key, value):
        if self.dtype.kind == 'f':
            value = np.asarray(value, dtype=np.float64).astype(np.float32)
        np.ndarray.__setitem__(self, key, value)

    def __getitem__(self, key):
        r = np.ndarray.__getitem__(self, key)
        if isinstance(r, BufferAttribute):
            return r.view(np.ndarray)
        return r

    def __bool__(self):  # JS objects are always truthy
        return True

    def __reduce__(self):
        return (_rebuild_attr, (np.asarray(self.view(np.ndarray)), self.dtype.kind, self.ndim == 1,
                                getattr(self, 'normalized', False)))

    # -- three API -----------------------------------------------------------------------------------------
    @property
    def count(self):
        return self.shape[0] if self.ndim >= 1 else 1

    @property
    def itemSize(self):
        return self.shape[1] if self.ndim == 2 else 1

    @property
    def array(self):
        """Flat view (JS typed array); writes through it are float32-rounded too."""
        return self.reshape(-1)

    @property
    def needsUpdate(self):
        return False

    @needsUpdate.setter
    def needsUpdate(self, v):
        pass

    def setUsage(self, usage):
        return self

    def _set1(self, i, c, v):
        if self.dtype.kind == 'f':
            v = np.float32(v)
        if self.ndim == 2:
            np.ndarray.__setitem__(self, (i, c), v)
        else:
            np.ndarray.__setitem__(self, i, v)

    def getX(self, i):
        return self.item(i, 0) if self.ndim == 2 else self.item(i)

    def getY(self, i):
        return self.item(i, 1)

    def getZ(self, i):
        return self.item(i, 2)

    def getW(self, i):
        return self.item(i, 3)

    def getComponent(self, i, c):
        return self.item(i, c) if self.ndim == 2 else self.item(i * 1 + c)

    def setComponent(self, i, c, v):
        self._set1(i, c, v)
        return self

    def setX(self, i, x):
        self._set1(i, 0, x)
        return self

    def setY(self, i, y):
        self._set1(i, 1, y)
        return self

    def setZ(self, i, z):
        self._set1(i, 2, z)
        return self

    def setW(self, i, w):
        self._set1(i, 3, w)
        return self

    def setXY(self, i, x, y):
        v = np.array((x, y), dtype=np.float32 if self.dtype.kind == 'f' else np.int64)
        np.ndarray.__setitem__(self, (i, slice(0, 2)), v)
        return self

    def setXYZ(self, i, x, y, z):
        v = np.array((x, y, z), dtype=np.float32 if self.dtype.kind == 'f' else np.int64)
        np.ndarray.__setitem__(self, (i, slice(0, 3)), v)
        return self

    def setXYZW(self, i, x, y, z, w):
        v = np.array((x, y, z, w), dtype=np.float32 if self.dtype.kind == 'f' else np.int64)
        np.ndarray.__setitem__(self, (i, slice(0, 4)), v)
        return self

    def set(self, value, offset=0):
        flat = self.reshape(-1)
        value = np.asarray(value).reshape(-1)
        flat[offset:offset + len(value)] = value
        return self

    def clone(self):
        return self.copy()

    def copyArray(self, array):
        self.reshape(-1)[:] = np.asarray(array).reshape(-1)
        return self

    def _xyz(self):
        a = self.view(np.ndarray)
        return a[:, 0], a[:, 1], a[:, 2]

    def _store3(self, x, y, z):
        a = self.view(np.ndarray)
        a[:, 0] = x
        a[:, 1] = y
        a[:, 2] = z
        if self.dtype.kind == 'f':
            _f32_inplace(a)

    def applyMatrix3(self, m):
        e = m.elements
        a = self.view(np.ndarray)
        if self.itemSize == 2:
            x, y = a[:, 0].copy(), a[:, 1].copy()
            a[:, 0] = e[0] * x + e[3] * y + e[6]
            a[:, 1] = e[1] * x + e[4] * y + e[7]
            _f32_inplace(a)
        elif self.itemSize == 3:
            x, y, z = (c.copy() for c in self._xyz())
            self._store3(e[0] * x + e[3] * y + e[6] * z, e[1] * x + e[4] * y + e[7] * z,
                         e[2] * x + e[5] * y + e[8] * z)
        return self

    def applyMatrix4(self, m):
        e = m.elements
        x, y, z = (c.copy() for c in self._xyz())
        with np.errstate(divide='ignore', invalid='ignore'):
            w = 1 / (e[3] * x + e[7] * y + e[11] * z + e[15])
        self._store3((e[0] * x + e[4] * y + e[8] * z + e[12]) * w,
                     (e[1] * x + e[5] * y + e[9] * z + e[13]) * w,
                     (e[2] * x + e[6] * y + e[10] * z + e[14]) * w)
        return self

    def applyNormalMatrix(self, m):
        e = m.elements
        x, y, z = (c.copy() for c in self._xyz())
        nx = e[0] * x + e[3] * y + e[6] * z
        ny = e[1] * x + e[4] * y + e[7] * z
        nz = e[2] * x + e[5] * y + e[8] * z
        self._store3(*_normalize3(nx, ny, nz))
        return self

    def transformDirection(self, m):
        e = m.elements
        x, y, z = (c.copy() for c in self._xyz())
        nx = e[0] * x + e[4] * y + e[8] * z
        ny = e[1] * x + e[5] * y + e[9] * z
        nz = e[2] * x + e[6] * y + e[10] * z
        self._store3(*_normalize3(nx, ny, nz))
        return self


def _rebuild_attr(arr, kind, flat, normalized):
    return BufferAttribute(arr, None if flat else (arr.shape[1] if arr.ndim == 2 else 1), normalized,
                           dtype='int' if kind in 'iub' else 'float', _flat=flat)


def _normalize3(x, y, z):
    """Vector3.normalize() vectorised: v * (1 / (length || 1)) (same op order as JS)."""
    l = np.sqrt(x * x + y * y + z * z)
    l = np.where((l == 0) | np.isnan(l), 1.0, l)
    inv = 1 / l
    return x * inv, y * inv, z * inv


def Float32BufferAttribute(array, itemSize, normalized=False):
    """new THREE.Float32BufferAttribute(arrayOrLength, itemSize) (a number = zero-filled length, like a TypedArray)."""
    if isinstance(array, (int, np.integer)) and not isinstance(array, bool):
        array = np.zeros(int(array))
    return BufferAttribute(array, itemSize, normalized, dtype='float')


def Uint16BufferAttribute(array, itemSize, normalized=False):
    if isinstance(array, (int, np.integer)) and not isinstance(array, bool):
        array = np.zeros(int(array), dtype=np.int64)
    return BufferAttribute(array, itemSize, normalized, dtype='int')


Uint32BufferAttribute = Uint16BufferAttribute
Int32BufferAttribute = Uint16BufferAttribute
Uint8BufferAttribute = Uint16BufferAttribute
Int16BufferAttribute = Uint16BufferAttribute


def _as_index(index):
    if index is None:
        return None
    if isinstance(index, BufferAttribute) and index.ndim == 1:
        return index
    return BufferAttribute(np.asarray(index, dtype=np.int64).reshape(-1), dtype='int', _flat=True)


# ============================================================================================ Geometry

_ITEM = {'position': 3, 'normal': 3, 'color': 3, 'tangent': 4, 'uv': 2, 'uv1': 2, 'uv2': 2, 'uv3': 2,
         'skinIndex': 4, 'skinWeight': 4}


class _Attributes(JSObj):
    """geometry.attributes: JSObj whose item/attribute assignment wraps plain arrays into BufferAttributes
    (itemSize from a 2-D shape, else from the usual attribute name, else 1)."""
    __slots__ = ()

    def __setitem__(self, k, v):
        if v is not None and not isinstance(v, BufferAttribute):
            a = np.asarray(v)
            v = BufferAttribute(a, a.shape[1] if a.ndim == 2 else _ITEM.get(k, 1))
        dict.__setitem__(self, k, v)


_geo_id = [0]


class Geometry:
    """THREE.BufferGeometry (numpy-backed). Primitive geometries below are subclasses."""
    isBufferGeometry = True

    def __init__(self):
        self.id = _geo_id[0]
        _geo_id[0] += 1
        self.uuid = generateUUID()
        self.name = ''
        self.type = 'BufferGeometry'
        self.index = None
        self.attributes = _Attributes()
        self.morphAttributes = JSObj()
        self.morphTargetsRelative = False
        self.groups = []
        self.boundingBox = None
        self.boundingSphere = None
        self.drawRange = JSObj(start=0, count=_INF)
        self.userData = JSObj()
        self.parameters = None

    def __repr__(self):
        p = self.attributes.get('position')
        return '<%s %r verts=%d index=%s groups=%d>' % (
            self.type, self.name, p.count if p is not None else 0,
            'None' if self.index is None else self.index.count, len(self.groups))

    # -- attributes / index / groups ----------------------------------------------------------------------
    def getIndex(self):
        return self.index

    def setIndex(self, index):
        self.index = _as_index(index)
        return self

    def getAttribute(self, name):
        return self.attributes.get(name)

    def setAttribute(self, name, attribute, itemSize=None):
        if (isinstance(attribute, BufferAttribute) and attribute.ndim == 2 and
                (itemSize is None or itemSize == attribute.shape[1])):
            self.attributes[name] = attribute
        else:
            self.attributes[name] = BufferAttribute(attribute, itemSize)
        return self

    def deleteAttribute(self, name):
        self.attributes.pop(name, None)
        return self

    def hasAttribute(self, name):
        return name in self.attributes

    def addGroup(self, start, count, materialIndex=0):
        self.groups.append(JSObj(start=start, count=count, materialIndex=materialIndex))

    def clearGroups(self):
        self.groups = []

    def setDrawRange(self, start, count):
        self.drawRange.start = start
        self.drawRange.count = count

    # -- transforms ------------------------------------------------------------------------------------------
    def applyMatrix4(self, matrix):
        position = self.attributes.get('position')
        if position is not None:
            position.applyMatrix4(matrix)
        normal = self.attributes.get('normal')
        if normal is not None:
            normalMatrix = Matrix3().getNormalMatrix(matrix)
            normal.applyNormalMatrix(normalMatrix)
        tangent = self.attributes.get('tangent')
        if tangent is not None:
            tangent.transformDirection(matrix)
        if self.boundingBox is not None:
            self.computeBoundingBox()
        if self.boundingSphere is not None:
            self.computeBoundingSphere()
        return self

    def applyQuaternion(self, q):
        return self.applyMatrix4(Matrix4().makeRotationFromQuaternion(q))

    def rotateX(self, angle):
        return self.applyMatrix4(Matrix4().makeRotationX(angle))

    def rotateY(self, angle):
        return self.applyMatrix4(Matrix4().makeRotationY(angle))

    def rotateZ(self, angle):
        return self.applyMatrix4(Matrix4().makeRotationZ(angle))

    def translate(self, x, y, z):
        return self.applyMatrix4(Matrix4().makeTranslation(x, y, z))

    def scale(self, x, y, z):
        return self.applyMatrix4(Matrix4().makeScale(x, y, z))

    def lookAt(self, vector):
        # _obj.lookAt(vector): Object3D at the origin (non camera) -> m.lookAt(target, position, up)
        m1 = Matrix4().lookAt(_v3(vector), Vector3(0, 0, 0), Vector3(0, 1, 0))
        q = Quaternion().setFromRotationMatrix(m1)
        return self.applyMatrix4(Matrix4().compose(Vector3(0, 0, 0), q, Vector3(1, 1, 1)))

    def center(self):
        self.computeBoundingBox()
        offset = self.boundingBox.getCenter(Vector3()).negate()
        self.translate(offset.x, offset.y, offset.z)
        return self

    def setFromPoints(self, points):
        pts = [(p.x, p.y, getattr(p, 'z', 0) or 0) if hasattr(p, 'x') else
               (p[0], p[1], (p[2] if len(p) > 2 else 0) or 0) for p in points]
        position = self.attributes.get('position')
        if position is None:
            self.setAttribute('position', Float32BufferAttribute(np.array(pts, dtype=float).reshape(-1), 3))
        else:
            l = min(len(pts), position.count)
            for i in range(l):
                position.setXYZ(i, *pts[i])
            if len(pts) > position.count:
                _warn('BufferGeometry: Buffer size too small for points data.')
        return self

    # -- bounds ----------------------------------------------------------------------------------------------
    def computeBoundingBox(self):
        if self.boundingBox is None:
            self.boundingBox = Box3()
        position = self.attributes.get('position')
        if position is not None:
            self.boundingBox.setFromBufferAttribute(position)
            morph = self.morphAttributes.get('position')
            if morph:
                for ma in morph:
                    b = Box3().setFromBufferAttribute(ma)
                    if self.morphTargetsRelative:
                        self.boundingBox.expandByPoint(Vector3().addVectors(self.boundingBox.min, b.min))
                        self.boundingBox.expandByPoint(Vector3().addVectors(self.boundingBox.max, b.max))
                    else:
                        self.boundingBox.expandByPoint(b.min)
                        self.boundingBox.expandByPoint(b.max)
        else:
            self.boundingBox.makeEmpty()
        return self.boundingBox  # (JS returns undefined; convenience)

    def computeBoundingSphere(self):
        if self.boundingSphere is None:
            self.boundingSphere = Sphere()
        position = self.attributes.get('position')
        if position is not None:
            center = self.boundingSphere.center
            box = Box3().setFromBufferAttribute(position)
            morph = self.morphAttributes.get('position')
            if morph:
                for ma in morph:
                    b = Box3().setFromBufferAttribute(ma)
                    if self.morphTargetsRelative:
                        box.expandByPoint(Vector3().addVectors(box.min, b.min))
                        box.expandByPoint(Vector3().addVectors(box.max, b.max))
                    else:
                        box.expandByPoint(b.min)
                        box.expandByPoint(b.max)
            box.getCenter(center)
            maxRadiusSq = 0
            if position.count:
                x, y, z = position._xyz()
                dx = center.x - x
                dy = center.y - y
                dz = center.z - z
                maxRadiusSq = max(0.0, float(np.max(dx * dx + dy * dy + dz * dz)))
            if morph:
                P = position.view(np.ndarray)
                for ma in morph:
                    M = ma.view(np.ndarray)
                    if self.morphTargetsRelative:
                        M = M[:, :3] + P[:, :3]
                    dx = center.x - M[:, 0]
                    dy = center.y - M[:, 1]
                    dz = center.z - M[:, 2]
                    if len(dx):
                        maxRadiusSq = max(maxRadiusSq, float(np.max(dx * dx + dy * dy + dz * dz)))
            self.boundingSphere.radius = math.sqrt(maxRadiusSq)
        return self.boundingSphere  # (JS returns undefined; convenience)

    # -- normals ---------------------------------------------------------------------------------------------
    def computeVertexNormals(self):
        """Bit-exact with three: per-vertex face-normal accumulation in triangle order with a float32 store
        after every addition, then normalizeNormals()."""
        index = self.index
        position = self.attributes.get('position')
        if position is None:
            return
        n = position.count
        normal = self.attributes.get('normal')
        if normal is None or normal.count != n:
            normal = BufferAttribute(np.zeros((n, 3)), 3)
            self.setAttribute('normal', normal)
        else:
            normal.view(np.ndarray)[...] = 0
        P = position.view(np.ndarray)
        N = normal.view(np.ndarray)
        if index is not None:
            idx = index.view(np.ndarray)
            nt = len(idx) // 3
            ia, ib, ic = idx[0:3 * nt:3], idx[1:3 * nt:3], idx[2:3 * nt:3]
            cr = _face_cross(P[ia, :3], P[ib, :3], P[ic, :3])
            tri = np.arange(nt)
            mb = ib != ia
            mc = (ic != ia) & (ic != ib)
            verts = np.concatenate([ia, ib[mb], ic[mc]])
            tris = np.concatenate([tri, tri[mb], tri[mc]])
            vals = np.concatenate([cr, cr[mb], cr[mc]])
            if len(verts):
                order = np.lexsort((tris, verts))
                verts, vals = verts[order], vals[order]
                start = np.r_[0, np.flatnonzero(verts[1:] != verts[:-1]) + 1]
                counts = np.diff(np.r_[start, len(verts)])
                rank = np.arange(len(verts)) - np.repeat(start, counts)
                acc = np.zeros((n, 3))
                for k in range(int(rank.max()) + 1):
                    sel = rank == k
                    v = verts[sel]
                    acc[v] = _f32(acc[v] + vals[sel])
                N[:, :3] = acc
        else:
            nt = n // 3
            cr = _face_cross(P[0:3 * nt:3, :3], P[1:3 * nt:3, :3], P[2:3 * nt:3, :3])
            cr = _f32(cr)
            N[0:3 * nt:3, :3] = cr
            N[1:3 * nt:3, :3] = cr
            N[2:3 * nt:3, :3] = cr
        self.normalizeNormals()

    def normalizeNormals(self):
        normals = self.attributes.get('normal')
        if normals is None:
            return
        x, y, z = (c.copy() for c in normals._xyz())
        normals._store3(*_normalize3(x, y, z))

    # -- conversions -----------------------------------------------------------------------------------------
    def toNonIndexed(self):
        if self.index is None:
            _warn('BufferGeometry.toNonIndexed(): BufferGeometry is already non-indexed.')
            return self
        geometry2 = Geometry()
        indices = self.index.view(np.ndarray)
        for name, attribute in self.attributes.items():
            geometry2.setAttribute(name, _convert_attr(attribute, indices))
        for name, morphAttribute in self.morphAttributes.items():
            geometry2.morphAttributes[name] = [_convert_attr(a, indices) for a in morphAttribute]
        geometry2.morphTargetsRelative = self.morphTargetsRelative
        for g in self.groups:
            geometry2.addGroup(g['start'], g['count'], g['materialIndex'])
        return geometry2

    def copy(self, source):
        self.index = None
        self.attributes = _Attributes()
        self.morphAttributes = JSObj()
        self.groups = []
        self.boundingBox = None
        self.boundingSphere = None
        self.name = source.name
        if source.index is not None:
            self.setIndex(source.index.clone())
        for name, attribute in source.attributes.items():
            self.setAttribute(name, attribute.clone())
        for name, morph in source.morphAttributes.items():
            self.morphAttributes[name] = [a.clone() for a in morph]
        self.morphTargetsRelative = source.morphTargetsRelative
        for g in source.groups:
            self.addGroup(g['start'], g['count'], g['materialIndex'])
        if source.boundingBox is not None:
            self.boundingBox = source.boundingBox.clone()
        if source.boundingSphere is not None:
            self.boundingSphere = source.boundingSphere.clone()
        self.drawRange.start = source.drawRange.start
        self.drawRange.count = source.drawRange.count
        self.userData = source.userData
        if type(self) is not Geometry and getattr(source, 'parameters', None) is not None:
            self.parameters = JSObj(source.parameters)
        return self

    def clone(self):
        """new this.constructor().copy(this) without re-running the primitive build (like kit.js
        fastGeometryClone): same class, type, parameters and data (+ TubeGeometry frames)."""
        g = self.__class__.__new__(self.__class__)
        Geometry.__init__(g)
        g.type = self.type
        g.copy(self)
        if hasattr(self, 'tangents'):
            g.tangents = self.tangents
            g.normals = self.normals
            g.binormals = self.binormals
        return g

    def dispose(self):
        pass


BufferGeometry = Geometry


def _face_cross(pA, pB, pC):
    """cb = pC - pB; ab = pA - pB; cb.cross(ab) (vectorised, same op order)."""
    cbx = pC[:, 0] - pB[:, 0]
    cby = pC[:, 1] - pB[:, 1]
    cbz = pC[:, 2] - pB[:, 2]
    abx = pA[:, 0] - pB[:, 0]
    aby = pA[:, 1] - pB[:, 1]
    abz = pA[:, 2] - pB[:, 2]
    return np.stack([cby * abz - cbz * aby, cbz * abx - cbx * abz, cbx * aby - cby * abx], axis=1)


def _convert_attr(attribute, indices):
    arr = attribute.view(np.ndarray)[indices]
    a = BufferAttribute(arr, attribute.itemSize, getattr(attribute, 'normalized', False),
                        dtype='int' if attribute.dtype.kind in 'iub' else 'float')
    return a


def _n(x):
    """Integer-valued float -> int (JS numbers are all doubles: 24.0 segments must loop like 24)."""
    if isinstance(x, float) and x.is_integer():
        return int(x)
    return x


def _v2(p):
    return p if hasattr(p, 'x') else Vector2(p[0], p[1])


def _v3(p):
    return p if hasattr(p, 'z') else Vector3(p[0], p[1], p[2])


def _opt(options, key, default):
    v = options.get(key) if options is not None else None
    return default if v is None else v


# ============================================================================================ primitives

class BoxGeometry(Geometry):
    def __init__(self, width=1, height=1, depth=1, widthSegments=1, heightSegments=1, depthSegments=1):
        Geometry.__init__(self)
        self.type = 'BoxGeometry'
        self.parameters = JSObj(width=width, height=height, depth=depth, widthSegments=widthSegments,
                                heightSegments=heightSegments, depthSegments=depthSegments)
        widthSegments = math.floor(widthSegments)
        heightSegments = math.floor(heightSegments)
        depthSegments = math.floor(depthSegments)
        indices, vertices, normals, uvs = [], [], [], []
        st = {'numberOfVertices': 0, 'groupStart': 0}
        AX = {'x': 0, 'y': 1, 'z': 2}

        def buildPlane(u, v, w, udir, vdir, width, height, depth, gridX, gridY, materialIndex):
            segmentWidth = width / gridX
            segmentHeight = height / gridY
            widthHalf = width / 2
            heightHalf = height / 2
            depthHalf = depth / 2
            gridX1 = gridX + 1
            gridY1 = gridY + 1
            vertexCounter = 0
            groupCount = 0
            vector = [0, 0, 0]
            ui, vi, wi = AX[u], AX[v], AX[w]
            for iy in range(gridY1):
                y = iy * segmentHeight - heightHalf
                for ix in range(gridX1):
                    x = ix * segmentWidth - widthHalf
                    vector[ui] = x * udir
                    vector[vi] = y * vdir
                    vector[wi] = depthHalf
                    vertices.extend(vector)
                    vector[ui] = 0
                    vector[vi] = 0
                    vector[wi] = 1 if depth > 0 else -1
                    normals.extend(vector)
                    uvs.append(ix / gridX)
                    uvs.append(1 - (iy / gridY))
                    vertexCounter += 1
            nv = st['numberOfVertices']
            for iy in range(gridY):
                for ix in range(gridX):
                    a = nv + ix + gridX1 * iy
                    b = nv + ix + gridX1 * (iy + 1)
                    c = nv + (ix + 1) + gridX1 * (iy + 1)
                    d = nv + (ix + 1) + gridX1 * iy
                    indices.extend((a, b, d, b, c, d))
                    groupCount += 6
            self.addGroup(st['groupStart'], groupCount, materialIndex)
            st['groupStart'] += groupCount
            st['numberOfVertices'] += vertexCounter

        buildPlane('z', 'y', 'x', -1, -1, depth, height, width, depthSegments, heightSegments, 0)  # px
        buildPlane('z', 'y', 'x', 1, -1, depth, height, -width, depthSegments, heightSegments, 1)  # nx
        buildPlane('x', 'z', 'y', 1, 1, width, depth, height, widthSegments, depthSegments, 2)  # py
        buildPlane('x', 'z', 'y', 1, -1, width, depth, -height, widthSegments, depthSegments, 3)  # ny
        buildPlane('x', 'y', 'z', 1, -1, width, height, depth, widthSegments, heightSegments, 4)  # pz
        buildPlane('x', 'y', 'z', -1, -1, width, height, -depth, widthSegments, heightSegments, 5)  # nz
        self.setIndex(indices)
        self.setAttribute('position', Float32BufferAttribute(vertices, 3))
        self.setAttribute('normal', Float32BufferAttribute(normals, 3))
        self.setAttribute('uv', Float32BufferAttribute(uvs, 2))


class PlaneGeometry(Geometry):
    def __init__(self, width=1, height=1, widthSegments=1, heightSegments=1):
        Geometry.__init__(self)
        self.type = 'PlaneGeometry'
        self.parameters = JSObj(width=width, height=height, widthSegments=widthSegments,
                                heightSegments=heightSegments)
        width_half = width / 2
        height_half = height / 2
        gridX = math.floor(widthSegments)
        gridY = math.floor(heightSegments)
        gridX1 = gridX + 1
        gridY1 = gridY + 1
        segment_width = width / gridX
        segment_height = height / gridY
        indices, vertices, normals, uvs = [], [], [], []
        for iy in range(gridY1):
            y = iy * segment_height - height_half
            for ix in range(gridX1):
                x = ix * segment_width - width_half
                vertices.extend((x, -y, 0))
                normals.extend((0, 0, 1))
                uvs.append(ix / gridX)
                uvs.append(1 - (iy / gridY))
        for iy in range(gridY):
            for ix in range(gridX):
                a = ix + gridX1 * iy
                b = ix + gridX1 * (iy + 1)
                c = (ix + 1) + gridX1 * (iy + 1)
                d = (ix + 1) + gridX1 * iy
                indices.extend((a, b, d, b, c, d))
        self.setIndex(indices)
        self.setAttribute('position', Float32BufferAttribute(vertices, 3))
        self.setAttribute('normal', Float32BufferAttribute(normals, 3))
        self.setAttribute('uv', Float32BufferAttribute(uvs, 2))


def _jsrange_le(n):
    """for (let s = 0; s <= n; s++) with a possibly fractional n."""
    return range(int(math.floor(n)) + 1) if n >= 0 else range(0)


def _jsrange_lt(n):
    """for (let s = 0; s < n; s++) with a possibly fractional n."""
    return range(int(math.ceil(n))) if n > 0 else range(0)


class CircleGeometry(Geometry):
    def __init__(self, radius=1, segments=32, thetaStart=0, thetaLength=math.pi * 2):
        Geometry.__init__(self)
        self.type = 'CircleGeometry'
        self.parameters = JSObj(radius=radius, segments=segments, thetaStart=thetaStart, thetaLength=thetaLength)
        segments = max(3, segments)
        indices, vertices, normals, uvs = [0, 0, 0][:0], [0, 0, 0], [0, 0, 1], [0.5, 0.5]
        for s in _jsrange_le(segments):
            segment = thetaStart + s / segments * thetaLength
            vx = radius * math.cos(segment)
            vy = radius * math.sin(segment)
            vertices.extend((vx, vy, 0))
            normals.extend((0, 0, 1))
            uvs.append((vx / radius + 1) / 2)
            uvs.append((vy / radius + 1) / 2)
        i = 1
        while i <= segments:
            indices.extend((i, i + 1, 0))
            i += 1
        self.setIndex(indices)
        self.setAttribute('position', Float32BufferAttribute(vertices, 3))
        self.setAttribute('normal', Float32BufferAttribute(normals, 3))
        self.setAttribute('uv', Float32BufferAttribute(uvs, 2))


class RingGeometry(Geometry):
    def __init__(self, innerRadius=0.5, outerRadius=1, thetaSegments=32, phiSegments=1, thetaStart=0,
                 thetaLength=math.pi * 2):
        Geometry.__init__(self)
        self.type = 'RingGeometry'
        self.parameters = JSObj(innerRadius=innerRadius, outerRadius=outerRadius, thetaSegments=thetaSegments,
                                phiSegments=phiSegments, thetaStart=thetaStart, thetaLength=thetaLength)
        thetaSegments = max(3, thetaSegments)
        phiSegments = max(1, phiSegments)
        indices, vertices, normals, uvs = [], [], [], []
        radius = innerRadius
        radiusStep = ((outerRadius - innerRadius) / phiSegments)
        for j in _jsrange_le(phiSegments):
            for i in _jsrange_le(thetaSegments):
                segment = thetaStart + i / thetaSegments * thetaLength
                vx = radius * math.cos(segment)
                vy = radius * math.sin(segment)
                vertices.extend((vx, vy, 0))
                normals.extend((0, 0, 1))
                uvs.append((vx / outerRadius + 1) / 2)
                uvs.append((vy / outerRadius + 1) / 2)
            radius += radiusStep
        for j in _jsrange_lt(phiSegments):
            thetaSegmentLevel = j * (thetaSegments + 1)
            for i in _jsrange_lt(thetaSegments):
                segment = i + thetaSegmentLevel
                a = segment
                b = segment + thetaSegments + 1
                c = segment + thetaSegments + 2
                d = segment + 1
                indices.extend((a, b, d, b, c, d))
        self.setIndex(indices)
        self.setAttribute('position', Float32BufferAttribute(vertices, 3))
        self.setAttribute('normal', Float32BufferAttribute(normals, 3))
        self.setAttribute('uv', Float32BufferAttribute(uvs, 2))


class CylinderGeometry(Geometry):
    def __init__(self, radiusTop=1, radiusBottom=1, height=1, radialSegments=32, heightSegments=1, openEnded=False,
                 thetaStart=0, thetaLength=math.pi * 2):
        Geometry.__init__(self)
        self.type = 'CylinderGeometry'
        self.parameters = JSObj(radiusTop=radiusTop, radiusBottom=radiusBottom, height=height,
                                radialSegments=radialSegments, heightSegments=heightSegments, openEnded=openEnded,
                                thetaStart=thetaStart, thetaLength=thetaLength)
        radialSegments = math.floor(radialSegments)
        heightSegments = math.floor(heightSegments)
        indices, vertices, normals, uvs = [], [], [], []
        st = {'index': 0, 'groupStart': 0}
        indexArray = []
        halfHeight = height / 2

        def generateTorso():
            groupCount = 0
            slope = (radiusBottom - radiusTop) / height
            for y in range(heightSegments + 1):
                indexRow = []
                v = y / heightSegments
                radius = v * (radiusBottom - radiusTop) + radiusTop
                for x in range(radialSegments + 1):
                    u = x / radialSegments
                    theta = u * thetaLength + thetaStart
                    sinTheta = math.sin(theta)
                    cosTheta = math.cos(theta)
                    vertices.extend((radius * sinTheta, -v * height + halfHeight, radius * cosTheta))
                    nv = Vector3(sinTheta, slope, cosTheta).normalize()
                    normals.extend((nv.x, nv.y, nv.z))
                    uvs.extend((u, 1 - v))
                    indexRow.append(st['index'])
                    st['index'] += 1
                indexArray.append(indexRow)
            for x in range(radialSegments):
                for y in range(heightSegments):
                    a = indexArray[y][x]
                    b = indexArray[y + 1][x]
                    c = indexArray[y + 1][x + 1]
                    d = indexArray[y][x + 1]
                    if radiusTop > 0 or y != 0:
                        indices.extend((a, b, d))
                        groupCount += 3
                    if radiusBottom > 0 or y != heightSegments - 1:
                        indices.extend((b, c, d))
                        groupCount += 3
            self.addGroup(st['groupStart'], groupCount, 0)
            st['groupStart'] += groupCount

        def generateCap(top):
            centerIndexStart = st['index']
            groupCount = 0
            radius = radiusTop if top else radiusBottom
            sign = 1 if top else -1
            for x in range(1, radialSegments + 1):
                vertices.extend((0, halfHeight * sign, 0))
                normals.extend((0, sign, 0))
                uvs.extend((0.5, 0.5))
                st['index'] += 1
            centerIndexEnd = st['index']
            for x in range(radialSegments + 1):
                u = x / radialSegments
                theta = u * thetaLength + thetaStart
                cosTheta = math.cos(theta)
                sinTheta = math.sin(theta)
                vertices.extend((radius * sinTheta, halfHeight * sign, radius * cosTheta))
                normals.extend((0, sign, 0))
                uvs.extend(((cosTheta * 0.5) + 0.5, (sinTheta * 0.5 * sign) + 0.5))
                st['index'] += 1
            for x in range(radialSegments):
                c = centerIndexStart + x
                i = centerIndexEnd + x
                if top:
                    indices.extend((i, i + 1, c))
                else:
                    indices.extend((i + 1, i, c))
                groupCount += 3
            self.addGroup(st['groupStart'], groupCount, 1 if top else 2)
            st['groupStart'] += groupCount

        generateTorso()
        if openEnded is False:
            if radiusTop > 0:
                generateCap(True)
            if radiusBottom > 0:
                generateCap(False)
        self.setIndex(indices)
        self.setAttribute('position', Float32BufferAttribute(vertices, 3))
        self.setAttribute('normal', Float32BufferAttribute(normals, 3))
        self.setAttribute('uv', Float32BufferAttribute(uvs, 2))


class ConeGeometry(CylinderGeometry):
    def __init__(self, radius=1, height=1, radialSegments=32, heightSegments=1, openEnded=False, thetaStart=0,
                 thetaLength=math.pi * 2):
        CylinderGeometry.__init__(self, 0, radius, height, radialSegments, heightSegments, openEnded, thetaStart,
                                  thetaLength)
        self.type = 'ConeGeometry'
        self.parameters = JSObj(radius=radius, height=height, radialSegments=radialSegments,
                                heightSegments=heightSegments, openEnded=openEnded, thetaStart=thetaStart,
                                thetaLength=thetaLength)


class SphereGeometry(Geometry):
    def __init__(self, radius=1, widthSegments=32, heightSegments=16, phiStart=0, phiLength=math.pi * 2,
                 thetaStart=0, thetaLength=math.pi):
        Geometry.__init__(self)
        self.type = 'SphereGeometry'
        self.parameters = JSObj(radius=radius, widthSegments=widthSegments, heightSegments=heightSegments,
                                phiStart=phiStart, phiLength=phiLength, thetaStart=thetaStart,
                                thetaLength=thetaLength)
        widthSegments = max(3, math.floor(widthSegments))
        heightSegments = max(2, math.floor(heightSegments))
        thetaEnd = min(thetaStart + thetaLength, math.pi)
        index = 0
        grid = []
        indices, vertices, normals, uvs = [], [], [], []
        for iy in range(heightSegments + 1):
            verticesRow = []
            v = iy / heightSegments
            theta = thetaStart + v * thetaLength
            y = radius * math.cos(theta)
            ringRadius = math.sqrt(radius * radius - y * y) if radius * radius - y * y >= 0 else _NAN
            uOffset = 0
            if iy == 0 and thetaStart == 0:
                uOffset = 0.5 / widthSegments
            elif iy == heightSegments and thetaEnd == math.pi:
                uOffset = -0.5 / widthSegments
            for ix in range(widthSegments + 1):
                u = ix / widthSegments
                phi = phiStart + u * phiLength
                vx = -ringRadius * math.cos(phi)
                vy = y
                vz = ringRadius * math.sin(phi)
                vertices.extend((vx, vy, vz))
                nv = Vector3(vx, vy, vz).normalize()
                normals.extend((nv.x, nv.y, nv.z))
                uvs.extend((u + uOffset, 1 - v))
                verticesRow.append(index)
                index += 1
            grid.append(verticesRow)
        for iy in range(heightSegments):
            for ix in range(widthSegments):
                a = grid[iy][ix + 1]
                b = grid[iy][ix]
                c = grid[iy + 1][ix]
                d = grid[iy + 1][ix + 1]
                if iy != 0 or thetaStart > 0:
                    indices.extend((a, b, d))
                if iy != heightSegments - 1 or thetaEnd < math.pi:
                    indices.extend((b, c, d))
        self.setIndex(indices)
        self.setAttribute('position', Float32BufferAttribute(vertices, 3))
        self.setAttribute('normal', Float32BufferAttribute(normals, 3))
        self.setAttribute('uv', Float32BufferAttribute(uvs, 2))


class TorusGeometry(Geometry):
    def __init__(self, radius=1, tube=0.4, radialSegments=12, tubularSegments=48, arc=math.pi * 2, thetaStart=0,
                 thetaLength=math.pi * 2):
        Geometry.__init__(self)
        self.type = 'TorusGeometry'
        self.parameters = JSObj(radius=radius, tube=tube, radialSegments=radialSegments,
                                tubularSegments=tubularSegments, arc=arc, thetaStart=thetaStart,
                                thetaLength=thetaLength)
        radialSegments = math.floor(radialSegments)
        tubularSegments = math.floor(tubularSegments)
        indices, vertices, normals, uvs = [], [], [], []
        for j in range(radialSegments + 1):
            v = thetaStart + (j / radialSegments) * thetaLength
            for i in range(tubularSegments + 1):
                u = i / tubularSegments * arc
                vx = (radius + tube * math.cos(v)) * math.cos(u)
                vy = (radius + tube * math.cos(v)) * math.sin(u)
                vz = tube * math.sin(v)
                vertices.extend((vx, vy, vz))
                cx = radius * math.cos(u)
                cy = radius * math.sin(u)
                nv = Vector3(vx - cx, vy - cy, vz - 0).normalize()
                normals.extend((nv.x, nv.y, nv.z))
                uvs.append(i / tubularSegments)
                uvs.append(j / radialSegments)
        for j in range(1, radialSegments + 1):
            for i in range(1, tubularSegments + 1):
                a = (tubularSegments + 1) * j + i - 1
                b = (tubularSegments + 1) * (j - 1) + i - 1
                c = (tubularSegments + 1) * (j - 1) + i
                d = (tubularSegments + 1) * j + i
                indices.extend((a, b, d, b, c, d))
        self.setIndex(indices)
        self.setAttribute('position', Float32BufferAttribute(vertices, 3))
        self.setAttribute('normal', Float32BufferAttribute(normals, 3))
        self.setAttribute('uv', Float32BufferAttribute(uvs, 2))


class LatheGeometry(Geometry):
    """points: list of Vector2 or (x, y) pairs (radius, height), bottom to top."""

    def __init__(self, points=None, segments=12, phiStart=0, phiLength=math.pi * 2):
        Geometry.__init__(self)
        if points is None:
            points = [Vector2(0, -0.5), Vector2(0.5, 0), Vector2(0, 0.5)]
        points = [_v2(p) for p in points]
        self.type = 'LatheGeometry'
        self.parameters = JSObj(points=points, segments=segments, phiStart=phiStart, phiLength=phiLength)
        segments = math.floor(segments)
        phiLength = clamp(phiLength, 0, math.pi * 2)
        indices, vertices, uvs, initNormals, normals = [], [], [], [], []
        inverseSegments = 1.0 / segments
        normal = Vector3()
        curNormal = Vector3()
        prevNormal = Vector3()
        L = len(points)
        for j in range(L):
            if j == 0:
                dx = points[j + 1].x - points[j].x
                dy = points[j + 1].y - points[j].y
                normal.x = dy * 1.0
                normal.y = -dx
                normal.z = dy * 0.0
                prevNormal.copy(normal)
                normal.normalize()
                initNormals.extend((normal.x, normal.y, normal.z))
            elif j == L - 1:
                initNormals.extend((prevNormal.x, prevNormal.y, prevNormal.z))
            else:
                dx = points[j + 1].x - points[j].x
                dy = points[j + 1].y - points[j].y
                normal.x = dy * 1.0
                normal.y = -dx
                normal.z = dy * 0.0
                curNormal.copy(normal)
                normal.x += prevNormal.x
                normal.y += prevNormal.y
                normal.z += prevNormal.z
                normal.normalize()
                initNormals.extend((normal.x, normal.y, normal.z))
                prevNormal.copy(curNormal)
        for i in range(segments + 1):
            phi = phiStart + i * inverseSegments * phiLength
            sin = math.sin(phi)
            cos = math.cos(phi)
            for j in range(L):
                vertices.extend((points[j].x * sin, points[j].y, points[j].x * cos))
                uvs.extend((i / segments, j / (L - 1)))
                x = initNormals[3 * j + 0] * sin
                y = initNormals[3 * j + 1]
                z = initNormals[3 * j + 0] * cos
                normals.extend((x, y, z))
        for i in range(segments):
            for j in range(L - 1):
                base = j + i * L
                a = base
                b = base + L
                c = base + L + 1
                d = base + 1
                indices.extend((a, b, d, c, d, b))
        self.setIndex(indices)
        self.setAttribute('position', Float32BufferAttribute(vertices, 3))
        self.setAttribute('uv', Float32BufferAttribute(uvs, 2))
        self.setAttribute('normal', Float32BufferAttribute(normals, 3))


class CapsuleGeometry(Geometry):
    """three r186 CapsuleGeometry (arc-length v, heightSegments)."""

    def __init__(self, radius=1, height=1, capSegments=4, radialSegments=8, heightSegments=1):
        Geometry.__init__(self)
        self.type = 'CapsuleGeometry'
        self.parameters = JSObj(radius=radius, height=height, capSegments=capSegments,
                                radialSegments=radialSegments, heightSegments=heightSegments)
        height = max(0, height)
        capSegments = max(1, math.floor(capSegments))
        radialSegments = max(3, math.floor(radialSegments))
        heightSegments = max(1, math.floor(heightSegments))
        indices, vertices, normals, uvs = [], [], [], []
        halfHeight = height / 2
        capArcLength = (math.pi / 2) * radius
        cylinderPartLength = height
        totalArcLength = 2 * capArcLength + cylinderPartLength
        numVerticalSegments = capSegments * 2 + heightSegments
        verticesPerRow = radialSegments + 1
        for iy in range(numVerticalSegments + 1):
            if iy <= capSegments:
                segmentProgress = iy / capSegments
                angle = (segmentProgress * math.pi) / 2
                profileY = -halfHeight - radius * math.cos(angle)
                profileRadius = radius * math.sin(angle)
                normalYComponent = -radius * math.cos(angle)
                currentArcLength = segmentProgress * capArcLength
            elif iy <= capSegments + heightSegments:
                segmentProgress = (iy - capSegments) / heightSegments
                profileY = -halfHeight + segmentProgress * height
                profileRadius = radius
                normalYComponent = 0
                currentArcLength = capArcLength + segmentProgress * cylinderPartLength
            else:
                segmentProgress = (iy - capSegments - heightSegments) / capSegments
                angle = (segmentProgress * math.pi) / 2
                profileY = halfHeight + radius * math.sin(angle)
                profileRadius = radius * math.cos(angle)
                normalYComponent = radius * math.sin(angle)
                currentArcLength = capArcLength + cylinderPartLength + segmentProgress * capArcLength
            v = max(0, min(1, currentArcLength / totalArcLength))
            uOffset = 0
            if iy == 0:
                uOffset = 0.5 / radialSegments
            elif iy == numVerticalSegments:
                uOffset = -0.5 / radialSegments
            for ix in range(radialSegments + 1):
                u = ix / radialSegments
                theta = u * math.pi * 2
                sinTheta = math.sin(theta)
                cosTheta = math.cos(theta)
                vertices.extend((-profileRadius * cosTheta, profileY, profileRadius * sinTheta))
                nv = Vector3(-profileRadius * cosTheta, normalYComponent, profileRadius * sinTheta).normalize()
                normals.extend((nv.x, nv.y, nv.z))
                uvs.extend((u + uOffset, v))
            if iy > 0:
                prevIndexRow = (iy - 1) * verticesPerRow
                for ix in range(radialSegments):
                    i1 = prevIndexRow + ix
                    i2 = prevIndexRow + ix + 1
                    i3 = iy * verticesPerRow + ix
                    i4 = iy * verticesPerRow + ix + 1
                    indices.extend((i1, i2, i3, i2, i4, i3))
        self.setIndex(indices)
        self.setAttribute('position', Float32BufferAttribute(vertices, 3))
        self.setAttribute('normal', Float32BufferAttribute(normals, 3))
        self.setAttribute('uv', Float32BufferAttribute(uvs, 2))


class PolyhedronGeometry(Geometry):
    def __init__(self, vertices=(), indices=(), radius=1, detail=0):
        Geometry.__init__(self)
        self.type = 'PolyhedronGeometry'
        self.parameters = JSObj(vertices=list(vertices), indices=list(indices), radius=radius, detail=detail)
        vertexBuffer = []
        uvBuffer = []
        detail = _n(detail)

        def getVertexByIndex(index, vertex):
            stride = index * 3
            vertex.x = vertices[stride + 0]
            vertex.y = vertices[stride + 1]
            vertex.z = vertices[stride + 2]

        def pushVertex(vertex):
            vertexBuffer.extend((vertex.x, vertex.y, vertex.z))

        def subdivideFace(a, b, c, detail):
            cols = detail + 1
            v = []
            for i in range(cols + 1):
                v.append([])
                aj = a.clone().lerp(c, i / cols)
                bj = b.clone().lerp(c, i / cols)
                rows = cols - i
                for j in range(rows + 1):
                    if j == 0 and i == cols:
                        v[i].append(aj)
                    else:
                        v[i].append(aj.clone().lerp(bj, j / rows))
            for i in range(cols):
                for j in range(2 * (cols - i) - 1):
                    k = math.floor(j / 2)
                    if j % 2 == 0:
                        pushVertex(v[i][k + 1])
                        pushVertex(v[i + 1][k])
                        pushVertex(v[i][k])
                    else:
                        pushVertex(v[i][k + 1])
                        pushVertex(v[i + 1][k + 1])
                        pushVertex(v[i + 1][k])

        def subdivide(detail):
            a, b, c = Vector3(), Vector3(), Vector3()
            for i in range(0, len(indices), 3):
                getVertexByIndex(indices[i + 0], a)
                getVertexByIndex(indices[i + 1], b)
                getVertexByIndex(indices[i + 2], c)
                subdivideFace(a, b, c, detail)

        def applyRadius(radius):
            vertex = Vector3()
            for i in range(0, len(vertexBuffer), 3):
                vertex.x = vertexBuffer[i + 0]
                vertex.y = vertexBuffer[i + 1]
                vertex.z = vertexBuffer[i + 2]
                vertex.normalize().multiplyScalar(radius)
                vertexBuffer[i + 0] = vertex.x
                vertexBuffer[i + 1] = vertex.y
                vertexBuffer[i + 2] = vertex.z

        def azimuth(vector):
            return math.atan2(vector.z, -vector.x)

        def inclination(vector):
            return math.atan2(-vector.y, math.sqrt((vector.x * vector.x) + (vector.z * vector.z)))

        def correctUV(uv, stride, vector, azi):
            if azi < 0 and uv.x == 1:
                uvBuffer[stride] = uv.x - 1
            if vector.x == 0 and vector.z == 0:
                uvBuffer[stride] = azi / 2 / math.pi + 0.5

        def correctUVs():
            a, b, c, centroid = Vector3(), Vector3(), Vector3(), Vector3()
            uvA, uvB, uvC = Vector2(), Vector2(), Vector2()
            i = 0
            j = 0
            while i < len(vertexBuffer):
                a.set(vertexBuffer[i + 0], vertexBuffer[i + 1], vertexBuffer[i + 2])
                b.set(vertexBuffer[i + 3], vertexBuffer[i + 4], vertexBuffer[i + 5])
                c.set(vertexBuffer[i + 6], vertexBuffer[i + 7], vertexBuffer[i + 8])
                uvA.set(uvBuffer[j + 0], uvBuffer[j + 1])
                uvB.set(uvBuffer[j + 2], uvBuffer[j + 3])
                uvC.set(uvBuffer[j + 4], uvBuffer[j + 5])
                centroid.copy(a).add(b).add(c).divideScalar(3)
                azi = azimuth(centroid)
                correctUV(uvA, j + 0, a, azi)
                correctUV(uvB, j + 2, b, azi)
                correctUV(uvC, j + 4, c, azi)
                i += 9
                j += 6

        def correctSeam():
            for i in range(0, len(uvBuffer), 6):
                x0 = uvBuffer[i + 0]
                x1 = uvBuffer[i + 2]
                x2 = uvBuffer[i + 4]
                mx = max(x0, x1, x2)
                mn = min(x0, x1, x2)
                if mx > 0.9 and mn < 0.1:
                    if x0 < 0.2:
                        uvBuffer[i + 0] += 1
                    if x1 < 0.2:
                        uvBuffer[i + 2] += 1
                    if x2 < 0.2:
                        uvBuffer[i + 4] += 1

        def generateUVs():
            vertex = Vector3()
            for i in range(0, len(vertexBuffer), 3):
                vertex.x = vertexBuffer[i + 0]
                vertex.y = vertexBuffer[i + 1]
                vertex.z = vertexBuffer[i + 2]
                u = azimuth(vertex) / 2 / math.pi + 0.5
                v = inclination(vertex) / math.pi + 0.5
                uvBuffer.extend((u, 1 - v))
            correctUVs()
            correctSeam()

        subdivide(detail)
        applyRadius(radius)
        generateUVs()
        self.setAttribute('position', Float32BufferAttribute(vertexBuffer, 3))
        self.setAttribute('normal', Float32BufferAttribute(list(vertexBuffer), 3))
        self.setAttribute('uv', Float32BufferAttribute(uvBuffer, 2))
        if detail == 0:
            self.computeVertexNormals()
        else:
            self.normalizeNormals()


class IcosahedronGeometry(PolyhedronGeometry):
    def __init__(self, radius=1, detail=0):
        t = (1 + math.sqrt(5)) / 2
        vertices = [-1, t, 0, 1, t, 0, -1, -t, 0, 1, -t, 0,
                    0, -1, t, 0, 1, t, 0, -1, -t, 0, 1, -t,
                    t, 0, -1, t, 0, 1, -t, 0, -1, -t, 0, 1]
        indices = [0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11,
                   1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8,
                   3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9,
                   4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1]
        PolyhedronGeometry.__init__(self, vertices, indices, radius, detail)
        self.type = 'IcosahedronGeometry'
        self.parameters = JSObj(radius=radius, detail=detail)


class OctahedronGeometry(PolyhedronGeometry):
    def __init__(self, radius=1, detail=0):
        vertices = [1, 0, 0, -1, 0, 0, 0, 1, 0, 0, -1, 0, 0, 0, 1, 0, 0, -1]
        indices = [0, 2, 4, 0, 4, 3, 0, 3, 5, 0, 5, 2, 1, 2, 5, 1, 5, 3, 1, 3, 4, 1, 4, 2]
        PolyhedronGeometry.__init__(self, vertices, indices, radius, detail)
        self.type = 'OctahedronGeometry'
        self.parameters = JSObj(radius=radius, detail=detail)


class TetrahedronGeometry(PolyhedronGeometry):
    def __init__(self, radius=1, detail=0):
        vertices = [1, 1, 1, -1, -1, 1, -1, 1, -1, 1, -1, -1]
        indices = [2, 1, 0, 0, 3, 2, 1, 3, 0, 2, 3, 1]
        PolyhedronGeometry.__init__(self, vertices, indices, radius, detail)
        self.type = 'TetrahedronGeometry'
        self.parameters = JSObj(radius=radius, detail=detail)


class DodecahedronGeometry(PolyhedronGeometry):
    def __init__(self, radius=1, detail=0):
        t = (1 + math.sqrt(5)) / 2
        r = 1 / t
        vertices = [
            -1, -1, -1, -1, -1, 1, -1, 1, -1, -1, 1, 1, 1, -1, -1, 1, -1, 1, 1, 1, -1, 1, 1, 1,
            0, -r, -t, 0, -r, t, 0, r, -t, 0, r, t,
            -r, -t, 0, -r, t, 0, r, -t, 0, r, t, 0,
            -t, 0, -r, t, 0, -r, -t, 0, r, t, 0, r]
        indices = [
            3, 11, 7, 3, 7, 15, 3, 15, 13, 7, 19, 17, 7, 17, 6, 7, 6, 15, 17, 4, 8, 17, 8, 10, 17, 10, 6,
            8, 0, 16, 8, 16, 2, 8, 2, 10, 0, 12, 1, 0, 1, 18, 0, 18, 16, 6, 10, 2, 6, 2, 13, 6, 13, 15,
            2, 16, 18, 2, 18, 3, 2, 3, 13, 18, 1, 9, 18, 9, 11, 18, 11, 3, 4, 14, 12, 4, 12, 0, 4, 0, 8,
            11, 9, 5, 11, 5, 19, 11, 19, 7, 19, 5, 14, 19, 14, 4, 19, 4, 17, 1, 12, 14, 1, 14, 5, 1, 5, 9]
        PolyhedronGeometry.__init__(self, vertices, indices, radius, detail)
        self.type = 'DodecahedronGeometry'
        self.parameters = JSObj(radius=radius, detail=detail)


# ============================================================================================ curves

def CatmullRom(t, p0, p1, p2, p3):
    v0 = (p2 - p0) * 0.5
    v1 = (p3 - p1) * 0.5
    t2 = t * t
    t3 = t * t2
    return (2 * p1 - 2 * p2 + v0 + v1) * t3 + (-3 * p1 + 3 * p2 - 2 * v0 - v1) * t2 + v0 * t + p1


def QuadraticBezier(t, p0, p1, p2):
    k = 1 - t
    return k * k * p0 + 2 * (1 - t) * t * p1 + t * t * p2


def CubicBezier(t, p0, p1, p2, p3):
    k = 1 - t
    return k * k * k * p0 + 3 * k * k * t * p1 + 3 * (1 - t) * t * t * p2 + t * t * t * p3


class Curve:
    isCurve = True
    isVector2Curve = False

    def __init__(self):
        self.type = 'Curve'
        self.arcLengthDivisions = 200
        self.needsUpdate = False
        self.cacheArcLengths = None

    def getPoint(self, t, optionalTarget=None):
        _warn('Curve: .getPoint() not implemented.')
        return None

    def getPointAt(self, u, optionalTarget=None):
        t = self.getUtoTmapping(u)
        return self.getPoint(t, optionalTarget)

    def getPoints(self, divisions=5):
        return [self.getPoint(d / divisions) for d in _jsrange_le(divisions)]

    def getSpacedPoints(self, divisions=5):
        return [self.getPointAt(d / divisions) for d in _jsrange_le(divisions)]

    def getLength(self):
        lengths = self.getLengths()
        return lengths[len(lengths) - 1]

    def getLengths(self, divisions=None):
        if divisions is None:
            divisions = self.arcLengthDivisions
        if (self.cacheArcLengths is not None and len(self.cacheArcLengths) == divisions + 1 and
                not self.needsUpdate):
            return self.cacheArcLengths
        self.needsUpdate = False
        cache = [0]
        last = self.getPoint(0)
        s = 0
        for p in range(1, int(divisions) + 1):
            current = self.getPoint(p / divisions)
            s += current.distanceTo(last)
            cache.append(s)
            last = current
        self.cacheArcLengths = cache
        return cache

    def updateArcLengths(self):
        self.needsUpdate = True
        self.getLengths()

    def getUtoTmapping(self, u, distance=None):
        arcLengths = self.getLengths()
        il = len(arcLengths)
        if distance:
            targetArcLength = distance
        else:
            targetArcLength = u * arcLengths[il - 1]
        low = 0
        high = il - 1
        i = 0
        while low <= high:
            i = math.floor(low + (high - low) / 2)
            comparison = arcLengths[i] - targetArcLength
            if comparison < 0:
                low = i + 1
            elif comparison > 0:
                high = i - 1
            else:
                high = i
                break
        i = high
        lengthBefore = arcLengths[i] if 0 <= i < il else _NAN
        if lengthBefore == targetArcLength:
            return i / (il - 1)
        lengthAfter = arcLengths[i + 1] if 0 <= i + 1 < il else _NAN
        segmentLength = lengthAfter - lengthBefore
        segmentFraction = (targetArcLength - lengthBefore) / segmentLength if segmentLength != 0 else (
            _NAN if targetArcLength - lengthBefore == 0 else math.copysign(_INF, targetArcLength - lengthBefore))
        return (i + segmentFraction) / (il - 1)

    def getTangent(self, t, optionalTarget=None):
        delta = 0.0001
        t1 = t - delta
        t2 = t + delta
        if t1 < 0:
            t1 = 0
        if t2 > 1:
            t2 = 1
        pt1 = self.getPoint(t1)
        pt2 = self.getPoint(t2)
        tangent = optionalTarget or (Vector2() if getattr(pt1, 'isVector2', False) else Vector3())
        tangent.copy(pt2).sub(pt1).normalize()
        return tangent

    def getTangentAt(self, u, optionalTarget=None):
        t = self.getUtoTmapping(u)
        return self.getTangent(t, optionalTarget)

    def computeFrenetFrames(self, segments, closed=False):
        segments = _n(segments)
        normal = Vector3()
        tangents, normals, binormals = [], [], []
        vec = Vector3()
        mat = Matrix4()
        for i in range(segments + 1):
            u = i / segments
            tangents.append(self.getTangentAt(u, Vector3()))
        normals.append(Vector3())
        binormals.append(Vector3())
        mn = MAX_VALUE
        tx = abs(tangents[0].x)
        ty = abs(tangents[0].y)
        tz = abs(tangents[0].z)
        if tx <= mn:
            mn = tx
            normal.set(1, 0, 0)
        if ty <= mn:
            mn = ty
            normal.set(0, 1, 0)
        if tz <= mn:
            normal.set(0, 0, 1)
        vec.crossVectors(tangents[0], normal).normalize()
        normals[0].crossVectors(tangents[0], vec)
        binormals[0].crossVectors(tangents[0], normals[0])
        for i in range(1, segments + 1):
            normals.append(normals[i - 1].clone())
            binormals.append(binormals[i - 1].clone())
            vec.crossVectors(tangents[i - 1], tangents[i])
            if vec.length() > EPSILON:
                vec.normalize()
                theta = math.acos(clamp(tangents[i - 1].dot(tangents[i]), -1, 1))
                normals[i].applyMatrix4(mat.makeRotationAxis(vec, theta))
            binormals[i].crossVectors(tangents[i], normals[i])
        if closed is True:
            theta = math.acos(clamp(normals[0].dot(normals[segments]), -1, 1))
            theta /= segments
            if tangents[0].dot(vec.crossVectors(normals[0], normals[segments])) > 0:
                theta = -theta
            for i in range(1, segments + 1):
                normals[i].applyMatrix4(mat.makeRotationAxis(tangents[i], theta * i))
                binormals[i].crossVectors(tangents[i], normals[i])
        return JSObj(tangents=tangents, normals=normals, binormals=binormals)

    def clone(self):
        c = self.__class__.__new__(self.__class__)
        Curve.__init__(c)
        c.__dict__.update({k: v for k, v in self.__dict__.items()})
        c.cacheArcLengths = None
        for k, v in list(c.__dict__.items()):
            if isinstance(v, (Vector2, Vector3)):
                c.__dict__[k] = v.clone()
            elif k == 'points':
                c.__dict__[k] = [p.clone() for p in v]
            elif k == 'curves':
                c.__dict__[k] = [cv.clone() for cv in v]
            elif k == 'holes':
                c.__dict__[k] = [h.clone() for h in v]
        if hasattr(c, 'cacheLengths'):
            c.cacheLengths = None
        if hasattr(c, 'uuid'):
            c.uuid = generateUUID()
        return c

    def copy(self, source):
        self.arcLengthDivisions = source.arcLengthDivisions
        return self


class EllipseCurve(Curve):
    isEllipseCurve = True

    def __init__(self, aX=0, aY=0, xRadius=1, yRadius=1, aStartAngle=0, aEndAngle=math.pi * 2, aClockwise=False,
                 aRotation=0):
        Curve.__init__(self)
        self.type = 'EllipseCurve'
        self.aX = 0 if aX is None else aX
        self.aY = 0 if aY is None else aY
        self.xRadius = 1 if xRadius is None else xRadius
        self.yRadius = 1 if yRadius is None else yRadius
        self.aStartAngle = 0 if aStartAngle is None else aStartAngle
        self.aEndAngle = math.pi * 2 if aEndAngle is None else aEndAngle
        self.aClockwise = False if aClockwise is None else aClockwise
        self.aRotation = 0 if aRotation is None else aRotation

    def getPoint(self, t, optionalTarget=None):
        point = optionalTarget if optionalTarget is not None else Vector2()
        twoPi = math.pi * 2
        deltaAngle = self.aEndAngle - self.aStartAngle
        samePoints = abs(deltaAngle) < EPSILON
        while deltaAngle < 0:
            deltaAngle += twoPi
        while deltaAngle > twoPi:
            deltaAngle -= twoPi
        if deltaAngle < EPSILON:
            if samePoints:
                deltaAngle = 0
            else:
                deltaAngle = twoPi
        if self.aClockwise is True and not samePoints:
            if deltaAngle == twoPi:
                deltaAngle = -twoPi
            else:
                deltaAngle = deltaAngle - twoPi
        angle = self.aStartAngle + t * deltaAngle
        x = self.aX + self.xRadius * math.cos(angle)
        y = self.aY + self.yRadius * math.sin(angle)
        if self.aRotation != 0:
            cos = math.cos(self.aRotation)
            sin = math.sin(self.aRotation)
            tx = x - self.aX
            ty = y - self.aY
            x = tx * cos - ty * sin + self.aX
            y = tx * sin + ty * cos + self.aY
        return point.set(x, y)


class ArcCurve(EllipseCurve):
    isArcCurve = True

    def __init__(self, aX=0, aY=0, aRadius=1, aStartAngle=0, aEndAngle=math.pi * 2, aClockwise=False):
        EllipseCurve.__init__(self, aX, aY, aRadius, aRadius, aStartAngle, aEndAngle, aClockwise)
        self.type = 'ArcCurve'


class LineCurve(Curve):
    isLineCurve = True

    def __init__(self, v1=None, v2=None):
        Curve.__init__(self)
        self.type = 'LineCurve'
        self.v1 = v1 if v1 is not None else Vector2()
        self.v2 = v2 if v2 is not None else Vector2()

    def getPoint(self, t, optionalTarget=None):
        point = optionalTarget if optionalTarget is not None else Vector2()
        if t == 1:
            point.copy(self.v2)
        else:
            point.copy(self.v2).sub(self.v1)
            point.multiplyScalar(t).add(self.v1)
        return point

    def getPointAt(self, u, optionalTarget=None):
        return self.getPoint(u, optionalTarget)

    def getTangent(self, t, optionalTarget=None):
        return (optionalTarget if optionalTarget is not None else Vector2()).subVectors(self.v2, self.v1).normalize()

    def getTangentAt(self, u, optionalTarget=None):
        return self.getTangent(u, optionalTarget)


class LineCurve3(Curve):
    isLineCurve3 = True

    def __init__(self, v1=None, v2=None):
        Curve.__init__(self)
        self.type = 'LineCurve3'
        self.v1 = v1 if v1 is not None else Vector3()
        self.v2 = v2 if v2 is not None else Vector3()

    def getPoint(self, t, optionalTarget=None):
        point = optionalTarget if optionalTarget is not None else Vector3()
        if t == 1:
            point.copy(self.v2)
        else:
            point.copy(self.v2).sub(self.v1)
            point.multiplyScalar(t).add(self.v1)
        return point

    def getPointAt(self, u, optionalTarget=None):
        return self.getPoint(u, optionalTarget)

    def getTangent(self, t, optionalTarget=None):
        return (optionalTarget if optionalTarget is not None else Vector3()).subVectors(self.v2, self.v1).normalize()

    def getTangentAt(self, u, optionalTarget=None):
        return self.getTangent(u, optionalTarget)


class QuadraticBezierCurve(Curve):
    isQuadraticBezierCurve = True

    def __init__(self, v0=None, v1=None, v2=None):
        Curve.__init__(self)
        self.type = 'QuadraticBezierCurve'
        self.v0 = v0 if v0 is not None else Vector2()
        self.v1 = v1 if v1 is not None else Vector2()
        self.v2 = v2 if v2 is not None else Vector2()

    def getPoint(self, t, optionalTarget=None):
        point = optionalTarget if optionalTarget is not None else Vector2()
        v0, v1, v2 = self.v0, self.v1, self.v2
        return point.set(QuadraticBezier(t, v0.x, v1.x, v2.x), QuadraticBezier(t, v0.y, v1.y, v2.y))


class QuadraticBezierCurve3(Curve):
    isQuadraticBezierCurve3 = True

    def __init__(self, v0=None, v1=None, v2=None):
        Curve.__init__(self)
        self.type = 'QuadraticBezierCurve3'
        self.v0 = v0 if v0 is not None else Vector3()
        self.v1 = v1 if v1 is not None else Vector3()
        self.v2 = v2 if v2 is not None else Vector3()

    def getPoint(self, t, optionalTarget=None):
        point = optionalTarget if optionalTarget is not None else Vector3()
        v0, v1, v2 = self.v0, self.v1, self.v2
        return point.set(QuadraticBezier(t, v0.x, v1.x, v2.x), QuadraticBezier(t, v0.y, v1.y, v2.y),
                         QuadraticBezier(t, v0.z, v1.z, v2.z))


class CubicBezierCurve(Curve):
    isCubicBezierCurve = True

    def __init__(self, v0=None, v1=None, v2=None, v3=None):
        Curve.__init__(self)
        self.type = 'CubicBezierCurve'
        self.v0 = v0 if v0 is not None else Vector2()
        self.v1 = v1 if v1 is not None else Vector2()
        self.v2 = v2 if v2 is not None else Vector2()
        self.v3 = v3 if v3 is not None else Vector2()

    def getPoint(self, t, optionalTarget=None):
        point = optionalTarget if optionalTarget is not None else Vector2()
        v0, v1, v2, v3 = self.v0, self.v1, self.v2, self.v3
        return point.set(CubicBezier(t, v0.x, v1.x, v2.x, v3.x), CubicBezier(t, v0.y, v1.y, v2.y, v3.y))


class CubicBezierCurve3(Curve):
    isCubicBezierCurve3 = True

    def __init__(self, v0=None, v1=None, v2=None, v3=None):
        Curve.__init__(self)
        self.type = 'CubicBezierCurve3'
        self.v0 = v0 if v0 is not None else Vector3()
        self.v1 = v1 if v1 is not None else Vector3()
        self.v2 = v2 if v2 is not None else Vector3()
        self.v3 = v3 if v3 is not None else Vector3()

    def getPoint(self, t, optionalTarget=None):
        point = optionalTarget if optionalTarget is not None else Vector3()
        v0, v1, v2, v3 = self.v0, self.v1, self.v2, self.v3
        return point.set(CubicBezier(t, v0.x, v1.x, v2.x, v3.x), CubicBezier(t, v0.y, v1.y, v2.y, v3.y),
                         CubicBezier(t, v0.z, v1.z, v2.z, v3.z))


class SplineCurve(Curve):
    isSplineCurve = True

    def __init__(self, points=None):
        Curve.__init__(self)
        self.type = 'SplineCurve'
        self.points = [_v2(p) for p in points] if points is not None else []

    def getPoint(self, t, optionalTarget=None):
        point = optionalTarget if optionalTarget is not None else Vector2()
        points = self.points
        p = (len(points) - 1) * t
        intPoint = math.floor(p)
        weight = p - intPoint
        p0 = points[intPoint if intPoint == 0 else intPoint - 1]
        p1 = points[intPoint]
        p2 = points[len(points) - 1 if intPoint > len(points) - 2 else intPoint + 1]
        p3 = points[len(points) - 1 if intPoint > len(points) - 3 else intPoint + 2]
        return point.set(CatmullRom(weight, p0.x, p1.x, p2.x, p3.x), CatmullRom(weight, p0.y, p1.y, p2.y, p3.y))


class _CubicPoly:
    __slots__ = ('c0', 'c1', 'c2', 'c3')

    def init(self, x0, x1, t0, t1):
        self.c0 = x0
        self.c1 = t0
        self.c2 = -3 * x0 + 3 * x1 - 2 * t0 - t1
        self.c3 = 2 * x0 - 2 * x1 + t0 + t1

    def initCatmullRom(self, x0, x1, x2, x3, tension):
        self.init(x1, x2, tension * (x2 - x0), tension * (x3 - x1))

    def initNonuniformCatmullRom(self, x0, x1, x2, x3, dt0, dt1, dt2):
        t1 = (x1 - x0) / dt0 - (x2 - x0) / (dt0 + dt1) + (x2 - x1) / dt1
        t2 = (x2 - x1) / dt1 - (x3 - x1) / (dt1 + dt2) + (x3 - x2) / dt2
        t1 *= dt1
        t2 *= dt1
        self.init(x1, x2, t1, t2)

    def calc(self, t):
        t2 = t * t
        t3 = t2 * t
        return self.c0 + self.c1 * t + self.c2 * t2 + self.c3 * t3


class CatmullRomCurve3(Curve):
    isCatmullRomCurve3 = True

    def __init__(self, points=None, closed=False, curveType='centripetal', tension=0.5):
        Curve.__init__(self)
        self.type = 'CatmullRomCurve3'
        self.points = [_v3(p) for p in points] if points is not None else []
        self.closed = closed
        self.curveType = curveType
        self.tension = tension
        self._px, self._py, self._pz = _CubicPoly(), _CubicPoly(), _CubicPoly()

    def getPoint(self, t, optionalTarget=None):
        point = optionalTarget if optionalTarget is not None else Vector3()
        points = self.points
        l = len(points)
        p = (l - (0 if self.closed else 1)) * t
        intPoint = math.floor(p)
        weight = p - intPoint
        if self.closed:
            intPoint += 0 if intPoint > 0 else (math.floor(abs(intPoint) / l) + 1) * l
        elif weight == 0 and intPoint == l - 1:
            intPoint = l - 2
            weight = 1
        if self.closed or intPoint > 0:
            p0 = points[(intPoint - 1) % l]
        else:
            p0 = Vector3().subVectors(points[0], points[1]).add(points[0])
        p1 = points[intPoint % l]
        p2 = points[(intPoint + 1) % l]
        if self.closed or intPoint + 2 < l:
            p3 = points[(intPoint + 2) % l]
        else:
            p3 = Vector3().subVectors(points[l - 1], points[l - 2]).add(points[l - 1])
        px, py, pz = self._px, self._py, self._pz
        if self.curveType == 'centripetal' or self.curveType == 'chordal':
            pw = 0.5 if self.curveType == 'chordal' else 0.25
            dt0 = math.pow(p0.distanceToSquared(p1), pw)
            dt1 = math.pow(p1.distanceToSquared(p2), pw)
            dt2 = math.pow(p2.distanceToSquared(p3), pw)
            if dt1 < 1e-4:
                dt1 = 1.0
            if dt0 < 1e-4:
                dt0 = dt1
            if dt2 < 1e-4:
                dt2 = dt1
            px.initNonuniformCatmullRom(p0.x, p1.x, p2.x, p3.x, dt0, dt1, dt2)
            py.initNonuniformCatmullRom(p0.y, p1.y, p2.y, p3.y, dt0, dt1, dt2)
            pz.initNonuniformCatmullRom(p0.z, p1.z, p2.z, p3.z, dt0, dt1, dt2)
        elif self.curveType == 'catmullrom':
            px.initCatmullRom(p0.x, p1.x, p2.x, p3.x, self.tension)
            py.initCatmullRom(p0.y, p1.y, p2.y, p3.y, self.tension)
            pz.initCatmullRom(p0.z, p1.z, p2.z, p3.z, self.tension)
        return point.set(px.calc(weight), py.calc(weight), pz.calc(weight))


class CurvePath(Curve):
    def __init__(self):
        Curve.__init__(self)
        self.type = 'CurvePath'
        self.curves = []
        self.autoClose = False
        self.cacheLengths = None

    def add(self, curve):
        self.curves.append(curve)

    def closePath(self):
        startPoint = self.curves[0].getPoint(0)
        endPoint = self.curves[len(self.curves) - 1].getPoint(1)
        if not startPoint.equals(endPoint):
            if getattr(startPoint, 'isVector2', False):
                self.curves.append(LineCurve(endPoint, startPoint))
            else:
                self.curves.append(LineCurve3(endPoint, startPoint))
        return self

    def getPoint(self, t, optionalTarget=None):
        d = t * self.getLength()
        curveLengths = self.getCurveLengths()
        i = 0
        while i < len(curveLengths):
            if curveLengths[i] >= d:
                diff = curveLengths[i] - d
                curve = self.curves[i]
                segmentLength = curve.getLength()
                u = 0 if segmentLength == 0 else 1 - diff / segmentLength
                return curve.getPointAt(u, optionalTarget)
            i += 1
        return None

    def getLength(self):
        lens = self.getCurveLengths()
        return lens[len(lens) - 1]

    def updateArcLengths(self):
        self.needsUpdate = True
        self.cacheLengths = None
        self.getCurveLengths()

    def getCurveLengths(self):
        if self.cacheLengths is not None and len(self.cacheLengths) == len(self.curves):
            return self.cacheLengths
        lengths = []
        sums = 0
        for c in self.curves:
            sums += c.getLength()
            lengths.append(sums)
        self.cacheLengths = lengths
        return lengths

    def getSpacedPoints(self, divisions=40):
        points = [self.getPoint(i / divisions) for i in _jsrange_le(divisions)]
        if self.autoClose:
            points.append(points[0])
        return points

    def getPoints(self, divisions=12):
        points = []
        last = None
        for curve in self.curves:
            if getattr(curve, 'isEllipseCurve', False):
                resolution = divisions * 2
            elif getattr(curve, 'isLineCurve', False) or getattr(curve, 'isLineCurve3', False):
                resolution = 1
            elif getattr(curve, 'isSplineCurve', False):
                resolution = divisions * len(curve.points)
            else:
                resolution = divisions
            pts = curve.getPoints(resolution)
            for point in pts:
                if last is not None and last.equals(point):
                    continue
                points.append(point)
                last = point
        if self.autoClose and len(points) > 1 and not points[len(points) - 1].equals(points[0]):
            points.append(points[0])
        return points


class Path(CurvePath):
    def __init__(self, points=None):
        CurvePath.__init__(self)
        self.type = 'Path'
        self.currentPoint = Vector2()
        if points:
            self.setFromPoints(points)

    def setFromPoints(self, points):
        points = [_v2(p) for p in points]
        self.moveTo(points[0].x, points[0].y)
        for i in range(1, len(points)):
            self.lineTo(points[i].x, points[i].y)
        return self

    def moveTo(self, x, y):
        self.currentPoint.set(x, y)
        return self

    def lineTo(self, x, y):
        curve = LineCurve(self.currentPoint.clone(), Vector2(x, y))
        self.curves.append(curve)
        self.currentPoint.set(x, y)
        return self

    def quadraticCurveTo(self, aCPx, aCPy, aX, aY):
        curve = QuadraticBezierCurve(self.currentPoint.clone(), Vector2(aCPx, aCPy), Vector2(aX, aY))
        self.curves.append(curve)
        self.currentPoint.set(aX, aY)
        return self

    def bezierCurveTo(self, aCP1x, aCP1y, aCP2x, aCP2y, aX, aY):
        curve = CubicBezierCurve(self.currentPoint.clone(), Vector2(aCP1x, aCP1y), Vector2(aCP2x, aCP2y),
                                 Vector2(aX, aY))
        self.curves.append(curve)
        self.currentPoint.set(aX, aY)
        return self

    def splineThru(self, pts):
        pts = [_v2(p) for p in pts]
        npts = [self.currentPoint.clone()] + pts
        curve = SplineCurve(npts)
        self.curves.append(curve)
        self.currentPoint.copy(pts[len(pts) - 1])
        return self

    def arc(self, aX, aY, aRadius, aStartAngle, aEndAngle, aClockwise=False):
        x0 = self.currentPoint.x
        y0 = self.currentPoint.y
        self.absarc(aX + x0, aY + y0, aRadius, aStartAngle, aEndAngle, aClockwise)
        return self

    def absarc(self, aX, aY, aRadius, aStartAngle, aEndAngle, aClockwise=False):
        self.absellipse(aX, aY, aRadius, aRadius, aStartAngle, aEndAngle, aClockwise)
        return self

    def ellipse(self, aX, aY, xRadius, yRadius, aStartAngle, aEndAngle, aClockwise=False, aRotation=0):
        x0 = self.currentPoint.x
        y0 = self.currentPoint.y
        self.absellipse(aX + x0, aY + y0, xRadius, yRadius, aStartAngle, aEndAngle, aClockwise, aRotation)
        return self

    def absellipse(self, aX, aY, xRadius, yRadius, aStartAngle, aEndAngle, aClockwise=False, aRotation=0):
        curve = EllipseCurve(aX, aY, xRadius, yRadius, aStartAngle, aEndAngle, aClockwise, aRotation)
        if len(self.curves) > 0:
            firstPoint = curve.getPoint(0)
            if not firstPoint.equals(self.currentPoint):
                self.lineTo(firstPoint.x, firstPoint.y)
        self.curves.append(curve)
        lastPoint = curve.getPoint(1)
        self.currentPoint.copy(lastPoint)
        return self


class Shape(Path):
    def __init__(self, points=None):
        Path.__init__(self, points)
        self.uuid = generateUUID()
        self.type = 'Shape'
        self.holes = []

    def getPointsHoles(self, divisions):
        return [h.getPoints(divisions) for h in self.holes]

    def extractPoints(self, divisions):
        return JSObj(shape=self.getPoints(divisions), holes=self.getPointsHoles(divisions))


# ============================================================================================ ShapeUtils / Earcut

class _ENode:
    __slots__ = ('i', 'x', 'y', 'prev', 'next', 'z', 'prevZ', 'nextZ', 'steiner')

    def __init__(self, i, x, y):
        self.i = i
        self.x = x
        self.y = y
        self.prev = None
        self.next = None
        self.z = 0
        self.prevZ = None
        self.nextZ = None
        self.steiner = False


def _truthy(v):
    return v != 0 and v == v


def earcut(data, holeIndices=None, dim=2):
    """mapbox/earcut 3.0.2 (three/src/extras/lib/earcut.js)."""
    hasHoles = bool(holeIndices) and len(holeIndices) > 0
    outerLen = holeIndices[0] * dim if hasHoles else len(data)
    outerNode = _linkedList(data, 0, outerLen, dim, True)
    triangles = []
    if outerNode is None or outerNode.next is outerNode.prev:
        return triangles
    minX = minY = invSize = None
    if hasHoles:
        outerNode = _eliminateHoles(data, holeIndices, outerNode, dim)
    if len(data) > 80 * dim:
        minX = data[0]
        minY = data[1]
        maxX = minX
        maxY = minY
        for i in range(dim, outerLen, dim):
            x = data[i]
            y = data[i + 1]
            if x < minX:
                minX = x
            if y < minY:
                minY = y
            if x > maxX:
                maxX = x
            if y > maxY:
                maxY = y
        invSize = max(maxX - minX, maxY - minY)
        invSize = 32767 / invSize if invSize != 0 else 0
    _earcutLinked(outerNode, triangles, dim, minX, minY, invSize, 0)
    return triangles


def _linkedList(data, start, end, dim, clockwise):
    last = None
    if clockwise == (_signedArea(data, start, end, dim) > 0):
        for i in range(start, end, dim):
            last = _insertNode(i // dim, data[i], data[i + 1], last)
    else:
        for i in range(end - dim, start - 1, -dim):
            last = _insertNode(i // dim, data[i], data[i + 1], last)
    if last is not None and _equals(last, last.next):
        _removeNode(last)
        last = last.next
    return last


def _filterPoints(start, end=None):
    if start is None:
        return start
    if end is None:
        end = start
    p = start
    while True:
        again = False
        if not p.steiner and (_equals(p, p.next) or _area(p.prev, p, p.next) == 0):
            _removeNode(p)
            p = end = p.prev
            if p is p.next:
                break
            again = True
        else:
            p = p.next
        if not (again or p is not end):
            break
    return end


def _earcutLinked(ear, triangles, dim, minX, minY, invSize, pass_):
    if ear is None:
        return
    if not pass_ and invSize:
        _indexCurve(ear, minX, minY, invSize)
    stop = ear
    while ear.prev is not ear.next:
        prev = ear.prev
        nxt = ear.next
        if (_isEarHashed(ear, minX, minY, invSize) if invSize else _isEar(ear)):
            triangles.extend((prev.i, ear.i, nxt.i))
            _removeNode(ear)
            ear = nxt.next
            stop = nxt.next
            continue
        ear = nxt
        if ear is stop:
            if not pass_:
                _earcutLinked(_filterPoints(ear), triangles, dim, minX, minY, invSize, 1)
            elif pass_ == 1:
                ear = _cureLocalIntersections(_filterPoints(ear), triangles)
                _earcutLinked(ear, triangles, dim, minX, minY, invSize, 2)
            elif pass_ == 2:
                _splitEarcut(ear, triangles, dim, minX, minY, invSize)
            break


def _isEar(ear):
    a = ear.prev
    b = ear
    c = ear.next
    if _area(a, b, c) >= 0:
        return False
    ax, bx, cx, ay, by, cy = a.x, b.x, c.x, a.y, b.y, c.y
    x0 = min(ax, bx, cx)
    y0 = min(ay, by, cy)
    x1 = max(ax, bx, cx)
    y1 = max(ay, by, cy)
    p = c.next
    while p is not a:
        if (x0 <= p.x <= x1 and y0 <= p.y <= y1 and
                _pointInTriangleExceptFirst(ax, ay, bx, by, cx, cy, p.x, p.y) and
                _area(p.prev, p, p.next) >= 0):
            return False
        p = p.next
    return True


def _isEarHashed(ear, minX, minY, invSize):
    a = ear.prev
    b = ear
    c = ear.next
    if _area(a, b, c) >= 0:
        return False
    ax, bx, cx, ay, by, cy = a.x, b.x, c.x, a.y, b.y, c.y
    x0 = min(ax, bx, cx)
    y0 = min(ay, by, cy)
    x1 = max(ax, bx, cx)
    y1 = max(ay, by, cy)
    minZ = _zOrder(x0, y0, minX, minY, invSize)
    maxZ = _zOrder(x1, y1, minX, minY, invSize)
    p = ear.prevZ
    n = ear.nextZ
    while p is not None and p.z >= minZ and n is not None and n.z <= maxZ:
        if (x0 <= p.x <= x1 and y0 <= p.y <= y1 and p is not a and p is not c and
                _pointInTriangleExceptFirst(ax, ay, bx, by, cx, cy, p.x, p.y) and _area(p.prev, p, p.next) >= 0):
            return False
        p = p.prevZ
        if (x0 <= n.x <= x1 and y0 <= n.y <= y1 and n is not a and n is not c and
                _pointInTriangleExceptFirst(ax, ay, bx, by, cx, cy, n.x, n.y) and _area(n.prev, n, n.next) >= 0):
            return False
        n = n.nextZ
    while p is not None and p.z >= minZ:
        if (x0 <= p.x <= x1 and y0 <= p.y <= y1 and p is not a and p is not c and
                _pointInTriangleExceptFirst(ax, ay, bx, by, cx, cy, p.x, p.y) and _area(p.prev, p, p.next) >= 0):
            return False
        p = p.prevZ
    while n is not None and n.z <= maxZ:
        if (x0 <= n.x <= x1 and y0 <= n.y <= y1 and n is not a and n is not c and
                _pointInTriangleExceptFirst(ax, ay, bx, by, cx, cy, n.x, n.y) and _area(n.prev, n, n.next) >= 0):
            return False
        n = n.nextZ
    return True


def _cureLocalIntersections(start, triangles):
    p = start
    while True:
        a = p.prev
        b = p.next.next
        if (not _equals(a, b) and _intersects(a, p, p.next, b) and _locallyInside(a, b) and
                _locallyInside(b, a)):
            triangles.extend((a.i, p.i, b.i))
            _removeNode(p)
            _removeNode(p.next)
            p = start = b
        p = p.next
        if p is start:
            break
    return _filterPoints(p)


def _splitEarcut(start, triangles, dim, minX, minY, invSize):
    a = start
    while True:
        b = a.next.next
        while b is not a.prev:
            if a.i != b.i and _isValidDiagonal(a, b):
                c = _splitPolygon(a, b)
                a = _filterPoints(a, a.next)
                c = _filterPoints(c, c.next)
                _earcutLinked(a, triangles, dim, minX, minY, invSize, 0)
                _earcutLinked(c, triangles, dim, minX, minY, invSize, 0)
                return
            b = b.next
        a = a.next
        if a is start:
            break


def _eliminateHoles(data, holeIndices, outerNode, dim):
    queue = []
    ln = len(holeIndices)
    for i in range(ln):
        start = holeIndices[i] * dim
        end = holeIndices[i + 1] * dim if i < ln - 1 else len(data)
        lst = _linkedList(data, start, end, dim, False)
        if lst is lst.next:
            lst.steiner = True
        queue.append(_getLeftmost(lst))
    queue.sort(key=cmp_to_key(_compareXYSlope))
    for q in queue:
        outerNode = _eliminateHole(q, outerNode)
    return outerNode


def _cmpnum(v):
    if v != v:
        return 0
    return -1 if v < 0 else (1 if v > 0 else 0)


def _div(a, b):
    if b == 0:
        if a == 0 or a != a:
            return _NAN
        return math.copysign(_INF, a) * (1 if math.copysign(1, b) > 0 else -1)
    return a / b


def _compareXYSlope(a, b):
    result = a.x - b.x
    if result == 0:
        result = a.y - b.y
        if result == 0:
            aSlope = _div(a.next.y - a.y, a.next.x - a.x)
            bSlope = _div(b.next.y - b.y, b.next.x - b.x)
            result = aSlope - bSlope
    return _cmpnum(result)


def _eliminateHole(hole, outerNode):
    bridge = _findHoleBridge(hole, outerNode)
    if bridge is None:
        return outerNode
    bridgeReverse = _splitPolygon(bridge, hole)
    _filterPoints(bridgeReverse, bridgeReverse.next)
    return _filterPoints(bridge, bridge.next)


def _findHoleBridge(hole, outerNode):
    p = outerNode
    hx = hole.x
    hy = hole.y
    qx = -_INF
    m = None
    if _equals(hole, p):
        return p
    while True:
        if _equals(hole, p.next):
            return p.next
        elif hy <= p.y and hy >= p.next.y and p.next.y != p.y:
            x = p.x + (hy - p.y) * (p.next.x - p.x) / (p.next.y - p.y)
            if x <= hx and x > qx:
                qx = x
                m = p if p.x < p.next.x else p.next
                if x == hx:
                    return m
        p = p.next
        if p is outerNode:
            break
    if m is None:
        return None
    stop = m
    mx = m.x
    my = m.y
    tanMin = _INF
    p = m
    while True:
        if (hx >= p.x and p.x >= mx and hx != p.x and
                _pointInTriangle(hx if hy < my else qx, hy, mx, my, qx if hy < my else hx, hy, p.x, p.y)):
            tan = abs(hy - p.y) / (hx - p.x)
            if (_locallyInside(p, hole) and
                    (tan < tanMin or (tan == tanMin and (p.x > m.x or (p.x == m.x and _sectorContainsSector(m, p)))))):
                m = p
                tanMin = tan
        p = p.next
        if p is stop:
            break
    return m


def _sectorContainsSector(m, p):
    return _area(m.prev, m, p.prev) < 0 and _area(p.next, m, m.next) < 0


def _indexCurve(start, minX, minY, invSize):
    p = start
    while True:
        if p.z == 0:
            p.z = _zOrder(p.x, p.y, minX, minY, invSize)
        p.prevZ = p.prev
        p.nextZ = p.next
        p = p.next
        if p is start:
            break
    p.prevZ.nextZ = None
    p.prevZ = None
    _sortLinked(p)


def _sortLinked(lst):
    inSize = 1
    while True:
        p = lst
        lst = None
        tail = None
        numMerges = 0
        while p is not None:
            numMerges += 1
            q = p
            pSize = 0
            for _ in range(inSize):
                pSize += 1
                q = q.nextZ
                if q is None:
                    break
            qSize = inSize
            while pSize > 0 or (qSize > 0 and q is not None):
                if pSize != 0 and (qSize == 0 or q is None or p.z <= q.z):
                    e = p
                    p = p.nextZ
                    pSize -= 1
                else:
                    e = q
                    q = q.nextZ
                    qSize -= 1
                if tail is not None:
                    tail.nextZ = e
                else:
                    lst = e
                e.prevZ = tail
                tail = e
            p = q
        tail.nextZ = None
        inSize *= 2
        if not numMerges > 1:
            break
    return lst


def _zOrder(x, y, minX, minY, invSize):
    x = to_int32((x - minX) * invSize)
    y = to_int32((y - minY) * invSize)
    x = (x | (x << 8)) & 0x00FF00FF
    x = (x | (x << 4)) & 0x0F0F0F0F
    x = (x | (x << 2)) & 0x33333333
    x = (x | (x << 1)) & 0x55555555
    y = (y | (y << 8)) & 0x00FF00FF
    y = (y | (y << 4)) & 0x0F0F0F0F
    y = (y | (y << 2)) & 0x33333333
    y = (y | (y << 1)) & 0x55555555
    return to_int32(x | to_int32(y << 1))


def _getLeftmost(start):
    p = start
    leftmost = start
    while True:
        if p.x < leftmost.x or (p.x == leftmost.x and p.y < leftmost.y):
            leftmost = p
        p = p.next
        if p is start:
            break
    return leftmost


def _pointInTriangle(ax, ay, bx, by, cx, cy, px, py):
    return ((cx - px) * (ay - py) >= (ax - px) * (cy - py) and
            (ax - px) * (by - py) >= (bx - px) * (ay - py) and
            (bx - px) * (cy - py) >= (cx - px) * (by - py))


def _pointInTriangleExceptFirst(ax, ay, bx, by, cx, cy, px, py):
    return not (ax == px and ay == py) and _pointInTriangle(ax, ay, bx, by, cx, cy, px, py)


def _isValidDiagonal(a, b):
    return (a.next.i != b.i and a.prev.i != b.i and not _intersectsPolygon(a, b) and
            ((_locallyInside(a, b) and _locallyInside(b, a) and _middleInside(a, b) and
              (_truthy(_area(a.prev, a, b.prev)) or _truthy(_area(a, b.prev, b)))) or
             (_equals(a, b) and _area(a.prev, a, a.next) > 0 and _area(b.prev, b, b.next) > 0)))


def _area(p, q, r):
    return (q.y - p.y) * (r.x - q.x) - (q.x - p.x) * (r.y - q.y)


def _equals(p1, p2):
    return p1.x == p2.x and p1.y == p2.y


def _sign(num):
    return 1 if num > 0 else (-1 if num < 0 else 0)


def _onSegment(p, q, r):
    return (q.x <= max(p.x, r.x) and q.x >= min(p.x, r.x) and q.y <= max(p.y, r.y) and
            q.y >= min(p.y, r.y))


def _intersects(p1, q1, p2, q2):
    o1 = _sign(_area(p1, q1, p2))
    o2 = _sign(_area(p1, q1, q2))
    o3 = _sign(_area(p2, q2, p1))
    o4 = _sign(_area(p2, q2, q1))
    if o1 != o2 and o3 != o4:
        return True
    if o1 == 0 and _onSegment(p1, p2, q1):
        return True
    if o2 == 0 and _onSegment(p1, q2, q1):
        return True
    if o3 == 0 and _onSegment(p2, p1, q2):
        return True
    if o4 == 0 and _onSegment(p2, q1, q2):
        return True
    return False


def _intersectsPolygon(a, b):
    p = a
    while True:
        if (p.i != a.i and p.next.i != a.i and p.i != b.i and p.next.i != b.i and
                _intersects(p, p.next, a, b)):
            return True
        p = p.next
        if p is a:
            break
    return False


def _locallyInside(a, b):
    if _area(a.prev, a, a.next) < 0:
        return _area(a, b, a.next) >= 0 and _area(a, a.prev, b) >= 0
    return _area(a, b, a.prev) < 0 or _area(a, a.next, b) < 0


def _middleInside(a, b):
    p = a
    inside = False
    px = (a.x + b.x) / 2
    py = (a.y + b.y) / 2
    while True:
        if (((p.y > py) != (p.next.y > py)) and p.next.y != p.y and
                (px < (p.next.x - p.x) * (py - p.y) / (p.next.y - p.y) + p.x)):
            inside = not inside
        p = p.next
        if p is a:
            break
    return inside


def _splitPolygon(a, b):
    a2 = _ENode(a.i, a.x, a.y)
    b2 = _ENode(b.i, b.x, b.y)
    an = a.next
    bp = b.prev
    a.next = b
    b.prev = a
    a2.next = an
    an.prev = a2
    b2.next = a2
    a2.prev = b2
    bp.next = b2
    b2.prev = bp
    return b2


def _insertNode(i, x, y, last):
    p = _ENode(i, x, y)
    if last is None:
        p.prev = p
        p.next = p
    else:
        p.next = last.next
        p.prev = last
        last.next.prev = p
        last.next = p
    return p


def _removeNode(p):
    p.next.prev = p.prev
    p.prev.next = p.next
    if p.prevZ is not None:
        p.prevZ.nextZ = p.nextZ
    if p.nextZ is not None:
        p.nextZ.prevZ = p.prevZ


def _signedArea(data, start, end, dim):
    s = 0
    j = end - dim
    for i in range(start, end, dim):
        s += (data[j] - data[i]) * (data[i + 1] + data[j + 1])
        j = i
    return s


class Earcut:
    @staticmethod
    def triangulate(data, holeIndices=None, dim=2):
        return earcut(data, holeIndices, dim)


def _removeDupEndPts(points):
    l = len(points)
    if l > 2 and points[l - 1].equals(points[0]):
        points.pop()


class ShapeUtils:
    @staticmethod
    def area(contour):
        n = len(contour)
        a = 0.0
        p = n - 1
        for q in range(n):
            a += contour[p].x * contour[q].y - contour[q].x * contour[p].y
            p = q
        return a * 0.5

    @staticmethod
    def isClockWise(pts):
        return ShapeUtils.area(pts) < 0

    @staticmethod
    def triangulateShape(contour, holes):
        vertices = []
        holeIndices = []
        faces = []
        _removeDupEndPts(contour)
        for p in contour:
            vertices.append(p.x)
            vertices.append(p.y)
        holeIndex = len(contour)
        for h in holes:
            _removeDupEndPts(h)
        for h in holes:
            holeIndices.append(holeIndex)
            holeIndex += len(h)
            for p in h:
                vertices.append(p.x)
                vertices.append(p.y)
        triangles = Earcut.triangulate(vertices, holeIndices)
        for i in range(0, len(triangles), 3):
            faces.append(triangles[i:i + 3])
        return faces


# ============================================================================================ Tube / Shape / Extrude

class TubeGeometry(Geometry):
    def __init__(self, path=None, tubularSegments=64, radius=1, radialSegments=8, closed=False):
        Geometry.__init__(self)
        if path is None:
            path = QuadraticBezierCurve3(Vector3(-1, -1, 0), Vector3(-1, 1, 0), Vector3(1, 1, 0))
        self.type = 'TubeGeometry'
        self.parameters = JSObj(path=path, tubularSegments=tubularSegments, radius=radius,
                                radialSegments=radialSegments, closed=closed)
        tubularSegments = _n(tubularSegments)
        radialSegments = _n(radialSegments)
        frames = path.computeFrenetFrames(tubularSegments, closed)
        self.tangents = frames.tangents
        self.normals = frames.normals
        self.binormals = frames.binormals
        vertices, normals, uvs, indices = [], [], [], []
        P = Vector3()
        normal = Vector3()

        def generateSegment(i):
            nonlocal P
            P = path.getPointAt(i / tubularSegments, P)
            N = frames.normals[i]
            B = frames.binormals[i]
            for j in range(radialSegments + 1):
                v = j / radialSegments * math.pi * 2
                sin = math.sin(v)
                cos = -math.cos(v)
                normal.x = (cos * N.x + sin * B.x)
                normal.y = (cos * N.y + sin * B.y)
                normal.z = (cos * N.z + sin * B.z)
                normal.normalize()
                normals.extend((normal.x, normal.y, normal.z))
                vertices.extend((P.x + radius * normal.x, P.y + radius * normal.y, P.z + radius * normal.z))

        for i in range(tubularSegments):
            generateSegment(i)
        generateSegment(tubularSegments if closed is False else 0)
        for i in range(tubularSegments + 1):
            for j in range(radialSegments + 1):
                uvs.extend((i / tubularSegments, j / radialSegments))
        for j in range(1, tubularSegments + 1):
            for i in range(1, radialSegments + 1):
                a = (radialSegments + 1) * (j - 1) + (i - 1)
                b = (radialSegments + 1) * j + (i - 1)
                c = (radialSegments + 1) * j + i
                d = (radialSegments + 1) * (j - 1) + i
                indices.extend((a, b, d, b, c, d))
        self.setIndex(indices)
        self.setAttribute('position', Float32BufferAttribute(vertices, 3))
        self.setAttribute('normal', Float32BufferAttribute(normals, 3))
        self.setAttribute('uv', Float32BufferAttribute(uvs, 2))


class ShapeGeometry(Geometry):
    def __init__(self, shapes=None, curveSegments=12):
        Geometry.__init__(self)
        if shapes is None:
            shapes = Shape([Vector2(0, 0.5), Vector2(-0.5, -0.5), Vector2(0.5, -0.5)])
        self.type = 'ShapeGeometry'
        self.parameters = JSObj(shapes=shapes, curveSegments=curveSegments)
        indices, vertices, normals, uvs = [], [], [], []
        st = {'groupStart': 0, 'groupCount': 0}

        def addShape(shape):
            indexOffset = len(vertices) // 3
            points = shape.extractPoints(curveSegments)
            shapeVertices = points.shape
            shapeHoles = points.holes
            if ShapeUtils.isClockWise(shapeVertices) is False:
                shapeVertices.reverse()
            for i in range(len(shapeHoles)):
                shapeHole = shapeHoles[i]
                if ShapeUtils.isClockWise(shapeHole) is True:
                    shapeHole.reverse()
                    shapeHoles[i] = shapeHole
            faces = ShapeUtils.triangulateShape(shapeVertices, shapeHoles)
            for shapeHole in shapeHoles:
                shapeVertices = shapeVertices + shapeHole
            for vertex in shapeVertices:
                vertices.extend((vertex.x, vertex.y, 0))
                normals.extend((0, 0, 1))
                uvs.extend((vertex.x, vertex.y))
            for face in faces:
                indices.extend((face[0] + indexOffset, face[1] + indexOffset, face[2] + indexOffset))
                st['groupCount'] += 3

        if not isinstance(shapes, (list, tuple)):
            addShape(shapes)
        else:
            for i, s in enumerate(shapes):
                addShape(s)
                self.addGroup(st['groupStart'], st['groupCount'], i)
                st['groupStart'] += st['groupCount']
                st['groupCount'] = 0
        self.setIndex(indices)
        self.setAttribute('position', Float32BufferAttribute(vertices, 3))
        self.setAttribute('normal', Float32BufferAttribute(normals, 3))
        self.setAttribute('uv', Float32BufferAttribute(uvs, 2))


class _WorldUVGenerator:
    @staticmethod
    def generateTopUV(geometry, vertices, indexA, indexB, indexC):
        return [Vector2(vertices[indexA * 3], vertices[indexA * 3 + 1]),
                Vector2(vertices[indexB * 3], vertices[indexB * 3 + 1]),
                Vector2(vertices[indexC * 3], vertices[indexC * 3 + 1])]

    @staticmethod
    def generateSideWallUV(geometry, vertices, indexA, indexB, indexC, indexD):
        a_x, a_y, a_z = vertices[indexA * 3], vertices[indexA * 3 + 1], vertices[indexA * 3 + 2]
        b_x, b_y, b_z = vertices[indexB * 3], vertices[indexB * 3 + 1], vertices[indexB * 3 + 2]
        c_x, c_y, c_z = vertices[indexC * 3], vertices[indexC * 3 + 1], vertices[indexC * 3 + 2]
        d_x, d_y, d_z = vertices[indexD * 3], vertices[indexD * 3 + 1], vertices[indexD * 3 + 2]
        if abs(a_y - b_y) < abs(a_x - b_x):
            return [Vector2(a_x, 1 - a_z), Vector2(b_x, 1 - b_z), Vector2(c_x, 1 - c_z), Vector2(d_x, 1 - d_z)]
        return [Vector2(a_y, 1 - a_z), Vector2(b_y, 1 - b_z), Vector2(c_y, 1 - c_z), Vector2(d_y, 1 - d_z)]


WorldUVGenerator = _WorldUVGenerator


class ExtrudeGeometry(Geometry):
    """options (dict or kwargs): depth=1, bevelEnabled=True, bevelThickness=0.2, bevelSize=bevelThickness-0.1,
    bevelOffset=0, bevelSegments=3, curveSegments=12, steps=1, extrudePath=None, UVGenerator=WorldUVGenerator."""

    def __init__(self, shapes=None, options=None, **kw):
        Geometry.__init__(self)
        if shapes is None:
            shapes = Shape([Vector2(0.5, 0.5), Vector2(-0.5, 0.5), Vector2(-0.5, -0.5), Vector2(0.5, -0.5)])
        options = dict(options or {})
        options.update(kw)
        self.type = 'ExtrudeGeometry'
        self.parameters = JSObj(shapes=shapes, options=options)
        shapes = list(shapes) if isinstance(shapes, (list, tuple)) else [shapes]
        verticesArray = []
        uvArray = []
        for shape in shapes:
            self._addShape(shape, options, verticesArray, uvArray)
        self.setAttribute('position', Float32BufferAttribute(verticesArray, 3))
        self.setAttribute('uv', Float32BufferAttribute(uvArray, 2))
        self.computeVertexNormals()

    def _addShape(self, shape, options, verticesArray, uvArray):
        scope = self
        placeholder = []
        curveSegments = _opt(options, 'curveSegments', 12)
        steps = _n(_opt(options, 'steps', 1))
        depth = _opt(options, 'depth', 1)
        bevelEnabled = _opt(options, 'bevelEnabled', True)
        bevelThickness = _opt(options, 'bevelThickness', 0.2)
        bevelSize = _opt(options, 'bevelSize', bevelThickness - 0.1)
        bevelOffset = _opt(options, 'bevelOffset', 0)
        bevelSegments = _n(_opt(options, 'bevelSegments', 3))
        extrudePath = options.get('extrudePath')
        uvgen = _opt(options, 'UVGenerator', WorldUVGenerator)
        extrudeByPath = False
        extrudePts = splineTube = binormal = normal = position2 = None
        if extrudePath:
            extrudePts = extrudePath.getSpacedPoints(steps)
            extrudeByPath = True
            bevelEnabled = False
            isClosed = extrudePath.closed if getattr(extrudePath, 'isCatmullRomCurve3', False) else False
            splineTube = extrudePath.computeFrenetFrames(steps, isClosed)
            binormal = Vector3()
            normal = Vector3()
            position2 = Vector3()
        if not bevelEnabled:
            bevelSegments = 0
            bevelThickness = 0
            bevelSize = 0
            bevelOffset = 0

        shapePoints = shape.extractPoints(curveSegments)
        vertices = shapePoints.shape
        holes = shapePoints.holes
        reverse = not ShapeUtils.isClockWise(vertices)
        if reverse:
            vertices.reverse()
            for h in range(len(holes)):
                ahole = holes[h]
                if ShapeUtils.isClockWise(ahole):
                    ahole.reverse()
                    holes[h] = ahole

        def mergeOverlappingPoints(points):
            THRESHOLD = 1e-10
            THRESHOLD_SQ = THRESHOLD * THRESHOLD
            prevPos = points[0]
            i = 1
            while i <= len(points):
                currentIndex = i % len(points)
                currentPos = points[currentIndex]
                dx = currentPos.x - prevPos.x
                dy = currentPos.y - prevPos.y
                distSq = dx * dx + dy * dy
                scalingFactorSqrt = max(abs(currentPos.x), abs(currentPos.y), abs(prevPos.x), abs(prevPos.y))
                thresholdSqScaled = THRESHOLD_SQ * scalingFactorSqrt * scalingFactorSqrt
                if distSq <= thresholdSqScaled:
                    del points[currentIndex]
                    continue  # i-- ; continue ; i++  -> same i
                prevPos = currentPos
                i += 1

        mergeOverlappingPoints(vertices)
        for h in holes:
            mergeOverlappingPoints(h)
        numHoles = len(holes)
        contour = vertices
        for h in range(numHoles):
            vertices = vertices + holes[h]

        def scalePt2(pt, vec, size):
            return pt.clone().addScaledVector(vec, size)

        vlen = len(vertices)

        def getBevelVec(inPt, inPrev, inNext):
            v_prev_x = inPt.x - inPrev.x
            v_prev_y = inPt.y - inPrev.y
            v_next_x = inNext.x - inPt.x
            v_next_y = inNext.y - inPt.y
            v_prev_lensq = (v_prev_x * v_prev_x + v_prev_y * v_prev_y)
            collinear0 = (v_prev_x * v_next_y - v_prev_y * v_next_x)
            if abs(collinear0) > EPSILON:
                v_prev_len = math.sqrt(v_prev_lensq)
                v_next_len = math.sqrt(v_next_x * v_next_x + v_next_y * v_next_y)
                ptPrevShift_x = (inPrev.x - v_prev_y / v_prev_len)
                ptPrevShift_y = (inPrev.y + v_prev_x / v_prev_len)
                ptNextShift_x = (inNext.x - v_next_y / v_next_len)
                ptNextShift_y = (inNext.y + v_next_x / v_next_len)
                sf = (((ptNextShift_x - ptPrevShift_x) * v_next_y - (ptNextShift_y - ptPrevShift_y) * v_next_x) /
                      (v_prev_x * v_next_y - v_prev_y * v_next_x))
                v_trans_x = (ptPrevShift_x + v_prev_x * sf - inPt.x)
                v_trans_y = (ptPrevShift_y + v_prev_y * sf - inPt.y)
                v_trans_lensq = (v_trans_x * v_trans_x + v_trans_y * v_trans_y)
                if v_trans_lensq <= 2:
                    return Vector2(v_trans_x, v_trans_y)
                shrink_by = math.sqrt(v_trans_lensq / 2)
            else:
                direction_eq = False
                if v_prev_x > EPSILON:
                    if v_next_x > EPSILON:
                        direction_eq = True
                else:
                    if v_prev_x < -EPSILON:
                        if v_next_x < -EPSILON:
                            direction_eq = True
                    else:
                        if js_sign(v_prev_y) == js_sign(v_next_y):
                            direction_eq = True
                if direction_eq:
                    v_trans_x = -v_prev_y
                    v_trans_y = v_prev_x
                    shrink_by = math.sqrt(v_prev_lensq)
                else:
                    v_trans_x = v_prev_x
                    v_trans_y = v_prev_y
                    shrink_by = math.sqrt(v_prev_lensq / 2)
            return Vector2(v_trans_x / shrink_by, v_trans_y / shrink_by)

        def movements(pts):
            out = []
            il = len(pts)
            for i in range(il):
                j = i - 1 if i > 0 else il - 1
                k = i + 1 if i + 1 < il else 0
                out.append(getBevelVec(pts[i], pts[j], pts[k]))
            return out

        contourMovements = movements(contour)
        holesMovements = []
        verticesMovements = list(contourMovements)
        for h in range(numHoles):
            oneHoleMovements = movements(holes[h])
            holesMovements.append(oneHoleMovements)
            verticesMovements = verticesMovements + oneHoleMovements

        def v(x, y, z):
            placeholder.append(x)
            placeholder.append(y)
            placeholder.append(z)

        if bevelSegments == 0:
            faces = ShapeUtils.triangulateShape(contour, holes)
        else:
            contractedContourVertices = []
            expandedHoleVertices = []
            for b in range(bevelSegments):
                t = b / bevelSegments
                z = bevelThickness * math.cos(t * math.pi / 2)
                bs = bevelSize * math.sin(t * math.pi / 2) + bevelOffset
                for i in range(len(contour)):
                    vert = scalePt2(contour[i], contourMovements[i], bs)
                    v(vert.x, vert.y, -z)
                    if t == 0:
                        contractedContourVertices.append(vert)
                for h in range(numHoles):
                    ahole = holes[h]
                    oneHoleMovements = holesMovements[h]
                    oneHoleVertices = []
                    for i in range(len(ahole)):
                        vert = scalePt2(ahole[i], oneHoleMovements[i], bs)
                        v(vert.x, vert.y, -z)
                        if t == 0:
                            oneHoleVertices.append(vert)
                    if t == 0:
                        expandedHoleVertices.append(oneHoleVertices)
            faces = ShapeUtils.triangulateShape(contractedContourVertices, expandedHoleVertices)
        flen = len(faces)
        bs = bevelSize + bevelOffset
        for i in range(vlen):
            vert = scalePt2(vertices[i], verticesMovements[i], bs) if bevelEnabled else vertices[i]
            if not extrudeByPath:
                v(vert.x, vert.y, 0)
            else:
                normal.copy(splineTube.normals[0]).multiplyScalar(vert.x)
                binormal.copy(splineTube.binormals[0]).multiplyScalar(vert.y)
                position2.copy(extrudePts[0]).add(normal).add(binormal)
                v(position2.x, position2.y, position2.z)
        for s in range(1, steps + 1):
            for i in range(vlen):
                vert = scalePt2(vertices[i], verticesMovements[i], bs) if bevelEnabled else vertices[i]
                if not extrudeByPath:
                    v(vert.x, vert.y, depth / steps * s)
                else:
                    normal.copy(splineTube.normals[s]).multiplyScalar(vert.x)
                    binormal.copy(splineTube.binormals[s]).multiplyScalar(vert.y)
                    position2.copy(extrudePts[s]).add(normal).add(binormal)
                    v(position2.x, position2.y, position2.z)
        for b in range(bevelSegments - 1, -1, -1):
            t = b / bevelSegments
            z = bevelThickness * math.cos(t * math.pi / 2)
            bs2 = bevelSize * math.sin(t * math.pi / 2) + bevelOffset
            for i in range(len(contour)):
                vert = scalePt2(contour[i], contourMovements[i], bs2)
                v(vert.x, vert.y, depth + z)
            for h in range(len(holes)):
                ahole = holes[h]
                oneHoleMovements = holesMovements[h]
                for i in range(len(ahole)):
                    vert = scalePt2(ahole[i], oneHoleMovements[i], bs2)
                    if not extrudeByPath:
                        v(vert.x, vert.y, depth + z)
                    else:
                        v(vert.x, vert.y + extrudePts[steps - 1].y, extrudePts[steps - 1].x + z)

        def addVertex(index):
            verticesArray.append(placeholder[index * 3 + 0])
            verticesArray.append(placeholder[index * 3 + 1])
            verticesArray.append(placeholder[index * 3 + 2])

        def addUV(vector2):
            uvArray.append(vector2.x)
            uvArray.append(vector2.y)

        def f3(a, b, c):
            addVertex(a)
            addVertex(b)
            addVertex(c)
            nextIndex = len(verticesArray) // 3
            uvs = uvgen.generateTopUV(scope, verticesArray, nextIndex - 3, nextIndex - 2, nextIndex - 1)
            addUV(uvs[0])
            addUV(uvs[1])
            addUV(uvs[2])

        def f4(a, b, c, d):
            addVertex(a)
            addVertex(b)
            addVertex(d)
            addVertex(b)
            addVertex(c)
            addVertex(d)
            nextIndex = len(verticesArray) // 3
            uvs = uvgen.generateSideWallUV(scope, verticesArray, nextIndex - 6, nextIndex - 3, nextIndex - 2,
                                           nextIndex - 1)
            addUV(uvs[0])
            addUV(uvs[1])
            addUV(uvs[3])
            addUV(uvs[1])
            addUV(uvs[2])
            addUV(uvs[3])

        def buildLidFaces():
            start = len(verticesArray) // 3
            if bevelEnabled:
                layer = 0
                offset = vlen * layer
                for i in range(flen):
                    face = faces[i]
                    f3(face[2] + offset, face[1] + offset, face[0] + offset)
                layer = steps + bevelSegments * 2
                offset = vlen * layer
                for i in range(flen):
                    face = faces[i]
                    f3(face[0] + offset, face[1] + offset, face[2] + offset)
            else:
                for i in range(flen):
                    face = faces[i]
                    f3(face[2], face[1], face[0])
                for i in range(flen):
                    face = faces[i]
                    f3(face[0] + vlen * steps, face[1] + vlen * steps, face[2] + vlen * steps)
            scope.addGroup(start, len(verticesArray) // 3 - start, 0)

        def sidewalls(cont, layeroffset):
            i = len(cont)
            while True:
                i -= 1
                if not i >= 0:
                    break
                j = i
                k = i - 1
                if k < 0:
                    k = len(cont) - 1
                for s in range(steps + bevelSegments * 2):
                    slen1 = vlen * s
                    slen2 = vlen * (s + 1)
                    a = layeroffset + j + slen1
                    b = layeroffset + k + slen1
                    c = layeroffset + k + slen2
                    d = layeroffset + j + slen2
                    f4(a, b, c, d)

        def buildSideFaces():
            start = len(verticesArray) // 3
            layeroffset = 0
            sidewalls(contour, layeroffset)
            layeroffset += len(contour)
            for h in range(len(holes)):
                ahole = holes[h]
                sidewalls(ahole, layeroffset)
                layeroffset += len(ahole)
            scope.addGroup(start, len(verticesArray) // 3 - start, 1)

        buildLidFaces()
        buildSideFaces()


# ============================================================================================ RoundedBoxGeometry

class RoundedBoxGeometry(BoxGeometry):
    """three/addons/geometries/RoundedBoxGeometry.js (non-indexed, 6 groups)."""

    def __init__(self, width=1, height=1, depth=1, segments=2, radius=0.1):
        totalSegments = segments * 2 + 1
        radius = min(width / 2, height / 2, depth / 2, radius)
        BoxGeometry.__init__(self, 1, 1, 1, totalSegments, totalSegments, totalSegments)
        self.type = 'RoundedBoxGeometry'
        self.parameters = JSObj(width=width, height=height, depth=depth, segments=segments, radius=radius)
        if totalSegments == 1:
            return
        geometry2 = self.toNonIndexed()
        self.index = None
        self.attributes['position'] = geometry2.attributes.position
        self.attributes['normal'] = geometry2.attributes.normal
        self.attributes['uv'] = geometry2.attributes.uv
        pos = self.attributes.position.view(np.ndarray)
        nor = self.attributes.normal.view(np.ndarray)
        uvs = self.attributes.uv.view(np.ndarray)
        halfSegmentSize = 0.5 / totalSegments
        bx = width / 2 - radius
        by = height / 2 - radius
        bz = depth / 2 - radius
        px, py, pz = pos[:, 0].copy(), pos[:, 1].copy(), pos[:, 2].copy()
        sx, sy, sz = np.sign(px), np.sign(py), np.sign(pz)
        nx = px - sx * halfSegmentSize
        ny = py - sy * halfSegmentSize
        nz = pz - sz * halfSegmentSize
        nx, ny, nz = _normalize3(nx, ny, nz)
        pos[:, 0] = bx * sx + nx * radius
        pos[:, 1] = by * sy + ny * radius
        pos[:, 2] = bz * sz + nz * radius
        _f32_inplace(pos)
        nor[:, 0] = nx
        nor[:, 1] = ny
        nor[:, 2] = nz
        _f32_inplace(nor)
        n = len(px)
        faceTris = (n * 3) / 6
        side = np.floor((np.arange(n) * 3) / faceTris).astype(np.int64)
        N = (nx, ny, nz)
        AX = {'x': 0, 'y': 1, 'z': 2}

        def getUv(fd, uvAxis, projectionAxis, sideLength):
            totArcLength = 2 * math.pi * radius / 4
            centerLength = max(sideLength - 2 * radius, 0)
            halfArc = math.pi / 4
            t = [N[0].copy(), N[1].copy(), N[2].copy()]
            t[AX[projectionAxis]] = np.zeros_like(t[0])
            tx, ty, tz = _normalize3(t[0], t[1], t[2])
            arcUvRatio = 0.5 * totArcLength / (totArcLength + centerLength)
            # angleTo(faceDirVector)
            lsq = tx * tx + ty * ty + tz * tz
            fl = fd[0] * fd[0] + fd[1] * fd[1] + fd[2] * fd[2]
            den = np.sqrt(lsq * fl)
            dot = tx * fd[0] + ty * fd[1] + tz * fd[2]
            with np.errstate(divide='ignore', invalid='ignore'):
                theta = dot / den
            ang = np.where(den == 0, math.pi / 2, np.arccos(np.clip(np.where(den == 0, 0, theta), -1, 1)))
            arcAngleRatio = 1.0 - (ang / halfArc)
            comp = (tx, ty, tz)[AX[uvAxis]]
            lenUv = centerLength / (totArcLength + centerLength)
            return np.where(np.sign(comp) == 1, arcAngleRatio * arcUvRatio,
                            lenUv + arcUvRatio + arcUvRatio * (1.0 - arcAngleRatio))

        U = np.zeros(n)
        V = np.zeros(n)
        specs = [
            ((1, 0, 0), lambda: (getUv((1, 0, 0), 'z', 'y', depth), 1.0 - getUv((1, 0, 0), 'y', 'z', height))),
            ((-1, 0, 0), lambda: (1.0 - getUv((-1, 0, 0), 'z', 'y', depth), 1.0 - getUv((-1, 0, 0), 'y', 'z', height))),
            ((0, 1, 0), lambda: (1.0 - getUv((0, 1, 0), 'x', 'z', width), getUv((0, 1, 0), 'z', 'x', depth))),
            ((0, -1, 0), lambda: (1.0 - getUv((0, -1, 0), 'x', 'z', width), 1.0 - getUv((0, -1, 0), 'z', 'x', depth))),
            ((0, 0, 1), lambda: (1.0 - getUv((0, 0, 1), 'x', 'y', width), 1.0 - getUv((0, 0, 1), 'y', 'x', height))),
            ((0, 0, -1), lambda: (getUv((0, 0, -1), 'x', 'y', width), 1.0 - getUv((0, 0, -1), 'y', 'x', height))),
        ]
        for s, (_, fn) in enumerate(specs):
            m = side == s
            if m.any():
                u, vv = fn()
                U[m] = u[m]
                V[m] = vv[m]
        uvs[:, 0] = U
        uvs[:, 1] = V
        _f32_inplace(uvs)


# ============================================================================================ ConvexHull / ConvexGeometry

_Visible = 0
_Deleted = 1


class _HFace:
    __slots__ = ('normal', 'midpoint', 'area', 'constant', 'outside', 'mark', 'edge')

    def __init__(self):
        self.normal = Vector3()
        self.midpoint = Vector3()
        self.area = 0
        self.constant = 0
        self.outside = None
        self.mark = _Visible
        self.edge = None

    @staticmethod
    def create(a, b, c):
        face = _HFace()
        e0 = _HalfEdge(a, face)
        e1 = _HalfEdge(b, face)
        e2 = _HalfEdge(c, face)
        e0.next = e2.prev = e1
        e1.next = e0.prev = e2
        e2.next = e1.prev = e0
        face.edge = e0
        return face.compute()

    def getEdge(self, i):
        edge = self.edge
        while i > 0:
            edge = edge.next
            i -= 1
        while i < 0:
            edge = edge.prev
            i += 1
        return edge

    def compute(self):
        a = self.edge.tail()
        b = self.edge.head()
        c = self.edge.next.head()
        tri = Triangle(a.point, b.point, c.point)
        tri.getNormal(self.normal)
        tri.getMidpoint(self.midpoint)
        self.area = tri.getArea()
        self.constant = self.normal.dot(self.midpoint)
        return self

    def distanceToPoint(self, point):
        return self.normal.dot(point) - self.constant


class _HalfEdge:
    __slots__ = ('vertex', 'prev', 'next', 'twin', 'face')

    def __init__(self, vertex, face):
        self.vertex = vertex
        self.prev = None
        self.next = None
        self.twin = None
        self.face = face

    def head(self):
        return self.vertex

    def tail(self):
        return self.prev.vertex if self.prev else None

    def setTwin(self, edge):
        self.twin = edge
        edge.twin = self
        return self


class _VertexNode:
    __slots__ = ('point', 'prev', 'next', 'face')

    def __init__(self, point):
        self.point = point
        self.prev = None
        self.next = None
        self.face = None


class _VertexList:
    def __init__(self):
        self.head = None
        self.tail = None

    def first(self):
        return self.head

    def last(self):
        return self.tail

    def clear(self):
        self.head = self.tail = None
        return self

    def insertBefore(self, target, vertex):
        vertex.prev = target.prev
        vertex.next = target
        if vertex.prev is None:
            self.head = vertex
        else:
            vertex.prev.next = vertex
        target.prev = vertex
        return self

    def insertAfter(self, target, vertex):
        vertex.prev = target
        vertex.next = target.next
        if vertex.next is None:
            self.tail = vertex
        else:
            vertex.next.prev = vertex
        target.next = vertex
        return self

    def append(self, vertex):
        if self.head is None:
            self.head = vertex
        else:
            self.tail.next = vertex
        vertex.prev = self.tail
        vertex.next = None
        self.tail = vertex
        return self

    def appendChain(self, vertex):
        if self.head is None:
            self.head = vertex
        else:
            self.tail.next = vertex
        vertex.prev = self.tail
        while vertex.next is not None:
            vertex = vertex.next
        self.tail = vertex
        return self

    def remove(self, vertex):
        if vertex.prev is None:
            self.head = vertex.next
        else:
            vertex.prev.next = vertex.next
        if vertex.next is None:
            self.tail = vertex.prev
        else:
            vertex.next.prev = vertex.prev
        return self

    def removeSubList(self, a, b):
        if a.prev is None:
            self.head = b.next
        else:
            a.prev.next = b.next
        if b.next is None:
            self.tail = a.prev
        else:
            b.next.prev = a.prev
        return self

    def isEmpty(self):
        return self.head is None


class ConvexHull:
    """three/addons/math/ConvexHull.js (QuickHull)."""

    def __init__(self):
        self.tolerance = -1
        self.faces = []
        self.newFaces = []
        self.assigned = _VertexList()
        self.unassigned = _VertexList()
        self.vertices = []

    def setFromPoints(self, points):
        if len(points) >= 4:
            self.makeEmpty()
            for p in points:
                self.vertices.append(_VertexNode(_v3(p)))
            self._compute()
        return self

    def makeEmpty(self):
        self.faces = []
        self.vertices = []
        return self

    def containsPoint(self, point):
        for face in self.faces:
            if face.distanceToPoint(point) > self.tolerance:
                return False
        return True

    def _addVertexToFace(self, vertex, face):
        vertex.face = face
        if face.outside is None:
            self.assigned.append(vertex)
        else:
            self.assigned.insertBefore(face.outside, vertex)
        face.outside = vertex
        return self

    def _removeVertexFromFace(self, vertex, face):
        if vertex is face.outside:
            if vertex.next is not None and vertex.next.face is face:
                face.outside = vertex.next
            else:
                face.outside = None
        self.assigned.remove(vertex)
        return self

    def _removeAllVerticesFromFace(self, face):
        if face.outside is not None:
            start = face.outside
            end = face.outside
            while end.next is not None and end.next.face is face:
                end = end.next
            self.assigned.removeSubList(start, end)
            start.prev = end.next = None
            face.outside = None
            return start
        return None

    def _deleteFaceVertices(self, face, absorbingFace=None):
        faceVertices = self._removeAllVerticesFromFace(face)
        if faceVertices is not None:
            if absorbingFace is None:
                self.unassigned.appendChain(faceVertices)
            else:
                vertex = faceVertices
                while True:
                    nextVertex = vertex.next
                    distance = absorbingFace.distanceToPoint(vertex.point)
                    if distance > self.tolerance:
                        self._addVertexToFace(vertex, absorbingFace)
                    else:
                        self.unassigned.append(vertex)
                    vertex = nextVertex
                    if vertex is None:
                        break
        return self

    def _resolveUnassignedPoints(self, newFaces):
        if self.unassigned.isEmpty() is False:
            vertex = self.unassigned.first()
            while True:
                nextVertex = vertex.next
                maxDistance = self.tolerance
                maxFace = None
                for face in newFaces:
                    if face.mark == _Visible:
                        distance = face.distanceToPoint(vertex.point)
                        if distance > maxDistance:
                            maxDistance = distance
                            maxFace = face
                        if maxDistance > 1000 * self.tolerance:
                            break
                if maxFace is not None:
                    self._addVertexToFace(vertex, maxFace)
                vertex = nextVertex
                if vertex is None:
                    break
        return self

    def _computeExtremes(self):
        mn = Vector3()
        mx = Vector3()
        minVertices = [self.vertices[0]] * 3
        maxVertices = [self.vertices[0]] * 3
        mn.copy(self.vertices[0].point)
        mx.copy(self.vertices[0].point)
        for vertex in self.vertices:
            point = vertex.point
            for j in range(3):
                if point.getComponent(j) < mn.getComponent(j):
                    mn.setComponent(j, point.getComponent(j))
                    minVertices[j] = vertex
            for j in range(3):
                if point.getComponent(j) > mx.getComponent(j):
                    mx.setComponent(j, point.getComponent(j))
                    maxVertices[j] = vertex
        self.tolerance = 3 * EPSILON * (max(abs(mn.x), abs(mx.x)) + max(abs(mn.y), abs(mx.y)) +
                                        max(abs(mn.z), abs(mx.z)))
        return {'min': minVertices, 'max': maxVertices}

    def _computeInitialHull(self):
        vertices = self.vertices
        extremes = self._computeExtremes()
        mn = extremes['min']
        mx = extremes['max']
        maxDistance = 0
        index = 0
        for i in range(3):
            distance = mx[i].point.getComponent(i) - mn[i].point.getComponent(i)
            if distance > maxDistance:
                maxDistance = distance
                index = i
        v0 = mn[index]
        v1 = mx[index]
        v2 = v3 = None
        maxDistance = 0
        line3 = Line3().set(v0.point, v1.point)
        closestPoint = Vector3()
        for vertex in vertices:
            if vertex is not v0 and vertex is not v1:
                line3.closestPointToPoint(vertex.point, True, closestPoint)
                distance = closestPoint.distanceToSquared(vertex.point)
                if distance > maxDistance:
                    maxDistance = distance
                    v2 = vertex
        maxDistance = -1
        plane = Plane().setFromCoplanarPoints(v0.point, v1.point, v2.point)
        for vertex in vertices:
            if vertex is not v0 and vertex is not v1 and vertex is not v2:
                distance = abs(plane.distanceToPoint(vertex.point))
                if distance > maxDistance:
                    maxDistance = distance
                    v3 = vertex
        faces = []
        if plane.distanceToPoint(v3.point) < 0:
            faces.extend([_HFace.create(v0, v1, v2), _HFace.create(v3, v1, v0), _HFace.create(v3, v2, v1),
                          _HFace.create(v3, v0, v2)])
            for i in range(3):
                j = (i + 1) % 3
                faces[i + 1].getEdge(2).setTwin(faces[0].getEdge(j))
                faces[i + 1].getEdge(1).setTwin(faces[j + 1].getEdge(0))
        else:
            faces.extend([_HFace.create(v0, v2, v1), _HFace.create(v3, v0, v1), _HFace.create(v3, v1, v2),
                          _HFace.create(v3, v2, v0)])
            for i in range(3):
                j = (i + 1) % 3
                faces[i + 1].getEdge(2).setTwin(faces[0].getEdge((3 - i) % 3))
                faces[i + 1].getEdge(0).setTwin(faces[j + 1].getEdge(1))
        for i in range(4):
            self.faces.append(faces[i])
        for vertex in vertices:
            if vertex is not v0 and vertex is not v1 and vertex is not v2 and vertex is not v3:
                maxDistance = self.tolerance
                maxFace = None
                for j in range(4):
                    distance = self.faces[j].distanceToPoint(vertex.point)
                    if distance > maxDistance:
                        maxDistance = distance
                        maxFace = self.faces[j]
                if maxFace is not None:
                    self._addVertexToFace(vertex, maxFace)
        return self

    def _reindexFaces(self):
        self.faces = [f for f in self.faces if f.mark == _Visible]
        return self

    def _nextVertexToAdd(self):
        if self.assigned.isEmpty() is False:
            eyeVertex = None
            maxDistance = 0
            eyeFace = self.assigned.first().face
            vertex = eyeFace.outside
            while True:
                distance = eyeFace.distanceToPoint(vertex.point)
                if distance > maxDistance:
                    maxDistance = distance
                    eyeVertex = vertex
                vertex = vertex.next
                if not (vertex is not None and vertex.face is eyeFace):
                    break
            return eyeVertex
        return None

    def _computeHorizon(self, eyePoint, crossEdge, face, horizon):
        self._deleteFaceVertices(face)
        face.mark = _Deleted
        if crossEdge is None:
            edge = crossEdge = face.getEdge(0)
        else:
            edge = crossEdge.next
        while True:
            twinEdge = edge.twin
            oppositeFace = twinEdge.face
            if oppositeFace.mark == _Visible:
                if oppositeFace.distanceToPoint(eyePoint) > self.tolerance:
                    self._computeHorizon(eyePoint, twinEdge, oppositeFace, horizon)
                else:
                    horizon.append(edge)
            edge = edge.next
            if edge is crossEdge:
                break
        return self

    def _addAdjoiningFace(self, eyeVertex, horizonEdge):
        face = _HFace.create(eyeVertex, horizonEdge.tail(), horizonEdge.head())
        self.faces.append(face)
        face.getEdge(-1).setTwin(horizonEdge.twin)
        return face.getEdge(0)

    def _addNewFaces(self, eyeVertex, horizon):
        self.newFaces = []
        firstSideEdge = None
        previousSideEdge = None
        for horizonEdge in horizon:
            sideEdge = self._addAdjoiningFace(eyeVertex, horizonEdge)
            if firstSideEdge is None:
                firstSideEdge = sideEdge
            else:
                sideEdge.next.setTwin(previousSideEdge)
            self.newFaces.append(sideEdge.face)
            previousSideEdge = sideEdge
        firstSideEdge.next.setTwin(previousSideEdge)
        return self

    def _addVertexToHull(self, eyeVertex):
        horizon = []
        self.unassigned.clear()
        self._removeVertexFromFace(eyeVertex, eyeVertex.face)
        self._computeHorizon(eyeVertex.point, None, eyeVertex.face, horizon)
        self._addNewFaces(eyeVertex, horizon)
        self._resolveUnassignedPoints(self.newFaces)
        return self

    def _cleanup(self):
        self.assigned.clear()
        self.unassigned.clear()
        self.newFaces = []
        return self

    def _compute(self):
        self._computeInitialHull()
        while True:
            vertex = self._nextVertexToAdd()
            if vertex is None:
                break
            self._addVertexToHull(vertex)
        self._reindexFaces()
        self._cleanup()
        return self


class ConvexGeometry(Geometry):
    """three/addons/geometries/ConvexGeometry.js: non-indexed, flat face normals, NO uv attribute."""

    def __init__(self, points=()):
        Geometry.__init__(self)
        vertices = []
        normals = []
        convexHull = ConvexHull().setFromPoints(list(points))
        for face in convexHull.faces:
            edge = face.edge
            while True:
                point = edge.head().point
                vertices.extend((point.x, point.y, point.z))
                normals.extend((face.normal.x, face.normal.y, face.normal.z))
                edge = edge.next
                if edge is face.edge:
                    break
        self.setAttribute('position', Float32BufferAttribute(vertices, 3))
        self.setAttribute('normal', Float32BufferAttribute(normals, 3))


# ============================================================================================ BufferGeometryUtils

def mergeAttributes(attributes):
    kind = None
    itemSize = None
    normalized = None
    for a in attributes:
        k = 'i' if a.dtype.kind in 'iub' else 'f'
        if kind is None:
            kind = k
        if kind != k:
            _warn('BufferGeometryUtils: .mergeAttributes() failed. BufferAttribute.array must be of consistent '
                  'array types across matching attributes.')
            return None
        if itemSize is None:
            itemSize = a.itemSize
        if itemSize != a.itemSize:
            _warn('BufferGeometryUtils: .mergeAttributes() failed. BufferAttribute.itemSize must be consistent '
                  'across matching attributes.')
            return None
        n = getattr(a, 'normalized', False)
        if normalized is None:
            normalized = n
        if normalized != n:
            _warn('BufferGeometryUtils: .mergeAttributes() failed. BufferAttribute.normalized must be consistent '
                  'across matching attributes.')
            return None
    arr = np.concatenate([a.view(np.ndarray).reshape(-1, itemSize) for a in attributes], axis=0)
    return BufferAttribute(arr, itemSize, normalized, dtype='int' if kind == 'i' else 'float')


def mergeGeometries(geometries, useGroups=False):
    """BufferGeometryUtils.mergeGeometries: returns a new Geometry, or None (with a message) when the inputs are
    incompatible (index on some but not all, different attribute sets, ...), exactly like three."""
    isIndexed = geometries[0].index is not None
    attributesUsed = set(geometries[0].attributes.keys())
    morphAttributesUsed = set(geometries[0].morphAttributes.keys())
    attributes = {}
    morphAttributes = {}
    morphTargetsRelative = geometries[0].morphTargetsRelative
    mergedGeometry = Geometry()
    offset = 0
    for i, geometry in enumerate(geometries):
        attributesCount = 0
        if isIndexed != (geometry.index is not None):
            _warn('BufferGeometryUtils: .mergeGeometries() failed with geometry at index %d. All geometries must '
                  'have compatible attributes; make sure index attribute exists among all geometries, or in none '
                  'of them.' % i)
            return None
        for name in geometry.attributes:
            if name not in attributesUsed:
                _warn('BufferGeometryUtils: .mergeGeometries() failed with geometry at index %d. All geometries '
                      'must have compatible attributes; make sure "%s" attribute exists among all geometries, or '
                      'in none of them.' % (i, name))
                return None
            attributes.setdefault(name, []).append(geometry.attributes[name])
            attributesCount += 1
        if attributesCount != len(attributesUsed):
            _warn('BufferGeometryUtils: .mergeGeometries() failed with geometry at index %d. Make sure all '
                  'geometries have the same number of attributes.' % i)
            return None
        if morphTargetsRelative != geometry.morphTargetsRelative:
            _warn('BufferGeometryUtils: .mergeGeometries() failed with geometry at index %d. '
                  '.morphTargetsRelative must be consistent throughout all geometries.' % i)
            return None
        for name in geometry.morphAttributes:
            if name not in morphAttributesUsed:
                _warn('BufferGeometryUtils: .mergeGeometries() failed with geometry at index %d.  '
                      '.morphAttributes must be consistent throughout all geometries.' % i)
                return None
            morphAttributes.setdefault(name, []).append(geometry.morphAttributes[name])
        if useGroups:
            if isIndexed:
                count = geometry.index.count
            elif geometry.attributes.get('position') is not None:
                count = geometry.attributes.position.count
            else:
                _warn('BufferGeometryUtils: .mergeGeometries() failed with geometry at index %d. The geometry must '
                      'have either an index or a position attribute' % i)
                return None
            mergedGeometry.addGroup(offset, count, i)
            offset += count
    if isIndexed:
        indexOffset = 0
        parts = []
        for g in geometries:
            parts.append(g.index.view(np.ndarray).reshape(-1) + indexOffset)
            indexOffset += g.attributes.position.count
        mergedGeometry.setIndex(np.concatenate(parts) if parts else [])
    for name, lst in attributes.items():
        merged = mergeAttributes(lst)
        if merged is None:
            _warn('BufferGeometryUtils: .mergeGeometries() failed while trying to merge the %s attribute.' % name)
            return None
        mergedGeometry.setAttribute(name, merged)
    for name, lists in morphAttributes.items():
        numMorphTargets = len(lists[0])
        if numMorphTargets == 0:
            continue
        mergedGeometry.morphAttributes[name] = []
        for i in range(numMorphTargets):
            merged = mergeAttributes([lst[i] for lst in lists])
            if merged is None:
                _warn('BufferGeometryUtils: .mergeGeometries() failed while trying to merge the %s morphAttribute.'
                      % name)
                return None
            mergedGeometry.morphAttributes[name].append(merged)
    return mergedGeometry


def mergeVertices(geometry, tolerance=1e-4):
    """BufferGeometryUtils.mergeVertices: welds vertices whose ALL attributes hash equal (truncated at `tolerance`),
    returns an indexed clone (groups kept)."""
    tolerance = max(tolerance, EPSILON)
    indices = geometry.getIndex()
    positions = geometry.getAttribute('position')
    vertexCount = indices.count if indices is not None else positions.count
    attributeNames = list(geometry.attributes.keys())
    halfTolerance = tolerance * 0.5
    exponent = math.log10(1 / tolerance)
    hashMultiplier = math.pow(10, exponent)
    hashAdditive = halfTolerance * hashMultiplier
    order = indices.view(np.ndarray).reshape(-1) if indices is not None else np.arange(vertexCount)
    cols = []
    for name in attributeNames:
        a = geometry.attributes[name].view(np.ndarray)
        a = a.reshape(a.shape[0], -1)[order][:, :4].astype(np.float64)
        with np.errstate(invalid='ignore', over='ignore'):
            h = np.trunc(a * hashMultiplier + hashAdditive)
        cols.append(h)
    H = np.concatenate(cols, axis=1) if cols else np.zeros((vertexCount, 0))
    H = H + 0.0  # -0 -> 0 (JS `${-0}` === '0')
    hashToIndex = {}
    newIndices = np.empty(vertexCount, dtype=np.int64)
    firstSrc = []
    for i, row in enumerate(map(tuple, H.tolist())):
        j = hashToIndex.get(row)
        if j is None:
            j = len(firstSrc)
            hashToIndex[row] = j
            firstSrc.append(order[i])
        newIndices[i] = j
    firstSrc = np.asarray(firstSrc, dtype=np.int64)
    result = geometry.clone()
    for name in attributeNames:
        attr = geometry.attributes[name]
        result.setAttribute(name, BufferAttribute(attr.view(np.ndarray)[firstSrc], attr.itemSize,
                                                  getattr(attr, 'normalized', False),
                                                  dtype='int' if attr.dtype.kind in 'iub' else 'float'))
        morph = geometry.morphAttributes.get(name)
        if morph:
            result.morphAttributes[name] = [
                BufferAttribute(m.view(np.ndarray)[firstSrc], m.itemSize, getattr(m, 'normalized', False))
                for m in morph]
    result.setIndex(newIndices)
    return result


class BufferGeometryUtils:
    mergeGeometries = staticmethod(mergeGeometries)
    mergeAttributes = staticmethod(mergeAttributes)
    mergeVertices = staticmethod(mergeVertices)


# JS `undefined` -> default parameter: a None argument takes the default (ports pass opts.get('x')).
for _cls in (BoxGeometry, PlaneGeometry, CircleGeometry, RingGeometry, CylinderGeometry, ConeGeometry, SphereGeometry,
             TorusGeometry, LatheGeometry, CapsuleGeometry, PolyhedronGeometry, IcosahedronGeometry,
             OctahedronGeometry, TetrahedronGeometry, DodecahedronGeometry, TubeGeometry, ShapeGeometry,
             RoundedBoxGeometry, EllipseCurve, ArcCurve, CatmullRomCurve3):
    _cls.__init__ = js_defaults(_cls.__init__)
for _cls, _names in ((Curve, ('getPoints', 'getSpacedPoints', 'computeFrenetFrames')),
                     (CurvePath, ('getPoints', 'getSpacedPoints')),
                     (Path, ('arc', 'absarc', 'ellipse', 'absellipse'))):
    for _nm in _names:
        setattr(_cls, _nm, js_defaults(_cls.__dict__[_nm]))
mergeVertices = js_defaults(mergeVertices)
mergeGeometries = js_defaults(mergeGeometries)
BufferGeometryUtils.mergeGeometries = staticmethod(mergeGeometries)
BufferGeometryUtils.mergeVertices = staticmethod(mergeVertices)

# NOTE: no ShapePath / TorusKnot / Edges / Wireframe: the game does not use them.
