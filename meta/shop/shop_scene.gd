extends Node2D
## Один ShopScene на ВСЕ магазины. Различия — только в ShopDefinition.
## Сцена не знает слова «пекарня».

const VISUAL_RECT := Rect2(30, 210, 1020, 940)

@onready var _bg: Sprite2D = $Visuals/Background
@onready var _slots_root: Node2D = $Visuals/Slots
@onready var _ui: CanvasLayer = $UI

var shop_id: String = ""
var shop: ShopDefinition

var _slots: Dictionary = {}          ## slot_id -> StateSlot
var _focus: MetaFocus = null
var _task_list: VBoxContainer
var _wallet: Label
var _timers: Dictionary = {}         ## task_id -> Label
var _rows: Dictionary = {}           ## task_id -> Control
var _refresh_acc: float = 0.0
var _rebuilding: bool = false


func setup(payload: Dictionary) -> void:
	shop_id = String(payload.get("shop_id", ""))
	_focus = payload.get("focus")
	if not is_node_ready():
		await ready
	_build()


func _build() -> void:
	shop = ContentDB.shop(shop_id)
	if shop == null:
		push_error("ShopScene: неизвестный магазин '%s'" % shop_id)
		return

	var tex := PlaceholderArt.flat_texture(
		Vector2i(1080, 1920), Palette.top(shop.palette), Palette.bottom(shop.palette))
	_bg.texture = tex
	_bg.centered = false

	for def in shop.slots:
		var slot := StateSlot.create(def, VISUAL_RECT)
		_slots_root.add_child(slot)
		_slots[def.id] = slot
		var state := Game.meta.slot_state(shop_id, def.id)
		slot.set_state(state if not state.is_empty() else def.default_state, false)

	_build_ui()
	_rebuild_tasks()

	EventBus.shop_visual_changed.connect(_on_visual_changed)
	EventBus.task_state_changed.connect(func(_t, _s): _queue_rebuild())
	EventBus.cooldown_finished.connect(func(_a): _queue_rebuild())
	EventBus.currency_changed.connect(func(_i, _v): _update_wallet())

	_show_pending_narrative()


## --- визуальные состояния ---------------------------------------------------

func _on_visual_changed(changed_shop: String, slot_id: String, state_id: String) -> void:
	if changed_shop != shop_id:
		return
	var slot: StateSlot = _slots.get(slot_id)
	if slot != null:
		slot.set_state(state_id, true)


## --- UI ---------------------------------------------------------------------

func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(root)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(margin)
	SafeArea.apply(margin, 20)

	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)

	var header := HBoxContainer.new()
	col.add_child(header)

	var back := UIKit.button("‹ Район", 30)
	back.custom_minimum_size = Vector2(210, 96)
	back.pressed.connect(func(): Game.open_map())
	header.add_child(back)

	var title := UIKit.label(shop.display_name, 36)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(title)

	_wallet = UIKit.label("", 26)
	_wallet.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_wallet)
	_update_wallet()

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(spacer)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 640)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)

	_task_list = VBoxContainer.new()
	_task_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_task_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_task_list)


func _update_wallet() -> void:
	if _wallet != null:
		_wallet.text = "%d ● %d ◆" % [PlayerState.amount_of("coins"), PlayerState.amount_of("hard")]


func _queue_rebuild() -> void:
	call_deferred("_rebuild_tasks")


func _rebuild_tasks() -> void:
	if _task_list == null or _rebuilding:
		return
	_rebuilding = true
	for c in _task_list.get_children():
		c.queue_free()
	_timers.clear()
	_rows.clear()

	for task in Game.meta.tasks_at("shop", shop_id):
		_task_list.add_child(_task_row(task))

	if _focus != null and _rows.has(_focus.task_id):
		_flash(_rows[_focus.task_id])
	_rebuilding = false


func _task_row(task: MetaTaskDefinition) -> Control:
	var panel := UIKit.panel()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)
	_rows[task.id] = panel

	var state: int = Game.meta.task_state(task.id)
	col.add_child(UIKit.label(task.title, 32, UIKit.ACCENT))

	var action: MetaActionDefinition = Game.meta.action_for_task(task.id)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)

	match state:
		MetaService.TaskState.AVAILABLE, MetaService.TaskState.IN_PROGRESS:
			if not task.hint.is_empty():
				col.add_child(UIKit.label(task.hint, 24, Color(0.85, 0.84, 0.8)))
			col.add_child(_missing_label(action))
			if not task.level_ids.is_empty():
				var play := UIKit.button(_play_label(task), 32)
				play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				play.pressed.connect(func(): Game.play_task(task.id))
				buttons.add_child(play)

		MetaService.TaskState.READY_TO_APPLY:
			col.add_child(UIKit.label(action.description if action != null else "", 24))
			var apply := UIKit.button(_apply_label(action), 32)
			apply.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			apply.disabled = not Game.meta.can_start_action(task.id)
			apply.pressed.connect(func(): _on_apply(task.id))
			buttons.add_child(apply)
			var again := UIKit.button("Повтор уровня", 26)
			again.pressed.connect(func(): Game.play_task(task.id))
			buttons.add_child(again)

		MetaService.TaskState.APPLYING:
			var timer := UIKit.label("", 28)
			col.add_child(timer)
			_timers[task.id] = timer
			_update_timer(task.id)
			if Game.meta.can_claim(task.id):
				var claim := UIKit.button("Забрать", 32)
				claim.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				claim.pressed.connect(func(): _on_claim(task.id))
				buttons.add_child(claim)
			else:
				if action != null and action.speedup_hard_cost > 0:
					var fast := UIKit.button("Ускорить · %d ◆" % action.speedup_hard_cost, 28)
					fast.pressed.connect(func(): _on_speedup(task.id))
					buttons.add_child(fast)
				if action != null and action.ad_reduce_sec > 0:
					var ad := UIKit.button("Реклама −%d мин" % int(action.ad_reduce_sec / 60), 28)
					ad.pressed.connect(func(): _on_ad(task.id))
					buttons.add_child(ad)

		MetaService.TaskState.COMPLETED:
			col.add_child(UIKit.label("✓ выполнено", 26, Color(0.55, 0.9, 0.6)))

	if buttons.get_child_count() > 0:
		col.add_child(buttons)
	return panel


func _play_label(task: MetaTaskDefinition) -> String:
	var info := Game.meta.resolve_level_for_task(task.id)
	if info.is_empty():
		return "Играть"
	if bool(info.get("replay", false)):
		return "Повтор (награда ниже)"
	var done := 0
	for lid in task.level_ids:
		if Game.meta.completed_levels.has(lid):
			done += 1
	return "Играть · %d/%d" % [done + 1, task.level_ids.size()]


func _apply_label(action: MetaActionDefinition) -> String:
	if action == null:
		return "Применить"
	if action.is_instant():
		return action.button_label
	return "%s · %s" % [action.button_label, TimeService.format_duration(action.duration_sec)]


func _missing_label(action: MetaActionDefinition) -> Control:
	if action == null:
		return Control.new()
	var missing := TaskResolver.missing(action.requirements, Game.meta)
	if missing.is_empty():
		return Control.new()
	var parts := PackedStringArray()
	for r in missing:
		if r.kind == Requirement.Kind.ITEM:
			parts.append("%s %d/%d" % [
				ContentDB.item_name(r.id), PlayerState.amount_of(r.id), r.amount])
		else:
			parts.append(r.describe())
	return UIKit.label("Нужно: " + ", ".join(parts), 24, Color(0.9, 0.82, 0.6))


## --- действия ---------------------------------------------------------------

func _on_apply(task_id: String) -> void:
	if Game.meta.start_action(task_id):
		SaveService.save_game()
		_show_pending_narrative()
		_rebuild_tasks()
	else:
		EventBus.toast.emit("Условия не выполнены")


func _on_claim(task_id: String) -> void:
	if Game.meta.claim_action(task_id):
		SaveService.save_game()
		_show_pending_narrative()
		_rebuild_tasks()


func _on_speedup(task_id: String) -> void:
	if Game.meta.speed_up_with_hard(task_id):
		SaveService.save_game()
		_rebuild_tasks()
	else:
		EventBus.toast.emit("Не хватает hard currency")


func _on_ad(task_id: String) -> void:
	if Game.meta.speed_up_with_ad(task_id):
		SaveService.save_game()
		_rebuild_tasks()


## --- таймеры ----------------------------------------------------------------

func _process(delta: float) -> void:
	_refresh_acc += delta
	if _refresh_acc < 0.5:
		return
	_refresh_acc = 0.0
	for task_id in _timers.keys():
		_update_timer(task_id)


func _update_timer(task_id: String) -> void:
	var label: Label = _timers.get(task_id)
	var action: MetaActionDefinition = Game.meta.action_for_task(task_id)
	if label == null or action == null:
		return
	var left := CooldownService.remaining(action.id)
	if left <= 0:
		# Перестроение списка НЕ запускаем отсюда: _update_timer вызывается
		# и из _rebuild_tasks, и рекурсивный call_deferred вешает кадр целиком.
		# Перестроение придёт по EventBus.cooldown_finished — он стреляет один раз.
		label.text = "Готово — можно забрать"
	else:
		label.text = "Идёт: %s" % TimeService.format_duration(left)


## --- нарратив ---------------------------------------------------------------

func _show_pending_narrative() -> void:
	var lines := Game.meta.take_narrative()
	if lines.is_empty():
		return
	var overlay := UIKit.full_screen_dim(0.7)
	_ui.add_child(overlay)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(margin)
	SafeArea.apply(margin, 40)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 16)
	margin.add_child(box)

	var panel := UIKit.panel()
	box.add_child(panel)
	var text := UIKit.label("\n\n".join(lines), 32)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(text)

	var ok := UIKit.button("Дальше", 32)
	ok.pressed.connect(func(): overlay.queue_free())
	box.add_child(ok)


func _flash(node: Control) -> void:
	var tw := node.create_tween()
	tw.tween_property(node, "modulate", Color(1.35, 1.25, 0.9), 0.25)
	tw.tween_property(node, "modulate", Color.WHITE, 0.45)
