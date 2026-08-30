class_name ShopSlotState
extends Resource

@export var id: String = ""
@export var label: String = ""
@export var color: Color = Color.GRAY
@export var shape: String = "rect"
@export var hidden: bool = false   ## состояние "объекта нет"
## Плёнка поверх арта для этого состояния (грязь, тень запертой двери).
## Нужна только когда у магазина есть настоящий фон: перекрасить нарисованную
## витрину нельзя, а притемнить её область — можно. Альфа 0 = ничего не рисуем.
@export var overlay: Color = Color(0, 0, 0, 0)
## Отдельная картинка объекта поверх фона локации. Нужна там, где предмет НЕ
## нарисован на фоне: собранный шкаф приезжает своим PNG и ставится в свой rect.
## Файла нет — слот падает на цвет/плёнку, локация остаётся играбельной.
@export var texture_path: String = ""

func has_overlay() -> bool:
	return overlay.a > 0.001

func has_texture() -> bool:
	return not texture_path.is_empty()
