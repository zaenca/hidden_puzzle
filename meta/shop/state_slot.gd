class_name StateSlot
extends Node2D
## Один изменяемый объект магазина. Дети = варианты состояния, активен ровно
## один. Копии всей пекарни под каждое визуальное состояние не создаются —
## это структурный запрет, а не соглашение.

var slot_id: String = ""
var current_state: String = ""
var world_rect: Rect2 = Rect2()   ## область слота на экране — по ней идёт хит-тест
var art_mode: bool = false        ## поверх настоящего арта рисуем только плёнку

var _variants: Dictionary = {}   ## state_id -> Node2D
var _highlight: Line2D = null


## art_mode = у магазина есть настоящий фон. Тогда слот ничего не «рисует
## вместо» объекта — объект уже нарисован художником. Остаётся только плёнка
## состояния (грязь, тень) и рамка «сюда можно нажать».
static func create(def: ShopSlotDefinition, area: Rect2, art_mode: bool = false) -> StateSlot:
	var slot := StateSlot.new()
	slot.slot_id = def.id
	slot.name = "Slot_" + def.id
	slot.art_mode = art_mode

	var rect := Rect2(
		area.position + Vector2(def.rect.position.x * area.size.x, def.rect.position.y * area.size.y),
		Vector2(def.rect.size.x * area.size.x, def.rect.size.y * area.size.y))
	slot.world_rect = rect

	for state in def.states:
		var variant := Node2D.new()
		variant.name = state.id
		variant.visible = false
		if art_mode:
			if state.has_overlay():
				var film := Polygon2D.new()
				film.polygon = _shape_polygon(rect, state.shape)
				film.color = state.overlay
				variant.add_child(film)
		elif not state.hidden:
			var poly := Polygon2D.new()
			poly.polygon = _shape_polygon(rect, state.shape)
			poly.color = state.color
			variant.add_child(poly)

			var outline := Line2D.new()
			var pts := PackedVector2Array(poly.polygon)
			if pts.size() > 0:
				pts.append(pts[0])
			outline.points = pts
			outline.width = 3.0
			outline.default_color = Color(0, 0, 0, 0.45)
			variant.add_child(outline)

			var label := UIKit.label(state.label, 26)
			label.position = rect.position + Vector2(8, rect.size.y - 40)
			label.size = Vector2(rect.size.x - 16, 36)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			variant.add_child(label)
		slot.add_child(variant)
		slot._variants[state.id] = variant

	return slot


func set_state(state_id: String, animate: bool = true) -> void:
	if not _variants.has(state_id):
		push_warning("StateSlot %s: нет состояния '%s' (контент изменился?)" % [slot_id, state_id])
		return
	if current_state == state_id:
		return
	for id in _variants:
		_variants[id].visible = false
	var variant: Node2D = _variants[state_id]
	variant.visible = true
	current_state = state_id
	if not (animate and is_inside_tree()):
		return
	variant.modulate.a = 0.0
	# Точки плёнки заданы в мировых координатах, поэтому scale тянул бы её от
	# начала координат сцены, а не от самого объекта. Поверх арта — только альфа.
	if art_mode:
		variant.create_tween().tween_property(variant, "modulate:a", 1.0, 0.35)
		return
	variant.scale = Vector2(0.86, 0.86)
	var tw := variant.create_tween().set_parallel(true)
	tw.tween_property(variant, "modulate:a", 1.0, 0.35)
	tw.tween_property(variant, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Подсветка «с этим объектом сейчас можно что-то сделать». Рисуется поверх
## варианта состояния и живёт отдельно от него: состояния меняются, рамка нет.
func set_highlight(on: bool) -> void:
	if on == (_highlight != null):
		return
	if not on:
		_highlight.queue_free()
		_highlight = null
		return

	var inset := world_rect.grow(-4.0)
	_highlight = Line2D.new()
	_highlight.points = PackedVector2Array([
		inset.position,
		inset.position + Vector2(inset.size.x, 0),
		inset.position + inset.size,
		inset.position + Vector2(0, inset.size.y),
		inset.position,
	])
	_highlight.width = 5.0
	_highlight.default_color = UIKit.ACCENT
	_highlight.joint_mode = Line2D.LINE_JOINT_ROUND
	add_child(_highlight)

	var tw := _highlight.create_tween().set_loops()
	tw.tween_property(_highlight, "modulate:a", 0.35, 0.7)
	tw.tween_property(_highlight, "modulate:a", 1.0, 0.7)


static func _shape_polygon(rect: Rect2, shape: String) -> PackedVector2Array:
	match shape:
		"circle":
			var pts := PackedVector2Array()
			var c := rect.position + rect.size * 0.5
			for i in 24:
				var a := TAU * float(i) / 24.0
				pts.append(c + Vector2(cos(a) * rect.size.x * 0.5, sin(a) * rect.size.y * 0.5))
			return pts
		"triangle":
			return PackedVector2Array([
				rect.position + Vector2(rect.size.x * 0.5, 0),
				rect.position + rect.size,
				rect.position + Vector2(0, rect.size.y),
			])
		_:
			return PackedVector2Array([
				rect.position,
				rect.position + Vector2(rect.size.x, 0),
				rect.position + rect.size,
				rect.position + Vector2(0, rect.size.y),
			])
