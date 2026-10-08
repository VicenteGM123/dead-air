class_name Data
## Balance and content tables. Everything tunable lives here.

const START_COINS := 24
const NIGHTS := 7
const HERO_RESPAWN := 6.0 # seconds; +1 for every earlier fall in the same night, up to HERO_RESPAWN_MAX
const HERO_RESPAWN_MAX := 10.0

## Economy: a new house, olive grove or pier pays for itself in a dawn and a half (upgrades in about three), so the
## island fills up night after night, but only if it survives: a building razed at night pays nothing that dawn.
## "built" is the word the toast uses when it rises (Spanish gender of its name).
const BUILDINGS := {
	"pharos": {
		"name": "Faro",
		"built": "",
		"levels": [
			{"cost": 0, "hp": 650, "income": 8, "desc": "El corazón de la isla. Si su llama se apaga, todo termina."},
			{"cost": 16, "hp": 900, "income": 14, "desc": "Aviva la llama: más vida, más tributo y la luz alcanza nuevos solares."},
			{"cost": 30, "hp": 1200, "income": 20, "desc": "Faro de tres cuerpos: aún más vida y tributo, y los últimos solares."},
		],
	},
	"house": {
		"name": "Casa",
		"built": "construida",
		"levels": [
			{"cost": 6, "hp": 80, "income": 4, "desc": "Una familia de pescadores. +4 dracmas cada amanecer."},
			{"cost": 10, "hp": 110, "income": 7, "desc": "Segundo piso y pérgola. +7 dracmas cada amanecer."},
		],
	},
	"farm": {
		"name": "Olivar",
		"built": "construido",
		"levels": [
			{"cost": 10, "hp": 90, "income": 6, "desc": "Olivos y una prensa. +6 dracmas cada amanecer."},
			{"cost": 14, "hp": 120, "income": 10, "desc": "Más olivos y ánforas. +10 dracmas cada amanecer."},
		],
	},
	"dock": {
		"name": "Muelle",
		"built": "construido",
		"levels": [
			{"cost": 8, "hp": 80, "income": 5, "desc": "Barcas de pesca. +5 dracmas cada amanecer."},
			{"cost": 12, "hp": 110, "income": 8, "desc": "Muelle más largo y otra barca. +8 dracmas cada amanecer."},
		],
	},
	"tower": {
		"name": "Torre de arqueros",
		"built": "construida",
		"levels": [
			{"cost": 7, "hp": 150, "range": 13.0, "dmg": 7.0, "rate": 1.05, "shots": 1, "desc": "Un arquero dispara a las criaturas cercanas."},
			{"cost": 12, "hp": 210, "range": 15.0, "dmg": 10.0, "rate": 0.85, "shots": 1, "desc": "Piedra y mejor arco: más alcance y daño."},
			{"cost": 18, "hp": 280, "range": 17.0, "dmg": 12.0, "rate": 0.7, "shots": 2, "desc": "Torre de mármol: dos flechas por disparo."},
		],
	},
	"wall": {
		"name": "Muralla",
		"built": "construida",
		"levels": [
			{"cost": 4, "hp": 160, "desc": "Empalizada: las criaturas que caminan deben derribarla para pasar."},
			{"cost": 8, "hp": 420, "desc": "Muralla de piedra, mucho más resistente."},
		],
	},
	"barracks": {
		"name": "Cuartel",
		"built": "construido",
		"levels": [
			{"cost": 10, "hp": 150, "soldiers": 2, "s_hp": 90.0, "s_dmg": 10.0, "desc": "Dos hoplitas defienden el camino."},
			{"cost": 15, "hp": 210, "soldiers": 3, "s_hp": 130.0, "s_dmg": 14.0, "desc": "Tres hoplitas veteranos."},
		],
	},
}

const ECONOMY := ["pharos", "house", "farm", "dock"]

const ENEMIES := {
	"shade": {"name": "Sombra", "hp": 34.0, "speed": 2.3, "dmg": 6.0, "rate": 1.15, "range": 1.2, "radius": 0.45, "aggro": 4.5},
	"ker": {"name": "Ker", "hp": 16.0, "speed": 4.1, "dmg": 4.0, "rate": 0.8, "range": 1.1, "radius": 0.4, "aggro": 6.0, "flying": true},
	"shielded": {"name": "Escudado", "hp": 75.0, "speed": 1.8, "dmg": 10.0, "rate": 1.3, "range": 1.35, "radius": 0.55, "aggro": 4.0, "arrow_resist": 0.5},
	"archer": {"name": "Arquero de Nyx", "hp": 24.0, "speed": 2.1, "dmg": 6.0, "rate": 1.9, "range": 9.0, "radius": 0.45, "aggro": 10.0, "ranged": true},
	"cyclops": {"name": "Cíclope de sombra", "hp": 320.0, "speed": 1.35, "dmg": 28.0, "rate": 2.4, "range": 2.1, "radius": 1.1, "aggro": 6.0, "building_mult": 1.7, "aoe": 2.3, "heavy": true},
	"hydra": {"name": "Hidra de la Noche", "hp": 3200.0, "speed": 1.0, "dmg": 34.0, "rate": 2.6, "range": 4.2, "radius": 2.4, "aggro": 9.0, "building_mult": 1.5, "boss": true, "heavy": true,
		# Bite: a violet ring marks where the head will land; it lands `bite_at` s later (the rig's contact frame),
		# 3 m wide, softer on Fanós (he is meant to dodge it, not to tank it). Spit: three orbs, one per head.
		"bite_at": 0.66, "bite_radius": 3.0, "hero_mult": 0.7, "spit_dmg": 18.0},
}

## Each night: list of [seconds from nightfall, lane index, {type: count}]. Lanes: 0 south, 1 east, 2 west, 3 north.
## Ramp: night 1 teaches on the southern beach; night 2 sends Keres over Fanós' head at the village (a tower is the
## answer); on night 3 the south and the east land at the same time, so one beach must hold without Fanós (the east
## needs the lighthouse at level 2). The west opens on night 4, the north on night 5 (level 3); night 6 is the peak
## and night 7 the Hydra.
const NIGHT_WAVES := [
	# 1 · Sombras por el sur.
	[[2.0, 0, {"shade": 3}], [16.0, 0, {"shade": 3}], [30.0, 0, {"shade": 4}]],
	# 2 · Llegan las Keres: vuelan sobre Fanós y las murallas hacia la aldea; el primer arquero.
	[[2.0, 0, {"shade": 4}], [12.0, 0, {"shade": 5, "archer": 1}], [16.0, 0, {"ker": 4}], [30.0, 0, {"shade": 5}],
		[34.0, 0, {"ker": 3}], [44.0, 0, {"shade": 4}]],
	# 3 · Se abre la Cala del Este a la vez que el sur: un frente queda para las torres. Primeros Escudados.
	[[2.0, 0, {"shade": 4}], [2.0, 1, {"shade": 4}], [14.0, 1, {"ker": 4, "shade": 2}], [20.0, 0, {"shade": 3, "shielded": 1, "archer": 1}],
		[32.0, 1, {"shade": 4, "archer": 2}], [32.0, 0, {"ker": 4, "shade": 3}], [44.0, 0, {"shielded": 1, "shade": 4}], [44.0, 1, {"shade": 3}]],
	# 4 · Se abre el oeste; el primer Cíclope.
	[[2.0, 2, {"shade": 5}], [6.0, 0, {"shade": 5, "shielded": 1}], [13.0, 1, {"shade": 5, "archer": 2}], [22.0, 2, {"shade": 4, "ker": 5}],
		[32.0, 0, {"cyclops": 1, "shade": 4}], [36.0, 1, {"ker": 3}], [42.0, 1, {"shade": 5, "shielded": 2}], [52.0, 2, {"shade": 4, "archer": 2}]],
	# 5 · Se abre el norte: cuatro frentes y tres Cíclopes.
	[[2.0, 3, {"shade": 6}], [5.0, 0, {"shade": 6, "archer": 2}], [11.0, 1, {"shade": 6, "shielded": 2}], [18.0, 2, {"ker": 6, "shade": 4}],
		[20.0, 1, {"cyclops": 1, "shade": 3}], [27.0, 3, {"shade": 5, "shielded": 2, "archer": 2}], [36.0, 0, {"cyclops": 1, "shade": 5}],
		[45.0, 1, {"shade": 5, "ker": 5}], [54.0, 2, {"cyclops": 1, "shielded": 2, "shade": 3}]],
	# 6 · La noche más larga: todo a la vez.
	[[2.0, 0, {"shade": 8, "archer": 2}], [4.0, 1, {"shade": 7, "shielded": 2}], [10.0, 2, {"ker": 6, "shade": 5}], [16.0, 3, {"shade": 7, "archer": 3}],
		[26.0, 0, {"cyclops": 1, "shielded": 3, "shade": 3}], [32.0, 2, {"cyclops": 1, "shade": 6}], [40.0, 1, {"cyclops": 1, "ker": 5, "shade": 3}],
		[50.0, 3, {"shielded": 3, "archer": 3, "shade": 3}], [60.0, 0, {"shade": 8, "ker": 4}]],
	# 7 · La Hidra de la Noche sale por el sur; su prole llega por las otras playas (menos que en la noche 6: la
	#     protagonista es ella).
	[[3.0, 0, {"hydra": 1}], [8.0, 1, {"shade": 6, "ker": 3}], [15.0, 2, {"shade": 6, "archer": 2}], [25.0, 3, {"shielded": 3, "shade": 5}],
		[38.0, 1, {"cyclops": 1, "shade": 5}], [50.0, 2, {"shielded": 2, "ker": 4, "shade": 2}], [62.0, 3, {"cyclops": 1, "archer": 2, "shade": 2}]],
]

## Creatures grow tougher as the nights go on (health multiplier per night; the Hydra keeps its own).
const NIGHT_HP := [1.0, 1.0, 1.0, 1.1, 1.3, 1.5, 1.25]

const BLESSINGS := {
	"zeus": {"god": "Zeus", "title": "Ira del cielo", "desc": "El Haz del Faro se carga un 35 % más rápido y quema un 50 % más.", "icon": "bolt", "color": Color("F2C14E")},
	"poseidon": {"god": "Poseidón", "title": "Mareas", "desc": "Las criaturas que salen del mar avanzan un 45 % más lentas durante 6 segundos.", "icon": "trident", "color": Color("4FD6CF")},
	"athena": {"god": "Atenea", "title": "Égida", "desc": "Todos tus edificios tienen un 30 % más de vida.", "icon": "owl", "color": Color("B9C3D6")},
	"artemis": {"god": "Artemisa", "title": "Ojo de cazadora", "desc": "Las torres disparan un 25 % más rápido y alcanzan 2 m más lejos.", "icon": "bow", "color": Color("C9E3A0")},
	"apollo": {"god": "Apolo", "title": "Luz sanadora", "desc": "+40 de vida máxima y te curas mucho más rápido fuera de combate.", "icon": "sun", "color": Color("FFD27A")},
	"hermes": {"god": "Hermes", "title": "Sandalias aladas", "desc": "Fanós corre un 20 % más rápido y su embestida de vapor llega un 30 % más lejos y se recarga antes.", "icon": "wing", "color": Color("E9E2D0")},
	"ares": {"god": "Ares", "title": "Furia", "desc": "El ancla y el destello de la lente hacen un 30 % más de daño.", "icon": "spear", "color": Color("E86A5A")},
	"hephaestus": {"god": "Hefesto", "title": "Forja divina", "desc": "Las murallas tienen un 60 % más de vida y las torres hacen un 20 % más de daño.", "icon": "hammer", "color": Color("E39A57")},
	"demeter": {"god": "Deméter", "title": "Cosecha", "desc": "Cada olivar y cada muelle dan 4 dracmas más al amanecer.", "icon": "wheat", "color": Color("E5C76B")},
	"hestia": {"god": "Hestia", "title": "Hogar", "desc": "Cada casa da 2 dracmas más y el Faro tiene un 25 % más de vida.", "icon": "flame", "color": Color("FFB25A")},
}

## Llama: favor_per_dmg per point of damage dealt, but one swing counts at most favor_swing_cap times its own
## damage (a sweep through a crowd fills it faster, not ten times faster) and blows on the Hydra count favor_boss
## times; a lens flash that stuns adds favor_flash. Aim: about 3-5 beams on the late nights.
const HERO := {
	"hp": 130.0, "speed": 6.0, "combo": [13.0, 13.0, 24.0], "bash_dmg": 10.0, "bash_cd": 4.0, "dodge_cd": 0.75,
	"favor_max": 100.0, "favor_per_dmg": 0.24, "favor_swing_cap": 1.5, "favor_boss": 0.6, "favor_flash": 4.0, "beam_dmg": 70.0, "beam_radius": 10.0,
}


static func building_level(type: String, level: int) -> Dictionary:
	var lv: Array = BUILDINGS[type]["levels"]
	return lv[clampi(level - 1, 0, lv.size() - 1)]


static func max_level(type: String) -> int:
	return (BUILDINGS[type]["levels"] as Array).size()


static func night_hp_mult(n: int) -> float:
	return float(NIGHT_HP[clampi(n - 1, 0, NIGHT_HP.size() - 1)])


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
