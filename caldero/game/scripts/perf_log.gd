extends Node
class_name PerfLog
## --- R6 PERF: registro de tiempos para buscar tirones (solo para pruebas; el juego normal no lo crea).
## --perflog=<archivo> en escritorio, --perflog=console en la web (cada línea sale por la consola con «PERF »).
## Anota cada cuadro dibujado (señal RenderingServer.frame_post_draw): ms desde el cuadro anterior (dt), tiempo de los
## scripts (proc), de física (phys), llamadas de dibujo, objetos, memoria de texturas y los contadores de compilación
## de shaders que dé el renderizador. Y cada paso medido con PerfLog.step() / PerfLog.mark() con su hora exacta:
##   var t := PerfLog.t0()
##   ... trabajo ...
##   PerfLog.step("ev:build", t)        # «S t=<inicio> dur=<ms> ev:build»
##   PerfLog.mark("ev:fade_in")          # «M t=<ms> ev:fade_in»
## Las horas son ms desde que empezó el registro; un paso cae en el cuadro cuyo intervalo contiene su inicio.

static var on := false
static var _inst: PerfLog
static var _console := false
static var _file: FileAccess
static var _t_start := 0
static var _t_last := 0
static var _frame := 0
static var _sched := PackedInt64Array([0, 0])   # (Linux) tiempo de CPU del hilo principal y espera en la cola, en ns

## Empieza a anotar. out: ruta de un archivo o "console".
static func start(parent: Node, out: String) -> void:
	if _inst != null:
		return
	on = true
	_console = out == "console" or OS.has_feature("web")
	if not _console:
		_file = FileAccess.open(out, FileAccess.WRITE)
		if _file == null:
			_console = true
	_inst = PerfLog.new()
	_inst.name = "PerfLog"
	_inst.process_mode = Node.PROCESS_MODE_ALWAYS
	parent.add_child(_inst)
	_t_start = Time.get_ticks_usec()
	_t_last = _t_start
	RenderingServer.viewport_set_measure_render_time(parent.get_viewport().get_viewport_rid(), true)
	if DisplayServer.get_name() == "headless":   # sin dibujo (--headless): un «cuadro» por cada vuelta de proceso
		parent.get_tree().process_frame.connect(_inst._on_post_draw)
	else:
		RenderingServer.frame_post_draw.connect(_inst._on_post_draw)
	_emit("# perflog start %s %s | %s | %s" % [Engine.get_version_info().get("string", ""), OS.get_name(),
		RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_api_version()])
	if OS.has_feature("web"):
		# la hora de la página (performance.now) en t=0: para alinear con los requestAnimationFrame de la prueba web
		_emit("# web_t0=%.1f" % float(JavaScriptBridge.eval("performance.now()", true)))

static func t0() -> int:
	return Time.get_ticks_usec()

static func now_ms() -> float:
	return (Time.get_ticks_usec() - _t_start) / 1000.0

## Un paso medido: empezó en `since` (PerfLog.t0()) y termina ahora.
static func step(label: String, since: int) -> void:
	if not on:
		return
	var t := Time.get_ticks_usec()
	_emit("S t=%.1f dur=%.2f %s" % [(since - _t_start) / 1000.0, (t - since) / 1000.0, label])

## Un instante.
static func mark(label: String) -> void:
	if not on:
		return
	_emit("M t=%.1f %s" % [now_ms(), label])

static func _emit(line: String) -> void:
	if _console:
		print("PERF ", line)
	elif _file:
		_file.store_line(line)

static func stop() -> void:
	if _file:
		_file.flush()
		_file.close()
		_file = null
	on = false

func _on_post_draw() -> void:
	var t := Time.get_ticks_usec()
	var dt := (t - _t_last) / 1000.0
	_t_last = t
	_frame += 1
	var vp := get_viewport().get_viewport_rid()
	var info := func(k: int) -> int: return RenderingServer.get_rendering_info(k)
	var comp := "%d/%d/%d/%d/%d" % [info.call(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS),
		info.call(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH),
		info.call(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE),
		info.call(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW),
		info.call(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION)]
	# cpu = ms de CPU del hilo principal en este cuadro, rq = ms esperando CPU (la máquina ocupada por otros procesos):
	# con la máquina cargada el dt engaña; cpu dice cuánto trabajo hizo el juego en el cuadro
	var cpu := -1.0
	var rq := -1.0
	if OS.get_name() == "Linux":
		var f := FileAccess.open("/proc/thread-self/schedstat", FileAccess.READ)
		if f:
			var v := f.get_line().split(" ")
			if v.size() >= 2:
				var c := int(v[0])
				var w := int(v[1])
				if _sched[0] > 0:
					cpu = (c - _sched[0]) / 1e6
					rq = (w - _sched[1]) / 1e6
				_sched[0] = c
				_sched[1] = w
	_emit("F %d t=%.1f dt=%.2f proc=%.2f phys=%.2f rcpu=%.2f draws=%d objs=%d tex=%.1f comp=%s cpu=%.1f rq=%.1f" % [_frame,
		(t - _t_start) / 1000.0, dt,
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu(),
		info.call(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		info.call(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		info.call(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) / 1048576.0, comp, cpu, rq])

func _exit_tree() -> void:
	stop()
