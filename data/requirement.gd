class_name Requirement
extends Resource
## Условие, которое проверяет мета-слой (доступность задачи, запуск meta action).
## Tagged union вместо иерархии наследников — для M1 это меньше кода при той же
## data-driven семантике. Разделение на подклассы — кандидат на M4+.

enum Kind { ITEM, TASK, LEVEL, FLAG }

@export var kind: Kind = Kind.ITEM
@export var id: String = ""        ## item_id / task_id / level_id / flag
@export var amount: int = 1        ## для ITEM
@export var state: String = ""     ## для TASK: ожидаемое состояние

func describe() -> String:
	match kind:
		Kind.ITEM:
			return "%s x%d" % [id, amount]
		Kind.TASK:
			return "задача %s = %s" % [id, state]
		Kind.LEVEL:
			return "уровень %s" % id
		Kind.FLAG:
			return "флаг %s" % id
	return id
