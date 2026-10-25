extends Node
class_name TextLog
## --- R5 MERGE: registro de depuración de TODO el texto que se ve (solo con --textlog=<archivo>; nunca en el juego normal).
## Cada pocos cuadros mira los Control visibles (Label, RichTextLabel, Button, LineEdit, pestañas, y el tooltip de
## cualquier Control) y los Label3D visibles; cada texto nuevo va una sola vez al archivo, con el cuadro, el tipo de
## nodo, su nombre y el panel abierto. Lo que se dibuja con draw_string (el mapa del viaje, los números del trazo de la
## runa) llega con TextLog.note(). Sirve para buscar restos de español y textos rotos (%s, {n}...) en todo el juego.
##   godot --path game -- --demo=<x> --textlog=/ruta/x.txt

static var _inst: TextLog = null

var _f: FileAccess = null
var _seen := {}
var _nodes: Array = []       # los nodos que pueden mostrar texto (se agregan al entrar al árbol)
var _tick := 0
var _main: Node = null

## main.gd la crea si viene --textlog=<archivo>.
static func start(main: Node, path: String) -> void:
	if _inst != null:
		return
	var t := TextLog.new()
	t.name = "TextLog"
	t._main = main
	t._f = FileAccess.open(path, FileAccess.WRITE)
	if t._f == null:
		push_warning("TextLog: no se pudo abrir " + path)
		return
	_inst = t
	t.process_mode = Node.PROCESS_MODE_ALWAYS
	main.add_child(t)

## Un texto que no está en un nodo de texto (draw_string): se anota si el registro está activo.
static func note(kind: String, text: String) -> void:
	if _inst != null and text != "":
		_inst._rec(kind, "draw", "", text)

func _ready() -> void:
	get_tree().node_added.connect(_on_added)
	_collect(get_tree().root)
	print("TEXTLOG on")

func _collect(n: Node) -> void:
	_on_added(n)
	for c in n.get_children():
		_collect(c)

func _on_added(n: Node) -> void:
	if n is Control or n is Label3D:
		_nodes.append(n)

func _process(_d: float) -> void:
	_tick += 1
	if _tick % 3 != 0:
		return
	var keep: Array = []
	for n in _nodes:
		if not is_instance_valid(n) or not n.is_inside_tree():
			continue
		keep.append(n)
		_check(n)
	_nodes = keep

func _check(n: Node) -> void:
	if not (n as Node).call("is_visible_in_tree"):
		return
	var t := ""
	if n is Label:
		t = (n as Label).text
	elif n is RichTextLabel:
		t = (n as RichTextLabel).text
	elif n is Button:
		t = (n as Button).text
	elif n is LineEdit:
		t = (n as LineEdit).text + ("" if (n as LineEdit).placeholder_text == "" else " | " + (n as LineEdit).placeholder_text)
	elif n is Label3D:
		t = (n as Label3D).text
	elif n is TabBar:
		var tb := n as TabBar
		for i in tb.tab_count:
			t += ("" if i == 0 else " | ") + tb.get_tab_title(i)
	elif n is TabContainer:
		var tc := n as TabContainer
		for i in tc.get_tab_count():
			t += ("" if i == 0 else " | ") + tc.get_tab_title(i)
	if t.strip_edges() != "":
		_rec("text", n.get_class(), String(n.name), t)
	if n is Control and (n as Control).tooltip_text != "":
		_rec("tip", n.get_class(), String(n.name), (n as Control).tooltip_text)

func _rec(kind: String, cls: String, nname: String, t: String) -> void:
	var key := kind + "\u0001" + t
	if _seen.has(key):
		return
	_seen[key] = true
	var panel := ""
	if _main and _main.get("ov") != null and is_instance_valid(_main.ov):
		panel = String(_main.ov.current)
	_f.store_line("%d\t%s\t%s\t%s\t%s\t%s" % [Engine.get_process_frames(), kind, cls, nname, panel, t.replace("\n", "\\n")])
	_f.flush()

func _exit_tree() -> void:
	if _inst == self:
		_inst = null
	if _f:
		_f.flush()
