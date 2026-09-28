# BARON VON STATIC — the easter-egg boss (GDD §8.5, §13 step 6, §18.8 'boss_baron', T.boss). Port of src/actors/boss.js.
# Owner: boss + ending engineer (with scripts/game/ending.gd and the baked 'boss_baron' character). Constructs
# game.ending (the defeat sequence, credits and the Morning Show, scripts/game/ending.gd) and drives its lifecycle
# from here (game.gd does not know it).
#
# MODEL (~6 m, floating): the sculpted SDF body (the baked 'boss_baron' character, scripts/art/char_runtime.gd; ×2.5)
#   — tux with plum lapels, jabot, gold "13" medallion, the tall Dracula collar, long arms, huge white four-finger
#   gloves — plus: the walnut console-TV head (1.6 × 1.3 × 1.2 m; static parts = Blender runtime asset
#   blender/runtime/boss.py -> assets/runtime/boss/baron_head.glb: cabinet, bezel, knobs, grille, rabbit-ear antenna
#   horns with glowing tips; built here: the rubber-glass bulging screen showing cards 'baron' at 20 fps and the halo
#   sprites), the black cape (cloth sheet with a vertex wobble, plum lining; rebuilt every frame here) and the
#   noise-textured static tornado the body trails into (vertex sway in its shader). Damage shows on the model: the
#   screen cracks at 66 % (crack_overlay), the antennas spark at 33 %, the face goes frantic. No health bar.
# FIGHT (GDD §13 step 6, numbers from T.boss):
#   start(round)  THUNK (ee_switch_thunk), machine:boss_start {round} (screens -> snow, tower lights off one by one
#     (yard.gd), uplink disabled), 2.0 s of total silence (audio.stopAll + music 'silence'), round paused
#     (rounds reads boss.active), zombies dissolve into static (no points, requeued), DY slams shut behind a wall of
#     static (door reset + collider + nav), Telly flagged unavailable; static swirls down from the tower top and forms
#     the Baron (4 s intro, the player keeps control; sting_boss_intro, boss_form), then music 'boss:1'.
#   Phase 1 CHANNEL HOPPING (100–66 %): hovers 4 m up; every 7 s teleports on the 9 m ring around the tower (CRT
#     dot-out / dot-in 0.6 s each); volleys of 3 homing static balls every 3.5 s (12 m/s, 15°/s, 35 dmg); 3 Tuned-Ins
#     over the fence climbs every 12 s (<= 10 adds).
#   Phase 2 TEST PATTERN SWEEP (66–33 %): colour bars on his screen; every 9 s a 1.2 s telegraph (1 kHz rise, bars
#     glow, the 180° sector lights on the gravel) then a 7-colour beam band 0.0–0.6 m high sweeps 180° (radius 16 m)
#     in 2.5 s, through props: jump it (60 dmg); one Forecaster at a time, 6 Sock Hoppers every 15 s, balls every 7 s.
#   Phase 3 DEAD AIR (33–0 %): the moon dims to 30 % and static fog rolls in; he drifts at 2.2 m/s toward the player;
#     GRAB within 2.5 m (0.8 s arm wind-up, 80 dmg + 5 m throw); Tuned-Ins every 10 s (<= 8); OFF-AIR every 15 s for
#     4 s: layer TV_ONLY (invisible but a 10 % shimmer + a static crackle), fully visible on the Yard monitors (the
#     yard feed camera auto-tracks him); any hit reveals him 1.5 s.
#   A FULL REEL drops at the tower base at each phase transition (powerups.dropGuaranteed).
#   Defeat: adds dissolve, egg:step {step:6} + egg:complete (via the egg API when it is at step 5), then
#   game.ending.play() (goodnight face + wave, head collapse, CRT collapse, living room, credits, STAY TUNED?).
# DAMAGE: HP = T.boss.hpBase + hpPerRound · round. Zones: screen ×2, antenna tips ×3, body ×0.5 (cabinet, torso,
#   arms, gloves). Bullets/melee through weapons.registerShootable('boss_baron'); grenades call boss.damage directly
#   (already ×0.5); wonder weapons pass fixed amounts (Zapper 2000 / Boom Mic 700·charge / Chroma-Key 3000: no zone
#   multiplier). +10 points per damaging hit event, a hitmarker (weak spots = head style). CANCELLED / ONE TAKE never
#   touch him, PLEASE STAND BY freezes only his adds.
# WONDER ADAPTER: the wonder weapons (wonder.gd) look for the boss among the zombies (type 'boss_baron') and damage it
#   through zombies.damage / zombies.raycast. The JS wraps those two methods and wonder._zombies() on the instances
#   while the fight runs. GDScript cannot replace a method on an instance, so the wrappers live here as Callables in
#   `_adapted` (null when not installed): { damage(z, amount, info) -> Variant (null = z is not the boss proxy, else
#   the JS wrapper's result), raycast(o, d, max, h) -> hit (h = zombies' own hit or null; returns the wrapped result),
#   zombies(list) -> list } and installed into the hook fields of the other systems while the fight runs:
#   wonder._zombiesHook (wonder.gd), zombies._damageHook / zombies._raycastHook (zombies.gd: call them at the top of
#   damage() / at the end of raycast() when valid). The proxy (boss.proxy: type 'boss_baron', boss:true, pos, hp,
#   hitZones...) is routed to boss.damage.
# API (game.boss)
#   active (bool: intro .. end of the ending)  running (alias)  phase (0 | 1..3)  hp  maxHp  round  state
#   ('idle' | 'intro' | 'fight' | 'defeated')  pos (Vector3, waist)  offAir  proxy  root (Node3D)
#   start(round = rounds.round)  end({ keepEnding })  damage(amount, info) -> killed  raycast(origin, dir, max) ->
#   { dist, point, zone, mul, head:false } | null  inArena(x, z) (Instant Replay keeps samples inside)  warmup()
#   goodnight() / collapseHead(k 0..1) / cleanupAfterEnding()   (ending.gd beats)
#   debugStart({ round, teleport = true, skipIntro })  debugPhase(n)  debugKill()  debugHit(zone, amount)
#   debugOffAir(on)  debugSweep()  debugGrab()  debugState()
# EVENTS: machine:boss_start {round}, machine:boss_phase {phase}, machine:boss_offair {on}, egg:step {step:6},
#   egg:complete {} (when the egg does not emit them itself), boss:defeated {round}, boss:hit {...}.
# SOUNDS: ee_switch_thunk, ee_tower_off, sting_boss_intro, boss_form, boss_voice, boss_teleport, boss_static_ball,
#   boss_sweep_warn, boss_sweep, boss_grab, boss_offair, boss_hurt, baron_laugh, ee_baron_scream, crt_power_off.
#
# PORT NOTES
#   Renames (SPEC §3.2): `char` -> `char_` (GDScript built-in function). JS getters `running` / `fighting` are
#   read-only properties. Objects of other systems (zombies, handles, items) may be Dictionaries or Objects: they are
#   read through _gp() / called through _fc(). A THREE.Set of zombies is an Array compared by identity (is_same).
#   warmup() (shader precompile) is engine plumbing: kept as a harmless no-op returning null (SPEC §0.2).
#   setTimeout(…, 650) -> a real-time SceneTreeTimer guarded by a token (clearTimeout).
#   THREE.Sprite -> a camera-facing quad (spatial shader, _spriteMat); ShaderMaterials -> spatial shaders ported
#   line by line (NOISE / TORNADO / BALL / WALL / FOG / BLADE / FAN). Godot's front faces are clockwise: every
#   index buffer built here keeps three's front side by swapping the last two indices of each triangle.
extends RefCounted

const S := 2.5                                   # model units -> meters (boss_baron is sculpted at 1/2.5)
const HEAD_SCALE := 1.3                          # the GDD's 1.6 × 1.3 × 1.2 m TV, exaggerated ×1.3 (a cartoon big head)
const TOWER := Vector3(45, 0, -12)               # layout tower_base
const ARENA := {"x0": 35.2, "z0": -19.8, "x1": 50.8, "z1": -2.2}   # yard rect (layout AREAS yard), a little inset
const HOVER := {1: 4.0, 2: 3.4, 3: 2.45}         # waist height per phase (the gloves reach ~0.8 m below it)
const FENCE := ["f_yard_north", "f_yard_east_n", "f_yard_east_s", "g_yard_gate"]
const INTRO := {"silence": 2.0, "swirl": 2.0, "form": 4.6, "laugh": 5.4, "end": 6.0}
const HOP := {"out": 0.6, "in": 0.6}
const TRANSITION := 2.2
const DY := {"id": "dy_mc_yard", "rect": [34.8, -9.2, 35.2, -6.8], "h": 2.6}
const TAU := PI * 2.0
const FIXED_CAUSES := ["zapper", "boom_mic", "chroma_key", "wonder", "grenade", "explosion", "tele", "tiny_tele", "burn", "hot_mic", "signal", "gag"]
const HEAD_GLB := "res://assets/runtime/boss/baron_head.glb"
const FX_GLB := "res://assets/runtime/boss/baron_fx.glb"
const STANDIN_GLB := "res://assets/runtime/boss/baron_standin.glb"
const EndingScript := preload("res://scripts/game/ending.gd")

var B: Dictionary = Config.T.boss
var ZONE_MUL: Dictionary = {}

static func smooth(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)

static func easeOutBack(x: float, s: float = 1.8) -> float:
	x = clampf(x, 0.0, 1.0)
	return 1.0 + (s + 1.0) * pow(x - 1.0, 3.0) + s * pow(x - 1.0, 2.0)

static func easeInOut(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 4.0 * x * x * x if x < 0.5 else 1.0 - pow(-2.0 * x + 2.0, 3.0) / 2.0

static func angDiff(a: float, b: float) -> float:
	return atan2(sin(a - b), cos(a - b))

static func yawTo(dx: float, dz: float) -> float:
	return atan2(-dx, -dz)

# ------------------------------------------------------------------------------------------------ geometry tests
# Ray (o, d normalized) vs capsule a..b radius r -> distance or INF.
static func rayCapsule(o: Vector3, d: Vector3, a: Vector3, b: Vector3, r: float) -> float:
	var ba := b - a
	var oa := o - a
	var baba := ba.dot(ba)
	var bard := ba.dot(d)
	var baoa := ba.dot(oa)
	var rdoa := d.dot(oa)
	var oaoa := oa.dot(oa)
	var qa := baba - bard * bard
	var qb := baba * rdoa - baoa * bard
	var qc := baba * oaoa - baoa * baoa - r * r * baba
	if qa > 1e-9:
		var h := qb * qb - qa * qc
		if h < 0.0:
			return INF
		var t := (-qb - sqrt(h)) / qa
		var y := baoa + t * bard
		if y > 0.0 and y < baba:
			return t if t >= 0.0 else INF
		return raySphereT(o, d, a if y <= 0.0 else b, r)
	return raySphereT(o, d, a, r)

static func raySphereT(o: Vector3, d: Vector3, c: Vector3, r: float) -> float:
	var ox := o.x - c.x
	var oy := o.y - c.y
	var oz := o.z - c.z
	var b := ox * d.x + oy * d.y + oz * d.z
	var q := ox * ox + oy * oy + oz * oz - r * r
	var disc := b * b - q
	if disc < 0.0:
		return INF
	var t := -b - sqrt(disc)
	return t if t >= 0.0 else (0.0 if q < 0.0 else INF)

# THREE.Ray.intersectBox: entry point (or the exit point when the origin is inside), null when missed.
static func rayBox(o: Vector3, d: Vector3, bmin: Vector3, bmax: Vector3):
	var tmin := -INF
	var tmax := INF
	for ax in 3:
		var inv := 1.0 / d[ax] if d[ax] != 0.0 else INF
		var t0: float
		var t1: float
		if inv >= 0.0:
			t0 = (bmin[ax] - o[ax]) * inv
			t1 = (bmax[ax] - o[ax]) * inv
		else:
			t0 = (bmax[ax] - o[ax]) * inv
			t1 = (bmin[ax] - o[ax]) * inv
		if is_nan(t0):
			t0 = -INF
		if is_nan(t1):
			t1 = INF
		if tmin > t1 or t0 > tmax:
			return null
		if t0 > tmin or is_nan(tmin):
			tmin = t0
		if t1 < tmax or is_nan(tmax):
			tmax = t1
	if tmax < 0.0:
		return null
	return o + d * (tmin if tmin >= 0.0 else tmax)

# ------------------------------------------------------------------------------------------------ shaders
const NOISE_GLSL := """
float bh(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(bh(i), bh(i + vec2(1.0, 0.0)), f.x), mix(bh(i + vec2(0.0, 1.0)), bh(i + vec2(1.0, 1.0)), f.x), f.y);
}
"""

# Static tornado: spiral-scrolling noise bands + TV snow flecks, soft top/tip fade, fresnel edges; the tip sways.
const TORNADO_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;
uniform float uTime; uniform float uSway; uniform float uReach;
uniform float uAlpha; uniform float uGain; uniform float uSpin;
uniform vec3 uA : source_color; uniform vec3 uB : source_color;
varying float vFres;
%NOISE%
void vertex() {
	vec3 p = VERTEX;
	float v = UV.y;
	p.y *= mix(1.0, uReach, v);
	p.x += sin(uTime * 1.3 + v * 3.1) * uSway * v * v;
	p.z += cos(uTime * 1.07 + v * 2.6) * uSway * v * v;
	VERTEX = p;
	vec4 mv = MODELVIEW_MATRIX * vec4(p, 1.0);
	vec3 n = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vFres = 1.0 - abs(dot(n, normalize(-mv.xyz)));
}
void fragment() {
	float v = UV.y;
	vec2 sp = vec2(UV.x * 5.0 + v * 2.4 - uTime * uSpin, v * 5.0 - uTime * 1.7);
	float bands = vn(sp) * 0.62 + vn(sp * 2.3 + 7.1) * 0.38;
	float frame = floor(uTime * 24.0);
	float sn = bh(floor(UV * vec2(160.0, 110.0)) + frame * vec2(13.1, 7.7));
	vec3 col = mix(uA, uB, smoothstep(0.32, 0.78, bands));
	col += vec3(0.9, 0.88, 1.0) * step(0.94, sn) * 0.7;
	float a = uAlpha * (0.18 + 0.62 * smoothstep(0.28, 0.82, bands) + 0.3 * step(0.95, sn));
	a *= smoothstep(1.0, 0.7, v) * smoothstep(0.0, 0.08, v);
	a *= 0.5 + 0.6 * vFres;
	ALBEDO = col * uGain;
	ALPHA = clamp(a, 0.0, 1.0);
}
"""

# Static ball / generic static blob: bright snow core, violet rim.
const BALL_SHADER := """
shader_type spatial;
render_mode unshaded, fog_disabled, shadows_disabled;
uniform float uTime; uniform vec3 uCol : source_color;
varying vec3 vN; varying vec3 vV; varying vec3 vP;
%NOISE%
void vertex() {
	vP = VERTEX;
	vec4 mv = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vN = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vV = normalize(-mv.xyz);
}
void fragment() {
	float f = 1.0 - abs(dot(vN, vV));
	float frame = floor(uTime * 24.0);
	float sn = bh(floor((vP.xy + vP.z * 0.7) * 26.0) + frame * vec2(3.7, 9.1));
	vec3 col = mix(vec3(0.9, 0.9, 1.0) * (0.55 + 0.9 * sn), uCol * 2.2, smoothstep(0.25, 0.95, f));
	ALBEDO = col;
}
"""

# Wall of static (DY): scrolling snow with scanlines, alpha edges; unrolls from the top (uReveal on 1 - v).
const WALL_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;
uniform float uTime; uniform float uAlpha; uniform float uReveal;
%NOISE%
void fragment() {
	vec2 vUv = UV;
	if (1.0 - vUv.y > uReveal) discard;
	float frame = floor(uTime * 24.0);
	float sn = bh(floor(vUv * vec2(90.0, 110.0)) + frame * vec2(11.3, 5.9));
	float band = 0.75 + 0.25 * sin(vUv.y * 140.0 + uTime * 30.0);
	float roll = smoothstep(0.0, 0.08, abs(fract(vUv.y * 0.6 - uTime * 0.35) - 0.5));
	vec3 col = vec3(sn * sn * 1.3 + 0.08) * band * vec3(0.86, 0.84, 1.08) * (0.8 + 0.2 * roll);
	float edge = smoothstep(0.0, 0.06, vUv.x) * smoothstep(1.0, 0.94, vUv.x) * smoothstep(0.0, 0.03, vUv.y);
	float lip = smoothstep(uReveal - 0.04, uReveal, 1.0 - vUv.y) * 1.6;
	ALBEDO = col + lip;
	ALPHA = uAlpha * edge;
}
"""

const FOG_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, fog_disabled, shadows_disabled;
uniform float uTime; uniform float uAlpha;
%NOISE%
void fragment() {
	vec2 vUv = UV;
	vec2 p = vUv * 9.0;
	float n = vn(p + vec2(uTime * 0.13, uTime * 0.07)) * 0.6 + vn(p * 2.1 - vec2(uTime * 0.21, -uTime * 0.05)) * 0.4;
	float frame = floor(uTime * 20.0);
	float sn = bh(floor(vUv * 420.0) + frame * vec2(7.1, 3.3));
	float r = length(vUv - 0.5) * 2.0;
	float a = uAlpha * smoothstep(0.3, 0.85, n) * smoothstep(1.0, 0.55, r) * (0.88 + 0.24 * sn);
	ALBEDO = vec3(0.5, 0.46, 0.68) * (0.8 + 0.3 * sn);
	ALPHA = a;
}
"""

# Sweep blade: 7 colour-bar bands along its length, hot core line, soft top edge.
const BLADE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;
uniform float uTime; uniform float uAlpha; uniform vec3 uBars[7];
void fragment() {
	vec2 vUv = UV;
	int idx = int(clamp(floor(vUv.x * 7.0), 0.0, 6.0));
	vec3 c = uBars[idx];
	float top = smoothstep(1.0, 0.72, vUv.y);
	float core = exp(-abs(vUv.y - 0.45) * 9.0) * 0.9;
	float scan = 0.85 + 0.15 * sin(vUv.y * 60.0 - uTime * 40.0);
	ALBEDO = c * (1.4 + core * 2.2) * scan;
	ALPHA = uAlpha * top;
}
"""

# Floor sector (telegraph + afterimage fan): concentric colour-bar rings, fading with angle from the blade.
const FAN_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;
uniform float uTime; uniform float uAlpha; uniform float uSweep; uniform float uPulse; uniform vec3 uBars[7];
void fragment() {
	vec2 vUv = UV;
	float r = vUv.y;
	int idx = int(clamp(floor(r * 7.0), 0.0, 6.0));
	vec3 c = uBars[idx];
	float a = vUv.x;
	float trail = uSweep < 0.0 ? 1.0 : smoothstep(uSweep - 0.35, uSweep, a) * step(a, uSweep);
	float ring = 0.65 + 0.35 * smoothstep(0.4, 0.5, abs(fract(r * 7.0) - 0.5));
	float edge = smoothstep(0.0, 0.015, a) * smoothstep(1.0, 0.985, a);
	ALBEDO = c * (0.9 + uPulse);
	ALPHA = uAlpha * trail * ring * edge * smoothstep(0.02, 0.06, r);
}
"""

# THREE.Sprite / SpriteMaterial (and plain unlit textured planes): map × colour (linear, may exceed 1) × opacity.
# Sprites face the camera (scaled by the node's world scale, rotated by `rotation`).
const SPRITE_SHADER := """
shader_type spatial;
render_mode unshaded, %BLEND%, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;
uniform sampler2D map : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 color = vec3(1.0);
uniform float opacity = 1.0;
uniform float rotation = 0.0;
void vertex() {
%BILLBOARD%
}
void fragment() {
	vec4 t = texture(map, UV);
	ALBEDO = t.rgb * color;
	ALPHA = t.a * opacity;
}
"""
const BILLBOARD_VERT := """
	vec2 sc = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz));
	vec2 c = VERTEX.xy * sc;
	float s = sin(rotation);
	float co = cos(rotation);
	c = vec2(co * c.x - s * c.y, s * c.x + co * c.y);
	vec4 mv = VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0);
	mv.xy += c;
	POSITION = PROJECTION_MATRIX * mv;
"""

static var _shaderCache := {}
static var _glowTex: Texture2D = null
static var _lineTex: Texture2D = null

static func shaderOf(code: String) -> Shader:
	if _shaderCache.has(code):
		return _shaderCache[code]
	var sh := Shader.new()
	sh.code = code.replace("%NOISE%", NOISE_GLSL)
	_shaderCache[code] = sh
	return sh

static func shaderMat(code: String, params: Dictionary = {}, priority: int = 0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shaderOf(code)
	for k in params:
		m.set_shader_parameter(k, params[k])
	m.render_priority = clampi(priority, -128, 127)
	return m

# THREE colour hex (sRGB) times a factor, as the LINEAR rgb three stores (new THREE.Color(hex).multiplyScalar(k)).
static func linColor(hex: String, k: float = 1.0) -> Vector3:
	var c := Color(hex)
	return Vector3(DAU.srgbToLinear(c.r), DAU.srgbToLinear(c.g), DAU.srgbToLinear(c.b)) * k

# Sprite-like material: additive (default) or normal blending; billboard for THREE.Sprite, flat for plain meshes.
static func spriteMat(tex: Texture2D, col: Vector3, additive: bool = true, billboard: bool = true, priority: int = 0) -> ShaderMaterial:
	var code := SPRITE_SHADER.replace("%BLEND%", "blend_add" if additive else "blend_mix").replace("%BILLBOARD%", BILLBOARD_VERT if billboard else "")
	return shaderMat(code, {"map": tex, "color": col, "opacity": 1.0, "rotation": 0.0}, priority)

# 128² radial white glow: stops 0 (a 1), 0.25 (a 0.55), 1 (a 0).
static func glowTexture() -> Texture2D:
	if _glowTex:
		return _glowTex
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	for y in 128:
		for x in 128:
			var d := Vector2(x + 0.5 - 64.0, y + 0.5 - 64.0).length() / 64.0
			var a := 0.0
			if d <= 0.25:
				a = lerpf(1.0, 0.55, d / 0.25)
			elif d <= 1.0:
				a = lerpf(0.55, 0.0, (d - 0.25) / 0.75)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	img.generate_mipmaps()
	_glowTex = ImageTexture.create_from_image(img)
	return _glowTex

# A CRT power-off line: hot white core, soft top/bottom falloff, tapered ends (256 × 64; the vertical gradient,
# then 'destination-in' with the horizontal alpha ramp).
static func lineTexture() -> Texture2D:
	if _lineTex:
		return _lineTex
	var img := Image.create(256, 64, false, Image.FORMAT_RGBA8)
	var vs := [[0.0, Color8(255, 255, 255, 0)], [0.42, Color(235 / 255.0, 240 / 255.0, 1.0, 0.55)], [0.5, Color(1, 1, 1, 1)],
		[0.58, Color(235 / 255.0, 240 / 255.0, 1.0, 0.55)], [1.0, Color(1, 1, 1, 0)]]
	var hs := [[0.0, 0.0], [0.12, 1.0], [0.88, 1.0], [1.0, 0.0]]
	for y in 64:
		var gv: Color = _stops((y + 0.5) / 64.0, vs)
		for x in 256:
			var u := (x + 0.5) / 256.0
			var ha := 0.0
			for i in range(1, hs.size()):
				if u <= hs[i][0]:
					ha = lerpf(hs[i - 1][1], hs[i][1], (u - hs[i - 1][0]) / (hs[i][0] - hs[i - 1][0]))
					break
			img.set_pixel(x, y, Color(gv.r, gv.g, gv.b, gv.a * ha))
	img.generate_mipmaps()
	_lineTex = ImageTexture.create_from_image(img)
	return _lineTex

static func _stops(u: float, st: Array) -> Color:
	if u <= st[0][0]:
		return st[0][1]
	for i in range(1, st.size()):
		if u <= st[i][0]:
			var k: float = (u - st[i - 1][0]) / (st[i][0] - st[i - 1][0])
			return (st[i - 1][1] as Color).lerp(st[i][1], k)
	return st[st.size() - 1][1]

static func barColors() -> PackedVector3Array:
	var out := PackedVector3Array()
	for h in Config.BARS:
		out.append(linColor(h))
	return out

# ------------------------------------------------------------------------------------------------ meshes built here
# three PlaneGeometry(w, h, gx, gy) (XY plane facing +Z, v = 1 at the top), optionally translated.
static func planeMesh(w: float, h: float, gx: int = 1, gy: int = 1, off: Vector3 = Vector3.ZERO) -> ArrayMesh:
	var pos := PackedVector3Array()
	var uv := PackedVector2Array()
	var nrm := PackedVector3Array()
	for iy in gy + 1:
		var y := iy * h / gy - h / 2.0
		for ix in gx + 1:
			var x := ix * w / gx - w / 2.0
			pos.append(Vector3(x, -y, 0) + off)
			nrm.append(Vector3(0, 0, 1))
			uv.append(Vector2(float(ix) / gx, 1.0 - float(iy) / gy))
	var idx := PackedInt32Array()
	for iy in gy:
		for ix in gx:
			var a := ix + (gx + 1) * iy
			var b := ix + (gx + 1) * (iy + 1)
			var c := (ix + 1) + (gx + 1) * (iy + 1)
			var d := (ix + 1) + (gx + 1) * iy
			idx.append_array([a, b, d, b, c, d])
	return meshFrom(pos, uv, idx, nrm)

# Indexed triangle mesh from three-convention data (CCW front faces): indices are re-wound for Godot. Normals are
# computed like BufferGeometry.computeVertexNormals when not given.
static func meshFrom(pos: PackedVector3Array, uv: PackedVector2Array, idx: PackedInt32Array, nrm: PackedVector3Array = PackedVector3Array(), mesh: ArrayMesh = null) -> ArrayMesh:
	if nrm.is_empty():
		nrm = computeNormals(pos, idx)
	var gi := PackedInt32Array()
	gi.resize(idx.size())
	for i in range(0, idx.size(), 3):
		gi[i] = idx[i]
		gi[i + 1] = idx[i + 2]
		gi[i + 2] = idx[i + 1]
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pos
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_INDEX] = gi
	if mesh == null:
		mesh = ArrayMesh.new()
	else:
		mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh

static func computeNormals(pos: PackedVector3Array, idx: PackedInt32Array) -> PackedVector3Array:
	var n := PackedVector3Array()
	n.resize(pos.size())
	for i in range(0, idx.size(), 3):
		var a := idx[i]
		var b := idx[i + 1]
		var c := idx[i + 2]
		var cb := (pos[c] - pos[b]).cross(pos[a] - pos[b])
		n[a] += cb
		n[b] += cb
		n[c] += cb
	for i in n.size():
		n[i] = n[i].normalized()
	return n

static func meshNode(mesh: Mesh, mat: Material, name: String = "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.rotation_order = EULER_ORDER_XYZ
	if name != "":
		mi.name = name
	return mi

# A THREE.Sprite: unit quad + sprite material.
static func sprite(mat: ShaderMaterial, name: String = "") -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var mi := meshNode(q, mat, name)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8))
	return mi

# ================================================================================================ the Boss
var game
var active := false
var phase := 0
var hp := 0.0
var maxHp := 0.0
var round := 0
var state := "idle"
var pos := Vector3(TOWER.x, HOVER[1], TOWER.z - 9)
var yaw := 0.0
var offAir := false
var root: Node3D = null
var built := false
var debug := false
var proxy: Dictionary
var ending = null
var char_ = null                 # JS `char` (renamed: GDScript built-in)
var J: Dictionary = {}
var head: Dictionary = {}
var cape: Dictionary = {}
var tornado: Dictionary = {}
var dot: MeshInstance3D = null
var line: MeshInstance3D = null
var fxRoot: Node3D = null

var running: bool:
	get:
		return active
var fighting: bool:
	get:
		return active and (state == "intro" or state == "fight")

var _t := 0.0
var _rt := 0.0
var _adds: Array = []
var _balls: Array = []
var _saved = null
var _adapted = null
var _restPose := {}
var _introT := 0.0
var _introFlags := {}
var _phaseT := 0.0
var _transT := 0.0
var _nextPhase := 0
var _hurtT := 0.0
var _voiceT := 0.0
var _revealT := 0.0
var _grab = null
var _hop = null
var _sweep = null
var _gesture = null
var _offAirT := 0.0
var _offAirTimer := 0.0
var _offAirLoop = null
var _cracked := false
var _sparking := false
var _pointsFrame := -1
var _hmFrame := -1
var _fxFrame := -1
var _ptKey := ""
var _drops := {}
var _ringA := 0.0
var _hoverY := 0.0
var _hopT := 0.0
var _ballT := 0.0
var _addsT := 0.0
var _socksT := 0.0
var _fcT := 0.0
var _sweepT := 0.0
var _grabCd := 0.0
var _hidden := false
var _layer := 0
var _vel = null                  # Vector3 | null
var _shake := 0.0
var _staticT := 0.0
var _whiteout := 0.0
var _switchAnim = null
var _fenceI := 0
var _env = null
var _feedSaved = null
var _dy = null
var _wall: MeshInstance3D = null
var _wallT := 0.0
var _shootable := false
var _shimmer: Array = []
var _shimmerMat: StandardMaterial3D = null
var _ballMesh: Mesh = null
var _ballMat: ShaderMaterial = null
var _ballHalo: ShaderMaterial = null
var _blade = null
var _bladeMat: ShaderMaterial = null
var _fanMat: ShaderMaterial = null
var _errT := -1e9
var _faceTok := 0
var _warned := {}

func _init(g) -> void:
	game = g
	ZONE_MUL = {"screen": B.screenMul, "antenna": B.antennaMul, "body": B.bodyMul}
	proxy = _makeProxy()
	ending = EndingScript.new(g, self)
	g.ending = ending

# ------------------------------------------------------------------------------------------ foreign-object glue
# Property of a Dictionary or an Object (null when missing).
static func _gp(o, k: String, def = null):
	if o == null:
		return def
	if o is Dictionary:
		return o.get(k, def)
	if o is Object:
		if not is_instance_valid(o):
			return def
		var v = o.get(k)
		return def if v == null else v
	return def

static func _path(o, keys: Array):
	for k in keys:
		o = _gp(o, k)
		if o == null:
			return null
	return o

# o.k = v on a Dictionary or an Object.
static func _sp(o, k: String, v) -> void:
	if o is Dictionary:
		o[k] = v
	elif o is Object and is_instance_valid(o):
		o.set(k, v)

# Calls o.m(args...) when o is an Object with that method, or a Dictionary / Object holding a Callable under m.
static func _fc(o, m: String, args: Array = []):
	if o == null:
		return null
	if o is Object:
		if not is_instance_valid(o):
			return null
		if o.has_method(m):
			return o.callv(m, args)
		var v = o.get(m)
		if v is Callable and v.is_valid():
			return v.callv(args)
		return null
	if o is Dictionary:
		var f = o.get(m)
		if f is Callable and f.is_valid():
			return f.callv(args)
	return null

static func _hasFn(o, m: String) -> bool:
	if o == null:
		return false
	if o is Object:
		return is_instance_valid(o) and (o.has_method(m) or o.get(m) is Callable)
	if o is Dictionary:
		return o.get(m) is Callable
	return false

func _play(id: String, opts: Dictionary = {}):
	if game.audio != null:
		return _fc(game.audio, "play", [id, opts])
	return null

func _music(id: String) -> void:
	if game.audio != null:
		_fc(game.audio, "music", [id])

func _burst(p: Vector3, opts: Dictionary) -> void:
	if game.fx != null:
		_fc(game.fx, "burst", [p, opts])

func _flash(p: Vector3, color: String, intensity: float, dur: float) -> void:
	if game.fx != null:
		_fc(game.fx, "flashLight", [p, color, intensity, dur])

func _camShake(a: float, d: float) -> void:
	if game.cam != null:
		_fc(game.cam, "shake", [a, d])

func _post():
	return _gp(game.render, "post") if game.render != null else null

# ------------------------------------------------------------------------------------------ lifecycle
func init() -> void:
	var ev = game.events
	var drop := func(p) -> void:
		if p is Dictionary and p.get("z") != null:
			_addsDelete(p.z)
	var over := func(_p) -> void:
		if active:
			end({"quiet": true})
	ev.on("zombie:kill", drop)
	ev.on("zombie:despawn", drop)
	ev.on("game:over", over)
	if ending != null and ending.has_method("init"):
		ending.init()

func reset() -> void:
	if active or state != "idle":
		end({"quiet": true})
	if ending != null and ending.has_method("reset"):
		ending.reset()
	phase = 0
	hp = 0.0
	maxHp = 0.0
	state = "idle"

# Precompile hook (engine plumbing: Godot compiles on first use). Kept for API parity.
func warmup():
	return null

# ------------------------------------------------------------------------------------------ start / end
func start(round_ = null) -> bool:
	var g = game
	if active:
		return false
	if not ((round_ is int or round_ is float) and is_finite(float(round_))):
		var rr = _gp(g.rounds, "round", 0)
		round_ = rr if rr else 1
	_ensureBuilt()
	if g.scene == null:
		push_warning("[boss] no game.scene (render missing): fight not started")
		return false
	round = maxi(1, int(round_))
	maxHp = float(B.hpBase + B.hpPerRound * round)
	hp = maxHp
	active = true
	state = "intro"
	phase = 0
	_t = 0.0
	_introT = 0.0
	_introFlags = {}
	_phaseT = 0.0
	_transT = 0.0
	_hurtT = 0.0
	_voiceT = 0.0
	_revealT = 0.0
	_grab = null
	_hop = null
	_sweep = null
	_offAirT = 0.0
	_offAirTimer = float(B.p3.offAirEvery)
	offAir = false
	_cracked = false
	_sparking = false
	_pointsFrame = -1
	_hmFrame = -1
	_drops = {}
	_saved = {"round": _gp(g.rounds, "round")}
	# position: the ring point with the best view from the player (7–11 m away, not behind the tower)
	var p: Vector3 = _playerPos() if g.player != null else TOWER
	var a0 := _pickRingAngle(p, null)
	_ringA = a0
	pos = _ringPoint(a0, HOVER[1])
	_hoverY = HOVER[1]
	yaw = yawTo(p.x - pos.x, p.z - pos.z)
	root.position = pos
	root.rotation = Vector3(0, yaw, 0)
	root.scale = Vector3.ONE
	root.visible = false
	if root.get_parent() != g.scene:
		DAU.detach(root)
		g.scene.add_child(root)
	if fxRoot.get_parent() != g.scene:
		DAU.detach(fxRoot)
		g.scene.add_child(fxRoot)
	_setLayers(Config.LAYERS.WORLD)
	_setFace("laugh")
	head.crack.visible = false
	head.group.visible = true
	head.group.scale = Vector3.ONE
	for k in ["_flash", "_dot"]:
		var o = head.get(k)
		if o != null:
			o.visible = false
			DAU.detach(o)
	tornado.group.scale = Vector3.ONE * 0.001
	for i in tornado.mats.size():
		var m: ShaderMaterial = tornado.mats[i]
		m.set_shader_parameter("uAlpha", tornado.alpha[i])
		m.set_shader_parameter("uReach", 1.0)
		tornado.reach[i] = 1.0
	head.antennaSpark = 0

	# t = 0: THUNK, tower lights off (yard.gd on machine:boss_start), TVs to snow (screens.gd), dead air
	if g.audio != null:
		_fc(g.audio, "stopAll")
	_music("silence")
	_play("ee_switch_thunk", {"pos": _switchPos()})
	_play("ee_tower_off", {"pos": Vector3(TOWER.x, 12, TOWER.z), "delay": 0.2})
	var eggStep = _gp(g.egg, "step", 0)
	if not (eggStep != null and float(eggStep) >= 5):
		_throwSwitch()   # the egg throws the knife switch itself at step 5
	g.events.emit("machine:boss_start", {"round": round})
	# round paused (rounds reads boss.active) + every living zombie dissolves (no points; requeued for later)
	if g.zombies != null:
		_fc(g.zombies, "despawnAll", [{"fx": true, "requeue": true}])
	_adds.clear()
	_closeDY()
	if g.telly != null:
		_sp(g.telly, "disabled", true)
	_installAdapters()
	_registerShootable()
	_trackFeed(true)
	_camShake(0.25, 0.4)
	return true

# Stops everything and restores the world. keepEnding: the ending sequence keeps running (it calls
# cleanupAfterEnding() when it is done).
func end(o: Dictionary = {}) -> void:
	var quiet: bool = o.get("quiet", false)
	var keepEnding: bool = o.get("keepEnding", false)
	var g = game
	_clearBalls()
	_stopSweep()
	if _offAirLoop != null:
		_fc(_offAirLoop, "stop", [0.2])
		_offAirLoop = null
	_despawnAdds(not quiet)
	_uninstallAdapters()
	_unregisterShootable()
	_trackFeed(false)
	_restoreEnv()
	_openDY(quiet)
	if g.telly != null:
		_sp(g.telly, "disabled", false)
	if root != null:
		root.visible = false
		DAU.detach(root)
	if fxRoot != null:
		DAU.detach(fxRoot)
	offAir = false
	if not keepEnding:
		active = false
		state = "idle"
		phase = 0
		if not quiet and ending != null:
			ending.stop()

# ------------------------------------------------------------------------------------------ update
func update(dt: float) -> void:
	var g = game
	var rdt: float = g.time.realDt if g.time.has("realDt") else dt
	if ending != null and (ending.active or ending.playing):
		ending.update(rdt)
	if not active or not built:
		return
	if state == "defeated":
		if root.get_parent() != null:
			_animateModel(rdt, true)
		return
	if not (dt > 0.0):
		_animateModel(0.0, false)
		return
	_t += dt
	if state == "intro":
		_updateIntro(dt)
	elif state == "fight":
		_updateFight(dt)
	_updateBalls(dt)
	_updateSweep(dt)
	_updateAddsTick(dt)
	_animateModel(dt, false)
	_syncProxy()
	_updateFeedTarget(dt)
	_updateEnv(dt)
	_updateWall(dt)

# The wall of static in the DY doorway unrolls from the top in 0.3 s, then keeps crawling.
func _updateWall(dt: float) -> void:
	var w := _wall
	if w == null or w.get_parent() == null:
		return
	_wallT += dt
	var m: ShaderMaterial = w.material_override
	m.set_shader_parameter("uTime", _t)
	m.set_shader_parameter("uReveal", minf(1.0, _wallT / 0.3))

func _err(tag: String, msg: String) -> void:
	var now := DAU.nowMs()
	if now - _errT > 5000.0:
		_errT = now
		push_error("[boss:%s] %s" % [tag, msg])

# ------------------------------------------------------------------------------------------ intro
func _updateIntro(dt: float) -> void:
	var g = game
	var F := _introFlags
	_introT += dt
	var t := _introT
	var top := Vector3(TOWER.x, 30, TOWER.z)
	var v2 := pos
	if t >= INTRO.swirl and not F.has("swirl"):
		F.swirl = true
		_play("sting_boss_intro")
		_play("boss_form", {"pos": top, "vol": 1.2})
	# static swirls above the tower, then spirals down to where he forms
	if t >= INTRO.swirl and t < INTRO.form + 0.3:
		var u := clampf((t - INTRO.swirl) / (INTRO.form - INTRO.swirl), 0.0, 1.0)
		var e := easeInOut(u)
		for i in 5:
			var a := t * 7.5 + i * (TAU / 5.0)
			var r := lerpf(3.8, 1.3, e) * (0.8 + 0.3 * randf())
			var cx := lerpf(TOWER.x, pos.x, e)
			var cz := lerpf(TOWER.z, pos.z, e)
			var cy := lerpf(31.0, pos.y + 1.5, e)
			v2 = Vector3(cx + cos(a) * r, cy + (randf() - 0.5) * 2.4, cz + sin(a) * r)
			_burst(v2, {"shape": "static", "count": 3, "speed": 1.4, "size": 0.3, "life": 0.7})
		if randf() < dt * 6.0:
			_burst(v2, {"shape": "spark", "count": 3, "speed": 5, "size": 0.05, "colors": ["#C9A0FF", "#FFFFFF"], "life": 0.3})
	# the tornado grows first, then the body warms up out of a CRT dot
	if t >= INTRO.form - 1.0:
		var k := smooth((t - (INTRO.form - 1.0)) / 1.0)
		tornado.group.scale = Vector3.ONE * maxf(0.001, k)
	if t >= INTRO.form and not F.has("form"):
		F.form = true
		root.visible = true
		v2 = Vector3(pos.x, pos.y + 1.5, pos.z)
		_flash(v2, "#D9B8FF", 14, 0.5)
		_burst(v2, {"shape": "static", "count": 40, "speed": 6, "size": 0.3, "life": 0.8})
		_burst(v2, {"shape": "confetti", "count": 24, "colors": Config.BARS, "speed": 6, "size": 0.14})
		_camShake(0.45, 0.5)
		if _post() != null:
			_whiteout = 0.22
	if t >= INTRO.form:
		var k := clampf((t - INTRO.form) / 0.6, 0.0, 1.0)
		_dotScale(k)
	if t >= INTRO.laugh and not F.has("laugh"):
		F.laugh = true
		_voice("baron_laugh", 1.2)
		_play("boss_voice", {"pos": pos, "syllables": 5})
	if t >= INTRO.end:
		_dotScale(1.0)
		_beginPhase(1)

# ------------------------------------------------------------------------------------------ fight
func _beginPhase(n: int) -> void:
	var g = game
	var prev := phase
	phase = n
	state = "fight"
	_phaseT = 0.0
	_hopT = float(B.p1.hopEvery)
	_ballT = 1.6 if n == 1 else B.p2.sweepEvery * 0.5
	_addsT = 3.0 if n == 1 else (4.0 if n == 2 else 3.0)
	_socksT = 6.0
	_fcT = 2.0
	_sweepT = 2.0 if n == 2 else INF
	_grabCd = 1.5
	_offAirTimer = B.p3.offAirEvery * 0.6
	_music("boss:%d" % n)
	if n == 2:
		_setFace("bars")
	elif n == 3:
		_setFace("frantic")
	else:
		_setFace("laugh")
	if n == 3:
		_enterDeadAir()
	g.events.emit("machine:boss_phase", {"phase": n})
	if prev > 0:
		_dropReel()

func _updateFight(dt: float) -> void:
	var g = game
	_phaseT += dt
	if _transT > 0.0:
		# phase-change recoil: screen static, scream, no attacks; the FULL REEL already dropped
		_transT -= dt
		if _transT <= 0.0:
			_beginPhase(_nextPhase)
		return
	var n := phase
	var p = g.player
	if n == 1 or n == 2:
		# channel hopping (phase 2: only between sweeps)
		if _hop == null:
			_hopT -= dt
			var sweeping: bool = _sweep != null and _sweep.phase != "done"
			if _hopT <= 0.0 and not sweeping:
				_startHop()
		if _hop != null:
			_updateHop(dt)
		# static balls
		_ballT -= dt
		var every: float = B.p1.ballEvery if n == 1 else B.p1.ballEvery * 2.0
		if _ballT <= 0.0 and _hop == null and not (_sweep != null and _sweep.phase == "sweep"):
			_ballT = every
			_volley()
		if n == 2:
			_sweepT -= dt
			if _sweepT <= 0.0 and _hop == null and _sweep == null:
				_sweepT = float(B.p2.sweepEvery)
				_startSweep()
	elif n == 3:
		_updateDrift(dt)
		_updateGrab(dt)
		_updateOffAir(dt)
	# adds
	_updateAdds(dt, n)
	# face the player (smoothly)
	if p != null and _hop == null:
		var pp := _playerPos()
		var want := yawTo(pp.x - pos.x, pp.z - pos.z)
		yaw += angDiff(want, yaw) * (1.0 - exp(-dt * 3.2))
	# hover height eases to the phase height
	var hy: float = HOVER.get(n, HOVER[1])
	_hoverY += (hy - _hoverY) * (1.0 - exp(-dt * 1.2))
	pos.y = _hoverY + sin(_t * 1.3) * 0.18

# HP thresholds: a single hit never skips a phase (HP is clamped at the threshold until the transition).
func _checkPhase() -> void:
	if state != "fight" or _transT > 0.0:
		return
	var f := hp / maxHp
	var next := 0
	if phase == 1 and f <= 2.0 / 3.0:
		next = 2
	elif phase == 2 and f <= 1.0 / 3.0:
		next = 3
	if next == 0:
		return
	_nextPhase = next
	_transT = TRANSITION
	_hop = null
	_stopSweep()
	_restoreScale()
	if next == 2:
		head.crack.visible = true
		_cracked = true
	if next == 3:
		_sparking = true
	_setFace("frantic")
	_voice("ee_baron_scream", 1.0)
	_play("boss_hurt", {"pos": pos, "vol": 1.3})
	var v := _screenWorld()
	_burst(v, {"shape": "static", "count": 36, "speed": 7, "size": 0.28, "life": 0.9})
	_burst(v, {"shape": "spark", "count": 30, "speed": 9, "size": 0.06, "colors": ["#FFFFFF", "#C9A0FF", "#FFE27A"]})
	_flash(v, "#E0C8FF", 12, 0.4)
	_camShake(0.4, 0.5)
	head.wobble = 1.0
	_dropReel()

func _dropReel() -> void:
	var g = game
	if _drops.has(phase):
		return
	_drops[phase] = true
	var p: Vector3 = _playerPos() if g.player != null else TOWER
	var v := Vector3(p.x - TOWER.x, 0, p.z - TOWER.z)
	if v.length_squared() < 1e-4:
		v = Vector3(0, 0, 1)
	v = v.normalized() * 3.0 + TOWER
	v.y = 0
	var pu = g.powerups
	if pu == null:
		return
	if _hasFn(pu, "dropGuaranteed"):
		_fc(pu, "dropGuaranteed", ["full_reel", v])
	else:
		_fc(pu, "drop", ["full_reel", v])

# ------------------------------------------------------------------------------------------ helpers
func _playerPos() -> Vector3:
	var p = _gp(game.player, "pos")
	return p if p is Vector3 else TOWER

func _ringPoint(a: float, y: float) -> Vector3:
	var out := Vector3(TOWER.x + cos(a) * B.p1.ring, y, TOWER.z + sin(a) * B.p1.ring)
	out.x = clampf(out.x, ARENA.x0 + 1.5, ARENA.x1 - 1.5)
	out.z = clampf(out.z, ARENA.z0 + 1.5, ARENA.z1 - 1.5)
	return out

# Ring angle scored for readability: 7–11 m from the player, never hidden behind the tower, and (for hops) at
# least 5 m from where he is now. A little randomness keeps the hops unpredictable.
func _pickRingAngle(p: Vector3, from) -> float:
	var best := 0.0
	var bestS := -INF
	for i in 16:
		var a := (i / 16.0) * TAU + (randf() - 0.5) * 0.3
		var v3 := _ringPoint(a, 0.0)
		var dx := v3.x - p.x
		var dz := v3.z - p.z
		var d := Vector2(dx, dz).length()
		var s := -absf(d - 9.0) + randf() * 1.5
		# tower occlusion: distance from the tower axis to the player->point segment
		var L2 := dx * dx + dz * dz
		if L2 == 0.0:
			L2 = 1.0
		var k := clampf(((TOWER.x - p.x) * dx + (TOWER.z - p.z) * dz) / L2, 0.0, 1.0)
		var ox := p.x + dx * k - TOWER.x
		var oz := p.z + dz * k - TOWER.z
		if Vector2(ox, oz).length() < 2.8 and k > 0.05 and k < 0.95:
			s -= 12.0
		if from is Vector3 and Vector2(v3.x - from.x, v3.z - from.z).length() < 5.0:
			s -= 20.0
		if s > bestS:
			bestS = s
			best = a
	return best

func inArena(x: float, z: float) -> bool:
	return x >= ARENA.x0 - 0.3 and x <= ARENA.x1 + 0.3 and z >= ARENA.z0 - 0.3 and z <= ARENA.z1 + 0.3

func _switchPos() -> Vector3:
	var ks = _path(game.level, ["objects", "ee_kill_switch"])
	var p = _gp(ks, "pos")
	return p if p is Vector3 else Vector3(45, 1.2, -9.7)

# The knife switch goes THUNK (if the egg did not already throw it).
func _throwSwitch() -> void:
	var sw = _path(game.level, ["objects", "ee_kill_switch", "parts", "switch"])
	if not (sw is Node3D):
		return
	sw.rotation_order = EULER_ORDER_XYZ
	if sw.rotation.x < 1.5:
		_switchAnim = {"part": sw, "from": sw.rotation.x, "t": 0.0}

func _voice(id: String, vol: float = 1.0) -> void:
	_play(id, {"pos": _screenWorld() if not head.is_empty() else pos, "vol": vol, "tv": true})

func _floorY(x = null, z = null) -> float:
	var xx: float = pos.x if x == null else x
	var zz: float = pos.z if z == null else z
	var col = _gp(game.level, "col")
	var f = _fc(col, "floorAt", [xx, zz, 6])
	return float(f) if (f is float or f is int) and is_finite(float(f)) else 0.0

func _screenWorld() -> Vector3:
	var s = head.get("screen")
	if s is Node3D:
		return DAU.worldPos(s)
	return pos

# ============================================================================================ model
func _ensureBuilt() -> void:
	if built:
		return
	var g = game
	root = DAU.node3d("boss_baron")
	# ---- body (baked SDF, else a primitive stand-in)
	var ch = _buildBakedBody()
	if ch == null:
		ch = _standInBody()
	var grp: Node3D = _gp(ch, "group")
	grp.scale = Vector3.ONE * S
	root.add_child(grp)
	char_ = ch
	J = _path(ch, ["rig", "joints"])
	for n in J:
		var j: Node3D = J[n]
		j.rotation_order = EULER_ORDER_XYZ
		_restPose[n] = j.rotation
	# ---- head (world units under a 1/S holder on the head joint)
	var holder := DAU.node3d("baron_head_holder")
	holder.scale = Vector3.ONE * (HEAD_SCALE / S)
	J.head.add_child(holder)
	head = _buildHead()
	holder.add_child(head.group)
	# ---- cape (model units on the chest joint)
	cape = _buildCape()
	J.chest.add_child(cape.group)
	# ---- tornado (world units on the root)
	tornado = _buildTornado()
	root.add_child(tornado.group)
	# ---- CRT dot / line glows for teleports and the goodnight collapse
	dot = sprite(spriteMat(glowTexture(), linColor("#F4EEFF", 3.0)), "boss_dot")
	dot.visible = false
	fxRoot = DAU.node3d("boss_baron_fx")
	fxRoot.add_child(dot)
	var q := QuadMesh.new()
	line = meshNode(q, spriteMat(lineTexture(), linColor("#F4EEFF", 3.0), true, false), "boss_line")
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	line.visible = false
	fxRoot.add_child(line)
	# ---- off-air shimmer (a 10 % additive copy of the silhouette, on layer 0)
	_buildShimmer()
	var sm = _gp(char_, "skinnedMesh")
	if sm is GeometryInstance3D:
		sm.extra_cull_margin = 8.0
	built = true

# The baked Baron (scripts/art/char_runtime.gd buildCharacter('boss_baron', …)); null when unavailable.
func _buildBakedBody():
	var g = game
	if g.params.get("art") == 0:
		return null
	var path := "res://scripts/art/char_runtime.gd"
	if not ResourceLoader.exists(path):
		return null
	var CR = load(path)
	if CR == null:
		return null
	if CR.has_method("isBaked") and not CR.isBaked("boss_baron"):
		return null
	var opts := {"envMap": _gp(g.mats, "envMap"), "globals": _gp(g.mats, "uniforms"), "animator": false, "shadows": true}
	var res = null
	if CR.has_method("buildCharacter"):
		res = CR.buildCharacter("boss_baron", opts)
	elif CR.can_instantiate():
		var inst = CR.new()
		if inst.has_method("buildCharacter"):
			res = inst.buildCharacter("boss_baron", opts)
	if res == null or _gp(res, "group") == null or not (_path(res, ["rig", "joints"]) is Dictionary):
		push_warning("[boss] baked Baron body unavailable, using the stand-in")
		return null
	return res

# Primitive stand-in body (only when the bake is missing): same joints and proportions. Its meshes are the Blender
# runtime asset baron_standin.glb (standin_torso, standin_upper_L/R, standin_fore_L/R, standin_glove_L/R).
func _standInBody() -> Dictionary:
	var joints := {}
	var rootJ := DAU.node3d("standin_root")
	var mk := func(name: String, parent, p: Array) -> Node3D:
		var o := DAU.node3d(name)
		o.position = Vector3(p[0], p[1], p[2])
		(joints[parent] if parent != null else rootJ).add_child(o)
		joints[name] = o
		return o
	mk.call("base", null, [0, 0, 0])
	mk.call("chest", "base", [0, 0.3, 0])
	mk.call("head", "chest", [0, 0.34, 0.01])
	mk.call("shoulderL", "chest", [-0.31, 0.275, 0.01])
	mk.call("elbowL", "shoulderL", [-0.15, -0.295, -0.03])
	mk.call("handL", "elbowL", [-0.09, -0.28, -0.05])
	mk.call("shoulderR", "chest", [0.31, 0.275, 0.01])
	mk.call("elbowR", "shoulderR", [0.15, -0.295, -0.03])
	mk.call("handR", "elbowR", [0.09, -0.28, -0.05])
	var lib := _loadRuntime(STANDIN_GLB)
	var put := func(src: String, parent: String) -> void:
		var n = lib.find_child(src, true, false) if lib != null else null
		if n is Node3D:
			var t: Transform3D = n.transform
			_adopt(n)
			n.transform = t
			joints[parent].add_child(n)
	put.call("standin_torso", "base")
	for s in ["L", "R"]:
		put.call("standin_upper_" + s, "shoulder" + s)
		put.call("standin_fore_" + s, "elbow" + s)
		put.call("standin_glove_" + s, "hand" + s)
	if lib != null:
		lib.queue_free()
	var group := DAU.node3d("char:boss_baron")
	group.add_child(rootJ)
	return {"group": group, "rig": {"root": rootJ, "joints": joints}, "skinnedMesh": null, "standIn": true}

# Takes a node out of an instanced GLB scene (parent and owner cleared on the whole branch).
static func _adopt(n: Node) -> void:
	DAU.detach(n)
	var clear := func(o: Node) -> void:
		o.owner = null
	DAU.traverse(n, clear)

# Instances a Blender runtime GLB: restores node userData ("da" extras), applies castShadow / visible flags and
# converts every material through mats.fromSpec (SPEC §5.4/§5.5). Returns the glTF scene root (or null).
func _loadRuntime(path: String) -> Node3D:
	if not ResourceLoader.exists(path):
		if not _warned.has(path):
			_warned[path] = true
			push_warning("[boss] runtime asset missing: %s (run blender/build_all.py --only runtime)" % path)
		return null
	var ps = load(path)
	if not (ps is PackedScene):
		return null
	var inst: Node = ps.instantiate()
	DAU.traverse(inst, func(n: Node) -> void: _convertImported(n))
	return inst as Node3D

func _convertImported(n: Node) -> void:
	if n is Node3D:
		(n as Node3D).rotation_order = EULER_ORDER_XYZ
	var ex = n.get_meta("extras") if n.has_meta("extras") else null
	if ex is Dictionary and ex.has("da"):
		var da = JSON.parse_string(ex.da) if ex.da is String else ex.da
		if da is Dictionary:
			var ud := DAU.ud(n)
			ud.merge(da, true)
			if da.get("visible") == false and n is Node3D:
				n.visible = false
			if da.has("castShadow") and n is GeometryInstance3D:
				n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if da.castShadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if n is MeshInstance3D and n.mesh != null and game.mats != null and game.mats.has_method("fromSpec"):
		var mi := n as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var m := mi.get_active_material(i)
			if m == null or not m.has_meta("extras"):
				continue
			var mex = m.get_meta("extras")
			if not (mex is Dictionary and mex.has("da")):
				continue
			var spec = JSON.parse_string(mex.da) if mex.da is String else mex.da
			if spec is Dictionary:
				var conv = game.mats.fromSpec(spec, m)
				if conv is Material:
					mi.set_surface_override_material(i, conv)

# The walnut console-TV head. Local frame: origin at the neck, y up, front = -z. World units (1.6 × 1.3 × 1.2 m).
# The static cabinet (carcass, lid, brass bands, cream bezel, liner, knobs, CH 0 label, grille, back panel, vents,
# swivel collar, antenna dome and telescoping horns with glowing tips, the crack plane, the shimmer box) is the
# Blender asset baron_head.glb; the screen (rubber glass over the animated 'baron' card) and the halos are built here.
func _buildHead() -> Dictionary:
	var g = game
	var W := 1.6
	var H := 1.3
	var D := 1.2
	var Y0 := 0.08
	var CY := Y0 + H / 2.0
	var SCR := {"w": 0.98, "h": 0.76, "x": 0.17, "y": CY + 0.03}      # local +x = the viewer's left: screen left, controls right
	var lib := _loadRuntime(HEAD_GLB)
	var grp: Node3D = null
	if lib != null:
		grp = lib.find_child("baron_head", true, false) as Node3D
		if grp == null and lib.get_child_count() > 0:
			grp = lib.get_child(0) as Node3D
		if grp != null:
			_adopt(grp)
		lib.queue_free()
	if grp == null:
		grp = DAU.node3d("baron_head")
	grp.rotation_order = EULER_ORDER_XYZ
	grp.transform = Transform3D.IDENTITY
	# the screen: rubber glass bulging out of the bezel, showing the Baron's face
	var face = _fc(g.cards, "animated", ["baron", {"owner": "boss"}])
	var faceTex = _gp(face, "texture")
	var scrMat = null
	if g.mats != null and g.mats.has_method("rubberGlass"):
		scrMat = g.mats.rubberGlass(faceTex, {"w": SCR.w, "h": SCR.h, "bright": 1.18, "bulge": 0.07})
	var scrGeo = g.mats.screenGeometry(SCR.w, SCR.h) if g.mats != null and g.mats.has_method("screenGeometry") else planeMesh(SCR.w, SCR.h, 24, 18)
	if scrMat == null:
		scrMat = spriteMat(faceTex if faceTex is Texture2D else glowTexture(), Vector3.ONE * 1.18, false, false)
	var screen := meshNode(scrGeo, scrMat, "baron_screen")
	screen.position = Vector3(SCR.x, SCR.y, -D / 2.0 - 0.045)
	screen.rotation.y = PI
	var sud := DAU.ud(screen)
	sud.noMerge = true
	sud.noAO = true
	sud.noOcclude = true
	screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	grp.add_child(screen)
	# the crack overlay (plane in the GLB; built here when the asset is missing)
	var crack = grp.find_child("baron_crack", true, false)
	if not (crack is MeshInstance3D):
		crack = meshNode(planeMesh(SCR.w * 0.98, SCR.h * 0.98), null, "baron_crack")
		crack.position = Vector3(SCR.x, SCR.y, -D / 2.0 - 0.13)
		crack.rotation.y = PI
		grp.add_child(crack)
	var crackTex = _fc(g.cards, "get", ["crack_overlay"])
	var crackMat := spriteMat(crackTex if crackTex is Texture2D else glowTexture(), Vector3(1.25, 1.25, 1.3), false, false, 3)
	crack.material_override = crackMat
	crack.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	crack.visible = false
	# antenna horns: telescoping chrome rods from a dome, glowing tips (+ halo sprites)
	var top := Y0 + H + 0.03
	var tipMat = g.mats.glow("#D46BFF", 3.2) if g.mats != null and g.mats.has_method("glow") else null
	var halos := []
	var tips := []
	var ants := []
	for s in [-1, 1]:
		var aname := "antennaR" if s < 0 else "antennaL"
		var ant = grp.find_child(aname, true, false)
		if not (ant is Node3D):
			ant = DAU.node3d(aname)
			grp.add_child(ant)
		ant.rotation_order = EULER_ORDER_XYZ
		ant.position = Vector3(s * 0.05, top + 0.05, 0.14)
		ant.rotation = Vector3(0.1, 0, -s * 0.62)
		var aud := DAU.ud(ant)
		aud.noMerge = true
		aud.baseRot = Vector3(0.1, 0, -s * 0.62)
		var tip = ant.find_child(aname + "_tip", true, false)
		if not (tip is Node3D):
			tip = DAU.node3d(aname + "_tip")
			tip.position = Vector3(0, 1.42, 0)
			ant.add_child(tip)
		if tip is MeshInstance3D:
			if tipMat != null:
				tip.material_override = tipMat
			tip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var halo := sprite(spriteMat(glowTexture(), linColor("#C95BFF", 1.6)), aname + "_halo")
		halo.position = tip.position
		halo.scale = Vector3.ONE * 0.75
		ant.add_child(halo)
		ants.append(ant)
		tips.append(tip)
		halos.append(halo)
	var api := {
		"group": grp, "screen": screen, "crack": crack, "face": face, "scrMat": scrMat, "tips": tips, "halos": halos, "ants": ants,
		"W": W, "H": H, "D": D, "Y0": Y0, "CY": CY, "SCR": SCR,
		"wobble": 0.0, "antennaSpark": 0, "faceMode": "laugh", "_flash": null, "_dot": null, "_collapseAt": null,
	}
	return api

# Cape: a curved cloth sheet hanging from behind the shoulders (chest-local, model units). The wobble (amplitude
# grows toward the hem) and the drag against the motion move its vertices every frame (_updateCapeMesh; JS: the
# same formula in a vertex hook). Outside black satin, plum lining inside.
func _buildCape() -> Dictionary:
	var g = game
	var NU := 22
	var NV := 26
	var L := 1.02
	var P := PackedVector3Array()
	var ca := PackedVector2Array()
	for j in NV + 1:
		var v := float(j) / NV
		for i in NU + 1:
			var u := float(i) / NU
			var th := lerpf(-1.95 + 3.9 * u, -1.55 + 3.1 * u, v)
			var r := lerpf(0.27, 0.56, pow(v, 0.8)) + 0.034 * v * sin(th * 6.2 + 0.6)
			var cz := lerpf(0.05, 0.2, v)
			var x := sin(th) * r * 1.12
			var z := cz + cos(th) * r * 0.78
			var y := 0.255 - L * v + 0.03 * pow(v, 4.0) * sin(th * 6.2 + 1.4)
			P.append(Vector3(x, y, z))
			ca.append(Vector2(u, v))
	var idx := PackedInt32Array()
	for j in NV:
		for i in NU:
			var a := j * (NU + 1) + i
			var b := a + 1
			var c := a + NU + 1
			var d := c + 1
			idx.append_array([a, c, b, b, c, d])
	var nrm := computeNormals(P, idx)
	# the front side must face away from the body (+z, behind): check the middle vertex normal
	var mid := (NV / 2) * (NU + 1) + (NU / 2)
	var outward := nrm[mid].z > 0.0
	var mesh := meshFrom(P, ca, idx, nrm)
	var U := {"uCapeT": 0.0, "uCapeAmp": 0.05, "uCapeDrag": Vector3.ZERO}
	var make := func(color: String, side: String, name: String):
		if g.mats != null and g.mats.has_method("toon"):
			return g.mats.toon(color, {"rough": 0.42, "rim": 0.5, "rimColor": "#C9A0FF", "keepColor": true, "side": side, "name": name, "wrap": 0.6})
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(color)
		m.cull_mode = BaseMaterial3D.CULL_BACK if side == "front" else BaseMaterial3D.CULL_FRONT
		return m
	var outer := meshNode(mesh, make.call("#1C1628", "front" if outward else "back", "baronCapeOuter"), "baron_cape_outer")
	var inner := meshNode(mesh, make.call("#7E2250", "back" if outward else "front", "baronCapeInner"), "baron_cape_inner")
	outer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	inner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	outer.extra_cull_margin = 2.0
	inner.extra_cull_margin = 2.0
	var group := DAU.node3d("baron_cape")
	group.add_child(outer)
	group.add_child(inner)
	return {"group": group, "U": U, "outer": outer, "inner": inner, "mesh": mesh, "base": P, "ca": ca, "idx": idx, "nrm": nrm}

# The cape vertex hook: wobble + drag (positions only; the normals stay those of the rest sheet, as in the JS).
func _updateCapeMesh() -> void:
	var C := cape
	var U: Dictionary = C.U
	var T: float = U.uCapeT
	var amp: float = U.uCapeAmp
	var drag: Vector3 = U.uCapeDrag
	var base: PackedVector3Array = C.base
	var ca: PackedVector2Array = C.ca
	var out := PackedVector3Array()
	out.resize(base.size())
	for i in base.size():
		var cu := ca[i].x
		var cv := ca[i].y
		var th := (cu - 0.5) * 3.4
		var w := pow(cv, 1.45) * amp
		var p := base[i]
		p.x += w * (sin(T * 1.9 + th * 2.6 + cv * 5.0) * 0.7 + sin(T * 3.7 + th * 5.1) * 0.25)
		p.z += w * (cos(T * 1.6 + th * 1.8 + cv * 4.0) * 0.8 + 0.45)
		p.y += w * 0.3 * sin(T * 1.3 + cv * 3.0 + th)
		p += drag * pow(cv, 1.6)
		out[i] = p
	meshFrom(out, ca, C.idx, C.nrm, C.mesh)

# Static tornado: two nested open cones (world units) with the spiral static shader.
func _buildTornado() -> Dictionary:
	var group := DAU.node3d("baron_tornado")
	var cone := func(rTop: float, ln: float) -> ArrayMesh:
		var NU := 30
		var NV := 18
		var P := PackedVector3Array()
		var uv := PackedVector2Array()
		var idx := PackedInt32Array()
		for j in NV + 1:
			var v := float(j) / NV
			var r := lerpf(rTop, 0.04, pow(v, 0.8)) * (1.0 + 0.12 * sin(v * 9.0))
			for i in NU + 1:
				var a := (float(i) / NU) * TAU
				P.append(Vector3(cos(a) * r, 0.34 - ln * v, sin(a) * r))
				uv.append(Vector2(float(i) / NU, v))
		for j in NV:
			for i in NU:
				var a := j * (NU + 1) + i
				var b := a + 1
				var c := a + NU + 1
				var d := c + 1
				idx.append_array([a, b, c, b, d, c])
		return meshFrom(P, uv, idx)
	var mk := func(alpha: float, gain: float, spin: float, a: String, b: String, prio: int) -> ShaderMaterial:
		return shaderMat(TORNADO_SHADER, {"uTime": 0.0, "uAlpha": alpha, "uGain": gain, "uSpin": spin, "uSway": 0.35, "uReach": 1.0,
			"uA": Color(a), "uB": Color(b)}, prio)
	var outerMat: ShaderMaterial = mk.call(0.7, 1.2, 0.8, "#1E1630", "#6C5A9C", 1)
	var innerMat: ShaderMaterial = mk.call(0.55, 1.35, 1.7, "#2E2250", "#A898D8", 2)
	var outer := meshNode(cone.call(0.82, 3.4), outerMat, "baron_tornado_outer")
	var inner := meshNode(cone.call(0.5, 3.1), innerMat, "baron_tornado_inner")
	for m in [outer, inner]:
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.custom_aabb = AABB(Vector3(-3, -8, -3), Vector3(6, 9, 6))
		group.add_child(m)
	return {"group": group, "mats": [outerMat, innerMat], "alpha": [0.7, 0.55], "reach": [1.0, 1.0], "outer": outer, "inner": inner}

func _buildShimmer() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color("#B9C6FF", 0.1)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.disable_fog = true
	_shimmerMat = mat
	_shimmer = []
	var sm = _gp(char_, "skinnedMesh")
	if sm is MeshInstance3D and sm.get_parent() != null:
		var s := MeshInstance3D.new()
		s.mesh = sm.mesh
		s.skin = sm.skin
		s.transform = sm.transform
		sm.get_parent().add_child(s)
		s.skeleton = sm.skeleton
		s.material_override = mat
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		s.extra_cull_margin = 8.0
		s.visible = false
		s.name = "baron_shimmer_body"
		_shimmer.append(s)
	var h := head
	var hb = h.group.find_child("baron_shimmer_head", true, false)
	if hb is MeshInstance3D:
		hb.material_override = mat
		hb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		hb.visible = false
		_shimmer.append(hb)
	var fx := _loadRuntime(FX_GLB)
	var cone = fx.find_child("baron_shimmer_cone", true, false) if fx != null else null
	if cone is MeshInstance3D:
		_adopt(cone)
		cone.material_override = mat
		cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cone.rotation_order = EULER_ORDER_XYZ
		cone.rotation = Vector3(PI, 0, 0)
		cone.position = Vector3(0, -1.4, 0)
		cone.scale = Vector3.ONE
		cone.visible = false
		root.add_child(cone)
		_shimmer.append(cone)
	var ball = fx.find_child("baron_ball", true, false) if fx != null else null
	if ball is MeshInstance3D:
		_ballMesh = ball.mesh
	if fx != null:
		fx.queue_free()

func _setLayers(layer: int) -> void:
	if root == null:
		return
	DAU.setLayerRecursive(root, layer)
	for s in _shimmer:
		s.layers = 1 << Config.LAYERS.WORLD
	dot.layers = 1 << Config.LAYERS.WORLD
	line.layers = 1 << Config.LAYERS.WORLD
	_layer = layer

# scrMat.map = tex (DAMaterial facade; a plain ShaderMaterial gets the screen shader's parameters).
func _setScrMap(tex) -> void:
	var m = head.scrMat
	if m == null or not (tex is Texture2D):
		return
	if "map" in m:
		m.map = tex
	elif m is ShaderMaterial:
		m.set_shader_parameter("tScreen", tex)
		m.set_shader_parameter("uTexel", Vector2(1.0 / maxf(1, tex.get_width()), 1.0 / maxf(1, tex.get_height())))
		if m.shader != null and m.shader.code.find("uniform sampler2D map") >= 0:
			m.set_shader_parameter("map", tex)

# mat.uniforms.<name>.value = v (DAMaterial facade), else the shader parameter.
func _setUniform(m, name: String, v) -> void:
	var U = m.get("uniforms") if m is Object else null
	if U is Dictionary and U.get(name) is Object:
		U[name].value = v
	elif m is ShaderMaterial:
		m.set_shader_parameter(name, v)

func _setFace(mode: String) -> void:
	var h := head
	if h.is_empty():
		return
	h.faceMode = mode
	if mode == "bars":
		_setScrMap(_fc(game.cards, "get", ["color_bars"]))
		return
	_setScrMap(_gp(h.face, "texture"))
	var variant := "laugh" if mode == "laugh" else mode
	var fo = _gp(h.face, "opts")
	if _gp(fo, "variant") != variant:
		# handle.set(patch) (an Object handle names it set_: SPEC §3.2)
		if h.face is Dictionary:
			_fc(h.face, "set", [{"variant": variant}])
		elif h.face is Object and is_instance_valid(h.face) and h.face.has_method("set_"):
			h.face.set_({"variant": variant})

# CRT warm-up / power-off of the whole figure: k = 0 dot, 0.45 line, 1 full. The glowing dot and line live in the
# unscaled fxRoot (placed at his chest every frame).
func _dotScale(k: float) -> void:
	k = clampf(k, 0.0, 1.0)
	var sx: float
	var sy: float
	if k < 0.45:
		sx = maxf(0.002, smooth(k / 0.45))
		sy = 0.012
	else:
		sx = 1.0
		sy = lerpf(0.012, 1.0, easeOutBack((k - 0.45) / 0.55, 1.2))
	root.scale = Vector3(sx, sy, sx)
	var show := k < 0.999
	dot.visible = show and k < 0.32
	line.visible = show and k > 0.04 and k < 0.78
	if dot.visible:
		var s := lerpf(0.5, 1.7, k / 0.12) if k < 0.12 else lerpf(1.7, 0.4, (k - 0.12) / 0.2)
		dot.scale = Vector3(s, s, 1)
	if line.visible:
		if game.camera != null:
			line.quaternion = game.camera.global_basis.get_rotation_quaternion()
		line.scale = Vector3(maxf(0.05, 4.4 * sx), 0.22, 1)
		(line.material_override as ShaderMaterial).set_shader_parameter("opacity", 1.0 if k < 0.45 else 1.0 - (k - 0.45) / 0.33)

func _restoreScale() -> void:
	if root == null:
		return
	root.scale = Vector3.ONE
	dot.visible = false
	line.visible = false

# ============================================================================================ animation
# Idle hover sway + gestures (volley throw, sweep spread, grab, wave) + the head, cape and tornado effects.
func _animateModel(dt: float, real: bool) -> void:
	var g = game
	var R := _restPose
	var h := head
	var t: float
	if real:
		_rt = (_rt if _rt != 0.0 else _t) + dt
		t = _rt
	else:
		t = _t
	if root == null:
		return
	root.position = pos
	root.rotation = Vector3(0, yaw, 0)
	if fxRoot != null:
		fxRoot.position = Vector3(pos.x, pos.y + 1.1, pos.z)
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - dt * 3.0)
		root.position.x += (randf() - 0.5) * _shake * 0.3
		root.position.y += (randf() - 0.5) * _shake * 0.2
	# ---- joints (rest + offsets)
	for n in J:
		if R.has(n):
			J[n].rotation = R[n]
	J.chest.rotation.z += sin(t * 0.9) * 0.045
	J.chest.rotation.x += -0.05 + sin(t * 0.7) * 0.03
	J.head.rotation.z += sin(t * 1.1 + 0.4) * 0.05
	J.head.rotation.x += sin(t * 0.8) * 0.03 - 0.04
	var armL := {"x": 0.25 + sin(t * 1.2) * 0.1, "z": -0.12 + sin(t * 1.05) * 0.08, "e": 0.45 + sin(t * 1.4) * 0.12, "h": 0.0}
	var armR := {"x": 0.25 + sin(t * 1.2 + 1.1) * 0.1, "z": 0.12 - sin(t * 1.05 + 0.7) * 0.08, "e": 0.45 + sin(t * 1.4 + 0.9) * 0.12, "h": 0.0}
	var ge = _gesture
	if ge != null:
		ge.t += dt
		if ge.kind == "throw":
			var u: float = ge.t / 0.7
			var up := smooth(u / 0.45) if u < 0.45 else 1.0 - smooth((u - 0.45) / 0.55)
			armR = {"x": 0.25 + up * 1.6, "z": 0.35 * up, "e": 0.2 + up * 0.3, "h": -0.4 * up}
			if u >= 1.0:
				_gesture = null
		elif ge.kind == "spread":
			var u := minf(1.0, ge.t / 0.4)
			var s := smooth(u)
			armL = {"x": 0.5 * s + 0.2, "z": -0.9 * s, "e": 0.25, "h": 0.4 * s}
			armR = {"x": 0.5 * s + 0.2, "z": 0.9 * s, "e": 0.25, "h": -0.4 * s}
			var dur: float = ge.get("dur", 3.7)
			if ge.t > (dur if dur else 3.7):
				_gesture = null
		elif ge.kind == "wave":
			var w := sin(ge.t * 7.5)
			armR = {"x": 1.1, "z": 1.25 + w * 0.22, "e": 1.2 + w * 0.2, "h": 0.2}
			armL = {"x": 0.45, "z": -0.25, "e": 0.9, "h": 0.0}
		elif ge.kind == "hurt":
			var k := maxf(0.0, 1.0 - ge.t / 0.45)
			J.chest.rotation.x -= 0.22 * k
			J.head.rotation.x -= 0.18 * k
			if ge.t > 0.45:
				_gesture = null
	var gr = _grab
	if gr != null:
		if gr.phase == "windup":
			var s := smooth(gr.t / B.p3.grabWindup)
			armL = {"x": 0.3 + 1.9 * s, "z": -0.35 * s, "e": 0.15, "h": 0.5 * s}
			armR = {"x": 0.3 + 1.9 * s, "z": 0.35 * s, "e": 0.15, "h": -0.5 * s}
		elif gr.phase == "strike" or gr.phase == "recover":
			var s := smooth(gr.t / 0.18) if gr.phase == "strike" else 1.0 - smooth(gr.t / 0.8)
			armL = {"x": lerpf(0.3, 1.1, s), "z": lerpf(-0.1, 0.25, s), "e": 0.6 * s, "h": -0.9 * s}
			armR = {"x": lerpf(0.3, 1.1, s), "z": lerpf(0.1, -0.25, s), "e": 0.6 * s, "h": 0.9 * s}
	if _transT > 0.0:
		var k := minf(1.0, (TRANSITION - _transT) / 0.3)
		armL = {"x": 1.2 * k, "z": -1.1 * k, "e": 1.4 * k, "h": 0.5}
		armR = {"x": 1.2 * k, "z": 1.1 * k, "e": 1.4 * k, "h": -0.5}
		J.chest.rotation.x -= 0.2 * k
	J.shoulderL.rotation.x += armL.x
	J.shoulderL.rotation.z += armL.z
	J.elbowL.rotation.x += armL.e
	J.handL.rotation.z += armL.h
	J.shoulderR.rotation.x += armR.x
	J.shoulderR.rotation.z += armR.z
	J.elbowR.rotation.x += armR.e
	J.handR.rotation.z += armR.h
	# ---- head: face card, bulge, wobble, antennas (twitch, glow, sparks)
	if not h.is_empty():
		_fc(h.face, "tick", [g.time.realNow if real else _t])
		var sm = h.scrMat
		h.wobble = maxf(0.0, h.wobble - dt * 2.2)
		var tele: bool = _sweep != null and _sweep.phase == "tele"
		_setUniform(sm, "uWobble", h.wobble)
		_setUniform(sm, "uBulge", 0.07 + 0.03 * sin(t * 2.3) + h.wobble * 0.08 + (0.05 if tele else 0.0))
		_setUniform(sm, "uBright", 1.18 + (0.9 * (0.5 + 0.5 * sin(t * 30.0)) if tele else 0.0))
		for i in h.ants.size():
			var a: Node3D = h.ants[i]
			var br: Vector3 = DAU.ud(a).baseRot
			var tw := (0.12 if _sparking else 0.04) * sin(t * (9.1 if i else 7.3)) + ((randf() - 0.5) * 0.25 if randf() < dt * 2.0 else 0.0)
			a.rotation = Vector3(br.x + sin(t * 1.7 + i) * 0.05, br.y, br.z + tw)
			var glow := 0.6 + randf() * 1.2 if _sparking else 1.0 + 0.25 * sin(t * 4.0 + i * 2.0)
			h.halos[i].scale = Vector3.ONE * (0.75 * glow)
			if _sparking and randf() < dt * 5.0:
				var v3 := DAU.worldPos(h.tips[i])
				_burst(v3, {"shape": "spark", "count": 6, "speed": 5, "size": 0.05, "life": 0.35, "colors": ["#FFFFFF", "#E7B8FF", "#FFE27A"]})
				if randf() < 0.3:
					_play("hurt_static", {"pos": v3, "vol": 0.35, "rate": 1.6})
	# ---- cape: wobble + drag against the motion (chest-local, model units)
	if not cape.is_empty():
		var U: Dictionary = cape.U
		U.uCapeT = t
		var vel: Vector3 = _vel if _vel is Vector3 else Vector3.ZERO
		var sp := minf(3.0, vel.length())
		U.uCapeAmp = 0.05 + sp * 0.025
		var v4: Vector3 = root.quaternion.inverse() * (vel * -0.035)
		U.uCapeDrag = (U.uCapeDrag as Vector3).lerp(v4, 1.0 - exp(-(dt if dt else 0.016) * 3.0))
		_updateCapeMesh()
	# ---- tornado
	if not tornado.is_empty():
		var ms: Array = tornado.mats
		var reach := maxf(1.0, (pos.y - _floorY()) / 3.1) if (_sweep != null and _sweep.phase != "done") else 1.0
		for i in ms.size():
			var m: ShaderMaterial = ms[i]
			m.set_shader_parameter("uTime", t)
			m.set_shader_parameter("uSway", 0.35 + minf(1.0, (_vel.length() if _vel is Vector3 else 0.0) * 0.2))
			tornado.reach[i] += (reach - tornado.reach[i]) * (1.0 - exp(-(dt if dt else 0.016) * 6.0))
			m.set_shader_parameter("uReach", tornado.reach[i])
		_staticT -= dt
		if _staticT <= 0.0 and root.visible and _layer != Config.LAYERS.TV_ONLY:
			_staticT = 0.08
			var a := randf() * TAU
			var v := randf()
			var v3 := Vector3(pos.x + cos(a) * (0.6 - v * 0.5), pos.y - v * 3.0, pos.z + sin(a) * (0.6 - v * 0.5))
			_burst(v3, {"shape": "static", "count": 1, "speed": 0.8, "size": 0.14, "life": 0.5})
	# ---- knife switch THUNK
	var sa = _switchAnim
	if sa != null:
		sa.t += dt
		var k := minf(1.0, sa.t / 0.22)
		if is_instance_valid(sa.part):
			sa.part.rotation.x = lerpf(sa.from, 1.9, easeOutBack(k, 2.2))
		if k >= 1.0:
			_switchAnim = null
	# ---- whiteout pulse (intro)
	var post = _post()
	if _whiteout > 0.0 and post != null:
		_whiteout = maxf(0.0, _whiteout - (dt if dt else 0.016) * 1.2)
		post.whiteout = maxf(float(_gp(post, "whiteout", 0.0)), _whiteout)
	# ---- off-air shimmer flicker
	if _shimmerMat != null and _layer == Config.LAYERS.TV_ONLY:
		_shimmerMat.albedo_color.a = 0.07 + 0.05 * randf()

# ============================================================================================ attacks
# ---- channel hopping: CRT dot-out, jump along the ring, dot-in
func _startHop() -> void:
	var p: Vector3 = _playerPos() if game.player != null else TOWER
	var a := _pickRingAngle(p, pos)
	_ringA = a
	_hop = {"t": 0.0, "to": _ringPoint(a, _hoverY), "moved": false}
	_play("boss_teleport", {"pos": pos})
	_vel = null

func _updateHop(dt: float) -> void:
	var h = _hop
	h.t += dt
	if h.t < HOP.out:
		_dotScale(1.0 - h.t / HOP.out)
	elif not h.moved:
		h.moved = true
		_burst(Vector3(pos.x, pos.y + 1.2, pos.z), {"shape": "static", "count": 22, "speed": 4, "size": 0.22, "life": 0.5})
		pos.x = h.to.x
		pos.z = h.to.z
		if game.player != null:
			var pp := _playerPos()
			yaw = yawTo(pp.x - pos.x, pp.z - pos.z)
		_dotScale(0.0)
		root.visible = false
		dot.visible = false
		line.visible = false
	elif h.t < HOP.out + 0.12:
		root.visible = false
		dot.visible = false
		line.visible = false
	else:
		root.visible = true
		var k: float = (h.t - HOP.out - 0.12) / HOP["in"]
		_dotScale(k)
		if k >= 1.0:
			_restoreScale()
			_hop = null
			_hopT = float(B.p1.hopEvery)
			_burst(Vector3(pos.x, pos.y + 1.2, pos.z), {"shape": "confetti", "count": 10, "colors": Config.BARS, "speed": 4, "size": 0.12})

# ---- static balls: volleys of 3, weakly homing
func _volley() -> void:
	var p = game.player
	if p == null or not _gp(p, "alive", false):
		return
	_gesture = {"kind": "throw", "t": 0.0}
	var o := DAU.worldPos(J.handR)
	o.y += 0.2
	var pp := _playerPos()
	var target := Vector3(pp.x, pp.y + 1.1, pp.z)
	var d := (target - o).normalized()
	var spread := 0.24
	for i in range(-1, 2):
		var dir := d.rotated(Vector3.UP, i * spread)
		dir.y += absf(i) * 0.04
		dir = dir.normalized()
		_spawnBall(o, dir * B.p1.ballSpeed, i * 0.06)
	if randf() < 0.35 and _voiceT <= 0.0:
		_voiceT = 3.0
		_play("boss_voice", {"pos": pos, "syllables": 3})

func _ballPool() -> void:
	if _ballMat != null:
		return
	if _ballMesh == null:
		# baron_fx.glb missing: a sphere of the icosahedron's size keeps the balls visible
		var sm := SphereMesh.new()
		sm.radius = 0.28
		sm.height = 0.56
		_ballMesh = sm
	_ballMat = shaderMat(BALL_SHADER, {"uTime": 0.0, "uCol": Color("#B574FF")})
	_ballHalo = spriteMat(glowTexture(), linColor("#A86BFF", 1.1))

func _spawnBall(from: Vector3, vel: Vector3, delay: float = 0.0):
	var g = game
	_ballPool()
	var b = null
	for x in _balls:
		if not x.alive:
			b = x
			break
	if b == null:
		if _balls.size() >= 14:
			return null
		var mesh := meshNode(_ballMesh, _ballMat, "baron_ball")
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var halo := sprite(_ballHalo, "baron_ball_halo")
		halo.scale = Vector3.ONE * 1.05
		mesh.add_child(halo)
		b = {"mesh": mesh, "halo": halo, "pos": Vector3.ZERO, "vel": Vector3.ZERO, "alive": false}
		_balls.append(b)
	b.alive = true
	b.life = 5.5
	b.delay = delay
	b.trail = 0.0
	b.pos = from
	b.vel = vel
	b.mesh.position = from
	b.mesh.visible = delay <= 0.0
	b.mesh.scale = Vector3.ONE * 0.2
	b.age = 0.0
	if b.mesh.get_parent() == null:
		g.scene.add_child(b.mesh)
	b.loop = null
	if g.audio != null:
		b.loop = _fc(g.audio, "loop", ["boss_static_ball", {"pos": from, "vol": 0.55}])
	return b

func _popBall(b: Dictionary, hitPlayer: bool = false) -> void:
	b.alive = false
	b.mesh.visible = false
	if b.loop != null:
		_fc(b.loop, "stop", [0.05])
		b.loop = null
	_burst(b.pos, {"shape": "static", "count": 26 if hitPlayer else 14, "speed": 5 if hitPlayer else 3, "size": 0.2, "life": 0.5})
	_burst(b.pos, {"shape": "spark", "count": 8, "speed": 5, "size": 0.05, "colors": ["#FFFFFF", "#C9A0FF"], "life": 0.3})
	if hitPlayer:
		_flash(b.pos, "#B77BFF", 6, 0.25)

func _clearBalls() -> void:
	for b in _balls:
		if b.alive:
			_popBall(b)

func _updateBalls(dt: float) -> void:
	var g = game
	var p = g.player
	var col = _gp(g.level, "col")
	if _ballMat != null:
		_ballMat.set_shader_parameter("uTime", _t)
	var maxTurn := deg_to_rad(15.0) * dt
	var palive: bool = p != null and _gp(p, "alive", false)
	var pp := _playerPos()
	for b in _balls:
		if not b.alive:
			continue
		if b.delay > 0.0:
			b.delay -= dt
			if b.delay > 0.0:
				continue
			b.mesh.visible = true
		b.age += dt
		b.life -= dt
		if b.life <= 0.0:
			_popBall(b)
			continue
		# weak homing toward the player's chest
		if palive:
			var v: Vector3 = (Vector3(pp.x, pp.y + 1.0, pp.z) - b.pos).normalized()
			var v2: Vector3 = b.vel.normalized()
			var ang := v2.angle_to(v)
			if ang > 1e-4:
				var ax := v2.cross(v).normalized()
				if ax.length_squared() > 0.0:
					b.vel = b.vel.rotated(ax, minf(ang, maxTurn))
		var step: float = b.vel.length() * dt
		var d: Vector3 = b.vel.normalized()
		var hit = _fc(col, "raycast", [b.pos, d, step + 0.25])
		b.pos += b.vel * dt
		b.mesh.position = b.pos
		b.mesh.rotation.x += dt * 5.0
		b.mesh.rotation.y += dt * 7.0
		var s: float = minf(1.0, b.age / 0.15) * (1.0 + 0.12 * sin(b.age * 40.0))
		b.mesh.scale = Vector3.ONE * s
		(b.halo.material_override as ShaderMaterial).set_shader_parameter("rotation", b.age * 3.0)
		if b.loop != null:
			_fc(b.loop, "setPos", [b.pos])
		b.trail -= dt
		if b.trail <= 0.0:
			b.trail = 0.04
			_burst(b.pos, {"shape": "static", "count": 1, "speed": 0.4, "size": 0.12, "life": 0.35})
		if hit != null and float(_gp(hit, "dist", INF)) <= step + 0.25:
			_popBall(b)
			continue
		# player capsule (feet+0.3 .. feet+1.5)
		if palive:
			var cy := clampf(b.pos.y, pp.y + 0.3, pp.y + 1.5)
			var dx: float = b.pos.x - pp.x
			var dy: float = b.pos.y - cy
			var dz: float = b.pos.z - pp.z
			var pr: float = _gp(p, "radius", 0.38)
			if dx * dx + dy * dy + dz * dz < pow(0.28 + (pr if pr else 0.38), 2.0):
				_fc(p, "hurt", [B.p1.ballDmg, b.pos])
				_play("hurt_static", {"pos": b.pos, "vol": 0.8})
				_popBall(b, true)
				continue
		if b.pos.y < _floorY(b.pos.x, b.pos.z) + 0.15:
			_popBall(b)

# ---- phase 2: the test-pattern sweep
func _sweepAssets() -> void:
	if _blade != null:
		return
	var g = game
	var bars := barColors()
	var ln: float = B.p2.beamR - 0.4
	var bg := planeMesh(ln, B.p2.beamTop, 28, 1, Vector3(0.4 + ln / 2.0, B.p2.beamTop / 2.0, 0))
	_bladeMat = shaderMat(BLADE_SHADER, {"uTime": 0.0, "uAlpha": 1.0, "uBars": bars})
	var blade := meshNode(bg, _bladeMat, "baron_sweep_blade")
	blade.custom_aabb = AABB(Vector3(-20, -1, -20), Vector3(40, 3, 40))
	blade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# glow wall above the blade (soft)
	var NU := 48
	var NV := 8
	var P := PackedVector3Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	for j in NV + 1:
		for i in NU + 1:
			var u := float(i) / NU
			var v := float(j) / NV
			var a := u * PI
			var r := lerpf(0.5, B.p2.beamR, v)
			P.append(Vector3(cos(a) * r, 0, sin(a) * r))
			uv.append(Vector2(u, v))
	for j in NV:
		for i in NU:
			var a := j * (NU + 1) + i
			var b := a + 1
			var c := a + NU + 1
			var d := c + 1
			idx.append_array([a, b, c, b, d, c])
	_fanMat = shaderMat(FAN_SHADER, {"uTime": 0.0, "uAlpha": 0.0, "uSweep": -1.0, "uPulse": 0.0, "uBars": bars}, 2)
	var fan := meshNode(meshFrom(P, uv, idx), _fanMat, "baron_sweep_fan")
	fan.custom_aabb = AABB(Vector3(-20, -1, -20), Vector3(40, 3, 40))
	fan.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var group := DAU.node3d("baron_sweep")
	var bladeHolder := DAU.node3d("baron_sweep_holder")
	bladeHolder.add_child(blade)
	group.add_child(fan)
	group.add_child(bladeHolder)
	group.visible = false
	_blade = {"group": group, "fan": fan, "blade": blade, "bladeHolder": bladeHolder}
	g.scene.add_child(group)

func _startSweep() -> void:
	var g = game
	var p = g.player
	if p == null:
		return
	_sweepAssets()
	var fy := _floorY()
	var center := Vector3(pos.x, fy + 0.03, pos.z)
	var pp := _playerPos()
	var aP := atan2(pp.z - center.z, pp.x - center.x)
	var dir := 1.0 if randf() < 0.5 else -1.0
	var a0 := aP - dir * PI / 2.0
	_sweep = {"phase": "tele", "t": 0.0, "center": center, "a0": a0, "dir": dir, "prevA": a0, "hit": false}
	var bl = _blade
	bl.group.position = center
	bl.fan.rotation = Vector3(0, -a0, 0)
	bl.fan.scale = Vector3(1, 1, dir)
	bl.bladeHolder.visible = false
	bl.group.visible = true
	_fanMat.set_shader_parameter("uSweep", -1.0)
	_gesture = {"kind": "spread", "t": 0.0, "dur": B.p2.tele + B.p2.sweepTime + 0.2}
	_play("boss_sweep_warn", {"pos": pos, "vol": 1.1})
	_play("tone_1khz", {"pos": pos, "vol": 0.35})

func _updateSweep(dt: float) -> void:
	var s = _sweep
	if s == null or _blade == null:
		return
	var g = game
	var P: Dictionary = B.p2
	var bl = _blade
	s.t += dt
	_fanMat.set_shader_parameter("uTime", _t)
	_bladeMat.set_shader_parameter("uTime", _t)
	if s.phase == "tele":
		_fanMat.set_shader_parameter("uAlpha", 0.16 + 0.14 * (0.5 + 0.5 * sin(s.t * 18.0)))
		_fanMat.set_shader_parameter("uPulse", 0.4 * (s.t / P.tele))
		if s.t >= P.tele:
			s.phase = "sweep"
			s.t = 0.0
			bl.bladeHolder.visible = true
			_bladeMat.set_shader_parameter("uAlpha", 1.0)
			_play("boss_sweep", {"pos": pos, "vol": 1.2})
			_camShake(0.12, P.sweepTime)
			if g.input != null:
				_fc(g.input, "rumble", [0.26, 0.08, P.sweepTime * 1000.0])   # the beam's hum on the gamepad (weak motor)
	elif s.phase == "sweep":
		var u := minf(1.0, s.t / P.sweepTime)
		var a: float = s.a0 + s.dir * PI * u
		bl.bladeHolder.rotation.y = -a
		_fanMat.set_shader_parameter("uSweep", u)
		_fanMat.set_shader_parameter("uAlpha", 0.55)
		_fanMat.set_shader_parameter("uPulse", 0.2)
		# damage: did the blade pass the player's angle this frame, with the feet below the beam top?
		var p = g.player
		if p != null and _gp(p, "alive", false) and not s.hit:
			var pp := _playerPos()
			var pr: float = _gp(p, "radius", 0.38)
			if not pr:
				pr = 0.38
			var dx: float = pp.x - s.center.x
			var dz: float = pp.z - s.center.z
			var r := Vector2(dx, dz).length()
			if r > 0.4 and r < P.beamR + pr:
				var ap := atan2(dz, dx)
				var d0: float = angDiff(ap, s.prevA) * s.dir
				var d1: float = angDiff(ap, a) * s.dir
				var crossed := d0 >= -0.02 and d1 <= 0.02 + pr / maxf(1.0, r)
				var feet := pp.y - _floorY(pp.x, pp.z)
				if crossed and feet < P.beamTop:
					s.hit = true
					if _fc(p, "hurt", [P.dmg, s.center]):
						_burst(Vector3(pp.x, pp.y + 0.3, pp.z), {"shape": "confetti", "count": 14, "colors": Config.BARS, "speed": 5, "size": 0.1})
						_fc(p, "knockback", [Vector3(dx, 0, dz).normalized() * 6.0])
		s.prevA = a
		if u >= 1.0:
			s.phase = "fade"
			s.t = 0.0
	elif s.phase == "fade":
		var k: float = 1.0 - s.t / 0.45
		_fanMat.set_shader_parameter("uAlpha", 0.55 * maxf(0.0, k))
		_bladeMat.set_shader_parameter("uAlpha", maxf(0.0, k))
		if k <= 0.0:
			_stopSweep()
			_hopT = minf(_hopT, 0.6)

func _stopSweep() -> void:
	if _blade != null:
		_blade.group.visible = false
	if _sweep != null:
		_sweep.phase = "done"
	_sweep = null
	if _gesture != null and _gesture.kind == "spread":
		_gesture = null

# ---- adds (over the fence climbs and the gate)
func _addsHas(z) -> bool:
	for x in _adds:
		if is_same(x, z):
			return true
	return false

func _addsDelete(z) -> void:
	for i in _adds.size():
		if is_same(_adds[i], z):
			_adds.remove_at(i)
			return

func _updateAdds(dt: float, n: int) -> void:
	var alive := _adds.size()
	if n == 1:
		_addsT -= dt
		if _addsT <= 0.0:
			_addsT = float(B.p1.addsEvery)
			_spawnAdds("tuned_in", mini(3, B.p1.addsMax - alive))
	elif n == 2:
		if not _hasAdd("forecaster"):
			_fcT -= dt
			if _fcT <= 0.0:
				_fcT = 4.0
				_spawnAdds("forecaster", 1)
		_socksT -= dt
		if _socksT <= 0.0:
			_socksT = float(B.p2.socksEvery)
			_spawnAdds("sock_hopper", mini(6, 14 - alive))
	elif n == 3:
		_addsT -= dt
		if _addsT <= 0.0:
			_addsT = float(B.p3.addsEvery)
			_spawnAdds("tuned_in", mini(3, B.p3.addsMax - alive))

func _updateAddsTick(dt: float) -> void:
	_voiceT = maxf(0.0, _voiceT - dt)
	for z in _adds.duplicate():
		if z == null or _gp(z, "dead", false) or _gp(z, "removed", false):
			_addsDelete(z)

func _hasAdd(type: String) -> bool:
	for z in _adds:
		if _gp(z, "type") == type and not _gp(z, "dead", false):
			return true
	return false

func _spawnAdds(type: String, count: int) -> int:
	var Z = game.zombies
	if Z == null or not _hasFn(Z, "spawn") or count <= 0:
		return 0
	var n := 0
	for i in count:
		var entry: String = FENCE[_fenceI % FENCE.size()]
		_fenceI += 1
		var z = _fc(Z, "spawn", [type, entry, null, {}])
		if z != null:
			_adds.append(z)
			n += 1
	return n

func _despawnAdds(fx: bool = true) -> void:
	var Z = game.zombies
	for z in _adds.duplicate():
		if z == null or _gp(z, "dead", false) or _gp(z, "removed", false):
			continue
		if fx:
			var zp = _gp(z, "pos")
			if zp is Vector3:
				_burst(Vector3(zp.x, zp.y + 0.8, zp.z), {"shape": "static", "count": 14, "speed": 2})
		_fc(Z, "despawn", [z, false])
	_adds.clear()

# ---- phase 3: drift toward the player
func _updateDrift(dt: float) -> void:
	var p = game.player
	if p == null:
		return
	var pp := _playerPos()
	var slow := 1.0
	if _grab != null:
		slow = 0.25 if _grab.phase == "windup" else 0.0
	var dx := pp.x - pos.x
	var dz := pp.z - pos.z
	var d := Vector2(dx, dz).length()
	var want := 1.4
	var prev := pos
	if d > want and slow > 0.0:
		var step := minf(d - want, B.p3.drift * slow * dt)
		pos.x += (dx / d) * step
		pos.z += (dz / d) * step
	pos.x = clampf(pos.x, ARENA.x0 + 0.8, ARENA.x1 - 0.8)
	pos.z = clampf(pos.z, ARENA.z0 + 0.8, ARENA.z1 - 0.8)
	_vel = (pos - prev) / maxf(1e-4, dt)

# ---- phase 3: the grab
func _updateGrab(dt: float) -> void:
	var g = game
	var p = g.player
	if p == null:
		return
	var pp := _playerPos()
	var dx := pp.x - pos.x
	var dz := pp.z - pos.z
	var d := Vector2(dx, dz).length()
	var gr = _grab
	var palive: bool = _gp(p, "alive", false)
	if gr == null:
		_grabCd -= dt
		if _grabCd <= 0.0 and d < B.p3.grabR and palive:
			_grab = {"phase": "windup", "t": 0.0}
			_play("boss_grab", {"pos": pos, "vol": 1.1})
			if offAir:
				_revealT = maxf(_revealT, B.p3.grabWindup + 0.5)
			_voice("baron_laugh", 0.8)
		return
	gr.t += dt
	if gr.phase == "windup" and gr.t >= B.p3.grabWindup:
		gr.phase = "strike"
		gr.t = 0.0
		if d < B.p3.grabR + 0.7 and palive:
			if _fc(p, "hurt", [B.p3.grabDmg, pos]):
				var l := d if d else 1.0
				_fc(p, "knockback", [Vector3(dx / l, 0, dz / l) * (B.p3.throw * 6.0)])
				var pv = _gp(p, "vel")
				if pv is Vector3:
					pv.y = maxf(pv.y, 6.5)
					_sp(p, "vel", pv)
				_camShake(0.6, 0.5)
				_burst(Vector3(pp.x, pp.y + 1.2, pp.z), {"shape": "static", "count": 30, "speed": 5, "size": 0.2})
				_play("boss_hurt", {"pos": pos, "vol": 0.6, "rate": 1.4})
		else:
			_burst(Vector3(pos.x + dx * 0.4, _floorY() + 0.2, pos.z + dz * 0.4), {"shape": "puff", "count": 8, "speed": 2, "size": 0.3})
	elif gr.phase == "strike" and gr.t >= 0.2:
		gr.phase = "recover"
		gr.t = 0.0
	elif gr.phase == "recover" and gr.t >= 0.8:
		_grab = null
		_grabCd = 2.4

# ---- phase 3: OFF-AIR (TV only) with the 10 % shimmer
func _updateOffAir(dt: float) -> void:
	if offAir:
		_offAirT -= dt
		if _offAirT <= 0.0:
			_setOffAir(false)
	else:
		_offAirTimer -= dt
		if _offAirTimer <= 0.0 and _grab == null:
			_setOffAir(true)
	if _revealT > 0.0:
		_revealT -= dt
	var hidden := offAir and _revealT <= 0.0
	if hidden != _hidden:
		_hidden = hidden
		_setLayers(Config.LAYERS.TV_ONLY if hidden else Config.LAYERS.WORLD)
		for s in _shimmer:
			s.visible = hidden
	if offAir:
		if _offAirLoop != null:
			_fc(_offAirLoop, "setPos", [pos])
		if hidden and randf() < dt * 9.0:
			var v := Vector3(pos.x + (randf() - 0.5) * 1.6, pos.y + randf() * 3.2 - 1.5, pos.z + (randf() - 0.5) * 1.6)
			_burst(v, {"shape": "static", "count": 1, "speed": 0.5, "size": 0.16, "life": 0.4})

func _setOffAir(on: bool) -> void:
	var g = game
	if offAir == on:
		return
	offAir = on
	if on:
		_offAirT = float(B.p3.offAir)
		_play("boss_offair", {"pos": pos, "vol": 1.1})
		_offAirLoop = _fc(g.audio, "loop", ["boss_static_ball", {"pos": pos, "vol": 0.45}]) if g.audio != null else null
	else:
		_offAirTimer = float(B.p3.offAirEvery)
		_revealT = 0.0
		if _offAirLoop != null:
			_fc(_offAirLoop, "stop", [0.2])
			_offAirLoop = null
		_play("crt_ping", {"pos": pos, "vol": 0.7})
		if _hidden:
			_hidden = false
			_setLayers(Config.LAYERS.WORLD)
			for s in _shimmer:
				s.visible = false
	g.events.emit("machine:boss_offair", {"on": on})

# ============================================================================================ environment
# The moon (a textured plane in the sky dome, renderOrder -8 in the JS) and the stars (a points cloud).
func _isMoon(o: Node) -> bool:
	if not (o is MeshInstance3D):
		return false
	var u := DAU.ud(o)
	if u.get("renderOrder") == -8 or u.get("moon") == true or String(o.name).to_lower().contains("moon"):
		return true
	var m: Material = (o as MeshInstance3D).get_active_material(0) if (o as MeshInstance3D).mesh != null else null
	return m != null and m.render_priority == -8

func _isStars(o: Node) -> bool:
	if o is GPUParticles3D or o is CPUParticles3D:
		return true
	if o is MeshInstance3D:
		var mesh: Mesh = (o as MeshInstance3D).mesh
		if mesh is ArrayMesh and mesh.get_surface_count() > 0 and mesh.surface_get_primitive_type(0) == Mesh.PRIMITIVE_POINTS:
			return true
		return String(o.name).to_lower().contains("star")
	return o is MultiMeshInstance3D and String(o.name).to_lower().contains("star")

static func matColor(o: MeshInstance3D):
	var m := o.material_override if o.material_override != null else o.get_active_material(0)
	if m is BaseMaterial3D:
		return (m as BaseMaterial3D).albedo_color
	if m is ShaderMaterial:
		for k in ["color", "uColor", "albedo"]:
			var v = m.get_shader_parameter(k)
			if v is Color:
				return v
	return null

static func setMatColor(o: MeshInstance3D, c: Color) -> void:
	var m := o.material_override if o.material_override != null else o.get_active_material(0)
	if m is BaseMaterial3D:
		(m as BaseMaterial3D).albedo_color = c
	elif m is ShaderMaterial:
		for k in ["color", "uColor", "albedo"]:
			if m.get_shader_parameter(k) is Color:
				m.set_shader_parameter(k, c)
				return

func _enterDeadAir() -> void:
	var g = game
	var L = g.level
	if _env != null:
		return
	var env := {"t": 0.0, "moon": null, "moonColor": null, "stars": null, "starOp": 1, "amb": null, "fog": null, "hasFog": false, "fogPlanes": null}
	# the moon (a textured plane in the sky dome) and the stars
	var sky = _gp(L, "sky")
	var visit := func(o: Node) -> void:
		if _isMoon(o):
			env.moon = o
			env.moonColor = matColor(o)
		if _isStars(o):
			env.stars = o
	if sky is Node:
		DAU.traverse(sky, visit)
	var yard = _path(L, ["areas", "yard"])
	if yard != null:
		var amb = _gp(yard, "ambient")
		var fog = _gp(yard, "fog")
		env.amb = amb.duplicate() if amb is Dictionary else null
		env.fog = fog.duplicate() if fog is Dictionary else null
		env.hasFog = true
		if amb is Dictionary:
			_sp(yard, "ambient", amb.duplicate())
	# ground-hugging static fog: three stacked noise discs over the arena
	var planes := DAU.node3d("baron_static_fog")
	var mats := []
	var alphas := []
	for row in [[0.22, 0.26, 1.0], [0.65, 0.17, 0.92], [1.25, 0.1, 0.8]]:
		var y: float = row[0]
		var a: float = row[1]
		var s: float = row[2]
		var m := shaderMat(FOG_SHADER, {"uTime": 0.0, "uAlpha": 0.0}, 4)
		var mesh := meshNode(planeMesh(22.0 * s, 22.0 * s), m)
		mesh.rotation.x = -PI / 2.0
		mesh.position = Vector3(43, y, -11)
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		planes.add_child(mesh)
		mats.append(m)
		alphas.append(a)
	g.scene.add_child(planes)
	env.fogPlanes = planes
	env.fogMats = mats
	env.fogAlpha = alphas
	_env = env

func _updateEnv(dt: float) -> void:
	var env = _env
	if env == null:
		return
	env.t += dt
	var k := smooth(env.t / 3.0)
	if env.moon != null and is_instance_valid(env.moon) and env.moonColor is Color:
		var mc: Color = env.moonColor
		setMatColor(env.moon, Color(mc.r * lerpf(1.0, 0.3, k), mc.g * lerpf(1.0, 0.3, k), mc.b * lerpf(1.0, 0.3, k), mc.a))
	var yard = _path(game.level, ["areas", "yard"])
	var ya = _gp(yard, "ambient")
	if yard != null and env.amb is Dictionary and ya is Dictionary:
		ya.intensity = float(env.amb.get("intensity", 0.8)) * lerpf(1.0, 0.55, k)
	if yard != null:
		_sp(yard, "fog", {"color": "#2A2140", "near": lerpf(60, 7, k), "far": lerpf(140, 40, k)})
	for i in env.get("fogMats", []).size():
		var m: ShaderMaterial = env.fogMats[i]
		m.set_shader_parameter("uTime", _t)
		m.set_shader_parameter("uAlpha", env.fogAlpha[i] * k)

func _restoreEnv() -> void:
	var env = _env
	if env == null:
		return
	if env.moon != null and is_instance_valid(env.moon) and env.moonColor is Color:
		setMatColor(env.moon, env.moonColor)
	var yard = _path(game.level, ["areas", "yard"])
	if yard != null:
		if env.amb != null:
			_sp(yard, "ambient", env.amb)
		if env.hasFog:
			_sp(yard, "fog", env.fog)
	if env.fogPlanes != null and is_instance_valid(env.fogPlanes):
		DAU.detach(env.fogPlanes)
		env.fogPlanes.queue_free()
	_env = null

# The yard feed camera (SkyCam 13) auto-tracks him during the fight.
func _feed():
	var cam = _path(game.screens, ["feedCams", "yard"])
	if cam is Node:
		return DAU.ud(cam).get("feed")
	return _path(cam, ["userData", "feed"])

func _trackFeed(on: bool) -> void:
	var f = _feed()
	if f == null:
		return
	if on:
		if _feedSaved == null:
			_feedSaved = {"target": _gp(f, "target"), "phase": _gp(f, "phase")}
	elif _feedSaved != null:
		f.target = _feedSaved.target
		f.phase = _feedSaved.phase
		_feedSaved = null

func _updateFeedTarget(dt: float) -> void:
	var s = game.screens
	var f = _feed()
	if f == null or _feedSaved == null:
		return
	var v := Vector3(pos.x, pos.y + 0.6, pos.z)
	var tg = _gp(f, "target")
	if tg is Vector3:
		f.target = tg.lerp(v, 1.0 - exp(-dt * 4.0))
	var clock = _gp(s, "clock")
	if (clock is float or clock is int) and is_finite(float(clock)):
		f.phase = -(float(clock) / 8.0) * TAU     # cancel the ±20° idle pan (screens PAN.period)

# ---- DY slams shut behind a wall of static (and reopens after the fight)
func _closeDY() -> void:
	var g = game
	var L = g.level
	var d = _path(L, ["doors", DY.id])
	var wasOpen: bool = d != null and bool(_gp(d, "open", false))
	_dy = {"wasOpen": wasOpen}
	if wasOpen:
		_fc(d, "reset")
		_sp(d, "open", false)
		_fc(_gp(L, "col"), "setEnabled", [DY.id, true])
		if g.nav != null:
			_fc(g.nav, "setDoor", [DY.id, false])
	var rc: Array = DY.rect
	var x0: float = rc[0]
	var z0: float = rc[1]
	var x1: float = rc[2]
	var z1: float = rc[3]
	_closeDYWallOnly()
	_wall.position = Vector3(x1 + 0.06, DY.h / 2.0, (z0 + z1) / 2.0)
	(_wall.material_override as ShaderMaterial).set_shader_parameter("uReveal", 0.0)
	_wallT = 0.0
	if _wall.get_parent() == null:
		g.scene.add_child(_wall)
	var c := Vector3((x0 + x1) / 2.0, 1.3, (z0 + z1) / 2.0)
	_play("door_poof", {"pos": c, "vol": 1.2})
	_play("crt_ping", {"pos": c, "vol": 0.8, "delay": 0.05})
	_burst(c, {"shape": "static", "count": 30, "speed": 4, "size": 0.24})

# The DY wall mesh (a double-sided plane of the wall-of-static shader).
func _closeDYWallOnly() -> void:
	if _wall != null:
		return
	var rc: Array = DY.rect
	var z0: float = rc[1]
	var z1: float = rc[3]
	var m := shaderMat(WALL_SHADER, {"uTime": 0.0, "uAlpha": 0.92, "uReveal": 0.0}, 3)
	_wall = meshNode(planeMesh(z1 - z0 + 0.3, DY.h + 0.1), m, "baron_dy_wall")
	_wall.rotation.y = PI / 2.0
	_wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _openDY(quiet: bool) -> void:
	var g = game
	if _wall != null:
		DAU.detach(_wall)
	if _dy != null and _dy.wasOpen:
		_fc(g.level, "openDoor", [DY.id, {"instant": quiet}])
	_dy = null

# ============================================================================================ damage
func _hittable() -> bool:
	return active and state == "fight" and _hop == null and root != null and root.visible

# Nearest hit zone along a ray: screen slab, cabinet, antenna tips (head space), torso + arms + gloves (world).
func raycast(origin: Vector3, dir: Vector3, maxDist: float = 80.0):
	if not _hittable() or not built:
		return null
	var h := head
	# (GDScript lambdas capture locals by value: the best hit is kept in a holder)
	var R := {"t": maxDist, "zone": ""}
	var consider := func(t: float, zone: String) -> void:
		if t >= 0.0 and t < R.t:
			R.t = t
			R.zone = zone
	# head space (holder HEAD_SCALE/S × body S; hit points go back to world space before measuring)
	var mw: Transform3D = (h.group as Node3D).global_transform
	var mi := mw.affine_inverse()
	var ro := mi * origin
	var rd := (mi.basis * dir).normalized()
	var S2: Dictionary = h.SCR
	var hp1 = rayBox(ro, rd, Vector3(S2.x - S2.w / 2.0 - 0.03, S2.y - S2.h / 2.0 - 0.03, -h.D / 2.0 - 0.2), Vector3(S2.x + S2.w / 2.0 + 0.03, S2.y + S2.h / 2.0 + 0.03, -h.D / 2.0 + 0.02))
	if hp1 != null:
		consider.call((mw * hp1).distance_to(origin), "screen")
	var hp2 = rayBox(ro, rd, Vector3(-h.W / 2.0, h.Y0 - 0.12, -h.D / 2.0 - 0.05), Vector3(h.W / 2.0, h.Y0 + h.H + 0.08, h.D / 2.0 + 0.05))
	if hp2 != null:
		consider.call((mw * hp2).distance_to(origin) + 0.01, "body")
	for tip in h.tips:
		consider.call(raySphereT(origin, dir, DAU.worldPos(tip), 0.34 * HEAD_SCALE), "antenna")
	# body (world)
	var a := DAU.worldPos(J.base)
	var b := DAU.worldPos(J.head)
	a.y += 0.35
	b.y -= 0.05
	consider.call(rayCapsule(origin, dir, a, b, 0.2 * S), "body")
	for s in ["L", "R"]:
		var o := DAU.worldPos(J["shoulder" + s])
		var v := DAU.worldPos(J["elbow" + s])
		consider.call(rayCapsule(origin, dir, o, v, 0.085 * S), "body")
		var v2 := DAU.worldPos(J["hand" + s])
		consider.call(rayCapsule(origin, dir, v, v2, 0.075 * S), "body")
		var d := (v2 - v).normalized()
		v2 += d * (0.12 * S)
		consider.call(raySphereT(origin, dir, v2, 0.13 * S), "body")
	var best: String = R.zone
	var bestT: float = R.t
	if best == "":
		return null
	return {"dist": bestT, "point": origin + dir * bestT, "zone": best, "mul": ZONE_MUL[best], "head": false}

# Zone of a hit point (re-cast a short ray through it).
func _zoneAt(point, dir) -> String:
	if not (point is Vector3):
		return "body"
	if dir is Vector3:
		var o: Vector3 = point - dir * 0.8
		var h = raycast(o, dir, 1.6)
		if h != null:
			return h.zone
	return "body"

func damage(amount: float, info: Dictionary = {}) -> bool:
	var g = game
	if not active or state != "fight" or not (amount > 0.0):
		return false
	var cause: String = info.get("cause") if info.get("cause") else ("melee" if info.get("melee") else "bullet")
	var zone = info.get("zone") if ZONE_MUL.has(info.get("zone", "")) else null
	var mul := 1.0
	if not FIXED_CAUSES.has(cause) and not FIXED_CAUSES.has(info.get("weaponId")):
		if zone == null:
			zone = _zoneAt(info.get("point"), info.get("dir"))
		mul = ZONE_MUL.get(zone, 1.0)
	var frame: int = g.time.frame
	var point: Vector3 = info.point if info.get("point") is Vector3 else _screenWorld()
	# off-air: any hit reveals him
	if offAir:
		_revealT = float(B.p3.reveal)
	# invulnerable while he recoils between phases (the static shields him): sparks only
	if _transT > 0.0:
		_burst(point, {"shape": "spark", "count": 4, "speed": 4, "size": 0.04, "colors": ["#C9A0FF", "#FFFFFF"]})
		return false
	var dmg := amount * mul
	var minHp := maxHp * (2.0 / 3.0) if phase == 1 else (maxHp / 3.0 if phase == 2 else 0.0)
	hp = maxf(minHp, hp - dmg)
	var killed := phase == 3 and hp <= 0.0
	# feedback
	if _fxFrame != frame:
		_fxFrame = frame
		_burst(point, {"shape": "static", "count": 3, "speed": 2.5, "size": 0.12, "life": 0.35})
		_burst(point, {"shape": "spark", "count": 3 if zone == "body" else 6, "speed": 5, "size": 0.045, "life": 0.25, "colors": ["#FFE27A", "#FFFFFF"] if zone == "antenna" else ["#FFFFFF", "#C9A0FF"]})
		head.wobble = minf(1.0, head.wobble + (0.35 if zone == "screen" else 0.12))
		_shake = minf(1.0, _shake + 0.15)
	if dmg > maxHp * 0.012 or zone != "body":
		_hurtT = _hurtT - 0.0
		if _gesture == null or _gesture.kind == "hurt":
			_gesture = {"kind": "hurt", "t": 0.0}
	if _voiceT <= 0.0 and randf() < 0.25:
		_voiceT = 1.6
		_play("boss_hurt", {"pos": pos, "vol": 0.9})
	if phase == 1 and head.faceMode == "laugh" and zone == "screen" and randf() < 0.3:
		_setFace("angry")
		_faceTok += 1
		var tok := _faceTok
		var back := func() -> void:
			if tok == _faceTok and phase == 1 and head.faceMode == "angry" and state == "fight":
				_setFace("laugh")
		g.get_tree().create_timer(0.65).timeout.connect(back)
	# points: +10 per damaging hit event (one per frame + weapon)
	if info.get("points") != false:
		var key := "%d|%s" % [frame, str(info.get("weaponId")) if info.get("weaponId") else cause]
		if _ptKey != key:
			_ptKey = key
			if g.economy != null:
				_fc(g.economy, "add", [Config.T.points.hit, "hit"])
	if info.get("hitmarker") != false and _hmFrame != frame:
		_hmFrame = frame
		if g.hud != null:
			_fc(g.hud, "hitmarker", [zone == "screen" or zone == "antenna", killed])
	g.events.emit("boss:hit", {"dmg": dmg, "zone": zone, "point": point, "cause": cause, "weaponId": info.get("weaponId"), "hp": hp})
	if killed:
		_defeat()
		return true
	_checkPhase()
	return false

# ---- shootable (bullets + melee through weapons.gd)
func _registerShootable() -> void:
	var w = game.weapons
	if w == null or not _hasFn(w, "registerShootable"):
		return
	var rc := func(o: Vector3, d: Vector3, mx = 80.0):
		var h = raycast(o, d, float(mx) if mx != null else 80.0)
		return {"dist": h.dist, "point": h.point} if h != null else null
	var onHit := func(info: Dictionary) -> void:
		var zone := _zoneAt(info.get("point"), info.get("dir"))
		var ii := info.duplicate()
		ii.zone = zone
		var c = info.get("cause")
		ii.cause = "melee" if info.get("melee") else ("bullet" if (c == "bullet" or not c) else c)
		damage(float(info.get("damage")) if info.get("damage") else 0.0, ii)
	_fc(w, "registerShootable", [{"id": "boss_baron", "blocksBullet": true, "melee": true, "bullets": true, "raycast": rc, "onHit": onHit}])
	_shootable = true

func _unregisterShootable() -> void:
	if not _shootable:
		return
	_shootable = false
	if game.weapons != null:
		_fc(game.weapons, "unregisterShootable", ["boss_baron"])

# ---- the wonder-weapon adapter (see header)
func _makeProxy() -> Dictionary:
	return {
		"id": "boss_baron", "type": "boss_baron", "boss": true, "flags": {"boss": true}, "def": {"id": "boss_baron"},
		"pos": Vector3.ZERO, "vel": Vector3.ZERO, "knock": Vector3.ZERO, "yaw": 0.0, "hp": 1.0, "maxHp": 1.0, "state": "dead",
		"dead": false, "removed": false, "radius": 1.1, "height": 5.0, "speed": 0.0, "scale": 1.0, "group": null, "head": null, "headR": 0.6,
		"hitZones": [{"zone": "screen", "mul": B.screenMul}, {"zone": "antenna", "mul": B.antennaMul}, {"zone": "body", "mul": B.bodyMul}],
		"anim": {}, "stun": 0.0, "area": "yard", "entry": null,
	}

func _syncProxy() -> void:
	var P := proxy
	P.pos = Vector3(pos.x, pos.y - 1.9, pos.z)
	P.hp = maxf(0.0, hp)
	P.maxHp = maxHp
	P.state = "chase" if _hittable() else "dead"
	P.yaw = yaw
	P.group = root
	P.head = head.get("screen")

# The JS wrappers of zombies.damage / zombies.raycast / wonder._zombies, as Callables zombies.gd and wonder.gd call
# while `_adapted` is set (GDScript cannot patch methods on an instance).
func _installAdapters() -> void:
	var g = game
	var zm = g.zombies
	if _adapted != null or zm == null:
		return
	# -> null when z is not the proxy (zombies.damage proceeds), else the boss result
	var dmg := func(z, amount, info):
		if not is_same(z, proxy):
			return null
		var ii: Dictionary = info.duplicate() if info is Dictionary else {}
		ii.zone = info.get("zone") if info is Dictionary else null
		ii.cause = info.get("cause") if (info is Dictionary and info.get("cause")) else "wonder"
		return damage(float(amount), ii)
	# h = zombies' own hit (or null) for (o, d, max); returns the wrapped result
	var rc := func(o: Vector3, d: Vector3, mx, h):
		var b = raycast(o, d, float(_gp(h, "dist", mx if mx != null else 80.0))) if _hittable() else null
		if b != null:
			return {"z": proxy, "head": false, "dist": b.dist, "point": b.point, "zone": b.zone, "mul": b.mul}
		return h
	var zs := func(list: Array) -> Array:
		if _hittable():
			var out := list.duplicate()
			out.append(proxy)
			return out
		return list
	_adapted = {"zm": zm, "wonder": g.wonder, "damage": dmg, "raycast": rc, "zombies": zs}
	if g.wonder != null and "_zombiesHook" in g.wonder:
		g.wonder._zombiesHook = zs
	if zm is Object and "_damageHook" in zm:
		zm._damageHook = dmg
	if zm is Object and "_raycastHook" in zm:
		zm._raycastHook = rc

func _uninstallAdapters() -> void:
	var A = _adapted
	if A == null:
		return
	if A.wonder != null and is_instance_valid(A.wonder) and "_zombiesHook" in A.wonder:
		A.wonder._zombiesHook = Callable()
	var zm = A.zm
	if zm is Object and is_instance_valid(zm):
		if "_damageHook" in zm:
			zm._damageHook = Callable()
		if "_raycastHook" in zm:
			zm._raycastHook = Callable()
	_adapted = null

# ============================================================================================ defeat
func _defeat() -> void:
	var g = game
	hp = 0.0
	state = "defeated"
	_clearBalls()
	_stopSweep()
	_grab = null
	_hop = null
	if offAir:
		_setOffAir(false)
	_restoreScale()
	_despawnAdds(true)
	_unregisterShootable()
	_uninstallAdapters()
	_completeEgg()
	g.events.emit("boss:defeated", {"round": round})
	if ending != null and ending.has_method("play"):
		ending.play({"round": round})
		return
	end({"quiet": true})
	g.victory()

# egg:step {step:6} + egg:complete: through the egg's own API when it reached step 5 (a debug fight started from
# an earlier step leaves the egg alone).
func _completeEgg() -> void:
	var g = game
	var e = g.egg
	if e == null or _gp(e, "done", false) or not (float(_gp(e, "step", 0)) >= 5):
		return
	if _hasFn(e, "onBossDefeated"):
		_fc(e, "onBossDefeated")
		if _gp(e, "done", false):
			return
	elif _hasFn(e, "bossDefeated"):
		_fc(e, "bossDefeated")
		if _gp(e, "done", false):
			return
	elif _hasFn(e, "setStep"):
		_fc(e, "setStep", [6])
		if _gp(e, "done", false):
			return
	if not _gp(e, "done", false):
		_sp(e, "step", 6)
		_sp(e, "done", true)
		g.events.emit("egg:step", {"step": 6})
		g.events.emit("egg:complete", {})

# ---- ending beats (driven by ending.gd) ----------------------------------------------------------------------
# t = 0: he freezes, his screen shows the teary goodnight face, he waves.
func goodnight() -> void:
	if not built:
		return
	state = "defeated"
	_setLayers(Config.LAYERS.WORLD)
	for s in _shimmer:
		s.visible = false
	_hidden = false
	head.crack.visible = false
	_sparking = false
	_setFace("goodnight")
	_gesture = {"kind": "wave", "t": 0.0}
	_rt = _t
	root.visible = true
	head.group.visible = true
	head.group.scale = Vector3.ONE
	_play("boss_goodnight", {"pos": _screenWorld(), "vol": 1.1})

# k 0..1: his TV head collapses into a white line (k < 0.5), then a dot, then nothing. The glowing line/dot sit
# in the unscaled scene at the screen's world position (the head itself squashes flat under them).
func collapseHead(k: float) -> void:
	if not built:
		return
	var h := head
	var g = game
	if h._flash == null:
		var fl := meshNode(QuadMesh.new(), spriteMat(lineTexture(), linColor("#F6F1FF", 4.0), true, false, 5), "boss_collapse_line")
		fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		h._flash = fl
		h._dot = sprite(spriteMat(glowTexture(), linColor("#F6F1FF", 4.0)), "boss_collapse_dot")
	var f: MeshInstance3D = h._flash
	var d: MeshInstance3D = h._dot
	if f.get_parent() != g.scene:
		DAU.detach(f)
		DAU.detach(d)
		g.scene.add_child(f)
		g.scene.add_child(d)
	if h._collapseAt == null or k <= 0.02:
		h._collapseAt = _screenWorld()
	f.position = h._collapseAt
	d.position = h._collapseAt
	if g.camera != null:
		f.quaternion = g.camera.global_basis.get_rotation_quaternion()
	k = clampf(k, 0.0, 1.0)
	var W: float = h.W * HEAD_SCALE
	var fm: ShaderMaterial = f.material_override
	if k < 0.5:
		var u := k / 0.5
		h.group.scale = Vector3(1, maxf(0.02, 1.0 - easeInOut(u)), 1)
		h.group.visible = u < 0.9
		f.visible = true
		d.visible = false
		f.scale = Vector3(W * (1.0 + 0.1 * u), lerpf(1.2, 0.18, easeInOut(u)), 1)
		fm.set_shader_parameter("opacity", minf(1.0, u * 3.0))
	elif k < 1.0:
		var u := (k - 0.5) / 0.5
		h.group.visible = false
		f.visible = u < 0.85
		f.scale = Vector3(maxf(0.1, W * (1.0 - easeInOut(u))), 0.18, 1)
		d.visible = true
		var s := lerpf(0.6, 1.4, sin(u * PI))
		d.scale = Vector3(s, s, 1)
	else:
		h.group.visible = false
		f.visible = false
		d.visible = false

# Once the view has collapsed (t = 4 s): remove the model, reopen DY, restore the world. The boss stays `active`
# (rounds stay paused) until the ending calls finish().
func cleanupAfterEnding() -> void:
	if not head.is_empty():
		head.group.visible = true
		head.group.scale = Vector3.ONE
		head._collapseAt = null
		for k in ["_flash", "_dot"]:
			var o = head.get(k)
			if o != null:
				o.visible = false
				DAU.detach(o)
	end({"quiet": true, "keepEnding": true})

# The ending is over (Y or N): the fight is fully finished, rounds may run again.
func finish() -> void:
	end({"quiet": true})

# ============================================================================================ debug
func debugStart(o: Dictionary = {}):
	var g = game
	var teleport: bool = o.get("teleport", true)
	var skipIntro: bool = o.get("skipIntro", false)
	debug = true
	if g.machines != null and not _gp(g.machines, "powerOn", false):
		_fc(g.machines, "setPower", [true])
	var d = _path(g.level, ["doors", DY.id])
	if d != null and not _gp(d, "open", false):
		_fc(g.level, "openDoor", [DY.id, {"instant": true}])
	if teleport and g.player != null and _gp(g.player, "area") != "yard":
		_fc(g.player, "teleport", [45, -8.6, PI])
	var r = o.get("round")
	if r == null:
		r = _gp(g.rounds, "round")
	if r == null:
		r = 1
	var ok := start(r)
	if ok and skipIntro:
		_introT = INTRO.end - 1e-3
		_introFlags = {"swirl": true, "form": true, "laugh": true}
		root.visible = true
		tornado.group.scale = Vector3.ONE
	return debugState()

func debugPhase(n: int = 2):
	if not active:
		debugStart({"skipIntro": true})
	if not active:
		return debugState()
	if state == "intro":
		_introT = INTRO.end
		_updateIntro(0.0)
	n = clampi(n, 1, 3)
	_transT = 0.0
	_hop = null
	_restoreScale()
	root.visible = true
	hp = maxHp if n == 1 else (maxHp * (2.0 / 3.0) if n == 2 else maxHp / 3.0)
	_cracked = n >= 2
	head.crack.visible = n >= 2
	_sparking = n >= 3
	_drops[n - 1] = true
	_beginPhase(n)
	return debugState()

func debugKill() -> bool:
	if not active:
		return false
	if state == "intro":
		_introT = INTRO.end
		_updateIntro(0.0)
	if state != "fight":
		return false
	_transT = 0.0
	if phase < 3:
		debugPhase(3)
	hp = 1.0
	return damage(10.0, {"cause": "debug", "points": false, "hitmarker": false})

func debugHit(zone: String = "screen", amount: float = 100.0):
	if not _hittable():
		return null
	var h := head
	var point: Vector3
	if zone == "antenna":
		point = DAU.worldPos(h.tips[0])
	elif zone == "screen":
		point = _screenWorld()
	else:
		point = DAU.worldPos(J.chest)
	var before := hp
	damage(amount, {"zone": zone, "cause": "bullet", "point": point, "weaponId": "debug", "points": false})
	return {"zone": zone, "dealt": before - hp, "hp": hp}

func debugOffAir(on: bool = true):
	if phase != 3:
		debugPhase(3)
	_setOffAir(on)
	_updateOffAir(0.0001)
	return {"offAir": offAir, "layer": _layer}

func debugSweep() -> bool:
	if phase != 2:
		debugPhase(2)
	_hop = null
	_restoreScale()
	_stopSweep()
	_startSweep()
	return _sweep != null

func debugGrab() -> bool:
	if phase != 3:
		debugPhase(3)
	var pp := _playerPos()
	pos.x = pp.x + 1.2
	pos.z = pp.z - 1.2
	_grabCd = 0.0
	_grab = null
	return true

func debugState() -> Dictionary:
	var alive := 0
	for b in _balls:
		if b.alive:
			alive += 1
	return {
		"active": active, "state": state, "phase": phase, "hp": int(roundf(hp)), "maxHp": maxHp, "round": round,
		"pos": [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), snappedf(pos.z, 0.01)], "offAir": offAir, "hidden": _hidden, "adds": _adds.size(),
		"balls": alive, "sweep": _sweep.phase if _sweep != null else null, "grab": _grab.phase if _grab != null else null,
		"hop": _hop != null, "trans": snappedf(_transT, 0.01), "baked": char_ != null and _gp(char_, "skinnedMesh") != null, "face": head.get("faceMode"),
		"adapted": _adapted != null, "ending": {"active": ending.active, "t": snappedf(ending.t, 0.01), "stage": ending.stage} if ending != null else null,
	}
