extends Node
## Реестр контента. Индекс уровней лёгкий (id → путь), сами определения
## грузятся лениво — так каталог из 1000+ уровней не тянет 1000 фонов в память.

const CONTENT_ROOT := "res://content/"
const LEVEL_CACHE_LIMIT := 3

var items: Dictionary = {}        ## id -> ItemDefinition
var shops: Dictionary = {}        ## id -> ShopDefinition
var tasks: Dictionary = {}        ## id -> MetaTaskDefinition
var actions: Dictionary = {}      ## id -> MetaActionDefinition
var level_index: Dictionary = {}  ## id -> {path, shop_id, task_id, order}
var level_ids: PackedStringArray = PackedStringArray()
var map_data: Dictionary = {}

var loaded: bool = false

var _level_cache: Dictionary = {}
var _cache_order: Array[String] = []


func load_all() -> void:
	if loaded:
		return
	items.clear()
	shops.clear()
	tasks.clear()
	actions.clear()
	level_index.clear()

	for raw in _array(CONTENT_ROOT + "items.json"):
		var it := ContentParser.item(raw)
		items[it.id] = it

	for raw in _array(CONTENT_ROOT + "tasks.json"):
		var t := ContentParser.task(raw)
		tasks[t.id] = t

	for raw in _array(CONTENT_ROOT + "actions.json"):
		var a := ContentParser.action(raw)
		actions[a.id] = a

	var index = ContentParser.read_json(CONTENT_ROOT + "level_index.json")
	if index is Array:
		var ids := PackedStringArray()
		for entry in index:
			var id := String(entry.get("id", ""))
			level_index[id] = entry
			ids.append(id)
		level_ids = ids

	var map = ContentParser.read_json(CONTENT_ROOT + "map.json")
	if map is Dictionary:
		map_data = map
		for shop_file in map.get("shops", []):
			var d = ContentParser.read_json(CONTENT_ROOT + String(shop_file))
			if d is Dictionary:
				var s := ContentParser.shop(d)
				shops[s.id] = s

	loaded = true


func level(id: String) -> LevelDefinition:
	if _level_cache.has(id):
		return _level_cache[id]
	if not level_index.has(id):
		push_error("ContentDB: неизвестный уровень %s" % id)
		return null
	var d = ContentParser.read_json(String(level_index[id].get("path", "")))
	if not (d is Dictionary):
		return null
	var def := ContentParser.level(d)
	_cache(id, def)
	return def


func item(id: String) -> ItemDefinition:
	return items.get(id)


func task(id: String) -> MetaTaskDefinition:
	return tasks.get(id)


func action(id: String) -> MetaActionDefinition:
	return actions.get(id)


func shop(id: String) -> ShopDefinition:
	return shops.get(id)


func tasks_for_shop(shop_id: String) -> Array[MetaTaskDefinition]:
	var out: Array[MetaTaskDefinition] = []
	for t in tasks.values():
		if t.shop_id == shop_id:
			out.append(t)
	out.sort_custom(func(a, b): return _task_order(a) < _task_order(b))
	return out


func item_name(id: String) -> String:
	var it: ItemDefinition = items.get(id)
	return it.display_name if it != null else id


func _task_order(t: MetaTaskDefinition) -> int:
	if t.level_ids.is_empty():
		return 9999
	var entry = level_index.get(t.level_ids[0], {})
	return int(entry.get("order", 9999))


func _array(path: String) -> Array:
	var d = ContentParser.read_json(path)
	return d if d is Array else []


func _cache(id: String, def: LevelDefinition) -> void:
	_level_cache[id] = def
	_cache_order.append(id)
	while _cache_order.size() > LEVEL_CACHE_LIMIT:
		var oldest: String = _cache_order.pop_front()
		_level_cache.erase(oldest)
