# Renders gfx cards (scripts/gfx/cards.gd) to PNG files with the real renderer (engine tooling, no JS counterpart).
# Needs a rendering device (not --headless): on Linux without a display use xvfb, e.g.
#   xvfb-run -a -s "-screen 0 1280x720x24" godot --path godot -s res://tools/canvas_cards_render.gd -- \
#       jobs=/abs/index.json out=/abs/dir [only=substring] [batch=6]
# jobs = JSON array of {name, id, opts, time, animated} (the $REF/cards/index.json of the JS reference dump);
# without jobs= every registered id is rendered with default opts at t = 0 as <id>.png.
# Also prints per-card CPU time (canvas command generation) for the performance notes.
extends SceneTree

var jobs: Array = []
var outDir := ""
var batch := 6
var i0 := 0
var pending: Array = []
var wait := 0
var t0 := 0

func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var k := a.find("=")
		if k > 0:
			args[a.substr(0, k)] = a.substr(k + 1)
	outDir = args.get("out", "user://cards")
	batch = int(args.get("batch", "6"))
	DirAccess.make_dir_recursive_absolute(outDir)
	if args.has("jobs"):
		jobs = JSON.parse_string(FileAccess.get_file_as_string(args.jobs))
	else:
		for id in DACards.cardIds():
			jobs.append({"name": id, "id": id, "opts": {}, "time": 0.0, "animated": false})
	if args.has("only"):
		jobs = jobs.filter(func(j): return String(j.name).contains(args.only))
	print("[cards] %d jobs -> %s" % [jobs.size(), outDir])
	t0 = Time.get_ticks_msec()
	RenderingServer.frame_post_draw.connect(_post)

func _post() -> void:
	if wait > 0:
		wait -= 1
		return
	for p in pending:
		var cv: DACanvas = p[1]
		var img := cv.toImage()
		img.save_png(outDir.path_join(p[0] + ".png"))
	pending = []
	if i0 >= jobs.size():
		if t0 < 0:
			return
		print("[cards] done in %d ms, stats %s" % [Time.get_ticks_msec() - t0, DACanvasGPU.stats])
		t0 = -1
		quit()
		return
	var n := 0
	while i0 < jobs.size() and n < batch:
		var j: Dictionary = jobs[i0]
		i0 += 1
		n += 1
		var info = DACards.cardInfo(j.id)
		if info == null:
			continue
		var cv := DACanvas.new(info.w, info.h)
		cv.opaque = not info.alpha
		cv.bakeMode = "never"
		var ctx = cv.getContext("2d")
		var opts: Dictionary = j.get("opts", {})
		var def = DACards.need(j.id)
		var t: float = float(j.get("time", 0.0))
		var us := Time.get_ticks_usec()
		DACards.render(def, ctx, DACards.quantize(def, t), opts)
		var ms := (Time.get_ticks_usec() - us) / 1000.0
		print("[cards] %-44s %7.1f ms" % [j.name, ms])
		pending.append([j.name, cv])
	wait = 1
