# DEAD AIR — audio.gd
# Audio engine (port of src/audio/audio.js; ARCHITECTURE §10, GDD §15, SPEC §7): bus graph, per-area reverb,
# positional voices, TV-speaker filter, ducking / low-HP muffle, loops, area ambience, music delegation and the
# automatic hookups of the trivial generic cues to game events.
# The sounds are the web build's own WebAudio recipes rendered offline by tools/audio/render.mjs into
# res://assets/audio (see sfx.gd for the cue library and index.json); music.gd drives the music states.
#
# Public API (game.audio)
#   play(id, { pos, vol=1, rate=1, detune=0, delay=0, bus, tv, pan, range, wet, ...recipeOpts }) -> Voice | null
#       Voice: { id, stop(fade), setPos(v), setVol(v, ramp), playing, step() (telly_surf_arp), setDistance(d) }.
#       Unknown ids, or a call before init(), return null silently. recipeOpts are the recipe parameters the
#       renders cover: upgraded, rhythm, base, foot, flip, dur, syllables, claps, notes, auto, d.
#   loop(id, { pos, vol }) -> LoopHandle { stop(fade), setPos(v), setVol(v, ramp), setDistance(d), playing }
#       Always returns a handle (inert for unknown ids). A loop requested before init() starts as soon as the engine
#       exists. Pass `pos` at creation to make it positional. Inherent loop recipes play their seamless loop render
#       until stopped; one-shot recipes are retriggered back to back (a new random variation each time).
#   music(stateId)  stopAll()  duck(db, lowpassHz, seconds)  setMasterVolume(v)  setBusVolume(bus, v)
#   getBusVolume(bus)  init()  update(dt)  reset()  unlock()
#
# Internal API (music.gd / sfx.gd)
#   ctx (null until unlock: true afterwards)  now() (audio clock, s)  _music (music.gd engine: state, beat())
#   bus = { master, music, sfx, ambience, ui, tv }: Godot bus names. sfx/ambience/tv form the "world" group that
#       duck() / the low-HP muffle filter and that feeds the area reverb; music and ui bypass both.
#       Master: compressor -> limiter -> soft clip.
#   registerCues(table, defaults?): kept for callers of the JS API; recipes cannot run live here, so ids already
#       rendered keep their files and new ones warn (add them to tools/audio/render.mjs).
#
# Automatic hookups (callers don't play these themselves): ui_hit / ui_hit_head (zombie:hit), ui_kill,
# footsteps per floor surface (player:step; its `surface`, else level.surfaceAt; skate_push when sprinting
# on Roller Boogie), jump, land, hurt_grunt (per-hero voice pitch) + hurt_static (+ jelly_bwoing with
# Wobble-Up), low-HP heartbeat and 1.2 kHz muffle, ui_buy on every spend, ui_denied, points flips (ka-ching
# in SWEEPS WEEK), weapon fire (wpn_<id>, chirp/upgraded layers inside), dry_fire, weapon_swap, melee
# whoosh/hit, wallbuy_boing, power-up spawn/grab + announcer (+ pu_bossa_bed under PLEASE STAND BY), the
# commercial duck, ui_prompt, area ambience. Door beats (poof, chain snap, keypad motif, elephant, DY buzz,
# crowd ooh), board_tear / board_repair, light_thunk and onair_clack are played by the world (level, doors,
# windows) in sync with their animations.
# Identical plays of one id within its `gap` (default 30 ms) at the same spot are merged, so a system
# that also plays one of these by hand is harmless.
#
# Port notes (engine plumbing / known deviations):
#   * No AudioContext: the engine is live from init() (no user-gesture unlock). The audio clock is real time.
#   * Voices are AudioStreamPlayer (non-positional) / AudioStreamPlayer3D (positional, children of game.scene) playing
#     the rendered files; the per-voice gain automation (setVol / stop release) runs at control rate.
#   * Positional voices: the JS distance models are computed here (Godot attenuation disabled): 'inverse' with
#     ref = recipe.ref ?? 2.5, or 'linear' from 1 m to `range`; panning is Godot's (no HRTF: the 8 HRTF slots only
#     keep their bookkeeping). The air-absorption low-pass (20 kHz·e^(-d/22), >= 2.2 kHz, set at placement) is
#     approximated with the player's high-shelf attenuation filter.
#   * The TV-speaker chain (HP 300 / peak 2.2 k / LP 4 k / soft clip, x1.35) is baked into the renders of every cue
#     heard through a TV; other tv:true plays fall back to a bus filter.
#   * Area reverb: Godot AudioEffectReverb per world bus (and per extra-wet bus) with room size / damping / wet
#     matched to each area's procedural impulse response (RT60 and energy measured on both engines).
#   * Master: WebAudio's soft-knee compressor (-16 dB, knee 12, 3:1) is a -10 dB hard-knee 3:1 (same curve above
#     -4 dB) with Chrome's +4.0 dB automatic makeup; the limiter (-2.5 dB, 20:1) keeps its +1.43 dB makeup; the soft
#     clip is a hard limiter at 0.985.
# Renames (SPEC §3.2): none.
extends RefCounted

const Param = preload("res://scripts/audio/param.gd")
const SfxLib = preload("res://scripts/audio/sfx.gd")
const MusicEngine = preload("res://scripts/audio/music.gd")

const AREA_REVERB := {"lobby": 0.8, "newsroom": 0.9, "green_room": 0.5, "studio_a": 1.8, "studio_b": 1.2, "master_control": 0.4, "yard": 0.3}
# Godot reverb per area, fitted to the JS impulse responses above (RT60 / energy of a white-noise burst measured on
# both engines): room_size, damping, predelay (ms), predelay feedback (the yard's slap echoes), k = wet per send.
const AREA_GODOT := {
	"lobby": {"room": 0.28, "damp": 0.8, "pre": 20.0, "fb": 0.0, "k": 0.202},
	"newsroom": {"room": 0.355, "damp": 0.8, "pre": 20.0, "fb": 0.0, "k": 0.206},
	"green_room": {"room": 0.0, "damp": 0.8, "pre": 20.0, "fb": 0.0, "k": 0.197},
	"studio_a": {"room": 0.68, "damp": 0.8, "pre": 20.0, "fb": 0.0, "k": 0.220},
	"studio_b": {"room": 0.51, "damp": 0.8, "pre": 20.0, "fb": 0.0, "k": 0.206},
	"master_control": {"room": 0.0, "damp": 0.8, "pre": 20.0, "fb": 0.0, "k": 0.178},
	"yard": {"room": 0.0, "damp": 0.8, "pre": 120.0, "fb": 0.36, "k": 0.147},
}
const HERO_VOICE := {"skip": 210, "roxy": 260, "penny": 240, "duke": 120}
const WORLD_BUSES := ["sfx", "ambience", "tv"]
const REVERB_SEND := {"sfx": 0.2, "ambience": 0.12, "tv": 0.16}
const DEFAULT_VOLUMES := {"master": 0.9, "music": 0.75, "sfx": 1.0, "ambience": 0.8, "ui": 0.85, "tv": 1.0}
const FIRE_CUES := {"revolver_38": "wpn_revolver_38", "pump_37": "wpn_pump_37", "mp7": "wpn_mp7", "m16a1": "wpn_m16a1", "m60": "wpn_m60", "zapper": "wpn_zapper", "chroma_key": "wpn_chroma_fire"}
const PU_CUES := {"cancelled": "pu_cancelled", "full_reel": "pu_full_reel", "one_take": "pu_one_take", "sweeps_week": "pu_sweeps_week", "gaffer_tape": "pu_gaffer_tape", "please_stand_by": "pu_stand_by"}
const PU_RHYTHM := {"cancelled": [1.1, 0.9], "full_reel": [1, 0.85], "one_take": [1.15, 0.9], "sweeps_week": [1, 1.1, 0.85], "gaffer_tape": [1.1, 0.95, 1.05, 0.85], "please_stand_by": [1.05, 1, 0.95, 1.12, 0.8]}
const LOW_HP := 0.35
const MAX_VOICES := 96
const MAX_HRTF := 8
const LOOKAHEAD := 0.4
const START_LAG := 0.012
const SURF_ARP := [0, 7, 12, 10]      # music.js telly_surf_arp: root, fifth, octave, flat seventh

const BUS_NAMES := {"master": "Master", "music": "Music", "sfx": "SFX", "ambience": "Ambience", "ui": "UI", "tv": "TV"}
# Master chain (see the header): WebAudio DynamicsCompressor settings mapped onto Godot's effects. Godot's compressor
# scales the overshoot by 2.0814 before applying the ratio, so a WebAudio ratio r becomes 1 / (1 - (r-1)/(2.0814·r))
# (3:1 -> 1.471, 20:1 -> 1.840); the static curve then matches node-web-audio-api / Chrome within ~0.5 dB.
const GODOT_OVER := 2.08136898
const COMP := {"threshold": -10.0, "ratio": 3.0, "gain": 4.0, "attack_us": 2000.0, "release_ms": 250.0}
const LIMIT := {"threshold": -2.5, "ratio": 20.0, "gain": 1.425, "attack_us": 1000.0, "release_ms": 80.0}

static func _godotRatio(r: float) -> float:
	return 1.0 / (1.0 - (r - 1.0) / (GODOT_OVER * r))
const CLIP_DB := -0.131   # 0.985

var game
var ctx = null
var bus = null
var synth = null            # the JS synth toolkit has no runtime counterpart (nothing is synthesised live)
var cues := {}
var cueDefaults := {}
var voices: Array = []
var volumes := DEFAULT_VOLUMES.duplicate()
var _n = null
var _music = null
var _musicState = null
var _regDefaults = null
var _pending: Array = []
var _last := {}
var _warned := {}
var _rv := {"area": null, "active": 0, "switchedAt": -10.0, "fadeOut": -1}
var _amb := {"id": null, "handle": null, "hum": null, "suspended": false, "level": 0.0}
var _area = null
var _lowHp := false
var _heart = null
var _prompt = null
var _lpos = null            # listener position (Vector3) once known
var _lib
var _node: Node             # non-positional players + the ticker (child of the Game node, processes always)
var _root3d: Node3D         # positional players + the listener (game.scene)
var _listener: AudioListener3D
var _t0usec := 0
var _reverbs: Array = []    # { bus, idx, send } every reverb effect (per-area parameters)
var _mirrors := {}          # extra bus name -> bus key whose volume it mirrors
var _hooked := false

# ------------------------------------------------------------------------------------------------ Voice
# One playing cue: its output chain (bus, position, gain automation) plus the players of its rendered file(s).
class Voice extends RefCounted:
	var audio
	var id: String
	var cue: Dictionary
	var chain: Dictionary        # { bus, gbus, pos, positional, baseVol, range, ref, air, hrtf, tvf }
	var ro: Dictionary           # play opts + { t, loop, pitch }
	var looping := false
	var kind := "shot"           # shot | loopfile | retrig | arp | notes | tones
	var end := 0.0
	var stopped := false
	var disposed := false
	var gain                     # Param: chain input gain (vol · baseVol)
	var subs: Array = []         # { node, at, k, started, loop }
	var _arpI := 0
	var _beat = null             # ee_tracking_tones: second sine's pitch (Param)
	var _fade = null             # ee_tracking_tones: the recipe's 0.15 s fade-in (Param)

	var playing: bool:
		get:
			return not stopped and not disposed and audio.now() < end

	func _init(a, i: String, c: Dictionary, ch: Dictionary, o: Dictionary, lp: bool) -> void:
		audio = a
		id = i
		cue = c
		chain = ch
		ro = o
		looping = lp
		gain = Param.new(float(o.get("vol", 1.0)) * float(ch.baseVol))

	func stop(fade := 0.06) -> void:
		if stopped or disposed:
			return
		stopped = true
		var now: float = audio.now()
		var f := maxf(0.005, fade)
		gain.cancelAndHoldAtTime(now)          # synth.release(param, now, f)
		gain.setTargetAtTime(0.0, now, f / 5.0)
		end = minf(end, now + f + 0.05)

	func setPos(p) -> void:
		if p != null and chain.positional:
			audio._placePanner(chain, p)
			for s in subs:
				if is_instance_valid(s.node):
					(s.node as Node3D).global_position = chain.pos
					audio._applyAir(s.node, chain)

	func setVol(v, ramp := 0.05) -> void:
		if stopped or disposed:
			return
		var now: float = audio.now()
		gain.cancelScheduledValues(now)
		gain.setTargetAtTime(float(v) * float(chain.baseVol), now, maxf(0.001, ramp / 3.0))

	# telly_surf_arp handle: one slap-bass note per dial detent, a semitone higher every 4 detents, with a hat tick.
	func step() -> void:
		if kind != "arp" or disposed:
			return
		var m: int = 52 + SURF_ARP[_arpI % 4] + int(floor(_arpI / 4.0))
		audio._arpNote(self, m, audio.now() + 0.005)
		_arpI += 1

	# ee_tracking_tones handle: the second sine glides to 440 + 2.5·d Hz (d clamped 0..12).
	func setDistance(d) -> void:
		if _beat == null:
			return
		var hz := 440.0 + 2.5 * clampf(float(d) if d != null else 0.0, 0.0, 12.0)
		_beat.setTargetAtTime(hz / 440.0, audio.now(), 0.05)

	func update(now: float) -> void:
		if disposed:
			return
		if kind == "retrig" and not stopped and now + LOOKAHEAD >= end:
			var t := maxf(end, now + START_LAG)
			var e: float = audio._retrigger(self, t)
			end = t + e if e > 0.0 else t + 1.0

	func dispose() -> void:
		if disposed:
			return
		disposed = true
		for s in subs:
			if is_instance_valid(s.node):
				s.node.stop()
				s.node.queue_free()
		subs.clear()

# ------------------------------------------------------------------------------------------------ LoopHandle
# Stable handle returned by loop(): survives being requested before the engine exists.
class LoopHandle extends RefCounted:
	var audio
	var id: String
	var opts: Dictionary
	var voice = null
	var stopped := false
	var _dist = null

	var playing: bool:
		get:
			return voice != null and voice.playing

	func _init(a, i: String, o: Dictionary) -> void:
		audio = a
		id = i
		opts = o.duplicate()

	func _start() -> void:
		if stopped or voice != null:
			return
		var v = audio._launch(id, opts, true)
		if v == null:
			return
		voice = v
		if _dist != null:
			setDistance(_dist)

	func stop(fade := 0.12) -> void:
		stopped = true
		if voice != null:
			voice.stop(fade)

	func setPos(p) -> void:
		opts.pos = p
		if voice != null:
			voice.setPos(p)

	func setVol(v, ramp := 0.1) -> void:
		opts.vol = v
		if voice != null:
			voice.setVol(v, ramp)

	func setDistance(d) -> void:
		_dist = d
		if voice != null:
			voice.setDistance(d)

	func step() -> void:
		if voice != null:
			voice.step()

# Drives the engine every frame in every game state (the JS 25 ms ticker).
class Ticker extends Node:
	var audio
	func _process(_delta: float) -> void:
		if audio != null:
			audio._tick()

# ------------------------------------------------------------------------------------------------ lifecycle
func _init(g) -> void:
	game = g
	_lib = SfxLib.new()
	cues = _lib.cues
	for id in cues:
		cueDefaults[id] = null

func init() -> void:
	_hookEvents()
	unlock()

# Godot needs no user gesture: the engine starts at once (JS: on the first pointer / key event).
func unlock() -> void:
	if ctx == null:
		attach()

func attach(_opts := {}) -> void:
	if ctx != null:
		return
	ctx = true
	_t0usec = Time.get_ticks_usec()
	_build()
	var pending := _pending
	_pending = []
	for h in pending:
		h._start()
	_startMusic()

func reset() -> void:
	for v in voices:
		if v.chain.bus != "music":
			v.stop(0.1)
	for h in _pending:
		h.stop()
	_pending = []
	_amb = {"id": null, "handle": null, "hum": null, "suspended": false, "level": 0.0}
	_area = null
	_lowHp = false
	_heart = null
	_prompt = null
	if _n != null:
		var now := now()
		_n.world.cancelScheduledValues(now)
		_n.world.setTargetAtTime(1.0, now, 0.05)
		_n.duckLp.cancelScheduledValues(now)
		_n.duckLp.setTargetAtTime(20000.0, now, 0.05)
		_n.muffLp.setTargetAtTime(20000.0, now, 0.05)

func update(_dt := 0.0) -> void:
	if ctx == null or _n == null:
		return
	_updateListener()
	_updateArea()
	_updateHealth()
	_updatePrompt()
	_schedule(now())

# ------------------------------------------------------------------------------------------------ graph
func _bus(name: String, send: String) -> int:
	var i := AudioServer.get_bus_index(name)
	if i < 0:
		AudioServer.add_bus()
		i = AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, name)
	while AudioServer.get_bus_effect_count(i) > 0:
		AudioServer.remove_bus_effect(i, 0)
	if send != "":
		AudioServer.set_bus_send(i, send)
	return i

static func _lowpass(cut: float, q: float) -> AudioEffectLowPassFilter:
	var f := AudioEffectLowPassFilter.new()
	f.cutoff_hz = cut
	f.resonance = q
	f.db = AudioEffectFilter.FILTER_12DB
	return f

func _reverb(bi: int, send: float) -> void:
	var r := AudioEffectReverb.new()
	r.dry = 1.0
	r.spread = 1.0
	r.hipass = 0.0
	AudioServer.add_bus_effect(bi, r)
	_reverbs.append({"bus": AudioServer.get_bus_name(bi), "idx": AudioServer.get_bus_effect_count(bi) - 1, "send": send})

func _build() -> void:
	# Master -> compressor -> limiter -> soft clip. Bus order keeps every send pointing to an earlier bus.
	var m := _bus("Master", "")
	var comp := AudioEffectCompressor.new()
	comp.threshold = COMP.threshold
	comp.ratio = _godotRatio(COMP.ratio)
	comp.gain = COMP.gain
	comp.attack_us = COMP.attack_us
	comp.release_ms = COMP.release_ms
	AudioServer.add_bus_effect(m, comp)
	var lim := AudioEffectCompressor.new()
	lim.threshold = LIMIT.threshold
	lim.ratio = _godotRatio(LIMIT.ratio)
	lim.gain = LIMIT.gain
	lim.attack_us = LIMIT.attack_us
	lim.release_ms = LIMIT.release_ms
	AudioServer.add_bus_effect(m, lim)
	var clip := AudioEffectHardLimiter.new()
	clip.ceiling_db = CLIP_DB
	AudioServer.add_bus_effect(m, clip)
	var muff := _bus("Muffle", "Master")
	AudioServer.add_bus_effect(muff, _lowpass(20000.0, 0.5))
	var world := _bus("World", "Muffle")
	AudioServer.add_bus_effect(world, _lowpass(20000.0, 0.5))
	bus = {"master": "Master"}
	for name in WORLD_BUSES:
		var bi := _bus(BUS_NAMES[name], "World")
		_reverb(bi, REVERB_SEND[name])
		bus[name] = BUS_NAMES[name]
	for name in ["music", "ui"]:
		_bus(BUS_NAMES[name], "Master")
		bus[name] = BUS_NAMES[name]
	for name in volumes:
		_applyBusVolume(name)
	_n = {"world": Param.new(1.0), "duckLp": Param.new(20000.0), "muffLp": Param.new(20000.0)}
	# players + ticker
	_node = Ticker.new()
	_node.name = "Audio"
	_node.audio = self
	_node.process_mode = Node.PROCESS_MODE_ALWAYS
	game.add_child(_node)
	var sc = game.get("scene")
	if sc is Node3D:
		_root3d = sc
	else:
		_root3d = Node3D.new()
		_root3d.name = "AudioWorld"
		game.add_child(_root3d)
	_listener = AudioListener3D.new()
	_listener.name = "AudioListener"
	_root3d.add_child(_listener)
	_listener.make_current()
	_setReverb("lobby", true)

func _applyBusVolume(name: String) -> void:
	if not BUS_NAMES.has(name):
		return
	var db := linear_to_db(maxf(float(volumes[name]), 1e-5))
	var i := AudioServer.get_bus_index(BUS_NAMES[name])
	if i >= 0:
		AudioServer.set_bus_volume_db(i, db)
	for b in _mirrors:
		if _mirrors[b] == name:
			var j := AudioServer.get_bus_index(b)
			if j >= 0:
				AudioServer.set_bus_volume_db(j, db)

func _setReverb(area, immediate := false) -> void:
	if _rv.area == area:
		return
	var now := now()
	if not immediate and now - float(_rv.switchedAt) < 1.0:
		return
	var A: Dictionary = AREA_GODOT.get(area, AREA_GODOT.lobby)
	for r in _reverbs:
		var bi := AudioServer.get_bus_index(r.bus)
		if bi < 0 or r.idx >= AudioServer.get_bus_effect_count(bi):
			continue
		var e := AudioServer.get_bus_effect(bi, r.idx) as AudioEffectReverb
		if e == null:
			continue
		e.room_size = A.room
		e.damping = A.damp
		e.predelay_msec = A.pre
		e.predelay_feedback = A.fb
		e.wet = float(r.send) * float(A.k)
	_rv.area = area
	_rv.switchedAt = now

# Bus of one voice: the base bus, or a lazily created variant carrying the voice's stereo pan, the TV-speaker filter
# (voices heard through a TV whose file was not rendered through it) and / or an extra reverb send (opts.wet ??
# recipe.wet: its own reverb at send + wet, straight to the base bus's parent, volume mirrored from the base bus).
func _voiceBus(key: String, tvf: bool, wet: float, pan: float) -> String:
	var base: String = BUS_NAMES.get(key, "SFX")
	if not tvf and wet <= 0.0 and absf(pan) < 0.005:
		return base
	var name := base
	if tvf:
		name += "_tv"
	if wet > 0.0:
		name += "_w%d" % roundi(wet * 100.0)
	if absf(pan) >= 0.005:
		name += "_p%d" % roundi(pan * 100.0)
	if AudioServer.get_bus_index(name) >= 0:
		return name
	var parent := "World" if WORLD_BUSES.has(key) else "Master"
	var bi := _bus(name, parent if wet > 0.0 else base)
	if absf(pan) >= 0.005:
		var pn := AudioEffectPanner.new()
		pn.pan = clampf(pan, -1.0, 1.0)
		AudioServer.add_bus_effect(bi, pn)
	if tvf:
		var hp := AudioEffectHighPassFilter.new()
		hp.cutoff_hz = 300.0
		hp.resonance = 0.7
		AudioServer.add_bus_effect(bi, hp)
		var eq := AudioEffectEQ6.new()
		eq.set_band_gain_db(4, 3.0)      # ~ the +3 dB peak at 2.2 kHz
		AudioServer.add_bus_effect(bi, eq)
		AudioServer.add_bus_effect(bi, _lowpass(4000.0, 0.9))
		var sh := AudioEffectDistortion.new()   # ~ tanh(1.8x)/tanh(1.8): x1.9 small-signal, soft ceiling
		sh.mode = AudioEffectDistortion.MODE_ATAN
		sh.drive = 0.2
		sh.post_gain = 13.6
		sh.keep_hf_hz = 16000.0
		AudioServer.add_bus_effect(bi, sh)
	if wet > 0.0:
		_reverb(bi, float(REVERB_SEND.get(key, 0.0)) + wet)
		_mirrors[name] = key
		_applyBusVolume(key)
		var area = _rv.area
		_rv.area = null
		_setReverb(area if area != null else "lobby", true)
	return name

# Per-voice output chain: gain -> [TV speaker] -> [air + panner | stereo pan] -> bus.
func _chain(o: Dictionary) -> Dictionary:
	var key: String = o.bus if BUS_NAMES.has(o.bus) and o.bus != "master" else "sfx"
	var baseVol: float = float(o.get("norm", 1.0)) * (1.35 if o.tvf else 1.0)
	var pos = o.get("pos")
	var positional: bool = pos != null
	var hrtf: bool = positional and bool(o.get("zombie", false)) and _hrtfCount() < MAX_HRTF
	var chain := {
		"bus": key, "positional": positional, "pos": DAU.v3(pos) if positional else Vector3.ZERO, "baseVol": baseVol,
		"range": o.get("range"), "ref": o.get("ref"), "air": 20000.0, "hrtf": hrtf, "tvf": o.tvf,
		"gbus": _voiceBus(key, o.tvf, float(o.get("wet", 0.0)) if o.get("wet") != null else 0.0, 0.0 if positional else float(o.get("pan", 0.0)) if o.get("pan") != null else 0.0),
	}
	if positional:
		_placePanner(chain, pos)
	return chain

func _placePanner(chain: Dictionary, p) -> void:
	chain.pos = DAU.v3(p)
	var d := 0.0
	if _lpos != null:
		d = (chain.pos as Vector3).distance_to(_lpos)
	chain.air = clampf(20000.0 * exp(-d / 22.0), 2200.0, 20000.0)

# Distance gain of the JS PannerNode models.
func _distGain(chain: Dictionary) -> float:
	if not chain.positional or _lpos == null:
		return 1.0
	var d := (chain.pos as Vector3).distance_to(_lpos)
	var rg = chain.range
	if rg != null and float(rg) > 0.0:
		var mx := float(rg)
		if mx <= 1.0:
			return 1.0 if d <= 1.0 else 0.0
		return clampf(1.0 - (clampf(d, 1.0, mx) - 1.0) / (mx - 1.0), 0.0, 1.0)
	var ref := float(chain.ref) if chain.ref != null else 2.5
	return ref / (ref + maxf(d, ref) - ref)

# Air absorption low-pass approximated by Godot's attenuation high-shelf (cutoff = the JS low-pass cutoff).
func _applyAir(node, chain: Dictionary) -> void:
	var p := node as AudioStreamPlayer3D
	if p == null:
		return
	var fc: float = chain.air
	if fc >= 16000.0:
		p.attenuation_filter_db = 0.0
		return
	p.attenuation_filter_cutoff_hz = fc
	# Godot scales the shelf by (1 - min(1, volume)): compensate so the shelf is ~-12 dB whatever the voice gain.
	var m := db_to_linear(minf(p.volume_db, p.max_db))
	p.attenuation_filter_db = clampf(-12.0 / maxf(0.05, 1.0 - minf(1.0, m)), -80.0, 0.0) if m < 0.999 else 0.0

func _hrtfCount() -> int:
	var n := 0
	var now := now()
	for v in voices:
		if v.chain.hrtf and not v.disposed and now < v.end:
			n += 1
	return n

# ------------------------------------------------------------------------------------------------ cues
func registerCues(table, defaults = null) -> void:
	if not (table is Dictionary):
		return
	for id in table:
		if cues.has(id):
			continue
		if not _warned.has("reg:" + str(id)):
			_warned["reg:" + str(id)] = true
			push_warning("[audio] cue '%s' registered at runtime has no render (add it to tools/audio/render.mjs)" % id)

func now() -> float:
	if ctx == null:
		return 0.0
	return float(Time.get_ticks_usec() - _t0usec) / 1000000.0

func out(_opts := {}):
	return null

func play(id: String, opts := {}):
	if ctx == null or _n == null or not cues.has(id):
		return null
	return _launch(id, opts if opts is Dictionary else {}, false)

func loop(id: String, opts := {}) -> LoopHandle:
	var h := LoopHandle.new(self, id, opts if opts is Dictionary else {})
	if not cues.has(id):
		h.stopped = true
		return h
	if ctx == null or _n == null:
		_pending.append(h)
	else:
		h._start()
	return h

func _launch(id: String, opts: Dictionary, looping: bool):
	var recipe: Dictionary = cues.get(id, {})
	if recipe.is_empty():
		return null
	if not looping and _duplicate(id, recipe, opts):
		return null
	_enforceLimits(id, recipe)
	var t := now() + START_LAG + float(opts.get("delay", 0.0) if opts.get("delay") != null else 0.0)
	var pitch := float(opts.get("rate", 1.0) if opts.get("rate") != null else 1.0) * pow(2.0, float(opts.get("detune", 0.0) if opts.get("detune") != null else 0.0) / 1200.0)
	if recipe.get("reads", []).has("foot") and opts.get("foot"):
		pitch *= 0.95        # sfx.js stepK: pit(o) · (o.foot ? 0.95 : 1)
	var wantTv: bool = bool(opts.tv) if opts.get("tv") != null else bool(recipe.get("tv", false))
	# what plays: kind + first file
	var kind := "shot"
	var pk = null
	var loopf = null
	if id == "ee_tracking_tones":
		kind = "tones"
	elif id == "toy_xylophone":
		kind = "notes"
	elif looping and recipe.get("loop") != null:
		kind = "loopfile"
		loopf = recipe.loop
	elif recipe.get("inherent", false):
		if recipe.get("loop") == null:
			return null
		kind = "loopfile"
		loopf = recipe.loop
	elif id == "telly_surf_arp" and not opts.get("auto"):
		kind = "arp"
	else:
		kind = "retrig" if looping else "shot"
		pk = _lib.pick(id, opts, pitch, wantTv)
		if pk == null:
			return null
	var rendTv := false
	if loopf != null:
		rendTv = bool(loopf.get("tv", false))
	elif pk != null:
		rendTv = pk.tv
	elif kind == "arp":
		rendTv = true
	var def = cueDefaults.get(id)
	var chain := _chain({
		"bus": opts.get("bus") if opts.get("bus") != null else recipe.get("bus", def.bus if def is Dictionary and def.has("bus") else "sfx"),
		"tvf": wantTv and not rendTv,
		"pos": opts.get("pos"),
		"pan": opts.get("pan"),
		"zombie": recipe.get("zombie", false),
		"range": opts.get("range") if opts.get("range") != null else recipe.get("range"),
		"ref": recipe.get("ref"),
		"wet": opts.get("wet") if opts.get("wet") != null else recipe.get("wet"),
		"norm": 1.0,
	})
	var ro := opts.duplicate()
	ro.t = t
	ro.loop = looping
	ro.pitch = pitch
	var v := Voice.new(self, id, recipe, chain, ro, looping)
	v.kind = kind
	match kind:
		"shot", "retrig":
			_addSub(v, pk.file, pk.rate, t)
			v.end = t + float(pk.file.e)
			if kind == "retrig" and float(pk.file.e) <= 0.0:
				v.end = t + 1.0
			if id == "telly_surf_arp":
				v.kind = "arp"
				v._arpI = 20
		"loopfile":
			var s: AudioStream = _lib.stream(loopf.f, float(loopf.s))
			_addSubStream(v, s, 1.0, t, float(loopf.get("k", 1.0)), true)
			v.end = INF
		"arp":
			v.end = t + 12.0
		"notes":
			v.end = _xyloNotes(v, t)
		"tones":
			_tones(v, t)
			v.end = INF
	voices.append(v)
	if id == "sting_gameover" and _music != null:
		_music.tapeStop(t, 1.2)       # music.js: the sting tape-stops the music (engine)
	return v

func _addSub(v: Voice, file: Dictionary, rate: float, at: float) -> void:
	var s: AudioStream = _lib.stream(file.f)
	_addSubStream(v, s, rate, at, float(file.get("k", 1.0)), false)

func _addSubStream(v: Voice, s: AudioStream, rate: float, at: float, k: float, looped: bool):
	if s == null:
		return null
	var node: Node
	if v.chain.positional:
		var p := AudioStreamPlayer3D.new()
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		p.max_db = 24.0
		p.max_distance = 0.0
		p.panning_strength = 1.0
		p.attenuation_filter_db = 0.0
		p.stream = s
		p.bus = v.chain.gbus
		p.pitch_scale = clampf(rate, 0.01, 4.0)
		p.volume_db = -100.0
		_root3d.add_child(p)
		p.global_position = v.chain.pos
		node = p
	else:
		var p := AudioStreamPlayer.new()
		p.stream = s
		p.bus = v.chain.gbus
		p.pitch_scale = clampf(rate, 0.01, 4.0)
		p.volume_db = -100.0
		_node.add_child(p)
		node = p
	var sub := {"node": node, "at": at, "k": k, "started": false, "loop": looped}
	v.subs.append(sub)
	_tickSub(v, sub, now(), v.gain.tick(now()))
	return sub

# loop() of a one-shot recipe: the next variation back to back (Voice.update). Returns its end offset.
func _retrigger(v: Voice, t: float) -> float:
	var pk = _lib.pick(v.id, v.ro, float(v.ro.pitch), v.chain.tvf or bool(v.ro.get("tv", v.cue.get("tv", false))))
	if pk == null:
		return 1.0
	_addSub(v, pk.file, pk.rate, t)
	return float(pk.file.e)

func _arpNote(v: Voice, m: int, at: float) -> void:
	var P: Dictionary = _lib.parts.get("telly_surf_arp", {})
	var files: Dictionary = P.get("f", {})
	if files.is_empty():
		return
	var key := str(m)
	var rate := 1.0
	if not files.has(key):
		var best := 0
		var bd := 999
		for k in files:
			if absi(int(k) - m) < bd:
				bd = absi(int(k) - m)
				best = int(k)
		key = str(best)
		rate = pow(2.0, (m - best) / 12.0)
	_addSubStream(v, _lib.stream(files[key]), rate, at, 1.0, false)

# toy_xylophone: opts.notes (MIDI) or a random 3-note tune from the pentatonic pool, 0.18 s apart, third note louder.
func _xyloNotes(v: Voice, t: float) -> float:
	var P: Dictionary = _lib.parts.get("toy_xylophone", {})
	var files: Dictionary = P.get("f", {})
	var pool: Array = P.get("pool", [72, 74, 76, 79, 81, 84])
	var notes = v.ro.get("notes")
	if not (notes is Array) or notes.is_empty():
		notes = [pool[randi() % pool.size()], pool[randi() % pool.size()], pool[randi() % pool.size()]]
	var peak := float(P.get("peak", 0.34))
	var stepT := float(P.get("step", 0.18))
	var end := t
	for k in notes.size():
		var m := int(notes[k])
		var key := str(m)
		var rate := 1.0
		if not files.has(key):
			var best := 72
			var bd := 999
			for f in files:
				if absi(int(f) - m) < bd:
					bd = absi(int(f) - m)
					best = int(f)
			key = str(best)
			rate = pow(2.0, (m - best) / 12.0)
		if files.has(key):
			_addSubStream(v, _lib.stream(files[key]), rate, t + k * stepT, (0.4 if k == 2 else 0.34) / peak, false)
		end = maxf(end, t + k * stepT + 0.45)
	return end

# ee_tracking_tones: 440 Hz reference + 440 + 2.5·d Hz (setDistance glides it), 0.15 s fade-in, endless.
func _tones(v: Voice, t: float) -> void:
	var P: Dictionary = _lib.parts.get("ee_tracking_tones", {})
	if not P.has("f"):
		return
	var s: AudioStream = _lib.stream(P.f, 0.0)
	v._fade = Param.new(0.0)
	v._fade.setValueAtTime(0.0, t)
	v._fade.linearRampToValueAtTime(1.0, t + float(P.get("fade", 0.15)))
	var d = v.ro.get("d")
	var hz := 440.0 + 2.5 * clampf(float(d) if d != null else 6.0, 0.0, 12.0)
	v._beat = Param.new(hz / 440.0)
	_addSubStream(v, s, 1.0, t, 1.0, true)
	var b = _addSubStream(v, s, hz / 440.0, t, 1.0, true)
	if b != null:
		b["beat"] = true

func _duplicate(id: String, recipe: Dictionary, opts: Dictionary) -> bool:
	var now := now()
	var gap := float(recipe.get("gap", 0.03))
	var p = opts.get("pos")
	var last = _last.get(id)
	if last != null and now - float(last.t) < gap:
		if p == null and not last.has:
			return true
		if p != null and last.has:
			var q := DAU.v3(p)
			if q.distance_squared_to(Vector3(last.x, last.y, last.z)) < 2.25:
				return true
	if last == null:
		last = {"t": 0.0, "has": false, "x": 0.0, "y": 0.0, "z": 0.0}
		_last[id] = last
	last.t = now
	last.has = p != null
	if p != null:
		var q := DAU.v3(p)
		last.x = q.x
		last.y = q.y
		last.z = q.z
	return false

func _enforceLimits(id: String, recipe: Dictionary) -> void:
	var limit := int(recipe.get("limit", 10))
	var now := now()
	var same := 0
	var oldest = null
	var live := 0
	var oldestAny = null
	for v in voices:
		if v.stopped or v.disposed or now >= v.end:
			continue
		live += 1
		if oldestAny == null and not v.looping:
			oldestAny = v
		if v.id == id:
			same += 1
			if oldest == null:
				oldest = v
	if same >= limit and oldest != null:
		oldest.stop(0.03)
	if live >= MAX_VOICES and oldestAny != null:
		oldestAny.stop(0.03)

# Loop scheduling, retriggers and disposal of finished voices.
func _schedule(now: float) -> void:
	var keep: Array = []
	for v in voices:
		v.update(now)
		if now > v.end + 0.15:
			v.dispose()
		else:
			keep.append(v)
	voices = keep

# Every frame, all states: voice gains / positions / scheduled starts, the music engine.
func _tick() -> void:
	if ctx == null or _n == null:
		return
	var now := now()
	_schedule(now)
	for v in voices:
		var g: float = v.gain.tick(now)
		if v._fade != null:
			g *= v._fade.tick(now)
		var bt := 1.0
		if v._beat != null:
			bt = v._beat.tick(now)
		var dead: Array = []
		for s in v.subs:
			if s.get("beat", false) and is_instance_valid(s.node):
				s.node.pitch_scale = bt
			if not _tickSub(v, s, now, g):
				dead.append(s)
		for s in dead:
			v.subs.erase(s)
	# world gain / duck / muffle automation
	var wg: float = _n.world.tick(now)
	var wi := AudioServer.get_bus_index("World")
	if wi >= 0:
		AudioServer.set_bus_volume_db(wi, linear_to_db(maxf(wg, 1e-5)))
		_setFilter(wi, _n.duckLp.tick(now))
	var mi := AudioServer.get_bus_index("Muffle")
	if mi >= 0:
		_setFilter(mi, _n.muffLp.tick(now))
	if _music != null:
		_music.update()

func _setFilter(bi: int, hz: float) -> void:
	if AudioServer.get_bus_effect_count(bi) < 1:
		return
	var f := AudioServer.get_bus_effect(bi, 0) as AudioEffectLowPassFilter
	if f == null:
		return
	var on := hz < 19500.0
	if AudioServer.is_bus_effect_enabled(bi, 0) != on:
		AudioServer.set_bus_effect_enabled(bi, 0, on)
	if on and absf(f.cutoff_hz - hz) > 0.5:
		f.cutoff_hz = hz

# One sub-player: start it at its time, set its volume; false once it has finished (freed).
func _tickSub(v: Voice, s: Dictionary, now: float, g: float) -> bool:
	var node = s.node
	if not is_instance_valid(node):
		return false
	if not s.started:
		if now < float(s.at):
			return true
		s.started = true
		node.play()
	elif not node.playing and not v.disposed:
		node.queue_free()
		return false
	var lin: float = g * float(s.k)
	if v.chain.positional:
		lin *= _distGain(v.chain)
	node.volume_db = linear_to_db(lin) if lin > 1e-5 else -100.0
	if v.chain.positional:
		_applyAir(node, v.chain)
	return true

# One-shot player on a bus outside any voice (music.gd: the select clack).
func _oneShotOnBus(rel: String, busName: String, at: float) -> void:
	var s: AudioStream = _lib.stream(rel)
	if s == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.bus = busName
	_node.add_child(p)
	p.finished.connect(p.queue_free)
	var delay := at - now()
	if delay > 0.004:
		game.get_tree().create_timer(delay).timeout.connect(func(): if is_instance_valid(p): p.play())
	else:
		p.play()

# ------------------------------------------------------------------------------------------------ music / global controls
func _startMusic() -> void:
	_regDefaults = {"bus": "music"}
	_music = MusicEngine.new(self)
	_regDefaults = null
	if _music != null and _musicState != null:
		music(_musicState)

func music(stateId) -> void:
	_musicState = stateId
	_amb.suspended = stateId == "silence"
	if _music != null:
		_music.setState(stateId)

func stopAll() -> void:
	for v in voices:
		v.stop(0.08)
	for h in _pending:
		h.stop()
	_pending = []
	_amb.handle = null
	_amb.hum = null
	_amb.id = null
	_amb.suspended = true
	_heart = null
	_lowHp = false
	if _music != null:
		_music.stop()

func duck(dbv = 0.0, lowpassHz = 20000.0, seconds = 0.0) -> void:
	if _n == null:
		return
	var now := now()
	var g = _n.world
	var f = _n.duckLp
	g.cancelScheduledValues(now)
	g.setTargetAtTime(pow(10.0, (float(dbv) if dbv != null else 0.0) / 20.0), now, 0.03)
	f.cancelScheduledValues(now)
	var hz := float(lowpassHz) if lowpassHz != null and float(lowpassHz) > 0.0 else 20000.0
	f.setTargetAtTime(clampf(hz, 60.0, 20000.0), now, 0.03)
	var s := float(seconds) if seconds != null else 0.0
	if s > 0.0 and is_finite(s):
		g.setTargetAtTime(1.0, now + s, 0.12)
		f.setTargetAtTime(20000.0, now + s, 0.12)

func setMasterVolume(v) -> void:
	setBusVolume("master", v)

func setBusVolume(name: String, v) -> void:
	if not volumes.has(name):
		return
	var x := float(v) if (v is float or v is int) else 0.0
	if is_nan(x):
		x = 0.0
	volumes[name] = clampf(x, 0.0, 1.5)
	if bus != null:
		_applyBusVolume(name)

func getBusVolume(name: String):
	return volumes.get(name)

# ------------------------------------------------------------------------------------------------ per-frame state
func _updateListener() -> void:
	var cam = game.get("camera")
	if not (cam is Camera3D) or not (cam as Camera3D).is_inside_tree():
		return
	var xf: Transform3D = (cam as Camera3D).global_transform
	var x := xf.origin
	var pl = game.get("player")
	var pp = pl.get("pos") if pl != null else null
	if pp != null:
		var q := DAU.v3(pp)
		x += (Vector3(q.x, q.y + 1.5, q.z) - x) * 0.6
	_lpos = x
	if is_instance_valid(_listener) and _listener.is_inside_tree():
		_listener.global_transform = Transform3D(xf.basis, x)
		if not _listener.is_current():
			_listener.make_current()

func _currentArea():
	var g = game
	var pl = g.get("player")
	if pl != null:
		var a = pl.get("area")
		if a != null and a != "":
			return a
		var pp = pl.get("pos")
		var lv = g.get("level")
		if pp != null and lv != null and lv.has_method("areaAt"):
			var q := DAU.v3(pp)
			return lv.areaAt(q.x, q.z)
	return null

func _updateArea() -> void:
	var area = _currentArea()
	if area == null:
		area = _area
	if area != null and area != _rv.area:
		_setReverb(area)
	_area = area
	_updateAmbience(area)

func _updateAmbience(area) -> void:
	var amb := _amb
	var st = game.get("state")
	var allowed: bool = not amb.suspended and (st == null or st == "" or st == "playing" or st == "down")
	var mach = game.get("machines")
	var power := bool(mach.get("powerOn")) if mach != null and mach.get("powerOn") != null else false
	var want = "amb_" + str(area) if allowed and area != null and cues.has("amb_" + str(area)) else null
	var level := 1.0 if power else 0.55
	if want != amb.id:
		if amb.handle != null:
			amb.handle.stop(1.5)
		amb.handle = loop(want, {"vol": 0.0}) if want != null else null
		if amb.handle != null:
			amb.handle.setVol(level, 1.5)
		amb.id = want
		amb.level = level
	elif amb.handle != null and amb.level != level:
		amb.handle.setVol(level, 2.0)
		amb.level = level
	var wantHum := allowed and not power
	if wantHum and amb.hum == null:
		amb.hum = loop("amb_hum")
	elif not wantHum and amb.hum != null:
		amb.hum.stop(2.0)
		amb.hum = null

func _updateHealth() -> void:
	var pl = game.get("player")
	if pl == null:
		return
	var mx := 0.0
	var mh = pl.get("maxHealth")
	if mh != null and float(mh) != 0.0:
		mx = float(mh)
	else:
		var mods = pl.get("mods")
		if mods != null and mods.get("maxHealth") != null and float(mods.get("maxHealth")) != 0.0:
			mx = float(mods.get("maxHealth"))
		else:
			mx = 150.0
	var h = pl.get("health")
	var hp := float(h) if h != null else mx
	var alive = pl.get("alive")
	var low: bool = alive != false and hp > 0.0 and hp / mx < LOW_HP
	if low == _lowHp:
		return
	_lowHp = low
	_n.muffLp.setTargetAtTime(1200.0 if low else 20000.0, now(), 0.25)
	if low:
		_heart = loop("heartbeat")
	elif _heart != null:
		_heart.stop(0.5)
		_heart = null

func _updatePrompt() -> void:
	var it = game.get("interact")
	var cur = it.get("current") if it != null else null
	if cur != null and cur != _prompt:
		play("ui_prompt")
	_prompt = cur

func _stopWorld() -> void:
	for v in voices:
		if v.chain.bus != "music" and v.chain.bus != "ui":
			v.stop(0.6)
	if _heart != null:
		_heart.stop(0.3)
		_heart = null
	_lowHp = false
	_amb.handle = null
	_amb.hum = null
	_amb.id = null
	if _n != null:
		_n.muffLp.setTargetAtTime(20000.0, now(), 0.2)

# ------------------------------------------------------------------------------------------------ event hookups
func _hookEvents() -> void:
	var ev = game.get("events")
	if ev == null or _hooked:
		return
	_hooked = true
	_on(ev, "zombie:hit", func(p): play("ui_hit_head" if p.get("head") else "ui_hit"))
	_on(ev, "zombie:kill", func(_p): play("ui_kill"))
	_on(ev, "player:step", func(p): _step(p))
	_on(ev, "player:jump", func(_p): play("jump"))
	_on(ev, "player:land", func(p): play("land", {"vol": clampf(float(p.get("speed", 6.0) if p.get("speed") != null else 6.0) / 10.0, 0.35, 1.0)}))
	_on(ev, "player:hurt", func(_p): _hurt())
	_on(ev, "points:change", func(p): _points(p))
	_on(ev, "points:denied", func(_p): play("ui_denied"))
	_on(ev, "weapon:fire", _evFire)
	_on(ev, "weapon:empty", func(_p): play("dry_fire"))
	_on(ev, "weapon:switch", func(_p): play("weapon_swap"))
	_on(ev, "weapon:melee", func(p): _melee(p))
	_on(ev, "weapon:acquire", _evAcquire)
	_on(ev, "powerup:spawn", func(p): play("pu_spawn", {"pos": p.get("pos")}))
	_on(ev, "powerup:grab", func(p): _powerup(p.get("type")))
	_on(ev, "powerup:end", _evPowerupEnd)
	_on(ev, "machine:commercial_start", func(_p): duck(-18, 800, 3.2))
	_on(ev, "game:start", _evGameStart)
	_on(ev, "game:over", func(_p): _stopWorld())
	_on(ev, "state", _evState)

func _evFire(p: Dictionary) -> void:
	var id = FIRE_CUES.get(p.get("weaponId"))
	if id != null:
		play(id, {"upgraded": bool(p.get("upgraded"))})

func _evAcquire(p: Dictionary) -> void:
	if p.get("source") == "wallbuy":
		play("wallbuy_boing")

func _evPowerupEnd(p: Dictionary) -> void:
	if p.get("type") == "please_stand_by":
		play("sting_back")

func _evGameStart(_p: Dictionary) -> void:
	_amb.suspended = false

func _evState(p: Dictionary) -> void:
	var to = p.get("to")
	if to == "menu" or to == "gameover" or to == "victory":
		_stopWorld()

# events.on wrapper: only once the engine exists, payload defaulting to {} (JS `fn(p || {})`).
func _on(ev, name: String, fn: Callable) -> void:
	ev.on(name, _guard.bind(fn))

func _guard(p, fn: Callable) -> void:
	if ctx != null:
		fn.call(p if p is Dictionary else {})

func _step(p: Dictionary) -> void:
	var pl = game.get("player")
	var pp = pl.get("pos") if pl != null else null
	if pp == null:
		return
	var perks = game.get("perks")
	if p.get("sprint") and perks != null and perks.has_method("has") and perks.has("roller_boogie"):
		play("skate_push", {"vol": 0.7})
		return
	var level = game.get("level")
	var surface = p.get("surface")
	if surface == null or surface == "":
		var q := DAU.v3(pp)
		surface = level.surfaceAt(q.x, q.z, q.y) if level != null and level.has_method("surfaceAt") else "tile"
	var id := "step_" + str(surface) if cues.has("step_" + str(surface)) else "step_tile"
	play(id, {"vol": 1.0 if p.get("sprint") else 0.75, "rate": 0.93 + randf() * 0.14, "foot": p.get("foot")})

func _hurt() -> void:
	var g = game
	var pl = g.get("player")
	var hero = pl.get("heroId") if pl != null else null
	play("hurt_grunt", {"base": HERO_VOICE.get(hero, 200)})
	play("hurt_static")
	var perks = g.get("perks")
	if perks != null and perks.has_method("has") and perks.has("wobble_up"):
		play("jelly_bwoing")

func _melee(p: Dictionary) -> void:
	play("melee_whoosh")
	var pl = game.get("player")
	var hero = pl.get("heroId") if pl != null else null
	if p.get("hit"):
		play("melee_hit_" + (str(hero) if HERO_VOICE.has(hero) else "skip"), {"delay": 0.04})

func _points(p: Dictionary) -> void:
	var d := float(p.get("delta", 0.0) if p.get("delta") != null else 0.0)
	if d < 0.0:
		play("ui_buy")
		return
	if d <= 0.0:
		return
	var pu = game.get("powerups")
	var active = pu.get("active") if pu != null else null
	if active is Dictionary and float(active.get("sweeps_week", 0.0) if active.get("sweeps_week") != null else 0.0) > 0.0:
		play("pu_sweeps_week", {"vol": 0.3, "flip": true})
	else:
		play("ui_points_flip")

func _powerup(type) -> void:
	if not PU_CUES.has(type):
		return
	play(PU_CUES[type])
	play("announcer_wahwah", {"rhythm": PU_RHYTHM[type], "delay": 0.55})
	if type == "cancelled":
		play("pu_sad_trombone", {"delay": 1.7})
	if type == "please_stand_by":
		play("pu_bossa_bed", {"delay": 0.3})

func _warn(key: String, e) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	push_warning("[audio] %s: %s" % [key, str(e)])
