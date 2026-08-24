class_name LevelDefinition
extends Resource
## Полное описание гибридного уровня. Уровень не имеет собственного скрипта:
## двадцать уровней — это двадцать таких определений и ноль контроллеров.

@export var id: String = ""
@export var shop_id: String = ""
@export var task_id: String = ""
@export var order: int = 0
@export var difficulty: int = 1
@export var title: String = ""
@export var narrative: PackedStringArray = PackedStringArray()
@export var art: SceneArt
@export var puzzle: PuzzleParams
@export var hidden_object: HOConfig
@export var rewards: RewardTable
@export var quest_grants: PackedStringArray = PackedStringArray()
