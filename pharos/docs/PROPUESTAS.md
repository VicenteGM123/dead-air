# Propuestas de juego a partir de las ideas del cliente

> **Para qué sirve este documento:** el cliente pidió: *"basado en las otras ideas, propón también juegos con lo que
> dije"*. Aquí hay cinco propuestas originales, **simples de construir pero bonitas**, que salen de sus tres ideas
> (fútbol anime con estética Octopath, un *tower defense* tipo Thronefall con gatos y una Grecia mítica de mundo
> abierto). Todas respetan sus condiciones: belleza y coherencia visual ante todo, formas simples, UI mínima y
> **ninguna cara fea** (ni bocas ni sonrisas).
> El MVP elegido es **PHAROS — La última luz** (ver `GDD.md`). Al final hay una comparación y la razón de esa elección.

| # | Propuesta | Idea de origen | Género |
|---|---|---|---|
| 1 | **Ocho Dorsales** | Fútbol anime + Octopath (HD-2D) | RPG de fútbol con duelos tácticos |
| 2 | **Bastet: la noche de Apep** | TD tipo Thronefall con gatos | *Tower defense* de acción |
| 3 | **Thalassa: el mar color de vino** | Grecia de mundo abierto tipo God of War | Acción y aventura en islas |
| 4 | **Episkyros: la Copa del Olimpo** | Fusión: fútbol anime + mitología griega | Fútbol arcade 3 contra 3 |
| 5 | **Siete Vidas** | Fusión: gatos + diorama + historia antigua | Aventura tranquila de exploración |

---

## 1. OCHO DORSALES

> **Pitch:** un RPG de fútbol en dioramas HD-2D: ocho futbolistas de ocho pueblos y ocho caminos que terminan en la
> misma final.

**Por qué es divertido**

- Los partidos duran **4–6 minutos** y solo se juegan los momentos decisivos: no hay 90 minutos de relleno.
- Toma el sistema de combate de Octopath y lo convierte en fútbol: cada rival tiene **escudos** (sus debilidades: regate
  corto, pase alto, tiro con efecto, cabezazo…). Si los rompes, el rival queda **quebrado** y se abre la jugada. El
  **Ímpetu** se acumula en cada duelo y se gasta (1–3 puntos) para potenciar una acción, como el *Boost* de Octopath.
- Los tiros especiales llegan con un *cut-in* anime: líneas de velocidad, luz dramática y un golpe de música.
- Las ocho historias se cruzan: el rival de un capítulo es el compañero de otro.

**Bucle principal**

1. **Pueblo (diorama):** explorar, reclutar compañeros, entrenar técnicas, espiar rivales (revela sus escudos).
2. **Partido (fútbol 5, cinco contra cinco):** se mueve al jugador que lleva el balón en tiempo real; al encontrarse con
   un defensor, la acción se congela en un **duelo** por turnos (elegir técnica, gastar Ímpetu); los compañeros los maneja
   la IA con órdenes simples (presionar, replegarse, apoyar).
3. **Recompensa:** experiencia, técnicas nuevas, una pieza de la historia; siguiente pueblo.

**Dirección de arte**

- **HD-2D:** personajes en *pixel art* (~48–64 px de alto) sobre dioramas 3D low-poly con desenfoque *tilt-shift*,
  *bloom* y luz dramática (tarde dorada, estadio de noche con focos, lluvia).
- **Cómo hacerlo sin dibujar a mano cada sprite:** los personajes son modelos 3D low-poly simples **renderizados a baja
  resolución** (viewport de 64 px, filtro *nearest*, paleta reducida). Se ven como *pixel art*, se animan como 3D y
  salen del mismo flujo procedural de PHAROS. El *tilt-shift* se hace con un shader propio en pantalla, porque el
  renderer web no trae todos los efectos de posproceso.
- **Sin caras:** a ese tamaño la cara es apenas un par de píxeles, y se resuelve con el recurso anime del **flequillo que
  tapa los ojos** y la cara en sombra. En los *cut-ins*, los personajes **se ven de espaldas o a contraluz**: botines,
  balón, pelo al viento y **el dorsal brillando**. Cada protagonista se reconoce por su espalda, y de ahí sale el título.

**Los ocho protagonistas**

| Dorsal | Rol | Pueblo / bioma | Acción de camino | Técnica especial |
|---|---|---|---|---|
| 1 | Portera | Puerto pesquero | Atajar: desafía a duelo de penales | "Muralla de mareas" |
| 4 | Defensa central | Pueblo minero | Intimidar: aparta a quien bloquea el camino | "Ancla de hierro" |
| 6 | Mediocampista defensivo | Monasterio en la montaña | Observar: revela escudos | "Paso del grulla" |
| 8 | Mediocampista | Ciudad de canales | Negociar: compra y recluta | "Pase de seda" |
| 7 | Extremo | Desierto de dunas | Correr: atajos por los tejados | "Espejismo" |
| 10 | Armador | Capital | Inspirar: sube la moral del equipo | "Corona" |
| 9 | Delantero | Aldea de arrozales | Rematar: rompe obstáculos con el balón | "Tormenta de verano" |
| 11 | Novato | Isla volcánica | Imitar: copia una técnica rival | "Brasa" |

**Estructura de ~8 h**

| Bloque | Contenido | Duración |
|---|---|---|
| Ocho capítulos | Uno por protagonista: pueblo, 2 partidos y un partido final de capítulo | 8 × ~50 min ≈ 6 h 40 min |
| Cruces | Partidos entre protagonistas cuando sus caminos se encuentran | ~40 min |
| Copa de las Ocho Ciudades | Final con el equipo que el jugador arme con los ocho | ~40 min |

**MVP mínimo (3–4 semanas)**

- Un protagonista (el 9), un pueblo-diorama pequeño y **un partido** 5 contra 5 contra un equipo.
- Sistema de duelos con escudos, quiebre e Ímpetu; dos técnicas especiales con *cut-in*.
- Flujo de "sprites desde 3D", *tilt-shift* y *bloom* funcionando en la web.

**Riesgos**

| Riesgo | Mitigación |
|---|---|
| Producir *pixel art* animado es caro | Render de modelos 3D a baja resolución; 4 direcciones y pocos cuadros. |
| La IA de fútbol es difícil | Fútbol 5 en cancha chica; la IA solo decide "presionar o replegarse"; los duelos resuelven lo importante. |
| Que mezclar tiempo real y turnos se sienta cortado | Duelos de 2–4 s, sin menús profundos: tres botones, como un QTE táctico. |
| Posproceso caro en la web | Desenfoque y *bloom* propios a media resolución; opción para desactivarlos. |

**El giro creativo:** el sistema de quiebre e Ímpetu de Octopath, convertido en fútbol, y **héroes que se reconocen
por la espalda**: el dorsal como identidad y la solución elegante al problema de las caras en el anime.

---

## 2. BASTET: LA NOCHE DE APEP

> **Pitch:** eres Mau, el gran gato de Ra. Cada noche la serpiente Apep sale del Nilo para tragarse el sol, y los gatos
> de tu aldea la esperan en los tejados… si tienen ganas.

**Por qué es divertido**

- **No construyes torres: seduces gatos.** Colocas **caprichos** (una caja, un cojín al sol, una cesta de pescado, un
  ovillo, una lámpara) y cada uno atrae a un tipo de gato, que defiende ese lugar a su manera.
- Los gatos siguen **reglas, no azar**: cada uno va al capricho más atractivo dentro de su radio, y un icono sobre su
  cabeza muestra su intención. El comportamiento es emergente pero se puede leer.
- El héroe es un gato: zarpazos en combo, **salto desde lo alto** sobre los enemigos, **bufido** que aturde en área. Las
  **9 vidas** son tus reintentos de la isla.
- Las ratas son presa natural: los gatos les hacen el doble de daño. Ver a seis gatos caer desde un tejado sobre un
  enjambre de ratas es puro placer.

**Bucle principal**

1. **Día:** los gatos duermen (¡16 horas!). Recoges pescado (la moneda) de las barcas, colocas caprichos en puntos fijos
   y acicalas gatos para subir su **cariño** (su nivel).
2. **Atardecer:** los gatos despiertan, se estiran y van a sus caprichos.
3. **Noche:** la prole de Apep llega desde el río y el desierto. Los gatos cazan; tú peleas donde haga falta.
4. **Amanecer:** una diosa (Bastet, Sejmet, Isis, Hathor…) ofrece una bendición.

| Gato | Capricho que lo atrae | Rol | Comportamiento |
|---|---|---|---|
| **De tejado** | Cojín al sol sobre un tejado | Emboscada | Salta sobre lo que pasa debajo. |
| **De caja** | Caja ("si cabe, entra") | Trampa | Atrapa y aturde al primero que se acerca. |
| **Gordo** | Cesta de pescado | Bloqueo | Duerme en medio del camino; hay que rodearlo o golpearlo mucho. |
| **Gatito** | Ovillo | Cazador rápido | Persigue ratas por toda la aldea. |
| **Del templo** | Lámpara de aceite | Aura | Debilita a la prole de Apep cerca de la luz. |

Los gatos **nunca mueren**: si los derrotan, huyen ofendidos y vuelven al amanecer. Hay tensión, pero nunca tristeza.

**Dirección de arte**

- Egipto low-poly y luminoso: adobe `#D9B98A`, caliza, azul lapislázuli `#1F4E9C`, turquesa de fayenza `#3FB8AF`,
  verde papiro `#7FA35B` y oro. Palmeras, obeliscos, casas cúbicas con toldos de lino y el Nilo como espejo.
- **La imagen insignia:** de noche, **los ojos de los gatos brillan dorados** (como en la vida real) y un tejado lleno de
  ojos es precioso y además se lee perfecto; la prole de Apep brilla en carmesí para contrastar.
- Gatos de formas simples (cápsulas y cuñas), cinco pelajes, **solo ojos y orejas**, sin boca. Los aldeanos se ven de
  día como siluetas tras cortinas de lino o con tocados que cubren la cabeza.

**Estructura de ~8 h** (8 capítulos de ~60 min, remontando el Nilo)

| # | Lugar | Gimmick | Jefe |
|---|---|---|---|
| 1 | Bubastis, la ciudad de Bastet | Tutorial | Cobra gigante |
| 2 | Marismas del Delta | Crecidas: el agua sube y cambia los caminos | Cocodrilo de sombra |
| 3 | Menfis | Mercado: las ratas roban pescado | El rey de las ratas |
| 4 | Giza | Tormentas de arena (menos visión) | Escarabajo colosal |
| 5 | Abidos | Tumbas: enemigos que salen del suelo | Ammit, la devoradora |
| 6 | Tebas (Karnak) | Bosque de columnas: emboscadas | Escorpión rey |
| 7 | Cataratas de Asuán | Rápidos: corrientes que empujan | Las hijas de Apep |
| 8 | La barca de Ra en el Duat | **Base en movimiento:** la barca del sol avanza por el río de la noche | Apep |

**MVP mínimo (2–3 semanas, reutilizando el núcleo de PHAROS)**

- Bubastis, Mau con 3 movimientos, 3 gatos con sus caprichos, 3 enemigos (ratas, cobras, escorpiones), 5 noches y la
  Cobra gigante. El ciclo día/noche, las oleadas y los puntos de construcción salen tal cual de PHAROS.

**Riesgos**

| Riesgo | Mitigación |
|---|---|
| Que los gatos se sientan aleatorios | Reglas deterministas e iconos de intención; vista previa al colocar un capricho. |
| Muchas unidades pequeñas | Siluetas claras, ojos brillantes y pocos tipos. |
| Tono (ternura contra amenaza) | Los gatos no mueren; la amenaza es Apep, nunca el gato. |

**El giro creativo:** un *tower defense* donde las torres tienen voluntad propia: no se ordena, se seduce. Además, las
9 vidas como sistema de reintentos y un final que es un *tower defense* en movimiento sobre la barca del sol.
*Variante griega:* el mismo juego en un puerto de las Cícladas, con Hestia en lugar de Bastet y gaviotas ladronas en
lugar de ratas, reutilizando todo el arte de PHAROS.

---

## 3. THALASSA: EL MAR COLOR DE VINO

> **Pitch:** un mundo abierto pequeño y precioso: islas griegas, un barco, templos y monstruos míticos, con un combate
> que pesa. Cada monstruo vencido le devuelve el color al mar.

**Por qué es divertido**

- **Combate al estilo God of War, a escala indie:** una **lanza que se arroja y vuelve a la mano**, escudo para parar y
  empujar, esquiva, golpes de gracia. Pocos enemigos por pelea, pero con patrones claros y golpes que se sienten.
- **Exploración densa, no grande:** algo cada 30–60 s: una cala para bucear, una cabra en un risco, una ofrenda, una
  vista. Las islas son pequeñas y están llenas.
- **Navegar y bucear:** barco de vela entre islas, con delfines, ballenas y tormentas; calas transparentes con pulpos y
  ánforas hundidas.
- **El mar es la barra de progreso:** Poseidón está herido y el mar empieza **gris y apagado**. Cada templo liberado
  devuelve el turquesa a su región. La recompensa se ve desde cualquier lugar.

**Bucle principal:** navegar → desembarcar → explorar y encontrar el templo → combates y puzles del templo → jefe → el
mar recupera su color → mejorar armas con **icor** → siguiente isla. Habilidades que abren el mundo, al estilo de un
metroidvania ligero: sandalias de Hermes (planear), caracola de Tritón (aguantar bajo el agua), égida (reflejar luz).

**Dirección de arte**

- La misma biblia "Diorama del Egeo" de PHAROS, con **cámara en tercera persona alta** (~8–10 m, no al hombro): el
  low-poly se ve como una maqueta cuidada, nunca "pobre" de cerca.
- El agua es la protagonista: el shader de PHAROS más una capa submarina (niebla turquesa, cáusticas, rayos de luz).
- **Monstruos sin caras:** centauros con yelmo, jabalí de Calidón con hocico en cuña, aves de bronce del Estínfalo, y la
  **Gorgona**, que nunca se ve de frente: mirarla petrifica, así que se pelea **mirando su reflejo en el escudo**, como
  Perseo. La regla de las caras se convierte en una mecánica.

**Estructura de ~8 h**

| Isla | Exploración | Templo y jefe | Duración |
|---|---|---|---|
| Isla del Olivo | Tutorial: aldea, cuevas | Jabalí de Calidón | 40 min |
| Isla de los Pinos | Bosque de Pan, ninfas, sendas ocultas | Rey centauro | 70 min |
| Isla de Bronce | Forjas de Hefesto, mecanismos | Talos | 70 min |
| Islas de los Acantilados | Planear entre riscos | Aves del Estínfalo | 70 min |
| Isla de la Gorgona | Estatuas petrificadas, reflejos | Medusa (velada) | 75 min |
| Ciudad hundida | Buceo y mareas | Escila | 75 min |
| Palacio de Poseidón | Bajo el mar | Ceto, madre de los monstruos marinos | 50 min |
| Navegación libre | Islotes, eventos, animales | — | ~30 min |

**MVP mínimo (4 semanas, sobre la tecnología de PHAROS)**

- Una isla de ~300 × 300 m, el barco, un templo de ~10 min y el Jabalí de Calidón; lanza arrojadiza, 3 enemigos y vida
  animal. Reutiliza el agua, la generación de islas, los animales, el combate y los enemigos de PHAROS. De hecho, la
  travesía por mar abierto del GDD de PHAROS (§4.3) ya es el prototipo de Thalassa.

**Riesgos**

| Riesgo | Mitigación |
|---|---|
| "Mundo abierto" es el riesgo número uno de un indie | Islas pequeñas y densas; una región cargada a la vez; nada de mapas vacíos. |
| Combate profundo exige mucha animación | Animación procedural, pocos enemigos con patrones muy claros. |
| Rendimiento web con terreno grande | Terreno por bloques con LOD, niebla de distancia, *MultiMesh* para vegetación. |

**El giro creativo:** el color del mar como barra de progreso, una lanza que vuelve a la mano y una Gorgona a la que se
vence sin mirarla.

---

## 4. EPISKYROS: LA COPA DEL OLIMPO

> **Pitch:** fútbol mitológico tres contra tres en estadios-diorama de la Grecia antigua: héroes con yelmo, poderes de
> los dioses y tiros especiales con *cut-in* anime.

El *episkyros* existió: era un juego de pelota por equipos de la antigua Grecia. Esta propuesta **fusiona el fútbol anime
con la mitología** que el cliente ama, y resuelve el problema de las caras por diseño: todos juegan con yelmo.

**Por qué es divertido**

- **Arcade rápido:** partidos de 3 minutos, tres contra tres, sin fuera de juego ni reglas complicadas. Pase, tiro,
  barrida y **golpe de escudo** para robar el balón (el empujón con aturdimiento del Destello de PHAROS, adaptado).
- **Un dios patrono por equipo**, con un poder que se carga durante el partido: Zeus (rayo que aturde a un rival),
  Poseidón (ola que barre media cancha), Hermes (sprint de todo el equipo), Hefesto (muro de bronce frente al arco),
  Atenea (pase teledirigido), Ares (tiro que atraviesa al portero).
- **Estadios con trampas míticas:** Olimpia (clásico), el Laberinto de Creta (muros que se mueven), la cubierta del Argo
  en plena tormenta, la caldera de Thera (lava en las bandas), el Hades (el balón se vuelve invisible a ratos).
- **Multijugador local** de 2 a 4 personas como corazón social. El online puede venir después: el repositorio ya tiene
  experiencia con salas WebRTC en Godot para navegador (el proyecto Dead Air).

**Bucle principal:** partido de 3 min → reclutar o subir de nivel a un héroe → elegir dios y formación → siguiente
estadio. Los héroes reclutables: Aquiles (velocidad), Áyax (portero muralla), Atalanta (delantera veloz), Heracles
(fuerza), Odiseo (pases con truco), Hipólita (defensa), Perseo (regate con sandalias aladas), Jasón (capitán).

**Dirección de arte**

- Reutiliza el "Diorama del Egeo" de PHAROS casi uno a uno: estadios de piedra caliza, columnas, gradas con estandartes,
  el mar al fondo.
- **La identidad del equipo es el color del penacho** (rojo contra azul): lo más legible de la pantalla.
- **Cut-ins anime sin caras:** líneas de velocidad, contraluz dramático, la rendija del yelmo encendida con el color del
  dios, primer plano de sandalias y balón. Toda la energía del anime, sin una sola boca.

**Estructura de ~8 h** · campaña "Los Juegos de los Dioses"

| Bloque | Contenido | Duración |
|---|---|---|
| 8 estadios | En cada uno, 3 partidos y un partido "jefe" contra un equipo de monstruos: Cíclopes (portero gigante), Centauros (velocidad), Amazonas, Harpías (roban el balón volando), Gigantes, Titanes… | 8 × ~55 min ≈ 7 h 20 min |
| Torneo final | Eliminatoria contra los equipos de los dioses | ~40 min |
| Después | Multijugador local y ligas personalizadas | Sin límite |

**MVP mínimo (2–3 semanas)**

- Un estadio (Olimpia), tres contra tres contra la IA, dos dioses, un tiro especial con *cut-in* y multijugador local
  para dos.

**Riesgos**

| Riesgo | Mitigación |
|---|---|
| IA de fútbol | Tres contra tres con roles fijos (portero, defensa, delantero); el jugador controla al que lleva el balón. |
| Balance de poderes | Cargas largas y un contrapoder por dios. |
| Física del balón | Simple y arcade: gravedad, fricción y rebote, sin efecto realista. |
| Alcance del online | Primero local; online solo si la demo funciona. |

**El giro creativo:** el sueño del fútbol anime del cliente, contado con la mitología que le encanta y resuelto con
yelmos: **el problema de las caras desaparece por diseño**, y el estadio también juega.

---

## 5. SIETE VIDAS

> **Pitch:** eres un gato que vive siete vidas en el mismo puerto mediterráneo, de la Grecia antigua a hoy. Cada vida
> es una época, y lo que haces en una cambia la siguiente.

**Por qué es divertido**

- **Ser gato:** saltar a los tejados, colarse por ventanas, tirar cosas de las mesas y dormir al sol (así se guarda la
  partida).
- **Un solo mapa, siete versiones:** el mismo puerto se vuelve romano, bizantino, veneciano, otomano, del siglo XIX y
  actual. Mucho contenido con poco costo, y el placer de reconocer cada esquina siglos después.
- **Ecos entre vidas:** enterrar un anillo en la Grecia antigua para que un arqueólogo lo encuentre en la vida 7; mover
  una semilla de olivo que, siglos después, es el árbol que permite subir a la muralla. Puzles a través del tiempo.
- Sin combate pesado: persecuciones (perros, gaviotas, ratas) y sigilo suave. Es la propuesta tranquila del grupo.

**Bucle principal:** explorar la época → descubrir qué necesita alguien del puerto (un pescador, una niña, un faro
apagado) → resolverlo con habilidades de gato → acurrucarse y dormir (el final de esa vida, con ternura) → despertar
siglos después.

**Dirección de arte**

- Diorama low-poly con *tilt-shift*: la "maqueta" de Octopath, pero con el flujo procedural de PHAROS. Cada época tiene
  su acento de color: blanco y terracota griego, rojo pompeyano, oro bizantino, verde veneciano, azulejo otomano,
  gris de vapor, colores pastel de hoy.
- **Sin caras, con una regla elegante:** en los momentos cercanos la cámara baja a la altura del gato, así que **los
  humanos se ven de las rodillas para abajo** (manos, sandalias, redes, faldas). En la vista de diorama llevan
  sombreros, velos o capuchas de su época.

**Estructura de ~8 h** (7 vidas de ~65 min y un epílogo)

| Vida | Época | El puerto |
|---|---|---|
| 1 | Grecia clásica | Faro de madera, trirremes, ágora |
| 2 | Roma | Termas, mosaicos, ánforas de vino |
| 3 | Bizancio | Iglesia con cúpula, murallas nuevas |
| 4 | Venecia | Fortaleza del león alado, galeras |
| 5 | Época otomana | Bazar, cafés, minarete |
| 6 | Siglo XIX | Faro de piedra, barcos de vapor |
| 7 | Hoy | Turistas, motos, el arqueólogo y el anillo |

**MVP mínimo (2–3 semanas)**

- El puerto griego (con arte de PHAROS) y el mismo puerto en época romana (variación del kit), control del gato
  (saltar, trepar, empujar), 3 puzles y **un eco entre vidas** funcionando.

**Riesgos**

| Riesgo | Mitigación |
|---|---|
| Diseñar puzles es caro | Pocos puzles por vida, pero buenos; los ecos reutilizan objetos. |
| Contar sin diálogos | Gestos, objetos, música y la luz de cada época. |
| Menos acción de la que le gusta al cliente | Persecuciones y ritmo; se ofrece como proyecto paralelo, no como principal. |

**El giro creativo:** el mismo diorama a lo largo de 2.500 años, vidas pasadas que dejan pistas a las futuras… y un
gato no mira caras: mira rodillas.

---

## Comparación

Escala: ★ = poco, ★★★★★ = mucho. En riesgo y alcance, menos es mejor.

| Proyecto | Atractivo visual | Riesgo técnico | Alcance | Originalidad | Encaje con el cliente |
|---|---|---|---|---|---|
| **PHAROS** (MVP elegido) | ★★★★★ | Bajo | Medio | ★★★★ | ★★★★★ — TD, Grecia, combate, agua y animales |
| **Ocho Dorsales** | ★★★★★ | Alto — *pixel art* desde 3D, IA de fútbol, posproceso web | Alto | ★★★★ | ★★★★ — su sueño anime |
| **Bastet** | ★★★★ | Bajo | Medio | ★★★★★ | ★★★★ — gatos y TD |
| **Thalassa** | ★★★★★ | Muy alto — mundo abierto y combate profundo | Muy alto | ★★★ | ★★★★★ — su sueño God of War |
| **Episkyros** | ★★★★ | Medio | Medio | ★★★★★ | ★★★★ — fútbol y mitología |
| **Siete Vidas** | ★★★★ | Bajo | Medio | ★★★★★ | ★★★ — tiene menos acción |

### Qué reutiliza cada propuesta de PHAROS

| Propuesta | Reutiliza de PHAROS | Hay que construir nuevo |
|---|---|---|
| **Bastet** | Ciclo día/noche, oleadas, puntos de construcción, combate del héroe, UI, animales | IA de gatos y caprichos, arte egipcio |
| **Thalassa** | Agua, generación de islas, vegetación, animales, combate, enemigos, navegación (§4.3 del GDD) | Lanza arrojadiza, mundo por regiones, templos, cámara más cercana |
| **Episkyros** | Arte griego, hoplitas con yelmo (los aliados de PHAROS), empujón con aturdimiento (el Destello), iluminación, UI | Balón e IA de tres contra tres, multijugador local, *cut-ins* |
| **Siete Vidas** | Puerto griego, agua, gatos, luz por hora del día | Control vertical del gato, puzles, variantes de época |
| **Ocho Dorsales** | Dioramas low-poly, iluminación, flujo procedural | Render a *pixel art*, *tilt-shift* propio, duelos, IA de fútbol |

---

## Recomendación: por qué PHAROS primero

1. **Une las tres ideas en un alcance que se puede terminar.** Es el *tower defense* que el cliente confirmó ("es un
   TD"), tiene la Grecia de God of War que le encanta (combate con peso, mitología, agua, animales) y deja abierta la
   puerta al mundo abierto con la navegación entre islas de la campaña.
2. **Máximo atractivo con el mínimo riesgo.** Un mapa cerrado, formas simples, sistemas pequeños y probados por el
   género. Se ve hermoso en la web y se puede jugar de principio a fin en semanas.
3. **La regla de las caras se cumple sola:** un héroe cuya cara es la llama de un farol, hoplitas con yelmo corintio,
   aldeanos con capucha, criaturas de cielo nocturno que solo tienen ojos que brillan y gatos sin boca.
4. **Construye la tubería que todas las demás necesitan:** geometría low-poly procedural, agua, luz por hora del día,
   vida animal, combate con *hit-stop*, kit de UI (Cinzel, EB Garamond, marfil y oro) y una exportación web optimizada.

**Ruta sugerida**

1. **PHAROS:** MVP → *vertical slice*, que ya incluye la primera travesía por mar (la semilla de Thalassa).
2. **Un proyecto corto, en paralelo o después:** **Bastet** o **Episkyros**. Cada MVP lleva 2–3 semanas porque
   reutiliza casi todo.
3. **Thalassa**, el sueño grande, cuando el agua, las islas y el combate estén maduros: es la evolución natural de
   PHAROS.
4. **Ocho Dorsales** necesita su propio flujo (*pixel art* desde 3D y posproceso). Conviene una prueba de arte de una
   semana antes de comprometerse.
