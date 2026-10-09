# DOCE · Los trabajos de Heracles

**Mundo abierto de islas griegas en estilo Wind Waker.** Cada uno de los doce trabajos es una bestia, y cada bestia es un
desafío jugable distinto que sale tal cual del mito. El juego se define por lo que haces: pelear con peso, moverte con
la lanza de cadena, explorar islas y resolver a cada bestia con su propia regla. La historia es mínima y se cuenta con el
mundo, no con escenas.

Este documento cubre el **primer tramo jugable: la isla de Nemea y el León**.

## Pilares

1. **Combate con peso.** Golpes que se sienten (parada de impacto, empuje, sacudida de cámara), escudo que bloquea, parada
   en el momento justo, voltereta para esquivar. Enemigos que avisan antes de atacar.
2. **La lanza con cadena.** La lanzas, se clava y tiras: si el objetivo es pequeño lo traes hacia ti; si es grande o fijo
   (una roca, una argolla de bronce), vas tú hacia él. Sirve igual para pelear y para moverte.
3. **Cada bestia es un problema distinto.** No son sacos de vida: el León no se puede cortar, la Hidra regenera cabezas…
   Hay que entender la regla y usar el mundo.
4. **Una isla que da ganas de recorrer.** Mar Wind Waker, luz de tarde, bosque, olivares, acantilados, un pueblo vivo con
   gatos y cabras, y cosas que se ven a lo lejos y se pueden alcanzar.

## Controles

| Acción | Teclado y ratón | Mando |
|---|---|---|
| Moverse / cámara | W A S D / ratón | stick izquierdo / derecho |
| Correr | Shift (mantener) | L3 / mantener B |
| Saltar | Espacio | A |
| Voltereta (esquivar) | Shift (pulsar) | B |
| Golpe (combo de 3) | clic izquierdo | X |
| Golpe fuerte | mantener clic izquierdo | mantener X |
| Escudo / parada | clic derecho (mantener / en el momento justo) | LT |
| Lanza con cadena | Q (apunta a lo que miras) | RT |
| Fijar objetivo | Tab / clic central | R3 |
| Usar / agarrar / acariciar | E | Y |
| Pausa | Esc | Start |

## La isla de Nemea

Una isla de unos 300 × 300 m de tierra rodeada de mar.

- **Sur:** el pueblo de Nemea junto a la playa y el muelle. Casas blancas, un pozo, un altar, gatos, cabras y gente con
  capucha o casco, sin caras. Aquí llega Heracles en barco y aquí está el barco para la siguiente isla (Lerna, cerrada en
  este tramo).
- **Centro:** bosque de encinas y pinos, praderas con flores, olivares en terrazas al este. Lobos en el bosque y jabalíes
  en los claros.
- **Altares:** dos o tres en lugares altos. Son el punto de guardado: curan y es donde reapareces si caes.
- **Paso roto y acantilados:** argollas de bronce en las rocas para cruzar con la lanza de cadena; atajos y miradores.
- **Norte:** la sierra y la **cueva del León**, con dos entradas como en el mito.

Lo que se ve debe contar lo que pasa: cercas rotas, cabras muertas cerca del bosque, huellas grandes hacia la sierra.

## Enemigos del tramo

- **Lobos:** rápidos, en manada de 3 a 5. Rodean, uno ataca mientras los otros esperan. Enseñan el combo y la voltereta.
- **Jabalíes:** embisten en línea recta tras un aviso. Se esquivan o se paran con el escudo en el momento justo; si chocan
  contra una roca quedan aturdidos.
- (Si sobra tiempo) **bandidos con escudo:** obligan a romper la guardia con el golpe fuerte o a quitarles el escudo con
  la cadena.

## Trabajo I · El León de Nemea

- **La regla:** ninguna arma lo corta. Las espadas rebotan con chispas y un sonido metálico; el juego lo dice una sola vez.
- **Antes de la pelea:** la cueva tiene dos entradas. Con la cadena puedes arrastrar una roca grande para tapar una. Si no
  lo haces, el León huye a mitad de la pelea por la otra y te ataca desde fuera: la pelea es más difícil.
- **Cómo se le hace daño:**
  1. Esquivar su salto: si choca contra una columna o una pared queda aturdido unos segundos.
  2. Tirarlo con la cadena contra una columna o una roca: también lo aturde.
  3. Con el León aturdido, **E** para agarrarlo: una lucha cuerpo a cuerpo (pulsar en el momento justo para apretar,
     aguantar sus sacudidas con la estamina). Ahí sí le haces daño.
- **Fases:** al 66 % ruge (onda que te empuja) y salta entre las columnas; al 33 % se enfurece y encadena ataques.
- **Al vencer:** Heracles se pone la piel del León. El casco se cambia por la cabeza del León como capucha y la piel como
  capa: menos daño de armas cortantes.

## Flujo del tramo (20–30 minutos)

1. Llegada en barco al muelle al atardecer. Primer control: moverte por el pueblo, acariciar un gato.
2. Camino al bosque: primera manada de lobos.
3. Un paso roto: primera argolla de bronce, primer uso de la cadena para moverte.
4. Claros con jabalíes; un altar en un mirador.
5. La sierra y la cueva: la roca, las dos entradas, el León.
6. La piel del León. Vuelta al barco: tarjeta «II · La Hidra de Lerna», próximamente.

## Dirección de arte

- **Mundo en estilo Wind Waker:** luz en bandas, contornos de color, colores saturados, mar turquesa con bandas de
  espuma, nubes gráficas grandes, tarde dorada.
- **Interfaz con frisos de cerámica y fresco:** meandros, figuras negras en las tarjetas de cada trabajo, tipografía
  clásica. Interfaz mínima: vida y estamina, la barra del jefe, avisos.
- **Sin caras feas:** Heracles con casco corintio (y luego la cabeza del León), la gente con capucha o casco, criaturas
  con ojos que brillan.

## Lo que no entra en el primer tramo

La Hidra y las demás islas, navegar libremente, mejoras de equipo, inventario, diálogos y multijugador. Todo eso viene
después, isla a isla.

## Tecnología

Godot 4.7, todo generado por código (modelos, animación, isla, sonido), renderer Compatibility para que funcione en el
navegador con WebGL 2. Se reutiliza de PHAROS lo que sirve: el mar y la luz Wind Waker de la prueba de estilo, la
vegetación griega, los animales, el audio, la interfaz y la exportación web.
