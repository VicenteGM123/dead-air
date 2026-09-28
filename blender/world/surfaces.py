# World surfaces (port of src/world/surfaces.js): the station's canvas textures (plaster, quilted padding, planks,
# painted concrete, diamond plate, gravel, acoustic tile, brick, cinder block, grass, asphalt, sidewalk, chain-link,
# the scenery-flat board atlas, lit skyline windows) and the material palette built on mats.toon.
#
# createSurfaces(ctx) -> Surfaces: get(key) -> { 'mat', 'tile': [u, v], 'key' }, plain(key) -> Mat, tex(name),
#   AREA_STYLE, EXTERIOR_STYLE
#   get(): the batch material (vertexColors = fake AO, see batch.py) and tile = metres covered by one texture
#   repeat (batch.py bakes world-space UVs with it). plain(): the same look without vertex colors, for ordinary
#   meshes with their own 0..1 UVs (door leaves, frames, props).
# AREA_STYLE[areaId] = { floor, wall:{ base, wainscot?, wainscotH?, rail?, baseboard, crown? }, ceiling,
#   fixtures:'panels'|'cans'|'grid', lightPre (emergency color or None = dark), lightPost, gridY? }
# All textures are deterministic (seeded: ONE mulberry32(0x13131313) stream shared by every texture, in the order
# the surfaces are first requested — the build must request them in the JS order: architecture, exterior, doors,
# windows) and <= 512^2, cached per createSurfaces call.
#
# ctx = { 'mats': wk.Mats (toon/basic/variant), 'tex': the game.tex port (dalib.tex: carpet, tiles, woodPanel …) }
# The materials are dalib.scene.Material specs (SPEC §5.5 "da"); every surface material also carries "surface": key
# (+ "tile": [u, v] for the batch ones) in its spec (level.gd registers the converted materials by key: surf.get_ /
# surf.plain at runtime).

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from dalib.canvas2d import Canvas  # noqa: E402
from dalib.rng import mulberry32  # noqa: E402
from dalib.mathutils3 import Color  # noqa: E402

from world import wk  # noqa: E402

PI = 3.141592653589793


def canvas(w, h):
    return Canvas(w, h)


def finish(c, name, srgb=True):
    # THREE.CanvasTexture: sRGB, RepeatWrapping, anisotropy 8 (key 'surfaces|<name>', PNG in godot/assets/textures)
    t = wk.tex_from_canvas(c, 'surfaces|' + name, True, 'ws')
    t.anisotropy = 8
    return t


def shade(hex_, k):
    c = Color(hex_)
    if k >= 0:
        c.lerp(Color(1, 1, 1), k)
    else:
        c.multiplyScalar(1 + k)
    return '#' + c.getHexString()


# Speckle helper: n soft dots of random grey value around `base` alpha.
def speckle(ctx, w, h, rand, n, size, alpha, light='#ffffff', dark='#000000'):
    for _ in range(n):
        ctx.globalAlpha = alpha * (0.3 + rand() * 0.7)
        ctx.fillStyle = light if rand() < 0.5 else dark
        s = size * (0.5 + rand())
        ctx.fillRect(rand() * w, rand() * h, s, s)
    ctx.globalAlpha = 1


# ------------------------------------------------------------------------------------------ textures
def _plaster(rand):
    # Light plaster with roller texture: tinted by the material color.
    c = canvas(256, 256)
    x = c.getContext('2d')
    x.fillStyle = '#eeeeee'
    x.fillRect(0, 0, 256, 256)
    speckle(x, 256, 256, rand, 2600, 2.2, 0.08, '#ffffff', '#9a9a9a')
    x.globalAlpha = 0.05
    for _ in range(18):
        x.fillStyle = '#fff' if rand() < 0.5 else '#bbb'
        x.fillRect(rand() * 256, 0, 10 + rand() * 30, 256)
    x.globalAlpha = 1
    return finish(c, 'plaster')


def _quilt(rand):
    # Quilted padding: diamond tufts with buttons (soundstage walls, padded doors). Tinted.
    c = canvas(256, 256)
    x = c.getContext('2d')
    x.fillStyle = '#d8d8d8'
    x.fillRect(0, 0, 256, 256)
    s = 64
    for j in range(-1, 5):
        for i in range(-1, 5):
            cx = i * s + (s / 2 if j % 2 else 0)
            cy = j * s
            g = x.createRadialGradient(cx, cy + s / 2, 4, cx, cy + s / 2, s * 0.62)
            g.addColorStop(0, '#ffffff')
            g.addColorStop(0.7, '#d0d0d0')
            g.addColorStop(1, '#8a8a8a')
            x.fillStyle = g
            x.beginPath()
            x.moveTo(cx, cy)
            x.lineTo(cx + s / 2, cy + s / 2)
            x.lineTo(cx, cy + s)
            x.lineTo(cx - s / 2, cy + s / 2)
            x.closePath()
            x.fill()
    x.fillStyle = '#6e6e6e'
    for j in range(0, 5):
        for i in range(0, 9):
            x.beginPath()
            x.arc(i * s / 2, j * s + (s / 2 if i % 2 else 0), 4, 0, PI * 2)
            x.fill()
    return finish(c, 'quilt')


def _jsmod(a, b):
    # JS % on (possibly negative) ints: sign of the dividend
    r = abs(a) % abs(b)
    return -r if a < 0 else r


def _planks(rand, base='#D9B27C', rows=8):
    # Floor planks with staggered joints and grain (base color baked in).
    c = canvas(512, 512)
    x = c.getContext('2d')
    h = 512 / rows
    for r in range(rows):
        px = -rand() * 256
        while px < 512:
            ln = 160 + rand() * 220
            x.fillStyle = shade(base, (rand() - 0.5) * 0.18)
            x.fillRect(px, r * h, ln, h)
            x.strokeStyle = shade(base, -0.22)
            x.globalAlpha = 0.35
            for _ in range(5):
                gy = r * h + 4 + rand() * (h - 8)
                x.beginPath()
                x.moveTo(px, gy)
                x.bezierCurveTo(px + ln * 0.3, gy + (rand() - 0.5) * 6, px + ln * 0.7, gy + (rand() - 0.5) * 6, px + ln, gy)
                x.stroke()
            x.globalAlpha = 1
            x.fillStyle = shade(base, -0.45)
            x.fillRect(px, r * h, 2, h)
            px += ln
        x.fillStyle = shade(base, -0.5)
        x.fillRect(0, r * h, 512, 2)
        x.fillStyle = shade(base, 0.2)
        x.fillRect(0, r * h + 2, 512, 1)
    return finish(c, 'planks')


def _concrete(rand):
    # Painted studio concrete (full color): mottled plum-grey, scuffs and colored spike-tape marks.
    c = canvas(512, 512)
    x = c.getContext('2d')
    x.fillStyle = '#4b4254'
    x.fillRect(0, 0, 512, 512)
    for _ in range(90):
        g = x.createRadialGradient(0, 0, 0, 0, 0, 40 + rand() * 60)
        v = 'rgba(255,255,255,0.05)' if rand() < 0.5 else 'rgba(0,0,0,0.07)'
        g.addColorStop(0, v)
        g.addColorStop(1, 'rgba(0,0,0,0)')
        x.save()
        x.translate(rand() * 512, rand() * 512)
        x.fillStyle = g
        x.fillRect(-100, -100, 200, 200)
        x.restore()
    speckle(x, 512, 512, rand, 3000, 1.6, 0.12, '#bdb4c6', '#1c1822')
    tapes = ['#F4E03A', '#3FD6E0', '#FF5FA2', '#F4F1E8']
    for i in range(7):
        x.save()
        x.translate(40 + rand() * 432, 40 + rand() * 432)
        x.rotate((rand() - 0.5) * 0.3)
        x.fillStyle = tapes[i % len(tapes)]
        x.globalAlpha = 0.85
        if i % 2:
            x.fillRect(-14, -3, 28, 6)
            x.fillRect(-3, -14, 6, 28)
        else:
            x.fillRect(-22, -3, 44, 6)
        x.restore()
    x.globalAlpha = 1
    return finish(c, 'concrete')


def _diamondPlate(rand):
    c = canvas(256, 256)
    x = c.getContext('2d')
    x.fillStyle = '#9aa3ab'
    x.fillRect(0, 0, 256, 256)
    speckle(x, 256, 256, rand, 900, 2, 0.1, '#ffffff', '#40464c')
    for j in range(8):
        for i in range(8):
            x.save()
            x.translate(i * 32 + (16 if j % 2 else 0) + 8, j * 32 + 16)
            x.rotate(0.8 if (i + j) % 2 else -0.8)
            x.fillStyle = '#6c747c'
            x.fillRect(-11, -3, 22, 6)
            x.fillStyle = '#d4dade'
            x.fillRect(-11, -3, 22, 2)
            x.restore()
    return finish(c, 'diamondPlate')


def _gravel(rand):
    c = canvas(512, 512)
    x = c.getContext('2d')
    x.fillStyle = '#5d5866'
    x.fillRect(0, 0, 512, 512)
    cols = ['#7b7684', '#8c8795', '#4a4652', '#a39eab', '#6a6573', '#77705f']
    for _ in range(5200):
        r = 1.5 + rand() * 4
        px, py = rand() * 512, rand() * 512
        x.fillStyle = '#2c2933'
        x.beginPath()
        x.ellipse(px + 1, py + 1.5, r, r * 0.8, rand() * 3, 0, PI * 2)
        x.fill()
        x.fillStyle = cols[int(rand() * len(cols))]
        x.beginPath()
        x.ellipse(px, py, r, r * 0.8, rand() * 3, 0, PI * 2)
        x.fill()
    return finish(c, 'gravel')


def _acoustic(rand):
    # 2x2 acoustic ceiling tiles with pinholes and a T-bar grid (tinted).
    c = canvas(256, 256)
    x = c.getContext('2d')
    x.fillStyle = '#efefef'
    x.fillRect(0, 0, 256, 256)
    x.fillStyle = '#b5b5b5'
    for _ in range(1500):
        x.fillRect(rand() * 256, rand() * 256, 1.4, 1.4)
    x.fillStyle = '#c9c9c9'
    for i in range(2):
        x.fillRect(i * 128, 0, 5, 256)
        x.fillRect(0, i * 128, 256, 5)
    x.fillStyle = '#ffffff'
    for i in range(2):
        x.fillRect(i * 128 + 5, 0, 1, 256)
        x.fillRect(0, i * 128 + 5, 256, 1)
    return finish(c, 'acoustic')


def _brick(rand):
    c = canvas(512, 512)
    x = c.getContext('2d')
    x.fillStyle = '#6d5a52'
    x.fillRect(0, 0, 512, 512)
    bw, bh = 64, 24
    r = 0
    while r < 512 / bh:
        i = -1
        while i < 512 / bw + 1:
            px = i * bw + (bw / 2 if r % 2 else 0)
            x.fillStyle = shade('#B98A6A', (rand() - 0.5) * 0.25)
            x.fillRect(px + 2, r * bh + 2, bw - 4, bh - 4)
            x.fillStyle = 'rgba(255,255,255,0.08)'
            x.fillRect(px + 2, r * bh + 2, bw - 4, 3)
            i += 1
        r += 1
    speckle(x, 512, 512, rand, 2500, 1.5, 0.1, '#e8d2bd', '#3a2a24')
    return finish(c, 'brick')


def _block(rand):
    c = canvas(256, 256)
    x = c.getContext('2d')
    x.fillStyle = '#9c9c9c'
    x.fillRect(0, 0, 256, 256)
    bw, bh = 128, 64
    for r in range(4):
        for i in range(-1, 3):
            px = i * bw + (bw / 2 if r % 2 else 0)
            x.fillStyle = shade('#e4e4e4', (rand() - 0.5) * 0.06)
            x.fillRect(px + 3, r * bh + 3, bw - 6, bh - 6)
    speckle(x, 256, 256, rand, 1400, 1.6, 0.12, '#ffffff', '#707070')
    return finish(c, 'block')


def _grass(rand):
    c = canvas(256, 256)
    x = c.getContext('2d')
    x.fillStyle = '#2f4a3a'
    x.fillRect(0, 0, 256, 256)
    for _ in range(2600):
        x.strokeStyle = '#3d5e46' if rand() < 0.5 else '#24392e'
        x.globalAlpha = 0.6
        px, py = rand() * 256, rand() * 256
        x.beginPath()
        x.moveTo(px, py)
        x.lineTo(px + (rand() - 0.5) * 3, py - 3 - rand() * 4)
        x.stroke()
    x.globalAlpha = 1
    return finish(c, 'grass')


def _asphalt(rand):
    c = canvas(256, 256)
    x = c.getContext('2d')
    x.fillStyle = '#2b2a31'
    x.fillRect(0, 0, 256, 256)
    speckle(x, 256, 256, rand, 4000, 1.3, 0.25, '#58566a', '#141318')
    return finish(c, 'asphalt')


def _sidewalk(rand):
    c = canvas(256, 256)
    x = c.getContext('2d')
    x.fillStyle = '#8b8792'
    x.fillRect(0, 0, 256, 256)
    speckle(x, 256, 256, rand, 2200, 1.5, 0.12, '#c8c4ce', '#4a4750')
    x.fillStyle = '#5d5a63'
    x.fillRect(0, 0, 256, 3)
    x.fillRect(0, 0, 3, 256)
    return finish(c, 'sidewalk')


def _chainLink(rand):
    # RGBA chain-link: galvanized wire diamonds on transparent (alphaTest in the material).
    c = canvas(128, 128)
    x = c.getContext('2d')
    x.clearRect(0, 0, 128, 128)
    x.lineWidth = 3.2
    x.lineCap = 'round'

    def draw(col, off):
        x.strokeStyle = col
        for i in range(-2, 4):
            x.beginPath()
            x.moveTo(i * 64 + off, 0)
            x.lineTo(i * 64 + 128 + off, 128)
            x.stroke()
            x.beginPath()
            x.moveTo(i * 64 + off, 128)
            x.lineTo(i * 64 + 128 + off, 0)
            x.stroke()
    draw('#4e565e', 1.2)
    draw('#c9d2da', 0)
    return finish(c, 'chainLink')


def _boards(rand):
    # Six scenery-flat slices (sky with clouds, brick, wood fence, stars, sunset stripes, hedge) + plywood band.
    c = canvas(512, 512)
    x = c.getContext('2d')
    band = 512 / 7

    def B(i, fn):
        x.save()
        x.beginPath()
        x.rect(0, i * band, 512, band)
        x.clip()
        x.translate(0, i * band)
        fn()
        x.restore()

    def b0():
        x.fillStyle = '#7FC8F0'
        x.fillRect(0, 0, 512, band)
        x.fillStyle = '#ffffff'
        for _ in range(7):
            cx = rand() * 512
            for k in range(4):
                x.beginPath()
                x.arc(cx + k * 16, band * 0.5 + (k % 2) * 6, 14 + rand() * 6, 0, 7)
                x.fill()

    def b1():
        x.fillStyle = '#E3E0D8'
        x.fillRect(0, 0, 512, band)
        for r in range(4):
            for i in range(-1, 12):
                x.fillStyle = shade('#C0513A', (rand() - 0.5) * 0.2)
                x.fillRect(i * 48 + (24 if r % 2 else 0) + 2, r * (band / 4) + 2, 44, band / 4 - 4)

    def b2():
        for i in range(16):
            x.fillStyle = shade('#B07A45', (rand() - 0.5) * 0.25)
            x.fillRect(i * 32, 0, 30, band)
        x.fillStyle = 'rgba(60,30,10,0.4)'
        for i in range(16):
            x.fillRect(i * 32 + 30, 0, 2, band)

    def b3():
        x.fillStyle = '#23285E'
        x.fillRect(0, 0, 512, band)
        x.fillStyle = '#FFF4B0'
        for _ in range(40):
            s = 1 + rand() * 2.5
            x.fillRect(rand() * 512, rand() * band, s, s)
        x.fillStyle = '#FFF4D6'
        x.beginPath()
        x.arc(400, band / 2, band * 0.32, 0, 7)
        x.fill()

    def b4():
        for i, col in enumerate(['#FF7E5F', '#FFB36B', '#FFE3A3', '#FFB36B']):
            x.fillStyle = col
            x.fillRect(0, i * band / 4, 512, band / 4 + 1)
        x.fillStyle = '#E3662B'
        x.beginPath()
        x.arc(140, band, band * 0.6, 0, 7)
        x.fill()

    def b5():
        x.fillStyle = '#4E8A3E'
        x.fillRect(0, 0, 512, band)
        for _ in range(70):
            x.fillStyle = '#63A84E' if rand() < 0.5 else '#3C6E30'
            x.beginPath()
            x.arc(rand() * 512, rand() * band, 8 + rand() * 12, 0, 7)
            x.fill()

    def b6():
        x.fillStyle = '#C9A77A'
        x.fillRect(0, 0, 512, band)
        x.strokeStyle = 'rgba(120,80,40,0.35)'
        for _ in range(30):
            y = rand() * band
            x.beginPath()
            x.moveTo(0, y)
            x.bezierCurveTo(170, y + 8, 340, y - 8, 512, y)
            x.stroke()
    for i, fn in enumerate([b0, b1, b2, b3, b4, b5, b6]):
        B(i, fn)
    # white painted edges on every slice
    x.fillStyle = 'rgba(255,255,255,0.55)'
    for i in range(6):
        x.fillRect(0, i * band, 512, 3)
        x.fillRect(0, (i + 1) * band - 3, 512, 3)
    return finish(c, 'boards')


def _skyline(rand):
    # Night facade with lit windows (warm, TV-blue, dark). Used unlit on skyline boxes.
    c = canvas(256, 256)
    x = c.getContext('2d')
    x.fillStyle = '#161a3a'
    x.fillRect(0, 0, 256, 256)
    for r in range(16):
        for i in range(12):
            k = rand()
            x.fillStyle = '#1f2448' if k < 0.7 else '#FFD88A' if k < 0.86 else '#8FD8FF' if k < 0.95 else '#FFB36B'
            x.fillRect(i * 21 + 5, r * 16 + 4, 11, 8)
    return finish(c, 'skyline')


TEX = {
    'plaster': _plaster, 'quilt': _quilt, 'planks': _planks, 'concrete': _concrete, 'diamondPlate': _diamondPlate,
    'gravel': _gravel, 'acoustic': _acoustic, 'brick': _brick, 'block': _block, 'grass': _grass,
    'asphalt': _asphalt, 'sidewalk': _sidewalk, 'chainLink': _chainLink, 'boards': _boards, 'skyline': _skyline,
}

# ---------------------------------------------------------------------------------------------- styles
AREA_STYLE = {
    'lobby': {
        'floor': 'shag_orange',
        'wall': {'base': 'wood_walnut', 'baseboard': 'trim_chocolate', 'crown': 'trim_teak'},
        'ceiling': 'ceiling_tile', 'fixtures': 'cans', 'lightPre': '#FFB45A', 'lightPost': '#FFC98A',
    },
    'newsroom': {
        'floor': 'vinyl_news',
        'wall': {'base': 'paint_news', 'wainscot': 'wood_teak', 'wainscotH': 1.1, 'rail': 'trim_chocolate', 'baseboard': 'trim_chocolate', 'crown': 'trim_cream'},
        'ceiling': 'ceiling_tile', 'fixtures': 'panels', 'lightPre': None, 'lightPost': '#E8F5E1',
    },
    'green_room': {
        'floor': 'shag_avocado',
        'wall': {'base': 'paint_avocado', 'wainscot': 'wood_olive', 'wainscotH': 1.0, 'rail': 'trim_mustard', 'baseboard': 'trim_chocolate', 'crown': 'trim_cream'},
        'ceiling': 'ceiling_tile', 'fixtures': 'panels', 'lightPre': None, 'lightPost': '#FFE6C0',
    },
    'studio_a': {
        'floor': 'concrete_studio',
        'wall': {'base': 'paint_studio', 'wainscot': 'quilt_plum', 'wainscotH': 3.0, 'rail': 'trim_black', 'baseboard': 'trim_black'},
        'ceiling': 'ceiling_studio', 'fixtures': 'grid', 'gridY': 6.5, 'lightPre': None, 'lightPost': '#FFC4E4',
    },
    'studio_b': {
        'floor': 'wood_maple',
        'wall': {'base': 'paint_lilac', 'wainscot': 'quilt_pink', 'wainscotH': 2.2, 'rail': 'trim_cream', 'baseboard': 'trim_cream'},
        'ceiling': 'ceiling_studio_b', 'fixtures': 'grid', 'gridY': 5.0, 'lightPre': None, 'lightPost': '#FFF1C9',
    },
    'master_control': {
        'floor': 'vinyl_mc',
        'wall': {'base': 'block_mc', 'baseboard': 'trim_black', 'crown': 'trim_steel'},
        'ceiling': 'ceiling_tile_mc', 'fixtures': 'panels', 'lightPre': None, 'lightPost': '#DDF3FF',
    },
    'yard': {'floor': 'gravel'},
}

EXTERIOR_STYLE = {'base': 'brick', 'wainscot': 'block_ext', 'wainscotH': 0.6, 'cap': 'trim_coping'}


# ------------------------------------------------------------------------------------------- factory
class Surfaces:
    def __init__(self, ctx):
        self.rand = mulberry32(0x13131313)
        self._tex = {}
        self.mats = ctx['mats']
        self.gtex = ctx['tex']       # game.tex (dalib.tex port of src/core/textures.js)
        self.AREA_STYLE = AREA_STYLE
        self.EXTERIOR_STYLE = EXTERIOR_STYLE
        self._cache = {}
        self._plain = {}

    def tex(self, name, *args):
        t = self._tex.get(name)
        if t is None:
            t = self._tex[name] = TEX[name](self.rand, *args)
        return t

    def _defs(self, key):
        T = self.tex
        mats = self.mats
        gt = self.gtex

        def toon(color, o=None):
            return mats.toon(color, dict({'rim': 0.12, 'vertexColors': True}, **(o or {})))

        def woodPanel(base):
            return gt.woodPanel(base)
        d = {
            # floors (rim off: floors should not glow at grazing angles)
            'shag_orange': lambda: [toon('#ffffff', {'map': gt.carpet('#D9602B', '#E8A92E'), 'rough': 0.95, 'rim': 0}), [1.0, 1.0]],
            'shag_avocado': lambda: [toon('#ffffff', {'map': gt.carpet('#7E8C33', '#C9B458'), 'rough': 0.95, 'rim': 0}), [1.0, 1.0]],
            'vinyl_news': lambda: [toon('#ffffff', {'map': gt.tiles('#EFE3C4', '#C98F3A', 4), 'rough': 0.42, 'rim': 0}), [1.2, 1.2]],
            'vinyl_mc': lambda: [toon('#ffffff', {'map': gt.tiles('#C7CEC6', '#7F8F8C', 4), 'rough': 0.45, 'rim': 0}), [1.2, 1.2]],
            'metal_plate': lambda: [toon('#ffffff', {'map': T('diamondPlate'), 'rough': 0.5, 'metal': 0.35, 'env': 0.3, 'rim': 0}), [0.8, 0.8]],
            'concrete_studio': lambda: [toon('#ffffff', {'map': T('concrete'), 'rough': 0.7, 'rim': 0}), [6, 6]],
            'wood_maple': lambda: [toon('#ffffff', {'map': T('planks'), 'rough': 0.5, 'rim': 0}), [3, 3]],
            'stage_wood': lambda: [toon('#C98E56', {'map': T('planks'), 'rough': 0.4, 'rim': 0}), [3, 3]],
            'bleacher_wood': lambda: [toon('#D6A46C', {'map': T('planks'), 'rough': 0.55, 'rim': 0.08}), [3, 3]],
            'riser_carpet': lambda: [toon('#ffffff', {'map': gt.carpet('#8A3B2A', '#E3662B'), 'rough': 0.95, 'rim': 0}), [1, 1]],
            'gravel': lambda: [toon('#ffffff', {'map': T('gravel'), 'rough': 0.95, 'rim': 0}), [3, 3]],
            # walls
            'wood_walnut': lambda: [toon('#ffffff', {'map': woodPanel('#8A5530'), 'rough': 0.35, 'rimColor': '#FFC98A'}), [1.6, 2.4]],
            'wood_teak': lambda: [toon('#ffffff', {'map': woodPanel('#B07A45'), 'rough': 0.35, 'rimColor': '#9FC8FF'}), [1.6, 2.4]],
            'wood_olive': lambda: [toon('#ffffff', {'map': woodPanel('#6E6A2E'), 'rough': 0.4, 'rimColor': '#FFD08A'}), [1.6, 2.4]],
            'paint_news': lambda: [toon('#E6D8B8', {'map': T('plaster'), 'rough': 0.85, 'rimColor': '#9FC8FF'}), [2, 2]],
            'paint_avocado': lambda: [toon('#9AA844', {'map': T('plaster'), 'rough': 0.85, 'rimColor': '#FFD08A'}), [2, 2]],
            'paint_studio': lambda: [toon('#4A3A58', {'map': T('plaster'), 'rough': 0.9, 'rimColor': '#FF4FA0'}), [2, 2]],
            'paint_lilac': lambda: [toon('#C8B4EA', {'map': T('plaster'), 'rough': 0.85, 'rimColor': '#FFB6C8'}), [2, 2]],
            'quilt_plum': lambda: [toon('#6B4A78', {'map': T('quilt'), 'rough': 0.9, 'rimColor': '#FF4FA0'}), [1.2, 1.2]],
            'quilt_pink': lambda: [toon('#F2B6C8', {'map': T('quilt'), 'rough': 0.9, 'rimColor': '#FFB6C8'}), [1.2, 1.2]],
            'quilt_red': lambda: [toon('#B5472A', {'map': T('quilt'), 'rough': 0.7, 'rimColor': '#FFC98A'}), [0.9, 0.9]],
            'block_mc': lambda: [toon('#8FA6B4', {'map': T('block'), 'rough': 0.8, 'rimColor': '#7FE7FF'}), [1.6, 1.6]],
            'brick': lambda: [toon('#ffffff', {'map': T('brick'), 'rough': 0.9, 'rimColor': '#9FB6FF', 'rim': 0.18}), [2.4, 2.4]],
            'block_ext': lambda: [toon('#6F6A78', {'map': T('block'), 'rough': 0.9, 'rimColor': '#9FB6FF'}), [1.6, 1.6]],
            # trims
            'trim_chocolate': lambda: [toon('#5A3A22', {'rough': 0.4}), [1, 1]],
            'trim_teak': lambda: [toon('#B07A45', {'rough': 0.35}), [1, 1]],
            'trim_cream': lambda: [toon('#F6E7C8', {'rough': 0.5}), [1, 1]],
            'trim_mustard': lambda: [toon('#D9A520', {'rough': 0.45}), [1, 1]],
            'trim_black': lambda: [toon('#2A2230', {'rough': 0.6}), [1, 1]],
            'trim_steel': lambda: [toon('#7C8A99', {'rough': 0.45, 'metal': 0.45, 'env': 0.35}), [1, 1]],
            'trim_chrome': lambda: [toon('#DDE3EA', {'rough': 0.25, 'metal': 1, 'env': 0.55}), [1, 1]],
            'trim_coping': lambda: [toon('#CFC6B8', {'rough': 0.8, 'rim': 0.2, 'rimColor': '#9FB6FF'}), [1, 1]],
            'trim_gold': lambda: [toon('#E8A92E', {'rough': 0.3, 'metal': 0.8, 'env': 0.5}), [1, 1]],
            # ceilings
            'ceiling_tile': lambda: [toon('#F6EEDC', {'map': T('acoustic'), 'rough': 0.95, 'rim': 0, 'emissive': '#8A7458', 'emissiveIntensity': 0.3}), [1.2, 1.2]],
            'ceiling_tile_mc': lambda: [toon('#DDE4E6', {'map': T('acoustic'), 'rough': 0.95, 'rim': 0, 'emissive': '#4A6072', 'emissiveIntensity': 0.28}), [1.2, 1.2]],
            'ceiling_studio': lambda: [toon('#1D1724', {'rough': 1, 'rim': 0}), [1, 1]],
            'ceiling_studio_b': lambda: [toon('#3A3150', {'rough': 1, 'rim': 0}), [1, 1]],
            # exterior
            'grass': lambda: [toon('#ffffff', {'map': T('grass'), 'rough': 1, 'rim': 0}), [3, 3]],
            'asphalt': lambda: [toon('#ffffff', {'map': T('asphalt'), 'rough': 0.9, 'rim': 0}), [4, 4]],
            'sidewalk': lambda: [toon('#ffffff', {'map': T('sidewalk'), 'rough': 0.9, 'rim': 0}), [2, 2]],
            'paint_line': lambda: [toon('#F2E6C0', {'rough': 0.8, 'rim': 0}), [1, 1]],
            'paint_yellow': lambda: [toon('#E8C33A', {'rough': 0.8, 'rim': 0}), [1, 1]],
            'chainlink': lambda: [toon('#C8CED6', {'map': T('chainLink'), 'rough': 0.65, 'metal': 0.25, 'env': 0.2, 'alphaTest': 0.5, 'side': 'double', 'rim': 0.15, 'rimColor': '#9FB6FF'}), [0.5, 0.5]],
            'galvanized': lambda: [toon('#A7B0B9', {'rough': 0.4, 'metal': 0.6, 'env': 0.4, 'rimColor': '#9FB6FF'}), [1, 1]],
            'boards': lambda: [toon('#ffffff', {'map': T('boards'), 'rough': 0.7, 'rim': 0.15}), [1, 1]],
            # level extras: stage skirt, bleacher risers, roofs, storefronts, the unlit skyline facades
            'bleacher_riser': lambda: [toon('#2F5BD3', {'map': T('plaster'), 'rough': 0.6, 'rimColor': '#FF4FA0'}), [2, 2]],
            'roof_gravel': lambda: [toon('#8A8494', {'map': T('gravel'), 'rough': 1, 'rim': 0}), [3, 3]],
            'stucco_cream': lambda: [toon('#D9C7A0', {'map': T('plaster'), 'rough': 0.9, 'rimColor': '#9FB6FF', 'rim': 0.18}), [2, 2]],
            'stucco_teal': lambda: [toon('#5E8C8C', {'map': T('plaster'), 'rough': 0.9, 'rimColor': '#9FB6FF', 'rim': 0.18}), [2, 2]],
            'stucco_rust': lambda: [toon('#A0543A', {'map': T('plaster'), 'rough': 0.9, 'rimColor': '#9FB6FF', 'rim': 0.18}), [2, 2]],
            'skyline': lambda: [mats.basic('#8C90B8', {'map': T('skyline'), 'fog': False, 'vertexColors': True}), [16, 48]],
            'storefront': lambda: [mats.basic('#ffffff', {'map': T('skyline'), 'vertexColors': True}), [3, 3]],
        }
        return d.get(key)

    def get(self, key):
        s = self._cache.get(key)
        if s is None:
            df = self._defs(key)
            if df is None:
                raise KeyError('[surfaces] unknown surface %s' % key)
            mat, tile = df()
            mat = self.mats.tagged(mat, surface=key, tile=tile)
            s = {'mat': mat, 'tile': tile, 'key': key}
            self._cache[key] = s
        return s

    def plain(self, key):
        m = self._plain.get(key)
        if m is None:
            src = self.get(key)['mat']
            m = self.mats.variant(src, {'vertexColors': False})
            if m is src:
                m = self.mats.basic('#' + src.color.getHexString(), {'map': src.map, 'fog': src.opts.get('fog', True)})
            m = self.mats.tagged(m, surface=key)
            self._plain[key] = m
        return m


def createSurfaces(ctx):
    return Surfaces(ctx)
