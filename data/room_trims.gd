class_name RoomTrims
extends Resource
## Стыки поверхностей. Без них комната читается как три отдельные картинки,
## положенные рядом: угол выглядит как шов между двумя PNG, а пол — как
## приклеенный к стене прямоугольник.
##
## Всё здесь необязательно и выключается нулём: комната обязана собираться и
## без единого стыка, иначе «опциональность» была бы только на словах.

## Затемнение в углу комнаты. width — доля стены от угла, на которую ложится
## градиент; strength — насколько темно у самого угла.
@export var corner_width: float = 0.0
@export var corner_strength: float = 0.0
@export var corner_color: Color = Color(0, 0, 0, 1)

## Плинтус: полоса внизу стены. height — доля высоты стены.
@export var baseboard_height: float = 0.0
@export var baseboard_material_id: String = ""
@export var baseboard_generator: String = ""
@export var baseboard_tint: Color = Color(0.86, 0.82, 0.76)

## Контактная тень на полу вдоль стен — то, что превращает стык в стык.
## size — доля пола от стены, strength — плотность.
@export var contact_size: float = 0.0
@export var contact_strength: float = 0.0
@export var contact_color: Color = Color(0, 0, 0, 1)


func has_corner() -> bool:
	return corner_width > 0.0 and corner_strength > 0.0

func has_baseboard() -> bool:
	return baseboard_height > 0.0

func has_contact() -> bool:
	return contact_size > 0.0 and contact_strength > 0.0
