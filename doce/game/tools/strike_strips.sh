#!/bin/bash
# Frame strips of Heracles' blows and every other action (docs/ANIMATION.md section 5): one PNG per action, rows = views, columns = moments.
#   COLS=12 T0=0 T1=0.56 LUNGE=0.8 SPEED=5.5 VIEWS="game side front" TILE=240x280 tools/strike_strips.sh <out dir> <action> [action ...]
# (SPEED: the hero runs at that many m/s when the blow starts; LUNGE: the metres the hero's lunge carries him, as HeroMelee does: the feet of the blow are the ones the game shows)
# Moments are evenly spaced between the action's own seconds T0 and T1 (default: the whole action). Views are the
# preview tool's: game (the gameplay camera, behind and above), side (his right side), front, top, tq, close, closeback.
# Needs a display (xvfb-run) and the GL driver of the preview tool. Prints "SHEET saved <png>" per strip.
set -e
OUT=${1:?usage: strike_strips.sh <out dir> <action> [action ...]}
shift
COLS=${COLS:-12}
VIEWS=${VIEWS:-"game side front"}
TILE=${TILE:-240x280}
HERE="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
cd "$HERE"
EXTRA=""
[ -n "$T0" ] && EXTRA="$EXTRA t0=$T0"
[ -n "$T1" ] && EXTRA="$EXTRA t1=$T1"
[ -n "$LUNGE" ] && EXTRA="$EXTRA lunge=$LUNGE"
for a in "$@"; do
  rows=""
  for v in $VIEWS; do rows="$rows;$a${SPEED:+:$SPEED}@$v"; done
  rows="${rows#;}"
  timeout 900 xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 --resolution 1280x720 \
    res://tools/preview.tscn -- script=res://tools/preview_heracles.gd fns=sheet rows="$rows" cols="$COLS" \
    tile="$TILE" msaa=0 settle=2 $EXTRA out="$OUT/strip_$a.png" 2>&1 | grep -E "SHEET|SCRIPT ERROR|Parse Error"
done
