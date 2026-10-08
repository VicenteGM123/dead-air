#!/bin/sh
# PHAROS web build: Godot 4.7 web export (Compatibility renderer / WebGL 2, single-threaded so it runs on GitHub
# Pages and inside iframes without COOP/COEP headers), custom loading screen from <project>/web/shell.html.
#
#   sh pharos/tools/export_web.sh [project_dir] [out_dir]
#
#   project_dir  Godot project to export (default: pharos/game next to this script). The first export of a copy
#                imports its assets into <project_dir>/.godot (a minute or two); later ones are incremental.
#   out_dir      static site to (re)write (default: pharos/web, published at
#                https://vicentegm123.github.io/dead-air/pharos/web/). index.*, fonts/, og.* and README.md there are
#                replaced; nothing else is touched.
#
# Refuses to export (exit 1, nothing written) when code the build ships uses something that breaks the web build:
#   `instance uniform` in a shader, set_/get_instance_shader_parameter(), RenderingServer's
#   instance_geometry_set_shader_parameter() or instance_shader_parameters/ in a scene (on WebGL 2 only ~14 instances
#   get their values: black or invisible models), or AudioServer.add_bus() (no sound at all). Comments are ignored.
#   Fix: plain `uniform` + Materials.set_param(node, &"param", value); AudioServer.bus_count = n + 1 for a new bus.
#
# Environment: GODOT=<godot binary> (default: godot on PATH, 4.7.x with the web export templates installed)
#              STRICT=1  also refuse when the Godot import/export log has a SCRIPT ERROR or a Parse Error (use it
#                        for every build that gets published)
#              FORCE=1   export despite the checks above (experiments only; never publish such a build)
# Output: index.html/.js/.wasm/.pck, the audio worklets, icons, everything in <project>/web/site/ (fonts/: Cinzel and
# EB Garamond subsets for the loading screen with their SIL OFL licences; og.jpg: the link-preview image) and a
# one-line README.md (Godot version and `git describe --always --dirty` of the project, no date, so re-exporting the
# same sources leaves it unchanged). index.js gets two fixes to Godot 4.7's web audio (see step 4): decoded sounds are
# shared instead of copied on every play(), and music and ambience loop without a gap. The build includes
# tools/bot.gd, so ?dev=1&play=1&bot=1&speed=2 works on the published page too (the smoke test uses it):
#   node pharos/tools/web_test.mjs <report_dir> --dir <out_dir>
# No pre-compressed copies: GitHub Pages already gzips html/js/wasm on the fly, it would not serve *.gz files as
# Content-Encoding, and the .pck is mostly Ogg Vorbis audio, which does not compress.
set -eu

PRESET="Web"
case "${1:-}" in
	-h|--help)
		sed -n '2,31p' "$0" | sed 's/^# \{0,1\}//'
		exit 0
		;;
esac

TOOLS_DIR=$(cd "$(dirname "$0")" && pwd)
PROJ=${1:-$TOOLS_DIR/../game}
OUT=${2:-$TOOLS_DIR/../web}
GODOT=${GODOT:-godot}
FORCE=${FORCE:-0}
STRICT=${STRICT:-0}

if [ ! -f "$PROJ/project.godot" ]; then
	echo "export_web: no project.godot in '$PROJ'" >&2
	exit 1
fi
PROJ=$(cd "$PROJ" && pwd)
if ! grep -q "^name=\"$PRESET\"\$" "$PROJ/export_presets.cfg" 2>/dev/null; then
	echo "export_web: preset \"$PRESET\" not found in $PROJ/export_presets.cfg" >&2
	exit 1
fi

# Files the preset leaves out of the build (its exclude_filter, e.g. "*.md, web/*, tools/preview*") do not matter.
EXCLUDES=$(sed -n 's/^exclude_filter="\(.*\)"$/\1/p' "$PROJ/export_presets.cfg" | head -n 1 | tr ',' ' ')
shipped() { # $1: path relative to the project
	set -f # the patterns are matched by case, never expanded
	for pat in $EXCLUDES; do
		case "$1" in
			$pat)
				set +f
				return 1
				;;
		esac
	done
	set +f
	return 0
}

# 0. Code that cannot work on the web (see the header). The awk program reads the file names and drops comments
#    (GDScript #, shader // and /* */) but keeps strings, so shader code embedded in a script is checked too.
WEBFAIL=$(
	cd "$PROJ"
	find . -path ./.godot -prune -o -type f \( -name '*.gd' -o -name '*.gdshader' -o -name '*.gdshaderinc' \
		-o -name '*.tscn' -o -name '*.tres' \) -print | sed 's|^\./||' | sort | while IFS= read -r f; do
		if shipped "$f"; then
			printf '%s\n' "$f"
		fi
	done | awk '
		function scan(f,    gd, st, q, line, code, n, i, c, t, ln, w, e) {
			gd = (f ~ /\.gd$/)
			st = 0
			ln = 0
			w = "(^|[^A-Za-z0-9_])"
			e = "([^A-Za-z0-9_]|$)"
			while ((getline line < f) > 0) {
				ln++
				code = ""
				n = length(line)
				i = 1
				q = ""
				while (i <= n) {
					c = substr(line, i, 1)
					if (gd) {
						if (st == 3 || st == 4) { # inside a """ or triple-single-quote string: embedded shader code
							t = (st == 3) ? DQ DQ DQ : SQ SQ SQ
							if (substr(line, i, 3) == t) { code = code t; i += 3; st = 0; continue }
							if (substr(line, i, 2) == "//") break
							code = code c; i++; continue
						}
						if (q != "") {
							if (c == "\\") { code = code substr(line, i, 2); i += 2; continue }
							if (c == q) q = ""
							code = code c; i++; continue
						}
						if (c == "#") break
						if (substr(line, i, 3) == DQ DQ DQ) { st = 3; code = code c; i += 3; continue }
						if (substr(line, i, 3) == SQ SQ SQ) { st = 4; code = code c; i += 3; continue }
						if (c == DQ || c == SQ) q = c
						code = code c; i++
					} else {
						if (st == 5) {
							if (substr(line, i, 2) == "*/") { st = 0; i += 2; continue }
							i++; continue
						}
						if (substr(line, i, 2) == "//") break
						if (substr(line, i, 2) == "/*") { st = 5; i += 2; continue }
						code = code c; i++
					}
				}
				if (code ~ (w "instance[ \t]+uniform" e) \
					|| (gd && code ~ (w "(set|get)_instance_shader_parameter" e)) \
					|| (gd && code ~ (w "instance_geometry_(set|get)_shader_parameter" e)) \
					|| (gd && code ~ /AudioServer[ \t]*\.[ \t]*add_bus[ \t]*\(/) \
					|| (!gd && code ~ /^[ \t]*instance_shader_parameters\//)) {
					sub(/^[ \t]+/, "", line)
					printf "%s:%d: %s\n", f, ln, substr(line, 1, 140)
				}
			}
			close(f)
		}
		BEGIN { DQ = "\""; SQ = "\047" }
		{ scan($0) }'
)
if [ -n "$WEBFAIL" ]; then
	echo "export_web: the build would ship code that does not work on the web (black or invisible models, or no sound):" >&2
	printf '%s\n' "$WEBFAIL" | head -n 25 | sed 's/^/  /' >&2
	n=$(printf '%s\n' "$WEBFAIL" | wc -l | tr -d ' ')
	if [ "$n" -gt 25 ]; then
		echo "  ... ($n lines)" >&2
	fi
	echo "  fix: plain \`uniform\` + Materials.set_param(node, &\"param\", value) instead of instance uniforms;" >&2
	echo "       AudioServer.bus_count = n + 1 instead of AudioServer.add_bus() (see scripts/core/audio.gd)" >&2
	if [ "$FORCE" = 1 ]; then
		echo "export_web: FORCE=1, exporting anyway (do not publish this build)" >&2
	else
		echo "export_web: nothing exported (FORCE=1 exports anyway)" >&2
		exit 1
	fi
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

echo "== PHAROS web export: preset \"$PRESET\", Godot $VERSION$( [ "$STRICT" = 1 ] && echo ", STRICT" )"
echo "   project: $PROJ"
echo "   output:  $OUT"

# 1. Import (creates/updates <project>/.godot: imported audio and fonts, global script class cache).
"$GODOT" --headless --path "$PROJ" --import >"$LOG" 2>&1 || {
	cat "$LOG"
	echo "export_web: import failed" >&2
	exit 1
}

# 2. Export into a staging folder; out_dir is only touched once the build is complete and checked, so a failed
#    export never leaves a half-written site behind.
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

# 3. Errors printed by the editor while importing/exporting; each one is printed by the import and again by the
#    export, so show every distinct error (with its "at:" line) once. Script errors in a script the build ships
#    usually mean a broken feature, or a broken game: STRICT=1 stops there.
ERRORS=$(awk '/^(ERROR|SCRIPT ERROR|USER ERROR)/ { e = $0; n = ""; getline n; k = e "|" n; if (!(k in seen)) { seen[k] = 1; print e; print n } }' "$LOG")
if [ -n "$ERRORS" ]; then
	echo "-- errors in the Godot import/export log:"
	printf '%s\n' "$ERRORS" | head -n 40
	if printf '%s\n' "$ERRORS" | grep -q 'Error loading custom project font'; then
		echo "   (the custom project font errors come from the first import of a copy without .godot/: harmless, the build has the font)"
	fi
fi
BROKEN=""
for f in $(awk '/SCRIPT ERROR|Parse Error/ { s = $0; getline n; s = s " " n; if (match(s, /res:\/\/[^:)]*\.gd/)) print substr(s, RSTART + 6, RLENGTH - 6) }' "$LOG" | sort -u); do
	if shipped "$f"; then
		BROKEN="$BROKEN $f"
	fi
done
if [ -n "$BROKEN" ] || grep -qE 'SCRIPT ERROR|Parse Error' "$LOG"; then
	echo "export_web: warning: script errors in the Godot log${BROKEN:+ (scripts the build ships:$BROKEN)}" >&2
	if [ "$STRICT" = 1 ]; then
		if [ "$FORCE" = 1 ]; then
			echo "export_web: STRICT=1 but FORCE=1, exporting anyway (do not publish this build)" >&2
		else
			echo "export_web: STRICT=1: nothing written to $OUT (fix the scripts above; FORCE=1 exports anyway)" >&2
			exit 1
		fi
	fi
fi

# 4. Two fixes to Godot 4.7's web audio (Sample playback) in index.js, each a literal replacement that is reported
#    when it no longer matches (a different Godot version):
#    a) a sound's decoded AudioBuffer is shared instead of copied on every play() (a ~0.3 s stall and ~25 MB of
#       garbage per music start); only AudioBufferSourceNode.buffer ever receives it and Web Audio lets any number of
#       sources share one buffer;
#    b) looping sounds (music, ambience) loop on the audio thread (AudioBufferSourceNode.loop) instead of being
#       restarted from the main thread's "ended" event, which leaves a gap at every loop point, as long as the frame
#       that is running then (a hitch silences the music); a paused loop resumes inside the buffer.
patch_js() { # $1: what for, $2: old text, $3: new text
	if grep -qF "$2" "$STAGE/index.js"; then
		OLD="$2" NEW="$3" awk 'BEGIN { o = ENVIRON["OLD"]; n = ENVIRON["NEW"] }
			{ out = ""; s = $0; while ((i = index(s, o)) > 0) { out = out substr(s, 1, i - 1) n; s = substr(s, i + length(o)) } print out s }' \
			"$STAGE/index.js" >"$STAGE/index.js.tmp"
		mv "$STAGE/index.js.tmp" "$STAGE/index.js"
	fi
	if ! grep -qF "$3" "$STAGE/index.js"; then
		echo "export_web: warning: Godot's web audio code has changed, index.js not patched: $1" >&2
	fi
}
patch_js "sounds still copy their AudioBuffer on every play()" \
	'getAudioBuffer(){return this._duplicateAudioBuffer()}' \
	'getAudioBuffer(){return this._audioBuffer}'
patch_js "looping sounds are still restarted from the main thread (a gap at every loop)" \
	'_addEndedListener(){if(this._onended!=null){' \
	'_addEndedListener(){if(this.getSample().loopMode==="forward"){this._source.loop=true}if(this._onended!=null){'
patch_js "a paused looping sound may resume at the start of its loop" \
	'this.pauseTime=(GodotAudio.ctx.currentTime-this._sourceStartTime)/this.getPlaybackRate();' \
	'this.pauseTime=(GodotAudio.ctx.currentTime-this._sourceStartTime)/this.getPlaybackRate();if(this._source.loop&&this._source.buffer){this.pauseTime%=this._source.buffer.duration}'

# 5. Shell assets: everything in <project>/web/site/ (loading-screen fonts with their SIL OFL licences, the
#    link-preview image). The shell has its own loading screen and never shows Godot's boot splash image.
rm -f "$STAGE/index.png"
if [ -d "$PROJ/web/site" ]; then
	(cd "$PROJ/web/site" && tar -cf - --exclude=.gdignore --exclude='*.import' .) | (cd "$STAGE" && tar -xf -)
fi
MISSING=""
for f in fonts/cinzel-600.woff2 fonts/cinzel-400.woff2 fonts/ebgaramond-400.woff2 fonts/ebgaramond-400-italic.woff2 \
	fonts/OFL-Cinzel.txt fonts/OFL-EBGaramond.txt og.jpg; do
	if [ ! -s "$STAGE/$f" ]; then
		MISSING="$MISSING $f"
	fi
done
if [ -n "$MISSING" ]; then
	echo "export_web: warning: missing from $PROJ/web/site:$MISSING (system fonts on the loading screen, no link preview)" >&2
fi

# 6. README line: Godot version and the project's commit (`-dirty` when the working tree has uncommitted changes), no
#    date, so exporting the same sources twice gives the same file.
COMMIT=$(git -C "$PROJ" describe --always --dirty 2>/dev/null || true)
cat >"$STAGE/README.md" <<EOF
PHAROS · La última luz — build web (Godot $VERSION, preset "$PRESET", WebGL 2, sin hilos)${COMMIT:+ de \`$COMMIT\`} generada con \`pharos/tools/export_web.sh\`; no editar a mano. Se juega en https://vicentegm123.github.io/dead-air/pharos/web/
EOF

# 7. Replace the previous build (old index.*, fonts/ and og.* go first so nothing stale is left behind).
rm -rf "$OUT"/index.* "$OUT/fonts" "$OUT"/og.* "$OUT/README.md"
(cd "$STAGE" && tar -cf - .) | (cd "$OUT" && tar -xf -)

# 8. Sizes (gzip -9 is roughly what GitHub Pages sends for html/js/wasm; pck/png/woff2/jpg go uncompressed).
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
echo "== build${COMMIT:+ of $COMMIT} done in $(( $(date +%s) - START )) s; smoke test:  node $TOOLS_DIR/web_test.mjs <report_dir> --dir $OUT"
