class_name RoomShot
extends RefCounted
## Снимок процедурной комнаты из настоящего запуска.
##
##   godot --path . -- --room-shot=room_lab
##   godot --path . -- --room-shot=room_lab --room-template=narrow_room
##
## Зачем отдельный инструмент. Геометрию комнаты нельзя принять по автопрогону:
## он проверяет логику, а тут всё решает кадр — сошёлся ли угол, не разъехалась
## ли плитка у горизонта, не уехало ли окно за край стены. Подбор шаблона это
## десяток итераций «поменял число — посмотрел», и делать их руками через меню
## значит не делать их вовсе.
##
## Headless не годится: без настоящего OpenGL шейдеры не выполняются, и в файл
## попадёт пустой кадр.

const OUT_DIR := "res://"


## template_id — необязательное переопределение геометрии: так все шаблоны
## снимаются одним прогоном, без правки контента под каждый.
func run(tree: SceneTree, shop_id: String, template_id: String = "") -> void:
	await tree.process_frame
	var suffix := ""
	if not template_id.is_empty():
		var shop: ShopDefinition = ContentDB.shop(shop_id)
		var room := ContentDB.room(shop.room_id) if shop != null else null
		if room != null:
			room.template_id = template_id
			suffix = "_" + template_id
	Game.open_shop(shop_id)
	## Ждём кадрами, а не таймером: комната собирается за один вызов, но
	## заглушки текстур рисуются по пикселям, и первый кадр может уйти раньше,
	## чем они готовы.
	for _i in 30:
		await tree.process_frame
	await RenderingServer.frame_post_draw

	var image := tree.root.get_texture().get_image()
	var path := "%sroom_shot_%s%s.png" % [OUT_DIR, shop_id, suffix]
	var err := image.save_png(path)
	if err != OK:
		push_error("RoomShot: не сохранилось в %s (код %d)" % [path, err])
	else:
		print("RoomShot: %s (%dx%d)" % [path, image.get_width(), image.get_height()])
	tree.quit(0 if err == OK else 1)
