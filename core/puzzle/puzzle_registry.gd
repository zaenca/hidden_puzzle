class_name PuzzleRegistry
extends RefCounted
## Подключение новой puzzle-механики = новая сцена + одна строка здесь.

const MODULES := {
	"jigsaw": "res://core/puzzle/jigsaw/jigsaw_module.tscn",
}

static func create(module_id: String) -> PuzzleModule:
	var path: String = String(MODULES.get(module_id, ""))
	if path.is_empty():
		push_error("PuzzleRegistry: неизвестный модуль '%s'" % module_id)
		return null
	var packed: PackedScene = load(path)
	if packed == null:
		push_error("PuzzleRegistry: не загрузилась сцена %s" % path)
		return null
	return packed.instantiate()

static func is_known(module_id: String) -> bool:
	return MODULES.has(module_id)
