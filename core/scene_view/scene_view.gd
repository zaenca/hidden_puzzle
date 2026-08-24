class_name SceneView
extends Node2D
## Общий визуал ОБЕИХ фаз уровня. Не пересоздаётся между фазами — именно
## поэтому переход puzzle → hidden object не является сменой сцены.

var background: Sprite2D
var markers: Node2D
var rect: Rect2 = Rect2()
var texture: Texture2D


func _ensure_nodes() -> void:
	if background == null:
		background = Sprite2D.new()
		background.name = "Background"
		background.centered = false
		add_child(background)
	if markers == null:
		markers = Node2D.new()
		markers.name = "Markers"
		add_child(markers)


func setup(art: SceneArt, targets: Array[HOTarget], items: Dictionary, image_rect: Rect2) -> void:
	_ensure_nodes()
	rect = image_rect
	texture = PlaceholderArt.build_scene_texture(art, targets, items)
	background.texture = texture
	background.position = image_rect.position
	var tex_size := Vector2(texture.get_size())
	background.scale = Vector2(image_rect.size.x / tex_size.x, image_rect.size.y / tex_size.y)


func norm_to_world(p: Vector2) -> Vector2:
	return rect.position + Vector2(p.x * rect.size.x, p.y * rect.size.y)


func world_to_norm(p: Vector2) -> Vector2:
	return Vector2((p.x - rect.position.x) / rect.size.x, (p.y - rect.position.y) / rect.size.y)


func norm_polygon_to_world(poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		out.append(norm_to_world(p))
	return out


## Во время puzzle-фазы фон приглушён: игрок собирает изображение, а не видит
## готовый ответ. При reveal возвращается в норму — это часть перехода.
func set_dim(amount: float) -> void:
	if background != null:
		var c := lerpf(1.0, 0.28, clampf(amount, 0.0, 1.0))
		background.modulate = Color(c, c, c * 1.05, 1.0)


func clear_markers() -> void:
	if markers == null:
		return
	for child in markers.get_children():
		child.queue_free()
