class_name ShopDefinition
extends Resource
## Шаблонное описание магазина. Один ShopScene.tscn обслуживает все магазины —
## различия только в данных. Копий сцены под визуальные состояния нет:
## состояния живут в слотах.

@export var id: String = ""
@export var display_name: String = ""
@export var palette: String = "bakery"
@export var map_rect: Rect2 = Rect2()
@export var visual_scene: PackedScene = null   ## финальный арт; пока null
@export var rooms: Array = []                  ## [{id, title}]
@export var slots: Array[ShopSlotDefinition] = []

func slot(slot_id: String) -> ShopSlotDefinition:
	for s in slots:
		if s.id == slot_id:
			return s
	return null

func default_states() -> Dictionary:
	var d := {}
	for s in slots:
		d[s.id] = s.default_state
	return d
