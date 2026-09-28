# The eight purchasable/powered doors (port of the geometry half of src/world/doors.js, GDD §5.3): casing, the
# blocker art per `look` (the opening beats themselves are godot/scripts/world/doors.gd).
#   glass_chained  D1 smoked glass double doors, "ACTION 13 NEWS", chained: the chain snaps, the doors swing
#   padded         D2 tufted red "EMPLOYEES ONLY" doors with brass studs: they burst open in a stuffing puff
#   debris_desk    D3 toppled desk, film-can stacks, chair and a moving blanket: everything tumbles away
#   soundstage     D4 padded plum soundstage doors with portholes and a dark ON AIR box: heavy swing
#   steel_keypad   D5 steel ENGINEERING doors + keypad: 4 keypad flashes (G4-C5-E5-G5 cue), LED green, swing
#   elephant       D6 plywood scene-dock door on a track: shudders, then rumbles sideways along the wall
#   debris_cables  D7 waterfall of patch cables over puppet crates: cables zip up, crates tumble away
#   fire_exit      DY red fire door with push bars and an EXIT sign: buzzes, then swings out to the Yard
# Door-local frame: origin at the opening centre on the floor, +x along the opening, +z toward areas[1]
# (every door opens toward areas[1]). ON AIR boxes hang over both faces of the doors flagged onAir.
#
# buildDoor(ctx, data) -> the door's 'pivot' Group (door-local; doors.gd places and rotates it), exported as
# godot/assets/world/doors/<doorId>.glb. Every animated piece is its own named node:
#   pivot / frame (casing + static trim, merged), blocker
#   blocker: leaf_0 (s = -1, hinge x = -w) / leaf_1 (s = +1)        (glass_chained, padded, soundstage, steel_keypad,
#            chain_0..chain_2 + lock (glass_chained)                   fire_exit)
#            blanket + piece_0..piece_8 (debris_desk: desk, 3 can stacks, 3 loose cans, chair, papers)
#            panel (elephant)   cables + piece_0..piece_3 (debris_cables crates)
#   frame:   onair_face_0 (areas[0] face) / onair_face_1 + userData.mats {dark, lit}; keypad (kp_btn_6, kp_btn_0,
#            kp_btn_2, kp_btn_4, kp_led, merged idle buttons; userData.mats {off, on, ledOff, ledOn}); exit_sign
# Build-time Math.random() (cable waterfall, papers) uses a seeded stream: the JS placement is random per load.

import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from world import wk  # noqa: E402
from world.wk import geo, THREE  # noqa: E402
from world.layout import WALL_T, AREAS  # noqa: E402

PI = math.pi
H = WALL_T / 2
HINGE_Z = H + 0.07
AREA_CEIL = {a['id']: a['ceilY'] for a in AREAS}
_rng = random.Random(0xD00125)


def rnd(a, b):
    return a + _rng.random() * (b - a)


class DoorBuild:
    """The build-time half of the JS Door: layout fields, frame / blocker groups, onAirBoxes."""

    def __init__(self, ctx, data):
        self.__dict__.update(data)
        self.data = data
        self.game = ctx['game']
        self.surf = ctx['surf']
        self.pivot = wk.group('pivot')
        self.frame = wk.group('frame')
        self.blocker = wk.group('blocker')
        self.blocker.userData.dynamic = True
        self.pivot.add(self.frame, self.blocker)
        self.pivot.userData.door = {'id': data['id'], 'look': data['look']}
        self.onAirBoxes = []
        LOOKS[data['look']](self)
        if data['onAir']:
            for i, side in enumerate([-1, 1]):
                self._onAirBox(side, i)
        wk.mergeByMaterial(self.frame, 'frame_m')

    def _onAirBox(self, side, i):
        M = self.game['mats']
        z = side * (H + 0.12)
        # Over the head, unless that side's ceiling (minus a crown) is too low: then as high as it fits, and beside
        # the casing if it would hit the head (D4's Green Room face: the box used to sink into the ceiling).
        c = AREA_CEIL.get(self.areas[0 if side < 0 else 1])
        top = (99 if c is None else c) - 0.16
        x, y = 0, self.height + 0.45
        if y + 0.21 > top:
            y = top - 0.21
            if y - 0.21 < self.height + CASE_W + 0.03:
                x = self.width / 2 + CASE_W + 0.56
                y = min(self.height - 0.1, y)
        self.frame.add(wk.mesh(geo.roundedBox(1.0, 0.42, 0.2, 0.05, 2), M.toon('#2A1A1E', {'rough': 0.5}), pos=[x, y, z], cast=False))
        tex = self.game['tex'].labelTex('ON AIR', {'w': 512, 'h': 160, 'fg': '#FFFFFF', 'bg': '#3A0E12'})
        dark = M.toon('#8A3A3A', {'map': tex, 'rough': 0.35, 'rim': 0.1})
        lit = M.glow('#FF3B30', 2.4, {'map': tex})
        face = wk.mesh(geo.plane(0.86, 0.3), dark, pos=[0, y, z + side * 0.106], rot=[0, PI if side < 0 else 0, 0], cast=False,
                       name='onair_face_%d' % i)
        face.userData.noMerge = True
        face.userData.mats = {'dark': dark.spec(), 'lit': lit.spec()}
        self.frame.add(face)
        self.onAirBoxes.append({'face': face, 'dark': dark, 'lit': lit})


def buildDoor(ctx, data):
    return DoorBuild(ctx, data).pivot


# ------------------------------------------------------------------------------------------------- helpers
def add(parent, g, mat, pos=None, rot=None, cast=True, name=None):
    m = wk.mesh(g, mat, pos=pos, rot=rot, cast=cast, name=name)
    parent.add(m)
    return m


def darkGlass(M):
    return M.toon('#1C2733', {'rough': 0.06, 'metal': 0.25, 'env': 1.3, 'rim': 0.55, 'rimColor': '#9FC8FF', 'rimPower': 3})


def decal(M, map_, o=None):
    opts = {'map': map_, 'alphaTest': 0.4, 'rough': 0.55, 'rim': 0}
    opts.update(o or {})
    return M.toon('#ffffff', opts)


# Door casing: two jambs and a head that wrap the wall ends and stand CASE_PROUD proud of both faces (deeper than
# any wall trim, so baseboards and chair rails die inside it). Their inner faces sit CASE_INSET inside the
# opening, never in the plane of a wall face (architecture.py no longer draws the jamb caps and soffit they cover).
# The jambs stop under the head instead of overlapping it (no coplanar corner blocks).
CASE_PROUD = 0.05
CASE_INSET = 0.005
CASE_W = 0.14


def casing(d, mat):
    W, Hh, D, I = d.width, d.height, 2 * (H + CASE_PROUD), CASE_INSET
    jh, jw = Hh - I, CASE_W + I
    for s in [-1, 1]:
        add(d.frame, geo.roundedBox(jw, jh, D, 0.02, 2), mat, [s * (W / 2 - I + jw / 2), jh / 2, 0])
    add(d.frame, geo.roundedBox(W + 2 * CASE_W, CASE_W + I, D, 0.02, 2), mat, [0, jh + (CASE_W + I) / 2, 0])


# Double leaves hinged at the jambs on the +z face; build(hinge, s, w) fills one leaf spanning x in [-s*w, 0].
def leaves(d, build):
    w = d.width / 2
    out = []
    for i, s in enumerate([-1, 1]):
        hinge = wk.group('leaf_%d' % i)
        hinge.position.set(s * w, 0, HINGE_Z)
        build(hinge, s, w)
        wk.mergeByMaterial(hinge, 'leaf%d_m' % i)
        d.blocker.add(hinge)
        out.append(hinge)
    return out


def porthole(M, parent, x, y, r, chrome):
    glass = darkGlass(M)
    for z in [-1, 1]:
        add(parent, geo.torus(r, 0.028, 8, 28), chrome, [x, y, z * 0.055], None, cast=False)
        add(parent, THREE.CircleGeometry(r, 24), glass, [x, y, z * 0.05], [0, PI if z < 0 else 0, 0], cast=False)


def tiledPlane(w, h, ru, rv=1):
    g = THREE.PlaneGeometry(w, h)
    uv = g.attributes.uv
    for i in range(uv.count):
        uv.setXY(i, uv.getX(i) * ru, uv.getY(i) * rv)
    return g


# ---------------------------------------------------------------------------------------------------- looks
def _glass_chained(d):
    M, S, T = d.game['mats'], d.surf, d.game['tex']
    bronze = M.toon('#6E5A44', {'metal': 0.55, 'rough': 0.35, 'rimColor': '#FFC98A'})
    chrome = S.plain('trim_chrome')
    glass = darkGlass(M)
    paper = M.toon('#ffffff', {'map': T.newspaperTex(), 'rough': 0.9, 'rim': 0})
    casing(d, bronze)
    Hh = d.height

    def build(g, s, w):
        c = -s * w / 2
        add(g, geo.roundedBox(0.09, Hh, 0.06, 0.02, 2), bronze, [-s * 0.045, Hh / 2, 0])
        add(g, geo.roundedBox(0.09, Hh, 0.06, 0.02, 2), bronze, [-s * (w - 0.045), Hh / 2, 0])
        add(g, geo.roundedBox(w, 0.12, 0.06, 0.02, 2), bronze, [c, Hh - 0.06, 0])
        add(g, geo.roundedBox(w, 0.32, 0.06, 0.02, 2), bronze, [c, 0.17, 0])
        add(g, geo.box(w - 0.16, Hh - 0.45, 0.012), glass, [c, 0.33 + (Hh - 0.45) / 2, 0], None, cast=False)
        tex = T.labelTex('ACTION\n13' if s > 0 else 'NEWS', {'w': 256, 'h': 256, 'fg': '#F4F1E8', 'stroke': '#E23B3B'})
        add(g, geo.plane(w - 0.3, w - 0.3), decal(M, tex), [c, 1.62, -0.012], [0, PI, 0], cast=False)
        add(g, geo.plane(0.42, 0.52), paper, [c - s * 0.12, 1.0, 0.012], [0, 0, s * 0.06], cast=False)
        add(g, geo.cylinder(0.022, 0.022, 0.5, 10), chrome, [-s * (w - 0.35), 1.05, -0.075], [0, 0, PI / 2])
        for x in [w - 0.12, w - 0.58]:
            add(g, geo.cylinder(0.02, 0.02, 0.1, 8), chrome, [-s * x, 1.05, -0.05], [PI / 2, 0, 0])
        add(g, geo.cylinder(0.022, 0.022, 0.6, 10), chrome, [-s * (w - 0.14), 1.05, 0.07])
    leaves(d, build)
    # The chain: 14 elongated links looped round both push bars, and a brass padlock.
    steel = M.toon('#9AA0A8', {'metal': 0.85, 'rough': 0.3})
    brass = M.toon('#D9A520', {'metal': 0.85, 'rough': 0.28})
    z = HINGE_Z - 0.075
    # Links are merged into three chunks (the snap throws chunks, not 14 separate draw calls).
    pieces = [wk.group('chain_%d' % i) for i in range(3)]
    for i in range(14):
        f = (i / 14) * PI * 2
        link = add(pieces[i // 5], geo.torus(0.04, 0.011, 6, 12), steel, [0.32 * math.cos(f), 0.1 * math.sin(f), 0], None, cast=False)
        link.scale.set(1.35, 1, 1)
        if i % 2:
            link.rotation.set(PI / 2, 0, f + PI / 2, 'ZYX')
        else:
            link.rotation.set(0, 0, f + PI / 2)
    for c in pieces:
        c.position.set(0, 1.05, z)
        wk.mergeByMaterial(c, c.name + '_m')
        d.blocker.add(c)
    lock = wk.group('lock')
    add(lock, geo.roundedBox(0.11, 0.13, 0.05, 0.02, 2), brass, [0, 0, 0], None, cast=False)
    add(lock, geo.torus(0.035, 0.011, 6, 12, PI), steel, [0, 0.065, 0], None, cast=False)
    lock.position.set(0, 0.86, z)
    d.blocker.add(lock)


def _padded(d):
    M, S, T = d.game['mats'], d.surf, d.game['tex']
    casing(d, S.plain('trim_chocolate'))
    pad = S.plain('quilt_red')
    brass = M.toon('#E0B040', {'metal': 0.9, 'rough': 0.25})
    chrome = S.plain('trim_chrome')
    Hh = d.height
    sign = decal(M, T.labelTex('EMPLOYEES ONLY', {'w': 512, 'h': 128, 'fg': '#F6E7C8', 'bg': '#5A3A22', 'border': '#E8A92E'}))

    def build(g, s, w):
        c = -s * w / 2
        add(g, geo.roundedBox(w - 0.02, Hh - 0.04, 0.09, 0.035, 2), pad, [c, Hh / 2, 0])
        x0, x1, y0, y1 = -s * 0.06, -s * (w - 0.06), 0.08, Hh - 0.08

        def stud(x, y):
            add(g, geo.sphere(0.02, 8, 6), brass, [x, y, -0.05], None, cast=False)
        t = 0
        while t <= 1.0001:
            stud(x0 + (x1 - x0) * t, y0)
            stud(x0 + (x1 - x0) * t, y1)
            t += 1 / 9
        t = 1 / 20
        while t < 1:
            stud(x0, y0 + (y1 - y0) * t)
            stud(x1, y0 + (y1 - y0) * t)
            t += 1 / 20
        porthole(M, g, c, 1.72, 0.15, chrome)
        add(g, geo.roundedBox(0.12, 0.36, 0.012, 0.004, 1), chrome, [-s * (w - 0.14), 1.1, -0.052], None, cast=False)
        if s < 0:
            add(g, geo.plane(0.72, 0.18), sign, [c, 1.3, -0.052], [0, PI, 0], cast=False)
    leaves(d, build)


def _debris_desk(d):
    M, S, T = d.game['mats'], d.surf, d.game['tex']
    casing(d, S.plain('trim_cream'))
    teak = M.toon('#B07A45', {'map': T.woodPanel('#B07A45'), 'rough': 0.4})
    steel = S.plain('trim_steel')
    can = M.toon('#B9C0C8', {'metal': 0.75, 'rough': 0.3})
    lids = [M.toon(c, {'rough': 0.45}) for c in ['#E23B3B', '#2F5BD3', '#E8A92E', '#2E8C8C']]
    vinyl = M.toon('#E3662B', {'rough': 0.45})
    paper = M.toon('#F4F1E8', {'rough': 0.9, 'rim': 0, 'side': 'double'})
    pieces = []
    # Blanket hung across the doorway behind the pile.
    add(d.blocker, geo.plane(d.width + 0.1, d.height), M.toon('#ffffff', {'map': T.movingPadTex(), 'rough': 0.95, 'side': 'double'}),
        [0, d.height / 2, 0.1], None, cast=False, name='blanket')

    # Toppled desk, on its back across the opening.
    def piece(g, x, y, z, rot):
        g.name = 'piece_%d' % len(pieces)
        g.position.set(x, y, z)
        g.rotation.set(*rot)
        wk.mergeByMaterial(g, g.name + '_m')
        d.blocker.add(g)
        pieces.append(g)
        return g
    desk = wk.group()
    add(desk, geo.roundedBox(1.7, 0.06, 0.8, 0.02, 2), teak, [0, 0.72, 0])
    add(desk, geo.roundedBox(0.45, 0.66, 0.74, 0.03, 2), teak, [0.55, 0.36, 0])
    add(desk, geo.roundedBox(1.1, 0.4, 0.03, 0.01, 1), teak, [-0.25, 0.48, -0.36])
    for x in [-0.8, -0.05]:
        for z in [-0.34, 0.34]:
            add(desk, geo.cylinder(0.025, 0.025, 0.7, 8), steel, [x, 0.35, z], None, cast=False)
    piece(desk, 0.1, 0.4, -0.15, [-1.45, 0.08, 0.05])

    # Film-can stacks (each stack tumbles as one piece) and a few loose cans.
    def stack(x, z, n, lid):
        g = wk.group()
        for i in range(n):
            tw = i * 0.012 * (1 if i % 2 else -1)
            add(g, geo.cylinder(0.2, 0.2, 0.05, 20), can, [tw, i * 0.055, -tw], None, cast=i == 0)
            add(g, geo.cylinder(0.12, 0.12, 0.012, 16), lid, [tw, i * 0.055 + 0.03, -tw], None, cast=False)
        piece(g, x, 0.03, z, [0, x * 2, 0])
    stack(-0.85, -0.45, 6, lids[0])
    stack(0.95, -0.5, 4, lids[1])
    stack(-0.35, -0.7, 3, lids[2])
    for x, rz in [[0.45, 1.2], [-1.05, -1.3], [0.2, 1.4]]:
        g = wk.group()
        add(g, geo.cylinder(0.2, 0.2, 0.05, 20), can, [0, 0, 0], None, cast=False)
        piece(g, x, 0.2, -0.75, [0.3, 0, rz])
    # Swivel chair on its side.
    chair = wk.group()
    add(chair, geo.cylinder(0.26, 0.26, 0.09, 18), vinyl, [0, 0.45, 0])
    add(chair, geo.roundedBox(0.44, 0.4, 0.08, 0.04, 2), vinyl, [0, 0.72, -0.2])
    add(chair, geo.cylinder(0.03, 0.03, 0.4, 8), steel, [0, 0.22, 0], None, cast=False)
    for i in range(5):
        a = (i / 5) * PI * 2
        add(chair, geo.roundedBox(0.3, 0.035, 0.05, 0.015, 1), steel, [math.cos(a) * 0.15, 0.03, math.sin(a) * 0.15], [0, -a, 0], cast=False)
    piece(chair, -0.55, 0.28, -0.55, [0.2, 0.6, 1.45])
    papers = wk.group()
    for i in range(6):
        add(papers, geo.plane(0.3, 0.21), paper, [rnd(-1.1, 1.1), i * 0.002, rnd(-0.35, 0.35)], [-PI / 2, 0, rnd(0, 3)], cast=False)
    piece(papers, 0, 0.012, -0.65, [0, 0, 0])


def _soundstage(d):
    M, S = d.game['mats'], d.surf
    black = S.plain('trim_black')
    chrome = S.plain('trim_chrome')
    casing(d, black)
    pad = S.plain('quilt_plum')
    Hh = d.height

    def build(g, s, w):
        c = -s * w / 2
        for x in [0.05, w - 0.05]:
            add(g, geo.roundedBox(0.1, Hh, 0.1, 0.03, 2), black, [-s * x, Hh / 2, 0])
        add(g, geo.roundedBox(w - 0.2, 0.14, 0.1, 0.03, 2), black, [c, Hh - 0.07, 0])   # top rail between the stiles
        # Kick plate: 3 mm proud of the stiles and 2 mm short of the leaf edges (its ends shared the stiles' side planes).
        add(g, geo.roundedBox(w - 0.004, 0.34, 0.106, 0.02, 2), chrome, [c, 0.17, 0])
        add(g, geo.roundedBox(w - 0.2, Hh - 0.5, 0.12, 0.05, 2), pad, [c, 0.34 + (Hh - 0.5) / 2, 0])
        porthole(M, g, c, 2.2, 0.2, chrome)
        add(g, geo.roundedBox(0.14, 0.42, 0.014, 0.005, 1), chrome, [-s * (w - 0.16), 1.2, -0.068], None, cast=False)
    leaves(d, build)


def _steel_keypad(d):
    M, S, T = d.game['mats'], d.surf, d.game['tex']
    steelFrame = S.plain('trim_steel')
    casing(d, steelFrame)
    steel = M.toon('#8C98A4', {'metal': 0.55, 'rough': 0.38, 'rimColor': '#9FC8FF'})
    chrome = S.plain('trim_chrome')
    Hh = d.height

    def build(g, s, w):
        c = -s * w / 2
        add(g, geo.roundedBox(w - 0.02, Hh - 0.03, 0.07, 0.02, 2), steel, [c, Hh / 2, 0])
        for y in [0.75, 1.95]:
            for z in [-1, 1]:
                add(g, geo.roundedBox(w - 0.3, 0.8, 0.02, 0.01, 1), steel, [c, y, z * 0.04], None, cast=False)
        add(g, geo.cylinder(0.022, 0.022, w - 0.3, 10), chrome, [c, 1.05, -0.09], [0, 0, PI / 2])
        if s < 0:
            add(g, geo.plane(0.9, 0.24), decal(M, T.stencilTex('ENGINEERING', {'w': 512, 'h': 128, 'ink': '#F4C21E'})), [c, 1.62, -0.056], [0, PI, 0], cast=False)
        else:
            add(g, geo.plane(0.42, 0.42), decal(M, T.boltSignTex()), [c, 1.62, -0.056], [0, PI, 0], cast=False)
    leaves(d, build)
    # Keypad on the approach face (areas[0], -z), to the viewer's right.
    kp = wk.group('keypad')
    kp.userData.noMerge = True
    kp.position.set(-(d.width / 2 + 0.42), 1.35, -(H + 0.03))
    add(kp, geo.roundedBox(0.24, 0.36, 0.05, 0.015, 2), M.toon('#3A3F46', {'rough': 0.5}), [0, 0, 0], name='kp_body')
    off = M.toon('#D8D8D0', {'rough': 0.4})
    on = M.glow('#7CFF6A', 2.2)
    # The four buttons of the G4-C5-E5-G5 cue stay separate meshes (they flash); the other eight are merged.
    idle = wk.group('kp_idle')
    for r in range(4):
        for q in range(3):
            i = r * 3 + q
            flashes = i in (6, 0, 2, 4)
            add(kp if flashes else idle, geo.roundedBox(0.05, 0.042, 0.02, 0.008, 1), off, [(1 - q) * 0.065, 0.07 - r * 0.055, -0.03],
                None, cast=False, name='kp_btn_%d' % i if flashes else None)
    wk.mergeByMaterial(idle, 'kp_idle_m')
    kp.add(idle)
    ledOff = M.toon('#C0302A', {'emissive': '#C0302A', 'emissiveIntensity': 0.8})
    ledOn = M.glow('#52E04A', 2.5)
    add(kp, geo.sphere(0.014, 10, 8), ledOff, [0, 0.145, -0.028], None, cast=False, name='kp_led')
    kp.userData.mats = {'off': off.spec(), 'on': on.spec(), 'ledOff': ledOff.spec(), 'ledOn': ledOn.spec()}
    d.frame.add(kp)


def _elephant(d):
    M, S, T = d.game['mats'], d.surf, d.game['tex']
    W, Hh = d.width, d.height
    steel = S.plain('trim_steel')
    casing(d, S.plain('trim_black'))
    PZ = -(H + CASE_PROUD + 0.062)   # track and panel: the panel back stays 2 mm clear of the casing
    add(d.frame, geo.roundedBox(2 * W + 0.9, 0.12, 0.16, 0.03, 2), steel, [W / 2, Hh + 0.42, PZ])
    ply = M.toon('#C49A6C', {'map': T.woodPanel('#C49A6C'), 'rough': 0.6, 'rim': 0.2, 'rimColor': '#FF4FA0'})
    panel = wk.group('panel')
    panel.position.set(0, 0, PZ)
    add(panel, geo.roundedBox(W + 0.3, Hh + 0.25, 0.12, 0.04, 2), ply, [0, (Hh + 0.25) / 2, 0])
    for x in [-(W / 2 - 0.1), W / 2 - 0.1]:
        add(panel, geo.roundedBox(0.14, Hh + 0.2, 0.05, 0.02, 1), ply, [x, (Hh + 0.2) / 2, -0.075])
    add(panel, geo.plane(W * 0.82, 1.1), decal(M, T.stencilTex('SCENE DOCK\nKEEP CLEAR', {'w': 512, 'h': 256})), [0, 2.0, -0.101], [0, PI, 0], cast=False)
    hz = T.hazardTex()
    hz.wrapS = 1000   # THREE.RepeatWrapping (the cached decal texture, like the JS)
    add(panel, tiledPlane(W + 0.3, 0.32, 3), M.toon('#ffffff', {'map': hz, 'rough': 0.6, 'rim': 0}), [0, 0.2, -0.066], [0, PI, 0], cast=False)
    for x in [-(W / 2 - 0.25), W / 2 - 0.25]:
        add(panel, geo.roundedBox(0.06, 0.3, 0.04, 0.01, 1), steel, [x, Hh + 0.3, 0], None, cast=False)
        add(panel, geo.cylinder(0.07, 0.07, 0.06, 14), steel, [x, Hh + 0.42, 0], [PI / 2, 0, 0], cast=False)
    d.blocker.add(panel)


def _debris_cables(d):
    M, S, T = d.game['mats'], d.surf, d.game['tex']
    W, Hh = d.width, d.height
    casing(d, S.plain('trim_black'))
    # Cable waterfall hung from the head (group origin at the top so it zips up by scaling y).
    # A blackout drape in the middle of the opening with a layer of cables on each face.
    cables = wk.group('cables')
    cables.position.set(0, Hh, 0)
    add(cables, geo.plane(W + 0.05, Hh), M.toon('#15121A', {'rough': 1, 'rim': 0, 'side': 'double'}), [0, -Hh / 2, 0], None, cast=False)
    colors = [M.toon(c, {'rough': 0.35, 'rim': 0.2}) for c in ['#E23B3B', '#F4E03A', '#3A58E4', '#52D24A']]
    for i in range(32):
        side = 1 if i % 2 else -1
        x = -W / 2 + 0.08 + ((W - 0.16) * (i >> 1)) / 15 + rnd(-0.05, 0.05)
        z = side * rnd(0.03, 0.09)
        pts = [[x, 0, z], [x + rnd(-0.12, 0.12), -Hh * 0.45, z + side * rnd(0, 0.06)],
               [x + rnd(-0.15, 0.15), -Hh + 0.3, z + side * rnd(0, 0.12)], [x + rnd(-0.25, 0.25), -Hh + 0.03, z + side * rnd(0.15, 0.45)]]
        add(cables, geo.tube(pts, rnd(0.016, 0.03), 18, 6), colors[(i >> 1) % len(colors)], None, None, cast=False)
    wk.mergeByMaterial(cables, 'cables_m')
    d.blocker.add(cables)
    # Puppet crates on the approach side (areas[0], -z).
    crate = M.toon('#B98A57', {'map': T.woodPanel('#B98A57'), 'rough': 0.6})
    ink = decal(M, T.stencilTex('PUPPETS\nFRAGILE', {'w': 256, 'h': 128}))
    for k, (sx, sy, sz, x, y, z, ry) in enumerate([
            [0.85, 0.62, 0.62, -0.55, 0.31, -0.45, 0.05], [0.8, 0.6, 0.6, 0.4, 0.3, -0.5, -0.08],
            [0.7, 0.55, 0.55, -0.1, 0.9, -0.45, 0.14], [0.5, 0.45, 0.45, 1.0, 0.225, -0.75, 0.3]]):
        g = wk.group('piece_%d' % k)
        add(g, geo.roundedBox(sx, sy, sz, 0.04, 2), crate, [0, 0, 0])
        add(g, geo.plane(sx * 0.8, sy * 0.5), ink, [0, 0, -sz / 2 - 0.004], [0, PI, 0], cast=False)
        g.position.set(x, y, z)
        g.rotation.y = ry
        d.blocker.add(g)


def _fire_exit(d):
    M, S, T = d.game['mats'], d.surf, d.game['tex']
    red = M.toon('#C0392B', {'metal': 0.3, 'rough': 0.4, 'rimColor': '#FFC98A'})
    chrome = S.plain('trim_chrome')
    casing(d, M.toon('#8E2A22', {'metal': 0.3, 'rough': 0.45}))
    Hh = d.height
    plate = decal(M, T.labelTex('FIRE EXIT\nALARM WILL SOUND', {'w': 512, 'h': 256, 'fg': '#F4F1E8', 'bg': '#9C2A20'}))

    def build(g, s, w):
        c = -s * w / 2
        add(g, geo.roundedBox(w - 0.02, Hh - 0.03, 0.07, 0.02, 2), red, [c, Hh / 2, 0])
        add(g, geo.roundedBox(w - 0.25, 0.08, 0.06, 0.03, 2), chrome, [c, 1.0, -0.08])
        for x in [0.15, w - 0.15]:
            add(g, geo.roundedBox(0.06, 0.12, 0.08, 0.02, 1), chrome, [-s * x, 1.0, -0.06], None, cast=False)
        if s < 0:
            add(g, geo.plane(0.62, 0.31), plate, [c, 1.6, -0.041], [0, PI, 0], cast=False)
    leaves(d, build)
    # EXIT sign over the MC face: emergency-powered, always lit.
    y, z = Hh + 0.36, -(H + 0.09)
    add(d.frame, geo.roundedBox(0.66, 0.28, 0.12, 0.03, 2), M.toon('#E8E4DC', {'rough': 0.4}), [0, y, z], None, cast=False)
    ex = add(d.frame, geo.plane(0.56, 0.2), M.glow('#52E04A', 2.2, {'map': T.labelTex('EXIT', {'w': 256, 'h': 96, 'fg': '#FFFFFF', 'bg': '#0E3A1A'})}),
             [0, y, z - 0.066], [0, PI, 0], cast=False, name='exit_sign')
    ex.userData.noMerge = True


LOOKS = {
    'glass_chained': _glass_chained, 'padded': _padded, 'debris_desk': _debris_desk, 'soundstage': _soundstage,
    'steel_keypad': _steel_keypad, 'elephant': _elephant, 'debris_cables': _debris_cables, 'fire_exit': _fire_exit,
}
