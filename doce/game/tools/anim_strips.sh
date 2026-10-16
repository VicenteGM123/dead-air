#!/bin/bash
# Frame strips of Heracles' gaits (docs/ANIMATION.md section 6): one PNG per gait, three rows (side, front, gameplay
# camera), one cycle across the columns.
#   tools/anim_strips.sh <out dir> [columns] [gait ...]
# A gait is idle, loco:<m/s>, strafe:<m/s>, strafel:<m/s>, back:<m/s>, guard:<m/s>, guardback:<m/s>, guardstrafe:<m/s>
# (default: idle loco:2.2 loco:6.2 loco:9.0). Needs a display (xvfb-run) and the GL driver of the preview tool; about
# 20 s a strip. Prints "SHEET saved <png>" per strip.
set -e
OUT=${1:?usage: anim_strips.sh <out dir> [columns] [gait ...]}
COLS=${2:-10}
shift 2 || shift $#
GAITS=${@:-"idle loco:2.2 loco:6.2 loco:9.0"}
HERE="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
cd "$HERE"
for g in $GAITS; do
  name=$(echo "$g" | tr ':.' '__')
  timeout 900 xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 --resolution 1280x720 \
    res://tools/preview.tscn -- script=res://tools/preview_heracles.gd fns=sheet rows="$g@side;$g@front;$g@game" cols="$COLS" \
    tile=240x280 msaa=0 settle=2 out="$OUT/strip_$name.png" 2>&1 | grep -E "SHEET|SCRIPT ERROR|Parse Error"
done
