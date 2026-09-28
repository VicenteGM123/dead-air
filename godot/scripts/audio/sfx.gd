# Cue library: the offline renders of the web build's WebAudio recipes (the data side of src/audio/sfx.js SFX_CUES and
# of src/audio/music.js MUSIC_CUES; SPEC §7). tools/audio/render.mjs runs the ORIGINAL recipes and writes
# res://assets/audio/**.ogg + index.json; this file loads the index, caches the streams and picks the file for a
# play(id, opts) call: the parameter variant (upgraded, rhythm, base, dur, syllables, flip, claps, auto), the
# TV-speaker render when the voice is heard through a TV, the nearest rendered pitch (rate · 2^(detune/1200); the
# remainder becomes pitch_scale) and a random variation (never the same one twice in a row).
#
# index.json (written by render.mjs; see tools/audio/README.md):
#   cues[id] = { bus, tv, zombie, range, ref, wet, limit, gap, loopable, music, pitch, reads, params, inherent,
#                variants: [{ k: variant key, o: opts, tv, sets: [{ p: pitch, f: [{ f: file, e: end, l: length, k: gain }] }] }],
#                loop: { f, s: loop start, e: loop end (= file end), tv, k } | null }
#   parts = { telly_surf_arp: { f: {midi: file}, tv }, toy_xylophone: { f: {midi: file}, peak, step, pool },
#             ee_tracking_tones: { f, hz, fade } }
#   music = { states: { id: { fade, delay, bpm, barDur, beatDur, bars, stems: { name: { f, s, e, k } } } }, clack }
# The JS synth toolkit itself (tone/noise/formant/... builders) has no runtime counterpart: nothing is synthesised live.
extends RefCounted

const ROOT := "res://assets/audio/"
# Same order and formatting as render.mjs PARAMS / variantKey().
const PARAMS := ["upgraded", "flip", "base", "rhythm", "syllables", "claps", "dur", "auto"]

var ok := false
var cues := {}
var parts := {}
var music := {}
var _streams := {}
var _last := {}
var _warned := {}
var _queue: Array = []       # files still to request from the threaded loader
var _requested := {}         # path -> true while a threaded load is pending

func _init() -> void:
	var path := ROOT + "index.json"
	if not FileAccess.file_exists(path):
		push_warning("[audio] %s missing: run `npm run audio` (tools/audio/render.mjs)" % path)
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (d is Dictionary):
		push_warning("[audio] index.json unreadable")
		return
	cues = d.get("cues", {})
	parts = d.get("parts", {})
	music = d.get("music", {}) if d.get("music") is Dictionary else {}
	ok = true
	# every one-shot file, queued for background loading (preloadStep) so a first play never stalls a frame
	for id in cues:
		for v in cues[id].get("variants", []):
			for s in v.sets:
				for f in s.f:
					_queue.append(f.f)
		if cues[id].get("loop") is Dictionary:
			_queue.append(cues[id].loop.f)
	for k in parts:
		var fs = parts[k].get("f")
		if fs is Dictionary:
			_queue.append_array(fs.values())
		elif fs is String:
			_queue.append(fs)
	for k in music.get("states", {}):
		for stem in music.states[k].get("stems", {}).values():
			_queue.append(stem.f)
	_queue.reverse()      # pop_back() then serves the first cues (and the music last)

# Requests a few queued files from ResourceLoader's threaded loader (called every frame by audio.gd).
func preloadStep(n := 16) -> void:
	while n > 0 and not _queue.is_empty():
		var rel: String = _queue.pop_back()
		n -= 1
		var path := ROOT + rel
		if _streams.has(rel) or _requested.has(path) or not ResourceLoader.exists(path):
			continue
		if ResourceLoader.load_threaded_request(path) == OK:
			_requested[path] = true

# ------------------------------------------------------------------------------------------------ streams
# Loads (and caches) one rendered file. Looped streams get loop / loop_offset set once (each file is either always
# looped or never). Imported resources are used when present; raw files are decoded directly otherwise.
func stream(rel: String, loop_start := -1.0) -> AudioStream:
	if _streams.has(rel):
		return _streams[rel]
	var path := ROOT + rel
	var s: AudioStream = null
	if _requested.has(path):
		_requested.erase(path)
		s = ResourceLoader.load_threaded_get(path) as AudioStream
	if s == null and ResourceLoader.exists(path):
		s = load(path) as AudioStream
	if s == null and FileAccess.file_exists(path):
		if rel.ends_with(".ogg"):
			s = AudioStreamOggVorbis.load_from_file(ProjectSettings.globalize_path(path))
		elif rel.ends_with(".wav"):
			s = AudioStreamWAV.load_from_file(ProjectSettings.globalize_path(path))
	if s == null:
		if not _warned.has(rel):
			_warned[rel] = true
			push_warning("[audio] missing file " + path)
		_streams[rel] = null
		return null
	if loop_start >= 0.0:
		if s is AudioStreamOggVorbis:
			(s as AudioStreamOggVorbis).loop = true
			(s as AudioStreamOggVorbis).loop_offset = loop_start
		elif s is AudioStreamWAV:
			var w := s as AudioStreamWAV
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = int(round(loop_start * w.mix_rate))
			w.loop_end = int(round(w.get_length() * w.mix_rate))
	_streams[rel] = s
	return s

# ------------------------------------------------------------------------------------------------ variants
static func fmtNum(x: float) -> String:
	var r := roundf(x * 1000.0) / 1000.0
	if r == floorf(r):
		return "%d" % int(r)
	return String.num(r)

static func fmtVal(v) -> String:
	if v is bool:
		return "1"
	if v is Array or v is PackedFloat32Array or v is PackedFloat64Array:
		if v.is_empty():
			return "[]"
		var s := []
		for x in v:
			s.append(fmtNum(float(x)))
		return ",".join(s)
	return fmtNum(float(v))

# Canonical variant key of a play opts dictionary for a cue reading `params` (render.mjs variantKey): params equal to
# the recipe's default (index `defaults`) select the default variant.
static func variantKey(params: Array, opts: Dictionary, defaults = null) -> String:
	var out := []
	for k in PARAMS:
		if not params.has(k):
			continue
		var v = opts.get(k)
		if v == null or (v is bool and v == false):
			continue
		if defaults is Dictionary and defaults.has(k) and fmtVal(defaults[k]) == fmtVal(v):
			continue
		out.append(k + "=" + fmtVal(v))
	return ";".join(out)

static func _keyParams(key: String) -> Dictionary:
	var d := {}
	if key == "":
		return d
	for part in key.split(";"):
		var i := part.find("=")
		d[part.substr(0, i)] = part.substr(i + 1)
	return d

# Picks a variant for (opts, wantTv): the exact key, else the closest one (numeric params by ratio), preferring the
# requested TV-ness. Returns the variant Dictionary or null.
func variantFor(entry: Dictionary, opts: Dictionary, wantTv: bool):
	var vs: Array = entry.get("variants", [])
	if vs.is_empty():
		return null
	var key := variantKey(entry.get("params", []), opts, entry.get("defaults"))
	var want := _keyParams(key)
	var best = null
	var bestScore := INF
	for v in vs:
		var score := 0.0
		if bool(v.get("tv", false)) != wantTv:
			score += 100.0
		if v.k != key:
			var have := _keyParams(v.k)
			for p in want:
				if not have.has(p):
					score += 1.0
				elif have[p] != want[p]:
					var a := String(want[p]).to_float()
					var b := String(have[p]).to_float()
					score += absf(log(maxf(a, 1e-3) / maxf(b, 1e-3))) if a > 0.0 and b > 0.0 and not String(want[p]).contains(",") else 1.0
			for p in have:
				if not want.has(p):
					score += 1.0
			if v.k == "":
				score += 0.01
		if score < bestScore:
			bestScore = score
			best = v
	return best

# The file for one voice: { file: {f, e, l, k}, rate: residual pitch_scale, tv: rendered through the TV speaker }.
func pick(id: String, opts: Dictionary, pitch: float, wantTv: bool):
	var entry = cues.get(id)
	if entry == null:
		return null
	var v = variantFor(entry, opts, wantTv)
	if v == null:
		return null
	var sets: Array = v.sets
	var best = null
	var bd := INF
	for s in sets:
		var d := absf(log(maxf(pitch, 1e-3) / float(s.p)))
		if d < bd:
			bd = d
			best = s
	if best == null or best.f.is_empty():
		return null
	var files: Array = best.f
	var lk := "%s|%s|%s" % [id, v.k, str(best.p)]
	var i := randi() % files.size()
	if files.size() > 1 and _last.get(lk, -1) == i:
		i = (i + 1 + randi() % (files.size() - 1)) % files.size()
	_last[lk] = i
	var rate := pitch / float(best.p) if entry.get("pitch", false) else 1.0
	return {"file": files[i], "rate": rate, "tv": bool(v.get("tv", false))}
