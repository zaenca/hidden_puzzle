class_name LevelResult
extends RefCounted
## Единственное, что уровень отдаёт наружу. Уровень НЕ вызывает мету, НЕ трогает
## кошелёк и НЕ знает про пекарню — он возвращает данные.

var level_id: String = ""
var task_id: String = ""
var success: bool = false
var replay: bool = false
var quest_items: PackedStringArray = PackedStringArray()
var soft_currency: int = 0
var xp: int = 0
var boosters_spent: Dictionary = {}
var stats: Dictionary = {}
