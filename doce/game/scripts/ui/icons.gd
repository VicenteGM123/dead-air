class_name Icons
## Minimal vector icons drawn with CanvasItem calls, so the UI stays crisp at any resolution and needs no
## image assets. Icons are designed on a 0..1 square, flat, in one colour plus at most a lighter or darker tint
## of it (the inner tongue of a flame, the rim of a coin). No faces: creatures only show their glowing eyes.

static func draw(ci: CanvasItem, icon: String, r: Rect2, col: Color) -> void:
	var s := minf(r.size.x, r.size.y)
	var o := r.position + (r.size - Vector2(s, s)) * 0.5
	var p := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s
	var w := maxf(1.5, s * 0.075)
	var dark := Color(col.r * 0.2, col.g * 0.18, col.b * 0.26, col.a)
	var light := Color(col.lerp(Color.WHITE, 0.55), col.a)
	match icon:
		"coin":
			ci.draw_circle(p.call(0.5, 0.52), s * 0.42, Color(col.darkened(0.3), col.a))
			ci.draw_circle(p.call(0.5, 0.48), s * 0.42, col)
			ci.draw_arc(p.call(0.5, 0.48), s * 0.32, 0.0, TAU, 32, Color(col.darkened(0.25), col.a), maxf(1.0, s * 0.045), true)
			_flame(ci, o, s, Vector2(0.5, 0.49), 0.36, Color(col.darkened(0.3), col.a))
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
		"moon", "crescent":
			_crescent(ci, p.call(0.52, 0.5), s * 0.38, col)
		"flame":
			_flame(ci, o, s, Vector2(0.5, 0.5), 0.92, col)
			_flame(ci, o, s, Vector2(0.5, 0.64), 0.42, light, true)
		"flame_out":
			# The lantern gone dark, a thread of smoke rising from it.
			_lantern(ci, o, s, Vector2(0.5, 0.62), 0.62, col, false)
			var pts := PackedVector2Array()
			for i in 14:
				var t := float(i) / 13.0
				pts.append(p.call(0.5 + sin(t * 4.6 + 0.4) * 0.07 * (0.4 + t), 0.3 - t * 0.27))
			ci.draw_polyline(pts, Color(col, col.a * 0.8), maxf(1.2, w * 0.6), true)
		"lantern":
			_lantern(ci, o, s, Vector2(0.5, 0.5), 1.0, col, true)
		"heart":
			ci.draw_circle(p.call(0.35, 0.38), s * 0.18, col)
			ci.draw_circle(p.call(0.65, 0.38), s * 0.18, col)
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.18, 0.46), p.call(0.82, 0.46), p.call(0.5, 0.85)]), col)
		"bolt":
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.62, 0.03), p.call(0.2, 0.56), p.call(0.46, 0.56), p.call(0.34, 0.97), p.call(0.8, 0.42), p.call(0.54, 0.42), p.call(0.7, 0.03)]), col)
		"beam":
			# The lantern head throwing its beam (Haz del Faro).
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.42, 0.44), p.call(0.97, 0.16), p.call(0.97, 0.84), p.call(0.42, 0.56)]), Color(col, col.a * 0.42))
			ci.draw_line(p.call(0.44, 0.43), p.call(0.95, 0.17), col, maxf(1.0, w * 0.55), true)
			ci.draw_line(p.call(0.44, 0.57), p.call(0.95, 0.83), col, maxf(1.0, w * 0.55), true)
			_lantern(ci, o, s, Vector2(0.24, 0.5), 0.56, col, true)
		"lens":
			# Destello de la lente: Fresnel rings and four sharp rays.
			var c0: Vector2 = p.call(0.5, 0.5)
			ci.draw_circle(c0, s * 0.1, col)
			ci.draw_arc(c0, s * 0.19, 0.0, TAU, 28, col, maxf(1.0, w * 0.55), true)
			ci.draw_arc(c0, s * 0.28, 0.0, TAU, 32, col, maxf(1.0, w * 0.55), true)
			for i in 4:
				var a := TAU * float(i) / 4.0 + PI * 0.25
				var d := Vector2(cos(a), sin(a))
				var n := Vector2(-d.y, d.x)
				ci.draw_colored_polygon(PackedVector2Array([c0 + d * s * 0.33 + n * s * 0.05, c0 + d * s * 0.5, c0 + d * s * 0.33 - n * s * 0.05]), col)
		"steam":
			# Embestida de vapor: puffs trailing behind a forward arrow.
			for i in 3:
				var y := 0.3 + i * 0.2
				var x0 := 0.1 + (0.08 if i == 1 else 0.0)
				var pts := PackedVector2Array()
				for k in 10:
					var t := float(k) / 9.0
					pts.append(p.call(x0 + t * 0.5, y + sin(t * PI * 2.0) * 0.035))
				ci.draw_polyline(pts, col, w * 0.85, true)
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.7, 0.24), p.call(0.94, 0.5), p.call(0.7, 0.76), p.call(0.76, 0.5)]), col)
		"trident":
			var sw := w * 1.05
			ci.draw_line(p.call(0.5, 0.4), p.call(0.5, 0.9), col, sw, true)
			ci.draw_circle(p.call(0.5, 0.92), s * 0.045, col)
			var u := PackedVector2Array()
			for i in 13:
				var t := float(i) / 12.0
				var x := lerpf(0.24, 0.76, t)
				var k := (x - 0.5) / 0.26
				u.append(p.call(x, 0.42 - 0.2 * k * k))
			ci.draw_polyline(u, col, sw, true)
			ci.draw_line(p.call(0.5, 0.42), p.call(0.5, 0.2), col, sw, true)
			for tip in [Vector2(0.24, 0.13), Vector2(0.5, 0.06), Vector2(0.76, 0.13)]:
				var t2: Vector2 = tip
				ci.draw_colored_polygon(PackedVector2Array([p.call(t2.x - 0.075, t2.y + 0.13), p.call(t2.x, t2.y), p.call(t2.x + 0.075, t2.y + 0.13), p.call(t2.x, t2.y + 0.09)]), col)
		"owl":
			# Athena's owl, as on the tetradrachm: round body, ear tufts, great ringed eyes.
			ci.draw_colored_polygon(_ellipse(p.call(0.5, 0.58), s * 0.27, s * 0.33, 28), col)
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.25, 0.42), p.call(0.24, 0.14), p.call(0.42, 0.3)]), col)
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.75, 0.42), p.call(0.76, 0.14), p.call(0.58, 0.3)]), col)
			ci.draw_circle(p.call(0.5, 0.38), s * 0.21, col)
			for ex in [0.39, 0.61]:
				ci.draw_circle(p.call(ex, 0.4), s * 0.1, dark)
				ci.draw_circle(p.call(ex, 0.4), s * 0.045, light)
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.46, 0.5), p.call(0.54, 0.5), p.call(0.5, 0.58)]), dark)
			for i in 3:
				var yy := 0.66 + i * 0.08
				ci.draw_arc(p.call(0.5, yy - 0.06), s * (0.1 - i * 0.012), PI * 0.2, PI * 0.8, 8, Color(dark, dark.a * 0.7), maxf(1.0, w * 0.4), true)
			ci.draw_line(p.call(0.3, 0.93), p.call(0.7, 0.93), col, maxf(1.0, w * 0.6), true)
		"bow":
			# Artemis: a recurve bow, its string and an arrow.
			var pts := PackedVector2Array()
			var inner := PackedVector2Array()
			for i in 17:
				var t := float(i) / 16.0
				var a := lerpf(-PI * 0.4, PI * 0.4, t)
				var thick := 0.022 + 0.035 * cos(a * 1.2)
				pts.append(p.call(0.3 + cos(a) * 0.42, 0.5 + sin(a) * 0.44))
				inner.append(p.call(0.3 + cos(a) * (0.42 - thick * 2.0), 0.5 + sin(a) * (0.44 - thick)))
			inner.reverse()
			ci.draw_colored_polygon(pts + inner, col)
			var top: Vector2 = pts[0]
			var bot: Vector2 = pts[pts.size() - 1]
			ci.draw_line(top, bot, Color(col, col.a * 0.8), maxf(1.0, w * 0.35), true)
			ci.draw_line(p.call(0.14, 0.5), p.call(0.86, 0.5), col, w * 0.7, true)
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.96, 0.5), p.call(0.82, 0.42), p.call(0.85, 0.5), p.call(0.82, 0.58)]), col)
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.12, 0.5), p.call(0.06, 0.42), p.call(0.2, 0.42), p.call(0.24, 0.5), p.call(0.2, 0.58), p.call(0.06, 0.58)]), col)
		"wing":
			# Hermes: a wing of four long feathers stacked and swept back, their roots under a rounded shoulder.
			for i in 4:
				var y0 := 0.27 + i * 0.155
				var root: Vector2 = p.call(0.72, y0 + 0.03)
				var tip: Vector2 = p.call(0.06 + i * 0.12, y0 - 0.08 + i * 0.012)
				ci.draw_colored_polygon(_leaf(root, tip, s * 0.062), col)
			ci.draw_colored_polygon(_ellipse(p.call(0.77, 0.42), s * 0.15, s * 0.25, 22), col)
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.66, 0.2), p.call(0.92, 0.1), p.call(0.88, 0.3)]), col)
		"spear":
			# Ares: a round hoplite shield with a spear behind it (only its butt and its blade show).
			var sc: Vector2 = p.call(0.47, 0.53)
			ci.draw_line(p.call(0.08, 0.94), p.call(0.82, 0.2), col, w * 0.95, true)
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.76, 0.22), p.call(0.97, 0.03), p.call(0.8, 0.26)]), col)
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.8, 0.26), p.call(0.97, 0.03), p.call(0.74, 0.24)]), col)
			ci.draw_colored_polygon(_leaf(p.call(0.72, 0.3), p.call(0.97, 0.03), s * 0.06), col)
			ci.draw_circle(sc, s * 0.33, Color(dark, col.a))
			ci.draw_circle(sc, s * 0.31, col)
			ci.draw_arc(sc, s * 0.235, 0.0, TAU, 32, Color(dark, col.a * 0.7), maxf(1.0, w * 0.45), true)
			ci.draw_circle(sc, s * 0.07, Color(dark, col.a * 0.7))
		"anchor":
			ci.draw_line(p.call(0.5, 0.22), p.call(0.5, 0.86), col, w, true)
			ci.draw_line(p.call(0.3, 0.32), p.call(0.7, 0.32), col, w, true)
			ci.draw_arc(p.call(0.5, 0.14), s * 0.075, 0.0, TAU, 16, col, w * 0.8, true)
			ci.draw_arc(p.call(0.5, 0.52), s * 0.34, PI * 0.12, PI * 0.88, 20, col, w, true)
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.1, 0.62), p.call(0.2, 0.48), p.call(0.27, 0.68)]), col)
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.9, 0.62), p.call(0.8, 0.48), p.call(0.73, 0.68)]), col)
		"hammer":
			# Hephaestus: hammer over an anvil.
			ci.draw_line(p.call(0.26, 0.66), p.call(0.66, 0.2), col, w * 1.05, true)
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.5, 0.06), p.call(0.86, 0.36), p.call(0.76, 0.48), p.call(0.4, 0.18)]), col)
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.12, 0.7), p.call(0.88, 0.7), p.call(0.8, 0.78), p.call(0.66, 0.8), p.call(0.66, 0.9), p.call(0.76, 0.95), p.call(0.24, 0.95), p.call(0.34, 0.9), p.call(0.34, 0.8), p.call(0.2, 0.78)]), col)
		"wheat":
			# Demeter: an ear of wheat with a leaf.
			ci.draw_line(p.call(0.5, 0.96), p.call(0.5, 0.2), col, w * 0.7, true)
			for i in 4:
				var y := 0.24 + i * 0.14
				ci.draw_colored_polygon(_leaf(p.call(0.5, y + 0.06), p.call(0.31, y - 0.04), s * 0.075), col)
				ci.draw_colored_polygon(_leaf(p.call(0.5, y + 0.06), p.call(0.69, y - 0.04), s * 0.075), col)
			ci.draw_colored_polygon(_leaf(p.call(0.5, 0.2), p.call(0.5, 0.04), s * 0.07), col)
			ci.draw_colored_polygon(_leaf(p.call(0.5, 0.86), p.call(0.8, 0.66), s * 0.06), col)
		"house":
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.12, 0.48), p.call(0.5, 0.16), p.call(0.88, 0.48)]), col)
			ci.draw_rect(Rect2(p.call(0.22, 0.48), Vector2(s * 0.56, s * 0.38)), col)
			ci.draw_rect(Rect2(p.call(0.44, 0.62), Vector2(s * 0.12, s * 0.24)), dark)
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
			# The lighthouse: stepped base, tapering tower, gallery, lantern room and dome, light to both sides.
			ci.draw_rect(Rect2(p.call(0.26, 0.88), Vector2(s * 0.48, s * 0.08)), col)
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.34, 0.88), p.call(0.41, 0.42), p.call(0.59, 0.42), p.call(0.66, 0.88)]), col)
			ci.draw_rect(Rect2(p.call(0.32, 0.37), Vector2(s * 0.36, s * 0.06)), col)
			ci.draw_rect(Rect2(p.call(0.4, 0.22), Vector2(s * 0.2, s * 0.15)), light)
			ci.draw_line(p.call(0.4, 0.22), p.call(0.4, 0.37), col, maxf(1.0, w * 0.5), true)
			ci.draw_line(p.call(0.6, 0.22), p.call(0.6, 0.37), col, maxf(1.0, w * 0.5), true)
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.37, 0.23), p.call(0.5, 0.09), p.call(0.63, 0.23)]), col)
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.3, 0.27), p.call(0.04, 0.2), p.call(0.04, 0.36)]), Color(col, col.a * 0.5))
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.7, 0.27), p.call(0.96, 0.2), p.call(0.96, 0.36)]), Color(col, col.a * 0.5))
		"horn":
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.08, 0.46), p.call(0.6, 0.42), p.call(0.9, 0.18), p.call(0.9, 0.82), p.call(0.6, 0.58), p.call(0.08, 0.54)]), col)
		"skull", "enemy":
			# A child of Nyx: a pointed hood, a dark void inside, two almond eyes that glow.
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.5, 0.04), p.call(0.7, 0.24), p.call(0.84, 0.56), p.call(0.86, 0.94), p.call(0.14, 0.94), p.call(0.16, 0.56), p.call(0.3, 0.24)]), col)
			ci.draw_colored_polygon(_ellipse(p.call(0.5, 0.58), s * 0.23, s * 0.22, 20), dark)
			ci.draw_colored_polygon(_leaf(p.call(0.32, 0.56), p.call(0.46, 0.6), s * 0.045), light)
			ci.draw_colored_polygon(_leaf(p.call(0.68, 0.56), p.call(0.54, 0.6), s * 0.045), light)
		"cat":
			# Seated cat seen from behind: head with two ears over a round body, curled tail.
			ci.draw_colored_polygon(_ellipse(p.call(0.5, 0.7), s * 0.24, s * 0.22, 20), col)
			ci.draw_circle(p.call(0.5, 0.38), s * 0.17, col)
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.35, 0.34), p.call(0.36, 0.12), p.call(0.49, 0.25)]), col)
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.65, 0.34), p.call(0.64, 0.12), p.call(0.51, 0.25)]), col)
			ci.draw_arc(p.call(0.8, 0.74), s * 0.13, -PI * 0.6, PI * 0.55, 12, col, w, true)
		"chevron":
			ci.draw_colored_polygon(PackedVector2Array([p.call(0.2, 0.15), p.call(0.85, 0.5), p.call(0.2, 0.85), p.call(0.38, 0.5)]), col)
		"pause":
			ci.draw_rect(Rect2(p.call(0.3, 0.24), Vector2(s * 0.13, s * 0.52)), col)
			ci.draw_rect(Rect2(p.call(0.57, 0.24), Vector2(s * 0.13, s * 0.52)), col)
		"tap":
			# A fingertip pressing: a dot inside two rings.
			ci.draw_circle(p.call(0.5, 0.5), s * 0.14, col)
			ci.draw_arc(p.call(0.5, 0.5), s * 0.27, 0.0, TAU, 24, Color(col, col.a * 0.7), maxf(1.2, w * 0.6), true)
			ci.draw_arc(p.call(0.5, 0.5), s * 0.4, 0.0, TAU, 28, Color(col, col.a * 0.35), maxf(1.0, w * 0.5), true)
		"stick":
			# Analogue stick seen from above.
			ci.draw_arc(p.call(0.5, 0.5), s * 0.4, 0.0, TAU, 28, col, maxf(1.2, w * 0.6), true)
			ci.draw_circle(p.call(0.5, 0.5), s * 0.22, col)
		"dpad":
			ci.draw_rect(Rect2(p.call(0.38, 0.1), Vector2(s * 0.24, s * 0.8)), col)
			ci.draw_rect(Rect2(p.call(0.1, 0.38), Vector2(s * 0.8, s * 0.24)), col)
		"mouse_l", "mouse_r":
			var body := Rect2(p.call(0.24, 0.08), Vector2(s * 0.52, s * 0.84))
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0, 0, 0, 0)
			sb.border_color = col
			sb.set_border_width_all(maxi(1, int(s * 0.06)))
			sb.set_corner_radius_all(int(s * 0.26))
			sb.anti_aliasing = true
			ci.draw_style_box(sb, body)
			ci.draw_line(p.call(0.5, 0.1), p.call(0.5, 0.42), col, maxf(1.0, s * 0.05), true)
			ci.draw_line(p.call(0.26, 0.42), p.call(0.74, 0.42), col, maxf(1.0, s * 0.05), true)
			var x0 := 0.28 if icon == "mouse_l" else 0.52
			var q := PackedVector2Array([p.call(x0, 0.16), p.call(x0 + 0.2, 0.16), p.call(x0 + 0.2, 0.39), p.call(x0, 0.39)])
			ci.draw_colored_polygon(q, col)
		"arrows":
			for d in [Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0)]:
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
			var u := float(i) / n # 0 = tip, 1 = bottom
			var wdt := h * (0.3 if not inner else 0.28) * pow(maxf(0.0, sin(PI * pow(u, 1.7))), 0.62)
			var lean := h * (0.09 * pow(1.0 - u, 2.2) - 0.025 * sin(u * PI))
			var x: float = c.x + lean + wdt * side
			var y := top + u * h
			if side < 0.0 and (j == 0 or j == n):
				continue
			pts.append(o + Vector2(x, y) * s)
	ci.draw_colored_polygon(pts, col)


## Fanós' head: dome with a finial, cap ring, a cage of bronze posts, base band; optionally a flame inside.
static func _lantern(ci: CanvasItem, o: Vector2, s: float, c: Vector2, k: float, col: Color, lit: bool) -> void:
	var p := func(x: float, y: float) -> Vector2: return o + (c + Vector2(x - 0.5, y - 0.5) * k) * s
	var w := maxf(1.2, s * k * 0.07)
	ci.draw_circle(p.call(0.5, 0.07), s * k * 0.045, col)
	var dome := PackedVector2Array()
	for i in 13:
		var a := lerpf(PI, TAU, float(i) / 12.0)
		dome.append(p.call(0.5 + cos(a) * 0.24, 0.27 + sin(a) * 0.17))
	ci.draw_colored_polygon(dome, col)
	ci.draw_colored_polygon(PackedVector2Array([p.call(0.2, 0.27), p.call(0.8, 0.27), p.call(0.8, 0.33), p.call(0.2, 0.33)]), col)
	ci.draw_line(p.call(0.28, 0.33), p.call(0.28, 0.76), col, w, true)
	ci.draw_line(p.call(0.72, 0.33), p.call(0.72, 0.76), col, w, true)
	if lit:
		_flame(ci, o, s, c + Vector2(0.0, 0.055) * k, 0.36 * k, col)
	else:
		ci.draw_line(p.call(0.5, 0.33), p.call(0.5, 0.76), Color(col, col.a * 0.5), w * 0.6, true)
	ci.draw_colored_polygon(PackedVector2Array([p.call(0.18, 0.76), p.call(0.82, 0.76), p.call(0.82, 0.84), p.call(0.18, 0.84)]), col)
	ci.draw_colored_polygon(PackedVector2Array([p.call(0.28, 0.84), p.call(0.72, 0.84), p.call(0.66, 0.92), p.call(0.34, 0.92)]), col)


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
