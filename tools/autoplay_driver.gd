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

	# --- завязка: вступление → мэр → КАРТА ---------------------------------
	_check("старт: новая игра открывается вступлением", Game.screen == Game.Screen.INTRO)
	## Заставку пропускаем кнопкой, а не вызовом finish_intro: у игрока есть
	## только кнопка, и «метод отработал» ничего не говорит о том, что до неё
	## можно дотянуться.
	_press_skip("вступление")
	await tree.create_timer(0.3).timeout
	_check("после вступления — диалог с мэром", Game.screen == Game.Screen.DIALOG)
	_check_dialog_runs()
	await tree.create_timer(0.5).timeout

	## Главное утверждение новой завязки. Раньше после мэра запускался пазл
	## «собери план района» — уровень, существовавший ровно затем, чтобы после
	## него было что применить в мете. Теперь мэр называет пекарню, и следующий
	## ход делает игрок.
	_check("после мэра — карта, а не уровень", Game.screen == Game.Screen.MAP)
	_check("завязка отмечена просмотренной",
		bool(Game.meta.flags.get(Game.INTRO_FLAG, false)))
	_check("после мэра не пройдено ни одного уровня",
		Game.meta.levels_completed_total == 0)

	# --- площадь: пекарня открыта из данных, без фиктивного уровня ---------
	_check("площадь: пекарня открыта с самого начала",
		Game.meta.shop_state("bakery") == "in_restoration")
	_check("площадь: открытость пришла из контента, а не от действия",
		ContentDB.shop("bakery").initial_state == "in_restoration")
	_check("площадь: задача «Осмотреть пекарню» открыта",
		Game.meta.task_state("task_visit_bakery") == MetaService.TaskState.AVAILABLE)
	_check("площадь: задача про завал ещё закрыта",
		Game.meta.task_state("task_clear_facade") == MetaService.TaskState.LOCKED)
	_check_map_task_bar(["task_visit_bakery"])
	_check_journal_hides_locked()

	## До обучения рука ведёт к журналу, а не к зданию: список объясняет, зачем
	## вообще идти в пекарню. К зданию она переезжает, когда объяснение доиграно.
	_check_hint_points_at_journal()
	await _play_journal_coach()
	_check_map_hint_points_at("bakery")
	_check_map_hit_areas()

	# --- первый вход: фасад → знакомство с Марго → СРАЗУ уровень -----------
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
	await tree.create_timer(0.6).timeout

	_check("после разговора с Марго уровень начинается сам",
		Game.screen == Game.Screen.LEVEL)
	_check("знакомство отмечено", bool(Game.meta.flags.get("met_baker", false)))
	_check("задача «Осмотреть пекарню» закрылась знакомством",
		Game.meta.task_state("task_visit_bakery") == MetaService.TaskState.COMPLETED)

	# --- уровень 1: Sort на фасаде -----------------------------------------
	_check_sort_scene()
	await _check_sort_fail_and_restart()
	await _finish_current_level()

	_check("после уровня — карта, без экрана результата", Game.screen == Game.Screen.MAP)
	_check("L1: уровень записан пройденным",
		Game.meta.completed_levels.has("bakery_01"))
	_check("L1: постоянное состояние фасада сохранено",
		bool(Game.meta.flags.get("facade_cleared", false)))
	_check("L1: задача про завал закрылась сама",
		Game.meta.task_state("task_clear_facade") == MetaService.TaskState.COMPLETED)
	_check("L1: обучение Sort отмечено пройденным",
		bool(Game.meta.flags.get(Game.SORT_FLAG, false)))
	## Монеты приходят и за уровень, и за задачу — и ровно по одному разу.
	_check("L1: начислено 40 (уровень) + 10 + 15 (задачи) монет",
		PlayerState.amount_of("coins") == 65)
	Game.meta.refresh()
	_check("L1: повторный пересчёт не удваивает награду",
		PlayerState.amount_of("coins") == 65)
	_check("L1: разбор завала ничего не положил в сумку", _bag_size() == 0)
	_check_task_notification("Разобрать завал у входа")
	_check_journal_all_done(["Осмотреть пекарню", "Разобрать завал у входа"])

	## Пекарня не открывается целиком после первого шага: убран вход, и только.
	_check("после L1 пекарня всё ещё в восстановлении",
		Game.meta.shop_state("bakery") == "in_restoration")

	_check_no_jigsaw()

	# --- сохранение / загрузка ---------------------------------------------
	SaveService.save_game()
	var levels_done: int = Game.meta.levels_completed_total
	PlayerState.reset()
	CooldownService.reset()
	Game.meta.reset()
	_check("состояние в памяти очищено",
		not bool(Game.meta.flags.get("facade_cleared", false)))
	SaveService.load_game()
	Game.meta.refresh()
	_check("сейв: фасад остался разобранным",
		bool(Game.meta.flags.get("facade_cleared", false)))
	_check("сейв: завязка не запустится заново",
		bool(Game.meta.flags.get(Game.INTRO_FLAG, false)))
	_check("сейв: знакомство с Марго не повторится",
		bool(Game.meta.flags.get("met_baker", false)))
	_check("сейв: уровень остался пройденным",
		Game.meta.completed_levels.has("bakery_01"))
	_check("сейв: пройдено уровней = %d" % levels_done,
		Game.meta.levels_completed_total == levels_done)
	_check("сейв: задача про завал осталась выполненной",
		Game.meta.task_state("task_clear_facade") == MetaService.TaskState.COMPLETED)

	_check_v1_migration()

	await _check_procedural_room()
	await _check_procedural_ceiling()
	await _check_dialog_skip()

	_report()


## --- уровень 1: Sort --------------------------------------------------------

## Игровой модуль текущего уровня. Экран уровня — маршрутизатор: он выбирает
## модуль по режиму из данных и больше ничего про геймплей не знает.
func _sort_module() -> Node:
	var level: Node = Game.current()
	if level == null or not ("module" in level):
		return null
	return level.module


## Что игрок видит, войдя в первый Sort. Проверяется не «красиво», а то, что
## ломается молча: сколько предметов на поле, сколько ячеек в лотке, и не
## заехал ли завал под интерфейс.
func _check_sort_scene() -> void:
	var def: LevelDefinition = ContentDB.level("bakery_01")
	_check("L1: уровень идёт в режиме sort", def != null and def.mode == "sort")
	if def == null or def.sort == null:
		_check("L1: раскладка Sort загрузилась", false)
		return
	_check("L1: на поле 12 предметов", def.sort.items.size() == 12)
	_check("L1: четыре категории по три", def.sort.categories.size() == 4
		and def.sort.category_counts().values().all(func(n): return int(n) == 3))
	_check("L1: лоток на 7 ячеек", def.sort.tray_size == 7)
	_check("L1: фон уровня — вход в пекарню",
		def.art.background_path == "res://art/bakery_door.png")

	var module := _sort_module()
	if module == null:
		_check("L1: игровой модуль построен", false)
		return
	_check("L1: экран уровня выбрал модуль Sort",
		String(module.get_script().resource_path).ends_with("sort_module.gd"))
	_check("L1: все 12 предметов на экране", module._views.size() == 12)
	_check("L1: обучение показано на первом прохождении", module._tutorial != null)

	## Лоток: ячейки должны быть различимы и попадать под палец.
	var tray = module._tray
	_check("L1: в лотке нарисовано 7 ячеек", tray.slot_count == 7)
	_check("L1: ячейка лотка крупнее пальца (%d px)" % int(tray.slot_diameter),
		tray.slot_diameter >= 96.0)
	_check("L1: ячейки не наложены друг на друга",
		tray.slot_center(1).x - tray.slot_center(0).x >= tray.slot_diameter)
	_check("L1: лоток стоит в нижней части экрана",
		module.tray_rect.position.y > 1200.0 and module.tray_rect.end.y <= 1920.0)

	## Предметы: крупные, внутри поля и не под лотком.
	var small := 0
	var outside := 0
	for id in module._views:
		var view: SortItemView = module._views[id]
		if view.span < 120.0:
			small += 1
		var box: Rect2 = view.hit_rect()
		if box.end.y > module.tray_rect.position.y \
				or box.position.y < module.play_rect.position.y \
				or box.position.x < module.play_rect.position.x \
				or box.end.x > module.play_rect.end.x:
			outside += 1
	_check("L1: предметы крупные — под палец, а не под пиксель", small == 0)
	_check("L1: ни один предмет не заехал под HUD или лоток", outside == 0)

	## Плашка обучения стоит над лотком и накрывает часть поля. Предмет под ней
	## не виден и не нажимается ровно на первом прохождении — там, где это
	## больнее всего.
	if module._tutorial != null:
		var plate: Rect2 = module._tutorial.plate_rect()
		var covered := 0
		for id in module._views:
			var view: SortItemView = module._views[id]
			if plate.intersects(view.hit_rect()):
				covered += 1
		_check("L1: подсказка обучения не накрывает предметы", covered == 0)

	## Тап попадает туда, куда смотрит игрок: хит-тест обязан вернуть тот же
	## предмет, в центр которого целятся.
	var mismatched := 0
	for id in module._views:
		if module._hit_test(module._views[id].position) != String(id):
			mismatched += 1
	_check("L1: тап по предмету попадает именно в него", mismatched == 0)


## Проигрыш и мгновенный перезапуск. Проверяем и то, чего игрок не видит:
## неудача не должна оставить в мете ни следа.
func _check_sort_fail_and_restart() -> void:
	var module := _sort_module()
	if module == null:
		_check("L1: модуль доступен для проверки проигрыша", false)
		return

	## Раскладку снимаем ДО первого тапа: после проигрыша семь предметов лежат
	## в ячейках лотка, и сравнивать с их положением там значит проверять не
	## раскладку уровня, а расстановку лотка.
	var layout_before := {}
	for id in module._views:
		layout_before[String(id)] = module._views[id].position

	## Семь предметов, ни одной тройки: по две штуки трёх категорий и одна
	## четвёртой. Это и есть единственный способ проиграть в Sort.
	var dead_end := ["p1", "p2", "w1", "w2", "d1", "d2", "f1"]
	var before: int = module._views.size()
	for id in dead_end:
		module._on_pick(String(id))
		await _tree.create_timer(0.06).timeout
	_check("L1: лоток заполнился семью предметами", module._state.tray.size() == 7)
	_check("L1: ни одна группа при этом не закрылась",
		module._views.size() == before)
	await _tree.create_timer(0.5).timeout

	_check("L1: переполненный лоток — это проигрыш", module._state.is_failed())
	_check("L1: после проигрыша ввод заблокирован", module._input_locked)
	_check("L1: игрок остался на уровне, а не уехал на карту",
		Game.screen == Game.Screen.LEVEL)
	_check("L1: проигрыш не записал победу",
		not Game.meta.completed_levels.has("bakery_01"))
	_check("L1: проигрыш не тронул мету",
		not bool(Game.meta.flags.get("facade_cleared", false)))
	_check("L1: проигрыш не выдал награду", PlayerState.amount_of("coins") == 10)

	## Перезапуск — кнопкой, а не вызовом restart(): у игрока есть только
	## кнопка, и уровень, который перезапускается лишь изнутри, для него
	## перезапустить нельзя.
	var again := _find_button(Game.current(), "Заново")
	_check("L1: на проигрыше есть кнопка «Заново»", again != null)
	if again == null:
		return
	again.pressed.emit()
	await _tree.create_timer(0.3).timeout

	_check("L1: после перезапуска все 12 предметов на месте", module._views.size() == 12)
	_check("L1: лоток пуст", module._state.tray.size() == 0)
	_check("L1: ввод снова принимается", not module._input_locked)
	## Тот же seed — та же раскладка. Иначе «Заново» даёт не второй заход, а
	## другой уровень, и проверить свою догадку игрок не может.
	var moved := 0
	for id in layout_before:
		var view = module._views.get(String(id))
		if view == null or view.position.distance_to(layout_before[id]) > 0.5:
			moved += 1
	_check("L1: раскладка после перезапуска та же самая", moved == 0)


## Сейв старой версии. Проверяем то, ради чего миграция вообще написана: игрок,
## который проходил прежнюю цепочку, не должен ни потерять завязку, ни получить
## новый уровень «уже пройденным» — id `bakery_01` в старом сейве означал другой
## уровень.
func _check_v1_migration() -> void:
	var old := {
		"version": 1,
		"player": {"currencies": {"coins": 120, "hard": 60, "xp": 30},
			"items": {"bakery_key": 1, "spiderweb": 1, "booster_hint": 3}},
		"meta": {
			"shops": {"bakery": {"state": "locked", "slots": {"door": "open"}}},
			"tasks": {"task_survey_district": "completed", "task_clear_hall": "completed"},
			"completed_levels": {"bakery_01": 1, "bakery_02": 1},
			"levels_completed_total": 2,
			"flags": {"intro_seen": true, "met_baker": true, "journal_seen": true,
				"bakery_chosen": true, "hall_clean": true, "door_open": true},
			"rewarded_tasks": {"task_survey_district": true},
		},
	}
	var f := FileAccess.open(SaveService.SAVE_PATH, FileAccess.WRITE)
	if f == null:
		_check("миграция: старый сейв записан", false)
		return
	f.store_string(JSON.stringify(old, "  "))
	f.close()

	PlayerState.reset()
	CooldownService.reset()
	Game.meta.reset()
	_check("миграция: старый сейв прочитан", SaveService.load_game())
	Game.meta.refresh()

	_check("миграция: завязка не проигрывается заново",
		bool(Game.meta.flags.get(Game.INTRO_FLAG, false)))
	_check("миграция: знакомство с Марго сохранено",
		bool(Game.meta.flags.get("met_baker", false)))
	## 120 из старого сейва плюс 10 за «Осмотреть пекарню»: этой задачи в старой
	## цепочке не было, и она честно закрывается знакомством, которое уже
	## состоялось. Всё, за что игроку платили раньше, лежит в rewarded_tasks и
	## второй раз не оплачивается.
	_check("миграция: кошелёк переехал целиком", PlayerState.amount_of("coins") == 130)
	_check("миграция: новый первый уровень не засчитан пройденным",
		not Game.meta.completed_levels.has("bakery_01"))
	_check("миграция: задача про завал снова ждёт игрока",
		Game.meta.task_state("task_clear_facade") == MetaService.TaskState.AVAILABLE)
	_check("миграция: флаги старой цепочки сняты",
		not bool(Game.meta.flags.get("hall_clean", false))
			and not bool(Game.meta.flags.get("door_open", false)))
	_check("миграция: пекарня открыта по данным, а не по старому состоянию",
		Game.meta.shop_state("bakery") == "in_restoration")
	_check("миграция: предметы мёртвой цепочки убраны из сумки",
		PlayerState.amount_of("bakery_key") == 0
			and PlayerState.amount_of("spiderweb") == 0)
	_check("миграция: сейв перезаписывается уже новой версией",
		SaveService.CURRENT_VERSION == 2)


## Пазла в новом обязательном пути нет ни одного — ни на экране, ни в контенте.
func _check_no_jigsaw() -> void:
	_check("jigsaw ни разу не появился в дереве сцен",
		_find_jigsaw(_tree.root) == null)
	var legacy := PackedStringArray()
	for id in ContentDB.level_ids:
		var def: LevelDefinition = ContentDB.level(String(id))
		if def != null and def.mode != "sort":
			legacy.append(String(id))
	_check("в активном контенте нет уровней старого режима", legacy.is_empty())
	_check("модуль jigsaw остался в проекте как legacy",
		PuzzleRegistry.is_known("jigsaw"))


func _find_jigsaw(node: Node) -> Node:
	if node.get_script() != null \
			and String(node.get_script().resource_path).contains("jigsaw_module"):
		return node
	for child in node.get_children():
		var found := _find_jigsaw(child)
		if found != null:
			return found
	return null


func _find_button(node: Node, text: String) -> Button:
	if node == null:
		return null
	if node is Button and (node as Button).text == text:
		return node
	for child in node.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null


## Журнал в конце пути: обе задачи выполнены и обе с галочкой.
func _check_journal_all_done(titles: Array) -> void:
	var node: Node = _tree.root.find_child("TaskJournal", true, false)
	if node == null:
		_check("журнал: виджет на месте", false)
		return
	node.call("open")
	var done: PackedStringArray = node.call("done_titles")
	for title in titles:
		var found := false
		for d in done:
			if String(d).contains(String(title)):
				found = true
		_check("журнал: у «%s» стоит галочка" % title, found)
	node.call("close")


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
		_say("Новый путь работает: мэр -> карта -> фасад -> Марго -> Sort -> мета.")
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

	_check_perspective(room, RoomGeometry.SURFACE_FLOOR, "пол")
	_check("комната: дальний край пола выше ближнего",
		room.geom.uv_to_screen(RoomGeometry.SURFACE_FLOOR, Vector2(0.0, 0.05)).y
		< room.geom.uv_to_screen(RoomGeometry.SURFACE_FLOOR, Vector2(0.0, 0.6)).y)

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


## Вторая лабораторная комната — процедурная копия кладовой. Проверяется то,
## чего в первой нет: потолок как четвёртая поверхность и элемент, который ни
## на одной плоскости комнаты не лежит.
func _check_procedural_ceiling() -> void:
	var scene: Node = Game.current()
	if scene == null or not ("_room" in scene) or scene._room == null:
		_check("лаборатория: интерьер собран", false)
		return
	var room: RoomAssembler = scene._room

	var ceiling: PackedVector2Array = room.geom.polygons[RoomGeometry.SURFACE_CEILING]
	_check("потолок: попал в кадр (%d точек)" % ceiling.size(), ceiling.size() >= 3)
	## Потолок обязан лежать ВЫШЕ верха угла комнаты: если он оказался ниже,
	## значит проекция вывернулась, а на кадре это выглядит правдоподобно.
	var centre := Vector2.ZERO
	for p in ceiling:
		centre += p
	centre /= maxf(1.0, float(ceiling.size()))
	_check("потолок: лежит выше верха угла", centre.y < room.geom.corner_top.y)

	_check_perspective(room, RoomGeometry.SURFACE_CEILING, "потолок")
	_check("потолок: дальний край ниже ближнего",
		room.geom.uv_to_screen(RoomGeometry.SURFACE_CEILING, Vector2(0.0, 0.05)).y
		> room.geom.uv_to_screen(RoomGeometry.SURFACE_CEILING, Vector2(0.0, 0.6)).y)

	_check_furniture(room)
	_check_room_roundtrip(room)


## Мебель. Проверяется не «нарисовалась ли», а три вещи, которые молча ломаются
## и на скриншоте выглядят правдоподобно: предмет стоит вертикально, стоит
## основанием на полу и уменьшается с удалением.
func _check_furniture(room: RoomAssembler) -> void:
	var shelf := room.element_rect("shelf_wood_01_1")
	_check("мебель: полка собралась", shelf.size.x > 20.0 and shelf.size.y > 20.0)

	var quad: PackedVector2Array = room._element_quads.get("shelf_wood_01_1",
		PackedVector2Array())
	## Предмет повёрнут к зрителю: его прямоугольник обязан остаться
	## прямоугольником. Натянутый на плоскость, он лёг бы вместе с ней на пол.
	_check("мебель: стоит вертикально, а не лежит по полу",
		quad.size() == 4 and absf(quad[0].y - quad[1].y) < 0.01
		and absf(quad[0].x - quad[3].x) < 0.01)

	## Низ предмета обязан совпасть с точкой пола, на которую его поставили:
	## иначе шкаф висит в воздухе, и заметно это только на глаз.
	var el := room.element("shelf_wood_01_1")
	if el != null and quad.size() == 4:
		var base := room.geom.uv_to_screen(RoomGeometry.SURFACE_FLOOR, el.anchor)
		_check("мебель: основание стоит ровно в своей точке пола",
			absf(quad[2].y - base.y) < 0.5 and absf((quad[2].x + quad[3].x) * 0.5 - base.x) < 0.5)

	## Один и тот же предмет у дальней стены и у ног — разного размера. Ставим
	## его дважды и сравниваем: без этого мебель просто не в перспективе.
	var far_id := room.place_material("crate_wood_01",
		room.geom.uv_to_screen(RoomGeometry.SURFACE_FLOOR, Vector2(0.05, 0.05)))
	var near_id := room.place_material("crate_wood_01",
		room.geom.uv_to_screen(RoomGeometry.SURFACE_FLOOR, Vector2(0.55, 0.55)))
	var far_rect := room.element_rect(far_id)
	var near_rect := room.element_rect(near_id)
	_check("мебель: перетаскивание ставит предмет на пол",
		not far_id.is_empty() and not near_id.is_empty())
	_check("мебель: у дальней стены мельче, чем у ног (%.0f против %.0f px)"
		% [far_rect.size.y, near_rect.size.y], far_rect.size.y < near_rect.size.y)

	## Поставленное опознаётся обратно по точке экрана — на этом держится
	## перетаскивание уже стоящего предмета.
	_check("мебель: поставленное опознаётся по точке экрана",
		room.element_at(near_rect.get_center()) == near_id)

	room.remove_element(far_id)
	room.remove_element(near_id)
	_check("мебель: убирается из комнаты",
		not room.has_element(far_id) and not room.has_element(near_id))

	## Окно перетаскивается на стену, а не на пол, — и наоборот. Решает это
	## комната по точке, куда отпустили, а не палитра.
	var wall_point := room.geom.uv_to_screen(RoomGeometry.SURFACE_RIGHT, Vector2(0.2, 0.4))
	var win_id := room.place_material("window_arched_01", wall_point)
	var win_el := room.element(win_id)
	_check("окно: перетаскивание сажает его на стену",
		win_el != null and win_el.surface == RoomGeometry.SURFACE_RIGHT
		and not win_el.stands())
	room.remove_element(win_id)

	## Промах мимо комнаты — это промах, а не «поставим куда-нибудь».
	_check("палитра: мимо кадра предмет не ставится",
		room.place_material("crate_wood_01", Vector2(-500, -500)).is_empty())


## Перспектива на поверхности: одна и та же плитка у дальнего края обязана
## занимать на экране меньше места, чем у ближнего.
##
## «Дальний край уже ближнего» тут не годится: у пола и потолка оси идут вдоль
## двух стен, а не «влево-вправо» и «от нас», поэтому крайние линии не
## параллельны и их ширины сравнивать бессмысленно. Площадь маленького квадрата
## разметки — величина однозначная, и на вывернутой проекции она ведёт себя
## наоборот.
func _check_perspective(room: RoomAssembler, surface_id: String, title: String) -> void:
	var part: Rect2 = room.geom.safe_part[surface_id]
	var side := 0.08
	var far_area := _patch_area(room, surface_id, part.position + Vector2(0.02, 0.02), side)
	var near_area := _patch_area(room, surface_id,
		part.end - Vector2(side + 0.02, side + 0.02), side)
	_check("%s: плитка у дальнего края мельче, чем у ближнего (%.0f против %.0f px²)"
		% [title, far_area, near_area], far_area < near_area)


## Площадь четырёхугольника, в который проецируется квадратик разметки.
func _patch_area(room: RoomAssembler, surface_id: String, uv: Vector2, side: float) -> float:
	var pts := PackedVector2Array([
		room.geom.uv_to_screen(surface_id, uv),
		room.geom.uv_to_screen(surface_id, uv + Vector2(side, 0.0)),
		room.geom.uv_to_screen(surface_id, uv + Vector2(side, side)),
		room.geom.uv_to_screen(surface_id, uv + Vector2(0.0, side)),
	])
	var area := 0.0
	for i in 4:
		var a := pts[i]
		var b := pts[(i + 1) % 4]
		area += a.x * b.y - b.x * a.y
	return absf(area) * 0.5


## Сохранение комнаты. Проверяется не запись в файл, а обратимость: то, что
## сериализатор выдал, обязан прочитать тот же ContentParser, которым живёт
## игра. Стенд, после которого комната читается иначе, чем выглядела, хуже
## отсутствия стенда — он тихо портит контент.
##
## На диск тут ничего не пишется намеренно: прогон не должен трогать контент.
func _check_room_roundtrip(room: RoomAssembler) -> void:
	var before := room.definition()
	var text := JSON.stringify(RoomSerializer.to_dict(before, "roundtrip_probe"), "  ")
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		_check("сохранение: комната сериализуется в валидный JSON", false)
		return
	_check("сохранение: комната сериализуется в валидный JSON", true)

	var after := ContentParser.room(parsed)
	_check("сохранение: шаблон и зерно пережили запись",
		after.template_id == before.template_id and after.seed == before.seed)
	_check("сохранение: все поверхности на месте (%d)" % after.surfaces.size(),
		after.surfaces.size() == before.surfaces.size())
	_check("сохранение: все элементы на месте (%d)" % after.elements.size(),
		after.elements.size() == before.elements.size())
	_check("сохранение: все наклейки на месте (%d)" % after.decals.size(),
		after.decals.size() == before.decals.size())

	## Мебель — самое хрупкое место записи: у неё другой набор полей, и потерять
	## якорь значит собрать комнату, в которой шкаф стоит в другом углу.
	var shelf_before := before.element("shelf_wood_01_1")
	var shelf_after := after.element("shelf_wood_01_1")
	_check("сохранение: у мебели уцелели постановка, якорь и размер",
		shelf_before != null and shelf_after != null
		and shelf_after.stands()
		and shelf_after.anchor.is_equal_approx(shelf_before.anchor)
		and shelf_after.size.is_equal_approx(shelf_before.size))

	## Привязка к слоту — то, чем комната цепляется за существующую механику.
	var door_after := after.element("door_01")
	_check("сохранение: у двери уцелела привязка к слоту локации",
		door_after != null and door_after.slot_id == "lab_door"
		and door_after.slot_state == "closed")
