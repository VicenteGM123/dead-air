"""Compare a Python-built prop with the JS reference dump ($REF/props/<key>.json).

    python3 blender/tools/compare_ref.py sample_portable_tv            # every variant of that id
    python3 blender/tools/compare_ref.py sample_portable_tv__349 -v    # one variant, per-mesh details
    python3 blender/tools/compare_ref.py --all                         # every registered id (summary)
    python3 blender/tools/compare_ref.py telly__012 --dump /tmp/me.json  # also write our stats (same format)

No Blender needed: builds the kit graph (the thing exported to the GLB) and computes the same stats the JS dump
records (bbox, tris, meshes, per-mesh path / tris / bbox / material, materials, root userData). Checks: bbox within
±1 cm, tris within ±10 % (exact is better), userData keys, parts / screens / anchors / colliders / lightAnchors /
interact (numbers ±1 cm), materials (type, colour, map, vertexColors, transparent, opacity, side), and per-mesh
matches by path (three's `name#index/...`: same structure as the JS when the port is faithful).
Exit code 0 when every compared variant passes.
"""
import argparse
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BLENDER = os.path.abspath(os.path.join(HERE, '..'))
if BLENDER not in sys.path:
    sys.path.insert(0, BLENDER)

DEFAULT_REF = os.environ.get('REF', '/tmp/claude-0/-home-user-dead-air/8458c55b-456c-5c02-b3dd-b7ced50b0561/scratchpad/ref')
BBOX_TOL = 0.01
TRIS_TOL = 0.10
NUM_TOL = 0.01


def r4(x):
    return round(x * 1e4) / 1e4


# ============================================================================================= our stats
def path_of(o, root):
    a = []
    q = o
    while q is not None and q is not root:
        a.insert(0, '%s#%d' % (q.name or q.type, q.parent.children.index(q)))
        q = q.parent
    return '/'.join(a)


def mat_info(m):
    from dalib.scene import Material
    if not isinstance(m, Material):
        return {'type': getattr(m, 'type', '?')}
    t = m.map if m.map is not None else getattr(m, '_card', None)
    mp = None
    if t is not None:
        mp = getattr(t, 'name', None) or getattr(t, 'card', None) or 'tex'
    return {'type': m.type, 'name': m.name, 'kind': m.kind,
            'color': None if m.type == 'ShaderMaterial' else '#' + m.color.getHexString(),
            'emissive': ('#' + m.emissive.getHexString()) if m.type == 'MeshStandardMaterial' else None,
            'emissiveIntensity': m.emissiveIntensity if m.type == 'MeshStandardMaterial' else None,
            'roughness': m.roughness if m.type == 'MeshStandardMaterial' else None,
            'metalness': m.metalness if m.type == 'MeshStandardMaterial' else None,
            'map': mp, 'vertexColors': bool(m.vertexColors), 'transparent': bool(m.transparent),
            'opacity': m.opacity, 'side': m.side}


def our_stats(root, v):
    from dalib.scene import box_from_object, jsonable
    root.updateMatrixWorld(True)
    from dalib.mathutils3 import Matrix4
    inv = Matrix4().copy(root.matrixWorld).invert()
    mats, meshes = {}, []
    total = 0.0

    def mi(m):
        if m.uuid not in mats:
            d = mat_info(m)
            d['idx'] = len(mats)
            mats[m.uuid] = d
        return mats[m.uuid]['idx']

    def f(o):
        nonlocal total
        if not (getattr(o, 'isMesh', False) or getattr(o, 'isLine', False) or getattr(o, 'isPoints', False)):
            return
        g = o.geometry
        pos = g.attributes.position
        if g.boundingBox is None:
            g.computeBoundingBox()
        m4 = Matrix4().multiplyMatrices(inv, o.matrixWorld)
        bb = g.boundingBox.clone().applyMatrix4(m4)
        nt = (g.index.count if g.index is not None else pos.count) / 3
        inst = getattr(o, 'isInstancedMesh', False)
        total += nt * (o.count if inst else 1)
        mat = o.material if isinstance(o.material, list) else [o.material]
        meshes.append({'path': path_of(o, root), 'type': o.type, 'verts': pos.count, 'tris': nt,
                       'instances': o.count if inst else None,
                       'bbox': [[r4(x) for x in bb.min.toArray()], [r4(x) for x in bb.max.toArray()]],
                       'mat': [mi(m) for m in mat], 'visible': o.visible,
                       'userData': jsonable(o.userData, None, strict=False) or None})
    root.traverse(f)

    def conv(x, d=0):
        if d > 5:
            return None
        if getattr(x, 'isObject3D', False):
            return {'__node': path_of(x, root)}
        if isinstance(x, dict):
            return {k: conv(val, d + 1) for k, val in x.items()}
        if isinstance(x, (list, tuple)):
            return [conv(val, d + 1) for val in x]
        return jsonable(x, None, strict=False)
    bb = box_from_object(root)
    return {'id': v['id'], 'opts': v.get('opts'), 'key': v['key'], 'userData': conv(root.userData),
            'bbox': [[r4(x) for x in bb.min.toArray()], [r4(x) for x in bb.max.toArray()]],
            'tris': total, 'meshCount': len(meshes), 'materials': sorted(mats.values(), key=lambda d: d['idx']),
            'meshes': meshes}


# ================================================================================================ diffing
def _num(a):
    return isinstance(a, (int, float)) and not isinstance(a, bool)


def deep_diff(a, b, path, out, tol=NUM_TOL):
    """Differences between reference `a` and ours `b` (numbers within tol; node refs by leaf name)."""
    if isinstance(a, dict) and '__node' in a:
        an = a['__node'].split('/')[-1].split('#')[0] if a['__node'] else ''
        bn = (b or {}).get('__node', '') if isinstance(b, dict) else ''
        bn = bn.split('/')[-1].split('#')[0] if bn else ''
        if an != bn:
            out.append('%s: node %r vs ours %r' % (path, a['__node'], (b or {}).get('__node') if isinstance(b, dict)
                                                   else b))
        return
    if _num(a) and _num(b):
        if abs(a - b) > tol:
            out.append('%s: %s vs ours %s' % (path, a, b))
        return
    if isinstance(a, dict) and isinstance(b, dict):
        for k in a:
            if k not in b:
                out.append('%s.%s: missing in ours (ref %s)' % (path, k, json.dumps(a[k])[:80]))
            else:
                deep_diff(a[k], b[k], '%s.%s' % (path, k), out, tol)
        for k in b:
            if k not in a:
                out.append('%s.%s: extra in ours (%s)' % (path, k, json.dumps(b[k])[:80]))
        return
    if isinstance(a, list) and isinstance(b, list):
        if len(a) != len(b):
            out.append('%s: %d items vs ours %d' % (path, len(a), len(b)))
        for i, (x, y) in enumerate(zip(a, b)):
            deep_diff(x, y, '%s[%d]' % (path, i), out, tol)
        return
    if isinstance(a, str) and isinstance(b, str) and a.lower() == b.lower():
        return
    if a != b:
        out.append('%s: %s vs ours %s' % (path, json.dumps(a)[:80], json.dumps(b)[:80]))


def mat_sig(m):
    return (m.get('type'), (m.get('color') or '').lower(), m.get('map') or None, bool(m.get('vertexColors')),
            bool(m.get('transparent')), round(float(m.get('opacity') or 1), 3), m.get('side') or 0)


def compare(ref, ours, verbose=False):
    lines = []
    ok = True
    # bbox
    bd = max(abs(a - b) for ra, rb in zip(ref['bbox'], ours['bbox']) for a, b in zip(ra, rb))
    if bd > BBOX_TOL:
        ok = False
    lines.append('bbox   %s  ref %s  ours %s  (max diff %.4f m)' % ('OK ' if bd <= BBOX_TOL else 'BAD', ref['bbox'],
                                                                      ours['bbox'], bd))
    # tris
    rt, ot = ref['tris'], ours['tris']
    rel = abs(ot - rt) / max(1, rt)
    if rel > TRIS_TOL:
        ok = False
    lines.append('tris   %s  ref %d  ours %d  (%+.1f %%)' % ('OK ' if rel <= TRIS_TOL else 'BAD', rt, ot,
                                                            (ot - rt) / max(1, rt) * 100))
    lines.append('meshes     ref %d  ours %d' % (ref['meshCount'], ours['meshCount']))
    # userData
    ud = []
    deep_diff(ref['userData'], ours['userData'], 'userData', ud)
    # stats are informative (merge differences show up in meshes/mats)
    ud_hard = [x for x in ud if not x.startswith('userData.stats')]
    if ud_hard:
        ok = False
    lines.append('userData %s' % ('OK' if not ud_hard else 'DIFF (%d)' % len(ud_hard)))
    for x in ud[:60]:
        lines.append('    ' + x)
    # materials
    rs = sorted(mat_sig(m) for m in ref['materials'])
    osg = sorted(mat_sig(m) for m in ours['materials'])
    miss = [s for s in rs if s not in osg]
    extra = [s for s in osg if s not in rs]
    lines.append('materials  ref %d  ours %d%s' % (len(rs), len(osg), '' if not (miss or extra) else '  (differences)'))
    for s in miss:
        lines.append('    missing in ours: %s' % (s,))
    for s in extra:
        lines.append('    extra in ours:   %s' % (s,))
    # meshes by path
    rm = {m['path']: m for m in ref['meshes']}
    om = {m['path']: m for m in ours['meshes']}
    only_r = [p for p in rm if p not in om]
    only_o = [p for p in om if p not in rm]
    bad = []
    for p in rm:
        if p in om:
            a, b = rm[p], om[p]
            d = max(abs(x - y) for ra, rb in zip(a['bbox'], b['bbox']) for x, y in zip(ra, rb)) if a['bbox'] and \
                b['bbox'] else 0
            if abs(a['tris'] - b['tris']) > 0.1 * max(1, a['tris']) or d > BBOX_TOL:
                bad.append((p, a['tris'], b['tris'], d))
    lines.append('mesh paths: %d matched, %d only in ref, %d only in ours, %d differ' % (
        len(rm) - len(only_r), len(only_r), len(only_o), len(bad)))
    if verbose or only_r or only_o or bad:
        for p in only_r[:40]:
            m = rm[p]
            lines.append('    only ref : %-60s tris %5d bbox %s' % (p, m['tris'], m['bbox']))
        for p in only_o[:40]:
            m = om[p]
            lines.append('    only ours: %-60s tris %5d bbox %s' % (p, m['tris'], m['bbox']))
        for p, a, b, d in bad[:40]:
            lines.append('    differs  : %-60s tris %d vs %d, bbox diff %.4f' % (p, a, b, d))
    return ok, lines


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('what', nargs='*', help='prop id(s) or variant key(s)')
    ap.add_argument('--ref', default=DEFAULT_REF)
    ap.add_argument('--all', action='store_true')
    ap.add_argument('-v', '--verbose', action='store_true')
    ap.add_argument('--dump', help='write our stats JSON here (single variant)')
    a = ap.parse_args()
    from props import load_all
    from dalib import kit as K
    from dalib import export
    load_all(verbose=False)
    variants = export.load_variants()
    if a.all:
        todo = [v for v in variants if v['id'] in K.PROPS]
    else:
        todo = [v for v in variants if v['id'] in a.what or v['key'] in a.what]
    if not todo:
        print('nothing to compare (unknown id/key or not registered)')
        return 2
    game = K.Game()
    n_ok = 0
    for v in todo:
        rp = os.path.join(a.ref, 'props', v['key'] + '.json')
        if not os.path.exists(rp):
            print('== %s: no reference %s' % (v['key'], rp))
            continue
        with open(rp) as f:
            ref = json.load(f)
        try:
            root = K.buildProp(v['id'], game, json.loads(json.dumps(v.get('opts') or {})))
        except Exception as e:
            import traceback
            print('== %s: BUILD FAILED\n%s' % (v['key'], traceback.format_exc()))
            continue
        ours = our_stats(root, v)
        if a.dump:
            with open(a.dump, 'w') as f:
                json.dump(ours, f, indent=1)
        ok, lines = compare(ref, ours, a.verbose)
        n_ok += ok
        print('== %s %s' % (v['key'], 'PASS' if ok else 'FAIL'))
        if not (a.all and ok):
            for ln in lines:
                print('  ' + ln)
    print('%d/%d variants pass' % (n_ok, len(todo)))
    return 0 if n_ok == len(todo) else 1


if __name__ == '__main__':
    sys.exit(main())
