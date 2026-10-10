extends Control
## The big moments, drawn like the frieze of a vase:
##  - show_labor(index, title): "I · EL LEÓN DE NEMEA" — a band of clay unrolls from the centre of the screen,
##    a meander above and a row of tongues below, palmettes at both ends, the black-figure beast walking towards
##    the inscription (painted in black glaze, as on the pots). Holds ~5 s and rolls up again.
##  - show_victory(index, title, sub): "Trabajo I completado · La piel del León" — the same frieze with the
##    lion's head in a laurel wreath.
##  - show_death() / hide_death(): "Has caído" over a darkened, wine-tinted screen, "Vuelves al último altar".
## Everything runs on real time (tweens and timers ignore hit-stop and pause).

const S := preload("res://scripts/ui/style.gd")
const F := preload("res://scripts/ui/figures.gd")

const ROMAN := ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII"]
## A line under each labour's name: where it happens, or the hint the place gives.
const EPIGRAPHS := {
	1: "Nemea · la cueva de las dos bocas",
	2: "Lerna · próximamente",
}
const LABOR_HOLD := 5.2
const VICTORY_HOLD := 6.5

var mode := "" # "labor" | "victory" | ""
var index := 1
var title := ""
var line1 := ""
var sub := ""
var _t := 0.0
var _hold := LABOR_HOLD
var _death := 0.0
var _death_on := false
var _death_t := 0.0
var _frieze: Frieze


## The clay band. Lives in its own clipped control so it can unroll (width) and roll up (height) while the
## drawing inside stays still.
class Frieze extends Control:
	var owner_cards: Control
	var band := Rect2()

	func _init() -> void:
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_set_transform(-position, 0.0, Vector2.ONE)
		owner_cards.call("_draw_band", self, band)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frieze = Frieze.new()
	_frieze.owner_cards = self
	_frieze.visible = false
	add_child(_frieze)


func is_showing() -> bool:
	return mode != "" or _death > 0.0


func show_labor(idx: int, t: String) -> void:
	index = idx
	mode = "labor"
	line1 = "TRABAJO %s" % _roman(idx)
	title = t.to_upper()
	sub = String(EPIGRAPHS.get(idx, ""))
	_t = 0.0
	_hold = LABOR_HOLD
	S.sfx("ui_card", -1.0)


func show_victory(idx: int, t: String = "La piel del León", s: String = "Las armas cortantes apenas te hieren") -> void:
	index = idx
	mode = "victory"
	line1 = "TRABAJO %s COMPLETADO" % _roman(idx)
	title = t.to_upper()
	sub = s
	_t = 0.0
	_hold = VICTORY_HOLD


func hide_card() -> void:
	if mode != "" and _t < 0.8 + _hold:
		_t = 0.8 + _hold


## Debug (uitour): everything off at once, no roll-up.
func reset() -> void:
	mode = ""
	_frieze.visible = false
	_death_on = false
	_death = 0.0
	queue_redraw()


func show_death() -> void:
	_death_on = true
	_death_t = 0.0
	var s: Node = get_node_or_null("/root/Sfx")
	if s and s.has_method("play"):
		s.call("play", "stinger_death")


func hide_death() -> void:
	_death_on = false


func _roman(i: int) -> String:
	return ROMAN[i] if i >= 0 and i < ROMAN.size() else str(i)


func _band_rect() -> Rect2:
	var h := clampf(size.y * 0.44, 250.0, 360.0)
	return Rect2(0.0, size.y * 0.47 - h * 0.5, size.x, h)


func _process(delta: float) -> void:
	var rd := S.rdelta(delta)
	# --- frieze card ---
	if mode != "":
		_t += rd
		var band := _band_rect()
		var open_k := S.ease_out(_t / 0.75)
		var close_k := S.ease_in_out((_t - 0.8 - _hold) / 0.55)
		var w := band.size.x * open_k
		var h := band.size.y * (1.0 - close_k)
		_frieze.visible = w > 1.0 and h > 1.0
		_frieze.band = band
		_frieze.position = Vector2(band.position.x + (band.size.x - w) * 0.5, band.position.y + (band.size.y - h) * 0.5)
		_frieze.size = Vector2(w, h)
		_frieze.queue_redraw()
		if close_k >= 1.0:
			mode = ""
			_frieze.visible = false
	# --- death screen ---
	if _death_on:
		_death_t += rd
	var want := 1.0 if (_death_on and _death_t > 0.5) else 0.0
	var was := _death
	_death = move_toward(_death, want, rd * (1.4 if want > 0.0 else 2.2))
	if mode != "" or _death > 0.0 or was > 0.0:
		queue_redraw()


func _draw() -> void:
	if mode != "":
		# the world dims a little behind the frieze
		var k := S.ease_out(_t / 0.4) * (1.0 - S.ease_in_out((_t - 0.8 - _hold) / 0.55))
		draw_rect(Rect2(Vector2.ZERO, size), Color(S.INK, 0.28 * k))
	if _death > 0.0:
		_draw_death(_death)


# --- the frieze ----------------------------------------------------------------------------------------------

func _draw_band(ci: CanvasItem, band: Rect2) -> void:
	var clay := S.CLAY_BG
	var ink := S.INK
	ci.draw_rect(band, clay)
	# subtle firing variation: a darker wash towards the edges
	S.draw_soft_band(ci, Rect2(band.position.x - 40.0, band.position.y, band.size.x + 80.0, band.size.y), Color(1.0, 0.82, 0.62, 0.1), 0.35, 0.3)
	var top := Rect2(band.position.x, band.position.y + 8.0, band.size.x, 30.0)
	ci.draw_rect(Rect2(band.position.x, band.position.y, band.size.x, 5.0), ink)
	S.draw_meander_band(ci, top, ink, Color(0, 0, 0, 0), 2.2)
	var bot_y := band.end.y - 30.0
	ci.draw_rect(Rect2(band.position.x, band.end.y - 5.0, band.size.x, 5.0), ink)
	S.draw_tongues(ci, Rect2(band.position.x, bot_y, band.size.x, 20.0), ink)
	ci.draw_line(Vector2(band.position.x, bot_y - 4.0), Vector2(band.end.x, bot_y - 4.0), ink, 1.5, true)
	var field := Rect2(band.position.x, top.end.y + 6.0, band.size.x, bot_y - top.end.y - 14.0)
	var t := _t
	var fig_a := S.ease_out((t - 0.3) / 0.6)
	var txt_a := S.ease_out((t - 0.5) / 0.6)
	# palmettes at both ends
	var ph := field.size.y * 0.58
	var px := clampf(field.size.x * 0.06, 60.0, 110.0)
	F.draw_palmette(ci, Vector2(field.position.x + px, field.end.y - 4.0), ph, ink, clay)
	F.draw_palmette(ci, Vector2(field.end.x - px, field.end.y - 4.0), ph, ink, clay)
	# the scene: the beast (left) and the inscription (right)
	var cx := field.position.x + field.size.x * 0.5
	var fig_w := minf(field.size.x * 0.4, field.size.y * 2.05)
	var fig := Rect2(cx - fig_w - field.size.x * 0.03, field.position.y + 6.0, fig_w, field.size.y - 8.0)
	var slide := 24.0 * (1.0 - fig_a)
	var ink_f := Color(ink, ink.a * fig_a)
	var clay_f := Color(clay, fig_a)
	if mode == "labor":
		if index == 2:
			F.draw_hydra(ci, Rect2(fig.position + Vector2(-slide, 0), fig.size), ink_f, clay_f)
		else:
			F.draw_lion(ci, Rect2(fig.position + Vector2(-slide, 0), fig.size), ink_f, clay_f)
		# fillers: rosettes in the empty clay around the figure, as on Corinthian ware
		for q: Vector2 in [Vector2(0.06, 0.18), Vector2(0.9, 0.12), Vector2(0.42, 0.08)]:
			F.draw_rosette(ci, fig.position + fig.size * q, field.size.y * 0.06, ink_f, clay_f)
	else:
		# victory: the lion's head inside a laurel wreath
		var c := Vector2(fig.position.x + fig.size.x * 0.55, field.position.y + field.size.y * 0.5)
		var rr := field.size.y * 0.42
		var head := Rect2(c - Vector2(rr, rr) * 0.78, Vector2(rr, rr) * 1.56)
		F.draw_lion_head(ci, head, ink_f, clay_f)
		for side: float in [-1.0, 1.0]:
			var a0 := c + Vector2(side * rr * 0.25, rr * 1.0)
			var steps := 7
			for i in steps:
				var ang0 := PI * 0.5 + side * (0.28 + float(i) / steps * 2.2)
				var ang1 := PI * 0.5 + side * (0.28 + float(i + 1) / steps * 2.2)
				var p0 := c + Vector2(cos(ang0), sin(ang0)) * rr * 1.08
				var p1 := c + Vector2(cos(ang1), sin(ang1)) * rr * 1.08
				F.draw_laurel(ci, p0, p1, ink_f, 1, rr * 0.075)
			ci.draw_line(a0, c + Vector2(cos(PI * 0.5 + side * 0.28), sin(PI * 0.5 + side * 0.28)) * rr * 1.08, ink_f, 2.0, true)
	# the inscription
	var tx := cx + field.size.x * 0.04
	var tw := field.end.x - px * 2.5 - tx
	var mid_y := field.position.y + field.size.y * 0.5
	var f1 := S.font(S.CINZEL)
	var f2 := S.font(S.CINZEL_BOLD)
	var big := int(clampf(field.size.y * 0.2, 30.0, 52.0))
	var track := 4.0 + 14.0 * (1.0 - S.ease_out((t - 0.5) / 1.2))
	while big > 22 and S.tracked_width(f2, title, big, track) > tw:
		big -= 2
	var small := int(big * 0.46)
	var center_x := tx + tw * 0.5
	S.draw_tracked(ci, f1, line1, small, Vector2(center_x, mid_y - big * 0.78), 9.0, Color(ink, txt_a), 1, 0, txt_a)
	S.draw_tracked(ci, f2, title, big, Vector2(center_x, mid_y + big * 0.32), track, Color(ink, txt_a), 1, 0, clampf((t - 0.5) / 0.9, 0.0, 1.0))
	var rule_w := minf(tw * 0.42, S.tracked_width(f2, title, big, 4.0) * 0.45)
	_ink_rule(ci, Vector2(center_x, mid_y + big * 0.72), rule_w * S.ease_out((t - 0.7) / 0.7), Color(ink, txt_a))
	if sub != "":
		var fi := S.font(S.ITALIC)
		var spx := int(clampf(big * 0.46, 16.0, 24.0))
		var sw := fi.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, spx).x
		ci.draw_string(fi, Vector2(center_x - sw * 0.5, mid_y + big * 0.72 + spx * 1.6), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, spx, Color(ink, 0.92 * S.ease_out((t - 0.9) / 0.6)))


## Rule in black glaze: hairlines and a dot-diamond, as painted between registers.
func _ink_rule(ci: CanvasItem, c: Vector2, half_w: float, col: Color) -> void:
	if half_w < 2.0:
		return
	ci.draw_line(c + Vector2(-half_w, 0), c + Vector2(-9, 0), col, 1.6, true)
	ci.draw_line(c + Vector2(9, 0), c + Vector2(half_w, 0), col, 1.6, true)
	S.draw_diamond(ci, c, 4.5, col)
	ci.draw_circle(c + Vector2(-half_w - 5.0, 0), 2.2, col)
	ci.draw_circle(c + Vector2(half_w + 5.0, 0), 2.2, col)


# --- the death screen ----------------------------------------------------------------------------------------

func _draw_death(k: float) -> void:
	var a := S.ease_in_out(k)
	draw_rect(Rect2(Vector2.ZERO, size), Color(S.INK, 0.5 * a))
	var edge := Color(S.WINE, 0.0)
	var wine := Color(S.WINE.darkened(0.3), 0.55 * a)
	var w := size.x
	var h := size.y
	# a wine-dark vignette from the edges
	for b in [[Vector2(0, 0), Vector2(w, 0), Vector2(w, h * 0.3), Vector2(0, h * 0.3), wine, wine, edge, edge],
			[Vector2(0, h * 0.7), Vector2(w, h * 0.7), Vector2(w, h), Vector2(0, h), edge, edge, wine, wine],
			[Vector2(0, 0), Vector2(w * 0.25, 0), Vector2(w * 0.25, h), Vector2(0, h), wine, edge, edge, wine],
			[Vector2(w * 0.75, 0), Vector2(w, 0), Vector2(w, h), Vector2(w * 0.75, h), edge, wine, wine, edge]]:
		draw_polygon(PackedVector2Array([b[0], b[1], b[2], b[3]]), PackedColorArray([b[4], b[5], b[6], b[7]]))
	var c := Vector2(w * 0.5, h * 0.44)
	S.draw_soft_band(self, Rect2(c.x - w * 0.36, c.y - 110.0, w * 0.72, 200.0), Color(S.INK, 0.45 * a), 0.3, 0.32)
	var f := S.font(S.CINZEL)
	var px := int(clampf(h * 0.095, 44.0, 76.0))
	var track := 14.0 + 16.0 * (1.0 - S.ease_out(_death_t / 2.0))
	S.draw_tracked(self, f, "HAS CAÍDO", px, c + Vector2(0, px * 0.3), track, Color(S.IVORY.lerp(Color("FFD9CC"), 0.25), a), 1, 7, clampf((_death_t - 0.5) / 1.0, 0.0, 1.0))
	# a broken meander: the line of the hero's labours, interrupted
	var mw := clampf(w * 0.17, 140.0, 240.0)
	var my := c.y + px * 0.72
	S.draw_meander(self, Vector2(c.x - mw * 0.55 - 14.0, my), mw * 0.5, 13.0, Color(S.CLAY_LIGHT, 0.85 * a))
	S.draw_meander(self, Vector2(c.x + mw * 0.55 + 14.0, my), mw * 0.5, 13.0, Color(S.CLAY_LIGHT, 0.85 * a))
	S.draw_diamond(self, Vector2(c.x, my + 1.0), 4.0, Color(S.CLAY_LIGHT, 0.6 * a))
	var sa := a * S.ease_out((_death_t - 1.0) / 0.8)
	S.draw_text(self, S.font(S.ITALIC), "Vuelves al último altar", 25, Vector2(c.x, my + 46.0), Color(S.IVORY, 0.9 * sa), 1, 5)
