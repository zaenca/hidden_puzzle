class_name RoomDebugPanel
extends PanelContainer
## Переключатель материалов процедурной комнаты. Только для debug-сборки.
##
## Нужен не «чтобы поиграться»: систему процедурных комнат нельзя принять на
## одном скриншоте. Штукатурка скрывает перспективу, кирпич её выдаёт, а
## шахматка показывает раскладку с точностью до плитки. Проверять это,
## переписывая JSON и перезапуская игру, — значит не проверять вовсе.

const SURFACE_TITLES := {
	"left_wall": "Левая стена",
	"right_wall": "Правая стена",
	"floor": "Пол",
	"ceiling": "Потолок",
}
## Какие материалы предлагать каждой поверхности. Пол на настенном кирпиче
## смотрится нормально, поэтому фильтр мягкий: любой материал поверхности любой
## поверхности. Отсеиваются только элементы и наклейки — окно, натянутое на всю
## стену, ничего не проверяет.
const SURFACE_CATEGORIES := ["wall", "floor", "ceiling"]
## Строка выбора геометрии. Отдельным ключом, а не поверхностью: список у неё
## свой, а обработчик тот же.
const TEMPLATE_ROW := "__template"

var _room: RoomAssembler = null
var _materials: Dictionary = {}
var _templates: Dictionary = {}
var _choices: Dictionary = {}      ## строка -> PackedStringArray
var _index: Dictionary = {}        ## строка -> int
var _labels: Dictionary = {}       ## строка -> Label


static func create(room: RoomAssembler, materials: Dictionary,
		templates: Dictionary, current: Dictionary,
		current_template: String) -> RoomDebugPanel:
	var panel := RoomDebugPanel.new()
	panel.name = "RoomDebugPanel"
	panel._room = room
	panel._materials = materials
	panel._templates = templates
	panel._build(current, current_template)
	return panel


func _build(current: Dictionary, current_template: String) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.10, 0.14, 0.92)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(14)
	add_theme_stylebox_override("panel", sb)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	col.add_child(UIKit.label("КОМНАТА: ГЕОМЕТРИЯ И МАТЕРИАЛЫ", 20, UIKit.ACCENT))

	var template_ids := PackedStringArray()
	for id in _templates:
		template_ids.append(String(id))
	_choices[TEMPLATE_ROW] = template_ids
	_index[TEMPLATE_ROW] = maxi(0, template_ids.find(current_template))
	col.add_child(_row(TEMPLATE_ROW, "Шаблон"))

	var ids := PackedStringArray()
	for id in _materials:
		var mat: RoomMaterial = _materials[id]
		if SURFACE_CATEGORIES.has(mat.category):
			ids.append(String(id))

	for surface_id in SURFACE_TITLES:
		## Строка только для тех поверхностей, что у комнаты есть. Потолок
		## необязателен, и строка «Потолок», которая ничего не переключает,
		## врала бы про то, из чего комната собрана.
		if not current.has(surface_id):
			continue
		_choices[surface_id] = ids
		_index[surface_id] = maxi(0, ids.find(String(current.get(surface_id, ""))))
		col.add_child(_row(String(surface_id), String(SURFACE_TITLES[surface_id])))


func _row(key: String, title_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var title := UIKit.label(title_text, 18)
	title.custom_minimum_size = Vector2(150, 0)
	row.add_child(title)

	row.add_child(_step_button(key, -1, "<"))

	var value := UIKit.label(_current_id(key), 18, UIKit.ACCENT)
	value.custom_minimum_size = Vector2(230, 44)
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(value)
	_labels[key] = value

	row.add_child(_step_button(key, 1, ">"))
	return row


func _step_button(key: String, delta: int, text: String) -> Button:
	var b := UIKit.button(text, 22)
	b.custom_minimum_size = Vector2(56, 44)
	b.pressed.connect(func(): _step(key, delta))
	return b


## Шаг по списку. Материал меняется на месте, геометрия — пересборкой всей
## комнаты: поверхности при смене шаблона встают в других местах, и подменить
## одну текстуру тут недостаточно.
func _step(key: String, delta: int) -> void:
	var list: PackedStringArray = _choices[key]
	if list.is_empty():
		return
	_index[key] = posmod(int(_index[key]) + delta, list.size())
	if key == TEMPLATE_ROW:
		_room.rebuild_with_template(_templates.get(_current_id(key)))
	else:
		_room.set_surface_material(key, _current_id(key))
	(_labels[key] as Label).text = _current_id(key)


func _current_id(key: String) -> String:
	var list: PackedStringArray = _choices[key]
	if list.is_empty():
		return ""
	return list[int(_index[key]) % list.size()]
