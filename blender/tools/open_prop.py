"""Build one prop into the CURRENT Blender scene to look at it / tweak it (run from Blender's Scripting tab, or
`blender --python blender/tools/open_prop.py -- sample_portable_tv [--key sample_portable_tv__349] [--clear]`).

Unlike build_all.py it does not reset the file and does not export: it adds a collection named after the variant
key with the prop in it (three.js coordinates converted to Blender's Z-up, like the exporter). Edit the Python
builder (blender/props/<category>.py), then run this again (with --clear to replace the previous copy).
In the Scripting tab set PROP below instead of passing arguments.
"""
import os
import sys

PROP = 'sample_portable_tv'   # used when no argument is given (Scripting tab)

HERE = os.path.dirname(os.path.abspath(__file__))
BLENDER = os.path.abspath(os.path.join(HERE, '..'))
if BLENDER not in sys.path:
    sys.path.insert(0, BLENDER)


def main(argv):
    import bpy
    import importlib
    from props import load_all
    from dalib import kit as K, scene as S, tex as T, export
    # pick up edits made since the last run (Scripting tab keeps modules loaded)
    for name in list(sys.modules):
        if name.startswith('props.'):
            importlib.reload(sys.modules[name])
    load_all(verbose=False)
    pid = argv[0] if argv and not argv[0].startswith('--') else PROP
    key = argv[argv.index('--key') + 1] if '--key' in argv else None
    variants = [v for v in export.load_variants() if v['id'] == pid and (key is None or v['key'] == key)]
    v = variants[0] if variants else {'id': pid, 'opts': {}, 'key': pid}
    root = K.buildProp(v['id'], K.Game(), dict(v.get('opts') or {}))
    coll_name = v['key']
    old = bpy.data.collections.get(coll_name)
    if old is not None and '--clear' in argv:
        for ob in list(old.objects):
            bpy.data.objects.remove(ob, do_unlink=True)
        bpy.data.collections.remove(old)
        old = None
    coll = old or bpy.data.collections.new(coll_name)
    if coll.name not in bpy.context.scene.collection.children:
        bpy.context.scene.collection.children.link(coll)
    names = S.assign_names(root, root.name)
    # to_blender links into the scene collection: move the new objects into our collection afterwards
    before = set(bpy.data.objects)
    S.to_blender(root, names, T.texture_file, force_names=False)
    for ob in set(bpy.data.objects) - before:
        for c in list(ob.users_collection):
            c.objects.unlink(ob)
        coll.objects.link(ob)
    print('[open_prop] %s -> collection %s (%d objects)' % (v['key'], coll_name, len(coll.objects)))


if __name__ == '__main__':
    main(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
