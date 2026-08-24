class_name JigsawGeometry
extends RefCounted
## Части пазла генерируются кодом, а не рисуются художником.
##
## Соседние части используют ОДИН И ТОТ ЖЕ массив точек общей грани (у одной
## части он читается вперёд, у другой назад), поэтому замки всегда совпадают.
## Текстура берётся с общего фона через UV — отдельные PNG не нужны, стоимость
## нового пазла равна нулю.

## Профиль замка в нормализованных координатах грани:
## x — вдоль грани (0..1), y — наружу (умножается на высоту замка и на знак).
## Голова (x 0.28..0.72) шире шейки (x 0.35..0.65) — за счёт этого части
## сцепляются, а не просто соприкасаются.
const PROFILE: Array[Vector2] = [
	Vector2(0.00, 0.00), Vector2(0.20, 0.00), Vector2(0.35, 0.04),
	Vector2(0.37, 0.20), Vector2(0.28, 0.31), Vector2(0.28, 0.48),
	Vector2(0.42, 0.58), Vector2(0.58, 0.58), Vector2(0.72, 0.48),
	Vector2(0.72, 0.31), Vector2(0.63, 0.20), Vector2(0.65, 0.04),
	Vector2(0.80, 0.00), Vector2(1.00, 0.00),
]

const SMOOTH_STEPS := 3


## Возвращает Array[Dictionary]: {cell: Vector2i, origin: Vector2, polygon: PackedVector2Array}
## polygon — в координатах, относительных к origin (левый верхний угол ячейки).
static func build(cols: int, rows: int, size: Vector2, tab_ratio: float, seed_value: int) -> Array:
	cols = maxi(1, cols)
	rows = maxi(1, rows)

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value if seed_value != 0 else 1

	var cw := size.x / float(cols)
	var ch := size.y / float(rows)
	var tab := tab_ratio * minf(cw, ch)

	# Горизонтальные грани: h[r][c] идёт слева направо по линии y = r*ch.
	var h: Array = []
	for r in rows + 1:
		var row: Array = []
		for c in cols:
			var a := Vector2(c * cw, r * ch)
			var b := Vector2((c + 1) * cw, r * ch)
			var sign := 0 if (r == 0 or r == rows) else (1 if rng.randf() < 0.5 else -1)
			row.append(_edge(a, b, sign, tab))
		h.append(row)

	# Вертикальные грани: v[r][c] идёт сверху вниз по линии x = c*cw.
	var v: Array = []
	for r in rows:
		var row: Array = []
		for c in cols + 1:
			var a := Vector2(c * cw, r * ch)
			var b := Vector2(c * cw, (r + 1) * ch)
			var sign := 0 if (c == 0 or c == cols) else (1 if rng.randf() < 0.5 else -1)
			row.append(_edge(a, b, sign, tab))
		v.append(row)

	var pieces: Array = []
	for r in rows:
		for c in cols:
			var poly := PackedVector2Array()
			_append_forward(poly, h[r][c])        # верх: слева направо
			_append_forward(poly, v[r][c + 1])    # право: сверху вниз
			_append_backward(poly, h[r + 1][c])   # низ: справа налево
			_append_backward(poly, v[r][c])       # лево: снизу вверх

			var origin := Vector2(c * cw, r * ch)
			var local := PackedVector2Array()
			for p in poly:
				local.append(p - origin)

			pieces.append({
				"cell": Vector2i(c, r),
				"origin": origin,
				"polygon": local,
			})
	return pieces


static func _edge(a: Vector2, b: Vector2, sign: int, tab: float) -> PackedVector2Array:
	if sign == 0:
		return PackedVector2Array([a, b])
	var delta := b - a
	var length := delta.length()
	var dir := delta / length
	var normal := Vector2(-dir.y, dir.x)
	var pts := PackedVector2Array()
	for p in PROFILE:
		pts.append(a + dir * (p.x * length) + normal * (p.y * tab * float(sign)))
	return _smooth(pts, SMOOTH_STEPS)


## Catmull-Rom по опорным точкам. Применяется один раз к каждой грани, поэтому
## обе соседние части получают идентичную кривую.
static func _smooth(pts: PackedVector2Array, steps: int) -> PackedVector2Array:
	if steps <= 0 or pts.size() < 3:
		return pts
	var n := pts.size()
	var out := PackedVector2Array()
	for i in n - 1:
		var p0 := pts[maxi(i - 1, 0)]
		var p1 := pts[i]
		var p2 := pts[i + 1]
		var p3 := pts[mini(i + 2, n - 1)]
		out.append(p1)
		for s in range(1, steps):
			out.append(_catmull(p0, p1, p2, p3, float(s) / float(steps)))
	out.append(pts[n - 1])
	return out


static func _catmull(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * (
		2.0 * p1
		+ (-p0 + p2) * t
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
	)


static func _append_forward(target: PackedVector2Array, edge: PackedVector2Array) -> void:
	for i in edge.size() - 1:
		target.append(edge[i])


static func _append_backward(target: PackedVector2Array, edge: PackedVector2Array) -> void:
	for i in range(edge.size() - 1, 0, -1):
		target.append(edge[i])
