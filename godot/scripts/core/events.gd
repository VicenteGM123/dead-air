# EventBus: tiny synchronous pub/sub used by every system (port of src/core/events.js; ARCHITECTURE §4 lists the
# canonical events). Event names and payload keys are exactly the JS ones ('zombie:kill', { z, cause, ... }).
# Payloads are Dictionaries (or null). on() returns an unsubscribe Callable.
# GDScript has no try/catch: a listener that errors aborts itself only (Godot logs the error and continues).
extends RefCounted

var _map := {}

# Subscribe; returns an unsubscribe Callable.
func on(name: String, fn: Callable) -> Callable:
	if not _map.has(name):
		_map[name] = []
	_map[name].append(fn)
	return func(): off(name, fn)

# Subscribe for a single emission.
func once(name: String, fn: Callable) -> Callable:
	var holder := {"wrap": Callable()}
	holder.wrap = func(p):
		off(name, holder.wrap)
		fn.call(p)
	return on(name, holder.wrap)

func off(name: String, fn: Callable) -> void:
	var list: Array = _map.get(name, [])
	var i := list.find(fn)
	if i >= 0:
		list.remove_at(i)

func emit(name: String, payload = null) -> void:
	var list: Array = _map.get(name, [])
	if list.is_empty():
		return
	# Iterate over a snapshot: listeners may unsubscribe while being called.
	for fn in list.duplicate():
		if fn.is_valid():
			if fn.get_argument_count() == 0:
				fn.call()
			else:
				fn.call(payload)

func clear() -> void:
	_map.clear()
