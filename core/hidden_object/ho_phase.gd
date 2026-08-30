class_name HiddenObjectPhase
extends Node2D
## Hidden-object фаза. Работает поверх той же SceneView, что и puzzle:
## предметы уже нарисованы в изображении, здесь только попадания и обратная связь.

signal target_found(target: HOTarget, item: ItemDefinition)
signal missed(world_pos: Vector2)
signal completed

const TOUCH_FORGIVENESS_PX := 26.0

var _config: HOConfig
var _view: SceneView
var _items: Dictionary = {}
var _found: Dictionary = {}     ## target_id -> true
var _active: bool = false
var _quest_total: int = 0
var _quest_found: int = 0
var _normal_found: int = 0
var _misses: int = 0


func setup(config: HOConfig, view: SceneView, items: Dictionary) -> void:
	_config = config
	_view = view
	_items = items
	_found.clear()
	_quest_found = 0
	_normal_found = 0
	_misses = 0
	_quest_total = config.quest_targets().size()


func begin() -> void:
	_active = true


func stop() -> void:
	_active = false


func is_active() -> bool:
	return _active


func stats() -> Dictionary:
	return {
		"misses": _misses,
		"quest_found": _quest_found,
		"normal_found": _normal_found,
	}


func remaining() -> Array[HOTarget]:
	var out: Array[HOTarget] = []
	for t in _config.targets:
		if not _found.has(t.id):
			out.append(t)
	return out


func found_quest_items() -> PackedStringArray:
	var out := PackedStringArray()
	for t in _config.targets:
		if t.is_quest() and _found.has(t.id):
			out.append(t.item_id)
	return out


func handle_tap(world: Vector2) -> bool:
	if not _active:
		return false
	var norm := _view.world_to_norm(world)
	var hit := _pick(norm)
	if hit == null:
		_misses += 1
		missed.emit(world)
		return false
	_register(hit)
	return true


## Точное попадание, иначе — прощение по радиусу, но только если рядом
## ровно одна цель (иначе «прочёсывание» тапами становится стратегией).
func _pick(norm: Vector2) -> HOTarget:
	for t in _config.targets:
		if _found.has(t.id):
			continue
		if Geometry2D.is_point_in_polygon(norm, t.shape):
			return t

	var tol := Vector2(
		TOUCH_FORGIVENESS_PX / _view.rect.size.x,
		TOUCH_FORGIVENESS_PX / _view.rect.size.y)
	var candidates: Array[HOTarget] = []
	for t in _config.targets:
		if _found.has(t.id):
			continue
		if t.bounds().grow_individual(tol.x, tol.y, tol.x, tol.y).has_point(norm):
			candidates.append(t)
	return candidates[0] if candidates.size() == 1 else null


func _register(t: HOTarget) -> void:
	_found[t.id] = true
	if t.is_quest():
		_quest_found += 1
	else:
		_normal_found += 1
	_draw_found_marker(t)
	target_found.emit(t, _items.get(t.item_id))
	if is_complete():
		_active = false
		completed.emit()


func is_complete() -> bool:
	return _quest_found >= _quest_total and _normal_found >= _config.required_normal


## Какую цель подсказать бустером. Фаза называет цель, но не рисует подсказку:
## как она выглядит — вопрос уровня, а не механики поиска.
func hint_target() -> HOTarget:
	var left := remaining()
	return left[0] if not left.is_empty() else null


func force_complete() -> void:
	for t in _config.targets:
		if _found.has(t.id):
			continue
		if t.is_quest() or _normal_found < _config.required_normal:
			_register(t)
		if is_complete():
			break
	if is_complete() and _active:
		_active = false
		completed.emit()


func _draw_found_marker(t: HOTarget) -> void:
	if _view == null:
		return
	var poly := _view.norm_polygon_to_world(t.shape)
	var outline := Line2D.new()
	var pts := PackedVector2Array(poly)
	if pts.size() > 0:
		pts.append(pts[0])
	outline.points = pts
	outline.width = 6.0
	outline.default_color = Color(0.35, 0.95, 0.45, 0.9)
	_view.markers.add_child(outline)

	var fill := Polygon2D.new()
	fill.polygon = poly
	fill.color = Color(0.2, 0.8, 0.35, 0.35)
	_view.markers.add_child(fill)

	var tw := outline.create_tween()
	tw.tween_property(outline, "width", 10.0, 0.12)
	tw.tween_property(outline, "width", 6.0, 0.12)
