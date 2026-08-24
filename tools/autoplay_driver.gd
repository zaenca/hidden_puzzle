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
	_check("L1: получен сюжетный предмет 'План района'", PlayerState.amount_of("district_plan") >= 1)
	_check("L1: задача готова к применению",
		Game.meta.task_state("task_survey_district") == MetaService.TaskState.READY_TO_APPLY)

	_apply("task_survey_district")
	_check("мета: пекарня выбрана", Game.meta.shop_state("bakery") == "in_restoration")
	_check("мета: план израсходован", PlayerState.amount_of("district_plan") == 0)

	Game.open_shop("bakery")
	await tree.create_timer(0.3).timeout

	# --- уровень 2: расчистка фасада ---------------------------------------
	await _play("task_clear_facade")
	_check("L2: найдены метла и мешок",
		PlayerState.amount_of("broom") >= 1 and PlayerState.amount_of("trash_bag") >= 1)
	_apply("task_clear_facade")
	_check("мета: мусор убран (visual state)",
		Game.meta.slot_state("bakery", "facade_trash") == "cleaned")

	# --- уровни 3-4: вывеска (одна задача, две части) ----------------------
	await _play("task_install_sign")
	_check("L3: задача в процессе (нужны ещё предметы)",
		Game.meta.task_state("task_install_sign") == MetaService.TaskState.IN_PROGRESS)
	await _play("task_install_sign")
	_check("L4: задача готова к применению",
		Game.meta.task_state("task_install_sign") == MetaService.TaskState.READY_TO_APPLY)
	_apply("task_install_sign")
	_check("мета: вывеска установлена",
		Game.meta.slot_state("bakery", "sign") == "installed")

	# --- cooldown: ремонт замка + параллельная задача ----------------------
	_check("после вывески открыт ремонт замка",
		Game.meta.task_state("task_repair_lock") == MetaService.TaskState.READY_TO_APPLY)
	_check("параллельная задача доступна",
		Game.meta.task_state("task_polish_window") == MetaService.TaskState.AVAILABLE)

	_apply("task_repair_lock")
	var left_before := CooldownService.remaining("repair_lock")
	_check("cooldown запущен (%d с)" % left_before, left_before > 500)
	_check("во время cooldown есть чем заняться", not Game.meta.playable_tasks().is_empty())

	# --- уровень 5: параллельно, сокращает ожидание ------------------------
	await _play("task_polish_window")
	var left_after := CooldownService.remaining("repair_lock")
	_check("уровень сократил cooldown на 180 c (%d → %d)" % [left_before, left_after],
		left_before - left_after >= 175)
	_apply("task_polish_window")
	_check("мета: витрина вымыта", Game.meta.slot_state("bakery", "window") == "clean")
	_check("мета: ручка установлена", Game.meta.slot_state("bakery", "door_handle") == "installed")

	# --- mock-ускорение и claim --------------------------------------------
	var hard_before := PlayerState.amount_of("hard")
	var sped := Game.meta.speed_up_with_hard("task_repair_lock")
	_check("mock hard-currency ускорение сработало", sped)
	_check("гемы списаны", PlayerState.amount_of("hard") == hard_before - 25)
	await tree.create_timer(0.2).timeout
	_check("cooldown готов к получению", Game.meta.can_claim("task_repair_lock"))

	Game.meta.claim_action("task_repair_lock")
	_check("мета: дверь открыта", Game.meta.slot_state("bakery", "door") == "open")
	_check("задача замка завершена",
		Game.meta.task_state("task_repair_lock") == MetaService.TaskState.COMPLETED)

	# --- сохранение / загрузка ---------------------------------------------
	SaveService.save_game()
	var levels_done: int = Game.meta.levels_completed_total
	PlayerState.reset()
	CooldownService.reset()
	Game.meta.reset()
	_check("состояние в памяти очищено", Game.meta.slot_state("bakery", "door") != "open")
	SaveService.load_game()
	Game.meta.refresh()
	_check("сейв: дверь осталась открытой", Game.meta.slot_state("bakery", "door") == "open")
	_check("сейв: вывеска на месте", Game.meta.slot_state("bakery", "sign") == "installed")
	_check("сейв: пройдено уровней = %d" % levels_done, Game.meta.levels_completed_total == levels_done)
	_check("сейв: пройдено 5 уровней", Game.meta.completed_levels.size() == 5)

	_report()


## --- вспомогательное --------------------------------------------------------

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
