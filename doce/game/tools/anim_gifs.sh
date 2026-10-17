#!/bin/bash
# GIFs of every animation of Heracles for the client (tools/anim_gifs.py: one GIF per category, labelled in Spanish, real time,
# plus indice.jpg). Needs xvfb-run, godot 4.7 (software GL is fine), ffmpeg and python3 with PIL. One Godot process at a time.
#   tools/anim_gifs.sh <out dir> [--only 05,07] [--keep] [--sun 110,35]
# About 7-10 minutes for all eleven GIFs on 4 cores. The project is this script's parent folder (the copy it runs in is the one
# filmed: run it in the tree whose hero you want to show).
set -e
OUT=${1:?usage: anim_gifs.sh <out dir> [--only 05,07] [--keep]}
shift
HERE="$(cd "$(dirname "$0")" && pwd)"
exec python3 "$HERE/anim_gifs.py" "$OUT" "$@"
