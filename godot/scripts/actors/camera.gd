# Third-person over-the-shoulder camera, PvZ Garden Warfare style (port of src/actors/camera.js; ARCHITECTURE §9,
# GDD §3.7/§16).
# Pivot at head height; offset 0.75 m right, 0.35 m up, 3.4 m back, FOV 70. ADS (hold RMB): 1.6 m back,
# 0.55 m right, FOV 52 in 0.12 s. C swaps the shoulder (critically damped, no snap). +4 deg FOV while sprinting.
# The crosshair is the exact screen center (the camera looks along the player's yaw/pitch; the hero sits left of
# center).
# Collision: a 0.25 m sphere is swept from the pivot along the boom against ARCHITECTURE only (collider tags in
# ARCH: walls, glass, doors, boarded windows, the ground, platforms, fence, tower lattice). Props (desks, chairs,
# pedestal cameras, globes, machines...) never pull the camera: their small boxes made the probe hit and miss on
# alternate frames, and the snap-in / ease-out sawtooth read as a rapid left/right shake. The collision limit snaps
# in at once (never see through a wall), holds for HOLD s after the last pull-in, then eases back out
# (EASE_OUT time constant, at most MAX_OUT m/s). The limit is separate from the boom length, so ADS in/out
# stays instant. CEILINGS count as walls (ceilingClamp): the boom stops CEIL_GAP under the ceiling of the room it
# is in (pivot and boom end), so aiming down in the 3.5-4 m rooms keeps the camera inside instead of on the roof
# (the gravel roof used to fill the whole screen, hiding the hero).
# OCCLUSION (cam.occ, see materials.gd / render.gd): whatever stands between the camera and the hero dither-fades
# (screen door) instead of hiding the hero. Walls never do: they pull the camera in (above), so they are never in
# front of the hero. Two parts, both limited to what is closer to the camera than the hero and above its feet:
#   - a see-through window: an ellipse around the hero's projected silhouette (feet to head, shoulder width),
#     always on while this camera drives the view (nothing else is ever in front of the hero there);
#   - whole-object fades: collision boxes the camera ignores (props, machines, rails, the tower lattice; never
#     walls / glass / doors / windows / floors) crossed by the lines from the lens to the hero (head, chest, hips,
#     shoulders) or by the view rays right in front of the lens (< OCC_NEAR: the lobby letter board when the
#     camera backs against the south wall), up to OCC_BOXES at a time, each ramping in over OCC_IN s and out over
#     OCC_OUT s after OCC_HOLD s without a hit (no flicker when a line grazes an edge).
#   Actors never fade (zombies, the boss: mats.noOcclusion on spawn), nor does the hero (hero-fade materials).
#   Nothing inside the walls / doors / windows / glass / fences / platforms nearest the camera (occ.walls, up to 4)
#   ever fades: the window's soft rim can reach a wall beside a hero standing close to the camera, and a prop box
#   can touch a wall.
#   occ = { amt, cx, cy, rx, ry (NDC ellipse, three.js NDC: x right, y up, -1..1), zFull, zSoft (view depths),
#           feetY, boxes: [{ min: Vector3, max: Vector3, level }], n, walls: [{ min, max, level: 1, d }], nw,
#           cam: [px, py, pz, qx, qy, qz, qw, fov, aspect] (the camera state it was computed for) },
#   occValid(camera) = computed for that camera exactly as it is now (render.gd skips it otherwise).
# API: shake(amount 0..1 trauma, duration=0.4; >= 0.18 also rumbles the gamepad via input.shakeRumble), kick(pitch,
# yaw=0) (recoil: shifts the aim, recovers at 8 deg/s, plus a quick visual punch), heroDistance (m, for the hero
# fade), enabled (debug cameras turn it off), fovBase (options, 60..90), side (+1 right shoulder / -1 left), occ,
# occValid(camera), occlusion (bool, default true: false turns the fade off), ceilingClamp (bool, default true).
# Godot notes: game.camera is a Camera3D whose parent has an identity transform (render.gd), so camera.position /
# quaternion are world values like the JS; Camera3D.fov is vertical (keep_height) like THREE's. The projection
# (THREE Vector3.project / unproject) is computed from fov and the viewport aspect (the symmetric perspective THREE
# builds). Collision boxes are keyed by their index in col.boxes (the JS Map keyed the box objects).
# Renames (SPEC §3.2): none.
# MP (online co-op; nothing below runs in solo): `target` / spectate(player-like | null) — the camera follows that
#   player (a RemotePlayer: pos, yaw, pitch, rig, ads, sprinting, downed are read like the local player's) instead of
#   game.player; switching snaps the boom (no glide across the map). A DOWNED followed player gets the low, woozy
#   down camera (pivot -0.62 m, shorter boom, slight roll sway, FOV -4, blended over DOWN_TIME). Remote avatars never
#   occlusion-fade (mats.noOcclusion on their models, re-applied every second for new held weapons).
extends RefCounted

const HIP := {"right": 0.75, "up": 0.35, "back": 3.4, "fov": 70.0}
const ADS := {"right": 0.55, "up": 0.3, "back": 1.6, "fov": 52.0}
const ADS_TIME := 0.12
const SPRINT_FOV := 4.0
const PROBE_R := 0.25
const MIN_DIST := 0.15
const SKIN := 0.02
const MAX_BOOM := 4.0     # collision limit when nothing is in the way (longer than any boom)
const HOLD := 0.25        # s the camera stays pulled in after the last pull-in (hysteresis)
const EASE_OUT := 0.25    # s time constant of the ease back out
const MAX_OUT := 1.2      # m/s cap on the ease-out (a long recovery glides instead of pumping, ~2 cm per frame)
const SIDE_TIME := 0.12   # s shoulder swap smoothing (critically damped)
const RECOVER := 8.0 * PI / 180.0
const CEIL_GAP := 0.3     # m the camera stays under a ceiling
# Collider tags that block the camera (collision.gd tag names; walls from shell.gd, platforms/stairs, doors,
# boarded window openings). Every other tag (prop, machine, telly, rail, ...) is ignored by the camera.
const ARCH := {"wall": true, "glass": true, "door": true, "window": true, "floor": true, "platform": true, "fence": true, "lattice": true}

# occlusion (see the header)
const OCC_MAX := 1.0          # strength of the see-through window (1: clear over the hero, dithered towards its rim)
const OCC_BOX_MAX := 0.9      # strongest whole-object fade: fraction of pixels dropped (14 of every 16 pixels)
const OCC_MARGIN := 0.45      # m closer than the hero's nearest point (head top, back...) where the fade is full ...
const OCC_SOFT := 0.3         # ... easing out over this range (nothing within 0.15 m of the hero fades: what it carries)
const OCC_FEET := 0.08        # m above the feet: floors, rugs and decals below never fade
const OCC_W := 0.45           # m half width of the hero silhouette (with the gun)
const OCC_ELL := 1.3          # ellipse radii / projected half extents (the fade is full inside ~0.6 of the radii)
const OCC_NEAR := 0.75        # m: a box the view rays cross this close to the lens fades whole
const OCC_IN := 0.12          # s fade in (a box, the whole effect)
const OCC_OUT := 0.3          # s fade out
const OCC_HOLD := 0.2         # s a box keeps fading after its last hit
const OCC_BOXES := 4          # boxes faded at once (materials uOccBox0/1)
const OCC_PAD := 0.05         # m the faded region extends past the collision box (plus a 0.15 m soft edge)
const OCC_SKIP := {"wall": true, "glass": true, "door": true, "window": true, "floor": true, "platform": true} # never faded whole
const OCC_KEEP := {"wall": true, "glass": true, "door": true, "window": true, "platform": true, "fence": true}  # protected (floors: feetY)
const OCC_WALLS := 4          # protected boxes (materials uOccWall0/1)
const OCC_RAYS := [[0.0, 0.0], [0.6, 0.55], [-0.6, 0.55], [0.6, -0.55], [-0.6, -0.55], [0.0, -0.7]] # NDC view rays
# MP down camera (see the header)
const DOWN := {"right": 0.5, "up": 0.15, "back": 2.4, "drop": 0.62, "fov": -4.0}
const DOWN_TIME := 0.35

var game
var camera: Camera3D
var enabled := true
var side := 1
var fovBase: float = HIP.fov
var heroDistance := 3.0
var _side := 1.0
var _sideVel := 0.0
var _ads := 0.0
var _sprintFov := 0.0
var _dist: float = HIP.back
var _clip := MAX_BOOM  # smoothed collision limit (m along the boom)
var _holdT := 0.0
var _pivotY = null
var _trauma := 0.0
var _traumaDecay := 2.5
var _kickP := 0.0
var _kickY := 0.0
var _punch
var _t := 0.0
var ceilingClamp := true
var occlusion := true
var occ := {}
var _occState := {}  # collision box index -> { box, level, hold, hit }
var _occList: Array = []
# this frame's pivot and boom direction (module scratch vectors in the JS, shared with _ceiling / _occlusion)
var _pivot := Vector3.ZERO
var _dir := Vector3.ZERO
# Engine-side speed-up (same results): the box tags / camera / ramp flags never change after a box is added, so the
# per-frame loops only visit the boxes those static flags let through (indices into col.boxes, in box order);
# `enabled` and every other test still run per frame. Rebuilt when col.boxes is another array or grows.
var _boxesRef = null
var _boxesN := -1
var _archIdx := PackedInt32Array()   # sphereCast candidates: camera-blocking architecture, not ramps
var _keepIdx := PackedInt32Array()   # OCC_KEEP tags (protected boxes)
var _fadeIdx := PackedInt32Array()   # whole-object fade candidates (not ramps, not OCC_SKIP, not camera architecture)
var _bb := PackedFloat64Array()      # box bounds (minX, minY, minZ, maxX, maxY, maxZ) per box index (boxes never move)
# MP
var target = null                    # followed player-like (spectating), null = game.player
var _downK := 0.0
var _noOccT := 0.0

func _init(g) -> void:
	game = g
	camera = g.camera
	_punch = Rig.Spring.new(300.0, 20.0)
	var boxes: Array = []
	for i in OCC_BOXES:
		boxes.append({"min": Vector3.ZERO, "max": Vector3.ZERO, "level": 0.0})
	var walls: Array = []
	for i in OCC_WALLS:
		walls.append({"min": Vector3.ZERO, "max": Vector3.ZERO, "level": 1.0, "d": 0.0})
	occ = {
		"amt": 0.0, "cx": 0.0, "cy": 0.0, "rx": 0.0, "ry": 0.0, "zFull": 0.0, "zSoft": OCC_SOFT, "feetY": 0.0, "n": 0,
		"boxes": boxes, "walls": walls, "nw": 0,
		"cam": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],  # camera position, quaternion, fov, aspect it was computed for (occValid)
	}
	# actors never fade (materials noOcclusion): every spawned zombie, the boss when its fight starts
	var ev = g.events
	if ev != null:
		ev.on("zombie:spawn", func(e) -> void:
			if e is Dictionary and e.get("z") != null and game.mats != null and game.mats.has_method("noOcclusion"):
				game.mats.noOcclusion(e.z.group))
		ev.on("machine:boss_start", func(_e) -> void:
			if game.boss != null and game.mats != null and game.mats.has_method("noOcclusion"):
				game.mats.noOcclusion(game.boss.root))

# Viewport aspect of a camera (THREE camera.aspect).
static func aspectOf(cam: Camera3D) -> float:
	if cam != null and cam.is_inside_tree():
		var vp := cam.get_viewport()
		if vp != null:
			var s := vp.get_visible_rect().size
			if s.y > 0.0:
				return s.x / s.y
	return 16.0 / 9.0

# cam.occ was computed for `camera` exactly as it is now (render.gd calls it before the main render).
func occValid(cam: Camera3D) -> bool:
	var s: Array = occ.cam
	var p := cam.position
	var q := cam.quaternion
	return s[0] == p.x and s[1] == p.y and s[2] == p.z and s[3] == q.x and s[4] == q.y and s[5] == q.z and s[6] == q.w \
		and s[7] == cam.fov and s[8] == aspectOf(cam)

func reset() -> void:
	side = 1
	_side = 1.0
	_sideVel = 0.0
	_ads = 0.0
	_trauma = 0.0
	_kickP = 0.0
	_kickY = 0.0
	_punch.reset()
	_pivotY = null
	_dist = HIP.back
	_clip = MAX_BOOM
	_holdT = 0.0
	_occState.clear()
	occ.n = 0
	occ.amt = 0.0
	target = null
	_downK = 0.0

# MP: follow another player (spectating) or the local player again (null). Snaps the boom to the new player.
func spectate(t) -> void:
	if is_same(t, target):
		return
	target = t
	_pivotY = null
	_clip = MAX_BOOM
	_holdT = 0.0
	_occState.clear()

# The followed player: the spectated one while it is still a live object, else the local player.
func _follow(g):
	if target != null and target is Object and is_instance_valid(target) and target.get("pos") is Vector3:
		return target
	target = null
	return g.player

func shake(amount: float = 0.3, duration: float = 0.4) -> void:
	_trauma = minf(1.0, _trauma + amount)
	_traumaDecay = 1.0 / maxf(0.05, duration)
	if game.input != null and game.input.has_method("shakeRumble"):
		game.input.shakeRumble(amount, duration)  # big shakes rumble the Xbox pad (input.gd)

func kick(pitch: float = 0.02, yaw: float = 0.0) -> void:
	_kickP += pitch
	_kickY += yaw
	_punch.kick(pitch * 30.0)

func update(dt: float) -> void:
	var g = game
	var p = g.player if target == null else _follow(g)
	_t += dt
	if g.input != null and g.input.pressed("shoulder"):
		side = -side
	if camera == null:
		camera = g.camera
	# MP: remote avatars never occlusion-fade (their held weapons change: re-applied every second)
	var n = g.get("net")
	if n != null and n.inGame:
		_noOccT -= dt
		if _noOccT <= 0.0:
			_noOccT = 1.0
			if g.mats != null and g.mats.has_method("noOcclusion"):
				for rp in n.remotes():
					if rp.model != null:
						g.mats.noOcclusion(rp.model)
	if not enabled or p == null or camera == null:
		occ.amt = 0.0
		return

	# Blend factors. Shoulder: critically damped spring (smooth start and stop, no overshoot).
	if true:
		var w := 2.0 / SIDE_TIME
		var x := w * dt
		var e := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
		var change := _side - side
		var tmp := (_sideVel + w * change) * dt
		_sideVel = (_sideVel - w * tmp) * e
		_side = side + (change + tmp) * e
	var adsSpeed: float = float(p.mods.adsSpeed) if p.get("mods") != null else 1.0
	var adsRate := dt / ADS_TIME * adsSpeed
	_ads = clampf(_ads + (adsRate if p.ads else -adsRate), 0.0, 1.0)
	var a := _ads * _ads * (3.0 - 2.0 * _ads)
	_sprintFov += ((SPRINT_FOV if p.sprinting else 0.0) - _sprintFov) * (1.0 - exp(-dt * 6.0))
	# MP: the down camera blend of a downed followed player (always 0 in solo)
	var dw := 1.0 if p.downed else 0.0
	if _downK != dw:
		_downK = clampf(_downK + (dt / DOWN_TIME if dw > _downK else -dt / DOWN_TIME), 0.0, 1.0)
	var dk := _downK * _downK * (3.0 - 2.0 * _downK) if _downK > 0.0 else 0.0

	# Recoil recovery (aim-affecting) and the visual punch.
	_kickP = signf(_kickP) * maxf(0.0, absf(_kickP) - RECOVER * dt)
	_kickY = signf(_kickY) * maxf(0.0, absf(_kickY) - RECOVER * dt)
	var punch: float = _punch.update(dt, 0.0)

	# Pivot at head height; vertical steps are smoothed, horizontal follow is exact (responsive aim).
	var headH := 1.5
	if p.rig != null:
		var dims = p.rig.dims
		headH = float(dims.height) - float(dims.headH) * 0.55
	if dk > 0.0:
		headH -= DOWN.drop * dk
	var ty: float = p.pos.y + headH
	_pivotY = ty if _pivotY == null else float(_pivotY) + (ty - float(_pivotY)) * (1.0 - exp(-dt * 14.0))
	_pivot = Vector3(p.pos.x, float(_pivotY), p.pos.z)

	var yaw: float = p.yaw + _kickY
	var pitch := clampf(p.pitch + _kickP, -1.35, 1.25)
	var _q := Quaternion.from_euler(Vector3(pitch + punch * 0.02, yaw, 0.0))  # Euler 'YXZ'
	if dk > 0.0:
		_q = Quaternion.from_euler(Vector3(pitch + punch * 0.02, yaw, sin(_t * 0.9) * 0.035 * dk))

	var right := lerpf(HIP.right, ADS.right, a) * _side
	var up := lerpf(HIP.up, ADS.up, a)
	var back := lerpf(HIP.back, ADS.back, a)
	if dk > 0.0:
		right = lerpf(right, DOWN.right * _side, dk)
		up = lerpf(up, DOWN.up, dk)
		back = lerpf(back, DOWN.back, dk)
	var _offset := _q * Vector3(right, up, back)
	var want := _offset.length()
	_dir = _offset / want

	# Collision: sweep a 0.25 m sphere from the pivot along the boom against architecture only. The limit
	# snaps in, holds HOLD s after the last pull-in, then eases out; the boom itself (ADS blend) stays exact.
	var col = g.level.get("col") if g.level != null else null
	var hit := INF
	if col != null:
		_prepBoxes(col.boxes)
		hit = _sphereCastFast(col.boxes, _pivot, _dir, want, PROBE_R)
	if ceilingClamp and _dir.y > 1e-3:
		hit = minf(hit, _ceiling(g, want))
	var free := MAX_BOOM if hit == INF else maxf(MIN_DIST, hit - SKIN)
	if free < _clip - 1e-3:
		_clip = free
		_holdT = HOLD
	elif _holdT > 0.0:
		_holdT -= dt
	else:
		_clip += minf((free - _clip) * (1.0 - exp(-dt / EASE_OUT)), MAX_OUT * dt)
	_dist = minf(want, _clip)

	var cam := camera
	var cpos := _pivot + _dir * _dist
	var cq := _q

	# Trauma shake (squared falloff, smooth noise).
	_trauma = maxf(0.0, _trauma - _traumaDecay * dt)
	var s := _trauma * _trauma
	if s > 0.0:
		var t := _t * 22.0
		cpos.x += Rng.noise1(t) * 0.12 * s
		cpos.y += Rng.noise1(t + 31.7) * 0.1 * s
		var e := Vector3(Rng.noise1(t + 71.3) * 0.03 * s, Rng.noise1(t + 11.1) * 0.03 * s, Rng.noise1(t + 53.9) * 0.05 * s)
		cq = cq * Quaternion.from_euler(e)
	cam.transform = Transform3D(Basis(cq), cpos)

	var fov := lerpf(fovBase, ADS.fov + (fovBase - HIP.fov) * 0.5, a) + _sprintFov
	if dk > 0.0:
		fov += DOWN.fov * dk
	if absf(cam.fov - fov) > 1e-3:
		cam.fov = fov
	heroDistance = cam.position.distance_to(_pivot)
	_occlusion(dt, p, cam, col)

# Boom length at which the camera reaches CEIL_GAP under the lowest ceiling of the rooms at the pivot and at the
# boom end (INF: no ceiling there, e.g. the yard). _pivot / _dir are this frame's.
func _ceiling(g, want: float) -> float:
	var lv = g.level
	if lv == null or lv.get("areas") == null or not lv.has_method("areaAt"):
		return INF
	var ceil := INF
	for i in 2:
		var t := want if i == 1 else 0.0
		var id = lv.areaAt(_pivot.x + _dir.x * t, _pivot.z + _dir.z * t)
		var ar = lv.areas.get(id) if id != null and id != "" else null
		if ar != null and ar.get("ceilY") != null and float(ar.ceilY) < ceil:
			ceil = float(ar.ceilY)
	# no ceiling above the hero (or the hero above it: debug teleports onto the roof)
	if ceil == INF or _pivot.y > ceil - CEIL_GAP:
		return INF
	return (ceil - CEIL_GAP - _pivot.y) / _dir.y + SKIN

# Entry distance of the segment o + d * t, t in [0, len] (d unit), into box b, or -1 when it misses. 0 when o is
# inside the box.
static func segBox(b, o: Vector3, d: Vector3, len: float) -> float:
	return _segBoxF(b.minX, b.minY, b.minZ, b.maxX, b.maxY, b.maxZ, o, d, len)

static func _segBoxF(minX: float, minY: float, minZ: float, maxX: float, maxY: float, maxZ: float, o: Vector3, d: Vector3, len: float) -> float:
	var t0 := 0.0
	var t1 := len
	for ax in 3:
		var oa: float = o[ax]
		var da: float = d[ax]
		var lo: float = minX if ax == 0 else (minY if ax == 1 else minZ)
		var hi: float = maxX if ax == 0 else (maxY if ax == 1 else maxZ)
		if absf(da) < 1e-9:
			if oa < lo or oa > hi:
				return -1.0
			continue
		var ta := (lo - oa) / da
		var tb := (hi - oa) / da
		if ta > tb:
			var tt := ta
			ta = tb
			tb = tt
		if ta > t0:
			t0 = ta
		if tb < t1:
			t1 = tb
		if t0 > t1:
			return -1.0
	return t0

# Distance along the unit dir d from o at which a sphere of radius r first touches an enabled, camera-blocking
# architecture box (box expanded by r: square corners, slightly conservative), or INF within max.
# Boxes already containing o are skipped (the probe may leave a volume), like collision.raycast.
# ~285 boxes in the whole station: a flat loop with an AABB reject is cheaper than the hash here.
static func sphereCast(boxes: Array, o: Vector3, d: Vector3, max_: float, r: float) -> float:
	var ex := o.x + d.x * max_
	var ey := o.y + d.y * max_
	var ez := o.z + d.z * max_
	var sx0 := minf(o.x, ex) - r
	var sx1 := maxf(o.x, ex) + r
	var sy0 := minf(o.y, ey) - r
	var sy1 := maxf(o.y, ey) + r
	var sz0 := minf(o.z, ez) - r
	var sz1 := maxf(o.z, ez) + r
	var best := max_
	var hit := false
	for b in boxes:
		if not b.enabled or not b.camera or b.ramp or not ARCH.has(b.tag):
			continue
		if b.maxX < sx0 or b.minX > sx1 or b.maxY < sy0 or b.minY > sy1 or b.maxZ < sz0 or b.minZ > sz1:
			continue
		var x0: float = b.minX - r
		var x1: float = b.maxX + r
		var y0: float = b.minY - r
		var y1: float = b.maxY + r
		var z0: float = b.minZ - r
		var z1: float = b.maxZ + r
		if o.x > x0 and o.x < x1 and o.y > y0 and o.y < y1 and o.z > z0 and o.z < z1:
			continue
		var t0 := 0.0
		var t1 := best
		var ok := true
		for ax in 3:
			if not ok:
				break
			var oa: float = o[ax]
			var da: float = d[ax]
			var lo: float = x0 if ax == 0 else (y0 if ax == 1 else z0)
			var hi: float = x1 if ax == 0 else (y1 if ax == 1 else z1)
			if absf(da) < 1e-9:
				ok = oa >= lo and oa <= hi
				continue
			var ta := (lo - oa) / da
			var tb := (hi - oa) / da
			if ta > tb:
				var tt := ta
				ta = tb
				tb = tt
			if ta > t0:
				t0 = ta
			if tb < t1:
				t1 = tb
			ok = t0 <= t1
		if ok and t0 < best:
			best = t0
			hit = true
	return best if hit else INF

# sphereCast over the static candidates (_archIdx, bounds from _bb): the same maths and results.
func _sphereCastFast(boxes: Array, o: Vector3, d: Vector3, max_: float, r: float) -> float:
	var ex := o.x + d.x * max_
	var ey := o.y + d.y * max_
	var ez := o.z + d.z * max_
	var sx0 := minf(o.x, ex) - r
	var sx1 := maxf(o.x, ex) + r
	var sy0 := minf(o.y, ey) - r
	var sy1 := maxf(o.y, ey) + r
	var sz0 := minf(o.z, ez) - r
	var sz1 := maxf(o.z, ez) + r
	var best := max_
	var hit := false
	var bb := _bb
	for i in _archIdx:
		var k := i * 6
		if bb[k + 3] < sx0 or bb[k] > sx1 or bb[k + 4] < sy0 or bb[k + 1] > sy1 or bb[k + 5] < sz0 or bb[k + 2] > sz1:
			continue
		if not boxes[i].enabled:
			continue
		var x0: float = bb[k] - r
		var x1: float = bb[k + 3] + r
		var y0: float = bb[k + 1] - r
		var y1: float = bb[k + 4] + r
		var z0: float = bb[k + 2] - r
		var z1: float = bb[k + 5] + r
		if o.x > x0 and o.x < x1 and o.y > y0 and o.y < y1 and o.z > z0 and o.z < z1:
			continue
		var t0 := 0.0
		var t1 := best
		var ok := true
		for ax in 3:
			if not ok:
				break
			var oa: float = o[ax]
			var da: float = d[ax]
			var lo: float = x0 if ax == 0 else (y0 if ax == 1 else z0)
			var hi: float = x1 if ax == 0 else (y1 if ax == 1 else z1)
			if absf(da) < 1e-9:
				ok = oa >= lo and oa <= hi
				continue
			var ta := (lo - oa) / da
			var tb := (hi - oa) / da
			if ta > tb:
				var tt := ta
				ta = tb
				tb = tt
			if ta > t0:
				t0 = ta
			if tb < t1:
				t1 = tb
			ok = t0 <= t1
		if ok and t0 < best:
			best = t0
			hit = true
	return best if hit else INF

# Static candidate lists (see _archIdx). A box whose flags would pass none of the loops is skipped for good.
func _prepBoxes(boxes: Array) -> void:
	if is_same(boxes, _boxesRef) and boxes.size() == _boxesN:
		return
	_boxesRef = boxes
	_boxesN = boxes.size()
	_archIdx.clear()
	_keepIdx.clear()
	_fadeIdx.clear()
	_bb.resize(boxes.size() * 6)
	for i in boxes.size():
		var b = boxes[i]
		_bb[i * 6] = b.minX
		_bb[i * 6 + 1] = b.minY
		_bb[i * 6 + 2] = b.minZ
		_bb[i * 6 + 3] = b.maxX
		_bb[i * 6 + 4] = b.maxY
		_bb[i * 6 + 5] = b.maxZ
		if b.camera and not b.ramp and ARCH.has(b.tag):
			_archIdx.append(i)
		if OCC_KEEP.has(b.tag):
			_keepIdx.append(i)
		elif not b.ramp and not OCC_SKIP.has(b.tag) and not (b.camera and ARCH.has(b.tag)):
			_fadeIdx.append(i)

# Keeps the OCC_WALLS protected boxes nearest the lens in occ.walls (insertion by distance).
func _occWall(o: Dictionary, b, d: float) -> void:
	var W: Array = o.walls
	var i: int
	if o.nw < OCC_WALLS:
		i = o.nw
		o.nw += 1
	else:
		i = OCC_WALLS
	if i == OCC_WALLS:
		if d >= W[OCC_WALLS - 1].d:
			return
		i = OCC_WALLS - 1
	var slot: Dictionary = W[i]
	while i > 0 and W[i - 1].d > d:
		W[i] = W[i - 1]
		i -= 1
	W[i] = slot
	slot.d = d
	slot.min = Vector3(b.minX - OCC_PAD, b.minY - OCC_PAD, b.minZ - OCC_PAD)
	slot.max = Vector3(b.maxX + OCC_PAD, b.maxY + OCC_PAD, b.maxZ + OCC_PAD)

# cam.occ for this frame (see the header). The camera transform is this frame's.
func _occlusion(dt: float, p, cam: Camera3D, col) -> void:
	var o := occ
	var on := occlusion != false
	o.amt = minf(OCC_MAX, o.amt + dt * OCC_MAX / OCC_IN) if on else maxf(0.0, o.amt - dt * OCC_MAX / OCC_OUT)
	var aspect := aspectOf(cam)
	var s: Array = o.cam
	var cq := cam.quaternion
	s[0] = cam.position.x; s[1] = cam.position.y; s[2] = cam.position.z
	s[3] = cq.x; s[4] = cq.y; s[5] = cq.z; s[6] = cq.w
	s[7] = cam.fov; s[8] = aspect
	if o.amt <= 0.0:
		o.n = 0
		o.nw = 0
		_occState.clear()
		return

	var C := cam.position
	var xf := cam.transform
	var _fwd := -xf.basis.z.normalized()
	var _right := xf.basis.x.normalized()
	var xfInv := xf.affine_inverse()
	var tanY := tan(deg_to_rad(cam.fov) * 0.5)
	var feet: float = p.pos.y
	var h: float
	if p.rig != null and p.rig.get("dims") != null:
		h = float(p.rig.dims.height)
	else:
		h = float(p.height) if p.height else 1.75
	o.feetY = feet + OCC_FEET
	# hero samples: head (pivot), chest, hips, both shoulders
	var _pts: Array = []
	_pts.append(_pivot)
	var chest := Vector3(p.pos.x, feet + h * 0.58, p.pos.z)
	_pts.append(chest)
	_pts.append(Vector3(p.pos.x, feet + h * 0.32, p.pos.z))
	_pts.append(chest + _right * (OCC_W * 0.55))
	_pts.append(chest + _right * (-OCC_W * 0.55))
	# depth of the hero's nearest point: the samples, the head top and the back (what it carries: the reel...)
	var heroZ := INF
	for q in _pts:
		heroZ = minf(heroZ, (q - C).dot(_fwd))
	heroZ = minf(heroZ, (Vector3(p.pos.x, feet + h + 0.05, p.pos.z) - C).dot(_fwd))
	var _v := Vector3(C.x - p.pos.x, 0.0, C.z - p.pos.z)
	if _v.length_squared() > 1e-6:
		_v = _v.normalized() * 0.25 + chest
		heroZ = minf(heroZ, (_v - C).dot(_fwd))
	o.zFull = heroZ - OCC_MARGIN
	o.zSoft = OCC_SOFT

	# see-through window: the hero's feet-to-head, shoulder-wide quad projected to NDC
	var x0 := INF
	var x1 := -INF
	var y0 := INF
	var y1 := -INF
	var ok := true
	for i in 4:
		_v = Vector3(p.pos.x, feet if i < 2 else feet + h + 0.08, p.pos.z) + _right * (OCC_W if (i & 1) else -OCC_W)
		var vz := (_v.x - C.x) * _fwd.x + (_v.y - C.y) * _fwd.y + (_v.z - C.z) * _fwd.z
		if vz < cam.near * 2.0:
			ok = false
			break
		var vv := xfInv * _v  # view space (camera looks down -z)
		var nx := (vv.x / -vv.z) / (tanY * aspect)
		var ny := (vv.y / -vv.z) / tanY
		x0 = minf(x0, nx)
		x1 = maxf(x1, nx)
		y0 = minf(y0, ny)
		y1 = maxf(y1, ny)
	if ok:
		o.cx = (x0 + x1) / 2.0
		o.cy = (y0 + y1) / 2.0
		o.rx = (x1 - x0) / 2.0 * OCC_ELL
		o.ry = (y1 - y0) / 2.0 * OCC_ELL
	else:
		o.rx = 0.0
		o.ry = 0.0

	# whole-object fades
	var st := _occState
	for k in st:
		st[k].hit = false
	var boxes = col.get("boxes") if col != null else null
	o.nw = 0
	if boxes != null:
		# view rays near the lens
		var _rays: Array = []
		for r in OCC_RAYS:
			_rays.append((xf.basis * Vector3(float(r[0]) * tanY * aspect, float(r[1]) * tanY, -1.0)).normalized())
		var ax0 := C.x - OCC_NEAR
		var ax1 := C.x + OCC_NEAR
		var ay0 := C.y - OCC_NEAR
		var ay1 := C.y + OCC_NEAR
		var az0 := C.z - OCC_NEAR
		var az1 := C.z + OCC_NEAR
		for q in _pts:
			ax0 = minf(ax0, q.x)
			ax1 = maxf(ax1, q.x)
			ay0 = minf(ay0, q.y)
			ay1 = maxf(ay1, q.y)
			az0 = minf(az0, q.z)
			az1 = maxf(az1, q.z)
		var reach := heroZ + 0.5  # protected boxes: only those that can be closer to the lens than the hero
		_prepBoxes(boxes)
		var bb := _bb
		for bi in _keepIdx:  # OCC_KEEP tags
			var k := bi * 6
			var dx := maxf(maxf(bb[k] - C.x, 0.0), C.x - bb[k + 3])
			var dy := maxf(maxf(bb[k + 1] - C.y, 0.0), C.y - bb[k + 4])
			var dz := maxf(maxf(bb[k + 2] - C.z, 0.0), C.z - bb[k + 5])
			var d := sqrt(dx * dx + dy * dy + dz * dz)
			if d < reach and boxes[bi].enabled:
				_occWall(o, boxes[bi], d)
		var feetLim: float = o.feetY + 0.1
		for bi in _fadeIdx:  # not ramps, not OCC_SKIP, not camera-blocking architecture
			var k := bi * 6
			var bx0: float = bb[k]
			var by0: float = bb[k + 1]
			var bz0: float = bb[k + 2]
			var bx1: float = bb[k + 3]
			var by1: float = bb[k + 4]
			var bz1: float = bb[k + 5]
			if bx1 < ax0 or bx0 > ax1 or by1 < ay0 or by0 > ay1 or bz1 < az0 or bz0 > az1:
				continue
			if by1 < feetLim:
				continue
			# around the hero (a volume it stands in), not between
			if chest.x > bx0 and chest.x < bx1 and chest.y > by0 and chest.y < by1 and chest.z > bz0 and chest.z < bz1:
				continue
			var b = boxes[bi]
			if not b.enabled:
				continue
			var hit := false
			for pi in _pts.size():
				if hit:
					break
				var dd: Vector3 = _pts[pi] - C
				var len := dd.length()
				if len < 0.35:
					continue
				dd /= len
				var t := _segBoxF(bx0, by0, bz0, bx1, by1, bz1, C, dd, len)
				hit = t >= 0.0 and t < len - 0.3
			for q in _rays.size():
				if hit:
					break
				hit = _segBoxF(bx0, by0, bz0, bx1, by1, bz1, C, _rays[q], OCC_NEAR) >= 0.0
			if not hit:
				continue
			var e = st.get(bi)
			if e == null:
				e = {"box": b, "level": 0.0, "hold": 0.0, "hit": false}
				st[bi] = e
			e.hit = true
	var list := _occList
	list.clear()
	for k in st.keys():
		var e: Dictionary = st[k]
		if e.hit:
			e.hold = OCC_HOLD
		else:
			e.hold -= dt
		e.level = minf(1.0, e.level + dt / OCC_IN) if e.hold > 0.0 else e.level - dt / OCC_OUT
		if e.level <= 0.0 and e.hold <= 0.0:
			st.erase(k)
			continue
		if e.level > 0.0:
			list.append(e)
	if list.size() > OCC_BOXES:
		list.sort_custom(func(l, r) -> bool: return l.level > r.level)
	o.n = mini(OCC_BOXES, list.size())
	for i in o.n:
		var e: Dictionary = list[i]
		var b = e.box
		var dst: Dictionary = o.boxes[i]
		dst.min = Vector3(b.minX - OCC_PAD, b.minY - OCC_PAD, b.minZ - OCC_PAD)
		dst.max = Vector3(b.maxX + OCC_PAD, b.maxY + OCC_PAD, b.maxZ + OCC_PAD)
		dst.level = e.level * OCC_BOX_MAX
