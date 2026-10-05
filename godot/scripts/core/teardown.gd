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
const MAX_STEPS := 20000000

static func run(game: Node) -> Dictionary:
	var st := {"objects": 0, "orphans": 0}
	_disconnectSingletons()
	var seen := {}
	var vars := {}      # Script -> PackedStringArray of its plain script vars (accessor properties excluded)
	var stack: Array = [game]
	for g in ProjectSettings.get_global_class_list():
		var path: String = g.get("path", "")
		if path.ends_with(".gd") and ResourceLoader.has_cached(path):
			stack.append(load(path))
	var steps := 0
	while not stack.is_empty():
		steps += 1
		if steps > MAX_STEPS:
			push_warning("[teardown] gave up after %d steps" % steps)
			break
		var v = stack.pop_back()
		match typeof(v):
			TYPE_ARRAY:
				var a: Array = v
				if a.is_read_only() or a.is_empty():
					continue
				var tb := a.get_typed_builtin()
				if a.is_typed() and tb != TYPE_OBJECT and tb != TYPE_ARRAY and tb != TYPE_DICTIONARY and tb != TYPE_CALLABLE:
					continue
				if a.is_typed():
					stack.append_array(a)
				else:
					for e in a:
						var te := typeof(e)
						if te >= TYPE_OBJECT and te <= TYPE_ARRAY:   # Object, Callable, Signal, Dictionary, Array
							stack.append(e)
				a.clear()
			TYPE_DICTIONARY:
				var d: Dictionary = v
				if d.is_read_only() or d.is_empty():
					continue
				for k in d:
					var tk := typeof(k)
					if tk >= TYPE_OBJECT and tk <= TYPE_ARRAY:
						stack.append(k)
					var e = d[k]
					var te := typeof(e)
					if te >= TYPE_OBJECT and te <= TYPE_ARRAY:
						stack.append(e)
				d.clear()
			TYPE_OBJECT:
				if not is_instance_valid(v):
					continue
				var o: Object = v
				var id := o.get_instance_id()
				if seen.has(id):
					continue
				seen[id] = true
				_object(o, stack, vars)
	_freeOrphans(game, st, seen)
	st.objects = seen.size()
	return st

# Frees the Nodes that are not in the tree: model / effect pools, prop prototypes, detached rooms. The root Window
# and the Game's ancestors are skipped: the engine is deleting them right now (the Game is deleted as a child).
# Node.get_orphan_node_ids() is empty in release export templates, so the roots of the off-tree Nodes reached by
# the walk (`seen`) are freed too; without that an exported build aborted on exit (leaked geometry instances).
static func _freeOrphans(game: Node, st: Dictionary, seen: Dictionary) -> void:
	var roots := {}
	for nid in ClassDB.class_call_static("Node", "get_orphan_node_ids"):
		roots[nid] = true
	for oid in seen:
		var o = instance_from_id(oid)
		if o == null or not is_instance_valid(o) or not (o is Node) or o.is_inside_tree():
			continue
		var top: Node = o
		while top.get_parent() != null:
			top = top.get_parent()
		roots[top.get_instance_id()] = true
	for nid in roots:
		var n = instance_from_id(nid)
		if n == null or not is_instance_valid(n) or not (n is Node):
			continue
		if n.get_parent() != null or n.is_inside_tree() or n == game or n is Window or n.is_ancestor_of(game):
			continue
		# only game content (3D nodes, canvas items, viewports and plain nodes the scripts made)
		if not (n is Node3D or n is CanvasItem or n is Viewport or n is CanvasLayer or n.get_script() != null or n.get_class() == "Node"):
			continue
		n.free()
		st.orphans += 1

static func _object(o: Object, stack: Array, vars: Dictionary) -> void:
	if o is GDScript:
		var sc: GDScript = o
		for p in sc.get_property_list():       # static vars
			if p.usage & SCRIPT_VAR:
				_take(sc, p.name, stack)
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
	var names = vars.get(s)
	if names == null:
		names = _scriptVars(s)
		vars[s] = names
	for n in names:
		_take(o, n, stack)

# Plain member vars of a script (with its base scripts). Accessor properties (get:/set: blocks) are skipped: they
# are computed from other vars and must not run here.
static func _scriptVars(s: Script) -> PackedStringArray:
	var methods := {}
	var sc: Script = s
	while sc != null:
		for m in sc.get_script_method_list():
			methods[m.name] = true
		sc = sc.get_base_script()
	var out := PackedStringArray()
	for p in s.get_script_property_list():
		if p.usage & SCRIPT_VAR and not methods.has("@%s_getter" % p.name) and not methods.has("@%s_setter" % p.name):
			out.append(p.name)
	return out

# Queues a var's value and releases it (containers are emptied when popped; Objects / Callables nulled).
static func _take(o: Object, name: String, stack: Array) -> void:
	if o is GDScript and (o.has_method("@%s_getter" % name) or o.has_method("@%s_setter" % name)):
		return
	var v = o.get(name)
	match typeof(v):
		TYPE_ARRAY, TYPE_DICTIONARY:
			stack.append(v)
		TYPE_OBJECT:
			if v != null:
				stack.append(v)
				o.set(name, null)
		TYPE_CALLABLE:
			var c: Callable = v
			if c.is_valid():
				var t = c.get_object()
				if t != null:
					stack.append(t)
				o.set(name, Callable())

# Script callables connected to engine singletons (lambdas keep their captures alive).
static func _disconnectSingletons() -> void:
	for obj in [RenderingServer, Input, AudioServer, PhysicsServer3D, ProjectSettings]:
		for sig in obj.get_signal_list():
			for c in obj.get_signal_connection_list(sig.name):
				var cb: Callable = c.callable
				var tgt = cb.get_object()
				if tgt != null and tgt.get_script() != null:
					obj.disconnect(sig.name, cb)
