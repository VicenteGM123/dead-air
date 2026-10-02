# DEAD AIR — versión Godot

Migración 1:1 del juego web (`src/`, Three.js) a **Godot 4.7**. Todo el código del juego está en GDScript y todos
los assets 3D se generan en **Blender** con scripts de Python (`../blender/`). El sonido se renderiza a partir de las
recetas originales de audio (`../tools/audio/`).

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

## Multijugador (cooperativo online, 1-4 jugadores)

En la pantalla de título pulsa cualquier tecla: aparece el menú principal (**SINGLE PLAYER / MULTIPLAYER / OPTIONS /
CONTROLS / QUIT**). SINGLE PLAYER es el juego de siempre, sin ningún cambio.

**MULTIPLAYER**
- **NAME**: tu nombre (se guarda).
- **HOST GAME**: creas la partida. Tus amigos ven en la lista "Tonight's Cast" la dirección que tienen que usar
  (la de internet, si el router abre el puerto solo con UPnP, y la de la red local).
- **JOIN GAME**: aparecen solas las partidas de tu red local; para una partida por internet elige ENTER ADDRESS y
  escribe la IP del anfitrión (con el mando hay un teclado en pantalla).
- **Sala de espera**: cada uno elige su héroe en el dial de la tele (cada héroe solo puede llevarlo un jugador) y lo
  sintoniza para quedar listo. Cuando todos están listos, el anfitrión pulsa START: cuenta atrás y a jugar.

**Jugar por internet**: el anfitrión necesita el puerto **UDP 31313** abierto hacia su PC. El juego intenta abrirlo
solo (UPnP); si tu router no lo permite, ábrelo a mano en el router (redirección de puertos UDP 31313) o usad una red
privada virtual tipo **Tailscale**, **ZeroTier** o **Radmin VPN** y unid por la IP que os da. Todos deben tener la
misma versión del juego.

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
cuando hay N jugadores), `mplag= mpjitter= mploss=` (simulan mala red). Código: `scripts/net/` (red, sala, jugadores
remotos) y los `*_net.gd` / párrafos `MP:` de cada sistema.

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
