"""DEAD AIR — static canvas textures (ports of the JS canvas painters), drawn with dalib/canvas2d.py.

Same keys and the same seeded randomness (mulberry32(hashStr(key))) as the JS, so the PNGs are pixel-comparable
with the browser's canvases.

    kit.js       tex.canvas(key, w, h, draw, opts) · tex.wood · tex.burl · tex.shag · tex.weave · tex.pebble ·
                 tex.brushed · tex.label                        (keys 'k.wood|…' …; custom keys as given)
    textures.js  plaid · stripes · colorBars · text · woodPanel · carpet · tiles · noise · gradient · radial ·
                 poster · repeat · staticNoise (animated at runtime: a RuntimeTexture stub, Godot draws it)
    decals.js    labelTex · stencilTex · hazardTex · boltSignTex · newspaperTex · movingPadTex

Every helper returns a cached Texture (THREE.CanvasTexture look-alike: image = the Canvas, key/name, wrapS/wrapT,
repeat/offset/rotation/center, flipY=True, magFilter …). Texture.clone() shares the image (textures.js repeat()).

Files: texture_file(tex) writes godot/assets/textures/<file>.png (+ a .png.import: lossless, mipmaps) the first
time a texture is exported and returns (abs_path, 'res://assets/textures/<file>.png'). The PNG is stored TOP-DOWN as
drawn on the canvas; three's flipY is applied by the material (Godot shaders sample (u, 1-v)); the exported glTF
TEXCOORD_0 is the three.js uv. godot/assets/textures/index.json maps texture key -> file.
"""
from __future__ import annotations

import hashlib
import json
import math
import os
import re

from .canvas2d import Canvas
from .rng import mulberry32, hashStr
from .pal import PAL
from .mathutils3 import Color, js_str, js_json, js_round, clamp, ceilPowerOfTwo, Vector2, JSObj

__all__ = ['Texture', 'CardTexture', 'RuntimeTexture', 'tex', 'shade', 'canvasTex', 'plaid', 'stripes',
           'colorBars', 'text', 'woodPanel', 'carpet', 'tiles', 'noise', 'gradient', 'radial', 'poster', 'repeat',
           'staticNoise', 'labelTex', 'stencilTex', 'hazardTex', 'boltSignTex', 'newspaperTex', 'movingPadTex',
           'Textures', 'texture_file', 'OUT_DIR', 'RepeatWrapping', 'ClampToEdgeWrapping', 'MirroredRepeatWrapping',
           'NearestFilter', 'LinearFilter', 'LinearMipmapLinearFilter', 'SRGBColorSpace', 'getCard', 'cardInfo',
           'cardIds', 'drawTo']

_HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(_HERE, '..', '..'))
OUT_DIR = os.path.join(REPO, 'godot', 'assets', 'textures')   # export.py may redirect (tests)
RES_DIR = 'res://assets/textures'

RepeatWrapping, ClampToEdgeWrapping, MirroredRepeatWrapping = 1000, 1001, 1002
NearestFilter, NearestMipmapNearestFilter, NearestMipmapLinearFilter = 1003, 1004, 1005
LinearFilter, LinearMipmapNearestFilter, LinearMipmapLinearFilter = 1006, 1007, 1008
SRGBColorSpace = 'srgb'


def _jsjoin(v):
    """`${v}` for any value (arrays join with ',' like Array.prototype.toString)."""
    if isinstance(v, (list, tuple)):
        return ','.join('' if x is None else _jsjoin(x) for x in v)
    return js_str(v)


# ================================================================================================= Texture
class Texture:
    """THREE.CanvasTexture look-alike. `key` identifies the drawing (and the PNG file); clones share it."""
    isTexture = True
    isCanvasTexture = True

    def __init__(self, canvas, key, repeat=True, ns='k'):
        self.image = canvas
        self.key = key
        self.name = key
        self.ns = ns
        self.wrapS = self.wrapT = RepeatWrapping if repeat else ClampToEdgeWrapping
        self.repeat = Vector2(1, 1)
        self.offset = Vector2(0, 0)
        self.center = Vector2(0, 0)
        self.rotation = 0
        self.flipY = True
        self.colorSpace = SRGBColorSpace
        self.anisotropy = 4
        self.magFilter = LinearFilter
        self.minFilter = LinearMipmapLinearFilter
        self.generateMipmaps = True
        self.needsUpdate = False
        self.userData = JSObj()
        self.uuid = hashlib.sha1(('%s|%s' % (ns, key)).encode()).hexdigest()

    def __repr__(self):
        return '<Texture %s>' % self.key

    def clone(self):
        t = Texture.__new__(Texture)
        t.__dict__.update(self.__dict__)
        t.repeat = self.repeat.clone()
        t.offset = self.offset.clone()
        t.center = self.center.clone()
        t.userData = JSObj(self.userData)
        return t

    def dispose(self):
        pass

    # ------------------------------------------------------------------------------------------ files
    def file_name(self):
        if self.key is None and self.image is not None:
            # anonymous THREE.CanvasTexture(canvas): key from the pixels
            self.key = 'canvas:' + hashlib.sha1(self.image.to_array().tobytes()).hexdigest()[:12]
            self.name = self.key
        slug = re.sub(r'[^A-Za-z0-9]+', '_', self.key).strip('_')[:48] or 'tex'
        h = hashlib.sha1(('%s|%s' % (self.ns, self.key)).encode('utf-8')).hexdigest()[:8]
        if slug.lower().startswith(self.ns + '_'):
            return '%s_%s.png' % (slug, h)
        return '%s_%s_%s.png' % (self.ns, slug, h)

    def res_path(self):
        return '%s/%s' % (RES_DIR, self.file_name())


class CardTexture:
    """A gfx card (src/gfx/cards.js getCard): drawn by Godot at runtime (scripts/gfx/cards.gd). The material spec
    gets "card"/"cardOpts" and no image."""
    isCard = True
    isTexture = False

    def __init__(self, card, opts=None):
        self.card = card
        self.cardOpts = dict(opts or {})
        self.key = 'card:%s|%s' % (card, js_json(self.cardOpts))
        self.name = card
        self.repeat = Vector2(1, 1)
        self.offset = Vector2(0, 0)
        self.center = Vector2(0, 0)
        self.rotation = 0
        self.wrapS = self.wrapT = ClampToEdgeWrapping
        self.flipY = True
        self.userData = JSObj()
        self.image = None
        info = cardInfo(card)
        if info and info.get('atlas'):
            self.userData['atlas'] = _Atlas(info['atlas'])

    def clone(self):
        c = CardTexture(self.card, self.cardOpts)
        c.repeat = self.repeat.clone()
        c.offset = self.offset.clone()
        return c


class RuntimeTexture(Texture):
    """A texture that only exists at runtime in Godot (staticNoise). Spec: {"map": key, "runtime": true}."""
    isRuntime = True

    def __init__(self, key):
        super().__init__(None, key, True, 'rt')

    def res_path(self):
        return None


class _Atlas(dict):
    """cards.js atlas: { chars, cols, rows, cellW, cellH, uv(ch) -> [u0, v0, u1, v1] } (uv from cards_info.json)."""

    def __getattr__(self, k):
        return self.get(k)

    def uv(self, ch):
        u = self.get('uv') or {}
        if ch in u:
            return list(u[ch])
        first = (self.get('chars') or ' ')[0]
        return list(u.get(first, [0, 0, 1, 1]))


_CARD_INFO = None
CARD_DIRS = [os.path.join(_HERE, 'cards'), os.path.join(REPO, 'godot', 'assets', 'cards')]


def drawTo(ctx, card_id, w, h, time=0, opts=None):
    """cards.js drawTo(ctx, id, w, h, time, opts): draws a pre-rendered card image <CARD_DIRS>/<id>.png scaled to
    w x h at 0,0. The card painters themselves are Godot runtime code (scripts/gfx/cards.gd): a static texture that
    embeds a card needs that PNG; without it this raises KeyError (the JS callers that wrap drawTo in try/catch
    then draw their fallback)."""
    from .canvas2d import Image
    for d in CARD_DIRS:
        p = os.path.join(d, '%s.png' % card_id)
        if os.path.exists(p):
            ctx.drawImage(Image(p), 0, 0, w, h)
            return
    raise KeyError('card image %s.png not found in %s' % (card_id, CARD_DIRS))


def cardIds():
    cardInfo('')
    return list(_CARD_INFO.keys())


def cardInfo(card_id):
    """cards.js cardInfo(id) -> {w, h, fps, alpha, opts} from blender/dalib/cards_info.json when present."""
    global _CARD_INFO
    if _CARD_INFO is None:
        p = os.path.join(_HERE, 'cards_info.json')
        try:
            with open(p, 'r', encoding='utf-8') as f:
                _CARD_INFO = json.load(f)
        except Exception:
            _CARD_INFO = {}
    return _CARD_INFO.get(card_id)


def getCard(card_id, opts=None):
    """cards.js getCard(id, opts): a CardTexture reference (Godot draws the card)."""
    return CardTexture(card_id, opts)


# ================================================================================================== files
_written = {}
_index = None


IMPORT_FILE = """[remap]

importer="texture"
type="CompressedTexture2D"

[params]

compress/mode=0
mipmaps/generate=true
detect_3d/compress_to=0
"""


def texture_file(t, out_dir=None):
    """Writes the PNG of a canvas texture (once per session, only if the bytes changed) and returns
    (abs_path, res_path); None for cards / runtime textures."""
    if t is None or getattr(t, 'isCard', False) or getattr(t, 'isRuntime', False) or t.image is None:
        return None
    d = out_dir or OUT_DIR
    fname = t.file_name()
    path = os.path.join(d, fname)
    k = (d, fname)
    if k not in _written:
        os.makedirs(d, exist_ok=True)
        tmp = '%s.%d.tmp' % (path, os.getpid())
        t.image.save_png(tmp)
        with open(tmp, 'rb') as f:
            new = f.read()
        old = None
        if os.path.exists(path):
            with open(path, 'rb') as f:
                old = f.read()
        if old != new:
            os.replace(tmp, path)
        else:
            os.remove(tmp)
        imp = path + '.import'
        if not os.path.exists(imp):
            with open(imp, 'w') as f:
                f.write(IMPORT_FILE)
        _written[k] = True
        entry = {'file': fname, 'w': t.image.width, 'h': t.image.height,
                 'wrap': 'repeat' if t.wrapS == RepeatWrapping else 'clamp', 'ns': t.ns}
        _save_index(d, t.key, entry)
    return path, t.res_path()


def _save_index(d, key, entry):
    """Merges one entry into <d>/index.json (re-read right before writing: several builders may run at once)."""
    p = os.path.join(d, 'index.json')
    try:
        with open(p, 'r', encoding='utf-8') as f:
            idx = json.load(f)
    except Exception:
        idx = {}
    if idx.get(key) == entry:
        return
    idx[key] = entry
    tmp = '%s.%d.tmp' % (p, os.getpid())
    with open(tmp, 'w', encoding='utf-8') as f:
        json.dump(dict(sorted(idx.items())), f, indent=1, ensure_ascii=False)
    os.replace(tmp, p)


# ================================================================================================== helpers
def shade(hex_, amt):
    """kit.js / textures.js shade(): lighten toward white (amt >= 0) or darken (amt < 0) in LINEAR space."""
    c = Color(hex_)
    if amt >= 0:
        c.lerp(Color(1, 1, 1), amt)
    else:
        c.multiplyScalar(1 + amt)
    return '#' + c.getHexString()


def _merge(opts, kw):
    o = dict(opts or {})
    o.update(kw)
    return o


# ============================================================================================ kit.js `tex`
_kit_cache = {}


def canvasTex(key, w, h, draw, opts=None):
    """kit.js canvasTex: cached canvas texture; draw(ctx, w, h, rand). opts: {repeat=True, fonts=False}."""
    opts = opts or {}
    t = _kit_cache.get(key)
    if t is not None:
        return t
    cv = Canvas(w, h)
    ctx = cv.getContext('2d')
    ctx.clearRect(0, 0, w, h)
    draw(ctx, w, h, mulberry32(hashStr(key)))
    t = Texture(cv, key, opts.get('repeat', True) is not False, 'k')
    t.anisotropy = 8
    _kit_cache[key] = t
    return t


def _wear(ctx, w, h, rand, amount=0.5, color='#000'):
    """Scuffs / scratches / edge wear, drawn over a texture's canvas."""
    if amount <= 0:
        return
    ctx.save()
    ctx.strokeStyle = color
    ctx.lineCap = 'round'
    i = 0
    while i < 60 * amount:
        ctx.globalAlpha = 0.04 + rand() * 0.1 * amount
        ctx.lineWidth = 0.5 + rand() * 1.5
        x, y, a, l = rand() * w, rand() * h, rand() * math.pi, 4 + rand() * 30
        ctx.beginPath()
        ctx.moveTo(x, y)
        ctx.quadraticCurveTo(x + math.cos(a) * l * 0.5 + rand() * 4, y + math.sin(a) * l * 0.5,
                             x + math.cos(a) * l, y + math.sin(a) * l)
        ctx.stroke()
        i += 1
    i = 0
    while i < 25 * amount:
        ctx.globalAlpha = 0.03 + rand() * 0.06 * amount
        ctx.fillStyle = color
        ctx.beginPath()
        ctx.ellipse(rand() * w, rand() * h, 3 + rand() * 14, 2 + rand() * 8, rand() * 3, 0, math.pi * 2)
        ctx.fill()
        i += 1
    ctx.restore()


class _KitTex:
    """kit.js `tex` (K.tex.wood(...) …)."""

    canvas = staticmethod(canvasTex)

    # Long-grain wood (flat-sawn cathedrals + straight grain + color bands). Grain runs along V (texture y).
    # opts: { planks=0 (vertical seams), dark=0.32 (grain contrast), wear=0, size=512 }
    @staticmethod
    def wood(base=None, opts=None, **kw):
        base = PAL.teak if base is None else base
        o = _merge(opts, kw)
        planks, dark, wr, size = o.get('planks', 0), o.get('dark', 0.32), o.get('wear', 0), o.get('size', 512)
        key = 'k.wood|%s|%s|%s|%s|%s' % (_jsjoin(base), _jsjoin(planks), _jsjoin(dark), _jsjoin(wr), _jsjoin(size))

        def draw(ctx, w, h, rand):
            ctx.fillStyle = base
            ctx.fillRect(0, 0, w, h)
            for i in range(14):  # soft color bands
                ctx.globalAlpha = 0.12 + rand() * 0.12
                ctx.fillStyle = shade(base, (rand() - 0.5) * 0.3)
                ctx.fillRect(rand() * w, 0, 8 + rand() * 40, h)
            ctx.lineCap = 'round'
            for i in range(70):  # straight grain lines (wrap horizontally)
                x0, amp, fr, ph = rand() * w, 1 + rand() * 4, 0.004 + rand() * 0.01, rand() * 6
                ctx.strokeStyle = shade(base, -dark * (0.4 + rand() * 0.8))
                ctx.globalAlpha = 0.25 + rand() * 0.35
                ctx.lineWidth = 0.6 + rand() * 1.4
                for off in (0, -w, w):
                    ctx.beginPath()
                    y = 0
                    while y <= h:
                        x = x0 + off + math.sin(y * fr * 6.283 / 6 + ph) * amp + math.sin(y * 0.05 + i) * 0.6
                        if y == 0:
                            ctx.moveTo(x, y)
                        else:
                            ctx.lineTo(x, y)
                        y += 8
                    ctx.stroke()
            for k in range(3):  # cathedral arches
                cx, cy, spread = rand() * w, rand() * h, 30 + rand() * 50
                for r in range(7):
                    ctx.strokeStyle = shade(base, -dark * (0.5 + rand() * 0.5))
                    ctx.globalAlpha = 0.18 + rand() * 0.2
                    ctx.lineWidth = 1 + rand() * 1.5
                    s = spread * (0.35 + r * 0.14)
                    ctx.beginPath()
                    ctx.moveTo(cx - s, cy + h * 0.45)
                    ctx.bezierCurveTo(cx - s, cy - s * 0.3, cx + s * 0.9, cy - s * 0.4, cx + s, cy + h * 0.45)
                    ctx.stroke()
            ctx.globalAlpha = 1
            if planks > 0:
                pw = w / planks
                for p in range(int(math.ceil(planks))):
                    ctx.fillStyle = shade(base, -0.6)
                    ctx.fillRect(p * pw, 0, 2, h)
                    ctx.fillStyle = shade(base, 0.2)
                    ctx.fillRect(p * pw + 2, 0, 1, h)
                    ctx.globalAlpha = 0.1
                    ctx.fillStyle = '#000' if rand() < 0.5 else '#fff'
                    ctx.fillRect(p * pw + 3, 0, pw - 3, h)
                    ctx.globalAlpha = 1
            _wear(ctx, w, h, rand, wr, shade(base, -0.7))
        return canvasTex(key, size, size, draw)

    # Walnut burl veneer (swirls and eyes): dashboards, console trims, radio cabinets.
    @staticmethod
    def burl(base=None, opts=None, **kw):
        base = PAL.walnut if base is None else base
        o = _merge(opts, kw)
        size = o.get('size', 512)

        def draw(ctx, w, h, rand):
            ctx.fillStyle = base
            ctx.fillRect(0, 0, w, h)
            for i in range(260):
                x, y, r = rand() * w, rand() * h, 4 + rand() * 26
                ctx.strokeStyle = _burl_col(base, rand)
                ctx.globalAlpha = 0.15 + rand() * 0.3
                ctx.lineWidth = 0.8 + rand() * 1.6
                ctx.beginPath()
                ctx.ellipse(x, y, r, r * (0.4 + rand() * 0.6), rand() * 3.14, 0, math.pi * (1 + rand()))
                ctx.stroke()
            for i in range(40):
                ctx.fillStyle = shade(base, -0.6)
                ctx.globalAlpha = 0.5
                ctx.beginPath()
                ctx.arc(rand() * w, rand() * h, 1 + rand() * 2.5, 0, 7)
                ctx.fill()
            ctx.globalAlpha = 1
        return canvasTex('k.burl|%s|%s' % (_jsjoin(base), _jsjoin(size)), size, size, draw)

    # Shag pile: dense short strands with light tips and dark roots. fleck = second yarn color.
    @staticmethod
    def shag(base=None, fleck=None, opts=None, **kw):
        base = PAL.shagOrange if base is None else base
        fleck = PAL.harvestGold if fleck is None else fleck
        o = _merge(opts, kw)
        size, density = o.get('size', 512), o.get('density', 1)

        def draw(ctx, w, h, rand):
            ctx.fillStyle = shade(base, -0.35)
            ctx.fillRect(0, 0, w, h)
            ctx.lineCap = 'round'
            n = js_round(size * size * 0.09 * density)
            for i in range(n):
                x, y, a, l = rand() * w, rand() * h, rand() * 6.283, 3 + rand() * 6
                r = rand()
                ctx.strokeStyle = fleck if r < 0.08 else shade(base, -0.3 + rand() * 0.45)
                ctx.globalAlpha = 0.55 + rand() * 0.45
                ctx.lineWidth = 1.4 + rand() * 1.6
                ctx.beginPath()
                ctx.moveTo(x, y)
                ctx.quadraticCurveTo(x + math.cos(a + 0.8) * l * 0.6, y + math.sin(a + 0.8) * l * 0.6,
                                     x + math.cos(a) * l, y + math.sin(a) * l)
                ctx.stroke()
                if rand() < 0.3:  # bright tip
                    ctx.fillStyle = shade(fleck if r < 0.08 else base, 0.25)
                    ctx.globalAlpha = 0.6
                    ctx.fillRect(x + math.cos(a) * l - 0.8, y + math.sin(a) * l - 0.8, 1.6, 1.6)
            ctx.globalAlpha = 1
        return canvasTex('k.shag|%s|%s|%s|%s' % (_jsjoin(base), _jsjoin(fleck), _jsjoin(size), _jsjoin(density)),
                         size, size, draw)

    # Upholstery weave. pattern: 'plain' | 'tweed' (multi-color flecks) | 'cord' (corduroy ribs along V) | 'herring'
    @staticmethod
    def weave(base=None, opts=None, **kw):
        base = PAL.avocado if base is None else base
        o = _merge(opts, kw)
        pattern, thread, fleck = o.get('pattern', 'plain'), o.get('thread'), o.get('fleck', [])
        size, scale = o.get('size', 256), o.get('scale', 4)
        key = 'k.weave|%s|%s|%s|%s|%s|%s' % (_jsjoin(base), _jsjoin(pattern), _jsjoin(thread), _jsjoin(fleck),
                                             _jsjoin(size), _jsjoin(scale))

        def draw(ctx, w, h, rand):
            ctx.fillStyle = base
            ctx.fillRect(0, 0, w, h)
            s = scale
            lite = thread if thread is not None else shade(base, 0.14)
            dark = shade(base, -0.22)
            if pattern == 'cord':
                x = 0
                while x < w:
                    g = ctx.createLinearGradient(x, 0, x + s * 2, 0)
                    g.addColorStop(0, dark)
                    g.addColorStop(0.5, lite)
                    g.addColorStop(1, dark)
                    ctx.fillStyle = g
                    ctx.fillRect(x, 0, s * 2, h)
                    x += s * 2
            elif pattern == 'herring':
                y = 0
                while y < h:
                    x = 0
                    while x < w:
                        band = int(math.floor(x / (s * 4))) % 2
                        v = int(x / s + (y / s if band else -y / s))
                        ctx.fillStyle = lite if (v & 3) < 2 else dark
                        ctx.globalAlpha = 0.5
                        ctx.fillRect(x, y, s, s)
                        x += s
                    y += s
            else:
                y = 0
                while y < h:
                    x = 0
                    while x < w:
                        ctx.fillStyle = lite if math.fmod((x + y) / s, 2) else dark
                        ctx.globalAlpha = 0.35 + rand() * 0.15
                        ctx.fillRect(x, y, s, s * 0.8)
                        x += s
                    y += s
            ctx.globalAlpha = 1
            fl = [shade(base, 0.35), shade(base, -0.45), PAL.cream] if pattern == 'tweed' and not len(fleck) else fleck
            n = size * 6 if len(fl) else size * 2
            i = 0
            while i < n:
                ctx.fillStyle = fl[int(math.floor(rand() * len(fl)))] if len(fl) else ('#fff' if rand() < 0.5 else '#000')
                ctx.globalAlpha = 0.5 + rand() * 0.4 if len(fl) else 0.05
                ctx.fillRect(rand() * w, rand() * h, 1 + rand() * 2.5, 1)
                i += 1
            ctx.globalAlpha = 1
        return canvasTex(key, size, size, draw)

    # Pebbled leatherette / tolex / vinyl grain.
    @staticmethod
    def pebble(base=None, opts=None, **kw):
        base = PAL.chocolate if base is None else base
        size = _merge(opts, kw).get('size', 256)

        def draw(ctx, w, h, rand):
            ctx.fillStyle = base
            ctx.fillRect(0, 0, w, h)
            for i in range(size * 10):
                ctx.fillStyle = shade(base, -0.18) if rand() < 0.5 else shade(base, 0.1)
                ctx.globalAlpha = 0.35
                ctx.beginPath()
                ctx.arc(rand() * w, rand() * h, 0.6 + rand() * 1.6, 0, 7)
                ctx.fill()
            ctx.globalAlpha = 1
        return canvasTex('k.pebble|%s|%s' % (_jsjoin(base), _jsjoin(size)), size, size, draw)

    # Brushed metal: fine horizontal streaks (along U).
    @staticmethod
    def brushed(base='#C9CED6', opts=None, **kw):
        size = _merge(opts, kw).get('size', 256)

        def draw(ctx, w, h, rand):
            ctx.fillStyle = base
            ctx.fillRect(0, 0, w, h)
            for i in range(size * 3):
                ctx.fillStyle = shade(base, 0.25) if rand() < 0.5 else shade(base, -0.2)
                ctx.globalAlpha = 0.15 + rand() * 0.2
                ctx.fillRect(rand() * w - 20, rand() * h, 20 + rand() * 120, 1)
            ctx.globalAlpha = 1
        return canvasTex('k.brushed|%s|%s' % (_jsjoin(base), _jsjoin(size)), size, size, draw)

    # Printed label / decal / nameplate (not repeating). opts: { sub, bg, fg, accent, font='Bungee',
    # subFont='Titan One', w=512, h=256, radius=0.12 (of h), border=0.05 (of h), stripes:[colors], wear=0.2,
    # transparent=false, outline=null }. Pass opts in the JS key order (the key is JSON.stringify(opts)).
    @staticmethod
    def label(text='WZTV', opts=None, **kw):
        o = _merge(opts, kw)
        sub = o.get('sub', '')
        bg, fg, accent = o.get('bg', PAL.cream), o.get('fg', PAL.chocolate), o.get('accent', PAL.burntOrange)
        font, subFont = o.get('font', 'Bungee'), o.get('subFont', 'Titan One')
        w, h = o.get('w', 512), o.get('h', 256)
        radius, border, stripes = o.get('radius', 0.12), o.get('border', 0.05), o.get('stripes')
        wr, transparent, outline = o.get('wear', 0.2), o.get('transparent', False), o.get('outline')

        def draw(ctx, W, H, rand):
            if not transparent:
                ctx.fillStyle = shade(bg, -0.35)
                ctx.fillRect(0, 0, W, H)
            r, b = H * radius, H * border

            def rr(x, y, ww, hh, rad):
                ctx.beginPath()
                ctx.roundRect(x, y, ww, hh, rad)
            rr(0, 0, W, H, r)
            ctx.fillStyle = accent
            ctx.fill()
            rr(b, b, W - 2 * b, H - 2 * b, max(1, r - b))
            ctx.fillStyle = bg
            ctx.fill()
            ctx.save()
            ctx.clip()
            if stripes:
                sh = (H - 2 * b) * 0.1
                for i, c in enumerate(stripes):
                    ctx.fillStyle = c
                    ctx.fillRect(0, H * 0.62 + i * sh * 1.1, W, sh)
            ctx.restore()
            ctx.textAlign = 'center'
            ctx.textBaseline = 'middle'
            size = H * (0.42 if sub else 0.55)

            def fit(f, s, mx):
                ctx.font = '%spx "%s", "Arial Black", sans-serif' % (js_str(s), f)
                while ctx.measureText(text).width > mx and s > 6:
                    s *= 0.93
                    ctx.font = '%spx "%s", "Arial Black", sans-serif' % (js_str(s), f)
                return s
            size = fit(font, size, W * 0.84)
            ty = H * 0.4 if sub else H * 0.52
            if outline:
                ctx.lineWidth = size * 0.14
                ctx.strokeStyle = outline
                ctx.lineJoin = 'round'
                ctx.strokeText(text, W / 2, ty)
            ctx.fillStyle = shade(fg, -0.35)
            ctx.globalAlpha = 0.35
            ctx.fillText(text, W / 2 + size * 0.05, ty + size * 0.06)
            ctx.globalAlpha = 1
            ctx.fillStyle = fg
            ctx.fillText(text, W / 2, ty)
            if sub:
                ss = H * 0.17
                ctx.font = '%spx "%s", "Arial Black", sans-serif' % (js_str(ss), subFont)
                while ctx.measureText(sub).width > W * 0.8 and ss > 6:
                    ss *= 0.93
                    ctx.font = '%spx "%s", "Arial Black", sans-serif' % (js_str(ss), subFont)
                ctx.fillStyle = accent
                ctx.fillText(sub, W / 2, H * 0.74)
            _wear(ctx, W, H, rand, wr, shade(bg, -0.6))
        return canvasTex('k.label|%s|%s' % (text, js_json(o)), w, h, draw, {'repeat': False, 'fonts': True})


def _burl_col(base, rand):
    # JS: shade(base, rand() < 0.6 ? -0.35 - rand() * 0.3 : 0.15 + rand() * 0.15)
    return shade(base, -0.35 - rand() * 0.3 if rand() < 0.6 else 0.15 + rand() * 0.15)


tex = _KitTex()


# ============================================================================================ textures.js
_tx_cache = {}


def _cached(key, w, h, builder, opts=None):
    """textures.js cached(): builder(ctx, canvas, rand) draws; returns the shared texture for `key`."""
    t = _tx_cache.get(key)
    if t is not None:
        return t
    canvas = Canvas(w, h)
    ctx = canvas.getContext('2d')
    builder(ctx, canvas, mulberry32(hashStr(key)))
    o = opts or {}
    t = Texture(canvas, key, o.get('repeat', True), 'tx')
    t.colorSpace = SRGBColorSpace if o.get('srgb', True) else 'linear'
    _tx_cache[key] = t
    return t


def plaid(base, lines=None, scale=1):
    """Tartan: lines = [[color, width(0..1 of tile), offset(0..1)], ...] woven both ways over base."""
    lines = lines if lines is not None else []

    def b(ctx, c, rand):
        ctx.fillStyle = base
        ctx.fillRect(0, 0, 256, 256)
        for color, w, o in lines:
            ctx.fillStyle = color
            ctx.globalAlpha = 0.55
            ctx.fillRect(0, o * 256, 256, w * 256)
            ctx.fillRect(o * 256, 0, w * 256, 256)
        # Twill weave: fine diagonal hatching gives the cloth a woven feel.
        ctx.globalAlpha = 0.07
        ctx.strokeStyle = '#000'
        for i in range(-256, 256, 4):
            ctx.beginPath()
            ctx.moveTo(i, 256)
            ctx.lineTo(i + 256, 0)
            ctx.stroke()
        ctx.globalAlpha = 0.05
        for i in range(900):
            ctx.fillStyle = '#fff' if rand() < 0.5 else '#000'
            ctx.fillRect(rand() * 256, rand() * 256, 2, 1)
        ctx.globalAlpha = 1
    t = _cached('plaid|%s|%s' % (_jsjoin(base), js_json(lines)), 256, 256, b)
    return _withRepeat(t, scale, scale)


def stripes(colors, vertical=True, count=None):
    """Equal-width color stripes, repeated `count` bands in total."""
    count = len(colors) if count is None else count

    def b(ctx, c, rand):
        n = max(1, count)
        step = 256 / n
        for i in range(n):
            ctx.fillStyle = colors[i % len(colors)]
            if vertical:
                ctx.fillRect(math.floor(i * step), 0, math.ceil(step), 256)
            else:
                ctx.fillRect(0, math.floor(i * step), 256, math.ceil(step))
        # A soft fabric sheen between stripes.
        ctx.globalAlpha = 0.08
        ctx.fillStyle = '#000'
        for i in range(1, n):
            if vertical:
                ctx.fillRect(math.floor(i * step) - 1, 0, 2, 256)
            else:
                ctx.fillRect(0, math.floor(i * step) - 1, 256, 2)
        ctx.globalAlpha = 1
    return _cached('stripes|%s|%s|%s' % (','.join(colors), js_str(vertical), js_str(count)), 256, 256, b)


def colorBars():
    """Cartoonized SMPTE color bars (GDD §3.2) with the reverse-blue strip and PLUGE row."""
    def b(ctx, c, rand):
        bars = PAL.BARS
        w = 256 / 7
        for i, col in enumerate(bars):
            ctx.fillStyle = col
            ctx.fillRect(math.floor(i * w), 0, math.ceil(w), 128)
        rev = [PAL.barBlue, '#141018', PAL.barMagenta, '#141018', PAL.barCyan, '#141018', PAL.barWhite]
        for i, col in enumerate(rev):
            ctx.fillStyle = col
            ctx.fillRect(math.floor(i * w), 128, math.ceil(w), 16)
        pluge = ['#1D2A5C', '#F4F1E8', '#3A1D5C', '#141018', '#0E0B12', '#141018', '#1A1620']
        pw = [46, 46, 46, 46, 24, 24, 24]
        x = 0
        for i, col in enumerate(pluge):
            ctx.fillStyle = col
            ctx.fillRect(x, 144, pw[i] + 1, 48)
            x += pw[i]
    return _cached('colorBars', 256, 192, b, {'repeat': False})


def text(s, opts=None, **kw):
    """Text label. opts: { font='Bungee', size=64, color='#fff', bg=null, w, h, align='center', pad=0.18, weight='' }"""
    o = _merge(opts, kw)
    font, size, color = o.get('font', 'Bungee'), o.get('size', 64), o.get('color', '#ffffff')
    bg, align, pad, weight = o.get('bg'), o.get('align', 'center'), o.get('pad', 0.18), o.get('weight', '')
    probe = Canvas(4, 4).getContext('2d')
    fontStr = ('%s %spx "%s", "Arial Black", sans-serif' % (js_str(weight), js_str(size), font)).strip()
    probe.font = fontStr
    lines = js_str(s).split('\n')
    tw = max(probe.measureText(l).width for l in lines)
    w = o.get('w') or min(1024, ceilPowerOfTwo(math.ceil(tw + size * pad * 2)))
    h = o.get('h') or min(1024, ceilPowerOfTwo(math.ceil(size * (len(lines) * 1.2 + pad * 2))))

    def b(ctx, c, rand):
        if bg:
            ctx.fillStyle = bg
            ctx.fillRect(0, 0, w, h)
        ctx.font = fontStr
        ctx.fillStyle = color
        ctx.textBaseline = 'middle'
        ctx.textAlign = align
        x = size * pad if align == 'left' else w - size * pad if align == 'right' else w / 2
        lh = size * 1.2
        y0 = h / 2 - ((len(lines) - 1) * lh) / 2
        for i, l in enumerate(lines):
            ctx.fillText(l, x, y0 + i * lh)
    return _cached('text|%s|%s' % (js_str(s), js_json(o)), int(w), int(h), b, {'repeat': False})


def woodPanel(base=None):
    """Lacquered walnut paneling: vertical planks, grooves and flowing grain."""
    base = PAL.walnut if base is None else base

    def b(ctx, c, rand):
        ctx.fillStyle = base
        ctx.fillRect(0, 0, 256, 256)
        planks = 4
        pw = 256 / planks
        for p in range(planks):
            x0 = p * pw
            ctx.fillStyle = shade(base, (rand() - 0.5) * 0.16)
            ctx.fillRect(x0, 0, pw, 256)
            ctx.lineWidth = 1.2
            for g in range(9):
                gx = x0 + rand() * pw
                amp = 2 + rand() * 5
                freq = 0.01 + rand() * 0.02
                ctx.strokeStyle = shade(base, -0.25 - rand() * 0.15)
                ctx.globalAlpha = 0.35 + rand() * 0.3
                ctx.beginPath()
                for y in range(0, 257, 8):
                    x = gx + math.sin(y * freq + g) * amp
                    if y == 0:
                        ctx.moveTo(x, y)
                    else:
                        ctx.lineTo(x, y)
                ctx.stroke()
            ctx.globalAlpha = 1
            ctx.fillStyle = shade(base, -0.55)
            ctx.fillRect(x0, 0, 2, 256)
            ctx.fillStyle = shade(base, 0.18)
            ctx.fillRect(x0 + 2, 0, 1, 256)
    return _cached('wood|%s' % js_str(base), 256, 256, b)


def carpet(base=None, fleck=None):
    """Shag carpet: dense colored flecks over a base."""
    base = PAL.shagOrange if base is None else base
    fleck = PAL.harvestGold if fleck is None else fleck

    def b(ctx, c, rand):
        ctx.fillStyle = base
        ctx.fillRect(0, 0, 256, 256)
        dark = shade(base, -0.3)
        light = shade(base, 0.15)
        for i in range(5200):
            r = rand()
            ctx.fillStyle = dark if r < 0.45 else light if r < 0.85 else fleck
            ctx.globalAlpha = 0.35 + rand() * 0.5
            x, y = rand() * 256, rand() * 256
            ctx.beginPath()
            ctx.ellipse(x, y, 1 + rand() * 1.6, 1 + rand() * 1.6, 0, 0, math.pi * 2)
            ctx.fill()
        ctx.globalAlpha = 1
    return _cached('carpet|%s|%s' % (js_str(base), js_str(fleck)), 256, 256, b)


def tiles(a='#E8E1D0', b_='#B5472A', n=4):
    """Checker tiles (n x n per texture) with soft grout and a faint gloss."""
    def b(ctx, c, rand):
        s = 256 / n
        for y in range(n):
            for x in range(n):
                ctx.fillStyle = shade(b_ if (x + y) % 2 else a, (rand() - 0.5) * 0.06)
                ctx.fillRect(x * s, y * s, s, s)
        ctx.strokeStyle = 'rgba(40,24,30,0.35)'
        ctx.lineWidth = 2
        for i in range(n + 1):
            ctx.beginPath()
            ctx.moveTo(i * s, 0)
            ctx.lineTo(i * s, 256)
            ctx.stroke()
            ctx.beginPath()
            ctx.moveTo(0, i * s)
            ctx.lineTo(256, i * s)
            ctx.stroke()
    return _cached('tiles|%s|%s|%s' % (js_str(a), js_str(b_), js_str(n)), 256, 256, b)


def noise(w=128, h=128, amount=0.2):
    """Grey value noise around mid-grey (+-amount), handy as a subtle overlay/roughness map."""
    import numpy as np

    def b(ctx, c, rand):
        img = ctx.createImageData(w, h)
        vals = np.empty(w * h, dtype=np.uint8)
        for i in range(w * h):
            vals[i] = js_round(255 * clamp(0.5 + (rand() * 2 - 1) * amount, 0, 1))
        d = img.data.reshape(-1, 4)
        d[:, 0] = d[:, 1] = d[:, 2] = vals
        d[:, 3] = 255
        ctx.putImageData(img, 0, 0)
    return _cached('noise|%s|%s|%s' % (js_str(w), js_str(h), js_str(amount)), w, h, b)


def gradient(stops, vertical=True):
    """Linear gradient. stops: ['#a', '#b', ...] (evenly spaced) or [[0,'#a'], [1,'#b']]."""
    def b(ctx, c, rand):
        g = ctx.createLinearGradient(0, 0, 0, 256) if vertical else ctx.createLinearGradient(0, 0, 256, 0)
        for i, s in enumerate(stops):
            if isinstance(s, (list, tuple)):
                g.addColorStop(s[0], s[1])
            else:
                g.addColorStop(i / max(1, len(stops) - 1), s)
        ctx.fillStyle = g
        ctx.fillRect(0, 0, c.width, c.height)
    return _cached('grad|%s|%s' % (js_json(stops), js_str(vertical)), 4 if vertical else 256, 256 if vertical else 4,
                   b, {'repeat': False})


_RADIAL_DEFAULT = [[0, 'rgba(255,255,255,1)'], [0.45, 'rgba(255,255,255,0.45)'], [1, 'rgba(255,255,255,0)']]


def radial(stops=None):
    """Radial gradient (center -> edge). stops as in gradient(); default = soft white falloff to transparent."""
    stops = _RADIAL_DEFAULT if stops is None else stops

    def b(ctx, c, rand):
        g = ctx.createRadialGradient(64, 64, 0, 64, 64, 64)
        for i, s in enumerate(stops):
            if isinstance(s, (list, tuple)):
                g.addColorStop(s[0], s[1])
            else:
                g.addColorStop(i / max(1, len(stops) - 1), s)
        ctx.fillStyle = g
        ctx.fillRect(0, 0, 128, 128)
    return _cached('radial|%s' % js_json(stops), 128, 128, b, {'repeat': False})


def poster(opts=None, **kw):
    """Retro show poster: sunburst background, big title, subtitle band.
    opts: { title='WZTV', sub='CHANNEL 13', bg=PAL.harvestGold, fg=PAL.chocolate, accent=PAL.burntOrange,
    font='Bungee', w=256, h=384 }"""
    o = _merge(opts, kw)
    title, sub = o.get('title', 'WZTV'), o.get('sub', 'CHANNEL 13')
    bg, fg, accent = o.get('bg', PAL.harvestGold), o.get('fg', PAL.chocolate), o.get('accent', PAL.burntOrange)
    font, w, h = o.get('font', 'Bungee'), o.get('w', 256), o.get('h', 384)

    def b(ctx, c, rand):
        ctx.fillStyle = bg
        ctx.fillRect(0, 0, w, h)
        cx, cy, rays = w / 2, h * 0.42, 18
        ctx.fillStyle = accent
        ctx.globalAlpha = 0.55
        for i in range(rays):
            a0 = (i / rays) * math.pi * 2
            a1 = a0 + math.pi / rays
            ctx.beginPath()
            ctx.moveTo(cx, cy)
            ctx.lineTo(cx + math.cos(a0) * h, cy + math.sin(a0) * h)
            ctx.lineTo(cx + math.cos(a1) * h, cy + math.sin(a1) * h)
            ctx.fill()
        ctx.globalAlpha = 1
        ctx.lineWidth = w * 0.035
        ctx.strokeStyle = fg
        ctx.strokeRect(ctx.lineWidth, ctx.lineWidth, w - ctx.lineWidth * 2, h - ctx.lineWidth * 2)
        ctx.textAlign = 'center'
        ctx.textBaseline = 'middle'
        size = w * 0.24
        ctx.font = '%spx "%s", "Arial Black", sans-serif' % (js_str(size), font)
        while ctx.measureText(title).width > w * 0.84 and size > 8:
            size *= 0.92
            ctx.font = '%spx "%s", "Arial Black", sans-serif' % (js_str(size), font)
        ctx.fillStyle = shade(fg, -0.3)
        ctx.fillText(title, cx + 3, cy + 3)
        ctx.fillStyle = PAL.capWhite
        ctx.fillText(title, cx, cy)
        ctx.fillStyle = fg
        ctx.fillRect(w * 0.08, h * 0.76, w * 0.84, h * 0.13)
        ctx.fillStyle = bg
        ctx.font = '%spx "%s", "Arial Black", sans-serif' % (js_str(w * 0.09), font)
        ctx.fillText(sub, cx, h * 0.825)
    return _cached('poster|%s' % js_json(o), w, h, b, {'repeat': False})


_static = None


def staticNoise():
    """Animated TV snow: re-randomized at ~24 Hz by the Godot runtime (textures.gd). Static builds only get a
    reference (spec {"map": "staticNoise", "runtime": true})."""
    global _static
    if _static is None:
        _static = RuntimeTexture('staticNoise')
    return _static


def _withRepeat(t, rx, ry):
    """Textures are shared: callers wanting their own repeat get a lightweight clone (same image)."""
    if rx == 1 and ry == 1:
        return t
    key = '%s|rep%sx%s' % (t.name, js_str(rx), js_str(ry))
    c = _tx_cache.get(key)
    if c is None:
        c = t.clone()
        c.repeat.set(rx, ry)
        c.name = key
        _tx_cache[key] = c
    return c


def repeat(t, rx, ry=None):
    """Shared-texture repeat helper for any cached texture."""
    return _withRepeat(t, rx, rx if ry is None else ry)


class Textures:
    """game.tex: the textures.js helpers (plaid, stripes, colorBars, text, woodPanel, carpet, tiles, noise,
    staticNoise, poster, gradient, radial, repeat)."""

    def __init__(self, game=None):
        self.game = game
        self.plaid, self.stripes, self.colorBars, self.text = plaid, stripes, colorBars, text
        self.woodPanel, self.carpet, self.tiles, self.noise = woodPanel, carpet, tiles, noise
        self.staticNoise, self.poster, self.gradient, self.radial, self.repeat = staticNoise, poster, gradient, \
            radial, repeat

    def init(self):
        pass

    def update(self, *a):
        pass


# ============================================================================================== decals.js
_dc_cache = {}
FALLBACK = '"Arial Black", "Helvetica Neue", sans-serif'


def _make(key, w, h, draw):
    t = _dc_cache.get(key)
    if t is not None:
        return t
    c = Canvas(w, h)
    draw(c.getContext('2d'), w, h)
    t = Texture(c, key, False, 'dc')
    _dc_cache[key] = t
    return t


def _fit(ctx, lines, font, maxW, maxH):
    """Largest font size (<= h*0.72 per line) whose widest line fits maxW."""
    size = math.floor(maxH / len(lines) / 1.15)
    while size > 6:
        ctx.font = '%spx "%s", %s' % (js_str(size), font, FALLBACK)
        if max(ctx.measureText(l).width for l in lines) <= maxW:
            break
        size -= 2
    return size


def labelTex(txt, opts=None, **kw):
    """labelTex(text, { w=512, h=128, fg, bg, font, stroke, border, pad })"""
    o = _merge(opts, kw)
    w, h, fg, bg = o.get('w', 512), o.get('h', 128), o.get('fg', '#F4F1E8'), o.get('bg')
    font, stroke, border, pad = o.get('font', 'Bungee'), o.get('stroke'), o.get('border'), o.get('pad', 0.1)

    def draw(x, W, H):
        if bg:
            x.fillStyle = bg
            x.fillRect(0, 0, w, h)
        if border:
            x.strokeStyle = border
            x.lineWidth = h * 0.06
            x.strokeRect(x.lineWidth, x.lineWidth, w - x.lineWidth * 2, h - x.lineWidth * 2)
        lines = js_str(txt).split('\n')
        size = _fit(x, lines, font, w * (1 - pad * 2), h * (1 - pad * 2))
        x.textAlign = 'center'
        x.textBaseline = 'middle'
        lh = size * 1.12
        y0 = h / 2 - ((len(lines) - 1) * lh) / 2
        for i, l in enumerate(lines):
            if stroke:
                x.strokeStyle = stroke
                x.lineWidth = size * 0.14
                x.lineJoin = 'round'
                x.strokeText(l, w / 2, y0 + i * lh)
            x.fillStyle = fg
            x.fillText(l, w / 2, y0 + i * lh)
    return _make('label|%s|%s' % (js_str(txt), js_json(o)), w, h, draw)


def stencilTex(txt, opts=None, **kw):
    """Spray-painted stencil on transparent (crates, the elephant door). opts: { w=512, h=256, ink }"""
    o = _merge(opts, kw)
    w, h, ink = o.get('w', 512), o.get('h', 256), o.get('ink', '#2A2230')

    def draw(x, W, H):
        lines = js_str(txt).split('\n')
        size = _fit(x, lines, 'Bungee', w * 0.86, h * 0.8)
        x.textAlign = 'center'
        x.textBaseline = 'middle'
        x.fillStyle = ink
        lh = size * 1.12
        y0 = h / 2 - ((len(lines) - 1) * lh) / 2
        for i, l in enumerate(lines):
            x.fillText(l, w / 2, y0 + i * lh)
        # Stencil bridges + overspray: knock thin vertical gaps out of the letters and speckle the edges.
        x.globalCompositeOperation = 'destination-out'
        i = 0.0
        while i < w:
            x.fillRect(i, 0, max(2, size * 0.06), h)
            i += size * 0.62
        x.globalCompositeOperation = 'source-over'
        x.globalAlpha = 0.18
        for i in range(500):
            x.fillRect(math.fmod(i * 97, w), math.fmod(i * 57, h), 2, 2)
        x.globalAlpha = 1
    return _make('stencil|%s|%s|%s|%s' % (js_str(txt), js_str(w), js_str(h), js_str(ink)), w, h, draw)


def hazardTex():
    def draw(x, w, h):
        x.fillStyle = '#F4C21E'
        x.fillRect(0, 0, w, h)
        x.fillStyle = '#231E24'
        for i in range(-h, w + h, 48):
            x.beginPath()
            x.moveTo(i, h)
            x.lineTo(i + 24, h)
            x.lineTo(i + 24 + h, 0)
            x.lineTo(i + h, 0)
            x.closePath()
            x.fill()
    return _make('hazard', 256, 64, draw)


def boltSignTex():
    def draw(x, w, h):
        x.fillStyle = '#231E24'
        x.beginPath()
        x.moveTo(128, 14)
        x.lineTo(246, 226)
        x.lineTo(10, 226)
        x.closePath()
        x.fill()
        x.fillStyle = '#F4C21E'
        x.beginPath()
        x.moveTo(128, 40)
        x.lineTo(224, 212)
        x.lineTo(32, 212)
        x.closePath()
        x.fill()
        x.fillStyle = '#231E24'
        x.beginPath()
        x.moveTo(140, 78)
        x.lineTo(98, 150)
        x.lineTo(128, 150)
        x.lineTo(112, 200)
        x.lineTo(160, 124)
        x.lineTo(130, 124)
        x.closePath()
        x.fill()
    return _make('bolt', 256, 256, draw)


def newspaperTex():
    def draw(x, w, h):
        x.fillStyle = '#E9E2CF'
        x.fillRect(0, 0, w, h)
        x.fillStyle = '#2A2230'
        x.font = 'bold 30px "Times New Roman", serif'
        x.textAlign = 'center'
        x.fillText('THE DAILY DIAL', w / 2, 36)
        x.fillRect(12, 46, w - 24, 3)
        x.font = 'bold 26px %s' % FALLBACK
        x.fillText('STATION', w / 2, 84)
        x.fillText('GOES DARK', w / 2, 114)
        x.globalAlpha = 0.55
        for c in range(3):
            for r in range(18):
                x.fillRect(14 + c * 80, 132 + r * 10, 68 - ((r * 7 + c * 3) % 4) * 6, 4)
        x.globalAlpha = 0.4
        x.fillRect(96, 140, 64, 56)
        x.globalAlpha = 1
    return _make('newspaper', 256, 320, draw)


def movingPadTex():
    """Quilted grey-blue moving blanket (hung across the D3 doorway behind the debris)."""
    def draw(x, w, h):
        x.fillStyle = '#3F5C8A'
        x.fillRect(0, 0, w, h)
        x.strokeStyle = 'rgba(20,24,48,0.55)'
        x.lineWidth = 3
        for i in range(-h, w, 32):
            x.beginPath()
            x.moveTo(i, 0)
            x.lineTo(i + h, h)
            x.stroke()
            x.beginPath()
            x.moveTo(i + h, 0)
            x.lineTo(i, h)
            x.stroke()
        x.fillStyle = '#C9A24A'
        x.fillRect(0, 0, w, 10)
        x.fillRect(0, h - 10, w, 10)
    return _make('movingPad', 256, 256, draw)
