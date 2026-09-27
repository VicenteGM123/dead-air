# DEAD AIR

**Canal 13 WZTV, noche de Halloween de 1977, un minuto antes de medianoche.** La emisora no consigue cerrar la
emisión, y todos los que la estaban viendo se han quedado "sintonizados": el público del plató, el coro de calcetines
del programa infantil, el hombre del tiempo y los cámaras. Tú eres uno de los cuatro miembros del equipo que se
salvaron, porque *quien hace un programa nunca lo ve*.

Es un juego de zombis por rondas en tercera persona, con estética de dibujo animado setentero (cámara al hombro
estilo *Plants vs. Zombies: Garden Warfare*). Todo está hecho con código, en Three.js, y funciona en el navegador.

## Cómo jugar

1. Haz **doble clic en `index.html`**. Se abre en el navegador (Chrome o Edge recomendados) y no necesita
   servidor ni conexión.
2. La primera carga tarda un poco, porque se construye toda la emisora.
3. En la pantalla de título pulsa cualquier tecla. En el dial de la tele elige personaje con **A/D** (o la
   rueda del ratón) y sintonízalo con **E / Enter / Espacio**.
4. Haz clic en la ventana para capturar el ratón. **Esc** abre la pausa (opciones, controles y salir).

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
