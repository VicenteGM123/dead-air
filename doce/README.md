# DOCE · Los trabajos de Heracles

Acción y aventura en tercera persona en un mundo de islas griegas con el estilo de *Wind Waker*. Cada uno de los
doce trabajos de Heracles es una bestia con su propia regla: se pelea con peso, se viaja con una lanza con cadena y
a cada bestia hay que entenderla para vencerla. Este es el **primer tramo jugable: la isla de Nemea y el León**
(20–30 minutos).

**Jugar en el navegador:** <https://vicentegm123.github.io/dead-air/doce/web/>
(WebGL 2: Chrome, Edge, Firefox o Safari recientes; teclado y ratón o mando).

## El tramo

1. Llegas en barco al muelle de Nemea al atardecer. El pueblo, sus gatos (se pueden acariciar).
2. El camino del bosque: la primera manada de lobos.
3. El campo de trigo que baja hacia el mar y la puesta de sol. Entra en el trigo y camina: Heracles pasa la mano
   por las espigas.
4. El paso roto: las argollas de bronce y la lanza con cadena.
5. Los claros de los jabalíes y el Altar de la Sierra (rezar cura y guarda el punto de regreso).
6. La cueva del León tiene dos entradas. Arrastra la roca con la cadena para tapar la grieta... o no: huirá por ella
   y te atacará desde fuera.
7. El León: las espadas rebotan en su piel. Esquiva su salto para que choque contra una columna, o tíralo contra
   ella con la cadena; aturdido, agárralo (**E**) y lucha cuerpo a cuerpo.
8. Vístete con su piel y vuelve al barco: «II · La Hidra de Lerna», próximamente.

## Controles

| Acción | Teclado y ratón | Mando |
|---|---|---|
| Moverse | W A S D o flechas | stick izquierdo (inclinado a medias: caminar) o cruceta |
| Cámara | ratón (clic en el juego para capturarlo; Esc lo suelta) | stick derecho |
| Esprintar | mantener Shift | mantener B o pulsar L3 |
| Voltereta (esquivar) | pulsar Shift | pulsar B |
| Saltar | Espacio | A |
| Golpe (combo de 3) | clic izquierdo | X |
| Golpe fuerte | mantener clic izquierdo | mantener X |
| Escudo / parada | clic derecho (mantener / justo antes del golpe) | LT |
| Lanza con cadena | Q (apunta a lo que miras) | RT |
| Fijar objetivo | Tab o clic central | R3 |
| Usar, agarrar, acariciar, rezar | E | Y |
| Pausa | Esc o P | Start |

Pistas: los lobos atacan de uno en uno mientras los demás rodean (voltereta o escudo, y castiga); los jabalíes avisan
antes de embestir en línea recta (ponte delante de una roca o para el golpe con el escudo en el momento justo).

## Ejecutarlo en local

Hace falta **Godot 4.7.2** (versión estándar, no .NET).

```sh
godot --path doce/game              # el juego, desde el menú de título
godot --path doce/game -- play=1    # directo a jugar
```

También se puede abrir `doce/game/project.godot` en el editor y pulsar F5.

**Versión web en local** (necesita las plantillas de exportación web de Godot 4.7.2):

```sh
STRICT=1 sh doce/tools/export_web.sh               # exporta a doce/web
cd doce/web && python3 -m http.server 8000         # y abrir http://localhost:8000/
```

La build web es de un solo hilo: sirve cualquier servidor estático, sin cabeceras COOP/COEP. Pesa 44,3 MB (15,4 MB con gzip, que es lo que se descarga): 37,7 MB el motor (`index.wasm`) y 6,1 MB el juego (`index.pck`, casi todo audio Ogg).
Prueba automática en Chromium (título, flujo y partida, con WebGL 2):
`cd doce/tools && npm install && node web_test.mjs <carpeta_informe> --dir ../web`.

## Pruebas automáticas

Bots que juegan con los controles reales del héroe (detalles en `docs/ARCHITECTURE.md`, sección 9):

```sh
cd doce/game
godot --headless --path . res://tools/playthrough.tscn --fixed-fps 60 --quit-after 300000 -- ptbot=1 quit=1   # el tramo entero
godot --headless --path . res://tools/arena.tscn --fixed-fps 60 --quit-after 12000 -- autotest=1 quit=1      # combate
godot --headless --path . res://tools/encounters.tscn --fixed-fps 60 --quit-after 500000 -- encbot=all quit=1 # lobos y jabalíes
godot --headless --path . --fixed-fps 60 --quit-after 80000 -- play=1 lionbot=units quit=1                    # el León
godot --headless --path . res://tools/wheat_walk.tscn --fixed-fps 60 --quit-after 4000 -- enemies=0          # la mano en el trigo
```

## Documentación

- `docs/GDD.md`: el diseño (qué es el juego y el tramo).
- `docs/ARCHITECTURE.md`: cómo está hecho (escena, contratos, mundo, hierba y trigo, depuración, pruebas).
- `docs/COMBAT.md`: el combate, la lanza con cadena y la cámara. `docs/ENCOUNTERS.md`: lobos, jabalíes y el León.
- `docs/AUDIO.md`: los sonidos.

## Tecnología

Godot 4.7, GDScript y el renderer Compatibility (WebGL 2 en la web). Todo se genera por código: los modelos, la
animación, la isla y el sonido (`doce/tools/audio`). Tipografías Cinzel y EB Garamond (licencia SIL OFL).
