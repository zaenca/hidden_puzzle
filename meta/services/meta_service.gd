class_name MetaService
extends RefCounted
## Мета-слой: состояния магазинов, задач, применение результатов уровня.
##
## Намеренно НЕ autoload: создаётся с любыми player/db/cooldowns, поэтому
## правила задач проверяются headless без единой сцены (tools/smoke_test.gd).

enum TaskState { LOCKED, AVAILABLE, IN_PROGRESS, READY_TO_APPLY, APPLYING, COMPLETED }

const STATE_NAMES := ["locked", "available", "in_progress", "ready_to_apply", "applying", "completed"]
const AUTO_APPLY_PASSES := 4

var player: Node
var db: Node
var cooldowns: Node

var shop_states: Dictionary = {}      ## shop_id -> {"state": String, "slots": {slot_id: state_id}}
var task_states: Dictionary = {}      ## task_id -> int (TaskState)
var completed_levels: Dictionary = {} ## level_id -> сколько раз пройден
var flags: Dictionary = {}
var levels_completed_total: int = 0
var pending_narrative: PackedStringArray = PackedStringArray()
## Диалоги, которые эффекты попросили показать. Очередь, а не одно поле: два
## действия могут закрыться одним пересчётом, и второй диалог не должен молча
## затирать первый.
var pending_dialogs: Array[String] = []
## task_id -> true. Задачи, за которые награда уже выдана.
var rewarded_tasks: Dictionary = {}

var _auto_applying: bool = false


func _init(p: Node, content: Node, cd: Node) -> void:
	player = p
	db = content
	cooldowns = cd


## --- инициализация и пересчёт ----------------------------------------------

func ensure_defaults() -> void:
	for shop_id in db.shops:
		if not shop_states.has(shop_id):
			shop_states[shop_id] = {
				"state": db.shop(shop_id).initial_state,
				"slots": db.shop(shop_id).default_states(),
			}
		else:
			var slots: Dictionary = shop_states[shop_id]["slots"]
			for slot_id in db.shop(shop_id).default_states():
				if not slots.has(slot_id):
					slots[slot_id] = db.shop(shop_id).default_states()[slot_id]
	for task_id in db.tasks:
		if not task_states.has(task_id):
			task_states[task_id] = TaskState.LOCKED


func refresh() -> void:
	ensure_defaults()
	# Два прохода: разблокировка одной задачи может открыть следующую.
	for _pass in 2:
		for task_id in db.tasks:
			var before: int = task_states.get(task_id, TaskState.LOCKED)
			var after := TaskResolver.compute(db.task(task_id), self)
			if after != before:
				if after == TaskState.COMPLETED:
					_pay_task_reward(task_id)
				task_states[task_id] = after
				EventBus.task_state_changed.emit(task_id, after)
	_auto_apply_ready()
	_check_parallel_task_invariant()


## Часть задач не требует от игрока ни кнопки, ни выбора: они выполнены ровно
## тогда, когда выполнены их условия. Такие действия помечены auto_apply и
## применяются здесь, сразу после пересчёта, — иначе задача зависала бы в
## READY_TO_APPLY с кнопкой, которая ничего не решает.
##
## Место выбрано намеренно: refresh() — единственная точка, где состояния задач
## становятся актуальными, и её зовут все, кто меняет мир. Развесить
## авто-применение по вызывающим значило бы однажды забыть одного из них.
func _auto_apply_ready() -> void:
	# start_action → _complete_action → refresh(): без охраны это рекурсия.
	if _auto_applying:
		return
	_auto_applying = true
	# Выполнение одной задачи открывает следующую — крутим, пока есть что.
	for _pass in AUTO_APPLY_PASSES:
		var applied := false
		for task_id in db.tasks:
			if task_state(task_id) != TaskState.READY_TO_APPLY:
				continue
			var action := action_for_task(task_id)
			## Cooldown-действие само себя не запускает: ждать десять минут —
			## это решение игрока, а не следствие условий.
			if action == null or not action.auto_apply or not action.is_instant():
				continue
			if start_action(task_id):
				applied = true
		if not applied:
			break
	_auto_applying = false


## Инвариант: у игрока всегда есть чем заняться. Нарушение — баг контента,
## и он должен всплыть на разработке, а не у игрока во время cooldown.
## Повтор пройденного уровня тоже считается занятием, но это слабый запасной
## вариант — если новых задач нет, об этом стоит знать.
func _check_parallel_task_invariant() -> void:
	if applying_tasks().is_empty() or not playable_tasks().is_empty():
		return
	if replayable_tasks().is_empty():
		push_warning("Контент: все задачи в cooldown, заняться нечем совсем")
	else:
		push_warning("Контент: во время cooldown из активностей остался только повтор уровней")


## Пройденные задачи, чьи уровни можно перепройти ради ресурсов.
func replayable_tasks() -> Array[MetaTaskDefinition]:
	var out: Array[MetaTaskDefinition] = []
	for t in db.tasks.values():
		if task_state(t.id) == TaskState.COMPLETED and not t.level_ids.is_empty():
			out.append(t)
	return out


## --- запросы ----------------------------------------------------------------

func task_state(task_id: String) -> int:
	return task_states.get(task_id, TaskState.LOCKED)


func task_state_name(task_id: String) -> String:
	return STATE_NAMES[task_state(task_id)]


func slot_state(shop_id: String, slot_id: String) -> String:
	return String(shop_states.get(shop_id, {}).get("slots", {}).get(slot_id, ""))


func shop_state(shop_id: String) -> String:
	return String(shop_states.get(shop_id, {}).get("state", "locked"))


func is_shop_open(shop_id: String) -> bool:
	return shop_state(shop_id) != "locked"


## Весь путь игрока в сюжетном порядке — для журнала. В отличие от tasks_at()
## отдаёт и выполненные, и ещё закрытые: журнал существует ровно затем, чтобы
## показать, что уже сделано и что впереди, а список из одной текущей строки
## этого не говорит.
func all_tasks() -> Array[MetaTaskDefinition]:
	var out: Array[MetaTaskDefinition] = []
	for t in db.tasks.values():
		out.append(t)
	out.sort_custom(func(a, b): return db._task_order(a) < db._task_order(b))
	return out


func tasks_at(location: String, shop_id: String = "") -> Array[MetaTaskDefinition]:
	var out: Array[MetaTaskDefinition] = []
	for t in db.tasks.values():
		if t.location != location:
			continue
		if not shop_id.is_empty() and t.shop_id != shop_id:
			continue
		if task_state(t.id) == TaskState.LOCKED:
			continue
		out.append(t)
	out.sort_custom(func(a, b): return db._task_order(a) < db._task_order(b))
	return out


func playable_tasks() -> Array[MetaTaskDefinition]:
	var out: Array[MetaTaskDefinition] = []
	for t in db.tasks.values():
		var s := task_state(t.id)
		if s == TaskState.AVAILABLE or s == TaskState.IN_PROGRESS or s == TaskState.READY_TO_APPLY:
			out.append(t)
	return out


func applying_tasks() -> Array[MetaTaskDefinition]:
	var out: Array[MetaTaskDefinition] = []
	for t in db.tasks.values():
		if task_state(t.id) == TaskState.APPLYING:
			out.append(t)
	return out


## Какой уровень запускать для задачи. Все пройдены → повтор последнего
## со сниженной наградой и БЕЗ повторной выдачи сюжетных предметов.
func resolve_level_for_task(task_id: String) -> Dictionary:
	var task: MetaTaskDefinition = db.task(task_id)
	if task == null or task.level_ids.is_empty():
		return {}
	for level_id in task.level_ids:
		if not completed_levels.has(level_id):
			return {"level_id": level_id, "replay": false}
	return {"level_id": task.level_ids[task.level_ids.size() - 1], "replay": true}


## --- изменение мира ---------------------------------------------------------

func set_slot_state(shop_id: String, slot_id: String, state_id: String) -> void:
	if not shop_states.has(shop_id):
		ensure_defaults()
	if not shop_states.has(shop_id):
		push_warning("Meta: неизвестный магазин %s" % shop_id)
		return
	shop_states[shop_id]["slots"][slot_id] = state_id
	EventBus.shop_visual_changed.emit(shop_id, slot_id, state_id)


func set_shop_state(shop_id: String, state: String) -> void:
	if not shop_states.has(shop_id):
		ensure_defaults()
	if shop_states.has(shop_id):
		shop_states[shop_id]["state"] = state


## Флаг — это состояние мира: он открывает одни задачи и закрывает те, что ждали
## именно его. Пересчёт живёт здесь, а не у вызывающих: диалог, тап по объекту и
## эффект действия поднимают флаги по-разному, и однажды кто-то из них забудет.
func set_flag(flag: String, value: bool = true) -> void:
	if bool(flags.get(flag, false)) == value:
		return
	flags[flag] = value
	refresh()


## --- point-and-click: тап по слоту ------------------------------------------

## Единственная точка обработки тапа по объекту магазина. Сцена не знает ни про
## ключ, ни про дверь: она сообщает «тапнули по слоту, в руке предмет» и
## показывает то, что вернула мета. Поэтому то же самое умеет headless-прогон.
##
## Возвращает: {ok, text, narrative, granted, consumed, state}
func interact(shop_id: String, slot_id: String, selected_item: String = "") -> Dictionary:
	var out := {"ok": false, "text": "", "narrative": false,
		"granted": "", "consumed": "", "state": ""}

	var shop: ShopDefinition = db.shop(shop_id)
	var slot: ShopSlotDefinition = shop.slot(slot_id) if shop != null else null
	if slot == null:
		return out

	var state := current_slot_state(shop_id, slot_id)
	for rule in slot.interactions:
		if not rule.matches(state, selected_item, flags):
			continue

		if not rule.use_item.is_empty() and rule.consume:
			if not player.pay(rule.use_item, 1):
				continue
			out["consumed"] = rule.use_item
		if not rule.grant_item.is_empty():
			player.grant(rule.grant_item, 1)
			out["granted"] = rule.grant_item
		if not rule.once_flag.is_empty():
			set_flag(rule.once_flag, true)
		if not rule.set_state.is_empty():
			set_slot_state(shop_id, slot_id, rule.set_state)
			out["state"] = rule.set_state
		if not rule.set_flag.is_empty():
			set_flag(rule.set_flag, true)

		out["ok"] = true
		out["text"] = rule.text
		out["narrative"] = rule.shows_narrative()
		if rule.shows_narrative() and not rule.text.is_empty():
			pending_narrative.append(rule.text)
		refresh()
		return out

	# Ни одно правило не подошло — это нормальная ситуация, а не ошибка:
	# игрок ткнул не тем предметом или объектом, с которым уже всё сделано.
	if selected_item.is_empty():
		out["text"] = "Здесь ничего не происходит."
	else:
		out["text"] = "«%s» здесь не поможет." % db.item_name(selected_item)
	return out


## Состояние слота с подстраховкой: в сейве может лежать состояние, которого
## в контенте уже нет (контент переписали) — тогда берём default.
func current_slot_state(shop_id: String, slot_id: String) -> String:
	var shop: ShopDefinition = db.shop(shop_id)
	var slot: ShopSlotDefinition = shop.slot(slot_id) if shop != null else null
	if slot == null:
		return ""
	var state := slot_state(shop_id, slot_id)
	if state.is_empty() or not slot.has_state(state):
		return slot.default_state
	return state


## --- главный вход: результат уровня ----------------------------------------

func apply_level_result(result: LevelResult) -> MetaFocus:
	var focus := MetaFocus.new()
	if result == null or not result.success:
		return focus

	completed_levels[result.level_id] = int(completed_levels.get(result.level_id, 0)) + 1
	levels_completed_total += 1

	player.grant("coins", result.soft_currency)
	player.grant("xp", result.xp)
	for booster_id in result.boosters_spent:
		player.pay(booster_id, int(result.boosters_spent[booster_id]))

	# Сюжетные предметы выдаются только за первое прохождение.
	if not result.replay:
		for item_id in result.quest_items:
			player.grant(item_id, 1)

	_reduce_running_cooldowns()
	refresh()

	var task: MetaTaskDefinition = db.task(result.task_id)
	if task != null:
		focus.location = task.location
		focus.shop_id = task.shop_id
		focus.task_id = task.id
		focus.action_id = task.action_id
		focus.hotspot = task.hotspot
		focus.auto_open = task_state(task.id) == TaskState.READY_TO_APPLY
	focus.narrative = take_narrative()
	return focus


## Прохождение любого core level сокращает все идущие cooldown — это и есть
## «продолжай играть, чтобы ждать меньше».
func _reduce_running_cooldowns() -> Array:
	var report := []
	for action_id in cooldowns.running_ids():
		var action: MetaActionDefinition = db.action(action_id)
		if action == null or action.reduce_per_level_sec <= 0:
			continue
		var applied: int = cooldowns.reduce(action_id, action.reduce_per_level_sec)
		if applied > 0:
			report.append({"action_id": action_id, "seconds": applied})
	return report


## --- meta actions -----------------------------------------------------------

func action_for_task(task_id: String) -> MetaActionDefinition:
	var task: MetaTaskDefinition = db.task(task_id)
	return db.action(task.action_id) if task != null else null


func can_start_action(task_id: String) -> bool:
	var action := action_for_task(task_id)
	if action == null:
		return false
	if task_state(task_id) != TaskState.READY_TO_APPLY:
		return false
	if not TaskResolver.missing(action.requirements, self).is_empty():
		return false
	for c in action.costs:
		if not player.can_pay(c.id, c.amount):
			return false
	return true


func start_action(task_id: String) -> bool:
	if not can_start_action(task_id):
		return false
	var action := action_for_task(task_id)
	for c in action.costs:
		player.pay(c.id, c.amount)
	if action.is_instant():
		_complete_action(task_id, action)
	else:
		cooldowns.start(action.id, action.duration_sec, task_id)
		task_states[task_id] = TaskState.APPLYING
		EventBus.task_state_changed.emit(task_id, TaskState.APPLYING)
	return true


func can_claim(task_id: String) -> bool:
	var action := action_for_task(task_id)
	if action == null or task_state(task_id) != TaskState.APPLYING:
		return false
	return cooldowns.is_ready(action.id)


func claim_action(task_id: String) -> bool:
	if not can_claim(task_id):
		return false
	var action := action_for_task(task_id)
	cooldowns.clear(action.id)
	_complete_action(task_id, action)
	return true


func speed_up_with_hard(task_id: String) -> bool:
	var action := action_for_task(task_id)
	if action == null or not cooldowns.is_running(action.id):
		return false
	if action.speedup_hard_cost <= 0 or not player.pay("hard", action.speedup_hard_cost):
		return false
	cooldowns.finish_now(action.id)
	return true


func speed_up_with_ad(task_id: String) -> bool:
	var action := action_for_task(task_id)
	if action == null or not cooldowns.is_running(action.id) or action.ad_reduce_sec <= 0:
		return false
	if not MockServices.show_rewarded_ad("cooldown_" + action.id):
		return false
	cooldowns.reduce(action.id, action.ad_reduce_sec)
	return true


func _complete_action(task_id: String, action: MetaActionDefinition) -> void:
	var lines := EffectRunner.apply(action.effects, self)
	for l in lines:
		pending_narrative.append(l)
	_pay_task_reward(task_id)
	task_states[task_id] = TaskState.COMPLETED
	EventBus.task_state_changed.emit(task_id, TaskState.COMPLETED)
	refresh()


## Награда за задачу выдаётся один раз за партию. Состояния задач пересчитываются
## на каждом refresh и после каждой загрузки сейва, поэтому «задача выполнена» —
## не событие, а факт, и платить по нему нельзя: список выданных наград и есть
## то, что отличает первое выполнение от сотого пересчёта.
func _pay_task_reward(task_id: String) -> void:
	if rewarded_tasks.has(task_id):
		return
	var task: MetaTaskDefinition = db.task(task_id)
	if task == null or task.reward_coins <= 0:
		return
	rewarded_tasks[task_id] = true
	player.grant("coins", task.reward_coins)


func take_narrative() -> PackedStringArray:
	var out := pending_narrative.duplicate()
	pending_narrative = PackedStringArray()
	return out


## --- отложенный диалог ------------------------------------------------------

## Эффект действия может попросить показать сцену-диалог. Мета её не открывает
## сама: экранами распоряжается Game, и вызов сцены отсюда сделал бы мету
## зависимой от того, что вообще есть экраны. Поэтому диалог складывается сюда,
## а забирает его тот, кто в этот момент решает, куда вести игрока.
##
## В сейв не попадает намеренно: это событие момента, а не состояние мира.
## Диалог, не показанный из-за выхода из игры, не должен всплыть через неделю
## посреди другого занятия — а то, ради чего он игрался, уже записано флагом.
func queue_dialog(dialog_id: String) -> void:
	if dialog_id.is_empty():
		return
	pending_dialogs.append(dialog_id)


func take_dialog() -> String:
	if pending_dialogs.is_empty():
		return ""
	var next: String = pending_dialogs[0]
	pending_dialogs.remove_at(0)
	return next


## --- save -------------------------------------------------------------------

func save_data() -> Dictionary:
	var tasks_out := {}
	for k in task_states:
		tasks_out[k] = STATE_NAMES[int(task_states[k])]
	return {
		"shops": shop_states.duplicate(true),
		"tasks": tasks_out,
		"completed_levels": completed_levels.duplicate(),
		"levels_completed_total": levels_completed_total,
		"flags": flags.duplicate(),
		"rewarded_tasks": rewarded_tasks.duplicate(),
	}


func load_data(d: Dictionary) -> void:
	shop_states = (d.get("shops", {}) as Dictionary).duplicate(true)
	task_states = {}
	for k in d.get("tasks", {}):
		var idx := STATE_NAMES.find(String(d["tasks"][k]))
		task_states[String(k)] = idx if idx >= 0 else TaskState.LOCKED
	completed_levels = {}
	for k in d.get("completed_levels", {}):
		completed_levels[String(k)] = int(d["completed_levels"][k])
	levels_completed_total = int(d.get("levels_completed_total", 0))
	flags = (d.get("flags", {}) as Dictionary).duplicate()
	## Без этого списка загрузка сейва пересчитала бы состояния задач и заплатила
	## за каждую пройденную заново — на каждом запуске игры.
	rewarded_tasks = (d.get("rewarded_tasks", {}) as Dictionary).duplicate()
	## Отложенные сцены и тексты не переживают загрузку. Разговор привязан к
	## моменту, когда действие применилось; пересчёт меты на загрузке вправе
	## доиграть недоделанное, но всплыть этот разговор должен был тогда, а не
	## посреди следующего экрана в другой сессии.
	pending_dialogs.clear()
	pending_narrative = PackedStringArray()


## Пересчёт сразу после загрузки сейва. Состояния догоняются как обычно, но
## сцены и тексты, которые при этом накопились, отбрасываются.
##
## Разговор принадлежит моменту, когда игрок что-то сделал: прошёл уровень,
## тронул дверь. На загрузке этот момент уже прошёл — либо игрок видел сцену в
## той сессии, либо не увидит вовсе. Оставленный в очереди, такой разговор
## всплывает при первом же следующем тапе, посреди чужого экрана.
func refresh_after_load() -> void:
	refresh()
	pending_dialogs.clear()
	pending_narrative = PackedStringArray()


func reset() -> void:
	shop_states.clear()
	task_states.clear()
	completed_levels.clear()
	flags.clear()
	rewarded_tasks.clear()
	levels_completed_total = 0
	pending_narrative = PackedStringArray()
	pending_dialogs.clear()
	ensure_defaults()
