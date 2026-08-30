class_name ShopSlotDefinition
extends Resource
## Один изменяемый объект магазина (мусор, вывеска, дверь...).
## rect нормализован относительно визуальной области магазина.

@export var id: String = ""
@export var rect: Rect2 = Rect2(0, 0, 0.2, 0.2)
@export var states: Array[ShopSlotState] = []
@export var default_state: String = ""
@export var interactions: Array[SlotInteraction] = []   ## реакции на тап игрока
## Когда рисовать рамку «сюда можно нажать»:
##   auto   — когда с объектом прямо сейчас есть что сделать (по умолчанию);
##   always — всегда: объект кликабелен, но прогресс не двигает, и без рамки
##            неотличим от нарисованного фона;
##   never  — никогда: объект нужно найти глазами, рамка выдала бы его сразу.
@export var highlight: String = "auto"

func state(state_id: String) -> ShopSlotState:
	for s in states:
		if s.id == state_id:
			return s
	return null

func has_state(state_id: String) -> bool:
	return state(state_id) != null

func is_interactive() -> bool:
	return not interactions.is_empty()

## Есть ли в этом состоянии правило, двигающее прогресс — по нему сцена решает,
## подсвечивать слот игроку или нет.
func has_progress_in(state_id: String, flags: Dictionary) -> bool:
	for i in interactions:
		if not i.is_progress():
			continue
		if not i.state.is_empty() and i.state != state_id:
			continue
		if not i.once_flag.is_empty() and bool(flags.get(i.once_flag, false)):
			continue
		return true
	return false

## Рамку рисуем по режиму из данных, а не по одному лишь наличию дела: сцена
## поиска обязана уметь молчать про объект, который игрок ещё не нашёл.
func highlight_on(state_id: String, flags: Dictionary) -> bool:
	match highlight:
		"always":
			return true
		"never":
			return false
		_:
			return has_progress_in(state_id, flags)


## Объект, который игрок должен найти сам. По таким же работает лампочка-подсказка.
func is_searchable() -> bool:
	return highlight == "never"
