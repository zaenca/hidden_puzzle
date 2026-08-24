extends Node2D
## Контроллер гибридного уровня — ОДИН на все уровни. Он не знает ни одного
## конкретного level id: всё приходит из LevelDefinition через LevelContext.
##
## Порядок фаз: INTRO → PUZZLE → REVEAL → HIDDEN_OBJECT → OUTRO → RESULT.
## REVEAL — отдельная фаза намеренно: это самая важная секунда игры, у неё
## должен быть свой владелец, а не «хвост» пазла.

signal finished(result: LevelResult)
signal abandoned

enum Phase { INTRO, PUZZLE, REVEAL, HIDDEN_OBJECT, OUTRO, RESULT }

const IMAGE_RECT := Rect2(0, 250, 1080, 1300)
const TRAY_RECT := Rect2(30, 1595, 1020, 290)

@onready var _view: SceneView = $SceneView
@onready var _puzzle_host: Node2D = $PuzzleHost
@onready var _ho: HiddenObjectPhase = $HOPhase
@onready var _hud: LevelHUD = $UI/HUD
@onready var _camera: Camera2D = $CameraRig/Camera2D

var context: LevelContext
var definition: LevelDefinition
var phase: int = Phase.INTRO

var _puzzle: PuzzleModule
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

	_view.setup(definition.art, definition.hidden_object.targets, context.items, IMAGE_RECT)
	_view.set_dim(1.0)

	_ho.setup(definition.hidden_object, _view, context.items)
	_ho.target_found.connect(_on_target_found)
	_ho.missed.connect(_on_miss)
	_ho.completed.connect(_on_ho_completed)

	phase = Phase.INTRO
	_hud.set_phase("")
	_hud.show_narrative(definition.narrative)


## --- PUZZLE -----------------------------------------------------------------

func _start_puzzle() -> void:
	phase = Phase.PUZZLE
	_puzzle = PuzzleRegistry.create(definition.puzzle.module_id)
	if _puzzle == null:
		push_error("HybridLevel: не создан puzzle-модуль")
		return
	_puzzle_host.add_child(_puzzle)
	_puzzle.setup(definition.puzzle, _view.texture, IMAGE_RECT, TRAY_RECT)
	_puzzle.progress_changed.connect(_hud.set_progress)
	_puzzle.solved.connect(_reveal)
	_puzzle.begin()
	_hud.set_phase("Собери сцену")


## --- REVEAL: бесшовный переход ---------------------------------------------

func _reveal() -> void:
	phase = Phase.REVEAL
	_hud.set_phase("…")
	_puzzle.fade_seams(0.35)
	await get_tree().create_timer(0.35).timeout

	_puzzle.fade_out(0.3)
	var tw := create_tween().set_parallel(true)
	tw.tween_method(_view.set_dim, 1.0, 0.0, 0.35)
	tw.tween_property(_camera, "zoom", Vector2(1.05, 1.05), 0.55).set_trans(Tween.TRANS_SINE)
	await tw.finished

	_start_hidden_object()


## --- HIDDEN OBJECT ----------------------------------------------------------

func _start_hidden_object() -> void:
	phase = Phase.HIDDEN_OBJECT
	_hud.set_phase("Найди предметы")
	_hud.show_items(definition.hidden_object.targets, context.items)
	_hud.set_progress(0, definition.hidden_object.targets.size())
	_ho.begin()


func _unhandled_input(event: InputEvent) -> void:
	if phase != Phase.HIDDEN_OBJECT:
		return
	if event is InputEventScreenTouch and event.pressed:
		_ho.handle_tap(get_canvas_transform().affine_inverse() * event.position)


func _on_target_found(target: HOTarget, item: ItemDefinition) -> void:
	_hud.mark_found(target.id)
	var found := definition.hidden_object.targets.size() - _ho.remaining().size()
	_hud.set_progress(found, definition.hidden_object.targets.size())
	if target.is_quest():
		_hud.toast("Сюжетный предмет: %s" % (item.display_name if item != null else target.item_id))


func _on_miss(_world: Vector2) -> void:
	pass


func _on_ho_completed() -> void:
	phase = Phase.OUTRO
	_hud.set_phase("Готово")
	_hud.hide_items()
	await get_tree().create_timer(0.5).timeout
	_show_result()


## --- RESULT -----------------------------------------------------------------

func _build_result() -> LevelResult:
	var r := LevelResult.new()
	r.level_id = definition.id
	r.task_id = definition.task_id
	r.success = true
	r.replay = context.replay
	r.quest_items = _ho.found_quest_items()
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
				_ho.highlight(t)
				used = true
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
	await get_tree().create_timer(1.4).timeout
	if phase == Phase.HIDDEN_OBJECT:
		_ho.force_complete()
	await get_tree().create_timer(0.8).timeout
	if phase == Phase.RESULT:
		_emit_result()
