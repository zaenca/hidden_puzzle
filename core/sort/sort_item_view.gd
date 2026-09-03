class_name SortItemView
extends Node2D
## Один предмет Sort на экране: и в завале на кадре, и в ячейке лотка.
##
## Ничего, кроме самой картинки предмета. Ни подложки, ни рамки: предмет должен
## выглядеть лежащей вещью, а не фишкой настольной игры — категорию игрок
## читает по самому предмету (паутина, лужа, обрывки бумаги), и обводить их
## цветными кольцами значит объяснять то, что и так видно.
##
## Одна нода на оба места намеренно. Предмет не «исчезает с кадра и появляется в
## лотке» — он туда летит, и перелёт возможен только если это один и тот же
## объект. Второй экземпляр в лотке пришлось бы синхронизировать с первым.
##
## Начало координат — центр предмета: снаружи им управляют как точкой, а не как
## прямоугольником с углом.

## Запас вокруг картинки под палец. Промах по краю предмета — самая обидная
## ошибка ввода, и стоит она дешевле, чем случайный тап по соседу: до соседа
## всё равно ещё полкартинки.
const HIT_PAD := 1.12

var instance: SortItemInstance
var category_color: Color = Color.WHITE
## Габарит предмета по большей стороне, px. Картинки не квадратные, вторая
## сторона считается по пропорциям исходника.
var span: float = 140.0

var _icon: Sprite2D


func setup(inst: SortItemInstance, item: ItemDefinition, color: Color, size_px: float) -> void:
	instance = inst
	category_color = color
	span = size_px
	rotation_degrees = inst.rotation_deg

	_icon = Sprite2D.new()
	_icon.centered = true
	_icon.texture = PlaceholderArt.item_icon(item, 160)
	add_child(_icon)
	_fit_icon()


## Вписываем по большей стороне: `size` в данных — это габарит предмета, а не
## ширина. Иначе широкая лужа и высокий ящик, заданные одним числом, оказались
## бы на экране разной величины.
func _fit_icon() -> void:
	if _icon == null or _icon.texture == null:
		return
	var tex := Vector2(_icon.texture.get_size())
	var s: float = span / maxf(1.0, maxf(tex.x, tex.y))
	_icon.scale = Vector2(s, s)


## Размер картинки на экране, px.
func drawn_size() -> Vector2:
	if _icon == null or _icon.texture == null:
		return Vector2(span, span)
	return Vector2(_icon.texture.get_size()) * _icon.scale * scale


## Область под палец в мировых координатах.
func hit_rect() -> Rect2:
	var size := drawn_size() * HIT_PAD
	return Rect2(global_position - size * 0.5, size)


func contains_point(world: Vector2) -> bool:
	return hit_rect().has_point(world)


## «Тебя услышали»: короткое сжатие до того, как предмет полетит в лоток.
func press_feedback() -> void:
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(0.86, 0.86), 0.07) \
		.set_trans(Tween.TRANS_SINE)
	tw.tween_property(self, "scale", Vector2.ONE, 0.09) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Перелёт в ячейку лотка. Дуга, а не прямая: по прямой предмет читается как
## подставленный движком, по дуге — как брошенный.
func fly_to(target: Vector2, target_span: float, duration: float) -> void:
	var start := position
	var peak := start.lerp(target, 0.5) + Vector2(0, -minf(180.0, start.distance_to(target) * 0.32))
	var scale_to: float = target_span / maxf(1.0, span)
	var tw := create_tween().set_parallel(true)
	tw.tween_method(func(t: float):
			position = start.bezier_interpolate(peak, peak, target, t),
		0.0, 1.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "scale", Vector2(scale_to, scale_to), duration) \
		.set_trans(Tween.TRANS_SINE)
	tw.tween_property(self, "rotation", 0.0, duration)


## Предмет доехал и встал в ячейку: габарит становится ячейкиным, масштаб —
## единицей. Без этого дальнейшие перестроения лотка считали бы размер от
## старого, «кадрового» габарита.
func settle(target_span: float) -> void:
	span = target_span
	scale = Vector2.ONE
	rotation = 0.0
	_fit_icon()


## Группа собралась: предметы вспыхивают, и только потом исчезают. Без вспышки
## три ячейки просто пустеют, и игрок не связывает это со своим последним тапом.
func flash() -> void:
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color(2.2, 2.2, 2.2), 0.14)
	tw.tween_property(self, "modulate", Color.WHITE, 0.22)


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
