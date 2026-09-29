# Exports every gfx card (scripts/gfx/cards.gd) at its native size, default opts, t = 0, to
# <repo>/blender/dalib/cards/<id>.png for the Blender pipeline (prop/room textures that use cards.getCard /
# cards.drawTo). Engine tooling (no JS counterpart).
# The Canvas 2D emulation renders on the GPU, so this needs a real rendering device (NOT --headless):
#   godot --path godot -s res://tools/export_cards.gd                       (desktop)
#   xvfb-run -a -s "-screen 0 1280x720x24" godot --path godot -s res://tools/export_cards.gd   (Linux, no display)
# Options after `--`: out=/abs/dir  only=<substring>
# PNGs are straight-alpha RGBA (transparent cards keep their alpha; opaque ones are fully opaque).
extends SceneTree

var ids: Array = []
var outDir := ""
var i0 := 0
var pending: Array = []
var wait := 0
var done := false

func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var k := a.find("=")
		if k > 0:
			args[a.substr(0, k)] = a.substr(k + 1)
	outDir = args.get("out", ProjectSettings.globalize_path("res://").path_join("../blender/dalib/cards").simplify_path())
	if DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() == "dummy":
		push_error("[export_cards] needs a rendering device: run without --headless (use xvfb-run on a display-less Linux box)")
		quit(1)
		done = true
		return
	DirAccess.make_dir_recursive_absolute(outDir)
	ids = DACards.cardIds()
	if args.has("only"):
		ids = ids.filter(func(id): return String(id).contains(args.only))
	print("[export_cards] %d cards -> %s" % [ids.size(), outDir])
	RenderingServer.frame_post_draw.connect(_post)

func _post() -> void:
	if done:
		return
	if wait > 0:
		wait -= 1
		return
	for p in pending:
		var img: Image = (p[1] as DACanvas).toImage()
		var err := img.save_png(outDir.path_join(p[0] + ".png"))
		if err != OK:
			push_error("[export_cards] cannot write %s (%d)" % [p[0], err])
	pending = []
	if i0 >= ids.size():
		done = true
		print("[export_cards] done")
		quit()
		return
	var n := 0
	while i0 < ids.size() and n < 6:
		var id: String = ids[i0]
		i0 += 1
		n += 1
		var info = DACards.cardInfo(id)
		var cv := DACanvas.new(info.w, info.h)
		cv.opaque = not info.alpha
		cv.bakeMode = "never"
		var def = DACards.need(id)
		DACards.render(def, cv.getContext("2d"), 0.0, {})
		pending.append([id, cv])
	wait = 1
