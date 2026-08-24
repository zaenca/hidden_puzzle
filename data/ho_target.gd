class_name HOTarget
extends Resource
## Цель hidden-object фазы. Координаты нормализованы (0..1) относительно
## SceneArt.reference_size — это делает разметку независимой от разрешения PNG
## и от aspect ratio устройства.

enum Kind { NORMAL, THEMED, QUEST }

@export var id: String = ""
@export var item_id: String = ""
@export var kind: Kind = Kind.NORMAL
@export var shape: PackedVector2Array = PackedVector2Array()
@export var hint_zoom: float = 1.6

func bounds() -> Rect2:
	if shape.is_empty():
		return Rect2()
	var r := Rect2(shape[0], Vector2.ZERO)
	for i in range(1, shape.size()):
		r = r.expand(shape[i])
	return r

func centroid() -> Vector2:
	if shape.is_empty():
		return Vector2.ZERO
	var acc := Vector2.ZERO
	for p in shape:
		acc += p
	return acc / float(shape.size())

func is_quest() -> bool:
	return kind == Kind.QUEST
