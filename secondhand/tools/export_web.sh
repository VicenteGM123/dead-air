#!/bin/sh
# Secondhand Stars: versión web. Exporta el proyecto con su preset "Web" de Godot 4.7 (renderizador Compatibility /
# WebGL 2, sin hilos: funciona en GitHub Pages) y arregla el audio web de Godot 4.7 en index.js.
# (Copiado de caldero/tools/export_web.sh de Midnight Cauldron: mismos pasos, otro título.)
#
#   sh secondhand/tools/export_web.sh [carpeta_del_proyecto] [carpeta_de_salida]
#
#   carpeta_del_proyecto  por defecto secondhand/game (junto a este script)
#   carpeta_de_salida     por defecto secondhand/web (se publica en https://vicentegm123.github.io/dead-air/secondhand/web/);
#                         se reemplazan sus index.*, nada más
#
# Variables: GODOT=<ejecutable de Godot 4.7.x con las plantillas de exportación web instaladas> (por defecto: godot)
#            FORCE=1  exporta aunque falle la comprobación del paso 0 (solo para pruebas; no publicar)
#            WEB_TITLE=<título de la pestaña> (por defecto: Secondhand Stars)
#
# 0. No exporta si el código usa AudioServer.add_bus(): en la web desordena los buses y no se oye nada
#    (para crear un bus: AudioServer.bus_count = n + 1, ver scripts/sfx.gd).
# 1-2. Importa y exporta en una carpeta temporal; la salida solo se toca si la exportación sale completa.
# 3. Dos arreglos al audio web de Godot 4.7 (reproducción "Sample") en index.js, cada uno un reemplazo literal que
#    avisa si ya no encaja (otra versión de Godot):
#    a) los sonidos en bucle (música, viento, puerto) se repiten en el hilo de audio (AudioBufferSourceNode.loop) en
#       vez de reiniciarse desde el hilo principal: sin hueco en cada vuelta y sin silencio cuando el juego va lento;
#       al pausar un bucle, la posición se guarda dentro del sonido;
#    b) cada sonido decodificado se comparte en vez de copiarse en cada play() (menos tirones y menos memoria).
# 3b. El <title> de index.html dice el nombre del juego (WEB_TITLE): Godot escribe ahí config/name (aquí ya es
#    «Secondhand Stars»; el paso se deja por si alguna vez cambian, como pasó en Midnight Cauldron).
set -eu

PRESET="Web"
case "${1:-}" in
	-h|--help)
		sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'
		exit 0
		;;
esac

TOOLS_DIR=$(cd "$(dirname "$0")" && pwd)
PROJ=${1:-$TOOLS_DIR/../game}
OUT=${2:-$TOOLS_DIR/../web}
GODOT=${GODOT:-godot}
FORCE=${FORCE:-0}
WEB_TITLE=${WEB_TITLE:-Secondhand Stars}

if [ ! -f "$PROJ/project.godot" ]; then
	echo "export_web: no hay project.godot en '$PROJ'" >&2
	exit 1
fi
PROJ=$(cd "$PROJ" && pwd)
if ! grep -q "^name=\"$PRESET\"\$" "$PROJ/export_presets.cfg" 2>/dev/null; then
	echo "export_web: falta el preset \"$PRESET\" en $PROJ/export_presets.cfg" >&2
	exit 1
fi
if ! command -v "$GODOT" >/dev/null 2>&1; then
	echo "export_web: no encuentro Godot ('$GODOT'); usa GODOT=/ruta/a/godot" >&2
	exit 1
fi

# 0. AudioServer.add_bus() en los scripts que se exportan (sin contar comentarios; tools/ no se exporta).
ADD_BUS=$(cd "$PROJ" && find . -path ./.godot -prune -o -path ./tools -prune -o -name '*.gd' -type f -print | sort |
	while IFS= read -r f; do
		sed 's/#.*//' "$f" | grep -n 'AudioServer[[:space:]]*\.[[:space:]]*add_bus[[:space:]]*(' | sed "s|^|${f#./}:|"
	done)
if [ -n "$ADD_BUS" ]; then
	echo "export_web: este código deja la versión web sin sonido (AudioServer.add_bus):" >&2
	printf '%s\n' "$ADD_BUS" | sed 's/^/  /' >&2
	echo "  arreglo: AudioServer.bus_count = n + 1 y luego set_bus_name(n, ...) (ver scripts/sfx.gd)" >&2
	if [ "$FORCE" != 1 ]; then
		exit 1
	fi
	echo "export_web: FORCE=1, se exporta igual (no publicar esta versión)" >&2
fi

mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
case "$OUT" in
	"$PROJ"|"$PROJ"/*)
		echo "export_web: la carpeta de salida no puede estar dentro del proyecto ($OUT)" >&2
		exit 1
		;;
esac

LOG=$(mktemp "${TMPDIR:-/tmp}/secondhand-export.XXXXXX")
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/secondhand-web.XXXXXX")
trap 'rm -rf "$LOG" "$STAGE"' EXIT
VERSION=$("$GODOT" --version 2>/dev/null | head -n 1)
echo "== $WEB_TITLE, versión web: preset \"$PRESET\", Godot $VERSION"
echo "   proyecto: $PROJ"
echo "   salida:   $OUT"

# 1. Importar (crea o actualiza <proyecto>/.godot).
"$GODOT" --headless --path "$PROJ" --import >"$LOG" 2>&1 || {
	cat "$LOG"
	echo "export_web: falló la importación" >&2
	exit 1
}

# 2. Exportar a la carpeta temporal.
if ! "$GODOT" --headless --path "$PROJ" --export-release "$PRESET" "$STAGE/index.html" >>"$LOG" 2>&1; then
	cat "$LOG"
	echo "export_web: falló la exportación (no se tocó $OUT)" >&2
	exit 1
fi
for f in index.html index.js index.wasm index.pck; do
	if [ ! -s "$STAGE/$f" ]; then
		cat "$LOG"
		echo "export_web: falta $f tras exportar (no se tocó $OUT)" >&2
		exit 1
	fi
done
if grep -qE '^(ERROR|SCRIPT ERROR|USER ERROR)|Parse Error' "$LOG"; then
	echo "-- errores en el registro de Godot:"
	grep -E -A1 '^(ERROR|SCRIPT ERROR|USER ERROR)|Parse Error' "$LOG" | head -n 40
fi

# 3. Arreglos al audio web en index.js.
patch_js() { # $1: para qué, $2: texto original, $3: texto nuevo
	if grep -qF "$2" "$STAGE/index.js"; then
		OLD="$2" NEW="$3" awk 'BEGIN { o = ENVIRON["OLD"]; n = ENVIRON["NEW"] }
			{ out = ""; s = $0; while ((i = index(s, o)) > 0) { out = out substr(s, 1, i - 1) n; s = substr(s, i + length(o)) } print out s }' \
			"$STAGE/index.js" >"$STAGE/index.js.tmp"
		mv "$STAGE/index.js.tmp" "$STAGE/index.js"
	fi
	if ! grep -qF "$3" "$STAGE/index.js"; then
		echo "export_web: aviso: el audio web de Godot cambió, index.js sin arreglar: $1" >&2
	fi
}
patch_js "los bucles se siguen reiniciando desde el hilo principal (hueco o silencio en cada vuelta)" \
	'_addEndedListener(){if(this._onended!=null){' \
	'_addEndedListener(){if(this.getSample().loopMode==="forward"){this._source.loop=true}if(this._onended!=null){'
patch_js "un bucle en pausa puede volver al principio" \
	'this.pauseTime=(GodotAudio.ctx.currentTime-this._sourceStartTime)/this.getPlaybackRate();' \
	'this.pauseTime=(GodotAudio.ctx.currentTime-this._sourceStartTime)/this.getPlaybackRate();if(this._source.loop&&this._source.buffer){this.pauseTime%=this._source.buffer.duration}'
patch_js "cada play() sigue copiando el sonido decodificado" \
	'getAudioBuffer(){return this._duplicateAudioBuffer()}' \
	'getAudioBuffer(){return this._audioBuffer}'

# 3b. El título de la pestaña (y de los marcadores): el <title> que Godot escribió con config/name.
if grep -q '<title>[^<]*</title>' "$STAGE/index.html"; then
	T="$WEB_TITLE" awk 'BEGIN { t = ENVIRON["T"] } { sub(/<title>[^<]*<\/title>/, "<title>" t "</title>"); print }' \
		"$STAGE/index.html" >"$STAGE/index.html.tmp"
	mv "$STAGE/index.html.tmp" "$STAGE/index.html"
fi
if ! grep -qF "<title>$WEB_TITLE</title>" "$STAGE/index.html"; then
	echo "export_web: aviso: index.html sin <title>$WEB_TITLE</title>" >&2
fi

# 4. Reemplazar la versión anterior (solo index.*).
rm -f "$OUT"/index.*
cp "$STAGE"/index.* "$OUT"/

echo "== archivos en $OUT"
for f in $(cd "$OUT" && ls); do
	n=$(wc -c <"$OUT/$f" | tr -d ' ')
	awk -v f="$f" -v n="$n" 'BEGIN { printf "  %-32s %10d B %8.2f MB\n", f, n, n / 1048576 }'
done
echo "== listo"
