# DEAD AIR — versión Godot

Migración 1:1 del juego web (`src/`, Three.js) a **Godot 4.7**. Todo el código del juego está en GDScript y todos
los assets 3D se generan en **Blender** con scripts de Python (`../blender/`). El sonido se renderiza a partir de las
recetas originales de audio (`../tools/audio/`).

## Descargar (Windows / Linux)

Builds de escritorio exportadas, listas para jugar sin instalar Godot y **con multijugador online**
(ver [`builds/README.md`](../builds/README.md)). Cada ZIP va partido en dos trozos (GitHub no admite archivos de más
de 100 MB): descarga los dos, únelos y descomprime.

- **Windows 10/11 (64 bits)**, 169 MB:
  [trozo 1](https://github.com/VicenteGM123/dead-air/raw/main/builds/DeadAir-windows.zip.001) +
  [trozo 2](https://github.com/VicenteGM123/dead-air/raw/main/builds/DeadAir-windows.zip.002) +
  [UNIR-windows.bat](https://github.com/VicenteGM123/dead-air/raw/main/builds/UNIR-windows.bat)
  (o `copy /b DeadAir-windows.zip.001+DeadAir-windows.zip.002 DeadAir-windows.zip`). Ejecuta `DeadAir.exe`; si
  SmartScreen avisa: **Más información → Ejecutar de todas formas**.
- **Linux x86_64**, 159 MB:
  [trozo 1](https://github.com/VicenteGM123/dead-air/raw/main/builds/DeadAir-linux.zip.001) +
  [trozo 2](https://github.com/VicenteGM123/dead-air/raw/main/builds/DeadAir-linux.zip.002), luego
  `cat DeadAir-linux.zip.0* > DeadAir-linux.zip`, descomprime y `./DeadAir.x86_64`.

Multijugador: con **código de sala** (por defecto, sin abrir puertos, también contra el navegador) o por **IP / LAN**
(puerto **UDP 31313** abierto en el anfitrión, o Tailscale / ZeroTier). Necesita una gráfica con Vulkan.

Para regenerarlas: presets "Windows Desktop" y "Linux" de `export_presets.cfg` (`godot --headless --export-release
"Linux" DeadAir.x86_64`; exporta desde una copia del proyecto, no desde el repo, para no reimportar los assets).

## Cómo jugar

1. Instala **Godot 4.7** (versión estándar, no hace falta la de .NET).
2. Abre Godot, pulsa **Importar** y elige `godot/project.godot`. La primera vez Godot importa todos los assets
   (unos minutos).
3. Pulsa **F5** (Ejecutar proyecto). Arranca igual que la versión web: PLEASE STAND BY → título → selección de
   personaje en el dial de la tele → partida.

Los controles son los mismos que en la web (ver el `README.md` principal), con teclado + ratón o mando de Xbox.

### Parámetros de prueba

Los parámetros de URL de la versión web (`?test=1&char=roxy&power=1`…) se pasan después de `--`:

```
godot --path godot -- test=1 char=roxy power=1 doors=1 god=1 round=10
```

O desde el editor: *Proyecto → Configuración → application/run/da_params* (`test=1 god=1`, separados por espacios).

| Parámetro | Efecto |
|---|---|
| `test=1` | salta los menús y empieza la partida directamente |
| `char=<duke\|skip\|roxy\|penny>` | héroe |
| `god=1` | invulnerable |
| `power=1` / `doors=1` | estación ya encendida / todas las puertas abiertas |
| `round=N`, `points=N`, `seed=N` | ronda inicial, puntos, semilla |
| `nozombies=1` | sin zombis |
| `shot=<cam_*>` | cámara fija de captura (las `cam_*` de `data/layout.json`) |
| `screenshot=/ruta.png shotafter=S` | guarda una captura tras S segundos y sale |

La API de depuración de la web sigue existiendo: `DAGame.inst.debug.teleport(...)`, `give(...)`, `spawn(...)`,
`power(true)`, `freeCam(true)`, etc. (ver `scripts/core/debug.gd`).

## Versión web (navegador)

Build de prueba publicada en https://vicentegm123.github.io/dead-air/godot-web/ (carpeta `godot-web/` de la rama
main). Se exporta con `sh godot/web/export_web.sh [carpeta]` (plantillas web de Godot 4.7.2 instaladas):

- Dos builds del motor con los mismos datos: `index.html` (preset **Web**, **con hilos**: el audio se mezcla fuera del
  hilo principal y las cargas van en segundo plano) e `index-st.html` (preset **Web ST**, sin hilos, de reserva). La
  build con hilos necesita aislamiento cross-origin (cabeceras COOP/COEP) y GitHub Pages no las envía: el shell
  `web/shell.html` registra el service worker `web/coi-sw.js` (copiado junto a `index.html`), que las añade, y recarga
  la página una vez; si no se puede (ventana privada, navegador antiguo, http) redirige a `index-st.html`. Los
  parámetros de la URL pasan al juego como en la versión JS (`index.html?hitch=150&dynres=0`).
- Como GitHub no admite ficheros de más de 100 MB, los datos van en dos paquetes: `index.pck` (todo menos
  `assets/props/*.glb`) e `index.props.pck` (los props, exportado como parche con el preset **Web Full**). El shell
  descarga los dos y `game.gd` monta el segundo (`ProjectSettings.load_resource_pack`) antes de arrancar.
- Audio: `audio/general/default_playback_type.web = Stream` (el modo "Sample" por defecto de Godot en la web no aplica
  los efectos de bus ni la automatización de volumen de `audio.gd`, y se quedaba mudo). El navegador desbloquea el
  audio con el primer clic o tecla.
- Calentamiento de shaders (`scripts/gfx/warmup.gd`): Compatibility compila cada variante de shader la primera vez que
  se dibuja, en el hilo principal (segundos de pantalla congelada en WebGL). Tras la carga, detrás del título, se
  dibuja la estación desde arriba área por área en un SubViewport pequeño, más una galería con un ejemplar de cada
  shader oculto (pools de zombis, FX, disfraces de perks, atrezo del anuncio, armas, materiales encendidos tras el
  Sign-On) bajo las combinaciones de luces, y los materiales 2D. También en escritorio (Forward+): ahí cada combinación
  nueva de shader + formato de vértice compila sus pipelines Vulkan al aparecer la primera instancia; el calentamiento
  las deja compiladas (0 compilaciones de pipelines bloqueantes en la partida) y los presets de escritorio llevan el
  *shader baker* (SPIR-V precompilado). `warm=0` lo desactiva, `warm=1` lo fuerza; nunca con `--headless`.
- Al sintonizar una partida, la pantalla pasa de la zambullida al test card **PLEASE STAND BY** con una barra de
  progreso (`scripts/ui/standby_card.gd`) mientras se dibujan los primeros fotogramas de la estación (solo con
  Compatibility; `standby=1/0`). Parámetro de diagnóstico `hitch=<ms>`: registra cada fotograma más largo que eso con
  el tiempo de script y las llamadas más costosas.
- En la web Godot solo tiene el renderizador **Compatibility** (WebGL 2). Los shaders tienen ramas
  `#if CURRENT_RENDERER == RENDERER_COMPATIBILITY` (`daIn` / `daOut` en `shaders/da_common.gdshaderinc`, decodificado
  de la vista 3D en `post` / `bloom`, cielo con Z invertida en rango -1..1) para que se vea igual que en escritorio;
  en escritorio (Forward+) no cambia nada. Diferencias: sin sombras proyectadas de la luz principal (Compatibility
  suma en sRGB las pasadas de luces con sombra y quema la imagen) y sin MSAA en los lienzos 2D.
- **MULTIPLAYER** funciona con códigos de sala (WebRTC; el modo IP / LAN con ENet/UDP no existe en el navegador) y
  QUIT no aparece (una pestaña no se puede cerrar).

## Multijugador (cooperativo online, 1-4 jugadores)

En la pantalla de título pulsa cualquier tecla: aparece el menú principal (**SINGLE PLAYER / MULTIPLAYER / OPTIONS /
CONTROLS / QUIT**). SINGLE PLAYER es el juego de siempre, sin ningún cambio.

**MULTIPLAYER**
- **NAME**: tu nombre (se guarda).
- **CONNECTION** (solo escritorio; en el navegador siempre es por código): **ONLINE · CODE** o **DIRECT IP · LAN**.
- Con **ONLINE · CODE** (por defecto):
  - **HOST GAME**: creas una sala y en la lista "Tonight's Cast" aparece en grande su código (**SHARE THIS CODE**,
    p. ej. `WZTV-4K2P`; C, el botón Y del mando o un clic lo copian al portapapeles). Pásaselo a tus amigos.
  - **JOIN GAME → ENTER CODE**: escribe el código (teclado, Ctrl+V en escritorio, o el teclado en pantalla con el
    mando). Sin letras ambiguas: no hay I, L, O, 0 ni 1.
  - Funciona igual en el navegador y en escritorio, y se pueden mezclar.
- Con **DIRECT IP · LAN** (escritorio):
  - **HOST GAME**: creas la partida. Tus amigos ven en la lista "Tonight's Cast" la dirección que tienen que usar
    (la de internet, si el router abre el puerto solo con UPnP, y la de la red local).
  - **JOIN GAME**: aparecen solas las partidas de tu red local; para una partida por internet elige ENTER ADDRESS y
    escribe la IP del anfitrión (con el mando hay un teclado en pantalla).
- **Sala de espera**: cada uno elige su héroe en el dial de la tele (cada héroe solo puede llevarlo un jugador) y lo
  sintoniza para quedar listo. Cuando todos están listos, el anfitrión pulsa START: cuenta atrás y a jugar.

**Cómo funcionan los códigos (ONLINE · CODE)**: conexión directa entre jugadores con **WebRTC** (topología en
estrella: cada invitado se conecta solo al anfitrión, que reenvía lo demás). Para encontrarse se usan servicios
públicos y gratuitos, sin cuenta: el servidor en la nube de **PeerJS** (`wss://0.peerjs.com`) y, a la vez como
respaldo, un broker **MQTT** público por WebSocket (`wss://broker.hivemq.com:8884/mqtt`); solo transportan los
mensajes de conexión (oferta / respuesta / candidatos ICE), nunca la partida. Las direcciones se descubren con los
servidores **STUN** de Google (`stun.l.google.com:19302`) y, si existe, con el relé **TURN** gratuito "Open Relay" de
Metered (`openrelay.metered.ca`, credenciales públicas). Limitaciones: si los dos jugadores están detrás de un NAT
estricto (simétrico: algunas redes móviles 4G/5G, redes de empresa o universidad, CG-NAT) y el relé TURN gratuito no
responde, la conexión falla con "COULDN'T LINK UP · A FIREWALL OR STRICT NAT?": probad otra red, o el modo DIRECT IP
con Tailscale / ZeroTier. Si los servicios públicos cambian o caen, se pueden cambiar en `project.godot`
(`dead_air/net/signal_servers`, `dead_air/net/ice_servers` como JSON) o con los parámetros `mpsignal=` / `mpice=`.
Mensajes de error: "NO SUCH ROOM" (código mal escrito o sala cerrada), "CAN'T REACH THE SIGNAL SERVER" (sin internet o
servicios caídos), "COULDN'T LINK UP" (NAT / cortafuegos), "WRONG VERSION", "LOBBY FULL", "SHOW ALREADY ON AIR".
En escritorio WebRTC lo aporta la extensión oficial **webrtc-native** (`addons/webrtc/`, Windows y Linux x86_64); el
navegador lo trae de serie.

**Jugar por IP (DIRECT IP · LAN)**: el anfitrión necesita el puerto **UDP 31313** abierto hacia su PC. El juego
intenta abrirlo solo (UPnP); si tu router no lo permite, ábrelo a mano en el router (redirección de puertos UDP 31313)
o usad una red privada virtual tipo **Tailscale**, **ZeroTier** o **Radmin VPN** y unid por la IP que os da. Todos
deben tener la misma versión del juego.

**Reglas en equipo** (al estilo de los zombis de Call of Duty):
- Puntos por jugador; cada uno paga lo suyo. Puertas, corriente, tablas de las ventanas y máquinas son compartidas.
- Potenciadores para todo el equipo (FULL REEL rellena la munición de todos, etc.).
- Si te tumban (sin Instant Replay), quedas en el suelo 30 s: un compañero te levanta manteniendo E / X junto a ti.
  Si nadie llega, quedas fuera del aire y miras a un compañero hasta la ronda siguiente, en la que vuelves con el
  revólver y tus puntos (pierdes las mejoras).
- La partida acaba si caen todos a la vez. Luego volvéis a la sala de espera.
- Más jugadores = más zombis por ronda; el jefe tiene más vida.
- La pausa no congela el juego en multijugador (LEAVE GAME para salir).

Parámetros de prueba: `mp=host` / `mp=join mpip=<ip>`, `mpname=`, `mpstart=N` (con `test=1`: el anfitrión empieza solo
cuando hay N jugadores), `mplag= mpjitter= mploss=` (simulan mala red); WebRTC: `mpnet=rtc mpcode=<código>`,
`mpsignal=peerjs:ws://127.0.0.1:9000/,mqtt:ws://127.0.0.1:8883/mqtt` (servidores de señalización propios, p. ej. el
paquete npm `peer`), `mpice=none|stun`, `mpturn=0`, `mplog=<s>` (escribe los jugadores en la consola). Código:
`scripts/net/` (red, sala, jugadores remotos; `net_rtc.gd` + `net_signal.gd` = transporte WebRTC) y los `*_net.gd` /
párrafos `MP:` de cada sistema.

## Estructura

```
godot/
  project.godot, main.tscn        el nodo raíz "Game" ejecuta scripts/core/game.gd (el bucle del juego)
  scripts/core/                   game, config (T/PAL/LAYERS), events, rng, render, materials, lights, textures,
                                  input, gamepad, rig, geo, interact, debug
  scripts/actors/                 player, camera, heroes, zombies, zombie_types, boss, types/<zombi especial>
  scripts/art/                    runtime de personajes (char_runtime, char_material, face, chars/<id>.gd)
  scripts/world/                  level, layout, collision, nav, doors, windows, rooms/<sala>.gd …
  scripts/game/                   weapons, wonder, rounds, economy, machines, screens, signon, telly, sponsors,
                                  uplink, perks, powerups, easteregg, ending
  scripts/ui/                     hud, menu, commercial, fonts
  scripts/audio/                  audio, music, sfx
  scripts/fx/, scripts/gfx/       efectos, emulación de Canvas 2D (canvas2d.gd) y tarjetas de TV (cards.gd)
  scripts/props/props.gd          biblioteca de props (carga los .glb de Blender)
  shaders/                        toon, glow, pantallas CRT, personajes, post-proceso, bloom …
  assets/                         GENERADO: props, chars, world, runtime, textures (Blender) y audio (tools/audio)
  data/layout.json                GENERADO por blender/world/layout.py (planta de la emisora)
  tools/                          utilidades de verificación (render de materiales, tarjetas, personajes…)
```

Cada archivo `.gd` corresponde a un módulo JS con el mismo nombre (en snake_case) y conserva los nombres de
funciones, campos, eventos e ids del original, así que se puede leer en paralelo con `src/`.

La emisora se construye por código al arrancar, igual que en la web: `level.gd` carga la arquitectura
(`assets/world/*.glb`) y cada `rooms/<sala>.gd` coloca sus props. Para verla sin jugar: `test=1 nozombies=1 god=1`
y `DAGame.inst.debug.freeCam(true)` (WASD, Q/E, ratón).

## Regenerar los assets

- **Modelos 3D (Blender):** ver `../blender/README.md`. Resumen:
  `blender --background --python blender/build_all.py` (todo) o `-- --only props --id telly` (uno solo).
  Después, abre Godot para que reimporte.
- **Tarjetas de TV como PNG para Blender:**
  `godot --path godot -s res://tools/export_cards.gd` (necesita ventana; no funciona con `--headless`).
- **Audio:** `npm install` y `npm run audio` (ver `../tools/audio/README.md`).

## Diferencias conocidas con la web

Son de motor, no de contenido:
- No se portan las optimizaciones propias de WebGL (precompilado de shaders, fusión de draw calls); Godot las
  gestiona por su cuenta.
- El audio ya no se sintetiza en vivo: está pre-renderizado con varias variaciones por sonido, a partir de las
  mismas recetas.
- El suavizado del Canvas 2D es MSAA 4x (Chrome usa cobertura analítica) y las sombras de texto se aproximan.
- Las sombras direccionales las ajusta Godot a la cámara en vez de a la caja de ±18 m alrededor del jugador.
