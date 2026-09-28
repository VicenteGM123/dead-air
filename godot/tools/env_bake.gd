# Converts the RoomEnvironment PMREM atlas baked by tools/jsref (three.js PMREMGenerator.fromScene(new
# RoomEnvironment(), 0.04): 768x1024 RGBA half floats, GL row order) into res://shaders/data/room_env.res
# (ImageTexture, RGBAH, no mipmaps) = materials.gd envMap / the daEnvMap global sampler.
#   node tools/jsref/build.mjs <dir> && node tools/jsref/run.mjs <dir> env <dir>/room_env.bin
#   godot --headless --path . -s res://tools/env_bake.gd -- in=<dir>/room_env.bin
extends SceneTree

func _init() -> void:
	var src := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("in="):
			src = a.substr(3)
	var f := FileAccess.open(src, FileAccess.READ)
	if f == null:
		push_error("env_bake: cannot read '%s'" % src)
		quit(1)
		return
	var bytes := f.get_buffer(f.get_length())
	var img := Image.create_from_data(768, 1024, false, Image.FORMAT_RGBAH, bytes)
	var tex := ImageTexture.create_from_image(img)
	var err := ResourceSaver.save(tex, "res://shaders/data/room_env.res", ResourceSaver.FLAG_COMPRESS)
	print("env_bake: ", "ok" if err == OK else "error %d" % err)
	quit(0)
