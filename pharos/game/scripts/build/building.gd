class_name Building
extends Unit
## A structure on a build spot. Destroyed buildings turn into rubble at night and are rebuilt for free at dawn.

signal destroyed(b: Building)

var type := ""
var level := 1
var spot: Node3D = null
var anchors := {}
var footprint := 2.0
var height := 3.0
var lane := -1
var lane_s := 0.0
var mesh_node: MeshInstance3D
var _rise := 1.0
var _shake := 0.0
var _hit_sfx_t := 0.0
var _smoke_t := 0.0
var _seed := 1


func setup(t: String, lv: int, at_spot: Node3D, seed_value: int) -> void:
	type = t
	level = lv
	spot = at_spot
	_seed = seed_value
	team = 0
	is_building = true
	display_name = Data.BUILDINGS[t]["name"]


func _ready() -> void:
	mesh_node = MeshInstance3D.new()
	mesh_node.material_override = Materials.lowpoly()
	add_child(mesh_node)
	_apply_model(true)


func _apply_model(animate: bool) -> void:
	var d := ModelsBuildings.building(type, level, _seed)
	mesh_node.mesh = d["mesh"]
	if d.has("material"):
		mesh_node.material_override = d["material"]
	anchors = d.get("anchors", {})
	footprint = d.get("footprint", 2.0)
	height = d.get("height", 3.0)
	radius = footprint
	var lv := Data.building_level(type, level)
	var old_max := max_hp
	max_hp = float(lv["hp"]) * Game.building_hp_mult(type)
	hp = max_hp if animate or old_max <= 0.0 else hp + (max_hp - old_max)
	Obstacles.remove_owner(self)
	_add_obstacles()
	if animate:
		_rise = 0.0
	_on_model_changed()


func _on_model_changed() -> void:
	pass


## What keeps units out of the building (a disc; walls override it with a line, docks stand on the water).
func _add_obstacles() -> void:
	if type != "wall" and type != "dock":
		Obstacles.add(global_position, footprint * 0.85, self)


func refresh_max_hp() -> void:
	var lv := Data.building_level(type, level)
	var r := hp_ratio()
	max_hp = float(lv["hp"]) * Game.building_hp_mult(type)
	hp = max_hp * r


func upgrade() -> void:
	level += 1
	_apply_model(true)
	Game.stats["upgrades"] += 1


func anchor(n: String, default: Vector3 = Vector3.ZERO) -> Vector3:
	return global_transform * anchors.get(n, default)


func income() -> int:
	if not alive:
		return 0
	var lv := Data.building_level(type, level)
	return int(lv.get("income", 0)) + Game.income_bonus(type)


func _process(delta: float) -> void:
	if _rise < 1.0:
		_rise = minf(1.0, _rise + delta * 1.6)
		var k := Rig.ease_out(_rise)
		mesh_node.position.y = -height * 0.6 * (1.0 - k)
		mesh_node.scale = Vector3(1.0 + 0.06 * sin(k * PI), 1.0, 1.0 + 0.06 * sin(k * PI))
		if Game.fx and fmod(_rise, 0.25) < delta * 1.6:
			Game.fx.dust(global_position + Vector3(randf_range(-footprint, footprint), 0, randf_range(-footprint, footprint)) * 0.6, 3, 0.8)
		if _rise >= 1.0:
			mesh_node.position.y = 0.0
			mesh_node.scale = Vector3.ONE
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 4.0)
		mesh_node.position.x = sin(_shake * 90.0) * 0.06 * _shake
	if _hit_sfx_t > 0.0:
		_hit_sfx_t -= delta
	if alive and hp < max_hp * 0.45 and Game.fx:
		_smoke_t -= delta
		if _smoke_t <= 0.0:
			_smoke_t = 0.35
			Game.fx.smoke(global_position + Vector3(randf_range(-0.6, 0.6), height * 0.7, randf_range(-0.6, 0.6)), 1)


func _on_hurt(_amount: float, _from: Node3D, _kind: String) -> void:
	_shake = 1.0
	if _hit_sfx_t <= 0.0:
		_hit_sfx_t = 0.25
		Sfx.play("structure_hit", global_position, -4.0, randf_range(0.9, 1.1))


func _on_death() -> void:
	Sfx.play("structure_break", global_position)
	Obstacles.remove_owner(self)
	mesh_node.mesh = ModelsBuildings.rubble(footprint, _seed, 8.0 if type == "wall" else 0.0)
	mesh_node.position = Vector3.ZERO
	if Game.fx:
		Game.fx.dust(global_position, 14, footprint)
		Game.fx.smoke(global_position + Vector3(0, 1.0, 0), 6)
	Game.shake(0.25)
	destroyed.emit(self)


## Dawn: rebuild for free.
func restore() -> void:
	if alive:
		hp = max_hp
		return
	alive = true
	_apply_model(true)
	hp = max_hp
	Game.register(self, team)
	_on_restored()


func _on_restored() -> void:
	pass


func repair_full() -> void:
	hp = max_hp
