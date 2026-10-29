Secondhand Stars · tools/arte (generadores de arte en Python; Godot no los exporta: tools/* está excluido)
=======================================================================================================

Cómo correrlos: python3 con pillow, numpy y scipy (el python3 del sistema ya los trae). fonts_ss.py necesita además
fontTools: el venv del scratchpad lo tiene (/tmp/claude-0/-home-user-dead-air/84a550d9-2edd-52f7-8fa3-04790d444022/scratchpad/venv/bin/python;
también scratchpad/pyenv/site con PYTHONPATH). Desde la carpeta game/:

  python3 tools/arte/ss_placeholders.py [--sheet hoja.png]   el arte de RELLENO de la semilla (personajes, sombra,
                                                             emociones, cursor, icono, texturas seed_*.png)
  python3 tools/arte/chars64.py --out assets/chars nell zib  personajes con el kit (fichas en c64cast_ss.py)
  python3 tools/arte/chars64.py --list                       los ids del elenco
  python3 tools/arte/chars64.py --cast-sheet hoja.png        además la hoja del elenco (sale en ./salida/chars)
  python3 tools/arte/chars64.py --mc alquimista              un personaje de Midnight Cauldron (ejemplo de ficha)
  <venv>/bin/python tools/arte/fonts_ss.py                   las fuentes recortadas + sus licencias (assets/fonts)

Después de cambiar imágenes: godot --headless --path game --import

Archivos:
  pixlib.py        kit chico de pixel art (rampas con matiz, sombreado y contorno automáticos, ASCII -> imagen)
  c64core.py       lienzo por partes, máscaras, render cel con contorno (personajes 64x96)
  c64body.py       especies (cuerpos), poses quieto / caminar, cabezas con anclas
  c64parts.py      cara, orejas, ropa, calzado          c64hair.py  pelo y barbas
  c64acc.py        objetos (gafas, mochila, cascos...)  c64hat.py   tocados que contienen el pelo
  c64cat.py        un cuadrúpedo (la gata de Midnight Cauldron; ejemplo)
  chars64.py       el generador: ficha -> idle (2 cuadros) + walk (4 cuadros), hoja del elenco
  c64cast_ss.py    el elenco de Secondhand Stars (RELLENO de la semilla: ART pone aquí los diseños reales)
  c64cast_mc.py    el elenco de Midnight Cauldron, solo como ejemplos de fichas
  ss_placeholders.py  el arte de relleno de la semilla (incluye a Kettle dibujado a mano: el kit solo hace humanoides)
  fonts_ss.py      Inter (OFL), Secondhand Mono (= Liberation Mono Bold recortada, OFL), Secondhand Symbols (DejaVu)
  (el kit c64*, pixlib y chars64 vienen de Midnight Cauldron, caldero/game/tools/arte, sin cambios en el generador)

Formato de los personajes (lo lee scripts/world/actor.gd): assets/chars/<id>_idle.png = 2 cuadros de 64x96 en fila
(128x96), <id>_walk.png = 4 cuadros (256x96); miran a la DERECHA (el juego los da vuelta), pies en la fila 91,
adultos de 60-64 px de alto.
