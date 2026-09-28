# Interactable registry + focus selection (port of src/core/interact.js; ARCHITECTURE §10/§12, GDD §14/§16).
# register({ id, pos:Vector3|[x,y,z], radius=1.6, height?, enabled:()=>bool, prompt:()=>({cost?, plug?, hold?,
#   denied?}|null), use:()=>void, hold?:seconds, onHold?:(t 0..1)=>void,
#   facing?:rotY | normal?:Vector3|[x,y,z]   front side of a wall-mounted item (rotY uses the anchor convention:
#                                            front = (-sin rotY, 0, -cos rotY)); the player must stand in front
#   facingSlack?=0.25 (m the feet may sit behind the item's plane), los?=true (false: skip the wall test),
#   losIgnore?:[colliderId]                  architecture colliders that belong to the item itself }) -> item;
# unregister(id).
# Callbacks are Callables (enabled / prompt / use / onHold); the item is a Dictionary (the def's keys + defaults).
# Focus = the best enabled item that is (a) within its radius of the player (horizontal) and height band,
# (b) in front of the camera (or right under the player), (c) on the item's front side when it declares a facing,
# and (d) in line of sight from the player's head against ARCHITECTURE only (walls, glass, fences, closed doors,
# boarded windows, the tower base — props never block, so an item's own prop is ignored): nothing is usable
# through a wall. E tap uses it; items with `hold` need E held (progress 0..1, reset on release or focus change,
# one completion per press). Drives hud.setPrompt({ ...prompt, key:'E' | 'X' (input.glyph(): X while the Xbox pad is
# the last device), progress, denied }) every frame (null when nothing is focused). `current` is the focused item.
# Emits interact:use {id}.
# check(itemOrId) -> { ok, dist, dy, inRadius, inHeight, front, los } geometry only (no camera facing, no
#   enabled/prompt), for tests and debugging.
# Renames (SPEC §3.2): none.
extends RefCounted

# Collider tags that stop an interaction (shell.gd); everything else (props, machines, platforms, floor) is ignored.
const ARCH_TAGS := ["wall", "glass", "fence", "door", "window", "lattice"]
const EYE := 1.5          # m above the feet: the player's head
const LOS_TOL := 0.12     # a hit this close to the target still counts as reaching it (points on / in a wall face)
const FRONT_LIFT := 0.1   # faced items: the sight target is pulled this far out of their plane

var game
var items := {}           # id -> item (Map: insertion order kept)
var current = null
var prompt = null
var progress := 0.0
var _holdItem = null
var _holdDone := false
var _shown := {"item": null, "prompt": {}}
var _col = null
var _losOpts := {"camera": true, "ignoreTags": 0}

func _init(g) -> void:
	game = g

static func _truthy(v) -> bool:
	if v == null:
		return false
	if v is bool:
		return v
	if v is int or v is float:
		return v != 0 and not is_nan(float(v))
	if v is String or v is StringName:
		return v != ""
	return true

func register(def: Dictionary) -> Dictionary:
	var pos: Vector3 = DAU.v3(def.get("pos", [0, 0, 0]))
	var item := {"radius": 1.6, "height": null, "enabled": func() -> bool: return true, "prompt": func() -> Dictionary: return {},
		"use": func() -> void: pass, "hold": 0.0, "los": true, "losIgnore": null, "facingSlack": 0.25}
	for k in def:
		item[k] = def[k]
	item.pos = pos
	var n = null
	if def.get("normal") != null:
		n = DAU.v3(def.normal)
	elif def.get("facing") is float or def.get("facing") is int:
		var f := float(def.facing)
		n = Vector3(-sin(f), 0.0, -cos(f))
	if n != null:
		n.y = 0.0
		if n.length_squared() > 1e-8:
			n = n.normalized()
		else:
			n = null
	item.normal = n
	items[item.id] = item
	return item

func unregister(id) -> void:
	items.erase(id)
	if current != null and current.id == id:
		current = null

func reset() -> void:
	current = null
	prompt = null
	progress = 0.0
	_holdItem = null

# Player on the item's front side (items without a facing: always).
func _front(it: Dictionary, p) -> bool:
	var n = it.normal
	if n == null:
		return true
	return (p.pos.x - it.pos.x) * n.x + (p.pos.z - it.pos.z) * n.z > -float(it.facingSlack)

# Line of sight from the player's head to the item against architecture colliders.
func _los(it: Dictionary, p) -> bool:
	if it.get("los") is bool and it.los == false:
		return true
	var col = game.level.get("col") if game.level != null else null
	if col == null or not col.has_method("raycast"):
		return true
	if not is_same(_col, col):
		# ignore every tag bit except the architecture ones (tags registered later get non-architecture bits)
		_col = col
		_losOpts.ignoreTags = ~int(col.maskOf(ARCH_TAGS)) & 0x7fffffff
	var ph = p.get("height")
	var eye := Vector3(p.pos.x, p.pos.y + minf(EYE, (float(ph) if ph else 1.75) * 0.86), p.pos.z)
	var t: Vector3 = it.pos
	if it.normal != null:
		t += it.normal * FRONT_LIFT
	var o := eye
	var d := t - o
	var left := d.length()
	if left < 0.25:
		return true
	d /= left
	for i in 4:
		var hit = col.raycast(o, d, left, _losOpts)
		if hit == null or hit.dist >= left - LOS_TOL:
			return true
		var ign = it.get("losIgnore")
		if ign == null or not ign.has(hit.id):
			return false
		# the item's own architecture (e.g. its door blocker): continue from just inside that box
		o += d * (hit.dist + 0.01)
		left -= hit.dist + 0.01
	return false

func check(itemOrId) -> Variant:
	var it = items.get(itemOrId) if (itemOrId is String or itemOrId is StringName) else itemOrId
	var p = game.player
	if it == null or p == null:
		return null
	var dist := Vector2(it.pos.x - p.pos.x, it.pos.z - p.pos.z).length()
	var dy: float = it.pos.y - p.pos.y
	var inRadius: bool = dist <= float(it.radius)
	var inHeight: bool = absf(dy) <= float(it.height) if it.height != null else (dy >= -1.2 and dy <= 2.8)
	var front := _front(it, p)
	var los := _los(it, p)
	return {"ok": inRadius and inHeight and front and los, "dist": dist, "dy": dy, "inRadius": inRadius,
		"inHeight": inHeight, "front": front, "los": los}

func update(dt: float) -> void:
	var g = game
	var p = g.player
	var best = null
	var bestPrompt = null
	var bestScore := INF
	if p != null and p.alive and not p.downed and g.camera != null:
		var cam: Camera3D = g.camera
		var _f: Vector3 = -(cam.global_transform.basis.z if cam.is_inside_tree() else cam.transform.basis.z)
		_f.y = 0.0
		_f = _f.normalized()
		for it in items.values():
			var dx: float = it.pos.x - p.pos.x
			var dz: float = it.pos.z - p.pos.z
			var d := sqrt(dx * dx + dz * dz)
			if d > float(it.radius):
				continue
			var dy: float = it.pos.y - p.pos.y
			if (absf(dy) > float(it.height)) if it.height != null else (dy < -1.2 or dy > 2.8):
				continue
			var facing := 1.0 if d < 0.8 else (dx * _f.x + dz * _f.z) / d
			if facing < 0.3:
				continue
			if not _front(it, p):
				continue
			var score := d * (1.6 - facing)
			if score >= bestScore:
				continue
			if not _truthy(_callv(it.enabled)):
				continue
			var pr = _callv(it.prompt) if it.prompt is Callable and it.prompt.is_valid() else {}
			if pr == null:
				continue
			if not _los(it, p):
				continue
			bestScore = score
			best = it
			bestPrompt = pr
	if not is_same(best, _holdItem):
		progress = 0.0
		_holdItem = null
	current = best
	prompt = bestPrompt

	var input = g.input
	if not input.down("interact"):
		_holdDone = false
	if best != null and dt > 0.0:
		var hold := float(best.hold) if best.hold else 0.0
		if hold > 0.0:
			if input.down("interact") and not _holdDone:
				_holdItem = best
				progress = minf(1.0, progress + dt / hold)
				var oh = best.get("onHold")
				if oh is Callable and oh.is_valid():
					oh.call(progress)
				if progress >= 1.0:
					_use(best)
					progress = 0.0
					_holdDone = true
			else:
				progress = 0.0
		elif input.pressed("interact"):
			_use(best)
	_updateHud(best, bestPrompt)

static func _callv(fn) -> Variant:
	if fn is Callable and fn.is_valid():
		return fn.call()
	return fn

func _use(it: Dictionary) -> void:
	if it.use is Callable and it.use.is_valid():
		it.use.call()
	game.events.emit("interact:use", {"id": it.id})

func _updateHud(item, pr) -> void:
	var hud = game.hud
	if hud == null or not hud.has_method("setPrompt"):
		return
	if item == null:
		if _shown.item != null:
			hud.setPrompt(null)
		_shown.item = null
		return
	var pts: float = float(game.economy.points) if game.economy != null else INF
	var out := {}
	for k in pr:
		out[k] = pr[k]
	out.key = game.input.glyph() if game.input != null and game.input.has_method("glyph") else "E"  # 'X' while playing with the pad
	var ih = item.get("hold")
	out.hold = pr.hold if pr.get("hold") != null else (ih if ih else null)
	out.progress = progress
	out.denied = pr.denied if pr.get("denied") != null else (pr.get("cost") != null and float(pr.cost) > pts)
	_shown.item = item
	hud.setPrompt(out)
