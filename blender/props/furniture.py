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
