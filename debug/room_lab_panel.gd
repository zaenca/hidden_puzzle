class_name RoomLabPanel
extends PanelContainer
## Лаборатория комнат: собрать интерьер руками и оставить его в контенте.
##
## Стенд, который показывает красивую комнату и ничего после себя не оставляет,
## — не инструмент. Поэтому здесь не только переключатели: подобранное
## сохраняется в тот же JSON, который читает игра, и цепляется к настоящей
## локации. Иначе всё найденное пришлось бы переписывать руками, а руками
## переносят неточно и не всё.
##
## Материалы выбираются списками, а предметы — перетаскиванием: окно на стене
## стоит не «в 0.33 от края», а там, где ему место, и подбирать эту цифру
## вслепую дороже, чем один раз перетащить.
##
## Только debug-сборка. В собранной игре res:// лежит внутри PCK и записи не
## принимает — это инструмент разработки, а не функция игры.

const SURFACE_TITLES := {
	"left_wall": "Левая стена",
	"right_wall": "Правая стена",
	"floor": "Пол",
	"ceiling": "Потолок",
}
## Материалы поверхностей: любой на любую. Пол на настенном кирпиче смотрится
## нормально, а вот окно, натянутое на всю стену, ничего не проверяет —
## отсеиваются только элементы, мебель и наклейки.
const SURFACE_CATEGORIES := ["wall", "floor", "ceiling"]
## Что можно перетащить в комнату. Порядок задаёт порядок в палитре.
const PALETTE_CATEGORIES := ["window", "door", "furniture"]
const CATEGORY_TITLES := {
	"window": "Окна", "door": "Двери", "furniture": "Мебель",
}

const TEMPLATE_ROW := "__template"
const PRESET_ROW := "__preset"
const SHOP_ROW := "__shop"
const NO_SHOP := "— не цеплять —"

## Комната, в которую пишет «Сохранить». Отдельная от пресетов: сохраняя, стенд
## не должен затирать заготовку, из которой его открыли.
const LAB_ROOM_ID := "room_lab"

var _room: RoomAssembler = null
var _materials: Dictionary = {}
var _templates: Dictionary = {}
var _to_world: Callable = Callable()
var _reload: Callable = Callable()

var _choices: Dictionary = {}
var _index: Dictionary = {}
var _labels: Dictionary = {}

var _body: VBoxContainer = null
var _collapse: Button = null
var _status: Label = null

## Перетаскивание. drag_material — тащим новый предмет из палитры,
## drag_existing — двигаем уже поставленный.
var _drag_material: String = ""
var _drag_existing: String = ""
var _ghost: TextureRect = null


static func create(room: RoomAssembler, materials: Dictionary, templates: Dictionary,
		current: Dictionary, current_template: String, current_room: String,
		to_world: Callable, reload: Callable) -> RoomLabPanel:
	var panel := RoomLabPanel.new()
	panel.name = "RoomLabPanel"
	panel._room = room
	panel._materials = materials
	panel._templates = templates
	panel._to_world = to_world
	panel._reload = reload
	panel._build(current, current_template, current_room)
	return panel


func _build(current: Dictionary, current_template: String, current_room: String) -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.10, 0.14, 0.94)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(12)
	add_theme_stylebox_override("panel", sb)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	add_child(outer)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	outer.add_child(head)
	var title := UIKit.label("ЛАБОРАТОРИЯ КОМНАТ", 20, UIKit.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_collapse = UIKit.button("▼", 20)
	_collapse.custom_minimum_size = Vector2(52, 36)
	_collapse.pressed.connect(func(): set_body_visible(not _body.visible))
	head.add_child(_collapse)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 5)
	outer.add_child(_body)

	_add_row(PRESET_ROW, "Заготовка", _room_ids(), current_room)
	_add_row(TEMPLATE_ROW, "Геометрия", _dict_ids(_templates), current_template)

	var surface_ids := _materials_of(SURFACE_CATEGORIES)
	for surface_id in SURFACE_TITLES:
		## Строка только для тех поверхностей, что у комнаты есть. Потолок
		## необязателен, и строка, которая ничего не переключает, врала бы про
		## то, из чего комната собрана.
		if not current.has(surface_id):
			continue
		_add_row(String(surface_id), String(SURFACE_TITLES[surface_id]),
			surface_ids, String(current.get(surface_id, "")))

	_build_palette()

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	_body.add_child(buttons)
	buttons.add_child(_action("Убрать последнее", _undo_last))
	buttons.add_child(_action("Сохранить", _save_room))

	_add_row(SHOP_ROW, "Прицепить к", _shop_ids(), NO_SHOP)
	_body.add_child(_action("Прицепить к локации", _attach_to_shop))

	_status = UIKit.label("Предметы перетаскиваются из палитры в комнату.", 16,
		Color(0.68, 0.66, 0.62))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(_status)


func set_body_visible(on: bool) -> void:
	_body.visible = on
	_collapse.text = "▼" if on else "▲"


## --- строки выбора ----------------------------------------------------------

func _add_row(key: String, title_text: String, ids: PackedStringArray,
		current_id: String) -> void:
	_choices[key] = ids
	_index[key] = maxi(0, ids.find(current_id))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var title := UIKit.label(title_text, 18)
	title.custom_minimum_size = Vector2(140, 0)
	row.add_child(title)
	row.add_child(_step_button(key, -1, "<"))

	var value := UIKit.label(_current_id(key), 18, UIKit.ACCENT)
	value.custom_minimum_size = Vector2(250, 40)
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value.clip_text = true
	row.add_child(value)
	_labels[key] = value

	row.add_child(_step_button(key, 1, ">"))
	_body.add_child(row)


func _step_button(key: String, delta: int, text: String) -> Button:
	var b := UIKit.button(text, 22)
	b.custom_minimum_size = Vector2(52, 40)
	b.pressed.connect(func(): _step(key, delta))
	return b


## Шаг по списку. Материал меняется на месте, геометрия — пересборкой комнаты
## (поверхности встают в других местах), заготовка — полной перезагрузкой.
func _step(key: String, delta: int) -> void:
	var list: PackedStringArray = _choices[key]
	if list.is_empty():
		return
	_index[key] = posmod(int(_index[key]) + delta, list.size())
	(_labels[key] as Label).text = _current_id(key)
	match key:
		PRESET_ROW:
			_reload.call(_current_id(key))
		TEMPLATE_ROW:
			_room.rebuild_with_template(_templates.get(_current_id(key)))
		SHOP_ROW:
			pass
		_:
			_room.set_surface_material(key, _current_id(key))


func _current_id(key: String) -> String:
	var list: PackedStringArray = _choices.get(key, PackedStringArray())
	if list.is_empty():
		return ""
	return list[int(_index.get(key, 0)) % list.size()]


## --- палитра ----------------------------------------------------------------

func _build_palette() -> void:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 132)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(scroll)

	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 8)
	scroll.add_child(strip)

	for category in PALETTE_CATEGORIES:
		var group := VBoxContainer.new()
		group.add_theme_constant_override("separation", 2)
		strip.add_child(group)
		group.add_child(UIKit.label(String(CATEGORY_TITLES[category]), 15,
			Color(0.62, 0.60, 0.56)))
		var items := HBoxContainer.new()
		items.add_theme_constant_override("separation", 6)
		group.add_child(items)
		for id in _materials:
			var mat: RoomMaterial = _materials[id]
			if mat.category == category:
				items.add_child(_palette_item(String(id), mat))


## Плитка палитры: картинка предмета и его id. Перетаскивание начинается здесь,
## а заканчивается в комнате — поэтому дальше событиями занимается сама панель,
## а не эта кнопка.
func _palette_item(id: String, mat: RoomMaterial) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.custom_minimum_size = Vector2(96, 0)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.tooltip_text = id

	var frame := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.18, 0.18, 0.22, 1.0)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(4)
	frame.add_theme_stylebox_override("panel", sb)
	box.add_child(frame)

	var icon := TextureRect.new()
	icon.texture = RoomTextures.resolve(mat.texture_path, mat.generator, mat.seed)
	icon.custom_minimum_size = Vector2(88, 72)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(icon)

	var caption := UIKit.label(id.substr(0, 12), 13, Color(0.72, 0.70, 0.66))
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(caption)

	box.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			_begin_drag(id, icon.texture))
	return box


## --- перетаскивание ---------------------------------------------------------

## Пока предмет тащат, панель уезжает: она занимает низ экрана, а это ровно тот
## пол, на который чаще всего и ставят. Иначе половина комнаты недосягаема.
func _begin_drag(material_id: String, tex: Texture2D) -> void:
	_drag_material = material_id
	_drag_existing = ""
	_show_ghost(tex)
	set_body_visible(false)


func _show_ghost(tex: Texture2D) -> void:
	_clear_ghost()
	_ghost = TextureRect.new()
	_ghost.texture = tex
	_ghost.size = Vector2(140, 140)
	_ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_ghost.modulate = Color(1, 1, 1, 0.65)
	_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ghost.z_index = 200
	get_parent().add_child(_ghost)


func _clear_ghost() -> void:
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if _ghost != null:
			_ghost.global_position = event.position - _ghost.size * 0.5
		if not _drag_existing.is_empty():
			_move_existing(event.position)
		return

	if not (event is InputEventMouseButton) or event.button_index != MOUSE_BUTTON_LEFT:
		return

	if event.pressed:
		## Нажатие мимо панели — возможно, взяли уже поставленный предмет.
		if _drag_material.is_empty() and not _hits_panel(event.position):
			var id := _room.element_at(_room_point(event.position))
			if not id.is_empty():
				_drag_existing = id
				_say("Двигаем «%s»." % id)
		return

	if not _drag_material.is_empty():
		_drop_new(event.position)
	elif not _drag_existing.is_empty():
		_drag_existing = ""
		_say("Готово.")


func _drop_new(screen_pos: Vector2) -> void:
	var material_id := _drag_material
	_drag_material = ""
	_clear_ghost()
	set_body_visible(true)
	## Отпустили над панелью — это отмена, а не постановка предмета под неё.
	if _hits_panel(screen_pos):
		_say("Отменено.")
		return
	var id := _room.place_material(material_id, _room_point(screen_pos))
	if id.is_empty():
		_say("Мимо комнаты: предмет ставится на стену или на пол.")
	else:
		_say("Поставлено: «%s»." % id)


func _move_existing(screen_pos: Vector2) -> void:
	if _hits_panel(screen_pos):
		return
	var el := _room.element(_drag_existing)
	if el == null:
		return
	_room.place_material(el.material_id, _room_point(screen_pos), _drag_existing)


func _room_point(screen_pos: Vector2) -> Vector2:
	var world: Vector2 = _to_world.call(screen_pos) if _to_world.is_valid() else screen_pos
	return _room.to_local(world)


func _hits_panel(screen_pos: Vector2) -> bool:
	return get_global_rect().has_point(screen_pos)


## --- действия ---------------------------------------------------------------

func _undo_last() -> void:
	var id := _room.last_placed_id()
	if id.is_empty():
		_say("Убирать нечего: руками поставленного нет.")
		return
	_room.remove_element(id)
	_say("Убрано: «%s»." % id)


func _save_room() -> void:
	var path := RoomSerializer.save_room(_room.definition(), LAB_ROOM_ID)
	if path.is_empty():
		_say("Не удалось записать файл — запись в res:// есть только в запуске из исходников.")
	else:
		_say("Сохранено: %s" % path)


func _attach_to_shop() -> void:
	var shop_id := _current_id(SHOP_ROW)
	if shop_id == NO_SHOP or shop_id.is_empty():
		_say("Сперва выберите локацию в строке «Прицепить к».")
		return
	## У локации своя копия комнаты, а не ссылка на лабораторную: следующая
	## правка на стенде не должна менять то, что уже стоит в игре.
	var room_id := "%s_room" % shop_id
	var path := RoomSerializer.save_room(_room.definition(), room_id)
	if path.is_empty():
		_say("Не удалось записать комнату.")
		return
	if RoomSerializer.attach_to_shop(shop_id, room_id):
		_say("Комната «%s» прицеплена к локации «%s». Перезапустите игру." % [room_id, shop_id])
	else:
		_say("Комната сохранена, но локацию поправить не вышло — см. консоль.")


func _action(text: String, action: Callable) -> Button:
	var b := UIKit.button(text, 18)
	b.custom_minimum_size = Vector2(0, 44)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(action)
	return b


func _say(text: String) -> void:
	if _status != null:
		_status.text = text


## --- списки -----------------------------------------------------------------

## Заготовки — это файлы в content/rooms. Каталог, а не индекс: список нужен
## только стенду, и отдельный индекс пришлось бы вести руками.
func _room_ids() -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open("res://content/rooms")
	if dir == null:
		return out
	for file in dir.get_files():
		if file.ends_with(".json"):
			out.append(file.trim_suffix(".json"))
	out.sort()
	return out


## Локации, к которым есть смысл цеплять комнату: все, кроме самой лаборатории.
func _shop_ids() -> PackedStringArray:
	var out := PackedStringArray([NO_SHOP])
	for id in ContentDB.shops:
		if not String(id).begins_with("room_lab"):
			out.append(String(id))
	return out


func _materials_of(categories: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for id in _materials:
		if categories.has((_materials[id] as RoomMaterial).category):
			out.append(String(id))
	return out


func _dict_ids(d: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for id in d:
		out.append(String(id))
	return out
