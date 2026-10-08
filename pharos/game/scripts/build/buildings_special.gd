class_name BuildingsSpecial
extends Object
## Factory for building subclasses.

static func create(type: String) -> Building:
	match type:
		"tower":
			return TowerBuilding.new()
		"barracks":
			return BarracksBuilding.new()
		"pharos":
			return PharosBuilding.new()
		"wall":
			return WallBuilding.new()
		"dock":
			return DockBuilding.new()
	return Building.new()
