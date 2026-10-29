"""Secondhand Stars · logo de la pantalla de título (assets/ui/logo.png).

"SECONDHAND" en esténcil de carga (Saira Stencil One, OFL) sobre una tira de metal remachada; "STARS" en letras de
cartel (Bungee, OFL) con esmalte de dos tonos gastado por el sol, contorno grueso, sombra dura y rayones; una estrella
de chapa remachada y soldada (la del cartel de la tienda) con la estela de una estrella fugaz (la lluvia de chatarra).
Nada de letras amarillas solo de contorno ni tipografía de la saga: es un cartel de taller.

Se dibuja a resolución nativa sin suavizado y se agranda x PX (píxeles grandes, como el resto del arte).
"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage as ndi
from ss_ui import plate, hexc

FONTS = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'fonts')


def text_mask(txt, font, spacing=0, aa=False):
    """Máscara booleana del texto (sin suavizado), con espaciado extra entre letras."""
    w = int(sum(font.getlength(c) for c in txt) + spacing * (len(txt) - 1) + 8)
    asc, desc = font.getmetrics()
    h = asc + desc + 8
    im = Image.new('L', (w, h), 0)
    d = ImageDraw.Draw(im)
    if not aa:
        d.fontmode = '1'
    x = 4
    for c in txt:
        d.text((x, 2), c, font=font, fill=255)
        x += font.getlength(c) + spacing
    a = np.array(im) > 127
    ys, xs = np.nonzero(a)
    return a[ys.min():ys.max() + 1, xs.min():xs.max() + 1]


def dilate(m, r):
    st = np.zeros((2 * r + 1, 2 * r + 1), bool)
    yy, xx = np.mgrid[-r:r + 1, -r:r + 1]
    st[(xx * xx + yy * yy) <= r * r + 0.5] = True
    return ndi.binary_dilation(m, structure=st)


def star_pts(cx, cy, ro, ri, rot=-90):
    pts = []
    for k in range(10):
        a = math.radians(rot + k * 36)
        r = ro if k % 2 == 0 else ri
        pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    return pts


def build_logo(out, px=3, W0=320, H0=136):
    canvas = np.zeros((H0, W0, 4), np.uint8)

    def put(mask, col, ox=0, oy=0):
        h, w = mask.shape
        sub = canvas[oy:oy + h, ox:ox + w]
        mm = mask[:sub.shape[0], :sub.shape[1]]
        sub[mm] = hexc(col) if isinstance(col, str) else col

    f_big = ImageFont.truetype(os.path.join(FONTS, 'Bungee-Regular.ttf'), 58)
    f_small = ImageFont.truetype(os.path.join(FONTS, 'SairaStencilOne-Regular.ttf'), 21)
    stars = text_mask('STARS', f_big, spacing=3)
    second = text_mask('SECONDHAND', f_small, spacing=3)
    sh, sw = stars.shape
    # --- tira de metal con SECONDHAND
    strip_w, strip_h = second.shape[1] + 34, second.shape[0] + 12
    sx = (W0 - strip_w) // 2 - 10
    sy = 6
    strip = plate(strip_w, strip_h, '#2f3b3d', '#4e6062', '#1e2628', '#121718', rivet=('#8a8e90', '#c4c8c8', '#4a4e50'), chamfer=2)
    sub = canvas[sy:sy + strip_h, sx:sx + strip_w]
    a = strip[..., 3] > 0
    sub[a] = strip[a]
    tx, ty = sx + (strip_w - second.shape[1]) // 2, sy + (strip_h - second.shape[0]) // 2
    put(second, '#141a1c', tx + 1, ty + 1)
    put(second, '#ece2c8', tx, ty)
    # --- STARS: sombra dura, contorno, esmalte de dos tonos, brillo arriba y rayones
    ox = (W0 - sw) // 2 - 10
    oy = sy + strip_h + 6
    pad = 4
    big = np.zeros((sh + 2 * pad + 4, sw + 2 * pad + 4), bool)
    big[pad:pad + sh, pad:pad + sw] = stars
    outl = dilate(big, 3)
    shadow = np.zeros_like(outl)
    shadow[4:, 4:] = outl[:-4, :-4]
    put(shadow & ~outl, '#1c1210', ox - pad, oy - pad)
    put(outl, '#2a1a16', ox - pad, oy - pad)
    # relleno: arriba ámbar claro, abajo naranja tostado, con una franja de luz en el tercio de arriba
    ys = np.mgrid[0:big.shape[0], 0:big.shape[1]][0]
    top_c, mid_c, bot_c, line_c = hexc('#f4c060'), hexc('#eaa23c'), hexc('#c8702e'), hexc('#ffe4a0')
    fill = np.zeros(big.shape + (4,), np.uint8)
    split = pad + int(sh * 0.56)
    fill[big & (ys < split)] = mid_c
    fill[big & (ys >= split)] = bot_c
    fill[big & (ys < pad + int(sh * 0.22))] = top_c
    # borde superior interior de cada letra: 1 px de luz
    topedge = big & ~np.roll(big, 1, axis=0)
    fill[topedge] = line_c
    # línea fina oscura entre los dos tonos (esmalte de dos colores)
    fill[big & (ys == split)] = hexc('#a85a28')
    # rayones: diagonales cortas claras (gasto de sol y uso)
    rng = np.random.RandomState(7)
    for k in range(9):
        x0 = rng.randint(pad + 4, pad + sw - 8)
        y0 = rng.randint(pad + 6, pad + sh - 6)
        L = rng.randint(3, 7)
        for t in range(L):
            yy, xx = y0 + t // 2, x0 + t
            if big[yy, xx]:
                fill[yy, xx] = hexc('#f8d898') if ys[yy, xx] < split else hexc('#e0985a')
    sub = canvas[oy - pad:oy - pad + big.shape[0], ox - pad:ox - pad + big.shape[1]]
    sub[big] = fill[big]
    # --- estrella de chapa remachada con soldadura, y estela de estrella fugaz
    cx, cy = ox + sw + 18, oy + 6
    # estela (tres trazos que se desvanecen hacia arriba a la derecha)
    for k, (col, w_) in enumerate((('#ffe4a0', 3), ('#eaa23c', 2), ('#c8702e', 1))):
        for t in range(16 + k * 6):
            x = cx + 6 + t + k * 2
            y = cy - 6 - t * 0.55 + k * 2.0
            if 0 <= int(y) < H0 and 0 <= int(x) + w_ < W0:
                canvas[int(y), int(x):int(x) + w_] = hexc(col)
    im = Image.new('L', (W0, H0), 0)
    d = ImageDraw.Draw(im)
    d.polygon(star_pts(cx, cy, 17, 7.2, rot=-90 + 8), fill=255)
    m = np.array(im) > 127
    outm = dilate(m, 2)
    shm = np.zeros_like(outm)
    shm[3:, 3:] = outm[:-3, :-3]
    canvas[shm & ~outm] = hexc('#1c1210')
    canvas[outm & ~m] = hexc('#2a1a16')
    yy, xx = np.mgrid[0:H0, 0:W0]
    lit = (xx - cx) * 0.6 + (yy - cy) * 0.8
    canvas[m & (lit <= -2)] = hexc('#f6d27a')
    canvas[m & (lit > -2) & (lit <= 5)] = hexc('#dcae4e')
    canvas[m & (lit > 5)] = hexc('#a8783a')
    # soldadura (costura en zigzag) a través de un brazo: la estrella está remendada
    for t in range(9):
        x = int(cx + 3 + t)
        y = int(cy - 2 + (t % 2) + t * 0.35)
        if m[y, x]:
            canvas[y, x] = hexc('#6a4424')
            if m[y - 1, x]:
                canvas[y - 1, x] = hexc('#ffe6a6')
    # remaches en las puntas internas
    for (x, y) in star_pts(cx, cy, 5.2, 5.2, rot=-90 + 8 + 36)[::2]:
        x, y = int(round(x)), int(round(y))
        canvas[y, x] = hexc('#fff0c0')
        canvas[y + 1, x] = hexc('#8a6030')
    img = Image.fromarray(canvas, 'RGBA')
    bb = img.getbbox()
    img = img.crop((max(0, bb[0] - 2), max(0, bb[1] - 2), min(W0, bb[2] + 2), min(H0, bb[3] + 2)))
    img = img.resize((img.width * px, img.height * px), Image.NEAREST)
    os.makedirs(os.path.join(out, 'ui'), exist_ok=True)
    img.save(os.path.join(out, 'ui', 'logo.png'))
    return img


if __name__ == '__main__':
    args = sys.argv[1:]
    out = './out'
    if '--out' in args:
        out = args[args.index('--out') + 1]
    im = build_logo(out)
    print('ok logo', im.size)
