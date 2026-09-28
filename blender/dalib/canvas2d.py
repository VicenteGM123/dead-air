"""DEAD AIR — HTML Canvas 2D emulation over skia-python (SPEC §6).

Chrome draws <canvas> with Skia, so the JS texture code ports line by line and produces (nearly) the same pixels:

    cv = Canvas(512, 256)
    ctx = cv.getContext('2d')
    ctx.fillStyle = '#F4F1E8'; ctx.fillRect(0, 0, 512, 256)
    ctx.font = 'bold 48px "Bungee", "Arial Black", sans-serif'
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle'
    ctx.fillText('WZTV', 256, 128)
    cv.save_png('/tmp/x.png')            # or cv.to_blender_image('name')

Implemented (JS names): paths (beginPath moveTo lineTo arc arcTo ellipse quadraticCurveTo bezierCurveTo rect
roundRect closePath), fill/stroke/clip (nonzero|evenodd, Path2D), fillRect strokeRect clearRect, save/restore,
translate rotate scale transform setTransform resetTransform getTransform, globalAlpha, globalCompositeOperation
(every standard mode; the "unbounded" ones clear outside the shape like Chrome), shadowBlur/Color/OffsetX/Y,
filter ('blur(Npx)', 'none'), lineWidth lineCap lineJoin miterLimit setLineDash getLineDash lineDashOffset,
fillText strokeText measureText (CSS font strings, textAlign, textBaseline, letterSpacing, maxWidth),
createLinearGradient createRadialGradient createConicGradient createPattern, drawImage (3 signatures, Canvas or
Image), getImageData putImageData createImageData, imageSmoothingEnabled, isPointInPath, CSS colour parsing
(hex 3/4/6/8, rgb[a], hsl[a], named, transparent).

Fonts: the game's four web fonts (Bungee, Titan One, Shrikhand, VT323) load from godot/assets/fonts/*.woff; any
other family goes through the system font manager (fontconfig on Linux, like Chrome), generic families
(sans-serif, serif, monospace) map to the system defaults. Text is shaped with HarfBuzz (uharfbuzz, installed by
vendor.py) so kerning matches Chrome; without it plain advances are used.
"""
from __future__ import annotations

import math
import os
import re
import struct

from . import vendor

vendor.ensure()
import skia  # noqa: E402
import numpy as np  # noqa: E402

try:  # optional: HarfBuzz shaping (kerning) like Chrome
    import uharfbuzz as _hb  # noqa: E402
except Exception:  # pragma: no cover
    _hb = None

__all__ = ['Canvas', 'Image', 'ImageData', 'Path2D', 'CanvasGradient', 'CanvasPattern', 'TextMetrics',
           'parse_color', 'parse_font', 'FONT_DIR', 'createCanvas', 'loadImage']

_HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(_HERE, '..', '..'))
FONT_DIR = os.path.join(REPO, 'godot', 'assets', 'fonts')
GAME_FONTS = {'bungee': 'Bungee.woff', 'titan one': 'TitanOne.woff', 'shrikhand': 'Shrikhand.woff',
              'vt323': 'VT323.woff'}

# Chrome (Linux, device scale 1) text raster settings: grayscale AA, slight hinting, no subpixel positioning.
TEXT_SUBPIXEL = False
TEXT_HINTING = 'slight'

TAU = math.pi * 2

# ================================================================================================== colours
NAMED = {
    'aliceblue': 0xf0f8ff, 'antiquewhite': 0xfaebd7, 'aqua': 0x00ffff, 'aquamarine': 0x7fffd4, 'azure': 0xf0ffff,
    'beige': 0xf5f5dc, 'bisque': 0xffe4c4, 'black': 0x000000, 'blanchedalmond': 0xffebcd, 'blue': 0x0000ff,
    'blueviolet': 0x8a2be2, 'brown': 0xa52a2a, 'burlywood': 0xdeb887, 'cadetblue': 0x5f9ea0, 'chartreuse': 0x7fff00,
    'chocolate': 0xd2691e, 'coral': 0xff7f50, 'cornflowerblue': 0x6495ed, 'cornsilk': 0xfff8dc, 'crimson': 0xdc143c,
    'cyan': 0x00ffff, 'darkblue': 0x00008b, 'darkcyan': 0x008b8b, 'darkgoldenrod': 0xb8860b, 'darkgray': 0xa9a9a9,
    'darkgreen': 0x006400, 'darkgrey': 0xa9a9a9, 'darkkhaki': 0xbdb76b, 'darkmagenta': 0x8b008b,
    'darkolivegreen': 0x556b2f, 'darkorange': 0xff8c00, 'darkorchid': 0x9932cc, 'darkred': 0x8b0000,
    'darksalmon': 0xe9967a, 'darkseagreen': 0x8fbc8f, 'darkslateblue': 0x483d8b, 'darkslategray': 0x2f4f4f,
    'darkslategrey': 0x2f4f4f, 'darkturquoise': 0x00ced1, 'darkviolet': 0x9400d3, 'deeppink': 0xff1493,
    'deepskyblue': 0x00bfff, 'dimgray': 0x696969, 'dimgrey': 0x696969, 'dodgerblue': 0x1e90ff,
    'firebrick': 0xb22222, 'floralwhite': 0xfffaf0, 'forestgreen': 0x228b22, 'fuchsia': 0xff00ff,
    'gainsboro': 0xdcdcdc, 'ghostwhite': 0xf8f8ff, 'gold': 0xffd700, 'goldenrod': 0xdaa520, 'gray': 0x808080,
    'green': 0x008000, 'greenyellow': 0xadff2f, 'grey': 0x808080, 'honeydew': 0xf0fff0, 'hotpink': 0xff69b4,
    'indianred': 0xcd5c5c, 'indigo': 0x4b0082, 'ivory': 0xfffff0, 'khaki': 0xf0e68c, 'lavender': 0xe6e6fa,
    'lavenderblush': 0xfff0f5, 'lawngreen': 0x7cfc00, 'lemonchiffon': 0xfffacd, 'lightblue': 0xadd8e6,
    'lightcoral': 0xf08080, 'lightcyan': 0xe0ffff, 'lightgoldenrodyellow': 0xfafad2, 'lightgray': 0xd3d3d3,
    'lightgreen': 0x90ee90, 'lightgrey': 0xd3d3d3, 'lightpink': 0xffb6c1, 'lightsalmon': 0xffa07a,
    'lightseagreen': 0x20b2aa, 'lightskyblue': 0x87cefa, 'lightslategray': 0x778899, 'lightslategrey': 0x778899,
    'lightsteelblue': 0xb0c4de, 'lightyellow': 0xffffe0, 'lime': 0x00ff00, 'limegreen': 0x32cd32,
    'linen': 0xfaf0e6, 'magenta': 0xff00ff, 'maroon': 0x800000, 'mediumaquamarine': 0x66cdaa,
    'mediumblue': 0x0000cd, 'mediumorchid': 0xba55d3, 'mediumpurple': 0x9370db, 'mediumseagreen': 0x3cb371,
    'mediumslateblue': 0x7b68ee, 'mediumspringgreen': 0x00fa9a, 'mediumturquoise': 0x48d1cc,
    'mediumvioletred': 0xc71585, 'midnightblue': 0x191970, 'mintcream': 0xf5fffa, 'mistyrose': 0xffe4e1,
    'moccasin': 0xffe4b5, 'navajowhite': 0xffdead, 'navy': 0x000080, 'oldlace': 0xfdf5e6, 'olive': 0x808000,
    'olivedrab': 0x6b8e23, 'orange': 0xffa500, 'orangered': 0xff4500, 'orchid': 0xda70d6,
    'palegoldenrod': 0xeee8aa, 'palegreen': 0x98fb98, 'paleturquoise': 0xafeeee, 'palevioletred': 0xdb7093,
    'papayawhip': 0xffefd5, 'peachpuff': 0xffdab9, 'peru': 0xcd853f, 'pink': 0xffc0cb, 'plum': 0xdda0dd,
    'powderblue': 0xb0e0e6, 'purple': 0x800080, 'rebeccapurple': 0x663399, 'red': 0xff0000,
    'rosybrown': 0xbc8f8f, 'royalblue': 0x4169e1, 'saddlebrown': 0x8b4513, 'salmon': 0xfa8072,
    'sandybrown': 0xf4a460, 'seagreen': 0x2e8b57, 'seashell': 0xfff5ee, 'sienna': 0xa0522d, 'silver': 0xc0c0c0,
    'skyblue': 0x87ceeb, 'slateblue': 0x6a5acd, 'slategray': 0x708090, 'slategrey': 0x708090, 'snow': 0xfffafa,
    'springgreen': 0x00ff7f, 'steelblue': 0x4682b4, 'tan': 0xd2b48c, 'teal': 0x008080, 'thistle': 0xd8bfd8,
    'tomato': 0xff6347, 'turquoise': 0x40e0d0, 'violet': 0xee82ee, 'wheat': 0xf5deb3, 'white': 0xffffff,
    'whitesmoke': 0xf5f5f5, 'yellow': 0xffff00, 'yellowgreen': 0x9acd32,
}

_NUM = r'[+-]?(?:\d+\.?\d*|\.\d+)(?:e[+-]?\d+)?'
_color_cache = {}


def _clamp(x, a, b):
    return a if x < a else b if x > b else x


def _parse_num(tok, scale255=True):
    tok = tok.strip()
    if tok.endswith('%'):
        v = float(tok[:-1]) / 100.0
        return v * 255.0 if scale255 else v
    return float(tok)


def _hsl_to_rgb(h, s, l):
    h = (h % 360.0) / 360.0
    s = _clamp(s, 0.0, 1.0)
    l = _clamp(l, 0.0, 1.0)

    def hue(t):
        t = t % 1.0
        q = l * (1 + s) if l <= 0.5 else l + s - l * s
        p = 2 * l - q
        if t < 1 / 6:
            return p + (q - p) * 6 * t
        if t < 0.5:
            return q
        if t < 2 / 3:
            return p + (q - p) * (2 / 3 - t) * 6
        return p
    return hue(h + 1 / 3) * 255.0, hue(h) * 255.0, hue(h - 1 / 3) * 255.0


def parse_color(s):
    """CSS colour -> (r, g, b, a) with r,g,b 0..255 ints and a 0..1 float, or None if invalid."""
    if not isinstance(s, str):
        return None
    hit = _color_cache.get(s)
    if hit is not None or s in _color_cache:
        return hit
    t = s.strip().lower()
    out = None
    if t.startswith('#'):
        h = t[1:]
        if re.fullmatch(r'[0-9a-f]+', h or 'x'):
            if len(h) in (3, 4):
                v = [int(c * 2, 16) for c in h]
                out = (v[0], v[1], v[2], (v[3] / 255.0) if len(h) == 4 else 1.0)
            elif len(h) in (6, 8):
                v = [int(h[i:i + 2], 16) for i in range(0, len(h), 2)]
                out = (v[0], v[1], v[2], (v[3] / 255.0) if len(h) == 8 else 1.0)
    elif t in NAMED:
        v = NAMED[t]
        out = ((v >> 16) & 255, (v >> 8) & 255, v & 255, 1.0)
    elif t == 'transparent':
        out = (0, 0, 0, 0.0)
    elif t == 'currentcolor':
        out = (0, 0, 0, 1.0)
    else:
        m = re.fullmatch(r'(rgba?|hsla?)\((.*)\)', t)
        if m:
            fn, body = m.group(1), m.group(2).strip()
            if ',' in body:
                parts = [p.strip() for p in body.split(',')]
                alpha = parts[3] if len(parts) == 4 else None
                parts = parts[:3]
            else:
                if '/' in body:
                    body, alpha = body.split('/', 1)
                    alpha = alpha.strip()
                else:
                    alpha = None
                parts = body.split()
            try:
                if len(parts) == 3:
                    a = 1.0
                    if alpha is not None:
                        a = _clamp(_parse_num(alpha, False), 0.0, 1.0)
                    if fn.startswith('rgb'):
                        r, g, b = (_clamp(_parse_num(p), 0.0, 255.0) for p in parts)
                    else:
                        hh = parts[0]
                        hv = float(re.sub(r'deg$', '', hh)) if not hh.endswith('turn') else float(hh[:-4]) * 360
                        r, g, b = _hsl_to_rgb(hv, _parse_num(parts[1], False), _parse_num(parts[2], False))
                    out = (int(math.floor(r + 0.5)), int(math.floor(g + 0.5)), int(math.floor(b + 0.5)), a)
            except ValueError:
                out = None
    _color_cache[s] = out
    return out


def _skcolor(rgba, alpha_mul=1.0):
    r, g, b, a = rgba
    a = _clamp(a * alpha_mul, 0.0, 1.0)
    return skia.Color4f(r / 255.0, g / 255.0, b / 255.0, a)


def _serialize(rgba):
    r, g, b, a = rgba
    if a >= 1.0:
        return '#%02x%02x%02x' % (r, g, b)
    return 'rgba(%d, %d, %d, %s)' % (r, g, b, ('%g' % a))


# ==================================================================================================== fonts
_tf_cache = {}
_hb_cache = {}
_fm = None


def _fontmgr():
    global _fm
    if _fm is None:
        _fm = skia.FontMgr()
    return _fm


def _load_game_typeface(fname):
    key = ('file', fname)
    tf = _tf_cache.get(key)
    if tf is None:
        tf = skia.Typeface.MakeFromFile(os.path.join(FONT_DIR, fname))
        _tf_cache[key] = tf
    return tf


GENERIC = {'sans-serif', 'serif', 'monospace', 'cursive', 'fantasy', 'system-ui', 'ui-sans-serif', 'ui-serif',
           'ui-monospace', 'math', 'emoji'}


def _resolve_family(name, weight, italic):
    """Typeface for one CSS family name (or None when not available)."""
    low = name.lower()
    if low in GAME_FONTS:
        return _load_game_typeface(GAME_FONTS[low]), True
    key = ('sys', low, weight >= 600, italic)
    if key in _tf_cache:
        return _tf_cache[key], False
    style = skia.FontStyle(int(weight), skia.FontStyle.kNormal_Width,
                           skia.FontStyle.kItalic_Slant if italic else skia.FontStyle.kUpright_Slant)
    q = {'system-ui': 'sans-serif', 'ui-sans-serif': 'sans-serif', 'ui-serif': 'serif',
         'ui-monospace': 'monospace', 'cursive': 'sans-serif', 'fantasy': 'sans-serif'}.get(low, name)
    tf = _fontmgr().matchFamilyStyle(q, style)
    _tf_cache[key] = tf
    return tf, False


_FONT_RE = re.compile(r'^\s*((?:(?:normal|italic|oblique|small-caps|bold|bolder|lighter|[1-9]00|ultra-condensed|'
                      r'extra-condensed|condensed|semi-condensed|semi-expanded|expanded|extra-expanded|'
                      r'ultra-expanded)\s+)*)(' + _NUM + r')(px|pt|em|rem|%|pc|in|cm|mm|q)(?:\s*/\s*[^\s]+)?\s+(.+?)\s*$',
                      re.I)


def parse_font(s):
    """CSS font shorthand -> dict(size, weight, italic, families) or None when invalid."""
    m = _FONT_RE.match(s or '')
    if not m:
        return None
    mods = m.group(1).lower().split()
    size = float(m.group(2))
    unit = m.group(3).lower()
    size *= {'px': 1, 'pt': 4 / 3, 'em': 10, 'rem': 16, '%': 0.1, 'pc': 16, 'in': 96, 'cm': 96 / 2.54,
             'mm': 96 / 25.4, 'q': 96 / 101.6}[unit]
    weight = 400
    italic = False
    for w in mods:
        if w == 'bold':
            weight = 700
        elif w == 'bolder':
            weight = 700
        elif w == 'lighter':
            weight = 100
        elif w.isdigit():
            weight = int(w)
        elif w in ('italic', 'oblique'):
            italic = True
    fams = []
    for f in re.findall(r'"[^"]*"|\'[^\']*\'|[^,]+', m.group(4)):
        f = f.strip().strip(',').strip()
        if not f:
            continue
        if f[0] in '"\'':
            f = f[1:-1]
        fams.append(re.sub(r'\s+', ' ', f.strip()))
    if not fams or size < 0:
        return None
    return {'size': size, 'weight': weight, 'italic': italic, 'families': fams}


class _FontFace:
    """One resolved family at one size/weight (skia Font + HarfBuzz font + baseline metrics)."""

    def __init__(self, tf, size, weight, italic, is_web):
        self.tf = tf
        self.size = size
        font = skia.Font(tf, size)
        font.setEdging(skia.Font.Edging.kAntiAlias)
        font.setSubpixel(TEXT_SUBPIXEL)
        font.setHinting({'none': skia.FontHinting.kNone, 'slight': skia.FontHinting.kSlight,
                         'normal': skia.FontHinting.kNormal, 'full': skia.FontHinting.kFull}[TEXT_HINTING])
        font.setEmbeddedBitmaps(False)
        font.setBaselineSnap(True)
        style = tf.fontStyle()
        # Chrome synthesizes bold / oblique when the face lacks them (web fonts are single-weight here)
        if weight >= 600 and style.weight() < 600:
            font.setEmbolden(True)
        if italic and style.slant() == skia.FontStyle.kUpright_Slant:
            font.setSkewX(-0.25)
        self.font = font
        self.hb = _hb_font(tf, size) if _hb is not None else None
        self._metrics()

    def _metrics(self):
        m = self.font.getMetrics()
        # Chrome rounds ascent/descent of the primary font (SimpleFontData::PlatformInit)
        self.ascent = float(round(-m.fAscent))
        self.descent = float(round(m.fDescent))
        upem = self.tf.getUnitsPerEm() or 1000
        typo = None
        try:
            os2 = self.tf.getTableData(int.from_bytes(b'OS/2', 'big'))
            if os2 and len(os2) >= 74:
                ta, td = struct.unpack('>hh', os2[68:72])
                typo = (ta * self.size / upem, -td * self.size / upem)
        except Exception:
            typo = None
        a, d = typo if typo and (typo[0] + typo[1]) > 0 else (-m.fAscent, m.fDescent)
        h = a + d
        # normalized to the em height, in LayoutUnits (1/64 px) like Blink
        self.em_ascent = round(a * self.size / h * 64) / 64 if h > 0 else self.size * 0.8
        self.em_descent = round(d * self.size / h * 64) / 64 if h > 0 else self.size * 0.2

    def has_glyph(self, ch):
        return self.tf.unicharToGlyph(ord(ch)) != 0


def _hb_font(tf, size):
    key = id(tf)
    face = _hb_cache.get(key)
    if face is None:
        tags = tf.getTableTags()
        tables = {}
        for t in tags:
            data = tf.getTableData(t)
            if data:
                tables[t] = bytes(data)
        n = len(tables)
        es = 1
        while es * 2 <= n:
            es *= 2
        head = struct.pack('>IHHHH', 0x00010000, n, es * 16, int(math.log2(es)), n * 16 - es * 16)
        off = 12 + 16 * n
        recs = b''
        body = b''
        for t in sorted(tables):
            d = tables[t]
            recs += struct.pack('>IIII', t, 0, off + len(body), len(d))
            body += d + b'\0' * ((4 - len(d) % 4) % 4)
        blob = _hb.Blob(head + recs + body)
        face = _hb.Face(blob)
        _hb_cache[key] = face
    f = _hb.Font(face)
    return f


def _shape_run(ff, text, letter_spacing):
    """Glyph ids + x offsets (Chrome-like: rounded hinted advances + GPOS adjustments)."""
    font = ff.font
    if not text:
        return [], [], 0.0
    if ff.hb is not None:
        buf = _hb.Buffer()
        buf.add_str(text)
        buf.guess_segment_properties()
        upem = ff.tf.getUnitsPerEm() or 1000
        ff.hb.scale = (upem, upem)
        _hb.shape(ff.hb, buf, {'kern': True, 'liga': True})
        infos, poss = buf.glyph_infos, buf.glyph_positions
        gids = [i.codepoint for i in infos]
        widths = font.getWidths(gids)
        k = ff.size / upem
        xs = []
        x = 0.0
        for gid, p, w in zip(gids, poss, widths):
            nominal = ff.hb.get_glyph_h_advance(gid)
            adv = (round(w) if not TEXT_SUBPIXEL else w) + (p.x_advance - nominal) * k
            xs.append(x + p.x_offset * k)
            x += adv + letter_spacing
        return gids, xs, x
    gids = font.textToGlyphs(text)
    widths = font.getWidths(gids)
    xs = []
    x = 0.0
    for w in widths:
        xs.append(x)
        x += (round(w) if not TEXT_SUBPIXEL else w) + letter_spacing
    return gids, xs, x


class _FontSpec:
    def __init__(self, css):
        p = parse_font(css)
        self.ok = p is not None
        if not p:
            return
        self.size = p['size']
        faces = []
        for fam in p['families']:
            tf, web = _resolve_family(fam, p['weight'], p['italic'])
            if tf is not None:
                faces.append(_FontFace(tf, self.size, p['weight'], p['italic'], web))
        if not faces:
            tf, _ = _resolve_family('sans-serif', p['weight'], p['italic'])
            faces.append(_FontFace(tf or skia.Typeface.MakeDefault(), self.size, p['weight'], p['italic'], False))
        self.faces = faces
        self.primary = faces[0]

    def runs(self, text):
        """Split text into runs by the first face that has each glyph (per-character fallback)."""
        out = []
        cur, buf = None, ''
        for ch in text:
            face = self.primary
            if not self.primary.has_glyph(ch) and ch not in '\n\r\t':
                for f in self.faces[1:]:
                    if f.has_glyph(ch):
                        face = f
                        break
            if face is not cur and buf:
                out.append((cur, buf))
                buf = ''
            cur = face
            buf += ch
        if buf:
            out.append((cur, buf))
        return out


_font_cache = {}


def _font_spec(css):
    fs = _font_cache.get(css)
    if fs is None:
        fs = _FontSpec(css)
        _font_cache[css] = fs
    return fs


# ================================================================================================ helpers
class TextMetrics:
    def __init__(self, **kw):
        self.__dict__.update(kw)

    def __getitem__(self, k):
        return self.__dict__[k]


class CanvasGradient:
    def __init__(self, kind, args):
        self.kind = kind
        self.args = args
        self.stops = []

    def addColorStop(self, offset, color):
        c = parse_color(color)
        if c is None:
            raise ValueError('SyntaxError: invalid colour %r' % (color,))
        if not (0 <= offset <= 1):
            raise ValueError('IndexSizeError: offset out of range')
        # stops keep insertion order for equal offsets (spec)
        self.stops.append((float(offset), c))
        self.stops.sort(key=lambda s: s[0])

    def _shader(self, alpha):
        if not self.stops:
            return None
        pos = [s[0] for s in self.stops]
        cols = [_skcolor(s[1]).toColor() for s in self.stops]
        if alpha < 1:
            cols = [skia.Color4f(skia.Color4f(c).fR, skia.Color4f(c).fG, skia.Color4f(c).fB,
                                 skia.Color4f(c).fA * alpha).toColor() for c in cols]
        if len(pos) == 1:
            pos = [0.0, 1.0]
            cols = cols * 2
        a = self.args
        if self.kind == 'linear':
            x0, y0, x1, y1 = a
            if x0 == x1 and y0 == y1:
                return 'none'
            return skia.GradientShader.MakeLinear([skia.Point(x0, y0), skia.Point(x1, y1)], cols, pos,
                                                  skia.TileMode.kClamp)
        if self.kind == 'radial':
            x0, y0, r0, x1, y1, r1 = a
            if x0 == x1 and y0 == y1 and r0 == r1:
                return 'none'
            return skia.GradientShader.MakeTwoPointConical(skia.Point(x0, y0), r0, skia.Point(x1, y1), r1, cols, pos,
                                                           skia.TileMode.kClamp)
        if self.kind == 'conic':
            ang, cx, cy = a
            deg = math.degrees(ang)
            sh = skia.GradientShader.MakeSweep(cx, cy, cols, pos, skia.TileMode.kClamp, 0, 360)
            return sh.makeWithLocalMatrix(skia.Matrix.RotateDeg(deg, skia.Point(cx, cy)))
        return None


class CanvasPattern:
    def __init__(self, image, repetition):
        self.image = image  # skia.Image
        self.rep = repetition or 'repeat'
        self.matrix = skia.Matrix()

    def setTransform(self, m=None):
        self.matrix = _to_matrix(m) if m is not None else skia.Matrix()

    def _shader(self, alpha, smoothing):
        r = self.rep
        tx = skia.TileMode.kRepeat if r in ('repeat', 'repeat-x') else skia.TileMode.kDecal
        ty = skia.TileMode.kRepeat if r in ('repeat', 'repeat-y') else skia.TileMode.kDecal
        samp = skia.SamplingOptions(skia.FilterMode.kLinear if smoothing else skia.FilterMode.kNearest)
        return self.image.makeShader(tx, ty, samp, self.matrix)


def _mcopy(m):
    return skia.Matrix.Concat(m, skia.Matrix())


def _to_matrix(m):
    if isinstance(m, skia.Matrix):
        return _mcopy(m)
    if isinstance(m, dict):
        g = m.get
        return skia.Matrix.MakeAll(g('a', 1), g('c', 0), g('e', 0), g('b', 0), g('d', 1), g('f', 0), 0, 0, 1)
    a, b, c, d, e, f = [getattr(m, k) for k in 'abcdef']
    return skia.Matrix.MakeAll(a, c, e, b, d, f, 0, 0, 1)


class DOMMatrix:
    def __init__(self, a=1, b=0, c=0, d=1, e=0, f=0):
        self.a, self.b, self.c, self.d, self.e, self.f = a, b, c, d, e, f

    def __repr__(self):
        return 'DOMMatrix(%g, %g, %g, %g, %g, %g)' % (self.a, self.b, self.c, self.d, self.e, self.f)


class ImageData:
    """RGBA 8-bit unpremultiplied pixels. data: flat numpy uint8 array (index like the JS Uint8ClampedArray)."""

    def __init__(self, width, height=None, data=None):
        if isinstance(width, ImageData):
            width, height = width.width, width.height
        self.width = int(width)
        self.height = int(height)
        if data is None:
            data = np.zeros(self.width * self.height * 4, dtype=np.uint8)
        else:
            data = np.asarray(data, dtype=np.uint8).reshape(-1)
        self.data = data


class Image:
    """A decoded image usable by drawImage / createPattern (JS `new Image()` with src set to a file path)."""

    def __init__(self, src=None):
        self._img = None
        self._src = None
        if src is not None:
            self.src = src

    @property
    def src(self):
        return self._src

    @src.setter
    def src(self, path):
        self._src = path
        self._img = skia.Image.open(path)

    @property
    def width(self):
        return self._img.width() if self._img else 0

    @property
    def height(self):
        return self._img.height() if self._img else 0

    naturalWidth = width
    naturalHeight = height

    @property
    def complete(self):
        return self._img is not None

    def _skimage(self):
        return self._img


def loadImage(path):
    return Image(path)


# ===================================================================================================== path
class Path2D:
    """Path in USER space; the context transforms it by the CTM when it is filled/stroked/clipped."""

    def __init__(self, other=None):
        self._p = skia.Path()
        self._has_cur = False
        if isinstance(other, Path2D):
            self._p = skia.Path(other._p)
            self._has_cur = other._has_cur
        elif isinstance(other, str):
            _svg_path(self, other)

    # the same builder API as the context, in local (untransformed) space
    def _mat(self):
        return None

    def addPath(self, path, transform=None):
        m = _to_matrix(transform) if transform is not None else skia.Matrix()
        self._p.addPath(path._p, m, skia.Path.kAppend_AddPathMode)
        self._has_cur = self._has_cur or not path._p.isEmpty()


def _svg_path(pb, d):
    """SVG path data (M L H V C S Q T A Z, absolute and relative) into a path builder (Path2D)."""
    toks = re.findall(r'[MmLlHhVvCcSsQqTtAaZz]|' + _NUM, d)
    i = 0
    cmd = None
    cx = cy = sx = sy = 0.0
    lc = None  # last control point (for S/T)
    nargs = {'m': 2, 'l': 2, 'h': 1, 'v': 1, 'c': 6, 's': 4, 'q': 4, 't': 2, 'a': 7, 'z': 0}
    while i < len(toks):
        t = toks[i]
        if t.isalpha():
            cmd = t
            i += 1
            if cmd in 'zZ':
                pb.closePath()
                cx, cy = sx, sy
                lc = None
                continue
        if cmd is None:
            break
        n = nargs[cmd.lower()]
        a = [float(x) for x in toks[i:i + n]]
        if len(a) < n:
            break
        i += n
        rel = cmd.islower()
        c = cmd.lower()
        ox, oy = (cx, cy) if rel else (0.0, 0.0)
        if c == 'm':
            cx, cy = a[0] + ox, a[1] + oy
            pb.moveTo(cx, cy)
            sx, sy = cx, cy
            cmd = 'l' if rel else 'L'
            lc = None
        elif c == 'l':
            cx, cy = a[0] + ox, a[1] + oy
            pb.lineTo(cx, cy)
            lc = None
        elif c == 'h':
            cx = a[0] + ox
            pb.lineTo(cx, cy)
            lc = None
        elif c == 'v':
            cy = a[0] + (cy if rel else 0.0)
            pb.lineTo(cx, cy)
            lc = None
        elif c == 'c':
            x1, y1, x2, y2, x, y = a[0] + ox, a[1] + oy, a[2] + ox, a[3] + oy, a[4] + ox, a[5] + oy
            pb.bezierCurveTo(x1, y1, x2, y2, x, y)
            lc = ('c', x2, y2)
            cx, cy = x, y
        elif c == 's':
            x1, y1 = (2 * cx - lc[1], 2 * cy - lc[2]) if lc and lc[0] == 'c' else (cx, cy)
            x2, y2, x, y = a[0] + ox, a[1] + oy, a[2] + ox, a[3] + oy
            pb.bezierCurveTo(x1, y1, x2, y2, x, y)
            lc = ('c', x2, y2)
            cx, cy = x, y
        elif c == 'q':
            x1, y1, x, y = a[0] + ox, a[1] + oy, a[2] + ox, a[3] + oy
            pb.quadraticCurveTo(x1, y1, x, y)
            lc = ('q', x1, y1)
            cx, cy = x, y
        elif c == 't':
            x1, y1 = (2 * cx - lc[1], 2 * cy - lc[2]) if lc and lc[0] == 'q' else (cx, cy)
            x, y = a[0] + ox, a[1] + oy
            pb.quadraticCurveTo(x1, y1, x, y)
            lc = ('q', x1, y1)
            cx, cy = x, y
        elif c == 'a':
            rx, ry, rot, large, sweep, x, y = a[0], a[1], a[2], a[3], a[4], a[5] + ox, a[6] + oy
            p, h = pb._p, pb
            if not h._has_cur:
                p.moveTo(cx, cy)
                h._has_cur = True
            p.arcTo(rx, ry, rot, skia.Path.ArcSize.kLarge_ArcSize if large else skia.Path.ArcSize.kSmall_ArcSize,
                    skia.PathDirection.kCW if sweep else skia.PathDirection.kCCW, x, y)
            cx, cy = x, y
            lc = None


def _pb_methods(cls, getp, getm):
    """Installs the path-building methods on cls. getp(self)->(skia.Path, state holder); getm(self)->Matrix|None."""

    def xf(self, x, y):
        m = getm(self)
        if m is None:
            return float(x), float(y)
        p = m.mapXY(float(x), float(y))
        return p.x(), p.y()

    def ensure(self, x, y):
        p, h = getp(self)
        if not h._has_cur:
            X, Y = xf(self, x, y)
            p.moveTo(X, Y)
            h._has_cur = True

    def moveTo(self, x, y):
        if not (_finite(x) and _finite(y)):
            return
        p, h = getp(self)
        X, Y = xf(self, x, y)
        p.moveTo(X, Y)
        h._has_cur = True

    def lineTo(self, x, y):
        if not (_finite(x) and _finite(y)):
            return
        p, h = getp(self)
        if not h._has_cur:
            moveTo(self, x, y)
            return
        X, Y = xf(self, x, y)
        p.lineTo(X, Y)

    def closePath(self):
        p, h = getp(self)
        if h._has_cur:
            p.close()

    def quadraticCurveTo(self, cx, cy, x, y):
        if not all(_finite(v) for v in (cx, cy, x, y)):
            return
        p, h = getp(self)
        ensure(self, cx, cy)
        a = xf(self, cx, cy)
        b = xf(self, x, y)
        p.quadTo(a[0], a[1], b[0], b[1])

    def bezierCurveTo(self, c1x, c1y, c2x, c2y, x, y):
        if not all(_finite(v) for v in (c1x, c1y, c2x, c2y, x, y)):
            return
        p, h = getp(self)
        ensure(self, c1x, c1y)
        a = xf(self, c1x, c1y)
        b = xf(self, c2x, c2y)
        c = xf(self, x, y)
        p.cubicTo(a[0], a[1], b[0], b[1], c[0], c[1])

    def _append_local(self, local, connect=True):
        p, h = getp(self)
        m = getm(self)
        if m is not None and not m.isIdentity():
            local.transform(m)
        if h._has_cur and connect:
            p.addPath(local, skia.Path.kExtend_AddPathMode)
        else:
            p.addPath(local, skia.Path.kAppend_AddPathMode)
        h._has_cur = True

    def ellipse(self, x, y, rx, ry, rotation, start, end, ccw=False):
        if not all(_finite(v) for v in (x, y, rx, ry, rotation, start, end)):
            return
        if rx < 0 or ry < 0:
            raise ValueError('IndexSizeError: negative radius')
        start, end = float(start), float(end)
        # Chrome: canonicalize the start angle into [0, 2pi) and adjust the end angle (AdjustEndAngle)
        new_start = math.fmod(start, TAU)
        if new_start < 0:
            new_start += TAU
        delta = new_start - start
        start = new_start
        end = end + delta
        if not ccw and end - start >= TAU:
            end = start + TAU
        elif ccw and start - end >= TAU:
            end = start - TAU
        elif not ccw and start > end:
            end = start + (TAU - math.fmod(start - end, TAU))
        elif ccw and start < end:
            end = start - (TAU - math.fmod(end - start, TAU))
        local = skia.Path()
        sd = math.degrees(start)
        sw = math.degrees(end - start)
        oval = skia.Rect.MakeLTRB(-rx, -ry, rx, ry)
        sx0 = math.cos(start) * rx
        sy0 = math.sin(start) * ry
        local.moveTo(sx0, sy0)
        if abs(sw - 360) < 1e-4:
            local.arcTo(oval, sd, 180, False)
            local.arcTo(oval, sd + 180, 180, False)
        elif abs(sw + 360) < 1e-4:
            local.arcTo(oval, sd, -180, False)
            local.arcTo(oval, sd - 180, -180, False)
        elif rx == 0 or ry == 0:
            # degenerate: Skia would draw nothing; the spec draws the (flattened) arc path as lines
            n = max(2, int(abs(sw) / 10) + 1)
            for i in range(1, n + 1):
                a = start + (end - start) * i / n
                local.lineTo(math.cos(a) * rx, math.sin(a) * ry)
        else:
            local.arcTo(oval, sd, sw, False)
        mm = skia.Matrix.Translate(x, y)
        if rotation:
            mm.preRotate(math.degrees(rotation))
        local.transform(mm)
        _append_local(self, local)

    def arc(self, x, y, r, start, end, ccw=False):
        ellipse(self, x, y, r, r, 0, start, end, ccw)

    def arcTo(self, x1, y1, x2, y2, r):
        if not all(_finite(v) for v in (x1, y1, x2, y2, r)):
            return
        if r < 0:
            raise ValueError('IndexSizeError: negative radius')
        p, h = getp(self)
        if not h._has_cur:
            moveTo(self, x1, y1)
        m = getm(self)
        lp = p.getPoint(p.countPoints() - 1)
        x0, y0 = lp.x(), lp.y()
        if m is not None and not m.isIdentity():
            inv = skia.Matrix()
            if not m.invert(inv):
                return
            q = inv.mapXY(x0, y0)
            x0, y0 = q.x(), q.y()
        local = skia.Path()
        local.moveTo(x0, y0)
        if (x0 == x1 and y0 == y1) or (x1 == x2 and y1 == y2) or r == 0:
            local.lineTo(x1, y1)
        else:
            # collinear points: straight line to (x1, y1)
            cross = (x1 - x0) * (y2 - y1) - (y1 - y0) * (x2 - x1)
            if abs(cross) < 1e-12:
                local.lineTo(x1, y1)
            else:
                local.arcTo(x1, y1, x2, y2, r)
        _append_local(self, local)

    def rect(self, x, y, w, hh):
        if not all(_finite(v) for v in (x, y, w, hh)):
            return
        p, h = getp(self)
        pts = [xf(self, x, y), xf(self, x + w, y), xf(self, x + w, y + hh), xf(self, x, y + hh)]
        p.moveTo(*pts[0])
        for q in pts[1:]:
            p.lineTo(*q)
        p.close()
        p.moveTo(*pts[0])
        h._has_cur = True

    def roundRect(self, x, y, w, hh, radii=0):
        if not all(_finite(v) for v in (x, y, w, hh)):
            return
        rl = radii if isinstance(radii, (list, tuple)) else [radii]
        if not (1 <= len(rl) <= 4):
            raise ValueError('RangeError: radii')

        def rxy(v):
            if isinstance(v, dict):
                return float(v.get('x', 0)), float(v.get('y', 0))
            if hasattr(v, 'x') and hasattr(v, 'y') and not isinstance(v, (int, float)):
                return float(v.x), float(v.y)
            return float(v), float(v)
        rr = [rxy(v) for v in rl]
        for a, b in rr:
            if a < 0 or b < 0:
                raise ValueError('RangeError: negative radius')
        if len(rr) == 4:
            tl, tr, br, bl = rr
        elif len(rr) == 3:
            tl, tr, br = rr
            bl = tr
        elif len(rr) == 2:
            tl, tr = rr
            br, bl = tl, tr
        else:
            tl = tr = br = bl = rr[0]
        # negative sizes flip the rect and swap the corners
        if w < 0:
            x, w = x + w, -w
            tl, tr, bl, br = tr, tl, br, bl
        if hh < 0:
            y, hh = y + hh, -hh
            tl, bl, tr, br = bl, tl, br, tr
        # scale down overlapping radii
        f = 1.0
        for s, lsum in ((w, tl[0] + tr[0]), (hh, tr[1] + br[1]), (w, br[0] + bl[0]), (hh, tl[1] + bl[1])):
            if lsum > 0 and s / lsum < f:
                f = s / lsum
        tl, tr, br, bl = [(a * f, b * f) for a, b in (tl, tr, br, bl)]
        rrect = skia.RRect()
        rrect.setRectRadii(skia.Rect.MakeXYWH(x, y, w, hh),
                           [skia.Point(*tl), skia.Point(*tr), skia.Point(*br), skia.Point(*bl)])
        local = skia.Path()
        local.addRRect(rrect, skia.PathDirection.kCW, 6 if True else 0)
        _append_local(self, local, connect=False)
        p, h = getp(self)
        X, Y = xf(self, x, y)
        p.moveTo(X, Y)

    for fn in (moveTo, lineTo, closePath, quadraticCurveTo, bezierCurveTo, ellipse, arc, arcTo, rect, roundRect):
        setattr(cls, fn.__name__, fn)


def _finite(v):
    try:
        return math.isfinite(v)
    except TypeError:
        return False


_pb_methods(Path2D, lambda self: (self._p, self), lambda self: None)


# ================================================================================================== context
_BLEND = {
    'source-over': skia.BlendMode.kSrcOver, 'source-in': skia.BlendMode.kSrcIn,
    'source-out': skia.BlendMode.kSrcOut, 'source-atop': skia.BlendMode.kSrcATop,
    'destination-over': skia.BlendMode.kDstOver, 'destination-in': skia.BlendMode.kDstIn,
    'destination-out': skia.BlendMode.kDstOut, 'destination-atop': skia.BlendMode.kDstATop,
    'lighter': skia.BlendMode.kPlus, 'copy': skia.BlendMode.kSrc, 'xor': skia.BlendMode.kXor,
    'multiply': skia.BlendMode.kMultiply, 'screen': skia.BlendMode.kScreen, 'overlay': skia.BlendMode.kOverlay,
    'darken': skia.BlendMode.kDarken, 'lighten': skia.BlendMode.kLighten,
    'color-dodge': skia.BlendMode.kColorDodge, 'color-burn': skia.BlendMode.kColorBurn,
    'hard-light': skia.BlendMode.kHardLight, 'soft-light': skia.BlendMode.kSoftLight,
    'difference': skia.BlendMode.kDifference, 'exclusion': skia.BlendMode.kExclusion,
    'hue': skia.BlendMode.kHue, 'saturation': skia.BlendMode.kSaturation, 'color': skia.BlendMode.kColor,
    'luminosity': skia.BlendMode.kLuminosity,
}
# modes whose result outside the drawn shape differs from "untouched" (Chrome composites a full layer)
_UNBOUNDED = {'source-in', 'source-out', 'destination-in', 'destination-atop', 'copy'}
_CAP = {'butt': skia.Paint.kButt_Cap, 'round': skia.Paint.kRound_Cap, 'square': skia.Paint.kSquare_Cap}
_JOIN = {'miter': skia.Paint.kMiter_Join, 'round': skia.Paint.kRound_Join, 'bevel': skia.Paint.kBevel_Join}


class _State:
    __slots__ = ('fill', 'stroke', 'fill_raw', 'stroke_raw', 'alpha', 'comp', 'lineWidth', 'lineCap', 'lineJoin',
                 'miterLimit', 'dash', 'dashOffset', 'font', 'font_raw', 'textAlign', 'textBaseline', 'direction',
                 'letterSpacing', 'wordSpacing', 'shadowBlur', 'shadowColor', 'shadowOffsetX', 'shadowOffsetY',
                 'filter', 'smoothing', 'smoothingQuality', 'matrix', 'fontKerning')

    def __init__(self):
        self.fill = (0, 0, 0, 1.0)
        self.stroke = (0, 0, 0, 1.0)
        self.fill_raw = '#000000'
        self.stroke_raw = '#000000'
        self.alpha = 1.0
        self.comp = 'source-over'
        self.lineWidth = 1.0
        self.lineCap = 'butt'
        self.lineJoin = 'miter'
        self.miterLimit = 10.0
        self.dash = []
        self.dashOffset = 0.0
        self.font_raw = '10px sans-serif'
        self.font = None
        self.textAlign = 'start'
        self.textBaseline = 'alphabetic'
        self.direction = 'ltr'
        self.letterSpacing = '0px'
        self.wordSpacing = '0px'
        self.shadowBlur = 0.0
        self.shadowColor = (0, 0, 0, 0.0)
        self.shadowOffsetX = 0.0
        self.shadowOffsetY = 0.0
        self.filter = 'none'
        self.smoothing = True
        self.smoothingQuality = 'low'
        self.matrix = skia.Matrix()
        self.fontKerning = 'auto'

    def copy(self):
        s = _State.__new__(_State)
        for k in _State.__slots__:
            setattr(s, k, getattr(self, k))
        s.dash = list(self.dash)
        s.matrix = _mcopy(self.matrix)
        return s


def _cm_filter(mat, inp):
    return skia.ImageFilters.ColorFilter(skia.ColorFilters.Matrix(mat), inp)


def _css_amount(v, pct_default=1.0):
    v = v.strip()
    if not v:
        return pct_default
    if v.endswith('%'):
        return float(v[:-1]) / 100.0
    return float(v)


def _css_filter(f):
    out = None
    for name, arg in re.findall(r'([a-z-]+)\(([^()]*(?:\([^()]*\)[^()]*)*)\)', f):
        if name == 'blur':
            r = _css_len(arg or '0')
            if r > 0:
                out = skia.ImageFilters.Blur(r, r, skia.TileMode.kDecal, out)
        elif name == 'brightness':
            a = _css_amount(arg)
            out = _cm_filter([a, 0, 0, 0, 0, 0, a, 0, 0, 0, 0, 0, a, 0, 0, 0, 0, 0, 1, 0], out)
        elif name == 'contrast':
            a = _css_amount(arg)
            b = (1 - a) / 2
            out = _cm_filter([a, 0, 0, 0, b, 0, a, 0, 0, b, 0, 0, a, 0, b, 0, 0, 0, 1, 0], out)
        elif name == 'opacity':
            a = min(1.0, _css_amount(arg))
            out = _cm_filter([1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, a, 0], out)
        elif name == 'invert':
            a = min(1.0, _css_amount(arg))
            k = 1 - 2 * a
            out = _cm_filter([k, 0, 0, 0, a, 0, k, 0, 0, a, 0, 0, k, 0, a, 0, 0, 0, 1, 0], out)
        elif name in ('saturate', 'grayscale', 'sepia', 'hue-rotate'):
            if name == 'saturate':
                sv = _css_amount(arg)
                m = [0.213 + 0.787 * sv, 0.715 - 0.715 * sv, 0.072 - 0.072 * sv,
                     0.213 - 0.213 * sv, 0.715 + 0.285 * sv, 0.072 - 0.072 * sv,
                     0.213 - 0.213 * sv, 0.715 - 0.715 * sv, 0.072 + 0.928 * sv]
            elif name == 'grayscale':
                a = 1 - min(1.0, _css_amount(arg))
                m = [0.2126 + 0.7874 * a, 0.7152 - 0.7152 * a, 0.0722 - 0.0722 * a,
                     0.2126 - 0.2126 * a, 0.7152 + 0.2848 * a, 0.0722 - 0.0722 * a,
                     0.2126 - 0.2126 * a, 0.7152 - 0.7152 * a, 0.0722 + 0.9278 * a]
            elif name == 'sepia':
                a = 1 - min(1.0, _css_amount(arg))
                m = [0.393 + 0.607 * a, 0.769 - 0.769 * a, 0.189 - 0.189 * a,
                     0.349 - 0.349 * a, 0.686 + 0.314 * a, 0.168 - 0.168 * a,
                     0.272 - 0.272 * a, 0.534 - 0.534 * a, 0.131 + 0.869 * a]
            else:
                t = arg.strip()
                deg = float(t[:-4]) * 360 if t.endswith('turn') else float(t[:-3]) * 180 / math.pi \
                    if t.endswith('rad') else float(re.sub('deg$', '', t) or 0)
                c, sn = math.cos(math.radians(deg)), math.sin(math.radians(deg))
                m = [0.213 + c * 0.787 - sn * 0.213, 0.715 - c * 0.715 - sn * 0.715, 0.072 - c * 0.072 + sn * 0.928,
                     0.213 - c * 0.213 + sn * 0.143, 0.715 + c * 0.285 + sn * 0.140, 0.072 - c * 0.072 - sn * 0.283,
                     0.213 - c * 0.213 - sn * 0.787, 0.715 - c * 0.715 + sn * 0.715, 0.072 + c * 0.928 + sn * 0.072]
            out = _cm_filter([m[0], m[1], m[2], 0, 0, m[3], m[4], m[5], 0, 0, m[6], m[7], m[8], 0, 0,
                              0, 0, 0, 1, 0], out)
        elif name == 'drop-shadow':
            parts = re.findall(r'(?:rgba?|hsla?)\([^)]*\)|#[0-9a-fA-F]+|[a-z]+|' + _NUM + r'(?:px)?', arg)
            nums = [_css_len(p) for p in parts if re.match(_NUM, p)]
            cols = [parse_color(p) for p in parts if not re.match(_NUM, p)]
            col = next((c for c in cols if c), (0, 0, 0, 1.0))
            dx, dy = (nums + [0, 0])[:2]
            bl = nums[2] if len(nums) > 2 else 0
            out = skia.ImageFilters.DropShadow(dx, dy, bl, bl, _skcolor(col).toColor(), out)
    return out


def _css_len(v, font_size=10.0):
    if isinstance(v, (int, float)):
        return float(v)
    m = re.fullmatch(r'\s*(' + _NUM + r')\s*(px|em|rem|pt)?\s*', str(v))
    if not m:
        return 0.0
    n = float(m.group(1))
    u = (m.group(2) or 'px').lower()
    return n * {'px': 1, 'em': font_size, 'rem': 16, 'pt': 4 / 3}[u]


class CanvasRenderingContext2D:
    def __init__(self, canvas):
        self.canvas = canvas
        self._reset()

    def _reset(self):
        self._s = _State()
        self._stack = []
        self._path = skia.Path()
        self._has_cur = False
        self._sk = self.canvas._surface.getCanvas()
        self._sk.restoreToCount(1)

    # ------------------------------------------------------------------------------------------- state props
    def _set_style(self, which, v):
        if isinstance(v, (CanvasGradient, CanvasPattern)):
            setattr(self._s, which, v)
            setattr(self._s, which + '_raw', v)
            return
        c = parse_color(v) if isinstance(v, str) else None
        if c is None:
            return  # invalid values are ignored
        setattr(self._s, which, c)
        setattr(self._s, which + '_raw', _serialize(c))

    fillStyle = property(lambda self: self._s.fill_raw, lambda self, v: self._set_style('fill', v))
    strokeStyle = property(lambda self: self._s.stroke_raw, lambda self, v: self._set_style('stroke', v))

    def _set_alpha(self, v):
        if _finite(v) and 0 <= v <= 1:
            self._s.alpha = float(v)
    globalAlpha = property(lambda self: self._s.alpha, _set_alpha)

    def _set_comp(self, v):
        if v in _BLEND:
            self._s.comp = v
    globalCompositeOperation = property(lambda self: self._s.comp, _set_comp)

    def _set_lw(self, v):
        if _finite(v) and v > 0:
            self._s.lineWidth = float(v)
    lineWidth = property(lambda self: self._s.lineWidth, _set_lw)

    def _set_cap(self, v):
        if v in _CAP:
            self._s.lineCap = v
    lineCap = property(lambda self: self._s.lineCap, _set_cap)

    def _set_join(self, v):
        if v in _JOIN:
            self._s.lineJoin = v
    lineJoin = property(lambda self: self._s.lineJoin, _set_join)

    def _set_ml(self, v):
        if _finite(v) and v > 0:
            self._s.miterLimit = float(v)
    miterLimit = property(lambda self: self._s.miterLimit, _set_ml)

    def _set_ldo(self, v):
        if _finite(v):
            self._s.dashOffset = float(v)
    lineDashOffset = property(lambda self: self._s.dashOffset, _set_ldo)

    def setLineDash(self, segs):
        segs = list(segs)
        if any((not _finite(x)) or x < 0 for x in segs):
            return
        if len(segs) % 2:
            segs = segs + segs
        self._s.dash = [float(x) for x in segs]

    def getLineDash(self):
        return list(self._s.dash)

    def _set_font(self, v):
        fs = _font_spec(v)
        if fs.ok:
            self._s.font_raw = v
            self._s.font = fs
    font = property(lambda self: self._s.font_raw, _set_font)

    def _set_align(self, v):
        if v in ('start', 'end', 'left', 'right', 'center'):
            self._s.textAlign = v
    textAlign = property(lambda self: self._s.textAlign, _set_align)

    def _set_baseline(self, v):
        if v in ('top', 'hanging', 'middle', 'alphabetic', 'ideographic', 'bottom'):
            self._s.textBaseline = v
    textBaseline = property(lambda self: self._s.textBaseline, _set_baseline)

    def _set_dir(self, v):
        if v in ('ltr', 'rtl', 'inherit'):
            self._s.direction = v
    direction = property(lambda self: self._s.direction, _set_dir)

    def _set_ls(self, v):
        self._s.letterSpacing = v if isinstance(v, str) else '%gpx' % v
    letterSpacing = property(lambda self: self._s.letterSpacing, _set_ls)

    def _set_ws(self, v):
        self._s.wordSpacing = v if isinstance(v, str) else '%gpx' % v
    wordSpacing = property(lambda self: self._s.wordSpacing, _set_ws)

    def _set_fk(self, v):
        if v in ('auto', 'normal', 'none'):
            self._s.fontKerning = v
    fontKerning = property(lambda self: self._s.fontKerning, _set_fk)

    def _set_sb(self, v):
        if _finite(v) and v >= 0:
            self._s.shadowBlur = float(v)
    shadowBlur = property(lambda self: self._s.shadowBlur, _set_sb)

    def _set_sc(self, v):
        c = parse_color(v)
        if c is not None:
            self._s.shadowColor = c
    shadowColor = property(lambda self: _serialize(self._s.shadowColor), _set_sc)

    def _set_sx(self, v):
        if _finite(v):
            self._s.shadowOffsetX = float(v)
    shadowOffsetX = property(lambda self: self._s.shadowOffsetX, _set_sx)

    def _set_sy(self, v):
        if _finite(v):
            self._s.shadowOffsetY = float(v)
    shadowOffsetY = property(lambda self: self._s.shadowOffsetY, _set_sy)

    def _set_filter(self, v):
        if isinstance(v, str):
            self._s.filter = v
    filter = property(lambda self: self._s.filter, _set_filter)

    def _set_smooth(self, v):
        self._s.smoothing = bool(v)
    imageSmoothingEnabled = property(lambda self: self._s.smoothing, _set_smooth)

    def _set_sq(self, v):
        if v in ('low', 'medium', 'high'):
            self._s.smoothingQuality = v
    imageSmoothingQuality = property(lambda self: self._s.smoothingQuality, _set_sq)

    # ------------------------------------------------------------------------------------------ save/restore
    def save(self):
        self._stack.append(self._s.copy())
        self._sk.save()

    def restore(self):
        if not self._stack:
            return
        self._s = self._stack.pop()
        self._sk.restore()

    def reset(self):
        self.canvas._clear()
        self._reset()

    def getContextAttributes(self):
        return {'alpha': True, 'colorSpace': 'srgb', 'desynchronized': False, 'willReadFrequently': False}

    # -------------------------------------------------------------------------------------------- transform
    def translate(self, x, y):
        if _finite(x) and _finite(y):
            self._s.matrix.preTranslate(float(x), float(y))

    def rotate(self, a):
        if _finite(a):
            self._s.matrix.preRotate(math.degrees(a))

    def scale(self, x, y):
        if _finite(x) and _finite(y):
            self._s.matrix.preScale(float(x), float(y))

    def transform(self, a, b, c, d, e, f):
        if all(_finite(v) for v in (a, b, c, d, e, f)):
            self._s.matrix.preConcat(skia.Matrix.MakeAll(a, c, e, b, d, f, 0, 0, 1))

    def setTransform(self, a=None, b=None, c=None, d=None, e=None, f=None):
        if a is None:
            self._s.matrix = skia.Matrix()
        elif b is None:
            self._s.matrix = _to_matrix(a)
        elif all(_finite(v) for v in (a, b, c, d, e, f)):
            self._s.matrix = skia.Matrix.MakeAll(a, c, e, b, d, f, 0, 0, 1)

    def resetTransform(self):
        self._s.matrix = skia.Matrix()

    def getTransform(self):
        m = self._s.matrix
        return DOMMatrix(m.getScaleX(), m.getSkewY(), m.getSkewX(), m.getScaleY(), m.getTranslateX(),
                         m.getTranslateY())

    # --------------------------------------------------------------------------------------------- paths
    def beginPath(self):
        self._path = skia.Path()
        self._has_cur = False

    # ------------------------------------------------------------------------------------------- painting
    def _paint_for(self, style, stroke=False):
        s = self._s
        p = skia.Paint()
        p.setAntiAlias(True)
        if isinstance(style, CanvasGradient):
            sh = style._shader(1.0)
            if sh is None or sh == 'none':
                return None
            p.setShader(sh)
            p.setAlphaf(s.alpha)
        elif isinstance(style, CanvasPattern):
            p.setShader(style._shader(1.0, s.smoothing))
            p.setAlphaf(s.alpha)
        else:
            p.setColor4f(_skcolor(style, s.alpha))
        if stroke:
            p.setStyle(skia.Paint.kStroke_Style)
            p.setStrokeWidth(s.lineWidth)
            p.setStrokeCap(_CAP[s.lineCap])
            p.setStrokeJoin(_JOIN[s.lineJoin])
            p.setStrokeMiter(s.miterLimit)
            if s.dash and any(x > 0 for x in s.dash):
                p.setPathEffect(skia.DashPathEffect.Make(s.dash, s.dashOffset))
        return p

    def _filter(self):
        """CSS filter string -> skia ImageFilter (blur, brightness, contrast, saturate, sepia, grayscale, invert,
        opacity, hue-rotate, drop-shadow) or None."""
        f = (self._s.filter or 'none').strip()
        if f == 'none' or not f:
            return None
        return _css_filter(f)

    def _shadow_on(self):
        s = self._s
        return s.shadowColor[3] > 0 and (s.shadowBlur > 0 or s.shadowOffsetX != 0 or s.shadowOffsetY != 0)

    def _draw(self, fn, paint, local=True):
        """Runs fn(skcanvas, paint) with the CTM applied (local=True) and the compositing state."""
        if paint is None:
            return
        s = self._s
        sk = self._sk
        m = s.matrix
        inv = skia.Matrix()
        if local and not m.invert(inv):
            return  # non-invertible CTM draws nothing
        filt = self._filter()
        shadow = self._shadow_on()
        mode = _BLEND[s.comp]
        if not shadow and filt is None and s.comp not in _UNBOUNDED:
            paint.setBlendMode(mode)
            sk.save()
            sk.setMatrix(m if local else skia.Matrix())
            fn(sk, paint)
            sk.restore()
            return
        lp = skia.Paint()
        lp.setBlendMode(mode)
        if shadow:
            sig = s.shadowBlur / 2.0
            filt = skia.ImageFilters.DropShadow(s.shadowOffsetX, s.shadowOffsetY, sig, sig,
                                                _skcolor(s.shadowColor).toColor(), filt)
        if filt is not None:
            lp.setImageFilter(filt)
        sk.save()
        sk.resetMatrix()
        sk.saveLayer(None, lp)
        sk.setMatrix(m if local else skia.Matrix())
        paint.setBlendMode(skia.BlendMode.kSrcOver)
        fn(sk, paint)
        sk.restore()
        sk.restore()

    def _local_path(self, path=None):
        """Current (device) path mapped back to user space for drawing with the CTM."""
        m = self._s.matrix
        if path is not None:
            return skia.Path(path._p)
        p = skia.Path(self._path)
        if not m.isIdentity():
            inv = skia.Matrix()
            if not m.invert(inv):
                return None
            p.transform(inv)
        return p

    @staticmethod
    def _rule(path, rule):
        path.setFillType(skia.PathFillType.kEvenOdd if rule == 'evenodd' else skia.PathFillType.kWinding)
        return path

    def fill(self, a=None, b=None):
        path, rule = (a, b) if isinstance(a, Path2D) else (None, a)
        p = self._local_path(path)
        if p is None:
            return
        self._rule(p, rule or 'nonzero')
        paint = self._paint_for(self._s.fill)
        self._draw(lambda c, pt: c.drawPath(p, pt), paint)

    def stroke(self, path=None):
        p = self._local_path(path if isinstance(path, Path2D) else None)
        if p is None:
            return
        paint = self._paint_for(self._s.stroke, stroke=True)
        self._draw(lambda c, pt: c.drawPath(p, pt), paint)

    def clip(self, a=None, b=None):
        path, rule = (a, b) if isinstance(a, Path2D) else (None, a)
        if path is not None:
            p = skia.Path(path._p)
            p.transform(self._s.matrix)
        else:
            p = skia.Path(self._path)
        self._rule(p, rule or 'nonzero')
        # the skia canvas matrix is identity between draws: clip with the device-space path
        self._sk.clipPath(p, skia.ClipOp.kIntersect, True)

    def isPointInPath(self, a, b=None, c=None, d=None):
        if isinstance(a, Path2D):
            path, x, y, rule = a, b, c, d
            p = skia.Path(path._p)
            p.transform(self._s.matrix)
        else:
            x, y, rule = a, b, c
            p = skia.Path(self._path)
        self._rule(p, rule or 'nonzero')
        return bool(p.contains(float(x), float(y)))

    def isPointInStroke(self, a, b=None, c=None):
        if isinstance(a, Path2D):
            p = skia.Path(a._p)
            x, y = b, c
        else:
            p = self._local_path()
            x, y = a, b
        paint = self._paint_for((0, 0, 0, 1.0), stroke=True)
        out = skia.Path()
        paint.getFillPath(p, out)
        out.transform(self._s.matrix)
        return bool(out.contains(float(x), float(y)))

    def fillRect(self, x, y, w, h):
        if not all(_finite(v) for v in (x, y, w, h)) or w == 0 or h == 0:
            return
        r = skia.Rect.MakeXYWH(x, y, w, h)
        r.sort()
        paint = self._paint_for(self._s.fill)
        self._draw(lambda c, pt: c.drawRect(r, pt), paint)

    def strokeRect(self, x, y, w, h):
        if not all(_finite(v) for v in (x, y, w, h)):
            return
        p = skia.Path()
        if w == 0 and h == 0:
            return
        if w == 0 or h == 0:
            p.moveTo(x, y)
            p.lineTo(x + w, y + h)
        else:
            p.addRect(skia.Rect.MakeXYWH(x, y, w, h))
        paint = self._paint_for(self._s.stroke, stroke=True)
        self._draw(lambda c, pt: c.drawPath(p, pt), paint)

    def clearRect(self, x, y, w, h):
        if not all(_finite(v) for v in (x, y, w, h)):
            return
        r = skia.Rect.MakeXYWH(x, y, w, h)
        r.sort()
        p = skia.Paint()
        p.setAntiAlias(True)
        p.setBlendMode(skia.BlendMode.kClear)
        sk = self._sk
        sk.save()
        sk.setMatrix(self._s.matrix)
        sk.drawRect(r, p)
        sk.restore()

    # --------------------------------------------------------------------------------------------- text
    def _layout(self, text, max_width=None):
        s = self._s
        fs = s.font or _font_spec('10px sans-serif')
        ls = _css_len(s.letterSpacing, fs.size)
        text = str(text).replace('\t', ' ').replace('\n', ' ').replace('\r', ' ').replace('\f', ' ')
        runs = []
        x = 0.0
        for face, t in fs.runs(text):
            gids, xs, w = _shape_run(face, t, ls)
            runs.append((face, gids, [x + v for v in xs]))
            x += w
        return fs, runs, x

    def _anchor(self, fs, width):
        s = self._s
        align = s.textAlign
        rtl = s.direction == 'rtl'
        if align == 'start':
            align = 'right' if rtl else 'left'
        elif align == 'end':
            align = 'left' if rtl else 'right'
        dx = {'left': 0.0, 'center': -width / 2.0, 'right': -width}[align]
        f = fs.primary
        b = s.textBaseline
        if b == 'alphabetic':
            dy = 0.0
        elif b == 'top':
            dy = f.em_ascent
        elif b == 'bottom':
            dy = -f.em_descent
        elif b == 'middle':
            dy = (f.em_ascent - f.em_descent) / 2.0
        elif b == 'hanging':
            dy = f.ascent * 0.8
        else:  # ideographic
            dy = -f.descent
        return dx, dy

    def _text(self, text, x, y, max_width, stroke):
        if not (_finite(x) and _finite(y)):
            return
        if max_width is not None and (not _finite(max_width) or max_width <= 0):
            return
        fs, runs, width = self._layout(text)
        if not runs:
            return
        dx, dy = self._anchor(fs, width)
        sx = 1.0
        if max_width is not None and width > max_width:
            sx = max_width / width
        builder = skia.TextBlobBuilder()
        any_g = False
        for face, gids, xs in runs:
            if not gids:
                continue
            pos = [skia.Point(v + dx, 0.0) for v in xs]
            builder.allocRunPos(face.font, gids, pos)
            any_g = True
        if not any_g:
            return
        blob = builder.make()
        style = self._s.stroke if stroke else self._s.fill
        paint = self._paint_for(style, stroke=stroke)
        if paint is None:
            return

        def draw(c, pt):
            c.translate(x, y + dy)
            if sx != 1.0:
                c.translate(-0.0, 0)
                c.scale(sx, 1.0)
            c.drawTextBlob(blob, 0, 0, pt)
        if sx != 1.0:
            # maxWidth squeeze keeps the anchor fixed (x is the anchor for every alignment)
            def draw(c, pt):  # noqa: F811
                c.translate(x, y + dy)
                c.scale(sx, 1.0)
                c.drawTextBlob(blob, 0, 0, pt)
        self._draw(draw, paint)

    def fillText(self, text, x, y, maxWidth=None):
        self._text(text, x, y, maxWidth, False)

    def strokeText(self, text, x, y, maxWidth=None):
        self._text(text, x, y, maxWidth, True)

    def measureText(self, text):
        fs, runs, width = self._layout(text)
        f = fs.primary
        dx, dy = self._anchor(fs, width)
        left = right = asc = desc = 0.0
        first = True
        for face, gids, xs in runs:
            if not gids:
                continue
            bounds = face.font.getBounds(gids)
            for gx, bb in zip(xs, bounds):
                if bb.isEmpty():
                    continue
                l, r, t, b = gx + bb.left(), gx + bb.right(), bb.top(), bb.bottom()
                if first:
                    left, right, asc, desc = l, r, t, b
                    first = False
                else:
                    left, right, asc, desc = min(left, l), max(right, r), min(asc, t), max(desc, b)
        return TextMetrics(
            width=width,
            actualBoundingBoxLeft=-(left + dx),
            actualBoundingBoxRight=right + dx,
            actualBoundingBoxAscent=-asc - dy,
            actualBoundingBoxDescent=desc + dy,
            fontBoundingBoxAscent=f.ascent - dy,
            fontBoundingBoxDescent=f.descent + dy,
            emHeightAscent=f.em_ascent - dy,
            emHeightDescent=f.em_descent + dy,
            hangingBaseline=f.ascent * 0.8 - dy,
            alphabeticBaseline=-dy,
            ideographicBaseline=-f.descent - dy,
        )

    # --------------------------------------------------------------------------------------------- images
    def _sampling(self):
        if not self._s.smoothing:
            return skia.SamplingOptions(skia.FilterMode.kNearest)
        if self._s.smoothingQuality == 'high':
            return skia.SamplingOptions(skia.CubicResampler.Mitchell())
        if self._s.smoothingQuality == 'medium':
            return skia.SamplingOptions(skia.FilterMode.kLinear, skia.MipmapMode.kLinear)
        return skia.SamplingOptions(skia.FilterMode.kLinear)

    def drawImage(self, img, *a):
        im = _skimage_of(img)
        if im is None:
            return
        iw, ih = im.width(), im.height()
        if len(a) == 2:
            sx, sy, sw, sh = 0, 0, iw, ih
            dx, dy, dw, dh = a[0], a[1], iw, ih
        elif len(a) == 4:
            sx, sy, sw, sh = 0, 0, iw, ih
            dx, dy, dw, dh = a
        elif len(a) == 8:
            sx, sy, sw, sh, dx, dy, dw, dh = a
        else:
            raise TypeError('drawImage: bad arguments')
        if not all(_finite(v) for v in (sx, sy, sw, sh, dx, dy, dw, dh)):
            return
        if sw == 0 or sh == 0 or dw == 0 or dh == 0:
            return
        src = skia.Rect.MakeXYWH(sx, sy, sw, sh)
        dst = skia.Rect.MakeXYWH(dx, dy, dw, dh)
        # normalize negative sizes (flip both rects together)
        if sw < 0:
            src = skia.Rect.MakeLTRB(sx + sw, src.top(), sx, src.bottom())
            dst = skia.Rect.MakeLTRB(dst.left(), dst.top(), dst.right(), dst.bottom())
        if sh < 0:
            src = skia.Rect.MakeLTRB(src.left(), sy + sh, src.right(), sy)
        dst.sort()
        # clip the source rect to the image bounds, shrinking the destination accordingly
        img_r = skia.Rect.MakeWH(iw, ih)
        cs = skia.Rect(src.left(), src.top(), src.right(), src.bottom())
        if not cs.intersect(img_r):
            return
        if cs != src:
            kx = dst.width() / src.width()
            ky = dst.height() / src.height()
            dst = skia.Rect.MakeLTRB(dst.left() + (cs.left() - src.left()) * kx,
                                     dst.top() + (cs.top() - src.top()) * ky,
                                     dst.right() - (src.right() - cs.right()) * kx,
                                     dst.bottom() - (src.bottom() - cs.bottom()) * ky)
            src = cs
        paint = skia.Paint()
        paint.setAntiAlias(True)
        paint.setAlphaf(self._s.alpha)
        samp = self._sampling()
        self._draw(lambda c, pt: c.drawImageRect(im, src, dst, samp, pt, skia.Canvas.kStrict_SrcRectConstraint),
                   paint)

    def createPattern(self, img, repetition='repeat'):
        im = _skimage_of(img)
        if im is None:
            return None
        if repetition in (None, ''):
            repetition = 'repeat'
        return CanvasPattern(im, repetition)

    def createLinearGradient(self, x0, y0, x1, y1):
        return CanvasGradient('linear', (float(x0), float(y0), float(x1), float(y1)))

    def createRadialGradient(self, x0, y0, r0, x1, y1, r1):
        if r0 < 0 or r1 < 0:
            raise ValueError('IndexSizeError: negative radius')
        return CanvasGradient('radial', (float(x0), float(y0), float(r0), float(x1), float(y1), float(r1)))

    def createConicGradient(self, start, x, y):
        return CanvasGradient('conic', (float(start), float(x), float(y)))

    # --------------------------------------------------------------------------------------------- pixels
    def createImageData(self, w, h=None):
        if isinstance(w, ImageData):
            return ImageData(w.width, w.height)
        return ImageData(abs(int(w)), abs(int(h)))

    def getImageData(self, sx, sy, sw, sh):
        sx, sy, sw, sh = int(math.floor(sx)), int(math.floor(sy)), int(sw), int(sh)
        if sw < 0:
            sx, sw = sx + sw, -sw
        if sh < 0:
            sy, sh = sy + sh, -sh
        out = np.zeros((sh, sw, 4), dtype=np.uint8)
        full = self.canvas._rgba()  # (H, W, 4) unpremultiplied
        H, W = full.shape[:2]
        x0, y0 = max(0, sx), max(0, sy)
        x1, y1 = min(W, sx + sw), min(H, sy + sh)
        if x1 > x0 and y1 > y0:
            out[y0 - sy:y1 - sy, x0 - sx:x1 - sx] = full[y0:y1, x0:x1]
        return ImageData(sw, sh, out.reshape(-1))

    def putImageData(self, img, dx, dy, dirtyX=0, dirtyY=0, dirtyW=None, dirtyH=None):
        dx, dy = int(math.floor(dx)), int(math.floor(dy))
        w, h = img.width, img.height
        if dirtyW is None:
            dirtyW, dirtyH = w, h
        if dirtyW < 0:
            dirtyX, dirtyW = dirtyX + dirtyW, -dirtyW
        if dirtyH < 0:
            dirtyY, dirtyH = dirtyY + dirtyH, -dirtyH
        x0, y0 = max(0, int(dirtyX)), max(0, int(dirtyY))
        x1, y1 = min(w, int(dirtyX + dirtyW)), min(h, int(dirtyY + dirtyH))
        if x1 <= x0 or y1 <= y0:
            return
        arr = np.asarray(img.data, dtype=np.uint8).reshape(h, w, 4)[y0:y1, x0:x1]
        self.canvas._put(np.ascontiguousarray(arr), dx + x0, dy + y0)


def _skimage_of(img):
    if isinstance(img, Canvas):
        return img._snapshot()
    if isinstance(img, Image):
        return img._skimage()
    if isinstance(img, ImageData):
        arr = np.asarray(img.data, dtype=np.uint8).reshape(img.height, img.width, 4)
        return skia.Image.fromarray(np.ascontiguousarray(arr), skia.ColorType.kRGBA_8888_ColorType,
                                    skia.AlphaType.kUnpremul_AlphaType)
    if isinstance(img, skia.Image):
        return img
    if hasattr(img, 'canvas') and isinstance(getattr(img, 'canvas'), Canvas):
        return img.canvas._snapshot()
    return None


_pb_methods(CanvasRenderingContext2D, lambda self: (self._path, self), lambda self: self._s.matrix)


# =================================================================================================== canvas
class Canvas:
    """document.createElement('canvas') equivalent. Setting width/height clears it (like the DOM)."""

    def __init__(self, width=300, height=150):
        self._w = max(1, int(width))
        self._h = max(1, int(height))
        self._zero = int(width) <= 0 or int(height) <= 0
        self._surface = skia.Surface(self._w, self._h)
        self._ctx = None
        self.name = None

    def _resize(self, w, h):
        self._w, self._h = max(1, int(w)), max(1, int(h))
        self._surface = skia.Surface(self._w, self._h)
        if self._ctx is not None:
            self._ctx._reset()

    width = property(lambda self: self._w, lambda self, v: self._resize(v, self._h))
    height = property(lambda self: self._h, lambda self, v: self._resize(self._w, v))

    def getContext(self, kind='2d', opts=None):
        if kind != '2d':
            return None
        if self._ctx is None:
            self._ctx = CanvasRenderingContext2D(self)
        return self._ctx

    def _clear(self):
        c = self._surface.getCanvas()
        c.save()
        c.resetMatrix()
        c.clear(skia.Color4f(0, 0, 0, 0))
        c.restore()

    def _snapshot(self):
        return self._surface.makeImageSnapshot()

    def _rgba(self):
        """(H, W, 4) uint8 RGBA unpremultiplied copy of the pixels."""
        img = self._snapshot()
        return img.toarray(colorType=skia.ColorType.kRGBA_8888_ColorType, alphaType=skia.AlphaType.kUnpremul_AlphaType)

    def _put(self, arr, x, y):
        info = skia.ImageInfo.Make(arr.shape[1], arr.shape[0], skia.ColorType.kRGBA_8888_ColorType,
                                   skia.AlphaType.kUnpremul_AlphaType)
        self._surface.getCanvas().writePixels(info, arr.tobytes(), arr.shape[1] * 4, x, y)

    # ------------------------------------------------------------------------------------------- output
    def to_array(self):
        """(H, W, 4) uint8 RGBA (straight alpha) — what getImageData returns for the full canvas."""
        return self._rgba()

    def save_png(self, path):
        d = os.path.dirname(path)
        if d:
            os.makedirs(d, exist_ok=True)
        arr = np.ascontiguousarray(self._rgba())
        img = skia.Image.fromarray(arr, skia.ColorType.kRGBA_8888_ColorType, skia.AlphaType.kUnpremul_AlphaType)
        data = img.encodeToData(skia.EncodedImageFormat.kPNG, 100)
        with open(path, 'wb') as f:
            f.write(bytes(data))
        return path

    def toDataURL(self, kind='image/png'):
        import base64
        arr = np.ascontiguousarray(self._rgba())
        img = skia.Image.fromarray(arr, skia.ColorType.kRGBA_8888_ColorType, skia.AlphaType.kUnpremul_AlphaType)
        return 'data:image/png;base64,' + base64.b64encode(bytes(img.encodeToData())).decode()

    def to_blender_image(self, name, filepath=None):
        """Creates (or refreshes) a bpy image with these pixels. With filepath the PNG is saved there and the
        image references the file (the exporter then points the glTF at it); otherwise the pixels are packed."""
        import bpy
        if filepath:
            self.save_png(filepath)
            img = bpy.data.images.get(name)
            if img is None or bpy.path.abspath(img.filepath) != filepath:
                img = bpy.data.images.load(filepath, check_existing=True)
                img.name = name
            else:
                img.reload()
            return img
        img = bpy.data.images.get(name)
        if img is None or img.size[0] != self._w or img.size[1] != self._h:
            if img is not None:
                bpy.data.images.remove(img)
            img = bpy.data.images.new(name, self._w, self._h, alpha=True)
        arr = self._rgba()[::-1].astype(np.float32) / 255.0  # Blender pixel rows go bottom-up
        img.pixels.foreach_set(arr.reshape(-1))
        img.pack()
        return img


def createCanvas(w, h):
    return Canvas(w, h)
