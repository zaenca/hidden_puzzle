extends Node2D
## Экран уровня. Единственное, что он делает, — выбирает игровой модуль по
## режиму из данных и пробрасывает наружу его результат.
##
## Раньше эту роль играл hybrid_level: он был контроллером ОДНОЙ механики
## (пазл → раскрытие → поиск → уборка), и любой другой геймплей пришлось бы
## встраивать в его порядок фаз. Теперь порядок фаз — дело модуля, а граница
## между core и метой одна на всех: LevelContext → модуль → LevelResult.

signal finished(result: LevelResult)
signal abandoned

var context: LevelContext
var module: Node = null


func setup(payload: Dictionary) -> void:
	context = payload.get("context")
	if context == null or context.definition == null:
		push_error("LevelController: пустой LevelContext")
		abandoned.emit()
		return

	var mode := context.definition.mode
	module = GameplayRegistry.create(mode)
	if module == null:
		push_error("LevelController: уровень %s просит режим '%s', которого нет"
			% [context.definition.id, mode])
		abandoned.emit()
		return

	add_child(module)
	## По сигналам, а не по типу: legacy-контроллер уровня не наследует
	## GameplayModule и наследовать не должен — он остаётся ровно тем, чем был.
	if module.has_signal("finished"):
		module.finished.connect(func(result: LevelResult): finished.emit(result))
	if module.has_signal("abandoned"):
		module.abandoned.connect(func(): abandoned.emit())
	if module.has_method("setup"):
		module.setup(context)


## Прохождение без игрока. Экран не знает, как проходится конкретный режим, —
## знает только модуль.
func debug_autoplay() -> void:
	if module != null and module.has_method("debug_autoplay"):
		await module.debug_autoplay()
