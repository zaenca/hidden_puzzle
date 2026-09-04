class_name SortZoneView
extends Node2D
## Закрытая зона на экране: место, куда пока нет доступа.
##
## Рисуется затемнением с рамкой поверх своего участка поля. Не «крышкой ящика»
## и не замком: чем именно закрыта зона, рассказывает сам кадр — на ней стоят
## коробки, и они видны. Задача этой ноды — показать границу места и то, что
## внутрь не заглянуть, а не изобрести второй язык поверх нарисованного.
##
## Начало координат — левый верхний угол зоны: снаружи ею управляют как
## прямоугольником, а не как точкой.

const FILL := Color(0.05, 0.04, 0.03, 0.52)
const BORDER_WIDTH := 4.0
const CORNER := 18.0
const LABEL_SIZE := 26

var box: Rect2 = Rect2()
var tint: Color = Color(0.35, 0.26, 0.17)

var _label: Label = null


func setup(rect_px: Rect2, color: Color, text: String) -> void:
	box = Rect2(Vector2.ZERO, rect_px.size)
	position = rect_px.position
	tint = color
	if text.is_empty():
		return
	_label = UIKit.label(text, LABEL_SIZE)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	## По нижнему краю, а не по центру: в середине зоны стоит то, что её держит,
	## и подпись под этим предметом читается наполовину.
	_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_label.size = rect_px.size
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)


func _draw() -> void:
	draw_rect(box, FILL, true)
	## Рамка цветом зоны: она обводит место, а не предмет, и по ней видно, где
	## заканчивается «сюда пока нельзя».
	draw_rect(box, Color(tint.r, tint.g, tint.b, 0.9), false, BORDER_WIDTH)


func contains_point(world: Vector2) -> bool:
	return Rect2(global_position, box.size).has_point(world)


## «Заперто»: короткое подрагивание границы в ответ на тап. Тот же ответ, что и
## у придавленного предмета, — потому что для игрока это одно и то же событие.
func refuse_feedback() -> void:
	var base := modulate
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color(1.6, 1.5, 1.3, base.a), 0.10)
	tw.tween_property(self, "modulate", base, 0.22)


## Зона открылась: затемнение уходит, и под ним оказывается то, что там лежало.
## Только прозрачность — начало координат стоит в углу зоны, и любой масштаб
## растаскивал бы её от угла, а не от середины.
func open(duration: float) -> void:
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_callback(queue_free)
