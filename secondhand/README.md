# Secondhand Stars

**Un prototipo chico y jugable:** una tienda de chatarra y reparaciones en un puerto espacial del desierto, en 2.5D (estilo HD-2D, como Midnight Cauldron) hecho en Godot 4.7. El juego está en inglés; esta documentación, en español.

Se juega en el navegador: https://vicentegm123.github.io/dead-air/secondhand/web/

Cada noche, pedazos de un viejo astillero en órbita caen sobre el planeta desierto **Saffra** como estrellas fugaces (la *starfall*). Al amanecer, los chatarreros los venden en el mercado. **Nell**, una mecánica joven, compra la chatarra, la arregla en su banco y la vende de segunda mano a los alienígenas y robots del puerto de **Rustwater**, en su tienda **The Secondhand Star** (un cartel con forma de estrella, remendado). La acompaña **Kettle**, un robot con forma de tetera de cobre que silba vapor cuando Nell acierta.

## La meta: 3 días, 300 créditos

El prototipo dura **3 días de juego** (unos 15-20 minutos). El casero de Rustwater quiere **300 créditos** de cuota del muelle (*dock dues*) al final del día 3. La barra **DUES** de arriba muestra cuánto falta. Al terminar el día 3 sale la pantalla final con el resumen y «Thanks for playing the prototype»: pagada o no, se puede jugar otra vez (**Play again**).

Con un juego ordenado la cuota se paga con algo de margen; si se juega apurado (aceptar el primer precio, adivinar las piezas, dejar que la gente se vaya de la fila) queda corta por unas decenas de créditos. El día 1 es un tutorial tranquilo: el reloj no corre hasta que Nell entrega la primera reparación, y Kettle explica cada paso del banco.

## Cómo se juega

- **Mañana (sin reloj): el Starfall Market**, la calle frente a la tienda.
  - **Raker's pods** (el puesto del Raker, con la tortuga de las dunas): cápsulas de chatarra cerradas. Solo se sabe el peso (las pesadas traen más piezas) y si suenan (las que traquetean suelen esconder algo roto). El precio se **regatea**.
  - Al comprar una, se abre (**Crack it open**): 2-3 piezas van al cajón y a veces sale un objeto roto, que se puede **reacondicionar** en el banco y vender.
  - **Mags's parts**: piezas a precio fijo (4-7 créditos).
  - La puerta de la tienda: **Open shop**.
- **Día (5 minutos reales, de 9 AM a 6 PM):** los clientes entran y hacen fila dentro de la tienda (hasta 4), cada uno con su reloj de arena de paciencia. En el **mostrador** (**Counter**) cada cliente:
  - trae algo roto y cuenta qué le pasa: **Repair it** (o **Fix him**, si es Clatter, el robot viejo que viene a arreglarse a sí mismo). Nell lo lleva al banco mientras el cliente espera; paga según las estrellas y la rapidez;
  - o quiere comprar algo que funcione: se vende del estante de lo reacondicionado, **regateando** (si no hay nada que le sirva: **Sorry, none**).
  - Kettle sirve **té** una vez por día (**Tea**, en su rincón): la fila recupera paciencia.
  - Con la tienda vacía, el banco reacondiciona lo roto de las cápsulas (**Refurbish**).
  - A las 6 PM se cierra: quien está en el mostrador todavía se atiende y la fila se va.
- **Noche:** el libro de cuentas (**ledger**: reparaciones, ventas, créditos, piezas, paciencia perdida, reputación, la cuota) y la lluvia de chatarra por la ventana (las cápsulas de mañana). El cartel de la estrella enciende una punta por cada buen día.

### El banco de reparación (el corazón del juego, 20-40 segundos por arreglo)

1. **Diagnose (diagnosticar):** la nota del cliente dice el síntoma («It crackles and hisses»). Tres herramientas: **Listen** (el sonido en la pantalla), **Tap** (la pieza floja traquetea) y **Scan** (el calor). Cada familia tiene su herramienta mejor: la radio se escucha, el robot de bolsillo se golpea (y habla), el propulsor se escanea. Se elige la pieza mala entre las 4; equivocarse cuesta tiempo y Kettle dice «hmm», acertar lo hace silbar.
2. **Swap (cambiar):** la pieza nueva sale del cajón. Si no hay repuesto, un **parche** (una estrella menos): nunca se bloquea.
3. **Solder (soldar):** pasar el soldador por los puntos en orden; la prolijidad da estrellas.
4. **Test (probar):** una aguja que barre; pararla en el verde.

Resultado: de 0 a 3 estrellas, pago y reputación.

### Regatear

Para comprar cápsulas y para vender del estante. El otro pide un precio; se contesta con una de tres contraofertas (**LOW**, **FAIR**, **FIRM**) o se acepta (**Accept**). La barra de ánimo (**Mood**) reacciona. Cada especie tiene su «seña»:

- **Gorrum** (un Hornback enorme, con poncho) se ofende si se le acepta rápido: siempre hay que contraofertar una vez.
- **Zib** (un Quill de cuatro brazos, apurado): cuando miente, la cresta le parpadea; deja propina por rapidez.
- **Mother Oona** (una Glimmerfolk con cabeza de cúpula de gelatina): primero propone **trueque**, piezas en vez de créditos.
- **Pipip** (un Burrower minero, tímido) paga en monedas chicas.
- **Rook Varga** (un piloto): su paciencia sigue la hora de salida de su nave.
- **Clatter** (un robot de servicio viejo): viene solo a que lo arreglen y paga con sus ahorros.
- **El Raker** (un chatarrero de cara de salamandra): cuando el precio es bueno, saca la lengua.

## Controles

| Teclado y ratón | Qué hace |
|---|---|
| `A` / `D` o flechas, o clic en el suelo | caminar |
| Clic en un lugar (puesto, mostrador, banco, cajón, estante, té, puerta) | Nell camina hasta allí y lo usa |
| `E`, `Intro` o `Espacio` | usar el lugar donde está Nell (el aviso dice qué hace: «[E] Repair», «[E] Buy pods», «[E] Open shop»…) |
| `Esc` | menú (volumen de música y sonido, volver al título); cierra o cancela la ventana abierta |
| Diálogos | `E` / `Intro` la opción principal, `1`-`9` las demás, `Esc` cancelar |
| Puesto de Mags | `1`-`9` compran la pieza de esa casilla |
| Regateo | `1` / `2` / `3` contraofertas LOW / FAIR / FIRM, `Intro` aceptar, `Esc` irse; con el trueque de Oona, `1` aceptar las piezas, `2` pedir créditos |
| Cápsula | `E` o `Espacio` abrirla y guardar lo que trae |
| Banco | `L` / `T` / `S` Listen / Tap / Scan, `1`-`4` elegir la pieza, `E` cambiar, `P` parchar, flechas o `WASD` (o el ratón) para soldar, `Espacio` o clic para parar la aguja, `Intro` terminar, `Esc` abandonar el arreglo (pregunta antes) |
| Título | `E` / `Intro` la opción principal, `N` partida nueva, `S` ajustes |

| Mando (Xbox y compatibles) | Qué hace |
|---|---|
| Stick izquierdo o cruceta | caminar (con una ventana abierta, mueven el cursor del mando) |
| `A` | interactuar (como `E`); en una ventana, tocar donde está el cursor o avanzar |
| `B` | volver / cerrar (como `Esc`) |
| `X` | como `Espacio` (p. ej. parar la aguja del banco) |
| `LB` / `RB` | mostrar el cursor y saltar a lo tocable anterior / siguiente (lugares, botones, piezas) |
| `Menu` | menú |

Los avisos cambian solos según el aparato: con el mando dicen «[A] Repair». En el navegador el sonido empieza con el primer clic o tecla (los navegadores no cuentan el mando); la esquina de la pantalla lo avisa.

La partida se guarda sola cada mañana y al abrir la tienda: **Continue** sigue desde ahí (en el navegador se guarda en el propio navegador).

## Qué tiene y qué no tiene todavía

**Tiene:** el título, la introducción (tres líneas sobre el cielo de noche), las tres mañanas del mercado (cápsulas con regateo, piezas de Mags), la tienda con fila, paciencia, reloj y cierre, el banco completo (4 pasos, 3 familias: radio, robot de bolsillo y propulsor de hoverbike; 9 piezas; 12 fallas con su síntoma), el regateo con las señas de cada especie, el trueque de Oona, el té de Kettle, el estante de lo reacondicionado, las cuentas de cada noche, la pantalla final, guardar y continuar, música y sonidos originales, teclado, ratón y mando.

**Todavía no (es un prototipo):**

- Solo 3 días; no hay mejoras de la tienda, historia más allá de la introducción ni más clientes que los 6 del elenco.
- Las cápsulas se abren en el momento de comprarlas (no se pueden guardar para abrirlas en el banco).
- Clatter se repara sobre la misma vista abierta del robot de bolsillo (no tiene un dibujo propio de su pecho abierto).
- Los «extras» de los encargos (pintura, bocina más fuerte…) están previstos en los datos pero no se usan.
- El balance se midió con jugadores automáticos (bots «bueno» y «torpe»); falta probarlo con más personas.
- Nadie escuchó todavía el audio con oídos de persona: los niveles y los bucles están medidos, el gusto no.
- Pensado para computador (1280x720 o más); no está adaptado a pantallas táctiles.

## Abrirlo en Godot

1. Instala **Godot 4.7** (versión estándar, no .NET).
2. Godot → **Importar** → `game/project.godot`. La primera vez tarda unos segundos en importar las imágenes. **F5** para jugar.

Usa el renderizador **Compatibility** (OpenGL / WebGL 2), el mismo de la versión web.

Pruebas sin ventana (desde `game/`): `godot --headless --path . -- --demo=smoke` (arranca y recorre las pantallas), `--demo=savetest` (guardar y cargar), `--demo=benchtest` (el banco), `--demo=autoplay --days=3 --bot=good` (un jugador automático juega los 3 días por el flujo real; también `perfect` y `sloppy`).

## Versión web (exportar)

```
GODOT=/ruta/a/godot sh secondhand/tools/export_web.sh
```

Sin argumentos usa `secondhand/game` y deja el resultado en `secondhand/web` (también acepta `export_web.sh <proyecto> <salida>`). Necesita Godot 4.7 con las plantillas de exportación web. Usa el preset «Web» (Compatibility / WebGL 2, sin hilos: funciona en GitHub Pages), arregla el audio web de Godot 4.7 en `index.js` (los bucles de música y ambiente se repiten sin cortes aunque el juego vaya lento), pone «Secondhand Stars» como título de la pestaña y no exporta si algún script usa `AudioServer.add_bus()`, que en la web deja el juego mudo. La página usa solo rutas relativas: funciona en `…/dead-air/secondhand/web/`.

## Dónde cambiar cosas

| Quiero cambiar… | Archivo (en `game/`) |
|---|---|
| La cuota (300), los días, la hora de apertura y cierre, el largo del día, los créditos y piezas del comienzo | `scripts/data.gd` (`DUES_GOAL`, `DAYS`, `OPEN_MIN`, `CLOSE_MIN`, `DAY_SECONDS`, `START_CREDITS`, `START_PARTS`, `START_SHELF`) |
| Quién llega cada día, a qué hora y qué trae o quiere | `scripts/data.gd` (`SCHEDULE`) |
| Paciencia de la fila y del mostrador, el té, la propina de Zib | `scripts/data.gd` (`LINE_PATIENCE`, `COUNTER_PATIENCE`, `TEA_BOOST`, `SPEED_TIP`…) |
| Personajes, especies y lo que dicen | `scripts/data.gd` (`CAST`, `SPECIES`, `LINES`, `MARKET_LINES`, `SELF_REPAIR` de Clatter) |
| Introducción, consejos del tutorial, frases de Kettle | `scripts/data.gd` (`INTRO`, `TIPS`, `KETTLE_TALK`, `KETTLE_TEA`) |
| Objetos, piezas, fallas y síntomas | `scripts/bench_data.gd` (`ITEMS`, `PARTS`, `FAULTS`, `SYMPTOM_LINES`) |
| Pistas de las herramientas, lo que dice el robot, lo que dice Kettle en el banco | `scripts/bench_data.gd` (`TOOL_CLUES`, `BOT_TALK`, `KETTLE`, `KETTLE_TUTORIAL`) |
| Pago de las reparaciones (estrellas y rapidez), precios de venta, puntaje del banco | `scripts/bench_data.gd` (`ITEMS` `repair_pay` / `sale_base`, `REPAY_Q`, `REPAY_SPEED`, `SCORE`) |
| Reglas del regateo por especie y sus frases | `scripts/bench_data.gd` (`HAGGLE`, `HAGGLE_LINES`, `MOODS`) |
| Cápsulas: precio, cuántas piezas, cuántas traen algo roto | `scripts/bench_data.gd` (`POD_BASE`, `POD_PARTS`, `POD_BROKEN`) y `scripts/data.gd` (`PODS_PER_DAY`, `DAY1_PODS`) |
| El estado de la partida, guardar y cargar | `scripts/game.gd` |
| El flujo: título, mañana, abrir, mostrador, banco, entrega, noche, final | `scripts/main.gd` |
| La fila, la paciencia y los clientes que entran y salen | `scripts/shop_day.gd` |
| La tienda en 3D (lugares, luces, ventana, estante, rincón del té) | `scripts/world/shop_world.gd` (`STATIONS`, `QUEUE_SPOTS`) |
| La calle y el mercado (puestos, casas, naves, el anillo del cielo) | `scripts/world/street_world.gd` |
| Piezas comunes de los escenarios, caminar, los personajes | `scripts/world/set_kit.gd`, `scripts/world/walker.gd`, `scripts/world/actor.gd` |
| El banco (pantalla y pasos) | `scripts/ui/bench_ui.gd` y sus ayudantes `scripts/ui/bench_*.gd` |
| El regateo / la cápsula | `scripts/ui/haggle_ui.gd` / `scripts/ui/pod_ui.gd` |
| El HUD, los avisos «[E] …», los mensajes | `scripts/ui/hud.gd`, `scripts/ui/ui_kit.gd` |
| Diálogos del mostrador, Mags, cajón, estante, menú | `scripts/ui/dialogs.gd` |
| Título, introducción, cuentas de la noche, pantalla final | `scripts/ui/screens.gd` |
| Mando | `scripts/ui/pad_cursor.gd` |
| Música y sonidos (qué suena dónde, volumen) | `scripts/sfx.gd` |
| El efecto de maqueta (desenfoque arriba y abajo), viñeta y color | `shaders/hd2d_post.gdshader` y `POST_*` en `scripts/main.gd` |

Todo el arte está en `game/assets/` y el audio en `game/audio/`. Se puede reemplazar cualquier PNG por otro con el mismo nombre y tamaño (los personajes: cuadros de 64x96, mirando a la derecha).

## Generadores de arte y audio

En `game/tools/arte/` están los scripts de Python que hicieron todo el pixel art, las texturas, el logo, la música y los sonidos (Godot no los exporta). Necesitan `pillow`, `numpy`, `scipy` y, para el audio, `ffmpeg`.

- **Arte:** `python3 ss_build_all.py --out <carpeta> [--game ../..]` regenera todo (personajes, props, objetos y piezas con su `manifest.json`, interfaz, texturas, logo) y, con `--game`, lo copia al proyecto con las rutas que usa el juego. Por partes: `ss_chars.py` y `ss_bots.py` (el elenco, Kettle, Clatter y la tortuga; usan el kit de personajes `c64*.py` / `chars64.py` de Midnight Cauldron), `ss_items.py` (objetos, piezas, cápsulas, la vista abierta del banco), `ss_world.py` y `ss_props.py` (texturas y props de la tienda y la calle, naves, cielo), `ss_ui.py` (placas, pantallas, etiquetas, iconos), `ss_logo.py` (el logo), `ss_emotes.py` (emociones e icono), `fonts_ss.py` (recorta las fuentes del juego). Después de cambiar imágenes: `godot --headless --path game --import`.
- **Audio:** `python3 make_audio.py ../../audio` genera los 18 `.ogg` (3 músicas, 2 ambientes, 13 efectos) con síntesis propia (`ss_audio.py`; `music_audio.py`, `amb_audio.py`, `sfx_audio.py`) y los copia al juego. Las músicas y ambientes son bucles sin costura. `levels.py` y `mixcheck.py` miden niveles y mezcla; `game/tools/audio_check.gd` comprueba en Godot que todo carga y hace bucle.

## Fuentes y licencias

- **Inter** (textos de la interfaz), de The Inter Project Authors: SIL Open Font License 1.1 (`game/assets/fonts/OFL-Inter.txt`).
- **Caveat** (la letra a mano de notas y etiquetas), de The Caveat Project Authors: SIL Open Font License 1.1 (`OFL-Caveat.txt`).
- **Secondhand Mono** (las pantallas ámbar): un subconjunto de Liberation Mono Bold, renombrado como pide la licencia: SIL Open Font License 1.1 (`OFL-SecondhandMono.txt`).
- **Secondhand Symbols** (★ ✓ ← → …): un subconjunto de DejaVu Sans Bold, licencia Bitstream Vera / DejaVu (`LICENSE-SecondhandSymbols.txt`).
- Solo para dibujar el logo (no van en el juego): **Saira Stencil One** y **Bungee**, SIL Open Font License 1.1 (`game/tools/arte/fonts/`).
- Pixel art, texturas, logo, música y efectos de sonido: originales, generados por código para este proyecto. El kit de personajes, el efecto HD-2D, el mando y el audio web vienen de Midnight Cauldron, del mismo estudio.
