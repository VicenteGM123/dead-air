#!/bin/sh
# DEAD AIR web build (Compatibility renderer, single-threaded: runs on GitHub Pages without COOP/COEP headers).
# GitHub refuses files over 100 MB, so the data is split in two packs:
#   index.pck        preset "Web"      (everything but assets/props/*.glb)
#   index.props.pck  preset "Web Full" exported as a patch of index.pck = just the props
# web/shell.html preloads index.props.pck and scripts/core/game.gd mounts it at boot.
# Usage: sh godot/web/export_web.sh [out_dir]   (default: <repo>/godot-web; needs the 4.7.2 web export templates)
set -e
GODOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:-$GODOT_DIR/../godot-web}
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
GODOT=${GODOT:-godot}
"$GODOT" --headless --path "$GODOT_DIR" --export-release "Web" "$OUT/index.html"
"$GODOT" --headless --path "$GODOT_DIR" --export-patch "Web Full" "$OUT/index.props.pck" --patches "$OUT/index.pck"
ls -l "$OUT"
