extends "res://scripts/main.gd"
## FX lane demo on the island: the driver of tools/fx_demo.gd (the arena) on the real ground, to see the trails, the
## cut flashes and the slams over grass and sand under the game's own light. Needs `dummies=1` (the straw posts in
## front of the hero) and `enemies=0`; `start=` / `face=` choose where (the wolves' clearing is grass):
##   timeout 900 xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 --resolution 1280x720 \
##     --write-movie <dir>/f.png --fixed-fps 30 --quit-after 400 res://tools/fx_demo_world.tscn -- play=1 noui=1 \
##     enemies=0 dummies=1 start=-24,0,14 face=0 demo=combo,slamw,beach,slamw quit=1

const Demo := preload("res://tools/fx_demo.gd")


func spawn_encounters() -> void:
	super.spawn_encounters()
	var d = Demo.Driver.new()
	d.name = "FxDemo"
	d.arena = self
	add_child(d)
