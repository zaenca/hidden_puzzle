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
## Замеры, которые надо видеть даже когда всё в порядке.
var notes: PackedStringArray = PackedStringArray()

var items := {}
var tasks := {}
var actions := {}
var shops := {}
var levels := {}
var index := []
var rooms := {}
var room_templates := {}
var room_materials := {}


func _initialize() -> void:
	_load()
	if errors.is_empty():
		_check_ids()
		_check_levels()
		_check_actions()
		_check_tasks()
		_check_shops()
		_check_rooms()
		_check_intros()
		_check_dialogs()
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
		## Опечатка в пути иконки не ломает игру — предмет просто откатывается к
		## цветной фигуре. Именно поэтому её надо ловить здесь: в готовой сборке
		## это заметят не сразу и не по тому признаку.
		var icon_path := String(d.get("icon", ""))
		if not icon_path.is_empty() and not ResourceLoader.exists(icon_path):
			_err("предмет %s: нет файла иконки '%s'" % [it.id, icon_path])

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

	for d in _json_array("room_templates.json"):
		var tpl := ContentParser.room_template(d)
		room_templates[tpl.id] = tpl

	for d in _json_array("room_materials.json"):
		var mat := ContentParser.room_material(d)
		room_materials[mat.id] = mat

	## Комнаты проверяются ВСЕ, а не только те, на которые ссылается локация:
	## лаборатория умеет загрузить любую заготовку из каталога, и битая комната
	## без владельца-локации всё равно однажды откроется.
	var rooms_dir := DirAccess.open(ROOT + "rooms")
	if rooms_dir != null:
		for file in rooms_dir.get_files():
			if not file.ends_with(".json"):
				continue
			var room_id := file.trim_suffix(".json")
			var rd = ContentParser.read_json("%srooms/%s" % [ROOT, file])
			if not (rd is Dictionary):
				_err("комната '%s' не читается" % room_id)
				continue
			rooms[room_id] = ContentParser.room(rd)

	for shop_v in shops.values():
		var shop: ShopDefinition = shop_v
		if not shop.room_id.is_empty() and not rooms.has(shop.room_id):
			_err("%s: комнаты '%s' нет в content/rooms" % [shop.id, shop.room_id])


func _json_array(file: String) -> Array:
	var d = ContentParser.read_json(ROOT + file)
	return d if d is Array else []


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
		if not GameplayRegistry.is_known(lvl.mode):
			_err("%s: неизвестный режим геймплея '%s'" % [lvl.id, lvl.mode])
		_check_sort(lvl)
		## Пустой модуль — это «уровень без сборки», а не опечатка: в зале игрок
		## убирается, и пазла там нет по замыслу.
		if not lvl.puzzle.module_id.is_empty() and not PuzzleRegistry.is_known(lvl.puzzle.module_id):
			_err("%s: неизвестный puzzle-модуль '%s'" % [lvl.id, lvl.puzzle.module_id])
		## Арт часто приезжает позже контента, и уровень остаётся играбельным на
		## заглушке — но молча собирать не ту картинку игрок не должен.
		if not lvl.art.background_path.is_empty() and not ResourceLoader.exists(lvl.art.background_path):
			_warn("%s: нет файла фона '%s' — уровень пойдёт на заглушечном арте"
				% [lvl.id, lvl.art.background_path])

		var jig := lvl.puzzle as JigsawParams
		if jig != null and jig.piece_count() < 4:
			_warn("%s: слишком мало частей пазла (%d)" % [lvl.id, jig.piece_count()])

		var ho := lvl.hidden_object
		var normals := ho.normal_target_count()
		if ho.required_normal > normals:
			_err("%s: required_normal=%d, а обычных целей всего %d" % [lvl.id, ho.required_normal, normals])
		## Уровень без целей — это чистый пазл, а не ошибка контента: сюжетный
		## предмет тогда приходит из quest_grants. Дырой он становится только
		## если он вообще ни на что не влияет — ни находкой, ни выдачей, ни как
		## условие мета-действия («пазл собран» само по себе двигает историю).
		if ho.targets.is_empty() and lvl.quest_grants.is_empty() and lvl.cleanup.is_empty() \
				and not _levels_required_by_actions().has(lvl.id):
			_warn("%s: ни целей hidden object, ни quest_grants — уровень не двигает сюжет" % lvl.id)

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

		_check_cleanup(lvl)

		for granted in lvl.quest_grants:
			var gid := String(granted)
			if not items.has(gid):
				_err("%s: quest_grants содержит несуществующий предмет '%s'" % [lvl.id, gid])
			elif not ho.targets.is_empty() and not quest_ids.has(gid):
				_err("%s: quest_grants содержит '%s', но такой quest-цели в сцене нет" % [lvl.id, gid])
		for q in quest_ids:
			if not lvl.quest_grants.has(q):
				_warn("%s: quest-цель '%s' не указана в quest_grants" % [lvl.id, q])


## Sort-уровень. Самый дорогой баг здесь — непроходимая раскладка: она
## выглядит нормальным уровнем ровно до того хода, после которого игрок уже
## ничего не может сделать. Поэтому проходимость не осматривается глазами, а
## доказывается солвером — тем же, которым уровень проходит headless-прогон.
func _check_sort(lvl: LevelDefinition) -> void:
	if lvl.mode != "sort":
		if lvl.sort != null:
			_warn("%s: раскладка Sort описана, но режим уровня '%s'" % [lvl.id, lvl.mode])
		return
	var s := lvl.sort
	if s == null:
		_err("%s: режим sort, но раскладки нет" % lvl.id)
		return

	if s.tray_size <= 0:
		_err("%s: лоток на %d ячеек" % [lvl.id, s.tray_size])
		return
	if s.group_size < 2:
		_err("%s: группа из %d предметов — закрывать нечего" % [lvl.id, s.group_size])
		return
	## Лоток обязан вмещать больше одной незакрытой группы, иначе игрок
	## проигрывает механически, а не по ошибке.
	if s.tray_size <= s.group_size:
		_err("%s: лоток (%d) не больше группы (%d) — ошибиться невозможно, проиграть неизбежно"
			% [lvl.id, s.tray_size, s.group_size])
	## Первый уровень задаёт ритм всей игре: семь ячеек — это обещание, и
	## менять его в туториале нельзя.
	if lvl.order == 1 and s.tray_size != 7:
		_err("%s: первый уровень обязан идти с лотком на 7 ячеек, а не на %d"
			% [lvl.id, s.tray_size])
	if s.seed == 0:
		_err("%s: нет seed — «Заново» вернёт не тот же уровень" % lvl.id)
	if not s.zones.is_empty():
		_err("%s: zones пока не поддерживаются модулем — уровень с ними не сыграется" % lvl.id)
	if not s.tutorial_id.is_empty() \
			and not FileAccess.file_exists("%stutorial/%s.json" % [ROOT, s.tutorial_id]):
		_err("%s: обучение '%s' не найдено в content/tutorial" % [lvl.id, s.tutorial_id])
	if s.items.is_empty():
		_err("%s: на поле нет ни одного предмета" % lvl.id)
		return

	var ids := {}
	for inst in s.items:
		var who := "%s / %s" % [lvl.id, inst.id]
		if inst.id.is_empty():
			_err("%s: предмет без id" % lvl.id)
			continue
		if ids.has(inst.id):
			_err("%s: дубль id предмета" % who)
		ids[inst.id] = inst
		if not items.has(inst.item_id):
			_err("%s: нет предмета '%s' в items.json" % [who, inst.item_id])
		if not s.has_category(inst.category):
			_err("%s: категории '%s' нет в списке категорий уровня" % [who, inst.category])
		## Позиция — центр, поэтому за край уезжает половина размера. Половина
		## считается одинаковой по обеим осям, хотя `size` — доля ШИРИНЫ поля:
		## пропорций поля контент не знает (их задаёт экран), и запас в пользу
		## отступа от края здесь дешевле, чем предмет, срезанный на телефоне с
		## другим соотношением сторон.
		var half := inst.size * 0.5
		if inst.position.x - half < 0.0 or inst.position.y - half < 0.0 \
				or inst.position.x + half > 1.0 or inst.position.y + half > 1.0:
			_err("%s: предмет выходит за игровое поле" % who)
		if inst.size < MIN_TARGET_SIDE * 2.0:
			_warn("%s: предмет мельче удобного touch-таргета (%.3f)" % [who, inst.size])

	for inst in s.items:
		for blocker in inst.blocked_by:
			if not ids.has(String(blocker)):
				_err("%s / %s: накрыт несуществующим предметом '%s'"
					% [lvl.id, inst.id, blocker])
			elif String(blocker) == inst.id:
				_err("%s / %s: предмет накрывает сам себя" % [lvl.id, inst.id])

	## Категория, которая не делится на группы, оставляет на поле предметы,
	## которые невозможно закрыть НИКОГДА, — и уровень не заканчивается.
	for category_id in s.category_counts():
		var n := int(s.category_counts()[category_id])
		if n % s.group_size != 0:
			_err("%s: в категории '%s' %d предметов — не делится на группы по %d"
				% [lvl.id, category_id, n, s.group_size])
	for c in s.categories:
		if not s.category_counts().has(c.id):
			_warn("%s: категория '%s' описана, но на поле её нет" % [lvl.id, c.id])

	_check_sort_solvable(lvl, s)


## Проходимость и достижимость. Первое доказывает солвер; второе — обход графа
## блокировок: предмет, накрытый кольцом других, солвер тоже не достанет, но
## сказать об этом словами «уровень не решается» значит спрятать причину.
func _check_sort_solvable(lvl: LevelDefinition, s: SortDefinition) -> void:
	var reachable := {}
	var changed := true
	while changed:
		changed = false
		for inst in s.items:
			if reachable.has(inst.id):
				continue
			var free := true
			for blocker in inst.blocked_by:
				if not reachable.has(String(blocker)):
					free = false
					break
			if free:
				reachable[inst.id] = true
				changed = true
	for inst in s.items:
		if not reachable.has(inst.id):
			_err("%s / %s: до предмета нельзя добраться — блокировки замкнуты в кольцо"
				% [lvl.id, inst.id])
			return

	var plan := SortSolver.solve(s)
	if bool(plan["exhausted"]):
		_warn("%s: перебор не доказал проходимость за %d состояний" % [lvl.id, int(plan["nodes"])])
		return
	if not bool(plan["solved"]):
		_err("%s: уровень непроходим — ни один порядок не разбирает поле" % lvl.id)
		return
	var path: PackedStringArray = plan["path"]
	if path.size() != s.items.size():
		_err("%s: решение разбирает %d предметов из %d" % [lvl.id, path.size(), s.items.size()])
	if int(plan["max_tray"]) > s.tray_size:
		_err("%s: известное решение переполняет лоток (%d при %d ячейках)"
			% [lvl.id, int(plan["max_tray"]), s.tray_size])
	## Пиковая занятость — главная цифра уровня: по ней видно, насколько тесно
	## игроку на найденном пути и остаётся ли ему запас на ошибку. Печатается
	## всегда, даже когда всё в порядке: «ошибок нет» об этом не говорит.
	notes.append("%s: решение из %d ходов, лоток в пике %d из %d"
		% [lvl.id, path.size(), int(plan["max_tray"]), s.tray_size])


func _check_actions() -> void:
	## Диалог, который действие обещает показать, обязан существовать: сцена
	## ищется по имени файла, и опечатка здесь заканчивается пустым экраном
	## ровно в момент сюжетного перехода.
	for a in actions.values():
		for e in a.effects:
			if e.kind != MetaEffect.Kind.DIALOG:
				continue
			if e.dialog_id.is_empty():
				_err("action %s: эффект dialog без имени диалога" % a.id)
			elif not FileAccess.file_exists("%sdialogs/%s.json" % [ROOT, e.dialog_id]):
				_err("action %s: диалога '%s' нет в content/dialogs" % [a.id, e.dialog_id])

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
				MetaEffect.Kind.SET_SHOP_STATE:
					if not shops.has(e.shop_id):
						_err("action %s: переводит в состояние несуществующий магазин '%s'" % [a.id, e.shop_id])
				MetaEffect.Kind.CONSUME, MetaEffect.Kind.GRANT:
					if not items.has(e.id) and not (e.id in ["coins", "hard", "xp"]):
						_err("action %s: эффект ссылается на неизвестный id '%s'" % [a.id, e.id])
		if a.duration_sec > 0 and a.speedup_hard_cost <= 0 and a.ad_reduce_sec <= 0:
			_warn("action %s: cooldown без единого способа ускорения" % a.id)


## Слоты магазинов: состояния, ссылки на предметы и достижимость входа внутрь.
func _check_shops() -> void:
	for shop_v in shops.values():
		var shop: ShopDefinition = shop_v
		## Локация без арта играется на градиенте, но rect'ы слотов размечены
		## под картинку — попадать пальцем в пустоту игрок будет уже как есть.
		if not shop.background_path.is_empty() and not ResourceLoader.exists(shop.background_path):
			_warn("%s: нет файла фона '%s' — локация пойдёт на градиенте"
				% [shop.id, shop.background_path])
		var back_shop := String(shop.back.get("shop_id", ""))
		if not back_shop.is_empty() and not shops.has(back_shop):
			_err("%s: кнопка «назад» ведёт в несуществующую локацию '%s'" % [shop.id, back_shop])
		for slot in shop.slots:
			if not slot.default_state.is_empty() and not slot.has_state(slot.default_state):
				_err("%s/%s: default-состояние '%s' не описано"
					% [shop.id, slot.id, slot.default_state])
			for st in slot.states:
				if st.has_texture() and not ResourceLoader.exists(st.texture_path):
					_warn("%s/%s: нет файла картинки '%s' — объект не будет виден"
						% [shop.id, slot.id, st.texture_path])
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

		## Режим подсветки — из закрытого набора: опечатка в нём молча
		## превращается в «auto», и объект, который игрок должен искать,
		## оказывается обведён рамкой.
		for slot in shop.slots:
			if not (slot.highlight in ["auto", "always", "never"]):
				_err("%s/%s: неизвестный режим подсветки '%s'"
					% [shop.id, slot.id, slot.highlight])

		## Полоска «что здесь собрать»: ячейки должны ссылаться на настоящие
		## предметы, а флаг завершения — кем-то выставляться, иначе полоска
		## останется висеть в убранной локации.
		if not shop.collection.is_empty():
			var coll_items: Array = shop.collection.get("items", [])
			if coll_items.is_empty():
				_err("%s: collection без единой ячейки" % shop.id)
			for raw in coll_items:
				if not items.has(String(raw)):
					_err("%s: в collection предмет '%s', которого нет в items.json"
						% [shop.id, raw])
			var done_flag := String(shop.collection.get("done_flag", ""))
			if not done_flag.is_empty() and not _flags_set_anywhere().has(done_flag):
				_err("%s: collection ждёт флаг '%s', который никто не выставляет"
					% [shop.id, done_flag])

		## Первый визит обставлен заставкой — обе половины обязаны быть на месте,
		## иначе игрок либо не увидит сцену, либо увидит её каждый раз.
		if not shop.first_visit.is_empty():
			var fv_intro := String(shop.first_visit.get("intro", ""))
			var fv_flag := String(shop.first_visit.get("flag", ""))
			if fv_intro.is_empty() or fv_flag.is_empty():
				_err("%s: first_visit нужен и intro, и flag" % shop.id)
			elif not FileAccess.file_exists("%sintros/%s.json" % [ROOT, fv_intro]):
				_err("%s: first_visit ссылается на несуществующую заставку '%s'"
					% [shop.id, fv_intro])
			elif not _flags_set_anywhere().has(fv_flag):
				_err("%s: флаг первого визита '%s' никто не выставляет — сцена будет повторяться"
					% [shop.id, fv_flag])

		if shop.enter.is_empty():
			continue
		var flag := String(shop.enter.get("requires_flag", ""))
		if not flag.is_empty() and not _flags_set_anywhere().has(flag):
			_err("%s: вход внутрь ждёт флаг '%s', который никто не выставляет"
				% [shop.id, flag])
		var enter_shop := String(shop.enter.get("open_shop", ""))
		if not enter_shop.is_empty() and not shops.has(enter_shop):
			_err("%s: вход ведёт в несуществующую локацию '%s'" % [shop.id, enter_shop])
		elif enter_shop.is_empty() and String(shop.enter.get("text", "")).is_empty():
			_warn("%s: вход никуда не ведёт и ничего не говорит" % shop.id)


## Заставки и связки между сценами. Завязка теперь цепочка
## «заставка → диалог → уровень → магазин», и оборванная ссылка в середине
## означает, что игрок упрётся в карту без объяснений.
func _check_intros() -> void:
	var dir := DirAccess.open(ROOT + "intros")
	if dir == null:
		return
	for file in dir.get_files():
		if not file.ends_with(".json"):
			continue
		var d = ContentParser.read_json("%sintros/%s" % [ROOT, file])
		if not (d is Dictionary):
			_err("заставка %s не читается" % file)
			continue

		var bg := String(d.get("background", ""))
		if bg.is_empty():
			_warn("заставка %s: нет фона" % file)
		elif not ResourceLoader.exists(bg):
			_err("заставка %s: нет файла фона '%s'" % [file, bg])

		if (d.get("screens", []) as Array).is_empty():
			_err("заставка %s: нет ни одного экрана" % file)

		_check_on_finish("заставка " + file, d.get("on_finish", {}))


## Куда сцена ведёт после себя. Ссылка на несуществующий диалог/заставку/задачу
## тихо превращается в «вернуться на карту» — самый незаметный вид обрыва.
func _check_on_finish(who: String, on_finish: Dictionary) -> void:
	if on_finish.is_empty():
		return
	var next_dialog := String(on_finish.get("dialog", ""))
	if not next_dialog.is_empty() and not FileAccess.file_exists("%sdialogs/%s.json" % [ROOT, next_dialog]):
		_err("%s: ведёт в несуществующий диалог '%s'" % [who, next_dialog])
	var next_intro := String(on_finish.get("intro", ""))
	if not next_intro.is_empty() and not FileAccess.file_exists("%sintros/%s.json" % [ROOT, next_intro]):
		_err("%s: ведёт в несуществующую заставку '%s'" % [who, next_intro])
	var task_id := String(on_finish.get("play_task", ""))
	if not task_id.is_empty() and not tasks.has(task_id):
		_err("%s: ведёт в несуществующую задачу '%s'" % [who, task_id])
	var shop_id := String(on_finish.get("open_shop", ""))
	if not shop_id.is_empty() and not shops.has(shop_id):
		_err("%s: ведёт в несуществующий магазин '%s'" % [who, shop_id])


## Диалоги. Реплика с опечаткой в говорящем — это пустая табличка имени и не
## тот фон в готовой игре, поэтому проверяется здесь, а не глазами.
func _check_dialogs() -> void:
	var dir := DirAccess.open(ROOT + "dialogs")
	if dir == null:
		return
	for file in dir.get_files():
		if not file.ends_with(".json"):
			continue
		var path := "%sdialogs/%s" % [ROOT, file]
		var d = ContentParser.read_json(path)
		if not (d is Dictionary):
			_err("диалог %s не читается" % file)
			continue

		_check_on_finish("диалог " + file, d.get("on_finish", {}))

		var speakers: Dictionary = d.get("speakers", {})
		var lines: Array = d.get("lines", [])
		if lines.is_empty():
			_err("диалог %s: нет реплик" % file)
		if speakers.is_empty():
			_err("диалог %s: не описан ни один говорящий" % file)

		for sid in speakers:
			var bg := String(speakers[sid].get("background", ""))
			if bg.is_empty():
				_warn("диалог %s / %s: нет фона — говорящего не будет видно" % [file, sid])
			elif not ResourceLoader.exists(bg):
				_err("диалог %s / %s: нет файла фона '%s'" % [file, sid, bg])
			if String(speakers[sid].get("name", "")).is_empty():
				_warn("диалог %s / %s: пустое имя на табличке" % [file, sid])

		var used := {}
		for i in lines.size():
			var line: Dictionary = lines[i]
			var sid := String(line.get("speaker", ""))
			used[sid] = true
			if not speakers.has(sid):
				_err("диалог %s, реплика %d: неизвестный говорящий '%s'" % [file, i + 1, sid])
			if String(line.get("text", "")).strip_edges().is_empty():
				_err("диалог %s, реплика %d: пустой текст" % [file, i + 1])

		for sid in speakers:
			if not used.has(sid):
				_warn("диалог %s: говорящий '%s' описан, но не произносит ни одной реплики"
					% [file, sid])


## Флаги, которые ставят заставки и диалоги через on_finish.set_flag.
func _scene_flags() -> Dictionary:
	var out := {}
	for folder in ["dialogs", "intros"]:
		var dir := DirAccess.open(ROOT + folder)
		if dir == null:
			continue
		for file in dir.get_files():
			if not file.ends_with(".json"):
				continue
			var d = ContentParser.read_json("%s%s/%s" % [ROOT, folder, file])
			if not (d is Dictionary):
				continue
			var flag := String((d.get("on_finish", {}) as Dictionary).get("set_flag", ""))
			if not flag.is_empty():
				out[flag] = true
	return out


## Шаги уборки. Каждый обещает игроку три вещи: предмет в полосе, место, куда
## его тащить, и следующий кадр комнаты. Не хватает любой — шаг молча становится
## тупиком: тащить нечего, некуда или картинка не меняется.
func _check_cleanup(lvl: LevelDefinition) -> void:
	var seen := {}
	for i in lvl.cleanup.size():
		var step: CleanupStep = lvl.cleanup[i]
		var who := "%s / уборка %d" % [lvl.id, i + 1]

		if not items.has(step.item_id):
			_err("%s: нет предмета '%s' в items.json" % [who, step.item_id])
		if seen.has(step.item_id):
			_err("%s: предмет '%s' используется дважды" % [who, step.item_id])
		seen[step.item_id] = true

		if step.art_path.is_empty():
			_err("%s: не задан кадр после шага" % who)
		elif not ResourceLoader.exists(step.art_path):
			_err("%s: нет файла кадра '%s'" % [who, step.art_path])

		var r := step.rect
		if r.position.x < 0.0 or r.position.y < 0.0 or r.end.x > 1.0 or r.end.y > 1.0:
			_err("%s: область выходит за пределы кадра" % who)
		if r.size.x < MIN_TARGET_SIDE or r.size.y < MIN_TARGET_SIDE:
			_warn("%s: область мельче минимального touch-таргета" % who)

	## Уровень, который заканчивается уборкой, не должен ещё и требовать поиска:
	## это две разные концовки, и вторая просто не наступит.
	if not lvl.cleanup.is_empty() and not lvl.hidden_object.targets.is_empty():
		_err("%s: заданы и цели поиска, и шаги уборки — фаза может быть только одна" % lvl.id)

## Такой уровень двигает историю самим фактом прохождения.
## Уровни, без которых не сработает мета-действие. Такой уровень двигает сюжет,
## даже если сам ничего не выдаёт: «пазл собран» и есть условие. Действие ждёт
## последний уровень цепочки — значит открывает её вся цепочка задачи целиком.
func _levels_required_by_actions() -> Dictionary:
	var out := {}
	for a in actions.values():
		for r in a.requirements:
			if r.kind == Requirement.Kind.LEVEL:
				out[r.id] = a.id
	for t in tasks.values():
		var act: MetaActionDefinition = actions.get(t.action_id)
		if act == null:
			continue
		for r in act.requirements:
			if r.kind == Requirement.Kind.LEVEL and t.level_ids.has(r.id):
				for lid in t.level_ids:
					out[String(lid)] = act.id
				break
	return out


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
	## Сцены тоже поднимают флаги — «познакомился с хозяйкой» ставит именно
	## диалог, а не действие.
	for folder in ["dialogs", "intros"]:
		var dir := DirAccess.open(ROOT + folder)
		if dir == null:
			continue
		for file in dir.get_files():
			if not file.ends_with(".json"):
				continue
			var d = ContentParser.read_json("%s%s/%s" % [ROOT, folder, file])
			if d is Dictionary:
				var flag := String((d.get("on_finish", {}) as Dictionary).get("set_flag", ""))
				if not flag.is_empty():
					out[flag] = true
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
		## Задача без уровней вне магазина — либо указатель («сходи туда»,
		## закрывается сама), либо дырка в контенте: строка, по которой игроку
		## нечего нажать и нечего сделать.
		var act: MetaActionDefinition = actions.get(t.action_id)
		if t.level_ids.is_empty() and t.location != "shop" \
				and (act == null or not act.auto_apply):
			_warn("task %s: нет уровней, не в магазине и не закрывается сама" % t.id)


## Симуляция линейного прохождения. Проверяет два инварианта:
##  1) прогресс не встаёт — на каждом шаге есть что делать;
##  2) в момент старта cooldown есть хотя бы одна параллельная задача.
func _simulate_progression() -> void:
	var inv := {}
	## Флаги, которые поднимают сцены (знакомство с хозяйкой ставит диалог, а не
	## действие), считаем достижимыми сразу. Собственных условий у сцен нет — до
	## них доводит цепочка on_finish, а её целостность проверяют _check_intros и
	## _check_dialogs. Моделировать здесь ещё и порядок сцен значило бы держать
	## вторую копию маршрутизации Game.
	var flags := _scene_flags()
	var done_levels := {}
	var slot_states := {}
	var done_tasks := {}
	var coins := 100000
	var guard := 0

	while done_tasks.size() < tasks.size() and guard < 200:
		guard += 1
		## Тап по объекту локации — такая же часть прогресса, как мета-действие:
		## ключ из-под коврика и открытая им дверь не описаны ни одним action,
		## и без их эмуляции всё, что стоит за флагом двери, выглядит мёртвым.
		var acted := _point_and_click(inv, flags, slot_states)

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


## Прогон всех тапов по объектам локаций: пустой рукой и каждым предметом из
## сумки. Правила берутся те же и в том же порядке, что и в MetaService.interact,
## поэтому симуляция не расходится с игрой.
##
## Возвращает true, только если мир реально сдвинулся — иначе цикл симуляции
## считал бы «осмотрел дверь» бесконечным прогрессом.
func _point_and_click(inv: Dictionary, flags: Dictionary, slot_states: Dictionary) -> bool:
	var changed := false
	for shop in shops.values():
		for slot in shop.slots:
			var key := "%s/%s" % [shop.id, slot.id]
			if not slot_states.has(key):
				slot_states[key] = slot.default_state

			var hands := PackedStringArray([""])
			for item_id in inv:
				if int(inv[item_id]) > 0:
					hands.append(String(item_id))

			for hand in hands:
				for rule in slot.interactions:
					if not rule.matches(String(slot_states[key]), hand, flags):
						continue
					# Первое подошедшее правило — единственное сработавшее.
					if not rule.use_item.is_empty() and rule.consume:
						inv[rule.use_item] = maxi(0, int(inv.get(rule.use_item, 0)) - 1)
						changed = true
					if not rule.grant_item.is_empty():
						inv[rule.grant_item] = int(inv.get(rule.grant_item, 0)) + 1
						changed = true
					if not rule.once_flag.is_empty():
						flags[rule.once_flag] = true
						changed = true
					if not rule.set_state.is_empty():
						slot_states[key] = rule.set_state
						changed = true
					if not rule.set_flag.is_empty() and not bool(flags.get(rule.set_flag, false)):
						flags[rule.set_flag] = true
						changed = true
					break
	return changed


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
	for n in notes:
		print("  [note]  " + n)
	for w in warnings:
		print("  [warn]  " + w)
	for e in errors:
		print("  [ERROR] " + e)
	if errors.is_empty():
		print("OK: ошибок нет (предупреждений: %d)" % warnings.size())
	else:
		print("ПРОВАЛ: ошибок %d" % errors.size())


## --- процедурные комнаты ----------------------------------------------------
##
## Ошибки здесь дорогие ровно потому, что они молчаливые: комната без материала
## соберётся на пурпурной шахматке, окно с rect за пределами 0..1 уедет мимо
## стены, а поверхность, которой нет в шаблоне, просто не нарисуется. В кадре
## это видно, но кадр смотрят не после каждой правки JSON.

func _check_rooms() -> void:
	for mat_v in room_materials.values():
		var mat: RoomMaterial = mat_v
		if mat.has_texture() and not ResourceLoader.exists(mat.texture_path):
			_warn("материал %s: нет файла '%s' — пойдёт процедурная заглушка"
				% [mat.id, mat.texture_path])
		if not mat.has_texture() and mat.generator.is_empty():
			_err("материал %s: ни texture, ни generator — рисовать нечем" % mat.id)
		if mat.tile_size.x <= 0.0 or mat.tile_size.y <= 0.0:
			_err("материал %s: нулевой размер плитки" % mat.id)

	for tpl_v in room_templates.values():
		var tpl: RoomTemplate = tpl_v
		if tpl.width <= 0.0 or tpl.depth <= 0.0 or tpl.height <= 0.0:
			_err("шаблон %s: нулевой размер комнаты" % tpl.id)
		## Камера в самом углу — не «странный кадр», а вывернутая наизнанку
		## проекция: половина комнаты окажется за её плоскостью.
		if tpl.cam_distance <= RoomGeometry.SAFE_DEPTH:
			_err("шаблон %s: камера стоит в самом углу (distance %.2f)"
				% [tpl.id, tpl.cam_distance])
			continue
		if tpl.cam_eye_height <= 0.0 or tpl.cam_eye_height >= tpl.height:
			_err("шаблон %s: глаз камеры вне высоты комнаты" % tpl.id)
		if tpl.horizon <= 0.05 or tpl.horizon >= 0.95:
			_err("шаблон %s: линия горизонта за пределами экрана" % tpl.id)
			continue
		_check_template_frame(tpl)

	for room_v in rooms.values():
		var room: RoomDefinition = room_v
		if not room_templates.has(room.template_id):
			_err("комната %s: шаблон '%s' не описан" % [room.id, room.template_id])
		for surface_id in room.surfaces:
			if not RoomGeometry.SURFACES.has(String(surface_id)):
				_err("комната %s: поверхность '%s' не существует (есть %s)"
					% [room.id, surface_id, ", ".join(RoomGeometry.SURFACES)])
		for surface_id in RoomGeometry.SURFACES:
			if not room.surfaces.has(surface_id):
				## Потолок необязателен: без него стены достраиваются вверх и
				## верх кадра остаётся стеной — это выбор, а не забытая строка.
				if surface_id != RoomGeometry.SURFACE_CEILING:
					_warn("комната %s: поверхность '%s' не описана — пойдёт заглушка"
						% [room.id, surface_id])
				continue
			var cfg: RoomSurfaceConfig = room.surfaces[surface_id]
			_check_room_art("комната %s / поверхность %s" % [room.id, surface_id],
				cfg.material_id, cfg.texture_path, cfg.generator)
		## Стены достраиваются вверх ровно затем, чтобы закрыть верх кадра. Если
		## шаблон это отключил, закрыть его должен потолок — иначе там останется
		## дыра, и увидит её игрок, а не автор комнаты.
		var tpl: RoomTemplate = room_templates.get(room.template_id)
		if tpl != null and tpl.wall_extend_up <= 0.0 \
				and not room.surfaces.has(RoomGeometry.SURFACE_CEILING):
			_err("комната %s: шаблон '%s' не достраивает стены вверх, а потолка нет — верх кадра будет пустым"
				% [room.id, room.template_id])
		for el in room.elements:
			_check_room_element(room, el, "элемент")
		for el in room.decals:
			_check_room_element(room, el, "наклейка")
		_check_room_trims(room)
		_check_room_scatter(room)


## Шаблон проверяется тем же кодом, которым он потом рисуется: числа камеры
## сами по себе ничего не говорят, а вот «стык стены с полом уехал за нижний
## край» — говорит, и увидеть это до запуска дешевле, чем после.
func _check_template_frame(tpl: RoomTemplate) -> void:
	var screen := Vector2(1080, 1920)
	var geom := RoomGeometry.build(tpl, screen)
	if geom.corner_base.y <= geom.horizon_y + 40.0:
		_err("шаблон %s: стык стен с полом оказался на линии горизонта — пола не будет видно"
			% tpl.id)
	elif geom.corner_base.y >= screen.y - 80.0:
		_warn("шаблон %s: стык стен с полом почти у нижнего края — пол в кадр не поместится"
			% tpl.id)
	if geom.corner_top.y >= geom.corner_base.y:
		_err("шаблон %s: верх угла ниже его основания — геометрия вывернута" % tpl.id)
	for surface_id in RoomGeometry.SURFACES:
		## Потолок в кадр попадать не обязан: в шаблоне с достроенными вверх
		## стенами его линия стыка уходит выше экрана, и это нормально.
		if surface_id == RoomGeometry.SURFACE_CEILING:
			continue
		var poly: PackedVector2Array = geom.polygons[surface_id]
		if poly.size() < 3:
			_err("шаблон %s: поверхность '%s' не попала в кадр" % [tpl.id, surface_id])


func _check_room_element(room: RoomDefinition, el: RoomElement, kind: String) -> void:
	var who := "комната %s / %s '%s'" % [room.id, kind, el.id if not el.id.is_empty() else el.type]
	if not RoomGeometry.ELEMENT_SURFACES.has(el.surface):
		_err("%s: поверхность '%s' не существует (есть %s)"
			% [who, el.surface, ", ".join(RoomGeometry.ELEMENT_SURFACES)])
	elif el.surface == RoomGeometry.SURFACE_CEILING \
			and not room.surfaces.has(RoomGeometry.SURFACE_CEILING):
		_warn("%s: стоит на потолке, которого у комнаты нет" % who)
	_check_room_art(who, el.material_id, el.texture_path, el.generator)
	if el.stands():
		_check_room_stand(who, el)
	## rect нормализован К ПОВЕРХНОСТИ. Выход за 0..1 — это не «чуть за краем»,
	## а элемент на соседней стене или под полом: там его никто не увидит.
	elif el.rect.size.x <= 0.0 or el.rect.size.y <= 0.0:
		_err("%s: нулевой размер" % who)
	elif el.rect.position.x < -0.001 or el.rect.position.y < -0.001 \
			or el.rect.end.x > 1.001 or el.rect.end.y > 1.001:
		_warn("%s: rect выходит за поверхность — часть окажется за её краем" % who)
	if el.opacity <= 0.0:
		_warn("%s: прозрачность 0 — не будет видно" % who)
	## Привязка к слоту работает только парой: без состояния элемент виден
	## всегда, и «дверь закрыта» нарисуется поверх «дверь открыта».
	if el.slot_id.is_empty() != el.slot_state.is_empty():
		_err("%s: привязке к слоту нужны и slot, и slot_state" % who)


func _check_room_art(who: String, material_id: String,
		texture_path: String, generator: String) -> void:
	if not material_id.is_empty() and not room_materials.has(material_id):
		_err("%s: материал '%s' не описан в room_materials.json" % [who, material_id])
	if not texture_path.is_empty() and not ResourceLoader.exists(texture_path):
		_warn("%s: нет файла '%s'" % [who, texture_path])
	if material_id.is_empty() and texture_path.is_empty() and generator.is_empty():
		_warn("%s: ни материала, ни картинки — пойдёт отладочная заглушка" % who)


func _check_room_trims(room: RoomDefinition) -> void:
	var trims := room.trims
	if trims == null:
		return
	if trims.has_baseboard() and not trims.baseboard_material_id.is_empty() \
			and not room_materials.has(trims.baseboard_material_id):
		_err("комната %s: плинтус ссылается на материал '%s', которого нет"
			% [room.id, trims.baseboard_material_id])
	if trims.has_cornice() and not trims.cornice_material_id.is_empty() \
			and not room_materials.has(trims.cornice_material_id):
		_err("комната %s: карниз ссылается на материал '%s', которого нет"
			% [room.id, trims.cornice_material_id])
	## Карниз — стык стены с потолком. Без потолка ему не с чем стыковаться, и
	## он читается как полоса, приклеенная поперёк стены.
	if trims.has_cornice() and not room.surfaces.has(RoomGeometry.SURFACE_CEILING):
		_warn("комната %s: карниз есть, а потолка нет" % room.id)
	if trims.corner_width > 0.5:
		_warn("комната %s: затемнение угла шире половины стены" % room.id)
	if trims.contact_size > 0.5:
		_warn("комната %s: контактная тень шире половины пола" % room.id)


func _check_room_scatter(room: RoomDefinition) -> void:
	for raw in room.scatter:
		if typeof(raw) != TYPE_DICTIONARY:
			_err("комната %s: правило scatter не словарь" % room.id)
			continue
		var rule: Dictionary = raw
		var material_id := String(rule.get("material", ""))
		if not material_id.is_empty() and not room_materials.has(material_id):
			_err("комната %s: scatter ссылается на материал '%s', которого нет"
				% [room.id, material_id])
		if not RoomGeometry.ELEMENT_SURFACES.has(String(rule.get("surface", ""))):
			_err("комната %s: scatter на несуществующей поверхности '%s'"
				% [room.id, rule.get("surface", "")])
		if int(rule.get("count", 0)) <= 0:
			_warn("комната %s: правило scatter ничего не разбрасывает" % room.id)
	## Зерно — это воспроизводимость. Комната со случайным слоем и нулевым
	## зерном после перезагрузки выглядит иначе, и это баг, а не разнообразие.
	if not room.scatter.is_empty() and room.seed == 0:
		_warn("комната %s: есть scatter, но нет seed — раскладка не воспроизводима"
			% room.id)


## Предмет, стоящий на полу. Ошибки здесь особенно тихие: шкаф с нулевым
## размером просто не рисуется, а поставленный за пределами пола уезжает за
## кадр — и в обоих случаях кажется, что «мебель не работает».
func _check_room_stand(who: String, el: RoomElement) -> void:
	if el.surface != RoomGeometry.SURFACE_FLOOR:
		_err("%s: стоящий предмет ставится только на пол, а не на '%s'"
			% [who, el.surface])
	if el.size.x <= 0.0 or el.size.y <= 0.0:
		_err("%s: нулевой размер предмета" % who)
	elif el.size.x > 12.0 or el.size.y > 12.0:
		_warn("%s: размер %.1f x %.1f единиц — предмет больше комнаты"
			% [who, el.size.x, el.size.y])
	if el.anchor.x < -0.001 or el.anchor.y < -0.001 \
			or el.anchor.x > 1.001 or el.anchor.y > 1.001:
		_warn("%s: предмет стоит за пределами пола — уедет за кадр" % who)
