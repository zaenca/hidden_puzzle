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
const CURRENT_VERSION := 1

## version -> имя метода миграции. Пример будущей записи: 1: "_migrate_1_to_2".
const MIGRATIONS := {}

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
