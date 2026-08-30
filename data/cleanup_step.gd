class_name CleanupStep
extends Resource
## Один шаг уборки: сперва найти предмет в кадре, потом нажать туда, где он
## нужен.
##
## Оба конца шага — нажатия по одной и той же картинке: find_rect — где предмет
## лежит, rect — где его применяют. Отдельного жеста у уборки нет, и это
## намеренно: предметы в игре везде находят и применяют тапом.
##
## Каждый шаг меняет состояние комнаты целиком — не наложением поверх, а
## следующим кадром. Художник рисует «пол вымыт», «витрина отмыта», «всё
## готово», и уровню остаётся их переключать: так уборка выглядит нарисованной,
## а не собранной из полупрозрачных пятен.

@export var item_id: String = ""
## Где предмет лежит в кадре. Пусто — предмет искать не надо, он сразу в полосе.
@export var find_rect: Rect2 = Rect2()
@export var rect: Rect2 = Rect2(0, 0, 1, 1)   ## куда нажимать, нормализовано к кадру
@export var art_path: String = ""             ## каким кадр становится после шага
@export var hint: String = ""
## Что написано в подсказке, пока предмет ещё не найден.
@export var find_hint: String = ""

func centroid() -> Vector2:
	return rect.position + rect.size * 0.5


func find_centroid() -> Vector2:
	return find_rect.position + find_rect.size * 0.5


func needs_finding() -> bool:
	return find_rect.size.x > 0.0 and find_rect.size.y > 0.0
