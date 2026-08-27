class_name SceneView
extends Node2D
## Общий визуал ОБЕИХ фаз уровня. Не пересоздаётся между фазами — именно
## поэтому переход puzzle → hidden object не является сменой сцены.
##
## Слоёв два: Background (то, что собирается пазлом) и Objects (тот же кадр
## с предметами поиска). Objects лежит сверху и до reveal полностью прозрачен.

var background: Sprite2D
var objects: Sprite2D
var markers: Node2D

## Область изображения на экране. Считается из кадра разметки и пропорций
## текстуры, поэтому арт никогда не растягивается.
var rect: Rect2 = Rect2()
var texture: Texture2D
var objects_texture: Texture2D


func _ensure_nodes() -> void:
	if background == null:
		background = Sprite2D.new()
		background.name = "Background"
		background.centered = false
		add_child(background)
	if objects == null:
		objects = Sprite2D.new()
		objects.name = "Objects"
		objects.centered = false
		objects.modulate.a = 0.0
		objects.visible = false
		add_child(objects)
	if markers == null:
		markers = Node2D.new()
		markers.name = "Markers"
		add_child(markers)


func setup(art: SceneArt, targets: Array[HOTarget], items: Dictionary, frame: Rect2) -> void:
	_ensure_nodes()

	texture = PlaceholderArt.build_scene_texture(art, targets, items)
	objects_texture = PlaceholderArt.load_texture(art.objects_background_path)

	rect = _fit(frame, Vector2(texture.get_size()))
	_place(background, texture)
	_place(objects, objects_texture)


## Вписываем изображение в кадр по меньшей стороне и центрируем. Пазл режет
## именно rect, поэтому любое несовпадение пропорций здесь означало бы, что
## части не совпадают с фоном.
static func _fit(frame: Rect2, tex_size: Vector2) -> Rect2:
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return frame
	var s: float = minf(frame.size.x / tex_size.x, frame.size.y / tex_size.y)
	var size := tex_size * s
	return Rect2(frame.position + (frame.size - size) * 0.5, size)


func _place(sprite: Sprite2D, tex: Texture2D) -> void:
	sprite.texture = tex
	if tex == null:
		sprite.visible = false
		return
	sprite.position = rect.position
	var tex_size := Vector2(tex.get_size())
	sprite.scale = Vector2(rect.size.x / tex_size.x, rect.size.y / tex_size.y)


## Во сколько раз пиксели текстуры плотнее экранных. Пазл строит UV в
## координатах rect, поэтому ему нужен этот множитель, а не масштабирование
## самой текстуры — так арт не пересэмплируется и не мылится.
func uv_scale() -> Vector2:
	if texture == null or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return Vector2.ONE
	var tex_size := Vector2(texture.get_size())
	return Vector2(tex_size.x / rect.size.x, tex_size.y / rect.size.y)


func has_objects_layer() -> bool:
	return objects_texture != null


## Проявление слоя с предметами — вторая половина бесшовного перехода.
func reveal_objects(duration: float) -> void:
	if objects_texture == null:
		return
	objects.visible = true
	var tw := create_tween()
	tw.tween_property(objects, "modulate:a", 1.0, duration)


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
##
## Глубина затемнения зависит от того, есть ли отдельный слой предметов. Если
## есть — в фоне прятать уже нечего, и гасить его сильно значит только мешать
## собирать пазл, особенно на тёмном арте.
func set_dim(amount: float) -> void:
	if background == null:
		return
	var floor_value := 0.6 if has_objects_layer() else 0.28
	var c := lerpf(1.0, floor_value, clampf(amount, 0.0, 1.0))
	background.modulate = Color(c, c, c * 1.05, 1.0)


func clear_markers() -> void:
	if markers == null:
		return
	for child in markers.get_children():
		child.queue_free()
