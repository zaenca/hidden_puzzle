extends Node
## Единый источник времени. Всё, что связано с cooldown, спрашивает время
## только здесь — это даёт одну точку для отладочной перемотки и для будущей
## замены на серверное время.

var debug_offset_sec: int = 0

func now() -> int:
	return int(Time.get_unix_time_from_system()) + debug_offset_sec

## Отладочная перемотка (debug-меню и headless-тесты).
func fast_forward(seconds: int) -> void:
	debug_offset_sec += seconds

func format_duration(seconds: int) -> String:
	var s := maxi(0, seconds)
	var h := s / 3600
	var m := (s % 3600) / 60
	var sec := s % 60
	if h > 0:
		return "%d:%02d:%02d" % [h, m, sec]
	return "%02d:%02d" % [m, sec]
