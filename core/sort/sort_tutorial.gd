class_name SortTutorial
extends Node
## Обучение Sort: короткие подсказки, привязанные к СОБЫТИЯМ уровня.
##
## Событийное, а не пошаговое, намеренно. Шаг «предмет уходит в лоток» имеет
## смысл ровно в тот момент, когда игрок впервые тапнул, — и ни секундой
## раньше. Сценарий с фиксированным порядком пришлось бы держать в согласии с
## тем, что игрок делает на самом деле, и он бы с ним разошёлся.
##
## Про Sort здесь не знают ничего: шаги приходят данными, события — строками.

signal finished

const TEXT_SIZE := 30
const PLATE_WIDTH := 880.0
const PLATE_MARGIN := 28.0

var _steps: Array = []
var _shown: Dictionary = {}   ## event -> true
var _pending: int = 0         ## сколько шагов ещё не показано
var _hand_host: Node2D = null
var _ui_host: Control = null

var _hand: TutorialHand = null
var _plate: Control = null
var _label: Label = null


## steps — сырые словари из content/tutorial/<id>.json: {event, text, target}.
func setup(steps: Array, hand_host: Node2D, ui_host: Control, plate_top: float) -> void:
	_steps = steps
	_pending = steps.size()
	_hand_host = hand_host
	_ui_host = ui_host
	_build_plate(plate_top)


func _build_plate(plate_top: float) -> void:
	if _ui_host == null:
		return
	_plate = UIKit.plate(UIKit.PLATE)
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.visible = false
	_ui_host.add_child(_plate)
	_plate.size = Vector2(PLATE_WIDTH, 0)
	_plate.position = Vector2((_ui_host.size.x - PLATE_WIDTH) * 0.5, plate_top)

	_label = UIKit.plate_label(TEXT_SIZE)
	_label.custom_minimum_size = Vector2(PLATE_WIDTH - PLATE_MARGIN * 2.0, 74)
	_plate.add_child(_label)


## Уровень сообщает, что произошло, и где сейчас находятся ориентиры.
## targets: имя цели -> мировая точка ("item", "tray", …).
func notify_event(event: String, targets: Dictionary = {}) -> void:
	if is_done():
		return
	for raw in _steps:
		var step: Dictionary = raw
		if String(step.get("event", "")) != event:
			continue
		if _shown.has(event):
			return
		_shown[event] = true
		_pending -= 1
		_show(step, targets)
		if is_done():
			finished.emit()
		return


func _show(step: Dictionary, targets: Dictionary) -> void:
	_stop_hand()
	var text := String(step.get("text", ""))
	if _label != null and not text.is_empty():
		_label.text = text
		_plate.visible = true
		_plate.modulate.a = 0.0
		_plate.create_tween().tween_property(_plate, "modulate:a", 1.0, 0.22)

	var target := String(step.get("target", ""))
	if target.is_empty() or _hand_host == null or not targets.has(target):
		return
	_hand = TutorialHand.new()
	_hand_host.add_child(_hand)
	_hand.play_tap(targets[target])


## Все шаги показаны — обучение можно считать пройденным и больше не заводить.
func is_done() -> bool:
	return _pending <= 0


func stop() -> void:
	_stop_hand()
	if _plate != null and _plate.visible:
		var tw := _plate.create_tween()
		tw.tween_property(_plate, "modulate:a", 0.0, 0.2)
		tw.tween_callback(func(): _plate.visible = false)


func _stop_hand() -> void:
	if _hand == null:
		return
	_hand.stop()
	_hand = null
