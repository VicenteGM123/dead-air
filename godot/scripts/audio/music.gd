# The music of WZTV Channel 13 (port of src/audio/music.js createMusic(); GDD §15, SPEC §7).
# The songs are rendered offline by tools/audio/render.mjs with music.js's own Player (every song, bar pattern,
# humanisation and the music plate reverb) into [intro | bar-aligned loop] files per state, with the adaptive layers
# as sample-aligned stems. This engine keeps music.js's state machine on top of them:
#   createMusic(audio) -> this object: setState(id), setIntensity(n), update(), stop(), tapeStop(t, dur), beat(), state
#   States: title, select, ambient, round, intermission, hullabaloo, boss, credits, morning, silence (STATES fades).
#     'select:<heroId>' picks that hero's 2-bar show intro (plain 'select' keeps the last hero) after the channel clack.
#     'boss:<n>' (or setIntensity(n), n = boss phase 1..3) raises the boss arrangement without a restart: the base
#     stem of phase n takes over on the next bar (music.js writes its bars 0.17 s ahead) and the p2 / p3 layers fade
#     over 1 s.
#     round / morning fade the wah-clav stem in while more than 16 zombies are alive (0.4 s / 4 s hysteresis,
#     1.5 s in / 3 s out), like music.js adapt().
#     ambient fades the music out (ambience and hum belong to audio.gd); silence cuts it (dead air).
#   tapeStop(t, dur = 1.2): pitch-glides whatever plays down to a stop (playback rate 1 -> 0 linearly, gain held to
#     dur/2 then faded), then silence. sting_gameover calls it (audio.gd).
#   beat(): { bpm, beat } of the current state (fractional beats since it started) or null; `state` = current id.
# JS plumbing not ported: the 25 ms lookahead scheduler, the delay-line tape (replaced by pitch_scale), the plate
# convolver (baked into the stems). Renames: none.
extends RefCounted

const Param = preload("res://scripts/audio/param.gd")

const LOOKAHEAD := 0.15          # music.js: note events committed this far ahead (bars are written 0.17 s early)
const CLAV_ZOMBIES := 16         # round/morning: the clav layer joins above this many living zombies
const BUS := "Music"

# fade: fade-in of the new state and fade-out of the previous one (seconds); no song = music off.
const STATES := {
	"title": {"song": true, "fade": 1.5},
	"select": {"fade": 0.25, "delay": 0.14},
	"ambient": {"fade": 2.5},
	"round": {"song": true, "fade": 2.0},
	"intermission": {"song": true, "fade": 1.2},
	"hullabaloo": {"song": true, "fade": 0.8},
	"boss": {"song": true, "fade": 0.6},
	"credits": {"song": true, "fade": 0.5},
	"morning": {"song": true, "fade": 2.5},
	"silence": {"fade": 0.04},
}
const ADAPTIVE := ["round", "morning"]
const HEROES := ["skip", "roxy", "penny", "duke"]

var audio
var lib
var cur = null           # { id, key, player }
var hero := "duke"       # GDD §4: Duke is the default / preselected hero
var intensity := 1
var clavWant := false
var clavSince := 0.0
var fading: Array = []
var _node: Node

# music.js `get state()`.
var state:
	get:
		return cur.id if cur != null else null

# ------------------------------------------------------------------------------------------------ Player
# One running song: the state's stems on the Music bus, started together at t0 (sample-aligned), each with its layer
# gain, under the song's fade / stop envelope (`out`) and the tape stop.
class Player extends RefCounted:
	var music
	var key: String
	var st: Dictionary
	var t0 := 0.0
	var bpm := 120.0
	var sd := 0.125
	var barDur := 2.0
	var out
	var stems := {}          # name -> { node, gain: Param, k }
	var vars := {}
	var started := false
	var endAt := INF
	var dead := false
	var tape = null          # { t, dur } when a tape stop runs through this song
	var _swap = null         # boss: { at, n } base stem swap on a bar line

	func _init(m, k: String, s: Dictionary, start: float, fade: float, v: Dictionary) -> void:
		music = m
		key = k
		st = s
		t0 = start
		vars = v
		bpm = float(s.get("bpm", 120.0))
		sd = 60.0 / bpm / 4.0
		barDur = sd * 16.0
		out = Param.new(0.0)
		if fade > 0.0:
			out.setValueAtTime(0.0, t0)
			out.linearRampToValueAtTime(1.0, t0 + fade)
		else:
			out.value = 1.0
			out._v0 = 1.0
		var n := int(vars.get("intensity", 1))
		for name in s.get("stems", {}):
			var f: Dictionary = s.stems[name]
			var strm: AudioStream = music.lib.stream(f.f, float(f.s))
			if strm == null:
				continue
			var p := AudioStreamPlayer.new()
			p.bus = BUS
			p.stream = strm
			p.volume_db = -80.0
			music._node.add_child(p)
			var on := true
			if name == "clav":
				on = false
			elif name.begins_with("base") and name.length() == 5:
				on = int(name.substr(4)) == n
			elif name == "p2":
				on = n >= 2
			elif name == "p3":
				on = n >= 3
			stems[name] = {"node": p, "gain": Param.new(1.0 if on else 0.0), "on": on, "k": float(f.get("k", 1.0))}

	func setLayer(name: String, on: bool, fade := 1.5) -> void:
		var L = stems.get(name)
		if L == null or L.on == on:
			return
		var t: float = music.audio.now()
		L.gain.cancelAndHoldAtTime(t)
		L.gain.linearRampToValueAtTime(1.0 if on else 0.0, t + fade)
		L.on = on

	# music.js setIntensity(): bars already written keep the old phase; the new one starts on the next bar line
	# at least LOOKAHEAD + 0.02 s away.
	func setIntensity(n: int, now: float) -> void:
		vars.intensity = n
		var b := ceilf((now + LOOKAHEAD + 0.02 - t0) / barDur)
		_swap = {"at": t0 + maxf(0.0, b) * barDur, "n": n}
		setLayer("p2", n >= 2, 1.0)
		setLayer("p3", n >= 3, 1.0)

	func pump(now: float) -> bool:
		if dead:
			return false
		if now > endAt + 0.1:
			dispose()
			return false
		if not started and now >= t0:
			started = true
			for name in stems:
				stems[name].node.play(maxf(0.0, now - t0))
		if _swap != null and now >= float(_swap.at):
			for name in stems:
				if name.begins_with("base") and name.length() == 5:
					var on: bool = int(name.substr(4)) == int(_swap.n)
					stems[name].gain.cancelAndHoldAtTime(now)
					stems[name].gain.linearRampToValueAtTime(1.0 if on else 0.0, now + 0.01)
					stems[name].on = on
			_swap = null
		var o: float = out.tick(now)
		var tg := 1.0
		var pitch := 1.0
		if tape != null:
			var x := clampf((now - float(tape.t)) / float(tape.dur), 0.0, 1.0)
			if now >= float(tape.t):
				pitch = maxf(0.01, 1.0 - x)
				tg = 1.0 if x <= 0.5 else clampf((1.0 - x) / 0.5, 0.0, 1.0)
		for name in stems:
			var L: Dictionary = stems[name]
			var g: float = L.gain.tick(now) * o * tg * float(L.k)
			var p: AudioStreamPlayer = L.node
			p.volume_db = linear_to_db(g) if g > 1e-5 else -100.0
			if absf(p.pitch_scale - pitch) > 1e-4:
				p.pitch_scale = pitch
		return true

	func stopAt(t: float, fade := 0.1) -> void:
		if dead or endAt <= t + fade:
			return
		out.cancelAndHoldAtTime(t)
		out.linearRampToValueAtTime(0.0, t + fade)
		endAt = t + fade

	func dispose() -> void:
		dead = true
		for name in stems:
			var p: AudioStreamPlayer = stems[name].node
			if is_instance_valid(p):
				p.stop()
				p.queue_free()
		stems.clear()

	func beat(now: float) -> float:
		return maxf(0.0, (now - t0) / (sd * 4.0))

# ------------------------------------------------------------------------------------------------ engine
func _init(a) -> void:
	audio = a
	lib = a._lib
	_node = Node.new()
	_node.name = "Music"
	a._node.add_child(_node)

func _stateDef(key: String):
	var ms: Dictionary = lib.music.get("states", {}) if lib.music is Dictionary else {}
	return ms.get(key)

func _start(key: String, fade: float, delay: float, vars: Dictionary):
	var st = _stateDef(key)
	if st == null or st.get("stems", {}).is_empty():
		push_warning("[audio] music state '%s' not rendered" % key)
		return null
	var p := Player.new(self, key, st, audio.now() + delay, fade, vars)
	p.pump(audio.now())
	return p

func setState(id) -> void:
	var s := String(id)
	var parts := s.split(":")
	var base := parts[0]
	var arg = parts[1] if parts.size() > 1 else null
	var def = STATES.get(base)
	if def == null:
		return
	if base == "boss" and cur != null and cur.id == "boss":
		if arg != null and arg != "":
			setIntensity(float(arg))
		return
	if base == "select" and arg != null and HEROES.has(arg):
		hero = arg
	var key := "select:" + hero if base == "select" else base
	if cur != null and cur.key == key:
		return
	var now: float = audio.now()
	var fade := float(def.fade)
	if cur != null and cur.player != null:
		cur.player.stopAt(now, fade)
		fading.append(cur.player)
	if base == "boss":
		var n := int(float(arg)) if arg != null and String(arg).is_valid_float() else 0
		intensity = clampi(n if n != 0 else 1, 1, 3)
	var hasSong: bool = def.get("song", false) or base == "select"
	if base == "select":
		_clack(now + 0.005)
	clavWant = false
	cur = {"id": base, "key": key, "player": _start(key, fade, float(def.get("delay", 0.03)), {"intensity": intensity}) if hasSong else null}

func setIntensity(n) -> void:
	var v := int(roundf(float(n)))
	intensity = clampi(v if v != 0 else 1, 1, 3)
	var p = cur.player if cur != null and cur.id == "boss" else null
	if p == null:
		return
	p.setIntensity(intensity, audio.now())

# round/morning: follow the living-zombie count with a little hysteresis.
func adapt(p, now: float) -> void:
	var g = audio.game
	var z = g.get("zombies") if g != null else null
	var n := 0
	if z != null:
		var alive = z.get("alive")
		if alive != null:
			n = alive.size()
	var want := n > CLAV_ZOMBIES
	if want != clavWant:
		clavWant = want
		clavSince = now
	var L = p.stems.get("clav")
	if L != null and L.on != want and now - clavSince > (0.4 if want else 4.0):
		p.setLayer("clav", want, 1.5 if want else 3.0)

func update(_dt := 0.0) -> void:
	var now: float = audio.now()
	var p = cur.player if cur != null else null
	if p != null:
		if ADAPTIVE.has(cur.id):
			adapt(p, now)
		if not p.pump(now):
			cur.player = null
	for f in fading.duplicate():
		if not f.pump(now):
			fading.erase(f)

func stop() -> void:
	var now: float = audio.now()
	for f in fading:
		f.stopAt(now, 0.05)
	if cur != null and cur.player != null:
		cur.player.stopAt(now, 0.05)
		fading.append(cur.player)
	cur = null

# Tape stop: the playback rate of every running song slows linearly to zero over `dur` (music.js: a delay line whose
# delay grows as t²/2D), the gain holds to dur/2 and fades out by dur; then silence.
func tapeStop(t: float, dur := 1.2) -> void:
	var p = cur.player if cur != null else null
	if p == null:
		return
	for q in fading + [p]:
		q.tape = {"t": t, "dur": dur}
	p.stopAt(t + dur, 0.02)
	fading.append(p)
	cur = {"id": "silence", "key": "silence", "player": null}

func beat():
	var p = cur.player if cur != null else null
	return {"bpm": p.bpm, "beat": p.beat(audio.now())} if p != null else null

# character select's channel clack (music.js clack(tapeIn, now + 0.005, { peak: 0.3 }) on the music bus)
func _clack(at: float) -> void:
	var c = lib.music.get("clack")
	if not (c is Dictionary):
		return
	audio._oneShotOnBus(String(c.f), BUS, at)
