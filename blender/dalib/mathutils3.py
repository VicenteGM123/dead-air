"""three.js math in pure Python (no bpy): Vector2/3/4, Matrix3/4, Quaternion, Euler, Color, Box3, Sphere, Line3,
Plane, Triangle, MathUtils + JS-semantics helpers (Math.round, Number->string, JSON.stringify, toFixed, int32 ops).

Port of node_modules/three/src/math/*.js (r186). Method names, argument order, defaults, mutating/chaining behaviour
(`a.add(b)` mutates `a` and returns it) and the floating point operation ORDER are kept 1:1, so JS math translated
line by line gives bit-identical doubles (up to libm differences in sin/cos/pow, <= 1 ulp).

Conventions (same as three.js, see SPEC §5.2): right-handed, +Y up, front -Z, Euler default order 'XYZ',
Matrix4.elements / Matrix3.elements are COLUMN-MAJOR flat lists exactly like three.js.

Color: `Color('#hex')` stores LINEAR components (THREE.ColorManagement enabled, working space linear-sRGB);
getHex()/getHexString()/getStyle() return sRGB. `Color(r, g, b)` / setRGB take linear values (as in three r152+).

JS helpers: js_round (Math.round), js_str (String(number) / template-literal formatting), js_json
(JSON.stringify), js_to_fixed (Number.prototype.toFixed), js_keys (for..in / Object.keys order),
to_int32 / to_uint32 / imul (32-bit ops), fmod-based js_mod (JS `%`), JSObj (dict with attribute access,
missing keys read as None like JS `undefined`).
"""

import math
import random as _random
import json as _json
from decimal import Decimal, ROUND_HALF_UP

try:  # numpy is optional here (only used for __array__ conveniences)
    import numpy as _np
except Exception:  # pragma: no cover
    _np = None

__all__ = [
    'JSObj', 'js_round', 'js_str', 'js_json', 'js_to_fixed', 'js_keys', 'js_mod', 'js_sign', 'js_trunc',
    'to_int32', 'to_uint32', 'imul', 'f32', 'EPSILON', 'MAX_VALUE', 'PI',
    'MathUtils', 'DEG2RAD', 'RAD2DEG', 'clamp', 'euclideanModulo', 'mapLinear', 'inverseLerp', 'lerp', 'damp',
    'pingpong', 'smoothstep', 'smootherstep', 'randInt', 'randFloat', 'randFloatSpread', 'seededRandom',
    'degToRad', 'radToDeg', 'isPowerOfTwo', 'ceilPowerOfTwo', 'floorPowerOfTwo', 'generateUUID',
    'Vector2', 'Vector3', 'Vector4', 'Matrix3', 'Matrix4', 'Quaternion', 'Euler', 'Color', 'Box3', 'Sphere',
    'Line3', 'Plane', 'Triangle', 'ColorManagement', 'SRGBToLinear', 'LinearToSRGB',
    'SRGBColorSpace', 'LinearSRGBColorSpace',
]

PI = math.pi
EPSILON = 2.220446049250313e-16          # Number.EPSILON
MAX_VALUE = 1.7976931348623157e+308      # Number.MAX_VALUE
_INF = float('inf')


# ============================================================================================ JS semantics helpers

class JSObj(dict):
    """dict with attribute access (`o.key` == `o['key']`). Reading a missing key by attribute returns None
    (JS `undefined`), so `if not g.attributes.color:` ports 1:1. Dunder lookups still raise (copy/pickle safe)."""
    __slots__ = ()

    def __getattr__(self, k):
        if k.startswith('__'):
            raise AttributeError(k)
        return self.get(k)

    def __setattr__(self, k, v):
        self[k] = v

    def __delattr__(self, k):
        self.pop(k, None)

    def __copy__(self):
        return JSObj(self)

    def __deepcopy__(self, memo):
        import copy as _copy
        return JSObj({k: _copy.deepcopy(v, memo) for k, v in self.items()})


def to_int32(x):
    """ToInt32 (JS `x | 0`, operands of `^ & << >>`)."""
    if isinstance(x, float):
        if x != x or x in (_INF, -_INF):
            return 0
        x = int(x)  # truncates toward zero
    x = int(x) & 0xFFFFFFFF
    return x - 0x100000000 if x & 0x80000000 else x


def to_uint32(x):
    """ToUint32 (JS `x >>> 0`)."""
    if isinstance(x, float):
        if x != x or x in (_INF, -_INF):
            return 0
        x = int(x)
    return int(x) & 0xFFFFFFFF


def imul(a, b):
    """Math.imul."""
    return to_int32((to_uint32(a) * to_uint32(b)) & 0xFFFFFFFF)


def f32(x):
    """Round a double to the nearest float32 (what storing into a Float32Array does)."""
    if _np is not None:
        return float(_np.float32(x))
    import struct
    return struct.unpack('f', struct.pack('f', x))[0]


def js_round(x):
    """Math.round: nearest integer, ties toward +Infinity. Returns a Python int (float for non-finite input)."""
    x = float(x)
    if x != x or x in (_INF, -_INF):
        return x
    r = math.floor(x)
    if x - r >= 0.5:
        r += 1
    return int(r)


def js_trunc(x):
    return math.trunc(x)


def js_sign(x):
    """Math.sign (keeps -0 / +0, NaN -> NaN)."""
    if x != x:
        return x
    if x > 0:
        return 1.0
    if x < 0:
        return -1.0
    return x  # +0 / -0


def js_mod(a, b):
    """JS `%` on numbers (result has the dividend's sign), i.e. C fmod."""
    return math.fmod(a, b)


def js_str(v):
    """String(v) / `${v}` for numbers, booleans, null (None -> 'null'), strings."""
    if v is None:
        return 'null'
    if v is True:
        return 'true'
    if v is False:
        return 'false'
    if isinstance(v, str):
        return v
    if isinstance(v, int) or (_np is not None and isinstance(v, _np.integer)):
        return str(int(v))
    x = float(v)
    if x != x:
        return 'NaN'
    if x == _INF:
        return 'Infinity'
    if x == -_INF:
        return '-Infinity'
    if x == 0:
        return '0'
    if x.is_integer() and abs(x) < 1e21:
        return str(int(x))
    r = repr(x)
    sign = ''
    if r[0] == '-':
        sign, r = '-', r[1:]
    if 'e' in r:
        mant, exp = r.split('e')
        exp = int(exp)
    else:
        mant, exp = r, 0
    if '.' in mant:
        ip, fp = mant.split('.')
    else:
        ip, fp = mant, ''
    D = (ip + fp).lstrip('0')
    n = exp - len(fp) + len(D)
    s = D.rstrip('0')
    k = len(s)
    if k <= n <= 21:
        out = s + '0' * (n - k)
    elif 0 < n <= 21:
        out = s[:n] + '.' + s[n:]
    elif -6 < n <= 0:
        out = '0.' + '0' * (-n) + s
    else:
        e = n - 1
        es = ('+' if e >= 0 else '-') + str(abs(e))
        out = (s + 'e' + es) if k == 1 else (s[0] + '.' + s[1:] + 'e' + es)
    return sign + out


def js_json(v):
    """JSON.stringify (compact) with JS number formatting. Vector2/3 are NOT special-cased (like JS they are
    objects: pass [x, y] lists)."""
    if v is None:
        return 'null'
    if v is True:
        return 'true'
    if v is False:
        return 'false'
    if isinstance(v, str):
        return _json.dumps(v, ensure_ascii=False)
    if isinstance(v, (int, float)) or (_np is not None and isinstance(v, (_np.integer, _np.floating))):
        x = float(v)
        if x != x or x in (_INF, -_INF):
            return 'null'
        return js_str(v)
    if isinstance(v, dict):
        return '{' + ','.join(_json.dumps(str(k), ensure_ascii=False) + ':' + js_json(v[k]) for k in js_keys(v)) + '}'
    if isinstance(v, (list, tuple)) or (_np is not None and isinstance(v, _np.ndarray)):
        return '[' + ','.join(js_json(x) for x in v) + ']'
    if hasattr(v, 'toJSON'):
        return js_json(v.toJSON())
    raise TypeError('js_json: unsupported value %r' % (v,))


def js_to_fixed(x, digits=0):
    """Number.prototype.toFixed (round half away from zero on the exact binary value)."""
    x = float(x)
    if x != x:
        return 'NaN'
    if abs(x) >= 1e21:
        return js_str(x)
    if x == 0:
        x = 0.0
    q = Decimal(1).scaleb(-digits) if digits > 0 else Decimal(1)
    d = Decimal(x).quantize(q, rounding=ROUND_HALF_UP)
    return format(d, 'f')


def _is_index_key(k):
    if isinstance(k, bool):
        return False
    if isinstance(k, int):
        return 0 <= k < 4294967295
    if isinstance(k, str) and k.isdigit() and (k == '0' or not k.startswith('0')):
        return int(k) < 4294967295
    return False


def js_keys(obj):
    """Object.keys / for..in order: integer-like keys ascending first, then the other keys in insertion order."""
    keys = list(obj.keys())
    idx = sorted((k for k in keys if _is_index_key(k)), key=lambda k: int(k))
    return idx + [k for k in keys if not _is_index_key(k)]


# ============================================================================================ MathUtils

DEG2RAD = math.pi / 180
RAD2DEG = 180 / math.pi
_seed = [1234567]


def generateUUID():
    import uuid as _uuid
    return str(_uuid.uuid4())


def clamp(value, min_, max_):
    return max(min_, min(max_, value))


def euclideanModulo(n, m):
    return math.fmod(math.fmod(n, m) + m, m)


def mapLinear(x, a1, a2, b1, b2):
    return b1 + (x - a1) * (b2 - b1) / (a2 - a1)


def inverseLerp(x, y, value):
    if x != y:
        return (value - x) / (y - x)
    return 0


def lerp(x, y, t):
    return (1 - t) * x + t * y


def damp(x, y, lambda_, dt):
    return lerp(x, y, 1 - math.exp(-lambda_ * dt))


def pingpong(x, length=1):
    return length - abs(euclideanModulo(x, length * 2) - length)


def smoothstep(x, min_, max_):
    """THREE.MathUtils.smoothstep(x, min, max) (NOT GLSL/Godot argument order)."""
    if x <= min_:
        return 0
    if x >= max_:
        return 1
    x = (x - min_) / (max_ - min_)
    return x * x * (3 - 2 * x)


def smootherstep(x, min_, max_):
    if x <= min_:
        return 0
    if x >= max_:
        return 1
    x = (x - min_) / (max_ - min_)
    return x * x * x * (x * (x * 6 - 15) + 10)


def randInt(low, high):
    return low + math.floor(_random.random() * (high - low + 1))


def randFloat(low, high):
    return low + _random.random() * (high - low)


def randFloatSpread(range_):
    return range_ * (0.5 - _random.random())


def seededRandom(s=None):
    if s is not None:
        _seed[0] = s
    _seed[0] = _seed[0] + 0x6D2B79F5
    t = to_int32(_seed[0])
    t = imul(t ^ (to_uint32(t) >> 15), t | 1)
    t = to_int32(t ^ to_int32(t + imul(t ^ (to_uint32(t) >> 7), t | 61)))
    return to_uint32(t ^ (to_uint32(t) >> 14)) / 4294967296


def degToRad(degrees):
    return degrees * DEG2RAD


def radToDeg(radians):
    return radians * RAD2DEG


def isPowerOfTwo(value):
    return value > 0 and float(value).is_integer() and 2 ** js_round(math.log2(value)) == value


def ceilPowerOfTwo(value):
    return math.pow(2, math.ceil(math.log(value) / math.log(2)))


def floorPowerOfTwo(value):
    return math.pow(2, math.floor(math.log(value) / math.log(2)))


class MathUtils:
    DEG2RAD = DEG2RAD
    RAD2DEG = RAD2DEG
    generateUUID = staticmethod(generateUUID)
    clamp = staticmethod(clamp)
    euclideanModulo = staticmethod(euclideanModulo)
    mapLinear = staticmethod(mapLinear)
    inverseLerp = staticmethod(inverseLerp)
    lerp = staticmethod(lerp)
    damp = staticmethod(damp)
    pingpong = staticmethod(pingpong)
    smoothstep = staticmethod(smoothstep)
    smootherstep = staticmethod(smootherstep)
    randInt = staticmethod(randInt)
    randFloat = staticmethod(randFloat)
    randFloatSpread = staticmethod(randFloatSpread)
    seededRandom = staticmethod(seededRandom)
    degToRad = staticmethod(degToRad)
    radToDeg = staticmethod(radToDeg)
    isPowerOfTwo = staticmethod(isPowerOfTwo)
    ceilPowerOfTwo = staticmethod(ceilPowerOfTwo)
    floorPowerOfTwo = staticmethod(floorPowerOfTwo)


# ============================================================================================ Vector2

class Vector2:
    __slots__ = ('x', 'y')
    isVector2 = True

    def __init__(self, x=0, y=0):
        self.x = x
        self.y = y

    # -- python conveniences (not in three): iteration / indexing / numpy / repr
    def __iter__(self):
        yield self.x
        yield self.y

    def __len__(self):
        return 2

    def __getitem__(self, i):
        return (self.x, self.y)[i]

    def __array__(self, dtype=None, copy=None):
        return _np.array([self.x, self.y], dtype=dtype or float)

    def __repr__(self):
        return 'Vector2(%r, %r)' % (self.x, self.y)

    @property
    def width(self):
        return self.x

    @width.setter
    def width(self, v):
        self.x = v

    @property
    def height(self):
        return self.y

    @height.setter
    def height(self, v):
        self.y = v

    def set(self, x, y):
        self.x = x
        self.y = y
        return self

    def setScalar(self, s):
        self.x = s
        self.y = s
        return self

    def setX(self, x):
        self.x = x
        return self

    def setY(self, y):
        self.y = y
        return self

    def setComponent(self, index, value):
        if index == 0:
            self.x = value
        elif index == 1:
            self.y = value
        else:
            raise IndexError('index is out of range: %r' % index)
        return self

    def getComponent(self, index):
        if index == 0:
            return self.x
        if index == 1:
            return self.y
        raise IndexError('index is out of range: %r' % index)

    def clone(self):
        return Vector2(self.x, self.y)

    def copy(self, v):
        self.x = v.x
        self.y = v.y
        return self

    def add(self, v):
        self.x += v.x
        self.y += v.y
        return self

    def addScalar(self, s):
        self.x += s
        self.y += s
        return self

    def addVectors(self, a, b):
        self.x = a.x + b.x
        self.y = a.y + b.y
        return self

    def addScaledVector(self, v, s):
        self.x += v.x * s
        self.y += v.y * s
        return self

    def sub(self, v):
        self.x -= v.x
        self.y -= v.y
        return self

    def subScalar(self, s):
        self.x -= s
        self.y -= s
        return self

    def subVectors(self, a, b):
        self.x = a.x - b.x
        self.y = a.y - b.y
        return self

    def multiply(self, v):
        self.x *= v.x
        self.y *= v.y
        return self

    def multiplyScalar(self, scalar):
        self.x *= scalar
        self.y *= scalar
        return self

    def divide(self, v):
        self.x /= v.x
        self.y /= v.y
        return self

    def divideScalar(self, scalar):
        return self.multiplyScalar(1 / scalar if scalar != 0 else math.copysign(_INF, scalar))

    def applyMatrix3(self, m):
        x, y = self.x, self.y
        e = m.elements
        self.x = e[0] * x + e[3] * y + e[6]
        self.y = e[1] * x + e[4] * y + e[7]
        return self

    def min(self, v):
        self.x = min(self.x, v.x)
        self.y = min(self.y, v.y)
        return self

    def max(self, v):
        self.x = max(self.x, v.x)
        self.y = max(self.y, v.y)
        return self

    def clamp(self, mn, mx):
        self.x = clamp(self.x, mn.x, mx.x)
        self.y = clamp(self.y, mn.y, mx.y)
        return self

    def clampScalar(self, minVal, maxVal):
        self.x = clamp(self.x, minVal, maxVal)
        self.y = clamp(self.y, minVal, maxVal)
        return self

    def clampLength(self, mn, mx):
        length = self.length()
        return self.divideScalar(length or 1).multiplyScalar(clamp(length, mn, mx))

    def floor(self):
        self.x = math.floor(self.x)
        self.y = math.floor(self.y)
        return self

    def ceil(self):
        self.x = math.ceil(self.x)
        self.y = math.ceil(self.y)
        return self

    def round(self):
        self.x = js_round(self.x)
        self.y = js_round(self.y)
        return self

    def roundToZero(self):
        self.x = math.trunc(self.x)
        self.y = math.trunc(self.y)
        return self

    def negate(self):
        self.x = -self.x
        self.y = -self.y
        return self

    def dot(self, v):
        return self.x * v.x + self.y * v.y

    def cross(self, v):
        return self.x * v.y - self.y * v.x

    def lengthSq(self):
        return self.x * self.x + self.y * self.y

    def length(self):
        return math.sqrt(self.x * self.x + self.y * self.y)

    def manhattanLength(self):
        return abs(self.x) + abs(self.y)

    def normalize(self):
        return self.divideScalar(self.length() or 1)

    def angle(self):
        return math.atan2(-self.y, -self.x) + math.pi

    def angleTo(self, v):
        denominator = math.sqrt(self.lengthSq() * v.lengthSq())
        if denominator == 0:
            return math.pi / 2
        theta = self.dot(v) / denominator
        return math.acos(clamp(theta, -1, 1))

    def distanceTo(self, v):
        return math.sqrt(self.distanceToSquared(v))

    def distanceToSquared(self, v):
        dx = self.x - v.x
        dy = self.y - v.y
        return dx * dx + dy * dy

    def manhattanDistanceTo(self, v):
        return abs(self.x - v.x) + abs(self.y - v.y)

    def setLength(self, length):
        return self.normalize().multiplyScalar(length)

    def lerp(self, v, alpha):
        self.x += (v.x - self.x) * alpha
        self.y += (v.y - self.y) * alpha
        return self

    def lerpVectors(self, v1, v2, alpha):
        self.x = v1.x + (v2.x - v1.x) * alpha
        self.y = v1.y + (v2.y - v1.y) * alpha
        return self

    def equals(self, v):
        return v.x == self.x and v.y == self.y

    def fromArray(self, array, offset=0):
        self.x = array[offset]
        self.y = array[offset + 1]
        return self

    def toArray(self, array=None, offset=0):
        if array is None:
            array = []
        _put(array, offset, (self.x, self.y))
        return array

    def fromBufferAttribute(self, attribute, index):
        self.x = attribute.getX(index)
        self.y = attribute.getY(index)
        return self

    def rotateAround(self, center, angle):
        c = math.cos(angle)
        s = math.sin(angle)
        x = self.x - center.x
        y = self.y - center.y
        self.x = x * c - y * s + center.x
        self.y = x * s + y * c + center.y
        return self

    def random(self):
        self.x = _random.random()
        self.y = _random.random()
        return self


def _put(array, offset, values):
    for i, v in enumerate(values):
        j = offset + i
        if isinstance(array, list):
            while len(array) <= j:
                array.append(None)
        array[j] = v


# ============================================================================================ Vector3

class Vector3:
    __slots__ = ('x', 'y', 'z')
    isVector3 = True

    def __init__(self, x=0, y=0, z=0):
        self.x = x
        self.y = y
        self.z = z

    def __iter__(self):
        yield self.x
        yield self.y
        yield self.z

    def __len__(self):
        return 3

    def __getitem__(self, i):
        return (self.x, self.y, self.z)[i]

    def __array__(self, dtype=None, copy=None):
        return _np.array([self.x, self.y, self.z], dtype=dtype or float)

    def __repr__(self):
        return 'Vector3(%r, %r, %r)' % (self.x, self.y, self.z)

    def set(self, x, y, z=None):
        if z is None:
            z = self.z  # sprite.scale.set(x, y)
        self.x = x
        self.y = y
        self.z = z
        return self

    def setScalar(self, scalar):
        self.x = scalar
        self.y = scalar
        self.z = scalar
        return self

    def setX(self, x):
        self.x = x
        return self

    def setY(self, y):
        self.y = y
        return self

    def setZ(self, z):
        self.z = z
        return self

    def setComponent(self, index, value):
        if index == 0:
            self.x = value
        elif index == 1:
            self.y = value
        elif index == 2:
            self.z = value
        else:
            raise IndexError('index is out of range: %r' % index)
        return self

    def getComponent(self, index):
        if index == 0:
            return self.x
        if index == 1:
            return self.y
        if index == 2:
            return self.z
        raise IndexError('index is out of range: %r' % index)

    def clone(self):
        return Vector3(self.x, self.y, self.z)

    def copy(self, v):
        self.x = v.x
        self.y = v.y
        self.z = v.z
        return self

    def add(self, v):
        self.x += v.x
        self.y += v.y
        self.z += v.z
        return self

    def addScalar(self, s):
        self.x += s
        self.y += s
        self.z += s
        return self

    def addVectors(self, a, b):
        self.x = a.x + b.x
        self.y = a.y + b.y
        self.z = a.z + b.z
        return self

    def addScaledVector(self, v, s):
        self.x += v.x * s
        self.y += v.y * s
        self.z += v.z * s
        return self

    def sub(self, v):
        self.x -= v.x
        self.y -= v.y
        self.z -= v.z
        return self

    def subScalar(self, s):
        self.x -= s
        self.y -= s
        self.z -= s
        return self

    def subVectors(self, a, b):
        self.x = a.x - b.x
        self.y = a.y - b.y
        self.z = a.z - b.z
        return self

    def multiply(self, v):
        self.x *= v.x
        self.y *= v.y
        self.z *= v.z
        return self

    def multiplyScalar(self, scalar):
        self.x *= scalar
        self.y *= scalar
        self.z *= scalar
        return self

    def multiplyVectors(self, a, b):
        self.x = a.x * b.x
        self.y = a.y * b.y
        self.z = a.z * b.z
        return self

    def applyEuler(self, euler):
        return self.applyQuaternion(Quaternion().setFromEuler(euler))

    def applyAxisAngle(self, axis, angle):
        return self.applyQuaternion(Quaternion().setFromAxisAngle(axis, angle))

    def applyMatrix3(self, m):
        x, y, z = self.x, self.y, self.z
        e = m.elements
        self.x = e[0] * x + e[3] * y + e[6] * z
        self.y = e[1] * x + e[4] * y + e[7] * z
        self.z = e[2] * x + e[5] * y + e[8] * z
        return self

    def applyNormalMatrix(self, m):
        return self.applyMatrix3(m).normalize()

    def applyMatrix4(self, m):
        x, y, z = self.x, self.y, self.z
        e = m.elements
        w = 1 / (e[3] * x + e[7] * y + e[11] * z + e[15])
        self.x = (e[0] * x + e[4] * y + e[8] * z + e[12]) * w
        self.y = (e[1] * x + e[5] * y + e[9] * z + e[13]) * w
        self.z = (e[2] * x + e[6] * y + e[10] * z + e[14]) * w
        return self

    def applyQuaternion(self, q):
        vx, vy, vz = self.x, self.y, self.z
        qx, qy, qz, qw = q.x, q.y, q.z, q.w
        tx = 2 * (qy * vz - qz * vy)
        ty = 2 * (qz * vx - qx * vz)
        tz = 2 * (qx * vy - qy * vx)
        self.x = vx + qw * tx + qy * tz - qz * ty
        self.y = vy + qw * ty + qz * tx - qx * tz
        self.z = vz + qw * tz + qx * ty - qy * tx
        return self

    def transformDirection(self, m):
        x, y, z = self.x, self.y, self.z
        e = m.elements
        self.x = e[0] * x + e[4] * y + e[8] * z
        self.y = e[1] * x + e[5] * y + e[9] * z
        self.z = e[2] * x + e[6] * y + e[10] * z
        return self.normalize()

    def divide(self, v):
        self.x /= v.x
        self.y /= v.y
        self.z /= v.z
        return self

    def divideScalar(self, scalar):
        return self.multiplyScalar(1 / scalar if scalar != 0 else math.copysign(_INF, scalar))

    def min(self, v):
        self.x = min(self.x, v.x)
        self.y = min(self.y, v.y)
        self.z = min(self.z, v.z)
        return self

    def max(self, v):
        self.x = max(self.x, v.x)
        self.y = max(self.y, v.y)
        self.z = max(self.z, v.z)
        return self

    def clamp(self, mn, mx):
        self.x = clamp(self.x, mn.x, mx.x)
        self.y = clamp(self.y, mn.y, mx.y)
        self.z = clamp(self.z, mn.z, mx.z)
        return self

    def clampScalar(self, minVal, maxVal):
        self.x = clamp(self.x, minVal, maxVal)
        self.y = clamp(self.y, minVal, maxVal)
        self.z = clamp(self.z, minVal, maxVal)
        return self

    def clampLength(self, mn, mx):
        length = self.length()
        return self.divideScalar(length or 1).multiplyScalar(clamp(length, mn, mx))

    def floor(self):
        self.x = math.floor(self.x)
        self.y = math.floor(self.y)
        self.z = math.floor(self.z)
        return self

    def ceil(self):
        self.x = math.ceil(self.x)
        self.y = math.ceil(self.y)
        self.z = math.ceil(self.z)
        return self

    def round(self):
        self.x = js_round(self.x)
        self.y = js_round(self.y)
        self.z = js_round(self.z)
        return self

    def roundToZero(self):
        self.x = math.trunc(self.x)
        self.y = math.trunc(self.y)
        self.z = math.trunc(self.z)
        return self

    def negate(self):
        self.x = -self.x
        self.y = -self.y
        self.z = -self.z
        return self

    def dot(self, v):
        return self.x * v.x + self.y * v.y + self.z * v.z

    def lengthSq(self):
        return self.x * self.x + self.y * self.y + self.z * self.z

    def length(self):
        return math.sqrt(self.x * self.x + self.y * self.y + self.z * self.z)

    def manhattanLength(self):
        return abs(self.x) + abs(self.y) + abs(self.z)

    def normalize(self):
        return self.divideScalar(self.length() or 1)

    def setLength(self, length):
        return self.normalize().multiplyScalar(length)

    def lerp(self, v, alpha):
        self.x += (v.x - self.x) * alpha
        self.y += (v.y - self.y) * alpha
        self.z += (v.z - self.z) * alpha
        return self

    def lerpVectors(self, v1, v2, alpha):
        self.x = v1.x + (v2.x - v1.x) * alpha
        self.y = v1.y + (v2.y - v1.y) * alpha
        self.z = v1.z + (v2.z - v1.z) * alpha
        return self

    def cross(self, v):
        return self.crossVectors(self, v)

    def crossVectors(self, a, b):
        ax, ay, az = a.x, a.y, a.z
        bx, by, bz = b.x, b.y, b.z
        self.x = ay * bz - az * by
        self.y = az * bx - ax * bz
        self.z = ax * by - ay * bx
        return self

    def projectOnVector(self, v):
        denominator = v.lengthSq()
        if denominator == 0:
            return self.set(0, 0, 0)
        scalar = v.dot(self) / denominator
        return self.copy(v).multiplyScalar(scalar)

    def projectOnPlane(self, planeNormal):
        _v = Vector3().copy(self).projectOnVector(planeNormal)
        return self.sub(_v)

    def reflect(self, normal):
        return self.sub(Vector3().copy(normal).multiplyScalar(2 * self.dot(normal)))

    def angleTo(self, v):
        denominator = math.sqrt(self.lengthSq() * v.lengthSq())
        if denominator == 0:
            return math.pi / 2
        theta = self.dot(v) / denominator
        return math.acos(clamp(theta, -1, 1))

    def distanceTo(self, v):
        return math.sqrt(self.distanceToSquared(v))

    def distanceToSquared(self, v):
        dx = self.x - v.x
        dy = self.y - v.y
        dz = self.z - v.z
        return dx * dx + dy * dy + dz * dz

    def manhattanDistanceTo(self, v):
        return abs(self.x - v.x) + abs(self.y - v.y) + abs(self.z - v.z)

    def setFromSpherical(self, s):
        return self.setFromSphericalCoords(s.radius, s.phi, s.theta)

    def setFromSphericalCoords(self, radius, phi, theta):
        sinPhiRadius = math.sin(phi) * radius
        self.x = sinPhiRadius * math.sin(theta)
        self.y = math.cos(phi) * radius
        self.z = sinPhiRadius * math.cos(theta)
        return self

    def setFromCylindricalCoords(self, radius, theta, y):
        self.x = radius * math.sin(theta)
        self.y = y
        self.z = radius * math.cos(theta)
        return self

    def setFromMatrixPosition(self, m):
        e = m.elements
        self.x = e[12]
        self.y = e[13]
        self.z = e[14]
        return self

    def setFromMatrixScale(self, m):
        sx = self.setFromMatrixColumn(m, 0).length()
        sy = self.setFromMatrixColumn(m, 1).length()
        sz = self.setFromMatrixColumn(m, 2).length()
        self.x = sx
        self.y = sy
        self.z = sz
        return self

    def setFromMatrixColumn(self, m, index):
        return self.fromArray(m.elements, index * 4)

    def setFromMatrix3Column(self, m, index):
        return self.fromArray(m.elements, index * 3)

    def setFromEuler(self, e):
        self.x = e._x
        self.y = e._y
        self.z = e._z
        return self

    def setFromColor(self, c):
        self.x = c.r
        self.y = c.g
        self.z = c.b
        return self

    def equals(self, v):
        return v.x == self.x and v.y == self.y and v.z == self.z

    def fromArray(self, array, offset=0):
        self.x = array[offset]
        self.y = array[offset + 1]
        self.z = array[offset + 2]
        return self

    def toArray(self, array=None, offset=0):
        if array is None:
            array = []
        _put(array, offset, (self.x, self.y, self.z))
        return array

    def fromBufferAttribute(self, attribute, index):
        self.x = attribute.getX(index)
        self.y = attribute.getY(index)
        self.z = attribute.getZ(index)
        return self

    def random(self):
        self.x = _random.random()
        self.y = _random.random()
        self.z = _random.random()
        return self

    def randomDirection(self):
        theta = _random.random() * math.pi * 2
        u = _random.random() * 2 - 1
        c = math.sqrt(1 - u * u)
        self.x = c * math.cos(theta)
        self.y = u
        self.z = c * math.sin(theta)
        return self


# ============================================================================================ Vector4

class Vector4:
    __slots__ = ('x', 'y', 'z', 'w')
    isVector4 = True

    def __init__(self, x=0, y=0, z=0, w=1):
        self.x = x
        self.y = y
        self.z = z
        self.w = w

    def __iter__(self):
        yield self.x
        yield self.y
        yield self.z
        yield self.w

    def __len__(self):
        return 4

    def __getitem__(self, i):
        return (self.x, self.y, self.z, self.w)[i]

    def __array__(self, dtype=None, copy=None):
        return _np.array([self.x, self.y, self.z, self.w], dtype=dtype or float)

    def __repr__(self):
        return 'Vector4(%r, %r, %r, %r)' % (self.x, self.y, self.z, self.w)

    def set(self, x, y, z, w):
        self.x, self.y, self.z, self.w = x, y, z, w
        return self

    def setScalar(self, s):
        self.x = self.y = self.z = self.w = s
        return self

    def clone(self):
        return Vector4(self.x, self.y, self.z, self.w)

    def copy(self, v):
        self.x, self.y, self.z = v.x, v.y, v.z
        self.w = v.w if getattr(v, 'w', None) is not None else 1
        return self

    def add(self, v):
        self.x += v.x
        self.y += v.y
        self.z += v.z
        self.w += v.w
        return self

    def sub(self, v):
        self.x -= v.x
        self.y -= v.y
        self.z -= v.z
        self.w -= v.w
        return self

    def multiplyScalar(self, s):
        self.x *= s
        self.y *= s
        self.z *= s
        self.w *= s
        return self

    def divideScalar(self, s):
        return self.multiplyScalar(1 / s)

    def applyMatrix4(self, m):
        x, y, z, w = self.x, self.y, self.z, self.w
        e = m.elements
        self.x = e[0] * x + e[4] * y + e[8] * z + e[12] * w
        self.y = e[1] * x + e[5] * y + e[9] * z + e[13] * w
        self.z = e[2] * x + e[6] * y + e[10] * z + e[14] * w
        self.w = e[3] * x + e[7] * y + e[11] * z + e[15] * w
        return self

    def dot(self, v):
        return self.x * v.x + self.y * v.y + self.z * v.z + self.w * v.w

    def lengthSq(self):
        return self.x * self.x + self.y * self.y + self.z * self.z + self.w * self.w

    def length(self):
        return math.sqrt(self.lengthSq())

    def normalize(self):
        return self.divideScalar(self.length() or 1)

    def lerp(self, v, alpha):
        self.x += (v.x - self.x) * alpha
        self.y += (v.y - self.y) * alpha
        self.z += (v.z - self.z) * alpha
        self.w += (v.w - self.w) * alpha
        return self

    def equals(self, v):
        return v.x == self.x and v.y == self.y and v.z == self.z and v.w == self.w

    def fromArray(self, array, offset=0):
        self.x, self.y, self.z, self.w = array[offset], array[offset + 1], array[offset + 2], array[offset + 3]
        return self

    def toArray(self, array=None, offset=0):
        if array is None:
            array = []
        _put(array, offset, (self.x, self.y, self.z, self.w))
        return array

    def fromBufferAttribute(self, attribute, index):
        self.x = attribute.getX(index)
        self.y = attribute.getY(index)
        self.z = attribute.getZ(index)
        self.w = attribute.getW(index)
        return self


# ============================================================================================ Matrix3

class Matrix3:
    isMatrix3 = True

    def __init__(self, *args):
        self.elements = [1.0, 0, 0, 0, 1.0, 0, 0, 0, 1.0]
        if args:
            self.set(*args)

    def __repr__(self):
        return 'Matrix3(%r)' % (self.elements,)

    def set(self, n11, n12, n13, n21, n22, n23, n31, n32, n33):
        te = self.elements
        te[0] = n11; te[1] = n21; te[2] = n31
        te[3] = n12; te[4] = n22; te[5] = n32
        te[6] = n13; te[7] = n23; te[8] = n33
        return self

    def identity(self):
        return self.set(1, 0, 0, 0, 1, 0, 0, 0, 1)

    def clone(self):
        return Matrix3().fromArray(self.elements)

    def copy(self, m):
        self.elements[:] = m.elements[:9]
        return self

    def fromArray(self, array, offset=0):
        for i in range(9):
            self.elements[i] = array[i + offset]
        return self

    def toArray(self, array=None, offset=0):
        if array is None:
            array = []
        _put(array, offset, self.elements)
        return array

    def extractBasis(self, xAxis, yAxis, zAxis):
        xAxis.setFromMatrix3Column(self, 0)
        yAxis.setFromMatrix3Column(self, 1)
        zAxis.setFromMatrix3Column(self, 2)
        return self

    def setFromMatrix4(self, m):
        me = m.elements
        return self.set(me[0], me[4], me[8], me[1], me[5], me[9], me[2], me[6], me[10])

    def multiply(self, m):
        return self.multiplyMatrices(self, m)

    def premultiply(self, m):
        return self.multiplyMatrices(m, self)

    def multiplyMatrices(self, a, b):
        ae = a.elements
        be = b.elements
        te = self.elements
        a11, a12, a13 = ae[0], ae[3], ae[6]
        a21, a22, a23 = ae[1], ae[4], ae[7]
        a31, a32, a33 = ae[2], ae[5], ae[8]
        b11, b12, b13 = be[0], be[3], be[6]
        b21, b22, b23 = be[1], be[4], be[7]
        b31, b32, b33 = be[2], be[5], be[8]
        te[0] = a11 * b11 + a12 * b21 + a13 * b31
        te[3] = a11 * b12 + a12 * b22 + a13 * b32
        te[6] = a11 * b13 + a12 * b23 + a13 * b33
        te[1] = a21 * b11 + a22 * b21 + a23 * b31
        te[4] = a21 * b12 + a22 * b22 + a23 * b32
        te[7] = a21 * b13 + a22 * b23 + a23 * b33
        te[2] = a31 * b11 + a32 * b21 + a33 * b31
        te[5] = a31 * b12 + a32 * b22 + a33 * b32
        te[8] = a31 * b13 + a32 * b23 + a33 * b33
        return self

    def multiplyScalar(self, s):
        te = self.elements
        for i in range(9):
            te[i] *= s
        return self

    def determinant(self):
        te = self.elements
        a, b, c, d, e, f, g, h, i = te
        return a * e * i - a * f * h - b * d * i + b * f * g + c * d * h - c * e * g

    def invert(self):
        te = self.elements
        n11, n21, n31 = te[0], te[1], te[2]
        n12, n22, n32 = te[3], te[4], te[5]
        n13, n23, n33 = te[6], te[7], te[8]
        t11 = n33 * n22 - n32 * n23
        t12 = n32 * n13 - n33 * n12
        t13 = n23 * n12 - n22 * n13
        det = n11 * t11 + n21 * t12 + n31 * t13
        if det == 0:
            return self.set(0, 0, 0, 0, 0, 0, 0, 0, 0)
        detInv = 1 / det
        te[0] = t11 * detInv
        te[1] = (n31 * n23 - n33 * n21) * detInv
        te[2] = (n32 * n21 - n31 * n22) * detInv
        te[3] = t12 * detInv
        te[4] = (n33 * n11 - n31 * n13) * detInv
        te[5] = (n31 * n12 - n32 * n11) * detInv
        te[6] = t13 * detInv
        te[7] = (n21 * n13 - n23 * n11) * detInv
        te[8] = (n22 * n11 - n21 * n12) * detInv
        return self

    def transpose(self):
        m = self.elements
        m[1], m[3] = m[3], m[1]
        m[2], m[6] = m[6], m[2]
        m[5], m[7] = m[7], m[5]
        return self

    def getNormalMatrix(self, matrix4):
        return self.setFromMatrix4(matrix4).invert().transpose()

    def transposeIntoArray(self, r):
        m = self.elements
        r[0] = m[0]; r[1] = m[3]; r[2] = m[6]
        r[3] = m[1]; r[4] = m[4]; r[5] = m[7]
        r[6] = m[2]; r[7] = m[5]; r[8] = m[8]
        return self

    def setUvTransform(self, tx, ty, sx, sy, rotation, cx, cy):
        c = math.cos(rotation)
        s = math.sin(rotation)
        return self.set(sx * c, sx * s, -sx * (c * cx + s * cy) + cx + tx,
                        -sy * s, sy * c, -sy * (-s * cx + c * cy) + cy + ty,
                        0, 0, 1)

    def makeTranslation(self, x, y=None):
        if getattr(x, 'isVector2', False):
            return self.set(1, 0, x.x, 0, 1, x.y, 0, 0, 1)
        return self.set(1, 0, x, 0, 1, y, 0, 0, 1)

    def makeRotation(self, theta):
        c = math.cos(theta)
        s = math.sin(theta)
        return self.set(c, -s, 0, s, c, 0, 0, 0, 1)

    def makeScale(self, x, y):
        return self.set(x, 0, 0, 0, y, 0, 0, 0, 1)

    def equals(self, m):
        return all(a == b for a, b in zip(self.elements, m.elements))


# ============================================================================================ Matrix4

class Matrix4:
    isMatrix4 = True

    def __init__(self, *args):
        self.elements = [1.0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, 1.0]
        if args:
            self.set(*args)

    def __repr__(self):
        return 'Matrix4(%r)' % (self.elements,)

    def to_numpy(self):
        """4x4 row-major numpy array (python convenience; M @ [x,y,z,1])."""
        return _np.array(self.elements, dtype=float).reshape(4, 4).T.copy()

    def set(self, n11, n12, n13, n14, n21, n22, n23, n24, n31, n32, n33, n34, n41, n42, n43, n44):
        te = self.elements
        te[0] = n11; te[4] = n12; te[8] = n13; te[12] = n14
        te[1] = n21; te[5] = n22; te[9] = n23; te[13] = n24
        te[2] = n31; te[6] = n32; te[10] = n33; te[14] = n34
        te[3] = n41; te[7] = n42; te[11] = n43; te[15] = n44
        return self

    def identity(self):
        return self.set(1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)

    def clone(self):
        return Matrix4().fromArray(self.elements)

    def copy(self, m):
        self.elements[:] = m.elements[:16]
        return self

    def copyPosition(self, m):
        te, me = self.elements, m.elements
        te[12] = me[12]
        te[13] = me[13]
        te[14] = me[14]
        return self

    def setFromMatrix3(self, m):
        me = m.elements
        return self.set(me[0], me[3], me[6], 0, me[1], me[4], me[7], 0, me[2], me[5], me[8], 0, 0, 0, 0, 1)

    def extractBasis(self, xAxis, yAxis, zAxis):
        if self.determinantAffine() == 0:
            xAxis.set(1, 0, 0)
            yAxis.set(0, 1, 0)
            zAxis.set(0, 0, 1)
            return self
        xAxis.setFromMatrixColumn(self, 0)
        yAxis.setFromMatrixColumn(self, 1)
        zAxis.setFromMatrixColumn(self, 2)
        return self

    def makeBasis(self, xAxis, yAxis, zAxis):
        return self.set(xAxis.x, yAxis.x, zAxis.x, 0,
                        xAxis.y, yAxis.y, zAxis.y, 0,
                        xAxis.z, yAxis.z, zAxis.z, 0,
                        0, 0, 0, 1)

    def extractRotation(self, m):
        if m.determinantAffine() == 0:
            return self.identity()
        te = self.elements
        me = m.elements
        _v = Vector3()
        scaleX = 1 / _v.setFromMatrixColumn(m, 0).length()
        scaleY = 1 / _v.setFromMatrixColumn(m, 1).length()
        scaleZ = 1 / _v.setFromMatrixColumn(m, 2).length()
        te[0] = me[0] * scaleX; te[1] = me[1] * scaleX; te[2] = me[2] * scaleX; te[3] = 0
        te[4] = me[4] * scaleY; te[5] = me[5] * scaleY; te[6] = me[6] * scaleY; te[7] = 0
        te[8] = me[8] * scaleZ; te[9] = me[9] * scaleZ; te[10] = me[10] * scaleZ; te[11] = 0
        te[12] = 0; te[13] = 0; te[14] = 0; te[15] = 1
        return self

    def makeRotationFromEuler(self, euler):
        te = self.elements
        x, y, z = euler.x, euler.y, euler.z
        a, b = math.cos(x), math.sin(x)
        c, d = math.cos(y), math.sin(y)
        e, f = math.cos(z), math.sin(z)
        order = euler.order
        if order == 'XYZ':
            ae, af, be, bf = a * e, a * f, b * e, b * f
            te[0] = c * e; te[4] = -c * f; te[8] = d
            te[1] = af + be * d; te[5] = ae - bf * d; te[9] = -b * c
            te[2] = bf - ae * d; te[6] = be + af * d; te[10] = a * c
        elif order == 'YXZ':
            ce, cf, de, df = c * e, c * f, d * e, d * f
            te[0] = ce + df * b; te[4] = de * b - cf; te[8] = a * d
            te[1] = a * f; te[5] = a * e; te[9] = -b
            te[2] = cf * b - de; te[6] = df + ce * b; te[10] = a * c
        elif order == 'ZXY':
            ce, cf, de, df = c * e, c * f, d * e, d * f
            te[0] = ce - df * b; te[4] = -a * f; te[8] = de + cf * b
            te[1] = cf + de * b; te[5] = a * e; te[9] = df - ce * b
            te[2] = -a * d; te[6] = b; te[10] = a * c
        elif order == 'ZYX':
            ae, af, be, bf = a * e, a * f, b * e, b * f
            te[0] = c * e; te[4] = be * d - af; te[8] = ae * d + bf
            te[1] = c * f; te[5] = bf * d + ae; te[9] = af * d - be
            te[2] = -d; te[6] = b * c; te[10] = a * c
        elif order == 'YZX':
            ac, ad, bc, bd = a * c, a * d, b * c, b * d
            te[0] = c * e; te[4] = bd - ac * f; te[8] = bc * f + ad
            te[1] = f; te[5] = a * e; te[9] = -b * e
            te[2] = -d * e; te[6] = ad * f + bc; te[10] = ac - bd * f
        elif order == 'XZY':
            ac, ad, bc, bd = a * c, a * d, b * c, b * d
            te[0] = c * e; te[4] = -f; te[8] = d * e
            te[1] = ac * f + bd; te[5] = a * e; te[9] = ad * f - bc
            te[2] = bc * f - ad; te[6] = b * e; te[10] = bd * f + ac
        te[3] = 0; te[7] = 0; te[11] = 0
        te[12] = 0; te[13] = 0; te[14] = 0; te[15] = 1
        return self

    def makeRotationFromQuaternion(self, q):
        return self.compose(Vector3(0, 0, 0), q, Vector3(1, 1, 1))

    def lookAt(self, eye, target, up):
        te = self.elements
        _z = Vector3().subVectors(eye, target)
        if _z.lengthSq() == 0:
            _z.z = 1
        _z.normalize()
        _x = Vector3().crossVectors(up, _z)
        if _x.lengthSq() == 0:
            if abs(up.z) == 1:
                _z.x += 0.0001
            else:
                _z.z += 0.0001
            _z.normalize()
            _x.crossVectors(up, _z)
        _x.normalize()
        _y = Vector3().crossVectors(_z, _x)
        te[0] = _x.x; te[4] = _y.x; te[8] = _z.x
        te[1] = _x.y; te[5] = _y.y; te[9] = _z.y
        te[2] = _x.z; te[6] = _y.z; te[10] = _z.z
        return self

    def multiply(self, m):
        return self.multiplyMatrices(self, m)

    def premultiply(self, m):
        return self.multiplyMatrices(m, self)

    def multiplyMatrices(self, a, b):
        ae = a.elements
        be = b.elements
        te = self.elements
        a11, a12, a13, a14 = ae[0], ae[4], ae[8], ae[12]
        a21, a22, a23, a24 = ae[1], ae[5], ae[9], ae[13]
        a31, a32, a33, a34 = ae[2], ae[6], ae[10], ae[14]
        a41, a42, a43, a44 = ae[3], ae[7], ae[11], ae[15]
        b11, b12, b13, b14 = be[0], be[4], be[8], be[12]
        b21, b22, b23, b24 = be[1], be[5], be[9], be[13]
        b31, b32, b33, b34 = be[2], be[6], be[10], be[14]
        b41, b42, b43, b44 = be[3], be[7], be[11], be[15]
        te[0] = a11 * b11 + a12 * b21 + a13 * b31 + a14 * b41
        te[4] = a11 * b12 + a12 * b22 + a13 * b32 + a14 * b42
        te[8] = a11 * b13 + a12 * b23 + a13 * b33 + a14 * b43
        te[12] = a11 * b14 + a12 * b24 + a13 * b34 + a14 * b44
        te[1] = a21 * b11 + a22 * b21 + a23 * b31 + a24 * b41
        te[5] = a21 * b12 + a22 * b22 + a23 * b32 + a24 * b42
        te[9] = a21 * b13 + a22 * b23 + a23 * b33 + a24 * b43
        te[13] = a21 * b14 + a22 * b24 + a23 * b34 + a24 * b44
        te[2] = a31 * b11 + a32 * b21 + a33 * b31 + a34 * b41
        te[6] = a31 * b12 + a32 * b22 + a33 * b32 + a34 * b42
        te[10] = a31 * b13 + a32 * b23 + a33 * b33 + a34 * b43
        te[14] = a31 * b14 + a32 * b24 + a33 * b34 + a34 * b44
        te[3] = a41 * b11 + a42 * b21 + a43 * b31 + a44 * b41
        te[7] = a41 * b12 + a42 * b22 + a43 * b32 + a44 * b42
        te[11] = a41 * b13 + a42 * b23 + a43 * b33 + a44 * b43
        te[15] = a41 * b14 + a42 * b24 + a43 * b34 + a44 * b44
        return self

    def multiplyScalar(self, s):
        te = self.elements
        for i in range(16):
            te[i] *= s
        return self

    def determinant(self):
        te = self.elements
        n11, n12, n13, n14 = te[0], te[4], te[8], te[12]
        n21, n22, n23, n24 = te[1], te[5], te[9], te[13]
        n31, n32, n33, n34 = te[2], te[6], te[10], te[14]
        n41, n42, n43, n44 = te[3], te[7], te[11], te[15]
        t11 = n23 * n34 - n24 * n33
        t12 = n22 * n34 - n24 * n32
        t13 = n22 * n33 - n23 * n32
        t21 = n21 * n34 - n24 * n31
        t22 = n21 * n33 - n23 * n31
        t23 = n21 * n32 - n22 * n31
        return (n11 * (n42 * t11 - n43 * t12 + n44 * t13) -
                n12 * (n41 * t11 - n43 * t21 + n44 * t22) +
                n13 * (n41 * t12 - n42 * t21 + n44 * t23) -
                n14 * (n41 * t13 - n42 * t22 + n43 * t23))

    def determinantAffine(self):
        te = self.elements
        n11, n12, n13 = te[0], te[4], te[8]
        n21, n22, n23 = te[1], te[5], te[9]
        n31, n32, n33 = te[2], te[6], te[10]
        return (n11 * (n22 * n33 - n23 * n32) -
                n12 * (n21 * n33 - n23 * n31) +
                n13 * (n21 * n32 - n22 * n31))

    def transpose(self):
        te = self.elements
        te[1], te[4] = te[4], te[1]
        te[2], te[8] = te[8], te[2]
        te[6], te[9] = te[9], te[6]
        te[3], te[12] = te[12], te[3]
        te[7], te[13] = te[13], te[7]
        te[11], te[14] = te[14], te[11]
        return self

    def setPosition(self, x, y=None, z=None):
        te = self.elements
        if getattr(x, 'isVector3', False):
            te[12] = x.x; te[13] = x.y; te[14] = x.z
        else:
            te[12] = x; te[13] = y; te[14] = z
        return self

    def invert(self):
        te = self.elements
        n11, n21, n31, n41 = te[0], te[1], te[2], te[3]
        n12, n22, n32, n42 = te[4], te[5], te[6], te[7]
        n13, n23, n33, n43 = te[8], te[9], te[10], te[11]
        n14, n24, n34, n44 = te[12], te[13], te[14], te[15]
        t1 = n11 * n22 - n21 * n12
        t2 = n11 * n32 - n31 * n12
        t3 = n11 * n42 - n41 * n12
        t4 = n21 * n32 - n31 * n22
        t5 = n21 * n42 - n41 * n22
        t6 = n31 * n42 - n41 * n32
        t7 = n13 * n24 - n23 * n14
        t8 = n13 * n34 - n33 * n14
        t9 = n13 * n44 - n43 * n14
        t10 = n23 * n34 - n33 * n24
        t11 = n23 * n44 - n43 * n24
        t12 = n33 * n44 - n43 * n34
        det = t1 * t12 - t2 * t11 + t3 * t10 + t4 * t9 - t5 * t8 + t6 * t7
        if det == 0:
            return self.set(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        detInv = 1 / det
        te[0] = (n22 * t12 - n32 * t11 + n42 * t10) * detInv
        te[1] = (n31 * t11 - n21 * t12 - n41 * t10) * detInv
        te[2] = (n24 * t6 - n34 * t5 + n44 * t4) * detInv
        te[3] = (n33 * t5 - n23 * t6 - n43 * t4) * detInv
        te[4] = (n32 * t9 - n12 * t12 - n42 * t8) * detInv
        te[5] = (n11 * t12 - n31 * t9 + n41 * t8) * detInv
        te[6] = (n34 * t3 - n14 * t6 - n44 * t2) * detInv
        te[7] = (n13 * t6 - n33 * t3 + n43 * t2) * detInv
        te[8] = (n12 * t11 - n22 * t9 + n42 * t7) * detInv
        te[9] = (n21 * t9 - n11 * t11 - n41 * t7) * detInv
        te[10] = (n14 * t5 - n24 * t3 + n44 * t1) * detInv
        te[11] = (n23 * t3 - n13 * t5 - n43 * t1) * detInv
        te[12] = (n22 * t8 - n12 * t10 - n32 * t7) * detInv
        te[13] = (n11 * t10 - n21 * t8 + n31 * t7) * detInv
        te[14] = (n24 * t2 - n14 * t4 - n34 * t1) * detInv
        te[15] = (n13 * t4 - n23 * t2 + n33 * t1) * detInv
        return self

    def scale(self, v):
        te = self.elements
        x, y, z = v.x, v.y, v.z
        te[0] *= x; te[4] *= y; te[8] *= z
        te[1] *= x; te[5] *= y; te[9] *= z
        te[2] *= x; te[6] *= y; te[10] *= z
        te[3] *= x; te[7] *= y; te[11] *= z
        return self

    def getMaxScaleOnAxis(self):
        te = self.elements
        scaleXSq = te[0] * te[0] + te[1] * te[1] + te[2] * te[2]
        scaleYSq = te[4] * te[4] + te[5] * te[5] + te[6] * te[6]
        scaleZSq = te[8] * te[8] + te[9] * te[9] + te[10] * te[10]
        return math.sqrt(max(scaleXSq, scaleYSq, scaleZSq))

    def makeTranslation(self, x, y=None, z=None):
        if getattr(x, 'isVector3', False):
            return self.set(1, 0, 0, x.x, 0, 1, 0, x.y, 0, 0, 1, x.z, 0, 0, 0, 1)
        return self.set(1, 0, 0, x, 0, 1, 0, y, 0, 0, 1, z, 0, 0, 0, 1)

    def makeRotationX(self, theta):
        c, s = math.cos(theta), math.sin(theta)
        return self.set(1, 0, 0, 0, 0, c, -s, 0, 0, s, c, 0, 0, 0, 0, 1)

    def makeRotationY(self, theta):
        c, s = math.cos(theta), math.sin(theta)
        return self.set(c, 0, s, 0, 0, 1, 0, 0, -s, 0, c, 0, 0, 0, 0, 1)

    def makeRotationZ(self, theta):
        c, s = math.cos(theta), math.sin(theta)
        return self.set(c, -s, 0, 0, s, c, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)

    def makeRotationAxis(self, axis, angle):
        c = math.cos(angle)
        s = math.sin(angle)
        t = 1 - c
        x, y, z = axis.x, axis.y, axis.z
        tx, ty = t * x, t * y
        return self.set(tx * x + c, tx * y - s * z, tx * z + s * y, 0,
                        tx * y + s * z, ty * y + c, ty * z - s * x, 0,
                        tx * z - s * y, ty * z + s * x, t * z * z + c, 0,
                        0, 0, 0, 1)

    def makeScale(self, x, y, z):
        return self.set(x, 0, 0, 0, 0, y, 0, 0, 0, 0, z, 0, 0, 0, 0, 1)

    def makeShear(self, xy, xz, yx, yz, zx, zy):
        return self.set(1, yx, zx, 0, xy, 1, zy, 0, xz, yz, 1, 0, 0, 0, 0, 1)

    def compose(self, position, quaternion, scale):
        te = self.elements
        x, y, z, w = quaternion._x, quaternion._y, quaternion._z, quaternion._w
        x2, y2, z2 = x + x, y + y, z + z
        xx, xy, xz = x * x2, x * y2, x * z2
        yy, yz, zz = y * y2, y * z2, z * z2
        wx, wy, wz = w * x2, w * y2, w * z2
        sx, sy, sz = scale.x, scale.y, scale.z
        te[0] = (1 - (yy + zz)) * sx
        te[1] = (xy + wz) * sx
        te[2] = (xz - wy) * sx
        te[3] = 0
        te[4] = (xy - wz) * sy
        te[5] = (1 - (xx + zz)) * sy
        te[6] = (yz + wx) * sy
        te[7] = 0
        te[8] = (xz + wy) * sz
        te[9] = (yz - wx) * sz
        te[10] = (1 - (xx + yy)) * sz
        te[11] = 0
        te[12] = position.x
        te[13] = position.y
        te[14] = position.z
        te[15] = 1
        return self

    def decompose(self, position, quaternion, scale):
        te = self.elements
        position.x = te[12]
        position.y = te[13]
        position.z = te[14]
        det = self.determinantAffine()
        if det == 0:
            scale.set(1, 1, 1)
            quaternion.identity()
            return self
        _v = Vector3()
        sx = _v.set(te[0], te[1], te[2]).length()
        sy = _v.set(te[4], te[5], te[6]).length()
        sz = _v.set(te[8], te[9], te[10]).length()
        if det < 0:
            sx = -sx
        _m = Matrix4().copy(self)
        invSX, invSY, invSZ = 1 / sx, 1 / sy, 1 / sz
        me = _m.elements
        me[0] *= invSX; me[1] *= invSX; me[2] *= invSX
        me[4] *= invSY; me[5] *= invSY; me[6] *= invSY
        me[8] *= invSZ; me[9] *= invSZ; me[10] *= invSZ
        quaternion.setFromRotationMatrix(_m)
        scale.x = sx
        scale.y = sy
        scale.z = sz
        return self

    def equals(self, m):
        return all(a == b for a, b in zip(self.elements, m.elements))

    def fromArray(self, array, offset=0):
        for i in range(16):
            self.elements[i] = array[i + offset]
        return self

    def toArray(self, array=None, offset=0):
        if array is None:
            array = []
        _put(array, offset, self.elements)
        return array


# ============================================================================================ Quaternion

def _noop():
    pass


class Quaternion:
    isQuaternion = True

    def __init__(self, x=0, y=0, z=0, w=1):
        self._x = x
        self._y = y
        self._z = z
        self._w = w
        self._onChangeCallback = _noop

    def __iter__(self):
        yield self._x
        yield self._y
        yield self._z
        yield self._w

    def __repr__(self):
        return 'Quaternion(%r, %r, %r, %r)' % (self._x, self._y, self._z, self._w)

    @property
    def x(self):
        return self._x

    @x.setter
    def x(self, v):
        self._x = v
        self._onChangeCallback()

    @property
    def y(self):
        return self._y

    @y.setter
    def y(self, v):
        self._y = v
        self._onChangeCallback()

    @property
    def z(self):
        return self._z

    @z.setter
    def z(self, v):
        self._z = v
        self._onChangeCallback()

    @property
    def w(self):
        return self._w

    @w.setter
    def w(self, v):
        self._w = v
        self._onChangeCallback()

    @staticmethod
    def slerpFlat(dst, dstOffset, src0, srcOffset0, src1, srcOffset1, t):
        x0, y0, z0, w0 = src0[srcOffset0], src0[srcOffset0 + 1], src0[srcOffset0 + 2], src0[srcOffset0 + 3]
        x1, y1, z1, w1 = src1[srcOffset1], src1[srcOffset1 + 1], src1[srcOffset1 + 2], src1[srcOffset1 + 3]
        if w0 != w1 or x0 != x1 or y0 != y1 or z0 != z1:
            dot = x0 * x1 + y0 * y1 + z0 * z1 + w0 * w1
            if dot < 0:
                x1, y1, z1, w1, dot = -x1, -y1, -z1, -w1, -dot
            s = 1 - t
            if dot < 0.9995:
                theta = math.acos(dot)
                sin = math.sin(theta)
                s = math.sin(s * theta) / sin
                t = math.sin(t * theta) / sin
                x0 = x0 * s + x1 * t
                y0 = y0 * s + y1 * t
                z0 = z0 * s + z1 * t
                w0 = w0 * s + w1 * t
            else:
                x0 = x0 * s + x1 * t
                y0 = y0 * s + y1 * t
                z0 = z0 * s + z1 * t
                w0 = w0 * s + w1 * t
                f = 1 / math.sqrt(x0 * x0 + y0 * y0 + z0 * z0 + w0 * w0)
                x0 *= f
                y0 *= f
                z0 *= f
                w0 *= f
        dst[dstOffset] = x0
        dst[dstOffset + 1] = y0
        dst[dstOffset + 2] = z0
        dst[dstOffset + 3] = w0

    def set(self, x, y, z, w):
        self._x, self._y, self._z, self._w = x, y, z, w
        self._onChangeCallback()
        return self

    def clone(self):
        return Quaternion(self._x, self._y, self._z, self._w)

    def copy(self, q):
        self._x, self._y, self._z, self._w = q.x, q.y, q.z, q.w
        self._onChangeCallback()
        return self

    def setFromEuler(self, euler, update=True):
        x, y, z, order = euler._x, euler._y, euler._z, euler._order
        c1 = math.cos(x / 2)
        c2 = math.cos(y / 2)
        c3 = math.cos(z / 2)
        s1 = math.sin(x / 2)
        s2 = math.sin(y / 2)
        s3 = math.sin(z / 2)
        if order == 'XYZ':
            self._x = s1 * c2 * c3 + c1 * s2 * s3
            self._y = c1 * s2 * c3 - s1 * c2 * s3
            self._z = c1 * c2 * s3 + s1 * s2 * c3
            self._w = c1 * c2 * c3 - s1 * s2 * s3
        elif order == 'YXZ':
            self._x = s1 * c2 * c3 + c1 * s2 * s3
            self._y = c1 * s2 * c3 - s1 * c2 * s3
            self._z = c1 * c2 * s3 - s1 * s2 * c3
            self._w = c1 * c2 * c3 + s1 * s2 * s3
        elif order == 'ZXY':
            self._x = s1 * c2 * c3 - c1 * s2 * s3
            self._y = c1 * s2 * c3 + s1 * c2 * s3
            self._z = c1 * c2 * s3 + s1 * s2 * c3
            self._w = c1 * c2 * c3 - s1 * s2 * s3
        elif order == 'ZYX':
            self._x = s1 * c2 * c3 - c1 * s2 * s3
            self._y = c1 * s2 * c3 + s1 * c2 * s3
            self._z = c1 * c2 * s3 - s1 * s2 * c3
            self._w = c1 * c2 * c3 + s1 * s2 * s3
        elif order == 'YZX':
            self._x = s1 * c2 * c3 + c1 * s2 * s3
            self._y = c1 * s2 * c3 + s1 * c2 * s3
            self._z = c1 * c2 * s3 - s1 * s2 * c3
            self._w = c1 * c2 * c3 - s1 * s2 * s3
        elif order == 'XZY':
            self._x = s1 * c2 * c3 - c1 * s2 * s3
            self._y = c1 * s2 * c3 - s1 * c2 * s3
            self._z = c1 * c2 * s3 + s1 * s2 * c3
            self._w = c1 * c2 * c3 + s1 * s2 * s3
        if update:
            self._onChangeCallback()
        return self

    def setFromAxisAngle(self, axis, angle):
        halfAngle = angle / 2
        s = math.sin(halfAngle)
        self._x = axis.x * s
        self._y = axis.y * s
        self._z = axis.z * s
        self._w = math.cos(halfAngle)
        self._onChangeCallback()
        return self

    def setFromRotationMatrix(self, m):
        te = m.elements
        m11, m12, m13 = te[0], te[4], te[8]
        m21, m22, m23 = te[1], te[5], te[9]
        m31, m32, m33 = te[2], te[6], te[10]
        trace = m11 + m22 + m33
        if trace > 0:
            s = 0.5 / math.sqrt(trace + 1.0)
            self._w = 0.25 / s
            self._x = (m32 - m23) * s
            self._y = (m13 - m31) * s
            self._z = (m21 - m12) * s
        elif m11 > m22 and m11 > m33:
            s = 2.0 * math.sqrt(1.0 + m11 - m22 - m33)
            self._w = (m32 - m23) / s
            self._x = 0.25 * s
            self._y = (m12 + m21) / s
            self._z = (m13 + m31) / s
        elif m22 > m33:
            s = 2.0 * math.sqrt(1.0 + m22 - m11 - m33)
            self._w = (m13 - m31) / s
            self._x = (m12 + m21) / s
            self._y = 0.25 * s
            self._z = (m23 + m32) / s
        else:
            s = 2.0 * math.sqrt(1.0 + m33 - m11 - m22)
            self._w = (m21 - m12) / s
            self._x = (m13 + m31) / s
            self._y = (m23 + m32) / s
            self._z = 0.25 * s
        self._onChangeCallback()
        return self

    def setFromUnitVectors(self, vFrom, vTo):
        r = vFrom.dot(vTo) + 1
        if r < 1e-8:
            r = 0
            if abs(vFrom.x) > abs(vFrom.z):
                self._x = -vFrom.y
                self._y = vFrom.x
                self._z = 0
                self._w = r
            else:
                self._x = 0
                self._y = -vFrom.z
                self._z = vFrom.y
                self._w = r
        else:
            self._x = vFrom.y * vTo.z - vFrom.z * vTo.y
            self._y = vFrom.z * vTo.x - vFrom.x * vTo.z
            self._z = vFrom.x * vTo.y - vFrom.y * vTo.x
            self._w = r
        return self.normalize()

    def angleTo(self, q):
        return 2 * math.acos(abs(clamp(self.dot(q), -1, 1)))

    def rotateTowards(self, q, step):
        angle = self.angleTo(q)
        if angle == 0:
            return self
        t = min(1, step / angle)
        self.slerp(q, t)
        return self

    def identity(self):
        return self.set(0, 0, 0, 1)

    def invert(self):
        return self.conjugate()

    def conjugate(self):
        self._x *= -1
        self._y *= -1
        self._z *= -1
        self._onChangeCallback()
        return self

    def dot(self, v):
        return self._x * v._x + self._y * v._y + self._z * v._z + self._w * v._w

    def lengthSq(self):
        return self._x * self._x + self._y * self._y + self._z * self._z + self._w * self._w

    def length(self):
        return math.sqrt(self._x * self._x + self._y * self._y + self._z * self._z + self._w * self._w)

    def normalize(self):
        l = self.length()
        if l == 0:
            self._x = 0
            self._y = 0
            self._z = 0
            self._w = 1
        else:
            l = 1 / l
            self._x = self._x * l
            self._y = self._y * l
            self._z = self._z * l
            self._w = self._w * l
        self._onChangeCallback()
        return self

    def multiply(self, q):
        return self.multiplyQuaternions(self, q)

    def premultiply(self, q):
        return self.multiplyQuaternions(q, self)

    def multiplyQuaternions(self, a, b):
        qax, qay, qaz, qaw = a._x, a._y, a._z, a._w
        qbx, qby, qbz, qbw = b._x, b._y, b._z, b._w
        self._x = qax * qbw + qaw * qbx + qay * qbz - qaz * qby
        self._y = qay * qbw + qaw * qby + qaz * qbx - qax * qbz
        self._z = qaz * qbw + qaw * qbz + qax * qby - qay * qbx
        self._w = qaw * qbw - qax * qbx - qay * qby - qaz * qbz
        self._onChangeCallback()
        return self

    def slerp(self, qb, t):
        x, y, z, w = qb._x, qb._y, qb._z, qb._w
        dot = self.dot(qb)
        if dot < 0:
            x, y, z, w, dot = -x, -y, -z, -w, -dot
        s = 1 - t
        if dot < 0.9995:
            theta = math.acos(dot)
            sin = math.sin(theta)
            s = math.sin(s * theta) / sin
            t = math.sin(t * theta) / sin
            self._x = self._x * s + x * t
            self._y = self._y * s + y * t
            self._z = self._z * s + z * t
            self._w = self._w * s + w * t
            self._onChangeCallback()
        else:
            self._x = self._x * s + x * t
            self._y = self._y * s + y * t
            self._z = self._z * s + z * t
            self._w = self._w * s + w * t
            self.normalize()
        return self

    def slerpQuaternions(self, qa, qb, t):
        return self.copy(qa).slerp(qb, t)

    def random(self):
        theta1 = 2 * math.pi * _random.random()
        theta2 = 2 * math.pi * _random.random()
        x0 = _random.random()
        r1 = math.sqrt(1 - x0)
        r2 = math.sqrt(x0)
        return self.set(r1 * math.sin(theta1), r1 * math.cos(theta1), r2 * math.sin(theta2), r2 * math.cos(theta2))

    def equals(self, q):
        return q._x == self._x and q._y == self._y and q._z == self._z and q._w == self._w

    def fromArray(self, array, offset=0):
        self._x, self._y, self._z, self._w = array[offset], array[offset + 1], array[offset + 2], array[offset + 3]
        self._onChangeCallback()
        return self

    def toArray(self, array=None, offset=0):
        if array is None:
            array = []
        _put(array, offset, (self._x, self._y, self._z, self._w))
        return array

    def fromBufferAttribute(self, attribute, index):
        self._x = attribute.getX(index)
        self._y = attribute.getY(index)
        self._z = attribute.getZ(index)
        self._w = attribute.getW(index)
        self._onChangeCallback()
        return self

    def _onChange(self, callback):
        self._onChangeCallback = callback
        return self


# ============================================================================================ Euler

class Euler:
    isEuler = True
    DEFAULT_ORDER = 'XYZ'

    def __init__(self, x=0, y=0, z=0, order=None):
        self._x = x
        self._y = y
        self._z = z
        self._order = order if order is not None else Euler.DEFAULT_ORDER
        self._onChangeCallback = _noop

    def __iter__(self):
        yield self._x
        yield self._y
        yield self._z
        yield self._order

    def __repr__(self):
        return 'Euler(%r, %r, %r, %r)' % (self._x, self._y, self._z, self._order)

    @property
    def x(self):
        return self._x

    @x.setter
    def x(self, v):
        self._x = v
        self._onChangeCallback()

    @property
    def y(self):
        return self._y

    @y.setter
    def y(self, v):
        self._y = v
        self._onChangeCallback()

    @property
    def z(self):
        return self._z

    @z.setter
    def z(self, v):
        self._z = v
        self._onChangeCallback()

    @property
    def order(self):
        return self._order

    @order.setter
    def order(self, v):
        self._order = v
        self._onChangeCallback()

    def set(self, x, y, z, order=None):
        self._x, self._y, self._z = x, y, z
        self._order = order if order is not None else self._order
        self._onChangeCallback()
        return self

    def clone(self):
        return Euler(self._x, self._y, self._z, self._order)

    def copy(self, euler):
        self._x, self._y, self._z, self._order = euler._x, euler._y, euler._z, euler._order
        self._onChangeCallback()
        return self

    def setFromRotationMatrix(self, m, order=None, update=True):
        if order is None:
            order = self._order
        te = m.elements
        m11, m12, m13 = te[0], te[4], te[8]
        m21, m22, m23 = te[1], te[5], te[9]
        m31, m32, m33 = te[2], te[6], te[10]
        if order == 'XYZ':
            self._y = math.asin(clamp(m13, -1, 1))
            if abs(m13) < 0.9999999:
                self._x = math.atan2(-m23, m33)
                self._z = math.atan2(-m12, m11)
            else:
                self._x = math.atan2(m32, m22)
                self._z = 0
        elif order == 'YXZ':
            self._x = math.asin(-clamp(m23, -1, 1))
            if abs(m23) < 0.9999999:
                self._y = math.atan2(m13, m33)
                self._z = math.atan2(m21, m22)
            else:
                self._y = math.atan2(-m31, m11)
                self._z = 0
        elif order == 'ZXY':
            self._x = math.asin(clamp(m32, -1, 1))
            if abs(m32) < 0.9999999:
                self._y = math.atan2(-m31, m33)
                self._z = math.atan2(-m12, m22)
            else:
                self._y = 0
                self._z = math.atan2(m21, m11)
        elif order == 'ZYX':
            self._y = math.asin(-clamp(m31, -1, 1))
            if abs(m31) < 0.9999999:
                self._x = math.atan2(m32, m33)
                self._z = math.atan2(m21, m11)
            else:
                self._x = 0
                self._z = math.atan2(-m12, m22)
        elif order == 'YZX':
            self._z = math.asin(clamp(m21, -1, 1))
            if abs(m21) < 0.9999999:
                self._x = math.atan2(-m23, m22)
                self._y = math.atan2(-m31, m11)
            else:
                self._x = 0
                self._y = math.atan2(m13, m33)
        elif order == 'XZY':
            self._z = math.asin(-clamp(m12, -1, 1))
            if abs(m12) < 0.9999999:
                self._x = math.atan2(m32, m22)
                self._y = math.atan2(m13, m11)
            else:
                self._x = math.atan2(-m23, m33)
                self._y = 0
        self._order = order
        if update:
            self._onChangeCallback()
        return self

    def setFromQuaternion(self, q, order=None, update=True):
        _m = Matrix4().makeRotationFromQuaternion(q)
        return self.setFromRotationMatrix(_m, order, update)

    def setFromVector3(self, v, order=None):
        return self.set(v.x, v.y, v.z, order if order is not None else self._order)

    def reorder(self, newOrder):
        _q = Quaternion().setFromEuler(self)
        return self.setFromQuaternion(_q, newOrder)

    def equals(self, euler):
        return (euler._x == self._x and euler._y == self._y and euler._z == self._z and
                euler._order == self._order)

    def fromArray(self, array):
        self._x, self._y, self._z = array[0], array[1], array[2]
        if len(array) > 3 and array[3] is not None:
            self._order = array[3]
        self._onChangeCallback()
        return self

    def toArray(self, array=None, offset=0):
        if array is None:
            array = []
        _put(array, offset, (self._x, self._y, self._z, self._order))
        return array

    def _onChange(self, callback):
        self._onChangeCallback = callback
        return self


# ============================================================================================ Color

SRGBColorSpace = 'srgb'
LinearSRGBColorSpace = 'srgb-linear'


def SRGBToLinear(c):
    return c * 0.0773993808 if c < 0.04045 else math.pow(c * 0.9478672986 + 0.0521327014, 2.4)


def LinearToSRGB(c):
    return c * 12.92 if c < 0.0031308 else 1.055 * (math.pow(c, 0.41666)) - 0.055


class _ColorManagement:
    enabled = True
    workingColorSpace = LinearSRGBColorSpace

    def convert(self, color, source, target):
        if not self.enabled or source == target or not source or not target:
            return color
        if source == SRGBColorSpace:
            color.r = SRGBToLinear(color.r)
            color.g = SRGBToLinear(color.g)
            color.b = SRGBToLinear(color.b)
        # both spaces share the Rec.709 primaries: no matrix step
        if target == SRGBColorSpace:
            color.r = LinearToSRGB(color.r)
            color.g = LinearToSRGB(color.g)
            color.b = LinearToSRGB(color.b)
        return color

    def workingToColorSpace(self, color, target):
        return self.convert(color, self.workingColorSpace, target)

    def colorSpaceToWorking(self, color, source):
        return self.convert(color, source, self.workingColorSpace)


ColorManagement = _ColorManagement()

_colorKeywords = {
    'aliceblue': 0xF0F8FF, 'antiquewhite': 0xFAEBD7, 'aqua': 0x00FFFF, 'aquamarine': 0x7FFFD4, 'azure': 0xF0FFFF,
    'beige': 0xF5F5DC, 'bisque': 0xFFE4C4, 'black': 0x000000, 'blanchedalmond': 0xFFEBCD, 'blue': 0x0000FF,
    'blueviolet': 0x8A2BE2, 'brown': 0xA52A2A, 'burlywood': 0xDEB887, 'cadetblue': 0x5F9EA0,
    'chartreuse': 0x7FFF00, 'chocolate': 0xD2691E, 'coral': 0xFF7F50, 'cornflowerblue': 0x6495ED,
    'cornsilk': 0xFFF8DC, 'crimson': 0xDC143C, 'cyan': 0x00FFFF, 'darkblue': 0x00008B, 'darkcyan': 0x008B8B,
    'darkgoldenrod': 0xB8860B, 'darkgray': 0xA9A9A9, 'darkgreen': 0x006400, 'darkgrey': 0xA9A9A9,
    'darkkhaki': 0xBDB76B, 'darkmagenta': 0x8B008B, 'darkolivegreen': 0x556B2F, 'darkorange': 0xFF8C00,
    'darkorchid': 0x9932CC, 'darkred': 0x8B0000, 'darksalmon': 0xE9967A, 'darkseagreen': 0x8FBC8F,
    'darkslateblue': 0x483D8B, 'darkslategray': 0x2F4F4F, 'darkslategrey': 0x2F4F4F, 'darkturquoise': 0x00CED1,
    'darkviolet': 0x9400D3, 'deeppink': 0xFF1493, 'deepskyblue': 0x00BFFF, 'dimgray': 0x696969,
    'dimgrey': 0x696969, 'dodgerblue': 0x1E90FF, 'firebrick': 0xB22222, 'floralwhite': 0xFFFAF0,
    'forestgreen': 0x228B22, 'fuchsia': 0xFF00FF, 'gainsboro': 0xDCDCDC, 'ghostwhite': 0xF8F8FF, 'gold': 0xFFD700,
    'goldenrod': 0xDAA520, 'gray': 0x808080, 'green': 0x008000, 'greenyellow': 0xADFF2F, 'grey': 0x808080,
    'honeydew': 0xF0FFF0, 'hotpink': 0xFF69B4, 'indianred': 0xCD5C5C, 'indigo': 0x4B0082, 'ivory': 0xFFFFF0,
    'khaki': 0xF0E68C, 'lavender': 0xE6E6FA, 'lavenderblush': 0xFFF0F5, 'lawngreen': 0x7CFC00,
    'lemonchiffon': 0xFFFACD, 'lightblue': 0xADD8E6, 'lightcoral': 0xF08080, 'lightcyan': 0xE0FFFF,
    'lightgoldenrodyellow': 0xFAFAD2, 'lightgray': 0xD3D3D3, 'lightgreen': 0x90EE90, 'lightgrey': 0xD3D3D3,
    'lightpink': 0xFFB6C1, 'lightsalmon': 0xFFA07A, 'lightseagreen': 0x20B2AA, 'lightskyblue': 0x87CEFA,
    'lightslategray': 0x778899, 'lightslategrey': 0x778899, 'lightsteelblue': 0xB0C4DE, 'lightyellow': 0xFFFFE0,
    'lime': 0x00FF00, 'limegreen': 0x32CD32, 'linen': 0xFAF0E6, 'magenta': 0xFF00FF, 'maroon': 0x800000,
    'mediumaquamarine': 0x66CDAA, 'mediumblue': 0x0000CD, 'mediumorchid': 0xBA55D3, 'mediumpurple': 0x9370DB,
    'mediumseagreen': 0x3CB371, 'mediumslateblue': 0x7B68EE, 'mediumspringgreen': 0x00FA9A,
    'mediumturquoise': 0x48D1CC, 'mediumvioletred': 0xC71585, 'midnightblue': 0x191970, 'mintcream': 0xF5FFFA,
    'mistyrose': 0xFFE4E1, 'moccasin': 0xFFE4B5, 'navajowhite': 0xFFDEAD, 'navy': 0x000080, 'oldlace': 0xFDF5E6,
    'olive': 0x808000, 'olivedrab': 0x6B8E23, 'orange': 0xFFA500, 'orangered': 0xFF4500, 'orchid': 0xDA70D6,
    'palegoldenrod': 0xEEE8AA, 'palegreen': 0x98FB98, 'paleturquoise': 0xAFEEEE, 'palevioletred': 0xDB7093,
    'papayawhip': 0xFFEFD5, 'peachpuff': 0xFFDAB9, 'peru': 0xCD853F, 'pink': 0xFFC0CB, 'plum': 0xDDA0DD,
    'powderblue': 0xB0E0E6, 'purple': 0x800080, 'rebeccapurple': 0x663399, 'red': 0xFF0000,
    'rosybrown': 0xBC8F8F, 'royalblue': 0x4169E1, 'saddlebrown': 0x8B4513, 'salmon': 0xFA8072,
    'sandybrown': 0xF4A460, 'seagreen': 0x2E8B57, 'seashell': 0xFFF5EE, 'sienna': 0xA0522D, 'silver': 0xC0C0C0,
    'skyblue': 0x87CEEB, 'slateblue': 0x6A5ACD, 'slategray': 0x708090, 'slategrey': 0x708090, 'snow': 0xFFFAFA,
    'springgreen': 0x00FF7F, 'steelblue': 0x4682B4, 'tan': 0xD2B48C, 'teal': 0x008080, 'thistle': 0xD8BFD8,
    'tomato': 0xFF6347, 'turquoise': 0x40E0D0, 'violet': 0xEE82EE, 'wheat': 0xF5DEB3, 'white': 0xFFFFFF,
    'whitesmoke': 0xF5F5F5, 'yellow': 0xFFFF00, 'yellowgreen': 0x9ACD32,
}

import re as _re
_re_func = _re.compile(r'^(\w+)\(([^\)]*)\)')
_re_rgb = _re.compile(r'^\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(?:,\s*(\d*\.?\d+)\s*)?$')
_re_rgbp = _re.compile(r'^\s*(\d+)\%\s*,\s*(\d+)\%\s*,\s*(\d+)\%\s*(?:,\s*(\d*\.?\d+)\s*)?$')
_re_hsl = _re.compile(r'^\s*(\d*\.?\d+)\s*,\s*(\d*\.?\d+)\%\s*,\s*(\d*\.?\d+)\%\s*(?:,\s*(\d*\.?\d+)\s*)?$')
_re_hex = _re.compile(r'^\#([A-Fa-f\d]+)$')


def _hue2rgb(p, q, t):
    if t < 0:
        t += 1
    if t > 1:
        t -= 1
    if t < 1 / 6:
        return p + (q - p) * 6 * t
    if t < 1 / 2:
        return q
    if t < 2 / 3:
        return p + (q - p) * 6 * (2 / 3 - t)
    return p


class Color:
    """THREE.Color: r, g, b in the LINEAR working space."""
    isColor = True
    NAMES = _colorKeywords
    __slots__ = ('r', 'g', 'b')

    def __init__(self, r=None, g=None, b=None):
        self.r = 1
        self.g = 1
        self.b = 1
        self.set(r, g, b)

    def __iter__(self):
        yield self.r
        yield self.g
        yield self.b

    def __len__(self):
        return 3

    def __getitem__(self, i):
        return (self.r, self.g, self.b)[i]

    def __array__(self, dtype=None, copy=None):
        return _np.array([self.r, self.g, self.b], dtype=dtype or float)

    def __repr__(self):
        return 'Color(%r, %r, %r)' % (self.r, self.g, self.b)

    def set(self, r, g=None, b=None):
        if g is None and b is None:
            value = r
            if value is not None and getattr(value, 'isColor', False):
                self.copy(value)
            elif isinstance(value, (int, float)) and not isinstance(value, bool):
                self.setHex(value)
            elif isinstance(value, str):
                self.setStyle(value)
        else:
            self.setRGB(r, g, b)
        return self

    def setScalar(self, scalar):
        self.r = scalar
        self.g = scalar
        self.b = scalar
        return self

    def setHex(self, hex_, colorSpace=SRGBColorSpace):
        hex_ = to_int32(math.floor(hex_))
        self.r = ((hex_ >> 16) & 255) / 255
        self.g = ((hex_ >> 8) & 255) / 255
        self.b = (hex_ & 255) / 255
        ColorManagement.colorSpaceToWorking(self, colorSpace)
        return self

    def setRGB(self, r, g, b, colorSpace=None):
        self.r = r
        self.g = g
        self.b = b
        ColorManagement.colorSpaceToWorking(self, colorSpace or ColorManagement.workingColorSpace)
        return self

    def setHSL(self, h, s, l, colorSpace=None):
        h = euclideanModulo(h, 1)
        s = clamp(s, 0, 1)
        l = clamp(l, 0, 1)
        if s == 0:
            self.r = self.g = self.b = l
        else:
            p = l * (1 + s) if l <= 0.5 else l + s - (l * s)
            q = (2 * l) - p
            self.r = _hue2rgb(q, p, h + 1 / 3)
            self.g = _hue2rgb(q, p, h)
            self.b = _hue2rgb(q, p, h - 1 / 3)
        ColorManagement.colorSpaceToWorking(self, colorSpace or ColorManagement.workingColorSpace)
        return self

    def setStyle(self, style, colorSpace=SRGBColorSpace):
        m = _re_func.match(style)
        if m:
            name, components = m.group(1), m.group(2)
            if name in ('rgb', 'rgba'):
                c = _re_rgb.match(components)
                if c:
                    return self.setRGB(min(255, int(c.group(1))) / 255, min(255, int(c.group(2))) / 255,
                                       min(255, int(c.group(3))) / 255, colorSpace)
                c = _re_rgbp.match(components)
                if c:
                    return self.setRGB(min(100, int(c.group(1))) / 100, min(100, int(c.group(2))) / 100,
                                       min(100, int(c.group(3))) / 100, colorSpace)
            elif name in ('hsl', 'hsla'):
                c = _re_hsl.match(components)
                if c:
                    return self.setHSL(float(c.group(1)) / 360, float(c.group(2)) / 100,
                                       float(c.group(3)) / 100, colorSpace)
            return self
        m = _re_hex.match(style)
        if m:
            hx = m.group(1)
            if len(hx) == 3:
                return self.setRGB(int(hx[0], 16) / 15, int(hx[1], 16) / 15, int(hx[2], 16) / 15, colorSpace)
            if len(hx) == 6:
                return self.setHex(int(hx, 16), colorSpace)
            return self
        if style:
            return self.setColorName(style, colorSpace)
        return self

    def setColorName(self, style, colorSpace=SRGBColorSpace):
        hx = _colorKeywords.get(style.lower())
        if hx is not None:
            self.setHex(hx, colorSpace)
        return self

    def clone(self):
        return Color(self.r, self.g, self.b)

    def copy(self, color):
        self.r = color.r
        self.g = color.g
        self.b = color.b
        return self

    def copySRGBToLinear(self, color):
        self.r = SRGBToLinear(color.r)
        self.g = SRGBToLinear(color.g)
        self.b = SRGBToLinear(color.b)
        return self

    def copyLinearToSRGB(self, color):
        self.r = LinearToSRGB(color.r)
        self.g = LinearToSRGB(color.g)
        self.b = LinearToSRGB(color.b)
        return self

    def convertSRGBToLinear(self):
        return self.copySRGBToLinear(self)

    def convertLinearToSRGB(self):
        return self.copyLinearToSRGB(self)

    def getHex(self, colorSpace=SRGBColorSpace):
        c = ColorManagement.workingToColorSpace(Color().copy(self), colorSpace)
        return (js_round(clamp(c.r * 255, 0, 255)) * 65536 + js_round(clamp(c.g * 255, 0, 255)) * 256 +
                js_round(clamp(c.b * 255, 0, 255)))

    def getHexString(self, colorSpace=SRGBColorSpace):
        return ('000000' + format(self.getHex(colorSpace), 'x'))[-6:]

    def getHSL(self, target=None, colorSpace=None):
        if target is None:
            target = JSObj()
        c = ColorManagement.workingToColorSpace(Color().copy(self), colorSpace or ColorManagement.workingColorSpace)
        r, g, b = c.r, c.g, c.b
        mx = max(r, g, b)
        mn = min(r, g, b)
        lightness = (mn + mx) / 2.0
        if mn == mx:
            hue = 0
            saturation = 0
        else:
            delta = mx - mn
            saturation = delta / (mx + mn) if lightness <= 0.5 else delta / (2 - mx - mn)
            if mx == r:
                hue = (g - b) / delta + (6 if g < b else 0)
            elif mx == g:
                hue = (b - r) / delta + 2
            else:
                hue = (r - g) / delta + 4
            hue /= 6
        if isinstance(target, dict):
            target['h'] = hue
            target['s'] = saturation
            target['l'] = lightness
        else:
            target.h = hue
            target.s = saturation
            target.l = lightness
        return target

    def getRGB(self, target, colorSpace=None):
        c = ColorManagement.workingToColorSpace(Color().copy(self), colorSpace or ColorManagement.workingColorSpace)
        target.r = c.r
        target.g = c.g
        target.b = c.b
        return target

    def getStyle(self, colorSpace=SRGBColorSpace):
        c = ColorManagement.workingToColorSpace(Color().copy(self), colorSpace)
        r, g, b = c.r, c.g, c.b
        if colorSpace != SRGBColorSpace:
            return 'color(%s %s %s %s)' % (colorSpace, js_to_fixed(r, 3), js_to_fixed(g, 3), js_to_fixed(b, 3))
        return 'rgb(%d,%d,%d)' % (js_round(r * 255), js_round(g * 255), js_round(b * 255))

    def offsetHSL(self, h, s, l):
        hsl = self.getHSL(JSObj())
        return self.setHSL(hsl['h'] + h, hsl['s'] + s, hsl['l'] + l)

    def add(self, color):
        self.r += color.r
        self.g += color.g
        self.b += color.b
        return self

    def addColors(self, c1, c2):
        self.r = c1.r + c2.r
        self.g = c1.g + c2.g
        self.b = c1.b + c2.b
        return self

    def addScalar(self, s):
        self.r += s
        self.g += s
        self.b += s
        return self

    def sub(self, color):
        self.r = max(0, self.r - color.r)
        self.g = max(0, self.g - color.g)
        self.b = max(0, self.b - color.b)
        return self

    def multiply(self, color):
        self.r *= color.r
        self.g *= color.g
        self.b *= color.b
        return self

    def multiplyScalar(self, s):
        self.r *= s
        self.g *= s
        self.b *= s
        return self

    def lerp(self, color, alpha):
        self.r += (color.r - self.r) * alpha
        self.g += (color.g - self.g) * alpha
        self.b += (color.b - self.b) * alpha
        return self

    def lerpColors(self, c1, c2, alpha):
        self.r = c1.r + (c2.r - c1.r) * alpha
        self.g = c1.g + (c2.g - c1.g) * alpha
        self.b = c1.b + (c2.b - c1.b) * alpha
        return self

    def lerpHSL(self, color, alpha):
        a = self.getHSL(JSObj())
        b = color.getHSL(JSObj())
        return self.setHSL(lerp(a['h'], b['h'], alpha), lerp(a['s'], b['s'], alpha), lerp(a['l'], b['l'], alpha))

    def setFromVector3(self, v):
        self.r = v.x
        self.g = v.y
        self.b = v.z
        return self

    def applyMatrix3(self, m):
        r, g, b = self.r, self.g, self.b
        e = m.elements
        self.r = e[0] * r + e[3] * g + e[6] * b
        self.g = e[1] * r + e[4] * g + e[7] * b
        self.b = e[2] * r + e[5] * g + e[8] * b
        return self

    def equals(self, c):
        return c.r == self.r and c.g == self.g and c.b == self.b

    def fromArray(self, array, offset=0):
        self.r, self.g, self.b = array[offset], array[offset + 1], array[offset + 2]
        return self

    def toArray(self, array=None, offset=0):
        if array is None:
            array = []
        _put(array, offset, (self.r, self.g, self.b))
        return array

    def fromBufferAttribute(self, attribute, index):
        self.r = attribute.getX(index)
        self.g = attribute.getY(index)
        self.b = attribute.getZ(index)
        return self

    def toJSON(self):
        return self.getHex()


# ============================================================================================ Box3 / Sphere / Line3 / Plane / Triangle

class Box3:
    isBox3 = True

    def __init__(self, min_=None, max_=None):
        self.min = min_ if min_ is not None else Vector3(_INF, _INF, _INF)
        self.max = max_ if max_ is not None else Vector3(-_INF, -_INF, -_INF)

    # python convenience: `mn, mx = box`
    def __iter__(self):
        yield self.min
        yield self.max

    def __getitem__(self, i):
        return (self.min, self.max)[i]

    def __repr__(self):
        return 'Box3(%r, %r)' % (self.min, self.max)

    def set(self, min_, max_):
        self.min.copy(min_)
        self.max.copy(max_)
        return self

    def setFromArray(self, array):
        self.makeEmpty()
        v = Vector3()
        for i in range(0, len(array), 3):
            self.expandByPoint(v.fromArray(array, i))
        return self

    def setFromBufferAttribute(self, attribute):
        self.makeEmpty()
        n = attribute.count if hasattr(attribute, 'count') else len(attribute)
        if n:
            a = _np.asarray(attribute, dtype=float).reshape(n, -1)
            mn = a[:, :3].min(axis=0)
            mx = a[:, :3].max(axis=0)
            self.min.set(float(mn[0]), float(mn[1]), float(mn[2]))
            self.max.set(float(mx[0]), float(mx[1]), float(mx[2]))
        return self

    def setFromPoints(self, points):
        self.makeEmpty()
        for p in points:
            self.expandByPoint(p)
        return self

    def setFromCenterAndSize(self, center, size):
        half = Vector3().copy(size).multiplyScalar(0.5)
        self.min.copy(center).sub(half)
        self.max.copy(center).add(half)
        return self

    def clone(self):
        return Box3().copy(self)

    def copy(self, box):
        self.min.copy(box.min)
        self.max.copy(box.max)
        return self

    def makeEmpty(self):
        self.min.x = self.min.y = self.min.z = _INF
        self.max.x = self.max.y = self.max.z = -_INF
        return self

    def isEmpty(self):
        return self.max.x < self.min.x or self.max.y < self.min.y or self.max.z < self.min.z

    def getCenter(self, target=None):
        if target is None:
            target = Vector3()
        return target.set(0, 0, 0) if self.isEmpty() else target.addVectors(self.min, self.max).multiplyScalar(0.5)

    def getSize(self, target=None):
        if target is None:
            target = Vector3()
        return target.set(0, 0, 0) if self.isEmpty() else target.subVectors(self.max, self.min)

    def expandByPoint(self, point):
        self.min.min(point)
        self.max.max(point)
        return self

    def expandByVector(self, vector):
        self.min.sub(vector)
        self.max.add(vector)
        return self

    def expandByScalar(self, scalar):
        self.min.addScalar(-scalar)
        self.max.addScalar(scalar)
        return self

    def containsPoint(self, p):
        return (self.min.x <= p.x <= self.max.x and self.min.y <= p.y <= self.max.y and
                self.min.z <= p.z <= self.max.z)

    def containsBox(self, box):
        return (self.min.x <= box.min.x and box.max.x <= self.max.x and self.min.y <= box.min.y and
                box.max.y <= self.max.y and self.min.z <= box.min.z and box.max.z <= self.max.z)

    def intersectsBox(self, box):
        return (box.max.x >= self.min.x and box.min.x <= self.max.x and box.max.y >= self.min.y and
                box.min.y <= self.max.y and box.max.z >= self.min.z and box.min.z <= self.max.z)

    def clampPoint(self, point, target=None):
        if target is None:
            target = Vector3()
        return target.copy(point).clamp(self.min, self.max)

    def distanceToPoint(self, point):
        return self.clampPoint(point, Vector3()).distanceTo(point)

    def intersect(self, box):
        self.min.max(box.min)
        self.max.min(box.max)
        if self.isEmpty():
            self.makeEmpty()
        return self

    def union(self, box):
        self.min.min(box.min)
        self.max.max(box.max)
        return self

    def applyMatrix4(self, matrix):
        if self.isEmpty():
            return self
        mn, mx = self.min, self.max
        pts = [Vector3(mn.x, mn.y, mn.z), Vector3(mn.x, mn.y, mx.z), Vector3(mn.x, mx.y, mn.z),
               Vector3(mn.x, mx.y, mx.z), Vector3(mx.x, mn.y, mn.z), Vector3(mx.x, mn.y, mx.z),
               Vector3(mx.x, mx.y, mn.z), Vector3(mx.x, mx.y, mx.z)]
        for p in pts:
            p.applyMatrix4(matrix)
        return self.setFromPoints(pts)

    def translate(self, offset):
        self.min.add(offset)
        self.max.add(offset)
        return self

    def equals(self, box):
        return box.min.equals(self.min) and box.max.equals(self.max)

    def getBoundingSphere(self, target):
        if self.isEmpty():
            target.makeEmpty()
        else:
            self.getCenter(target.center)
            target.radius = self.getSize(Vector3()).length() * 0.5
        return target


class Sphere:
    isSphere = True

    def __init__(self, center=None, radius=-1):
        self.center = center if center is not None else Vector3()
        self.radius = radius

    def __repr__(self):
        return 'Sphere(%r, %r)' % (self.center, self.radius)

    def set(self, center, radius):
        self.center.copy(center)
        self.radius = radius
        return self

    def setFromPoints(self, points, optionalCenter=None):
        center = self.center
        if optionalCenter is not None:
            center.copy(optionalCenter)
        else:
            Box3().setFromPoints(points).getCenter(center)
        maxRadiusSq = 0
        for p in points:
            maxRadiusSq = max(maxRadiusSq, center.distanceToSquared(p))
        self.radius = math.sqrt(maxRadiusSq)
        return self

    def copy(self, sphere):
        self.center.copy(sphere.center)
        self.radius = sphere.radius
        return self

    def clone(self):
        return Sphere().copy(self)

    def isEmpty(self):
        return self.radius < 0

    def makeEmpty(self):
        self.center.set(0, 0, 0)
        self.radius = -1
        return self

    def containsPoint(self, point):
        return point.distanceToSquared(self.center) <= (self.radius * self.radius)

    def distanceToPoint(self, point):
        return point.distanceTo(self.center) - self.radius

    def applyMatrix4(self, matrix):
        self.center.applyMatrix4(matrix)
        self.radius = self.radius * matrix.getMaxScaleOnAxis()
        return self

    def translate(self, offset):
        self.center.add(offset)
        return self


class Line3:
    def __init__(self, start=None, end=None):
        self.start = start if start is not None else Vector3()
        self.end = end if end is not None else Vector3()

    def set(self, start, end):
        self.start.copy(start)
        self.end.copy(end)
        return self

    def delta(self, target):
        return target.subVectors(self.end, self.start)

    def distanceSq(self):
        return self.start.distanceToSquared(self.end)

    def distance(self):
        return self.start.distanceTo(self.end)

    def at(self, t, target):
        return self.delta(target).multiplyScalar(t).add(self.start)

    def closestPointToPointParameter(self, point, clampToLine):
        startP = Vector3().subVectors(point, self.start)
        startEnd = Vector3().subVectors(self.end, self.start)
        startEnd2 = startEnd.dot(startEnd)
        if startEnd2 == 0:
            return 0
        startEnd_startP = startEnd.dot(startP)
        t = startEnd_startP / startEnd2
        if clampToLine:
            t = clamp(t, 0, 1)
        return t

    def closestPointToPoint(self, point, clampToLine, target):
        t = self.closestPointToPointParameter(point, clampToLine)
        return self.delta(target).multiplyScalar(t).add(self.start)


class Plane:
    def __init__(self, normal=None, constant=0):
        self.normal = normal if normal is not None else Vector3(1, 0, 0)
        self.constant = constant

    def set(self, normal, constant):
        self.normal.copy(normal)
        self.constant = constant
        return self

    def setFromNormalAndCoplanarPoint(self, normal, point):
        self.normal.copy(normal)
        self.constant = -point.dot(self.normal)
        return self

    def setFromCoplanarPoints(self, a, b, c):
        normal = Vector3().subVectors(c, b).cross(Vector3().subVectors(a, b)).normalize()
        self.setFromNormalAndCoplanarPoint(normal, a)
        return self

    def distanceToPoint(self, point):
        return self.normal.dot(point) + self.constant


class Triangle:
    def __init__(self, a=None, b=None, c=None):
        self.a = a if a is not None else Vector3()
        self.b = b if b is not None else Vector3()
        self.c = c if c is not None else Vector3()

    @staticmethod
    def getNormal_(a, b, c, target):  # static Triangle.getNormal
        target.subVectors(c, b)
        v0 = Vector3().subVectors(a, b)
        target.cross(v0)
        targetLengthSq = target.lengthSq()
        if targetLengthSq > 0:
            return target.multiplyScalar(1 / math.sqrt(targetLengthSq))
        return target.set(0, 0, 0)

    def set(self, a, b, c):
        self.a.copy(a)
        self.b.copy(b)
        self.c.copy(c)
        return self

    def getArea(self):
        v0 = Vector3().subVectors(self.c, self.b)
        v1 = Vector3().subVectors(self.a, self.b)
        return v0.cross(v1).length() * 0.5

    def getMidpoint(self, target):
        return target.addVectors(self.a, self.b).add(self.c).multiplyScalar(1 / 3)

    def getNormal(self, target):
        return Triangle.getNormal_(self.a, self.b, self.c, target)
