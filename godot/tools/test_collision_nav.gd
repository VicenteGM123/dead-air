# Cross-check of scripts/world/collision.gd + nav.gd against the original JS (src/world/collision.js, nav.js).
# The JS side (a Node harness) replays the station colliders of the running JS game into the original modules,
# runs a query battery and writes inputs + outputs into a cases file (every float as a base64 Float64Array:
# Godot's JSON float parsing is not exact). This script replays the same colliders into DACollision / Nav, runs
# the same queries, compares, and measures performance.
#   godot --headless --path . -s res://tools/test_collision_nav.gd -- cases=/abs/path/cases.json
# Without cases= it runs a small self-contained smoke + performance test on synthetic boxes.
# Exit code 0 = every comparison passed.
extends SceneTree

const Col := preload("res://scripts/world/collision.gd")
const NavScript := preload("res://scripts/world/nav.gd")

var fails := 0
var checks := 0
var report := []
var maxPosErr := 0.0
const REPS := 5

func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var i: int = a.find("=")
		if i > 0:
			args[a.substr(0, i)] = a.substr(i + 1)
	if args.has("cases"):
		_crossCheck(args.cases)
	else:
		_smoke()
	print("\n".join(report))
	print("RESULT: %s (%d checks, %d failures)" % ["PASS" if fails == 0 else "FAIL", checks, fails])
	quit(0 if fails == 0 else 1)

func _f64(s: String) -> PackedFloat64Array:
	return Marshalls.base64_to_raw(s).to_float64_array()

func _fail(msg: String) -> void:
	fails += 1
	if fails <= 60:
		report.append("  MISMATCH " + msg)

func _eqf(a: float, b: float, tol: float) -> bool:
	if a == b:
		return true
	if is_nan(a) and is_nan(b):
		return true
	if is_inf(a) or is_inf(b):
		return false
	return absf(a - b) <= tol

# ------------------------------------------------------------------------------------------ replay
func _replay(st: Dictionary) -> Array:
	var col = Col.new()
	col.maskOf(st.tagOrder)
	var f := _f64(st.f)
	var handles := []
	for i in st.tags.size():
		var fl := int(st.flags[i])
		var o := {"tag": st.tags[i], "id": st.ids[i]}
		var b = null
		var j: int = i * 7
		if int(st.isRamp[i]):
			b = col.addRamp([f[j], f[j + 2], f[j + 3], f[j + 5]], f[j + 1], f[j + 4], f[j + 6], o)
		else:
			o.walkable = (fl & 1) != 0
			o.solid = (fl & 2) != 0
			o.shots = (fl & 4) != 0
			o.camera = (fl & 8) != 0
			b = col.addBox([f[j], f[j + 1], f[j + 2]], [f[j + 3], f[j + 4], f[j + 5]], o)
		if (fl & 16) == 0:
			col.setEnabled(b, false)
		handles.append(b)
		if b.bit != int(st.bits[i]):
			_fail("box %d bit %d != %d" % [i, b.bit, int(st.bits[i])])
	return [col, handles]

# ------------------------------------------------------------------------------------------ groups
func _moveGroup(col, g: Dictionary, ign: Array, label: String) -> void:
	var inp := _f64(g.inp)
	var out := _f64(g.out)
	var n := int(g.n)
	var bad := 0
	var err := 0.0
	for c in n:
		var j := c * 9
		var owner = null
		if int(g.air[c]):
			owner = {"_colGrounded": false}
		elif c % 2 == 0:
			owner = {}
		var r: Dictionary = col.moveCircle(Vector3(inp[j], inp[j + 1], inp[j + 2]), Vector3(inp[j + 3], inp[j + 4], inp[j + 5]),
			inp[j + 6], inp[j + 7], inp[j + 8], ign[int(g.ign[c])], owner)
		var o := c * 7
		var p: Vector3 = r.pos
		var e := maxf(maxf(absf(p.x - out[o]), absf(p.y - out[o + 1])), absf(p.z - out[o + 2]))
		if not is_nan(e):
			err = maxf(err, e)
		var fl := (1 if r.onGround else 0) | (2 if r.hitWall else 0) | (4 if r.hitCeiling else 0)
		var nrm: Vector3 = r.normal
		checks += 1
		if not (e <= 1e-5) or not _eqf(r.groundY, out[o + 3], 1e-9) or fl != int(g.fl[c]) \
				or not _eqf(nrm.x, out[o + 4], 1e-6) or not _eqf(nrm.z, out[o + 6], 1e-6):
			bad += 1
			_fail("%s #%d in=%s got pos=%s gY=%s fl=%d n=%s want pos=(%s,%s,%s) gY=%s fl=%d n=(%s,%s)" % [label, c,
				str(inp.slice(j, j + 9)), str(p), str(r.groundY), fl, str(nrm), out[o], out[o + 1], out[o + 2], out[o + 3], int(g.fl[c]), out[o + 4], out[o + 6]])
		if owner is Dictionary and owner.get("_colGrounded") != r.onGround:
			_fail("%s #%d owner state not stored" % [label, c])
	maxPosErr = maxf(maxPosErr, err)
	report.append("%-8s %5d cases, %d mismatches, max |pos| err %s m" % [label, n, bad, String.num_scientific(err)])

func _rayGroup(col, g: Dictionary, opts: Array, label: String) -> void:
	var inp := _f64(g.inp)
	var out := _f64(g.out)
	var n := int(g.n)
	var bad := 0
	for c in n:
		var j := c * 7
		var h = col.raycast(Vector3(inp[j], inp[j + 1], inp[j + 2]), Vector3(inp[j + 3], inp[j + 4], inp[j + 5]), inp[j + 6], opts[int(g.opt[c])])
		var o := c * 8
		checks += 1
		var ok := true
		if out[o] == 0.0:
			ok = h == null
		elif h == null:
			ok = false
		else:
			var p: Vector3 = h.point
			var nm: Vector3 = h.normal
			ok = _eqf(h.dist, out[o + 1], 1e-9) and absf(p.x - out[o + 2]) <= 1e-4 and absf(p.y - out[o + 3]) <= 1e-4 \
				and absf(p.z - out[o + 4]) <= 1e-4 and nm.x == out[o + 5] and nm.y == out[o + 6] and nm.z == out[o + 7] \
				and h.tag == g.tags[c] and h.id == g.ids[c]
		if not ok:
			bad += 1
			_fail("%s #%d in=%s got %s want %s tag=%s id=%s" % [label, c, str(inp.slice(j, j + 7)), str(h), str(out.slice(o, o + 8)), g.tags[c], g.ids[c]])
	report.append("%-8s %5d cases, %d mismatches" % [label, n, bad])

func _losGroup(col, g: Dictionary, label: String) -> void:
	var inp := _f64(g.inp)
	var n := int(g.n)
	var bad := 0
	for c in n:
		var j := c * 6
		var v: bool = col.lineOfSight(Vector3(inp[j], inp[j + 1], inp[j + 2]), Vector3(inp[j + 3], inp[j + 4], inp[j + 5]))
		checks += 1
		if int(v) != int(g.out[c]):
			bad += 1
			_fail("%s #%d in=%s got %s" % [label, c, str(inp.slice(j, j + 6)), v])
	report.append("%-8s %5d cases, %d mismatches" % [label, n, bad])

# ------------------------------------------------------------------------------------------ cross-check
func _crossCheck(path: String) -> void:
	var t_load := Time.get_ticks_msec()
	var cs = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (cs is Dictionary):
		_fail("cannot read cases " + path)
		return
	report.append("cases loaded in %d ms" % (Time.get_ticks_msec() - t_load))
	var rp := _replay(cs.station)
	var col = rp[0]
	var handles: Array = rp[1]
	report.append("replayed %d boxes (big %d)" % [col.boxes.size(), col.big.size()])
	var ign: Array = cs.ign
	var rayOpts: Array = cs.rayOpts

	# floorAt
	var fi := _f64(cs.floor.inp)
	var fo := _f64(cs.floor.out)
	var bad := 0
	for c in int(cs.floor.n):
		var j := c * 4
		var y: float = col.floorAt(fi[j], fi[j + 1], fi[j + 2], fi[j + 3])
		checks += 1
		if not _eqf(y, fo[c], 1e-12):
			bad += 1
			_fail("floorAt #%d %s got %s want %s" % [c, str(fi.slice(j, j + 4)), y, fo[c]])
	# default args
	for c in 50:
		var j := c * 4
		if fi[j + 2] == INF and fi[j + 3] == 0.45:
			checks += 1
			if not _eqf(col.floorAt(fi[j], fi[j + 1]), fo[c], 1e-12):
				_fail("floorAt default args #%d" % c)
	report.append("%-8s %5d cases, %d mismatches" % ["floorAt", int(cs.floor.n), bad])
	# blockedAt
	var bi := _f64(cs.blocked.inp)
	bad = 0
	for c in int(cs.blocked.n):
		var j := c * 6
		var v: bool = col.blockedAt(bi[j], bi[j + 1], bi[j + 2], bi[j + 3], bi[j + 4], bi[j + 5], ign[int(cs.blocked.ign[c])])
		checks += 1
		if int(v) != int(cs.blocked.out[c]):
			bad += 1
			_fail("blockedAt #%d" % c)
	report.append("%-8s %5d cases, %d mismatches" % ["blocked", int(cs.blocked.n), bad])
	_moveGroup(col, cs.move, ign, "move")
	_rayGroup(col, cs.ray, rayOpts, "raycast")
	_losGroup(col, cs.los, "los")
	var si := _f64(cs.sph.inp)
	bad = 0
	for c in int(cs.sph.n):
		var j := c * 4
		var v: bool = col.sphereFree(Vector3(si[j], si[j + 1], si[j + 2]), si[j + 3])
		checks += 1
		if int(v) != int(cs.sph.out[c]):
			bad += 1
			_fail("sphereFree #%d" % c)
	report.append("%-8s %5d cases, %d mismatches" % ["sphere", int(cs.sph.n), bad])
	# sequences (pos stored back as Vector3 every frame, one owner per walker)
	bad = 0
	var serr := 0.0
	var nf := 0
	for s in cs.seq:
		var p0 := _f64(s.p0)
		var dl := _f64(s.deltas)
		var rr := _f64(s.radius)
		var out := _f64(s.out)
		var pos := Vector3(p0[0], p0[1], p0[2])
		var owner := {}
		var sbad := 0
		for f in int(s.frames):
			var r: Dictionary = col.moveCircle(pos, Vector3(dl[f * 3], dl[f * 3 + 1], dl[f * 3 + 2]), rr[0], rr[1], rr[2], ign[int(s.ign)], owner)
			pos = r.pos
			var o := f * 7
			var e := maxf(maxf(absf(pos.x - out[o]), absf(pos.y - out[o + 1])), absf(pos.z - out[o + 2]))
			serr = maxf(serr, e)
			var fl := (1 if r.onGround else 0) | (2 if r.hitWall else 0) | (4 if r.hitCeiling else 0)
			checks += 1
			nf += 1
			if not (e <= 1e-4) or fl != int(s.fl[f]) or not _eqf(r.groundY, out[o + 3], 1e-5):
				sbad += 1
				if sbad == 1:
					_fail("seq frame %d pos %s want (%s,%s,%s) fl %d/%d gY %s/%s" % [f, str(pos), out[o], out[o + 1], out[o + 2], fl, int(s.fl[f]), r.groundY, out[o + 3]])
		bad += sbad
	report.append("%-8s %5d frames (%d walkers), %d mismatches, max |pos| err %s m" % ["seq", nf, cs.seq.size(), bad, String.num_scientific(serr)])
	# maskOf
	var M: Dictionary = cs.masks
	for i in M.lists.size():
		checks += 1
		if col.maskOf(M.lists[i]) != int(M.out[i]):
			_fail("maskOf %s = %d want %d" % [str(M.lists[i]), col.maskOf(M.lists[i]), int(M.out[i])])
	for i in M.num.size():
		checks += 1
		if col.maskOf(int(M.num[i])) != int(M.numOut[i]):
			_fail("maskOf number")
	checks += 1
	if col.maskOf(null) != int(M.nul):
		_fail("maskOf null")
	# toggles
	for op in cs.toggles:
		col.setEnabled(op.id if op.has("id") else handles[int(op.idx)], op.on)
	bad = 0
	for i in col.boxes.size():
		checks += 1
		if int(col.boxes[i].enabled) != int(cs.enabledAfter[i]) or ((col._flags[i] & Col.F_ENABLED) != 0) != col.boxes[i].enabled:
			bad += 1
			_fail("enabled state box %d" % i)
	report.append("%-8s %d ops, %d state mismatches" % ["toggles", cs.toggles.size(), bad])
	_moveGroup(col, cs.move2, ign, "move2")
	_rayGroup(col, cs.ray2, rayOpts, "raycast2")
	_losGroup(col, cs.los2, "los2")
	var ops: Array = cs.toggles.duplicate()
	ops.reverse()
	for op in ops:
		col.setEnabled(op.id if op.has("id") else handles[int(op.idx)], true)
	for i in handles.size():
		col.setEnabled(handles[i], (int(cs.station.flags[i]) & 16) != 0)

	_navCheck(cs, col)
	_perf(cs, col)

func _navCheck(cs: Dictionary, col) -> void:
	var pl := _f64(cs.station.player)
	var game := {"level": {"col": col}, "player": {"pos": Vector3(pl[0], pl[1], pl[2])}}
	var nav = NavScript.new(game)
	var t0 := Time.get_ticks_usec()
	nav.build()
	var buildMs := (Time.get_ticks_usec() - t0) / 1000.0
	var B: Dictionary = cs.navBuild
	checks += 1
	if nav.w != int(B.w) or nav.h != int(B.h) or nav.x0 != float(B.x0) or nav.z0 != float(B.z0):
		_fail("nav grid dims %d %d %s %s" % [nav.w, nav.h, nav.x0, nav.z0])
		return
	var hh := _f64(B.height)
	var bad := 0
	for i in nav.w * nav.h:
		checks += 1
		if nav.height[i] != hh[i] or nav.base[i] != int(B.base[i]) or nav.doorOf[i] != int(B.doorOf[i]) or nav.near[i] != int(B.near[i]):
			bad += 1
			if bad < 5:
				_fail("nav cell %d h %s/%s base %d/%d door %d/%d near %d/%d" % [i, nav.height[i], hh[i], nav.base[i], int(B.base[i]), nav.doorOf[i], int(B.doorOf[i]), nav.near[i], int(B.near[i])])
	checks += 1
	if str(nav.doorIds) != str(B.doorIds):
		_fail("doorIds %s want %s" % [str(nav.doorIds), str(B.doorIds)])
	for rep in REPS - 1:
		t0 = Time.get_ticks_usec()
		nav.build()
		buildMs = minf(buildMs, (Time.get_ticks_usec() - t0) / 1000.0)
	report.append("%-8s %dx%d cells, %d mismatches, build %.1f ms (JS %.1f ms)" % ["navbuild", nav.w, nav.h, bad, buildMs, float(cs.jsTimes.buildWarm)])
	# the per-cell reference path (collision floorAt + blockedAt per cell, as the JS does) must agree with _navGrid
	t0 = Time.get_ticks_usec()
	var pbad := 0
	for k in nav.h:
		for i in nav.w:
			var idx: int = k * nav.w + i
			var x: float = nav.x0 + (i + 0.5) * 0.5
			var z: float = nav.z0 + (k + 0.5) * 0.5
			var y: float = col.floorAt(x, z, INF)
			var b := 1 if y > -INF and not col.blockedAt(x, z, 0.35, y, 0.45, 1.7, ["door"]) else 0
			if y != nav.height[idx] or b != nav.base[idx]:
				pbad += 1
	checks += 1
	if pbad:
		_fail("_navGrid differs from per-cell floorAt/blockedAt in %d cells" % pbad)
	report.append("%-8s per-cell path agrees (%d diffs), %.1f ms" % ["navgrid", pbad, (Time.get_ticks_usec() - t0) / 1000.0])

	var S := _f64(cs.navSamples)
	var ns := S.size() / 2
	var solveTimes := []
	var sbad := 0
	for sv in cs.solves:
		nav.reset()
		for id in sv.open:
			nav.setDoor(id, true)
		var g := _f64(sv.g)
		var best := INF
		for rep in REPS:
			t0 = Time.get_ticks_usec()
			nav.solveNow(g[0], g[1])
			best = minf(best, (Time.get_ticks_usec() - t0) / 1000.0)
		solveTimes.append(snappedf(best, 0.01))
		var fr := _f64(sv.front)
		var fb := 0
		for i in fr.size():
			if nav.front[i] != fr[i]:
				fb += 1
		var gg := _f64(sv.goal)
		checks += 1
		if fb or nav.goal.x != gg[0] or nav.goal.z != gg[1] or nav.goal.cell != int(sv.goalCell):
			sbad += 1
			_fail("solve %s: %d field cells differ, goal %s" % [str(g), fb, str(nav.goal)])
		sbad += _navSamples(nav, null, S, ns, _f64(sv.samples), "solve %s" % str(g))
		var wk := _f64(sv.walk)
		for i in ns:
			checks += 1
			if int(nav.walkable(S[i * 2], S[i * 2 + 1])) != int(wk[i * 2]) or nav.heightAt(S[i * 2], S[i * 2 + 1]) != wk[i * 2 + 1]:
				sbad += 1
				_fail("walkable/heightAt sample %d" % i)
	report.append("%-8s %d goals x (%d field cells + %d dir/dist/walkable samples), %d mismatches; solveNow ms %s (JS %s)" % ["navsolve",
		cs.solves.size(), nav.w * nav.h, ns, sbad, str(solveTimes), str((cs.jsTimes.solveWarm as Array).map(func(v): return snappedf(v, 0.01)))])
	# debug image
	var D: Dictionary = cs.debug
	nav.reset()
	for id in D.open:
		nav.setDoor(id, true)
	for id in D.closed:
		nav.setDoor(id, false)
	var dg := _f64(D.goal)
	nav.solveNow(dg[0], dg[1])
	var dbad := 0
	for pair in [["dist", D.dist], ["height", D.height], ["", D.def]]:
		var img: Dictionary = nav.debugImage(pair[0]) if pair[0] != "" else nav.debugImage()
		var want := Marshalls.base64_to_raw(pair[1])
		checks += 1
		if img.data != want or img.width != int(D.w) or img.height != int(D.h):
			dbad += 1
			var nd := 0
			var first := -1
			for i in mini(img.data.size(), want.size()):
				if img.data[i] != want[i]:
					nd += 1
					if first < 0:
						first = i
			_fail("debugImage(%s) %d bytes differ (first %d: %d vs %d)" % [pair[0], nd, first, img.data[first] if first >= 0 else -1, want[first] if first >= 0 else -1])
	report.append("%-8s 3 modes, %d mismatches" % ["debugimg", dbad])
	# local fields
	var lbad := 0
	var lfTimes := []
	for lf in cs.lf:
		nav.reset()
		for id in lf.open:
			nav.setDoor(id, true)
		var p := _f64(lf.p)
		var api = null
		var best := INF
		for rep in REPS:
			t0 = Time.get_ticks_usec()
			api = nav.localField(p[0], p[1], float(lf.maxDist))
			best = minf(best, (Time.get_ticks_usec() - t0) / 1000.0)
		lfTimes.append(snappedf(best, 0.01))
		var fr := _f64(lf.field)
		var fb := 0
		for i in fr.size():
			if api.field[i] != fr[i]:
				fb += 1
		var gg := _f64(lf.goal)
		checks += 1
		if fb or api.goal.x != gg[0] or api.goal.z != gg[1] or api.goal.cell != int(lf.goalCell):
			lbad += 1
			_fail("localField %s: %d cells differ" % [str(p), fb])
		lbad += _navSamples(nav, api, S, ns, _f64(lf.samples), "localField %s" % str(p))
	report.append("%-8s %d lures, %d mismatches, ms %s (JS %s)" % ["localfld", cs.lf.size(), lbad, str(lfTimes), str((cs.lf as Array).map(func(v): return snappedf(v.ms, 0.01)))])
	# time-sliced update(): the field converges to the solveNow result of the same goal, within the budget per frame
	# (the spawn goal with every door closed, and the slowest JS goal)
	var slow := 0
	for i in cs.solves.size():
		if float(cs.jsTimes.solveWarm[i]) > float(cs.jsTimes.solveWarm[slow]):
			slow = i
	for si in [0, slow]:
		var sv0: Dictionary = cs.solves[si]
		nav.reset()
		for id in sv0.open:
			nav.setDoor(id, true)
		nav.build()
		var g0 := _f64(sv0.g)
		game.player.pos = Vector3(g0[0], 0.0, g0[1])
		var frames := 0
		var times := []
		while frames < 3000:
			var was: bool = nav._solving
			t0 = Time.get_ticks_usec()
			nav.update(1.0 / 60.0)
			var ms := (Time.get_ticks_usec() - t0) / 1000.0
			if was or nav._solving or nav.goal.cell == int(sv0.goalCell):
				frames += 1
				times.append(snappedf(ms, 0.01))
			if not nav._solving and nav.goal.cell == int(sv0.goalCell):
				break
		report.append("         per-frame ms: %s" % str(times))
		times.sort()
		var fr0 := _f64(sv0.front)
		var ub := 0
		for i in fr0.size():
			if nav.front[i] != fr0[i]:
				ub += 1
		checks += 1
		if ub or nav.goal.cell != int(sv0.goalCell):
			_fail("update(): sliced solve differs in %d cells" % ub)
		report.append("%-8s goal #%d sliced solve done in %d update() frames, per-frame ms median %.2f max %.2f (BUDGET_MS %.1f), %d cells differ" % ["update",
			si, frames, times[times.size() / 2], times[-1], NavScript.BUDGET_MS, ub])
	# the 0.25 s re-solve cadence and door dirtiness
	var t1: float = nav._t
	nav.update(0.1)
	checks += 1
	if nav._solving:
		_fail("update(): re-solved before PERIOD without a goal change")
	nav.setDoor(nav.doorIds[0], true)
	nav.update(0.2)
	checks += 1
	if not nav._solving and not (nav._t == 0.0):
		_fail("update(): door change did not trigger a re-solve after PERIOD (t=%s)" % str(t1))

func _navSamples(nav, api, S: PackedFloat64Array, ns: int, want: PackedFloat64Array, label: String) -> int:
	var bad := 0
	for i in ns:
		var x := S[i * 2]
		var z := S[i * 2 + 1]
		var d: Vector3 = api.dir(x, z) if api != null else nav.dir(x, z)
		var ds: float = api.dist(x, z) if api != null else nav.dist(x, z)
		checks += 1
		if not _eqf(d.x, want[i * 3], 1e-6) or not _eqf(d.z, want[i * 3 + 1], 1e-6) or d.y != 0.0 or not _eqf(ds, want[i * 3 + 2], 1e-9):
			bad += 1
			_fail("%s sample %d (%s,%s): dir %s dist %s want (%s,%s) %s" % [label, i, x, z, str(d), ds, want[i * 3], want[i * 3 + 1], want[i * 3 + 2]])
	return bad

# ------------------------------------------------------------------------------------------ performance
# Timings: every batch of CHUNK calls is repeated REPS times and its fastest run kept (the sum of the batch minima,
# robust against preemption on a loaded machine), divided by the number of calls.
const CHUNK := 50

func _perf(cs: Dictionary, col) -> void:
	var inp := _f64(cs.move.inp)
	var n := int(cs.move.n)
	var ign: Array = cs.ign
	var owner := {}
	var poss: Array[Vector3] = []
	var dels: Array[Vector3] = []
	var igs := []
	for c in n:
		var j := c * 9
		poss.append(Vector3(inp[j], inp[j + 1], inp[j + 2]))
		dels.append(Vector3(inp[j + 3], inp[j + 4], inp[j + 5]))
		igs.append(ign[int(cs.move.ign[c])])
	var total := 0.0
	for c0 in range(0, n, CHUNK):
		var best := INF
		for rep in REPS:
			var t0 := Time.get_ticks_usec()
			for c in range(c0, mini(n, c0 + CHUNK)):
				var j := c * 9
				col.moveCircle(poss[c], dels[c], inp[j + 6], inp[j + 7], inp[j + 8], igs[c], owner)
			best = minf(best, Time.get_ticks_usec() - t0)
		total += best
	var moveUs := total / n
	# typical zombie step: walking speed 1.6 m/s at 60 fps, radius 0.35, on walkable floor
	var zp: Array[Vector3] = []
	var fl := _f64(cs.floor.inp)
	var c1 := 0
	while zp.size() < 400 and c1 < 6000:
		var y: float = col.floorAt(fl[c1 * 4], fl[c1 * 4 + 1], 50.0)
		if y > -INF:
			zp.append(Vector3(fl[c1 * 4], y, fl[c1 * 4 + 1]))
		c1 += 1
	total = 0.0
	for c0 in range(0, zp.size(), CHUNK):
		var best := INF
		for rep in REPS:
			var t0 := Time.get_ticks_usec()
			for c in range(c0, mini(zp.size(), c0 + CHUNK)):
				var a := c * 0.7
				col.moveCircle(zp[c], Vector3(cos(a) * 1.6 / 60.0, -0.16, sin(a) * 1.6 / 60.0), 0.35, 1.7, 0.45, null, owner)
			best = minf(best, Time.get_ticks_usec() - t0)
		total += best
	var zUs := total / zp.size()
	var ri := _f64(cs.ray.inp)
	var nr := int(cs.ray.n)
	var ro: Array[Vector3] = []
	var rd: Array[Vector3] = []
	for c in nr:
		ro.append(Vector3(ri[c * 7], ri[c * 7 + 1], ri[c * 7 + 2]))
		rd.append(Vector3(ri[c * 7 + 3], ri[c * 7 + 4], ri[c * 7 + 5]))
	total = 0.0
	for c0 in range(0, nr, CHUNK):
		var best := INF
		for rep in REPS:
			var t0 := Time.get_ticks_usec()
			for c in range(c0, mini(nr, c0 + CHUNK)):
				col.raycast(ro[c], rd[c], ri[c * 7 + 6])
			best = minf(best, Time.get_ticks_usec() - t0)
		total += best
	var rayUs := total / nr
	var li := _f64(cs.los.inp)
	var nl := int(cs.los.n)
	var la: Array[Vector3] = []
	var lb: Array[Vector3] = []
	for c in nl:
		la.append(Vector3(li[c * 6], li[c * 6 + 1], li[c * 6 + 2]))
		lb.append(Vector3(li[c * 6 + 3], li[c * 6 + 4], li[c * 6 + 5]))
	total = 0.0
	for c0 in range(0, nl, CHUNK):
		var best := INF
		for rep in REPS:
			var t0 := Time.get_ticks_usec()
			for c in range(c0, mini(nl, c0 + CHUNK)):
				col.lineOfSight(la[c], lb[c])
			best = minf(best, Time.get_ticks_usec() - t0)
		total += best
	var losUs := total / nl
	total = 0.0
	for c0 in range(0, 2000, CHUNK):
		var best := INF
		for rep in REPS:
			var t0 := Time.get_ticks_usec()
			for c in range(c0, c0 + CHUNK):
				col.floorAt(fl[c * 4], fl[c * 4 + 1], fl[c * 4 + 2], fl[c * 4 + 3])
			best = minf(best, Time.get_ticks_usec() - t0)
		total += best
	var floorUs := total / 2000.0
	report.append("perf     moveCircle %.1f us/call on the battery (JS %.1f), %.1f us typical zombie step; raycast %.1f us (JS %.1f); lineOfSight %.1f us; floorAt %.1f us" % [
		moveUs, float(cs.jsTimes.moveUs), zUs, rayUs, float(cs.jsTimes.rayUs), losUs, floorUs])

# ------------------------------------------------------------------------------------------ smoke test
func _smoke() -> void:
	var col = Col.new()
	col.addBox([-50, -1, -50], [60, 0, 50], {"tag": "floor", "id": "ground"})
	col.addBox([5, 0, -5], [5.3, 3, 5], {"tag": "wall"})
	col.addBox([0, 0, 2], [1, 0.3, 3], {"tag": "prop"})
	col.addBox([0, 0, 3], [1, 0.6, 4], {"tag": "prop"})
	col.addRamp([-6, -6, -2, -2], 0.0, 1.0, 1.0, {"tag": "platform", "id": "rp"})
	var d = col.addBox([2, 0, -10], [3, 2.5, -9], {"tag": "door", "id": "dA"})
	# walk into the wall: slides, stops at x = 5 - r
	var pos := Vector3(4.0, 0.0, 0.0)
	var owner := {}
	for i in 30:
		var r: Dictionary = col.moveCircle(pos, Vector3(0.1, -0.1, 0.02), 0.35, 1.7, 0.45, null, owner)
		pos = r.pos
	checks += 1
	if absf(pos.x - (5.0 - 0.35 - 1e-4)) > 1e-3 or absf(pos.y) > 1e-6:
		_fail("wall slide pos %s" % str(pos))
	# stairs: climb 0.3 then 0.6
	pos = Vector3(0.5, 0.0, 1.0)
	for i in 40:
		pos = col.moveCircle(pos, Vector3(0, -0.1, 0.1), 0.35, 1.7, 0.45, null, owner).pos
	checks += 1
	if absf(pos.y) > 1e-6 or pos.z < 4.5:
		_fail("stairs pos %s" % str(pos))
	checks += 1
	if absf(col.floorAt(-4.0, -4.0) - 1.0) > 1e-9 or absf(col.floorAt(-5.5, -4.0) - 0.5) > 1e-9:
		_fail("ramp floorAt %s %s" % [col.floorAt(-4.0, -4.0), col.floorAt(-5.5, -4.0)])
	var h = col.raycast(Vector3(0, 1, 0), Vector3(1, 0, 0), 20.0)
	checks += 1
	if h == null or absf(h.dist - 5.0) > 1e-9 or h.tag != "wall" or h.normal != Vector3(-1, 0, 0):
		_fail("raycast %s" % str(h))
	checks += 1
	if col.lineOfSight(Vector3(0, 1, 0), Vector3(8, 1, 0)) or not col.lineOfSight(Vector3(0, 1, 0), Vector3(4, 1, 0)):
		_fail("lineOfSight")
	col.setEnabled("dA", false)
	checks += 1
	if d.enabled or col.raycast(Vector3(2.5, 1, -12), Vector3(0, 0, 1), 5.0) != null and col.raycast(Vector3(2.5, 1, -12), Vector3(0, 0, 1), 5.0).tag == "door":
		_fail("setEnabled by id")
	d.enabled = true
	checks += 1
	if col.raycast(Vector3(2.5, 1, -12), Vector3(0, 0, 1), 5.0).tag != "door":
		_fail("Box.enabled setter sync")
	checks += 1
	if not col.sphereFree(Vector3(0, 2, 0), 0.25) or col.sphereFree(Vector3(5.1, 1, 0), 0.25):
		_fail("sphereFree")
	# owner = an Object (meta) and Vector3 box corners
	col.addBox(Vector3(-20, 0, -20), Vector3(-19, 1.0, -19), {"tag": "prop"})
	checks += 1
	if absf(col.floorAt(-19.5, -19.5, 0.8) - 1.0) > 1e-9:
		_fail("Vector3 corners")
	var ob := RefCounted.new()
	pos = Vector3(10, 0, 10)
	var r1: Dictionary = col.moveCircle(pos, Vector3(0, 0.5, 0), 0.35, 1.7, 0.45, null, ob)
	pos = r1.pos
	checks += 1
	if r1.onGround or ob.get_meta("_colGrounded", true) != false:
		_fail("object owner airborne state")
	# airborne, 0.3 m above the floor, falling slowly: no snap (grounded bodies would snap down)
	# (the result Dictionary is reused between calls, like the JS: copy what you need before the next call)
	var r2: Dictionary = col.moveCircle(Vector3(10, 0.3, 10), Vector3(0, -0.01, 0), 0.35, 1.7, 0.45, null, ob).duplicate()
	var r3: Dictionary = col.moveCircle(Vector3(10, 0.3, 10), Vector3(0, -0.01, 0), 0.35, 1.7, 0.45, null, null)
	checks += 1
	if r2.onGround or absf(r2.pos.y - 0.29) > 1e-6 or not r3.onGround or r3.pos.y != 0.0:
		_fail("grounded memory: airborne %s / fresh %s" % [str(r2.pos), str(r3.pos)])
	# nav on the synthetic world (stub game): a solve reaches around the wall
	var game := {"level": {"col": col}, "player": {"pos": Vector3(8, 0, 0)}}
	var nav = NavScript.new(game)
	nav.solveNow(8.0, 0.0)
	var dv: Vector3 = nav.dir(2.0, 0.0)
	checks += 1
	if not nav.built or nav.dist(2.0, 0.0) == INF or dv.length() < 0.99 or not nav.walkable(2.0, 0.0) or nav.walkable(5.15, 0.0):
		_fail("nav smoke: dist %s dir %s" % [nav.dist(2.0, 0.0), str(dv)])
	var lf = nav.localField(0.0, -1.0, 5.0)
	checks += 1
	if lf.dist(0.5, -1.0) > 1.0 or lf.dist(30.0, 0.0) != INF:
		_fail("localField smoke")
	report.append("smoke: collision + nav basics done")
