extends RefCounted
class_name ZCheck
## --- R5 WORLD: el comprobador de «paredes que tiemblan» (z-fighting). Solo para pruebas (no se usa al jugar).
##
## Uso: godot --path game --rendering-driver opengl3 -- --demo=zcheck --view=<vista> [--out=<carpeta>] [--shots]
##      [--film] [--noupgrades]
## Vistas: shop_day, shop_morning, shop_night, title, ending, market, academia, concurso, torneo, geo_all (solo la
## parte geométrica de todas, sin pantalla: sirve con --headless).
##
## 1) Geometría: junta las caras (triángulos en el espacio del mundo) de todo lo que se ve: MeshInstance3D (cajas,
##    cuadros, planos, prismas, cilindros, mallas hechas con SurfaceTool), MultiMesh, Sprite3D / AnimatedSprite3D y
##    Label3D que no miran a la cámara (los que sí, y lo que no prueba la profundidad, no pueden pelear). Informa cada
##    par de caras de objetos distintos que están en el mismo plano (a menos de 3 mm, normales paralelas, de frente o
##    de espaldas) y se tapan con área, y cada par paralelo y cercano (3 mm a 6 cm) que un búfer de profundidad de 24
##    bits no separa bien a la distancia de la cámara. Cada par sale con su clase:
##      SAME  las dos caras miran al mismo lado: pelean (z-fighting) si se ven;
##      DBL   miran a lados opuestos pero una es de dos caras (sprite, cull_disabled): pelean desde un lado;
##      OPP   opuestas y de una cara: inofensivo (una de las dos siempre está de espaldas);
##      LOOK  SAME, pero con el mismo material y la misma proyección triplanar del mundo: el mismo color, no se nota.
##    Imprime «ZCHECK ...» y escribe <out>/<vista>_geo.txt.
## 2) --shots: para cada parada de la cámara, 8 capturas con el tiempo congelado moviendo solo los planos near/far de
##    la cámara (cambia la profundidad y nada más: lo que cambia de color entre capturas es z-fighting; el sol no hace
##    sombra mientras tanto, porque su mapa de sombras se reparte según near/far) y 8 con desplazamientos de cámara de
##    menos de un píxel (h_offset / v_offset: brillos de textura y bordes; --zonly no las hace). Las compara
##    tools: work/heat.py (fuera del proyecto). --web: lo mismo en la versión web, con un arnés de Playwright.
## 3) --film: la cámara del juego moviéndose (ella camina de punta a punta), un cuadro por imagen.
## 4) --signs: primeros planos de cada letrero y texto 3D de la vista (y los letreros de las estaciones);
##    --stills: una captura normal en cada parada.

const TOL := 0.003          # a menos de 3 mm: coplanares
const NEAR_TOL := 0.06      # paralelas a menos de 6 cm: ¿las separa el búfer de profundidad?
const MIN_AREA := 0.0002    # 2 cm² de solape (menos es un borde que se toca)
const KN := 2000.0          # cuantización de las normales para agrupar planos

var main
var view := ""
var out_dir := ""
var _objs: Array = []       # [{node, desc, look, dbl, transp}]
var _tris: Array = []       # [obj, a, b, c, n, d]
var _skipped := {"billboard": 0, "nodepth": 0, "particles": 0}
var _stops: Array = []      # [[nombre, Callable]]
var _cams: Array = []       # [[nombre, Transform3D, fov, near, far, aspect]]

# ------------------------------------------------------------------ geometría

## Junta las caras de todo lo visible bajo `root`.
func collect(root: Node) -> void:
	_walk(root)

func _walk(n: Node) -> void:
	if n is Node3D and not (n as Node3D).visible:
		return
	if n is CanvasItem or n is CanvasLayer:
		return
	if n is GeometryInstance3D:
		_add_geom(n)
	for c in n.get_children():
		_walk(c)

func _add_geom(g: GeometryInstance3D) -> void:
	if g is GPUParticles3D or g is CPUParticles3D:
		_skipped["particles"] += 1
		return
	if g is MeshInstance3D:
		var mi := g as MeshInstance3D
		if mi.mesh == null:
			return
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s)
			if _mat_nodepth(mat):
				_skipped["nodepth"] += 1
				continue
			if _mat_billboard(mat):
				_skipped["billboard"] += 1
				continue
			var oi := _obj(mi, mat)
			_add_mesh_surface(mi.mesh, s, mi.global_transform, oi)
		return
	if g is MultiMeshInstance3D:
		var mm := (g as MultiMeshInstance3D).multimesh
		if mm == null or mm.mesh == null:
			return
		if DisplayServer.get_name() == "headless":
			# sin pantalla, las posiciones de las instancias no se pueden leer (quedan todas en el origen)
			_skipped["multimesh_headless"] = _skipped.get("multimesh_headless", 0) + 1
			return
		var mat0 := g.material_override if g.material_override else mm.mesh.surface_get_material(0)
		if _mat_billboard(mat0) or _mat_nodepth(mat0):
			_skipped["billboard"] += 1
			return
		var oi := _obj(g, mat0)
		for i in mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count:
			var xf := g.global_transform * mm.get_instance_transform(i)
			for s in mm.mesh.get_surface_count():
				_add_mesh_surface(mm.mesh, s, xf, oi)
		return
	if g is SpriteBase3D:
		var sp := g as SpriteBase3D
		if sp.billboard != BaseMaterial3D.BILLBOARD_DISABLED:
			_skipped["billboard"] += 1
			return
		if sp.no_depth_test:
			_skipped["nodepth"] += 1
			return
		_add_quad(sp, sp.get_aabb(), sp.double_sided)
		return
	if g is Label3D:
		var lb := g as Label3D
		if lb.billboard != BaseMaterial3D.BILLBOARD_DISABLED:
			_skipped["billboard"] += 1
			return
		if lb.no_depth_test:
			_skipped["nodepth"] += 1
			return
		_add_quad(lb, lb.get_aabb(), lb.double_sided)
		return

func _mat_nodepth(m: Material) -> bool:
	return m is BaseMaterial3D and (m as BaseMaterial3D).no_depth_test

func _mat_billboard(m: Material) -> bool:
	if m is BaseMaterial3D:
		return (m as BaseMaterial3D).billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED
	if m is ShaderMaterial and (m as ShaderMaterial).shader:
		var code: String = (m as ShaderMaterial).shader.code
		return code.contains("INV_VIEW_MATRIX") and code.contains("MODELVIEW_MATRIX =")
	return false

func _obj(n: Node3D, mat: Material) -> int:
	var dbl := false
	var transp := false
	var look := ""
	if n is SpriteBase3D or n is Label3D:
		dbl = bool(n.get("double_sided"))
		look = "sprite:" + str(n.get_instance_id())
	if mat is BaseMaterial3D:
		var b := mat as BaseMaterial3D
		dbl = dbl or b.cull_mode == BaseMaterial3D.CULL_DISABLED
		transp = b.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA
		if b.uv1_triplanar and b.uv1_world_triplanar:
			look = "tri:%s|%s|%s|%s" % [b.albedo_texture.resource_path if b.albedo_texture else "", b.albedo_color, b.uv1_scale, b.normal_texture.resource_path if b.normal_texture else ""]
	elif mat is ShaderMaterial and (mat as ShaderMaterial).shader:
		var code: String = (mat as ShaderMaterial).shader.code
		dbl = code.contains("cull_disabled")
		transp = code.contains("ALPHA")
	_objs.append({"node": n, "desc": describe(n, mat), "look": look, "dbl": dbl, "transp": transp})
	return _objs.size() - 1

## Una descripción que sirva para encontrarlo en el código: tipo y tamaño, posición, material y nombre del nodo.
static func describe(n: Node3D, mat: Material = null) -> String:
	var s := n.get_class()
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var m: Mesh = (n as MeshInstance3D).mesh
		s = m.get_class().replace("Mesh", "")
		if m is BoxMesh:
			var bs: Vector3 = (m as BoxMesh).size
			s += "(%.3fx%.3fx%.3f)" % [bs.x, bs.y, bs.z]
		elif m is QuadMesh:
			var qs: Vector2 = (m as QuadMesh).size
			s += "(%.2fx%.2f)" % [qs.x, qs.y]
		elif m is PlaneMesh:
			var ps: Vector2 = (m as PlaneMesh).size
			s += "(%.2fx%.2f)" % [ps.x, ps.y]
		elif m is PrismMesh:
			var pr: Vector3 = (m as PrismMesh).size
			s += "(%.2fx%.2fx%.2f)" % [pr.x, pr.y, pr.z]
		elif m is CylinderMesh:
			var cy := m as CylinderMesh
			s += "(r%.2f/%.2f h%.2f)" % [cy.top_radius, cy.bottom_radius, cy.height]
	elif n is Sprite3D and (n as Sprite3D).texture:
		s = "Sprite(%s)" % (n as Sprite3D).texture.resource_path.get_file()
	elif n is AnimatedSprite3D:
		var sf: SpriteFrames = (n as AnimatedSprite3D).sprite_frames
		var t: Texture2D = sf.get_frame_texture((n as AnimatedSprite3D).animation, 0) if sf else null
		var p := ""
		if t is AtlasTexture and (t as AtlasTexture).atlas:
			p = (t as AtlasTexture).atlas.resource_path.get_file()
		elif t:
			p = t.resource_path.get_file()
		s = "Anim(%s)" % p
	elif n is Label3D:
		s = "Label('%s')" % (n as Label3D).text.replace("\n", " ").left(28)
	elif n is MultiMeshInstance3D:
		s = "MultiMesh"
	var p3 := n.global_position
	s += "@(%.3f,%.3f,%.3f)" % [p3.x, p3.y, p3.z]
	var rot := n.global_transform.basis.get_euler()
	if rot.length() > 0.001:
		s += " rot(%.0f,%.0f,%.0f)" % [rad_to_deg(rot.x), rad_to_deg(rot.y), rad_to_deg(rot.z)]
	if mat is BaseMaterial3D and (mat as BaseMaterial3D).albedo_texture:
		s += " tex=" + (mat as BaseMaterial3D).albedo_texture.resource_path.get_file()
	elif mat is BaseMaterial3D:
		s += " col=" + (mat as BaseMaterial3D).albedo_color.to_html(false)
	elif mat is ShaderMaterial and (mat as ShaderMaterial).shader:
		s += " shader=" + (mat as ShaderMaterial).shader.resource_path.get_file()
	if not String(n.name).begins_with("@") and not String(n.name).contains("@"):
		s += " name=" + String(n.name)
	var par := n.get_parent()
	if par and not String(par.name).contains("@"):
		s += " in=" + String(par.name)
	return s

func _add_mesh_surface(mesh: Mesh, s: int, xf: Transform3D, oi: int) -> void:
	var arr: Array
	if mesh is PrimitiveMesh:
		arr = (mesh as PrimitiveMesh).get_mesh_arrays()
	else:
		if mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			return
		arr = mesh.surface_get_arrays(s)
	if arr.is_empty():
		return
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx = arr[Mesh.ARRAY_INDEX]
	var flip := mesh is PrimitiveMesh and (mesh as PrimitiveMesh).flip_faces
	if idx is PackedInt32Array and (idx as PackedInt32Array).size() > 0:
		var ii: PackedInt32Array = idx
		for k in range(0, ii.size() - 2, 3):
			_add_tri(oi, xf * vs[ii[k]], xf * vs[ii[k + 1]], xf * vs[ii[k + 2]], flip)
	else:
		for k in range(0, vs.size() - 2, 3):
			_add_tri(oi, xf * vs[k], xf * vs[k + 1], xf * vs[k + 2], flip)

## Un sprite o un letrero: su rectángulo (el AABB local tiene grosor 0) como dos triángulos.
func _add_quad(n: Node3D, ab: AABB, dbl: bool) -> void:
	if ab.size.x <= 0.0 or ab.size.y <= 0.0:
		return
	var oi := _obj(n, null)
	_objs[oi]["dbl"] = dbl
	if n is SpriteBase3D:
		_objs[oi]["transp"] = (n as SpriteBase3D).alpha_cut == SpriteBase3D.ALPHA_CUT_DISABLED and n.modulate.a < 0.999
	var xf := n.global_transform
	var z := ab.position.z
	var p0 := xf * Vector3(ab.position.x, ab.position.y, z)
	var p1 := xf * Vector3(ab.end.x, ab.position.y, z)
	var p2 := xf * Vector3(ab.end.x, ab.end.y, z)
	var p3 := xf * Vector3(ab.position.x, ab.end.y, z)
	# de frente a +z local (en el sentido de las agujas del reloj, como las caras de Godot)
	_add_tri(oi, p0, p3, p2, false)
	_add_tri(oi, p0, p2, p1, false)

func _add_tri(oi: int, a: Vector3, b: Vector3, c: Vector3, flip: bool) -> void:
	var cr := (b - a).cross(c - a)
	var l := cr.length()
	if l < 1e-9:
		return
	# Godot: caras delanteras en el sentido de las agujas del reloj => la normal de la cara es -(b-a)x(c-a)
	var nrm := -cr / l
	if flip:
		nrm = -nrm
	_tris.append([oi, a, b, c, nrm, nrm.dot(a)])

# ------------------------------------------------------------------ análisis

## Busca pares coplanares y pares paralelos cercanos. Devuelve {pairs: [...], near: [...]} agrupados por objeto.
func analyze() -> Dictionary:
	var buckets := {}       # clave del plano (normal canónica, d / TOL) -> [índices de triángulos]
	var nbuckets := {}      # lo mismo con d / NEAR_TOL
	for i in _tris.size():
		var t: Array = _tris[i]
		var n: Vector3 = t[4]
		var d: float = t[5]
		var cn := _canon(n)
		if cn.x * n.x + cn.y * n.y + cn.z * n.z < 0.0:
			d = -d
		var kn := Vector3i(roundi(cn.x * KN), roundi(cn.y * KN), roundi(cn.z * KN))
		var k1 := [kn, floori(d / TOL)]
		if not buckets.has(k1):
			buckets[k1] = []
		buckets[k1].append(i)
		var k2 := [kn, floori(d / NEAR_TOL)]
		if not nbuckets.has(k2):
			nbuckets[k2] = []
		nbuckets[k2].append(i)
	var pairs := {}
	var near := {}
	for k in buckets:
		var other = [k[0], k[1] + 1]
		_compare(buckets[k], buckets[k], pairs, true, true)
		if buckets.has(other):
			_compare(buckets[k], buckets[other], pairs, true, false)
	for k in nbuckets:
		var other2 = [k[0], k[1] + 1]
		_compare(nbuckets[k], nbuckets[k], near, false, true)
		if nbuckets.has(other2):
			_compare(nbuckets[k], nbuckets[other2], near, false, false)
	return {"pairs": pairs, "near": near}

func _canon(n: Vector3) -> Vector3:
	var ax := n.abs().max_axis_index()
	return n if n[ax] >= 0.0 else -n

func _compare(la: Array, lb: Array, out: Dictionary, tight: bool, same_list: bool) -> void:
	for ia in la.size():
		var i: int = la[ia]
		var ta: Array = _tris[i]
		var start := ia + 1 if same_list else 0
		for jb in range(start, lb.size()):
			var j: int = lb[jb]
			var tb: Array = _tris[j]
			if ta[0] == tb[0]:
				continue
			var na: Vector3 = ta[4]
			var nb: Vector3 = tb[4]
			var dot := na.dot(nb)
			if absf(dot) < 0.9999:
				continue
			var sep: float = absf(ta[5] - tb[5]) if dot > 0.0 else absf(ta[5] + tb[5])
			if tight:
				if sep > TOL:
					continue
			else:
				if sep <= TOL or sep > NEAR_TOL or dot < 0.0:
					continue
			# solape en el plano de ta
			var ov := _overlap(ta, tb, na)
			var area: float = ov[0]
			if area < 1e-7:
				continue
			var oa: int = ta[0]
			var ob: int = tb[0]
			# un par por objetos y por plano (dos cajas pueden compartir varias caras)
			var cn := _canon(na)
			var dd: float = ta[5] if cn.dot(na) > 0.0 else -ta[5]
			var key := [mini(oa, ob), maxi(oa, ob), Vector3i(roundi(cn.x * 100.0), roundi(cn.y * 100.0), roundi(cn.z * 100.0)), roundi(dd / 0.02)]
			if not out.has(key):
				var first_a := oa < ob
				out[key] = {"a": mini(oa, ob), "b": maxi(oa, ob), "area": 0.0, "sep": sep, "dot": dot,
					"na": na if first_a else nb, "nb": nb if first_a else na, "c": Vector3.ZERO, "w": 0.0, "pts": []}
			var e: Dictionary = out[key]
			e["area"] += area
			e["sep"] = minf(e["sep"], sep)
			# puntos de muestra del solape (en 3D): el centro y los vértices un poco hacia dentro
			var poly: PackedVector2Array = ov[1]
			var u: Vector3 = ov[2]
			var v: Vector3 = ov[3]
			var c2 := Vector2.ZERO
			for q in poly:
				c2 += q
			c2 /= float(poly.size())
			var c3: Vector3 = u * c2.x + v * c2.y + na * float(ta[5])
			e["c"] += c3 * area
			e["w"] += area
			if e["pts"].size() < 64:
				e["pts"].append(c3)
				for q in poly:
					var q2 := q.lerp(c2, 0.12)
					e["pts"].append(u * q2.x + v * q2.y + na * float(ta[5]))

## [área, polígono del solape en 2D, u, v] (u, v: la base del plano de ta)
func _overlap(ta: Array, tb: Array, n: Vector3) -> Array:
	var u := n.cross(Vector3.UP)
	if u.length() < 0.1:
		u = n.cross(Vector3.RIGHT)
	u = u.normalized()
	var v := n.cross(u)
	var a := PackedVector2Array([Vector2(u.dot(ta[1]), v.dot(ta[1])), Vector2(u.dot(ta[2]), v.dot(ta[2])), Vector2(u.dot(ta[3]), v.dot(ta[3]))])
	var b := PackedVector2Array([Vector2(u.dot(tb[1]), v.dot(tb[1])), Vector2(u.dot(tb[2]), v.dot(tb[2])), Vector2(u.dot(tb[3]), v.dot(tb[3]))])
	# rechazo rápido por cajas
	var ra := Rect2(a[0], Vector2.ZERO).expand(a[1]).expand(a[2])
	var rb := Rect2(b[0], Vector2.ZERO).expand(b[1]).expand(b[2])
	if not ra.grow(0.0005).intersects(rb):
		return [0.0]
	var poly := _clip_poly(a, b)
	if poly.size() < 3:
		return [0.0]
	return [absf(_signed_area(poly)), poly, u, v]

static func _signed_area(p: PackedVector2Array) -> float:
	var s := 0.0
	for i in p.size():
		var q := p[(i + 1) % p.size()]
		s += p[i].x * q.y - q.x * p[i].y
	return s * 0.5

## La intersección de dos polígonos convexos (Sutherland-Hodgman).
static func _clip_poly(a: PackedVector2Array, b: PackedVector2Array) -> PackedVector2Array:
	var poly := a
	var sb := signf(_signed_area(b))
	if sb == 0.0:
		return PackedVector2Array()
	for i in b.size():
		var p0 := b[i]
		var p1 := b[(i + 1) % b.size()]
		var e := p1 - p0
		var res := PackedVector2Array()
		var n := poly.size()
		if n == 0:
			return poly
		for j in n:
			var cur := poly[j]
			var prev := poly[(j - 1 + n) % n]
			var sc := sb * e.cross(cur - p0)
			var sp := sb * e.cross(prev - p0)
			if sc >= -1e-9:
				if sp < -1e-9:
					res.append(_inter(prev, cur, sp, sc))
				res.append(cur)
			elif sp >= -1e-9:
				res.append(_inter(prev, cur, sp, sc))
		poly = res
	return poly

static func _inter(p: Vector2, q: Vector2, sp: float, sq: float) -> Vector2:
	var t := sp / (sp - sq)
	return p + (q - p) * t

# ------------------------------------------------------------------ informe

## El informe de una vista. Para cada par y cada parada de la cámara: ¿se dibujan las dos caras (de frente a la cámara
## o de dos caras)? ¿cae algún punto del solape dentro de la vista? Clases:
##   FIGHT  las dos se dibujan y el solape está en la vista de alguna parada: z-fighting si nada lo tapa;
##   LOOK   como FIGHT, pero con el mismo material y la misma proyección triplanar del mundo (mismo color: no se nota);
##   OUT    las dos se dibujan, pero el solape no entra en ninguna vista;
##   SAFE   nunca se dibujan las dos (una siempre queda de espaldas a la cámara);
##   NEAR   paralelas, de frente, a 3 mm-6 cm y con menos de 64 pasos de un búfer de 24 bits a esa distancia.
func report(res: Dictionary) -> Dictionary:
	var lines: PackedStringArray = []
	var counts := {"FIGHT": 0, "LOOK": 0, "OUT": 0, "SAFE": 0, "NEAR": 0, "NEAR_OUT": 0}
	lines.append("ZCHECK view=%s objects=%d tris=%d skipped=%s" % [view, _objs.size(), _tris.size(), str(_skipped)])
	for c in _cams:
		lines.append("ZCHECK camera %s pos=(%.2f,%.2f,%.2f) fov=%.1f near=%.3f far=%.1f aspect=%.3f" % [c[0], c[1].origin.x, c[1].origin.y, c[1].origin.z, c[2], c[3], c[4], c[5]])
	var rows: Array = []
	var order := ["FIGHT", "NEAR", "LOOK", "OUT", "NEAR_OUT", "SAFE"]
	for key in res["pairs"]:
		var e: Dictionary = res["pairs"][key]
		if e["area"] < MIN_AREA:
			continue
		var oa: Dictionary = _objs[e["a"]]
		var ob: Dictionary = _objs[e["b"]]
		var vis := _seen_both(e, oa["dbl"], ob["dbl"])
		if oa["transp"] and ob["transp"]:
			vis = ["", vis[1], vis[2]]   # dos transparentes no escriben profundidad: se mezclan, no pelean
		var cls := "SAFE"
		if vis[0] == "both":
			cls = "OUT"
		elif vis[0] != "":
			cls = "FIGHT"
			if e["dot"] > 0.0 and oa["look"] != "" and oa["look"] == ob["look"] and not oa["look"].begins_with("sprite"):
				cls = "LOOK"
		counts[cls] += 1
		var cen: Vector3 = e["c"] / maxf(e["w"], 1e-9)
		rows.append([cls, e["area"], "ZCHECK %s area=%.4f m2 sep=%.4f %s at=(%.2f,%.2f,%.2f) n=(%.2f,%.2f,%.2f) seen=%s dist=%.1f\n    A: %s\n    B: %s" % [cls, e["area"], e["sep"], "same-facing" if e["dot"] > 0.0 else "opposite", cen.x, cen.y, cen.z, e["na"].x, e["na"].y, e["na"].z, vis[0] if vis[0] != "" else "never", vis[1], oa["desc"], ob["desc"]]])
	for key in res["near"]:
		var e: Dictionary = res["near"][key]
		if e["area"] < MIN_AREA:
			continue
		var oa: Dictionary = _objs[e["a"]]
		var ob: Dictionary = _objs[e["b"]]
		var vis := _seen_both(e, oa["dbl"], ob["dbl"])
		if vis[0] == "":
			continue
		var z: float = vis[2]
		# resolución del búfer de profundidad a esa distancia (proyección de OpenGL: dz ~ z² / (near · 2^bits))
		var nr: float = _cams[0][3] if not _cams.is_empty() else 0.1
		var r24 := z * z / (nr * 16777216.0)
		var k24: float = e["sep"] / maxf(r24, 1e-9)
		if k24 >= 64.0:
			continue
		var cls := "NEAR" if vis[0] != "both" else "NEAR_OUT"
		counts[cls] += 1
		var cen: Vector3 = e["c"] / maxf(e["w"], 1e-9)
		rows.append([cls, e["area"], "ZCHECK %s area=%.4f m2 sep=%.4f (x%.0f of a 24-bit depth step at %.1f m) at=(%.2f,%.2f,%.2f) seen=%s\n    A: %s\n    B: %s" % [cls, e["area"], e["sep"], k24, z, cen.x, cen.y, cen.z, vis[0], oa["desc"], ob["desc"]]])
	rows.sort_custom(func(p, q): return order.find(p[0]) * 1000.0 - p[1] < order.find(q[0]) * 1000.0 - q[1])
	for r in rows:
		lines.append(r[2])
	lines.append("ZCHECK SUMMARY view=%s FIGHT=%d NEAR=%d (to fix) | LOOK=%d OUT=%d NEAR_OUT=%d SAFE=%d (harmless)" % [view, counts["FIGHT"], counts["NEAR"], counts["LOOK"], counts["OUT"], counts["NEAR_OUT"], counts["SAFE"]])
	for l in lines:
		print(l)
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
		var f := FileAccess.open(out_dir.path_join(view + "_geo.txt"), FileAccess.WRITE)
		if f:
			f.store_string("\n".join(lines) + "\n")
	return counts

## ¿Desde qué parada se dibujan las dos caras con el solape en la vista? [parada | "both" (se dibujan, fuera de la
## vista) | "" (nunca las dos), distancia, profundidad en la vista]
func _seen_both(e: Dictionary, dbl_a: bool, dbl_b: bool) -> Array:
	var na: Vector3 = e["na"]
	var nb: Vector3 = e["nb"]
	var pts: Array = e["pts"]
	var res := ["", 1e9, -1.0]
	for c in _cams:
		var xf: Transform3D = c[1]
		var cam: Vector3 = xf.origin
		var fov: float = c[2]
		var th: float = tan(deg_to_rad(fov) * 0.5)
		var asp: float = c[5]
		var nr: float = c[3]
		for pv in pts:
			var p: Vector3 = pv
			var to_cam: Vector3 = cam - p
			var da: bool = dbl_a or to_cam.dot(na) > 0.0
			var db: bool = dbl_b or to_cam.dot(nb) > 0.0
			if not (da and db):
				continue
			var lp: Vector3 = xf.affine_inverse() * p
			var depth: float = -lp.z
			if depth > nr and absf(lp.y) <= depth * th * 1.02 and absf(lp.x) <= depth * th * asp * 1.02:
				return [c[0], to_cam.length(), depth]
			if res[0] == "":
				res = ["both", to_cam.length(), depth]
	return res

# ------------------------------------------------------------------ vistas y capturas

func _arg(name: String, def := "") -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + name + "="):
			return a.substr(name.length() + 3)
		if a == "--" + name:
			return "1"
	return def

## Punto de entrada (main.gd: --demo=zcheck).
static func run(m) -> void:
	var z := ZCheck.new()
	z.main = m
	await z._run()

func _run() -> void:
	view = _arg("view", "shop_day")
	out_dir = _arg("out", "")
	var tree: SceneTree = main.get_tree()
	if view == "geo_all":
		var tot := {}
		for v in ["shop_day", "shop_night", "ending", "market", "academia", "concurso", "torneo"]:
			var z := ZCheck.new()
			z.main = main
			z.view = v
			z.out_dir = out_dir
			await z._setup(v)
			for i in 3:
				await tree.process_frame
			await z._geo()
			z._teardown()
			for i in 2:
				await tree.process_frame
		print("ZCHECK DONE")
		tree.quit()
		return
	await _setup(view)
	for i in 6:
		await tree.process_frame
	await _geo()
	if _arg("web") != "":
		await _web()
		return
	if _arg("shots") != "":
		await _shots()
	if _arg("film") != "":
		await _film()
	if _arg("signs") != "":
		await _signs()
	if _arg("stills") != "":
		await _stills()
	print("ZCHECK DONE")
	tree.quit()

var _root: Node3D
var _cam: Camera3D
var _scene: Node3D
var _added: Array = []      # lo que agregó la vista (se borra en _teardown)
var _ending: EndingScene

## Prepara la vista: el lugar visible, la hora, la gente y las paradas de la cámara.
func _setup(v: String) -> void:
	var tree: SceneTree = main.get_tree()
	var w: ShopWorld = main.world
	var all_up := _arg("noupgrades") == ""
	if all_up:
		for id in Data.UPGRADE_ORDER:
			Game.upgrades[id] = true
		Game.ev_trophies = [{"kind": "academia", "medal": "gold"}, {"kind": "concurso", "medal": "silver"}, {"kind": "torneo", "medal": "bronze"}]
		w.refresh_upgrades()
		w.refresh_trophies()
	else:
		Game.upgrades = {}
		w.refresh_upgrades()
	main.ui.set_gameplay_visible(false)
	main.open_btn.visible = false
	main.trip_btn.visible = false
	match v:
		"shop_day", "shop_morning", "shop_night", "title":
			_root = w
			_cam = w.camera
			w.set_time({"shop_day": 0.45, "shop_morning": 0.0, "shop_night": 1.0, "title": 1.0}[v], false)
			_people(w)
			if v == "title":
				main._show_title()
				_stops = [["counter", func(): w.cam_fixed_x = INF; w.walker.teleport(ShopWorld.P_ALCH_COUNTER.x, 1); w.snap_camera()]]
			else:
				for x in [-10.0, -6.5, -2.35, -0.3, 2.0]:
					var xx: float = x
					_stops.append(["x%+.1f" % xx, func(): w.cam_fixed_x = xx; w.snap_camera()])
		"ending":
			_root = w
			_cam = w.camera
			var e := EndingScene.new()
			e.main = main
			e.world = w
			e.ui = main.ui
			main.add_child(e)
			e._setup()
			for c in EndingScene.CROWD:
				var a := e._spawn(c[0], c[1])
				a.face(-1)
			e._spawn("pip", EndingScene.PIP_SPOT).face(-1)
			var t := EndingScene._trophy_sprite()
			t.position = EndingScene.TROPHY_POS
			w.add_child(t)
			_added.append(t)
			_ending = e
			_stops = [["ending", func(): w.snap_camera()]]
		"market":
			main._switch_place(true, false)
			var mk: MarketWorld = main.market
			_root = mk
			_cam = mk.camera
			for x in [MarketWorld.CAM_X0, 7.0, MarketWorld.FOUNTAIN_POS.x, 18.0, MarketWorld.CAM_X1]:
				var xx: float = x
				_stops.append(["x%+.1f" % xx, func(): mk.walker.teleport(xx - 0.6, 1); mk.snap_camera()])
		"academia", "concurso", "torneo":
			main._scenes_demo(v)
			_scene = main.get_child(main.get_child_count() - 1) as Node3D
			for c in main.get_children():
				if c is Node3D and String(c.name).begins_with("Event_"):
					_scene = c
			_root = _scene
			_cam = _scene.get_node("Camera")
			_stops = [["event", func(): pass]]
	var only := _arg("only", "")
	if only != "":
		_stops = _stops.filter(func(st): return st[0] == only)
	for i in 3:
		await tree.process_frame

func _teardown() -> void:
	for n in _added:
		if is_instance_valid(n):
			n.queue_free()
	_added.clear()
	if _ending:
		for n in _ending._added:
			if is_instance_valid(n):
				n.queue_free()
		for id in _ending._actors:
			if is_instance_valid(_ending._actors[id]):
				_ending._actors[id].queue_free()
		main.world._cam_base = _ending._cam_base
		main.world._cam_target = _ending._cam_target
		main.world.cam_fixed_x = INF
		_ending.queue_free()
		_ending = null
	if _scene and is_instance_valid(_scene):
		_scene.queue_free()
		main._set_place_on(main.world, true)
		main.world.camera.current = true
	if view == "market":
		main._switch_place(false, false)

## Gente en la tienda: en el mostrador, en la fila (sobre la alfombra) y ella; sus sombras de mancha cuentan.
func _people(w: ShopWorld) -> void:
	var ids := ["lirien", "bram", "nyra", "kit", "panadera"]
	var spots := [ShopWorld.P_CUSTOMER] + ShopWorld.QUEUE_SPOTS
	for i in ids.size():
		var a := Actor.new()
		w.add_child(a)
		a.setup(Story.sprite_id(ids[i]))
		a.quiet = true
		a.global_position = spots[i]
		a.face(-1)
		_added.append(a)

## La parte geométrica: junta las caras y las cámaras de todas las paradas e informa.
func _geo() -> void:
	var tree: SceneTree = main.get_tree()
	_cams.clear()
	var vp_size: Vector2 = main.get_viewport().get_visible_rect().size
	for s in _stops:
		s[1].call()
		for i in 3:
			await tree.process_frame
		# sin pantalla (--headless) el tamaño de la vista puede ser 0: el juego es 16:9
		var asp := vp_size.x / vp_size.y if vp_size.x > 1.0 and vp_size.y > 1.0 and DisplayServer.get_name() != "headless" else 16.0 / 9.0
		_cams.append([s[0], _cam.global_transform, _cam.fov, _cam.near, _cam.far, asp])
	_objs.clear()
	_tris.clear()
	collect(_root)
	report(analyze())

## Las sombras del sol (PSSM) se reparten según near/far de la cámara: al moverlos, el mapa de sombras se reencaja y
## sus bordes saltan un texel, y eso parecería z-fighting (p. ej. la sombra de un poste del puesto de Borin en la
## puerta de detrás). Mientras se mueven near/far el sol no hace sombra; las de las luces omni (el fuego del caldero)
## no dependen de la cámara y se quedan.
var _suns: Array = []

func _sun_shadows(on: bool) -> void:
	if not on:
		_suns.clear()
		for n in main.get_tree().root.find_children("*", "DirectionalLight3D", true, false):
			var l := n as DirectionalLight3D
			if l.shadow_enabled:
				l.shadow_enabled = false
				_suns.append(l)
	else:
		for l in _suns:
			if is_instance_valid(l):
				(l as DirectionalLight3D).shadow_enabled = true
		_suns.clear()

## Capturas con el tiempo congelado en cada parada: 8 moviendo near/far (z_*.png, sin sombras del sol) y 8 moviendo la
## cámara menos de un píxel (s_*.png; --zonly se las salta).
func _shots() -> void:
	var tree: SceneTree = main.get_tree()
	var dir := out_dir.path_join(view)
	DirAccess.make_dir_recursive_absolute(dir)
	for s in _stops:
		Engine.time_scale = 1.0
		s[1].call()
		for i in 40:
			await tree.process_frame
		Engine.time_scale = 0.0
		_sun_shadows(false)
		for i in 3:
			await tree.process_frame
		var n0 := _cam.near
		var f0 := _cam.far
		for k in 8:
			_cam.near = n0 * (1.0 + 0.0013 * k)
			_cam.far = f0 * (1.0 + 0.011 * k)
			for i in 2:
				await tree.process_frame
			main.get_viewport().get_texture().get_image().save_png(dir.path_join("%s_z%d.png" % [s[0], k]))
		_cam.near = n0
		_cam.far = f0
		_sun_shadows(true)
		if _arg("zonly") != "":
			print("ZCHECK shots %s/%s" % [view, s[0]])
			continue
		var h0 := _cam.h_offset
		var v0 := _cam.v_offset
		for k in 8:
			var ang := TAU * k / 8.0
			_cam.h_offset = h0 + cos(ang) * 0.003
			_cam.v_offset = v0 + sin(ang) * 0.003
			for i in 2:
				await tree.process_frame
			main.get_viewport().get_texture().get_image().save_png(dir.path_join("%s_s%d.png" % [s[0], k]))
		_cam.h_offset = h0
		_cam.v_offset = v0
		print("ZCHECK shots %s/%s" % [view, s[0]])
	Engine.time_scale = 1.0

## En la web (WebGL 2, sin archivos): como --shots, pero cada estado se anuncia en la consola («ZCHECK WEB z3 x+2.0 #4»)
## y se mantiene hasta que el arnés (Playwright) saca la captura y lo confirma con window.zcheck_ack = 4 (o --hold
## cuadros como mínimo, y 3000 como mucho si nadie confirma). Al final, «ZCHECK WEB film»: el tiempo vuelve a correr con
## la cámara quieta en la parada (solo el vaivén del juego) y el arnés saca capturas seguidas.
## (SwiftShader va a ~0,5 cuadros por segundo: sin la confirmación, las últimas capturas salían ya con el tiempo corriendo.)
var _web_tok := 0

func _web_wait(tree: SceneTree, hold: int) -> void:
	_web_tok += 1
	for i in 3000:
		await tree.process_frame
		if i + 1 < hold:
			continue
		var ack = JavaScriptBridge.eval("window.zcheck_ack|0", true)
		if ack != null and int(ack) >= _web_tok:
			return

func _web() -> void:
	var tree: SceneTree = main.get_tree()
	var hold := int(_arg("hold", "2"))
	for s in _stops:
		Engine.time_scale = 1.0
		s[1].call()
		for i in 40:
			await tree.process_frame
		Engine.time_scale = 0.0
		_sun_shadows(false)
		for i in 3:
			await tree.process_frame
		var n0 := _cam.near
		var f0 := _cam.far
		for k in 8:
			_cam.near = n0 * (1.0 + 0.0013 * k)
			_cam.far = f0 * (1.0 + 0.011 * k)
			for i in 2:
				await tree.process_frame
			print("ZCHECK WEB z%d %s #%d" % [k, s[0], _web_tok + 1])
			await _web_wait(tree, hold)
		_cam.near = n0
		_cam.far = f0
		_sun_shadows(true)
		Engine.time_scale = 1.0
		print("ZCHECK WEB film %s #%d" % [s[0], _web_tok + 1])
		await _web_wait(tree, hold)
	print("ZCHECK WEB done")

## --stills: una captura normal (con sombras, el tiempo corriendo) en cada parada de la cámara: <out>/<vista>_stills/.
func _stills() -> void:
	var tree: SceneTree = main.get_tree()
	var dir := out_dir.path_join(view + "_stills")
	DirAccess.make_dir_recursive_absolute(dir)
	Engine.time_scale = 1.0
	for s in _stops:
		s[1].call()
		for i in 45:
			await tree.process_frame
		main.get_viewport().get_texture().get_image().save_png(dir.path_join("%s.png" % s[0]))
		print("ZCHECK still %s/%s" % [view, s[0]])

## --signs: una captura de cada letrero y cada texto del mundo 3D de la vista (para revisar el inglés): los Label3D
## visibles (sin los números de los tarros), los carteles pintados (Sprite3D con «sign» en el nombre de la textura),
## con una cámara de primer plano delante de cada uno, y en la tienda y el mercado los letreros que salen al pasar el
## cursor por cada estación (con la cámara del juego). <out>/signs_<vista>/NN_<texto>.png y una línea «ZCHECK SIGN».
func _signs() -> void:
	var tree: SceneTree = main.get_tree()
	var dir := out_dir.path_join("signs_" + view)
	DirAccess.make_dir_recursive_absolute(dir)
	if not _stops.is_empty():
		_stops[0][1].call()
	for i in 20:
		await tree.process_frame
	var items: Array = []   # [texto o textura, nodo]
	for n in _root.find_children("*", "Label3D", true, false):
		var l := n as Label3D
		if l.is_visible_in_tree() and l.text.strip_edges() != "" and not l.text.strip_edges().is_valid_int():
			items.append([l.text, l])
	for n in _root.find_children("*", "Sprite3D", true, false):
		var sp := n as Sprite3D
		if sp.is_visible_in_tree() and sp.texture and "sign" in sp.texture.resource_path.get_file():
			items.append([sp.texture.resource_path.get_file().get_basename(), sp])
	var k := 0
	var cam := Camera3D.new()
	cam.environment = _cam.environment
	cam.fov = 26.0
	cam.near = 0.05
	_root.add_child(cam)
	for it in items:
		k += 1
		var n: GeometryInstance3D = it[1]
		var ab: AABB = n.get_aabb()
		var xf: Transform3D = n.global_transform
		var center: Vector3 = xf * ab.get_center()
		var ext: float = maxf(ab.size.x * xf.basis.get_scale().x, ab.size.y * xf.basis.get_scale().y)
		var nrm: Vector3 = xf.basis.z.normalized()
		var bb: int = n.get("billboard") if n.get("billboard") != null else 0
		var to_cam: Vector3 = (_cam.global_position - center).normalized()
		if bb != 0 or nrm.dot(to_cam) < 0.0:
			nrm = to_cam if bb != 0 else -nrm
		var dist := clampf(ext * 1.35 / (2.0 * tan(deg_to_rad(cam.fov) / 2.0)), 0.6, 14.0)
		# un poco desde el lado de la cámara del juego, como se ve jugando
		var dv: Vector3 = (nrm * 0.65 + to_cam * 0.35).normalized()
		cam.global_position = center + dv * dist
		cam.look_at(center, Vector3.UP)
		cam.current = true
		for i in 3:
			await tree.process_frame
		var fname := "%02d_%s.png" % [k, _slug(String(it[0]))]
		main.get_viewport().get_texture().get_image().save_png(dir.path_join(fname))
		print("ZCHECK SIGN %s \"%s\" at (%.2f,%.2f,%.2f) -> %s" % [view, String(it[0]).replace("\n", " "), center.x, center.y, center.z, fname])
	_cam.current = true
	cam.queue_free()
	for i in 2:
		await tree.process_frame
	# los letreros de las estaciones (salen al pasar el cursor), con la cámara del juego
	if _root is ShopWorld:
		var w: ShopWorld = _root
		for id in w.station_nodes:
			var nx: float = (w.station_nodes[id] as Node3D).global_position.x
			w.cam_fixed_x = clampf(nx, -10.0, 2.0)
			w.snap_camera()
			w._label_on(id)
			for i in 4:
				await tree.process_frame
			k += 1
			var fname := "%02d_hover_%s.png" % [k, id]
			main.get_viewport().get_texture().get_image().save_png(dir.path_join(fname))
			print("ZCHECK SIGN %s hover %s \"%s\" -> %s" % [view, id, w._station_label.text, fname])
			w._label_off(id)
		w.cam_fixed_x = INF
	elif _root is MarketWorld:
		var mk: MarketWorld = _root
		# (la altura del letrero de la puerta, si la versión la tiene: así el comprobador también corre sobre la de antes)
		var door_h: float = mk.get_script().get_script_constant_map().get("DOOR_LABEL_H", 2.9)
		for id in mk.station_nodes:
			var nd: Node3D = mk.station_nodes[id]
			mk.walker.teleport(clampf(nd.global_position.x, MarketWorld.X0, MarketWorld.X1), 1)
			mk.snap_camera()
			mk._hover_on(id, nd, door_h if id == "tienda" else 3.25)
			for i in 4:
				await tree.process_frame
			k += 1
			var fname := "%02d_hover_%s.png" % [k, id]
			main.get_viewport().get_texture().get_image().save_png(dir.path_join(fname))
			print("ZCHECK SIGN %s hover %s \"%s\" -> %s" % [view, id, mk._label.text, fname])
			mk._hover_off(id)
	print("ZCHECK signs %s: %d" % [view, k])

func _slug(t: String) -> String:
	var o := ""
	for c in t.to_lower():
		o += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") else "_"
	while o.contains("__"):
		o = o.replace("__", "_")
	return o.trim_prefix("_").trim_suffix("_").left(32)

## La cámara del juego moviéndose: en la tienda ella camina de la biblioteca a la puerta y vuelve al mostrador; en el
## mercado, de su puerta al final de la calle; en los eventos la cámara de la escena (se mece sola).
func _film() -> void:
	var tree: SceneTree = main.get_tree()
	var dir := out_dir.path_join(view + "_film")
	DirAccess.make_dir_recursive_absolute(dir)
	Engine.time_scale = 1.0
	var n := 0
	var every := int(_arg("every", "1"))
	var frames := int(_arg("filmframes", "150"))
	if _root is ShopWorld:
		var w: ShopWorld = _root
		w.cam_fixed_x = INF
		w.walker.teleport(-10.2, 1)
		w.snap_camera()
		for i in 10:
			await tree.process_frame
		w.walker.go_to(3.95)
	elif _root is MarketWorld:
		var mk: MarketWorld = _root
		mk.walker.teleport(MarketWorld.X0, 1)
		mk.snap_camera()
		for i in 10:
			await tree.process_frame
		mk.walker.go_to(MarketWorld.X1)
	for f in frames:
		await tree.process_frame
		if f % every == 0:
			main.get_viewport().get_texture().get_image().save_png(dir.path_join("f%04d.png" % n))
			n += 1
	print("ZCHECK film %s frames=%d" % [view, n])
