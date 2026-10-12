class_name MeadowKit
## Meshes and textures of the anime meadow and the wheat field (DOCE), after Trung Duy Nguyen's "Anime Grass"
## method, all generated here at startup (cached). Read by shaders/meadow_grass.gdshader, meadow_bloom.gdshader,
## wheat_ears.gdshader and wheat_canopy.gdshader. Origins at the root on the ground, +Y up, metres, models built
## 1 m tall where the shader rescales them.
##
## Vertex conventions (the shaders rely on them):
##   grass clump   UV  = (blade random 0..1, height fraction along the blade 0 root .. 1 tip)
##                 UV2 = (across the blade 0 .. 1, blade height / clump height)
##   billboard     UV  = (0..1 across, 0 bottom .. 1 top) of a camera-facing quad (VERTEX.x -0.5..0.5, y 0..1)
##   flowers       UV  = (part: 0 stem, 0.5 petal, 1 heart, height fraction), UV2 = (head random, petal radial 0..1)
##   wheat clump   UV  = (part: 0 stalk / leaf, 0.5 ear, 1 awn, height fraction of the whole plant),
##                 UV2 = (stalk random, height fraction within the ear)
## The mound texture (Trung's "transfer vertex normal"): see mound_texture().

static var _cache := {}


# --- shader variants -------------------------------------------------------------------------------------------

## FIXER: a program built from a shader's own source with `defines` inserted right after its stencil_mode line (the
## meadow's billboards: MEADOW_CARDS, the wheat's cards: WHEAT_CARDS, the lab's opaque-list test: MEADOW_OPAQUE). One
## source file, separate programs, so the 3D clumps carry no discard. Cached per (path, defines).
static func shader_variant(path: String, defines: PackedStringArray) -> Shader:
	var base: Shader = load(path)
	if defines.is_empty():
		return base
	var key := "shv_%s_%s" % [path, ",".join(defines)]
	if _cache.has(key):
		return _cache[key]
	var code := base.code
	var anchor := code.find("stencil_mode")
	var at := code.find("\n", anchor) + 1 if anchor >= 0 else code.find("\n", code.find("render_mode")) + 1
	var ins := ""
	for d in defines:
		ins += "#define %s\n" % d
	var sh := Shader.new()
	sh.code = code.insert(at, ins)
	_cache[key] = sh
	return sh


# --- the mound field ---------------------------------------------------------------------------------------------

## The mound field, as a tiling RGBA8 texture (`res` px over one tile), made the way Trung makes his displacement
## texture (Photoshop's Clouds + Cut Out, "the detail should be distinctive"): CLOUDS = seamless fractal noise with a
## little domain warp (organic blobs `feature_px` across), CUT OUT = posterised into `levels` steps of equal area,
## mixed back with the clouds (`cut` = how much of the cut-out is kept), BLURRED soft (two box passes of `blur_px`:
## rounded shoulders, so every blob is a soft dome with a lit and a shaded side), then:
##   RG  the slope (dH/dx, dH/dz), 0.5 + 0.5 * slope / norm (norm = the 97th percentile: 1 = 45 degrees at intensity 1)
##   B   the height, equalised to 0..1 (rank): the hollows (the folds) and the tops, also the two-tone colour mask
##   A   the cut-out levels 0..1 (crisp shapes)
static func mound_texture(res: int = 256, seed_value: int = 7, feature_px: float = 30.0, levels: int = 4, cut: float = 0.7, blur_px: int = 3) -> ImageTexture:
	var key := "mound_%d_%d_%d_%d_%d_%d" % [res, seed_value, int(feature_px * 10.0), levels, int(cut * 100.0), blur_px]
	if _cache.has(key):
		return _cache[key]
	var t0 := Time.get_ticks_usec()
	var n := res * res
	var fn := FastNoiseLite.new()
	fn.seed = seed_value
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.frequency = 1.0 / feature_px
	fn.fractal_type = FastNoiseLite.FRACTAL_FBM
	fn.fractal_octaves = 3
	fn.fractal_gain = 0.42
	fn.domain_warp_enabled = true
	fn.domain_warp_type = FastNoiseLite.DOMAIN_WARP_SIMPLEX
	fn.domain_warp_amplitude = feature_px * 0.35
	fn.domain_warp_frequency = 1.0 / (feature_px * 1.6)
	var cloud := fn.get_seamless_image(res, res, false, false, 0.12, true)
	cloud.convert(Image.FORMAT_L8)
	var cd := cloud.get_data()
	# Cut out: thresholds at equal-area quantiles (a 256-bin histogram of the clouds).
	var hist := PackedInt32Array()
	hist.resize(256)
	for i in n:
		hist[cd[i]] += 1
	var thr := PackedFloat32Array()
	var acc := 0
	var lv := 1
	for b in 256:
		acc += hist[b]
		while lv < levels and acc >= n * lv / levels:
			thr.append(float(b) + 0.5)
			lv += 1
	var hf := PackedFloat32Array()
	hf.resize(n)
	var cutv := PackedByteArray()
	cutv.resize(n)
	var fl := float(maxi(levels - 1, 1))
	for i in n:
		var v := float(cd[i])
		var st := 0
		for k in thr.size():
			if v > thr[k]:
				st = k + 1
		var sv := float(st) / fl
		cutv[i] = int(sv * 255.0)
		hf[i] = lerpf(v / 255.0, sv, cut)
	var hb := _box_blur(hf, res, blur_px)
	hb = _box_blur(hb, res, blur_px)
	# Equalise the height (rank via a 1024-bin histogram): B is uniform over 0..1, so the share of the field below a
	# given height is that height (the shaders' hollow term stays predictable).
	var lo := INF
	var hi := -INF
	for i in n:
		lo = minf(lo, hb[i])
		hi = maxf(hi, hb[i])
	var hb_n := 1024
	var h2 := PackedInt32Array()
	h2.resize(hb_n)
	var span := maxf(hi - lo, 1e-5)
	for i in n:
		h2[clampi(int((hb[i] - lo) / span * (hb_n - 1)), 0, hb_n - 1)] += 1
	var cdf := PackedFloat32Array()
	cdf.resize(hb_n)
	var run := 0
	for b in hb_n:
		run += h2[b]
		cdf[b] = (float(run) - 0.5 * float(h2[b])) / float(n)
	# Slope of the blurred field (per pixel), normalised.
	var gx := PackedFloat32Array()
	var gz := PackedFloat32Array()
	gx.resize(n)
	gz.resize(n)
	var mags := PackedFloat32Array()
	mags.resize(n)
	for y in res:
		var ym := posmod(y - 1, res) * res
		var yp := posmod(y + 1, res) * res
		var row := y * res
		for x in res:
			var a := (hb[row + posmod(x + 1, res)] - hb[row + posmod(x - 1, res)]) * 0.5
			var b := (hb[yp + x] - hb[ym + x]) * 0.5
			gx[row + x] = a
			gz[row + x] = b
			mags[row + x] = sqrt(a * a + b * b)
	var sorted := mags.duplicate()
	sorted.sort()
	var norm := maxf(sorted[int(n * 0.97)], 1e-5)
	var out := PackedByteArray()
	out.resize(n * 4)
	for i in n:
		var o := i * 4
		out[o] = clampi(int((0.5 + 0.5 * clampf(gx[i] / norm, -1.0, 1.0)) * 255.0 + 0.5), 0, 255)
		out[o + 1] = clampi(int((0.5 + 0.5 * clampf(gz[i] / norm, -1.0, 1.0)) * 255.0 + 0.5), 0, 255)
		out[o + 2] = clampi(int(cdf[clampi(int((hb[i] - lo) / span * (hb_n - 1)), 0, hb_n - 1)] * 255.0 + 0.5), 0, 255)
		out[o + 3] = cutv[i]
	var res_img := Image.create_from_data(res, res, false, Image.FORMAT_RGBA8, out)
	res_img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(res_img)
	_cache[key] = tex
	_cache["mound_img"] = res_img
	_cache["mound_ms"] = (Time.get_ticks_usec() - t0) / 1000
	return tex


## The last mound field built (Image, for the tools) and how long it took (ms).
static func mound_image() -> Image:
	if not _cache.has("mound_img"):
		mound_texture()
	return _cache["mound_img"]


static func mound_ms() -> int:
	return int(_cache.get("mound_ms", 0))


## Separable box blur of radius r on a res x res tiling field (running sums, O(n)).
static func _box_blur(src: PackedFloat32Array, res: int, r: int) -> PackedFloat32Array:
	var tmp := PackedFloat32Array()
	tmp.resize(src.size())
	var out := PackedFloat32Array()
	out.resize(src.size())
	var inv := 1.0 / float(2 * r + 1)
	for y in res:
		var row := y * res
		var acc := 0.0
		for k in range(-r, r + 1):
			acc += src[row + posmod(k, res)]
		for x in res:
			tmp[row + x] = acc * inv
			acc += src[row + posmod(x + r + 1, res)] - src[row + posmod(x - r, res)]
	for x in res:
		var acc := 0.0
		for k in range(-r, r + 1):
			acc += tmp[posmod(k, res) * res + x]
		for y in res:
			out[y * res + x] = acc * inv
			acc += tmp[posmod(y + r + 1, res) * res + x] - tmp[posmod(y - r, res) * res + x]
	return out


# --- the ground under the grass ----------------------------------------------------------------------------------

## FIXER: the painted grass of the GROUND under the clumps (terrain.gdshader, the anime meadow): a tiling `res` px tile of
## `n` tapered blade strokes seen from above, combed along +u (within +-35 degrees, one in six crossing back), each
## with its own root -> tip data, over nothing (A = 0: the depth of the stand). The terrain turns it into colour with
## the meadow's palette (dark roots, bright tips), so any gap between the 3D clumps reads as more grass, never as a
## flat lighter surface. Two scales of it are layered in the shader.
##   R  position along the blade (0 root .. 1 tip)    G  the blade's own shade (random 0..1)
##   B  across the blade (0..1)                       A  coverage (soft 1 px edge)
static func ground_strokes(res: int = 256, n: int = 300, seed_value: int = 77) -> ImageTexture:
	var key := "strokes_%d_%d_%d" % [res, n, seed_value]
	if _cache.has(key):
		return _cache[key]
	var t0 := Time.get_ticks_usec()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var px := PackedByteArray()
	px.resize(res * res * 4)
	px.fill(0)
	var cov_buf := PackedFloat32Array()
	cov_buf.resize(res * res)
	cov_buf.fill(0.0)
	var fres := float(res)
	for i in n:
		var p := Vector2(rng.randf() * fres, rng.randf() * fres)
		var ang := rng.randfn(0.0, 0.32)
		if rng.randf() < 0.16:
			ang = PI + rng.randfn(0.0, 0.4)
		var L := rng.randf_range(0.1, 0.19) * fres
		var w0 := rng.randf_range(0.016, 0.03) * fres
		var bow := rng.randf_range(-0.12, 0.12) * L
		var shade := rng.randf()
		var d := Vector2(cos(ang), sin(ang))
		var nr := Vector2(-d.y, d.x)
		var e := p + d * L
		var x0 := int(floor(minf(p.x, e.x) - w0 - absf(bow) - 2.0))
		var x1 := int(ceil(maxf(p.x, e.x) + w0 + absf(bow) + 2.0))
		var y0 := int(floor(minf(p.y, e.y) - w0 - absf(bow) - 2.0))
		var y1 := int(ceil(maxf(p.y, e.y) + w0 + absf(bow) + 2.0))
		for y in range(y0, y1 + 1):
			var yy := posmod(y, res)
			for x in range(x0, x1 + 1):
				var q := Vector2(float(x) + 0.5, float(y) + 0.5) - p
				var t := q.dot(d) / L
				if t < 0.0 or t > 1.0:
					continue
				var off := q.dot(nr) - bow * sin(PI * t)
				# tapered: full width at the root, a point at the tip
				var hw := 0.5 * w0 * pow(1.0 - t, 0.8) + 0.25
				var cov := clampf(hw - absf(off) + 0.5, 0.0, 1.0)
				if cov <= 0.0:
					continue
				var xx := posmod(x, res)
				var o := yy * res + xx
				if cov > 0.5 or cov_buf[o] < cov:
					cov_buf[o] = maxf(cov_buf[o], cov)
					var o4 := o * 4
					px[o4] = int(t * 255.0)
					px[o4 + 1] = int(shade * 255.0)
					px[o4 + 2] = int(clampf(0.5 + off / maxf(2.0 * hw, 0.01), 0.0, 1.0) * 255.0)
					px[o4 + 3] = int(cov_buf[o] * 255.0)
	var img := Image.create_from_data(res, res, false, Image.FORMAT_RGBA8, px)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	_cache["strokes_img"] = img
	_cache["strokes_ms"] = (Time.get_ticks_usec() - t0) / 1000
	return tex


# --- grass -------------------------------------------------------------------------------------------------------

## A low-poly grass clump (Trung: "mine uses just 16 triangles"), pivot at the root, 1 m tall: `blades` long,
## tapered, curved blades COMBED along +X (the shader turns each clump with a smooth combing field, so neighbouring
## clumps lean together like the strokes of a painted meadow): each leans `comb` (fraction of its height) towards
## +X within +-30 degrees, one in five crosses back the other way, heights 0.55..1 (the first blade is the tallest),
## roots spread over a small disc (`spread` m). `segs` 2 = a quad and a tip (3 triangles a blade), 3 = two quads and
## a tip (5 triangles). `width` is the blade width at the root (m). Each blade faces across its lean, turned a little.
static func grass_clump(seed_value: int, blades: int = 5, width: float = 0.07, comb: float = 0.42, segs: int = 2, spread: float = 0.07) -> ArrayMesh:
	var key := "clump_%d_%d_%d_%d_%d_%d" % [seed_value, blades, int(width * 1000.0), int(comb * 100.0), segs, int(spread * 1000.0)]
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_value * 7349 + 11)
	var v := PackedVector3Array()
	var nn := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	var ss: Array[float] = [0.0, 0.55, 1.0]
	var ws: Array[float] = [1.0, 0.66]
	if segs > 2:
		ss = [0.0, 0.4, 0.75, 1.0]
		ws = [1.0, 0.8, 0.5]
	for i in blades:
		var a := rng.randf() * TAU
		var root := Vector3(cos(a), 0.0, sin(a)) * spread * sqrt(rng.randf()) + Vector3(0, -0.04, 0)
		var hs := 1.0 if i == 0 else rng.randf_range(0.55, 0.95)
		var ang := rng.randfn(0.0, 0.32)
		if i > 0 and rng.randf() < 0.2:
			ang = PI + rng.randfn(0.0, 0.4)
		var d := Vector3(cos(ang), 0.0, sin(ang))
		var lean := comb * rng.randf_range(0.55, 1.25) * (1.15 - hs * 0.3)
		var H := hs
		var L := H * lean
		var w := width * rng.randf_range(0.8, 1.2) * (0.8 + 0.2 * hs)
		var br := rng.randf()
		var perp := Vector3(-d.z, 0, d.x).rotated(Vector3.UP, rng.randf_range(-0.5, 0.5))
		var pts: Array[Vector3] = []
		for s2 in ss:
			# the blade rises then arches over: the lean grows with the square of the height fraction
			pts.append(root + d * L * pow(s2, 1.8) + Vector3(0, H * s2 * (1.0 - 0.28 * s2 * lean), 0))
		var fn := (pts[1] - pts[0]).normalized().cross(perp).normalized()
		if fn.y < 0.0:
			fn = -fn
		var first := v.size()
		for k in ss.size() - 1:
			var ww := w * ws[k] * 0.5
			v.append(pts[k] - perp * ww)
			v.append(pts[k] + perp * ww)
			nn.append(fn)
			nn.append(fn)
			uv.append(Vector2(br, ss[k]))
			uv.append(Vector2(br, ss[k]))
			uv2.append(Vector2(0.0, hs))
			uv2.append(Vector2(1.0, hs))
		v.append(pts[ss.size() - 1])
		nn.append(fn)
		uv.append(Vector2(br, 1.0))
		uv2.append(Vector2(0.5, hs))
		for k in ss.size() - 2:
			var l0 := first + k * 2
			idx.append_array([l0, l0 + 1, l0 + 3, l0, l0 + 3, l0 + 2])
		var lt := first + (ss.size() - 2) * 2
		idx.append_array([lt, lt + 1, lt + 2])
	var m := _commit(v, nn, uv, uv2, PackedColorArray(), idx)
	_cache[key] = m
	return m


## A camera-facing billboard (2 triangles): VERTEX.x -0.5 .. 0.5, VERTEX.y 0 .. 1, UV (u, v up).
static func billboard() -> ArrayMesh:
	if _cache.has("billboard"):
		return _cache["billboard"]
	var v := PackedVector3Array([Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0), Vector3(0.5, 1, 0), Vector3(-0.5, 1, 0)])
	var nn := PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK])
	var uv := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	var uv2 := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	var m := _commit(v, nn, uv, uv2, PackedColorArray(), PackedInt32Array([0, 2, 1, 0, 3, 2]))
	_cache["billboard"] = m
	return m


## The painted side view of a clump of 26-40 blades for the far billboards (R height fraction, G shade 0 back .. 1
## front, B across, A coverage), 3 variants side by side in a 384 x 128 texture (MeadowPaint's brushes).
static func billboard_texture() -> ImageTexture:
	if _cache.has("bb_tex"):
		return _cache["bb_tex"]
	var c := MeadowPaint.Canvas.new(384, 128)
	var rects := [Rect2i(0, 0, 128, 128), Rect2i(128, 0, 128, 128), Rect2i(256, 0, 128, 128)]
	var seeds := [5101, 5202, 5303]
	var ns := [34, 40, 26]
	for k in 3:
		_paint_clump(c, rects[k], seeds[k], ns[k], [0.95, 0.8, 1.0][k], [0.22, 0.28, 0.35][k], [0.1, 0.2, 0.45][k])
	var tex := c.texture()
	_cache["bb_tex"] = tex
	_cache["bb_img"] = c.image()
	return tex


static func _paint_clump(c: MeadowPaint.Canvas, r: Rect2i, seed_value: int, n: int, hk: float, comb: float, wild: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var x0 := float(r.position.x)
	var y_bot := float(r.position.y + r.size.y) - 1.0
	var W := float(r.size.x)
	var Hmax := float(r.size.y) - 6.0
	var blades: Array = []
	for i in n:
		var u := clampf(0.5 + rng.randfn(0.0, 0.17 + wild * 0.04), 0.1, 0.9)
		var env := pow(maxf(0.0, 1.0 - pow(absf(u - 0.5) / 0.5, 2.0)), 0.45)
		var depth := rng.randf()
		var h := Hmax * hk * env * rng.randf_range(0.5, 1.0)
		if rng.randf() < 0.06 + wild * 0.2:
			h = minf(Hmax, h * rng.randf_range(1.15, 1.4))
		var lean := h * (comb * rng.randf_range(0.2, 1.0) + (u - 0.5) * 0.6 * (1.0 + wild))
		var w0 := rng.randf_range(7.0, 11.0) * MeadowPaint.mix(0.85, 1.1, depth)
		blades.append([depth, u, h, lean, w0, rng.randf_range(-0.15, 0.15) * h * (0.3 + wild)])
	blades.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	c.rect_fill(Rect2i(r.position.x + int(W * 0.12), r.position.y + r.size.y - 10, int(W * 0.76), 10), Color(0.0, 0.2, 0.5, 1.0))
	for b in blades:
		c.blade(Vector2(x0 + float(b[1]) * W, y_bot), float(b[2]), float(b[3]), float(b[5]), float(b[4]), 0.2 + 0.8 * float(b[0]), r)


# --- flowers -----------------------------------------------------------------------------------------------------

## A cluster of `heads` blossoms, pivot at the root, heads 0.72-1.0 m up (the shader scales the heights to the grass
## at the root, so the blossoms sit in the top of the grass, some half hidden among the blades): each blossom is ONE
## triangle that the shader turns towards the camera (tilted up like a flower facing the sky) and cuts into a
## 5-petal flower with a heart (per pixel: a disc with five rounded lobes inscribed in the triangle). ~1 triangle a
## flower: drifts of many small flowers for the price of a few stickers.
## Vertex data: VERTEX = the blossom's centre (cluster space, all three corners alike), UV = the corner in the
## blossom's plane (inradius 1: (0, 2), (-1.732, -1), (1.732, -1)), UV2 = (size factor 0.75..1.25, random 0..1).
static func flower_cluster(seed_value: int, heads: int = 14, spread: float = 0.22) -> ArrayMesh:
	var key := "blossoms_%d_%d_%d" % [seed_value, heads, int(spread * 100.0)]
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_value * 31 + 5)
	var v := PackedVector3Array()
	var nn := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	var corners := [Vector2(0.0, 2.0), Vector2(-1.7320508, -1.0), Vector2(1.7320508, -1.0)]
	for i in heads:
		var a := rng.randf() * TAU
		var r := spread * sqrt(rng.randf())
		var c := Vector3(cos(a) * r, rng.randf_range(0.72, 1.0), sin(a) * r)
		var sz := rng.randf_range(0.75, 1.25)
		var hr := rng.randf()
		var q := v.size()
		for k in 3:
			v.append(c)
			nn.append(Vector3.UP)
			uv.append(corners[k])
			uv2.append(Vector2(sz, hr))
		idx.append_array([q, q + 1, q + 2])
	var m := _commit(v, nn, uv, uv2, PackedColorArray(), idx)
	# every vertex sits at its blossom's centre: give the mesh a box that holds the expanded blossoms
	m.custom_aabb = AABB(Vector3(-spread - 0.1, -0.05, -spread - 0.1), Vector3(spread * 2.0 + 0.2, 1.2, spread * 2.0 + 0.2))
	_cache[key] = m
	return m


# --- wheat -------------------------------------------------------------------------------------------------------

## A wheat clump, pivot at the root, 1 m tall: `stalks` stalks (a thin quad each, 1 cm) carrying an EAR (a slim
## spindle, two crossed planes of 4 triangles: the grains swell in the middle and taper to the tip, ~3 cm wide and
## 13-17 cm long, nodding a little forward) and `awns` long awns (thin triangles fanning up and out from the ear),
## plus `leaves` drooping leaves low down. UV = (part: 0 stalk / leaf, 0.5 ear, 1 awn, height fraction of the
## plant), UV2 = (stalk random, height fraction within the ear). Built leaning slightly to +X (the shader turns it).
static func wheat_clump(seed_value: int, stalks: int = 4, awns: int = 2, leaves: int = 1) -> ArrayMesh:
	var key := "wheat_%d_%d_%d_%d" % [seed_value, stalks, awns, leaves]
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_value * 977 + 3)
	var v := PackedVector3Array()
	var nn := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	for i in stalks:
		var a := rng.randf() * TAU
		# (FIXER-2: a slightly wider tuft when it has more stalks)
		var r := (0.1 + 0.01 * maxf(stalks - 4, 0)) * sqrt(rng.randf())
		var base := Vector3(cos(a) * r, -0.04, sin(a) * r)
		var hs := rng.randf_range(0.86, 1.0)
		var tilt := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.02, 0.09) + Vector3(0.05, 0, 0)
		var ear_len := rng.randf_range(0.13, 0.17)
		var top := base + tilt * hs + Vector3(0, hs - ear_len * 0.8, 0)
		var hr := rng.randf()
		var face := Vector3(-sin(a + 1.3), 0, cos(a + 1.3))
		# stalk: a thin quad (1 cm)
		var s0 := v.size()
		var side := face * 0.005
		for p in [base - side, base + side, top - side, top + side]:
			v.append(p)
			nn.append(face.cross(Vector3.UP).normalized())
			uv.append(Vector2(0.0, clampf(p.y, 0.0, 1.0)))
			uv2.append(Vector2(hr, 0.0))
		idx.append_array([s0, s0 + 1, s0 + 3, s0, s0 + 3, s0 + 2])
		# ear: a slim spindle along the nodding axis, two crossed planes
		var nod := (Vector3(0, 1, 0) + tilt * 2.5 + Vector3(0.22, 0, 0) * rng.randf_range(0.5, 1.3)).normalized()
		var w := rng.randf_range(0.014, 0.018)
		for k in 2:
			var wd := (face if k == 0 else face.cross(nod).normalized()) * w
			var q := v.size()
			var pts := [top, top + nod * ear_len * 0.3 - wd, top + nod * ear_len * 0.3 + wd, top + nod * ear_len * 0.72 - wd * 0.85, top + nod * ear_len * 0.72 + wd * 0.85, top + nod * ear_len]
			var fr := [0.0, 0.3, 0.3, 0.72, 0.72, 1.0]
			for e in 6:
				var p: Vector3 = pts[e]
				v.append(p)
				nn.append(wd.cross(nod).normalized())
				uv.append(Vector2(0.5, clampf(p.y, 0.0, 1.0)))
				uv2.append(Vector2(hr, fr[e]))
			idx.append_array([q, q + 1, q + 2, q + 1, q + 3, q + 4, q + 1, q + 4, q + 2, q + 3, q + 5, q + 4])
		# awns: thin triangles from the ear's upper half, fanning up and out
		for k in awns:
			var o := top + nod * ear_len * rng.randf_range(0.45, 0.95)
			var dir := (nod + Vector3(rng.randf_range(-0.45, 0.45), 0.25, rng.randf_range(-0.45, 0.45))).normalized()
			var tip := o + dir * rng.randf_range(0.1, 0.16)
			var w2 := face * 0.0035
			var q2 := v.size()
			for p in [o - w2, o + w2, tip]:
				v.append(p)
				nn.append(face.cross(dir).normalized())
				uv.append(Vector2(1.0, clampf(p.y, 0.0, 1.0)))
				uv2.append(Vector2(hr, 1.0))
			idx.append_array([q2, q2 + 1, q2 + 2])
	for i in leaves:
		var a := rng.randf() * TAU
		var d := Vector3(cos(a), 0, sin(a))
		var h0 := rng.randf_range(0.3, 0.55)
		var root := d * 0.03 + Vector3(0, h0, 0)
		var mid := root + d * 0.13 + Vector3(0, 0.06, 0)
		var tip := mid + d * 0.13 + Vector3(0, -0.08, 0)
		var perp := Vector3(-d.z, 0, d.x) * 0.013
		var q := v.size()
		for p in [root - perp, root + perp, mid - perp * 0.8, mid + perp * 0.8, tip]:
			v.append(p)
			nn.append(Vector3.UP)
			uv.append(Vector2(0.0, clampf(p.y, 0.0, 1.0)))
			uv2.append(Vector2(rng.randf(), 0.0))
		idx.append_array([q, q + 1, q + 3, q, q + 3, q + 2, q + 2, q + 3, q + 4])
	var m := _commit(v, nn, uv, uv2, PackedColorArray(), idx)
	_cache[key] = m
	return m


# --- helpers -----------------------------------------------------------------------------------------------------

static func _commit(v: PackedVector3Array, n: PackedVector3Array, uv: PackedVector2Array, uv2: PackedVector2Array, col: PackedColorArray, idx: PackedInt32Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = n
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	if not col.is_empty():
		arrays[Mesh.ARRAY_COLOR] = col
	if not idx.is_empty():
		arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


static func tris(m: Mesh) -> int:
	var t := 0
	for s in m.get_surface_count():
		var a := m.surface_get_arrays(s)
		var ix: Variant = a[Mesh.ARRAY_INDEX]
		t += (ix as PackedInt32Array).size() / 3 if ix != null else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return t
