"""DEAD AIR — props: 70s FURNITURE & DECOR (docs/PROPKIT.md). Owner: furniture prop artist.
Port of src/props/furniture.js (line by line: same builders, numbers, textures, seeds; see blender/README.md).
Every builder registers with registerProp(id, build, { category: 'furniture', ... }).

PLACEMENT CONVENTIONS used in this file (see also each prop's meta.desc / tags):
  floor props   : kit default. Floor at y = 0, centered on x/z, FRONT (the side people use / sit facing) = -z.
  'wall' tag    : origin = the point ON THE WALL under the prop's BOTTOM edge (back face at z = 0, prop extends
                  toward -z into the room, centered on x). Place with pos = [x, bottomHeight, z-on-wall] and rotY so
                  local -z points into the room. meta.desc gives a suggested bottom height. Colliders are [] (the
                  wall already blocks) unless the prop sticks out > 0.15 m.
  'ceiling' tag : origin = the attach point on the ceiling, prop hangs toward -y. Place with pos.y = ceiling height.
                  Colliders are [] (out of reach).
  'tabletop' tag: small props that sit on furniture (y = 0 is their base; put pos.y = the surface height).
  Light fixtures carry lightAnchors and expose their glowing mesh as userData.parts.glow (noMerge) so rooms can
  swap its material when the power is off (opts.lit = false builds it unlit).
Colors: most parts use a few neutral-textured materials and get their color from vertex tints (tc()), so a
prop stays at 2-5 materials; the AO bake multiplies on top.

PROPS (46): seating  sofa_cloud* couch_avocado* couch_talkshow* armchair_barrel chair_ball bean_bag chair_office
            desks    desk_reporter* desk_reception* desk_anchor* typewriter phone_rotary
            tables   table_coffee table_side_tulip table_side_drum
            lamps    lamp_arc lamp_tripod lamp_pole lamp_lava lamp_globe_pendant(ceiling) light_fluoro_panel(ceiling)
                     light_can(ceiling)
            plants   plant_rubber plant_fern plant_snake macrame_hanger(ceiling)
            misc     water_cooler filing_cabinet coat_rack trash_can ash_urn vending_soda* vending_cigarette* bookshelf
            wall     payphone_rotary clock_wall clock_sunburst cork_board frame_picture trophy_shelf macrame_owl
                     trim_baseboard trim_chair_rail trim_crown
            floor    rug_shag_round rug_shag_oval                                            (* = hero budget)
Scenes (propview): furn_lobby, furn_newsroom, furn_green (set-dressing references), furn_ceiling (ceiling fixtures:
they hang below y = 0 so the category sheet shows them as empty cells; review them in this scene).
Shared building blocks here: cbox (44-tri chamfer box), channelShell (continuous channel tufting), arcSlab /
arcColliders (curved desks), potGroup, phoneGroup / typewriterGroup / paperStack / mugGroup (desk dressing),
deskAtlas() + decorAtlas() (4x4 printed-detail atlases, cell()/dcell() map a 0..1-UV geometry into a cell).

JS -> Python notes: `a ?? b` -> _nn(a, b); `x.toFixed(3)` -> js_to_fixed; JS `%` -> math.fmod; the module-level
geometry cache `_geo` / cg() is kept (shared geometries are cloned before tinting exactly like the JS).
drawCard(): three draws the gfx card canvas into the desk atlas; here the pre-rendered card PNG is drawn with
K.drawTo (blender/dalib/cards/<id>.png); when it is missing the base colour stays, like the JS catch branch.
"""
import math

import numpy as np

from dalib import kit as K
from dalib.kit import registerProp, registerScene, PAL, THREE, getCard, cardInfo
from dalib.mathutils3 import js_str, js_round, js_sign, js_to_fixed, JSObj
from dalib.rng import mulberry32

lerp, clamp = THREE.MathUtils.lerp, THREE.MathUtils.clamp
UP = THREE.Vector3(0, 1, 0)
TAU = math.pi * 2
CAT = 'furniture'


def _nn(v, d):
    """JS `v ?? d`."""
    return d if v is None else v


# =================================================================================================== helpers
_geo = {}


def cg(key, make):
    g = _geo.get(key)
    if g is None:
        g = make()
        _geo[key] = g
    return g


# tinted copy (kit geometries are cached/shared: always clone before tinting)
def tc(geo, color):
    return K.tint(geo.clone(), color)


def v3(a):
    return THREE.Vector3(a[0], a[1], a[2])


def sph(r, ws=14, hs=10):
    return cg('sph|%s|%s|%s' % (js_str(r), js_str(ws), js_str(hs)), lambda: THREE.SphereGeometry(r, ws, hs))


# mesh placed at a with its local +y pointing at b (for cyl/lathe geometry that grows along +y from y = 0)
def span(geo, mat, a, b):
    A, B = v3(a), v3(b)
    msh = K.m(geo, mat)
    msh.position.copy(A)
    msh.quaternion.setFromUnitVectors(UP, B.sub(A).normalize())
    return msh


# bevelled rod from a to b (rb = radius at a, r = radius at b)
def rod(r, a, b, mat, o=None):
    o = o or {}
    ln = v3(a).distanceTo(v3(b))
    g = K.cyl(r, _nn(o.get('rb'), r), ln, {'seg': _nn(o.get('seg'), 10), 'bevel': _nn(o.get('bevel'), min(0.004, r * 0.4))})
    return span(tc(g, o['color']) if o.get('color') else g, mat, a, b)


# 44-tri chamfered box (books, papers, keys, slats): flat bevels read as soft edges at small sizes. UVs 0..1 per
# face; the -z face reads left->right from the front (spines, labels).
def cbox(w, h, d, c=0.004):
    def make():
        hx, hy, hz = w / 2, h / 2, d / 2
        cc = min(c, hx * 0.45, hy * 0.45, hz * 0.45)
        pts = []
        for sx in (-1, 1):
            for sy in (-1, 1):
                for sz in (-1, 1):
                    pts.extend([THREE.Vector3(sx * hx, sy * (hy - cc), sz * (hz - cc)),
                                THREE.Vector3(sx * (hx - cc), sy * hy, sz * (hz - cc)),
                                THREE.Vector3(sx * (hx - cc), sy * (hy - cc), sz * hz)])
        g = THREE.ConvexGeometry(pts)
        p, n = g.attributes.position, g.attributes.normal
        uv = np.zeros((p.count, 2))
        for i in range(p.count):
            ax, ay, az = abs(n.getX(i)), abs(n.getY(i)), abs(n.getZ(i))
            x, y, z = p.getX(i) / w + 0.5, p.getY(i) / h + 0.5, p.getZ(i) / d + 0.5
            if az >= ax and az >= ay:
                u = 1 - x if n.getZ(i) < 0 else x
                v = y
            elif ax >= ay:
                u = 1 - z if n.getX(i) > 0 else z
                v = y
            else:
                u = x
                v = 1 - z if n.getY(i) > 0 else z
            uv[i, 0] = u
            uv[i, 1] = v
        g.setAttribute('uv', THREE.BufferAttribute(uv, 2))
        return g
    return cg('cbox|%s|%s|%s|%s' % (js_str(w), js_str(h), js_str(d), js_str(c)), make)


# taper + welded normals (K.taper recomputes flat normals on the non-indexed rounded box)
def taperS(geo, o):
    return K.weldNormals(K.taper(geo, o))


# wall props: shift children so the bbox bottom sits at y = 0 and the back at z = 0. Returns [dy, dz].
def wallFit(g):
    g.updateMatrixWorld(True)
    bb = THREE.Box3().setFromObject(g)
    dy, dz = -bb.min.y, -bb.max.z
    for c in g.children:
        c.position.y += dy
        c.position.z += dz
    return [dy, dz]


def ring(r, n, y=0, a0=0, a1=TAU, closed=True):
    pts = []
    cnt = n if closed else n + 1
    for i in range(cnt):
        a = a0 + (i / n) * (a1 - a0)
        pts.append([math.sin(a) * r, y, math.cos(a) * r])
    return pts


# flat disc/puck with rounded edge (lathe), base at y = 0
def puck(r, h, round_=0.02, seg=24):
    return K.lathe([[0, 0], [r, 0], [r, h], [0, h]], {'round': min(round_, h / 2 - 1e-3, r / 2), 'seg': seg, 'steps': 2})


# removes triangles whose centroid satisfies cut(x,y,z) (indexed geometry in, indexed out)
def cutTris(geo, cut):
    g = geo.clone()
    idx, p = g.index.array, g.attributes.position
    keep = []
    for t in range(0, len(idx), 3):
        a, b, c = int(idx[t]), int(idx[t + 1]), int(idx[t + 2])
        x = (p.getX(a) + p.getX(b) + p.getX(c)) / 3
        y = (p.getY(a) + p.getY(b) + p.getY(c)) / 3
        z = (p.getZ(a) + p.getZ(b) + p.getZ(c)) / 3
        if not cut(x, y, z):
            keep.extend([a, b, c])
    g.setIndex(keep)
    return g


def flipGeo(geo):
    g = geo.clone()
    idx = g.index.array
    t = np.array(idx[1::3])
    idx[1::3] = idx[2::3]
    idx[2::3] = t
    n = g.attributes.normal
    n[:, :] = -np.asarray(n, dtype=np.float64)
    return g


# ------------------------------------------------------------------------------------------------ textures
def ctxRR(ctx, x, y, w, h, r):
    ctx.beginPath()
    ctx.roundRect(x, y, w, h, r)


# 70s fabric patterns atlas (2x2): 0 flower power, 1 concentric circles, 2 racing stripes, 3 avocado ogee.
def patternTex():
    def draw(ctx, W, H, rand):
        S = 256
        # 0: flower power (top-left)
        ctx.save()
        ctx.beginPath()
        ctx.rect(0, 0, S, S)
        ctx.clip()
        ctx.fillStyle = '#E8A92E'
        ctx.fillRect(0, 0, S, S)

        def flower(x, y, r, c, cc):
            ctx.fillStyle = c
            for i in range(5):
                a = i / 5 * TAU
                ctx.beginPath()
                ctx.ellipse(x + math.cos(a) * r * 0.55, y + math.sin(a) * r * 0.55, r * 0.5, r * 0.34, a, 0, TAU)
                ctx.fill()
            ctx.fillStyle = cc
            ctx.beginPath()
            ctx.arc(x, y, r * 0.3, 0, TAU)
            ctx.fill()
        for i in range(9):
            flower((i % 3) * 90 + 40 + ((i // 3) % 2) * 40, (i // 3) * 90 + 40, 30,
                   '#F6E7C8' if i % 2 else '#E3662B', '#E3662B' if i % 2 else '#5A3A22')
        ctx.restore()
        # 1: concentric circles (top-right)
        ctx.save()
        ctx.translate(S, 0)
        ctx.beginPath()
        ctx.rect(0, 0, S, S)
        ctx.clip()
        ctx.fillStyle = '#5A3A22'
        ctx.fillRect(0, 0, S, S)
        for cx, cy in [[64, 64], [192, 64], [64, 192], [192, 192]]:
            for i, c in enumerate(['#E3662B', '#E8A92E', '#F6E7C8', '#B5472A', '#5A3A22']):
                ctx.fillStyle = c
                ctx.beginPath()
                ctx.arc(cx, cy, 58 - i * 11, 0, TAU)
                ctx.fill()
        ctx.restore()
        # 2: racing stripes (bottom-left)
        ctx.save()
        ctx.translate(0, S)
        ctx.beginPath()
        ctx.rect(0, 0, S, S)
        ctx.clip()
        ctx.fillStyle = '#F6E7C8'
        ctx.fillRect(0, 0, S, S)
        for i, c in enumerate(['#5A3A22', '#B5472A', '#E3662B', '#E8A92E']):
            ctx.fillStyle = c
            ctx.fillRect(0, 70 + i * 30, S, 24)
        ctx.restore()
        # 3: avocado ogee (bottom-right)
        ctx.save()
        ctx.translate(S, S)
        ctx.beginPath()
        ctx.rect(0, 0, S, S)
        ctx.clip()
        ctx.fillStyle = '#8C9A3A'
        ctx.fillRect(0, 0, S, S)
        ctx.strokeStyle = '#F6E7C8'
        ctx.lineWidth = 7
        y = -64
        while y < S + 64:
            x = 0
            while x < S + 64:
                ctx.beginPath()
                ctx.ellipse(x + (32 if math.fmod(y / 64, 2) else 0), y, 30, 30, 0, 0, TAU)
                ctx.stroke()
                x += 64
            y += 64
        ctx.fillStyle = '#5A3A22'
        for y in range(0, S, 64):
            for x in range(0, S, 64):
                ctx.beginPath()
                ctx.arc(x + 32, y + 32, 6, 0, TAU)
                ctx.fill()
        ctx.restore()
    return K.tex.canvas('furn_patterns', 512, 512, draw, {'repeat': False})


PAT = {'flower': [0, 0.5, 0.5, 1], 'circles': [0.5, 0.5, 1, 1], 'stripes': [0, 0, 0.5, 0.5], 'ogee': [0.5, 0, 1, 0.5]}


def patUV(geo, key):
    u0, v0, u1, v1 = PAT[key]
    return K.uvRect(geo.clone(), u0, v0, u1, v1)


# neutral (light) fabric/vinyl/wood textures: color comes from vertex tints
NEUTRAL = '#EDE6DA'


def M(game):
    return JSObj(
        plastic=K.mat(game, 'plastic', '#ffffff'),
        lacquer=K.mat(game, 'lacquer', '#ffffff'),
        paint=K.mat(game, 'paint', '#ffffff'),
        metal=K.mat(game, 'metal', '#ffffff'),
        chrome=K.mat(game, 'chrome', '#A8B0BA'),
        brass=K.mat(game, 'brass', '#C8963C'),
        rubber=K.mat(game, 'rubber', '#ffffff'),
        cord=K.mat(game, 'fabric', '#ffffff', {'map': K.tex.weave(NEUTRAL, {'pattern': 'cord', 'scale': 3}), 'rim': 0.2,
                                               'rimPower': 3.4, 'rimColor': '#FFD9B0', 'wrap': 0.6}),
        tweed=K.mat(game, 'fabric', '#ffffff', {'map': K.tex.weave(NEUTRAL, {'pattern': 'tweed', 'fleck': ['#FFFFFF', '#B8AE9C', '#8A806E']}),
                                                'rim': 0.2, 'rimPower': 3.4, 'rimColor': '#FFD9B0', 'wrap': 0.6}),
        velvet=K.mat(game, 'fabric', '#ffffff', {'map': K.tex.weave(NEUTRAL, {'pattern': 'plain', 'scale': 2}), 'rim': 0.22,
                                                 'rimPower': 3.4, 'rimColor': '#FFD9B0', 'wrap': 0.6, 'rough': 0.8}),
        vinyl=K.mat(game, 'vinyl', '#ffffff', {'map': K.tex.pebble('#EEE8E0')}),
        teak=K.mat(game, 'lacquer', '#ffffff', {'map': K.tex.wood(PAL.teak, {'dark': 0.36})}),
        walnut=K.mat(game, 'walnut', '#ffffff', {'map': K.tex.wood(PAL.walnut, {'dark': 0.42})}),
        pattern=K.mat(game, 'fabric', '#ffffff', {'map': patternTex(), 'rim': 0.15, 'rimPower': 3.4, 'rimColor': '#FFD9B0',
                                                  'wrap': 0.6}),
    )


# Button tufts: small domed discs on a surface point with normal n (world-aligned in prop space).
def tuft(g, mat, pos, n, color, r=0.018):
    b = K.m(tc(K.lathe([[0, 0], [r, 0], [r * 0.85, r * 0.5], [0, r * 0.62]], {'seg': 8}), color), mat)
    b.position.set(pos[0], pos[1], pos[2])
    b.quaternion.setFromUnitVectors(UP, v3(n).normalize())
    g.add(b)


# ================================================================================================== SEATING
# ------------------------------------------------------------------------------------------- cloud sofa
def _sofa_cloud(game, opts=None):
    opts = opts or {}
    g = K.prop('sofa_cloud')
    mt = M(game)
    col = _nn(opts.get('color'), '#DE5A22')
    deep = THREE.Color(col).multiplyScalar(0.72).getStyle()
    seatW, n, armW, D = 0.66, 3, 0.26, 0.98
    W = seatW * n + armW * 2
    # recessed walnut plinth
    g.add(K.m(K.box(W - 0.3, 0.1, D - 0.3, 'sm', {'uv': 1.5}), mt.walnut, {'pos': [0, 0.05, 0.02]}))
    # deck
    g.add(K.m(tc(K.cushion(seatW * n + 0.04, 0.2, D, {'puff': 0.025, 'r': 0.07, 'seg': [10, 3, 5], 'uv': 3}), deep), mt.cord, {'pos': [0, 0.2, 0]}))
    # seat + back cushions
    for i in range(n):
        x = (i - (n - 1) / 2) * seatW
        g.add(K.m(tc(K.cushion(seatW - 0.01, 0.22, 0.8, {'puff': 0.08, 'r': 0.1, 'seg': [8, 4, 8], 'uv': 3}), col), mt.cord, {'pos': [x, 0.41, -0.08]}))
        g.add(K.m(tc(K.cushion(seatW - 0.02, 0.5, 0.28, {'puff': 0.09, 'r': 0.13, 'seg': [8, 6, 3], 'uv': 3}), col), mt.cord, {'pos': [x, 0.63, 0.32], 'rot': [0.2, 0, 0]}))
    g.add(K.m(tc(K.cushion(seatW * n + 0.04, 0.66, 0.16, {'puff': 0.03, 'r': 0.07, 'seg': [10, 4, 2], 'uv': 3}), deep), mt.cord, {'pos': [0, 0.56, D / 2 - 0.09], 'rot': [0.1, 0, 0]}))
    # cloud arms: tall puffy bolsters
    for s in (-1, 1):
        g.add(K.m(tc(K.cushion(armW + 0.04, 0.6, D + 0.02, {'puff': 0.07, 'r': 0.15, 'seg': [4, 6, 8], 'uv': 3}), col), mt.cord, {'pos': [s * (W / 2 - armW / 2), 0.36, 0]}))
    # throw pillows (flower power + circles)
    g.add(K.m(patUV(K.cushion(0.42, 0.42, 0.13, {'puff': 0.06, 'r': 0.06, 'seg': [5, 5, 2]}), 'flower'), mt.pattern, {'pos': [-0.66, 0.72, 0.12], 'rot': [0.28, 0.35, 0.12]}))
    g.add(K.m(patUV(K.cushion(0.38, 0.38, 0.12, {'puff': 0.055, 'r': 0.06, 'seg': [5, 5, 2]}), 'circles'), mt.pattern, {'pos': [0.7, 0.7, 0.12], 'rot': [0.26, -0.4, -0.1]}))
    g.userData.colliders = [{'min': [-W / 2, 0, -D / 2], 'max': [W / 2, 0.55, D / 2]}, {'min': [-W / 2, 0, 0.15], 'max': [W / 2, 0.86, D / 2]}]
    return K.finish(game, g)


registerProp('sofa_cloud', _sofa_cloud, {'category': CAT, 'tags': ['seat', 'sofa', 'lobby'], 'size': [2.5, 0.87, 0.98], 'desc': 'orange corduroy "cloud" sofa, puffy arms, flower-power pillows (opts.color)', 'hero': True})


# --------------------------------------------------------------------------------------- avocado couch
def _couch_avocado(game, opts=None):
    opts = opts or {}
    g = K.prop('couch_avocado')
    mt = M(game)
    col = _nn(opts.get('color'), '#8C9A3A')
    dark = THREE.Color(col).multiplyScalar(0.6).getStyle()
    n, sw = 3, 0.62
    W, D = sw * n + 0.2, 0.84
    # teak frame: side slabs with flat arm caps, front/back rails, tapered splayed legs
    for s in (-1, 1):
        g.add(K.m(K.box(0.07, 0.36, D - 0.06, 'sm', {'uv': 1.4, 'swap': True}), mt.teak, {'pos': [s * (W / 2 - 0.05), 0.42, 0]}))
        g.add(K.m(K.box(0.14, 0.045, D + 0.02, 0.018, {'uv': 1.4, 'swap': True}), mt.teak, {'pos': [s * (W / 2 - 0.05), 0.62, 0]}))
    g.add(K.m(K.box(W - 0.14, 0.07, 0.05, 'sm', {'uv': 1.4}), mt.teak, {'pos': [0, 0.26, -D / 2 + 0.06]}))
    g.add(K.m(K.box(W - 0.14, 0.07, 0.05, 'sm', {'uv': 1.4}), mt.teak, {'pos': [0, 0.26, D / 2 - 0.06]}))
    for x, z in [[-1, -1], [1, -1], [-1, 1], [1, 1], [0, -1], [0, 1]]:
        bx, bz = x * (W / 2 - 0.09), z * (D / 2 - 0.07)
        g.add(rod(0.026, [bx + x * 0.035, 0.012, bz + z * 0.03], [bx, 0.25, bz], mt.teak, {'rb': 0.016, 'seg': 10}))
        g.add(K.m(K.cyl(0.017, 0.018, 0.018, {'seg': 10, 'bevel': 0.005}), mt.brass, {'pos': [bx + x * 0.036, 0, bz + z * 0.031]}))
    # upholstered deck + back panel
    g.add(K.m(tc(K.box(W - 0.16, 0.12, D - 0.1, 0.03, {'uv': 3}), dark), mt.tweed, {'pos': [0, 0.33, 0]}))
    g.add(K.m(tc(K.cushion(W - 0.16, 0.44, 0.1, {'puff': 0.015, 'r': 0.04, 'seg': [8, 4, 2], 'uv': 3}), dark), mt.tweed, {'pos': [0, 0.6, D / 2 - 0.07], 'rot': [0.14, 0, 0]}))
    for i in range(n):
        x = (i - (n - 1) / 2) * sw
        g.add(K.m(tc(K.cushion(sw - 0.012, 0.16, 0.66, {'puff': 0.045, 'r': 0.05, 'seg': [7, 3, 7], 'uv': 3}), col), mt.tweed, {'pos': [x, 0.47, -0.06]}))
        # welt piping along the front top edge
        g.add(K.m(tc(K.tube([[x - sw / 2 + 0.06, 0.545, -0.39], [x + sw / 2 - 0.06, 0.545, -0.39]], 0.011, {'seg': 2, 'radial': 6}), dark), mt.tweed))
        bz, by = 0.28, 0.74
        g.add(K.m(tc(K.cushion(sw - 0.02, 0.44, 0.17, {'puff': 0.05, 'r': 0.06, 'seg': [6, 5, 2], 'uv': 3}), col), mt.tweed, {'pos': [x, by, bz], 'rot': [0.2, 0, 0]}))
        for bx in (-0.14, 0.14):
            tuft(g, mt.tweed, [x + bx, by + 0.04, bz - 0.14], [0, 0.2, -1], dark, 0.02)
    g.userData.colliders = [{'min': [-W / 2, 0, -D / 2], 'max': [W / 2, 0.64, D / 2]}, {'min': [-W / 2, 0, 0.1], 'max': [W / 2, 0.98, D / 2]}]
    return K.finish(game, g)


registerProp('couch_avocado', _couch_avocado, {'category': CAT, 'tags': ['seat', 'sofa', 'green_room', 'telly_home'], 'size': [2.06, 0.98, 0.86], 'desc': 'avocado tweed couch on a Danish teak frame, tufted back (opts.color)', 'hero': True})


# ------------------------------------------------------------------------------------ talk-show couch
def _couch_talkshow(game, opts=None):
    opts = opts or {}
    g = K.prop('couch_talkshow')
    mt = M(game)
    col = _nn(opts.get('color'), '#E8A92E')
    pip = _nn(opts.get('piping'), '#B5472A')
    Rc, span_ = 2.4, 0.62  # arc radius, half angle (rad); arc center in front (-z) so it hugs the guests
    cz = -Rc + 0.55  # arc center z (front)

    def at(r, a, y=0):
        return [math.sin(a) * r, y, cz + math.cos(a) * r]

    # plinth: extruded annulus sector (walnut) + chrome kick rail
    def sector(r0, r1, a0, a1, steps=20):
        pts = []
        for i in range(steps + 1):
            a = lerp(a0, a1, i / steps)
            pts.append([math.sin(a) * r1, -(cz + math.cos(a) * r1)])
        for i in range(steps, -1, -1):
            a = lerp(a0, a1, i / steps)
            pts.append([math.sin(a) * r0, -(cz + math.cos(a) * r0)])
        return pts
    plinth = K.extrude(sector(Rc - 0.46, Rc + 0.12, -span_, span_), 0.14, {'bevel': 0.02, 'round': 0.03, 'uv': 1.4})
    plinth.rotateX(-math.pi / 2)
    g.add(K.m(plinth, mt.walnut, {'pos': [0, 0.07 + 0.02, 0]}))
    g.add(K.m(K.tube([[x, 0.035, z + cz] for x, y, z in ring(Rc - 0.47, 24, 0, -span_, span_, False)], 0.018, {'seg': 36, 'radial': 6}), mt.chrome))
    # seat cushions along the arc
    nSeat = 4
    segA = (span_ * 2) / nSeat
    for i in range(nSeat):
        a = -span_ + segA * (i + 0.5)
        w = segA * (Rc - 0.2) - 0.02
        c = K.m(tc(K.cushion(w, 0.18, 0.62, {'puff': 0.05, 'r': 0.07, 'seg': [7, 3, 6], 'uv': 3}), col), mt.velvet)
        c.position.set(*at(Rc - 0.2, a, 0.28))
        c.rotation.y = a
        g.add(c)
        # piping on the front-top edge (follows the cushion)
        pw = w / 2 - 0.05
        p0 = THREE.Vector3(-pw, 0.36, -0.3).applyAxisAngle(UP, a).add(v3(at(Rc - 0.2, a)))
        p1 = THREE.Vector3(pw, 0.36, -0.3).applyAxisAngle(UP, a).add(v3(at(Rc - 0.2, a)))
        g.add(K.m(tc(K.tube([p0.toArray(), p1.toArray()], 0.012, {'seg': 2, 'radial': 6}), pip), mt.velvet))
    # channel-tufted back: vertical rolls around the arc
    nCh = 14
    chA = (span_ * 2) / nCh
    for i in range(nCh):
        a = -span_ + chA * (i + 0.5)
        w = chA * (Rc + 0.05)
        c = K.m(tc(K.cushion(w + 0.012, 0.56, 0.16, {'puff': 0.045, 'r': 0.07, 'seg': [3, 7, 2], 'uv': 3}), col), mt.velvet)
        c.position.set(*at(Rc + 0.04, a, 0.62))
        c.rotation.set(0, a, 0)
        c.rotateX(0.14)
        g.add(c)
    # back cap roll (piping color) along the top
    g.add(K.m(tc(K.tube([[x, 0.885, z + cz] for x, _y, z in ring(Rc + 0.07, 24, 0, -span_, span_, False)], 0.04, {'seg': 30, 'radial': 8}), pip), mt.velvet))
    # rounded arms
    for s in (-1, 1):
        a = s * (span_ + 0.03)
        c = K.m(tc(K.cushion(0.2, 0.36, 0.7, {'puff': 0.035, 'r': 0.09, 'seg': [3, 5, 7], 'uv': 3}), col), mt.velvet)
        c.position.set(*at(Rc - 0.14, a, 0.36))
        c.rotation.y = a
        g.add(c)
        g.add(K.m(tc(K.cushion(0.22, 0.08, 0.72, {'puff': 0.02, 'r': 0.035, 'seg': [3, 2, 7], 'uv': 3}), pip), mt.velvet, {'pos': at(Rc - 0.14, a, 0.56), 'rot': [0, a, 0]}))
    # a guest's forgotten throw pillow
    g.add(K.m(patUV(K.cushion(0.38, 0.38, 0.12, {'puff': 0.055, 'r': 0.06, 'seg': [5, 5, 2]}), 'stripes'), mt.pattern, {'pos': [*at(Rc - 0.02, 0.38, 0.62)], 'rot': [0.25, 0.38, 0.1]}))
    cols = []
    for i in range(5):
        a0, a1 = lerp(-span_ - 0.1, span_ + 0.1, i / 5), lerp(-span_ - 0.1, span_ + 0.1, (i + 1) / 5)
        xs = [math.sin(a) * (Rc + 0.12) for a in (a0, a1)] + [math.sin(a) * (Rc - 0.5) for a in (a0, a1)]
        zf = cz + max(math.cos(a0), math.cos(a1)) * (Rc - 0.5)
        zb = cz + max(math.cos(a0), math.cos(a1), math.cos((a0 + a1) / 2)) * (Rc + 0.14)
        cols.append({'min': [float(js_to_fixed(min(xs), 3)), 0, float(js_to_fixed(zf, 3))],
                     'max': [float(js_to_fixed(max(xs), 3)), 0.95, float(js_to_fixed(zb, 3))]})
    g.userData.colliders = cols
    return K.finish(game, g)


registerProp('couch_talkshow', _couch_talkshow, {'category': CAT, 'tags': ['seat', 'sofa', 'studio_a', 'telly_home'], 'size': [2.8, 0.96, 1.15], 'desc': 'curved harvest-gold velvet talk-show couch, channel-tufted back, walnut plinth', 'hero': True})


# ------------------------------------------------------------------------------------ barrel armchair
# Continuous channel-tufted shell around the y axis: inner face puffs toward the sitter in `n` vertical channels,
# outer face smooth, height per angle from hAt(a). Returns { geo, edge } (edge = welt path: front-left bottom ->
# up -> along the top -> down to front-right bottom).
def channelShell(R, a0, a1, y0, hAt, thick=0.09, n=9, puff=0.035, nv=5, per=3):
    nu = n * per
    pos, uv, idx = [], [], []

    def at(a, y, r):
        return [math.sin(a) * r, y, math.cos(a) * r]

    def chan(u):
        return math.pow(math.sin(math.pi * math.fmod(u * n, 1)), 0.5)

    def inner(u, t):
        a = lerp(a0, a1, u)
        return at(a, y0 + t * hAt(a), R - puff * chan(u) * math.pow(math.sin(math.pi * clamp(t * 1.08, 0, 1)), 0.4))

    def outer(u, t):
        a = lerp(a0, a1, u)
        return at(a, y0 + t * hAt(a), R + thick)

    def grid(fn, cu, cv, want):
        base = len(pos) // 3
        for j in range(cv + 1):
            for i in range(cu + 1):
                p = fn(i / cu, j / cv)
                pos.extend([p[0], p[1], p[2]])
                uv.extend([(i / cu) * (a1 - a0) * R * 3, (j / cv) * 1.5])
        # orientation test on the middle cell
        ci, cj = cu // 2, cv // 2
        A, B, C = v3(fn(ci / cu, cj / cv)), v3(fn((ci + 1) / cu, cj / cv)), v3(fn(ci / cu, (cj + 1) / cv))
        nrm = B.clone().sub(A).cross(C.clone().sub(A))
        flip = nrm.dot(v3(want(ci / cu, cj / cv))) < 0
        for j in range(cv):
            for i in range(cu):
                a = base + j * (cu + 1) + i
                b = a + 1
                c = a + cu + 1
                d = c + 1
                if flip:
                    idx.extend([a, c, b, b, c, d])
                else:
                    idx.extend([a, b, c, b, d, c])

    def radial(u):
        a = lerp(a0, a1, u)
        return [math.sin(a), 0, math.cos(a)]
    grid(inner, nu, nv, lambda u, t: [-v for v in radial(u)])
    grid(outer, nu, nv, lambda u, t: radial(u))

    def top(u, s):
        p, q = inner(u, 1), outer(u, 1)
        return [lerp(p[0], q[0], s), lerp(p[1], q[1], s), lerp(p[2], q[2], s)]
    grid(top, nu, 1, lambda u, t: [0, 1, 0])
    for e in (0, 1):
        def side(t, s, e=e):
            p, q = inner(e, t), outer(e, t)
            return [lerp(p[0], q[0], s), lerp(p[1], q[1], s), lerp(p[2], q[2], s)]

        def want(u, t, e=e):
            a = a1 if e else a0
            sg = 1 if e else -1
            return [math.cos(a) * sg, 0, -math.sin(a) * sg]
        grid(side, nv, 1, want)
    geo = THREE.BufferGeometry()
    geo.setAttribute('position', THREE.Float32BufferAttribute(pos, 3))
    geo.setAttribute('uv', THREE.Float32BufferAttribute(uv, 2))
    geo.setIndex(idx)
    geo.computeVertexNormals()
    cols = np.ones((len(pos) // 3, 3))
    for j in range(nv + 1):
        for i in range(nu + 1):
            k = 0.62 + 0.38 * chan(i / nu)
            o = j * (nu + 1) + i
            cols[o, 0] = k
            cols[o, 1] = k
            cols[o, 2] = k
    geo.setAttribute('color', THREE.BufferAttribute(cols, 3))

    def mid(u, t):
        p, q = inner(u, t), outer(u, t)
        return [(p[0] + q[0]) / 2, (p[1] + q[1]) / 2, (p[2] + q[2]) / 2]
    edge = [mid(0, 0), mid(0, 0.5), mid(0, 1)]
    for i in range(1, 20):
        p = mid(i / 20, 1)
        edge.append([p[0], p[1] + 0.004, p[2]])
    edge.extend([mid(1, 1), mid(1, 0.5), mid(1, 0)])
    return JSObj(geo=geo, edge=edge)


def _armchair_barrel(game, opts=None):
    opts = opts or {}
    g = K.prop('armchair_barrel')
    mt = M(game)
    col = _nn(opts.get('color'), '#C4502A')
    dark = THREE.Color(col).multiplyScalar(0.62).getStyle()
    R = 0.36
    # swivel plinth: walnut drum + brass ring and collar
    g.add(K.m(puck(0.27, 0.1, 0.02, 20), mt.walnut))
    g.add(K.m(K.tube(ring(0.272, 20, 0.1), 0.01, {'seg': 20, 'radial': 4, 'closed': True}), mt.brass))
    g.add(K.m(K.cyl(0.08, 0.1, 0.07, {'seg': 16}), mt.brass, {'pos': [0, 0.1, 0]}))
    # upholstered drum body + round seat cushion with welts
    g.add(K.m(tc(puck(R + 0.05, 0.2, 0.06, 24), col), mt.velvet, {'pos': [0, 0.16, 0]}))
    g.add(K.m(tc(K.tube(ring(R + 0.05, 24, 0.185), 0.012, {'seg': 24, 'radial': 4, 'closed': True}), dark), mt.velvet))
    g.add(K.m(tc(puck(R - 0.035, 0.12, 0.05, 24), col), mt.velvet, {'pos': [0, 0.35, -0.03]}))
    g.add(K.m(tc(K.tube(ring(R - 0.04, 24, 0.44), 0.011, {'seg': 24, 'radial': 4, 'closed': True}), dark), mt.velvet, {'pos': [0, 0, -0.03]}))

    # continuous channel-tufted barrel back sweeping down into the arms, welt all around its edge
    def hAt(a):
        return 0.22 + 0.3 * math.pow(max(0, math.cos((a / 2.2) * math.pi / 2)), 0.9)
    sh = channelShell(R=R + 0.0, a0=-2.2, a1=2.2, y0=0.34, hAt=hAt, thick=0.08, n=11, puff=0.06, nv=5, per=3)
    geo, edge = sh.geo, sh.edge
    g.add(K.m(tc(K.uvScale(geo, 1, 1), col), mt.velvet))
    g.add(K.m(tc(K.tube(edge, 0.045, {'seg': 36, 'radial': 6}), dark), mt.velvet))
    g.userData.colliders = [{'min': [-0.44, 0, -0.44], 'max': [0.44, 0.9, 0.44]}]
    return K.finish(game, g)


registerProp('armchair_barrel', _armchair_barrel, {'category': CAT, 'tags': ['seat', 'chair', 'lobby', 'green_room'], 'size': [0.88, 0.9, 0.88], 'desc': 'rust velvet channel-tufted barrel swivel chair on a walnut plinth (opts.color)'})


# ------------------------------------------------------------------------------------------ ball chair
def _chair_ball(game, opts=None):
    opts = opts or {}
    g = K.prop('chair_ball')
    mt = M(game)
    shellCol = _nn(opts.get('shell'), '#F4F1E8')
    inCol = _nn(opts.get('color'), '#E3662B')
    R, cut = 0.55, 0.4
    cy = 0.2 + R
    th0 = math.acos(cut)

    # spheres opened around -z (pole rotated from +y to -z so the opening edge is a clean circle)
    def shell(r, ws, hs):
        return THREE.SphereGeometry(r, ws, hs, 0, TAU, th0, math.pi - th0).rotateX(-math.pi / 2)
    g.add(K.m(tc(shell(R, 28, 14), shellCol), mt.lacquer, {'pos': [0, cy, 0]}))
    Ri = R - 0.05
    g.add(K.m(K.uvScale(tc(flipGeo(shell(Ri, 22, 11)), inCol), 8, 3), mt.vinyl, {'pos': [0, cy, 0]}))
    # rolled rim joining the two shells
    rz, rr = -(R + Ri) / 2 * cut, math.sqrt(1 - cut * cut) * (R + Ri) / 2
    g.add(K.m(tc(THREE.TorusGeometry(rr, 0.032, 6, 32), shellCol), mt.lacquer, {'pos': [0, cy, rz]}))
    # inside: seat puck + tufted back cushion
    g.add(K.m(K.uvScale(tc(puck(0.35, 0.13, 0.055, 24), inCol), 3, 1), mt.vinyl, {'pos': [0, cy - 0.38, -0.02]}))
    g.add(K.m(tc(K.cushion(0.52, 0.44, 0.13, {'puff': 0.06, 'r': 0.06, 'seg': [5, 5, 2], 'uv': 3}), inCol), mt.vinyl, {'pos': [0, cy + 0.0, 0.3], 'rot': [0.28, 0, 0]}))
    for x, y in [[-0.12, 0.06], [0.12, 0.06], [0, -0.08]]:
        tuft(g, mt.vinyl, [x, cy + y, 0.3 - 0.075 + y * 0.28], [0, 0.28, -1], THREE.Color(inCol).multiplyScalar(0.6).getStyle(), 0.02)
    # trumpet pedestal
    g.add(K.m(tc(K.lathe([[0, 0], [0.34, 0], [0.34, 0.025], [0.18, 0.06], [0.08, 0.14], [0.07, 0.24], [0, 0.24]], {'round': 0.02, 'seg': 22, 'steps': 1}), shellCol), mt.lacquer))
    g.userData.colliders = [{'min': [-R, 0, -R], 'max': [R, cy + R, R]}]
    return K.finish(game, g)


registerProp('chair_ball', _chair_ball, {'category': CAT, 'tags': ['seat', 'chair', 'lobby', 'green_room'], 'size': [1.1, 1.3, 1.1], 'desc': 'space-age ball chair: white lacquer shell, orange vinyl interior, trumpet base (opts.color/shell)'})


# --------------------------------------------------------------------------------------------- bean bag
def _bean_bag(game, opts=None):
    opts = opts or {}
    g = K.prop('bean_bag')
    mt = M(game)
    col = _nn(opts.get('color'), '#E23B3B')
    seed = _nn(opts.get('seed'), 3)
    rnd = mulberry32(seed * 131 + 7)
    ph = [rnd() * 6, rnd() * 6, rnd() * 6]
    H, Rb = 0.68, 0.42
    # slouchy pear: wide pooled bottom, narrower top leaning back, a sitting dent on the front
    dent = THREE.Vector3(0, 0.62, -0.78).normalize()
    d = THREE.Vector3()

    def shape(x, y, z):
        d.set(x, y, z).normalize()
        phi = math.acos(clamp(d.y, -1, 1))
        t = phi / math.pi
        th = math.atan2(d.z, d.x)
        r = Rb * math.pow(math.sin(phi), 0.6) * (0.5 + 0.5 * math.pow(t, 0.7)) * (1 + 0.07 * math.sin(th * 4 + ph[0] + t * 5) * math.sin(phi))
        yy = H * math.pow(math.cos(phi) * 0.5 + 0.5, 1.25)
        k = max(0, d.dot(dent) - 0.5) / 0.5
        yy -= k * k * 0.16
        r *= 1 + k * 0.06
        yy += 0.025 * math.sin(th * 3 + ph[1]) * (1 - t)
        lean = 0.09 * math.pow(yy / H, 2)
        return [math.cos(th) * r, max(0.004, yy), math.sin(th) * r + lean]
    geo = THREE.SphereGeometry(1, 32, 18)
    p = geo.attributes.position
    for i in range(p.count):
        x, y, z = shape(p.getX(i), p.getY(i), p.getZ(i))
        p.setXYZ(i, x, y, z)
    geo.computeVertexNormals()
    K.uvScale(geo, 5, 2.5)
    g.add(K.m(tc(geo, col), mt.vinyl))
    # panel seams (slightly proud) + a carry strap on the crown
    dark = THREE.Color(col).multiplyScalar(0.6).getStyle()
    for s in range(6):
        th = s * math.pi / 3 + 0.3
        pts = []
        for i in range(13):
            phi = lerp(0.1, 2.2, i / 12)
            x, y, z = shape(math.sin(phi) * math.cos(th), math.cos(phi), math.sin(phi) * math.sin(th))
            pts.append([x * 1.012, y + 0.002, z * 1.012])
        g.add(K.m(tc(K.tube(pts, 0.006, {'seg': 18, 'radial': 4}), dark), mt.vinyl))
    top = shape(0, 1, 0.001)
    g.add(K.m(tc(K.tube([[top[0] - 0.06, top[1] - 0.01, top[2] + 0.02], [top[0], top[1] + 0.045, top[2] + 0.03], [top[0] + 0.06, top[1] - 0.01, top[2] + 0.02]], 0.013, {'seg': 10, 'radial': 5}), dark), mt.vinyl))
    g.userData.colliders = [{'min': [-0.4, 0, -0.4], 'max': [0.4, 0.6, 0.45]}]
    return K.finish(game, g)


registerProp('bean_bag', _bean_bag, {'category': CAT, 'tags': ['seat', 'studio_b', 'green_room'], 'size': [0.84, 0.68, 0.9], 'desc': 'slouchy glossy vinyl bean bag with a sitting dent, panel seams, carry strap (opts.color, opts.seed)'})


# ------------------------------------------------------------------------------------ rolling office chair
def _chair_office(game, opts=None):
    opts = opts or {}
    g = K.prop('chair_office')
    mt = M(game)
    col = _nn(opts.get('color'), '#D2642E')
    dark, shellC = '#3A2A30', '#4A3530'
    # 5-star polished base with hooded casters
    legGeo = cg('office_leg', lambda: taperS(K.box(0.3, 0.04, 0.056, 0.012), {'axis': 'x', 'k': 0.62}))
    wheel = cg('office_wheel', lambda: THREE.CylinderGeometry(0.03, 0.03, 0.044, 10, 1).translate(0, 0, 0))
    for i in range(5):
        a = (i / 5) * TAU + 0.3
        leg = K.m(legGeo, mt.chrome)
        leg.position.set(math.sin(a) * 0.15, 0.085, math.cos(a) * 0.15)
        leg.rotation.set(0, a - math.pi / 2, -0.1)
        g.add(leg)
        cx, cz = math.sin(a) * 0.285, math.cos(a) * 0.285
        g.add(K.m(tc(wheel, dark), mt.rubber, {'pos': [cx, 0.03, cz], 'rot': [0, a, math.pi / 2]}))
        g.add(K.m(tc(cbox(0.056, 0.03, 0.05, 0.008), dark), mt.plastic, {'pos': [cx, 0.058, cz], 'rot': [0, a, 0]}))
    g.add(K.m(K.cyl(0.05, 0.056, 0.06, {'seg': 12}), mt.chrome, {'pos': [0, 0.065, 0]}))
    g.add(K.m(tc(K.lathe([[0, 0], [0.034, 0], [0.038, 0.03], [0.03, 0.05], [0.038, 0.07], [0.03, 0.09], [0.038, 0.11], [0.03, 0.13], [0.036, 0.16], [0, 0.16]], {'seg': 10}), dark), mt.rubber, {'pos': [0, 0.12, 0]}))
    g.add(K.m(K.cyl(0.022, 0.022, 0.16, {'seg': 10}), mt.chrome, {'pos': [0, 0.26, 0]}))
    g.add(K.m(tc(K.box(0.22, 0.03, 0.22, 0.01), dark), mt.plastic, {'pos': [0, 0.42, 0]}))
    # tilt knob
    g.add(K.m(tc(K.lathe([[0, 0], [0.025, 0], [0.028, 0.02], [0.02, 0.03], [0, 0.03]], {'seg': 10}), dark), mt.plastic, {'pos': [0.11, 0.41, -0.02], 'rot': [0, 0, -math.pi / 2]}))
    # seat: molded shell + biscuit-tufted vinyl cushion
    g.add(K.m(tc(K.box(0.5, 0.05, 0.48, 0.014), shellC), mt.plastic, {'pos': [0, 0.455, -0.02]}))
    g.add(K.m(tc(K.cushion(0.5, 0.1, 0.48, {'puff': 0.035, 'r': 0.04, 'seg': [6, 2, 6], 'uv': 3}), col), mt.vinyl, {'pos': [0, 0.52, -0.02]}))
    dk = THREE.Color(col).multiplyScalar(0.55).getStyle()
    g.add(K.m(tc(K.tube([[-0.2, 0.572, -0.03], [0.2, 0.572, -0.03]], 0.006, {'seg': 2, 'radial': 4}), dk), mt.vinyl))
    # spine + back cushion with a stitched channel
    g.add(K.m(K.tube([[0, 0.44, 0.1], [0, 0.45, 0.25], [0, 0.52, 0.29], [0, 0.66, 0.29]], 0.018, {'seg': 10, 'radial': 7}), mt.chrome))
    g.add(K.m(tc(K.box(0.44, 0.34, 0.04, 0.014), shellC), mt.plastic, {'pos': [0, 0.83, 0.3], 'rot': [-0.08, 0, 0]}))
    g.add(K.m(tc(K.cushion(0.44, 0.34, 0.08, {'puff': 0.03, 'r': 0.035, 'seg': [5, 4, 2], 'uv': 3}), col), mt.vinyl, {'pos': [0, 0.83, 0.255], 'rot': [-0.08, 0, 0]}))
    g.add(K.m(tc(K.tube([[-0.18, 0.82, 0.205], [0.18, 0.82, 0.205]], 0.005, {'seg': 2, 'radial': 4}), dk), mt.vinyl))
    # chrome loop arms with black pads
    for s in (-1, 1):
        g.add(K.m(K.tube([[s * 0.2, 0.46, 0.12], [s * 0.27, 0.52, 0.12], [s * 0.27, 0.66, 0.05], [s * 0.27, 0.66, -0.12], [s * 0.24, 0.5, -0.16], [s * 0.2, 0.46, -0.14]], 0.012, {'seg': 16, 'radial': 6}), mt.chrome))
        g.add(K.m(tc(K.box(0.055, 0.035, 0.2, 0.012), dark), mt.plastic, {'pos': [s * 0.27, 0.685, -0.03]}))
    g.userData.colliders = [{'min': [-0.3, 0, -0.3], 'max': [0.3, 1.0, 0.33]}]
    return K.finish(game, g)


registerProp('chair_office', _chair_office, {'category': CAT, 'tags': ['seat', 'chair', 'newsroom', 'master_control'], 'size': [0.6, 1.02, 0.62], 'desc': 'rolling office chair: 5-star chrome base, bellows column, orange vinyl (opts.color)'})


# ------------------------------------------------------------------------------------ desk atlas
# One 1024 atlas (4x4 cells of 256) for every small printed desk thing: cell(geo, cx, cy) maps a 0..1-UV geometry
# into a cell (cx, cy counted from the top-left). Uses the matte 'paint' preset (paper, cards, decals).
def deskAtlas():
    def draw(ctx, W, H, rand):
        S = 256

        def at(cx, cy, fn):
            ctx.save()
            ctx.translate(cx * S, cy * S)
            ctx.beginPath()
            ctx.rect(0, 0, S, S)
            ctx.clip()
            fn()
            ctx.restore()

        def font(px, f='Titan One'):
            return '%spx "%s", "Arial Black", sans-serif' % (js_str(px), f)

        def typed(lines, x, y, lh, px=13, col='#2A2230'):
            ctx.fillStyle = col
            ctx.font = '%spx "Courier New", monospace' % js_str(px)
            ctx.textAlign = 'left'
            ctx.textBaseline = 'alphabetic'
            for i, l in enumerate(lines):
                ctx.fillText(l, x, y + i * lh)

        # (0,0) rotary dial: number ring + finger holes
        def c00():
            ctx.fillStyle = '#F4F1E8'
            ctx.beginPath()
            ctx.arc(128, 128, 128, 0, TAU)
            ctx.fill()
            ctx.textAlign = 'center'
            ctx.textBaseline = 'middle'
            for i in range(10):
                a = -math.pi * 0.62 + i * 0.5
                x, y = 128 + math.cos(a) * 84, 128 + math.sin(a) * 84
                ctx.fillStyle = '#1E1530'
                ctx.beginPath()
                ctx.arc(x, y, 24, 0, TAU)
                ctx.fill()
                ctx.fillStyle = '#F4F1E8'
                ctx.font = font(22)
                ctx.fillText(str((i + 1) % 10), x, y + 1)
            ctx.fillStyle = '#E23B3B'
            ctx.beginPath()
            ctx.arc(128, 128, 40, 0, TAU)
            ctx.fill()
            ctx.fillStyle = '#F4F1E8'
            ctx.font = font(18, 'Bungee')
            ctx.fillText('WZ-13', 128, 130)
        at(0, 0, c00)

        # (1,0) typed sheet
        def c10():
            ctx.fillStyle = '#FBF6EA'
            ctx.fillRect(0, 0, S, S)
            typed(['WZTV ACTION 13 NEWS', '11:59 PM  FRI OCT 31', '', 'REPORTS OF STRANGE', 'VIEWERS "TUNING IN"', 'NEAR THE STATION...', '', 'STAY TUNED. DO NOT', 'ADJUST YOUR SET.', '', '-- 30 --'], 18, 30, 19)
            ctx.fillStyle = '#E23B3B'
            ctx.fillRect(18, 36, 150, 2)
        at(1, 0, c10)

        # (2,0) TV WEEKLY magazine cover (cards.js)
        def c20():
            ctx.fillStyle = '#E23B3B'
            ctx.fillRect(0, 0, S, S)
            drawCard(ctx, 'magazine_tv_weekly', 40, 0, 176, 256)
            ctx.fillStyle = '#E23B3B'
            ctx.fillRect(0, 0, 40, S)
            ctx.fillRect(216, 0, 40, S)
        at(2, 0, c20)

        # (3,0) yellow legal pad
        def c30():
            ctx.fillStyle = '#FBE88A'
            ctx.fillRect(0, 0, S, S)
            ctx.strokeStyle = '#7FB4E0'
            ctx.lineWidth = 2
            for y in range(40, S, 18):
                ctx.beginPath()
                ctx.moveTo(0, y)
                ctx.lineTo(S, y)
                ctx.stroke()
            ctx.strokeStyle = '#E47A7A'
            ctx.beginPath()
            ctx.moveTo(40, 0)
            ctx.lineTo(40, S)
            ctx.stroke()
            ctx.fillStyle = '#6B3A6E'
            ctx.fillRect(0, 0, S, 22)
            ctx.strokeStyle = '#2F5BD3'
            ctx.lineWidth = 2.5
            ctx.lineCap = 'round'
            for i in range(5):
                ctx.beginPath()
                x = 50
                ctx.moveTo(x, 54 + i * 18)
                while x < 120 + rand() * 110:
                    x += 6
                    ctx.lineTo(x, 54 + i * 18 - (rand() * 6))
                ctx.stroke()
        at(3, 0, c30)

        # (0,1) switchboard jack field
        def c01():
            ctx.fillStyle = '#3A2E36'
            ctx.fillRect(0, 0, S, S)
            for r in range(5):
                for c in range(8):
                    x, y = 18 + c * 30, 26 + r * 46
                    ctx.fillStyle = '#FFB347' if r % 2 else '#FF6B5A'
                    ctx.beginPath()
                    ctx.arc(x + 7, y - 12, 5, 0, TAU)
                    ctx.fill()
                    ctx.fillStyle = '#C9CED6'
                    ctx.beginPath()
                    ctx.arc(x + 7, y + 6, 9, 0, TAU)
                    ctx.fill()
                    ctx.fillStyle = '#120C16'
                    ctx.beginPath()
                    ctx.arc(x + 7, y + 6, 5, 0, TAU)
                    ctx.fill()
                    ctx.fillStyle = '#F4F1E8'
                    ctx.fillRect(x - 3, y + 18, 20, 6)
        at(0, 1, c01)

        # (1,1) rolodex / index card
        def c11():
            ctx.fillStyle = '#F7F1E1'
            ctx.fillRect(0, 0, S, S)
            ctx.fillStyle = '#E23B3B'
            ctx.fillRect(0, 38, S, 3)
            ctx.strokeStyle = '#9FC0E8'
            ctx.lineWidth = 2
            for y in range(70, S, 26):
                ctx.beginPath()
                ctx.moveTo(0, y)
                ctx.lineTo(S, y)
                ctx.stroke()
            typed(['DALTON, DUKE', 'PRECINCT 13 SET', 'EXT. 1313'], 14, 30, 34, 18)
        at(1, 1, c11)

        # (2,1) engraved brass nameplate
        def c21():
            g = ctx.createLinearGradient(0, 0, 0, S)
            g.addColorStop(0, '#F2CF6A')
            g.addColorStop(0.5, '#C8963C')
            g.addColorStop(1, '#8A6224')
            ctx.fillStyle = g
            ctx.fillRect(0, 0, S, S)
            ctx.fillStyle = '#3A2410'
            ctx.textAlign = 'center'
            ctx.textBaseline = 'middle'
            ctx.font = font(34, 'Bungee')
            ctx.fillText('RECEPTION', 128, 118)
            ctx.font = font(18)
            ctx.fillText('PLEASE RING', 128, 160)
        at(2, 1, c21)

        # (3,1) WZTV 13 badge: blue disc, red ring, white 13
        def c31():
            ctx.fillStyle = '#F4F1E8'
            ctx.beginPath()
            ctx.arc(128, 128, 128, 0, TAU)
            ctx.fill()
            ctx.fillStyle = '#E23B3B'
            ctx.beginPath()
            ctx.arc(128, 128, 118, 0, TAU)
            ctx.fill()
            ctx.fillStyle = '#2F5BD3'
            ctx.beginPath()
            ctx.arc(128, 128, 96, 0, TAU)
            ctx.fill()
            ctx.textAlign = 'center'
            ctx.textBaseline = 'middle'
            ctx.fillStyle = '#1B2F7A'
            ctx.font = font(104, 'Bungee')
            ctx.fillText('13', 134, 144)
            ctx.fillStyle = '#F4F1E8'
            ctx.fillText('13', 128, 138)
            ctx.fillStyle = '#FFD23A'
            ctx.font = font(24, 'Bungee')
            ctx.fillText('WZTV', 128, 62)
        at(3, 1, c31)

        # (0,2) ACTION 13 NEWS logo panel
        def c02():
            ctx.fillStyle = '#2A1D3A'
            ctx.fillRect(0, 0, S, S)
            for i, c in enumerate(['#E3662B', '#E8A92E', '#F6E7C8']):
                ctx.fillStyle = c
                ctx.fillRect(0, 150 + i * 16, S, 10)
            ctx.textAlign = 'center'
            ctx.textBaseline = 'middle'
            ctx.fillStyle = '#E8A92E'
            ctx.font = font(44, 'Bungee')
            ctx.fillText('ACTION', 128, 52)
            ctx.fillStyle = '#F4F1E8'
            ctx.font = font(78, 'Bungee')
            ctx.fillText('13', 128, 112)
            ctx.fillStyle = '#F6E7C8'
            ctx.font = font(34, 'Bungee')
            ctx.fillText('NEWS', 128, 222)
        at(0, 2, c02)

        # (1,2) drawer label cards
        def c12():
            ctx.fillStyle = '#C9CED6'
            ctx.fillRect(0, 0, S, S)
            ctx.fillStyle = '#FBF6EA'
            ctx.fillRect(16, 60, S - 32, S - 120)
            typed(['A - F', 'SCRIPTS'], 60, 118, 40, 30)
        at(1, 2, c12)

        # (2,2) typewriter brand plate
        def c22():
            ctx.fillStyle = '#2A2230'
            ctx.fillRect(0, 0, S, S)
            ctx.textAlign = 'center'
            ctx.textBaseline = 'middle'
            ctx.fillStyle = '#E8B84A'
            ctx.font = font(52, 'Bungee')
            ctx.fillText('SELECTRA', 128, 116)
            ctx.fillStyle = '#C9CED6'
            ctx.font = font(22)
            ctx.fillText('ELECTRIC  72', 128, 162)
        at(2, 2, c22)

        # (3,2) news script page
        def c32():
            ctx.fillStyle = '#FDFBF4'
            ctx.fillRect(0, 0, S, S)
            ctx.fillStyle = '#7FB4E0'
            ctx.fillRect(0, 0, S, 26)
            typed(['ANCHOR (ON CAM):', 'GOOD EVENING. OUR', 'TOP STORY TONIGHT', '... THE AUDIENCE', 'WON\'T LEAVE.', '', 'ROLL TAPE 13-B', '(VTR)  :30'], 16, 50, 22, 14)
            ctx.fillStyle = '#E23B3B'
            ctx.fillRect(12, 186, 110, 3)
        at(3, 2, c32)

        # (0,3) mug wrap: harvest gold with the 13 bug
        def c03():
            ctx.fillStyle = '#E8A92E'
            ctx.fillRect(0, 0, S, S)
            ctx.fillStyle = '#F6E7C8'
            ctx.fillRect(0, 26, S, 12)
            ctx.fillRect(0, S - 38, S, 12)
            ctx.fillStyle = '#2F5BD3'
            ctx.beginPath()
            ctx.arc(64, 128, 46, 0, TAU)
            ctx.fill()
            ctx.fillStyle = '#F4F1E8'
            ctx.textAlign = 'center'
            ctx.textBaseline = 'middle'
            ctx.font = font(50, 'Bungee')
            ctx.fillText('13', 64, 134)
        at(0, 3, c03)

        # (1,3) hairspray can label
        def c13():
            g = ctx.createLinearGradient(0, 0, S, 0)
            g.addColorStop(0, '#FF5FA2')
            g.addColorStop(1, '#C2407A')
            ctx.fillStyle = g
            ctx.fillRect(0, 0, S, S)
            ctx.fillStyle = '#FFE3A3'
            ctx.textAlign = 'center'
            ctx.textBaseline = 'middle'
            ctx.font = font(40, 'Shrikhand')
            ctx.fillText('Aqua', 128, 96)
            ctx.fillText('Hold', 128, 144)
            ctx.fillStyle = '#F4F1E8'
            ctx.font = font(16)
            ctx.fillText('SUPER HOLD', 128, 196)
        at(1, 3, c13)

        # (2,3) keycap letters
        def c23():
            ctx.fillStyle = '#3A2E36'
            ctx.fillRect(0, 0, S, S)
            ctx.fillStyle = '#F4F1E8'
            ctx.textAlign = 'center'
            ctx.textBaseline = 'middle'
            ctx.font = font(40)
            ctx.fillText('13', 128, 128)
        at(2, 3, c23)

        # (3,3) manila folder
        def c33():
            ctx.fillStyle = '#E8C98A'
            ctx.fillRect(0, 0, S, S)
            ctx.fillStyle = '#D4B070'
            ctx.fillRect(0, 0, S, 30)
            typed(['CONFIDENTIAL'], 40, 140, 20, 22, '#B5472A')
            ctx.strokeStyle = '#B5472A'
            ctx.lineWidth = 3
            ctx.strokeRect(30, 116, 196, 34)
        at(3, 3, c33)
    return K.tex.canvas('furn_desk_atlas', 1024, 1024, draw, {'repeat': False, 'fonts': True})


def drawCard(ctx, id, x, y, w, h):
    # JS: getCard(id).image (the card canvas) drawn at x, y, w, h. The card painters are Godot runtime code: the
    # kit draws the pre-rendered card image (K.drawTo); a missing card leaves the base color (JS catch branch).
    ctx.save()
    try:
        ctx.translate(x, y)
        K.drawTo(ctx, id, w, h)
    except Exception:
        pass  # card missing: leave the base color
    finally:
        ctx.restore()


def cell(geo, cx, cy):
    return K.uvRect(geo.clone(), cx / 4, 1 - (cy + 1) / 4, (cx + 1) / 4, 1 - cy / 4)


def atlasMat(game):
    return K.mat(game, 'paint', '#ffffff', {'map': deskAtlas()})


# ---------------------------------------------------------------------------- desk items (sub-assemblies)
# Each returns a THREE.Group in its own local space (base at y = 0, front = -z) built from shared materials.
def phoneGroup(game, color='#E23B3B'):
    mt, atl = M(game), atlasMat(game)
    g = THREE.Group()
    dark = '#2A2230'
    g.add(K.m(tc(K.box(0.19, 0.022, 0.205, 0.01), dark), mt.plastic, {'pos': [0, 0.011, 0.004]}))
    body = taperS(K.box(0.19, 0.11, 0.2, 0.045), {'axis': 'y', 'k': 0.72})
    g.add(K.m(tc(body, color), mt.plastic, {'pos': [0, 0.075, 0.005]}))
    # sloped dial face
    face = THREE.Group()
    face.position.set(0, 0.078, -0.075)
    face.rotation.x = -0.62
    face.add(K.m(tc(puck(0.062, 0.012, 0.005, 16), color), mt.plastic, {'rot': [-math.pi / 2, 0, 0]}))
    face.add(K.m(cell(THREE.CircleGeometry(0.054, 24), 0, 0), atl, {'pos': [0, 0, -0.0125], 'rot': [0, math.pi, 0]}))
    face.add(K.m(tc(puck(0.013, 0.008, 0.003, 12), '#F4F1E8'), mt.plastic, {'pos': [0, 0, -0.012], 'rot': [-math.pi / 2, 0, 0]}))
    face.add(K.m(K.box(0.006, 0.02, 0.006, 0.002), mt.chrome, {'pos': [0.043, -0.038, -0.015], 'rot': [0, 0, 0.6]}))
    g.add(face)
    # cradle horns + handset
    for s in (-1, 1):
        g.add(K.m(tc(K.box(0.034, 0.036, 0.056, 0.014), color), mt.plastic, {'pos': [s * 0.078, 0.132, 0.01]}))
    hs = THREE.Group()
    hs.position.set(0, 0.152, 0.01)
    cup = K.lathe([[0, 0], [0.028, 0], [0.034, 0.018], [0.03, 0.03], [0, 0.03]], {'seg': 12, 'round': 0.006, 'steps': 1})
    hs.add(K.m(tc(K.tube([[-0.1, -0.012, 0], [-0.06, 0.012, 0], [0.06, 0.012, 0], [0.1, -0.012, 0]], 0.016, {'seg': 10, 'radial': 7}), color), mt.plastic))
    for s in (-1, 1):
        hs.add(K.m(tc(cup, color), mt.plastic, {'pos': [s * 0.1, -0.012, 0], 'rot': [0, 0, math.pi], 'scale': [1, 1, 1]}))
    g.add(hs)
    # coiled cord from the handset end down to the body side
    pts = []
    for i in range(61):
        t = i / 60
        a = t * TAU * 9
        base = [lerp(-0.1, -0.12, t), lerp(0.13, 0.03, math.sin(t * math.pi * 0.5)), lerp(0.02, -0.06, t) - math.sin(t * math.pi) * 0.06]
        pts.append([base[0] + math.cos(a) * 0.008 - 0.012, base[1] + math.sin(a) * 0.008, base[2]])
    g.add(K.m(tc(K.tube(pts, 0.0035, {'seg': 48, 'radial': 3}), color), mt.plastic))
    return g


def typewriterGroup(game, color='#E8A92E'):
    mt, atl = M(game), atlasMat(game)
    g = THREE.Group()
    dark, deep = '#2E2630', THREE.Color(color).multiplyScalar(0.7).getStyle()
    # chunky body: lower tray + domed hood
    g.add(K.m(tc(K.box(0.46, 0.08, 0.38, 0.035), color), mt.plastic, {'pos': [0, 0.05, 0]}))
    g.add(K.m(tc(taperS(K.box(0.44, 0.09, 0.2, 0.04), {'axis': 'y', 'k': 0.82}), color), mt.plastic, {'pos': [0, 0.125, 0.07]}))
    g.add(K.m(tc(K.box(0.44, 0.012, 0.36, 0.005), dark), mt.plastic, {'pos': [0, 0.006, 0]}))
    # keyboard well
    g.add(K.m(tc(K.box(0.4, 0.03, 0.15, 0.012), dark), mt.plastic, {'pos': [0, 0.085, -0.105], 'rot': [0.2, 0, 0]}))
    key = cg('tw_key', lambda: K.lathe([[0, 0], [0.0128, 0], [0.012, 0.015], [0, 0.017]], {'seg': 7}))
    rows = [[10, 0], [9, 0.01], [8, 0.02]]
    for r, (n, off) in enumerate(rows):
        for i in range(n):
            x, z, y = (i - (n - 1) / 2) * 0.034 + off * 0.2, -0.155 + r * 0.035, 0.09 + r * 0.008
            g.add(K.m(tc(key, '#E23B3B' if (i + r) % 7 == 3 else '#F4F1E8'), mt.plastic, {'pos': [x, y, z], 'rot': [0.2, 0, 0]}))
    g.add(K.m(tc(K.box(0.2, 0.014, 0.024, 0.006), '#F4F1E8'), mt.plastic, {'pos': [0, 0.088, -0.19], 'rot': [0.2, 0, 0]}))
    # platen, knobs, paper, return lever, brand plate
    g.add(K.m(tc(K.cyl(0.028, 0.028, 0.42, {'seg': 14}), dark), mt.plastic, {'pos': [-0.21, 0.185, 0.1], 'rot': [0, 0, -math.pi / 2]}))
    for s in (-1, 1):
        g.add(K.m(tc(K.lathe([[0, 0], [0.024, 0], [0.028, 0.012], [0.024, 0.028], [0, 0.03]], {'seg': 12, 'round': 0.004, 'steps': 1}), dark), mt.plastic, {'pos': [s * 0.21, 0.185, 0.1], 'rot': [0, 0, -s * math.pi / 2]}))
    g.add(K.m(K.tint(cell(cbox(0.24, 0.26, 0.003, 0.001), 1, 0), '#D8D0C0'), atl, {'pos': [0, 0.3, 0.115], 'rot': [-0.18, 0, 0.02]}))
    g.add(K.m(K.tube([[-0.23, 0.2, 0.06], [-0.27, 0.23, 0.03], [-0.29, 0.25, -0.02]], 0.006, {'seg': 8, 'radial': 5}), mt.chrome))
    g.add(K.m(K.cyl(0.012, 0.012, 0.02, {'seg': 8}), mt.chrome, {'pos': [-0.29, 0.24, -0.02], 'rot': [0, 0, 0.4]}))
    g.add(K.m(cell(cbox(0.14, 0.03, 0.004, 0.001), 2, 2), atl, {'pos': [0, 0.15, -0.035], 'rot': [-0.55, 0, 0]}))
    g.add(K.m(tc(K.box(0.44, 0.02, 0.05, 0.009), deep), mt.plastic, {'pos': [0, 0.172, -0.02]}))
    return g


def paperStack(game, n=5, seed=1, cellXY=None):
    cellXY = [1, 0] if cellXY is None else cellXY
    atl = atlasMat(game)
    rnd = mulberry32(seed * 977 + 3)
    g = THREE.Group()
    for i in range(n):
        top = i == n - 1
        cx, cy = cellXY if top else [1, 2]
        geo = cell(cbox(0.22, 0.004, 0.28, 0.0012), cx, cy)
        px = (rnd() - 0.5) * 0.012
        pz = (rnd() - 0.5) * 0.012
        ry = (rnd() - 0.5) * 0.12
        sh = K.m(geo, atl, {'pos': [px, 0.002 + i * 0.0045, pz], 'rot': [0, ry, 0]})
        if not top:
            sh.geometry = K.tint(sh.geometry.clone(), '#F4EEDC')
        g.add(sh)
    return g


def mugGroup(game):
    atl, mt = atlasMat(game), M(game)
    g = THREE.Group()
    g.add(K.m(cell(K.lathe([[0, 0], [0.036, 0], [0.04, 0.005], [0.04, 0.09], [0.036, 0.092], [0.034, 0.02], [0, 0.02]], {'seg': 16}), 0, 3), atl))
    g.add(K.m(tc(THREE.TorusGeometry(0.024, 0.007, 6, 12, math.pi * 1.2), '#E8A92E'), mt.plastic, {'pos': [0.04, 0.048, 0], 'rot': [0, 0, -math.pi * 0.6]}))
    g.add(K.m(tc(THREE.CircleGeometry(0.034, 14), '#3A2014'), mt.plastic, {'pos': [0, 0.075, 0], 'rot': [-math.pi / 2, 0, 0]}))
    return g


def pencilCup(game):
    mt = M(game)
    g = THREE.Group()
    g.add(K.m(tc(K.lathe([[0, 0], [0.034, 0], [0.036, 0.1], [0.032, 0.1], [0.03, 0.01], [0, 0.01]], {'seg': 14}), '#8C9A3A'), mt.plastic))
    cols = ['#F4E03A', '#F4E03A', '#E23B3B', '#2F5BD3']
    for i, c in enumerate(cols):
        a = i * 1.7
        p0, p1 = [math.cos(a) * 0.012, 0.01, math.sin(a) * 0.012], [math.cos(a) * 0.03, 0.17 + i * 0.01, math.sin(a) * 0.03]
        g.add(rod(0.004, p0, p1, mt.paint, {'color': c, 'seg': 6, 'bevel': 0.001}))
        g.add(K.m(tc(K.cyl(0.0042, 0.0042, 0.01, {'seg': 6, 'bevel': 0.001}), '#FF8FA8'), mt.paint, {'pos': p1}))
    return g


def deskBell(game):
    mt = M(game)
    g = THREE.Group()
    g.add(K.m(tc(puck(0.05, 0.016, 0.005, 16), '#2A2230'), mt.plastic))
    g.add(K.m(K.lathe([[0, 0], [0.046, 0], [0.044, 0.012], [0.034, 0.03], [0.018, 0.042], [0, 0.045]], {'seg': 18, 'round': 0.006}), mt.chrome, {'pos': [0, 0.016, 0]}))
    g.add(K.m(K.cyl(0.004, 0.004, 0.012, {'seg': 6}), mt.chrome, {'pos': [0, 0.06, 0]}))
    g.add(K.m(K.lathe([[0, 0], [0.008, 0], [0.009, 0.004], [0, 0.007]], {'seg': 10}), mt.chrome, {'pos': [0, 0.071, 0]}))
    return g


def magazine(game):
    atl = atlasMat(game)
    g = THREE.Group()
    g.add(K.m(cell(cbox(0.21, 0.006, 0.28, 0.0015), 2, 0), atl, {'pos': [0, 0.003, 0]}))
    return g


def deskMic(game):
    mt = M(game)
    g = THREE.Group()
    g.add(K.m(tc(puck(0.06, 0.02, 0.008, 16), '#2A2230'), mt.plastic))
    g.add(K.m(K.tube([[0, 0.02, 0], [0, 0.1, 0], [0, 0.18, -0.03], [0, 0.22, -0.09]], 0.006, {'seg': 12, 'radial': 6}), mt.chrome))
    cap = THREE.Group()
    cap.position.set(0, 0.225, -0.1)
    cap.rotation.x = -1.1
    cap.add(K.m(K.lathe([[0, 0], [0.014, 0], [0.022, 0.03], [0.022, 0.06], [0.016, 0.08], [0, 0.082]], {'seg': 12, 'round': 0.005}), mt.chrome))
    cap.add(K.m(tc(K.lathe([[0, 0], [0.0225, 0], [0.0225, 0.022], [0, 0.022]], {'seg': 12}), '#2A2230'), mt.plastic, {'pos': [0, 0.034, 0]}))
    g.add(cap)
    return g


def hairspray(game):
    atl, mt = atlasMat(game), M(game)
    g = THREE.Group()
    g.add(K.m(cell(K.lathe([[0, 0], [0.026, 0], [0.028, 0.006], [0.028, 0.15], [0.024, 0.16], [0, 0.162]], {'seg': 14}), 1, 3), atl))
    g.add(K.m(tc(K.lathe([[0, 0], [0.02, 0], [0.022, 0.03], [0.016, 0.042], [0, 0.044]], {'seg': 12, 'round': 0.004}), '#F4F1E8'), mt.plastic, {'pos': [0, 0.16, 0]}))
    return g


def put(g, sub, pos, rotY=0, rot=None):
    sub.position.set(pos[0], pos[1], pos[2])
    if rot:
        sub.rotation.set(rot[0], rot[1], rot[2])
    else:
        sub.rotation.y = rotY
    g.add(sub)
    return sub


# ------------------------------------------------------------------------------------------ rotary phone
def _phone_rotary(game, opts=None):
    opts = opts or {}
    g = K.prop('phone_rotary')
    g.add(phoneGroup(game, _nn(opts.get('color'), '#E23B3B')))
    g.userData.colliders = []
    g.userData.interact = {'point': [0, 0.12, -0.12], 'radius': 1}
    return K.finish(game, g, {'ao': {'height': 0.02}})


registerProp('phone_rotary', _phone_rotary, {'category': CAT, 'tags': ['tabletop', 'phone', 'newsroom', 'lobby'], 'size': [0.24, 0.17, 0.24], 'desc': 'rotary desk phone with printed dial, handset and coiled cord (opts.color)'})


# --------------------------------------------------------------------------------------------- typewriter
def _typewriter(game, opts=None):
    opts = opts or {}
    g = K.prop('typewriter')
    g.add(typewriterGroup(game, _nn(opts.get('color'), '#E8A92E')))
    g.userData.colliders = []
    return K.finish(game, g, {'ao': {'height': 0.02}})


registerProp('typewriter', _typewriter, {'category': CAT, 'tags': ['tabletop', 'newsroom'], 'size': [0.6, 0.44, 0.4], 'desc': 'chunky 70s electric typewriter, round keys, typed sheet in the platen (opts.color)'})


# ------------------------------------------------------------------------------------------ reporter desk
def _desk_reporter(game, opts=None):
    opts = opts or {}
    g = K.prop('desk_reporter')
    mt, atl = M(game), atlasMat(game)
    steel = _nn(opts.get('color'), '#8FA38A')
    W, D, H = 1.5, 0.76, 0.76
    lam = K.mat(game, 'lacquer', '#ffffff', {'map': K.tex.wood('#A8743F', {'dark': 0.3})})
    # top: wood-grain laminate over a brushed aluminum edge band
    g.add(K.m(K.box(W, 0.034, D, 0.012, {'uv': 1.2, 'swap': True}), lam, {'pos': [0, H - 0.017, 0]}))
    g.add(K.m(K.box(W + 0.012, 0.022, D + 0.012, 0.008), mt.chrome, {'pos': [0, H - 0.04, 0]}))
    # steel carcass: right pedestal (3 drawers), left end panel, modesty panel, pencil drawer
    pw = 0.44
    px = W / 2 - pw / 2 - 0.01
    g.add(K.m(tc(K.box(pw, H - 0.1, D - 0.04, 0.02), steel), mt.paint, {'pos': [px, (H - 0.1) / 2 + 0.05, 0]}))
    g.add(K.m(tc(K.box(0.05, H - 0.1, D - 0.04, 0.02), steel), mt.paint, {'pos': [-W / 2 + 0.035, (H - 0.1) / 2 + 0.05, 0]}))
    g.add(K.m(tc(K.box(W - pw - 0.08, 0.42, 0.025, 0.01), steel), mt.paint, {'pos': [-pw / 2 + 0.01, H - 0.3, D / 2 - 0.05]}))
    g.add(K.m(tc(K.box(W - 0.06, 0.012, D - 0.1, 0.004), '#3A2E36'), mt.paint, {'pos': [0, H - 0.052, 0]}))
    dark = THREE.Color(steel).multiplyScalar(0.55).getStyle()
    # recessed plinths
    g.add(K.m(tc(K.box(pw - 0.04, 0.05, D - 0.1, 0.01), dark), mt.paint, {'pos': [px, 0.025, 0]}))
    g.add(K.m(tc(K.box(0.04, 0.05, D - 0.1, 0.01), dark), mt.paint, {'pos': [-W / 2 + 0.035, 0.025, 0]}))
    # drawers: raised fronts + chrome pulls + label cards
    dh = [0.16, 0.16, 0.28]
    y = H - 0.07
    for i, h in enumerate(dh):
        y -= h / 2 + 0.006
        g.add(K.m(tc(K.box(pw - 0.03, h - 0.012, 0.03, 0.012), steel), mt.paint, {'pos': [px, y, -D / 2 + 0.01]}))
        g.add(K.m(K.tube([[-0.07, 0, 0], [-0.065, 0, -0.02], [0.065, 0, -0.02], [0.07, 0, 0]], 0.007, {'seg': 8, 'radial': 5}), mt.chrome, {'pos': [px, y + h * 0.18, -D / 2 - 0.004]}))
        g.add(K.m(cell(cbox(0.07, 0.03, 0.004, 0.001), 1, 2), atl, {'pos': [px, y - h * 0.12, -D / 2 - 0.007]}))
        y -= h / 2 + 0.006
    # pencil drawer
    g.add(K.m(tc(K.box(W - pw - 0.14, 0.07, 0.03, 0.012), steel), mt.paint, {'pos': [-pw / 2 - 0.02, H - 0.09, -D / 2 + 0.01]}))
    g.add(K.m(K.tube([[-0.06, 0, 0], [-0.055, 0, -0.018], [0.055, 0, -0.018], [0.06, 0, 0]], 0.006, {'seg': 8, 'radial': 5}), mt.chrome, {'pos': [-pw / 2 - 0.02, H - 0.09, -D / 2 - 0.004]}))
    # on top: typewriter, phone, papers, legal pad, mug, pencil cup, manila folder, script spike
    top = H
    put(g, typewriterGroup(game, _nn(opts.get('typewriter'), '#E8A92E')), [-0.2, top, -0.04], 0.08)
    put(g, phoneGroup(game, _nn(opts.get('phone'), '#F4F1E8')), [0.52, top, -0.12], -0.35)
    put(g, paperStack(game, 6, 2), [0.18, top, 0.14], math.pi + 0.25)
    put(g, paperStack(game, 3, 5, [3, 3]), [0.5, top, 0.2], math.pi - 0.1)
    g.add(K.m(cell(cbox(0.2, 0.012, 0.28, 0.002), 3, 0), atl, {'pos': [0.2, top + 0.006, -0.2], 'rot': [0, -0.4, 0]}))
    put(g, mugGroup(game), [-0.6, top, 0.18], 2.2)
    put(g, pencilCup(game), [-0.62, top, -0.02], 0)
    g.add(K.m(K.cyl(0.028, 0.03, 0.008, {'seg': 12}), mt.chrome, {'pos': [0.66, top, 0.25]}))
    g.add(K.m(K.cyl(0.0018, 0.0018, 0.13, {'seg': 5, 'bevel': 0.0008}), mt.chrome, {'pos': [0.66, top + 0.008, 0.25]}))
    for i in range(3):
        g.add(K.m(cell(cbox(0.1, 0.002, 0.12, 0.0008), 1, 1), atl, {'pos': [0.66, top + 0.03 + i * 0.02, 0.25], 'rot': [0, i * 0.5, 0]}))
    g.userData.colliders = [{'min': [-W / 2, 0, -D / 2], 'max': [W / 2, H + 0.05, D / 2]}]
    g.userData.interact = None
    return K.finish(game, g)


registerProp('desk_reporter', _desk_reporter, {'category': CAT, 'tags': ['desk', 'newsroom'], 'size': [1.5, 1.1, 0.76], 'desc': 'sage steel tanker desk, wood-grain top: typewriter, rotary phone, papers, legal pad, mug (opts.color/typewriter/phone)', 'hero': True})


# --------------------------------------------------------------------------------------- reception desk
# arcs convex toward -z: P(a, r) = [sin a * r, cz - cos a * r]; sector slab extruded vertically
def arcSector(r0, r1, a0, a1, cz, steps=28):
    pts = []
    for i in range(steps + 1):
        a = lerp(a0, a1, i / steps)
        pts.append([math.sin(a) * r1, -(cz - math.cos(a) * r1)])
    for i in range(steps, -1, -1):
        a = lerp(a0, a1, i / steps)
        pts.append([math.sin(a) * r0, -(cz - math.cos(a) * r0)])
    return pts


def arcSlab(r0, r1, a0, a1, cz, y0, h, o=None):
    o = o or {}
    geo = K.extrude(arcSector(r0, r1, a0, a1, cz, _nn(o.get('steps'), 24)), h, {'bevel': _nn(o.get('bevel'), 0.01), 'round': 0, 'uv': _nn(o.get('uv'), 1.2), 'curveSeg': 4, 'bevelSeg': _nn(o.get('bevelSeg'), 2)})
    geo.rotateX(-math.pi / 2)
    geo.translate(0, y0 + h / 2, 0)
    return geo


def arcP(a, r, cz, y=0):
    return [math.sin(a) * r, y, cz - math.cos(a) * r]


# colliders for a convex-front arc desk: n boxes across x, each from the arc front at its inner edge to zBack
def arcColliders(Ro, cz, xMax, zBack, h, n=5):
    out = []
    for i in range(n):
        x0, x1 = lerp(-xMax, xMax, i / n), lerp(-xMax, xMax, (i + 1) / n)
        xi = min(abs(x0), abs(x1)) * (0 if x0 * x1 < 0 else 1)
        zf = cz - math.sqrt(max(0, Ro * Ro - xi * xi))
        out.append({'min': [float(js_to_fixed(x0, 3)), 0, float(js_to_fixed(zf, 3))], 'max': [float(js_to_fixed(x1, 3)), h, float(js_to_fixed(zBack, 3))]})
    return out


def _desk_reception(game, opts=None):
    opts = opts or {}
    g = K.prop('desk_reception')
    mt, atl = M(game), atlasMat(game)
    orange = _nn(opts.get('top'), '#E3662B')
    Ro, cz = 4.0, 3.43
    am = math.asin(1.8 / Ro)
    # recessed dark plinth + brass kick rail
    g.add(K.m(tc(arcSlab(Ro - 0.7, Ro - 0.08, -am, am, cz, 0, 0.08, {'bevelSeg': 1, 'steps': 16}), '#3A2418'), mt.lacquer))
    g.add(K.m(K.tube([arcP(lerp(-am, am, i / 24), Ro - 0.07, cz, 0.05) for i in range(25)], 0.012, {'seg': 36, 'radial': 5}), mt.brass))
    # walnut front skin
    g.add(K.m(arcSlab(Ro - 0.07, Ro - 0.01, -am, am, cz, 0.08, 0.9, {'bevel': 0.008, 'uv': 0.8, 'bevelSeg': 1, 'steps': 16}), mt.walnut))
    # vertical walnut ribs (fluted front)
    nR = 26
    for i in range(nR):
        a = lerp(-am + 0.02, am - 0.02, (i + 0.5) / nR)
        if abs(a) < 0.07:
            continue  # badge
        rib = K.m(K.uvScale(cbox(0.07, 0.8, 0.035, 0.012).clone(), 0.1, 1.2), mt.walnut)
        rib.position.set(*arcP(a, Ro + 0.005, cz, 0.12 + 0.4))
        rib.rotation.y = -a
        g.add(rib)
    # orange accent band + bullnose laminate counter
    g.add(K.m(tc(arcSlab(Ro - 0.02, Ro + 0.035, -am, am, cz, 0.93, 0.07, {'bevel': 0.012}), '#B5472A'), mt.lacquer))
    g.add(K.m(tc(arcSlab(Ro - 0.36, Ro + 0.06, -am - 0.004, am + 0.004, cz, 1.0, 0.055, {'bevel': 0.02, 'bevelSeg': 2}), orange), mt.lacquer))
    # step riser + lower work surface behind (receptionist side)
    g.add(K.m(arcSlab(Ro - 0.37, Ro - 0.31, -am, am, cz, 0.72, 0.28, {'bevel': 0.006, 'uv': 0.8, 'bevelSeg': 1, 'steps': 16}), mt.walnut))
    g.add(K.m(tc(arcSlab(Ro - 0.86, Ro - 0.06, -am, am, cz, 0.7, 0.04, {'bevel': 0.012}), '#F0A060'), mt.lacquer))
    # drawer pedestals under the work surface
    for s in (-1, 1):
        a = s * (am - 0.12)
        ped = K.m(K.box(0.42, 0.62, 0.5, 0.014, {'uv': 1.2, 'swap': True}), mt.walnut)
        ped.position.set(*arcP(a, Ro - 0.5, cz, 0.39))
        ped.rotation.y = -a
        g.add(ped)
        for k in range(3):
            pull = K.m(K.box(0.12, 0.018, 0.02, 0.008), mt.brass)
            pull.position.set(*arcP(a, Ro - 0.5 + 0.26, cz, 0.62 - k * 0.19))
            pull.rotation.y = -a
            g.add(pull)
    # rounded end drums: walnut with orange caps
    for s in (-1, 1):
        p = arcP(s * am, Ro - 0.2, cz)
        g.add(K.m(K.uvScale(K.cyl(0.21, 0.19, 1.0, {'seg': 20, 'bevel': 0.02}).clone(), 2, 1), mt.walnut, {'pos': [p[0], 0, p[2]]}))
        g.add(K.m(tc(puck(0.235, 0.055, 0.02, 20), orange), mt.lacquer, {'pos': [p[0], 1.0, p[2]]}))
    # WZTV 13 badge on the front
    bp = arcP(0, Ro + 0.03, cz, 0.56)
    g.add(K.m(tc(puck(0.25, 0.04, 0.015, 24), '#F4F1E8'), mt.lacquer, {'pos': bp, 'rot': [math.pi / 2, 0, 0]}))
    g.add(K.m(cell(THREE.CircleGeometry(0.235, 32), 3, 1), atl, {'pos': [bp[0], bp[1], bp[2] - 0.041], 'rot': [0, math.pi, 0]}))
    # counter items: bell (toy), TV WEEKLY (Baron), nameplate, pen on a chain, sign-in pad
    cy = 1.055
    bell = put(g, deskBell(game), arcP(0.12, Ro - 0.15, cz, cy), 0)
    bell.userData.noMerge = True
    mag = put(g, magazine(game), arcP(-0.2, Ro - 0.17, cz, cy), 0.35)
    mag.userData.noMerge = True
    np_ = K.m(cell(taperS(K.box(0.3, 0.07, 0.05, 0.008), {'axis': 'y', 'k': 0.5}), 2, 1), atl)
    np_.position.set(*arcP(-0.02, Ro - 0.1, cz, cy + 0.035))
    np_.rotation.set(0, 0, 0)
    g.add(np_)
    g.add(K.m(cell(cbox(0.24, 0.01, 0.18, 0.002), 1, 1), atl, {'pos': arcP(0.26, Ro - 0.16, cz, cy + 0.005), 'rot': [0, 0.2, 0]}))
    g.add(K.m(K.tube([arcP(0.3, Ro - 0.2, cz, cy + 0.01), arcP(0.31, Ro - 0.1, cz, cy + 0.02), arcP(0.33, Ro - 0.15, cz, cy + 0.012)], 0.003, {'seg': 8, 'radial': 4}), mt.chrome))
    # work surface: switchboard, phone, rolodex, mug
    wy = 0.74
    sb = THREE.Group()
    sb.add(K.m(tc(K.box(0.62, 0.1, 0.36, 0.02), '#6B5A4A'), mt.plastic, {'pos': [0, 0.05, 0]}))
    panel = THREE.Group()
    panel.position.set(0, 0.2, 0.12)
    panel.rotation.x = 0.5
    panel.add(K.m(tc(K.box(0.62, 0.26, 0.08, 0.02), '#6B5A4A'), mt.plastic))
    panel.add(K.m(cell(cbox(0.56, 0.22, 0.004, 0.001), 0, 1), atl, {'pos': [0, 0, -0.042], 'rot': [0, 0, 0]}))
    sb.add(panel)
    sb.add(K.m(tc(K.box(0.56, 0.02, 0.18, 0.008), '#2A2230'), mt.plastic, {'pos': [0, 0.11, -0.07]}))
    cords = [['#E23B3B', -0.2], ['#F4E03A', -0.08], ['#2F5BD3', 0.05], ['#52D24A', 0.18]]
    for c, x in cords:
        sb.add(K.m(tc(K.tube([[x, 0.13, -0.1], [x + 0.02, 0.2, -0.16], [x * 0.6, 0.26, -0.02], [x * 0.5, 0.25, 0.08]], 0.005, {'seg': 10, 'radial': 4}), c), mt.plastic))
        sb.add(K.m(tc(K.cyl(0.009, 0.009, 0.03, {'seg': 8}), c), mt.plastic, {'pos': [x, 0.12, -0.1]}))
    put(g, sb, arcP(-0.24, Ro - 0.6, cz, wy), 0.24 + math.pi)
    phone = put(g, phoneGroup(game, '#F6E7C8'), arcP(0.05, Ro - 0.62, cz, wy), math.pi - 0.1)
    del phone
    rolo = THREE.Group()
    rolo.add(K.m(tc(K.box(0.16, 0.03, 0.12, 0.01), '#2A2230'), mt.plastic, {'pos': [0, 0.015, 0]}))
    for i in range(9):
        rolo.add(K.m(cell(cbox(0.12, 0.08, 0.002, 0.0008), 1, 1), atl, {'pos': [0, 0.075, -0.04 + i * 0.01], 'rot': [-0.5 + i * 0.12, 0, 0]}))
    rolo.add(K.m(K.tube([[-0.07, 0.03, 0], [-0.07, 0.09, 0], [0.07, 0.09, 0], [0.07, 0.03, 0]], 0.004, {'seg': 10, 'radial': 4}), mt.chrome))
    put(g, rolo, arcP(0.24, Ro - 0.6, cz, wy), math.pi - 0.24)
    put(g, mugGroup(game), arcP(0.36, Ro - 0.72, cz, wy), 1.2)
    g.userData.parts = {'bell': bell, 'magazine': mag}
    zf, zb = cz - Ro - 0.06, cz - math.cos(am) * (Ro - 0.86)
    del zf
    g.userData.colliders = arcColliders(Ro + 0.06, cz, 2.0, zb, 1.1, 5)
    g.userData.interact = {'point': arcP(0.12, Ro - 0.15, cz, 1.1), 'radius': 1.2}
    return K.finish(game, g)


registerProp('desk_reception', _desk_reception, {'category': CAT, 'tags': ['desk', 'lobby', 'reception'], 'size': [4.0, 1.1, 1.15], 'desc': 'curved walnut reception desk: fluted front, orange laminate counter, WZTV 13 badge, switchboard, bell (parts.bell), TV WEEKLY (parts.magazine)', 'hero': True})


# ------------------------------------------------------------------------------------------- anchor desk
def _desk_anchor(game, opts=None):
    opts = opts or {}
    g = K.prop('desk_anchor')
    mt, atl = M(game), atlasMat(game)
    Ro = 3.6
    cz, am = Ro - 0.42, math.asin(1.3 / Ro)
    brown = '#5A3A22'
    # recessed kick + chocolate front + racing stripes
    g.add(K.m(tc(arcSlab(Ro - 0.62, Ro - 0.1, -am, am, cz, 0, 0.07), '#2A1C14'), mt.lacquer))
    g.add(K.m(tc(arcSlab(Ro - 0.08, Ro, -am, am, cz, 0.07, 0.68, {'bevel': 0.012}), brown), mt.lacquer))
    for i, c in enumerate(['#E3662B', '#E8A92E', '#B5472A']):
        g.add(K.m(tc(arcSlab(Ro - 0.01, Ro + 0.016, -am, am, cz, 0.44 + i * 0.075, 0.05, {'bevel': 0.01}), c), mt.lacquer))
    # back modesty panel (anchors' knees side stays open) + walnut bullnose top with a cream inset
    g.add(K.m(arcSlab(Ro - 0.7, Ro + 0.05, -am - 0.006, am + 0.006, cz, 0.75, 0.06, {'bevel': 0.024, 'bevelSeg': 3, 'uv': 1.1}), mt.walnut))
    g.add(K.m(tc(arcSlab(Ro - 0.55, Ro - 0.12, -am + 0.05, am - 0.05, cz, 0.806, 0.006, {'bevel': 0.002}), '#F6E7C8'), mt.paint))
    # rounded orange end drums
    for s in (-1, 1):
        p = arcP(s * am, Ro - 0.33, cz)
        g.add(K.m(tc(K.cyl(0.3, 0.3, 0.75, {'seg': 28, 'bevel': 0.02}), '#E3662B'), mt.lacquer, {'pos': [p[0], 0.0, p[2]]}))
        g.add(K.m(tc(K.cyl(0.27, 0.27, 0.07, {'seg': 28}), '#2A1C14'), mt.lacquer, {'pos': [p[0], 0, p[2]]}))
        g.add(K.m(puck(0.33, 0.06, 0.024, 28), mt.walnut, {'pos': [p[0], 0.75, p[2]]}))
    # ACTION 13 NEWS logo panel (proud, rounded)
    lp = arcP(0, Ro + 0.035, cz, 0.43)
    g.add(K.m(tc(K.box(0.66, 0.52, 0.05, 0.05), '#E8A92E'), mt.lacquer, {'pos': lp}))
    g.add(K.m(cell(cbox(0.58, 0.44, 0.01, 0.003), 0, 2), atl, {'pos': [lp[0], lp[1], lp[2] - 0.026]}))
    # desk dressing: scripts, mic, mug, pencil, toppled hairspray (parts.hairspray)
    ty = 0.812
    put(g, paperStack(game, 5, 7, [3, 2]), arcP(-0.12, Ro - 0.35, cz, ty), 0.1)
    put(g, paperStack(game, 3, 9, [3, 2]), arcP(0.16, Ro - 0.38, cz, ty), -0.2)
    put(g, deskMic(game), arcP(-0.02, Ro - 0.3, cz, ty), math.pi)
    put(g, mugGroup(game), arcP(0.3, Ro - 0.5, cz, ty), 2.4)
    g.add(rod(0.0035, arcP(0.02, Ro - 0.44, cz, ty + 0.004), arcP(0.07, Ro - 0.42, cz, ty + 0.004), mt.paint, {'color': '#F4E03A', 'seg': 6, 'bevel': 0.001}))
    hs = put(g, hairspray(game), arcP(-0.3, Ro - 0.42, cz, ty + 0.028), 0, [0, 0.7, math.pi / 2])
    hs.userData.noMerge = True
    g.userData.parts = {'hairspray': hs}
    zf, zb = cz - Ro - 0.06, cz - math.cos(am) * (Ro - 0.7) + 0.02
    del zf
    g.userData.colliders = arcColliders(Ro + 0.05, cz, 1.55, zb, 0.9, 5)
    return K.finish(game, g)


registerProp('desk_anchor', _desk_anchor, {'category': CAT, 'tags': ['desk', 'newsroom', 'anchor'], 'size': [3.2, 0.9, 1.1], 'desc': 'curved chocolate anchor desk, orange/gold racing stripes, ACTION 13 NEWS panel, mic, scripts, toppled hairspray (parts.hairspray)', 'hero': True})


# ------------------------------------------------------------------------------------ surfboard coffee table
def surfShape(w, d, n=28):
    pts = []
    for i in range(n):
        a = (i / n) * TAU
        c, s = math.cos(a), math.sin(a)
        x, y = js_sign(c) * math.pow(abs(c), 0.7) * w / 2, js_sign(s) * math.pow(abs(s), 0.85) * d / 2
        pts.append([x, y])
    return pts


def _table_coffee(game, opts=None):
    g = K.prop('table_coffee')
    mt = M(game)
    W, D, H = 1.3, 0.6, 0.4
    # surfboard top: teak lacquer slab over a darker walnut lip
    top = K.extrude(surfShape(W, D), 0.04, {'bevel': 0.014, 'uv': 1.4, 'bevelSeg': 2})
    top.rotateX(-math.pi / 2)
    g.add(K.m(top, mt.teak, {'pos': [0, H - 0.02, 0]}))
    lip = K.extrude(surfShape(W - 0.06, D - 0.06, 24), 0.03, {'bevel': 0.008, 'uv': 1.4, 'bevelSeg': 1})
    lip.rotateX(-math.pi / 2)
    g.add(K.m(tc(lip, '#6A4428'), mt.teak, {'pos': [0, H - 0.05, 0]}))
    # splayed tapered legs with brass ferrules
    for sx, sz in [[-1, -1], [1, -1], [-1, 1], [1, 1]]:
        tx, tz, fx, fz = sx * 0.4, sz * 0.16, sx * 0.47, sz * 0.22
        g.add(rod(0.024, [fx, 0.02, fz], [tx, H - 0.05, tz], mt.teak, {'rb': 0.014, 'seg': 10}))
        g.add(K.m(THREE.CylinderGeometry(0.015, 0.016, 0.03, 8, 1).translate(0, 0.015, 0), mt.brass, {'pos': [fx, 0, fz]}))
    # slatted magazine shelf
    for i in range(5):
        g.add(K.m(K.uvScale(cbox(0.84, 0.018, 0.06, 0.005).clone(), 1, 0.2), mt.teak, {'pos': [0, 0.16, -0.14 + i * 0.07]}))
    for s in (-1, 1):
        g.add(K.m(K.box(0.04, 0.03, 0.4, 0.01, {'uv': 1.4, 'swap': True}), mt.teak, {'pos': [s * 0.4, 0.14, 0]}))
    # dressing: magazines on the shelf, orange glass ashtray, gold bowl of wax fruit
    put(g, magazine(game), [-0.18, 0.169, 0.02], 0.3)
    put(g, magazine(game), [-0.14, 0.175, 0.0], -0.2)
    g.add(K.m(tc(K.lathe([[0, 0], [0.07, 0], [0.085, 0.03], [0.07, 0.032], [0.05, 0.012], [0, 0.012]], {'seg': 14, 'round': 0.006, 'steps': 1}), '#E3662B'), mt.lacquer, {'pos': [0.38, H, 0.08]}))
    g.add(K.m(tc(K.lathe([[0, 0], [0.05, 0], [0.13, 0.06], [0.14, 0.075], [0.125, 0.07], [0.04, 0.012], [0, 0.012]], {'seg': 16, 'round': 0.006, 'steps': 1}), '#E8A92E'), mt.lacquer, {'pos': [-0.2, H, -0.02]}))
    for x, z, r, c in [[-0.23, -0.03, 0.045, '#E23B3B'], [-0.16, 0.0, 0.042, '#FF8A2A'], [-0.2, 0.04, 0.04, '#F4E03A']]:
        g.add(K.m(tc(sph(r, 10, 7), c), mt.lacquer, {'pos': [x, H + 0.05, z]}))
    grapes = [[-0.14, -0.05], [-0.12, -0.03], [-0.15, -0.02], [-0.13, -0.065]]
    for i, (x, z) in enumerate(grapes):
        g.add(K.m(tc(sph(0.016, 6, 4), '#6B3A6E'), mt.lacquer, {'pos': [x, H + 0.075 + (i % 2) * 0.01, z]}))
    g.userData.colliders = [{'min': [-W / 2, 0, -D / 2], 'max': [W / 2, H + 0.05, D / 2]}]
    return K.finish(game, g)


registerProp('table_coffee', _table_coffee, {'category': CAT, 'tags': ['table', 'lobby', 'green_room', 'telly_home'], 'size': [1.3, 0.48, 0.6], 'desc': 'teak surfboard coffee table, splayed legs, slatted magazine shelf, ashtray + wax-fruit bowl'})


# ------------------------------------------------------------------------------------------ tulip side table
def _table_side_tulip(game, opts=None):
    opts = opts or {}
    g = K.prop('table_side_tulip')
    mt = M(game)
    col = _nn(opts.get('color'), '#D4521E')
    g.add(K.m(tc(K.lathe([[0, 0], [0.24, 0], [0.245, 0.02], [0.2, 0.05], [0.08, 0.12], [0.045, 0.24], [0.04, 0.4], [0.07, 0.48], [0.1, 0.5], [0, 0.5]], {'round': 0.02, 'seg': 28}), '#F4F1E8'), mt.lacquer))
    g.add(K.m(tc(puck(0.3, 0.035, 0.012, 32), '#F4F1E8'), mt.lacquer, {'pos': [0, 0.5, 0]}))
    g.add(K.m(tc(THREE.CircleGeometry(0.28, 32), col), mt.paint, {'pos': [0, 0.536, 0], 'rot': [-math.pi / 2, 0, 0]}))
    g.userData.colliders = [{'min': [-0.3, 0, -0.3], 'max': [0.3, 0.54, 0.3]}]
    return K.finish(game, g)


registerProp('table_side_tulip', _table_side_tulip, {'category': CAT, 'tags': ['table', 'lobby', 'green_room'], 'size': [0.6, 0.54, 0.6], 'desc': 'space-age white tulip side table with an orange laminate top (opts.color)'})


# ------------------------------------------------------------------------------------------ drum side table
def _table_side_drum(game, opts=None):
    g = K.prop('table_side_drum')
    mt = M(game)
    g.add(K.m(K.uvScale(K.lathe([[0, 0], [0.2, 0], [0.225, 0.08], [0.235, 0.24], [0.225, 0.4], [0.2, 0.48], [0, 0.48]], {'round': 0.015, 'seg': 24}).clone(), 3, 1.5), mt.walnut))
    for y in (0.07, 0.24, 0.41):
        g.add(K.m(K.tube(ring(0.238 if y == 0.24 else 0.226, 24, y), 0.009, {'seg': 24, 'radial': 5, 'closed': True}), mt.brass))
    g.add(K.m(tc(puck(0.25, 0.03, 0.012, 24), '#5A3A22'), mt.lacquer, {'pos': [0, 0.48, 0]}))
    g.add(K.m(tc(THREE.CircleGeometry(0.22, 24), '#3A2A30'), mt.lacquer, {'pos': [0, 0.5105, 0], 'rot': [-math.pi / 2, 0, 0]}))
    # coaster + a paperback
    g.add(K.m(tc(puck(0.045, 0.006, 0.002, 14), '#E8A92E'), mt.paint, {'pos': [0.08, 0.511, -0.06]}))
    g.add(K.m(tc(cbox(0.11, 0.022, 0.17, 0.003), '#2E8C8C'), mt.paint, {'pos': [-0.06, 0.522, 0.04], 'rot': [0, 0.5, 0]}))
    g.userData.colliders = [{'min': [-0.24, 0, -0.24], 'max': [0.24, 0.52, 0.24]}]
    return K.finish(game, g)


registerProp('table_side_drum', _table_side_drum, {'category': CAT, 'tags': ['table', 'lobby', 'green_room', 'telly_home'], 'size': [0.5, 0.53, 0.5], 'desc': 'walnut drum side table with brass hoops and a smoked top'})


# ------------------------------------------------------------------------------------------------ lamps
# glowing part helper: lit -> glow material, unlit -> toon material of the same tint (rooms swap on Sign-On)
def glowMat(game, lit, color, intensity, unlit='#D8CFC0'):
    return K.glow(game, color, intensity) if lit else K.mat(game, 'plastic', unlit)


def marbleTex():
    def draw(ctx, w, h, rand):
        ctx.fillStyle = '#F2EEE6'
        ctx.fillRect(0, 0, w, h)
        for i in range(40):
            ctx.fillStyle = '#E6E0D4' if rand() < 0.5 else '#FAF8F2'
            ctx.globalAlpha = 0.5
            ctx.beginPath()
            ctx.arc(rand() * w, rand() * h, 6 + rand() * 30, 0, TAU)
            ctx.fill()
        ctx.globalAlpha = 1
        ctx.lineCap = 'round'
        for i in range(9):
            ctx.strokeStyle = '#B8B0A6' if i % 3 else '#8E857C'
            ctx.lineWidth = 0.6 + rand() * 2
            ctx.globalAlpha = 0.5 + rand() * 0.4
            ctx.beginPath()
            x, y = rand() * w, -10
            ctx.moveTo(x, y)
            while y < h + 10:
                x += (rand() - 0.5) * 40
                y += 10 + rand() * 30
                ctx.lineTo(x, y)
            ctx.stroke()
        ctx.globalAlpha = 1
    return K.tex.canvas('furn_marble', 256, 256, draw)


# ----------------------------------------------------------------------------------------------- arc lamp
def _lamp_arc(game, opts=None):
    opts = opts or {}
    g = K.prop('lamp_arc')
    mt = M(game)
    lit = _nn(opts.get('lit'), True)
    marble = K.mat(game, 'ceramic', '#ffffff', {'map': marbleTex()})
    bz, sz, sy = 0.62, -0.7, 1.52
    # marble block base with a chrome collar
    g.add(K.m(K.box(0.34, 0.36, 0.3, 0.035, {'uv': 2}), marble, {'pos': [0, 0.18, bz]}))
    g.add(K.m(K.lathe([[0, 0], [0.035, 0], [0.03, 0.06], [0.018, 0.08], [0, 0.08]], {'seg': 14, 'round': 0.008}), mt.chrome, {'pos': [0, 0.34, bz]}))
    # sweeping chrome arc (telescoping: a thicker lower section)
    arc = [[0, 0.4, bz], [0, 1.0, bz + 0.02], [0, 1.55, bz - 0.08], [0, 1.9, bz - 0.36], [0, 2.04, bz - 0.72], [0, 2.0, bz - 1.02], [0, 1.88, sz + 0.06], [0, 1.74, sz], [0, sy + 0.14, sz]]
    g.add(K.m(K.tube(arc[0:4], 0.017, {'seg': 20, 'radial': 8}), mt.chrome))
    g.add(K.m(K.tube(arc[3:], 0.012, {'seg': 40, 'radial': 7}), mt.chrome))
    g.add(span(K.cyl(0.022, 0.022, 0.05, {'seg': 10}), mt.chrome, [0, 1.87, bz - 0.33], [0, 1.93, bz - 0.4]))
    # brushed dome shade with a rolled rim, perforation ring and glowing underside
    shade = THREE.Group()
    shade.position.set(0, sy, sz)
    dome = K.lathe([[0.2, 0], [0.205, 0.012], [0.19, 0.06], [0.15, 0.14], [0.08, 0.2], [0.02, 0.22], [0, 0.22]], {'seg': 28})
    shade.add(K.m(dome, K.mat(game, 'metal', '#ffffff', {'map': K.tex.brushed('#D8DDE4'), 'side': THREE.DoubleSide})))
    shade.add(K.m(K.tube(ring(0.203, 28, 0.004), 0.01, {'seg': 28, 'radial': 5, 'closed': True}), mt.chrome))
    for i in range(16):
        a = (i / 16) * TAU
        shade.add(K.m(tc(sph(0.008, 6, 4), '#2A2230'), mt.plastic, {'pos': [math.sin(a) * 0.123, 0.172, math.cos(a) * 0.123]}))
    bulb = K.m(K.lathe([[0, 0], [0.03, 0.005], [0.05, 0.04], [0.045, 0.07], [0, 0.08]], {'seg': 14}), glowMat(game, lit, PAL.tungsten, 4), {'pos': [0, 0.03, 0]})
    bulb.userData.noMerge = True
    bulb.userData.noOcclude = True
    shade.add(bulb)
    inner = K.m(THREE.CircleGeometry(0.19, 24), glowMat(game, lit, '#FFE2B0', 1.4, '#E8E0D0'), {'pos': [0, 0.14, 0], 'rot': [math.pi / 2, 0, 0]})
    inner.userData.noOcclude = True
    shade.add(inner)
    g.add(shade)
    g.userData.parts = {'glow': bulb}
    g.userData.lightAnchors = [{'pos': [0, sy - 0.1, sz], 'color': PAL.tungsten, 'intensity': 1.8, 'distance': 4.5}] if lit else []
    g.userData.colliders = [{'min': [-0.16, 0, bz - 0.14], 'max': [0.16, 0.45, bz + 0.14]}]
    return K.finish(game, g)


registerProp('lamp_arc', _lamp_arc, {'category': CAT, 'tags': ['lamp', 'light', 'lobby', 'green_room', 'telly_home'], 'size': [0.42, 2.1, 1.55], 'desc': 'chrome arc floor lamp on a marble block, brushed dome shade (light anchor; base-only collider; opts.lit)'})


# ------------------------------------------------------------------------------------------ tripod lamp
def _lamp_tripod(game, opts=None):
    opts = opts or {}
    g = K.prop('lamp_tripod')
    mt = M(game)
    lit = _nn(opts.get('lit'), True)
    col = _nn(opts.get('color'), '#E8A92E')
    shadeMat = K.mat(game, 'fabric', '#ffffff', {'map': K.tex.weave(NEUTRAL, {'pattern': 'plain', 'scale': 3}), 'side': THREE.DoubleSide, 'emissive': '#FFB060' if lit else '#000000', 'emissiveIntensity': 0.3 if lit else 0, 'rim': 0.15, 'rimPower': 3})
    hub = 0.95
    for i in range(3):
        a = (i / 3) * TAU + 0.5
        f, t = [math.sin(a) * 0.3, 0.02, math.cos(a) * 0.3], [math.sin(a) * 0.04, hub, math.cos(a) * 0.04]
        g.add(rod(0.026, f, t, mt.walnut, {'rb': 0.017, 'seg': 10}))
        g.add(K.m(THREE.CylinderGeometry(0.018, 0.02, 0.028, 8, 1).translate(0, 0.014, 0), mt.brass, {'pos': [f[0], 0, f[2]]}))
    # round walnut tray between the legs
    g.add(K.m(puck(0.2, 0.025, 0.01, 24), mt.walnut, {'pos': [0, 0.46, 0]}))
    g.add(K.m(K.tube(ring(0.2, 24, 0.472), 0.007, {'seg': 24, 'radial': 4, 'closed': True}), mt.brass))
    g.add(K.m(K.lathe([[0, 0], [0.06, 0], [0.066, 0.04], [0.04, 0.09], [0, 0.1]], {'round': 0.012, 'seg': 16}), mt.brass, {'pos': [0, hub - 0.05, 0]}))
    g.add(K.m(K.cyl(0.014, 0.014, 0.44, {'seg': 10}), mt.brass, {'pos': [0, hub + 0.04, 0]}))
    by = 1.46
    bulb = K.m(K.lathe([[0, 0], [0.018, 0.005], [0.04, 0.045], [0.045, 0.075], [0.03, 0.11], [0, 0.12]], {'seg': 14}), glowMat(game, lit, PAL.tungsten, 4), {'pos': [0, by - 0.06, 0]})
    bulb.userData.noMerge = True
    bulb.userData.noOcclude = True
    g.add(bulb)
    # mustard drum shade with orange bands, glowing lining
    y0, y1, r0, r1 = 1.34, 1.72, 0.3, 0.27
    shell = THREE.LatheGeometry([THREE.Vector2(r0, 0), THREE.Vector2(r1, y1 - y0)], 48)
    K.uvScale(shell, 9, 1.2)
    g.add(K.m(tc(shell, col), shadeMat, {'pos': [0, y0, 0]}))
    for y, r, c in [[0.04, r0 - 0.003, '#E3662B'], [0.075, r0 - 0.005, '#B5472A'], [y1 - y0 - 0.05, r1 + 0.002, '#E3662B']]:
        band = THREE.LatheGeometry([THREE.Vector2(r + 0.004, 0), THREE.Vector2(r + 0.004 - 0.002, 0.022)], 48)
        g.add(K.m(tc(band, c), shadeMat, {'pos': [0, y0 + y, 0]}))
    lin = K.m(THREE.LatheGeometry([THREE.Vector2(r1 - 0.006, y1 - y0 - 0.004), THREE.Vector2(r0 - 0.006, 0.004)], 28), glowMat(game, lit, '#FFD9A0', 1.1, '#E8DCC4'), {'pos': [0, y0, 0]})
    lin.userData.noOcclude = True
    g.add(lin)
    g.add(K.m(K.tube(ring(r0 + 0.006, 24, y0), 0.011, {'seg': 28, 'radial': 4, 'closed': True}), mt.brass))
    g.add(K.m(K.tube(ring(r1 + 0.006, 24, y1), 0.01, {'seg': 28, 'radial': 4, 'closed': True}), mt.brass))
    for i in range(3):
        a = (i / 3) * TAU
        g.add(K.m(K.tube([[0, by + 0.1, 0], [math.sin(a) * r1 * 0.6, y1 - 0.01, math.cos(a) * r1 * 0.6], [math.sin(a) * r1, y1, math.cos(a) * r1]], 0.005, {'seg': 8, 'radial': 4}), mt.brass))
    g.userData.parts = {'glow': bulb}
    g.userData.lightAnchors = [{'pos': [0, by, 0], 'color': PAL.tungsten, 'intensity': 1.8, 'distance': 4.5}] if lit else []
    g.userData.colliders = [{'min': [-0.24, 0, -0.24], 'max': [0.24, 1.72, 0.24]}]
    return K.finish(game, g)


registerProp('lamp_tripod', _lamp_tripod, {'category': CAT, 'tags': ['lamp', 'light', 'lobby', 'newsroom', 'telly_home'], 'size': [0.64, 1.74, 0.64], 'desc': 'walnut tripod floor lamp with a tray, mustard drum shade with orange bands (light anchor; opts.color, opts.lit)'})


# ------------------------------------------------------------------------------------ tension pole lamp
def _lamp_pole(game, opts=None):
    opts = opts or {}
    g = K.prop('lamp_pole')
    mt = M(game)
    lit = _nn(opts.get('lit'), True)
    H = _nn(opts.get('h'), 2.4)
    g.add(K.m(tc(puck(0.08, 0.03, 0.012, 12), '#2A2230'), mt.rubber))
    g.add(K.m(K.cyl(0.018, 0.018, H - 0.06, {'seg': 10}), mt.chrome, {'pos': [0, 0.03, 0]}))
    g.add(K.m(tc(puck(0.07, 0.03, 0.012, 12), '#2A2230'), mt.rubber, {'pos': [0, H - 0.03, 0]}))
    g.add(K.m(K.cyl(0.024, 0.024, 0.12, {'seg': 10}), mt.chrome, {'pos': [0, H - 0.5, 0]}))
    inside = K.mat(game, 'paint', '#F6E7C8')
    cones = [[0.9, '#E3662B', 0.4, -0.5], [1.35, '#E8A92E', 2.5, 0.2], [1.8, '#8C9A3A', 4.4, -0.3]]
    bulbs = []
    for y, c, a, tilt in cones:
        arm = THREE.Group()
        arm.position.set(0, y, 0)
        arm.rotation.y = a
        arm.add(K.m(K.cyl(0.026, 0.026, 0.05, {'seg': 10}), mt.chrome, {'pos': [0, -0.025, 0]}))
        arm.add(K.m(K.tube([[0, 0, 0], [0, 0.03, -0.1], [0, 0.02, -0.15]], 0.008, {'seg': 8, 'radial': 5}), mt.chrome))
        hd = THREE.Group()
        hd.position.set(0, 0.02, -0.17)
        hd.rotation.x = math.pi * 0.5 + tilt
        cone = K.lathe([[0.12, 0], [0.118, 0.012], [0.07, 0.14], [0.04, 0.2], [0.038, 0.22], [0, 0.22]], {'seg': 18, 'round': 0.01, 'steps': 1})
        hd.add(K.m(tc(cone, c), mt.lacquer, {'pos': [0, -0.2, 0]}))
        hd.add(K.m(flipGeo(K.lathe([[0.112, 0.01], [0.066, 0.135], [0.034, 0.195], [0, 0.2]], {'seg': 18})), inside, {'pos': [0, -0.2, 0]}))
        b = K.m(sph(0.034, 10, 8), glowMat(game, lit, PAL.tungsten, 3.5), {'pos': [0, -0.16, 0]})
        b.userData.noOcclude = True
        b.userData.noMerge = True
        hd.add(b)
        bulbs.append(b)
        arm.add(hd)
        g.add(arm)
    g.userData.parts = {'glow': bulbs[1], 'glow0': bulbs[0], 'glow2': bulbs[2]}
    g.userData.lightAnchors = [{'pos': [0, 1.35, 0], 'color': PAL.tungsten, 'intensity': 1.8, 'distance': 4.5}] if lit else []
    g.userData.colliders = [{'min': [-0.1, 0, -0.1], 'max': [0.1, H, 0.1]}]
    return K.finish(game, g)


registerProp('lamp_pole', _lamp_pole, {'category': CAT, 'tags': ['lamp', 'light', 'green_room', 'lobby'], 'size': [0.5, 2.4, 0.5], 'desc': 'floor-to-ceiling tension pole lamp with orange / mustard / avocado enamel cones (opts.h = ceiling height, opts.lit)'})


# ------------------------------------------------------------------------------------------ globe pendant
def _lamp_globe_pendant(game, opts=None):
    opts = opts or {}
    g = K.prop('lamp_globe_pendant')
    mt = M(game)
    lit = _nn(opts.get('lit'), True)
    drop = _nn(opts.get('drop'), 0.9)
    R = _nn(opts.get('r'), 0.2)
    g.add(K.m(K.lathe([[0, 0], [0.09, 0], [0.085, -0.02], [0.03, -0.045], [0, -0.05]], {'seg': 20, 'round': 0.008}), mt.brass))
    # chain: alternating flat links
    nL = max(3, js_round((drop - 0.12) / 0.05))
    for i in range(nL):
        l = K.m(THREE.TorusGeometry(0.014, 0.004, 4, 10), mt.brass, {'pos': [0, -0.06 - i * 0.05 * (drop - 0.12) / (nL * 0.05), 0], 'rot': [0, (i % 2) * math.pi / 2, 0]})
        l.scale.set(1, 1.7, 1)
        g.add(l)
    cy = -drop - R + 0.02
    g.add(K.m(K.lathe([[0, 0], [0.07, 0], [0.075, 0.02], [0.05, 0.06], [0.02, 0.09], [0, 0.1]], {'seg': 18, 'round': 0.01}), mt.brass, {'pos': [0, cy + R - 0.035, 0]}))
    globe = K.m(sph(R, 24, 16), K.mat(game, 'ceramic', '#FFF1D8', {'emissive': '#FFD9A0', 'emissiveIntensity': 0.95, 'rim': 0.5, 'rimColor': '#FFFFFF'} if lit else {}), {'pos': [0, cy, 0]})
    globe.userData.noMerge = True
    globe.userData.noOcclude = True
    g.add(globe)
    g.add(K.m(K.lathe([[0, 0], [0.028, 0], [0.024, 0.02], [0, 0.026]], {'seg': 12}), mt.brass, {'pos': [0, cy - R - 0.012, 0]}))
    g.userData.parts = {'glow': globe}
    g.userData.lightAnchors = [{'pos': [0, cy, 0], 'color': PAL.tungsten, 'intensity': 2.2, 'distance': 6}] if lit else []
    g.userData.colliders = []
    return K.finish(game, g, {'ao': {'floor': False, 'height': 0}})


registerProp('lamp_globe_pendant', _lamp_globe_pendant, {'category': CAT, 'tags': ['ceiling', 'lamp', 'light', 'lobby'], 'size': [0.4, 1.3, 0.4], 'desc': 'opal glass globe pendant on a brass chain (ceiling origin; opts.drop, opts.r, opts.lit)'})


# ------------------------------------------------------------------------------------------------ lava lamp
def _lamp_lava(game, opts=None):
    opts = opts or {}
    g = K.prop('lamp_lava')
    mt = M(game)
    lit = _nn(opts.get('lit'), True)
    wax = _nn(opts.get('color'), '#FF3B6A')

    def drawBase(ctx, w, h, rand):
        gr = ctx.createLinearGradient(0, 0, 0, h)
        gr.addColorStop(0, '#F2CF6A')
        gr.addColorStop(1, '#A87830')
        ctx.fillStyle = gr
        ctx.fillRect(0, 0, w, h)
        ctx.fillStyle = '#3A1E2A'
        for i in range(6):
            x, y = 20 + i * 43, 64 + (-14 if i % 2 else 14)
            ctx.beginPath()
            for k in range(10):
                a, r = (k / 10) * TAU - math.pi / 2, 6 if k % 2 else 14
                ctx.lineTo(x + math.cos(a) * r, y + math.sin(a) * r)
            ctx.fill()
    starTex = K.tex.canvas('furn_lava_base', 256, 128, drawBase)
    gold = K.mat(game, 'brass', '#ffffff', {'map': starTex})
    g.add(K.m(K.lathe([[0, 0], [0.11, 0], [0.11, 0.012], [0.07, 0.15], [0.058, 0.16], [0, 0.16]], {'seg': 24, 'round': 0.006}), gold))
    # tapered bottle: liquid (translucent glow) + blobs (parts.blobs, animatable)
    bottle = [[0.056, 0], [0.075, 0.1], [0.07, 0.18], [0.046, 0.3], [0.034, 0.33], [0, 0.33]]
    liquid = K.m(K.lathe(bottle, {'seg': 24}), K.glow(game, '#FF9A3A', 0.62, {'transparent': True, 'opacity': 0.82}) if lit else K.mat(game, 'plastic', '#C8A070', {'transparent': True, 'opacity': 0.85}), {'pos': [0, 0.16, 0]})
    liquid.userData.noOcclude = True
    liquid.userData.noMerge = True
    g.add(liquid)
    blobs = THREE.Group()
    blobs.position.set(0, 0.16, 0)
    blobs.userData.noMerge = True
    wm = K.glow(game, wax, 1.25) if lit else K.mat(game, 'plastic', wax)
    for x, y, z, r, sy in [[0.0, 0.035, 0, 0.05, 0.55], [0.012, 0.13, 0.01, 0.028, 1.3], [-0.015, 0.21, -0.008, 0.02, 1.0], [0.004, 0.27, 0.004, 0.014, 1.2]]:
        b = K.m(sph(r, 12, 8), wm, {'pos': [x, y, z], 'scale': [1, sy, 1]})
        b.userData.noOcclude = True
        blobs.add(b)
    g.add(blobs)
    g.add(K.m(K.lathe([[0.036, 0], [0.034, 0.03], [0.022, 0.06], [0.01, 0.07], [0, 0.072]], {'seg': 20, 'round': 0.006}), gold, {'pos': [0, 0.48, 0]}))
    g.userData.parts = {'glow': liquid, 'blobs': blobs}
    g.userData.lightAnchors = [{'pos': [0, 0.35, 0], 'color': wax, 'intensity': 1.2, 'distance': 3}] if lit else []
    g.userData.colliders = []
    return K.finish(game, g, {'ao': {'height': 0.02}})


registerProp('lamp_lava', _lamp_lava, {'category': CAT, 'tags': ['tabletop', 'lamp', 'light', 'green_room'], 'size': [0.22, 0.55, 0.22], 'desc': 'lava lamp: gold star-cut base, glowing amber liquid, pink wax blobs (parts.blobs to animate; opts.color, opts.lit)'})


# ------------------------------------------------------------------------------------ fluorescent panel
def _light_fluoro_panel(game, opts=None):
    opts = opts or {}
    g = K.prop('light_fluoro_panel')
    mt = M(game)
    lit = _nn(opts.get('lit'), True)
    W, D = _nn(opts.get('w'), 1.22), _nn(opts.get('d'), 0.61)

    def drawPrism(ctx, w, h, rand):
        ctx.fillStyle = '#F4FAF0'
        ctx.fillRect(0, 0, w, h)
        for y in range(0, h, 16):
            for x in range(0, w, 16):
                gr = ctx.createRadialGradient(x + 8, y + 8, 1, x + 8, y + 8, 10)
                gr.addColorStop(0, '#FFFFFF')
                gr.addColorStop(1, '#C8D8C8')
                ctx.fillStyle = gr
                ctx.beginPath()
                ctx.moveTo(x + 8, y)
                ctx.lineTo(x + 16, y + 8)
                ctx.lineTo(x + 8, y + 16)
                ctx.lineTo(x, y + 8)
                ctx.fill()
    prism = K.tex.canvas('furn_prism', 128, 128, drawPrism)
    g.add(K.m(tc(K.box(W, 0.07, D, 0.012), '#EDEAE2'), mt.paint, {'pos': [0, -0.035, 0]}))
    lens = K.m(K.uvScale(THREE.PlaneGeometry(W - 0.07, D - 0.07).clone(), W * 6, D * 6), K.glow(game, '#E8F5E1', 1.25, {'map': prism}) if lit else K.mat(game, 'plastic', '#E4EAE0', {'map': prism}), {'pos': [0, -0.073, 0], 'rot': [math.pi / 2, 0, 0]})
    lens.userData.noMerge = True
    lens.userData.noOcclude = True
    g.add(lens)
    # frame lip
    for s in (-1, 1):
        g.add(K.m(tc(K.box(W, 0.012, 0.04, 0.004), '#DCD8CE'), mt.paint, {'pos': [0, -0.074, s * (D / 2 - 0.02)]}))
        g.add(K.m(tc(K.box(0.04, 0.012, D - 0.06, 0.004), '#DCD8CE'), mt.paint, {'pos': [s * (W / 2 - 0.02), -0.074, 0]}))
    g.userData.parts = {'glow': lens}
    g.userData.lightAnchors = [{'pos': [0, -0.4, 0], 'color': '#E8F5E1', 'intensity': 2.2, 'distance': 6, 'flicker': bool(K._truthy(opts.get('flicker')))}] if lit else []
    g.userData.colliders = []
    return K.finish(game, g, {'ao': {'floor': False, 'height': 0}})


registerProp('light_fluoro_panel', _light_fluoro_panel, {'category': CAT, 'tags': ['ceiling', 'light', 'newsroom', 'master_control'], 'size': [1.22, 0.08, 0.61], 'desc': '2x4 fluorescent troffer with a prismatic lens (ceiling origin; opts.w/d, opts.lit, opts.flicker)'})


# ------------------------------------------------------------------------------------------------ can light
def _light_can(game, opts=None):
    opts = opts or {}
    g = K.prop('light_can')
    mt = M(game)
    lit = _nn(opts.get('lit'), True)
    recessed = opts.get('style') == 'recessed'
    col = _nn(opts.get('color'), '#F4F1E8')
    h = 0.02 if recessed else 0.2
    if not recessed:
        g.add(K.m(tc(puck(0.07, 0.02, 0.006, 16), col), mt.lacquer, {'pos': [0, -0.02, 0]}))
        g.add(K.m(tc(K.lathe([[0.085, 0], [0.09, 0.01], [0.09, h - 0.03], [0.08, h - 0.02], [0.02, h - 0.02], [0, h - 0.02]], {'seg': 22, 'round': 0.006}), col), mt.lacquer, {'pos': [0, -h, 0]}))
    # trim ring + black stepped baffle + bulb face
    g.add(K.m(tc(K.lathe([[0.075, 0], [0.105, 0], [0.108, 0.01], [0.09, 0.016], [0.075, 0.014]], {'seg': 22}), col if recessed else '#C9CED6'), mt.lacquer if recessed else mt.chrome, {'pos': [0, -h - 0.004, 0]}))
    g.add(K.m(tc(K.lathe([[0.075, 0.014], [0.068, 0.03], [0.07, 0.034], [0.062, 0.05], [0.064, 0.054], [0.056, 0.07]], {'seg': 20}), '#2A2230'), mt.plastic, {'pos': [0, -h - 0.004, 0], 'rot': [0, 0, 0]}))
    face = K.m(THREE.CircleGeometry(0.056, 18), glowMat(game, lit, PAL.tungsten, 3.2), {'pos': [0, -h + 0.064, 0], 'rot': [math.pi / 2, 0, 0]})
    face.userData.noMerge = True
    face.userData.noOcclude = True
    g.add(face)
    g.userData.parts = {'glow': face}
    g.userData.lightAnchors = [{'pos': [0, -h - 0.3, 0], 'color': PAL.tungsten, 'intensity': 1.8, 'distance': 5}] if lit else []
    g.userData.colliders = []
    return K.finish(game, g, {'ao': {'floor': False, 'height': 0}})


registerProp('light_can', _light_can, {'category': CAT, 'tags': ['ceiling', 'light', 'lobby', 'green_room'], 'size': [0.22, 0.22, 0.22], 'desc': 'surface-mounted can light with a chrome trim and black baffle (ceiling origin; opts.style=recessed, opts.color, opts.lit)'})

# ============================================================================================ review scenes
registerScene('furn_ceiling', {
    'floor': 'tile', 'wall': '#D8C9A8', 'room': [5.2, 4.2], 'wallH': 3.2,
    'items': [
        {'id': 'lamp_globe_pendant', 'pos': [-1.6, 2.8, 0.6]},
        {'id': 'lamp_globe_pendant', 'pos': [-0.9, 2.8, 1.2], 'opts': {'drop': 0.5, 'r': 0.15}},
        {'id': 'light_fluoro_panel', 'pos': [0.4, 2.8, 0.7]},
        {'id': 'light_fluoro_panel', 'pos': [0.4, 2.8, 1.6], 'opts': {'lit': False}},
        {'id': 'light_can', 'pos': [1.7, 2.8, 0.4]},
        {'id': 'light_can', 'pos': [1.7, 2.8, 1.3], 'opts': {'style': 'recessed'}},
        {'id': 'lamp_globe_pendant', 'pos': [-0.2, 2.8, 1.9], 'opts': {'lit': False}},
    ],
    'cam': {'pos': [0, 1.1, -1.9], 'target': [0, 2.35, 1.1], 'fov': 64}, 'hemi': 0.8,
})
