extends "res://scripts/main.gd"
## Wind check: a STATIC camera over the meadow or the wheat (the hero parked far away, no beasts, no fauna), so that a
## --write-movie sequence shows only what the wind does to the grass. Used by analysis/video_signal.py (temporal
## signal of the grass regions: frame differences, energy above 2 Hz) and for the before / after render pairs.
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1280x720 --write-movie <dir>/f.png --fixed-fps 30 \
##     --quit-after 600 res://tools/wind_view.tscn -- shot=meadow|wheat|meadow_far|ridge quality=1 shadows=0 nopost=1 \
##     noedges=1 scale3d=0.5 t0=60 tod=golden
## (the movie is always 1280x720, the project's base size: scale3d=0.5 renders the 3D at 640x360 and is the cheap way.)
## Defaults: enemies=0 fauna=0 lion=0 noui=1 cam=fly, quality=1 (the web default; not saved).
## Extra args: pos=x,y,z yaw=deg pitch=deg (override the preset), fov=deg, t0=<seconds> (the shader clock starts here),
## speed=k (Game.time_scale); experiments that split what the video shows: windk=<k> (g_wind: 0 = nothing leans or sways),
## tint=<k> (k x the wave tint and sheen of the grass and the ground: 0 = none, what is left is the blades' motion).
## Presets: [camera xz, height above ground, yaw (0 = north, 90 = west), pitch, fov]
const VIEWS := {
	"meadow": [Vector2(48.0, 53.0), 1.7, -47.0, -9.0, 60.0],
	"meadow_low": [Vector2(48.0, 53.0), 0.7, -47.0, -4.0, 60.0],
	"meadow_far": [Vector2(-14.0, 58.0), 3.0, -139.0, -12.0, 60.0],
	"wheat": [Vector2(-58.5, 17.6), 2.0, 95.0, -10.0, 60.0],
	"ridge": [Vector2(-40.0, -79.0), 2.2, -80.0, -10.0, 60.0],
}


func _wants_title() -> bool:
	return false


func _ready() -> void:
	if not Game.has_arg("noui"):
		Game.args["noui"] = "1"
	if not Game.has_arg("enemies"):
		Game.args["enemies"] = "0"
	if not Game.has_arg("lion"):
		Game.args["lion"] = "0"
	if not Game.has_arg("fauna"):
		Game.args["fauna"] = "0"
	if not Game.has_arg("cam"):
		Game.args["cam"] = "fly"
	# the web default quality (1) unless quality=<n> says otherwise (not saved)
	Settings.ensure()
	Settings.data["quality"] = clampi(int(Game.arg("quality", "1")), 0, 2)
	super._ready()
	var v: Array = VIEWS.get(String(Game.arg("shot", "meadow")), VIEWS["meadow"])
	var xz: Vector2 = v[0]
	var g: Vector3 = world.ground(Vector3(xz.x, 0.0, xz.y))
	var pos := Vector3(xz.x, g.y + float(v[1]), xz.y)
	var yaw := float(v[2])
	var pitch := float(v[3])
	if Game.has_arg("pos"):
		pos = Game.arg_vec3("pos")
	if Game.has_arg("yaw"):
		yaw = Game.arg_f("yaw", yaw)
	if Game.has_arg("pitch"):
		pitch = Game.arg_f("pitch", pitch)
	cam.set_fly(pos, yaw, pitch)
	cam.cam.fov = Game.arg_f("fov", float(v[4]))
	# the hero stands far from the shot (on the pier): its rig, its pusher and its idle motion are out of the picture
	hero.teleport(Transform3D(Basis(Vector3.UP, 0.0), world.ground(Vector3(14, 0, 130))))
	hero.input_enabled = false
	if Game.has_arg("windk"):
		RenderingServer.global_shader_parameter_set("g_wind", Game.arg_f("windk", 1.0))
	if Game.has_arg("tint"):
		var tk := Game.arg_f("tint", 1.0)
		var mats: Array = []
		if world.get("grass") != null:
			mats.append_array(world.grass.get("_mats"))
		mats.append(Materials.terrain())
		for m in mats:
			if m is ShaderMaterial:
				var sm := m as ShaderMaterial
				sm.set_shader_parameter("wave_tint", 0.3 * tk)
				sm.set_shader_parameter("crest_k", 0.3 * tk)
	if Game.has_arg("t0") and Game.tod != null:
		if Game.tod.has_method("set_shader_time"):
			Game.tod.call("set_shader_time", Game.arg_f("t0", 0.0))
		else:
			Game.tod.set("_time", Game.arg_f("t0", 0.0))   # the pristine TimeOfDay (before / after pairs)
