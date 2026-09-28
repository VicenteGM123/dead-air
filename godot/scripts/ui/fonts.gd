# Bundled fonts (GDD §14): Titan One (HUD digits, prompt tape), VT323 (ammo counter), Shrikhand (chyron, logo,
# title), Bungee (in-world signage/posters). Port of src/ui/fonts.js.
# The JS inlined the .woff2 files and registered them with document.fonts; here they are the imported FontFile
# resources res://assets/fonts/*.woff. loadFonts() loads them (synchronously, cached) and returns the FontFile list.
# FONTS keeps the CSS family lists of the JS (other ports build canvas font strings from them:
# "92px " + DAFonts.FONTS.tape); family(css) resolves such a CSS family list (or a whole CSS font shorthand such as
# 'bold 48px "Titan One", sans-serif') to a Godot Font, parseFont(css) returns { font, size, weight, style }.
# Generic / system names in the lists (Arial Black, Courier New, Georgia, sans-serif…) fall back to a SystemFont.
class_name DAFonts
extends RefCounted

const FONTS := {
	"hud": '"Titan One", "Arial Black", sans-serif',
	"tape": '"VT323", "Courier New", monospace',
	"logo": '"Shrikhand", "Georgia", serif',
	"sign": '"Bungee", "Arial Black", sans-serif',
}

const SOURCES := [
	["Shrikhand", "res://assets/fonts/Shrikhand.woff"],
	["Titan One", "res://assets/fonts/TitanOne.woff"],
	["VT323", "res://assets/fonts/VT323.woff"],
	["Bungee", "res://assets/fonts/Bungee.woff"],
]

static var _loaded: Dictionary = {}      # lower-case family -> FontFile
static var _system: Dictionary = {}      # lower-case css family list -> Font (fallback chain)
static var _loading := false

# Loads (once) every bundled face. Returns the FontFile list in SOURCES order.
static func loadFonts() -> Array:
	if not _loading:
		_loading = true
		for s in SOURCES:
			var f = load(s[1]) if ResourceLoader.exists(s[1]) else null
			if f == null:
				push_warning("[fonts] missing %s" % s[1])
				continue
			_loaded[String(s[0]).to_lower()] = f
	var out: Array = []
	for s in SOURCES:
		if _loaded.has(String(s[0]).to_lower()):
			out.append(_loaded[String(s[0]).to_lower()])
	return out

# Splits a CSS family list ('"Titan One", "Arial Black", sans-serif') into bare names.
static func families(css: String) -> PackedStringArray:
	var out := PackedStringArray()
	for part in css.split(","):
		var n := part.strip_edges().trim_prefix('"').trim_suffix('"').trim_prefix("'").trim_suffix("'").strip_edges()
		if n != "":
			out.append(n)
	return out

# Font for a CSS family list (or a FONTS key: 'hud' | 'tape' | 'logo' | 'sign'). The first bundled family wins;
# otherwise a SystemFont over the listed names (generic families map to Godot's defaults).
static func family(css: String) -> Font:
	loadFonts()
	if FONTS.has(css):
		css = FONTS[css]
	var names := families(css)
	for n in names:
		var k := n.to_lower()
		if _loaded.has(k):
			return _loaded[k]
	var key := css.to_lower()
	if _system.has(key):
		return _system[key]
	var sf := SystemFont.new()
	var sys := PackedStringArray()
	for n in names:
		match n.to_lower():
			"sans-serif", "serif", "monospace", "cursive", "fantasy":
				sys.append(n.to_lower())
			_:
				sys.append(n)
	sf.font_names = sys
	_system[key] = sf
	return sf

# Parses a CSS font shorthand ('[italic] [bold|700] 48px <family list>') -> { font, size, weight, style, family }.
static func parseFont(css: String) -> Dictionary:
	var out := {"font": null, "size": 10.0, "weight": 400, "style": "normal", "family": ""}
	var s := css.strip_edges()
	var re := RegEx.new()
	re.compile("(\\d+(?:\\.\\d+)?)px")
	var m := re.search(s)
	var fam := s
	if m != null:
		out.size = float(m.get_string(1))
		var head := s.substr(0, m.get_start())
		fam = s.substr(m.get_end()).strip_edges()
		if fam.begins_with("/"):          # line-height: "48px/1.2 Family"
			var sp := fam.find(" ")
			fam = fam.substr(sp + 1) if sp >= 0 else ""
		for w in head.split(" ", false):
			var lw := w.to_lower()
			if lw == "bold" or lw == "bolder":
				out.weight = 700
			elif lw.is_valid_int():
				out.weight = int(lw)
			elif lw == "italic" or lw == "oblique":
				out.style = lw
	out.family = fam
	out.font = family(fam)
	return out
