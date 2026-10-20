# Caldero Nocturno

Una tiendita de pociones en 2.5D (estilo HD-2D) hecha en Godot 4.7. El proyecto está en `game/` (ver `game/README.md`: cómo se juega y dónde cambiar cosas) y la versión web en `web/`.

Se juega en https://vicentegm123.github.io/dead-air/caldero/web/

## Novedades (ronda 4)

- **Un día de 5 minutos:** al abrir corre un reloj de 9:00 a 18:00. La gente entra y **hace fila dentro de la tienda** (4 esperando y 1 en el mostrador), cada uno con su **paciencia** (un reloj de arena sobre la cabeza): si se acaba, se va molesto. Cuanto más rápido atiendes, más vendes; cada 4 días es **día de mercado** y viene más gente.
- **Las cuentas del día:** de noche, una hoja con los atendidos, los que se fueron, la espera media, lo ganado y el renombre.
- **El Escalafón del Gremio de Boticarios de Arvendal:** 30 tiendas y la tuya empieza última. Cada mañana el correo trae tu puesto, cada 5 días llega la **Gaceta del Gremio**, y al llegar al **puesto 1** hay un final con fiesta (después se sigue jugando).
- **Krápido**, pociones a pico y pluma: la ventanilla del cuervo, una mejora del puesto de Mabel. Los pedidos llegan primero a la **bola de cristal**; después **Graznido** pasa a buscarlos y espera un minuto en la percha. Sus reseñas en plumas deciden cuántos pedidos llegan.
- **Eventos:** invitaciones por carta al **Examen de la Academia de Magia**, al **Concurso de Pociones de Robledal** y a la **Feria del Torneo**. Si aceptas, ese día no abres: viajas y lo juegas en su propio escenario, y vuelves con una medalla (renombre, oro, puntos y un trofeo) o sin ella (pierdes renombre).

## Teclado y ratón

| Tecla | Qué hace |
|---|---|
| Clic | tocar: un lugar o un objeto de la tienda (ella camina hasta allí y lo usa), un puesto del mercado, un botón |
| Clic en el suelo, `A` / `D` o las flechas | caminar |
| `E` | usar el lugar donde está la alquimista: el caldero abre el banco, el escritorio de la biblioteca abre el grimorio, la puerta lleva al mercado (por la mañana) |
| `Espacio` | avanzar diálogos y remover |
| `R` / `J` | recetario / diario (`←` `→` o la rueda pasan las hojas) |
| `G` | el Escalafón del Gremio (también la copa del menú de arriba) |
| `Esc` | ajustes (o cerrar la ventana abierta) |

En el **banco del caldero**: `1`–`8` echan un frasco, `Espacio` remueve o embotella, `Retroceso` saca el último y `Esc` o `E` lo cierran.
En el **grimorio** (el escritorio de la biblioteca): flechas e `Intro` para elegir y `Esc` para cerrar; la runa se traza con el ratón, las flechas o `WASD`, y `Esc` suelta la pluma sin gastar tinta.
En la **bola de cristal** de Krápido (junto a la ventanilla; se abre con un clic o con `E` en la ventanilla): `←` `→` eligen una poción, `Intro` o `Espacio` se la dan a Graznido, `1`–`5` destacan un pedido y `Esc` o `E` la cierran.
En un **evento**: `E` abre el caldero del evento y `Espacio` o `Intro` aceptan sus tarjetas (el jurado, los resultados).

## Mando (Xbox y compatibles)

El mando lleva un cursor dorado que hace de ratón: aparece al usar el mando y se esconde al mover el ratón.

| Botón | Qué hace |
|---|---|
| Stick izquierdo | mover el cursor (al soltarlo sobre algo tocable, o cerca, se centra solo) |
| Cruceta izquierda / derecha | caminar (con una ventana o un diálogo abiertos, mueve el cursor) |
| A | tocar donde está el cursor (o avanzar el diálogo) |
| B | volver / cerrar la ventana abierta (también el banco del caldero y la bola de cristal) |
| X | avanzar diálogos y remover (como `Espacio`) |
| Y | recetario |
| Vista | diario de viajeros |
| Menú | ajustes |
| LB / RB | saltar al objeto tocable anterior / siguiente (lugares de la tienda, puestos del mercado, frascos del banco, páginas del grimorio, pedidos de la bola, botones de los eventos) |
| LT / RT | pasar las hojas del recetario y del diario |
| Stick derecho | desplazar listas |

En el navegador, el sonido empieza con el primer clic o tecla: los navegadores no cuentan el mando como interacción (la pantalla de título lo avisa).

## Versión web

Se genera con `tools/export_web.sh` (necesita Godot 4.7 con las plantillas de exportación web):

```
GODOT=/ruta/a/godot sh caldero/tools/export_web.sh
```

Usa el preset "Web" del proyecto (renderizador Compatibility / WebGL 2, sin hilos, para que funcione en GitHub Pages) y deja el resultado en `web/`. Además arregla el audio web de Godot 4.7 en `index.js` (los sonidos en bucle, como la música, el fuego y los grillos, se repiten en el hilo de audio: sin cortes aunque el juego vaya lento) y no exporta si algún script usa `AudioServer.add_bus()`, que en la web deja el juego sin sonido (los buses se crean agrandando `AudioServer.bus_count`, ver `game/scripts/sfx.gd`).
