class_name RoomGeometry
extends RefCounted
## Геометрия комнаты на экране: где встали стены, где пол, где угол.
##
## Считается крошечной камерой-обскурой по восьми точкам коробки. Это не 3D:
## ни одной 3D-ноды, ни одного 3D-рендера — только проекция восьми Vector3 в
## экранные Vector2 на CPU, один раз при сборке комнаты. Зато перспектива стен,
## пола, окна и двери приходит из ОДНОЙ модели и не может разъехаться между
## собой — а разъехавшийся угол виден мгновенно.
##
## Наклона у камеры нет: вертикали комнаты остаются вертикалями на экране.
## Это сознательное ограничение — см. RoomTemplate.

const SURFACE_LEFT := "left_wall"
const SURFACE_RIGHT := "right_wall"
const SURFACE_FLOOR := "floor"
const SURFACE_CEILING := "ceiling"
## Поверхности, которые красятся текстурой. Потолок последний: комната без него
## обходится — стены тогда достраиваются вверх и верх кадра остаётся стеной.
const SURFACES := [SURFACE_LEFT, SURFACE_RIGHT, SURFACE_FLOOR, SURFACE_CEILING]

## Экран — не поверхность комнаты, а её отсутствие: так вешается то, что висит
## в воздухе и ни на одной плоскости не лежит (лампа, передний план). Перспективы
## у такого элемента нет, rect нормализован к экрану.
const SURFACE_SCREEN := "screen"
const ELEMENT_SURFACES := [SURFACE_LEFT, SURFACE_RIGHT, SURFACE_FLOOR,
	SURFACE_CEILING, SURFACE_SCREEN]

## Ближе этого к камере точку не проецируем: за плоскостью камеры проекция
## переворачивается, и стена, достроенная «до бесконечности», вывернулась бы
## наизнанку через весь экран.
const MIN_DEPTH := 0.35
## Ближе этого гомографию по углам поверхности не строим. Дальний угол пола в
## тесной комнате оказывается ЗА камерой — по такому углу отображение не
## построить вовсе, а по «почти за камерой» оно вырождается. Поэтому берётся
## заведомо безопасный кусок поверхности и растягивается на всю (scaled_uv).
const SAFE_DEPTH := 0.8

var tpl: RoomTemplate
var screen: Vector2 = Vector2(1080, 1920)

var quads: Dictionary = {}         ## surface id -> PackedVector2Array, безопасный кусок
var safe_part: Dictionary = {}     ## surface id -> Rect2, какой кусок поверхности в quads
var polygons: Dictionary = {}      ## surface id -> PackedVector2Array, что рисуем
var extents: Dictionary = {}       ## surface id -> Vector2, размер в единицах комнаты
var maps: Dictionary = {}          ## surface id -> RoomHomography

var corner_top: Vector2 = Vector2.ZERO
var corner_base: Vector2 = Vector2.ZERO
var horizon_y: float = 0.0

var _dir_right: Vector3 = Vector3.ZERO
var _dir_left: Vector3 = Vector3.ZERO
var _focal: float = 1000.0
var _cx: float = 540.0
var _cy: float = 800.0


static func build(template: RoomTemplate, screen_size: Vector2) -> RoomGeometry:
	var g := RoomGeometry.new()
	g.tpl = template
	g.screen = screen_size
	g._prepare()
	return g


func _prepare() -> void:
	var dirs := tpl.corner_dirs()
	_dir_right = dirs[0]
	_dir_left = dirs[1]
	_focal = (screen.x * 0.5) / maxf(0.05, tan(deg_to_rad(tpl.fov_deg) * 0.5))
	_cx = screen.x * 0.5
	_cy = screen.y * tpl.horizon
	horizon_y = _cy

	corner_top = project(Vector3(0.0, tpl.height, 0.0))
	corner_base = project(Vector3.ZERO)

	extents[SURFACE_RIGHT] = Vector2(tpl.width, tpl.height)
	extents[SURFACE_LEFT] = Vector2(tpl.depth, tpl.height)
	extents[SURFACE_FLOOR] = Vector2(tpl.width, tpl.depth)
	extents[SURFACE_CEILING] = Vector2(tpl.width, tpl.depth)

	for id in SURFACES:
		var part := _safe_part(id)
		var q := PackedVector2Array([
			project(surface_point(id, part.position)),
			project(surface_point(id, Vector2(part.end.x, part.position.y))),
			project(surface_point(id, part.end)),
			project(surface_point(id, Vector2(part.position.x, part.end.y))),
		])
		quads[id] = q
		safe_part[id] = part
		maps[id] = RoomHomography.from_quad(q[0], q[1], q[2], q[3]).remap_uv(part)

	polygons[SURFACE_RIGHT] = _wall_polygon(SURFACE_RIGHT)
	polygons[SURFACE_LEFT] = _wall_polygon(SURFACE_LEFT)
	polygons[SURFACE_FLOOR] = _horizontal_polygon(SURFACE_FLOOR)
	polygons[SURFACE_CEILING] = _horizontal_polygon(SURFACE_CEILING)


## Точка поверхности в координатах комнаты. u идёт слева направо по экрану у
## обеих стен — иначе rect окна на левой стене пришлось бы считать задом наперёд.
## v идёт сверху вниз.
func surface_point(surface_id: String, uv: Vector2) -> Vector3:
	match surface_id:
		SURFACE_RIGHT:
			return _dir_right * (uv.x * tpl.width) + Vector3(0.0, tpl.height * (1.0 - uv.y), 0.0)
		SURFACE_LEFT:
			return _dir_left * ((1.0 - uv.x) * tpl.depth) + Vector3(0.0, tpl.height * (1.0 - uv.y), 0.0)
		SURFACE_CEILING:
			## Потолок — тот же пол, поднятый на высоту комнаты. Одна и та же
			## разметка (u вдоль правой стены, v вдоль левой) не случайна: балки
			## потолка и швы пола обязаны сходиться в одних вертикалях.
			return _dir_right * (uv.x * tpl.width) + _dir_left * (uv.y * tpl.depth) \
				+ Vector3(0.0, tpl.height, 0.0)
		_:
			return _dir_right * (uv.x * tpl.width) + _dir_left * (uv.y * tpl.depth)


## Какой кусок поверхности заведомо перед камерой. Стены уходят к зрителю
## только по одной оси (высота глубину не меняет), у пола к зрителю идут обе.
## У левой стены нумерация обратная — угол там при u = 1, — поэтому безопасен
## её ДАЛЬНИЙ конец, а не начало.
func _safe_part(surface_id: String) -> Rect2:
	var cos_a: float = maxf(0.05, cos(deg_to_rad(tpl.corner_angle_deg)))
	var room: float = maxf(0.01, tpl.cam_distance - SAFE_DEPTH)
	match surface_id:
		SURFACE_RIGHT:
			var kr: float = minf(1.0, room / maxf(0.01, tpl.width * cos_a))
			return Rect2(0.0, 0.0, kr, 1.0)
		SURFACE_LEFT:
			var kl: float = minf(1.0, room / maxf(0.01, tpl.depth * cos_a))
			return Rect2(1.0 - kl, 0.0, kl, 1.0)
		_:
			## У пола и потолка глубина набегает сразу по двум осям, поэтому
			## запас делится между ними: безопасный по каждой оси в отдельности
			## угол (1,1) всё равно оказался бы за камерой.
			var total: float = maxf(0.01, (tpl.width + tpl.depth) * cos_a)
			var k: float = minf(1.0, room / total)
			return Rect2(0.0, 0.0, k, k)


## Камера-обскура без наклона. Глубина ограничена снизу: точка, достроенная за
## плоскость камеры, иначе уехала бы в другую половину экрана.
func project(p: Vector3) -> Vector2:
	var depth: float = maxf(MIN_DEPTH, tpl.cam_distance - p.z)
	return Vector2(
		_cx + _focal * (p.x - tpl.cam_shift_x) / depth,
		_cy - _focal * (p.y - tpl.cam_eye_height) / depth)


func homography(surface_id: String) -> RoomHomography:
	return maps.get(surface_id)


func extent(surface_id: String) -> Vector2:
	return extents.get(surface_id, Vector2.ONE)


## Точка поверхности (u,v) в экран. Через ту же гомографию, которой красится
## поверхность: окно обязано стоять ровно там, где проходит её плитка.
func uv_to_screen(surface_id: String, uv: Vector2) -> Vector2:
	var h: RoomHomography = maps.get(surface_id)
	return h.map_uv(uv) if h != null else Vector2.ZERO


## --- полигоны отрисовки -----------------------------------------------------
##
## Полигон, который РИСУЕТСЯ, намеренно отвязан от четырёхугольника, который
## ЗАДАЁТ отображение. Стена достраивается вверх и вбок за пределы комнаты,
## пол — до низа экрана, а раскладка плитки при этом остаётся той же: шейдер
## считает координату поверхности из позиции пикселя, а не из вершин.

func _wall_polygon(surface_id: String) -> PackedVector2Array:
	var size_uv := extent(surface_id)
	var up: float = -tpl.wall_extend_up / maxf(0.01, size_uv.y)
	## Наружу стена достраивается до плоскости камеры: там её проекция уезжает
	## далеко за край экрана, и обрезка по экрану делает остальное.
	var cos_a: float = cos(deg_to_rad(tpl.corner_angle_deg))
	var reach: float = (tpl.cam_distance - MIN_DEPTH) / maxf(0.05, cos_a)
	var out_uv: float = maxf(1.0, reach / maxf(0.01, size_uv.x))

	var u0 := 0.0
	var u1 := out_uv
	if surface_id == SURFACE_LEFT:
		## У левой стены угол справа (u = 1), наружу — влево, за u = 0.
		u0 = 1.0 - out_uv
		u1 = 1.0

	var poly := PackedVector2Array([
		project(surface_point(surface_id, Vector2(u0, up))),
		project(surface_point(surface_id, Vector2(u1, up))),
		project(surface_point(surface_id, Vector2(u1, 1.0))),
		project(surface_point(surface_id, Vector2(u0, 1.0))),
	])
	return clip_to_rect(poly, Rect2(Vector2.ZERO, screen))


## Пол — это весь экран ниже двух линий, по которым стены стоят на полу; потолок
## — весь экран выше двух линий, по которым стены в него упираются. Так обе
## горизонтальные поверхности доходят до края кадра при любом формате экрана, а
## лишнее закрывают стены, которые рисуются между ними.
func _horizontal_polygon(surface_id: String) -> PackedVector2Array:
	## Вторые точки линий стыка берём на безопасном куске поверхности, а не в
	## дальних углах комнаты: угол может лежать за камерой, там проекция
	## обрезается по MIN_DEPTH и линия уезжает с настоящего стыка. Прямая на
	## плоскости проецируется в прямую, поэтому двух ближних точек достаточно.
	var part: Rect2 = safe_part[surface_id]
	var corner := corner_base if surface_id == SURFACE_FLOOR else corner_top
	var along_right := project(surface_point(surface_id, Vector2(part.end.x, 0.0)))
	var along_left := project(surface_point(surface_id, Vector2(0.0, part.end.y)))
	var inside := project(surface_point(surface_id, part.position + part.size * 0.5))

	var poly := PackedVector2Array([
		Vector2.ZERO, Vector2(screen.x, 0), screen, Vector2(0, screen.y)])
	poly = clip_half_plane(poly, corner, along_right, inside)
	poly = clip_half_plane(poly, corner, along_left, inside)
	return poly


## --- обрезка полигонов (Сазерленд и Ходжман) --------------------------------

static func clip_to_rect(poly: PackedVector2Array, r: Rect2) -> PackedVector2Array:
	var c := r.position + r.size * 0.5
	var out := poly
	out = clip_half_plane(out, r.position, Vector2(r.end.x, r.position.y), c)
	out = clip_half_plane(out, Vector2(r.end.x, r.position.y), r.end, c)
	out = clip_half_plane(out, r.end, Vector2(r.position.x, r.end.y), c)
	out = clip_half_plane(out, Vector2(r.position.x, r.end.y), r.position, c)
	return out


## Оставить часть полигона по ту же сторону прямой (a,b), с какой лежит inside.
static func clip_half_plane(poly: PackedVector2Array, a: Vector2, b: Vector2,
		inside: Vector2) -> PackedVector2Array:
	if poly.size() < 3:
		return poly
	var n := (b - a).orthogonal()
	var sign_in: float = n.dot(inside - a)
	if absf(sign_in) < 1e-9:
		return poly
	if sign_in < 0.0:
		n = -n

	var out := PackedVector2Array()
	var count := poly.size()
	for i in count:
		var p := poly[i]
		var q := poly[(i + 1) % count]
		var dp := n.dot(p - a)
		var dq := n.dot(q - a)
		if dp >= 0.0:
			out.append(p)
		if (dp >= 0.0) != (dq >= 0.0):
			var t: float = dp / (dp - dq)
			out.append(p + (q - p) * t)
	return out
