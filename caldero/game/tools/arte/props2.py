"""World props for the 2.5D shop: cauldron, hearth, candles, plants, furniture, particles."""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from pixlib import *
from props import art, pad_to
import numpy as np
from PIL import Image

OUT = './salida/props'
FX = './salida/fx'
os.makedirs(OUT, exist_ok=True); os.makedirs(FX, exist_ok=True)

IRON = {'R': ('#5c5a6e', None, 'top'), 'I': ('#3e3c4e', None), 'L': ('#2e2c3a', None), 'H': ('#6c6a80', None, 'flat')}
COPPER = {'R': ('#e0965a', None, 'top'), 'I': ('#b8643a', None), 'L': ('#6a3a2a', None), 'H': ('#f0b07a', None, 'flat')}

CAULDRON = """
........................................
........RRRRRRRRRRRRRRRRRRRRRRRR........
.....RRRRRRRRRRRRRRRRRRRRRRRRRRRRRR.....
....RRRR........................RRRR....
...RRR............................RRR...
...RRR............................RRR...
....RRRR........................RRRR....
.....RRRRRRRRRRRRRRRRRRRRRRRRRRRRRR.....
....IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII....
.HHIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIHH.
H..IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII..H
H.IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII.H
.HIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIH.
..IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII..
..IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII..
..IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII..
..IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII..
...IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII...
...IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII...
....IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII....
.....IIIIIIIIIIIIIIIIIIIIIIIIIIIIII.....
......IIIIIIIIIIIIIIIIIIIIIIIIIIII......
........IIIIIIIIIIIIIIIIIIIIIIII........
.......LL..IIIIIIIIIIIIIIIIII..LL.......
.......LL......................LL.......
......LLL......................LLL......
"""

LIQUID = """
........LLLLLLLLLLLLLLLLLLLLLLLL........
....LLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLL....
...LLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLL...
...LLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLL...
....LLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLL....
"""

def cauldron(mats, name):
    a = art(CAULDRON, mats)
    a = pad_to(a, 40, 28, 'bottom')
    save(a, f'{OUT}/{name}.png')
    return a

def liquid():
    rows = LIQUID.strip('\n').split('\n')
    img = np.zeros((28, 40, 4), np.uint8)
    # place to match the cauldron interior (rows 3..6 of the 28px canvas after padding: art is 26 rows -> offset 2)
    oy = 2 + 2
    for y, r in enumerate(rows):
        for x, ch in enumerate(r):
            if ch == 'L':
                v = 255 if y < 2 else 225
                if (x + y) % 9 == 0 and y < 3:
                    v = 255
                img[oy + y, x] = (v, v, v, 255)
    # highlight streak
    for x in range(12, 20):
        img[oy + 1, x] = (255, 255, 255, 255)
    save(img, f'{OUT}/cauldron_liquid.png')
    return img

FIRE_FRAMES = [
"""
..........Y.....Y.........
.........YY....YYO........
....O....YOY..YOOY...Y....
...OOY..YOOY..YORY..YO....
...ORO..YORRY.ORRO.YOO....
..ORRO.YORRRYYORRROYORO...
..ORRRROORRRRORRRRRORRO...
.ORRRRRRRRRRRRRRRRRRRRRO..
""",
"""
.....Y.........Y..........
.....YY.......YY.....Y....
....YOY..Y...YOY....YY....
....YOOY.YY..YOOY..YOY....
...YORO.YOY.YORRY..ORO....
..ORRRO.ORO.ORRRO.ORRO....
..ORRRROORRORRRRROORRRO...
.ORRRRRRRRRRRRRRRRRRRRRO..
""",
"""
........Y.........Y.......
...Y....YY.......YY.......
...YY..YOY...Y..YOY..Y....
..YOY..YOOY..YY.YOOY.YY...
..YORO.YORO.YOY.ORRO.YOY..
..ORRO.ORRRYORO.ORRROORO..
..ORRRROORRRRRRORRRRRRRO..
.ORRRRRRRRRRRRRRRRRRRRRRO.
""",
"""
............Y.......Y.....
......Y.....YY.....YY.....
......YY...YOY..Y..YOY....
.....YOY...YOOY.YY.YOOY...
..O..YORO.YORRO.YOY.ORO...
..OO.ORRRYORRRO.ORO.ORRO..
.ORRRORRRRRRRRRORRRRORRO..
.ORRRRRRRRRRRRRRRRRRRRRRO.
""",
]

def fire():
    frames = []
    for f in FIRE_FRAMES:
        rows = f.strip('\n').split('\n')
        img = np.zeros((10, 26, 4), np.uint8)
        cols = {'Y': (255, 236, 150), 'O': (255, 160, 60), 'R': (232, 72, 40)}
        for y, r in enumerate(rows):
            for x, ch in enumerate(r):
                if ch in cols:
                    img[2 + y, x, :3] = cols[ch]; img[2 + y, x, 3] = 255
        frames.append(img)
    save(hstack(frames), f'{OUT}/fire.png')
    return frames

HEARTH = """
..SSSS..SSSSS..SSSSS..SSSSS..SSSSS..SSSS..
.SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSS.
SSSSSSSsSSSSSSsSSSSSSSsSSSSSSsSSSSSSSsSSSS
SSSSSSSsSSSSSSsSSSSSSSsSSSSSSsSSSSSSSsSSSS
.SSSSSSsSSSSSSsSSSSSSSsSSSSSSsSSSSSSSsSSS.
"""
LOGS = """
....WWWWWWWWWWWWWWWWWW....
..WWWWWWWWWWWWWWWWWWWWWW..
.wwwwwwwwwwwwwwwwwwwwwwww.
"""

CANDLE = """
.WW.
.WW.
.WW.
.WW.
.WW.
.WW.
WWWW
HHHH
"""
FLAME_FRAMES = [
"""
..Y..
.YY..
.YOY.
YOOY.
.YOY.
""",
"""
..Y..
..YY.
.YOY.
.YOOY
.YOY.
""",
"""
.Y...
.YY..
.YOY.
YOOOY
.YOY.
""",
]

def flames():
    frames = []
    for f in FLAME_FRAMES:
        rows = f.strip('\n').split('\n')
        img = np.zeros((6, 5, 4), np.uint8)
        cols = {'Y': (255, 240, 170), 'O': (255, 170, 70)}
        for y, r in enumerate(rows):
            for x, ch in enumerate(r):
                if ch in cols:
                    img[y, x, :3] = cols[ch]; img[y, x, 3] = 255
        frames.append(img)
    save(hstack(frames), f'{OUT}/flame.png')

FERN = """
..........V...........V.......
.........VV..V.......VV.......
....V...VVV.VV..V...VVV...V...
...VV..VVV.VVV.VV..VVV...VV...
..VVV.VVV..VVVVV..VVV...VVV...
..VVVVVV..VVVVV..VVVV..VVV....
...VVVVVVVVVVVVVVVVVVVVVVV.V..
.V..VVVVVVVVVVVVVVVVVVVVVVVV..
.VV..VVVVVVVVVVVVVVVVVVVVVV...
.VVVVVVVVVVVVVVVVVVVVVVVVVVVV.
..VVVVVVVVVVVVVVVVVVVVVVVVVV..
...VVVVVVVVVVVVVVVVVVVVVVVV...
....VVVVVVVVVVVVVVVVVVVVVV....
......PPPPPPPPPPPPPPPPPP......
.....PPPPPPPPPPPPPPPPPPPP.....
......PPPPPPPPPPPPPPPPPP......
......PPPPPPPPPPPPPPPPPP......
.......PPPPPPPPPPPPPPPP.......
.......PPPPPPPPPPPPPPPP.......
........PPPPPPPPPPPPPP........
"""
SMALL_POT = """
....FF.FF.
...FFFFFFF
..FFFFFFF.
...VVFVV..
..VVVVVVV.
...VVVVV..
..PPPPPPP.
...PPPPP..
...PPPPP..
....PPP...
"""
HERBS = """
......S.......
......S.......
......S.......
.....TTT......
....GGGGG.....
...GGGGGGG....
..GGgGGGgGG...
..GGGGgGGGG...
.GGgGGGGGgGG..
.GGGGGGgGGGG..
.GgGGgGGGGgG..
.GGGGGGGgGG...
..GgGGGGGGG...
..GGGGgGGG....
...GgGGGG.....
...GGGGg......
....GG........
"""
LAVENDER = HERBS.replace('G', 'L').replace('g', 'l')
BOOKS = """
....AAAAAAAAAAAA..
....AAAAAAAAAAAAa.
..BBBBBBBBBBBBB...
..BBBBBBBBBBBBBb..
...CCCCCCCCCCCCC..
...CCCCCCCCCCCCCc.
.DDDDDDDDDDDDDD...
.DDDDDDDDDDDDDDd..
"""
OPEN_BOOK = """
..PPPPPPPP..PPPPPPPP..
.PPPpppPPPPPPpppPPPPP.
.PPPPPPPPPPPPPPPPPPPP.
.PPpppppPPPPPpppppPPP.
.PPPPPPPPPPPPPPPPPPPP.
.PPppppPPPPPPPpppPPPP.
.PPPPPPPPPPPPPPPPPPPP.
BBBBBBBBBBBBBBBBBBBBBB
.BBBBBBBBBBBBBBBBBBBB.
"""
BARREL = """
....WWWWWWWWWWWWWW....
..WWWWWWWWWWWWWWWWWW..
.WWWWWWWWWWWWWWWWWWWW.
.IIIIIIIIIIIIIIIIIIII.
WWWWWWWWWWWWWWWWWWWWWW
WWWWWWWWWWWWWWWWWWWWWW
WWWWWWWWWWWWWWWWWWWWWW
WWWWWWWWWWWWWWWWWWWWWW
IIIIIIIIIIIIIIIIIIIIII
WWWWWWWWWWWWWWWWWWWWWW
WWWWWWWWWWWWWWWWWWWWWW
WWWWWWWWWWWWWWWWWWWWWW
WWWWWWWWWWWWWWWWWWWWWW
WWWWWWWWWWWWWWWWWWWWWW
IIIIIIIIIIIIIIIIIIIIII
.WWWWWWWWWWWWWWWWWWWW.
.WWWWWWWWWWWWWWWWWWWW.
..WWWWWWWWWWWWWWWWWW..
.IIIIIIIIIIIIIIIIIIII.
..WWWWWWWWWWWWWWWWWW..
"""
CRATE = """
WWWWWWWWWWWWWWWWWWWW
WwwwwwwwwwwwwwwwwwwW
WwWWWWWWWWWWWWWWWWwW
WwWWwWWWWWWWWWWwWWwW
WwWWWWwWWWWWWwWWWWwW
WwWWWWWWwWWwWWWWWWwW
WwWWWWWWWwwWWWWWWWwW
WwWWWWWWwWWwWWWWWWwW
WwWWWWwWWWWWWwWWWWwW
WwWWwWWWWWWWWWWwWWwW
WwWWWWWWWWWWWWWWWWwW
WwwwwwwwwwwwwwwwwwwW
WWWWWWWWWWWWWWWWWWWW
"""
SACK = """
.....TT.......
....SSSS......
...SSSSSS.....
..SSSSSSSS....
.SSSSSSSSSS...
.SSSSSSSSSSS..
SSSSSSSSSSSSS.
SSSSSFFSSSSSS.
SSSSFFFFSSSSS.
SSSSSFFSSSSSS.
SSSSSSSSSSSSS.
.SSSSSSSSSSS..
"""
LANTERN = """
....HH....
...H..H...
..MMMMMM..
.MGGGGGGM.
.MGYYYYGM.
.MGYOOYGM.
.MGYOOYGM.
.MGYYYYGM.
.MGGGGGGM.
..MMMMMM..
...MMMM...
"""
FIREFLY_JAR = """
...CCCC...
...CCCC...
..GGGGGG..
.GxxxxxxG.
.GxyxxxxG.
.GxxxxyxG.
.GxxyxxxG.
.GxxxxxxG.
.GyxxxyxG.
..GGGGGG..
"""
BELL = """
....SS....
...SSSS...
..BBBBBB..
..BBBBBB..
.BBBBBBBB.
.BBBBBBBB.
BBBBBBBBBB
....BB....
"""
MORTAR = """
..........PP..
.........PP...
........PP....
.MMMMMMMMMMMM.
MMMMMMMMMMMMMM
.MMMMMMMMMMMM.
..MMMMMMMMMM..
...MMMMMMMM...
....MMMMMM....
"""
CRYSTAL_BALL = """
....GGGGGG....
..GGGGGGGGGG..
.GGwGGGGGGGGG.
.GwGGGGGGgGGG.
GGGGGGGggGGGGG
GGGGGGGgGGGGGG
.GGGGGGGGGGGG.
.GGGGGGGGGGGG.
..GGGGGGGGGG..
...BBBBBBBB...
..BBBBBBBBBB..
"""
SCROLLS = """
..PPPPPPPPPPPP..
.PPPPPPPPPPPPPP.
PPPPPPPPPPPPPPPP
.RRPPPPPPPPPPRR.
..PPPPPPPPPPPP..
....PPPPPPPPPPPP
...PPPPPPPPPPPP.
"""
BOTTLE_SM = """
..CC..
..GG..
.GLLG.
GLLLLG
GhLLLG
GLLLLG
GLLLLG
.GGGG.
"""

def small_bottles():
    out = []
    for col in ('#ff7d4d', '#5fe0c0', '#9a6ae8', '#ffbf2e', '#6a7cff', '#9ae04a'):
        a = art(BOTTLE_SM, {'G': ('#d9eef5', None, 'flat'), 'L': (col, None), 'h': ('#ffffff', None, 'flat'), 'C': ('#a8774a', None)})
        out.append(a)
    return out

def particles():
    # dust mote 4x4 soft
    d = np.zeros((4, 4, 4), np.uint8)
    for (x, y, a) in [(1, 1, 255), (2, 1, 200), (1, 2, 200), (2, 2, 255), (0, 1, 80), (3, 2, 80), (1, 0, 80), (2, 3, 80)]:
        d[y, x] = (255, 244, 220, a)
    save(d, f'{FX}/dust.png')
    # sparkle 7x7
    s = np.zeros((7, 7, 4), np.uint8)
    for i in range(7):
        a = 255 if i == 3 else (180 if i in (2, 4) else 90)
        s[3, i] = (255, 255, 230, a); s[i, 3] = (255, 255, 230, a)
    save(s, f'{FX}/sparkle.png')
    # bubble 6x6 ring
    b = np.zeros((6, 6, 4), np.uint8)
    for (x, y) in [(2, 0), (3, 0), (1, 1), (4, 1), (0, 2), (5, 2), (0, 3), (5, 3), (1, 4), (4, 4), (2, 5), (3, 5)]:
        b[y, x] = (255, 255, 255, 230)
    b[1, 2] = (255, 255, 255, 255); b[2, 1] = (255, 255, 255, 160)
    for y in range(1, 5):
        for x in range(1, 5):
            if b[y, x, 3] == 0:
                b[y, x] = (255, 255, 255, 60)
    save(b, f'{FX}/bubble.png')
    # smoke puff 16x16 (posterized)
    sm = np.zeros((16, 16, 4), np.uint8)
    for y in range(16):
        for x in range(16):
            dx, dy = (x - 7.5) / 7.5, (y - 7.5) / 7.5
            r = dx * dx + dy * dy
            if r < 1:
                a = int((1 - r) * 200)
                a = (a // 60) * 60
                sm[y, x] = (240, 236, 250, a)
    save(sm, f'{FX}/smoke.png')
    # firefly 5x5
    f = np.zeros((5, 5, 4), np.uint8)
    for (x, y, a) in [(2, 2, 255), (1, 2, 160), (3, 2, 160), (2, 1, 160), (2, 3, 160), (1, 1, 60), (3, 3, 60), (1, 3, 60), (3, 1, 60)]:
        f[y, x] = (230, 255, 140, a)
    save(f, f'{FX}/firefly.png')
    # ember 3x3
    e = np.zeros((3, 3, 4), np.uint8)
    e[1, 1] = (255, 220, 120, 255); e[0, 1] = e[1, 0] = e[2, 1] = e[1, 2] = (255, 140, 60, 160)
    save(e, f'{FX}/ember.png')
    # heart small 7x6
    h = np.zeros((6, 7, 4), np.uint8)
    for (x, y) in [(1, 0), (2, 0), (4, 0), (5, 0), (0, 1), (1, 1), (2, 1), (3, 1), (4, 1), (5, 1), (6, 1), (0, 2), (1, 2), (2, 2), (3, 2), (4, 2), (5, 2), (6, 2), (1, 3), (2, 3), (3, 3), (4, 3), (5, 3), (2, 4), (3, 4), (4, 4), (3, 5)]:
        h[y, x] = (255, 110, 140, 255)
    h[1, 1] = (255, 220, 230, 255)
    save(h, f'{FX}/heart.png')
    # soft radial glow 32x32 (for fake light halos)
    g = np.zeros((32, 32, 4), np.uint8)
    for y in range(32):
        for x in range(32):
            dx, dy = (x - 15.5) / 15.5, (y - 15.5) / 15.5
            r = (dx * dx + dy * dy) ** 0.5
            if r < 1:
                a = int((1 - r) ** 2 * 255)
                g[y, x] = (255, 255, 255, a)
    save(g, f'{FX}/glow.png')

if __name__ == '__main__':
    a = cauldron(IRON, 'cauldron_iron')
    b = cauldron(COPPER, 'cauldron_copper')
    liq = liquid()
    fr = fire()
    flames()
    hearth = art(HEARTH, {'S': ('#7a7486', None, 'top'), 's': ('#4a4656', None, 'flat')})
    save(hearth, f'{OUT}/hearth.png')
    logs = art(LOGS, {'W': ('#6a4430', None, 'top'), 'w': ('#3a2420', None, 'flat')})
    save(logs, f'{OUT}/logs.png')
    candle = art(CANDLE, {'W': ('#efe6cf', None), 'H': ('#b08a4a', None, 'top')})
    save(candle, f'{OUT}/candle.png')
    items = {
        'fern': art(FERN, {'V': ('#4f9a4a', None, 'top'), 'P': ('#b5603a', None, 'top')}),
        'pot_red': art(SMALL_POT, {'F': ('#ff6a6a', None, 'top'), 'V': ('#5aa84a', None), 'P': ('#b5603a', None, 'top')}),
        'pot_blue': art(SMALL_POT, {'F': ('#7a9aff', None, 'top'), 'V': ('#5aa84a', None), 'P': ('#a35a3a', None, 'top')}),
        'pot_yellow': art(SMALL_POT, {'F': ('#ffd84d', None, 'top'), 'V': ('#5aa84a', None), 'P': ('#b5703a', None, 'top')}),
        'herbs': art(HERBS, {'S': ('#d8c8a0', None, 'flat'), 'T': ('#c94a3a', None), 'G': ('#7a9a4a', None), 'g': ('#a8a050', None, 'flat')}),
        'lavender': art(LAVENDER, {'S': ('#d8c8a0', None, 'flat'), 'T': ('#c94a3a', None), 'L': ('#9a7ad0', None), 'l': ('#c8b0f0', None, 'flat')}),
        'books': art(BOOKS, {'A': ('#3a6a9a', None, 'top'), 'a': ('#e8dcc0', None, 'flat'), 'B': ('#9a3a3a', None, 'top'), 'b': ('#e8dcc0', None, 'flat'),
                              'C': ('#4a7a4a', None, 'top'), 'c': ('#e8dcc0', None, 'flat'), 'D': ('#7a4a8a', None, 'top'), 'd': ('#e8dcc0', None, 'flat')}),
        'open_book': art(OPEN_BOOK, {'P': ('#f0e6cc', None), 'p': ('#8a7a6a', None, 'flat'), 'B': ('#7a3a2a', None)}),
        'barrel': art(BARREL, {'W': ('#8a5a3a', None), 'I': ('#5a5868', None, 'top')}),
        'crate': art(CRATE, {'W': ('#9a6a42', None), 'w': ('#6a4428', None, 'flat')}),
        'sack': art(SACK, {'S': ('#d8c8a4', None), 'T': ('#a8784a', None), 'F': ('#b0a080', None, 'flat')}),
        'lantern': art(LANTERN, {'H': ('#4a4656', None), 'M': ('#5a5668', None, 'top'), 'G': ('#ffd88a', None, 'flat'), 'Y': ('#ffe9a8', None, 'flat'), 'O': ('#fff8e0', None, 'flat')}),
        'firefly_jar': art(FIREFLY_JAR, {'C': ('#a8774a', None), 'G': ('#cfe6ee', None, 'flat'), 'x': ('#2a3a3a', None, 'flat'), 'y': ('#e6ff8a', None, 'flat')}),
        'bell': art(BELL, {'S': ('#7a6a5a', None), 'B': ('#f0c050', None, 'shine')}),
        'mortar': art(MORTAR, {'M': ('#9a96a8', None, 'top'), 'P': ('#c8b8a0', None)}),
        'crystal_ball': art(CRYSTAL_BALL, {'G': ('#9fd8ff', None, 'flat'), 'w': ('#ffffff', None, 'flat'), 'g': ('#d0a8ff', None, 'flat'), 'B': ('#7a5a3a', None, 'top')}),
        'scrolls': art(SCROLLS, {'P': ('#ecdcb4', None, 'top'), 'R': ('#c84a3a', None, 'flat')}),
    }
    for k, v in items.items():
        save(v, f'{OUT}/{k}.png')
    sb = small_bottles()
    for i, v in enumerate(sb):
        save(v, f'{OUT}/bottle_sm_{i}.png')
    particles()
    # preview composite of cauldron + liquid
    comp = a.copy()
    tint = np.array([95, 224, 192])
    l2 = liq.copy().astype(np.float32)
    l2[..., :3] = l2[..., :3] / 255 * tint
    for y in range(28):
        for x in range(40):
            if comp[y, x, 3] == 0 and l2[y, x, 3] > 0:
                comp[y, x] = l2[y, x].astype(np.uint8)
    hearth_p = pad_to(hearth, 44, 8)
    preview([comp, b, hearth_p] + fr + [candle] + list(items.values()) + sb, scale=5, cols=7, path='./prev_props.png')
    print('ok')
