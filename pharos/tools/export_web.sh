#!/bin/sh
# PHAROS web build: Godot 4.7 web export (Compatibility renderer / WebGL 2, single-threaded so it runs on GitHub
# Pages and inside iframes without COOP/COEP headers), custom loading screen from <project>/web/shell.html.
#
#   sh pharos/tools/export_web.sh [project_dir] [out_dir]
#
#   project_dir  Godot project to export (default: pharos/game next to this script). The first export of a copy
#                imports its assets into <project_dir>/.godot (a minute or two); later ones are incremental.
#   out_dir      static site to (re)write (default: pharos/web, published at
#                https://vicentegm123.github.io/dead-air/pharos/web/). Previous index.* files there are replaced.
#
# Environment: GODOT=<godot binary> (default: godot on PATH, 4.7.x with the web export templates installed).
# Output: index.html/.js/.wasm/.pck, the audio worklets, icons, fonts/ (Cinzel for the loading screen, SIL OFL) and a
# README.md line. The build includes tools/bot.gd, so ?play=1&bot=1&speed=2 works on the published page too (the
# smoke test uses it): node pharos/tools/web_test.mjs <report_dir> --dir <out_dir>
# No pre-compressed copies: GitHub Pages already gzips html/js/wasm on the fly, it would not serve *.gz files as
# Content-Encoding, and the .pck is mostly Ogg Vorbis audio, which does not compress.
set -eu

PRESET="Web"
case "${1:-}" in
	-h|--help)
		sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
		exit 0
		;;
esac

TOOLS_DIR=$(cd "$(dirname "$0")" && pwd)
PROJ=${1:-$TOOLS_DIR/../game}
OUT=${2:-$TOOLS_DIR/../web}
GODOT=${GODOT:-godot}

if [ ! -f "$PROJ/project.godot" ]; then
	echo "export_web: no project.godot in '$PROJ'" >&2
	exit 1
fi
PROJ=$(cd "$PROJ" && pwd)
if ! grep -q "^name=\"$PRESET\"\$" "$PROJ/export_presets.cfg" 2>/dev/null; then
	echo "export_web: preset \"$PRESET\" not found in $PROJ/export_presets.cfg" >&2
	exit 1
fi
if ! command -v "$GODOT" >/dev/null 2>&1; then
	echo "export_web: Godot binary '$GODOT' not found (set GODOT=/path/to/godot)" >&2
	exit 1
fi
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
case "$OUT" in
	"$PROJ"|"$PROJ"/*)
		echo "export_web: out_dir must be outside the project ($OUT)" >&2
		exit 1
		;;
esac

# Export templates of this exact Godot version (e.g. 4.7.2.stable); only a hint, Godot reports the real error.
VERSION=$("$GODOT" --version 2>/dev/null | head -n 1 | sed -E 's/^([0-9]+(\.[0-9]+)*\.[a-z]+[0-9]*).*/\1/')
TPL=web_nothreads_release.zip
FOUND=0
for d in "${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/$VERSION" \
	"$HOME/Library/Application Support/Godot/export_templates/$VERSION" \
	"${APPDATA:-/nonexistent}/Godot/export_templates/$VERSION"; do
	if [ -f "$d/$TPL" ]; then
		FOUND=1
	fi
done
if [ "$FOUND" = 0 ]; then
	echo "export_web: warning: $TPL for Godot $VERSION not found in the usual export_templates folders" >&2
fi

LOG=$(mktemp "${TMPDIR:-/tmp}/pharos-export.XXXXXX")
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/pharos-web.XXXXXX")
trap 'rm -rf "$LOG" "$STAGE"' EXIT
START=$(date +%s)

echo "== PHAROS web export: preset \"$PRESET\", Godot $VERSION"
echo "   project: $PROJ"
echo "   output:  $OUT"

# 1. Import (creates/updates <project>/.godot: imported audio and fonts, global script class cache).
"$GODOT" --headless --path "$PROJ" --import >"$LOG" 2>&1 || {
	cat "$LOG"
	echo "export_web: import failed" >&2
	exit 1
}

# 2. Export into a staging folder; out_dir is only touched once the build is complete, so a failed export never
#    leaves a half-written site behind.
if ! "$GODOT" --headless --path "$PROJ" --export-release "$PRESET" "$STAGE/index.html" >>"$LOG" 2>&1; then
	cat "$LOG"
	echo "export_web: export failed (nothing written to $OUT)" >&2
	exit 1
fi
for f in index.html index.js index.wasm index.pck; do
	if [ ! -s "$STAGE/$f" ]; then
		cat "$LOG"
		echo "export_web: $f missing after export (nothing written to $OUT)" >&2
		exit 1
	fi
done
if grep -q '\$GODOT_' "$STAGE/index.html"; then
	echo "export_web: warning: unreplaced \$GODOT_ placeholders in index.html (custom shell out of date?)" >&2
fi
# The shell has its own loading screen and never shows Godot's boot splash image.
rm -f "$STAGE/index.png"
# Replace the previous build (old index.* files go first so nothing stale is left behind).
rm -f "$OUT"/index.*
cp "$STAGE"/index.* "$OUT"/

# Errors printed by the editor while importing/exporting (script parse errors etc.) are worth a look; each one is
# printed by the import and again by the export, so show every distinct error (with its "at:" line) once.
ERRORS=$(awk '/^(ERROR|SCRIPT ERROR|USER ERROR)/ { e = $0; n = ""; getline n; k = e "|" n; if (!(k in seen)) { seen[k] = 1; print e; print n } }' "$LOG")
if [ -n "$ERRORS" ]; then
	echo "-- errors in the Godot import/export log (the build may still work, but check them):"
	printf '%s\n' "$ERRORS" | head -n 40
fi

# 3. Loading-screen fonts (SIL Open Font License: the licence travels with the files).
mkdir -p "$OUT/fonts"
for f in Cinzel-Regular.ttf Cinzel-SemiBold.ttf OFL-Cinzel.txt; do
	if [ -f "$PROJ/assets/fonts/$f" ]; then
		cp "$PROJ/assets/fonts/$f" "$OUT/fonts/$f"
	else
		echo "export_web: warning: assets/fonts/$f not found, the loading screen falls back to a system serif" >&2
	fi
done

# 4. README line.
COMMIT=$(git -C "$PROJ" rev-parse --short HEAD 2>/dev/null || echo "?")
cat >"$OUT/README.md" <<EOF
PHAROS · La última luz — build web (Godot $VERSION, preset "$PRESET", WebGL 2, sin hilos) generada con \`pharos/tools/export_web.sh\` el $(date -u +%Y-%m-%d) (commit $COMMIT); no editar a mano. Se juega en https://vicentegm123.github.io/dead-air/pharos/web/
EOF

# 5. Sizes (gzip -9 is roughly what GitHub Pages sends for html/js/wasm; pck/png/ttf go uncompressed).
echo "== files in $OUT"
TOTAL=0
TOTAL_GZ=0
for f in $(cd "$OUT" && find . -type f | sed 's|^\./||' | sort); do
	n=$(wc -c <"$OUT/$f" | tr -d ' ')
	g=$(gzip -9 -c "$OUT/$f" | wc -c | tr -d ' ')
	TOTAL=$((TOTAL + n))
	TOTAL_GZ=$((TOTAL_GZ + g))
	awk -v f="$f" -v n="$n" -v g="$g" 'BEGIN { printf "  %-34s %10d B %9.2f MB   gzip %8.2f MB\n", f, n, n / 1048576, g / 1048576 }'
done
awk -v n="$TOTAL" -v g="$TOTAL_GZ" 'BEGIN { printf "  %-34s %10d B %9.2f MB   gzip %8.2f MB\n", "total", n, n / 1048576, g / 1048576 }'
echo "== done in $(( $(date +%s) - START )) s; smoke test:  node $TOOLS_DIR/web_test.mjs <report_dir> --dir $OUT"
