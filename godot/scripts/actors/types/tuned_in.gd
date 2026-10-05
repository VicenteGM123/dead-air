# TUNED-IN (`tuned_in`, the studio audience) type module — GDD §8.1. Port of src/actors/types/tuned_in.js.
# Contract: see the TYPE MODULE CONTRACT in scripts/actors/zombie_types.gd. The ZombieManager does the heavy lifting
# (window entry, flow-field chase, the two-arm swipe with T.zombies.tunedIn numbers, hit reactions, the topple +
# static dissolve death, head cork-pop); this module adds the model (sculpted variants z_crew / z_reporter / z_disco /
# z_mom when baked, pooled), the HP / speed rules and the Tuned-In flavour: formant groans at random, a louder chase
# groan when it first spots you, and a clap of the hands on every 4th step.
#
# Port notes: the JS module-level `clapBudget` / `clapT` live on this (single, registry-owned) module instance as
#   _clapBudget / _clapT (leading underscore: not merged into the def). Parameter `round` -> `r` (GDScript builtin).
#   Without baked art build() leaves z.group null and the manager's spawn fails (the placeholder is not ported).
# MP: puppet(game, z, dt) runs the same flavour on client puppets (zombies_net.gd).
extends RefCounted

const HEAR := 16.0        # m: groans/claps farther than this are skipped (the audio engine has a voice budget)

var _clapBudget := 0      # global limiter: claps per second across the crowd
var _clapT := 0.0

var id := "tuned_in"
var height := 1.62
var radius := 0.36
var dmg = Config.T.zombies.tunedIn.dmg
var range = Config.T.zombies.tunedIn.range
var windup = Config.T.zombies.tunedIn.windup
var cd = Config.T.zombies.tunedIn.cd
var spawnMode := "window"

func hp(r = 1, _game = null):
	return Rounds.zombieHp(maxi(1, int(r)))

# GDD §7.3 tier roll; Rounds applies the per-round 60 % super-sprint cap.
func speed(r = 1, game = null):
	var ro = game.rounds if game != null else null
	if ro != null and ro.has_method("rollTunedInSpeed"):
		return ro.rollTunedInSpeed()
	return Rounds.rollSpeed(maxi(1, int(r)), game.rand if game != null else func(): return randf())

func build(game, z: Dictionary) -> void:
	var av = z.get("artVariant")
	var m = ZombieTypes.acquireModel(game, "tuned_in", av if av != null else -1)
	if m == null:
		return
	z.model = m
	z.group = m.group
	z.rig = m.rig
	z.animator = m.animator
	z.head = m.head
	z.headR = m.headR
	z.hitZones = ZombieTypes.humanoidHitZones(m)
	var dims = ZombieTypes._f(m.rig, "dims") if m.rig != null else null
	var h: float = float(ZombieTypes._f(dims, "height", 1.62)) if dims != null else 1.62
	z.height = h
	# Crowd variety: a little size jitter per spawn (the manager keeps it in z.scale).
	z.scale = 0.94 + randf() * 0.12
	z.flags.groanT = 2.0 + randf() * 5.0
	z.flags.step = 0
	z.flags.lastPhase = 0
	z.flags.clapT = 0.0

func release(_game, z: Dictionary) -> void:
	ZombieTypes.releaseModel(z.model)
	z.model = null

# Flavour only: returns false so the manager steers and swipes.
func update(game, z: Dictionary, dt: float) -> bool:
	# perf: typed locals (same arithmetic, same order of randf() / audio calls)
	var f: Dictionary = z.flags
	var p = game.player
	var pp: Vector3 = p.pos
	var zp: Vector3 = z.pos
	var d := Vector2(pp.x - zp.x, pp.z - zp.z).length()
	# Global clap limiter (~3 per second).
	_clapT += dt
	if _clapT > 0.33:
		_clapT = 0.0
		_clapBudget = mini(1, _clapBudget + 1)

	var groanT: float = f.groanT - dt
	f.groanT = groanT
	if groanT <= 0.0:
		f.groanT = 3.0 + randf() * 5.0
		if d < HEAR:
			_play(game, "zmb_groan", {"pos": z.pos, "rate": 0.9 + randf() * 0.25, "vol": 0.8})
	# Spotted: the first time it gets line of sight within 12 m -> a louder chase groan.
	if not f.get("spotted", false) and z.los and d < 12.0:
		f.spotted = true
		_play(game, "zmb_groan_chase", {"pos": z.pos, "rate": 0.95 + randf() * 0.2})
		if z.animator is Object and z.animator.has_method("kick"):
			z.animator.kick(0.35)
	# Every 4th footstep (half gait cycle) the hands clap together.
	var an: Dictionary = z.anim
	var a = z.animator
	var ph = a.get("phase") if a is Object else null
	if ph is float or ph is int:
		var half := int(floorf(float(ph) / PI))
		if half != f.lastPhase:
			f.lastPhase = half
			if an.speed > 0.4:
				var step: int = f.step + 1
				f.step = step
				if step % 4 == 0:
					f.clapT = 0.22
					if d < HEAR * 0.75 and _clapBudget > 0:
						_clapBudget -= 1
						_play(game, "zmb_clap", {"pos": z.pos, "vol": 0.7})
	var clapT: float = f.clapT
	if clapT > 0.0:
		clapT = maxf(0.0, clapT - dt)
		f.clapT = clapT
	an.clap = sin((1.0 - clapT / 0.22) * PI) if clapT > 0.0 else 0.0
	return false

# MP client puppet (zombies_net.gd): the same flavour (groans, claps, the clap pose) for the local listener; the
# "spotted" groan uses distance (no line-of-sight test on puppets).
func puppet(game, z: Dictionary, dt: float) -> void:
	var p = game.player
	if p != null:
		z.los = Vector2(p.pos.x - z.pos.x, p.pos.z - z.pos.z).length() < 9.0
	update(game, z, dt)

func _play(game, id_: String, opts: Dictionary) -> void:
	if game.audio != null:
		game.audio.play(id_, opts)
