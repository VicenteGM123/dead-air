# Caldero Nocturno

Una tiendita de pociones en 2.5D (estilo HD-2D) hecha en Godot 4.7. El proyecto está en `game/` (ver `game/README.md`: cómo se juega y dónde cambiar cosas) y la versión web en `web/`.

Se juega en https://vicentegm123.github.io/dead-air/caldero/web/

## Mando (Xbox y compatibles)

El mando lleva un cursor dorado que hace de ratón: aparece al usar el mando y se esconde al mover el ratón.

| Botón | Qué hace |
|---|---|
| Stick izquierdo / cruceta | mover el cursor (al soltarlo sobre algo tocable, o cerca, se centra solo) |
| A | tocar donde está el cursor (o avanzar el diálogo) |
| B | volver / cerrar la ventana abierta |
| X | avanzar diálogos y remover (como `Espacio`) |
| Y | libro de recetas |
| Vista | diario de viajeros |
| Menú | ajustes |
| LB / RB | saltar al objeto tocable anterior / siguiente |
| Stick derecho | desplazar listas |

En el navegador, el sonido empieza con el primer clic o tecla: los navegadores no cuentan el mando como interacción (la pantalla de título lo avisa).

## Versión web

Se genera con `tools/export_web.sh` (necesita Godot 4.7 con las plantillas de exportación web):

```
GODOT=/ruta/a/godot sh caldero/tools/export_web.sh
```

Usa el preset "Web" del proyecto (renderizador Compatibility / WebGL 2, sin hilos, para que funcione en GitHub Pages) y deja el resultado en `web/`. Además arregla el audio web de Godot 4.7 en `index.js` (los sonidos en bucle, como la música, el fuego y los grillos, se repiten en el hilo de audio: sin cortes aunque el juego vaya lento) y no exporta si algún script usa `AudioServer.add_bus()`, que en la web deja el juego sin sonido (los buses se crean agrandando `AudioServer.bus_count`, ver `game/scripts/sfx.gd`).
