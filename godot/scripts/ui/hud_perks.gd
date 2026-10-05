# HudPerks — the PERK TRAY of the HUD (built by scripts/ui/hud.gd on its first world frame, solo and MP alike), the
# Call-of-Duty-Zombies-style row of the sponsor products the local player owns. Wordless like the rest of the HUD:
# every perk is a round "sticker" slapped next to the WZTV round dial (bottom left, vertically centred on the dial,
# purchase order left to right): a cream rim (gold leaf after the Morning Show) around the sponsor's starburst with
# its product package (DACards.PRODUCTS + DACards.starburst, the art of the sponsor_logo_<perkId> card, drawn once
# per perk into a 160 px DACanvas, no raster files), each one tilted a little like a real sticker.
#   - joins: pops in (white flash disc, overshooting scale + untwist, a ring of star rays) once the HUD is back on
#     screen after the commercial (it waits while the HUD is hidden / suppressed); several at once (Morning Show)
#     pop one after another.
#   - Replay-Ade: three pips under the sticker = the game's stock of bottles (T.perks.replayMax): spent ones dark,
#     the one you carry bright gold, the ones still for sale hollow; the gold Morning Show bottle shows one pip that
#     goes dark once this round's replay is used. The sticker flickers during an INSTANT REPLAY and, when the bottle
#     is consumed, leaves rewinding (spins backwards with a cyan / magenta VHS split).
#   - other losses (MP bleed-out: perks.clearAll) leave with a grey poof; a new game clears the tray at once.
#   - MP: only the local player's perks (game.perks is local); the tray dims / hides with the ammo while downed /
#     off-air (hud._mpDim). drawDots(ci, ids, xRight, cy, a) draws a teammate's loadout as tiny sponsor-colour dots
#     (hud_team.gd rows).
# Cost: one list diff per frame; the Control redraws only while something animates (or a pip / blink changes).
extends RefCounted

const SIZE := 60.0          # sticker diameter (reference px)
const GAP := 12.0
const TEX := 160            # sticker canvas px
const POP := 0.55           # s: pop-in
const POP_STAGGER := 0.14   # s between pops queued in the same frame
const POOF := 0.45          # s: poof out
const REWIND := 0.75        # s: Replay-Ade consumed
const TILT := {"replay_ade": -6.0, "wobble_up": 5.0, "jump_cut": -3.0, "roller_boogie": 7.0, "double_vision": -5.0}
const INK := "#2A1D3A"
# product size (x face radius) and vertical offset (x face radius) inside the sticker, per package shape
const PROD_FIT := {"replay_ade": [1.5, 0.04], "wobble_up": [1.12, 0.06], "jump_cut": [1.25, 0.1], "roller_boogie": [1.3, 0.04], "double_vision": [1.35, 0.04]}

var hud
var game
var H                       # the hud.gd script (static helpers, DrawCtl)
var ctl: Control
var slots: Array = []       # [{id, t (s since the pop started; < 0 = waiting), out ("" | "poof" | "rewind"), ot, x}]
var _tex := {}              # "<id>|<gold>" -> Texture2D
var _sig := ""
var _time := 0.0
var _dim := 1.0

func _init(h) -> void:
	hud = h
	game = h.game
	H = h.get_script()
	ctl = H.DrawCtl.new(_draw, "perks")
	ctl.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	hud.stage.add_child(ctl)
	layout(hud.stageW)

func layout(_W: float) -> void:
	# right of the round dial (hud: dial at (M, REF_H - M - 84), 84 x 84), centred on it
	ctl.position = Vector2(H.M + 84.0 + 22.0, H.REF_H - H.M - 42.0)

func reset() -> void:
	slots.clear()
	_sig = ""
	ctl.queue_redraw()

# ------------------------------------------------------------------------------------------------ per frame
func update(dt: float) -> void:
	_time += dt
	var P = game.get("perks")
	var list: Array = P.list if P != null else []
	var shown: bool = hud.stage.visible and hud._supp.is_empty()
	var anim := false
	# gains: a new slot waits (t < 0) until the HUD is on screen, then pops; queued pops are staggered
	var have := {}
	for s in slots:
		if s.out == "":
			have[s.id] = true
	var queued := 0
	for s in slots:
		if s.t < 0.0:
			queued += 1
	for id in list:
		if not have.has(id):
			slots.append({"id": id, "t": -0.12 - POP_STAGGER * queued, "out": "", "ot": 0.0, "x": -1.0})
			queued += 1
			anim = true
	# losses
	for s in slots:
		if s.out == "" and not list.has(s.id):
			s.out = "rewind" if s.id == "replay_ade" and P != null and P.replayActive else "poof"
			s.ot = 0.0
			if s.t < 0.0:
				s.ot = 99.0     # never shown: drop at once
	# clocks
	for i in range(slots.size() - 1, -1, -1):
		var s: Dictionary = slots[i]
		if s.out != "":
			s.ot += dt
			if s.ot >= (REWIND if s.out == "rewind" else POOF):
				slots.remove_at(i)
				anim = true
				continue
			anim = true
		if s.t < POP and (shown or s.t >= 0.0):
			s.t += dt
			anim = true
	# positions: live slots slide toward their place; a slot leaving stays where it was while it vanishes
	var i2 := 0
	for s in slots:
		if s.out != "":
			continue
		var tx := i2 * (SIZE + GAP) + SIZE / 2.0
		if s.x < 0.0:
			s.x = tx
		elif absf(s.x - tx) > 0.25:
			s.x = lerpf(s.x, tx, 1.0 - exp(-dt * 14.0))
			anim = true
		else:
			s.x = tx
		i2 += 1
	# dim with the own elements while downed / off-air (MP)
	var dim: float = hud._mpDim if hud._mpDim >= 0.0 else 1.0
	if dim != _dim:
		_dim = dim
		ctl.modulate.a = dim
	var sig := _pipSig(P)
	if anim or sig != _sig:
		_sig = sig
		ctl.queue_redraw()

# Replay-Ade state that changes the drawing without an animation (pips, the replay flicker frame).
func _pipSig(P) -> String:
	if P == null or not P.has("replay_ade"):
		return ""
	var S = game.get("sponsors")
	var flick := ""
	if P.replayActive:
		flick = str(int(_time / 0.125) % 2)
	return "%d|%s|%s|%s" % [int(S.replayBought) if S != null else 0, str(P.gold), str(_goldUsed(P)), flick]

func _goldUsed(P) -> bool:
	if not P.gold:
		return false
	var R = game.get("rounds")
	return R != null and int(P._goldReplayRound) == int(R.get("round") if R.get("round") != null else -2)

# ------------------------------------------------------------------------------------------------ art
func sticker(id: String, gold: bool) -> Texture2D:
	var key := "%s|%s" % [id, gold]
	if _tex.has(key):
		return _tex[key]
	var c = paintSticker(id, gold)
	var t: Texture2D = null
	if c != null:
		c.bakeMode = "now"
		c.mipmaps = true
		t = c.texture
	_tex[key] = t
	return t

# The sticker art (TEX x TEX DACanvas, transparent outside the disc) or null for an unknown perk.
static func paintSticker(id: String, gold: bool):
	if not DACards.SPONSORS.has(id):
		return null
	var S: Dictionary = DACards.SPONSORS[id]
	var c := DACards.makeCanvas(TEX, TEX)
	c.opaque = false
	var ctx = c.getContext("2d")
	var m := TEX / 2.0
	# drop shadow + ink edge + rim (cream; gold leaf after the Morning Show)
	DACards.circle(ctx, m, m + 3.0, m - 3.0)
	DACards.fill(ctx, "rgba(20,10,28,0.55)")
	DACards.circle(ctx, m, m, m - 4.0)
	DACards.fill(ctx, INK)
	DACards.circle(ctx, m, m, m - 8.0)
	DACards.fill(ctx, DACards.linear(ctx, 0, 0, 0, TEX, ["#FFF1A8", "#F2B53A", "#A86A12"]) if gold else DACards.linear(ctx, 0, 0, 0, TEX, ["#FFFFFF", "#F6E7C8", "#E2CFA4"]))
	# the logo card's starburst + product, clipped to the sticker face
	var r := m - 15.0
	var pf: Array = PROD_FIT.get(id, [1.4, 0.0])
	ctx.save()
	DACards.circle(ctx, m, m, r)
	ctx.clip()
	DACards.starburst(ctx, float(TEX), float(TEX), m, m * 1.05, S.main, DACards.lighten(S.main, 0.3), 16)
	# lower lip in the sponsor's deep colour (the logo card's ribbon), behind the product
	ctx.fillStyle = S.deep
	ctx.globalAlpha = 0.85
	ctx.fillRect(0, m + r * 0.72, TEX, TEX)
	ctx.globalAlpha = 1.0
	DACards.PRODUCTS[id].call(ctx, m, m + r * float(pf[1]), r * float(pf[0]), 0.1)
	ctx.restore()
	DACards.circle(ctx, m, m, r)
	DACards.stroke(ctx, S.deep, 4.0)
	# gloss + a glint (no canvas shadow: it would blur a box at this size)
	DACards.ellipse(ctx, m - r * 0.38, m - r * 0.52, r * 0.42, r * 0.2, -0.55)
	DACards.fill(ctx, "rgba(255,255,255,0.32)")
	DACards.starPath(ctx, m + r * 0.66, m - r * 0.62, 10.0, 1.8, 4, 0)
	DACards.fill(ctx, "#FFFFFF")
	return c

# A teammate's loadout as tiny sponsor dots ending at xRight (right-aligned). Returns the width used.
func drawDots(ci: CanvasItem, ids: Array, xRight: float, cy: float, a: float = 1.0) -> float:
	var n := ids.size()
	if n == 0:
		return 0.0
	var x := xRight - 5.0
	for i in range(n - 1, -1, -1):
		var S = DACards.SPONSORS.get(ids[i])
		if S == null:
			continue
		ci.draw_circle(Vector2(x, cy + 1.5), 6.0, Color(0, 0, 0, 0.45 * a))
		ci.draw_circle(Vector2(x, cy), 6.0, Color(DAU.color(INK), a))
		ci.draw_circle(Vector2(x, cy), 4.5, Color(DAU.color(S.main), a))
		ci.draw_circle(Vector2(x - 1.3, cy - 1.5), 1.5, Color(1, 1, 1, 0.6 * a))
		x -= 14.0
	return n * 14.0

# ------------------------------------------------------------------------------------------------ painting
func _draw(ci: Control) -> void:
	var P = game.get("perks")
	var gold: bool = P != null and P.gold
	for s in slots:
		if s.t < 0.0:
			continue
		var tex := sticker(s.id, gold)
		if tex == null:
			continue
		var k := clampf(s.t / POP, 0.0, 1.0)
		var tilt := deg_to_rad(float(TILT.get(s.id, 0.0)))
		var sc := 1.0
		var rot := tilt
		var a := 1.0
		var c := Vector2(s.x, 0.0)
		# pop-in: overshooting scale (easeOutBack) + untwist from -35 deg; flash disc + star rays behind
		if k < 1.0:
			var e := clampf(k / 0.75, 0.0, 1.0)
			sc = 1.0 + 2.6 * pow(e - 1.0, 3.0) + 1.6 * pow(e - 1.0, 2.0)
			rot = lerpf(deg_to_rad(-35.0), tilt, H.cssEaseOut(e))
			var fl := 1.0 - clampf(k / 0.45, 0.0, 1.0)
			if fl > 0.0:
				ci.draw_circle(c, SIZE * (0.35 + 0.55 * (1.0 - fl)), Color(1.0, 0.98, 0.85, 0.85 * fl))
			var rk := clampf((k - 0.1) / 0.9, 0.0, 1.0)
			if rk > 0.0 and rk < 1.0:
				var col := Color(DAU.color("#FFE27A"), 1.0 - rk)
				for j in 8:
					var ang := j * TAU / 8.0 + 0.2
					var d := Vector2.from_angle(ang)
					var r0 := SIZE * (0.45 + 0.45 * rk)
					ci.draw_line(c + d * r0, c + d * (r0 + 10.0 * (1.0 - rk) + 3.0), col, 3.0, true)
		# leaving
		if s.out == "poof":
			var q := clampf(s.ot / POOF, 0.0, 1.0)
			sc = (1.0 + 0.18 * sin(minf(q / 0.35, 1.0) * PI * 0.5)) * (1.0 - H.cssEase(clampf((q - 0.3) / 0.7, 0.0, 1.0)))
			a = 1.0 - q * q
			for j in 5:
				var d2 := Vector2.from_angle(j * TAU / 5.0 - 0.6)
				ci.draw_circle(c + d2 * SIZE * (0.3 + 0.5 * q), SIZE * 0.14 * (1.0 - q * 0.6), Color(0.85, 0.83, 0.8, 0.6 * (1.0 - q)))
		elif s.out == "rewind":
			var q2 := clampf(s.ot / REWIND, 0.0, 1.0)
			rot = tilt - TAU * 1.5 * H.cssEaseInOut(q2)
			sc = 1.0 - 0.85 * q2 * q2
			a = 1.0 - clampf((q2 - 0.55) / 0.45, 0.0, 1.0)
		if sc <= 0.01:
			continue
		var bl := 1.0
		if s.out == "" and s.id == "replay_ade" and P != null and P.replayActive:
			bl = 0.35 if int(_time / 0.125) % 2 == 1 else 1.0
		var half := SIZE / 2.0
		var rect := Rect2(-half, -half, SIZE, SIZE)
		if s.out == "rewind":
			# VHS split: cyan / magenta copies sliding apart
			var off := 6.0 * sin(clampf(s.ot / REWIND, 0.0, 1.0) * PI)
			for pair in [[Vector2(-off, 0), Color(0.3, 1.0, 1.0, 0.55 * a)], [Vector2(off, 0), Color(1.0, 0.3, 0.8, 0.55 * a)]]:
				ci.draw_set_transform(c + pair[0], rot, Vector2(sc, sc))
				ci.draw_texture_rect(tex, rect, false, pair[1])
		ci.draw_set_transform(c, rot, Vector2(sc, sc))
		var mod := Color(1, 1, 1, a * bl)
		if s.out == "poof":
			mod = Color(0.6, 0.6, 0.62, a)
		ci.draw_texture_rect(tex, rect, false, mod)
		ci.draw_set_transform(Vector2.ZERO)
		if s.id == "replay_ade" and s.out == "" and k >= 1.0:
			_drawPips(ci, P, c + Vector2(0.0, half + 7.0))

func _drawPips(ci: Control, P, at: Vector2) -> void:
	var gold := DAU.color("#FFD23A")
	var spent := DAU.color("#3A2A4A")
	if P.gold:
		var used := _goldUsed(P)
		ci.draw_circle(at + Vector2(0, 1.5), 5.0, Color(0, 0, 0, 0.45))
		ci.draw_circle(at, 5.0, DAU.color(INK))
		ci.draw_circle(at, 3.6, spent if used else gold)
		return
	var S = game.get("sponsors")
	var total := int(Config.T.perks.replayMax)
	var bought: int = int(S.replayBought) if S != null else 1
	var consumed := maxi(0, bought - 1)     # the bottle we carry is the last one bought
	for i in total:
		var p := at + Vector2((i - (total - 1) / 2.0) * 12.0, 0.0)
		ci.draw_circle(p + Vector2(0, 1.5), 5.0, Color(0, 0, 0, 0.45))
		ci.draw_circle(p, 5.0, DAU.color(INK))
		if i < consumed:
			ci.draw_circle(p, 3.6, spent)
		elif i == consumed:
			ci.draw_circle(p, 3.6, gold)
			ci.draw_circle(p + Vector2(-1.1, -1.2), 1.2, Color(1, 1, 1, 0.7))
		else:
			ci.draw_arc(p, 3.0, 0.0, TAU, 12, DAU.color(H.CREAM), 1.4, true)
