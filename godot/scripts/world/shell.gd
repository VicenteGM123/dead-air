# Building shell physics: registers every collider the architecture implies (ground, walls, fence, platforms,
# stairs, ramps, bleacher rails, door blockers, player-only window/gate blockers, tower base). Pure data ->
# Collision, no meshes, so level.gd and any test build the exact same physical station. (Port of src/world/shell.js.)
#
# Tags: floor, wall, glass, fence, platform, rail, door (id = door id, toggled by level.openDoor),
#       window (id = window id: invisible player-only blocker, ignored by shots and the camera), lattice.
#
# Usage: const Shell = preload("res://scripts/world/shell.gd"); Shell.addShellColliders(col);
#        Shell.segmentBox(seg, half, extend) -> [min:[x,y,z], max:[x,y,z]] (arrays, like the JS)
# Collision API used (collision.gd, the JS names): col.addBox(min:[x,y,z], max:[x,y,z], {tag, id}),
# col.addRamp(rect:[x0,z0,x1,z1], y0, y1, inset, {tag, id}).
extends RefCounted

const FENCE_T := 0.2
const GROUND := [[-80.0, -1.0, -90.0], [130.0, 0.0, 70.0]]
const TOWER_BLOCK_H := 3.0

static func H() -> float:
	return Layout.WALL_T / 2.0

# Axis-aligned box of a wall segment: `half` across the line, optionally extended along it at non-jamb ends.
static func segmentBox(seg: Array, half: float = -1.0, extend: float = 0.0) -> Array:
	if half < 0.0:
		half = H()
	var x0: float = seg[0]
	var z0: float = seg[1]
	var x1: float = seg[2]
	var z1: float = seg[3]
	var y0: float = seg[4]
	var y1: float = seg[5]
	var meta = seg[7] if seg.size() > 7 else null
	var alongX := z0 == z1
	var e0 := 0.0 if meta and meta.jambs[0] else extend
	var e1 := 0.0 if meta and meta.jambs[1] else extend
	if alongX:
		var a := minf(x0, x1) - e0
		var b := maxf(x0, x1) + e1
		return [[a, y0, z0 - half], [b, y1, z0 + half]]
	var a2 := minf(z0, z1) - e0
	var b2 := maxf(z0, z1) + e1
	return [[x0 - half, y0, a2], [x0 + half, y1, b2]]

static func addShellColliders(col) -> void:
	var h := H()
	col.addBox(GROUND[0], GROUND[1], {"tag": "floor", "id": "ground"})

	for seg in Layout.WALLS:
		var kind: String = seg[6]
		var bx := segmentBox(seg, FENCE_T / 2.0 if kind == "fence" else h, 0.0 if kind == "fence" else h)
		col.addBox(bx[0], bx[1], {"tag": "wall" if kind == "solid" else kind})

	for p in Layout.PLATFORMS:
		var r: Array = p.rect
		if p.ramp > 0:
			col.addRamp(p.rect, 0.0, p.top, p.ramp, {"tag": "platform", "id": p.id})
		else:
			col.addBox([r[0], 0.0, r[1]], [r[2], p.top, r[3]], {"tag": "platform", "id": p.id})

	for b in Layout.BLOCKERS:
		var r: Array = b.rect
		col.addBox([r[0], b.y0, r[1]], [r[2], b.y1, r[3]], {"tag": b.tag, "id": b.id})

	for d in Layout.DOORS:
		var r: Array = d.rect
		col.addBox([r[0], d.y0, r[1]], [r[2], d.y1, r[3]], {"tag": "door", "id": d.id})

	# Boarded windows and the gate: fill the opening. Fence climbs need nothing (the fence is continuous).
	for w in Layout.WINDOWS:
		if w.type == "fence":
			continue
		var axis: String = w.line[0]
		var at: float = w.line[1]
		var t := FENCE_T / 2.0 if w.type == "gate" else h
		var a: float = w.span[0]
		var b: float = w.span[1]
		var mn := [a, w.sill, at - t] if axis == "z" else [at - t, w.sill, a]
		var mx := [b, w.top, at + t] if axis == "z" else [at + t, w.top, b]
		col.addBox(mn, mx, {"tag": "window", "id": w.id})

	var tr: Array = Layout.ANCHORS.tower_base.rect
	col.addBox([tr[0], 0.0, tr[1]], [tr[2], TOWER_BLOCK_H, tr[3]], {"tag": "lattice", "id": "tower_base"})
