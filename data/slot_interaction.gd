class_name SlotInteraction
extends Resource
## Реакция слота магазина на тап. Правило point-and-click целиком лежит в
## данных: сцена сообщает только «тапнули по слоту, в руке предмет X»,
## а что из этого следует — решает контент.
##
## Порядок правил в JSON значим: срабатывает первое подошедшее.

@export var state: String = ""        ## при каком состоянии слота ("" — при любом)
@export var use_item: String = ""     ## что выбрано в сумке ("" — пустая рука)
@export var consume: bool = false     ## израсходовать use_item
@export var grant_item: String = ""   ## что выдать в сумку
@export var set_state: String = ""    ## в какое состояние перевести слот
@export var set_flag: String = ""     ## флаг мира
@export var once_flag: String = ""    ## правило одноразовое; флаг ставится сам
@export var text: String = ""


## Пустой use_item намеренно требует пустой руки: тап предметом, который здесь
## не при чём, не должен проваливаться в правило «просто осмотреть».
func matches(current_state: String, selected_item: String, flags: Dictionary) -> bool:
	if not state.is_empty() and state != current_state:
		return false
	if not once_flag.is_empty() and bool(flags.get(once_flag, false)):
		return false
	return use_item == selected_item


## Двигает ли правило мир вперёд. Осмотр и подсказки — нет, и подсвечивать
## слот ради них не нужно.
func is_progress() -> bool:
	return not set_state.is_empty() or not grant_item.is_empty()
