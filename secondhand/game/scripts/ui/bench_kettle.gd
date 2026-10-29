extends Control
class_name BenchKettle
## Kettle en la esquina del banco: el bot-pava ayudante. Quieto (kettle_idle.png, 2 cuadros), SILBA cuando Nell
## acierta (kettle_react.png cuadros 0-1: salta la tapa, chorro de vapor; suena sfx_whistle) y dice "hmm" cuando se
## equivoca (cuadros 2-3: ojo entornado, bocanada gris). Habla con un globo (BenchBubble).
## --- SS BENCH (nuevo). Se dibuja a x3 y solo la parte de abajo del cuadro de 64x96 (Kettle es chiquito).

const SCALE := 3.0
const CROP := Rect2(0, 44, 64, 52)     # la parte del cuadro donde está Kettle (con el vapor)

var bubble: BenchBubble
var _sprite: TextureRect
var _idle: Array = []
var _react: Array = []
var _mode := "idle"      # idle | whistle | hmm
var _t := 0.0
var _mode_t := 0.0
var _hop := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in 2:
		_idle.append(BenchKit.frame("res://assets/chars/kettle_idle.png", i, 64, 96, CROP))
	for i in 4:
		_react.append(BenchKit.frame("res://assets/chars/kettle_react.png", i, 64, 96, CROP))
	_sprite = TextureRect.new()
	_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sprite.stretch_mode = TextureRect.STRETCH_SCALE
	_sprite.size = CROP.size * SCALE
	_sprite.texture = _idle[0] if not _idle.is_empty() else null
	add_child(_sprite)
	custom_minimum_size = CROP.size * SCALE
	size = custom_minimum_size
	bubble = BenchBubble.new()
	bubble.max_width = 200.0     # cabe en la columna izquierda del banco (el globo se centra sobre el pico)
	bubble.tail_x = 0.5
	add_child(bubble)

## El pico de Kettle (donde apunta la cola del globo), en coordenadas de este control.
func spout() -> Vector2:
	return Vector2(40, 22) * SCALE

func say(text: String, dur := 3.0) -> void:
	bubble.say(text, "", dur)
	bubble.point_at(spout() + Vector2(-20, -4))

func whistle(text := "") -> void:
	_set_mode("whistle")
	_hop = 1.0
	Sfx.play("whistle", 0.05, -2.0)
	say(text if text != "" else _pick("whistle"), 1.8)

func hmm(text := "") -> void:
	_set_mode("hmm")
	Sfx.play_pitched("blip", 0.6, -8.0)
	say(text if text != "" else _pick("hmm"), 1.8)

func idle() -> void:
	_set_mode("idle")

func reset() -> void:
	_set_mode("idle")
	_hop = 0.0
	bubble.hide_now()

func _pick(key: String) -> String:
	var a: Array = BenchData.KETTLE.get(key, ["..."])
	return String(a[randi() % a.size()])

func _set_mode(m: String) -> void:
	_mode = m
	_mode_t = 0.0

func _process(delta: float) -> void:
	_t += delta
	_mode_t += delta
	var tex: Texture2D = null
	match _mode:
		"whistle":
			if _react.size() >= 2:
				tex = _react[0 if fmod(_mode_t, 0.24) < 0.12 else 1]
			if _mode_t > 1.4:
				_set_mode("idle")
		"hmm":
			if _react.size() >= 4:
				tex = _react[2 if _mode_t < 0.5 or fmod(_mode_t, 0.6) < 0.3 else 3]
			if _mode_t > 1.4:
				_set_mode("idle")
		_:
			if _idle.size() >= 2:
				tex = _idle[0 if fmod(_t, 1.1) < 0.75 else 1]
	if tex and _sprite.texture != tex:
		_sprite.texture = tex
	# saltito al silbar (en píxeles del arte)
	_hop = maxf(0.0, _hop - delta * 2.8)
	var y := -roundf(sin(_hop * PI) * 4.0) * SCALE if _hop > 0.0 else 0.0
	_sprite.position = Vector2(0, y)
