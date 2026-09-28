"""DEAD AIR — kit sample props (reference quality bar for the prop artists; docs/PROPKIT.md).
Port of src/props/_samples.js — THE worked example every prop port imitates (see blender/README.md, kit guide).

  sample_floor_lamp   70s teak tripod floor lamp: pleated burnt-orange drum shade, brass hardware, lit bulb
  sample_portable_tv  1970s portable CRT: harvest-orange ABS shell, cream face, dials, grille, rabbit ears
  sample_side_table   teak cube side table with a walnut-burl top inlay (set-dressing helper)
Scene 'samples' (tools/propview): the three on shag against wood paneling.

Porting rules shown here (JS -> Python):
  * `import * as K from './kit.js'` -> `from dalib import kit as K`; `{ registerProp, PAL, THREE }` the same names.
  * JS object literals -> dicts with the SAME keys and order ({ bevel: 0.008, seg: 12 } -> {'bevel': 0.008, 'seg': 12}).
  * three.js API calls stay as they are (THREE.Vector3, .position.copy(), .quaternion.setFromUnitVectors ...):
    the kit graph and dalib.mathutils3 mirror three.js, in three.js coordinates (never think in Blender axes).
  * `a ?? b` -> `x if x is not None else b` (or opts.get(k, b) when the key is simply absent).
  * Arrow builders -> nested def (closures over the same variables).
"""
import math

from dalib import kit as K
from dalib.kit import registerProp, registerScene, PAL, THREE


# ------------------------------------------------------------------------------------------ floor lamp
def _floor_lamp(game, opts=None):
    g = K.prop('sample_floor_lamp')
    teak = K.mat(game, 'teak', '#ffffff', {'map': K.tex.wood(PAL.teak, {'dark': 0.38})})
    brass = K.mat(game, 'brass', '#C8963C')
    # emissive = fake translucency of a lit linen shade
    shadeMat = K.mat(game, 'fabric', '#ffffff', {'map': K.tex.weave(PAL.burntOrange, {'pattern': 'plain', 'scale': 3}),
                                                 'side': THREE.DoubleSide, 'emissive': '#FF7A30',
                                                 'emissiveIntensity': 0.28})
    lining = K.glow(game, '#FFD9A0', 1.15)
    bulb = K.glow(game, PAL.tungsten, 4)

    # tripod: three tapered teak legs splayed from a brass collar
    collarY, footR = 0.6, 0.27
    for i in range(3):
        a = (i / 3) * math.pi * 2 + math.pi / 6
        foot = THREE.Vector3(math.sin(a) * footR, 0.02, math.cos(a) * footR)
        top = THREE.Vector3(math.sin(a) * 0.035, collarY, math.cos(a) * 0.035)
        ln = foot.distanceTo(top)
        leg = K.m(K.uvScale(K.cyl(0.027, 0.016, ln, {'bevel': 0.008, 'seg': 12}).clone(), 1, 3), teak)
        leg.position.copy(foot)
        leg.quaternion.setFromUnitVectors(THREE.Vector3(0, 1, 0), top.clone().sub(foot).normalize())
        g.add(leg)
        cap = K.m(K.cyl(0.018, 0.02, 0.03, {'bevel': 0.006, 'seg': 10}), brass)
        cap.position.copy(foot).setY(0)
        g.add(cap)
    g.add(K.m(K.lathe([[0, 0], [0.066, 0], [0.072, 0.035], [0.056, 0.08], [0.03, 0.115], [0, 0.115]],
                      {'round': 0.014, 'seg': 16}), brass, {'pos': [0, collarY - 0.06, 0]}))
    # pole with a knurled coupling
    g.add(K.m(K.cyl(0.016, 0.016, 0.72, {'bevel': 0.004, 'seg': 12}), brass, {'pos': [0, collarY + 0.04, 0]}))
    g.add(K.m(K.lathe([[0, 0], [0.028, 0], [0.034, 0.018], [0.034, 0.042], [0.028, 0.06], [0, 0.06]],
                      {'round': 0.008, 'seg': 14, 'steps': 1}), brass, {'pos': [0, 0.98, 0]}))
    # socket + bulb
    bulbY = 1.43
    g.add(K.m(K.lathe([[0, 0], [0.022, 0], [0.026, 0.02], [0.026, 0.06], [0.018, 0.075], [0, 0.075]],
                      {'round': 0.006, 'seg': 14, 'steps': 1}), brass, {'pos': [0, bulbY - 0.13, 0]}))
    g.add(K.m(K.lathe([[0, 0], [0.018, 0.005], [0.04, 0.045], [0.045, 0.075], [0.03, 0.11], [0, 0.12]],
                      {'round': 0.01, 'seg': 14}), bulb, {'pos': [0, bulbY - 0.06, 0], 'cast': False}))

    # pleated drum shade (lathe + radial pleat displacement), glowing lining, piped rims
    y0, y1, rb, rt = 1.28, 1.68, 0.3, 0.22

    def pleat(geo, amp):
        gg = geo.clone()
        p = gg.attributes.position
        for i in range(p.count):
            x, z = p.getX(i), p.getZ(i)
            th = math.atan2(z, x)
            k = 1 + amp * abs(math.cos(th * 14))
            p.setX(i, x * k)
            p.setZ(i, z * k)
        gg.computeVertexNormals()
        return gg
    shell = THREE.LatheGeometry([THREE.Vector2(rb, 0), THREE.Vector2((rb + rt) / 2 + 0.006, (y1 - y0) / 2),
                                 THREE.Vector2(rt, y1 - y0)], 84)
    g.add(K.m(K.uvScale(pleat(shell, 0.05), 10, 1.4), shadeMat, {'pos': [0, y0, 0], 'name': 'shade'}))
    lin = THREE.LatheGeometry([THREE.Vector2(rt - 0.006, y1 - y0 - 0.004), THREE.Vector2(rb - 0.006, 0.004)], 36)
    linMesh = K.m(lin, lining, {'pos': [0, y0, 0], 'cast': False})
    g.add(linMesh)
    rimMat = K.mat(game, 'fabric', '#9E3D17')
    g.add(K.m(K.tube(ring(rb * 1.035, 28), 0.013, {'seg': 40, 'radial': 6, 'closed': True}), rimMat,
              {'pos': [0, y0, 0]}))
    g.add(K.m(K.tube(ring(rt * 1.035, 28), 0.011, {'seg': 36, 'radial': 6, 'closed': True}), rimMat,
              {'pos': [0, y1, 0]}))
    # spider (harp) arms to the top ring + finial
    for i in range(3):
        a = (i / 3) * math.pi * 2
        g.add(K.m(K.tube([[0, bulbY + 0.12, 0], [math.sin(a) * rt * 0.6, y1 - 0.01, math.cos(a) * rt * 0.6],
                          [math.sin(a) * rt, y1, math.cos(a) * rt]], 0.005, {'seg': 8, 'radial': 5}), brass))
    g.add(K.m(K.lathe([[0, 0], [0.012, 0], [0.02, 0.018], [0.014, 0.034], [0, 0.04]],
                      {'round': 0.006, 'seg': 12, 'steps': 1}), brass, {'pos': [0, bulbY + 0.12, 0]}))
    # pull chain
    g.add(K.m(K.tube([[0.03, bulbY - 0.09, 0], [0.034, bulbY - 0.2, -0.01]], 0.002, {'seg': 4, 'radial': 4}), brass))
    g.add(K.m(K.cyl(0.006, 0.006, 0.018, {'bevel': 0.003, 'seg': 8}), brass, {'pos': [0.034, bulbY - 0.22, -0.01]}))

    # small fixture: pooled lights cast no shadows
    g.userData.lightAnchors = [{'pos': [0, bulbY - 0.05, 0], 'color': PAL.tungsten, 'intensity': 1.8,
                                'distance': 4.5}]
    g.userData.colliders = [{'min': [-0.2, 0, -0.2], 'max': [0.2, 1.68, 0.2]}]
    linMesh.userData.noOcclude = True
    return K.finish(game, g)


registerProp('sample_floor_lamp', _floor_lamp,
             {'category': 'samples', 'tags': ['lamp', 'light', 'living'], 'size': [0.56, 1.7, 0.56],
              'desc': '70s teak tripod floor lamp'})


def ring(r, n):
    pts = []
    for i in range(n):
        a = (i / n) * math.pi * 2
        pts.append([math.cos(a) * r, 0, math.sin(a) * r])
    return pts


# ------------------------------------------------------------------------------------------ portable TV
def _portable_tv(game, opts=None):
    opts = opts or {}
    g = K.prop('sample_portable_tv')
    shellColor = opts.get('color') if opts.get('color') is not None else PAL.harvestGold
    shell = K.mat(game, 'plastic', shellColor)
    face = K.mat(game, 'plastic', PAL.cream)
    dark = K.mat(game, 'plastic', '#2A2230')
    chrome = K.mat(game, 'chrome', '#A8B0BA')
    rubber = dark

    W, H, D, footH = 0.48, 0.36, 0.3, 0.022
    cy = footH + H / 2
    # shell: chunky front block + tapered rear housing (the tube's neck)
    g.add(K.m(K.box(W, H, D, 0.07), shell, {'pos': [0, cy, 0]}))
    g.add(K.m(K.taper(K.box(W * 0.86, H * 0.84, 0.2, 0.065), {'axis': 'z', 'k': 0.55, 'ease': 0.8}), shell,
              {'pos': [0, cy + 0.004, D / 2 + 0.08]}))
    # vent slots on the back housing
    for i in range(4):
        g.add(K.m(K.box(0.014, 0.09, 0.012, 0.005), dark, {'pos': [-0.045 + i * 0.03, cy + 0.01, D / 2 + 0.18]}))
    # cream face plate
    fz = -D / 2
    g.add(K.m(K.box(W - 0.03, H - 0.03, 0.02, 0.035), face, {'pos': [0, cy, fz - 0.002]}))
    # screen bezel: extruded frame with a rounded hole, sunk into the face
    sx, sw, sh = -0.058, 0.3, 0.245
    outer = K.roundRect(sw + 0.04, sh + 0.04, 0.05)
    outer.holes.append(THREE.Path(K.roundRect(sw, sh, 0.035).getPoints(8)))
    g.add(K.m(K.extrude(outer, 0.03, {'bevel': 0.008, 'bevelSeg': 1, 'curveSeg': 6}), dark,
              {'pos': [sx, cy + 0.005, fz - 0.012]}))
    scr = K.screen(game, sw, sh, {'card': opts.get('card') or 'show_4', 'group': opts.get('group') or 'scr_decor',
                                  'dome': 0.014})
    scr.position.set(sx, cy + 0.005, fz - 0.004)
    g.add(scr)
    # control column: two channel dials with printed faces, knobs, a grille and a nameplate
    cx = 0.165

    # one atlas for both dial faces + the speaker grille (fewer materials): [VHF | UHF | grille], 768x256
    def draw_atlas(ctx, w_, h_, rand):
        for c, (label, n0, n1) in enumerate([['VHF', 2, 13], ['UHF', 14, 25]]):
            ox, w = c * 256, 256
            ctx.fillStyle = PAL.capWhite
            ctx.beginPath()
            ctx.arc(ox + w / 2, w / 2, w / 2, 0, 7)
            ctx.fill()
            ctx.fillStyle = '#2A2230'
            ctx.textAlign = 'center'
            ctx.textBaseline = 'middle'
            ctx.font = '26px "Titan One", "Arial Black", sans-serif'
            count = n1 - n0 + 1
            for i in range(count):
                a = -math.pi * 0.8 + (i / (count - 1)) * math.pi * 1.6
                ctx.fillText(str(n0 + i), ox + w / 2 + math.sin(a) * w * 0.38, w / 2 - math.cos(a) * w * 0.38)
            ctx.fillStyle = PAL.channelRed
            ctx.font = '22px "Bungee", "Arial Black", sans-serif'
            ctx.fillText(label, ox + w / 2, w * 0.86)
        ctx.fillStyle = '#3A3040'
        ctx.fillRect(512, 0, 256, 256)
        for y in range(9):
            for x in range(9):
                ctx.fillStyle = '#120C16'
                ctx.beginPath()
                ctx.arc(512 + 20 + x * 27, 20 + y * 27, 8, 0, 7)
                ctx.fill()
                ctx.fillStyle = 'rgba(255,255,255,0.12)'
                ctx.beginPath()
                ctx.arc(512 + 20 + x * 27, 22 + y * 27, 8, 0.2, 2.9)
                ctx.fill()
    atlas = K.tex.canvas('sample_tv_atlas', 768, 256, draw_atlas, {'repeat': False, 'fonts': True})
    atlasMat = K.mat(game, 'plastic', '#ffffff', {'map': atlas})
    knob = K.lathe([[0, 0], [0.034, 0], [0.036, 0.01], [0.03, 0.03], [0.026, 0.036], [0, 0.036]],
                   {'round': 0.006, 'seg': 14, 'steps': 1})
    parts = {}
    for i, (label, n0, n1, dy) in enumerate([['VHF', 2, 13, 0.07], ['UHF', 14, 25, -0.02]]):
        disc = K.m(K.uvRect(THREE.CircleGeometry(0.045, 28), i / 3, 0, (i + 1) / 3, 1), atlasMat,
                   {'pos': [cx, cy + dy, fz - 0.0135], 'rot': [0, math.pi, 0]})
        g.add(disc)
        k = THREE.Group()
        k.position.set(cx, cy + dy, fz - 0.013)
        k.userData.noMerge = True
        body = K.m(knob, chrome if i else dark, {'rot': [-math.pi / 2, 0, 0]})
        ptr = K.m(K.box(0.008, 0.028, 0.008, 0.003), dark if i else face, {'pos': [0, 0.012, -0.036]})
        k.add(body, ptr)
        k.rotation.z = -0.6 if i else 0.9
        g.add(k)
        parts['dialUHF' if i else 'dialVHF'] = k
    g.add(K.m(K.uvRect(K.box(0.08, 0.07, 0.01, 0.005).clone(), 2 / 3, 0, 1, 1), atlasMat,
              {'pos': [cx, cy - 0.105, fz - 0.011]}))
    plate = K.mat(game, 'metal', '#ffffff', {'map': K.tex.label('VISTRONIC  ·  SOLID STATE', {
        'bg': '#E8E4DA', 'fg': '#2A2230', 'accent': '#B9BEC6', 'w': 512, 'h': 64, 'border': 0.1, 'wear': 0.1})})
    g.add(K.m(K.box(0.19, 0.021, 0.006, 0.003), plate, {'pos': [sx, cy - 0.152, fz - 0.014]}))
    # power button + indicator
    g.add(K.m(K.box(0.03, 0.018, 0.014, 0.005), dark, {'pos': [cx, cy + 0.14, fz - 0.013]}))
    g.add(K.m(K.cyl(0.005, 0.005, 0.006, {'bevel': 0.002, 'seg': 10}), K.glow(game, PAL.onAirRed, 3),
              {'pos': [cx + 0.03, cy + 0.14, fz - 0.009], 'rot': [-math.pi / 2, 0, 0]}))
    # carry handle: chrome bail with black grip on pivot bosses
    top = footH + H
    hx = W / 2 + 0.013
    for s in (-1, 1):
        g.add(K.m(K.cyl(0.024, 0.026, 0.018, {'bevel': 0.006, 'seg': 12}), dark,
                  {'pos': [s * (W / 2 - 0.004), top - 0.06, 0], 'rot': [0, 0, -s * math.pi / 2]}))
    g.add(K.m(K.tube([[-hx, top - 0.06, 0], [-hx, top + 0.01, -0.004], [-W / 2 + 0.03, top + 0.07, -0.012],
                      [-0.12, top + 0.085, -0.015], [0.12, top + 0.085, -0.015], [W / 2 - 0.03, top + 0.07, -0.012],
                      [hx, top + 0.01, -0.004], [hx, top - 0.06, 0]], 0.009, {'seg': 32, 'radial': 6}), chrome))
    g.add(K.m(K.tube([[-0.1, top + 0.085, -0.015], [0.1, top + 0.085, -0.015]], 0.016, {'seg': 4, 'radial': 10}),
              rubber))
    # rabbit ears: swivel ball + telescoping chrome rods with ball tips
    ax, ay, az = 0.02, top + 0.005, 0.1
    g.add(K.m(K.lathe([[0, 0], [0.04, 0], [0.042, 0.012], [0.02, 0.03], [0, 0.034]],
                      {'round': 0.008, 'seg': 14, 'steps': 1}), dark, {'pos': [ax, ay - 0.01, az]}))
    ant = THREE.Group()
    ant.position.set(ax, ay + 0.02, az)
    ant.userData.noMerge = True
    for s in (-1, 1):
        dr = THREE.Vector3(s * 0.55, 1, 0.22).normalize()
        segs = [[0.0055, 0.2], [0.0042, 0.18], [0.003, 0.16]]
        dpos = 0.0
        for r, ln in segs:
            rod = K.m(K.cyl(r, r, ln, {'bevel': 0.0015, 'seg': 6}), chrome)
            rod.position.copy(dr).multiplyScalar(dpos)
            rod.quaternion.setFromUnitVectors(THREE.Vector3(0, 1, 0), dr)
            ant.add(rod)
            dpos += ln - 0.01
        ant.add(K.m(G_SPHERE(0.009), chrome, {'pos': dr.clone().multiplyScalar(dpos + 0.005).toArray()}))
    g.add(ant)
    parts['antenna'] = ant
    # rubber feet
    for x, z in [[-1, -1], [1, -1], [-1, 1], [1, 1]]:
        g.add(K.m(K.cyl(0.022, 0.026, footH, {'bevel': 0.005, 'seg': 10}), rubber,
                  {'pos': [x * (W / 2 - 0.06), 0, z * (D / 2 - 0.05)]}))

    g.userData.parts = parts
    g.userData.colliders = [{'min': [-W / 2, 0, -D / 2 - 0.02], 'max': [W / 2, top + 0.08, D / 2 + 0.17]}]
    g.userData.interact = {'point': [0, cy, fz - 0.05], 'radius': 1.2}
    return K.finish(game, g)


registerProp('sample_portable_tv', _portable_tv,
             {'category': 'samples', 'tags': ['tv', 'crt', 'screen', 'living'], 'size': [0.48, 0.46, 0.5],
              'desc': '1970s portable CRT television', 'hero': True})


def G_SPHERE(r):
    return THREE.SphereGeometry(r, 10, 6)


# ------------------------------------------------------------------------------------------ side table
def _side_table(game, opts=None):
    g = K.prop('sample_side_table')
    teak = K.mat(game, 'lacquer', '#ffffff', {'map': K.tex.wood(PAL.teak, {'dark': 0.35})})
    burl = K.mat(game, 'lacquer', '#ffffff', {'map': K.tex.burl(PAL.walnut)})
    S, Hh = 0.56, 0.5
    g.add(K.m(K.box(S, 0.05, S, 0.02, {'uv': 1.6}), teak, {'pos': [0, Hh - 0.025, 0]}))
    g.add(K.m(K.box(S - 0.1, 0.006, S - 0.1, 0.003, {'uv': 1.5}), burl, {'pos': [0, Hh + 0.001, 0]}))
    g.add(K.m(K.box(S - 0.06, 0.03, S - 0.06, 0.012, {'uv': 1.6}), teak, {'pos': [0, 0.16, 0]}))
    for x, z in [[-1, -1], [1, -1], [-1, 1], [1, 1]]:
        g.add(K.m(K.box(0.05, Hh - 0.05, 0.05, 0.014, {'uv': 1.6, 'swap': True}), teak,
                  {'pos': [x * (S / 2 - 0.035), (Hh - 0.05) / 2, z * (S / 2 - 0.035)]}))
    return K.finish(game, g)


registerProp('sample_side_table', _side_table,
             {'category': 'samples', 'tags': ['table', 'living'], 'size': [0.56, 0.5, 0.56],
              'desc': 'teak cube side table, burl inlay'})

registerScene('samples', {
    'floor': 'shag', 'wall': 'panel', 'room': [4.4, 3.4],
    'items': [
        {'id': 'sample_floor_lamp', 'pos': [-1.0, 0.6], 'rotY': 0.3},
        {'id': 'sample_side_table', 'pos': [0.15, 0.55], 'rotY': 0},
        {'id': 'sample_portable_tv', 'pos': [0.15, 0.5, 0.52], 'rotY': -0.25},
        {'id': 'sample_portable_tv', 'pos': [1.25, 0.9], 'rotY': -0.7, 'opts': {'color': PAL.avocado,
                                                                                 'card': 'station_id'}},
    ],
    'cam': {'pos': [0.6, 1.45, -2.6], 'target': [0, 0.6, 0.7], 'fov': 50},
})
