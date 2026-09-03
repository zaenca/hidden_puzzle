class_name GameplayRegistry
extends RefCounted
## Режим геймплея → сцена, которая его играет. Новый режим — новая строка
## здесь и поле `mode` в JSON уровня; ни Game, ни мета об этом не узнают.

const MODES := {
	"sort": "res://core/sort/sort_module.tscn",
	## Гибрид «пазл → поиск → уборка». Новый контент его не использует, но
	## уровни, написанные под него, обязаны остаться играбельными.
	"legacy": "res://core/level/hybrid_level.tscn",
}


static func create(mode: String) -> Node:
	var path: String = String(MODES.get(mode, ""))
	if path.is_empty():
		push_error("GameplayRegistry: неизвестный режим '%s'" % mode)
		return null
	var packed: PackedScene = load(path)
	if packed == null:
		push_error("GameplayRegistry: не загрузилась сцена %s" % path)
		return null
	return packed.instantiate()


static func is_known(mode: String) -> bool:
	return MODES.has(mode)
