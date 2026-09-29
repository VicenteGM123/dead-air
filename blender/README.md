# DEAD AIR — pipeline de assets en Blender

Todos los assets 3D del juego (props, armas, personajes, arquitectura de la estación, mallas estáticas de los
sistemas) se **generan con código Python** (bpy) a partir de los ports 1:1 de los módulos JS de `src/`, y se exportan
a glTF (`.glb`) dentro de `godot/assets/`. Para mejorar un asset se edita su script y se vuelve a exportar.

```
blender/
  build_all.py        punto de entrada (este README)
  dalib/              librería común
    kit.py            port de src/props/kit.js (registro, materiales, geometría, bakeAO, finish, THREE, game)
    scene.py          grafo tipo three.js (Object3D/Group/Mesh/InstancedMesh, Material) + conversión a Blender
    export.py         escena Blender -> GLB (ajustes SPEC §5.3), enlace de texturas, variantes, index.json
    tex.py            texturas de canvas estáticas: kit.js `tex`, src/core/textures.js, src/world/decals.js
    canvas2d.py       CanvasRenderingContext2D sobre skia-python (mismas llamadas que el JS)
    vendor.py         instala skia-python / uharfbuzz en blender/_vendor la primera vez
    three_geo.py geo.py mathutils3.py rng.py pal.py   (port de three.js / geo.js / config.js — otro agente)
    cards_info.json   tamaños y atlas de las "cards" (src/gfx/cards.js cardInfo)
  props/
    __init__.py       lista de categorías (load_all importa cada módulo, que registra sus props)
    samples.py        port de src/props/_samples.js: EL EJEMPLO a imitar
    <categoria>.py    broadcast, furniture, sets, weapons, machines, sponsors, outdoor (ports de src/props/*.js)
    variants.json     variantes (id, opts, key) que se exportan
  tools/
    compare_ref.py    compara un prop construido con la referencia JS ($REF/props/<key>.json)
    compare_glb.py    compara dos GLB vértice a vértice (posición, normal, UV, color)
    open_prop.py      construye un prop dentro de la escena abierta de Blender para verlo
  out/                .blend guardados con --save-blend (ignorado por git)
  _vendor/            paquetes pip instalados automáticamente (ignorado por git)
```

## Requisitos

* **Blender 4.2 o superior** (probado con Blender/bpy 5.0.1). También funciona con `bpy` instalado como módulo de
  Python (`pip install bpy`), que es como se usa en el contenedor de desarrollo.
* **numpy**: viene con Blender.
* **skia-python** (dibujo de canvas, es el mismo motor que usa Chrome) y **uharfbuzz** (kerning de texto como
  Chrome): **se instalan solos** la primera vez que se ejecuta el pipeline. `dalib/vendor.py` lanza
  `python -m pip install --target blender/_vendor skia-python uharfbuzz` con el Python que esté corriendo (el de
  Blender si se ejecuta dentro de Blender) y añade `blender/_vendor` al `sys.path`. Necesita internet solo esa vez.
  Sin internet: copiar/instalar esos dos paquetes a mano en `blender/_vendor/` (misma versión de Python que Blender).
  Para forzar una reinstalación, borrar `blender/_vendor/`.
* Fuentes: las cuatro del juego están en `godot/assets/fonts/*.woff` (Bungee, Titan One, Shrikhand, VT323). Otras
  familias (`"Times New Roman"`, `serif`, `sans-serif`…) se buscan en el sistema como hace Chrome
  (sans-serif = Arial/Liberation Sans, serif = Times New Roman/Liberation Serif).

## Cómo ejecutarlo

Desde la raíz del repositorio:

```bash
# con Blender instalado (modo consola, sin interfaz)
blender --background --python blender/build_all.py -- --only props
blender --background --python blender/build_all.py -- --only props --id sample_portable_tv --save-blend

# con bpy como módulo de Python (el contenedor de desarrollo)
python3 blender/build_all.py --only props --id telly
python3 blender/build_all.py --only props --key telly__012
python3 blender/build_all.py --list                       # props registrados por categoría
```

También se puede abrir `blender/build_all.py` en la pestaña *Scripting* de Blender y pulsar *Run Script* (construye
todo). Opciones:

| opción | qué hace |
|---|---|
| `--only props` | cada variante de `props/variants.json` (o solo las de `--id` / `--key`) → `godot/assets/props/<key>.glb` y reescribe `godot/assets/props/index.json` |
| `--only textures` | solo vuelve a pintar los PNG de las texturas de canvas que usan esos props (sin exportar GLB) |
| `--only chars` / `world` / `runtime` | llama a `blender/<seccion>/build.py: build(ids, save_blend, godot)` (los escriben esos ports) |
| `--id a,b` / `--key k` | limita a esos props / variantes (repetible o separado por comas) |
| `--save-blend` | guarda además `blender/out/<key>.blend` para abrirlo y editarlo en Blender |
| `--godot DIR` | escribe en otra copia del proyecto Godot (pruebas) |
| `--stop-on-error` | se detiene en el primer fallo |

Sin `--only` construye props, chars, world y runtime. Cada asset se construye en una escena vacía nueva
(`read_factory_settings(use_empty=True)`), así los nombres son deterministas.

## Qué se genera

* `godot/assets/props/<key>.glb` — un GLB por **variante** (id + opts). `key = <id>__<nnn>`.
* `godot/assets/props/index.json` — `{ "<id>": [ {"key": "<key>", "opts": {…}}, … ] }` (lo lee `props.gd`).
* `godot/assets/textures/<nombre>.png` + `.png.import` — texturas de canvas **compartidas** (ver abajo) y
  `godot/assets/textures/index.json` (clave de textura → fichero, tamaño, wrap).
* `blender/out/<key>.blend` con `--save-blend`.

## Editar un prop y volver a exportar

1. Buscar el prop: `grep -n "registerProp('telly'" blender/props/*.py`. Cada builder es la traducción línea a
   línea de su función JS (`src/props/<categoria>.js`), con los mismos nombres y números.
2. Editar el código (medidas, colores, piezas…). Todas las coordenadas son **las de three.js** (Y arriba, el frente
   del prop mira a −Z, metros); nunca hay que pensar en los ejes de Blender.
3. Exportar: `python3 blender/build_all.py --only props --id telly` (o con `blender --background …`).
4. Verlo en Blender: añadir `--save-blend` y abrir `blender/out/telly__NNN.blend`, o desde la pestaña *Scripting*
   ejecutar `blender/tools/open_prop.py` (construye el prop en la escena abierta sin tocar nada más; con
   `-- telly --clear` reemplaza la copia anterior).
5. Godot reimporta el GLB al abrir el proyecto (o `godot --headless --import`).
6. Comprobar que sigue igual que el juego JS: `python3 blender/tools/compare_ref.py telly`.

Para **añadir una variante** (otras opts de un prop existente) basta añadir una línea a `props/variants.json`
(`{"id": "telly", "opts": {...}, "key": "telly__351"}`, clave nueva y única) y exportar ese id. `props.gd` elige la
variante cuyas opts coinciden con las pedidas.

## Formato de los GLB (contrato con Godot, SPEC §5.2–5.5)

* **Ejes**: el grafo está en coordenadas three.js; `scene.py` convierte a Blender (x, −z, y) y el exportador glTF
  (+Y arriba) lo devuelve exactamente a three.js. En Godot las coordenadas son las del JS.
* **Nodos**: la raíz se llama como el grupo JS (`prop:telly` → `prop_telly`); los hijos conservan su nombre JS
  (`screen`, `shade`, …); los que no tienen nombre reciben `mesh`, `mesh_1`, `group_2`… (orden de recorrido,
  deterministas). Los nombres repetidos llevan `_1`, `_2`. Se sustituyen los caracteres que Godot no admite
  (`: . / @ " %`) y se evitan los sufijos que el importador de Godot interpreta (`-col`, `_wheel`, `-rigid`…).
  Al instanciar el `.glb` en Godot se obtiene un Node3D envoltorio llamado `<key>` cuyo único hijo es la raíz.
* **"da"** (propiedad personalizada → `get_meta("extras")["da"]`, un **string JSON**):
  * raíz: el `userData` del JS (`id, size, colliders, lightAnchors, parts, screens, interact, stats, …`),
    `parts: {nombre: "<nombre de nodo>"}`, `screens: [{node, group, id?}]`, cualquier otra referencia a un
    Object3D → `{"__node": "<nombre>"}`, materiales → `{"__material": spec}`, texturas → `{"__texture": …}`.
  * hijos: sus flags de `userData` (`noMerge`, `noShadow`, `noAO`, `screenGroup`, …) + `castShadow` (según las
    reglas de `finish()`), `receiveShadow: false`, `visible: false`, `renderOrder`, `layers`, `rotationOrder`
    cuando no son los valores por defecto.
  * `InstancedMesh`: nodo padre `<nombre>` con `{"instanced": true, "count": n}` y un hijo `<nombre>_<i>` por
    instancia con `{"instance": i, "instanceColor": [r,g,b]}` (lineal; lo aplica `props.gd`).
* **Materiales**: cada material lleva "da" = la especificación (SPEC §5.5) que `materials.gd fromSpec()` convierte
  en el mismo shader que el JS: `{kind: toon|glow|basic|screen|…, color, opts (las opts de la fábrica JS, side como
  "front"/"back"/"double"), map, mapFile, mapWrap, mapFilter, flipY, card, cardOpts, screen{w,h,bulge,bright,group,
  id}, userData}`. El Principled BSDF de Blender es solo una vista previa (color, rugosidad, metal, emisión, alfa,
  textura).
* **Vértices**: posiciones y **normales exactas** de three.js (en Blender ≥ 4.5 como "free normals"), `COLOR_0` =
  colores de vértice lineales (incluye el AO horneado por `bakeAO`), `TEXCOORD_0` = **el uv de three.js** (la
  repetición/offset de la textura JS ya viene multiplicada en las UV).
* **Merge**: `finish()` fusiona las mallas estáticas por material como el JS (`mergeByMaterial`), así la estructura
  (y las rutas de nodos) coinciden con la referencia JS; las piezas `noMerge` y los grupos animables quedan aparte.

### Decisión sobre las texturas: PNG externos compartidos

Las texturas de canvas **no** se incrustan en cada GLB. `tex.texture_file()` escribe cada una una sola vez en
`godot/assets/textures/<nombre>.png` y el GLB apunta a ella con una `uri` relativa (`../textures/<nombre>.png`).
Motivos:

* una textura usada por 40 props (la madera de teca, la moqueta…) es **un solo recurso** en Godot (memoria, tiempo de
  importación, tamaño del repositorio);
* con imágenes incrustadas Godot las extrae junto a cada `.glb` (cientos de PNG duplicados en `assets/props/`).

Verificado con Godot 4.7: el importador carga la `uri` como el recurso del proyecto
(`res://assets/textures/…png`), y respeta el `.png.import` que escribe el pipeline la primera vez (**sin pérdida,
con mipmaps**, sin conversión automática a VRAM — igual de nítido que el canvas del JS). Godot completa ese fichero
(uid, rutas) al importar: se versiona como cualquier `.import`.

**Orientación (flipY)**: los PNG se guardan **tal como se dibujan** en el canvas (fila 0 = arriba). three.js sube
los canvas con `flipY = true`; por eso los shaders del juego (`materials.gd`) muestrean `texture(map, vec2(UV.x,
1.0 - UV.y))`, igual que con las texturas de canvas creadas en Godot en tiempo de ejecución (cards). Para que el
material estándar que crea el importador (y cualquier visor glTF, y la vista de Blender) también se vea bien, el
`textureInfo` lleva `KHR_texture_transform` (`scale [1,-1]`, `offset [0,1]`); `fromSpec` lo ignora.

## Guía del kit: cómo portar un módulo `src/props/*.js`

Mirar `props/samples.py` junto a `src/props/_samples.js`: es la traducción de referencia. Reglas:

1. **Mismos nombres, misma estructura, mismos números.** Una función JS → una función Python con el mismo nombre
   (los builders anónimos de `registerProp` se convierten en `def _nombre(game, opts=None)`). Los comentarios se
   conservan.
2. **Mismas llamadas a three.js**: el grafo (`dalib/scene.py`) y `dalib/mathutils3.py` imitan three.js (objetos
   mutables, métodos encadenables): `leg.position.copy(foot)`, `leg.quaternion.setFromUnitVectors(…)`,
   `dir.clone().multiplyScalar(d).toArray()` funcionan igual. (Al revés que en GDScript, aquí los vectores son
   referencias como en JS.)
3. **Objetos JS → dict** con las mismas claves **y en el mismo orden** (el orden importa: `JSON.stringify(opts)`
   forma parte de las claves de textura y de la semilla aleatoria). `userData` es un `JSObj` (dict con acceso
   por atributo; una clave inexistente se lee como `None`, igual que `undefined`).
4. `a ?? b` → `a if a is not None else b` (o `opts.get('k', b)` cuando la clave simplemente falta);
   `a || b` → `a or b` **cuidado**: en JS `[]` y `{}` son verdaderos y en Python no (`kit._or(v, d)` hace la
   versión JS).
5. Números: `Math.round` → `js_round` (redondea .5 hacia +∞), `x % y` → `math.fmod(x, y)` cuando puede ser
   negativo, `Math.floor(x)` como índice → `int(math.floor(x))`, `${n}` en claves → `js_str(n)`,
   `JSON.stringify(o)` → `js_json(o)` (todo en `dalib.mathutils3`). Las semillas: `mulberry32` / `hashStr` de
   `dalib.rng` (idénticos bit a bit).
6. Bucles: `for (let i = 0; i < n; i++)` → `for i in range(n)`; `arr.forEach((x, i) => …)` → `for i, x in
   enumerate(arr)`; bucles con paso real (`y += 8` hasta `<= h`) → `while`. Respetar el orden de las llamadas a
   `rand()` (Python evalúa de izquierda a derecha como JS; en `a if cond else b` se evalúa primero `cond`).
7. Nada de ejes de Blender, nada de `bpy` en los builders: solo el kit. `finish(game, g)` al final como en el JS.

### Antes / después

```js
// JS (src/props/_samples.js)
import * as K from './kit.js';
import { registerProp, PAL, THREE } from './kit.js';

registerProp('sample_side_table', (game) => {
  const g = K.prop('sample_side_table');
  const teak = K.mat(game, 'lacquer', '#ffffff', { map: K.tex.wood(PAL.teak, { dark: 0.35 }) });
  for (const [x, z] of [[-1, -1], [1, -1], [-1, 1], [1, 1]]) {
    g.add(K.m(K.box(0.05, 0.45, 0.05, 0.014, { uv: 1.6, swap: true }), teak, { pos: [x * 0.245, 0.225, z * 0.245] }));
  }
  return K.finish(game, g);
}, { category: 'samples', tags: ['table', 'living'], size: [0.56, 0.5, 0.56], desc: 'teak cube side table' });
```

```python
# Python (blender/props/samples.py)
from dalib import kit as K
from dalib.kit import registerProp, PAL, THREE

def _side_table(game, opts=None):
    g = K.prop('sample_side_table')
    teak = K.mat(game, 'lacquer', '#ffffff', {'map': K.tex.wood(PAL.teak, {'dark': 0.35})})
    for x, z in [[-1, -1], [1, -1], [-1, 1], [1, 1]]:
        g.add(K.m(K.box(0.05, 0.45, 0.05, 0.014, {'uv': 1.6, 'swap': True}), teak, {'pos': [x * 0.245, 0.225, z * 0.245]}))
    return K.finish(game, g)

registerProp('sample_side_table', _side_table,
             {'category': 'samples', 'tags': ['table', 'living'], 'size': [0.56, 0.5, 0.56], 'desc': 'teak cube side table'})
```

Más equivalencias frecuentes:

| JS | Python |
|---|---|
| `new THREE.Group()` / `new THREE.Mesh(geo, mat)` | `THREE.Group()` / `THREE.Mesh(geo, mat)` |
| `new THREE.Vector3(1, 2, 3)`, `.Color`, `.Quaternion`, `.Matrix4`, `.Euler`, `.Box3` | igual, sin `new` |
| `new THREE.CylinderGeometry(…)` y demás geometrías, `Shape`, `Path`, `CatmullRomCurve3` | igual (`dalib.three_geo`, expuesto en `K.THREE`) |
| `g.attributes.position.getX(i)` / `setXYZ` / `.count` / `.array` | igual (array numpy, se redondea a float32 como un `Float32Array`) |
| `new THREE.BufferAttribute(new Float32Array(n * 3).fill(1), 3)` | `THREE.BufferAttribute(np.ones((n, 3)), 3)` |
| `mergeGeometries(list)` (BufferGeometryUtils) | `THREE.mergeGeometries(list, False)` |
| `import { mulberry32 } from '../core/rng.js'` | `from dalib.rng import mulberry32` |
| `import { getCard, cardInfo } from '../gfx/cards.js'` | `from dalib.kit import getCard, cardInfo` (una card = referencia; Godot la dibuja) |
| `import { woodPanel } from '../core/textures.js'` | `from dalib.tex import woodPanel` (o `game.tex.woodPanel`) |
| `K.tex.canvas('key', 256, 256, (ctx, w, h, rand) => {…}, { repeat: false })` | `def draw(ctx, w, h, rand): …` + `K.tex.canvas('key', 256, 256, draw, {'repeat': False})` |
| `ctx.fillStyle = '#fff'; ctx.beginPath(); ctx.arc(…); ctx.fill()` | idéntico (`dalib.canvas2d`) |
| `document.createElement('canvas')` + `new THREE.CanvasTexture(c)` | `K.document.createElement('canvas')` + `THREE.CanvasTexture(c)` |
| `game.mats.toon / glow / basic / glass / skin / screen / rubberGlass / variant` | igual (`game` es `kit.Game()`, devuelven especificaciones) |
| `new THREE.ShaderMaterial({…})` propio (p. ej. `bubbleMat`) | `K.material('bubble', color, {'intensity': 1.1}, type='ShaderMaterial', transparent=True, depthWrite=False, blending=THREE.AdditiveBlending)` (el `kind` que conoce `materials.gd`) |
| `new THREE.InstancedMesh(geo, mat, n)`; `setMatrixAt`, `setColorAt`, `.instanceMatrix.needsUpdate` | igual |
| `mesh.userData.noMerge = true` | `mesh.userData.noMerge = True` |
| `g.userData.parts = { drum }` | `g.userData.parts = {'drum': drum}` |
| funciones en `userData` (animación en tiempo de ejecución) | no se exportan: esa lógica va al GDScript del sistema |
| `const { a = 1, b } = opts` | `a = opts.get('a', 1); b = opts.get('b')` |
| `{ ...base, ...extra }` | `{**base, **extra}` |
| `Math.max(...arr)` | `max(arr)` |

## Referencia de la API

**`dalib.kit`** (igual que `kit.js`): `registerProp(id, build, meta)`, `buildProp(id, game, opts)`,
`listProps(cat)`, `propMeta(id)`, `cloneProp(g)`, `registerScene/getScene/listScenes`; `MAT`, `mat(game, preset,
color, extra)`, `glow(game, color, intensity, opts)`, `screen(game, w, h, {card, bulge, bright, dome, group})`,
`material(kind, color, opts, **campos)`; `R`, `box(w,h,d,r,{uv,swap,seg})`, `uvBox`, `taper(geo,{axis,k,center,
ease})`, `uvRect`, `uvScale`, `weldNormals`, `cushion(w,h,d,{r,puff,seg,uv,swap})`, `roundProfile`,
`lathe(profile,{seg,round,steps})`, `cyl(rt,rb,h,{bevel,seg})`, `roundRect(w,h,r)`, `extrude(shape|pts, depth,
{bevel,bevelSeg,curveSeg,round,uv})`, `tube(pts, r, {seg,radial,closed})`, `roundRectPath`, `leaf`, `leafCluster`,
`tint(geo, color|fn)`, `m(geo, mat, {pos,rot,scale,name,cast,receive})`; `tex` (wood, burl, shag, weave, pebble,
brushed, label, canvas); `bakeAO(group, opts)` (mismo algoritmo y números, vectorizado con numpy), `prop(id,
fields)`, `finish(game, group, {ao, merge, cast})`, `merge(group)`, `stats(group)`; `PAL`, `THREE`, `Game()`,
`getCard(id, opts)`, `cardInfo(id)`, `cardIds()`, `drawTo(ctx, id, w, h)` (necesita `dalib/cards/<id>.png`),
`document`.

**`dalib.scene`**: `Object3D`, `Group`, `Mesh`, `InstancedMesh`, `Line`, `Points`, `Material`, `box_from_object`,
`assign_names(root)`, `to_blender(root, names, texture_file)`, `jsonable(v)`.

**`dalib.tex`**: `tex.*` (kit.js), `plaid, stripes, colorBars, text, woodPanel, carpet, tiles, noise, gradient,
radial, poster, repeat, staticNoise` (textures.js; `staticNoise` es de Godot en tiempo de ejecución: la spec lleva
`"map": "staticNoise", "runtime": true`), `labelTex, stencilTex, hazardTex, boltSignTex, newspaperTex,
movingPadTex` (decals.js), `Texture`, `CardTexture`, `texture_file(tex)`, `shade(hex, amt)`.

**`dalib.canvas2d`**: `Canvas(w, h)` (`getContext('2d')`, `width/height`, `save_png(path)`,
`to_blender_image(name)`, `to_array()`), la API completa de `CanvasRenderingContext2D` con los nombres JS (rutas,
fill/stroke/clip con nonzero/evenodd, transformaciones, `globalAlpha`, todos los `globalCompositeOperation`,
sombras, `filter` (blur, brightness, contrast, saturate, sepia, grayscale, invert, opacity, hue-rotate,
drop-shadow), guiones, texto con fuentes CSS, `measureText`, gradientes lineales/radiales/cónicos, patrones,
`drawImage` (3 firmas), `getImageData/putImageData/createImageData`), `Path2D` (también con cadenas SVG),
`Image(path)`, `parse_color`, `parse_font`. Probado contra Chrome: mismas métricas de texto al píxel y
diferencias de antialiasing mínimas.

**`dalib.export`**: `build_props(ids, keys, …)`, `build_variant(v)`, `export_graph(root, path, root_name,
save_blend)` (para world/runtime/chars: grafo → escena nueva → GLB con texturas enlazadas), `export_glb(path)`,
`link_textures(glb)`, `reset_scene()`, `GLTF_SETTINGS`.

## Herramientas

* `python3 blender/tools/compare_ref.py <id|key> [-v] [--ref DIR] [--dump yo.json]` — construye el prop (sin
  Blender) y lo compara con el volcado del juego JS: bbox (±1 cm), triángulos (±10 %), número de mallas, userData
  (parts, screens, anchors, colliders, lightAnchors, interact…), materiales y cada malla por su ruta de nodo.
  `--all` resume todos los props registrados.
* `python3 blender/tools/compare_glb.py ref.glb nuestro.glb` — compara dos GLB vértice a vértice.
* `blender/tools/open_prop.py` — construye un prop en la escena abierta de Blender (pestaña *Scripting*).

## Otras secciones

`--only chars|world|runtime` importa `blender/<seccion>/build.py` y llama a
`build(ids=None|[...], save_blend=bool, godot=<ruta del proyecto Godot>)`. Esos módulos usan la misma librería:
`dalib.export.export_graph()` (o `scene.to_blender` + `export.export_glb` + `export.link_textures`) y
`dalib.tex.texture_file`.

## Proyecto Godot: primera apertura y exportación

* **Primera apertura.** `godot --path godot --headless --import` (o abrir `godot/project.godot` en el editor)
  importa todos los assets (~1 min; `.godot/` está ignorado por git). Los `.import` del repo que escriben los
  builders (`dalib/tex.py`, `chars/build.py`, `chars/patterns.py`, `runtime/telly.py`) son mínimos a propósito
  (PNG sin pérdida, sin LOD ni compresión de vértices en los personajes): Godot los completa con `uid`/`dest_files`
  al importar. Los GLB/PNG/OGG sin `.import` se importan con los valores por defecto. Godot 4.4+ crea además un
  `<script>.gd.uid` junto a cada script la primera vez que abre el editor.
* **Exportar.** `export_presets.cfg` está ignorado por git: se crea en *Proyecto → Exportar*. Con el filtro por
  defecto (*Exportar todos los recursos*) los `.json` que el juego lee con `FileAccess`
  (`assets/props/index.json`, `assets/textures/index.json`, `data/layout.json`, el índice de audio…) SÍ entran en
  el paquete: Godot 4 reconoce `.json` como recurso (comprobado con `--export-pack`). Aun así conviene poner en
  *Recursos → Filtros para exportar archivos no-recurso* `*.json, assets/chars/patterns/*.png`: el segundo
  patrón incluye los PNG originales de los patrones de personaje, que `char_material.gd` lee byte a byte (sin él
  cae al PNG importado, que puede alterar el RGB bajo alfa 0).
* **Salida limpia.** Al cerrar, `scripts/core/teardown.gd` (llamado desde `game.gd`) rompe los ciclos de
  referencias entre sistemas, vacía las cachés `static var` y libera los nodos fuera del árbol (pools), para que
  Godot salga rápido y sin avisos de fugas.
