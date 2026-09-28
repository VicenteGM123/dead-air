# tools/audio — render offline del sonido de DEAD AIR

La versión web sintetiza todo el sonido en vivo con WebAudio (`src/audio/sfx.js`, `src/audio/music.js`). El port a
Godot reproduce archivos: este script ejecuta **las recetas originales, sin modificarlas**, sobre el
`OfflineAudioContext` de [`node-web-audio-api`](https://github.com/ircam-ismm/node-web-audio-api) y escribe Ogg Vorbis
(con [`wasm-media-encoders`](https://github.com/arseneyr/wasm-media-encoders)) en `godot/assets/audio/`, más
`godot/assets/audio/index.json`, que lee `godot/scripts/audio/audio.gd`.

## Uso

```sh
npm install            # instala las devDependencies (node-web-audio-api, wasm-media-encoders)
npm run audio          # = node tools/audio/render.mjs   (≈10 min, ≈16 MB)
```

Opciones:

| opción | efecto |
|---|---|
| `--only=id,id,…` | re-renderiza solo esos cues (y fusiona el `index.json` existente); `music` = los estados musicales |
| `--no-sfx` / `--no-music` | salta cues+loops+partes / estados musicales |
| `--quick` | una sola variación por cue (pruebas) |
| `--wav` | WAV PCM 16 bit en vez de Ogg (Godot usa lo que diga `index.json`) |
| `--q=N` | calidad Vorbis (−1…10; por defecto 4 para SFX, 5 para música) |
| `--jobs=N` | renders en paralelo (por defecto 6) |

`Math.random` se sustituye por un generador con semilla por archivo: dos ejecuciones producen lo mismo.
Después de renderizar, abrir el proyecto de Godot (o `godot --headless --import`) importa los archivos nuevos.

## Qué se carga

* `src/audio/sfx.js` tal cual (`synth` + `SFX_CUES`).
* `src/audio/music.js` tal cual, cargado desde una URL `data:` con su única importación (`./audio.js`) apuntando a
  `sfx.js` y exportando además sus partes privadas (`Player`, las canciones, `plate`, `clack`…).
* los cues que `src/game/wonder.js` registra en `_registerCues()` (el cuerpo del método se evalúa tal cual).

La tabla final es la de `audio.js`: `SFX_CUES`, luego `MUSIC_CUES` (bus por defecto `music`), luego los de wonder
(bus `sfx`).

## Qué se renderiza

Todo a 44,1 kHz, **a nivel de voz**: la salida de la receta tal como entra en la cadena de la voz — después del
filtro de altavoz de TV cuando el cue se oye por una tele (HP 300 Hz, pico +3 dB a 2,2 kHz, LP 4 kHz, saturación
suave, ×1,35), antes de volumen, panner/distancia, bus, reverb de área, duck y cadena master (eso lo hace
`audio.gd` en vivo). Los stings musicales incluyen su envío a la reverb *plate* de la música (`wet()`).

* `sfx/<id>/v<k>[t]_p<tono>_<n>.ogg` — cada id de cue. Por cue:
  * **variaciones aleatorias** `n`: 1 si la receta es determinista, 2 si solo varía el ruido, 4 (6 para voces muy
    repetidas: gruñidos, golpes, risitas…) si usa `rnd`/`pick`;
  * **variantes de parámetro** `v<k>` (tabla `VARIANTS`): `upgraded` (disparos), `rhythm` (announcer_wahwah: los
    ritmos de los power-ups y de los patrocinadores), `base` (hurt_grunt: voz de cada héroe), `dur` (tone_1khz,
    tele_tick, uplink_motor, crowd_*…), `syllables` (boss_voice), `flip` (pu_sweeps_week), `claps`
    (ee_applause_near), `auto` (telly_surf_arp); `PARAM_DEFAULTS` indica el valor por defecto de cada receta;
  * **tonos** `p<tono×100>`: si la receta lee `opts.pitch` (= `rate · 2^(detune/1200)`), los tonos que usan las
    llamadas del juego (tabla `RATE_USE`, sacada de todos los `audio.play(…, { rate })` de `src/`); los rangos
    aleatorios se cubren con pasos de ≤ 8 %. En Godot se elige el tono renderizado más cercano y el resto se aplica
    como `pitch_scale`;
  * sufijo `t`: render con el filtro de TV (cues con `tv` estático y los que alguna llamada reproduce por una tele,
    `TV_EXTRA`).
* `loops/<id>[_tv].ogg` — cada cue que el juego usa con `audio.loop()` (`LOOPS`): renderizado en modo bucle igual que
  `audio.js` (las recetas infinitas con sus secuenciadores; las de un disparo se re-disparan una tras otra) y cortado
  en `[intro | bucle]` con la costura en fundido cruzado; la longitud del bucle es un número entero de periodos de
  sus osciladores / LFO / patrones cuando es posible.
* `music/<estado>[_<stem>].ogg` — cada estado de `music.js` (`title`, `select:<héroe>`, `round`, `intermission`,
  `hullabaloo`, `boss`, `credits`, `morning`) con el `Player` original: `[intro (≥ 3 s, en compás) | bucle de N
  compases]`. Las capas adaptativas son *stems* alineados a la muestra (misma interpretación aleatoria): `round` /
  `morning` = `base` + `clav` (entra con > 16 zombis), `boss` = `base1/2/3` (patrón de cada fase) + `p2` + `p3`.
  También `music/select_clack.ogg`.
* `parts/…` — notas sueltas de los cues que el juego toca nota a nota: `telly_surf_arp` (`step()`, bajo slap + hat,
  por el altavoz de Telly), `toy_xylophone` (`opts.notes`), y la sinusoide de 440 Hz de `ee_tracking_tones`
  (`setDistance(d)` cambia su `pitch_scale`).

## index.json

```jsonc
{
  "version": 1, "sampleRate": 44100, "format": "ogg",
  "cues": { "<id>": {
      "bus": "sfx|ambience|tv|ui|music", "tv": false, "zombie": false, "range": null, "ref": null, "wet": null,
      "limit": 10, "gap": 0.03, "loopable": false, "music": false, "pitch": true,
      "reads": ["pitch", …],               // opts que lee la receta
      "params": ["upgraded", …], "defaults": { … },
      "inherent": false,                   // receta infinita (solo loop)
      "variants": [ { "k": "upgraded=1", "o": { … }, "tv": false,
                      "sets": [ { "p": 1, "f": [ { "f": "sfx/…ogg", "e": 0.12, "l": 0.2, "k": 1.2 } ] } ] } ],
      "loop": { "f": "loops/…ogg", "s": 0.5, "e": 8.6, "tv": false } } },
  "parts": { … },
  "music": { "states": { "<estado>": { "fade", "delay", "bpm", "barDur", "beatDur", "bars",
                                        "stems": { "<stem>": { "f", "s", "e" } } } }, "clack": { "f" } }
}
```

`e` = tiempo de fin que devuelve la receta (lo que `audio.js` usa para `playing`, límites y re-disparos),
`l` = duración del archivo, `k` = ganancia a re-aplicar (solo si el render superaba ±1), `s`/`e` de bucles = inicio /
fin del bucle en segundos.

## Añadir o cambiar un sonido

Editar la receta en `src/audio/*.js` y volver a ejecutar `npm run audio -- --only=<id>` (o `--only=music`). Un cue
nuevo que el juego llame con parámetros nuevos (otro `rate`, otra `dur`…) se añade a `RATE_USE` / `VARIANTS`; si
se usa con `audio.loop()`, a `LOOPS`.
