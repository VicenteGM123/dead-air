# Heroes (port of src/actors/heroes.js; ARCHITECTURE §10/§12, GDD §4): HEROES data + buildHero(). DEFAULT_HERO =
# 'duke' (GDD §4: default / first hero, preselected in character select and used by test=1).
#   HEROES = [{ id, name, role, rig, colors }] (GDD §4, rig spec overrides from the §4 table),
#   Heroes.buildHero(heroId, game = DAGame.inst) -> { group, rig, animator, parts: { head, torso, handL, handR },
#     slots: { head, handL, handR, footL, footR, back, wristL, wristR, neck, belt }, hairBounds, def, baked, art }
#     (a Dictionary; `art` is the CharRuntime.Character, face API in result.art.face).
# The sculpted SkinnedMesh character of scripts/art/char_runtime.gd is used (same engine rig + Animator, §12 slots);
# `baked` is true and the caller must NOT merge its joints (face attachments animate).
# Not ported (SPEC §0.2): the placeholder primitive heroes (the JS dev fallback when a baked character is missing or
# ?art=0) — every hero is baked. A missing asset is reported and buildHero returns null.
class_name Heroes
extends RefCounted

const DEFAULT_HERO := "duke"

const HEROES := [
	{"id": "skip", "name": "Skip Kowalski", "role": "Floor runner", "rig": {"height": 1.60, "headScale": 1.10, "shoulderW": 0.38, "hipW": 0.24, "legLen": 0.70},
		"colors": {"skin": "#F2BE98", "hair": "#6B3A1E", "top": "#2F5BD3", "sleeve": "#2F5BD3", "pants": "#B5703A", "shoes": "#2F5BD3", "iris": "#6B3A1E"}},
	{"id": "roxy", "name": "Roxy Rivers", "role": "Dance-show host", "rig": {"height": 1.70, "headScale": 1.05, "shoulderW": 0.40, "hipW": 0.27, "legLen": 0.80},
		"colors": {"skin": "#8A5A3C", "hair": "#3A2418", "top": "#F7F0E4", "sleeve": null, "pants": "#D8322B", "shoes": "#F6E7C8", "iris": "#4A2A18"}},
	{"id": "penny", "name": "Penny Watts", "role": "Broadcast engineer", "rig": {"height": 1.68, "headScale": 1.05, "shoulderW": 0.38, "hipW": 0.26, "legLen": 0.78},
		"colors": {"skin": "#F4C3A0", "hair": "#5A3320", "top": "#F0641E", "sleeve": "#F0641E", "pants": "#4A2A24", "shoes": "#F6E7C8", "iris": "#5A3320"}},
	{"id": "duke", "name": "Duke Dalton", "role": "Cop-show star", "rig": {"height": 1.80, "headScale": 1.00, "shoulderW": 0.46, "hipW": 0.27, "legLen": 0.82},
		"colors": {"skin": "#E9AE86", "hair": "#5A3320", "top": "#F07A1E", "sleeve": "#F07A1E", "pants": "#3A4FA0", "shoes": "#6B3A1E", "iris": "#3A2418"}},
]

const SLOT_NAMES := ["head", "handL", "handR", "footL", "footR", "back", "wristL", "wristR", "neck", "belt"]

# True when a sculpted/baked character is available for this id.
static func hasBakedHero(heroId: String, _game = null) -> bool:
	return CharRuntime.characterIds().has(heroId)

static func _heroDef(heroId) -> Dictionary:
	for h in HEROES:
		if h.id == heroId:
			return h
	for h in HEROES:
		if h.id == DEFAULT_HERO:
			return h
	return HEROES[0]

static func buildHero(heroId, game = null):
	if game == null:
		game = DAGame.inst
	var def := _heroDef(heroId)
	if not hasBakedHero(def.id, game):
		push_error("[heroes] '%s' is not baked (godot/assets/chars/%s.glb missing)" % [def.id, def.id])
		return null
	return buildBakedHero(def, game)

# Sculpted character from scripts/art (CharRuntime.buildCharacter) mapped onto the buildHero contract.
static func buildBakedHero(def: Dictionary, game):
	var M = game.mats if game != null else null
	# JS: merge: true (draw-call merging, not ported); envMap / globals: the shared env map + global uniforms.
	var c = CharRuntime.buildCharacter(def.id, {"envMap": M.get("envMap") if M != null else null, "globals": true, "heroFade": true, "merge": true})
	if c == null:
		return null
	var J: Dictionary = c.rig.joints
	var D: Dictionary = c.rig.dims
	var missing := SLOT_NAMES.filter(func(k): return c.slots == null or not c.slots.has(k))
	if not missing.is_empty():
		push_error("charRuntime result lacks slots %s" % ", ".join(PackedStringArray(missing)))
		return null
	if c.animator == null:
		push_error("charRuntime result lacks an animator")
		return null
	# parts.head = head centre (hit tests, look-at, head costumes); torso = the chest joint.
	var head := DAU.node3d("part:headCenter")
	head.position = Vector3(0, float(D.headH) * 0.5, 0)
	J.head.add_child(head)
	c.group.name = "hero:%s" % def.id
	return {
		"group": c.group, "rig": c.rig, "animator": c.animator,
		"parts": {"head": head, "torso": J.chest, "handL": J.handL, "handR": J.handR},
		"slots": c.slots, "hairBounds": c.hairBounds, "def": def, "baked": true, "art": c,
	}
