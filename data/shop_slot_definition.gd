class_name ShopSlotDefinition
extends Resource
## Один изменяемый объект магазина (мусор, вывеска, дверь...).
## rect нормализован относительно визуальной области магазина.

@export var id: String = ""
@export var rect: Rect2 = Rect2(0, 0, 0.2, 0.2)
@export var states: Array[ShopSlotState] = []
@export var default_state: String = ""

func state(state_id: String) -> ShopSlotState:
	for s in states:
		if s.id == state_id:
			return s
	return null

func has_state(state_id: String) -> bool:
	return state(state_id) != null
