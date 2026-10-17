# Caldero Nocturno

Una tiendita de pociones en 2.5D (estilo HD-2D) hecha en Godot 4.7. El proyecto está en `game/` (ver `game/README.md`: cómo se juega y dónde cambiar cosas) y la versión web en `web/`.

Se juega en https://vicentegm123.github.io/dead-air/caldero/web/

La versión web se genera con el preset "Web" del proyecto (renderizador Compatibility / WebGL 2, sin hilos, para que funcione en GitHub Pages):

```
godot --headless --path caldero/game --export-release "Web" "$PWD/caldero/web/index.html"
```
