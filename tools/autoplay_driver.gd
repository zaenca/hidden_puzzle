class_name AutoplayDriver
extends RefCounted
## Сквозной прогон vertical slice БЕЗ участия игрока — реальные сцены, реальные
## сервисы, реальный сейв. Это и есть «запусти и проверь» для CI и для меня.
##
##   godot --headless --path . -- --autoplay

## Лог пишется в файл построчно: консольный stdout/stderr при перенаправлении
## буферизуется, и до завершения процесса ничего не видно.
const REPORT_PATH := "res://autoplay_report.txt"

## Мусор в кладовой. Порядок как в content/shops/bakery_storeroom.json.
const TRASH_IDS := ["spiderweb", "flour_spill", "bootprints", "scrap_paper", "puddle"]

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

	# --- уровень 2: пазл зала и уборка нажатием ----------------------------
	_check_hall_scene()
	await _play_hall_to_cleanup()
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

	# --- кладовая: два пазла, уборка, мусор кликом в инвентарь -------------
	_check("кладовая: задача открылась после открытия двери",
		Game.meta.task_state("task_open_storeroom") == MetaService.TaskState.AVAILABLE)
	_check("кладовая: вход внутрь пока закрыт",
		not bool(Game.meta.flags.get("storeroom_ready", false)))

	_check("L3: кладовая собирается из 9 частей",
		ContentDB.level("storeroom_01").puzzle.piece_count() == 9)
	await _play("task_open_storeroom")
	_check("L3: кладовая собрана", Game.meta.completed_levels.has("storeroom_01"))
	_check("после первого пазла задача ещё не готова к применению",
		Game.meta.task_state("task_open_storeroom") == MetaService.TaskState.IN_PROGRESS)

	_check("L4: шкаф собирается из 9 частей",
		ContentDB.level("storeroom_02").puzzle.piece_count() == 9)
	await _play("task_open_storeroom")
	_check("L4: шкаф собран", Game.meta.completed_levels.has("storeroom_02"))
	_check("собраны оба предмета — задачу можно применить",
		Game.meta.task_state("task_open_storeroom") == MetaService.TaskState.READY_TO_APPLY)

	_apply("task_open_storeroom")
	_check("флаг storeroom_ready выставлен",
		bool(Game.meta.flags.get("storeroom_ready", false)))
	_check("мета: кладовая перешла в восстановление",
		Game.meta.shop_state("bakery_storeroom") == "in_restoration")

	Game.open_shop("bakery_storeroom")
	await tree.create_timer(0.4).timeout
	_check("кладовая открывается своей сценой", Game.screen == Game.Screen.SHOP)
	_check_storeroom_scene()

	var shelf_tap := Game.meta.interact("bakery_storeroom", "shelf", "")
	_check("шкаф отвечает на тап: %s" % shelf_tap.get("text", ""), bool(shelf_tap.get("ok", false)))

	_check("кладовая: задача уборки открылась",
		Game.meta.task_state("task_clear_storeroom") == MetaService.TaskState.AVAILABLE)
	_check_trash_pickup()
	await tree.create_timer(0.4).timeout
	_check_inventory_shows(TRASH_IDS)
	_check("весь мусор собран — задачу можно применить",
		Game.meta.task_state("task_clear_storeroom") == MetaService.TaskState.READY_TO_APPLY)

	_apply("task_clear_storeroom")
	var left := 0
	for id in TRASH_IDS:
		left += PlayerState.amount_of(String(id))
	_check("мусор вынесен из инвентаря", left == 0)
	_check("флаг storeroom_clean выставлен",
		bool(Game.meta.flags.get("storeroom_clean", false)))

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
	_check("сейв: кладовая осталась разобранной", bool(Game.meta.flags.get("storeroom_ready", false)))
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



## Уборка засчитывается НАЖАТИЕМ по месту, а не перетаскиванием предмета.
## Прогон делает это руками игрока: тап мимо не должен ничего менять, тап по
## месту — переключать кадр и забирать предмет из полосы.
func _check_hall_cleanup_is_tap() -> void:
	var level: Node = Game.current()
	if level == null or not ("_cleanup" in level):
		_check("зал: фаза уборки доступна прогону", false)
		return
	var cleanup = level._cleanup
	if cleanup == null or cleanup.current() == null:
		_check("зал: фаза уборки началась", false)
		return

	_check("зал: уборка на нажатии, а не на перетаскивании",
		cleanup.has_method("handle_tap") and not cleanup.has_method("handle_release"))

	var step = cleanup.current()
	var view = level._view
	var before := String(step.item_id)

	## Тап мимо: место шага — не весь кадр, и промах обязан остаться промахом.
	var outside: Vector2 = view.norm_to_world(_point_outside(step.rect))
	cleanup.handle_tap(outside)
	_check("зал: тап мимо места ничего не меняет",
		cleanup.current() != null and String(cleanup.current().item_id) == before)

	cleanup.handle_tap(view.norm_to_world(step.centroid()))
	_check("зал: тап по месту засчитывает шаг «%s»" % before,
		cleanup.current() == null or String(cleanup.current().item_id) != before)
	_check("зал: применённый предмет ушёл из полосы",
		Rect2(level._hud.chip_rect(before)) == Rect2())


## Точка заведомо вне области шага — по той стороне кадра, где её нет.
func _point_outside(rect: Rect2) -> Vector2:
	if rect.position.x > 0.1:
		return Vector2(rect.position.x * 0.5, rect.get_center().y)
	if rect.end.x < 0.9:
		return Vector2((rect.end.x + 1.0) * 0.5, rect.get_center().y)
	if rect.position.y > 0.1:
		return Vector2(rect.get_center().x, rect.position.y * 0.5)
	return Vector2(rect.get_center().x, (rect.end.y + 1.0) * 0.5)


## Зал прогон проходит не одним force'ом: до фазы уборки доводит пазл, а сами
## шаги делает нажатием, как игрок. Иначе проверка «уборка на нажатии» осталась
## бы проверкой сигнатуры метода, а не поведения.
func _play_hall_to_cleanup() -> void:
	var level: Node = Game.current()
	if level == null or not level.has_method("debug_autoplay"):
		_check("зал: уровень доступен и управляем", false)
		return
	if level._puzzle == null:
		level._start_puzzle()
		await _tree.create_timer(0.3).timeout
	if level._puzzle != null:
		level._puzzle.force_solve()

	var deadline := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline:
		if level._cleanup != null and level._cleanup.current() != null:
			break
		await _tree.process_frame
	_check_hall_cleanup_is_tap()

	if level._cleanup != null:
		level._cleanup.force_complete()
	await _await_left_level()



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


## Кладовая: собранная сцена из двух картинок плюс то, ради чего она собрана.
## Проверяем не «красиво», а то, что ломает игру молча: шкаф справа, мусор
## попадает под палец и НЕ обведён рамкой заранее — иначе искать нечего.
func _check_storeroom_scene() -> void:
	var scene: Node = Game.current()
	if scene == null or not ("_slots" in scene):
		_check("кладовая: сцена локации доступна", false)
		return
	var slot = scene._slots.get("shelf")
	if slot == null:
		_check("кладовая: слот шкафа построен", false)
		return
	_check("кладовая: шкаф стоит справа",
		slot.world_rect.get_center().x > 540.0)
	_check("кладовая: у шкафа есть площадь под палец",
		slot.world_rect.size.x > 100.0 and slot.world_rect.size.y > 100.0)

	var built := 0
	var ringed := 0
	var small := 0
	for id in TRASH_IDS:
		var s = scene._slots.get(String(id))
		if s == null:
			continue
		built += 1
		if s._highlight != null:
			ringed += 1
		if s.world_rect.size.x < 96.0 or s.world_rect.size.y < 96.0:
			small += 1
	_check("кладовая: весь мусор построен на сцене — %d/%d" % [built, TRASH_IDS.size()],
		built == TRASH_IDS.size())
	_check("кладовая: мусор не обведён рамкой заранее", ringed == 0)
	_check("кладовая: по каждому предмету можно попасть пальцем", small == 0)

	var with_art := 0
	for id in TRASH_IDS:
		if ContentDB.item(String(id)) != null and ContentDB.item(String(id)).icon != null:
			with_art += 1
	_check("кладовая: у мусора настоящие иконки, а не заглушки",
		with_art == TRASH_IDS.size())

	_check("кладовая: лампочка-подсказка на экране", scene._hint_button != null)
	_check("кладовая: подсказка знает, что показывать",
		not String(scene._next_searchable()).is_empty())
	_check("кладовая: полоска ячеек показана",
		scene._collection_panel != null and scene._collection_panel.visible)
	if scene._collection_row != null:
		_check("кладовая: ячеек ровно %d" % TRASH_IDS.size(),
			scene._collection_row.get_child_count() == TRASH_IDS.size())


## Каждый предмет мусора убирается ОДНИМ тапом пустой рукой и оказывается в
## инвентаре. Перетаскивания здесь нет и быть не должно.
func _check_trash_pickup() -> void:
	var scene: Node = Game.current()
	for id in TRASH_IDS:
		var item_id := String(id)
		var before := PlayerState.amount_of(item_id)
		var take := Game.meta.interact("bakery_storeroom", item_id, "")
		_check("мусор '%s' убирается тапом" % ContentDB.item_name(item_id),
			bool(take.get("ok", false)) and PlayerState.amount_of(item_id) == before + 1)
		_check("мусор '%s' пропал со сцены" % ContentDB.item_name(item_id),
			Game.meta.current_slot_state("bakery_storeroom", item_id) == "taken")
		var again := Game.meta.interact("bakery_storeroom", item_id, "")
		## Убранное место отвечает текстом — это нормально; не нормально было бы
		## выдать второй такой же предмет.
		_check("повторный тап по '%s' не выдаёт второй" % ContentDB.item_name(item_id),
			PlayerState.amount_of(item_id) == before + 1
				and String(again.get("granted", "")).is_empty())
	if scene != null and scene.has_method("_next_searchable"):
		_check("подсказке больше нечего показывать",
			String(scene._next_searchable()).is_empty())


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
