# Station architecture meshes (port of src/world/architecture.js): floors with edge AO, walls with per-area finishes
# (wainscot, chair rail, baseboard, crown), the brick exterior shell with block plinth and coping, ceilings with their
# light fixtures (troffers, recessed cans, studio pipe grids), door thresholds, MC floor plates, the Studio A stage
# and stair, the newsroom riser, the bleachers and their side rails, the Yard chain-link fence and the roofs.
# Everything static goes through the world-UV Batch; fixtures that change at Sign-On are returned as records.
#
# buildArchitecture(ctx) -> { 'fixtures': [{ area, mesh, pre, post, anchors:[{ id, pre, post }], center, dist }] }
#   ctx = { game: { mats, tex, lights }, batch, surf, group(name) -> Group }  batch groups: '<area>', '<area>#ceil',
#   'shell', 'shell#roof'. pre/post = { mat } for the fixture mesh and { color, intensity } for its light anchors;
#   dist = metres from the Sign-On lever to the nearest point of the area (the color wave reaches it at dist/15 s).
# The fixture lens mesh of each area is named fixtures_<areaId> (JS 'fixtures:<areaId>') and carries the record in
# userData.fixture (exported as the node's "da": {fixture: {area, pre: <spec>, post: <spec>, anchors: [{id, pos,
# pre:{color,intensity}, post:{color,intensity}, distance}], center, dist}}): godot/scripts/world/architecture.gd
# rebuilds the switch records and registers the light anchors (game.lights.addAnchor) at runtime.

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from world import wk  # noqa: E402
from world.wk import geo, THREE  # noqa: E402
from world.layout import (AREAS, WALLS, WALL_T, ROOF_T, FENCE_H, PLATFORMS, BLOCKERS, FLOOR_PATCHES, DOORS,  # noqa: E402
                          WINDOWS, ANCHORS)
from world.shell import segmentBox  # noqa: E402
from world.surfaces import AREA_STYLE, EXTERIOR_STYLE  # noqa: E402

PI = math.pi
H = WALL_T / 2
AREA = {a['id']: a for a in AREAS}


def indoor(id):
    return bool(id) and not AREA[id].get('sky')


WALL_AO = 0.42
EXT_AO = 0.3
FLOOR_BORDER = 0.7
FLOOR_AO = 0.36
_lv = ANCHORS['sign_on_lever']['pos']
LEVER = (_lv[0], 1, _lv[2])
WALL_TOP_DROP = 0.004   # interior wall tops sit this far under the roof that covers them (no z-fight)

# Openings whose frame wraps the wall: every door casing (doors.py) and every boarded-window frame (windows.py).
# The frame's inner faces cover the wall's jamb caps, its head covers the lintel soffit and its sill board covers
# the sill top, in exactly the same planes: drawn together they z-fight (the flickering door frames). Those wall
# faces are therefore not emitted; the frame is the visible surface. cover = height up to which the sill piece,
# the frame and the lintel piece hide a neighbouring wall end (the lintel top).
FRAMED = [{'id': d['id'], 'line': d['line'], 'span': d['span'], 'lo': 0, 'hi': d['height']} for d in DOORS] + \
    [{'id': w['id'], 'line': w['line'], 'span': w['span'], 'lo': w['sill'], 'hi': w['top']} for w in WINDOWS if w['type'] == 'boarded']
for _f in FRAMED:
    _lintel = next((s for s in WALLS if s[7] and s[7]['opening'] == _f['id'] and s[4] > 0), None)
    _f['cover'] = _lintel[5] if _lintel else _f['hi']
FRAMED_ID = {f['id']: f for f in FRAMED}


def near(a, b):
    return abs(a - b) < 1e-6


def framedAt(axis, at, end):
    """The framed opening whose side lies at `end` on the wall line (axis, at), or None."""
    return next((f for f in FRAMED if f['line'][0] == axis and near(f['line'][1], at)
                 and (near(f['span'][0], end) or near(f['span'][1], end))), None)


def buildArchitecture(ctx):
    floors(ctx)
    walls(ctx)
    ceilings(ctx)
    platforms(ctx)
    roofs(ctx)
    return {'fixtures': [fixtures(ctx, a) for a in AREAS if indoor(a['id'])]}


# --------------------------------------------------------------------------------------------------- floors
def floors(ctx):
    batch = ctx['batch']
    for a in AREAS:
        x0, z0, x1, z1 = a['rect']
        outdoor = not indoor(a['id'])
        batch.hface(a['id'], AREA_STYLE[a['id']]['floor'], x0, z0, x1, z1, 0, True,
                    border=0 if outdoor else FLOOR_BORDER, ao=FLOOR_AO)
    for p in FLOOR_PATCHES:
        x0, z0, x1, z1 = p['rect']
        batch.hface('master_control', 'metal_plate', x0, z0, x1, z1, 0.006, True)
    # Door thresholds: a steel strip across each doorway hides the floor-material change on the wall line.
    for d in DOORS:
        axis, at = d['line']
        s0, s1 = d['span']
        if axis == 'x':
            batch.hface(d['areas'][0], 'trim_steel', at - 0.22, s0, at + 0.22, s1, 0.012, True)
        else:
            batch.hface(d['areas'][0], 'trim_steel', s0, at - 0.22, s1, at + 0.22, 0.012, True)


# ---------------------------------------------------------------------------------------------------- walls
def baseKey(owner):
    return EXTERIOR_STYLE['base'] if owner == 'shell' else AREA_STYLE[owner]['wall']['base']


def walls(ctx):
    batch = ctx['batch']
    for seg in WALLS:
        y0, y1, kind, meta = seg[4], seg[5], seg[6], seg[7]
        if kind == 'fence':
            fence(ctx, seg)
            continue
        if kind == 'glass':
            boothGlass(ctx, seg)
            continue
        alongX = seg[1] == seg[3]
        axis = 'z' if alongX else 'x'
        at = seg[1] if alongX else seg[0]
        mn, mx = segmentBox(seg, H, H)
        a0 = mn[0] if alongX else mn[2]
        a1 = mx[0] if alongX else mx[2]
        # The framed opening at each end (a sill/lintel piece is framed at both ends by its own opening).
        own = FRAMED_ID.get(meta['opening']) if meta['opening'] else None
        framed = [(own or framedAt(axis, at, a0 if i == 0 else a1)) if jamb else None for i, jamb in enumerate(meta['jambs'])]
        for i, area in enumerate(meta['sides']):
            sign = -1 if i == 0 else 1
            plane = at + sign * H
            if indoor(area):
                indoorFace(ctx, area, axis, plane, sign, a0, a1, y0, y1, framed, meta['jambs'])
            else:
                exteriorFace(ctx, axis, plane, sign, a0, a1, y0, y1)
        owner = meta['sides'][0] if indoor(meta['sides'][0]) else meta['sides'][1] if indoor(meta['sides'][1]) else 'shell'
        exterior = any(not indoor(s) for s in meta['sides'])
        sill = bool(meta['opening']) and y0 == 0
        if sill:
            if not own:
                batch.hface(owner, baseKey(owner), mn[0], mn[2], mx[0], mx[2], y1, True)   # framed: the sill board
        elif exterior:
            batch.box('shell', EXTERIOR_STYLE['cap'], [mn[0] - 0.05, y1, mn[2] - 0.05], [mx[0] + 0.05, y1 + 0.1, mx[2] + 0.05],
                      skip={'ny': True})
        else:
            # Interior wall top: the taller side's roof (roofs(), extended by H) covers it in the very same plane.
            roofY = max(AREA[s]['ceilY'] for s in meta['sides']) + ROOF_T
            batch.hface('shell', EXTERIOR_STYLE['cap'], mn[0], mn[2], mx[0], mx[2], y1 - WALL_TOP_DROP if near(y1, roofY) else y1, True)
        # Soffit under a lintel (a framed opening's head covers it).
        if y0 > 0 and not (own and near(y0, own['hi'])):
            batch.hface(owner, baseKey(owner), mn[0], mn[2], mx[0], mx[2], y0, False)
        # Jamb caps: the wall ends facing an opening. Next to a framed opening the sill piece, the frame's inner face
        # and the lintel piece hide the end up to the lintel top; only what rises above it (if anything) is drawn.
        # (A sill/lintel piece's own end caps face into the neighbouring wall piece and are kept as they were.)
        for i, jamb in enumerate(meta['jambs']):
            if not jamb:
                continue
            end = a0 if i == 0 else a1
            lo = max(y0, framed[i]['cover']) if framed[i] and not own else y0
            if y1 - lo < 1e-4:
                continue
            batch.vface(owner, baseKey(owner), 'x' if alongX else 'z', end, -1 if i == 0 else 1, at - H, at + H, lo, y1)


# Inside finish of one wall face: wainscot + upper wall, baseboard, chair rail, crown; above this area's ceiling
# the face belongs to the exterior shell (seen from the Yard over lower roofs).
# framed = [opening at a0 | None, opening at a1 | None]: trim ends there lose their end cap (see trim()).
# jambs = [a0 faces an opening, a1 faces an opening]: every other end runs H into a junction (segmentBox), so its
# trim end cap would lie exactly in the far face of the crossing wall (next room / exterior): never drawn.
def indoorFace(ctx, area, axis, plane, sign, a0, a1, y0, y1, framed=(None, None), jambs=(True, True)):
    batch = ctx['batch']
    st = AREA_STYLE[area]['wall']
    ceil = AREA[area]['ceilY']
    top = min(y1, ceil)
    if y1 - ceil > ROOF_T + 0.01:
        exteriorFace(ctx, axis, plane, sign, a0, a1, max(y0, ceil), y1)
    if top <= y0:
        return
    wH = st['wainscotH'] if st.get('wainscot') else 0
    o = {'ao': WALL_AO, 'top': ceil}
    if wH > y0:
        batch.vface(area, st['wainscot'], axis, plane, sign, a0, a1, y0, min(wH, top), **o)
    if top > max(y0, wH):
        batch.vface(area, st['base'], axis, plane, sign, a0, a1, max(y0, wH), top, **o)

    def trim(key, ya, yb, depth, onFloor):
        lo, hi = min(plane, plane + sign * depth), max(plane, plane + sign * depth)
        mn = [a0, ya, lo] if axis == 'z' else [lo, ya, a0]
        mx = [a1, yb, hi] if axis == 'z' else [hi, yb, a1]
        back = ('nz' if sign > 0 else 'pz') if axis == 'z' else ('nx' if sign > 0 else 'px')
        skip = {back: True, 'ny': onFloor}
        # At a framed opening the trim runs into the casing/frame (5 cm proud, deeper than any trim: it swallows the
        # end) or into the sill/lintel piece's identical trim; the end cap would only sit in the frame's inner-face
        # plane (z-fight), so it is dropped. A trim straddling the frame's top or bottom keeps it.

        def cap(i):
            return ('px' if i else 'nx') if axis == 'z' else ('pz' if i else 'nz')
        for i, f in enumerate(framed):
            if not f or (ya < f['lo'] - 1e-6 and yb > f['lo'] + 1e-6) or (ya < f['hi'] - 1e-6 and yb > f['hi'] + 1e-6):
                continue
            skip[cap(i)] = True
        for i, jamb in enumerate(jambs):
            if not jamb:
                skip[cap(i)] = True
        batch.box(area, key, mn, mx, skip=skip)
    if y0 == 0:
        trim(st['baseboard'], 0, 0.16, 0.035, True)
    # Chair rail 3.7 cm deep: wall-mounted lightboxes/posters hang their face 4 cm off the wall and stay in front.
    if st.get('rail') and wH > y0 and wH < top:
        trim(st['rail'], wH - 0.035, wH + 0.035, 0.037, False)
    if st.get('crown') and top == ceil:
        trim(st['crown'], ceil - 0.14, ceil, 0.05, False)


def exteriorFace(ctx, axis, plane, sign, a0, a1, y0, y1):
    batch = ctx['batch']
    E = EXTERIOR_STYLE
    if y0 < E['wainscotH']:
        batch.vface('shell', E['wainscot'], axis, plane, sign, a0, a1, y0, min(E['wainscotH'], y1), ao=EXT_AO)
    if y1 > E['wainscotH']:
        batch.vface('shell', E['base'], axis, plane, sign, a0, a1, max(y0, E['wainscotH']), y1, ao=EXT_AO)


# Announce-booth glass (§5.7): pane between knee wall and header, chrome mullions.
def boothGlass(ctx, seg):
    game, surf, group = ctx['game'], ctx['surf'], ctx['group']
    x0, z, x1, _, y0, y1 = seg[0:6]
    a = min(x0, x1) + H
    b = max(x0, x1)
    root = group('lobby')
    glass = game['mats'].toon('#3A4A5C', {
        'transparent': True, 'opacity': 0.28, 'rough': 0.06, 'env': 0.6, 'rim': 0.4, 'rimColor': '#FFC98A',
        'depthWrite': False, 'name': 'booth_glass',
    })
    root.add(wk.mesh(geo.plane(b - a, y1 - y0), glass, pos=[(a + b) / 2, (y0 + y1) / 2, z], cast=False, name='booth_glass'))
    chrome = surf.plain('trim_chrome')
    for x in [b - 0.03, (a + b) / 2]:
        root.add(wk.mesh(geo.box(0.06, y1 - y0, 0.08), chrome, pos=[x, (y0 + y1) / 2, z], cast=False))


# Yard chain-link: a double-sided alpha-tested plane (world UVs), galvanized posts every <= 2.5 m, top and
# bottom rails.
def fence(ctx, seg):
    batch, surf, group = ctx['batch'], ctx['surf'], ctx['group']
    x0, z0, x1, z1 = seg[0:4]
    alongX = z0 == z1
    a = min(x0, x1) if alongX else min(z0, z1)
    b = max(x0, x1) if alongX else max(z0, z1)
    at = z0 if alongX else x0
    batch.vface('yard', 'chainlink', 'z' if alongX else 'x', at, 1, a, b, 0.05, FENCE_H - 0.05)
    root = group('yard')
    steel = surf.plain('galvanized')
    n = max(1, math.ceil((b - a) / 2.5))
    for i in range(n + 1):
        s = a + ((b - a) * i) / n
        p = [s, (FENCE_H + 0.1) / 2, at] if alongX else [at, (FENCE_H + 0.1) / 2, s]
        root.add(wk.mesh(geo.cylinder(0.05, 0.05, FENCE_H + 0.1, 10), steel, pos=p))
    for y in [FENCE_H - 0.04, 0.12]:
        p = [(a + b) / 2, y, at] if alongX else [at, y, (a + b) / 2]
        rot = [0, 0, PI / 2] if alongX else [PI / 2, 0, 0]
        root.add(wk.mesh(geo.cylinder(0.035, 0.035, b - a, 8), steel, pos=p, rot=rot, cast=False))


# ------------------------------------------------------------------------------------------------- ceilings
def ceilings(ctx):
    batch = ctx['batch']
    for a in AREAS:
        if not indoor(a['id']):
            continue
        x0, z0, x1, z1 = a['rect']
        batch.hface(a['id'] + '#ceil', AREA_STYLE[a['id']]['ceiling'], x0, z0, x1, z1, a['ceilY'], False, border=0.5, ao=0.28)


def roofs(ctx):
    batch = ctx['batch']
    for a in AREAS:
        if not indoor(a['id']):
            continue
        x0, z0, x1, z1 = a['rect']
        batch.hface('shell#roof', 'roof_gravel', x0 - H, z0 - H, x1 + H, z1 + H, a['ceilY'] + ROOF_T, True)


def spread(a, b, n):
    """Evenly spread centres: n items across [a, b]."""
    return [a + ((b - a) * (i + 0.5)) / n for i in range(n)]


def js_round(v):
    return math.floor(v + 0.5)


def clampN(v, lo, hi):
    return max(lo, min(hi, js_round(v)))


# Ceiling fixtures of one area -> record whose diffuser mesh + light anchors switch at Sign-On.
def fixtures(ctx, area):
    game, surf, group = ctx['game'], ctx['surf'], ctx['group']
    M = game['mats']
    st = AREA_STYLE[area['id']]
    x0, z0, x1, z1 = area['rect']
    ceil = area['ceilY']
    root = group(area['id'])
    lens = []
    if st['fixtures'] == 'panels':
        # Troffer: a 6 cm cream frame ring around a lens recessed 2 cm into it (a lens lying 2 mm under a solid
        # frame plate z-fought with it across the room).
        frame = surf.plain('trim_cream')
        for x in spread(x0, x1, clampN((x1 - x0) / 3.4, 1, 8)):
            for z in spread(z0, z1, clampN((z1 - z0) / 3.2, 1, 6)):
                for s in [-1, 1]:
                    root.add(wk.mesh(geo.box(0.06, 0.05, 1.32), frame, pos=[x + s * 0.33, ceil - 0.025, z], cast=False))
                    root.add(wk.mesh(geo.box(0.6, 0.05, 0.06), frame, pos=[x, ceil - 0.025, z + s * 0.63], cast=False))
                lens.append(THREE.PlaneGeometry(0.6, 1.2).rotateX(PI / 2).translate(x, ceil - 0.03, z))
    elif st['fixtures'] == 'cans':
        ring = surf.plain('trim_chrome')
        for x in spread(x0, x1, 3):
            for z in spread(z0, z1, 2):
                root.add(wk.mesh(geo.cylinder(0.2, 0.2, 0.05, 20), ring, pos=[x, ceil - 0.025, z], cast=False))
                lens.append(THREE.CircleGeometry(0.15, 20).rotateX(PI / 2).translate(x, ceil - 0.058, z))   # 8 mm proud
    elif st['fixtures'] == 'grid':
        # Pipe grid + drop rods, and a row of scoop lights hanging from it (post-power work lights).
        pipe = surf.plain('trim_black')
        y = st['gridY']
        gx = spread(x0 + 0.6, x1 - 0.6, clampN((x1 - x0) / 2.5, 2, 12))
        gz = spread(z0 + 0.6, z1 - 0.6, clampN((z1 - z0) / 2.5, 2, 12))
        for z in gz:
            root.add(wk.mesh(geo.cylinder(0.045, 0.045, x1 - x0 - 1, 8), pipe, pos=[(x0 + x1) / 2, y, z], rot=[0, 0, PI / 2], cast=False))
        for x in gx:
            root.add(wk.mesh(geo.cylinder(0.045, 0.045, z1 - z0 - 1, 8), pipe, pos=[x, y + 0.09, (z0 + z1) / 2], rot=[PI / 2, 0, 0], cast=False))
        for i in range(0, len(gx), 3):
            for k in range(0, len(gz), 3):
                root.add(wk.mesh(geo.cylinder(0.025, 0.025, ceil - y, 6), pipe, pos=[gx[i], (ceil + y) / 2, gz[k]], cast=False))
        housing = surf.plain('trim_black')
        for x in spread(x0 + 2, x1 - 2, clampN((x1 - x0) / 4, 2, 6)):
            for z in [gz[1], gz[len(gz) - 2]]:
                root.add(wk.mesh(geo.cylinder(0.26, 0.2, 0.34, 16), housing, pos=[x, y - 0.3, z], cast=False))
                lens.append(THREE.CircleGeometry(0.2, 16).rotateX(PI / 2).translate(x, y - 0.475, z))
    mesh = wk.Mesh(THREE.mergeGeometries(lens), M.glow('#ffffff', 1))
    mesh.name = 'fixtures_' + area['id']
    mesh.userData.noMerge = True
    mesh.castShadow = False     # three Mesh default (not built through geo.mesh)
    mesh.receiveShadow = False
    root.add(mesh)

    pre = st['lightPre']
    post = st['lightPost']
    preMat = M.glow(pre, 1.1) if pre else M.toon('#D8D2C4', {'rough': 0.3, 'rim': 0})
    postMat = M.glow(post, 1.9)
    mesh.material = preMat
    low = 3 if area['id'] == 'master_control' else 5
    ly = st['gridY'] - 0.6 if st['fixtures'] == 'grid' else ceil - 0.5
    anchors = []
    for x in spread(x0, x1, clampN((x1 - x0) / 8, 1, 3)):
        for z in spread(z0, z1, clampN((z1 - z0) / 8, 1, 3)):
            aid = 'lvl_%s_%d' % (area['id'], len(anchors))
            a = {
                'id': aid,
                'pre': {'color': pre or post, 'intensity': 3.2 if pre else 0},
                'post': {'color': post, 'intensity': low},
                'pos': [x, ly, z], 'distance': max(9, ceil * 1.8),
            }
            anchors.append(a)
    cx = min(max(LEVER[0], x0), x1)
    cz = min(max(LEVER[2], z0), z1)
    center = [(x0 + x1) / 2, ceil - 0.5, (z0 + z1) / 2]
    dist = math.sqrt((LEVER[0] - cx) ** 2 + (LEVER[1] - 1) ** 2 + (LEVER[2] - cz) ** 2)
    rec = {'area': area['id'], 'mesh': mesh, 'pre': {'mat': preMat}, 'post': {'mat': postMat}, 'anchors': anchors,
           'center': center, 'dist': dist}
    mesh.userData.fixture = {'area': area['id'], 'pre': preMat.spec(), 'post': postMat.spec(), 'anchors': anchors,
                             'center': center, 'dist': dist}
    return rec


# ------------------------------------------------------------------------------------------------ platforms
def platforms(ctx):
    batch = ctx['batch']
    for p in PLATFORMS:
        if p['kind'] == 'riser':
            riser(ctx, p)
            continue
        x0, z0, x1, z1 = p['rect']
        bleacher = p['kind'] == 'bleacher'
        top = 'bleacher_wood' if bleacher else 'stage_wood'
        side = 'bleacher_riser' if bleacher else 'trim_black'
        r = AREA[p['area']]['rect']
        g = p['area']
        batch.hface(g, top, x0, z0, x1, z1, p['top'], True)
        o = {'ao': 0.3}
        if z0 > r[1] + 1e-3:
            batch.vface(g, side, 'z', z0, -1, x0, x1, 0, p['top'], **o)
        if z1 < r[3] - 1e-3:
            batch.vface(g, side, 'z', z1, 1, x0, x1, 0, p['top'], **o)
        if x0 > r[0] + 1e-3:
            batch.vface(g, side, 'x', x0, -1, z0, z1, 0, p['top'], **o)
        if x1 < r[2] - 1e-3:
            batch.vface(g, side, 'x', x1, 1, z0, z1, 0, p['top'], **o)
        # Nosing: gold on the stage and its step (front edge = +z), mustard on the bleacher tiers (front = -z).
        # The nosing wraps 6 mm past an exposed side (its end cap used to lie in the side face's plane: z-fight;
        # 1 cm would land in the bleacher_block end panels' plane).
        n0 = x0 - 0.006 if x0 > r[0] + 1e-3 else x0
        n1 = x1 + 0.006 if x1 < r[2] - 1e-3 else x1
        if bleacher:
            batch.box(g, 'trim_mustard', [n0, p['top'] - 0.05, z0 - 0.02], [n1, p['top'] + 0.01, z0 + 0.06], skip={'ny': True})
        else:
            batch.box(g, 'trim_gold', [n0, p['top'] - 0.05, z1 - 0.06], [n1, p['top'] + 0.01, z1 + 0.02], skip={'ny': True})
    # Bleacher side rails: stepped blue end panels with a mustard cap rail.
    # The panels stand 3 mm proud all round: their outer and front faces used to share the tiers' side and riser
    # planes (different AO, so they fought).
    e = 0.003
    for b in BLOCKERS:
        x0, z0, x1, z1 = b['rect']
        batch.box(b['area'], 'bleacher_riser', [x0 - e, b['y0'], z0 - e], [x1 + e, b['y1'] - 0.06, z1 + e], skip={'ny': True, 'py': True})
        batch.box(b['area'], 'trim_mustard', [x0 - 0.02, b['y1'] - 0.06, z0 - e], [x1 + 0.02, b['y1'], z1 + e], skip={'ny': True})


# Anchor riser: carpeted top inset by the ramp width, four sloped carpet faces.
def riser(ctx, p):
    batch = ctx['batch']
    x0, z0, x1, z1 = p['rect']
    r, y, g, key = p['ramp'], p['top'], p['area'], 'riser_carpet'
    X0, X1, Z0, Z1 = x0 + r, x1 - r, z0 + r, z1 - r
    batch.hface(g, key, X0, Z0, X1, Z1, y, True)
    ny = r / math.hypot(r, y)
    nh = y / math.hypot(r, y)
    batch.poly(g, key, [[x0, 0, z0], [x1, 0, z0], [X1, y, Z0], [X0, y, Z0]], [0, ny, -nh], [0.3, 0.3, 0, 0])
    batch.poly(g, key, [[x0, 0, z1], [X0, y, Z1], [X1, y, Z1], [x1, 0, z1]], [0, ny, nh], [0.3, 0, 0, 0.3])
    batch.poly(g, key, [[x0, 0, z0], [X0, y, Z0], [X0, y, Z1], [x0, 0, z1]], [-nh, ny, 0], [0.3, 0, 0, 0.3])
    batch.poly(g, key, [[x1, 0, z0], [x1, 0, z1], [X1, y, Z1], [X1, y, Z0]], [nh, ny, 0], [0.3, 0.3, 0, 0])
