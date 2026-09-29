"""Builds every runtime asset module in blender/runtime/ (static meshes that the JS game systems assembled at runtime).

Called by blender/build_all.py `--only runtime [--id <module>[,<module>...]]`.
Each module (boss.py, telly.py, rooms_lobby_green.py, ...) exposes build(save_blend=False, only=None, ...) and exports
its GLBs into godot/assets/runtime/<system>/. `--id` selects modules by file name (without .py).
"""
import importlib
import os
import traceback

HERE = os.path.dirname(os.path.abspath(__file__))


def modules():
    out = []
    for f in sorted(os.listdir(HERE)):
        if f.endswith('.py') and not f.startswith('_') and f != 'build.py':
            out.append(f[:-3])
    return out


def build(ids=None, save_blend=False, godot=None):
    wanted = None
    if ids:
        wanted = set()
        for i in ids:
            wanted.update(s.strip() for s in str(i).split(',') if s.strip())
    ok = True
    for name in modules():
        if wanted is not None and name not in wanted:
            continue
        try:
            mod = importlib.import_module('runtime.%s' % name)
            print('[runtime] %s' % name)
            if mod.build(save_blend=save_blend) is False:
                ok = False
        except Exception:
            traceback.print_exc()
            ok = False
    return ok
