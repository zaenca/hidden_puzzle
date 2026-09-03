class_name SortItemView
extends Node2D
## Один предмет Sort на экране: и в завале на фасаде, и в ячейке лотка.
##
## Одна нода на оба места намеренно. Предмет не «исчезает с поля и появляется в
## лотке» — он туда летит, и перелёт возможен только если это один и тот же
## объект. Второй экземпляр в лотке пришлось бы синхронизировать с первым.
##
## Начало координат — центр предмета: снаружи им управляют как точкой, а не как
## прямоугольником с углом.

## Подложка под иконку. До финального арта именно она делает предмет предметом:
## сама по себе цветная фигура на фотографии фасада читается как дефект.
const BODY_ALPHA := 0.92
const RING_WIDTH := 7.0
const ICON_FILL := 0.66   ## иконка занимает эту долю диаметра

var instance: SortItemInstance
var category_color: Color = Color.WHITE
var diameter: float = 140.0

var _icon: Sprite2D
var _ring_pulse: float = 0.0


func setup(inst: SortItemInstance, item: ItemDefinition, color: Color, size_px: float) -> void:
	instance = inst
	category_color = color
	diameter = size_px
	rotation_degrees = inst.rotation_deg

	_icon = Sprite2D.new()
	_icon.centered = true
	_icon.texture = PlaceholderArt.item_icon(item, 160)
	add_child(_icon)
	_fit_icon()
	queue_redraw()


func _fit_icon() -> void:
	if _icon == null or _icon.texture == null:
		return
	var tex := Vector2(_icon.texture.get_size())
	var target := diameter * ICON_FILL
	var s: float = target / maxf(tex.x, tex.y)
	_icon.scale = Vector2(s, s)


func _draw() -> void:
	var r := diameter * 0.5
	## Тень: без неё предмет выглядит наклейкой на фотографии, а не вещью,
	## которая на фасаде лежит.
	draw_circle(Vector2(0, r * 0.14), r, Color(0, 0, 0, 0.28))
	var body := category_color.lerp(Color(1, 1, 1), 0.38)
	body.a = BODY_ALPHA
	draw_circle(Vector2.ZERO, r, body)
	## Кольцо цвета категории — единственное, по чему до финального арта видно,
	## что три предмета собираются в одну группу.
	var ring := category_color.darkened(0.25)
	ring.a = 1.0
	draw_arc(Vector2.ZERO, r - RING_WIDTH * 0.5, 0.0, TAU, 48, ring, RING_WIDTH, true)
	## Тёмный контур по краю. Лоток нарисован кремовой плашкой, и светлый
	## предмет без него в ячейке попросту не виден.
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(0.16, 0.11, 0.06, 0.45), 3.0, true)
	if _ring_pulse > 0.0:
		draw_arc(Vector2.ZERO, r - RING_WIDTH * 0.5, 0.0, TAU, 48,
			Color(1, 1, 1, _ring_pulse), RING_WIDTH * 2.0, true)


## Радиус попадания. Чуть больше нарисованного: промах по краю предмета —
## самая обидная ошибка ввода, и стоит она дешевле, чем случайный тап по
## соседнему предмету, до которого всё равно ещё полдиаметра.
func hit_radius() -> float:
	return diameter * 0.58


func contains_point(world: Vector2) -> bool:
	return global_position.distance_to(world) <= hit_radius() * global_scale.x


## «Тебя услышали»: короткое сжатие до того, как предмет полетит в лоток.
func press_feedback() -> void:
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(0.86, 0.86), 0.07) \
		.set_trans(Tween.TRANS_SINE)
	tw.tween_property(self, "scale", Vector2.ONE, 0.09) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Перелёт в ячейку лотка. Дуга, а не прямая: по прямой предмет читается как
## подставленный движком, по дуге — как брошенный.
func fly_to(target: Vector2, target_diameter: float, duration: float) -> void:
	var start := position
	var peak := start.lerp(target, 0.5) + Vector2(0, -minf(180.0, start.distance_to(target) * 0.32))
	var scale_to: float = target_diameter / maxf(1.0, diameter)
	var tw := create_tween().set_parallel(true)
	tw.tween_method(func(t: float):
			position = start.bezier_interpolate(peak, peak, target, t),
		0.0, 1.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "scale", Vector2(scale_to, scale_to), duration) \
		.set_trans(Tween.TRANS_SINE)
	tw.tween_property(self, "rotation", 0.0, duration)


## Предмет доехал и встал в ячейку: диаметр становится ячейкиным, масштаб —
## единицей. Без этого дальнейшие перестроения лотка считали бы размер от
## старого, «фасадного» диаметра.
func settle(target_diameter: float) -> void:
	diameter = target_diameter
	scale = Vector2.ONE
	rotation = 0.0
	_fit_icon()
	queue_redraw()


## Группа собралась: предметы вспыхивают, и только потом исчезают. Без вспышки
## три ячейки просто пустеют, и игрок не связывает это со своим последним тапом.
func flash() -> void:
	var tw := create_tween()
	tw.tween_method(func(v: float):
			_ring_pulse = v
			queue_redraw(),
		0.0, 0.9, 0.14)
	tw.tween_method(func(v: float):
			_ring_pulse = v
			queue_redraw(),
		0.9, 0.0, 0.22)


func vanish(duration: float) -> void:
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "scale", Vector2(0.2, 0.2), duration) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "modulate:a", 0.0, duration)
	tw.chain().tween_callback(queue_free)


## Плавный переезд внутри лотка: ячейки схлопываются после закрытой группы.
func slide_to(target: Vector2, duration: float) -> void:
	create_tween().tween_property(self, "position", target, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
