extends "res://scripts/main.gd"
## The slice played from the title to the boat (ENCOUNTERS merge): the real game (scripts/main.gd: the island, the
## wolves and boars, the lion's encounter, the UI) plus, with `ptbot=1`, the playthrough bot (tools/playthrough_bot.gd):
##   godot --headless --path . res://tools/playthrough.tscn --fixed-fps 60 --quit-after 300000 -- ptbot=1 quit=1
## The bot lives under the tree's root, not in this scene: it outlasts the scene's reload when the boat's teaser ends
## in the title (the UI's to_title()), so it can check the title came back. It takes `ptbot` out of Game.args before
## that reload (the reloaded scene adds no second bot). Without ptbot this is just the game (title first).

func _ready() -> void:
	super._ready()
	if Game.has_arg("ptbot") and ResourceLoader.exists("res://tools/playthrough_bot.gd"):
		var b: Node = load("res://tools/playthrough_bot.gd").new()
		b.name = "PlaythroughBot"
		b.set("main", self)
		get_tree().root.add_child.call_deferred(b)
