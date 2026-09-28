"""Compare two prop GLBs vertex by vertex (e.g. the JS reference $REF/props/<key>.glb and ours):

    python3 blender/tools/compare_glb.py $REF/props/telly__012.glb godot/assets/props/telly__012.glb

Meshes are matched by node name (':' '.' etc. sanitized like dalib does), vertices by world position + normal
(vertex order and duplicates differ between three's exporter and Blender's). Reports per mesh: vertex/triangle counts
and the max difference of POSITION / NORMAL / TEXCOORD_0 / COLOR_0 (linear) over the matched vertices. UVs are
compared as glTF sees them after each file's texture transform, i.e. a reference exported from a flipY canvas
(images flipped by THREE.GLTFExporter, uv as is) equals ours (uv as is, KHR_texture_transform flip).
No Blender needed (numpy only).
"""
import json
import os
import re
import struct
import sys

import numpy as np

CT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NC = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}


def load(path):
    with open(path, 'rb') as f:
        data = f.read()
    off = 12
    js, bin_ = None, b''
    while off < len(data):
        n, t = struct.unpack_from('<I4s', data, off)
        c = data[off + 8:off + 8 + n]
        if t == b'JSON':
            js = json.loads(c)
        else:
            bin_ = c
        off += 8 + n
    return js, bin_


def accessor(js, bin_, i):
    a = js['accessors'][i]
    bv = js['bufferViews'][a['bufferView']]
    dt = np.dtype(CT[a['componentType']])
    nc = NC[a['type']]
    stride = bv.get('byteStride') or dt.itemsize * nc
    start = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
    raw = np.frombuffer(bin_, dtype=np.uint8, count=stride * (a['count'] - 1) + dt.itemsize * nc, offset=start)
    out = np.empty((a['count'], nc), dtype=np.float64)
    for k in range(a['count']):
        out[k] = np.frombuffer(raw[k * stride:k * stride + dt.itemsize * nc].tobytes(), dtype=dt)
    if a.get('normalized'):
        if dt == np.uint8:
            out /= 255.0
        elif dt == np.uint16:
            out /= 65535.0
    return out


def trs(node):
    if 'matrix' in node:
        return np.array(node['matrix'], dtype=np.float64).reshape(4, 4).T
    t = node.get('translation', [0, 0, 0])
    x, y, z, w = node.get('rotation', [0, 0, 0, 1])
    s = node.get('scale', [1, 1, 1])
    r = np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                  [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                  [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
    m = np.eye(4)
    m[:3, :3] = r * np.array(s)[None, :]
    m[:3, 3] = t
    return m


def sanitize(n):
    n = re.sub(r'[^A-Za-z0-9_\-]+', '_', n or '').strip('_')
    return n


def meshes(path):
    js, bin_ = load(path)
    out = []
    scene = js['scenes'][js.get('scene', 0)]

    def walk(i, parent):
        nd = js['nodes'][i]
        m = parent @ trs(nd)
        if 'mesh' in nd:
            for p in js['meshes'][nd['mesh']]['primitives']:
                at = p['attributes']
                pos = accessor(js, bin_, at['POSITION'])
                P = (np.c_[pos, np.ones(len(pos))] @ m.T)[:, :3]
                N = accessor(js, bin_, at['NORMAL']) @ np.linalg.inv(m[:3, :3]).T if 'NORMAL' in at else None
                if N is not None:
                    N /= np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-12)
                uv = accessor(js, bin_, at['TEXCOORD_0']) if 'TEXCOORD_0' in at else None
                col = accessor(js, bin_, at['COLOR_0'])[:, :3] if 'COLOR_0' in at else None
                idx = accessor(js, bin_, p['indices'])[:, 0].astype(int) if 'indices' in p else np.arange(len(P))
                out.append({'name': sanitize(nd.get('name', '')), 'P': P, 'N': N, 'uv': uv, 'col': col,
                            'tris': len(idx) // 3})
        for c in nd.get('children', []):
            walk(c, m)
    for r in scene['nodes']:
        walk(r, np.eye(4))
    return out


def _match(m, o):
    """For every vertex of m: the vertex of o at the same position whose normal/uv/colour are closest."""
    kb = {}
    for i, k in enumerate(map(tuple, np.round(o['P'] * 1e4).astype(np.int64))):
        kb.setdefault(k, []).append(i)
    ia, ib = [], []
    for i, k in enumerate(map(tuple, np.round(m['P'] * 1e4).astype(np.int64))):
        c = kb.get(k)
        if not c:
            continue
        if len(c) == 1:
            j = c[0]
        else:
            cost = np.zeros(len(c))
            for key in ('N', 'uv', 'col'):
                if m[key] is not None and o[key] is not None:
                    cost += np.abs(o[key][c] - m[key][i]).sum(axis=1)
            j = c[int(np.argmin(cost))]
        ia.append(i)
        ib.append(j)
    return np.array(ia, dtype=int), np.array(ib, dtype=int)


def _bbox(m):
    return np.r_[m['P'].min(axis=0), m['P'].max(axis=0)] if len(m['P']) else np.zeros(6)


def compare(a_path, b_path, verbose=True):
    A, B = meshes(a_path), meshes(b_path)
    unused = list(range(len(B)))
    pairs = []
    # 1) same (sanitized) name  2) unnamed / renamed: same triangle count and bbox
    for m in A:
        j = next((j for j in unused if B[j]['name'] == m['name'] and m['name']), None)
        if j is None:
            best = None
            for j2 in unused:
                if B[j2]['tris'] == m['tris']:
                    d = np.abs(_bbox(B[j2]) - _bbox(m)).max()
                    if d < 0.02 and (best is None or d < best[0]):
                        best = (d, j2)
            j = best[1] if best else None
        if j is not None:
            unused.remove(j)
        pairs.append((m, B[j] if j is not None else None))
    worst = {'pos': 0, 'nor': 0, 'uv': 0, 'col': 0}
    rows = []
    for m, o in pairs:
        label = '%s -> %s' % (m['name'] or '(unnamed)', o['name'] if o else '-')
        if o is None:
            rows.append('%-44s only in A (tris %d)' % (label, m['tris']))
            continue
        ia, ib = _match(m, o)
        cover = len(ia) / max(1, len(m['P']))
        d = {}
        bad = 0
        if len(ia):
            d['pos'] = np.abs(m['P'][ia] - o['P'][ib]).max()
            for k, key in (('nor', 'N'), ('uv', 'uv'), ('col', 'col')):
                if m[key] is not None and o[key] is not None:
                    e = np.abs(m[key][ia] - o[key][ib]).max(axis=1)
                    d[k] = e.max()
                    bad = max(bad, int((e > 1e-3).sum()))
                elif (m[key] is None) != (o[key] is None):
                    d[k] = float('nan')
        for k, v in d.items():
            if v == v:
                worst[k] = max(worst[k], v)
        rows.append('%-44s tris %5d/%5d  matched %5.1f%%  %s  (verts off >1e-3: %d)' % (
            label, m['tris'], o['tris'], cover * 100, '  '.join('%s %.4f' % (k, v) for k, v in d.items()), bad))
    for j in unused:
        rows.append('%-44s only in B (tris %d)' % ('- -> ' + B[j]['name'], B[j]['tris']))
    if verbose:
        print('\n'.join(rows))
        print('worst:', {k: round(float(v), 5) for k, v in worst.items()})
    return worst


if __name__ == '__main__':
    compare(sys.argv[1], sys.argv[2])
