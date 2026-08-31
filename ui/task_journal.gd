class_name TaskJournal
extends Control
## Журнал заданий: кнопка слева вверху и список за ней.
##
## Живёт в оверлее Boot, а не в сцене: путь игрока не принадлежит ни карте, ни
## локации, и переписанный в каждой сцене он превратился бы в два списка,
## которые однажды разойдутся.
##
## Показывает весь путь целиком — и пройденное, и то, что ещё закрыто. Журнал
## затем и открывают, чтобы понять, где ты находишься; список из одной текущей
## строки этого не говорит, а она и так висит на карте.

const BUTTON_ICON := "res://art/ui/taskbarbutton.png"
const BUTTON_SIZE := Vector2(124, 124)
const EDGE := 24.0          ## отступ от края экрана, поверх safe area
const PANEL_WIDTH := 900.0
const PANEL_TOP := 210.0

## Выполненное, текущее и ещё закрытое различаются цветом, а не только
## значком: значок читается только вблизи, цвет — сразу.
const DONE := Color(0.42, 0.50, 0.28)
const CURRENT := Color(0.24, 0.16, 0.07)
const LATER := Color(0.58, 0.50, 0.40)

var _button: TextureButton
var _sheet: Control
var _list: VBoxContainer
var _active: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_button()
	_build_sheet()
	_fit_to_screen()
	## Задача закрывается в мете, часто ещё на уровне. Журнал, собранный один
	## раз при старте, показывал бы вчерашний список.
	EventBus.task_state_changed.connect(func(_id, _state): _rebuild())


## Размер берём у вьюпорта, а не у родителя: контейнер оверлея сам выставляет
## себе якоря до входа в дерево и остаётся нулевым, а по нулевому родителю
## растягиваться некуда — затемнение выходило размером в точку, и список
## читался поверх незатемнённой карты.
func _fit_to_screen() -> void:
	var screen := get_viewport_rect().size
	position = Vector2.ZERO
	size = screen
	if _sheet != null:
		_sheet.position = Vector2.ZERO
		_sheet.size = screen


func _build_button() -> void:
	_button = TextureButton.new()
	_button.texture_normal = Backdrop.load_texture(BUTTON_ICON)
	_button.ignore_texture_size = true
	_button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	_button.visible = false
	_button.pressed.connect(_toggle)
	add_child(_button)

	## Геометрия строго после add_child: offsets Control считает от размера
	## родителя, а до дерева он нулевой.
	var inset := SafeArea.insets(get_viewport_rect().size)
	var left := int(inset["left"]) + EDGE
	var top := int(inset["top"]) + EDGE
	_button.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_button.offset_left = left
	_button.offset_top = top
	_button.offset_right = left + BUTTON_SIZE.x
	_button.offset_bottom = top + BUTTON_SIZE.y


func _build_sheet() -> void:
	## Затемнение под списком: он перекрывает карту целиком, и без него строки
	## читаются поверх домов. Клик мимо списка закрывает — это единственный
	## жест, который игрок пробует первым.
	_sheet = UIKit.full_screen_dim(0.55)
	_sheet.visible = false
	_sheet.gui_input.connect(_on_sheet_input)
	add_child(_sheet)
	## Якоря — повторно и после add_child: full_screen_dim выставляет их ещё до
	## дерева, и offsets тогда считаются от нулевого родителя. Панель со списком
	## при этом видна, а сама затемняющая подложка остаётся размером в ноль —
	## список читается поверх незатемнённой карты.
	_sheet.set_anchors_preset(Control.PRESET_FULL_RECT)

	var panel := UIKit.plate(UIKit.PLATE)
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_sheet.add_child(panel)
	panel.position = Vector2((get_viewport_rect().size.x - PANEL_WIDTH) * 0.5, PANEL_TOP)
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)

	var title := UIKit.plate_label(36)
	title.text = "Задания"
	col.add_child(title)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 16)
	col.add_child(_list)


## --- содержимое -------------------------------------------------------------

func _rebuild() -> void:
	if _list == null:
		return
	## remove_child до queue_free: освобождение отложено до конца кадра, и
	## пересобранный в том же кадре журнал держал бы старые строки рядом с
	## новыми. На экране это не видно, а вот прочитать список — уже нельзя.
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()

	var n := 0
	for task in Game.meta.all_tasks():
		n += 1
		_list.add_child(_row(n, task, Game.meta.task_state(task.id)))


## Строка журнала. Номер стоит всегда: список без нумерации читается как набор
## дел, а не как путь, и «что после чего» из него не видно.
func _row(number: int, task: MetaTaskDefinition, state: int) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)

	var mark := "•"
	var color := LATER
	var size := 28
	match state:
		MetaService.TaskState.COMPLETED:
			mark = "✓"
			color = DONE
		MetaService.TaskState.LOCKED:
			mark = "•"
			color = LATER
		_:
			## Текущее — крупнее остальных: ради него журнал и открывают.
			mark = "▶"
			color = CURRENT
			size = 32

	box.add_child(_line("%d.  %s  %s" % [number, mark, task.title], size, color))
	## Подсказка только у текущего: у пройденного она уже не нужна, у закрытого
	## — это спойлер.
	if state != MetaService.TaskState.COMPLETED and state != MetaService.TaskState.LOCKED \
			and not task.hint.is_empty():
		box.add_child(_line("     %s" % task.hint, 24, LATER))
	return box


## Свой Label вместо UIKit.label: там светлая буква с чёрной обводкой под арт,
## а здесь тёмная по кремовой бумаге — обводка превратила бы её в грязь.
func _line(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(PANEL_WIDTH - 60.0, 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## --- показ ------------------------------------------------------------------

## Журнал держится там, где игрок принимает решения. На уровне слева вверху
## стоит выход, и вторая кнопка в том же углу — это две кнопки «уйти отсюда».
func set_active(on: bool) -> void:
	_active = on
	if _button != null:
		_button.visible = on
	if not on:
		close()


func _toggle() -> void:
	if _sheet.visible:
		close()
	else:
		open()


func open() -> void:
	if not _active:
		return
	_fit_to_screen()
	_rebuild()
	_sheet.visible = true


func close() -> void:
	if _sheet != null:
		_sheet.visible = false


func _on_sheet_input(event: InputEvent) -> void:
	var tap: bool = event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed
	var click: bool = event is InputEventMouseButton and (event as InputEventMouseButton).pressed
	if tap or click:
		close()


## --- для headless-прогона ---------------------------------------------------

func is_open() -> bool:
	return _sheet != null and _sheet.visible


## Строки журнала как текст: прогон обязан проверять то, что прочтёт игрок,
## а не то, что мета думает про свои задачи.
func lines() -> PackedStringArray:
	var out := PackedStringArray()
	if _list == null:
		return out
	for row in _list.get_children():
		for child in row.get_children():
			if child is Label:
				out.append((child as Label).text)
	return out
