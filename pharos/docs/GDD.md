# PHAROS — La última luz · Documento de diseño (GDD)

> **Estado:** v1.0 del GDD · el MVP (Delos) está en desarrollo en Godot 4.7 (GDScript, todo procedural, renderer
> Compatibility para web).
> **Documentos relacionados:** `BRIEF.md` (resumen para el equipo) · `PROPUESTAS.md` (otros juegos posibles con las
> ideas del cliente).
> **Sobre los números:** todas las cifras de este documento (vida, daño, costos, tiempos) son **valores de referencia
> orientativos**. Sirven para empezar a construir y se ajustarán con pruebas de juego. Si el código y este documento
> no coinciden, manda lo que se sienta mejor al jugar; después se actualiza el documento.

## Índice

1. [Visión](#1-visión)
2. [Bucles de juego](#2-bucles-de-juego)
3. [Sistemas](#3-sistemas)
4. [Campaña: La Odisea de la Luz (~8 h)](#4-campaña-la-odisea-de-la-luz-8-h)
5. [Meta-progresión y rejugabilidad](#5-meta-progresión-y-rejugabilidad)
6. [Narrativa y tono](#6-narrativa-y-tono)
7. [Biblia de arte](#7-biblia-de-arte)
8. [Audio](#8-audio)
9. [Alcance del MVP actual](#9-alcance-del-mvp-actual)
10. [Producción](#10-producción)

---

## 1. Visión

### 1.1 Elevator pitch

**Un *tower defense* de acción en dioramas griegos.** Eres Fanós, un autómata de bronce con un farol por cabeza. De día
levantas una aldea alrededor de un faro; de noche las criaturas de Nyx salen del mar y tú peleas en primera línea, con
un ancla y una lente de faro, junto a tus torres y tus hoplitas. Isla tras isla, llevas la última llama del mundo
(dentro de tu propia cabeza) a través del Egeo para volver a encender el sol.

### 1.2 Fantasía del jugador

- **Ser la luz.** Eres Fanós, el autómata del faro: Hefesto te forjó y Hestia te dio su última chispa. Lo que se pierde
  de noche se pierde donde no estabas. Tu farol es la torre más importante.
- **Ver crecer tu hogar.** Cada amanecer la aldea es un poco más grande, más blanca, más viva: casas encaladas, olivos,
  barcas, gatos al sol.
- **Ser elegido por los dioses.** Cada amanecer un dios del Olimpo te ofrece un don. Al final de una isla, tu partida
  se siente única.
- **Navegar un mar mítico.** Entre islas, el mar abierto: delfines, islotes secretos, santuarios y monstruos.

### 1.3 Pilares

| # | Pilar | Qué significa en la práctica | Pregunta para decidir |
|---|---|---|---|
| 1 | **Bello y legible** | Diorama low-poly, sombreado plano, paleta luminosa, agua preciosa, siluetas claras. **Ningún personaje tiene cara** (el rostro de Fanós es una llama). | ¿Se entiende en una captura pequeña? ¿Se ve bonito sin UI? |
| 2 | **Simple de aprender** | Seis acciones: mover, atacar con el ancla, Destello, Embestida de vapor, Haz del Faro, mantener para construir. | ¿Lo entiende alguien en 30 segundos sin tutorial de texto? |
| 3 | **Combate con peso** | Combo de ancla que termina en un golpe al suelo, Destello que empuja, Embestida de vapor con invulnerabilidad, *hit-stop*, retroceso, temblor de cámara. | ¿Cada golpe se siente en las manos? |
| 4 | **Un mundo vivo** | Gatos que se acarician, cabras, gaviotas, delfines, luciérnagas, viento, ciclo de luz. | ¿Dan ganas de quedarse un minuto sin hacer nada? |

### 1.4 Referencias y qué tomamos de cada una

| Referencia | Qué tomamos | Qué evitamos |
|---|---|---|
| **Thronefall** | Bucle día/noche, construcción en puntos fijos, héroe que pelea, minimalismo visual y de UI. | Combate automático y poco profundo del héroe. |
| **Kingdom Two Crowns** | La tensión de "el amanecer como alivio", economía de pocas monedas, ingresos al amanecer. | Lentitud y ambigüedad (aquí todo se explica con iconos claros). |
| **Bad North** | Islas como dioramas cerrados, desembarcos desde el mar, legibilidad desde arriba. | Control indirecto de escuadras. |
| **Hades** | Dones de dioses con identidad clara, sinergias entre dioses (dones dobles), líneas cortas de narración, la "muerte" como parte del ritmo. | Cantidad de texto y diálogo. |
| **God of War** | Peso del combate: *hit-stop*, golpes que empujan, un arma pesada (el ancla), Grecia mítica a escala de monstruos. | Violencia gráfica, cámara al hombro (aquí es diorama). |
| **Octopath Traveler** | La idea de "diorama": profundidad de campo leve, luz dramática por hora del día, mundo que parece una maqueta. | Pixel art (aquí es low-poly facetado). |
| **Zelda: The Wind Waker** | Navegación como pausa contemplativa, islotes pequeños con sorpresas. | Travesías largas y vacías. |

---

## 2. Bucles de juego

### 2.1 Momento a momento (combate, 5–30 s)

**Leer → posicionarse → golpear → reaccionar.** Fanós ve una oleada llegar a una playa, corre hacia ella, rompe la
formación con un Destello, encadena los barridos del ancla, esquiva con la Embestida de vapor el golpe de un Cíclope
y, cuando la Llama está llena, gira con el Haz del Faro. Las torres y los hoplitas sostienen el resto del perímetro mientras tanto.

Decisión constante: **¿dónde estoy más útil ahora?** El héroe no puede estar en todas las playas a la vez.

### 2.2 Día / noche (un ciclo ≈ 5–8 min)

| Fase | Duración | Qué hace el jugador | Emoción |
|---|---|---|---|
| **Día** | Sin límite (≈1,5–3 min) | Construye y mejora en puntos fijos, explora, acaricia gatos, lee las marcas de desembarco. | Calma, planificación |
| **Llamar a la noche** | 1 s (mantener *Interactuar* en el faro) | Decide que está listo. Las playas de esta noche ya están marcadas. | Anticipación |
| **Noche** | ≈2–4 min (por oleadas) | Pelea, se mueve entre frentes, usa el Haz del Faro, protege edificios clave. | Tensión, poder |
| **Amanecer** | ≈20–40 s | Cobra ingresos, ve reconstruirse lo destruido, elige 1 de 3 dones. | Alivio, recompensa |

Reglas clave del ciclo:

- El jugador **elige cuándo empieza la noche**. Nunca hay prisa de día.
- Antes de cada noche, unos **marcadores en el mar** (manchas de tinta índigo con humo y chispas cian) muestran por dónde
  desembarcarán los enemigos. La información siempre llega antes que la amenaza.
- Lo destruido **se reconstruye gratis al amanecer**, pero **no produce ingresos esa mañana**: perder un edificio duele,
  pero no arruina la partida.
- Si Fanós cae, su llama se apaga y el Faro lo vuelve a encender tras unos segundos. Si **cae el faro**, se pierde la isla (se puede reintentar
  desde el inicio de esa noche).

### 2.3 Isla (≈35–65 min)

Cada isla es una partida cerrada de 6–9 noches: empiezas con pocas dracmas y un faro débil, construyes una
economía, abres nuevas playas de desembarco noche a noche y terminas con un **jefe mítico**. La economía (dracmas,
edificios) **se reinicia en cada isla**; lo que se conserva es la meta-progresión (armas, reliquias, constelaciones).

Curva de una isla típica:

1. **Noches 1–2:** una playa, enemigos básicos; se enseña el gimmick de la isla.
2. **Noches 3–5:** se abren 2–3 playas; aparece el enemigo nuevo de la isla; primeras decisiones de qué frente
   dejarle a las torres y cuál defender en persona.
3. **Noche 6 (o penúltima):** pico de presión con todas las playas.
4. **Noche final:** jefe + oleadas de apoyo. Al vencer, se enciende el faro de la isla.

### 2.4 Campaña (≈8 h)

**Isla → travesía por mar → isla.** Al terminar una isla, Fanós sube al barco *Fósforo* ("el que trae la luz") y se
navega por mar abierto hasta la siguiente. En el mar hay islotes opcionales, eventos y animales. Son ocho islas, cada
una con un gimmick, un edificio o una unidad nueva, un enemigo nuevo y un jefe (ver §4).

### 2.5 Meta-progresión (entre islas y entre partidas)

- **Kleos** (gloria): moneda persistente que se gana al terminar islas y retos. Desbloquea armas y mejoras de la armería y del farol.
- **Reliquias:** objetos míticos con efectos pasivos (se equipan hasta 3).
- **Constelaciones:** cada isla salvada vuelve a encender una constelación en el cielo nocturno; sus estrellas son
  pequeñas mejoras permanentes. **La progresión se ve en el cielo del juego.**
- **Rejugar:** dificultad "Noche eterna" con juramentos (modificadores), isla diaria y modo sin fin (ver §5).

---

## 3. Sistemas

### 3.1 Héroe: Fanós, el autómata del faro

**Quién es.** Fanós ("farol") es un autómata de bronce que Hefesto forjó, como a Talos, para cuidar el Faro de Delos.
Cuando Nyx se tragó el Egeo, Hestia guardó dentro de su cabeza la última chispa de su llama eterna. **Su cabeza es un
farol y la llama es su rostro**: no tiene cara, y la llama lo comunica todo (se aviva al atacar, tiembla al recibir
daño, baja con la vida y se apaga al caer). Es robusto, de gestos lentos y paciente: en reposo mira a su alrededor, se
apoya en el ancla clavada en el suelo y contempla el mar; de noche, su farol ilumina el suelo a su alrededor. Su
aspecto completo está en §7.2.

| Atributo | MVP | Notas |
|---|---|---|
| Vida | 130 | Apolo: +40 y regeneración. Sin regeneración base de noche; al amanecer se repara por completo. |
| Velocidad | 6,0 m/s | Hermes: +20 %. |
| Caída y reencendido | ≈6 s | La llama se apaga, se desploma sobre el ancla y el Faro lo vuelve a encender (aviso: "La llama de Fanós se ha apagado · El Faro volverá a encenderla"). Sube 1 s por cada caída en la misma noche (máx. 10 s). |
| Medidor de **Llama** | 0–100 | Se llena al infligir daño (≈+1 por cada 3 de daño); un Destello que aturde da un extra. Activa el Haz del Faro. |

#### Moveset

| Acción | Entrada (teclado / control) | Daño | Tiempos aprox. (arranque / activo / recuperación) | Efecto |
|---|---|---|---|---|
| Barrido 1 | J o clic izq. / X | 13 | 0,12 / 0,10 / 0,24 s | Barrido amplio con el ancla (~150°, ~2,5 m), empuje leve. |
| Barrido 2 | J (en ventana de combo) | 13 | 0,10 / 0,10 / 0,24 s | Barrido de vuelta, en sentido contrario. |
| Ancla al suelo | J (en ventana de combo) | 24 | 0,22 / 0,10 / 0,45 s | Golpe desde arriba con **onda expansiva** (radio ~3 m) y retroceso fuerte. Cierra el combo. |
| **Destello** | K o clic der. / Y | 10 | 0,08 / 0,12 / 0,25 s | La lente se enciende: cono frontal (~60°, ~6 m) que ciega, **aturde 1,4 s** y empuja. Enfriamiento 4 s. Interrumpe ataques normales (no los de jefe). |
| **Embestida de vapor** | Espacio / B | — | ~0,35 s en total | Impulso a vapor de ~4,5 m; **invulnerable ~0,05–0,28 s**; los respiraderos de la espalda sueltan un chorro. Enfriamiento ~0,5 s. |
| **Haz del Faro** | Q / RB | 70 | Carga 0,3 s + giro ~0,8 s (invulnerable) | El farol arde y Fanós gira una vez: el haz barre 360° (radio 10 m), **quema y aturde** (~1 s) todo lo que toca. Consume toda la Llama. |
| Construir / interactuar | Mantener E / mantener A | — | ~0,8–1,2 s | Construye, mejora, acaricia gatos, llama a la noche. Se cancela si lo golpean. |

**Ampliaciones previstas para la versión completa** (no están en el MVP):

| Acción | Entrada | Efecto |
|---|---|---|
| Ancla lanzada | Mantener J ~0,6 s | Lanza el ancla atada a su cadena (~6 m) y la recoge, arrastrando enemigos hacia él. |
| Contraataque a vapor | J al final de la Embestida | Golpe rápido con el ancla (+50 % de daño). Premia embestir *hacia* el enemigo. |
| Destello perfecto | K justo antes del impacto (~0,15 s) | Anula el golpe, devuelve proyectiles y deja al enemigo aturdido. Sin enfriamiento si acierta. |
| Golpe de gracia | J sobre un enemigo grande aturdido | Remate con el ancla y cámara cercana (sin sangre: el enemigo se deshace en motas de luz). Da Llama extra. |

#### Cancelaciones

| Desde ↓ / hacia → | Golpe siguiente | Destello | Embestida | Haz |
|---|---|---|---|---|
| Barridos 1–2 (activo) | — | No | No | No |
| Barridos 1–2 (recuperación) | Sí (ventana ~0,25 s) | Sí | Sí | Sí |
| Ancla al suelo (recuperación) | No (reinicia combo) | Sí | Sí | Sí |
| Destello (recuperación) | Sí (entra al Barrido 2) | — | Sí | Sí |
| Embestida (final) | Sí | Sí | No (enfriamiento) | Sí |

Regla general: **la Embestida cancela casi todo** (el jugador siempre puede salvarse), pero no la fase activa de un golpe
(los golpes se comprometen).

#### Sensación de impacto (*game feel*)

| Elemento | Valor de referencia |
|---|---|
| *Hit-stop* | Barridos: ~0,05 s · ancla al suelo: ~0,09 s · Destello: ~0,07 s · Haz del Faro: ~0,12 s · golpe de gracia: ~0,15 s. |
| Temblor de cámara | Pequeño en los barridos, medio en el ancla al suelo y el Destello, fuerte en el Haz y en golpes de jefe. Opción para reducirlo. |
| Destello del impacto | El enemigo golpeado se pone blanco ~0,06 s; chispas de bronce en el punto de impacto. |
| Retroceso | Barridos: 0,5–1 m · ancla al suelo: ~2,5 m · Destello: ~4 m. Los enemigos grandes resisten (factor de masa). |
| La llama como vida | La llama del farol baja y parpadea al perder vida: el jugador lee el estado de Fanós sin mirar la UI. |
| Números de daño | Desactivados por defecto (UI mínima); activables en opciones. |
| Sonido | Cada golpe tiene capa de impacto sordo + capa de bronce; el ancla al suelo suena como una campana grave; la Embestida, a siseo de vapor. |

#### Reglas del combate

- Los enemigos **telegrafían**: brillo de ojos más intenso y pose de carga ~0,4–0,8 s antes de golpear.
- Fanós **no se bloquea en animaciones largas**; ninguna acción dura más de ~0,6 s, salvo el Haz y el golpe de gracia.
- **Fuego amigo:** no existe. El Haz del Faro no daña edificios ni aliados.
- **Prioridad de objetivo enemigo:** cada enemigo tiene una preferencia (faro, edificios, héroe, torres) para que la
  defensa sea un rompecabezas legible (ver §3.4).

### 3.2 Construcción y economía

**Construir:** cada isla tiene **puntos de construcción fijos** (círculos de piedra con una moneda flotante). El jugador
se acerca, ve el edificio fantasma y el costo, y **mantiene E** para pagar. Mejorar funciona igual sobre un edificio ya
hecho. Mejorar el faro amplía el **radio de construcción** y hace aparecer nuevos puntos.

**Moneda:** dracmas. Se empieza con **12**. Los ingresos llegan solo al amanecer (en la versión completa, los enemigos
grandes también sueltan alguna moneda).

| Edificio | Nivel 1 | Nivel 2 | Nivel 3 | Efecto | Vida aprox. |
|---|---|---|---|---|---|
| **Faro** (núcleo) | — (inicial) | 12 | 20 | +3 dracmas/amanecer. Cada nivel: más vida y más radio de construcción. Si cae, se pierde la isla. | 600 / 800 / 1000 |
| **Casa** | 4 → +2/amanecer | ≈6 → +3 | — | Economía básica. Aparecen gatos al sol junto a las casas. | 80 / 120 |
| **Olivar** | 6 → +3 | ≈8 → +5 | — | Economía; ocupa espacio en laderas. | 70 / 100 |
| **Muelle de pesca** | 5 → +3 | ≈7 → +4 | — | Economía en la costa: **expuesto** (está junto a las playas). | 70 / 100 |
| **Torre de arqueros** | 6 | 10 | 16 | Dispara al enemigo más cercano; prioriza voladores. Más daño y alcance por nivel. | 150 / 220 / 300 |
| **Muralla** | 3 (empalizada) | 6 (piedra) | — | Bloquea el paso a pie; los enemigos la golpean. No frena a Keres. | 200 / 450 |
| **Cuartel de hoplitas** | 8 (2 hoplitas) | 12 (3 hoplitas más fuertes) | — | Los hoplitas guardan una zona cercana y reaparecen al amanecer. | 250 / 350 |

Los costos de nivel 2 de los edificios de economía son provisionales y se calibran en las pruebas.

**Reglas de economía**

- Los ingresos del amanecer solo cuentan edificios **en pie al terminar la noche**.
- Lo destruido se reconstruye gratis al amanecer, sin ingresos esa mañana.
- No hay venta ni demolición en el MVP (evita errores irreversibles).
- Objetivo de diseño: al final de la noche 7 el jugador puede haber construido el **~70–80 %** de los puntos. Nunca
  todo: **elegir es el juego**.

**Ramas de mejora (versión completa).** A partir del nivel máximo, algunos edificios se especializan en una de dos
ramas (elección permanente en esa isla):

| Edificio | Rama A | Rama B |
|---|---|---|
| Torre de arqueros | **Torre de Artemisa:** mucho alcance, críticos contra voladores. | **Oxíbeles (balista):** virote que atraviesa en línea, lento. |
| Muralla | **Muralla de púas:** daña a quien la golpea. | **Muralla ciclópea:** el doble de vida, más cara. |
| Cuartel | **Falange:** escudos unidos, bloquean proyectiles. | **Peltastas:** jabalinas a media distancia. |
| Casa | **Ágora:** +1 dracma por cada casa vecina. | **Santuario del hogar:** repara a Fanós cuando pasa cerca. |
| Olivar | **Prensa de aceite:** el aceite alimenta las antorchas (más luz y alcance de torres cercanas). | **Bosque sagrado:** produce Llama durante la noche. |
| Muelle | **Astillero:** barcas incendiarias contra enemigos en el agua. | **Lonja:** +3 dracmas pero más frágil. |
| Faro (nivel 4) | **Haz de Apolo:** el haz del faro hiere a las Keres que cruza. | **Llama de Hestia:** el faro cura a edificios cercanos al amanecer. |

### 3.3 Unidades aliadas

Los aliados **no se controlan directamente**: guardan su zona. En la versión completa, el héroe puede **plantar un
estandarte** (mantener *Interactuar* en un punto vacío) para mover el punto de reunión del cuartel más cercano.

| Unidad | Origen | Vida | Daño | Rol | Notas |
|---|---|---|---|---|---|
| **Hoplita** | Cuartel nv. 1 (×2) | 60 | 8 | Contener cuerpo a cuerpo | Escudo y lanza; bronce clásico, yelmo corintio y penacho azul (contraste buscado con Fanós). |
| **Hoplita veterano** | Cuartel nv. 2 (×3) | 90 | 11 | Contener mejor | Penacho azul. |
| **Falange** | Rama del cuartel | 100 | 9 | Bloquear proyectiles | Se mueve lento en bloque. |
| **Peltasta** | Rama del cuartel | 50 | 10 a distancia | Apoyo | Jabalinas; evita el cuerpo a cuerpo. |
| **Ménade** | Naxos (nuevo) | 45 | 6 + aturdir | Control | Tirso que aturde; danza (sin cara: velo y corona de hiedra). |
| **Arquero cretense** | Creta (nuevo) | 40 | 7 a distancia | Patrulla móvil | Sigue al héroe a corta distancia. |
| **Cantor de Orfeo** | Lesbos (nuevo) | 40 | — | Apoyo | Inmuniza contra el canto de las Sirenas en su aura. |
| **Eco de héroes** | Ténaro (final) | 150 | 15 | Refuerzo de élite | Siluetas doradas con yelmo de Teseo, Orfeo, Odiseo…; se invocan una vez por noche desde un brasero. |

### 3.4 Enemigos: la prole de Nyx

Todas las criaturas de Nyx están **hechas de cielo nocturno**: cuerpo índigo con estrellas que titilan dentro, borde
violeta suave, bajos de humo que se deshilachan, siluetas encapuchadas que flotan, **ojos almendrados que brillan**
(cian; carmesí-rosado en las Keres; violeta en los jefes), un adorno de media luna de plata y **ninguna boca**. Mueren
deshaciéndose en motas de luz. El aspecto de cada una está en §7.10.

#### Enemigos del MVP (Delos)

| Enemigo | Vida | Daño | Velocidad | Prioridad de objetivo | Rol | Cómo se contrarresta |
|---|---|---|---|---|---|---|
| **Sombra** | 30 | 6 | Media | Lo más cercano en su ruta al faro | Masa básica | Torres, barridos del ancla. |
| **Ker** | 18 | 5 | Rápida, vuela | Edificios de economía y héroe | Acosadora; **ignora murallas** | Torres (priorizan voladores), Haz del Faro, Artemisa. |
| **Escudado** | 70 | 9 | Lenta | Murallas y hoplitas | Tanque (hoplita caído); **flechas a la mitad** | Destello (rompe guardia), ancla al suelo, hoplitas, Hefesto. |
| **Arquero de Nyx** | 25 | 8 a ~12 m | Media | Torres y hoplitas | Desgaste a distancia | Fanós flanquea con la Embestida; murallas cortan su avance. |
| **Cíclope de sombra** | 260 | 25 (×3 a edificios) | Muy lenta | Edificios | Demoledor; golpe en área | Aturdirlo con el Destello, retenerlo con muralla de piedra bajo fuego de torres. |

#### Enemigos nuevos de la campaña

| Enemigo | Isla | Rol | Mecánica | Contrarresto |
|---|---|---|---|---|
| **Pirata tirreno** | Naxos | Desembarco masivo | Llegan en barcas: si una torre hunde la barca antes de tocar tierra, se pierden todos. | Torres costeras, Astillero. |
| **Toro de sombra** | Creta | Ariete | Embiste en línea recta, derriba murallas de un golpe; si choca con piedra queda aturdido. | Muralla ciclópea en ángulo, esquivar y castigar. |
| **Autómata de bronce** | Rodas | Blindado | Inmune a flechas normales por el frente; vulnerable por la espalda y a la luz. | Rodearlo, Oxíbeles, Haz del Faro. |
| **Harpía** | Lesbos | Ladrona | Roba dracmas de casas y muelles y huye volando; si la matas, devuelve el botín. | Torres de Artemisa, perseguir con Hermes. |
| **Lestrigón** | Ítaca | Artillería pesada | Gigante que lanza rocas a los edificios desde el agua poco profunda. | Haz del Faro, entrar al agua a buscarlo, Peltastas. |
| **Salamandra de ceniza** | Thera | Kamikaze | Explota al morir y quema lo cercano; inmune al fuego. | Matarla lejos de edificios: arqueros, jabalinas. |
| **Oniro** (sueño) | Ténaro | Ilusionista | Crea copias falsas de Fanós y de enemigos; las copias se rompen de un golpe. | Leer la luz: las copias no tienen ojos encendidos (ni llama, las de Fanós). |

Los enemigos nuevos siguen el mismo lenguaje de cielo nocturno; los Autómatas de bronce, por ejemplo, son hermanos de
Fanós corrompidos por Nyx: bronce oscuro con grietas por las que se ve el cielo estrellado.

### 3.5 Jefes

Los jefes llegan en la **última noche** de cada isla, con oleadas de apoyo. Reglas comunes: barra de vida segmentada
por fases, ataques muy telegrafiados (zonas marcadas en el suelo con líneas de luz violeta), siempre hay una ventana
de castigo clara, y **ningún jefe tiene cara**: fauces cerradas sin dientes, capuchas, máscaras o brillo interior.

| Jefe | Isla | Fases | Mecánica clave | Cómo se vence |
|---|---|---|---|---|
| **Hidra de la Noche** | Delos (MVP) | 3 (66 % / 33 %) | Sale del mar; 3 cuellos de serpiente que golpean con las fauces cerradas y escupen orbes de sombra contra las torres; a 66 % y 33 % invoca Sombras. | Esquivar los golpes, castigar la cabeza que queda clavada en el suelo tras golpear; las torres limpian a los invocados. |
| **Los Alóadas** | Naxos | 2 | Dos gigantes gemelos que atacan juntos; se curan si están cerca uno del otro. | Como en el mito, hacer que se golpeen entre sí: cuando cargan, ponerse entre los dos y esquivar en el último momento. |
| **Minotauro de Nyx** | Creta | 3 | Persigue al héroe dentro del laberinto y embiste a través de los muros. | Atraerlo contra columnas de piedra para aturdirlo; el hilo de Ariadna marca su ruta. |
| **El Coloso (Talos)** | Rodas | 3 | Gigante de bronce (el primer autómata de Hefesto, "hermano mayor" de Fanós) que pisa la isla y lanza rayos de calor. | Su punto débil es el clavo del tobillo (como en el mito de Medea): el Destello y el ancla al suelo lo aflojan hasta soltar el icor. |
| **Las Sirenas** | Lesbos | 3 | Tres figuras aladas con velo; su canto encanta a hoplitas y aldeanos, que caminan hacia el mar. | Destruir sus rocas de canto; el aura del Santuario de Orfeo protege a los aliados. |
| **Escila y Caribdis** | Ítaca | 2 + 2 | Escila (seis cuellos desde un acantilado) arrebata unidades; Caribdis (remolino) arrastra todo hacia el centro. | Caribdis traga también a los enemigos: usarla a favor. Golpear los cuellos de Escila cuando se clavan en tierra. |
| **Tifón** | Thera | 3 | El padre de los monstruos dentro del volcán; lluvia de ceniza, ríos de lava, cabezas de serpiente. | Sobrevivir hasta cargar el Haz del Faro al máximo y apuntarlo al cráter; fase final cuerpo a cuerpo. |
| **Nyx** | Ténaro | 3 | La Noche misma: apaga luces, roba el radio de construcción, invoca ecos de todos los jefes. | Mantener vivas las luces mientras la llama se carga; final narrativo (ver §6). |

### 3.6 Dones divinos

Al amanecer se ofrecen **3 dones al azar** (en el MVP, nunca uno que ya tengas); se elige **uno**. Cada don es un
modificador simple que se lee en una línea.

| Dios | Don (MVP) | Para qué estilo | Sinergias recomendadas |
|---|---|---|---|
| **Zeus** | La Llama se carga un 35 % más rápido; Haz del Faro +50 % de daño. | Héroe agresivo | Ares (más daño → más Llama). |
| **Poseidón** | Los enemigos que salen del mar quedan ralentizados unos segundos. | Defensa de playas | Artemisa (más disparos mientras están lentos). |
| **Atenea** | Edificios +30 % de vida. | Defensivo | Hefesto, Hestia. |
| **Artemisa** | Torres +25 % cadencia y +alcance. | Torres | Poseidón, Hefesto. |
| **Apolo** | Fanós +40 de vida máxima y autorreparación. | Aguante | Ares (puedes arriesgar más). |
| **Hermes** | Velocidad +20 %; Embestida de vapor más rápida y con menos enfriamiento. | Movilidad (cubrir varios frentes) | Zeus, Apolo. |
| **Ares** | Daño del ancla y del Destello +30 %. | Héroe agresivo | Zeus, Apolo. |
| **Hefesto** | Murallas +60 % de vida; torres +20 % de daño. | Fortaleza | Atenea, Artemisa. |
| **Deméter** | Olivares y muelles +2 de ingreso. | Economía | Hestia (todo a economía al principio). |
| **Hestia** | Casas +1 de ingreso; faro +25 % de vida. | Economía y seguridad | Deméter, Atenea. |

**Versión completa:**

- **Niveles:** el mismo don puede salir de nuevo como nivel II y III (efecto +50 % cada vez).
- **Dones dobles** (estilo Hades): aparecen solo si ya tienes un don de cada dios.

| Don doble | Requisitos | Efecto |
|---|---|---|
| Tormenta marina | Zeus + Poseidón | Caen rayos sobre los enemigos que están en el agua. |
| Gemelos de Delos | Apolo + Artemisa | Las flechas de las torres reparan a Fanós 1 punto por impacto. |
| Égida forjada | Atenea + Hefesto | Las murallas devuelven el 30 % del daño recibido. |
| Furia veloz | Ares + Hermes | Tras la Embestida de vapor, el siguiente golpe hace +100 %. |
| Hogar fértil | Deméter + Hestia | +1 dracma por cada casa vecina de un olivar. |
| Mensajero del rayo | Zeus + Hermes | La Embestida de vapor deja una estela eléctrica que daña. |

- **Pactos de Nyx** (opcionales, desde la isla 3): al amanecer, aceptar una noche más dura (+1 playa, enemigos más
  rápidos…) a cambio de un don extra o Kleos. Riesgo elegido, nunca impuesto.

### 3.7 Dificultad

| Modo | Para quién | Cambios principales |
|---|---|---|
| **Peregrino** | Primera vez o poca experiencia en acción | Héroe +50 % de vida, enemigos −25 % de vida, reaparición en 3 s, marcadores con conteo de enemigos. |
| **Hoplita** (normal) | Recomendado | Valores de este documento. |
| **Espartano** | Jugadores de acción | Enemigos +30 % de vida y daño, reaparición 10 s, menos dracmas iniciales. |
| **Noche eterna** | Post-campaña | Hoplita + **juramentos** acumulables (ver §5.5). |

**Red de seguridad:** perder una isla permite **reintentar desde el inicio de la última noche** (el guardado se hace al
amanecer). Nunca se pierden más de ~5–8 min de progreso. **Ajuste dinámico suave:** si se pierde dos veces la misma
noche, se ofrece (no se impone) un don de apoyo extra.

---

## 4. Campaña: La Odisea de la Luz (~8 h)

### 4.1 Premisa

Delos resiste siete noches (el MVP). Al amanecer del octavo día, el Oráculo habla: la llama de Hestia sola no puede
devolver el sol. Hay que **llevarla por el Egeo y volver a encender los faros antiguos de otras seis islas**, y luego
cruzar hasta el **cabo Ténaro**, donde se abren las puertas del Érebo, para enfrentarse a Nyx. La llama viaja en la
cabeza de Fanós, que de noche guía desde la proa al *Fósforo*, una pentecóntera (nave de 50 remos). Cada faro encendido devuelve una
**constelación** al cielo.

### 4.2 Ruta

**Delos → Naxos → Creta → Rodas → Lesbos → Ítaca → Thera → Ténaro.** La ruta zigzaguea por el Egeo, como la de Odiseo:
el viento de Nyx desvía la nave (y así se justifica una travesía larga de Ítaca a Thera, empujada por la tormenta de
Poseidón). En la primera partida el orden es fijo para controlar la curva de dificultad y de mecánicas. En "Noche
eterna" se puede elegir el orden y los enemigos escalan según el número de islas completadas.

### 4.3 Navegación por mar abierto (el "mundo abierto" del juego)

Entre isla e isla, el jugador **navega libremente** por una región de mar (~600 × 600 m) con 3–5 islotes. Aquí entra el
sueño del cliente de una Grecia abierta, con agua preciosa, animales y mitología, pero con un alcance controlado.

| Elemento | Diseño |
|---|---|
| **Control** | El *Fósforo* se dirige con el stick o WASD. Mantener *Embestida* hace **remar fuerte** (ráfaga con enfriamiento). Con el viento a favor (indicador en la vela), se va más rápido. |
| **Tiempo** | Cada travesía empieza al alba y tiene un **reloj de sol**: explorar islotes consume tiempo. Si cae el sol antes de llegar, hay una **Noche en el mar**. |
| **Noche en el mar** | Defensa corta (2–3 min) en la que el barco es una mini-fortaleza: 3 puntos de construcción en cubierta (arquero, brasero, puesto de hoplita) y el héroe pelea a bordo. Es arriesgada pero da Kleos extra. |
| **Islotes** | Desembarco a pie en islotes pequeños (1–3 min cada uno), con el combate y los controles de las islas. |
| **Recompensas** | Dracmas iniciales para la próxima isla, reliquias, Kleos, inscripciones de lore, gatos de a bordo. |
| **Escala técnica** | Una región de mar cargada a la vez (web). Reutiliza el agua, el generador de islas, los animales y el combate de las islas. |

**Tipos de islote**

| Islote | Qué hay | Recompensa |
|---|---|---|
| **Santuario** | Altar de un dios, ofrenda de dracmas. | El don de ese dios desde el primer día de la próxima isla. |
| **Naufragio** | Restos de una nave entre rocas; cangrejos y gaviotas. | +4–8 dracmas iniciales en la próxima isla. |
| **Cueva de Nyx** | Arena de combate cerrada (2–4 min), oleadas sin construcción. Es la parte más "God of War". | Reliquia. |
| **Poza de marea** | Pulpos, tortugas, erizos; modo foto. | Lore y una estrella de constelación por "catálogo" completo. |
| **Ruina con inscripción** | Estela o columna caída con un fragmento del mito. | Kleos y una línea del Oráculo. |
| **Islote de los gatos** | Gatos entre redes y ánforas. | **Gato de a bordo** (acompaña a Fanós en las islas; puro cariño, +1 de Llama al acariciarlo). |

**Eventos en el mar** (aparecen al azar, uno o dos por travesía)

| Evento | Qué pasa |
|---|---|
| **Delfines** | Una manada nada junto a la proa: si la sigues, te lleva a un islote secreto y da velocidad. |
| **Mercader fenicio** | Barco con un mercader encapuchado: cambia dracmas o Kleos por reliquias. |
| **Tormenta** | Olas grandes y viento cruzado; navegar entre las crestas. Se ve la tormenta antes de que llegue. |
| **Ballena** | Un rorcual sale a respirar; la cámara se aleja para mostrar su tamaño. Puro asombro, sin mecánica. |
| **Náufrago** | Un aldeano en una balsa: en la próxima isla hay una casa construida gratis. |
| **Canto lejano** | Presagio de las Sirenas (antes de Lesbos): la nave se desvía si no se rema contra la corriente. |
| **Hipocampos** | Caballos de mar míticos que retan a una carrera entre boyas. |

### 4.4 Las ocho islas

Cada isla añade **una sola idea nueva grande** (su gimmick) y la combina con todo lo anterior.

#### 1 · Delos — La isla del faro (MVP)

- **Duración:** ~35 min · 7 noches. **Mapa:** ~140 × 110 m; el faro sobre una colina central; caminos de tierra hacia
  4 playas (S, E, O, N) que se abren noche a noche.
- **Gimmick:** ninguno; enseña lo básico: construir, leer las playas marcadas, elegir dones.
- **Nuevo:** todos los edificios base. **Enemigos:** Sombra, Ker, Escudado, Arquero de Nyx, Cíclope de sombra.
- **Jefe:** Hidra de la Noche. **Mito:** Leto da a luz a Apolo y Artemisa en Delos, la isla errante que Poseidón ancló
  al fondo del mar con cuatro columnas.

#### 2 · Naxos — Las mareas de Dioniso

- **Duración:** ~45 min · 7 noches. **Mapa:** isla alargada con dos bahías, bancos de arena y viñedos en terrazas.
- **Gimmick: mareas.** Cada noche alterna pleamar y bajamar (se anuncia de día). En bajamar aparecen bancos de arena:
  rutas nuevas para el enemigo y **puntos de construcción temporales** muy rentables que la pleamar se lleva.
- **Nuevo:** **Viñedo** (economía que madura: +1 por cada amanecer sin daño, hasta +6) y la unidad **Ménade**.
- **Enemigo nuevo:** Pirata tirreno. **Jefe:** Los Alóadas.
- **Mito:** Dioniso convierte en delfines a los piratas que lo secuestran; Ariadna, abandonada por Teseo, se queda en
  Naxos. Los gigantes Alóadas murieron aquí, engañados por Artemisa.

#### 3 · Creta — El laberinto de Dédalo

- **Duración:** ~55 min · 8 noches. **Mapa:** palacio minoico en ruinas (columnas rojas que se estrechan hacia abajo,
  patios, frescos de pulpos y delfines) rodeado por un laberinto.
- **Gimmick: laberinto.** De día se giran secciones de muro con palancas: **el jugador diseña el camino** del enemigo
  (alargarlo bajo las torres, o acortarlo hacia una trampa).
- **Nuevo:** **Taller de Dédalo** (trampas: cepo de bronce, rodillo de piedra) y la unidad **Arquero cretense**.
- **Enemigo nuevo:** Toro de sombra. **Jefe:** Minotauro de Nyx.
- **Mito:** Dédalo construye el laberinto y las alas de Ícaro; Teseo entra con el hilo de Ariadna.

#### 4 · Rodas — Los espejos de Helios

- **Duración:** ~50 min · 7 noches. **Mapa:** puerto con dos espigones (donde estuvo el Coloso) y una acrópolis blanca
  sobre un acantilado.
- **Gimmick: luz reflejada.** El haz del faro gira de noche. Los **Espejos de bronce** (puntos fijos) lo desvían: una
  línea de luz que quema a lo que cruza. Colocar y orientar espejos es el rompecabezas de la isla.
- **Nuevo:** Espejo de bronce. **Enemigo nuevo:** Autómata de bronce. **Jefe:** El Coloso (Talos).
- **Mito:** Rodas emerge del mar y Helios la elige; el Coloso; Talos, el gigante de bronce con una sola vena de icor
  cerrada por un clavo: el "hermano mayor" de Fanós, corrompido por Nyx.

#### 5 · Lesbos — La niebla de las Sirenas

- **Duración:** ~55 min · 8 noches. **Mapa:** pinares y olivares en terrazas alrededor de un golfo interior en calma,
  con flamencos en las salinas.
- **Gimmick: niebla y canto.** La niebla oculta el mar: los desembarcos solo se ven dentro de la luz (faro, antorchas).
  El canto de las Sirenas **encanta** a hoplitas y aldeanos, que caminan hacia el agua si nadie los protege.
- **Nuevo:** **Santuario de Orfeo** (aura que protege del canto y disipa la niebla) y la unidad **Cantor de Orfeo**.
- **Enemigo nuevo:** Harpía. **Jefe:** Las Sirenas.
- **Mito:** la cabeza de Orfeo y su lira llegan flotando a Lesbos, todavía cantando; la isla de la poesía de Safo.

#### 6 · Ítaca — La tormenta de Poseidón

- **Duración:** ~55 min · 8 noches. **Mapa:** isla montañosa con calas, el palacio de Odiseo y un estrecho rocoso.
- **Gimmick: viento y rayos.** El viento cambia cada noche (veleta sobre el faro): las flechas a favor llegan más
  lejos, en contra se quedan cortas. Los rayos caen sobre lo más alto; un **Pararrayos** los convierte en Llama.
- **Nuevo:** **Torre del Arco de Odiseo** (una flecha que atraviesa hasta 12 enemigos en línea, como las doce hachas).
- **Enemigo nuevo:** Lestrigón. **Jefe:** Escila y Caribdis.
- **Mito:** Odiseo vuelve a casa; Penélope teje y desteje; la prueba del arco.

#### 7 · Thera — El despertar de Tifón

- **Duración:** ~60 min · 9 noches. **Mapa:** caldera: anillo de acantilados con el pueblo blanco en lo alto y un islote
  volcánico humeante en el centro de la bahía. Los enemigos llegan por fuera y por dentro de la caldera.
- **Gimmick: volcán.** Las erupciones se anuncian una noche antes (humo). Lluvia de ceniza (menos visión) y ríos de lava
  que cortan caminos y queman edificios. El suelo volcánico da +2 a olivares y viñedos: riesgo contra recompensa.
- **Nuevo:** **Forja de Hefesto** (mejora a los aliados) y **Torre de fuego griego** (daño en área, incendia).
- **Enemigo nuevo:** Salamandra de ceniza. **Jefe:** Tifón.
- **Mito:** Zeus vence a Tifón y lo sepulta bajo una montaña; la gran erupción y el eco de la Atlántida.

#### 8 · Ténaro — Las puertas del Érebo (final)

- **Duración:** ~50 min · 6 noches largas. **Mapa:** cabo gris al final del mundo, cipreses, cuevas y un río negro.
- **Gimmick: noche eterna.** No hay día pleno: solo **crepúsculos** cortos (con reloj) para construir. El territorio es
  la luz: cada **brasero** encendido crea puntos de construcción; si se apaga, se pierden.
- **Nuevo:** Brasero y **Eco de héroes** (siluetas doradas de Teseo, Orfeo, Odiseo… que se invocan una vez por noche).
- **Enemigo nuevo:** Oniro. **Jefe:** Nyx.
- **Mito:** por Ténaro bajaron Orfeo y Heracles al Hades. Nyx, madre de Hipnos y Tánatos, es la única diosa a la que
  hasta Zeus teme.

### 4.5 Duración de la campaña

| # | Tramo | Noches | Isla (min) | Travesía a la siguiente (min) | Acumulado |
|---|---|---|---|---|---|
| — | Prólogo (vasijas pintadas) | — | 3 | — | 0:03 |
| 1 | Delos | 7 | 35 | 6 (tutorial de navegación) | 0:44 |
| 2 | Naxos | 7 | 45 | 9 | 1:38 |
| 3 | Creta | 8 | 55 | 8 | 2:41 |
| 4 | Rodas | 7 | 50 | 10 | 3:41 |
| 5 | Lesbos | 8 | 55 | 12 | 4:48 |
| 6 | Ítaca | 8 | 55 | 10 (tormenta) | 5:53 |
| 7 | Thera | 9 | 60 | 8 (mar de Nyx) | 7:01 |
| 8 | Ténaro | 6 | 50 | — | 7:51 |
| — | Epílogo | — | 4 | — | **7:55** |

**Totales:** 60 noches · islas 6 h 45 min · travesías 1 h 03 min · prólogo y epílogo 7 min. Con reintentos de noches
perdidas, una primera partida real ronda **8–9 h**. Completarlo todo (islotes, cuevas, retos y constelaciones) lleva
**~11–12 h**.

---

## 5. Meta-progresión y rejugabilidad

La economía se reinicia en cada isla; lo que persiste hace al héroe **más versátil**, no solo más fuerte, para que la
dificultad de cada isla siga siendo relevante.

### 5.1 Kleos y armería

**Kleos** (gloria) se gana al terminar islas, cuevas y retos. Se gasta en la **forja de a bordo** del *Fósforo*, donde
Fanós cambia de arma. Cada arma trae su propia acción secundaria y su especial, y tiene 3 mejoras compradas con Kleos
(golpes más largos, enfriamiento menor, efecto extra).

| Arma | Desbloqueo | Estilo | Ataque (J) | Secundaria (K) | Especial (Q) |
|---|---|---|---|---|---|
| **Ancla de Delos** | Inicial | Pesada, de área | 2 barridos + ancla al suelo (13/13/24) | **Destello** de la lente: ciega, aturde y empuja | **Haz del Faro**: barrido de luz de 360° |
| **Remos gemelos** | Tras Naxos | Rápida, agresiva | Combo de 5 golpes con dos remos de bronce (7/7/8/8/16) | Bloqueo cruzado: parada corta con contraataque | **Galerna**: torbellino de remos que avanza y arrastra |
| **Cadenas de Hefesto** | Tras Creta | Alcance medio, control | Latigazos de cadena (~5 m) que atraen | Garfio: tira de un enemigo hacia Fanós, o de Fanós hacia un punto alto | **Fragua**: las cadenas se ponen al rojo y giran a su alrededor |
| **Lente de Helios** | Tras Rodas | A distancia, precisión | Rayos de luz concentrada; mantener: rayo continuo que atraviesa | Destello amplio (más ancho, sin aturdir) | **Mediodía**: una columna de sol cae y persigue a los enemigos 3 s |

### 5.2 El farol: llamas y mejoras

La cabeza de Fanós también progresa. Con Kleos se mejoran **tres piezas del farol** (3 niveles cada una): **cristales**
(más radio de luz de noche), **mecha** (la Llama se carga más rápido) y **cúpula** (más vida). Además, varias islas
regalan **el color de una llama**, que se elige a bordo antes de desembarcar: es la "clase" ligera de la partida, y se
ve en toda la isla, porque el farol tiñe de ese color el suelo a su alrededor.

| Llama | Se obtiene en | Efecto |
|---|---|---|
| **Ámbar de Hestia** | Inicial | Equilibrada, sin modificadores. |
| **Dorada de Helios** | Rodas | Cada noche empieza con la Llama al 50 %. |
| **Blanca de Apolo** | Lesbos | +25 % de radio de luz; el Haz del Faro da un giro y medio. |
| **Azul de Poseidón** | Ítaca | El Haz ralentiza lo que toca. Es un azul profundo, nunca cian (el cian es de Nyx). |
| **Roja de Hefesto** | Thera | El Destello quema (daño durante 3 s). |
| **Violeta de Nyx** | Final de la campaña | La Llama también se carga al recibir daño. |

### 5.3 Reliquias

Se equipan hasta **3** a la vez (a bordo, entre islas). Se encuentran en jefes, cuevas e islotes.

| Reliquia | Dónde | Efecto |
|---|---|---|
| **Hilo de Ariadna** | Creta (jefe) | Los marcadores de desembarco muestran también qué enemigos vienen. |
| **Sandalias de Hermes** | Cueva de Nyx | Dos Embestidas de vapor seguidas. |
| **Vellocino de oro** | Islote secreto (delfines) | Una vez por noche, la llama de Fanós se reaviva al instante. |
| **Cuerno de Amaltea** | Santuario | +3 dracmas en cada amanecer. |
| **Lira de Orfeo** | Lesbos (jefe) | Aliados inmunes a encantamiento y aturdimiento. |
| **Clavo de Talos** | Rodas (jefe) | El Destello y el ancla al suelo hacen el doble de daño a jefes y constructos. |
| **Odre de Eolo** | Ítaca (evento) | Una vez por noche: ráfaga que devuelve al mar a los enemigos de una playa. |
| **Niebla de Hades** | Cueva de Nyx | Tras la Embestida, el vapor se vuelve negro: 1 s de invisibilidad y los enemigos pierden el objetivo. |

### 5.4 Constelaciones

Cada isla salvada **vuelve a encender una constelación** en el cielo nocturno del juego. Sus estrellas se ganan con
retos de la isla (ganar sin perder edificios, vencer al jefe sin caer, acariciar a todos los gatos, completar en
Espartano…) y cada estrella da una mejora pequeña y permanente.

| Constelación | Isla | Mito | Rama de mejoras | Ejemplo de estrella |
|---|---|---|---|---|
| **Orión** | Delos | El cazador | Héroe | +10 de vida máxima. |
| **Corona Boreal** | Naxos | La corona de Ariadna | Economía | +2 dracmas iniciales. |
| **Tauro** | Creta | El toro de Zeus | Murallas y trampas | Las empalizadas empiezan con +20 % de vida. |
| **Águila** | Rodas | El águila de Zeus | Torres | Las torres de nivel 1 cuestan 1 dracma menos. |
| **Lira** | Lesbos | La lira de Orfeo | Aliados | Los hoplitas reaparecen también a medianoche. |
| **Delfín** | Ítaca | El delfín de Poseidón | Navegación | +15 % de velocidad del *Fósforo*. |
| **Hércules** | Thera | El héroe | Contra jefes | +10 % de daño a jefes. |
| **Fanós** | Ténaro | **Nueva**: la primera estrella nacida en eras, con forma de farol | Final | Desbloquea "Noche eterna". |

### 5.5 Modos y rejugabilidad

| Modo | Qué es | Desbloqueo |
|---|---|---|
| **Noche eterna** | La campaña con **juramentos de Nyx** acumulables; cada juramento suma rango (1–3); el rango total da Kleos y emblemas. | Terminar la campaña |
| **Vigilia sin fin** | Delos con noches infinitas y escalado; récord de noches. | Terminar Delos |
| **Oráculo del día** | Una isla con semilla diaria, mismos dones ofrecidos para todos; tabla de puntuación. | Terminar Creta |
| **Elegir isla** | Rejugar cualquier isla con cualquier arma y reliquias. | Al completarla |

**Juramentos de Nyx (ejemplos):** +1 playa por noche · enemigos +20 % de velocidad · sin reconstrucción gratis · dones
de 2 opciones en vez de 3 · faro con −30 % de vida · jefes con una fase extra · marcadores de desembarco solo 5 s antes.

**Cosméticos** (por retos, nunca a la venta): fajas de vela de colores, grabados de la lente (lechuza, pegaso, pulpo,
delfín, ancla), emblemas del sol del pecho, colores de penacho para los hoplitas, estilos de aldea (cicládico, minoico,
rodio) y variantes del gato de a bordo.

---

## 6. Narrativa y tono

### 6.1 Tono

Épico pero sereno: **melancolía luminosa**. El mito se cuenta como en una vasija: con pocas figuras, gestos claros y
mucha atmósfera. Nunca hay sangre ni gore (los enemigos se deshacen en motas de luz). El humor llega de los gatos y de
los gestos de Fanós (un resoplido de vapor, cómo se apoya en el ancla a mirar el mar), nunca de chistes en diálogos.

### 6.2 Cómo se cuenta sin caras y sin diálogos largos

| Recurso | Uso | Reglas |
|---|---|---|
| **El Oráculo** | Una voz velada (la Pitia) que habla al amanecer, al aparecer un enemigo nuevo o un jefe. | Máximo 2 líneas (~15 palabras). EB Garamond en itálica. Voz opcional: susurro procesado o coro sin palabras, nunca doblaje con labios. |
| **Vasijas pintadas** | Prólogo, inicio y final de cada isla, epílogo. | Animación 2D en estilo de **cerámica de figuras negras** (siluetas negras sobre terracota). La cámara gira alrededor del ánfora. 20–40 s cada una. Las siluetas de perfil no tienen rasgos. |
| **Inscripciones** | Estelas en islotes y ruinas; frases grabadas en cada faro. | Una o dos frases; se coleccionan en el **Códice** del barco. |
| **El mundo** | Frescos minoicos, estatuas erosionadas sin rostro, las constelaciones que vuelven al cielo. | Cada isla cuenta su mito con al menos un elemento de escenario. |
| **Personajes** | Fanós, el Oráculo (velado), el Timonel del *Fósforo* (capucha), el gato de a bordo. | Se expresan con postura, gestos, luz y sonido (la llama de Fanós se aviva, tiembla o se apaga). Ninguno habla en pantalla. |

### 6.3 Arco narrativo

| Acto | Islas | Qué se descubre |
|---|---|---|
| **I. La última luz** | Delos, Naxos, Creta | Sobrevivir y partir. ¿Por qué se tragó Nyx el sol? |
| **II. El cielo robado** | Rodas, Lesbos, Ítaca | Las inscripciones revelan que los olímpicos llenaron el cielo de Nyx con sus propios trofeos y héroes (las constelaciones); la Noche se quedó sin estrellas propias. |
| **III. La devolución** | Thera, Ténaro | Tifón, enemigo de Zeus, muestra el otro lado de la guerra. En Ténaro, Fanós vence a Nyx, pero no la destruye: le **entrega su propia llama**, la última chispa de Hestia, para que vuelva a haber estrellas. Día y noche se alternan de nuevo. |

Idea central: **la luz no vence a la noche; le devuelve sus estrellas.** En el epílogo, Fanós, con el farol apagado, se
apoya en su ancla frente al mar de Delos. Sale el sol y en su farol prende una llama nueva, pequeña, del color del
alba. Esa noche brilla en el cielo una constelación que antes no existía: la suya.

### 6.4 Ejemplos de líneas del Oráculo

- *"Siete faros, siete noches. Una sola llama."*
- *"Del mar sale lo que el mar escondió."*
- *"La noche no odia la luz. Odia que la olviden."*
- *"Las Sirenas no mienten: cantan lo que quieres oír."*
- *"El gato no defiende la aldea. Pero la aldea defiende al gato."*
- *"Hefesto le dio el cuerpo. Hestia, la luz. Lo demás lo puso él."*

---

## 7. Biblia de arte

**"Diorama del Egeo", en una frase:** una maqueta mediterránea iluminada por el sol, hecha de formas simples y colores
limpios, donde la noche es azul y legible y la amenaza se reconoce por sus ojos.

### 7.1 Forma y proporciones

- **Low-poly facetado:** normales planas, color por vértice, **sin texturas** (la excepción son el degradado del cielo
  y el shader del agua). Todo se genera por código.
- **Escala:** 1 unidad = 1 m. Edificios a escala de maqueta (~0,8 de lo real, puertas y ventanas algo más grandes).
- **Personajes:** hoplitas y aldeanos de 1,7–1,9 m, cabeza grande por el yelmo o la capucha (~1/5 de la altura), hombros
  anchos, manos en mitón, pies simples. Fanós es más robusto y su farol, más grande (ver §7.2). Todo se tiene que leer
  a 20 m de cámara.
- **Orgánico contra construido:** rocas, árboles y terreno con 2–5 % de irregularidad en los vértices; la arquitectura
  es recta y limpia.
- **Sin contornos** (*outlines*): la separación la dan la luz, el color y la silueta.

| Presupuesto (triángulos) | Valor orientativo |
|---|---|
| Fanós | 1.200–2.000 (farol con cristales) |
| Hoplita / aldeano | 400–700 |
| Sombra / Ker / Arquero | 200–500 |
| Cíclope | 800–1.200 |
| Jefe (Hidra) | 2.000–3.500 |
| Casa / torre | 150–600 |
| Árbol | 80–200 (instanciado con *MultiMesh*) |
| Escena visible total (web) | < 150.000, < 300 llamadas de dibujo |

### 7.2 Fanós

| Parte | Diseño |
|---|---|
| **Silueta** | Robusto y de centro bajo (~1,8 m con el farol): torso ancho, piernas cortas y firmes, brazos gruesos. La cabeza-farol ocupa ~1/4 de la altura para que su luz sea lo más reconocible de la pantalla. |
| **Cabeza-farol** | Sala de linterna octogonal: cristales ámbar `#F2A83B`, montantes de bronce, cúpula de verdín `#4AA394` y anillo de remate dorado. Dentro, la llama (`#FFE3A3` en el centro, `#FFB25A` en los bordes): **es su rostro**. |
| **Cuerpo** | Bronce `#C08A3E` con acentos de verdín en juntas y bordes; tachuelas de oro, banda de meandro en el cinturón, un **sol** en el pecho y faldellín de placas de bronce. |
| **Detalles vivos** | **Respiraderos en la espalda** que sueltan bocanadas de vapor (en reposo, al esforzarse y en la Embestida). Una **faja azul de lona de vela** `#2E6FB0` ondea a un costado. |
| **Armas** | **Ancla antigua de bronce** al hombro derecho (en reposo, clavada en el suelo). **Lente de faro** con anillos de Fresnel como escudo en el brazo izquierdo; se enciende en el Destello. |
| **Expresión** | Solo con la llama y la postura: se aviva al atacar, tiembla al recibir daño, baja con la vida. En reposo mira a su alrededor y contempla el mar apoyado en el ancla. Al caer, la llama se apaga y él se desploma sobre el ancla. |
| **Luz** | De noche lleva una luz puntual ámbar (~6 m) que ilumina el suelo a su alrededor: el jugador siempre se encuentra. |
| **Contraste** | Los hoplitas aliados conservan el bronce clásico, el yelmo corintio y el penacho azul: Fanós tiene que leerse como único. |

### 7.3 La regla "sin caras"

**Ningún personaje muestra boca, sonrisa, dientes ni ojos humanos con pupila.** La identidad se lee por la silueta, el
color y el gesto.

| Quién | Solución |
|---|---|
| Fanós | Su cabeza es un farol: **la llama es su rostro**. Sin ojos ni boca. |
| Hoplitas | Yelmo corintio o calcídico, penacho azul. |
| Aldeanos | Capuchas, velos, sombreros de ala ancha (*pétaso*) o cántaros sobre la cabeza. Desde la cámara alta, la cabeza es una forma lisa. |
| Oráculo, Timonel, mercaderes | Velo o capucha completa. |
| Criaturas de Nyx | Capucha con un vacío oscuro dentro y **ojos almendrados y rasgados que brillan**. Sin boca. |
| Jefes | Fauces cerradas, sin labios ni dientes; brillo interior. |
| Animales | Gatos: dos ojos almendrados y orejas, sin boca. Cabras: hocico en bloque. Delfines: sin boca marcada. |
| Estatuas y frescos | Rostros erosionados y lisos; figuras de perfil en silueta. |

### 7.4 Paleta

| Uso | Color |
|---|---|
| Mármol / cal | `#F3EFE6` |
| Piedra caliza | `#E3D3B4` |
| Arena | `#EED9A8` |
| Terracota (tejados) | `#C8623E` |
| Azul Egeo (acentos, puertas, estandartes, penachos de hoplitas, faja de Fanós) | `#2E6FB0` |
| Mar somero → profundo | `#4FD6CF` → `#14507A` |
| Espuma | `#F6FBFA` |
| Hierba seca mediterránea | `#A3B860` / `#7E9A4A` / `#5E7A3A` |
| Olivo / ciprés | `#8C9C66` / `#3E5B3A` |
| Roca | `#B7A792` / `#8E7F6C` |
| Camino | `#CDAA7D` |
| Bronce | `#C08A3E` |
| Verdín (pátina de Fanós, cúpula del farol) | `#4AA394` |
| Cristal ámbar / llama de Fanós | `#F2A83B` / `#FFE3A3` |
| Flores (buganvilla / lavanda / amapola) | `#E05A9A` / `#9A7FD1` / `#E04A3A` |
| Oro (dracmas) | `#F2C14E` |
| Cuerpo de Nyx (índigo / violeta) | `#241B45` / `#3A2A66` |
| Brillo de Nyx (cian / carmesí Keres / violeta jefe) | `#7CF6FF` / `#FF5C7A` / `#B07CFF` |
| Estrellas / media luna / borde de Nyx | `#F4F1FF` / `#CBD5E6` / `#8C7BD8` |
| Fuego | `#FFB25A` |

**Reglas de uso**

- **60 / 30 / 10:** 60 % blancos cálidos y arena, 30 % verdes y azules, 10 % acentos (terracota, ámbar, oro, flores).
- **El cian brillante es de Nyx.** De noche, el agua somera se oscurece y se desatura para que el único cian intenso de
  la pantalla sean los ojos enemigos. La UI no usa cian, y el verdín de Fanós es un turquesa apagado que nunca brilla.
- **El ámbar vivo es de Fanós.** De noche, su llama es la luz cálida más intensa de la pantalla; antorchas y braseros
  son más tenues y anaranjados.
- **El oro es dinero y divinidad:** dracmas, dones, filetes de la UI y los detalles que un dios forjó en Fanós. Nada más
  brilla en dorado.

### 7.5 Iluminación por hora del día

| Momento | Sol (color · intensidad) | Ambiente | Cielo (cénit → horizonte) | Notas |
|---|---|---|---|---|
| **Amanecer** | `#FFC9A3` · 0,8 | `#9FB4D8` | `#7FA6D9` → `#F7C9A8` | Sombras largas; niebla rosada baja sobre el mar. Momento de los dones. |
| **Día** | `#FFF4E0` · 1,1 | `#B9D3EE` | `#4F9AE0` → `#CFE8F5` | Luz alta y limpia; sombras cortas; máximo color. |
| **Atardecer** | `#FFB070` · 0,9 | `#B58BC0` | `#5B6FB5` → `#F59C7A` | Dorado y rosado; se encienden las antorchas. Al llamar a la noche, la transición dura ~3 s. |
| **Noche** | Luna `#9DB6FF` · 0,35 | `#2A3A6B` | `#0B1433` → `#1E2E5C` | Azul profundo pero **legible**: charcos de luz cálida `#FFB25A` en antorchas, braseros y el farol de Fanós; ojos cian y estrellas de Nyx. |
| **Jefe** | Luna velada `#B9A6FF` · 0,3 | `#2B2250` | `#120B2E` → `#3A2A66` | Tinte violeta; relámpagos lejanos. |

Recursos: luz direccional + luz ambiental de cielo, niebla de distancia con el color del horizonte, *glow* suave en
fuegos, rayos y ojos (si el renderer de la web lo permite; si no, halos falsos con *billboards* aditivos). En la web
(renderer Compatibility) las sombras son caras: se usan **sombras de mancha** bajo personajes y oclusión ambiental
pintada en los colores por vértice; la sombra direccional real solo si el rendimiento lo permite.

### 7.6 Agua

El agua es la firma visual del juego y merece más cuidado que cualquier otro elemento.

- **Color por profundidad:** `#4FD6CF` (somero) → `#14507A` (profundo). La profundidad se **precalcula por vértice**
  (distancia a la costa) en vez de leer el *depth buffer*: más barato y compatible con WebGL 2.
- **Olas facetadas:** 2–3 ondas suaves en el shader de vértices; las normales planas crean **destellos de sol en
  escamas** que parpadean.
- **Espuma:** bandas `#F6FBFA` animadas que avanzan y retroceden en la orilla; anillos de espuma alrededor de rocas,
  muelles y personajes que entran al agua.
- **Transparencia en lo somero:** se ve la arena y las rocas del fondo, con cáusticas falsas (patrón animado).
- **Noche:** azul profundo, franja de reflejo de luna, reflejos cálidos de las antorchas del muelle.
- **Nyx:** donde van a desembarcar los enemigos, el agua se mancha de **tinta índigo** con chispas cian (el marcador).

### 7.7 Vegetación

| Planta | Forma | Color | Dónde |
|---|---|---|---|
| **Olivo** | Tronco retorcido, copa en 3–5 bloques facetados | `#8C9C66`, envés plateado al viento | Olivares, laderas |
| **Ciprés** | Cono alargado y vertical | `#3E5B3A` | Junto a templos y caminos; marca verticales en la composición |
| **Pino piñonero** | Copa en paraguas sobre tronco alto | `#5E7A3A` | Colinas; silueta icónica contra el atardecer |
| **Buganvilla** | Manchas sobre muros y pérgolas | `#E05A9A` | Sobre casas encaladas |
| **Lavanda** | Matas redondas bajas | `#9A7FD1` | Bordes de camino; con abejas y mariposas |
| **Amapolas** | Puntos sueltos | `#E04A3A` | Prados, entre la hierba seca |
| **Hierba seca** | Mechones de 3–5 triángulos | `#A3B860` / `#7E9A4A` / `#5E7A3A` | Todo el terreno, en tres tonos |

Todo se mece con el viento (shader de vértices: más movimiento cuanto más alto), con más fuerza al atardecer.

### 7.8 Arquitectura

- **Casas:** cubos encalados `#F3EFE6` con zócalo de caliza, puertas y contraventanas azul Egeo, tejados de terracota
  (a dos aguas, para que lean desde arriba), escaleras exteriores, ánforas y pérgolas con buganvilla.
- **Templos y faro:** columnas dóricas de 8–12 caras, capiteles simples, mármol con vetas de caliza. El faro es una torre
  escalonada con un gran brasero de bronce; su luz se ve desde toda la isla.
- **Defensas:** empalizada de troncos con punta → muralla de piedra ciclópea (bloques poligonales grandes). Torres con
  base de piedra, plataforma de madera y estandarte azul. Muelles de madera con barcas azules, rojas y ocres.
- **Identidad por isla:** Naxos (la Portara, gran puerta de mármol), Creta (columnas rojas minoicas, cuernos de
  consagración), Rodas (bronce y acrópolis blanca), Lesbos (piedra gris y pino), Ítaca (piedra rústica), Thera (pueblo
  blanco sobre roca volcánica negra y roja), Ténaro (piedra gris, cipreses y braseros).

### 7.9 Animales

Los animales **nunca sufren daño**: los enemigos los ignoran y ellos huyen de las peleas.

| Animal | Dónde | Comportamiento | Interacción |
|---|---|---|---|
| **Gatos** (5 pelajes) | Junto a las casas, al sol | Duermen, se estiran, siguen a Fanós un rato; de noche se esconden. | Mantener E: acariciar (ronroneo, pequeño destello dorado). |
| **Cabras** | Laderas | Pastan, saltan entre rocas, huyen si corres; cencerros. | Ninguna (atmósfera). |
| **Gaviotas** | Muelles y costa | Planean en círculos, se posan en postes. | Se espantan al pasar. |
| **Delfines** | Mar cercano, de día | Saltan en arcos en grupos de 2–4. | En el mar abierto, guían a islotes secretos. |
| **Luciérnagas** | Olivares, de noche | Puntos cálidos que flotan. | Contraste cálido frente al cian enemigo. |
| **Mariposas** | Flores, de día | Revolotean en la lavanda. | Atmósfera. |
| *Campaña:* pulpos, tortugas, flamencos, ballenas, búhos, ciervos, abejas | Según isla | Ver §4. | Modo foto y catálogo de la poza. |

### 7.10 Criaturas de Nyx: hechas de cielo nocturno

- **Materia:** cuerpo índigo profundo `#241B45` con **estrellas que titilan dentro** `#F4F1FF`, como si se mirara el cielo
  por una ventana (shader de estrellas en espacio de pantalla, barato y sin texturas importadas), y un **borde violeta
  suave** `#8C7BD8` que las separa del fondo oscuro.
- **Forma:** siluetas encapuchadas, elegantes y **flotantes**; los bajos son de humo y se deshilachan en jirones.
- **Rostro:** dentro de la capucha, un vacío oscuro con **ojos almendrados y rasgados que brillan**: cian `#7CF6FF`;
  carmesí-rosado `#FF5C7A` en las Keres; violeta `#B07CFF` en la Hidra. Un pequeño **adorno de media luna de plata**
  `#CBD5E6` (en la frente, el pecho o el arma) las marca como hijas de Nyx.
- **Aparición:** emergen del agua como si el cielo nocturno subiera a la superficie. **Muerte:** se deshacen en **motas
  de luz** que suben (estrellas que vuelven al cielo).

| Criatura | Silueta | Detalle que la identifica |
|---|---|---|
| **Sombra** | Figura encapuchada que flota, brazos largos de humo | La más simple: la media luna en la frente. |
| **Ker** | Pequeña, alada, rápida | Alas de jirones; ojos carmesí-rosados. |
| **Escudado** | Hoplita caído, en bronce oscuro | Visor que brilla; gran escudo con una media luna. |
| **Arquero de Nyx** | Encapuchado esbelto | Arco con forma de luna creciente. |
| **Cíclope de sombra** | Masa enorme y encorvada, con cuernos | Un solo ojo, grande y cian. |
| **Hidra de la Noche** | Tres cuellos de serpiente que salen del mar | Fauces cerradas, sin dientes; ojos violeta; constelaciones que recorren los cuellos. |

### 7.11 VFX

| Efecto | Descripción |
|---|---|
| Impacto | Chispas de bronce y oro, destello blanco del enemigo, pequeño anillo de polvo. |
| Ancla al suelo | Onda expansiva circular de polvo y chispas; grietas de luz que se desvanecen. |
| Destello | La lente se enciende: cono de luz blanca y ámbar, con los anillos de Fresnel proyectados en el suelo. |
| Embestida de vapor | Chorros blancos de los respiraderos y una estela de vapor que se disipa. |
| Haz del Faro | El farol arde y el haz barre 360° como el de un faro real; breve destello de pantalla y suelo quemado que se desvanece. |
| Fanós cae y se reenciende | La llama se apaga con una voluta de humo; al volver, una chispa vuela desde el Faro hasta su farol. |
| Muerte de Nyx | Motas de luz que suben y se apagan como estrellas. |
| Dracmas | Monedas que vuelan de los edificios al contador al amanecer. |
| Construcción | El edificio "crece" desde el suelo con polvo y un tintineo; se ve antes como fantasma translúcido. |
| Ambiente | Polvo en rayos de sol, hojas de olivo al viento, chispas de antorchas, niebla baja sobre el mar al amanecer. |

### 7.12 UI

**Principio:** la UI es parte del diorama, no un tablero encima. Mínima, siempre legible y coherente con el mundo.

- **Colores:** texto marfil `#F7F1E3`, acento oro `#E9C46A`, paneles oscuros translúcidos (azul noche al ~70 %) con un
  filete dorado fino; el meandro griego como separador.
- **Tipografías:** **Cinzel** (títulos, números, etiquetas) y **EB Garamond** (textos y líneas del Oráculo).
- **HUD:** arriba a la izquierda, vida (barra fina marfil; la llama del farol también la muestra) y Llama (arco ámbar
  alrededor de un icono de llama); arriba a la derecha, dracmas (moneda + número) y noche actual (`III / VII`); abajo al centro, vida del faro solo de noche o si
  recibe daño.
- **En el mundo:** costos flotando sobre los puntos de construcción, el círculo dorado de "mantener E" que se llena,
  marcadores de desembarco en el mar, indicadores en el borde de la pantalla cuando atacan algo fuera de cámara.
- **Movimiento:** fundidos de 150–250 ms; nada rebota ni gira. Iconos de línea dorada, sin degradados.
- **Al caer Fanós:** "La llama de Fanós se ha apagado · El Faro volverá a encenderla", en EB Garamond, centrado, con
  un fundido lento.
- **Dones:** tres cartas verticales con el símbolo del dios (rayo, tridente, lechuza…), nombre en Cinzel y efecto en una
  línea.

### 7.13 Cámara

- Perspectiva elevada de 3/4, FOV ~35–40°, inclinación ~50°, distancia ~18–22 m. **Sin rotación libre**: el diorama
  siempre se ve desde el sur (el mar al fondo y a los lados).
- Seguimiento suave con adelanto en la dirección de movimiento; se aleja un poco de noche y bastante con los jefes.
- Profundidad de campo tipo *tilt-shift* (bordes superior e inferior desenfocados) como opción "Diorama", si el
  rendimiento en la web lo permite.
- **Modo foto** (versión completa): cámara libre limitada, hora del día ajustable, UI oculta.

---

## 8. Audio

| Capa | Contenido |
|---|---|
| **Instrumentos** | Lira y cítara pulsadas, aulós (doble caña), tímpano (pandero), címbalos y crótalos, coro suave sin palabras; *salpinx* (trompeta griega) solo para jefes. |
| **Modos** | **Dórico** de día (cálido, sereno) · **frigio** de noche (tensión) · mixolidio para el amanecer y la victoria. |
| **Día** | Lira sola, tempo lento; capas de ambiente: mar, viento en los olivos, cigarras, cabras a lo lejos. |
| **Llamada a la noche** | Un cuerno grave y un redoble de tímpano: 3 s que separan la calma de la tensión. |
| **Noche** | Tímpano + aulós + coro en frigio. **Música por capas**: se suman instrumentos según cuántos enemigos quedan y cuántas playas están activas. Ambiente: grillos, crepitar del fuego, olas más fuertes. |
| **Amanecer** | Acorde luminoso, gaviotas, el tintineo de las dracmas. Cada dios tiene un motivo de 2–3 notas al elegir su don. |
| **Jefes** | Tema propio con *salpinx* y coro grave; cambia de capa en cada fase. |
| **Mar abierto** | Tema de navegación amplio (lira + coro + cuerdas de viento), olas, crujir de la madera, delfines. |

**Principios de SFX:** sonidos redondos y filtrados, nada estridente. Cada golpe tiene capa de impacto sordo y capa de
bronce. Fanós suena a bronce y fuego: zumbido suave del farol, siseo de vapor (en reposo y en la Embestida), campana
grave en el ancla al suelo y un coro ascendente en el Haz del Faro. Los enemigos de Nyx suenan a viento invertido y
cristal, y al morir, a campanillas que se apagan. Prioridad de mezcla: Fanós > jefe > faro > resto. Audio
posicional para playas y torres.

**Técnica:** música en *stems* sincronizados (los recursos de música interactiva de Godot 4.x), OGG comprimido, límite de
voces simultáneas. En la web, el audio arranca después del primer clic o tecla (política de autoplay de los navegadores).

---

## 9. Alcance del MVP actual

### 9.1 Objetivo

Una demo **web** de **25–35 minutos** que demuestre los cuatro pilares en una sola isla. Prioridad absoluta: que sea
**bonita y visualmente coherente** en cada captura; después, que el combate se sienta bien; después, la variedad.

### 9.2 Qué incluye

| Área | Contenido |
|---|---|
| **Isla** | Delos (~140 × 110 m): faro en la colina central, caminos de tierra, 4 playas (S, E, O, N), aldea inicial, agua con shader propio, vegetación mediterránea. |
| **Héroe** | Fanós, el autómata del faro: vida 130, combo de ancla (13/13/24), Destello, Embestida de vapor, medidor de Llama y Haz del Faro; el Faro lo reenciende al caer; animaciones de reposo. |
| **Edificios** | Faro (3 niveles), Casa, Olivar, Muelle (2 niveles cada uno), Torre de arqueros (3), Muralla (2), Cuartel (2). |
| **Enemigos** | Sombra, Ker, Escudado, Arquero de Nyx, Cíclope de sombra y la **Hidra de la Noche**. |
| **Dones** | Los 10 dones de §3.6 (1 de 3 al amanecer). |
| **Ciclo** | Día sin límite, llamada a la noche, marcadores de desembarco, oleadas, ingresos al amanecer, reconstrucción gratis. |
| **Vida** | Gatos acariciables, cabras, gaviotas, delfines, luciérnagas, mariposas; viento y ciclo de luz. |
| **UI** | Menú principal, HUD mínimo, cartas de dones, pausa (controles y volumen), victoria y derrota con resumen de la partida. |
| **Controles** | Teclado y mouse, y control (gamepad), según `BRIEF.md`. |
| **Audio** | Música día/noche y de jefe, SFX de combate y construcción, ambiente. |
| **Plataforma** | Web (renderer Compatibility, WebGL 2) y escritorio. |

### 9.3 Las 7 noches de Delos

| Noche | Playas activas | Composición (orientativa) | Qué enseña |
|---|---|---|---|
| 1 | S | Sombras | Pelear y proteger el faro. |
| 2 | S | Sombras + Keres | Los voladores ignoran murallas: torres. |
| 3 | S, E | + Escudados | Flechas a la mitad: Destello y hoplitas. |
| 4 | S, E | + Arqueros de Nyx | Proteger torres; flanquear. |
| 5 | S, E, O | + 1 Cíclope | Defender edificios; aturdir al grande. |
| 6 | S, E, O, N | Todo, 2 Cíclopes | Pico de presión: elegir frente. |
| 7 | S, E, O, N | **Hidra** (sur) + oleadas de apoyo | Jefe. |

### 9.4 Fuera del alcance del MVP

Campaña y otras islas · navegación por mar abierto · Kleos, armería, reliquias y constelaciones · armas distintas del
ancla · llamas de color y mejoras del farol · ramas de mejora, niveles de dones, dones dobles y pactos · selector de dificultad (se ajusta una sola,
"Hoplita") · unidades nuevas · modo foto · vasijas narrativas (como mucho, unas pocas líneas del Oráculo) · guardado a
mitad de partida · localización (solo español) · voces · multijugador · logros.

### 9.5 Definición de "terminado"

- Se juega de principio a fin en el navegador sin errores en 20 partidas de prueba.
- Cualquier captura sin UI se ve bonita y coherente con la paleta; **ningún personaje tiene cara**.
- Un jugador nuevo vence a la Hidra en 1–2 intentos en dificultad normal.

---

## 10. Producción

### 10.1 Hitos

Estimaciones para **un desarrollador solo con apoyo puntual** (música/audio y pruebas). Duraciones acumulativas.

| Hito | Duración | Contenido | Criterio de salida |
|---|---|---|---|
| **MVP** (en curso) | 4–6 semanas | Delos completa (§9). | Demo web jugable de principio a fin; métricas de §10.3. |
| **Vertical slice** | +8–10 semanas | Delos pulida, primera travesía con 2 islotes, Naxos completa (mareas, Viñedo, Ménade, piratas, Alóadas), Xiphos doble, armería básica, guardado. | Una porción con calidad final, lista para mostrar (itch.io, festivales). |
| **Alpha** | +5–6 meses | Las 8 islas jugables (arte provisional en las últimas), 8 jefes en bruto, navegación con islotes y eventos, 4 armas, reliquias, constelaciones. | La campaña se completa de principio a fin. |
| **Beta** | +3 meses | Contenido final, balance, audio final, vasijas narrativas, inglés, accesibilidad, rendimiento web. | Sin errores bloqueantes; pruebas con 20–50 jugadores externos. |
| **1.0** | +1–2 meses | Pulido, modos (Noche eterna, Vigilia, Oráculo del día), páginas de tienda. | Lanzamiento en web, itch.io y Steam. |

**Total:** ~12–16 meses desde hoy hasta la 1.0.

### 10.2 Riesgos y mitigaciones

| Riesgo | Prob. | Impacto | Mitigación |
|---|---|---|---|
| Rendimiento en la web (WebGL 2) | Alta | Alto | Presupuestos de §7.1, *MultiMesh*, sombras de mancha, LOD de animación; medir cada semana en una laptop con gráfica integrada. |
| Alcance de 8 islas para un equipo mínimo | Alta | Alto | Un gimmick por isla, sistemas reutilizables, generador de islas paramétrico. La campaña funciona también con 6 islas si hay que recortar. |
| Legibilidad de noche | Media | Alto | Regla del cian, contraluz violeta, pruebas con el brillo de pantalla bajo. |
| Combate sin peso | Media | Alto | *Hit-stop*, retroceso y sonido en capas desde el primer día; probar con y sin cada elemento. |
| Balance de la economía | Media | Medio | Valores en recursos de datos (no en el código), registro local de dracmas por noche, hoja de cálculo de curvas. |
| Rutas con muchas unidades | Media | Medio | Rutas precalculadas por playa (campo de flujo simple); recalcular solo al construir o destruir murallas. |
| Arte procedural repetitivo | Media | Medio | Variación por semilla (color, escala, rotación) y decoración a mano en puntos clave. |
| Audio en el navegador | Baja | Medio | Pantalla de inicio con clic, pocos buses, OGG comprimido. |
| Desgaste del desarrollador solo | Media | Alto | Hitos cortos y jugables; recortar antes que retrasar; demo pública temprana para recibir comentarios. |

### 10.3 Métricas de éxito de la demo

| Métrica | Objetivo |
|---|---|
| Jugadores que llegan a la noche 3 | ≥ 80 % |
| Jugadores que vencen a la Hidra | ≥ 40–50 % |
| Duración media de la sesión | 25–35 min |
| Jugadores que acarician al menos un gato | ≥ 70 % |
| "¿Es bonito?" (1–5) | ≥ 4,5 |
| "¿Jugarías la versión completa?" (1–5) | ≥ 4 |
| FPS en el navegador (laptop media / gráfica integrada) | ≥ 60 / ≥ 30 |
| Carga inicial | < 15 s |
| Elección de dones | Ningún dios por encima del 25 % ni por debajo del 5 % de las elecciones |
| Errores bloqueantes | 0 en 20 partidas |
