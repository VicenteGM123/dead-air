"""Tiny pixel-art toolkit: ASCII stamping, hue-shifted ramps, auto shading and sel-out outlines."""
import colorsys, math, random
import numpy as np
from PIL import Image

def hexrgb(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))

def clamp01(v):
    return max(0.0, min(1.0, v))

def shift(rgb, dv=0.0, ds=0.0, dh=0.0):
    r, g, b = [c / 255 for c in rgb]
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    h = (h + dh / 360.0) % 1.0
    s = clamp01(s + ds)
    v = clamp01(v + dv)
    r, g, b = colorsys.hsv_to_rgb(h, s, v)
    return (round(r * 255), round(g * 255), round(b * 255))

def toward_hue(rgb, target_deg, amount_deg, dv, ds):
    r, g, b = [c / 255 for c in rgb]
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    hd = h * 360
    diff = ((target_deg - hd + 540) % 360) - 180
    step = max(-amount_deg, min(amount_deg, diff))
    if s < 0.08:
        step *= 0.3
    return shift(rgb, dv, ds, step)

def ramp(base):
    """5 shades: 0 darkest .. 2 base .. 4 lightest, hue-shifted (shadows to violet, lights to warm)."""
    b = hexrgb(base) if isinstance(base, str) else base
    return [
        toward_hue(b, 255, 28, -0.40, +0.10),
        toward_hue(b, 250, 14, -0.20, +0.06),
        b,
        toward_hue(b, 50, 10, +0.12, -0.08),
        toward_hue(b, 55, 16, +0.24, -0.18),
    ]

class Mat:
    def __init__(self, base, mode='cyl', outline_k=0.55):
        self.r = ramp(base)
        self.mode = mode   # 'cyl' auto shade, 'flat' no shading, 'top' highlight on top edge too
        self.outline_k = outline_k

def stamp(grid, art, ox=0, oy=0, transparent='.'):
    lines = [l for l in art.strip('\n').split('\n')]
    for y, line in enumerate(lines):
        for x, ch in enumerate(line):
            if ch == transparent or ch == ' ':
                continue
            gy, gx = oy + y, ox + x
            if 0 <= gy < len(grid) and 0 <= gx < len(grid[0]):
                grid[gy][gx] = ch
    return grid

def new_grid(w, h):
    return [['.'] * w for _ in range(h)]

def render(grid, codes, outline=True, outline_col=None, light_from='left'):
    """codes: char -> (Mat, forced_level|None)"""
    h, w = len(grid), len(grid[0])
    img = np.zeros((h, w, 4), dtype=np.uint8)
    lvl = [[None] * w for _ in range(h)]
    for y in range(h):
        x = 0
        while x < w:
            ch = grid[y][x]
            if ch == '.' or ch not in codes:
                x += 1
                continue
            mat, forced = codes[ch]
            # run of same material (any char mapping to same Mat object)
            x0 = x
            while x < w and grid[y][x] in codes and codes[grid[y][x]][0] is mat:
                x += 1
            x1 = x - 1
            run_w = x1 - x0 + 1
            for xx in range(x0, x1 + 1):
                c = grid[y][xx]
                m2, f2 = codes[c]
                if f2 is not None:
                    lv = f2
                elif m2.mode == 'flat':
                    lv = 2
                else:
                    lv = 2
                    rel = (xx - x0) / max(1, run_w - 1)
                    if light_from == 'right':
                        rel = 1 - rel
                    above = y > 0 and grid[y-1][xx] in codes and codes[grid[y-1][xx]][0] is m2
                    below = y < h-1 and grid[y+1][xx] in codes and codes[grid[y+1][xx]][0] is m2
                    if run_w >= 3 and rel > 0.70:
                        lv = 1
                    if run_w >= 2 and ((light_from == 'left' and xx == x1) or (light_from == 'right' and xx == x0)):
                        lv = 1
                    if not below and run_w >= 2:
                        lv = min(lv, 1)
                    if run_w >= 4 and ((light_from == 'left' and xx == x0) or (light_from == 'right' and xx == x1)) and above:
                        lv = 3
                    if m2.mode == 'top' and not above:
                        lv = 3 if rel < 0.7 else 2
                    if m2.mode == 'shine' and not above and rel < 0.6:
                        lv = 4
                lvl[y][xx] = (m2, lv)
    for y in range(h):
        for x in range(w):
            if lvl[y][x] is not None:
                m, lv = lvl[y][x]
                img[y, x, :3] = m.r[lv]
                img[y, x, 3] = 255
    if outline:
        out = img.copy()
        for y in range(h):
            for x in range(w):
                if img[y, x, 3] != 0:
                    continue
                best = None
                for dx, dy in ((0, 1), (-1, 0), (1, 0), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h and img[ny, nx, 3] != 0 and lvl[ny][nx] is not None:
                        best = lvl[ny][nx][0]
                        break
                if best is not None:
                    if outline_col is not None:
                        out[y, x, :3] = hexrgb(outline_col)
                    else:
                        d = best.r[0]
                        out[y, x, :3] = tuple(int(c * best.outline_k) for c in d)
                    out[y, x, 3] = 255
        img = out
    return img

def to_image(arr):
    return Image.fromarray(arr, 'RGBA')

def preview(images, scale=6, cols=8, bg=(40, 34, 56), pad=4, path='preview.png', checker=True):
    ims = [i if isinstance(i, Image.Image) else to_image(i) for i in images]
    cw = max(i.width for i in ims) * scale + pad * 2
    ch = max(i.height for i in ims) * scale + pad * 2
    rows = math.ceil(len(ims) / cols)
    sheet = Image.new('RGBA', (cw * min(cols, len(ims)), ch * rows), bg + (255,))
    for n, im in enumerate(ims):
        cx, cy = (n % cols) * cw, (n // cols) * ch
        if checker:
            for yy in range(0, ch, 12):
                for xx in range(0, cw, 12):
                    if (xx // 12 + yy // 12) % 2 == 0:
                        sheet.paste((48, 42, 66, 255), (cx + xx, cy + yy, min(cx + xx + 12, cx + cw), min(cy + yy + 12, cy + ch)))
        big = im.resize((im.width * scale, im.height * scale), Image.NEAREST)
        sheet.alpha_composite(big, (cx + pad + (cw - pad*2 - big.width) // 2, cy + pad + (ch - pad*2 - big.height)))
    sheet.save(path)
    return path

def shift_rows(arr, y_from, y_to, dy):
    """Shift rows [y_from, y_to) by dy (positive = down), returns new array."""
    out = arr.copy()
    h = arr.shape[0]
    block = arr[y_from:y_to].copy()
    out[y_from:y_to] = 0
    for i in range(block.shape[0]):
        ty = y_from + i + dy
        if 0 <= ty < h:
            src = block[i]
            mask = src[:, 3] > 0
            out[ty][mask] = src[mask]
    return out

def hstack(frames):
    return np.concatenate(frames, axis=1)

def save(arr, path):
    to_image(arr).save(path)
