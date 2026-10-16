extends Node
## Test of the shaders' clock (TimeOfDay._advance_clock, g_time): uneven frames must advance the wind in even steps,
## the clock must stay within 0.3 s of the raw one, a hit-stop must freeze it, slow motion must slow it, and at a steady
## frame rate it must BE the raw clock. Headless is fine:
##   godot --headless --path . res://tools/wind_clock_test.tscn --quit-after 3 | grep CLOCK
## Prints "CLOCK <test> ... PASS|FAIL", "CLOCK seq ..." (the clock values of the alternating sequence, compared with the
## Python port in analysis/pacing.py by analysis/clock_compare.py) and "CLOCK result=PASS|FAIL".

var _fails := 0


func _ready() -> void:
	var seq_alt := PackedFloat64Array()
	for i in 1200:
		seq_alt.append(1.0 / 60.0 if i % 2 == 0 else 2.0 / 60.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var seq_jit := PackedFloat64Array()
	for i in 1200:
		seq_jit.append(0.020 + rng.randf_range(-0.008, 0.008))
	var seq_hitch := PackedFloat64Array()
	for i in 600:
		seq_hitch.append(0.1 if i == 300 else 1.0 / 60.0)
	var seq_stall := PackedFloat64Array()
	for i in 600:
		seq_stall.append(3.0 if i == 300 else 1.0 / 60.0)
	var seq_steady := PackedFloat64Array()
	seq_steady.resize(600)
	seq_steady.fill(1.0 / 60.0)
	var seq_30 := PackedFloat64Array()
	seq_30.resize(300)
	seq_30.fill(1.0 / 30.0)

	# 1. steady frame rates: the clock IS the raw clock
	var r := _run(seq_steady, 1.0)
	_check("steady 60 fps: clock == raw", absf(r["end_err"]) < 1e-9 and r["max_err"] < 1e-9, "max |clock - raw| = %.12f s" % r["max_err"])
	r = _run(seq_30, 1.0)
	_check("fixed 30 fps (renders): clock == raw", r["max_err"] < 1e-9, "max |clock - raw| = %.12f s" % r["max_err"])
	# 2. the vsync beat: even steps, bounded drift
	r = _run(seq_alt, 1.0)
	_check("16.7/33.3 ms beat: steps are even", r["step_std"] < 0.1 * r["delta_std"], "std of the steps %.2f ms vs of the deltas %.2f ms" % [r["step_std"] * 1000.0, r["delta_std"] * 1000.0])
	_check("16.7/33.3 ms beat: drift <= 0.3 s", r["max_err"] <= 0.3 + 1e-9, "max |clock - raw| = %.3f s" % r["max_err"])
	var line := PackedStringArray()
	for i in 60:
		line.append("%.6f" % float(r["clock"][i]))
	print("CLOCK seq alt ", " ".join(line))
	# 3. jitter
	r = _run(seq_jit, 1.0)
	_check("20 ms +- 8 ms jitter: steps are even", r["step_std"] < 0.25 * r["delta_std"], "std of the steps %.2f ms vs of the deltas %.2f ms" % [r["step_std"] * 1000.0, r["delta_std"] * 1000.0])
	_check("20 ms +- 8 ms jitter: drift <= 0.3 s", r["max_err"] <= 0.3 + 1e-9, "max |clock - raw| = %.3f s" % r["max_err"])
	# 4. one 100 ms hitch: no jump, caught up within 1.5 s
	r = _run(seq_hitch, 1.0)
	var clock: PackedFloat64Array = r["clock"]
	var step_at: float = clock[300] - clock[299]
	var back: float = absf(float(r["raw"][390]) - clock[390])
	_check("100 ms hitch: the clock steps %.1f ms (not 100)" % [step_at * 1000.0], step_at < 0.03, "step %.1f ms" % [step_at * 1000.0])
	_check("100 ms hitch: back in step within 1.5 s", back < 0.02, "|clock - raw| after 1.5 s = %.1f ms" % [back * 1000.0])
	# 5. a 3 s stall (hidden tab, a long load): never more than 0.3 s from the raw clock
	r = _run(seq_stall, 1.0)
	_check("3 s stall: drift <= 0.3 s, finite", r["max_err"] <= 0.3 + 1e-9 and is_finite(float(r["clock"][599])), "max |clock - raw| = %.3f s" % r["max_err"])
	# 6. hit-stop (time scale 0.02): the clock freezes with the world, and nothing is left over afterwards
	var hs := PackedFloat64Array()
	for i in 200:
		hs.append(1.0 / 60.0)
	var scales := PackedFloat64Array()
	for i in 200:
		scales.append(0.02 if (i >= 100 and i < 106) else 1.0)
	r = _run(hs, 1.0, scales)
	var frozen: float = r["clock"][105] - r["clock"][99]
	_check("hit-stop: 6 frames advance %.2f ms (0.02 x 100 ms = 2 ms)" % [frozen * 1000.0], absf(frozen - 6.0 / 60.0 * 0.02) < 0.0005, "advance %.3f ms" % [frozen * 1000.0])
	_check("hit-stop: back to the raw clock", r["max_err"] < 0.01, "max |clock - raw| = %.2f ms" % [r["max_err"] * 1000.0])
	# 7. slow motion (time scale 0.4)
	var sm := PackedFloat64Array()
	var sm_scales := PackedFloat64Array()
	for i in 240:
		sm.append(1.0 / 60.0)
		sm_scales.append(0.4)
	r = _run(sm, 1.0, sm_scales)
	_check("slow motion x0.4: 4 s of frames advance 1.6 s", absf(float(r["clock"][239]) - 240.0 / 60.0 * 0.4) < 0.01, "clock %.3f s" % float(r["clock"][239]))
	print("CLOCK result=%s (%d failed)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit()


## Feeds the frame deltas (the delta the engine passes: already multiplied by the frame's time scale) to a fresh TimeOfDay
## and collects its clock. `scales` (optional) is the time scale of each frame.
func _run(deltas: PackedFloat64Array, _unused: float, scales := PackedFloat64Array()) -> Dictionary:
	var tod := TimeOfDay.new()
	var clock := PackedFloat64Array()
	var raw := PackedFloat64Array()
	var acc := 0.0
	var max_err := 0.0
	var steps := PackedFloat64Array()
	var prev := 0.0
	for i in deltas.size():
		var sc := 1.0 if scales.is_empty() else scales[i]
		Game.frame_scale = sc
		var d := deltas[i] * sc
		tod.call("_advance_clock", d)
		acc += d
		var t: float = tod.get("_time")
		clock.append(t)
		raw.append(acc)
		max_err = maxf(max_err, absf(t - acc))
		steps.append(t - prev)
		prev = t
	Game.frame_scale = 1.0
	tod.free()
	var n := deltas.size()
	var mean_d := 0.0
	var mean_s := 0.0
	for i in n:
		mean_d += deltas[i]
		mean_s += steps[i]
	mean_d /= n
	mean_s /= n
	var vd := 0.0
	var vs := 0.0
	for i in range(60, n):   # (skip the first second: the average is still settling)
		vd += (deltas[i] - mean_d) * (deltas[i] - mean_d)
		vs += (steps[i] - mean_s) * (steps[i] - mean_s)
	var m := maxi(n - 60, 1)
	return {"clock": clock, "raw": raw, "max_err": max_err, "end_err": acc - prev, "delta_std": sqrt(vd / m), "step_std": sqrt(vs / m)}


func _check(name: String, ok: bool, detail: String) -> void:
	if not ok:
		_fails += 1
	print("CLOCK %s: %s (%s)" % [name, "PASS" if ok else "FAIL", detail])
