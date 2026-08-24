extends Node2D
## Карта района. Здания — data-driven, состояние берётся из меты.

const MAP_RECT := Rect2(30, 210, 1020, 900)
const SCREEN := Vector2(1080, 1920)

@onready var _bg: Sprite2D = $Visuals/Background
@onready var _buildings: Node2D = $Visuals/Buildings
@onready var _ui: CanvasLayer = $UI

var _focus: MetaFocus = null
var _hit_areas: Array = []      ## [{rect: Rect2, shop_id: String}]
var _task_list: VBoxContainer

## Прямоугольник, к которому нормализованы координаты зданий. С реальным артом
## это область самой картинки, без него — условная MAP_RECT.
var _map_rect: Rect2 = MAP_RECT
var _has_art: bool = false


func setup(payload: Dictionary) -> void:
	_focus = payload.get("focus")
	if not is_node_ready():
		await ready
	_build()


func _build() -> void:
	_setup_background()

	for entry in ContentDB.map_data.get("buildings", []):
		_add_building(entry)

	_build_ui()
	_rebuild_tasks()

	EventBus.task_state_changed.connect(func(_t, _s): call_deferred("_rebuild_tasks"))
	_show_pending_narrative()


## Реальный арт кладётся «по обрезке»: картинка накрывает экран целиком, лишнее
## уходит за край. Если файла нет — прежний процедурный градиент, чтобы проект
## оставался запускаемым без ассетов.
func _setup_background() -> void:
	var path := String(ContentDB.map_data.get("background", ""))
	var tex: Texture2D = null
	if not path.is_empty() and ResourceLoader.exists(path):
		tex = load(path) as Texture2D

	_bg.centered = false
	if tex != null:
		_has_art = true
		_bg.texture = tex
		var tex_size := Vector2(tex.get_size())
		var s: float = maxf(SCREEN.x / tex_size.x, SCREEN.y / tex_size.y)
		_bg.scale = Vector2(s, s)
		_bg.position = (SCREEN - tex_size * s) * 0.5
		_map_rect = Rect2(_bg.position, tex_size * s)
	else:
		_has_art = false
		var palette := String(ContentDB.map_data.get("palette", "street"))
		_bg.texture = PlaceholderArt.flat_texture(
			Vector2i(int(SCREEN.x), int(SCREEN.y)), Palette.top(palette), Palette.bottom(palette))
		_bg.scale = Vector2.ONE
		_bg.position = Vector2.ZERO
		_map_rect = MAP_RECT


func _add_building(entry: Dictionary) -> void:
	var shop_id := String(entry.get("shop_id", ""))
	## Здание без shop_id тоже кликабельно: за ним пока нет сцены, и тап честно
	## отвечает «объект пока закрыт». Убрать здание из хит-теста можно только
	## явным "clickable": false в map.json.
	var clickable := bool(entry.get("clickable", true))
	var norm := ContentParser.to_rect(entry.get("rect", [0, 0, 0.2, 0.2]))
	var rect := Rect2(
		_map_rect.position + Vector2(norm.position.x * _map_rect.size.x, norm.position.y * _map_rect.size.y),
		Vector2(norm.size.x * _map_rect.size.x, norm.size.y * _map_rect.size.y))

	var open := not shop_id.is_empty() and Game.meta.is_shop_open(shop_id)
	var corners := PackedVector2Array([
		rect.position,
		rect.position + Vector2(rect.size.x, 0),
		rect.position + rect.size,
		rect.position + Vector2(0, rect.size.y),
	])

	if _has_art:
		_draw_over_art(rect, corners, clickable, open)
	else:
		var color := ContentParser.to_color(entry.get("color", "#8a7f6d"))
		if not open:
			color = color.darkened(0.45)
		var poly := Polygon2D.new()
		poly.polygon = corners
		poly.color = color
		_buildings.add_child(poly)

		var label := UIKit.label(String(entry.get("label", shop_id)), 30)
		label.position = rect.position + Vector2(10, 12)
		label.size = Vector2(rect.size.x - 20, 40)
		_buildings.add_child(label)

		var status := "открыт" if open else ("заброшен" if not clickable else "закрыт")
		var status_label := UIKit.label(status, 22, Color(0.9, 0.88, 0.84))
		status_label.position = rect.position + Vector2(10, rect.size.y - 40)
		status_label.size = Vector2(rect.size.x - 20, 32)
		_buildings.add_child(status_label)

	if clickable:
		_hit_areas.append({"rect": rect, "shop_id": shop_id})


## Названия зданий уже нарисованы на арте, поэтому свои подписи не дублируются.
## Игроку нужно показать только одно: куда можно нажать и что уже доступно.
func _draw_over_art(rect: Rect2, corners: PackedVector2Array, clickable: bool, open: bool) -> void:
	if not clickable:
		return

	if not open:
		var shade := Polygon2D.new()
		shade.polygon = corners
		shade.color = Color(0.04, 0.05, 0.10, 0.42)
		_buildings.add_child(shade)

	## Рамка вдавлена внутрь: крайние здания стоят вплотную к границе экрана,
	## и линия по самому контуру обрезалась бы наполовину.
	var inset := rect.grow(-4.0)
	var outline := Line2D.new()
	outline.points = PackedVector2Array([
		inset.position,
		inset.position + Vector2(inset.size.x, 0),
		inset.position + inset.size,
		inset.position + Vector2(0, inset.size.y),
		inset.position,
	])
	outline.width = 5.0
	outline.default_color = UIKit.ACCENT if open else Color(0.88, 0.88, 0.92, 0.55)
	outline.joint_mode = Line2D.LINE_JOINT_ROUND
	_buildings.add_child(outline)

	var chip := UIKit.label("Открыт" if open else "Закрыт", 24,
		UIKit.ACCENT if open else Color(0.88, 0.88, 0.92))
	chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip.position = rect.position + Vector2(0, rect.size.y - 38)
	chip.size = Vector2(rect.size.x, 32)
	_buildings.add_child(chip)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventScreenTouch and event.pressed):
		return
	var world: Vector2 = get_canvas_transform().affine_inverse() * event.position
	for area in _hit_areas:
		if (area["rect"] as Rect2).has_point(world):
			var shop_id := String(area["shop_id"])
			if Game.meta.is_shop_open(shop_id):
				Game.open_shop(shop_id)
			else:
				EventBus.toast.emit("Объект пока закрыт")
			return


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

	var title := UIKit.label(String(ContentDB.map_data.get("title", "Район")), 38)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(spacer)

	var scroll := ScrollContainer.new()
	## Нижние здания арта заканчиваются на y=1642 из 1920 — панель задач обязана
	## начинаться ниже, иначе она срезает метки статуса у кафе и цветочного.
	scroll.custom_minimum_size = Vector2(0, 240)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)

	_task_list = VBoxContainer.new()
	_task_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_task_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_task_list)


func _rebuild_tasks() -> void:
	if _task_list == null:
		return
	for c in _task_list.get_children():
		c.queue_free()

	for task in Game.meta.tasks_at("map"):
		var panel := UIKit.panel()
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 8)
		panel.add_child(box)
		box.add_child(UIKit.label(task.title, 30, UIKit.ACCENT))
		var state: int = Game.meta.task_state(task.id)
		match state:
			MetaService.TaskState.AVAILABLE, MetaService.TaskState.IN_PROGRESS:
				if not task.hint.is_empty():
					box.add_child(UIKit.label(task.hint, 24))
				var play := UIKit.button("Играть", 32)
				play.pressed.connect(func(): Game.play_task(task.id))
				box.add_child(play)
			MetaService.TaskState.READY_TO_APPLY:
				var action: MetaActionDefinition = Game.meta.action_for_task(task.id)
				var apply := UIKit.button(action.button_label if action != null else "Применить", 32)
				apply.pressed.connect(func():
					if Game.meta.start_action(task.id):
						SaveService.save_game()
						_refresh_all())
				box.add_child(apply)
			MetaService.TaskState.COMPLETED:
				box.add_child(UIKit.label("✓ выполнено", 26, Color(0.55, 0.9, 0.6)))
		_task_list.add_child(panel)

	# Быстрый вход в открытые магазины — тап по зданию тоже работает.
	for shop in ContentDB.shops.values():
		if Game.meta.is_shop_open(shop.id):
			var enter := UIKit.button("Войти: " + shop.display_name, 30)
			enter.pressed.connect(func(): Game.open_shop(shop.id))
			_task_list.add_child(enter)


func _refresh_all() -> void:
	for c in _buildings.get_children():
		c.queue_free()
	_hit_areas.clear()
	for entry in ContentDB.map_data.get("buildings", []):
		_add_building(entry)
	_rebuild_tasks()
	_show_pending_narrative()


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
