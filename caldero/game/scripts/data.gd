extends Node
## Datos fijos del juego: esencias, ingredientes, pociones, mejoras, clientes e historias.

const ESSENCE_ORDER := ["fuego", "escarcha", "vida", "sombra", "luz"]

const ESSENCES := {
	"fuego": {"name": "Fuego", "color": Color("ff7a45")},
	"escarcha": {"name": "Escarcha", "color": Color("7fd4ff")},
	"vida": {"name": "Vida", "color": Color("7ee08a")},
	"sombra": {"name": "Sombra", "color": Color("b48cff")},
	"luz": {"name": "Luz", "color": Color("ffd84d")},
}

const INGREDIENTS := {
	"raiz_mandragora": {"name": "Raíz de mandrágora", "ess": {"vida": 2, "sombra": 1}, "price": 3, "level": 0,
		"color": Color("c9a06b"), "desc": "Grita un poquito al arrancarla. Huele a tierra mojada."},
	"lagrima_sirena": {"name": "Lágrima de sirena", "ess": {"vida": 1, "escarcha": 1}, "price": 3, "level": 0,
		"color": Color("6fd6d0"), "desc": "La recogen los pescadores al amanecer, dentro de conchas abiertas."},
	"hongo_violeta": {"name": "Hongo violeta", "ess": {"sombra": 2, "luz": 1}, "price": 3, "level": 0,
		"color": Color("9a5ad6"), "desc": "Brilla tenue en lo más hondo del bosque."},
	"ambar_abeja": {"name": "Ámbar de abeja", "ess": {"luz": 2, "fuego": 1}, "price": 4, "level": 0,
		"color": Color("f0a632"), "desc": "Miel antigua endurecida por el sol de cien veranos."},
	"pluma_fenix": {"name": "Pluma de fénix", "ess": {"fuego": 2, "vida": 1}, "price": 6, "level": 1,
		"color": Color("ff6a3a"), "desc": "Sigue tibia aunque lleve años guardada."},
	"escarcha_luna": {"name": "Escarcha de luna", "ess": {"escarcha": 2, "sombra": 1}, "price": 6, "level": 2,
		"color": Color("a8e6ff"), "desc": "Solo se forma en las noches de luna llena."},
	"polvo_estrella": {"name": "Polvo de estrella", "ess": {"luz": 2, "vida": 1}, "price": 7, "level": 3,
		"color": Color("ffd84d"), "desc": "Cae en las colinas cuando pasa un cometa."},
	"ceniza_dragon": {"name": "Ceniza de dragón", "ess": {"fuego": 3}, "price": 10, "level": 4,
		"color": Color("e8452a"), "desc": "Regalo de un dragón viejo y muy educado."},
}

const INGREDIENT_ORDER := ["raiz_mandragora", "lagrima_sirena", "hongo_violeta", "ambar_abeja",
	"pluma_fenix", "escarcha_luna", "polvo_estrella", "ceniza_dragon"]

const POTIONS := {
	"elixir_alba": {"name": "Elixir del Alba", "pair": ["fuego", "vida"], "base": 18, "color": Color("ff7d4d"),
		"effect": "Devuelve el calor al cuerpo y cierra heridas."},
	"tonico_brio": {"name": "Tónico de Brío", "pair": ["fuego", "luz"], "base": 16, "color": Color("ffbf2e"),
		"effect": "Energía ardiente para los grandes esfuerzos."},
	"pocion_clima": {"name": "Poción de Clima", "pair": ["fuego", "escarcha"], "base": 24, "color": Color("e05aa8"),
		"effect": "Protege del frío y del calor más extremos."},
	"humo_furtivo": {"name": "Humo Furtivo", "pair": ["fuego", "sombra"], "base": 20, "color": Color("a8466e"),
		"effect": "Una nube de humo para desaparecer de golpe."},
	"balsamo_helado": {"name": "Bálsamo Helado", "pair": ["escarcha", "vida"], "base": 14, "color": Color("5fe0c0"),
		"effect": "Baja la fiebre y alivia las quemaduras."},
	"velo_invernal": {"name": "Velo Invernal", "pair": ["escarcha", "sombra"], "base": 18, "color": Color("6a7cff"),
		"effect": "Vuelve tus pasos silenciosos como la nieve."},
	"brebaje_lucido": {"name": "Brebaje Lúcido", "pair": ["escarcha", "luz"], "base": 16, "color": Color("8fe8ff"),
		"effect": "Mente fría y clara para pensar mejor."},
	"sueno_profundo": {"name": "Sueño Profundo", "pair": ["vida", "sombra"], "base": 12, "color": Color("9a6ae8"),
		"effect": "Un descanso hondo y reparador."},
	"vigor_verde": {"name": "Vigor Verde", "pair": ["vida", "luz"], "base": 12, "color": Color("9ae04a"),
		"effect": "Fuerza y salud renovadas."},
	"ojo_nocturno": {"name": "Ojo Nocturno", "pair": ["sombra", "luz"], "base": 14, "color": Color("4b5bd6"),
		"effect": "Permite ver en la oscuridad total."},
}

const POTION_ORDER := ["sueno_profundo", "balsamo_helado", "vigor_verde", "ojo_nocturno", "tonico_brio",
	"velo_invernal", "elixir_alba", "humo_furtivo", "brebaje_lucido", "pocion_clima"]

const LEVELS := [
	{"points": 0, "name": "Aprendiz"},
	{"points": 12, "name": "Boticaria"},
	{"points": 32, "name": "Alquimista"},
	{"points": 60, "name": "Maestra de pociones"},
	{"points": 95, "name": "Leyenda del valle"},
]

const LEVEL_REWARDS := {
	1: "Nuevo ingrediente en el mercado: Pluma de fénix.",
	2: "Nuevo ingrediente: Escarcha de luna. Además, llega un cliente más cada día.",
	3: "Nuevo ingrediente en el mercado: Polvo de estrella.",
	4: "Nuevo ingrediente en el mercado: Ceniza de dragón.",
}

const UPGRADES := {
	"cojin": {"name": "Cojín para Miga", "cost": 25, "level": 0,
		"desc": "Tu gata duerme más feliz. Acariciarla una vez al día te da suerte: +1 de potencia en la siguiente poción."},
	"alfombra": {"name": "Alfombra tejida", "cost": 35, "level": 0,
		"desc": "Los clientes se sienten en casa: +10% de propina."},
	"caldero_ancho": {"name": "Caldero ancho", "cost": 60, "level": 0,
		"desc": "Permite mezclar hasta 3 ingredientes."},
	"huerto": {"name": "Huerto en la ventana", "cost": 70, "level": 0,
		"desc": "Cada mañana cosechas 2 raíces de mandrágora y 2 lágrimas de sirena."},
	"estante": {"name": "Estante de pociones", "cost": 50, "level": 1,
		"desc": "Guardas hasta 12 pociones (antes 6)."},
	"campanilla": {"name": "Campanilla de la puerta", "cost": 90, "level": 1,
		"desc": "Su sonido se oye desde la plaza: llega 1 cliente más cada día."},
	"farolillos": {"name": "Farolillos de luciérnaga", "cost": 110, "level": 2,
		"desc": "Luz cálida para las noches y +15% de propina."},
	"caldero_cobre": {"name": "Caldero de cobre", "cost": 140, "level": 2,
		"desc": "Calienta parejo: +1 de potencia en todas tus pociones."},
}

const UPGRADE_ORDER := ["cojin", "alfombra", "caldero_ancho", "huerto", "estante", "campanilla", "farolillos", "caldero_cobre"]

# Personajes (sprite + nombre visible)
const CHARACTERS := {
	"lirien": {"name": "Lirien", "title": "maga elfa", "pixel": 0.04},
	"bram": {"name": "Bram", "title": "guerrero enano", "pixel": 0.04},
	"elda": {"name": "Sor Elda", "title": "sacerdotisa", "pixel": 0.04},
	"kit": {"name": "Kit", "title": "ladrona mediana", "pixel": 0.04},
	"aldric": {"name": "Sir Aldric", "title": "caballero novato", "pixel": 0.04},
	"wren": {"name": "Wren", "title": "exploradora", "pixel": 0.04},
	"granjero": {"name": "Tomás", "title": "granjero", "pixel": 0.04},
	"panadera": {"name": "Greta", "title": "panadera", "pixel": 0.04},
	"anciano": {"name": "Don Ruperto", "title": "vecino jubilado", "pixel": 0.04},
}

const HERO_ORDER := ["lirien", "bram", "elda", "kit", "aldric", "wren"]

# Historias de los aventureros: 3 capítulos cada uno.
const HEROES := {
	"lirien": [
		{"level": 0, "potion": "ojo_nocturno",
			"text": "Busco una flor que solo se abre de noche, en unas ruinas donde nunca llega la luna. Una vieja amiga decía que era la más bonita del mundo. Quiero comprobarlo.",
			"hint": "Algo que vea en la sombra… y que traiga un poco de luz.",
			"thanks": "La encontré. Hacía ochenta años que no veía ese color. Te traje una semilla, por si algún día quieres plantarla.",
			"journal": "Lirien buscó la flor nocturna que amaba una vieja amiga, en las ruinas de Alvenmoor. La encontró.",
			"gift": {"gold": 10}},
		{"level": 2, "potion": "brebaje_lucido",
			"text": "Quiero recordar la canción que mi amiga tarareaba al ver esa flor, pero mi memoria se nubla. Los elfos olvidamos despacio… pero olvidamos.",
			"hint": "Una mente fría, y clara como el día.",
			"thanks": "La recordé. Era una canción tonta sobre pan recién horneado. Era perfecta.",
			"journal": "Lirien recordó la canción de su amiga. Dice que los recuerdos también se pueden cuidar, como las plantas.",
			"gift": {"gold": 15}},
		{"level": 3, "potion": "sueno_profundo",
			"text": "Plantaré la semilla junto al río, donde ella descansa. Después quisiera dormir una noche entera sin soñar con el pasado. Solo una.",
			"hint": "Un poco de vida y un poco de sombra, para descansar.",
			"thanks": "Dormí como hace siglos. Volveré cuando florezca; quizá en diez años, quizá en cien. Guárdame un té.",
			"journal": "La flor de Lirien crece junto al río. Prometió volver cuando florezca, aunque pase un siglo.",
			"gift": {"gold": 30}},
	],
	"bram": [
		{"level": 0, "potion": "tonico_brio",
			"text": "¡Ja! Voy a subir la Montaña Gris a ver a mi hermano. Son tres días de escalones de piedra y mis rodillas ya no son lo que eran.",
			"hint": "¡Algo que arda por dentro! Y que me ilumine el camino.",
			"thanks": "¡Subí como un muchacho de doscientos años! Mi hermano casi se cae de la silla al verme.",
			"journal": "Bram subió la Montaña Gris para visitar a su hermano después de cuarenta años sin verse.",
			"gift": {"gold": 10}},
		{"level": 1, "potion": "elixir_alba",
			"text": "Mi hermano está enfermo. Tiene un frío metido en los huesos que no se le quita con nada, y una herida vieja que no cierra.",
			"hint": "Calor… y vida. Mucha vida.",
			"thanks": "Ya se levantó de la cama y me ganó a las pulseadas. ¡Desgraciado! Gracias, de verdad.",
			"journal": "El hermano de Bram se recuperó. Volvieron a discutir por todo, que es como se quieren los enanos.",
			"gift": {"gold": 15}},
		{"level": 2, "potion": "pocion_clima",
			"text": "Vamos a reabrir la vieja forja de nuestro padre. Pero allá arriba el fuego quema y la nieve muerde, todo en el mismo cuarto.",
			"hint": "Fuego y escarcha. ¡Las dos cosas a la vez, no me mires así!",
			"thanks": "La forja vuelve a sonar. Te forjamos esto entre los dos: una bolsa de monedas nuevas, con nuestro sello.",
			"journal": "Bram y su hermano reabrieron la forja familiar en la Montaña Gris. Te enviaron monedas recién acuñadas.",
			"gift": {"gold": 40}},
	],
	"elda": [
		{"level": 0, "potion": "balsamo_helado",
			"text": "Hay fiebre en el pueblo de Robledal. Los niños no pueden dormir del calor que tienen. ¿Podrías ayudarme?",
			"hint": "Algo frío como la escarcha, que también dé vida.",
			"thanks": "Las fiebres bajaron en dos días. Los niños te mandan dibujos. Este de aquí es tu gata, creo.",
			"journal": "Sor Elda curó la fiebre de Robledal con tu bálsamo. Los niños te dibujaron (y a tu gata).",
			"gift": {"gold": 8}},
		{"level": 1, "potion": "vigor_verde",
			"text": "Los campesinos de Robledal perdieron la cosecha mientras estaban enfermos. Quiero ayudarlos a sembrar antes del invierno.",
			"hint": "Vida y luz, como un día de primavera.",
			"thanks": "Sembramos todo el campo en una semana. Cantamos mucho. Desafinamos más.",
			"journal": "Robledal sembró a tiempo. Sor Elda dice que la tierra también sabe agradecer.",
			"gift": {"gold": 12}},
		{"level": 3, "potion": "elixir_alba",
			"text": "El viejo guardián del faro está muy débil y se acerca el invierno. Se niega a dejar su luz.",
			"hint": "Calor para el cuerpo, y vida.",
			"thanks": "El faro sigue encendido. Él dice que ahora ve barcos que no existen, pero que son muy bonitos.",
			"journal": "El guardián del faro pasó el invierno. Sor Elda lo visita cada semana y le lleva pan.",
			"gift": {"gold": 30}},
	],
	"kit": [
		{"level": 0, "potion": "velo_invernal",
			"text": "Shh. Necesito entrar en la mansión del barón sin que me oigan. No para robar, ¡para devolver! Le quitó el violín a la señora Mabel.",
			"hint": "Pasos de nieve… y un poco de sombra.",
			"thanks": "¡Lo logré! La señora Mabel tocó toda la noche. Muy mal, pero muy feliz.",
			"journal": "Kit devolvió el violín a la señora Mabel. El barón todavía no se da cuenta.",
			"gift": {"gold": 10}},
		{"level": 1, "potion": "humo_furtivo",
			"text": "El barón se dio cuenta. Necesito una salida rápida, por si acaso. Un por si acaso que va a pasar seguro.",
			"hint": "Humo: fuego y sombra.",
			"thanks": "¡Puf! Desaparecí frente a sus narices. Le dejé una nota: «Gracias por el violín».",
			"journal": "Kit escapó del barón en una nube de humo. Ahora es una leyenda en las tabernas.",
			"gift": {"gold": 15}},
		{"level": 2, "potion": "ojo_nocturno",
			"text": "Encontré el sótano del barón lleno de cosas robadas al pueblo. Está oscuro como boca de lobo. ¿Me ayudas una última vez?",
			"hint": "Para ver en lo oscuro: sombra y luz.",
			"thanks": "Devolvimos todo. Hasta un gallo. No preguntes por el gallo.",
			"journal": "El pueblo recuperó todo lo que el barón robó, gallo incluido. Kit dice que se retira (no le creas).",
			"gift": {"gold": 35}},
	],
	"aldric": [
		{"level": 0, "potion": "sueno_profundo",
			"text": "Mañana es mi primera misión como caballero y llevo tres noches sin dormir. ¿Es normal que a uno le tiemblen las rodillas dentro de la armadura?",
			"hint": "Algo de vida y algo de sombra, para dormir.",
			"thanks": "¡Dormí! La misión era rescatar a un gato de un árbol. Lo logré. Me arañó.",
			"journal": "Sir Aldric completó su primera misión: un gato en un árbol. Lleva sus arañazos con orgullo.",
			"gift": {"gold": 6}},
		{"level": 2, "potion": "brebaje_lucido",
			"text": "Me pidieron resolver los acertijos del troll del puente. No soy bueno con los acertijos. Ni con los trolls.",
			"hint": "Una mente fría… y luz para pensar.",
			"thanks": "¡Resolví los siete! El troll lloró de emoción. Ahora somos amigos. Se llama Pequeño.",
			"journal": "Sir Aldric resolvió los acertijos del troll Pequeño. Ahora toman té los domingos.",
			"gift": {"gold": 15}},
		{"level": 3, "potion": "vigor_verde",
			"text": "Pequeño y yo vamos a reconstruir el puente, que ya estaba muy viejo. Es mucho trabajo, incluso para un troll.",
			"hint": "Fuerza: vida y luz.",
			"thanks": "El puente quedó precioso. Le pusimos tu nombre a una piedra. Una piedra pequeña, pero tuya.",
			"journal": "El puente nuevo tiene una piedra con tu nombre. Sir Aldric ya no tiembla.",
			"gift": {"gold": 30}},
	],
	"wren": [
		{"level": 1, "potion": "elixir_alba",
			"text": "Voy a dibujar el mapa de los bosques del norte. Allá el frío muerde aunque lleves tres capas, y siempre termino rasguñada.",
			"hint": "Calor y vida, por favor.",
			"thanks": "Traje el primer mapa. Mira: marqué tu tienda con una estrellita.",
			"journal": "Wren cartografió los bosques del norte. Tu tienda aparece en su mapa con una estrellita.",
			"gift": {"gold": 12}},
		{"level": 2, "potion": "velo_invernal",
			"text": "Hay una manada de lobos blancos en el paso. No quiero hacerles daño, solo cruzar sin que me sientan.",
			"hint": "Silenciosa como la nieve, oscura como la noche.",
			"thanks": "Pasé entre ellos. Una loba me miró y me dejó seguir. Fue lo más bonito que he visto.",
			"journal": "Wren cruzó el paso de los lobos blancos. Dice que una loba la saludó con la cabeza.",
			"gift": {"gold": 15}},
		{"level": 3, "potion": "pocion_clima",
			"text": "Quiero llegar a la cima del Pico Estelar para ver la lluvia de cometas. Arriba hace un frío terrible, y a mediodía el sol quema.",
			"hint": "Fuego y escarcha, juntos.",
			"thanks": "Te traje polvo de cometa de la cima. Brillaba tanto que lloré un poquito.",
			"journal": "Wren vio la lluvia de cometas desde el Pico Estelar. Te regaló polvo de estrella.",
			"gift": {"gold": 10, "item": "polvo_estrella", "qty": 4}},
	],
}

# Pedidos de los vecinos (se repiten con variedad)
const VILLAGER_REQUESTS := [
	{"who": "panadera", "potion": "sueno_profundo", "text": "Hace tres noches que no duermo por los ronquidos de mi marido. ¡Parece un oso resfriado!", "hint": "Algo para dormir… vida y sombra, ¿no?"},
	{"who": "panadera", "potion": "balsamo_helado", "text": "Me quemé la mano sacando el pan del horno. ¡Me arde muchísimo!", "hint": "Algo fresquito que cure."},
	{"who": "panadera", "potion": "ojo_nocturno", "text": "Horneo antes del amanecer y se me acabaron las velas. No veo ni la harina.", "hint": "Algo para ver en la oscuridad."},
	{"who": "panadera", "potion": "vigor_verde", "text": "Tengo que amasar para la boda del pueblo: ¡trescientos panes! Mis brazos no darán abasto.", "hint": "Fuerza y salud: vida y luz."},
	{"who": "panadera", "potion": "humo_furtivo", "text": "El cobrador de impuestos viene mañana. ¿Tienes algo para… desaparecer un ratito?", "hint": "Humo: fuego y sombra."},
	{"who": "granjero", "potion": "vigor_verde", "text": "Mi buey está viejo y tengo que arar todo el campo yo solo.", "hint": "Fuerza: vida y luz."},
	{"who": "granjero", "potion": "tonico_brio", "text": "Mañana es la feria y tengo que cargar cien sacos de papas.", "hint": "Energía: fuego y luz."},
	{"who": "granjero", "potion": "balsamo_helado", "text": "Mi niña tiene fiebre desde ayer y no se le pasa.", "hint": "Algo frío que cure: escarcha y vida."},
	{"who": "granjero", "potion": "elixir_alba", "text": "Me pillé un resfrío tremendo cuidando las ovejas bajo la lluvia.", "hint": "Calor y vida."},
	{"who": "granjero", "potion": "pocion_clima", "text": "Mis tomates se queman de día y se hielan de noche. ¿Algo que los proteja?", "hint": "Fuego y escarcha, para equilibrar."},
	{"who": "anciano", "potion": "ojo_nocturno", "text": "Se me cayeron los lentes al pozo. ¡Y el pozo está oscurísimo!", "hint": "Para ver en lo oscuro: sombra y luz."},
	{"who": "anciano", "potion": "velo_invernal", "text": "Quiero salir a pasear sin que me vea la vecina. Me habla durante horas.", "hint": "Para pasar desapercibido: escarcha y sombra."},
	{"who": "anciano", "potion": "sueno_profundo", "text": "A mi edad, dormir de un tirón es un arte que se olvida.", "hint": "Vida y sombra, muchacha."},
	{"who": "anciano", "potion": "tonico_brio", "text": "Mi nieta me desafió a una carrera hasta el molino. No pienso perder.", "hint": "Algo que arda… y brille."},
	{"who": "anciano", "potion": "brebaje_lucido", "text": "Juego ajedrez con el alcalde cada domingo. En cuarenta años nunca le he ganado.", "hint": "Mente fría y clara: escarcha y luz."},
	{"who": "panadera", "potion": "brebaje_lucido", "text": "Tengo que sacar las cuentas del mes y los números me bailan.", "hint": "Algo para pensar claro."},
]

const WRONG_LINES := [
	"Mmm… creo que esto no es lo que necesito.",
	"Huele rico, pero no es lo que busco.",
	"¿Esto? No, no… pero gracias por intentarlo.",
]

const DECLINE_LINES := [
	"Entiendo. Volveré otro día.",
	"No te preocupes, quizá la próxima vez.",
]

const TUTORIAL_REQUEST := {"who": "panadera", "potion": "sueno_profundo",
	"text": "¡Buenos días, vecina! Hace tres noches que no duermo por los ronquidos de mi marido. ¿Tienes algo para dormir?",
	"hint": "Tu maestra dejó esa receta anotada en el libro: Sueño Profundo es vida y sombra."}

const TIMES_OF_DAY := ["Mañana", "Mediodía", "Tarde", "Atardecer", "Noche"]
