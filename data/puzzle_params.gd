class_name PuzzleParams
extends Resource
## Базовые параметры puzzle-модуля. Наследники описывают конкретную механику.
## module_id — ключ в PuzzleRegistry. Подключение screws/bubbles позже = новый
## наследник + новая сцена + одна строка в реестре; core-код не меняется.

@export var module_id: String = "jigsaw"
