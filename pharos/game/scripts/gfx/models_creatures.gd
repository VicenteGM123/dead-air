class_name ModelsCreatures
## Factory for the creatures of Nyx (rigs). PLACEHOLDER variants of the shade until the bestiary pass lands.

static func make(type: String) -> Rig:
	var r := RigShade.new()
	match type:
		"ker":
			r.glow = Pal.KER_GLOW
			r.size = 0.7
		"shielded":
			r.size = 1.15
		"archer":
			r.glow = Color(0.7, 1.0, 0.8, 0.5)
		"cyclops":
			r.size = 2.3
		"hydra":
			r.glow = Pal.BOSS_GLOW
			r.size = 3.5
	return r
