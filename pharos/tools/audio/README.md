# Audio procedural de PHAROS

Todo el audio del juego (efectos, música y ambientes) se **sintetiza con código**: numpy puro,
sin muestras, sin descargas, sin bancos de sonido. Es obra original del proyecto (licencia limpia).
El render es **determinista**: las semillas salen del nombre de cada sonido (crc32) y ffmpeg
codifica en modo `bitexact`, así que repetirlo produce exactamente los mismos bytes
(con las mismas versiones de numpy / ffmpeg / libvorbis).

## Regenerar

Desde la raíz del repositorio:

```bash
python3 pharos/tools/audio/render_all.py
```

Tarda ~1 min con 4 núcleos y escribe `pharos/game/assets/audio/{sfx,music,amb}/*.ogg`
(OGG Vorbis `-q:a 5`, 44,1 kHz). Opciones:

| Opción | Uso |
|---|---|
| `--only coin day amb/sea` | regenera solo esos nombres (`day` = música y ambiente; `amb/day` solo el ambiente) |
| `--png DIR` | espectrograma + forma de onda + espectro medio de cada fichero (control de calidad) |
| `--wav DIR` | copia WAV de cada render |
| `--jobs N` | procesos en paralelo (por defecto 4) |
| `--list` | lista los ficheros que genera |

Requisitos: Python ≥ 3.10, **numpy**, **ffmpeg con libvorbis**. Pillow solo para `--png`.
No hace falta scipy. `analyze.py fichero.ogg --png DIR` analiza cualquier OGG ya generado.

## Módulos

| Fichero | Contenido |
|---|---|
| `dsp.py` | núcleo: envolventes, biquads RBJ aplicados por FFT, ruido espectral variable en el tiempo, reverb por convolución con IR sintética, paneo, limitador |
| `instruments.py` | lira (Karplus–Strong), aulós (aditivo, vibrato, portamento, aliento), pads de cuerdas/coro (formantes), tímpano, campanas, metales, bordón, platillo |
| `sfx.py` | una receta por efecto (registro `SFX`) |
| `music.py` | composición escrita como datos (acordes, arpegios, melodías) y mezcla por buses |
| `ambience.py` | mar, día, noche, fuego |
| `analyze.py` | estadísticas (pico, RMS, DC, energía > 4/8 kHz, salto en el punto de bucle) y PNG |
| `render_all.py` | orquesta todo y codifica a OGG |

Para cambiar un sonido: edita su receta y ejecuta `--only nombre --png /tmp/png` para revisarlo.

## Niveles

- **SFX**: pico −3 dBFS. Excepciones intencionadas: `ui_select`/`ui_back` −4, `ui_move` −6,
  `footstep` −8 y `gull` −10 dBFS (suaves/lejanos por diseño).
- **Música en bucle**: RMS ≈ −20 dBFS (`boss` −19, `title` −20,5), picos ≤ −1 dBFS.
  **Stingers**: RMS activo ≈ −18/−19 dBFS.
- **Ambientes**: RMS ≈ −26 dBFS (`night` −27, `fire` −24, mono).
- Energía por encima de 8 kHz contenida en todo (filtrado suave; nada estridente).

## Bucles (importante en Godot)

Activar **Loop** en la importación (offset 0) de: `music/day`, `music/night`, `music/boss`,
`music/title`, todos los `amb/*` y `sfx/cat_purr`. Se renderizan de forma **circular**: las colas
de notas y de reverb que pasan del final se pliegan sobre el principio, el ruido es periódico y la
reverb es convolución circular, así que el bucle es continuo y sin clic (comprobado tras decodificar
el OGG: longitud exacta en muestras y sin salto en la unión).

## Ficheros

### `sfx/` (mono)

| Fichero | s | Descripción |
|---|---|---|
| `swing_1`, `swing_2` | 0,30 | barrido de lanza (ruido de banda con Doppler, silbido tenue) |
| `swing_3` | 0,40 | barrido pesado (más grave, "woom" sub) para el 3er golpe del combo |
| `bash` | 0,5 | golpe de escudo: thump grave + clang de bronce corto |
| `dodge` | 0,35 | tela que vuela + gravilla |
| `hit_1..3` | 0,25 | lanza contra sombra: impacto redondo + siseo de humo |
| `hero_hurt` | 0,3 | impacto apagado + tintineo de armadura |
| `hero_down` | 1,0 | caída pesada + escudo que baila en el suelo |
| `lightning` | 2,0 | rayo de Zeus: chasquido + trueno que rueda |
| `favor_ready` | 0,8 | campanillas ascendentes (Re mayor) con brillo |
| `enemy_spawn` | 1,2 | agua que sube y borbotea + silbido fantasmal ascendente |
| `enemy_die` | 0,6 | humo que se disipa, tono descendente |
| `ker_screech` | 0,5 | chillido espectral aireado |
| `cyclops_stomp` | 0,8 | pisotón muy grave + retumbo y polvo |
| `cyclops_roar` | 1,5 | gruñido grave con formantes |
| `hydra_roar` | 2,5 | rugido de tres cabezas + siseo + retumbo |
| `hydra_spit` | 0,5 | salivazo húmedo + whoosh |
| `orb_hit` | 0,5 | impacto de magia oscura |
| `arrow_shoot` / `arrow_hit` | 0,3 / 0,2 | cuerda del arco + flecha / golpe seco en madera |
| `zap` | 0,4 | descarga eléctrica suave |
| `structure_hit` / `structure_break` | 0,25 / 1,2 | golpe en madera/piedra / derrumbe con escombros |
| `soldier_hit` | 0,2 | clank metálico pequeño |
| `coin` | 0,25 | una moneda de oro (corta, pensada para repetirse con variación de tono) |
| `income` | 1,2 | cascada de monedas |
| `build_done` / `upgrade` | 1,0 | golpe de madera + acorde de lira ascendente (upgrade más brillante) |
| `ui_move` / `ui_select` / `ui_back` | 0,08 / 0,25 / 0,2 | tic suave / pulsación de lira / pulsación más grave |
| `blessing` | 2,0 | coro divino en Re mayor + campana |
| `cat_purr` | 2,0 | ronroneo (bucle: 50 pulsos a 25 Hz, respiración) |
| `cat_meow` | 0,4 | "mrrp" corto con trino |
| `splash` | 0,8 | chapuzón |
| `gull` | 0,6 | gaviota lejana |
| `night_horn` | 2,5 | caracola/salpinx (Re → La) que anuncia la noche |
| `footstep` | 0,12 | paso muy suave en tierra/gravilla |

### `music/` (estéreo)

| Fichero | s | Tonalidad / tempo | Armonía e instrumentación |
|---|---|---|---|
| `day` | 68,6 (bucle) | Re dórico, 84 BPM, 4/4, 24 c. | A: Dm9–G/D (IV mayor dórico sobre pedal de Re) ×2 → Fmaj7–C/E–G–Am7sus4; A′ igual → Fmaj7–G–Am7–Asus4; B: bajo descendente C–G/B–Am7–G–Fmaj7–C/E–G6–Asus4 con melodía de lira. Arpegios de lira, pad de cuerdas (+ coro "u" desde c. 9), bajo de lira, latido de tímpano suave desde c. 9 |
| `night` | 57,6 (bucle) | Re frigio, 100 BPM, 4/4, 24 c. | Vamp Dm–Dm–E♭–Dm (i–♭II), luego B♭–Cm–E♭–Dm y Gm–Cm–E♭–E♭ → Dm (cadencia frigia en el bucle). Bordón Re/La, tímpano 3+3+2, ostinato de lira apagada con el ♭2 (Mi♭), pad oscuro, frases de aulós (lamento La–Si♭–La–Sol–Fa–Mi♭–Re) y respuesta de lira |
| `boss` | 48,0 (bucle) | Re frigio, 110 BPM, 4/4, 22 c. | Intro Dm–Dm–E♭–Dm–E♭–E♭; B Dm–E♭–Cm–Dm–B♭–Cm–E♭–Dm (+ coro "a"); C B♭–Cm–Dm–Dm–B♭–Cm–E♭–E♭ (+ aulós agudo). Ostinato en semicorcheas, gran tambor + tímpano con redobles y platillos hacia cada sección, metales graves en swell cada 2 compases |
| `title` | 61,7 (bucle) | Re menor (eólico/dórico), 70 BPM, 3/4, 24 c. | Dm9–B♭maj7–Fadd9–Cadd9 / Dm–B♭maj7–Gm7–Asus4→A / B♭maj7–F/A–Gm7–Asus4→A (2 c. por acorde). Lira lenta, coro "o/a" + cuerdas graves, campana lejana cada 4 c., melodía de soprano desde c. 9 |
| `stinger_dawn` | 4 | Re mayor | acorde Re add9 (cuerdas + coro), glissando de lira en pentatónica de Re, campanas La/Re/Fa♯ |
| `stinger_victory` | 7 | Re mayor | redoble + platillo → B♭ – C – D (♭VI–♭VII–I) con metales, coro y línea Re–Mi–Fa♯; arpegio de lira y campanas |
| `stinger_defeat` | 5 | Re menor | bordón; coro "u" Gm/B♭ → Asus4→A → Dm; el aulós desciende La–Sol–Fa–Mi–Re; campana grave final |

### `amb/` (bucles)

| Fichero | s | Descripción |
|---|---|---|
| `sea` | 30 (estéreo) | cinco olas suaves que crecen, rompen y se retiran con espuma, sobre mar de fondo |
| `day` | 30 (estéreo) | brisa ligera con hojas + tres cigarras suaves (banda estrecha ~4–5 kHz, filtrada) |
| `night` | 30 (estéreo) | viento suave + cuatro grillos a distintas distancias + grillo arborícola lejano |
| `fire` | 8 (mono) | crepitar de hoguera: rumor grave, chasquidos, chispas y estallidos de resina |
