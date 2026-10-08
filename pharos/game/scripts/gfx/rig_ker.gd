class_name RigKer
extends Rig
## Ker: a small, swift death-spirit of Nyx. A comet of night sky — round hooded head, a teardrop body that runs out
## into a long thin tail ending in a little diamond fin — carried by two swept sickle wings that beat fast. Two
## crimson almond eyes in the dark of the hood. Gameplay hovers it ~2.2 m up; the rig dives to strike.
## Parts: shape, tail, wing_l, wing_r (+ one eye halo) = 5 draw calls.

const BODY_LOW := Color("0D0820")
const BODY_HIGH := Color("35205E")
const WING_ROOT := Color("2A1A50")
const WING_TIP := Color("4A2C78")
const EDGE := Color(0.4, 0.15, 0.27, 0.5) # faint self-lit crimson leading edge
const HALO_I := 0.26
## Overall scale: small next to the Sombra, but big enough to read from the gameplay camera 30 m away.
const SIZE := 1.25
const HOOD_RING := 8
## Body lathe (radius, along, z offset): built with scale (1, 0.88, 1) then turned so +along is forward (-Z).
const BODY_PROF := [
	Vector3(0.012, -0.32, 0.02), Vector3(0.04, -0.26, 0.015), Vector3(0.075, -0.17, 0.008),
	Vector3(0.11, -0.07, 0.0), Vector3(0.135, 0.02, 0.0), Vector3(0.145, 0.09, 0.005),
	Vector3(0.136, 0.15, 0.01), Vector3(0.112, 0.205, 0.018), Vector3(0.088, 0.243, 0.024),
	Vector3(0.07, 0.238, 0.02), Vector3(0.045, 0.222, 0.016), Vector3(0.0, 0.214, 0.014),
]

var glow := Pal.KER_GLOW
var rim := Color("D77CC6")

var _body: Node3D
var _tail: Node3D
var _wing_l: Node3D
var _wing_r: Node3D
var _halo: MeshInstance3D
var _sway := 0.0
var _phase := 0.0
var _seed := 0.0


func _ready() -> void:
	_seed = randf() * TAU
	_phase = randf() * TAU
	var mat := Materials.nyx_sky(rim)
	_body = add_part("body", null, "", Vector3(0, 0.25, 0))
	add_part("shape", ModelsCreatures.cached("ker_body", _mesh_body), "body", Vector3.ZERO, true, mat)
	_tail = add_part("tail", ModelsCreatures.cached("ker_tail", _mesh_tail), "body", Vector3(0, 0.018, 0.29), false, mat)
	_wing_l = add_part("wing_l", ModelsCreatures.cached("ker_wing_l", _mesh_wing.bind(-1.0)), "body", Vector3(-0.07, 0.075, -0.03), false, mat)
	_wing_r = add_part("wing_r", ModelsCreatures.cached("ker_wing_r", _mesh_wing.bind(1.0)), "body", Vector3(0.07, 0.075, -0.03), false, mat)
	_halo = add_glow("body", Vector3(0, 0.03, -0.24), Color(glow.r, glow.g, glow.b), 0.26, HALO_I)
	scale = Vector3.ONE * SIZE


func set_dissolve(v: float) -> void:
	super(v)
	if _halo:
		Materials.set_param(_halo, &"intensity", HALO_I * (1.0 - v) * (1.0 - v))


# --- meshes ------------------------------------------------------------------------------------------------

func _body_color(c: Vector3, ring: int, _side: int) -> Color:
	# Lathe space: c.y runs along the body (front > 0), c.z is up. Rings past the hood lip are the dark face.
	if ring >= HOOD_RING:
		return ModelsCreatures.VOID
	var up := clampf(c.z / 0.14 * 0.5 + 0.5, 0.0, 1.0)
	var col := BODY_LOW.lerp(BODY_HIGH, up * up)
	if ring == HOOD_RING - 1:
		col = col.lightened(0.1)
	return col


func _mesh_body() -> Mesh:
	var mb := MeshBuilder.new(41)
	mb.push(Transform3D(Basis.from_scale(Vector3(1.0, 0.88, 1.0)), Vector3.ZERO))
	mb.push(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3.ZERO))
	# Teardrop from the tail joint to the hood lip, then a recessed dish: the dark opening of the hood.
	mb.lathe(BODY_PROF, 10, _body_color, PI / 10.0)
	mb.pop()
	mb.pop()
	# Hood tip sweeping back from the crown, like the Sombra's.
	mb.tube([Vector3(0, 0.075, -0.15), Vector3(0, 0.125, -0.06), Vector3(0, 0.16, 0.05), Vector3(0, 0.17, 0.16), Vector3(0, 0.155, 0.27)], 0.075, 0.0, 6,
		func(k: float) -> Color: return BODY_HIGH.lerp(BODY_LOW, k * 0.6))
	# Two hooked talons tucked under the chest.
	for sx in [-1.0, 1.0]:
		mb.tube([Vector3(0.045 * sx, -0.07, -0.05), Vector3(0.055 * sx, -0.15, -0.08), Vector3(0.05 * sx, -0.19, -0.15), Vector3(0.04 * sx, -0.18, -0.2)], 0.022, 0.0, 4,
			func(k: float) -> Color: return BODY_HIGH.lerp(Color("6A4A9A"), k))
	# Slanted crimson eyes in the dark of the hood.
	for sx in [-1.0, 1.0]:
		ModelsCreatures.eye(mb, Vector3(0.043 * sx, 0.026, -0.219), 0.028, sx, 0.3, glow, 0.45, -0.4 * sx)
	return mb.commit()


func _mesh_tail() -> Mesh:
	var mb := MeshBuilder.new(43)
	var pts := [Vector3(0, 0, -0.02), Vector3(0, 0.006, 0.14), Vector3(0, 0.0, 0.28), Vector3(0, -0.02, 0.42), Vector3(0, -0.026, 0.56), Vector3(0, -0.012, 0.67)]
	mb.tube(pts, 0.032, 0.006, 5, func(k: float) -> Color: return BODY_LOW.lerp(BODY_HIGH, 0.4 + k * 0.4), false)
	# Diamond fin at the tip.
	var c := Vector3(0, -0.01, 0.74)
	mb.plate([Vector3(0, -0.012, 0.64), Vector3(0.065, -0.008, 0.73), Vector3(0, -0.006, 0.86), Vector3(-0.065, -0.008, 0.73)], WING_TIP)
	mb.plate([c + Vector3(0, -0.002, -0.07), c + Vector3(0, 0.05, 0.0), c + Vector3(0, 0.0, 0.1), c + Vector3(0, -0.04, 0.0)], WING_ROOT)
	return mb.commit()


func _mesh_wing(side: float) -> Mesh:
	var mb := MeshBuilder.new(45)
	var s := side
	# Sickle wing: leading edge, a line just behind it (for the lit edge band) and the trailing edge, root -> tip.
	var lead := [Vector3(0.0, 0.0, -0.05), Vector3(0.16 * s, 0.025, -0.075), Vector3(0.34 * s, 0.045, -0.045), Vector3(0.52 * s, 0.06, 0.04), Vector3(0.66 * s, 0.066, 0.17), Vector3(0.78 * s, 0.062, 0.35)]
	var band := [Vector3(0.0, 0.0, -0.025), Vector3(0.16 * s, 0.025, -0.05), Vector3(0.34 * s, 0.045, -0.022), Vector3(0.51 * s, 0.06, 0.06), Vector3(0.645 * s, 0.065, 0.185), Vector3(0.78 * s, 0.062, 0.35)]
	var trail := [Vector3(0.01 * s, 0.0, 0.085), Vector3(0.14 * s, 0.02, 0.13), Vector3(0.3 * s, 0.035, 0.11), Vector3(0.45 * s, 0.05, 0.15), Vector3(0.6 * s, 0.06, 0.25), Vector3(0.78 * s, 0.062, 0.35)]
	ModelsCreatures.strip(mb, lead, band, func(k: float, _e: float) -> Color: return EDGE if k > 0.15 else WING_ROOT)
	ModelsCreatures.strip(mb, band, trail, func(k: float, _e: float) -> Color: return WING_ROOT.lerp(WING_TIP, k))
	return mb.commit()


# --- animation ---------------------------------------------------------------------------------------------

func _action_length(a: String) -> float:
	match a:
		"attack":
			return 0.7
		"hit":
			return 0.25
		"death":
			return 0.8
		"spawn":
			return 1.0
	return 0.4


func _animate(delta: float) -> void:
	var mv := clampf(speed / speed_max, 0.0, 1.0)
	_sway = lerpf(_sway, mv, 1.0 - exp(-delta * 3.0))
	# Wing beat: fast, with short glides while travelling.
	var glide := smooth(sin(t * 0.9 + _seed) * 1.8 - 0.8) * _sway
	var freq := lerpf(3.0, 4.4, _sway) * (1.0 - 0.7 * glide)
	_phase = fmod(_phase + delta * freq * TAU, TAU)
	var s := sin(_phase)
	var amp := lerpf(0.8, 0.12, glide)
	var flap := s * amp
	var sweep := cos(_phase) * 0.18 * amp
	var lift := -cos(_phase) * 0.035 * amp
	var pos := Vector3(0, 0.25 + lift + sin(t * 1.3 + _seed) * 0.05, 0)
	var rot := Vector3(-0.2 * _sway + sin(t * 1.1) * 0.05, sin(t * 0.7 + _seed) * 0.1, sin(t * 1.6) * 0.09 * (1.0 - _sway * 0.5))
	var dihedral := 0.1 + glide * 0.12
	var tail_x := sin(_phase - 1.3) * 0.12 * amp + 0.06
	var tail_y := sin(t * 2.3 + _seed) * 0.28
	if action != "":
		var p := ap()
		match action:
			"attack":
				# Rise and rear with the wings up (0-.38), plunge with folded wings (.38-.6), rake with the talons,
				# then beat back up (high strokes, clear of the ground) settling into the normal beat (no pop at the end).
				var a := smooth(p / 0.38)
				var d := smooth((p - 0.38) / 0.22)
				var r := smooth((p - 0.62) / 0.38)
				var dive := d * (1.0 - r)
				pos += Vector3(0, 0.35 * a * (1.0 - d) - 1.0 * dive, 0.22 * a * (1.0 - d) - 0.7 * dive)
				rot.x += 0.45 * a * (1.0 - d) - 0.95 * d * (1.0 - smooth((p - 0.54) / 0.1)) + 0.55 * smooth((p - 0.54) / 0.1) * (1.0 - r)
				var fold := smooth((p - 0.3) / 0.12) * (1.0 - smooth((p - 0.58) / 0.08))
				var climb := smooth((p - 0.58) / 0.08)
				var hold := a * (1.0 - climb)
				flap = lerpf(flap + 0.4 * climb * (1.0 - r), lerpf(1.1, 0.35, fold), hold)
				sweep = lerpf(sweep, lerpf(-0.35, -0.7, fold), hold)
				# The tail trails the plunge, then lifts as the body rears to rake (it would hang into the ground).
				var rake := smooth((p - 0.54) / 0.1)
				tail_x += 0.5 * dive * (1.0 - rake) - 0.35 * rake * (1.0 - r)
				_mark("impact", 0.42)
			"hit":
				var k := sin(p * PI)
				pos += Vector3(0, 0.15 * k, 0.3 * k)
				rot.x += 0.6 * k
				rot.z += 0.4 * k
				flap = lerpf(flap, -0.6, k)
			"death":
				var e := ease_in(p)
				pos += Vector3(0, -1.35 * e, 0.3 * p)
				rot += Vector3(-1.4 * p, 0.0, 5.0 * e)
				flap = lerpf(flap, 1.25, smooth(p * 3.0)) + sin(p * 40.0) * 0.15 * (1.0 - p)
				sweep = lerpf(sweep, -0.6, p)
				_body.scale = Vector3.ONE * (1.0 - 0.35 * p)
			"spawn":
				var e := smooth(p)
				pos.y -= (1.0 - e) * 1.1
				rot.x += 0.9 * (1.0 - e)
				flap = lerpf(1.1, flap, smooth((p - 0.35) / 0.5))
				sweep = lerpf(-0.5, sweep, smooth((p - 0.35) / 0.5))
	if action != "death":
		_body.scale = Vector3.ONE
	_body.position = pos
	_body.rotation = rot
	_wing_r.rotation = Vector3(0.0, sweep, dihedral + flap)
	_wing_l.rotation = Vector3(0.0, -sweep, -(dihedral + flap))
	_tail.rotation = Vector3(tail_x, tail_y, 0.0)
