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
	_check("после пазла — сразу городская площадь, без экрана результата",
		Game.screen == Game.Screen.MAP)
	## Осмотр района — часть разговора с мэром, а не добыча: ни предмета в
	## инвентаре, ни начислений за первый пазл.
	_check("L1: инвентарь после первого пазла пуст", _bag_size() == 0)
	_check("L1: за сюжетный пазл не начислено монет", PlayerState.amount_of("coins") == 300)

	_check("L1: задача осмотра закрылась сама",
		Game.meta.task_state("task_survey_district") == MetaService.TaskState.COMPLETED)
	## Плашку копим, пока идёт уровень, и показываем уже в мете: поздравлять
	## поверх раскрытия сцены значит перебивать ровно тот кадр, ради которого
	## уровень и собирали.
	_check_task_notification("Осмотреть район")
	_check("мета: пекарня выбрана", Game.meta.shop_state("bakery") == "in_restoration")

	# --- площадь: ровно одна активная задача и указатель на неё -------------
	_check("площадь: задача «Осмотреть пекарню» открыта",
		Game.meta.task_state("task_visit_bakery") == MetaService.TaskState.AVAILABLE)
	_check_map_task_bar(["task_visit_bakery"])
	_check_map_hint_points_at("bakery")

	# --- карта: закрытые объекты тоже кликабельны --------------------------
	_check_map_hit_areas()

	# --- первый вход в пекарню: фасад → знакомство с хозяйкой --------------
	_check("до первого визита хозяйка незнакома",
		not bool(Game.meta.flags.get("met_baker", false)))
	Game.enter_shop("bakery")
	await tree.create_timer(0.5).timeout
	## Проверяем инвариант, а не конкретную сцену: в первый раз игрок не
	## попадает внутрь, минуя знакомство.
	_check("первый вход ведёт в сцену, а не сразу в локацию",
		Game.screen == Game.Screen.INTRO or Game.screen == Game.Screen.DIALOG)
	if Game.screen == Game.Screen.INTRO:
		Game.finish_intro()
		await tree.create_timer(0.4).timeout
	_check("после фасада — разговор с хозяйкой", Game.screen == Game.Screen.DIALOG)
	_check_dialog_runs()
	await tree.create_timer(0.4).timeout
	_check("после разговора игрок попадает сразу в уборку, а не в локацию",
		Game.screen == Game.Screen.LEVEL)
	_check("знакомство отмечено", bool(Game.meta.flags.get("met_baker", false)))
	_check("задача «Осмотреть пекарню» закрылась знакомством",
		Game.meta.task_state("task_visit_bakery") == MetaService.TaskState.COMPLETED)

	# --- уровень 2: пазл зала и уборка перетаскиванием ----------------------
	_check_hall_scene()
	await _finish_current_level()
	_check("после уборки — локация пекарни", Game.screen == Game.Screen.SHOP)
	_check("зал: задача уборки закрылась сама",
		Game.meta.task_state("task_clear_hall") == MetaService.TaskState.COMPLETED)
	_check("зал: флаг hall_clean выставлен", bool(Game.meta.flags.get("hall_clean", false)))
	_check_task_notification("Прибраться в торговом зале")
	## Предметы уборки живут внутри уровня и там же расходуются — в инвентарь
	## игрока они не попадают.
	_check("уборочный инвентарь не осел в сумке", _bag_size() == 0)

	# --- дверь в цех: заперто, ключ, применение ключа -----------------------
	_check("зал: дверь заперта", Game.meta.current_slot_state("bakery", "door") == "locked")
	_check("зал: вход в цех пока закрыт", not bool(Game.meta.flags.get("door_open", false)))

	var take := Game.meta.interact("bakery", "door", "")
	_check("тап по двери сработал: %s" % take.get("text", ""), bool(take.get("ok", false)))
	_check("ключ попал в инвентарь", PlayerState.amount_of("bakery_key") == 1)
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


## Зал — пазл, потом уборка перетаскиванием. Проверяем структуру уровня: что
## именно там происходит и в каком порядке. Сам drag прогон не эмулирует —
## он форсирует шаги, а вот что шагов три и у каждого свой кадр, ломается
## незаметно.
func _check_hall_scene() -> void:
	var def: LevelDefinition = ContentDB.level("bakery_02")
	if def == null:
		_check("зал: уровень bakery_02 загружается", false)
		return

	_check("зал: пазл собирается из 9 частей", def.puzzle.piece_count() == 9)
	_check("зал: предметы не ищут — фазы поиска нет",
		def.hidden_object.targets.is_empty())

	var steps := def.cleanup
	_check("зал: три шага уборки", steps.size() == 3)
	var order := PackedStringArray()
	for s in steps:
		order.append(s.item_id)
	_check("зал: порядок уборки — метла, щётка, мешок",
		"/".join(order) == "broom/brush/trash_bag")

	## Каждый шаг обязан менять кадр: без нового состояния комнаты игрок тащит
	## предмет и не видит результата.
	var arts := {}
	var arts_ok := true
	for s in steps:
		if s.art_path.is_empty() or arts.has(s.art_path) or not ResourceLoader.exists(s.art_path):
			arts_ok = false
		arts[s.art_path] = true
	_check("зал: у каждого шага свой кадр комнаты", arts_ok and arts.size() == 3)

	_check("зал: экран результата не показывается", not def.show_result)
	_check("зал: предметы уборки известны уровню",
		Game.items_for_level(def).size() >= 3)

	_check("зал: пазл собирается по интерьеру пекарни",
		def.art.background_path == "res://art/bakery_interior.jpg")
	_check("зал: предметы лежат отдельным слоем, а не запечены в пазл",
		def.art.objects_background_path == "res://art/bakery_interior_objects.png")


## «Задача закрыта» и «игрок про это узнал» — разные утверждения. Плашка живёт
## в оверлее Boot, поэтому ищем её там, а не в текущей сцене.
func _check_task_notification(expected_title: String) -> void:
	var node: Node = _tree.root.find_child("TaskNotification", true, false)
	if node == null:
		_check("плашка: виджет уведомлений на месте", false)
		return
	_check("плашка: показана после закрытия задачи", node.is_showing())
	_check("плашка: игрок извещён про «%s»" % expected_title, node.knows(expected_title))



## Что игрок видит в инвентаре: бустеры в полосу не попадают.
func _bag_size() -> int:
	var n := 0
	for id in PlayerState.items:
		if String(id) != Game.BOOSTER_ID:
			n += 1
	return n


## Панель задач на карте показывает ровно то, чем можно заняться сейчас.
## Проверяем сцену, а не мету: «задача выполнена» и «строка про неё убралась с
## экрана» — разные утверждения, и ломается обычно второе.
func _check_map_task_bar(expected_ids: PackedStringArray) -> void:
	var map: Node = Game.current()
	if map == null or not ("_task_list" in map):
		_check("площадь: панель задач доступна", false)
		return
	var list: Node = map._task_list
	var rows := 0
	for c in list.get_children():
		if not c.is_queued_for_deletion():
			rows += 1
	var titles := PackedStringArray()
	for id in expected_ids:
		var t: MetaTaskDefinition = ContentDB.task(String(id))
		if t != null:
			titles.append(t.title)
	_check("площадь: в панели ровно %d задача — %s" % [expected_ids.size(), ", ".join(titles)],
		rows == expected_ids.size())


## Указатель обязан стоять на здании, а не «где-то на карте».
func _check_map_hint_points_at(shop_id: String) -> void:
	var map: Node = Game.current()
	if map == null or not ("_hand" in map):
		_check("площадь: указатель доступен", false)
		return
	_check("площадь: рука показывает на здание", map._hand != null)
	if map._hand == null:
		return
	var rect := Rect2()
	for area in map._hit_areas:
		if String(area["shop_id"]) == shop_id:
			rect = area["rect"]
	_check("площадь: рука стоит именно на пекарне",
		rect.size.x > 0.0 and rect.has_point(map._hand.position))


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
	await _await_left_level()


## Ждём не секунды, а смену экрана. Уровень без экрана результата доигрывает
## переход сам и ровно поэтому не может дождаться сам себя: он освобождается
## посреди собственной корутины.
func _await_left_level(timeout_sec: float = 6.0) -> void:
	var deadline := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while Game.screen == Game.Screen.LEVEL and Time.get_ticks_msec() < deadline:
		await _tree.process_frame
	await _tree.create_timer(0.4).timeout


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
