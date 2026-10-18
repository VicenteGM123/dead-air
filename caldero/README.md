# Caldero Nocturno

Una tiendita de pociones en 2.5D (estilo HD-2D) hecha en Godot 4.7. El proyecto está en `game/` (ver `game/README.md`: cómo se juega y dónde cambiar cosas) y la versión web en `web/`.

Se juega en https://vicentegm123.github.io/dead-air/caldero/web/

## Novedades

- **Pociones en su propia pantalla:** al usar el caldero se abre el banco: los frascos a la izquierda, el caldero grande a la derecha. Tocas un frasco y cae dentro; luego Remover y Embotellar.
- **El grimorio encanta pociones:** algunos pedidos traen una runa en su ticket (Prisa, Calma, Dulzor…). Preparas la poción, la encantas en el escritorio de la biblioteca trazando la runa y la entregas. Ya no hay pergaminos.
- **Menos texto, más papel:** el pedido es un ticket clavado arriba; el recetario, el diario, el correo y los puestos del mercado son hojas de papel con letra a mano.
- **El mercado:** por la mañana, precio normal; de día el encargo cuesta el doble (x2). La fuente de la plaza ahora tiene agua.
- **La tienda y el elenco:** el mostrador cruza la tienda y ella pasa por una trampilla; los gorros y cascos cubren el pelo, los pies son nuevos y la alquimista ya no sostiene una poción.

## Teclado y ratón

| Tecla | Qué hace |
|---|---|
| Clic | tocar: un lugar o un objeto de la tienda (ella camina hasta allí y lo usa), un puesto del mercado, un botón |
| Clic en el suelo, `A` / `D` o las flechas | caminar |
| `E` | usar el lugar donde está la alquimista: el caldero abre el banco, el escritorio de la biblioteca abre el grimorio, la puerta lleva al mercado (por la mañana) |
| `Espacio` | avanzar diálogos y remover |
| `R` / `J` | recetario / diario (`←` `→` o la rueda pasan las hojas) |
| `Esc` | ajustes (o cerrar la ventana abierta) |

En el **banco del caldero**: `1`–`8` echan un frasco, `Espacio` remueve o embotella, `Retroceso` saca el último y `Esc` o `E` lo cierran.
En el **grimorio** (el escritorio de la biblioteca): flechas e `Intro` para elegir y `Esc` para cerrar; la runa se traza con el ratón, las flechas o `WASD`, y `Esc` suelta la pluma sin gastar tinta.

## Mando (Xbox y compatibles)

El mando lleva un cursor dorado que hace de ratón: aparece al usar el mando y se esconde al mover el ratón.

| Botón | Qué hace |
|---|---|
| Stick izquierdo | mover el cursor (al soltarlo sobre algo tocable, o cerca, se centra solo) |
| Cruceta izquierda / derecha | caminar (con una ventana o un diálogo abiertos, mueve el cursor) |
| A | tocar donde está el cursor (o avanzar el diálogo) |
| B | volver / cerrar la ventana abierta (también el banco del caldero) |
| X | avanzar diálogos y remover (como `Espacio`) |
| Y | recetario |
| Vista | diario de viajeros |
| Menú | ajustes |
| LB / RB | saltar al objeto tocable anterior / siguiente (lugares de la tienda, puestos del mercado, frascos del banco, páginas del grimorio) |
| LT / RT | pasar las hojas del recetario y del diario |
| Stick derecho | desplazar listas |

En el navegador, el sonido empieza con el primer clic o tecla: los navegadores no cuentan el mando como interacción (la pantalla de título lo avisa).

## Versión web

Se genera con `tools/export_web.sh` (necesita Godot 4.7 con las plantillas de exportación web):

```
GODOT=/ruta/a/godot sh caldero/tools/export_web.sh
```

Usa el preset "Web" del proyecto (renderizador Compatibility / WebGL 2, sin hilos, para que funcione en GitHub Pages) y deja el resultado en `web/`. Además arregla el audio web de Godot 4.7 en `index.js` (los sonidos en bucle, como la música, el fuego y los grillos, se repiten en el hilo de audio: sin cortes aunque el juego vaya lento) y no exporta si algún script usa `AudioServer.add_bus()`, que en la web deja el juego sin sonido (los buses se crean agrandando `AudioServer.bus_count`, ver `game/scripts/sfx.gd`).
