class_name JigsawParams
extends PuzzleParams
## Части пазла НЕ рисуются художником: геометрия генерируется по cols/rows/seed,
## а текстура берётся с общего фона через UV. Стоимость нового пазла = 0.

@export var cols: int = 3
@export var rows: int = 4
@export var seed: int = 0
@export var tab_ratio: float = 0.20
@export var snap_distance_px: float = 90.0
@export var tray_scale: float = 0.42

func piece_count() -> int:
	return cols * rows
