class_name AutoplayDriver
extends RefCounted
## Сквозной прогон vertical slice БЕЗ участия игрока — реальные сцены, реальные
## сервисы, реальный сейв. Это и есть «запусти и проверь» для CI и для меня.
##
##   godot --headless --path . -- --autoplay

## Лог пишется в файл построчно: консольный stdout/stderr при перенаправлении
## буферизуется, и до завершения процесса ничего не видно.
const REPORT_PATH := "res://autoplay_report.txt"

var _tree: SceneTree
var _checks: Array = []
var _log: PackedStringArray = PackedStringArray()


func _say(line: String) -> void:
	_log.append(line)
	print(line)
	var f := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_log))
		f.close()


func run(tree: SceneTree) -> void:
	_tree = tree
	await tree.process_frame
	await tree.create_timer(0.2).timeout

	_say("=== AUTOPLAY: vertical slice ===")
	Game.hard_reset()
	await tree.create_timer(0.3).timeout

	_check("старт: задача осмотра района доступна",
		Game.meta.task_state("task_survey_district") == MetaService.TaskState.AVAILABLE)

	# --- уровень 1: карта района -------------------------------------------
	await _play("task_survey_district")
	# Осмотр района — это разговор с мэром, а не добыча предмета: сумка после
	# первого уровня обязана остаться пустой.
	_check("L1: сумка после первого уровня пуста", _bag_size() == 0)
	_check("L1: задача готова к применению",
		Game.meta.task_state("task_survey_district") == MetaService.TaskState.READY_TO_APPLY)

	_apply("task_survey_district")
	_check("мета: пекарня выбрана", Game.meta.shop_state("bakery") == "in_restoration")

	# --- карта: закрытые объекты тоже кликабельны --------------------------
	_check_map_hit_areas()

	Game.open_shop("bakery")
	await tree.create_timer(0.3).timeout

	# --- фасад: заперто, ключ, применение ключа ----------------------------
	_check("фасад: дверь заперта", Game.meta.current_slot_state("bakery", "door") == "locked")
	_check("фасад: вход внутрь пока закрыт", not bool(Game.meta.flags.get("door_open", false)))

	var take := Game.meta.interact("bakery", "door", "")
	_check("тап по двери сработал: %s" % take.get("text", ""), bool(take.get("ok", false)))
	_check("ключ попал в сумку", PlayerState.amount_of("bakery_key") == 1)
	_check("дверь всё ещё заперта", Game.meta.current_slot_state("bakery", "door") == "locked")

	var again := Game.meta.interact("bakery", "door", "")
	_check("повторный тап не выдаёт второй ключ", PlayerState.amount_of("bakery_key") == 1)
	_check("повторный тап подсказывает, а не открывает",
		not bool(again.get("narrative", false)))

	var wrong := Game.meta.interact("bakery", "door", Game.BOOSTER_ID)
	_check("чужой предмет дверь не открывает",
		not bool(wrong.get("ok", false)) and Game.meta.current_slot_state("bakery", "door") == "locked")

	var used := Game.meta.interact("bakery", "door", "bakery_key")
	_check("ключ применён к двери", bool(used.get("ok", false)))
	_check("мета: дверь открыта", Game.meta.current_slot_state("bakery", "door") == "open")
	_check("ключ израсходован", PlayerState.amount_of("bakery_key") == 0)
	_check("флаг door_open выставлен", bool(Game.meta.flags.get("door_open", false)))

	var closed := Game.meta.interact("bakery", "door", "")
	_check("открытая дверь больше не выдаёт ключ", PlayerState.amount_of("bakery_key") == 0)
	_check("открытая дверь отвечает текстом", not String(closed.get("text", "")).is_empty())

	# --- уровень 2: торговый зал -------------------------------------------
	_check("зал: задача разблокирована открытой дверью",
		Game.meta.task_state("task_clear_hall") == MetaService.TaskState.AVAILABLE)

	await _play("task_clear_hall")
	_check("L2: найдена метла", PlayerState.amount_of("broom") == 1)
	_check("L2: найден мешок для мусора", PlayerState.amount_of("trash_bag") == 1)
	_check("L2: в зале искали ровно два предмета", _hall_target_count() == 2)
	_check("L2: задача готова к применению",
		Game.meta.task_state("task_clear_hall") == MetaService.TaskState.READY_TO_APPLY)

	_apply("task_clear_hall")
	_check("мета: инвентарь для уборки израсходован",
		PlayerState.amount_of("broom") == 0 and PlayerState.amount_of("trash_bag") == 0)
	_check("мета: флаг hall_cleared выставлен", bool(Game.meta.flags.get("hall_cleared", false)))

	# --- сохранение / загрузка ---------------------------------------------
	SaveService.save_game()
	var levels_done: int = Game.meta.levels_completed_total
	PlayerState.reset()
	CooldownService.reset()
	Game.meta.reset()
	_check("состояние в памяти очищено", Game.meta.current_slot_state("bakery", "door") != "open")
	SaveService.load_game()
	Game.meta.refresh()
	_check("сейв: дверь осталась открытой", Game.meta.current_slot_state("bakery", "door") == "open")
	_check("сейв: флаг door_open на месте", bool(Game.meta.flags.get("door_open", false)))
	_check("сейв: ключ не воскрес", PlayerState.amount_of("bakery_key") == 0)
	_check("сейв: пройдено уровней = %d" % levels_done, Game.meta.levels_completed_total == levels_done)
	_check("сейв: пройдено 2 уровня", Game.meta.completed_levels.size() == 2)

	_report()


## Мэрия и другие «пока закрытые» здания обязаны попадать в хит-тест: игрок
## должен получать ответ на тап, а не тишину.
func _check_map_hit_areas() -> void:
	var map: Node = Game.current()
	if map == null or not ("_hit_areas" in map):
		_check("карта: доступен список кликабельных зданий", false)
		return
	var areas: Array = map._hit_areas
	var without_shop := 0
	for a in areas:
		if String(a.get("shop_id", "")).is_empty():
			without_shop += 1
	_check("карта: кликабельны все %d зданий" % ContentDB.map_data.get("buildings", []).size(),
		areas.size() == ContentDB.map_data.get("buildings", []).size())
	_check("карта: здание без магазина (мэрия) тоже кликабельно", without_shop >= 1)


## --- вспомогательное --------------------------------------------------------

## Что игрок видит в сумке на фасаде: бустеры туда не попадают.
func _bag_size() -> int:
	var n := 0
	for id in PlayerState.items:
		if String(id) != Game.BOOSTER_ID:
			n += 1
	return n


func _hall_target_count() -> int:
	var def: LevelDefinition = ContentDB.level("bakery_02")
	return def.hidden_object.targets.size() if def != null else -1


func _play(task_id: String) -> void:
	Game.play_task(task_id)
	await _tree.create_timer(0.4).timeout
	var level: Node = Game.current()
	if level == null or not level.has_method("debug_autoplay"):
		_check("уровень для '%s' запустился" % task_id, false)
		return
	_check("уровень для '%s' запустился" % task_id, true)
	await level.debug_autoplay()
	await _tree.create_timer(0.6).timeout


func _apply(task_id: String) -> void:
	var ok := Game.meta.start_action(task_id)
	_check("meta action задачи '%s' применён" % task_id, ok)


func _check(title: String, ok: bool) -> void:
	_checks.append({"title": title, "ok": ok})
	_say(("  [ OK ] " if ok else "  [FAIL] ") + title)


func _report() -> void:
	var failed := 0
	for c in _checks:
		if not c["ok"]:
			failed += 1
	_say("=== AUTOPLAY: %d проверок, провалено %d ===" % [_checks.size(), failed])
	if failed == 0:
		_say("Полный цикл puzzle -> hidden object -> quest item -> meta change работает.")
	_tree.quit(1 if failed > 0 else 0)
