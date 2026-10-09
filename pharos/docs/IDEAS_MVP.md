# Cinco ideas nuevas para un MVP

**Lo que aprendimos de PHAROS.** De PHAROS gustó el mar, pero el juego iba despacio: largas fases de construir sin presión, torres que disparaban solas mientras mirábamos, pocas decisiones por minuto, una dificultad repartida en siete noches, la acción pequeña y lejos de la cámara, golpes con poco impacto, pocas sorpresas y ningún motivo para volver a jugar. La prueba de estilos dejó otra lección: un estilo embellece un juego, pero no lo hace divertido. Por eso las cinco ideas siguen las mismas reglas: algo divertido en los primeros diez segundos, una decisión cada uno o dos segundos, nada que juegue por ti, más dificultad cada minuto, la acción grande y cerca, golpes que se notan, partidas cortas que aprietan desde el primer minuto, reintento inmediato y cada estilo con la cámara que le sienta bien.

Las cinco son distintas entre sí y entre todas usan los cuatro estilos que te gustaron. Cada MVP da para 10–20 minutos de juego en el navegador y lleva de 2 a 3 días. ARPÓN y ÁNFORA recogen lo que pedías para una Grecia tipo God of War: mar, animales, mito y combate con peso.

---

## 1. ARPÓN · Los piratas de Dioniso

> Una barca, un arpón con cuerda y un mar lleno de piratas: te enganchas a una columna hundida, giras cada vez más rápido y te sueltas contra la flota; cada pirata que cae al agua se convierte en delfín y se une a la fila que nada detrás de ti.

**Los primeros 10 segundos.** Tu barca de vela azul cabecea entre los bajíos turquesa de una bahía y, delante, asoma la columna de un templo hundido. Mantienes el clic: el arpón se clava, la cuerda se tensa con un golpe seco y la barca gira alrededor de la columna cada vez más rápido. Sueltas, sales disparado, rebotas sobre el agua y partes en dos un esquife pirata. Sus tripulantes caen al mar, salen saltando convertidos en delfines y se ponen en fila en tu estela.

**Por qué engancha**
- **Tensión:** la velocidad es tu daño, y la fila de delfines, tu vida. Si te dan, la fila se dispersa y hay que recogerla pasando por encima, como los anillos de Sonic; si te dan sin delfines, vuelcas y se acaba la partida.
- **Escalada:** cada minuto, más barcos y más oleaje, hasta una tormenta con olas que sirven de rampa.
- **Maestría:** soltar en la tangente justa, elegir cuerda larga (giro lento y fácil) o corta (rápido y exigente) y encadenar anclajes sin perder velocidad.
- **Sorpresa:** un barco arponeado que usas de martillo; una ola que te lanza por el aire con toda la fila saltando detrás.
- **Volver a jugar:** la bahía se coloca de otra forma en cada partida, hay récords y un capricho de Dioniso al azar altera una regla (la cuerda enreda como una parra, el mar de vino marea a los piratas…).

**El bucle.** Eliges anclaje (columna, roca o barco enemigo), giras, sueltas hacia un objetivo y vuelves a arponear antes de frenar: una decisión cada uno o dos segundos. Los delfines no atacan solos: nadan en tu estela como la cola de un cometa y, cuando vas a toda velocidad, arrollan lo que cruza tu ruta. La fila es tu vida, tu fuerza y tu marcador (cuantos más delfines, más vale cada barco), sin interfaz, y quedarse girando en una columna no limpia nada. Partidas de 6 minutos: la flota llega en el primer minuto y, en el quinto, el buque insignia, que solo vuelca con tres vueltas de cuerda.

**El MVP** (3 días)
- Bahía de 150 × 150 m llena de bajíos, arrecifes y bancos de arena, con unos 30 anclajes colocados por código en cada partida: rocas y columnas enteras, rotas o caídas con su capitel. Siempre hay uno al alcance del arpón, que llega a 25 m.
- El mar Wind Waker de la prueba de estilos con tres cosas nuevas: estelas de espuma detrás de cada barco, sombras de nubes y un oleaje de tormenta que también se calcula en la CPU, para que la barca pueda saltar en las olas.
- Barca sencilla y órbita calculada (radio y velocidad), sin simular la cuerda. Al soltar, un imán suave corrige hasta 15°: con la cuerda corta queda una ventana de unos 100 ms, que pide habilidad sin frustrar.
- Cámara inclinada que enseña el horizonte y el cielo; mientras giras mira al centro del giro, y solo se adelanta al soltar.
- 3 enemigos (Esquife, que embiste; Arquero, que solo dispara cuando está en pantalla; Birreme, que hay que arrastrar), el buque insignia y una embestida que, a toda velocidad, parte un barco en dos.
- Hasta 40 delfines (el delfín de PHAROS) que siguen la ruta grabada de la barca, lo que sale más barato que una IA de caza; récords, reintento inmediato y audio procedural de cuerda, viento y tambor.
- 4 caprichos y relámpagos en la tormenta, que son lo primero que se recorta si falta tiempo.
- *Fuera:* Caribdis y Escila, arpones nuevos, mejoras entre partidas y el coop online.

**Estilo: Wind Waker.** El mejor mar de las pruebas lucía junto a la costa, donde las bandas turquesa salen de la poca profundidad; por eso la bahía está llena de bajíos, con anillos de espuma en cada arrecife, y la cámara inclinada enseña también el horizonte y las nubes recortadas. Al final llega la tormenta. La vela azul, los piratas de rojo y los delfines gris azulado se distinguen al instante, sin interfaz en pantalla. Caras: Acetes, el protagonista, lleva un pétaso (sombrero de ala ancha), que es lo único que se ve desde la cámara; los piratas son siluetas con casco, y de Dioniso solo se ven la parra del mástil y un leopardo en la proa, de perfil y con la boca cerrada.

**Referencias:** la copa de Exequias (Dioniso entre delfines, c. 530 a. C.); el *Himno homérico a Dioniso* y Ovidio, *Metamorfosis* III (Acetes); *The Wind Waker*; *Rocket League* (la velocidad es el daño); *Sonic* (los anillos que se pierden con cada golpe); *Snake* (la cola que crece).

**Riesgo principal:** que soltar frustre o que, con demasiada ayuda, se vuelva automático. Lo cubren el imán suave, la cuerda larga para aprender, la cámara que mira al centro del giro y medio día reservado para afinar.

---

## 2. ÁNFORA · El vaso que gira

> Peleas dentro del friso de un ánfora de figuras negras que gira en el torno: un pincel gigante pinta a los enemigos delante de ti, y lo que lanzas da la vuelta al vaso y vuelve por el otro lado.

**Los primeros 10 segundos.** Un ánfora gira en un taller a la luz de un candil y la cámara entra en su franja pintada. Eres Heracles, una figura negra con la piel del león por capucha. Un pincel gigante termina de pintar un centauro, que carga contra ti. Lo agarras, lo volteas y lo lanzas: desaparece tras la curva del vaso y, con un silbido que sube, asoma por el otro lado, arrolla por la espalda a tres hoplitas y vuelve hacia ti. Lo atrapas al vuelo y lo lanzas otra vez.

**Por qué engancha**
- **Tensión:** lo recién pintado se borra de un golpe, que es lo seguro; lo que dejas secar pelea, pero puedes lanzarlo, y solo los lanzamientos llenan el combo.
- **Escalada:** tres oleadas más densas y un pincel cada vez más rápido, que desde la segunda pinta de dos en dos, a ambos lados de ti.
- **Maestría:** contar la vuelta de cada lanzamiento, que tarda siempre lo mismo, y atraparlo para multiplicar el combo.
- **Sorpresa:** lo lanzado reaparece por tu espalda cuando ya miras otra cosa y arrolla a quien encuentra.
- **Volver a jugar:** el récord de combo, el reto de acabar sin grietas y partidas de 6 minutos con reintento inmediato.

**El bucle.** Miras dónde baja el pincel, borras o esperas, agarras (el centauro rueda y arrolla; el hoplita vuela), lanzas hacia delante o hacia atrás y atrapas a la vuelta. Por detrás del vaso solo pasa lo que lanzas tú: nunca te hace daño, tarda siempre lo mismo en dar la vuelta (unos 4 segundos) y, si no lo atrapas, cae al suelo y puedes recogerlo. La parte oculta es un ritmo, no una amenaza: lanzo, cuento, atrapo. Los hoplitas paran de frente, pero lo lanzado les llega por la espalda. En la primera oleada los enemigos llegan ya secos, para que descubras el agarre antes que el borrón. Con el combo lleno, el vaso entra al horno: 10 segundos en figuras rojas sin recibir daño.

**El MVP** (3 días justos, con el alcance recortado)
- Primer día: la pelea en una tira plana que se repite, para comprobar que agarrar y lanzar divierte antes de hacer el vaso.
- Una franja cilíndrica de 60 m de vuelta. La pelea se dibuja de perfil en una textura que envuelve un ánfora hecha por código, a doble resolución y con mipmaps para que las incisiones no parpadeen al girar.
- Heracles: golpe, agarrar, voltear, lanzar, atrapar al vuelo, estampar y esquivar.
- El pincel (1,5 s por enemigo) y 2 enemigos, Hoplita y Centauro, en tres oleadas.
- Vida en 5 grietas que se reparan con lañas de plomo, como los vasos griegos; modo horno y audio procedural de barro, aulós y tímpano.
- *Fuera:* Gerión y los demás jefes, la Amazona, los ornamentos con poderes, el ánfora final con tus jugadas, más franjas y vasos, y el coop online.

**Estilo: cerámica ática, figuras negras (y rojas en el horno).** Barniz negro brillante con líneas incisas sobre arcilla naranja, entre meandros. La prueba mostró que este estilo falla visto desde arriba; aquí va de perfil, como en los vasos, y el ánfora aporta volumen: un brillo que resbala al girar y el taller detrás. Para que las figuras no queden como manchas negras lisas, llevan lo que da vida a los vasos de Exequias: emblemas grandes en los escudos (nunca gorgonas, que son caras), penachos y detalles en rojo y blanco añadidos, y la melena del león incisa, que además distingue a Heracles en la melé. No hay barras: la vida son las grietas. Caras: la cabeza del león, que le sirve de capucha a Heracles, va con la boca cerrada, y el perfil del héroe queda en negro liso; todos los demás llevan yelmo, también los centauros, y del Pintor solo se ve el pincel.

**Referencias:** las ánforas de Exequias; el ánfora de Neso (Heracles contra el centauro, c. 620 a. C.); *Nebulus* (la torre que gira); *Castle Crashers* (lanzar enemigos); *Okami* (el pincel como mecánica).

**Riesgo principal:** que los agarres hechos por código no pesen. Lo cubren dos cuerpos unidos por un punto de agarre, poses sacadas de los vasos, mucha respuesta (pausa, temblor, polvo de barro) y el primer día en la tira plana: si ahí agarrar y lanzar no divierte, no se hace el vaso.

---

## 3. SALTO DEL TORO · Los saltadores de Cnosos

> En el patio de Cnosos al toro no se le mata, se le salta: te agarras a los cuernos en el último instante, das una voltereta sobre su lomo y encadenas toros sin tocar el suelo mientras el muro del palacio pinta tus saltos.

**Los primeros 10 segundos.** No hay menú: estás en el patio, visto de perfil y entero en pantalla. Por la puerta de la izquierda entra un toro manchado, escarba y embiste; la grada calla y los tambores aceleran. Sus cuernos destellan en oro y pulsas: te agarras, el toro te lanza y, por un instante, su lomo pasa bajo tus manos. Caes de pie, estalla una nube de pigmento azul y en la pared del fondo tu figura se pinta trazo a trazo. Por la puerta de la derecha entra el segundo toro.

**Por qué engancha**
- **Tensión:** cuanto más tarde agarras, más alto saltas y más puntúas; un instante de más y el toro te lanza a la grada.
- **Escalada:** cada 30–40 segundos, un paso más: toros más rápidos, el que amaga, dos que se cruzan y hasta tres a la vez por las dos puertas.
- **Maestría:** leer a cada toro, caer sobre el lomo del que viene de frente, clavar el aterrizaje y variar, porque el público se cansa si repites el mismo truco con la misma caída.
- **Sorpresa:** toros que amagan, dos toros que se cruzan y chocan, columnas que caen y el Toro de Poseidón saliendo del mar pintado en el muro.
- **Volver a jugar:** festivales de 4 minutos con los toros en otro orden cada vez, reintento en un segundo, récord y una postal de fresco con tu mejor salto.

**El bucle.** Cada uno o dos segundos ves qué toro viene y por qué puerta, lo llamas con una palmada si te conviene y decides: saltarlo o esquivarlo rodando, porque no hay carril al que apartarse. Si te agarras pronto, salto corto; justo, salto alto y dorado; tarde, sales volando hacia la grada, sin sangre. En el aire eliges truco y dónde caer: en el suelo cobras el combo; sobre el lomo del toro que viene de frente, el combo sigue creciendo. Tres vidas, que son tres lirios.

**El MVP** (2–3 días)
- Un patio de unos 15 m, de perfil, con cámara fija y un solo plano, como el fresco: dos puertas, columnas que caen, grada de siluetas y muro de fresco. Los toros lo cruzan en 1,5 s.
- Una acróbata nueva (cintura estrecha y rizos largos) con rig por código: correr, rodar, palmada, agarre (ventana perfecta de 120 ms con imán), 3 trucos y aterrizaje.
- Un toro nuevo, con la columna de varios anillos del gato de PHAROS, patas de dos tramos y la pose del «galope volador» del fresco, en 3 variantes: rápido, que amaga y enorme que derriba columnas. Cada modelo nuevo lleva medio día.
- Festival de 4 minutos que sube cada 30–40 s (de 1 a 3 toros a la vez, en otro orden cada partida), multiplicador del público de ×1 a ×8 y un muro que estampa tus 12 mejores poses.
- Una pausa de menos de 0,3 s en los saltos perfectos, y en ningún otro momento.
- El Toro de Poseidón como jefe, que es lo primero que se recorta si falta tiempo.
- Audio procedural: tambores, cascos, público y una lira en los saltos perfectos.
- *Fuera:* el Minotauro (un rey con máscara de toro), más patios y trucos, y el coop con los tres papeles del fresco: sujetar, saltar y recibir.

**Estilo: fresco minoico.** Cal agrietada, pigmento plano y cenefas de espirales que enmarcan la pantalla. Para evitar el «ocre sobre ocre» de la prueba se usa como el original: de perfil, con figuras grandes y cálidas sobre azul egipcio intenso, toros blancos y negros y columnas rojas. El fresco vive de la línea, así que todo lleva contorno oscuro irregular, pigmento algo desvaído y huecos donde se cayó el enlucido; sin eso, el color plano se vería simplón. El muro empieza en cal desnuda y se colorea con tus saltos, y la única interfaz es el multiplicador. Caras: las acróbatas, de perfil, tienen la cabeza de un tono plano, sin ojo ni boca, con rizos negros y cinta; el público es un friso de cabezas con velo. No es una corrida: el toro nunca sufre.

**Referencias:** el Fresco del Salto del Toro y el de la Tribuna (Cnosos, c. 1450 a. C.); *El rey debe morir*, de Mary Renault; *Tony Hawk's Pro Skater* (el combo se cobra al aterrizar); *Punch-Out!!* (leer al rival).

**Riesgo principal:** que el agarre se reduzca a pulsar cuando lo pide la pantalla. No hay anillo: el aviso es el toro (resopla, baja la cabeza, los cuernos destellan 0,3 s antes), la ventana es generosa al principio y el giro y la caída son tuyos. El estilo plano perdona las volteretas hechas por código, pero no un toro que galopa rígido; por eso el toro es un modelo nuevo.

---

## 4. LÉLAPS · El perro de las estrellas

> Eres Lélaps, el perro que siempre atrapa a su presa: corres dentro de una copa de figuras rojas dejando una estela de luz, y lo que encierras en un lazo sube al cielo convertido en constelación.

**Los primeros 10 segundos.** Apareces en el fondo de una copa negra como la noche. Un rebaño de cabras de terracota la cruza a la carrera y un jabalí embiste hacia ti. Corres y de tus patas sale un hilo dorado; rodeas al rebaño y, cuando el hilo toca su inicio, suena un clic de cristal: las seis cabras estallan en estrellas que se encienden con un arpegio de lira y suben al borde. El jabalí se estrella contra tu hilo y rebota aturdido: es el siguiente.

**Por qué engancha**
- **Tensión:** tu estela es una cerca que las bestias no cruzan, pero la serpiente la corta. Un lazo grande atrapa más y deja más cerca al alcance de las serpientes.
- **Escalada:** el primer minuto ya trae jabalíes y serpientes, y cada minuto llega una oleada más densa.
- **Maestría:** ladrar para apelotonar, empujar al rebaño con la cerca, desviar al jabalí y encadenar cierres para subir el multiplicador.
- **Sorpresa:** el jabalí que rebota en tu cerca y queda aturdido dentro del lazo; la serpiente que llega por donde no mirabas; la zorra que se lleva una constelación.
- **Volver a jugar:** constelaciones-poder (1 de 3 cada 2 minutos) que cambian cada partida y el récord del lazo más grande.

**El bucle.** Rodeas grupos, ladras para juntarlos, decides el tamaño del lazo según dónde estén las serpientes y esprintas para cerrarlo; los cierres grandes sueltan una cascada de estrellas. Las presas evitan el borde de la copa, así que siempre se pueden rodear. Partidas de 6 minutos que acaban con la zorra de Teumeso, más rápida que tú y capaz de cortar tu estela: roba una constelación del borde y se la lleva hacia el centro, donde se la puede encerrar. Tres cierres y Zeus os convierte a los dos en estrellas, como en el mito.

**El MVP** (2–3 días)
- El interior de la copa (unos 30 m de diámetro), con un borde de meandro donde se ven las constelaciones.
- Lélaps: correr, estela que se cierra sola, esprint y ladrido; aguanta 3 golpes, que son las estrellas de su collar.
- La estela como cerca: las bestias chocan con ella y solo la serpiente y la zorra la cortan. Es una regla de colisión, no contenido nuevo.
- 3 bestias (cabra, jabalí y serpiente), grandes y como mucho 15 a la vez; la zorra, 6 constelaciones-poder, multiplicador y récord.
- Lo nuevo de verdad son las figuras: recortes planos de perfil, con líneas interiores y paso animado por código.
- Cada cierre se nota (pausa breve, onda, cristal); la cámara va cerca del perro y se aleja poco. Audio procedural de lira, cristal y ladridos.
- El resto es sencillo: detectar el lazo es geometría básica y las manadas son bandadas (boids), sin humanos que animar.
- *Fuera:* la arpía, el León de Nemea, más vasos, el zodiaco completo, retos diarios y el coop.

**Estilo: cerámica ática, figuras rojas.** El barniz negro de la copa es el cielo nocturno y las bestias son figuras de terracota de perfil, con líneas negras finas, como en el medallón de una copa real. La cámara mira la copa inclinada (55–60°) y las figuras van de pie, recortadas, y solo se voltean a izquierda o derecha, como las siluetas animadas de Lotte Reiniger: nunca se ven tumbadas ni desde arriba, que es donde la prueba dio masas negras pesadas. Son pocas y grandes, y la cámara se aleja poco, para que las líneas finas no se pierdan. La estela es una línea dorada y lo capturado pasa a blanco y oro: cuanto mejor juegas, más estrellas tiene la copa. Caras: no hay humanos; el perro y la zorra tienen el ojo como un punto de luz y no tienen boca.

**Referencias:** las copas (kílix) de figuras rojas; Lélaps y la zorra de Teumeso (Ovidio, *Metamorfosis* VII); *Las aventuras del príncipe Achmed*, de Lotte Reiniger (siluetas animadas); *Vampire Survivors* (oleadas y mejoras); *Qix* y *Paper.io* (encerrar); *Peggle* (celebrar la jugada grande).

**Riesgo principal:** el aspecto. Las figuras de perfil hechas por código son un sistema nuevo, porque los animales de PHAROS son 3D, y si salen pobres la copa se llena de manchas naranjas. Por eso el MVP se queda en tres bestias y la zorra, con la cámara cerca; si se ven bien, se añaden más. Que los cortes parezcan azar ya no preocupa: solo corta la serpiente, y se la ve venir.

---

## 5. ALAS DE CERA · Ni muy alto ni muy bajo

> Escapas de Creta con alas de plumas y cera: cerca del sol cazas aves de bronce en picado y cada una multiplica tus puntos mientras la cera se derrite; para cobrarlos tienes que rozar el mar, que la enfría pero empapa las plumas.

**Los primeros 10 segundos.** Amanece en lo alto de la torre del Laberinto. Saltas detrás de Dédalo y caes en picado hacia el mar. Abres las alas en el último instante, rozas las olas y suena una campanilla. Subes a través de un cúmulo enorme y, al salir, cerca del sol, vuela una bandada de aves de bronce. Pliegas las alas, caes sobre la primera y el golpe te devuelve hacia arriba: ×2. Otra: ×3. La cera brilla y se suelta una pluma. ¿Una más o bajas a cobrar?

**Por qué engancha**
- **Tensión:** cada ave cazada sube el multiplicador y te devuelve hacia arriba, donde se derrite la cera; abajo cobras y te enfrías, pero las plumas mojadas pesan.
- **Escalada:** según avanza el día, las bandadas son más densas, la línea de calor baja y el pasillo seguro se estrecha.
- **Maestría:** cambiar altura por velocidad, encadenar presas sin aletear y elegir el momento de bajar a cobrar.
- **Sorpresa:** el ala con menos plumas tira del vuelo hacia su lado; una arpía te arrastra hacia el agua.
- **Volver a jugar:** vuelos de 3 a 5 minutos con bandadas y viento distintos cada vez, una pluma que flota donde caíste y la meta de pasar Icaria, donde Ícaro cayó en el mito.

**El bucle.** El multiplicador no sube por estar arriba, sino por cazar arriba. Picas sobre un ave de bronce, el rebote te devuelve hacia arriba sin aletear y buscas la siguiente; encadenarlas te mantiene en lo alto mientras gotea la cera, hasta ×10. Cada ave plantea la misma pregunta, una vez por segundo: ¿una más o bajo a cobrar? Para cobrar, rozas el mar antes de quedarte sin plumas. Por el camino esquivas los disparos de las aves, las arpías y las rocas que lanza Talos, y cruzas bandadas de gaviotas que devuelven plumas. Si caes, la caída es lenta, entre plumas, y acaba en una escena como el cuadro de Bruegel, donde nadie mira.

**El MVP** (3 días)
- Vuelo lateral de Creta a Icaria (unos 4 minutos) con capas de paralaje: cielo, cúmulos, 5 islas y mar.
- Dos botones: mantener para picar y pulsar para aletear, que gasta aliento.
- Calor y humedad sin interfaz: la cera gotea y cada ala tiene 20 plumas que se ven, se sueltan y se oscurecen al mojarse.
- Aves de bronce cerca del sol, que disparan y se cazan en picado; arpías, rocas de Talos, las gaviotas de PHAROS, final en Icaria o en el mar, récord y audio procedural de viento y cera.
- El juego cabe en dos días; el tercero es para el aspecto pintado (ver el estilo) y para los cúmulos de primer plano que se atraviesan, que son tarjetas nuevas.
- *Fuera:* el coop de Dédalo e Ícaro, Talos como jefe, la tormenta de Zeus y alas de otras aves.

**Estilo: pintura Ghibli.** El mejor cielo de las pruebas: cúmulos enormes con sombras violetas y bordes dorados, y un mar con destellos y pincelada visible. Ese aspecto salía de un filtro de pintura a pantalla completa, el más caro en web y el que más «nada» al moverse. Aquí el filtro se aplica una sola vez, al cargar, a las capas de paralaje (cielo, nubes e islas lejanas), que luego solo se desplazan: se conserva lo que gustó, la pincelada no se mueve y apenas cuesta. En vivo solo se dibujan el mar cercano, con la pincelada en su textura, y los personajes, planos y limpios como en las películas de Ghibli, para que se lean a toda velocidad. La cámara va cerca de Ícaro y solo se abre en los picados largos. Caras: Ícaro y Dédalo llevan capuchas de plumas con visor en forma de pico y se ven de perfil, a contraluz; las arpías llevan máscara de bronce, y en la escena final el labrador, el pastor y el pescador están de espaldas o con capucha.

**Referencias:** Ovidio, *Metamorfosis* VIII («ni muy alto ni muy bajo»); *Paisaje con la caída de Ícaro*, atribuido a Bruegel; *Porco Rosso*; *Tiny Wings* y *Luftrausers* (vuelo con inercia).

**Riesgo principal:** que se sienta tranquila, como un juego de móvil. Por eso el multiplicador solo sube cazando: no basta con aguantar arriba, hay que actuar cada segundo. Aun así es la menos intensa de las cinco; a cambio, es la que mejor luce la pintura Ghibli.

---

## Comparación

| Idea | Género | Estilo | Emoción | Viabilidad | Multijugador (después del MVP) |
|---|---|---|---|---|---|
| **ARPÓN** | Acción arcade de velocidad en el mar | Wind Waker | ★★★★★ | ★★★ · 3 días | Coop online de 2 a 4 barcas: una cuerda tendida entre dos barcas barre la flota como una red |
| **ÁNFORA** | Lucha lateral: agarrar y lanzar | Cerámica ática (figuras negras y rojas) | ★★★★★ | ★★ · 3 días, recortada | Coop online de 2: os pasáis enemigos lanzados alrededor del vaso |
| **SALTO DEL TORO** | Acrobacias con puntuación | Fresco minoico | ★★★★ | ★★★★ · 2–3 días | Coop online de 2 o 3 con los papeles del fresco: sujetar, saltar y recibir |
| **LÉLAPS** | Supervivencia por oleadas con un lazo | Cerámica ática (figuras rojas) | ★★★★ | ★★★★ · 2–3 días | Coop online de 2 a 4 perros: dos estelas se unen en un lazo gigante |
| **ALAS DE CERA** | Vuelo arcade de riesgo | Pintura Ghibli | ★★★ | ★★★ · 3 días | Coop online de 2: Dédalo e Ícaro en formación |

Los cinco MVP son para un jugador; el multijugador usaría las salas con código de DEAD AIR, que ya funcionan en el navegador.

## Recomendación

Empezaríamos por **ARPÓN**. Es la idea que divierte antes (a los tres segundos ya estás girando enganchado a una columna), está hecha sobre el mar, que fue lo que te gustó de PHAROS, y usa el Wind Waker, que dio el mejor mar de las pruebas. Además corrige uno por uno los problemas de PHAROS: no hay esperas, decides cada uno o dos segundos, la dificultad sube cada minuto, cada choque se nota y nada juega por ti, porque los delfines solo arrollan lo que tú barres. No es la más barata: el mar, el estilo y el delfín ya existen, pero la barca, la órbita, la cámara y el oleaje de tormenta son nuevos. En 3 días tendrías una partida en el navegador para decidir si seguimos; antes de empezar dedicaríamos dos horas a ver el estilo en movimiento, porque las pruebas de estilo fueron imágenes fijas. Después iríamos a **SALTO DEL TORO**, de las más baratas y con la mejor imagen de cartel, o a **ÁNFORA**, la más original y la que más trabajo pide.

Quedan en reserva tres ideas más cercanas a tus primeros deseos: **TALÓN** (Aquiles, invulnerable salvo por la espalda, en un combate cuerpo a cuerpo en la playa de Troya), **SOLANA** (gatos que se pelean por la única mancha de sol de la casa, para jugar con amigos) y **LA NOVENA OLA** (fútbol-surf de dos contra dos sobre una ola gigante).
