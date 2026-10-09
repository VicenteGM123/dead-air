class_name Settings
## Player settings persisted in user://settings.cfg (on the web: the browser's IndexedDB, through Godot).
##   music, sfx       0..1 bus volumes
##   quality          0 low, 1 medium (web default), 2 high
##   shake            camera shake on hits
##   mouse_sens       mouse look multiplier (1 = default speed)
##   pad_sens         right-stick look multiplier
##   invert_y         invert vertical look (mouse and stick)
##   invert_x         invert horizontal look

const PATH := "user://settings.cfg"

static var data := {
	"music": 0.7,
	"sfx": 0.85,
	"quality": 2,
	"shake": true,
	"mouse_sens": 1.0,
	"pad_sens": 1.0,
	"invert_y": false,
	"invert_x": false,
}
static var _loaded := false


static func ensure() -> void:
	if _loaded:
		return
	_loaded = true
	if OS.has_feature("web"):
		data["quality"] = 1
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		for k in data:
			data[k] = cf.get_value("settings", k, data[k])


static func save() -> void:
	var cf := ConfigFile.new()
	for k in data:
		cf.set_value("settings", k, data[k])
	cf.save(PATH)


static func get_v(k: String) -> Variant:
	ensure()
	return data.get(k)


static func set_v(k: String, v: Variant) -> void:
	ensure()
	data[k] = v
	save()


## Sun shadows on? (quality >= 1; debug: shadows=0 / shadows=1)
static func shadows() -> bool:
	if Game.arg("shadows", "") != "":
		return Game.arg("shadows") == "1"
	return int(get_v("quality")) >= 1


## Applies the quality level to the running viewport (and the sun's shadows when a TimeOfDay is live).
static func apply_quality(vp: Viewport) -> void:
	var q := int(get_v("quality"))
	vp.msaa_3d = Viewport.MSAA_2X if q >= 2 else Viewport.MSAA_DISABLED
	vp.scaling_3d_scale = 1.0 if q >= 1 else 0.75
	if Game.has_arg("scale3d"): # debug: cheaper 3D for software-rendered tests
		vp.scaling_3d_scale = clampf(Game.arg_f("scale3d", 1.0), 0.1, 1.0)
	if Game.tod and is_instance_valid(Game.tod) and Game.tod.has_method("set_shadows"):
		Game.tod.call("set_shadows", shadows())
