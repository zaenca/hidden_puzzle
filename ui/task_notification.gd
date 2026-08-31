class_name TaskNotification
extends Control
## Всплывающая плашка «задание выполнено».
##
## Живёт в оверлее Boot, а не в сцене: задача закрывается в мете, и момент этот
## приходится на смену экрана — уровень уже отдал результат, карта ещё не
## построилась. Плашка в сцене такое событие просто не пережила бы.
##
## Показывается по одной. Авто-применяемые действия умеют закрывать две задачи
## подряд, и две плашки друг поверх друга читаются как одна сломанная.

const TEXTURE_PATH := "res://art/ui/taskbar_notification.png"
const PATCH_MARGIN := 36      ## поля 9-slice: перекрывают рамку и скругление
const SIZE := Vector2(880, 170)
const TOP_Y := 150.0          ## куда выезжает плашка
const SLIDE_IN := 0.4
const HOLD := 1.9
const SLIDE_OUT := 0.3

const CAPTION := Color(0.55, 0.40, 0.20)
const TITLE := Color(0.24, 0.16, 0.07)

var _plate: NinePatchRect
var _caption: Label
var _title: Label

var _queue: PackedStringArray = PackedStringArray()
var _playing: bool = false
var _current: String = ""
var _tween: Tween = null
var _active: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	EventBus.task_state_changed.connect(_on_task_state_changed)


func _build() -> void:
	_plate = NinePatchRect.new()
	_plate.texture = Backdrop.load_texture(TEXTURE_PATH)
	_plate.patch_margin_left = PATCH_MARGIN
	_plate.patch_margin_right = PATCH_MARGIN
	_plate.patch_margin_top = PATCH_MARGIN
	_plate.patch_margin_bottom = PATCH_MARGIN
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.size = SIZE
	_plate.visible = false
	add_child(_plate)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 2)
	_plate.add_child(col)

	## Свои Label вместо UIKit: там чёрная обводка под светлый текст на арте, а
	## здесь тёмный текст на кремовом — обводка превратила бы его в грязь.
	_caption = _plain("Задание выполнено", 26, CAPTION)
	col.add_child(_caption)
	_title = _plain("", 38, TITLE)
	col.add_child(_title)


func _plain(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(SIZE.x - PATCH_MARGIN * 2, 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## --- события ----------------------------------------------------------------

func _on_task_state_changed(task_id: String, state: int) -> void:
	if state != MetaService.TaskState.COMPLETED:
		return
	var task: MetaTaskDefinition = ContentDB.task(task_id)
	if task == null or task.title.is_empty():
		return
	_queue.append(task.title)
	_flush()


## Плашка ждёт своего экрана. Задача часто закрывается ещё в уровне — поздравлять
## поверх раскрытия сцены значит перебивать ровно тот кадр, ради которого
## уровень и собирали.
func set_active(on: bool) -> void:
	_active = on
	if on:
		_flush()
	elif _playing:
		_interrupt()


## Экран сменился посреди показа. Плашку убираем сразу — доигрывать её поверх
## заголовка уровня незачем, — но заголовок возвращаем в начало очереди: игрок
## мог не успеть прочитать, а терять уведомление о закрытой задаче нельзя.
func _interrupt() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	_plate.visible = false
	_playing = false
	if not _current.is_empty():
		_queue.insert(0, _current)
		_current = ""


func _flush() -> void:
	if _playing or not _active or _queue.is_empty():
		return
	var title := _queue[0]
	_queue.remove_at(0)
	_play(title)


func _play(title: String) -> void:
	_playing = true
	_current = title
	_title.text = title

	_plate.visible = true
	_plate.modulate.a = 0.0
	## Центр берём у вьюпорта в момент показа, а не из опорной ширины 1080: на
	## окне шире опорного 9:16 «половина 1080» — уже не середина экрана, и плашка
	## уезжает влево. size самого контрола для этого не годится: на первом показе
	## раскладка ещё не посчитана и он равен нулю.
	_plate.position = Vector2(
		(get_viewport_rect().size.x - SIZE.x) * 0.5, TOP_Y - SIZE.y - 40.0)

	var tw := create_tween()
	_tween = tw
	tw.set_parallel(true)
	tw.tween_property(_plate, "position:y", TOP_Y, SLIDE_IN) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_plate, "modulate:a", 1.0, SLIDE_IN * 0.5)
	tw.chain().tween_interval(HOLD)
	tw.chain().tween_property(_plate, "position:y", TOP_Y - SIZE.y - 40.0, SLIDE_OUT) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_plate, "modulate:a", 0.0, SLIDE_OUT)
	tw.chain().tween_callback(_finish_one)


func _finish_one() -> void:
	_plate.visible = false
	_playing = false
	_current = ""
	_tween = null
	_flush()


## Для headless-прогона: «плашка показана» и «задача закрыта» — разные
## утверждения, и ломается обычно первое.
func is_showing() -> bool:
	return _playing


func shown_title() -> String:
	return _title.text if _playing else ""


func pending() -> int:
	return _queue.size()


## Знает ли виджет про это уведомление — показывает сейчас или ещё покажет.
## Две задачи умеют закрыться подряд, и «плашка про вторую уже на экране» было
## бы проверкой очерёдности, а не того, что игрока вообще известили.
func knows(title: String) -> bool:
	return _current == title or _queue.has(title)
