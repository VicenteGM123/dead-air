class_name TimeOfDay
extends Node
## Owns the WorldEnvironment and the single directional light (sun by day, moon by night) and drives every
## global shader parameter from a small table of lighting moods. Transitions blend between moods.

signal transition_finished(state: String)

const STATES := {
	"day": {
		"elev": 54.0, "azim": -58.0, "moon": false,
		"light": Color("FFF0DA"), "energy": 1.05,
		"amb_sky": Color("8FA9CF"), "amb_sky_k": 0.92, "amb_ground": Color("B39A74"), "amb_ground_k": 0.62,
		"fog": Color("CFE4EC"), "fog_near": 75.0, "fog_far": 230.0,
		"sky_top": Color("5D9BD8"), "sky_horizon": Color("D3EAF2"),
		"shallow": Color("4CD3CB"), "deep": Color("1A5C8C"), "foam": Color("F6FBFA"),
		"night": 0.0, "wind": 1.0,
	},
	"golden": {
		"elev": 17.0, "azim": -78.0, "moon": false,
		"light": Color("FFC38E"), "energy": 1.05,
		"amb_sky": Color("9C95C4"), "amb_sky_k": 0.78, "amb_ground": Color("B07A5C"), "amb_ground_k": 0.5,
		"fog": Color("F2CDAE"), "fog_near": 70.0, "fog_far": 220.0,
		"sky_top": Color("6F84C6"), "sky_horizon": Color("F8CDA0"),
		"shallow": Color("5AC6C0"), "deep": Color("22537F"), "foam": Color("FFF2E4"),
		"night": 0.0, "wind": 1.2,
	},
	"dusk": {
		"elev": 3.0, "azim": -86.0, "moon": false,
		"light": Color("FF9070"), "energy": 0.6,
		"amb_sky": Color("7B70BC"), "amb_sky_k": 0.74, "amb_ground": Color("4E416E"), "amb_ground_k": 0.45,
		"fog": Color("C394B4"), "fog_near": 60.0, "fog_far": 200.0,
		"sky_top": Color("3D4592"), "sky_horizon": Color("F0A68E"),
		"shallow": Color("3F93AA"), "deep": Color("1B3264"), "foam": Color("F4DDE4"),
		"night": 0.55, "wind": 1.3,
	},
	"night": {
		"elev": 46.0, "azim": 28.0, "moon": true,
		"light": Color("9FB4FF"), "energy": 0.56,
		"amb_sky": Color("4A5BB0"), "amb_sky_k": 0.56, "amb_ground": Color("2A2650"), "amb_ground_k": 0.45,
		"fog": Color("1E2650"), "fog_near": 55.0, "fog_far": 185.0,
		"sky_top": Color("0B1030"), "sky_horizon": Color("2A3466"),
		"shallow": Color("1E6E8A"), "deep": Color("0B1C40"), "foam": Color("9FD3EE"),
		"night": 1.0, "wind": 1.4,
	},
	"dawn": {
		"elev": 9.0, "azim": 72.0, "moon": false,
		"light": Color("FFBFA2"), "energy": 0.75,
		"amb_sky": Color("9BA6D6"), "amb_sky_k": 0.74, "amb_ground": Color("8F6E74"), "amb_ground_k": 0.5,
		"fog": Color("F2CBC6"), "fog_near": 65.0, "fog_far": 210.0,
		"sky_top": Color("7A90D2"), "sky_horizon": Color("FAD6BE"),
		"shallow": Color("58C8C8"), "deep": Color("1F5083"), "foam": Color("FFF4F0"),
		"night": 0.25, "wind": 0.8,
	},
}

var env: Environment
var world_env: WorldEnvironment
var sun: DirectionalLight3D
var state := "day"
var shadows := true

var _cur: Dictionary = {}
var _from: Dictionary = {}
var _to: Dictionary = {}
var _t := 1.0
var _dur := 0.0
var _queue: Array = []
var _time := 0.0


func _ready() -> void:
	world_env = WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.BLACK
	env.ambient_light_energy = 0.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = false
	world_env.environment = env
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.shadow_bias = float(Game.arg("sbias", "0.08"))
	sun.shadow_normal_bias = float(Game.arg("snbias", "3.0"))
	sun.shadow_blur = float(Game.arg("sblur", "1.5"))
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 95.0
	sun.directional_shadow_split_1 = 0.3
	sun.directional_shadow_fade_start = 0.85
	sun.light_specular = 0.0
	add_child(sun)
	set_state("day")


func set_shadows(on: bool) -> void:
	shadows = on
	sun.shadow_enabled = on
	RenderingServer.global_shader_parameter_set("g_sun_comp", 1.0 if on else 0.0)


func set_state(s: String) -> void:
	state = s
	_cur = STATES[s].duplicate()
	_t = 1.0
	_queue.clear()
	_apply(_cur)


## Blend to a mood over `dur` seconds. Several calls queue up (day -> golden -> dusk -> night).
func transition_to(s: String, dur: float) -> void:
	_queue.append([s, dur])
	if _t >= 1.0:
		_next()


func is_transitioning() -> bool:
	return _t < 1.0 or not _queue.is_empty()


func _next() -> void:
	if _queue.is_empty():
		return
	var item: Array = _queue.pop_front()
	_from = _cur.duplicate()
	_to = STATES[item[0]].duplicate()
	_to["name"] = item[0]
	_dur = maxf(0.01, item[1])
	_t = 0.0


func _process(delta: float) -> void:
	_time += delta
	RenderingServer.global_shader_parameter_set("g_time", _time)
	if _t < 1.0:
		_t = minf(1.0, _t + delta / _dur)
		var k := _t * _t * (3.0 - 2.0 * _t)
		_cur = _blend(_from, _to, k)
		_apply(_cur)
		if _t >= 1.0:
			state = _to["name"]
			transition_finished.emit(state)
			_next()


func _blend(a: Dictionary, b: Dictionary, k: float) -> Dictionary:
	var r := {}
	for key in a:
		var va = a[key]
		var vb = b.get(key, va)
		if va is Color:
			r[key] = (va as Color).lerp(vb, k)
		elif va is float:
			r[key] = lerpf(va, vb, k)
		else:
			r[key] = vb if k >= 0.5 else va
	# Sun <-> moon swap: the light dims to nothing and the direction jumps while it is dark.
	if a["moon"] != b["moon"]:
		var dip := absf(k - 0.5) * 2.0
		r["energy"] = lerpf(a["energy"], b["energy"], k) * dip * dip
		var src: Dictionary = a if k < 0.5 else b
		r["elev"] = src["elev"]
		r["azim"] = src["azim"]
		r["moon"] = src["moon"]
	return r


static func dir_from(elev_deg: float, azim_deg: float) -> Vector3:
	var e := deg_to_rad(elev_deg)
	var a := deg_to_rad(azim_deg)
	return Vector3(cos(e) * sin(a), sin(e), cos(e) * cos(a)).normalized()


func _apply(s: Dictionary) -> void:
	var to_sun := dir_from(s["elev"], s["azim"])
	sun.look_at_from_position(Vector3.ZERO, -to_sun, Vector3.UP if absf(to_sun.y) < 0.99 else Vector3.FORWARD)
	sun.light_color = s["light"]
	sun.light_energy = s["energy"]
	var night: float = s["night"]
	var gs := RenderingServer
	gs.global_shader_parameter_set("g_amb_sky", Pal.lin(s["amb_sky"]) * float(s["amb_sky_k"]))
	gs.global_shader_parameter_set("g_amb_ground", Pal.lin(s["amb_ground"]) * float(s["amb_ground_k"]))
	gs.global_shader_parameter_set("g_fog_color", Pal.lin(s["fog"]))
	gs.global_shader_parameter_set("g_fog_near", s["fog_near"])
	gs.global_shader_parameter_set("g_fog_far", s["fog_far"])
	gs.global_shader_parameter_set("g_sky_top", Pal.lin(s["sky_top"]))
	gs.global_shader_parameter_set("g_sky_horizon", Pal.lin(s["sky_horizon"]))
	gs.global_shader_parameter_set("g_water_shallow", Pal.lin(s["shallow"]))
	gs.global_shader_parameter_set("g_water_deep", Pal.lin(s["deep"]))
	gs.global_shader_parameter_set("g_foam", Pal.lin(s["foam"]))
	gs.global_shader_parameter_set("g_night", night)
	gs.global_shader_parameter_set("g_wind", s["wind"])
	var sun_vis := dir_from(s["elev"], s["azim"]) if not s["moon"] else dir_from(-10.0, -80.0)
	gs.global_shader_parameter_set("g_sun_dir", sun_vis)
	gs.global_shader_parameter_set("g_sun_color", Pal.lin(s["light"]))
	gs.global_shader_parameter_set("g_moon_dir", dir_from(38.0, 160.0))


func night_amount() -> float:
	return float(_cur.get("night", 0.0))
