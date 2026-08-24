class_name MetaEffect
extends Resource
## Что происходит с миром, когда meta action завершён.
## Эффекты — единственный способ изменить мету. Уровень их не создаёт.

enum Kind {
	SET_VISUAL_STATE,  ## слот магазина переходит в новое состояние
	SET_SHOP_STATE,    ## состояние магазина целиком
	GRANT,             ## выдать валюту/предмет
	CONSUME,           ## списать предмет
	UNLOCK_TASK,       ## открыть задачу
	SET_FLAG,          ## поставить флаг прогресса
	NARRATIVE,         ## показать реплику
}

@export var kind: Kind = Kind.GRANT
@export var shop_id: String = ""
@export var slot_id: String = ""
@export var state_id: String = ""
@export var task_id: String = ""
@export var id: String = ""
@export var amount: int = 1
@export var text: String = ""
