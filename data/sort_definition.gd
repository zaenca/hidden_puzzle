class_name SortDefinition
extends Resource
## Полное описание Sort-уровня: что лежит на поле, из чего собираются тройки,
## сколько ячеек в лотке.
##
## Модуль не знает ни одного id уровня — весь уровень это данные, поэтому
## следующие Sort-уровни добавляются JSON-файлом, а не новым скриптом.

@export var tray_size: int = 7
## Сколько предметов одной категории закрывают группу. Тройка — не константа
## движка, а правило уровня: поздние уровни могут требовать другое.
@export var group_size: int = 3
## Раскладка обязана быть воспроизводимой: тот же seed — тот же уровень, иначе
## «Заново» после проигрыша выдавал бы другую задачу.
@export var seed: int = 0
@export var categories: Array[SortCategory] = []
@export var items: Array[SortItemInstance] = []
## Обучение, которое сопровождает уровень (id файла в content/tutorial).
## Пусто — уровень идёт без объяснений.
@export var tutorial_id: String = ""

## Закрытые участки поля: ящики и полки, внутрь которых сначала нет доступа.
## Пусто — уровень без зон, и так проходят первые три.
@export var zones: Array[SortZone] = []

## Полный лоток без собранной группы = проигрыш. Выключается уровнями, где
## переполнение решается иначе (расширение лотка, откат хода).
@export var fail_on_full_tray: bool = true


func category(category_id: String) -> SortCategory:
	for c in categories:
		if c.id == category_id:
			return c
	return null


func has_category(category_id: String) -> bool:
	return category(category_id) != null


func item(instance_id: String) -> SortItemInstance:
	for i in items:
		if i.id == instance_id:
			return i
	return null


func zone(zone_id: String) -> SortZone:
	for z in zones:
		if z.id == zone_id:
			return z
	return null


## В какой зоне лежит экземпляр. null — предмет лежит на открытом поле.
## Обратный поиск, а не поле в самом экземпляре: принадлежность зоне — это про
## зону, и хранить её в двух местах значит однажды их разойтись.
func zone_of(instance_id: String) -> SortZone:
	for z in zones:
		if z.items.has(instance_id):
			return z
	return null


func category_color(category_id: String) -> Color:
	var c := category(category_id)
	return c.color if c != null else Color(0.85, 0.85, 0.85)


## Сколько предметов в каждой категории. Нужно и валидатору («группа делится на
## тройки»), и солверу.
func category_counts() -> Dictionary:
	var out := {}
	for i in items:
		out[i.category] = int(out.get(i.category, 0)) + 1
	return out
