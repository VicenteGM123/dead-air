"""DEAD AIR — props: broadcast gear (docs/PROPKIT.md). Port of src/props/broadcast.js (line by line).

1977 TV-station hardware for Master Control, the studios, the newsroom and the lobby exhibit. One shared 1024^2
canvas ATLAS ("bc_atlas_2") carries flat palette swatches (32 px cells, rows 0-1), lit lamp colors (row 2) and every
printed part (dials, VU faces, jacks, nameplates, signs, slate, reel faces), so most props render with 3-6
materials: paletted plastic (pl), paletted matte (mt), paletted metal (me), chrome (ch), lit atlas (lit / soft / sign
glows), dim (unlit lamp), CRT glass + one CRT per screen.

PROPS (category 'broadcast')
  bc_pedestal_camera   hero studio camera: tally dome, zoom lens + matte box, pan bars, headset on hook
  bc_eng_camera        hero ENG shoulder camera on a wooden tripod, battery belt on the front leg
  bc_tv_portable       13" red portable, VHF/UHF dials, rabbit ears          bc_tv_19        19" walnut TV on legs
  bc_rack_monitor      broadcast rack monitor (9"/14")                        bc_monitor_bank hero 5-CRT bank
  bc_cart_monitor      hero AV cart: 19" monitor + cassette deck              bc_monitor_wall hero MC 4x3 CRT wall
  bc_console_switcher / _audio / _monitor (hero, preview monitor) / _corner (45 deg) / _end   MC island segments
  bc_patch_bay         19" rack with patch rows + cords                       bc_vtr_quad     hero quad 2" VTR
  bc_boom_mic          hero Fisher boom dolly                                 bc_light_fresnel / _scoop (hanging)
  bc_light_tripod / bc_light_softbox (floor stands)                           bc_grid_clamp / bc_grid_batten
  bc_cable_spaghetti / bc_cable_coil (walkable)                               bc_flight_case / _stack (hero)
  bc_on_air (wall) / bc_applause (hero, hanging)                              bc_clapperboard, bc_teleprompter
  bc_reel_to_reel, bc_headphones_hook (wall)
Scenes: bc_master_control, bc_studio. Debug (only with PROFILE, JS ?bcprof=1): bc__atlas, bc__vu + per-prop tri log.

Conventions (on top of the kit's): wall-mounted props (ON AIR, headphones hook) have their back face at z = +D/2
(place at wallZ - D/2); hanging props (APPLAUSE, grid lights, batten, clamp) keep y = 0 at their lowest point and
expose userData.hang.pipeY (pipe center above the origin: place at gridY - pipeY); grid lights expose
userData.aim {pos, dir} for spot lights. Screens get ids in userData.screens[i].id where useful. Named parts
(userData.parts) are noMerge so rooms/machines can animate or re-material them; lamps expose
userData.lampMats = { on, off } and the JS exported setLamp(prop, 'on'|'off'|color, part='lamp') (runtime helper:
ported on the Godot side, it rewrites the lamp mesh UVs to a LIT swatch; LAMP_COLORS / LITUV are kept here).
Geometry helpers (local): cbox (44-tri chamfer box), keycap (18 tris), L/bcyl (1-step lathes), frame (bevelled
ring: keep bevel < 0.35 * border), monitorUnit, tapeReel, spindle, vuMeter, knob, caster, rabbitEars, fresnelHead.

Port notes: JS `a ?? b` -> nn(a, b); `opts.x?.[i]` -> _at(opts.get('x'), i); closures that mutate a captured `let`
use `nonlocal`. The JS `setLamp` runtime helper is not ported here (Godot props runtime owns it).
"""
import math

import numpy as np

from dalib import kit as K
from dalib.kit import registerProp, registerScene, PAL, THREE, getCard
from dalib.rng import mulberry32
from dalib.mathutils3 import JSObj, js_str, js_round, js_to_fixed

TAU, HP = math.pi * 2, math.pi / 2
UP = THREE.Vector3(0, 1, 0)


def nn(v, d):
    """JS `v ?? d`."""
    return d if v is None else v


def _at(lst, i):
    """JS `lst?.[i]` (undefined -> None)."""
    if lst is None:
        return None
    try:
        return lst[i]
    except (IndexError, KeyError, TypeError):
        return None


def _truthy(v):
    return K._truthy(v)


# ================================================================================================= ATLAS
AS = 1024
# flat swatches: rows 0-1 (32) + row 3 (16). Sampled at the swatch center (palette texturing).
SW = {
    'cream': '#F6E7C8', 'ivory': '#EFE6D2', 'capWhite': '#F4F1E8', 'putty': '#D2C6AE', 'beige': '#C4B394',
    'sand': '#E3D3B0',
    'wztvBlue': '#2F5BD3', 'navy': '#22367A', 'sky': '#86B6EA', 'teal': '#2E8C8C',
    'red': '#E23B3B', 'maroon': '#8E2A2E', 'orange': '#E3662B', 'gold': '#E8A92E', 'mustard': '#D9A520',
    'avocado': '#8C9A3A',
    'chocolate': '#5A3A22', 'walnut': '#7A4A2A', 'tan': '#B8895A', 'plum': '#6B3A6E',
    'ink': '#2A2231', 'charcoal': '#3B3645', 'slate': '#505A6E', 'gunmetal': '#6B7282', 'grey': '#8F95A0',
    'silver': '#B8BEC8', 'light': '#DADDE2',
    'rubber': '#2B2530', 'black': '#1D1822', 'white': '#FBF8F1', 'olive': '#6E7A34', 'rust': '#B5472A',
    # row 3
    'lampRed': '#7A2428', 'lampAmber': '#86602A', 'lampGreen': '#2F6234', 'lampBlue': '#2C3F78',
    'lampWhite': '#9A9284',
    'tape': '#4A2E1E', 'tapeGold': '#A8823A', 'pink': '#E88AAA', 'lilac': '#A88ACF', 'mint': '#9ED9C0',
    'brass': '#C8963C',
    'copper': '#B8683A', 'cork': '#B98F5E', 'denim': '#3A5A8A', 'paper': '#F3EEDF', 'steel': '#7C8594',
}
# lit swatches (row 2): used with the lit (glow) atlas material
LIT = {
    'red': '#FF3B30', 'amber': '#FFB347', 'green': '#52E04A', 'blue': '#4A86FF', 'white': '#FFF1D8',
    'yellow': '#FFE14A', 'cyan': '#5FE3FF', 'magenta': '#FF4FA0', 'orange': '#FF8A2A', 'tungsten': '#FFC98A',
    'purple': '#B070FF', 'softWhite': '#E8DCC0',
}
# 32 px swatch cells, 32 per row: rows 0-1 flat, row 2 lit. Swatch-mapped meshes have one UV per mesh, so their UV
# derivatives are zero (mip 0 always): no bleeding between neighbours at any distance.
SWS = 32
SWUV = {}
for _i, _k in enumerate(SW.keys()):
    _row, _col = _i // 32, _i % 32
    SWUV[_k] = [(_col * SWS + SWS / 2) / AS, 1 - (_row * SWS + SWS / 2) / AS, _col * SWS, _row * SWS]
LITUV = {}
for _i, _k in enumerate(LIT.keys()):
    LITUV[_k] = [(_i * SWS + SWS / 2) / AS, 1 - (2 * SWS + SWS / 2) / AS, _i * SWS, 2 * SWS]

FONTS = {
    'bungee': '"Bungee", "Arial Black", sans-serif', 'titan': '"Titan One", "Arial Black", sans-serif',
    'vt': '"VT323", "Courier New", monospace', 'shrik': '"Shrikhand", "Cooper Black", Georgia, serif',
    'mono': '"Courier New", Courier, monospace',
}


def txt(ctx, s, x, y, size, font, color, o=None):
    o = o or {}
    f = FONTS.get(font) or font
    sz = size
    ctx.font = '%spx %s' % (js_str(sz), f)
    if o.get('max'):
        while ctx.measureText(s).width > o['max'] and sz > 5:
            sz *= 0.92
            ctx.font = '%spx %s' % (js_str(sz), f)
    ctx.textAlign = o.get('align') or 'center'
    ctx.textBaseline = 'middle'
    if o.get('stroke'):
        ctx.lineWidth = o.get('lw') or sz * 0.12
        ctx.strokeStyle = o['stroke']
        ctx.lineJoin = 'round'
        ctx.strokeText(s, x, y)
    if o.get('shadow'):
        ctx.fillStyle = o['shadow']
        ctx.fillText(s, x + sz * 0.04, y + sz * 0.05)
    ctx.fillStyle = color
    ctx.fillText(s, x, y)


def rr(ctx, x, y, w, h, r):
    ctx.beginPath()
    ctx.roundRect(x, y, w, h, r)


def lighten(hex_, a):
    c = THREE.Color(hex_)
    if a >= 0:
        c.lerp(THREE.Color(1, 1, 1), a)
    else:
        c.multiplyScalar(1 + a)
    return '#' + c.getHexString()


# printed plate: rounded plate with border + text
def drawPlate(text, o=None):
    o = o or {}
    bg, fg, border = o.get('bg', '#C9CED6'), o.get('fg', '#2A2231'), o.get('border', '#8F95A0')
    stripe, font, sub = o.get('stripe'), o.get('font', 'bungee'), o.get('sub')

    def draw(ctx, w, h, rand=None):
        g = ctx.createLinearGradient(0, 0, 0, h)
        g.addColorStop(0, lighten(bg, 0.25))
        g.addColorStop(0.5, bg)
        g.addColorStop(1, lighten(bg, -0.18))
        ctx.fillStyle = border
        ctx.fillRect(0, 0, w, h)
        rr(ctx, 3, 3, w - 6, h - 6, h * 0.22)
        ctx.fillStyle = g
        ctx.fill()
        if stripe:
            ctx.fillStyle = stripe
            ctx.fillRect(6, h * 0.72, w - 12, h * 0.1)
        txt(ctx, text, w / 2, h * 0.4 if sub else h * 0.52, h * (0.46 if sub else 0.58), font, fg, {'max': w * 0.86})
        if sub:
            txt(ctx, sub, w / 2, h * 0.78, h * 0.22, 'titan', fg, {'max': w * 0.8})
    return draw


def drawDial(labels, o=None):
    o = o or {}
    bg, fg, ring_ = o.get('bg', '#F4F1E8'), o.get('fg', '#2A2231'), o.get('ring')
    title, titleColor = o.get('title'), o.get('titleColor', '#E23B3B')
    span, font = o.get('span', 1.6), o.get('font', 'titan')

    def draw(ctx, w, h, rand=None):
        cx, cy, R = w / 2, h / 2, w / 2 - 2
        ctx.fillStyle = ring_ or lighten(bg, -0.25)
        ctx.beginPath()
        ctx.arc(cx, cy, R, 0, TAU)
        ctx.fill()
        ctx.fillStyle = bg
        ctx.beginPath()
        ctx.arc(cx, cy, R - 4, 0, TAU)
        ctx.fill()
        n = len(labels)
        for i in range(n):
            a = -math.pi * span / 2 + (i / (n - 1) if n > 1 else 0) * math.pi * span
            sx, sy = math.sin(a), -math.cos(a)
            ctx.strokeStyle = fg
            ctx.lineWidth = 2.5
            ctx.beginPath()
            ctx.moveTo(cx + sx * R * 0.84, cy + sy * R * 0.84)
            ctx.lineTo(cx + sx * R * 0.95, cy + sy * R * 0.95)
            ctx.stroke()
            if labels[i] != '':
                txt(ctx, str(labels[i]), cx + sx * R * 0.66, cy + sy * R * 0.66, w * (0.1 if n > 12 else 0.12),
                    font, fg)
        if title:
            txt(ctx, title, cx, cy + R * 0.62, w * 0.1, 'bungee', titleColor, {'max': R * 1.1})
    return draw


# cells [name, w, h, draw(ctx, w, h, rand)] — shelf-packed from y = 96 (rows 0-2 are swatches)
SPECS = []


def cell(name, w, h, draw):
    SPECS.append([name, w, h, draw])


def _cell_reel(ctx, w, h, rand=None):  # 2" quad / NAB aluminum reel flange with tape visible through windows
    cx, cy, R = w / 2, h / 2, w / 2 - 2
    g = ctx.createRadialGradient(cx - 30, cy - 40, 10, cx, cy, R)
    g.addColorStop(0, '#EEF1F5')
    g.addColorStop(0.6, '#BCC3CC')
    g.addColorStop(1, '#8E96A2')
    ctx.fillStyle = '#6E7684'
    ctx.beginPath()
    ctx.arc(cx, cy, R, 0, TAU)
    ctx.fill()
    ctx.fillStyle = g
    ctx.beginPath()
    ctx.arc(cx, cy, R - 5, 0, TAU)
    ctx.fill()
    for i in range(3):  # three windows showing the tape pack
        a = i / 3 * TAU - HP
        ctx.beginPath()
        ctx.arc(cx, cy, R * 0.82, a - 0.62, a + 0.62)
        ctx.arc(cx, cy, R * 0.34, a + 0.5, a - 0.5, True)
        ctx.closePath()
        tg = ctx.createRadialGradient(cx, cy, R * 0.3, cx, cy, R * 0.85)
        tg.addColorStop(0, '#2A1A12')
        tg.addColorStop(0.55, '#5A3A22')
        tg.addColorStop(1, '#3A2416')
        ctx.fillStyle = tg
        ctx.fill()
        ctx.strokeStyle = '#5E6674'
        ctx.lineWidth = 4
        ctx.stroke()
    r = 0.9
    while r > 0.3:
        ctx.strokeStyle = 'rgba(255,255,255,0.08)'
        ctx.lineWidth = 1
        ctx.beginPath()
        ctx.arc(cx, cy, R * r, 0, TAU)
        ctx.stroke()
        r -= 0.06
    ctx.fillStyle = '#9AA2AE'
    ctx.beginPath()
    ctx.arc(cx, cy, R * 0.26, 0, TAU)
    ctx.fill()
    ctx.fillStyle = '#4A5260'
    ctx.beginPath()
    ctx.arc(cx, cy, R * 0.12, 0, TAU)
    ctx.fill()
    for i in range(6):
        a = i / 6 * TAU
        ctx.fillStyle = '#6E7684'
        ctx.beginPath()
        ctx.arc(cx + math.cos(a) * R * 0.19, cy + math.sin(a) * R * 0.19, 3.5, 0, TAU)
        ctx.fill()


cell('reel', 256, 256, _cell_reel)


def _cell_slate(ctx, w, h, rand=None):  # clapperboard slate face
    ctx.fillStyle = '#26242C'
    ctx.fillRect(0, 0, w, h)
    ctx.strokeStyle = 'rgba(244,241,232,0.85)'
    ctx.lineWidth = 2.5

    def L_(x0, y0, x1, y1):
        ctx.beginPath()
        ctx.moveTo(x0, y0)
        ctx.lineTo(x1, y1)
        ctx.stroke()
    L_(8, 48, w - 8, 48)
    L_(8, 96, w - 8, 96)
    L_(8, 144, w - 8, 144)
    L_(w / 3, 96, w / 3, 144)
    L_(2 * w / 3, 96, 2 * w / 3, 144)
    txt(ctx, 'WZTV 13', w / 2, 26, 30, 'bungee', '#F4F1E8')
    txt(ctx, 'PROD.', 30, 62, 11, 'titan', '#CFCAC0')
    txt(ctx, 'Spooktacular', w / 2 + 14, 74, 26, 'shrik', '#F4F1E8', {'max': 190})
    txt(ctx, 'ROLL', 26, 106, 10, 'titan', '#CFCAC0')
    txt(ctx, 'SCENE', w / 3 + 22, 106, 10, 'titan', '#CFCAC0')
    txt(ctx, 'TAKE', 2 * w / 3 + 20, 106, 10, 'titan', '#CFCAC0')
    txt(ctx, '13', w / 6, 124, 26, 'shrik', '#F4F1E8')
    txt(ctx, '1', w / 2, 124, 26, 'shrik', '#F4F1E8')
    txt(ctx, '3', 5 * w / 6, 124, 26, 'shrik', '#FFB0A0')
    txt(ctx, 'DIR. B. VON STATIC', w / 2, 158, 14, 'titan', '#F4F1E8', {'max': 230})
    txt(ctx, '10 · 31 · 77', w / 2, 178, 14, 'titan', '#CFCAC0')
    ctx.fillStyle = 'rgba(255,255,255,0.05)'
    for i in range(40):
        ctx.fillRect((i * 97) % w, (i * 53) % h, 30, 2)


cell('slate', 256, 192, _cell_slate)


def _cell_script(ctx, w, h, rand=None):  # teleprompter text (lit, on black: additive on the glass)
    ctx.fillStyle = '#000'
    ctx.fillRect(0, 0, w, h)
    lines = ['GOOD EVENING,', 'AND WELCOME', 'BACK TO THE', '13-HOUR', 'SPOOKTACULAR!', '(SMILE)']
    for i, s in enumerate(lines):
        txt(ctx, s, w / 2, 20 + i * 30, 27, 'vt', '#FFD23A' if i == 5 else '#F4F1E8', {'max': w - 16})


cell('script', 256, 192, _cell_script)


def _cell_onair(ctx, w, h, rand=None):
    g = ctx.createRadialGradient(w / 2, h / 2, 10, w / 2, h / 2, w * 0.55)
    g.addColorStop(0, '#FF5A48')
    g.addColorStop(0.7, '#D8231E')
    g.addColorStop(1, '#8A1010')
    ctx.fillStyle = g
    ctx.fillRect(0, 0, w, h)
    txt(ctx, 'ON AIR', w / 2, h * 0.54, 62, 'bungee', '#FFF1E0', {'max': w * 0.88, 'shadow': 'rgba(90,0,0,0.5)'})


cell('onair', 256, 96, _cell_onair)


def _cell_applause(ctx, w, h, rand=None):
    g = ctx.createLinearGradient(0, 0, 0, h)
    g.addColorStop(0, '#C8283A')
    g.addColorStop(1, '#8A1428')
    ctx.fillStyle = g
    ctx.fillRect(0, 0, w, h)
    txt(ctx, 'APPLAUSE', w / 2, h * 0.54, 60, 'bungee', '#FFF4D8', {'max': w * 0.84, 'shadow': 'rgba(60,0,20,0.55)'})


cell('applause', 384, 96, _cell_applause)


def _cell_vu(ctx, w, h, rand=None):  # backlit VU meter face (needle is 3D)
    g = ctx.createLinearGradient(0, 0, 0, h)
    g.addColorStop(0, '#FFF6CC')
    g.addColorStop(1, '#F0D68A')
    ctx.fillStyle = g
    ctx.fillRect(0, 0, w, h)
    cx, cy, R = w / 2, h * 1.02, h * 0.8
    T = [[-20, 0], [-10, 0.28], [-7, 0.4], [-5, 0.5], [-3, 0.6], [-2, 0.66], [-1, 0.72], [0, 0.78], [1, 0.85],
         [2, 0.92], [3, 1]]

    def ang(t):
        return -HP - 0.8 + t * 1.6
    ctx.lineWidth = 3
    ctx.strokeStyle = '#2A2231'
    ctx.beginPath()
    ctx.arc(cx, cy, R, ang(0), ang(0.78))
    ctx.stroke()
    ctx.lineWidth = 7
    ctx.strokeStyle = '#E23B3B'
    ctx.beginPath()
    ctx.arc(cx, cy, R + 2, ang(0.78), ang(1))
    ctx.stroke()
    for db, t in T:
        a = ang(t)
        c, s = math.cos(a), math.sin(a)
        ctx.strokeStyle = '#C8201E' if t >= 0.78 else '#2A2231'
        ctx.lineWidth = 2.5
        ctx.beginPath()
        ctx.moveTo(cx + c * R, cy + s * R)
        ctx.lineTo(cx + c * (R + 12), cy + s * (R + 12))
        ctx.stroke()
        if db in [-20, -10, -5, -3, 0, 3]:
            txt(ctx, str(abs(db)), cx + c * (R + 24), cy + s * (R + 24), 15, 'titan',
                '#C8201E' if t >= 0.78 else '#2A2231')
    txt(ctx, 'VU', cx, h * 0.7, 30, 'bungee', '#2A2231')
    ctx.strokeStyle = '#8A7040'
    ctx.lineWidth = 4
    ctx.strokeRect(2, 2, w - 4, h - 4)


cell('vu', 256, 128, _cell_vu)


def _cell_vuBar(ctx, w, h, rand=None):  # LED bar graph (lit)
    ctx.fillStyle = '#140E18'
    ctx.fillRect(0, 0, w, h)
    for i in range(10):
        y = h - 12 - i * 11.5
        ctx.fillStyle = '#FF3B30' if i >= 8 else '#FFB347' if i >= 6 else '#52E04A'
        ctx.globalAlpha = 1 if i < 7 else 0.35
        rr(ctx, 14, y - 4, w - 28, 8, 2)
        ctx.fill()
    ctx.globalAlpha = 1


cell('vuBar', 64, 128, _cell_vuBar)
cell('dial10', 128, 128, drawDial(['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10'],
                                  {'bg': '#2E2836', 'fg': '#F4F1E8', 'ring': '#15101A', 'span': 1.55}))
cell('dialCh', 128, 128, drawDial(['2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12', '13'], {'title': 'VHF'}))
cell('dialUhf', 128, 128, drawDial(['14', '', '30', '', '45', '', '60', '', '83'],
                                   {'title': 'UHF', 'titleColor': '#2F5BD3'}))
cell('dialTrk', 128, 128, drawDial(['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12'],
                                   {'title': 'TRACK', 'bg': '#F6E7C8', 'span': 1.8}))


def _cell_logo13(ctx, w, h, rand=None):  # WZTV "13" disc: white 13 in a blue disc with a red ring
    cx, cy = w / 2, h / 2
    ctx.fillStyle = '#F4F1E8'
    ctx.beginPath()
    ctx.arc(cx, cy, 63, 0, TAU)
    ctx.fill()
    ctx.fillStyle = '#E23B3B'
    ctx.beginPath()
    ctx.arc(cx, cy, 58, 0, TAU)
    ctx.fill()
    ctx.fillStyle = '#2F5BD3'
    ctx.beginPath()
    ctx.arc(cx, cy, 47, 0, TAU)
    ctx.fill()
    txt(ctx, '13', cx + 1, cy + 4, 56, 'bungee', '#F4F1E8', {'shadow': 'rgba(20,20,80,0.45)'})


cell('logo13', 128, 128, _cell_logo13)


def _cell_grille(ctx, w, h, rand=None):
    ctx.fillStyle = '#3A3444'
    ctx.fillRect(0, 0, w, h)
    for y in range(9):
        for x in range(9):
            ctx.fillStyle = '#120C16'
            ctx.beginPath()
            ctx.arc(10 + x * 13.5, 10 + y * 13.5, 4.2, 0, TAU)
            ctx.fill()
            ctx.fillStyle = 'rgba(255,255,255,0.12)'
            ctx.beginPath()
            ctx.arc(10 + x * 13.5, 11.5 + y * 13.5, 4.2, 0.2, 2.9)
            ctx.fill()


cell('grille', 128, 128, _cell_grille)


def _cell_vent(ctx, w, h, rand=None):
    ctx.fillStyle = '#4A4556'
    ctx.fillRect(0, 0, w, h)
    for i in range(7):
        rr(ctx, 10, 9 + i * 16.5, w - 20, 8, 4)
        ctx.fillStyle = '#120C16'
        ctx.fill()
        ctx.fillStyle = 'rgba(255,255,255,0.14)'
        ctx.fillRect(14, 18 + i * 16.5, w - 28, 1.5)


cell('vent', 128, 128, _cell_vent)


def _cell_fabric(ctx, w, h, rand):  # TV speaker cloth: brown with gold thread
    ctx.fillStyle = '#5A3A22'
    ctx.fillRect(0, 0, w, h)
    y = 0
    while y < h:
        ctx.fillStyle = '#6A4630' if y % 8 else '#4A2E1A'
        ctx.fillRect(0, y, w, 2)
        y += 4
    x = 0
    while x < w:
        ctx.fillStyle = 'rgba(232,169,46,0.35)'
        ctx.fillRect(x, 0, 1.5, h)
        x += 4
    for i in range(300):
        ctx.fillStyle = 'rgba(255,220,150,0.18)' if rand() < 0.5 else 'rgba(0,0,0,0.15)'
        ctx.fillRect(rand() * w, rand() * h, 2, 1)


cell('fabric', 128, 128, _cell_fabric)


def _cell_reelLabel(ctx, w, h, rand=None):
    ctx.fillStyle = '#F7F2E4'
    ctx.beginPath()
    ctx.arc(w / 2, h / 2, 62, 0, TAU)
    ctx.fill()
    ctx.strokeStyle = '#2F5BD3'
    ctx.lineWidth = 5
    ctx.beginPath()
    ctx.arc(w / 2, h / 2, 56, 0, TAU)
    ctx.stroke()
    txt(ctx, '13', w / 2, h / 2 + 2, 52, 'shrik', '#D8231E')
    txt(ctx, 'SIGN-OFF', w / 2, h * 0.82, 13, 'titan', '#2A2231')
    ctx.fillStyle = '#2A2231'
    ctx.beginPath()
    ctx.arc(w / 2, h / 2, 9, 0, TAU)
    ctx.fill()


cell('reelLabel', 128, 128, _cell_reelLabel)


def _cell_caseTag(ctx, w, h, rand=None):  # stuck-on paper tag "FRAGILE" + arrows
    ctx.fillStyle = '#F3EEDF'
    rr(ctx, 2, 2, w - 4, h - 4, 10)
    ctx.fill()
    ctx.strokeStyle = '#E23B3B'
    ctx.lineWidth = 5
    rr(ctx, 8, 8, w - 16, h - 16, 8)
    ctx.stroke()
    txt(ctx, 'FRAGILE', w / 2, 30, 22, 'bungee', '#E23B3B', {'max': w - 24})
    ctx.fillStyle = '#2A2231'
    for x in [w * 0.34, w * 0.66]:
        ctx.beginPath()
        ctx.moveTo(x, 50)
        ctx.lineTo(x + 16, 72)
        ctx.lineTo(x + 6, 72)
        ctx.lineTo(x + 6, 100)
        ctx.lineTo(x - 6, 100)
        ctx.lineTo(x - 6, 72)
        ctx.lineTo(x - 16, 72)
        ctx.closePath()
        ctx.fill()
    txt(ctx, 'THIS SIDE UP', w / 2, 112, 12, 'titan', '#2A2231')


cell('caseTag', 128, 128, _cell_caseTag)


def _cell_digits(ctx, w, h, rand=None):
    ctx.fillStyle = '#0C0A10'
    ctx.fillRect(0, 0, w, h)
    txt(ctx, '00:13:07:13', w / 2, h / 2 + 1, 28, 'vt', '#7CFF6A', {'max': w - 8})


cell('digits', 128, 32, _cell_digits)


def _cell_keys(ctx, w, h, rand=None):
    ctx.fillStyle = '#2E2836'
    ctx.fillRect(0, 0, w, h)
    for i, s in enumerate(['REW', 'PLAY', 'STOP', 'FF', 'REC']):
        txt(ctx, s, 26 + i * 51, h / 2 + 1, 14, 'titan', '#FF6A5A' if i == 4 else '#F4F1E8')


cell('keys', 256, 32, _cell_keys)


def _cell_bus(ctx, w, h, rand=None):
    ctx.fillStyle = '#2E2836'
    ctx.fillRect(0, 0, w, h)
    for i, s in enumerate(['CAM1', 'CAM2', 'CAM3', 'CAM4', 'VTR1', 'VTR2', 'NET', 'BARS']):
        txt(ctx, s, 16 + i * 32, h / 2 + 1, 10, 'titan', '#E8E2D4')


cell('bus', 256, 32, _cell_bus)


def _cell_hv(ctx, w, h, rand=None):
    ctx.fillStyle = '#F4C81E'
    ctx.fillRect(0, 0, w, h)
    ctx.fillStyle = '#2A2231'
    x = -h
    while x < w:
        ctx.beginPath()
        ctx.moveTo(x, h)
        ctx.lineTo(x + 14, h)
        ctx.lineTo(x + 14 + h * 0.5, 0)
        ctx.lineTo(x + h * 0.5, 0)
        ctx.closePath()
        ctx.fill()
        x += 28
    ctx.fillStyle = '#F4C81E'
    rr(ctx, 30, 9, w - 60, h - 18, 6)
    ctx.fill()
    txt(ctx, 'HIGH VOLTAGE', w / 2, h / 2 + 1, 20, 'bungee', '#2A2231', {'max': w - 70})


cell('hv', 256, 48, _cell_hv)


def _cell_stripes(ctx, w, h, rand=None):
    ctx.fillStyle = '#F4F1E8'
    ctx.fillRect(0, 0, w, h)
    ctx.fillStyle = '#26242C'
    x = -h
    while x < w + h:
        ctx.beginPath()
        ctx.moveTo(x, h)
        ctx.lineTo(x + 22, h)
        ctx.lineTo(x + 22 + h, 0)
        ctx.lineTo(x + h, 0)
        ctx.closePath()
        ctx.fill()
        x += 44


cell('stripes', 256, 32, _cell_stripes)


def _cell_jacks(ctx, w, h, rand=None):  # patch bay jack row
    ctx.fillStyle = '#35303E'
    ctx.fillRect(0, 0, w, h)
    ctx.fillStyle = '#F0EBDD'
    ctx.fillRect(4, h / 2 - 6, w - 8, 12)
    for i in range(16):
        txt(ctx, str(i + 1), 10 + i * 15.6, h / 2, 8, 'titan', '#2A2231')
    for yy in [13, h - 13]:
        for i in range(16):
            x = 10 + i * 15.6
            ctx.fillStyle = '#C8CDD6'
            ctx.beginPath()
            ctx.arc(x, yy, 6, 0, TAU)
            ctx.fill()
            ctx.fillStyle = '#0E0A12'
            ctx.beginPath()
            ctx.arc(x, yy, 3, 0, TAU)
            ctx.fill()


cell('jacks', 256, 64, _cell_jacks)


def _cell_meterRound(ctx, w, h, rand=None):  # round panel meter (black face)
    ctx.fillStyle = '#1A1620'
    ctx.beginPath()
    ctx.arc(w / 2, h / 2, 62, 0, TAU)
    ctx.fill()
    ctx.strokeStyle = '#F4F1E8'
    ctx.lineWidth = 2
    for i in range(11):
        a = -2.3 + i / 10 * 1.6 * 1.3
        ctx.beginPath()
        ctx.moveTo(64 + math.cos(a) * 44, 70 + math.sin(a) * 44)
        ctx.lineTo(64 + math.cos(a) * 52, 70 + math.sin(a) * 52)
        ctx.stroke()
    ctx.strokeStyle = '#52E04A'
    ctx.lineWidth = 5
    ctx.beginPath()
    ctx.arc(64, 70, 48, -1.3, -0.4)
    ctx.stroke()
    txt(ctx, 'mA', 64, 92, 16, 'titan', '#F4F1E8')


cell('meterRound', 128, 128, _cell_meterRound)


def _cell_tape(ctx, w, h, rand=None):  # gaffer tape strip
    ctx.fillStyle = '#9EA4AE'
    ctx.fillRect(0, 0, w, h)
    for i in range(40):
        ctx.fillStyle = 'rgba(255,255,255,0.12)' if i % 2 else 'rgba(0,0,0,0.08)'
        ctx.fillRect(0, i * 1.6, w, 0.8)
    ctx.fillStyle = '#8A909A'
    x = 0
    while x < w:
        ctx.fillRect(x, 0, 3, 3)
        ctx.fillRect(x + 3, h - 3, 3, 3)
        x += 6


cell('tape', 128, 64, _cell_tape)
# small labels (white on charcoal) and nameplates
LABELS = ['LOBBY', 'NEWS', 'STUDIO A', 'STUDIO B', 'PGM', 'PVW', 'NET', 'VTR', 'CAM 1', 'CAM 2', 'AUDIO', 'SYNC',
          'LINE', 'AIR']
for _t in LABELS:
    cell('lbl_' + _t, 128, 32, drawPlate(_t, {'bg': '#2E2836', 'fg': '#F4F1E8', 'border': '#15101A', 'font': 'titan'}))
cell('pl_QUADRAMAX', 256, 48, drawPlate('QUADRAMAX', {'bg': '#C9CED6', 'fg': '#22367A', 'stripe': '#E3662B'}))
cell('pl_VIDICAM', 256, 48, drawPlate('VIDICAM', {'bg': '#C9CED6', 'fg': '#2A2231', 'stripe': '#2F5BD3'}))
cell('pl_KINETRON', 256, 48, drawPlate('KINETRON', {'bg': '#2E2836', 'fg': '#E8E2D4', 'border': '#15101A'}))
cell('pl_AUDIOLUX', 256, 48, drawPlate('AUDIOLUX', {'bg': '#D8C8A0', 'fg': '#5A3A22', 'border': '#8A6A40',
                                                    'font': 'titan'}))
cell('pl_ZENOLUX', 256, 48, drawPlate('ZENOLUX', {'bg': '#C9CED6', 'fg': '#8E2A2E', 'font': 'titan'}))
cell('pl_WZTV', 256, 48, drawPlate('WZTV 13', {'bg': '#2F5BD3', 'fg': '#F4F1E8', 'border': '#E23B3B'}))
cell('pl_PROPERTY', 256, 48, drawPlate('PROPERTY OF WZTV-13', {'bg': '#F4C81E', 'fg': '#2A2231', 'border': '#2A2231',
                                                               'font': 'titan'}))
cell('pl_STUDIOA', 256, 48, drawPlate('STUDIO A', {'bg': '#F3EEDF', 'fg': '#2A2231', 'border': '#E3662B',
                                                   'font': 'bungee'}))
cell('pl_MASTER', 256, 48, drawPlate('MASTER CONTROL', {'bg': '#2E2836', 'fg': '#FFB347', 'border': '#15101A',
                                                        'font': 'bungee'}))
cell('pl_TELESCRIPT', 256, 48, drawPlate('TELE·Q', {'bg': '#C9CED6', 'fg': '#2A2231', 'stripe': '#E23B3B'}))
cell('pl_FISHER', 256, 48, drawPlate('BOOMCO', {'bg': '#C9CED6', 'fg': '#2A2231', 'stripe': '#E8A92E'}))
cell('pl_LUMEX', 256, 48, drawPlate('LUMEX', {'bg': '#2E2836', 'fg': '#FFC98A', 'border': '#15101A'}))


def _num_cell(i):
    def draw(ctx, w, h, rand=None):
        ctx.fillStyle = '#2A2231'
        rr(ctx, 1, 1, w - 2, h - 2, 10)
        ctx.fill()
        txt(ctx, str(i), w / 2, h / 2 + 3, 48, 'bungee', '#F4F1E8')
    return draw


for _i in range(1, 5):
    cell('num' + str(_i), 64, 64, _num_cell(_i))
for _i in range(1, 4):
    cell('vtr' + str(_i), 128, 48, drawPlate('VTR ' + str(_i), {'bg': '#2E2836', 'fg': '#FFE14A', 'border': '#15101A'}))

CELLS = {}


def _pack():
    order = sorted(SPECS, key=lambda s: -s[2])   # stable, like Array.prototype.sort
    x, y, rh = 0, 3 * SWS, 0
    for n, w, h, _d in order:
        if x + w > AS:
            x = 0
            y += rh
            rh = 0
        CELLS[n] = [x, y, w, h]
        x += w
        rh = max(rh, h)
    if y + rh > AS:
        print('[props/broadcast] atlas overflow', y + rh)


_pack()


def atlasTex():
    def draw(ctx, W, H, rand):
        ctx.fillStyle = '#7A7480'
        ctx.fillRect(0, 0, W, H)
        for k in SWUV:
            _u, _v, x, y = SWUV[k]
            ctx.fillStyle = SW[k]
            ctx.fillRect(x, y, SWS, SWS)
        for k in LITUV:
            _u, _v, x, y = LITUV[k]
            ctx.fillStyle = LIT[k]
            ctx.fillRect(x, y, SWS, SWS)
        for n, _w, _h, dr in SPECS:
            x, y, w, h = CELLS[n]
            ctx.save()
            ctx.beginPath()
            ctx.rect(x, y, w, h)
            ctx.clip()
            ctx.translate(x, y)
            dr(ctx, w, h, rand)
            ctx.restore()
    return K.tex.canvas('bc_atlas_2', AS, AS, draw, {'repeat': False, 'fonts': True})


# ---- UV helpers (all return new geometry)
def fillUV(geo, u, v):
    g = geo.clone()
    n = g.attributes.position.count
    uv = np.empty((n, 2))
    uv[:, 0] = u
    uv[:, 1] = v
    g.setAttribute('uv', THREE.BufferAttribute(uv, 2))
    return g


def sw(geo, name):
    s = SWUV.get(name)
    if not s:
        raise KeyError('[bc] swatch %s' % name)
    return fillUV(geo, s[0], s[1])


def lw(geo, name):
    s = LITUV.get(name)
    if not s:
        raise KeyError('[bc] lit %s' % name)
    return fillUV(geo, s[0], s[1])


def cu(geo, name, inset=1.5):
    c = CELLS.get(name)
    if not c:
        raise KeyError('[bc] cell %s' % name)
    x, y, w, h = c
    g = geo.clone()
    if not g.attributes.uv:
        g.setAttribute('uv', THREE.BufferAttribute(np.zeros((g.attributes.position.count, 2)), 2))
    return K.uvRect(g, (x + inset) / AS, 1 - (y + h - inset) / AS, (x + w - inset) / AS, 1 - (y + inset) / AS)


# flat decal facing -z (front), w x h meters, showing an atlas cell
def decal(name, w, h):
    return cu(THREE.PlaneGeometry(w, h).rotateY(math.pi), name)


def discDecal(name, r, seg=24):
    return cu(THREE.CircleGeometry(r, seg).rotateY(math.pi), name)


# ---- shared materials (cached by the engine per params)
def mats(game):
    at = atlasTex()
    return JSObj(
        pl=K.mat(game, 'plastic', '#ffffff', {'map': at}),                 # paletted glossy plastic / enamel
        mt=K.mat(game, 'paint', '#ffffff', {'map': at}),                   # paletted matte (rubber, crinkle paint)
        me=K.mat(game, 'metal', '#ffffff', {'map': at}),                   # paletted painted metal
        lit=K.glow(game, '#ffffff', 1.7, {'map': at}),                     # lit lamps / buttons / LEDs / signs
        soft=K.glow(game, '#ffffff', 0.86, {'map': at}),                   # backlit meter faces / reflectors
        sign=K.glow(game, '#ffffff', 1.12, {'map': at}),                   # lit sign faces (letters bloom)
        dim=K.mat(game, 'plastic', '#6A6068', {'map': at}),                # unlit lamp (same UVs as lit)
        ch=K.mat(game, 'chrome', '#9CA4AE'),
        glass=K.mat(game, 'crt', '#232838'),
    )


def woodMat(game, base=None):
    base = PAL.walnut if base is None else base
    return K.mat(game, 'walnut', '#ffffff', {'map': K.tex.wood(base, {'dark': 0.42})})


def brushedMat(game, base='#C4CAD2'):
    return K.mat(game, 'metal', '#ffffff', {'map': K.tex.brushed(base)})


# ================================================================================================= GEOMETRY
# Chamfered keycap: top at y = h, open bottom, flat faces (18 tris). Buttons, keys, switch caps.
_kc = {}


def keycap(w, d, h, c=0.004):
    key = '%s|%s|%s|%s' % (js_str(w), js_str(d), js_str(h), js_str(c))
    if key in _kc:
        return _kc[key]
    hw, hd = w / 2, d / 2
    iw, id_, hc = hw - c, hd - c, h - c
    T = [[-iw, h, -id_], [iw, h, -id_], [iw, h, id_], [-iw, h, id_]]
    S = [[-hw, hc, -hd], [hw, hc, -hd], [hw, hc, hd], [-hw, hc, hd]]
    B = [[-hw, 0, -hd], [hw, 0, -hd], [hw, 0, hd], [-hw, 0, hd]]
    tris = []

    def quad(a, b, c2, d2):
        tris.extend([a, b, c2, a, c2, d2])
    quad(T[0], T[3], T[2], T[1])  # top (+y)
    for i in range(4):
        j = (i + 1) % 4
        quad(T[i], T[j], S[j], S[i])
        quad(S[i], S[j], B[j], B[i])
    pos = [v for p in tris for v in p]
    g = THREE.BufferGeometry()
    g.setAttribute('position', THREE.Float32BufferAttribute(pos, 3))
    g.setAttribute('uv', THREE.BufferAttribute(np.zeros((len(tris), 2)), 2))
    g.computeVertexNormals()
    _kc[key] = g
    return g


# cheap closed cylinder, base at y = 0 (tiny parts: LEDs, screws, pins)
def lowCyl(r, h, seg=10, rb=None):
    rb = r if rb is None else rb
    return THREE.CylinderGeometry(r, rb, h, seg, 1).translate(0, h / 2, 0)


def lowSphere(r, ws=8, hs=6):
    return THREE.SphereGeometry(r, ws, hs)


# 1-step-rounded lathe (cheaper than the kit default) and bevelled cylinder, base at y = 0
def L(p, round_=0, seg=16):
    return K.lathe(p, {'round': round_, 'seg': seg, 'steps': 1})


def bcyl(rt, rb, h, bevel=0.005, seg=14):
    return L([[0, 0], [rb, 0], [rt, h], [0, h]], bevel, seg)


# Chamfered box (44 tris, flat facets), centered: small and medium hard parts.
_cb = {}


def cbox(w, h, d, c=0.004):
    c = max(1e-4, min(c, w / 2 - 1e-4, h / 2 - 1e-4, d / 2 - 1e-4))
    key = '%s|%s|%s|%s' % (js_str(w), js_str(h), js_str(d), js_str(c))
    g = _cb.get(key)
    if g is None:
        hx, hy, hz = w / 2, h / 2, d / 2
        pts = []
        for sx in (-1, 1):
            for sy in (-1, 1):
                for sz in (-1, 1):
                    pts.extend([THREE.Vector3(sx * hx, sy * (hy - c), sz * (hz - c)),
                                THREE.Vector3(sx * (hx - c), sy * hy, sz * (hz - c)),
                                THREE.Vector3(sx * (hx - c), sy * (hy - c), sz * hz)])
        g = THREE.ConvexGeometry(pts)
        g.setAttribute('uv', THREE.BufferAttribute(np.zeros((g.attributes.position.count, 2)), 2))
        _cb[key] = g
    return g


def ring(r, n, y=0):
    pts = []
    for i in range(n):
        a = (i / n) * TAU
        pts.append([math.cos(a) * r, y, math.sin(a) * r])
    return pts


# rounded-rect loop in the XY plane (for trims around faces)
def rectLoopXY(w, h, r, steps=3):
    return [[x, z, 0] for x, _y, z in K.roundRectPath(w, h, r, 0, steps)]


# bevelled frame (ring) in the XY plane, depth along z: outer w x h, border b
def frame(w, h, b, depth, r=0.03, ri=None, o=None):
    o = o or {}
    s = K.roundRect(w, h, r)
    s.holes.append(THREE.Path(K.roundRect(w - 2 * b, h - 2 * b, nn(ri, max(0.004, r - b * 0.6))).getPoints(
        nn(o.get('holeSeg'), 2 if o.get('lite') else 4))))
    # bevel must stay well under half the border or the caps self-intersect and fill the opening
    return K.extrude(s, depth, {'bevel': min(nn(o.get('bevel'), 0.008), depth * 0.4, b * 0.35), 'bevelSeg': 1,
                                'curveSeg': nn(o.get('curveSeg'), 2 if o.get('lite') else 4)})


# mesh oriented from a to b (for cylinders built along +y from y = 0)
def along(geo, mat, a, b):
    va, vb = THREE.Vector3(*a), THREE.Vector3(*b)
    ln = va.distanceTo(vb)
    me = K.m(geo(ln), mat)
    me.position.copy(va)
    me.quaternion.setFromUnitVectors(UP, vb.clone().sub(va).normalize())
    return me


# knob: lathe body with a pointer, facing -z; returns meshes array positioned at p (face plane z)
def knob(M, r, p, o=None):
    o = o or {}
    color, cap = o.get('color', 'ink'), o.get('cap')
    depth = o['depth'] if 'depth' in o and o['depth'] is not None else r * 0.9
    skirt = o.get('skirt', True)
    rot, mat_ = o.get('rot', 0.6), o.get('mat', 'pl')
    seg = o['seg'] if o.get('seg') is not None else (12 if skirt else 10)
    pointer = o.get('pointer', True)
    prof = [[0, 0], [r * 1.2, 0], [r * 1.2, depth * 0.22], [r * 0.95, depth * 0.34], [r * 0.9, depth * 0.88],
            [r * 0.72, depth], [0, depth]] if skirt else \
        [[0, 0], [r, 0], [r * 0.96, depth * 0.84], [r * 0.74, depth], [0, depth]]
    out = []
    out.append(K.m(sw(L(prof, 0, seg), color), M[mat_], {'pos': p, 'rot': [-HP, 0, 0]}))
    if cap:
        out.append(K.m(sw(lowCyl(r * 0.7, 0.003, seg), cap), M.me, {'pos': [p[0], p[1], p[2] - depth - 0.001],
                                                                     'rot': [-HP, 0, 0]}))
    if not pointer:
        return out
    ptr = K.m(sw(cbox(r * 0.22, r * 0.75, 0.004, 0.0012), 'white'), M.pl, {})
    ptr.position.set(p[0] + math.sin(rot) * r * 0.45, p[1] + math.cos(rot) * r * 0.45, p[2] - depth - 0.0015)
    ptr.rotation.z = -rot
    out.append(ptr)
    return out


# caster wheel assembly (swivel fork + rubber wheel), contact at y = 0; returns Group
def caster(M, r=0.04, color='charcoal'):
    c = THREE.Group()
    c.add(K.m(sw(L([[0, -r * 0.45], [r * 0.75, -r * 0.45], [r, -r * 0.15], [r, r * 0.15], [r * 0.75, r * 0.45],
                    [0, r * 0.45]], 0, 12), 'rubber'), M.mt, {'pos': [0, r, 0], 'rot': [0, 0, HP]}))
    c.add(K.m(sw(cbox(r * 1.35, r * 0.28, r * 1.05, r * 0.1), color), M.pl, {'pos': [0, r * 1.95, -r * 0.12]}))
    for s in (-1, 1):
        c.add(K.m(sw(cbox(r * 0.2, r * 1.25, r * 0.85, r * 0.07), color), M.pl,
                  {'pos': [s * r * 0.6, r * 1.35, -r * 0.15]}))
    c.add(K.m(sw(lowCyl(r * 0.3, r * 0.6, 8), 'silver'), M.pl, {'pos': [0, r * 2, 0]}))
    return c


# telescoping rabbit ears (V antenna) on a swivel ball; returns Group (noMerge part)
def rabbitEars(M, len_=0.5, spread=0.55, lean=0.2):
    ant = THREE.Group()
    ant.userData.noMerge = True
    ant.add(K.m(sw(L([[0, 0], [0.045, 0], [0.046, 0.012], [0.03, 0.03], [0.012, 0.04], [0, 0.042]], 0, 12), 'ink'),
                M.pl))
    for s in (-1, 1):
        dr = THREE.Vector3(s * spread, 1, lean).normalize()
        segs = [[0.0055, len_ * 0.38], [0.0042, len_ * 0.34], [0.003, len_ * 0.32]]
        d = 0.03
        for r, ln in segs:
            rod = K.m(lowCyl(r, ln, 6), M.ch)
            rod.position.copy(dr).multiplyScalar(d).add(THREE.Vector3(0, 0.02, 0))
            rod.quaternion.setFromUnitVectors(UP, dr)
            ant.add(rod)
            d += ln - 0.008
        ant.add(K.m(lowSphere(0.009, 6, 4), M.ch,
                    {'pos': dr.clone().multiplyScalar(d + 0.004).add(THREE.Vector3(0, 0.02, 0)).toArray()}))
    return ant


# CRT screen (engine CRT material, preview card; ScreenManager owns it in game). Faces -z, domed.
# Cheaper than K.screen (8x6 grid by default). o: { card, group, id, dome, bright, seg:[x,y] }
def scr(game, w, h, o=None):
    o = o or {}
    sx, sy = nn(o.get('seg'), [8, 6])
    dome = nn(o.get('dome'), min(w, h) * 0.05)
    g = THREE.PlaneGeometry(w, h, sx, sy)
    pos = g.attributes.position
    for i in range(pos.count):
        x, y = (pos.getX(i) / w) * 2, (pos.getY(i) / h) * 2
        pos.setZ(i, dome * (1 - x * x * 0.5 - y * y * 0.5))
    g.computeVertexNormals()
    g.rotateY(math.pi)
    # (JS: o.card === null -> no card; every caller passes a card id or undefined -> 'station_id')
    card = getCard(nn(o.get('card'), 'station_id'))
    mt = game.mats.screen(card, {'w': w, 'h': h, 'bulge': 0, 'bright': nn(o.get('bright'), 0.85)})
    mesh = THREE.Mesh(g, mt)
    mesh.name = 'screen'
    mesh.userData.noMerge = True
    mesh.userData.screenGroup = nn(o.get('group'), 'scr_decor')
    if o.get('id'):
        mesh.userData.screenId = o['id']
    mesh.castShadow = False
    return mesh


# finish + per-group merges for animated parts + screen ids + stats
PROFILE = False   # JS: ?bcprof=1 (per-prop tri breakdown log + debug props)


def done(game, g, o=None):
    o = o or {}
    if PROFILE:
        rows = []
        g.updateMatrixWorld(True)

        def prof(m):
            if not getattr(m, 'isMesh', False):
                return
            gg = m.geometry
            t = (gg.index.count if gg.index is not None else gg.attributes.position.count) / 3
            p = THREE.Vector3().setFromMatrixPosition(m.matrixWorld)
            rows.append([t, gg.type, ','.join(js_to_fixed(v, 2) for v in p.toArray())])
        g.traverse(prof)
        rows.sort(key=lambda r: -r[0])
        tot = sum(r[0] for r in rows)
        print('[bcprof] %s total %s in %d meshes :: ' % (g.userData.id, js_str(tot), len(rows)) +
              ' | '.join('%s %s @%s' % (js_str(r[0]), r[1], r[2]) for r in rows[:30]))
    K.finish(game, g, o.get('finish') or {})
    for p in o.get('mergeParts') or []:
        if p:
            K.merge(p)
    for s in g.userData.screens:
        if s.mesh.userData.screenId:
            s.id = s.mesh.userData.screenId

    # every mesh keeps a color attribute so lamps can swap lit <-> dim (vertexColors) materials at runtime
    def addcol(ob):
        if getattr(ob, 'isMesh', False) and not ob.geometry.attributes.color and ob.material.type != 'ShaderMaterial':
            ob.geometry = ob.geometry.clone()
            ob.geometry.setAttribute('color', THREE.BufferAttribute(
                np.ones((ob.geometry.attributes.position.count, 3)), 3))
    g.traverse(addcol)
    g.userData.stats = K.stats(g)
    return g


# A standalone CRT monitor unit (metal case, face plate, bevelled bezel, screen, control strip). Group, base at
# y = 0, centered, front -z. Returns { group, screen, h, d }.
# o: { w, h, d, case, face, bezel, screen:[sw,sh], sy (screen center offset y), card, group, id, knobs=4, ears,
#      handles, plate, tally, tilt }
def monitorUnit(game, M, o=None):
    o = o or {}
    w, h, d = nn(o.get('w'), 0.48), nn(o.get('h'), 0.38), nn(o.get('d'), 0.42)
    caseC, faceC, bezC = nn(o.get('case'), 'charcoal'), nn(o.get('face'), 'putty'), nn(o.get('bezel'), 'ink')
    grp = THREE.Group()
    fz = -d / 2
    grp.add(K.m(sw(K.box(w, h, d * 0.62, min(0.035, h * 0.12)), caseC), M.pl, {'pos': [0, h / 2, fz + d * 0.31]}))
    grp.add(K.m(sw(K.taper(K.box(w * 0.86, h * 0.84, d * 0.42, 0.035), {'axis': 'z', 'k': 0.62}), caseC), M.pl,
                {'pos': [0, h / 2 + 0.005, fz + d * 0.62 + d * 0.19 - 0.01]}))
    # face plate
    grp.add(K.m(sw(K.box(w - 0.014, h - 0.014, 0.024, min(0.028, h * 0.1)), faceC), M.pl,
                {'pos': [0, h / 2, fz - 0.004]}))
    sW, sH = nn(o.get('screen'), [w * 0.7, h * 0.64])
    sy = h / 2 + nn(o.get('sy'), h * 0.07)
    b = min(0.03, sW * 0.08)
    grp.add(K.m(sw(frame(sW + b * 2, sH + b * 2, b, 0.026, min(sW, sH) * 0.14), bezC), M.pl,
                {'pos': [0, sy, fz - 0.018]}))
    screen = scr(game, sW, sH, {'card': o.get('card'), 'group': o.get('group'), 'id': o.get('id'),
                                'dome': min(sW, sH) * 0.05})
    screen.position.set(0, sy, fz - 0.012)
    grp.add(screen)
    # control strip
    stripY = (sy - sH / 2 - b) / 2 + 0.004
    nk = nn(o.get('knobs'), 4)
    kr = min(0.014, (sy - sH / 2 - b) * 0.32)
    for i in range(nk):
        kx = w * 0.12 + i * kr * 3.2
        for mm in knob(M, kr, [kx, stripY, fz - 0.016], {'color': 'ink', 'depth': kr * 0.9, 'skirt': False,
                                                         'rot': 0.4 + i, 'seg': 8, 'pointer': kr > 0.013}):
            grp.add(mm)
    if o.get('plate') is not False:
        grp.add(K.m(decal(nn(o.get('plate'), 'pl_KINETRON'), min(w * 0.3, 0.16), min(w * 0.3, 0.16) * 0.19), M.pl,
                    {'pos': [-w * 0.24, stripY, fz - 0.0175]}))
    if o.get('tally') is not False:
        grp.add(K.m(lw(lowCyl(0.006, 0.006, 8), nn(o.get('tallyColor'), 'red')), M.lit,
                    {'pos': [-w / 2 + 0.035, stripY, fz - 0.016], 'rot': [-HP, 0, 0]}))
    if o.get('ears'):
        for s in (-1, 1):
            grp.add(K.m(sw(cbox(0.03, h, 0.006, 0.002), faceC), M.pl, {'pos': [s * (w / 2 + 0.012), h / 2, fz - 0.002]}))
            for yy in [0.2, 0.8]:
                grp.add(K.m(sw(THREE.PlaneGeometry(0.012, 0.006).rotateY(math.pi), 'ink'), M.pl,
                            {'pos': [s * (w / 2 + 0.014), h * yy, fz - 0.0055]}))
    if o.get('handles'):
        for s in (-1, 1):
            x = s * (w / 2 - 0.02)
            grp.add(K.m(K.tube([[x, h * 0.18, fz - 0.01], [x, h * 0.18, fz - 0.045], [x, h * 0.82, fz - 0.045],
                                [x, h * 0.82, fz - 0.01]], 0.0065, {'seg': 10, 'radial': 5}), M.ch))
    # top vents
    grp.add(K.m(cu(THREE.PlaneGeometry(w * 0.5, d * 0.3).rotateX(-HP), 'vent'), M.pl,
                {'pos': [0, h + 0.001, fz + d * 0.3]}))
    return JSObj(group=grp, screen=screen, h=h, d=d)


# ================================================================================================= PROPS
# ---------------------------------------------------------------------------------- pedestal studio camera
def _pedestal_camera(game, opts=None):
    opts = {} if opts is None else opts
    g = K.prop('bc_pedestal_camera')
    M = mats(game)
    bodyC, accC, pedC = nn(opts.get('color'), 'cream'), nn(opts.get('accent'), 'wztvBlue'), \
        nn(opts.get('pedestal'), 'slate')
    tallyOn = opts.get('tally') is not False
    # --- dolly base: rounded triangle, central skirt, domed caster pods with rubber bumpers
    tri = []
    for i in range(3):
        a = (i / 3) * TAU - HP
        tri.append([math.cos(a) * 0.52, math.sin(a) * 0.52])
    g.add(K.m(sw(K.extrude(tri, 0.08, {'bevel': 0.026, 'round': 0.22, 'curveSeg': 4, 'bevelSeg': 1}).rotateX(-HP),
                 pedC), M.pl, {'pos': [0, 0.14, 0]}))
    g.add(K.m(sw(L([[0, 0], [0.3, 0], [0.28, 0.04], [0.19, 0.08], [0.15, 0.1], [0, 0.1]], 0.02, 18), pedC), M.pl,
              {'pos': [0, 0.17, 0]}))
    for i in range(3):
        a = (i / 3) * TAU - HP
        x, z = math.cos(a) * 0.4, -math.sin(a) * 0.4
        g.add(K.m(sw(L([[0, 0], [0.095, 0], [0.1, 0.03], [0.08, 0.075], [0, 0.085]], 0.015, 12), pedC), M.pl,
                  {'pos': [x, 0.09, z]}))
        g.add(K.m(sw(L([[0.088, 0], [0.104, 0], [0.104, 0.03], [0.088, 0.03]], 0, 12), 'rubber'), M.mt,
                  {'pos': [x, 0.065, z]}))
        c = caster(M, 0.036)
        c.position.set(x, 0, z)
        c.rotation.y = a
        g.add(c)
    # --- column: flared lower column, rubber bellows, chrome upper column, steering ring
    g.add(K.m(sw(L([[0, 0], [0.15, 0], [0.15, 0.03], [0.12, 0.07], [0.11, 0.12], [0.108, 0.48], [0.125, 0.5],
                    [0.125, 0.54], [0, 0.54]], 0.012, 18), pedC), M.pl, {'pos': [0, 0.22, 0]}))
    bel = [[0, 0]]
    for i in range(4):
        bel.extend([[0.098, i * 0.022 + 0.002], [0.112, i * 0.022 + 0.011]])
    bel.extend([[0.098, 0.09], [0, 0.09]])
    g.add(K.m(sw(L(bel, 0, 16), 'rubber'), M.mt, {'pos': [0, 0.76, 0]}))
    g.add(K.m(bcyl(0.075, 0.075, 0.2, 0.006, 16), M.ch, {'pos': [0, 0.84, 0]}))
    g.add(K.m(sw(L([[0, 0], [0.1, 0], [0.105, 0.02], [0.1, 0.05], [0, 0.05]], 0.01, 16), pedC), M.pl,
              {'pos': [0, 0.875, 0]}))
    g.add(K.m(sw(K.tube(ring(0.34, 24, 0), 0.026, {'seg': 30, 'radial': 7, 'closed': True}), 'rubber'), M.mt,
              {'pos': [0, 0.905, 0]}))
    for i in range(3):
        a = (i / 3) * TAU + 0.5
        g.add(K.m(K.tube([[math.cos(a) * 0.09, 0.9, math.sin(a) * 0.09], [math.cos(a) * 0.22, 0.905, math.sin(a) * 0.22],
                          [math.cos(a) * 0.33, 0.905, math.sin(a) * 0.33]], 0.013, {'seg': 5, 'radial': 6}), M.ch))
    # --- headset hook + hanging headset (coiled cord) on the column's right side
    hx, hy = 0.23, 0.66
    g.add(K.m(K.tube([[0.1, hy - 0.02, 0], [0.19, hy - 0.02, 0], [hx, hy, 0], [hx + 0.005, hy + 0.05, 0]], 0.008,
                     {'seg': 8, 'radial': 5}), M.ch))
    g.add(K.m(sw(K.tube([[hx, hy - 0.15, -0.105], [hx, hy - 0.05, -0.095], [hx, hy + 0.012, -0.04], [hx, hy + 0.02, 0],
                         [hx, hy + 0.012, 0.04], [hx, hy - 0.05, 0.095], [hx, hy - 0.15, 0.105]], 0.011,
                        {'seg': 16, 'radial': 6}), 'ink'), M.pl))
    for s in (-1, 1):
        g.add(K.m(sw(L([[0, 0], [0.052, 0], [0.056, 0.014], [0.048, 0.04], [0, 0.042]], 0.008, 12), 'ink'), M.pl,
                  {'pos': [hx, hy - 0.18, s * 0.085], 'rot': [s * HP, 0, 0]}))
        g.add(K.m(sw(L([[0, 0], [0.046, 0], [0.05, 0.01], [0.036, 0.022], [0, 0.022]], 0.006, 12), 'orange'), M.mt,
                  {'pos': [hx, hy - 0.18, s * 0.085], 'rot': [-s * HP, 0, 0]}))
    g.add(K.m(sw(K.tube([[hx + 0.01, hy - 0.2, -0.12], [hx + 0.05, hy - 0.25, -0.18], [hx + 0.04, hy - 0.3, -0.24]],
                        0.006, {'seg': 8, 'radial': 5}), 'ink'), M.pl))
    g.add(K.m(sw(lowSphere(0.02, 10, 7), 'rubber'), M.mt, {'pos': [hx + 0.04, hy - 0.305, -0.245]}))
    coil = []
    for i in range(37):
        t = i / 36
        a = t * TAU * 5
        coil.append([hx + math.cos(a) * 0.014, hy - 0.23 - t * 0.2, 0.12 + math.sin(a) * 0.014])
    coil.extend([[0.16, 0.34, 0.1], [0.12, 0.3, 0.06]])
    g.add(K.m(sw(K.tube(coil, 0.004, {'seg': 40, 'radial': 4}), 'ink'), M.pl))

    # --- pan head (part 'head') + tilt cradle (part 'tilt') carrying the camera
    head = THREE.Group()
    head.position.set(0, 1.04, 0)
    head.userData.noMerge = True
    g.add(head)
    head.add(K.m(sw(L([[0, 0], [0.13, 0], [0.14, 0.025], [0.115, 0.065], [0, 0.065]], 0.012, 16), 'charcoal'), M.pl))
    for s in (-1, 1):
        head.add(K.m(sw(cbox(0.055, 0.14, 0.24, 0.016), 'charcoal'), M.pl, {'pos': [s * 0.13, 0.11, 0]}))
    head.add(K.m(sw(cbox(0.22, 0.05, 0.18, 0.014), 'charcoal'), M.pl, {'pos': [0, 0.08, 0]}))
    for s in (-1, 1):
        head.add(K.m(bcyl(0.034, 0.034, 0.02, 0.006, 12), M.ch, {'pos': [s * 0.158, 0.15, 0], 'rot': [0, 0, -s * HP]}))
    tilt = THREE.Group()
    tilt.position.set(0, 0.15, 0)
    tilt.userData.noMerge = True
    head.add(tilt)
    bw, bh, bd = 0.42, 0.4, 0.7
    by, bz = 0.035 + bh / 2 + 0.01, 0.03  # body center (tilt space)
    tilt.add(K.m(sw(cbox(0.3, 0.04, 0.56, 0.012), 'charcoal'), M.pl, {'pos': [0, 0.035, 0.02]}))
    tilt.add(K.m(sw(K.box(bw, bh, bd, 0.085), bodyC), M.pl, {'pos': [0, by, bz]}))
    # accent side panels with the 13 disc + nameplate + vent grilles
    for s in (-1, 1):
        pan = K.m(sw(K.extrude(K.roundRect(0.54, 0.25, 0.075), 0.026, {'bevel': 0.009, 'curveSeg': 4, 'bevelSeg': 1}),
                     accC), M.pl)
        pan.position.set(s * (bw / 2 + 0.002), by - 0.02, bz + 0.03)
        pan.rotation.y = s * HP
        tilt.add(pan)
        logo = K.m(discDecal('logo13', 0.085, 28), M.pl)
        logo.position.set(s * (bw / 2 + 0.0155), by - 0.01, bz - 0.12)
        logo.rotation.y = -s * HP
        tilt.add(logo)
        plate = K.m(decal('pl_VIDICAM', 0.22, 0.041), M.pl)
        plate.position.set(s * (bw / 2 + 0.0155), by - 0.095, bz + 0.1)
        plate.rotation.y = -s * HP
        tilt.add(plate)
        vent = K.m(decal('vent', 0.12, 0.12), M.pl)
        vent.position.set(s * (bw / 2 + 0.0155), by + 0.01, bz + 0.19)
        vent.rotation.y = -s * HP
        tilt.add(vent)
    # lens turret + big zoom lens (axis -z) + flared matte-box sunshade
    fz = bz - bd / 2
    tilt.add(K.m(sw(K.box(0.34, 0.33, 0.07, 0.045), 'charcoal'), M.pl, {'pos': [0, by - 0.005, fz - 0.015]}))
    lz = fz - 0.05
    tilt.add(K.m(sw(L([[0, 0], [0.105, 0], [0.105, 0.03], [0.092, 0.036], [0.092, 0.24], [0, 0.24]], 0.008, 18), 'ink'),
                 M.pl, {'pos': [0, by, lz], 'rot': [-HP, 0, 0]}))

    def knurl(r0, ln, n=6):
        p = [[0, 0]]
        for i in range(n + 1):
            p.append([r0 + (0.009 if i % 2 else 0.002), (i / n) * ln])
        p.append([0, ln])
        return p
    tilt.add(K.m(sw(L(knurl(0.093, 0.065), 0, 16), 'rubber'), M.mt, {'pos': [0, by, lz - 0.05], 'rot': [-HP, 0, 0]}))
    tilt.add(K.m(sw(L(knurl(0.093, 0.05, 4), 0, 16), 'rubber'), M.mt, {'pos': [0, by, lz - 0.15], 'rot': [-HP, 0, 0]}))
    tilt.add(K.m(L([[0.094, 0], [0.101, 0], [0.101, 0.014], [0.094, 0.014]], 0, 18), M.ch,
                 {'pos': [0, by, lz - 0.032], 'rot': [-HP, 0, 0]}))
    tilt.add(K.m(L([[0.094, 0], [0.101, 0], [0.101, 0.012], [0.094, 0.012]], 0, 18), M.ch,
                 {'pos': [0, by, lz - 0.215], 'rot': [-HP, 0, 0]}))
    tilt.add(K.m(THREE.CircleGeometry(0.094, 20).rotateY(math.pi), M.glass, {'pos': [0, by, lz - 0.236]}))
    shade = K.taper(frame(0.25, 0.21, 0.02, 0.13, 0.05, 0.035, {'bevel': 0.008}), {'axis': 'z', 'k': 0.72})
    tilt.add(K.m(sw(shade, 'rubber'), M.mt, {'pos': [0, by, lz - 0.3]}))
    tilt.add(K.m(sw(cbox(0.06, 0.09, 0.17, 0.016), 'charcoal'), M.pl, {'pos': [0.12, by - 0.02, lz - 0.1]}))
    tilt.add(K.m(sw(cbox(0.034, 0.034, 0.034, 0.008), 'red'), M.pl, {'pos': [0.155, by + 0.01, lz - 0.12]}))
    # viewfinder (flush on the body) with rubber hood + camera number, tally dome up front
    vh = 0.21
    vy, vz = by + bh / 2 + vh / 2 - 0.02, bz + 0.08
    tilt.add(K.m(sw(K.box(0.36, vh, 0.4, 0.06), bodyC), M.pl, {'pos': [0, vy, vz]}))
    tilt.add(K.m(sw(K.box(0.366, 0.055, 0.36, 0.022, {'seg': 1}), accC), M.pl, {'pos': [0, vy - 0.05, vz + 0.01]}))
    tilt.add(K.m(sw(K.taper(frame(0.3, 0.2, 0.032, 0.16, 0.055, 0.03, {'bevel': 0.01}), {'axis': 'z', 'k': 1.12}),
                    'rubber'), M.mt, {'pos': [0, vy + 0.005, vz + 0.26]}))
    tilt.add(K.m(sw(THREE.PlaneGeometry(0.24, 0.14), 'black'), M.mt, {'pos': [0, vy + 0.005, vz + 0.2]}))
    tilt.add(K.m(decal('num' + js_str(nn(opts.get('num'), 1)), 0.1, 0.1), M.pl, {'pos': [0.1, vy + 0.012, vz - 0.2015]}))
    tilt.add(K.m(decal('vent', 0.1, 0.07), M.pl, {'pos': [-0.1, vy + 0.012, vz - 0.2015]}))
    tilt.add(K.m(L([[0, 0], [0.06, 0], [0.063, 0.014], [0.056, 0.024], [0, 0.024]], 0.005, 16), M.ch,
                 {'pos': [0, vy + vh / 2 - 0.004, vz - 0.12]}))
    onMat, offMat = M.lit, M.dim
    tallyGeo = lw(L([[0, 0], [0.052, 0], [0.052, 0.014], [0.045, 0.042], [0.026, 0.064], [0, 0.069]], 0.012, 16), 'red')
    tally = K.m(tallyGeo, onMat if tallyOn else offMat, {'pos': [0, vy + vh / 2 + 0.018, vz - 0.12], 'name': 'tally'})
    tally.userData.noMerge = True
    tilt.add(tally)
    # carry handle along the viewfinder top
    tilt.add(K.m(K.tube([[0, vy + vh / 2 - 0.01, vz + 0.02], [0, vy + vh / 2 + 0.05, vz + 0.05],
                         [0, vy + vh / 2 + 0.05, vz + 0.14], [0, vy + vh / 2 - 0.01, vz + 0.17]], 0.012,
                        {'seg': 12, 'radial': 6}), M.ch))
    # pan bars with rubber grips, zoom rocker (right) and focus crank (left)
    for s in (-1, 1):
        pts = [[s * 0.11, 0.05, 0.25], [s * 0.18, 0.02, 0.44], [s * 0.25, -0.04, 0.62], [s * 0.29, -0.08, 0.76]]
        tilt.add(K.m(K.tube(pts, 0.016, {'seg': 12, 'radial': 7}), M.ch))
        tilt.add(K.m(sw(K.tube([[s * 0.245, -0.035, 0.6], [s * 0.27, -0.06, 0.69], [s * 0.293, -0.085, 0.78]], 0.027,
                               {'seg': 6, 'radial': 9}), 'rubber'), M.mt))
        tilt.add(K.m(sw(lowSphere(0.029, 10, 7), 'rubber'), M.mt, {'pos': [s * 0.296, -0.088, 0.79]}))
    tilt.add(K.m(sw(cbox(0.055, 0.04, 0.08, 0.012), 'charcoal'), M.pl, {'pos': [0.205, 0.0, 0.5]}))
    tilt.add(K.m(sw(cbox(0.024, 0.02, 0.045, 0.006), 'red'), M.pl, {'pos': [0.205, 0.027, 0.5]}))
    tilt.add(K.m(sw(bcyl(0.045, 0.045, 0.02, 0.005, 14), 'charcoal'), M.pl, {'pos': [-0.215, 0.0, 0.5], 'rot': [0, 0, HP]}))
    tilt.add(K.m(sw(lowCyl(0.009, 0.055, 8), 'rubber'), M.mt, {'pos': [-0.235, 0.03, 0.5], 'rot': [0, 0, HP]}))
    # camera cable: back connector, down behind the pedestal, trailing on the floor
    tilt.add(K.m(bcyl(0.032, 0.032, 0.05, 0.006, 12), M.ch, {'pos': [0.09, by - 0.07, bz + bd / 2 - 0.005],
                                                            'rot': [HP, 0, 0]}))
    g.add(K.m(sw(K.tube([[0.09, 1.28, 0.44], [0.11, 1.18, 0.54], [0.18, 0.8, 0.56], [0.22, 0.3, 0.56], [0.25, 0.04, 0.62],
                         [0.34, 0.02, 0.76], [0.52, 0.02, 0.82]], 0.019, {'seg': 26, 'radial': 6}), 'ink'), M.pl))
    lensTip = THREE.Object3D()
    lensTip.name = 'lensTip'
    lensTip.position.set(0, by, lz - 0.37)
    tilt.add(lensTip)

    g.userData.parts = {'head': head, 'tilt': tilt, 'tally': tally, 'lensTip': lensTip}
    g.userData.lampMats = {'on': onMat, 'off': offMat}
    g.userData.colliders = [{'min': [-0.46, 0, -0.44], 'max': [0.46, 1.0, 0.5]},
                            {'min': [-0.26, 1.0, -0.78], 'max': [0.26, 1.86, 0.85]}]
    return done(game, g, {'mergeParts': [head, tilt]})


registerProp('bc_pedestal_camera', _pedestal_camera, {
    'category': 'broadcast', 'tags': ['camera', 'studio', 'feed_cam', 'hero'], 'size': [1.05, 1.86, 1.6], 'hero': True,
    'desc': 'boxy 70s pedestal studio camera: tally dome, zoom lens + matte box, pan bars, headset on hook. parts '
            'head/tilt/tally/lensTip (lampMats on/off); opts {num 1-4, tally, color, accent, pedestal}'})


# ---------------------------------------------------------------------------------- 13" portable TV
def _tv_portable(game, opts=None):
    opts = {} if opts is None else opts
    g = K.prop('bc_tv_portable')
    M = mats(game)
    shellC = nn(opts.get('color'), 'red')
    W, H, D, foot = 0.44, 0.35, 0.25, 0.03
    cy, fz = foot + H / 2, -D / 2 - 0.02
    g.add(K.m(sw(K.box(W, H, D, 0.075, {'seg': 2}), shellC), M.pl, {'pos': [0, cy, -0.02]}))
    g.add(K.m(sw(K.taper(K.box(W * 0.8, H * 0.78, 0.2, 0.045), {'axis': 'z', 'k': 0.58, 'ease': 0.8}), shellC), M.pl,
              {'pos': [0, cy + 0.01, D / 2 + 0.06]}))
    for i in range(5):
        g.add(K.m(sw(cbox(0.012, 0.08, 0.01, 0.004), 'ink'), M.pl, {'pos': [-0.05 + i * 0.025, cy + 0.02, D / 2 + 0.16]}))
    # visor brow + cream face + chrome trim loop
    g.add(K.m(sw(K.box(W + 0.012, 0.04, 0.07, 0.02, {'seg': 1}), shellC), M.pl, {'pos': [0, foot + H - 0.012, fz + 0.01]}))
    g.add(K.m(sw(K.box(W - 0.03, H - 0.05, 0.02, 0.045), 'capWhite'), M.pl, {'pos': [0, cy - 0.01, fz + 0.006]}))
    g.add(K.m(K.tube(rectLoopXY(W - 0.022, H - 0.042, 0.05, 2), 0.005, {'seg': 28, 'radial': 4, 'closed': True}), M.ch,
              {'pos': [0, cy - 0.01, fz - 0.003]}))
    sx, sW, sH, sy = -0.06, 0.27, 0.21, cy - 0.01
    g.add(K.m(sw(frame(sW + 0.05, sH + 0.05, 0.028, 0.03, 0.06, 0.045, {'curveSeg': 3, 'holeSeg': 3}), 'ink'), M.pl,
              {'pos': [sx, sy, fz - 0.008]}))
    screen = scr(game, sW, sH, {'card': nn(opts.get('card'), 'show_7'), 'group': opts.get('group'), 'dome': 0.014})
    screen.position.set(sx, sy, fz - 0.002)
    g.add(screen)
    # control column: VHF + UHF dials, grille, power knob, nameplate
    cx = 0.155
    g.add(K.m(discDecal('dialCh', 0.047), M.pl, {'pos': [cx, cy + 0.07, fz - 0.0045]}))
    for mm in knob(M, 0.026, [cx, cy + 0.07, fz - 0.005], {'color': 'ink', 'rot': 0.9}):
        g.add(mm)
    g.add(K.m(discDecal('dialUhf', 0.036), M.pl, {'pos': [cx, cy - 0.025, fz - 0.0045]}))
    for mm in knob(M, 0.02, [cx, cy - 0.025, fz - 0.005], {'color': 'silver', 'mat': 'me', 'rot': -0.7}):
        g.add(mm)
    g.add(K.m(cu(cbox(0.075, 0.06, 0.008, 0.003), 'grille'), M.pl, {'pos': [cx, cy - 0.105, fz - 0.002]}))
    g.add(K.m(decal('pl_ZENOLUX', 0.12, 0.0225), M.pl, {'pos': [sx, cy - 0.145, fz - 0.0045]}))
    # top: fold-down chrome handle, rabbit ears (part 'antenna')
    top = foot + H
    for s in (-1, 1):
        g.add(K.m(sw(bcyl(0.02, 0.022, 0.016, 0.005, 10), 'ink'), M.pl,
                  {'pos': [s * (W / 2 - 0.004), top - 0.055, 0.0], 'rot': [0, 0, -s * HP]}))
    hx = W / 2 + 0.012
    g.add(K.m(K.tube([[-hx, top - 0.055, 0], [-hx, top - 0.01, -0.03], [-W / 2 + 0.03, top + 0.012, -0.07],
                      [-0.12, top + 0.016, -0.08], [0.12, top + 0.016, -0.08], [W / 2 - 0.03, top + 0.012, -0.07],
                      [hx, top - 0.01, -0.03], [hx, top - 0.055, 0]], 0.008, {'seg': 18, 'radial': 5}), M.ch))
    ant = rabbitEars(M, 0.46, 0.6, 0.25)
    ant.position.set(0.03, top - 0.005, 0.06)
    g.add(ant)
    for x, z in [[-1, -1], [1, -1], [-1, 1], [1, 1]]:
        g.add(K.m(sw(bcyl(0.02, 0.024, foot, 0.006, 8), 'rubber'), M.mt,
                  {'pos': [x * (W / 2 - 0.06), 0, z * (D / 2 - 0.04)]}))
    g.userData.parts = {'antenna': ant}
    g.userData.colliders = [{'min': [-W / 2, 0, fz], 'max': [W / 2, top + 0.03, D / 2 + 0.17]}]
    g.userData.interact = {'point': [0, cy, fz - 0.05], 'radius': 1.2}
    return done(game, g)


registerProp('bc_tv_portable', _tv_portable, {
    'category': 'broadcast', 'tags': ['tv', 'crt', 'screen', 'portable'], 'size': [0.47, 0.8, 0.45],
    'desc': '13" portable TV, red shell, visor brow, VHF/UHF dials, rabbit ears. opts {color, card, group}'})


# ---------------------------------------------------------------------------------- 19" walnut TV set
def _tv_19(game, opts=None):
    opts = {} if opts is None else opts
    g = K.prop('bc_tv_19')
    M = mats(game)
    wood = woodMat(game)
    legs = nn(opts.get('legs'), 'splay')
    legH = 0 if legs == 'none' else 0.3
    W, H, D = 0.7, 0.52, 0.44
    y0 = legH
    cy, fz = y0 + H / 2, -D / 2
    g.add(K.m(K.box(W, H, D, 0.04, {'uv': 1.4}), wood, {'pos': [0, cy, 0]}))
    g.add(K.m(sw(K.taper(K.box(W * 0.74, H * 0.74, 0.18, 0.05), {'axis': 'z', 'k': 0.6}), 'chocolate'), M.pl,
              {'pos': [0, cy + 0.01, D / 2 + 0.08]}))
    # recessed silver face panel with chrome trim
    g.add(K.m(sw(K.box(W - 0.07, H - 0.07, 0.03, 0.025), 'silver'), M.me, {'pos': [0, cy, fz - 0.002]}))
    g.add(K.m(K.tube(rectLoopXY(W - 0.058, H - 0.058, 0.03, 2), 0.006, {'seg': 28, 'radial': 4, 'closed': True}), M.ch,
              {'pos': [0, cy, fz - 0.012]}))
    sx, sW, sH = -0.075, 0.44, 0.34
    g.add(K.m(sw(frame(sW + 0.05, sH + 0.05, 0.028, 0.03, 0.07, 0.05, {'curveSeg': 3, 'holeSeg': 3}), 'ink'), M.pl,
              {'pos': [sx, cy, fz - 0.02]}))
    screen = scr(game, sW, sH, {'card': nn(opts.get('card'), 'show_4'), 'group': opts.get('group'), 'dome': 0.02})
    screen.position.set(sx, cy, fz - 0.014)
    g.add(screen)
    cx = 0.235
    g.add(K.m(discDecal('dialCh', 0.05), M.pl, {'pos': [cx, cy + 0.14, fz - 0.018]}))
    for mm in knob(M, 0.03, [cx, cy + 0.14, fz - 0.018], {'color': 'walnut', 'cap': 'silver', 'rot': 1.3}):
        g.add(mm)
    g.add(K.m(discDecal('dialUhf', 0.04), M.pl, {'pos': [cx, cy + 0.035, fz - 0.018]}))
    for mm in knob(M, 0.022, [cx, cy + 0.035, fz - 0.018], {'color': 'walnut', 'cap': 'silver', 'rot': -0.5}):
        g.add(mm)
    for i in range(3):
        g.add(K.m(sw(keycap(0.034, 0.02, 0.012, 0.003), 'gold' if i == 0 else 'ivory'), M.pl,
                  {'pos': [cx - 0.04 + i * 0.04, cy - 0.04, fz - 0.017], 'rot': [-HP, 0, 0]}))
    g.add(K.m(cu(K.box(0.13, 0.12, 0.01, 0.006), 'fabric'), M.mt, {'pos': [cx, cy - 0.14, fz - 0.017]}))
    g.add(K.m(decal('pl_ZENOLUX', 0.12, 0.0225), M.pl, {'pos': [sx, cy - 0.215, fz - 0.018]}))
    if legs == 'splay':
        for x, z in [[-1, -1], [1, -1], [-1, 1], [1, 1]]:
            top = [x * (W / 2 - 0.08), y0 + 0.01, z * (D / 2 - 0.07)]
            foot = [x * (W / 2 - 0.02), 0.03, z * (D / 2 - 0.01)]
            g.add(along(lambda l_: K.uvScale(bcyl(0.022, 0.014, l_, 0.006, 8).clone(), 1, 2), wood, foot, top))
            g.add(K.m(sw(bcyl(0.015, 0.017, 0.035, 0.004, 8), 'brass'), M.me, {'pos': [foot[0], 0, foot[2]]}))
        g.add(K.m(K.box(W - 0.1, 0.035, D - 0.1, 0.012, {'uv': 1.4}), wood, {'pos': [0, y0 - 0.005, 0]}))
    elif legs == 'swivel':
        g.add(K.m(sw(K.lathe([[0, 0], [0.24, 0], [0.25, 0.02], [0.2, 0.04], [0.06, 0.06], [0.045, 0.1],
                              [0.045, legH - 0.04], [0.14, legH - 0.02], [0.14, legH], [0, legH]],
                             {'round': 0.01, 'seg': 24}), 'silver'), M.ch))
    if opts.get('ears'):
        ant = rabbitEars(M, 0.5, 0.55, 0.2)
        ant.position.set(0.1, y0 + H - 0.005, 0.05)
        g.add(ant)
        g.userData.parts = {'antenna': ant}
    g.userData.colliders = [{'min': [-W / 2, 0, -D / 2 - 0.03], 'max': [W / 2, y0 + H, D / 2 + 0.17]}]
    g.userData.interact = {'point': [0, cy, fz - 0.05], 'radius': 1.3}
    return done(game, g)


registerProp('bc_tv_19', _tv_19, {
    'category': 'broadcast', 'tags': ['tv', 'crt', 'screen', 'walnut'], 'size': [0.72, 0.82, 0.64],
    'desc': '19" walnut TV on splayed legs, silver face, dials, speaker cloth. opts {legs:splay|swivel|none, ears, '
            'card, group}'})


# ---------------------------------------------------------------------------------- rack monitor
def _rack_monitor(game, opts=None):
    opts = {} if opts is None else opts
    g = K.prop('bc_rack_monitor')
    M = mats(game)
    s = nn(opts.get('size'), 14) / 14
    u = monitorUnit(game, M, {'w': 0.48 * s, 'h': 0.37 * s, 'd': 0.44 * s, 'card': nn(opts.get('card'), 'color_bars'),
                              'group': opts.get('group'), 'id': opts.get('id'), 'ears': True, 'handles': True,
                              'case': nn(opts.get('case'), 'charcoal'), 'face': nn(opts.get('face'), 'putty'),
                              'knobs': 4})
    g.add(u.group)
    g.userData.colliders = [{'min': [-0.26 * s, 0, -0.27 * s], 'max': [0.26 * s, 0.37 * s, 0.24 * s]}]
    return done(game, g)


registerProp('bc_rack_monitor', _rack_monitor, {
    'category': 'broadcast', 'tags': ['monitor', 'crt', 'screen', 'master_control'], 'size': [0.53, 0.37, 0.48],
    'desc': 'broadcast rack monitor: rack ears, chrome handles, knob strip, tally LED. opts {size:9|14, card, group, '
            'id, case, face}'})


# ---------------------------------------------------------------------------------- stacked monitor bank
def _monitor_bank(game, opts=None):
    opts = {} if opts is None else opts
    g = K.prop('bc_monitor_bank')
    M = mats(game)
    wood = woodMat(game)
    W, CH, D = 1.5, 0.66, 0.56
    # base cabinet: walnut cheeks, charcoal front with vent + plate, kick recess
    for sx in (-1, 1):
        g.add(K.m(K.box(0.05, CH, D, 0.018, {'uv': 1.5, 'swap': True}), wood, {'pos': [sx * (W / 2 - 0.025), CH / 2, 0]}))
    g.add(K.m(sw(K.box(W - 0.1, CH - 0.08, D - 0.03, 0.02), 'charcoal'), M.pl, {'pos': [0, CH / 2 + 0.04, 0.01]}))
    g.add(K.m(sw(cbox(W - 0.14, 0.07, D - 0.1, 0.008), 'black'), M.pl, {'pos': [0, 0.035, 0.03]}))
    g.add(K.m(K.box(W + 0.02, 0.035, D + 0.02, 0.014, {'uv': 1.4}), wood, {'pos': [0, CH + 0.0175, 0]}))
    for sx in (-0.4, 0.4):
        g.add(K.m(decal('vent', 0.3, 0.26), M.pl, {'pos': [sx, CH / 2 + 0.03, -D / 2 + 0.004]}))
    g.add(K.m(decal('pl_MASTER', 0.3, 0.056), M.pl, {'pos': [0, CH / 2 + 0.1, -D / 2 + 0.004]}))
    for i in range(4):
        g.add(K.m(lw(keycap(0.04, 0.03, 0.014, 0.004), ['green', 'amber', 'red', 'white'][i]), M.lit,
                  {'pos': [-0.075 + i * 0.05, CH / 2 - 0.02, -D / 2 + 0.005], 'rot': [-HP, 0, 0]}))
    cards = nn(opts.get('cards'), ['color_bars', 'show_2', 'station_id', 'show_9', 'show_12'])
    groups = nn(opts.get('groups'), [])
    units = []
    # lower row: 3 x 14" rack monitors, slight lean; upper row: 2 x 19" monitors
    lower = [-0.49, 0, 0.49]
    for i, x in enumerate(lower):
        u = monitorUnit(game, M, {'w': 0.47, 'h': 0.37, 'd': 0.44, 'card': _at(cards, i), 'group': _at(groups, i),
                                  'id': _at(opts.get('ids'), i), 'face': 'light' if i == 1 else 'putty', 'knobs': 3})
        u.group.position.set(x, CH + 0.035, -0.02)
        u.group.rotation.z = [0.012, -0.006, -0.015][i]
        g.add(u.group)
        units.append(u)
    for i, x in enumerate([-0.33, 0.35]):
        u = monitorUnit(game, M, {'w': 0.62, 'h': 0.46, 'd': 0.46, 'card': _at(cards, 3 + i), 'group': _at(groups, 3 + i),
                                  'id': _at(opts.get('ids'), 3 + i), 'case': 'slate' if i else 'charcoal',
                                  'face': 'putty', 'knobs': 4})
        u.group.position.set(x, CH + 0.035 + 0.375, 0.0)
        u.group.rotation.set(-0.06, [0.035, -0.028][i], [-0.02, 0.025][i])
        g.add(u.group)
        units.append(u)
    # cables drooping behind
    g.add(K.m(sw(K.tube([[-0.5, 1.0, 0.25], [-0.45, 0.8, 0.34], [-0.2, 0.7, 0.32], [0.3, 0.72, 0.33], [0.55, 0.95, 0.27]],
                        0.014, {'seg': 24, 'radial': 6}), 'ink'), M.pl))
    g.userData.colliders = [{'min': [-W / 2 - 0.01, 0, -D / 2 - 0.02], 'max': [W / 2 + 0.01, 1.55, D / 2 + 0.02]}]
    return done(game, g)


registerProp('bc_monitor_bank', _monitor_bank, {
    'category': 'broadcast', 'tags': ['monitor', 'crt', 'screen', 'master_control', 'newsroom'],
    'size': [1.52, 1.56, 0.58], 'hero': True,
    'desc': 'monitor bank: walnut base cabinet + 3 rack monitors + 2 x 19" on top, leaning. 5 screens. opts {cards[5], '
            'groups[5], ids[5]}'})


# ---------------------------------------------------------------------------------- cart monitor (AV cart)
def _cart_monitor(game, opts=None):
    opts = {} if opts is None else opts
    g = K.prop('bc_cart_monitor')
    M = mats(game)
    cartC = nn(opts.get('cart'), 'mustard')
    W, D = 0.72, 0.52
    shelves = [0.2, 0.56, 0.94]
    for y in shelves:
        g.add(K.m(sw(K.box(W, 0.03, D, 0.012), cartC), M.pl, {'pos': [0, y, 0]}))
        g.add(K.m(sw(K.tube(K.roundRectPath(W - 0.012, D - 0.012, 0.03, 0.022, 2), 0.008,
                            {'seg': 20, 'radial': 4, 'closed': True}), cartC), M.pl, {'pos': [0, y, 0]}))
    for x, z in [[-1, -1], [1, -1], [-1, 1], [1, 1]]:
        g.add(K.m(bcyl(0.015, 0.015, 0.88, 0.004, 8), M.ch, {'pos': [x * (W / 2 - 0.03), 0.09, z * (D / 2 - 0.03)]}))
        c = caster(M, 0.035)
        c.position.set(x * (W / 2 - 0.03), 0, z * (D / 2 - 0.03))
        c.rotation.y = x * z * 0.6
        g.add(c)
    mon = monitorUnit(game, M, {'w': 0.58, 'h': 0.46, 'd': 0.46, 'card': nn(opts.get('card'), 'show_5'),
                                'group': opts.get('group'), 'id': opts.get('id'), 'case': 'slate', 'face': 'light',
                                'handles': True, 'knobs': 4})
    mon.group.position.set(0, 0.955, -0.01)
    mon.group.rotation.y = 0.04
    g.add(mon.group)
    # strap over the monitor
    g.add(K.m(sw(cbox(0.05, 0.006, 0.47, 0.002), 'ink'), M.mt, {'pos': [0.18, 0.955 + 0.465, 0.0], 'rot': [0, 0.04, 0]}))
    # cassette deck on the middle shelf
    dy = 0.575
    g.add(K.m(sw(K.box(0.54, 0.14, 0.38, 0.025), 'silver'), M.me, {'pos': [0, dy + 0.07, 0.0]}))
    g.add(K.m(sw(cbox(0.52, 0.02, 0.36, 0.008), 'charcoal'), M.pl, {'pos': [0, dy + 0.145, 0.0]}))
    g.add(K.m(sw(cbox(0.3, 0.012, 0.2, 0.004), 'ink'), M.pl, {'pos': [-0.08, dy + 0.155, 0.02]}))
    for i in range(6):
        g.add(K.m(sw(keycap(0.04, 0.05, 0.016, 0.004), 'red' if i == 4 else 'ivory'), M.pl,
                  {'pos': [-0.2 + i * 0.045, dy + 0.12, -0.19], 'rot': [-0.6, 0, 0]}))
    g.add(K.m(decal('digits', 0.12, 0.03), M.lit, {'pos': [0.17, dy + 0.08, -0.1905]}))
    g.add(K.m(decal('lbl_VTR', 0.1, 0.025), M.pl, {'pos': [0.17, dy + 0.035, -0.1905]}))
    # bottom shelf: cable coil + tape boxes
    coil = []
    for i in range(61):
        t = i / 60
        a = t * TAU * 3.2
        r = 0.1 + math.sin(a * 0.5) * 0.008
        coil.append([-0.15 + math.cos(a) * r, 0.24 + t * 0.05, 0.02 + math.sin(a) * r * 0.9])
    g.add(K.m(sw(K.tube(coil, 0.012, {'seg': 50, 'radial': 4}), 'orange'), M.pl))
    for x, y, c, r in [[0.13, 0.215, 'wztvBlue', 0.1], [0.16, 0.255, 'charcoal', -0.12], [0.14, 0.295, 'red', 0.05]]:
        g.add(K.m(sw(cbox(0.24, 0.04, 0.16, 0.007), c), M.pl, {'pos': [x, y, 0.0], 'rot': [0, r, 0]}))
        lab = K.m(sw(cbox(0.1, 0.002, 0.07, 0.0008), 'paper'), M.pl, {'pos': [x, y + 0.021, 0.0], 'rot': [0, r, 0]})
        g.add(lab)
    # power cable down the back leg
    g.add(K.m(sw(K.tube([[0.1, 1.1, 0.24], [0.2, 1.0, 0.3], [0.33, 0.8, 0.27], [0.33, 0.3, 0.27], [0.36, 0.02, 0.4],
                         [0.5, 0.012, 0.6]], 0.01, {'seg': 22, 'radial': 5}), 'ink'), M.pl))
    g.userData.colliders = [{'min': [-W / 2 - 0.02, 0, -D / 2 - 0.05], 'max': [W / 2 + 0.02, 1.42, D / 2 + 0.02]}]
    g.userData.interact = None
    return done(game, g)


registerProp('bc_cart_monitor', _cart_monitor, {
    'category': 'broadcast', 'tags': ['monitor', 'crt', 'screen', 'cart', 'feed_monitor', 'newsroom'],
    'size': [0.76, 1.42, 0.6], 'hero': True,
    'desc': 'rolling AV cart: 19" monitor (strap), cassette deck, cable coil, tape boxes. opts {card, group (e.g. '
            'scr_feed_newsroom), id, cart}'})


# ---------------------------------------------------------------------------------- MC monitor wall (4x3)
# Three rows of big CRTs fill MC's CRT band (0.56-3.28 m under the 3.6 m ceiling). The MIDDLE row, at eye level, is
# scr_mc_feeds (the four live feeds); the top and bottom rows are scr_mc_canned. The bottom-row corner CRTs carry the
# screen-spawn ids ss_mc_w (column 0 = the viewer's left) / ss_mc_e (last column); every other screen is
# mcwall_r{row}c{col}. The furniture (lamp keys, LED bars, knobs, bezels) scales with the row height.
def _monitor_wall(game, opts=None):
    opts = {} if opts is None else opts
    g = K.prop('bc_monitor_wall')
    M = mats(game)
    brushed = brushedMat(game)
    cols, rows = nn(opts.get('cols'), 4), nn(opts.get('rows'), 3)
    # defaults fit MC's 3.6 m ceiling: CRT band 0.56-3.28 m, header to 3.48, cap to 3.55
    base, band, headH = nn(opts.get('base'), 0.56), nn(opts.get('band'), 2.72), nn(opts.get('headH'), 0.2)
    cw, rh = nn(opts.get('cellW'), 1.6), nn(opts.get('cellH'), band / rows)
    k = rh / 0.68
    kw = min(k, 1.2)   # furniture scale vs the classic 0.68 m row
    W, D, topY = cols * cw, 0.5, base + rows * rh
    H = topY + headH
    post = 0.07
    sW = nn(opts.get('screenW'), min(0.8 * k, cw - 2 * post - 0.36))
    sH = nn(opts.get('screenH'), sW * (0.58 / 0.8))
    fz = -D / 2
    colLabels = nn(opts.get('labels'), ['LOBBY', 'NEWS', 'STUDIO A', 'STUDIO B'])
    feedRow = nn(opts.get('feedRow'), (int(math.floor((rows - 1) / 2)) if rows >= 3 else 0))
    spawnIds = None if opts.get('spawnIds') is False else {
        '%s_0' % js_str(rows - 1): 'ss_mc_w', '%s_%s' % (js_str(rows - 1), js_str(cols - 1)): 'ss_mc_e'}
    rnd = mulberry32(1313)
    canned = ['color_bars', 'station_id', 'snow', 'color_bars', 'station_id', 'snow', 'station_id', 'color_bars', 'snow',
              'station_id', 'color_bars', 'snow']
    feeds = ['show_4', 'show_7', 'show_2', 'show_9']
    cannedN = 0
    # back shell (one box) + top cap + plinth
    g.add(K.m(sw(K.box(W - 0.02, H - 0.04, D - 0.1, 0.01), 'charcoal'), M.pl, {'pos': [0, H / 2, 0.05]}))
    g.add(K.m(sw(K.box(W + 0.04, 0.07, D + 0.04, 0.025, {'seg': 1}), 'wztvBlue'), M.pl, {'pos': [0, H + 0.025, 0]}))
    g.add(K.m(sw(cbox(W, 0.018, 0.01, 0.003), 'orange'), M.pl, {'pos': [0, H - 0.03, -D / 2 - 0.003]}))
    for c in range(cols + 1):
        g.add(K.m(discDecal('logo13', 0.05, 16), M.pl, {'pos': [-W / 2 + c * cw, H + 0.025, -D / 2 - 0.021]}))
    g.add(K.m(sw(K.box(W, 0.08, D - 0.06, 0.012), 'black'), M.mt, {'pos': [0, 0.04, 0.02]}))
    for c in range(cols):
        x0 = W / 2 - (c + 0.5) * cw  # c = 0 is the leftmost column seen from the front
        pw = cw - 2 * post - 0.006
        # posts
        for s in (-1, 1):
            g.add(K.m(K.box(post, H, D, 0.012, {'uv': 2.2, 'swap': True}), brushed,
                      {'pos': [x0 + s * (cw / 2 - post / 2), H / 2, 0]}))
        # front panel with rounded CRT openings
        shape = K.roundRect(pw, rows * rh - 0.01, 0.015)
        for r in range(rows):
            cy = (rows - 1 - r + 0.5) * rh - (rows * rh) / 2
            shape.holes.append(THREE.Path([p.add(THREE.Vector2(0, cy)) for p in
                                           K.roundRect(sW + 0.06, sH + 0.06, 0.1 * kw).getPoints(4)]))
        panel = K.extrude(shape, 0.03, {'bevel': 0.008, 'bevelSeg': 1, 'curveSeg': 3, 'uv': 2})
        g.add(K.m(panel, brushed, {'pos': [x0, base + (rows * rh) / 2, fz + 0.015]}))
        # header + kick cabinet
        g.add(K.m(K.box(pw, headH - 0.02, 0.05, 0.015, {'uv': 2, 'seg': 1}), brushed,
                  {'pos': [x0, topY + headH / 2, fz + 0.03]}))
        g.add(K.m(decal('lbl_' + nn(_at(colLabels, c), 'LINE'), 0.36, 0.09), M.pl,
                  {'pos': [x0 + 0.2, topY + headH / 2, fz + 0.0035]}))
        for i in range(3):
            g.add(K.m(lw(keycap(0.04, 0.03, 0.012, 0.004), ('red' if c == 0 else 'green') if i == 0 else 'amber'),
                      M.dim if i == 2 else M.lit,
                      {'pos': [x0 - 0.2 - i * 0.07, topY + headH / 2, fz + 0.004], 'rot': [-HP, 0, 0]}))
        g.add(K.m(K.box(pw, base - 0.1, 0.04, 0.015, {'uv': 2, 'seg': 1}), brushed,
                  {'pos': [x0, 0.08 + (base - 0.1) / 2, fz + 0.03]}))
        g.add(K.m(decal('vent', 0.5, 0.26), M.pl, {'pos': [x0 + 0.3, 0.08 + (base - 0.1) / 2, fz + 0.0085]}))
        g.add(K.m(decal('pl_MASTER' if c == 1 else 'pl_KINETRON', 0.34, 0.064), M.pl,
                  {'pos': [x0 - 0.3, 0.08 + (base - 0.1) / 2 + 0.06, fz + 0.0085]}))
        g.add(K.m(decal('hv', 0.2, 0.0375), M.pl, {'pos': [x0 - 0.3, 0.08 + (base - 0.1) / 2 - 0.07, fz + 0.0085]}))
        for r in range(rows):
            cy = base + (rows - 1 - r + 0.5) * rh
            # tube bezel (dark rounded face behind the opening) + screen
            g.add(K.m(sw(THREE.ShapeGeometry(K.roundRect(sW + 0.06, sH + 0.06, 0.1 * kw), 4).rotateY(math.pi), 'ink'),
                      M.pl, {'pos': [x0, cy, fz + 0.034]}))
            idx = r * cols + c
            isFeed = r == feedRow
            ssId = spawnIds and spawnIds.get('%s_%s' % (js_str(r), js_str(c)))
            card = _at(opts.get('cards'), idx)
            if card is None:
                if isFeed:
                    card = feeds[c % 4]
                elif ssId:
                    card = 'snow'
                else:
                    card = canned[cannedN % len(canned)]
                    cannedN += 1
            screen = scr(game, sW, sH, {
                'card': card,
                'group': nn(_at(opts.get('groups'), idx), 'scr_mc_feeds' if isFeed else 'scr_mc_canned'),
                'id': ssId or 'mcwall_r%sc%s' % (js_str(r), js_str(c)), 'dome': 0.03 * k,
                'seg': [10, 8] if k > 1.1 else None,
            })
            screen.position.set(x0, cy, fz + 0.03)
            g.add(screen)
            # side furniture: two lamp keys left, LED bar + knob right, centred in the strip between the opening
            # and the post
            side = (sW / 2 + 0.03 + cw / 2 - post) / 2
            lx, rx = x0 + side, x0 - side  # lamp keys on the viewer's left, meter on the right
            for i in range(2):
                on = rnd() < 0.6
                colr = ['green', 'amber', 'red', 'white'][int(math.floor(rnd() * 4))]
                g.add(K.m(lw(keycap(0.06, 0.045, 0.014, 0.005), colr) if on else
                          sw(keycap(0.06, 0.045, 0.014, 0.005), 'lampWhite'), M.lit if on else M.pl,
                          {'pos': [lx, cy + 0.08 * k - i * 0.15 * k, fz], 'rot': [-HP, 0, 0]}))
            g.add(K.m(decal('vuBar', 0.045 * kw, 0.2 * k), M.lit, {'pos': [rx, cy + 0.06 * k, fz - 0.001]}))
            for mm in knob(M, 0.018 * kw, [rx, cy - 0.15 * k, fz], {'color': 'ink', 'skirt': False, 'rot': rnd() * 3,
                                                                   'seg': 8}):
                g.add(mm)
    g.userData.colliders = [{'min': [-W / 2, 0, -D / 2], 'max': [W / 2, H + 0.05, D / 2]}]
    return done(game, g)


registerProp('bc_monitor_wall', _monitor_wall, {
    'category': 'broadcast', 'tags': ['monitor', 'crt', 'screen', 'master_control', 'wall', 'hero'],
    'size': [6.5, 3.55, 0.54], 'hero': True,
    'desc': 'MC monitor wall: 4x3 big CRTs flush in brushed racks, lamp keys, LED meters, column labels. 12 screens: '
            'middle row scr_mc_feeds, top + bottom rows scr_mc_canned; ids mcwall_r{row}c{col}, bottom corners ss_mc_w '
            '/ ss_mc_e. opts {cols, rows, band, cellW, cellH, base, screenW, screenH, feedRow, spawnIds:false, '
            'labels[], cards[], groups[]}'})


# ---------------------------------------------------------------------------------- ON AIR light box
def signBox(game, g, M, o):
    W, H, D, cellName, lit = o['W'], o['H'], o['D'], o['cellName'], o['lit']
    frameC, bezel = o.get('frameC', 'ink'), o.get('bezel', True)
    g.add(K.m(sw(K.box(W, H, D, min(0.05, H * 0.22)), frameC), M.pl, {'pos': [0, H / 2, 0]}))
    if bezel:
        g.add(K.m(frame(W - 0.02, H - 0.02, 0.032, 0.022, min(0.045, H * 0.2), 0.02), M.ch,
                  {'pos': [0, H / 2, -D / 2 - 0.004]}))
    faceGeo = cu(K.box(W - 0.075, H - 0.075, 0.016, 0.008), cellName)
    lamp = K.m(faceGeo, M.sign if lit else M.dim, {'pos': [0, H / 2, -D / 2 - 0.0], 'name': 'lamp'})
    lamp.userData.noMerge = True
    lamp.userData.noOcclude = True
    g.add(lamp)
    parts = JSObj(g.userData.parts or {})
    parts['lamp'] = lamp
    g.userData.parts = parts
    g.userData.lampMats = {'on': M.sign, 'off': M.dim}
    return lamp


def _on_air(game, opts=None):
    opts = {} if opts is None else opts
    g = K.prop('bc_on_air')
    M = mats(game)
    W, H, D = 0.64, 0.24, 0.13
    lit = _truthy(opts.get('lit'))
    signBox(game, g, M, {'W': W, 'H': H, 'D': D, 'cellName': 'onair', 'lit': lit})
    # wall brackets + conduit up the wall
    for s in (-1, 1):
        g.add(K.m(sw(K.box(0.04, 0.12, 0.04, 0.012), 'charcoal'), M.pl, {'pos': [s * (W / 2 - 0.08), H / 2, D / 2 + 0.005]}))
    g.add(K.m(K.cyl(0.013, 0.013, 0.34, {'bevel': 0.003, 'seg': 8}), M.ch, {'pos': [W / 2 - 0.1, H - 0.02, D / 2 - 0.02]}))
    g.add(K.m(sw(K.box(0.05, 0.05, 0.04, 0.012), 'charcoal'), M.pl, {'pos': [W / 2 - 0.1, H + 0.005, D / 2 - 0.02]}))
    # little visor above the face
    g.add(K.m(sw(K.box(W - 0.02, 0.018, 0.07, 0.008), 'ink'), M.pl, {'pos': [0, H - 0.01, -D / 2 - 0.03],
                                                                      'rot': [0.18, 0, 0]}))
    if lit and opts.get('anchor'):
        g.userData.lightAnchors = [{'pos': [0, H / 2, -0.4], 'color': PAL.onAirRed, 'intensity': 0.8, 'distance': 2.5}]
    g.userData.colliders = []
    return done(game, g)


registerProp('bc_on_air', _on_air, {
    'category': 'broadcast', 'tags': ['sign', 'on_air', 'wall', 'lamp'], 'size': [0.64, 0.58, 0.2],
    'desc': 'wall ON AIR light box (back at z=+0.065): chrome bezel, red face = parts.lamp; lampMats {on, off}. opts '
            '{lit=false, anchor}'})


# ---------------------------------------------------------------------------------- APPLAUSE light box
def _applause(game, opts=None):
    opts = {} if opts is None else opts
    g = K.prop('bc_applause')
    M = mats(game)
    W, H, D = 1.5, 0.42, 0.2
    lit = opts.get('lit') is not False
    lamp = signBox(game, g, M, {'W': W, 'H': H, 'D': D, 'cellName': 'applause', 'lit': lit, 'frameC': 'charcoal'})
    lamp.scale.set(1, 0.86, 1)
    # marquee bulbs around the face (part 'bulbs')
    bulbs = THREE.Group()
    bulbs.userData.noMerge = True
    bgeo = lw(lowSphere(0.02, 6, 4), 'tungsten')
    n = 14
    for i in range(n):
        x = -W / 2 + 0.08 + (i / (n - 1)) * (W - 0.16)
        for y in [H - 0.028, 0.028]:
            bulbs.add(K.m(bgeo, M.lit if lit else M.dim, {'pos': [x, y, -D / 2 - 0.018]}))
    for s in (-1, 1):
        for y in [0.14, 0.28]:
            bulbs.add(K.m(bgeo, M.lit if lit else M.dim, {'pos': [s * (W / 2 - 0.03), y, -D / 2 - 0.018]}))
    g.add(bulbs)
    # hanging chains to the grid
    chain = nn(opts.get('chain'), 0.7)
    for s in (-1, 1):
        g.add(K.m(sw(bcyl(0.022, 0.022, 0.03, 0.006, 10), 'ink'), M.pl, {'pos': [s * (W / 2 - 0.15), H, 0]}))
        links = js_round(chain / 0.06)
        for i in range(int(links)):
            l_ = K.m(K.tube(ring(0.018, 6), 0.0045, {'seg': 6, 'radial': 3, 'closed': True}), M.ch,
                     {'pos': [s * (W / 2 - 0.15), H + 0.045 + i * 0.06, 0]})
            l_.rotation.set(HP, HP if i % 2 else 0, 0)
            l_.scale.set(1, 1.7, 1)
            g.add(l_)
    g.userData.parts = {'lamp': lamp, 'bulbs': bulbs}
    if lit and opts.get('anchor'):
        g.userData.lightAnchors = [{'pos': [0, H / 2, -0.6], 'color': '#FF6A50', 'intensity': 1.2, 'distance': 4}]
    g.userData.colliders = []
    return done(game, g, {'mergeParts': [bulbs]})


registerProp('bc_applause', _applause, {
    'category': 'broadcast', 'tags': ['sign', 'applause', 'studio_a', 'lamp', 'hanging', 'ee'], 'size': [1.5, 1.15, 0.24],
    'hero': True,
    'desc': 'hanging APPLAUSE box: marquee bulbs (parts.bulbs), face = parts.lamp; y=0 is the box bottom, chains rise '
            'opts.chain (0.7 m). opts {lit=true, chain, anchor}'})

# ---------------------------------------------------------------------------------- lamp helper (engine API)
# setLamp(prop, state, partName = 'lamp'): state 'on' | 'off' | a LIT color name (red amber green blue white
# yellow cyan magenta orange tungsten purple). Color changes rewrite the lamp's UVs (LITUV[color][0..1]) on its own
# geometry copy. Runtime helper: implemented by the Godot props runtime (not part of the static asset).
LAMP_COLORS = list(LIT.keys())


# ---------------------------------------------------------------------------------- quad 2-inch VTR
# A reel group (flanges with the printed aluminum face, tape pack, hub), axis along z, front face at z = 0.
def tapeReel(M, r=0.18, o=None):
    o = o or {}
    grp = THREE.Group()
    grp.userData.noMerge = True
    depth, pack = nn(o.get('depth'), 0.055), nn(o.get('pack'), 0.72)
    rs = 22 if r < 0.12 else 32
    grp.add(K.m(discDecal('reel', r, rs), M.me, {'pos': [0, 0, -0.001]}))
    grp.add(K.m(cu(THREE.CircleGeometry(r, rs), 'reel'), M.me, {'pos': [0, 0, depth]}))
    for z in ([-0.002] if r < 0.12 else [-0.002, depth + 0.001]):
        grp.add(K.m(sw(K.tube(ring(r, 20), 0.0045, {'seg': 22, 'radial': 3, 'closed': True}), 'steel'), M.me,
                    {'pos': [0, 0, z], 'rot': [HP, 0, 0]}))
    grp.add(K.m(sw(lowCyl(r * pack, depth - 0.006, 20), 'tape'), M.pl, {'pos': [0, 0, 0.003], 'rot': [HP, 0, 0]}))
    grp.add(K.m(sw(L([[0, 0], [r * 0.24, 0], [r * 0.24, 0.012], [r * 0.18, 0.02], [0, 0.02]], 0, 12), 'silver'), M.me,
                {'pos': [0, 0, -0.001], 'rot': [-HP, 0, 0]}))
    if o.get('label'):
        grp.add(K.m(discDecal('reelLabel', r * 0.17, 20), M.pl, {'pos': [0, 0, -0.023]}))
    return grp


# spindle with three lock tabs (bare = conspicuous), axis along -z from the deck plate
def spindle(M):
    grp = THREE.Group()
    grp.userData.noMerge = True
    grp.add(K.m(sw(L([[0, 0], [0.05, 0], [0.05, 0.012], [0.026, 0.02], [0.024, 0.075], [0.03, 0.08], [0.02, 0.095],
                      [0, 0.097]], 0.004, 16), 'silver'), M.me, {'rot': [-HP, 0, 0]}))
    for i in range(3):
        t = K.m(sw(cbox(0.016, 0.034, 0.016, 0.004), 'silver'), M.me, {})
        a = (i / 3) * TAU
        t.position.set(math.cos(a) * 0.03, math.sin(a) * 0.03, -0.075)
        t.rotation.z = a - HP
        grp.add(t)
    return grp


# VU meter: soft-lit face in a bezel + needle (part), facing -z; returns { meshes, needle }
def vuMeter(M, w, p, o=None):
    o = o or {}
    h = w * 0.5
    out = []
    out.append(K.m(sw(frame(w + 0.024, h + 0.024, 0.014, 0.02, 0.012, 0.005, {'lite': True}), nn(o.get('bezel'), 'ink')),
                   M.pl, {'pos': [p[0], p[1], p[2] - 0.008]}))
    out.append(K.m(decal('vu', w, h), M.soft, {'pos': [p[0], p[1], p[2] - 0.004]}))
    needle = K.m(sw(cbox(0.003, h * 0.78, 0.002, 0.0008), 'black'), M.pl, {})
    pivot = THREE.Group()
    pivot.position.set(p[0], p[1] - h * 0.5, p[2] - 0.007)
    needle.position.set(0, h * 0.39, 0)
    pivot.rotation.z = nn(o.get('angle'), 0.25)
    pivot.add(needle)
    if o.get('part'):
        pivot.userData.noMerge = True
    out.append(pivot)
    return JSObj(meshes=out, needle=pivot)


def _vtr_quad(game, opts=None):
    opts = {} if opts is None else opts
    g = K.prop('bc_vtr_quad')
    M = mats(game)
    bodyC, accC, deckC = nn(opts.get('color'), 'ivory'), nn(opts.get('accent'), 'teal'), 'gunmetal'
    reels = opts.get('reels') is not False
    W, H, D = 1.16, 1.92, 0.8
    fz = -D / 2
    # cabinet: plinth, main body, accent cheeks, overhanging top cap
    g.add(K.m(sw(cbox(W - 0.08, 0.08, D - 0.08, 0.01), 'black'), M.pl, {'pos': [0, 0.04, 0.02]}))
    g.add(K.m(sw(K.box(W - 0.1, H - 0.1, D, 0.05), bodyC), M.pl, {'pos': [0, 0.07 + (H - 0.1) / 2, 0]}))
    for s in (-1, 1):
        g.add(K.m(sw(K.box(0.07, H - 0.07, D + 0.02, 0.03), accC), M.pl,
                  {'pos': [s * (W / 2 - 0.035), 0.07 + (H - 0.07) / 2, 0]}))
    g.add(K.m(sw(K.box(W + 0.02, 0.05, D + 0.05, 0.022, {'seg': 1}), 'charcoal'), M.pl, {'pos': [0, H + 0.02, 0]}))
    # lower doors with vents, chrome pulls, nameplate + number
    for s in (-1, 1):
        g.add(K.m(sw(K.extrude(K.roundRect(0.47, 0.64, 0.035), 0.022, {'bevel': 0.008, 'curveSeg': 3, 'bevelSeg': 1}),
                     bodyC), M.pl, {'pos': [s * 0.25, 0.46, fz - 0.009]}))
        g.add(K.m(decal('vent', 0.3, 0.2), M.pl, {'pos': [s * 0.25, 0.3, fz - 0.0205]}))
        g.add(K.m(K.tube([[s * 0.04, 0.58, fz - 0.02], [s * 0.04, 0.58, fz - 0.05], [s * 0.04, 0.68, fz - 0.05],
                          [s * 0.04, 0.68, fz - 0.02]], 0.008, {'seg': 8, 'radial': 5}), M.ch))
    g.add(K.m(decal('pl_QUADRAMAX', 0.3, 0.056), M.pl, {'pos': [-0.25, 0.66, fz - 0.0205]}))
    g.add(K.m(decal('vtr' + js_str(nn(opts.get('num'), 1)), 0.16, 0.06), M.pl, {'pos': [0.25, 0.66, fz - 0.0205]}))
    # control ledge: sloped strip with transport keys, timecode, TRACKING knob (part)
    ly = 0.86
    g.add(K.m(sw(K.box(W - 0.14, 0.09, 0.2, 0.03), 'charcoal'), M.pl, {'pos': [0, ly, fz - 0.06], 'rot': [-0.35, 0, 0]}))
    ledge = THREE.Group()
    ledge.position.set(0, ly + 0.045 * math.cos(0.35), fz - 0.06 - 0.045 * math.sin(0.35))
    ledge.rotation.x = -0.35
    g.add(ledge)
    keyC = [['lampWhite', 0], ['green', 1], ['lampRed', 0], ['lampWhite', 0], ['red', 1 if _truthy(opts.get('rec')) else 0]]
    for i, (c, on) in enumerate(keyC):
        ledge.add(K.m(lw(keycap(0.065, 0.06, 0.02, 0.006), c) if on else sw(keycap(0.065, 0.06, 0.02, 0.006), c),
                      M.lit if on else M.pl, {'pos': [-0.42 + i * 0.078, 0.0, 0.02]}))
    ledge.add(K.m(cu(THREE.PlaneGeometry(0.38, 0.036).rotateX(-HP), 'keys'), M.pl, {'pos': [-0.265, 0.002, -0.058]}))
    ledge.add(K.m(cu(THREE.PlaneGeometry(0.16, 0.04).rotateX(-HP), 'digits'), M.lit, {'pos': [0.03, 0.002, 0.0]}))
    ledge.add(K.m(cu(THREE.CircleGeometry(0.078, 28).rotateX(-HP), 'dialTrk'), M.pl, {'pos': [0.33, 0.002, 0]}))
    knobG = THREE.Group()
    knobG.position.set(0.33, 0.002, 0)
    knobG.rotation.y = nn(opts.get('track'), 3) * -0.48  # 13 detents
    knobG.userData.noMerge = True
    knobG.add(K.m(sw(L([[0, 0], [0.05, 0], [0.05, 0.012], [0.042, 0.02], [0.04, 0.05], [0.032, 0.058], [0, 0.058]], 0,
                       16), 'ink'), M.pl))
    knobG.add(K.m(sw(cbox(0.012, 0.012, 0.05, 0.003), 'red'), M.pl, {'pos': [0, 0.058, -0.022]}))
    knobG.add(K.m(sw(lowCyl(0.03, 0.004, 14), 'silver'), M.me, {'pos': [0, 0.058, 0]}))
    ledge.add(knobG)
    # tape deck: inset gunmetal panel, reels or bare spindles, head block, tape path
    dy, rx, rr0 = 1.26, 0.3, 0.18
    g.add(K.m(sw(K.box(W - 0.2, 0.62, 0.03, 0.03), deckC), M.pl, {'pos': [0, dy, fz - 0.006]}))
    g.add(K.m(K.tube(rectLoopXY(W - 0.19, 0.61, 0.03), 0.006, {'seg': 32, 'radial': 4, 'closed': True}), M.ch,
              {'pos': [0, dy, fz - 0.02]}))
    spL, spR = spindle(M), spindle(M)
    spL.position.set(-rx, dy + 0.04, fz - 0.021)
    spR.position.set(rx, dy + 0.04, fz - 0.021)
    if not reels:  # bare spindles must read from across MC (EE step 5)
        spL.scale.setScalar(1.5)
        spR.scale.setScalar(1.5)
    g.add(spL, spR)
    reelL = reelR = None
    if reels:
        reelL, reelR = tapeReel(M, rr0, {'pack': 0.8}), tapeReel(M, rr0, {'pack': 0.5})
        reelL.position.set(-rx, dy + 0.04, fz - 0.1)
        reelR.position.set(rx, dy + 0.04, fz - 0.1)
        reelL.rotation.z = 0.4
        reelR.rotation.z = 1.3
        g.add(reelL, reelR)
    # head assembly: chrome block with the rotary head drum + guide rollers
    g.add(K.m(sw(K.box(0.24, 0.13, 0.08, 0.02), 'silver'), M.me, {'pos': [0, dy - 0.2, fz - 0.05]}))
    g.add(K.m(bcyl(0.045, 0.045, 0.05, 0.006, 16), M.ch, {'pos': [0, dy - 0.2, fz - 0.09], 'rot': [-HP, 0, 0]}))
    g.add(K.m(sw(cbox(0.06, 0.03, 0.02, 0.006), 'red'), M.pl, {'pos': [0, dy - 0.13, fz - 0.09]}))
    for s in (-1, 1):
        g.add(K.m(bcyl(0.018, 0.018, 0.07, 0.004, 10), M.ch, {'pos': [s * 0.17, dy - 0.2, fz - 0.02], 'rot': [-HP, 0, 0]}))
    if reels:
        tz, tc = fz - 0.13, 'tapeGold'

        def band(a, b):
            va, vb = THREE.Vector3(*a), THREE.Vector3(*b)
            ln = va.distanceTo(vb)
            me = K.m(sw(cbox(0.004, ln, 0.05, 0.001), tc), M.pl)
            me.position.copy(va).lerp(vb, 0.5)
            me.rotation.z = math.atan2(vb.y - va.y, vb.x - va.x) - HP
            return me
        g.add(band([-rx - 0.02, dy + 0.04 - rr0 * 0.8, tz], [-0.18, dy - 0.2, tz]))
        g.add(band([-0.18, dy - 0.215, tz], [0.18, dy - 0.215, tz]))
        g.add(band([0.18, dy - 0.2, tz], [rx + 0.02, dy + 0.04 - rr0 * 0.5, tz]))
    # meter bridge: slanted panel, 2 VU meters (needle parts), monitor, status lamp (part)
    my = 1.72
    g.add(K.m(sw(K.box(W - 0.14, 0.34, 0.1, 0.03), 'charcoal'), M.pl, {'pos': [0, my, fz + 0.03], 'rot': [0.12, 0, 0]}))
    bridge = THREE.Group()
    bridge.position.set(0, my, fz - 0.02)
    bridge.rotation.x = 0.12
    g.add(bridge)
    vuL = vuMeter(M, 0.16, [-0.38, 0.02, 0], {'angle': 0.35, 'part': True})
    vuR = vuMeter(M, 0.16, [-0.17, 0.02, 0], {'angle': -0.1, 'part': True})
    for mm in vuL.meshes + vuR.meshes:
        bridge.add(mm)
    mon = monitorUnit(game, M, {'w': 0.34, 'h': 0.27, 'd': 0.24, 'case': 'ink', 'face': 'charcoal',
                                'card': nn(opts.get('card'), 'snow' if opts.get('group') == 'scr_vtr2' else 'station_id'),
                                'group': opts.get('group'), 'id': opts.get('id'), 'knobs': 2, 'plate': False,
                                'tally': False})
    mon.group.position.set(0.3, -0.145, 0.02)
    bridge.add(mon.group)
    for i in range(4):
        bridge.add(K.m((sw if i == 3 else lw)(cbox(0.03, 0.02, 0.012, 0.004), ['green', 'amber', 'green', 'lampRed'][i]),
                       M.pl if i == 3 else M.lit, {'pos': [-0.44 + i * 0.05, -0.11, -0.012]}))
    bridge.add(K.m(decal('lbl_AUDIO', 0.16, 0.04), M.pl, {'pos': [-0.275, 0.13, -0.004]}))
    # status beacon on the top cap
    g.add(K.m(sw(L([[0, 0], [0.06, 0], [0.062, 0.02], [0.05, 0.03], [0, 0.03]], 0.005, 14), 'charcoal'), M.pl,
              {'pos': [0.42, H + 0.045, -0.2]}))
    lampColor = nn(opts.get('lamp'), 'green')
    lamp = K.m(lw(L([[0, 0], [0.045, 0], [0.045, 0.02], [0.04, 0.06], [0.024, 0.085], [0, 0.09]], 0.012, 14),
                  'amber' if lampColor == 'off' else lampColor), M.dim if lampColor == 'off' else M.lit,
               {'pos': [0.42, H + 0.072, -0.2], 'name': 'lamp'})
    lamp.userData.noMerge = True
    g.add(lamp)
    # cable bundle out the back
    g.add(K.m(sw(K.tube([[-0.3, 0.5, D / 2 - 0.02], [-0.3, 0.2, D / 2 + 0.08], [-0.25, 0.03, D / 2 + 0.2],
                         [-0.1, 0.025, D / 2 + 0.45]], 0.025, {'seg': 14, 'radial': 6}), 'ink'), M.pl))
    g.userData.parts = {'lamp': lamp, 'reelL': reelL, 'reelR': reelR, 'spindleL': spL, 'spindleR': spR,
                        'needleL': vuL.needle, 'needleR': vuR.needle, 'trackingKnob': knobG}
    g.userData.lampMats = {'on': M.lit, 'off': M.dim}
    g.userData.colliders = [{'min': [-W / 2 - 0.01, 0, fz - 0.14], 'max': [W / 2 + 0.01, H + 0.1, D / 2 + 0.03]}]
    g.userData.interact = {'point': [0, 1.1, fz - 0.45], 'radius': 1.5}
    return done(game, g, {'mergeParts': [reelL, reelR, spL, spR, knobG]})


registerProp('bc_vtr_quad', _vtr_quad, {
    'category': 'broadcast', 'tags': ['vtr', 'tape', 'master_control', 'ee', 'hero', 'screen'],
    'size': [1.18, 2.03, 0.95], 'hero': True,
    'desc': 'fridge-sized quad 2" VTR: reels (parts reelL/R, spin about z), spindles, VU needles, TRACKING knob, '
            'status lamp (setLamp), monitor. opts {reels=true, lamp:green|amber|purple|red|off, num 1-3, group '
            '(scr_vtr2 for #2), card, id, rec}'})

# ---------------------------------------------------------------------------------- MC console segments
# Shared side profile (z, y): recessed kick, front, armrest lip, sloped work panel, turret. Width along x.
CON = {'D': 0.96, 'slope': [[-0.38, 0.78], [0.08, 0.93]], 'turret': [[0.12, 0.95], [0.16, 1.2]], 'topY': 1.22}
CON_PROFILE = [[-0.4, 0], [0.47, 0], [0.47, 1.2], [0.44, 1.23], [0.16, 1.22], [0.1, 0.95], [0.08, 0.93], [-0.38, 0.78],
               [-0.44, 0.76], [-0.47, 0.72], [-0.47, 0.12], [-0.4, 0.1]]
SLOPE_A = math.atan2(0.93 - 0.78, 0.08 + 0.38)  # ~18 deg


def consoleBody(game, g, M, W, o=None):
    o = o or {}
    bodyC = nn(o.get('color'), 'putty')
    geo = K.extrude(CON_PROFILE, W, {'bevel': 0.018, 'round': 0.025, 'curveSeg': 2, 'bevelSeg': 1}).rotateY(-HP)
    taper_ = o.get('taper')
    if taper_:  # corner wedge: scale x by depth
        p = geo.attributes.position
        for i in range(p.count):
            t = (p.getZ(i) + 0.47) / 0.94
            p.setX(i, p.getX(i) * (taper_[0] + (taper_[1] - taper_[0]) * t))
        geo.computeVertexNormals()
    g.add(K.m(sw(geo, bodyC), M.pl))
    wood = woodMat(game)

    def wf(z):
        return taper_[0] + (taper_[1] - taper_[0]) * ((z + 0.47) / 0.94) if taper_ else 1
    # vinyl armrest + walnut kick trim + walnut turret top
    vinyl = K.mat(game, 'vinyl', '#ffffff', {'map': K.tex.pebble(nn(o.get('vinyl'), '#8A3A22'))})
    g.add(K.m(K.cushion(W * wf(-0.43) - 0.01, 0.075, 0.13, {'puff': 0.012, 'seg': [6, 2, 3]}), vinyl,
              {'pos': [0, 0.785, -0.42]}))
    g.add(K.m(K.box(W * wf(-0.47) - 0.01, 0.06, 0.03, 0.01, {'uv': 1.5, 'swap': True}), wood, {'pos': [0, 0.69, -0.475]}))
    g.add(K.m(K.box(W * wf(0.3) - 0.01, 0.03, 0.34, 0.01, {'uv': 1.5, 'swap': True}), wood, {'pos': [0, 1.235, 0.3]}))
    # panel plates (charcoal) on the slope and turret
    slope = THREE.Group()
    slope.position.set(0, 0.855 + 0.008, -0.15)
    slope.rotation.x = -SLOPE_A
    g.add(slope)
    slope.add(K.m(sw(cbox(W * wf(-0.15) - 0.1, 0.012, 0.44, 0.005), 'charcoal'), M.pl))
    turret = THREE.Group()
    ta = math.atan2(0.06, 0.27)
    turret.position.set(0, 1.085, 0.13)
    turret.rotation.x = ta
    g.add(turret)
    turret.add(K.m(sw(cbox(W * wf(0.13) - 0.1, 0.22, 0.012, 0.005), 'charcoal'), M.pl, {'pos': [0, 0, -0.004]}))
    return JSObj(slope=slope, turret=turret, wood=wood)


# face-up items on the slope group: y up = panel normal, -z = toward the operator
def consoleCommon(g):
    g.userData.colliders = [{'min': [-g.userData['__w'] / 2, 0, -0.5], 'max': [g.userData['__w'] / 2, 1.25, 0.48]}]
    del g.userData['__w']


def _console_switcher(game, opts=None):
    opts = {} if opts is None else opts
    g = K.prop('bc_console_switcher')
    M = mats(game)
    W = nn(opts.get('width'), 1.2)
    cb = consoleBody(game, g, M, W, opts)
    slope, turret = cb.slope, cb.turret
    rnd = mulberry32(77)
    # three buses x 10 chunky keys; one lit per bus (PGM red, PST green, EFX amber)
    bus = [['red', 'lampWhite', -0.13], ['green', 'lampWhite', -0.03], ['amber', 'beige', 0.07]]
    for bi, (litC, offC, z) in enumerate(bus):
        litIdx = [2, 5, 7][bi]
        for i in range(10):
            x = -0.43 + i * 0.068
            on = i == litIdx
            slope.add(K.m(lw(keycap(0.052, 0.052, 0.022, 0.007), litC) if on else
                          sw(keycap(0.052, 0.052, 0.022, 0.007), 'sky' if rnd() < 0.15 else offC),
                          M.lit if on else M.pl, {'pos': [x, 0.006, z]}))
        slope.add(K.m(cu(THREE.PlaneGeometry(0.66, 0.024).rotateX(-HP), 'bus'), M.pl, {'pos': [-0.12, 0.0075, z - 0.042]}))
    # T-bar fader (part 'tbar' pivots about x) in a slotted plate
    slope.add(K.m(sw(cbox(0.13, 0.014, 0.3, 0.006), 'ink'), M.pl, {'pos': [0.44, 0.008, -0.02]}))
    slope.add(K.m(sw(THREE.PlaneGeometry(0.03, 0.24).rotateX(-HP), 'black'), M.pl, {'pos': [0.44, 0.0155, -0.02]}))
    tbar = THREE.Group()
    tbar.position.set(0.44, 0.01, -0.02)
    tbar.rotation.x = nn(opts.get('tbar'), 0.35)
    tbar.userData.noMerge = True
    tbar.add(K.m(bcyl(0.011, 0.011, 0.2, 0.003, 8), M.ch))
    tbar.add(K.m(K.tube([[-0.09, 0.2, 0], [0.09, 0.2, 0]], 0.02, {'seg': 2, 'radial': 10}), M.ch))
    for s in (-1, 1):
        tbar.add(K.m(sw(K.tube([[s * 0.03, 0.2, 0], [s * 0.1, 0.2, 0]], 0.026, {'seg': 2, 'radial': 10}), 'black'), M.pl))
    for s in (-1, 1):
        tbar.add(K.m(sw(lowSphere(0.026, 10, 6), 'black'), M.pl, {'pos': [s * 0.1, 0.2, 0]}))
    slope.add(tbar)
    # joystick positioner + wipe pattern keys
    slope.add(K.m(sw(L([[0, 0], [0.04, 0], [0.042, 0.01], [0.02, 0.022], [0, 0.024]], 0.004, 12), 'ink'), M.pl,
                  {'pos': [-0.42, 0.006, 0.16]}))
    slope.add(K.m(K.cyl(0.006, 0.006, 0.07, {'bevel': 0.002, 'seg': 6}), M.ch, {'pos': [-0.42, 0.02, 0.16],
                                                                               'rot': [0.2, 0, 0.15]}))
    slope.add(K.m(sw(lowSphere(0.017, 10, 6), 'red'), M.pl, {'pos': [-0.411, 0.088, 0.174]}))
    for i in range(6):
        slope.add(K.m((lw if i == 2 else sw)(keycap(0.04, 0.04, 0.016, 0.005), 'cyan' if i == 2 else 'light'),
                      M.lit if i == 2 else M.pl, {'pos': [-0.3 + i * 0.05, 0.006, 0.16]}))
    # turret: 2 round meters, lit status keys, labels
    for x, c in [[-0.4, 'meterRound'], [-0.26, 'meterRound']]:
        turret.add(K.m(sw(L([[0.05, 0], [0.058, 0], [0.058, 0.012], [0.05, 0.012]], 0, 16), 'silver'), M.pl,
                       {'pos': [x, 0.02, -0.01], 'rot': [-HP, 0, 0]}))
        turret.add(K.m(discDecal(c, 0.05, 20), M.soft, {'pos': [x, 0.02, -0.012]}))
    for i, t in enumerate(['AIR', 'LINE', 'SYNC']):
        airOff = i == 0 and not _truthy(opts.get('onAir'))
        turret.add(K.m((sw if airOff else lw)(keycap(0.07, 0.05, 0.014, 0.005),
                                             'lampRed' if airOff else ['red', 'green', 'amber'][i]).clone().rotateX(-HP),
                       M.pl if airOff else M.lit, {'pos': [-0.05 + i * 0.12, 0.04, -0.01]}))
        turret.add(K.m(decal('lbl_' + t, 0.09, 0.0225), M.pl, {'pos': [-0.05 + i * 0.12, -0.03, -0.0112]}))
    turret.add(K.m(decal('pl_MASTER', 0.2, 0.0375), M.pl, {'pos': [0.4, 0.06, -0.0112]}))
    turret.add(K.m(decal('digits', 0.16, 0.04), M.lit, {'pos': [0.4, -0.02, -0.0112]}))
    g.userData.parts = {'tbar': tbar}
    g.userData['__w'] = W
    consoleCommon(g)
    return done(game, g, {'mergeParts': [tbar]})


registerProp('bc_console_switcher', _console_switcher, {
    'category': 'broadcast', 'tags': ['console', 'switcher', 'master_control', 'island'], 'size': [1.2, 1.25, 0.96],
    'desc': 'MC island segment: vision switcher, 3 buses of chunky lit keys, chrome T-bar (parts.tbar, rot.x), '
            'joystick, turret meters. Segments butt together along x (width 1.2). opts {width, color, vinyl, tbar, '
            'onAir}'})


def _console_audio(game, opts=None):
    opts = {} if opts is None else opts
    g = K.prop('bc_console_audio')
    M = mats(game)
    W = nn(opts.get('width'), 1.2)
    cb = consoleBody(game, g, M, W, opts)
    slope, turret = cb.slope, cb.turret
    rnd = mulberry32(31)
    n = 8
    sp = (W - 0.24) / n
    capC = ['red', 'ivory', 'ivory', 'sky', 'sky', 'ivory', 'gold', 'black']
    for i in range(n):
        x = -W / 2 + 0.16 + i * sp
        for z, c in [[-0.17, 'orange'], [-0.1, 'sky']]:
            slope.add(K.m(sw(L([[0, 0], [0.016, 0], [0.015, 0.018], [0.011, 0.024], [0, 0.024]], 0, 7), 'ink'), M.pl,
                          {'pos': [x, 0.006, z]}))
            slope.add(K.m(sw(lowCyl(0.009, 0.003, 7), c), M.pl, {'pos': [x, 0.03, z]}))
        slope.add(K.m(sw(THREE.PlaneGeometry(0.014, 0.22).rotateX(-HP), 'black'), M.mt, {'pos': [x, 0.0065, 0.07]}))
        slope.add(K.m(sw(keycap(0.04, 0.032, 0.028, 0.007), capC[i]), M.pl, {'pos': [x, 0.006, 0.12 - rnd() * 0.15]}))
        on = rnd() < 0.5
        slope.add(K.m(lw(keycap(0.034, 0.026, 0.012, 0.004), 'amber') if on else
                      sw(keycap(0.034, 0.026, 0.012, 0.004), 'lampAmber'), M.lit if on else M.pl,
                      {'pos': [x, 0.006, -0.04]}))
    # turret: two big VU meters with needles (parts), master knobs
    vA = vuMeter(M, 0.26, [-0.26, 0.0, -0.012], {'angle': 0.3, 'part': True})
    vB = vuMeter(M, 0.26, [0.08, 0.0, -0.012], {'angle': -0.15, 'part': True})
    for mm in vA.meshes + vB.meshes:
        turret.add(mm)
    for mm in knob(M, 0.03, [0.36, 0.02, -0.012], {'color': 'ink', 'rot': 0.4}):
        turret.add(mm)
    turret.add(K.m(decal('pl_AUDIOLUX', 0.16, 0.03), M.pl, {'pos': [0.36, -0.07, -0.0112]}))
    g.userData.parts = {'needleL': vA.needle, 'needleR': vB.needle}
    g.userData['__w'] = W
    consoleCommon(g)
    return done(game, g, {'mergeParts': []})


registerProp('bc_console_audio', _console_audio, {
    'category': 'broadcast', 'tags': ['console', 'audio', 'master_control', 'island'], 'size': [1.2, 1.25, 0.96],
    'desc': 'MC island segment: audio board, 8 fader strips + knobs, 2 big VU meters (parts needleL/needleR, rot.z). '
            'opts {width, color, vinyl}'})


def _console_monitor(game, opts=None):
    opts = {} if opts is None else opts
    g = K.prop('bc_console_monitor')
    M = mats(game)
    W = nn(opts.get('width'), 1.2)
    slope = consoleBody(game, g, M, W, opts).slope
    # two monitors on the turret: preview (color bars, never overridden) + program
    pv = monitorUnit(game, M, {'w': 0.42, 'h': 0.33, 'd': 0.32, 'case': 'charcoal', 'face': 'light', 'card': 'color_bars',
                               'group': nn(opts.get('previewGroup'), 'scr_preview'), 'id': 'mc_preview', 'knobs': 3,
                               'plate': 'lbl_PVW'})
    pv.group.position.set(-0.24, 1.25, 0.28)
    pv.group.rotation.set(-0.08, 0.1, 0)
    pg = monitorUnit(game, M, {'w': 0.42, 'h': 0.33, 'd': 0.32, 'case': 'charcoal', 'face': 'light',
                               'card': nn(opts.get('card'), 'station_id'), 'group': opts.get('group'),
                               'id': nn(opts.get('id'), 'mc_program'), 'knobs': 3, 'plate': 'lbl_PGM'})
    pg.group.position.set(0.24, 1.25, 0.28)
    pg.group.rotation.set(-0.08, -0.1, 0)
    g.add(pv.group, pg.group)
    # slope: intercom panel, clock, a few keys, script clipboard
    rnd = mulberry32(5)
    for r in range(2):
        for i in range(6):
            on = rnd() < 0.3
            slope.add(K.m(lw(keycap(0.045, 0.04, 0.016, 0.005), 'green') if on else
                          sw(keycap(0.045, 0.04, 0.016, 0.005), 'light'), M.lit if on else M.pl,
                          {'pos': [-0.44 + i * 0.058, 0.006, -0.12 + r * 0.06]}))
    slope.add(K.m(sw(K.box(0.24, 0.012, 0.3, 0.006), 'cork'), M.mt, {'pos': [0.3, 0.012, -0.02], 'rot': [0, 0.15, 0]}))
    slope.add(K.m(cu(THREE.PlaneGeometry(0.2, 0.26).rotateX(-HP), 'script'), M.pl, {'pos': [0.3, 0.0195, -0.01],
                                                                                   'rot': [0, 0.15, 0]}))
    slope.add(K.m(K.tube([[0.25, 0.02, -0.15], [0.35, 0.02, -0.165]], 0.006, {'seg': 2, 'radial': 6}), M.ch,
                  {'rot': [0, 0.15, 0]}))
    slope.add(K.m(sw(L([[0, 0], [0.05, 0], [0.05, 0.018], [0.045, 0.024], [0, 0.024]], 0.003, 14), 'ink'), M.pl,
                  {'pos': [-0.02, 0.006, 0.12]}))
    slope.add(K.m(sw(lowCyl(0.018, 0.006, 8), 'red'), M.pl, {'pos': [-0.02, 0.03, 0.12]}))
    g.userData['__w'] = W
    consoleCommon(g)
    return done(game, g)


registerProp('bc_console_monitor', _console_monitor, {
    'category': 'broadcast', 'tags': ['console', 'monitor', 'master_control', 'island', 'screen'],
    'size': [1.2, 1.6, 0.96], 'hero': True,
    'desc': 'MC island segment with preview (color bars, scr_preview, id mc_preview) + program monitors on the turret, '
            'intercom keys, rundown clipboard. opts {width, group, card, id, previewGroup}'})


def _console_corner(game, opts=None):
    opts = {} if opts is None else opts
    g = K.prop('bc_console_corner')
    M = mats(game)
    t = math.tan(math.pi / 8) * 0.94  # 45-degree wedge: front narrower than back
    w0 = nn(opts.get('front'), 0.36)
    w1 = w0 + 2 * t
    W = 1
    o2 = dict(opts)
    o2['taper'] = [w0, w1]
    cb = consoleBody(game, g, M, W, o2)
    slope, turret = cb.slope, cb.turret
    rnd = mulberry32(9)
    for r in range(3):
        for i in range(4):
            on = rnd() < 0.35
            slope.add(K.m(lw(keycap(0.045, 0.045, 0.018, 0.005), ['amber', 'green', 'cyan'][r]) if on else
                          sw(keycap(0.045, 0.045, 0.018, 0.005), 'light'), M.lit if on else M.pl,
                          {'pos': [-0.12 + i * 0.08, 0.006, -0.12 + r * 0.08]}))
    turret.add(K.m(decal('lbl_NET', 0.12, 0.03), M.pl, {'pos': [0, 0.06, -0.0112]}))
    turret.add(K.m(decal('vuBar', 0.04, 0.08), M.lit, {'pos': [-0.08, -0.03, -0.0112]}))
    turret.add(K.m(decal('vuBar', 0.04, 0.08), M.lit, {'pos': [0.08, -0.03, -0.0112]}))
    g.userData.colliders = [{'min': [-w1 / 2, 0, -0.5], 'max': [w1 / 2, 1.25, 0.48]}]
    return done(game, g)


registerProp('bc_console_corner', _console_corner, {
    'category': 'broadcast', 'tags': ['console', 'master_control', 'island', 'corner'], 'size': [1.14, 1.25, 0.96],
    'desc': '45-degree console corner wedge (front width 0.36, back ~1.14): side faces at +-22.5 deg, joins two '
            'segments turned 45 deg apart. opts {front, color, vinyl}'})


def _console_end(game, opts=None):
    opts = {} if opts is None else opts
    g = K.prop('bc_console_end')
    wood = woodMat(game)
    M = mats(game)
    T = 0.05
    geo = K.extrude([[z * 1.02, y + (0.012 if y > 0.5 else 0)] for z, y in CON_PROFILE], T,
                    {'bevel': 0.014, 'round': 0.03, 'curveSeg': 2, 'bevelSeg': 1, 'uv': 1.4}).rotateY(-HP)
    g.add(K.m(geo, wood))
    g.add(K.m(sw(cbox(T + 0.006, 0.07, 0.9, 0.01), 'black'), M.mt, {'pos': [0, 0.035, 0.02]}))
    g.userData.colliders = [{'min': [-T / 2, 0, -0.5], 'max': [T / 2, 1.26, 0.49]}]
    return done(game, g)


registerProp('bc_console_end', _console_end, {
    'category': 'broadcast', 'tags': ['console', 'master_control', 'island'], 'size': [0.05, 1.26, 0.98],
    'desc': 'walnut end cheek for the console island (same profile, 5 cm thick); place at a run end, x = +-(segment '
            'edge + 0.025)'})


# ---------------------------------------------------------------------------------- patch bay rack
def _patch_bay(game, opts=None):
    opts = {} if opts is None else opts
    g = K.prop('bc_patch_bay')
    M = mats(game)
    W, H, D = 0.62, 1.96, 0.66
    fz = -D / 2
    rackC = nn(opts.get('color'), 'charcoal')
    g.add(K.m(sw(K.box(W, H - 0.06, D, 0.035), rackC), M.pl, {'pos': [0, 0.06 + (H - 0.06) / 2, 0]}))
    g.add(K.m(sw(cbox(W - 0.06, 0.06, D - 0.06, 0.01), 'black'), M.mt, {'pos': [0, 0.03, 0.01]}))
    g.add(K.m(sw(K.box(W + 0.02, 0.05, D + 0.02, 0.02, {'seg': 1}), 'ink'), M.pl, {'pos': [0, H, 0]}))
    for s in (-1, 1):
        g.add(K.m(sw(cbox(0.04, H - 0.14, 0.02, 0.006), 'silver'), M.me,
                  {'pos': [s * (W / 2 - 0.05), 0.07 + (H - 0.14) / 2 + 0.02, fz - 0.005]}))
    # stack of 1U/2U panels from the top
    y = H - 0.08

    def panel(h, fn=None):
        nonlocal y
        cy = y - h / 2
        g.add(K.m(sw(cbox(W - 0.08, h - 0.008, 0.012, 0.004), 'slate'), M.pl, {'pos': [0, cy, fz - 0.012]}))
        for s in (-1, 1):
            g.add(K.m(sw(lowCyl(0.006, 0.004, 6), 'silver'), M.pl, {'pos': [s * (W / 2 - 0.05), cy + s * h * 0.25,
                                                                           fz - 0.018], 'rot': [-HP, 0, 0]}))
        if fn:
            fn(cy, h)
        y -= h
    panel(0.1, lambda cy, h: g.add(K.m(decal('vent', 0.4, 0.07), M.pl, {'pos': [0, cy, fz - 0.0185]})))

    def p_sync(cy, h):
        g.add(K.m(decal('lbl_SYNC', 0.14, 0.035), M.pl, {'pos': [-0.14, cy, fz - 0.0185]}))
        for i in range(4):
            g.add(K.m(lw(cbox(0.02, 0.014, 0.01, 0.003), ['green', 'green', 'amber', 'red'][i]),
                      M.dim if i == 3 else M.lit, {'pos': [0.06 + i * 0.045, cy, fz - 0.02]}))
    panel(0.06, p_sync)
    jackRows = []

    def p_jacks(cy, h):
        g.add(K.m(decal('jacks', 0.48, 0.084), M.pl, {'pos': [0, cy, fz - 0.0185]}))
        jackRows.append(cy)
    for i in range(6):
        panel(0.09, p_jacks)

    def p_meters(cy, h):
        for i in range(4):
            g.add(K.m(decal('vuBar', 0.05, 0.12), M.lit, {'pos': [-0.15 + i * 0.1, cy, fz - 0.0185]}))
    panel(0.16, p_meters)

    def p_drawer(cy, h):
        g.add(K.m(sw(cbox(W - 0.1, 0.1, 0.03, 0.008), 'gunmetal'), M.pl, {'pos': [0, cy, fz - 0.025]}))
        g.add(K.m(K.tube([[-0.08, cy, fz - 0.04], [-0.08, cy, fz - 0.07], [0.08, cy, fz - 0.07], [0.08, cy, fz - 0.04]],
                         0.007, {'seg': 8, 'radial': 5}), M.ch))
    panel(0.12, p_drawer)

    def p_plate(cy, h):
        g.add(K.m(decal('pl_KINETRON', 0.22, 0.041), M.pl, {'pos': [0, cy + 0.04, fz - 0.0185]}))
        g.add(K.m(decal('hv', 0.2, 0.0375), M.pl, {'pos': [0, cy - 0.04, fz - 0.0185]}))
    panel(0.2, p_plate)
    panel(max(0.1, y - 0.1), lambda cy, h: g.add(K.m(decal('vent', 0.44, min(0.3, h - 0.04)), M.pl,
                                                     {'pos': [0, cy, fz - 0.0185]})))
    # patch cords: sagging arcs between jacks, colored plugs
    rnd = mulberry32(nn(opts.get('seed'), 4))
    cols = ['red', 'gold', 'wztvBlue', 'avocado', 'orange', 'black', 'red', 'teal']
    n = nn(opts.get('cords'), 6)
    for i in range(n):
        r0 = int(math.floor(rnd() * len(jackRows)))
        r1 = min(len(jackRows) - 1, r0 + 1 + int(math.floor(rnd() * 3)))
        x0 = -0.22 + math.floor(rnd() * 16) * 0.0293
        x1 = -0.22 + math.floor(rnd() * 16) * 0.0293
        y0 = jackRows[r0] + (0.024 if rnd() < 0.5 else -0.024)
        y1 = jackRows[r1] + (0.024 if rnd() < 0.5 else -0.024)
        sag = 0.08 + rnd() * 0.12
        c = cols[i % len(cols)]
        a, b = [x0, y0, fz - 0.05], [x1, y1, fz - 0.05]
        g.add(K.m(sw(K.tube([[x0, y0, fz - 0.03], a, [(x0 + x1) / 2 + (rnd() - 0.5) * 0.1, min(y0, y1) - sag,
                                                       fz - 0.1 - rnd() * 0.05], b, [x1, y1, fz - 0.03]], 0.0055,
                            {'seg': 12, 'radial': 4}), c), M.pl))
        for px, py in [[x0, y0], [x1, y1]]:
            g.add(K.m(sw(lowCyl(0.009, 0.032, 8), c), M.pl, {'pos': [px, py, fz - 0.018], 'rot': [-HP, 0, 0]}))
    g.userData.colliders = [{'min': [-W / 2 - 0.01, 0, fz - 0.12], 'max': [W / 2 + 0.01, H + 0.03, D / 2 + 0.01]}]
    return done(game, g)


registerProp('bc_patch_bay', _patch_bay, {
    'category': 'broadcast', 'tags': ['rack', 'patch', 'master_control'], 'size': [0.64, 1.99, 0.8],
    'desc': '19" rack: 6 patch-jack rows with sagging colored cords, lamp row, LED meters, drawer, vents. opts {cords=7, '
            'seed, color}'})


# ================================================================================================= STUDIO LIGHTS
# Hanging props are built around their pipe/hook at the origin, then lifted so the lowest point sits at y = 0:
# userData.hang = { pipeY } is the pipe center height above the prop origin (place at gridY - pipeY).
def liftToFloor(g):
    g.updateMatrixWorld(True)
    bb = THREE.Box3().setFromObject(g)
    dy = -bb.min.y
    for c in g.children:
        c.position.y += dy
    return dy


HANG_AO = {'ao': {'floor': False, 'height': 0}}


# Fresnel lamp head, pivot (tilt axis x) at the body center, lens toward -z. Returns { head, lens }.
def fresnelHead(M, o=None):
    o = o or {}
    r, ln, bodyC = nn(o.get('r'), 0.13), nn(o.get('len'), 0.3), nn(o.get('color'), 'charcoal')
    gel, lit = nn(o.get('gel'), 'tungsten'), o.get('lit') is not False
    head = THREE.Group()
    prof = [[0, 0], [r * 0.72, 0], [r * 0.86, 0.016], [r * 0.9, 0.04]]
    for i in range(3):
        prof.extend([[r * 1.03, 0.05 + i * 0.03], [r * 0.93, 0.065 + i * 0.03]])
    prof.extend([[r * 0.97, 0.16], [r * 0.97, ln - 0.035], [r * 1.1, ln - 0.025], [r * 1.1, ln], [r * 0.86, ln],
                 [0, ln - 0.004]])
    head.add(K.m(sw(L(prof, 0, 16), bodyC), M.pl, {'pos': [0, 0, ln / 2], 'rot': [-HP, 0, 0]}))
    # stepped fresnel lens (lit)
    lp = [[0, 0.018]]
    for i in range(1, 5):
        rr_ = r * 0.84 * (i / 4)
        lp.extend([[rr_, 0.018 - i * 0.002], [rr_, 0.004 + (4 - i) * 0.002]])
    lp.append([r * 0.84, 0])
    lens = K.m(lw(L(lp, 0, 18), gel), M.lit if lit else M.dim, {'pos': [0, 0, -ln / 2 + 0.006], 'rot': [-HP, 0, 0],
                                                               'name': 'lens'})
    lens.userData.noMerge = True
    lens.userData.noOcclude = True
    head.add(lens)
    # rear vent cap + handle
    head.add(K.m(sw(L([[0, 0], [r * 0.5, 0], [r * 0.52, 0.02], [r * 0.3, 0.035], [0, 0.036]], 0.006, 12), 'ink'), M.pl,
                 {'pos': [0, 0, ln / 2 - 0.004], 'rot': [HP, 0, 0]}))
    head.add(K.m(K.tube([[0, r * 0.55, ln / 2 - 0.02], [0, r * 0.75, ln / 2 + 0.03], [0, r * 0.2, ln / 2 + 0.07],
                         [0, -r * 0.3, ln / 2 + 0.05]], 0.008, {'seg': 10, 'radial': 5}), M.ch))
    # barn doors (4 leaves on a ring)
    bz, open_ = -ln / 2 - 0.012, nn(o.get('open'), 0.55)
    head.add(K.m(sw(K.tube(ring(r * 1.1, 16), 0.01, {'seg': 18, 'radial': 4, 'closed': True}), 'ink'), M.pl,
                 {'pos': [0, 0, bz], 'rot': [HP, 0, 0]}))

    def leaf(sx, sy, sz, px, py, rx, ry):
        pv = THREE.Group()
        pv.position.set(px, py, bz)
        pv.rotation.set(rx, ry, 0)
        pv.add(K.m(sw(cbox(sx, sy, sz, 0.002), 'ink'), M.pl, {'pos': [0, 0, -sz / 2]}))
        head.add(pv)
    leaf(r * 2.1, 0.006, r * 0.95, 0, r * 1.06, open_, 0)
    leaf(r * 2.1, 0.006, r * 0.8, 0, -r * 1.06, -open_, 0)
    leaf(0.006, r * 1.8, r * 0.8, -r * 1.06, 0, 0, open_)
    leaf(0.006, r * 1.8, r * 0.8, r * 1.06, 0, 0, -open_)
    # brand plate on the side
    pl = K.m(decal('pl_LUMEX', 0.13, 0.026), M.pl, {'pos': [r * 0.975 + 0.002, 0, 0.02], 'rot': [0, -HP, 0]})
    head.add(pl)
    return JSObj(head=head, lens=lens, len=ln, r=r)


# yoke (U strap) around a head of radius r, pivot at y = 0; up=true: strap goes over the top (hanging)
def yoke(M, r, up=True, color='charcoal'):
    grp = THREE.Group()
    s = 1 if up else -1
    w, t = r + 0.035, r + 0.1
    grp.add(K.m(sw(K.tube([[-w, 0, 0], [-w, s * t * 0.7, 0], [-w * 0.6, s * t, 0], [w * 0.6, s * t, 0], [w, s * t * 0.7, 0],
                           [w, 0, 0]], 0.013, {'seg': 18, 'radial': 6}), color), M.pl))
    for x in (-1, 1):
        grp.add(K.m(sw(L([[0, 0], [0.032, 0], [0.034, 0.012], [0.024, 0.03], [0, 0.03]], 0.005, 12), 'ink'), M.pl,
                    {'pos': [x * (w + 0.008), 0, 0], 'rot': [0, 0, -x * HP]}))
    return grp


# C-clamp around a grid pipe (pipe center at the origin, pipe along x); optional pipe stub
def cClamp(M, o=None):
    o = o or {}
    grp = THREE.Group()
    pr = 0.024
    grp.add(K.m(sw(cbox(0.05, 0.02, 0.1, 0.005), 'ink'), M.pl, {'pos': [0, pr + 0.012, 0.005]}))
    grp.add(K.m(sw(cbox(0.05, 0.1, 0.02, 0.005), 'ink'), M.pl, {'pos': [0, 0, pr + 0.022]}))
    grp.add(K.m(sw(cbox(0.05, 0.02, 0.05, 0.005), 'ink'), M.pl, {'pos': [0, -pr - 0.02, pr + 0.005]}))
    grp.add(K.m(lowCyl(0.006, 0.06, 6), M.ch, {'pos': [0, -pr - 0.055, -0.005]}))
    grp.add(K.m(K.tube([[-0.03, -pr - 0.06, -0.005], [0.03, -pr - 0.06, -0.005]], 0.005, {'seg': 2, 'radial': 5}), M.ch))
    grp.add(K.m(sw(bcyl(0.012, 0.012, 0.05, 0.003, 8), 'ink'), M.pl, {'pos': [0, -pr - 0.08, 0.005]}))
    if _truthy(o.get('pipe')):
        grp.add(K.m(sw(bcyl(pr, pr, o['pipe'], 0.003, 12), 'silver'), M.me, {'pos': [-o['pipe'] / 2, 0, 0],
                                                                             'rot': [0, 0, -HP]}))
    return grp


def _light_fresnel(game, opts=None):
    opts = {} if opts is None else opts
    g = K.prop('bc_light_fresnel')
    M = mats(game)
    fh = fresnelHead(M, {'gel': opts.get('gel'), 'lit': opts.get('lit'), 'color': opts.get('color')})
    head, ln, r = fh.head, fh.len, fh.r
    tiltG = THREE.Group()
    tiltG.rotation.x = -nn(opts.get('tilt'), 0.6)
    tiltG.add(head)
    tiltG.userData.noMerge = True
    rig = THREE.Group()
    rig.position.y = -0.36
    rig.add(tiltG, yoke(M, r, True))
    g.add(rig)
    clamp = cClamp(M, {'pipe': nn(opts.get('pipe'), 0.5)})
    g.add(clamp)
    g.add(K.m(bcyl(0.012, 0.012, 0.13, 0.003, 8), M.ch, {'pos': [0, -0.24, 0]}))
    # safety cable loop
    g.add(K.m(K.tube([[0.03, 0, 0.03], [0.07, -0.08, 0.03], [0.1, -0.25, 0.02], [r + 0.05, -0.36, 0]], 0.003,
                     {'seg': 12, 'radial': 3}), M.ch))
    dy = liftToFloor(g)
    g.userData.hang = {'pipeY': float(js_to_fixed(dy, 3))}
    t = nn(opts.get('tilt'), 0.6)
    g.userData.aim = {'pos': [0, dy - 0.36, 0], 'dir': [0, -math.sin(t), -math.cos(t)]}
    g.userData.parts = {'head': tiltG, 'lens': next((c for c in head.children if c.name == 'lens'), None)}
    g.userData.lampMats = {'on': M.lit, 'off': M.dim}
    g.userData.colliders = []
    if _truthy(opts.get('anchor')):
        g.userData.lightAnchors = [{'pos': [0, dy - 0.6, -0.3], 'color': LIT.get(nn(opts.get('gel'), 'tungsten')),
                                    'intensity': 3, 'distance': 9}]
    return done(game, g, {'finish': HANG_AO, 'mergeParts': [tiltG]})


registerProp('bc_light_fresnel', _light_fresnel, {
    'category': 'broadcast', 'tags': ['light', 'studio', 'grid', 'hanging'], 'size': [0.5, 0.7, 0.5],
    'desc': 'hanging Fresnel on a yoke + C-clamp (pipe stub along x): barn doors, glowing stepped lens (gel). y=0 lowest '
            'point, userData.hang.pipeY, userData.aim {pos, dir}. parts head (rot.x) / lens (setLamp). opts '
            '{gel:tungsten|magenta|amber|cyan, tilt, lit, pipe, anchor}'})


def _light_scoop(game, opts=None):
    opts = {} if opts is None else opts
    g = K.prop('bc_light_scoop')
    M = mats(game)
    R0, dep = 0.24, 0.24
    head = THREE.Group()
    shell = []
    for i in range(9):
        t = i / 8
        shell.append([R0 * math.sqrt(t) + 0.02, t * dep])
    shell[0] = [0, 0]
    outer = [[0, 0]] + shell[1:] + [[R0 + 0.035, dep + 0.005], [R0 + 0.035, dep + 0.025], [R0 + 0.01, dep + 0.025]]
    head.add(K.m(sw(L(outer, 0.004, 22), nn(opts.get('color'), 'gunmetal')), M.pl, {'pos': [0, 0, dep / 2],
                                                                                 'rot': [-HP, 0, 0]}))
    inner = [[max(0, x - 0.012), y + 0.006] for x, y in shell]
    lining = K.m(lw(L(inner, 0, 22), nn(opts.get('gel'), 'softWhite')), M.dim if opts.get('lit') is False else M.soft,
                 {'pos': [0, 0, dep / 2 - 0.002], 'rot': [-HP, 0, 0], 'name': 'lens'})
    lining.geometry = lining.geometry.clone()
    idx = lining.geometry.index.array
    for i in range(0, len(idx), 3):
        t2 = int(idx[i + 1])
        idx[i + 1] = idx[i + 2]
        idx[i + 2] = t2
    lining.geometry.computeVertexNormals()
    lining.userData.noMerge = True
    lining.userData.noOcclude = True
    head.add(lining)
    head.add(K.m(lw(lowSphere(0.05, 10, 8), 'tungsten'), M.dim if opts.get('lit') is False else M.lit,
                 {'pos': [0, 0, -dep * 0.35]}))
    head.add(K.m(sw(bcyl(0.04, 0.05, 0.06, 0.008, 12), 'ink'), M.pl, {'pos': [0, 0, dep / 2 + 0.05], 'rot': [-HP, 0, 0]}))
    tiltG = THREE.Group()
    tiltG.rotation.x = -nn(opts.get('tilt'), 0.7)
    tiltG.add(head)
    tiltG.userData.noMerge = True
    rig = THREE.Group()
    rig.position.y = -0.42
    rig.add(tiltG, yoke(M, R0 + 0.02, True))
    g.add(rig)
    g.add(cClamp(M, {'pipe': nn(opts.get('pipe'), 0.5)}))
    g.add(K.m(bcyl(0.012, 0.012, 0.1, 0.003, 8), M.ch, {'pos': [0, -0.2, 0]}))
    dy = liftToFloor(g)
    g.userData.hang = {'pipeY': float(js_to_fixed(dy, 3))}
    t = nn(opts.get('tilt'), 0.7)
    g.userData.aim = {'pos': [0, dy - 0.42, 0], 'dir': [0, -math.sin(t), -math.cos(t)]}
    g.userData.parts = {'head': tiltG, 'lens': lining}
    g.userData.lampMats = {'on': M.soft, 'off': M.dim}
    g.userData.colliders = []
    return done(game, g, {'finish': HANG_AO, 'mergeParts': [tiltG]})


registerProp('bc_light_scoop', _light_scoop, {
    'category': 'broadcast', 'tags': ['light', 'studio', 'grid', 'hanging'], 'size': [0.6, 0.8, 0.6],
    'desc': 'hanging scoop floodlight: big bowl with a glowing white lining + bulb, yoke, C-clamp. hang.pipeY / aim like '
            'the Fresnel. opts {tilt, lit, gel, color, pipe}'})


# tripod light stand (floor), top spigot at height h; returns Group
def tripodStand(M, h, o=None):
    o = o or {}
    grp = THREE.Group()
    cy, fr, legC = nn(o.get('collar'), 0.62), nn(o.get('foot'), 0.46), nn(o.get('legColor'), 'charcoal')
    grp.add(K.m(sw(bcyl(0.03, 0.03, 0.09, 0.006, 12), legC), M.pl, {'pos': [0, cy - 0.05, 0]}))
    for i in range(3):
        a = (i / 3) * TAU + nn(o.get('rot'), 0)
        foot = [math.cos(a) * fr, 0.025, math.sin(a) * fr]
        top = [math.cos(a) * 0.035, cy, math.sin(a) * 0.035]
        grp.add(along(lambda l_: sw(bcyl(0.014, 0.014, l_, 0.003, 6), legC), M.pl, foot, top))
        brace0 = [math.cos(a) * fr * 0.55, cy * 0.45, math.sin(a) * fr * 0.55]
        grp.add(along(lambda l_: lowCyl(0.007, l_, 6), M.ch, brace0, [0, cy * 0.3, 0]))
        grp.add(K.m(sw(L([[0, 0], [0.026, 0], [0.024, 0.02], [0.012, 0.03], [0, 0.03]], 0.004, 10), 'rubber'), M.mt,
                    {'pos': [foot[0] * 1.02, 0, foot[2] * 1.02]}))
    grp.add(K.m(sw(bcyl(0.022, 0.022, cy + 0.02, 0.004, 10), legC), M.pl, {'pos': [0, cy * 0.3, 0]}))
    grp.add(K.m(bcyl(0.015, 0.015, h - cy, 0.003, 10), M.ch, {'pos': [0, cy, 0]}))
    grp.add(K.m(sw(bcyl(0.026, 0.026, 0.05, 0.006, 10), legC), M.pl, {'pos': [0, cy + (h - cy) * 0.45, 0]}))
    grp.add(K.m(sw(lowCyl(0.006, 0.05, 6), 'ink'), M.pl, {'pos': [0.03, cy + (h - cy) * 0.45 + 0.025, 0],
                                                         'rot': [0, 0, -HP]}))
    return grp


def _light_tripod(game, opts=None):
    opts = {} if opts is None else opts
    g = K.prop('bc_light_tripod')
    M = mats(game)
    h = nn(opts.get('height'), 1.55)
    g.add(tripodStand(M, h, {'rot': 0.4}))
    fh = fresnelHead(M, {'r': 0.14, 'len': 0.3, 'gel': opts.get('gel'), 'lit': opts.get('lit'),
                         'color': nn(opts.get('color'), 'charcoal')})
    head, r = fh.head, fh.r
    tiltG = THREE.Group()
    tiltG.rotation.x = -nn(opts.get('tilt'), 0.18)
    tiltG.add(head)
    tiltG.userData.noMerge = True
    rig = THREE.Group()
    rig.position.y = h + r + 0.1
    rig.add(tiltG, yoke(M, r, False))
    g.add(rig)
    # power cable down the pole to the floor
    g.add(K.m(sw(K.tube([[0.05, h + r + 0.05, 0.12], [0.06, h - 0.1, 0.06], [0.03, 1.0, 0.03], [0.04, 0.6, 0.05],
                         [0.12, 0.08, 0.2], [0.3, 0.012, 0.45], [0.55, 0.012, 0.5]], 0.009, {'seg': 18, 'radial': 4}),
                 'ink'), M.pl))
    g.userData.parts = {'head': tiltG, 'lens': next((c for c in head.children if c.name == 'lens'), None)}
    g.userData.lampMats = {'on': M.lit, 'off': M.dim}
    g.userData.aim = {'pos': [0, h + r + 0.1, 0], 'dir': [0, -math.sin(nn(opts.get('tilt'), 0.18)),
                                                          -math.cos(nn(opts.get('tilt'), 0.18))]}
    g.userData.colliders = [{'min': [-0.3, 0, -0.3], 'max': [0.3, h + 0.35, 0.3]}]
    if opts.get('anchor') is not False and opts.get('lit') is not False:
        g.userData.lightAnchors = [{'pos': [0, h + r + 0.05, -0.45], 'color': LIT.get(nn(opts.get('gel'), 'tungsten')),
                                    'intensity': 2.2, 'distance': 6}]
    return done(game, g, {'mergeParts': [tiltG]})


registerProp('bc_light_tripod', _light_tripod, {
    'category': 'broadcast', 'tags': ['light', 'studio', 'stand', 'tripod'], 'size': [0.95, 1.95, 0.95],
    'desc': 'Fresnel on a chrome tripod stand: barn doors, lit lens (gel), cable to the floor, point-light anchor in '
            'front. parts head/lens. opts {height, tilt, gel, lit, anchor=true}'})


def _light_softbox(game, opts=None):
    opts = {} if opts is None else opts
    g = K.prop('bc_light_softbox')
    M = mats(game)
    h = nn(opts.get('height'), 1.2)
    # rolling 3-caster stand
    for i in range(3):
        a = (i / 3) * TAU + 0.3
        g.add(along(lambda l_: sw(cbox(0.035, l_, 0.03, 0.008), 'charcoal').translate(0, l_ / 2, 0), M.pl, [0, 0.1, 0],
                    [math.cos(a) * 0.42, 0.08, math.sin(a) * 0.42]))
        c = caster(M, 0.03)
        c.position.set(math.cos(a) * 0.42, 0, math.sin(a) * 0.42)
        g.add(c)
    g.add(K.m(sw(bcyl(0.05, 0.06, 0.08, 0.01, 12), 'charcoal'), M.pl, {'pos': [0, 0.06, 0]}))
    g.add(K.m(sw(bcyl(0.024, 0.024, 0.6, 0.004, 10), 'charcoal'), M.pl, {'pos': [0, 0.12, 0]}))
    g.add(K.m(bcyl(0.017, 0.017, h - 0.7, 0.003, 10), M.ch, {'pos': [0, 0.7, 0]}))
    g.add(K.m(sw(bcyl(0.03, 0.03, 0.05, 0.006, 10), 'charcoal'), M.pl, {'pos': [0, 0.68, 0]}))
    # soft light: tapered painted shell, deep front rim, concave glowing reflector, lamp lip with tube lamps
    W, Hh, D = 0.7, 0.52, 0.34
    shellC = nn(opts.get('color'), 'sand')
    lit = opts.get('lit') is not False
    head = THREE.Group()
    head.rotation.x = -nn(opts.get('tilt'), 0.15)
    head.userData.noMerge = True
    head.add(K.m(sw(K.taper(K.box(W, Hh, D * 0.6, 0.06), {'axis': 'z', 'k': 0.6}), shellC), M.pl, {'pos': [0, 0, 0.04]}))
    head.add(K.m(sw(frame(W + 0.02, Hh + 0.02, 0.04, 0.12, 0.06, 0.03, {'bevel': 0.012}), shellC), M.pl,
                 {'pos': [0, 0, -0.102]}))
    rg = THREE.PlaneGeometry(W - 0.08, Hh - 0.08, 8, 1)
    rp = rg.attributes.position
    for i in range(rp.count):
        x = rp.getX(i) / ((W - 0.08) / 2)
        rp.setZ(i, -0.03 * (1 - x * x))
    rg.rotateY(math.pi)
    refl = K.m(lw(rg, 'softWhite'), M.soft if lit else M.dim, {'pos': [0, 0, -0.1], 'name': 'lens'})
    refl.userData.noMerge = True
    refl.userData.noOcclude = True
    head.add(refl)
    head.add(K.m(sw(cbox(W - 0.05, 0.085, 0.06, 0.02), 'ink'), M.pl, {'pos': [0, -Hh / 2 + 0.065, -0.135]}))
    head.add(K.m(lw(K.tube([[-W / 2 + 0.09, -Hh / 2 + 0.105, -0.12], [W / 2 - 0.09, -Hh / 2 + 0.105, -0.12]], 0.02,
                           {'seg': 2, 'radial': 8}), 'tungsten'), M.lit if lit else M.dim))
    head.add(K.m(K.tube([[-0.1, Hh / 2 + 0.005, 0.0], [-0.08, Hh / 2 + 0.06, 0.0], [0.08, Hh / 2 + 0.06, 0.0],
                         [0.1, Hh / 2 + 0.005, 0.0]], 0.01, {'seg': 10, 'radial': 5}), M.ch))
    head.add(K.m(decal('pl_LUMEX', 0.14, 0.028), M.pl, {'pos': [0.18, Hh / 2 - 0.018, -0.163]}))
    head.add(K.m(decal('vent', 0.2, 0.12), M.pl, {'pos': [0, 0.03, 0.172], 'rot': [0, math.pi, 0]}))
    rig = THREE.Group()
    rig.add(K.m(sw(K.tube([[-W / 2 - 0.035, Hh * 0.05, 0], [-W / 2 - 0.035, -Hh / 2 - 0.05, 0], [0, -Hh / 2 - 0.09, 0],
                           [W / 2 + 0.035, -Hh / 2 - 0.05, 0], [W / 2 + 0.035, Hh * 0.05, 0]], 0.014,
                          {'seg': 12, 'radial': 5}), 'charcoal'), M.pl))
    for x in (-1, 1):
        rig.add(K.m(sw(L([[0, 0], [0.036, 0], [0.038, 0.014], [0.026, 0.034], [0, 0.034]], 0.005, 12), 'ink'), M.pl,
                    {'pos': [x * (W / 2 + 0.04), 0, 0], 'rot': [0, 0, -x * HP]}))
    rig.add(head)
    rig.position.y = h + Hh / 2 + 0.07
    g.add(rig)
    g.userData.parts = {'head': head, 'lens': refl}
    g.userData.lampMats = {'on': M.soft, 'off': M.dim}
    g.userData.colliders = [{'min': [-0.4, 0, -0.4], 'max': [0.4, h + Hh + 0.12, 0.4]}]
    if _truthy(opts.get('anchor')):
        g.userData.lightAnchors = [{'pos': [0, h + Hh / 2, -0.6], 'color': '#FFE6C0', 'intensity': 2, 'distance': 5}]
    return done(game, g, {'mergeParts': [head]})


registerProp('bc_light_softbox', _light_softbox, {
    'category': 'broadcast', 'tags': ['light', 'studio', 'stand', 'softlight'], 'size': [0.86, 1.9, 0.86],
    'desc': '70s soft light: sand shell, deep rim, concave glowing reflector (parts.lens), tube lamps behind a lip, on a '
            'rolling 3-caster stand. opts {height, tilt, lit, color, anchor}'})


def _grid_clamp(game, opts=None):
    opts = {} if opts is None else opts
    g = K.prop('bc_grid_clamp')
    M = mats(game)
    g.add(cClamp(M, {'pipe': nn(opts.get('pipe'), 0.4)}))
    g.add(K.m(K.tube([[0.03, 0, 0.03], [0.06, -0.08, 0.04], [0.02, -0.14, 0.03], [-0.02, -0.08, 0.03], [-0.03, 0, 0.03]],
                     0.003, {'seg': 14, 'radial': 3}), M.ch))
    dy = liftToFloor(g)
    g.userData.hang = {'pipeY': float(js_to_fixed(dy, 3))}
    g.userData.colliders = []
    return done(game, g, {'finish': HANG_AO})


registerProp('bc_grid_clamp', _grid_clamp, {
    'category': 'broadcast', 'tags': ['grid', 'clamp', 'hanging'], 'size': [0.4, 0.16, 0.1],
    'desc': 'C-clamp + safety loop on a 0.4 m pipe stub (pipe along x). hang.pipeY. opts {pipe}'})


def _grid_batten(game, opts=None):
    opts = {} if opts is None else opts
    g = K.prop('bc_grid_batten')
    M = mats(game)
    ln = nn(opts.get('len'), 3)
    g.add(K.m(sw(bcyl(0.024, 0.024, ln, 0.004, 12), 'silver'), M.me, {'pos': [-ln / 2, 0, 0], 'rot': [0, 0, -HP]}))
    # plugging strip (raceway) with numbered outlets
    g.add(K.m(sw(K.box(ln * 0.92, 0.07, 0.06, 0.012, {'seg': 1}), 'charcoal'), M.pl, {'pos': [0, -0.07, 0]}))
    n = int(max(2, js_round(ln / 0.5)))
    for i in range(n):
        x = -ln * 0.42 + (i / (n - 1)) * ln * 0.84
        g.add(K.m(sw(cbox(0.06, 0.04, 0.02, 0.005), 'ink'), M.pl, {'pos': [x, -0.07, -0.035]}))
        g.add(K.m(decal('num' + str((i % 4) + 1), 0.026, 0.026), M.pl, {'pos': [x + 0.05, -0.07, -0.0305]}))
        # pigtail tails dangling
        if i % 2 == 0:
            g.add(K.m(sw(K.tube([[x, -0.1, -0.03], [x + 0.02, -0.25, -0.05], [x + 0.05, -0.35, -0.03]], 0.008,
                                {'seg': 8, 'radial': 4}), 'ink'), M.pl))
    # cable bundle tied along the pipe with gaffer tape
    g.add(K.m(sw(K.tube([[-ln / 2, 0.035, 0.02], [-ln / 4, 0.04, 0.025], [0, 0.035, 0.02], [ln / 4, 0.042, 0.022],
                         [ln / 2, 0.035, 0.02]], 0.014, {'seg': 20, 'radial': 5}), 'ink'), M.pl))
    for i in range(4):
        g.add(K.m(cu(bcyl(0.042, 0.042, 0.04, 0.002, 10), 'tape'), M.pl,
                  {'pos': [-ln * 0.4 + i * ln * 0.27, 0.012, 0.01], 'rot': [0, 0, -HP]}))
    for x in [-ln * 0.45, ln * 0.45]:
        g.add(cClamp(M, {}).translateX(x))
    dy = liftToFloor(g)
    g.userData.hang = {'pipeY': float(js_to_fixed(dy, 3))}
    g.userData.colliders = []
    return done(game, g, {'finish': HANG_AO})


registerProp('bc_grid_batten', _grid_batten, {
    'category': 'broadcast', 'tags': ['grid', 'batten', 'hanging', 'studio'], 'size': [3, 0.5, 0.12],
    'desc': 'lighting batten: chrome pipe (along x) with a numbered plugging strip, dangling pigtails, taped cable '
            'bundle, clamps. hang.pipeY. opts {len=3}'})


# ================================================================================================= STUDIO FLOOR
def _boom_mic(game, opts=None):
    opts = {} if opts is None else opts
    g = K.prop('bc_boom_mic')
    M = mats(game)
    chC = nn(opts.get('color'), 'gold')

    # tricycle chassis: two rear wheels, one steerable front wheel, platform + seat
    def wheel(x, z, r):
        g.add(K.m(sw(L([[0, -0.03], [r * 0.8, -0.03], [r, -0.01], [r, 0.01], [r * 0.8, 0.03], [0, 0.03]], 0.008, 16),
                     'rubber'), M.mt, {'pos': [x, r, z], 'rot': [0, 0, HP]}))
        g.add(K.m(sw(bcyl(r * 0.45, r * 0.45, 0.066, 0.006, 12), chC), M.pl, {'pos': [x - 0.033, r, z],
                                                                              'rot': [0, 0, -HP]}))
    wheel(-0.42, 0.34, 0.11)
    wheel(0.42, 0.34, 0.11)
    wheel(0, -0.48, 0.1)
    # chassis plate (world x,z) -> shape (x, -z): rear axle at z = +0.34, nose over the front wheel
    chassis = [[x, -z] for x, z in [[-0.46, 0.44], [0.46, 0.44], [0.46, 0.2], [0.16, -0.5], [-0.16, -0.5], [-0.46, 0.2]]]
    g.add(K.m(sw(K.extrude(chassis, 0.075, {'bevel': 0.024, 'round': 0.09, 'curveSeg': 2, 'bevelSeg': 1}).rotateX(-HP),
                 chC), M.pl, {'pos': [0, 0.2, 0]}))
    g.add(K.m(sw(cbox(0.72, 0.03, 0.26, 0.01), 'slate'), M.mt, {'pos': [0, 0.252, 0.28]}))
    for x in [-0.42, 0.42]:
        g.add(K.m(sw(cbox(0.05, 0.11, 0.08, 0.012), chC), M.pl, {'pos': [x * 0.92, 0.18, 0.34]}))
    g.add(K.m(sw(bcyl(0.02, 0.02, 0.12, 0.005, 10), 'charcoal'), M.pl, {'pos': [0, 0.13, -0.48]}))
    # operator seat on a post
    g.add(K.m(bcyl(0.018, 0.018, 0.34, 0.004, 8), M.ch, {'pos': [0.3, 0.26, 0.3]}))
    g.add(K.m(K.cushion(0.3, 0.07, 0.28, {'puff': 0.02}), K.mat(game, 'vinyl', '#ffffff', {'map': K.tex.pebble('#5A3A22')}),
              {'pos': [0.3, 0.63, 0.3]}))
    # column: charcoal lower + chrome telescoping upper
    g.add(K.m(sw(L([[0, 0], [0.13, 0], [0.13, 0.03], [0.09, 0.07], [0.08, 0.12], [0.075, 0.9], [0.09, 0.93], [0.09, 0.97],
                    [0, 0.97]], 0.01, 16), 'charcoal'), M.pl, {'pos': [0, 0.23, 0]}))
    g.add(K.m(bcyl(0.05, 0.05, 0.42, 0.005, 14), M.ch, {'pos': [0, 1.18, 0]}))
    g.add(K.m(decal('pl_FISHER', 0.14, 0.026), M.pl, {'pos': [0, 0.7, -0.0775]}))
    # boom (part): pivot cradle, telescoping arm forward, counterweight + crank wheel behind, mic on a yoke
    boom = THREE.Group()
    boom.position.set(0, 1.64, 0)
    boom.rotation.set(nn(opts.get('raise'), 0.12), nn(opts.get('swing'), 0), 0)
    boom.userData.noMerge = True
    g.add(boom)
    boom.add(K.m(sw(L([[0, 0], [0.09, 0], [0.1, 0.02], [0.08, 0.05], [0, 0.05]], 0.008, 14), 'charcoal'), M.pl,
                 {'pos': [0, -0.05, 0]}))
    for s in (-1, 1):
        boom.add(K.m(sw(cbox(0.03, 0.14, 0.16, 0.01), 'charcoal'), M.pl, {'pos': [s * 0.07, 0.04, 0]}))
    reach = nn(opts.get('reach'), 2.2)
    secs = [[0.056, 0.9, chC], [0.043, 0.9, None], [0.033, reach - 1.4, None]]
    z, tipZ = 0.55, 0
    for r, l_, c in secs:
        boom.add(K.m(sw(bcyl(r, r, l_, 0.004, 14 if c else 12), nn(c, 'silver')), M.pl if c else M.me,
                     {'pos': [0, 0.08, z], 'rot': [-HP, 0, 0]}))
        boom.add(K.m(sw(bcyl(r + 0.008, r + 0.008, 0.03, 0.004, 12), 'ink'), M.pl,
                     {'pos': [0, 0.08, z - l_ + 0.03], 'rot': [-HP, 0, 0]}))
        tipZ = z - l_
        z -= l_ - 0.1
    boom.add(K.m(sw(cbox(0.1, 0.1, 0.16, 0.02), 'charcoal'), M.pl, {'pos': [0, 0.08, 0.6]}))
    boom.add(K.m(bcyl(0.012, 0.012, 0.3, 0.003, 8), M.ch, {'pos': [0, 0.08, 0.6], 'rot': [HP, 0, 0]}))
    for i in range(3):
        boom.add(K.m(sw(bcyl(0.1 - i * 0.012, 0.1 - i * 0.012, 0.045, 0.01, 18), 'red' if i == 1 else 'charcoal'), M.pl,
                     {'pos': [0, 0.08, 0.7 + i * 0.05], 'rot': [HP, 0, 0]}))
    boom.add(K.m(sw(K.tube(ring(0.13, 16), 0.012, {'seg': 20, 'radial': 5, 'closed': True}), 'ink'), M.pl,
                 {'pos': [0.12, 0.08, 0.48], 'rot': [0, 0, HP]}))
    boom.add(K.m(K.tube([[0.12, 0.08, 0.48], [0.12, 0.2, 0.48]], 0.008, {'seg': 2, 'radial': 5}), M.ch))
    boom.add(K.m(sw(lowCyl(0.012, 0.06, 8), 'rubber'), M.mt, {'pos': [0.12, 0.2, 0.48], 'rot': [0, 0, -HP]}))
    # mic cable along the arm
    boom.add(K.m(sw(K.tube([[0, 0.02, 0.6], [0, 0.03, 0.2], [0, 0.04, -0.6], [0, 0.03, tipZ + 0.3], [0, -0.03, tipZ + 0.05]],
                           0.007, {'seg': 20, 'radial': 4}), 'ink'), M.pl))
    # big ribbon mic in a yoke at the tip
    mic = THREE.Group()
    mic.position.set(0, 0.08, tipZ)
    mic.rotation.x = -nn(opts.get('micTilt'), 0.5)
    mic.scale.setScalar(1.45)
    mic.userData.noMerge = True
    boom.add(mic)
    mic.add(K.m(K.tube([[-0.07, -0.02, 0], [-0.075, -0.1, 0], [-0.07, -0.18, 0]], 0.007, {'seg': 6, 'radial': 5}), M.ch))
    mic.add(K.m(K.tube([[0.07, -0.02, 0], [0.075, -0.1, 0], [0.07, -0.18, 0]], 0.007, {'seg': 6, 'radial': 5}), M.ch))
    mic.add(K.m(K.tube([[-0.07, -0.02, 0], [0, 0.01, 0], [0.07, -0.02, 0]], 0.007, {'seg': 6, 'radial': 5}), M.ch))
    capsule = [[0, 0], [0.03, 0.005], [0.05, 0.03], [0.058, 0.07], [0.058, 0.14], [0.05, 0.18], [0.03, 0.205], [0, 0.21]]
    mic.add(K.m(sw(L(capsule, 0.01, 16), 'silver'), M.me, {'pos': [0, -0.24, 0]}))
    for i in range(5):
        mic.add(K.m(sw(K.tube(ring(0.06, 14), 0.003, {'seg': 16, 'radial': 3, 'closed': True}), 'charcoal'), M.pl,
                    {'pos': [0, -0.2 + i * 0.03, 0]}))
    mic.add(K.m(sw(bcyl(0.02, 0.024, 0.05, 0.004, 10), 'ink'), M.pl, {'pos': [0, -0.285, 0]}))
    mic.add(K.m(discDecal('logo13', 0.035, 16), M.pl, {'pos': [0, -0.17, -0.06]}))
    g.userData.parts = {'boom': boom, 'mic': mic}
    g.userData.colliders = [{'min': [-0.55, 0, -0.6], 'max': [0.55, 1.75, 0.5]}]
    return done(game, g, {'mergeParts': [boom, mic]})


registerProp('bc_boom_mic', _boom_mic, {
    'category': 'broadcast', 'tags': ['boom', 'mic', 'studio_a', 'hero'], 'size': [1.1, 1.9, 3.0], 'hero': True,
    'desc': 'Fisher-style boom mic dolly: gold tricycle chassis, seat, telescoping arm reaching -z, counterweight + '
            'crank, ribbon mic in a yoke. parts boom (rot.y swing, rot.x raise) / mic. opts {reach, raise, swing, '
            'micTilt, color}'})


# cable spaghetti: several floor cables snaking inside w x d, connectors at the ends, gaffer tape crossings
def floorCable(rnd, x0, z0, x1, z1, r, bends=5):
    pts = []
    for i in range(bends + 1):
        t = i / bends
        wob = 0 if (i == 0 or i == bends) else 1
        px = x0 + (x1 - x0) * t + (rnd() - 0.5) * 0.5 * wob
        py = r + (rnd() * 0.012 if wob else 0)
        pz = z0 + (z1 - z0) * t + (rnd() - 0.5) * 0.45 * wob
        pts.append([px, py, pz])
    return pts


def _cable_spaghetti(game, opts=None):
    opts = {} if opts is None else opts
    g = K.prop('bc_cable_spaghetti')
    M = mats(game)
    w, d = nn(opts.get('w'), 2.4), nn(opts.get('d'), 1.2)
    rnd = mulberry32(nn(opts.get('seed'), 7))
    cols = ['ink', 'orange', 'wztvBlue', 'mustard', 'ink', 'red']
    n = nn(opts.get('count'), 5)
    for i in range(n):
        r = 0.019 + rnd() * 0.01
        za = (rnd() - 0.5) * d
        zb = (rnd() - 0.5) * d
        pts = floorCable(rnd, -w / 2, za, w / 2, zb, r, 6)
        if rnd() < 0.4:
            k = 2 + int(math.floor(rnd() * 3))
            px, _py, pz = pts[k]
            pts[k + 1:k + 1] = [[px + 0.18, r + 0.01, pz + 0.12], [px + 0.02, r + 0.02, pz + 0.24],
                                [px - 0.12, r + 0.01, pz + 0.08]]
        c = cols[i % len(cols)]
        g.add(K.m(sw(K.tube(pts, r, {'seg': 28, 'radial': 6}), c), M.mt))
        for px, _py, pz in [pts[0], pts[-1]]:
            g.add(K.m(sw(bcyl(r * 1.6, r * 1.6, 0.08, 0.005, 10), 'charcoal' if i % 2 else 'silver'), M.pl,
                      {'pos': [px, r * 1.6, pz], 'rot': [0, 0, HP if px < 0 else -HP]}))
    for i in range(3):
        x = -w * 0.3 + i * w * 0.3
        g.add(K.m(cu(cbox(0.1, 0.005, d * 0.7, 0.001), 'tape'), M.mt, {'pos': [x, 0.052, 0],
                                                                        'rot': [0, (rnd() - 0.5) * 0.3, 0]}))
    g.userData.colliders = []
    return done(game, g, {'finish': {'ao': {'strength': 0.55, 'height': 0.02, 'heightStrength': 0.2}}})


registerProp('bc_cable_spaghetti', _cable_spaghetti, {
    'category': 'broadcast', 'tags': ['cable', 'floor', 'studio'], 'size': [2.6, 0.05, 1.4],
    'desc': 'walkable floor cable spaghetti (no collider): 5 cables, connectors, gaffer-tape strips. opts {w, d, count, '
            'seed}'})


def _cable_coil(game, opts=None):
    opts = {} if opts is None else opts
    g = K.prop('bc_cable_coil')
    M = mats(game)
    r, c = 0.016, nn(opts.get('color'), 'orange')
    pts = []
    for i in range(81):
        t = i / 80
        a = t * TAU * 5
        rr_ = 0.24 + math.sin(a * 0.7) * 0.02
        pts.append([math.cos(a) * rr_, r + t * r * 7 + math.sin(a * 3) * 0.004, math.sin(a) * rr_ * 0.92])
    pts.extend([[0.3, r * 3, 0.1], [0.45, r, 0.3], [0.7, r, 0.35]])
    g.add(K.m(sw(K.tube(pts, r * 1.3, {'seg': 100, 'radial': 5}), c), M.mt))
    g.add(K.m(sw(bcyl(r * 1.8, r * 1.8, 0.08, 0.004, 10), 'charcoal'), M.pl, {'pos': [0.78, r * 1.8, 0.35],
                                                                             'rot': [0, 0, -HP]}))
    g.add(K.m(cu(cbox(0.06, 0.006, 0.12, 0.002), 'tape'), M.mt, {'pos': [0.22, r * 10, 0.0], 'rot': [0, 0.3, 0.12]}))
    g.userData.colliders = []
    return done(game, g, {'finish': {'ao': {'strength': 0.6, 'height': 0.03, 'heightStrength': 0.2}}})


registerProp('bc_cable_coil', _cable_coil, {
    'category': 'broadcast', 'tags': ['cable', 'floor'], 'size': [1.1, 0.16, 0.6],
    'desc': 'coiled orange cable on the floor with a trailing end + connector, taped (no collider). opts {color}'})


# ================================================================================================= CASES
def flightCase(game, M, parent, o=None):
    o = o or {}
    S = {'sm': [0.5, 0.34, 0.36], 'md': [0.8, 0.5, 0.5], 'lg': [1.1, 0.68, 0.62], 'tall': [0.62, 1.1, 0.56]}[
        nn(o.get('size'), 'md')]
    w, h, d = S
    grp = THREE.Group()
    tolex = K.mat(game, 'paint', '#ffffff', {'map': K.tex.pebble(nn(o.get('color'), '#2E2934')), 'rim': 0.07,
                                             'rimPower': 3.5, 'rough': 0.7})
    y0 = 0.09 if o.get('size') == 'tall' else 0.012
    grp.add(K.m(K.box(w - 0.02, h - 0.02, d - 0.02, 0.012, {'uv': 2}), tolex, {'pos': [0, y0 + h / 2, 0]}))
    # aluminum edge extrusions + ball corners
    e = 0.024
    for sx in (-1, 1):
        for sy in (-1, 1):
            grp.add(K.m(sw(cbox(w - 0.04, e, e, 0.005), 'silver'), M.me,
                        {'pos': [0, y0 + h / 2 + sy * (h / 2 - e / 2), sx * (d / 2 - e / 2)]}))
            grp.add(K.m(sw(cbox(e, h - 0.04, e, 0.005), 'silver'), M.me,
                        {'pos': [sx * (w / 2 - e / 2), y0 + h / 2, sy * (d / 2 - e / 2)]}))
            grp.add(K.m(sw(cbox(e, e, d - 0.04, 0.005), 'silver'), M.me,
                        {'pos': [sx * (w / 2 - e / 2), y0 + h / 2 + sy * (h / 2 - e / 2), 0]}))
    for sx in (-1, 1):
        for sy in (-1, 1):
            for sz in (-1, 1):
                grp.add(K.m(lowSphere(0.024, 8, 6), M.ch, {'pos': [sx * (w / 2 - 0.012), y0 + h / 2 + sy * (h / 2 - 0.012),
                                                                   sz * (d / 2 - 0.012)]}))
    # lid seam valance + latches + side dish handles
    sy = y0 + h * 0.7
    grp.add(K.m(sw(cbox(w - 0.03, 0.018, 0.006, 0.002), 'silver'), M.me, {'pos': [0, sy, -d / 2 - 0.001]}))
    grp.add(K.m(sw(cbox(w - 0.03, 0.018, 0.006, 0.002), 'silver'), M.me, {'pos': [0, sy, d / 2 + 0.001]}))
    nl = 3 if w > 0.7 else 2
    for i in range(nl):
        x = (i - (nl - 1) / 2) * (w * 0.6 / ((nl - 1) or 1))
        grp.add(K.m(sw(cbox(0.07, 0.07, 0.014, 0.006), 'silver'), M.me, {'pos': [x, sy, -d / 2 - 0.006]}))
        grp.add(K.m(sw(lowCyl(0.02, 0.008, 10), 'steel'), M.me, {'pos': [x, sy, -d / 2 - 0.013], 'rot': [-HP, 0, 0]}))
    for s in (-1, 1):
        grp.add(K.m(sw(cbox(0.012, 0.09, 0.16, 0.004), 'ink'), M.pl, {'pos': [s * (w / 2 + 0.001), sy - h * 0.25, 0]}))
        grp.add(K.m(K.tube([[s * (w / 2 + 0.004), sy - h * 0.25, -0.06], [s * (w / 2 + 0.018), sy - h * 0.25, -0.05],
                            [s * (w / 2 + 0.018), sy - h * 0.25, 0.05], [s * (w / 2 + 0.004), sy - h * 0.25, 0.06]],
                           0.007, {'seg': 8, 'radial': 5}), M.ch))
    # stenciled tags
    grp.add(K.m(decal(nn(o.get('tag'), 'pl_STUDIOA'), min(0.32, w * 0.45), min(0.32, w * 0.45) * 0.1875), M.pl,
                {'pos': [-w * 0.18, y0 + h * 0.36, -d / 2 + 0.009]}))
    grp.add(K.m(decal('caseTag', min(0.14, h * 0.4), min(0.14, h * 0.4)), M.pl,
                {'pos': [w * 0.26, y0 + h * 0.36, -d / 2 + 0.009]}))
    if o.get('size') != 'sm':
        grp.add(K.m(cu(THREE.PlaneGeometry(0.3, 0.056).rotateX(-HP), 'pl_PROPERTY'), M.pl,
                    {'pos': [0.05, y0 + h - 0.009, 0.02], 'rot': [0, 0.1, 0]}))
    if o.get('size') == 'tall':
        for sx in (-1, 1):
            for sz in (-1, 1):
                c = caster(M, 0.035)
                c.position.set(sx * (w / 2 - 0.07), 0, sz * (d / 2 - 0.07))
                grp.add(c)
    parent.add(grp)
    return JSObj(grp=grp, w=w, h=h + y0, d=d)


def _flight_case(game, opts=None):
    opts = {} if opts is None else opts
    g = K.prop('bc_flight_case')
    M = mats(game)
    c = flightCase(game, M, g, opts)
    g.userData.colliders = [{'min': [-c.w / 2 - 0.02, 0, -c.d / 2 - 0.02], 'max': [c.w / 2 + 0.02, c.h, c.d / 2 + 0.02]}]
    return done(game, g)


registerProp('bc_flight_case', _flight_case, {
    'category': 'broadcast', 'tags': ['case', 'road_case', 'studio', 'crate'], 'size': [0.84, 0.51, 0.54],
    'desc': 'road/flight case: pebbled tolex, aluminum edges, ball corners, butterfly latches, dish handles, stencil '
            'tags. opts {size:sm|md|lg|tall, color (hex tolex), tag}'})


def _flight_case_stack(game, opts=None):
    opts = {} if opts is None else opts
    g = K.prop('bc_flight_case_stack')
    M = mats(game)
    a = flightCase(game, M, g, {'size': 'lg', 'color': nn(_at(opts.get('colors'), 0), '#2E2934')})
    b = flightCase(game, M, g, {'size': 'md', 'color': nn(_at(opts.get('colors'), 1), '#2F4A7A'), 'tag': 'pl_WZTV'})
    b.grp.position.set(-0.08, a.h, 0.02)
    b.grp.rotation.y = 0.12
    c = flightCase(game, M, g, {'size': 'sm', 'color': nn(_at(opts.get('colors'), 2), '#7A2A26')})
    c.grp.position.set(0.12, a.h + b.h, -0.02)
    c.grp.rotation.y = -0.2
    g.userData.colliders = [{'min': [-0.58, 0, -0.34], 'max': [0.58, a.h + b.h + c.h, 0.34]}]
    return done(game, g)


registerProp('bc_flight_case_stack', _flight_case_stack, {
    'category': 'broadcast', 'tags': ['case', 'road_case', 'stack', 'studio'], 'size': [1.16, 1.55, 0.68], 'hero': True,
    'desc': 'stack of 3 flight cases (lg black, md blue, sm red), slightly twisted. opts {colors[3]}'})


# ================================================================================================= SMALL PROPS
def _clapperboard(game, opts=None):
    opts = {} if opts is None else opts
    g = K.prop('bc_clapperboard')
    M = mats(game)
    W, H, T = 0.3, 0.24, 0.014
    root = THREE.Group()
    g.add(root)
    root.add(K.m(sw(K.box(W, H, T, 0.006, {'seg': 1}), 'black'), M.pl, {'pos': [0, H / 2, 0]}))
    root.add(K.m(decal('slate', W - 0.02, H - 0.02), M.pl, {'pos': [0, H / 2, -T / 2 - 0.0008]}))
    root.add(K.m(cu(cbox(W, 0.04, T, 0.004), 'stripes'), M.pl, {'pos': [0, H + 0.02, 0]}))
    clap = THREE.Group()
    clap.position.set(-W / 2 + 0.005, H + 0.04, 0)
    clap.rotation.z = nn(opts.get('open'), 0.4)
    clap.userData.noMerge = True
    clap.add(K.m(cu(cbox(W, 0.04, T, 0.004), 'stripes'), M.pl, {'pos': [W / 2 - 0.005, 0.02, 0]}))
    root.add(clap)
    root.add(K.m(bcyl(0.01, 0.01, T + 0.01, 0.002, 10), M.ch, {'pos': [-W / 2 + 0.005, H + 0.04, -T / 2 - 0.005],
                                                              'rot': [HP, 0, 0]}))
    if _truthy(opts.get('flat')):
        root.rotation.x = HP
        root.position.set(0, T / 2, -H / 2 - 0.02)
    else:
        root.rotation.x = -0.12
    g.userData.parts = {'clapper': clap}
    g.userData.colliders = []
    return done(game, g, {'mergeParts': [clap]})


registerProp('bc_clapperboard', _clapperboard, {
    'category': 'broadcast', 'tags': ['clapper', 'slate', 'small', 'desk'], 'size': [0.3, 0.3, 0.05],
    'desc': 'clapperboard: chalk slate "SPOOKTACULAR", striped clapper (parts.clapper rot.z). opts {open, flat}'})


def _teleprompter(game, opts=None):
    opts = {} if opts is None else opts
    g = K.prop('bc_teleprompter')
    M = mats(game)
    # small rolling base + chrome column
    for i in range(3):
        a = (i / 3) * TAU + HP
        g.add(along(lambda l_: sw(cbox(0.04, l_, 0.035, 0.008), 'slate').translate(0, l_ / 2, 0), M.pl, [0, 0.1, 0],
                    [math.cos(a) * 0.36, 0.1, math.sin(a) * 0.36]))
        c = caster(M, 0.03)
        c.position.set(math.cos(a) * 0.36, 0, math.sin(a) * 0.36)
        g.add(c)
    g.add(K.m(sw(L([[0, 0], [0.09, 0], [0.09, 0.03], [0.05, 0.08], [0, 0.08]], 0.01, 14), 'slate'), M.pl,
              {'pos': [0, 0.06, 0]}))
    g.add(K.m(bcyl(0.028, 0.028, 0.95, 0.004, 12), M.ch, {'pos': [0, 0.12, 0]}))
    g.add(K.m(sw(bcyl(0.04, 0.04, 0.05, 0.006, 12), 'slate'), M.pl, {'pos': [0, 0.6, 0]}))
    # hooded prompter head: monitor box facing up, 45deg beam-splitter glass, cloth hood, glowing script
    y0, W, D = 1.07, 0.5, 0.46
    g.add(K.m(sw(K.box(W, 0.18, D, 0.04), 'charcoal'), M.pl, {'pos': [0, y0 + 0.09, 0]}))
    g.add(K.m(sw(frame(W - 0.03, D - 0.03, 0.03, 0.02, 0.03, 0.01).rotateX(-HP), 'ink'), M.pl, {'pos': [0, y0 + 0.185, 0]}))
    g.add(K.m(cu(THREE.PlaneGeometry(W - 0.09, D - 0.09).rotateX(-HP).rotateY(math.pi), 'script'), M.pl,
              {'pos': [0, y0 + 0.187, 0]}))
    for s in (-1, 1):
        g.add(K.m(sw(K.extrude([[-D / 2, 0], [D / 2, 0], [D / 2, D - 0.04], [D / 2 - 0.04, D]], 0.02,
                               {'bevel': 0.006, 'round': 0.02}).rotateY(-HP), 'ink'), M.mt,
                  {'pos': [s * (W / 2 - 0.01), y0 + 0.18, 0]}))
    g.add(K.m(sw(cbox(W, 0.02, 0.08, 0.006), 'ink'), M.mt, {'pos': [0, y0 + 0.18 + D - 0.02, D / 2 - 0.04]}))
    g.add(K.m(sw(cbox(W, D - 0.02, 0.02, 0.006), 'ink'), M.mt, {'pos': [0, y0 + 0.18 + D / 2 - 0.01, D / 2 - 0.01]}))
    L45 = math.hypot(D, D) - 0.05
    glassMat = game.mats.toon('#2A3446', {'rough': 0.12, 'env': 0.25, 'rim': 0.35, 'rimColor': '#BFE8FF',
                                          'transparent': True, 'opacity': 0.55, 'depthWrite': False,
                                          'side': THREE.DoubleSide})
    gl = K.m(THREE.PlaneGeometry(W - 0.05, L45), glassMat, {'pos': [0, y0 + 0.18 + D / 2, 0], 'rot': [math.pi / 4, 0, 0]})
    gl.userData.noAO = True
    g.add(gl)
    g.add(K.m(cu(THREE.PlaneGeometry(W - 0.12, L45 * 0.7), 'script'),
              K.glow(game, '#ffffff', 0.95, {'map': atlasTex(), 'additive': True}),
              {'pos': [0, y0 + 0.18 + D / 2 + 0.003, -0.003], 'rot': [math.pi / 4, math.pi, 0]}))
    g.children[len(g.children) - 1].userData.noOcclude = True
    g.add(K.m(decal('pl_TELESCRIPT', 0.16, 0.03), M.pl, {'pos': [0, y0 + 0.1, -D / 2 - 0.003]}))
    g.add(K.m(lw(lowCyl(0.008, 0.006, 8), 'green'), M.lit, {'pos': [0.18, y0 + 0.1, -D / 2 - 0.001], 'rot': [-HP, 0, 0]}))
    g.userData.colliders = [{'min': [-0.38, 0, -0.38], 'max': [0.38, y0 + 0.2 + D, 0.38]}]
    return done(game, g)


registerProp('bc_teleprompter', _teleprompter, {
    'category': 'broadcast', 'tags': ['teleprompter', 'studio', 'newsroom'], 'size': [0.76, 1.72, 0.76],
    'desc': 'rolling teleprompter: up-facing script monitor, 45-degree beam-splitter glass with glowing script, cloth '
            'hood'})


def _reel_to_reel(game, opts=None):
    opts = {} if opts is None else opts
    g = K.prop('bc_reel_to_reel')
    M = mats(game)
    wood = woodMat(game)
    brushed = brushedMat(game)
    W, H, D = 0.46, 0.52, 0.2
    fz = -D / 2
    g.add(K.m(sw(K.box(W - 0.06, H, D - 0.01, 0.02), 'charcoal'), M.pl, {'pos': [0, H / 2, 0.005]}))
    for s in (-1, 1):
        g.add(K.m(K.box(0.035, H + 0.01, D + 0.01, 0.012, {'uv': 2, 'swap': True}), wood,
                  {'pos': [s * (W / 2 - 0.0175), H / 2 + 0.005, 0]}))
    g.add(K.m(K.box(W - 0.07, H - 0.02, 0.012, 0.006, {'uv': 2.5, 'seg': 1}), brushed, {'pos': [0, H / 2, fz + 0.002]}))
    reels = opts.get('reels') is not False
    ry, rx, rr0 = H * 0.7, 0.1, 0.09
    parts = {}
    for s, k, pack in [[-1, 'reelL', 0.85], [1, 'reelR', 0.45]]:
        sp = K.m(sw(lowCyl(0.012, 0.03, 8), 'silver'), M.me, {'pos': [s * rx, ry, fz - 0.004], 'rot': [-HP, 0, 0]})
        g.add(sp)
        if reels:
            rl = tapeReel(M, rr0, {'depth': 0.03, 'pack': pack})
            rl.position.set(s * rx, ry, fz - 0.03)
            rl.rotation.z = s
            g.add(rl)
            parts[k] = rl
    # head cover + tape path + capstan
    g.add(K.m(sw(K.box(0.12, 0.06, 0.04, 0.012), 'ink'), M.pl, {'pos': [0, ry - 0.11, fz - 0.018]}))
    g.add(K.m(bcyl(0.008, 0.008, 0.04, 0.002, 8), M.ch, {'pos': [0.075, ry - 0.11, fz - 0.004], 'rot': [-HP, 0, 0]}))
    g.add(K.m(sw(bcyl(0.016, 0.016, 0.03, 0.004, 10), 'rubber'), M.mt, {'pos': [0.1, ry - 0.1, fz - 0.004],
                                                                        'rot': [-HP, 0, 0]}))
    if reels:
        for a, b in [[[-rx - rr0 * 0.6, ry - 0.05], [-0.06, ry - 0.14]], [[-0.06, ry - 0.145], [0.075, ry - 0.145]],
                     [[0.075, ry - 0.14], [rx + rr0 * 0.35, ry - 0.03]]]:
            ln = math.hypot(b[0] - a[0], b[1] - a[1])
            me = K.m(sw(cbox(0.003, ln, 0.018, 0.001), 'tapeGold'), M.pl, {'pos': [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2,
                                                                                   fz - 0.045]})
            me.rotation.z = math.atan2(b[1] - a[1], b[0] - a[0]) - HP
            g.add(me)
    # meters, knobs, piano keys, badge
    vA = vuMeter(M, 0.1, [-0.085, H * 0.28, fz - 0.004], {'angle': 0.3})
    vB = vuMeter(M, 0.1, [0.085, H * 0.28, fz - 0.004], {'angle': 0.05})
    for mm in vA.meshes + vB.meshes:
        g.add(mm)
    for i in range(4):
        for mm in knob(M, 0.014, [-0.12 + i * 0.08, H * 0.16, fz - 0.004], {'color': 'ink', 'cap': 'silver',
                                                                            'rot': i * 0.7, 'seg': 10}):
            g.add(mm)
    for i in range(5):
        g.add(K.m(sw(keycap(0.05, 0.035, 0.03, 0.006), 'red' if i == 4 else 'ivory'), M.pl,
                  {'pos': [-0.12 + i * 0.06, H * 0.06, fz - 0.004], 'rot': [-HP + 0.3, 0, 0]}))
    g.add(K.m(decal('pl_AUDIOLUX', 0.13, 0.025), M.pl, {'pos': [0, H * 0.4, fz - 0.0045]}))
    g.userData.parts = parts
    g.userData.colliders = [{'min': [-W / 2, 0, fz - 0.06], 'max': [W / 2, H + 0.01, D / 2]}]
    return done(game, g, {'mergeParts': list(parts.values())})


registerProp('bc_reel_to_reel', _reel_to_reel, {
    'category': 'broadcast', 'tags': ['audio', 'tape', 'desk', 'master_control'], 'size': [0.46, 0.53, 0.26],
    'desc': 'upright reel-to-reel deck: brushed face, walnut cheeks, reels (parts reelL/R spin about z), VU meters, '
            'piano keys. opts {reels}'})


def headphones(M, g, o=None):
    o = o or {}
    grp = THREE.Group()
    cupC, padC = nn(o.get('cup'), 'silver'), nn(o.get('pad'), 'orange')
    grp.add(K.m(sw(K.tube([[-0.09, -0.04, 0], [-0.085, 0.05, 0], [-0.05, 0.1, 0], [0, 0.115, 0], [0.05, 0.1, 0],
                           [0.085, 0.05, 0], [0.09, -0.04, 0]], 0.009, {'seg': 18, 'radial': 6}), 'ink'), M.pl))
    grp.add(K.m(sw(K.tube([[-0.055, 0.092, 0], [-0.03, 0.108, 0], [0, 0.113, 0], [0.03, 0.108, 0], [0.055, 0.092, 0]],
                          0.017, {'seg': 10, 'radial': 7}), 'chocolate'), M.mt))
    for s in (-1, 1):
        grp.add(K.m(sw(L([[0, 0], [0.055, 0], [0.06, 0.012], [0.052, 0.04], [0.03, 0.05], [0, 0.052]], 0.008, 14), cupC),
                    M.me, {'pos': [s * 0.1, -0.06, 0], 'rot': [0, 0, s * HP]}))
        grp.add(K.m(sw(L([[0, 0], [0.056, 0], [0.058, 0.012], [0.045, 0.026], [0, 0.026]], 0.008, 14), padC), M.mt,
                    {'pos': [s * 0.1, -0.06, 0], 'rot': [0, 0, -s * HP]}))
        grp.add(K.m(sw(cbox(0.012, 0.05, 0.02, 0.004), 'ink'), M.pl, {'pos': [s * 0.095, -0.02, 0]}))
    coil = []
    for i in range(41):
        t = i / 40
        a = t * TAU * 8
        coil.append([0.13 + math.cos(a) * 0.012, -0.09 - t * 0.28, math.sin(a) * 0.012])
    coil.extend([[0.12, -0.42, 0.0], [0.11, -0.48, -0.01]])
    grp.add(K.m(sw(K.tube(coil, 0.0035, {'seg': 60, 'radial': 4}), 'ink'), M.pl))
    grp.add(K.m(bcyl(0.006, 0.006, 0.05, 0.002, 8), M.ch, {'pos': [0.11, -0.53, -0.01]}))
    grp.add(K.m(sw(bcyl(0.01, 0.01, 0.05, 0.003, 8), 'ink'), M.pl, {'pos': [0.11, -0.49, -0.01]}))
    g.add(grp)
    return grp


def _headphones_hook(game, opts=None):
    opts = {} if opts is None else opts
    g = K.prop('bc_headphones_hook')
    M = mats(game)
    wood = woodMat(game)
    Dd = 0.1
    g.add(K.m(K.box(0.1, 0.14, 0.02, 0.008, {'uv': 3}), wood, {'pos': [0, 0.62, Dd / 2 - 0.01]}))
    g.add(K.m(K.tube([[0, 0.6, Dd / 2 - 0.02], [0, 0.6, -0.02], [0, 0.62, -0.05], [0, 0.66, -0.05]], 0.008,
                     {'seg': 10, 'radial': 6}), M.ch))
    hp = headphones(M, g, opts)
    hp.position.set(0, 0.5, -0.03)
    hp.rotation.y = 0.12
    g.userData.colliders = []
    return done(game, g, {'finish': {'ao': {'floor': False, 'height': 0}}})


registerProp('bc_headphones_hook', _headphones_hook, {
    'category': 'broadcast', 'tags': ['headphones', 'wall', 'small'], 'size': [0.26, 0.7, 0.13],
    'desc': 'wall hook (back at z=+0.05) with 70s headphones: padded band, silver cups, orange pads, coiled cord + plug. '
            'y=0 = plug tip (hook at 0.6 m)'})


# ================================================================================================= ENG CAMERA
def _eng_camera(game, opts=None):
    opts = {} if opts is None else opts
    g = K.prop('bc_eng_camera')
    M = mats(game)
    # wooden tripod legs with spreader
    wood = woodMat(game, '#9A6A3E')
    hy = 1.18
    for i in range(3):
        a = (i / 3) * TAU + 0.5
        foot, top = [math.cos(a) * 0.48, 0.02, math.sin(a) * 0.48], [math.cos(a) * 0.07, hy - 0.04, math.sin(a) * 0.07]
        for o2 in [-0.018, 0.018]:
            ofs = [math.cos(a + HP) * o2, 0, math.sin(a + HP) * o2]
            g.add(along(lambda l_: K.uvScale(bcyl(0.013, 0.011, l_, 0.003, 8).clone(), 1, 3), wood,
                        [foot[0] + ofs[0], foot[1], foot[2] + ofs[2]], [top[0] + ofs[0], top[1], top[2] + ofs[2]]))
        mid = [foot[0] * 0.55 + top[0] * 0.45, 0.55, foot[2] * 0.55 + top[2] * 0.45]
        g.add(K.m(sw(cbox(0.06, 0.05, 0.03, 0.008), 'ink'), M.pl, {'pos': mid, 'rot': [0, -a, 0]}))
        g.add(K.m(sw(L([[0, 0], [0.024, 0], [0.02, 0.03], [0, 0.034]], 0.004, 8), 'silver'), M.pl,
                  {'pos': [foot[0], 0, foot[2]]}))
        g.add(along(lambda l_: sw(cbox(0.02, l_, 0.012, 0.004), 'charcoal').translate(0, l_ / 2, 0), M.pl,
                    [foot[0] * 0.7, 0.08, foot[2] * 0.7], [0, 0.08, 0]))
    g.add(K.m(sw(L([[0, 0], [0.11, 0], [0.11, 0.04], [0.08, 0.06], [0, 0.06]], 0.01, 14), 'charcoal'), M.pl,
              {'pos': [0, hy - 0.06, 0]}))
    # fluid head + pan handle
    head = THREE.Group()
    head.position.set(0, hy, 0)
    head.rotation.y = nn(opts.get('pan'), -0.3)
    head.userData.noMerge = True
    g.add(head)
    head.add(K.m(sw(bcyl(0.06, 0.07, 0.08, 0.01, 14), 'ink'), M.pl))
    head.add(K.m(sw(cbox(0.12, 0.03, 0.2, 0.008), 'charcoal'), M.pl, {'pos': [0, 0.095, 0]}))
    head.add(K.m(K.tube([[0.04, 0.06, 0.08], [0.1, 0.02, 0.3], [0.14, -0.04, 0.5]], 0.012, {'seg': 10, 'radial': 6}), M.ch))
    head.add(K.m(sw(K.tube([[0.12, -0.01, 0.42], [0.14, -0.04, 0.5]], 0.02, {'seg': 3, 'radial': 8}), 'rubber'), M.mt))
    # shoulder ENG camera: body, lens, side viewfinder tube, top handle, tally, shoulder pad
    cam = THREE.Group()
    cam.position.set(0, 0.11, 0.02)
    cam.scale.setScalar(nn(opts.get('camScale'), 1.25))
    head.add(cam)
    bodyC = nn(opts.get('color'), 'putty')
    cam.add(K.m(sw(K.box(0.18, 0.22, 0.4, 0.04), bodyC), M.pl, {'pos': [0, 0.12, 0.02]}))
    cam.add(K.m(sw(K.box(0.186, 0.06, 0.3, 0.02, {'seg': 1}), 'orange'), M.pl, {'pos': [0, 0.06, 0.04]}))
    cam.add(K.m(sw(K.box(0.16, 0.05, 0.22, 0.02), 'rubber'), M.mt, {'pos': [0, -0.005, 0.1]}))
    cam.add(K.m(sw(L([[0, 0], [0.06, 0], [0.06, 0.02], [0.054, 0.025], [0.054, 0.18], [0.07, 0.24], [0.066, 0.25],
                      [0, 0.25]], 0.006, 16), 'ink'), M.pl, {'pos': [0, 0.12, -0.18], 'rot': [-HP, 0, 0]}))
    cam.add(K.m(sw(L([[0.055, 0], [0.061, 0], [0.061, 0.05], [0.055, 0.05]], 0, 16), 'rubber'), M.mt,
                {'pos': [0, 0.12, -0.23], 'rot': [-HP, 0, 0]}))
    cam.add(K.m(THREE.CircleGeometry(0.058, 16).rotateY(math.pi), M.glass, {'pos': [0, 0.12, -0.425]}))
    cam.add(K.m(sw(cbox(0.03, 0.05, 0.12, 0.008), 'charcoal'), M.pl, {'pos': [0.075, 0.1, -0.28]}))
    cam.add(K.m(sw(bcyl(0.028, 0.028, 0.22, 0.005, 12), 'ink'), M.pl, {'pos': [-0.13, 0.2, -0.1], 'rot': [HP, 0, 0]}))
    cam.add(K.m(sw(L([[0, 0], [0.03, 0], [0.042, 0.04], [0.036, 0.05], [0, 0.05]], 0.005, 12), 'rubber'), M.mt,
                {'pos': [-0.13, 0.2, 0.12], 'rot': [HP, 0, 0]}))
    cam.add(K.m(sw(cbox(0.06, 0.03, 0.03, 0.008), 'ink'), M.pl, {'pos': [-0.1, 0.2, -0.06]}))
    cam.add(K.m(K.tube([[0, 0.23, -0.12], [0, 0.3, -0.09], [0, 0.3, 0.1], [0, 0.23, 0.14]], 0.012,
                       {'seg': 12, 'radial': 6}), M.ch))
    tallyProf = [[0, 0], [0.016, 0], [0.016, 0.008], [0.01, 0.018], [0, 0.02]]
    cam.add(K.m(lw(L(tallyProf, 0.004, 10), 'red') if _truthy(opts.get('tally')) else sw(L(tallyProf, 0.004, 10), 'lampRed'),
                M.lit if _truthy(opts.get('tally')) else M.pl, {'pos': [0.05, 0.23, -0.15]}))
    cam.add(K.m(decal('pl_VIDICAM', 0.12, 0.0225), M.pl, {'pos': [0.0935, 0.14, 0.05], 'rot': [0, -HP, 0]}))
    cam.add(K.m(discDecal('logo13', 0.035, 16), M.pl, {'pos': [0.0935, 0.17, -0.07], 'rot': [0, -HP, 0]}))
    # battery belt draped over the front leg: leather strap, chunky cells, chrome buckle, cable up to the camera
    af = 0.5 + (2 / 3) * TAU  # front leg angle
    dr, tan = [math.cos(af), 0, math.sin(af)], [-math.sin(af), 0, math.cos(af)]

    def P(s2, drop, out=0):
        return [dr[0] * (0.215 + out) + tan[0] * s2, 0.76 - drop, dr[2] * (0.215 + out) + tan[2] * s2]
    beltPts = []
    for i in range(15):
        t = i / 14 * 2 - 1
        beltPts.append(P(t * 0.15, 0.3 * math.pow(abs(t), 1.6) - 0.028, 0.045 * (1 - abs(t))))
    g.add(K.m(sw(K.tube(beltPts, 0.026, {'seg': 24, 'radial': 6}), 'chocolate'), M.pl))
    for i in [2, 4, 10, 12]:
        p0, p1 = beltPts[i - 1], beltPts[i + 1]
        g.add(along(lambda l_, i=i: sw(bcyl(0.034, 0.034, l_, 0.008, 10), 'ink' if i % 4 else 'charcoal'), M.pl,
                    [p0[0] + dr[0] * 0.02, p0[1], p0[2] + dr[2] * 0.02], [p1[0] + dr[0] * 0.02, p1[1], p1[2] + dr[2] * 0.02]))
    g.add(K.m(sw(cbox(0.05, 0.04, 0.02, 0.006), 'silver'), M.pl, {'pos': beltPts[14], 'rot': [0, -af, 0]}))
    g.add(K.m(sw(K.tube([beltPts[13], [beltPts[13][0], 0.5, beltPts[13][2] - 0.08], [0.1, 0.3, -0.25], [0.2, 0.9, -0.05],
                         [0.06, 1.2, 0.05], [0.02, 1.33, 0.2]], 0.007, {'seg': 22, 'radial': 4}), 'ink'), M.pl))
    g.userData.parts = {'head': head}
    g.userData.colliders = [{'min': [-0.45, 0, -0.45], 'max': [0.45, 1.55, 0.45]}]
    return done(game, g, {'mergeParts': [head]})


registerProp('bc_eng_camera', _eng_camera, {
    'category': 'broadcast', 'tags': ['camera', 'eng', 'news', 'lobby', 'tripod'], 'size': [1.0, 1.7, 1.05], 'hero': True,
    'desc': 'portable ENG shoulder camera on a wooden tripod: fluid head + pan bar (parts.head rot.y), side viewfinder, '
            'battery belt draped over a leg. opts {pan, tally, color}'})

# ================================================================================================= SCENES
# propview set-dressing checks (camera looks toward +z; back wall at +z, side wall at -x)
HPI = math.pi / 2
registerScene('bc_master_control', {
    'floor': '#3C4252', 'wall': '#2C3646', 'room': [9, 7], 'wallH': 3.9,
    'items': [
        {'id': 'bc_monitor_wall', 'pos': [0, 3.22]},
        {'id': 'bc_console_end', 'pos': [-1.825, 0.5]},
        {'id': 'bc_console_switcher', 'pos': [-1.2, 0.5]},
        {'id': 'bc_console_monitor', 'pos': [0, 0.5]},
        {'id': 'bc_console_audio', 'pos': [1.2, 0.5]},
        {'id': 'bc_console_end', 'pos': [1.825, 0.5]},
        {'id': 'bc_vtr_quad', 'pos': [-4.02, -0.9], 'rotY': -HPI, 'opts': {'num': 1}},
        {'id': 'bc_vtr_quad', 'pos': [-4.02, 0.45], 'rotY': -HPI, 'opts': {'num': 2, 'reels': False, 'lamp': 'amber',
                                                                          'group': 'scr_vtr2'}},
        {'id': 'bc_vtr_quad', 'pos': [-4.02, 1.8], 'rotY': -HPI, 'opts': {'num': 3}},
        {'id': 'bc_patch_bay', 'pos': [3.95, 3.05]},
        {'id': 'bc_patch_bay', 'pos': [3.95, 2.3], 'rotY': -0.08, 'opts': {'seed': 9, 'cords': 5}},
        {'id': 'bc_on_air', 'pos': [-4.43, 2.75, 2.75], 'rotY': -HPI, 'opts': {'lit': True}},
        {'id': 'bc_headphones_hook', 'pos': [-4.45, 0.75, 2.65], 'rotY': -HPI},
        {'id': 'bc_cart_monitor', 'pos': [3.2, -1.4], 'rotY': -0.7, 'opts': {'card': 'show_9'}},
        {'id': 'bc_flight_case_stack', 'pos': [-2.6, -2.6], 'rotY': 0.3},
        {'id': 'bc_cable_spaghetti', 'pos': [-2.4, -0.7], 'rotY': 0.4},
        {'id': 'bc_cable_coil', 'pos': [2.2, -2.3], 'rotY': 2.1},
        {'id': 'bc_reel_to_reel', 'pos': [2.9, 0.84, 1.6], 'rotY': -0.5},
        {'id': 'bc_flight_case', 'pos': [2.9, 1.6], 'rotY': -0.3, 'opts': {'size': 'lg', 'color': '#2F4A7A'}},
    ],
    'cam': {'pos': [0.6, 2.3, -4.6], 'target': [-0.3, 1.35, 1.6], 'fov': 58}, 'hemi': 0.75, 'key': 1.1,
})
registerScene('bc_studio', {
    'floor': 'wood', 'floorColor': '#6A4A36', 'wall': '#3A2A4A', 'room': [10, 7], 'wallH': 3.8,
    'items': [
        {'id': 'bc_pedestal_camera', 'pos': [-1.6, -0.6], 'rotY': 0.35, 'opts': {'num': 1}},
        {'id': 'bc_pedestal_camera', 'pos': [1.5, -0.3], 'rotY': -0.4, 'opts': {'num': 2, 'tally': False,
                                                                                'accent': 'orange'}},
        {'id': 'bc_boom_mic', 'pos': [3.3, 1.2], 'rotY': -2.4, 'opts': {'swing': 0.2}},
        {'id': 'bc_light_tripod', 'pos': [-3.6, 1.8], 'rotY': 0.9, 'opts': {'gel': 'amber'}},
        {'id': 'bc_light_softbox', 'pos': [3.6, 2.6], 'rotY': -0.6},
        {'id': 'bc_teleprompter', 'pos': [0.1, 2.2], 'rotY': math.pi},
        {'id': 'bc_grid_batten', 'pos': [0, 3.18, 1.8], 'opts': {'len': 5}},
        {'id': 'bc_light_fresnel', 'pos': [-1.6, 2.52, 1.8], 'opts': {'gel': 'magenta'}},
        {'id': 'bc_light_scoop', 'pos': [0.2, 2.46, 1.8]},
        {'id': 'bc_light_fresnel', 'pos': [1.8, 2.52, 1.8], 'opts': {'gel': 'cyan'}},
        {'id': 'bc_applause', 'pos': [0, 2.3, 3.2]},
        {'id': 'bc_cable_spaghetti', 'pos': [-0.4, 0.6], 'rotY': 0.1, 'opts': {'seed': 3}},
        {'id': 'bc_flight_case_stack', 'pos': [-4.1, -0.9], 'rotY': 0.6},
        {'id': 'bc_flight_case', 'pos': [-2.9, -2.3], 'rotY': -0.2, 'opts': {'size': 'md'}},
        {'id': 'bc_clapperboard', 'pos': [-2.9, 0.51, -2.3], 'rotY': 0.3, 'opts': {'flat': True}},
        {'id': 'bc_cart_monitor', 'pos': [4.1, -1.5], 'rotY': -0.9, 'opts': {'card': 'show_12'}},
        {'id': 'bc_cable_coil', 'pos': [1.6, -2.3], 'rotY': 0.8},
    ],
    'cam': {'pos': [0.2, 2.1, -5.2], 'target': [0, 1.2, 1.2], 'fov': 58}, 'hemi': 0.8, 'key': 1.1,
})

# debug: PROFILE (JS ?bcprof=1) registers a plane showing the whole atlas (not part of the library)
if PROFILE:
    def _dbg_atlas(game, opts=None):
        g = K.prop('bc__atlas')
        M = mats(game)
        g.add(K.m(THREE.PlaneGeometry(2, 2), M.pl, {'pos': [0, 1, 0], 'rot': [0, math.pi, 0]}))
        g.add(K.m(THREE.PlaneGeometry(2, 2), M.soft, {'pos': [2.1, 1, 0], 'rot': [0, math.pi, 0]}))
        return done(game, g, {'finish': {'ao': False}})
    registerProp('bc__atlas', _dbg_atlas, {'category': 'debug'})

    def _dbg_vu(game, opts=None):
        g = K.prop('bc__vu')
        M = mats(game)
        g.add(K.m(sw(cbox(0.6, 0.4, 0.05, 0.01), 'charcoal'), M.pl, {'pos': [0, 0.3, 0.03]}))
        v = vuMeter(M, 0.26, [-0.14, 0.3, 0], {})
        for m_ in v.meshes:
            g.add(m_)
        g.add(K.m(decal('vu', 0.2, 0.1), M.soft, {'pos': [0.16, 0.3, -0.01]}))
        return done(game, g)
    registerProp('bc__vu', _dbg_vu, {'category': 'debug'})
