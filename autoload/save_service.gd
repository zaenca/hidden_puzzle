extends Node
## Локальное сохранение. JSON, а не Resource: прозрачно, мигрируемо, не
## исполняет код при загрузке пользовательского файла и не ломается при
## переименовании классов.
##
## Запись атомарная: tmp → бэкап старого → замена. Прерывание записи не
## разрушает предыдущий сейв.

const SAVE_PATH := "user://save.json"
const BACKUP_PATH := "user://save.bak"
const TMP_PATH := "user://save.tmp"
const CURRENT_VERSION := 3

## version -> имя метода миграции.
const MIGRATIONS := {1: "_migrate_1_to_2", 2: "_migrate_2_to_3"}

## Всё, что осталось от старой цепочки «пазл района → зал → ключ → кладовая».
## Флаги и уровни, которых больше нет в контенте, надо снимать явно: задача
## пересчитывается от состояния мира, и оставшийся `hall_clean` открыл бы
## игроку задачу, которой в игре уже нет.
const V1_DEAD_FLAGS := ["bakery_chosen", "bakery_visited", "hall_clean", "door_open",
	"bakery_key_found", "storeroom_ready", "storeroom_clean", "shelf_checked"]
const V1_DEAD_LEVELS := ["bakery_01", "bakery_02", "bakery_03", "bakery_04", "bakery_05",
	"storeroom_01", "storeroom_02"]

var recovered_from_backup: bool = false
var started_fresh: bool = false

var _providers: Dictionary = {}   ## key -> объект с save_data()/load_data()
var _order: Array[String] = []


func register(key: String, provider: Object) -> void:
	if not _providers.has(key):
		_order.append(key)
	_providers[key] = provider


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save_game() -> bool:
	var data := {
		"version": CURRENT_VERSION,
		"saved_at": TimeService.now(),
	}
	for key in _order:
		var p: Object = _providers[key]
		if p != null and p.has_method("save_data"):
			data[key] = p.save_data()

	var f := FileAccess.open(TMP_PATH, FileAccess.WRITE)
	if f == null:
		push_error("SaveService: не удалось открыть %s" % TMP_PATH)
		return false
	f.store_string(JSON.stringify(data, "  "))
	f.close()

	var dir := DirAccess.open("user://")
	if dir == null:
		return false
	if dir.file_exists("save.json"):
		dir.remove("save.bak")
		dir.copy(SAVE_PATH, BACKUP_PATH)
		dir.remove("save.json")
	dir.rename("save.tmp", "save.json")
	return true


func load_game() -> bool:
	recovered_from_backup = false
	started_fresh = false

	var data := _read(SAVE_PATH)
	if data.is_empty():
		data = _read(BACKUP_PATH)
		if not data.is_empty():
			recovered_from_backup = true
			push_warning("SaveService: основной сейв повреждён, восстановлено из .bak")

	if data.is_empty():
		started_fresh = true
		return false

	data = _migrate(data)
	for key in _order:
		var p: Object = _providers[key]
		if p != null and p.has_method("load_data") and data.has(key):
			p.load_data(data[key])
	return true


func wipe() -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	for f in ["save.json", "save.bak", "save.tmp"]:
		if dir.file_exists(f):
			dir.remove(f)


func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	if json.parse(text) != OK:
		push_warning("SaveService: битый JSON в %s" % path)
		return {}
	var d = json.data
	if not (d is Dictionary) or not d.has("version"):
		push_warning("SaveService: неожиданная структура сейва в %s" % path)
		return {}
	if int(d["version"]) > CURRENT_VERSION:
		push_warning("SaveService: сейв версии %d новее приложения (%d) — не трогаем"
			% [int(d["version"]), CURRENT_VERSION])
		return {}
	return d


## v1 → v2: старая цепочка заменена на Sort.
##
## Сохраняем то, что про игрока и что остаётся правдой: кошелёк, просмотренную
## завязку, знакомство с Марго, объяснённый журнал. Снимаем то, что описывало
## исчезнувший контент: пройденные уровни старой цепочки, её флаги и состояния
## задач, которых больше нет.
##
## Отдельного разговора стоит `bakery_01`. Его id занял первый Sort-уровень, и
## «пройден» в старом сейве означало другой уровень — засчитать его новому
## значило бы отдать игроку награду за работу, которой он не делал, и пропустить
## единственный уровень, который в игре сейчас есть.
##
## Состояния локаций стираются целиком: пекарня теперь открыта из данных
## (initial_state), а сохранённое «locked» перекрыло бы это значение и оставило
## бы игрока на карте без единого доступного объекта.
func _migrate_1_to_2(data: Dictionary) -> Dictionary:
	var meta = data.get("meta", {})
	if not (meta is Dictionary):
		return data

	## Состояния задач пересчитываются от мира, поэтому их достаточно снести —
	## новые задачи разложатся сами. А вот список уже выданных наград остаётся:
	## он про то, за что игроку УЖЕ заплатили, и стереть его значит заплатить
	## второй раз за то же самое.
	meta.erase("shops")
	meta.erase("tasks")

	var levels: Dictionary = meta.get("completed_levels", {})
	var removed := 0
	for id in V1_DEAD_LEVELS:
		if levels.erase(id):
			removed += 1
	meta["completed_levels"] = levels
	meta["levels_completed_total"] = maxi(0, int(meta.get("levels_completed_total", 0)) - removed)

	var flags: Dictionary = meta.get("flags", {})
	for f in V1_DEAD_FLAGS:
		flags.erase(f)
	meta["flags"] = flags

	## Сюжетные предметы старой цепочки: ключ от пекарни и мусор из кладовой.
	## Тратить их больше негде, а в полосе инвентаря они остались бы навсегда.
	var player = data.get("player", {})
	if player is Dictionary:
		var bag: Dictionary = player.get("items", {})
		for id in ["bakery_key", "spiderweb", "flour_spill", "bootprints", "scrap_paper",
				"puddle", "broom", "brush", "trash_bag"]:
			bag.erase(id)
		player["items"] = bag
		data["player"] = player

	data["meta"] = meta
	return data


## Обучение перестало быть одним флагом на весь Sort: у каждого набора подсказок
## теперь свой, иначе объяснение правил в первом уровне закрыло бы заодно и
## предупреждение про лоток во втором — то, чего игрок ещё не видел.
func _migrate_2_to_3(data: Dictionary) -> Dictionary:
	var meta = data.get("meta", {})
	if not (meta is Dictionary):
		return data
	var flags: Dictionary = meta.get("flags", {})
	if bool(flags.get("sort_taught", false)):
		flags["tutorial_done:sort_basics"] = true
	flags.erase("sort_taught")
	meta["flags"] = flags
	data["meta"] = meta
	return data


func _migrate(data: Dictionary) -> Dictionary:
	var v := int(data.get("version", 1))
	while v < CURRENT_VERSION:
		if not MIGRATIONS.has(v):
			push_warning("SaveService: нет миграции с версии %d" % v)
			break
		data = call(MIGRATIONS[v], data)
		v += 1
		data["version"] = v
	return data
