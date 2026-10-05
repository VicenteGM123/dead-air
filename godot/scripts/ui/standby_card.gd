# DEAD AIR — ui/standby_card.gd: the PLEASE STAND BY card between the tune-in dive and the first station frame
# (Godot-only; the web build needs it, the JS game had no stall to cover).
#
# The menu's dive ends on a white flash and game.newGame(); the first frames of the station then draw the whole
# level, its HUD and the hero (first-use GPU uploads, the remaining shader variants): seconds on a weak WebGL GPU.
# Instead of a frozen white frame the screen cuts to the station's test card (cards.gd "stand_by", awake Telly) on
# black, with a TUNING IN caption and a progress bar, and fades out once the station has drawn a few frames.
# Driven by menu.gd (_startGame / update): show_() -> the menu calls game.newGame() one drawn frame later ->
# frameDrawn() per frame -> fades by itself (update(dt)). A CanvasLayer at 22: over the HUD (10), the commercial
# (15) and the menus (20, the white flash fades under it).
extends RefCounted

const LAYER := 22
const MIN_FRAMES := 4        # station frames drawn under the card before it fades
const MIN_TIME := 0.35       # s on screen at least (no one-frame blink on fast machines)
const FADE := 0.4

var game
var layer: CanvasLayer
var view: Control
var tex: Texture2D = null
var active := false
var progress := 0.0          # 0..1 shown
var target := 0.0
var alpha := 0.0
var _t := 0.0
var _frames := -1            # station frames drawn since newGame (-1: not started yet)
var _fading := false

class CardView extends Control:
	var card
	func _draw() -> void:
		var c = card
		var S := size
		var a: float = c.alpha
		draw_rect(Rect2(Vector2.ZERO, S), Color(0, 0, 0, a))
		# 4:3 picture, 78 % of the height, a little above the centre
		var ph := S.y * 0.74
		var pw := ph * 4.0 / 3.0
		if pw > S.x * 0.92:
			pw = S.x * 0.92
			ph = pw * 0.75
		var px := (S.x - pw) / 2.0
		var py := (S.y - ph) / 2.0 - S.y * 0.05
		if c.tex != null:
			draw_texture_rect(c.tex, Rect2(px, py, pw, ph), false, Color(1, 1, 1, a))
		else:
			draw_rect(Rect2(px, py, pw, ph), Color(0.18, 0.25, 0.66, a))
		# caption + progress bar under the picture
		var cream := Color("#F6E7C8")
		cream.a = a
		var gold := Color("#E8A92E")
		gold.a = a
		var bw := pw * 0.56
		var bh := maxf(6.0, S.y * 0.018)
		var bx := (S.x - bw) / 2.0
		var by := py + ph + S.y * 0.06
		var font: Font = c.font
		if font != null:
			var fs := int(maxf(12.0, S.y * 0.034))
			var txt := "TUNING IN  ·  WZTV 13"
			var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(font, Vector2((S.x - tw) / 2.0, by - S.y * 0.016), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, cream)
		draw_rect(Rect2(bx - 3, by - 3, bw + 6, bh + 6), cream, false, 2.0)
		draw_rect(Rect2(bx, by, bw * clampf(c.progress, 0.0, 1.0), bh), gold)

var font: Font = null

func _init(g) -> void:
	game = g

# Builds the layer (hidden) and the card texture: call it while loading so show_() costs nothing.
func prepare() -> void:
	if layer != null and is_instance_valid(layer):
		return
	layer = CanvasLayer.new()
	layer.name = "StandbyCard"
	layer.layer = LAYER
	layer.visible = false
	view = CardView.new()
	view.card = self
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(view)
	game.add_child(layer)
	if tex == null:
		var t = DACards.getCard("stand_by", {"variant": "awake"})
		tex = t if t is Texture2D else null
	if font == null and ResourceLoader.exists("res://scripts/ui/fonts.gd"):
		font = DAFonts.family(DAFonts.FONTS.tape)

func show_() -> void:
	prepare()
	active = true
	_fading = false
	_t = 0.0
	_frames = -1
	alpha = 1.0
	progress = 0.08
	target = 0.25
	layer.visible = true
	view.queue_redraw()

# The run has been started under the card (game.newGame done).
func started() -> void:
	_frames = 0
	target = 0.55

func update(dt: float) -> void:
	if not active:
		return
	_t += dt
	if _frames >= 0:
		_frames += 1
		target = maxf(target, minf(1.0, 0.55 + 0.45 * float(_frames) / MIN_FRAMES))
		if not _fading and _frames >= MIN_FRAMES and _t >= MIN_TIME:
			_fading = true
			target = 1.0
	progress = minf(target, progress + maxf(dt, 1.0 / 60.0) * 2.5) if progress < target else target
	if _fading:
		alpha = maxf(0.0, alpha - dt / FADE)
		if alpha <= 0.0:
			active = false
			layer.visible = false
	view.queue_redraw()
