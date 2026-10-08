# PHAROS — La última luz · Brief del director

> Documento corto de referencia para todo el equipo (código, arte, audio, diseño). El GDD completo está en `GDD.md`.

## Una frase

**Thronefall en una isla griega**: de día levantas y amplías la aldea alrededor del faro; de noche los hijos de Nyx
salen del mar oscuro y tú peleas en primera línea, con un ancla de bronce y una lente de faro, junto a tus torres y tus
hoplitas.

## Fantasía

Nyx, la Noche primordial, se ha tragado el Egeo. Solo queda una luz: el **Faro de Delos**. Eres **Fanós, el autómata
del faro** (su nombre significa "farol"): un guardián de bronce, robusto y paciente, que Hefesto forjó (como a Talos)
para cuidar el Faro. Cuando cayó la noche, Hestia guardó la última chispa de su llama eterna dentro de su cabeza, que
es un farol. Cada noche las criaturas de Nyx emergen del agua para apagar el Faro. Cada amanecer, los dioses del Olimpo
te ofrecen un don.

## El héroe: Fanós

- **Cabeza-farol:** sala de linterna octogonal con cristales ámbar, montantes de bronce, cúpula de verdín y anillo de
  remate dorado. **La llama es su rostro** (no tiene cara): parpadea y baja de intensidad a medida que pierde vida.
- **Cuerpo:** bronce robusto con acentos de verdín (pátina turquesa) y tachuelas de oro: banda de meandro, un sol en el
  pecho, faldellín de placas de bronce. **Respiraderos en la espalda que sueltan vapor.** Una **faja azul de lona de
  vela** ondea a su costado.
- **Armas:** un **ancla antigua de bronce** al hombro derecho y una **lente de faro** (anillos de Fresnel) como escudo en
  el brazo izquierdo.
- **Personalidad en reposo:** mira a su alrededor, se apoya en el ancla clavada en el suelo y contempla el mar. De noche,
  su farol ilumina el suelo a su alrededor.
- **Al caer:** su llama se apaga, se desploma sobre el ancla y, tras unos segundos, el Faro lo vuelve a encender
  ("La llama de Fanós se ha apagado · El Faro volverá a encenderla").
- **Contraste buscado:** los hoplitas aliados conservan el aspecto clásico de bronce, yelmo corintio y penacho azul.

| Acción | Entrada | Valores de referencia (orientativos) |
|---|---|---|
| Combo de ancla | J / clic izq. | Dos barridos amplios + golpe de ancla desde arriba con onda expansiva: 13 / 13 / 24 |
| **Destello** | K / clic der. | La lente se enciende: cono que ciega, aturde 1,4 s y empuja; 10 de daño; enfriamiento 4 s |
| **Embestida de vapor** | Espacio | Impulso a vapor con invulnerabilidad |
| **Haz del Faro** | Q | El farol arde y Fanós gira una vez: el haz barre 360° (10 m), quema y aturde; 70 de daño |
| Medidor de **Llama** | — | Se llena al infligir daño; activa el Haz del Faro |

Vida 130 · velocidad 6,0.

## Pilares

1. **Bello y legible.** Diorama low-poly mediterráneo, sombreado plano, paleta luminosa, agua preciosa. Siluetas
   claras. **Ningún personaje tiene cara**: la cabeza de Fanós es un farol, los hoplitas llevan yelmo, los aldeanos
   capucha y las criaturas de Nyx solo tienen ojos que brillan. Nada de bocas ni sonrisas.
2. **Simple de aprender.** Moverse, atacar con el ancla, Destello, Embestida de vapor, Haz del Faro y "mantener para
   construir".
3. **Combate con peso.** Combo de ancla que termina en un golpe al suelo, Destello que ciega y empuja, Embestida de vapor
   con invulnerabilidad, *hit-stop*, retroceso, temblor de cámara y el Haz del Faro.
4. **Un mundo vivo.** Gatos al sol junto a las casas (se pueden acariciar), cabras en las colinas, gaviotas,
   delfines que saltan, luciérnagas de noche, ciclo día/noche, viento.

## Bucle

**Día** (sin límite de tiempo): construir / mejorar con dracmas en puntos fijos, explorar, acariciar gatos.
→ Mantener *Interactuar* en el faro para **llamar a la noche** (antes se marcan las playas por donde vendrán).
→ **Noche**: oleadas desde las playas marcadas. Torres disparan, hoplitas defienden, tú peleas. Si cae el faro, pierdes.
→ **Amanecer**: ingresos de las casas, olivares y muelles que sigan en pie; los edificios destruidos se reconstruyen
gratis; eliges **1 de 3 dones divinos**.
→ 7 noches; la 7ª es la del jefe: **la Hidra de la Noche**, que sale del mar.

## Contenido del MVP

- **Isla**: Delos (una isla, ~140×110 m), 4 playas de desembarco (sur, este, oeste, norte), caminos de tierra hacia el
  faro en el centro, sobre una colina.
- **Edificios**: Faro (núcleo; mejorarlo amplía el radio de construcción), Casa, Olivar, Muelle de pesca (economía),
  Torre de arqueros (3 niveles), Muralla (empalizada → piedra), Cuartel de hoplitas (2–3 soldados de guardia).
- **Enemigos (la prole de Nyx)**: Sombra (cuerpo a cuerpo básico), Ker (rápida, voladora, ignora murallas),
  Escudado (hoplita caído, resistente a flechas), Arquero de Nyx (a distancia), Cíclope de sombra (gran destructor de
  edificios), **Hidra de la Noche** (jefe, tres cuellos de serpiente).
- **Dones** (uno de tres al amanecer): Zeus, Poseidón, Atenea, Artemisa, Apolo, Hermes, Ares, Hefesto, Deméter,
  Hestia; cada uno es un modificador simple y claro. Zeus potencia el Haz del Faro (carga un 35 % más rápida, +50 % de
  daño); Ares, el ancla y la lente; Hermes, la velocidad y la Embestida de vapor.
- **Controles**: WASD/flechas mover · J o clic izq. atacar · K o clic der. Destello · Espacio Embestida de vapor
  · Q Haz del Faro · mantener E interactuar/construir · Esc pausa. Mando: stick, X, Y, B, RB, mantener A.

## Dirección de arte — "Diorama del Egeo"

Low-poly facetado (normales planas), colores por vértice, sin texturas. Luz de sol cálida + ambiente de cielo frío,
sombras suaves. Atardecer dorado y rosado. Noche azul profunda y legible, con charcos de luz cálida de antorchas, el
farol de Fanós y los ojos cian de las criaturas de Nyx.

**Las criaturas de Nyx están hechas de cielo nocturno:** cuerpo índigo profundo con estrellas que titilan dentro (como
una ventana abierta al cielo), un borde violeta suave, bajos de humo que se deshilachan en jirones, siluetas
encapuchadas, elegantes y flotantes, ojos almendrados y rasgados que brillan en un vacío oscuro (cian; carmesí-rosado
en las Keres; violeta en la Hidra) y un pequeño adorno de media luna de plata. Al morir se deshacen en motas de luz.

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

**UI**: minimalista. Texto marfil `#F7F1E3`, oro `#E9C46A` como acento, paneles oscuros translúcidos con filete
dorado fino. Tipografías: **Cinzel** (títulos, números, etiquetas) y **EB Garamond** (textos).

## Dirección de audio

Instrumentos que evocan Grecia antigua: lira pulsada, aulós (doble caña), tímpano (pandero), címbalos, coros
suaves. Modos dórico (día, cálido) y frigio (noche, tensión). Ambiente: mar, viento, cigarras de día, grillos de
noche, crepitar del fuego. Nada estridente: sonidos redondos y filtrados.
