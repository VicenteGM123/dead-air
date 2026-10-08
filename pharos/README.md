# PHAROS — La última luz

**Defensa de una isla griega contra las criaturas de la Noche.** De día levantas y amplías la aldea alrededor del
faro de Delos; de noche los hijos de Nyx salen del mar oscuro y tú peleas en primera línea junto a tus torres y tus
hoplitas. Siete noches; en la última sale del mar la **Hidra de la Noche**.

Juegas con **Fanós, el autómata del faro**: un guardián de bronce forjado por Hefesto cuya cabeza es la linterna del
faro (la última chispa de la llama de Hestia es su rostro). Lleva un **ancla** al hombro, una **lente de faro** como
escudo y un fajín de vela que ondea al viento. Si cae, su llama se apaga… y el Faro vuelve a encenderla.

Juego hecho en **Godot 4.7** (GDScript), con todo generado por código: modelos 3D low-poly, isla, agua, animaciones,
efectos, interfaz, música y sonidos. Funciona en escritorio y en el navegador (WebGL 2).

## Jugar

- **En el navegador:** `pharos/web/` (cuando esté en la rama `main`, en
  <https://vicentegm123.github.io/dead-air/pharos/web/>). Chrome, Edge, Firefox o Safari 15+ con aceleración gráfica;
  también en móvil, en horizontal, con controles táctiles (stick a la izquierda, acciones a la derecha).
- **En Godot:** instala Godot 4.7 (versión estándar), abre `pharos/game/project.godot` y pulsa **F5**.

## Controles

| Acción | Teclado y ratón | Mando |
|---|---|---|
| Moverse | W A S D / flechas | Stick izquierdo |
| Atacar con el ancla (combo de 3 golpes; el 3.º hace temblar el suelo) | J / clic izquierdo | X |
| Destello de la lente (aturde y empuja en cono) | K / clic derecho | Y |
| Embestida de vapor (esquiva con invulnerabilidad) | Espacio / Shift | B |
| **Haz del Faro** (cuando la Llama está llena) | Q | RB / RT |
| Construir, mejorar, tocar el cuerno, acariciar gatos (mantener) | E | A |
| Pausa | Esc | Start |

Si cambias de ventana o de pestaña en mitad de una partida, el juego se pausa solo.

## Cómo se juega

1. **Día** (sin límite de tiempo): camina hasta un solar (contorno de piedras) y **mantén E** para pagar dracma a
   dracma. Mejorar el **Faro** amplía su luz y desbloquea nuevos solares. Las columnas violetas sobre el mar marcan
   por dónde llegarán las criaturas esa noche.
2. Cuando estés listo, toca el **cuerno de la noche** junto a la plaza.
3. **Noche:** las criaturas emergen del mar. Las torres disparan, los hoplitas defienden sus puestos, las murallas
   cortan los caminos y tú peleas. Si cae el Faro, se acaba.
4. **Amanecer:** casas, olivares y muelles pagan su tributo, lo destruido se reconstruye gratis y eliges **uno de tres
   dones de los dioses** (Zeus, Poseidón, Atenea, Artemisa, Apolo, Hermes, Ares, Hefesto, Deméter, Hestia).
5. Si el Faro cae, puedes **reintentar la noche** desde el anochecer, con la aldea y los dones que tenías.

Las playas se abren poco a poco (al principio solo el sur; en la quinta noche, las cuatro) y las criaturas son un poco más
duras. El Destello de la lente interrumpe los ataques de las criaturas normales (no los de la Hidra), y la Hidra marca
en el suelo, con un anillo violeta, dónde va a morder o escupir.

## La isla

Delos está ordenada como una isla de las Cícladas en la Antigüedad: la aldea y sus huertos junto al faro; olivos,
viñas bajas y trigo en terrazas de piedra seca; colinas de garriga con tomillo, jara y retama donde pastan las
cabras; un santuario con ruinas y cipreses; una fuente con plátanos y adelfas; pinos de Alepo y tamarices en la costa,
y una era para trillar. Nada anacrónico: ni chumberas ni pitas, y una parra en vez de buganvilla. Por la isla viven
gatos (se dejan acariciar), cabras, gaviotas, delfines, mariposas y, de noche, luciérnagas.

| Edificio | Para qué sirve |
|---|---|
| Faro | El núcleo. Más niveles: más vida y más solares |
| Casa · Olivar · Muelle | Dracmas cada amanecer |
| Torre de arqueros | Dispara a las criaturas (3 niveles) |
| Muralla | Bloquea el camino a las criaturas que caminan |
| Cuartel | Hoplitas que guardan la zona |

| Criatura de Nyx | |
|---|---|
| Sombra | La más común: espíritu encapuchado hecho de cielo nocturno |
| Ker | Rápida y voladora: ignora las murallas |
| Escudado | Hoplita caído: resiste las flechas |
| Arquero de Nyx | Ataca a distancia con su arco de luna |
| Cíclope de sombra | Lento y enorme: derriba edificios |
| Hidra de la Noche | Jefa de la séptima noche |

## Estructura

```
pharos/
├── game/               proyecto de Godot (abre project.godot)
│   ├── scripts/        core (estado, datos, audio), world (isla, mar, vegetación, ciclo día/noche, fauna),
│   │                   gfx (kit de modelado low-poly, modelos, personajes animados), units, build, game, ui, fx
│   ├── shaders/        iluminación propia (sombras correctas en WebGL 2), agua, cielo, criaturas de cielo nocturno
│   ├── assets/         tipografías (Cinzel, EB Garamond, licencia OFL) y audio generado
│   └── tools/          herramientas de prueba: bot que juega solo, verificador de colisiones del héroe, vistas previas
├── web/                build web exportada
├── tools/              exportación web y prueba automática en Chromium; tools/audio genera toda la música y los sonidos
└── docs/               BRIEF (dirección), GDD (diseño completo de ~8 h) y PROPUESTAS (otros juegos posibles)
```

### Parámetros de prueba

Se pasan después de `--` (`godot --path pharos/game -- play=1 village=1`) o en la URL de la versión web, donde
solo funcionan si se añade `dev=1` (`index.html?dev=1&play=1&village=1`):

| Parámetro | Efecto |
|---|---|
| `play=1` | salta el título y empieza la partida |
| `village=1`, `pl=3` | aldea ya construida / nivel del faro |
| `startnight=N` | empieza directamente en la noche N |
| `bot=1 speed=3` | un bot juega solo (construye, llama a la noche y pelea; `build=greedy\|econ\|lazy\|none`, `fight=0\|1\|2`) |
| `coins=N` | dracmas iniciales |
| `nearfight=1` | la cámara empieza junto a la primera pelea de la noche |
| `uitest=title\|hud\|blessing\|pause\|options\|controls\|victory\|defeat\|touch` | fuerza una pantalla de la interfaz |

Versión web: `STRICT=1 sh pharos/tools/export_web.sh` exporta a `pharos/web/` (se niega si encuentra código que se
rompe en WebGL 2) y `node pharos/tools/web_test.mjs /tmp/pharos-webtest --dir pharos/web` la prueba en Chromium
(carga, título, partida, noche, móvil, audio y consola).

## Documentos

- [`docs/BRIEF.md`](docs/BRIEF.md): dirección del juego en una página.
- [`docs/GDD.md`](docs/GDD.md): diseño completo de la versión larga (~8 h, campaña "La Odisea de la Luz").
- [`docs/PROPUESTAS.md`](docs/PROPUESTAS.md): otros juegos a partir de tus ideas (fútbol anime HD-2D, gatos,
  mundo abierto griego y fusiones).

## Créditos

Diseño, código, modelos, música y sonido generados para este proyecto. Tipografías **Cinzel** y **EB Garamond**
(SIL Open Font License, incluidas en `game/assets/fonts`).
