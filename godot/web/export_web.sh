#!/bin/sh
# DEAD AIR web build (Compatibility renderer). Two engine builds share the data packs:
#   index.html/.js/.wasm     preset "Web"     threaded (needs cross-origin isolation: GitHub Pages sends no COOP/COEP
#                            headers, so web/coi-sw.js, a service worker copied next to it, adds them; shell.html
#                            registers it on the first visit and reloads)
#   index-st.html/.js/.wasm  preset "Web ST"  single-threaded fallback (index.html redirects there when no service
#                            worker can be used); its own pack is deleted: it loads index.pck too
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
"$GODOT" --headless --path "$GODOT_DIR" --export-release "Web ST" "$OUT/index-st.html"
rm -f "$OUT/index-st.pck"
cp "$GODOT_DIR/web/coi-sw.js" "$OUT/coi-sw.js"
ls -l "$OUT"
