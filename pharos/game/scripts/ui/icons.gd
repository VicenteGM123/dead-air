class_name Icons
## Minimal vector icons drawn with CanvasItem calls, so the UI stays crisp at any resolution and needs no
## image assets. Icons are designed on a 0..1 square.

static func draw(ci: CanvasItem, icon: String, r: Rect2, col: Color) -> void:
	var s := minf(r.size.x, r.size.y)
	var o := r.position + (r.size - Vector2(s, s)) * 0.5
	var p := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s
	var w := maxf(1.5, s * 0.07)
	match icon:
		"coin":
			ci.draw_circle(p.call(0.5, 0.5), s * 0.42, col)
			ci.draw_arc(p.call(0.5, 0.5), s * 0.3, 0.0, TAU, 28, col.darkened(0.3), maxf(1.2, s * 0.05), true)
			ci.draw_line(p.call(0.5, 0.33), p.call(0.5, 0.67), col.darkened(0.3), maxf(1.2, s * 0.06), true)
		"sun":
			ci.draw_circle(p.call(0.5, 0.5), s * 0.2, col)
			for i in 8:
				var a := TAU * float(i) / 8.0
				var d := Vector2(cos(a), sin(a))
				ci.draw_line(p.call(0.5, 0.5) + d * s * 0.3, p.call(0.5, 0.5) + d * s * 0.45, col, w, true)
		"moon":
			ci.draw_circle(p.call(0.5, 0.5), s * 0.38, col)
			ci.draw_circle(p.call(0.64, 0.4), s * 0.32, Color(0, 0, 0, 0))
			_crescent(ci, p.call(0.5, 0.5), s * 0.38, col)
		"flame":
			var pts := PackedVector2Array()
			for i in 24:
				var t := float(i) / 23.0
				var a := lerpf(-PI * 0.5, PI * 1.5, t)
				var rr := s * 0.3 * (1.0 - 0.55 * pow(maxf(0.0, -sin(a)), 3.0))
				var q := p.call(0.5, 0.62) + Vector2(cos(a) * rr, sin(a) * rr * 1.1)
				if sin(a) < -0.6:
					q = p.call(0.5, 0.62) + Vector2(cos(a) * rr * 0.6, -s * 0.48)
				pts.append(q)
			ci.draw_colored_polygon(_flame_pts(o, s), col)
		"heart":
			ci.draw_circle(p.call(0.35, 0.38), s * 0.18, col)
			ci.draw_circle(p.call(0.65, 0.38), s * 0.18, col)
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.18, 0.46), p.call(0.82, 0.46), p.call(0.5, 0.85)]), col)
		"bolt":
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.58, 0.05), p.call(0.22, 0.55), p.call(0.47, 0.55), p.call(0.38, 0.95), p.call(0.78, 0.4), p.call(0.53, 0.4)]), col)
		"beam":
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.3, 0.42), p.call(0.95, 0.15), p.call(0.95, 0.85), p.call(0.3, 0.58)]), Color(col.r, col.g, col.b, col.a * 0.55))
			ci.draw_rect(Rect2(p.call(0.12, 0.3), Vector2(s * 0.2, s * 0.4)), col)
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.1, 0.3), p.call(0.22, 0.12), p.call(0.34, 0.3)]), col)
		"trident":
			ci.draw_line(p.call(0.5, 0.2), p.call(0.5, 0.95), col, w, true)
			ci.draw_line(p.call(0.25, 0.35), p.call(0.75, 0.35), col, w, true)
			for x in [0.25, 0.5, 0.75]:
				ci.draw_colored_polygon(PackedVector2Array([p.call(x - 0.07, 0.36), p.call(x, 0.08), p.call(x + 0.07, 0.36)]), col)
		"owl":
			ci.draw_circle(p.call(0.5, 0.58), s * 0.3, col)
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.22, 0.4), p.call(0.28, 0.15), p.call(0.42, 0.33)]), col)
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.78, 0.4), p.call(0.72, 0.15), p.call(0.58, 0.33)]), col)
			ci.draw_circle(p.call(0.39, 0.5), s * 0.09, col.darkened(0.6))
			ci.draw_circle(p.call(0.61, 0.5), s * 0.09, col.darkened(0.6))
		"bow":
			ci.draw_arc(p.call(0.3, 0.5), s * 0.42, -PI * 0.42, PI * 0.42, 20, col, w, true)
			ci.draw_line(p.call(0.43, 0.12), p.call(0.43, 0.88), col, maxf(1.0, w * 0.5), true)
			ci.draw_line(p.call(0.2, 0.5), p.call(0.92, 0.5), col, w * 0.8, true)
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.92, 0.5), p.call(0.8, 0.42), p.call(0.8, 0.58)]), col)
		"wing":
			for i in 4:
				var y := 0.3 + i * 0.12
				ci.draw_line(p.call(0.2, 0.75), p.call(0.85 - i * 0.12, y - 0.1), col, w, true)
		"spear":
			ci.draw_line(p.call(0.18, 0.82), p.call(0.72, 0.28), col, w, true)
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.68, 0.22), p.call(0.88, 0.12), p.call(0.78, 0.32)]), col)
		"anchor":
			ci.draw_line(p.call(0.5, 0.18), p.call(0.5, 0.86), col, w, true)
			ci.draw_line(p.call(0.32, 0.32), p.call(0.68, 0.32), col, w, true)
			ci.draw_arc(p.call(0.5, 0.15), s * 0.08, 0.0, TAU, 14, col, w * 0.8, true)
			ci.draw_arc(p.call(0.5, 0.55), s * 0.32, PI * 0.15, PI * 0.85, 18, col, w, true)
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.14, 0.62), p.call(0.22, 0.5), p.call(0.28, 0.68)]), col)
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.86, 0.62), p.call(0.78, 0.5), p.call(0.72, 0.68)]), col)
		"hammer":
			ci.draw_line(p.call(0.3, 0.85), p.call(0.6, 0.35), col, w, true)
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.42, 0.14), p.call(0.86, 0.36), p.call(0.76, 0.54), p.call(0.32, 0.32)]), col)
		"wheat":
			ci.draw_line(p.call(0.5, 0.95), p.call(0.5, 0.15), col, w * 0.8, true)
			for i in 4:
				var y := 0.22 + i * 0.15
				ci.draw_colored_polygon(PackedVector2Array([p.call(0.5, y), p.call(0.3, y - 0.08), p.call(0.36, y + 0.06)]), col)
				ci.draw_colored_polygon(PackedVector2Array([p.call(0.5, y), p.call(0.7, y - 0.08), p.call(0.64, y + 0.06)]), col)
		"house":
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.12, 0.48), p.call(0.5, 0.14), p.call(0.88, 0.48)]), col)
			ci.draw_rect(Rect2(p.call(0.22, 0.48), Vector2(s * 0.56, s * 0.38)), col)
		"tower":
			ci.draw_rect(Rect2(p.call(0.3, 0.3), Vector2(s * 0.4, s * 0.58)), col)
			for i in 3:
				ci.draw_rect(Rect2(p.call(0.26 + i * 0.17, 0.14), Vector2(s * 0.12, s * 0.16)), col)
		"wall":
			for row in 2:
				for i in 3:
					ci.draw_rect(Rect2(p.call(0.1 + i * 0.28 + (0.14 if row == 1 else 0.0), 0.4 + row * 0.22), Vector2(s * 0.24, s * 0.18)), col)
		"barracks":
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.1, 0.4), p.call(0.5, 0.15), p.call(0.9, 0.4)]), col)
			for i in 4:
				ci.draw_rect(Rect2(p.call(0.16 + i * 0.2, 0.44), Vector2(s * 0.08, s * 0.4)), col)
		"farm":
			ci.draw_circle(p.call(0.5, 0.38), s * 0.26, col)
			ci.draw_line(p.call(0.5, 0.6), p.call(0.5, 0.9), col, w, true)
		"dock":
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.12, 0.55), p.call(0.88, 0.55), p.call(0.72, 0.78), p.call(0.28, 0.78)]), col)
			ci.draw_line(p.call(0.5, 0.55), p.call(0.5, 0.12), col, w * 0.8, true)
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.53, 0.15), p.call(0.8, 0.48), p.call(0.53, 0.48)]), col)
		"pharos":
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.36, 0.9), p.call(0.42, 0.34), p.call(0.58, 0.34), p.call(0.64, 0.9)]), col)
			ci.draw_rect(Rect2(p.call(0.36, 0.26), Vector2(s * 0.28, s * 0.08)), col)
			ci.draw_colored_polygon(_flame_pts(o + Vector2(s * 0.3, -s * 0.06), s * 0.4), col)
		"horn":
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.12, 0.46), p.call(0.62, 0.42), p.call(0.88, 0.2), p.call(0.88, 0.8), p.call(0.62, 0.58), p.call(0.12, 0.54)]), col)
		"crescent":
			_crescent(ci, p.call(0.5, 0.5), s * 0.4, col)
		"skull", "enemy":
			# A shade's hood with two eyes (used for "creatures remaining").
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.5, 0.06), p.call(0.82, 0.42), p.call(0.78, 0.92), p.call(0.22, 0.92), p.call(0.18, 0.42)]), col)
			ci.draw_line(p.call(0.33, 0.52), p.call(0.45, 0.56), col.darkened(0.75), w, true)
			ci.draw_line(p.call(0.67, 0.52), p.call(0.55, 0.56), col.darkened(0.75), w, true)
		"chevron":
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.2, 0.15), p.call(0.85, 0.5), p.call(0.2, 0.85), p.call(0.38, 0.5)]), col)
		_:
			ci.draw_circle(p.call(0.5, 0.5), s * 0.3, col)


static func _crescent(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	var n := 24
	for i in n + 1:
		var a := lerpf(PI * 0.35, PI * 1.65, float(i) / n)
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	for i in n + 1:
		var a := lerpf(PI * 1.5, PI * 0.5, float(i) / n)
		pts.append(c + Vector2(r * 0.42, 0) + Vector2(cos(a) * r * 0.72, sin(a) * r * 0.86))
	ci.draw_colored_polygon(pts, col)


static func _flame_pts(o: Vector2, s: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := 20
	for i in n:
		var t := float(i) / n
		var a := TAU * t
		# Teardrop: round bottom, pointed top.
		var x := sin(a) * 0.28 * (1.0 - 0.45 * pow(0.5 + 0.5 * cos(a), 2.0))
		var y := -cos(a) * 0.4
		if cos(a) > 0.0:
			y = -cos(a) * 0.4 - pow(cos(a), 4.0) * 0.12
		pts.append(o + Vector2(0.5 + x, 0.58 + y * 1.0) * s)
	return pts


## A keyboard / pad key cap with a label (e.g. "E").
static func keycap(ci: CanvasItem, r: Rect2, label: String, font: Font, col: Color, bg: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = Color(col.r, col.g, col.b, 0.75)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(int(r.size.y * 0.22))
	ci.draw_style_box(sb, r)
	var fs := int(r.size.y * 0.58)
	var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	ci.draw_string(font, Vector2(r.position.x + (r.size.x - tw) * 0.5, r.position.y + r.size.y * 0.5 + fs * 0.36), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
