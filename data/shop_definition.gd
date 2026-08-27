class_name ShopDefinition
extends Resource
## Шаблонное описание магазина. Один ShopScene.tscn обслуживает все магазины —
## различия только в данных. Копий сцены под визуальные состояния нет:
## состояния живут в слотах.

@export var id: String = ""
@export var display_name: String = ""
@export var palette: String = "bakery"
@export var map_rect: Rect2 = Rect2()
## Фон локации. Пока пусто — сцена рисует градиент по palette, поэтому магазин
## без арта остаётся играбельным. rect'ы слотов нормализованы именно к этой
## картинке, а не к экрану.
@export var background_path: String = ""
@export var visual_scene: PackedScene = null   ## финальный арт; пока null
@export var rooms: Array = []                  ## [{id, title}]
@export var slots: Array[ShopSlotDefinition] = []
## Вход внутрь: {label, requires_flag, locked_text, text}. Пока это заглушка
## под комнату — сцена торгового зала появится отдельным этапом.
@export var enter: Dictionary = {}
## Чем обставлен первый приход игрока: {intro, flag}. Пока флаг не поднят, вход
## ведёт в заставку, а не сразу в локацию. Карта об этом не знает.
@export var first_visit: Dictionary = {}

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
