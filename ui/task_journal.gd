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
const CHECKBOX_EMPTY := "res://art/ui/checkbox.png"
const CHECKBOX_DONE := "res://art/ui/checkboxdone.png"
const COIN_ICON := "res://art/ui/coin.png"
const CHECKBOX_SIZE := Vector2(64, 64)
const COIN_SIZE := Vector2(52, 52)
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
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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


## Строка журнала — отдельная плашка: задания читают по одному, и общий список
## внутри одной рамки склеивает их в абзац. Слева чекбокс, справа награда —
## «сделано» и «за что» стоят по краям и находятся глазом без чтения.
func _row(number: int, task: MetaTaskDefinition, state: int) -> Control:
	var done := state == MetaService.TaskState.COMPLETED
	var locked := state == MetaService.TaskState.LOCKED

	var panel := UIKit.plate(UIKit.PLATE)
	## Ширину строка берёт у списка, а не задаёт сама: у внешней плашки свои
	## поля, и строка шириной «панель минус глазомер» вылезала за них — у
	## награды справа отрезало половину числа.
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	panel.add_child(row)

	row.add_child(_checkbox(done))

	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 2)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)

	## Номер стоит всегда: список без нумерации читается как набор дел, а не как
	## путь, и «что после чего» из него не видно.
	var color := DONE if done else (LATER if locked else CURRENT)
	var size := 32 if not done and not locked else 28
	text.add_child(_line("%d.  %s" % [number, task.title], size, color))
	## Подсказка только у текущего: у пройденного она уже не нужна, у закрытого
	## — это спойлер.
	if not done and not locked and not task.hint.is_empty():
		text.add_child(_line(task.hint, 24, LATER))

	if task.reward_coins > 0:
		row.add_child(_reward(task.reward_coins, done))
	return panel


## Чекбокс — картинка, а не значок в тексте: он стоит в своей колонке и его
## состояние должно читаться раньше, чем игрок начал читать строку.
func _checkbox(done: bool) -> Control:
	var box := TextureRect.new()
	box.texture = Backdrop.load_texture(CHECKBOX_DONE if done else CHECKBOX_EMPTY)
	box.custom_minimum_size = CHECKBOX_SIZE
	box.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	box.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return box


## Награда за задачу: монета и число. У пройденной приглушена — это уже не
## обещание, а запись о том, что заплачено.
func _reward(coins: int, done: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var icon := TextureRect.new()
	icon.texture = Backdrop.load_texture(COIN_ICON)
	icon.custom_minimum_size = COIN_SIZE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)

	var amount := _line(str(coins), 28, DONE if done else CURRENT)
	## Без переноса: число короткое, а перенос по словам ломает его пополам,
	## когда колонка с названием забирает всю ширину строки.
	amount.autowrap_mode = TextServer.AUTOWRAP_OFF
	amount.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	amount.custom_minimum_size = Vector2.ZERO
	row.add_child(amount)
	return row


## Свой Label вместо UIKit.label: там светлая буква с чёрной обводкой под арт,
## а здесь тёмная по кремовой бумаге — обводка превратила бы её в грязь.
func _line(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(0, 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## --- показ ------------------------------------------------------------------

## Журнал держится там, где игрок принимает решения, — на карте и в локации.
## На уровне слева вверху стоит выход, и вторая кнопка в том же углу — это
## две кнопки «уйти отсюда».
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
		_collect_labels(row, out)
	return out


## Обход в глубину: строка журнала — это плашка, внутри неё колонка, внутри
## колонки текст. Перебор одних только прямых детей не находит ничего.
func _collect_labels(node: Node, out: PackedStringArray) -> void:
	if node is Label:
		out.append((node as Label).text)
	for child in node.get_children():
		_collect_labels(child, out)


## Названия задач, отмеченных галочкой. Читаем текстуру чекбокса, а не состояние
## задачи в мете: галочка — это то, по чему игрок судит о своём прогрессе, и
## разойтись она может именно с метой.
func done_titles() -> PackedStringArray:
	var out := PackedStringArray()
	if _list == null:
		return out
	for row in _list.get_children():
		var texts := PackedStringArray()
		_collect_labels(row, texts)
		if not texts.is_empty() and _has_done_mark(row):
			out.append(texts[0])
	return out


func _has_done_mark(node: Node) -> bool:
	if node is TextureRect:
		var tex: Texture2D = (node as TextureRect).texture
		return tex != null and tex.resource_path == CHECKBOX_DONE
	for child in node.get_children():
		if _has_done_mark(child):
			return true
	return false
