#!/bin/bash
# GIFs of every animation of Heracles for the client (tools/anim_gifs.py: one GIF per category, the blows spread over several,
# labelled in Spanish, real time, each tile held 4-6 frames on its last pose before it loops; plus indice.jpg). The blows, the
# draw into a blow, the dodges, the block, the parry and the hits at 30 fps with the hero 240 px tall and the tiles sized to
# hold the whole swing (3/4 view and the gameplay camera); the rest at 15 fps. Needs xvfb-run, godot 4.7 (software GL is
# fine), ffmpeg and python3 with PIL. One Godot process at a time.
#   tools/anim_gifs.sh <out dir> [--only 05,07b] [--keep] [--sun 110,35] [--plan-only] [--compose-only]
# About 12-13 minutes for all seventeen GIFs on 4 cores (12 min 21 s measured). The project is this script's parent folder
# (the copy it runs in is the one filmed: run it in the tree whose hero you want to show). Writes nothing into the tree.
set -e
OUT=${1:?usage: anim_gifs.sh <out dir> [--only 05,07b] [--keep] [--plan-only]}
shift
HERE="$(cd "$(dirname "$0")" && pwd)"
exec python3 "$HERE/anim_gifs.py" "$OUT" "$@"
