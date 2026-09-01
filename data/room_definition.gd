class_name RoomDefinition
extends Resource
## Одна комната целиком: какая геометрия, чем покрыты поверхности, что на них
## стоит и что на них испачкано.
##
## Смысл всей системы — чтобы новая комната стоила один JSON, а не нарисованный
## целиком фон. Поэтому здесь нет ни одного поля, которое нельзя заполнить, не
## открывая графический редактор.

@export var id: String = ""
@export var template_id: String = "medium_room"
## Зерно для процедурных слоёв. Одно и то же зерно обязано давать один и тот же
## кадр: комната, которая после перезагрузки выглядит иначе, — это не
## разнообразие, а баг. В сейв зерно не пишется, оно часть контента.
@export var seed: int = 0

@export var surfaces: Dictionary = {}          ## id -> RoomSurfaceConfig
@export var elements: Array[RoomElement] = []  ## окна, двери, ниши, полки
@export var decals: Array[RoomElement] = []    ## трещины, пятна, паутина
@export var trims: RoomTrims = null

## Общий тон комнаты и виньетка — самый дешёвый способ отличить холодную
## кладовую от тёплой пекарни, не меняя ни одного материала.
@export var tint: Color = Color.WHITE
@export var vignette: float = 0.0
@export var vignette_color: Color = Color(0, 0, 0, 1)

## Процедурный слой поверх явной конфигурации: правила «разбросай N пятен вот
## в этой области». Именно поверх, а не вместо: комната без scatter обязана
## собираться полностью, случайность — добавка, а не основа.
@export var scatter: Array = []

## Показывать ли в debug-сборке переключатель материалов. Живёт в данных, а не
## в коде сцены: лабораторная комната этим и отличается от игровой.
@export var debug_panel: bool = false


func surface(surface_id: String) -> RoomSurfaceConfig:
	return surfaces.get(surface_id)
