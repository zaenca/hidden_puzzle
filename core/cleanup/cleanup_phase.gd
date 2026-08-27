class_name CleanupPhase
extends CanvasLayer
## Фаза уборки: предмет из нижней полосы перетаскивается в область кадра, кадр
## меняется на следующее состояние комнаты, предмет уходит из полосы.
##
## Живёт в экранных координатах: тащат от чипа в панели (это UI) к месту в
## сцене (это мир), и держать одну систему координат на оба конца дешевле, чем
## переводить туда-сюда на каждый кадр перетаскивания. Мир приходит снаружи —
## уровень отдаёт готовые экранные точки.
##
## Активен ровно один шаг. Всё остальное — и другие предметы, и остальной
## кадр — не реагирует: это обучение, а не свободная песочница, и промах по
## соседней области здесь не «ошибка игрока», а шум.

signal step_done(index: int)
signal completed

const DRAG_ICON_PX := 132.0
const RETURN_SEC := 0.18
const HINT_DELAY := 1.2      ## сколько ждём игрока, прежде чем показать руку

var _steps: Array[CleanupStep] = []
var _view: SceneView
var _hud: LevelHUD
var _items: Dictionary = {}
var _to_screen: Callable = Callable()

var _index: int = -1
var _active: bool = false

var _root: Control
var _drag_icon: TextureRect
var _dragging: bool = false
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

	_drag_icon = TextureRect.new()
	_drag_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_drag_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_drag_icon.size = Vector2(DRAG_ICON_PX, DRAG_ICON_PX)
	_drag_icon.pivot_offset = Vector2(DRAG_ICON_PX, DRAG_ICON_PX) * 0.5
	_drag_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_icon.visible = false
	_root.add_child(_drag_icon)


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


## Рука ждёт, а не выскакивает сразу: если игрок уже потянул предмет, подсказка
## ему только мешает.
func _process(delta: float) -> void:
	if not _active or _dragging or _hand != null:
		return
	_hint_timer += delta
	if _hint_timer >= HINT_DELAY:
		show_hint()


## --- подсказка --------------------------------------------------------------

func show_hint() -> void:
	var step := current()
	if step == null or not _active or _hand != null:
		return
	var from := _hud.chip_rect(step.item_id).get_center()
	var to := _target_screen(step)
	if from == Vector2.ZERO:
		return
	_hand = TutorialHand.new()
	_root.add_child(_hand)
	_hand.play_drag(from, to)


func _stop_hint() -> void:
	_hint_timer = 0.0
	if _hand == null:
		return
	_hand.stop()
	_hand = null


func _target_screen(step: CleanupStep) -> Vector2:
	var world := _view.norm_to_world(step.centroid())
	return _to_screen.call(world) if _to_screen.is_valid() else world


## --- перетаскивание ---------------------------------------------------------

## Тащить можно только предмет текущего шага. Остальные чипы и весь кадр глухие.
func handle_press(screen_pos: Vector2) -> bool:
	var step := current()
	if not _active or step == null:
		return false
	if not _hud.chip_rect(step.item_id).has_point(screen_pos):
		return false
	_stop_hint()
	_dragging = true
	var item: ItemDefinition = _items.get(step.item_id)
	_drag_icon.texture = PlaceholderArt.item_icon(item, int(DRAG_ICON_PX))
	_drag_icon.visible = true
	_move_icon(screen_pos)
	return true


func handle_drag(screen_pos: Vector2) -> void:
	if _dragging:
		_move_icon(screen_pos)


func handle_release(world_pos: Vector2) -> void:
	if not _dragging:
		return
	_dragging = false
	_drag_icon.visible = false

	var step := current()
	if step == null:
		return
	if not step.rect.has_point(_view.world_to_norm(world_pos)):
		## Промах молча возвращает предмет: ругаться на игрока, которому только
		## что показали пальцем, не за что.
		_hint_timer = HINT_DELAY - RETURN_SEC
		return
	_apply(step)


func _move_icon(screen_pos: Vector2) -> void:
	_drag_icon.position = screen_pos - _drag_icon.size * 0.5


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
