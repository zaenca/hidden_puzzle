extends Node
## Cooldown хранит АБСОЛЮТНЫЙ ends_at, а не остаток — поэтому после закрытия
## приложения ничего «доганять» не нужно, время идёт само.
##
## Состояние READY отделено от CLAIMED намеренно: эффекты применяются только
## когда игрок вернулся и увидел изменение мира. Иначе он пропускает главную
## награду цикла.

const STATE_NONE := "none"
const STATE_RUNNING := "running"
const STATE_READY := "ready"

var _entries: Dictionary = {}   ## action_id -> Dictionary
var _tick_acc: float = 0.0
var _last_seen: int = 0


func _ready() -> void:
	_last_seen = TimeService.now()


func _process(delta: float) -> void:
	_tick_acc += delta
	if _tick_acc < 0.5:
		return
	_tick_acc = 0.0
	_last_seen = TimeService.now()
	for action_id in _entries.keys():
		var e: Dictionary = _entries[action_id]
		if not e.get("notified", false) and remaining(action_id) <= 0:
			e["notified"] = true
			EventBus.cooldown_finished.emit(action_id)


func start(action_id: String, duration_sec: int, task_id: String = "") -> void:
	var now := TimeService.now()
	_entries[action_id] = {
		"started_at": now,
		"ends_at": now + maxi(0, duration_sec),
		"total_sec": duration_sec,
		"reduced_sec": 0,
		"source_task": task_id,
		"notified": duration_sec <= 0,
	}
	EventBus.cooldown_started.emit(action_id)


func has(action_id: String) -> bool:
	return _entries.has(action_id)


func remaining(action_id: String) -> int:
	if not _entries.has(action_id):
		return 0
	return maxi(0, int(_entries[action_id]["ends_at"]) - TimeService.now())


func total(action_id: String) -> int:
	return int(_entries.get(action_id, {}).get("total_sec", 0))


func state(action_id: String) -> String:
	if not _entries.has(action_id):
		return STATE_NONE
	return STATE_READY if remaining(action_id) <= 0 else STATE_RUNNING


func is_ready(action_id: String) -> bool:
	return state(action_id) == STATE_READY


func is_running(action_id: String) -> bool:
	return state(action_id) == STATE_RUNNING


## Сокращение за прохождение core level.
func reduce(action_id: String, seconds: int) -> int:
	if not _entries.has(action_id) or seconds <= 0:
		return 0
	var e: Dictionary = _entries[action_id]
	var before := remaining(action_id)
	var applied := mini(before, seconds)
	e["ends_at"] = int(e["ends_at"]) - applied
	e["reduced_sec"] = int(e["reduced_sec"]) + applied
	return applied


## Все идущие cooldown, чтобы мета могла сократить каждый по своему правилу.
func running_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for id in _entries:
		if is_running(id):
			out.append(id)
	return out


func finish_now(action_id: String) -> void:
	if not _entries.has(action_id):
		return
	_entries[action_id]["ends_at"] = TimeService.now()


func clear(action_id: String) -> void:
	_entries.erase(action_id)


func entry(action_id: String) -> Dictionary:
	return _entries.get(action_id, {})


## --- save -------------------------------------------------------------------

func save_data() -> Dictionary:
	return {"entries": _entries.duplicate(true), "last_seen": TimeService.now()}


func load_data(d: Dictionary) -> void:
	_entries = {}
	for k in d.get("entries", {}):
		_entries[String(k)] = (d["entries"][k] as Dictionary).duplicate()
	_last_seen = int(d.get("last_seen", TimeService.now()))
	_guard_clock_rollback()


## Часы отмотали назад → сдвигаем ends_at на ту же дельту, чтобы отмотка
## не давала выигрыша. Перевод часов ВПЕРЁД в прототипе не блокируется
## (требует серверного времени) — зафиксировано как допущение.
func _guard_clock_rollback() -> void:
	var now := TimeService.now()
	if now >= _last_seen - 60:
		return
	var delta := _last_seen - now
	for id in _entries:
		_entries[id]["ends_at"] = int(_entries[id]["ends_at"]) - delta


func reset() -> void:
	_entries.clear()
