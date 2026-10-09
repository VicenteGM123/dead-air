class_name Pal
## The game's palette (inherited from PHAROS' "Diorama del Egeo"; the toon shaders saturate it into the Wind Waker
## look). Every model and UI element takes its colours from here so the whole game stays consistent. Values are
## sRGB, as authored. The NYX_* tones are PHAROS leftovers kept for the copied UI kit and materials.

const MARBLE := Color("F3EFE6")
const MARBLE_SHADE := Color("DCD5C6")
const LIMESTONE := Color("E3D3B4")
const LIMESTONE_DARK := Color("C9B793")
const SAND := Color("EED9A8")
const SAND_WET := Color("D6BC8C")
const TERRACOTTA := Color("C2643F")
const TERRACOTTA_DARK := Color("9E4A2F")
const AEGEAN := Color("2E6FB0")
const AEGEAN_LIGHT := Color("4B8FD0")
const GRASS_LIGHT := Color("B2C177")
const GRASS := Color("9AAE62")
const GRASS_DARK := Color("7F9654")
const GRASS_DRY := Color("CDBB7C")
const OLIVE_LEAF := Color("8E9E68")
const OLIVE_LEAF_DARK := Color("6F7F52")
const CYPRESS := Color("3F5E3B")
const CYPRESS_DARK := Color("2F4A2E")
const PINE := Color("557A45")
const ROCK := Color("B7A792")
const ROCK_DARK := Color("8E7F6C")
const PATH := Color("D2B183")
const PATH_DARK := Color("BE9C70")
const WOOD := Color("8A5A3B")
const WOOD_LIGHT := Color("A8754C")
const WOOD_DARK := Color("5E3D29")
const BRONZE := Color("C9923F")
const BRONZE_DARK := Color("94662B")
const CREST := Color("B8322C")
const CLOTH := Color("EFE7D6")
const CLOTH_RED := Color("A83A32")
const SKIN_SHADOW := Color("2A2430")
const BOUGAINVILLEA := Color("E05A9A")
const LAVENDER := Color("9A7FD1")
const POPPY := Color("E04A3A")
const DAISY := Color("F6F1DE")
const GOLD := Color("F2C14E")
const GOLD_DARK := Color("C99A2E")
const WINDOW := Color(0.16, 0.19, 0.27, 0.0) # alpha 0 = night-glowing window
const FIRE := Color(1.0, 0.70, 0.35, 0.5) # alpha 0.5 = self-lit
const FIRE_CORE := Color(1.0, 0.90, 0.62, 0.5)

const NYX_BODY := Color("241B45")
const NYX_BODY_LIGHT := Color("3A2A66")
const NYX_CLOTH := Color("2C2352")
const NYX_GLOW := Color(0.49, 0.96, 1.0, 0.5)
const KER_GLOW := Color(1.0, 0.36, 0.48, 0.5)
const BOSS_GLOW := Color(0.69, 0.49, 1.0, 0.5)

# UI
const UI_TEXT := Color("F7F1E3")
const UI_DIM := Color(0.97, 0.94, 0.89, 0.62)
const UI_GOLD := Color("E9C46A")
const UI_PANEL := Color(0.08, 0.075, 0.12, 0.62)
const UI_DANGER := Color("E86A5A")
const UI_GOOD := Color("9BD88A")
const UI_NYX := Color("7CF6FF")


static func lin(c: Color) -> Vector3:
	var l := c.srgb_to_linear()
	return Vector3(l.r, l.g, l.b)


static func glow(c: Color) -> Color:
	return Color(c.r, c.g, c.b, 0.5)
