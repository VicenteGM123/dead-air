class_name Settings
## Player settings persisted in user://settings.cfg.

const PATH := "user://settings.cfg"

static var data := {
	"music": 0.7,
	"sfx": 0.85,
	"quality": 2, # 0 baja, 1 media, 2 alta
	"shake": true,
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
	return data[k]


static func set_v(k: String, v: Variant) -> void:
	ensure()
	data[k] = v
	save()


static func shadows() -> bool:
	if Game.arg("shadows", "") != "":
		return Game.arg("shadows") == "1"
	return int(get_v("quality")) >= 1


## Applies the quality level to the running viewport.
static func apply_quality(vp: Viewport) -> void:
	var q := int(get_v("quality"))
	vp.msaa_3d = Viewport.MSAA_2X if q >= 2 else Viewport.MSAA_DISABLED
	vp.scaling_3d_scale = 1.0 if q >= 1 else 0.75
	if Game.main and Game.main.tod:
		Game.main.tod.set_shadows(q >= 1)
