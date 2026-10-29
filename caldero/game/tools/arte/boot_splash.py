#!/usr/bin/env python3
# --- BOOT: la imagen de arranque (application/boot_splash/image) y de la pantalla de carga (scripts/boot_screen.gd).
# 1920x1080, fondo liso del color de project.godot (application/boot_splash/bg_color = environment default_clear_color,
# #0d0a17): el emblema de la tienda al centro con un halo suave, «Midnight Cauldron» en Alegreya SC Bold (las mismas
# letras y colores que la pantalla de título) y «a little potion shop» a mano (Caveat). Abajo queda libre la franja de
# la barra de progreso (la dibujan la página web y boot_screen.gd, en el 90 % del alto).
#
#   python3 tools/arte/boot_splash.py            (desde game/: escribe assets/ui/boot_splash.png)
import os
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.normpath(os.path.join(HERE, '..', '..'))
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(GAME, 'assets', 'ui', 'boot_splash.png')
W, H = 1920, 1080
BG = (13, 10, 23)                 # Color(0.05, 0.04, 0.09)
GOLD = (255, 219, 128)            # UIKit.GOLD_BRIGHT
LAVENDER = (209, 199, 255)        # el «Cauldron» del título
PAPER = (234, 219, 184)           # eadbb8
SC_BOLD = os.path.join(GAME, 'assets', 'fonts', 'AlegreyaSC-Bold.ttf')
HAND = os.path.join(GAME, 'assets', 'fonts', 'Caveat-VariableFont_wght.ttf')

img = Image.new('RGB', (W, H), BG)

# halo cálido detrás del emblema (muy suave: en negro casi no se nota, pero quita lo plano)
glow = Image.new('L', (W, H), 0)
gd = ImageDraw.Draw(glow)
cx, cy = W // 2, 330
for r, a in ((330, 26), (240, 34), (160, 40)):
    gd.ellipse((cx - r, cy - r, cx + r, cy + r), fill=a)
glow = glow.filter(ImageFilter.GaussianBlur(90))
warm = Image.new('RGB', (W, H), (120, 70, 40))
img = Image.composite(warm, img, glow)

# el emblema (pixel art 26x25) a 9x, sin suavizar
em = Image.open(os.path.join(GAME, 'assets', 'ui', 'paper_emblem.png')).convert('RGBA')
k = 9
em = em.resize((em.width * k, em.height * k), Image.NEAREST)
shadow = Image.new('RGBA', em.size, (0, 0, 0, 0))
shadow.putalpha(em.getchannel('A').point(lambda v: 150 if v > 0 else 0))
ex, ey = cx - em.width // 2, cy - em.height // 2
img.paste((0, 0, 0), (ex + 8, ey + 10), shadow)
img.paste(em, (ex, ey), em)

d = ImageDraw.Draw(img)


def centered(text_parts, font, y, shadow_off=5):
    """Una línea centrada hecha de trozos (texto, color), con sombra."""
    widths = [d.textlength(t, font=font) for t, _ in text_parts]
    x = (W - sum(widths)) / 2
    for (t, col), w in zip(text_parts, widths):
        d.text((x + shadow_off, y + shadow_off), t, font=font, fill=(4, 2, 8))
        d.text((x, y), t, font=font, fill=col)
        x += w


title = ImageFont.truetype(SC_BOLD, 132)
centered([('Midnight ', GOLD), ('Cauldron', LAVENDER)], title, 520)
hand = ImageFont.truetype(HAND, 60)
try:
    hand.set_variation_by_axes([600])   # Caveat seminegrita, como PaperKit.font_hand
except Exception:
    pass
centered([('a little potion shop', PAPER)], hand, 690, 3)

os.makedirs(os.path.dirname(OUT), exist_ok=True)
img.save(OUT, optimize=True)
print('boot_splash ->', OUT, img.size)
