class_name LevelShot
extends RefCounted
## Снимок уровня из настоящего запуска.
##
##   godot --path . -- --level-shot=bakery_01
##   godot --path . -- --level-shot=bakery_01 --shot-picks=3
##
## Зачем отдельный инструмент. Раскладку Sort нельзя принять автопрогоном: он
## доказывает, что уровень проходим и что ни один предмет не заехал под HUD, но
## «выглядит ли завал завалом» и «не сливаются ли предметы с фасадом» решает
## только кадр. Тот же приём, что у RoomShot, и по той же причине: headless не
## годится — без настоящего OpenGL в файл попадёт пустота.
##
## `--shot-picks=N` снимает кадр после N тапов: лоток с предметами и лоток
## пустой — разные картинки, и проверять надо обе.

const OUT_DIR := "res://"


func run(tree: SceneTree, level_id: String, picks: int = 0) -> void:
	await tree.process_frame
	Game.play_level(level_id)
	for _i in 20:
		await tree.process_frame

	var suffix := ""
	if picks > 0:
		suffix = "_picks%d" % picks
		await _play(tree, picks)

	await RenderingServer.frame_post_draw
	var image := tree.root.get_texture().get_image()
	var path := "%slevel_shot_%s%s.png" % [OUT_DIR, level_id, suffix]
	var err := image.save_png(path)
	if err != OK:
		push_error("LevelShot: не сохранилось в %s (код %d)" % [path, err])
	else:
		print("LevelShot: %s (%dx%d)" % [path, image.get_width(), image.get_height()])
	tree.quit(0 if err == OK else 1)


## Первые N ходов известного решения — чтобы на кадр попал заполненный лоток.
## Путь берётся у солвера, а не пишется здесь: снимок обязан показывать то же
## самое, что увидит игрок, который играет правильно.
func _play(tree: SceneTree, picks: int) -> void:
	var screen: Node = Game.current()
	var module: Node = screen.module if screen != null and ("module" in screen) else null
	if module == null or not ("sort" in module):
		return
	var plan := SortSolver.solve(module.sort)
	if not bool(plan["solved"]):
		return
	var path: PackedStringArray = plan["path"]
	for i in mini(picks, path.size()):
		module._on_pick(String(path[i]))
		for _f in 12:
			await tree.process_frame
