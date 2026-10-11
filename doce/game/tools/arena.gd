extends "res://scripts/main.gd"
## Combat test arena: the same game (hero, camera, toon screen, sea, golden light) on a stone platform by the sea
## (tools/arena_world.gd: training ground, a ledge ring, two rings across a sea gap, a doorway and the boulder, a
## pillar row, ramps) with three straw posts, a sparring post, two straw sacks (light chain targets) and the beast
## dummy (a straw bull: chain kind beast, stunned against a pillar, then wrestled), and two straw soldiers that die
## (a full combo; a new one stands up 3.5 s later). No title.
##   godot --path . res://tools/arena.tscn          (or the game with scene=arena; on the web ?dev=1&scene=arena)
## Debug args work as in the game (tod=..., cam=fly pos=... yaw=... pitch=..., noui=1), plus:
##   autotest=1          the bot (tools/arena_bot.gd) runs every test and prints "ARENA test <name> PASS|FAIL"
##                       and "ARENA autotest passed=N/M result=PASS|FAIL"
##   bot=<a,b,...>       only those tests (combo, heavy, guard, parry, dodge, lockon, light, ledge, rings, beast,
##                       boulder); `show=1` slows the bot down to watch it; frames are logged for strip renders

const ArenaWorld := preload("res://tools/arena_world.gd")
const ArenaBeast := preload("res://tools/arena_beast.gd")
const ArenaBot := preload("res://tools/arena_bot.gd")

## The straw posts (kept for older tools: `dummies`).
var dummies: Array = []
var sparring: TrainingDummy
var sacks: Array = []
## The straw soldiers (they die; replaced 3.5 s later at the same spot).
var straw: Array = []
var beast: Enemy
var bot: Node = null


func _make_world() -> Node3D:
	var w: Node3D = ArenaWorld.new()
	w.name = "ArenaWorld"
	add_child(w)
	w.call("build", 1)
	return w


## The arena is a training ground, not the lion's cave: no labour card when the hero stands by its centre (the UI
## shows it on reaching World.cave().arena_center, which the arena's world answers too).
func _make_ui() -> void:
	super._make_ui()
	if ui != null and "auto_labor_card" in ui:
		ui.set("auto_labor_card", false)


func _wants_title() -> bool:
	return false


func spawn_encounters() -> void:
	var s: Dictionary = world.call("spots")
	var posts: Array = s["posts"]
	for i in posts.size():
		var d := TrainingDummy.new()
		d.name = "Dummy_%d" % i
		add_child(d)
		d.teleport(world.ground(posts[i]), PI if i != 1 else PI) # facing the hero's start (south)
		dummies.append(d)
	sparring = TrainingDummy.new(&"sparring")
	sparring.name = "Sparring"
	add_child(sparring)
	sparring.teleport(world.ground(s["sparring"]), PI)
	for i in (s["sacks"] as Array).size():
		var k := TrainingDummy.new(&"sack")
		k.name = "Sack_%d" % i
		add_child(k)
		k.teleport(world.ground(s["sacks"][i]), PI * 0.5)
		sacks.append(k)
	for i in (s["straw"] as Array).size():
		_spawn_straw(i)
	beast = ArenaBeast.new()
	beast.name = "Beast"
	add_child(beast)
	beast.teleport(world.ground(s["beast"]), 0.0) # facing north, towards the pillars
	if Game.arg_on("autotest") or Game.has_arg("bot"):
		bot = ArenaBot.new()
		bot.name = "ArenaBot"
		bot.set("arena", self)
		add_child(bot)


func _spawn_straw(i: int) -> void:
	var s: Dictionary = world.call("spots")
	var m := TrainingDummy.new(&"straw")
	m.name = "Straw_%d" % i
	add_child(m)
	m.teleport(world.ground(s["straw"][i]), PI)
	while straw.size() <= i:
		straw.append(null)
	straw[i] = m
	m.died.connect(func(_e: Enemy) -> void: _respawn_straw(i))


func _respawn_straw(i: int) -> void:
	await get_tree().create_timer(3.5, false).timeout
	if is_inside_tree():
		_spawn_straw(i)
