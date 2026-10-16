extends Node
## Renders the wind functions of shaders/wind.gdshaderinc, one per frame, for a given list of clock values, as images
## (tools/wind_probe.gdshader encodes each value in 16 bits): the proof that the shader's maths is the maths the Python
## port (analysis/windsim_*.py) analysed. Needs a window (xvfb + software GL is fine):
##   xvfb-run -a godot --path . --rendering-driver opengl3 --write-movie <dir>/p.png --fixed-fps 10 --quit-after 24 \
##     res://tools/wind_probe.tscn
## Frame i: mode MODES[i % MODES.size()] at the clock TIMES[i / MODES.size()] (the wind's direction wobble is set to the
## same clock, as scripts/world/wind.gd does with its own).

const MODES := [0, 1, 2, 3, 4]
const TIMES := [12.34, 47.1, 1234.5, 36000.0]

var _mat: ShaderMaterial


func _ready() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var rect := ColorRect.new()
	rect.size = Vector2(1280, 720)
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://tools/wind_probe.gdshader")
	rect.material = _mat
	layer.add_child(rect)
	var rs := RenderingServer
	rs.global_shader_parameter_set("g_wind", 1.2)
	rs.global_shader_parameter_set("g_wind_gust", Vector4(1.0, 14.0, 3.8, 1.0))


func _process(_delta: float) -> void:
	var i := Engine.get_frames_drawn()
	var mode: int = MODES[i % MODES.size()]
	var t: float = TIMES[(i / MODES.size()) % TIMES.size()]
	var rs := RenderingServer
	rs.global_shader_parameter_set("g_time", t)
	var d := Vector2(0.94, 0.34).normalized().rotated(sin(t * 0.21) * 0.06 + sin(t * 0.053) * 0.05)
	rs.global_shader_parameter_set("g_wind_dir", d)
	_mat.set_shader_parameter("mode", mode)
	if i == 0:
		print("WINDPROBE frames: mode = i %% %d of %s, time = TIMES[i / %d] of %s" % [MODES.size(), str(MODES), MODES.size(), str(TIMES)])
