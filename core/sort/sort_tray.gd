class_name SortTray
extends Node2D
## Лоток: ряд ячеек внизу экрана, куда уходят выбранные предметы.
##
## Лоток — это и есть сложность Sort: ячеек конечное число, и игрок всё время
## считает, сколько осталось. Поэтому ячейки нарисованы все, включая пустые, и
## заполненность видна одним взглядом, без цифр.

const SLOT_GAP := 10.0
const PLATE_PATCH := 40      ## поля 9-slice нарисованной плашки
const SLOT_RADIUS_RATIO := 0.46
## Последние ячейки подсвечиваются тревожным цветом: «места почти нет» игрок
## должен видеть до того, как проиграет, а не в момент проигрыша.
const WARN_FREE_SLOTS := 2
const WARN_COLOR := Color(0.93, 0.45, 0.35)

var rect: Rect2 = Rect2()
var slot_count: int = 7
var slot_diameter: float = 120.0

var _plate: NinePatchRect = null
## Ячейки рисуются отдельным узлом, а не в _draw() самого лотка. Собственная
## отрисовка Node2D идёт ДО его детей, а плашка лотка — ребёнок: нарисованные
## в _draw() ячейки она бы и закрыла.
var _holes: Node2D = null
var _free_slots: int = 7


func setup(area: Rect2, count: int) -> void:
	rect = area
	slot_count = maxi(1, count)
	_free_slots = slot_count
	slot_diameter = _compute_slot_diameter()
	_build_plate()
	_build_holes()
	queue_redraw()


func _compute_slot_diameter() -> float:
	var usable: float = rect.size.x - SLOT_GAP * float(slot_count + 1)
	var by_width: float = usable / float(slot_count)
	## По высоте ячейка тоже не должна упираться в края плашки — иначе предмет
	## в ней касается нарисованной рамки и читается как вылезший.
	return minf(by_width, rect.size.y * 0.72)


func _build_plate() -> void:
	if _plate != null:
		_plate.queue_free()
		_plate = null
	var tex := Backdrop.load_texture(UIKit.PLATE)
	if tex == null:
		return
	_plate = NinePatchRect.new()
	_plate.texture = tex
	_plate.patch_margin_left = PLATE_PATCH
	_plate.patch_margin_right = PLATE_PATCH
	_plate.patch_margin_top = PLATE_PATCH
	_plate.patch_margin_bottom = PLATE_PATCH
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.position = rect.position
	_plate.size = rect.size
	add_child(_plate)
	move_child(_plate, 0)


func _build_holes() -> void:
	if _holes != null:
		_holes.queue_free()
	_holes = Node2D.new()
	add_child(_holes)
	_holes.draw.connect(_draw_holes)
	_holes.queue_redraw()


## Центр ячейки в координатах родителя лотка. Наружу отдаётся именно центр:
## предметы позиционируются точкой, и знать про поля плашки им незачем.
func slot_center(index: int) -> Vector2:
	var step: float = slot_diameter + SLOT_GAP
	var row_width: float = step * float(slot_count) - SLOT_GAP
	var left: float = rect.position.x + (rect.size.x - row_width) * 0.5
	return Vector2(left + step * float(index) + slot_diameter * 0.5,
		rect.position.y + rect.size.y * 0.5)


## Сколько ячеек свободно — только для отрисовки. Правила лотка живут в
## SortState, и второй счётчик здесь разъехался бы с ними на первой же ошибке.
func set_free_slots(n: int) -> void:
	if _free_slots == n:
		return
	_free_slots = n
	if _holes != null:
		_holes.queue_redraw()


## Без нарисованной плашки лоток всё равно должен быть виден: уровень обязан
## оставаться играбельным без арта.
func _draw() -> void:
	if _plate != null:
		return
	draw_rect(rect, Color(0.32, 0.22, 0.13, 0.82))
	draw_rect(rect, Color(1.0, 0.93, 0.80, 0.28), false, 4.0)


func _draw_holes() -> void:
	var r: float = slot_diameter * SLOT_RADIUS_RATIO
	var warn: bool = _free_slots <= WARN_FREE_SLOTS
	for i in slot_count:
		var c := slot_center(i)
		## Занятые ячейки не подсвечиваем: под предметом рамка всё равно не
		## видна, а тревожный цвет должен читаться на пустом месте.
		var filled: bool = i < slot_count - _free_slots
		var hole := Color(0.42, 0.31, 0.20, 0.34)
		var edge := Color(0.62, 0.46, 0.29, 0.55)
		if warn and not filled:
			edge = WARN_COLOR
		_holes.draw_circle(c, r, hole)
		_holes.draw_arc(c, r, 0.0, TAU, 40, edge, 4.0, true)
