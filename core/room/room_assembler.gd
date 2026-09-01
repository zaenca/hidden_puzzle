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
		if cfg == null:
			cfg = RoomSurfaceConfig.new()
			cfg.id = surface_id
		_surface_cfg[surface_id] = cfg

		var poly := Polygon2D.new()
		poly.name = "Surface_" + surface_id
		poly.polygon = geom.polygons[surface_id]
		poly.z_index = RoomElement.LAYER_FLOOR if surface_id == RoomGeometry.SURFACE_FLOOR \
			else RoomElement.LAYER_WALL
		add_child(poly)
		_surface_nodes[surface_id] = poly
		_apply_surface_material(poly, surface_id, cfg)


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
	if not RoomGeometry.SURFACES.has(el.surface):
		push_warning("RoomAssembler: элемент '%s' на неизвестной поверхности '%s'"
			% [el.id, el.surface])
		return
	var nodes: Array[Node2D] = []
	var quad := _quad_for(el.surface, el.rect, el.rotation_deg)

	## Тень вокруг проёма рисуется ПОД элементом и шире его: это она делает
	## окно утопленным в стену, а не наклеенным на неё.
	if el.shadow > 0.0:
		var grown := el.rect.grow_individual(
			el.rect.size.x * el.shadow, el.rect.size.y * el.shadow,
			el.rect.size.x * el.shadow, el.rect.size.y * el.shadow)
		grown.position += Vector2(el.shadow_offset.x * el.rect.size.x,
			el.shadow_offset.y * el.rect.size.y)
		nodes.append(_quad_node("%s_shadow" % el.id,
			_quad_for(el.surface, grown, el.rotation_deg),
			RoomTextures.generate("soft_shadow"), el.shadow_color,
			el.layer - 2, Vector2.ZERO))

	## Наличник — под самим элементом, но над тенью.
	if el.frame > 0.0:
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
			el.frame_tint, el.layer - 1, Vector2.ZERO))

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
			RoomTextures.resolve(path, gen, _seed_for(el.id)), tint, el.layer,
			Vector2(1.0 if el.flip_h else 0.0, 1.0 if el.flip_v else 0.0)))

	## Внутренняя тень — поверх картинки: это откос проёма, а не грязь на стекле.
	if el.inset > 0.0:
		nodes.append(_quad_node("%s_inset" % el.id, quad,
			RoomTextures.generate("inner_shadow"),
			Color(1, 1, 1, clampf(el.inset, 0.0, 1.0)), el.layer + 1, Vector2.ZERO))

	if nodes.is_empty():
		return
	if not el.id.is_empty():
		_element_nodes[el.id] = nodes
		_elements[el.id] = el
		_element_rects[el.id] = _bounds(quad)


## Плинтус: полоса внизу каждой стены в координатах самой стены, поэтому он
## сходится в углу сам, без подгонки.
func _build_baseboard() -> void:
	var trims := _def.trims
	if trims == null or not trims.has_baseboard():
		return
	var mat: RoomMaterial = _materials.get(trims.baseboard_material_id)
	var path := ""
	var gen := trims.baseboard_generator
	if mat != null and gen.is_empty():
		path = mat.texture_path
		gen = mat.generator
	if path.is_empty() and gen.is_empty():
		gen = "wood"
	var tex := RoomTextures.resolve(path, gen, _def.seed)
	for surface_id in [RoomGeometry.SURFACE_LEFT, RoomGeometry.SURFACE_RIGHT]:
		var rect := Rect2(0.0, 1.0 - trims.baseboard_height, 1.0, trims.baseboard_height)
		_quad_node("baseboard_" + surface_id,
			_quad_for(surface_id, rect, 0.0), tex, trims.baseboard_tint,
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
func _quad_for(surface_id: String, rect: Rect2, rotation_deg: float) -> PackedVector2Array:
	var corners := [
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
	]
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
