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

	# --- завязка: вступление → диалог → пазл → площадь ----------------------
	_check("старт: задача осмотра района доступна",
		Game.meta.task_state("task_survey_district") == MetaService.TaskState.AVAILABLE)

	_check("старт: новая игра открывается вступлением", Game.screen == Game.Screen.INTRO)
	Game.finish_intro()
	await tree.create_timer(0.3).timeout
	_check("после вступления — диалог с мэром", Game.screen == Game.Screen.DIALOG)
	_check_dialog_runs()
	await tree.create_timer(0.5).timeout
	_check("после диалога — сразу пазл, а не карта", Game.screen == Game.Screen.LEVEL)
	_check("завязка отмечена просмотренной",
		bool(Game.meta.flags.get(Game.INTRO_FLAG, false)))

	# --- уровень 1: план района, только пазл из 6 частей --------------------
	_check("L1: пазл собирается из 6 частей",
		ContentDB.level("bakery_01").puzzle.piece_count() == 6)
	await _finish_current_level()
	_check("L1: получен сюжетный предмет 'План района'", PlayerState.amount_of("district_plan") >= 1)
	_check("после пазла — городская площадь", Game.screen == Game.Screen.MAP)
	_check("L1: задача готова к применению",
		Game.meta.task_state("task_survey_district") == MetaService.TaskState.READY_TO_APPLY)

	_apply("task_survey_district")
	_check("мета: пекарня выбрана", Game.meta.shop_state("bakery") == "in_restoration")
	_check("мета: план израсходован", PlayerState.amount_of("district_plan") == 0)

	# --- карта: закрытые объекты тоже кликабельны --------------------------
	_check_map_hit_areas()

	# --- первый вход в пекарню: фасад → знакомство с хозяйкой --------------
	_check("до первого визита хозяйка незнакома",
		not bool(Game.meta.flags.get("met_baker", false)))
	Game.enter_shop("bakery")
	await tree.create_timer(0.5).timeout
	## Кадр с фасадом проскакивает сам, пока его арта нет в проекте, — проверяем
	## не его наличие, а инвариант: в первый раз игрок не попадает внутрь, минуя
	## знакомство.
	_check("первый вход ведёт в сцену, а не сразу в локацию",
		Game.screen == Game.Screen.INTRO or Game.screen == Game.Screen.DIALOG)
	if Game.screen == Game.Screen.INTRO:
		Game.finish_intro()
		await tree.create_timer(0.4).timeout
	_check("после фасада — разговор с хозяйкой", Game.screen == Game.Screen.DIALOG)
	_check_dialog_runs()
	await tree.create_timer(0.4).timeout
	_check("после разговора игрок внутри пекарни", Game.screen == Game.Screen.SHOP)
	_check("знакомство отмечено", bool(Game.meta.flags.get("met_baker", false)))

	Game.enter_shop("bakery")
	await tree.create_timer(0.4).timeout
	_check("повторный вход ведёт сразу в локацию, без сцены",
		Game.screen == Game.Screen.SHOP)

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

	var wrong := Game.meta.interact("bakery", "door", "district_plan")
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

	# --- уровень 2: завал в зале, метла и мешок падают в инвентарь ----------
	_check("зал: задача уборки открылась",
		Game.meta.task_state("task_clear_hall") == MetaService.TaskState.AVAILABLE)
	_check("зал: пол засыпан мусором",
		Game.meta.current_slot_state("bakery", "floor_litter") == "dirty")
	_check("зал: витрина грязная",
		Game.meta.current_slot_state("bakery", "showcase") == "dirty")

	await _play("task_clear_hall")
	_check("L2: метла выдана", PlayerState.amount_of("broom") >= 1)
	_check("L2: мешок для мусора выдан", PlayerState.amount_of("trash_bag") >= 1)
	await tree.create_timer(0.4).timeout
	_check_inventory_shows(["broom", "trash_bag"])

	_apply("task_clear_hall")
	_check("зал: пол убран",
		Game.meta.current_slot_state("bakery", "floor_litter") == "cleaned")
	_check("мешок израсходован", PlayerState.amount_of("trash_bag") == 0)
	_check("метла осталась инструментом", PlayerState.amount_of("broom") >= 1)
	_check("под завалом нашлась ветошь", PlayerState.amount_of("rag") >= 1)

	var wipe := Game.meta.interact("bakery", "showcase", "rag")
	_check("витрина отмыта ветошью: %s" % wipe.get("text", ""), bool(wipe.get("ok", false)))
	_check("витрина: состояние clean",
		Game.meta.current_slot_state("bakery", "showcase") == "clean")
	_check("ветошь израсходована", PlayerState.amount_of("rag") == 0)

	# --- сохранение / загрузка ---------------------------------------------
	SaveService.save_game()
	var levels_done: int = Game.meta.levels_completed_total
	var distinct_levels: int = Game.meta.completed_levels.size()
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
	_check("сейв: пройдено разных уровней = %d" % distinct_levels,
		Game.meta.completed_levels.size() == distinct_levels)

	_report()


## Диалог листается той же кнопкой, что и у игрока: проверяем, что цепочка
## реплик доходит до конца и сама выводит на площадь, а не застревает.
func _check_dialog_runs() -> void:
	var scene: Node = Game.current()
	if scene == null or not scene.has_method("advance"):
		_check("диалог: сцена доступна", false)
		return

	var total: int = scene.line_count()
	_check("диалог: загружено реплик — %d" % total, total > 0)

	var speakers := {}
	var guard := 0
	while Game.screen == Game.Screen.DIALOG and guard <= total + 2:
		guard += 1
		speakers[scene.current_speaker()] = true
		scene.advance()

	_check("диалог: пролистан кнопкой до конца", Game.screen != Game.Screen.DIALOG)
	_check("диалог: реплики есть у обоих собеседников", speakers.size() >= 2)


## Начислить предмет и показать его игроку — разные вещи. Полоса инвентаря
## живёт в оверлее Boot и обязана быть на виду сразу после возврата с уровня.
func _check_inventory_shows(item_ids: Array) -> void:
	var bar = Game.inventory
	if bar == null:
		_check("инвентарь: полоса существует", false)
		return
	_check("инвентарь: полоса видна после возврата с уровня", bar.visible)
	for id in item_ids:
		_check("инвентарь: '%s' попал в полосу" % ContentDB.item_name(String(id)),
			bar.shows(String(id)))


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

func _play(task_id: String) -> void:
	Game.play_task(task_id)
	await _tree.create_timer(0.4).timeout
	_check("уровень для '%s' запустился" % task_id, Game.screen == Game.Screen.LEVEL)
	await _finish_current_level()


## Пройти уровень, который УЖЕ открыт. Отдельно от _play: после диалога игрок
## попадает в уровень сам, и запускать его повторно значило бы проверять не тот
## путь, которым идёт игрок.
func _finish_current_level() -> void:
	var level: Node = Game.current()
	if level == null or not level.has_method("debug_autoplay"):
		_check("уровень доступен и управляем", false)
		return
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
