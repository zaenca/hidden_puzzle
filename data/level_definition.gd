class_name LevelDefinition
extends Resource
## Полное описание уровня. Уровень не имеет собственного скрипта: двадцать
## уровней — это двадцать таких определений и ноль контроллеров.

@export var id: String = ""
@export var shop_id: String = ""
@export var task_id: String = ""
@export var order: int = 0
@export var difficulty: int = 1
@export var title: String = ""
@export var narrative: PackedStringArray = PackedStringArray()
@export var art: SceneArt

## Каким режимом играется уровень: "sort" — основной core, "legacy" — прежний
## гибрид «пазл → поиск → уборка». Режим выбирает игровой модуль (см.
## GameplayRegistry) и потому обязан жить в данных: иначе новая механика
## означала бы правку маршрутизации, а не новый JSON.
@export var mode: String = "sort"
## Раскладка Sort. Заполнена ровно у уровней с mode == "sort".
@export var sort: SortDefinition = null

@export var puzzle: PuzzleParams
@export var hidden_object: HOConfig
@export var rewards: RewardTable
@export var quest_grants: PackedStringArray = PackedStringArray()

## Показывать ли экран результата. Сюжетный пазл без начислений заканчивается
## плавным уходом в мету: «Уровень пройден. Монеты: +60» посреди завязки
## превращает сцену истории в отчёт о проделанной работе.
@export var show_result: bool = true

## Шаги уборки после сборки кадра: предмет из полосы → область сцены → новое
## состояние комнаты. Пусто — уровень заканчивается на пазле или на поиске.
@export var cleanup: Array[CleanupStep] = []
