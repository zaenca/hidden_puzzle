class_name HOConfig
extends Resource
## Настройка hidden-object фазы уровня.

@export var targets: Array[HOTarget] = []
@export var required_normal: int = 4      ## сколько обычных целей обязательно
@export var time_limit_sec: float = 0.0   ## 0 = без таймера (решение по слайсу)
@export var miss_penalty_sec: float = 0.0
@export var allow_zoom: bool = true

func quest_targets() -> Array[HOTarget]:
	var out: Array[HOTarget] = []
	for t in targets:
		if t.is_quest():
			out.append(t)
	return out

func normal_target_count() -> int:
	var n := 0
	for t in targets:
		if not t.is_quest():
			n += 1
	return n
