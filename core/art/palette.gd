class_name Palette
extends RefCounted
## Палитры placeholder-арта. Заменяются реальными PNG без изменений в коде.

const SETS := {
	"street": {
		"top": "#5b7fa6",
		"bottom": "#8f8577",
		"clutter": ["#6d6153", "#7b6c5b", "#55606b", "#8a7f6d", "#4e5a63"],
	},
	"facade": {
		"top": "#7d6a55",
		"bottom": "#4a4038",
		"clutter": ["#6a5946", "#8b7457", "#3f3831", "#7a6a52", "#574c40"],
	},
	"wood": {
		"top": "#8a6b41",
		"bottom": "#5a4227",
		"clutter": ["#7a5c36", "#9c7a4c", "#4b3720", "#6d5230", "#a98a5c"],
	},
	"door": {
		"top": "#4f4438",
		"bottom": "#2e2822",
		"clutter": ["#5c4d3d", "#3d342b", "#6b5943", "#463b30", "#2a241e"],
	},
	"bakery": {
		"top": "#c8a878",
		"bottom": "#8d6f4a",
		"clutter": ["#b08f60", "#d8bd93", "#7a5f3f", "#c2a170", "#9c7d52"],
	},
}

static func get_set(name: String) -> Dictionary:
	return SETS.get(name, SETS["street"])

static func top(name: String) -> Color:
	return Color.html(get_set(name)["top"])

static func bottom(name: String) -> Color:
	return Color.html(get_set(name)["bottom"])

static func clutter_color(name: String, index: int) -> Color:
	var list: Array = get_set(name)["clutter"]
	return Color.html(list[index % list.size()])
