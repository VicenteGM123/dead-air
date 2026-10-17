# Caldero Nocturno

Una tiendita de pociones en 2.5D (estilo HD-2D): pixel art dentro de un escenario 3D con luz cálida, desenfoque de maqueta y rayos de luz por la ventana. Llegan aventureros con problemas, tú adivinas qué poción necesitan, la preparas en el caldero y se la entregas. Con el tiempo crece tu renombre, se desbloquean ingredientes, mejoras para la tienda y las historias de seis viajeros.

## Cómo abrirlo

1. Instala **Godot 4.7** (versión estándar, no la .NET) desde godotengine.org.
2. Abre Godot → **Importar** → elige `project.godot` de esta carpeta.
3. La primera vez tarda unos segundos en importar las imágenes. Luego pulsa **F5** para jugar.

Está hecho y probado con Godot 4.7.2 usando el renderizador Forward+. Si tu computador es antiguo y no lo soporta, Godot cambia solo a OpenGL (se verá algo más simple).

## Cómo se juega

- **Mañana:** compras ingredientes y mejoras en el Mercado. Puedes preparar pociones antes de abrir.
- **Tienda abierta:** cada cliente cuenta su problema. Puedes pedir una pista.
- **Caldero:** toca los frascos del estante para echar ingredientes (2, o 3 con la mejora). La poción la deciden las **dos esencias más fuertes** de la mezcla. Pulsa **Remover** y acierta la zona dorada para +1 de potencia.
- **Entregar:** toca una poción de tu estante (abajo a la derecha). Si no es la correcta, el cliente te la devuelve y puedes probar otra.
- **Noche:** resumen del día, nuevas páginas en el Diario de viajeros, y a dormir.
- Acaricia a **Miga**, la gata. Con el cojín te da suerte.

Atajos: `Espacio` avanza diálogos y remueve, `R` libro de recetas, `J` diario, `Esc` ajustes.
La partida se guarda sola al empezar cada día y después de cada cliente.

## Dónde cambiar cosas

| Quiero cambiar… | Archivo |
|---|---|
| Ingredientes, pociones, precios, mejoras, niveles, historias y pedidos | `scripts/data.gd` |
| Reglas de alquimia, economía, guardado, qué clientes llegan | `scripts/game.gd` |
| Flujo del día, tutorial, entregas | `scripts/main.gd` |
| Escenario 3D, posiciones, luces y hora del día | `scripts/world/shop_world.gd` |
| Caldero (fuego, burbujas, vapor) | `scripts/world/cauldron.gd` |
| Interfaz (HUD, diálogo, paneles) | `scripts/ui/game_ui.gd`, `scripts/ui/overlays.gd`, `scripts/ui/ui_kit.gd` |
| Efecto de maqueta, viñeta y color | `shaders/hd2d_post.gdshader` |

Todo el arte está en `assets/`. Los sprites miran a la derecha y miden 32×48 píxeles (personajes). Puedes reemplazar cualquier PNG por uno tuyo con el mismo nombre y tamaño.

En `tools/arte/` están los scripts de Python que generaron el pixel art, las texturas, la música y los sonidos (necesitan `pillow`, `numpy`, `scipy` y `ffmpeg`). Godot ignora esa carpeta.

### Ideas para seguir

- Un nuevo aventurero: agrega su sprite en `assets/chars/` (archivos `nombre_idle.png` de 2 cuadros y `nombre_walk.png` de 4 cuadros), su entrada en `CHARACTERS` y sus tres capítulos en `HEROES`.
- Un ingrediente nuevo: su ícono en `assets/icons/ing_<id>.png`, su frasco en `assets/props/jar_<id>.png` y su entrada en `INGREDIENTS` e `INGREDIENT_ORDER`.
- Clientes que vuelven otro día contando cómo les fue, eventos de temporada, o un desafío diario con ranking.

## Créditos

- Fuentes: Alegreya y Alegreya SC, de Huerta Tipográfica, con licencia SIL Open Font License (ver `assets/fonts/OFL-Alegreya.txt`).
- Pixel art, texturas, música y efectos de sonido: generados por código para este proyecto.
