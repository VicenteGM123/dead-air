# Caldero Nocturno

Una tiendita de pociones en 2.5D (estilo HD-2D) hecha en Godot 4.7. El proyecto está en `game/` (ver `game/README.md`: cómo se juega y dónde cambiar cosas) y la versión web en `web/`.

Se juega en https://vicentegm123.github.io/dead-air/caldero/web/

## Novedades

La tienda ahora se recorre a pie: la alquimista camina entre la biblioteca, el caldero, el mostrador y la puerta, y por la mañana puede salir al mercado, una calle con puestos y gente que pasea. En la biblioteca, el grimorio de su maestra le enseña a escribir pergaminos mágicos, que se venden como las pociones. Los clientes ya no dicen en el acto si la poción les sirvió: se la llevan, y cómo les fue llega después, por carta a la mañana siguiente o cuando vuelven a la tienda. Y el pueblo tiene un elenco nuevo (elfos, enanos, gente bestia, caballeros, magos, campesinos…): los personajes ahora son sprites de 64x96 píxeles al estilo de Octopath Traveler.

## Teclado y ratón

| Tecla | Qué hace |
|---|---|
| Clic | tocar: un lugar o un objeto de la tienda (ella camina hasta allí y lo usa), un puesto del mercado, un botón |
| Clic en el suelo, `A` / `D` o las flechas | caminar |
| `E` | usar el lugar donde está la alquimista |
| `Espacio` | avanzar diálogos y remover |
| `R` | libro de recetas |
| `J` | diario de viajeros |
| `Esc` | ajustes (o cerrar la ventana abierta) |

En la runa del grimorio también se traza con las flechas o `WASD`; `Esc` la cancela sin gastar nada.

## Mando (Xbox y compatibles)

El mando lleva un cursor dorado que hace de ratón: aparece al usar el mando y se esconde al mover el ratón.

| Botón | Qué hace |
|---|---|
| Stick izquierdo | mover el cursor (al soltarlo sobre algo tocable, o cerca, se centra solo) |
| Cruceta izquierda / derecha | caminar (con una ventana o un diálogo abiertos, mueve el cursor) |
| A | tocar donde está el cursor (o avanzar el diálogo) |
| B | volver / cerrar la ventana abierta |
| X | avanzar diálogos y remover (como `Espacio`) |
| Y | libro de recetas |
| Vista | diario de viajeros |
| Menú | ajustes |
| LB / RB | saltar al objeto tocable anterior / siguiente (también los lugares de la tienda y los puestos del mercado) |
| Stick derecho | desplazar listas |

En el navegador, el sonido empieza con el primer clic o tecla: los navegadores no cuentan el mando como interacción (la pantalla de título lo avisa).

## Versión web

Se genera con `tools/export_web.sh` (necesita Godot 4.7 con las plantillas de exportación web):

```
GODOT=/ruta/a/godot sh caldero/tools/export_web.sh
```

Usa el preset "Web" del proyecto (renderizador Compatibility / WebGL 2, sin hilos, para que funcione en GitHub Pages) y deja el resultado en `web/`. Además arregla el audio web de Godot 4.7 en `index.js` (los sonidos en bucle, como la música, el fuego y los grillos, se repiten en el hilo de audio: sin cortes aunque el juego vaya lento) y no exporta si algún script usa `AudioServer.add_bus()`, que en la web deja el juego sin sonido (los buses se crean agrandando `AudioServer.bus_count`, ver `game/scripts/sfx.gd`).
