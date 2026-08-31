extends Node2D
## Заставка: экраны текста поверх одной картинки. Одна сцена на все заставки —
## различия только в данных (content/intros/<id>.json). Экран без текста это
## просто кадр: так показывается фасад пекарни перед разговором с хозяйкой.
##
## Куда идти после — не дело сцены, она сообщает Game «доиграла».
##
## Экраны сменяются сами, но тап всегда работает: пока текст ещё проявляется —
## показывает его целиком, после — переводит дальше. Тап во время проявления не
## должен проматывать непрочитанное, иначе игрок теряет строку, ничего не сделав
## неправильно.

## Camera2D в сцене нет: арт кладётся по реальному размеру вьюпорта, поэтому
## заполняет окно любого формата без чёрных полей по краям.
const FADE_IN := 0.8
const HOLD := 3.4
const FADE_OUT := 0.6
const SILENT_HOLD := 2.0   ## экран без текста: сколько держать одну картинку

@onready var _bg: Sprite2D = $Background
@onready var _ui: CanvasLayer = $UI

var intro_id: String = ""

var _screens: Array = []
var _index: int = -1
var _revealed: bool = false
var _done: bool = false
var _has_art: bool = false
var _label: Label
var _panel: Control
var _tween: Tween


func setup(payload: Dictionary = {}) -> void:
	intro_id = String(payload.get("intro_id", ""))
	if not is_node_ready():
		await ready
	_build()


func _build() -> void:
	var data := ContentDB.intro(intro_id)
	_screens = data.get("screens", [])

	var screen := get_viewport_rect().size
	var tex := Backdrop.load_texture(String(data.get("background", "")))
	_has_art = tex != null
	if _has_art:
		Backdrop.cover(_bg, tex, screen)
	else:
		Backdrop.gradient(_bg, String(data.get("palette", "street")), screen)

	_build_ui()

	if _screens.is_empty():
		_finish()
		return
	_show_screen(0)


func _build_ui() -> void:
	## Всё, кроме кнопки пропуска, не ловит мышь: тап по любому месту экрана
	## должен доходить до _unhandled_input и двигать текст.
	var dim := UIKit.full_screen_dim(0.32)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(dim)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(root)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(margin)
	SafeArea.apply(margin, 40)

	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.alignment = BoxContainer.ALIGNMENT_END
	col.add_theme_constant_override("separation", 20)
	margin.add_child(col)

	_panel = UIKit.panel(Color(0.07, 0.07, 0.10, 0.82))
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_panel)

	_label = UIKit.label("", 38)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size = Vector2(0, 200)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.modulate.a = 0.0
	_panel.add_child(_label)

	## Текст стоит над нижней третью картинки, а не по центру: там мощёная
	## площадь без деталей, и здание остаётся видно целиком.
	var lift := Control.new()
	lift.custom_minimum_size = Vector2(0, 170)
	lift.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(lift)

	## Пропуск целиком, а не по экрану: заставку смотрят один раз, и на
	## повторном прохождении листать её по кадру — работа, а не выбор.
	UIKit.add_skip_button(root, _finish)


## --- смена экранов ----------------------------------------------------------

func _show_screen(i: int) -> void:
	if i >= _screens.size():
		_finish()
		return
	_index = i
	_revealed = false

	var entry: Dictionary = _screens[i] if _screens[i] is Dictionary else {}
	var lines: Array = entry.get("lines", [])
	var parts := PackedStringArray()
	for l in lines:
		parts.append(String(l))
	_label.text = "\n".join(parts)
	_label.modulate.a = 0.0

	## Экран без текста — это просто кадр: панель прячем целиком, иначе игрок
	## смотрит на пустую подложку и ждёт, когда в ней что-то появится.
	_panel.visible = not parts.is_empty()
	if parts.is_empty():
		## Кадр без текста держится только ради картинки. Если арта ещё нет —
		## это не пауза, а пустой экран, и его надо проскочить, а не выдержать.
		if not _has_art:
			_show_screen(_index + 1)
			return
		_revealed = true
		_tween = create_tween()
		_tween.tween_interval(float(entry.get("hold", SILENT_HOLD)))
		_tween.tween_callback(func(): _show_screen(_index + 1))
		return

	_tween = create_tween()
	_tween.tween_property(_label, "modulate:a", 1.0, FADE_IN)
	_tween.tween_callback(_on_revealed)


func _on_revealed() -> void:
	_revealed = true
	_play_out()


## Пауза на чтение и затухание. Отдельным твином: тап во время проявления
## прыгает сразу сюда, минуя оставшийся fade in.
func _play_out() -> void:
	_tween = create_tween()
	_tween.tween_interval(HOLD)
	_tween.tween_property(_label, "modulate:a", 0.0, FADE_OUT)
	_tween.tween_callback(func(): _show_screen(_index + 1))


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventScreenTouch and event.pressed):
		return
	_on_tap()


func _on_tap() -> void:
	if _done:
		return
	if not _revealed:
		_kill_tween()
		_label.modulate.a = 1.0
		_revealed = true
		_play_out()
		return
	_kill_tween()
	_show_screen(_index + 1)


func _finish() -> void:
	if _done:
		return
	_done = true
	_kill_tween()
	Game.finish_intro()
