extends Node
class_name GalaScene
## --- SS2 RANK: la noche del Brass Comet (SS2_DESIGN §3.10, §8.8). Reemplaza entero el stub de la línea S.
## La fiesta en la calle de noche después del libro de cuentas de la noche 10 (o la primera noche #1 del modo sin fin,
## solo la versión campeona). Dos versiones:
##   campeona  1 la radio (Rosa) · 2 la cuenta del split-flap 5 -> 1 (fila 1: THE SECONDHAND STAR) · 3 el elenco llega a
##             los lugares de street.gala_spots() con corazones y vítores · 4 Tolle certifica · 5 Glint, un poco aparte
##             (+ el favor) · 6 Mags y Raker atornillan el cometa de latón al cartel (street.set_comet) · 7 Old Seven
##             junto a Kettle: el anillo contesta como un faro (3 núcleos: las 7 lámparas; si no, dos parpadean y se
##             apagan) · 8 la lluvia de chispas (street.play_sparks) y las líneas del epílogo según los hilos · 9 Kettle
##             silba, la frase de Nell · 10 la tarjeta del premio con el resumen de la temporada, los créditos (se
##             saltan) y [Keep trading] / [Title].
##   todavía no (#2-#30)  1-3 con el ganador de verdad (si Nell está más abajo que #5, una fila aparte con su puesto),
##             la línea de quien ganó (Glint o Rosa) · 7-10 igual, sin cometa; el premio por puesto; "Next season."
## Cada momento avanza solo (~3 s) o con E / Enter / Espacio / A; Esc / B saltan a la tarjeta del premio. El mando: B =
## Esc, X = Espacio; con el gancho de main.gd (marcado SS2 RANK) A también es Espacio y LB / RB saltan a los botones.
## Web (§8.13): se crea escondido en main._boot_background (_make_gala) y se reusa; su capa 2D y todas sus texturas se
## arman / cargan en _ready; los actores del elenco se crean uno por cuadro debajo de la pantalla de carga (los únicos
## nodos 3D nuevos son Actors, la familia ya calentada) y quedan escondidos hasta la fiesta. La calle solo se toca por
## la API de StreetWorld con has_method (§8.10: set_event, set_moons, set_ring_lamps, set_comet, play_sparks,
## gala_spots, set_band, rival_actor, vendor_actor): con el stub de S no se ve el cometa ni las lámparas, pero todo corre.
## auto (los bots): cada momento dura un instante, sin créditos, elige "keep" (o choice_override).

signal finished(choice: String)

const BEAT := 3.4                # segundos por momento (E / A adelantan)
const AUTO_BEAT := 0.08
const CAM_X := -6.0              # la cámara fija de la fiesta: la fachada de Nell, el cartel, la gente y las lunas
                                 # --- POLISH LOOK (P3): -5.0 -> -6.0: el letrero de Shine Again entra entero (se leía
                                 # "HINE AGAIN" cortado en el borde); el público de la derecha sigue en cuadro
const AMBER := Color(1.0, 0.72, 0.30)
const AMBER_HI := Color(1.0, 0.86, 0.52)
const PINK := Color(1.0, 0.56, 0.75)
const TEAL := Color(0.45, 0.88, 0.78)
const MUTED := Color(0.76, 0.71, 0.63)
const CREAM := Color(0.96, 0.93, 0.86)

## Quién llega a los lugares de la fiesta (street.gala_spots(), en este orden: W los da de la puerta hacia afuera,
## alternando fila de adelante y de atrás; los 3 últimos a la izquierda, pasando la banda). Los chicos adelante junto
## a la puerta (Pipip), los grandes atrás (Gorrum), así nadie tapa a Kettle. Raker, Mags, Dolly y Glint ya están en la
## calle (se toman prestados y vuelven a su sitio al final); los demás son Actors propios hechos al arrancar.
const CROWD := ["pipip", "gorrum", "zib", "raker", "oona", "mags", "clatter", "rook", "singer", "timekeeper", "tracker",
	"vendor", "dockmaster"]
const BEAT_CAST := ["inspector", "rival", "hermit", "buffbot"]
## El centro de la cabeza en el cuadro de 64x96 (el retrato de la franja de abajo); los nuevos vienen de CastData.
const HEADS := {"nell": Vector2(31, 36), "kettle": Vector2(32, 72), "gorrum": Vector2(30, 24), "zib": Vector2(33, 26),
	"oona": Vector2(31, 36), "pipip": Vector2(32, 54), "rook": Vector2(32, 33), "clatter": Vector2(31, 19),
	"raker": Vector2(37, 38), "mags": Vector2(32, 32)}
const WHO := {"rosa": ["Rosa Reverb", "the Drift Signal"], "nell": ["Nell", "The Secondhand Star"],
	"kettle": ["Kettle", "Your kettle"], "inspector": ["Inspector Tolle", "Tally Office"],
	"rival": ["Madame Glint", "Shine Again, next door"], "hermit": ["Old Seven", "Lamp-keeper of the Yards"],
	"mags": ["Mags", "Parts"], "raker": ["Raker", "Pods"], "rook": ["Rook Varga", "Pilot"],
	"dockmaster": ["Dockmaster Hesk", "Dock dues"], "singer": ["Lune", "Singer at the Slow Orbit"],
	"clatter": ["Clatter", "A regular"], "pipip": ["Pipip", "Glasspan Derby"]}

## Las líneas (§3.10 y el epílogo de §5.5). Inglés británico, cortas.
const LINES := {
	"rosa_count": "Drift, hold your lanterns. The Great Starfall count is in.",
	"rosa_gear_close": "...the Gilded Gear, again. Rustwater, so close!",
	"rosa_gear_far": "...the Gilded Gear, again. Rustwater, next season!",
	"rosa_other_close": "...{shop}, of {world}! Rustwater, so close!",
	"rosa_other_far": "...{shop}, of {world}! Rustwater, next season!",
	"glint_won": "Shine is hard, sweetie. You were close.",
	"tolle": "By the authority of the Tally Office, and with no forms missing, I certify it.",
	"glint": "First place. Ugh. Congratulations, Nell. ...Call me Dot.",
	"glint_favour": "Your fix won me Bronzemoon, you know. Don't tell Buff.",
	"mags_bolt": "Two bolts and a lot of hope. Nobody lean on it.",
	"seven_all": "...Every machine remembers who fixed it.",
	"seven_two": "...Next fall, then. The sky is patient.",
	"nell_win": "I never wanted to leave. I wanted the stars to come to the shop.",
	"nell_next": "Next season.",
	"kettle_next": "Fweee.",
	"rook_delivered": "The band owes you forever. So do I. Mostly the band.",
	"rook_declared": "No hard feelings. Mostly.",
	"rook_refused": "Next crate's yours. Kidding.",
	"rook_seized": "Lost a crate, found a party. Fair trade.",
	"tolle_certified": "Orderly. Exceptionally.",
	"tolle_other": "Noted. Fondly.",
	"hesk_paid_win": "On MY dock. First on the Board. Hm. ...Hm!",
	"hesk_paid": "Paid in full, on MY dock. Hm. ...Hm!",
	"hesk_short": "Pay me after the party. I'm not a monster.",
	"lune_band": "This one's for the kid with the wrench across the street.",
	"clatter": "I have saved up for this. It is free. I will cheer anyway.",
	"pipip_cup": "Digger says thank you. Digger can't talk. I'm saying it.",
	"end_win": "The Starfall Season is over. The shop stays open.",
	"end_crown": "The Brass Comet is yours. Keep the lights on.",
	"end_next": "The Starfall Season is over. The comet is still up there.",
}
## Los créditos: el elenco de dos en dos sobre la calle de noche (se saltan con E / Esc / A / B).
const CREDITS := [["Nell", "fixes things"], ["Kettle", "makes the tea"], ["Raker", "sells what fell"],
	["Mags", "fixed prices"], ["Dolly", "lifts things"], ["Madame Glint", "makes things sparkle"],
	["Inspector Tolle", "counts everything"], ["Dockmaster Hesk", "collects"], ["Gorrum", "never says yes first"],
	["Zib", "in a hurry"], ["Mother Oona", "thinks in colours"], ["Pipip", "and Digger"], ["Rook Varga", "keeps a secret"],
	["Clatter", "saves up"], ["Lune", "sings at the Slow Orbit"], ["Madam Sift", "keeps the time"],
	["Warden Brisk", "chases things"], ["Old Seven", "keeps the lamps"], ["Rosa Reverb", "the Drift Signal"],
	["The Low Moons", "Mo, Zee and Bow"]]

var auto := false
var choice_override := ""   # (pruebas) "title"
var last_champion := false
var plays := 0               # cuántas veces se jugó (el bot de S cuenta las suyas en main.galas_played)
var beats_log: Array = []    # (pruebas) los momentos que se jugaron, en orden
var stage := ""              # "" | "beats" | "card" | "credits" | "end"
var demo_stop := ""          # (capturas) se queda quieta al llegar a este momento: count_done, walk_done, comet_on,
                             # ring_, <quien>:, card, credits, end
var frozen := false          # (capturas) ya se quedó quieta

var _main: Node
var _street: Node
var _open := false
var _champion := false
var _next := false
var _skip := false           # Esc / B: a la tarjeta del premio
var _abort := false          # close_now()
var _choice := ""
var _end_sel := 0
var _pad_was := false
var _cores := 0
var _nell_pos := Vector3.ZERO
var _kettle_pos := Vector3.ZERO
var _cam_dist0 := 12.0
var _cam := {"x": CAM_X, "d": 12.0}

# 3D: el elenco (Actors propios, escondidos) y los prestados de la calle
var _actors := {}            # id -> Actor
var _borrowed: Array = []    # [{"a", "pos", "face", "vis"}]
var _prebuilt := false

# 2D
var _layer: CanvasLayer
var _root: Control
var _dim: ColorRect
var _tex := {}
var _crest_at: Array = []
var _por := {}               # id -> AtlasTexture (la cabeza)
var _sb_flap: StyleBox
var _sb_flap_flip: StyleBox
var _sb_board: StyleBox
var _sb_me: StyleBox
var _sb_rival: StyleBox
var _sb_empty: StyleBox
var _cap: PanelContainer
var _cap_por: TextureRect
var _cap_name: Label
var _cap_sub: Label
var _cap_line: Label
var _count: PanelContainer
var _count_rows: Array = []  # [{"box", "pos", "crest", "name", "world", "score"}]
var _count_gap: Label
var _count_me: Dictionary = {}
var _card: PanelContainer
var _card_art: TextureRect
var _card_title: Label
var _card_line: Label
var _card_season: Label
var _card_vals: Array = []   # [[key Label, value Label] x 8]
var _card_btn: Button
var _card_key: HBoxContainer
var _credits: Control
var _cred_box: VBoxContainer
var _end: PanelContainer
var _end_line: Label
var _end_keep: Button
var _end_title: Button
var _end_keep_key: HBoxContainer
var _end_title_key: HBoxContainer
var _hint: HBoxContainer
var _card_pulse: Tween           # --- POLISH LOOK (P3): el brillo del cometa en la tarjeta
var _card_count: Tween           # --- POLISH LOOK (P3): los números que cuentan

func _ready() -> void:
	name = "GalaScene"
	_layer = CanvasLayer.new()
	_layer.layer = 8          # encima del libro de cuentas y del tablero (7), debajo del fundido (20)
	add_child(_layer)
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.theme = UIKit.theme()
	_root.gui_input.connect(_on_root_input)
	_layer.add_child(_root)
	UIKit.load_fonts()
	_load_textures()
	_dim = ColorRect.new()
	_dim.color = Color(0.02, 0.02, 0.05, 0.0)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_dim)
	_build_count()
	_build_caption()
	_build_card()
	_build_credits()
	_build_end()
	_build_hint()
	_layer.visible = false
	set_process(false)
	# el elenco: un Actor por cuadro, escondido, mientras sigue el arranque (main.street ya existe)
	_prebuild.call_deferred()

# ================================================================== el armado (al arrancar)

func _load_textures() -> void:
	for n in ["board9", "flap_cell", "crests", "rosa", "comet_card", "award_ribbon", "icon_rank", "icon_radio"]:
		var p := "res://assets/ui/%s.png" % n
		_tex[n] = load(p) if ResourceLoader.exists(p) else null
	for i in 30:
		var at := AtlasTexture.new()
		at.atlas = _tex["crests"]
		at.region = Rect2(i * 24, 0, 24, 24)
		_crest_at.append(at)
	_sb_board = _nine(_tex["board9"], 18, 22)
	_sb_flap = _nine_region(_tex["flap_cell"], Rect2(0, 0, 48, 32), 6)
	_sb_flap_flip = _nine_region(_tex["flap_cell"], Rect2(48, 0, 48, 32), 6)
	_sb_me = _flat(Color(1.0, 0.72, 0.3, 0.18), Color(1.0, 0.72, 0.3, 0.7))
	_sb_rival = _flat(Color(1.0, 0.56, 0.75, 0.1), Color(0, 0, 0, 0))
	_sb_empty = StyleBoxEmpty.new()
	if _tex["rosa"]:
		_por["rosa"] = _tex["rosa"]

func _nine(tex: Texture2D, margin: int, content: int) -> StyleBox:
	if tex == null:
		return UIKit.panel_style(Color(0.11, 0.1, 0.09, 0.96), UIKit.ACCENT, 3, 6, content)
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.set_texture_margin_all(margin)
	sb.set_content_margin_all(content)
	return sb

func _nine_region(tex: Texture2D, region: Rect2, margin_x: int) -> StyleBox:
	if tex == null:
		var f := StyleBoxFlat.new()
		f.bg_color = Color(0.13, 0.12, 0.11)
		return f
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.region_rect = region
	sb.texture_margin_left = margin_x
	sb.texture_margin_right = margin_x
	sb.set_content_margin_all(0)
	return sb

func _flat(bg: Color, border: Color) -> StyleBoxFlat:
	var f := StyleBoxFlat.new()
	f.bg_color = bg
	f.border_color = border
	f.set_border_width_all(1 if border.a > 0 else 0)
	f.set_corner_radius_all(3)
	f.content_margin_left = 4
	f.content_margin_right = 4
	return f

func _lbl(text: String, size: int, col: Color, font: Font = null, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	return UIKit.label(text, size, col, font if font else UIKit.font_regular, align)

## Un borde oscuro alrededor de las letras (los créditos van sobre la calle).
func _ol(l: Label) -> Label:
	l.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.02))
	l.add_theme_constant_override("outline_size", 7)
	return l

func _flap(cells: int, size: int, col: Color, right := false) -> Control:
	var f = RankScreens.FlapText.new()
	f.right_align = right
	f.setup(cells, size, _sb_flap, _sb_flap_flip, col)
	return f

## La cuenta de la Great Starfall: el cartel de persianas grande (5 filas + la de Nell si está más abajo).
func _build_count() -> void:
	_count = PanelContainer.new()
	_count.add_theme_stylebox_override("panel", _sb_board)
	UIKit.place(_count, Vector2(0.5, 0.0), Vector2(-390, 34), Vector2(780, 0), Control.GROW_DIRECTION_BOTH)
	_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_count)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 7)
	_count.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	v.add_child(head)
	if _tex["icon_rank"]:
		var ic := TextureRect.new()
		ic.texture = _tex["icon_rank"]
		ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ic.custom_minimum_size = Vector2(32, 32)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		head.add_child(ic)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 0)
	hv.add_child(_lbl("THE GREAT STARFALL COUNT", 26, AMBER, UIKit.font_bold))
	hv.add_child(_lbl("The Lantern Board · top 30 shops of the Amber Drift", 17, MUTED))
	head.add_child(hv)
	for i in 5:
		var r := _count_row()
		v.add_child(r["box"])
		_count_rows.append(r)
	_count_gap = _lbl("·  ·  ·", 20, MUTED, UIKit.font_bold, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(_count_gap)
	_count_me = _count_row()
	v.add_child(_count_me["box"])
	_count.visible = false

func _count_row() -> Dictionary:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", _sb_empty)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	box.add_child(h)
	var pos = _flap(2, 22, AMBER_HI, true)
	h.add_child(pos)
	var crest := TextureRect.new()
	crest.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	crest.custom_minimum_size = Vector2(32, 32)
	crest.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	crest.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	crest.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(crest)
	var nm = _flap(24, 22, AMBER)
	h.add_child(nm)
	var world := _lbl("", 18, MUTED)
	world.custom_minimum_size = Vector2(118, 0)
	world.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(world)
	var score := _lbl("", 20, AMBER_HI, UIKit.font_bold, HORIZONTAL_ALIGNMENT_RIGHT)
	score.custom_minimum_size = Vector2(76, 0)
	score.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(score)
	return {"box": box, "pos": pos, "crest": crest, "name": nm, "world": world, "score": score}

## La franja de quien habla, abajo al centro: su cabeza, su nombre y su línea.
func _build_caption() -> void:
	_cap = PanelContainer.new()
	var sb := UIKit.panel_style(Color(0.07, 0.06, 0.05, 0.9), AMBER, 2, 6, 12)
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	_cap.add_theme_stylebox_override("panel", sb)
	UIKit.place(_cap, Vector2(0.5, 1.0), Vector2(-430, -14), Vector2(860, 0), Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BEGIN)
	_cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_cap)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	_cap.add_child(h)
	var frame := PanelContainer.new()
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = Color(0.2, 0.16, 0.12, 0.9)
	fsb.border_color = Color(0.55, 0.42, 0.25)
	fsb.set_border_width_all(2)
	fsb.set_corner_radius_all(5)
	frame.add_theme_stylebox_override("panel", fsb)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cap_por = TextureRect.new()
	_cap_por.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_cap_por.custom_minimum_size = Vector2(64, 64)
	_cap_por.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cap_por.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	frame.add_child(_cap_por)
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(frame)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(v)
	var nh := HBoxContainer.new()
	nh.add_theme_constant_override("separation", 10)
	v.add_child(nh)
	_cap_name = _lbl("", 21, AMBER, UIKit.font_bold)
	nh.add_child(_cap_name)
	_cap_sub = _lbl("", 16, MUTED)
	_cap_sub.size_flags_vertical = Control.SIZE_SHRINK_END
	nh.add_child(_cap_sub)
	_cap_line = _lbl("", 22, CREAM)
	_cap_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cap_line.custom_minimum_size = Vector2(740, 0)
	v.add_child(_cap_line)
	_cap.visible = false

## La tarjeta del premio con el resumen de la temporada.
func _build_card() -> void:
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", _sb_board)
	UIKit.place(_card, Vector2(0.5, 0.5), Vector2(-340, -40), Vector2(680, 80), Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BOTH)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_card.add_child(v)
	_card_art = TextureRect.new()
	_card_art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_card_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_card_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_card_art.custom_minimum_size = Vector2(384, 168)
	_card_art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(_card_art)
	_card_title = _lbl("", 34, AMBER, UIKit.font_bold, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(_card_title)
	_card_line = _lbl("", 20, CREAM, null, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(_card_line)
	_card_season = _lbl("", 16, MUTED, null, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(_card_season)
	var rule := ColorRect.new()
	rule.color = Color(0.85, 0.62, 0.3, 0.45)
	rule.custom_minimum_size = Vector2(0, 2)
	v.add_child(rule)
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 14)
	g.add_theme_constant_override("v_separation", 4)
	g.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(g)
	for i in 8:
		var k := _lbl("", 18, MUTED, null, HORIZONTAL_ALIGNMENT_RIGHT)
		k.custom_minimum_size = Vector2(140, 0)
		var val := _lbl("", 19, CREAM, UIKit.font_bold)
		val.custom_minimum_size = Vector2(150, 0)
		g.add_child(k)
		g.add_child(val)
		_card_vals.append([k, val])
	var bh := HBoxContainer.new()
	bh.alignment = BoxContainer.ALIGNMENT_END
	bh.add_theme_constant_override("separation", 10)
	v.add_child(bh)
	_card_key = HBoxContainer.new()
	bh.add_child(_card_key)
	_card_btn = _button("Continue", true, func(): _next = true, 190.0)
	bh.add_child(_card_btn)
	_card.visible = false

## Los créditos: una columna que sube despacio sobre la calle (no es un texto que se aleja en perspectiva).
func _build_credits() -> void:
	_credits = Control.new()
	_credits.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_credits.clip_contents = true
	_credits.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_credits)
	# --- POLISH LOOK (P3): una banda oscura en degradé detrás de los créditos (la calle sigue viéndose arriba)
	var band := TextureRect.new()
	var bg := Gradient.new()
	bg.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	bg.colors = PackedColorArray([Color(0.04, 0.03, 0.06, 0.0), Color(0.04, 0.03, 0.06, 0.7), Color(0.03, 0.02, 0.05, 0.9)])
	var bt := GradientTexture2D.new()
	bt.gradient = bg
	bt.fill_from = Vector2(0.0, 0.0)
	bt.fill_to = Vector2(0.0, 1.0)
	bt.width = 4
	bt.height = 128
	band.texture = bt
	band.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	band.stretch_mode = TextureRect.STRETCH_SCALE
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.set_anchors_preset(Control.PRESET_FULL_RECT)
	band.anchor_top = 0.3
	band.offset_top = 0.0
	_credits.add_child(band)
	# --- end POLISH LOOK
	_cred_box = VBoxContainer.new()
	_cred_box.add_theme_constant_override("separation", 10)
	_cred_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIKit.place(_cred_box, Vector2(0.5, 0.0), Vector2(-360, 720), Vector2(720, 0), Control.GROW_DIRECTION_BOTH)
	_credits.add_child(_cred_box)
	# --- POLISH LOOK (P3): el logo de verdad (el del título) en vez del nombre en letra común
	if ResourceLoader.exists("res://assets/ui/logo.png"):
		var logo := TextureRect.new()
		logo.texture = load("res://assets/ui/logo.png")
		logo.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		logo.custom_minimum_size = Vector2(402, 130)   # (804 x 261 a la mitad: pixeles enteros)
		logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_cred_box.add_child(logo)
	else:
		_cred_box.add_child(_ol(_lbl("SECONDHAND STARS", 38, AMBER, UIKit.font_bold, HORIZONTAL_ALIGNMENT_CENTER)))
	# --- end POLISH LOOK
	_cred_box.add_child(_ol(_lbl("Season one · the Starfall Season", 19, MUTED, null, HORIZONTAL_ALIGNMENT_CENTER)))
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 18)
	_cred_box.add_child(sp)
	var i := 0
	while i < CREDITS.size():
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 30)
		for j in 2:
			var cell := VBoxContainer.new()
			cell.custom_minimum_size = Vector2(345, 0)
			cell.add_theme_constant_override("separation", 0)
			if i + j < CREDITS.size():
				cell.add_child(_ol(_lbl(String(CREDITS[i + j][0]), 22, CREAM, UIKit.font_bold, HORIZONTAL_ALIGNMENT_CENTER)))
				cell.add_child(_ol(_lbl(String(CREDITS[i + j][1]), 17, Color(0.86, 0.8, 0.7), null, HORIZONTAL_ALIGNMENT_CENTER)))
			h.add_child(cell)
		_cred_box.add_child(h)
		i += 2
	var sp2 := Control.new()
	sp2.custom_minimum_size = Vector2(0, 26)
	_cred_box.add_child(sp2)
	_cred_box.add_child(_ol(_lbl("Fixed here. Properly.", 24, AMBER_HI, UIKit.font_bold, HORIZONTAL_ALIGNMENT_CENTER)))
	_cred_box.add_child(_ol(_lbl("Thanks for keeping the lights on.", 20, CREAM, null, HORIZONTAL_ALIGNMENT_CENTER)))
	_credits.visible = false

## La placa final: [Keep trading] (primario) y [Title].
func _build_end() -> void:
	_end = PanelContainer.new()
	_end.add_theme_stylebox_override("panel", _sb_board)
	UIKit.place(_end, Vector2(0.5, 1.0), Vector2(-330, -60), Vector2(660, 0), Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BEGIN)
	_end.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_end)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	_end.add_child(v)
	_end_line = _lbl("", 22, CREAM, null, HORIZONTAL_ALIGNMENT_CENTER)
	_end_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_end_line)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 10)
	v.add_child(h)
	_end_keep_key = HBoxContainer.new()
	h.add_child(_end_keep_key)
	_end_keep = _button("Keep trading", true, func(): _pick("keep"), 300.0)
	_end_keep.mouse_entered.connect(func(): _select_end(0))
	h.add_child(_end_keep)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(12, 0)
	h.add_child(gap)
	_end_title_key = HBoxContainer.new()
	h.add_child(_end_title_key)
	_end_title = _button("Title", false, func(): _pick("title"), 150.0)
	_end_title.mouse_entered.connect(func(): _select_end(1))
	h.add_child(_end_title)
	_end.visible = false

## La ayuda de las teclas, abajo a la derecha (se rehace al cambiar de aparato).
func _build_hint() -> void:
	_hint = HBoxContainer.new()
	_hint.add_theme_constant_override("separation", 6)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIKit.place(_hint, Vector2(1.0, 0.0), Vector2(-24, 18), Vector2(0, 30), Control.GROW_DIRECTION_BEGIN)
	_root.add_child(_hint)

func _primary(b: Button) -> void:
	for pair in [["normal", "btn_primary9.png"], ["hover", "btn_primary_hover9.png"], ["pressed", "btn_primary_pressed9.png"],
			["disabled", "btn_disabled9.png"]]:
		var sb := UIKit.nine(pair[1], 12, 15)
		if sb:
			sb.content_margin_left = maxf(sb.content_margin_left, 18.0)
			sb.content_margin_right = maxf(sb.content_margin_right, 18.0)
			b.add_theme_stylebox_override(pair[0], sb)

func _button(text: String, primary: bool, cb: Callable, w := 180.0) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size", 21)
	b.custom_minimum_size = Vector2(w, 48)
	if primary:
		_primary(b)
	b.pressed.connect(func():
		Sfx.play("click", 0.05, -4.0)
		cb.call())
	b.mouse_entered.connect(func(): Sfx.play("hover", 0.05, -14.0))
	return b

## Un Actor por cuadro, escondido (los que se llevan el elenco de la fiesta) y su cabeza para la franja.
func _prebuild() -> void:
	for id in CROWD + BEAT_CAST + ["nell", "kettle"]:
		if not is_inside_tree():
			return
		_portrait(id)
		if id in ["nell", "kettle", "raker", "mags", "vendor", "rival"]:
			continue   # (ya están en la calle)
		_actor(id)
		await get_tree().process_frame
	_prebuilt = true

func _street_node() -> Node:
	if _street and is_instance_valid(_street):
		return _street
	var p := get_parent()
	if p and p.get("street") != null:
		_street = p.get("street")
	return _street

## Un Actor propio del elenco (escondido fuera de la escena); null si no hay hoja.
func _actor(id: String) -> Actor:
	if _actors.has(id) and is_instance_valid(_actors[id]):
		return _actors[id]
	var st := _street_node()
	if st == null or not st.has_method("make_actor") or not ResourceLoader.exists("res://assets/chars/%s_idle.png" % id):
		return null
	var a: Actor = st.make_actor(id, Vector3(30.0, 0.0, -1.6), -1)
	a.visible = false
	a.quiet = true
	_actors[id] = a
	return a

## El que hace de id en la fiesta: los que ya están en la calle se toman prestados (Raker, Mags, Dolly, Glint).
func _cast(id: String) -> Actor:
	var st := _street_node()
	if st:
		match id:
			"raker":
				return st.get("raker")
			"mags":
				return st.get("mags")
			"vendor":
				if st.has_method("vendor_actor") and st.vendor_actor() != null:
					return st.vendor_actor()
			"rival":
				if st.has_method("rival_actor") and st.rival_actor() != null:
					return st.rival_actor()
			"nell":
				return st.get("nell")
			"kettle":
				return st.get("kettle")
	return _actor(id)

## La cabeza de alguien (un recorte de 40x40 del primer cuadro de su hoja).
func _portrait(id: String) -> Texture2D:
	if _por.has(id):
		return _por[id]
	var path := "res://assets/chars/%s_idle.png" % id
	if not ResourceLoader.exists(path):
		_por[id] = null
		return null
	var tex: Texture2D = load(path)
	var head: Vector2 = HEADS.get(id, CastData.PORTRAIT_ANCHORS.get(id, {}).get("head", Vector2(32, 34)))
	var at := AtlasTexture.new()
	at.atlas = tex
	var x0 := clampf(head.x - 20.0, 0.0, 24.0)
	var y0 := clampf(head.y - 20.0, 0.0, 56.0)
	at.region = Rect2(x0, y0, 40, 40)
	_por[id] = at
	return at

# ================================================================== la API (§8.8)

## await gala.play(main, champion) -> "keep" | "title". Empieza de cero cada vez.
func play(main: Node, champion: bool) -> String:
	_main = main
	_street = main.get("street") if main else null
	_champion = champion
	last_champion = champion
	plays += 1
	beats_log.clear()
	frozen = false
	_open = true
	_next = false
	_skip = false
	_abort = false
	_choice = ""
	_end_sel = 0
	stage = "beats"
	_cores = int(Game.flag("cores", 0))
	print("GALA play champion=%s auto=%s place=%d" % [str(champion), str(auto), Ranking.position()])
	await _setup_scene()
	await _beats()
	if _skip and not _abort:
		_skip_fill()
	if not _abort:
		await _award_card()
	if not _abort and not auto:
		await _credits_roll()
	if not _abort:
		await _end_choice()
	_teardown()
	var c := choice_override if choice_override != "" else (_choice if _choice != "" else "keep")
	_open = false
	stage = ""
	finished.emit(c)
	return c

func is_open() -> bool:
	return _open

## Termina ya (elige "keep"): los bucles salen en el cuadro siguiente.
func close_now() -> void:
	if _open:
		_abort = true

## "next" (lo que haría E / A) | "skip" (Esc / B) | "keep" | "title". Para los bots y las pruebas.
func press(id := "next") -> void:
	match id:
		"skip":
			_back()
		"keep", "title":
			if stage == "end":
				_pick(id)
		_:
			_advance()

## La capa cuyos botones toca el mando (main._pad_root, gancho SS2 RANK).
func pad_root() -> Control:
	return _root

# ================================================================== la escena

func _setup_scene() -> void:
	var st := _street_node()
	if _main and _main.has_method("fade_to") and not auto:
		await _main.fade_to(1.0, 0.5)
	# (web) el tema de la gala y la música de la noche, decodificados bajo el negro (si ya lo estaban, nada)
	Sfx.prewarm_late("gala")
	Sfx.prewarm_late("night")
	if _main:
		var scr = _main.get("screens")
		if scr and scr.has_method("hide_all"):
			scr.hide_all()
		var hud = _main.get("hud")
		if hud:
			_call(hud, "show_top", [false])
			_call(hud, "hide_prompt", [])
			_call(hud, "clear_tip", [])
			_call(hud, "hide_banner", [])
		if _main.has_method("use_world") and st:
			_main.use_world(st)
	if st == null:
		_layer.visible = true
		return
	_call(st, "set_event", ["finale"])
	st.set_night(true)
	_call(st, "set_moons", ["normal"])
	_ring(0, "dark")   # el anillo a oscuras: contesta en el momento de Old Seven
	_call(st, "set_comet", [false])
	_call(st, "set_balloon", [""])
	_call(st, "set_band", [bool(Game.flag("band", false)) or int(Season.rep_tier().get("rep", 0)) >= 60])
	_call(st, "refresh_sign", [])
	_call(st, "set_door_open_sign", [false])
	# Nell y Kettle delante de la puerta; la cámara quieta sobre la fachada, el cartel y la gente
	var shop_x := float(StreetWorld.SHOP_X)
	_nell_pos = Vector3(shop_x, 0.0, -2.05)
	_kettle_pos = Vector3(shop_x + 0.65, 0.0, -1.75)
	var walker = st.get("walker")
	if walker:
		walker.frozen = true
	st.set("kettle_follow", false)
	var nell: Actor = st.get("nell")
	var kettle: Actor = st.get("kettle")
	if nell:
		nell.visible = true
		nell.global_position = _nell_pos
		nell.face(1)
		nell.set_walking(false)
	if kettle:
		kettle.visible = true
		kettle.global_position = _kettle_pos
		kettle.face(1)
		kettle.set_walking(false)
	_cam_dist0 = float(st.get("cam_dist"))
	_cam = {"x": CAM_X, "d": _cam_dist0}
	st.set("cam_fixed", true)
	_place_cam()
	# el elenco: los propios escondidos y fuera; los prestados, anotados (vuelven a su sitio al final)
	_borrowed.clear()
	for id in CROWD + BEAT_CAST:
		var a := _cast(id)
		if a == null:
			continue
		if id in ["raker", "mags", "vendor", "rival"]:
			_borrowed.append({"a": a, "pos": a.global_position, "face": a.facing, "vis": a.visible})
			if id == "vendor":
				a.visible = false   # (Dolly llega rodando desde su patio, fuera de cuadro)
			continue
		a.visible = false
		a.global_position = Vector3(30.0, 0.0, -1.6)
	Sfx.ambience("")
	Sfx.music("gala")
	_dim.color.a = 0.0
	_count.visible = false
	_cap.visible = false
	_card.visible = false
	_credits.visible = false
	_end.visible = false
	_layer.visible = true
	_pad_was = PadCursor.pad_in_use
	_refresh_hint()
	set_process(true)
	if _main and _main.has_method("fade_to") and not auto:
		await _main.fade_to(0.0, 0.8)

func _teardown() -> void:
	set_process(false)
	_layer.visible = false
	var st := _street_node()
	if st == null:
		return
	for id in _actors:
		var a: Actor = _actors[id]
		if is_instance_valid(a):
			a.visible = false
			a.clear_emote()
			a.global_position = Vector3(30.0, 0.0, -1.6)
	for b in _borrowed:
		var a2: Actor = b["a"]
		if is_instance_valid(a2):
			a2.global_position = b["pos"]
			a2.face(int(b["face"]))
			a2.visible = bool(b["vis"])
			a2.set_walking(false)
			a2.clear_emote()
	_borrowed.clear()
	var kettle: Actor = st.get("kettle")
	if kettle:
		kettle.clear_emote()
	var nell: Actor = st.get("nell")
	if nell:
		nell.clear_emote()
	st.set("kettle_follow", true)
	var walker = st.get("walker")
	if walker:
		walker.frozen = false
	st.set("cam_dist", _cam_dist0)
	st.set("cam_fixed", false)
	_call(st, "set_band", [false])
	_call(st, "set_event", [""])
	# lo que queda: el cometa en el cartel si ganó (o ya tenía la corona); con los 3 núcleos, la lámpara siete
	# sigue encendida en el anillo (§2.6)
	_call(st, "set_comet", [_champion or bool(Game.get("crown_seen"))])
	_ring(-1, "blink")   # (W: -1 = automático: la lámpara siete fija si Old Seven tiene sus 3 núcleos)

func _call(o: Object, m: String, args: Array) -> void:
	if o and o.has_method(m):
		o.callv(m, args)

## Las lámparas del anillo: set_ring_lamps(n, rest) de W ("blink" | "dark"; n = -1 automático); con una API de un solo
## argumento (el stub de S) solo n (y -1 como 0).
func _ring(n: int, rest: String) -> void:
	var st := _street_node()
	if st == null or not st.has_method("set_ring_lamps"):
		return
	for m in st.get_method_list():
		if String(m["name"]) == "set_ring_lamps":
			if (m["args"] as Array).size() >= 2:
				st.set_ring_lamps(n, rest)
			else:
				st.set_ring_lamps(maxi(n, 0))
			return

func _place_cam() -> void:
	var st := _street_node()
	if st == null:
		return
	st.set("cam_dist", float(_cam["d"]))
	if st.has_method("place_camera"):
		st.place_camera(float(_cam["x"]))

## La cámara se acerca o se aleja despacio (el cometa).
func _cam_to(x: float, d: float, t: float) -> void:
	if auto:
		_cam["x"] = x
		_cam["d"] = d
		_place_cam()
		return
	var x0 := float(_cam["x"])
	var d0 := float(_cam["d"])
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_method(func(k: float):
		_cam["x"] = lerpf(x0, x, k)
		_cam["d"] = lerpf(d0, d, k)
		_place_cam(), 0.0, 1.0, t)

# ================================================================== los momentos

## Espera t segundos (E / A adelantan). Devuelve true si hay que saltar a la tarjeta (Esc / B) o cerrar.
func _hold(t: float) -> bool:
	if demo_stop != "" and _stop_hit():
		frozen = true
		while not _abort:
			await get_tree().process_frame
		return true
	var left := AUTO_BEAT if auto else t
	_next = false
	while left > 0.0 and not _next and not _skip and not _abort:
		await get_tree().process_frame
		left -= get_process_delta_time()
	_next = false
	return _skip or _abort

func _stop_hit() -> bool:
	for e in beats_log:
		if String(e).begins_with(demo_stop):
			return true
	return false

func _say(who: String, line: String) -> void:
	var w: Array = WHO.get(who, [Data.char_name(who), ""])
	_cap_name.text = String(w[0])
	_cap_sub.text = String(w[1])
	_cap_line.text = line
	var tex: Texture2D = _tex.get("rosa") if who == "rosa" else _portrait(who)
	_cap_por.texture = tex
	_cap_por.get_parent().visible = tex != null
	_cap.visible = true
	beats_log.append("%s: %s" % [who, line])
	var a: Actor = null
	if who != "rosa":
		a = _cast(who)
	if a and a.visible:
		a.emote("heart" if who != "hermit" else "star", 1.4)

func _beats() -> void:
	var place := Ranking.position()
	# 1. la radio
	Sfx.play("sfx_signal", 0.0, -3.0)
	_say("rosa", LINES["rosa_count"])
	if await _hold(BEAT):
		return
	# 2. la cuenta 5 -> 1 (y la fila de Nell si está más abajo)
	_cap.visible = false
	if await _countdown(place):
		return
	if not _champion:
		var top: Dictionary = Ranking.table()[0]
		var close := place <= 5
		if String(top["id"]) == Ranking.RIVAL:
			_say("rival", LINES["glint_won"])
		elif String(top["id"]) == Ranking.CHAMPION:
			_say("rosa", LINES["rosa_gear_close" if close else "rosa_gear_far"])
		else:
			_say("rosa", String(LINES["rosa_other_close" if close else "rosa_other_far"]).replace("{shop}", String(top["name"])).replace("{world}", String(top["world_name"])))
		if await _hold(BEAT):
			return
	# 3. llega la gente de la calle
	_count.visible = false
	_cap.visible = false
	await _walk_in()
	if await _hold(BEAT + 0.6):
		return
	if _champion:
		# 4. Tolle certifica
		await _bring("inspector", Vector3(_nell_pos.x + 0.8, 0.0, -2.6), 1.8)
		Sfx.play("sfx_stamp", 0.0, -3.0)
		_say("inspector", LINES["tolle"])
		if await _hold(BEAT + 0.6):
			return
		# 5. Glint, un poco aparte (y Buff, si está su hoja)
		var buff := _actor("buffbot")
		if buff:
			_bring_no_wait(buff, Vector3(_nell_pos.x - 2.05, 0.0, -1.3))
		await _bring("rival", Vector3(_nell_pos.x - 1.35, 0.0, -1.55), 1.6)
		_say("rival", LINES["glint"])
		if await _hold(BEAT):
			return
		if String(Game.flag("favour", "")) == "done":
			_say("rival", LINES["glint_favour"])
			if await _hold(BEAT):
				return
		# 6. Mags y Raker atornillan el cometa de latón al cartel
		if await _comet():
			return
	# 7. Old Seven junto a Kettle: el anillo contesta
	if await _seven():
		return
	# 8. la lluvia de chispas y el epílogo, una línea por hilo
	_call(_street_node(), "play_sparks", [])
	for e in _epilogue():
		_say(String(e[0]), String(e[1]))
		if await _hold(2.9):
			return
	# 9. Kettle silba; Nell
	var kettle := _cast("kettle")
	if kettle:
		kettle.emote("note", 2.2)
		kettle.hop(2)
	Sfx.play("whistle", 0.02, -6.0)
	if _champion:
		_say("nell", LINES["nell_win"])
		await _hold(BEAT + 0.8)
	else:
		_say("nell", LINES["nell_next"])
		if await _hold(2.2):
			return
		_say("kettle", LINES["kettle_next"])
		await _hold(2.0)

## Esc / B en los momentos: la calle queda como al final de la fiesta (la gente en sus lugares, el cometa en el
## cartel si ganó, el anillo según los núcleos) y sigue la tarjeta.
func _skip_fill() -> void:
	_count.visible = false
	_cap.visible = false
	_settle_count()
	var st := _street_node()
	if st == null:
		return
	beats_log.append("skipped")
	var spots: Array = st.gala_spots() if st.has_method("gala_spots") else []
	var n := 0
	for id in CROWD:
		var a := _cast(id)
		if a == null or n >= spots.size():
			continue
		if not a.visible or a.global_position.x > 20.0:
			a.global_position = spots[n]
			a.visible = true
			a.face_towards(_nell_pos)
		n += 1
	var place := {"hermit": Vector3(_nell_pos.x - 0.85, 0.0, -2.6)}
	if _champion:
		place["inspector"] = Vector3(_nell_pos.x + 0.8, 0.0, -2.6)
		place["rival"] = Vector3(_nell_pos.x - 1.35, 0.0, -1.55)
		place["buffbot"] = Vector3(_nell_pos.x - 2.05, 0.0, -1.3)
	for id in place:
		var b := _cast(String(id))
		if b and (not b.visible or b.global_position.x > 20.0 or String(id) == "rival"):
			b.global_position = place[id]
			b.visible = true
			b.face_towards(_nell_pos)
	if _champion:
		_call(st, "set_comet", [true])
	_ring(7 if _cores >= 3 else 0, "dark" if _cores >= 3 else "blink")

## La cuenta del split-flap: #5 abajo, #1 arriba, de a una fila; Nell aparte si está más abajo de #5.
func _countdown(place: int) -> bool:
	var tab: Array = Ranking.table()
	_count.visible = true
	for r in _count_rows:
		_clear_row(r)
	_clear_row(_count_me)
	_count_gap.visible = place > 5
	_count_me["box"].visible = place > 5
	beats_log.append("countdown")
	for i in range(4, -1, -1):
		if i < tab.size():
			_fill_row(_count_rows[i], tab[i])
			Sfx.play("sfx_flap", 0.04, -6.0)
		if await _hold(0.95 if i > 0 else 1.2):
			_settle_count()
			return true
	if place > 5 and place - 1 < tab.size():
		_fill_row(_count_me, tab[place - 1])
		Sfx.play("sfx_flap", 0.04, -6.0)
		if await _hold(1.2):
			_settle_count()
			return true
	_settle_count()
	beats_log.append("count_done")
	return await _hold(2.0)

func _clear_row(r: Dictionary) -> void:
	r["pos"].set_now("")
	r["name"].set_now("")
	r["crest"].texture = null
	r["world"].text = ""
	r["score"].text = ""
	(r["box"] as PanelContainer).add_theme_stylebox_override("panel", _sb_empty)

func _fill_row(r: Dictionary, row: Dictionary) -> void:
	var id := String(row["id"])
	var world := "Rustwater" if id in Ranking.RUSTWATER else String(row["world_name"])
	var me := id == Ranking.ME
	r["name"].color = AMBER_HI if me else (PINK if id == Ranking.RIVAL else AMBER)
	if auto:
		r["pos"].set_now(str(int(row["pos"])))
		r["name"].set_now(String(row["name"]).to_upper())
	else:
		r["pos"].flip_to(str(int(row["pos"])))
		r["name"].flip_to(String(row["name"]).to_upper(), 0.05)
	r["crest"].texture = _crest_at[clampi(int(row["crest"]), 0, 29)]
	r["world"].text = world
	r["score"].text = "%d ★" % int(row["score"])
	(r["box"] as PanelContainer).add_theme_stylebox_override("panel", _sb_me if me else (_sb_rival if id == Ranking.RIVAL else _sb_empty))

func _settle_count() -> void:
	for r in _count_rows + [_count_me]:
		r["pos"].settle()
		r["name"].settle()

## La gente llega a sus lugares desde los dos lados (los de la calle, desde donde están) y saluda a Nell.
func _walk_in() -> void:
	beats_log.append("walk_in")
	var st := _street_node()
	var spots: Array = st.gala_spots() if st and st.has_method("gala_spots") else []
	var n := 0
	var who: Array = []
	for id in CROWD:
		var a := _cast(id)
		if a == null or n >= spots.size():
			continue
		var target: Vector3 = spots[n]
		n += 1
		who.append(a)
		if not a.visible or a.global_position.x > 20.0:
			var from_left := target.x < float(StreetWorld.SHOP_X)
			a.global_position = Vector3((CAM_X - 8.6) if from_left else (CAM_X + 8.6), 0.0, target.z)
		a.visible = true
		if auto:
			a.global_position = target
			a.face_towards(_nell_pos)
		else:
			_walk_after(a, target, 0.12 * n, 2.7)
	Sfx.play("sfx_cheer", 0.0, -3.0)
	await _hold(1.4)
	var k := 0
	for a2 in who:
		if k % 2 == 0:
			(a2 as Actor).emote("heart", 1.6)
		k += 1
	var nell := _cast("nell")
	if nell:
		nell.hop(1)
	beats_log.append("walk_done")

func _walk_after(a: Actor, target: Vector3, delay: float, speed: float) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	if not _open or not is_instance_valid(a):
		return
	await a.walk_to(target, speed)
	if _open and is_instance_valid(a):
		a.face_towards(_nell_pos)

## Alguien entra para su momento (desde la derecha si no estaba) y se para en p mirando a Nell. Espera hasta t s.
func _bring(id: String, p: Vector3, t: float) -> void:
	var a := _cast(id)
	if a == null:
		return
	_bring_no_wait(a, p)
	if not auto:
		await get_tree().create_timer(t).timeout

func _bring_no_wait(a: Actor, p: Vector3) -> void:
	if not a.visible or a.global_position.x > 20.0:
		a.global_position = Vector3((CAM_X - 8.6) if p.x < _nell_pos.x else (CAM_X + 8.6), 0.0, p.z)
	a.visible = true
	if auto:
		a.global_position = p
		a.face_towards(_nell_pos)
	else:
		_walk_after(a, p, 0.0, 2.8)

## Mags y Raker atornillan el cometa al cartel; la cámara se acerca un poco; el cartel brilla.
func _comet() -> bool:
	beats_log.append("comet")
	var shop_x := float(StreetWorld.SHOP_X)
	var raker := _cast("raker")
	var mags := _cast("mags")
	var spots := {}
	for pair in [[raker, Vector3(shop_x - 0.85, 0.0, -3.35)], [mags, Vector3(shop_x + 0.85, 0.0, -3.35)]]:
		var a: Actor = pair[0]
		if a:
			spots[a] = a.global_position
			a.visible = true
			if auto:
				a.global_position = pair[1]
			else:
				_walk_after(a, pair[1], 0.0, 3.0)
	_cam_to(shop_x - 0.15, _cam_dist0 - 1.8, 1.6)   # --- POLISH LOOK (P3): +0.5 -> -0.15: el cartel al centro y el letrero de Shine Again entero
	_say("mags", LINES["mags_bolt"])
	if await _hold(1.8):
		return true
	for a in spots:
		(a as Actor).face_towards(Vector3(shop_x, 0, -4.0))
		(a as Actor).hop(2, 0.22)
	Sfx.play("ratchet", 0.05, -4.0)
	if await _hold(0.7):
		return true
	Sfx.play("ratchet", 0.05, -4.0)
	if await _hold(0.6):
		return true
	_call(_street_node(), "set_comet", [true])
	_call(_street_node(), "refresh_sign", [])
	_call(_street_node(), "celebrate_sign", [])
	Sfx.play("sfx_comet", 0.0, -2.0)
	_cap.visible = false
	beats_log.append("comet_on")
	var nell := _cast("nell")
	if nell:
		nell.emote("star", 2.0)
		nell.hop(2)
	if await _hold(BEAT):
		return true
	for a in spots:
		if not auto:
			_walk_after(a, spots[a], 0.0, 2.6)
		else:
			(a as Actor).global_position = spots[a]
	_cam_to(CAM_X, _cam_dist0, 1.4)
	return false

## Old Seven entra junto a Kettle (Kettle corre hacia él), su lámpara parpadea y el anillo contesta.
func _seven() -> bool:
	beats_log.append("seven")
	var seven := _cast("hermit")
	var kettle := _cast("kettle")
	var p := Vector3(_nell_pos.x - 0.85, 0.0, -2.6)
	if seven:
		_bring_no_wait(seven, p)
	if not auto:
		await get_tree().create_timer(1.6).timeout
	if kettle:
		var kp := Vector3(p.x + 0.45, 0.0, -2.2)
		if auto:
			kettle.global_position = kp
		else:
			_walk_after(kettle, kp, 0.0, 3.6)
	if await _hold(1.2):
		return true
	if kettle:
		kettle.face_towards(p)
		kettle.hop(2)
		kettle.emote("heart", 1.6)
	# la lámpara de Old Seven parpadea dos veces (una señal) y el anillo contesta como un faro
	if seven:
		var tw := seven.create_tween()
		for i in 2:
			tw.tween_property(seven.sprite, "modulate", Color(1.9, 1.7, 1.2), 0.18)
			tw.tween_property(seven.sprite, "modulate", Color.WHITE, 0.3)
	Sfx.play("bell", 0.0, -8.0)
	if await _hold(1.0):
		return true
	var st := _street_node()
	if _cores >= 3:
		_ring(7, "dark")
		Sfx.play("sfx_comet", 0.0, -9.0)
		_say("hermit", LINES["seven_all"])
		beats_log.append("ring_7")
	else:
		_ring(2, "dark")
		_say("hermit", LINES["seven_two"])
		beats_log.append("ring_2")
		if await _hold(1.4):
			return true
		_ring(0, "dark")
	return await _hold(BEAT)

## Las líneas del epílogo (§5.5), una por hilo, según cómo quedó cada uno.
func _epilogue() -> Array:
	var out: Array = []
	match String(Game.flag("crate", "")):
		"delivered":
			out.append(["rook", LINES["rook_delivered"]])
		"declared":
			out.append(["rook", LINES["rook_declared"]])
		"refused":
			out.append(["rook", LINES["rook_refused"]])
		"seized":
			out.append(["rook", LINES["rook_seized"]])
	if not _champion:
		out.append(["inspector", LINES["tolle_certified" if String(Game.flag("grade", "")) == "certified" else "tolle_other"]])
	if Game.debt > 0:
		out.append(["dockmaster", LINES["hesk_short"]])
	elif bool(Game.flag("paid_in_full", false)):
		out.append(["dockmaster", LINES["hesk_paid_win" if _champion else "hesk_paid"]])
	if bool(Game.flag("band", false)):
		out.append(["singer", LINES["lune_band"]])
	out.append(["clatter", LINES["clatter"]])
	if String(Game.flag("race", "")) == "podium":
		out.append(["pipip", LINES["pipip_cup"]])
	return out

# ================================================================== la tarjeta, los créditos, la placa final

func _award_card() -> void:
	stage = "card"
	_skip = false
	_count.visible = false
	_cap.visible = false
	beats_log.append("card")
	var aw := Ranking.award()
	var rc := Ranking.season_recap()
	var tot: Dictionary = Game.totals() if Game.has_method("totals") else {}
	var place := int(rc.get("place", Ranking.position()))
	if _champion:
		_card_art.texture = _tex["comet_card"]
		_card_art.custom_minimum_size = Vector2(384, 168)
		_card_title.text = String(Ranking.AWARDS["champion"]["title"])
		_card_line.text = String(Ranking.AWARDS["champion"]["line"])
	else:
		_card_art.texture = _tex["award_ribbon"]
		_card_art.custom_minimum_size = Vector2(144, 144)
		_card_title.text = String(aw["title"])
		_card_line.text = String(aw["line"])
	_card_season.text = "The Secondhand Star · Rustwater, Saffra · the Starfall Season"
	var best := "+%d ★ · night %d" % [int(rc.get("best_stars", 0)), int(rc.get("best_night", 0))] if int(rc.get("best_night", 0)) > 0 else "-"
	var rows := [["Place", "%s of %d" % [UIKit.ordinal(place), Ranking.SHOPS.size()]],
		["Season ★", str(int(rc.get("score", Ranking.score())))],
		["Repairs", str(int(tot.get("repairs", 0)))],
		["Sales", str(int(tot.get("sales", 0)))],
		["Best night", best],
		["Shops passed", str(int(rc.get("passed", 0)))],
		["Credits earned", "%s cr" % UIKit.num(int(tot.get("earned", 0)))],
		["Star sign", "%d of 5 points" % clampi(int(Game.sign_points), 0, 5)]]
	for i in _card_vals.size():
		(_card_vals[i][0] as Label).text = String(rows[i][0])
		(_card_vals[i][1] as Label).text = String(rows[i][1])
	_card_juice()   # --- POLISH LOOK (P3)
	_card.modulate.a = 0.0
	_card.visible = true
	_dim.color.a = 0.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_card, "modulate:a", 1.0, 0.0 if auto else 0.5)
	tw.tween_property(_dim, "color:a", 0.45, 0.0 if auto else 0.5)
	Sfx.play("sfx_stamp", 0.0, -6.0)
	_refresh_hint()
	# espera E / A / clic (los bots: un instante)
	_next = false
	var t := 0.0
	frozen = demo_stop == "card"
	while not _next and not _abort and not (auto and t > AUTO_BEAT * 2.0):
		await get_tree().process_frame
		t += get_process_delta_time()
	_next = false
	_card.visible = false
	_card_juice_stop()   # --- POLISH LOOK (P3)

# --- POLISH LOOK (P3): la tarjeta viva. Los números cuentan desde 0 en ~0,8 s con el tic de las paletas (el sonido del
# tablero), el arte del cometa late despacio, y una lluvia de chispas sale del cartel cuando aparece. Los bots (auto)
# ven los valores finales al instante. Nada nuevo que compilar (labels, modulate; las chispas ya se calentaron).
func _card_juice() -> void:
	_card_juice_stop()
	if auto:
		return
	var nums: Array = []   # [Label, valor, sufijo, con comas]
	for pair in _card_vals:
		var lv: Label = pair[1]
		var tx := lv.text
		var suffix := ""
		var core := tx
		if tx.ends_with(" cr"):
			core = tx.trim_suffix(" cr")
			suffix = " cr"
		var plain := core.replace(",", "")
		if plain.is_valid_int() and int(plain) > 0:
			nums.append([lv, int(plain), suffix, core.contains(",") or int(plain) >= 1000])
	if not nums.is_empty():
		_card_count = create_tween()
		_card_count.tween_interval(0.35)   # (después del fundido de entrada)
		_card_count.tween_method(_count_step.bind(nums), 0.0, 1.0, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		for i in 7:   # el tic de las paletas mientras cuentan
			_card_count.parallel().tween_callback(func(): Sfx.play("flap", 0.08, -16.0)).set_delay(0.35 + i * 0.11)
		for n in nums:
			(n[0] as Label).text = "0" + String(n[2])
	_card_pulse = create_tween().set_loops()
	_card_pulse.tween_property(_card_art, "modulate", Color(1.22, 1.14, 0.96), 0.9).set_trans(Tween.TRANS_SINE)
	_card_pulse.tween_property(_card_art, "modulate", Color.WHITE, 0.9).set_trans(Tween.TRANS_SINE)
	_call(_street_node(), "play_sparks", [])

func _count_step(k: float, nums: Array) -> void:
	for n in nums:
		var v := int(round(float(n[1]) * k))
		(n[0] as Label).text = (UIKit.num(v) if bool(n[3]) else str(v)) + String(n[2])

func _card_juice_stop() -> void:
	if _card_count and _card_count.is_valid():
		_card_count.kill()
	if _card_pulse and _card_pulse.is_valid():
		_card_pulse.kill()
	_card_art.modulate = Color.WHITE
# --- end POLISH LOOK

func _credits_roll() -> void:
	stage = "credits"
	beats_log.append("credits")
	_skip = false
	_next = false
	if Sfx.has_method("music_playing") and not Sfx.music_playing():
		Sfx.music("night")
	_credits.visible = true
	_dim.color.a = 0.62
	_refresh_hint()
	await get_tree().process_frame
	var h := _cred_box.get_combined_minimum_size().y
	var y0 := 720.0
	var y1 := -h - 20.0
	var dur := 22.0
	var t := 0.0
	while t < dur and not _next and not _skip and not _abort:
		_cred_box.offset_top = lerpf(y0, y1, t / dur)
		_cred_box.offset_bottom = _cred_box.offset_top + h
		await get_tree().process_frame
		if demo_stop == "credits" and t > dur * 0.3:
			frozen = true
			continue
		t += get_process_delta_time()
	_next = false
	_skip = false
	_credits.visible = false

func _end_choice() -> void:
	stage = "end"
	beats_log.append("end")
	_end_keep.text = "Keep trading" if _champion else "Keep trading: chase the comet"
	_end_line.text = LINES["end_win" if _champion and Game.is_campaign() else ("end_crown" if _champion else "end_next")]
	_end.visible = true
	_dim.color.a = 0.25
	_select_end(0)
	_refresh_hint()
	frozen = demo_stop == "end"
	var t := 0.0
	while _choice == "" and not _abort:
		await get_tree().process_frame
		t += get_process_delta_time()
		if auto and t > AUTO_BEAT:
			_choice = choice_override if choice_override != "" else "keep"
	if _choice == "":
		_choice = "keep"
	_end.visible = false
	if Sfx.has_method("music_playing") and Sfx.music_name() == "gala":
		Sfx.music("night")

func _pick(id: String) -> void:
	if stage == "end" and _choice == "":
		_choice = id

func _select_end(i: int) -> void:
	_end_sel = clampi(i, 0, 1)
	_end_keep.modulate = Color.WHITE if _end_sel == 0 else Color(0.8, 0.8, 0.8)
	_end_title.modulate = Color.WHITE if _end_sel == 1 else Color(0.8, 0.8, 0.8)
	_set_key(_end_keep_key, "E" if _end_sel == 0 else "", "A" if _end_sel == 0 else "")
	_set_key(_end_title_key, "E" if _end_sel == 1 else "", "A" if _end_sel == 1 else "")

# ================================================================== las teclas, el ratón, el mando

## E / Enter / Espacio / A (con el gancho) / X: lo siguiente.
func _advance() -> void:
	if not _open:
		return
	if stage == "end":
		_pick("keep" if _end_sel == 0 else "title")
	else:
		_next = true

## Esc / B: saltan a la tarjeta (en los créditos, los saltan; en la tarjeta y la placa no hacen nada).
func _back() -> void:
	if not _open:
		return
	match stage:
		"beats":
			_skip = true
		"credits":
			_next = true

func _on_root_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and stage != "end":
		_advance()

func _input(ev: InputEvent) -> void:
	if not _open or not _layer.visible:
		return
	if ev is InputEventKey and ev.pressed and not ev.echo:
		var k: int = ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
		match k:
			KEY_E, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				_advance()
			KEY_ESCAPE:
				_back()
			KEY_LEFT, KEY_A, KEY_UP, KEY_W:
				if stage == "end":
					_select_end(0)
			KEY_RIGHT, KEY_D, KEY_DOWN, KEY_S:
				if stage == "end":
					_select_end(1)
			_:
				return
		get_viewport().set_input_as_handled()

func _set_key(box: HBoxContainer, key_kb: String, key_pad: String) -> void:
	for c in box.get_children():
		c.queue_free()
	var k := key_pad if PadCursor.pad_in_use else key_kb
	if k == "":
		return
	var kc := UIKit.keycap(k, 16)
	kc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(kc)

## La ayuda de arriba a la derecha según la etapa y el aparato ("E next · Esc skip" / "A next · B skip").
func _refresh_hint() -> void:
	for c in _hint.get_children():
		c.queue_free()
	var pad := PadCursor.pad_in_use
	var pairs: Array = []
	match stage:
		"beats":
			pairs = [["A" if pad else "E", "next"], ["B" if pad else "Esc", "skip"]]
		"card":
			pairs = []   # --- POLISH LOOK (P3): la tarjeta ya trae su tecla junto a Continue (antes salía dos veces)
		"credits":
			pairs = [["A" if pad else "E", "skip"]]
		"end":
			pairs = [["LB/RB" if pad else "← →", "choose"], ["A" if pad else "E", "select"]]
	for p in pairs:
		# --- POLISH LOOK (P5): "LB/RB" son dos botones dibujados (antes una tecla con el texto)
		for k in (String(p[0]).split("/") if String(p[0]) == "LB/RB" else PackedStringArray([String(p[0])])):
			var kc := UIKit.keycap(k, 15)
			kc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			_hint.add_child(kc)
		var l := _lbl(String(p[1]), 17, CREAM)
		l.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.02))
		l.add_theme_constant_override("outline_size", 6)
		_hint.add_child(l)
	if stage == "end":
		_select_end(_end_sel)
	if stage == "card":
		_set_key(_card_key, "E", "A")

func _process(_dt: float) -> void:
	if not _open:
		return
	if PadCursor.pad_in_use != _pad_was:
		_pad_was = PadCursor.pad_in_use
		_refresh_hint()
	# el tema de la gala suena una vez (60 s): después, la música de la noche
	if Sfx.music_name() == "gala" and Sfx.has_method("music_playing") and not Sfx.music_playing() and stage != "beats":
		Sfx.music("night")
