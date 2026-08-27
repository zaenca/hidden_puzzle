class_name SceneView
extends Node2D
## Общий визуал ОБЕИХ фаз уровня. Не пересоздаётся между фазами — именно
## поэтому переход puzzle → hidden object не является сменой сцены.
##
## Слоёв два: Background — пустая комната, её игрок собирает как пазл; Objects —
## тот же кадр с предметами поиска, он проявляется на reveal. Разделены
## намеренно: пока предметы запечены в ту же картинку, их видно по частям
## в лотке ещё до того, как пазл собран.

var background: Sprite2D
var objects: Sprite2D
var markers: Node2D
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


## area — место, отведённое уровню под картинку. Картинка ВПИСЫВАЕТСЯ в него по
## своему формату, а не растягивается на него: арт 9:16 в области 1080x1300
## иначе сжимался бы по горизонтали в полтора раза. Получившийся прямоугольник
## и есть rect — по нему же режутся части пазла и считаются цели поиска,
## поэтому расхождению между картинкой и хитбоксами взяться неоткуда.
func setup(art: SceneArt, targets: Array[HOTarget], items: Dictionary, area: Rect2) -> void:
	_ensure_nodes()
	texture = PlaceholderArt.build_scene_texture(art, targets, items)
	objects_texture = Backdrop.load_texture(art.objects_background_path)

	var tex_size := Vector2(texture.get_size())
	var s: float = minf(area.size.x / tex_size.x, area.size.y / tex_size.y)
	var fitted := tex_size * s
	rect = Rect2(area.position + (area.size - fitted) * 0.5, fitted)

	_place(background, texture)
	_place(objects, objects_texture)


## Оба слоя ложатся в один и тот же rect: они снимки одной комнаты, и любое
## расхождение между ними читалось бы как рывок на переходе.
func _place(sprite: Sprite2D, tex: Texture2D) -> void:
	sprite.texture = tex
	if tex == null:
		sprite.visible = false
		return
	var tex_size := Vector2(tex.get_size())
	sprite.position = rect.position
	sprite.scale = Vector2(rect.size.x / tex_size.x, rect.size.y / tex_size.y)


func has_objects_layer() -> bool:
	return objects_texture != null


## Проявление предметов — вторая половина бесшовного раскрытия: комната собрана,
## и в ней «обнаруживается» то, что предстоит найти.
func reveal_objects(duration: float) -> void:
	if objects_texture == null:
		return
	objects.visible = true
	var tw := create_tween()
	tw.tween_property(objects, "modulate:a", 1.0, duration)


## Во сколько раз пиксели текстуры плотнее экранных. Пазл режет изображение в
## координатах rect, а сэмплирует в пиксельных — без этого множителя части
## сходятся со сдвигом ровно там, где картинка не 1:1 к своей области, и
## собранный пазл остаётся разлинованным швами.
func uv_scale() -> Vector2:
	if texture == null or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return Vector2.ONE
	var tex_size := Vector2(texture.get_size())
	return Vector2(tex_size.x / rect.size.x, tex_size.y / rect.size.y)


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
## Глубина зависит от того, есть ли отдельный слой предметов: если есть, в фоне
## прятать уже нечего, и гасить его сильно значит только мешать собирать —
## особенно на тёмном интерьере.
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
