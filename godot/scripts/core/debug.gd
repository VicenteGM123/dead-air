# Debug / test API (port of src/core/debug.js; ARCHITECTURE §11): game.debug (window.__game.debug in the web build).
#   teleport(x, z, yaw?), look(yaw, pitch), mouseDelta(dx, dy), god(bool), addPoints(n), setRound(n), power(bool),
#   openAllDoors(), give(weaponId, upgraded?), perk(perkId), spawn(typeId, x?, z?), killAll(), freeze(bool),
#   shotCam(camIdOrPos|null, target?) (named 'cam_*' anchor or explicit [x,y,z]/Vector3 + target; hides the HUD;
#   null restores), freeCam(bool) (fly with WASD, Q/E down/up, Shift fast, mouse look), state() (JSON
#   snapshot), egg(step), showCard(cardId) (a CRT 1.8 m in front of the player showing that gfx card through
#   game.screens group 'scr_preview'; false for unknown ids).
# shot=<camId> (launch param) places the shot camera at boot and freezes gameplay (art screenshots).
# Renames (SPEC §3.2): none.
extends RefCounted

var game
var active = null  # null | 'shot' | 'free'
var _yaw := 0.0
var _pitch := 0.0
var _card: MeshInstance3D = null
var _look := {"yaw": 0.0, "pitch": 0.0}

func _init(g) -> void:
	game = g

func init() -> void:
	var g = game
	if g.params.get("shot"):
		g.events.once("game:start", func(_p) -> void:
			shotCam(str(g.params.shot))
			g.time.scale = 0.0
			freeze(true))

func _vec(v) -> Variant:
	if v == null:
		return null
	return DAU.v3(v)

func teleport(x: float, z: float, yaw = null) -> Variant:
	game.player.teleport(x, z, yaw)
	return state().player

func look(yaw: float, pitch: float = 0.0) -> void:
	var p = game.player
	p.yaw = yaw
	p.pitch = pitch

func mouseDelta(dx: float, dy: float) -> void:
	game.input.injectMouse(dx, dy)

func god(on = true) -> void:
	game.player.god = bool(on)

func addPoints(n) -> Variant:
	game.economy.add(n, "debug")
	return game.economy.points

func setRound(n: int) -> void:
	game.rounds.startRound(n)

func power(on = true) -> void:
	game.machines.setPower(bool(on))

func openAllDoors() -> void:
	game.level.openAllDoors()

func give(weaponId: String, upgraded: bool = false) -> Variant:
	return game.weapons.give(weaponId, {"upgraded": upgraded})

func perk(perkId: String) -> Variant:
	return game.perks.give(perkId)

func spawn(typeId: String = "tuned_in", x = null, z = null) -> Variant:
	var g = game
	var pos = null
	if x != null and z != null:
		var f: float = g.level.col.floorAt(float(x), float(z), 50.0)
		pos = Vector3(float(x), f if f > -INF else 0.0, float(z))
	var zz = g.zombies.spawn(typeId, null, pos)
	return zz.id if zz != null else null

func killAll() -> void:
	game.zombies.killAll("debug")

func freeze(on = true) -> void:
	game.zombies.freezeAll(bool(on))

func shotCam(camIdOrPos, target = null) -> bool:
	var g = game
	if camIdOrPos == null or (camIdOrPos is bool and camIdOrPos == false):
		_release()
		return true
	var pos: Vector3
	var lookAt: Vector3
	if camIdOrPos is String or camIdOrPos is StringName:
		var a = g.level.anchors.get(camIdOrPos) if g.level != null else null
		if a == null:
			push_warning("[debug] unknown shot camera '%s'" % camIdOrPos)
			return false
		pos = DAU.v3(a.pos)
		var ry: float = float(a.get("rotY")) if a.get("rotY") else 0.0
		lookAt = DAU.v3(a.target) if a.get("target") != null else pos + Vector3(-sin(ry), 0.0, -cos(ry))
	else:
		pos = _vec(camIdOrPos)
		var t = _vec(target)
		lookAt = t if t != null else pos + Vector3(0.0, 0.0, -1.0)
	_take("shot")
	var cam: Camera3D = g.camera
	cam.position = pos
	_lookAt(cam, lookAt)
	return true

# Object3D.lookAt for a camera: -Z towards the target, +Y up.
static func _lookAt(cam: Node3D, target: Vector3) -> void:
	var d := target - cam.position
	if d.length_squared() < 1e-12:
		return
	var up := Vector3.UP
	if absf(d.normalized().dot(up)) > 0.9999:
		up = Vector3(0.0, 0.0, 1.0)
	cam.transform = Transform3D(Basis.looking_at(d, up), cam.position)

func freeCam(on = true) -> void:
	var g = game
	if not on:
		_release()
		return
	_take("free")
	if g.camera == null:
		return
	var _v: Vector3 = -g.camera.transform.basis.z
	_yaw = atan2(-_v.x, -_v.z)
	_pitch = asin(clampf(_v.y, -1.0, 1.0))

func _take(mode: String) -> void:
	var g = game
	active = mode
	if g.cam != null:
		g.cam.enabled = false
	if g.player != null:
		g.player.controlLocked = true
	if g.hud != null and g.hud.has_method("hide"):
		g.hud.hide()

func _release() -> void:
	var g = game
	if active == null:
		return
	active = null
	if g.cam != null:
		g.cam.enabled = true
	if g.player != null:
		g.player.controlLocked = false
	if g.hud != null and g.hud.has_method("show"):
		g.hud.show()

func showCard(id: String) -> bool:
	var g = game
	if g.cards == null or not g.cards.ids().has(id):
		return false
	if _card == null:
		_card = MeshInstance3D.new()
		_card.rotation_order = EULER_ORDER_XYZ
		if g.mats != null and g.mats.has_method("screenGeometry"):
			_card.mesh = g.mats.screenGeometry(1.2, 0.9)
		if g.mats != null and g.mats.has_method("screen"):
			_card.material_override = g.mats.screen(null, {"w": 1.2, "h": 0.9})
		_card.name = "debug_card"
		g.scene.add_child(_card)
		if g.screens != null:
			g.screens.register(_card, "scr_preview", {"id": "debug_card"})
	var info = g.cards.info(id)
	var w: float = info.w
	var h: float = info.h
	var p = g.player
	var _v: Vector3 = p.forward()
	_v.y = 0.0
	_v = _v.normalized()
	_card.scale = Vector3(1.0, (h / w) / 0.75, 1.0)
	_card.position = p.pos + _v * 1.8
	_card.position.y = p.pos.y + 1.5
	# Object3D.lookAt for a non-camera object: +Z towards the target
	var d: Vector3 = Vector3(p.pos.x, p.pos.y + 1.5, p.pos.z) - _card.position
	if d.length_squared() > 1e-12:
		_card.quaternion = Basis.looking_at(d, Vector3.UP, true).get_rotation_quaternion()
	if g.screens != null:
		g.screens.setSource("scr_preview", id)
	return true

func egg(step) -> Variant:
	var e = game.egg
	if e.has_method("setStep"):
		e.setStep(step)
	else:
		e.step = step
	return e.step

func state() -> Dictionary:
	var g = game
	var p = g.player
	var cam: Camera3D = g.camera
	var slots: Array = []
	if g.weapons != null:
		for s in g.weapons.slots:
			slots.append({"id": s.get("id"), "upgraded": s.get("upgraded"), "mag": s.get("mag"), "reserve": s.get("reserve")})
	return {
		"state": g.state,
		"player": {"pos": [p.pos.x, p.pos.y, p.pos.z], "yaw": p.yaw, "pitch": p.pitch, "health": p.health, "maxHealth": p.maxHealth,
			"area": p.area, "grounded": p.grounded, "sprinting": p.sprinting, "ads": p.ads, "stamina": p.stamina, "heroId": p.heroId, "alive": p.alive},
		"round": g.rounds.round if g.rounds != null else null,
		"points": g.economy.points if g.economy != null else null,
		"zombies": g.zombies.alive.size() if g.zombies != null else null,
		"perks": g.perks.list.duplicate() if g.perks != null else [],
		"weapons": slots,
		"power": g.machines.powerOn if g.machines != null else null,
		"egg": g.egg.step if g.egg != null else null,
		"camera": {"pos": [cam.position.x, cam.position.y, cam.position.z] if cam != null else null, "fov": cam.fov if cam != null else null,
			"side": g.cam.side if g.cam != null else null},
		"interact": g.interact.current.id if g.interact != null and g.interact.current != null else null,
	}

# Runs every frame (real dt) in every state.
func update(dt: float) -> void:
	if active != "free":
		return
	var g = game
	var input = g.input
	var cam: Camera3D = g.camera
	if cam == null or input == null:
		return
	var d: Dictionary = input.lookDelta(_look)
	_yaw += d.yaw
	_pitch = clampf(_pitch + d.pitch, -1.5, 1.5)
	var q := Quaternion.from_euler(Vector3(_pitch, _yaw, 0.0))  # 'YXZ'
	cam.quaternion = q
	var speed := (18.0 if input.key("ShiftLeft") else 6.0) * dt
	var _v := Vector3((1.0 if input.key("KeyD") else 0.0) - (1.0 if input.key("KeyA") else 0.0), (1.0 if input.key("KeyE") else 0.0) - (1.0 if input.key("KeyQ") else 0.0),
		(1.0 if input.key("KeyS") else 0.0) - (1.0 if input.key("KeyW") else 0.0))
	if _v.length_squared() > 0.0:
		cam.position += q * (_v.normalized() * speed)
