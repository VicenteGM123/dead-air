class_name Altar
extends StaticBody3D
## Altar of Zeus: the checkpoint. Interact (E / pad Y) to pray: heals the hero to full and makes this altar the
## place the hero comes back to after a fall (Game.checkpoint). A marble block with a bronze fire bowl whose
## flame flickers; its prompt is "Rezar".
## Interactable (scripts/core/interactables.gd) with interact_press(). Collision: world layer 1.

signal used(hero: Node)

var title := "Altar de Zeus"
var _flame: MeshInstance3D
var _halo: MeshInstance3D
var _t := 0.0
var _pulse := 0.0


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	add_to_group("altar")
	_build()
	Interactables.add(self)


func _exit_tree() -> void:
	Interactables.remove(self)


func _build() -> void:
	var mb := MeshBuilder.new(41)
	mb.vary = 0.02
	# Two marble steps (the lower one sunk into the ground so slopes never show a gap), the altar block, a cornice.
	mb.block(Vector3(0, -0.6, 0), Vector3(2.8, 0.75, 2.2), Pal.MARBLE_SHADE, Pal.MARBLE)
	mb.block(Vector3(0, 0.15, 0), Vector3(2.2, 0.2, 1.7), Pal.MARBLE_SHADE, Pal.MARBLE)
	mb.block(Vector3(0, 0.35, 0), Vector3(1.6, 0.75, 1.15), Pal.MARBLE, Pal.MARBLE)
	# A red meander band round the block.
	mb.block(Vector3(0, 0.88, 0), Vector3(1.64, 0.1, 1.19), Pal.TERRACOTTA)
	mb.block(Vector3(0, 1.1, 0), Vector3(1.85, 0.16, 1.4), Pal.LIMESTONE, Pal.MARBLE)
	# Bronze fire bowl on a short foot, with glowing embers (vertex alpha 0.5 = self-lit).
	mb.cyl(Vector3(0, 1.26, 0), 0.1, 0.2, 0.16, 10, Pal.BRONZE_DARK)
	mb.cyl(Vector3(0, 1.36, 0), 0.2, 0.18, 0.46, 12, Pal.BRONZE, true, 0.0, Color(1.0, 0.5, 0.22, 0.5))
	mb.ring(Vector3(0, 1.54, 0), 0.5, 0.42, 0.05, 14, Pal.BRONZE_DARK)
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit()
	mi.material_override = Materials.lowpoly()
	add_child(mi)
	# The flame: a self-lit twisted cone and an additive halo.
	var fb := MeshBuilder.new(43)
	fb.cyl(Vector3.ZERO, 0.75, 0.3, 0.0, 6, Color(1.0, 0.62, 0.25, 0.5))
	fb.cyl(Vector3(0, 0.02, 0), 0.5, 0.17, 0.0, 5, Color(1.0, 0.92, 0.6, 0.5), true, 0.5)
	_flame = MeshInstance3D.new()
	_flame.mesh = fb.commit()
	_flame.material_override = Materials.lowpoly()
	_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flame.position = Vector3(0, 1.5, 0)
	add_child(_flame)
	_halo = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(2.2, 2.2)
	_halo.mesh = qm
	_halo.material_override = Materials.glow_add()
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_halo.position = Vector3(0, 1.85, 0)
	add_child(_halo)
	Materials.set_param(_halo, &"tint_color", Vector3(1.0, 0.7, 0.35))
	Materials.set_param(_halo, &"intensity", 0.55)
	var base := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.2, 0.95, 1.7)
	base.shape = bs
	base.position = Vector3(0, -0.22, 0)
	add_child(base)
	var top := CollisionShape3D.new()
	var ts := BoxShape3D.new()
	ts.size = Vector3(1.85, 1.35, 1.4)
	top.shape = ts
	top.position = Vector3(0, 0.62, 0)
	add_child(top)


func _process(delta: float) -> void:
	_t += delta
	_pulse = maxf(0.0, _pulse - delta * 1.5)
	var f := 1.0 + sin(_t * 9.0) * 0.06 + sin(_t * 14.3 + 1.0) * 0.04 + _pulse * 0.5
	_flame.scale = Vector3(1.0 + sin(_t * 7.0) * 0.05, f, 1.0 + cos(_t * 6.0) * 0.05)
	_flame.rotation.y = _t * 1.3
	Materials.set_param(_halo, &"intensity", 0.5 + 0.08 * sin(_t * 5.0) + _pulse)


# --- interactable --------------------------------------------------------------------------------------------

func can_interact(hero: Node) -> bool:
	return Game.phase == Game.Phase.PLAY and hero != null and (not hero.has_method("is_alive") or hero.is_alive())


func interact_position() -> Vector3:
	return global_position


func interact_range() -> float:
	return 2.6


func interact_info() -> Dictionary:
	return {"title": title, "verb": "Rezar", "desc": "Cura y guarda el camino", "progress": -1.0,
		"anchor": global_position + Vector3(0, 2.6, 0)}


func interact_press(hero: Node) -> void:
	if hero.has_method("heal"):
		hero.call("heal", 99999.0)
	Game.checkpoint = self
	_pulse = 1.0
	Sfx.play("blessing", global_position)
	if Game.fx:
		Game.fx.call("motes", global_position + Vector3(0, 1.8, 0), 14, Color(1.0, 0.8, 0.45))
	Game.say(title, "Has recuperado fuerzas. Si caes, volverás aquí.", "altar")
	used.emit(hero)


## Where a hero who fell comes back: 2.4 m in front of the altar (+Z), facing it.
func respawn_transform() -> Transform3D:
	var p := global_transform * Vector3(0, 0, 2.4)
	if Game.world:
		p = Game.world.ground(p)
	return Transform3D(Basis(Vector3.UP, global_rotation.y), p)
