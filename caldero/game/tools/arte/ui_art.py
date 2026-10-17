import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from pixlib import *
from props import art, pad_to
from PIL import Image
OUT='./salida/ui'
os.makedirs(OUT, exist_ok=True)
CORNER = """
YYYYYYYYYY..
Y...........
Y.YYYYYY....
Y.Y.........
Y.Y..YY.....
Y.Y..Y......
Y.Y.........
Y...........
Y...........
Y...........
.............
.............
"""
c = art(CORNER, {'Y': ('#e2c27a', None, 'flat')}, outline=False)
save(c, f'{OUT}/corner.png')
DIV = """
...............Y................
.YYYYYYYYYYYY.YYY.YYYYYYYYYYYYY.
...............Y................
"""
save(art(DIV, {'Y': ('#e2c27a', None, 'flat')}, outline=False), f'{OUT}/divider.png')
# game icon: cauldron with teal liquid on night background
ic = Image.new('RGBA', (64, 64), (24, 20, 44, 255))
cal = Image.open('./salida/props/cauldron_copper.png')
liq = Image.open('./salida/props/cauldron_liquid.png').convert('RGBA')
import numpy as np
l = np.array(liq).astype(float); l[..., 0] *= 95/255; l[..., 1] *= 224/255; l[..., 2] *= 192/255
liq = Image.fromarray(l.astype('uint8'), 'RGBA')
base = Image.new('RGBA', (40, 28), (0, 0, 0, 0)); base.alpha_composite(liq); base.alpha_composite(cal)
# stars
px = ic.load()
for (x, y) in [(8, 8), (50, 12), (30, 5), (12, 30), (56, 34), (40, 20)]:
    px[x, y] = (255, 240, 200, 255)
ic.alpha_composite(base, (12, 26))
# sparkle above
for (x, y) in [(30, 18), (34, 14), (27, 12)]:
    px[x, y] = (180, 255, 230, 255)
ic = ic.resize((128, 128), Image.NEAREST)
ic.save(f'{OUT}/icon.png')
preview([c, art(DIV, {'Y': ('#e2c27a', None, 'flat')}, outline=False), np.array(ic.resize((64,64), Image.NEAREST))], scale=4, cols=3, path='./prev_ui.png')
print('ok')
