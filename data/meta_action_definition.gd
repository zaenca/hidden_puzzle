class_name MetaActionDefinition
extends Resource
## Мета-действие: применение найденного в мире.
## duration_sec > 0 превращает его в cooldown-действие.

@export var id: String = ""
@export var title: String = ""
@export var description: String = ""
@export var button_label: String = "Применить"
@export var requirements: Array[Requirement] = []
@export var costs: Array[Cost] = []
## Применяется само, как только выполнены условия. Для шагов, где выбора у
## игрока нет: кнопка «применить», нажатие которой ничего не решает, — это не
## решение, а лишний тап между ним и следующей сценой.
@export var auto_apply: bool = false
@export var duration_sec: int = 0
@export var reduce_per_level_sec: int = 0   ## сокращение за каждый core level
@export var speedup_hard_cost: int = 0      ## mock hard currency
@export var ad_reduce_sec: int = 0          ## mock rewarded ad
@export var effects: Array[MetaEffect] = []

func is_instant() -> bool:
	return duration_sec <= 0
