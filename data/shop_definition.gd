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
## Процедурная комната вместо готового фона. Заполнено — интерьер собирается
## RoomAssembler'ом по `content/rooms/<id>.json`, и background_path не нужен.
## Пусто — прежний путь: картинка или градиент. Именно поэтому переход на
## процедурные комнаты идёт по одной локации за раз, а не разом.
@export var room_id: String = ""
@export var visual_scene: PackedScene = null   ## финальный арт; пока null
@export var rooms: Array = []                  ## [{id, title}]
@export var slots: Array[ShopSlotDefinition] = []
## Вход внутрь: {label, requires_flag, locked_text, text, open_shop}. С
## open_shop кнопка ведёт в другую локацию, без него — просто показывает text.
@export var enter: Dictionary = {}
## Куда ведёт кнопка «назад»: {label, shop_id}. Пусто — на карту района.
## Нужно вложенным локациям (кладовая внутри пекарни): выкидывать из них сразу
## на площадь значит заставлять игрока заходить в пекарню заново.
@export var back: Dictionary = {}
## Чем обставлен первый приход игрока: {intro, flag}. Пока флаг не поднят, вход
## ведёт в заставку, а не сразу в локацию. Карта об этом не знает.
@export var first_visit: Dictionary = {}
## Полоска ячеек «что здесь надо собрать»: {title, items, done_flag}. Игрок
## должен видеть, сколько ещё искать, — список требований в задаче это говорит
## текстом, а ячейки показывают. Пусто — полоски нет.
@export var collection: Dictionary = {}

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
