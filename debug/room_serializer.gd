class_name RoomSerializer
extends RefCounted
## Комната из редактора обратно в JSON — тот самый, который читает ContentParser.
##
## Смысл всей лаборатории в этом файле. Стенд, который показывает красивую
## комнату и ничего после себя не оставляет, — не инструмент, а демонстрация:
## подобранное в нём приходится переписывать в JSON руками, а руками переносят
## неточно и не всё.
##
## Пишется только то, что отличается от значений по умолчанию. Полный дамп всех
## полей был бы «правильнее», но читать и править такой файл потом невозможно,
## а править его будут — редактор задаёт заготовку, а не последнее слово.
##
## Работает только в запуске из исходников: в собранной игре res:// лежит
## внутри PCK и записи не принимает. Это инструмент разработки, а не функция
## игры, и притворяться иначе не стоит.

const ROOMS_DIR := "res://content/rooms/"
const SHOPS_DIR := "res://content/shops/"


static func save_room(def: RoomDefinition, room_id: String) -> String:
	var text := JSON.stringify(to_dict(def, room_id), "  ")
	var path := "%s%s.json" % [ROOMS_DIR, room_id]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("RoomSerializer: не открылся %s (код %d)" % [path, FileAccess.get_open_error()])
		return ""
	f.store_string(text + "\n")
	f.close()
	return path


## Прицепить комнату к локации.
##
## Правится ТЕКСТ файла, а не разобранный словарь: в магазинах живут поля
## `_note`, порядок ключей и форматирование, а перезапись через JSON.stringify
## снесла бы всё это ради одной строки. Ничего не удаляется — `background`
## остаётся на месте, комната просто главнее; убрать строку `"room"` значит
## вернуть локацию к прежней картинке.
static func attach_to_shop(shop_id: String, room_id: String) -> bool:
	var path := "%s%s.json" % [SHOPS_DIR, shop_id]
	if not FileAccess.file_exists(path):
		push_error("RoomSerializer: нет файла локации %s" % path)
		return false
	var text := FileAccess.get_file_as_string(path)
	var line := '  "room": "%s",' % room_id

	var re := RegEx.new()
	re.compile('(?m)^\\s*"room"\\s*:\\s*"[^"]*"\\s*,?\\s*$')
	var found := re.search(text)
	if found != null:
		text = text.substr(0, found.get_start()) + line + text.substr(found.get_end())
	else:
		## Вставляем сразу после "id" — там же, где поле стоит в остальных
		## локациях, чтобы файл не начал отличаться от соседних.
		var id_re := RegEx.new()
		id_re.compile('(?m)^\\s*"id"\\s*:\\s*"[^"]*"\\s*,\\s*$')
		var id_line := id_re.search(text)
		if id_line == null:
			push_error("RoomSerializer: в %s не нашлось строки \"id\"" % path)
			return false
		text = text.substr(0, id_line.get_end()) + "\n" + line + text.substr(id_line.get_end())

	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("RoomSerializer: не открылся %s" % path)
		return false
	f.store_string(text)
	f.close()
	return true


## --- комната в словарь ------------------------------------------------------

static func to_dict(def: RoomDefinition, room_id: String) -> Dictionary:
	var d := {
		"_note": "Собрано в лаборатории комнат (⚙ → «Лаборатория комнат»). Файл обычный: правится руками наравне с остальными и при следующем сохранении из стенда будет перезаписан.",
		"id": room_id,
		"room_template": def.template_id,
		"seed": def.seed,
	}
	var surfaces := {}
	for surface_id in RoomGeometry.SURFACES:
		var cfg: RoomSurfaceConfig = def.surfaces.get(surface_id)
		if cfg == null:
			continue
		surfaces[surface_id] = _surface(cfg)
	d["surfaces"] = surfaces

	var elements := []
	for el in def.elements:
		elements.append(_element(el))
	if not elements.is_empty():
		d["elements"] = elements

	var decals := []
	for el in def.decals:
		decals.append(_element(el))
	if not decals.is_empty():
		d["decals"] = decals

	var trims := _trims(def.trims)
	if not trims.is_empty():
		d["trims"] = trims
	if def.tint != Color.WHITE:
		d["tint"] = "#" + def.tint.to_html(false)
	if def.vignette > 0.0:
		d["vignette"] = {
			"strength": snappedf(def.vignette, 0.01),
			"color": "#" + def.vignette_color.to_html(false),
		}
	if not def.scatter.is_empty():
		d["scatter"] = def.scatter
	if def.debug_panel:
		d["debug_panel"] = true
	return d


static func _surface(cfg: RoomSurfaceConfig) -> Dictionary:
	var d := {}
	if not cfg.material_id.is_empty():
		d["material"] = cfg.material_id
	if not cfg.texture_path.is_empty():
		d["texture"] = cfg.texture_path
	if not cfg.generator.is_empty():
		d["generator"] = cfg.generator
	if cfg.tile_size != Vector2.ZERO:
		d["tile_size"] = _vec(cfg.tile_size)
	if cfg.repeat != Vector2.ZERO:
		d["repeat"] = _vec(cfg.repeat)
	if not is_equal_approx(cfg.tile_scale, 1.0):
		d["tile_scale"] = snappedf(cfg.tile_scale, 0.01)
	if cfg.tint != Color.WHITE:
		d["tint"] = "#" + cfg.tint.to_html(false)
	if cfg.uv_offset != Vector2.ZERO:
		d["uv_offset"] = _vec(cfg.uv_offset)
	return d


static func _element(el: RoomElement) -> Dictionary:
	var d := {}
	if not el.id.is_empty():
		d["id"] = el.id
	d["type"] = el.type
	d["surface"] = el.surface
	if el.stands():
		d["placement"] = RoomElement.PLACE_STAND
		d["anchor"] = _vec(el.anchor)
		d["size"] = _vec(el.size)
	else:
		d["rect"] = [
			snappedf(el.rect.position.x, 0.001), snappedf(el.rect.position.y, 0.001),
			snappedf(el.rect.size.x, 0.001), snappedf(el.rect.size.y, 0.001)]
	if not el.material_id.is_empty():
		d["material"] = el.material_id
	if not el.texture_path.is_empty():
		d["texture"] = el.texture_path
	if not el.generator.is_empty():
		d["generator"] = el.generator
	if el.tint != Color.WHITE:
		d["tint"] = "#" + el.tint.to_html(false)
	if not is_equal_approx(el.opacity, 1.0):
		d["opacity"] = snappedf(el.opacity, 0.01)
	if absf(el.rotation_deg) > 0.01:
		d["rotation"] = snappedf(el.rotation_deg, 0.1)
	if el.flip_h:
		d["flip_h"] = true
	if el.flip_v:
		d["flip_v"] = true
	if el.shadow > 0.0:
		d["shadow"] = snappedf(el.shadow, 0.001)
	if el.inset > 0.0:
		d["inset"] = snappedf(el.inset, 0.01)
	if el.frame > 0.0:
		d["frame"] = snappedf(el.frame, 0.001)
	if not el.frame_material_id.is_empty():
		d["frame_material"] = el.frame_material_id
	if not el.visible_if_flag.is_empty():
		d["visible_if_flag"] = el.visible_if_flag
	if not el.hidden_if_flag.is_empty():
		d["hidden_if_flag"] = el.hidden_if_flag
	if not el.slot_id.is_empty():
		d["slot"] = el.slot_id
		d["slot_state"] = el.slot_state
	if el.placed_in_editor:
		d["placed"] = true
	return d


static func _trims(t: RoomTrims) -> Dictionary:
	if t == null:
		return {}
	var d := {}
	if t.has_corner():
		d["corner_shadow"] = {
			"width": snappedf(t.corner_width, 0.01),
			"strength": snappedf(t.corner_strength, 0.01)}
	if t.has_baseboard():
		d["baseboard"] = {
			"height": snappedf(t.baseboard_height, 0.001),
			"material": t.baseboard_material_id,
			"tint": "#" + t.baseboard_tint.to_html(false)}
	if t.has_cornice():
		d["cornice"] = {
			"height": snappedf(t.cornice_height, 0.001),
			"material": t.cornice_material_id,
			"tint": "#" + t.cornice_tint.to_html(false)}
	if t.has_contact():
		d["contact_shadow"] = {
			"size": snappedf(t.contact_size, 0.01),
			"strength": snappedf(t.contact_strength, 0.01)}
	return d


static func _vec(v: Vector2) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001)]
