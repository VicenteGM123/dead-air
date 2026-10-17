# Caldero Nocturno

Una tiendita de pociones en 2.5D (estilo HD-2D): pixel art dentro de un escenario 3D con luz cálida, desenfoque de maqueta y rayos de luz por la ventana. Al pie de la Montaña Gris hay un pueblo lleno de gente de todo el reino (elfos que recuerdan siglos, enanos, gente gato y gente lobo, una viajera de la raza demonio, caballeros, magos errantes, campesinos…). Te cuentan sus problemas, tú adivinas qué poción o qué pergamino necesitan, lo preparas y se lo entregas. Días después te cuentan cómo les fue. Con el tiempo crece tu renombre, se desbloquean ingredientes, hechizos, mejoras para la tienda y las historias de seis viajeros.

## Cómo abrirlo

1. Instala **Godot 4.7** (versión estándar, no la .NET) desde godotengine.org.
2. Abre Godot → **Importar** → elige `project.godot` de esta carpeta.
3. La primera vez tarda unos segundos en importar las imágenes. Luego pulsa **F5** para jugar.

Está hecho y probado con Godot 4.7.2 usando el renderizador Forward+. Si tu computador es antiguo y no lo soporta, Godot cambia solo a OpenGL (se verá algo más simple).

## Cómo se juega

- **La tienda:** la alquimista camina entre la **biblioteca** (el grimorio), el **caldero** con el estante de ingredientes, el **mostrador** y la **puerta**. Toca un lugar o un objeto y ella va hasta allí; cada cosa funciona cuando llega.
- **Mañana:** primero, el **correo de la mañana**: las cartas de tus clientes de días anteriores (ver más abajo). Después puedes salir por la puerta al **Mercado**, una calle con puestos: hierbas (Ilse), gemas (Borin), tintas y papel (Tobías), cosas para la tienda (Mabel) y lo que trae el lago (Lupo). Puedes preparar pociones antes de abrir.
- **Tienda abierta:** cada cliente cuenta su problema. Puedes pedir una pista. Durante el día, el botón **Mercado** es un encargo: Pip te trae los ingredientes corriendo.
- **Caldero:** toca los frascos del estante para echar ingredientes (2, o 3 con la mejora). La poción la deciden las **dos esencias más fuertes** de la mezcla. Pulsa **Remover** y acierta la zona dorada para +1 de potencia.
- **Grimorio:** en el escritorio de la biblioteca escribes **pergaminos** (hechizos) con papel y tinta: elige una página, traza la runa uniendo sus puntos en orden y el pergamino va a su estante. Las tintas se compran a Tobías o se hacen en el caldero (botón **Tinta**).
- **Entregar:** toca una poción (o un pergamino) de tu estante, abajo a la derecha: con el grimorio abierto tiene dos pestañas, **Pociones** y **Pergaminos**, y enseña sola la de lo que pide el cliente. El cliente solo puede ver, oler y leer la etiqueta: la paga y se la lleva. **Todavía no sabe si funciona**: no la ha usado.
- **Tu intuición:** si lo que preparaste es justo lo que el cliente necesita, lo sientes al momento: la poción brilla, **Miga ronronea** y la alquimista lo piensa en voz baja («Esto debería funcionar…»). Es una corazonada, no una certeza.
- **Las noticias llegan después:** a la mañana siguiente por **carta**, o días después cuando el cliente **vuelve a la tienda** a contarte cómo le fue (a veces con otro pedido). Con las buenas noticias llegan la **propina**, el **renombre**, a veces un **regalo**, y las páginas del **Diario de viajeros**. Si la poción no era la correcta llega una queja: le devuelves el dinero, baja un poco tu renombre y tarda unos días en volver. Un pergamino lleva el nombre del hechizo en la etiqueta: si no es el que pidió, el cliente lo nota y te lo devuelve en el acto.
- **El pueblo crece:** cada pocos días llega gente nueva (por la mañana se comenta en el pueblo quién llegó). En el Diario ves también a quién le debes noticias.
- **Noche:** resumen del día y a dormir.
- Acaricia a **Miga**, la gata. Con el cojín te da suerte.

Caminar: `A` / `D` o las flechas, o haz clic en el suelo. `E` usa el lugar donde está la alquimista. Por la mañana, la puerta (o **Ir al mercado**) lleva al mercado; para volver, la puerta de tu tienda en la calle o **Volver a la tienda**.
Atajos: `Espacio` avanza diálogos y remueve, `R` libro de recetas, `J` diario, `Esc` ajustes. En la runa del grimorio también puedes trazar con las flechas o `WASD`; `Esc` la cancela sin gastar nada.
Con mando (Xbox y compatibles): el stick izquierdo mueve un cursor, la cruceta izquierda/derecha hace caminar a la alquimista, `A` toca, `B` vuelve o cierra, `X` avanza y remueve, `Y` recetas, `Vista` diario, `Menú` ajustes, `LB` / `RB` saltan entre objetos tocables (también los lugares de la tienda y los puestos del mercado) y el stick derecho desplaza las listas. El cursor se esconde al mover el ratón.
La partida se guarda sola al empezar cada día y después de cada cliente (también las noticias que aún no llegan).

## Dónde cambiar cosas

| Quiero cambiar… | Archivo |
|---|---|
| Ingredientes, pociones, precios, mejoras y niveles | `scripts/data.gd` |
| Personajes (nombre, especie, cuándo llegan al pueblo, saludo y firma de sus cartas, regalos) | `scripts/data.gd` (`CHARACTERS`) |
| Pedidos de los clientes, lo que dicen al recibir la poción y cómo les fue | `scripts/data.gd` (`VILLAGER_REQUESTS`: `text`, `hint`, `plan`, `good`, `fail`) |
| Historias de los seis viajeros | `scripts/data.gd` (`HEROES`: `react` al entregar, `thanks` cuando vuelven, `via` carta o visita) |
| Textos de reacciones, cartas, visitas e intuición | `scripts/data.gd` (`REACTIONS`, `WRONG_EFFECTS`, `LETTERS`, `RETURN_VISITS`, `INTUITION`) |
| Hechizos, tintas, papel y pedidos de pergaminos | `scripts/data.gd` (`SPELLS`, `INKS`, `PAPERS`, `MAGIC_ITEMS`, `SCROLL_REQUESTS`) |
| Reglas de alquimia, economía, guardado, qué clientes llegan cada día | `scripts/game.gd` |
| Cuándo llegan las noticias (carta o visita, cuántos días) y cómo se escriben | `scripts/story.gd` |
| Noticias pendientes, quejas, regalos (lo que se aplica cuando llegan) | `scripts/game.gd` (bloque STORY) |
| Reglas de la magia | `scripts/game.gd` (bloque MAGIC) |
| Flujo del día, tutorial, entregas, intuición, visitas y correo | `scripts/main.gd` |
| Escenario 3D de la tienda: lugares, posiciones, luces y hora del día | `scripts/world/shop_world.gd` (`LANE`, `STATIONS`) |
| Caminar (carril, velocidad) | `scripts/world/walker.gd` |
| El mercado (puestos, casas, gente) | `scripts/world/market_world.gd` y `VENDORS` en `scripts/data.gd` |
| Caldero (fuego, burbujas, vapor) | `scripts/world/cauldron.gd` |
| Interfaz (HUD, diálogo, paneles, correo de la mañana) | `scripts/ui/game_ui.gd`, `scripts/ui/overlays.gd`, `scripts/ui/ui_kit.gd` |
| Grimorio y minijuego de la runa | `scripts/ui/grimoire_ui.gd`, `scripts/ui/rune_game.gd` |
| Mando (cursor, botones, velocidad) | `scripts/ui/pad_cursor.gd` |
| Música y sonidos | `scripts/sfx.gd` |
| Efecto de maqueta, viñeta y color | `shaders/hd2d_post.gdshader` |

Todo el arte está en `assets/`. Los sprites miran a la derecha; los personajes miden 64×96 píxeles por cuadro. Puedes reemplazar cualquier PNG por uno tuyo con el mismo nombre y tamaño.

En `tools/arte/` están los scripts de Python que generaron el pixel art, las texturas, la música y los sonidos (necesitan `pillow`, `numpy`, `scipy` y `ffmpeg`). Los personajes y la gata Miga (también `props/cat.png`) salen de `chars64.py`; `chars.py` es el generador viejo de 32×48 y escribe aparte, en `salida/chars32`. Godot ignora esa carpeta.

### Ideas para seguir

- Un nuevo vecino: agrega su sprite en `assets/chars/` (archivos `nombre_idle.png` de 2 cuadros y `nombre_walk.png` de 4 cuadros), su entrada en `CHARACTERS` (con `arrives` y un `rumor` para el día que llega) y sus pedidos en `VILLAGER_REQUESTS`. Llegará solo al pueblo ese día.
- Un nuevo aventurero: lo mismo, más sus tres capítulos en `HEROES` y su id en `HERO_ORDER`.
- Un ingrediente nuevo: su ícono en `assets/icons/ing_<id>.png`, su frasco en `assets/props/jar_<id>.png` y su entrada en `INGREDIENTS` e `INGREDIENT_ORDER`.
- Eventos de temporada, encargos de varios días, o un desafío diario con ranking.

## Créditos

- Fuentes: Alegreya y Alegreya SC, de Huerta Tipográfica, con licencia SIL Open Font License (ver `assets/fonts/OFL-Alegreya.txt`).
- Pixel art, texturas, música y efectos de sonido: generados por código para este proyecto.
