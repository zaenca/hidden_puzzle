extends Node2D
## Контроллер гибридного уровня — ОДИН на все уровни. Он не знает ни одного
## конкретного level id: всё приходит из LevelDefinition через LevelContext.
##
## Порядок фаз: INTRO → PUZZLE → REVEAL → HIDDEN_OBJECT → OUTRO → RESULT.
## REVEAL — отдельная фаза намеренно: это самая важная секунда игры, у неё
## должен быть свой владелец, а не «хвост» пазла.

signal finished(result: LevelResult)
signal abandoned

enum Phase { INTRO, PUZZLE, REVEAL, HIDDEN_OBJECT, CLEANUP, OUTRO, RESULT }

## Доска и лоток стоят одной колонкой, и боковые границы у них общие: ширину
## обоих задаёт картинка, вписанная в BOARD_AREA. Отдельной ширины у лотка нет
## намеренно — две константы разъезжались бы на каждом новом арте.
const BOARD_AREA := Rect2(0, 150, 1080, 1400)
const BOARD_PAD := 18.0     ## углубление под картинкой: рамка вокруг доски
const TRAY_TOP := 1565.0
const TRAY_HEIGHT := 345.0
const TRAY_PATCH := 40      ## поля 9-slice лотка: перекрывают рамку и скругление
## Поле раскладки внутри лотка. Части центруются по ячейкам, но ушки торчат за
## ячейку, и крайние куски заезжали бы на нарисованную рамку плашки. По бокам
## поле уже, чем сверху и снизу: ушки съедают именно ширину — по высоте частям
## и так просторно.
const TRAY_PAD_X := 60.0
const TRAY_PAD_Y := 30.0
const SCREEN := Vector2(1080, 1920)

## Уход в мету без экрана результата: сколько держим собранную картинку и за
## сколько гасим экран.
const HOLD_BEFORE_FADE := 1.0
const FADE_OUT_SEC := 0.45

## За сколько проявляется слой предметов поиска после сборки пазла.
const OBJECTS_FADE_IN_SEC := 0.5

## Сколько предметы «доезжают» в нижнюю полосу перед фазой уборки.
const COLLECT_SEC := 0.55

## Подложка уровня. Тёплый casual-градиент вместо пустоты движка: доска и лоток
## должны читаться как предметы НА чём-то, иначе экран выглядит недорисованным.
const SKY_TOP := Color("#5fb3e0")
const SKY_BOTTOM := Color("#f5e2bd")

@onready var _backdrop: Node2D = $Backdrop
@onready var _view: SceneView = $SceneView
@onready var _puzzle_host: Node2D = $PuzzleHost
@onready var _ho: HiddenObjectPhase = $HOPhase
@onready var _hud: LevelHUD = $UI/HUD
@onready var _camera: Camera2D = $CameraRig/Camera2D

var context: LevelContext
var definition: LevelDefinition
var phase: int = Phase.INTRO

var _puzzle: PuzzleModule
var _hand: TutorialHand = null        ## обучающий ход в пазле
var _find_hand: TutorialHand = null   ## бустер-подсказка в поиске
var _cleanup: CleanupPhase = null
var _hint_active: bool = false
var _tray_slot: Control = null
var _boosters_left: int = 0
var _boosters_spent: int = 0
var _started_msec: int = 0


func setup(payload: Dictionary) -> void:
	context = payload.get("context")
	if context == null or context.definition == null:
		push_error("HybridLevel: пустой LevelContext")
		return
	definition = context.definition
	_boosters_left = context.boosters_available
	if not is_node_ready():
		await ready
	_build()


func _build() -> void:
	_started_msec = Time.get_ticks_msec()

	_hud.set_level_title(definition.title)
	_hud.set_booster_count(_boosters_left)
	_hud.abandon_pressed.connect(func(): abandoned.emit())
	_hud.booster_pressed.connect(_on_booster)
	_hud.narrative_finished.connect(_start_puzzle)
	_hud.result_continue.connect(_emit_result)

	_view.setup(definition.art, definition.hidden_object.targets, context.items, BOARD_AREA)
	_view.set_dim(1.0)
	_build_backdrop()

	_ho.setup(definition.hidden_object, _view, context.items)
	_ho.target_found.connect(_on_target_found)
	_ho.missed.connect(_on_miss)
	_ho.completed.connect(_on_ho_completed)

	phase = Phase.INTRO
	_hud.set_phase("")
	## Кнопка «Далее» ложится в лоток: место, которое до конца брифинга пустует,
	## а сразу после него занимают части. HUD сам его знать не может.
	_hud.place_narrative_button(tray_rect())
	_hud.show_narrative(definition.narrative)


## --- подложка ---------------------------------------------------------------

## Живёт в мире, а не в CanvasLayer: на раскрытии камера подъезжает, и подложка
## обязана ехать вместе с доской — иначе рамка вокруг картинки поедет отдельно
## от самой картинки.
func _build_backdrop() -> void:
	var cover := SCREEN * 1.35   ## запас под наезд камеры

	var sky := Sprite2D.new()
	sky.texture = PlaceholderArt.flat_texture(Vector2i(8, 256), SKY_TOP, SKY_BOTTOM)
	sky.centered = true
	sky.position = SCREEN * 0.5
	sky.scale = Vector2(cover.x / 8.0, cover.y / 256.0)
	_backdrop.add_child(sky)

	## Место под доску: картинка на время сборки приглушена, и без углубления
	## под ней она читается как грязное пятно, а не как «сюда собирают».
	_backdrop.add_child(_slot(_board_rect(),
		Color(0.10, 0.13, 0.20, 0.30), Color(1, 1, 1, 0.22), 28))

	## Лоток — нарисованная плашка, та же, что под текстом в игре: части лежат на
	## столе, а не в служебном прямоугольнике, дорисованном движком.
	## Лоток нужен только под части. Без пазла это пустая полка на пол-экрана.
	if not _has_puzzle():
		return
	_tray_slot = _plate_slot(tray_rect())
	_backdrop.add_child(_tray_slot)


## Плашка под лоток. NinePatchRect, а не тема панели: лоток живёт в мире, рядом
## с доской, и ему нужен собственный узел. Арта может не быть — тогда остаётся
## прежняя полка, потому что уровень обязан оставаться играбельным без картинок.
func _plate_slot(rect: Rect2) -> Control:
	var tex := Backdrop.load_texture(UIKit.PLATE)
	if tex == null:
		return _slot(rect, Color(0.42, 0.28, 0.16, 0.45), Color(1.0, 0.93, 0.80, 0.25), 34)
	var plate := NinePatchRect.new()
	plate.texture = tex
	plate.patch_margin_left = TRAY_PATCH
	plate.patch_margin_right = TRAY_PATCH
	plate.patch_margin_top = TRAY_PATCH
	plate.patch_margin_bottom = TRAY_PATCH
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.position = rect.position
	plate.size = rect.size
	return plate


## Доска с её углублением — то, что игрок видит как «поле». Считается от
## реально занятого картинкой прямоугольника, а не от BOARD_AREA: арт вписан
## по своему формату, и разница между областью и картинкой бывает в сотни px.
func _board_rect() -> Rect2:
	return _view.rect.grow(BOARD_PAD)


## Лоток. Публично: HUD кладёт в него кнопку «Далее», а прогон проверяет, что
## части лежат внутри рамки. Боковые границы берутся у доски — доска и лоток
## обязаны стоять одной колонкой, иначе экран выглядит собранным из двух разных
## макетов.
func tray_rect() -> Rect2:
	var board := _board_rect()
	return Rect2(board.position.x, TRAY_TOP, board.size.x, TRAY_HEIGHT)


func _slot(rect: Rect2, bg: Color, border: Color, radius: int) -> Panel:
	var panel := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(radius)
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.position = rect.position
	panel.size = rect.size
	return panel


## --- PUZZLE -----------------------------------------------------------------

## Есть ли на этом уровне сборка. Уровень без пазла — не поломка: в зале игрок
## убирается, и заставлять его перед этим собирать ту же комнату из кусков
## значит показывать одну и ту же картинку дважды.
func _has_puzzle() -> bool:
	return not definition.puzzle.module_id.is_empty()


func _start_puzzle() -> void:
	## Уровня без сборки фаза PUZZLE просто не касается: сцена открывается
	## сразу, и уровень начинается с того, ради чего сделан.
	if not _has_puzzle():
		_reveal()
		return
	phase = Phase.PUZZLE
	_puzzle = PuzzleRegistry.create(definition.puzzle.module_id)
	if _puzzle == null:
		push_error("HybridLevel: не создан puzzle-модуль")
		return
	_puzzle_host.add_child(_puzzle)
	## Не IMAGE_RECT, а то, что SceneView реально занял: картинка вписана в
	## отведённую область по своему формату, и резать пазл надо по ней.
	_puzzle.setup(definition.puzzle, _view.texture, _view.rect,
		tray_rect().grow_individual(-TRAY_PAD_X, -TRAY_PAD_Y, -TRAY_PAD_X, -TRAY_PAD_Y),
		_view.uv_scale())
	_puzzle.progress_changed.connect(_hud.set_progress)
	_puzzle.solved.connect(_reveal)
	_puzzle.begin()
	_hud.show_progress(false)
	## Название фазы нужно только там, где фаз больше одной. На чистом пазле оно
	## лишь повторяет заголовок уровня другими словами.
	_hud.set_phase("Собери сцену" if _has_hidden_object() else "")

	if context.show_drag_hint:
		_start_drag_hint()


## --- обучающий ход ----------------------------------------------------------

## Рука ведёт «призрак» части на её место и повторяет это, пока игрок не тронет
## экран. Путь и то, что по нему едет, знает модуль пазла — уровень только
## ведёт по этому пути руку.
func _start_drag_hint() -> void:
	var hint := _puzzle.demo_hint()
	if hint.is_empty():
		return
	_hand = TutorialHand.new()
	$FX.add_child(_hand)
	_hand.play_drag(hint["from"], hint["to"], hint["step"])
	_hint_active = true


## --- подсказка в поиске -----------------------------------------------------

## Бустер в фазе поиска показывает пальцем, куда нажать, а не обводит предмет
## рамкой. Обводка отвечает на вопрос «где он», палец — на вопрос «что делать»,
## и второй ответ здесь единственный нужный: предмет уже нарисован в сцене,
## игроку остаётся по нему попасть.
func _show_find_hint(t: HOTarget) -> void:
	_stop_find_hint()
	_find_hand = TutorialHand.new()
	$FX.add_child(_find_hand)
	_find_hand.play_tap(_view.norm_to_world(t.centroid()))


## Палец держится, пока предмет не найден: промах — это повод показывать
## дальше, а не прятать подсказку, за которую заплатили бустером.
func _stop_find_hint() -> void:
	if _find_hand == null:
		return
	_find_hand.stop()
	_find_hand = null


## Любое касание означает «я понял» — подсказка молча уходит.
func _stop_hint() -> void:
	if not _hint_active:
		return
	_hint_active = false
	if _hand != null:
		_hand.stop()
		_hand = null
	## Призрак части живёт только в фазе сборки: в фазе поиска пазла на экране
	## уже нет, и чистить в нём нечего.
	if _puzzle != null and phase == Phase.PUZZLE:
		_puzzle.clear_demo_hint()


## --- REVEAL: бесшовный переход ---------------------------------------------

func _reveal() -> void:
	_stop_hint()
	phase = Phase.REVEAL
	_hud.set_phase("…")
	if _puzzle != null:
		_puzzle.fade_seams(0.35)
	await get_tree().create_timer(0.35).timeout

	if _puzzle != null:
		_puzzle.fade_out(0.3)
	var tw := create_tween().set_parallel(true)
	## Пустая полка под собранной картинкой — просто тёмный прямоугольник.
	if _tray_slot != null:
		tw.tween_property(_tray_slot, "modulate:a", 0.0, 0.35)
	tw.tween_method(_view.set_dim, 1.0, 0.0, 0.35)
	tw.tween_property(_camera, "zoom", Vector2(1.05, 1.05), 0.55).set_trans(Tween.TRANS_SINE)
	await tw.finished

	if not _has_hidden_object() and not _has_cleanup():
		_finish_after_puzzle()
		return

	await _reveal_objects()
	if _has_cleanup():
		await _start_cleanup()
	else:
		_start_hidden_object()


## Комната собрана — и в ней проявляется то, что предстоит найти. Пазл шёл по
## пустому кадру, поэтому опознать предметы заранее по частям в лотке было
## нельзя, и их появление читается как событие, а не как смена подписи в HUD.
func _reveal_objects() -> void:
	if not _view.has_objects_layer():
		return
	_view.reveal_objects(OBJECTS_FADE_IN_SEC)
	await get_tree().create_timer(OBJECTS_FADE_IN_SEC).timeout


## --- HIDDEN OBJECT ----------------------------------------------------------

## Фаза поиска не обязательна. Уровень без целей — это чистый пазл: сюжетный
## предмет тогда выдаётся из quest_grants, а не «находится» в сцене. Так первый
## уровень может не учить двум механикам сразу, и для этого не нужен ни отдельный
## контроллер уровня, ни флаг в данных — достаточно пустого списка целей.
func _has_hidden_object() -> bool:
	return not definition.hidden_object.targets.is_empty()


func _finish_after_puzzle() -> void:
	phase = Phase.OUTRO
	if not definition.show_result:
		await _slip_into_meta()
		return
	_hud.set_phase("Готово")
	await get_tree().create_timer(0.6).timeout
	_show_result()


## Конец уровня без экрана результата. Собранная картинка держится секунду —
## это и есть награда, — потом экран гаснет, и игрок оказывается там, куда его
## ведёт история. Никакой строки «Монеты: +60» между двумя кадрами сюжета.
func _slip_into_meta() -> void:
	_hud.set_phase("")
	await get_tree().create_timer(HOLD_BEFORE_FADE).timeout
	if not is_inside_tree():
		return

	var veil := ColorRect.new()
	veil.color = Color(0, 0, 0, 0)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## Последним ребёнком слоя — поверх HUD: гаснуть должен весь экран, иначе
	## заголовок и счётчик частей висят над чернотой.
	$UI.add_child(veil)

	var tw := create_tween()
	tw.tween_property(veil, "color:a", 1.0, FADE_OUT_SEC)
	await tw.finished
	if is_inside_tree():
		_emit_result()


## --- CLEANUP: нажать туда, где найденное нужно применить -------------------

func _has_cleanup() -> bool:
	return not definition.cleanup.is_empty()


## Что предстоит убрать, показано сразу: три силуэта в нижней полосе. Это не
## «предметы уже твои», а список — каждый загорается в тот момент, когда игрок
## нашёл его в кадре. Только после этого предмет можно применить.
func _start_cleanup() -> void:
	phase = Phase.CLEANUP
	_hud.show_progress(false)

	var ids := PackedStringArray()
	for step in definition.cleanup:
		ids.append(step.item_id)
	_hud.show_item_row(ids, context.items)
	await get_tree().create_timer(COLLECT_SEC).timeout
	if not is_inside_tree():
		return

	_cleanup = CleanupPhase.new()
	_cleanup.name = "CleanupPhase"
	add_child(_cleanup)
	_cleanup.setup(definition.cleanup, _view, _hud, context.items,
		func(world: Vector2) -> Vector2: return get_canvas_transform() * world)
	_cleanup.completed.connect(_on_cleanup_completed)
	_cleanup.item_found.connect(_on_cleanup_item_found)
	_cleanup.begin()


func _on_cleanup_item_found(item_id: String) -> void:
	var item: ItemDefinition = context.items.get(item_id)
	_hud.toast("Нашлось: %s" % (item.display_name if item != null else item_id))


func _on_cleanup_completed() -> void:
	phase = Phase.OUTRO
	_hud.set_phase("")
	_hud.hide_items()
	if not definition.show_result:
		await _slip_into_meta()
		return
	await get_tree().create_timer(0.6).timeout
	_show_result()


func _start_hidden_object() -> void:
	phase = Phase.HIDDEN_OBJECT
	_hud.set_phase("Найди предметы")
	_hud.show_progress(true)
	_hud.show_items(definition.hidden_object.targets, context.items)
	_hud.set_progress(0, definition.hidden_object.targets.size())
	_ho.begin()

	if context.show_tap_hint:
		_start_tap_hint()


## Рука показывает жест поиска: предметы находятся НАЖАТИЕМ. Без этого хода
## единственное, чему игрока научили, — перетаскивание частей пазла, и тот же
## жест он переносит сюда.
func _start_tap_hint() -> void:
	var t := _ho.hint_target()
	if t == null:
		return
	_hand = TutorialHand.new()
	$FX.add_child(_hand)
	_hand.play_tap(_view.norm_to_world(t.bounds().get_center()))
	_hint_active = true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed and _hint_active:
		_stop_hint()

	if phase == Phase.CLEANUP:
		_cleanup_input(event)
		return
	if phase != Phase.HIDDEN_OBJECT:
		return
	if event is InputEventScreenTouch and event.pressed:
		_ho.handle_tap(get_canvas_transform().affine_inverse() * event.position)


## Ввод фазы уборки приходит сюда, а не в саму фазу: нажатие приходит в
## экранных координатах, а место шага размечено по кадру, и перевод между этими
## системами координат знает уровень.
func _cleanup_input(event: InputEvent) -> void:
	if _cleanup == null:
		return
	if event is InputEventScreenTouch and event.pressed:
		_cleanup.handle_tap(get_canvas_transform().affine_inverse() * event.position)


func _on_target_found(target: HOTarget, item: ItemDefinition) -> void:
	_stop_find_hint()
	_hud.mark_found(target.id)
	var found := definition.hidden_object.targets.size() - _ho.remaining().size()
	_hud.set_progress(found, definition.hidden_object.targets.size())
	if target.is_quest():
		_hud.toast("Сюжетный предмет: %s" % (item.display_name if item != null else target.item_id))


func _on_miss(_world: Vector2) -> void:
	pass


func _on_ho_completed() -> void:
	phase = Phase.OUTRO
	_hud.hide_items()
	if not definition.show_result:
		await _slip_into_meta()
		return
	_hud.set_phase("Готово")
	await get_tree().create_timer(0.5).timeout
	_show_result()


## --- RESULT -----------------------------------------------------------------

func _build_result() -> LevelResult:
	var r := LevelResult.new()
	r.level_id = definition.id
	r.task_id = definition.task_id
	r.success = true
	r.replay = context.replay
	r.quest_items = _ho.found_quest_items() if _has_hidden_object() else definition.quest_grants
	r.soft_currency = definition.rewards.coins_for(context.replay)
	r.xp = definition.rewards.xp_for(context.replay)
	if _boosters_spent > 0:
		r.boosters_spent[context.booster_id] = _boosters_spent
	r.stats = _ho.stats()
	r.stats["seconds"] = (Time.get_ticks_msec() - _started_msec) / 1000.0
	return r


func _show_result() -> void:
	phase = Phase.RESULT
	_hud.show_result(_build_result(), context.items)


func _emit_result() -> void:
	finished.emit(_build_result())


## --- бустеры ----------------------------------------------------------------

func _on_booster() -> void:
	if _boosters_left <= 0:
		_hud.toast("Бустеров нет")
		return
	var used := false
	match phase:
		Phase.PUZZLE:
			used = _puzzle != null and _puzzle.apply_booster(context.booster_id)
		Phase.HIDDEN_OBJECT:
			var t := _ho.hint_target()
			if t != null:
				_show_find_hint(t)
				used = true
		Phase.CLEANUP:
			## Подсказка нужна в обоих заходах: в поиске она показывает предмет,
			## в применении — место. Шага при этом может ещё не быть.
			used = _cleanup != null and _cleanup.show_hint()
	if used:
		_boosters_left -= 1
		_boosters_spent += 1
		_hud.set_booster_count(_boosters_left)
	else:
		_hud.toast("Бустер сейчас не применить")


## --- отладка ----------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_S:
				if phase == Phase.PUZZLE and _puzzle != null:
					_puzzle.force_solve()
			KEY_F:
				if phase == Phase.HIDDEN_OBJECT:
					_ho.force_complete()


## Полное прохождение без участия игрока — для headless-проверки цикла.
func debug_autoplay() -> void:
	if phase == Phase.INTRO:
		_start_puzzle()
	if _puzzle != null:
		_puzzle.force_solve()
	await _settle_playable()
	if not is_inside_tree():
		return
	if phase == Phase.HIDDEN_OBJECT:
		_ho.force_complete()
	elif phase == Phase.CLEANUP and _cleanup != null:
		_cleanup.force_complete()

	## Уровень без экрана результата доигрывает переход и уходит в мету сам.
	## Дожидаться его здесь нельзя: нода освободится посреди этой корутины, и
	## тот, кто её ждёт, не дождётся никогда. Прогон ждёт смены экрана снаружи.
	if not definition.show_result:
		return
	await _settle(Phase.RESULT)
	if not is_inside_tree():
		return
	if phase == Phase.RESULT:
		_emit_result()


## Ждём фазу, а не фиксированные секунды: длительность раскрытия зависит от
## того, есть ли у сцены отдельный слой предметов, и захардкоженный таймер
## начинает врать ровно при добавлении такого слоя.
## Ждём фазу, в которой прогону есть что доиграть за игрока. Фаза уборки
## доступна не сразу: предметы сперва «доезжают» в полосу, и до этого момента
## форсировать в ней нечего.
func _settle_playable(timeout_sec: float = 8.0) -> void:
	var deadline := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while is_inside_tree() and Time.get_ticks_msec() < deadline:
		if phase == Phase.HIDDEN_OBJECT or phase == Phase.OUTRO or phase == Phase.RESULT:
			return
		if phase == Phase.CLEANUP and _cleanup != null:
			return
		await get_tree().process_frame


func _settle(target: int, timeout_sec: float = 8.0) -> void:
	var deadline := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while is_inside_tree() and phase != target and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
