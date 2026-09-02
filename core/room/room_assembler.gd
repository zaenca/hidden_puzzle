class_name RoomAssembler
extends Node2D
## Сборщик интерьера: из описания комнаты делает кадр.
##
## Задача системы — чтобы новая локация стоила один JSON, а не нарисованный
## целиком фон. Поэтому здесь нет ни одной ветки под конкретную комнату: всё,
## что различает кладовую и пекарню, лежит в RoomDefinition.
##
## Про мету сборщик не знает ничего. Флаги и состояния слотов ему ПЕРЕДАЮТ —
## сам он ни к MetaService, ни к сейву не обращается, поэтому его одинаково
## можно ставить и в локацию, и внутрь уровня.
##
## Одна поверхность — один Polygon2D. Не полторы сотни спрайтов на плитки:
## повтор делает шейдер, а не дерево нод. На весь прототип комнаты уходит
## порядка полутора десятков объектов отрисовки.

const SURFACE_SHADER_PATH := "res://core/room/room_surface.gdshader"
const DECAL_SHADER_PATH := "res://core/room/room_decal.gdshader"

## Комната пересобрана на другой геометрии. Слушает локация: области слотов
## привязаны к элементам комнаты, а те после смены шаблона стоят в другом месте.
signal rebuilt

var geom: RoomGeometry = null

var _def: RoomDefinition = null
var _tpl: RoomTemplate = null
var _screen: Vector2 = Vector2(1080, 1920)
var _materials: Dictionary = {}
var _surface_nodes: Dictionary = {}    ## surface id -> Polygon2D
var _surface_cfg: Dictionary = {}      ## surface id -> RoomSurfaceConfig
var _element_nodes: Dictionary = {}    ## element id -> Array[Node2D]
var _element_rects: Dictionary = {}    ## element id -> Rect2 на экране
## element id -> PackedVector2Array, сам четырёхугольник. Rect2 — только его
## габарит, а перекошен элемент или нет, видно лишь по четырём точкам.
var _element_quads: Dictionary = {}
var _elements: Dictionary = {}         ## element id -> RoomElement
var _surface_shader: Shader = null
var _decal_shader: Shader = null


## materials — библиотека id → RoomMaterial. Передаётся снаружи, а не берётся
## из ContentDB: так сборщик остаётся чистой отрисовкой и его можно кормить
## подменённым материалом из debug-панели, не трогая контент.
func build(def: RoomDefinition, tpl: RoomTemplate, materials: Dictionary,
		screen: Vector2) -> void:
	_def = def
	_tpl = tpl
	_screen = screen
	_materials = materials
	_surface_shader = load(SURFACE_SHADER_PATH)
	_decal_shader = load(DECAL_SHADER_PATH)
	geom = RoomGeometry.build(tpl, screen)

	for child in get_children():
		remove_child(child)
		child.queue_free()
	_surface_cfg.clear()
	_surface_nodes.clear()
	_element_nodes.clear()
	_element_rects.clear()
	_element_quads.clear()
	_elements.clear()

	_build_surfaces()
	_build_contact_shadow()
	_build_elements(def.decals)
	_build_scatter(screen)
	_build_baseboard()
	_build_corner_shadow()
	_build_elements(def.elements)
	_build_vignette(screen)

	modulate = def.tint
	rebuilt.emit()


## Пересобрать ту же комнату на другой геометрии. Нужно debug-стенду: шаблон
## выбирают глазами, а не по числам, и перезапуск игры на каждую попытку
## означает, что выбирать никто не будет.
func rebuild_with_template(tpl: RoomTemplate) -> void:
	if tpl == null:
		return
	build(_def, tpl, _materials, _screen)


func template() -> RoomTemplate:
	return _tpl


## Пересчитать видимость по состоянию мира. Дешёвая операция: ноды не
## пересоздаются, меняется только `visible`. Именно поэтому дверь может
## открыться прямо в кадре, без пересборки комнаты.
func apply_state(flags: Dictionary, slot_states: Dictionary) -> void:
	for id in _element_nodes:
		var el: RoomElement = _elements.get(id)
		if el == null:
			continue
		var on := el.is_visible(flags, slot_states)
		for node in _element_nodes[id]:
			node.visible = on


## Экранный прямоугольник элемента. Нужен локации: дверь, нарисованную
## комнатой, игрок должен нажимать ровно там, где она нарисована, — иначе
## хитбокс приходится подгонять руками и он разъезжается при смене шаблона.
func element_rect(id: String) -> Rect2:
	return _element_rects.get(id, Rect2())


func has_element(id: String) -> bool:
	return _element_rects.has(id)


func element(id: String) -> RoomElement:
	return _elements.get(id)


## --- редактор: поставить, подвинуть, убрать ----------------------------------
##
## Элементы кладутся В САМО ОПИСАНИЕ комнаты, а не в отдельный список сцены.
## Поэтому поставленный шкаф переживает смену шаблона геометрии, попадает в
## сохранение и ничем не отличается от написанного руками в JSON: редактор
## правит контент, а не рисует поверх него.

## Куда именно попал предмет и во что это превращается. Решает комната, а не
## палитра: окно уезжает на стену, шкаф встаёт на пол, а промах по кадру —
## это промах, а не «поставим куда-нибудь».
func place_material(material_id: String, world_pos: Vector2,
		move_id: String = "") -> String:
	var mat: RoomMaterial = _materials.get(material_id)
	if mat == null:
		return ""
	var surface_id := geom.surface_at_point(world_pos)
	if surface_id.is_empty():
		return ""

	var el: RoomElement = _elements.get(move_id) if not move_id.is_empty() else null
	var moving := el != null
	if not moving:
		el = RoomElement.new()
		el.id = _free_element_id(material_id)
		el.material_id = material_id
		el.placed_in_editor = true
		el.type = mat.category

	var item_size := mat.size if mat.size != Vector2.ZERO else Vector2(1.0, 1.0)
	if surface_id == RoomGeometry.SURFACE_FLOOR:
		## Мебель на полу: якорь — основание, размер в единицах комнаты.
		el.placement = RoomElement.PLACE_STAND
		el.surface = RoomGeometry.SURFACE_FLOOR
		el.anchor = geom.screen_to_uv(RoomGeometry.SURFACE_FLOOR, world_pos)
		el.size = item_size
	else:
		## Окно и дверь — прямоугольник на поверхности. Размер тот же, в
		## единицах комнаты: окно 1.2 м остаётся окном 1.2 м на любой стене,
		## а доля поверхности растянула бы его вместе с ней.
		var extent := geom.extent(surface_id)
		var uv := geom.screen_to_uv(surface_id, world_pos)
		var w: float = item_size.x / maxf(0.01, extent.x)
		var h: float = item_size.y / maxf(0.01, extent.y)
		el.placement = RoomElement.PLACE_SURFACE
		el.surface = surface_id
		el.rect = Rect2(uv.x - w * 0.5, uv.y - h * 0.5, w, h)
		el.layer = RoomElement.LAYER_STRUCTURE

	if moving:
		_free_element_nodes(el.id)
	else:
		_def.elements.append(el)
	_build_element(el)
	return el.id


## Что стоит под точкой экрана. Нужно перетаскиванию уже поставленного: чтобы
## подвинуть шкаф, его сперва надо опознать.
func element_at(world_pos: Vector2) -> String:
	var best := ""
	var best_layer := -9999
	for id in _element_quads:
		var el: RoomElement = _elements.get(id)
		if el == null or not el.placed_in_editor:
			continue
		if not Geometry2D.is_point_in_polygon(world_pos, _element_quads[id]):
			continue
		var layer: int = _stand_layer(el) if el.stands() else el.layer
		if layer >= best_layer:
			best_layer = layer
			best = id
	return best


func remove_element(id: String) -> void:
	var el: RoomElement = _elements.get(id)
	if el == null:
		return
	_free_element_nodes(id)
	_def.elements.erase(el)
	_elements.erase(id)


## Последний поставленный в редакторе — то, что уберёт «отменить».
func last_placed_id() -> String:
	for i in range(_def.elements.size() - 1, -1, -1):
		var el: RoomElement = _def.elements[i]
		if el.placed_in_editor:
			return el.id
	return ""


func definition() -> RoomDefinition:
	return _def


func _free_element_nodes(id: String) -> void:
	for node in _element_nodes.get(id, []):
		node.queue_free()
	_element_nodes.erase(id)
	_element_rects.erase(id)
	_element_quads.erase(id)


func _free_element_id(material_id: String) -> String:
	var n := 1
	while _elements.has("%s_%d" % [material_id, n]):
		n += 1
	return "%s_%d" % [material_id, n]


## Подменить материал поверхности на лету — для debug-переключателя.
func set_surface_material(surface_id: String, material_id: String) -> void:
	var cfg: RoomSurfaceConfig = _surface_cfg.get(surface_id)
	if cfg == null:
		return
	cfg.material_id = material_id
	cfg.texture_path = ""
	cfg.generator = ""
	var poly: Polygon2D = _surface_nodes.get(surface_id)
	if poly != null:
		_apply_surface_material(poly, surface_id, cfg)


## --- поверхности ------------------------------------------------------------

func _build_surfaces() -> void:
	for surface_id in RoomGeometry.SURFACES:
		var cfg: RoomSurfaceConfig = _def.surface(surface_id)
		## Потолок строго по заявке: комната без него — это выбор (стены
		## достраиваются вверх, верх кадра остаётся стеной), а комната без пола
		## или стены — забытая строка, и её видно по отладочной заглушке.
		if cfg == null and surface_id == RoomGeometry.SURFACE_CEILING:
			continue
		if cfg == null:
			cfg = RoomSurfaceConfig.new()
			cfg.id = surface_id
		_surface_cfg[surface_id] = cfg

		var poly := Polygon2D.new()
		poly.name = "Surface_" + surface_id
		poly.polygon = geom.polygons[surface_id]
		poly.z_index = _surface_layer(surface_id)
		add_child(poly)
		_surface_nodes[surface_id] = poly
		_apply_surface_material(poly, surface_id, cfg)


static func _surface_layer(surface_id: String) -> int:
	match surface_id:
		RoomGeometry.SURFACE_FLOOR: return RoomElement.LAYER_FLOOR
		RoomGeometry.SURFACE_CEILING: return RoomElement.LAYER_CEILING
		_: return RoomElement.LAYER_WALL


func _apply_surface_material(poly: Polygon2D, surface_id: String,
		cfg: RoomSurfaceConfig) -> void:
	var mat: RoomMaterial = _materials.get(cfg.material_id)
	var texture_path := cfg.texture_path
	var generator := cfg.generator
	var seed_value := _def.seed
	var tint := cfg.tint
	var tile := cfg.tile_size
	if mat != null:
		if texture_path.is_empty() and generator.is_empty():
			texture_path = mat.texture_path
			generator = mat.generator
			seed_value = mat.seed if mat.seed != 0 else _def.seed
		if tile == Vector2.ZERO:
			tile = mat.tile_size
		tint = tint * mat.tint
	if tile == Vector2.ZERO:
		tile = Vector2.ONE
	tile *= maxf(0.01, cfg.tile_scale)

	## Число повторов — это «сколько плиток такого метража укладывается в
	## поверхность». Именно поэтому размер PNG на кадр не влияет: он вообще не
	## участвует в расчёте.
	var extent := geom.extent(surface_id)
	var repeat := Vector2(extent.x / maxf(0.01, tile.x), extent.y / maxf(0.01, tile.y))
	if cfg.repeat.x > 0.0 and cfg.repeat.y > 0.0:
		repeat = cfg.repeat

	var shader_mat := ShaderMaterial.new()
	shader_mat.shader = _surface_shader
	shader_mat.set_shader_parameter("tex",
		RoomTextures.resolve(texture_path, generator, seed_value))
	shader_mat.set_shader_parameter("tiling", repeat)
	shader_mat.set_shader_parameter("uv_offset", cfg.uv_offset)
	shader_mat.set_shader_parameter("tint", tint)
	_set_inverse(shader_mat, geom.homography(surface_id))
	poly.material = shader_mat


## --- элементы, наклейки, стыки ----------------------------------------------

func _build_elements(list: Array) -> void:
	for el in list:
		_build_element(el)


func _build_element(el: RoomElement) -> void:
	if not RoomGeometry.ELEMENT_SURFACES.has(el.surface):
		push_warning("RoomAssembler: элемент '%s' на неизвестной поверхности '%s'"
			% [el.id, el.surface])
		return
	var nodes: Array[Node2D] = []
	var stands := el.stands()
	var quad := _stand_quad(el) if stands else _quad_for(el.surface, el.rect, el.rotation_deg)
	var layer := _stand_layer(el) if stands else el.layer

	## Тень вокруг проёма рисуется ПОД элементом и шире его: это она делает
	## окно утопленным в стену, а не наклеенным на неё.
	## Тень, наличник и откос описывают ПРОЁМ в стене — у предмета на полу
	## проёма нет, и подкладывать ему тень «вокруг рамы» нечего.
	if el.shadow > 0.0 and not stands:
		var grown := el.rect.grow_individual(
			el.rect.size.x * el.shadow, el.rect.size.y * el.shadow,
			el.rect.size.x * el.shadow, el.rect.size.y * el.shadow)
		grown.position += Vector2(el.shadow_offset.x * el.rect.size.x,
			el.shadow_offset.y * el.rect.size.y)
		nodes.append(_quad_node("%s_shadow" % el.id,
			_quad_for(el.surface, grown, el.rotation_deg),
			RoomTextures.generate("soft_shadow"), el.shadow_color,
			layer - 2, Vector2.ZERO))

	## Наличник — под самим элементом, но над тенью.
	if el.frame > 0.0 and not stands:
		var frame_rect := el.rect.grow_individual(
			el.rect.size.x * el.frame, el.rect.size.y * el.frame,
			el.rect.size.x * el.frame, el.rect.size.y * el.frame)
		var frame_mat: RoomMaterial = _materials.get(el.frame_material_id)
		var frame_path := el.frame_texture_path
		var frame_gen := el.frame_generator
		if frame_mat != null and frame_path.is_empty() and frame_gen.is_empty():
			frame_path = frame_mat.texture_path
			frame_gen = frame_mat.generator
		if frame_path.is_empty() and frame_gen.is_empty():
			frame_gen = "frame_bevel"
		nodes.append(_quad_node("%s_frame" % el.id,
			_quad_for(el.surface, frame_rect, el.rotation_deg),
			RoomTextures.resolve(frame_path, frame_gen, _seed_for(el.id)),
			el.frame_tint, layer - 1, Vector2.ZERO))

	if el.has_art():
		var mat: RoomMaterial = _materials.get(el.material_id)
		var path := el.texture_path
		var gen := el.generator
		var tint := el.tint
		if mat != null and path.is_empty() and gen.is_empty():
			path = mat.texture_path
			gen = mat.generator
			tint = tint * mat.tint
		tint.a *= el.opacity
		nodes.append(_quad_node(el.id, quad,
			RoomTextures.resolve(path, gen, _seed_for(el.id)), tint, layer,
			Vector2(1.0 if el.flip_h else 0.0, 1.0 if el.flip_v else 0.0)))

	## Внутренняя тень — поверх картинки: это откос проёма, а не грязь на стекле.
	if el.inset > 0.0 and not stands:
		nodes.append(_quad_node("%s_inset" % el.id, quad,
			RoomTextures.generate("inner_shadow"),
			Color(1, 1, 1, clampf(el.inset, 0.0, 1.0)), layer + 1, Vector2.ZERO))

	if nodes.is_empty():
		return
	if not el.id.is_empty():
		_element_nodes[el.id] = nodes
		_elements[el.id] = el
		_element_rects[el.id] = _bounds(quad)
		_element_quads[el.id] = quad


## Плинтус и карниз: полосы внизу и вверху каждой стены в координатах самой
## стены, поэтому они сходятся в углу сами, без подгонки.
func _build_baseboard() -> void:
	var trims := _def.trims
	if trims == null:
		return
	if trims.has_baseboard():
		_wall_band("baseboard", trims.baseboard_material_id, trims.baseboard_generator,
			trims.baseboard_tint,
			Rect2(0.0, 1.0 - trims.baseboard_height, 1.0, trims.baseboard_height))
	if trims.has_cornice():
		_wall_band("cornice", trims.cornice_material_id, trims.cornice_generator,
			trims.cornice_tint, Rect2(0.0, 0.0, 1.0, trims.cornice_height))


func _wall_band(band_name: String, material_id: String, generator: String,
		tint: Color, rect: Rect2) -> void:
	var mat: RoomMaterial = _materials.get(material_id)
	var path := ""
	var gen := generator
	if mat != null and gen.is_empty():
		path = mat.texture_path
		gen = mat.generator
	if path.is_empty() and gen.is_empty():
		gen = "wood"
	var tex := RoomTextures.resolve(path, gen, _def.seed)
	for surface_id in [RoomGeometry.SURFACE_LEFT, RoomGeometry.SURFACE_RIGHT]:
		_quad_node("%s_%s" % [band_name, surface_id],
			_quad_for(surface_id, rect, 0.0), tex, tint,
			RoomElement.LAYER_TRIM, Vector2.ZERO)


## Затемнение в углу. Рисуется на обеих стенах в их собственных координатах:
## затемнение, положенное экранной полосой, при смене шаблона уезжает с угла.
func _build_corner_shadow() -> void:
	var trims := _def.trims
	if trims == null or not trims.has_corner():
		return
	var tex := RoomTextures.generate("gradient_h")
	var tint := trims.corner_color
	tint.a = trims.corner_strength
	## У правой стены угол слева (u = 0), у левой — справа (u = 1); градиент
	## один и тот же, второй отражается.
	_quad_node("corner_right",
		_quad_for(RoomGeometry.SURFACE_RIGHT, Rect2(0.0, 0.0, trims.corner_width, 1.0), 0.0),
		tex, tint, RoomElement.LAYER_TRIM, Vector2.ZERO)
	_quad_node("corner_left",
		_quad_for(RoomGeometry.SURFACE_LEFT,
			Rect2(1.0 - trims.corner_width, 0.0, trims.corner_width, 1.0), 0.0),
		tex, tint, RoomElement.LAYER_TRIM, Vector2(1.0, 0.0))


## Контактная тень на полу вдоль стен. Без неё пол выглядит подложенным под
## стены, а не стоящим с ними в одной комнате.
func _build_contact_shadow() -> void:
	var trims := _def.trims
	if trims == null or not trims.has_contact():
		return
	var tint := trims.contact_color
	tint.a = trims.contact_strength
	## Правая стена стоит на линии v = 0 пола, левая — на линии u = 0.
	_quad_node("contact_right",
		_quad_for(RoomGeometry.SURFACE_FLOOR, Rect2(0.0, 0.0, 1.0, trims.contact_size), 0.0),
		RoomTextures.generate("gradient_v"), tint,
		RoomElement.LAYER_FLOOR_DECAL, Vector2.ZERO)
	_quad_node("contact_left",
		_quad_for(RoomGeometry.SURFACE_FLOOR, Rect2(0.0, 0.0, trims.contact_size, 1.0), 0.0),
		RoomTextures.generate("gradient_h"), tint,
		RoomElement.LAYER_FLOOR_DECAL, Vector2.ZERO)


## Процедурный слой поверх явной конфигурации. Одно и то же зерно обязано дать
## тот же кадр: иначе комната «моргает» после каждой перезагрузки, и это уже не
## разнообразие, а баг.
func _build_scatter(_screen: Vector2) -> void:
	if _def.scatter.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = _def.seed if _def.seed != 0 else hash(_def.id)
	for raw in _def.scatter:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var rule: Dictionary = raw
		var surface_id := String(rule.get("surface", RoomGeometry.SURFACE_LEFT))
		var area := ContentParser.to_rect(rule.get("area", [0.0, 0.0, 1.0, 1.0]))
		var size_range: Array = rule.get("size", [0.08, 0.16])
		var rot_range: Array = rule.get("rotation", [0.0, 0.0])
		var alpha_range: Array = rule.get("opacity", [0.4, 0.8])
		var count := int(rule.get("count", 0))
		for i in count:
			var el := RoomElement.new()
			el.id = "%s_scatter_%d" % [surface_id, _element_nodes.size() + i]
			el.surface = surface_id
			el.material_id = String(rule.get("material", ""))
			el.generator = String(rule.get("generator", ""))
			el.layer = int(rule.get("layer", RoomElement.LAYER_WALL_DECAL))
			var w := rng.randf_range(float(size_range[0]), float(size_range[-1]))
			var h := w * rng.randf_range(0.7, 1.3)
			el.rect = Rect2(
				area.position.x + rng.randf() * maxf(0.0, area.size.x - w),
				area.position.y + rng.randf() * maxf(0.0, area.size.y - h), w, h)
			el.rotation_deg = rng.randf_range(float(rot_range[0]), float(rot_range[-1]))
			el.opacity = rng.randf_range(float(alpha_range[0]), float(alpha_range[-1]))
			el.flip_h = rng.randf() < 0.5
			_build_element(el)


## Виньетка — самый дешёвый способ увести взгляд от краёв кадра. Экранная, а не
## на поверхности: она про кадр, а не про комнату.
func _build_vignette(screen: Vector2) -> void:
	if _def.vignette <= 0.0:
		return
	var sprite := Sprite2D.new()
	sprite.name = "Vignette"
	sprite.centered = false
	sprite.texture = RoomTextures.generate("vignette")
	var tex_size := Vector2(sprite.texture.get_size())
	sprite.scale = screen / tex_size
	var c := _def.vignette_color
	c.a = clampf(_def.vignette, 0.0, 1.0)
	sprite.modulate = c
	sprite.z_index = RoomElement.LAYER_FOREGROUND
	add_child(sprite)


## --- геометрия элементов ----------------------------------------------------

## Прямоугольник в координатах поверхности → четырёхугольник на экране.
##
## Поворот делается В ПЛОСКОСТИ СТЕНЫ, а не на экране, и в пропорциях комнаты,
## а не в долях: наклонённая трещина обязана наклоняться вместе со стеной,
## иначе она читается как наклейка на стекле поверх кадра.
## Четырёхугольник предмета, стоящего на полу.
##
## Он вертикальный и повёрнут к зрителю: у камеры нет наклона, поэтому вертикали
## комнаты остаются вертикалями, и шкаф не должен ни падать вбок, ни ложиться на
## пол вместе с плиткой. Уменьшается он не «на глаз», а по той же перспективе,
## что и всё остальное: экранный масштаб в точке пола — focal / глубина.
func _stand_quad(el: RoomElement) -> PackedVector2Array:
	var base := geom.uv_to_screen(RoomGeometry.SURFACE_FLOOR, el.anchor)
	var s := geom.scale_at_floor(el.anchor)
	var w := el.size.x * s * 0.5
	var h := el.size.y * s
	return PackedVector2Array([
		Vector2(base.x - w, base.y - h),
		Vector2(base.x + w, base.y - h),
		Vector2(base.x + w, base.y),
		Vector2(base.x - w, base.y),
	])


## Слой предмета — по его месту на полу: ближний рисуется поверх дальнего.
## Без этого шкаф в глубине комнаты закрывал бы ящик, стоящий у ног.
func _stand_layer(el: RoomElement) -> int:
	var t: float = clampf((el.anchor.x + el.anchor.y) * 0.5, 0.0, 1.0)
	return RoomElement.LAYER_FURNITURE + int(t * float(RoomElement.LAYER_FURNITURE_SPAN))


func _quad_for(surface_id: String, rect: Rect2, rotation_deg: float) -> PackedVector2Array:
	var corners := [
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
	]
	if surface_id == RoomGeometry.SURFACE_SCREEN:
		return _screen_quad(rect, rotation_deg)
	if absf(rotation_deg) > 0.01:
		var extent := geom.extent(surface_id)
		var centre := rect.position + rect.size * 0.5
		var pivot := Vector2(centre.x * extent.x, centre.y * extent.y)
		var a := deg_to_rad(rotation_deg)
		for i in 4:
			var p: Vector2 = corners[i]
			var w := Vector2(p.x * extent.x, p.y * extent.y) - pivot
			w = w.rotated(a) + pivot
			corners[i] = Vector2(w.x / maxf(0.01, extent.x), w.y / maxf(0.01, extent.y))

	var out := PackedVector2Array()
	for c in corners:
		out.append(geom.uv_to_screen(surface_id, c))
	return out


## Элемент, который ни на одной плоскости комнаты не лежит: лампа висит в
## воздухе, передний план стоит перед кадром. Перспективы у него нет и быть не
## должно — натянутая на стену лампа перекосилась бы вместе со стеной.
func _screen_quad(rect: Rect2, rotation_deg: float) -> PackedVector2Array:
	var r := Rect2(rect.position * _screen, rect.size * _screen)
	var corners := PackedVector2Array([
		r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	if absf(rotation_deg) > 0.01:
		var pivot := r.position + r.size * 0.5
		var a := deg_to_rad(rotation_deg)
		for i in 4:
			corners[i] = pivot + (corners[i] - pivot).rotated(a)
	return corners


func _quad_node(node_name: String, quad: PackedVector2Array, tex: Texture2D,
		tint: Color, layer: int, flip: Vector2) -> Polygon2D:
	var poly := Polygon2D.new()
	## У наклейки id может не быть — она ничем не управляется и никому не нужна
	## по имени. Пустое имя ноды при этом запрещено движком.
	poly.name = node_name if not node_name.is_empty() else "Quad"
	poly.polygon = quad
	poly.z_index = layer
	var mat := ShaderMaterial.new()
	mat.shader = _decal_shader
	mat.set_shader_parameter("tex", tex)
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("flip", flip)
	_set_inverse(mat, RoomHomography.from_quad(quad[0], quad[1], quad[2], quad[3]))
	poly.material = mat
	add_child(poly)
	return poly


func _set_inverse(mat: ShaderMaterial, h: RoomHomography) -> void:
	var rows := h.inv_rows()
	mat.set_shader_parameter("inv_r0", rows[0])
	mat.set_shader_parameter("inv_r1", rows[1])
	mat.set_shader_parameter("inv_r2", rows[2])


static func _bounds(quad: PackedVector2Array) -> Rect2:
	var r := Rect2(quad[0], Vector2.ZERO)
	for i in range(1, quad.size()):
		r = r.expand(quad[i])
	return r


func _seed_for(id: String) -> int:
	return _def.seed + int(hash(id) % 100000)
