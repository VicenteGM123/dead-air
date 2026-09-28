"""DEAD AIR — props: weapons (docs/PROPKIT.md, GDD §9). Port of src/props/weapons.js (same names, same numbers).
Every gun, wonder weapon, throwable and melee prop the heroes hold, built as premium chunky toys (~1.3x real size,
bevelled, wood / chrome / bright plastic, navy blue-steel #3A4A6B metal, one die-cut sticker each).

  buildWeapon(id, { upgraded, signal, pose }, game) -> Group   (cached + cloned via buildProp)
  makeWeapon(game, id, opts)  raw (uncached) builder         WEAPON_IDS   every id below
  buildWeaponModel(id, upgraded, game)   drop-in for src/game/weaponModels.js (same signature)
  animateWeapon(group, t, state)         runtime helper (spins reels, bobs the VU needle, wobbles goo...): NOT built
                                         here — ported to GDScript in godot/scripts/game/weapon_models.gd (it drives
                                         the parts reelL / reelR / needle / goo / filament, all kept below).

Ids (registered with registerProp, category 'weapons'): revolver_38 pump_37 mp7 m16a1 m60 zapper boom_mic
chroma_key tube_grenade tiny_tele melee_walkie melee_lp melee_wrench

HAND CONVENTION (pose 'hand', the default in game): grip point (palm centre of the right hand) at the origin,
barrel along -Z, top +Y, a child Object3D named 'muzzle' at the barrel tip. Root userData adds:
  leftHand:[x,y,z] support-hand point · grip:[x,y,z] · muzzle:[x,y,z] · weapon:{ id, upgraded, signal, pose }
  parts:{ name: Object3D } animatable sub-groups (flagged noMerge) — drum, pump, mag, reelL, reelR, needle,
  antenna, goo, battery, keys, filament, cover, bipod ... (see each builder)
Parts per id: revolver_38 drum (spin z) · pump_37 pump (slide +z 0.07) · mp7/m16a1 mag (drop -y) · m60 cover
(hinge x), bipod (x), belt (InstancedMesh) · zapper keys, battery (pops +z) · boom_mic reelL/reelR (spin y), needle
(rotation.x 0.7..-0.7), mic (wobble) · chroma_key goo (wobble) · tube_grenade filament (flicker) · tiny_tele
antenna, ant2/ant3 (slide local +y 0.08/0.078 to extend) — hints in userData.anim.
Other poses (opts.pose): 'display' — resting on the floor (y=0), centered on x/z (propview default when
window.__pv exists); 'wall' — side-on for wall-buy posters: right side faces -Z, barrel toward -X, centered on
x/y, back touching z=0. Extra opts: tiny_tele { antenna:'up', card }.
Screens: chroma_key (viewfinder, card world_beach) and tiny_tele (card show_9) carry K.screen meshes in group
'scr_weapon' (rebuilt per call, not cached). Scenes: weapons_wall, weapons_wall_up, weapons_wonder, weapons_small,
weapons_hand (hand pose check). Shots: _shots/props/weapons/.
UPGRADED LOOK (opts.upgraded): the 'chromacast' finish (animated hue-shifting gradient along the barrel,
scrolling colour-bar stripes, sparkle specks, emissive 0.3, biased to opts.signal: hot_mic|laugh_track|
cold_open) on the steel and body parts + a gold "13" medallion, a mini rabbit-ear antenna, tail fins and extra
chrome. The chromacast material is a toon material with extra shader code; its heroFade variant is pre-patched
so game.mats.applyHeroFade keeps the finish.

Port notes (JS -> Python):
  * The chromacast material: the JS toon material patched with onBeforeCompile (patchChroma) becomes the cached toon
    spec switched to kind 'chromacast' with the uniform values in spec["chroma"] = {uChHue, uChSpread, uChLen,
    uChDark: {value}} — godot materials.gd fromSpec builds toon(color, opts) + patchShader(mat, "chroma", chroma)
    (the GLSL below is kept as reference only: the Godot shader include implements it). chromaUV() writes the
    same UVs (u = 0 rear .. 1 muzzle, v = height) the shader reads.
  * Local renames (Python builtins / shadowing only): the `thick` parameter of side()/sideHoles() -> thick_,
    `len` parameters -> len_, `id` -> id_ where it would shadow the registry loop variable.
  * creased() is vectorised with numpy but keeps the JS operation order (float32 stores, per-vertex face order).
"""
import math

import numpy as np

from dalib import kit as K
from dalib.kit import registerProp, registerScene, buildProp, PAL, THREE, _truthy
from dalib.mathutils3 import JSObj, js_round, js_str, smoothstep, clamp
from dalib.three_geo import mergeGeometries, mergeVertices, BufferAttribute

STEEL = '#3A4A6B'
CHROME = '#98A1AD'
GOLD = '#E2A93A'
BRASS = '#C8963C'
INK = '#2A2233'          # "black" parts: deep plum, never pure black
KEEP = {'keepColor': True}
TAU = math.pi * 2
SIGNALS = {'hot_mic': PAL.hotMic, 'laugh_track': PAL.laughTrack, 'cold_open': PAL.coldOpen}
V3 = THREE.Vector3


def _d(o, k, default):
    """`o.k ?? default` for an opts dict."""
    v = o.get(k) if o else None
    return default if v is None else v


def _f32(a):
    return np.asarray(a, dtype=np.float64).astype(np.float32).astype(np.float64)


def _jsround(q):
    """Math.round on an array (ties toward +Infinity)."""
    r = np.floor(q)
    return r + ((q - r) >= 0.5)


# ============================================================================================ geometry helpers
# Rounds every corner of a closed polygon [[x,y],...] (roundProfile rounds interior points only).
def roundClosed(pts, r=0.01, steps=3):
    n = len(pts)
    rr = [0] + list(r) + [0] if isinstance(r, (list, tuple)) else r
    return K.roundProfile([pts[n - 1]] + list(pts) + [pts[0]], rr, steps)[1:-1]


# Smooth normals across edges flatter than `angle` (rad), keep harder creases (fine 0.01 mm vertex hashing:
# BufferGeometryUtils.toCreasedNormals hashes at 1 cm, too coarse for hand-held props). Returns non-indexed.
def creased(geo, angle=1.0):
    g = geo.toNonIndexed() if geo.index is not None else geo
    p = g.attributes.position
    n = p.count
    faces = n // 3
    P = np.asarray(p, dtype=np.float64)[:faces * 3, :3]
    A, B, C = P[0::3], P[1::3], P[2::3]
    # a.fromBufferAttribute(p, f*3) ...; c.sub(b); a.sub(b); c.cross(a)
    cx, cy, cz = C[:, 0] - B[:, 0], C[:, 1] - B[:, 1], C[:, 2] - B[:, 2]
    ax, ay, az = A[:, 0] - B[:, 0], A[:, 1] - B[:, 1], A[:, 2] - B[:, 2]
    x = cy * az - cz * ay
    y = cz * ax - cx * az
    z = cx * ay - cy * ax
    fn = _f32(np.stack([x, y, z], 1))                       # Float32Array fn
    ln = np.sqrt(x * x + y * y + z * z)
    ln = np.where(ln == 0, 1.0, ln)                          # normalize(): divideScalar(length() || 1)
    s = 1 / ln
    fu = _f32(np.stack([x * s, y * s, z * s], 1))           # Float32Array fu
    # key = `${Math.round(x * 1e5)},${Math.round(y * 1e5)},${Math.round(z * 1e5)}` (vertex order kept per key)
    Pv = np.asarray(p, dtype=np.float64)[:, :3]
    keys = _jsround(Pv * 1e5)
    _, kid = np.unique(keys, axis=0, return_inverse=True)
    kid = kid.reshape(-1)
    order = np.argsort(kid, kind='stable')                   # vertices grouped by key, increasing index inside
    counts = np.bincount(kid)
    starts = np.concatenate([[0], np.cumsum(counts)[:-1]])
    rep = counts[kid]                                        # for vertex i: size of its key's list
    I = np.repeat(np.arange(n), rep)
    off = np.arange(len(I)) - np.repeat(np.cumsum(rep) - rep, rep)
    J = order[np.repeat(starts[kid], rep) + off]             # list faces in push order (vertex j -> face j/3|0)
    fI, fJ = I // 3, J // 3
    fI = np.minimum(fI, faces - 1)
    fJ = np.minimum(fJ, faces - 1)
    cos = math.cos(angle)
    dot = fu[fJ, 0] * fu[fI, 0] + fu[fJ, 1] * fu[fI, 1] + fu[fJ, 2] * fu[fI, 2]
    keep = ~(dot < cos)
    acc = np.zeros((n, 3))
    np.add.at(acc, I[keep], fn[fJ[keep]])                   # x += fn[f*3] ... in the JS order
    l = np.sqrt(acc[:, 0] * acc[:, 0] + acc[:, 1] * acc[:, 1] + acc[:, 2] * acc[:, 2])
    l = np.where(l == 0, 1.0, l)                             # Math.hypot(x, y, z) || 1
    nor = np.stack([acc[:, 0] / l, acc[:, 1] / l, acc[:, 2] / l], 1)
    g.setAttribute('normal', BufferAttribute(nor, 3))
    return mergeVertices(g, 1e-5)


# Scales x (thickness) linearly along z between zA (factor kA) and zB (factor kB): tapered stocks and grips.
def thick(geo, zA, kA, zB, kB):
    p = geo.attributes.position
    a = np.asarray(p, dtype=np.float64)
    t = np.clip((a[:, 2] - zA) / (zB - zA), 0, 1)
    p[:, 0] = a[:, 0] * (kA + (kB - kA) * t)
    p.needsUpdate = True
    geo.computeVertexNormals()
    return geo


# Side-profile slab: pts [[fwd, up], ...] (fwd = -z), thickness along x, centered on x = 0.
def side(pts, thick_, o=None):
    o = o or {}
    shape = roundClosed(pts, _d(o, 'round', 0.008), _d(o, 'steps', 2))
    g = K.extrude(shape, thick_, {'bevel': _d(o, 'bevel', min(0.008, thick_ * 0.3)), 'curveSeg': 6,
                                  'bevelSeg': _d(o, 'bevelSeg', 2), 'uv': o.get('uv')})
    g.rotateY(math.pi / 2)
    return creased(g, _d(o, 'crease', 0.75))


# Side-profile slab with holes (carry handles, sight towers): holes = [[[fwd, up], ...], ...].
def sideHoles(pts, holes, thick_, o=None):
    o = o or {}

    def v2(arr):
        return [THREE.Vector2(x, y) for x, y in arr]
    sh = THREE.Shape(v2(roundClosed(pts, _d(o, 'round', 0.008), _d(o, 'steps', 2))))
    for h in holes:
        sh.holes.append(THREE.Path(v2(roundClosed(h, _d(o, 'holeRound', 0.006), 2))))
    g = K.extrude(sh, thick_, {'bevel': _d(o, 'bevel', min(0.006, thick_ * 0.3)), 'curveSeg': 6,
                               'bevelSeg': _d(o, 'bevelSeg', 2), 'uv': o.get('uv')})
    g.rotateY(math.pi / 2)
    return creased(g, _d(o, 'crease', 0.75))


# Ribbed lathe profile [[r, t], ...] (ringtail pumps, knurled nuts, flash hiders): n grooves of `depth`.
def ribProfile(L, R, n, depth, endR=None, o=None):
    endR = R * 0.85 if endR is None else endR
    o = o or {}
    e = _d(o, 'end', min(0.02, L * 0.15))
    pts = [[0, 0], [endR, 0], [R, e]]
    span = L - 2 * e
    gw = _d(o, 'gw', min(0.004, span / n / 3))
    for i in range(n):
        c = e + ((i + 0.5) / n) * span
        pts += [[R, c - gw], [R - depth, c - gw * 0.5], [R - depth, c + gw * 0.5], [R, c + gw]]
    pts += [[R, L - e], [endR, L], [0, L]]
    return pts


# Cross-section slab: pts [[x, y], ...] extruded along z (length centered on z = 0).
def section(pts, len_, o=None):
    o = o or {}
    shape = roundClosed(pts, _d(o, 'round', 0.008), _d(o, 'steps', 2))
    return creased(K.extrude(shape, len_, {'bevel': _d(o, 'bevel', 0.006), 'curveSeg': 6,
                                           'bevelSeg': _d(o, 'bevelSeg', 2), 'uv': o.get('uv')}),
                   _d(o, 'crease', 0.75))


# Lathe along -z: profile [[radius, t], ...] with t = distance forward (0 at the object's local origin).
def zlathe(profile, o=None):
    o = o or {}
    return K.lathe(profile, {'seg': _d(o, 'seg', 20), 'round': o.get('round'), 'steps': o.get('steps')}) \
        .clone().rotateX(-math.pi / 2)


# Bevelled cylinder along -z from 0 to len (rRear at z=0, rFront at z=-len).
def zcyl(rRear, rFront, len_, o=None):
    o = o or {}
    return K.cyl(rRear if rFront is None else rFront, rRear, len_,
                 {'bevel': _d(o, 'bevel', min(0.004, rRear * 0.3)), 'seg': _d(o, 'seg', 18)}) \
        .clone().rotateX(-math.pi / 2)


# Bevelled cylinder along x (knobs, screws facing +x), base at x = 0.
def xcyl(r, len_, o=None):
    o = o or {}
    return K.cyl(_d(o, 'rt', r), r, len_, {'bevel': _d(o, 'bevel', min(0.003, r * 0.3)), 'seg': _d(o, 'seg', 16)}) \
        .clone().rotateZ(-math.pi / 2)


# Bevelled cylinder along y, base at y = 0.
def ycyl(r, len_, o=None):
    o = o or {}
    return K.cyl(_d(o, 'rt', r), r, len_, {'bevel': _d(o, 'bevel', min(0.003, r * 0.3)), 'seg': _d(o, 'seg', 16)}) \
        .clone()


def sphere(r, ws=16, hs=12):
    return THREE.SphereGeometry(r, ws, hs)


# Point helper: (fwd, up, x) -> [x, up, -fwd]
def P(f, u, x=0):
    return [x, u, -f]


# Cylinder with n rounded flutes (revolver drum), along -z from 0 to len.
def fluted(R, len_, n=6, depth=0.009, o=None):
    o = o or {}
    bev = _d(o, 'bevel', 0.009)
    rows = []
    rows.append([0, 0])
    rows.append([R - bev, 0])
    for i in range(1, 4):
        a = (i / 3) * math.pi / 2
        rows.append([R - bev + math.sin(a) * bev, bev - math.cos(a) * bev])
    mid = 9
    for i in range(1, mid):
        rows.append([R, bev + (i / mid) * (len_ - 2 * bev)])
    for i in range(0, 4):
        a = (i / 3) * math.pi / 2
        rows.append([R - bev + math.cos(a) * bev, len_ - bev + math.sin(a) * bev])
    rows.append([0, len_])
    g = THREE.LatheGeometry([THREE.Vector2(r, y) for r, y in rows], _d(o, 'seg', 48))
    p = g.attributes.position
    y0, y1, ramp = len_ * 0.26, len_ * 0.9, len_ * 0.12
    phase = _d(o, 'phase', 0.5)
    for i in range(p.count):
        x, y, z = p.getX(i), p.getY(i), p.getZ(i)
        r = math.hypot(x, z)
        if r < R * 0.8:
            continue
        th = math.atan2(z, x)
        d = math.fmod((th / TAU) * n + phase, 1)
        if d < 0:
            d += 1
        d -= 0.5
        w = 0.3
        f = math.cos((d / w) * math.pi / 2) ** 2 if abs(d) < w else 0
        gy = smoothstep(y, y0, y0 + ramp) * (1 - smoothstep(y, y1 - ramp * 0.5, y1))
        k = (r - depth * f * gy) / r
        p.setX(i, x * k)
        p.setZ(i, z * k)
    g.computeVertexNormals()
    K.weldNormals(g)
    g.rotateX(-math.pi / 2)
    return g


# Rounded star / flower outline points for extrusions.
def starPts(n, r0, r1, rot=-math.pi / 2):
    pts = []
    for i in range(n * 2):
        a = rot + (i / (n * 2)) * TAU
        r = r1 if i % 2 else r0
        pts.append([math.cos(a) * r, math.sin(a) * r])
    return pts


# ============================================================================================ sticker atlas
ATLAS = 1024
CELLS = {
    'star': [0, 0, 256, 256], 'daisy': [256, 0, 256, 256], 'logo13': [512, 0, 256, 256], 'medal13': [768, 0, 256, 256],
    'agent13': [0, 256, 256, 256], 'tenfour': [256, 256, 256, 256], 'space': [512, 256, 256, 256],
    'weather': [768, 256, 256, 256],
    'groove': [0, 512, 512, 256], 'vu': [512, 512, 256, 256], 'lp': [768, 512, 256, 256],
    'dymoCrew': [0, 768, 512, 64], 'dymoEng': [0, 832, 512, 64], 'grille': [0, 896, 128, 128],
    'chromaPlate': [128, 896, 384, 128],
    'tubeLabel': [512, 768, 256, 128], 'telePlate': [512, 896, 256, 128], 'dial13': [768, 768, 256, 256],
}


def cellUV(name, inset=2):
    x, y, w, h = CELLS[name]
    return [(x + inset) / ATLAS, 1 - (y + h - inset) / ATLAS, (x + w - inset) / ATLAS, 1 - (y + inset) / ATLAS]


def FONT(px, f='Titan One'):
    return '%spx "%s", "Arial Black", sans-serif' % (js_str(px), f)


def dieCut(ctx, path, fill, border=9):
    ctx.save()
    ctx.lineJoin = 'round'
    ctx.lineCap = 'round'
    path()
    ctx.strokeStyle = '#CFC6B8'
    ctx.lineWidth = border * 2 + 4
    ctx.stroke()
    path()
    ctx.strokeStyle = '#FBF8F0'
    ctx.lineWidth = border * 2
    ctx.stroke()
    path()
    ctx.fillStyle = fill
    ctx.fill()
    ctx.restore()


def starPath(ctx, cx, cy, r0, r1, n=5, rot=-math.pi / 2):
    ctx.beginPath()
    for i in range(n * 2):
        a = rot + (i / (n * 2)) * TAU
        r = r1 if i % 2 else r0
        x, y = cx + math.cos(a) * r, cy + math.sin(a) * r
        if i:
            ctx.lineTo(x, y)
        else:
            ctx.moveTo(x, y)
    ctx.closePath()


def gloss(ctx, x, y, w, h, a=0.35):
    g = ctx.createLinearGradient(x, y, x + w * 0.4, y + h)
    g.addColorStop(0, 'rgba(255,255,255,%s)' % js_str(a))
    g.addColorStop(0.45, 'rgba(255,255,255,0)')
    ctx.fillStyle = g
    ctx.fillRect(x, y, w, h)


def stickers():
    def draw(ctx, W, H, rnd):
        ctx.clearRect(0, 0, W, H)

        def cell(name, fn):
            x, y, w, h = CELLS[name]
            ctx.save()
            ctx.translate(x, y)
            ctx.beginPath()
            ctx.rect(0, 0, w, h)
            ctx.clip()
            fn(w, h)
            ctx.restore()

        def text(t, x, y, px, fill, f='Titan One', stroke=None, sw=0):
            ctx.font = FONT(px, f)
            ctx.textAlign = 'center'
            ctx.textBaseline = 'middle'
            if stroke:
                ctx.lineJoin = 'round'
                ctx.lineWidth = sw
                ctx.strokeStyle = stroke
                ctx.strokeText(t, x, y)
            ctx.fillStyle = fill
            ctx.fillText(t, x, y)

        # gold star (revolver)
        def c_star(w, h):
            g = ctx.createLinearGradient(40, 30, 210, 230)
            g.addColorStop(0, '#FFE58A')
            g.addColorStop(0.45, '#F2B233')
            g.addColorStop(1, '#C07A1A')
            dieCut(ctx, lambda: starPath(ctx, 128, 134, 108, 50), g, 10)
            ctx.save()
            starPath(ctx, 128, 134, 108, 50)
            ctx.clip()
            ctx.strokeStyle = 'rgba(150,80,10,0.55)'
            ctx.lineWidth = 5
            starPath(ctx, 128, 136, 74, 34)
            ctx.stroke()
            ctx.fillStyle = 'rgba(255,255,255,0.45)'
            ctx.beginPath()
            ctx.ellipse(96, 96, 40, 13, -0.6, 0, TAU)
            ctx.fill()
            text('13', 128, 142, 50, '#8A4A0E', 'Bungee')
            text('13', 126, 139, 50, '#FFF3C4', 'Bungee')
            ctx.restore()
        cell('star', c_star)

        # daisy (pump)
        def c_daisy(w, h):
            cx, cy = 128, 128

            def petals():
                ctx.beginPath()
                for i in range(12):
                    a = (i / 12) * TAU
                    ctx.moveTo(cx, cy)
                    ctx.ellipse(cx + math.cos(a) * 62, cy + math.sin(a) * 62, 50, 21, a, 0, TAU)
            ctx.save()
            ctx.lineJoin = 'round'
            petals()
            ctx.strokeStyle = '#CFC6B8'
            ctx.lineWidth = 20
            ctx.stroke()
            petals()
            ctx.strokeStyle = '#FBF8F0'
            ctx.lineWidth = 16
            ctx.stroke()
            for i in range(12):
                a = (i / 12) * TAU
                ctx.beginPath()
                ctx.ellipse(cx + math.cos(a) * 62, cy + math.sin(a) * 62, 50, 21, a, 0, TAU)
                ctx.fillStyle = '#FFFDF6' if i % 2 else '#F6EEDD'
                ctx.fill()
                ctx.strokeStyle = 'rgba(227,102,43,0.55)'
                ctx.lineWidth = 3
                ctx.stroke()
            g = ctx.createRadialGradient(118, 116, 4, cx, cy, 44)
            g.addColorStop(0, '#FFE680')
            g.addColorStop(1, '#E89A1E')
            ctx.beginPath()
            ctx.arc(cx, cy, 40, 0, TAU)
            ctx.fillStyle = g
            ctx.fill()
            ctx.strokeStyle = '#C0661A'
            ctx.lineWidth = 4
            ctx.stroke()
            ctx.fillStyle = '#5A3A22'
            ctx.beginPath()
            ctx.arc(114, 120, 6, 0, TAU)
            ctx.arc(142, 120, 6, 0, TAU)
            ctx.fill()
            ctx.lineWidth = 5
            ctx.strokeStyle = '#5A3A22'
            ctx.lineCap = 'round'
            ctx.beginPath()
            ctx.arc(128, 132, 16, 0.25, math.pi - 0.25)
            ctx.stroke()
            ctx.restore()
        cell('daisy', c_daisy)

        # station logo 13 (M16)
        def c_logo13(w, h):
            def circ():
                ctx.beginPath()
                ctx.arc(128, 128, 104, 0, TAU)
            dieCut(ctx, circ, '#E23B3B', 10)
            ctx.beginPath()
            ctx.arc(128, 128, 84, 0, TAU)
            ctx.fillStyle = '#2F5BD3'
            ctx.fill()
            ctx.beginPath()
            ctx.arc(128, 128, 84, 0, TAU)
            ctx.strokeStyle = '#F4F1E8'
            ctx.lineWidth = 6
            ctx.stroke()
            text('13', 132, 138, 104, '#1B2F7A', 'Bungee')
            text('13', 128, 132, 104, '#F4F1E8', 'Bungee')
            ctx.save()
            ctx.beginPath()
            ctx.arc(128, 128, 104, 0, TAU)
            ctx.clip()
            gloss(ctx, 20, 20, 216, 216, 0.3)
            ctx.restore()
        cell('logo13', c_logo13)

        # gold medallion face (upgrades)
        def c_medal13(w, h):
            g = ctx.createRadialGradient(100, 90, 10, 128, 128, 128)
            g.addColorStop(0, '#FFF1B0')
            g.addColorStop(0.5, '#F2B640')
            g.addColorStop(1, '#A8651A')
            ctx.beginPath()
            ctx.arc(128, 128, 124, 0, TAU)
            ctx.fillStyle = g
            ctx.fill()
            ctx.beginPath()
            ctx.arc(128, 128, 100, 0, TAU)
            ctx.fillStyle = '#2F5BD3'
            ctx.fill()
            ctx.lineWidth = 10
            ctx.strokeStyle = '#E23B3B'
            ctx.stroke()
            for i in range(13):
                a = (i / 13) * TAU - math.pi / 2
                starPath(ctx, 128 + math.cos(a) * 113, 128 + math.sin(a) * 113, 7, 3)
                ctx.fillStyle = '#FFF6D0'
                ctx.fill()
            text('13', 133, 140, 108, '#10204E', 'Bungee')
            text('13', 128, 133, 108, '#FFE27A', 'Bungee', '#A8651A', 6)
            ctx.save()
            ctx.beginPath()
            ctx.arc(128, 128, 124, 0, TAU)
            ctx.clip()
            gloss(ctx, 10, 10, 236, 236, 0.35)
            ctx.restore()
        cell('medal13', c_medal13)

        # AGENT 13 keyhole badge (MP7)
        def c_agent13(w, h):
            def rr():
                ctx.beginPath()
                ctx.roundRect(18, 58, 220, 140, 40)
            dieCut(ctx, rr, '#E3662B', 9)
            ctx.fillStyle = '#FFD9A0'
            ctx.beginPath()
            ctx.roundRect(30, 70, 196, 116, 30)
            ctx.fill()
            ctx.fillStyle = '#2A2233'
            ctx.beginPath()
            ctx.arc(78, 110, 22, 0, TAU)
            ctx.fill()
            ctx.beginPath()
            ctx.moveTo(66, 118)
            ctx.lineTo(90, 118)
            ctx.lineTo(98, 168)
            ctx.lineTo(58, 168)
            ctx.closePath()
            ctx.fill()
            text('AGENT', 162, 104, 34, '#E3662B', 'Bungee')
            text('13', 162, 148, 52, '#2A2233', 'Bungee')
            gloss(ctx, 20, 60, 216, 136, 0.25)
        cell('agent13', c_agent13)

        # 10-4 trucker diamond (M60)
        def c_tenfour(w, h):
            def d():
                ctx.beginPath()
                ctx.moveTo(128, 14)
                ctx.lineTo(242, 128)
                ctx.lineTo(128, 242)
                ctx.lineTo(14, 128)
                ctx.closePath()
            ctx.save()
            ctx.lineJoin = 'round'
            dieCut(ctx, d, '#F4C81E', 9)
            ctx.beginPath()
            ctx.moveTo(128, 34)
            ctx.lineTo(222, 128)
            ctx.lineTo(128, 222)
            ctx.lineTo(34, 128)
            ctx.closePath()
            ctx.strokeStyle = '#3A2A1A'
            ctx.lineWidth = 7
            ctx.stroke()
            text('10-4', 128, 120, 64, '#3A2A1A', 'Bungee')
            text('GOOD BUDDY', 128, 164, 18, '#B5472A', 'Bungee')
            ctx.restore()
        cell('tenfour', c_tenfour)

        # Space Patrol 3000 (zapper)
        def c_space(w, h):
            def circ():
                ctx.beginPath()
                ctx.arc(128, 128, 108, 0, TAU)
            dieCut(ctx, circ, '#1B1E4A', 9)
            ctx.save()
            ctx.beginPath()
            ctx.arc(128, 128, 108, 0, TAU)
            ctx.clip()
            for i in range(40):
                ctx.fillStyle = 'rgba(255,244,214,%s)' % js_str(0.4 + rnd() * 0.6)
                ctx.beginPath()
                ctx.arc(rnd() * 256, rnd() * 256, 1 + rnd() * 2.2, 0, TAU)
                ctx.fill()
            ctx.beginPath()
            ctx.arc(150, 104, 40, 0, TAU)
            pg = ctx.createLinearGradient(120, 70, 180, 140)
            pg.addColorStop(0, '#FFB36B')
            pg.addColorStop(1, '#E3662B')
            ctx.fillStyle = pg
            ctx.fill()
            ctx.beginPath()
            ctx.ellipse(150, 104, 70, 16, -0.35, 0, TAU)
            ctx.strokeStyle = '#F4E03A'
            ctx.lineWidth = 7
            ctx.stroke()
            ctx.restore()
            # rocket
            ctx.save()
            ctx.translate(82, 132)
            ctx.rotate(0.6)
            ctx.fillStyle = '#F4F1E8'
            ctx.beginPath()
            ctx.moveTo(0, -46)
            ctx.quadraticCurveTo(20, -20, 14, 26)
            ctx.lineTo(-14, 26)
            ctx.quadraticCurveTo(-20, -20, 0, -46)
            ctx.fill()
            ctx.fillStyle = '#E23B3B'
            ctx.beginPath()
            ctx.moveTo(-14, 10)
            ctx.lineTo(-28, 34)
            ctx.lineTo(-12, 26)
            ctx.fill()
            ctx.beginPath()
            ctx.moveTo(14, 10)
            ctx.lineTo(28, 34)
            ctx.lineTo(12, 26)
            ctx.fill()
            ctx.beginPath()
            ctx.moveTo(0, -46)
            ctx.quadraticCurveTo(10, -36, 12, -26)
            ctx.lineTo(-12, -26)
            ctx.quadraticCurveTo(-10, -36, 0, -46)
            ctx.fill()
            ctx.fillStyle = '#7FE7FF'
            ctx.beginPath()
            ctx.arc(0, -6, 6, 0, TAU)
            ctx.fill()
            ctx.fillStyle = '#FFC23A'
            ctx.beginPath()
            ctx.moveTo(-8, 28)
            ctx.lineTo(0, 50)
            ctx.lineTo(8, 28)
            ctx.fill()
            ctx.restore()
            text('SPACE PATROL', 128, 198, 22, '#F4E03A', 'Bungee', '#1B1E4A', 4)
        cell('space', c_space)

        # Weather Watch 13 (chroma key)
        def c_weather(w, h):
            def rr():
                ctx.beginPath()
                ctx.roundRect(20, 20, 216, 216, 46)
            dieCut(ctx, rr, '#4AA8F0', 9)
            ctx.beginPath()
            ctx.arc(150, 96, 44, 0, TAU)
            ctx.fillStyle = '#FFD23A'
            ctx.fill()
            ctx.strokeStyle = '#FFD23A'
            ctx.lineWidth = 8
            ctx.lineCap = 'round'
            for i in range(9):
                a = (i / 9) * TAU
                ctx.beginPath()
                ctx.moveTo(150 + math.cos(a) * 54, 96 + math.sin(a) * 54)
                ctx.lineTo(150 + math.cos(a) * 68, 96 + math.sin(a) * 68)
                ctx.stroke()
            ctx.fillStyle = '#FFFFFF'
            ctx.beginPath()
            ctx.arc(84, 138, 30, 0, TAU)
            ctx.arc(118, 124, 36, 0, TAU)
            ctx.arc(150, 142, 26, 0, TAU)
            ctx.rect(70, 140, 90, 28)
            ctx.fill()
            text('WEATHER WATCH', 128, 196, 22, '#1E4A8A', 'Bungee')
            text('13', 206, 44, 30, '#E23B3B', 'Bungee')
        cell('weather', c_weather)

        # GROOVE HOUR rainbow (boom mic)
        def c_groove(w, h):
            def rr():
                ctx.beginPath()
                ctx.roundRect(16, 20, w - 32, h - 40, 60)
            dieCut(ctx, rr, '#6B3A6E', 9)
            cols = ['#E4473A', '#E3662B', '#F4C81E', '#52D24A', '#3FB8E8']
            ctx.save()
            ctx.beginPath()
            ctx.roundRect(16, 20, w - 32, h - 40, 60)
            ctx.clip()
            for i, c in enumerate(cols):
                ctx.strokeStyle = c
                ctx.lineWidth = 12
                ctx.beginPath()
                ctx.arc(w / 2, h + 40, 190 - i * 14, math.pi * 1.08, math.pi * 1.92)
                ctx.stroke()
            ctx.restore()
            text('Groove Hour', w / 2, h * 0.56, 70, '#FFE9A0', 'Shrikhand', '#3A1440', 12)
            text('THE', w / 2, h * 0.24, 24, '#FFD23A', 'Bungee')
        cell('groove', c_groove)

        # VU meter face
        def c_vu(w, h):
            g = ctx.createLinearGradient(0, 0, 0, h)
            g.addColorStop(0, '#FFF0B8')
            g.addColorStop(1, '#F2C866')
            ctx.fillStyle = g
            ctx.fillRect(0, 0, w, h)
            cx, cy, R = w / 2, h * 0.92, h * 0.7
            ctx.lineWidth = 5
            ctx.strokeStyle = '#3A2A1A'
            ctx.beginPath()
            ctx.arc(cx, cy, R, math.pi * 1.22, math.pi * 1.62)
            ctx.stroke()
            ctx.strokeStyle = '#E23B3B'
            ctx.lineWidth = 12
            ctx.beginPath()
            ctx.arc(cx, cy, R - 4, math.pi * 1.62, math.pi * 1.78)
            ctx.stroke()
            for i in range(11):
                a = math.pi * (1.22 + (i / 10) * 0.56)
                ctx.strokeStyle = '#E23B3B' if i > 7 else '#3A2A1A'
                ctx.lineWidth = 3 if i % 5 else 5
                ctx.beginPath()
                ctx.moveTo(cx + math.cos(a) * R, cy + math.sin(a) * R)
                ctx.lineTo(cx + math.cos(a) * (R + (14 if i % 5 else 24)), cy + math.sin(a) * (R + (14 if i % 5 else 24)))
                ctx.stroke()
            text('VU', cx, h * 0.62, 50, '#3A2A1A', 'Bungee')
            text('-20      0   +3', cx, h * 0.12, 18, '#3A2A1A', 'Bungee')
        cell('vu', c_vu)

        # LP record label
        def c_lp(w, h):
            g = ctx.createRadialGradient(128, 128, 10, 128, 128, 126)
            g.addColorStop(0, '#FF8A4A')
            g.addColorStop(1, '#E3662B')
            ctx.beginPath()
            ctx.arc(128, 128, 126, 0, TAU)
            ctx.fillStyle = g
            ctx.fill()
            ctx.lineWidth = 6
            ctx.strokeStyle = '#FFD23A'
            ctx.beginPath()
            ctx.arc(128, 128, 112, 0, TAU)
            ctx.stroke()
            text('BOOGIE', 128, 70, 34, '#FFF3C4', 'Shrikhand', '#8A2A10', 6)
            text('DOWN', 128, 188, 34, '#FFF3C4', 'Shrikhand', '#8A2A10', 6)
            ctx.fillStyle = '#FFD23A'
            ctx.font = FONT(16, 'Bungee')
            ctx.textAlign = 'center'
            ctx.fillText('WZTV 13 · 33⅓', 128, 150)
            ctx.fillStyle = '#6B2A10'
            ctx.beginPath()
            ctx.arc(128, 128, 12, 0, TAU)
            ctx.fill()
        cell('lp', c_lp)

        # Dymo embossed tape labels
        def dymo(name, t, bg):
            def fn(w, h):
                ctx.fillStyle = bg
                ctx.beginPath()
                ctx.roundRect(4, 8, w - 8, h - 16, 8)
                ctx.fill()
                ctx.fillStyle = 'rgba(255,255,255,0.18)'
                ctx.fillRect(8, 11, w - 16, 5)
                ctx.font = FONT(34, 'Bungee')
                ctx.textAlign = 'center'
                ctx.textBaseline = 'middle'
                ctx.fillStyle = 'rgba(0,0,0,0.35)'
                ctx.fillText(t, w / 2 + 2, h / 2 + 3)
                ctx.fillStyle = '#F7F4EE'
                ctx.fillText(t, w / 2, h / 2)
            cell(name, fn)
        dymo('dymoCrew', 'WZTV CREW 2', '#2A3A8A')
        dymo('dymoEng', 'ENG. DEPT 13', '#C8202A')

        # speaker grille
        def c_grille(w, h):
            ctx.fillStyle = '#3A3040'
            ctx.fillRect(0, 0, w, h)
            for y in range(7):
                for x in range(7):
                    px, py = 10 + x * 18 + (y % 2) * 9, 10 + y * 18
                    ctx.fillStyle = '#120C16'
                    ctx.beginPath()
                    ctx.arc(px, py, 5.5, 0, TAU)
                    ctx.fill()
                    ctx.fillStyle = 'rgba(255,255,255,0.14)'
                    ctx.beginPath()
                    ctx.arc(px, py + 1.5, 5.5, 0.2, 2.9)
                    ctx.fill()
        cell('grille', c_grille)

        # CHROMA-KEY nameplate
        def c_chromaPlate(w, h):
            g = ctx.createLinearGradient(0, 0, 0, h)
            g.addColorStop(0, '#E8ECF2')
            g.addColorStop(0.5, '#AEB6C2')
            g.addColorStop(1, '#D8DDE5')
            ctx.fillStyle = g
            ctx.beginPath()
            ctx.roundRect(4, 14, w - 8, h - 28, 16)
            ctx.fill()
            ctx.fillStyle = '#1E5BFF'
            ctx.beginPath()
            ctx.roundRect(14, 24, w - 28, h - 48, 10)
            ctx.fill()
            text('CHROMA-KEY', w / 2, h / 2 + 2, 40, '#F4F1E8', 'Bungee', '#10204E', 6)
        cell('chromaPlate', c_chromaPlate)

        # tube glass print (transparent bg)
        def c_tubeLabel(w, h):
            text('WZTV', w / 2, h * 0.34, 44, 'rgba(250,246,236,0.95)', 'Bungee')
            text('6L6·13', w / 2, h * 0.74, 30, 'rgba(250,246,236,0.95)', 'Bungee')
        cell('tubeLabel', c_tubeLabel)

        # TINY TELE nameplate
        def c_telePlate(w, h):
            g = ctx.createLinearGradient(0, 0, 0, h)
            g.addColorStop(0, '#F2F4F7')
            g.addColorStop(0.5, '#B9C0CA')
            g.addColorStop(1, '#E2E6EC')
            ctx.fillStyle = g
            ctx.beginPath()
            ctx.roundRect(4, 20, w - 8, h - 40, 14)
            ctx.fill()
            text('TINY TELE', w / 2, h / 2 + 2, 38, '#E3662B', 'Bungee', '#5A2A10', 5)
        cell('telePlate', c_telePlate)

        # channel dial face
        def c_dial13(w, h):
            ctx.beginPath()
            ctx.arc(128, 128, 124, 0, TAU)
            ctx.fillStyle = '#F4F1E8'
            ctx.fill()
            ctx.lineWidth = 6
            ctx.strokeStyle = '#E3662B'
            ctx.stroke()
            for i in range(12):
                a = -math.pi * 0.8 + (i / 11) * math.pi * 1.6
                n = i + 2
                text(str(n), 128 + math.sin(a) * 92, 128 - math.cos(a) * 92, 30 if n == 13 else 22,
                     '#E23B3B' if n == 13 else '#2A2233', 'Titan One')
        cell('dial13', c_dial13)
    return K.tex.canvas('wpn_stickers_v3', ATLAS, ATLAS, draw, {'repeat': False, 'fonts': True})


# ============================================================================================ chromacast
# The JS patches three's toon shader (onBeforeCompile) with this GLSL. Reference only: the Godot port of the finish
# is the "chroma" extension of godot/scripts/core/materials.gd (patchShader), fed by the spec below.
CH_VERT_PARS = '#include <common>\nvarying vec2 vChUv;\nvarying vec3 vChPos;'
CH_VERT_MAIN = '#include <begin_vertex>\nvChUv = uv;\nvChPos = position;'
CH_FRAG_PARS = """#include <common>
varying vec2 vChUv;
varying vec3 vChPos;
uniform float uChHue;
uniform float uChSpread;
uniform float uChLen;
uniform float uChDark;
vec3 chHue( float h ) {
  vec3 k = clamp( abs( mod( h * 6.0 + vec3( 0.0, 4.0, 2.0 ), 6.0 ) - 3.0 ) - 1.0, 0.0, 1.0 );
  return k * k * ( 3.0 - 2.0 * k );
}
float chHash( vec3 p ) {
  p = fract( p * 0.3183099 + vec3( 0.71, 0.113, 0.419 ) );
  p *= 17.0;
  return fract( p.x * p.y * p.z * ( p.x + p.y + p.z ) );
}"""
CH_FRAG_COLOR = """#include <color_fragment>
vec3 chEm = vec3( 0.0 );
{
  float t = vChUv.x;
  // full rainbow scroll without a signal; a +-spread swing around the signal hue with one
  float hue = uChSpread > 0.9 ? t * 0.9 - uTime * 0.1 + uChHue : uChHue + uChSpread * sin( t * 5.5 - uTime * 0.8 );
  vec3 cc = chHue( fract( hue + 0.04 * sin( vChUv.y * 40.0 + t * 9.0 ) ) );
  cc = pow( mix( vec3( 1.0 ), cc, 0.92 ), vec3( 1.5 ) );
  // scrolling colour-bar stripes: groups of 7 thin SMPTE bars
  float s = vChUv.x * uChLen * 70.0 + vChUv.y * 40.0 - uTime * 2.0;
  float cell = floor( s );
  float f = fract( s );
  float grp = mod( cell, 17.0 );
  float band = step( grp, 6.5 ) * smoothstep( 0.0, 0.1, f ) * ( 1.0 - smoothstep( 0.9, 1.0, f ) );
  vec3 bar = uBars[ int( mod( grp, 7.0 ) ) ];
  cc = mix( cc, bar * bar, band * 0.8 );
  cc *= min( 1.0, 0.5 / max( dot( cc, vec3( 0.299, 0.587, 0.114 ) ), 1e-3 ) );
  cc *= uChDark;
  diffuseColor.rgb *= cc;
  chEm = cc * 0.3;
  float sp = chHash( floor( vChPos * 150.0 ) );
  float tw = step( 0.972, sp ) * pow( max( 0.0, sin( uTime * 3.3 + sp * 91.0 ) ), 3.0 );
  chEm += vec3( 1.0, 0.96, 0.88 ) * tw * 2.2;
}"""
CH_FRAG_EMIS = '#include <emissivemap_fragment>\ntotalEmissiveRadiance += chEm;'


def patchChroma(m, u):
    """JS: m.userData.chroma = u + onBeforeCompile shader patch. Here: the toon spec becomes kind 'chromacast' with
    spec["chroma"] = u (materials.gd fromSpec -> toon + patchShader(mat, "chroma", u))."""
    if m is None or m.extra.get('chroma'):
        return
    m.kind = 'chromacast'
    m.extra['chroma'] = u


# Chromacast toon material for weapon `id` (variant 'a' bright body / 'b' darker trim), cached by the engine.
def chromaMat(W, variant='a'):
    game = W.game
    name = 'chroma|%s|%s|%s' % (W.id, W.signal or 'none', variant)
    base = {'rough': 0.32, 'metal': 0.25} if variant == 'b' else {'rough': 0.26, 'metal': 0.18}
    m = game.mats.toon('#ffffff', {**base, 'rim': 0.32, 'rimColor': '#FFFFFF', 'rimPower': 2.4, 'env': 0.22,
                                   'keepColor': True, 'vertexColors': True, 'name': name})
    if not m.extra.get('chroma'):
        hsl = JSObj(h=0, s=0, l=0)
        if W.signal:
            THREE.Color(SIGNALS[W.signal]).getHSL(hsl)
        u = {
            'uChHue': {'value': hsl.h if W.signal else 0.0},
            'uChSpread': {'value': 0.1 if W.signal else 1},
            'uChLen': {'value': 0.3},
            'uChDark': {'value': 0.55 if variant == 'b' else 1},
        }
        patchChroma(m, u)
        # the player swaps held-weapon materials to their heroFade variant: pre-patch the cached instance it will get
        patchChroma(game.mats.variant(m, {'heroFade': True}), u)
    if not any(x is m for x in W.chromaMats):
        W.chromaMats.append(m)
    return m


def _apply4(P, m4):
    """Vector3.applyMatrix4 over an (n, 3) array (three's formula, perspective divide included)."""
    e = m4.elements
    x, y, z = P[:, 0], P[:, 1], P[:, 2]
    w = 1 / (e[3] * x + e[7] * y + e[11] * z + e[15])
    return ((e[0] * x + e[4] * y + e[8] * z + e[12]) * w, (e[1] * x + e[5] * y + e[9] * z + e[13]) * w,
            (e[2] * x + e[6] * y + e[10] * z + e[14]) * w)


# Writes chromacast coordinates into the UVs of every chroma mesh: u = 0 (rear) .. 1 (muzzle), v = height (m).
def chromaUV(W):
    h = W.root
    h.updateMatrixWorld(True)
    inv = THREE.Matrix4().copy(h.matrixWorld).invert()
    lst = []
    h.traverse(lambda o: lst.append(o) if (getattr(o, 'isMesh', False) and o.userData.chroma) else None)
    if not lst:
        return
    mt = THREE.Matrix4()
    z0, z1 = math.inf, -math.inf
    for o in lst:
        mt.multiplyMatrices(inv, o.matrixWorld)
        _, _, vz = _apply4(np.asarray(o.geometry.attributes.position, dtype=np.float64), mt)
        if len(vz):
            z0 = min(z0, float(vz.min()))
            z1 = max(z1, float(vz.max()))
    ln = max(0.05, z1 - z0)
    for o in lst:
        mt.multiplyMatrices(inv, o.matrixWorld)
        g = o.geometry
        _, vy, vz = _apply4(np.asarray(g.attributes.position, dtype=np.float64), mt)
        uv = np.empty((len(vz), 2))
        uv[:, 0] = (z1 - vz) / ln
        uv[:, 1] = vy
        g.setAttribute('uv', BufferAttribute(uv, 2))
    for m in W.chromaMats:
        m.extra['chroma']['uChLen']['value'] = ln


# ============================================================================================ build context
class WeaponCtx:
    """The JS build context W = { game, id, opts, up, signal, root, mats, parts, woodMat, chromaMats } + helpers."""
    pass


def makeCtx(game, id, opts, root):
    up = _truthy(opts.get('upgraded'))
    signal = opts.get('signal') if (_truthy(opts.get('signal')) and opts.get('signal') in SIGNALS) else None
    mats = JSObj(
        paint=K.mat(game, 'plastic', '#ffffff', KEEP),
        steel=K.mat(game, 'metal', '#ffffff', {**KEEP, 'rough': 0.34, 'metal': 0.5, 'env': 0.5, 'rim': 0.3}),
        chrome=K.mat(game, 'chrome', '#ffffff', KEEP),
        decal=K.mat(game, 'plastic', '#ffffff', {**KEEP, 'map': stickers(), 'alphaTest': 0.5}),
    )
    W = WeaponCtx()
    W.game, W.id, W.opts, W.up, W.signal, W.root, W.mats = game, id, opts, up, signal, root, mats
    W.parts, W.woodMat, W.chromaMats = JSObj(), None, []

    def wood(base=None, o=None):
        base = PAL.walnut if base is None else base
        o = o or {}
        W.woodMat = K.mat(game, _d(o, 'preset', 'lacquer'), '#ffffff',
                          {**KEEP, 'map': K.tex.wood(base, {'dark': _d(o, 'dark', 0.42)})})
        return W.woodMat
    W.wood = wood

    # add(geo, role, color, o): role = paint | steel | chrome | gold | brass | wood | decal | glow | glass | <Material>
    # o: { pos, rot, scale, parent, name, up (true|'a'|'b'|false: chromacast when upgraded; default true for steel),
    #      intensity (glow), opacity (glass), noAO, noOcclude, noShadow }
    def add(geo, role='paint', color=None, o=None):
        o = o or {}
        tint = color
        if role == 'paint':
            mat = mats.paint
            tint = color if color is not None else '#ffffff'
        elif role == 'steel':
            mat = mats.steel
            tint = color if color is not None else STEEL
        elif role == 'chrome':
            mat = mats.chrome
            tint = color if color is not None else CHROME
        elif role == 'gold':
            mat = mats.chrome
            tint = color if color is not None else GOLD
        elif role == 'brass':
            mat = mats.chrome
            tint = color if color is not None else BRASS
        elif role == 'wood':
            mat = W.woodMat or W.wood()
        elif role == 'decal':
            mat = mats.decal
            tint = None
        elif role == 'glow':
            mat = K.glow(game, color if color is not None else PAL.tungsten, _d(o, 'intensity', 2.5))
            tint = None
        elif role == 'glass':
            mat = game.mats.toon(color if color is not None else '#DDEEFF', {
                'rough': 0.06, 'transparent': True, 'opacity': _d(o, 'opacity', 0.14), 'rim': 0.45,
                'rimColor': '#FFFFFF', 'rimPower': 2.6, 'env': 0.7, 'depthWrite': False, 'keepColor': True,
                'name': 'wpn_glass'})
            tint = None
        else:
            mat = role if (role is not None and getattr(role, 'isMaterial', False)) else mats.paint
        upFlag = o.get('up') if o.get('up') is not None else (role == 'steel')
        chroma = ('b' if upFlag == 'b' else 'a') if (up and _truthy(upFlag)) else None
        if chroma:
            mat = chromaMat(W, chroma)
            tint = o.get('upTint')
        g = geo
        if tint or chroma:
            g = geo.clone()
        if tint:
            K.tint(g, tint)
        mesh = K.m(g, mat, {'pos': o.get('pos'), 'rot': o.get('rot'), 'scale': o.get('scale'), 'name': o.get('name')})
        if chroma:
            mesh.userData.chroma = 1
        if o.get('noAO') or role == 'glass' or role == 'glow':
            mesh.userData.noAO = True
        if o.get('noOcclude') or role == 'glow' or role == 'glass':
            mesh.userData.noOcclude = True
        if o.get('noShadow'):
            mesh.userData.noShadow = True
        (o.get('parent') if o.get('parent') is not None else root).add(mesh)
        return mesh
    W.add = add

    # Animated sub-group (kept out of the merge) registered in userData.parts.
    def part(name, pos=None, parent=None, rot=None):
        pos = [0, 0, 0] if pos is None else pos
        parent = root if parent is None else parent
        p = THREE.Group()
        p.name = name
        p.position.fromArray(pos)
        if rot:
            p.rotation.set(rot[0], rot[1], rot[2])
        p.userData.noMerge = True
        parent.add(p)
        W.parts[name] = p
        return p
    W.part = part

    # Static sub-group (mergeable): a local frame for a cluster of parts (tilted grips, etc.).
    def group(pos=None, rot=None, parent=None):
        pos = [0, 0, 0] if pos is None else pos
        parent = root if parent is None else parent
        p = THREE.Group()
        p.position.fromArray(pos)
        if rot:
            p.rotation.set(rot[0], rot[1], rot[2])
        parent.add(p)
        return p
    W.group = group

    # Die-cut sticker plane from the atlas. face: '+x' | '-x' | '+y' | '-z' | '+z'; spin rotates it in its plane.
    def sticker(name, w, h, o=None):
        o = o or {}
        g = THREE.PlaneGeometry(w, h)
        K.uvRect(g, *cellUV(name))
        if o.get('spin'):
            g.rotateZ(o['spin'])
        face = _d(o, 'face', '+x')
        if face == '+x':
            g.rotateY(math.pi / 2)
        elif face == '-x':
            g.rotateY(-math.pi / 2)
        elif face == '+y':
            g.rotateX(-math.pi / 2)
        elif face == '-z':
            g.rotateY(math.pi)
        return W.add(g, 'decal', None, {'pos': o.get('pos'), 'rot': o.get('rot'), 'parent': o.get('parent'),
                                        'noOcclude': True})
    W.sticker = sticker

    # Printed disc (dial faces, labels) facing `face` with the atlas cell mapped on it.
    def disc(name, r, o=None):
        o = o or {}
        g = THREE.CircleGeometry(r, _d(o, 'seg', 28))
        K.uvRect(g, *cellUV(name))
        if o.get('spin'):
            g.rotateZ(o['spin'])
        face = _d(o, 'face', '-z')
        if face == '+x':
            g.rotateY(math.pi / 2)
        elif face == '-x':
            g.rotateY(-math.pi / 2)
        elif face == '+y':
            g.rotateX(-math.pi / 2)
        elif face == '-z':
            g.rotateY(math.pi)
        return W.add(g, 'decal', None, {'pos': o.get('pos'), 'rot': o.get('rot'), 'parent': o.get('parent'),
                                        'noOcclude': True})
    W.disc = disc
    return W


# ============================================================================================ upgrade kit
# spec: { medal:{pos, r, face, parent}, ears:{pos, s}, fins:{pos, s, n, spread}, ring:{pos, r, len}, trim:[[x,y,z],[x,y,z]] }
def upgradeKit(W, spec):
    add = W.add
    if spec.get('medal'):
        md = spec['medal']
        pos, r, face, parent = md['pos'], _d(md, 'r', 0.022), _d(md, 'face', '+x'), md.get('parent')
        s = -1 if face == '-x' else 1
        bez = add(K.lathe([[0, 0], [r * 1.18, 0], [r * 1.26, r * 0.18], [r * 1.12, r * 0.34], [r * 0.98, r * 0.3],
                           [0, r * 0.3]], {'round': r * 0.1, 'seg': 26}), 'gold', GOLD,
                  {'pos': pos, 'parent': parent, 'up': False})
        bez.rotation.z = -s * math.pi / 2
        face3 = V3(*pos).add(V3(s * r * 0.31, 0, 0))
        W.disc('medal13', r, {'face': '+x' if s > 0 else '-x', 'pos': face3.toArray(), 'parent': parent})
    if spec.get('ears'):
        pos, s = spec['ears']['pos'], _d(spec['ears'], 's', 1)
        base = W.group(pos)
        add(K.lathe([[0, 0], [0.018 * s, 0], [0.02 * s, 0.008 * s], [0.012 * s, 0.018 * s], [0, 0.02 * s]],
                    {'round': 0.004 * s, 'seg': 14}), 'paint', INK, {'parent': base})
        for sx in [-1, 1]:
            dr = V3(sx * 0.62, 1, 0.3).normalize()
            ln = 0.12 * s
            rod = K.cyl(0.0022 * s, 0.0032 * s, ln, {'bevel': 0.001, 'seg': 6}).clone()
            q = THREE.Quaternion().setFromUnitVectors(V3(0, 1, 0), dr)
            rod.applyQuaternion(q)
            add(rod, 'chrome', None, {'parent': base, 'pos': [0, 0.015 * s, 0]})
            tip = dr.clone().multiplyScalar(ln).add(V3(0, 0.015 * s, 0))
            add(sphere(0.0065 * s, 10, 8), 'gold', GOLD, {'parent': base, 'pos': tip.toArray(), 'up': False})
    if spec.get('fins'):
        # swept tail fins radiating around the local z axis, sweeping backward (+z) from `pos`
        fs = spec['fins']
        pos, s, n, rot = fs['pos'], _d(fs, 's', 1), _d(fs, 'n', 3), _d(fs, 'rot', 0)
        spread, r0 = _d(fs, 'spread', 0), _d(fs, 'r0', 0)
        fin = side([[0.02, 0.0], [-0.012, 0.0], [-0.05, 0.034], [-0.07, 0.062], [-0.058, 0.066], [-0.02, 0.036]],
                   0.008, {'round': 0.006, 'bevel': 0.003})
        grp = W.group(pos, [rot, 0, 0])
        for i in range(n):
            wrap = THREE.Group()
            wrap.rotation.z = ((1 if i else -1) * math.pi / 2 if n == 2 else (i / n) * TAU) + spread
            grp.add(wrap)
            add(fin, 'steel', '#C8963C', {'parent': wrap, 'up': 'b', 'scale': s, 'pos': [0, r0, 0]})
    if spec.get('ring'):
        rg = spec['ring']
        pos, r, ln = rg['pos'], _d(rg, 'r', 0.024), _d(rg, 'len', 0.03)
        add(zlathe([[r * 0.7, 0], [r, 0], [r * 1.12, ln * 0.3], [r * 1.12, ln * 0.7], [r, ln], [r * 0.7, ln]],
                   {'round': r * 0.12, 'seg': 22}), 'chrome', None, {'pos': pos})
    if spec.get('trim'):
        a, b = spec['trim']
        add(K.tube([a, b], 0.0035, {'seg': 2, 'radial': 6}), 'chrome')


# ============================================================================================ weapons
# ---------------------------------------------------------------------------------------------- .38 revolver
def revolver(W):
    add = W.add
    W.wood(PAL.walnut, {'dark': 0.45})
    boreY, drumY = 0.121, 0.094

    # walnut grip with finger bumps, tilted back
    gripG = W.group([0, 0, 0], [-0.28, 0, 0])
    gripPts = [[0.03, 0.055], [0.028, 0.03], [0.035, 0.012], [0.026, -0.004], [0.034, -0.023], [0.025, -0.04],
               [0.031, -0.058], [0.022, -0.08],
               [-0.03, -0.086], [-0.037, -0.06], [-0.035, 0.0], [-0.03, 0.04], [-0.02, 0.066], [0.012, 0.07]]
    add(side(gripPts, 0.056, {'bevel': 0.018, 'round': 0.01, 'uv': 6, 'steps': 3, 'bevelSeg': 3}), 'wood', None,
        {'parent': gripG})
    # brass escutcheons + the gold star sticker
    for s in [-1, 1]:
        add(xcyl(0.0085, 0.004, {'rt': 0.0075, 'seg': 14}), 'brass', None,
            {'parent': gripG, 'pos': [s * 0.0275 - (0.004 if s < 0 else 0), 0.034, -0.002],
             'rot': [0, math.pi, 0] if s < 0 else None})
    W.sticker('star', 0.046, 0.046, {'parent': gripG, 'pos': [0.0292, -0.022, 0.0], 'face': '+x'})
    # butt cap
    add(side([[0.022, -0.074], [0.024, -0.082], [-0.03, -0.09], [-0.036, -0.078], [-0.03, -0.076]], 0.05,
             {'bevel': 0.01, 'round': 0.006}), 'steel', None, {'parent': gripG, 'up': 'b'})

    # chrome frame
    frame = [[-0.005, 0.128], [0.012, 0.152], [0.14, 0.152], [0.152, 0.14], [0.152, 0.075], [0.135, 0.058],
             [0.09, 0.05], [0.07, 0.04],
             [0.03, 0.036], [0.0, 0.05], [-0.014, 0.075], [-0.014, 0.1]]
    add(side(frame, 0.036, {'bevel': 0.008, 'round': 0.01, 'steps': 3}), 'chrome', None, {'up': 'a'})
    # side plate screws + cylinder latch
    for f, u in [[0.0, 0.092], [0.03, 0.07], [0.012, 0.132]]:
        add(xcyl(0.0045, 0.003, {'rt': 0.0038, 'seg': 10}), 'steel', None, {'pos': [0.0175, u, -f]})
    add(K.box(0.008, 0.013, 0.024, 0.004), 'steel', None, {'pos': [-0.019, 0.108, -0.028]})
    # rear sight groove
    add(K.box(0.008, 0.006, 0.05, 0.002), 'paint', INK, {'pos': [0, 0.1515, -0.07]})

    # fluted drum (rotates around z)
    drum = W.part('drum', [0, drumY, -0.05])
    add(fluted(0.047, 0.075, 6, 0.011, {'phase': 0.5}), 'steel', None, {'parent': drum})
    for i in range(6):
        a = math.pi / 2 + (i / 6) * TAU
        cx, cy = math.cos(a) * 0.027, math.sin(a) * 0.027
        add(THREE.CircleGeometry(0.0105, 16).rotateY(math.pi), 'paint', INK, {'parent': drum, 'pos': [cx, cy, -0.0752]})
        add(K.lathe([[0, 0], [0.0078, 0], [0.0078, 0.004], [0.005, 0.009], [0, 0.011]],
                    {'round': 0.002, 'seg': 10, 'steps': 1}).clone().rotateX(-math.pi / 2), 'brass', None,
            {'parent': drum, 'pos': [cx, cy, -0.069]})
    add(zcyl(0.007, 0.006, 0.006, {'seg': 12}), 'chrome', None, {'parent': drum, 'pos': [0, 0, -0.074]})

    # barrel + underlug + crown + front sight
    add(zlathe([[0, 0], [0.024, 0], [0.024, 0.02], [0.0215, 0.098], [0, 0.098]], {'round': 0.004, 'seg': 22}), 'steel',
        None, {'pos': [0, boreY, -0.15]})
    add(side([[0.148, 0.112], [0.236, 0.112], [0.242, 0.1], [0.232, 0.086], [0.148, 0.086]], 0.022,
             {'bevel': 0.006, 'round': 0.008}), 'steel')
    add(zlathe([[0, 0], [0.0255, 0], [0.027, 0.011], [0.023, 0.018], [0.0115, 0.018], [0.0095, 0.013], [0, 0.013]],
               {'round': 0.002, 'seg': 22}), 'chrome', None, {'pos': [0, boreY, -0.24]})
    add(THREE.CircleGeometry(0.0098, 16).rotateY(math.pi), 'paint', INK, {'pos': [0, boreY, -0.2532]})
    add(side([[0.206, 0.139], [0.246, 0.139], [0.246, 0.152], [0.232, 0.154]], 0.012, {'bevel': 0.004, 'round': 0.004}),
        'steel')
    add(K.box(0.0125, 0.006, 0.008, 0.002), 'paint', PAL.channelRed, {'pos': [0, 0.1505, -0.24]})

    # hammer (spur) + gold trigger + chrome guard
    hammer = [[0.022, 0.112], [0.026, 0.138], [0.01, 0.15], [-0.016, 0.156], [-0.034, 0.158], [-0.04, 0.148],
              [-0.024, 0.138], [-0.006, 0.114]]
    add(side(hammer, 0.018, {'bevel': 0.005, 'round': 0.006}), 'steel')
    add(side([[-0.012, 0.152], [-0.03, 0.155], [-0.034, 0.149], [-0.016, 0.146]], 0.0185,
             {'bevel': 0.002, 'round': 0.002}), 'paint', INK, {'up': False})
    add(side([[0.062, 0.045], [0.068, 0.022], [0.064, 0.0], [0.053, -0.012], [0.047, -0.006], [0.053, 0.012],
              [0.051, 0.04]], 0.012, {'bevel': 0.004, 'round': 0.004}), 'gold', GOLD, {'up': False})
    add(K.tube([P(0.096, 0.048), P(0.099, 0.02), P(0.09, -0.008), P(0.066, -0.023), P(0.04, -0.018), P(0.03, 0.0),
                P(0.028, 0.036)], 0.0078, {'seg': 24, 'radial': 8}), 'chrome')

    if W.up:
        # SPECIAL REPORT: flashbulb reflector around the muzzle
        add(zlathe([[0.028, 0], [0.034, 0.002], [0.052, 0.018], [0.056, 0.024], [0.05, 0.024], [0.03, 0.01],
                    [0.027, 0.004]], {'round': 0.002, 'seg': 28}), 'chrome', None, {'pos': [0, boreY, -0.226]})
        add(sphere(0.008, 10, 8), 'glow', '#EAF6FF', {'pos': [0, boreY + 0.038, -0.244], 'intensity': 2})
    return {
        'muzzle': [0, boreY, -0.262],
        'leftHand': [-0.032, -0.024, -0.004],
        'up': {
            'medal': {'pos': [0.0292, 0.03, -0.002], 'r': 0.016, 'parent': gripG},
            'ears': {'pos': [0, 0.152, -0.02], 's': 0.7},
            'fins': {'pos': [0, boreY, -0.215], 's': 0.5, 'n': 3, 'r0': 0.019, 'spread': math.pi / 3},
            'ring': {'pos': [0, boreY, -0.2], 'r': 0.0245, 'len': 0.02},
        },
    }


# ---------------------------------------------------------------------------------------------- Model 37 pump
def pump(W):
    add = W.add
    W.wood(PAL.teak, {'dark': 0.62})
    boreY = 0.07
    # navy receiver with a rounded top, daisy sticker, pins
    add(side([[0.03, 0.0], [0.25, 0.0], [0.258, 0.03], [0.255, 0.088], [0.238, 0.1], [0.07, 0.102], [0.034, 0.09]],
             0.066, {'bevel': 0.018, 'round': 0.014, 'steps': 3}), 'steel')
    for f in [0.06, 0.225]:
        for s in [-1, 1]:
            add(xcyl(0.005, 0.003, {'rt': 0.004, 'seg': 10}), 'chrome', None,
                {'pos': [s * 0.0325, 0.018, -f], 'rot': [0, math.pi, 0] if s < 0 else None})
    W.sticker('daisy', 0.066, 0.066, {'pos': [0.0334, 0.054, -0.15]})
    # barrel, vent rib, crown, brass bead
    add(zcyl(0.021, 0.02, 0.47, {'seg': 20}), 'steel', None, {'pos': [0, boreY, -0.25]})
    add(K.box(0.013, 0.006, 0.44, 0.0025), 'chrome', None, {'pos': [0, boreY + 0.023, -0.48]})
    add(zlathe([[0, 0], [0.0235, 0], [0.025, 0.01], [0.022, 0.02], [0.012, 0.02], [0.01, 0.016], [0, 0.016]],
               {'round': 0.002, 'seg': 20}), 'chrome', None, {'pos': [0, boreY, -0.705]})
    add(THREE.CircleGeometry(0.0105, 16).rotateY(math.pi), 'paint', INK, {'pos': [0, boreY, -0.7215]})
    add(sphere(0.0078, 12, 8), 'brass', None, {'pos': [0, boreY + 0.03, -0.708]})
    # magazine tube + knurled cap + barrel band
    add(zcyl(0.017, 0.017, 0.38, {'seg': 18}), 'steel', None, {'pos': [0, 0.03, -0.25]})
    add(zlathe(ribProfile(0.034, 0.0195, 4, 0.0025, 0.016), {'seg': 16}), 'chrome', None, {'pos': [0, 0.03, -0.625]})
    add(side([[0.585, 0.018], [0.612, 0.018], [0.612, 0.086], [0.585, 0.086]], 0.03, {'bevel': 0.006, 'round': 0.008}),
        'steel')
    # ringtail pump (slides along z)
    pumpG = W.part('pump', [0, 0.04, -0.33])
    add(zlathe(ribProfile(0.19, 0.037, 8, 0.0055, 0.03, {'gw': 0.0045}), {'seg': 20}), 'wood', None,
        {'parent': pumpG, 'scale': [1, 1.06, 1]})
    for s in [-1, 1]:
        add(K.box(0.005, 0.008, 0.1, 0.002), 'steel', None, {'parent': pumpG, 'pos': [s * 0.02, -0.008, 0.045]})
    # teak stock with white-line spacer and plum recoil pad
    add(thick(side([[0.035, 0.092], [-0.02, 0.058], [-0.1, 0.068], [-0.33, 0.08], [-0.338, 0.062], [-0.338, -0.094],
                    [-0.33, -0.104], [-0.26, -0.092], [-0.12, -0.06], [-0.04, -0.04], [0.0, -0.034], [0.036, -0.004]],
                   0.058, {'bevel': 0.02, 'round': 0.016, 'steps': 3, 'bevelSeg': 3, 'uv': 3.2}), 0.0, 0.82, 0.3, 1.0),
        'wood')
    add(side([[-0.334, 0.077], [-0.343, 0.078], [-0.345, -0.099], [-0.336, -0.1]], 0.056,
             {'bevel': 0.012, 'round': 0.003}), 'paint', PAL.cream)
    add(side([[-0.341, 0.079], [-0.368, 0.081], [-0.374, 0.07], [-0.376, -0.094], [-0.37, -0.102], [-0.343, -0.1]],
             0.058, {'bevel': 0.016, 'round': 0.008}), 'paint', '#5A2E36')
    # trigger group
    add(K.tube([P(0.124, 0.004), P(0.122, -0.03), P(0.1, -0.049), P(0.07, -0.051), P(0.045, -0.036), P(0.035, -0.004)],
               0.0072, {'seg': 20, 'radial': 8}), 'steel')
    add(side([[0.095, 0.005], [0.1, -0.015], [0.094, -0.034], [0.086, -0.036], [0.089, -0.016], [0.086, 0.004]], 0.011,
             {'bevel': 0.0035, 'round': 0.004}), 'brass', None)
    add(xcyl(0.0058, 0.05, {'seg': 12}), 'paint', PAL.channelRed, {'pos': [-0.025, -0.003, -0.116]})
    return {
        'muzzle': [0, boreY, -0.725],
        'leftHand': [-0.018, 0.006, -0.43],
        'anim': {'pump': {'axis': 'z', 'travel': 0.07}},
        'up': {
            'medal': {'pos': [0.0334, 0.052, -0.215], 'r': 0.02},
            'ears': {'pos': [0, 0.1, -0.09], 's': 0.8},
            'fins': {'pos': [0, boreY, -0.64], 's': 0.6, 'n': 3, 'r0': 0.02, 'spread': math.pi / 3},
            'ring': {'pos': [0, boreY, -0.66], 'r': 0.0235, 'len': 0.026},
            'trim': [[0.0345, 0.09, -0.06], [0.0345, 0.09, -0.24]],
        },
    }


# ---------------------------------------------------------------------------------------------- MP7 "Agent 13"
def mp7(W):
    add = W.add
    OLIVE, OLIVE2, ORANGE = '#62703A', '#4B5530', PAL.burntOrange
    boreY = 0.1
    # pistol grip + long magazine (drops out on reload)
    gripG = W.group([0, 0, 0], [-0.22, 0, 0])
    add(side([[0.028, 0.05], [0.026, 0.02], [0.033, 0.0], [0.024, -0.018], [0.032, -0.036], [0.022, -0.052],
              [0.026, -0.07], [0.018, -0.08], [-0.03, -0.082], [-0.035, -0.05], [-0.032, 0.0], [-0.028, 0.05]],
             0.05, {'bevel': 0.016, 'round': 0.01, 'steps': 3, 'bevelSeg': 3}), 'paint', OLIVE,
        {'parent': gripG, 'up': 'b'})
    mag = W.part('mag', [0, 0, 0], gripG)
    add(side([[0.017, -0.06], [0.017, -0.2], [-0.021, -0.2], [-0.021, -0.06]], 0.03, {'bevel': 0.007, 'round': 0.006}),
        'steel', None, {'parent': mag})
    add(side([[0.024, -0.195], [0.025, -0.214], [-0.028, -0.216], [-0.028, -0.196]], 0.037,
             {'bevel': 0.009, 'round': 0.006}), 'paint', ORANGE, {'parent': mag})
    for i in range(3):
        add(K.box(0.031, 0.004, 0.03, 0.0015), 'paint', INK, {'parent': mag, 'pos': [0, -0.1 - i * 0.025, 0.002]})
    # receiver body
    add(side([[-0.1, 0.045], [0.1, 0.045], [0.12, 0.06], [0.2, 0.07], [0.226, 0.085], [0.226, 0.12], [0.21, 0.133],
              [-0.08, 0.133], [-0.105, 0.115]],
             0.058, {'bevel': 0.016, 'round': 0.012, 'steps': 3}), 'paint', OLIVE, {'up': 'a'})
    add(K.box(0.004, 0.02, 0.06, 0.003), 'paint', INK, {'pos': [0.0292, 0.115, -0.05]})
    W.sticker('agent13', 0.072, 0.072, {'pos': [0.0296, 0.086, -0.13]})
    # trigger guard + orange trigger + selector
    add(K.tube([P(0.1, 0.047), P(0.105, 0.012), P(0.09, -0.012), P(0.058, -0.017), P(0.038, -0.006), P(0.034, 0.03)],
               0.0082, {'seg': 20, 'radial': 8}), 'paint', OLIVE, {'up': 'b'})
    add(side([[0.068, 0.047], [0.074, 0.028], [0.07, 0.01], [0.062, 0.004], [0.064, 0.022], [0.06, 0.045]], 0.011,
             {'bevel': 0.0035, 'round': 0.004}), 'paint', ORANGE)
    sel = side([[0.0, 0.004], [0.026, 0.008], [0.028, -0.002], [0.0, -0.006]], 0.006, {'bevel': 0.002, 'round': 0.003})
    add(sel, 'paint', ORANGE, {'pos': [0.032, 0.083, 0.01]})
    add(xcyl(0.008, 0.004, {'seg': 12}), 'paint', ORANGE, {'pos': [0.029, 0.083, -0.01]})
    # barrel + ribbed flash hider
    add(zcyl(0.0145, 0.0135, 0.05), 'steel', None, {'pos': [0, boreY, -0.222]})
    add(zlathe(ribProfile(0.036, 0.018, 3, 0.003, 0.015), {'seg': 18}), 'steel', None, {'pos': [0, boreY, -0.262]})
    add(THREE.CircleGeometry(0.009, 14).rotateY(math.pi), 'paint', INK, {'pos': [0, boreY, -0.2985]})
    # folding foregrip
    add(side([[0.155, 0.05], [0.19, 0.05], [0.192, 0.0], [0.188, -0.05], [0.182, -0.062], [0.162, -0.062],
              [0.156, -0.05], [0.152, 0.0]], 0.034, {'bevel': 0.012, 'round': 0.01, 'steps': 3}), 'paint', OLIVE,
        {'up': 'b'})
    add(side([[0.158, -0.056], [0.186, -0.056], [0.184, -0.074], [0.16, -0.074]], 0.037,
             {'bevel': 0.01, 'round': 0.006}), 'paint', ORANGE)
    add(xcyl(0.007, 0.042, {'seg': 12}), 'chrome', None, {'pos': [-0.021, 0.05, -0.172]})
    # telescoping stock: twin rods + butt plate with orange pad
    for s in [-1, 1]:
        add(K.tube([[s * 0.019, 0.098, 0.1], [s * 0.019, 0.098, 0.205]], 0.0068, {'seg': 2, 'radial': 10}), 'steel')
    add(side([[-0.195, 0.142], [-0.225, 0.142], [-0.228, 0.02], [-0.198, 0.02]], 0.054,
             {'bevel': 0.014, 'round': 0.012}), 'paint', OLIVE, {'up': 'b'})
    add(side([[-0.225, 0.137], [-0.239, 0.137], [-0.241, 0.025], [-0.227, 0.025]], 0.05,
             {'bevel': 0.01, 'round': 0.008}), 'paint', ORANGE)
    # top rail (toothed) + oversized tube sight
    rail = [[-0.07, 0.128], [0.19, 0.128], [0.19, 0.143]]
    for i in range(12):
        f1 = 0.19 - i * 0.0217
        rail += [[f1 - 0.004, 0.146], [f1 - 0.013, 0.146], [f1 - 0.0145, 0.141]]
    rail.append([-0.07, 0.141])
    add(side(rail, 0.024, {'bevel': 0.0025, 'round': 0.0015, 'steps': 1, 'bevelSeg': 1}), 'steel')
    sy = 0.188
    for f in [0.05, 0.12]:
        add(K.box(0.022, 0.03, 0.022, 0.005), 'steel', None, {'pos': [0, 0.158, -f]})
    add(zlathe([[0.022, 0.012], [0.022, 0.0], [0.033, 0.0], [0.035, 0.012], [0.031, 0.02], [0.031, 0.09],
                [0.035, 0.098], [0.035, 0.11], [0.022, 0.11], [0.022, 0.098]], {'round': 0.002, 'seg': 26}),
        'paint', OLIVE2, {'pos': [0, sy, -0.03], 'up': 'b'})
    for t in [0.0, 0.098]:
        add(zlathe([[0.0335, 0], [0.0365, 0.002], [0.0365, 0.01], [0.0335, 0.012]], {'seg': 26}), 'paint', ORANGE,
            {'pos': [0, sy, -0.03 - t]})
    add(THREE.CircleGeometry(0.0225, 20), 'paint', '#1E2436', {'pos': [0, sy, -0.042]})
    add(sphere(0.0032, 8, 6), 'glow', PAL.onAirRed, {'pos': [0, sy, -0.043], 'intensity': 4})
    add(THREE.CircleGeometry(0.0225, 20).rotateY(math.pi), 'paint', '#F2A640', {'pos': [0, sy, -0.128]})
    add(THREE.CircleGeometry(0.007, 12).rotateY(math.pi), 'paint', '#FFF1C4', {'pos': [0.008, sy + 0.008, -0.1285]})
    add(ycyl(0.011, 0.016, {'seg': 14}), 'paint', ORANGE, {'pos': [0, sy + 0.028, -0.085]})
    add(xcyl(0.011, 0.016, {'seg': 14}), 'paint', ORANGE, {'pos': [0.028, sy, -0.085]})
    # charging handle
    add(K.box(0.052, 0.013, 0.016, 0.005), 'paint', ORANGE, {'pos': [0, 0.134, 0.098]})
    return {
        'muzzle': [0, boreY, -0.3],
        'leftHand': [-0.004, -0.02, -0.172],
        'anim': {'mag': {'axis': 'y', 'drop': 0.25}},
        'up': {
            'medal': {'pos': [0.0296, 0.09, 0.045], 'r': 0.018},
            'ears': {'pos': [0, 0.133, 0.085], 's': 0.75},
            'fins': {'pos': [0, boreY, -0.262], 's': 0.45, 'n': 3, 'r0': 0.014, 'spread': math.pi / 3},
            'ring': {'pos': [0, boreY, -0.245], 'r': 0.0165, 'len': 0.02},
        },
    }


# ---------------------------------------------------------------------------------------------- M16A1 burst
def m16a1(W):
    add = W.add
    FURN, TEALG, FURN2 = '#39405C', '#62868A', '#4A5270'
    boreY = 0.13
    # pistol grip
    gripG = W.group([0, 0, 0], [-0.34, 0, 0])
    add(side([[0.026, 0.05], [0.026, 0.02], [0.033, 0.004], [0.022, -0.012], [0.024, -0.04], [0.017, -0.072],
              [-0.028, -0.078], [-0.035, -0.04], [-0.031, 0.02], [-0.027, 0.05]],
             0.043, {'bevel': 0.014, 'round': 0.01, 'steps': 3, 'bevelSeg': 3}), 'paint', FURN,
        {'parent': gripG, 'up': 'b'})
    # lower (with magazine well) + upper receivers, teal-grey
    add(side([[-0.07, 0.1], [-0.07, 0.062], [-0.05, 0.045], [0.03, 0.045], [0.09, 0.05], [0.1, 0.0], [0.205, 0.0],
              [0.212, 0.06], [0.2, 0.1]], 0.05, {'bevel': 0.012, 'round': 0.01}), 'steel', TEALG)
    add(side([[-0.085, 0.1], [0.24, 0.1], [0.246, 0.115], [0.24, 0.15], [-0.07, 0.152], [-0.09, 0.132]], 0.056,
             {'bevel': 0.013, 'round': 0.01}), 'steel', TEALG)
    add(K.box(0.004, 0.022, 0.07, 0.003), 'paint', INK, {'pos': [0.0285, 0.124, -0.075]})
    add(xcyl(0.0065, 0.006, {'seg': 12}), 'paint', FURN, {'pos': [0.025, 0.072, -0.095]})
    # carry handle with sight hole + rear sight, charging handle, teardrop forward assist
    add(sideHoles([[-0.05, 0.145], [0.19, 0.145], [0.19, 0.162], [0.175, 0.2], [-0.02, 0.203], [-0.05, 0.19]],
                  [[[0.0, 0.158], [0.155, 0.158], [0.15, 0.187], [0.01, 0.189]]], 0.03,
                  {'bevel': 0.008, 'round': 0.01}), 'steel', TEALG)
    add(side([[-0.048, 0.19], [-0.018, 0.2], [-0.02, 0.217], [-0.044, 0.217]], 0.026, {'bevel': 0.006, 'round': 0.006}),
        'steel', TEALG)
    add(xcyl(0.009, 0.036, {'seg': 14}), 'steel', TEALG, {'pos': [-0.018, 0.2, 0.034]})
    add(K.box(0.05, 0.012, 0.016, 0.0045), 'paint', FURN2, {'pos': [0, 0.142, 0.099]})
    add(zlathe([[0, 0], [0.012, 0.004], [0.012, 0.018], [0.008, 0.028], [0, 0.031]], {'round': 0.003, 'seg': 14}),
        'steel', TEALG, {'pos': [0.031, 0.128, 0.004], 'rot': [0, math.pi, 0]})
    # buttstock + plate + the "13" decal
    add(thick(side([[-0.07, 0.15], [-0.45, 0.148], [-0.46, 0.14], [-0.46, -0.03], [-0.45, -0.04], [-0.3, -0.005],
                    [-0.12, 0.048], [-0.07, 0.055]], 0.052,
                   {'bevel': 0.016, 'round': 0.012, 'steps': 3, 'bevelSeg': 3}), 0.07, 0.8, 0.46, 1.0),
        'paint', FURN, {'up': 'b'})
    add(side([[-0.458, 0.148], [-0.476, 0.148], [-0.478, -0.04], [-0.46, -0.042]], 0.05,
             {'bevel': 0.01, 'round': 0.008}), 'paint', FURN2)
    W.sticker('logo13', 0.074, 0.074, {'pos': [0.0245, 0.075, 0.29]})
    # triangular handguard with slip ring + cap
    hg = K.taper(section([[-0.036, -0.026], [0.036, -0.026], [0.03, 0.012], [0.0, 0.034], [-0.03, 0.012]], 0.295,
                         {'round': 0.014, 'bevel': 0.006}), {'axis': 'z', 'k': 1.12})
    add(hg, 'paint', FURN, {'pos': [0, boreY - 0.004, -0.3925], 'up': 'b'})
    for i in range(5):
        add(K.box(0.066, 0.004, 0.012, 0.0015), 'paint', INK, {'pos': [0, boreY - 0.03, -0.29 - i * 0.05]})
    for sx in [-1, 1]:
        for i in range(7):
            z = -0.275 - i * 0.04
            k = 1 + 0.12 * ((0.54 + z) / 0.295)
            add(THREE.CircleGeometry(0.0055, 10).rotateY(sx * math.pi / 2), 'paint', INK,
                {'pos': [sx * (0.0305 * k + 0.0008), boreY + 0.004, z]})
    add(zlathe([[0, 0], [0.043, 0], [0.046, 0.01], [0.043, 0.02], [0, 0.02]], {'round': 0.003, 'seg': 22}), 'steel',
        None, {'pos': [0, boreY - 0.004, -0.233]})
    add(zlathe([[0, 0], [0.034, 0], [0.035, 0.012], [0.018, 0.02], [0, 0.02]], {'round': 0.003, 'seg': 20}), 'steel',
        None, {'pos': [0, boreY - 0.002, -0.535]})
    # barrel, triangular front sight tower, sling swivel, birdcage
    add(zcyl(0.0135, 0.0125, 0.19, {'seg': 16}), 'steel', None, {'pos': [0, boreY, -0.545]})
    add(sideHoles([[0.6, 0.108], [0.668, 0.108], [0.668, 0.124], [0.648, 0.2], [0.642, 0.222], [0.632, 0.222],
                   [0.626, 0.2], [0.606, 0.15], [0.6, 0.14]],
                  [[[0.618, 0.152], [0.641, 0.152], [0.635, 0.19], [0.629, 0.19]]], 0.024,
                  {'bevel': 0.006, 'round': 0.006}), 'steel')
    add(side([[0.632, 0.11], [0.662, 0.11], [0.66, 0.094], [0.636, 0.094]], 0.012, {'bevel': 0.003, 'round': 0.004}),
        'steel')
    add(THREE.TorusGeometry(0.011, 0.0028, 6, 16).rotateY(math.pi / 2), 'chrome', None, {'pos': [0, 0.086, -0.618]})
    add(zlathe(ribProfile(0.07, 0.0175, 5, 0.004, 0.015, {'gw': 0.004}), {'seg': 18}), 'steel', None,
        {'pos': [0, boreY, -0.73]})
    add(THREE.CircleGeometry(0.009, 14).rotateY(math.pi), 'paint', INK, {'pos': [0, boreY, -0.8005]})
    # curved 30-round magazine (drops on reload)
    mag = W.part('mag')
    add(side([[0.112, 0.02], [0.198, 0.02], [0.205, -0.05], [0.222, -0.13], [0.222, -0.142], [0.165, -0.158],
              [0.155, -0.15], [0.14, -0.07], [0.115, 0.0]], 0.028, {'bevel': 0.007, 'round': 0.01}), 'steel', None,
        {'parent': mag})
    add(side([[0.224, -0.128], [0.228, -0.146], [0.164, -0.166], [0.155, -0.152]], 0.033,
             {'bevel': 0.008, 'round': 0.006}), 'steel', '#2E3A56', {'parent': mag})
    # trigger group
    add(K.tube([P(0.096, 0.047), P(0.098, 0.012), P(0.088, -0.006), P(0.05, -0.009), P(0.034, 0.002), P(0.03, 0.036)],
               0.0058, {'seg': 20, 'radial': 8}), 'steel', TEALG)
    add(side([[0.072, 0.047], [0.077, 0.028], [0.072, 0.01], [0.065, 0.005], [0.067, 0.024], [0.064, 0.045]], 0.01,
             {'bevel': 0.003, 'round': 0.004}), 'steel')
    return {
        'muzzle': [0, boreY, -0.8],
        'leftHand': [-0.012, 0.098, -0.38],
        'anim': {'mag': {'axis': 'y', 'drop': 0.25}},
        'up': {
            'medal': {'pos': [0.0255, 0.074, -0.03], 'r': 0.018},
            'ears': {'pos': [0, 0.203, -0.08], 's': 0.8},
            'fins': {'pos': [0, boreY, -0.68], 's': 0.55, 'n': 3, 'r0': 0.013, 'spread': math.pi / 3},
            'ring': {'pos': [0, boreY, -0.7], 'r': 0.0165, 'len': 0.024},
        },
    }


# ---------------------------------------------------------------------------------------------- M60 "Truckers!"
def m60(W):
    add = W.add
    OLIVE, BOX = '#5E6838', '#6E7A42'
    boreY = 0.12
    # pistol grip + trigger housing + winter trigger guard
    gripG = W.group([0, 0, 0], [-0.2, 0, 0])
    add(side([[0.028, 0.05], [0.026, 0.02], [0.033, 0.0], [0.024, -0.018], [0.032, -0.036], [0.022, -0.052],
              [0.026, -0.07], [0.018, -0.08], [-0.03, -0.082], [-0.035, -0.05], [-0.032, 0.0], [-0.028, 0.05]],
             0.052, {'bevel': 0.016, 'round': 0.01, 'steps': 3, 'bevelSeg': 3}), 'paint', OLIVE,
        {'parent': gripG, 'up': 'b'})
    add(side([[-0.035, 0.056], [0.09, 0.056], [0.084, 0.032], [-0.024, 0.03]], 0.05, {'bevel': 0.012, 'round': 0.008}),
        'steel')
    add(K.tube([P(0.082, 0.036), P(0.087, 0.0), P(0.072, -0.023), P(0.042, -0.027), P(0.031, 0.0), P(0.029, 0.032)],
               0.0075, {'seg': 20, 'radial': 8}), 'steel')
    add(side([[0.058, 0.04], [0.064, 0.022], [0.06, 0.005], [0.052, 0.0], [0.054, 0.018], [0.05, 0.038]], 0.011,
             {'bevel': 0.0035, 'round': 0.004}), 'brass', None)
    # massive box receiver + feed tray window
    add(side([[-0.1, 0.05], [0.3, 0.05], [0.312, 0.07], [0.312, 0.152], [0.3, 0.16], [-0.09, 0.16], [-0.106, 0.14]],
             0.072, {'bevel': 0.016, 'round': 0.012, 'steps': 3}), 'steel')
    add(K.box(0.004, 0.026, 0.055, 0.003), 'paint', INK, {'pos': [0.0365, 0.132, -0.2]})
    for f in [-0.06, 0.28]:
        for s in [-1, 1]:
            add(xcyl(0.006, 0.003, {'rt': 0.005, 'seg': 10}), 'chrome', None,
                {'pos': [s * 0.0355, 0.075, -f], 'rot': [0, math.pi, 0] if s < 0 else None})
    # hinged feed cover (+ rear sight leaf)
    cover = W.part('cover', [0, 0.158, -0.02])
    add(side([[0.0, 0.0], [0.25, 0.0], [0.25, 0.02], [0.236, 0.032], [0.02, 0.034], [0.0, 0.022]], 0.075,
             {'bevel': 0.01, 'round': 0.008}), 'steel', '#4A5C82', {'parent': cover})
    add(side([[0.012, 0.03], [0.042, 0.03], [0.036, 0.058], [0.018, 0.058]], 0.022, {'bevel': 0.005, 'round': 0.005}),
        'steel', None, {'parent': cover})
    add(K.box(0.03, 0.01, 0.018, 0.004), 'chrome', None, {'parent': cover, 'pos': [0, 0.02, -0.248]})
    # buttstock, plate, shoulder rest
    add(thick(side([[-0.1, 0.155], [-0.44, 0.15], [-0.45, 0.14], [-0.45, 0.0], [-0.44, -0.01], [-0.3, 0.02],
                    [-0.12, 0.05], [-0.1, 0.056]], 0.062,
                   {'bevel': 0.019, 'round': 0.014, 'steps': 3, 'bevelSeg': 3}), 0.1, 0.8, 0.45, 1.0),
        'paint', OLIVE, {'up': 'b'})
    add(side([[-0.448, 0.15], [-0.47, 0.15], [-0.472, -0.01], [-0.45, -0.012]], 0.06, {'bevel': 0.012, 'round': 0.008}),
        'steel')
    add(side([[-0.37, 0.149], [-0.472, 0.151], [-0.472, 0.163], [-0.38, 0.161]], 0.052,
             {'bevel': 0.005, 'round': 0.005}), 'steel')
    # barrel, gas cylinder, ribbed forearm, carry handle, front sight, flared suppressor
    add(zcyl(0.018, 0.017, 0.5, {'seg': 18}), 'steel', None, {'pos': [0, boreY, -0.3]})
    add(zcyl(0.0155, 0.0155, 0.32, {'seg': 14}), 'steel', None, {'pos': [0, 0.084, -0.3]})
    add(section([[-0.037, -0.03], [0.037, -0.03], [0.037, 0.022], [0.0, 0.037], [-0.037, 0.022]], 0.22,
                {'round': 0.014, 'bevel': 0.007}), 'paint', OLIVE, {'pos': [0, 0.094, -0.42], 'up': 'b'})
    for i in range(5):
        add(K.box(0.077, 0.03, 0.007, 0.002), 'paint', INK, {'pos': [0, 0.09, -0.34 - i * 0.04]})
    add(K.tube([P(0.5, 0.13, 0.0), P(0.51, 0.18, 0.008), P(0.56, 0.206, 0.012), P(0.61, 0.18, 0.008),
                P(0.62, 0.13, 0.0)], 0.0075, {'seg': 24, 'radial': 8}), 'chrome')
    add(K.tube([P(0.535, 0.198, 0.011), P(0.585, 0.198, 0.011)], 0.0125, {'seg': 2, 'radial': 10}), 'paint', OLIVE,
        {'up': 'b'})
    add(side([[0.765, 0.13], [0.79, 0.13], [0.786, 0.162], [0.772, 0.162]], 0.012, {'bevel': 0.003, 'round': 0.004}),
        'steel')
    add(zlathe([[0, 0], [0.0195, 0], [0.021, 0.02], [0.025, 0.06], [0.023, 0.078], [0.016, 0.078], [0.0145, 0.07],
                [0, 0.07]], {'round': 0.003, 'seg': 22}), 'steel', None, {'pos': [0, boreY, -0.8]})
    add(THREE.CircleGeometry(0.0145, 16).rotateY(math.pi), 'paint', INK, {'pos': [0, boreY, -0.8705]})
    # folded bipod
    bip = W.part('bipod', [0, 0.074, -0.62])
    add(K.box(0.062, 0.02, 0.024, 0.006), 'steel', None, {'parent': bip})
    for s in [-1, 1]:
        add(K.tube([[s * 0.022, 0, 0], [s * 0.028, -0.003, -0.19]], 0.0068, {'seg': 2, 'radial': 8}), 'steel', None,
            {'parent': bip})
        add(zlathe([[0, 0], [0.011, 0.0], [0.012, 0.012], [0.008, 0.02], [0, 0.02]], {'round': 0.003, 'seg': 12}),
            'paint', INK, {'parent': bip, 'pos': [s * 0.028, -0.003, -0.19]})
    # olive ammo box under the receiver + instanced brass belt into the feed tray
    add(K.box(0.086, 0.13, 0.17, 0.014), 'paint', BOX, {'pos': [0, -0.03, -0.17], 'up': 'b'})
    add(K.box(0.092, 0.02, 0.176, 0.007), 'paint', OLIVE, {'pos': [0, 0.036, -0.17], 'up': 'b'})
    add(K.box(0.088, 0.012, 0.172, 0.004), 'paint', '#F4C81E', {'pos': [0, -0.07, -0.17]})
    add(K.box(0.03, 0.034, 0.012, 0.004), 'steel', None, {'pos': [0, 0.012, -0.257]})
    W.sticker('tenfour', 0.085, 0.085, {'pos': [0.0436, -0.028, -0.17]})
    cart = mergeGeo([
        K.tint(K.lathe([[0, 0], [0.0078, 0], [0.0078, 0.034], [0.0056, 0.04], [0.0056, 0.046]],
                       {'seg': 10, 'round': 0.0015, 'steps': 1}).clone(), BRASS),
        K.tint(K.lathe([[0, 0.046], [0.0056, 0.046], [0.0056, 0.052], [0.0035, 0.062], [0, 0.066]],
                       {'seg': 10, 'round': 0.002, 'steps': 1}).clone(), '#D0784A'),
        K.tint(THREE.TorusGeometry(0.0086, 0.0022, 5, 12).rotateX(math.pi / 2).translate(0, 0.018, 0), STEEL),
    ])
    cart.rotateX(-math.pi / 2)
    cart.translate(0, 0, 0.033)
    curve = THREE.CatmullRomCurve3([V3(x, y, -0.2) for x, y in
                                    [[0.028, 0.035], [0.056, 0.052], [0.07, 0.083], [0.064, 0.114], [0.042, 0.136]]])
    N = 8
    belt = THREE.InstancedMesh(cart, W.mats.chrome, N)
    m4, q, e = THREE.Matrix4(), THREE.Quaternion(), THREE.Euler()
    for i in range(N):
        t = (i + 0.5) / N
        p, tg = curve.getPointAt(t), curve.getTangentAt(t)
        e.set(0, 0, math.atan2(tg.y, tg.x))
        m4.compose(p, q.setFromEuler(e), V3(1, 1, 1))
        belt.setMatrixAt(i, m4)
    belt.name = 'belt'
    beltG = W.part('belt')
    beltG.add(belt)
    return {
        'muzzle': [0, boreY, -0.878],
        'leftHand': [-0.01, 0.062, -0.41],
        'anim': {'cover': {'axis': 'x', 'open': -1.1}, 'bipod': {'axis': 'x', 'deploy': 1.4}},
        'up': {
            'medal': {'pos': [0.0366, 0.1, -0.03], 'r': 0.021},
            'ears': {'pos': [0, 0.194, -0.14], 's': 0.9},
            'fins': {'pos': [0, boreY, -0.72], 's': 0.7, 'n': 3, 'r0': 0.018, 'spread': math.pi / 3},
            'ring': {'pos': [0, boreY, -0.74], 'r': 0.021, 'len': 0.03},
            'trim': [[0.037, 0.145, 0.07], [0.037, 0.145, -0.29]],
        },
    }


# ---------------------------------------------------------------------------------------------- The Zapper
def zapper(W):
    add = W.add
    W.wood(PAL.walnut, {'dark': 0.5})
    BEIGE = '#EBDCBC'
    L, zc = 0.36, -0.07  # body z: +0.11 (rear) .. -0.25 (front)
    body = K.taper(section([[-0.046, -0.012], [0.046, -0.012], [0.047, 0.016], [0.037, 0.03], [-0.037, 0.03],
                            [-0.047, 0.016]], L, {'round': 0.016, 'bevel': 0.012, 'steps': 3, 'bevelSeg': 3}),
                   {'axis': 'z', 'k': 1.1})
    add(body, 'paint', BEIGE, {'pos': [0, 0, zc], 'up': 'a'})
    bottom = K.taper(section([[-0.043, -0.008], [0.043, -0.008], [0.042, -0.024], [0.033, -0.031], [-0.033, -0.031],
                              [-0.042, -0.024]], L - 0.012, {'round': 0.01, 'bevel': 0.008, 'uv': 6}),
                     {'axis': 'z', 'k': 1.1})
    add(bottom, 'wood', None, {'pos': [0, 0, zc]})
    for s in [-1, 1]:
        add(K.tube([[s * 0.0495, -0.0105, 0.1], [s * 0.046, -0.0105, -0.24]], 0.0042, {'seg': 2, 'radial': 8}),
            'chrome')
    # chrome piano keys in a dark well
    add(K.box(0.082, 0.008, 0.064, 0.004), 'paint', INK, {'pos': [0, 0.0305, 0.045]})
    add(K.box(0.088, 0.006, 0.07, 0.003), 'chrome', None, {'pos': [0, 0.029, 0.045]})
    keys = W.part('keys', [0, 0.036, 0.045])
    for i in range(4):
        add(side([[-0.026, -0.004], [0.026, -0.004], [0.028, 0.002], [0.022, 0.007], [-0.026, 0.007]], 0.0165,
                 {'bevel': 0.003, 'round': 0.003}), 'chrome', None,
            {'parent': keys, 'pos': [-0.0285 + i * 0.019, -0.003 if i == 1 else 0, 0]})
    # big red dome button
    add(K.lathe([[0, 0], [0.027, 0], [0.029, 0.004], [0.025, 0.009], [0, 0.009]], {'round': 0.002, 'seg': 24}),
        'chrome', None, {'pos': [0, 0.028, -0.045]})
    dome = []
    for i in range(7):
        a = (i / 6) * math.pi / 2
        dome.append([math.cos(a) * 0.021, math.sin(a) * 0.017])
    add(K.lathe([[0, 0]] + dome, {'seg': 24}), 'paint', '#E8302E', {'pos': [0, 0.036, -0.045]})
    add(sphere(0.006, 10, 6), 'paint', '#FFB0A0', {'pos': [-0.007, 0.05, -0.052], 'scale': [1, 0.5, 1]})
    # Space Patrol sticker, ultrasonic emitter, stubby ball antenna, channel LED
    W.sticker('space', 0.056, 0.056, {'face': '+y', 'pos': [0, 0.0318, -0.145]})
    add(K.box(0.074, 0.03, 0.012, 0.006), 'chrome', None, {'pos': [0, 0.009, -0.249]})
    for i in range(4):
        add(K.box(0.058, 0.0028, 0.004, 0.001), 'paint', INK, {'pos': [0, -0.001 + i * 0.0068, -0.2552]})
    add(K.lathe([[0, 0], [0.012, 0], [0.013, 0.006], [0.008, 0.012], [0, 0.012]], {'round': 0.002, 'seg': 16}),
        'chrome', None, {'pos': [0, 0.029, -0.215]})
    dr = V3(0, math.sin(0.42), -math.cos(0.42))
    rod = K.cyl(0.0045, 0.006, 0.07, {'bevel': 0.0015, 'seg': 10}).clone()
    rod.applyQuaternion(THREE.Quaternion().setFromUnitVectors(V3(0, 1, 0), dr))
    add(rod, 'chrome', None, {'pos': [0, 0.036, -0.215]})
    tip = V3(0, 0.036, -0.215).addScaledVector(dr, 0.078)
    add(sphere(0.0125, 16, 12), 'chrome', None, {'pos': tip.toArray()})
    add(sphere(0.0045, 10, 8), 'glow', PAL.onAirRed, {'pos': [0.028, 0.031, -0.19], 'intensity': 3})
    # battery (pops out of the rear on reload): brass end cap + a yellow cell inside
    bat = W.part('battery', [0, 0.004, 0.1])
    add(zcyl(0.012, 0.012, 0.075, {'seg': 14}), 'paint', '#F4C81E', {'parent': bat, 'pos': [0, 0, 0.005]})
    add(zcyl(0.0122, 0.0122, 0.02, {'seg': 14}), 'paint', STEEL, {'parent': bat, 'pos': [0, 0, -0.03]})
    add(zlathe([[0, 0], [0.015, 0], [0.016, 0.004], [0.013, 0.008], [0, 0.008]], {'round': 0.002, 'seg': 16}), 'brass',
        None, {'parent': bat, 'pos': [0, 0, 0.018], 'rot': [0, math.pi, 0]})
    return {
        'muzzle': tip.clone().addScaledVector(dr, 0.012).toArray(),
        'leftHand': [-0.03, -0.035, -0.1],
        'anim': {'keys': {'press': -0.003}, 'battery': {'axis': 'z', 'pop': 0.09}},
        'up': {
            'medal': {'pos': [0.0485, 0.008, -0.1], 'r': 0.016},
            'ears': {'pos': [0, 0.033, 0.085], 's': 0.6},
            'fins': {'pos': [0, 0.004, 0.105], 's': 0.55, 'n': 2},
        },
    }


# ---------------------------------------------------------------------------------------------- The Boom Mic
def boomMic(W):
    add, game = W.add, W.game
    PLUM, ORANGE, TAN, CREAM = '#6B3A6E', PAL.burntOrange, '#A8713E', '#EFE4CC'
    # telescoping pole (3 sections), rear cap, ribbed foam grip, twist-lock collars
    add(zcyl(0.021, 0.021, 0.33, {'seg': 16}), 'chrome', None, {'pos': [0, 0, 0.13], 'up': 'a'})
    add(zcyl(0.0165, 0.0165, 0.37, {'seg': 14}), 'chrome', None, {'pos': [0, 0, -0.19], 'up': 'a'})
    add(zcyl(0.013, 0.013, 0.28, {'seg': 12}), 'chrome', None, {'pos': [0, 0, -0.55], 'up': 'a'})
    add(zlathe([[0, 0], [0.026, 0], [0.028, 0.012], [0.024, 0.024], [0, 0.024]], {'round': 0.004, 'seg': 18}), 'paint',
        INK, {'pos': [0, 0, 0.154]})
    add(zlathe(ribProfile(0.17, 0.031, 7, 0.004, 0.026, {'gw': 0.004}), {'seg': 18}), 'paint', PLUM,
        {'pos': [0, 0, 0.13], 'up': 'b'})
    add(zlathe(ribProfile(0.038, 0.0272, 3, 0.0025, 0.022), {'seg': 18}), 'paint', ORANGE,
        {'pos': [0, 0, -0.176], 'up': 'b'})
    add(zlathe(ribProfile(0.034, 0.0225, 3, 0.0022, 0.017), {'seg': 16}), 'paint', ORANGE,
        {'pos': [0, 0, -0.538], 'up': 'b'})
    # mini reel-to-reel strapped on top, tilted toward the camera side
    rec = W.group([0, 0.004, -0.2], [0, 0, -0.42], W.root)
    rec.scale.setScalar(1.18)
    add(K.box(0.092, 0.062, 0.17, 0.016), 'paint', CREAM, {'parent': rec, 'pos': [0, 0.049, 0], 'up': 'a'})
    add(K.box(0.084, 0.006, 0.162, 0.006), 'chrome', None, {'parent': rec, 'pos': [0, 0.081, 0]})
    for nm, z in [['reelL', 0.042], ['reelR', -0.042]]:
        reel = W.part(nm, [0, 0.084, z], rec)
        add(ycyl(0.028, 0.009, {'seg': 22}), 'paint', '#4A2E22', {'parent': reel})
        fl = THREE.Shape()
        fl.absarc(0, 0, 0.036, 0, TAU, False)
        for i in range(3):
            a = (i / 3) * TAU
            h = THREE.Path()
            h.absarc(math.cos(a) * 0.021, math.sin(a) * 0.021, 0.0085, 0, TAU, True)
            fl.holes.append(h)
        add(K.extrude(fl, 0.004, {'bevel': 0.0012, 'curveSeg': 5, 'bevelSeg': 1}).rotateX(-math.pi / 2), 'paint',
            ORANGE, {'parent': reel, 'pos': [0, 0.011, 0]})
        add(ycyl(0.0085, 0.016, {'seg': 12}), 'chrome', None, {'parent': reel})
    # VU meter (backlit face + needle) on the camera-side face
    add(K.box(0.006, 0.04, 0.066, 0.005), 'chrome', None, {'parent': rec, 'pos': [0.046, 0.046, -0.02]})
    vu = THREE.PlaneGeometry(0.056, 0.031)
    K.uvRect(vu, *cellUV('vu'))
    vu.rotateY(math.pi / 2)
    add(vu, K.glow(game, '#FFF2D0', 1.05, {'map': stickers()}), None, {'parent': rec, 'pos': [0.0495, 0.046, -0.02]})
    needle = W.part('needle', [0.0502, 0.0325, -0.02], rec)
    add(K.box(0.0012, 0.026, 0.002, 0.0005), 'paint', '#D22A2A', {'parent': needle, 'pos': [0, 0.013, 0]})
    needle.rotation.x = 0.35
    # transport keys + REC on the front face, Groove Hour sticker facing the shooter
    for i in range(4):
        add(K.box(0.012, 0.013, 0.012, 0.003), 'paint' if i == 3 else 'chrome', PAL.channelRed if i == 3 else None,
            {'parent': rec, 'pos': [-0.027 + i * 0.018, 0.058, -0.087]})
    add(xcyl(0.009, 0.01, {'seg': 14}), 'paint', CREAM, {'parent': rec, 'pos': [0.046, 0.022, 0.045]})
    W.sticker('groove', 0.082, 0.041, {'face': '+z', 'parent': rec, 'pos': [0, 0.047, 0.0855]})
    # leather straps around pole + recorder
    for z in [-0.055, 0.055]:
        path = []
        for i in range(16):
            a = (i / 16) * TAU
            path.append([math.cos(a) * 0.052, 0.036 + math.sin(a) * 0.056, z])
        add(K.tube(path, 0.0042, {'seg': 32, 'radial': 5, 'closed': True}), 'paint', TAN,
            {'parent': rec, 'scale': [1, 1, 1]})
    # coiled cable spiralling down the pole to the mic
    coil = []
    for i in range(101):
        t = i / 100
        a = t * 10 * TAU
        coil.append([math.cos(a) * 0.025, math.sin(a) * 0.025, -0.3 - t * 0.5])
    add(K.tube(coil, 0.0036, {'seg': 150, 'radial': 4}), 'paint', PLUM, {'up': 'b'})
    # shock mount + shaggy dead-cat windscreen
    add(K.box(0.024, 0.02, 0.034, 0.006), 'chrome', None, {'pos': [0, 0, -0.842]})
    add(THREE.TorusGeometry(0.042, 0.005, 6, 20), 'chrome', None, {'pos': [0, 0, -0.868]})
    mic = W.part('mic', [0, 0, -0.99])
    add(deadCat(0.074, 0.27), K.mat(game, 'fabric', '#ffffff', {**KEEP, 'map': furTex(), 'rim': 0.6}), None,
        {'parent': mic})
    return {
        'muzzle': [0, 0, -1.13],
        'leftHand': [0, -0.022, -0.45],
        'anim': {'reels': {'axis': 'y', 'spin': 9}, 'needle': {'axis': 'x', 'min': 0.7, 'max': -0.7}, 'mic': 'wobble'},
        'up': {
            'medal': {'pos': [0.0172, 0, -0.1], 'r': 0.013},
            'ears': {'pos': [0, 0.016, 0.1], 's': 0.6},
            'fins': {'pos': [0, 0, 0.17], 's': 0.75, 'n': 3},
            'ring': {'pos': [0, 0, -0.8], 'r': 0.013, 'len': 0.02},
        },
    }


# Displaced capsule with a noisy, spiky silhouette (fur windscreen), along -z centered on 0.
def deadCat(R, len_):
    rows = []
    half = len_ / 2 - R
    for i in range(10):
        a = -math.pi / 2 + (i / 9) * math.pi / 2
        rows.append([math.cos(a) * R, -half + math.sin(a) * R])
    for i in range(1, 8):
        rows.append([R, -half + (i / 8) * half * 2])
    for i in range(10):
        a = (i / 9) * math.pi / 2
        rows.append([math.cos(a) * R, half + math.sin(a) * R])
    g = THREE.LatheGeometry([THREE.Vector2(max(0, r), y) for r, y in rows], 36)
    p = g.attributes.position

    def hh(x, y, z):
        s = math.sin(x * 127.1 + y * 311.7 + z * 74.7) * 43758.5453
        return s - math.floor(s)
    d = V3()
    for i in range(p.count):
        x, y, z = p.getX(i), p.getY(i), p.getZ(i)
        r = math.hypot(x, z)
        kx, ky, kz = js_round(x * 1e4) / 1e4, js_round(y * 1e4) / 1e4, js_round(z * 1e4) / 1e4
        lo = 0.06 * math.sin(kx * 60 + ky * 40) * math.cos(kz * 55 - ky * 30)
        spike = 0.2 * math.pow(hh(kx, ky, kz), 2.2)
        k = 1 + lo + spike
        if r < 1e-5:
            p.setY(i, y * (1 + spike * 0.4))
            continue
        d.set(x, (y - half) if y > half else (y + half) if y < -half else 0, z).normalize()
        p.setXYZ(i, x + d.x * R * (k - 1), y + d.y * R * (k - 1), z + d.z * R * (k - 1))
    g.computeVertexNormals()
    K.weldNormals(g)
    K.uvScale(g, 4, 3)
    g.rotateX(-math.pi / 2)
    return g


def furTex():
    def draw(ctx, w, h, rnd):
        ctx.fillStyle = '#9C7A3A'
        ctx.fillRect(0, 0, w, h)
        ctx.lineCap = 'round'
        for i in range(5200):
            x, y, a, l = rnd() * w, rnd() * h, -math.pi / 2 + (rnd() - 0.5) * 1.6, 5 + rnd() * 10
            c = rnd()
            ctx.strokeStyle = '#FFF1C8' if c < 0.1 else '#E0B25A' if c < 0.55 else '#C8963C' if c < 0.85 else '#8A6428'
            ctx.globalAlpha = 0.6 + rnd() * 0.4
            ctx.lineWidth = 1.2 + rnd() * 1.8
            ctx.beginPath()
            ctx.moveTo(x, y)
            ctx.quadraticCurveTo(x + math.cos(a + 0.5) * l * 0.5, y + math.sin(a + 0.5) * l * 0.5,
                                 x + math.cos(a) * l, y + math.sin(a) * l)
            ctx.stroke()
        ctx.globalAlpha = 1
    return K.tex.canvas('wpn_fur_v1', 256, 256, draw)


# ---------------------------------------------------------------------------------------------- Chroma-Key Cannon
def chromaKey(W):
    add, game = W.add, W.game
    CREAM, SLATE, ORANGE = '#EAE0CA', '#39405C', PAL.burntOrange
    goo = PAL.greenScreen if W.up else PAL.chromaBlue
    # pistol grip + trigger
    gripG = W.group([0, 0, 0], [-0.25, 0, 0])
    add(side([[0.028, 0.055], [0.026, 0.02], [0.033, 0.0], [0.024, -0.018], [0.032, -0.036], [0.022, -0.052],
              [0.026, -0.07], [0.018, -0.08], [-0.03, -0.082], [-0.035, -0.05], [-0.032, 0.0], [-0.028, 0.055]],
             0.05, {'bevel': 0.016, 'round': 0.01, 'steps': 3, 'bevelSeg': 3}), 'paint', SLATE,
        {'parent': gripG, 'up': 'b'})
    add(K.tube([P(0.1, 0.062), P(0.104, 0.028), P(0.088, 0.006), P(0.058, 0.002), P(0.04, 0.012), P(0.036, 0.045)],
               0.0078, {'seg': 20, 'radial': 8}), 'paint', SLATE, {'up': 'b'})
    add(side([[0.07, 0.06], [0.076, 0.042], [0.072, 0.024], [0.064, 0.018], [0.066, 0.036], [0.062, 0.058]], 0.012,
             {'bevel': 0.004, 'round': 0.004}), 'paint', PAL.channelRed)
    # boxy camera body: cream shell, slate belly band, orange pinstripe
    add(side([[-0.1, 0.06], [0.16, 0.06], [0.172, 0.08], [0.172, 0.212], [0.158, 0.226], [-0.086, 0.226],
              [-0.1, 0.212]], 0.14, {'bevel': 0.03, 'round': 0.02, 'steps': 3, 'bevelSeg': 3}), 'paint', CREAM,
        {'up': 'a'})
    add(side([[-0.098, 0.064], [0.168, 0.064], [0.17, 0.102], [-0.098, 0.102]], 0.144,
             {'bevel': 0.016, 'round': 0.012}), 'paint', SLATE, {'up': 'b'})
    add(side([[-0.096, 0.104], [0.168, 0.104], [0.168, 0.11], [-0.096, 0.11]], 0.1445,
             {'bevel': 0.003, 'round': 0.002}), 'paint', ORANGE)
    # flared chrome muzzle with the goo core
    gooMat = K.mat(game, 'ceramic', goo, {**KEEP, 'emissive': goo, 'emissiveIntensity': 0.55, 'rim': 0.5,
                                          'rimColor': '#BFE0FF', 'env': 0.12})
    add(zlathe([[0.0, 0.0], [0.056, 0.0], [0.058, 0.036], [0.05, 0.042]], {'round': 0.004, 'steps': 1, 'seg': 20}),
        'paint', SLATE, {'pos': [0, 0.145, -0.168], 'up': 'b'})
    add(zlathe([[0.0, 0.0], [0.048, 0.0], [0.046, 0.02], [0.05, 0.05], [0.064, 0.085], [0.086, 0.112], [0.093, 0.122],
                [0.088, 0.13], [0.07, 0.124], [0.04, 0.106], [0.0, 0.1]], {'round': 0.004, 'steps': 1, 'seg': 24}),
        'chrome', None, {'pos': [0, 0.145, -0.2]})
    add(THREE.CircleGeometry(0.04, 24).rotateY(math.pi), gooMat, None, {'pos': [0, 0.145, -0.302]})
    add(THREE.TorusGeometry(0.052, 0.005, 6, 24), 'paint', goo, {'pos': [0, 0.145, -0.312]})
    # bulbous glass goo dome on a chrome collar (goo wobbles)
    add(K.lathe([[0, 0], [0.058, 0], [0.062, 0.012], [0.054, 0.024], [0, 0.024]], {'round': 0.004, 'steps': 1, 'seg': 20}),
        'chrome', None, {'pos': [0, 0.222, -0.066]})
    gooG = W.part('goo', [0, 0.298, -0.066])
    add(sphere(0.058, 20, 14), gooMat, None, {'parent': gooG, 'scale': [1, 0.94, 1]})
    for x, y, z, r in [[0.024, 0.018, -0.046, 0.009], [-0.026, -0.01, -0.047, 0.007], [0.01, -0.03, -0.05, 0.006],
                       [-0.012, 0.032, -0.044, 0.005]]:
        add(sphere(r, 10, 8), 'paint', '#9CC8FF', {'parent': gooG, 'pos': [x, y, z]})
    add(sphere(0.068, 22, 16), 'glass', '#E4F2FF', {'pos': [0, 0.3, -0.066], 'opacity': 0.1})
    add(sphere(0.012, 10, 8), 'paint', '#FFFFFF', {'pos': [-0.028, 0.34, -0.1], 'scale': [1, 0.6, 1]})
    # viewfinder CRT at the rear (faces the shooter)
    add(K.box(0.03, 0.02, 0.05, 0.006), 'paint', SLATE, {'pos': [0, 0.232, 0.052]})
    add(K.box(0.104, 0.076, 0.086, 0.02), 'paint', CREAM, {'pos': [0, 0.278, 0.056], 'up': 'a'})
    add(K.box(0.108, 0.012, 0.03, 0.005), 'paint', CREAM, {'pos': [0, 0.318, 0.1], 'up': 'a'})
    bez = K.roundRect(0.086, 0.062, 0.014)
    bez.holes.append(THREE.Path(K.roundRect(0.07, 0.048, 0.01).getPoints(6)))
    add(K.extrude(bez, 0.01, {'bevel': 0.003, 'bevelSeg': 1, 'curveSeg': 5}), 'paint', INK, {'pos': [0, 0.278, 0.099]})
    scr = K.screen(game, 0.07, 0.048, {'card': 'world_beach', 'group': 'scr_weapon', 'dome': 0.004, 'bright': 0.8})
    scr.rotation.y = math.pi
    scr.position.set(0, 0.278, 0.1)
    W.root.add(scr)
    # side knobs (camera side), tally light, nameplate + sticker
    for f, u, r in [[0.02, 0.17, 0.021], [0.085, 0.165, 0.016]]:
        add(xcyl(r, 0.016, {'seg': 18}), 'paint', CREAM, {'pos': [0.07, u, -f]})
        add(xcyl(r * 0.62, 0.008, {'seg': 14}), 'paint', ORANGE, {'pos': [0.085, u, -f]})
    add(K.lathe([[0, 0], [0.012, 0], [0.013, 0.005], [0, 0.005]], {'seg': 14}), 'chrome', None,
        {'pos': [0.042, 0.224, -0.14]})
    add(sphere(0.009, 12, 8), 'glow', PAL.onAirRed, {'pos': [0.042, 0.23, -0.14], 'intensity': 3, 'scale': [1, 0.7, 1]})
    W.sticker('chromaPlate', 0.1, 0.033, {'face': '-z', 'pos': [0, 0.198, -0.1725]})
    W.sticker('weather', 0.062, 0.062, {'pos': [0.0705, 0.162, 0.058]})
    # left side handle
    add(K.tube([[-0.07, 0.15, -0.035], [-0.1, 0.15, -0.04], [-0.114, 0.15, -0.07], [-0.114, 0.15, -0.13],
                [-0.1, 0.15, -0.16], [-0.07, 0.15, -0.165]], 0.0065, {'seg': 24, 'radial': 8}), 'chrome')
    add(zcyl(0.0135, 0.0135, 0.06, {'seg': 14}), 'paint', ORANGE, {'pos': [-0.114, 0.15, -0.07]})
    return {
        'muzzle': [0, 0.145, -0.33],
        'leftHand': [-0.114, 0.15, -0.1],
        'anim': {'goo': 'wobble'},
        'up': {
            'medal': {'pos': [0.0715, 0.09, 0.03], 'r': 0.018},
            'ears': {'pos': [0, 0.316, 0.06], 's': 0.8},
            'fins': {'pos': [0, 0.145, -0.18], 's': 0.8, 'n': 3, 'r0': 0.05, 'spread': math.pi / 3},
            'ring': {'pos': [0, 0.145, -0.19], 'r': 0.056, 'len': 0.02},
        },
    }


# ---------------------------------------------------------------------------------------------- Tube grenade
def tubeGrenade(W):
    add = W.add
    # bakelite base, brass band, chrome pins, key post
    add(K.lathe([[0, -0.078], [0.029, -0.078], [0.034, -0.072], [0.034, -0.046], [0.03, -0.04], [0.027, -0.036],
                 [0, -0.036]], {'round': 0.004, 'steps': 1, 'seg': 18}), 'paint', '#4A2E22', {'up': 'a'})
    add(K.lathe([[0.0342, -0.064], [0.0355, -0.062], [0.0355, -0.056], [0.0342, -0.054]], {'seg': 18}), 'brass')
    for i in range(8):
        a = (i / 8) * TAU
        add(THREE.CylinderGeometry(0.0026, 0.0026, 0.014, 5), 'chrome', None,
            {'pos': [math.cos(a) * 0.019, -0.084, math.sin(a) * 0.019]})
    add(THREE.CylinderGeometry(0.007, 0.007, 0.012, 10), 'paint', INK, {'pos': [0, -0.083, 0]})
    # insides: mica spacers, split anode plates, glowing filament (flickers), support rods, silvered getter
    for y in [-0.014, 0.074]:
        add(THREE.CylinderGeometry(0.029, 0.029, 0.0025, 14), 'paint', '#F2E4C4', {'pos': [0, y + 0.00125, 0]})
    for s in [-1, 1]:
        add(K.box(0.014, 0.078, 0.022, 0.004), 'paint', '#5E6678', {'pos': [s * 0.013, 0.03, 0]})
    for s in [-1, 1]:
        add(ycyl(0.0016, 0.09, {'seg': 4, 'bevel': 0.0005}), 'chrome', None, {'pos': [s * 0.024, -0.014, 0.006]})
    fil = W.part('filament')
    zig = []
    for i in range(9):
        zig.append([(0.004 if i % 2 else -0.004), -0.008 + i * 0.009, 0])
    add(K.tube(zig, 0.0024, {'seg': 24, 'radial': 5}), 'glow', '#FF7A22', {'parent': fil, 'intensity': 2.4})
    add(ycyl(0.0042, 0.074, {'seg': 8}), 'glow', '#FF7A22', {'parent': fil, 'pos': [0, -0.008, 0], 'intensity': 2.4})
    for s in [-1, 1]:
        add(K.tube([[x * 0.7, y, s * 0.0125] for x, y, _z in zig], 0.0016, {'seg': 16, 'radial': 4}), 'glow',
            '#FF7A22', {'parent': fil, 'intensity': 2.4})
    add(K.lathe([[0, 0.086], [0.026, 0.086], [0.029, 0.092], [0.022, 0.101], [0.01, 0.107], [0, 0.108]],
                {'round': 0.003, 'steps': 1, 'seg': 16}), 'chrome')
    # coke-bottle glass envelope + exhaust tip + printed label
    add(K.lathe([[0.0, -0.038], [0.028, -0.038], [0.031, -0.02], [0.035, 0.01], [0.038, 0.04], [0.037, 0.07],
                 [0.031, 0.095], [0.021, 0.107], [0.009, 0.112], [0.0045, 0.118], [0, 0.121]],
                {'round': 0.004, 'steps': 1, 'seg': 18}), 'glass', '#FFE8C8', {'opacity': 0.16})
    W.sticker('tubeLabel', 0.046, 0.023, {'face': '-z', 'pos': [0, 0.052, -0.0385]})
    return {
        'muzzle': [0, 0.121, 0],
        'leftHand': [0, 0, 0],
        'anim': {'filament': 'flicker'},
        'up': {'medal': {'pos': [0.0345, -0.058, 0], 'r': 0.012}},
    }


# ---------------------------------------------------------------------------------------------- Tiny Tele
def tinyTele(W):
    add, game, opts = W.add, W.game, W.opts
    ORANGE = PAL.burntOrange
    Wd, Hd, Dd, cy = 0.3, 0.23, 0.22, -0.185
    add(K.box(Wd, Hd, Dd, 0.07), 'paint', ORANGE, {'pos': [0, cy, 0], 'up': 'a'})
    add(K.taper(K.box(Wd * 0.8, Hd * 0.78, 0.13, 0.055), {'axis': 'z', 'k': 0.6, 'ease': 0.8}), 'paint', ORANGE,
        {'pos': [0, cy + 0.004, Dd / 2 + 0.05], 'up': 'a'})
    for i in range(4):
        add(K.box(0.012, 0.07, 0.01, 0.004), 'paint', INK, {'pos': [-0.036 + i * 0.024, cy + 0.01, Dd / 2 + 0.108]})
    fz = -Dd / 2
    add(K.box(Wd - 0.028, Hd - 0.028, 0.02, 0.045), 'paint', PAL.cream, {'pos': [0, cy, fz - 0.002]})
    sx, sw, sh = -0.035, 0.18, 0.142
    outer = K.roundRect(sw + 0.03, sh + 0.03, 0.04)
    outer.holes.append(THREE.Path(K.roundRect(sw, sh, 0.03).getPoints(8)))
    add(K.extrude(outer, 0.026, {'bevel': 0.007, 'bevelSeg': 1, 'curveSeg': 6}), 'paint', INK,
        {'pos': [sx, cy + 0.004, fz - 0.012]})
    scr = K.screen(game, sw, sh, {'card': _d(opts, 'card', 'show_9'), 'group': 'scr_weapon', 'dome': 0.012,
                                  'bright': 0.8})
    scr.position.set(sx, cy + 0.004, fz - 0.005)
    W.root.add(scr)
    # controls: channel dial + knob, volume, grille, nameplate, power LED
    cx = 0.1
    W.disc('dial13', 0.03, {'pos': [cx, cy + 0.045, fz - 0.0125]})
    knob = K.lathe([[0, 0], [0.022, 0], [0.024, 0.008], [0.019, 0.024], [0, 0.026]], {'round': 0.004, 'seg': 16})
    add(knob, 'chrome', None, {'pos': [cx, cy + 0.045, fz - 0.012], 'rot': [-math.pi / 2, 0, 0]})
    add(K.box(0.006, 0.02, 0.006, 0.002), 'paint', PAL.channelRed, {'pos': [cx, cy + 0.054, fz - 0.038]})
    add(knob, 'paint', INK, {'pos': [cx, cy - 0.02, fz - 0.012], 'rot': [-math.pi / 2, 0, 0], 'scale': 0.7})
    gr = THREE.PlaneGeometry(0.05, 0.036)
    K.uvRect(gr, *cellUV('grille'))
    gr.rotateY(math.pi)
    add(gr, 'decal', None, {'pos': [cx, cy - 0.07, fz - 0.0125]})
    W.sticker('telePlate', 0.086, 0.043, {'face': '-z', 'pos': [sx, cy - 0.1, fz - 0.0126]})
    add(sphere(0.005, 10, 8), 'glow', PAL.onAirRed, {'pos': [cx + 0.03, cy + 0.088, fz - 0.013], 'intensity': 3})
    # carry handle (the grip is the origin)
    for s in [-1, 1]:
        add(xcyl(0.024, 0.016, {'seg': 14}), 'paint', INK,
            {'pos': [s * (Wd / 2 - 0.006) + (-0.016 if s < 0 else 0), -0.13, 0]})
    hx = Wd / 2 + 0.012
    add(K.tube([[-hx, -0.13, 0], [-hx, -0.07, 0], [-hx + 0.03, -0.02, 0], [-0.1, 0.0, 0], [0.1, 0.0, 0],
                [hx - 0.03, -0.02, 0], [hx, -0.07, 0], [hx, -0.13, 0]], 0.009, {'seg': 36, 'radial': 8}), 'chrome')
    add(K.tube([[-0.085, 0, 0], [0.085, 0, 0]], 0.0165, {'seg': 2, 'radial': 12}), 'paint', PAL.cream)
    # telescoping antenna: base swivel + nested segments (ant2/ant3 slide up along local +y to extend)
    top = cy + Hd / 2
    add(K.lathe([[0, 0], [0.024, 0], [0.026, 0.008], [0.014, 0.018], [0, 0.02]], {'round': 0.004, 'seg': 14}), 'paint',
        INK, {'pos': [0.085, top - 0.006, 0.05]})
    ant = W.part('antenna', [0.085, top + 0.008, 0.05], W.root, [0.25, 0, -0.42])
    add(K.cyl(0.0052, 0.0052, 0.09, {'bevel': 0.0015, 'seg': 8}), 'chrome', None, {'parent': ant})
    ext = 1 if opts.get('antenna') == 'up' else 0
    a2 = W.part('ant2', [0, 0.08 * ext, 0], ant)
    add(K.cyl(0.0038, 0.0038, 0.088, {'bevel': 0.001, 'seg': 7}), 'chrome', None, {'parent': a2})
    a3 = W.part('ant3', [0, 0.078 * ext, 0], a2)
    add(K.cyl(0.0027, 0.0027, 0.085, {'bevel': 0.001, 'seg': 6}), 'chrome', None, {'parent': a3})
    add(sphere(0.0085, 12, 8), 'chrome', None, {'parent': a3, 'pos': [0, 0.092, 0]})
    # rubber feet
    for x, z in [[-1, -1], [1, -1], [-1, 1], [1, 1]]:
        add(K.cyl(0.02, 0.024, 0.018, {'bevel': 0.005, 'seg': 10}), 'paint', INK,
            {'pos': [x * (Wd / 2 - 0.05), cy - Hd / 2 - 0.016, z * (Dd / 2 - 0.045)]})
    return {
        'muzzle': [sx, cy + 0.004, fz - 0.03],
        'leftHand': [0, cy, Dd / 2 + 0.05],
        'anim': {'antenna': {'ant2': 0.08, 'ant3': 0.078}},
        'up': {
            'medal': {'pos': [Wd / 2 + 0.002, cy, -0.02], 'r': 0.022},
            'ears': {'pos': [-0.08, top - 0.004, 0.02], 's': 0.9},
        },
    }


# ---------------------------------------------------------------------------------------------- melee: walkie
def walkie(W):
    add = W.add
    BODY, BAND = '#34426A', '#283452'
    add(K.box(0.086, 0.18, 0.056, 0.022), 'paint', BODY, {'pos': [0, 0.06, 0], 'up': 'a'})
    add(K.box(0.088, 0.078, 0.058, 0.022), 'paint', BAND, {'pos': [0, -0.066, 0], 'up': 'b'})
    add(K.box(0.07, 0.11, 0.008, 0.012), 'chrome', None, {'pos': [0, 0.078, -0.028]})
    gr = THREE.PlaneGeometry(0.058, 0.094)
    K.uvRect(gr, *cellUV('grille'))
    gr.rotateY(math.pi)
    add(gr, 'decal', None, {'pos': [0, 0.078, -0.0325]})
    W.sticker('dymoCrew', 0.074, 0.0095, {'face': '-z', 'pos': [0, 0.008, -0.0286]})
    # top: rubber-duck antenna with a red tip, knurled channel knob, TX LED
    add(K.lathe([[0, 0], [0.012, 0], [0.012, 0.02], [0.009, 0.05], [0.006, 0.12], [0.005, 0.13], [0, 0.132]],
                {'round': 0.003, 'seg': 12}), 'paint', '#3A2E48', {'pos': [0.022, 0.148, 0.004]})
    add(sphere(0.0085, 12, 8), 'paint', PAL.channelRed, {'pos': [0.022, 0.282, 0.004]})
    add(K.lathe([[r, t] for r, t in ribProfile(0.022, 0.012, 4, 0.0015, 0.01)], {'seg': 14}), 'chrome', None,
        {'pos': [-0.02, 0.146, -0.004]})
    add(sphere(0.0045, 10, 8), 'glow', PAL.onAirRed, {'pos': [0.0, 0.151, -0.018], 'intensity': 3})
    # orange push-to-talk key, chrome belt clip
    add(K.box(0.012, 0.056, 0.03, 0.006), 'paint', PAL.burntOrange, {'pos': [-0.046, 0.06, 0]})
    add(K.box(0.03, 0.09, 0.006, 0.003), 'chrome', None, {'pos': [0, 0.07, 0.031]})
    return {'muzzle': [0.022, 0.29, 0.004], 'leftHand': [0, 0, 0], 'up': {'medal': {'pos': [0.044, 0.06, 0.0], 'r': 0.014}}}


# ---------------------------------------------------------------------------------------------- melee: 12" LP
def grooveTex():
    def draw(ctx, w, h, rnd):
        c = w / 2
        ctx.fillStyle = '#3A2450'
        ctx.fillRect(0, 0, w, h)
        r = c * 0.36
        while r < c * 0.985:
            gap = any(abs(r / c - g) < 0.012 for g in [0.52, 0.66, 0.8])
            ctx.strokeStyle = '#5A4476' if gap else '#2C1A3E' if rnd() < 0.5 else '#4A3262'
            ctx.lineWidth = 3 if gap else 1
            ctx.beginPath()
            ctx.arc(c, c, r, 0, TAU)
            ctx.stroke()
            r += 1.6
        for a0 in [-0.9, math.pi - 0.9]:
            g = ctx.createConicGradient(a0, c, c) if hasattr(ctx, 'createConicGradient') else None
            if not g:
                continue
            g.addColorStop(0, 'rgba(255,240,255,0)')
            g.addColorStop(0.035, 'rgba(240,220,255,0.5)')
            g.addColorStop(0.09, 'rgba(255,240,255,0)')
            g.addColorStop(1, 'rgba(255,240,255,0)')
            ctx.fillStyle = g
            ctx.beginPath()
            ctx.arc(c, c, c * 0.985, 0, TAU)
            ctx.fill()
        ctx.strokeStyle = '#4A405A'
        ctx.lineWidth = 3
        ctx.beginPath()
        ctx.arc(c, c, c * 0.99, 0, TAU)
        ctx.stroke()
    return K.tex.canvas('wpn_grooves_v2', 512, 512, draw, {'repeat': False})


def record(W):
    add, game = W.add, W.game
    R, cz, cy = 0.175, -0.17, 0.02
    g = THREE.CylinderGeometry(R, R, 0.0045, 72, 1, False)
    p = g.attributes.position
    uv = g.attributes.uv
    for i in range(p.count):
        x, z = p.getX(i), p.getZ(i)
        uv.setXY(i, 0.5 + x / (2 * R), 0.5 + z / (2 * R))
        r, a = math.hypot(x, z), math.atan2(z, x)
        p.setY(i, p.getY(i) + 0.007 * math.sin(a * 2 + 0.6) * (r / R) ** 2)
    g.computeVertexNormals()
    g.rotateZ(-math.pi / 2)
    add(g, K.mat(game, 'plastic', '#ffffff', {**KEEP, 'map': grooveTex(), 'rough': 0.28, 'env': 0.14}), None,
        {'pos': [0, cy, cz], 'up': False})
    for s in [-1, 1]:
        W.disc('lp', 0.056, {'face': '+x' if s > 0 else '-x', 'pos': [s * 0.0024, cy, cz],
                             'spin': 0 if s > 0 else math.pi})
    for s in [-1, 1]:
        add(THREE.CircleGeometry(0.0055, 12).rotateY(s * math.pi / 2), 'paint', INK, {'pos': [s * 0.0027, cy, cz]})
    return {'muzzle': [0, cy, cz - R], 'leftHand': [0, 0, 0]}


# ---------------------------------------------------------------------------------------------- melee: wrench
def wrench(W):
    add = W.add
    TEAL = '#2E9A9A'
    outline = [[-0.1, 0.0], [-0.092, 0.018], [0.24, 0.021], [0.3, 0.06], [0.385, 0.08], [0.45, 0.058], [0.468, 0.03],
               [0.418, 0.023], [0.396, 0.0],
               [0.418, -0.023], [0.468, -0.03], [0.45, -0.058], [0.385, -0.08], [0.3, -0.06], [0.24, -0.021],
               [-0.092, -0.018]]
    radii = [0.014, 0.01, 0.03, 0.03, 0.03, 0.012, 0.004, 0.004, 0.012, 0.004, 0.004, 0.012, 0.03, 0.03, 0.03, 0.01]
    hole = []
    for i in range(14):
        a = (i / 14) * TAU
        hole.append([-0.078 + math.cos(a) * 0.008, math.sin(a) * 0.008])
    add(sideHoles(outline, [hole], 0.026, {'round': radii, 'bevel': 0.008, 'steps': 3, 'bevelSeg': 3}), 'chrome',
        '#8C95A2', {'up': 'a'})
    # teal rubber grip sleeve with ribs
    add(side([[-0.055, 0.025], [0.12, 0.027], [0.128, 0.0], [0.12, -0.027], [-0.055, -0.025], [-0.062, 0.0]], 0.034,
             {'bevel': 0.012, 'round': 0.01, 'steps': 3}), 'paint', TEAL, {'up': 'b'})
    for i in range(5):
        add(K.box(0.0355, 0.046, 0.0035, 0.0012), 'paint', '#1E6A6A', {'pos': [0, 0, 0.03 - i * 0.03]})
    # knurled adjuster below the jaw + Dymo tape
    add(zlathe(ribProfile(0.04, 0.0145, 7, 0.0018, 0.012, {'gw': 0.0018}), {'seg': 16}), 'chrome', None,
        {'pos': [0, -0.04, -0.34]})
    W.sticker('dymoEng', 0.084, 0.0105, {'pos': [0.0122, 0, -0.195]})
    return {'muzzle': [0, 0, -0.468], 'leftHand': [0, 0, 0.05], 'up': {'medal': {'pos': [0.0132, 0.035, -0.37], 'r': 0.016}}}


def mergeGeo(lst):
    norm = []
    for g in lst:
        x = g.toNonIndexed() if g.index is not None else g
        if x.attributes.uv is None:
            x.setAttribute('uv', BufferAttribute(np.zeros((x.attributes.position.count, 2)), 2))
        norm.append(x)
    keep = ['position', 'normal', 'uv', 'color']
    for g in norm:
        for k in list(g.attributes.keys()):
            if k not in keep:
                g.deleteAttribute(k)
    return mergeGeometries(norm, False)


# ============================================================================================ registry + API
DEFS = {
    'revolver_38': {'build': revolver, 'desc': '.38 "Detective Special" snub revolver: fluted navy drum, walnut grip, gold star', 'hero': True},
    'pump_37': {'build': pump, 'desc': 'Model 37 pump shotgun: teak ringtail pump + stock, navy receiver, brass bead, daisy sticker', 'hero': True},
    'mp7': {'build': mp7, 'desc': 'MP7 "Agent 13": stubby olive SMG, orange accents, oversized tube sight, long magazine', 'hero': True},
    'm16a1': {'build': m16a1, 'desc': 'M16A1: triangular handguard, carry handle, charcoal + teal-grey, "13" decal', 'hero': True},
    'm60': {'build': m60, 'desc': 'M60 "Truckers!": box receiver, folded bipod, olive ammo box, instanced brass belt, 10-4 sticker', 'hero': True},
    'zapper': {'build': zapper, 'desc': 'The Zapper: 40 cm beige clicker remote, chrome piano keys, red dome, ball-tip antenna, walnut bottom', 'hero': True},
    'boom_mic': {'build': boomMic, 'desc': 'Boom Mic: telescoping pole, shaggy dead-cat windscreen, strapped reel-to-reel with VU meter', 'hero': True},
    'chroma_key': {'build': chromaKey, 'desc': 'Chroma-Key Cannon: boxy 70s camera, glass dome of chroma-blue goo, flared muzzle, viewfinder CRT', 'hero': True},
    'tube_grenade': {'build': tubeGrenade, 'desc': 'Tube grenade: glass vacuum tube, glowing orange filament, silvered getter, bakelite base'},
    'tiny_tele': {'build': tinyTele, 'desc': 'Tiny Tele: 13-inch burnt-orange portable TV, carry handle, telescoping antenna, live screen', 'hero': True},
    'melee_walkie': {'build': walkie, 'desc': 'Skip\'s walkie-talkie: navy brick, rubber-duck antenna, orange PTT, Dymo label'},
    'melee_lp': {'build': record, 'desc': 'Roxy\'s 12-inch LP: plum vinyl with grooves and sheen, Boogie Down label, a cartoon warp'},
    'melee_wrench': {'build': wrench, 'desc': 'Penny\'s oversized chrome open-end wrench: teal rubber grip, knurled adjuster, Dymo label', 'hero': True},
}
WEAPON_IDS = list(DEFS.keys())


def poseGroup(h, pose):
    if pose == 'hand':
        return
    if pose == 'wall':
        h.rotation.y = math.pi / 2
    h.updateMatrixWorld(True)
    bb = THREE.Box3()
    h.traverse(lambda o: bb.expandByObject(o) if getattr(o, 'isMesh', False) else None)
    c = bb.getCenter(V3())
    if pose == 'wall':
        h.position.set(-c.x, -c.y, -bb.max.z)
    else:
        h.position.set(-c.x, -bb.min.y + 0.002, -c.z)
    h.updateMatrixWorld(True)


def makeWeapon(game, id, opts=None):
    opts = {} if opts is None else opts
    dfn = DEFS.get(id)
    if not dfn:
        raise KeyError('[weapons] unknown weapon "%s"' % id)
    g = K.prop(id)
    h = THREE.Group()
    h.name = 'wpn'
    g.add(h)
    W = makeCtx(game, id, opts, h)
    spec = dfn['build'](W) or {}
    if W.up and spec.get('up'):
        upgradeKit(W, spec['up'])
    muzzle = THREE.Object3D()
    muzzle.name = 'muzzle'
    muzzle.position.fromArray(_d(spec, 'muzzle', [0, 0, -0.2]))
    h.add(muzzle)
    chromaUV(W)
    pose = _d(opts, 'pose', 'hand')   # JS: opts.pose ?? (globalThis.__pv ? 'display' : 'hand') — no propview here
    poseGroup(h, pose)

    def toRoot(p):
        return [js_round(n * 1e4) / 1e4 for n in V3().fromArray(p).applyMatrix4(h.matrix).toArray()]
    u = g.userData
    u.parts = W.parts
    u.leftHand = toRoot(_d(spec, 'leftHand', [0, -0.03, -0.1]))
    u.grip = toRoot([0, 0, 0])
    u.muzzle = toRoot(_d(spec, 'muzzle', [0, 0, -0.2]))
    u.weapon = JSObj(id=id, upgraded=W.up, signal=W.signal, pose=pose)
    u.anim = _d(spec, 'anim', None)
    if pose == 'hand':
        u.colliders = []
    if spec.get('screens'):
        u.screens = spec['screens']
    return K.finish(game, g, {'ao': {'floor': False, 'height': 0, 'dist': _d(dfn, 'aoDist', 0.06), 'strength': 0.75,
                                     'rays': 16, 'res': 72}, 'cast': 0.04})


# Cached (buildProp) weapon: opts { upgraded, signal, pose }.
def buildWeapon(id, opts=None, game=None):
    return buildProp(id, game if game is not None else K.Game(), {} if opts is None else opts)


# Drop-in replacement for src/game/weaponModels.js buildWeaponModel(id, upgraded, game).
def buildWeaponModel(id, upgraded=False, game=None):
    return buildProp(id, game if game is not None else K.Game(), {'upgraded': bool(upgraded), 'pose': 'hand'})


# animateWeapon(group, t, state): runtime per-frame helper -> godot/scripts/game/weapon_models.gd (not a build step).

def _register(id_, dfn):
    registerProp(id_, lambda game, opts=None: makeWeapon(game, id_, {} if opts is None else opts),
                 {'category': 'weapons', 'tags': ['weapon'] + list(dfn.get('tags') or []), 'desc': dfn['desc'],
                  'hero': bool(dfn.get('hero'))})


for _id, _def in DEFS.items():
    _register(_id, _def)


# ============================================================================================ propview scenes
# Armory walls: the guns in 'wall' pose (wall-buy mounting) + the wonder weapons / throwables / melee.
def WALL(id, x, y, opts=None):
    return {'id': id, 'pos': [x, y, 1.095], 'opts': {'pose': 'wall', **(opts or {})}}


registerScene('weapons_wall', {
    'floor': 'wood', 'wall': 'panel', 'room': [3.0, 2.2], 'wallH': 2.8,
    'items': [WALL('m60', 0, 2.22), WALL('m16a1', 0, 1.86), WALL('pump_37', 0, 1.52), WALL('mp7', -0.42, 1.08),
              WALL('revolver_38', 0.46, 1.1)],
    'cam': {'pos': [0, 1.62, -1.25], 'target': [0, 1.62, 1.1], 'fov': 50},
})
registerScene('weapons_wall_up', {
    'floor': 'wood', 'wall': 'panel', 'room': [3.0, 2.2], 'wallH': 2.8,
    'items': [WALL('m60', 0, 2.22, {'upgraded': True, 'signal': 'cold_open'}), WALL('m16a1', 0, 1.86, {'upgraded': True}),
              WALL('pump_37', 0, 1.52, {'upgraded': True, 'signal': 'laugh_track'}),
              WALL('mp7', -0.42, 1.08, {'upgraded': True, 'signal': 'hot_mic'}),
              WALL('revolver_38', 0.46, 1.1, {'upgraded': True, 'signal': 'hot_mic'})],
    'cam': {'pos': [0, 1.62, -1.25], 'target': [0, 1.62, 1.1], 'fov': 50},
})
registerScene('weapons_wonder', {
    'floor': 'wood', 'wall': 'panel', 'room': [3.0, 2.2], 'wallH': 2.8,
    'items': [WALL('boom_mic', 0, 2.22), WALL('zapper', -0.42, 1.8), WALL('chroma_key', 0.38, 1.7),
              WALL('melee_wrench', -0.4, 1.34), WALL('melee_lp', 0.1, 1.22)],
    'cam': {'pos': [0, 1.62, -1.35], 'target': [0, 1.62, 1.1], 'fov': 52},
})
# Hand pose check: every weapon as held (grip at the prop origin), right side to the camera.
registerScene('weapons_hand', {
    'floor': 'wood', 'wall': 'panel', 'room': [3.0, 2.2], 'wallH': 2.8,
    'items': [{'id': i, 'pos': [x + 0.2, y, 0.9], 'rotY': math.pi / 2, 'opts': {'pose': 'hand'}} for i, x, y in [
        ['m60', -0.28, 2.3], ['m16a1', -0.28, 2.0], ['pump_37', -0.33, 1.73], ['boom_mic', -0.15, 1.47],
        ['mp7', -0.85, 1.08], ['revolver_38', -0.45, 1.08], ['zapper', -0.05, 1.12],
        ['chroma_key', 0.42, 1.03], ['tube_grenade', -0.95, 0.64], ['melee_walkie', -0.7, 0.58],
        ['melee_wrench', -0.2, 0.7], ['melee_lp', 0.3, 0.62], ['tiny_tele', 0.78, 0.88]]],
    'cam': {'pos': [0, 1.5, -1.6], 'target': [0, 1.45, 1.1], 'fov': 58},
})
registerScene('weapons_small', {
    'floor': 'shag', 'wall': 'panel', 'room': [2.0, 1.6], 'wallH': 2.4,
    'items': [{'id': 'tiny_tele', 'pos': [0.22, 0.0, 0.2], 'rotY': -0.4, 'opts': {'pose': 'display', 'antenna': 'up'}},
              {'id': 'tube_grenade', 'pos': [-0.12, 0, 0.0], 'opts': {'pose': 'display'}},
              {'id': 'melee_walkie', 'pos': [-0.36, 0, 0.12], 'rotY': 0.35, 'opts': {'pose': 'display'}},
              {'id': 'tube_grenade', 'pos': [0.02, 0, -0.14], 'rotY': 1, 'opts': {'pose': 'display', 'upgraded': True}}],
    'cam': {'pos': [0.0, 0.42, -0.95], 'target': [0, 0.16, 0.1], 'fov': 40},
})
