# Caldero Nocturno

Una tiendita de pociones en 2.5D (estilo HD-2D): pixel art dentro de un escenario 3D con luz cálida, desenfoque de maqueta y rayos de luz por la ventana. Al pie de la Montaña Gris hay un pueblo lleno de gente de todo el reino (elfos que recuerdan siglos, enanos, gente gato y gente lobo, una viajera de la raza demonio, caballeros, magos errantes, campesinos…). Te cuentan sus problemas, tú adivinas qué poción necesitan (y, a veces, qué runa debe llevar en la etiqueta), la preparas y se la entregas. Días después te cuentan cómo les fue. Con el tiempo crece tu renombre, se desbloquean ingredientes, runas, mejoras para la tienda y las historias de seis viajeros.

## Novedades (ronda 3)

- **El banco del caldero:** al usar el caldero se abre una pantalla propia: los frascos a la izquierda, el caldero grande a la derecha. Tocas un frasco y cae dentro.
- **El ticket:** el pedido de cada cliente queda clavado arriba, en un papelito con su cara, la pista en iconos y las runas que pide.
- **El libro de runas:** el grimorio ahora sirve para encantar pociones. Algunos pedidos traen una runa: preparas la poción, la encantas en el escritorio de la biblioteca y la entregas. Ya no hay pergaminos.
- **Papeles de verdad:** el recetario, el diario, el correo y los puestos del mercado son hojas de papel con letra a mano, y hay mucho menos texto.
- **El mercado:** por la mañana, precio normal; de día el encargo cuesta **el doble (x2)**. La fuente de la plaza tiene agua.
- **La tienda:** el mostrador cruza la tienda; ella pasa por una trampilla y los clientes esperan del otro lado.
- **El elenco:** gorros y cascos que cubren el pelo, pies nuevos, la alquimista sin la poción en la mano y una Miga más gata.

## Cómo abrirlo

1. Instala **Godot 4.7** (versión estándar, no la .NET) desde godotengine.org.
2. Abre Godot → **Importar** → elige `project.godot` de esta carpeta.
3. La primera vez tarda unos segundos en importar las imágenes. Luego pulsa **F5** para jugar.

Está hecho y probado con Godot 4.7.2 usando el renderizador Forward+. Si tu computador es antiguo y no lo soporta, Godot cambia solo a OpenGL (se verá algo más simple).

## Cómo se juega

- **La tienda:** la alquimista camina entre la **biblioteca** (el grimorio), el **caldero** con el estante de ingredientes, el **mostrador** y la **puerta**. El mostrador cruza la tienda de la pared al frente: ella atiende de su lado y pasa al de la puerta por la **trampilla**; los clientes esperan del otro lado. Toca un lugar o un objeto y ella va hasta allí; cada cosa funciona cuando llega.
- **Mañana:** primero, el **correo de la mañana**: las cartas de tus clientes de días anteriores (ver más abajo). Después puedes salir por la puerta al **Mercado**, una calle con puestos: hierbas (Ilse), gemas (Borin), tintas y runas (Tobías), cosas para la tienda (Mabel) y lo que trae el lago (Lupo). En la plaza, la fuente. Puedes preparar pociones antes de abrir.
- **Tienda abierta:** cada cliente cuenta su problema y su pedido queda clavado arriba en un **ticket** (con los iconos de las runas que pide). Puedes pedir una pista. Durante el día, el botón **Mercado** es un encargo: Pip te trae los ingredientes corriendo, pero cuestan **el doble (x2)**. Conviene comprar por la mañana.
- **Caldero:** en el caldero (o tocando un frasco del estante de la tienda) se abre el **banco del caldero**: los frascos a la izquierda, el caldero grande a la derecha. Toca un frasco y cae al caldero (2, o 3 con la mejora). La poción la deciden las **dos esencias más fuertes** de la mezcla (los tubos de ensayo las muestran). **Remover**: acierta la zona dorada para +1 de potencia; luego **Embotellar**. **Vaciar** devuelve los ingredientes; con el grimorio abierto, **Tinta** hace la tinta de la esencia más fuerte.
- **Grimorio:** en el escritorio de la biblioteca está el **libro de runas**. Una runa se inscribe en la etiqueta de una poción ya embotellada: Prisa, Dulzor, Calma, Duración, Frescor, Alas, Sigilo y Fuerza. Si el ticket de un pedido trae una runa, prepara la poción, ve al escritorio, elige la poción, moja la pluma en la tinta de la runa y traza la runa uniendo sus puntos en orden (trazo perfecto = 3 estrellas). La runa pedida paga un extra; si falta, la propina baja y la carta lo cuenta. Las runas se aprenden con el renombre, los regalos de los viajeros y la página que vende Tobías; la tinta, en el puesto de Tobías o en el caldero (botón **Tinta**).
- **Entregar:** toca una poción de tu estante, abajo a la derecha (las encantadas llevan el icono de su runa). El cliente solo puede ver, oler y leer la etiqueta: la paga y se la lleva. **Todavía no sabe si funciona**: no la ha usado.
- **Tu intuición:** si lo que preparaste es justo lo que el cliente necesita, lo sientes al momento: la poción brilla, **Miga ronronea** y la alquimista lo piensa en voz baja («Esto debería funcionar…»). Es una corazonada, no una certeza.
- **Las noticias llegan después:** a la mañana siguiente por **carta**, o días después cuando el cliente **vuelve a la tienda** a contarte cómo le fue (a veces con otro pedido). Con las buenas noticias llegan la **propina**, el **renombre**, a veces un **regalo**, y las páginas del **Diario de viajeros**. Si la poción no era la correcta llega una queja: le devuelves el dinero, baja un poco tu renombre y tarda unos días en volver. Si faltaba la runa que pidió, la propina baja y la carta lo dice.
- **El pueblo crece:** cada pocos días llega gente nueva (por la mañana se comenta en el pueblo quién llegó). En el Diario ves también a quién le debes noticias.
- **Noche:** resumen del día y a dormir.
- Acaricia a **Miga**, la gata. Con el cojín te da suerte.

## Controles

| Teclado y ratón | Qué hace |
|---|---|
| Clic | tocar: un lugar o un objeto de la tienda (ella camina hasta allí y lo usa), un puesto del mercado, un botón |
| Clic en el suelo, `A` / `D` o las flechas | caminar |
| `E` | usar el lugar donde está: el caldero abre el banco, el escritorio de la biblioteca abre el grimorio, la puerta lleva al mercado (por la mañana) |
| `Espacio` | avanzar diálogos y remover |
| `R` / `J` | recetario / diario (`←` `→` o la rueda pasan las hojas) |
| `Esc` | ajustes, o cerrar lo que esté abierto |
| **Banco del caldero** | `1`–`8` echan un frasco, `Espacio` remueve o embotella, `Retroceso` saca el último, `Esc` o `E` cierran |
| **Grimorio** (escritorio de la biblioteca) | flechas e `Intro` para elegir, `Esc` cierra; la runa se traza con el ratón, las flechas o `WASD`, y `Esc` suelta la pluma sin gastar tinta |

| Mando (Xbox y compatibles) | Qué hace |
|---|---|
| Stick izquierdo | mover el cursor dorado (se centra solo en lo tocable más cercano) |
| Cruceta izquierda / derecha | caminar (con una ventana abierta, mueve el cursor) |
| `A` | tocar, o avanzar el diálogo |
| `B` | volver o cerrar (también el banco del caldero) |
| `X` | avanzar diálogos y remover |
| `Y` / `Vista` / `Menú` | recetario / diario / ajustes |
| `LB` / `RB` | saltar al objeto tocable anterior / siguiente (lugares de la tienda, puestos, frascos del banco, páginas del grimorio) |
| `LT` / `RT` | pasar las hojas del recetario y del diario |
| Stick derecho | desplazar listas |

El cursor del mando se esconde al mover el ratón. La partida se guarda sola al empezar cada día y después de cada cliente (también las noticias que aún no llegan).

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

Todo el arte está en `assets/`. Los sprites miran a la derecha; los personajes miden 64×96 píxeles por cuadro. Puedes reemplazar cualquier PNG por uno tuyo con el mismo nombre y tamaño.

En `tools/arte/` están los scripts de Python que generaron el pixel art, las texturas, la música y los sonidos (necesitan `pillow`, `numpy`, `scipy` y `ffmpeg`). Los personajes y la gata Miga (también `props/cat.png`) salen de `chars64.py` (los gorros y cascos, de `c64hat.py`); `chars.py` es el generador viejo de 32×48 y escribe aparte, en `salida/chars32`. Godot ignora esa carpeta. La interfaz (banco del caldero, ticket, papeles, botones) sale de `ui_art.py`, y el libro de runas y sus iconos de `magic_art.py`.

### Ideas para seguir

- Un nuevo vecino: agrega su sprite en `assets/chars/` (archivos `nombre_idle.png` de 2 cuadros y `nombre_walk.png` de 4 cuadros), su entrada en `CHARACTERS` (con `arrives` y un `rumor` para el día que llega) y sus pedidos en `VILLAGER_REQUESTS`. Llegará solo al pueblo ese día.
- Un nuevo aventurero: lo mismo, más sus tres capítulos en `HEROES` y su id en `HERO_ORDER`.
- Un ingrediente nuevo: su ícono en `assets/icons/ing_<id>.png`, su frasco en `assets/props/jar_<id>.png` y su entrada en `INGREDIENTS` e `INGREDIENT_ORDER`.
- Eventos de temporada, encargos de varios días, o un desafío diario con ranking.

## Créditos

- Fuentes: Alegreya y Alegreya SC, de Huerta Tipográfica, con licencia SIL Open Font License (ver `assets/fonts/OFL-Alegreya.txt`). Caveat (la letra manuscrita de los papeles), de The Caveat Project Authors, con licencia SIL Open Font License (ver `assets/fonts/OFL-Caveat.txt`).
- Pixel art, texturas, música y efectos de sonido: generados por código para este proyecto.
