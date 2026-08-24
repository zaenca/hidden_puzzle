extends SceneTree
## Валидатор контента. Ловит самый дорогой класс багов — «мёртвый прогресс»
## и рассыпавшиеся ссылки — до того, как их увидит игрок.
##
##   godot --headless --path . --script res://tools/validate_content.gd
##
## Не зависит от автолоадов: читает JSON напрямую, поэтому годится и для CI.

const ROOT := "res://content/"
const MIN_TARGET_SIDE := 0.035   ## ~38 px при базовом 1080 — минимум под палец

var errors: PackedStringArray = PackedStringArray()
var warnings: PackedStringArray = PackedStringArray()

var items := {}
var tasks := {}
var actions := {}
var shops := {}
var levels := {}
var index := []


func _initialize() -> void:
	_load()
	if errors.is_empty():
		_check_ids()
		_check_levels()
		_check_actions()
		_check_tasks()
		_check_shops()
		_check_item_flow()
		_simulate_progression()
	_report()
	quit(1 if not errors.is_empty() else 0)


func _err(msg: String) -> void:
	errors.append(msg)


func _warn(msg: String) -> void:
	warnings.append(msg)


func _load() -> void:
	var items_raw = ContentParser.read_json(ROOT + "items.json")
	if not (items_raw is Array):
		_err("items.json не читается")
		return
	for d in items_raw:
		var it := ContentParser.item(d)
		items[it.id] = it

	for d in ContentParser.read_json(ROOT + "tasks.json"):
		var t := ContentParser.task(d)
		tasks[t.id] = t

	for d in ContentParser.read_json(ROOT + "actions.json"):
		var a := ContentParser.action(d)
		actions[a.id] = a

	index = ContentParser.read_json(ROOT + "level_index.json")
	if not (index is Array):
		_err("level_index.json не читается")
		return
	for entry in index:
		var path := String(entry.get("path", ""))
		var d = ContentParser.read_json(path)
		if not (d is Dictionary):
			_err("Уровень %s: файл %s не читается" % [entry.get("id", "?"), path])
			continue
		var lvl := ContentParser.level(d)
		levels[lvl.id] = lvl

	var map = ContentParser.read_json(ROOT + "map.json")
	if map is Dictionary:
		for f in map.get("shops", []):
			var sd = ContentParser.read_json(ROOT + String(f))
			if sd is Dictionary:
				var s := ContentParser.shop(sd)
				shops[s.id] = s


func _check_ids() -> void:
	for entry in index:
		var id := String(entry.get("id", ""))
		if not levels.has(id):
			_err("level_index: уровень %s не загрузился" % id)
			continue
		if levels[id].id != id:
			_err("level_index: id '%s' не совпадает с id внутри файла ('%s')" % [id, levels[id].id])

	var orders := {}
	for lvl in levels.values():
		var key := "%s:%d" % [lvl.shop_id, lvl.order]
		if orders.has(key):
			_err("Дубль order: %s и %s" % [orders[key], lvl.id])
		orders[key] = lvl.id


func _check_levels() -> void:
	for lvl_v in levels.values():
		var lvl: LevelDefinition = lvl_v
		if not tasks.has(lvl.task_id):
			_err("%s: неизвестная задача '%s'" % [lvl.id, lvl.task_id])
		if not PuzzleRegistry.is_known(lvl.puzzle.module_id):
			_err("%s: неизвестный puzzle-модуль '%s'" % [lvl.id, lvl.puzzle.module_id])

		var jig := lvl.puzzle as JigsawParams
		if jig != null and jig.piece_count() < 4:
			_warn("%s: слишком мало частей пазла (%d)" % [lvl.id, jig.piece_count()])

		var ho := lvl.hidden_object
		var normals := ho.normal_target_count()
		if ho.required_normal > normals:
			_err("%s: required_normal=%d, а обычных целей всего %d" % [lvl.id, ho.required_normal, normals])
		if ho.targets.is_empty():
			_err("%s: нет целей hidden object" % lvl.id)

		var seen := {}
		var quest_ids := PackedStringArray()
		for t in ho.targets:
			if seen.has(t.id):
				_err("%s: дубль id цели '%s'" % [lvl.id, t.id])
			seen[t.id] = true
			if not items.has(t.item_id):
				_err("%s / %s: нет предмета '%s' в items.json" % [lvl.id, t.id, t.item_id])
			elif t.is_quest() and not items[t.item_id].is_quest():
				_err("%s / %s: цель помечена quest, но предмет '%s' — не quest" % [lvl.id, t.id, t.item_id])
			if t.is_quest():
				quest_ids.append(t.item_id)

			var b := t.bounds()
			if b.position.x < 0.0 or b.position.y < 0.0 or b.end.x > 1.0 or b.end.y > 1.0:
				_err("%s / %s: цель выходит за пределы изображения" % [lvl.id, t.id])
			if b.size.x < MIN_TARGET_SIDE or b.size.y < MIN_TARGET_SIDE:
				_warn("%s / %s: цель мельче минимального touch-таргета" % [lvl.id, t.id])

		for granted in lvl.quest_grants:
			if not quest_ids.has(String(granted)):
				_err("%s: quest_grants содержит '%s', но такой quest-цели в сцене нет" % [lvl.id, granted])
		for q in quest_ids:
			if not lvl.quest_grants.has(q):
				_warn("%s: quest-цель '%s' не указана в quest_grants" % [lvl.id, q])


func _check_actions() -> void:
	for a in actions.values():
		for r in a.requirements:
			if r.kind == Requirement.Kind.ITEM:
				if not items.has(r.id):
					_err("action %s: требует несуществующий предмет '%s'" % [a.id, r.id])
		for c in a.costs:
			if not (c.id in ["coins", "hard", "xp"]) and not items.has(c.id):
				_err("action %s: цена в несуществующей валюте/предмете '%s'" % [a.id, c.id])
		for e in a.effects:
			match e.kind:
				MetaEffect.Kind.SET_VISUAL_STATE:
					var shop: ShopDefinition = shops.get(e.shop_id)
					if shop == null:
						_err("action %s: неизвестный магазин '%s'" % [a.id, e.shop_id])
					else:
						var slot := shop.slot(e.slot_id)
						if slot == null:
							_err("action %s: у магазина '%s' нет слота '%s'" % [a.id, e.shop_id, e.slot_id])
						elif not slot.has_state(e.state_id):
							_err("action %s: у слота '%s' нет состояния '%s'" % [a.id, e.slot_id, e.state_id])
				MetaEffect.Kind.CONSUME, MetaEffect.Kind.GRANT:
					if not items.has(e.id) and not (e.id in ["coins", "hard", "xp"]):
						_err("action %s: эффект ссылается на неизвестный id '%s'" % [a.id, e.id])
		if a.duration_sec > 0 and a.speedup_hard_cost <= 0 and a.ad_reduce_sec <= 0:
			_warn("action %s: cooldown без единого способа ускорения" % a.id)


## Слоты магазинов: состояния, ссылки на предметы и достижимость входа внутрь.
func _check_shops() -> void:
	for shop_v in shops.values():
		var shop: ShopDefinition = shop_v
		for slot in shop.slots:
			if not slot.default_state.is_empty() and not slot.has_state(slot.default_state):
				_err("%s/%s: default-состояние '%s' не описано"
					% [shop.id, slot.id, slot.default_state])
			for i in slot.interactions:
				if not i.state.is_empty() and not slot.has_state(i.state):
					_err("%s/%s: правило ссылается на состояние '%s', которого нет"
						% [shop.id, slot.id, i.state])
				if not i.set_state.is_empty() and not slot.has_state(i.set_state):
					_err("%s/%s: правило переводит в состояние '%s', которого нет"
						% [shop.id, slot.id, i.set_state])
				if not i.use_item.is_empty() and not items.has(i.use_item):
					_err("%s/%s: правило требует предмет '%s', которого нет в items.json"
						% [shop.id, slot.id, i.use_item])
				if not i.grant_item.is_empty() and not items.has(i.grant_item):
					_err("%s/%s: правило выдаёт предмет '%s', которого нет в items.json"
						% [shop.id, slot.id, i.grant_item])
				if i.text.is_empty():
					_warn("%s/%s: правило без текста — игрок не поймёт, что произошло"
						% [shop.id, slot.id])

		if shop.enter.is_empty():
			continue
		var flag := String(shop.enter.get("requires_flag", ""))
		if not flag.is_empty() and not _flags_set_anywhere().has(flag):
			_err("%s: вход внутрь ждёт флаг '%s', который никто не выставляет"
				% [shop.id, flag])


## Все флаги, которые кто-то в контенте вообще может выставить.
func _flags_set_anywhere() -> Dictionary:
	var out := {}
	for a in actions.values():
		for e in a.effects:
			if e.kind == MetaEffect.Kind.SET_FLAG:
				out[e.id] = true
	for shop in shops.values():
		for slot in shop.slots:
			for i in slot.interactions:
				if not i.set_flag.is_empty():
					out[i.set_flag] = true
				if not i.once_flag.is_empty():
					out[i.once_flag] = true
	return out


## Предмет, который выдаётся и никому не нужен, — мусор в сумке. Проверяем
## только то, что реально выдаётся: уровнями или тапом по объекту.
func _check_item_flow() -> void:
	var granted := {}
	for lvl in levels.values():
		for g in lvl.quest_grants:
			granted[String(g)] = "уровень " + lvl.id
	for shop in shops.values():
		for slot in shop.slots:
			for i in slot.interactions:
				if not i.grant_item.is_empty():
					granted[i.grant_item] = "%s/%s" % [shop.id, slot.id]

	var consumed := {}
	for a in actions.values():
		for r in a.requirements:
			if r.kind == Requirement.Kind.ITEM:
				consumed[r.id] = true
		for e in a.effects:
			if e.kind == MetaEffect.Kind.CONSUME:
				consumed[e.id] = true
	for shop in shops.values():
		for slot in shop.slots:
			for i in slot.interactions:
				if i.consume and not i.use_item.is_empty():
					consumed[i.use_item] = true

	for id in granted:
		if not items.has(id):
			_err("выдаётся несуществующий предмет '%s' (%s)" % [id, granted[id]])
		elif not consumed.has(id):
			_warn("Предмет '%s' выдаётся (%s), но его никто не тратит" % [id, granted[id]])


func _check_tasks() -> void:
	for t in tasks.values():
		if not actions.has(t.action_id):
			_err("task %s: нет action '%s'" % [t.id, t.action_id])
		if not shops.has(t.shop_id):
			_err("task %s: нет магазина '%s'" % [t.id, t.shop_id])
		elif not t.hotspot.is_empty() and shops[t.shop_id].slot(t.hotspot) == null:
			_warn("task %s: hotspot '%s' не соответствует слоту" % [t.id, t.hotspot])
		for lid in t.level_ids:
			if not levels.has(String(lid)):
				_err("task %s: неизвестный уровень '%s'" % [t.id, lid])
		if t.level_ids.is_empty() and t.location != "shop":
			_warn("task %s: нет уровней и не в магазине" % t.id)


## Симуляция линейного прохождения. Проверяет два инварианта:
##  1) прогресс не встаёт — на каждом шаге есть что делать;
##  2) в момент старта cooldown есть хотя бы одна параллельная задача.
func _simulate_progression() -> void:
	var inv := {}
	var flags := {}
	var done_levels := {}
	var done_tasks := {}
	var coins := 100000
	var guard := 0

	while done_tasks.size() < tasks.size() and guard < 200:
		guard += 1
		var acted := false

		for t in tasks.values():
			if done_tasks.has(t.id):
				continue
			if not _unlocked(t, flags, done_levels, done_tasks, inv):
				continue

			# играем невыполненные уровни задачи
			for lid in t.level_ids:
				var level_id := String(lid)
				if done_levels.has(level_id):
					continue
				done_levels[level_id] = true
				for g in levels[level_id].quest_grants:
					inv[String(g)] = int(inv.get(String(g), 0)) + 1
				acted = true

			var a: MetaActionDefinition = actions.get(t.action_id)
			if a == null:
				continue
			if not _requirements_met(a.requirements, inv, flags, done_levels, done_tasks):
				continue
			var affordable := true
			for c in a.costs:
				if c.id != "coins" and int(inv.get(c.id, 0)) < c.amount:
					affordable = false
			if not affordable:
				continue

			if a.duration_sec > 0:
				var parallel := _count_parallel(t.id, flags, done_levels, done_tasks, inv)
				if parallel == 0:
					_err("Прогресс встаёт: во время cooldown '%s' нет ни одной параллельной задачи" % a.id)

			for e in a.effects:
				match e.kind:
					MetaEffect.Kind.CONSUME:
						inv[e.id] = maxi(0, int(inv.get(e.id, 0)) - e.amount)
					MetaEffect.Kind.GRANT:
						inv[e.id] = int(inv.get(e.id, 0)) + e.amount
					MetaEffect.Kind.SET_FLAG:
						flags[e.id] = true
					MetaEffect.Kind.UNLOCK_TASK:
						flags["task_unlocked:" + e.task_id] = true
			done_tasks[t.id] = true
			acted = true

		if not acted:
			var stuck := PackedStringArray()
			for t in tasks.values():
				if not done_tasks.has(t.id):
					stuck.append(t.id)
			_err("Прогресс встаёт: недостижимые задачи — %s" % ", ".join(stuck))
			return

	for lvl in levels.values():
		if not done_levels.has(lvl.id):
			_warn("Уровень %s недостижим при линейном прохождении" % lvl.id)


func _unlocked(t: MetaTaskDefinition, flags, done_levels, done_tasks, inv) -> bool:
	return _requirements_met(t.unlock, inv, flags, done_levels, done_tasks)


func _requirements_met(reqs: Array[Requirement], inv, flags, done_levels, done_tasks) -> bool:
	for r in reqs:
		match r.kind:
			Requirement.Kind.ITEM:
				if int(inv.get(r.id, 0)) < r.amount:
					return false
			Requirement.Kind.FLAG:
				if not bool(flags.get(r.id, false)):
					return false
			Requirement.Kind.LEVEL:
				if not done_levels.has(r.id):
					return false
			Requirement.Kind.TASK:
				if r.state == "completed" and not done_tasks.has(r.id):
					return false
	return true


func _count_parallel(current_id: String, flags, done_levels, done_tasks, inv) -> int:
	var n := 0
	for t in tasks.values():
		if t.id == current_id or done_tasks.has(t.id):
			continue
		if _unlocked(t, flags, done_levels, done_tasks, inv) and not t.level_ids.is_empty():
			n += 1
	return n


func _report() -> void:
	print("=== Валидация контента ===")
	print("Предметы: %d | Задачи: %d | Действия: %d | Уровни: %d | Магазины: %d"
		% [items.size(), tasks.size(), actions.size(), levels.size(), shops.size()])
	for w in warnings:
		print("  [warn]  " + w)
	for e in errors:
		print("  [ERROR] " + e)
	if errors.is_empty():
		print("OK: ошибок нет (предупреждений: %d)" % warnings.size())
	else:
		print("ПРОВАЛ: ошибок %d" % errors.size())
