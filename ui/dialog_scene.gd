extends Node2D
## Сцена диалога: реплики поверх арта, где окно и кнопка уже нарисованы.
##
## Из этого следует всё остальное. Своего окна сцена не рисует — она вписывает
## текст в нарисованное, поэтому rect'ы текста, таблички имени и кнопки лежат в
## данных и нормализованы К КАРТИНКЕ, а не к экрану: посчитать их от экрана
## значит промахнуться мимо рамки на любом соотношении сторон.
##
## Кто говорит — тот и смотрит на игрока: у каждого говорящего свой фон, где его
## взгляд направлен в камеру. Поэтому смена реплики меняет и картинку.
##
## Camera2D в сцене НЕТ намеренно. Окно диалога нарисовано на арте, а подписи и
## кнопка живут в CanvasLayer, то есть в экранных координатах. Камера двигает
## мир относительно экрана на любом окне, чей формат отличается от 9:16, — и
## текст с кнопкой уезжают от нарисованной рамки. Без камеры мир и экран
## совпадают, и арт кладётся по РЕАЛЬНОМУ размеру вьюпорта, а не по опорному
## 1080x1920: тогда совпадение точное при любом формате окна.

const FADE := 0.18

@onready var _bg: Sprite2D = $Background
@onready var _ui: CanvasLayer = $UI

var dialog_id: String = ""

var _data: Dictionary = {}
var _lines: Array = []
var _speakers: Dictionary = {}
var _index: int = -1
var _done: bool = false

var _art_rect: Rect2 = Rect2()
var _text: Label
var _name: Label
var _name_holder: Control
var _textures: Dictionary = {}   ## speaker_id -> Texture2D
var _show_tap_hint: bool = false
var _hand: TutorialHand = null


func setup(payload: Dictionary = {}) -> void:
	dialog_id = String(payload.get("dialog_id", ""))
	_show_tap_hint = bool(payload.get("show_tap_hint", false))
	if not is_node_ready():
		await ready
	_build()


func _build() -> void:
	_data = ContentDB.dialog(dialog_id)
	_lines = _data.get("lines", [])
	_speakers = _data.get("speakers", {})

	for id in _speakers:
		var tex := Backdrop.load_texture(String(_speakers[id].get("background", "")))
		if tex != null:
			_textures[String(id)] = tex

	## Прямоугольник арта считаем по любому из фонов: у говорящих кадры одного
	## размера, окно на них в одном месте — различается только табличка имени.
	var screen := get_viewport_rect().size
	_art_rect = Rect2(Vector2.ZERO, screen)
	var first: Texture2D = _textures.values()[0] if not _textures.is_empty() else null
	if first != null:
		_art_rect = Backdrop.cover_bottom(_bg, first, screen)
	else:
		Backdrop.gradient(_bg, "street", screen)

	_build_ui()

	if _lines.is_empty():
		_finish()
		return
	_show_line(0)


## Перевод нормализованного к картинке rect'а в экранные координаты.
func _to_screen(norm: Array) -> Rect2:
	var r := ContentParser.to_rect(norm)
	return Rect2(
		_art_rect.position + Vector2(r.position.x * _art_rect.size.x, r.position.y * _art_rect.size.y),
		Vector2(r.size.x * _art_rect.size.x, r.size.y * _art_rect.size.y))


func _build_ui() -> void:
	var layout: Dictionary = _data.get("layout", {})

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(root)

	## Текст ложится на кремовое поле, поэтому он тёмный и без обводки: светлая
	## буква с чёрным контуром, которой набран весь остальной интерфейс, здесь
	## читалась бы как грязь.
	var text_rect := _to_screen(layout.get("text_rect", [0.10, 0.81, 0.75, 0.13]))
	_text = UIKit.label("", 33, Color(0.27, 0.19, 0.12))
	_text.add_theme_constant_override("outline_size", 0)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	## По центру, а не от верха: реплики от одной строки до трёх, и прижатая к
	## верху короткая фраза оставляет под собой пустое кремовое поле в пол-окна.
	_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_text)
	_text.position = text_rect.position
	_text.size = text_rect.size

	_name_holder = Control.new()
	_name_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_name_holder)

	_name = UIKit.label("", 27, Color(0.99, 0.95, 0.86))
	_name.add_theme_constant_override("outline_size", 4)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name.set_anchors_preset(Control.PRESET_FULL_RECT)
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_holder.add_child(_name)

	root.add_child(_advance_button(layout.get("advance", {})))

	## Пропуск всего разговора. Отдельной кнопкой наверху, а не долгим нажатием
	## на «дальше»: жест, о котором нигде не сказано, — это отсутствие пропуска.
	## Разговор при этом доигрывается до конца, а не бросается: флаг и переход
	## дальше висят на on_finish, и выход мимо него оставил бы игрока между
	## сценами.
	UIKit.add_skip_button(root, skip)


## Кнопка «дальше» — прозрачная накладка на кружок, который уже нарисован на
## арте. Радиус берём чуть больше нарисованного: попасть пальцем в 70 px
## сложнее, чем кажется, а промах по единственной кнопке сцены читается как
## «игра зависла».
func _advance_button(cfg: Dictionary) -> Control:
	var center_norm: Array = cfg.get("center", [0.855, 0.925])
	var radius_norm := float(cfg.get("radius", 0.055))

	var center := _art_rect.position + Vector2(
		float(center_norm[0]) * _art_rect.size.x,
		float(center_norm[1]) * _art_rect.size.y)
	var r := radius_norm * _art_rect.size.x

	var button := Button.new()
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = "Дальше"
	for style in ["normal", "hover", "pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(style, StyleBoxEmpty.new())
	button.pressed.connect(advance)
	button.size = Vector2(r * 2.0, r * 2.0)
	button.position = center - Vector2(r, r)

	## Новичку кнопку надо показать: единственный способ продолжить игру не
	## должен искаться. Рука уходит с первого же нажатия.
	if _show_tap_hint:
		_hand = TutorialHand.new()
		_ui.add_child(_hand)
		_hand.play_tap(center)

	return button


## --- реплики ----------------------------------------------------------------

func _show_line(i: int) -> void:
	if i >= _lines.size():
		_finish()
		return
	_index = i

	var line: Dictionary = _lines[i]
	var speaker_id := String(line.get("speaker", ""))
	var speaker: Dictionary = _speakers.get(speaker_id, {})

	var tex: Texture2D = _textures.get(speaker_id)
	if tex != null and _bg.texture != tex:
		_art_rect = Backdrop.cover_bottom(_bg, tex, get_viewport_rect().size)

	_name.text = String(speaker.get("name", speaker_id))
	var plate := _to_screen(speaker.get("name_rect", [0.082, 0.763, 0.311, 0.036]))
	_name_holder.position = plate.position
	_name_holder.size = plate.size

	_text.text = String(line.get("text", ""))

	_text.modulate.a = 0.0
	_name.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_text, "modulate:a", 1.0, FADE)
	tw.tween_property(_name, "modulate:a", 1.0, FADE)


## Публично: это и обработчик кнопки, и точка входа headless-прогона — он
## обязан листать диалог тем же способом, что и игрок.
func advance() -> void:
	if _done:
		return
	_stop_hint()
	_show_line(_index + 1)


## Пропустить разговор целиком. Публично по той же причине, что и advance:
## headless-прогон обязан пропускать диалог тем же способом, каким это делает
## игрок, — иначе он проверяет не ту кнопку.
func skip() -> void:
	if _done:
		return
	_stop_hint()
	_finish()


func _stop_hint() -> void:
	if _hand == null:
		return
	_hand.stop()
	_hand = null


func line_count() -> int:
	return _lines.size()


func current_speaker() -> String:
	if _index < 0 or _index >= _lines.size():
		return ""
	return String((_lines[_index] as Dictionary).get("speaker", ""))


func _finish() -> void:
	if _done:
		return
	_done = true
	Game.finish_dialog()
