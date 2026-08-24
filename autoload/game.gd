extends Node
## FSM приложения и единственная точка смены экранов.
## Здесь же живёт связка core → мета: уровень отдаёт LevelResult, Game передаёт
## его MetaService и маршрутизирует игрока обратно к конкретной задаче.

enum Screen { NONE, MAP, SHOP, LEVEL }

const SCENE_PATHS := {
	Screen.MAP: "res://meta/map/map_scene.tscn",
	Screen.SHOP: "res://meta/shop/shop_scene.tscn",
	Screen.LEVEL: "res://core/level/hybrid_level.tscn",
}

const NEW_GAME_WALLET := {"coins": 300, "hard": 60, "booster_hint": 3}
const BOOSTER_ID := "booster_hint"

signal screen_changed(screen: int)

var meta: MetaService
var screen: int = Screen.NONE

var _root: Node = null
var _current: Node = null
var _last_shop_id: String = ""
var _last_meta_screen: int = Screen.MAP


func _ready() -> void:
	meta = MetaService.new(PlayerState, ContentDB, CooldownService)


func attach(root: Node) -> void:
	_root = root


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
	open_map()


func new_game() -> void:
	PlayerState.reset(NEW_GAME_WALLET)
	CooldownService.reset()
	meta.reset()
	meta.refresh()
	SaveService.save_game()


func hard_reset() -> void:
	SaveService.wipe()
	new_game()
	open_map()


## --- маршрутизация ----------------------------------------------------------

func goto(target: int, payload: Dictionary = {}) -> void:
	if _root == null:
		push_error("Game: не вызван attach()")
		return
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
	goto(Screen.LEVEL, {"context": ctx})


func items_for_level(def: LevelDefinition) -> Dictionary:
	var out := {}
	for t in def.hidden_object.targets:
		var item: ItemDefinition = ContentDB.item(t.item_id)
		if item != null:
			out[t.item_id] = item
	for id in def.quest_grants:
		var item: ItemDefinition = ContentDB.item(String(id))
		if item != null:
			out[String(id)] = item
	return out


## --- возврат из уровня ------------------------------------------------------

func _on_level_finished(result: LevelResult) -> void:
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
