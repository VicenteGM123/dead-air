"""Third-party modules for Blender's bundled Python (SPEC §5.1).

Blender ships numpy but not skia-python (Canvas 2D, dalib/canvas2d.py) nor uharfbuzz (text shaping/kerning like
Chrome). ensure() makes them importable: first from wherever they are already installed, else from
blender/_vendor/, else it runs `python -m pip install --target blender/_vendor skia-python uharfbuzz` with the
interpreter that is running (Blender's own Python when run inside Blender) and adds the folder to sys.path.
blender/_vendor/ is git-ignored; delete it to force a reinstall.
"""
import importlib
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
VENDOR = os.path.abspath(os.path.join(HERE, '..', '_vendor'))
# module name -> pip requirement
REQUIRED = {'skia': 'skia-python>=87.5'}
OPTIONAL = {'uharfbuzz': 'uharfbuzz'}

_done = False


def _add_path():
    if os.path.isdir(VENDOR) and VENDOR not in sys.path:
        sys.path.insert(0, VENDOR)


def _importable(mod):
    try:
        importlib.import_module(mod)
        return True
    except Exception:
        return False


def _pip(reqs):
    os.makedirs(VENDOR, exist_ok=True)
    py = sys.executable
    # inside Blender sys.executable is the blender binary on old versions; the python binary lives next to it
    if 'blender' in os.path.basename(py).lower():
        import glob
        cands = glob.glob(os.path.join(sys.prefix, 'bin', 'python*'))
        if cands:
            py = sorted(cands)[0]
    cmd = [py, '-m', 'pip', 'install', '--disable-pip-version-check', '--no-warn-script-location', '--upgrade',
           '--target', VENDOR] + reqs
    print('[dalib.vendor] installing', ' '.join(reqs), '->', VENDOR, flush=True)
    try:
        subprocess.check_call(cmd)
    except Exception:
        # Blender's Python may lack pip: bootstrap it first
        subprocess.call([py, '-m', 'ensurepip', '--upgrade'])
        subprocess.check_call(cmd)
    importlib.invalidate_caches()


def ensure():
    """Makes skia (required) and uharfbuzz (optional, kerning) importable."""
    global _done
    if _done:
        return
    _add_path()
    missing = [req for mod, req in REQUIRED.items() if not _importable(mod)]
    optional = [req for mod, req in OPTIONAL.items() if not _importable(mod)]
    if missing or optional:
        try:
            _pip(missing + optional)
        except Exception as e:  # optional packages may fail on exotic platforms
            if missing:
                raise RuntimeError('[dalib.vendor] could not install %s: %s' % (missing, e))
            print('[dalib.vendor] optional install failed (%s); text kerning disabled' % e)
        _add_path()
    for mod in REQUIRED:
        importlib.import_module(mod)
    _done = True
