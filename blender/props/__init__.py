"""DEAD AIR — prop library entry (port of src/props/index.js): the category modules register their builders with
dalib.kit.registerProp() when imported, exactly like the JS modules do.

    from props import load_all
    load_all()                      # imports every category module that exists
    from dalib.kit import buildProp, listProps, propMeta

CATEGORIES lists the ports of src/props/*.js (file name = JS module name, `_samples.js` -> samples.py). A module
that is missing or fails to import is reported and skipped, so the pipeline keeps working while the port is
incomplete. placeProp() (colliders / light anchors / screens wiring) is runtime code: godot/scripts/props/props.gd.
"""
import importlib
import sys
import traceback

CATEGORIES = ['broadcast', 'furniture', 'sets', 'weapons', 'machines', 'sponsors', 'outdoor', 'samples']
# + the props the room modules register (src/world/rooms/*.js registerProp calls, e.g. yard.js 'yard_*'):
#   blender/props/rooms_*.py, loaded after the categories (rooms may reuse category helpers)
import os as _os
CATEGORIES += sorted(f[:-3] for f in _os.listdir(_os.path.dirname(_os.path.abspath(__file__)))
                     if f.startswith('rooms_') and f.endswith('.py'))

_loaded = {}


def load_all(only=None, verbose=True):
    """Imports the category modules (all, or the names in `only`). Returns {name: module or None}."""
    for name in CATEGORIES:
        if only and name not in only:
            continue
        if name in _loaded:
            continue
        try:
            _loaded[name] = importlib.import_module('props.' + name)
        except ModuleNotFoundError as e:
            if e.name in ('props.' + name, name):
                _loaded[name] = None
                if verbose:
                    print('[props] category module props/%s.py not written yet: skipped' % name)
            else:
                _loaded[name] = None
                print('[props] ERROR importing props/%s.py:\n%s' % (name, traceback.format_exc()), file=sys.stderr)
        except Exception:
            _loaded[name] = None
            print('[props] ERROR importing props/%s.py:\n%s' % (name, traceback.format_exc()), file=sys.stderr)
    return dict(_loaded)
