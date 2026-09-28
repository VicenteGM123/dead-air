# A WebAudio AudioParam automation timeline evaluated at control rate (once per frame) — engine glue for the port of
# src/audio/audio.js / music.js, whose gains, filter frequencies and fades are AudioParam automations. Supports the
# calls the JS makes: setValueAtTime, linearRampToValueAtTime, setTargetAtTime, cancelScheduledValues,
# cancelAndHoldAtTime (holdAt / synth.release). tick(now) advances to `now` and returns the value.
extends RefCounted

var value := 0.0
var _ev: Array = []        # sorted by t: { k: 0 set | 1 linear | 2 target, t, v, tau }
var _tgt = null            # active setTarget event
var _t0 := 0.0             # time / value where the next linear ramp starts (the previous event)
var _v0 := 0.0
var _now := 0.0

func _init(v := 0.0) -> void:
	value = v
	_v0 = v

func _add(e: Dictionary) -> void:
	var i := _ev.size()
	while i > 0 and float(_ev[i - 1].t) > float(e.t):
		i -= 1
	_ev.insert(i, e)

func setValueAtTime(v: float, t: float) -> void:
	_add({"k": 0, "t": t, "v": v})

func linearRampToValueAtTime(v: float, t: float) -> void:
	_add({"k": 1, "t": t, "v": v})

func setTargetAtTime(v: float, t: float, tau: float) -> void:
	_add({"k": 2, "t": t, "v": v, "tau": maxf(tau, 1e-4)})

func cancelScheduledValues(t: float) -> void:
	_ev = _ev.filter(func(e): return float(e.t) < t)

# Freezes the value at `t` (the current value when t <= now) and drops everything scheduled from t on.
func cancelAndHoldAtTime(t: float) -> void:
	cancelScheduledValues(t)
	if t <= _now:
		_tgt = null
		_t0 = _now
		_v0 = value
	else:
		# hold whatever the curve reaches at t: approximate with the value then (evaluated when reached)
		_add({"k": 3, "t": t, "v": 0.0})

func tick(now: float) -> float:
	var last := _now
	while not _ev.is_empty() and float(_ev[0].t) <= now:
		var e: Dictionary = _ev.pop_front()
		var et := float(e.t)
		if _tgt != null:
			value = float(_tgt.v) + (value - float(_tgt.v)) * exp(-maxf(0.0, et - maxf(last, float(_tgt.t))) / float(_tgt.tau))
		match int(e.k):
			0:
				value = float(e.v)
				_tgt = null
			1:
				value = float(e.v)
				_tgt = null
			2:
				_tgt = e
			3:
				_tgt = null
		_t0 = et
		_v0 = value
		last = et
	if not _ev.is_empty() and int(_ev[0].k) == 1:
		var e: Dictionary = _ev[0]
		var span := float(e.t) - _t0
		var x := clampf((now - _t0) / span, 0.0, 1.0) if span > 0.0 else 1.0
		value = lerpf(_v0, float(e.v), x)
	elif _tgt != null:
		value = float(_tgt.v) + (value - float(_tgt.v)) * exp(-maxf(0.0, now - maxf(last, float(_tgt.t))) / float(_tgt.tau))
	_now = now
	return value

# True while automation is still scheduled or a setTarget has not settled.
func busy() -> bool:
	return not _ev.is_empty() or (_tgt != null and absf(value - float(_tgt.v)) > 1e-4)
