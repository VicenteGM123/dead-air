"""Ronda de pulido: el arte nuevo de la calle de enfrente (P1).
- street_win_<color>.png: las ventanas de las casas del mercado (props/window_<color>.png) con el cristal recortado
  (transparente). Detrás va un cristal aparte (street_pane.png) que la tienda tiñe según la hora: reflejo frío de día,
  luz cálida de noche (shop_world._street_time).
- street_pane.png: el cristal de detrás (blanco; el color lo pone el modulate), con dos cortinas a los lados.
- glow_soft.png: un halo redondo y suave (blanco que se desvanece), para la farola de la calle y los farolillos de
  luciérnagas (P2). Escalonado en pocos niveles de alfa, como el resto del pixel art.
Uso: python3 <ruta>/polish_art.py <carpeta del juego> <carpeta de salida>
     (lee assets/props/window_*.png del juego; escribe en la salida; se copian a mano a assets/props/)."""
import os, sys
from PIL import Image

GLASS = {(159, 224, 247), (190, 245, 255), (122, 176, 216)}   # los tres azules del cristal de window_*.png


def street_window(src, dst):
    im = Image.open(src).convert('RGBA')
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a and (r, g, b) in GLASS:
                px[x, y] = (0, 0, 0, 0)
    im.save(dst)


def street_pane(dst):
    w, h = 14, 18
    im = Image.new('RGBA', (w, h), (255, 255, 255, 255))
    px = im.load()
    for y in range(h):
        for x in range(w):
            # cortinas: dos franjas algo más oscuras a los lados, recogidas abajo
            side = min(x, w - 1 - x)
            lim = 3 if y < h * 0.55 else 2
            if side < lim:
                px[x, y] = (205, 190, 175, 255)
            elif y < 2:
                px[x, y] = (232, 222, 210, 255)   # la sombra del dintel
    im.save(dst)


def glow_soft(dst, n=32):
    im = Image.new('RGBA', (n, n), (255, 255, 255, 0))
    px = im.load()
    c = (n - 1) / 2.0
    for y in range(n):
        for x in range(n):
            d = (((x - c) ** 2 + (y - c) ** 2) ** 0.5) / (n / 2.0)
            a = max(0.0, 1.0 - d) ** 1.6
            a = round(a * 6) / 6.0          # 6 escalones de alfa
            px[x, y] = (255, 255, 255, int(a * 255))
    im.save(dst)


if __name__ == '__main__':
    game, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    for c in ('green', 'red', 'blue', 'plum'):
        street_window(os.path.join(game, 'assets/props/window_%s.png' % c), os.path.join(out, 'street_win_%s.png' % c))
    street_pane(os.path.join(out, 'street_pane.png'))
    glow_soft(os.path.join(out, 'glow_soft.png'))
    print('ok', out)
