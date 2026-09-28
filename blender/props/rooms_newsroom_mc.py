"""DEAD AIR — room-only props of the NEWSROOM and MASTER CONTROL (port of the prop builders of
src/world/rooms/newsroom.js and src/world/rooms/master_control.js, line by line).

newsroom.js registers its room-only props (category 'rooms_nm', same ids / opts as the JS):
  nm_teletype     wire-service teletype on its pedestal (toy_teletype): parts head, paper, tape, bulb, keys
  nm_typewriter   toy typewriter {color}: parts carriage, keys, sheet
  nm_desk_bare    bare sage tanker desk {color}
  nm_globe        teak tripod floor globe (toy_globe): parts globe, tilt
  nm_coffee_cart  rolling coffee cart
  nm_desk_lamp    gooseneck desk lamp {color}: parts bulb (dimmable glow)
  nm_skyline      night-skyline news backdrop {w, h}: parts face
master_control.js builds its local props with K.prop('mc_*') + K.finish (never registered in the JS); they are
registered here with those ids (category 'rooms_mc') so rooms/master_control.gd builds them with game.props.build:
  mc_laff_o_matic  Laff-O-Matic cart: parts button, needle, lampL, lampR; lampMats {on, off, onR, offR}
  mc_switcher      ROUTE-O-MATIC 16 routing switcher cart: parts keys (live key canvas: runtime texture)
  mc_scope_cart    waveform / vectorscope cart: parts faces; lampMats {on, off}
  mc_tape_shelf    quad-tape library shelving (one empty SIGN OFF slot)
  mc_cable_tray    hanging ladder cable tray {L, rod}
  mc_picture_light brass picture light: parts glow
  mc_extinguisher  wall fire extinguisher + FIRE sign
  mc_floor_fan     oscillating floor fan: parts head, blades
  mc_tape_cart     tape library cart
  mc_tape_stack    tape-box floor stack {n, seed}
  mc_meter_panel   TRANSMITTER REMOTE meter panel: parts needles [3], lamps; lampMats {on, off}
The shared room toolkit of newsroom.js (stdMats, atlas, quad, ribbon, tc, drawText, the paper/print atlas, the decal
atlas, slat / wash textures) and master_control.js (mcAtlas, qf, hash, cart) lives here too;
blender/runtime/rooms_newsroom_mc.py imports it for the meshes the rooms add straight under their dressing root.

Runtime-only parts: dimmableGlow() materials are exported as glow specs (colour, intensity): the room scripts give
each lamp its own clone and drive its level; the switcher key canvas and the LED speckle canvas are runtime textures
(spec "runtime": true) that the room scripts draw with DACanvas.
"""
import math

from dalib import kit as K
from dalib.kit import registerProp, PAL, THREE
from dalib.mathutils3 import js_str, js_round
from dalib.tex import RuntimeTexture

TAU = math.pi * 2
HP = math.pi / 2
PI = math.pi


# ================================================================================================ toolkit
def yawTo(frm, to):
    return math.atan2(-(to[0] - frm[0]), -(to[2] - frm[2]))


def tc(geo, color):
    return K.tint(geo.clone(), color)


def v3(a):
    return THREE.Vector3(a[0], a[1], a[2])


# The furniture kit's shared white-base materials (vertex tints carry the colour): same instances as the
# library's props, so the level merge folds our meshes into the draws it already has.
class _Obj(dict):
    def __getattr__(self, k):
        try:
            return self[k]
        except KeyError:
            raise AttributeError(k)


def stdMats(game):
    return _Obj(
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


# ------------------------------------------------------------------------------------------------ atlas
# 1024² paper/print atlas (4 x 4 cells of 256 px) shared by both rooms + a 512² alpha atlas (2 x 2) for floor
# decals. cell(c, r) -> [u0, v0, u1, v1] (r counted from the top).
CELLS = {
    'page': [0, 0], 'news': [1, 0], 'wire': [2, 0], 'memo': [3, 0],
    'sched': [0, 1], 'quiet': [1, 1], 'eng': [2, 1], 'spines': [3, 1],
    'bars': [0, 2], 'donut': [1, 2], 'logo13': [2, 2], 'promo': [3, 2],
    'panel': [0, 3], 'plate': [1, 3], 'assign': [2, 3], 'cream': [3, 3],
}
DECALS = {'stain': [0, 0], 'scuff': [1, 0], 'tapeX': [0, 1], 'dust': [1, 1]}


def drawText(ctx, s, x, y, o=None):
    o = o or {}
    font = o.get('font', 'Bungee')
    size = o.get('size', 20)
    fill = o.get('fill', '#222')
    align = o.get('align', 'center')
    rot = o.get('rot', 0)
    maxW = o.get('maxW', 0)
    ctx.save()
    ctx.translate(x, y)
    ctx.rotate(rot)
    sz = size
    ctx.font = '%spx "%s", "Arial Black", sans-serif' % (js_str(sz), font)
    if maxW:
        while ctx.measureText(s).width > maxW and sz > 6:
            sz *= 0.92
            ctx.font = '%spx "%s", "Arial Black", sans-serif' % (js_str(sz), font)
    ctx.textAlign = align
    ctx.textBaseline = 'middle'
    ctx.fillStyle = fill
    ctx.fillText(s, 0, 0)
    ctx.restore()


def rrect(ctx, x, y, w, h, r):
    ctx.beginPath()
    ctx.roundRect(x, y, w, h, r)


def lines(ctx, x, y, w, rows, gap, rand, color='rgba(40,40,60,0.55)', thick=3):
    ctx.fillStyle = color
    for i in range(rows):
        ln = w * (0.55 + rand() * 0.45)
        ctx.fillRect(x, y + i * gap, ln, thick)


def paintAtlas(ctx, W, H, rand):
    S = 256

    def at(c, r, fn):
        ctx.save()
        ctx.translate(c * S, r * S)
        ctx.beginPath()
        ctx.rect(0, 0, S, S)
        ctx.clip()
        fn()
        ctx.restore()

    # typed page
    def page():
        ctx.fillStyle = '#F7F2E4'
        ctx.fillRect(0, 0, S, S)
        ctx.fillStyle = '#E23B3B'
        ctx.fillRect(18, 18, 120, 10)
        drawText(ctx, 'ACTION 13 NEWS', 22, 42, {'font': 'Titan One', 'size': 16, 'fill': '#2F5BD3', 'align': 'left'})
        lines(ctx, 22, 66, 210, 11, 16, rand, 'rgba(50,40,60,0.6)', 4)
        ctx.strokeStyle = 'rgba(226,59,59,0.7)'
        ctx.lineWidth = 3
        ctx.beginPath()
        ctx.moveTo(30, 150)
        ctx.lineTo(190, 146)
        ctx.stroke()
    at(0, 0, page)

    # newspaper
    def news():
        ctx.fillStyle = '#EDE6D2'
        ctx.fillRect(0, 0, S, S)
        drawText(ctx, 'THE DAILY SIGNAL', S / 2, 26, {'font': 'Shrikhand', 'size': 26, 'fill': '#2A2230', 'maxW': 230})
        ctx.fillStyle = '#2A2230'
        ctx.fillRect(12, 44, S - 24, 3)
        drawText(ctx, 'TELETHON TONIGHT!', S / 2, 70, {'font': 'Bungee', 'size': 24, 'fill': '#2A2230', 'maxW': 230})
        ctx.fillStyle = '#9A9080'
        ctx.fillRect(14, 92, 104, 76)
        ctx.fillStyle = '#6A6258'
        ctx.beginPath()
        ctx.arc(66, 128, 22, 0, TAU)
        ctx.fill()
        lines(ctx, 128, 96, 112, 8, 10, rand, 'rgba(40,40,50,0.55)', 3)
        lines(ctx, 14, 182, 228, 6, 11, rand, 'rgba(40,40,50,0.55)', 3)
    at(1, 0, news)

    # teletype wire copy (continuous feed)
    def wire():
        ctx.fillStyle = '#F4EBC8'
        ctx.fillRect(0, 0, S, S)
        for i in range(4):
            ctx.fillStyle = 'rgba(160,140,90,0.25)'
            ctx.fillRect(0, i * 64 + 30, S, 2)
        words = ['ZCZC', 'BULLETIN', 'WZTV', 'WIRE', 'MORE', 'URGENT', 'CITY', 'STORM', 'WATCH', 'NNNN', 'TOWER', '11:59']
        ctx.font = 'bold 15px "Courier New", monospace'
        ctx.fillStyle = '#3A3050'
        ctx.textBaseline = 'middle'
        for i in range(14):
            s = ''
            k = 0
            while k < 3 + math.floor(rand() * 3):     # the bound is re-evaluated every iteration, like the JS
                s += words[int(math.floor(rand() * len(words)))] + ' '
                k += 1
            ctx.fillText(s, 14, 14 + i * 17)
    at(2, 0, wire)

    # yellow memo
    def memo():
        ctx.fillStyle = '#FFF0A0'
        ctx.fillRect(0, 0, S, S)
        ctx.fillStyle = 'rgba(0,0,0,0.07)'
        ctx.fillRect(0, S - 24, S, 24)
        drawText(ctx, 'CALL BACK', S / 2, 60, {'font': 'Titan One', 'size': 30, 'fill': '#2A2A8A', 'rot': -0.05})
        drawText(ctx, 'STU RE: FORECAST', S / 2, 110, {'font': 'Titan One', 'size': 22, 'fill': '#2A2A8A', 'rot': -0.04, 'maxW': 220})
        drawText(ctx, 'x 1313', S / 2, 160, {'font': 'Titan One', 'size': 26, 'fill': '#E23B3B', 'rot': -0.03})
    at(3, 0, memo)

    # on-air schedule chart
    def sched():
        ctx.fillStyle = '#F6E7C8'
        ctx.fillRect(0, 0, S, S)
        ctx.fillStyle = '#2F5BD3'
        ctx.fillRect(0, 0, S, 34)
        drawText(ctx, 'ON-AIR SCHEDULE', S / 2, 18, {'font': 'Bungee', 'size': 18, 'fill': '#F4F1E8', 'maxW': 230})
        cols = [PAL.harvestGold, PAL.burntOrange, PAL.avocado, PAL.teal, PAL.plum, PAL.channelRed]
        for r in range(7):
            drawText(ctx, '%s:00' % js_str(((6 + r * 3) % 12) or 12), 30, 52 + r * 28, {'font': 'Titan One', 'size': 13, 'fill': '#5A3A22'})
            x = 58
            while x < S - 10:
                w = 30 + math.floor(rand() * 60)
                ctx.fillStyle = cols[int(math.floor(rand() * len(cols)))]
                rrect(ctx, x, 42 + r * 28, min(w, S - 10 - x), 20, 5)
                ctx.fill()
                x += w + 4
    at(0, 1, sched)

    # QUIET sign
    def quiet():
        ctx.fillStyle = '#E23B3B'
        rrect(ctx, 6, 6, S - 12, S - 12, 24)
        ctx.fill()
        ctx.strokeStyle = '#F4F1E8'
        ctx.lineWidth = 8
        rrect(ctx, 18, 18, S - 36, S - 36, 16)
        ctx.stroke()
        drawText(ctx, 'QUIET!', S / 2, 96, {'font': 'Bungee', 'size': 58, 'fill': '#F4F1E8'})
        drawText(ctx, "WE'RE ON", S / 2, 158, {'font': 'Titan One', 'size': 32, 'fill': '#FFE3A3'})
        drawText(ctx, 'THE AIR', S / 2, 196, {'font': 'Titan One', 'size': 32, 'fill': '#FFE3A3'})
    at(1, 1, quiet)

    # ENGINEERING sign
    def eng():
        ctx.fillStyle = '#F4C21E'
        rrect(ctx, 6, 6, S - 12, S - 12, 20)
        ctx.fill()
        ctx.fillStyle = '#1E1530'
        ctx.fillRect(6, 80, S - 12, 96)
        ctx.beginPath()
        ctx.moveTo(52, 20)
        ctx.lineTo(28, 66)
        ctx.lineTo(48, 66)
        ctx.lineTo(36, 104)
        ctx.lineTo(74, 50)
        ctx.lineTo(54, 50)
        ctx.closePath()
        ctx.fill()
        drawText(ctx, 'DANGER', 160, 44, {'font': 'Bungee', 'size': 34, 'fill': '#1E1530'})
        drawText(ctx, 'ENGINEERING', S / 2, 112, {'font': 'Bungee', 'size': 28, 'fill': '#F4C21E', 'maxW': 230})
        drawText(ctx, 'AUTHORIZED ONLY', S / 2, 150, {'font': 'Titan One', 'size': 20, 'fill': '#F4F1E8', 'maxW': 230})
        drawText(ctx, 'HIGH VOLTAGE', S / 2, 214, {'font': 'Bungee', 'size': 22, 'fill': '#E23B3B'})
    at(2, 1, eng)

    # tape box spines (8 per cell, vertical strips)
    def spines():
        cols = ['#2F5BD3', '#E23B3B', '#E8A92E', '#2A2230', '#8C9A3A', '#E3662B', '#6B3A6E', '#2E8C8C']
        for i in range(8):
            x = i * 32
            ctx.fillStyle = cols[i]
            ctx.fillRect(x, 0, 32, S)
            ctx.fillStyle = '#F6EFD8'
            ctx.fillRect(x + 5, 40, 22, 130)
            ctx.fillStyle = 'rgba(40,30,60,0.7)'
            for k in range(5):
                ctx.fillRect(x + 9, 52 + k * 22, 14 * (0.5 + rand() * 0.5), 4)
            ctx.fillStyle = 'rgba(255,255,255,0.18)'
            ctx.fillRect(x, 0, 3, S)
    at(3, 1, spines)

    # SMPTE bars chart poster
    def bars():
        ctx.fillStyle = '#F4F1E8'
        ctx.fillRect(0, 0, S, S)
        for i, c in enumerate(PAL.BARS):
            ctx.fillStyle = c
            ctx.fillRect(14 + i * 32.6, 40, 32.6, 130)
        ctx.fillStyle = '#1E1530'
        ctx.fillRect(14, 170, 228, 30)
        drawText(ctx, 'SMPTE TEST', S / 2, 22, {'font': 'Bungee', 'size': 20, 'fill': '#1E1530'})
        drawText(ctx, 'ALIGN DAILY  1 kHz  0 dB', S / 2, 226, {'font': 'Titan One', 'size': 14, 'fill': '#5A3A22', 'maxW': 230})
    at(0, 2, bars)

    # donut box lid print
    def donut():
        ctx.fillStyle = '#FFB6C8'
        ctx.fillRect(0, 0, S, S)
        for i in range(8):
            ctx.fillStyle = '#F4F1E8' if i % 2 else '#FF8FAE'
            ctx.fillRect(i * 32, 0, 16, S)
        ctx.fillStyle = '#F4F1E8'
        rrect(ctx, 30, 70, 196, 116, 20)
        ctx.fill()
        drawText(ctx, 'DOUGH-NUTS', S / 2, 110, {'font': 'Shrikhand', 'size': 32, 'fill': '#E23B3B', 'maxW': 180})
        drawText(ctx, 'FRESH DAILY', S / 2, 152, {'font': 'Titan One', 'size': 18, 'fill': '#5A3A22'})
    at(1, 2, donut)

    # round ACTION 13 NEWS logo
    def logo13():
        ctx.fillStyle = '#E8A92E'
        ctx.beginPath()
        ctx.arc(S / 2, S / 2, 124, 0, TAU)
        ctx.fill()
        ctx.fillStyle = '#E23B3B'
        ctx.beginPath()
        ctx.arc(S / 2, S / 2, 104, 0, TAU)
        ctx.fill()
        ctx.fillStyle = '#2F5BD3'
        ctx.beginPath()
        ctx.arc(S / 2, S / 2, 88, 0, TAU)
        ctx.fill()
        drawText(ctx, '13', S / 2, S / 2 + 6, {'font': 'Shrikhand', 'size': 96, 'fill': '#F4F1E8'})
        drawText(ctx, 'ACTION', S / 2, 58, {'font': 'Bungee', 'size': 20, 'fill': '#F4F1E8'})
        drawText(ctx, 'NEWS', S / 2, 206, {'font': 'Bungee', 'size': 22, 'fill': '#F4F1E8'})
    at(2, 2, logo13)

    # promo poster
    def promo():
        g = ctx.createLinearGradient(0, 0, 0, S)
        g.addColorStop(0, '#2F5BD3')
        g.addColorStop(1, '#6B3A6E')
        ctx.fillStyle = g
        ctx.fillRect(0, 0, S, S)
        for i in range(5):
            ctx.fillStyle = [PAL.harvestGold, PAL.burntOrange, PAL.channelRed, PAL.plum, PAL.teal][i]
            ctx.fillRect(0, 150 + i * 12, S, 8)
        drawText(ctx, "WE'RE ON", S / 2, 50, {'font': 'Shrikhand', 'size': 40, 'fill': '#F6E7C8'})
        drawText(ctx, 'YOUR SIDE', S / 2, 98, {'font': 'Shrikhand', 'size': 40, 'fill': '#FFC23A'})
        drawText(ctx, 'ACTION 13 NEWS  6 & 11', S / 2, 230, {'font': 'Titan One', 'size': 17, 'fill': '#F4F1E8', 'maxW': 230})
    at(3, 2, promo)

    # equipment panel with LEDs
    def panel():
        ctx.fillStyle = '#3A3440'
        ctx.fillRect(0, 0, S, S)
        for r in range(6):
            for c in range(8):
                ctx.fillStyle = ['#52E04A', '#FFB347', '#FF3B30', '#7FE7FF', '#3A3A44'][int(math.floor(rand() * 5))]
                ctx.beginPath()
                ctx.arc(24 + c * 30, 30 + r * 38, 7, 0, TAU)
                ctx.fill()
    at(0, 3, panel)

    # nameplates (top: WIRE SERVICE, bottom: LAFF-O-MATIC)
    def plate():
        ctx.fillStyle = '#2A2230'
        ctx.fillRect(0, 0, S, S)
        ctx.fillStyle = '#C8963C'
        rrect(ctx, 8, 12, S - 16, 104, 14)
        ctx.fill()
        ctx.fillStyle = '#2A2230'
        rrect(ctx, 16, 20, S - 32, 88, 10)
        ctx.fill()
        drawText(ctx, 'WZTV WIRE', S / 2, 64, {'font': 'Bungee', 'size': 34, 'fill': '#E8B84A', 'maxW': 210})
        ctx.fillStyle = '#F4F1E8'
        rrect(ctx, 8, 138, S - 16, 104, 14)
        ctx.fill()
        ctx.fillStyle = '#E3662B'
        rrect(ctx, 16, 146, S - 32, 88, 10)
        ctx.fill()
        drawText(ctx, 'LAFF-O-MATIC', S / 2, 190, {'font': 'Shrikhand', 'size': 30, 'fill': '#FFF3B0', 'maxW': 210})
    at(1, 3, plate)

    # assignment board (green chalkboard)
    def assign():
        ctx.fillStyle = '#2F4A3A'
        ctx.fillRect(0, 0, S, S)
        ctx.strokeStyle = 'rgba(255,255,255,0.08)'
        ctx.lineWidth = 16
        for i in range(6):
            ctx.beginPath()
            ctx.moveTo(rand() * S, rand() * S)
            ctx.lineTo(rand() * S, rand() * S)
            ctx.stroke()
        drawText(ctx, 'ASSIGNMENTS', S / 2, 28, {'font': 'Titan One', 'size': 26, 'fill': '#F4F1E8'})
        items = ['TELETHON - LIVE', 'CITY HALL - 3PM', 'WEATHER - STU', 'MAYOR PRESSER', 'SPORTS FINAL', 'LATE NIGHT - ??']
        for i, s in enumerate(items):
            drawText(ctx, s, 18, 70 + i * 30, {'font': 'Titan One', 'size': 17, 'fill': '#FFB6C8' if i == 5 else '#E8F0E0',
                                               'align': 'left', 'rot': (rand() - 0.5) * 0.04, 'maxW': 220})
    at(2, 3, assign)

    def cream():
        ctx.fillStyle = '#F6E7C8'
        ctx.fillRect(0, 0, S, S)
    at(3, 3, cream)


def paintDecals(ctx, W, H, rand):
    S = 256
    ctx.clearRect(0, 0, W, H)
    # coffee ring + splash
    ctx.save()
    ctx.translate(128, 128)
    ctx.fillStyle = 'rgba(92,52,24,0.55)'
    ctx.beginPath()
    ctx.ellipse(0, 0, 70, 58, 0.3, 0, TAU)
    ctx.fill()
    for i in range(9):
        a = rand() * TAU
        r = 70 + rand() * 30
        ctx.beginPath()
        ctx.arc(math.cos(a) * r, math.sin(a) * r, 5 + rand() * 9, 0, TAU)
        ctx.fill()
    ctx.strokeStyle = 'rgba(70,36,14,0.7)'
    ctx.lineWidth = 6
    ctx.beginPath()
    ctx.ellipse(-10, 8, 38, 38, 0, 0, TAU)
    ctx.stroke()
    ctx.restore()
    # scuffs
    ctx.save()
    ctx.translate(S, 0)
    ctx.strokeStyle = 'rgba(40,30,40,0.35)'
    ctx.lineCap = 'round'
    for i in range(26):
        ctx.lineWidth = 2 + rand() * 5
        ctx.beginPath()
        x = 30 + rand() * 196
        y = 30 + rand() * 196
        ctx.moveTo(x, y)
        ctx.lineTo(x + (rand() - 0.5) * 70, y + (rand() - 0.5) * 20)
        ctx.stroke()
    ctx.restore()
    # gaffer tape X (yellow)
    ctx.save()
    ctx.translate(128, S + 128)
    for a in [0.78, -0.78]:
        ctx.save()
        ctx.rotate(a)
        ctx.fillStyle = 'rgba(244,210,58,0.95)'
        ctx.fillRect(-100, -18, 200, 36)
        ctx.fillStyle = 'rgba(0,0,0,0.12)'
        i = -100
        while i < 100:
            ctx.fillRect(i, -18, 2, 36)
            i += 9
        ctx.restore()
    ctx.restore()
    # dust smudge
    ctx.save()
    ctx.translate(S + 128, S + 128)
    g = ctx.createRadialGradient(0, 0, 10, 0, 0, 120)
    g.addColorStop(0, 'rgba(60,40,50,0.35)')
    g.addColorStop(1, 'rgba(60,40,50,0)')
    ctx.fillStyle = g
    ctx.fillRect(-128, -128, 256, 256)
    ctx.restore()


def atlas(game):
    mp = K.tex.canvas('nm_atlas_v1', 1024, 1024, paintAtlas, {'repeat': False, 'fonts': True})
    dmap = K.tex.canvas('nm_decals_v1', 512, 512, paintDecals, {'repeat': False})
    mat = K.mat(game, 'paint', '#ffffff', {'map': mp, 'rim': 0.12})
    decal = game.mats.toon('#ffffff', {'map': dmap, 'transparent': True, 'depthWrite': False, 'rough': 0.8, 'rim': 0, 'name': 'nm_decal'})
    decal.polygonOffset = True          # (no polygon offset in Godot: the decals sit 4 mm above the floor)
    decal.polygonOffsetFactor = -2
    decal.polygonOffsetUnits = -2

    def cell(name, sub=(0, 0, 1, 1)):
        c, r = CELLS[name]
        u0, u1 = (c + sub[0]) / 4, (c + sub[2]) / 4
        v1, v0 = 1 - (r + sub[1]) / 4, 1 - (r + sub[3]) / 4
        return [u0, v0, u1, v1]

    def dcell(name):
        c, r = DECALS[name]
        return [c / 2, 1 - (r + 1) / 2, (c + 1) / 2, 1 - r / 2]
    return _Obj(mat=mat, decal=decal, cell=cell, dcell=dcell, map=mp)


# Plane w x h facing +z with its UVs remapped into rect [u0, v0, u1, v1].
def quad(w, h, rect=(0, 0, 1, 1), seg=1):
    g = THREE.PlaneGeometry(w, h, seg, seg)
    uv = g.attributes.uv
    for i in range(uv.count):
        uv.setXY(i, rect[0] + uv.getX(i) * (rect[2] - rect[0]), rect[1] + uv.getY(i) * (rect[3] - rect[1]))
    return g


# Flat ribbon (paper tape, cables laid flat) along a Catmull-Rom curve through `points`; normal ~ up.
def ribbon(points, width, opts=None):
    opts = opts or {}
    seg = opts.get('seg', 32)
    up = opts.get('up', [0, 1, 0])
    rect = opts.get('rect', [0, 0, 1, 1])
    curve = THREE.CatmullRomCurve3([v3(p) for p in points])
    pos, uv, idx = [], [], []
    U = v3(up)
    t, s, p = THREE.Vector3(), THREE.Vector3(), THREE.Vector3()
    for i in range(seg + 1):
        k = i / seg
        curve.getPointAt(k, p)
        curve.getTangentAt(k, t)
        s.crossVectors(t, U).normalize().multiplyScalar(width / 2)
        pos.extend([p.x - s.x, p.y - s.y, p.z - s.z, p.x + s.x, p.y + s.y, p.z + s.z])
        v = rect[1] + k * (rect[3] - rect[1])
        uv.extend([rect[0], v, rect[2], v])
        if i < seg:
            a = i * 2
            idx.extend([a, a + 1, a + 2, a + 1, a + 3, a + 2])
    g = THREE.BufferGeometry()
    g.setAttribute('position', THREE.Float32BufferAttribute(pos, 3))
    g.setAttribute('uv', THREE.Float32BufferAttribute(uv, 2))
    g.setIndex(idx)
    g.computeVertexNormals()
    return g


# Materials the rooms mutate at runtime (never the shared caches): a lamp glow that can dim. Exported as the glow
# spec (colour x intensity, the same MeshBasicMaterial as the JS); the room script clones it per lamp and drives
# its level (userData.base / level).
def dimmableGlow(game, color, intensity=2.2):
    m = game.mats.glow(color, intensity)
    return m


# Additive plane material (washes, slats), level-controlled (the room script clones it and sets the level).
def additive(mp, color, level=1):
    m = THREE.MeshBasicMaterial({'map': mp, 'color': color, 'transparent': True, 'depthWrite': False,
                                 'blending': THREE.AdditiveBlending, 'fog': False, 'toneMapped': True, 'side': THREE.DoubleSide})
    m.userData.base = color
    m.userData.level = level
    m.polygonOffset = True
    m.polygonOffsetFactor = -3
    m.polygonOffsetUnits = -3
    return m


# Slat stripes (moonlight through boards / blinds) and soft vertical wash gradients.
def slatTex(n=6):
    def draw(ctx, w, h, rand):
        ctx.clearRect(0, 0, w, h)
        for i in range(n):
            y0 = (i + 0.18) * (h / n)
            hh = (h / n) * 0.55
            g = ctx.createLinearGradient(0, y0, 0, y0 + hh)
            g.addColorStop(0, 'rgba(255,255,255,0)')
            g.addColorStop(0.25, 'rgba(255,255,255,1)')
            g.addColorStop(0.75, 'rgba(255,255,255,1)')
            g.addColorStop(1, 'rgba(255,255,255,0)')
            ctx.fillStyle = g
            ctx.fillRect(0, y0, w, hh)
        # soft side falloff
        s = ctx.createLinearGradient(0, 0, w, 0)
        s.addColorStop(0, 'rgba(0,0,0,1)')
        s.addColorStop(0.2, 'rgba(0,0,0,0)')
        s.addColorStop(0.8, 'rgba(0,0,0,0)')
        s.addColorStop(1, 'rgba(0,0,0,1)')
        ctx.globalCompositeOperation = 'destination-out'
        ctx.fillStyle = s
        ctx.fillRect(0, 0, w, h)
        e = ctx.createLinearGradient(0, 0, 0, h)
        e.addColorStop(0, 'rgba(0,0,0,0)')
        e.addColorStop(0.7, 'rgba(0,0,0,0.2)')
        e.addColorStop(1, 'rgba(0,0,0,1)')
        ctx.fillStyle = e
        ctx.fillRect(0, 0, w, h)
        ctx.globalCompositeOperation = 'source-over'
    return K.tex.canvas('nm_slats_%s' % js_str(n), 64, 256, draw, {'repeat': False})


def washTex():
    def draw(ctx, w, h, rand):
        g = ctx.createRadialGradient(w / 2, h * 0.75, 4, w / 2, h * 0.6, w * 0.6)
        g.addColorStop(0, 'rgba(255,255,255,1)')
        g.addColorStop(0.5, 'rgba(255,255,255,0.45)')
        g.addColorStop(1, 'rgba(255,255,255,0)')
        ctx.fillStyle = g
        ctx.fillRect(0, 0, w, h)
    return K.tex.canvas('nm_wash', 128, 128, draw, {'repeat': False})


# ================================================================================== room-only props (nm_*)
CAT = 'rooms_nm'


def sph(r, ws=14, hs=10):
    return THREE.SphereGeometry(r, ws, hs)


def keyGeo():
    return K.lathe([[0, 0], [0.0128, 0], [0.012, 0.015], [0, 0.017]], {'seg': 7})


# ------------------------------------------------------------------------------------------------ teletype
# Wire-service teletype on its pedestal (toy_teletype). Front (keyboard) -z. parts: head (print head, slides x),
# paper (printout, grows scale.y from the slot), tape (punched tape ribbon), bulb (work-lamp glow mesh),
# keys (a few keys that bob). anchors.lamp = bulb position (local).
def _nm_teletype(game, opts=None):
    g = K.prop('nm_teletype')
    mt, A = stdMats(game), atlas(game)
    cream, putty, dark = '#E9DFC4', '#CFC3A2', '#3A3440'
    # pedestal + kick
    g.add(K.m(tc(K.box(0.6, 0.5, 0.48, 'md'), putty), mt.paint, {'pos': [0, 0.33, 0.02]}))
    g.add(K.m(tc(K.box(0.54, 0.08, 0.42, 'sm'), '#5A4A46'), mt.paint, {'pos': [0, 0.04, 0.02]}))
    g.add(K.m(tc(K.box(0.44, 0.22, 0.02, 'sm'), '#8A7E66'), mt.paint, {'pos': [0, 0.34, -0.225]}))
    # paper feed box in the pedestal opening (fan-fold stack)
    for i in range(6):
        g.add(K.m(tc(K.box(0.36, 0.02, 0.3, 'xs'), '#F4EBC8' if i % 2 else '#E9DFB8'), mt.paint,
                  {'pos': [0, 0.25 + i * 0.021, -0.07], 'rot': [0, (i % 3 - 1) * 0.02, 0]}))
    # chassis + stripe
    g.add(K.m(tc(K.box(0.68, 0.16, 0.56, 'lg'), cream), mt.plastic, {'pos': [0, 0.66, 0]}))
    g.add(K.m(tc(K.box(0.685, 0.03, 0.565, 'sm'), PAL.burntOrange), mt.plastic, {'pos': [0, 0.6, 0]}))
    # sloped keyboard deck with keys
    deck = THREE.Group()
    deck.position.set(0, 0.75, -0.19)
    deck.rotation.x = 0.22
    g.add(deck)
    deck.add(K.m(tc(K.box(0.56, 0.04, 0.2, 'sm'), dark), mt.plastic))
    kg = keyGeo()
    bobKeys = THREE.Group()
    bobKeys.userData.noMerge = True
    for r in range(3):
        for i in range(9 - r):
            x, z = (i - (8 - r) / 2) * 0.05, -0.06 + r * 0.05
            col = PAL.channelRed if (i + r) % 6 == 2 else '#F4F1E8'
            key = K.m(tc(kg, col), mt.plastic, {'pos': [x, 0.02, z]})
            if r == 1 and (i == 2 or i == 5):
                bobKeys.add(key)
            else:
                deck.add(key)
    deck.add(bobKeys)
    deck.add(K.m(tc(K.box(0.26, 0.02, 0.035, 'xs'), '#F4F1E8'), mt.plastic, {'pos': [0, 0.025, -0.085]}))
    # hood with a smoked window over the platen
    g.add(K.m(tc(K.box(0.62, 0.2, 0.3, 0.08), cream), mt.plastic, {'pos': [0, 0.83, 0.1]}))
    g.add(K.m(K.box(0.5, 0.13, 0.012, 'xs'), game.mats.glass('#5A4A3A', {'opacity': 0.35}), {'pos': [0, 0.87, -0.052], 'rot': [-0.25, 0, 0]}))
    g.add(K.m(tc(K.cyl(0.035, 0.035, 0.52, {'seg': 14}), '#2A2230'), mt.rubber, {'pos': [-0.26, 0.855, 0.02], 'rot': [0, 0, -HP]}))
    for s in [-1, 1]:
        g.add(K.m(K.cyl(0.03, 0.034, 0.03, {'seg': 12}), mt.chrome, {'pos': [s * 0.33, 0.855, 0.02], 'rot': [0, 0, -s * HP]}))
    # print head (part)
    head = THREE.Group()
    head.position.set(0, 0.86, -0.02)
    head.userData.noMerge = True
    head.add(K.m(K.box(0.07, 0.05, 0.05, 'sm'), mt.chrome))
    head.add(K.m(tc(K.box(0.03, 0.02, 0.03, 'xs'), PAL.channelRed), mt.plastic, {'pos': [0, 0.035, 0]}))
    g.add(head)
    # paper roll behind the hood
    g.add(K.m(tc(K.cyl(0.07, 0.07, 0.5, {'seg': 16}), '#F4EEDC'), mt.paint, {'pos': [-0.25, 0.9, 0.2], 'rot': [0, 0, -HP]}))
    # printout coming out of the slot and curling back (part 'paper', pivot at the slot)
    paper = THREE.Group()
    paper.position.set(0, 0.935, 0.06)
    paper.userData.noMerge = True
    pg = quad(0.46, 0.46, A.cell('wire'), 8)
    pp = pg.attributes.position
    for i in range(pp.count):
        y = pp.getY(i) + 0.23              # 0..0.46 up the sheet
        k = y / 0.46
        pp.setXYZ(i, -pp.getX(i), math.sin(k * 1.9) * 0.3, 0.02 + (1 - math.cos(k * 1.9)) * 0.2)  # mirrored: text faces -z
    pg.computeVertexNormals()
    paper.add(K.m(pg, K.mat(game, 'paint', '#ffffff', {'map': A.map, 'side': THREE.DoubleSide, 'rim': 0.1}), {'cast': False}))
    g.add(paper)
    # punched paper tape (part) spilling from the side punch to the floor
    tape = THREE.Group()
    tape.position.set(-0.36, 0.7, -0.08)
    tape.userData.noMerge = True
    tpts = [[0, 0, 0], [-0.08, -0.05, -0.04], [-0.12, -0.25, -0.1], [-0.05, -0.45, -0.18], [-0.15, -0.66, -0.24], [-0.3, -0.695, -0.2], [-0.32, -0.695, -0.05]]
    tape.add(K.m(ribbon(tpts, 0.028, {'seg': 28, 'up': [1, 0, 0]}), K.mat(game, 'paint', '#F4D23A', {'side': THREE.DoubleSide}), {'cast': False}))
    g.add(tape)
    g.add(K.m(tc(K.box(0.08, 0.12, 0.14, 'sm'), '#8A7E66'), mt.plastic, {'pos': [-0.36, 0.68, -0.06]}))
    # nameplate on the chassis front
    g.add(K.m(quad(0.2, 0.07, A.cell('plate', [0, 0, 1, 0.5])), A.mat, {'pos': [0.18, 0.66, -0.282], 'rot': [0, math.pi, 0]}))
    # gooseneck work lamp clamped on the back right
    g.add(K.m(tc(K.cyl(0.05, 0.055, 0.03, {'seg': 14}), '#2A2230'), mt.plastic, {'pos': [0.26, 0.74, 0.2]}))
    neck = [[0.26, 0.76, 0.2], [0.27, 0.95, 0.2], [0.24, 1.14, 0.12], [0.16, 1.22, 0.0], [0.1, 1.2, -0.08]]
    g.add(K.m(K.tube(neck, 0.012, {'seg': 20, 'radial': 6}), mt.chrome))
    shade = THREE.Group()
    shade.position.set(0.09, 1.19, -0.1)
    shade.rotation.x = 0.9
    shade.add(K.m(tc(K.lathe([[0.03, 0.06], [0.05, 0.04], [0.085, -0.02], [0.09, -0.05], [0.08, -0.05], [0.07, -0.02]], {'seg': 16, 'round': 0.004}), PAL.burntOrange), mt.lacquer))
    bulb = K.m(sph(0.035, 12, 8), dimmableGlow(game, '#FFD9A0', 2.4), {'pos': [0, -0.02, 0], 'cast': False})
    bulb.userData.noMerge = True
    bulb.userData.noOcclude = True
    shade.add(bulb)
    g.add(shade)
    u = g.userData
    u.parts = {'head': head, 'paper': paper, 'tape': tape, 'bulb': bulb, 'keys': bobKeys}
    u.anchors = {'lamp': [0.09, 1.13, -0.16]}
    u.colliders = [{'min': [-0.36, 0, -0.32], 'max': [0.36, 0.96, 0.3]}]
    u.interact = {'point': [0, 0.9, -0.5], 'radius': 1.4}
    return K.finish(game, g, {'ao': {'res': 40}})


registerProp('nm_teletype', _nm_teletype, {'category': CAT, 'tags': ['newsroom', 'toy'], 'size': [0.72, 1.25, 0.6],
                                           'desc': 'wire-service teletype on a pedestal with printout, punched tape and a gooseneck work lamp'})


# ------------------------------------------------------------------------------------- toy typewriter
# parts: carriage (slides along x, returns with a ding), keys (bobbing group), sheet (paper in the platen).
def _nm_typewriter(game, opts=None):
    opts = opts or {}
    g = K.prop('nm_typewriter')
    mt, A = stdMats(game), atlas(game)
    color = opts['color'] if opts.get('color') is not None else PAL.harvestGold
    dark = '#2E2630'
    g.add(K.m(tc(K.box(0.46, 0.08, 0.38, 0.035), color), mt.plastic, {'pos': [0, 0.05, 0]}))
    g.add(K.m(K.weldNormals(K.taper(tc(K.box(0.44, 0.09, 0.2, 0.04), color), {'axis': 'y', 'k': 0.82})), mt.plastic, {'pos': [0, 0.125, 0.07]}))
    g.add(K.m(tc(K.box(0.44, 0.012, 0.36, 0.005), dark), mt.plastic, {'pos': [0, 0.006, 0]}))
    g.add(K.m(tc(K.box(0.4, 0.03, 0.15, 0.012), dark), mt.plastic, {'pos': [0, 0.085, -0.105], 'rot': [0.2, 0, 0]}))
    kg = keyGeo()
    bob = THREE.Group()
    bob.userData.noMerge = True
    for r, (n, off) in enumerate([[10, 0], [9, 0.01], [8, 0.02]]):
        for i in range(n):
            x, z, y = (i - (n - 1) / 2) * 0.034 + off * 0.2, -0.155 + r * 0.035, 0.09 + r * 0.008
            k = K.m(tc(kg, PAL.channelRed if (i + r) % 7 == 3 else '#F4F1E8'), mt.plastic, {'pos': [x, y, z], 'rot': [0.2, 0, 0]})
            if r == 1 and i % 3 == 1:
                bob.add(k)
            else:
                g.add(k)
    g.add(bob)
    g.add(K.m(tc(K.box(0.2, 0.014, 0.024, 0.006), '#F4F1E8'), mt.plastic, {'pos': [0, 0.088, -0.19], 'rot': [0.2, 0, 0]}))
    # carriage (part): platen, knobs, sheet, return lever, bell
    car = THREE.Group()
    car.position.set(0, 0.185, 0.1)
    car.userData.noMerge = True
    car.add(K.m(tc(K.cyl(0.028, 0.028, 0.42, {'seg': 14}), dark), mt.plastic, {'pos': [-0.21, 0, 0], 'rot': [0, 0, -HP]}))
    for s in [-1, 1]:
        car.add(K.m(tc(K.lathe([[0, 0], [0.024, 0], [0.028, 0.012], [0.024, 0.028], [0, 0.03]], {'seg': 12, 'round': 0.004, 'steps': 1}), dark),
                    mt.plastic, {'pos': [s * 0.21, 0, 0], 'rot': [0, 0, -s * HP]}))
    sheet = K.m(quad(0.24, 0.27, A.cell('page')), K.mat(game, 'paint', '#ffffff', {'map': A.map, 'side': THREE.DoubleSide, 'rim': 0.1}),
                {'pos': [0, 0.13, 0.015], 'rot': [-0.18, 0, 0.02], 'cast': False})
    car.add(sheet)
    car.add(K.m(K.tube([[-0.23, 0.015, -0.04], [-0.27, 0.045, -0.07], [-0.29, 0.065, -0.12]], 0.006, {'seg': 8, 'radial': 5}), mt.chrome))
    car.add(K.m(tc(K.box(0.44, 0.02, 0.05, 0.009), THREE.Color(color).multiplyScalar(0.7).getStyle()), mt.plastic, {'pos': [0, -0.013, -0.12]}))
    g.add(car)
    g.add(K.m(K.lathe([[0, 0], [0.02, 0], [0.018, 0.012], [0.01, 0.02], [0, 0.021]], {'seg': 12, 'round': 0.004}), mt.chrome, {'pos': [0.19, 0.1, 0.16]}))
    g.add(K.m(quad(0.12, 0.028, A.cell('plate', [0, 0, 1, 0.5])), A.mat, {'pos': [0, 0.15, -0.034], 'rot': [0.55, math.pi, 0]}))
    u = g.userData
    u.parts = {'carriage': car, 'keys': bob, 'sheet': sheet}
    u.colliders = []
    return K.finish(game, g, {'ao': {'height': 0.02}})


registerProp('nm_typewriter', _nm_typewriter, {'category': CAT, 'tags': ['tabletop', 'newsroom', 'toy'], 'size': [0.6, 0.44, 0.4],
                                               'desc': 'toy typewriter with a sliding carriage (parts.carriage)'})


# ---------------------------------------------------------------------------------- bare reporter desk
# Same sage tanker desk as the library's desk_reporter (same materials/tints), minus the top dressing, so the
# toy typewriter can sit on it. Front (drawers, knee hole) -z.
def _nm_desk_bare(game, opts=None):
    opts = opts or {}
    g = K.prop('nm_desk_bare')
    mt = stdMats(game)
    steel = opts['color'] if opts.get('color') is not None else '#8FA38A'
    W, D, H = 1.5, 0.76, 0.76
    lam = K.mat(game, 'lacquer', '#ffffff', {'map': K.tex.wood('#A8743F', {'dark': 0.3})})
    g.add(K.m(K.box(W, 0.034, D, 0.012, {'uv': 1.2, 'swap': True}), lam, {'pos': [0, H - 0.017, 0]}))
    g.add(K.m(K.box(W + 0.012, 0.022, D + 0.012, 0.008), mt.chrome, {'pos': [0, H - 0.04, 0]}))
    pw = 0.44
    px = W / 2 - pw / 2 - 0.01
    g.add(K.m(tc(K.box(pw, H - 0.1, D - 0.04, 0.02), steel), mt.paint, {'pos': [px, (H - 0.1) / 2 + 0.05, 0]}))
    g.add(K.m(tc(K.box(0.05, H - 0.1, D - 0.04, 0.02), steel), mt.paint, {'pos': [-W / 2 + 0.035, (H - 0.1) / 2 + 0.05, 0]}))
    g.add(K.m(tc(K.box(W - pw - 0.08, 0.42, 0.025, 0.01), steel), mt.paint, {'pos': [-pw / 2 + 0.01, H - 0.3, D / 2 - 0.05]}))
    dark = THREE.Color(steel).multiplyScalar(0.55).getStyle()
    g.add(K.m(tc(K.box(pw - 0.04, 0.05, D - 0.1, 0.01), dark), mt.paint, {'pos': [px, 0.025, 0]}))
    g.add(K.m(tc(K.box(0.04, 0.05, D - 0.1, 0.01), dark), mt.paint, {'pos': [-W / 2 + 0.035, 0.025, 0]}))
    y = H - 0.07
    for h in [0.16, 0.16, 0.28]:
        y -= h / 2 + 0.006
        g.add(K.m(tc(K.box(pw - 0.03, h - 0.012, 0.03, 0.012), steel), mt.paint, {'pos': [px, y, -D / 2 + 0.01]}))
        g.add(K.m(K.tube([[-0.07, 0, 0], [-0.065, 0, -0.02], [0.065, 0, -0.02], [0.07, 0, 0]], 0.007, {'seg': 8, 'radial': 5}), mt.chrome,
                  {'pos': [px, y + h * 0.18, -D / 2 - 0.004]}))
        y -= h / 2 + 0.006
    g.add(K.m(tc(K.box(W - pw - 0.14, 0.07, 0.03, 0.012), steel), mt.paint, {'pos': [-pw / 2 - 0.02, H - 0.09, -D / 2 + 0.01]}))
    g.userData.colliders = [{'min': [-W / 2, 0, -D / 2], 'max': [W / 2, H + 0.05, D / 2]}]
    return K.finish(game, g)


registerProp('nm_desk_bare', _nm_desk_bare, {'category': CAT, 'tags': ['desk', 'newsroom'], 'size': [1.5, 0.78, 0.76],
                                             'desc': 'bare sage tanker desk (desk_reporter without dressing)'})


# ------------------------------------------------------------------------------------------ floor globe
# Teak tripod floor globe (toy_globe). parts: globe (spins about its local y), tilt (23.5° axis group).
def globeTex():
    def draw(ctx, w, h, rand):
        ctx.fillStyle = '#3F9AB8'
        ctx.fillRect(0, 0, w, h)
        for i in range(40):
            ctx.fillStyle = 'rgba(255,255,255,%s)' % js_str(0.04 + rand() * 0.05)
            ctx.fillRect(0, rand() * h, w, 2)

        def blob(cx, cy, rx, ry, col, n=9):
            ctx.fillStyle = col
            for i in range(n):
                ctx.beginPath()
                ctx.ellipse(cx + (rand() - 0.5) * rx, cy + (rand() - 0.5) * ry, rx * (0.3 + rand() * 0.4), ry * (0.3 + rand() * 0.4), rand() * 3, 0, TAU)
                ctx.fill()
        land = [[110, 80, 90, 60], [150, 170, 50, 70], [260, 80, 60, 50], [280, 150, 50, 70], [380, 90, 110, 60], [420, 190, 50, 30], [70, 30, 60, 20]]
        for x, y, rx, ry in land:
            blob(x, y, rx, ry, '#E8D9A0')
        for x, y, rx, ry in land:
            blob(x, y, rx * 0.7, ry * 0.6, '#9CC46A', 5)
        ctx.fillStyle = '#F4F1E8'
        ctx.fillRect(0, 0, w, 12)
        ctx.fillRect(0, h - 12, w, 12)
        ctx.strokeStyle = 'rgba(30,40,70,0.25)'
        ctx.lineWidth = 1.5
        for i in range(1, 6):
            ctx.beginPath()
            ctx.moveTo(0, (i * h) / 6)
            ctx.lineTo(w, (i * h) / 6)
            ctx.stroke()
        for i in range(12):
            ctx.beginPath()
            ctx.moveTo((i * w) / 12, 0)
            ctx.lineTo((i * w) / 12, h)
            ctx.stroke()
        ctx.fillStyle = '#E23B3B'
        ctx.beginPath()
        ctx.arc(130, 92, 7, 0, TAU)
        ctx.fill()
    return K.tex.canvas('nm_globe_map', 512, 256, draw)


def _nm_globe(game, opts=None):
    g = K.prop('nm_globe')
    mt = stdMats(game)
    hubY, R, cy = 0.42, 0.22, 0.74
    # tripod legs
    for i in range(3):
        a = (i / 3) * TAU + 0.3
        top = THREE.Vector3(math.cos(a) * 0.05, hubY, math.sin(a) * 0.05)
        foot = THREE.Vector3(math.cos(a) * 0.27, 0.0, math.sin(a) * 0.27)
        ln = top.distanceTo(foot)
        leg = K.m(K.uvScale(K.cyl(0.02, 0.014, ln, {'seg': 10}).clone(), 1, 2), mt.teak)
        leg.position.copy(foot)
        leg.quaternion.setFromUnitVectors(THREE.Vector3(0, 1, 0), top.clone().sub(foot).normalize())
        g.add(leg)
        g.add(K.m(K.cyl(0.018, 0.02, 0.025, {'seg': 10}), mt.brass, {'pos': [foot.x, 0, foot.z]}))
    ring = []
    for i in range(13):
        a = (i / 12) * TAU
        ring.append([math.cos(a) * 0.16, 0.16, math.sin(a) * 0.16])
    g.add(K.m(K.tube(ring, 0.008, {'seg': 24, 'radial': 5, 'closed': True}), mt.brass))
    g.add(K.m(K.lathe([[0, 0], [0.06, 0], [0.065, 0.03], [0.03, 0.06], [0.025, 0.2], [0.04, 0.22], [0, 0.23]], {'seg': 14, 'round': 0.006}), mt.teak, {'pos': [0, hubY - 0.05, 0]}))
    # meridian + globe (parts)
    tilt = THREE.Group()
    tilt.position.set(0, cy, 0)
    tilt.rotation.z = 0.41
    tilt.userData.noMerge = True
    tilt.add(K.m(THREE.TorusGeometry(R + 0.03, 0.012, 6, 40, math.pi * 1.3), mt.brass, {'rot': [0, 0, -math.pi * 0.65 + HP]}))
    globe = K.m(THREE.SphereGeometry(R, 32, 20), K.mat(game, 'lacquer', '#ffffff', {'map': globeTex()}), {'name': 'globe'})
    globe.userData.noMerge = True
    tilt.add(globe)
    for s in [-1, 1]:
        tilt.add(K.m(K.cyl(0.012, 0.012, 0.04, {'seg': 8}), mt.brass, {'pos': [0, s * (R + 0.02) - (0.04 if s < 0 else 0), 0]}))
    g.add(tilt)
    # stem from the hub to the meridian
    g.add(K.m(K.cyl(0.012, 0.012, cy - R - hubY + 0.1, {'seg': 8}), mt.brass, {'pos': [0, hubY + 0.15, 0]}))
    u = g.userData
    u.parts = {'globe': globe, 'tilt': tilt}
    u.colliders = [{'min': [-0.28, 0, -0.28], 'max': [0.28, 1.0, 0.28]}]
    return K.finish(game, g, {'ao': {'res': 36}})


registerProp('nm_globe', _nm_globe, {'category': CAT, 'tags': ['newsroom', 'toy'], 'size': [0.56, 1.0, 0.56],
                                     'desc': 'teak tripod floor globe (parts.globe spins)'})


# ------------------------------------------------------------------------------------------- coffee cart
def _nm_coffee_cart(game, opts=None):
    g = K.prop('nm_coffee_cart')
    mt, A = stdMats(game), atlas(game)
    W, D = 0.82, 0.46
    for y, c in [[0.22, PAL.avocado], [0.78, PAL.mustard]]:
        g.add(K.m(tc(K.box(W, 0.035, D, 0.014), c), mt.lacquer, {'pos': [0, y, 0]}))
        g.add(K.m(K.tube(K.roundRectPath(W - 0.01, D - 0.01, 0.03, 0.025, 2), 0.008, {'seg': 20, 'radial': 4, 'closed': True}), mt.chrome, {'pos': [0, y, 0]}))
    for x, z in [[-1, -1], [1, -1], [-1, 1], [1, 1]]:
        g.add(K.m(K.cyl(0.013, 0.013, 0.78, {'seg': 8}), mt.chrome, {'pos': [x * (W / 2 - 0.03), 0.07, z * (D / 2 - 0.03)]}))
        g.add(K.m(tc(sph(0.035, 10, 8), '#2A2230'), mt.rubber, {'pos': [x * (W / 2 - 0.03), 0.035, z * (D / 2 - 0.03)]}))
    g.add(K.m(K.tube([[W / 2 - 0.03, 0.8, -D / 2 + 0.05], [W / 2 + 0.06, 0.86, -D / 2 + 0.05], [W / 2 + 0.06, 0.86, D / 2 - 0.05], [W / 2 - 0.03, 0.8, D / 2 - 0.05]],
                     0.012, {'seg': 12, 'radial': 6}), mt.chrome))
    # percolator
    top = 0.8
    g.add(K.m(K.lathe([[0, 0], [0.09, 0], [0.1, 0.02], [0.085, 0.05], [0.075, 0.26], [0.08, 0.28], [0.05, 0.3], [0.03, 0.34], [0, 0.35]], {'seg': 20, 'round': 0.008}),
              mt.chrome, {'pos': [-0.24, top, -0.02]}))
    g.add(K.m(K.lathe([[0, 0], [0.022, 0], [0.018, 0.03], [0, 0.04]], {'seg': 10}), game.mats.glass('#8A5A30', {'opacity': 0.5}), {'pos': [-0.24, top + 0.34, -0.02]}))
    g.add(K.m(tc(K.tube([[-0.16, top + 0.24, -0.02], [-0.12, top + 0.22, -0.02], [-0.12, top + 0.08, -0.02], [-0.16, top + 0.06, -0.02]], 0.014, {'seg': 10, 'radial': 6}), '#2A2230'), mt.plastic))
    g.add(K.m(K.tube([[-0.33, top + 0.2, -0.02], [-0.37, top + 0.25, -0.02]], 0.01, {'seg': 3, 'radial': 6}), mt.chrome))
    # cup stack + mugs
    for i in range(6):
        g.add(K.m(tc(K.lathe([[0, 0], [0.028, 0], [0.036, 0.06], [0.034, 0.06], [0.026, 0.004], [0, 0.004]], {'seg': 12}), '#F4F1E8'), mt.plastic, {'pos': [0.02, top + i * 0.018, -0.08]}))
    for x, z, c in [[0.1, 0.1, PAL.channelRed], [0.02, 0.12, PAL.wztvBlue]]:
        g.add(K.m(tc(K.lathe([[0, 0], [0.034, 0], [0.036, 0.085], [0.032, 0.085], [0.03, 0.01], [0, 0.01]], {'seg': 14}), c),
                  mt.get('ceramic') or mt.plastic, {'pos': [x, top, z]}))
        g.add(K.m(tc(THREE.TorusGeometry(0.022, 0.006, 6, 12, math.pi * 1.2), c), mt.plastic, {'pos': [x + 0.036, top + 0.045, z], 'rot': [0, 0, -math.pi * 0.6]}))
    # open donut box with donuts
    bx, bz = 0.2, -0.04
    g.add(K.m(tc(K.box(0.3, 0.05, 0.26, 'xs'), '#F4F1E8'), mt.paint, {'pos': [bx, top + 0.025, bz]}))
    lid = K.m(quad(0.3, 0.26, A.cell('donut')), A.mat, {'pos': [bx, top + 0.16, bz + 0.2], 'rot': [-0.35, math.pi, 0]})
    g.add(lid)
    glaze = [PAL.neonPink, '#6B3A22', '#F6E7C8', PAL.neonPink]
    for i, (x, z) in enumerate([[-0.07, -0.05], [0.07, -0.05], [-0.07, 0.07], [0.06, 0.06]]):
        g.add(K.m(tc(THREE.TorusGeometry(0.042, 0.022, 8, 16), '#D9A060'), mt.plastic, {'pos': [bx + x, top + 0.07, bz + z], 'rot': [HP, 0, 0]}))
        g.add(K.m(tc(THREE.TorusGeometry(0.042, 0.02, 6, 16, TAU), glaze[i]), mt.plastic, {'pos': [bx + x, top + 0.077, bz + z], 'rot': [HP, 0, 0], 'scale': [1.02, 1.02, 0.6]}))
    # bottom shelf: coffee cans + sugar
    for x, z in [[-0.22, 0], [-0.08, 0.04]]:
        g.add(K.m(tc(K.cyl(0.07, 0.07, 0.16, {'seg': 14}), PAL.channelRed), mt.lacquer, {'pos': [x, 0.24, z]}))
        g.add(K.m(tc(K.cyl(0.072, 0.072, 0.02, {'seg': 14}), '#C8963C'), mt.metal, {'pos': [x, 0.39, z]}))
    g.add(K.m(K.lathe([[0, 0], [0.05, 0], [0.05, 0.12], [0.02, 0.15], [0, 0.16]], {'seg': 12}), game.mats.glass('#F4F1E8', {'opacity': 0.5}), {'pos': [0.2, 0.24, 0.02]}))
    g.userData.colliders = [{'min': [-W / 2 - 0.02, 0, -D / 2 - 0.02], 'max': [W / 2 + 0.08, 1.15, D / 2 + 0.02]}]
    return K.finish(game, g, {'ao': {'res': 40}})


registerProp('nm_coffee_cart', _nm_coffee_cart, {'category': CAT, 'tags': ['newsroom', 'cart'], 'size': [0.9, 1.15, 0.5],
                                                 'desc': 'rolling coffee cart: chrome percolator, cups, an open box of donuts, coffee cans'})


# ------------------------------------------------------------------------------------ gooseneck desk lamp
# parts.bulb (dimmable glow mesh, swap level on power). Front -z.
def _nm_desk_lamp(game, opts=None):
    opts = opts or {}
    g = K.prop('nm_desk_lamp')
    mt = stdMats(game)
    c = opts['color'] if opts.get('color') is not None else PAL.avocado
    g.add(K.m(tc(K.lathe([[0, 0], [0.08, 0], [0.085, 0.015], [0.06, 0.03], [0, 0.035]], {'seg': 16, 'round': 0.005}), c), mt.lacquer))
    g.add(K.m(K.tube([[0, 0.03, 0.02], [0, 0.2, 0.04], [0, 0.34, -0.02], [0, 0.38, -0.12]], 0.01, {'seg': 16, 'radial': 6}), mt.chrome))
    shade = THREE.Group()
    shade.position.set(0, 0.38, -0.15)
    shade.rotation.x = 0.5
    shade.add(K.m(tc(K.lathe([[0.025, 0.05], [0.045, 0.03], [0.075, -0.02], [0.08, -0.045], [0.07, -0.045], [0.062, -0.02]], {'seg': 16, 'round': 0.004}), c), mt.lacquer))
    bulb = K.m(sph(0.028, 10, 8), dimmableGlow(game, '#FFE0A8', 2.2), {'pos': [0, -0.02, 0], 'cast': False})
    bulb.userData.noMerge = True
    bulb.userData.noOcclude = True
    shade.add(bulb)
    g.add(shade)
    g.userData.parts = {'bulb': bulb}
    g.userData.colliders = []
    return K.finish(game, g, {'ao': {'height': 0.02}})


registerProp('nm_desk_lamp', _nm_desk_lamp, {'category': CAT, 'tags': ['tabletop', 'lamp'], 'size': [0.18, 0.45, 0.25],
                                             'desc': 'gooseneck desk lamp (parts.bulb dimmable)'})


# ------------------------------------------------------------------------------------- skyline backdrop
def skylineTex():
    def draw(ctx, w, h, rand):
        sky = ctx.createLinearGradient(0, 0, 0, h)
        sky.addColorStop(0, '#16185A')
        sky.addColorStop(0.45, '#3A2E86')
        sky.addColorStop(0.72, '#9A4A8C')
        sky.addColorStop(0.86, '#E3662B')
        sky.addColorStop(1, '#F6A94A')
        ctx.fillStyle = sky
        ctx.fillRect(0, 0, w, h)
        for i in range(160):
            ctx.fillStyle = 'rgba(255,244,214,%s)' % js_str(0.3 + rand() * 0.6)
            s = 3 if rand() < 0.1 else 1.6
            ctx.fillRect(rand() * w, rand() * h * 0.5, s, s)
        # moon (right, under the logo band)
        ctx.fillStyle = '#FFF4D6'
        ctx.beginPath()
        ctx.arc(w * 0.9, h * 0.47, 40, 0, TAU)
        ctx.fill()
        ctx.fillStyle = '#3A2E86'
        ctx.globalAlpha = 0.92
        ctx.beginPath()
        ctx.arc(w * 0.9 + 20, h * 0.47 - 9, 37, 0, TAU)
        ctx.fill()
        ctx.globalAlpha = 1

        # skyline layers
        def layer(base, col, win, minH, maxH, bw):
            x = -10
            while x < w:
                bwid = bw * (0.6 + rand() * 0.9)
                bh = minH + rand() * (maxH - minH)
                top = h - base - bh
                ctx.fillStyle = col
                ctx.fillRect(x, top, bwid, bh + base)
                if rand() < 0.3:
                    ctx.fillRect(x + bwid * 0.35, top - 26, bwid * 0.3, 26)
                if rand() < 0.15:
                    ctx.fillRect(x + bwid * 0.48, top - 60, 3, 60)
                    ctx.fillStyle = '#FF3B30'
                    ctx.fillRect(x + bwid * 0.48 - 2, top - 64, 7, 7)
                    ctx.fillStyle = col
                if win:
                    yy = top + 10
                    while yy < h - base - 8:
                        xx = x + 6
                        while xx < x + bwid - 8:
                            if rand() < 0.42:
                                ctx.fillStyle = '#FFD36A' if rand() < 0.8 else '#9FE7FF'
                                ctx.fillRect(xx, yy, 6, 8)
                            xx += 12
                        yy += 16
                x += bwid + 2
        layer(0, '#2A2F6B', False, 180, 330, 70)
        layer(0, '#1E2150', True, 90, 250, 90)
        layer(0, '#141638', True, 30, 120, 110)
        # logo band across the top (the world clocks hang under it)
        ctx.fillStyle = 'rgba(16,12,44,0.72)'
        ctx.fillRect(0, 18, w, 128)
        for i, c in enumerate([PAL.harvestGold, PAL.burntOrange, PAL.channelRed]):
            ctx.fillStyle = c
            ctx.fillRect(0, 150 + i * 13, w, 9)
        cx = w / 2
        ctx.fillStyle = '#2F5BD3'
        ctx.beginPath()
        ctx.arc(cx, 82, 58, 0, TAU)
        ctx.fill()
        ctx.strokeStyle = '#E23B3B'
        ctx.lineWidth = 12
        ctx.stroke()
        drawText(ctx, '13', cx, 88, {'font': 'Shrikhand', 'size': 70, 'fill': '#F4F1E8'})
        drawText(ctx, 'ACTION', cx - 78, 84, {'font': 'Bungee', 'size': 56, 'fill': '#F6E7C8', 'align': 'right'})
        drawText(ctx, 'NEWS', cx + 78, 80, {'font': 'Shrikhand', 'size': 64, 'fill': '#FFC23A', 'align': 'left'})
    return K.tex.canvas('nm_skyline_v1', 1024, 768, draw, {'repeat': False, 'fonts': True})


def _nm_skyline(game, opts=None):
    opts = opts or {}
    g = K.prop('nm_skyline')
    mt = stdMats(game)
    W = opts['w'] if opts.get('w') is not None else 4.2
    H = opts['h'] if opts.get('h') is not None else 3.2
    y0 = 0.35
    face = K.m(quad(W, H), K.mat(game, 'paint', '#ffffff', {'map': skylineTex(), 'rim': 0.08, 'emissive': '#1A1850', 'emissiveIntensity': 0.25}),
               {'pos': [0, y0 + H / 2, -0.07], 'rot': [0, math.pi, 0], 'cast': False})
    g.add(face)
    g.add(K.m(tc(K.box(W + 0.1, H + 0.1, 0.1, 'sm'), '#2A2230'), mt.paint, {'pos': [0, y0 + H / 2, -0.01]}))
    # chunky frame: teak bottom sill + chrome edges
    g.add(K.m(K.box(W + 0.24, 0.14, 0.2, 'md', {'uv': 1.2}), mt.teak, {'pos': [0, y0 - 0.02, -0.08]}))
    g.add(K.m(tc(K.box(W + 0.24, 0.35, 0.12, 'sm'), '#3A2A40'), mt.paint, {'pos': [0, 0.175, -0.06]}))
    for s in [-1, 1]:
        g.add(K.m(K.box(0.06, H + 0.1, 0.06, 'sm'), mt.chrome, {'pos': [s * (W / 2 + 0.06), y0 + H / 2, -0.09]}))
    g.add(K.m(K.box(W + 0.18, 0.06, 0.06, 'sm'), mt.chrome, {'pos': [0, y0 + H + 0.06, -0.09]}))
    u = g.userData
    u.parts = {'face': face}
    u.colliders = [{'min': [-W / 2 - 0.12, 0, -0.18], 'max': [W / 2 + 0.12, y0 + H + 0.1, 0.05]}]
    return K.finish(game, g, {'ao': {'floor': False, 'height': 0.1, 'res': 40}})


registerProp('nm_skyline', _nm_skyline, {'category': CAT, 'tags': ['newsroom', 'wall', 'backdrop'], 'size': [4.44, 3.6, 0.2],
                                         'desc': 'painted night-skyline news backdrop with the ACTION 13 NEWS logo (back at z = 0)'})


# ==================================================================================== master control (mc_*)
CAT_MC = 'rooms_mc'
WALL = _Obj(n=-13.85, s=-2.15, w=23.15, e=34.85)
DETENT = TAU / 13


def hash_(n):
    s = math.sin(n * 127.1 + 311.7) * 43758.5453
    return s - math.floor(s)


# ================================================================================================ mc atlas
# 512² print atlas (4 x 4 cells of 128 px): fire sign, no smoking, the SIGN OFF shelf label, VTR BAY sign, the
# switcher key plate, tape-box labels. cell(name) -> [u0, v0, u1, v1].
MCELLS = {
    'fire': [0, 0], 'nosmoke': [1, 0], 'signoff': [2, 0, 2, 1], 'vtrbay': [0, 1, 2, 1], 'router': [2, 1, 2, 1],
    'tapelbl': [0, 2, 4, 1], 'library': [0, 3, 4, 1],
}


def mcAtlasTex():
    def draw(ctx, W, H, rand):
        ctx.clearRect(0, 0, W, H)
        C = 128

        def at(n):
            c = MCELLS[n]
            return [c[0] * C, c[1] * C, (c[2] if len(c) > 2 else 1) * C, (c[3] if len(c) > 3 else 1) * C]

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
            ctx.fillStyle = fill
            ctx.fillText(s, 0, 0)
            ctx.restore()
        SIGN = '"Bungee", Impact, "Arial Black", sans-serif'
        ROUND = '"Titan One", "Arial Rounded MT Bold", "Arial Black", sans-serif'
        HAND = '"Titan One", "Comic Sans MS", sans-serif'
        x, y, w, h = at('fire')
        rr(x + 6, y + 6, w - 12, h - 12, 12)
        ctx.fillStyle = '#E23B3B'
        ctx.fill()
        ctx.fillStyle = '#FFE3A3'
        ctx.beginPath()
        ctx.moveTo(x + 64, y + 22)
        ctx.bezierCurveTo(x + 96, y + 52, x + 90, y + 88, x + 64, y + 94)
        ctx.bezierCurveTo(x + 38, y + 88, x + 32, y + 56, x + 52, y + 40)
        ctx.bezierCurveTo(x + 52, y + 56, x + 60, y + 60, x + 64, y + 22)
        ctx.fill()
        text('FIRE', x + 64, y + 110, 20, SIGN, '#FBF8F1')
        x, y, w, h = at('nosmoke')
        ctx.fillStyle = '#FBF8F1'
        rr(x + 6, y + 6, w - 12, h - 12, 12)
        ctx.fill()
        ctx.fillStyle = '#5A3A22'
        ctx.fillRect(x + 30, y + 58, 60, 12)
        ctx.fillStyle = '#E3662B'
        ctx.fillRect(x + 84, y + 58, 10, 12)
        ctx.strokeStyle = '#E23B3B'
        ctx.lineWidth = 9
        ctx.beginPath()
        ctx.arc(x + 64, y + 60, 38, 0, TAU)
        ctx.moveTo(x + 37, y + 33)
        ctx.lineTo(x + 91, y + 87)
        ctx.stroke()
        text('NO SMOKING', x + 64, y + 112, 13, SIGN, '#2A2231')
        x, y, w, h = at('signoff')
        ctx.fillStyle = '#FBF8F1'
        rr(x + 8, y + 30, w - 16, h - 60, 6)
        ctx.fill()
        ctx.strokeStyle = '#2A2A8A'
        ctx.lineWidth = 3
        ctx.strokeRect(x + 14, y + 36, w - 28, h - 72)
        text('SIGN OFF', x + w / 2, y + 60, 34, HAND, '#E23B3B', {'rot': -0.03})
        text('12:00 AM  · #13', x + w / 2, y + 88, 16, HAND, '#2A2A8A', {'rot': -0.02})
        x, y, w, h = at('vtrbay')
        rr(x + 4, y + 20, w - 8, h - 40, 14)
        ctx.fillStyle = '#2A2231'
        ctx.fill()
        ctx.strokeStyle = '#FFB347'
        ctx.lineWidth = 5
        ctx.stroke()
        text('QUAD VTR BAY', x + w / 2, y + h / 2 - 4, 34, SIGN, '#FFB347', {'max': w - 30})
        text('2-INCH · 15 IPS', x + w / 2, y + h / 2 + 26, 14, ROUND, '#F6E7C8')
        x, y, w, h = at('router')
        rr(x + 4, y + 30, w - 8, h - 60, 10)
        ctx.fillStyle = '#F6E7C8'
        ctx.fill()
        text('ROUTE-O-MATIC 16', x + w / 2, y + h / 2, 26, SIGN, '#2F5BD3', {'max': w - 24})
        x, y, w, h = at('tapelbl')
        ctx.fillStyle = '#F3EEDF'
        ctx.fillRect(x, y, w, h)
        for i in range(8):
            ctx.fillStyle = ['#E23B3B', '#2F5BD3', '#E8A92E', '#52D24A'][i % 4]
            ctx.fillRect(x + i * 64, y, 64, 18)
            ctx.fillStyle = 'rgba(40,30,60,0.7)'
            for k in range(4):
                ctx.fillRect(x + i * 64 + 8, y + 34 + k * 20, 30 + ((i * 7 + k * 3) % 18), 5)
        x, y, w, h = at('library')
        rr(x + 4, y + 24, w - 8, h - 48, 12)
        ctx.fillStyle = '#C8963C'
        ctx.fill()
        rr(x + 12, y + 32, w - 24, h - 64, 8)
        ctx.fillStyle = '#2A2231'
        ctx.fill()
        text('WZTV TAPE LIBRARY', x + w / 2, y + h / 2 + 2, 36, SIGN, '#E8B84A', {'max': w - 50})
    return K.tex.canvas('rooms.mc.atlas.v1', 512, 512, draw, {'repeat': False, 'fonts': True})


def mcAtlas(game):
    mp = mcAtlasTex()
    mp.anisotropy = 8

    def cell(name, sub=(0, 0, 1, 1)):
        c = MCELLS[name]
        cw, ch = (c[2] if len(c) > 2 else 1) / 4, (c[3] if len(c) > 3 else 1) / 4
        u0, vTop = c[0] / 4, 1 - c[1] / 4
        return [u0 + sub[0] * cw, vTop - sub[3] * ch, u0 + sub[2] * cw, vTop - sub[1] * ch]
    return _Obj(map=mp, cell=cell, mat=K.mat(game, 'paint', '#ffffff', {'map': mp, 'rim': 0.12}),
                dim=K.mat(game, 'paint', '#D8CCB0', {'map': mp, 'rim': 0.05, 'rough': 0.9}))


# plane facing -z (prop front) with a rect of UVs
def qf(w, h, rect):
    return quad(w, h, rect).rotateY(PI)


# ============================================================================================ local builders
# Rolling equipment cart (walnut shelves, chrome posts, casters). Returns the group; top shelf at y = top.
def cart(g, mt, W=0.52, D=0.42, top=0.74):
    for y in [0.16, top]:
        g.add(K.m(K.box(W, 0.03, D, 0.01, {'uv': 1.5}), mt.walnut, {'pos': [0, y, 0]}))
        g.add(K.m(K.tube(K.roundRectPath(W - 0.01, D - 0.01, 0.025, 0.018, 2), 0.006, {'seg': 20, 'radial': 4, 'closed': True}), mt.chrome, {'pos': [0, y, 0]}))
    for x, z in [[-1, -1], [1, -1], [-1, 1], [1, 1]]:
        g.add(K.m(K.cyl(0.013, 0.013, top - 0.05, {'seg': 8}), mt.chrome, {'pos': [x * (W / 2 - 0.03), 0.06, z * (D / 2 - 0.03)]}))
        g.add(K.m(tc(sph(0.028, 10, 8), '#2A2231'), mt.rubber, {'pos': [x * (W / 2 - 0.03), 0.028, z * (D / 2 - 0.03)]}))


def lampMatsLaff(game):
    return {'on': K.glow(game, '#FFE14A', 2.0), 'off': K.mat(game, 'plastic', '#8A7A48', {'rim': 0.3}),
            'onR': K.glow(game, '#FF5A3C', 2.0), 'offR': K.mat(game, 'plastic', '#7A3A34', {'rim': 0.3})}


# ---------------------------------------------------------------------------------------------- Laff-O-Matic
# The canned-laughter machine on its cart: cream case, orange face, LAFF-O-MATIC plate, a giant red button (part),
# LAUGH / APPLAUSE lamps (parts, material swap), a VU needle (part), a grinning speaker grille and a tape cart.
# Front -z.
def laffCart(game, NA):
    g = K.prop('mc_laff_o_matic')
    mt = stdMats(game)
    LM = lampMatsLaff(game)
    cart(g, mt)
    y0 = 0.755
    g.add(K.m(tc(K.box(0.46, 0.26, 0.32, 0.05), '#F3E6C8'), mt.lacquer, {'pos': [0, y0 + 0.13, 0.01]}))
    g.add(K.m(tc(K.box(0.42, 0.2, 0.02, 0.02), PAL.burntOrange), mt.lacquer, {'pos': [0, y0 + 0.13, -0.155]}))
    g.add(K.m(quad(0.2, 0.05, NA.cell('plate', [0, 0.5, 1, 1])).rotateY(PI), NA.mat, {'pos': [-0.08, y0 + 0.2, -0.167]}))
    # grinning speaker grille: dark slot + chrome smile
    g.add(K.m(tc(K.box(0.16, 0.05, 0.01, 0.02), '#2A2231'), mt.plastic, {'pos': [-0.08, y0 + 0.1, -0.166]}))
    g.add(K.m(THREE.TorusGeometry(0.08, 0.008, 6, 18, PI), mt.chrome, {'pos': [-0.08, y0 + 0.12, -0.168], 'rot': [0, 0, PI]}))
    # VU meter (needle part)
    g.add(K.m(tc(K.box(0.1, 0.07, 0.01, 0.01), '#FFF1C8'), mt.plastic, {'pos': [0.12, y0 + 0.17, -0.166]}))
    needle = THREE.Group()
    needle.position.set(0.12, y0 + 0.14, -0.173)
    needle.rotation.z = 0.5
    needle.userData.noMerge = True
    needle.add(K.m(tc(K.box(0.004, 0.05, 0.003, 0.001), '#E23B3B'), mt.plastic, {'pos': [0, 0.025, 0]}))
    g.add(needle)
    # lamps
    lampL = K.m(K.lathe([[0, 0], [0.028, 0], [0.028, 0.012], [0.02, 0.028], [0, 0.032]], {'seg': 14, 'round': 0.004}).clone().rotateX(-HP), LM['off'],
                {'pos': [0.08, y0 + 0.075, -0.165], 'cast': False})
    lampR = K.m(K.lathe([[0, 0], [0.028, 0], [0.028, 0.012], [0.02, 0.028], [0, 0.032]], {'seg': 14, 'round': 0.004}).clone().rotateX(-HP), LM['offR'],
                {'pos': [0.16, y0 + 0.075, -0.165], 'cast': False})
    for l in [lampL, lampR]:
        l.userData.noMerge = True
        l.userData.noOcclude = True
        g.add(l)
    # giant red button on top (part), chrome collar
    g.add(K.m(K.cyl(0.075, 0.08, 0.025, {'seg': 20, 'bevel': 0.006}), mt.chrome, {'pos': [0.1, y0 + 0.26, -0.02]}))
    button = THREE.Group()
    button.position.set(0.1, y0 + 0.285, -0.02)
    button.userData.noMerge = True
    button.add(K.m(tc(K.lathe([[0, 0], [0.062, 0], [0.064, 0.02], [0.05, 0.045], [0.025, 0.056], [0, 0.058]], {'seg': 20, 'round': 0.006}), '#E23B3B'), mt.lacquer))
    g.add(button)
    # tape cart slot + cart sticking out
    g.add(K.m(tc(K.box(0.14, 0.02, 0.1, 0.006), '#2A2231'), mt.plastic, {'pos': [-0.1, y0 + 0.262, 0.02]}))
    g.add(K.m(tc(K.box(0.12, 0.05, 0.08, 0.01), '#E8A92E'), mt.plastic, {'pos': [-0.1, y0 + 0.29, 0.03], 'rot': [0.1, 0, 0]}))
    # bottom shelf: tape carts + coiled cord
    for i in range(4):
        g.add(K.m(tc(K.box(0.12, 0.04, 0.1, 0.008), ['#E23B3B', '#2F5BD3', '#E8A92E', '#52D24A'][i]), mt.plastic,
                  {'pos': [-0.14 + (i % 2) * 0.13, 0.195 + math.floor(i / 2) * 0.042, 0.04], 'rot': [0, (i - 1.5) * 0.12, 0]}))
    coil = []
    for i in range(41):
        t = i / 40
        a = t * TAU * 3
        coil.append([0.13 + math.cos(a) * 0.07, 0.19 + t * 0.03, math.sin(a) * 0.06])
    g.add(K.m(tc(K.tube(coil, 0.008, {'seg': 36, 'radial': 4}), '#2A2231'), mt.plastic))
    g.userData.parts = {'button': button, 'needle': needle, 'lampL': lampL, 'lampR': lampR}
    g.userData.lampMats = LM
    g.userData.colliders = [{'min': [-0.28, 0, -0.22], 'max': [0.28, 1.1, 0.22]}]
    return K.finish(game, g, {'ao': {'res': 32}})


# --------------------------------------------------------------------------------------- routing switcher
# "ROUTE-O-MATIC 16": a 4 x 4 grid of lit keys (one mesh whose colours come from a small live canvas, so the key
# chase costs one draw), two knobs, a take bar. Front -z. userData.keyTex = the live canvas texture (a runtime
# texture here: rooms/master_control.gd draws it with DACanvas).
def routerCart(game, MA):
    g = K.prop('mc_switcher')
    mt = stdMats(game)
    cart(g, mt)
    y0 = 0.755
    g.add(K.m(tc(K.box(0.46, 0.1, 0.34, 0.03), '#3B3645'), mt.plastic, {'pos': [0, y0 + 0.05, 0]}))
    g.add(K.m(tc(K.box(0.46, 0.12, 0.08, 0.03), '#3B3645'), mt.plastic, {'pos': [0, y0 + 0.11, 0.13]}))
    g.add(K.m(qf(0.4, 0.07, MA.cell('router')), MA.mat, {'pos': [0, y0 + 0.13, 0.087], 'rot': [-0.25, 0, 0]}))
    # keys on a sloped plate: 4 x 4, UV per key into a 4 x 4 canvas
    keyTex = RuntimeTexture('rooms_mc_router_keys')
    keyTex.magFilter = THREE.NearestFilter
    keyTex.minFilter = THREE.NearestFilter
    keyTex.generateMipmaps = False
    geos = []
    kg = K.box(0.05, 0.035, 0.042, 0.01)
    for r in range(4):
        for c in range(4):
            k = kg.clone()
            uv = k.attributes.uv
            u, v = (c + 0.5) / 4, 1 - (r + 0.5) / 4
            for i in range(uv.count):
                uv.setXY(i, u, v)
            k.translate(-0.105 + c * 0.07, 0.008, -0.095 + r * 0.062)
            geos.append(k)
    keysGeo = THREE.mergeGeometries(geos, False)
    keys = K.m(keysGeo, game.mats.glow('#ffffff', 1.4, {'map': keyTex}), {'pos': [-0.04, y0 + 0.108, -0.04], 'rot': [0.12, 0, 0], 'cast': False})
    keys.userData.noMerge = True
    keys.userData.noOcclude = True
    g.add(keys)
    for x in [0.15, 0.2]:
        g.add(K.m(tc(K.lathe([[0, 0], [0.018, 0], [0.017, 0.025], [0.012, 0.032], [0, 0.033]], {'seg': 12, 'round': 0.003}), '#2A2231'), mt.plastic, {'pos': [x, y0 + 0.1, -0.1]}))
    g.add(K.m(K.cyl(0.008, 0.008, 0.12, {'seg': 8}), mt.chrome, {'pos': [0.175, y0 + 0.1, 0.0], 'rot': [0.3, 0, 0]}))
    g.add(K.m(tc(sph(0.02, 10, 8), '#E23B3B'), mt.plastic, {'pos': [0.175, y0 + 0.215, 0.035]}))
    for i in range(3):
        g.add(K.m(tc(K.box(0.2, 0.012, 0.2, 0.004), ['#2F5BD3', '#E23B3B', '#F4F1E8'][i]), mt.paint, {'pos': [0.02, 0.18 + i * 0.013, 0.02], 'rot': [0, (i - 1) * 0.15, 0]}))
    g.userData.parts = {'keys': keys}
    g.userData.keyCanvas = None
    g.userData.keyTex = keyTex
    g.userData.colliders = [{'min': [-0.28, 0, -0.22], 'max': [0.28, 1.0, 0.22]}]
    return K.finish(game, g, {'ao': {'res': 32}})


# --------------------------------------------------------------------------------------- waveform/vector cart
# Two scope CRTs on a cart: the waveform monitor (green line traces) and the vectorscope (green star); faces are one
# mesh with lit/unlit materials (parts.faces, lampMats {on, off}). Front -z.
def scopeTex():
    def draw(ctx, w, h, rand):
        S = 256
        for i in range(2):
            x0 = i * S
            g = ctx.createRadialGradient(x0 + S / 2, h / 2, 10, x0 + S / 2, h / 2, S * 0.7)
            g.addColorStop(0, '#0E3A26')
            g.addColorStop(1, '#04140C')
            ctx.fillStyle = g
            ctx.fillRect(x0, 0, S, h)
            ctx.strokeStyle = 'rgba(120,255,160,0.25)'
            ctx.lineWidth = 2
            for k in range(1, 8):
                ctx.beginPath()
                ctx.moveTo(x0 + k * 32, 16)
                ctx.lineTo(x0 + k * 32, h - 16)
                ctx.stroke()
                ctx.beginPath()
                ctx.moveTo(x0 + 16, k * 32)
                ctx.lineTo(x0 + S - 16, k * 32)
                ctx.stroke()
        ctx.shadowColor = '#7CFF9A'
        ctx.shadowBlur = 8
        ctx.strokeStyle = '#9CFFB0'
        ctx.lineWidth = 3
        # waveform: colour-bar staircase + sync
        ctx.beginPath()
        lv = [0.78, 0.7, 0.58, 0.52, 0.44, 0.36, 0.26]
        ctx.moveTo(20, 200)
        for k, l in enumerate(lv):
            x = 30 + k * 30
            ctx.lineTo(x, 230 - l * 200)
            ctx.lineTo(x + 28, 230 - l * 200)
        ctx.lineTo(240, 200)
        ctx.stroke()
        ctx.beginPath()
        x = 20
        while x < 240:
            ctx.lineTo(x, 214 + math.sin(x * 0.4) * 3)
            x += 4
        ctx.stroke()
        # vectorscope: graticule circle + colour-bar star
        cx, cy = S + S / 2, h / 2
        ctx.strokeStyle = 'rgba(156,255,176,0.6)'
        ctx.lineWidth = 2
        ctx.beginPath()
        ctx.arc(cx, cy, 100, 0, TAU)
        ctx.stroke()
        ctx.strokeStyle = '#9CFFB0'
        ctx.lineWidth = 3
        ctx.beginPath()
        pts = [[0.2, 1.3], [0.8, 2.4], [0.7, 3.4], [0.75, 4.4], [0.8, 5.5], [0.7, 0.3]]
        ctx.moveTo(cx, cy)
        for r, a in pts:
            ctx.lineTo(cx + math.cos(a) * r * 90, cy + math.sin(a) * r * 90)
            ctx.lineTo(cx, cy)
        ctx.stroke()
        ctx.shadowBlur = 0
    return K.tex.canvas('rooms.mc.scopes.v1', 512, 256, draw, {'repeat': False})


def scopeCart(game):
    g = K.prop('mc_scope_cart')
    mt = stdMats(game)
    cart(g, mt, 0.6, 0.46, 0.7)
    mp = scopeTex()
    on = game.mats.glow('#ffffff', 1.15, {'map': mp})
    off = K.mat(game, 'crt', '#1A2A22', {'map': mp})
    geos = []
    for x, y, i in [[-0.14, 0.95, 0], [0.14, 0.95, 1]]:
        g.add(K.m(tc(K.box(0.27, 0.24, 0.36, 0.03), '#6B7282'), mt.metal, {'pos': [x, y, 0.02]}))
        g.add(K.m(tc(K.box(0.25, 0.22, 0.02, 0.02), '#2A2231'), mt.plastic, {'pos': [x, y, -0.16]}))
        f = quad(0.19, 0.15, [i * 0.5, 0, i * 0.5 + 0.5, 1]).rotateY(PI).translate(x, y + 0.01, -0.172)
        geos.append(f)
        for k in range(3):
            g.add(K.m(tc(K.cyl(0.012, 0.012, 0.012, {'seg': 8}), '#C9CED6'), mt.plastic, {'pos': [x - 0.07 + k * 0.07, y - 0.09, -0.172], 'rot': [HP, 0, 0]}))
    faces = K.m(THREE.mergeGeometries(geos, False), off, {'cast': False})
    faces.userData.noMerge = True
    faces.userData.noOcclude = True
    g.add(faces)
    # label + probe cable
    g.add(K.m(K.tube([[0.25, 0.9, 0.2], [0.33, 0.6, 0.25], [0.3, 0.2, 0.3], [0.45, 0.02, 0.5]], 0.01, {'seg': 16, 'radial': 5}), K.mat(game, 'rubber', '#2A2230')))
    g.userData.parts = {'faces': faces}
    g.userData.lampMats = {'on': on, 'off': off}
    g.userData.colliders = [{'min': [-0.32, 0, -0.26], 'max': [0.32, 1.12, 0.26]}]
    return K.finish(game, g, {'ao': {'res': 32}})


# ------------------------------------------------------------------------------------------- tape library
# Steel shelving of 2" quad tape boxes (spines from the newsroom atlas), a row of round tape cans on top, a WZTV
# TAPE LIBRARY header, shelf-edge labels and ONE EMPTY SLOT with a hand-written SIGN OFF label (the missing reel of
# EE step 5). Front -z, back at local z = +D/2.
def tapeShelf(game, NA, MA):
    g = K.prop('mc_tape_shelf')
    mt = stdMats(game)
    W, H, D = 1.9, 2.0, 0.42
    steel = '#7C8594'
    for s in [-1, 1]:
        g.add(K.m(tc(K.box(0.04, H, D, 0.01), steel), mt.metal, {'pos': [s * (W / 2 - 0.02), H / 2, 0]}))
    g.add(K.m(tc(K.box(W, H - 0.02, 0.02, 0.006), '#5A6070'), mt.metal, {'pos': [0, H / 2, D / 2 - 0.01]}))
    shelfY = [0.08, 0.5, 0.92, 1.34, 1.76]
    for y in shelfY:
        g.add(K.m(tc(K.box(W - 0.06, 0.03, D - 0.02, 0.008), steel), mt.metal, {'pos': [0, y, 0]}))
        g.add(K.m(tc(K.box(W - 0.06, 0.04, 0.012, 0.004), '#9EA4AE'), mt.metal, {'pos': [0, y + 0.005, -D / 2 + 0.01]}))
    # tape boxes: 4 shelves, box width varies; spines = 1/8 of the 'spines' cell each
    boxGeo = K.box(1, 1, 1, 0.004)
    spineMat = NA.mat
    for si in range(4):
        y = shelfY[si] + 0.015
        x = -W / 2 + 0.07
        k = si * 5
        while x < W / 2 - 0.1:
            bw = 0.055 + hash_(k * 1.7) * 0.02
            bh = 0.34 + hash_(k * 2.3) * 0.02
            empty = si == 1 and abs(x - 0.15) < 0.05
            if empty:            # the missing Sign-Off reel
                x += 0.1
                k += 1
                continue
            lean = -0.18 if (x > W / 2 - 0.2 and si == 3) else 0
            b = boxGeo.clone().scale(bw, bh, 0.34)
            g.add(K.m(tc(b, '#E8E0CC'), mt.paint, {'pos': [x + bw / 2, y + bh / 2, 0.01], 'rot': [0, 0, lean]}))
            s = k % 8
            g.add(K.m(qf(bw - 0.006, bh - 0.02, NA.cell('spines', [s / 8, 0.05, (s + 1) / 8, 0.95])), spineMat,
                      {'pos': [x + bw / 2, y + bh / 2, -0.161], 'rot': [0, 0, lean]}))
            x += bw + 0.004
            k += 1
    # shelf 2 empty-slot label (hand-written SIGN OFF card) + shelf label strips
    g.add(K.m(qf(0.13, 0.065, MA.cell('signoff')), MA.dim, {'pos': [0.2, shelfY[1] - 0.03, -D / 2 - 0.002], 'rot': [0, 0, 0.04]}))
    for si in range(4):
        g.add(K.m(qf(0.3, 0.035, MA.cell('tapelbl', [si * 0.25, 0, si * 0.25 + 0.25, 1])), MA.mat, {'pos': [-0.55 + (si % 2) * 1.1, shelfY[si] - 0.03, -D / 2 - 0.003]}))
    # top: round tape cans + a reel in the open
    for i in range(6):
        cx = -0.72 + i * 0.26
        g.add(K.m(tc(K.cyl(0.13, 0.13, 0.05, {'seg': 20, 'bevel': 0.006}), ['#B8BEC8', '#E23B3B', '#B8BEC8', '#2F5BD3', '#B8BEC8', '#E8A92E'][i]), mt.metal,
                  {'pos': [cx, shelfY[4] + 0.015 + (i % 2) * 0.05, 0.0]}))
    g.add(K.m(qf(1.1, 0.14, MA.cell('library')), MA.mat, {'pos': [0, H + 0.12, -D / 2 + 0.02]}))
    g.add(K.m(tc(K.box(1.16, 0.18, 0.03, 0.01), '#2A2231'), mt.plastic, {'pos': [0, H + 0.12, -D / 2 + 0.04]}))
    g.userData.colliders = [{'min': [-W / 2, 0, -D / 2], 'max': [W / 2, H + 0.2, D / 2]}]
    return K.finish(game, g, {'ao': {'res': 48}})


# ------------------------------------------------------------------------------------------ ladder cable tray
# Hanging ladder tray along local x (length L), rails + rungs + a colourful cable bundle lying in it, drop rods to
# the ceiling (rod = ceiling height above the tray bottom). y = 0 is the tray bottom.
def cableTray(game, L, rod=0.32):
    g = K.prop('mc_cable_tray')
    mt = stdMats(game)
    Wd = 0.34
    for s in [-1, 1]:
        g.add(K.m(tc(K.box(L, 0.08, 0.025, 0.006), '#5C6474'), mt.paint, {'pos': [0, 0.04, s * Wd / 2]}))
    rungs = math.floor(L / 0.3)
    for i in range(rungs + 1):
        g.add(K.m(tc(K.box(0.03, 0.02, Wd, 0.004), '#5C6474'), mt.paint, {'pos': [-L / 2 + (i / rungs) * L, 0.01, 0]}))
    x = -L / 2 + 0.3
    while x < L / 2:
        for s in [-1, 1]:
            g.add(K.m(K.cyl(0.008, 0.008, rod, {'seg': 6}), mt.chrome, {'pos': [x, 0.04, s * (Wd / 2 + 0.01)]}))
        x += 1.6
    cols = ['#2A2231', '#E3662B', '#2F5BD3', '#E8A92E', '#2A2231', '#E23B3B', '#52D24A']
    for i, c in enumerate(cols):
        z, y = -Wd / 2 + 0.04 + (i % 4) * 0.08, 0.035 + math.floor(i / 4) * 0.035
        pts = []
        for k in range(9):
            pts.append([-L / 2 + (k / 8) * L, y + math.sin(k * 1.3 + i) * 0.006, z + math.sin(k * 0.9 + i * 2) * 0.012])
        g.add(K.m(tc(K.tube(pts, 0.016, {'seg': max(8, js_round(L * 3)), 'radial': 5}), c), mt.rubber))
    g.userData.colliders = []
    return K.finish(game, g, {'ao': False})


# -------------------------------------------------------------------------------------------- picture light
# Brass picture light over the rundown board: wall plate, swan arm, hood with a glowing slot (parts.glow).
def pictureLight(game):
    g = K.prop('mc_picture_light')
    mt = stdMats(game)
    g.add(K.m(K.box(0.12, 0.08, 0.02, 0.008), mt.brass, {'pos': [0, 0, -0.01]}))
    g.add(K.m(K.tube([[0, 0, -0.02], [0, 0.06, -0.12], [0, 0.04, -0.22]], 0.012, {'seg': 10, 'radial': 6}), mt.brass))
    g.add(K.m(K.cyl(0.05, 0.05, 0.6, {'seg': 16}).clone().rotateZ(HP), mt.brass, {'pos': [0.3, 0.02, -0.24]}))
    glow = K.m(K.box(0.56, 0.012, 0.04, 0.004), K.mat(game, 'plastic', '#C8B890'), {'pos': [0, -0.03, -0.24], 'cast': False})
    glow.userData.noMerge = True
    glow.userData.noOcclude = True
    g.add(glow)
    g.userData.parts = {'glow': glow}
    g.userData.colliders = []
    return K.finish(game, g, {'ao': False})


# ------------------------------------------------------------------------------------------ fire extinguisher
def extinguisher(game, MA):
    g = K.prop('mc_extinguisher')
    mt = stdMats(game)
    g.add(K.m(tc(K.box(0.14, 0.2, 0.02, 0.006), '#3B3645'), mt.metal, {'pos': [0, 0.5, -0.01]}))
    g.add(K.m(tc(K.lathe([[0, 0], [0.085, 0], [0.09, 0.03], [0.09, 0.5], [0.07, 0.56], [0.03, 0.58], [0, 0.585]], {'seg': 20, 'round': 0.01}), '#D8342C'), mt.lacquer, {'pos': [0, 0.12, -0.11]}))
    g.add(K.m(K.cyl(0.02, 0.024, 0.06, {'seg': 10}), mt.chrome, {'pos': [0, 0.7, -0.11]}))
    g.add(K.m(K.box(0.14, 0.02, 0.03, 0.006), mt.chrome, {'pos': [0.04, 0.77, -0.11], 'rot': [0, 0, -0.2]}))
    g.add(K.m(tc(K.tube([[0.03, 0.74, -0.11], [0.12, 0.7, -0.14], [0.12, 0.35, -0.17], [0.07, 0.25, -0.18]], 0.012, {'seg': 14, 'radial': 5}), '#2A2231'), mt.rubber))
    g.add(K.m(qf(0.24, 0.24, MA.cell('fire')), MA.mat, {'pos': [0, 1.0, -0.004]}))
    g.userData.colliders = [{'min': [-0.12, 0, -0.22], 'max': [0.14, 0.75, 0]}]
    return K.finish(game, g, {'ao': {'res': 28, 'floor': False}})


# ------------------------------------------------------------------------------------- oscillating floor fan
# Chrome 70s floor fan (all that tube gear runs hot): weighted base, pole, motor, wire cage, 4 blades (part 'blades',
# spins about local z) on an oscillating head (part 'head', swings about y). Front -z.
def floorFan(game):
    g = K.prop('mc_floor_fan')
    mt = stdMats(game)
    g.add(K.m(K.lathe([[0, 0], [0.2, 0], [0.205, 0.02], [0.15, 0.05], [0.04, 0.07], [0, 0.07]], {'seg': 24, 'round': 0.008}), mt.chrome))
    g.add(K.m(K.cyl(0.018, 0.018, 1.0, {'seg': 10}), mt.chrome, {'pos': [0, 0.06, 0]}))
    head = THREE.Group()
    head.position.set(0, 1.12, 0)
    head.userData.noMerge = True
    head.add(K.m(tc(K.cyl(0.07, 0.08, 0.16, {'seg': 16, 'bevel': 0.02}).clone().rotateX(HP), '#8C9A3A'), mt.lacquer, {'pos': [0, 0, 0.1]}))
    head.add(K.m(tc(K.box(0.05, 0.08, 0.05, 0.015), '#8C9A3A'), mt.lacquer, {'pos': [0, -0.06, 0.1]}))

    def ring(r):
        pts = []
        for i in range(29):
            a = (i / 28) * TAU
            pts.append([math.cos(a) * r, math.sin(a) * r, 0])
        return K.tube(pts, 0.005, {'seg': 36, 'radial': 4, 'closed': True})
    for r, z in [[0.26, -0.04], [0.18, -0.07], [0.09, -0.085]]:
        head.add(K.m(ring(r), mt.chrome, {'pos': [0, 0, z]}))
    for i in range(12):
        a = (i / 12) * TAU
        head.add(K.m(K.tube([[0, 0, -0.09], [math.cos(a) * 0.18, math.sin(a) * 0.18, -0.07], [math.cos(a) * 0.26, math.sin(a) * 0.26, -0.04],
                             [math.cos(a) * 0.26, math.sin(a) * 0.26, 0.04]], 0.004, {'seg': 6, 'radial': 3}), mt.chrome))
    head.add(K.m(tc(K.cyl(0.03, 0.03, 0.012, {'seg': 12}), '#E23B3B'), mt.lacquer, {'pos': [0, 0, -0.095], 'rot': [HP, 0, 0]}))
    blades = THREE.Group()
    blades.position.set(0, 0, 0.0)
    blades.userData.noMerge = True
    for i in range(4):
        b = K.m(tc(K.box(0.07, 0.2, 0.012, 0.03), '#E8E0CC'), mt.plastic, {'pos': [0, 0.12, 0], 'rot': [0.25, 0, 0]})
        piv = THREE.Group()
        piv.rotation.z = (i / 4) * TAU
        piv.add(b)
        blades.add(piv)
    blades.add(K.m(tc(K.cyl(0.035, 0.035, 0.04, {'seg': 12}).clone().rotateX(HP), '#8C9A3A'), mt.lacquer, {'pos': [0, 0, 0.02]}))
    head.add(blades)
    g.add(head)
    g.userData.parts = {'head': head, 'blades': blades}
    g.userData.colliders = [{'min': [-0.21, 0, -0.21], 'max': [0.21, 1.1, 0.21]}]
    return K.finish(game, g, {'ao': {'res': 28}})


# ------------------------------------------------------------------------------------------- tape library cart
def tapeCart(game, NA):
    g = K.prop('mc_tape_cart')
    mt = stdMats(game)
    cart(g, mt, 0.8, 0.44, 0.84)
    g.add(K.m(K.tube([[0.4, 0.86, -0.2], [0.5, 0.95, -0.2], [0.5, 0.95, 0.2], [0.4, 0.86, 0.2]], 0.012, {'seg': 10, 'radial': 6}), mt.chrome))
    for y, n in [[0.175, 9], [0.855, 7]]:
        for i in range(n):
            bw, x = 0.065, -0.34 + i * 0.075
            lean = -0.25 if i == n - 1 else 0
            g.add(K.m(tc(K.box(bw, 0.34, 0.34, 0.004), '#E8E0CC'), mt.paint, {'pos': [x + (0.03 if lean else 0), y + 0.17, 0], 'rot': [0, 0, lean]}))
            s = (i * 3 + (1 if y > 0.5 else 0)) % 8
            g.add(K.m(qf(bw - 0.006, 0.32, NA.cell('spines', [s / 8, 0.05, (s + 1) / 8, 0.95])), NA.mat,
                      {'pos': [x + (0.03 if lean else 0), y + 0.17, -0.171], 'rot': [0, 0, lean]}))
    g.userData.colliders = [{'min': [-0.45, 0, -0.24], 'max': [0.52, 1.2, 0.24]}]
    return K.finish(game, g, {'ao': {'res': 32}})


# ------------------------------------------------------------------------------------- tape-box floor stack
def tapeStack(game, NA, n=4, seed=1):
    g = K.prop('mc_tape_stack')
    mt = stdMats(game)
    y = 0
    for i in range(n):
        r = (hash_(seed * 3.1 + i) - 0.5) * 0.4
        s = math.floor(hash_(seed + i * 1.9) * 8)
        g.add(K.m(tc(K.box(0.4, 0.07, 0.4, 0.012), '#E8E0CC'), mt.paint, {'pos': [0, y + 0.035, 0], 'rot': [0, r, 0]}))
        g.add(K.m(quad(0.38, 0.06, NA.cell('spines', [s / 8, 0.3, (s + 1) / 8, 0.7])).rotateY(PI + r), NA.mat,
                  {'pos': [math.sin(r) * -0.201, y + 0.035, -math.cos(r) * 0.201]}))
        y += 0.07
    g.userData.colliders = [{'min': [-0.24, 0, -0.24], 'max': [0.24, y, 0.24]}]
    return K.finish(game, g, {'ao': {'res': 24}})


# ------------------------------------------------------------------------------ transmitter meter panel (wall)
# Wall-mounted "TRANSMITTER REMOTE" panel: three big round meters (needle parts: 0 before power, the output
# swings up after), a row of lamps (lit/unlit swap), a key switch. Back at local z = 0, front -z, y = bottom.
def meterPanel(game, NA):
    g = K.prop('mc_meter_panel')
    mt = stdMats(game)
    W, H = 1.3, 0.72
    g.add(K.m(tc(K.box(W, H, 0.08, 0.02), '#3B3645'), mt.plastic, {'pos': [0, H / 2, -0.04]}))
    g.add(K.m(tc(K.box(W - 0.06, H - 0.06, 0.02, 0.012), '#D8D2C2'), mt.plastic, {'pos': [0, H / 2, -0.085]}))

    def drawFace(ctx, w, h, rand):
        ctx.fillStyle = '#FFF4D6'
        ctx.beginPath()
        ctx.arc(w / 2, h / 2, 62, 0, math.pi * 2)
        ctx.fill()
        ctx.strokeStyle = '#2A2231'
        ctx.lineWidth = 3
        for i in range(11):
            a = math.pi * (1.15 + i * 0.07)
            ctx.beginPath()
            ctx.moveTo(w / 2 + math.cos(a) * 44, h / 2 + 12 + math.sin(a) * 44)
            ctx.lineTo(w / 2 + math.cos(a) * (50 if i % 5 else 54), h / 2 + 12 + math.sin(a) * (50 if i % 5 else 54))
            ctx.stroke()
        ctx.strokeStyle = '#E23B3B'
        ctx.lineWidth = 6
        ctx.beginPath()
        ctx.arc(w / 2, h / 2 + 12, 50, math.pi * 1.75, math.pi * 1.85)
        ctx.stroke()
        ctx.fillStyle = '#2A2231'
        ctx.font = '14px "Bungee", "Arial Black", sans-serif'
        ctx.textAlign = 'center'
        ctx.fillText('KW', w / 2, h / 2 + 36)
    face = K.tex.canvas('rooms.mc.meterface.v1', 128, 128, drawFace, {'repeat': False, 'fonts': True})
    faceMat = K.mat(game, 'plastic', '#ffffff', {'map': face, 'rim': 0.1})
    needles = []
    for x in [-0.4, 0, 0.4]:
        ring = []
        for i in range(25):
            a = (i / 24) * math.pi * 2
            ring.append([x + math.cos(a) * 0.15, 0.42 + math.sin(a) * 0.15, -0.1])
        g.add(K.m(K.tube(ring, 0.012, {'seg': 32, 'radial': 5, 'closed': True}), mt.chrome))
        g.add(K.m(tc(THREE.CircleGeometry(0.145, 28).rotateY(math.pi), '#ffffff'), faceMat, {'pos': [x, 0.42, -0.097]}))
        nd = THREE.Group()
        nd.position.set(x, 0.42 - 0.03, -0.108)
        nd.rotation.z = 1.05
        nd.userData.noMerge = True
        nd.add(K.m(tc(K.box(0.008, 0.12, 0.004, 0.002), '#2A2231'), mt.plastic, {'pos': [0, 0.06, 0]}))
        g.add(nd)
        needles.append(nd)
    plate = K.tex.label('TRANSMITTER', {'sub': 'REMOTE CONTROL · 50 KW', 'bg': '#2A2231', 'fg': '#E8B84A', 'w': 256, 'h': 64})
    g.add(K.m(tc(THREE.PlaneGeometry(0.5, 0.09).rotateY(math.pi), '#ffffff'), K.mat(game, 'plastic', '#ffffff', {'map': plate, 'rim': 0.1}), {'pos': [0, 0.64, -0.097]}))
    lampOn, lampOff = K.glow(game, '#FF8A2A', 1.8), K.mat(game, 'plastic', '#7A5A3A', {'rim': 0.3})
    lamps = K.m(tc(THREE.mergeGeometries([K.cyl(0.025, 0.025, 0.02, {'seg': 12}).clone().rotateX(HP).translate(x, 0.13, -0.1)
                                          for x in [-0.45, -0.3, -0.15, 0.15, 0.3, 0.45]], False), '#ffffff'), lampOff, {'cast': False})
    lamps.userData.noMerge = True
    g.add(lamps)
    g.add(K.m(tc(K.box(0.07, 0.07, 0.03, 0.01), '#C8963C'), mt.brass, {'pos': [0, 0.13, -0.1]}))
    g.userData.parts = {'needles': needles, 'lamps': lamps}
    g.userData.lampMats = {'on': lampOn, 'off': lampOff}
    g.userData.colliders = []
    return K.finish(game, g, {'ao': {'floor': False, 'height': 0, 'res': 32}})


# The master_control.js local builders, registered with their K.prop ids (never registered in the JS: the room
# built them directly; here they are GLB props the room script instances with game.props.build).
registerProp('mc_laff_o_matic', lambda game, opts=None: laffCart(game, atlas(game)),
             {'category': CAT_MC, 'tags': ['master_control', 'toy', 'cart'], 'desc': 'Laff-O-Matic canned-laughter cart (toy_laff_o_matic)'})
registerProp('mc_switcher', lambda game, opts=None: routerCart(game, mcAtlas(game)),
             {'category': CAT_MC, 'tags': ['master_control', 'toy', 'cart'], 'desc': 'ROUTE-O-MATIC 16 routing switcher cart (toy_switcher)'})
registerProp('mc_scope_cart', lambda game, opts=None: scopeCart(game),
             {'category': CAT_MC, 'tags': ['master_control', 'cart'], 'desc': 'waveform monitor + vectorscope cart (parts.faces lit after power)'})
registerProp('mc_tape_shelf', lambda game, opts=None: tapeShelf(game, atlas(game), mcAtlas(game)),
             {'category': CAT_MC, 'tags': ['master_control', 'shelf'], 'desc': 'quad-tape library shelving with the empty SIGN OFF slot'})
registerProp('mc_cable_tray', lambda game, opts=None: cableTray(game, (opts or {}).get('L', 1), (opts or {})['rod'] if (opts or {}).get('rod') is not None else 0.32),
             {'category': CAT_MC, 'tags': ['master_control', 'ceiling'], 'desc': 'hanging ladder cable tray {L, rod}'})
registerProp('mc_picture_light', lambda game, opts=None: pictureLight(game),
             {'category': CAT_MC, 'tags': ['master_control', 'lamp', 'wall'], 'desc': 'brass picture light (parts.glow)'})
registerProp('mc_extinguisher', lambda game, opts=None: extinguisher(game, mcAtlas(game)),
             {'category': CAT_MC, 'tags': ['master_control', 'wall'], 'desc': 'wall fire extinguisher under a FIRE sign'})
registerProp('mc_floor_fan', lambda game, opts=None: floorFan(game),
             {'category': CAT_MC, 'tags': ['master_control'], 'desc': 'oscillating chrome floor fan (parts.head, parts.blades)'})
registerProp('mc_tape_cart', lambda game, opts=None: tapeCart(game, atlas(game)),
             {'category': CAT_MC, 'tags': ['master_control', 'cart'], 'desc': 'tape library cart'})
registerProp('mc_tape_stack', lambda game, opts=None: tapeStack(game, atlas(game), (opts or {}).get('n', 4), (opts or {}).get('seed', 1)),
             {'category': CAT_MC, 'tags': ['master_control'], 'desc': 'floor stack of quad tape boxes {n, seed}'})
registerProp('mc_meter_panel', lambda game, opts=None: meterPanel(game, atlas(game)),
             {'category': CAT_MC, 'tags': ['master_control', 'wall'], 'desc': 'TRANSMITTER REMOTE meter panel (parts.needles, parts.lamps)'})
