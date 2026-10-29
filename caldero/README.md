# Midnight Cauldron (Caldero Nocturno)

Una tiendita de pociones en 2.5D (estilo HD-2D) hecha en Godot 4.7. Desde la ronda 5 el juego está **todo en inglés** (esta documentación sigue en español). El proyecto está en `game/` (ver `game/README.md`: cómo se juega y dónde cambiar cosas) y la versión web en `web/`.

Se juega en https://vicentegm123.github.io/dead-air/caldero/web/

## Arranque en la web (pantalla de carga)

Antes, después de la pantalla de Godot la página se quedaba en negro unos segundos y el navegador podía avisar de que «no responde»: el juego armaba la tienda y el mercado de un tirón y compilaba todos los shaders (más de 200 programas de WebGL, 105 en un solo cuadro) antes de mostrar el título. Ahora:

- La página y el juego muestran la misma imagen («Midnight Cauldron» con el emblema) y una barra dorada que avanza: primero mientras baja el juego, después mientras se prepara. Nada de negro ni del logo de Godot.
- La tienda se arma y se muestra por partes, unos pocos materiales nuevos por cuadro: la página sigue respondiendo y la barra se mueve.
- Solo se prepara lo que se ve en el título. Lo demás (la biblioteca, los efectos, las letras de los eventos, el mercado) se prepara después, ya con el título en pantalla, sin que se note; si se va al mercado antes, se termina en el fundido del viaje. Los eventos siguen empezando sin tirones.
- Medido en un navegador sin tarjeta gráfica: la primera imagen del juego sale a los ~1,6 s (antes ~5 s, y era negra), el cuadro más largo antes del título bajó de 4,7 s a 1,4 s y el título necesita 149 programas de shader en vez de 203 (como mucho 16 por cuadro, antes 105). Con una tarjeta gráfica normal todo es bastante más rápido; la segunda vez, más aún (el navegador guarda los shaders ya compilados).
- `index.wasm` (37,7 MB, ~10 MB comprimido) es el motor de Godot tal como viene: no se puede achicar sin compilar Godot a medida.

## Novedades (ronda 6)

- **Sin tirón al empezar un evento:** el escenario se arma durante el viaje y lo que se dibuja por primera vez (gente, efectos, letras) se prepara con el mapa quieto, antes del fundido. En la web (medido en un navegador sin tarjeta gráfica), el peor cuadro después de aparecer el evento bajó de 2,7–7,5 s a unos pocos milisegundos.
- **Avisos de botón:** junto a una persona o a algo que se puede usar aparece la tecla y lo que hace (**E Give potion · Space Talk** en el mostrador, **E Brew**, **E Buy**, **E Go to market**, **E Hand over**…). Con el mando se ven los botones del mando.
- **Botones de arriba nuevos:** **Open shop** (`O`) y **Market** (`M`) con icono y su tecla; los de la derecha con marco nuevo y su tecla en el rótulo.
- **Menos desenfoque:** las franjas borrosas de arriba y abajo son más angostas (en el mercado, del 48 % al 28 % de la pantalla), con la misma fuerza.
- Las partidas guardadas siguen funcionando.

Los nombres en inglés (desde la ronda 5):

| Antes | Ahora |
|---|---|
| Caldero Nocturno (el juego y su tienda) | **Midnight Cauldron** |
| Krápido · Ventanilla Krápido | **Crow Delivery**, “Potions by beak and feather” · **Crow Window** |
| Graznido, el cuervo · plumas | **Squawk** · **feathers** |
| Escalafón del Gremio · La Gaceta del Gremio | **Guild Rankings** · **The Guild Gazette** |
| Fizz y Chispa | **Fizz & Spark** |
| Valdelago · Robledal · Brisaclara · la Montaña Gris | **Lakevale** · **Oakdale** · **Clearbreeze** · **the Grey Mountain** |
| Examen de la Academia · Concurso de Robledal · Feria del Torneo | **The Academy of Magic Exam** · **The Oakdale Potion Contest** · **The Clearbreeze Tournament Fair** |

## Teclado y ratón

Junto a cada lugar o persona, un aviso dice qué tecla usar (o qué botón del mando, si lo último que usaste fue el mando).

| Tecla | Qué hace |
|---|---|
| Clic | tocar: un lugar o un objeto de la tienda (ella camina hasta allí y lo usa), una persona, un puesto del mercado, un botón |
| Clic en el suelo, `A` / `D` o las flechas | caminar |
| `E` | lo que dice el aviso: **Open shop**, **Talk**, **Give potion**, **Brew**, **Enchant**, **Go to market**, **Buy**, **Back to shop**, **Hand over** / **Read orders** (la ventanilla del cuervo) |
| `Espacio` | la segunda acción del aviso (**Talk**, o **Present** en el concurso), avanzar diálogos y remover (**Stir**) |
| `O` / `M` | **Open shop** / **Market** (en el mercado, **Back to shop**) |
| `1` – `3` | las respuestas de un diálogo (**Brew it**, **A hint?**, **I can't**) |
| `Intro` | el botón principal de un papel (**Sleep**, **Next**, **Done**, **Start**…); `Tab` marca otro botón; en la invitación, `1` = **Accept**, `2` = **Decline** |
| `R` / `J` | recetario (**Recipes**) / diario (**Journal**) (`←` `→` o la rueda pasan las hojas) |
| `G` | el **Guild Rankings** (también la copa del menú de arriba) |
| `Esc` | ajustes (**Settings**), o cerrar la ventana abierta |

Al dar una poción con `E`, si en el estante hay pociones distintas se abre para elegir: `←` `→` (o `1`–`9`) y `E` o `Intro`; `Esc` vuelve. Con el banco abierto, `Tab` abre el estante.
En el **banco del caldero**: `1`–`8` echan un frasco, `Espacio` remueve o embotella (**Stir** / **Bottle**), `Retroceso` saca el último, `I` hace tinta (**Ink**), `Supr` vacía (**Empty**) y `Esc` o `E` lo cierran.
En el **grimorio** (el escritorio de la biblioteca): flechas e `Intro` para elegir y `Esc` para cerrar; la runa se traza con el ratón, las flechas o `WASD`, y `Esc` suelta la pluma sin gastar tinta.
En la **bola de cristal** de Crow Delivery (se abre con `E` en la ventanilla o con un clic): `←` `→` eligen una poción, `Intro` o `Espacio` se la dan a Squawk, `1`–`5` destacan un pedido y `Esc` o `E` la cierran.
En un **evento**: `E` abre el caldero del evento (**Cauldron**), en el concurso `Espacio` elige la poción para el jurado (**Present**), y `Espacio` o `Intro` aceptan sus tarjetas (**Next round**, **See results**, **Head home**).

## Mando (Xbox y compatibles)

El mando lleva un cursor dorado que hace de ratón: aparece al usar el mando y se esconde al mover el ratón.

| Botón | Qué hace |
|---|---|
| A | la acción del aviso (si el cursor no está sobre otra cosa); sobre algo, tocarlo; en un diálogo, avanzar; en un papel, su botón principal |
| X | la segunda acción del aviso (**Talk**, **Present**), avanzar diálogos y remover (como `Espacio`) |
| B | volver / cerrar (el estante, la ventana abierta, el banco del caldero, la bola de cristal) |
| Cruceta izquierda / derecha | caminar; en el estante y en la bola, elegir la poción |
| Stick izquierdo | mover el cursor (al soltarlo sobre algo tocable, o cerca, se centra solo) |
| Y | recetario (**Recipes**) |
| View (Vista) | diario de viajeros (**Journal**) |
| Menu (Menú) | ajustes (**Settings**) |
| LB / RB | saltar al objeto tocable anterior / siguiente (lugares de la tienda, puestos del mercado, frascos del banco, páginas del grimorio, pedidos de la bola, botones de los eventos) |
| LT / RT | pasar las hojas del recetario y del diario |
| Stick derecho | desplazar listas |

En el navegador, el sonido empieza con el primer clic o tecla: los navegadores no cuentan el mando como interacción (la pantalla de título lo avisa).

## Versión web

Se genera con `tools/export_web.sh` (necesita Godot 4.7 con las plantillas de exportación web):

```
GODOT=/ruta/a/godot sh caldero/tools/export_web.sh
```

Usa el preset "Web" del proyecto (renderizador Compatibility / WebGL 2, sin hilos, para que funcione en GitHub Pages) y deja el resultado en `web/`. Además arregla el audio web de Godot 4.7 en `index.js` (los sonidos en bucle, como la música, el fuego y los grillos, se repiten en el hilo de audio: sin cortes aunque el juego vaya lento) pone «Midnight Cauldron» como título de la pestaña (el nombre interno del proyecto sigue siendo «Caldero Nocturno»: nombra la carpeta de las partidas guardadas, también en el navegador), usa una página propia (`game/tools/web/shell.html`: la de Godot con el color, la imagen y la barra del juego) y no exporta si algún script usa `AudioServer.add_bus()`, que en la web deja el juego sin sonido (los buses se crean agrandando `AudioServer.bus_count`, ver `game/scripts/sfx.gd`).
