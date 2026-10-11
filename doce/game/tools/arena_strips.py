#!/usr/bin/env python3
"""Frame strips of the arena bot's moves (one row per move) from --write-movie frames.

Render a move with the gameplay camera, e.g.
  xvfb-run -a -s "-screen 0 1600x900x24" godot --path doce/game --rendering-driver opengl3 --resolution 1280x720 \
      --write-movie /abs/frames/combo/f.png --fixed-fps 30 --quit-after 100 res://tools/arena.tscn -- bot=combo noui=1
the bot prints "ARENA mark combo frame=16": the move starts at movie frame 16. Then
  python3 doce/game/tools/arena_strips.py out.png --cols 8 \
      --row "combo:/abs/frames/combo:16:8:3" --row "heavy:/abs/frames/heavy:16:8:3:640:380:620:520"
A row is label:dir:first_frame:count:step[:centre_x:centre_y:crop_w:crop_h] (crop in source pixels; default a
640 x 520 box round (640, 380) of a 1280 x 720 frame). Each cell is labelled with its frame offset in seconds.
With --log (the movie run's output) and --dir, a row can name a mark instead of a frame:
  --log run.log --dir /abs/frames --mark "combo:8:3" --mark "grapple+1.3:8:4" (tag[+seconds]:count:step[:crop])
"""
import re
import argparse
import os
import sys

from PIL import Image, ImageDraw


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--row", action="append", default=[])
    ap.add_argument("--cell", type=int, default=300, help="cell width in pixels")
    ap.add_argument("--fps", type=float, default=30.0)
    ap.add_argument("--log", default="")
    ap.add_argument("--dir", default="")
    ap.add_argument("--mark", action="append", default=[])
    args = ap.parse_args()
    marks = {}
    if args.log:
        for line in open(args.log, errors="replace"):
            m = re.search(r"ARENA mark (\S+) frame=(\d+)", line)
            if m:
                marks[m.group(1)] = int(m.group(2))
    for spec in args.mark:
        p = spec.split(":")
        tag = p[0]
        off = 0.0
        if "+" in tag:
            tag, o = tag.split("+", 1)
            off = float(o)
        if tag not in marks:
            print("no mark", tag, file=sys.stderr)
            continue
        first = marks[tag] + int(round(off * args.fps))
        rest = ":".join(p[1:])
        args.row.append("%s:%s:%d:%s" % (p[0].replace(":", "_"), args.dir, first, rest))
    rows = []
    for spec in args.row:
        p = spec.split(":")
        label, d, first, count, step = p[0], p[1], int(p[2]), int(p[3]), int(p[4])
        cx, cy, cw, ch = 640, 380, 640, 520
        if len(p) >= 9:
            cx, cy, cw, ch = int(p[5]), int(p[6]), int(p[7]), int(p[8])
        rows.append((label, d, first, count, step, cx, cy, cw, ch))
    if not rows:
        print("no rows", file=sys.stderr)
        return 1
    cols = max(r[3] for r in rows)
    cell_w = args.cell
    cell_h = max(int(cell_w * r[8] / r[7]) for r in rows)
    sheet = Image.new("RGB", (cell_w * cols, cell_h * len(rows)), (24, 22, 28))
    draw = ImageDraw.Draw(sheet)
    for ri, (label, d, first, count, step, cx, cy, cw, ch) in enumerate(rows):
        for ci in range(count):
            f = first + ci * step
            path = os.path.join(d, "f%08d.png" % f)
            if not os.path.exists(path):
                continue
            im = Image.open(path).convert("RGB")
            box = (cx - cw // 2, cy - ch // 2, cx + cw // 2, cy + ch // 2)
            im = im.crop(box).resize((cell_w, int(cell_w * ch / cw)), Image.LANCZOS)
            x, y = ci * cell_w, ri * cell_h
            sheet.paste(im, (x, y))
            tag = "%s +%.2fs" % (label, (f - first) / args.fps) if ci == 0 else "+%.2fs" % ((f - first) / args.fps)
            draw.rectangle((x + 2, y + 2, x + 8 + 7 * len(tag), y + 16), fill=(0, 0, 0))
            draw.text((x + 5, y + 3), tag, fill=(255, 240, 200))
        draw.line((0, (ri + 1) * cell_h - 1, cell_w * cols, (ri + 1) * cell_h - 1), fill=(10, 10, 10), width=2)
    sheet.save(args.out)
    print("STRIPS saved", args.out, sheet.size)
    return 0


if __name__ == "__main__":
    sys.exit(main())
