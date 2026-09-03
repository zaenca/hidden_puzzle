extends Node
## FSM приложения и единственная точка смены экранов.
## Здесь же живёт связка core → мета: уровень отдаёт LevelResult, Game передаёт
## его MetaService и маршрутизирует игрока обратно к конкретной задаче.

enum Screen { NONE, INTRO, DIALOG, MAP, SHOP, LEVEL }

const SCENE_PATHS := {
	Screen.INTRO: "res://ui/intro_scene.tscn",
	Screen.DIALOG: "res://ui/dialog_scene.tscn",
	Screen.MAP: "res://meta/map/map_scene.tscn",
	Screen.SHOP: "res://meta/shop/shop_scene.tscn",
	## Экран уровня один на все режимы: какой геймплей запускать, решает сам
	## контроллер по данным уровня. Иначе Game пришлось бы знать список
	## механик, и каждая новая правила бы автолоад.
	Screen.LEVEL: "res://core/level/level_controller.tscn",
}

## Партия начинается с пустым кошельком: монеты приходят за задания и уровни,
## и стартовые 300 «на потестировать» врали игроку про его собственный прогресс.
const NEW_GAME_WALLET := {"coins": 0, "hard": 60, "booster_hint": 3}
const BOOSTER_ID := "booster_hint"
## Вступление показывается один раз за прохождение. Флаг живёт в мете, а не в
## настройках: он про эту партию, и «Сброс прогресса» обязан вернуть интро.
## Ставится только В КОНЦЕ всей завязки: выход посреди диалога с мэром не должен
## оставлять игрока без объяснения, зачем он тут.
const INTRO_FLAG := "intro_seen"
## «Игрок уже находил предметы нажатием». Пока флага нет, обучающая рука
## показывает тап — и в фазе поиска уровня, и в локации-уборке: жест один и тот
## же, а единственное, чему игрока научили до этого, — тащить части пазла.
const SEARCH_FLAG := "search_taught"
## «Игрок уже видел журнал заданий». Пока флага нет, указатель на карте ведёт к
## кнопке журнала, а первое его открытие объясняет, как список устроен.
const JOURNAL_FLAG := "journal_seen"
## «Игрок уже понял Sort». Пока флага нет, уровень получает шаги обучения из
## своего же контента; после первого доигранного объяснения — не получает
## никогда. Флаг живёт в мете, потому что это факт об игроке, а не о уровне.
const SORT_FLAG := "sort_taught"
const INTRO_ID := "opening"

signal screen_changed(screen: int)

var meta: MetaService
var screen: int = Screen.NONE

## Предмет «в руке». Один на всё приложение: инвентарь общий для всех экранов,
## значит и выбор в нём общий — иначе каждая сцена заводила бы свой и они
## расходились бы при переходе.
var selected_item: String = ""

## Полоса инвентаря из оверлея Boot. Тип намеренно широкий: InventoryBar сам
## обращается к Game, и назвать его здесь по имени класса значит замкнуть
## автолоад на UI-скрипт.
var inventory: Control = null

## Журнал заданий из оверлея. Тип широкий по той же причине, что у inventory:
## виджет сам обращается к Game, и назвать его здесь по классу значит замкнуть
## автолоад на UI-скрипт.
var journal: Control = null

var _root: Node = null
var _current: Node = null
var _current_dialog: String = ""
var _current_intro: String = ""
var _last_shop_id: String = ""
var _last_meta_screen: int = Screen.MAP


func _ready() -> void:
	meta = MetaService.new(PlayerState, ContentDB, CooldownService)


func attach(root: Node) -> void:
	_root = root


func attach_journal(widget: Control) -> void:
	journal = widget


func attach_inventory(bar: Control) -> void:
	inventory = bar


## --- инвентарь: выбранный предмет -------------------------------------------

## Повторный тап по тому же предмету кладёт его обратно — иначе из режима
## «в руке ключ» нельзя выйти, не применив ключ хоть куда-нибудь.
func select_item(item_id: String) -> void:
	var next := "" if selected_item == item_id else item_id
	if next == selected_item:
		return
	selected_item = next
	EventBus.inventory_selection_changed.emit(selected_item)
	if not selected_item.is_empty():
		EventBus.toast.emit("В руке: %s" % ContentDB.item_name(selected_item))


func clear_selection() -> void:
	if selected_item.is_empty():
		return
	selected_item = ""
	EventBus.inventory_selection_changed.emit("")


## Сколько снизу занимает полоса инвентаря. Экраны держат на неё отступ, чтобы
## их нижние панели не уезжали под инвентарь.
func bottom_reserved() -> int:
	if inventory == null or not inventory.has_method("reserved_height"):
		return 0
	return int(inventory.reserved_height())


## Текущий экран. Нужен debug-меню и headless-прогону; игровой код им не пользуется.
func current() -> Node:
	return _current


func boot() -> void:
	ContentDB.load_all()
	SaveService.register("player", PlayerState)
	SaveService.register("cooldowns", CooldownService)
	SaveService.register("meta", meta)
	if not SaveService.load_game():
		new_game()
	meta.refresh()
	_open_start_screen()


func new_game() -> void:
	clear_selection()
	PlayerState.reset(NEW_GAME_WALLET)
	CooldownService.reset()
	meta.reset()
	meta.refresh()
	SaveService.save_game()


func hard_reset() -> void:
	SaveService.wipe()
	new_game()
	_open_start_screen()


## --- вступление -------------------------------------------------------------

## С чего открывается игра. Новая партия начинается со вступления, продолжение —
## сразу с площади.
func _open_start_screen() -> void:
	if bool(meta.flags.get(INTRO_FLAG, false)):
		open_map()
	else:
		open_intro(INTRO_ID)


func open_intro(intro_id: String) -> void:
	_current_intro = intro_id
	goto(Screen.INTRO, {"intro_id": intro_id})


func open_dialog(dialog_id: String) -> void:
	_current_dialog = dialog_id
	goto(Screen.DIALOG, {
		"dialog_id": dialog_id,
		"show_tap_hint": is_first_time_player(),
	})


## Сцены умеют только доиграть себя до конца. Что случится дальше — флаг, другая
## сцена, уровень или магазин — написано в самом контенте (`on_finish`), поэтому
## порядок «фасад → разговор с хозяйкой → внутрь пекарни» правится в JSON, а не
## здесь. Иначе каждая новая сцена дописывала бы себе ветку в Game.
func finish_intro() -> void:
	var finished := _current_intro
	_current_intro = ""
	_route_after(ContentDB.intro(finished).get("on_finish", {}))


func finish_dialog() -> void:
	var finished := _current_dialog
	_current_dialog = ""
	_route_after(ContentDB.dialog(finished).get("on_finish", {}))


func _route_after(on_finish: Dictionary) -> void:
	var flag := String(on_finish.get("set_flag", ""))
	if not flag.is_empty():
		meta.set_flag(flag, true)
	SaveService.save_game()

	var next_intro := String(on_finish.get("intro", ""))
	if not next_intro.is_empty():
		open_intro(next_intro)
		return

	var next_dialog := String(on_finish.get("dialog", ""))
	if not next_dialog.is_empty():
		open_dialog(next_dialog)
		return

	var task_id := String(on_finish.get("play_task", ""))
	if not task_id.is_empty() and not meta.resolve_level_for_task(task_id).is_empty():
		play_task(task_id)
		return

	var shop_id := String(on_finish.get("open_shop", ""))
	if not shop_id.is_empty() and meta.is_shop_open(shop_id):
		open_shop(shop_id)
		return

	open_map()


## Игрок хочет войти в локацию. Первый визит может быть обставлен сценой — это
## описано в самом магазине (`first_visit`), поэтому карта просто говорит «сюда»
## и не знает, будет ли по дороге разговор.
func enter_shop(shop_id: String) -> void:
	var shop: ShopDefinition = ContentDB.shop(shop_id)
	if shop != null:
		var first: Dictionary = shop.first_visit
		var flag := String(first.get("flag", ""))
		var intro_id := String(first.get("intro", ""))
		if not flag.is_empty() and not intro_id.is_empty() \
				and not bool(meta.flags.get(flag, false)):
			open_intro(intro_id)
			return
	open_shop(shop_id)


## Показать завязку ещё раз, не сбрасывая прогресс. Нужно только debug-панели.
func replay_intro() -> void:
	open_intro(INTRO_ID)


## --- маршрутизация ----------------------------------------------------------

func goto(target: int, payload: Dictionary = {}) -> void:
	if _root == null:
		push_error("Game: не вызван attach()")
		return
	# Предмет «в руке» имеет смысл только там, где есть куда его применить.
	# Уносить ключ внутрь уровня и находить его там же выбранным — не имеет.
	if target == Screen.LEVEL:
		clear_selection()

	if _current != null:
		_root.remove_child(_current)
		_current.queue_free()
		_current = null

	var packed: PackedScene = load(String(SCENE_PATHS[target]))
	var inst: Node = packed.instantiate()
	_root.add_child(inst)
	_current = inst
	screen = target

	if inst.has_signal("finished"):
		inst.finished.connect(_on_level_finished)
	if inst.has_signal("abandoned"):
		inst.abandoned.connect(_on_level_abandoned)
	if inst.has_method("setup"):
		inst.setup(payload)
	screen_changed.emit(target)


func open_map(focus: MetaFocus = null) -> void:
	_last_meta_screen = Screen.MAP
	goto(Screen.MAP, {"focus": focus})


func open_shop(shop_id: String, focus: MetaFocus = null) -> void:
	_last_shop_id = shop_id
	_last_meta_screen = Screen.SHOP
	goto(Screen.SHOP, {"shop_id": shop_id, "focus": focus})


func back_to_meta(focus: MetaFocus = null) -> void:
	if _last_meta_screen == Screen.SHOP and not _last_shop_id.is_empty():
		open_shop(_last_shop_id, focus)
	else:
		open_map(focus)


## --- запуск уровня ----------------------------------------------------------

func play_task(task_id: String) -> void:
	var info := meta.resolve_level_for_task(task_id)
	if info.is_empty():
		EventBus.toast.emit("Для задачи нет уровней")
		return
	play_level(String(info["level_id"]), bool(info["replay"]))


func play_level(level_id: String, replay: bool = false) -> void:
	var def: LevelDefinition = ContentDB.level(level_id)
	if def == null:
		EventBus.toast.emit("Уровень не найден: %s" % level_id)
		return
	var ctx := LevelContext.new()
	ctx.definition = def
	ctx.replay = replay
	ctx.items = items_for_level(def)
	ctx.booster_id = BOOSTER_ID
	ctx.boosters_available = PlayerState.amount_of(BOOSTER_ID)
	ctx.show_drag_hint = is_first_time_player()
	ctx.show_tap_hint = not bool(meta.flags.get(SEARCH_FLAG, false))
	ctx.tutorial_steps = _tutorial_steps_for(def)
	goto(Screen.LEVEL, {"context": ctx})


## Обучение уровня: какой файл читать — написано в самом уровне, а показывать
## ли его вообще — знает мета. Ни того, ни другого игровой модуль решать не
## может: первое сделало бы его знающим про конкретный уровень, второе — про
## прогресс игрока.
func _tutorial_steps_for(def: LevelDefinition) -> Array:
	if def.sort == null or def.sort.tutorial_id.is_empty():
		return []
	if bool(meta.flags.get(SORT_FLAG, false)):
		return []
	return ContentDB.tutorial(def.sort.tutorial_id).get("steps", [])


## Обучающие подсказки показываем, пока игрок не прошёл ни одного уровня.
## Отдельного флага для этого не нужно: «ни одного уровня» и есть определение
## новичка, и оно само перестаёт быть верным ровно тогда, когда надо.
func is_first_time_player() -> bool:
	return meta.levels_completed_total == 0


func items_for_level(def: LevelDefinition) -> Dictionary:
	var out := {}
	## Предметы Sort не ищут и не выдают — их разбирают. Уровню нужны их иконки
	## и названия, в инвентарь игрока они не попадают.
	if def.sort != null:
		for inst in def.sort.items:
			var sort_item: ItemDefinition = ContentDB.item(inst.item_id)
			if sort_item != null:
				out[inst.item_id] = sort_item
	for t in def.hidden_object.targets:
		var item: ItemDefinition = ContentDB.item(t.item_id)
		if item != null:
			out[t.item_id] = item
	for id in def.quest_grants:
		var item: ItemDefinition = ContentDB.item(String(id))
		if item != null:
			out[String(id)] = item
	## Предметы уборки не ищут и не выдают — их показывают и тут же тащат.
	## В инвентарь игрока они не попадают, но уровню нужны их иконки и названия.
	for step in def.cleanup:
		var item: ItemDefinition = ContentDB.item(step.item_id)
		if item != null:
			out[step.item_id] = item
	return out


## --- возврат из уровня ------------------------------------------------------

func _on_level_finished(result: LevelResult) -> void:
	## Найденный тапом предмет — доказательство, что жест понят. Обучающую руку
	## в сценах поиска больше не показываем.
	if result != null:
		var found := int(result.stats.get("quest_found", 0)) \
			+ int(result.stats.get("normal_found", 0))
		if found > 0:
			meta.set_flag(SEARCH_FLAG, true)
		## Объяснение Sort доиграно до конца — второй раз его показывать не за
		## что. Флаг ставит мета, а не уровень: уровень только сообщает факт.
		if bool(result.stats.get("tutorial_done", false)):
			meta.set_flag(SORT_FLAG, true)
	var focus := meta.apply_level_result(result)
	SaveService.save_game()
	if focus.location == "map":
		open_map(focus)
	else:
		open_shop(focus.shop_id if not focus.shop_id.is_empty() else _last_shop_id, focus)


func _on_level_abandoned() -> void:
	back_to_meta(null)


## --- сохранение по жизненному циклу -----------------------------------------

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_GO_BACK_REQUEST:
			_safe_save()
		NOTIFICATION_WM_CLOSE_REQUEST:
			_safe_save()


func _safe_save() -> void:
	if meta != null and ContentDB.loaded:
		SaveService.save_game()
