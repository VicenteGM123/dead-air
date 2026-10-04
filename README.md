# DEAD AIR

**Canal 13 WZTV, noche de Halloween de 1977, un minuto antes de medianoche.** La emisora no consigue cerrar la
emisión, y todos los que la estaban viendo se han quedado "sintonizados": el público del plató, el coro de calcetines
del programa infantil, el hombre del tiempo y los cámaras. Tú eres uno de los cuatro miembros del equipo que se
salvaron, porque *quien hace un programa nunca lo ve*.

Es un juego de zombis por rondas en tercera persona, con estética de dibujo animado setentero (cámara al hombro
estilo *Plants vs. Zombies: Garden Warfare*). Todo está hecho con código, en Three.js, y funciona en el navegador.

## Versión Godot + Blender

El juego también está migrado tal cual a **Godot 4.7** (`godot/`, todo el código en GDScript) con todos los
assets 3D generados por código en **Blender** (`blender/`, scripts de Python que exportan a `godot/assets/`).
Para jugarla: abre `godot/project.godot` en Godot 4.7 y pulsa F5. Detalles en `godot/README.md`,
`blender/README.md` y `tools/audio/README.md`. La versión Godot tiene además **multijugador cooperativo online
de 1 a 4 jugadores** (MULTIPLAYER en el menú principal; ver `godot/README.md`).

**[Jugar versión Godot en el navegador](https://vicentegm123.github.io/dead-air/godot-web/)** (build web de prueba,
`godot-web/`: unos 165 MB de descarga la primera vez; Chrome/Edge/Firefox de escritorio con aceleración gráfica). En el
navegador Godot solo tiene el renderizador Compatibility (WebGL 2): se ve casi igual, pero sin sombras proyectadas, y el
multijugador no está disponible (los navegadores no pueden usar UDP/ENet): usa la versión de escritorio para jugar
online. Se regenera con `sh godot/web/export_web.sh` (necesita las plantillas de exportación web de Godot 4.7.2).

## Cómo jugar

**Jugar online:** https://vicentegm123.github.io/dead-air/

1. O descarga el repo y haz **doble clic en `index.html`**. Se abre en el navegador (Chrome o Edge recomendados) y no necesita
   servidor ni conexión.
2. La primera carga tarda un poco, porque se construye toda la emisora.
3. En la pantalla de título pulsa cualquier tecla. En el dial de la tele elige personaje con **A/D** (o la
   rueda del ratón) y sintonízalo con **E / Enter / Espacio**.
4. Haz clic en la ventana para capturar el ratón (con el mando de Xbox no hace falta). **Esc** abre la pausa
   (opciones, controles y salir).

Si cambias el código fuente, recompila con `npm install` (solo la primera vez) y luego `npm run build`. Tiene que
salir `build ok`.

## Controles

| Acción | Tecla |
|---|---|
| Moverse | W A S D |
| Mirar | Ratón |
| Correr | Shift |
| Saltar | Espacio |
| Apuntar | Botón derecho |
| Disparar | Botón izquierdo |
| Recargar | R |
| Usar / comprar | E |
| Reparar ventanas / girar manivelas | Mantener E |
| Cuerpo a cuerpo | V |
| Granada de válvula | G (mantén para cocinarla) |
| Tiny Tele | Q |
| Cambiar de arma | 1, 2 o rueda del ratón |
| Cambiar de hombro | C |
| Pausa | Esc |

## Control de Xbox

Conecta un mando de Xbox (por cable o Bluetooth) y pulsa cualquier botón: el juego lo detecta solo. Chrome y Edge
lo reconocen sin instalar nada. Con el mando no hace falta capturar el ratón. Mientras juegues con él, los carteles
de interacción muestran el botón del mando (**[X] 950**, con el anillo de carga alrededor de la X al mantenerlo) y
vuelven a **[E]** en cuanto toques el teclado o el ratón. El mando vibra un poco al disparar armas pesadas, al
recibir daño, con las explosiones y con el rayo del jefe.

| Acción | Botón |
|---|---|
| Moverse | Stick izquierdo (cuanto más lo inclinas, más rápido vas) |
| Mirar | Stick derecho |
| Correr | L3 (pulsa el stick izquierdo mientras avanzas; sigues corriendo hasta que te paras, apuntas o disparas) |
| Saltar | A |
| Apuntar | LT |
| Disparar | RT (mantenlo con las automáticas y para grabar con el Boom Mic) |
| Recargar | X (cuando no hay nada con lo que interactuar) |
| Usar / comprar / coger | X |
| Reparar ventanas / girar manivelas / el interruptor | Mantener X |
| Cuerpo a cuerpo | B |
| Granada de válvula | RB (mantenlo para cocinarla) |
| Tiny Tele | LB |
| Cambiar de arma | Y, o la cruceta izquierda / derecha para el arma 1 / 2 |
| Cambiar de hombro | Cruceta abajo |
| Pausa | Menú o Vista |

En los menús se navega con la cruceta o el stick izquierdo, **A** acepta y **B** vuelve. En el título vale
cualquier botón; en el dial de la tele, izquierda / derecha cambian de canal y **A** lo sintoniza. En la pausa, **B**
vuelve al juego y los deslizadores de Opciones se mueven con izquierda / derecha. En la pantalla final, **A** es sí y
**B** es no.

En Opciones hay una sensibilidad propia para el mando, invertir Y (compartido con el ratón), la asistencia de
apuntado (ligera: la mira frena un poco sobre los zombis y se acerca a ellos al pulsar LT) y la vibración. La tarjeta
de Controles de la pausa enseña las dos distribuciones, teclado y mando.

## Lo básico

- **No hay tutoriales, flechas ni textos de ayuda**, a propósito. La emisora te enseña con sus carteles, sus
  pantallas y sus sonidos. Mira a tu alrededor.
- Ganas puntos al disparar y eliminar zombis y al reparar ventanas. Con ellos abres puertas, compras armas de las
  paredes y pagas las máquinas.
- **Telly**, el televisor de madera que tiene vida, te da armas al azar si le pagas. Si abusas de su paciencia,
  se levanta y se va a otra habitación.
- Las **mejoras son anuncios**: compra un producto en su plató, protagoniza el anuncio y sal de él llevándolo puesto.
- La emisora empieza sin corriente. Encenderla lo cambia todo.
- En el patio del transmisor hay una antena parabólica que hace cosas muy buenas con tus armas.

## Consejos (sin destripar nada)

- Repara las ventanas entre oleadas: son puntos gratis y ganas tiempo.
- Apunta a la cabeza. Hace más daño y da más puntos.
- No te quedes arrinconado. Da vueltas amplias por las salas grandes para agrupar a los zombis.
- Cada tipo de zombi avisa antes de atacar con un sonido y un gesto propios. Aprende a reconocerlos.
- Si una ronda se alarga, busca al zombi rezagado: a veces está atascado en la otra punta.
- Esta emisora guarda más secretos de los que parece. Si algo te parece raro, probablemente lo sea.

## Requisitos

Un navegador moderno con WebGL2 (Chrome o Edge actualizados). Con gráficos integrados, el juego baja la resolución
interna solo para mantener la fluidez. En Opciones (menú de pausa) hay un preajuste de calidad.
