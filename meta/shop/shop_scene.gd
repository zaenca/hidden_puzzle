extends Node2D
## Один ShopScene на ВСЕ магазины. Различия — только в ShopDefinition.
## Сцена не знает слова «пекарня».

const VISUAL_RECT := Rect2(30, 210, 1020, 940)
const CELL := Vector2(120, 108)   ## ячейка полоски «что здесь надо собрать»
const SCREEN := Vector2(1080, 1920)
const LETTERBOX := Color(0.06, 0.05, 0.05, 1.0)
## Цвета строк на кремовой плашке: пройденное и нехватка ресурсов. Не те же,
## что на тёмной панели, — светло-зелёный по бумаге не читается.
const DONE_GREEN := Color(0.42, 0.50, 0.28)
const MISSING := Color(0.62, 0.34, 0.16)

@onready var _bg: Sprite2D = $Visuals/Background
@onready var _slots_root: Node2D = $Visuals/Slots
@onready var _ui: CanvasLayer = $UI

var shop_id: String = ""
var shop: ShopDefinition

var _slots: Dictionary = {}          ## slot_id -> StateSlot
var _slot_defs: Dictionary = {}      ## slot_id -> ShopSlotDefinition
var _focus: MetaFocus = null
var _task_list: VBoxContainer
var _wallet: Label
var _margin: MarginContainer

## Прямоугольник, к которому нормализованы rect'ы слотов. С настоящим артом это
## область самой картинки на экране, без него — условная VISUAL_RECT.
var _visual_rect: Rect2 = VISUAL_RECT
var _has_art: bool = false
var _timers: Dictionary = {}         ## task_id -> Label
var _rows: Dictionary = {}           ## task_id -> Control
var _refresh_acc: float = 0.0
var _rebuilding: bool = false
var _hint_button: Button = null
var _collection_panel: PanelContainer = null
var _collection_row: HBoxContainer = null
var _hand: TutorialHand = null


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

	_setup_background()

	for def in shop.slots:
		var slot := StateSlot.create(def, _visual_rect, _has_art)
		_slots_root.add_child(slot)
		_slots[def.id] = slot
		_slot_defs[def.id] = def
		slot.set_state(Game.meta.current_slot_state(shop_id, def.id), false)

	_build_ui()
	_rebuild_tasks()
	_refresh_highlights()

	EventBus.shop_visual_changed.connect(_on_visual_changed)
	EventBus.task_state_changed.connect(func(_t, _s): _queue_rebuild())
	EventBus.cooldown_finished.connect(func(_a): _queue_rebuild())
	EventBus.currency_changed.connect(func(_i, _v): _update_wallet())
	EventBus.inventory_changed.connect(func(_i, _v):
		call_deferred("_apply_margins")
		call_deferred("_refresh_collection"))

	_show_pending_narrative()
	_maybe_start_search_hint()


## Арт кладётся «по обрезке»: картинка накрывает экран целиком, лишнее уходит за
## край. Файла нет — прежний градиент по палитре, чтобы магазин без ассетов
## оставался играбельным.
func _setup_background() -> void:
	var tex := Backdrop.load_texture(shop.background_path)
	_has_art = tex != null
	if not _has_art:
		Backdrop.gradient(_bg, shop.palette, SCREEN)
		_visual_rect = VISUAL_RECT
		return

	## Локация вписывается целиком, а не кроется по экрану. Комната здесь —
	## игровое поле: обрезка по бокам уносит за край её объекты вместе с
	## хитбоксами, и игрок ищет дверь, которой на экране нет.
	_fill_letterbox()
	_visual_rect = Backdrop.fit(_bg, tex, SCREEN)


## Полосы над и под вписанным артом. Пустота движка за краем комнаты читается
## как обрыв; тёмная подложка — как рамка вокруг сцены.
func _fill_letterbox() -> void:
	var pad := ColorRect.new()
	pad.color = LETTERBOX
	pad.position = Vector2.ZERO
	pad.size = SCREEN
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.z_index = -1
	_bg.get_parent().add_child(pad)
	_bg.get_parent().move_child(pad, 0)


## --- визуальные состояния ---------------------------------------------------

func _on_visual_changed(changed_shop: String, slot_id: String, state_id: String) -> void:
	if changed_shop != shop_id:
		return
	var slot: StateSlot = _slots.get(slot_id)
	if slot != null:
		slot.set_state(state_id, true)
	_refresh_highlights()
	_queue_rebuild()


## --- point-and-click --------------------------------------------------------

## Тап по фасаду. UI-слой ловит свои нажатия сам (Control'ы стоят на STOP),
## сюда доходит только то, что мимо интерфейса.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventScreenTouch and event.pressed):
		return
	## Любое касание означает «я понял»: рука уходит, даже если игрок промахнулся.
	_stop_search_hint()
	var world: Vector2 = get_canvas_transform().affine_inverse() * event.position

	# С конца: слоты объявлены снизу вверх по слоям, верхний должен побеждать.
	var ids: Array = _slot_defs.keys()
	ids.reverse()
	for slot_id in ids:
		var def: ShopSlotDefinition = _slot_defs[slot_id]
		if not def.is_interactive():
			continue
		var slot: StateSlot = _slots[slot_id]
		if not slot.world_rect.has_point(world):
			continue
		_interact(String(slot_id))
		return


func _interact(slot_id: String) -> void:
	var def: ShopSlotDefinition = _slot_defs.get(slot_id)
	var result := Game.meta.interact(shop_id, slot_id, Game.selected_item)
	if bool(result.get("ok", false)):
		if not String(result.get("consumed", "")).is_empty():
			Game.clear_selection()
		## Первый найденный предмет и есть доказательство, что жест понят —
		## отдельного «нажми ОК» для обучения не нужно.
		if def != null and def.is_searchable():
			Game.meta.set_flag(Game.SEARCH_FLAG, true)
		SaveService.save_game()

	if bool(result.get("narrative", false)):
		_show_pending_narrative()
	elif not String(result.get("text", "")).is_empty():
		EventBus.toast.emit(String(result["text"]))

	_refresh_highlights()
	_rebuild_tasks()


## Подсвечены те объекты, с которыми прямо сейчас есть что сделать, — и те, кому
## подсветка назначена контентом. Второе нужно объектам, которые кликабельны, но
## прогресс пока не двигают: без рамки они неотличимы от нарисованного фона.
func _refresh_highlights() -> void:
	for slot_id in _slot_defs:
		var def: ShopSlotDefinition = _slot_defs[slot_id]
		var slot: StateSlot = _slots[slot_id]
		var state := Game.meta.current_slot_state(shop_id, String(slot_id))
		slot.set_highlight(def.highlight_on(state, Game.meta.flags))


## --- поиск: ячейки, лампочка, обучающий тап ---------------------------------

## Полоска ячеек «что здесь надо собрать». Пусто — иконка тёмным силуэтом,
## предмет в сумке — иконка целиком. Список требований в задаче говорит то же
## самое текстом, но пересчитывать «Паутина 0/1, Лужа 0/1» глазами игрок не
## должен: сколько ещё искать, видно по ячейкам.
func _build_collection(parent: VBoxContainer) -> void:
	if shop.collection.is_empty():
		return
	_collection_panel = UIKit.panel()
	parent.add_child(_collection_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_collection_panel.add_child(box)
	box.add_child(UIKit.label(String(shop.collection.get("title", "Собрать")), 24,
		Color(0.82, 0.80, 0.76)))

	_collection_row = HBoxContainer.new()
	_collection_row.add_theme_constant_override("separation", 10)
	box.add_child(_collection_row)
	_refresh_collection()


func _refresh_collection() -> void:
	if _collection_panel == null or not _collection_panel.is_inside_tree():
		return
	## Полоска исчезает, когда работа закрыта: пустые ячейки в убранной кладовой
	## читались бы как «ты что-то пропустил».
	var done_flag := String(shop.collection.get("done_flag", ""))
	_collection_panel.visible = done_flag.is_empty() \
		or not bool(Game.meta.flags.get(done_flag, false))
	if not _collection_panel.visible:
		return
	for c in _collection_row.get_children():
		_collection_row.remove_child(c)
		c.queue_free()
	for raw in shop.collection.get("items", []):
		_collection_row.add_child(_collection_cell(String(raw)))


func _collection_cell(item_id: String) -> Control:
	var have := PlayerState.amount_of(item_id) > 0
	var cell := PanelContainer.new()
	cell.custom_minimum_size = CELL
	cell.tooltip_text = ContentDB.item_name(item_id)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.10, 0.13, 0.85)
	sb.border_color = UIKit.ACCENT if have else Color(0.45, 0.43, 0.40, 0.9)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(8)
	cell.add_theme_stylebox_override("panel", sb)

	var icon := TextureRect.new()
	icon.texture = PlaceholderArt.item_icon(ContentDB.item(item_id), 84)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## Не найденный предмет показан силуэтом: форму видно, деталей нет —
	## подсказка «что искать», а не ответ «вот оно».
	icon.modulate = Color(1, 1, 1, 1) if have else Color(0, 0, 0, 0.6)
	cell.add_child(icon)
	return cell


## Лампочка появляется только там, где есть что искать. В обычной локации все
## объекты и так обведены рамкой, и подсказывать нечего.
##
## Висит у правого борта по центру высоты, а не в общей колонке: сверху
## заголовок, снизу панели задач и инвентарь — правый край единственное место,
## где кнопка не накрывает сцену поиска.
func _build_hint_button(parent: Control) -> void:
	if not _has_searchables():
		return
	_hint_button = UIKit.button("💡", 44)
	_hint_button.custom_minimum_size = Vector2(120, 120)
	_hint_button.tooltip_text = "Показать, где лежит"
	parent.add_child(_hint_button)
	_hint_button.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_hint_button.offset_left = -140
	_hint_button.offset_right = -20
	_hint_button.offset_top = -60
	_hint_button.offset_bottom = 60
	_hint_button.pressed.connect(_on_hint)



func _has_searchables() -> bool:
	for slot_id in _slot_defs:
		if (_slot_defs[slot_id] as ShopSlotDefinition).is_searchable():
			return true
	return false


## Первый ещё не убранный объект из тех, что игрок должен найти сам.
func _next_searchable() -> String:
	for slot_id in _slot_defs:
		var def: ShopSlotDefinition = _slot_defs[slot_id]
		if not def.is_searchable():
			continue
		if def.has_progress_in(Game.meta.current_slot_state(shop_id, String(slot_id)),
				Game.meta.flags):
			return String(slot_id)
	return ""


## Подсказка бесплатная и без счётчика. Локация-уборка — про внимательность, а
## не про ресурс: платная лампочка здесь была бы ловушкой, а не помощью.
func _on_hint() -> void:
	var target := _next_searchable()
	if target.is_empty():
		EventBus.toast.emit("Здесь всё убрано")
		return
	_stop_search_hint()
	(_slots[target] as StateSlot).flash_hint()


## Первый раз в сцене поиска игроку показывают жест рукой. До этого его учили
## только тащить части пазла — и без этого хода он тащит и здесь, хотя предметы
## находятся нажатием.
func _maybe_start_search_hint() -> void:
	if bool(Game.meta.flags.get(Game.SEARCH_FLAG, false)):
		return
	var target := _next_searchable()
	if target.is_empty():
		return
	_hand = TutorialHand.new()
	$Visuals.add_child(_hand)
	_hand.play_tap((_slots[target] as StateSlot).world_rect.get_center())


func _stop_search_hint() -> void:
	if _hand == null:
		return
	_hand.stop()
	_hand = null


## --- UI ---------------------------------------------------------------------

func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(root)

	_margin = MarginContainer.new()
	_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_margin)
	_apply_margins()

	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 10)
	_margin.add_child(col)

	var header := HBoxContainer.new()
	col.add_child(header)

	## Куда ведёт «назад» — из данных: кладовая лежит внутри пекарни, и с неё
	## правильный выход в пекарню, а не сразу на площадь.
	var back_shop := String(shop.back.get("shop_id", ""))
	## Слева в этом углу стоит кнопка журнала — она в оверлее и про шапку сцены
	## ничего не знает. Держим под неё место, иначе «Район» окажется под ней.
	var journal_gap := Control.new()
	journal_gap.custom_minimum_size = Vector2(TaskJournal.BUTTON_SIZE.x + TaskJournal.EDGE, 0)
	journal_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(journal_gap)

	var back := UIKit.plate_button(String(shop.back.get("label", "‹ Район")), 30)
	back.custom_minimum_size = Vector2(210, 96)
	if back_shop.is_empty():
		back.pressed.connect(func(): Game.open_map())
	else:
		back.pressed.connect(func(): Game.open_shop(back_shop))
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

	## Полоска «что собрать» стоит СРАЗУ под заголовком, а не над списком задач:
	## внизу и так две панели, и третья накрыла бы ту самую сцену, в которой
	## игрок ищет предметы.
	_build_collection(col)
	_build_hint_button(root)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(spacer)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 280)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)

	_task_list = VBoxContainer.new()
	_task_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_task_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_task_list)


## Полоса инвентаря лежит в оверлее поверх сцены, поэтому место под неё держим
## отступом. Пересчитывается на изменение инвентаря: пустая полоса не
## показывается и высоты не занимает.
##
## Вызов отложенный, и к моменту исполнения экран мог смениться: сцена уже вынута
## из дерева, но ещё не освобождена. Вьюпорта у неё в этот момент нет, а отступы
## считать не для кого.
func _apply_margins() -> void:
	if _margin != null and _margin.is_inside_tree():
		SafeArea.apply(_margin, 20, Game.bottom_reserved())


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

	## Панель показывает только то, чем можно заняться. «✓ выполнено» вечным
	## списком — не прогресс, а мусор поверх локации, и на нём теряется строка,
	## которая сейчас важна.
	for task in Game.meta.tasks_at("shop", shop_id):
		if Game.meta.task_state(task.id) == MetaService.TaskState.COMPLETED:
			continue
		_task_list.add_child(_task_row(task))

	var enter_row := _enter_row()
	if enter_row != null:
		_task_list.add_child(enter_row)

	if _focus != null and _rows.has(_focus.task_id):
		_flash(_rows[_focus.task_id])
	_rebuilding = false


## Вход внутрь магазина. Условие открытия — флаг из данных, поэтому сцена не
## знает ни про дверь, ни про ключ.
func _enter_row() -> Control:
	if shop.enter.is_empty():
		return null
	var flag := String(shop.enter.get("requires_flag", ""))
	var unlocked := flag.is_empty() or bool(Game.meta.flags.get(flag, false))

	## Вход — такая же строка, как задача: он и есть задача, просто описанная в
	## магазине, а не в tasks.json. Значит и плашка под ним та же.
	var panel := UIKit.plate(UIKit.PLATE)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)

	var label := String(shop.enter.get("label", "Войти"))
	## По центру, в отличие от списка задач: здесь один пункт, а не колонка, и
	## выравнивать его по левому краю не с чем.
	if not unlocked:
		col.add_child(_plate_line(label, 32, UIKit.PLATE_HINT))
		col.add_child(_plate_line(String(shop.enter.get("locked_text", "")), 24, UIKit.PLATE_HINT))
		for line in col.get_children():
			(line as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		return panel

	var title := _plate_line(label, 32, UIKit.PLATE_TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	var button := UIKit.plate_button("Войти", 32)
	## Рамка обводит надпись, а не всю ширину панели: растянутая кнопка читается
	## как полоса, и непонятно, что нажимать — её или строку над ней.
	var center := CenterContainer.new()
	center.add_child(button)
	col.add_child(center)
	## Куда именно ведёт вход, решает контент: есть open_shop — переходим в ту
	## локацию, нет — показываем текст-заглушку. Сцена по-прежнему не знает,
	## что за дверью.
	var target_shop := String(shop.enter.get("open_shop", ""))
	var enter_text := String(shop.enter.get("text", ""))
	if target_shop.is_empty():
		button.pressed.connect(func(): EventBus.toast.emit(enter_text))
	else:
		button.pressed.connect(func(): Game.open_shop(target_shop))
	return panel


func _task_row(task: MetaTaskDefinition) -> Control:
	## Та же нарисованная плашка, что у задачи на карте и у попапа «задание
	## выполнено»: одна строка задачи не должна выглядеть по-разному в зависимости
	## от того, из какого экрана на неё смотрят.
	var panel := UIKit.plate(UIKit.PLATE)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)
	_rows[task.id] = panel

	var state: int = Game.meta.task_state(task.id)
	var title := UIKit.plate_label(32, false)
	title.text = task.title
	col.add_child(title)

	var action: MetaActionDefinition = Game.meta.action_for_task(task.id)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	## Кнопки стоят по центру строки и по размеру своей надписи: рамка обводит
	## слова, а растянутая во всю панель кнопка читается как полоса, и непонятно,
	## что в ней нажимать.
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER

	match state:
		MetaService.TaskState.AVAILABLE, MetaService.TaskState.IN_PROGRESS:
			if not task.hint.is_empty():
				col.add_child(_plate_line(task.hint, 24, UIKit.PLATE_HINT))
			col.add_child(_missing_label(action))
			if not task.level_ids.is_empty():
				var play := UIKit.plate_button(_play_label(task), 32)
				play.pressed.connect(func(): Game.play_task(task.id))
				buttons.add_child(play)

		MetaService.TaskState.READY_TO_APPLY:
			col.add_child(_plate_line(action.description if action != null else "", 24, UIKit.PLATE_HINT))
			var apply := UIKit.plate_button(_apply_label(action), 32)
			apply.disabled = not Game.meta.can_start_action(task.id)
			apply.pressed.connect(func(): _on_apply(task.id))
			buttons.add_child(apply)
			var again := UIKit.plate_button("Повтор уровня", 26)
			again.pressed.connect(func(): Game.play_task(task.id))
			buttons.add_child(again)

		MetaService.TaskState.APPLYING:
			var timer := _plate_line("", 28, UIKit.PLATE_TEXT)
			col.add_child(timer)
			_timers[task.id] = timer
			_update_timer(task.id)
			if Game.meta.can_claim(task.id):
				var claim := UIKit.plate_button("Забрать", 32)
				claim.pressed.connect(func(): _on_claim(task.id))
				buttons.add_child(claim)
			else:
				if action != null and action.speedup_hard_cost > 0:
					var fast := UIKit.plate_button("Ускорить · %d ◆" % action.speedup_hard_cost, 28)
					fast.pressed.connect(func(): _on_speedup(task.id))
					buttons.add_child(fast)
				if action != null and action.ad_reduce_sec > 0:
					var ad := UIKit.plate_button("Реклама −%d мин" % int(action.ad_reduce_sec / 60), 28)
					ad.pressed.connect(func(): _on_ad(task.id))
					buttons.add_child(ad)

		MetaService.TaskState.COMPLETED:
			col.add_child(_plate_line("✓ выполнено", 26, DONE_GREEN))

	if buttons.get_child_count() > 0:
		col.add_child(buttons)
	else:
		# У выполненной задачи кнопок нет, и контейнер в дерево не попадает —
		# без явного free он остаётся сиротой на каждой пересборке списка.
		buttons.free()
	return panel


## Что написано на кнопке запуска. Подпись берётся у задачи: «Разобрать» на
## кладовой говорит игроку, что он собирается сделать, а «Играть» — только то,
## что сейчас будет геймплей, о чём он и так догадался, нажимая кнопку.
##
## Счётчик уровней с кнопки убран: «1/2» — это отчёт о работе, а не обещание.
func _play_label(task: MetaTaskDefinition) -> String:
	var info := Game.meta.resolve_level_for_task(task.id)
	if not info.is_empty() and bool(info.get("replay", false)):
		return "Повтор (награда ниже)"
	return task.play_label if not task.play_label.is_empty() else "Играть"


func _apply_label(action: MetaActionDefinition) -> String:
	if action == null:
		return "Применить"
	if action.is_instant():
		return action.button_label
	return "%s · %s" % [action.button_label, TimeService.format_duration(action.duration_sec)]


## Строка на нарисованной плашке. Своя, а не UIKit.label: там светлая буква с
## чёрной обводкой под арт, а здесь тёмная по кремовой бумаге.
func _plate_line(text: String, size: int, color: Color) -> Label:
	var l := UIKit.plate_label(size, false)
	l.text = text
	l.add_theme_color_override("font_color", color)
	return l


func _missing_label(action: MetaActionDefinition) -> Control:
	if action == null:
		return Control.new()
	var missing := TaskResolver.missing(action.requirements, Game.meta)
	if missing.is_empty():
		return Control.new()
	var parts := PackedStringArray()
	for r in missing:
		## Требование «пройти уровень» игроку не показываем: кнопка запуска стоит
		## тут же, и строка «нужно: уровень storeroom_02» рассказывает про
		## внутреннее имя файла, а не про то, что делать.
		if r.kind == Requirement.Kind.LEVEL:
			continue
		if r.kind == Requirement.Kind.ITEM:
			parts.append("%s %d/%d" % [
				ContentDB.item_name(r.id), PlayerState.amount_of(r.id), r.amount])
		else:
			parts.append(r.describe())
	if parts.is_empty():
		return Control.new()
	return _plate_line("Нужно: " + ", ".join(parts), 24, MISSING)


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
