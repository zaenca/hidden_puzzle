class_name PuzzleModule
extends Node2D
## Контракт puzzle-модуля. Замена jigsaw на screws/bubbles не должна трогать
## HybridLevelController — он общается только через этот интерфейс.

signal solved
signal progress_changed(done: int, total: int)

func setup(_params: PuzzleParams, _texture: Texture2D, _image_rect: Rect2, _tray_rect: Rect2) -> void:
	pass

func begin() -> void:
	pass

## Универсальный бустер: в jigsaw ставит одну часть, в hidden object подсветит
## предмет. Возвращает true, если бустер реально что-то сделал.
func apply_booster(_booster_id: String) -> bool:
	return false

func progress() -> Vector2i:
	return Vector2i(0, 0)

## Плавное исчезновение швов и слоя целиком — это и есть «бесшовное раскрытие».
func fade_seams(_duration: float) -> void:
	pass

func fade_out(_duration: float) -> void:
	pass

## Для debug-меню и headless-тестов.
func force_solve() -> void:
	pass
