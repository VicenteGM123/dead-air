"""Tiny JS-compatibility helpers shared by the character pipeline (blender/chars/**).

O          attribute dict (JS object literal): O(base, x=1) == {...base, x: 1}; missing attributes read as None
           (JS undefined), so `E.yaw` works like in the JS defs. JSON-serialisable (it is a dict).
nz(a, d)   JS `a ?? d`
jsround    JS Math.round (half up)
"""
import math


class O(dict):
    """JS-like object: attribute access to keys; missing keys -> None (undefined)."""

    def __init__(self, *bases, **kw):
        super().__init__()
        for b in bases:
            if b:
                self.update(b)
        self.update(kw)

    def __getattr__(self, k):
        if k.startswith('__'):
            raise AttributeError(k)
        return self.get(k)

    def __setattr__(self, k, v):
        self[k] = v

    def __delattr__(self, k):
        self.pop(k, None)

    def copy(self):
        return O(self)


def nz(a, d):
    """JS `a ?? d`."""
    return d if a is None else a


def jsround(x):
    """JS Math.round (ties toward +inf)."""
    return math.floor(x + 0.5)


def truthy(v):
    """JS truthiness for the values used by the defs."""
    if v is None or v is False:
        return False
    if isinstance(v, (int, float)) and not isinstance(v, bool):
        return v != 0 and not (isinstance(v, float) and math.isnan(v))
    if isinstance(v, str):
        return v != ''
    return True


def jor(a, b):
    """JS `a || b`."""
    return a if truthy(a) else b


def opts(o, kw):
    """Merge a JS-style options object (dict or None) with Python keyword arguments."""
    if o is None:
        return O(kw)
    r = O(o)
    r.update(kw)
    return r


DEG = math.pi / 180
