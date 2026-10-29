"""Secondhand Stars · kit de interfaz ("taller del futuro usado": placas de metal remachadas, pantallas CRT ámbar,
etiquetas de papel). Limpio y profesional: formas lisas, biseles de 1 px, remaches solo en las esquinas, nada de ruido.

Convención (la del Caldero): las texturas de 9 cortes salen YA a x3 (márgenes en píxeles de pantalla); los iconos salen
a x1 (16x16) para mostrarse a x2 o x3 con filtro NEAREST. Márgenes y colores de texto en assets/ui/ui_kit.json.

Uso: python3 ss_ui.py [--out DIR]  -> DIR/ui/*.png + DIR/ui/ui_kit.json
"""
import sys, os, json, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from PIL import Image

S = 3          # escala de las texturas de 9 cortes


def hexc(h, a=255):
    h = h.lstrip('#')
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def up(arr, s=S):
    im = Image.fromarray(arr, 'RGBA')
    return im.resize((im.width * s, im.height * s), Image.NEAREST)


def rrect_mask(w, h, r=0, chamfer=0):
    m = np.ones((h, w), bool)
    ys, xs = np.mgrid[0:h, 0:w]
    if chamfer:
        c = chamfer
        m &= ~((xs + ys) < c)
        m &= ~(((w - 1 - xs) + ys) < c)
        m &= ~((xs + (h - 1 - ys)) < c)
        m &= ~(((w - 1 - xs) + (h - 1 - ys)) < c)
    if r:
        for (cx, cy) in ((r - 0.5, r - 0.5), (w - r - 0.5, r - 0.5), (r - 0.5, h - r - 0.5), (w - r - 0.5, h - r - 0.5)):
            corner = ((xs < r) if cx < w / 2 else (xs >= w - r)) & ((ys < r) if cy < h / 2 else (ys >= h - r))
            m &= ~(corner & (((xs - cx) ** 2 + (ys - cy) ** 2) > (r - 0.15) ** 2))
    return m


def edges(m):
    """Bordes interiores de una máscara: arriba, izquierda, abajo, derecha (1 px)."""
    pad = np.pad(m, 1)
    top = m & ~pad[:-2, 1:-1]
    bot = m & ~pad[2:, 1:-1]
    left = m & ~pad[1:-1, :-2]
    right = m & ~pad[1:-1, 2:]
    return top, left, bot, right


def shrink(m, k=1):
    out = m.copy()
    for _ in range(k):
        t, l, b, r = edges(out)
        out &= ~(t | l | b | r)
    return out


def paint(arr, m, col):
    arr[m] = col


def plate(w, h, fill, hi, lo, line, rivet=None, chamfer=2, brushed=None):
    """Placa de metal: contorno oscuro, bisel claro arriba/izquierda y oscuro abajo/derecha, remaches en las esquinas."""
    arr = np.zeros((h, w, 4), np.uint8)
    m = rrect_mask(w, h, chamfer=chamfer)
    paint(arr, m, hexc(line))
    inner = shrink(m)
    paint(arr, inner, hexc(fill))
    t, l, b, r = edges(inner)
    paint(arr, t | l, hexc(hi))
    paint(arr, b | r, hexc(lo))
    if brushed:
        # vetas horizontales MUY suaves (cada 3 filas una apenas más clara): textura de metal cepillado
        core = shrink(inner, 2)
        for y in range(0, h, 3):
            row = np.zeros_like(core)
            row[y] = True
            paint(arr, core & row, hexc(brushed))
    if rivet:
        base, light, dark = rivet
        for (x, y) in ((3, 3), (w - 5, 3), (3, h - 5), (w - 5, h - 5)):
            arr[y:y + 2, x:x + 2] = hexc(base)
            arr[y, x] = hexc(light)
            arr[y + 1, x + 1] = hexc(dark)
    return arr


def screen(w, h):
    """Pantalla CRT ámbar: bisel oscuro con brillo arriba, vidrio marrón muy oscuro con líneas de barrido y viñeta."""
    arr = plate(w, h, '#262224', '#4a4446', '#141012', '#0c0a0a', rivet=('#7a7470', '#a8a29a', '#3a3634'), chamfer=2)
    gl = rrect_mask(w - 8, h - 8, r=2)
    glass = np.zeros((h, w), bool)
    glass[4:h - 4, 4:w - 4] = gl
    paint(arr, glass, hexc('#2e1c0e'))
    ys = np.mgrid[0:h, 0:w][0]
    paint(arr, glass & (ys % 2 == 1), hexc('#28180c'))
    # viñeta: el borde del vidrio más oscuro, un reflejo diagonal arriba a la izquierda
    ring = glass & ~shrink(glass, 1)
    paint(arr, ring, hexc('#1c120a'))
    for k in range(3):
        if 6 + k < w - 6:
            arr[6, 6 + k] = hexc('#5a3a1c')
    arr[7, 6] = hexc('#4a3018')
    return arr


def tag(w, h):
    """Etiqueta de papel: crema, borde un poco más oscuro, ojal reforzado a la izquierda con un hilo, esquinas
    cortadas a la izquierda (forma de etiqueta), lado derecho levemente rasgado."""
    arr = np.zeros((h, w, 4), np.uint8)
    m = np.ones((h, w), bool)
    ys, xs = np.mgrid[0:h, 0:w]
    m &= ~((xs + ys) < 4) & ~((xs + (h - 1 - ys)) < 4)
    # borde derecho rasgado (dientes de 1 px)
    m &= ~((xs == w - 1) & (ys % 3 == 0))
    paint(arr, m, hexc('#6a5a44'))
    inner = shrink(m)
    paint(arr, inner, hexc('#ece2c8'))
    t, l, b, r = edges(inner)
    paint(arr, b | r, hexc('#d6c8a6'))
    paint(arr, t, hexc('#f6eedc'))
    cy = h // 2
    # ojal
    for (dx, dy, c) in ((0, -1, '#b8a888'), (-1, 0, '#b8a888'), (1, 0, '#b8a888'), (0, 1, '#b8a888'),
                        (0, 0, '#3a2e26'), (-1, -1, '#cfc2a4'), (1, 1, '#cfc2a4'), (1, -1, '#cfc2a4'), (-1, 1, '#cfc2a4')):
        arr[cy + dy, 5 + dx] = hexc(c)
    return arr


def key(w, h, face, face_hi, lip, line, press=False, rim=None):
    """Botón tipo tecla: cara plana con brillo arriba, labio de 2 px abajo (profundidad); al apretar baja 1 px."""
    arr = np.zeros((h, w, 4), np.uint8)
    top = 1 if press else 0
    lip_h = 1 if press else 2
    m = rrect_mask(w, h - top, r=2)
    full = np.zeros((h, w), bool)
    full[top:, :] = m
    paint(arr, full, hexc(rim or line))
    body = shrink(full)
    paint(arr, body, hexc(lip))
    fm = body.copy()
    rows = np.nonzero(body.any(axis=1))[0]
    yb = rows.max()
    fm[yb - lip_h + 1:yb + 1, :] = False
    fm = fm & rrect_mask(w, h, r=2)[:, :] if False else fm
    paint(arr, fm, hexc(face))
    t, l, b, r = edges(fm)
    paint(arr, t, hexc(face_hi))
    # línea de separación cara / labio
    sep = fm & ~np.roll(fm, -1, axis=0)
    paint(arr, sep & ~t, hexc(lip))
    return arr


KEYS = {
    'normal':   dict(face='#e8dec6', face_hi='#fff8e6', lip='#a89878', line='#2a2024'),
    'hover':    dict(face='#f6ecd4', face_hi='#fffcf0', lip='#b8a684', line='#2a2024', rim='#e8a038'),
    'pressed':  dict(face='#d8cca8', face_hi='#ece2c6', lip='#9a8a6c', line='#2a2024', press=True),
    'disabled': dict(face='#8c8782', face_hi='#9e9994', lip='#605c58', line='#3a3634'),
    'primary':  dict(face='#eaa23c', face_hi='#ffd28e', lip='#a8622a', line='#2a2024'),
    'primary_hover': dict(face='#f6b452', face_hi='#ffe0a8', lip='#b8702e', line='#2a2024', rim='#fff0c8'),
    'primary_pressed': dict(face='#d8902e', face_hi='#f0b866', lip='#985426', line='#2a2024', press=True),
}


def build_panels(out):
    d = os.path.join(out, 'ui')
    os.makedirs(d, exist_ok=True)
    spec = {}
    # placa oscura (HUD, paneles): metal pavonado verde petróleo, remaches de acero
    a = plate(24, 24, '#2f3b3d', '#4e6062', '#1e2628', '#121718', rivet=('#8a8e90', '#c4c8c8', '#4a4e50'), brushed='#323e40')
    up(a).save(os.path.join(d, 'plate9.png'))
    spec['plate9.png'] = dict(margin=8 * S, content=10 * S, note='placa oscura remachada (HUD, ventanas)')
    # placa clara (carteles, ventanas de diálogo sobre fondo oscuro): metal pintado color arena
    a = plate(24, 24, '#c4b490', '#e2d4b0', '#988a6a', '#3a3026', rivet=('#7a6e5a', '#a89a80', '#4a4034'))
    up(a).save(os.path.join(d, 'plate_light9.png'))
    spec['plate_light9.png'] = dict(margin=8 * S, content=10 * S, note='placa clara (texto oscuro encima)')
    # pantalla ámbar
    a = screen(24, 20)
    up(a).save(os.path.join(d, 'screen9.png'))
    spec['screen9.png'] = dict(margin=8 * S, content=9 * S, text='#f0b44a', text_dim='#9a6a2a', note='CRT ámbar: números, reloj, precios')
    # etiqueta de papel
    a = tag(28, 14)
    up(a).save(os.path.join(d, 'tag9.png'))
    spec['tag9.png'] = dict(margin_left=9 * S, margin_right=4 * S, margin_top=4 * S, margin_bottom=4 * S, text='#3a2e26',
                            content_left=34, content_right=16, content_top=2, content_bottom=4,
                            note='etiqueta de papel (texto a mano con Caveat); el ojal va en el margen izquierdo')
    # botones (teclas)
    for name, kw in KEYS.items():
        a = key(20, 14, **kw)
        up(a).save(os.path.join(d, f'btn_{name}9.png'))
    spec['btn_*9.png'] = dict(margin=5 * S, content_top=3 * S, content_bottom=4 * S, text='#2a2024', text_disabled='#4a4642',
                              note='normal / hover / pressed / disabled (+ primary, primary_hover, primary_pressed)')
    return spec



# ================================================================== iconos (16x16, render HD-2D del kit)
from c64core import Cv, render, bez
from ss_bots import pal_of

ICON_MATS = {
    'gold': ('#e8b448', 'metal'), 'gold2': ('#b07a2a', 'metal'), 'star': ('#f0b440', 'metal'), 'steel': ('#b4b8c2', 'metal'),
    'dkmetal': ('#5a5660', 'metal'), 'wood': ('#a06a3e', 'leather'), 'glass': ('#c4dce4', 'white'), 'sand': ('#e8a838', 'cloth'),
    'teal': '#3e9a92', 'teal2': '#2a6662', 'cream': ('#ece2c8', 'white'), 'tea': ('#8a4e2a', 'cloth'), 'smoke': ('#f0ece4', 'flat'),
    'heat': ('#e8642e', 'gem'), 'heat2': ('#ffd36a', 'flat'), 'heart': ('#d8463e', 'gem'), 'face': ('#f2ead6', 'white'),
    'hand': ('#2a2224', 'flat'), 'cover': '#8a4e30', 'page': ('#ece2c8', 'white'), 'ribbon': ('#d8463e', 'cloth'),
    'pod': ('#9aa8ac', 'metal'), 'podband': '#c0603a', 'light': ('#ffd36a', 'flat'), 'hole': ('#1a1618', 'flat'),
}


def icv():
    pal, kinds = pal_of(ICON_MATS, accents=('teal', 'heat', 'heart', 'sand', 'star', 'gold'))
    return Cv(pal, w=16, h=16, kinds=kinds)


def star_poly(cx, cy, ro, ri, rot=-90):
    pts = []
    for k in range(10):
        a = math.radians(rot + k * 36)
        r = ro if k % 2 == 0 else ri
        pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    return pts


def ic_credits():
    cv = icv()
    p = cv.put(cv.ellipse(7.5, 8.0, 6.6, 6.6), 'gold', mode='shine', cast=1)
    cv.set_nrm(p, cv.sphere_n(6.0, 6.5, 8.0, 8.0, k=0.8))
    ring = cv.ellipse(7.5, 8.0, 5.2, 5.2) & ~cv.ellipse(7.5, 8.0, 4.3, 4.3)
    cv.shade(ring, -1, within=[p])
    cv.paint(cv.poly(star_poly(7.5, 8.2, 3.4, 1.4)), 'gold2', 2)
    cv.dot(4.5, 4.5, 'white', 4)
    return render(cv)


def ic_star():
    cv = icv()
    p = cv.put(cv.poly(star_poly(7.5, 8.4, 7.6, 3.2)), 'star', mode='shine', cast=1)
    cv.set_nrm(p, cv.sphere_n(6.0, 6.5, 8.0, 8.0, k=0.7))
    cv.dot(6.0, 6.0, 'white', 4)
    return render(cv)


def ic_sandtimer():
    cv = icv()
    cv.put(cv.poly([(4, 3), (11, 3), (8, 7.6), (7, 7.6)]) | cv.poly([(7, 8.4), (8, 8.4), (11, 12.6), (4, 12.6)]), 'glass', mode='flat')
    cv.paint(cv.poly([(5.6, 5), (9.4, 5), (8, 7.4), (7, 7.4)]), 'sand', 2)
    cv.paint(cv.poly([(4.6, 12.4), (10.4, 12.4), (7.5, 9.6)]), 'sand', 2)
    cv.dot(7.5, 8.0, 'sand', 3)
    cv.put(cv.rect(2, 1, 13, 2), 'wood', mode='top', iline=True)
    cv.put(cv.rect(2, 13, 13, 14), 'wood', mode='top', iline=True)
    for x in (2, 13):
        cv.put(cv.rect(x, 3, x, 12), 'wood', mode='flat', iline=True)
    return render(cv)


def ic_wrench():
    cv = icv()
    cv.put(cv.capsule((3.6, 12.4), (9.8, 6.2), 1.3), 'steel', mode='shine', cast=1, iline=True)
    head = cv.ellipse(11.0, 5.0, 3.4, 3.4) & ~cv.poly([(11.2, 5.0), (13.6, 0.6), (16.0, 2.4), (12.4, 6.0)])
    cv.put(head, 'steel', mode='shine', cast=1, iline=True)
    cv.put(cv.ellipse(3.4, 12.6, 1.9, 1.9), 'steel', mode='shine', iline=True)
    cv.dot(3.4, 12.6, 'hole', 0)
    return render(cv)


def ic_listen():
    cv = icv()
    cv.put(cv.stroke(bez((3.0, 9.0), (7.5, -1.0), (12.0, 9.0), 14), 1.0), 'steel', mode='shine', cast=1, iline=True)
    for x in (3.4, 11.6):
        p = cv.put(cv.ellipse(x, 10.4, 2.4, 3.4), 'teal', mode='shine', cast=1, iline=True)
        cv.paint(cv.ellipse(x + (0.8 if x < 7 else -0.8), 10.6, 1.0, 2.2), 'teal2', 2)
    return render(cv)


def ic_tap():
    cv = icv()
    cv.put(cv.capsule((11.6, 13.4), (6.6, 6.8), 0.9), 'wood', mode='cyl', cast=1, iline=True)
    cv.put(cv.capsule((3.4, 6.6), (8.8, 3.0), 2.0), 'steel', mode='shine', cast=1, iline=True)
    for (a, b) in (((1.0, 10.6), (2.6, 9.6)), ((3.2, 12.6), (3.8, 11.0)), ((0.4, 8.2), (1.8, 8.4))):
        q = cv.put(cv.line([a, b]), 'heat2', mode='flat', outline=False)
        cv.parts[q].keep = True
    return render(cv)


def ic_scan():
    cv = icv()
    cv.put(cv.capsule((10.4, 10.4), (13.8, 13.8), 1.4), 'wood', mode='cyl', cast=1, iline=True)
    cv.put(cv.ellipse(6.5, 6.5, 5.6, 5.6) & ~cv.ellipse(6.5, 6.5, 4.0, 4.0), 'steel', mode='shine', cast=1, iline=True)
    g = cv.put(cv.ellipse(6.5, 6.5, 4.0, 4.0), 'heat', mode='flat')
    cv.paint(cv.ellipse(7.0, 7.4, 2.2, 1.8), 'heat2', 2)
    for (x, y) in ((4, 4), (5, 4)):
        cv.dot(x, y, 'white', 4)
    return render(cv)


def ic_tea():
    cv = icv()
    cv.put(cv.ellipse(7.5, 13.4, 6.8, 1.8), 'cream', mode='top', cast=1, iline=True)
    h = cv.ellipse(12.6, 8.8, 2.2, 2.2) & ~cv.ellipse(12.6, 8.8, 1.0, 1.0)
    cv.put(h, 'cream', mode='shine', iline=True)
    p = cv.put(cv.poly([(2.6, 6), (12.4, 6), (11.0, 12.4), (4.0, 12.4)]), 'cream', mode='cyl', cast=1, iline=True)
    cv.paint(cv.rect(2, 8, 13, 9) & cv.of(p), 'teal', 2)
    cv.put(cv.ellipse(7.5, 6.0, 4.8, 1.1), 'tea', mode='flat')
    for pts in (((6.0, 4.0), (5.0, 2.2), (6.0, 0.4)), ((9.4, 4.0), (10.4, 2.2), (9.4, 0.4))):
        q = cv.put(cv.line(list(pts)), 'smoke', mode='flat', outline=False)
        cv.parts[q].keep = True
    return render(cv)


def ic_rep():
    cv = icv()
    hm = cv.ellipse(5.0, 6.0, 3.4, 3.4) | cv.ellipse(10.0, 6.0, 3.4, 3.4) | cv.poly([(1.8, 7.4), (13.2, 7.4), (7.5, 14.0)])
    p = cv.put(hm, 'heart', mode='shine', cast=1)
    cv.set_nrm(p, cv.sphere_n(6.0, 6.0, 8.0, 8.0, k=0.75))
    cv.dot(4.0, 4.6, 'white', 4)
    cv.dot(5.0, 4.0, 'white', 3)
    return render(cv)


def ic_clock():
    cv = icv()
    cv.put(cv.ellipse(7.5, 8.0, 6.6, 6.6), 'dkmetal', mode='shine', cast=1)
    cv.put(cv.ellipse(7.5, 8.0, 5.2, 5.2), 'face', mode='flat')
    for (x, y) in ((7.5, 3.6), (11.9, 8.0), (7.5, 12.4), (3.1, 8.0)):
        cv.dot(x, y, 'hand', 0)
    q = cv.put(cv.line([(7.5, 8.0), (7.5, 4.6)]) | cv.line([(7.5, 8.0), (10.4, 9.6)]), 'hand', mode='flat', outline=False)
    cv.parts[q].keep = True
    return render(cv)


def ic_ledger():
    cv = icv()
    cv.put(cv.poly([(3, 3), (13, 2), (13, 13), (3, 14)]), 'page', mode='flat', iline=True)
    p = cv.put(cv.poly([(2, 2), (12, 1), (12, 13), (2, 14)]), 'cover', mode='cyl', cast=1, iline=True)
    cv.paint(cv.rect(2, 1, 3, 14) & cv.of(p), 'tea', 2)
    cv.paint(cv.poly(star_poly(7.6, 7.2, 2.6, 1.1)), 'gold', 2)
    q = cv.put(cv.rect(9, 13, 10, 15), 'ribbon', mode='flat', iline=True)
    return render(cv)


def ic_pod():
    cv = icv()
    p = cv.put(cv.ellipse(7.5, 8.4, 5.4, 6.6), 'pod', mode='shine', cast=1)
    cv.set_nrm(p, cv.sphere_n(6.0, 6.5, 6.5, 7.5, k=0.85))
    cv.paint(cv.rect(2, 8, 13, 9) & cv.of(p), 'podband', 2)
    cv.dot(10.6, 8.4, 'light', 4)
    return render(cv)


ICONS = {'credits': ic_credits, 'star': ic_star, 'sandtimer': ic_sandtimer, 'wrench': ic_wrench, 'listen': ic_listen,
         'tap': ic_tap, 'scan': ic_scan, 'tea': ic_tea, 'rep': ic_rep, 'clock': ic_clock, 'ledger': ic_ledger, 'pod': ic_pod}


def build_icons(out):
    d = os.path.join(out, 'ui')
    os.makedirs(d, exist_ok=True)
    for name, fn in ICONS.items():
        Image.fromarray(fn(), 'RGBA').save(os.path.join(d, f'icon_{name}.png'))


# ================================================================== indicaciones de botón (glifos) y globo de diálogo

LETTERS = {'A': ["01110", "10001", "10001", "11111", "10001", "10001"],
           'B': ["11110", "10001", "11110", "10001", "10001", "11110"]}


def pad_glyph(letter, face, face_hi, face_lo):
    """Botón redondo del mando (A verde, B rojo) con la letra en crema: 16x16, se muestra a x2 o x3."""
    arr = np.zeros((16, 16, 4), np.uint8)
    ys, xs = np.mgrid[0:16, 0:16]
    d = np.sqrt((xs - 7.5) ** 2 + (ys - 7.5) ** 2)
    paint(arr, d <= 7.6, hexc('#1a1416'))
    paint(arr, d <= 6.6, hexc(face))
    lit = (xs - 7.5) * 0.6 + (ys - 7.5) * 0.8
    paint(arr, (d <= 6.6) & (d > 5.4) & (lit < -1.5), hexc(face_hi))
    paint(arr, (d <= 6.6) & (d > 5.4) & (lit > 2.5), hexc(face_lo))
    for j, row in enumerate(LETTERS[letter]):
        for i, c in enumerate(row):
            if c == '1':
                arr[5 + j, 5 + i] = hexc('#f6eedc')
    return arr


def mouse_glyph():
    """Ratón con el botón izquierdo encendido (clic para caminar / usar)."""
    arr = np.zeros((16, 16, 4), np.uint8)
    m = rrect_mask(10, 14, r=4)
    full = np.zeros((16, 16), bool)
    full[1:15, 3:13] = m
    paint(arr, full, hexc('#1a1416'))
    body = shrink(full)
    paint(arr, body, hexc('#d8d0c0'))
    t, l, b, r = edges(body)
    paint(arr, b | r, hexc('#a89e8c'))
    lb = body & (np.mgrid[0:16, 0:16][0] <= 6) & (np.mgrid[0:16, 0:16][1] <= 7)
    paint(arr, lb, hexc('#eaa23c'))
    arr[2:7, 8] = hexc('#1a1416')
    arr[7, 4:12] = hexc('#1a1416')
    return arr


def key_glyph():
    """Tecla en blanco (16x16) para imprimir encima la letra (E, Enter, Esc...)."""
    return key(16, 16, **KEYS['normal'])


def bubble():
    """Globo de diálogo crema de 9 cortes (x3) y su colita aparte (bubble_tail.png, abajo al centro)."""
    w, h = 20, 16
    arr = np.zeros((h, w, 4), np.uint8)
    m = rrect_mask(w, h, r=4)
    paint(arr, m, hexc('#2a2024'))
    inner = shrink(m)
    paint(arr, inner, hexc('#f4ecd8'))
    t, l, b, r = edges(inner)
    paint(arr, b | r, hexc('#d8ccb0'))
    tail = np.zeros((6, 8, 4), np.uint8)
    rows = ["11111111", "12222221", "01222210", "00122100", "00011000", "00000000"]
    for j, row in enumerate(rows):
        for i, c in enumerate(row):
            if c == '1':
                tail[j, i] = hexc('#2a2024')
            elif c == '2':
                tail[j, i] = hexc('#f4ecd8')
    tail[0, 1:7] = hexc('#f4ecd8')
    return arr, tail


def build_extras(out):
    d = os.path.join(out, 'ui')
    Image.fromarray(pad_glyph('A', '#4caa5a', '#7cd488', '#2e7a3c'), 'RGBA').save(os.path.join(d, 'glyph_pad_a.png'))
    Image.fromarray(pad_glyph('B', '#d04a3e', '#f07a6a', '#9a2e26'), 'RGBA').save(os.path.join(d, 'glyph_pad_b.png'))
    Image.fromarray(mouse_glyph(), 'RGBA').save(os.path.join(d, 'glyph_mouse.png'))
    Image.fromarray(key_glyph(), 'RGBA').save(os.path.join(d, 'glyph_key.png'))
    bb, tl = bubble()
    up(bb).save(os.path.join(d, 'bubble9.png'))
    up(tl).save(os.path.join(d, 'bubble_tail.png'))

if __name__ == '__main__':
    args = sys.argv[1:]
    out = './out'
    if '--out' in args:
        out = args[args.index('--out') + 1]
    spec = build_panels(out)
    build_icons(out)
    build_extras(out)
    spec['glyph_*.png'] = dict(size=16, note='indicaciones: glyph_pad_a (A verde), glyph_pad_b (B rojo), glyph_mouse (clic '
                               'izquierdo), glyph_key (tecla en blanco: imprimir la letra encima, texto #2a2024)')
    spec['bubble9.png'] = dict(margin=6 * S, content=6 * S, tail='bubble_tail.png (24x18, abajo al centro, superponer 3 px)',
                               text='#2a2024')
    spec['icon_*.png'] = dict(size=16, scale='x2 o x3, filtro NEAREST', names=sorted(ICONS))
    with open(os.path.join(out, 'ui', 'ui_kit.json'), 'w') as f:
        json.dump(spec, f, indent=1)
    print('ok ui')
