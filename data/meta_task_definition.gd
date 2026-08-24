class_name MetaTaskDefinition
extends Resource
## Задача восстановления. Связывает цепочку core-уровней с одним meta action.

@export var id: String = ""
@export var shop_id: String = ""
@export var room_id: String = ""
@export var location: String = "shop"   ## shop | map — куда вернуть игрока
@export var title: String = ""
@export var hint: String = ""
@export var unlock: Array[Requirement] = []
@export var level_ids: PackedStringArray = PackedStringArray()
@export var action_id: String = ""
@export var hotspot: String = ""        ## slot_id, к которому летит камера
