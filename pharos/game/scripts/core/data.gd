class_name Data
## Balance and content tables. Everything tunable lives here.

const START_COINS := 14
const NIGHTS := 7
const HERO_RESPAWN := 7.0

const BUILDINGS := {
	"pharos": {
		"name": "Faro",
		"levels": [
			{"cost": 0, "hp": 600, "income": 4, "desc": "El corazón de la isla. Si su llama se apaga, todo termina."},
			{"cost": 12, "hp": 850, "income": 5, "desc": "Aviva la llama: más vida y la luz alcanza nuevos solares."},
			{"cost": 22, "hp": 1150, "income": 6, "desc": "Faro de tres cuerpos: aún más vida y los últimos solares."},
		],
	},
	"house": {
		"name": "Casa",
		"levels": [
			{"cost": 4, "hp": 80, "income": 2, "desc": "Una familia de pescadores. +2 dracmas cada amanecer."},
			{"cost": 6, "hp": 110, "income": 3, "desc": "Segundo piso y pérgola. +3 dracmas cada amanecer."},
		],
	},
	"farm": {
		"name": "Olivar",
		"levels": [
			{"cost": 6, "hp": 90, "income": 3, "desc": "Olivos y una prensa. +3 dracmas cada amanecer."},
			{"cost": 8, "hp": 120, "income": 5, "desc": "Más olivos y ánforas. +5 dracmas cada amanecer."},
		],
	},
	"dock": {
		"name": "Muelle",
		"levels": [
			{"cost": 5, "hp": 80, "income": 3, "desc": "Barcas de pesca. +3 dracmas cada amanecer."},
			{"cost": 7, "hp": 110, "income": 4, "desc": "Muelle más largo y otra barca. +4 dracmas cada amanecer."},
		],
	},
	"tower": {
		"name": "Torre de arqueros",
		"levels": [
			{"cost": 6, "hp": 150, "range": 13.0, "dmg": 7.0, "rate": 1.05, "shots": 1, "desc": "Un arquero dispara a las criaturas cercanas."},
			{"cost": 10, "hp": 210, "range": 15.0, "dmg": 10.0, "rate": 0.85, "shots": 1, "desc": "Piedra y mejor arco: más alcance y daño."},
			{"cost": 16, "hp": 280, "range": 17.0, "dmg": 12.0, "rate": 0.7, "shots": 2, "desc": "Torre de mármol: dos flechas por disparo."},
		],
	},
	"wall": {
		"name": "Muralla",
		"levels": [
			{"cost": 3, "hp": 160, "desc": "Empalizada: las criaturas que caminan deben derribarla para pasar."},
			{"cost": 6, "hp": 420, "desc": "Muralla de piedra, mucho más resistente."},
		],
	},
	"barracks": {
		"name": "Cuartel",
		"levels": [
			{"cost": 8, "hp": 150, "soldiers": 2, "s_hp": 60.0, "s_dmg": 8.0, "desc": "Dos hoplitas defienden la zona."},
			{"cost": 12, "hp": 210, "soldiers": 3, "s_hp": 90.0, "s_dmg": 11.0, "desc": "Tres hoplitas veteranos."},
		],
	},
}

const ECONOMY := ["pharos", "house", "farm", "dock"]

const ENEMIES := {
	"shade": {"name": "Sombra", "hp": 30.0, "speed": 2.3, "dmg": 6.0, "rate": 1.15, "range": 1.2, "radius": 0.45, "aggro": 4.5},
	"ker": {"name": "Ker", "hp": 16.0, "speed": 4.1, "dmg": 4.0, "rate": 0.8, "range": 1.1, "radius": 0.35, "aggro": 6.0, "flying": true},
	"shielded": {"name": "Escudado", "hp": 75.0, "speed": 1.8, "dmg": 10.0, "rate": 1.3, "range": 1.35, "radius": 0.55, "aggro": 4.0, "arrow_resist": 0.5},
	"archer": {"name": "Arquero de Nyx", "hp": 24.0, "speed": 2.1, "dmg": 6.0, "rate": 1.9, "range": 9.0, "radius": 0.45, "aggro": 10.0, "ranged": true},
	"cyclops": {"name": "Cíclope de sombra", "hp": 280.0, "speed": 1.35, "dmg": 28.0, "rate": 2.4, "range": 2.1, "radius": 1.1, "aggro": 6.0, "building_mult": 2.0, "aoe": 2.3, "heavy": true},
	"hydra": {"name": "Hidra de la Noche", "hp": 2600.0, "speed": 0.9, "dmg": 34.0, "rate": 2.0, "range": 4.2, "radius": 2.4, "aggro": 9.0, "building_mult": 1.5, "boss": true, "heavy": true},
}

## Each night: list of [seconds from nightfall, lane index, {type: count}].
const NIGHT_WAVES := [
	[[2.0, 0, {"shade": 3}], [16.0, 0, {"shade": 4}]],
	[[2.0, 0, {"shade": 4}], [10.0, 1, {"shade": 3}], [24.0, 0, {"shade": 3, "ker": 2}], [33.0, 1, {"shade": 4}]],
	[[2.0, 2, {"shade": 4}], [9.0, 0, {"shade": 4, "archer": 1}], [19.0, 1, {"shade": 4, "ker": 3}], [31.0, 2, {"shade": 3, "shielded": 1}], [41.0, 0, {"shade": 5, "archer": 2}]],
	[[2.0, 0, {"shade": 5, "shielded": 2}], [10.0, 1, {"shade": 5, "archer": 2}], [20.0, 2, {"ker": 5, "shade": 3}], [34.0, 0, {"cyclops": 1, "shade": 4}], [45.0, 1, {"shielded": 2, "shade": 4}]],
	[[2.0, 3, {"shade": 5}], [8.0, 0, {"shade": 4, "shielded": 2, "archer": 2}], [18.0, 1, {"ker": 6}], [27.0, 2, {"shade": 6, "archer": 2}], [37.0, 3, {"cyclops": 1, "shade": 4}], [49.0, 0, {"cyclops": 1, "shielded": 3}]],
	[[2.0, 0, {"shade": 6, "archer": 2}], [6.0, 1, {"shade": 6, "shielded": 2}], [14.0, 2, {"ker": 6, "shade": 4}], [23.0, 3, {"shade": 6, "archer": 3}], [35.0, 0, {"cyclops": 1, "shielded": 3}], [42.0, 1, {"cyclops": 1, "ker": 5}], [53.0, 2, {"cyclops": 1, "shade": 6}], [62.0, 3, {"shielded": 4, "archer": 3}]],
	[[3.0, 0, {"hydra": 1}], [9.0, 1, {"shade": 5, "ker": 4}], [17.0, 2, {"shade": 5, "archer": 2}], [31.0, 3, {"shielded": 3, "shade": 4}], [46.0, 1, {"cyclops": 1, "shade": 4}]],
]

const BLESSINGS := {
	"zeus": {"god": "Zeus", "title": "Ira del cielo", "desc": "El Haz del Faro se carga un 35 % más rápido y quema un 50 % más.", "icon": "bolt", "color": Color("F2C14E")},
	"poseidon": {"god": "Poseidón", "title": "Mareas", "desc": "Las criaturas que salen del mar avanzan un 45 % más lentas durante 6 segundos.", "icon": "trident", "color": Color("4FD6CF")},
	"athena": {"god": "Atenea", "title": "Égida", "desc": "Todos tus edificios tienen un 30 % más de vida.", "icon": "owl", "color": Color("B9C3D6")},
	"artemis": {"god": "Artemisa", "title": "Ojo de cazadora", "desc": "Las torres disparan un 25 % más rápido y alcanzan 2 m más lejos.", "icon": "bow", "color": Color("C9E3A0")},
	"apollo": {"god": "Apolo", "title": "Luz sanadora", "desc": "+40 de vida máxima y te curas mucho más rápido fuera de combate.", "icon": "sun", "color": Color("FFD27A")},
	"hermes": {"god": "Hermes", "title": "Sandalias aladas", "desc": "Fanós se mueve un 20 % más rápido y la embestida de vapor se recarga un 40 % antes.", "icon": "wing", "color": Color("E9E2D0")},
	"ares": {"god": "Ares", "title": "Furia", "desc": "El ancla y el destello de la lente hacen un 30 % más de daño.", "icon": "spear", "color": Color("E86A5A")},
	"hephaestus": {"god": "Hefesto", "title": "Forja divina", "desc": "Las murallas tienen un 60 % más de vida y las torres hacen un 20 % más de daño.", "icon": "hammer", "color": Color("E39A57")},
	"demeter": {"god": "Deméter", "title": "Cosecha", "desc": "Cada olivar y cada muelle dan 2 dracmas más al amanecer.", "icon": "wheat", "color": Color("E5C76B")},
	"hestia": {"god": "Hestia", "title": "Hogar", "desc": "Cada casa da 1 dracma más y el Faro tiene un 25 % más de vida.", "icon": "flame", "color": Color("FFB25A")},
}

const HERO := {
	"hp": 130.0, "speed": 6.0, "combo": [13.0, 13.0, 24.0], "bash_dmg": 10.0, "bash_cd": 4.0, "dodge_cd": 0.75,
	"favor_max": 100.0, "beam_dmg": 70.0, "beam_radius": 10.0,
}


static func building_level(type: String, level: int) -> Dictionary:
	var lv: Array = BUILDINGS[type]["levels"]
	return lv[clampi(level - 1, 0, lv.size() - 1)]


static func max_level(type: String) -> int:
	return (BUILDINGS[type]["levels"] as Array).size()


static func night_lanes(n: int) -> Array:
	var out: Array = []
	if n < 1 or n > NIGHT_WAVES.size():
		return out
	for w in NIGHT_WAVES[n - 1]:
		if not out.has(w[1]):
			out.append(w[1])
	out.sort()
	return out


static func night_total(n: int) -> int:
	var c := 0
	if n < 1 or n > NIGHT_WAVES.size():
		return 0
	for w in NIGHT_WAVES[n - 1]:
		for k in w[2]:
			c += int(w[2][k])
	return c
