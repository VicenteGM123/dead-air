"""meshoptimizer's meshopt_simplifyWithAttributes (C++ source vendored from zeux/meshoptimizer v1.2, the library
version inside the npm package `meshoptimizer@1.2.0` that tools/bake/bake.mjs calls), compiled on first use with the
system C++ compiler into blender/_vendor/ and called through ctypes, so the Blender bake distributes triangles
exactly like the JS bake. Compiled with -ffp-contract=off (no FMA), like the wasm build, so the float32 arithmetic
matches it. available() is False when no compiler is found; chars/bake/bake.py then falls back to the numpy
simplifier (chars/bake/simplify.py).
"""
import ctypes
import hashlib
import os
import shutil
import subprocess
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
VENDOR = os.path.abspath(os.path.join(HERE, '..', '..', '..', '_vendor'))
SOURCES = ['simplifier.cpp', 'allocator.cpp']
FLAGS = {'LockBorder': 1, 'Sparse': 2, 'ErrorAbsolute': 4, 'Prune': 8, 'Regularize': 16, 'Permissive': 32,
         'RegularizeLight': 64}

_lib = None
_err = None


def _build():
    h = hashlib.sha1()
    for s in SOURCES + ['meshoptimizer.h']:
        with open(os.path.join(HERE, s), 'rb') as f:
            h.update(f.read())
    so = os.path.join(VENDOR, 'libmeshopt_simplifier_%s.so' % h.hexdigest()[:12])
    if not os.path.exists(so):
        cxx = os.environ.get('CXX') or shutil.which('c++') or shutil.which('g++') or shutil.which('clang++')
        if not cxx:
            raise RuntimeError('no C++ compiler (set CXX)')
        os.makedirs(VENDOR, exist_ok=True)
        tmp = so + '.%d.tmp' % os.getpid()
        cmd = [cxx, '-O2', '-DNDEBUG', '-ffp-contract=off', '-fno-fast-math', '-fPIC', '-shared', '-std=gnu++98',
               '-o', tmp] + [os.path.join(HERE, s) for s in SOURCES]
        print('[chars.bake.meshopt] compiling', ' '.join(cmd), flush=True)
        subprocess.check_call(cmd)
        os.replace(tmp, so)
    lib = ctypes.CDLL(so)
    f = lib.meshopt_simplifyWithAttributes
    P = ctypes.c_void_p
    Z = ctypes.c_size_t
    f.argtypes = [P, P, Z, P, Z, Z, P, Z, P, Z, P, Z, ctypes.c_float, ctypes.c_uint, P]
    f.restype = Z
    return lib


def available():
    global _lib, _err
    if _lib is None and _err is None:
        try:
            _lib = _build()
        except Exception as e:     # no compiler / build failure: numpy fallback
            _err = e
            print('[chars.bake.meshopt] unavailable (%s): using the numpy simplifier' % e, file=sys.stderr, flush=True)
    return _lib is not None


def simplify_with_attributes(indices, positions, attrs, weights, target_index_count, target_error=0.05, flags=None,
                             vertex_lock=None):
    """Same call as MeshoptSimplifier.simplifyWithAttributes(idx, positions, 3, attrs, k, weights, lock, target,
    error, flags) -> (indices (m,3) int64 into the input vertices, result error)."""
    if not available():
        raise RuntimeError('meshoptimizer unavailable: %s' % _err)
    I = np.ascontiguousarray(np.asarray(indices).reshape(-1), np.uint32)
    Pp = np.ascontiguousarray(np.asarray(positions, np.float32).reshape(len(np.asarray(positions)), -1)[:, :3])
    A = np.ascontiguousarray(np.asarray(attrs, np.float32))
    n, k = A.shape
    Wt = np.ascontiguousarray(np.asarray(weights, np.float32))
    lock = None if vertex_lock is None else np.ascontiguousarray(np.asarray(vertex_lock, np.uint8))
    opts = 0
    for fl in flags or []:
        opts |= FLAGS[fl]
    dst = np.zeros(len(I), np.uint32)
    err = np.zeros(1, np.float32)
    cnt = _lib.meshopt_simplifyWithAttributes(
        dst.ctypes.data, I.ctypes.data, len(I), Pp.ctypes.data, n, 12, A.ctypes.data, k * 4, Wt.ctypes.data, len(Wt),
        None if lock is None else lock.ctypes.data, int(target_index_count), float(target_error), opts,
        err.ctypes.data)
    return dst[:cnt].astype(np.int64).reshape(-1, 3), float(err[0])
