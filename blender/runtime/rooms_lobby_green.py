"""DEAD AIR — room-local geometry of src/world/rooms/lobby.js + src/world/rooms/green_room.js as Blender assets.

The JS rooms build part of their dressing at runtime with the prop kit (local builders that are not registered
props: lg_* in lobby.js, gm_* in green_room.js) and add loose meshes straight under the area root (floor papers,
fallen letters, glass lettering, moonlight slats, cables, signs). Everything static goes here (SPEC §4/§5, ROOMS
context); the behaviour (placement, colliders, light anchors, power wave, toys, level.objects) is
godot/scripts/world/rooms/lobby.gd / green_room.gd.

Line-by-line ports (same names, numbers, canvas drawing and seeds):
  lobby.js      CELLS + atlasTex() ('rooms.lg.atlas.v1', 1024^2) + atlasMats(game), cellPlane(), decal(),
                velvetRopes(), wallShelf(), exitSign(), plinth(), signPost(), announcerDesk(), doormat(),
                moonSlatsTex() + the moonSlats() mesh
  green_room.js GCELLS + gmAtlasTex() ('rooms.gm.atlas.v1', 512^2) + gmAtlas(), gPlane(), mirrorMat(), bulbMats(),
                bulbGeo(), vanity(), boaGeo(), makeupChair(), directorChair(), wallTV(), coatRail(), jacketShape(),
                garmentRack(), trunkAndHead(), hifi(), phoneShelf(), barStool(), ensureColors(), the leak strip
  newsroom.js   stdMats(), tc(), ribbon() (imported by green_room.js; private copies here)

Outputs (godot/assets/runtime/rooms_lobby/ and rooms_green_room/; textures -> godot/assets/textures/ as the kit does):
  rooms_lobby/lg_velvet_ropes.glb    velvetRopes(game, [[4.22,4.72],[4.22,3.72],[5.5,3.72],[6.72,3.72]])
  rooms_lobby/lg_wall_shelf.glb      wallShelf(game, 0.66, 0.5)
  rooms_lobby/lg_exit.glb            exitSign(game, am) (lobby x2, green room x2)
  rooms_lobby/lg_plinth.glb          plinth(game, am, 1.22)
  rooms_lobby/lg_sign_post.glb       signPost(game, card 'sign_see_yourself')
  rooms_lobby/lg_announcer_desk.glb  announcerDesk(game, am)
  rooms_lobby/lg_doormat.glb         doormat(game, am) (x2)
  rooms_lobby/lobby_dressing.glb     the loose meshes lobby.build() adds under the area root, in world space:
                                     booth glass lettering, the camera cable, 8 floor papers, the fallen SIGN OFF
                                     letters ('letter_0'..'letter_6', letter_board.letters) and the three moonlight
                                     slat meshes ('moon_slats_0'..'moon_slats_2', userData {onMat, offMat} = the two
                                     glow materials the power wave swaps)
  rooms_green_room/gm_*.glb          vanity (len 4.8, parts.bulbs, lampMats), makeup chair, director chairs
                                     (gm_director_chair__roxy / gm_director_chair__talent), wall TV (screen), coat
                                     rail, garment rack, trunk + Hootie head, hi-fi, phone shelf, stool
  rooms_green_room/green_room_dressing.glb   the loose meshes green_room.build() adds under the area root
                                     (bottle caps, decals, leak strip, MAKE-UP / QUIET PLEASE / CALL BOARD signs and
                                     backers, cup, the make-up cable, 'moon_slats_0')
Each local builder's root is its K.prop group (userData: colliders, parts, screens, lampMats …), exported in local
space: the room script places it with kit.put exactly like the JS.

Run: python3 blender/build_all.py --only runtime (build_all calls build(save_blend)), or standalone:
     cd /home/user/dead-air && python3 blender/runtime/rooms_lobby_green.py [--save-blend]
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
from dalib.kit import THREE, PAL  # noqa: E402
from dalib.mathutils3 import JSObj, js_str  # noqa: E402
from dalib.scene import Mesh  # noqa: E402

REPO = os.path.dirname(_BLENDER)
OUT_LOBBY = os.path.join(REPO, 'godot', 'assets', 'runtime', 'rooms_lobby')
OUT_GREEN = os.path.join(REPO, 'godot', 'assets', 'runtime', 'rooms_green_room')
BLEND_OUT = os.path.join(_BLENDER, 'out')

PI = math.pi
TAU = PI * 2
HP = PI / 2


def hash_(n):
    s = math.sin(n * 127.1 + 311.7) * 43758.5453
    return s - math.floor(s)


def _cell(c, i):
    return c[i] if len(c) > i else 1


# ============================================================================================ lobby.js: atlas
# One shared 1024^2 decal atlas (8x8 cells of 128 px) for every small printed thing of the lobby + green room:
# fallen letters, papers, signs, plaques, the doormat, glass lettering (one material -> one draw call).
CELLS = {
    'S': [0, 0], 'I': [1, 0], 'G': [2, 0], 'N': [3, 0], 'O': [4, 0], 'F': [5, 0], 'exit': [6, 0, 2, 1],
    'script': [0, 1], 'pledge': [1, 1], 'memo': [2, 1], 'polaroid': [3, 1], 'paper': [4, 1, 2, 1], 'ticket': [6, 1],
    'star': [7, 1],
    'mat': [0, 2, 4, 2], 'plaque': [4, 2, 4, 1], 'glassAnnounce': [4, 3, 4, 1],
    'makeup': [0, 4, 4, 1], 'callboard': [4, 4, 4, 1], 'quiet': [0, 5, 4, 1], 'towel': [4, 5, 2, 1], 'cue': [6, 5, 2, 1],
    'script2': [0, 6], 'cup': [1, 6], 'boa': [2, 6], 'cucumber': [3, 6], 'fan': [4, 6], 'wig': [5, 6], 'sheet': [6, 6],
    'sheet2': [7, 6],
}
FONT_SIGN = '"Bungee", Impact, "Arial Black", sans-serif'
FONT_ROUND = '"Titan One", "Arial Rounded MT Bold", "Arial Black", sans-serif'
FONT_TYPE = '"Courier New", Courier, monospace'
FONT_GROOVY = '"Shrikhand", "Cooper Black", Georgia, serif'


def atlasTex():
    def draw(ctx, W, H, rand):
        ctx.clearRect(0, 0, W, H)
        C = 128

        def at(name):
            c = CELLS[name]
            return [c[0] * C, c[1] * C, _cell(c, 2) * C, _cell(c, 3) * C]

        def rr(x, y, w, h, r):
            ctx.beginPath()
            ctx.roundRect(x, y, w, h, r)

        def text(s, x, y, size, font, fill, o=None):
            o = o or {}
            ctx.save()
            ctx.font = '%spx %s' % (js_str(size), font)
            if o.get('max'):
                sz = size
                while ctx.measureText(s).width > o['max'] and sz > 6:
                    sz *= 0.93
                    ctx.font = '%spx %s' % (js_str(sz), font)
            ctx.textAlign = o.get('align') or 'center'
            ctx.textBaseline = 'middle'
            if o.get('shadow'):
                ctx.fillStyle = o['shadow']
                ctx.fillText(s, x + size * 0.05, y + size * 0.07)
            if o.get('stroke'):
                ctx.lineWidth = o.get('lw') or size * 0.12
                ctx.strokeStyle = o['stroke']
                ctx.lineJoin = 'round'
                ctx.strokeText(s, x, y)
            ctx.fillStyle = fill
            ctx.fillText(s, x, y)
            ctx.restore()

        # fallen changeable letters: white molded plastic with a soft shadow edge
        for L in ['S', 'I', 'G', 'N', 'O', 'F']:
            x, y = at(L)[:2]
            text(L, x + 64, y + 68, 110, FONT_SIGN, '#F7F2E6', {'stroke': '#8C7F6A', 'lw': 8, 'shadow': 'rgba(40,24,40,0.55)'})
        # EXIT face
        x, y, w, h = at('exit')
        ctx.fillStyle = '#5A0F12'
        ctx.fillRect(x, y, w, h)
        rr(x + 8, y + 8, w - 16, h - 16, 14)
        ctx.fillStyle = '#7A1418'
        ctx.fill()
        text('EXIT', x + w / 2, y + h / 2 + 4, 86, FONT_SIGN, '#FFE0D0', {'stroke': '#FF4A30', 'lw': 10})

        # papers
        def paper(name, bg, lines, header, hc):
            x, y, w, h = at(name)
            rr(x + 6, y + 4, w - 12, h - 8, 4)
            ctx.fillStyle = bg
            ctx.fill()
            if header:
                text(header, x + w / 2, y + 20, 15, FONT_SIGN, hc or '#5A3A22', {'max': w - 24})
            ctx.fillStyle = 'rgba(60,40,50,0.55)'
            for i in range(lines):
                ctx.fillRect(x + 16, y + 36 + i * 11, (w - 32) * (0.55 + rand() * 0.45), 3)
        paper('script', '#F6F0E0', 8, 'SPOOKTACULAR', '#B5472A')
        paper('script2', '#FFF8E8', 8, 'RUNDOWN', '#2F5BD3')
        paper('sheet', '#F2ECDC', 9, 'CALL SHEET', '#5A3A22')
        paper('sheet2', '#EDF2E0', 9, 'PLEDGES', '#2E8C8C')
        paper('memo', '#FFE680', 5, 'MEMO', '#7A4A2A')
        x, y, w, h = at('pledge')
        rr(x + 8, y + 18, w - 16, h - 36, 6)
        ctx.fillStyle = '#FFB6C8'
        ctx.fill()
        text('PLEDGE', x + w / 2, y + 40, 22, FONT_SIGN, '#8E2A2E')
        text('$13', x + w / 2, y + 74, 34, FONT_ROUND, '#E23B3B')
        ctx.fillStyle = 'rgba(90,40,60,0.5)'
        ctx.fillRect(x + 22, y + 96, w - 44, 3)
        x, y, w, h = at('polaroid')
        rr(x + 14, y + 8, w - 28, h - 16, 3)
        ctx.fillStyle = '#FBF8F1'
        ctx.fill()
        g = ctx.createLinearGradient(0, y + 16, 0, y + 90)
        g.addColorStop(0, '#6B3A6E')
        g.addColorStop(1, '#E3662B')
        ctx.fillStyle = g
        ctx.fillRect(x + 22, y + 16, w - 44, 76)
        ctx.fillStyle = '#F6E7C8'
        ctx.beginPath()
        ctx.arc(x + 64, y + 50, 16, 0, TAU)
        ctx.fill()
        x, y, w, h = at('paper')
        ctx.fillStyle = '#EDE6D2'
        ctx.fillRect(x + 4, y + 6, w - 8, h - 12)
        text('THE TRI-COUNTY TRIBUNE', x + w / 2, y + 22, 16, FONT_GROOVY, '#2A2231', {'max': w - 20})
        ctx.fillStyle = '#2A2231'
        ctx.fillRect(x + 10, y + 34, w - 20, 2)
        text('TELETHON $13 SHORT!', x + w / 2, y + 52, 20, FONT_SIGN, '#2A2231', {'max': w - 24})
        ctx.fillStyle = '#9A9284'
        ctx.fillRect(x + 12, y + 66, 70, 48)
        ctx.fillStyle = 'rgba(40,30,40,0.45)'
        for i in range(7):
            ctx.fillRect(x + 92, y + 68 + i * 7, w - 106, 3)
        x, y, w, h = at('ticket')
        rr(x + 8, y + 36, w - 16, h - 72, 6)
        ctx.fillStyle = '#F4E03A'
        ctx.fill()
        text('ADMIT ONE', x + w / 2, y + 56, 16, FONT_SIGN, '#8E2A2E')
        text('WZTV 13', x + w / 2, y + 76, 14, FONT_ROUND, '#2F5BD3')
        x, y = at('star')[:2]
        ctx.fillStyle = '#FFC23A'
        ctx.strokeStyle = '#A8701A'
        ctx.lineWidth = 5
        ctx.beginPath()
        for i in range(10):
            a = -PI / 2 + i * PI / 5
            r = 22 if i % 2 else 54
            ctx.lineTo(x + 64 + math.cos(a) * r, y + 66 + math.sin(a) * r)
        ctx.closePath()
        ctx.fill()
        ctx.stroke()
        # doormat (rubber, WZTV 13 WELCOME)
        x, y, w, h = at('mat')
        rr(x + 6, y + 6, w - 12, h - 12, 26)
        ctx.fillStyle = '#3B2A30'
        ctx.fill()
        rr(x + 22, y + 22, w - 44, h - 44, 18)
        ctx.fillStyle = '#4E3840'
        ctx.fill()
        ctx.strokeStyle = 'rgba(0,0,0,0.25)'
        ctx.lineWidth = 3
        for i in range(26):
            ctx.beginPath()
            ctx.moveTo(x + 30 + i * 18, y + 30)
            ctx.lineTo(x + 30 + i * 18, y + h - 30)
            ctx.stroke()
        ctx.fillStyle = PAL.wztvBlue
        ctx.beginPath()
        ctx.arc(x + 118, y + 128, 70, 0, TAU)
        ctx.fill()
        ctx.lineWidth = 12
        ctx.strokeStyle = PAL.channelRed
        ctx.stroke()
        text('13', x + 118, y + 132, 80, FONT_SIGN, '#F4F1E8')
        text('WZTV', x + 330, y + 104, 74, FONT_SIGN, '#E8A92E', {'shadow': 'rgba(0,0,0,0.4)'})
        text('WELCOME', x + 330, y + 170, 38, FONT_ROUND, '#F6E7C8')
        # brass plaque for the studio-tour exhibit
        x, y, w, h = at('plaque')
        g = ctx.createLinearGradient(0, y, 0, y + h)
        g.addColorStop(0, '#FFE9A8')
        g.addColorStop(0.5, '#E0B04A')
        g.addColorStop(1, '#A8761C')
        rr(x + 6, y + 10, w - 12, h - 20, 14)
        ctx.fillStyle = g
        ctx.fill()
        ctx.lineWidth = 4
        ctx.strokeStyle = '#7A5210'
        ctx.stroke()
        text('STUDIO TOUR', x + w / 2, y + 44, 34, FONT_SIGN, '#4A2E08')
        text('RCA TK-41 · THE FIRST COLOR CAMERA OF WZTV · 1954', x + w / 2, y + 84, 18, FONT_ROUND, '#5A3A0A',
             {'max': w - 40})
        # gold vinyl lettering for the booth glass (transparent bg)
        x, y, w, h = at('glassAnnounce')
        text('ANNOUNCE', x + w / 2, y + 52, 64, FONT_GROOVY, '#FFD27A', {'stroke': '#8A5A20', 'lw': 6})
        text('· WZTV 13 ·', x + w / 2, y + 104, 26, FONT_SIGN, '#FFD27A')
        # MAKE-UP sign, CALL BOARD header, QUIET PLEASE
        x, y, w, h = at('makeup')
        rr(x + 4, y + 8, w - 8, h - 16, 40)
        ctx.fillStyle = '#F6E7C8'
        ctx.fill()
        ctx.lineWidth = 8
        ctx.strokeStyle = '#E3662B'
        ctx.stroke()
        text('Make-Up', x + w / 2, y + h / 2 + 6, 70, FONT_GROOVY, '#B5472A', {'shadow': 'rgba(90,40,20,0.3)'})
        x, y, w, h = at('callboard')
        rr(x + 4, y + 16, w - 8, h - 32, 12)
        ctx.fillStyle = '#2A2231'
        ctx.fill()
        text('CALL BOARD', x + w / 2, y + h / 2 + 3, 54, FONT_SIGN, '#FFC23A')
        x, y, w, h = at('quiet')
        rr(x + 4, y + 14, w - 8, h - 28, 16)
        ctx.fillStyle = '#E23B3B'
        ctx.fill()
        text('QUIET PLEASE', x + w / 2, y + h / 2 + 3, 50, FONT_SIGN, '#FBF8F1')
        x, y, w, h = at('towel')
        ctx.fillStyle = '#F4F1E8'
        ctx.fillRect(x, y, w, h)
        for c, yy in [[PAL.burntOrange, 18], [PAL.harvestGold, 34], [PAL.avocado, 50]]:
            ctx.fillStyle = c
            ctx.fillRect(x, y + yy, w, 10)
            ctx.fillRect(x, y + h - yy - 10, w, 10)
        text('WZTV', x + w / 2, y + h / 2, 30, FONT_SIGN, PAL.wztvBlue)
        x, y, w, h = at('cue')
        rr(x + 6, y + 10, w - 12, h - 20, 8)
        ctx.fillStyle = '#FBF8F1'
        ctx.fill()
        text('STATION ID', x + w / 2, y + 42, 26, FONT_SIGN, '#E23B3B')
        text('"This is WZTV, Channel 13..."', x + w / 2, y + 80, 15, FONT_TYPE, '#2A2231', {'max': w - 24})
        # cup lid, boa fluff, cucumber, fan, wig
        x, y = at('cup')[:2]
        ctx.fillStyle = '#F6E7C8'
        ctx.beginPath()
        ctx.arc(x + 64, y + 64, 50, 0, TAU)
        ctx.fill()
        ctx.fillStyle = '#5A3A22'
        ctx.beginPath()
        ctx.arc(x + 64, y + 64, 40, 0, TAU)
        ctx.fill()
        x, y = at('boa')[:2]
        for i in range(80):
            ctx.fillStyle = '#FF5FA2' if rand() < 0.5 else '#FF8CC0'
            ctx.beginPath()
            ex = x + 20 + rand() * 88
            ey = y + 20 + rand() * 88
            ctx.ellipse(ex, ey, 12, 5, rand() * 3, 0, TAU)
            ctx.fill()
        x, y = at('cucumber')[:2]
        ctx.fillStyle = '#3F7A2A'
        ctx.beginPath()
        ctx.arc(x + 64, y + 64, 56, 0, TAU)
        ctx.fill()
        ctx.fillStyle = '#CFE8A0'
        ctx.beginPath()
        ctx.arc(x + 64, y + 64, 48, 0, TAU)
        ctx.fill()
        ctx.fillStyle = '#E8F6C8'
        for i in range(7):
            a = i / 7 * TAU
            ctx.beginPath()
            ctx.ellipse(x + 64 + math.cos(a) * 22, y + 64 + math.sin(a) * 22, 7, 4, a, 0, TAU)
            ctx.fill()
        x, y = at('fan')[:2]
        ctx.fillStyle = '#6B3A6E'
        ctx.beginPath()
        ctx.moveTo(x + 64, y + 110)
        ctx.arc(x + 64, y + 110, 96, -PI * 0.85, -PI * 0.15)
        ctx.closePath()
        ctx.fill()
        ctx.strokeStyle = '#FFC23A'
        ctx.lineWidth = 3
        for i in range(8):
            a = -PI * 0.85 + i * PI * 0.1
            ctx.beginPath()
            ctx.moveTo(x + 64, y + 110)
            ctx.lineTo(x + 64 + math.cos(a) * 94, y + 110 + math.sin(a) * 94)
            ctx.stroke()
        x, y = at('wig')[:2]
        for i in range(60):
            ctx.fillStyle = '#2A1A12' if rand() < 0.5 else '#4A2E1E'
            ctx.beginPath()
            cx = x + 20 + rand() * 88
            cy = y + 20 + rand() * 88
            ctx.arc(cx, cy, 10 + rand() * 8, 0, TAU)
            ctx.fill()
    return K.tex.canvas('rooms.lg.atlas.v1', 1024, 1024, draw, {'repeat': False, 'fonts': True})


def atlasMats(game):
    map_ = atlasTex()
    map_.anisotropy = 8
    return JSObj(
        decal=K.mat(game, 'plastic', '#ffffff', {'map': map_, 'alphaTest': 0.5, 'side': THREE.DoubleSide}),
        paper=K.mat(game, 'paint', '#ffffff', {'map': map_, 'alphaTest': 0.5, 'side': THREE.DoubleSide}),
        glow=K.glow(game, '#ffffff', 1.5, {'map': map_}),
    )


# PlaneGeometry (w x h, facing +z) textured with an atlas cell. flat = lying on the floor (facing +y, text top -> -z).
def cellPlane(name, w, h, opts=None):
    opts = opts or {}
    flat = opts.get('flat', False)
    face = opts.get('face', '+z')
    c = CELLS[name]
    g = THREE.PlaneGeometry(w, h)
    K.uvRect(g, c[0] / 8, 1 - (c[1] + _cell(c, 3)) / 8, (c[0] + _cell(c, 2)) / 8, 1 - c[1] / 8)
    if flat:
        g.rotateX(-PI / 2)
    elif face == '-z':
        g.rotateY(PI)
    return g


# Small flat paper / letter on the floor or a tabletop (y = surface height).
def decal(mat, name, w, h, pos, rotY=0):
    m = Mesh(cellPlane(name, w, h, {'flat': True}), mat)
    m.position.set(pos[0], pos[1] + 0.004, pos[2])
    m.rotation.y = rotY
    m.castShadow = False
    m.receiveShadow = True
    return m


# ================================================================================================ local props
# Brass stanchions + red velvet ropes through [[x,z],...] (local), axis-aligned segments get thin colliders.
def velvetRopes(game, posts):
    g = K.prop('lg_velvet_ropes')
    brass = K.mat(game, 'brass', '#C8963C')
    velvet = K.mat(game, 'felt', '#B0203A')
    H = 0.92
    for x, z in posts:
        g.add(K.m(K.lathe([[0, 0], [0.16, 0], [0.165, 0.02], [0.12, 0.045], [0.04, 0.065], [0, 0.066]],
                          {'seg': 22, 'round': 0.008}), brass, {'pos': [x, 0, z]}))
        g.add(K.m(K.cyl(0.026, 0.03, H - 0.06, {'seg': 14}), brass, {'pos': [x, 0.05, z]}))
        g.add(K.m(K.lathe([[0, 0], [0.042, 0], [0.05, 0.03], [0.044, 0.06], [0.024, 0.08], [0.032, 0.1], [0.02, 0.125],
                           [0, 0.13]], {'seg': 16, 'round': 0.006}), brass, {'pos': [x, H - 0.03, z]}))
    colliders = []
    for i in range(len(posts) - 1):
        ax, az = posts[i]
        bx, bz = posts[i + 1]
        pts = []
        for k in range(11):
            t = k / 10
            pts.append([ax + (bx - ax) * t, H - 0.07 - math.sin(PI * t) * 0.17, az + (bz - az) * t])
        g.add(K.m(K.tube(pts, 0.024, {'seg': 22, 'radial': 8}), velvet))
        for x, z, s in [[ax, az, 1], [bx, bz, -1]]:
            d = math.hypot(bx - ax, bz - az) or 1
            g.add(K.m(K.cyl(0.03, 0.03, 0.05, {'seg': 10}).clone().rotateZ(PI / 2).rotateY(-math.atan2(bz - az, bx - ax)),
                      brass, {'pos': [x + ((bx - ax) / d) * 0.05 * s, H - 0.075, z + ((bz - az) / d) * 0.05 * s]}))
        colliders.append({'min': [min(ax, bx) - 0.07, 0, min(az, bz) - 0.07], 'max': [max(ax, bx) + 0.07, H, max(az, bz) + 0.07]})
    g.userData.colliders = colliders
    return K.finish(game, g, {'ao': {'res': 40, 'height': 0.08}})


# Walnut wall shelf on two brass brackets; back at local z = 0 (wall plane), top at y = 0.
def wallShelf(game, w=0.62, d=0.46):
    g = K.prop('lg_wall_shelf')
    walnut = K.mat(game, 'walnut', '#ffffff', {'map': K.tex.wood(PAL.walnut, {'dark': 0.35})})
    brass = K.mat(game, 'brass', '#C8963C')
    g.add(K.m(K.box(w, 0.04, d, 0.012, {'uv': 1.5}), walnut, {'pos': [0, -0.02, -d / 2]}))
    for s in [-1, 1]:
        g.add(K.m(K.box(0.03, 0.22, 0.02, 0.006), brass, {'pos': [s * (w / 2 - 0.08), -0.15, -0.012]}))
        g.add(K.m(K.tube([[0, -0.25, -0.02], [0, -0.12, -d * 0.45], [0, -0.04, -d * 0.7]], 0.012, {'seg': 10, 'radial': 5}),
                  brass, {'pos': [s * (w / 2 - 0.08), 0, 0]}))
    g.userData.colliders = []
    return K.finish(game, g, {'ao': {'floor': False, 'height': 0}})


# Lit EXIT box (emergency circuit: always on). Back at local z = 0, faces -z, bottom at y = 0.
def exitSign(game, am):
    g = K.prop('lg_exit')
    shell = K.mat(game, 'plastic', '#E8E0CC')
    chrome = K.mat(game, 'chrome', '#A8B0BA')
    g.add(K.m(K.box(0.56, 0.24, 0.1, 0.03), shell, {'pos': [0, 0.12, -0.05]}))
    face = K.m(cellPlane('exit', 0.5, 0.19, {'face': '-z'}), am.glow, {'pos': [0, 0.12, -0.102]})
    face.userData.noOcclude = True
    g.add(face)
    for s in [-1, 1]:
        g.add(K.m(K.cyl(0.012, 0.012, 0.12, {'seg': 8}), chrome, {'pos': [s * 0.2, 0.24, -0.05]}))
    g.userData.colliders = []
    return K.finish(game, g, {'ao': {'floor': False, 'height': 0}})


# ============================================================================================ lobby builders
def plinth(game, am, h=1.22):
    g = K.prop('lg_plinth')
    walnut = K.mat(game, 'walnut', '#ffffff', {'map': K.tex.wood(PAL.walnut, {'dark': 0.35})})
    lac = K.mat(game, 'lacquer', '#2A1D2A')
    g.add(K.m(K.box(0.62, 0.1, 0.56, 0.03, {'uv': 1.5}), lac, {'pos': [0, 0.05, 0]}))
    g.add(K.m(K.box(0.5, h - 0.2, 0.44, 0.04, {'uv': 1.5, 'swap': True}), walnut, {'pos': [0, 0.1 + (h - 0.2) / 2, 0]}))
    g.add(K.m(K.box(0.64, 0.1, 0.58, 0.03, {'uv': 1.5}), lac, {'pos': [0, h - 0.05, 0]}))
    for y in [0.34, h - 0.24]:
        g.add(K.m(K.box(0.52, 0.035, 0.46, 0.012), K.mat(game, 'brass', '#C8963C'), {'pos': [0, y, 0]}))
    g.add(K.m(cellPlane('plaque', 0.44, 0.11, {'face': '-z'}), am.decal, {'pos': [0, h - 0.42, -0.226]}))
    g.userData.colliders = [{'min': [-0.32, 0, -0.3], 'max': [0.32, h, 0.3]}]
    return K.finish(game, g, {'ao': {'res': 32}})


def signPost(game, card):
    g = K.prop('lg_sign_post')
    brass = K.mat(game, 'brass', '#C8963C')
    face = K.mat(game, 'lacquer', '#ffffff', {'map': card})
    g.add(K.m(K.lathe([[0, 0], [0.15, 0], [0.155, 0.02], [0.1, 0.04], [0.03, 0.06], [0, 0.06]], {'seg': 20, 'round': 0.008}), brass))
    g.add(K.m(K.cyl(0.022, 0.024, 0.9, {'seg': 12}), brass, {'pos': [0, 0.04, 0]}))
    panel = THREE.Group()
    panel.position.set(0, 1.02, 0)
    panel.rotation.x = 0.3
    panel.add(K.m(K.box(0.66, 0.36, 0.035, 0.012), brass, {'pos': [0, 0, 0.02]}))
    panel.add(K.m(THREE.PlaneGeometry(0.62, 0.31).rotateY(PI), face, {'pos': [0, 0, 0.0]}))
    g.add(panel)
    g.userData.colliders = [{'min': [-0.16, 0, -0.16], 'max': [0.16, 1.2, 0.16]}]
    return K.finish(game, g, {'ao': {'res': 32}})


# Announcer desk with a chunky ribbon microphone, script, cue card and coffee mug. Front (announcer side) = -z.
def announcerDesk(game, am):
    g = K.prop('lg_announcer_desk')
    walnut = K.mat(game, 'walnut', '#ffffff', {'map': K.tex.wood(PAL.walnut, {'dark': 0.35})})
    felt = K.mat(game, 'felt', '#3E6B3A')
    chrome = K.mat(game, 'chrome', '#A8B0BA')
    lac = K.mat(game, 'lacquer', '#ffffff')
    W, D, H = 1.2, 0.58, 0.76
    g.add(K.m(K.box(W, 0.05, D, 0.02, {'uv': 1.5}), walnut, {'pos': [0, H - 0.025, 0]}))
    g.add(K.m(K.box(W - 0.1, 0.012, D - 0.14, 0.004), felt, {'pos': [0, H + 0.006, -0.02]}))
    for s in [-1, 1]:
        g.add(K.m(K.box(0.05, H - 0.05, D - 0.06, 0.015, {'uv': 1.5, 'swap': True}), walnut,
                  {'pos': [s * (W / 2 - 0.04), (H - 0.05) / 2, 0]}))
    g.add(K.m(K.box(W - 0.1, 0.42, 0.03, 0.012, {'uv': 1.5}), walnut, {'pos': [0, H - 0.3, D / 2 - 0.06]}))
    g.add(K.m(K.tint(K.box(W - 0.14, 0.05, 0.03, 0.012).clone(), PAL.burntOrange), lac, {'pos': [0, H - 0.1, D / 2 - 0.08]}))
    # ribbon mic (RCA 44 style, chunky): pill body with a dark grille band, chrome caps, yoke, weighted base
    mic = THREE.Group()
    mic.position.set(0.05, H, 0.02)
    mic.add(K.m(K.lathe([[0, 0], [0.11, 0], [0.115, 0.02], [0.07, 0.045], [0, 0.05]], {'seg': 22, 'round': 0.01}), chrome))
    mic.add(K.m(K.cyl(0.016, 0.016, 0.22, {'seg': 10}), chrome, {'pos': [0, 0.04, 0]}))
    head = THREE.Group()
    head.position.set(0, 0.36, 0)
    head.rotation.x = 0.12
    head.add(K.m(K.lathe([[0, -0.13], [0.05, -0.12], [0.075, -0.07], [0.08, 0], [0.075, 0.07], [0.05, 0.12], [0, 0.13]],
                         {'seg': 22, 'round': 0.01}), K.mat(game, 'metal', '#3A3440', {'rough': 0.5})))
    for y in [-0.085, 0.085]:
        head.add(K.m(K.cyl(0.078, 0.078, 0.03, {'seg': 22, 'bevel': 0.008}), chrome, {'pos': [0, y - 0.015, 0]}))
    head.add(K.m(K.cyl(0.083, 0.083, 0.02, {'seg': 22, 'bevel': 0.006}), K.mat(game, 'lacquer', PAL.channelRed), {'pos': [0, -0.01, 0]}))
    for s in [-1, 1]:
        head.add(K.m(K.box(0.012, 0.16, 0.03, 0.005), chrome, {'pos': [s * 0.095, -0.03, 0]}))
    mic.add(head)
    g.add(mic)
    # script, cue card, mug
    g.add(K.m(cellPlane('script', 0.21, 0.28, {'flat': True}), am.paper, {'pos': [-0.33, H + 0.016, -0.05], 'rot': [0, 0.18, 0]}))
    g.add(K.m(cellPlane('script2', 0.21, 0.28, {'flat': True}), am.paper, {'pos': [-0.36, H + 0.02, -0.02], 'rot': [0, -0.1, 0]}))
    cue = K.m(cellPlane('cue', 0.3, 0.15, {'face': '-z'}), am.decal, {'pos': [0.4, H + 0.09, -0.02], 'rot': [-0.3, -0.2, 0]})
    g.add(cue)
    g.add(K.m(K.tint(K.cyl(0.042, 0.038, 0.1, {'seg': 16}).clone(), PAL.harvestGold), lac, {'pos': [-0.12, H + 0.012, -0.14]}))
    g.add(K.m(K.tube([[-0.08, H + 0.09, -0.14], [-0.055, H + 0.07, -0.14], [-0.055, H + 0.04, -0.14], [-0.08, H + 0.03, -0.14]],
                     0.008, {'seg': 10, 'radial': 5}), lac))
    g.userData.colliders = [{'min': [-W / 2, 0, -D / 2], 'max': [W / 2, H + 0.05, D / 2]}]
    return K.finish(game, g, {'ao': {'res': 40}})


# WZTV rubber doormat (walkable, no collider).
def doormat(game, am):
    g = K.prop('lg_doormat')
    g.add(K.m(K.box(1.3, 0.018, 0.66, 0.008), K.mat(game, 'rubber', '#3B2A30'), {'pos': [0, 0.009, 0]}))
    g.add(K.m(cellPlane('mat', 1.24, 0.6, {'flat': True}), am.paper, {'pos': [0, 0.019, 0]}))
    g.userData.colliders = []
    return K.finish(game, g, {'ao': False})


# Moonlight through the boarded front doors: additive floor slats (board gaps), fading into the room.
def moonSlatsTex():
    def draw(ctx, w, h, rand):
        ctx.fillStyle = '#000'
        ctx.fillRect(0, 0, w, h)
        gaps = [0.1, 0.27, 0.46, 0.63, 0.82]
        for gp in gaps:
            y = gp * h
            grd = ctx.createLinearGradient(0, y - 12, 0, y + 12)
            grd.addColorStop(0, 'rgba(255,255,255,0)')
            grd.addColorStop(0.5, 'rgba(255,255,255,1)')
            grd.addColorStop(1, 'rgba(255,255,255,0)')
            ctx.fillStyle = grd
            ctx.fillRect(10, y - 12, w - 20, 24)
        # fade toward the room (bottom = far from the window) and soft sides
        ctx.globalCompositeOperation = 'destination-in'
        f = ctx.createLinearGradient(0, 0, 0, h)
        f.addColorStop(0, 'rgba(0,0,0,0)')
        f.addColorStop(1, 'rgba(0,0,0,1)')
        ctx.fillStyle = f
        ctx.fillRect(0, 0, w, h)
        s = ctx.createLinearGradient(0, 0, w, 0)
        s.addColorStop(0, 'rgba(0,0,0,0)')
        s.addColorStop(0.18, 'rgba(0,0,0,1)')
        s.addColorStop(0.82, 'rgba(0,0,0,1)')
        s.addColorStop(1, 'rgba(0,0,0,0)')
        ctx.fillStyle = s
        ctx.fillRect(0, 0, w, h)
        ctx.globalCompositeOperation = 'source-over'
    return K.tex.canvas('rooms.lg.moonslats', 256, 256, draw, {'repeat': False})


def moonSlats(game, root, pos, rotY, opts=None):
    """lobby.js moonSlats(game, kit, pos, rotY, opts): the slat mesh (added to root). The power switch
    (m.material = on ? onM : offM when the colour wave reaches pos) is the room script's: the two materials are
    kept in m.userData.onMat / offMat (exported as material specs), the switch position in userData.powerPos."""
    o = opts or {}
    w = o.get('w', 1.9)
    d = o.get('d', 2.6)
    shear = o.get('shear', 0.35)
    pre = o.get('pre', 0.55)
    post = o.get('post', 0.3)
    color = o.get('color', '#9FB6FF')
    map_ = moonSlatsTex()
    geo = THREE.PlaneGeometry(w, d, 1, 1).rotateX(-PI / 2)
    p = geo.attributes.position
    for i in range(p.count):
        p.setX(i, p.getX(i) + (p.getZ(i) + d / 2) * shear)   # lean
    geo.translate(0, 0, -d / 2)        # local z 0 = the wall, the slats reach into -z (the room)
    onM = game.mats.glow(color, post, {'map': map_, 'additive': True, 'fog': False})
    offM = game.mats.glow(color, pre, {'map': map_, 'additive': True, 'fog': False})
    m = Mesh(geo, offM)
    m.position.set(pos[0], 0.012, pos[2])
    m.rotation.y = rotY
    m.renderOrder = 2
    m.castShadow = False
    m.receiveShadow = False
    m.userData.noMerge = True
    m.userData.onMat = onM
    m.userData.offMat = offM
    m.userData.powerPos = list(pos)
    root.add(m)
    return m


# ================================================================================ newsroom.js (green_room imports)
def tc(geo, color):
    return K.tint(geo.clone(), color)


# The furniture kit's shared white-base materials (vertex tints carry the colour): same instances as the
# library's props, so the level merge folds our meshes into the draws it already has.
def stdMats(game):
    return JSObj(
        plastic=K.mat(game, 'plastic', '#ffffff'),
        lacquer=K.mat(game, 'lacquer', '#ffffff'),
        paint=K.mat(game, 'paint', '#ffffff'),
        metal=K.mat(game, 'metal', '#ffffff'),
        chrome=K.mat(game, 'chrome', '#A8B0BA'),
        brass=K.mat(game, 'brass', '#C8963C'),
        rubber=K.mat(game, 'rubber', '#ffffff'),
        fabric=K.mat(game, 'fabric', '#ffffff'),
        teak=K.mat(game, 'lacquer', '#ffffff', {'map': K.tex.wood(PAL.teak, {'dark': 0.36})}),
        walnut=K.mat(game, 'walnut', '#ffffff', {'map': K.tex.wood(PAL.walnut, {'dark': 0.42})}),
    )


def ribbon(points, width, opts=None):
    o = opts or {}
    seg = o.get('seg', 32)
    up = o.get('up', [0, 1, 0])
    rect = o.get('rect', [0, 0, 1, 1])
    curve = THREE.CatmullRomCurve3([THREE.Vector3(a[0], a[1], a[2]) for a in points])
    pos, uv, idx = [], [], []
    U = THREE.Vector3(up[0], up[1], up[2])
    t = THREE.Vector3()
    s = THREE.Vector3()
    p = THREE.Vector3()
    for i in range(seg + 1):
        k = i / seg
        curve.getPointAt(k, p)
        curve.getTangentAt(k, t)
        s.crossVectors(t, U).normalize().multiplyScalar(width / 2)
        pos += [p.x - s.x, p.y - s.y, p.z - s.z, p.x + s.x, p.y + s.y, p.z + s.z]
        v = rect[1] + k * (rect[3] - rect[1])
        uv += [rect[0], v, rect[2], v]
        if i < seg:
            a = i * 2
            idx += [a, a + 1, a + 2, a + 1, a + 3, a + 2]
    g = THREE.BufferGeometry()
    g.setAttribute('position', THREE.Float32BufferAttribute(pos, 3))
    g.setAttribute('uv', THREE.Float32BufferAttribute(uv, 2))
    g.setIndex(idx)
    g.computeVertexNormals()
    return g


# ======================================================================================= green_room.js: gm atlas
WALL_G = JSObj(n=-11.85, s=-6.15, w=-6.85, e=16.85)


def sph(r, ws=14, hs=10):
    return THREE.SphereGeometry(r, ws, hs)


# 512^2 print atlas (4 x 4 cells of 128 px) for the green room's own printed bits: chair backs, phone book,
# LP sleeves, notes, lipstick doodles, hi-fi plate. cell(name) -> [u0, v0, u1, v1].
GCELLS = {
    'chair_duke': [0, 0, 2, 1], 'chair_talent': [2, 0, 2, 1], 'chair_roxy': [0, 1, 2, 1], 'phonebook': [2, 1], 'note': [3, 1],
    'lp1': [0, 2], 'lp2': [1, 2], 'lp3': [2, 2], 'lp4': [3, 2], 'doodle': [0, 3], 'lipstick': [1, 3], 'hifi': [2, 3, 2, 1],
}


def gmAtlasTex():
    def draw(ctx, W, H, rand):
        ctx.clearRect(0, 0, W, H)
        C = 128

        def at(n):
            c = GCELLS[n]
            return [c[0] * C, c[1] * C, _cell(c, 2) * C, _cell(c, 3) * C]

        def rr(x, y, w, h, r):
            ctx.beginPath()
            ctx.roundRect(x, y, w, h, r)

        def text(s, x, y, size, font, fill, o=None):
            o = o or {}
            ctx.save()
            ctx.translate(x, y)
            if o.get('rot'):
                ctx.rotate(o['rot'])
            sz = size
            ctx.font = '%spx %s' % (js_str(sz), font)
            if o.get('max'):
                while ctx.measureText(s).width > o['max'] and sz > 6:
                    sz *= 0.93
                    ctx.font = '%spx %s' % (js_str(sz), font)
            ctx.textAlign = 'center'
            ctx.textBaseline = 'middle'
            if o.get('stroke'):
                ctx.lineWidth = o.get('lw') or size * 0.12
                ctx.strokeStyle = o['stroke']
                ctx.lineJoin = 'round'
                ctx.strokeText(s, 0, 0)
            ctx.fillStyle = fill
            ctx.fillText(s, 0, 0)
            ctx.restore()
        SIGN = '"Bungee", Impact, "Arial Black", sans-serif'
        ROUND = '"Titan One", "Arial Rounded MT Bold", "Arial Black", sans-serif'
        GROOVY = '"Shrikhand", "Cooper Black", Georgia, serif'
        # director's chair backs (canvas stripe + stencil name)
        for n, name, bg, fg in [['chair_duke', 'DUKE', '#E3662B', '#FFF4DA'], ['chair_talent', 'TALENT', '#2F5BD3', '#FFE3A3'],
                                ['chair_roxy', 'ROXY', '#6B3A6E', '#FFD23A']]:
            x, y, w, h = at(n)
            ctx.fillStyle = bg
            ctx.fillRect(x, y, w, h)
            ctx.fillStyle = 'rgba(0,0,0,0.12)'
            i = 0
            while i < w:
                ctx.fillRect(x + i, y, 2, h)
                i += 6
            ctx.fillStyle = fg
            ctx.fillRect(x, y + 8, w, 6)
            ctx.fillRect(x, y + h - 14, w, 6)
            text(name, x + w / 2, y + h / 2 + 3, 62, SIGN, fg, {'max': w - 30})
        # phone book
        x, y, w, h = at('phonebook')
        ctx.fillStyle = '#F4D23A'
        ctx.fillRect(x, y, w, h)
        ctx.fillStyle = '#2A2231'
        ctx.fillRect(x, y + 12, w, 4)
        text('YELLOW', x + w / 2, y + 40, 26, SIGN, '#2A2231')
        text('PAGES', x + w / 2, y + 70, 26, SIGN, '#2A2231')
        ctx.fillStyle = '#2A2231'
        ctx.beginPath()
        ctx.ellipse(x + w / 2, y + 102, 16, 10, 0, 0, TAU)
        ctx.fill()
        text('TRI-COUNTY 1977', x + w / 2, y + 120, 11, ROUND, '#5A3A22')
        # pinned note
        x, y, w, h = at('note')
        ctx.fillStyle = '#FFF0A0'
        rr(x + 8, y + 8, w - 16, h - 16, 4)
        ctx.fill()
        text('CALL', x + w / 2, y + 36, 24, ROUND, '#2A2A8A', {'rot': -0.06})
        text('555-1313', x + w / 2, y + 66, 20, ROUND, '#E23B3B', {'rot': -0.05})
        text('ASK 4 STU', x + w / 2, y + 96, 15, ROUND, '#2A2A8A', {'rot': -0.04})

        # LP sleeves
        def lp(n, bg, fn):
            x, y, w, h = at(n)
            ctx.fillStyle = bg
            ctx.fillRect(x, y, w, h)
            ctx.save()
            ctx.translate(x, y)
            fn(w, h)
            ctx.restore()

        def lp1(w, h):
            for i in range(5):
                ctx.fillStyle = ['#FFD23A', '#E23B3B', '#6B3A6E', '#2F5BD3', '#52E04A'][i]
                ctx.beginPath()
                ctx.arc(w / 2, h + 10, 110 - i * 20, PI, TAU)
                ctx.fill()
            text('FUNK', w / 2, 30, 30, GROOVY, '#FFF4DA')

        def lp2(w, h):
            ctx.fillStyle = '#FF5FA2'
            ctx.beginPath()
            ctx.arc(w / 2, h / 2, 40, 0, TAU)
            ctx.fill()
            ctx.fillStyle = '#FFD23A'
            ctx.beginPath()
            ctx.arc(w / 2, h / 2, 14, 0, TAU)
            ctx.fill()
            text('DISCO', w / 2, 22, 22, SIGN, '#7FE7FF')

        def lp3(w, h):
            ctx.fillStyle = '#8C9A3A'
            ctx.fillRect(0, h * 0.55, w, h)
            ctx.fillStyle = '#E8A92E'
            ctx.beginPath()
            ctx.arc(w * 0.7, h * 0.45, 22, 0, TAU)
            ctx.fill()
            text('Country Hits', w / 2, 24, 18, GROOVY, '#5A3A22')

        def lp4(w, h):
            ctx.strokeStyle = '#FFF4DA'
            ctx.lineWidth = 6
            for i in range(6):
                ctx.beginPath()
                ctx.moveTo(0, 30 + i * 16)
                ctx.bezierCurveTo(w * 0.3, 10 + i * 16, w * 0.7, 50 + i * 16, w, 30 + i * 16)
                ctx.stroke()
            text('SMOOTH', w / 2, h - 20, 22, SIGN, '#FFD23A')
        lp('lp1', '#E3662B', lp1)
        lp('lp2', '#1E1530', lp2)
        lp('lp3', '#F6E7C8', lp3)
        lp('lp4', '#2F5BD3', lp4)
        # phone-wall doodles (transparent)
        x, y = at('doodle')[:2]
        ctx.strokeStyle = 'rgba(40,30,70,0.8)'
        ctx.lineWidth = 3
        ctx.beginPath()
        ctx.moveTo(x + 30, y + 40)
        ctx.bezierCurveTo(x + 10, y + 10, x + 50, y + 5, x + 30, y + 40)
        ctx.stroke()
        for i in range(3):
            cx = x + 70 + i * 16
            cy = y + 30 + i * 22
            ctx.beginPath()
            for k in range(10):
                a = -HP + k * PI / 5
                r = 4 if k % 2 else 10
                ctx.lineTo(cx + math.cos(a) * r, cy + math.sin(a) * r)
            ctx.closePath()
            ctx.stroke()
        text('555-0113', x + 50, y + 92, 18, ROUND, 'rgba(40,30,70,0.85)', {'rot': -0.15})
        text('B.V.S.', x + 88, y + 116, 14, ROUND, 'rgba(150,30,60,0.85)', {'rot': 0.1})
        # lipstick on the mirror (transparent)
        x, y = at('lipstick')[:2]
        ctx.fillStyle = '#E2234A'
        ctx.beginPath()
        ctx.moveTo(x + 64, y + 58)
        ctx.bezierCurveTo(x + 64, y + 30, x + 24, y + 30, x + 24, y + 54)
        ctx.bezierCurveTo(x + 24, y + 74, x + 50, y + 84, x + 64, y + 100)
        ctx.bezierCurveTo(x + 78, y + 84, x + 104, y + 74, x + 104, y + 54)
        ctx.bezierCurveTo(x + 104, y + 30, x + 64, y + 30, x + 64, y + 58)
        ctx.lineWidth = 6
        ctx.strokeStyle = '#E2234A'
        ctx.stroke()
        text('BREAK A LEG!', x + 64, y + 118, 15, GROOVY, '#E2234A', {'rot': -0.08})
        # hi-fi faceplate
        x, y, w, h = at('hifi')
        ctx.fillStyle = '#D8D2C2'
        ctx.fillRect(x, y, w, h)
        ctx.fillStyle = '#2A2231'
        rr(x + 10, y + 12, w - 20, 46, 8)
        ctx.fill()
        ctx.fillStyle = '#FFB347'
        ctx.fillRect(x + 20, y + 20, w - 40, 30)
        ctx.fillStyle = '#5A3A22'
        for i in range(18):
            ctx.fillRect(x + 26 + i * 11.5, y + 22, 2, 10 if i % 3 else 18)
        ctx.fillStyle = '#E23B3B'
        ctx.fillRect(x + 120, y + 20, 3, 30)
        text('STEREO-MATIC 8000', x + w / 2, y + 84, 22, SIGN, '#5A3A22', {'max': w - 30})
        text('AM · FM · PHONO', x + w / 2, y + 110, 14, ROUND, '#7A4A2A')
    return K.tex.canvas('rooms.gm.atlas.v1', 512, 512, draw, {'repeat': False, 'fonts': True})


def gmAtlas(game):
    map_ = gmAtlasTex()
    map_.anisotropy = 8

    def cell(name):
        c = GCELLS[name]
        return [c[0] / 4, 1 - (c[1] + _cell(c, 3)) / 4, (c[0] + _cell(c, 2)) / 4, 1 - c[1] / 4]
    return JSObj(
        map=map_, cell=cell,
        mat=K.mat(game, 'paint', '#ffffff', {'map': map_, 'rim': 0.12}),
        decal=K.mat(game, 'plastic', '#ffffff', {'map': map_, 'alphaTest': 0.5, 'side': THREE.DoubleSide}),
    )


# Plane w x h facing -z (prop front) with the UVs of a gm atlas cell.
def gPlane(ga, name, w, h, face='-z'):
    u0, v0, u1, v1 = ga.cell(name)
    g = THREE.PlaneGeometry(w, h)
    K.uvRect(g, u0, v0, u1, v1)
    if face == '-z':
        g.rotateY(PI)
    elif face == '+y':
        g.rotateX(-HP)
    return g


# ============================================================================================ local builders
# Switchable bulbs: one geometry merged from bulb spheres (local positions), off/on materials swapped at Sign-On.
def mirrorMat(game):
    def draw(ctx, w, h, rand):
        g = ctx.createLinearGradient(0, 0, w * 0.3, h)
        g.addColorStop(0, '#C9DAE4')
        g.addColorStop(0.55, '#8FA4B6')
        g.addColorStop(1, '#5E6F84')
        ctx.fillStyle = g
        ctx.fillRect(0, 0, w, h)
        ctx.save()
        ctx.translate(w / 2, h / 2)
        ctx.rotate(-0.62)
        ctx.fillStyle = 'rgba(255,255,255,0.55)'
        ctx.fillRect(-w, -64, w * 2, 26)
        ctx.fillStyle = 'rgba(255,255,255,0.32)'
        ctx.fillRect(-w, -22, w * 2, 10)
        ctx.fillStyle = 'rgba(255,255,255,0.22)'
        ctx.fillRect(-w, 58, w * 2, 16)
        ctx.restore()
    map_ = K.tex.canvas('rooms.gm.mirror.v1', 256, 256, draw, {'repeat': False})
    return K.mat(game, 'lacquer', '#ffffff', {'map': map_, 'env': 0.22, 'rough': 0.12, 'rim': 0.1})


def bulbMats(game):
    return JSObj(on=K.glow(game, '#FFD08A', 2.3), off=K.mat(game, 'ceramic', '#E9DDC6', {'rim': 0.35}))


def bulbGeo(points, r=0.036):
    base = THREE.SphereGeometry(r, 10, 7)
    geos = [base.clone().translate(x, y, z) for x, y, z in points]
    return THREE.mergeGeometries(geos, False)


# ---------------------------------------------------------------------------------------- Hollywood vanity
# Long make-up counter against a wall: drawer banks + knee holes, harvest-gold top, three bulb-ringed mirrors on
# the wall, per-station clutter (Roxy's wig head + afro pick, Duke's cucumber plate + towel + make-up kit, a boa,
# brushes, tissue box, radio). Front -z, back (wall) at local z = +D/2. parts.bulbs (merged, noMerge).
def vanity(game, am, ga, opts=None):
    length = (opts or {}).get('len', 6.0)
    g = K.prop('gm_vanity')
    mt = stdMats(game)
    W, D, H = length, 0.56, 0.8
    bz = D / 2
    cream, choc, gold, orange = '#F3E6C8', '#4A2E22', '#E8A92E', '#E3662B'
    sp = min(2.0, (W - 1.7) / 2)   # station spacing: 2.0 on a 6 m counter, tighter on a shorter one
    st = [-sp, 0, sp]
    knee = 0.74
    # kick + banks
    g.add(K.m(tc(K.box(W - 0.08, 0.08, D - 0.1, 'sm'), choc), mt.paint, {'pos': [0, 0.04, 0.03]}))
    edges = [-W / 2]
    for x in st:
        edges += [x - knee / 2, x + knee / 2]
    edges.append(W / 2)
    pull = K.tube([[-0.07, 0, 0], [-0.06, 0, -0.022], [0.06, 0, -0.022], [0.07, 0, 0]], 0.0075, {'seg': 8, 'radial': 5})
    for i in range(0, len(edges), 2):
        x0, x1 = edges[i], edges[i + 1]
        w = x1 - x0
        cx = (x0 + x1) / 2
        g.add(K.m(tc(K.box(w - 0.01, H - 0.12, D - 0.04, 'md'), cream), mt.lacquer, {'pos': [cx, 0.08 + (H - 0.12) / 2, 0.01]}))
        n = 2 if w > 1.0 else 1
        for k in range(n):
            dx = cx if n == 1 else cx + (k - 0.5) * (w / 2)
            dw = w / n - 0.06
            y = H - 0.08
            for j, hh in enumerate([0.2, 0.2, 0.26]):
                cy = y - hh / 2
                g.add(K.m(tc(K.box(dw, hh - 0.02, 0.03, 'sm'), orange if j == 2 else gold), mt.lacquer, {'pos': [dx, cy, -D / 2 + 0.005]}))
                g.add(K.m(pull, mt.chrome, {'pos': [dx, cy + hh * 0.2, -D / 2 - 0.012]}))
                y = y - hh
    for x in st:
        g.add(K.m(tc(K.box(knee, H - 0.2, 0.03, 'sm'), '#6A4A36'), mt.paint, {'pos': [x, (H - 0.2) / 2 + 0.06, bz - 0.04]}))
        g.add(K.m(tc(K.box(knee - 0.02, 0.1, 0.03, 'sm'), gold), mt.lacquer, {'pos': [x, H - 0.12, -D / 2 + 0.005]}))
        g.add(K.m(pull, mt.chrome, {'pos': [x, H - 0.12, -D / 2 - 0.012]}))
    # top: laminate slab with a chocolate bullnose band + low backsplash
    g.add(K.m(tc(K.box(W + 0.04, 0.045, D + 0.04, 'md'), gold), mt.lacquer, {'pos': [0, H - 0.0225, 0]}))
    g.add(K.m(tc(K.box(W + 0.05, 0.03, 0.05, 'sm'), choc), mt.lacquer, {'pos': [0, H - 0.035, -D / 2 - 0.01]}))
    g.add(K.m(tc(K.box(W, 0.14, 0.03, 'sm'), cream), mt.lacquer, {'pos': [0, H + 0.07, bz - 0.015]}))
    # mirrors: cream frames with bulbs, mirror glass, lipstick + polaroids
    mirror = K.mat(game, 'chrome', '#C6D4DC', {'rough': 0.07, 'env': 0.85, 'rim': 0.1})
    bulbs = []
    MW, MH, my = 1.14, 0.94, 1.55
    for x in st:
        fr = K.roundRect(MW + 0.2, MH + 0.2, 0.09)
        fr.holes.append(THREE.Path(K.roundRect(MW, MH, 0.05).getPoints(6)))
        g.add(K.m(tc(K.extrude(fr, 0.05, {'bevel': 0.015, 'curveSeg': 4, 'bevelSeg': 2}), cream), mt.lacquer, {'pos': [x, my, bz - 0.04]}))
        g.add(K.m(THREE.PlaneGeometry(MW + 0.02, MH + 0.02).rotateY(PI), mirrorMat(game), {'pos': [x, my, bz - 0.03]}))
        # bulbs: 7 across the top, 4 down each side, sockets on the frame
        bx = (MW + 0.1) / 2
        by = (MH + 0.1) / 2
        for i in range(7):
            bulbs.append([x - bx + (i / 6) * 2 * bx, my + by, bz - 0.095])
        for s in [-1, 1]:
            for i in range(4):
                bulbs.append([x + s * bx, my + by - 0.24 - i * 0.22, bz - 0.095])
    bm = bulbMats(game)
    socketGeo = K.cyl(0.024, 0.024, 0.03, {'seg': 8}).clone().rotateX(-HP)
    for x, y, z in bulbs:
        g.add(K.m(socketGeo, mt.brass, {'pos': [x, y, z + 0.035]}))
    bulbMesh = K.m(bulbGeo(bulbs, 0.037), bm.off, {'cast': False})
    bulbMesh.name = 'bulbs'
    bulbMesh.userData.noMerge = True
    bulbMesh.userData.noOcclude = True
    g.add(bulbMesh)
    g.add(K.m(gPlane(ga, 'lipstick', 0.34, 0.34), ga.decal, {'pos': [st[1] + 0.3, my + 0.12, bz - 0.036], 'rot': [0, 0, 0.05]}))
    for x, y, r in [[st[0] - 0.42, my + 0.28, 0.12], [st[1] - 0.44, my - 0.3, -0.1], [st[2] + 0.4, my + 0.25, -0.14],
                    [st[2] - 0.38, my + 0.3, 0.08]]:
        g.add(K.m(cellPlane('polaroid', 0.15, 0.15, {'face': '-z'}), am.decal, {'pos': [x, y, bz - 0.037], 'rot': [0, 0, r]}))
    T = H + 0.001
    # --- station 1 (Roxy): wig head with an afro, afro pick, hairspray, lipsticks, hand mirror
    x = st[0]
    foam = '#EEE6D8'
    g.add(K.m(tc(K.cyl(0.07, 0.085, 0.02, {'seg': 16}), '#2A2231'), mt.plastic, {'pos': [x - 0.25, T, -0.02]}))
    g.add(K.m(tc(K.cyl(0.045, 0.05, 0.14, {'seg': 12}), foam), mt.paint, {'pos': [x - 0.25, T + 0.02, -0.02]}))
    g.add(K.m(tc(sph(0.1, 16, 12), foam), mt.paint, {'pos': [x - 0.25, T + 0.24, -0.02], 'scale': [0.9, 1.1, 0.95]}))
    g.add(K.m(tc(sph(0.02, 8, 6), '#E8D8C8'), mt.paint, {'pos': [x - 0.25, T + 0.23, -0.115]}))
    afro = THREE.Group()

    def rnd(i):
        return hash_(i * 3.7 + 1.3)
    for i in range(26):
        a = rnd(i) * TAU
        e = 0.1 + rnd(i + 40) * 1.1
        r = 0.15
        px = math.cos(a) * math.sin(e) * r
        py = math.cos(e) * r * 0.95
        pz = math.sin(a) * math.sin(e) * r
        if pz < -0.06 and py < 0.08:
            continue   # keep the face open
        afro.add(K.m(tc(sph(0.055 + rnd(i + 9) * 0.02, 10, 8), '#2A1A12' if i % 3 else '#3E2618'), mt.fabric, {'pos': [px, py, pz + 0.02]}))
    afro.position.set(x - 0.25, T + 0.27, -0.02)
    g.add(afro)
    # afro pick (black fist handle + prongs)
    g.add(K.m(tc(K.box(0.05, 0.012, 0.07, 'xs'), '#1E1530'), mt.plastic, {'pos': [x + 0.05, T + 0.006, -0.14], 'rot': [0, 0.4, 0]}))
    for i in range(6):
        g.add(K.m(tc(K.box(0.006, 0.008, 0.07, 'xs'), '#1E1530'), mt.plastic,
                  {'pos': [x + 0.05 + math.cos(0.4) * (i - 2.5) * 0.009 + math.sin(0.4) * -0.06, T + 0.005,
                           -0.14 + math.cos(0.4) * -0.06 - math.sin(0.4) * (i - 2.5) * 0.009]}))
    # hairspray + lipsticks + hand mirror
    g.add(K.m(tc(K.cyl(0.035, 0.035, 0.2, {'seg': 14}), '#FF5FA2'), mt.lacquer, {'pos': [x + 0.2, T, 0.02]}))
    g.add(K.m(tc(K.cyl(0.036, 0.03, 0.05, {'seg': 14}), '#F4F1E8'), mt.plastic, {'pos': [x + 0.2, T + 0.2, 0.02]}))
    for i in range(3):
        g.add(K.m(tc(K.cyl(0.011, 0.011, 0.06, {'seg': 8}), ['#E2234A', '#C8963C', '#B5472A'][i]), mt.lacquer,
                  {'pos': [x + 0.32 + i * 0.03, T, -0.08 + (i % 2) * 0.02]}))
    hm = THREE.Group()
    hm.position.set(x - 0.02, T + 0.012, -0.05)
    hm.rotation.y = -0.5
    hm.add(K.m(tc(K.cyl(0.07, 0.07, 0.014, {'seg': 18}), '#FF8CC0'), mt.lacquer))
    hm.add(K.m(K.cyl(0.058, 0.058, 0.004, {'seg': 18}), mirror, {'pos': [0, 0.013, 0]}))
    hm.add(K.m(tc(K.box(0.03, 0.014, 0.12, 'xs'), '#FF8CC0'), mt.lacquer, {'pos': [0, 0.007, -0.12]}))
    g.add(hm)
    # --- station 2 (Duke, "in the make-up chair with cucumber slices over his eyes"): plate of cucumber slices,
    #     rolled towel, open make-up kit, powder puff, coffee mug, script
    x = st[1]
    g.add(K.m(tc(K.lathe([[0, 0], [0.09, 0], [0.12, 0.018], [0.125, 0.022], [0, 0.012]], {'seg': 22}), '#F8F4EC'), mt.plastic,
              {'pos': [x - 0.3, T, -0.06]}))
    for i in range(5):
        a = i * 1.26
        r = 0.055 if i else 0
        g.add(K.m(tc(K.cyl(0.034, 0.034, 0.008, {'seg': 14}), '#3F7A2A'), mt.plastic,
                  {'pos': [x - 0.3 + math.cos(a) * r, T + 0.016 + i * 0.002, -0.06 + math.sin(a) * r]}))
        g.add(K.m(tc(K.cyl(0.028, 0.028, 0.009, {'seg': 14}), '#CFE8A0'), mt.plastic,
                  {'pos': [x - 0.3 + math.cos(a) * r, T + 0.0165 + i * 0.002, -0.06 + math.sin(a) * r]}))
    g.add(K.m(tc(K.cyl(0.06, 0.06, 0.34, {'seg': 14}), '#F4F1E8'), mt.fabric, {'pos': [x + 0.02, T + 0.06, 0.1], 'rot': [0, 0, HP]}))
    g.add(K.m(tc(K.cyl(0.061, 0.061, 0.03, {'seg': 14}), PAL.burntOrange), mt.fabric, {'pos': [x - 0.05, T + 0.06, 0.1], 'rot': [0, 0, HP]}))
    # make-up kit: tackle box with the lid swung open and colour pans
    kit = THREE.Group()
    kit.position.set(x + 0.3, T, -0.02)
    kit.rotation.y = -0.15
    kit.add(K.m(tc(K.box(0.3, 0.1, 0.18, 'sm'), '#2F5BD3'), mt.lacquer, {'pos': [0, 0.05, 0]}))
    kit.add(K.m(tc(K.box(0.3, 0.02, 0.18, 'xs'), '#2A3A8A'), mt.lacquer, {'pos': [0, 0.14, 0.14], 'rot': [-1.2, 0, 0]}))
    for i in range(8):
        kit.add(K.m(tc(K.cyl(0.018, 0.018, 0.012, {'seg': 10}),
                       ['#E2234A', '#FFB6C8', '#E3662B', '#6B3A6E', '#7FD4FF', '#FFD23A', '#8C9A3A', '#F4F1E8'][i]), mt.plastic,
                    {'pos': [-0.105 + (i % 4) * 0.07, 0.1, -0.045 + math.floor(i / 4) * 0.08]}))
    g.add(kit)
    g.add(K.m(tc(sph(0.045, 12, 8), '#FFD0DC'), mt.fabric, {'pos': [x + 0.08, T + 0.02, -0.16], 'scale': [1, 0.45, 1]}))
    g.add(K.m(tc(K.lathe([[0, 0], [0.036, 0], [0.04, 0.09], [0.036, 0.09], [0.032, 0.008], [0, 0.008]], {'seg': 14}), PAL.harvestGold),
              mt.lacquer, {'pos': [x + 0.52, T, 0.1]}))
    g.add(K.m(THREE.TorusGeometry(0.024, 0.007, 6, 12, PI * 1.2), mt.lacquer, {'pos': [x + 0.56, T + 0.05, 0.1], 'rot': [0, 0, -PI * 0.6]}))
    g.add(K.m(cellPlane('script', 0.2, 0.26, {'flat': True}), am.paper, {'pos': [x - 0.1, T + 0.004, -0.13], 'rot': [0, 0.25, 0]}))
    # --- station 3: boa draped over the mirror corner and the counter, brush jar, tissue box, transistor radio
    x = st[2]
    boaPts = [[x + 0.62, my + 0.5, bz - 0.1], [x + 0.72, my + 0.2, bz - 0.13], [x + 0.66, my - 0.2, bz - 0.16],
              [x + 0.54, T + 0.3, -0.05], [x + 0.36, T + 0.04, -0.14], [x + 0.12, T + 0.03, -0.2]]
    curve = THREE.CatmullRomCurve3([THREE.Vector3(p[0], p[1], p[2]) for p in boaPts])
    g.add(K.m(boaGeo(curve, 64), mt.fabric, {'cast': False}))
    g.add(K.m(K.lathe([[0, 0], [0.04, 0], [0.042, 0.12], [0.038, 0.12], [0.036, 0.004], [0, 0.004]], {'seg': 16}),
              game.mats.glass('#CFE0E8', {'opacity': 0.45}), {'pos': [x - 0.3, T, 0.08]}))
    for i in range(5):
        g.add(K.m(tc(K.cyl(0.006, 0.004, 0.2, {'seg': 6}), ['#5A3A22', '#E23B3B', '#1E1530', '#C8963C', '#5A3A22'][i]), mt.lacquer,
                  {'pos': [x - 0.3 + (i - 2) * 0.012, T + 0.02, 0.08 + (i % 2) * 0.012], 'rot': [(i - 2) * 0.08, 0, (i - 2) * 0.1]}))
    g.add(K.m(tc(K.box(0.2, 0.1, 0.12, 'sm'), '#8C9A3A'), mt.lacquer, {'pos': [x - 0.02, T + 0.05, -0.02], 'rot': [0, 0.2, 0]}))
    g.add(K.m(tc(sph(0.045, 10, 8), '#FBF8F1'), mt.fabric, {'pos': [x - 0.02, T + 0.12, -0.02], 'scale': [1.2, 0.7, 0.9]}))
    radio = THREE.Group()
    radio.position.set(x + 0.3, T, 0.05)
    radio.rotation.y = -0.25
    radio.add(K.m(tc(K.box(0.24, 0.15, 0.08, 'md'), '#E23B3B'), mt.lacquer, {'pos': [0, 0.075, 0]}))
    radio.add(K.m(tc(K.box(0.13, 0.1, 0.01, 'sm'), '#F4F1E8'), mt.plastic, {'pos': [-0.04, 0.075, -0.042]}))
    radio.add(K.m(K.cyl(0.02, 0.02, 0.012, {'seg': 12}), mt.chrome, {'pos': [0.075, 0.1, -0.046], 'rot': [HP, 0, 0]}))
    radio.add(K.m(K.cyl(0.004, 0.004, 0.32, {'seg': 5}), mt.chrome, {'pos': [0.09, 0.15, 0.02], 'rot': [0, 0, -0.35]}))
    g.add(radio)
    u = g.userData
    u.parts = JSObj(bulbs=bulbMesh)
    u.lampMats = bm
    u.colliders = [{'min': [-W / 2 - 0.02, 0, -D / 2 - 0.03], 'max': [W / 2 + 0.02, H + 0.05, D / 2]}]
    return K.finish(game, g, {'ao': {'res': 56}})


# Feather boa: dense jittered puffs along a curve (reads fluffy, one merged geometry).
def boaGeo(curve, n=60, r=0.04):
    out = []
    p = THREE.Vector3()
    for i in range(n):
        curve.getPoint(i / (n - 1), p)
        for k in range(2):
            h = hash_(i * 7.3 + k * 1.9)
            a = hash_(i * 3.1 + k * 5.7) * TAU
            b = hash_(i * 1.3 + k * 9.1) * PI
            s = r * (0.55 + h * 0.5)
            o = r * 0.6
            col = '#FF8CC0' if (i + k) % 3 == 0 else '#FF5FA2' if (i + k) % 3 == 1 else '#FFB0D2'
            out.append(tc(THREE.IcosahedronGeometry(s, 1).translate(p.x + math.cos(a) * math.sin(b) * o, p.y + math.cos(b) * o,
                                                                    p.z + math.sin(a) * math.sin(b) * o), col))
    return THREE.mergeGeometries(out, False)


# ----------------------------------------------------------------------------------- reclining make-up chair
# Chrome hydraulic pedestal, orange vinyl seat, reclined back + headrest with a towel, chrome arms, footrest.
# Front (sitter faces) -z.
def makeupChair(game):
    g = K.prop('gm_makeup_chair')
    mt = stdMats(game)
    vinyl = K.mat(game, 'vinyl', '#ffffff', {'map': K.tex.pebble('#E3662B')})
    g.add(K.m(K.lathe([[0, 0], [0.3, 0], [0.31, 0.02], [0.26, 0.05], [0.09, 0.08], [0, 0.085]], {'seg': 28, 'round': 0.01}), mt.chrome))
    g.add(K.m(K.cyl(0.06, 0.07, 0.34, {'seg': 18, 'bevel': 0.01}), mt.chrome, {'pos': [0, 0.08, 0]}))
    g.add(K.m(tc(K.box(0.08, 0.03, 0.16, 'sm'), '#2A2231'), mt.plastic, {'pos': [0.2, 0.05, -0.18], 'rot': [0.15, 0.6, 0]}))
    g.add(K.m(K.box(0.5, 0.06, 0.46, 'md'), mt.chrome, {'pos': [0, 0.44, 0]}))
    g.add(K.m(K.cushion(0.56, 0.14, 0.52, {'puff': 0.03}), vinyl, {'pos': [0, 0.53, -0.01]}))
    back = THREE.Group()
    back.position.set(0, 0.56, 0.24)
    back.rotation.x = 0.38
    back.add(K.m(K.cushion(0.54, 0.66, 0.13, {'puff': 0.03}), vinyl, {'pos': [0, 0.36, 0.02]}))
    back.add(K.m(K.box(0.5, 0.62, 0.04, 'sm'), mt.chrome, {'pos': [0, 0.36, 0.1]}))
    back.add(K.m(K.cyl(0.016, 0.016, 0.16, {'seg': 8}), mt.chrome, {'pos': [0, 0.68, 0.04]}))
    back.add(K.m(K.cushion(0.32, 0.14, 0.12, {'puff': 0.03}), vinyl, {'pos': [0, 0.86, 0.02]}))
    back.add(K.m(tc(K.box(0.36, 0.06, 0.2, 'md'), '#F4F1E8'), mt.fabric, {'pos': [0, 0.96, -0.02], 'rot': [0.3, 0, 0]}))
    back.add(K.m(tc(K.box(0.37, 0.018, 0.2, 'sm'), PAL.burntOrange), mt.fabric, {'pos': [0, 0.99, -0.03], 'rot': [0.3, 0, 0]}))
    g.add(back)
    for s in [-1, 1]:
        g.add(K.m(K.tube([[s * 0.29, 0.46, 0.2], [s * 0.32, 0.72, 0.16], [s * 0.32, 0.72, -0.22], [s * 0.29, 0.46, -0.24]], 0.016,
                         {'seg': 12, 'radial': 6}), mt.chrome))
        g.add(K.m(K.cushion(0.09, 0.06, 0.44, {'puff': 0.015}), vinyl, {'pos': [s * 0.32, 0.75, -0.03]}))
    g.add(K.m(K.tube([[-0.2, 0.44, -0.24], [-0.2, 0.22, -0.46], [0.2, 0.22, -0.46], [0.2, 0.44, -0.24]], 0.014, {'seg': 12, 'radial': 6}), mt.chrome))
    g.add(K.m(K.box(0.44, 0.02, 0.16, 'sm'), mt.chrome, {'pos': [0, 0.22, -0.46], 'rot': [0.3, 0, 0]}))
    # two cucumber slices dropped on the seat
    for x, z, r in [[-0.08, -0.12, 0.2], [0.1, -0.02, 0.9]]:
        g.add(K.m(tc(K.cyl(0.034, 0.034, 0.008, {'seg': 14}), '#3F7A2A'), mt.plastic, {'pos': [x, 0.61, z], 'rot': [0.04, r, 0.06]}))
        g.add(K.m(tc(K.cyl(0.028, 0.028, 0.009, {'seg': 14}), '#CFE8A0'), mt.plastic, {'pos': [x, 0.6105, z], 'rot': [0.04, r, 0.06]}))
    g.userData.colliders = [{'min': [-0.36, 0, -0.5], 'max': [0.36, 1.2, 0.5]}]
    return K.finish(game, g, {'ao': {'res': 40}})


# ---------------------------------------------------------------------------------------- director's chair
def directorChair(game, ga, cellName, fabric):
    g = K.prop('gm_director_chair')
    mt = stdMats(game)
    W, SH = 0.56, 0.46
    for s in [-1, 1]:
        # X legs on each side
        for d in [-1, 1]:
            g.add(K.m(K.tube([[s * W / 2, 0.02, -0.22 * d], [s * W / 2, SH - 0.02, 0.2 * d]], 0.018, {'seg': 2, 'radial': 7}), mt.teak))
        g.add(K.m(K.box(0.04, 0.04, 0.46, 'sm'), mt.teak, {'pos': [s * W / 2, SH, 0]}))
        g.add(K.m(K.box(0.04, 0.04, 0.44, 'sm'), mt.teak, {'pos': [s * W / 2, 0.66, 0.0]}))
        g.add(K.m(K.box(0.04, 0.5, 0.04, 'sm'), mt.teak, {'pos': [s * W / 2, 0.66, 0.22]}))
        g.add(K.m(K.box(0.04, 0.22, 0.04, 'sm'), mt.teak, {'pos': [s * W / 2, SH + 0.1, -0.2]}))
    g.add(K.m(tc(K.box(W - 0.02, 0.025, 0.42, 'xs'), fabric), mt.fabric, {'pos': [0, SH + 0.01, 0]}))
    g.add(K.m(tc(K.box(W - 0.02, 0.2, 0.02, 'xs'), fabric), mt.fabric, {'pos': [0, 0.8, 0.22]}))
    g.add(K.m(gPlane(ga, cellName, W - 0.06, 0.18, '+z'), ga.mat, {'pos': [0, 0.8, 0.232]}))
    g.userData.colliders = [{'min': [-W / 2 - 0.03, 0, -0.26], 'max': [W / 2 + 0.03, 0.92, 0.26]}]
    return K.finish(game, g, {'ao': {'res': 32}})


# ------------------------------------------------------------------------------------- ss_green wall TV
# A walnut built-in wall TV (the screen sits ~0.28 m off the wall so screen-spawn zombies crawl out of the
# glass): silver face, bevelled bezel, CRT (screens id ss_green), dials + speaker cloth, rabbit ears, a little
# shelf below with a TV WEEKLY and a cactus. Wall at local z = 0, front -z, origin = the screen centre.
def wallTV(game):
    g = K.prop('gm_wall_tv')
    mt = stdMats(game)
    W, H, D, cx = 1.08, 0.86, 0.25, -0.15
    SW, SH = 0.62, 0.47
    g.add(K.m(K.box(W, H, D, 0.07, {'uv': 1.4}), mt.walnut, {'pos': [cx, 0, -D / 2]}))
    g.add(K.m(tc(K.box(W - 0.08, H - 0.08, 0.02, 0.03), '#C9C2B2'), mt.metal, {'pos': [cx, 0, -D - 0.005]}))
    fr = K.roundRect(SW + 0.1, SH + 0.1, 0.07)
    fr.holes.append(THREE.Path(K.roundRect(SW, SH, 0.06).getPoints(6)))
    g.add(K.m(tc(K.extrude(fr, 0.04, {'bevel': 0.012, 'curveSeg': 4, 'bevelSeg': 2}), '#2A2231'), mt.plastic, {'pos': [0, 0, -D - 0.02]}))
    g.add(K.m(tc(THREE.PlaneGeometry(SW + 0.02, SH + 0.02).rotateY(PI), '#1E1822'), mt.plastic, {'pos': [0, 0, -D - 0.012]}))
    screen = K.screen(game, SW, SH, {'card': 'snow', 'group': 'scr_decor', 'dome': 0.03})
    screen.position.set(0, 0, -D - 0.02)
    g.add(screen)
    # controls column (viewer's right = local -x after the room's rotY pi)
    kx = cx - W / 2 + 0.13
    for y, r, c in [[0.24, 0.05, '#2A2231'], [0.08, 0.038, '#C8963C']]:
        g.add(K.m(tc(K.cyl(r + 0.012, r + 0.012, 0.01, {'seg': 22}), '#F4F1E8'), mt.plastic, {'pos': [kx, y, -D - 0.018], 'rot': [HP, 0, 0]}))
        g.add(K.m(tc(K.lathe([[0, 0], [r * 0.8, 0], [r * 0.75, 0.03], [r * 0.5, 0.045], [0, 0.046]], {'seg': 16, 'round': 0.004}), c),
                  mt.lacquer, {'pos': [kx, y, -D - 0.02], 'rot': [-HP, 0, 0]}))
    g.add(K.m(K.box(0.16, 0.2, 0.012, 'sm'), K.mat(game, 'fabric', '#ffffff', {'map': K.tex.weave('#8A6A4A', {'pattern': 'cord'})}),
              {'pos': [kx, -0.18, -D - 0.018]}))
    g.add(K.m(tc(K.cyl(0.035, 0.035, 0.012, {'seg': 18}), PAL.wztvBlue), mt.lacquer, {'pos': [kx, -0.33, -D - 0.02], 'rot': [HP, 0, 0]}))
    g.add(K.m(THREE.TorusGeometry(0.036, 0.006, 6, 18), mt.plastic, {'pos': [kx, -0.33, -D - 0.026]}))
    g.add(K.m(K.tube([[q[0] + cx, q[2], 0] for q in K.roundRectPath(W - 0.03, H - 0.03, 0.06, 0)], 0.008,
                     {'seg': 40, 'radial': 5, 'closed': True}), mt.chrome, {'pos': [0, 0, -D - 0.003]}))
    # rabbit ears
    top = H / 2
    g.add(K.m(tc(K.lathe([[0, 0], [0.07, 0], [0.072, 0.015], [0.05, 0.04], [0, 0.045]], {'seg': 16, 'round': 0.006}), '#2A2231'),
              mt.plastic, {'pos': [cx + 0.12, top, -D / 2]}))
    for s in [-1, 1]:
        g.add(K.m(K.cyl(0.005, 0.004, 0.62, {'seg': 6}), mt.chrome, {'pos': [cx + 0.12 + s * 0.012, top + 0.035, -D / 2], 'rot': [0.2, 0, s * 0.55]}))
        g.add(K.m(sph(0.012, 8, 6), mt.chrome, {'pos': [cx + 0.12 + s * 0.33, top + 0.56, -D / 2 - 0.11]}))
    # shelf below: walnut slab on brass brackets, TV WEEKLY, doily, cactus
    sy = -H / 2 - 0.1
    g.add(K.m(K.box(0.9, 0.035, 0.28, 0.012, {'uv': 1.5}), mt.walnut, {'pos': [cx, sy, -0.14]}))
    for s in [-1, 1]:
        g.add(K.m(K.tube([[cx + s * 0.32, sy - 0.18, 0], [cx + s * 0.32, sy - 0.05, -0.12], [cx + s * 0.32, sy - 0.02, -0.22]], 0.01,
                         {'seg': 8, 'radial': 5}), mt.brass))
    mag = K.getCard('magazine_tv_weekly')
    g.add(K.m(THREE.PlaneGeometry(0.2, 0.27).rotateX(-HP), K.mat(game, 'paint', '#ffffff', {'map': mag or None}),
              {'pos': [cx - 0.15, sy + 0.02, -0.15], 'rot': [0, 0.3, 0]}))
    g.add(K.m(tc(K.cyl(0.05, 0.04, 0.08, {'seg': 14}), PAL.burntOrange), mt.lacquer, {'pos': [cx + 0.25, sy + 0.018, -0.14]}))
    g.add(K.m(tc(K.cyl(0.03, 0.028, 0.12, {'seg': 10}), '#5E8C3A'), mt.plastic, {'pos': [cx + 0.25, sy + 0.08, -0.14]}))
    g.add(K.m(tc(sph(0.02, 8, 6), '#5E8C3A'), mt.plastic, {'pos': [cx + 0.28, sy + 0.16, -0.14]}))
    g.add(K.m(tc(sph(0.012, 6, 5), '#FF5FA2'), mt.plastic, {'pos': [cx + 0.25, sy + 0.22, -0.14]}))
    g.userData.colliders = [{'min': [cx - W / 2, -H / 2 - 0.15, -D - 0.06], 'max': [cx + W / 2, H / 2 + 0.05, 0]}]
    return K.finish(game, g, {'ao': {'floor': False, 'height': 0, 'res': 40}})


# --------------------------------------------------------------------------------------------- coat rail
def coatRail(game):
    g = K.prop('gm_coat_rail')
    mt = stdMats(game)
    L = 1.0
    g.add(K.m(K.box(L, 0.12, 0.03, 0.012, {'uv': 1.5}), mt.walnut, {'pos': [0, 0, -0.015]}))
    hooks = [-0.375, -0.125, 0.125, 0.375]
    for x in hooks:
        g.add(K.m(K.tube([[x, 0.01, -0.03], [x, 0.0, -0.1], [x, 0.05, -0.13]], 0.009, {'seg': 8, 'radial': 5}), mt.brass))
        g.add(K.m(sph(0.014, 8, 6), mt.brass, {'pos': [x, 0.05, -0.13]}))
    # fedora on hook 1
    g.add(K.m(tc(K.lathe([[0, 0], [0.16, 0], [0.165, 0.012], [0.1, 0.02], [0.09, 0.1], [0.07, 0.13], [0, 0.12]], {'seg': 20, 'round': 0.006}),
                 '#5A3A22'), mt.fabric, {'pos': [hooks[0], -0.05, -0.12], 'rot': [-1.35, 0, 0]}))
    g.add(K.m(tc(K.cyl(0.093, 0.1, 0.03, {'seg': 20}), '#E3662B'), mt.fabric, {'pos': [hooks[0], -0.06, -0.14], 'rot': [-1.35, 0, 0]}))
    # mustard scarf on hook 2 (two hanging ribbons)
    for dx in [-0.03, 0.035]:
        g.add(K.m(ribbon([[hooks[1] + dx, 0.03, -0.12], [hooks[1] + dx * 1.3, -0.25, -0.1], [hooks[1] + dx * 1.6, -0.55, -0.08]], 0.09,
                         {'seg': 10, 'up': [0, 0, 1]}), K.mat(game, 'fabric', PAL.mustard, {'side': THREE.DoubleSide}), {'cast': False}))
    # pink boa on hook 3
    hx = hooks[2]
    boaCurve = THREE.CatmullRomCurve3([THREE.Vector3(q[0], q[1], q[2]) for q in
                                       [[hx - 0.1, -0.7, -0.1], [hx - 0.07, -0.3, -0.11], [hx - 0.02, 0.03, -0.13], [hx + 0.04, 0.03, -0.13],
                                        [hx + 0.09, -0.35, -0.11], [hx + 0.12, -0.62, -0.1]]])
    g.add(K.m(boaGeo(boaCurve, 44, 0.036), mt.fabric, {'cast': False}))
    # tote bag on hook 4
    g.add(K.m(K.tube([[hooks[3] - 0.08, -0.2, -0.12], [hooks[3], 0.04, -0.13], [hooks[3] + 0.08, -0.2, -0.12]], 0.008, {'seg': 10, 'radial': 4}),
              K.mat(game, 'fabric', '#5A3A22')))
    g.add(K.m(tc(K.box(0.26, 0.28, 0.07, 'md'), '#8C9A3A'), mt.fabric, {'pos': [hooks[3], -0.34, -0.1]}))
    g.add(K.m(tc(K.box(0.18, 0.08, 0.072, 'sm'), '#E8A92E'), mt.fabric, {'pos': [hooks[3], -0.3, -0.105]}))
    g.userData.colliders = []
    return K.finish(game, g, {'ao': {'floor': False, 'height': 0, 'res': 32}})


# ---------------------------------------------------------------------------------------- garment rack
# Rolling chrome rack with costumes fanned on hangers (sequin jacket, the Baron's spare cape, a cowboy shirt, a
# giant Sock Hopper costume, a white disco suit, a plaid blazer). Front -z.
def jacketShape(w, h, sleeve=True):
    s = THREE.Shape()
    s.moveTo(-0.05, 0)
    s.lineTo(-w / 2, -0.06)
    if sleeve:
        s.lineTo(-w / 2 - 0.08, -h * 0.72)
        s.lineTo(-w / 2 + 0.03, -h * 0.74)
    s.lineTo(-w / 2 + 0.04, -h)
    s.lineTo(w / 2 - 0.04, -h)
    if sleeve:
        s.lineTo(w / 2 - 0.03, -h * 0.74)
        s.lineTo(w / 2 + 0.08, -h * 0.72)
    s.lineTo(w / 2, -0.06)
    s.lineTo(0.05, 0)
    s.lineTo(0, -0.08)
    s.closePath()
    return s


def garmentRack(game):
    g = K.prop('gm_garment_rack')
    mt = stdMats(game)
    L, H = 1.7, 1.75
    for s in [-1, 1]:
        g.add(K.m(K.cyl(0.018, 0.018, H - 0.1, {'seg': 10}), mt.chrome, {'pos': [s * L / 2, 0.08, 0]}))
        g.add(K.m(K.box(0.05, 0.04, 0.5, 'sm'), mt.chrome, {'pos': [s * L / 2, 0.08, 0]}))
        for d in [-1, 1]:
            g.add(K.m(tc(sph(0.035, 10, 8), '#2A2231'), mt.rubber, {'pos': [s * L / 2, 0.035, d * 0.23]}))
    g.add(K.m(K.cyl(0.016, 0.016, L + 0.06, {'seg': 10}), mt.chrome, {'pos': [-L / 2 - 0.03, H - 0.02, 0], 'rot': [0, 0, -HP]}))
    cloth = [
        {'c': '#E8A92E', 'w': 0.44, 'h': 0.66, 'sleeve': True, 'trim': '#FFE3A3'},
        {'c': '#6B3A6E', 'w': 0.5, 'h': 1.15, 'sleeve': False, 'trim': '#E23B3B'},
        {'c': '#E23B3B', 'w': 0.42, 'h': 0.62, 'sleeve': True, 'trim': '#F4F1E8'},
        {'c': 'sock', 'w': 0.34, 'h': 1.0},
        {'c': '#F4F1E8', 'w': 0.44, 'h': 1.2, 'sleeve': True, 'trim': '#FFC23A'},
        {'c': '#B5472A', 'w': 0.44, 'h': 0.7, 'sleeve': True, 'trim': '#E8A92E'},
    ]
    for i, k in enumerate(cloth):
        x = -L / 2 + 0.2 + i * ((L - 0.4) / (len(cloth) - 1))
        grp = THREE.Group()
        grp.position.set(x, H - 0.03, 0)
        grp.rotation.y = (-1 if i % 2 else 1) * (0.7 + hash_(i * 5.1) * 0.25)
        # hanger
        grp.add(K.m(THREE.TorusGeometry(0.03, 0.005, 5, 10, PI * 1.4), mt.chrome, {'pos': [0, 0.01, 0], 'rot': [0, HP, 0.3]}))
        grp.add(K.m(K.tube([[-0.2, -0.1, 0], [0, -0.03, 0], [0.2, -0.1, 0]], 0.008, {'seg': 8, 'radial': 4}), mt.teak))
        if k['c'] == 'sock':
            # giant striped sock costume (Sockette)
            stripes = ['#E23B3B', '#F4E03A', '#3A58E4', '#F4F1E8']
            for j in range(7):
                grp.add(K.m(tc(K.cyl(0.16, 0.16, 0.13, {'seg': 16}), stripes[j % 4]), mt.fabric, {'pos': [0, -0.12 - (j + 1) * 0.13, 0]}))
            grp.add(K.m(tc(sph(0.17, 16, 10), '#F4F1E8'), mt.fabric, {'pos': [0.06, -1.07, -0.05], 'scale': [1.3, 0.8, 1]}))
            for s in [-1, 1]:
                grp.add(K.m(tc(sph(0.05, 10, 8), '#FBF8F1'), mt.plastic, {'pos': [s * 0.06, -0.3, -0.15]}))
                grp.add(K.m(tc(sph(0.025, 8, 6), '#1E1530'), mt.plastic, {'pos': [s * 0.06 + 0.01, -0.31, -0.19]}))
            grp.add(K.m(tc(sph(0.04, 10, 8), '#E23B3B'), mt.plastic, {'pos': [0, -0.42, -0.16], 'scale': [1.4, 0.6, 0.6]}))
        else:
            grp.add(K.m(tc(K.extrude(jacketShape(k['w'], k['h'], k['sleeve']), 0.07, {'bevel': 0.025, 'curveSeg': 2, 'bevelSeg': 2}), k['c']),
                        mt.fabric, {'pos': [0, -0.08, 0]}))
            # lapels / trim stripes on the front face (-z)
            for s in [-1, 1]:
                grp.add(K.m(tc(K.box(0.035, k['h'] * 0.78, 0.02, 'xs'), k['trim']), mt.plastic,
                            {'pos': [s * 0.045, -0.12 - k['h'] * 0.39, -0.055], 'rot': [0, 0, s * 0.08]}))
            if k['sleeve']:
                for j in range(3):
                    grp.add(K.m(tc(sph(0.014, 8, 6), k['trim']), mt.plastic, {'pos': [0.075, -0.3 - j * 0.12, -0.06]}))
        g.add(grp)
    # price-tag style costume tags
    g.userData.colliders = [{'min': [-L / 2 - 0.05, 0, -0.34], 'max': [L / 2 + 0.05, H + 0.05, 0.34]}]
    return K.finish(game, g, {'ao': {'res': 40}})


# ------------------------------------------------------------------------ steamer trunk + Hootie costume head
def trunkAndHead(game):
    g = K.prop('gm_trunk_hootie')
    mt = stdMats(game)
    TW, TH, TD = 0.86, 0.46, 0.5
    g.add(K.m(tc(K.box(TW, TH, TD, 'md'), '#2A3A8A'), mt.lacquer, {'pos': [0, TH / 2, 0]}))
    g.add(K.m(tc(K.box(TW + 0.01, 0.03, TD + 0.01, 'sm'), '#5A3A22'), mt.lacquer, {'pos': [0, TH - 0.08, 0]}))
    for x in [-0.26, 0.26]:
        g.add(K.m(tc(K.box(0.06, TH + 0.012, TD + 0.012, 'sm'), '#6A4A30'), mt.paint, {'pos': [x, TH / 2, 0]}))
    for x, z in [[-1, -1], [1, -1], [-1, 1], [1, 1]]:
        for y in [0.03, TH - 0.03]:
            g.add(K.m(K.box(0.07, 0.07, 0.07, 'sm'), mt.brass, {'pos': [x * (TW / 2 - 0.025), y, z * (TD / 2 - 0.025)]}))
    g.add(K.m(K.box(0.08, 0.07, 0.02, 'sm'), mt.brass, {'pos': [0, TH - 0.12, -TD / 2 - 0.008]}))
    for x, y, c, r in [[-0.12, 0.2, '#E23B3B', 0.06], [0.12, 0.28, '#F4E03A', 0.05], [0.1, 0.12, '#52D24A', 0.045]]:
        g.add(K.m(tc(K.cyl(r, r, 0.006, {'seg': 16}), c), mt.paint, {'pos': [x, y, -TD / 2 - 0.003], 'rot': [HP, 0, 0]}))
    # Hootie the owl costume head: round brown head, heart-shaped cream face discs, huge amber-ringed eyes, V brow,
    # little orange beak, feather tufts, a chevron bib and an orange collar ring. It sits on the trunk.
    head = THREE.Group()
    head.position.set(0.02, TH, 0)
    head.rotation.y = -0.35
    brown, light = '#8A5530', '#F6E2B8'
    head.add(K.m(tc(sph(0.3, 22, 16), brown), mt.fabric, {'pos': [0, 0.3, 0], 'scale': [1.05, 0.95, 0.95]}))
    for s in [-1, 1]:
        head.add(K.m(tc(sph(0.15, 18, 12), light), mt.fabric, {'pos': [s * 0.1, 0.33, -0.17], 'scale': [1, 1.05, 0.5]}))
        head.add(K.m(tc(sph(0.1, 16, 12), '#FBF8F1'), mt.plastic, {'pos': [s * 0.1, 0.34, -0.23]}))
        head.add(K.m(tc(sph(0.07, 14, 10), '#F2A23A'), mt.plastic, {'pos': [s * 0.1, 0.34, -0.285]}))
        head.add(K.m(tc(sph(0.045, 12, 10), '#1E1530'), mt.plastic, {'pos': [s * 0.1 + s * 0.008, 0.34, -0.33]}))
        head.add(K.m(tc(sph(0.015, 8, 6), '#FFFFFF'), mt.plastic, {'pos': [s * 0.1 - 0.015, 0.36, -0.37]}))
        head.add(K.m(tc(K.box(0.14, 0.032, 0.05, 'sm'), '#4A2A14'), mt.fabric, {'pos': [s * 0.105, 0.475, -0.26], 'rot': [0.25, 0, -s * 0.18]}))
        head.add(K.m(tc(K.cyl(0.0, 0.055, 0.13, {'seg': 10}), brown), mt.fabric, {'pos': [s * 0.2, 0.52, -0.02], 'rot': [-0.2, 0, s * 0.62]}))
    head.add(K.m(tc(K.cyl(0.0, 0.045, 0.1, {'seg': 10}), '#FF8A2A'), mt.plastic, {'pos': [0, 0.25, -0.33], 'rot': [-HP - 0.5, 0, 0]}))
    for j in range(3):
        head.add(K.m(tc(K.box(0.07, 0.025, 0.03, 'xs'), '#C8864A'), mt.fabric,
                     {'pos': [0, 0.14 - j * 0.035, -0.27 + j * 0.02], 'rot': [0, 0, 0.5 if j % 2 else -0.5]}))
    head.add(K.m(tc(K.cyl(0.26, 0.28, 0.06, {'seg': 20}), '#E3662B'), mt.fabric, {'pos': [0, 0.0, 0]}))
    head.add(K.m(tc(K.cyl(0.14, 0.14, 0.01, {'seg': 18}), '#2A1A12'), mt.fabric, {'pos': [0, 0.061, 0]}))
    g.add(head)
    g.userData.colliders = [{'min': [-TW / 2, 0, -TD / 2], 'max': [TW / 2, TH + 0.6, TD / 2]}]
    return K.finish(game, g, {'ao': {'res': 40}})


# ------------------------------------------------------------------------------------------- hi-fi console
def hifi(game, ga):
    g = K.prop('gm_hifi')
    mt = stdMats(game)
    W, H, D = 1.6, 0.62, 0.44
    grille = K.mat(game, 'fabric', '#ffffff', {'map': K.tex.weave('#7A5A3A', {'pattern': 'cord'})})
    g.add(K.m(K.box(W, H - 0.1, D, 0.03, {'uv': 1.5}), mt.walnut, {'pos': [0, 0.1 + (H - 0.1) / 2, 0]}))
    for x, z in [[-1, -1], [1, -1], [-1, 1], [1, 1]]:
        g.add(K.m(K.cyl(0.018, 0.012, 0.12, {'seg': 8}), mt.walnut, {'pos': [x * (W / 2 - 0.08), 0, z * (D / 2 - 0.06)]}))
    for s in [-1, 1]:
        g.add(K.m(K.box(0.44, 0.38, 0.01, 'sm'), grille, {'pos': [s * 0.54, 0.36, -D / 2 - 0.004]}))
    g.add(K.m(gPlane(ga, 'hifi', 0.56, 0.28), ga.mat, {'pos': [0, 0.4, -D / 2 - 0.006]}))
    for i in range(3):
        g.add(K.m(tc(K.cyl(0.02, 0.022, 0.03, {'seg': 12}), '#2A2231'), mt.plastic, {'pos': [-0.16 + i * 0.16, 0.22, -D / 2 - 0.012], 'rot': [HP, 0, 0]}))
    # turntable on top
    tt = THREE.Group()
    tt.position.set(-0.2, H, 0)
    tt.add(K.m(tc(K.box(0.5, 0.06, 0.38, 'sm'), '#D8D2C2'), mt.plastic, {'pos': [0, 0.03, 0]}))
    tt.add(K.m(K.cyl(0.15, 0.15, 0.02, {'seg': 28}), mt.chrome, {'pos': [-0.05, 0.06, 0]}))
    tt.add(K.m(tc(K.cyl(0.148, 0.148, 0.006, {'seg': 28}), '#1E1822'), mt.plastic, {'pos': [-0.05, 0.08, 0]}))
    tt.add(K.m(tc(K.cyl(0.05, 0.05, 0.007, {'seg': 16}), '#E23B3B'), mt.plastic, {'pos': [-0.05, 0.081, 0]}))
    tt.add(K.m(K.tube([[0.18, 0.1, 0.12], [0.16, 0.11, -0.04], [0.05, 0.1, -0.1]], 0.007, {'seg': 8, 'radial': 5}), mt.chrome))
    g.add(tt)
    # record sleeves leaning against the side + a snake plant on top
    for i, n in enumerate(['lp1', 'lp2', 'lp3', 'lp4']):
        grp = THREE.Group()
        grp.position.set(W / 2 + 0.06 + i * 0.012, 0, -0.05 + i * 0.01)
        grp.rotation.set(0, -HP + 0.2, -0.18 + i * 0.04)
        grp.add(K.m(tc(K.box(0.3, 0.3, 0.006, 'xs'), '#F4F1E8'), mt.paint, {'pos': [0, 0.15, 0]}))
        grp.add(K.m(gPlane(ga, n, 0.29, 0.29), ga.mat, {'pos': [0, 0.15, -0.0035]}))
        g.add(grp)
    g.userData.colliders = [{'min': [-W / 2, 0, -D / 2], 'max': [W / 2 + 0.2, H + 0.12, D / 2]}]
    return K.finish(game, g, {'ao': {'res': 40}})


# ------------------------------------------------------------------------------ payphone shelf + phone book
def phoneShelf(game, ga):
    g = K.prop('gm_phone_shelf')
    mt = stdMats(game)
    g.add(K.m(tc(K.box(0.42, 0.03, 0.26, 'sm'), '#9EA4AE'), mt.metal, {'pos': [0, 0, -0.13]}))
    for s in [-1, 1]:
        g.add(K.m(tc(K.box(0.02, 0.16, 0.2, 'xs'), '#9EA4AE'), mt.metal, {'pos': [s * 0.2, -0.08, -0.1]}))
    # phone book hanging on a chain + lying ajar
    book = THREE.Group()
    book.position.set(0.05, -0.36, -0.06)
    book.rotation.set(0.05, 0, 0.08)
    book.add(K.m(tc(K.box(0.2, 0.26, 0.06, 'sm'), '#F4D23A'), mt.paint))
    book.add(K.m(gPlane(ga, 'phonebook', 0.18, 0.2), ga.mat, {'pos': [0, 0, -0.0305]}))
    book.add(K.m(tc(K.box(0.19, 0.25, 0.052, 'xs'), '#FBF4E0'), mt.paint, {'pos': [0.006, 0, 0.002]}))
    g.add(book)
    g.add(K.m(K.tube([[0.12, -0.02, -0.04], [0.14, -0.12, -0.05], [0.12, -0.22, -0.06]], 0.005, {'seg': 8, 'radial': 4}), mt.chrome))
    g.add(K.m(cellPlane('memo', 0.14, 0.14, {'face': '-z'}), atlasMats(game).decal, {'pos': [-0.3, 0.52, -0.005], 'rot': [0, 0, 0.1]}))
    g.add(K.m(gPlane(ga, 'note', 0.14, 0.14), ga.decal, {'pos': [0.34, 0.66, -0.005], 'rot': [0, 0, -0.08]}))
    g.add(K.m(gPlane(ga, 'doodle', 0.34, 0.34), ga.decal, {'pos': [-0.36, 0.1, -0.004]}))
    g.userData.colliders = []
    return K.finish(game, g, {'ao': {'floor': False, 'height': 0, 'res': 28}})


# ----------------------------------------------------------------------------------------------- bar stool
def barStool(game):
    g = K.prop('gm_stool')
    mt = stdMats(game)
    vinyl = K.mat(game, 'vinyl', '#ffffff', {'map': K.tex.pebble('#E23B3B')})
    g.add(K.m(K.lathe([[0, 0], [0.2, 0], [0.205, 0.015], [0.14, 0.03], [0, 0.035]], {'seg': 22, 'round': 0.006}), mt.chrome))
    g.add(K.m(K.cyl(0.03, 0.035, 0.62, {'seg': 12}), mt.chrome, {'pos': [0, 0.03, 0]}))
    g.add(K.m(THREE.TorusGeometry(0.15, 0.012, 6, 22), mt.chrome, {'pos': [0, 0.28, 0], 'rot': [HP, 0, 0]}))
    g.add(K.m(K.cushion(0.36, 0.1, 0.36, {'puff': 0.04, 'r': 0.05}), vinyl, {'pos': [0, 0.7, 0]}))
    g.userData.colliders = [{'min': [-0.2, 0, -0.2], 'max': [0.2, 0.75, 0.2]}]
    return K.finish(game, g, {'ao': {'res': 28}})


# Meshes added straight under the room (not through K.finish) whose material wants vertex colours get a white
# colour attribute (else the toon shader reads black where the level merge leaves a mesh alone).
def ensureColors(root):
    def f(o):
        if not getattr(o, 'isMesh', False) or o.material is None or isinstance(o.material, list) or not o.material.vertexColors:
            return
        g = o.geometry
        if g is None or g.attributes.color is not None:
            return
        c = g.clone()
        c.setAttribute('color', THREE.BufferAttribute(np.ones((c.attributes.position.count, 3)), 3))
        o.geometry = c
    root.traverse(f)


# ============================================================================================ the rooms
def _named(m, name):
    m.name = name
    return m


def lobbyAssets(game):
    """lobby.js build(): the local builders (placed by lobby.gd with kit.put) + the loose meshes of the area root."""
    am = atlasMats(game)
    WALL = JSObj(n=-5.85, s=5.85, w=-6.85, e=6.85)
    out = {
        'lg_velvet_ropes': velvetRopes(game, [[4.22, 4.72], [4.22, 3.72], [5.5, 3.72], [6.72, 3.72]]),
        'lg_wall_shelf': wallShelf(game, 0.66, 0.5),
        'lg_exit': exitSign(game, am),
        'lg_plinth': plinth(game, am, 1.22),
        'lg_sign_post': signPost(game, K.getCard('sign_see_yourself')),
        'lg_announcer_desk': announcerDesk(game, am),
        'lg_doormat': doormat(game, am),
    }
    root = THREE.Group()
    root.name = 'lobby_dressing'
    # gold lettering on the booth glass (lobby side)
    glassTxt = Mesh(cellPlane('glassAnnounce', 1.5, 0.375), am.decal)
    glassTxt.position.set(-5.8, 2.25, -2.975)
    glassTxt.castShadow = False
    root.add(_named(glassTxt, 'glass_announce'))
    # camera cable snaking to a wall box
    cable = K.m(K.tube([[5.9, 0.03, 5.1], [6.2, 0.03, 5.35], [6.5, 0.03, 5.4], [6.78, 0.08, 5.45], [6.8, 0.35, 5.5]], 0.022,
                       {'seg': 20, 'radial': 6}), K.mat(game, 'rubber', '#2A2230'))
    root.add(_named(cable, 'camera_cable'))
    # papers + pledge cards around the desk and booth
    for name, x, z, r, s in [
        ['pledge', 1.6, 0.55, 0.4, 0.2], ['script', -1.2, 0.7, -0.5, 0.26], ['pledge', -2.6, -0.2, 1.1, 0.2],
        ['memo', 2.5, -1.25, 0.3, 0.14], ['paper', -4.1, -4.1, 0.25, 0.5], ['ticket', 3.4, 2.4, -0.7, 0.16],
        ['script2', -3.6, -2.4, 0.8, 0.26], ['pledge', 0.8, 1.9, 2.4, 0.18],
    ]:
        hgt = 0.25 if name == 'paper' else s * (1.33 if name.startswith('script') else 1.15)
        root.add(decal(am.paper, name, s, hgt, [x, 0.0, z], r))
    # fallen SIGN OFF letters (letter_board.letters)
    for i, (L, x, z, r) in enumerate([['S', 0.55, 4.55, 0.5], ['I', -0.35, 3.25, -0.9], ['G', 1.95, 4.35, 2.2], ['N', 0.1, 4.95, 1.4],
                                      ['O', -0.95, 4.2, 0.2], ['F', 2.35, 3.7, -0.4], ['F', 1.2, 3.55, 2.9]]):
        m = decal(am.decal, L, 0.19, 0.19, [x, 0.0, z], r)
        m.userData.noMerge = True
        root.add(_named(m, 'letter_%d' % i))
    # moonlight slats: the two front doors, then the west window (lobby.js order)
    n = 0
    for x in [-3, 3]:
        _named(moonSlats(game, root, [x, 0, WALL.s], 0, {'w': 1.7, 'd': 2.7, 'shear': 0.28 if x < 0 else -0.28}), 'moon_slats_%d' % n)
        n += 1
    _named(moonSlats(game, root, [WALL.w, 0, 0], -PI / 2, {'w': 1.7, 'd': 2.4, 'shear': 0.22, 'pre': 0.4, 'post': 0.22}), 'moon_slats_%d' % n)
    ensureColors(root)
    out['lobby_dressing'] = root
    return out


def greenAssets(game):
    """green_room.js build(): the local builders (placed by green_room.gd with kit.put) + the loose meshes."""
    am = atlasMats(game)
    ga = gmAtlas(game)
    mt = stdMats(game)
    WALL = WALL_G
    out = {
        'gm_vanity': vanity(game, am, ga, {'len': 4.8}),
        'gm_makeup_chair': makeupChair(game),
        'gm_director_chair__roxy': directorChair(game, ga, 'chair_roxy', '#6B3A6E'),
        'gm_director_chair__talent': directorChair(game, ga, 'chair_talent', '#2F5BD3'),
        'gm_wall_tv': wallTV(game),
        'gm_coat_rail': coatRail(game),
        'gm_garment_rack': garmentRack(game),
        'gm_trunk_hootie': trunkAndHead(game),
        'gm_hifi': hifi(game, ga),
        'gm_phone_shelf': phoneShelf(game, ga),
        'gm_stool': barStool(game),
    }
    root = THREE.Group()
    root.name = 'green_room_dressing'

    def add(m):
        root.add(m)
        return m
    # west end: bottle caps by the vending machines
    for x, z, r, c in [[-4.95, -10.6, 0.4, '#D8342C'], [-4.35, -10.35, 1.8, '#E3662B'], [-5.6, -10.3, 2.6, '#D8342C']]:
        add(K.m(tc(K.cyl(0.032, 0.03, 0.05, {'seg': 12}), c), mt.lacquer, {'pos': [x, 0.032, z], 'rot': [HP, r, 0], 'scale': [1, 0.55, 1], 'cast': False}))
    lp = [-4.0, 0.9, -11.3]   # ANCHORS.toy_lava_lamp.pos
    add(decal(am.paper, 'boa', 0.16, 0.16, [lp[0] + 0.5, 0, lp[2] + 0.55], 0.6))
    moonSlats(game, root, [WALL.w, 0, -9], -HP, {'w': 1.6, 'd': 2.5, 'shear': 0.2, 'pre': 0.42, 'post': 0.2}).name = 'moon_slats_0'

    # the Baron's door leak: additive: brightness lives in RGB (black = nothing), fading away from the door and at the sides
    def leakDraw(ctx, w, h, rand):
        ctx.fillStyle = '#000'
        ctx.fillRect(0, 0, w, h)
        for x in range(w):
            k = math.sin((x / (w - 1)) * math.pi) ** 1.5
            g = ctx.createLinearGradient(0, 0, 0, h)
            g.addColorStop(0, 'rgba(255,255,255,%s)' % js_str(k))
            g.addColorStop(0.35, 'rgba(255,255,255,%s)' % js_str(k * 0.35))
            g.addColorStop(1, 'rgba(255,255,255,0)')
            ctx.fillStyle = g
            ctx.fillRect(x, 0, 1, h)
    leak = K.tex.canvas('rooms.gm.leak.v2', 128, 64, leakDraw, {'repeat': False})
    lm = game.mats.glow('#B070FF', 1.25, {'map': leak, 'additive': True, 'fog': False})
    strip = Mesh(THREE.PlaneGeometry(0.95, 0.55).rotateX(-HP).translate(0, 0, -0.275), lm)
    strip.position.set(-6.3, 0.011, WALL.s - 0.06)
    strip.renderOrder = 2
    strip.userData.noMerge = True
    add(_named(strip, 'baron_leak'))
    VX = 5.3
    add(decal(am.paper, 'cucumber', 0.07, 0.07, [VX - 0.35, 0, -7.95], 0.2))
    add(decal(am.paper, 'cucumber', 0.07, 0.07, [VX + 0.4, 0, -8.1], 1.4))
    add(decal(am.paper, 'towel', 0.4, 0.2, [VX + 0.9, 0, -7.9], 0.5))
    add(decal(am.paper, 'fan', 0.24, 0.24, [VX - 2.3, 0, -8.0], -0.4))
    mk = Mesh(cellPlane('makeup', 1.7, 0.425), am.decal)
    mk.position.set(VX, 2.62, WALL.s - 0.045)
    mk.rotation.y = PI
    add(_named(mk, 'makeup_sign'))
    add(K.m(tc(K.box(1.84, 0.52, 0.03, 'sm'), '#4A2E22'), mt.lacquer, {'pos': [VX, 2.62, WALL.s - 0.012]}))
    quiet = Mesh(cellPlane('quiet', 1.2, 0.3), am.decal)
    quiet.position.set(6.8, 2.62, WALL.n + 0.04)
    add(_named(quiet, 'quiet_sign'))
    add(K.m(tc(K.box(1.28, 0.36, 0.03, 'sm'), '#2A2231'), mt.lacquer, {'pos': [6.8, 2.62, WALL.n + 0.004]}))
    add(decal(am.paper, 'script2', 0.2, 0.26, [6.2, 0, -10.2], 0.7))
    add(decal(am.paper, 'sheet', 0.2, 0.26, [7.9, 0, -9.7], -0.4))
    add(K.m(tc(THREE.CylinderGeometry(0.028, 0.02, 0.07, 10, 1, True), '#F4F1E8'), mt.plastic, {'pos': [11.4, 0.02, -11.2], 'rot': [HP, 0, 0.6]}))
    cb = Mesh(cellPlane('callboard', 1.2, 0.3), am.decal)
    cb.position.set(15.05, 2.12, WALL.s - 0.02)
    cb.rotation.y = PI
    add(_named(cb, 'callboard_sign'))
    # floor clutter
    for name, x, z, r, s in [
        ['script', -3.9, -8.3, 0.5, 0.24], ['pledge', 0.4, -9.9, -0.6, 0.18], ['sheet2', 1.6, -9.0, 1.1, 0.24],
        ['cup', 2.3, -10.8, 0, 0.1], ['memo', -2.2, -7.2, 0.9, 0.14], ['ticket', 13.1, -7.0, -0.3, 0.14],
    ]:
        add(decal(am.paper, name, s, s * (1.3 if name.startswith('script') or name.startswith('sheet') else 1), [x, 0, z], r))
    # make-up station cable (moves with the vanity; its wall end stays 0.45 m clear of D2's swing)
    cable = K.m(K.tube([[VX - 1.2, 0.02, -6.6], [VX - 1.05, 0.02, -7.4], [VX - 2.05, 0.02, -8.15], [VX - 2.5, 0.03, -7.3],
                        [VX - 2.46, 0.1, -6.35]], 0.012, {'seg': 20, 'radial': 5}), K.mat(game, 'rubber', '#2A2230'))
    add(_named(cable, 'makeup_cable'))
    ensureColors(root)
    out['green_room_dressing'] = root
    return out


# ------------------------------------------------------------------------------------------------ build
def build(save_blend=False, only=None):
    """Builds every lobby / green room asset into godot/assets/runtime/rooms_lobby|rooms_green_room/.
    only: asset names (lg_exit, gm_vanity, lobby_dressing …) or 'lobby' / 'green_room' for a whole room.
    Returns the written paths."""
    from dalib import export as EX
    game = K.Game()
    written = []
    for out_dir, tag, assets in [(OUT_LOBBY, 'lobby', lobbyAssets), (OUT_GREEN, 'green_room', greenAssets)]:
        for name, root in assets(game).items():
            if only and name not in only and tag not in only:
                continue
            path = os.path.join(out_dir, name + '.glb')
            blend = os.path.join(BLEND_OUT, 'runtime_rooms_%s_%s.blend' % (tag, name)) if save_blend else None
            EX.export_graph(root, path, root_name=name, save_blend=blend)
            written.append(path)
            print('[runtime/rooms_lobby_green] %s' % path, flush=True)
    return written


if __name__ == '__main__':
    args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
    build(save_blend='--save-blend' in args, only=[a for a in args if not a.startswith('--')] or None)
