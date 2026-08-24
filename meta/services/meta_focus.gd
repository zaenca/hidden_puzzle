class_name MetaFocus
extends RefCounted
## Куда вернуть игрока после уровня. Только строки — никаких ссылок на ноды,
## поэтому возврат «в конкретную meta action» переживает любую пересборку сцен.

var location: String = "shop"
var shop_id: String = ""
var task_id: String = ""
var action_id: String = ""
var hotspot: String = ""
var auto_open: bool = true
var narrative: PackedStringArray = PackedStringArray()

func is_empty() -> bool:
	return task_id.is_empty() and shop_id.is_empty()
