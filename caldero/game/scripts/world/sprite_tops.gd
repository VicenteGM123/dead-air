class_name SpriteTops
## --- R6 PERF: filas precalculadas de los sprites de personajes (generado por tools/perf/sprite_tops.py; no editar a
## mano). TOP: primera fila con algún píxel visible de la hoja idle (Actor.top_height). HEAD: primera fila con alfa >= 0.5
## del primer cuadro entre x = 8 y el ancho del cuadro - 8 (la cara del ticket, de las tarjetas y de la bola).
## Leerlas aquí evita get_image(): en la web es un readPixels que espera a la tarjeta gráfica (un tirón por personaje).
## Un sprite que no esté en la tabla se mide una vez en tiempo de juego (top_of / head_of) y se guarda.

const TOP := {
	"aldric": 28, "alquimista": 17, "alumna_azul": 30, "alumna_roja": 30, "alumna_verde": 29, "alumno_azul": 33,
	"alumno_rojo": 27, "alumno_violeta": 35, "anciano": 31, "anselmo": 21, "borin": 44, "bram": 44, "brann": 17,
	"elda": 30, "fizz": 47, "granjero": 26, "grumm": 17, "hassim": 27, "ilse": 29, "isolde": 22, "kit": 47,
	"lirien": 27, "lupo": 20, "mabel": 33, "marta": 31, "miga": 54, "nyra": 25, "panadera": 31, "pip": 46,
	"ragnar": 19, "roxa": 17, "sylwen": 29, "tobias": 27, "vianne": 21, "wren": 30, "zaria": 29
}

const HEAD := {
	"aldric": 28, "alquimista": 17, "alumna_azul": 30, "alumna_roja": 30, "alumna_verde": 29, "alumno_azul": 33,
	"alumno_rojo": 27, "alumno_violeta": 35, "anciano": 31, "anselmo": 21, "borin": 44, "bram": 44, "brann": 17,
	"elda": 30, "fizz": 47, "granjero": 26, "grumm": 17, "hassim": 27, "ilse": 29, "isolde": 22, "kit": 47,
	"lirien": 27, "lupo": 20, "mabel": 33, "marta": 31, "miga": 54, "nyra": 25, "panadera": 31, "pip": 46,
	"ragnar": 19, "roxa": 17, "sylwen": 29, "tobias": 27, "vianne": 21, "wren": 30, "zaria": 29
}

static var _top_cache := {}
static var _head_cache := {}

## La primera fila visible de la hoja idle de `sid` (alfa > 0). tex: su textura idle (solo si no está en la tabla).
static func top_of(sid: String, tex: Texture2D) -> int:
	if TOP.has(sid):
		return int(TOP[sid])
	if not _top_cache.has(sid):
		var img := tex.get_image() if tex else null
		if img and img.is_compressed():
			img.decompress()
		_top_cache[sid] = img.get_used_rect().position.y if img else 0
	return int(_top_cache[sid])

## La fila donde empieza la cara (alfa >= 0.5 en el primer cuadro, entre x = 8 y el ancho del cuadro - 8). 6 si no se puede medir.
static func head_of(sid: String, tex: Texture2D) -> int:
	if HEAD.has(sid):
		return int(HEAD[sid])
	if not _head_cache.has(sid):
		var top := 6
		var img := tex.get_image() if tex else null
		if img:
			if img.is_compressed():
				img.decompress()
			var fw := img.get_width() / 2
			top = -1
			for y in img.get_height():
				for x in range(8, fw - 8):
					if img.get_pixel(x, y).a > 0.5:
						top = y
						break
				if top >= 0:
					break
			top = maxi(0, top)
		_head_cache[sid] = top
	return int(_head_cache[sid])
