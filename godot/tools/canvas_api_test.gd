# Canvas 2D emulation feature test (scripts/gfx/canvas2d.gd): one 160x120 canvas per feature, the same drawing as
# the JS reference tests (scratchpad apitest/tests.js rendered in Chromium) so both can be compared pixel by pixel.
# Needs a rendering device (not --headless):
#   xvfb-run -a -s "-screen 0 1280x720x24" godot --path godot -s res://tools/canvas_api_test.gd -- out=/abs/dir
# Also runs a few non-visual assertions (colour parsing, measureText, getTransform, isPointInPath, getImageData).
extends SceneTree

var outDir := "user://canvas_api_test"
var canvases: Array = []
var n := 0
var fails := 0

func check(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
		push_error("[canvas_api_test] FAIL: " + what)
	else:
		print("[canvas_api_test] ok: " + what)

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			outDir = a.substr(4)
	DirAccess.make_dir_recursive_absolute(outDir)
	for name in ["rects", "fillrule", "strokes", "curves", "gradients", "pattern", "clip", "alpha", "composite", "shadows", "text", "transforms", "images", "path2d", "cpuread"]:
		var cv := DACanvas.new(160, 120)
		cv.bakeMode = "never"
		call("t_" + name, cv.getContext("2d"))
		canvases.append([name, cv])
	_asserts()
	RenderingServer.frame_post_draw.connect(_post)

func _asserts() -> void:
	check(DACanvas.parseColor("#f80a") == Color8(255, 136, 0, 170), "parseColor #rgba")
	check(DACanvas.parseColor("rgba(10, 20, 30, 0.5)") == Color8(10, 20, 30, 128), "parseColor rgba()")
	check(DACanvas.parseColor("hsl(120, 100%, 50%)") == Color8(0, 255, 0), "parseColor hsl()")
	check(DACanvas.parseColor("teal") == Color8(0, 128, 128), "parseColor named")
	check(DACanvas.parseColor("nonsense") == null, "parseColor invalid -> null")
	var cv := DACanvas.new(10, 10)
	var c = cv.getContext("2d")
	c.fillStyle = "#123456"
	check(c.fillStyle == "#123456", "fillStyle serialises")
	c.fillStyle = "not a colour"
	check(c.fillStyle == "#123456", "invalid fillStyle ignored")
	c.translate(5, 6)
	c.scale(2, 3)
	var m: Dictionary = c.getTransform()
	check(m.a == 2 and m.d == 3 and m.e == 5 and m.f == 6, "getTransform")
	c.resetTransform()
	c.font = "48px Bungee"
	var mt: Dictionary = c.measureText("HULLABALOO")
	check(absf(mt.width - 347.953) < 0.5, "measureText Bungee width (Chrome 347.953): %.3f" % mt.width)
	c.font = "bold 20px \"Titan One\", sans-serif"
	check(c.font == "bold 20px \"Titan One\", sans-serif", "font keeps the CSS string")
	var p := DAPath2D.new("M0 0 L10 0 L10 10 Z")
	check(c.isPointInPath(p, 8, 2) and not c.isPointInPath(p, 2, 8), "isPointInPath")
	c.setLineDash([4, 2, 1])
	check(c.getLineDash() == [4.0, 2.0, 1.0, 4.0, 2.0, 1.0], "setLineDash odd list doubles")

func _post() -> void:
	n += 1
	if n < 3:
		return
	if n > 3:
		return
	for e in canvases:
		var img: Image = (e[1] as DACanvas).toImage()
		img.save_png(outDir.path_join(e[0] + ".png"))
	# synchronous readback on a GPU canvas
	var cv := DACanvas.new(8, 8)
	var c = cv.getContext("2d")
	c.fillStyle = "rgba(255,0,0,0.5)"
	c.fillRect(0, 0, 4, 8)
	var d: PackedByteArray = c.getImageData(0, 0, 8, 8).data
	check(d[0] == 255 and absi(d[3] - 128) <= 1 and d[4 * 5 + 3] == 0, "getImageData on GPU canvas (straight alpha)")
	print("[canvas_api_test] %d failures" % fails)
	quit(1 if fails > 0 else 0)

# ------------------------------------------------------------------------------------------------ tests (1:1 tests.js)
func t_rects(c) -> void:
	c.fillStyle = "#2F5BD3"; c.fillRect(10, 10, 60, 40); c.strokeStyle = "#E23B3B"; c.lineWidth = 5; c.strokeRect(80, 10, 60, 40); c.fillStyle = "rgba(255,200,0,0.5)"; c.fillRect(40, 30, 60, 40); c.clearRect(20, 20, 20, 20); c.fillStyle = "hsl(120, 60%, 40%)"; c.fillRect(10, 80, 30, 30); c.fillStyle = "teal"; c.fillRect(50, 80, 30, 30); c.fillStyle = "#f80a"; c.fillRect(90, 80, 30, 30)

func t_fillrule(c) -> void:
	var star := func():
		c.beginPath()
		for i in 5:
			var a := -PI / 2 + i * 4 * PI / 5
			c.lineTo(40 + cos(a) * 34, 55 + sin(a) * 34)
		c.closePath()
	c.fillStyle = "#E3662B"; star.call(); c.fill(); c.translate(75, 0); star.call(); c.fill("evenodd"); c.setTransform(1, 0, 0, 1, 0, 0)
	c.beginPath(); c.arc(40, 100, 16, 0, TAU); c.arc(40, 100, 8, 0, TAU, true); c.fillStyle = "#2E8C8C"; c.fill()
	c.beginPath(); c.arc(115, 100, 16, 0, TAU); c.arc(115, 100, 8, 0, TAU); c.fill("evenodd")

func t_strokes(c) -> void:
	c.lineWidth = 10; c.strokeStyle = "#2A1D3A"
	var caps := ["butt", "round", "square"]
	for i in 3:
		c.lineCap = caps[i]; c.beginPath(); c.moveTo(15, 15 + i * 18); c.lineTo(65, 15 + i * 18); c.stroke()
	c.lineCap = "butt"
	var joins := ["miter", "round", "bevel"]
	for i in 3:
		c.lineJoin = joins[i]; c.beginPath(); c.moveTo(80 + i * 26, 50); c.lineTo(90 + i * 26, 12); c.lineTo(100 + i * 26, 50); c.stroke()
	c.lineJoin = "miter"; c.miterLimit = 2; c.beginPath(); c.moveTo(20, 110); c.lineTo(35, 70); c.lineTo(50, 110); c.stroke()
	c.miterLimit = 10; c.lineWidth = 3; c.setLineDash([8, 4, 2, 4]); c.lineDashOffset = 3; c.strokeStyle = "#E23B3B"; c.beginPath(); c.moveTo(60, 100); c.bezierCurveTo(90, 60, 120, 130, 150, 80); c.stroke(); c.setLineDash([])
	c.strokeStyle = "rgba(40,120,255,0.5)"; c.lineWidth = 12; c.lineJoin = "round"; c.beginPath(); c.moveTo(70, 70); c.lineTo(150, 110); c.lineTo(100, 115); c.lineTo(140, 60); c.stroke()

func t_curves(c) -> void:
	c.lineWidth = 3; c.strokeStyle = "#2A1D3A"; c.fillStyle = "#FFD23A"
	c.beginPath(); c.arc(30, 30, 20, 0.3, 4.5); c.stroke()
	c.beginPath(); c.arc(80, 30, 20, 0.3, 4.5, true); c.stroke()
	c.beginPath(); c.ellipse(130, 30, 22, 12, 0.5, 0, TAU); c.fill(); c.stroke()
	c.beginPath(); c.moveTo(10, 70); c.arcTo(60, 70, 60, 110, 18); c.lineTo(60, 110); c.stroke()
	c.beginPath(); c.moveTo(70, 110); c.quadraticCurveTo(95, 50, 120, 110); c.bezierCurveTo(130, 60, 150, 60, 155, 100); c.stroke()
	c.beginPath(); c.roundRect(12, 78, 30, 30, [10, 2, 6, 14]); c.fillStyle = "#52D24A"; c.fill()

func t_gradients(c) -> void:
	var g = c.createLinearGradient(0, 0, 70, 0); g.addColorStop(0, "#FF3B30"); g.addColorStop(0.5, "rgba(255,255,255,0)"); g.addColorStop(1, "#3A7BFF")
	c.fillStyle = g; c.fillRect(5, 5, 70, 50)
	g = c.createRadialGradient(115, 30, 4, 110, 30, 28); g.addColorStop(0, "#FFFFFF"); g.addColorStop(0.4, "#FFD23A"); g.addColorStop(1, "#6B3A6E")
	c.fillStyle = g; c.fillRect(80, 5, 75, 50)
	g = c.createRadialGradient(40, 90, 10, 55, 90, 30); g.addColorStop(0, "#52E04A"); g.addColorStop(1, "#1E1530")
	c.fillStyle = g; c.fillRect(5, 62, 70, 53)
	g = c.createConicGradient(0.5, 115, 88)
	var cs := ["#FF3B30", "#FFD23A", "#52E04A", "#3A7BFF", "#FF3B30"]
	for i in cs.size():
		g.addColorStop(i / 4.0, cs[i])
	c.fillStyle = g; c.beginPath(); c.arc(115, 88, 26, 0, TAU); c.fill()
	c.save(); c.translate(80, 60); c.scale(2, 0.5); g = c.createLinearGradient(0, 0, 0, 40); g.addColorStop(0, "#000"); g.addColorStop(1, "#fff"); c.strokeStyle = g; c.lineWidth = 4; c.strokeRect(2, 2, 36, 100); c.restore()

func t_pattern(c) -> void:
	var t := DACanvas.new(16, 16)
	var g = t.getContext("2d")
	g.fillStyle = "#FFD23A"; g.fillRect(0, 0, 16, 16); g.fillStyle = "#2F5BD3"; g.fillRect(0, 0, 8, 8); g.fillRect(8, 8, 8, 8)
	c.fillStyle = c.createPattern(t, "repeat"); c.fillRect(5, 5, 70, 50)
	c.save(); c.translate(90, 10); c.rotate(0.3); c.fillStyle = c.createPattern(t, "repeat-x"); c.fillRect(0, 0, 60, 40); c.restore()
	var p = c.createPattern(t, "repeat"); p.setTransform({"a": 2, "b": 0, "c": 0, "d": 2, "e": 0, "f": 0}); c.fillStyle = p; c.beginPath(); c.arc(40, 90, 26, 0, TAU); c.fill()
	c.fillStyle = c.createPattern(t, "no-repeat"); c.translate(95, 70); c.fillRect(0, 0, 50, 45)

func t_clip(c) -> void:
	c.fillStyle = "#1E1530"; c.fillRect(0, 0, 160, 120)
	c.save(); c.beginPath(); c.arc(60, 60, 45, 0, TAU); c.clip()
	c.fillStyle = "#E3662B"; c.fillRect(0, 0, 160, 120)
	c.beginPath(); c.rect(40, 20, 100, 60); c.clip()
	c.fillStyle = "rgba(255,255,255,0.7)"; c.fillRect(0, 0, 160, 120)
	c.restore()
	c.save(); c.beginPath(); c.moveTo(110, 70); c.lineTo(155, 115); c.lineTo(100, 115); c.closePath(); c.clip(); c.fillStyle = "#52E04A"; c.beginPath(); c.arc(120, 100, 22, 0, TAU); c.fill(); c.restore()
	c.save(); c.rect(5, 5, 30, 30); c.clip(); c.lineWidth = 6; c.strokeStyle = "#FFD23A"; c.strokeRect(5, 5, 30, 30); c.restore()

func t_alpha(c) -> void:
	c.fillStyle = "#F4F1E8"; c.fillRect(0, 0, 160, 120)
	c.globalAlpha = 0.5; c.fillStyle = "#E23B3B"; c.beginPath(); c.arc(50, 50, 30, 0, TAU); c.arc(80, 50, 30, 0, TAU); c.fill()
	c.globalAlpha = 1; c.strokeStyle = "rgba(0,0,200,0.4)"; c.lineWidth = 14; c.lineCap = "round"; c.beginPath(); c.moveTo(20, 100); c.lineTo(140, 100); c.lineTo(140, 60); c.lineTo(100, 110); c.stroke()
	c.globalAlpha = 0.3; c.drawImage(c.canvas, 0, 0, 160, 120, 100, 5, 55, 40)

func t_composite(c) -> void:
	var ops := ["source-over", "source-in", "source-out", "source-atop", "destination-over", "destination-in", "destination-out", "destination-atop", "lighter", "copy", "xor", "multiply", "screen", "overlay", "darken", "lighten", "color-dodge", "color-burn", "hard-light", "soft-light", "difference", "exclusion", "hue", "saturation", "color", "luminosity"]
	var s := DACanvas.new(30, 22)
	var g = s.getContext("2d")
	for i in ops.size():
		g.globalCompositeOperation = "source-over"; g.clearRect(0, 0, 30, 22)
		g.fillStyle = "rgba(40,110,255,0.9)"; g.fillRect(2, 2, 16, 14)
		g.globalCompositeOperation = ops[i]; g.fillStyle = "rgba(255,200,40,0.8)"; g.beginPath(); g.arc(19, 13, 8, 0, TAU); g.fill()
		c.drawImage(s, (i % 5) * 32, (i / 5) * 20)

func t_shadows(c) -> void:
	c.fillStyle = "#F4F1E8"; c.fillRect(0, 0, 160, 120)
	c.shadowColor = "rgba(40,20,60,0.7)"; c.shadowBlur = 10; c.shadowOffsetX = 6; c.shadowOffsetY = 6
	c.fillStyle = "#2F5BD3"; c.fillRect(15, 15, 50, 35)
	c.shadowColor = "#FF4FA0"; c.shadowBlur = 16; c.shadowOffsetX = 0; c.shadowOffsetY = 0
	c.strokeStyle = "#FFFFFF"; c.lineWidth = 4; c.beginPath(); c.arc(115, 35, 20, 0, TAU); c.stroke()
	c.shadowColor = "#000"; c.shadowBlur = 0; c.shadowOffsetX = 4; c.shadowOffsetY = 3; c.font = "28px Bungee"; c.fillStyle = "#FFD23A"; c.fillText("HI!", 20, 100)
	c.shadowColor = "rgba(0,0,0,0)"; c.filter = "blur(3px)"; c.fillStyle = "#52D24A"; c.fillRect(100, 70, 40, 35)
	c.filter = "brightness(0.5)"; c.fillStyle = "#E3662B"; c.fillRect(85, 90, 20, 20); c.filter = "none"

func t_text(c) -> void:
	c.fillStyle = "#1E1530"; c.fillRect(0, 0, 160, 120)
	c.fillStyle = "#FFD23A"; c.font = "26px Shrikhand"; c.textAlign = "left"; c.textBaseline = "alphabetic"; c.fillText("Dead Air", 6, 30)
	c.font = "18px \"Titan One\""; c.textAlign = "center"; c.textBaseline = "middle"; c.strokeStyle = "#E23B3B"; c.lineWidth = 4; c.lineJoin = "round"; c.strokeText("WZTV 13", 80, 50); c.fillStyle = "#fff"; c.fillText("WZTV 13", 80, 50)
	c.font = "22px VT323"; c.textAlign = "right"; c.textBaseline = "top"; c.fillStyle = "#5CFF6E"; c.fillText("CH 03", 155, 64)
	c.font = "14px Bungee"; c.textAlign = "left"; c.textBaseline = "bottom"; c.letterSpacing = "3px"; c.fillText("SPACED", 6, 90); c.letterSpacing = "0px"
	var m = c.measureText("SPACED"); c.fillStyle = "rgba(255,255,255,0.3)"; c.fillRect(6, 92, m.width, 3)
	c.font = "bold 16px \"Courier New\", monospace"; c.textBaseline = "hanging"; c.fillStyle = "#9CFF57"; c.fillText("Courier", 6, 98)
	c.save(); c.translate(110, 105); c.rotate(-0.3); c.font = "16px Bungee"; var g = c.createLinearGradient(0, -10, 0, 6); g.addColorStop(0, "#fff"); g.addColorStop(1, "#3A7BFF"); c.fillStyle = g; c.textAlign = "center"; c.textBaseline = "middle"; c.fillText("ROT", 0, 0, 40); c.restore()

func t_transforms(c) -> void:
	c.fillStyle = "#2F5BD3"
	c.save(); c.translate(40, 40); c.rotate(0.5); c.fillRect(-15, -15, 30, 30); c.restore()
	c.save(); c.transform(1, 0, 0.6, 1, 60, 10); c.fillStyle = "#E3662B"; c.fillRect(0, 0, 30, 30); c.restore()
	c.save(); c.setTransform(0.5, 0.2, -0.2, 1.2, 120, 10); c.fillStyle = "#52D24A"; c.fillRect(0, 0, 30, 30); c.restore()
	c.save(); c.translate(40, 90); c.scale(2, 0.6); c.beginPath(); c.arc(0, 0, 14, 0, TAU); c.lineWidth = 3; c.strokeStyle = "#2A1D3A"; c.stroke(); c.restore()
	c.save(); c.translate(110, 90); c.scale(-1, 1); c.font = "20px Bungee"; c.textAlign = "center"; c.textBaseline = "middle"; c.fillStyle = "#FF4FA0"; c.fillText("MIR", 0, 0); c.restore()
	var m = c.getTransform(); c.fillStyle = "#000"; c.fillRect(m.e + 150, m.f + 110, 4, 4)

func t_images(c) -> void:
	var s := DACanvas.new(8, 8)
	var g = s.getContext("2d")
	for y in 8:
		for x in 8:
			g.fillStyle = "#FFD23A" if ((x + y) & 1) else "#6B3A6E"
			g.fillRect(x, y, 1, 1)
	c.drawImage(s, 5, 5)
	c.drawImage(s, 20, 5, 40, 40)
	c.imageSmoothingEnabled = false; c.drawImage(s, 65, 5, 40, 40); c.imageSmoothingEnabled = true
	c.drawImage(s, 2, 2, 4, 4, 110, 5, 40, 40)
	c.save(); c.translate(40, 85); c.rotate(0.4); c.globalAlpha = 0.7; c.drawImage(s, -25, -25, 50, 50); c.restore()
	var d: Dictionary = c.getImageData(20, 5, 40, 40)
	var dd: PackedByteArray = d.data
	var i := 0
	while i < dd.size():
		dd[i] = 255 - dd[i]
		i += 4
	d.data = dd
	c.putImageData(d, 100, 60)
	var e: Dictionary = c.createImageData(30, 10)
	var ed: PackedByteArray = e.data
	i = 0
	while i < ed.size():
		ed[i + 1] = 200
		ed[i + 3] = ((i / 4) % 30) * 8
		i += 4
	e.data = ed
	c.putImageData(e, 100, 105)

func t_path2d(c) -> void:
	var p := DAPath2D.new("M20 20 C60 0 100 40 140 20 L140 60 Q80 100 20 60 Z")
	c.fillStyle = "#8CCB6A"; c.fill(p); c.lineWidth = 3; c.strokeStyle = "#2A1D3A"; c.stroke(p)
	var q := DAPath2D.new(); q.arc(80, 95, 18, 0, TAU); q.rect(20, 80, 30, 30); var q2 := DAPath2D.new(q); q2.moveTo(110, 80); q2.lineTo(150, 110); q2.lineTo(110, 110); q2.closePath()
	c.fillStyle = "#3A7BFF"; c.fill(q2)
	c.fillStyle = "#FFD23A" if c.isPointInPath(p, 80, 40) else "#E23B3B"; c.fillRect(75, 35, 10, 10)
	c.fillStyle = "#FFD23A" if c.isPointInPath(p, 5, 5) else "#E23B3B"; c.fillRect(2, 2, 6, 6)
	var a := DAPath2D.new("M120 10 a15 10 0 1 0 30 0 a15 10 0 1 0 -30 0 h-10 v8 l-4 -4 z"); c.strokeStyle = "#FF4FA0"; c.stroke(a)

func t_cpuread(c) -> void:
	var m := DACanvas.new(32, 24)
	var g = m.getContext("2d", {"willReadFrequently": true})
	g.fillStyle = "#000"; g.fillRect(0, 0, 32, 24); g.fillStyle = "#fff"; g.beginPath(); g.arc(16, 12, 9, 0, TAU); g.fill(); g.lineWidth = 2; g.strokeStyle = "#888"; g.beginPath(); g.moveTo(2, 2); g.lineTo(30, 20); g.stroke()
	var d: PackedByteArray = g.getImageData(0, 0, 32, 24).data
	for y in 24:
		for x in 32:
			var v := d[(y * 32 + x) * 4]
			c.fillStyle = "rgb(%d,%d,60)" % [v, int(floorf(v * 0.8 + 0.5))]
			c.fillRect(x * 5, y * 5, 5, 5)
