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

	## Объяснение журнала выключено в контенте, и указатель обязан это уважать:
	## рука ведёт прямо к пекарне, а не к кнопке списка, за которой ничего не
	## произойдёт.
	_check("обучение журналу выключено контентом", not Game.journal_coach_pending())
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

	## После победы игрок попадает не в мету, а в разговор: эффект выполненного
	## действия попросил показать сцену. Кто что говорит — написано в контенте,
	## Game про это не знает.
	_check("после L1 — две реплики, а не сразу мета", Game.screen == Game.Screen.DIALOG)
	_check("L1: уровень записан пройденным",
		Game.meta.completed_levels.has("bakery_01"))
	_check("L1: постоянное состояние фасада сохранено",
		bool(Game.meta.flags.get("facade_cleared", false)))
	_check("L1: задача про завал закрылась сама",
		Game.meta.task_state("task_clear_facade") == MetaService.TaskState.COMPLETED)
	_check("L1: обучение Sort отмечено пройденным",
		bool(Game.meta.flags.get(Game.tutorial_flag("sort_basics"), false)))
	## Монеты приходят и за уровень, и за задачу — и ровно по одному разу.
	_check("L1: начислено 40 (уровень) + 10 + 15 (задачи) монет",
		PlayerState.amount_of("coins") == 65)
	Game.meta.refresh()
	_check("L1: повторный пересчёт не удваивает награду",
		PlayerState.amount_of("coins") == 65)
	_check("L1: разбор завала ничего не положил в сумку", _bag_size() == 0)

	## Пекарня не открывается целиком после первого шага: убран вход, и только.
	_check("после L1 пекарня всё ещё в восстановлении",
		Game.meta.shop_state("bakery") == "in_restoration")
	_check("после L1 зал ещё завален",
		Game.meta.current_slot_state("bakery", "hall") == "facade")

	# --- разговор между уровнями и сразу второй уровень ---------------------
	_check_dialog_runs()
	await tree.create_timer(0.6).timeout
	_check("после разговора второй уровень начинается сам",
		Game.screen == Game.Screen.LEVEL)

	# --- уровень 2: Sort в торговом зале ------------------------------------
	_check_hall_scene()
	await _check_hall_blockers()
	await _check_hall_fail_and_restart()
	await _finish_current_level()

	_check("после L2 — две реплики про витрину и кладовую",
		Game.screen == Game.Screen.DIALOG)
	_check("L2: уровень записан пройденным",
		Game.meta.completed_levels.has("bakery_02"))
	_check("L2: постоянное состояние зала сохранено",
		bool(Game.meta.flags.get("hall_cleared_stage_1", false)))
	_check("L2: задача про зал закрылась сама",
		Game.meta.task_state("task_clear_hall") == MetaService.TaskState.COMPLETED)
	_check("L2: зал перешёл в первое восстановленное состояние",
		Game.meta.current_slot_state("bakery", "hall") == "stage_1")
	_check("L2: предупреждение про лоток отмечено показанным",
		bool(Game.meta.flags.get(Game.tutorial_flag("sort_tray_risk"), false)))
	_check("L2: начислено 40+70 за уровни и 10+15+25 за задачи",
		PlayerState.amount_of("coins") == 160)

	## Разговор про витрину и кладовую сам открывает следующий шаг: последняя
	## реплика несёт play_task, и третий уровень начинается без единой строки
	## маршрутизации в коде.
	_check_dialog_runs()
	await tree.create_timer(0.6).timeout
	_check("после разговора про кладовую третий уровень начинается сам",
		Game.screen == Game.Screen.LEVEL)

	# --- уровень 3: Sort у витрины, перекрытия как содержание ---------------
	_check_showcase_scene()
	await _check_showcase_blockers()
	await _check_showcase_roomy_path()
	await _check_showcase_fail_and_restart()
	await _finish_current_level()

	_check("после L3 — две реплики про дверь в кладовую",
		Game.screen == Game.Screen.DIALOG)
	_check("L3: уровень записан пройденным",
		Game.meta.completed_levels.has("bakery_03"))
	_check("L3: постоянное состояние витрины сохранено",
		bool(Game.meta.flags.get("hall_showcase_cleared", false)))
	_check("L3: задача про витрину закрылась сама",
		Game.meta.task_state("task_clear_showcase") == MetaService.TaskState.COMPLETED)
	_check("L3: зал перешёл во второе восстановленное состояние",
		Game.meta.current_slot_state("bakery", "hall") == "stage_2")
	_check("L3: объяснение перекрытий отмечено показанным",
		bool(Game.meta.flags.get(Game.tutorial_flag("sort_blockers"), false)))
	_check("L3: начислено 40+70+95 за уровни и 10+15+25+35 за задачи",
		PlayerState.amount_of("coins") == 290)
	## Дверь ещё завалена: подойти к ней нельзя, и тапать по ней тоже.
	_check("после L3 дверь кладовой ещё недоступна",
		Game.meta.current_slot_state("bakery", "storeroom_door") == "blocked")

	## Разговор про дверь сам открывает следующую работу — как и два прошлых.
	_check_dialog_runs()
	await tree.create_timer(0.6).timeout
	_check("после разговора про дверь четвёртый уровень начинается сам",
		Game.screen == Game.Screen.LEVEL)

	# --- уровень 4: Sort с закрытой зоной ----------------------------------
	_check_approach_scene()
	await _check_approach_zone()
	await _check_approach_roomy_path()
	await _check_approach_fail_and_restart()
	await _finish_current_level()

	_check("L4: уровень записан пройденным",
		Game.meta.completed_levels.has("bakery_04"))
	_check("L4: постоянное состояние подхода сохранено",
		bool(Game.meta.flags.get("storeroom_approach_cleared", false)))
	_check("L4: задача про подход закрылась сама",
		Game.meta.task_state("task_clear_approach") == MetaService.TaskState.COMPLETED)
	_check("L4: зал перешёл в последнее восстановленное состояние",
		Game.meta.current_slot_state("bakery", "hall") == "stage_3")
	_check("L4: объяснение зон отмечено показанным",
		bool(Game.meta.flags.get(Game.tutorial_flag("sort_zones"), false)))
	_check("L4: начислено 40+70+95+120 за уровни и 10+15+25+35+45 за задачи",
		PlayerState.amount_of("coins") == 455)
	## Разговора сразу после уровня нет намеренно: игрок выходит к двери и сам
	## решает, дёргать ли её. Сцена, начатая без его действия, отобрала бы у
	## этого шага единственное, что в нём есть.
	_check("после L4 игрок сразу в пекарне, без сцены", Game.screen == Game.Screen.SHOP)
	_check_hall_repainted("stage_3")

	# --- дверь кладовой: доступна, но заперта -------------------------------
	await _check_storeroom_door()

	_check_journal_all_done(["Осмотреть пекарню", "Разобрать завал у входа",
		"Расчистить торговый зал", "Освободить витрину",
		"Разобрать подход к кладовой", "Проверить дверь кладовой"])

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
	Game.meta.refresh_after_load()
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
	_check("сейв: зал остался расчищенным",
		bool(Game.meta.flags.get("hall_cleared_stage_1", false)))
	## Слот у зала один, и он показывает ПОСЛЕДНЕЕ достигнутое состояние, а не
	## каждое по очереди. После третьего уровня это stage_2, и проверять здесь
	## надо не конкретный шаг, а то, что зал не откатился к завалу.
	_check("сейв: локация не вернулась к заваленному залу",
		Game.meta.current_slot_state("bakery", "hall") != "facade")
	_check("сейв: второй уровень остался пройденным",
		Game.meta.completed_levels.has("bakery_02"))
	_check("сейв: витрина осталась освобождённой",
		bool(Game.meta.flags.get("hall_showcase_cleared", false)))
	_check("сейв: локация показывает последнее восстановленное состояние зала",
		Game.meta.current_slot_state("bakery", "hall") == "stage_3")
	_check("сейв: третий уровень остался пройденным",
		Game.meta.completed_levels.has("bakery_03"))
	_check("сейв: объяснение перекрытий больше не повторится",
		bool(Game.meta.flags.get(Game.tutorial_flag("sort_blockers"), false)))
	_check("сейв: подход к кладовой остался разобранным",
		bool(Game.meta.flags.get("storeroom_approach_cleared", false)))
	_check("сейв: четвёртый уровень остался пройденным",
		Game.meta.completed_levels.has("bakery_04"))
	## Главное, чего перезагрузка не должна сделать: ни отменить работу, ни
	## доделать её за игрока. Дверь как была заперта, так и осталась, ключа нет.
	_check("сейв: дверь кладовой доступна, но по-прежнему заперта",
		Game.meta.current_slot_state("bakery", "storeroom_door") == "locked")
	_check("сейв: ключ не появился сам собой", PlayerState.amount_of("bakery_key") == 0)
	_check("сейв: отметка о проверенной двери на месте",
		bool(Game.meta.flags.get("storeroom_door_tried", false)))
	_check("сейв: объяснение зон больше не повторится",
		bool(Game.meta.flags.get(Game.tutorial_flag("sort_zones"), false)))

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
	## Кратность, а не «ровно три»: категория вполне может уходить двумя
	## тройками, и такой контент не должен выглядеть поломкой.
	_check("L1: четыре категории, и каждая делится на тройки",
		def.sort.categories.size() == 4
		and def.sort.category_counts().values().all(func(n): return int(n) % 3 == 0))
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


## Состояние в мете и картинка на экране — разные вещи, и расходятся они молча.
## Проверяем не «флаг стоит», а что локация действительно показывает другой зал:
## слот нашёл свою текстуру и включил именно её вариант.
func _check_hall_repainted(expected_state: String = "stage_1") -> void:
	var slot := _find_node_named(Game.current(), "Slot_hall")
	if slot == null:
		_check("зал: слот вида локации есть в сцене", false)
		return
	var shown := ""
	var textured := false
	for child in slot.get_children():
		if not (child is Node2D) or not (child as Node2D).visible:
			continue
		shown = child.name
		for grand in child.get_children():
			if grand is Sprite2D and (grand as Sprite2D).texture != null:
				textured = true
	_check("зал: локация переключилась на восстановленный вид (%s)" % shown,
		shown == expected_state)
	_check("зал: у нового вида есть своя картинка, а не заглушка", textured)


func _find_node_named(node: Node, wanted: String) -> Node:
	if node == null:
		return null
	if node.name == wanted:
		return node
	for child in node.get_children():
		var found := _find_node_named(child, wanted)
		if found != null:
			return found
	return null


## --- уровень 2: тот же Sort, но с порядком ходов ---------------------------

func _check_hall_scene() -> void:
	var def: LevelDefinition = ContentDB.level("bakery_02")
	_check("L2: уровень идёт в режиме sort", def != null and def.mode == "sort")
	if def == null or def.sort == null:
		_check("L2: раскладка Sort загрузилась", false)
		return
	_check("L2: сборки из кусков в зале нет", def.puzzle.module_id.is_empty())
	_check("L2: старой уборки инструментами в зале нет", def.cleanup.is_empty())
	_check("L2: предметы не ищут — фазы поиска нет", def.hidden_object.targets.is_empty())
	_check("L2: на поле 18 предметов", def.sort.items.size() == 18)
	_check("L2: шесть категорий по три",
		def.sort.categories.size() == 6
		and def.sort.category_counts().size() == 6
		and def.sort.category_counts().values().all(func(n): return int(n) == 3))
	_check("L2: лоток по-прежнему на 7 ячеек", def.sort.tray_size == 7)

	var blocked := 0
	for inst in def.sort.items:
		if not inst.blocked_by.is_empty():
			blocked += 1
	_check("L2: часть предметов накрыта (%d из 18)" % blocked, blocked >= 5 and blocked <= 8)

	## Доступных с самого начала должно быть много: уровень про выбор порядка, а
	## не про поиск единственного возможного хода.
	var state := SortState.new()
	state.setup(def.sort)
	var open_now: int = state.available_ids().size()
	_check("L2: сразу доступно %d предметов" % open_now, open_now >= 10 and open_now <= 13)

	var module := _sort_module()
	if module == null:
		_check("L2: модуль уровня доступен", false)
		return
	_check("L2: на экране ровно 18 предметов", module._views.size() == 18)
	_check("L2: лоток нарисован на 7 ячеек", module._tray.slot_count == 7)

	## Восемнадцать предметов тесно стоят на одном экране, и проверка «не уехал
	## под интерфейс» здесь нужнее, чем на первом уровне: место кончается раньше,
	## чем это заметно глазом на одном разрешении.
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
	_check("L2: предметы крупные — под палец, а не под пиксель", small == 0)
	_check("L2: ни один предмет не заехал под HUD или лоток", outside == 0)


## Блокировки: накрытый предмет не берётся, а после ухода блокера — берётся.
## Проверяется через модуль, а не через голое состояние: тап игрока проходит
## через попадание и через запрет, и сломаться может любой из двух.
func _check_hall_blockers() -> void:
	var module := _sort_module()
	if module == null:
		return
	var def: LevelDefinition = ContentDB.level("bakery_02")

	## Кастрюля лежит под смятой банкой — до банки её не взять.
	_check("L2: накрытый предмет недоступен", not module._state.is_available("f2"))
	module._on_pick("f2")
	await _tree.create_timer(0.1).timeout
	_check("L2: тап по накрытому предмету ничего не делает",
		module._state.tray.is_empty() and module._views.size() == 18)

	## Верхний предмет забирает тап себе, даже если попали в перекрытие.
	var pot_view: SortItemView = module._views.get("f2")
	if pot_view != null:
		var overlap: Vector2 = (pot_view.position + module._views["s1"].position) * 0.5
		_check("L2: в перекрытии тап достаётся верхнему предмету",
			module._hit_test(overlap) == "s1")

	module._on_pick("s1")
	await _tree.create_timer(0.3).timeout
	_check("L2: снятый блокер открывает предмет под собой",
		module._state.is_available("f2"))

	## Возвращаем уровень в исходное состояние: дальше его проверяют с начала.
	module.restart()
	await _tree.create_timer(0.3).timeout
	_check("L2: перезапуск вернул все 18 предметов", module._views.size() == 18)
	_check("L2: все блокировки на месте", not module._state.is_available("f2"))
	## Раскладка та же самая — иначе «Заново» даёт другой уровень.
	var moved := 0
	for inst in def.sort.items:
		var view: SortItemView = module._views.get(inst.id)
		if view == null:
			moved += 1
			continue
		if absf(view.position.x - (module.play_rect.position.x
				+ inst.position.x * module.play_rect.size.x)) > 0.5:
			moved += 1
	_check("L2: раскладка после перезапуска совпадает с данными", moved == 0)


## Проигрыш во втором уровне достижим гораздо легче первого: шесть категорий
## против четырёх, и «беру всё подряд» упирается в лоток уже на седьмом ходу.
func _check_hall_fail_and_restart() -> void:
	var module := _sort_module()
	if module == null:
		return
	## По одному предмету из шести категорий плюс седьмой: ни одной тройки.
	var greedy := ["w1", "f1", "p1", "d1", "b1", "s1", "w2"]
	for id in greedy:
		module._on_pick(String(id))
		await _tree.create_timer(0.06).timeout
	_check("L2: набор вразнобой заполнил лоток", module._state.tray.size() == 7)
	await _tree.create_timer(0.5).timeout
	_check("L2: переполненный лоток — проигрыш", module._state.is_failed())
	_check("L2: после проигрыша ввод заблокирован", module._input_locked)
	_check("L2: проигрыш не записал победу",
		not Game.meta.completed_levels.has("bakery_02"))
	_check("L2: проигрыш не тронул мету",
		not bool(Game.meta.flags.get("hall_cleared_stage_1", false)))

	var again := _find_button(Game.current(), "Заново")
	_check("L2: на проигрыше есть кнопка «Заново»", again != null)
	if again == null:
		return
	again.pressed.emit()
	await _tree.create_timer(0.3).timeout
	_check("L2: после перезапуска поле снова полное",
		module._views.size() == 18 and module._state.tray.is_empty())
	_check("L2: ввод снова принимается", not module._input_locked)


## --- уровень 3: тот же Sort, но перекрытия стали содержанием ---------------

func _check_showcase_scene() -> void:
	var def: LevelDefinition = ContentDB.level("bakery_03")
	_check("L3: уровень идёт в режиме sort", def != null and def.mode == "sort")
	if def == null or def.sort == null:
		_check("L3: раскладка Sort загрузилась", false)
		return
	_check("L3: сборки из кусков у витрины нет", def.puzzle.module_id.is_empty())
	_check("L3: старой уборки инструментами у витрины нет", def.cleanup.is_empty())
	_check("L3: предметы не ищут — фазы поиска нет", def.hidden_object.targets.is_empty())
	_check("L3: на поле 21 предмет", def.sort.items.size() == 21)
	_check("L3: лоток по-прежнему на 7 ячеек", def.sort.tray_size == 7)
	_check("L3: фон — зал в том состоянии, в котором его оставил второй уровень",
		def.art.background_path == "res://art/bakery_interior_floor.jpg")

	## Шесть категорий и семь троек: одна категория идёт двумя группами. Это и
	## есть способ получить 21 предмет, не выдумывая седьмой смысл.
	var counts := def.sort.category_counts()
	_check("L3: шесть категорий, каждая делится на тройки",
		def.sort.categories.size() == 6 and counts.size() == 6
		and counts.values().all(func(n): return int(n) % 3 == 0))
	var groups := 0
	var doubled := ""
	for cid in counts:
		groups += int(counts[cid]) / 3
		if int(counts[cid]) == 6:
			doubled = String(cid)
	_check("L3: всего семь групп", groups == 7)
	_check("L3: удвоена ровно одна категория (%s)" % doubled, doubled == "trash")

	## Два слоя, не три: «убери, чтобы убрать, чтобы взять» — правило, которого
	## игроку никто не объяснял.
	var layers := {}
	var blocked := 0
	for inst in def.sort.items:
		layers[inst.layer] = true
		if not inst.blocked_by.is_empty():
			blocked += 1
	_check("L3: слоёв ровно два", layers.size() == 2)
	_check("L3: накрыто %d предметов из 21" % blocked, blocked == 8)

	## Перекрытия — главная механика уровня, и её обязано быть заметно больше,
	## чем во втором зале, иначе третий уровень ничему новому не учит.
	var state := SortState.new()
	state.setup(def.sort)
	var open_now: int = state.available_ids().size()
	_check("L3: сразу доступно %d предметов" % open_now, open_now == 13)

	## Ни одной категории, кроме мусора, нельзя закрыть, ничего не разобрав:
	## третий предмет всегда лежит под чужим блокером. Ровно отсюда берётся
	## вопрос уровня — «что убрать, чтобы стало можно взять».
	var open_by_category := {}
	for id in state.available_ids():
		var inst := def.sort.item(String(id))
		open_by_category[inst.category] = int(open_by_category.get(inst.category, 0)) + 1
	var closable := PackedStringArray()
	for cid in open_by_category:
		if int(open_by_category[cid]) >= 3:
			closable.append(String(cid))
	_check("L3: с ходу закрывается только мусор — остальное надо откапывать",
		closable.size() == 1 and closable[0] == "trash")

	var module := _sort_module()
	if module == null:
		_check("L3: модуль уровня доступен", false)
		return
	_check("L3: на экране ровно 21 предмет", module._views.size() == 21)
	_check("L3: лоток нарисован на 7 ячеек", module._tray.slot_count == 7)

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
	_check("L3: предметы крупные — под палец, а не под пиксель", small == 0)
	_check("L3: ни один предмет не заехал под HUD или лоток", outside == 0)

	## Двадцать один предмет на одном экране — место кончается раньше, чем это
	## видно глазом. Пересекаться вправе только те, кто друг друга держит:
	## случайное наложение делает тап лотереей.
	var stray := PackedStringArray()
	for a in def.sort.items:
		for b in def.sort.items:
			if a.id >= b.id:
				continue
			if a.blocked_by.has(b.id) or b.blocked_by.has(a.id):
				continue
			var va: SortItemView = module._views.get(a.id)
			var vb: SortItemView = module._views.get(b.id)
			if va != null and vb != null and va.hit_rect().intersects(vb.hit_rect()):
				stray.append("%s+%s" % [a.id, b.id])
	_check("L3: пересекаются только те предметы, что друг друга держат (%s)"
		% ("нет лишних" if stray.is_empty() else " ".join(stray)), stray.is_empty())


## Перекрытия в деле: накрытый предмет не берётся, отказ виден, подсказка
## приходит ровно один раз, а двойная блокировка снимается только целиком.
func _check_showcase_blockers() -> void:
	var module := _sort_module()
	if module == null:
		return

	## Гаечный ключ лежит под картонной коробкой — прямая одиночная блокировка.
	_check("L3: накрытый предмет недоступен", not module._state.is_available("wrench"))
	module._on_pick("wrench")
	await _tree.create_timer(0.1).timeout
	_check("L3: тап по накрытому предмету ничего не кладёт в лоток",
		module._state.tray.is_empty() and module._views.size() == 21)
	## Отказ — это событие, а не тишина: по нему приходит единственная подсказка
	## уровня, и приходит она в тот момент, когда игрок в перекрытие упёрся.
	_check("L3: отказ засчитан", module._refused == 1)
	if module._tutorial != null:
		_check("L3: подсказка про перекрытия показана первым же отказом",
			module._tutorial._shown.has("first_blocked_item_attempt"))
		## Плашка стоит над завалом, а не на нём: объяснение, накрывшее собой
		## то, что объясняет, — худший вид подсказки.
		var plate: Rect2 = module._tutorial.plate_rect()
		var covered := 0
		for id in module._views:
			if plate.intersects((module._views[id] as SortItemView).hit_rect()):
				covered += 1
		_check("L3: подсказка не накрывает предметы", covered == 0)

	## В перекрытии тап достаётся верхнему: иначе накрытый предмет можно было бы
	## «прокликать» сквозь то, что на нём лежит.
	var wrench_view: SortItemView = module._views.get("wrench")
	var box_view: SortItemView = module._views.get("box")
	if wrench_view != null and box_view != null:
		_check("L3: в перекрытии тап достаётся верхнему предмету",
			module._hit_test((wrench_view.position + box_view.position) * 0.5) == "box")

	## Кружка придавлена сразу кастрюлей и ведром: одного блокера мало.
	_check("L3: кружка под двумя предметами недоступна", not module._state.is_available("mug"))
	module._on_pick("pot")
	await _tree.create_timer(0.25).timeout
	_check("L3: снят один блокер из двух — кружка всё ещё придавлена",
		not module._state.is_available("mug"))
	module._on_pick("bucket")
	await _tree.create_timer(0.25).timeout
	_check("L3: снят второй блокер — кружка открылась", module._state.is_available("mug"))
	## Тряпку держала только кастрюля, и её хватило одной.
	_check("L3: снятая кастрюля открыла и тряпку", module._state.is_available("rag"))

	## Подсказка одноразовая: второй отказ её не повторяет.
	module._on_pick("jam")
	await _tree.create_timer(0.1).timeout
	_check("L3: второй отказ подсказку не повторяет", module._refused == 2)

	module.restart()
	await _tree.create_timer(0.3).timeout
	_check("L3: перезапуск вернул все 21 предмет", module._views.size() == 21)
	_check("L3: все блокировки на месте",
		not module._state.is_available("wrench") and not module._state.is_available("mug"))
	var def: LevelDefinition = ContentDB.level("bakery_03")
	var moved := 0
	for inst in def.sort.items:
		var view: SortItemView = module._views.get(inst.id)
		if view == null:
			moved += 1
			continue
		if absf(view.position.x - (module.play_rect.position.x
				+ inst.position.x * module.play_rect.size.x)) > 0.5:
			moved += 1
	_check("L3: раскладка после перезапуска совпадает с данными", moved == 0)


## У уровня обязан быть не только путь, найденный перебором, но и просторный
## человеческий: тот, где каждая тройка закрывается сразу, а лоток не подходит
## к краю. Иначе «проходим» означало бы «проходим ровно одним способом», а это
## уже угадывание авторского замысла, а не игра.
func _check_showcase_roomy_path() -> void:
	var def: LevelDefinition = ContentDB.level("bakery_03")
	if def == null or def.sort == null:
		return
	## Порядок человеческий: начать с мусора, который лежит открыто, и дальше
	## каждый раз снимать блокера той группы, которую собираешься закрыть.
	var human := ["news_top", "can_case", "bottle_floor",
		"flour", "pin", "whisk",
		"pot", "bucket", "sponge", "rag", "mug", "plate",
		"box", "crate", "jam",
		"hammer", "wrench", "screw",
		"news_low", "bottle_low", "can_floor"]
	var state := SortState.new()
	state.setup(def.sort)
	var peak := 0
	var refused := PackedStringArray()
	for id in human:
		var res := state.pick(String(id))
		if not bool(res["ok"]):
			refused.append(String(id))
			continue
		peak = maxi(peak, int(res["peak"]))
	_check("L3: человеческий порядок проходит без единого запрещённого хода (%s)"
		% ("чисто" if refused.is_empty() else " ".join(refused)), refused.is_empty())
	_check("L3: он разбирает поле целиком", state.is_complete())
	_check("L3: и держит лоток на %d ячейках из 7 — запас на ошибку есть" % peak,
		peak <= 4)

	## Второй путь — тот, которым уровень проходит прогон. Он теснее, и это
	## нормально: важно, что оба существуют и ни один не переполняет лоток.
	var plan := SortSolver.solve(def.sort)
	_check("L3: солвер тоже находит решение", bool(plan["solved"]))
	_check("L3: решение солвера разбирает все 21 предмет",
		(plan["path"] as PackedStringArray).size() == 21)
	_check("L3: путь солвера держится в пределах лотка (пик %d из 7)"
		% int(plan["max_tray"]), int(plan["max_tray"]) <= 7)


## Проигрыш здесь достижим тем же способом, что и во втором зале, — набором
## вразнобой. Шесть категорий на семь ячеек: седьмой предмет некуда положить.
func _check_showcase_fail_and_restart() -> void:
	var module := _sort_module()
	if module == null:
		return
	var greedy := ["pin", "plate", "box", "screw", "sponge", "news_top", "crate"]
	for id in greedy:
		module._on_pick(String(id))
		await _tree.create_timer(0.06).timeout
	_check("L3: набор вразнобой заполнил лоток", module._state.tray.size() == 7)
	await _tree.create_timer(0.5).timeout
	_check("L3: переполненный лоток — проигрыш", module._state.is_failed())
	_check("L3: после проигрыша ввод заблокирован", module._input_locked)
	_check("L3: проигрыш не записал победу",
		not Game.meta.completed_levels.has("bakery_03"))
	_check("L3: проигрыш не тронул мету",
		not bool(Game.meta.flags.get("hall_showcase_cleared", false)))

	var again := _find_button(Game.current(), "Заново")
	_check("L3: на проигрыше есть кнопка «Заново»", again != null)
	if again == null:
		return
	again.pressed.emit()
	await _tree.create_timer(0.3).timeout
	_check("L3: после перезапуска поле снова полное",
		module._views.size() == 21 and module._state.tray.is_empty())
	_check("L3: ввод снова принимается", not module._input_locked)


## --- уровень 4: тот же Sort, но с закрытой зоной ---------------------------

func _check_approach_scene() -> void:
	var def: LevelDefinition = ContentDB.level("bakery_04")
	_check("L4: уровень идёт в режиме sort", def != null and def.mode == "sort")
	if def == null or def.sort == null:
		_check("L4: раскладка Sort загрузилась", false)
		return
	_check("L4: сборки из кусков перед дверью нет", def.puzzle.module_id.is_empty())
	_check("L4: старой уборки инструментами перед дверью нет", def.cleanup.is_empty())
	_check("L4: предметы не ищут — фазы поиска нет", def.hidden_object.targets.is_empty())
	_check("L4: на поле 24 предмета", def.sort.items.size() == 24)
	_check("L4: лоток по-прежнему на 7 ячеек", def.sort.tray_size == 7)
	_check("L4: фон — зал в том состоянии, в котором его оставил третий уровень",
		def.art.background_path == "res://art/bakery_interior_showcase.png")

	var counts := def.sort.category_counts()
	_check("L4: шесть категорий, каждая делится на тройки",
		def.sort.categories.size() == 6 and counts.size() == 6
		and counts.values().all(func(n): return int(n) % 3 == 0))
	var groups := 0
	for cid in counts:
		groups += int(counts[cid]) / 3
	_check("L4: всего восемь групп", groups == 8)

	var layers := {}
	var blocked := 0
	for inst in def.sort.items:
		layers[inst.layer] = true
		if not inst.blocked_by.is_empty():
			blocked += 1
	_check("L4: слоёв по-прежнему ровно два", layers.size() == 2)
	_check("L4: накрыто %d предметов" % blocked, blocked == 5)

	## Зона — главное, чем этот уровень отличается от третьего.
	_check("L4: ровно одна закрытая зона", def.sort.zones.size() == 1)
	if def.sort.zones.is_empty():
		return
	var zone: SortZone = def.sort.zones[0]
	_check("L4: в зоне 4 предмета", zone.items.size() == 4)
	_check("L4: зону держат 3 предмета", zone.blocked_by.size() == 3)
	## Держат её вещи из разных категорий: снять всё сразу стоит трёх ячеек
	## лотка, и момент открытия зоны становится решением, а не формальностью.
	var lid_categories := {}
	for id in zone.blocked_by:
		lid_categories[def.sort.item(String(id)).category] = true
	_check("L4: замок зоны собран из трёх разных категорий", lid_categories.size() == 3)
	## Без зоны не закрыть ни инструменты, ни посуду — иначе её можно было бы
	## не открывать вовсе, и вся механика существовала бы на бумаге.
	var need_zone := {}
	for id in zone.items:
		need_zone[def.sort.item(String(id)).category] = true
	_check("L4: в зоне лежат предметы 4 категорий", need_zone.size() == 4)

	var state := SortState.new()
	state.setup(def.sort)
	_check("L4: зона закрыта в стартовой позиции", not state.is_zone_open(zone.id))
	var open_now: int = state.available_ids().size()
	_check("L4: сразу доступно %d предметов" % open_now, open_now == 15)
	for id in zone.items:
		if state.is_available(String(id)):
			_check("L4: предмет '%s' из закрытой зоны недоступен" % id, false)
			break

	## Инструментов доступен ровно один: второй под молотком, третий в зоне.
	## Это самая длинная связка уровня и его главный вопрос.
	var open_by_category := {}
	for id in state.available_ids():
		var inst := def.sort.item(String(id))
		open_by_category[inst.category] = int(open_by_category.get(inst.category, 0)) + 1
	_check("L4: инструмент доступен ровно один",
		int(open_by_category.get("tools", 0)) == 1)
	var closable := PackedStringArray()
	for cid in open_by_category:
		if int(open_by_category[cid]) >= 3:
			closable.append(String(cid))
	closable.sort()
	_check("L4: с ходу закрываются только тара и мусор — два безопасных старта",
		"|".join(closable) == "storage|trash")

	var module := _sort_module()
	if module == null:
		_check("L4: модуль уровня доступен", false)
		return
	_check("L4: на экране ровно 24 предмета", module._views.size() == 24)
	_check("L4: закрытая зона нарисована", module._zone_views.size() == 1)
	var hidden := 0
	for id in zone.items:
		var view: SortItemView = module._views.get(String(id))
		if view != null and not view.visible:
			hidden += 1
	_check("L4: содержимое зоны не показано игроку", hidden == 4)

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
	_check("L4: предметы крупные — под палец, а не под пиксель", small == 0)
	_check("L4: ни один предмет не заехал под HUD или лоток", outside == 0)

	## Двадцать четыре предмета на экране — плотнее, чем где-либо до сих пор.
	## Пересекаться вправе только те, кто друг друга держит, и те, кто стоит на
	## зоне: у остальных тап стал бы лотереей.
	var in_zone := {}
	for id in zone.items:
		in_zone[String(id)] = true
	var lids := {}
	for id in zone.blocked_by:
		lids[String(id)] = true
	var stray := PackedStringArray()
	for a in def.sort.items:
		for b in def.sort.items:
			if a.id >= b.id:
				continue
			if a.blocked_by.has(b.id) or b.blocked_by.has(a.id):
				continue
			## Крышка зоны и её содержимое обязаны накладываться: этим зона и
			## закрыта.
			if (in_zone.has(a.id) and lids.has(b.id)) or (in_zone.has(b.id) and lids.has(a.id)):
				continue
			var va: SortItemView = module._views.get(a.id)
			var vb: SortItemView = module._views.get(b.id)
			if va != null and vb != null and va.hit_rect().intersects(vb.hit_rect()):
				stray.append("%s+%s" % [a.id, b.id])
	_check("L4: пересекаются только держащие друг друга и стоящие на зоне (%s)"
		% ("нет лишних" if stray.is_empty() else " ".join(stray)), stray.is_empty())


## Зона в деле: закрыта, ловит тап, объясняет причину, открывается снятием
## последнего, что на ней стояло, и показывает содержимое.
func _check_approach_zone() -> void:
	var module := _sort_module()
	if module == null:
		return
	var def: LevelDefinition = ContentDB.level("bakery_04")
	var zone: SortZone = def.sort.zones[0]

	## Тап в закрытую зону. Ловит его именно зона: внутри ничего не нарисовано,
	## и без этого тап по ящику означал бы ровно ничего.
	var center: Vector2 = module.play_rect.position \
		+ (zone.rect.position + zone.rect.size * 0.5) * module.play_rect.size
	_check("L4: закрытая зона ловит тап по себе", module._zone_at(center) != null)
	module._refuse_zone(zone)
	await _tree.create_timer(0.15).timeout
	_check("L4: тап по закрытой зоне ничего не кладёт в лоток",
		module._state.tray.is_empty())
	_check("L4: отказ зоны засчитан", module._zone_refused == 1)
	if module._tutorial != null:
		_check("L4: подсказка про зоны показана первым же тапом по ней",
			module._tutorial._shown.has("first_locked_zone_attempt"))
		var plate: Rect2 = module._tutorial.plate_rect()
		var covered := 0
		for id in module._views:
			var v: SortItemView = module._views[id]
			if v.visible and plate.intersects(v.hit_rect()):
				covered += 1
		_check("L4: подсказка не накрывает предметы", covered == 0)

	## Снимаем замок по одному: пока стоит хоть что-то, зона закрыта.
	var lids: PackedStringArray = zone.blocked_by
	for i in lids.size() - 1:
		module._on_pick(String(lids[i]))
		await _tree.create_timer(0.2).timeout
		_check("L4: снято %d из %d — зона всё ещё закрыта" % [i + 1, lids.size()],
			not module._state.is_zone_open(zone.id))
	module._on_pick(String(lids[lids.size() - 1]))
	await _tree.create_timer(0.6).timeout
	_check("L4: снят последний — зона открылась", module._state.is_zone_open(zone.id))
	_check("L4: крышка зоны убрана с экрана", module._zone_views.is_empty())

	var shown := 0
	var takeable := 0
	for id in zone.items:
		var view: SortItemView = module._views.get(String(id))
		if view != null and view.visible:
			shown += 1
		if module._state.is_available(String(id)):
			takeable += 1
	_check("L4: содержимое зоны показалось", shown == 4)
	_check("L4: и его теперь можно брать", takeable == 4)

	## Перезапуск возвращает зону закрытой вместе со всем остальным.
	module.restart()
	await _tree.create_timer(0.4).timeout
	_check("L4: перезапуск вернул все 24 предмета", module._views.size() == 24)
	_check("L4: перезапуск снова закрыл зону",
		not module._state.is_zone_open(zone.id) and module._zone_views.size() == 1)
	var still_shown := 0
	for id in zone.items:
		var view: SortItemView = module._views.get(String(id))
		if view != null and view.visible:
			still_shown += 1
	_check("L4: содержимое зоны снова спрятано", still_shown == 0)
	var moved := 0
	for inst in def.sort.items:
		var view: SortItemView = module._views.get(inst.id)
		if view == null:
			moved += 1
			continue
		if absf(view.position.x - (module.play_rect.position.x
				+ inst.position.x * module.play_rect.size.x)) > 0.5:
			moved += 1
	_check("L4: раскладка после перезапуска совпадает с данными", moved == 0)


## У уровня должен быть не только путь перебора, но и просторный человеческий:
## тот, где лоток не доходит до края. Иначе «проходим» означало бы «проходим
## ровно одним способом» — то есть угадывание авторского замысла.
func _check_approach_roomy_path() -> void:
	var def: LevelDefinition = ContentDB.level("bakery_04")
	if def == null or def.sort == null:
		return
	var human := ["box_b", "tin", "box_a",
		"news_a", "can_a", "bottle_a",
		"flour", "pin", "whisk",
		"pot", "bucket", "sponge", "rag",
		"crate", "bag", "mug", "plate",
		"jam", "sack",
		"paper", "news_zone",
		"hammer", "wrench", "screw"]
	var state := SortState.new()
	state.setup(def.sort)
	var zone_id: String = (def.sort.zones[0] as SortZone).id
	var peak := 0
	var opened_at := 0
	var refused := PackedStringArray()
	for i in human.size():
		var res := state.pick(String(human[i]))
		if not bool(res["ok"]):
			refused.append(String(human[i]))
			continue
		peak = maxi(peak, int(res["peak"]))
		if opened_at == 0 and state.is_zone_open(zone_id):
			opened_at = i + 1
	_check("L4: человеческий порядок проходит без единого запрещённого хода (%s)"
		% ("чисто" if refused.is_empty() else " ".join(refused)), refused.is_empty())
	_check("L4: он разбирает поле целиком", state.is_complete())
	_check("L4: зона открывается на ходу %d из 24 — в середине, а не в конце"
		% opened_at, opened_at >= 8 and opened_at <= 18)
	_check("L4: и держит лоток на %d ячейках из 7 — запас на ошибку есть" % peak,
		peak <= 5)

	var plan := SortSolver.solve(def.sort)
	_check("L4: солвер тоже находит решение", bool(plan["solved"]))
	_check("L4: решение солвера разбирает все 24 предмета",
		(plan["path"] as PackedStringArray).size() == 24)
	_check("L4: путь солвера держится в пределах лотка (пик %d из 7)"
		% int(plan["max_tray"]), int(plan["max_tray"]) <= 7)


## Переполнение здесь достижимо тем же способом, что и раньше, — набором
## вразнобой. Шесть категорий на семь ячеек, седьмой предмет класть некуда.
func _check_approach_fail_and_restart() -> void:
	var module := _sort_module()
	if module == null:
		return
	var greedy := ["plate", "pin", "tin", "news_a", "sponge", "hammer", "flour"]
	for id in greedy:
		module._on_pick(String(id))
		await _tree.create_timer(0.06).timeout
	_check("L4: набор вразнобой заполнил лоток", module._state.tray.size() == 7)
	await _tree.create_timer(0.5).timeout
	_check("L4: переполненный лоток — проигрыш", module._state.is_failed())
	_check("L4: после проигрыша ввод заблокирован", module._input_locked)
	_check("L4: проигрыш не записал победу",
		not Game.meta.completed_levels.has("bakery_04"))
	_check("L4: проигрыш не тронул мету",
		not bool(Game.meta.flags.get("storeroom_approach_cleared", false)))

	var again := _find_button(Game.current(), "Заново")
	_check("L4: на проигрыше есть кнопка «Заново»", again != null)
	if again == null:
		return
	again.pressed.emit()
	await _tree.create_timer(0.4).timeout
	_check("L4: после перезапуска поле снова полное",
		module._views.size() == 24 and module._state.tray.is_empty())
	_check("L4: ввод снова принимается", not module._input_locked)


## Дверь кладовой после четвёртого уровня: подойти можно, войти — нет. Самое
## важное здесь — то, чего происходить НЕ должно: ключ не выдаётся и дверь не
## открывается. Прежний путь выдавал ключ прямо по тапу, и вернуться этому
## поведению нельзя.
func _check_storeroom_door() -> void:
	_check("дверь: после уровня стала доступной",
		Game.meta.current_slot_state("bakery", "storeroom_door") == "locked")
	_check("дверь: задача «проверить дверь» открылась",
		Game.meta.task_state("task_try_storeroom_door") == MetaService.TaskState.AVAILABLE)
	_check("дверь: до тапа ключа в сумке нет", PlayerState.amount_of("bakery_key") == 0)

	var slot := _find_node_named(Game.current(), "Slot_storeroom_door")
	_check("дверь: слот есть в сцене", slot != null)
	if slot == null:
		return
	var def: ShopDefinition = ContentDB.shop("bakery")
	var slot_def: ShopSlotDefinition = def.slot("storeroom_door")
	_check("дверь: подсвечена как то, с чем есть что сделать",
		slot_def.highlight_on("locked", Game.meta.flags))
	## Тап идёт через сцену локации, а не через мету напрямую: у игрока есть
	## только палец, и «правило сработало» ничего не говорит о том, покажут ли
	## ему после этого обещанный разговор.
	var shop: Node = Game.current()
	if shop == null or not shop.has_method("_interact"):
		_check("дверь: локация умеет обработать тап по слоту", false)
		return
	shop._interact("storeroom_door")
	await _tree.create_timer(0.6).timeout
	_check("дверь: тап НЕ выдал ключ", PlayerState.amount_of("bakery_key") == 0)
	_check("дверь: тап НЕ открыл дверь",
		Game.meta.current_slot_state("bakery", "storeroom_door") == "locked")
	_check("дверь: отмечено, что её пробовали",
		bool(Game.meta.flags.get("storeroom_door_tried", false)))
	_check("дверь: после тапа — разговор о пропавшем ключе",
		Game.screen == Game.Screen.DIALOG)
	_check("дверь: задача «проверить дверь» закрылась сама",
		Game.meta.task_state("task_try_storeroom_door") == MetaService.TaskState.COMPLETED)
	_check_dialog_runs()
	await tree_wait(0.6)
	_check("дверь: после разговора игрок остаётся в пекарне",
		Game.screen == Game.Screen.SHOP)
	_check("дверь: разговор ключа тоже не выдал", PlayerState.amount_of("bakery_key") == 0)
	## Пятый уровень — поиск ключа — в этой партии ещё не сделан, и появиться
	## сам собой из-за того, что разговор его пообещал, он не должен.
	_check("дверь: пятого уровня в контенте пока нет",
		ContentDB.level("bakery_05") == null)
	var again: Node = Game.current()
	if again != null and again.has_method("_interact"):
		again._interact("storeroom_door")
		await _tree.create_timer(0.4).timeout
	_check("дверь: повторный тап по-прежнему ничего не выдаёт и не открывает",
		PlayerState.amount_of("bakery_key") == 0
		and Game.meta.current_slot_state("bakery", "storeroom_door") == "locked")
	_check("дверь: повторный тап не заводит разговор заново",
		Game.screen == Game.Screen.SHOP)


func tree_wait(sec: float) -> void:
	await _tree.create_timer(sec).timeout


## Правило проигрыша само по себе — на выдуманной раскладке, без сцены.
## Четыре категории по три, лоток на семь: по два предмета из четырёх категорий
## дают восемь, и седьмой кладётся уже в переполненный лоток.
func _check_fail_rule() -> void:
	var def := SortDefinition.new()
	def.tray_size = 7
	def.group_size = 3
	def.fail_on_full_tray = true
	var made: Array[SortItemInstance] = []
	for c in ["a", "b", "c", "d"]:
		var cat := SortCategory.new()
		cat.id = String(c)
		def.categories.append(cat)
		for n in 3:
			var inst := SortItemInstance.new()
			inst.id = "%s%d" % [c, n]
			inst.item_id = "scrap_paper"
			inst.category = String(c)
			made.append(inst)
	def.items = made

	var state := SortState.new()
	state.setup(def)
	for id in ["a0", "a1", "b0", "b1", "c0", "c1"]:
		state.pick(String(id))
	_check("правило: шесть разрозненных предметов — ещё не проигрыш",
		not state.is_failed())
	state.pick("d0")
	_check("правило: седьмой предмет без тройки переполняет лоток",
		state.tray.size() == 7 and state.is_failed())

	## Тройка освобождает ячейки — иначе «проигрыш» наступал бы просто по
	## количеству ходов, независимо от того, что игрок собрал.
	var ok := SortState.new()
	ok.setup(def)
	for id in ["a0", "a1", "a2"]:
		ok.pick(String(id))
	_check("правило: собранная тройка освобождает лоток",
		ok.tray.is_empty() and not ok.is_failed())


## Проигрыш и мгновенный перезапуск. Проверяем и то, чего игрок не видит:
## неудача не должна оставить в мете ни следа.
func _check_sort_fail_and_restart() -> void:
	var module := _sort_module()
	if module == null:
		_check("L1: модуль доступен для проверки проигрыша", false)
		return

	## Раскладку снимаем ДО проигрыша: сравнивать её с положением предметов в
	## лотке значит проверять не раскладку уровня, а расстановку ячеек.
	var layout_before := {}
	for id in module._views:
		layout_before[String(id)] = module._views[id].position

	## Само правило проигрыша проверяется на выдуманном наборе, а не на первом
	## уровне: там категорий три, и семь предметов без тройки в лоток физически
	## не набрать. Это свойство обучения, а не пробел в проверке, — но правило
	## от этого не перестаёт существовать, и ломаться молча ему нельзя.
	_check_fail_rule()

	## На живом уровне — тот же тупик руками игрока: по два предмета из трёх
	## категорий и один из четвёртой. Семь ячеек заняты, ни одной тройки.
	var dead_end := ["p1", "p2", "d1", "d2", "b1", "b2", "w1"]
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
	Game.meta.refresh_after_load()

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
	_check("миграция: новый второй уровень тоже не засчитан пройденным",
		not Game.meta.completed_levels.has("bakery_02"))
	_check("миграция: сейв перезаписывается уже новой версией",
		SaveService.CURRENT_VERSION == 3)
	await _check_tutorial_flag_migration()


## Сейв версии 2 знал один флаг на весь Sort. Теперь у каждого объяснения свой,
## и старый флаг обязан переехать на новое имя — иначе игрок, прошедший первый
## уровень, увидит его объяснение заново.
func _check_tutorial_flag_migration() -> void:
	var old := {
		"version": 2,
		"saved_at": 0,
		"player": {"currencies": {"coins": 65, "hard": 60, "xp": 10}, "items": {}},
		"meta": {
			"completed_levels": {"bakery_01": 1},
			"levels_completed_total": 1,
			"flags": {"intro_seen": true, "met_baker": true, "facade_cleared": true,
				"sort_taught": true},
			"rewarded_tasks": {"task_visit_bakery": true, "task_clear_facade": true},
		},
	}
	var f := FileAccess.open(SaveService.SAVE_PATH, FileAccess.WRITE)
	if f == null:
		_check("миграция v2: сейв записан", false)
		return
	f.store_string(JSON.stringify(old, "  "))
	f.close()

	PlayerState.reset()
	CooldownService.reset()
	Game.meta.reset()
	_check("миграция v2: сейв прочитан", SaveService.load_game())
	Game.meta.refresh_after_load()
	_check("миграция v2: объяснение первого уровня осталось показанным",
		bool(Game.meta.flags.get(Game.tutorial_flag("sort_basics"), false)))
	_check("миграция v2: общий флаг убран",
		not bool(Game.meta.flags.get("sort_taught", false)))
	## Предупреждение второго уровня игрок ещё не видел, и переезд старого флага
	## не должен был закрыть заодно и его.
	_check("миграция v2: подсказка второго уровня всё ещё ждёт игрока",
		not bool(Game.meta.flags.get(Game.tutorial_flag("sort_tray_risk"), false)))


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


## --- обучение журналу: выключено, проверки ждут его возвращения -------------
##
## Само обучение выключено в контенте (`enabled: false` в tutorial/journal.json),
## поэтому две проверки ниже сейчас никто не зовёт. Удалять их не за что: шаги
## целиком на месте, и когда объяснению найдётся место в порядке сцен, проверять
## его придётся ровно этим — рукой, ведущей к кнопке, и прощёлкиванием списка.

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
