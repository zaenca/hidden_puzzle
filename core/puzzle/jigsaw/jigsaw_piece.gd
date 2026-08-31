class_name JigsawPiece
extends Node2D
## Одна часть пазла. Polygon2D с UV по общей текстуре сцены — поэтому когда
## все части на местах, изображение совпадает с фоном пиксель-в-пиксель,
## и слой пазла можно просто погасить.

var polygon: PackedVector2Array
var home: Vector2 = Vector2.ZERO       ## позиция, при которой часть на месте
var tray_point: Vector2 = Vector2.ZERO ## позиция в лотке
var tray_scale: float = 0.42
var placed: bool = false
var centroid: Vector2 = Vector2.ZERO

var _poly: Polygon2D
var _outline: Line2D
var _bounds: Rect2


static func create(poly: PackedVector2Array, origin: Vector2, texture: Texture2D,
		uv_scale: Vector2 = Vector2.ONE) -> JigsawPiece:
	var piece := JigsawPiece.new()
	piece.polygon = poly

	piece._poly = Polygon2D.new()
	piece._poly.polygon = poly
	var uv := PackedVector2Array()
	for p in poly:
		uv.append((p + origin) * uv_scale)
	piece._poly.uv = uv
	piece._poly.texture = texture
	piece.add_child(piece._poly)

	piece._outline = Line2D.new()
	var line := PackedVector2Array(poly)
	if poly.size() > 0:
		line.append(poly[0])
	piece._outline.points = line
	piece._outline.width = 3.0
	piece._outline.default_color = Color(0.05, 0.04, 0.03, 0.75)
	piece._outline.joint_mode = Line2D.LINE_JOINT_ROUND
	piece.add_child(piece._outline)

	piece._recalc()
	return piece


func _recalc() -> void:
	if polygon.is_empty():
		return
	var acc := Vector2.ZERO
	var r := Rect2(polygon[0], Vector2.ZERO)
	for p in polygon:
		acc += p
		r = r.expand(p)
	centroid = acc / float(polygon.size())
	_bounds = r


## Габариты части вместе с ушками. Раскладка лотка обязана считать по ним, а не
## по клетке пазла: ушки торчат за клетку, и часть, посчитанная по клетке,
## ложится в ячейку с нахлёстом на соседнюю.
func bounds() -> Rect2:
	return _bounds


func hit_test(world: Vector2) -> bool:
	var local := to_local(world)
	if Geometry2D.is_point_in_polygon(local, polygon):
		return true
	# Прощение для мелких частей в лотке: палец толще контура.
	var pad := 22.0 / maxf(0.05, scale.x)
	return _bounds.grow(pad).has_point(local)


func distance_to_home() -> float:
	return position.distance_to(home)


func place() -> void:
	placed = true
	position = home
	scale = Vector2.ONE
	rotation = 0.0
	z_index = 0
	modulate = Color.WHITE


func send_to_tray(animated: bool = true) -> void:
	z_index = 0
	if animated and is_inside_tree():
		var tw := create_tween().set_parallel(true)
		tw.tween_property(self, "position", tray_point, 0.18).set_trans(Tween.TRANS_SINE)
		tw.tween_property(self, "scale", Vector2.ONE * tray_scale, 0.18)
	else:
		position = tray_point
		scale = Vector2.ONE * tray_scale


func set_seam_alpha(a: float) -> void:
	if _outline != null:
		_outline.modulate.a = a
