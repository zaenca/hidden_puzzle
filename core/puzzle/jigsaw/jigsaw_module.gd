extends PuzzleModule
## Jigsaw — первая puzzle-механика. Ничего не знает про мету, экономику
## и пекарню: получает параметры, текстуру и два прямоугольника (доска и лоток).

const LIFT := Vector2(0, -110)   ## поднимаем часть над пальцем, чтобы её было видно

var _params: JigsawParams
var _pieces: Array[JigsawPiece] = []
var _image_rect: Rect2
var _tray_rect: Rect2
var _cell_size: Vector2
var _placed_count: int = 0
var _dragging: JigsawPiece = null
var _frame: Line2D
var _pieces_root: Node2D


func _ready() -> void:
	set_process_unhandled_input(false)


func setup(params: PuzzleParams, texture: Texture2D, image_rect: Rect2, tray_rect: Rect2,
		uv_scale: Vector2 = Vector2.ONE) -> void:
	_params = params as JigsawParams
	if _params == null:
		_params = JigsawParams.new()
	_image_rect = image_rect
	_tray_rect = tray_rect
	_cell_size = Vector2(image_rect.size.x / float(_params.cols), image_rect.size.y / float(_params.rows))

	_frame = Line2D.new()
	_frame.points = PackedVector2Array([
		image_rect.position,
		image_rect.position + Vector2(image_rect.size.x, 0),
		image_rect.position + image_rect.size,
		image_rect.position + Vector2(0, image_rect.size.y),
		image_rect.position,
	])
	_frame.width = 4.0
	_frame.default_color = Color(1, 1, 1, 0.25)
	add_child(_frame)

	_pieces_root = Node2D.new()
	_pieces_root.name = "Pieces"
	add_child(_pieces_root)

	var geometry := JigsawGeometry.build(
		_params.cols, _params.rows, image_rect.size, _params.tab_ratio, _params.seed)

	for entry in geometry:
		var piece := JigsawPiece.create(entry["polygon"], entry["origin"], texture, uv_scale)
		piece.home = image_rect.position + entry["origin"]
		_pieces_root.add_child(piece)
		_pieces.append(piece)

	_layout_tray()
	progress_changed.emit(0, _pieces.size())


func begin() -> void:
	set_process_unhandled_input(true)


func progress() -> Vector2i:
	return Vector2i(_placed_count, _pieces.size())


## --- раскладка лотка --------------------------------------------------------

func _layout_tray() -> void:
	var count := _pieces.size()
	var tray_rows := 2
	var tray_cols := int(ceil(count / float(tray_rows)))
	var cell := Vector2(_tray_rect.size.x / float(tray_cols), _tray_rect.size.y / float(tray_rows))
	var s: float = minf(cell.x / _cell_size.x, cell.y / _cell_size.y) * 0.82
	s = minf(s, _params.tray_scale * 1.6)

	var order: Array[int] = []
	for i in count:
		order.append(i)
	var rng := RandomNumberGenerator.new()
	rng.seed = (_params.seed if _params.seed != 0 else 7) + 991
	for i in range(count - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := order[i]
		order[i] = order[j]
		order[j] = tmp

	for slot in count:
		var piece := _pieces[order[slot]]
		var row := slot / tray_cols
		var col := slot % tray_cols
		var center := _tray_rect.position + Vector2((col + 0.5) * cell.x, (row + 0.5) * cell.y)
		piece.tray_scale = s
		piece.tray_point = center - piece.centroid * s
		piece.send_to_tray(false)


## --- ввод -------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var world := _to_world(event.position)
		if event.pressed:
			_begin_drag(world)
		else:
			_end_drag()
	elif event is InputEventScreenDrag and _dragging != null:
		_move_drag(_to_world(event.position))


func _to_world(screen_pos: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * screen_pos


func _begin_drag(world: Vector2) -> void:
	for i in range(_pieces.size() - 1, -1, -1):
		var piece := _pieces[i]
		if piece.placed:
			continue
		if piece.hit_test(world):
			_dragging = piece
			piece.z_index = 500
			piece.scale = Vector2.ONE
			_move_drag(world)
			return


func _move_drag(world: Vector2) -> void:
	if _dragging == null:
		return
	_dragging.position = world - _dragging.centroid + LIFT


func _end_drag() -> void:
	if _dragging == null:
		return
	var piece := _dragging
	_dragging = null
	if piece.distance_to_home() <= _params.snap_distance_px:
		_place(piece)
	else:
		piece.send_to_tray(true)


func _place(piece: JigsawPiece) -> void:
	piece.place()
	_placed_count += 1
	progress_changed.emit(_placed_count, _pieces.size())
	if _placed_count >= _pieces.size():
		_on_solved()


func _on_solved() -> void:
	set_process_unhandled_input(false)
	_frame.visible = false
	solved.emit()


## --- бустеры и отладка ------------------------------------------------------

func apply_booster(_booster_id: String) -> bool:
	for piece in _pieces:
		if not piece.placed:
			_place(piece)
			return true
	return false


func force_solve() -> void:
	for piece in _pieces:
		if not piece.placed:
			piece.place()
			_placed_count += 1
	progress_changed.emit(_placed_count, _pieces.size())
	_on_solved()


## --- бесшовное раскрытие ----------------------------------------------------

func fade_seams(duration: float) -> void:
	if _frame != null:
		_frame.visible = false
	var tw := create_tween().set_parallel(true)
	for piece in _pieces:
		tw.tween_method(piece.set_seam_alpha, 1.0, 0.0, duration)


func fade_out(duration: float) -> void:
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, duration)
	tw.tween_callback(func(): visible = false)
