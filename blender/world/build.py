# World build (the Blender half of src/world/level.js buildSteps): the station layout JSON, the batched graybox with
# per-area finishes, the brick shell and roofs, the ceiling fixtures, the exterior + night sky, the eight doors and
# the windows, exported to godot/assets/world/*.glb for godot/scripts/world/level.gd.
#
#   build_world(save_blend=False) -> list of written files
#   python3 blender/world/build.py [--save-blend]      (or build_all.py --only world)
#
# Outputs (node names are what the Godot level code looks up; ':' / '#' of the JS names become '_'):
#   godot/data/layout.json                 layout.py (SPEC §5.7)
#   godot/assets/world/architecture.glb    architecture -> area_<id> (floors, walls, trims, platforms, fence, window
#                                          frames window_<id> / climb_<id> / gate_<id>, fixture frames, the fixture
#                                          lens fixtures_<id> with "da".fixture, merged_* static meshes, batch_*
#                                          meshes) + ceiling_<id> (the area's ceiling; noMerge), shell (exterior
#                                          faces, copings, wall tops) + roof
#   godot/assets/world/exterior.glb        exterior_root -> exterior (ground, street, lamps: lamp_lenses/lamp_pools,
#                                          storefronts + sign_<text>, skyline + skyline_beacons, tower,
#                                          tower_beacons) and sky (sky_dome, sky_stars, sky_moon)
#   godot/assets/world/doors/<doorId>.glb  pivot -> frame, blocker (see doors.py)
#   godot/assets/world/boards.glb          boards -> boards_0..boards_5 (one plank per scenery slice)
#   godot/assets/textures/*.png            the canvas textures (dalib.tex.texture_file; materials carry mapFile)
# The build order is the JS one (architecture, exterior, doors, windows): the world surfaces share ONE seeded
# random stream in first-request order, so the textures come out identical to the browser's.

import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from world import wk, layout  # noqa: E402
from world.layout import AREAS, DOORS  # noqa: E402
from world.batch import Batch  # noqa: E402
from world.surfaces import createSurfaces, AREA_STYLE  # noqa: E402
from world.architecture import buildArchitecture  # noqa: E402
from world.exterior import buildExterior  # noqa: E402
from world.doors import buildDoor  # noqa: E402
from world.windows import buildWindows  # noqa: E402
from dalib import tex as dtex  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, '..', '..'))
OUT = os.path.join(REPO, 'godot', 'assets', 'world')

# level.js NO_CAST: batch surfaces that never cast into the key shadow map.
NO_CAST = set([s['floor'] for s in AREA_STYLE.values()] + ['metal_plate', 'trim_steel', 'chainlink', 'roof_gravel']
              + [s['ceiling'] for s in AREA_STYLE.values() if s.get('ceiling')])


def castOf(name, key):
    return key not in NO_CAST and name != 'ext' and '#' not in name


def build_graph(merge=True, surf_hook=None):
    """Builds the whole station graph (pure Python, no bpy). Returns the export roots (+ the batch buckets and the
    Surfaces object for checks). merge=False keeps every mesh as built (checks against the JS build)."""
    mats = wk.Mats()
    game = {'mats': mats, 'tex': dtex}
    surf = createSurfaces({'mats': mats, 'tex': dtex})
    if surf_hook:
        surf_hook(surf)
    batch = Batch(surf)
    arch = wk.group('architecture')
    groups = {}
    for a in AREAS:
        r = wk.group('area_' + a['id'])
        arch.add(r)
        groups[a['id']] = r
        c = wk.group('ceiling_' + a['id'])
        c.userData.noMerge = True
        r.add(c)
        groups[a['id'] + '#ceil'] = c
    shell = wk.group('shell')
    arch.add(shell)
    groups['shell'] = shell
    roof = wk.group('roof')
    shell.add(roof)
    groups['shell#roof'] = roof
    extRoot = wk.group('exterior_root')
    ext = wk.group('exterior')
    extRoot.add(ext)
    groups['ext'] = ext
    ctx = {'game': game, 'batch': batch, 'surf': surf, 'group': lambda n: groups[n]}

    buildArchitecture(ctx)
    ex = buildExterior(ctx)
    extRoot.add(ex['sky'])
    doors = [(d['id'], buildDoor(ctx, d)) for d in DOORS]
    win = buildWindows(ctx)

    buckets = [dict(b) for b in batch.buckets.values()]

    def emit(g, key, b):
        s = surf.get(key)
        m = wk.Mesh(wk.geometry(b['pos'], b['nrm'], b['uv'], b['col'], b['idx']), s['mat'])
        m.name = 'batch:%s:%s' % (g, key)
        m.castShadow = castOf(g, key)
        m.receiveShadow = True
        groups[g].add(m)
        return m
    batch.build(emit)

    # level.js merges every area root and the exterior per material (after the rooms). The placeholder tower and
    # its beacons stay separate nodes: the yard room replaces them at runtime.
    for a in (AREAS if merge else []):
        wk.mergeByMaterial(groups[a['id']], 'merged_' + a['id'])
    if merge:
        keep = [o for o in list(ext.children) if o.name in ('tower', 'tower_beacons')]
        for o in keep:
            ext.remove(o)
        wk.mergeByMaterial(ext, 'merged_ext')
        for o in keep:
            ext.add(o)
        wk.mergeByMaterial(shell, 'merged_shell')

    boards = wk.group('boards')
    for m in win['boards']:
        boards.add(m)
    return {'architecture': arch, 'exterior': extRoot, 'doors': doors, 'boards': boards, 'groups': groups,
            'buckets': buckets, 'surf': surf}


def build_world(save_blend=False, out_dir=None):
    t0 = time.time()
    out = out_dir or OUT
    written = [layout.write_json()]
    roots = build_graph()
    print('[world] graph built in %.1fs' % (time.time() - t0))
    written.append(wk.export_glb(roots['architecture'], os.path.join(out, 'architecture.glb'), 'architecture', save_blend))
    written.append(wk.export_glb(roots['exterior'], os.path.join(out, 'exterior.glb'), 'exterior_root', save_blend))
    written.append(wk.export_glb(roots['boards'], os.path.join(out, 'boards.glb'), 'boards', save_blend))
    for did, pivot in roots['doors']:
        written.append(wk.export_glb(pivot, os.path.join(out, 'doors', did + '.glb'), 'pivot', save_blend))
    print('[world] %d files in %.1fs' % (len(written), time.time() - t0))
    return written


if __name__ == '__main__':
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
    build_world(save_blend='--save-blend' in argv)
