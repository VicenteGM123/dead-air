extends "res://scripts/main.gd"
## ENCOUNTERS (lane P) test scene: the real game on Nemea (scripts/main.gd: the World, the hero, the wolves and boars
## of World.spawn_groups()) with no title, plus the encounter bot (tools/encounter_bot.gd) when `encbot=` is given:
##   godot --path . res://tools/encounters.tscn --fixed-fps 60 -- encbot=all quit=1      (docs/ENCOUNTERS.md)
## Without encbot it is just the game straight into play (handy for renders: `-- noui=1 start=x,y,z face=deg`).

func _ready() -> void:
	super._ready()
	if Game.has_arg("encbot") and ResourceLoader.exists("res://tools/encounter_bot.gd"):
		var b: Node = load("res://tools/encounter_bot.gd").new()
		b.name = "EncounterBot"
		b.set("main", self)
		add_child(b)


func _wants_title() -> bool:
	return false
