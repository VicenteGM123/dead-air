#!/usr/bin/env python3
"""R6 PERF: escribe scripts/world/sprite_tops.gd con, para cada personaje (assets/chars/<id>_idle.png):
  TOP[id]  = la primera fila con algún píxel visible (alfa > 0) en toda la hoja idle (lo que Actor medía con
             get_image().get_used_rect().position.y);
  HEAD[id] = la primera fila con alfa >= 0.5 entre x = 8 y x = ancho_de_cuadro - 8 del primer cuadro (la cara que
             recortan el ticket del pedido, las tarjetas de los eventos y la bola de cristal).
Así nadie lee la textura de vuelta desde la tarjeta gráfica (en la web, get_image() es un readPixels que espera a la GPU).
Volver a correrlo cuando cambien los sprites:  python3 tools/perf/sprite_tops.py   (desde la carpeta game/; necesita pillow)
"""
import glob, os, sys
from PIL import Image

root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
tops, heads = {}, {}
for p in sorted(glob.glob(os.path.join(root, 'assets', 'chars', '*_idle.png'))):
    sid = os.path.basename(p)[:-len('_idle.png')]
    im = Image.open(p).convert('RGBA')
    a = im.getchannel('A')
    bb = a.getbbox()
    tops[sid] = bb[1] if bb else 0
    w, h = im.size
    fw = w // 2
    px = a.load()
    head = -1
    for y in range(h):
        if any(px[x, y] >= 128 for x in range(8, fw - 8)):
            head = y
            break
    heads[sid] = max(0, head)

def gd_dict(d):
    items = ['"%s": %d' % (k, v) for k, v in d.items()]
    lines, cur = [], ''
    for it in items:
        if len(cur) + len(it) + 2 > 110:
            lines.append(cur.rstrip())
            cur = ''
        cur += it + ', '
    lines.append(cur.rstrip().rstrip(','))
    return '{\n\t' + '\n\t'.join(lines) + '\n}'

out = os.path.join(root, 'scripts', 'world', 'sprite_tops.gd')
with open(out, 'w') as f:
    f.write('class_name SpriteTops\n')
    f.write('## --- R6 PERF: filas precalculadas de los sprites de personajes (generado por tools/perf/sprite_tops.py; no editar a\n')
    f.write('## mano). TOP: primera fila con algún píxel visible de la hoja idle (Actor.top_height). HEAD: primera fila con alfa >= 0.5\n')
    f.write('## del primer cuadro entre x = 8 y el ancho del cuadro - 8 (la cara del ticket, de las tarjetas y de la bola).\n')
    f.write('## Leerlas aquí evita get_image(): en la web es un readPixels que espera a la tarjeta gráfica (un tirón por personaje).\n')
    f.write('## Un sprite que no esté en la tabla se mide una vez en tiempo de juego (top_of / head_of) y se guarda.\n\n')
    f.write('const TOP := ' + gd_dict(tops) + '\n\n')
    f.write('const HEAD := ' + gd_dict(heads) + '\n\n')
    f.write('''static var _top_cache := {}
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
''')
print('wrote', out, len(tops), 'sprites')
