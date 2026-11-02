# Secondhand Stars

**Un juego chico y completo:** una tienda de chatarra y reparaciones en un puerto espacial del desierto, en 2.5D (estilo HD-2D, como Midnight Cauldron) hecho en Godot 4.7. Una temporada de 10 días con un final, y después se puede seguir jugando sin fin. El juego está en inglés; esta documentación, en español.

Se juega en el navegador: https://vicentegm123.github.io/dead-air/secondhand/web/

Cada noche, pedazos de un viejo astillero en órbita (**the High Yards**, abandonado después de una guerra larga y aburrida por impuestos) caen sobre el planeta desierto **Saffra** como estrellas fugaces (la *starfall*). Al amanecer, los chatarreros los venden en el mercado. **Nell**, una mecánica joven, compra la chatarra, la arregla en su banco y la vende de segunda mano a los alienígenas y robots del puerto de **Rustwater**, en su tienda **The Secondhand Star** (un cartel con forma de estrella, remendado). La acompaña **Kettle**, un robot con forma de tetera de cobre que silba vapor cuando Nell acierta. De noche salen las dos lunas, **Copper** y **Tin**.

Esta temporada, el **Fixers' Guild** publica cada noche **the Lantern Board**: las 30 mejores tiendas de segunda mano del **Amber Drift**, una cadena de mundos de frontera. Nell empieza en el puesto 30. Al lado abre una rival con brillo de sobra.

## La meta: 10 días, tres cuotas y el Brass Comet

- **La temporada (the Starfall Season) dura 10 días de juego**, unos 75-90 minutos. Cada día tiene su nombre y casi todos traen algo nuevo (ver «Los días»).
- **Las cuotas del muelle** las cobra **Dockmaster Hesk** en tres partes: **100** créditos la noche 3, **200** la noche 6 y **300** la noche 9. La barra **DUES** de arriba muestra la próxima. Si no alcanza, nunca es el fin: Hesk se lleva todo menos 15 créditos (para la cápsula de mañana), lo que falta pasa a la cuota siguiente con un 10 % de recargo y aparece un sello **LATE** en el tablero (−3 estrellas, una vez). Si se pagan las tres a tiempo, una placa **PAID IN FULL** queda junto a la puerta.
- **El Lantern Board**: cada noche el tablero dice en qué puesto está la tienda. La meta es llegar al **#1** la última noche.
- **La noche 10 es la noche del Brass Comet**, una fiesta en la calle bajo las dos lunas. Si Nell terminó **#1**, el elenco entero sale a la calle, le atornillan al cartel de la estrella una cola de cometa de bronce (la estrella remendada se vuelve estrella fugaz) y se encienden las siete lámparas del anillo del cielo (si Nell juntó los tres núcleos de lámpara de Old Seven). Si no llegó, recibe un premio según el puesto (*Rising Lantern of the Drift*, *Rookie of the Season* o *Best New Shop in Rustwater*). Las dos versiones terminan con el resumen de la temporada, los créditos y dos botones: **Keep trading** y **Title**.
- **Keep trading** (sin fin): días 11, 12… con un día especial cada 2-3 días, un alquiler de **250** créditos cada tres noches (12, 15, 18…) y el tablero que sigue. Si Nell no fue #1 en la noche 10, la versión campeona de la fiesta se juega una vez, la primera noche que llegue a #1.

Un jugador ordenado que juega por primera vez llega al #1 la última noche la mayoría de las veces (los jugadores automáticos «humanos» lo logran en 3 de cada 4 partidas; si no, quedan #2 y la corona llega en el modo sin fin). Uno apurado termina cerca del puesto 13, con el premio al novato del año.

Las partidas del prototipo de 3 días siguen: **Continue** las carga con una nota corta («New: a 10-day season, the Lantern Board and fittings…»).

## Cómo se juega

- **Mañana (sin reloj): el Starfall Market**, la calle frente a la tienda.
  - **Raker's pods**: cápsulas de chatarra cerradas, con regateo. Solo se sabe el peso (las pesadas traen más piezas) y si traquetean (algo roto adentro). Con la reputación *Known in Rustwater* hay una tercera cápsula. Si Nell se queda sin créditos, sin piezas y sin nada para arreglar, el Raker regala una («On the house. Pay me back in stories.»).
  - **Mags's parts**: piezas a precio fijo; el surtido cambia cada día. Desde el día 3, el cajón de **as-is** (cosas rotas baratas para arreglar y vender).
  - **Dolly's Fittings** (desde el día 2): **Dolly**, un viejo robot de carga con mástil de montacargas, vende las mejoras de la tienda.
  - **El tablón** junto a la puerta de Nell: **Read** abre el calendario de la temporada (qué trae cada día y las noches de cuota).
  - **Shine Again**, la tienda de al lado (desde el día 3): **Visit** para ver qué dice Madame Glint.
  - A veces alguien se acerca a hablar: son los momentos de historia (ver «Las historias»).
  - La puerta: **Open shop**. Las mejoras compradas esa mañana se estrenan al abrir (la cámara va hasta ellas).
- **Día (5 minutos reales, de 9 AM a 6 PM):** como en el prototipo, la fila dentro de la tienda (hasta 4, cada uno con su reloj de arena de paciencia), el **mostrador** (**Repair it** o vender del estante regateando), el **banco**, el **té** de Kettle y **Refurbish** con la tienda vacía. Novedades:
  - **Close up early**: después de las 4 PM, si no queda nadie ni nadie por llegar, en el mostrador se puede cerrar antes.
  - **R** (o **Y** en el mando, o un clic en la placa **★ #14** de arriba) abre el tablero entero; el reloj se para mientras tanto.
- **Después de cerrar (After hours):** si quedó algo roto de las cápsulas, Nell puede arreglar hasta **2** cosas para el estante, sin reloj y sin fila, bajo las lunas (3 la noche antes de Bronzemoon). **Sleep** para dejarlo.
- **Noche:** el libro de cuentas (**ledger**: reparaciones, ventas, lo de después de cerrar, el tablero, la cuota de esta noche o la próxima, lo que trae mañana), después la cuota si toca, **el tablero de la noche** y, las noches 3, 6 y 9, **the Lantern Report**.

### El Lantern Board (el ranking galáctico)

30 tiendas de diez mundos del Amber Drift, del #1 al #30, cada una con su escudo, su dueño y una línea de humor (*Honest Holt's: Not honest. Possibly not Holt.*). Cada noche:

- **Las estrellas del día** de Nell: +1 por cada cliente atendido (reparación entregada o venta), más las estrellas del banco de cada reparación y las de cada cosa vendida, más las de los días especiales (el certificado de la inspección, la carrera, la banda…), +3 por un día limpio (nadie se fue enojado ni se perdió nada), +1 por cada mejora instalada (+2 el Neon Star), menos los que se fueron de la fila y los arreglos fallidos. El tablero muestra el desglose bajo la fila de Nell.
- **El tablero de la noche**: arriba los tres primeros, abajo una ventana de 9 filas alrededor de Nell; las filas se reordenan como un tablero de salidas de aeropuerto (**split-flap**), con el sonido de las paletas. Debajo: a quién pasó, cuánto falta para el siguiente y qué trae mañana.
- **Rosa Reverb**, la locutora del **Drift Signal** (la radio), dice una línea sobre Nell cada noche («The Secondhand Star, Rustwater: up 3, to twenty-first!»).
- **The Lantern Report** (noches 3, 6 y 9; en el modo sin fin, cada tres noches): una tira de papel que imprime la radio con 7 líneas: quién va primero, la carrera de Rustwater, una noticia, un escándalo, un aviso clasificado, el tiempo de mañana y la despedida («Keep your lights on, Drift.»). Nell anota a lápiz un «us!» junto a su línea.
- **La rival, Madame Glint** (y su robot Buff), abre **Shine Again** al lado el día 3: «We don't fix it. We make it sparkle.» Copia lo que hace Nell, así que siempre anda cerca; tiene sus golpes (un globo de cromo el día 8) y la carrera de las dos tiendas de Rustwater se cuenta en el Report.
- **El campeón, The Gilded Gear**, lidera toda la temporada… hasta que la noche 7 sale un escándalo.
- **El cartel de la estrella** enciende una punta por cada hito: top 20, top 15, top 10, top 5 y #1.

### Dolly y las mejoras (fittings)

Precio fijo (sin regateo). Cada fila del diálogo dice cuánto queda y cuándo es la próxima cuota («Leaves 85 cr · Dues 200 on night 6»), para decidir. Cada mejora se ve en la tienda y suma una estrella por día al tablero.

| Mejora | Precio | Desde | Qué hace |
|---|---|---|---|
| **Kettle's Samovar** | 30 | día 2 | té dos veces por día, y cada té calma un poco más la fila |
| **Liner Seats** | 35 | día 2 | asientos de una nave de pasajeros: la paciencia de la fila baja más lento |
| **Pod Lamp** | 50 | día 2 | en el puesto del Raker, cada cápsula muestra una cosa de adentro |
| **Cool Coil** | 45 | día 3 | banco fresco, pulso firme: +2 segundos para soldar y la aguja de la prueba más lenta (y un toldo en la puerta) |
| **Display Case** | 70 | día 3 (reputación 15) | vitrina: precios del estante +10 % y un comprador más cuando hay 3 o más cosas a la venta |
| **Parts Wall** | 55 | día 4 | una pieza gratis cada mañana, para un trabajo de ese día |
| **Loupe Lamp** | 75 | día 4 (reputación 15) | lupa: puntos de soldadura más grandes y zona verde más ancha |
| **Neon Star** | 85 | día 5 (reputación 35) | «FIXED HERE ★» en la ventana: un cliente más los días tranquilos y +10 % en las reparaciones |

La **reputación** también abre cosas: *Known in Rustwater* (15: una tercera cápsula, Madam Sift, dos mejoras), *Trusted* (35: dos cosas en el cajón as-is, Warden Brisk, el Neon Star), *Port Favourite* (60: reparaciones +10 %) y *Legend of the Drift* (90: +1 estrella por día).

### Los días

| Día | Nombre | Qué pasa |
|---|---|---|
| 1 | **Opening Day** | Tutorial tranquilo, como en el prototipo. El primer tablero de la noche |
| 2 | **Fittings for Sale** | Abre Dolly. Rook pide guardar una caja sellada que zumba |
| 3 | **New Neighbours** | Abre Shine Again al lado y el cajón as-is de Mags. Cuota de 100. Primer Report |
| 4 | **Music Across the Street** | Llega una familia nueva al banco, la **caja de música** (*Song box*) de Lune; Old Seven trae una radio con un acertijo |
| 5 | **The Scour** | Tormenta de arena: el puesto del Raker cierra, Mags rebaja las piezas, los clientes tienen más paciencia. Glint pide un favor en secreto |
| 6 | **Inspection Day** | La **inspectora Tolle** de la Tally Office trae una radio y califica el arreglo con un sello (Approved: certificado en la pared, +30 cr). Cuota de 200 |
| 7 | **Bigfall** | Cae un pedazo grande: la segunda familia nueva, la **brújula estelar** (*Star compass*); el Raker vende la cápsula del naufragio |
| 8 | **Bronzemoon** | Las dos lunas llenas y fiesta: 60 % de compradores, precios de venta ×1.2 y, si se ganó, la banda **the Low Moons** toca en la puerta (más paciencia y +4 estrellas). Mejor llegar con el estante lleno |
| 9 | **The Glasspan Derby** | Carrera de hoverbikes: 4 corredores traen propulsores a primera hora y los necesitan antes de las **2:30 PM**; con 3 o más bien arreglados, podio (+10 estrellas, +50 cr y una copa). Cuota de 300 |
| 10 | **The Great Starfall** | El final: vienen los 9 clientes conocidos, una vez cada uno, con buen humor; **cada estrella cuenta doble**. Esa noche no hay tablero: la cuenta regresiva de la fiesta es la revelación |

### Las historias

Momentos cortos de dos líneas, a veces con una decisión (con dos opciones, `Esc` no la cierra: hay que elegir):

- **La caja de Rook**: guardarla o no. Si Tolle la ve el día de la inspección, se puede decir que es el banquito de Kettle o declararla. Si llega entera al día 8, Rook revela qué es y la banda toca en la puerta (también toca si la caja de música de Lune salió bien el día 4); después de la carrera Rook deja su llave de la suerte en el estante de trofeos.
- **Los núcleos de lámpara de Old Seven**, un robot farero viejo y callado: uno por su radio del día 4, otro en la cápsula del naufragio del día 7, otro por su brújula del día 8 (si el arreglo sale bien). Con los tres, en la fiesta final se encienden las siete lámparas del anillo.
- **El favor de Glint**: arreglarle a escondidas el cepillo a Buff (o no). Cambia lo que dice en la fiesta.
- **Clatter**, el robot viejo del prototipo, se queda sin ahorros y pide trabajo (si se lo arregló varias veces).

Los epílogos de la fiesta dependen de lo que se eligió.

### Los clientes nuevos y sus señas

- **Lune** (una Lampwing, cantante del bar **the Slow Orbit**, del otro lado de la calle): trae la caja de música; cuando un precio le encanta, le tiemblan las alas. Con un arreglo de 3 estrellas tararea y toda la fila se calma. Desde el día 5 es clienta fija.
- **Madam Sift** (una Sandglass, un reloj de arena con modales): su arena es su paciencia; cuando miente con el precio, la arena deja de caer. La primera vez que se le acaba la paciencia, se da vuelta sola y le queda la mitad.
- **Warden Brisk** (una Brushtail, orejas de zorro, abrigo con bolso): siempre apurada; cerca de su límite baja las orejas. Si se le arregla en menos de 40 segundos, paga +30 %.
- **Inspector Marigold Tolle** (Tally Office, sombrero pastillero mostaza): el trabajo calificado del día 6.
- **Old Seven**: el farero de las lámparas del anillo, con sus acertijos en vez de síntomas.
- **Madame Glint**: la vecina rival (abrigo rosa durazno, «sweetie»).
- **Dolly**: la vendedora de mejoras.
- **Dockmaster Hesk**: cobra las cuotas («Fine. Now go make that lantern shine.»).

### El banco de reparación (20-40 segundos por arreglo)

Los mismos 4 pasos del prototipo (**Diagnose** con Listen / Tap / Scan, **Swap** o parche, **Solder**, **Test** con la aguja) y ahora **5 familias**: la radio (se escucha), el robot de bolsillo (se golpea), el propulsor de hoverbike (se escanea), la **caja de música** (*Song box*: se golpea, `Tap`) y la **brújula estelar** (*Star compass*: se escucha, `Listen`), con 4 piezas nuevas (tambor, ranura de monedas, giroscopio y aguja). Hay arreglos especiales: el **calificado** de Tolle (un sello rojo GRADED), los **acertijos** de Old Seven (la nota es un acertijo en vez del síntoma) y el favor secreto de Glint.

### Regatear

Igual que en el prototipo (**LOW / FAIR / FIRM** o **Accept**, la barra de ánimo y la seña de cada especie), con las señas nuevas de Lune, Madam Sift y Warden Brisk.

## Controles

| Teclado y ratón | Qué hace |
|---|---|
| `A` / `D` o flechas, o clic en el suelo | caminar |
| Clic en un lugar (puesto, mostrador, banco, cajón, estante, té, puerta, tablón, Dolly, Shine Again) | Nell camina hasta allí y lo usa |
| `E`, `Intro` o `Espacio` | usar el lugar donde está Nell (el aviso dice qué hace: «[E] Repair», «[E] Fittings», «[E] Read»…) |
| `R` o clic en la placa del puesto (★ #14) | **el tablero entero** (en la mañana y en el día; flechas o la rueda para elegir una tienda, `Esc` o `R` para cerrar) |
| `Esc` | menú (volumen, el calendario, volver al título); cierra o cancela la ventana abierta |
| Diálogos | `E` / `Intro` la opción principal, `1`-`9` las demás, `Esc` cancelar (no en una decisión de historia) |
| Dolly | `1`-`8` compran la mejora de esa fila |
| Puesto de Mags | `1`-`8` las piezas, `9` / `0` / `-` / `=` las cosas del cajón as-is |
| Regateo | `1` / `2` / `3` contraofertas LOW / FAIR / FIRM, `Intro` aceptar, `Esc` irse |
| Cápsula | `E` o `Espacio` abrirla y guardar lo que trae |
| Banco | `L` / `T` / `S` Listen / Tap / Scan, `1`-`4` elegir la pieza, `E` cambiar, `P` parchar, flechas o `WASD` (o el ratón) para soldar, `Espacio` o clic para parar la aguja, `Intro` terminar |
| Tablero de la noche, Report | `E` / `Intro` seguir, `Esc` saltar la animación |
| Noche del Brass Comet | `E` siguiente, `Esc` saltar a la tarjeta del premio; al final `←` / `→` y `E` para **Keep trading** o **Title** |
| Título | `E` / `Intro` la opción principal, `N` partida nueva, `S` ajustes |

| Mando (Xbox y compatibles) | Qué hace |
|---|---|
| Stick izquierdo o cruceta | caminar (con una ventana abierta, mueven el cursor del mando) |
| `A` | interactuar (como `E`); en una ventana, tocar donde está el cursor o avanzar |
| `B` | volver / cerrar (como `Esc`) |
| `X` | como `Espacio` (p. ej. parar la aguja del banco) |
| `Y` | el tablero entero (como `R`) |
| `LB` / `RB` | mostrar el cursor y saltar a lo tocable anterior / siguiente que se ve en pantalla (lugares, botones, piezas, filas del tablero) |
| `Menu` | menú |

Los avisos cambian solos según el aparato: con el mando dicen «[A] Repair». En el navegador el sonido empieza con el primer clic o tecla (los navegadores no cuentan el mando); la esquina de la pantalla lo avisa.

La partida se guarda sola cada mañana y al abrir la tienda: **Continue** sigue desde ahí (en el navegador se guarda en el propio navegador).

## Qué tiene y qué no tiene todavía

**Tiene:** la temporada de 10 días con su final en dos versiones y el modo sin fin; el Lantern Board con 30 tiendas, la rival, el campeón, la radio, el tablero de cada noche y el Report; las cuotas en tres partes con la regla blanda; las 8 mejoras de Dolly, visibles en la tienda; la reputación con lo que abre; 6 días especiales con su decorado, su música o su viento; 5 familias en el banco y 13 piezas; 7 personajes nuevos con sus señas; 3 hilos de historia con decisiones; el arreglo de después de cerrar; la tienda nueva (más vivida: chatarra delante, tablero de herramientas, un rayo de sol con polvo, la ventana con las lunas de noche) y la calle nueva (Shine Again, el patio de Dolly, el tablero de salidas, el bar the Slow Orbit, la banda, las dos lunas y el anillo con sus lámparas); música y sonidos nuevos; teclado, ratón y mando; las partidas del prototipo siguen.

**Todavía no:**

- Lo que quedó para otra ronda: el tablón de encargos (notas con trabajos), la racha de manos calientes, la música propia del día de la carrera (suena la de la tienda), algunos detalles de la calle (cangrejos de lata, pájaros del polvo, la nave de Glint, Buff puliendo la vidriera) y el sonido de las ruedas de Dolly.
- Barb y Barrow (una Thornfolk y un robot carretilla) están dibujados y tienen sus datos, pero todavía no entran a la tienda.
- La primera vez que se ve la tienda o la calle de noche, el navegador todavía prepara un efecto de luz (un tirón corto, una sola vez, como en el prototipo).
- El balance se midió con jugadores automáticos (perfecto, bueno, «humano» y apurado; 12 temporadas enteras) y con un simulador del tablero (500 temporadas por perfil); falta probarlo con más personas.
- Pensado para computador (1280x720 o más); no está adaptado a pantallas táctiles.

## Abrirlo en Godot

1. Instala **Godot 4.7** (versión estándar, no .NET).
2. Godot → **Importar** → `game/project.godot`. La primera vez tarda unos segundos en importar las imágenes. **F5** para jugar.

Usa el renderizador **Compatibility** (OpenGL / WebGL 2), el mismo de la versión web.

**Pruebas sin ventana** (desde `game/`, `godot --headless --path . -- <prueba>`):

- `--demo=smoke` arranca y recorre las pantallas (también Dolly, la cuota, el tablero, el Report y la fiesta).
- `--demo=savetest` guarda y carga (y carga las partidas del prototipo); revisa además que ningún texto use palabras prohibidas de la lista de propiedad intelectual.
- `--demo=benchtest` las 5 familias del banco con todas sus fallas.
- `--demo=ranktest`, `--demo=rankui` y `--demo=galatest`: el tablero, sus pantallas y la fiesta.
- `--demo=autoplay --days=10 --endless=2 --bot=good --seed=11`: un jugador automático juega la temporada entera por el flujo real (mañanas, día, después de cerrar, noches, la fiesta, 2 días del modo sin fin y vuelta al título) y termina con `errors=0`. Perfiles: `perfect`, `good`, `human` (el ritmo de una persona que juega por primera vez) y `sloppy`. `--from=8` empieza en una mañana típica del día 8; `--timescale=6` lo acelera.
- `--demo=ranksim --sims=500 --profile=human`: el simulador del tablero (en qué noche se llega al top 20, al top 10, al #1, y la probabilidad de ser #1 la noche 10).

## Versión web (exportar)

```
GODOT=/ruta/a/godot sh secondhand/tools/export_web.sh
```

Sin argumentos usa `secondhand/game` y deja el resultado en `secondhand/web` (también acepta `export_web.sh <proyecto> <salida>`). Necesita Godot 4.7 con las plantillas de exportación web. Usa el preset «Web» (Compatibility / WebGL 2, sin hilos: funciona en GitHub Pages), arregla el audio web de Godot 4.7 en `index.js` (los bucles de música y ambiente se repiten sin cortes aunque el juego vaya lento), pone «Secondhand Stars» como título de la pestaña y no exporta si algún script usa `AudioServer.add_bus()`, que en la web deja el juego mudo. La página usa solo rutas relativas: funciona en `…/dead-air/secondhand/web/`. El juego (`index.pck`) pesa unos 8 MB.

**El arranque.** Mientras baja el juego, la página muestra su imagen de arranque con una barra; después el juego arma todo de a un paso por cuadro bajo la pantalla de carga (`game/scripts/main.gd`, `_boot` y `_boot_background`): la calle (con lo nuevo: Shine Again, el patio de Dolly, el decorado de los días especiales, las lunas, la fiesta), la tienda de día y de noche con todas las mejoras y los objetos de historia escondidos, el banco, el regateo, la cápsula, el tablero y la fiesta del Brass Comet, y calienta sus shaders. Cuando aparece el título ya está todo listo, y ni las mejoras, ni los días especiales, ni el tablero compilan nada nuevo durante el juego. Las músicas nuevas largas (la tormenta, la fiesta de Bronzemoon, la del Brass Comet, la de la noche) se decodifican la noche anterior, debajo del libro de cuentas. Para medir: `--bootlog` escribe una línea por paso en la consola.

## Dónde cambiar cosas

| Quiero cambiar… | Archivo (en `game/`) |
|---|---|
| **La temporada**: los 10 días (nombre, quién viene, cuántos compradores, cápsulas, invitados), los días especiales y sus efectos, las cuotas y el alquiler del modo sin fin, la regla blanda, las mejoras (precio, día, efecto), la reputación y lo que abre, los momentos de historia y sus decisiones, la carrera, la inspección, textos de Kettle, Hesk, Dolly y Glint | `scripts/season_data.gd` (`PLAN`, `EVENTS`, `DUES`, `UPKEEP`, `SOFT_RULE`, `FITTINGS`, `REP_TIERS`, `UNLOCKS`, `BEATS`, `RACE`, `GRADES`, `HESK`, `DOLLY`, `TEXT`) |
| Cómo funciona la temporada (los horarios generados, los efectos de las mejoras y los días, cobrar las cuotas, el surtido de Mags y el cajón as-is, las cápsulas especiales, las historias, el modo sin fin) | `scripts/season.gd` |
| **El Lantern Board**: las 30 tiendas y los 10 mundos, la rival y el campeón, la fórmula de las estrellas, los hitos del cartel, las líneas de Rosa, el Report y sus noticias, los premios, lo que dicen los clientes del puesto | `scripts/ranking.gd` (`SHOPS`, `WORLDS`, `SCALE`, `RIVAL_SCRIPT`, `CHAMPION_PACE`, `MILESTONES`, `ROSA`, `POOL_*` y `report()`, `AWARDS`, `RANK_CHATTER`) |
| Las pantallas del tablero (el de la noche con las paletas, el tablero entero, la tira del Report) | `scripts/ui/rank_screens.gd` |
| La noche del Brass Comet (los pasos, quién habla, la tarjeta del premio, los créditos) | `scripts/world/gala_scene.gd` |
| Los personajes nuevos (nombre, especie, qué traen y compran, paciencia, sus frases, sus señas al regatear, los acertijos) | `scripts/cast_data.gd` |
| La cuota del prototipo, la hora de apertura y cierre, el largo del día, lo del comienzo | `scripts/data.gd` (`OPEN_MIN`, `CLOSE_MIN`, `DAY_SECONDS`, `START_CREDITS`, `START_PARTS`, `START_SHELF`) |
| Los días 1-3 (quién llega, a qué hora), los personajes del prototipo y lo que dicen, la introducción, los consejos | `scripts/data.gd` (`SCHEDULE`, `CAST`, `LINES`, `INTRO`, `TIPS`) |
| Objetos, piezas, fallas y síntomas (las 5 familias), pago de las reparaciones, regateo por especie, cápsulas | `scripts/bench_data.gd` (`ITEMS`, `PARTS`, `FAULTS`, `SYMPTOM_LINES`, `TOOL_CLUES`, `HAGGLE`, `POD_*`) |
| El estado de la partida, guardar y cargar (y cargar las del prototipo) | `scripts/game.gd` |
| El flujo: título, mañana, abrir, el estreno de las mejoras, mostrador, banco, después de cerrar, noche, la cuota, el tablero, la fiesta | `scripts/main.gd` |
| La fila, la paciencia y los clientes que entran y salen | `scripts/shop_day.gd` |
| La tienda en 3D (lugares, luces, ventana y su cielo, mejoras, objetos de historia, decorado de los días especiales) | `scripts/world/shop_world.gd` |
| La calle (puestos, Shine Again, el patio de Dolly, el tablón, el tablero de salidas, el bar, la banda, las lunas, el anillo, el cometa, el decorado de los días especiales) | `scripts/world/street_world.gd` |
| Piezas comunes de los escenarios, caminar, los personajes | `scripts/world/set_kit.gd`, `scripts/world/walker.gd`, `scripts/world/actor.gd` |
| El banco (pantalla y pasos) | `scripts/ui/bench_ui.gd` y sus ayudantes `scripts/ui/bench_*.gd` |
| El regateo / la cápsula | `scripts/ui/haggle_ui.gd` / `scripts/ui/pod_ui.gd` |
| El HUD (el día, la cuota, la placa del puesto), los avisos «[E] …», los mensajes | `scripts/ui/hud.gd`, `scripts/ui/ui_kit.gd` |
| Diálogos: mostrador, Mags, Dolly, el calendario, la cuota, los momentos de historia, después de cerrar, menú | `scripts/ui/dialogs.gd` |
| Título, introducción, libro de cuentas | `scripts/ui/screens.gd` |
| Mando | `scripts/ui/pad_cursor.gd` |
| Música y sonidos (qué suena dónde, volumen, cuándo se decodifica cada música larga en la web) | `scripts/sfx.gd` |
| El jugador automático y sus perfiles | `scripts/demo_kit.gd` (`PROFILES`) |
| El efecto de maqueta (desenfoque arriba y abajo), viñeta y color (también el tinte de cada día especial) | `shaders/hd2d_post.gdshader`, `POST_*` en `scripts/main.gd` y `EVENT_POST` en `scripts/world/street_world.gd` |

Todo el arte está en `game/assets/` y el audio en `game/audio/`. Se puede reemplazar cualquier PNG por otro con el mismo nombre y tamaño (los personajes: cuadros de 64x96, mirando a la derecha). Los nombres propios (Shine Again, THE SLOW ORBIT, FITTINGS, TALLY OFFICE…) nunca están dibujados en las imágenes: son texto, así que cambiar un nombre no pide arte nuevo.

## Generadores de arte y audio

En `game/tools/arte/` están los scripts de Python que hicieron todo el pixel art, las texturas, el logo, la música y los sonidos (Godot no los exporta). Necesitan `pillow`, `numpy`, `scipy` y, para el audio, `ffmpeg`.

- **Arte:** `python3 ss_build_all.py --out <carpeta> [--game ../..]` regenera todo y, con `--game`, lo copia al proyecto con las rutas que usa el juego. Por partes: `ss_chars.py` y `ss_bots.py` (el elenco del prototipo, Kettle, Clatter y la tortuga), **`ss_cast2.py`** (los personajes nuevos: Glint, Dolly, Tolle, Old Seven, Lune, Sift, Brisk, Hesk, Buff, Thunk, Barb, Barrow), `ss_items.py` (objetos, piezas, cápsulas, la vista abierta del banco de las 5 familias), `ss_world.py`, `ss_props.py` y **`ss_props2.py`** (texturas y props de la tienda y la calle; lo nuevo: la chatarra delante, las mejoras, los objetos de historia, Shine Again, el patio de Dolly, las lunas, el anillo, el decorado de los días especiales), `ss_ui.py` (placas, pantallas, etiquetas, iconos), **`ss_rank_art.py`** (el marco de bronce del tablero, las paletas, las linternas, los 30 escudos, la tira del Report, el retrato de Rosa, los sellos, la tarjeta del cometa, los íconos de los días), `ss_logo.py` (el logo), `ss_emotes.py` (emociones). Después de cambiar imágenes: `godot --headless --path game --import`.
- **Audio:** `python3 make_audio.py ../../audio --set=all` genera los 33 `.ogg` (6 músicas, 3 ambientes, 24 efectos) con síntesis propia (`ss_audio.py`; `music_audio.py`, `amb_audio.py`, `sfx_audio.py`). Lo nuevo: «The Brass Comet» (la fiesta, termina con el silbido de Kettle), «Moon Blues» (la banda de Bronzemoon, blues del desierto en 6/8 con serrucho), «Copper & Tin» (la noche), el viento de la tormenta, y los efectos del tablero (paletas, la radio, la tira de papel, el sello, subir y bajar). Las músicas y ambientes son bucles sin costura. `levels.py` y `mixcheck.py` miden niveles y mezcla; `game/tools/audio_check.gd` comprueba en Godot que todo carga y hace bucle.

## Fuentes y licencias

- **Inter** (textos de la interfaz), de The Inter Project Authors: SIL Open Font License 1.1 (`game/assets/fonts/OFL-Inter.txt`).
- **Caveat** (la letra a mano de notas y etiquetas), de The Caveat Project Authors: SIL Open Font License 1.1 (`OFL-Caveat.txt`).
- **Secondhand Mono** (las pantallas ámbar): un subconjunto de Liberation Mono Bold, renombrado como pide la licencia: SIL Open Font License 1.1 (`OFL-SecondhandMono.txt`).
- **Secondhand Symbols** (★ ✓ ← → …): un subconjunto de DejaVu Sans Bold, licencia Bitstream Vera / DejaVu (`LICENSE-SecondhandSymbols.txt`).
- Solo para dibujar el logo (no van en el juego): **Saira Stencil One** y **Bungee**, SIL Open Font License 1.1 (`game/tools/arte/fonts/`).
- Pixel art, texturas, logo, música y efectos de sonido: originales, generados por código para este proyecto. Todos los nombres, lugares y diseños nuevos se revisaron para que sean propios (sin nombres ni parecidos de franquicias conocidas). El kit de personajes, el efecto HD-2D, el mando y el audio web vienen de Midnight Cauldron, del mismo estudio.
