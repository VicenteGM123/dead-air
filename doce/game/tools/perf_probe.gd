extends SceneTree
## CORE perf probe (headless): the CPU cost per frame of the systems that run every frame in a fight, measured
## in isolation with a fixed step (no rendering):
##   godot --headless --path . -s res://tools/perf_probe.gd
## Prints "PERF <system> <us> us/frame". Budget reference: a 60 fps frame is 16 667 us for everything (scripts,
## physics, rendering); the web build runs GDScript roughly 2-3x slower than these desktop numbers.

const N := 600


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var rig := RigHeracles.new()
	root.add_child(rig)
	rig.process_mode = Node.PROCESS_MODE_DISABLED
	for i in 60:
		rig.advance(1.0 / 60.0)
	# the rig: idle, running, a combo of blows, the charged spin, a roll
	for mode in ["idle", "run", "combo", "heavy", "dodge"]:
		rig.set_locomotion(5.5 if mode == "run" else 0.0, 6.2)
		var seq: Array = ["attack1", "attack2", "attack3"] if mode == "combo" else ([mode] if mode in ["heavy", "dodge"] else [])
		var k := 0
		if not seq.is_empty():
			rig.play(seq[0])
		var t0 := Time.get_ticks_usec()
		for i in N:
			rig.advance(1.0 / 60.0)
			if not seq.is_empty() and rig.action == "":
				k = (k + 1) % seq.size()
				rig.play(seq[k])
		print("PERF rig_%s %.0f us/frame" % [mode, float(Time.get_ticks_usec() - t0) / N])
	# the blade segment the melee sweep reads each frame
	var t1 := Time.get_ticks_usec()
	for i in N:
		rig.blade_segment()
	print("PERF blade_segment %.1f us/call" % [float(Time.get_ticks_usec() - t1) / N])
	rig.queue_free()
	# Fx: a busy fight's worth of particles (impacts, dust, sparks) stepped every frame
	var fx := Fx.new()
	root.add_child(fx)
	fx.process_mode = Node.PROCESS_MODE_DISABLED
	await process_frame
	var cb := Basis.IDENTITY
	for i in 12:
		fx.impact(Vector3(randf(), 1.0, randf()), Vector3.FORWARD, 1.2)
		fx.dust(Vector3.ZERO, 6, 0.6)
		fx.hit_spark(Vector3(0, 1, 0), Vector3.FORWARD, 1.0)
	var live := 0
	for p in fx._pools.values():
		live += (p as Fx.Pool).n
	var t2 := Time.get_ticks_usec()
	for i in N:
		for p in fx._pools.values():
			(p as Fx.Pool).step(1.0 / 6000.0, cb) # tiny step: the particles stay alive the whole probe
	print("PERF fx_step %.0f us/frame (%d live particles)" % [float(Time.get_ticks_usec() - t2) / N, live])
	fx.queue_free()
	print("PERF done")
	quit()
