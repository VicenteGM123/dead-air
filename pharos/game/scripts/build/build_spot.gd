class_name BuildSpot
extends Node3D
## A fixed place where one kind of building can stand. Hold Interact during the day to pay coins one by one;
## when the price is met the building rises (or levels up).

signal built(spot: BuildSpot)

const PAY_RATE := 7.0 # coins per second (accelerates while held)

var type := ""
var ring := 1
var lane := -1
var yaw := 0.0
var building: Building = null
var paid := 0
var _pay_t := 0.0
var _hold_t := 0.0
var _marker: MeshInstance3D
var _revealed := false
var _reveal_k := 0.0
var _seed := 1
var _denied_t := 0.0


func setup(data: Dictionary, seed_value: int) -> void:
	type = data["type"]
	ring = data["ring"]
	lane = data["lane"]
	yaw = data["yaw"]
	_seed = seed_value


func _ready() -> void:
	rotation.y = yaw
	_marker = MeshInstance3D.new()
	_marker.mesh = ModelsBuildings.spot_marker(type, _seed)
	_marker.material_override = Materials.lowpoly()
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_marker)
	Interactables.add(self)
	Game.pharos_level_changed.connect(_on_pharos_level)
	_update_visibility(true)


func _exit_tree() -> void:
	Interactables.remove(self)


func level() -> int:
	return building.level if building else 0


func is_unlocked() -> bool:
	return ring <= Game.pharos_level


func _on_pharos_level(_lv: int) -> void:
	_update_visibility(false)


func _update_visibility(instant: bool) -> void:
	var show := is_unlocked()
	if show and not _revealed:
		_revealed = true
		_reveal_k = 1.0 if instant else 0.0
		if not instant and Game.fx:
			Game.fx.ring(global_position, 2.5, Color(1.0, 0.85, 0.5, 0.8), 0.6)
	visible = show
	_marker.visible = show and building == null


func cost() -> int:
	var next := level() + 1
	if next > Data.max_level(type):
		return -1
	return int(Data.building_level(type, next)["cost"])


func is_maxed() -> bool:
	return cost() < 0


# --- interactable ------------------------------------------------------------------------------------------

func can_interact(_hero: Node) -> bool:
	if not is_unlocked() or is_maxed():
		return false
	if Game.phase != Game.Phase.DAY:
		return false
	if building and not building.alive:
		return false
	return true


func interact_position() -> Vector3:
	return global_position


func interact_range() -> float:
	var r := 3.0
	match type:
		"pharos":
			r = 5.2
		"farm":
			r = 4.5
		"dock":
			r = 3.2
	# The building pushes Fanós out (Obstacles): always reachable from its edge, whatever the model size.
	if building and type != "wall" and type != "dock":
		r = maxf(r, building.footprint * 0.85 + 1.2)
	return r


func interact_info() -> Dictionary:
	var next := level() + 1
	var lv := Data.building_level(type, next)
	var name_s: String = Data.BUILDINGS[type]["name"]
	var verb := "Construir" if level() == 0 else "Mejorar"
	if type == "pharos":
		verb = "Avivar la llama"
	var title := name_s if level() == 0 else "%s · nivel %d" % [name_s, next]
	return {
		"title": title, "verb": verb, "desc": lv["desc"], "cost": cost(), "paid": paid,
		"afford": Game.coins + paid >= cost(), "progress": float(paid) / maxf(1.0, float(cost())),
		"denied": _denied_t > 0.0, "anchor": global_position + Vector3(0, _prompt_height(), 0),
	}


func _prompt_height() -> float:
	if building:
		return minf(building.height + 1.2, 7.0)
	return 2.4


func interact_hold(delta: float, hero: Node) -> void:
	var c := cost()
	if c < 0:
		return
	_hold_t += delta
	if paid >= c:
		_complete()
		return
	if Game.coins <= 0:
		if _denied_t <= 0.0:
			Sfx.play("ui_back", global_position, -4.0)
		_denied_t = 0.5
		return
	_pay_t -= delta * (1.0 + minf(_hold_t, 2.0) * 0.8)
	if _pay_t <= 0.0:
		_pay_t = 1.0 / PAY_RATE
		if Game.spend(1):
			paid += 1
			Sfx.play("coin", global_position, -6.0, 0.9 + 0.25 * float(paid) / float(c))
			if Game.fx:
				Game.fx.coin_fly(hero.global_position + Vector3(0, 1.6, 0), global_position + Vector3(0, 0.6, 0))
			if paid >= c:
				_complete()


func interact_release(_hero: Node) -> void:
	_hold_t = 0.0
	_pay_t = 0.0


func _complete() -> void:
	paid = 0
	_hold_t = 0.0
	if building == null:
		building = BuildingsSpecial.create(type)
		building.setup(type, 1, self, _seed)
		building.lane = lane
		add_child(building)
		Game.stats["built"] += 1
		Sfx.play("build_done", global_position)
		Game.say(Data.BUILDINGS[type]["name"], "construida" if type != "pharos" else "", "build")
	else:
		building.upgrade()
		Sfx.play("upgrade", global_position)
		if type == "pharos":
			Game.say("La llama crece", "La luz del faro alcanza nuevos solares", "build")
	_marker.visible = false
	Game.shake(0.12)
	if Game.fx:
		Game.fx.ring(global_position, maxf(2.0, building.footprint + 0.5), Color(1.0, 0.9, 0.6, 0.8), 0.5)
	built.emit(self)


## Place a building directly (start of game / tests).
func force_build(lv: int) -> void:
	lv = mini(lv, Data.max_level(type))
	if building == null:
		building = BuildingsSpecial.create(type)
		building.setup(type, lv, self, _seed)
		building.lane = lane
		add_child(building)
	elif building.level < lv:
		while building.level < lv:
			building.upgrade()
	_marker.visible = false


func _process(delta: float) -> void:
	if _denied_t > 0.0:
		_denied_t -= delta
	if _reveal_k < 1.0:
		_reveal_k = minf(1.0, _reveal_k + delta * 1.5)
		_marker.scale = Vector3.ONE * Rig.ease_out(_reveal_k)
