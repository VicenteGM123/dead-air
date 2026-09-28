"""Seeded randomness, bit-exact with src/core/rng.js (mulberry32) and the FNV-1a `hashStr` of
src/core/textures.js / src/props/kit.js (32-bit Math.imul semantics emulated with Python ints).

    rand = mulberry32(seed)      # rand() -> float in [0, 1), same sequence as the JS
    rand = seeded('some|key')    # == mulberry32(hashStr('some|key'))  (canvas textures, kit paint)

Helpers take the random source `r` as last argument (default: Python's random.random, i.e. JS Math.random).
NOTE: `range` shadows the builtin inside this module on purpose (JS name); import it as `rng.range`.
"""

import builtins as _builtins
import math as _math
import random as _random

from .mathutils3 import to_int32, to_uint32, imul, js_keys

__all__ = ['mulberry32', 'hashStr', 'seeded', 'range', 'rangeInt', 'pick', 'chance', 'shuffle', 'weighted',
           'hash1', 'noise1']

_brange = _builtins.range


def mulberry32(seed):
    """Returns rand() -> [0,1) (JS: `let a = seed >>> 0; return function rand() {...}`)."""
    state = [to_uint32(seed)]

    def rand():
        a = (state[0] + 0x6D2B79F5) & 0xFFFFFFFF          # a = (a + 0x6D2B79F5) >>> 0
        state[0] = a
        t = a
        t = imul(t ^ (t >> 15), t | 1)                    # Math.imul(t ^ (t >>> 15), t | 1)
        tu = t & 0xFFFFFFFF
        t = to_int32(t ^ to_int32(t + imul(t ^ (tu >> 7), t | 61)))   # t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
        tu = t & 0xFFFFFFFF
        return ((t ^ (tu >> 14)) & 0xFFFFFFFF) / 4294967296   # ((t ^ (t >>> 14)) >>> 0) / 4294967296

    return rand


def hashStr(s):
    """FNV-1a over UTF-16 code units (JS charCodeAt), Math.imul semantics, returns uint32."""
    h = 2166136261
    data = str(s).encode('utf-16-le', 'surrogatepass')
    for i in _brange(0, len(data), 2):
        c = data[i] | (data[i + 1] << 8)
        h = imul(to_int32(h) ^ c, 16777619)
    return to_uint32(h)


def seeded(key):
    """mulberry32(hashStr(key)) — the per-texture / per-paint stream pattern of textures.js and kit.js."""
    return mulberry32(hashStr(key))


def range(min_, max_, r=None):  # noqa: A001 (JS name)
    r = r or _random.random
    return min_ + (max_ - min_) * r()


def rangeInt(min_, max_, r=None):
    r = r or _random.random
    return int(_math.floor(min_ + (max_ - min_ + 1) * r()))


def pick(arr, r=None):
    r = r or _random.random
    return arr[int(_math.floor(r() * len(arr)))]


def chance(p, r=None):
    r = r or _random.random
    return r() < p


def shuffle(arr, r=None):
    """In-place Fisher-Yates shuffle (returns arr)."""
    r = r or _random.random
    for i in _brange(len(arr) - 1, 0, -1):
        j = int(_math.floor(r() * (i + 1)))
        arr[i], arr[j] = arr[j], arr[i]
    return arr


def weighted(weights, r=None):
    """Weighted pick over {key: weight} -> key (None if all weights are 0). Keys iterate in JS for..in order."""
    r = r or _random.random
    keys = js_keys(weights)
    total = 0
    for k in keys:
        total += weights[k]
    if total <= 0:
        return None
    x = r() * total
    for k in keys:
        x -= weights[k]
        if x < 0:
            return k
    return None


def hash1(n):
    """Cheap deterministic hash noise in [0,1)."""
    s = _math.sin(n * 127.1 + 311.7) * 43758.5453
    return s - _math.floor(s)


def noise1(x):
    """Smooth 1D value noise in [-1,1]."""
    i = _math.floor(x)
    f = x - i
    u = f * f * (3 - 2 * f)
    return (hash1(i) * (1 - u) + hash1(i + 1) * u) * 2 - 1
