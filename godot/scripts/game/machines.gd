# Machines aggregator (port of src/game/machines.js; ARCHITECTURE §3/§10).
# Constructs the machine sub-systems and exposes them as game.screens, game.signon, game.telly, game.sponsors,
# game.uplink (each loaded from res://scripts/game/<name>.gd when that file exists: telly/sponsors/uplink are ported
# by other agents). Game drives each sub-system's lifecycle (init/reset/update/lateUpdate) as its own isolated system
# right after `machines`; Machines must not call those methods itself.
# powerOn is the single power flag. setPower(on) switches it: the pre-power grade of every toon material
# (mats.uniforms.uSatEnv 0.70 -> 1.0, uAmber 0.08 -> 0, GDD §3.3), opens the doors with requiresPower and emits
# power:on {}. reset() restores the unpowered station (game params power=1 is applied by Game after reset).
# Machine events (GDD §18.15) are emitted by the sub-systems: machine:sign_on, machine:telly_*,
# machine:commercial_start/end, machine:dish_aligned, machine:uplink_*, machine:boss_*, machine:screen_override.
#
# Global uniforms: JS writes game.mats.uniforms.<name>.value. Here _setU() writes the same entry (Dictionary
# {value} or object with .value) when materials.gd exposes `uniforms`, calls mats.setUniform(name, v) when it has
# one, and also sets the Godot global shader parameter of that name when the project declares it.
extends RefCounted

const PRE_POWER := {"sat": 0.7, "amber": 0.08}
const SUBSYSTEMS := [
	["screens", "res://scripts/game/screens.gd"],
	["signon", "res://scripts/game/signon.gd"],
	["telly", "res://scripts/game/telly.gd"],
	["sponsors", "res://scripts/game/sponsors.gd"],
	["uplink", "res://scripts/game/uplink.gd"],
]

var game
var powerOn := false
var screens
var signon
var telly
var sponsors
var uplink

func _init(g) -> void:
	game = g
	powerOn = false
	for entry in SUBSYSTEMS:
		var sys = _make(entry[0], entry[1])
		set(entry[0], sys)
		game.set(entry[0], sys)

func _make(name: String, path: String):
	if not ResourceLoader.exists(path):
		push_warning("[machines] sub-system '%s' missing (%s)" % [name, path])
		return null
	var script = load(path)
	if script == null or not script.can_instantiate():
		push_error("[machines] sub-system '%s' failed to load (%s)" % [name, path])
		return null
	return script.new(game)

func reset() -> void:
	powerOn = false
	_grade(false)

func setPower(on: bool) -> void:
	var g = game
	if powerOn == on:
		return
	powerOn = on
	_grade(on)
	if not on:
		return
	var lv = g.level
	var doors = lv.get("doors") if lv != null else null
	if doors is Dictionary:
		for id in doors.keys():
			var d = doors[id]
			if d != null and d.get("requiresPower"):
				lv.openDoor(id)
	g.events.emit("power:on", {})

func _grade(on: bool) -> void:
	_setU("uSatEnv", 1.0 if on else PRE_POWER.sat)
	_setU("uAmber", 0.0 if on else PRE_POWER.amber)
	_setU("uWaveRadius", -1.0)

# game.mats.uniforms[name].value = v (see the header).
func _setU(name: String, v) -> void:
	var M = game.mats
	if M != null:
		if M.has_method("setUniform"):
			M.setUniform(name, v)
		else:
			var U = M.get("uniforms")
			if U is Dictionary and U.has(name):
				var u = U[name]
				if u is Dictionary:
					u["value"] = v
				elif u is Object:
					u.set("value", v)
	if RenderingServer.global_shader_parameter_get_list().has(StringName(name)):
		RenderingServer.global_shader_parameter_set(name, v)
