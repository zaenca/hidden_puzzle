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
	## Заставку пропускаем кнопкой, а не вызовом finish_intro: у игрока есть
	## только кнопка, и «метод отработал» ничего не говорит о том, что до неё
	## можно дотянуться.
	_press_skip("вступление")
	await tree.create_timer(0.3).timeout
	_check("после вступления — диалог с мэром", Game.screen == Game.Screen.DIALOG)
	_check_dialog_runs()
	await tree.create_timer(0.5).timeout
	_check("после диалога — сразу пазл, а не карта", Game.screen == Game.Screen.LEVEL)
	_check("завязка отмечена просмотренной",
		bool(Game.meta.flags.get(Game.INTRO_FLAG, false)))

	# --- уровень 1: план района, только пазл из 6 частей --------------------
	_check("L1: пазл собирается из 9 частей",
		ContentDB.level("bakery_01").puzzle.piece_count() == 9)
	await _finish_current_level()
	_check("после пазла — сразу городская площадь, без экрана результата",
		Game.screen == Game.Screen.MAP)
	## Осмотр района — часть разговора с мэром, а не добыча: предмета в
	## инвентаре после него нет. Монеты приходят, но за ЗАДАЧУ, а не за уровень:
	## кошелёк стартует пустым, и 10 монет в нём — ровно то, что обещал журнал.
	_check("L1: инвентарь после первого пазла пуст", _bag_size() == 0)
	_check("L1: за задачу начислено 10 монет", PlayerState.amount_of("coins") == 10)
	## Награда выдаётся один раз: пересчёт состояний задач идёт на каждом
	## refresh, и платить по факту «задача выполнена» значило бы платить всегда.
	Game.meta.refresh()
	_check("L1: повторный пересчёт не удваивает награду",
		PlayerState.amount_of("coins") == 10)

	_check("L1: задача осмотра закрылась сама",
		Game.meta.task_state("task_survey_district") == MetaService.TaskState.COMPLETED)
	## Плашку копим, пока идёт уровень, и показываем уже в мете: поздравлять
	## поверх раскрытия сцены значит перебивать ровно тот кадр, ради которого
	## уровень и собирали.
	_check_task_notification("Собрать план района")
	_check_journal("Собрать план района", "Осмотреть пекарню")
	_check("мета: пекарня выбрана", Game.meta.shop_state("bakery") == "in_restoration")

	# --- площадь: ровно одна активная задача и указатель на неё -------------
	_check("площадь: задача «Осмотреть пекарню» открыта",
		Game.meta.task_state("task_visit_bakery") == MetaService.TaskState.AVAILABLE)
	_check_map_task_bar(["task_visit_bakery"])
	## До обучения рука ведёт к журналу, а не к зданию: список объясняет, зачем
	## вообще идти в пекарню. К зданию она переезжает, когда объяснение доиграно.
	_check_hint_points_at_journal()
	await _play_journal_coach()
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
	## После знакомства игрок остаётся в зале, а не проваливается в уровень:
	## сперва он видит комнату, о которой шла речь, и уже сам решает начать.
	_check("после разговора игрок попадает в локацию, а не в уровень",
		Game.screen == Game.Screen.SHOP)
	_check("знакомство отмечено", bool(Game.meta.flags.get("met_baker", false)))
	_check("задача «Осмотреть пекарню» закрылась знакомством",
		Game.meta.task_state("task_visit_bakery") == MetaService.TaskState.COMPLETED)
	_check_journal_hides_locked()

	# --- уровень 2: пазл зала и уборка нажатием ----------------------------
	## Уборку запускает игрок кнопкой из списка задач — прогон делает то же.
	Game.play_task("task_clear_hall")
	await tree.create_timer(0.5).timeout
	_check("уборка зала запускается из списка задач", Game.screen == Game.Screen.LEVEL)
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

	await _check_procedural_room()
	await _check_dialog_skip()

	_report()


## Пропуск проверяем нажатием на настоящую кнопку. Кнопка тут — единственное,
## что есть у игрока: сцена, у которой пропуск работает только изнутри, для него
## ничем не отличается от сцены без пропуска.
func _press_skip(where: String) -> bool:
	var button := _find_skip_button(Game.current())
	_check("%s: кнопка «Пропустить» есть на экране" % where, button != null)
	if button == null:
		return false
	button.pressed.emit()
	return true


func _find_skip_button(node: Node) -> Button:
	if node == null:
		return null
	if node is Button and (node as Button).text == "Пропустить":
		return node
	for child in node.get_children():
		var found := _find_skip_button(child)
		if found != null:
			return found
	return null


## Пропуск разговора обязан доигрывать его до конца, а не бросать: флаг и
## переход дальше висят на on_finish, и выход мимо него оставил бы игрока между
## сценами. Проверка стоит последней: она уводит с экрана, а до этого прогон
## занят самим сюжетом.
func _check_dialog_skip() -> void:
	Game.open_dialog("intro_mayor")
	await _tree.create_timer(0.4).timeout
	if not _press_skip("диалог"):
		return
	await _tree.create_timer(0.4).timeout
	_check("диалог: пропуск уводит с экрана диалога", Game.screen != Game.Screen.DIALOG)


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

	## В зале пазла нет: игрок пришёл убираться, а не собирать ту же комнату.
	_check("зал: сборки перед уборкой нет", def.puzzle.module_id.is_empty())
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

	## Каждый предмет надо сперва найти. Шаг без find_rect молча превратился бы
	## в «предмет выдали», и поиска в уровне бы не осталось.
	var findable := 0
	for s in steps:
		if s.needs_finding():
			findable += 1
	_check("зал: у каждого шага размечено, где искать предмет", findable == steps.size())



## Уборка идёт в два захода и целиком на нажатии: сперва найти предмет в кадре,
## потом нажать туда, где он нужен. Прогон делает это руками игрока — иначе
## проверка «уборка на нажатии» осталась бы проверкой сигнатуры метода.
func _check_hall_cleanup_is_tap() -> void:
	var level: Node = Game.current()
	if level == null or not ("_cleanup" in level):
		_check("зал: фаза уборки доступна прогону", false)
		return
	var cleanup = level._cleanup
	var view = level._view
	if cleanup == null or view == null:
		_check("зал: фаза уборки началась", false)
		return
	var steps: Array = ContentDB.level("bakery_02").cleanup
	if steps.size() < 3:
		_check("зал: шаги уборки загрузились", false)
		return

	_check("зал: уборка на нажатии, а не на перетаскивании",
		cleanup.has_method("handle_tap") and not cleanup.has_method("handle_release"))
	_check("зал: фаза начинается с поиска, а не с применения",
		cleanup.current() == null)

	## Подсказку игрок вызывает сам, кнопкой, и она тратит бустер. Рука по
	## таймеру отвечала бы на вопрос, которого игрок ещё не задал.
	_check("зал: рука сама по себе не выскакивает", cleanup._hand == null)
	var boosters: int = level._boosters_left
	level._on_booster()
	_check("зал: кнопка подсказки показывает палец", cleanup._hand != null)
	_check("зал: подсказка потратила один бустер",
		int(level._boosters_left) == boosters - 1)

	## Применить то, чего ещё не нашли, нельзя — иначе поиск был бы декорацией.
	var use_spot: Vector2 = view.norm_to_world(steps[0].centroid())
	cleanup.handle_tap(use_spot)
	_check("зал: ненайденный предмет применить нельзя", cleanup.current() == null)

	var missed: Vector2 = view.norm_to_world(_point_outside(steps[0].find_rect))
	cleanup.handle_tap(missed)
	_check("зал: тап мимо предмета ничего не находит", cleanup.current() == null)

	for step in steps:
		var spot: Vector2 = view.norm_to_world(step.find_centroid())
		cleanup.handle_tap(spot)
	_check("зал: все три предмета находятся тапом", cleanup.current() != null)
	_check("зал: найденное стёрто из кадра",
		view.patches != null and view.patches.get_child_count() == steps.size())

	var before := String(steps[0].item_id)
	var off_target: Vector2 = view.norm_to_world(_point_outside(steps[0].rect))
	cleanup.handle_tap(off_target)
	_check("зал: тап мимо места применения ничего не меняет",
		cleanup.current() != null and String(cleanup.current().item_id) == before)

	cleanup.handle_tap(use_spot)
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
## Журнал заданий: путь целиком, с отметкой пройденного и текущего. Проверяем
## то, что прочтёт игрок, а не то, что мета думает про свои задачи: список
## строит виджет, и разойтись он может именно на строках.
## Журнал показывает пройденное и текущее, но не то, что ещё закрыто: список
## будущего — спойлер сюжета. Проверять надо именно отсутствие, поэтому берём
## закрытые задачи у меты и ищем их заголовки среди строк.
func _check_journal_hides_locked() -> void:
	var node: Node = _tree.root.find_child("TaskJournal", true, false)
	if node == null:
		_check("журнал: виджет на месте", false)
		return
	node.call("open")
	var joined := "\n".join(node.call("lines"))
	var locked := PackedStringArray()
	var leaked := ""
	for task in Game.meta.all_tasks():
		if Game.meta.task_state(task.id) != MetaService.TaskState.LOCKED:
			continue
		locked.append(task.title)
		if joined.contains(task.title):
			leaked = task.title
	_check("журнал: закрытых задач на экране нет (закрыто — %d)" % locked.size(),
		locked.size() > 0 and leaked.is_empty())
	node.call("close")


func _check_journal(done_title: String, current_title: String) -> void:
	var node: Node = _tree.root.find_child("TaskJournal", true, false)
	if node == null:
		_check("журнал: виджет на месте", false)
		return
	node.call("open")
	_check("журнал: открывается кнопкой", bool(node.call("is_open")))

	var lines: PackedStringArray = node.call("lines")
	_check("журнал: показывает пройденное и текущее", lines.size() >= 2)

	var done_at := -1
	var current_at := -1
	for i in lines.size():
		var line := String(lines[i])
		if line.contains(done_title):
			done_at = i
		elif line.contains(current_title):
			current_at = i
	## Порядок, а не просто наличие: журнал существует ради «что после чего»,
	## и список, где пройденное стоит после текущего, врёт именно об этом.
	_check("журнал: пройденное стоит перед текущим",
		done_at >= 0 and current_at > done_at)

	## Галочка читается из картинки чекбокса: по ней игрок и судит о прогрессе.
	var done: PackedStringArray = node.call("done_titles")
	var done_marked := false
	var current_marked := false
	for title in done:
		if String(title).contains(done_title):
			done_marked = true
		if String(title).contains(current_title):
			current_marked = true
	_check("журнал: у «%s» стоит галочка" % done_title, done_marked)
	_check("журнал: у «%s» галочки нет" % current_title, not current_marked)
	node.call("close")


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


## Указатель на кнопку журнала. Кнопка живёт в оверлее, поэтому и рука там же —
## проверяем, что она рядом с кнопкой, а не «где-то на экране».
func _check_hint_points_at_journal() -> void:
	var map: Node = Game.current()
	var journal: Node = Game.journal
	if map == null or not ("_hand" in map) or journal == null:
		_check("площадь: указатель доступен", false)
		return
	_check("площадь: рука показывает на журнал", map._hand != null)
	if map._hand == null:
		return
	var center: Vector2 = journal.call("button_center")
	_check("площадь: рука стоит на кнопке журнала",
		center.distance_to(map._hand.position) < 4.0)


## Обучение журналу: игрок открывает список и прощёлкивает объяснение. Прогон
## делает ровно то же — кнопкой, а не вызовом _finish_coach: сцена, у которой
## объяснение доигрывается только изнутри, для игрока ничем не отличается от
## сцены без объяснения.
func _play_journal_coach() -> void:
	var journal: Node = Game.journal
	if journal == null:
		_check("журнал: виджет на месте", false)
		return
	_check("обучение: до открытия журнала флаг не стоит",
		not bool(Game.meta.flags.get(Game.JOURNAL_FLAG, false)))

	journal.call("open")
	await _tree.process_frame
	await _tree.create_timer(0.3).timeout
	_check("обучение: подсказка появилась вместе со списком",
		bool(journal.call("coach_running")))

	## Список из json, и шагов в нём столько, сколько написано в контенте.
	var steps: int = ContentDB.tutorial("journal").get("steps", []).size()
	_check("обучение: шаги прочитаны из контента — %d" % steps, steps >= 4)

	var guard := 0
	while bool(journal.call("coach_running")) and guard <= steps + 2:
		guard += 1
		journal.call("_next_step")
		await _tree.create_timer(0.05).timeout
	_check("обучение: пролистано до конца кнопкой", not bool(journal.call("coach_running")))
	_check("обучение: флаг выставлен",
		bool(Game.meta.flags.get(Game.JOURNAL_FLAG, false)))
	journal.call("close")
	await _tree.create_timer(0.3).timeout


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


## --- процедурная комната ----------------------------------------------------
##
## Кадр прогон не проверяет — для этого есть room_shot. Здесь проверяется то,
## что кадром как раз НЕ видно: что комната собралась из данных, что область
## слота взялась у нарисованного элемента, а не осталась подогнанным вручную
## прямоугольником, и что смена состояния слота действительно переключает вид.
## Ошибка в любом из трёх выглядит на скриншоте нормально.

func _check_procedural_room() -> void:
	Game.open_shop("room_lab")
	await _tree.create_timer(0.4).timeout
	var scene: Node = Game.current()
	if scene == null or not ("_room" in scene):
		_check("комната: локация на процедурном интерьере открылась", false)
		return
	var room: RoomAssembler = scene._room
	_check("комната: интерьер собран из данных, а не из фона", room != null)
	if room == null:
		return

	_check("комната: три поверхности встали в кадр",
		room.geom.polygons.size() == RoomGeometry.SURFACES.size())
	for surface_id in RoomGeometry.SURFACES:
		var poly: PackedVector2Array = room.geom.polygons[surface_id]
		_check("комната: поверхность '%s' не выродилась (%d точек)" % [surface_id, poly.size()],
			poly.size() >= 3)

	## Перспектива: у пола дальний край обязан быть уже ближнего. Проверка
	## грубая намеренно — тонкости видны глазом, а вывернутая наизнанку
	## проекция глазом как раз выглядит правдоподобно.
	var far_left := room.geom.uv_to_screen(RoomGeometry.SURFACE_FLOOR, Vector2(0.0, 0.05))
	var far_right := room.geom.uv_to_screen(RoomGeometry.SURFACE_FLOOR, Vector2(1.0, 0.05))
	var near_left := room.geom.uv_to_screen(RoomGeometry.SURFACE_FLOOR, Vector2(0.0, 0.95))
	var near_right := room.geom.uv_to_screen(RoomGeometry.SURFACE_FLOOR, Vector2(1.0, 0.95))
	_check("комната: дальний край пола уже ближнего",
		absf(far_right.x - far_left.x) < absf(near_right.x - near_left.x))
	_check("комната: дальний край пола выше ближнего",
		far_left.y < near_left.y)

	## Гомография обратима: точка поверхности, переведённая на экран и обратно,
	## обязана вернуться в себя. Именно на этом стоит и раскладка плитки, и
	## попадание пальцем по стене.
	var h := room.geom.homography(RoomGeometry.SURFACE_RIGHT)
	var probe := Vector2(0.37, 0.62)
	var back := h.map_screen(h.map_uv(probe))
	_check("комната: отображение поверхности обратимо (ошибка %.4f)" % back.distance_to(probe),
		back.distance_to(probe) < 0.001)

	var slot_rect: Rect2 = room.element_rect("door_01")
	_check("комната: область двери взята у нарисованного элемента",
		slot_rect.size.x > 40.0 and slot_rect.size.y > 100.0)
	if "_slots" in scene:
		var slot: StateSlot = scene._slots.get("lab_door")
		_check("комната: хитбокс слота совпал с элементом",
			slot != null and slot.world_rect.is_equal_approx(slot_rect))

	## Дверь открывается существующей системой слотов — комната только
	## переключает вид. Отдельного механизма взаимодействия у неё нет.
	##
	## Тап идёт ЧЕРЕЗ хит-тест сцены, а не прямым вызовом interact: проверяется
	## именно то, что палец попадает туда, где комната нарисовала дверь. Прямой
	## вызов прошёл бы и при хитбоксе, уехавшем на полэкрана.
	_check("комната: дверь начинает закрытой",
		Game.meta.current_slot_state("room_lab", "lab_door") == "closed")
	## Рука пуста: правило двери описано под пустую руку, и оставшийся с прошлой
	## локации выбранный предмет молча увёл бы тап мимо всех правил.
	Game.clear_selection()
	var centre := slot_rect.position + slot_rect.size * 0.5
	_check("комната: центр двери попадает в её хитбокс",
		(scene._slots["lab_door"] as StateSlot).world_rect.has_point(centre))
	var touch := InputEventScreenTouch.new()
	## Событие приходит в экранных координатах, а сцена переводит их в мировые.
	## Подаём именно экранные — иначе проверка обошла бы ровно тот перевод,
	## на котором и ломается попадание пальцем.
	touch.position = scene.get_canvas_transform() * centre
	touch.pressed = true
	scene._unhandled_input(touch)
	await _tree.create_timer(0.3).timeout
	_check("комната: тап по центру нарисованной двери её открыл",
		Game.meta.current_slot_state("room_lab", "lab_door") == "open")

	var closed_view: Array = room._element_nodes.get("door_01", [])
	var open_view: Array = room._element_nodes.get("door_01_open", [])
	var closed_visible := not closed_view.is_empty() and (closed_view[0] as Node2D).visible
	var open_visible := not open_view.is_empty() and (open_view[0] as Node2D).visible
	_check("комната: закрытая дверь исчезла из кадра", not closed_visible)
	_check("комната: открытый проём появился", open_visible)

	## Зерно — это воспроизводимость: комната, которая после перезахода
	## выглядит иначе, была бы багом, а не разнообразием.
	var before := room.element_rect("left_wall_scatter_0")
	Game.open_shop("room_lab")
	await _tree.create_timer(0.4).timeout
	var again: RoomAssembler = Game.current()._room
	_check("комната: одно зерно — одна и та же раскладка",
		again.element_rect("left_wall_scatter_0").is_equal_approx(before))

	Game.meta.set_slot_state("room_lab", "lab_door", "closed")
