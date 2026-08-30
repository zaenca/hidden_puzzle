class_name ContentParser
extends RefCounted
## JSON → типизированные Resource-классы.
##
## Почему JSON, а не .tres: для M1 контент авторится руками и скриптами, а .tres
## с вложенными sub_resource неудобно писать вне редактора и он плохо мержится.
## Runtime-контракт при этом остаётся Resource-классами, поэтому переход на
## .tres/инспектор позже не затрагивает ни одну систему кроме ContentDB.

static func read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_error("ContentParser: нет файла %s" % path)
		return null
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	if json.parse(text) != OK:
		push_error("ContentParser: %s — строка %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data


## --- атомы ------------------------------------------------------------------

static func to_rect(a) -> Rect2:
	if typeof(a) != TYPE_ARRAY or a.size() < 4:
		return Rect2()
	return Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3]))


static func to_color(v, fallback := Color.WHITE) -> Color:
	if typeof(v) == TYPE_STRING and not String(v).is_empty():
		return Color.html(String(v))
	return fallback


static func rect_to_polygon(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([
		r.position,
		Vector2(r.position.x + r.size.x, r.position.y),
		r.position + r.size,
		Vector2(r.position.x, r.position.y + r.size.y),
	])


## --- сущности ---------------------------------------------------------------

static func item(d: Dictionary) -> ItemDefinition:
	var it := ItemDefinition.new()
	it.id = String(d.get("id", ""))
	it.display_name = String(d.get("name", it.id))
	it.color = to_color(d.get("color", "#cccccc"))
	it.shape = String(d.get("shape", "rect"))
	## Есть иконка — она и рисуется; нет — цвет с формой, как раньше. Смешивать
	## не нужно: PlaceholderArt сам предпочитает icon, когда тот заполнен.
	## Путь хранится и отдельно: валидатор должен уметь сказать «файла нет»,
	## не загружая ресурс.
	it.icon_path = String(d.get("icon", ""))
	it.icon = Backdrop.load_texture(it.icon_path)
	match String(d.get("kind", "normal")):
		"quest": it.kind = ItemDefinition.Kind.QUEST
		"themed": it.kind = ItemDefinition.Kind.THEMED
		"material": it.kind = ItemDefinition.Kind.MATERIAL
		_: it.kind = ItemDefinition.Kind.NORMAL
	return it


static func ho_target(d: Dictionary) -> HOTarget:
	var t := HOTarget.new()
	t.id = String(d.get("id", ""))
	t.item_id = String(d.get("item_id", ""))
	match String(d.get("kind", "normal")):
		"quest": t.kind = HOTarget.Kind.QUEST
		"themed": t.kind = HOTarget.Kind.THEMED
		_: t.kind = HOTarget.Kind.NORMAL
	if d.has("shape"):
		var pts := PackedVector2Array()
		for p in d["shape"]:
			pts.append(Vector2(float(p[0]), float(p[1])))
		t.shape = pts
	else:
		t.shape = rect_to_polygon(to_rect(d.get("rect", [0, 0, 0.1, 0.1])))
	t.hint_zoom = float(d.get("hint_zoom", 1.6))
	return t


static func scene_art(d: Dictionary) -> SceneArt:
	var a := SceneArt.new()
	var size = d.get("reference_size", [1080, 1350])
	a.reference_size = Vector2i(int(size[0]), int(size[1]))
	a.background_path = String(d.get("background", ""))
	a.objects_background_path = String(d.get("objects_background", ""))
	a.palette = String(d.get("palette", "street"))
	a.seed = int(d.get("seed", 0))
	a.clutter = int(d.get("clutter", 26))
	a.decor = d.get("decor", [])
	return a


static func puzzle_params(d: Dictionary) -> PuzzleParams:
	var module_id := String(d.get("module_id", "jigsaw"))
	match module_id:
		"jigsaw":
			var p := JigsawParams.new()
			p.module_id = module_id
			p.cols = int(d.get("cols", 3))
			p.rows = int(d.get("rows", 4))
			p.seed = int(d.get("seed", 0))
			p.tab_ratio = float(d.get("tab_ratio", 0.20))
			p.snap_distance_px = float(d.get("snap_distance_px", 90.0))
			p.tray_scale = float(d.get("tray_scale", 0.42))
			return p
		_:
			var base := PuzzleParams.new()
			base.module_id = module_id
			return base


static func ho_config(d: Dictionary) -> HOConfig:
	var c := HOConfig.new()
	var list: Array[HOTarget] = []
	for raw in d.get("targets", []):
		list.append(ho_target(raw))
	c.targets = list
	c.required_normal = int(d.get("required_normal", c.normal_target_count()))
	c.time_limit_sec = float(d.get("time_limit_sec", 0.0))
	c.miss_penalty_sec = float(d.get("miss_penalty_sec", 0.0))
	c.allow_zoom = bool(d.get("allow_zoom", true))
	return c


static func rewards(d: Dictionary) -> RewardTable:
	var r := RewardTable.new()
	r.coins = int(d.get("coins", 50))
	r.xp = int(d.get("xp", 10))
	r.replay_factor = float(d.get("replay_factor", 0.3))
	return r


static func cleanup_step(d: Dictionary) -> CleanupStep:
	var s := CleanupStep.new()
	s.item_id = String(d.get("item_id", ""))
	s.find_rect = to_rect(d.get("find", [0, 0, 0, 0]))
	s.rect = to_rect(d.get("rect", [0, 0, 1, 1]))
	s.art_path = String(d.get("art", ""))
	s.hint = String(d.get("hint", ""))
	s.find_hint = String(d.get("find_hint", ""))
	return s


static func level(d: Dictionary) -> LevelDefinition:
	var l := LevelDefinition.new()
	l.id = String(d.get("id", ""))
	l.shop_id = String(d.get("shop_id", ""))
	l.task_id = String(d.get("task_id", ""))
	l.order = int(d.get("order", 0))
	l.difficulty = int(d.get("difficulty", 1))
	l.title = String(d.get("title", l.id))
	l.narrative = PackedStringArray(d.get("narrative", []))
	l.art = scene_art(d.get("art", {}))
	l.puzzle = puzzle_params(d.get("puzzle", {}))
	l.hidden_object = ho_config(d.get("hidden_object", {}))
	l.rewards = rewards(d.get("rewards", {}))
	l.quest_grants = PackedStringArray(d.get("quest_grants", []))
	l.show_result = bool(d.get("show_result", true))
	var steps: Array[CleanupStep] = []
	for raw in d.get("cleanup", []):
		steps.append(cleanup_step(raw))
	l.cleanup = steps
	return l


static func requirement(d: Dictionary) -> Requirement:
	var r := Requirement.new()
	match String(d.get("type", "item")):
		"task":
			r.kind = Requirement.Kind.TASK
			r.id = String(d.get("task_id", ""))
			r.state = String(d.get("state", "completed"))
		"level":
			r.kind = Requirement.Kind.LEVEL
			r.id = String(d.get("level_id", ""))
		"flag":
			r.kind = Requirement.Kind.FLAG
			r.id = String(d.get("flag", ""))
		_:
			r.kind = Requirement.Kind.ITEM
			r.id = String(d.get("item_id", ""))
			r.amount = int(d.get("amount", 1))
	return r


static func cost(d: Dictionary) -> Cost:
	var c := Cost.new()
	c.id = String(d.get("id", "coins"))
	c.amount = int(d.get("amount", 0))
	return c


static func effect(d: Dictionary) -> MetaEffect:
	var e := MetaEffect.new()
	match String(d.get("type", "grant")):
		"set_visual_state":
			e.kind = MetaEffect.Kind.SET_VISUAL_STATE
			e.shop_id = String(d.get("shop_id", ""))
			e.slot_id = String(d.get("slot_id", ""))
			e.state_id = String(d.get("state_id", ""))
		"set_shop_state":
			e.kind = MetaEffect.Kind.SET_SHOP_STATE
			e.shop_id = String(d.get("shop_id", ""))
			e.state_id = String(d.get("state", ""))
		"consume":
			e.kind = MetaEffect.Kind.CONSUME
			e.id = String(d.get("id", ""))
			e.amount = int(d.get("amount", 1))
		"unlock_task":
			e.kind = MetaEffect.Kind.UNLOCK_TASK
			e.task_id = String(d.get("task_id", ""))
		"set_flag":
			e.kind = MetaEffect.Kind.SET_FLAG
			e.id = String(d.get("flag", ""))
		"narrative":
			e.kind = MetaEffect.Kind.NARRATIVE
			e.text = String(d.get("text", ""))
		_:
			e.kind = MetaEffect.Kind.GRANT
			e.id = String(d.get("id", ""))
			e.amount = int(d.get("amount", 1))
	return e


static func action(d: Dictionary) -> MetaActionDefinition:
	var a := MetaActionDefinition.new()
	a.id = String(d.get("id", ""))
	a.title = String(d.get("title", a.id))
	a.description = String(d.get("description", ""))
	a.button_label = String(d.get("button_label", "Применить"))
	var reqs: Array[Requirement] = []
	for raw in d.get("requirements", []):
		reqs.append(requirement(raw))
	a.requirements = reqs
	var costs: Array[Cost] = []
	for raw in d.get("costs", []):
		costs.append(cost(raw))
	a.costs = costs
	a.auto_apply = bool(d.get("auto_apply", false))
	a.duration_sec = int(d.get("duration_sec", 0))
	a.reduce_per_level_sec = int(d.get("reduce_per_level_sec", 0))
	a.speedup_hard_cost = int(d.get("speedup_hard_cost", 0))
	a.ad_reduce_sec = int(d.get("ad_reduce_sec", 0))
	var fx: Array[MetaEffect] = []
	for raw in d.get("effects", []):
		fx.append(effect(raw))
	a.effects = fx
	return a


static func task(d: Dictionary) -> MetaTaskDefinition:
	var t := MetaTaskDefinition.new()
	t.id = String(d.get("id", ""))
	t.shop_id = String(d.get("shop_id", ""))
	t.room_id = String(d.get("room_id", ""))
	t.location = String(d.get("location", "shop"))
	t.title = String(d.get("title", t.id))
	t.hint = String(d.get("hint", ""))
	var reqs: Array[Requirement] = []
	for raw in d.get("unlock", []):
		reqs.append(requirement(raw))
	t.unlock = reqs
	t.level_ids = PackedStringArray(d.get("level_ids", []))
	t.action_id = String(d.get("action_id", ""))
	t.hotspot = String(d.get("hotspot", ""))
	return t


static func shop_slot_state(d: Dictionary) -> ShopSlotState:
	var s := ShopSlotState.new()
	s.id = String(d.get("id", ""))
	s.label = String(d.get("label", s.id))
	s.color = to_color(d.get("color", "#888888"))
	s.shape = String(d.get("shape", "rect"))
	s.hidden = bool(d.get("hidden", false))
	s.overlay = to_color(d.get("overlay", ""), Color(0, 0, 0, 0))
	s.texture_path = String(d.get("texture", ""))
	return s


static func slot_interaction(d: Dictionary) -> SlotInteraction:
	var i := SlotInteraction.new()
	i.state = String(d.get("state", ""))
	i.use_item = String(d.get("use_item", ""))
	i.consume = bool(d.get("consume", false))
	i.grant_item = String(d.get("grant_item", ""))
	i.set_state = String(d.get("set_state", ""))
	i.set_flag = String(d.get("set_flag", ""))
	i.once_flag = String(d.get("once_flag", ""))
	i.text = String(d.get("text", ""))
	i.narrative = String(d.get("narrative", "auto"))
	return i


static func shop_slot(d: Dictionary) -> ShopSlotDefinition:
	var s := ShopSlotDefinition.new()
	s.id = String(d.get("id", ""))
	s.rect = to_rect(d.get("rect", [0, 0, 0.2, 0.2]))
	var states: Array[ShopSlotState] = []
	for raw in d.get("states", []):
		states.append(shop_slot_state(raw))
	s.states = states
	s.default_state = String(d.get("default", states[0].id if not states.is_empty() else ""))
	s.highlight = String(d.get("highlight", "auto"))
	var acts: Array[SlotInteraction] = []
	for raw in d.get("interactions", []):
		acts.append(slot_interaction(raw))
	s.interactions = acts
	return s


static func shop(d: Dictionary) -> ShopDefinition:
	var s := ShopDefinition.new()
	s.id = String(d.get("id", ""))
	s.display_name = String(d.get("display_name", s.id))
	s.palette = String(d.get("palette", "bakery"))
	s.background_path = String(d.get("background", ""))
	s.map_rect = to_rect(d.get("map_rect", [0.1, 0.4, 0.3, 0.2]))
	s.rooms = d.get("rooms", [])
	s.enter = d.get("enter", {})
	s.back = d.get("back", {})
	s.collection = d.get("collection", {})
	s.first_visit = d.get("first_visit", {})
	var slots: Array[ShopSlotDefinition] = []
	for raw in d.get("slots", []):
		slots.append(shop_slot(raw))
	s.slots = slots
	return s
