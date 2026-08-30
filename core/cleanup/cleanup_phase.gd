class_name CleanupPhase
extends CanvasLayer
## Фаза уборки в два захода: сперва НАЙТИ предметы в кадре, потом ПРИМЕНИТЬ
## каждый там, где он нужен. Оба конца — нажатие по картинке, отдельного жеста
## у уборки нет: предметы в этой игре везде находят и применяют тапом.
##
## Почему сперва все три, а не «нашёл — применил — нашёл следующий»: применение
## меняет кадр комнаты целиком, а нарисованные состояния «пол вымыт» и дальше
## предметов уже не содержат. Найти оставшееся после первой же смены кадра было
## бы негде.
##
## Живёт в экранных координатах: рука-подсказка и полоса предметов — это UI, и
## держать одну систему координат на них дешевле, чем переводить туда-сюда.
## Мир приходит снаружи — уровень отдаёт готовые экранные точки.
##
## Подсказку игрок вызывает сам, кнопкой: рука, выскакивающая по таймеру,
## отвечает на вопрос, которого игрок ещё не задал, и лишает находку смысла.

signal step_done(index: int)
signal item_found(item_id: String)
signal completed

enum Stage { FIND, USE }

var _steps: Array[CleanupStep] = []
var _view: SceneView
var _hud: LevelHUD
var _items: Dictionary = {}
var _to_screen: Callable = Callable()

var _stage: int = Stage.FIND
var _index: int = -1
var _found: Dictionary = {}       ## item_id -> true
var _active: bool = false

var _root: Control
var _hand: TutorialHand = null


func setup(steps: Array[CleanupStep], view: SceneView, hud: LevelHUD,
		items: Dictionary, to_screen: Callable) -> void:
	_steps = steps
	_view = view
	_hud = hud
	_items = items
	_to_screen = to_screen
	layer = 2
	_build()


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)


## --- ход фазы ---------------------------------------------------------------

func begin() -> void:
	_active = true
	_index = -1
	_found.clear()
	_stage = Stage.FIND if not _to_find().is_empty() else Stage.USE
	if _stage == Stage.FIND:
		for step in _steps:
			if step.needs_finding():
				_hud.set_chip_dim(step.item_id, true)
		_announce_find()
	else:
		_next_step()


func stage() -> int:
	return _stage


## Шаг, который применяют прямо сейчас. В фазе поиска шага ещё нет.
func current() -> CleanupStep:
	return _steps[_index] if _index >= 0 and _index < _steps.size() else null


## Что ещё предстоит найти — в порядке шагов, чтобы подсказка была предсказуемой.
func _to_find() -> Array[CleanupStep]:
	var out: Array[CleanupStep] = []
	for step in _steps:
		if step.needs_finding() and not _found.has(step.item_id):
			out.append(step)
	return out


func remaining_items() -> PackedStringArray:
	var out := PackedStringArray()
	for i in range(maxi(_index, 0), _steps.size()):
		out.append(_steps[i].item_id)
	return out


func _announce_find() -> void:
	var left := _to_find()
	if left.is_empty():
		return
	var hint := String(left[0].find_hint)
	_hud.set_phase(hint if not hint.is_empty() else "Найди, чем убирать")


func _next_step() -> void:
	_stop_hint()
	_index += 1
	if _index >= _steps.size():
		_active = false
		completed.emit()
		return
	var step := current()
	if step != null and not step.hint.is_empty():
		_hud.set_phase(step.hint)


## --- подсказка --------------------------------------------------------------

## Показывает палец на том, что нужно прямо сейчас: в фазе поиска — на самом
## предмете, в фазе применения — на месте, куда его применяют.
func show_hint() -> bool:
	if not _active or _hand != null:
		return false
	var at := _hint_point()
	if at == Vector2.ZERO:
		return false
	_hand = TutorialHand.new()
	_root.add_child(_hand)
	_hand.play_tap(at)
	return true


func _hint_point() -> Vector2:
	if _stage == Stage.FIND:
		var left := _to_find()
		if left.is_empty():
			return Vector2.ZERO
		return _to_world_screen(left[0].find_centroid())
	var step := current()
	return _to_world_screen(step.centroid()) if step != null else Vector2.ZERO


func _stop_hint() -> void:
	if _hand == null:
		return
	_hand.stop()
	_hand = null


func _to_world_screen(norm: Vector2) -> Vector2:
	var world := _view.norm_to_world(norm)
	return _to_screen.call(world) if _to_screen.is_valid() else world


## --- нажатие ----------------------------------------------------------------

## Промах молча ничего не делает: ругаться на игрока, который ищет, не за что.
func handle_tap(world_pos: Vector2) -> bool:
	if not _active:
		return false
	var norm := _view.world_to_norm(world_pos)
	if _stage == Stage.FIND:
		return _try_find(norm)
	var step := current()
	if step == null or not step.rect.has_point(norm):
		return false
	_stop_hint()
	_apply(step)
	return true


func _try_find(norm: Vector2) -> bool:
	for step in _to_find():
		if not step.find_rect.has_point(norm):
			continue
		_stop_hint()
		_take(step)
		return true
	return false


## Найденный предмет уходит из кадра и загорается в полосе: «оно теперь моё».
func _take(step: CleanupStep) -> void:
	_found[step.item_id] = true
	_view.hide_region(step.find_rect)
	_hud.set_chip_dim(step.item_id, false)
	item_found.emit(step.item_id)
	if _to_find().is_empty():
		_stage = Stage.USE
		_next_step()
	else:
		_announce_find()


## Шаг засчитан: кадр переключается на следующее состояние комнаты, предмет
## уходит из полосы.
func _apply(step: CleanupStep) -> void:
	_view.swap_background(step.art_path, 0.35)
	_hud.take_chip(step.item_id)
	step_done.emit(_index)
	_next_step()


func force_complete() -> void:
	while _active and _stage == Stage.FIND:
		var left := _to_find()
		if left.is_empty():
			break
		_take(left[0])
	while _active and current() != null:
		_apply(current())
