class_name ItemDefinition
extends Resource
## Описание предмета. Для placeholder-арта цвет + форма заменяют иконку:
## тот же цвет и форма запекаются в фон уровня и рисуются в панели поиска,
## поэтому предмет реально можно найти глазами.

enum Kind { NORMAL, THEMED, QUEST, MATERIAL }

@export var id: String = ""
@export var display_name: String = ""
@export var kind: Kind = Kind.NORMAL
@export var color: Color = Color.WHITE
@export var shape: String = "rect"  ## rect | circle | triangle | cross
@export var icon: Texture2D = null  ## финальный арт; пока null → placeholder

func is_quest() -> bool:
	return kind == Kind.QUEST
