# Lighting (port of src/core/lights.js; ARCHITECTURE §5, GDD §3.3/§3.9):
#  - HemisphereLight lerping toward the current area's ambient (level.areas[id].ambient; before power its
#    ambientPre, or ambient x0.6 when an area has none),
#    plus the per-area fog (render.fog always exists; "no fog" = pushed far away),
#  - one warm key DirectionalLight3D, the only shadow caster, its transform following the player (texel-snapped like
#    the JS shadow camera; Godot fits the 2048 shadow map around the camera itself) + a cool shadowless fill,
#  - exactly 8 pooled OmniLight3D, reassigned every 0.2 s to the anchors nearest the camera (same/adjacent area
#    first) with smooth fades. Lights are never added/removed at runtime.
# API: addAnchor({pos, color, intensity, distance, area, flicker?, id?}) -> anchor, setAnchor(id, {color,
#   intensity, enabled, flicker}), removeAnchor(id), flicker(id, amount, seconds), flash(pos, color, intensity,
#   seconds, distance) (transient, takes a slot immediately; used by fx.flashLight).
# Point intensities are three.js candela with decay 1.5 (typical fixture 2..6, distance 6..14 m): OmniLight3D
# light_energy = intensity, omni_attenuation = 1.5, omni_range = distance (Godot's omni falloff is three's).
# Godot mapping: `hemi` is a DAHemi (Node3D: two DirectionalLight3D with light_specular = 0, the shaders' hemisphere
# sentinel) with the THREE.HemisphereLight fields color / groundColor / intensity; `key` / `fill` are
# DirectionalLight3D (THREE .color = light_color, .intensity = light_energy); anchors are Dictionaries
# {id, pos: Vector3, color: Color, intensity, distance, area, flicker, enabled, cur, boost, boostT, seed, flash, ...};
# `anchors` is a Dictionary id -> anchor (the JS Map, insertion ordered). All colours are Godot Colors in sRGB
# (Color("#hex")); THREE.Color lerps happen in linear space in the JS (negligible difference here).
extends RefCounted

const POOL := 8
const REASSIGN := 0.2
const FADE_OUT := 0.18
const FADE_IN := 0.3
const HEMI_SCALE := 1.35    # area table intensities are artistic 0..1; scaled to renderer units here
const KEY := {"powered": 1.7, "dark": 1.3}  # warm key; lit diffuse stays under the bloom threshold
const PRE_POWER := 0.6      # GDD §3.3
const DEFAULT_AMBIENT := {"sky": "#FFE2B8", "ground": "#6B4226", "intensity": 0.9}
const SHADOW_SIZE := 36.0   # the JS shadow camera box (-18..18 m)

# THREE.HemisphereLight: two sentinel directional lights (sky shining down, ground shining up), the DEAD AIR shaders
# turn them into three's hemisphere irradiance mix(ground, sky, 0.5 * N.y + 0.5) (see da_common.gdshaderinc).
# Other worlds (menu, ending) create their own: DAHemi.new(sky, ground, intensity) added under their scene root.
class DAHemi extends Node3D:
	var sky: DirectionalLight3D
	var ground: DirectionalLight3D
	var _color := Color(1, 1, 1)
	var _groundColor := Color(0, 0, 0)
	var _intensity := 1.0
	var color: Color:
		get:
			return _color
		set(v):
			_color = v
			sky.light_color = v
	var groundColor: Color:
		get:
			return _groundColor
		set(v):
			_groundColor = v
			ground.light_color = v
	var intensity: float:
		get:
			return _intensity
		set(v):
			_intensity = v
			sky.light_energy = v
			ground.light_energy = v
	func _init(skyColor = "#ffffff", groundCol = "#444444", inten := 1.0) -> void:
		name = "HemisphereLight"
		sky = _half("sky", Vector3(-PI / 2, 0, 0))
		ground = _half("ground", Vector3(PI / 2, 0, 0))
		color = DAU.color(skyColor)
		groundColor = DAU.color(groundCol)
		intensity = inten
	func _half(n: String, rot: Vector3) -> DirectionalLight3D:
		var l := DirectionalLight3D.new()
		l.name = n
		l.rotation = rot
		l.light_specular = 0.0
		l.shadow_enabled = false
		l.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
		l.light_bake_mode = Light3D.BAKE_DISABLED
		add_child(l)
		return l

var game
var hemi: DAHemi
var key: DirectionalLight3D
var fill: DirectionalLight3D
var keyDir := Vector3(-0.42, 1, 0.32).normalized()  # toward the light: mostly overhead
var pool: Array = []
var anchors := {}
var _pendingFlash: Array = []
var _uid := 0
var _t := 0.0
var _reassignT := 0.0
var _ambient := {}
var _fog := {}

func _init(g) -> void:
	game = g
	var scene: Node3D = game.scene

	hemi = DAHemi.new(DEFAULT_AMBIENT.sky, DEFAULT_AMBIENT.ground, DEFAULT_AMBIENT.intensity * HEMI_SCALE)
	scene.add_child(hemi)

	key = DirectionalLight3D.new()
	key.name = "KeyLight"
	key.light_color = Color("#FFE4C2")
	key.light_energy = KEY.powered
	key.light_specular = 1.0
	key.shadow_enabled = true
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	key.directional_shadow_max_distance = SHADOW_SIZE
	key.directional_shadow_fade_start = 0.9
	key.shadow_bias = 0.03
	key.shadow_normal_bias = 1.0
	key.shadow_blur = 1.5
	key.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	scene.add_child(key)

	fill = DirectionalLight3D.new()
	fill.name = "FillLight"
	fill.light_color = Color("#9FB6FF")
	fill.light_energy = 0.35
	fill.light_specular = 1.0
	fill.shadow_enabled = false
	fill.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	scene.add_child(fill)
	_aim(fill, Vector3(0.6, 0.35, -0.7), Vector3.ZERO)

	for i in POOL:
		var light := OmniLight3D.new()
		light.name = "PoolLight%d" % i
		light.light_color = Color("#ffffff")
		light.light_energy = 0.0
		light.omni_range = 10.0
		light.omni_attenuation = 1.5
		light.light_specular = 1.0
		light.shadow_enabled = false
		scene.add_child(light)
		pool.append({"light": light, "anchor": null, "next": null, "hasNext": false, "level": 0.0})

	_ambient = {"sky": Color(DEFAULT_AMBIENT.sky), "ground": Color(DEFAULT_AMBIENT.ground), "intensity": DEFAULT_AMBIENT.intensity}
	_fog = {"color": Color("#150F1C"), "near": 1000.0, "far": 2000.0}
	_updateKey()

# Points a directional light from `pos` toward `target` (three: light.position + light.target).
static func _aim(l: Node3D, pos: Vector3, target: Vector3) -> void:
	l.position = pos
	var d := target - pos
	if d.length_squared() < 1e-12:
		return
	var up := Vector3.UP if absf(d.normalized().y) < 0.999 else Vector3.FORWARD
	l.basis = Basis.looking_at(d, up)

func reset() -> void:
	for id in anchors.keys():
		if anchors[id].flash:
			anchors.erase(id)
	_pendingFlash.clear()
	for slot in pool:
		if slot.anchor != null and slot.anchor.flash:
			slot.anchor = null
			slot.level = 0.0
	_reassignT = 0.0

# slot.next: JS undefined (no pending swap) = hasNext false; JS null (fade out to nothing) = hasNext true + next null.
func addAnchor(o: Dictionary) -> Dictionary:
	_uid += 1
	var id = o.get("id")
	var pos = o.get("pos")
	var anchor := {
		"id": id if id != null and str(id) != "" else "light_%d" % _uid,
		"pos": DAU.v3(pos),
		"color": DAU.color(o.get("color") if o.get("color") != null else "#FFC98A"),
		"intensity": float(o.get("intensity") if o.get("intensity") != null else 6.0),
		"distance": float(o.get("distance") if o.get("distance") != null else 10.0),
		"area": o.get("area"),
		"flicker": float(o.get("flicker") if o.get("flicker") != null else 0.0),
		"enabled": true,
		"cur": 0.0,          # eased intensity (setAnchor transitions)
		"boost": 0.0, "boostT": 0.0,  # temporary flicker()
		"seed": Rng.hash1(_uid * 7.3) * 100.0,
		"flash": false,
		"_score": 0.0,
	}
	anchor.cur = anchor.intensity
	# keep any extra keys of the descriptor (JS spreads them into the call, e.g. lightAnchors' fields are ignored)
	anchors[anchor.id] = anchor
	return anchor

func setAnchor(id, o: Dictionary = {}) -> void:
	var a = anchors.get(id)
	if a == null:
		return
	if o.has("color") and o.color != null:
		a.color = DAU.color(o.color)
	if o.has("intensity") and o.intensity != null:
		a.intensity = float(o.intensity)
	if o.has("enabled") and o.enabled != null:
		a.enabled = bool(o.enabled)
	if o.has("flicker") and o.flicker != null:
		a.flicker = float(o.flicker)

func removeAnchor(id) -> void:
	var a = anchors.get(id)
	if a == null:
		return
	anchors.erase(id)
	for slot in pool:
		if slot.hasNext and slot.next == a:
			slot.next = null
		if slot.anchor == a and not slot.hasNext:
			slot.next = null
			slot.hasNext = true

func flicker(id, amount := 0.8, seconds := 0.6) -> void:
	var a = anchors.get(id)
	if a == null:
		return
	a.boost = amount
	a.boostT = seconds

# Transient light (muzzle flashes, explosions): grabs a pool slot right away, fades over `seconds`.
func flash(pos, color = "#FFD08A", intensity := 8.0, seconds := 0.08, distance := 8.0) -> Dictionary:
	var a := addAnchor({"pos": pos, "color": color, "intensity": intensity, "distance": distance})
	a.flash = true
	a.ttl = seconds
	a.life = seconds
	_pendingFlash.append(a)
	return a

func update(dt: float) -> void:
	_t += dt
	_updateAmbient(dt)
	_updateKey()
	_updateFlashes(dt)
	_reassignT -= dt
	if _reassignT <= 0.0:
		_reassignT = REASSIGN
		_reassign()
	_updateSlots(dt)

func _currentArea():
	var g = game
	var level = g.level
	if level == null or level.get("areas") == null:
		return null
	var id = null
	if g.player != null and g.player.get("area"):
		id = g.player.area
	elif level.has_method("areaAt"):
		id = level.areaAt(g.camera.global_position.x, g.camera.global_position.z)
	if id == null or not id:
		return null
	var areas = level.areas
	return areas.get(id) if areas is Dictionary else null

static func _lerpC(a: Color, b: Color, k: float) -> Color:
	return Color(a.r + (b.r - a.r) * k, a.g + (b.g - a.g) * k, a.b + (b.b - a.b) * k, 1.0)

func _updateAmbient(dt: float) -> void:
	var area = _currentArea()
	var powered := true
	if game.machines != null:
		var pw = game.machines.get("powerOn")
		powered = pw == true or ((pw is int or pw is float) and pw != 0)
	# Before Sign-On: the area's emergency-power ambient (layout ambientPre), else the post ambient x0.6.
	var pre = area.get("ambientPre") if (not powered and area != null) else null
	var amb = pre if pre else (area.get("ambient") if area != null and area.get("ambient") else DEFAULT_AMBIENT)
	var scale := 1.0 if (powered or pre) else PRE_POWER
	var k := 1.0 - exp(-dt * 2.5)
	var A := _ambient
	A.sky = _lerpC(A.sky, DAU.color(amb.sky), k)
	A.ground = _lerpC(A.ground, DAU.color(amb.ground), k)
	var ai: float = float(amb.intensity) if amb.get("intensity") != null else 0.8
	A.intensity += (ai * scale - A.intensity) * k
	hemi.color = A.sky
	hemi.groundColor = A.ground
	hemi.intensity = A.intensity * HEMI_SCALE
	key.light_energy = KEY.powered if powered else KEY.dark
	if game.mats != null:
		game.mats.uniforms.uRimAmbient.value = clampf(0.45 + A.intensity * 0.65, 0.5, 1.2)

	var fog = area.get("fog") if area != null else null
	var F := _fog
	F.color = _lerpC(F.color, DAU.color(fog.color if fog else "#150F1C"), k)
	F.near += ((float(fog.near) if fog else 1000.0) - F.near) * k
	F.far += ((float(fog.far) if fog else 2000.0) - F.far) * k
	if game.render != null:
		var sf: Dictionary = game.render.fog
		sf.color = F.color
		sf.near = F.near
		sf.far = F.far

func _updateKey() -> void:
	var g = game
	var focus: Vector3
	if g.player != null and g.player.get("pos") != null:
		focus = DAU.v3(g.player.pos)
	else:
		focus = g.camera.global_position if g.camera.is_inside_tree() else g.camera.position
	var d := keyDir
	var texel := SHADOW_SIZE / 2048.0
	# Snap the focus to shadow-map texels in light space (stable shadows while moving).
	var right := Vector3(0, 0, 1).cross(d).normalized()
	var up := d.cross(right).normalized()
	var r := floorf(focus.dot(right) / texel + 0.5) * texel
	var u := floorf(focus.dot(up) / texel + 0.5) * texel
	var f := focus.dot(d)
	var v := right * r + up * u + d * f
	_aim(key, v + d * 30.0, v)

func _updateFlashes(dt: float) -> void:
	for a in _pendingFlash:
		var best = pool[0]
		var bestScore := INF
		for slot in pool:
			var score: float
			if slot.anchor == null:
				score = -1.0
			elif slot.anchor.flash:
				score = 1e9 - float(slot.anchor.ttl)
			else:
				score = slot.level * float(slot.anchor.cur)
			if score < bestScore:
				bestScore = score
				best = slot
		best.anchor = a
		best.next = null
		best.hasNext = false
		best.level = 1.0
		_place(best)
	_pendingFlash.clear()
	for id in anchors.keys():
		var a: Dictionary = anchors[id]
		if not a.flash:
			continue
		a.ttl -= dt
		if a.ttl <= 0.0:
			anchors.erase(id)
			for slot in pool:
				if slot.anchor == a:
					slot.anchor = null
					slot.level = 0.0

func _reassign() -> void:
	var cam: Vector3 = game.camera.global_position if game.camera.is_inside_tree() else game.camera.position
	var area = _currentArea()
	var areaId = area.get("id") if area != null else null
	var adj: Array = area.get("adjacent") if area != null and area.get("adjacent") is Array else []
	var list: Array = []
	for a in anchors.values():
		if a.flash or (not a.enabled and a.cur < 0.01) or a.intensity <= 0.0:
			continue
		var d2: float = a.pos.distance_squared_to(cam)
		var reach: float = a.distance + 18.0
		if d2 > reach * reach:
			continue
		var w := 1.0
		if areaId != null and a.area != null and a.area != areaId:
			w = 2.5 if adj.has(a.area) else 9.0
		a._score = d2 * w
		list.append(a)
	list.sort_custom(func(x, y): return x._score < y._score)
	var flashes := 0
	for s in pool:
		if s.anchor != null and s.anchor.flash:
			flashes += 1
	var free := POOL - flashes
	var desired := list.slice(0, maxi(0, free))
	var taken: Array = []
	for slot in pool:
		if slot.anchor != null and (slot.anchor.flash or desired.has(slot.anchor)):
			taken.append(slot.anchor)
			if slot.hasNext and not slot.anchor.flash:
				slot.hasNext = false
				slot.next = null
	var pending := desired.filter(func(a): return not taken.has(a))
	for slot in pool:
		if pending.is_empty():
			break
		if slot.anchor != null and taken.has(slot.anchor):
			continue
		var a = pending.pop_front()
		if slot.anchor == null or slot.level <= 0.01:
			slot.anchor = a
			slot.next = null
			slot.hasNext = false
			slot.level = 0.0
			_place(slot)
		else:
			slot.next = a
			slot.hasNext = true
	for slot in pool:
		if slot.anchor != null and not taken.has(slot.anchor) and not slot.hasNext:
			slot.next = null
			slot.hasNext = true

func _place(slot: Dictionary) -> void:
	var a = slot.anchor
	if a == null:
		return
	var l: OmniLight3D = slot.light
	l.position = a.pos
	l.light_color = a.color
	l.omni_range = a.distance

func _updateSlots(dt: float) -> void:
	var t := _t
	for a in anchors.values():
		var target: float = a.intensity if a.enabled else 0.0
		a.cur += (target - a.cur) * (1.0 - exp(-dt * 10.0))
		if a.boostT > 0.0:
			a.boostT -= dt
	for slot in pool:
		if slot.hasNext:
			slot.level -= dt / FADE_OUT
			if slot.level <= 0.0:
				slot.level = 0.0
				slot.anchor = slot.next
				slot.next = null
				slot.hasNext = false
				_place(slot)
		elif slot.anchor != null:
			slot.level = minf(1.0, slot.level + dt / FADE_IN)
		var a = slot.anchor
		var l: OmniLight3D = slot.light
		if a == null:
			l.light_energy = 0.0
			l.visible = false
			continue
		var k: float
		if a.flash:
			k = pow(maxf(0.0, a.ttl / a.life), 2.0) * a.intensity
		else:
			k = a.cur
		var f: float = a.flicker + (a.boost if a.boostT > 0.0 else 0.0)
		if f > 0.0:
			var buzz := 0.5 + 0.5 * Rng.noise1(t * 14.0 + a.seed)
			var drop := 0.7 if Rng.hash1(floorf(t * 18.0) + a.seed) > 0.86 else 0.0
			k *= 1.0 - minf(1.0, f) * minf(1.0, buzz * 0.5 + drop)
		l.light_color = a.color
		l.light_energy = k * slot.level
		l.visible = l.light_energy > 0.0
