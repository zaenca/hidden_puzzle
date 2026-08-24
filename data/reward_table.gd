class_name RewardTable
extends Resource

@export var coins: int = 50
@export var xp: int = 10
@export var replay_factor: float = 0.3  ## повтор пройденного уровня даёт меньше

func coins_for(replay: bool) -> int:
	return int(round(coins * replay_factor)) if replay else coins

func xp_for(replay: bool) -> int:
	return int(round(xp * replay_factor)) if replay else xp
