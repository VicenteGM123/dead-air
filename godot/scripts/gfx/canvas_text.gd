# DACanvasText: fonts and text geometry for the Canvas 2D emulation (no JS counterpart; engine glue).
# * resolve(cssFont) parses a CSS font shorthand ("bold 48px Bungee", "italic 700 20px \"Titan One\", sans-serif")
#   and picks the first available family like Chrome does: the bundled web fonts (res://assets/fonts/ Shrikhand,
#   Titan One, VT323, Bungee), then system fonts (SystemFont: real "Courier New"/Georgia/Impact/"Arial Black" on
#   Windows/macOS; metric-compatible Liberation fonts on Linux), generic families serif/sans-serif/monospace/
#   cursive/fantasy; default serif.
# * Text is drawn as glyph OUTLINES (TextServer.font_get_glyph_contours, HarfBuzz shaping at a reference size),
#   so fillText/strokeText get exactly the canvas semantics (gradients, clip, composite, lineWidth/lineJoin
#   outlines, transforms) and share the path pipeline. Shaped strings, fill meshes and stroke pieces are cached.
# * Baselines follow Blink: em box normalized from the OS/2 typo metrics (EM_ASC table, measured in Chromium),
#   hanging = 0.8 * round(ascent), ideographic = -round(descent).
class_name DACanvasText
extends RefCounted

const REF := 128               # shaping / outline reference size (px)
const GTOL := 0.04             # glyph flattening tolerance in REF px
const BUNDLED := {
	"shrikhand": "res://assets/fonts/Shrikhand.woff",
	"titan one": "res://assets/fonts/TitanOne.woff",
	"vt323": "res://assets/fonts/VT323.woff",
	"bungee": "res://assets/fonts/Bungee.woff",
}
const GENERIC := ["serif", "sans-serif", "monospace", "cursive", "fantasy", "system-ui", "ui-serif", "ui-sans-serif", "ui-monospace"]
# Families Chrome accepts as fontconfig substitutes (metric compatible) when the real one is missing.
const ALIASES := {
	"courier new": ["liberation mono", "cousine", "courier new"],
	"arial": ["liberation sans", "arimo", "arial"],
	"times new roman": ["liberation serif", "tinos", "times new roman"],
}
# Blink em-height ascent ratio (typoAscender / (typoAscender + typoDescender)), measured in Chromium.
const EM_ASC := {
	"shrikhand": 0.70375, "titan one": 0.8471875, "vt323": 0.80, "bungee": 0.77265625,
	"liberation mono": 0.76484375, "dejavu sans": 0.77578125, "dejavu serif": 0.76265625,
	"dejavu sans mono": 0.75984375,
}

static var _specs := {}        # css font string -> Spec
static var _fonts := {}        # "family|weight|italic" -> Font (or null when unavailable)
static var _shaped := {}       # spec.key + "|" + text -> Shaped
static var _glyphs := {}       # "rid|index" -> Glyph
static var _ts: TextServer = null

class Spec:
	extends RefCounted
	var key := ""
	var css := ""
	var px := 10.0
	var weight := 400
	var italic := false
	var font: Font = null
	var family := ""           # resolved family name (lower case)
	var emAsc := 0.8           # ratio
	var asc := 0.9             # font ascent ratio (fontBoundingBoxAscent / px)
	var desc := 0.25
	var synthItalic := false
	var synthBold := 0.0       # extra outline width (fraction of px) for fake bold

class Glyph:
	extends RefCounted
	var polys: Array = []      # PackedVector2Array contours (REF px, y down, baseline y = 0)
	var box := Rect2()
	var empty := true
	var fill: Array = []       # [pts, idx] (lazy)

class Shaped:
	extends RefCounted
	var glyphs: Array = []     # [Glyph, x, y] in REF px (letter spacing NOT included)
	var clusterEnds: PackedFloat64Array = PackedFloat64Array()   # per glyph: number of chars ended at this glyph
	var width := 0.0           # REF px (no spacing)
	var nchars := 0
	var cache := {}            # mesh caches keyed by spacing / stroke params

static func ts() -> TextServer:
	if _ts == null:
		_ts = TextServerManager.get_primary_interface()
	return _ts

# ------------------------------------------------------------------------------------------------ CSS font
static func resolve(css: String) -> Spec:
	var hit = _specs.get(css)
	if hit != null:
		return hit
	var sp := _parse(css)
	if sp == null:
		return null
	_specs[css] = sp
	return sp

static func _parse(css: String) -> Spec:
	var s := css.strip_edges()
	var sp := Spec.new()
	sp.css = s
	# split off the size token: first token that starts with a digit/dot and has a unit
	var i := 0
	var n := s.length()
	var pre: Array = []
	var sizeTok := ""
	while i < n:
		while i < n and s[i] == " ":
			i += 1
		var j := i
		while j < n and s[j] != " ":
			j += 1
		var tok := s.substr(i, j - i)
		i = j
		var c0 := tok[0] if tok.length() > 0 else ""
		if (c0 >= "0" and c0 <= "9") or c0 == ".":
			if tok.is_valid_int() and (tok.to_int() % 100 == 0) and tok.to_int() >= 100 and tok.to_int() <= 900 and sizeTok == "":
				pre.append(tok)
				continue
			sizeTok = tok
			break
		pre.append(tok.to_lower())
	if sizeTok == "":
		return null
	var rest := s.substr(i).strip_edges()
	var lh := sizeTok.find("/")
	if lh >= 0:
		sizeTok = sizeTok.substr(0, lh)
	elif rest.begins_with("/"):
		# "12px / 1.2 family"
		var k := 1
		while k < rest.length() and rest[k] == " ":
			k += 1
		while k < rest.length() and rest[k] != " ":
			k += 1
		rest = rest.substr(k).strip_edges()
	var px := 10.0
	if sizeTok.ends_with("px"):
		px = float(sizeTok.trim_suffix("px"))
	elif sizeTok.ends_with("pt"):
		px = float(sizeTok.trim_suffix("pt")) * 4.0 / 3.0
	elif sizeTok.ends_with("em") or sizeTok.ends_with("rem"):
		px = float(sizeTok.trim_suffix("rem").trim_suffix("em")) * 10.0
	elif sizeTok.ends_with("%"):
		px = float(sizeTok.trim_suffix("%")) * 0.1
	else:
		px = float(sizeTok)
	sp.px = px
	for t in pre:
		match t:
			"italic", "oblique":
				sp.italic = true
			"bold", "bolder":
				sp.weight = 700
			"lighter":
				sp.weight = 300
			"normal", "small-caps":
				pass
			_:
				if t.is_valid_int():
					sp.weight = t.to_int()
	var fams: Array = []
	for f in rest.split(","):
		var nm := f.strip_edges().trim_prefix("\"").trim_suffix("\"").trim_prefix("'").trim_suffix("'").strip_edges()
		if nm != "":
			fams.append(nm.to_lower())
	fams.append("serif")
	for fam in fams:
		var f := _font(fam, sp.weight, sp.italic)
		if f != null:
			sp.font = f
			sp.family = fam if BUNDLED.has(fam) or GENERIC.has(fam) else fam
			if f is SystemFont:
				sp.family = (f as SystemFont).get_font_name().to_lower()
			elif f is FontVariation and (f as FontVariation).base_font is SystemFont:
				sp.family = ((f as FontVariation).base_font as SystemFont).get_font_name().to_lower()
			break
	if sp.font == null:
		return null
	var bundled := BUNDLED.has(fams[0]) and sp.font != null and _fonts.get("%s|%d|%s" % [fams[0], sp.weight, sp.italic]) == sp.font
	if bundled or BUNDLED.has(sp.family):
		sp.synthItalic = sp.italic
		if sp.weight >= 600:
			sp.synthBold = 1.0 / 32.0 if px >= 36.0 else lerpf(1.0 / 24.0, 1.0 / 32.0, clampf((px - 9.0) / 27.0, 0.0, 1.0))
	var rids := sp.font.get_rids()
	var rid: RID = rids[0] if rids.size() > 0 else RID()
	var a := ts().font_get_ascent(rid, REF) / REF
	var d := ts().font_get_descent(rid, REF) / REF
	sp.asc = a
	sp.desc = d
	sp.emAsc = EM_ASC.get(sp.family, a / maxf(0.001, a + d))
	sp.key = "%s|%d|%s|%s" % [sp.family, sp.weight, sp.italic, str(sp.font.get_instance_id())]
	return sp

static func _font(fam: String, weight: int, italic: bool) -> Font:
	var key := "%s|%d|%s" % [fam, weight, italic]
	if _fonts.has(key):
		return _fonts[key]
	var f: Font = null
	if BUNDLED.has(fam):
		var base = load(BUNDLED[fam])
		if base is FontFile:
			var ff: FontFile = (base as FontFile).duplicate()
			ff.hinting = TextServer.HINTING_NONE
			ff.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_ONE_QUARTER
			ff.allow_system_fallback = true
			f = ff
	else:
		var sf := SystemFont.new()
		var names := PackedStringArray([fam])
		if GENERIC.has(fam):
			names = PackedStringArray([fam.trim_prefix("ui-")])
		else:
			for al in ALIASES.get(fam, []):
				names.append(al)
		sf.font_names = names
		sf.font_weight = weight
		sf.font_italic = italic
		sf.hinting = TextServer.HINTING_NONE
		sf.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_ONE_QUARTER
		var got := sf.get_font_name().to_lower()
		if got == "":
			f = null
		elif GENERIC.has(fam):
			f = sf
		elif got == fam or ALIASES.get(fam, []).has(got):
			f = sf
		else:
			f = null
	_fonts[key] = f
	return f

# Baseline offset (device-space y added to the anchor y, before the transform) for textBaseline.
static func baselineOffset(sp: Spec, px: float, base: String) -> float:
	var emA := roundf(sp.emAsc * px * 64.0) / 64.0
	match base:
		"top":
			return emA
		"middle":
			return emA - px * 0.5
		"bottom":
			return emA - px
		"hanging":
			return roundf(sp.asc * px) * 0.8
		"ideographic":
			return -roundf(sp.desc * px)
	return 0.0

# ------------------------------------------------------------------------------------------------ shaping
static func shape(sp: Spec, text: String) -> Shaped:
	var key := sp.key + "\u0001" + text
	var hit = _shaped.get(key)
	if hit != null:
		return hit
	if _shaped.size() > 4096:
		_shaped.clear()
	var sh := Shaped.new()
	var t := ts()
	var rid := t.create_shaped_text()
	t.shaped_text_add_string(rid, text, sp.font.get_rids(), REF, {}, "")
	t.shaped_text_shape(rid)
	var gl: Array = t.shaped_text_get_glyphs(rid)
	var x := 0.0
	sh.clusterEnds = PackedFloat64Array()
	for g in gl:
		var rep: int = g.get("repeat", 1)
		var adv: float = g.advance
		var off: Vector2 = g.offset
		var gi: int = g.index
		var frid: RID = g.font_rid
		for r in rep:
			if gi != 0 and frid.is_valid() and (int(g.flags) & TextServer.GRAPHEME_IS_VIRTUAL) == 0:
				var gd := glyph(frid, gi)
				if not gd.empty:
					sh.glyphs.append([gd, x + off.x, off.y])
					sh.clusterEnds.append(float(g.start))   # characters before this glyph (letter spacing)
			x += adv
	sh.width = x
	sh.nchars = text.length()
	t.free_rid(rid)
	_shaped[key] = sh
	return sh

static func glyph(frid: RID, idx: int) -> Glyph:
	var key := "%d|%d" % [frid.get_id(), idx]
	var hit = _glyphs.get(key)
	if hit != null:
		return hit
	var gd := Glyph.new()
	var c: Dictionary = ts().font_get_glyph_contours(frid, REF, idx)
	if c.has("points") and c.has("contours"):
		var pts: PackedVector3Array = c.points
		var ends: PackedInt32Array = c.contours
		var s := 0
		for e in ends:
			var poly := _contour(pts, s, e)
			if poly.size() >= 3:
				gd.polys.append(poly)
			s = e + 1
	if not gd.polys.is_empty():
		gd.empty = false
		var r := DACanvasGeom.bbox(gd.polys[0])
		for k in range(1, gd.polys.size()):
			r = r.merge(DACanvasGeom.bbox(gd.polys[k]))
		gd.box = r
	_glyphs[key] = gd
	return gd

# TrueType / CFF contour (tags: 1 on-curve, 0 conic control, 2 cubic control) -> flattened polyline.
static func _contour(pts: PackedVector3Array, s: int, e: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := e - s + 1
	if n < 2:
		return out
	var P: Array = []
	var T := PackedInt32Array()
	for k in n:
		var q := pts[s + k]
		P.append(Vector2(q.x, q.y))
		T.append(int(q.z) & 3)
	# start at an on-curve point (or an implied midpoint)
	var first := -1
	for k in n:
		if T[k] == 1:
			first = k
			break
	var startPt: Vector2
	if first < 0:
		startPt = (P[0] + P[1]) * 0.5
		first = 0
		# rotate so that P[0] is the first control after the implied start
		out.append(startPt)
		var cur := startPt
		var ctrl: Array = []
		for k in range(1, n + 1):
			var idx := k % n
			var p: Vector2 = P[idx]
			if ctrl.size() == 1:
				var mid: Vector2 = (ctrl[0] + p) * 0.5
				_quad(out, cur, ctrl[0], mid)
				cur = mid
				ctrl = [p]
			else:
				ctrl = [p]
		_quad(out, cur, ctrl[0], startPt)
		return out
	startPt = P[first]
	out.append(startPt)
	var curP := startPt
	var cs: Array = []    # pending control points
	var ctype := 0
	for k in range(1, n + 1):
		var idx2 := (first + k) % n
		var p2: Vector2 = P[idx2]
		var tg := T[idx2]
		if tg == 1:
			if cs.is_empty():
				out.append(p2)
			elif ctype == 0:
				_quad(out, curP, cs[0], p2)
			else:
				if cs.size() >= 2:
					_cubic(out, curP, cs[0], cs[1], p2)
				else:
					_quad(out, curP, cs[0], p2)
			curP = p2
			cs = []
		elif tg == 0:
			if not cs.is_empty() and ctype == 0:
				var mid2: Vector2 = (cs[0] + p2) * 0.5
				_quad(out, curP, cs[0], mid2)
				curP = mid2
				cs = [p2]
			else:
				cs = [p2]
			ctype = 0
		else:
			cs.append(p2)
			ctype = 2
	# drop the duplicated closing point
	if out.size() > 1 and out[0].distance_squared_to(out[out.size() - 1]) < 1e-10:
		out.remove_at(out.size() - 1)
	return out

static func _quad(out: PackedVector2Array, p0: Vector2, p1: Vector2, p2: Vector2) -> void:
	var n := DACanvasGeom.quadSegs(p0, p1, p2, GTOL)
	for i in range(1, n + 1):
		var t := float(i) / n
		var u := 1.0 - t
		out.append(p0 * (u * u) + p1 * (2.0 * u * t) + p2 * (t * t))

static func _cubic(out: PackedVector2Array, p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2) -> void:
	var n := DACanvasGeom.cubicSegs(p0, p1, p2, p3, GTOL)
	for i in range(1, n + 1):
		var t := float(i) / n
		var u := 1.0 - t
		out.append(p0 * (u * u * u) + p1 * (3.0 * u * u * t) + p2 * (3.0 * u * t * t) + p3 * (t * t * t))

# ------------------------------------------------------------------------------------------------ meshes
# x position (REF px) of every glyph with letter spacing `spRef` (REF px per character).
static func _glyphX(sh: Shaped, k: int, spRef: float) -> float:
	var x: float = sh.glyphs[k][1]
	if spRef != 0.0:
		x += spRef * sh.clusterEnds[k]
	return x

# Text fill mesh in REF space (glyphs positioned). Returns [pts, idx] (non-overlapping per glyph).
static func fillMesh(sh: Shaped, spRef: float) -> Array:
	var key := "f%.4f" % spRef
	var hit = sh.cache.get(key)
	if hit != null:
		return hit
	var P := PackedVector2Array()
	var I := PackedInt32Array()
	for k in sh.glyphs.size():
		var g: Glyph = sh.glyphs[k][0]
		if g.fill.is_empty():
			g.fill = DACanvasGeom.sweep(g.polys, false)
		var off := Vector2(_glyphX(sh, k, spRef), sh.glyphs[k][2])
		var base := P.size()
		var gp: PackedVector2Array = g.fill[0]
		P.append_array(Transform2D(0.0, off) * gp)
		for t in g.fill[1]:
			I.append(base + t)
	var res := [P, I]
	sh.cache[key] = res
	return res

# Text outline polygons in REF space: [pts, starts] (for the software canvas and clip).
static func polyGeo(sh: Shaped, spRef: float) -> Array:
	var key := "p%.4f" % spRef
	var hit = sh.cache.get(key)
	if hit != null:
		return hit
	var P := PackedVector2Array()
	var S := PackedInt32Array()
	for k in sh.glyphs.size():
		var g: Glyph = sh.glyphs[k][0]
		var xf := Transform2D(0.0, Vector2(_glyphX(sh, k, spRef), sh.glyphs[k][2]))
		for poly in g.polys:
			S.append(P.size())
			P.append_array(xf * (poly as PackedVector2Array))
	var res := [P, S]
	sh.cache[key] = res
	return res

# Stroke pieces of the text outlines in REF space for line width lwRef (REF px). [pts, starts].
static func strokeGeo(sh: Shaped, spRef: float, lwRef: float, cap: int, join: int, miter: float) -> Array:
	var key := "s%.4f|%.3f|%d|%d|%.3f" % [spRef, lwRef, cap, join, miter]
	var hit = sh.cache.get(key)
	if hit != null:
		return hit
	var subs: Array = []
	var cl: Array = []
	var pg := polyGeo(sh, spRef)
	var P: PackedVector2Array = pg[0]
	var S: PackedInt32Array = pg[1]
	for k in S.size():
		var a := S[k]
		var b := S[k + 1] if k + 1 < S.size() else P.size()
		subs.append(P.slice(a, b))
		cl.append(true)
	var res := DACanvasGeom.stroke(subs, cl, lwRef * 0.5, cap, join, miter, GTOL)
	sh.cache[key] = res
	return res

# Ink bounding box of the shaped text in REF px (letter spacing applied).
static func inkBox(sh: Shaped, spRef: float) -> Rect2:
	var r := Rect2()
	var first := true
	for k in sh.glyphs.size():
		var g: Glyph = sh.glyphs[k][0]
		var b := g.box
		b.position += Vector2(_glyphX(sh, k, spRef), sh.glyphs[k][2])
		if first:
			r = b
			first = false
		else:
			r = r.merge(b)
	return r
