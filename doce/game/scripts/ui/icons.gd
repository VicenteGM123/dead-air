class_name Icons
## Minimal vector icons drawn with CanvasItem calls, so the UI stays crisp at any resolution and needs no image
## assets. Designed on a 0..1 square, flat, in one colour plus at most a lighter or darker tint of it. No faces:
## the Corinthian helmet shows only its dark eye slit, beasts only a glowing eye.

static func draw(ci: CanvasItem, icon: String, r: Rect2, col: Color) -> void:
	var s := minf(r.size.x, r.size.y)
	var o := r.position + (r.size - Vector2(s, s)) * 0.5
	var p := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s
	var w := maxf(1.5, s * 0.075)
	var dark := Color(0.075, 0.052, 0.042, col.a)
	var light := Color(col.lerp(Color.WHITE, 0.45), col.a)
	match icon:
		"helmet":
			# Corinthian helmet in profile (facing right), crest of horsehair arching over it.
			var crest := PackedVector2Array()
			for i in 15:
				var t := float(i) / 14.0
				crest.append(p.call(lerpf(0.2, 0.74, t), 0.34 - 0.3 * sin(PI * t) - 0.04 * t))
			for i in range(14, -1, -1):
				var t := float(i) / 14.0
				crest.append(p.call(lerpf(0.27, 0.68, t), 0.36 - 0.17 * sin(PI * t) - 0.02 * t))
			ci.draw_colored_polygon(crest, light)
			var shell := PackedVector2Array([p.call(0.24, 0.92), p.call(0.21, 0.7), p.call(0.25, 0.48), p.call(0.35, 0.33),
				p.call(0.5, 0.27), p.call(0.66, 0.3), p.call(0.77, 0.41), p.call(0.81, 0.53), p.call(0.79, 0.68),
				p.call(0.75, 0.8), p.call(0.69, 0.82), p.call(0.65, 0.74), p.call(0.6, 0.9), p.call(0.42, 0.95)])
			ci.draw_colored_polygon(shell, col)
			ci.draw_colored_polygon(_leaf(p.call(0.56, 0.53), p.call(0.79, 0.5), s * 0.045), dark)
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.655, 0.54), p.call(0.7, 0.54), p.call(0.685, 0.8), p.call(0.655, 0.79)]), dark)
			ci.draw_line(p.call(0.3, 0.62), p.call(0.48, 0.66), Color(dark, dark.a * 0.6), maxf(1.0, s * 0.03), true)
		"lion":
			# The lion's head in profile within a ruff of mane (the hood Heracles wins).
			var ruff := PackedVector2Array()
			var c: Vector2 = p.call(0.44, 0.52)
			for i in 48:
				var a := TAU * float(i) / 48.0
				var rr := s * (0.36 + 0.05 * pow(absf(sin(a * 6.0)), 0.6))
				ruff.append(c + Vector2(cos(a), sin(a)) * rr)
			ci.draw_colored_polygon(ruff, col)
			var head := PackedVector2Array([p.call(0.4, 0.36), p.call(0.6, 0.3), p.call(0.8, 0.38), p.call(0.92, 0.52),
				p.call(0.9, 0.64), p.call(0.76, 0.72), p.call(0.56, 0.74), p.call(0.42, 0.64)])
			ci.draw_colored_polygon(head, light)
			ci.draw_circle(p.call(0.66, 0.46), s * 0.04, dark)
			ci.draw_line(p.call(0.9, 0.6), p.call(0.7, 0.62), dark, maxf(1.0, s * 0.03), true)
		"sword":
			var blade := PackedVector2Array([p.call(0.5, 0.04), p.call(0.58, 0.22), p.call(0.57, 0.6), p.call(0.5, 0.66),
				p.call(0.43, 0.6), p.call(0.42, 0.22)])
			ci.draw_colored_polygon(blade, col)
			ci.draw_line(p.call(0.5, 0.1), p.call(0.5, 0.58), Color(dark, 0.5), maxf(1.0, s * 0.025), true)
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.3, 0.66), p.call(0.7, 0.66), p.call(0.66, 0.72), p.call(0.34, 0.72)]), col)
			ci.draw_rect(Rect2(p.call(0.465, 0.72), Vector2(s * 0.07, s * 0.16)), col)
			ci.draw_circle(p.call(0.5, 0.9), s * 0.055, col)
		"shield":
			ci.draw_circle(p.call(0.5, 0.5), s * 0.44, col)
			ci.draw_arc(p.call(0.5, 0.5), s * 0.36, 0.0, TAU, 36, Color(dark, 0.55), maxf(1.0, s * 0.04), true)
			ci.draw_circle(p.call(0.5, 0.5), s * 0.1, light)
		"chain":
			# The chain spear: a leaf blade on a shaft trailing three links.
			ci.draw_line(p.call(0.18, 0.82), p.call(0.66, 0.34), col, maxf(1.2, s * 0.06), true)
			ci.draw_colored_polygon(_leaf(p.call(0.6, 0.4), p.call(0.92, 0.08), s * 0.07), col)
			for i in 3:
				var c2: Vector2 = p.call(0.16 - 0.03 * i, 0.84 + 0.0 * i) + Vector2(-s * 0.1 * i, s * 0.04 * i)
				ci.draw_arc(c2, s * 0.06, 0.0, TAU, 14, col, maxf(1.0, s * 0.035), true)
		"altar":
			ci.draw_rect(Rect2(p.call(0.22, 0.6), Vector2(s * 0.56, s * 0.3)), col)
			ci.draw_rect(Rect2(p.call(0.16, 0.54), Vector2(s * 0.68, s * 0.08)), col)
			ci.draw_rect(Rect2(p.call(0.16, 0.88), Vector2(s * 0.68, s * 0.07)), col)
			_flame(ci, o, s, Vector2(0.5, 0.33), 0.38, col)
			_flame(ci, o, s, Vector2(0.5, 0.39), 0.18, light, true)
		"laurel":
			for side: float in [-1.0, 1.0]:
				for i in 6:
					var a := PI * 0.5 + side * (0.35 + float(i) * 0.38)
					var c3: Vector2 = p.call(0.5, 0.5) + Vector2(cos(a), sin(a)) * s * 0.34
					var tang := Vector2(-sin(a), cos(a)) * side
					ci.draw_colored_polygon(_leaf(c3 - tang * s * 0.02, c3 + tang * s * 0.16 + Vector2(cos(a), sin(a)) * s * 0.05, s * 0.045), col)
		"boat":
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.06, 0.6), p.call(0.94, 0.56), p.call(0.82, 0.74), p.call(0.2, 0.76)]), col)
			ci.draw_line(p.call(0.5, 0.58), p.call(0.5, 0.12), col, maxf(1.0, s * 0.04), true)
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.28, 0.18), p.call(0.72, 0.18), p.call(0.7, 0.5), p.call(0.3, 0.5)]), light)
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.94, 0.56), p.call(1.0, 0.44), p.call(0.97, 0.6)]), col)
		"sun":
			ci.draw_circle(p.call(0.5, 0.5), s * 0.19, col)
			for i in 12:
				var a := TAU * float(i) / 12.0 - PI * 0.5
				var d := Vector2(cos(a), sin(a))
				var n := Vector2(-d.y, d.x)
				var c0: Vector2 = p.call(0.5, 0.5)
				var r0 := s * 0.27
				var r1 := s * (0.47 if i % 2 == 0 else 0.38)
				var hw := s * (0.055 if i % 2 == 0 else 0.04)
				ci.draw_colored_polygon(PackedVector2Array([c0 + d * r0 + n * hw, c0 + d * r1, c0 + d * r0 - n * hw]), col)
		"moon":
			_crescent(ci, p.call(0.52, 0.5), s * 0.38, col)
		"flame":
			_flame(ci, o, s, Vector2(0.5, 0.5), 0.92, col)
			_flame(ci, o, s, Vector2(0.5, 0.64), 0.42, light, true)
		"heart":
			ci.draw_circle(p.call(0.35, 0.38), s * 0.18, col)
			ci.draw_circle(p.call(0.65, 0.38), s * 0.18, col)
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.18, 0.46), p.call(0.82, 0.46), p.call(0.5, 0.85)]), col)
		"cat":
			ci.draw_colored_polygon(_ellipse(p.call(0.5, 0.7), s * 0.24, s * 0.22, 20), col)
			ci.draw_circle(p.call(0.5, 0.38), s * 0.17, col)
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.35, 0.34), p.call(0.36, 0.12), p.call(0.49, 0.25)]), col)
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.65, 0.34), p.call(0.64, 0.12), p.call(0.51, 0.25)]), col)
			ci.draw_arc(p.call(0.8, 0.74), s * 0.13, -PI * 0.6, PI * 0.55, 12, col, w, true)
		"eye":
			# A beast's glowing eye (warnings).
			ci.draw_colored_polygon(_leaf(p.call(0.1, 0.52), p.call(0.9, 0.48), s * 0.2), col)
			ci.draw_circle(p.call(0.5, 0.5), s * 0.12, dark)
			ci.draw_circle(p.call(0.53, 0.47), s * 0.04, light)
		"chevron":
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.2, 0.15), p.call(0.85, 0.5), p.call(0.2, 0.85), p.call(0.38, 0.5)]), col)
		"pause":
			ci.draw_rect(Rect2(p.call(0.3, 0.24), Vector2(s * 0.13, s * 0.52)), col)
			ci.draw_rect(Rect2(p.call(0.57, 0.24), Vector2(s * 0.13, s * 0.52)), col)
		"stick", "stick_l", "stick_r":
			# Analogue stick seen from above, with its side letter.
			ci.draw_circle(p.call(0.5, 0.5), s * 0.47, Color(dark, 0.55 * col.a))
			ci.draw_arc(p.call(0.5, 0.5), s * 0.45, 0.0, TAU, 28, col, maxf(1.2, w * 0.7), true)
			ci.draw_circle(p.call(0.5, 0.5), s * 0.3, col)
			if icon != "stick":
				var f: Font = load("res://assets/fonts/Cinzel-Bold.ttf") if ResourceLoader.exists("res://assets/fonts/Cinzel-Bold.ttf") else ThemeDB.fallback_font
				var fs := maxi(7, int(s * 0.4))
				var t := "L" if icon == "stick_l" else "R"
				var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				ci.draw_string(f, p.call(0.5, 0.5) + Vector2(-tw * 0.5, fs * 0.36), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, dark)
		"dpad":
			ci.draw_rect(Rect2(p.call(0.38, 0.1), Vector2(s * 0.24, s * 0.8)), col)
			ci.draw_rect(Rect2(p.call(0.1, 0.38), Vector2(s * 0.8, s * 0.24)), col)
		"mouse_l", "mouse_r", "mouse_m", "mouse":
			var body := Rect2(p.call(0.26, 0.08), Vector2(s * 0.48, s * 0.84))
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0, 0, 0, 0)
			sb.border_color = col
			sb.set_border_width_all(maxi(1, int(s * 0.06)))
			sb.set_corner_radius_all(int(s * 0.24))
			sb.anti_aliasing = true
			ci.draw_style_box(sb, body)
			ci.draw_line(p.call(0.5, 0.1), p.call(0.5, 0.42), col, maxf(1.0, s * 0.05), true)
			ci.draw_line(p.call(0.28, 0.42), p.call(0.72, 0.42), col, maxf(1.0, s * 0.05), true)
			if icon == "mouse_l" or icon == "mouse_r":
				var x0 := 0.3 if icon == "mouse_l" else 0.52
				ci.draw_colored_polygon(PackedVector2Array([p.call(x0, 0.16), p.call(x0 + 0.18, 0.16), p.call(x0 + 0.18, 0.39), p.call(x0, 0.39)]), col)
			elif icon == "mouse_m":
				ci.draw_rect(Rect2(p.call(0.46, 0.16), Vector2(s * 0.08, s * 0.18)), col)
			else:
				for d: Vector2 in [Vector2(-1, 0), Vector2(1, 0)]:
					var tip: Vector2 = p.call(0.5, 0.66) + d * s * 0.5
					ci.draw_colored_polygon(PackedVector2Array([tip, tip - d * s * 0.12 + Vector2(0, s * 0.08), tip - d * s * 0.12 - Vector2(0, s * 0.08)]), col)
		"arrows":
			for d: Vector2 in [Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0)]:
				var c0: Vector2 = p.call(0.5, 0.5) + d * s * 0.3
				var n := Vector2(-d.y, d.x)
				ci.draw_colored_polygon(PackedVector2Array([c0 + d * s * 0.14, c0 + n * s * 0.12, c0 - n * s * 0.12]), col)
		"diamond":
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.5, 0.1), p.call(0.9, 0.5), p.call(0.5, 0.9), p.call(0.1, 0.5)]), col)
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


static func _ellipse(c: Vector2, rx: float, ry: float, n: int = 20) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * float(i) / n
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


## A pointed leaf (or grain, or almond eye) from `a` to `b`, `hw` wide at its middle.
static func _leaf(a: Vector2, b: Vector2, hw: float) -> PackedVector2Array:
	var d := b - a
	var n := Vector2(-d.y, d.x).normalized()
	var pts := PackedVector2Array()
	for i in 9:
		var t := float(i) / 8.0
		pts.append(a + d * t + n * hw * sin(t * PI))
	for i in range(7, 0, -1):
		var t := float(i) / 8.0
		pts.append(a + d * t - n * hw * sin(t * PI))
	return pts


## A flame centred at `c` (unit coords) of height `h` (fraction of the icon): round belly, tip leaning a little.
static func _flame(ci: CanvasItem, o: Vector2, s: float, c: Vector2, h: float, col: Color, inner: bool = false) -> void:
	var pts := PackedVector2Array()
	var n := 18
	var top := c.y - h * 0.5
	for side in [1.0, -1.0]:
		for j in n + 1:
			var i: int = j if side > 0.0 else n - j
			var u := float(i) / n
			var wdt := h * (0.3 if not inner else 0.28) * pow(maxf(0.0, sin(PI * pow(u, 1.7))), 0.62)
			var lean := h * (0.09 * pow(1.0 - u, 2.2) - 0.025 * sin(u * PI))
			var x: float = c.x + lean + wdt * side
			var y := top + u * h
			if side < 0.0 and (j == 0 or j == n):
				continue
			pts.append(o + Vector2(x, y) * s)
	ci.draw_colored_polygon(pts, col)
