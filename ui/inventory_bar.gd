class_name InventoryBar
extends Control
## Инвентарь игрока — одна полоска по низу экрана, общая для карты и локаций.
##
## Живёт в оверлее Boot, а не внутри сцены магазина: предметы переезжают между
## экранами вместе с игроком, и пересобирать их на каждом экране заново значит
## каждый раз чинить это в двух местах. Выбранный предмет тоже один на всё
## приложение и лежит в Game — сцене остаётся только спросить, что в руке.
##
## Пустой инвентарь полосу не показывает: на старте игры отдавать ей 200 px
## высоты не за что. Экраны спрашивают reserved_height() и сами держат отступ.

const HEIGHT := 196
const SLOT := Vector2(150, 130)
const ICON := 72
const FALL_FROM := 520.0     ## с какой высоты предмет падает в полосу

var _panel: PanelContainer
var _row: HBoxContainer
var _chips: Dictionary = {}      ## item_id -> Control
var _known: Dictionary = {}      ## item_id -> сколько было в прошлый раз
var _pending: PackedStringArray = PackedStringArray()   ## что ещё не «упало»
var _falling: Array[Dictionary] = []                    ## [{icon, tween}] в полёте
var _dirty: bool = false


func _ready() -> void:
	## Якоря и offsets задаются вручную, без set_anchors_preset: пресет
	## пересчитывает offsets от ТЕКУЩЕГО прямоугольника, а в _ready он ещё
	## нулевой — полоса получала нулевую ширину и схлопывалась в угол экрана.
	anchor_left = 0.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = 0
	offset_right = 0
	offset_top = -HEIGHT
	offset_bottom = 0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	_snapshot()
	EventBus.inventory_changed.connect(_on_inventory_changed)
	EventBus.inventory_selection_changed.connect(func(_id): _queue_rebuild())
	_queue_rebuild()


func _build() -> void:
	_panel = UIKit.panel(Color(0.08, 0.08, 0.11, 0.92))
	## Пресет — до add_child: вне дерева он раскладывается от нулевого родителя
	## и даёт честный full rect, а внутри пересчитал бы offsets от текущего
	## (нулевого) размера панели и оставил бы её шириной по содержимому.
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	_panel.add_child(col)

	col.add_child(UIKit.label("Инвентарь", 22, Color(0.78, 0.76, 0.72)))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)

	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 12)
	scroll.add_child(_row)


## Высота, которую полоса реально занимает. Экраны держат на неё нижний отступ.
func reserved_height() -> int:
	return HEIGHT if not _item_ids().is_empty() else 0


## Лежит ли предмет в полосе прямо сейчас. Нужно headless-прогону: «предмет
## начислен» и «игрок его видит» — разные утверждения, и ломается обычно второе.
func shows(item_id: String) -> bool:
	return _chips.has(item_id)


## --- содержимое -------------------------------------------------------------

## Бустеры живут в HUD уровня — в инвентаре им делать нечего.
func _item_ids() -> Array:
	var ids := []
	for id in PlayerState.items:
		if String(id) == Game.BOOSTER_ID:
			continue
		ids.append(String(id))
	ids.sort()
	return ids


func _snapshot() -> void:
	_known.clear()
	for id in _item_ids():
		_known[id] = PlayerState.amount_of(String(id))


## Прибавка в инвентаре = предмет должен «упасть» в полосу. Убавка и появление
## во время уровня просто копятся: анимировать полосу, которой не видно, незачем.
func _on_inventory_changed(id: String, value: int) -> void:
	if id == Game.BOOSTER_ID:
		return
	if value > int(_known.get(id, 0)) and not _pending.has(id):
		_pending.append(id)
	_known[id] = value
	_queue_rebuild()


func _queue_rebuild() -> void:
	if _dirty:
		return
	_dirty = true
	call_deferred("_rebuild")


func _rebuild() -> void:
	_dirty = false
	if _row == null:
		return
	_cancel_falling()
	for c in _row.get_children():
		c.queue_free()
	_chips.clear()

	var ids := _item_ids()
	_panel.visible = not ids.is_empty()
	if not Game.selected_item.is_empty() and not ids.has(Game.selected_item):
		Game.clear_selection()

	for id in ids:
		var chip := _chip(String(id))
		_row.add_child(chip)
		_chips[String(id)] = chip
		if _pending.has(String(id)):
			chip.modulate.a = 0.0

	# Сейв загружается без событий инвентаря, поэтому _known после старта пуст.
	# Синхронизируем здесь, иначе первая же трата уже лежащего предмета
	# посчитается прибавкой.
	_snapshot()

	if not _pending.is_empty():
		call_deferred("_play_drops")


func _chip(item_id: String) -> Control:
	var selected := item_id == Game.selected_item
	var button := Button.new()
	button.custom_minimum_size = SLOT
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = ContentDB.item_name(item_id)
	button.pivot_offset = SLOT * 0.5
	if selected:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.30, 0.24, 0.10, 0.95)
		sb.border_color = UIKit.ACCENT
		sb.set_border_width_all(4)
		sb.set_corner_radius_all(14)
		button.add_theme_stylebox_override("normal", sb)
	button.pressed.connect(func(): Game.select_item(item_id))

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	button.add_child(box)

	var icon := TextureRect.new()
	icon.texture = PlaceholderArt.item_icon(ContentDB.item(item_id), ICON)
	icon.custom_minimum_size = Vector2(ICON, ICON)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(icon)

	var name_label := UIKit.label(ContentDB.item_name(item_id), 19)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size = Vector2(SLOT.x - 10, 0)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name_label)

	var count := PlayerState.amount_of(item_id)
	if count > 1:
		var badge := UIKit.label("×%d" % count, 19, UIKit.ACCENT)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(badge)

	return button


## --- «упало в инвентарь» ----------------------------------------------------

## Награду за уровень выдают, пока на экране ещё уровень. Ждём, когда полоса
## окажется на виду, иначе предмет падает в невидимую панель и игрок пропускает
## единственный кадр, где ему показывают, что он вообще что-то получил.
## Предмет остаётся в _pending, пока его иконка не долетит. Любая пересборка
## полосы освобождает чипы, в которые метились летящие иконки, — поэтому полёт
## отменяется и начинается заново по новым чипам, а не падает в освобождённый
## объект.
func _play_drops() -> void:
	if not is_visible_in_tree() or _pending.is_empty():
		return
	await get_tree().process_frame          # дождаться раскладки контейнера
	if not is_visible_in_tree():
		return

	var delay := 0.0
	for id in _pending.duplicate():
		var chip: Control = _chips.get(String(id))
		if chip == null:
			continue
		_drop(String(id), chip, delay)
		delay += 0.14


func _drop(item_id: String, chip: Control, delay: float) -> void:
	var icon := TextureRect.new()
	icon.texture = PlaceholderArt.item_icon(ContentDB.item(item_id), 112)
	icon.size = Vector2(112, 112)
	icon.pivot_offset = Vector2(56, 56)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(icon)

	var landing := chip.get_global_rect().get_center() - global_position - Vector2(56, 56)
	icon.position = Vector2(landing.x, landing.y - FALL_FROM)
	icon.modulate.a = 0.0

	## Твин заводим от самой иконки, а не от полосы: так он умирает вместе с ней
	## и не пытается доиграть колбэк по освобождённым нодам.
	var tw := icon.create_tween()
	_falling.append({"icon": icon, "tween": tw})
	tw.tween_interval(delay)
	tw.tween_property(icon, "modulate:a", 1.0, 0.10)
	tw.parallel().tween_property(icon, "position", landing, 0.42) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(icon, "rotation", randf_range(-0.5, 0.5), 0.42)
	tw.tween_callback(func(): _land(item_id, icon, chip))


func _land(item_id: String, icon: Control, chip: Control) -> void:
	_forget_falling(icon)
	if is_instance_valid(icon):
		icon.queue_free()
	var i := _pending.find(item_id)
	if i >= 0:
		_pending.remove_at(i)
	# Чип мог быть пересобран, пока иконка летела: она долетает «в никуда»,
	# а показать предмет обязана следующая пересборка.
	if is_instance_valid(chip):
		chip.modulate.a = 1.0
		_bounce(chip)


## Отменить полёт: чипы, в которые метились иконки, сейчас будут освобождены.
## Твин гасим до освобождения иконки, иначе он успевает дёрнуть колбэк.
func _cancel_falling() -> void:
	for entry in _falling:
		var tween: Tween = entry.get("tween")
		if tween != null and tween.is_valid():
			tween.kill()
		var icon: Control = entry.get("icon")
		if is_instance_valid(icon):
			icon.queue_free()
	_falling.clear()


func _forget_falling(icon: Control) -> void:
	for i in range(_falling.size() - 1, -1, -1):
		if _falling[i].get("icon") == icon:
			_falling.remove_at(i)


func _bounce(chip: Control) -> void:
	chip.scale = Vector2(1.35, 0.7)
	chip.create_tween().tween_property(chip, "scale", Vector2.ONE, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## --- видимость по экрану ----------------------------------------------------

func set_active(on: bool) -> void:
	visible = on
	if on:
		_queue_rebuild()
	else:
		_land_now()


## Уход с экрана посреди падения. Досматривать анимацию некому, но предмет в
## полосе обязан остаться видимым — иначе он «упал» в никуда.
func _land_now() -> void:
	_cancel_falling()
	_pending = PackedStringArray()
	for id in _chips:
		var chip: Control = _chips[id]
		if is_instance_valid(chip):
			chip.modulate.a = 1.0
