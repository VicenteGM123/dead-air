# Midnight Cauldron (Caldero Nocturno)

Una tiendita de pociones en 2.5D (estilo HD-2D): pixel art dentro de un escenario 3D con luz cálida, desenfoque de maqueta y rayos de luz por la ventana. Al pie de la Montaña Gris (*the Grey Mountain*), en Arvendal, hay un pueblo lleno de gente de todo el reino (elfos que recuerdan siglos, enanos, gente gato y gente lobo, una viajera de la raza demonio, caballeros, magos errantes, campesinos…). Te cuentan sus problemas, tú adivinas qué poción necesitan (y, a veces, qué runa debe llevar en la etiqueta), la preparas y se la entregas. Días después te cuentan cómo les fue. Con el tiempo crece tu renombre, se desbloquean ingredientes, runas, mejoras para la tienda y las historias de seis viajeros, y tu tienda sube en el **Guild Rankings** (el escalafón del Gremio de Boticarios de Arvendal).

Desde la ronda 5 **todo el juego está en inglés** (la tienda se llama **Midnight Cauldron**); esta documentación sigue en español.

## Novedades (ronda 5)

- **Todo en inglés:** el título, la intro, el HUD, los consejos, los diálogos y pedidos de los clientes, las cartas, el diario, el recetario, el grimorio, el banco, la bola, los puestos del mercado, las cuentas, el Guild Rankings, la Gaceta, las invitaciones, los tres eventos, el final y sus créditos, y también los carteles 3D y las imágenes con letras. Las partidas guardadas de antes siguen funcionando: al continuar, las cartas pendientes, el diario y las noticias guardadas en español se vuelven a escribir en inglés.
- **Los nombres nuevos:**

| Antes | Ahora |
|---|---|
| Caldero Nocturno (el juego y su tienda) | **Midnight Cauldron** |
| Krápido, «pociones a pico y pluma» | **Crow Delivery**, “Potions by beak and feather” |
| Ventanilla Krápido (la mejora de Mabel) | **Crow Window** |
| Graznido, el cuervo · las plumas | **Squawk** · **feathers** |
| Escalafón del Gremio · La Gaceta del Gremio | **Guild Rankings** · **The Guild Gazette** |
| Gremio de Boticarios de Arvendal | **the Arvendal Apothecaries' Guild** |
| Fizz y Chispa | **Fizz & Spark** |
| Valdelago · Robledal · Brisaclara · la Montaña Gris | **Lakevale** · **Oakdale** · **Clearbreeze** · **the Grey Mountain** |
| Examen de la Academia · Concurso de Robledal · Feria del Torneo | **The Academy of Magic Exam** · **The Oakdale Potion Contest** · **The Clearbreeze Tournament Fair** |
| renombre · oro · Jurado | **renown** · **gold** · **Judges** |
| Doña / Don / Sor / Padre | Mrs. / Mr. / Sister / Father (según el personaje); Miga sigue siendo Miga |

- **Las paredes que temblaban:** en la pared del lado de la puerta y en la del fondo de la biblioteca había dos superficies en el mismo lugar exacto (el yeso y la piedra del zócalo); la tarjeta gráfica no sabía cuál dibujar delante y cambiaba de una a otra en cada cuadro. Ahora la piedra sobresale 4 cm y los marcos de ventanas y puertas, las sombras de la gente sobre las alfombras, el mostrador y los trofeos tienen su propio lugar. Se revisó todo el juego (la tienda de día y de noche, el mercado, los tres eventos, el título y el final): ninguna superficie queda encima de otra.
- **La fachada del mercado:** la puerta azul de al lado (era de una panadería) ya no está: todo el frente es la tienda, con una sola puerta, el letrero **Midnight Cauldron**, el escaparate, el cartel del caldero y ventanas arriba. Con Crow Delivery comprado, en la fachada aparece la ventanilla del cuervo.

## Cómo abrirlo

1. Instala **Godot 4.7** (versión estándar, no la .NET) desde godotengine.org.
2. Abre Godot → **Importar** → elige `project.godot` de esta carpeta.
3. La primera vez tarda unos segundos en importar las imágenes. Luego pulsa **F5** para jugar.

Está hecho y probado con Godot 4.7.2 usando el renderizador Forward+. Si tu computador es antiguo y no lo soporta, Godot cambia solo a OpenGL (se verá algo más simple).

## Cómo se juega

- **La tienda:** la alquimista camina entre la **biblioteca** (el grimorio), el **caldero** con el estante de ingredientes, el **mostrador** y la **puerta**. El mostrador cruza la tienda de la pared al frente: ella atiende de su lado y pasa al de la puerta por la **trampilla**; los clientes esperan del otro lado. Toca un lugar o un objeto y ella va hasta allí; cada cosa funciona cuando llega.
- **Mañana:** primero, las invitaciones a eventos (**Accept** o **Decline**) y el **correo de la mañana** (**Mail**): las cartas de tus clientes de días anteriores (ver más abajo) y tu puesto en el Guild Rankings. Después puedes salir por la puerta al mercado (**Market**), una calle con puestos: hierbas (Ilse's Herbs), gemas (Borin's Gems), tintas y runas (Inks & Runes, de Tobías), cosas para la tienda (Mabel's) y lo que trae el lago (Gifts of the Lake, de Lupo). En la plaza, la fuente. Puedes preparar pociones antes de abrir y abrir con **Open**. 
- **Tienda abierta (5 minutos, de 9 AM a 6 PM):** la gente entra y hace fila dentro; cada cliente cuenta su problema y su pedido queda clavado arriba en un **ticket** (con los iconos de las runas que pide y una barra de paciencia). A las 6 PM se cierra (**Closing time!**): quien está en el mostrador todavía se atiende y la fila se va a casa. Al hablar con un cliente: **Brew it** (prepararla), **A hint?** (una pista) o **I can't** (no puedo). Durante el día, el botón **Market** es un encargo (**Errand**): Pip te trae los ingredientes corriendo, pero cuestan **el doble (x2)**. Conviene comprar por la mañana.
- **Caldero:** en el caldero (o tocando un frasco del estante de la tienda) se abre el **banco del caldero**: los frascos a la izquierda, el caldero grande a la derecha. Toca un frasco y cae al caldero (2, o 3 con la mejora). La poción la deciden las **dos esencias más fuertes** de la mezcla (los tubos de ensayo las muestran). **Stir** (remover): acierta la zona dorada para +1 de potencia; luego **Bottle** (embotellar). **Empty** (vaciar) devuelve los ingredientes; con el grimorio abierto, **Ink** hace la tinta de la esencia más fuerte.
- **Grimorio:** en el escritorio de la biblioteca está el **libro de runas**. Una runa se inscribe en la etiqueta de una poción ya embotellada: Haste, Sweet, Calm, Lasting, Fresh, Wings, Stealth y Strength (Prisa, Dulzor, Calma, Duración, Frescor, Alas, Sigilo y Fuerza). Si el ticket de un pedido trae una runa, prepara la poción, ve al escritorio, elige la poción, moja la pluma en la tinta de la runa y traza la runa uniendo sus puntos en orden (trazo perfecto = 3 estrellas). La runa pedida paga un extra; si falta, la propina baja y la carta lo cuenta. Las runas se aprenden con el renombre, los regalos de los viajeros y la página que vende Tobías; la tinta, en el puesto de Tobías o en el caldero (botón **Ink**).
- **Entregar:** toca una poción de tu estante, abajo a la derecha (las encantadas llevan el icono de su runa). El cliente solo puede ver, oler y leer la etiqueta: la paga y se la lleva. **Todavía no sabe si funciona**: no la ha usado.
- **Tu intuición:** si lo que preparaste es justo lo que el cliente necesita, lo sientes al momento: la poción brilla, **Miga ronronea** y la alquimista lo piensa en voz baja (“This should work…”). Es una corazonada, no una certeza.
- **Las noticias llegan después:** a la mañana siguiente por **carta**, o días después cuando el cliente **vuelve a la tienda** a contarte cómo le fue (a veces con otro pedido). Con las buenas noticias llegan la **propina**, el **renombre**, a veces un **regalo**, y las páginas del diario de viajeros (**Journal**). Si la poción no era la correcta llega una queja: le devuelves el dinero, baja un poco tu renombre y tarda unos días en volver. Si faltaba la runa que pidió, la propina baja y la carta lo dice.
- **El pueblo crece:** cada pocos días llega gente nueva (por la mañana se comenta en el pueblo quién llegó). En el diario ves también a quién le debes noticias.
- **Crow Delivery:** con la **Crow Window** comprada (en Mabel's, desde el nivel Apothecary), toca la **bola de cristal** (junto a la ventanilla): ahí ves los pedidos a domicilio, quién pide, qué poción y cuánto falta para que pase **Squawk**, el cuervo. Cuando espera en la percha, dale la poción desde la bola (o tocando una poción del estante estando en la ventanilla). Sus reseñas en **feathers** (1 a 5) deciden cuántos pedidos llegan.
- **Eventos:** a veces llega una invitación por carta (**Invitation**). Si aceptas, ese día no hay tienda: ella viaja y juega allí. En **The Academy of Magic Exam** se preparan muchas pociones iguales a contrarreloj, en **The Oakdale Potion Contest** el jurado (**Judges**) prueba tres pociones según un tema, y en **The Clearbreeze Tournament Fair** se atiende una fila larga de caballeros. Al final, la tarjeta con la medalla (gold, silver o bronze).
- **Noche:** las cuentas del día (**Day's Ledger**) y a dormir (**Sleep**). El **Guild Rankings** se abre cuando quieras con la copa del menú de arriba (o `G`); cada 5 días llega **The Guild Gazette**, y al llegar al puesto 1 hay un final con fiesta (después se sigue jugando con **Keep playing**).
- Acaricia a **Miga**, la gata. Con el cojín te da suerte.

## Controles

| Teclado y ratón | Qué hace |
|---|---|
| Clic | tocar: un lugar o un objeto de la tienda (ella camina hasta allí y lo usa), un puesto del mercado, un botón |
| Clic en el suelo, `A` / `D` o las flechas | caminar |
| `E` | usar el lugar donde está: el caldero (**Cauldron**) abre el banco, el escritorio de la biblioteca (**Library · grimoire**) abre el grimorio, la puerta (**Door · to the market**) lleva al mercado por la mañana |
| `Espacio` | avanzar diálogos y remover (**Stir**) |
| `R` / `J` | recetario (**Recipes**) / diario (**Journal**) (`←` `→` o la rueda pasan las hojas) |
| `G` | el **Guild Rankings** (también la copa del menú de arriba) |
| `Esc` | ajustes (**Settings**), o cerrar lo que esté abierto |
| **Banco del caldero** | `1`–`8` echan un frasco, `Espacio` remueve o embotella (**Stir** / **Bottle**), `Retroceso` saca el último, `Esc` o `E` cierran |
| **Grimorio** (escritorio de la biblioteca) | flechas e `Intro` para elegir, `Esc` cierra; la runa se traza con el ratón, las flechas o `WASD`, y `Esc` suelta la pluma sin gastar tinta |
| **Bola de cristal** (Crow Delivery, junto a la ventanilla) | un clic en la bola o `E` en la ventanilla la abre; `←` `→` eligen una poción, `Intro` o `Espacio` se la dan a Squawk, `1`–`5` destacan un pedido, `Esc` o `E` la cierran |
| **Eventos** | `E` abre el caldero del evento (**Cauldron**); `Espacio` o `Intro` aceptan las tarjetas (**Next round**, **See results**, **Head home**) |

| Mando (Xbox y compatibles) | Qué hace |
|---|---|
| Stick izquierdo | mover el cursor dorado (se centra solo en lo tocable más cercano) |
| Cruceta izquierda / derecha | caminar (con una ventana abierta, mueve el cursor) |
| `A` | tocar, o avanzar el diálogo |
| `B` | volver o cerrar (también el banco del caldero y la bola de cristal) |
| `X` | avanzar diálogos y remover |
| `Y` / `View` (Vista) / `Menu` | recetario / diario / ajustes |
| `LB` / `RB` | saltar al objeto tocable anterior / siguiente (lugares de la tienda, puestos, frascos del banco, páginas del grimorio, pedidos de la bola, botones del evento) |
| `LT` / `RT` | pasar las hojas del recetario y del diario |
| Stick derecho | desplazar listas |

El Guild Rankings se abre con el cursor sobre la copa del menú. El cursor del mando se esconde al mover el ratón. La partida se guarda sola al empezar cada día y después de cada cliente (también las noticias que aún no llegan).

## Dónde cambiar cosas

| Quiero cambiar… | Archivo |
|---|---|
| Ingredientes, pociones, precios, mejoras y niveles | `scripts/data.gd` |
| Personajes (nombre, especie, cuándo llegan al pueblo, saludo y firma de sus cartas, regalos) | `scripts/data.gd` (`CHARACTERS`) |
| Pedidos de los clientes, lo que dicen al recibir la poción y cómo les fue | `scripts/data.gd` (`VILLAGER_REQUESTS`: `text`, `hint`, `plan`, `good`, `fail`) |
| Historias de los seis viajeros | `scripts/data.gd` (`HEROES`: `react` al entregar, `thanks` cuando vuelven, `via` carta o visita) |
| Textos de reacciones, cartas, visitas e intuición | `scripts/data.gd` (`REACTIONS`, `WRONG_EFFECTS`, `LETTERS`, `RETURN_VISITS`, `INTUITION`) |
| Runas, tintas y pedidos con runas | `scripts/data.gd` (`RUNES`, `RUNE_TEXT`, `INKS`, `MAGIC_ITEMS`, `RUNE_REQUESTS`) |
| Reglas de alquimia, economía, guardado, qué clientes llegan cada día | `scripts/game.gd` |
| Cuándo llegan las noticias (carta o visita, cuántos días) y cómo se escriben | `scripts/story.gd` |
| Noticias pendientes, quejas, regalos (lo que se aplica cuando llegan) | `scripts/game.gd` (bloque STORY) |
| Reglas de las runas (aprender, encantar, lo que pagan) | `scripts/game.gd` (bloque R3 MAGIC3) |
| Precio del mercado (x2 en el encargo de día) | `scripts/game.gd` (`market_price`) |
| Flujo del día, tutorial, entregas, intuición, visitas y correo | `scripts/main.gd` |
| Escenario 3D de la tienda: lugares, posiciones, luces y hora del día | `scripts/world/shop_world.gd` (`LANE`, `STATIONS`) |
| Mostrador y trampilla | `scripts/world/shop_world.gd` (`COUNTER_X`…, `_build_counter`) |
| Caminar (carril, velocidad) | `scripts/world/walker.gd` |
| El mercado (puestos, casas, gente) | `scripts/world/market_world.gd` y `VENDORS` en `scripts/data.gd` |
| La fuente de la plaza (agua, chorros) | `scripts/world/market_world.gd` (`_build_fountain`) y `shaders/fountain_*.gdshader` |
| Caldero (fuego, burbujas, vapor) | `scripts/world/cauldron.gd` |
| Banco del caldero (frascos, caldero grande, remover, embotellar) | `scripts/ui/brew_ui.gd`, `scripts/ui/stir_game.gd` |
| Interfaz (HUD, ticket del pedido, estante, diálogo) | `scripts/ui/game_ui.gd`, `scripts/ui/ui_kit.gd` |
| Papeles: recetario, diario, correo, puestos del mercado, resumen, ajustes, título | `scripts/ui/overlays.gd`, `scripts/ui/paper_kit.gd` |
| Grimorio (libro de runas) y minijuego de la runa | `scripts/ui/grimoire_ui.gd`, `scripts/ui/rune_game.gd` |
| Mando (cursor, botones, velocidad) | `scripts/ui/pad_cursor.gd` |
| Música y sonidos | `scripts/sfx.gd` |
| Efecto de maqueta, viñeta y color | `shaders/hd2d_post.gdshader` |
| El día de 5 minutos: cuánta gente viene, paciencia, día de mercado, propinas | `scripts/game.gd` (bloque R4 PACE: `PACE_*`, `PACE_PATIENCE`, `pace_demand`) |
| La fila dentro de la tienda, el reloj, el cierre a las 18:00 | `scripts/main.gd` (bloque R4 PACE) y `QUEUE_SPOTS` en `scripts/world/shop_world.gd` |
| Las cuentas del día (la hoja de la noche) | `scripts/ui/overlays.gd` (`show_summary`) |
| El Guild Rankings: tiendas, puntos del día, rivales, la Gaceta | `scripts/ranking.gd` (`SHOPS`, `day_points`), `scripts/ui/rank_ui.gd` |
| El final del puesto 1 | `scripts/world/ending_scene.gd` |
| Crow Delivery: pedidos, tiempos, feathers, el cuervo y la bola | `scripts/krapido.gd`, `scripts/world/raven.gd`, `scripts/ui/ball_ui.gd` (textos y rimas en `scripts/data.gd`, bloque R4 RAVEN; los archivos conservan el nombre viejo) |
| Eventos: invitaciones, premios, cuotas, cortes de las medallas | `scripts/events.gd` (`CATALOG`, `reward`, `cuts`) |
| Las reglas de cada evento y su pantalla | `scripts/event_game.gd`, `scripts/ui/event_ui.gd` |
| Los escenarios de los eventos (Academia, Concurso, Torneo) | `scripts/world/event_scenes.gd` |
| Los textos en inglés | donde estaban los de español: `scripts/data.gd` (pedidos, cartas, personajes), `scripts/story.gd`, `scripts/main.gd` y `scripts/ui/*.gd`; los carteles 3D, en `scripts/world/*.gd`. Los ids internos y las claves de la partida guardada siguen en español (no cambiarlos) |
| Paredes superpuestas (para revisar después de mover algo en 3D) | `--demo=zcheck` (`scripts/world/zcheck.gd`): cuenta las superficies que se pisan en cada escenario; `--textlog=<archivo>` anota cada texto que aparece en pantalla |

Todo el arte está en `assets/`. Los sprites miran a la derecha; los personajes miden 64×96 píxeles por cuadro. Puedes reemplazar cualquier PNG por uno tuyo con el mismo nombre y tamaño.

En `tools/arte/` están los scripts de Python que generaron el pixel art, las texturas, la música y los sonidos (necesitan `pillow`, `numpy`, `scipy` y `ffmpeg`). Los personajes y la gata Miga (también `props/cat.png`) salen de `chars64.py` (los gorros y cascos, de `c64hat.py`); `chars.py` es el generador viejo de 32×48 y escribe aparte, en `salida/chars32`. Godot ignora esa carpeta. La interfaz (banco del caldero, ticket, papeles, botones) sale de `ui_art.py`, y el libro de runas y sus iconos de `magic_art.py`. Lo nuevo de la ronda 4: el reloj y la fila (`pace_art.py`, `pace_audio.py`), el cuervo, la bola y la ventanilla (`raven_art.py`, `raven_audio.py`), el Escalafón, la Gaceta y el final (`rank_art.py`), y los eventos (`event_art.py` para los escenarios, `events_ui_art.py` para su interfaz). En la ronda 5: el cartel CROW DELIVERY (`raven_art.py`), el encabezado THE GUILD GAZETTE (`rank_art.py`) y la fuente de símbolos ★ ▼ ✓ (`symbols_font.py`).

### Ideas para seguir

- Un nuevo vecino: agrega su sprite en `assets/chars/` (archivos `nombre_idle.png` de 2 cuadros y `nombre_walk.png` de 4 cuadros), su entrada en `CHARACTERS` (con `arrives` y un `rumor` para el día que llega) y sus pedidos en `VILLAGER_REQUESTS`. Llegará solo al pueblo ese día.
- Un nuevo aventurero: lo mismo, más sus tres capítulos en `HEROES` y su id en `HERO_ORDER`.
- Un ingrediente nuevo: su ícono en `assets/icons/ing_<id>.png`, su frasco en `assets/props/jar_<id>.png` y su entrada en `INGREDIENTS` e `INGREDIENT_ORDER`.
- Un evento nuevo: su entrada en `CATALOG` (`scripts/events.gd`), sus reglas en `scripts/event_game.gd` y su escenario en `scripts/world/event_scenes.gd`.
- Encargos de varios días, o eventos de temporada.

## Créditos

- Fuentes: Alegreya y Alegreya SC, de Huerta Tipográfica, con licencia SIL Open Font License (ver `assets/fonts/OFL-Alegreya.txt`). Caveat (la letra manuscrita de los papeles), de The Caveat Project Authors, con licencia SIL Open Font License (ver `assets/fonts/OFL-Caveat.txt`).
- Símbolos (★ ☆ ▲ ▼ ✓ ✗ ← → ♥): `CalderoSymbols.ttf`, un subconjunto de DejaVu Sans Bold con licencia Bitstream Vera / DejaVu (ver `assets/fonts/LICENSE-CalderoSymbols.txt`).
- Pixel art, texturas, música y efectos de sonido: generados por código para este proyecto.
