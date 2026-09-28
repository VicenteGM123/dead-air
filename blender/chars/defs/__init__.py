"""Character definitions (ports of src/art/chars/<id>.js). Each module exposes DEF (the JS `export default`)."""
import importlib

IDS = ['duke', 'skip', 'roxy', 'penny', 'z_crew', 'z_reporter', 'z_disco', 'z_mom', 'z_sock', 'z_forecaster',
       'z_bigshot', 'boss_baron', 'example_sock']


def load_def(cid):
    mod = importlib.import_module('.' + cid, __name__)
    return mod.DEF
