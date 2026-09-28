"""DEAD AIR — static meshes the easter egg (src/game/easteregg.js) built at runtime (SPEC §4/§5), as Blender assets.

Port of the art helpers of src/game/easteregg.js, line by line against the three.js-like graph (dalib.scene), the
prop kit (dalib.kit, same function names as src/props/kit.js) and the exact three geometry port (dalib.three_geo).
The Godot module (godot/scripts/game/easteregg.gd) loads these GLBs from godot/assets/runtime/easteregg/ and does
everything that moves or changes at runtime (poses, the on-air look variants, the lightning bolts, the knife-switch
outline, the VTR #2 picture, the per-instance glove fade, the rain scroll):

    ee_puppet_dudley.glb     buildDudley(): purple felt dragon (prop root 'ee_puppet_dudley', parts jaw / armL / armR
                             as noMerge groups at their pivots), finishPuppet (AO res 40 strength 0.7, parts merged,
                             no shadow casting)
    ee_puppet_sockrates.glb  buildSockrates(): striped sock puppet (part jaw; armL / armR = null), canvas
                             'egg.sock_stripes.v2'
    ee_puppet_hootie.glb     buildHootie(): brown felt owl host (parts jaw / armL / armR)
    ee_confetti_cannon.glb   buildCannon(): prop root 'ee_confetti_cannon', part 'barrel' at rest (the JS then turns the
                             barrel with setFromUnitVectors(+y, aimDir): easteregg.gd does it per cannon)
    ee_stray_storm.glb       buildStorm(): root 'stray_storm' -> 'body' -> 'cloud' (merged squashed puffs, toon
                             #5B4A7A), 'face' (plane, canvas 'egg.storm_face'), 'glow' (sphere, scale 1.35/0.7/0.9);
                             'rain' (open cylinder, canvas 'egg.storm_rain'). The root's 0.92 scale, the rain texture's
                             repeat (4, 1) + scrolling offset and the unlit materials are applied by easteregg.gd.
    ee_applause_glove.glb    gloveGeometry(false) / gloveGeometry(true) as meshes 'ee_applause_glove_l' / '_r' under the
                             root 'ee_applause_glove' (vertex colours; easteregg.gd draws them as two MultiMeshes)

Node names that the JS left empty ('body', 'cloud', 'face', 'glow', 'rain', the glove meshes) are given here so the
Godot side can find them (engine glue only).

Run: python3 blender/build_all.py --only runtime   (build_all calls build(save_blend)), or standalone:
     cd /home/user/dead-air && python3 blender/runtime/easteregg.py [--save-blend] [--only ee_puppet_dudley,...]
"""
import math
import os
import sys

import numpy as np

_HERE = os.path.dirname(os.path.abspath(__file__))
_BLENDER = os.path.dirname(_HERE)
if _BLENDER not in sys.path:
    sys.path.insert(0, _BLENDER)

from dalib import kit as K  # noqa: E402
from dalib.kit import THREE  # noqa: E402
from dalib.three_geo import mergeGeometries  # noqa: E402

REPO = os.path.dirname(_BLENDER)
OUT_DIR = os.path.join(REPO, 'godot', 'assets', 'runtime', 'easteregg')
BLEND_DIR = os.path.join(_BLENDER, 'out', 'runtime', 'easteregg')
PI = math.pi
TAU = PI * 2
STORM_COLOR = '#5B4A7A'


def clamp01(x):
    return 0 if x < 0 else (1 if x > 1 else x)


# ================================================================================================ art helpers
def tg(geo, color):
    return K.tint(geo.clone(), color)


def tm(geo, mat, color=None, o=None):
    return K.m(tg(geo, color) if color else geo, mat, o)


def sph(r, ws=18, hs=12):
    return THREE.SphereGeometry(r, ws, hs)


def cone(r, h, seg=12):
    return K.lathe([[0, 0], [r, 0], [r * 0.35, h * 0.72], [0, h]], {'seg': seg, 'round': min(r, h) * 0.18})


def googly(g, plas, pos, r, look, opts=None):
    """Googly eye: white ball + black pupil pushed toward `look` on its surface (+ a tiny catchlight)."""
    opts = opts or {}
    pupil = opts.get('pupil', 0.5)
    white = opts.get('white', '#FFFFFF')
    iris = opts.get('iris')
    g.add(tm(sph(r, 16, 12), plas, white, {'pos': pos}))
    d = THREE.Vector3(*look).normalize()
    if iris:
        g.add(tm(sph(r * 0.72, 14, 10), plas, iris, {'pos': [pos[0] + d.x * r * 0.62, pos[1] + d.y * r * 0.62, pos[2] + d.z * r * 0.62], 'scale': [1, 1, 0.55]}))
    pr = r * pupil
    pp = [pos[0] + d.x * (r - pr * 0.45), pos[1] + d.y * (r - pr * 0.45), pos[2] + d.z * (r - pr * 0.45)]
    pm = tm(sph(pr, 14, 10), plas, '#15101C', {'pos': pp, 'scale': [1, 1, 0.6]})
    pm.lookAt(pp[0] + d.x, pp[1] + d.y, pp[2] + d.z)
    g.add(pm)
    g.add(tm(sph(pr * 0.3, 8, 6), plas, '#FFFFFF', {'pos': [pp[0] + pr * 0.35, pp[1] + pr * 0.4, pp[2] + d.z * pr * 0.55]}))


def puppetFelt(game):
    """felt with a gentler rim than the kit preset (the preset's velvet halo washes small saturated puppets out)"""
    return K.mat(game, 'felt', '#ffffff', {'keepColor': True, 'rim': 0.22, 'rimPower': 2.6, 'wrap': 0.6})


def latheV(profile, opts, vSpan):
    """Lathe with v = height / vSpan (even stripes whatever the profile's point spacing)"""
    g = K.lathe(profile, opts).clone()
    p, uv = g.attributes.position, g.attributes.uv
    for i in range(p.count):
        uv.setY(i, p.getY(i) / vSpan)
    uv.needsUpdate = True
    return g


def partGroup(g, name, pos):
    p = THREE.Group()
    p.name = name
    p.position.set(pos[0], pos[1], pos[2])
    p.userData.noMerge = True
    g.add(p)
    g.userData.parts[name] = p
    return p


def finishPuppet(game, g):
    K.finish(game, g, {'ao': {'res': 40, 'strength': 0.7}})
    for p in list(g.userData.parts.values()):
        if p:
            K.merge(p)

    def f(o):
        if getattr(o, 'isMesh', False):
            o.castShadow = False
            o.receiveShadow = True
    g.traverse(f)
    return g


def buildDudley(game):
    """Dudley: purple felt dragon, googly eyes, yellow belly (GDD §13 step 2). ~0.5 m, base at y 0, front -z."""
    g = K.prop('ee_puppet_dudley')
    felt = puppetFelt(game)
    plas = K.mat(game, 'plastic', '#ffffff', {'keepColor': True})
    P, PD, BELLY, GREEN, CREAM = '#9B57F2', '#7340CC', '#FFD24A', '#46D467', '#FFF1D6'
    g.add(tm(K.lathe([[0, 0], [0.132, 0], [0.15, 0.035], [0.152, 0.11], [0.136, 0.2], [0.11, 0.27], [0, 0.3]], {'round': 0.025, 'seg': 24}), felt, P))
    g.add(tm(THREE.TorusGeometry(0.138, 0.02, 8, 26).rotateX(PI / 2), felt, PD, {'pos': [0, 0.022, 0]}))
    belly = K.tint(sph(0.1, 20, 16), lambda x, y, z: THREE.Color('#FFD84A') if math.floor((y + 0.1) / 0.05) % 2 else THREE.Color('#F5B528'))
    g.add(K.m(belly, felt, {'pos': [0, 0.15, -0.098], 'scale': [0.98, 1.25, 0.52]}))
    for s in [-1, 1]:
        g.add(tm(sph(0.028, 10, 8), felt, '#FF7FAA', {'pos': [s * 0.095, 0.385, -0.15], 'scale': [1, 0.7, 0.4]}))
    # head: cranium + long snout
    g.add(tm(sph(0.118), felt, P, {'pos': [0, 0.43, 0.03]}))
    g.add(tm(sph(0.12), felt, P, {'pos': [0, 0.385, -0.075], 'scale': [1.05, 0.7, 1.35]}))
    for s in [-1, 1]:
        g.add(tm(sph(0.014, 8, 6), felt, PD, {'pos': [s * 0.036, 0.41, -0.228]}))
    for s in [-1, 1]:
        g.add(tm(cone(0.014, 0.04, 8).rotateX(PI), plas, '#FFFFFF', {'pos': [s * 0.05, 0.36, -0.19]}))
    googly(g, plas, [-0.058, 0.505, -0.03], 0.056, [0.3, -0.35, -1])
    googly(g, plas, [0.058, 0.51, -0.025], 0.056, [-0.1, -0.1, -1])
    for s in [-1, 1]:
        g.add(tm(cone(0.022, 0.075, 10), felt, CREAM, {'pos': [s * 0.068, 0.53, 0.07], 'rot': [-0.55, 0, s * 0.35]}))
    for y, z, r in [[0.54, 0.06, 0.034], [0.49, 0.13, 0.042], [0.4, 0.165, 0.048], [0.3, 0.16, 0.046], [0.2, 0.155, 0.04]]:
        g.add(tm(cone(r, r * 1.5, 10), felt, GREEN, {'pos': [0, y, z], 'rot': [-1.2 + y * 0.8, 0, 0]}))
    for s in [-1, 1]:
        g.add(tm(cone(0.05, 0.12, 3), felt, GREEN, {'pos': [s * 0.08, 0.25, 0.12], 'rot': [-1.0, s * 0.5, s * 0.9], 'scale': [1, 1, 0.35]}))
    # jaw (lower snout + red mouth + tongue)
    jaw = partGroup(g, 'jaw', [0, 0.35, 0.03])
    jaw.rotation.x = -0.16
    jaw.add(tm(sph(0.105), felt, P, {'pos': [0, -0.03, -0.095], 'scale': [1, 0.42, 1.3]}))
    jaw.add(tm(sph(0.09), felt, '#C42F4C', {'pos': [0, 0.0, -0.1], 'scale': [0.9, 0.3, 1.12]}))
    jaw.add(tm(sph(0.036), felt, '#FF86A8', {'pos': [0, 0.012, -0.15], 'scale': [1, 0.4, 1.4]}))
    # stubby arms with mitten hands
    for s, name in [[-1, 'armL'], [1, 'armR']]:
        a = partGroup(g, name, [s * 0.13, 0.225, -0.02])
        a.add(tm(K.lathe([[0, 0], [0.032, 0.004], [0.03, -0.075], [0.0, -0.085]], {'round': 0.014, 'seg': 12}), felt, P, {'rot': [0.35, 0, s * 0.3]}))
        a.add(tm(sph(0.037, 12, 9), felt, P, {'pos': [s * 0.025, -0.085, -0.03]}))
        a.add(tm(sph(0.016, 8, 6), felt, CREAM, {'pos': [s * 0.035, -0.07, -0.062]}))
    return finishPuppet(game, g)


def _sock_stripes(ctx, w, h, rand):
    cols = ['#F2363A', '#FFF9EE', '#2F66F2', '#FFF9EE']
    for i in range(8):
        ctx.fillStyle = cols[i % 4]
        ctx.fillRect(0, (i * h) / 8, w, h / 8 + 1)
    ctx.fillStyle = 'rgba(0,0,0,0.06)'
    x = 0
    while x < w:
        ctx.fillRect(x, 0, 1, h)
        x += 4


def buildSockrates(game):
    """Sockrates: striped sock puppet with tiny spectacles, a toga sash, a laurel wreath and a felt beard."""
    g = K.prop('ee_puppet_sockrates')
    felt = puppetFelt(game)
    plas = K.mat(game, 'plastic', '#ffffff', {'keepColor': True})
    stripeTex = K.tex.canvas('egg.sock_stripes.v2', 64, 128, _sock_stripes)
    sock = K.mat(game, 'fabric', '#ffffff', {'map': stripeTex, 'keepColor': True, 'rim': 0.4})
    RED = '#EC3340'
    g.add(K.m(latheV([[0, 0], [0.122, 0], [0.132, 0.03], [0.128, 0.13], [0.118, 0.23], [0.1, 0.295], [0, 0.32]], {'round': 0.02, 'seg': 24}, 0.3), sock))
    g.add(tm(THREE.TorusGeometry(0.128, 0.022, 8, 26).rotateX(PI / 2), felt, '#F4F1E8', {'pos': [0, 0.02, 0]}))
    # toe = upper jaw (solid red toe patch)
    g.add(tm(sph(0.118), felt, RED, {'pos': [0, 0.37, -0.06], 'scale': [1, 0.72, 1.3]}))
    g.add(tm(sph(0.1), felt, RED, {'pos': [0, 0.395, 0.03]}))
    # button eyes + spectacles
    for s in [-1, 1]:
        g.add(tm(sph(0.027, 12, 9), plas, '#18121E', {'pos': [s * 0.045, 0.44, -0.108]}))
        g.add(tm(sph(0.007, 6, 5), plas, '#FFFFFF', {'pos': [s * 0.045 + 0.009, 0.449, -0.131]}))
        g.add(tm(THREE.TorusGeometry(0.033, 0.0055, 6, 18), plas, '#D9AE48', {'pos': [s * 0.046, 0.438, -0.128], 'rot': [0.12, 0, 0]}))
        g.add(tm(K.tube([[s * 0.079, 0.44, -0.125], [s * 0.1, 0.445, -0.07], [s * 0.105, 0.43, -0.01]], 0.004, {'seg': 6, 'radial': 4}), plas, '#D9AE48'))
    g.add(tm(K.tube([[-0.014, 0.442, -0.134], [0, 0.45, -0.138], [0.014, 0.442, -0.134]], 0.004, {'seg': 6, 'radial': 4}), plas, '#D9AE48'))
    # laurel wreath
    lg = sph(0.024, 10, 7)
    for i in range(14):
        a = (i / 14) * TAU
        l = tm(lg, felt, '#5DAA3E' if i % 2 else '#7BC650', {'pos': [math.sin(a) * 0.092, 0.462 + (i % 2) * 0.012, 0.03 + math.cos(a) * 0.092], 'scale': [1, 0.42, 0.55]})
        l.rotation.set(0, a, (0.5 if i % 2 else -0.5))
        g.add(l)
    g.add(tm(sph(0.012, 8, 6), felt, '#E8A92E', {'pos': [0, 0.47, -0.065]}))
    # toga sash (over the right shoulder, across the chest) + gold brooch
    sash = K.lathe([[0.126, -0.04], [0.14, -0.036], [0.146, 0], [0.14, 0.036], [0.126, 0.04]], {'seg': 28, 'round': 0.006}).clone()
    K.tint(sash, lambda x, y, z: THREE.Color('#E8A92E') if y < -0.028 else THREE.Color('#FFF6E6'))
    g.add(K.m(sash, felt, {'pos': [0, 0.165, 0], 'rot': [0.1, 0, 0.6]}))
    g.add(tm(K.lathe([[0, 0], [0.05, 0.01], [0.04, 0.09], [0, 0.1]], {'seg': 10, 'round': 0.01}), felt, '#FFF6E6', {'pos': [0.1, 0.2, 0.045], 'rot': [0.2, 0, -0.35]}))
    g.add(tm(sph(0.02, 10, 8), plas, '#E8A92E', {'pos': [0.098, 0.25, -0.075]}))
    # jaw: lower toe + mouth + tongue + beard
    jaw = partGroup(g, 'jaw', [0, 0.335, 0.02])
    jaw.rotation.x = -0.18
    jaw.add(tm(sph(0.1), felt, RED, {'pos': [0, -0.028, -0.09], 'scale': [0.96, 0.4, 1.26]}))
    jaw.add(tm(sph(0.085), felt, '#6E1A34', {'pos': [0, 0.0, -0.095], 'scale': [0.88, 0.3, 1.1]}))
    jaw.add(tm(sph(0.03), felt, '#FF86A8', {'pos': [0.02, 0.012, -0.15], 'scale': [1, 0.4, 1.4]}))
    for x, y, z, r in [[0, -0.055, -0.15, 0.045], [-0.045, -0.045, -0.13, 0.036], [0.045, -0.045, -0.13, 0.036], [-0.02, -0.095, -0.145, 0.034], [0.02, -0.095, -0.145, 0.034], [0, -0.13, -0.14, 0.026]]:
        jaw.add(tm(sph(r, 12, 9), felt, '#F7F4EE', {'pos': [x, y, z]}))
    g.userData.parts.armL = g.userData.parts.armR = None
    return finishPuppet(game, g)


def buildHootie(game):
    """Hootie: brown felt owl host with huge round eyes, ear tufts, a red bow tie."""
    g = K.prop('ee_puppet_hootie')
    felt = puppetFelt(game)
    plas = K.mat(game, 'plastic', '#ffffff', {'keepColor': True})
    BR, BRD, TAN, ORANGE = '#A1612E', '#7B4520', '#F5D09A', '#FF8A1C'
    g.add(tm(K.lathe([[0, 0], [0.125, 0], [0.155, 0.06], [0.165, 0.17], [0.155, 0.28], [0.125, 0.37], [0.07, 0.43], [0, 0.445]], {'round': 0.02, 'seg': 24}), felt, BR))
    g.add(tm(THREE.SphereGeometry(0.13, 22, 16), felt, TAN, {'pos': [0, 0.16, -0.105], 'scale': [0.84, 1.02, 0.54]}))
    scallop = THREE.SphereGeometry(0.021, 12, 6, 0, TAU, 0, PI / 2).rotateX(-PI / 2)
    for y, xs in [[0.215, [-0.036, 0, 0.036]], [0.175, [-0.054, -0.018, 0.018, 0.054]], [0.135, [-0.036, 0, 0.036]], [0.095, [-0.018, 0.018]]]:
        for x in xs:
            q = 1 - (x / 0.109) ** 2 - ((y - 0.16) / 0.133) ** 2
            z = -0.105 - 0.07 * math.sqrt(max(0, q)) + 0.004
            g.add(tm(scallop, felt, '#D69A5A', {'pos': [x, y, z], 'scale': [1, 0.8, 0.45]}))
    for s in [-1, 1]:
        g.add(tm(sph(0.088), felt, '#FFF0CF', {'pos': [s * 0.068, 0.325, -0.108], 'scale': [1, 1, 0.35]}))
        g.add(tm(K.lathe([[0, 0], [0.018, 0.002], [0.004, 0.05]], {'seg': 8, 'round': 0.004}), felt, BRD, {'pos': [s * 0.075, 0.405, -0.1], 'rot': [-0.3, 0, -s * 1.15]}))
        g.add(tm(cone(0.036, 0.1, 10), felt, BRD, {'pos': [s * 0.095, 0.425, 0.0], 'rot': [0, 0, -s * 0.45]}))
    googly(g, plas, [-0.068, 0.328, -0.125], 0.056, [0.05, 0.02, -1], {'pupil': 0.62, 'iris': '#FFB52E', 'white': '#FFF6DA'})
    googly(g, plas, [0.068, 0.328, -0.125], 0.056, [-0.05, 0.02, -1], {'pupil': 0.62, 'iris': '#FFB52E', 'white': '#FFF6DA'})
    g.add(tm(cone(0.028, 0.07, 10), plas, ORANGE, {'pos': [0, 0.29, -0.15], 'rot': [-2.1, 0, 0]}))
    # red bow tie
    for s in [-1, 1]:
        g.add(tm(cone(0.042, 0.075, 12), plas, '#E23B3B', {'pos': [s * 0.078, 0.232, -0.15], 'rot': [0, 0, s * PI / 2], 'scale': [1, 1, 0.5]}))
    g.add(tm(sph(0.02, 12, 9), plas, '#C22A2A', {'pos': [0, 0.232, -0.158]}))
    for s in [-1, 1]:
        g.add(tm(sph(0.009, 6, 5), plas, '#FFFFFF', {'pos': [s * 0.05, 0.245, -0.168]}))
    # feet
    for s in [-1, 1]:
        for k in range(-1, 2):
            g.add(tm(sph(0.02, 8, 6), plas, ORANGE, {'pos': [s * 0.06 + k * 0.022, 0.012, -0.12 - abs(k) * -0.01], 'scale': [1, 0.6, 1.4]}))
    jaw = partGroup(g, 'jaw', [0, 0.26, -0.14])
    jaw.add(tm(cone(0.02, 0.035, 8), plas, '#D8741E', {'pos': [0, 0, -0.01], 'rot': [-2.5, 0, 0]}))
    for s, name in [[-1, 'armL'], [1, 'armR']]:
        w = partGroup(g, name, [s * 0.148, 0.31, 0.01])
        w.add(tm(sph(0.1), felt, '#86502A', {'pos': [s * 0.012, -0.1, 0], 'scale': [0.32, 1, 0.72]}))
        w.add(tm(sph(0.06, 12, 8), felt, BRD, {'pos': [s * 0.018, -0.17, 0.01], 'scale': [0.3, 0.8, 0.6]}))
    return finishPuppet(game, g)


# ------------------------------------------------------------------------------------------------ Stray Storm
def _storm_face(ctx, w, h, rand):
    ctx.clearRect(0, 0, w, h)
    ctx.lineCap = 'round'
    for s in [-1, 1]:
        cx, cy = w / 2 + s * 52, 58
        ctx.fillStyle = '#FFFFFF'
        ctx.beginPath()
        ctx.ellipse(cx, cy, 24, 17, 0, 0, TAU)
        ctx.fill()
        ctx.fillStyle = '#1E1530'
        ctx.beginPath()
        ctx.arc(cx - s * 4, cy + 4, 9, 0, TAU)
        ctx.fill()
        # heavy lid slanting down toward the nose + an angry brow (inner end low)
        ctx.fillStyle = STORM_COLOR
        ctx.beginPath()
        ctx.moveTo(cx - 32, cy - 32)
        ctx.lineTo(cx + 32, cy - 32)
        ctx.lineTo(cx + 32, cy + 1 if s < 0 else cy - 15)
        ctx.lineTo(cx - 32, cy - 15 if s < 0 else cy + 1)
        ctx.closePath()
        ctx.fill()
        ctx.strokeStyle = '#1E1530'
        ctx.lineWidth = 11
        ctx.beginPath()
        ctx.moveTo(cx - s * 30, cy - 4)
        ctx.lineTo(cx + s * 28, cy - 24)
        ctx.stroke()
    # grumbling mouth: a lopsided frown with a zig-zag
    ctx.strokeStyle = '#1E1530'
    ctx.lineWidth = 8
    ctx.lineJoin = 'round'
    ctx.beginPath()
    ctx.moveTo(w / 2 - 36, 110)
    ctx.lineTo(w / 2 - 22, 98)
    ctx.lineTo(w / 2 - 10, 106)
    ctx.lineTo(w / 2 + 2, 96)
    ctx.lineTo(w / 2 + 14, 104)
    ctx.lineTo(w / 2 + 26, 96)
    ctx.lineTo(w / 2 + 36, 108)
    ctx.stroke()


def _storm_rain(ctx, w, h, rand):
    ctx.clearRect(0, 0, w, h)
    for i in range(38):
        x, y, l = rand() * w, rand() * h, 10 + rand() * 18
        # (JS evaluation order: x, y, then l)
        gr = ctx.createLinearGradient(x, y, x, y + l)
        gr.addColorStop(0, 'rgba(200,215,255,0)')
        gr.addColorStop(1, 'rgba(210,225,255,0.95)')
        ctx.strokeStyle = gr
        ctx.lineWidth = 1.4
        ctx.beginPath()
        ctx.moveTo(x, y)
        ctx.lineTo(x - 1, y + l)
        ctx.stroke()


def buildStorm(game):
    """The Stray Storm: a 1.5x Forecaster cloud in #5B4A7A with a grumpy face, an inner crackle glow and a rain
    column. Returns { root, body, cloud, face, faceMat, glow, glowMat, rain, rainMat, rainTex } like the JS."""
    root = THREE.Group()
    root.name = 'stray_storm'
    body = THREE.Group()
    body.name = 'body'
    root.add(body)
    puffs = [[0, 0, 0, 0.62], [0.58, 0.02, 0.05, 0.5], [-0.58, 0.0, 0.03, 0.52], [0.26, 0.34, 0.08, 0.46], [-0.3, 0.3, 0.02, 0.45],
             [0.98, -0.14, 0, 0.34], [-1.0, -0.12, 0.05, 0.36], [0, -0.24, 0.18, 0.42], [0.36, -0.22, -0.22, 0.36], [-0.36, -0.2, -0.2, 0.38],
             [0, 0.12, 0.38, 0.5], [0.05, 0.5, 0.12, 0.34]]
    geos = []
    for x, y, z, r in puffs:
        s = THREE.SphereGeometry(r, 16, 11)
        p = s.attributes.position
        for i in range(p.count):
            if p.getY(i) < -r * 0.45:
                p.setY(i, -r * 0.45 + (p.getY(i) + r * 0.45) * 0.35)
        s.computeVertexNormals()
        s.translate(x, y, z)
        geos.append(s)
    cloudGeo = mergeGeometries(geos, False)
    mat = game.mats.toon(STORM_COLOR, {'rough': 0.95, 'rim': 0.32, 'rimColor': '#B9A4F0', 'rimPower': 2.4, 'wrap': 0.7, 'keepColor': True, 'emissive': '#1C1430', 'emissiveIntensity': 0.6})
    cloud = THREE.Mesh(cloudGeo, mat)
    cloud.name = 'cloud'
    cloud.castShadow = True
    body.add(cloud)
    # grumpy face: angry brows, squinting eyes with little pupils, a wobbly frown
    faceTex = K.tex.canvas('egg.storm_face', 256, 128, _storm_face, {'repeat': False})
    faceMat = THREE.MeshBasicMaterial({'map': faceTex, 'transparent': True, 'alphaTest': 0.3, 'depthWrite': False, 'toneMapped': False})
    face = THREE.Mesh(THREE.PlaneGeometry(0.95, 0.475), faceMat)
    face.name = 'face'
    face.position.set(0, 0.05, -0.66)
    face.rotation.y = PI
    face.renderOrder = 2
    body.add(face)
    # crackle glow (inner)
    glowMat = THREE.MeshBasicMaterial({'color': THREE.Color('#C9A8FF').multiplyScalar(2.2), 'transparent': True, 'opacity': 0, 'blending': THREE.AdditiveBlending, 'depthWrite': False})
    glow = THREE.Mesh(THREE.SphereGeometry(0.8, 14, 10), glowMat)
    glow.name = 'glow'
    glow.scale.set(1.35, 0.7, 0.9)
    body.add(glow)
    # rain column: additive streaks scrolling down. (The JS clone's repeat (4, 1) is NOT baked into the UVs here:
    # easteregg.gd applies repeat (4, rainH / 1.6) and the scrolling offset at runtime on the raw cylinder UVs.)
    rainTex = K.tex.canvas('egg.storm_rain', 64, 128, _storm_rain).clone()
    rainTex.wrapS = rainTex.wrapT = THREE.RepeatWrapping
    rainMat = THREE.MeshBasicMaterial({'map': rainTex, 'color': '#AFC4FF', 'transparent': True, 'opacity': 0.7, 'blending': THREE.AdditiveBlending, 'depthWrite': False, 'side': THREE.DoubleSide})
    rainGeo = THREE.CylinderGeometry(0.8, 0.95, 1, 14, 1, True)
    rainGeo.translate(0, -0.5, 0)
    rain = THREE.Mesh(rainGeo, rainMat)
    rain.name = 'rain'
    rain.castShadow = False
    root.add(rain)
    # (JS: root.scale.setScalar(0.92) — applied by easteregg.gd, the asset keeps scale 1)
    return dict(root=root, body=body, cloud=cloud, face=face, faceMat=faceMat, glow=glow, glowMat=glowMat, rain=rain,
                rainMat=rainMat, rainTex=rainTex)


# ------------------------------------------------------------------------------------------------ confetti cannon
def buildCannon(game, aimDir=None):
    """Confetti cannon for the lighting grid (step 3): a striped barrel with a flared gold muzzle on a clamp post.
    Pivot at the origin; the post rises to the grid (+y); parts.barrel points along aimDir (its local +y).
    aimDir None = the rest pose exported as the asset (easteregg.gd turns the barrel per cannon)."""
    g = K.prop('ee_confetti_cannon')
    lac = K.mat(game, 'lacquer', '#ffffff', {'keepColor': True})
    metal = K.mat(game, 'metal', '#ffffff')
    barrel = partGroup(g, 'barrel', [0, 0, 0])

    def stripes(y):
        return THREE.Color('#E23B3B') if math.floor((y + 0.05) / 0.07) % 2 else THREE.Color('#F4F1E8')
    body = K.lathe([[0, -0.08], [0.1, -0.08], [0.11, -0.03], [0.1, 0.34], [0.13, 0.4], [0.155, 0.45], [0.11, 0.46], [0, 0.44]], {'round': 0.012, 'seg': 18}).clone()
    K.tint(body, lambda x, y, z: THREE.Color('#E8A92E') if y > 0.35 else stripes(y))
    barrel.add(K.m(body, lac))
    barrel.add(tm(THREE.TorusGeometry(0.105, 0.018, 6, 18).rotateX(PI / 2), lac, '#E8A92E', {'pos': [0, 0.06, 0]}))
    g.add(tm(sph(0.055, 12, 9), metal, '#3A3440', {'pos': [0, 0, 0]}))
    g.add(tm(K.box(0.05, 0.34, 0.05, 0.012), metal, '#3A3440', {'pos': [0, 0.2, 0]}))
    g.add(tm(K.box(0.16, 0.05, 0.1, 0.015), metal, '#3A3440', {'pos': [0, 0.37, 0]}))
    K.finish(game, g, {'ao': False})
    K.merge(barrel)
    if aimDir is not None:
        barrel.quaternion.setFromUnitVectors(THREE.Vector3(0, 1, 0), aimDir)

    def f(o):
        if getattr(o, 'isMesh', False):
            o.castShadow = False
    g.traverse(f)
    return g


# ------------------------------------------------------------------------------------------------ applause gloves
def gloveGeometry(mirror=False):
    """Applause hands (step 3): a lightweight white cartoon glove after props/machines.js buildGlove. Origin = wrist
    (top of the cuff), fingers +Y, palm -Z, thumb +X, three seams on the back (+Z). One non-indexed geometry with
    position, normal and colour; mirror = the other hand (x flipped, winding restored)."""
    W, SEAM, CUFF = '#FFFDF6', '#C4B59B', '#F3ECDD'
    parts = []

    def put(geo, color, m=None):
        g = geo.toNonIndexed() if geo.index is not None else geo.clone()
        if m is not None:
            g.applyMatrix4(m)
        for k in list(g.attributes.keys()):
            if k != 'position' and k != 'normal':
                g.deleteAttribute(k)
        K.tint(g, color)
        parts.append(g)

    def at(x, y, z, rx=0, ry=0, rz=0):
        return THREE.Matrix4().compose(THREE.Vector3(x, y, z), THREE.Quaternion().setFromEuler(THREE.Euler(rx, ry, rz)), THREE.Vector3(1, 1, 1))

    def ring(r, n, y):
        pts = []
        for i in range(n):
            a = (i / n) * TAU
            pts.append([math.cos(a) * r, y, math.sin(a) * r])
        return pts
    # cuff: flared bell, rolled lip, wrist band
    put(K.lathe([[0.058, 0.0], [0.062, -0.03], [0.073, -0.062], [0.085, -0.088]], {'seg': 16}), CUFF)
    put(K.tube(ring(0.084, 14, -0.088), 0.012, {'seg': 16, 'radial': 5, 'closed': True}), W)
    put(K.tube(ring(0.059, 12, 0.0), 0.01, {'seg': 14, 'radial': 4, 'closed': True}), W)
    # puffy palm + the three stitch lines on its back
    palm = THREE.SphereGeometry(1, 13, 9)
    palm.scale(0.088, 0.098, 0.056)
    palm.translate(0, 0.088, 0)
    put(palm, W)
    for x in [-0.034, 0, 0.034]:
        pts = []
        for i in range(7):
            y = 0.035 + i * 0.017
            nx, ny = x / 0.088, (y - 0.088) / 0.098
            pts.append([x, y, 0.056 * math.sqrt(max(0.02, 1 - nx * nx - ny * ny)) + 0.002])
        put(K.tube(pts, 0.0045, {'seg': 5, 'radial': 3}), SEAM)
    # fat sausage fingers from the knuckles (a little curled) + the thumb
    for x, ln, fan in [[0.05, 0.078, -0.16], [0.0, 0.088, 0.0], [-0.05, 0.07, 0.17]]:
        cap = THREE.CapsuleGeometry(0.031, ln, 3, 9)
        cap.translate(0, ln / 2 + 0.012, 0)
        p = cap.attributes.position
        for i in range(p.count):
            k = 1 + 0.1 * math.sin(clamp01(p.getY(i) / (ln + 0.04)) * PI)
            p.setX(i, p.getX(i) * k)
            p.setZ(i, p.getZ(i) * k)
        cap.computeVertexNormals()
        put(cap, W, at(x, 0.155, 0, -0.12, 0, fan))
    th = THREE.CapsuleGeometry(0.033, 0.058, 3, 9)
    th.translate(0, 0.045, 0)
    put(th, W, at(0.07, 0.07, -0.018, -0.35, 0.2, -0.95))
    g = mergeGeometries(parts, False)
    if mirror:
        g.scale(-1, 1, 1)
        for a in g.attributes.values():
            n = a.itemSize
            arr = np.asarray(a).reshape(-1, n)
            tri = arr[: (a.count // 3) * 3].reshape(-1, 3, n)
            tri[:, [1, 2], :] = tri[:, [2, 1], :]
            a[: (a.count // 3) * 3] = tri.reshape(-1, n)
    g.computeBoundingSphere()
    return g


def buildGloves(game):
    """The two applause-glove geometries as meshes (the JS InstancedMeshes' geometry; material built at runtime)."""
    root = THREE.Group()
    root.name = 'ee_applause_glove'
    mat = game.mats.toon('#ffffff', {'keepColor': True, 'vertexColors': True, 'rough': 0.55, 'rim': 0.5, 'rimColor': '#FFF1D8', 'rimPower': 2.0, 'wrap': 0.7, 'transparent': True})
    for mirror in (False, True):
        m = THREE.Mesh(gloveGeometry(mirror), mat)
        m.name = 'ee_applause_glove_r' if mirror else 'ee_applause_glove_l'
        m.castShadow = False
        m.receiveShadow = False
        m.userData.noMerge = True
        root.add(m)
    return root


# ------------------------------------------------------------------------------------------------ export
def _assets():
    game = K.Game()
    return {
        'ee_puppet_dudley': lambda: buildDudley(game),
        'ee_puppet_sockrates': lambda: buildSockrates(game),
        'ee_puppet_hootie': lambda: buildHootie(game),
        'ee_confetti_cannon': lambda: buildCannon(game),
        'ee_stray_storm': lambda: buildStorm(game)['root'],
        'ee_applause_glove': lambda: buildGloves(game),
    }


def build(save_blend=False, only=None):
    """Builds every easter-egg runtime asset into godot/assets/runtime/easteregg/. Returns the written paths."""
    from dalib import export as EX
    written = []
    for name, make in _assets().items():
        if only and name not in only:
            continue
        root = make()
        path = os.path.join(OUT_DIR, name + '.glb')
        blend = os.path.join(BLEND_DIR, name + '.blend') if save_blend else None
        EX.export_graph(root, path, root_name=root.name, save_blend=blend)
        written.append(path)
        print('[runtime/easteregg] %s' % path)
    return written


if __name__ == '__main__':
    args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
    only = None
    if '--only' in args:
        only = args[args.index('--only') + 1].split(',')
    build(save_blend='--save-blend' in args, only=only)
