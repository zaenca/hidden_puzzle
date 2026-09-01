class_name RoomHomography
extends RefCounted
## Проективное отображение «единичный квадрат поверхности ↔ четырёхугольник на
## экране». Это ядро всей перспективы.
##
## Почему не хватает Polygon2D с UV. Godot разбивает полигон на треугольники и
## интерполирует UV АФФИННО. Для трапеции пола это даёт классический излом
## текстуры по диагонали: плитка у дальнего края не уменьшается, а ломается.
## Гомография задаёт ту же зависимость точно: u = (ax+by+c)/(gx+hy+i). Считать
## её на пиксель дёшево — три скалярных произведения и одно деление, — и
## результат перспективно корректен по построению, без разбиения на треугольники
## и без зависимости от того, как полигон стриангулировался.
##
## Матрица хранится по строкам. В шейдер уходит ОБРАТНАЯ, тремя vec3: mat3 из
## GDScript пришлось бы транспонировать, и эта ошибка не видна глазом — она
## просто слегка перекашивает раскладку.

var m: PackedFloat32Array = PackedFloat32Array()      ## uv -> экран
var inv: PackedFloat32Array = PackedFloat32Array()    ## экран -> uv

const EPS := 1e-9


## Квадрат (0,0),(1,0),(1,1),(0,1) → p0,p1,p2,p3. Формула Хекберта
## («Projective Mappings for Image Warping»).
static func from_quad(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2) -> RoomHomography:
	var h := RoomHomography.new()
	var sx := p0.x - p1.x + p2.x - p3.x
	var sy := p0.y - p1.y + p2.y - p3.y
	var a: float
	var b: float
	var c: float
	var d: float
	var e: float
	var f: float
	var g: float
	var i: float

	var dx1 := p1.x - p2.x
	var dx2 := p3.x - p2.x
	var dy1 := p1.y - p2.y
	var dy2 := p3.y - p2.y
	var den := dx1 * dy2 - dx2 * dy1

	if (absf(sx) < EPS and absf(sy) < EPS) or absf(den) < EPS:
		## Параллелограмм (или вырожденный случай) — перспективы нет, отображение
		## аффинное. Отдельная ветка нужна не для скорости: общая формула здесь
		## делит на ноль.
		a = p1.x - p0.x
		b = p3.x - p0.x
		c = p0.x
		d = p1.y - p0.y
		e = p3.y - p0.y
		f = p0.y
		g = 0.0
		i = 0.0
	else:
		g = (sx * dy2 - dx2 * sy) / den
		i = (dx1 * sy - sx * dy1) / den
		a = p1.x - p0.x + g * p1.x
		b = p3.x - p0.x + i * p3.x
		c = p0.x
		d = p1.y - p0.y + g * p1.y
		e = p3.y - p0.y + i * p3.y
		f = p0.y

	h.m = PackedFloat32Array([a, b, c, d, e, f, g, i, 1.0])
	h.inv = _invert(h.m)
	## Знак однородной координаты в обратной матрице произвольный: умножение
	## всей гомографии на -1 отображение не меняет. Шейдеру он нужен
	## определённым — по нему он отбрасывает пиксели за линией горизонта, где
	## отображение переворачивается. Нормируем по центру четырёхугольника.
	var centre := (p0 + p1 + p2 + p3) * 0.25
	if h.inv[6] * centre.x + h.inv[7] * centre.y + h.inv[8] < 0.0:
		for k in 9:
			h.inv[k] = -h.inv[k]
	return h


## Была гомография единичного квадрата — стала гомография всей поверхности,
## у которой этот квадрат занимает `part`.
##
## Нужно там, где по четырём углам поверхности отображение не построить:
## ближний угол пола в тесной комнате лежит ЗА камерой, спроецировать его
## нельзя, а «почти за камерой» вырождает всю матрицу. Поэтому гомография
## строится по заведомо безопасному куску и переносится на всю поверхность.
## Обе записи задают ОДНУ И ТУ ЖЕ плоскость, поэтому это точный перенос, а не
## приближение: проективное отображение однозначно задано четырьмя точками, где
## бы они на плоскости ни лежали.
func remap_uv(part: Rect2) -> RoomHomography:
	var kx: float = maxf(0.0001, part.size.x)
	var ky: float = maxf(0.0001, part.size.y)
	var ox := part.position.x
	var oy := part.position.y
	var h := RoomHomography.new()
	h.m = PackedFloat32Array([
		m[0] / kx, m[1] / ky, m[2] - m[0] * ox / kx - m[1] * oy / ky,
		m[3] / kx, m[4] / ky, m[5] - m[3] * ox / kx - m[4] * oy / ky,
		m[6] / kx, m[7] / ky, m[8] - m[6] * ox / kx - m[7] * oy / ky,
	])
	h.inv = _invert(h.m)
	## Знак нормируем по центру исходного четырёхугольника: он заведомо лежит по
	## «правильную» сторону линии горизонта.
	var probe := h.map_uv(part.position + part.size * 0.5)
	if h.inv[6] * probe.x + h.inv[7] * probe.y + h.inv[8] < 0.0:
		for k in 9:
			h.inv[k] = -h.inv[k]
	return h


## Точка поверхности (u,v ∈ 0..1) → точка на экране.
func map_uv(uv: Vector2) -> Vector2:
	var w := m[6] * uv.x + m[7] * uv.y + m[8]
	if absf(w) < EPS:
		w = EPS
	return Vector2(
		(m[0] * uv.x + m[1] * uv.y + m[2]) / w,
		(m[3] * uv.x + m[4] * uv.y + m[5]) / w)


## Точка экрана → координаты на поверхности. Нужна хит-тесту: «куда на стене
## попал палец».
func map_screen(p: Vector2) -> Vector2:
	var w := inv[6] * p.x + inv[7] * p.y + inv[8]
	if absf(w) < EPS:
		w = EPS
	return Vector2(
		(inv[0] * p.x + inv[1] * p.y + inv[2]) / w,
		(inv[3] * p.x + inv[4] * p.y + inv[5]) / w)


## Три строки обратной матрицы — ровно в том виде, в каком их ждёт шейдер.
func inv_rows() -> Array:
	return [
		Vector3(inv[0], inv[1], inv[2]),
		Vector3(inv[3], inv[4], inv[5]),
		Vector3(inv[6], inv[7], inv[8]),
	]


static func _invert(s: PackedFloat32Array) -> PackedFloat32Array:
	var c0 := s[4] * s[8] - s[5] * s[7]
	var c1 := s[5] * s[6] - s[3] * s[8]
	var c2 := s[3] * s[7] - s[4] * s[6]
	var det := s[0] * c0 + s[1] * c1 + s[2] * c2
	if absf(det) < EPS:
		return PackedFloat32Array([1, 0, 0, 0, 1, 0, 0, 0, 1])
	var k := 1.0 / det
	return PackedFloat32Array([
		c0 * k,                          (s[2] * s[7] - s[1] * s[8]) * k, (s[1] * s[5] - s[2] * s[4]) * k,
		c1 * k,                          (s[0] * s[8] - s[2] * s[6]) * k, (s[2] * s[3] - s[0] * s[5]) * k,
		c2 * k,                          (s[1] * s[6] - s[0] * s[7]) * k, (s[0] * s[4] - s[1] * s[3]) * k,
	])
