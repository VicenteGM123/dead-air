"""Procedural pixel textures (+ normal maps) for the shop diorama. 32 px per world unit."""
import sys, os, random, math
sys.path.insert(0, os.path.dirname(__file__))
from pixlib import *
import numpy as np
from PIL import Image

OUT = './salida/tex'
os.makedirs(OUT, exist_ok=True)
rng = random.Random(7)
nrng = np.random.default_rng(7)

def quant(c):
    return tuple(int(max(0, min(255, v))) for v in c)

def normal_from_height(hm, strength=2.0):
    h, w = hm.shape
    # wrap-around sobel so textures tile
    dx = (np.roll(hm, -1, 1) - np.roll(hm, 1, 1)) * 0.5
    dy = (np.roll(hm, -1, 0) - np.roll(hm, 1, 0)) * 0.5
    nx = -dx * strength
    ny = dy * strength          # OpenGL-style (+Y up)
    nz = np.ones_like(hm)
    l = np.sqrt(nx * nx + ny * ny + nz * nz)
    n = np.stack([nx / l, ny / l, nz / l], -1)
    img = ((n * 0.5 + 0.5) * 255).astype(np.uint8)
    return img

def save_rgb(arr, name):
    Image.fromarray(arr.astype(np.uint8), 'RGB' if arr.shape[2] == 3 else 'RGBA').save(f'{OUT}/{name}.png')

def wood_palette(base):
    r = ramp(base)
    return r

# ------------------------------------------------------------------ floor planks 64x64
def floor_planks():
    W, H = 64, 64
    col = np.zeros((H, W, 3), np.float32)
    hm = np.zeros((H, W), np.float32)
    bases = ['#8a5a3a', '#7d5236', '#946240', '#83563a', '#8f5d3b']
    ph = 8
    for row in range(H // ph):
        y0 = row * ph
        x = -rng.randint(0, 40)
        while x < W:
            ln = rng.randint(22, 44)
            base = rng.choice(bases)
            rp = ramp(base)
            for yy in range(y0, y0 + ph):
                for xx in range(x, x + ln):
                    X = xx % W
                    t = yy - y0
                    c = np.array(rp[2], np.float32)
                    if t == 0:
                        c = np.array(rp[3], np.float32)
                    elif t == ph - 1:
                        c = np.array(rp[0], np.float32) * 0.85
                    elif t == ph - 2:
                        c = np.array(rp[1], np.float32)
                    col[yy, X] = c
                    hm[yy, X] = 1.0 if 0 < t < ph - 1 else (0.6 if t == 0 else 0.0)
            # grain lines
            for _ in range(rng.randint(1, 3)):
                gy = y0 + rng.randint(2, ph - 3)
                gx = x + rng.randint(2, max(3, ln - 12))
                gl = rng.randint(5, 14)
                for xx in range(gx, min(x + ln - 1, gx + gl)):
                    col[gy, xx % W] = np.array(rp[1], np.float32)
                    hm[gy, xx % W] = 0.85
            # knot
            if rng.random() < 0.35:
                kx = (x + rng.randint(4, max(5, ln - 5))) % W
                ky = y0 + rng.randint(2, ph - 3)
                col[ky, kx] = np.array(rp[0], np.float32)
                col[ky, (kx + 1) % W] = np.array(rp[1], np.float32)
                hm[ky, kx] = 0.7
            # seam (end of plank)
            for yy in range(y0, y0 + ph - 1):
                col[yy, (x + ln - 1) % W] = np.array(rp[0], np.float32)
                hm[yy, (x + ln - 1) % W] = 0.0
            # nail heads
            for yy in (y0 + 2, y0 + ph - 3):
                col[yy, (x + 2) % W] = np.array([60, 48, 50], np.float32)
            x += ln
    save_rgb(col, 'floor')
    save_rgb(normal_from_height(hm, 1.6), 'floor_n')

# ------------------------------------------------------------------ plaster wall 64x64
def plaster():
    W, H = 128, 128
    rp = ramp('#c4b8a8')
    col = np.zeros((H, W, 3), np.float32)
    hm = np.zeros((H, W), np.float32)
    noise = nrng.random((H // 8 + 1, W // 8 + 1))
    for y in range(H):
        for x in range(W):
            n = noise[y // 8, x // 8] * 0.5 + nrng.random() * 0.5
            if n < 0.08:
                c = rp[1]; hm[y, x] = 0.3
            elif n > 0.95:
                c = rp[3]; hm[y, x] = 0.8
            else:
                c = rp[2]; hm[y, x] = 0.55
            col[y, x] = c
    # large soft stains for variation
    for (cx, cy, r) in [(30, 90, 18), (100, 30, 14)]:
        for y in range(cy - r, cy + r):
            for x in range(cx - r, cx + r):
                if (x - cx) ** 2 + (y - cy) ** 2 < r * r and nrng.random() < 0.55:
                    col[y % H, x % W] = col[y % H, x % W] * 0.94
    # one patch of exposed bricks
    brick = ramp('#a86a52')
    bx, by = 76, 84
    for j in range(3):
        for i in range(3 - (j == 2)):
            x0, y0 = bx + i * 7 + (j % 2) * 3, by + j * 4
            for yy in range(y0, y0 + 3):
                for xx in range(x0, x0 + 6):
                    col[yy % H, xx % W] = brick[2 if yy > y0 else 3]
                    hm[yy % H, xx % W] = 0.9
            for yy in range(y0, y0 + 4):
                col[yy % H, (x0 + 6) % W] = brick[0]
            for xx in range(x0, x0 + 7):
                col[(y0 + 3) % H, xx % W] = rp[1]
                hm[(y0 + 3) % H, xx % W] = 0.2
    cx, cy = 20, 20
    for i in range(14):
        cx += rng.choice([-1, 0, 1]); cy += 1
        col[cy % H, cx % W] = rp[0]; hm[cy % H, cx % W] = 0.0
    save_rgb(col, 'plaster')
    save_rgb(normal_from_height(hm, 2.2), 'plaster_n')

# ------------------------------------------------------------------ stone wainscot 64x32
def stones():
    W, H = 64, 32
    col = np.zeros((H, W, 3), np.float32)
    hm = np.zeros((H, W), np.float32)
    mortar = ramp('#5a5060')
    col[:, :] = mortar[1]
    hm[:, :] = 0.0
    bases = ['#8a8a9a', '#7d7a8c', '#958f98', '#8c8070', '#7a8590']
    rows = [(0, 10), (10, 11), (21, 11)]
    for ri, (y0, rh) in enumerate(rows):
        x = -(ri * 9) % 64 - 20
        while x < W + 20:
            sw = rng.randint(11, 18)
            rp = ramp(rng.choice(bases))
            for yy in range(y0, y0 + rh - 1):
                for xx in range(x, x + sw - 1):
                    # rounded corners
                    if (yy in (y0, y0 + rh - 2)) and (xx in (x, x + sw - 2)):
                        continue
                    X = xx % W
                    t = (yy - y0) / rh
                    c = rp[2]
                    if yy == y0 or xx == x:
                        c = rp[3]
                    if yy == y0 + rh - 2 or xx == x + sw - 2:
                        c = rp[1]
                    if nrng.random() < 0.08:
                        c = rp[1]
                    col[yy % H, X] = c
                    hm[yy % H, X] = 1.0 - 0.3 * abs(t - 0.5)
            x += sw
    save_rgb(col, 'stone')
    save_rgb(normal_from_height(hm, 2.5), 'stone_n')

# ------------------------------------------------------------------ dark wood (beams, shelves, counter) 32x32
def wood(name, base, grain='#000000', vertical=False):
    W, H = 32, 32
    rp = ramp(base)
    col = np.zeros((H, W, 3), np.float32)
    hm = np.zeros((H, W), np.float32)
    col[:, :] = rp[2]
    hm[:, :] = 0.6
    for i in range(14):
        gy = rng.randint(0, H - 1)
        gx = rng.randint(0, W - 1)
        gl = rng.randint(6, 20)
        shade = rng.choice([1, 1, 3])
        for xx in range(gx, gx + gl):
            col[gy, xx % W] = rp[shade]
            hm[gy, xx % W] = 0.4 if shade == 1 else 0.75
            if rng.random() < 0.2:
                gy = (gy + rng.choice([-1, 1])) % H
    for _ in range(2):
        kx, ky = rng.randint(2, 29), rng.randint(2, 29)
        col[ky, kx] = rp[0]; col[ky, kx + 1] = rp[1]; col[ky + 1, kx] = rp[1]
    if vertical:
        col = np.transpose(col, (1, 0, 2)).copy()
        hm = hm.T.copy()
    save_rgb(col, name)
    save_rgb(normal_from_height(hm, 1.5), name + '_n')

# ------------------------------------------------------------------ counter front 64x32 (raised panels)
def counter_front():
    W, H = 64, 32
    rp = ramp('#7a4a2e')
    col = np.zeros((H, W, 3), np.float32)
    hm = np.zeros((H, W), np.float32)
    col[:, :] = rp[2]; hm[:, :] = 0.5
    for px in (3, 35):
        x0, x1, y0, y1 = px, px + 26, 4, 27
        for y in range(y0, y1):
            for x in range(x0, x1):
                c = rp[2]
                if y == y0 or x == x0:
                    c = rp[0]
                elif y == y1 - 1 or x == x1 - 1:
                    c = rp[4]
                elif y == y0 + 1 or x == x0 + 1:
                    c = rp[1]
                elif y in (y0 + 3, y0 + 4) or x in (x0 + 3, x0 + 4):
                    c = rp[3]
                col[y, x] = c
                hm[y, x] = 0.2 if (y == y0 or x == x0) else (0.9 if (y0 + 3 <= y < y1 - 2 and x0 + 3 <= x < x1 - 2) else 0.5)
    for y in range(H):
        col[y, 0] = rp[1]; col[y, 33] = rp[1]
    col[0, :] = rp[3]; col[H - 1, :] = rp[0]
    save_rgb(col, 'counter_front')
    save_rgb(normal_from_height(hm, 2.0), 'counter_front_n')

# ------------------------------------------------------------------ door 40x80
def door():
    W, H = 40, 80
    col = np.zeros((H, W, 4), np.float32)
    hm = np.zeros((H, W), np.float32)
    rp = ramp('#6e4a32')
    pw = 8
    for i in range(W // pw):
        prp = ramp(['#6e4a32', '#74503a', '#684430'][i % 3])
        for y in range(H):
            for x in range(i * pw, (i + 1) * pw):
                c = prp[2]
                if x == i * pw:
                    c = prp[0]
                elif x == i * pw + 1:
                    c = prp[3]
                elif x == (i + 1) * pw - 1:
                    c = prp[1]
                if rng.random() < 0.04:
                    c = prp[1]
                col[y, x, :3] = c; col[y, x, 3] = 255
                hm[y, x] = 0.2 if x == i * pw else 0.7
    iron = ramp('#4a4652')
    for by in (12, 64):
        for y in range(by, by + 5):
            for x in range(0, W - 4):
                col[y, x, :3] = iron[3] if y == by else (iron[1] if y == by + 4 else iron[2])
                hm[y, x] = 1.0
        for x in range(4, W - 6, 9):
            col[by + 2, x, :3] = iron[4]
    # handle ring
    for (x, y) in [(31, 40), (32, 40), (33, 41), (33, 42), (32, 43), (31, 43), (30, 42), (30, 41)]:
        col[y, x, :3] = (220, 180, 90)
        hm[y, x] = 1.0
    # small window in door
    for y in range(22, 34):
        for x in range(14, 26):
            edge = y in (22, 33) or x in (14, 25)
            col[y, x, :3] = rp[0] if edge else (255, 214, 140)
            hm[y, x] = 0.1 if not edge else 0.6
    for y in range(22, 34):
        col[y, 19, :3] = rp[0]; col[y, 20, :3] = rp[0]
    for x in range(14, 26):
        col[27, x, :3] = rp[0]
    save_rgb(col, 'door')
    save_rgb(normal_from_height(hm, 2.0), 'door_n')

# ------------------------------------------------------------------ rug 64x96 (RGBA)
def rug():
    W, H = 64, 96
    col = np.zeros((H, W, 4), np.uint8)
    red = ramp('#a33a3e'); gold = ramp('#e0b052'); blue = ramp('#2c4a7a'); cream = ramp('#efe0c0')
    for y in range(H):
        for x in range(W):
            dx, dy = min(x, W - 1 - x), min(y, H - 1 - y)
            d = min(dx, dy)
            if d == 0:
                c = red[0]
            elif d in (1, 2):
                c = red[2]
            elif d == 3:
                c = gold[2]
            elif d in (4, 5, 6, 7):
                c = blue[2] if ((x + y) // 3) % 2 else blue[1]
            elif d == 8:
                c = gold[2]
            else:
                c = red[2] if (x // 2 + y // 2) % 7 else red[1]
                # central medallion
                cx, cy = x - W / 2 + 0.5, y - H / 2 + 0.5
                r = abs(cx) / 18 + abs(cy) / 26
                if r < 1.0:
                    c = cream[2] if r < 0.55 else (gold[2] if r < 0.68 else blue[2])
                    if r < 0.25:
                        c = red[3]
            col[y, x, :3] = c
            col[y, x, 3] = 255
    # fringe
    for x in range(1, W - 1, 2):
        for y in (0, H - 1):
            col[y, x, :3] = cream[2]
    Image.fromarray(col, 'RGBA').save(f'{OUT}/rug.png')

# ------------------------------------------------------------------ hills/trees silhouette for the window backdrop 256x96 RGBA
def backdrop():
    W, H = 256, 96
    img = np.zeros((H, W, 4), np.uint8)
    far = ramp('#4a5a8a'); mid = ramp('#36507a'); near = ramp('#2a3f5a')
    # far mountains
    for x in range(W):
        h1 = 40 + 14 * math.sin(x / 23.0) + 8 * math.sin(x / 9.0 + 1.3)
        for y in range(int(h1), H):
            img[y, x, :3] = far[2] if y > h1 + 1 else far[3]
            img[y, x, 3] = 255
    # snow caps
    for x in range(W):
        h1 = 40 + 14 * math.sin(x / 23.0) + 8 * math.sin(x / 9.0 + 1.3)
        if h1 < 34:
            for y in range(int(h1), int(h1) + 3):
                img[y, x, :3] = (220, 230, 245)
    # mid hills
    for x in range(W):
        h2 = 62 + 8 * math.sin(x / 31.0 + 2.0) + 3 * math.sin(x / 7.0)
        for y in range(int(h2), H):
            img[y, x, :3] = mid[2] if y > h2 + 1 else mid[3]
    # pine trees
    rr = random.Random(3)
    for i in range(30):
        tx = rr.randint(0, W - 1)
        base = 70 + rr.randint(0, 12)
        th = rr.randint(10, 20)
        for k in range(th):
            half = max(0, int((k / th) * 4.5))
            y = base - th + k
            for x in range(tx - half, tx + half + 1):
                img[y, x % W, :3] = near[2] if x < tx else near[1]
                img[y, x % W, 3] = 255
    # near ground
    for x in range(W):
        h3 = 84 + 3 * math.sin(x / 13.0)
        for y in range(int(h3), H):
            img[y, x, :3] = near[1]
            img[y, x, 3] = 255
    # tiny village lights / house
    for (hx, hy) in [(60, 74), (170, 78)]:
        for y in range(hy, hy + 6):
            for x in range(hx, hx + 8):
                img[y, x, :3] = (70, 60, 70); img[y, x, 3] = 255
        for k in range(4):
            for x in range(hx - 1 + k, hx + 9 - k):
                img[hy - 1 - k, x, :3] = (90, 50, 50); img[hy - 1 - k, x, 3] = 255
        img[hy + 2, hx + 2, :3] = (255, 210, 120); img[hy + 2, hx + 5, :3] = (255, 210, 120)
    Image.fromarray(img, 'RGBA').save(f'{OUT}/backdrop.png')

# ------------------------------------------------------------------ outside cobble ground (seen through door) 32x32
def cobble():
    W, H = 32, 32
    col = np.zeros((H, W, 3), np.float32)
    rp = ramp('#7a8a6a')
    col[:, :] = ramp('#4a5a40')[1]
    for i in range(18):
        cx, cy = rng.randint(0, 31), rng.randint(0, 31)
        r = rng.randint(2, 4)
        rp2 = ramp(rng.choice(['#8a8a80', '#7d8478', '#968e80']))
        for y in range(cy - r, cy + r + 1):
            for x in range(cx - r, cx + r + 1):
                if (x - cx) ** 2 + (y - cy) ** 2 <= r * r:
                    c = rp2[2]
                    if y - cy < -r / 2:
                        c = rp2[3]
                    elif y - cy > r / 2:
                        c = rp2[1]
                    col[y % H, x % W] = c
    save_rgb(col, 'cobble')

# ------------------------------------------------------------------ glass pane 16x16 RGBA (window)
def glass():
    W, H = 16, 16
    img = np.zeros((H, W, 4), np.uint8)
    for y in range(H):
        for x in range(W):
            img[y, x] = (200, 225, 255, 40)
    for i in range(5):
        img[3 + i, 10 - i] = (255, 255, 255, 110)
        img[4 + i, 12 - i] = (255, 255, 255, 70)
    Image.fromarray(img, 'RGBA').save(f'{OUT}/glass.png')

# ------------------------------------------------------------------ soft blob shadow 32x16
def blob():
    W, H = 32, 16
    img = np.zeros((H, W, 4), np.uint8)
    for y in range(H):
        for x in range(W):
            dx = (x + 0.5 - W / 2) / (W / 2)
            dy = (y + 0.5 - H / 2) / (H / 2)
            d = dx * dx + dy * dy
            if d < 1:
                a = int(170 * (1 - d) ** 0.7)
                # posterize into 3 bands for a pixel look
                a = (a // 50) * 50
                img[y, x] = (20, 12, 28, a)
    Image.fromarray(img, 'RGBA').save(f'{OUT}/blob_shadow.png')

if __name__ == '__main__':
    floor_planks(); plaster(); stones()
    wood('wood', '#7a4a2e'); wood('wood_dark', '#5a3424'); wood('wood_light', '#a8784a')
    counter_front(); door(); rug(); backdrop(); cobble(); glass(); blob()
    # preview
    names = ['floor', 'plaster', 'stone', 'wood', 'wood_dark', 'counter_front', 'door', 'rug', 'cobble']
    ims = [Image.open(f'{OUT}/{n}.png').convert('RGBA') for n in names]
    preview(ims, scale=4, cols=5, path='./prev_tex.png', checker=False)
    preview([Image.open(f'{OUT}/backdrop.png')], scale=3, cols=1, path='./prev_backdrop.png')
    print('ok')
