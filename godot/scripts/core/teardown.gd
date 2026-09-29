# Exit-time teardown (Godot-only plumbing, no JS counterpart). Called once by game.gd when the Game node is deleted
# (the tree is being finalized after get_tree().quit() or a window close).
#
# The systems are RefCounted objects that reference each other through Arrays / Dictionaries / lambdas (and keep
# pools of Nodes that are not in the tree), and many scripts keep caches in `static var`s (materials, meshes,
# textures, model pools). None of that is released by the engine on its own: reference cycles are never broken
# and static vars live until the GDScript itself is freed, which cannot happen while its instances are alive. The
# result was a slow shutdown with thousands of "ObjectDB instances leaked", "resources still in use", RID leaks and
# sometimes a SIGABRT (exit 134) while the rendering server tore down instances of leaked geometry.
#
# run() walks the object graph from the Game node (every system, every script-level var, static vars of every
# script reached and of every class_name script, Node children and metadata), empties every Array / Dictionary,
# nulls every Object / Callable script var (which breaks all cycles), disconnects script callables from engine
# singletons, and finally frees the Nodes that are not in the tree (pools, prototypes, cached prop instances).
# Nothing here runs during play.
extends RefCounted

const SCRIPT_VAR := PROPERTY_USAGE_SCRIPT_VARIABLE

static func run(game: Node) -> Dictionary:
	var st := {"objects": 0, "orphans": 0}
	_disconnectSingletons()
	var seen := {}
	var stack: Array = [game]
	for g in ProjectSettings.get_global_class_list():
		var path: String = g.get("path", "")
		if path.ends_with(".gd") and ResourceLoader.has_cached(path):
			stack.append(load(path))
	var steps := 0
	while not stack.is_empty():
		steps += 1
		if steps % 200000 == 0:
			print("[teardown] dbg steps=%d stack=%d seen=%d top=%s" % [steps, stack.size(), seen.size(), type_string(typeof(stack[-1]))])
		if steps > 20000000:
			push_warning("[teardown] gave up after %d steps" % steps)
			break
		var v = stack.pop_back()
		match typeof(v):
			TYPE_ARRAY:
				var a: Array = v
				if a.is_read_only() or a.is_empty():
					continue
				if a.is_typed() and a.get_typed_builtin() != TYPE_OBJECT and a.get_typed_builtin() != TYPE_ARRAY \
						and a.get_typed_builtin() != TYPE_DICTIONARY and a.get_typed_builtin() != TYPE_CALLABLE:
					continue
				stack.append_array(a)
				a.clear()
			TYPE_DICTIONARY:
				var d: Dictionary = v
				if d.is_read_only() or d.is_empty():
					continue
				stack.append_array(d.keys())
				stack.append_array(d.values())
				d.clear()
			TYPE_OBJECT:
				if not is_instance_valid(v):
					continue
				var o: Object = v
				var id := o.get_instance_id()
				if seen.has(id):
					continue
				seen[id] = true
				if seen.size() % 20000 == 0:
					print("[teardown] dbg obj ", o, " ", o.get_script().resource_path if o.get_script() else "")
				_object(o, stack, st)
	# free the Nodes that are not in the tree: model / effect pools, prop prototypes, detached rooms
	var ids: Array = ClassDB.class_call_static("Node", "get_orphan_node_ids")
	for nid in ids:
		var n = instance_from_id(nid)
		if n == null or not is_instance_valid(n) or not (n is Node):
			continue
		if n.get_parent() != null or n.is_inside_tree() or n == game:
			continue
		# only game content (3D nodes, canvas items, viewports and plain nodes the scripts made)
		if not (n is Node3D or n is CanvasItem or n is Viewport or n is CanvasLayer or n.get_script() != null or n.get_class() == "Node"):
			continue
		n.free()
		st.orphans += 1
	st.objects = seen.size()
	return st

static func _object(o: Object, stack: Array, st: Dictionary) -> void:
	if o is GDScript:
		var sc: GDScript = o
		for p in sc.get_property_list():
			if p.usage & SCRIPT_VAR:
				_take(sc, p, stack)
		for c in sc.get_script_constant_map().values():
			if c is GDScript:
				stack.append(c)
		var base = sc.get_base_script()
		if base != null:
			stack.append(base)
		return
	if o is Node:
		stack.append_array((o as Node).get_children(true))
		for m in o.get_meta_list():
			stack.append(o.get_meta(m))
	var s = o.get_script()
	if s == null:
		return
	stack.append(s)
	for p in o.get_property_list():
		if p.usage & SCRIPT_VAR:
			_take(o, p, stack)

# Queues a script var's value and releases it (containers are emptied when popped; Objects / Callables nulled).
static func _take(o: Object, p: Dictionary, stack: Array) -> void:
	# accessor properties (get:/set: blocks) are computed from other vars: never evaluate them here
	if o.has_method("@%s_getter" % p.name) or o.has_method("@%s_setter" % p.name):
		return
	var v = o.get(p.name)
	match typeof(v):
		TYPE_ARRAY, TYPE_DICTIONARY:
			stack.append(v)
		TYPE_OBJECT:
			if v != null:
				stack.append(v)
				o.set(p.name, null)
		TYPE_CALLABLE:
			var c: Callable = v
			if c.is_valid():
				var t = c.get_object()
				if t != null:
					stack.append(t)
				o.set(p.name, Callable())

# Script callables connected to engine singletons (lambdas keep their captures alive).
static func _disconnectSingletons() -> void:
	for obj in [RenderingServer, Input, AudioServer, PhysicsServer3D, ProjectSettings]:
		for sig in obj.get_signal_list():
			for c in obj.get_signal_connection_list(sig.name):
				var cb: Callable = c.callable
				var tgt = cb.get_object()
				if tgt != null and tgt.get_script() != null:
					obj.disconnect(sig.name, cb)
