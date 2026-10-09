class_name TimeOfDay
extends Node
## Owns the WorldEnvironment and the single directional light (sun by day, moon by night) and drives every
## global shader parameter from a small table of lighting moods. Transitions blend between moods.
## DOCE plays in the "golden" late afternoon by default (main.gd: tod=<mood> overrides it); ToonScreen reads the
## per-mood post settings (rim, line, bloom, leak, sat) from current().

signal transition_finished(state: String)

## TOON style test moods: saturated anime light, coloured shadows (lavender by day, violet at golden hour, deep
## blue at night), graphic clouds and per-mood post settings (rim light, outline tint, bloom).
const STATES := {
	"day": {
		"elev": 47.0, "azim": -58.0, "moon": false,
		"light": Color("FFF2DA"), "energy": 1.12,
		"amb_sky": Color("7FA4EE"), "amb_sky_k": 0.84, "amb_ground": Color("B49A92"), "amb_ground_k": 0.6,
		"shade": Color(1, 1, 1),
		"fog": Color("BFE4F6"), "fog_near": 85.0, "fog_far": 260.0,
		"sky_top": Color("2C7CE6"), "sky_horizon": Color("C4ECFA"),
		"shallow": Color("37E2D2"), "deep": Color("1452B4"), "foam": Color("FFFFFF"),
		"cloud_lit": Color("FFFFFF"), "cloud_shade": Color("A8B9EC"), "cloud_cover": 0.6, "cloud_shadow": 0.5,
		"rim": Color("FFF4DC"), "rim_k": 0.5, "line": Color("2B2547"), "bloom": 0.3, "sat": 1.06, "leak": 0.22,
		"night": 0.0, "wind": 1.0,
	},
	"golden": {
		"elev": 17.0, "azim": -78.0, "moon": false,
		"light": Color("FFB46A"), "energy": 1.25,
		"amb_sky": Color("7E70D8"), "amb_sky_k": 0.74, "amb_ground": Color("B87A72"), "amb_ground_k": 0.5,
		"shade": Color(1, 1, 1),
		"fog": Color("FBD3A4"), "fog_near": 130.0, "fog_far": 470.0,
		"sky_top": Color("4A6CCC"), "sky_horizon": Color("FFC88E"),
		"shallow": Color("38D4C8"), "deep": Color("1A55B4"), "foam": Color("FFF6EA"),
		"cloud_lit": Color("FFE9C8"), "cloud_shade": Color("C9A0CC"), "cloud_cover": 0.6, "cloud_shadow": 0.0,
		"rim": Color("FFDCA6"), "rim_k": 0.85, "line": Color("3B1F3D"), "bloom": 0.3, "sat": 1.06, "leak": 0.32,
		"night": 0.0, "wind": 1.2,
	},
	"dusk": {
		"elev": 3.0, "azim": -86.0, "moon": false,
		"light": Color("FF8C6E"), "energy": 0.62,
		"amb_sky": Color("7468C6"), "amb_sky_k": 0.72, "amb_ground": Color("4E3F78"), "amb_ground_k": 0.45,
		"shade": Color(1, 1, 1),
		"fog": Color("B48ABE"), "fog_near": 60.0, "fog_far": 200.0,
		"sky_top": Color("33389A"), "sky_horizon": Color("F49C86"),
		"shallow": Color("2F96B4"), "deep": Color("16306C"), "foam": Color("F6DCEA"),
		"cloud_lit": Color("FFB3A0"), "cloud_shade": Color("6E5AA6"), "cloud_cover": 0.6, "cloud_shadow": 0.0,
		"rim": Color("FFB08C"), "rim_k": 0.7, "line": Color("231638"), "bloom": 0.55, "sat": 1.05, "leak": 0.25,
		"night": 0.55, "wind": 1.3,
	},
	"night": {
		"elev": 46.0, "azim": 28.0, "moon": true,
		"light": Color("A2C4FF"), "energy": 0.6,
		"amb_sky": Color("2B40B6"), "amb_sky_k": 0.4, "amb_ground": Color("221D5A"), "amb_ground_k": 0.4,
		"shade": Color(1, 1, 1),
		"fog": Color("0E1744"), "fog_near": 55.0, "fog_far": 190.0,
		"sky_top": Color("050A28"), "sky_horizon": Color("1A2A6A"),
		"shallow": Color("1786AC"), "deep": Color("091A4E"), "foam": Color("A6E8FF"),
		"cloud_lit": Color("6D84C8"), "cloud_shade": Color("28356F"), "cloud_cover": 0.5, "cloud_shadow": 0.0,
		"rim": Color("8ADFFF"), "rim_k": 0.75, "line": Color("060718"), "bloom": 1.1, "sat": 1.1, "leak": 0.1,
		"night": 1.0, "wind": 1.4,
	},
	"dawn": {
		"elev": 9.0, "azim": 72.0, "moon": false,
		"light": Color("FFBC9E"), "energy": 0.8,
		"amb_sky": Color("98A2E2"), "amb_sky_k": 0.74, "amb_ground": Color("93707C"), "amb_ground_k": 0.5,
		"shade": Color(1, 1, 1),
		"fog": Color("F4C8CC"), "fog_near": 65.0, "fog_far": 220.0,
		"sky_top": Color("6A86DA"), "sky_horizon": Color("FCD2BE"),
		"shallow": Color("4ED2CC"), "deep": Color("1C4E96"), "foam": Color("FFF4F2"),
		"cloud_lit": Color("FFE0D6"), "cloud_shade": Color("A992CF"), "cloud_cover": 0.6, "cloud_shadow": 0.0,
		"rim": Color("FFD0BC"), "rim_k": 0.7, "line": Color("2D2042"), "bloom": 0.4, "sat": 1.05, "leak": 0.25,
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
	var mood := String(Game.arg("tod", "golden"))
	set_state(mood if STATES.has(mood) else "golden")


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
	# Debug fogmul=<k> pushes the haze out for overview renders.
	var fm := Game.arg_f("fogmul", 1.0)
	gs.global_shader_parameter_set("g_fog_near", float(s["fog_near"]) * fm)
	gs.global_shader_parameter_set("g_fog_far", float(s["fog_far"]) * fm)
	gs.global_shader_parameter_set("g_sky_top", Pal.lin(s["sky_top"]))
	gs.global_shader_parameter_set("g_sky_horizon", Pal.lin(s["sky_horizon"]))
	gs.global_shader_parameter_set("g_water_shallow", Pal.lin(s["shallow"]))
	gs.global_shader_parameter_set("g_water_deep", Pal.lin(s["deep"]))
	gs.global_shader_parameter_set("g_foam", Pal.lin(s["foam"]))
	gs.global_shader_parameter_set("g_night", night)
	gs.global_shader_parameter_set("g_toon_shade", Pal.lin(s["shade"]))
	gs.global_shader_parameter_set("g_cloud_shadow", s["cloud_shadow"])
	gs.global_shader_parameter_set("g_cloud_lit", Pal.lin(s["cloud_lit"]))
	gs.global_shader_parameter_set("g_cloud_shade", Pal.lin(s["cloud_shade"]))
	gs.global_shader_parameter_set("g_cloud_cover", s["cloud_cover"])
	gs.global_shader_parameter_set("g_wind", s["wind"])
	var sun_vis := dir_from(s["elev"], s["azim"]) if not s["moon"] else dir_from(-10.0, -80.0)
	gs.global_shader_parameter_set("g_sun_dir", sun_vis)
	gs.global_shader_parameter_set("g_sun_color", Pal.lin(s["light"]))
	gs.global_shader_parameter_set("g_moon_dir", dir_from(38.0, 160.0))


## Current blended mood (the toon style reads its post settings from it).
func current() -> Dictionary:
	return _cur


func night_amount() -> float:
	return float(_cur.get("night", 0.0))
