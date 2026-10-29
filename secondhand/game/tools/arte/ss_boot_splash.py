#!/usr/bin/env python3
# --- BOOT: la imagen de arranque de Secondhand Stars (assets/ui/boot_splash.png, 1280x720).
# La usan el HTML de la versión web mientras baja el juego (index.png, «object-fit: contain» sobre el color
# application/boot_splash/bg_color) y la pantalla de arranque de Godot en escritorio. La pantalla de carga del juego
# (scripts/ui/boot_screen.gd) dibuja lo mismo por partes: assets/ui/boot_bg.png (el fondo con las estrellas, sin logo)
# y el logo encima en el mismo sitio (para luego llevarlo volando a su lugar en el título). Así se pasa de la pantalla
# del navegador a la del juego sin salto.
# El borde de la imagen es del color liso BG (si la ventana no es 16:9, el resto se rellena con ese color).
#   cd game && python3 tools/arte/ss_boot_splash.py
import os
import random
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.normpath(os.path.join(HERE, '..', '..'))
W, H = 1280, 720
BG = (28, 20, 38)            # = BootScreen.BG = application/boot_splash/bg_color (#1c1426)
LOGO_POS = (238, 196)        # = BootScreen.LOGO_RECT.position (el logo de 804x261 a escala 1)
# las estrellas: (x, y, tamaño, color) — las mismas que BootScreen.STARS
STAR_COLS = [(255, 236, 200), (255, 214, 150), (214, 206, 255)]


def stars():
    rnd = random.Random(7)
    out = []
    while len(out) < 34:
        x, y = rnd.randrange(24, W - 24), rnd.randrange(20, H - 20)
        # ni sobre el logo ni sobre la barra de progreso (abajo, al 90 % del alto)
        if 200 < x < 1080 and 170 < y < 490:
            continue
        if 280 < x < 1000 and 600 < y < 690:
            continue
        s = 2 if rnd.random() < 0.25 else 1
        out.append((x, y, s, rnd.randrange(len(STAR_COLS))))
    return out


def main():
    img = Image.new('RGBA', (W, H), BG + (255,))
    for x, y, s, c in stars():
        for dx in range(s * 2):
            for dy in range(s * 2):
                img.putpixel((x + dx, y + dy), STAR_COLS[c] + (255,))
    logo = Image.open(os.path.join(GAME, 'assets/ui/logo.png')).convert('RGBA')
    img.alpha_composite(logo, LOGO_POS)
    out = os.path.join(GAME, 'assets/ui/boot_splash.png')
    img.convert('RGB').save(out, optimize=True)
    print(out, os.path.getsize(out), 'bytes')
    bg = Image.new('RGBA', (W, H), BG + (255,))
    for x, y, s, c in stars():
        for dx in range(s * 2):
            for dy in range(s * 2):
                bg.putpixel((x + dx, y + dy), STAR_COLS[c] + (255,))
    out2 = os.path.join(GAME, 'assets/ui/boot_bg.png')
    bg.convert('RGB').save(out2, optimize=True)
    print(out2, os.path.getsize(out2), 'bytes')


if __name__ == '__main__':
    main()
