"""DEAD AIR — Blender asset pipeline entry point (SPEC §5.1).

    blender --background --python blender/build_all.py -- [--only props|chars|world|runtime|textures]
                                                          [--id <id>[,<id>…]] [--key <variant key>] [--save-blend]
    cd /home/user/dead-air && python3 blender/build_all.py --only props --id telly     # bpy as a Python module
    (or open this file in Blender's Scripting tab and press Run: builds everything)

--only props     every variant of blender/props/variants.json (or of --id / --key) -> godot/assets/props/<key>.glb
                 + godot/assets/props/index.json; textures -> godot/assets/textures/*.png
--only textures  re-renders the canvas textures used by the selected props (no GLB export)
--only chars|world|runtime
                 delegates to blender/<section>/build.py: build(ids, save_blend, godot) (owned by those ports)
--save-blend     also saves blender/out/<key>.blend (git-ignored) to open and edit in Blender
--godot <dir>    write into another copy of the Godot project (tests), default /home/user/dead-air/godot
--list           print the registered prop ids per category and exit
"""
import argparse
import importlib
import os
import sys
import time
import traceback

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

SECTIONS = ['props', 'chars', 'world', 'runtime', 'textures']


def _argv():
    if '--' in sys.argv:
        return sys.argv[sys.argv.index('--') + 1:]
    if os.path.basename(sys.argv[0] if sys.argv else '').lower().startswith('blender'):
        return []  # run from Blender's UI / without script args
    return sys.argv[1:]


def parse(argv=None):
    ap = argparse.ArgumentParser(prog='build_all.py', description='DEAD AIR Blender asset pipeline')
    ap.add_argument('--only', choices=SECTIONS, action='append', help='section(s) to build (default: all)')
    ap.add_argument('--id', action='append', default=[], help='prop / char id (repeatable or comma-separated)')
    ap.add_argument('--key', action='append', default=[], help='prop variant key (e.g. telly__012)')
    ap.add_argument('--save-blend', action='store_true', help='also save blender/out/<key>.blend')
    ap.add_argument('--godot', default=None, help='Godot project root to write into (default: ../godot)')
    ap.add_argument('--stop-on-error', action='store_true')
    ap.add_argument('--list', action='store_true', help='list registered props and exit')
    a = ap.parse_args(argv)
    a.id = [x for s in a.id for x in s.split(',') if x]
    a.key = [x for s in a.key for x in s.split(',') if x]
    return a


def _redirect(godot):
    from dalib import export, tex
    godot = os.path.abspath(godot)
    export.GODOT = godot
    export.PROPS_OUT = os.path.join(godot, 'assets', 'props')
    tex.OUT_DIR = os.path.join(godot, 'assets', 'textures')
    tex._index = None


def build_props(a):
    from dalib import export
    ok, failed = export.build_props(ids=a.id or None, keys=a.key or None, out_dir=export.PROPS_OUT,
                                    save_blend=a.save_blend, stop_on_error=a.stop_on_error)
    print('[props] %d built, %d failed -> %s' % (len(ok), len(failed), export.PROPS_OUT))
    for k, why in failed:
        print('  FAILED %s: %s' % (k, why.strip().splitlines()[-1] if why else ''))
    return not failed


def build_textures(a):
    from props import load_all
    from dalib import kit as K, export, tex
    load_all()
    variants = export.load_variants()
    game = K.Game()
    n = 0
    for v in variants:
        if (a.id and v['id'] not in a.id) or (a.key and v['key'] not in a.key) or v['id'] not in K.PROPS:
            continue
        root = K.buildProp(v['id'], game, dict(v.get('opts') or {}))
        seen = set()

        def f(o):
            nonlocal n
            mt = getattr(o, 'material', None)
            t = getattr(mt, 'map', None) if mt is not None else None
            if t is not None and id(t) not in seen:
                seen.add(id(t))
                if tex.texture_file(t):
                    n += 1
        root.traverse(f)
    print('[textures] %d textures written -> %s' % (n, tex.OUT_DIR))
    return True


def build_section(name, a):
    """chars / world / runtime: blender/<name>/build.py exposes build(ids, save_blend, godot)."""
    try:
        mod = importlib.import_module('%s.build' % name)
    except ModuleNotFoundError as e:
        print('[%s] blender/%s/build.py not written yet: skipped (%s)' % (name, name, e))
        return True
    from dalib import export
    return mod.build(ids=a.id or None, save_blend=a.save_blend, godot=export.GODOT) is not False


def main(argv=None):
    a = parse(_argv() if argv is None else argv)
    if a.godot:
        _redirect(a.godot)
    if a.list:
        from props import load_all
        from dalib import kit as K
        load_all()
        cats = {}
        for p in K.listProps():
            cats.setdefault(p['category'], []).append(p['id'])
        for c, ids in cats.items():
            print('%s (%d): %s' % (c, len(ids), ' '.join(ids)))
        return 0
    only = a.only or ['props', 'chars', 'world', 'runtime']
    t0 = time.time()
    ok = True
    for sec in only:
        try:
            if sec == 'props':
                ok &= build_props(a)
            elif sec == 'textures':
                ok &= build_textures(a)
            else:
                ok &= build_section(sec, a)
        except Exception:
            traceback.print_exc()
            ok = False
    print('[build_all] done in %.1fs%s' % (time.time() - t0, '' if ok else ' (with errors)'))
    return 0 if ok else 1


if __name__ == '__main__':
    rc = main()
    if '--' in sys.argv or not os.path.basename(sys.argv[0]).lower().startswith('blender'):
        sys.exit(rc)
