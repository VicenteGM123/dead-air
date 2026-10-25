# Midnight Cauldron (Caldero Nocturno)

Una tiendita de pociones en 2.5D (estilo HD-2D) hecha en Godot 4.7. Desde la ronda 5 el juego está **todo en inglés** (esta documentación sigue en español). El proyecto está en `game/` (ver `game/README.md`: cómo se juega y dónde cambiar cosas) y la versión web en `web/`.

Se juega en https://vicentegm123.github.io/dead-air/caldero/web/

## Novedades (ronda 5)

- **Todo en inglés:** textos, cartas, diálogos, carteles 3D, la Gaceta, los eventos y el final. Las partidas guardadas siguen: al continuar, lo guardado en español (cartas pendientes, diario, noticias) se vuelve a escribir en inglés.
- **Nombres nuevos:**

| Antes | Ahora |
|---|---|
| Caldero Nocturno (el juego y su tienda) | **Midnight Cauldron** |
| Krápido · Ventanilla Krápido | **Crow Delivery**, “Potions by beak and feather” · **Crow Window** |
| Graznido, el cuervo · plumas | **Squawk** · **feathers** |
| Escalafón del Gremio · La Gaceta del Gremio | **Guild Rankings** · **The Guild Gazette** |
| Fizz y Chispa | **Fizz & Spark** |
| Valdelago · Robledal · Brisaclara · la Montaña Gris | **Lakevale** · **Oakdale** · **Clearbreeze** · **the Grey Mountain** |
| Examen de la Academia · Concurso de Robledal · Feria del Torneo | **The Academy of Magic Exam** · **The Oakdale Potion Contest** · **The Clearbreeze Tournament Fair** |

- **Las paredes que temblaban:** al fondo y a los lados de la tienda había paredes dobles (el yeso y la piedra en el mismo lugar exacto) y la tarjeta gráfica alternaba entre las dos en cada cuadro. Arreglado en la tienda y revisado en todo el juego (mercado, eventos, título y final): ninguna superficie queda encima de otra.
- **La fachada del mercado:** ya no hay una puerta ajena al lado de la tienda: todo el frente es la tienda (una puerta, el letrero **Midnight Cauldron**, escaparate y ventanas). Con Crow Delivery comprado aparece ahí la ventanilla del cuervo.

## Teclado y ratón

| Tecla | Qué hace |
|---|---|
| Clic | tocar: un lugar o un objeto de la tienda (ella camina hasta allí y lo usa), un puesto del mercado, un botón |
| Clic en el suelo, `A` / `D` o las flechas | caminar |
| `E` | usar el lugar donde está la alquimista: el caldero (**Cauldron**) abre el banco, el escritorio de la biblioteca (**Library · grimoire**) abre el grimorio, la puerta (**Door · to the market**) lleva al mercado por la mañana |
| `Espacio` | avanzar diálogos y remover (**Stir**) |
| `R` / `J` | recetario (**Recipes**) / diario (**Journal**) (`←` `→` o la rueda pasan las hojas) |
| `G` | el **Guild Rankings** (también la copa del menú de arriba) |
| `Esc` | ajustes (**Settings**), o cerrar la ventana abierta |

En el **banco del caldero**: `1`–`8` echan un frasco, `Espacio` remueve o embotella (**Stir** / **Bottle**), `Retroceso` saca el último y `Esc` o `E` lo cierran.
En el **grimorio** (el escritorio de la biblioteca): flechas e `Intro` para elegir y `Esc` para cerrar; la runa se traza con el ratón, las flechas o `WASD`, y `Esc` suelta la pluma sin gastar tinta.
En la **bola de cristal** de Crow Delivery (junto a la ventanilla; se abre con un clic o con `E` en la ventanilla): `←` `→` eligen una poción, `Intro` o `Espacio` se la dan a Squawk, `1`–`5` destacan un pedido y `Esc` o `E` la cierran.
En un **evento**: `E` abre el caldero del evento (**Cauldron**) y `Espacio` o `Intro` aceptan sus tarjetas (**Next round**, **See results**, **Head home**).

## Mando (Xbox y compatibles)

El mando lleva un cursor dorado que hace de ratón: aparece al usar el mando y se esconde al mover el ratón.

| Botón | Qué hace |
|---|---|
| Stick izquierdo | mover el cursor (al soltarlo sobre algo tocable, o cerca, se centra solo) |
| Cruceta izquierda / derecha | caminar (con una ventana o un diálogo abiertos, mueve el cursor) |
| A | tocar donde está el cursor (o avanzar el diálogo) |
| B | volver / cerrar la ventana abierta (también el banco del caldero y la bola de cristal) |
| X | avanzar diálogos y remover (como `Espacio`) |
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

Usa el preset "Web" del proyecto (renderizador Compatibility / WebGL 2, sin hilos, para que funcione en GitHub Pages) y deja el resultado en `web/`. Además arregla el audio web de Godot 4.7 en `index.js` (los sonidos en bucle, como la música, el fuego y los grillos, se repiten en el hilo de audio: sin cortes aunque el juego vaya lento) pone «Midnight Cauldron» como título de la pestaña (el nombre interno del proyecto sigue siendo «Caldero Nocturno»: nombra la carpeta de las partidas guardadas, también en el navegador), y no exporta si algún script usa `AudioServer.add_bus()`, que en la web deja el juego sin sonido (los buses se crean agrandando `AudioServer.bus_count`, ver `game/scripts/sfx.gd`).
