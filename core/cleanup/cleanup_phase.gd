class_name CleanupPhase
extends CanvasLayer
## Фаза уборки: игрок нажимает на место, которое надо привести в порядок, — и
## кадр меняется на следующее состояние комнаты, а предмет уходит из полосы.
##
## Нажатие, а не перетаскивание. Предметы в этой игре находят и применяют одним
## тапом — и в фазе поиска, и в локациях. Отдельный жест ровно в одном месте
## игрок не выучивает, а спотыкается о него: тянет там, где надо нажать, и
## наоборот.
##
## Живёт в экранных координатах: рука-подсказка и полоса предметов — это UI, и
## держать одну систему координат на них дешевле, чем переводить туда-сюда.
## Мир приходит снаружи — уровень отдаёт готовые экранные точки.
##
## Активен ровно один шаг. Всё остальное — и другие предметы, и остальной
## кадр — не реагирует: это обучение, а не свободная песочница, и промах по
## соседней области здесь не «ошибка игрока», а шум.

signal step_done(index: int)
signal completed

const HINT_DELAY := 1.2      ## сколько ждём игрока, прежде чем показать руку

var _steps: Array[CleanupStep] = []
var _view: SceneView
var _hud: LevelHUD
var _items: Dictionary = {}
var _to_screen: Callable = Callable()

var _index: int = -1
var _active: bool = false

var _root: Control
var _hand: TutorialHand = null
var _hint_timer: float = 0.0


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
	_next_step()


func current() -> CleanupStep:
	return _steps[_index] if _index >= 0 and _index < _steps.size() else null


func remaining_items() -> PackedStringArray:
	var out := PackedStringArray()
	for i in range(maxi(_index, 0), _steps.size()):
		out.append(_steps[i].item_id)
	return out


func _next_step() -> void:
	_stop_hint()
	_index += 1
	if _index >= _steps.size():
		_active = false
		completed.emit()
		return
	_hint_timer = 0.0
	var step := current()
	if step != null and not step.hint.is_empty():
		_hud.set_phase(step.hint)


## Рука ждёт, а не выскакивает сразу: если игрок уже понял, куда нажимать,
## подсказка ему только мешает.
func _process(delta: float) -> void:
	if not _active or _hand != null:
		return
	_hint_timer += delta
	if _hint_timer >= HINT_DELAY:
		show_hint()


## --- подсказка --------------------------------------------------------------

## Показывает, КУДА нажать. По ней же работает лампочка в HUD.
func show_hint() -> void:
	var step := current()
	if step == null or not _active or _hand != null:
		return
	_hand = TutorialHand.new()
	_root.add_child(_hand)
	_hand.play_tap(_target_screen(step))


func _stop_hint() -> void:
	_hint_timer = 0.0
	if _hand == null:
		return
	_hand.stop()
	_hand = null


func _target_screen(step: CleanupStep) -> Vector2:
	var world := _view.norm_to_world(step.centroid())
	return _to_screen.call(world) if _to_screen.is_valid() else world


## --- нажатие ----------------------------------------------------------------

## Нажимать можно только по месту текущего шага. Остальной кадр глухой.
## Промах молча ничего не делает: ругаться на игрока, которому только что
## показали пальцем, не за что — рука просто вернётся.
func handle_tap(world_pos: Vector2) -> bool:
	var step := current()
	if not _active or step == null:
		return false
	if not step.rect.has_point(_view.world_to_norm(world_pos)):
		_hint_timer = HINT_DELAY
		return false
	_stop_hint()
	_apply(step)
	return true


## Шаг засчитан: кадр переключается на следующее состояние комнаты, предмет
## уходит из полосы.
func _apply(step: CleanupStep) -> void:
	_view.swap_background(step.art_path, 0.35)
	_hud.take_chip(step.item_id)
	step_done.emit(_index)
	_next_step()


func force_complete() -> void:
	while _active and current() != null:
		_apply(current())
