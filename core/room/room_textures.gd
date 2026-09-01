class_name RoomTextures
extends RefCounted
## Заглушки материалов и элементов комнаты, нарисованные кодом.
##
## Зачем они вообще. Система процедурных комнат бесполезна без текстур, а
## текстур ещё нет. Рисовать вместо них финальный арт — значит выкинуть его,
## когда придёт настоящий; оставить систему без картинок — значит не проверить
## ни перспективу, ни тайлинг. Поэтому здесь простые, честно бесшовные
## заглушки: их видно, по ним видно раскладку, и они заменяются одним полем
## `texture` в JSON, без единой правки кода.
##
## Все плиточные заглушки бесшовны ПО ПОСТРОЕНИЮ: узор строится на решётке,
## период которой делит размер картинки. Шум — тоже: решётка значений замкнута
## по модулю, поэтому левый край совпадает с правым точно, а не «на глаз».

const TILE_SIZE := 256
const NOISE_SIZE := 128

## Заглушки просят по нескольку раз (пол, стены, переключатель материалов),
## а рисование идёт по пикселям. Кэш держится на весь запуск: заглушек единицы,
## и перерисовывать их на каждый вход в локацию нечего.
static var _cache: Dictionary = {}


## Основная точка входа. Настоящий PNG важнее заглушки: как только художник
## пришлёт файл, генератор молча перестаёт использоваться.
static func resolve(texture_path: String, generator: String, seed_value: int = 0) -> Texture2D:
	if not texture_path.is_empty():
		var tex := Backdrop.load_texture(texture_path)
		if tex != null:
			return tex
		push_warning("RoomTextures: нет файла '%s' — рисую заглушку '%s'"
			% [texture_path, generator])
	if generator.is_empty():
		return generate("missing", seed_value)
	return generate(generator, seed_value)


static func generate(generator: String, seed_value: int = 0) -> Texture2D:
	var key := "%s|%d" % [generator, seed_value]
	if _cache.has(key):
		return _cache[key]
	var img := _draw(generator, seed_value)
	## Мип-мапы обязательны, а не «желательны»: у дальнего края пола одна плитка
	## занимает считанные пиксели, и без них там начинается муар, который сразу
	## выдаёт, что перспектива нарисована, а не снята.
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


static func _draw(generator: String, seed_value: int) -> Image:
	match generator:
		"plaster": return _noise_fill(Color(0.86, 0.80, 0.70), 0.13, seed_value)
		"concrete": return _noise_fill(Color(0.62, 0.62, 0.60), 0.11, seed_value)
		"brick": return _brick(seed_value)
		"tiles": return _tiles(seed_value)
		"wood": return _wood(seed_value)
		"checker": return _checker()
		"window": return _window()
		"door": return _door()
		"crack": return _crack(seed_value)
		"stain": return _stain(seed_value)
		"cobweb": return _cobweb()
		"inner_shadow": return _inner_shadow()
		"gradient_h": return _gradient(true)
		"gradient_v": return _gradient(false)
		"soft_shadow": return _soft_shadow()
		"vignette": return _vignette()
		"flat": return _flat()
		"frame_bevel": return _frame_bevel()
		_: return _missing()


## --- плиточные заглушки -----------------------------------------------------

static func _noise_fill(base: Color, amount: float, seed_value: int) -> Image:
	var img := Image.create_empty(NOISE_SIZE, NOISE_SIZE, false, Image.FORMAT_RGBA8)
	var grids := [
		_grid(4, seed_value), _grid(8, seed_value + 17), _grid(16, seed_value + 91)]
	var periods := [4, 8, 16]
	var weights := [0.55, 0.3, 0.15]
	for y in NOISE_SIZE:
		var fy := float(y) / float(NOISE_SIZE)
		for x in NOISE_SIZE:
			var fx := float(x) / float(NOISE_SIZE)
			var n := 0.0
			for k in 3:
				n += weights[k] * _sample(grids[k], periods[k], fx, fy)
			var c := base.lightened((n - 0.5) * amount * 2.0) if n > 0.5 \
				else base.darkened((0.5 - n) * amount * 2.0)
			c.a = 1.0
			img.set_pixel(x, y, c)
	return img


static func _brick(seed_value: int) -> Image:
	var img := Image.create_empty(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	var grout := Color(0.74, 0.71, 0.66)
	img.fill(grout)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 4001
	var rows := 8
	var bh := TILE_SIZE / rows          # 32
	var bw := TILE_SIZE / 2             # 128, два кирпича в ряд
	var gap := 4
	for row in rows:
		var offset := 0 if row % 2 == 0 else bw / 2
		for i in range(-1, 3):
			var x := i * bw + offset
			var base := Color(0.62, 0.33, 0.25).lightened(rng.randf_range(-0.10, 0.10))
			base.a = 1.0
			_wrapped_rect(img, x + gap, row * bh + gap, bw - gap, bh - gap, base)
	return img


static func _tiles(seed_value: int) -> Image:
	var img := Image.create_empty(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.70, 0.68, 0.64))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 7717
	var n := 4
	var step := TILE_SIZE / n            # 64
	var gap := 5
	for gy in n:
		for gx in n:
			var base := Color(0.88, 0.85, 0.79).lightened(rng.randf_range(-0.06, 0.06))
			base.a = 1.0
			_wrapped_rect(img, gx * step + gap, gy * step + gap, step - gap, step - gap, base)
			## Блик по верхней кромке: без него плитка читается как плоский
			## прямоугольник, а не как керамика.
			_wrapped_rect(img, gx * step + gap, gy * step + gap, step - gap, 3,
				base.lightened(0.18))
	return img


static func _wood(seed_value: int) -> Image:
	var img := Image.create_empty(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 1231
	var planks := 4
	var pw := TILE_SIZE / planks
	for p in planks:
		var base := Color(0.55, 0.38, 0.22).lightened(rng.randf_range(-0.12, 0.12))
		base.a = 1.0
		_wrapped_rect(img, p * pw, 0, pw, TILE_SIZE, base)
		for _g in 5:
			var gx := p * pw + rng.randi_range(3, pw - 4)
			_wrapped_rect(img, gx, 0, 1, TILE_SIZE, base.darkened(rng.randf_range(0.10, 0.25)))
		## Шов между досками.
		_wrapped_rect(img, p * pw, 0, 2, TILE_SIZE, base.darkened(0.45))
	return img


## Отладочная шахматка с меткой: по ней сразу видно и раскладку, и ориентацию —
## перевёрнутая или зеркальная поверхность иначе выглядит правдоподобно.
static func _checker() -> Image:
	var img := Image.create_empty(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	var a := Color(0.86, 0.86, 0.88)
	var b := Color(0.30, 0.32, 0.38)
	img.fill(a)
	var half := TILE_SIZE / 2
	img.fill_rect(Rect2i(half, 0, half, half), b)
	img.fill_rect(Rect2i(0, half, half, half), b)
	img.fill_rect(Rect2i(12, 12, 40, 12), Color(0.90, 0.32, 0.22))
	img.fill_rect(Rect2i(12, 12, 12, 40), Color(0.90, 0.32, 0.22))
	return img


## --- элементы и наклейки ----------------------------------------------------

static func _window() -> Image:
	var w := 320
	var h := 420
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var frame := Color(0.72, 0.62, 0.48)
	img.fill_rect(Rect2i(0, 0, w, h), frame)
	img.fill_rect(Rect2i(0, 0, w, 10), frame.lightened(0.18))
	img.fill_rect(Rect2i(0, h - 14, w, 14), frame.darkened(0.25))
	var m := 26
	## Стекло: небо сверху вниз. Градиент, а не заливка, — плоское стекло
	## читается как дырка в стене.
	for y in range(m, h - m):
		var t := float(y - m) / float(h - 2 * m)
		var sky := Color(0.62, 0.78, 0.92).lerp(Color(0.88, 0.90, 0.86), t)
		img.fill_rect(Rect2i(m, y, w - 2 * m, 1), sky)
	var bar := frame.darkened(0.10)
	img.fill_rect(Rect2i(w / 2 - 7, m, 14, h - 2 * m), bar)
	img.fill_rect(Rect2i(m, h / 2 - 7, w - 2 * m, 14), bar)
	return img


static func _door() -> Image:
	var w := 300
	var h := 640
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var base := Color(0.42, 0.28, 0.18)
	img.fill(base)
	img.fill_rect(Rect2i(0, 0, w, 12), base.lightened(0.20))
	img.fill_rect(Rect2i(0, h - 12, w, 12), base.darkened(0.30))
	for p in 4:
		var x := 8 + p * (w - 16) / 4
		img.fill_rect(Rect2i(x, 8, 2, h - 16), base.darkened(0.28))
	## Филёнки.
	for panel in 2:
		var py := 60 + panel * (h / 2 - 20)
		img.fill_rect(Rect2i(46, py, w - 92, h / 2 - 130), base.darkened(0.14))
		img.fill_rect(Rect2i(52, py + 6, w - 104, h / 2 - 142), base.lightened(0.06))
	_disc(img, Vector2(w - 44, h * 0.52), 15.0, Color(0.78, 0.68, 0.32))
	return img


static func _crack(seed_value: int) -> Image:
	var size := 256
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 5501
	_crack_line(img, rng, Vector2(size * 0.5, 4), 0, size, 3.0)
	for _b in 3:
		var y := rng.randf_range(size * 0.2, size * 0.8)
		_crack_line(img, rng, Vector2(size * 0.5 + rng.randf_range(-30, 30), y),
			rng.randf_range(-1.0, 1.0), int(size * rng.randf_range(0.2, 0.4)), 2.0)
	return img


static func _crack_line(img: Image, rng: RandomNumberGenerator, from: Vector2,
		drift: float, steps: int, width: float) -> void:
	var p := from
	var d := Vector2(drift, 1.0).normalized()
	for _i in steps:
		d = (d + Vector2(rng.randf_range(-0.35, 0.35), 0.0)).normalized()
		p += d
		var r := maxf(0.6, width * 0.5)
		_disc(img, p, r, Color(0.16, 0.13, 0.11, 0.75))


static func _stain(seed_value: int) -> Image:
	var size := 256
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 313
	var c := Vector2(size, size) * 0.5
	var radii := PackedFloat32Array()
	for i in 32:
		radii.append(rng.randf_range(0.62, 1.0))
	for y in size:
		for x in size:
			var v := Vector2(x, y) - c
			var d := v.length() / (size * 0.5)
			var a := (atan2(v.y, v.x) + PI) / TAU * 32.0
			var i0 := int(a) % 32
			var i1 := (i0 + 1) % 32
			var edge: float = lerpf(radii[i0], radii[i1], a - floorf(a))
			if d < edge:
				var alpha: float = smoothstep(edge, edge * 0.35, d) * 0.55
				img.set_pixel(x, y, Color(0.24, 0.19, 0.14, alpha))
	return img


static func _cobweb() -> Image:
	var size := 256
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Color(0.92, 0.92, 0.95, 0.55)
	var origin := Vector2(4, 4)
	var rays := 7
	for i in rays:
		var a: float = lerpf(0.05, PI * 0.5 - 0.05, float(i) / float(rays - 1))
		var dir := Vector2(cos(a), sin(a))
		for t in range(0, size):
			_disc(img, origin + dir * float(t), 0.7, c)
	for ring in range(1, 6):
		var r := size * float(ring) / 6.0
		var steps := int(r * 1.6)
		for s in steps:
			var a: float = lerpf(0.05, PI * 0.5 - 0.05, float(s) / float(maxi(1, steps - 1)))
			var sag := 1.0 - 0.12 * sin(float(s) / float(maxi(1, steps - 1)) * PI)
			_disc(img, origin + Vector2(cos(a), sin(a)) * r * sag, 0.7, c)
	return img


## --- служебные градиенты «встроенности» -------------------------------------

## Тень по краям проёма внутрь. Сверху сильнее: свет в комнате идёт сверху, и
## равномерная рамка вокруг окна читается как виньетка, а не как откос.
static func _inner_shadow() -> Image:
	var size := 128
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var depth := 0.22
	for y in size:
		var fy := float(y) / float(size - 1)
		for x in size:
			var fx := float(x) / float(size - 1)
			var top: float = 1.0 - clampf(fy / depth, 0.0, 1.0)
			var bottom: float = 1.0 - clampf((1.0 - fy) / depth, 0.0, 1.0)
			var left: float = 1.0 - clampf(fx / depth, 0.0, 1.0)
			var right: float = 1.0 - clampf((1.0 - fx) / depth, 0.0, 1.0)
			var a: float = maxf(maxf(top * 1.0, left * 0.75), maxf(bottom * 0.35, right * 0.5))
			img.set_pixel(x, y, Color(0.05, 0.04, 0.03, a * a))
	return img


static func _gradient(horizontal: bool) -> Image:
	var size := 64
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	for i in size:
		var t := float(i) / float(size - 1)
		var a := (1.0 - t) * (1.0 - t)
		var c := Color(0.03, 0.03, 0.04, a)
		if horizontal:
			img.fill_rect(Rect2i(i, 0, 1, size), c)
		else:
			img.fill_rect(Rect2i(0, i, size, 1), c)
	return img


static func _soft_shadow() -> Image:
	var size := 128
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		var fy := float(y) / float(size - 1)
		for x in size:
			var fx := float(x) / float(size - 1)
			var d: float = minf(minf(fx, 1.0 - fx), minf(fy, 1.0 - fy))
			var a: float = smoothstep(0.0, 0.32, d)
			img.set_pixel(x, y, Color(0.04, 0.03, 0.03, a))
	return img


## Обратная soft_shadow: прозрачная середина, тёмные края. Уводит взгляд от
## границ кадра — там комната кончается обрезкой, а не стеной.
static func _vignette() -> Image:
	var size := 128
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		var fy := float(y) / float(size - 1) * 2.0 - 1.0
		for x in size:
			var fx := float(x) / float(size - 1) * 2.0 - 1.0
			var d: float = sqrt(fx * fx + fy * fy) / sqrt(2.0)
			img.set_pixel(x, y, Color(1, 1, 1, smoothstep(0.45, 1.0, d)))
	return img


static func _frame_bevel() -> Image:
	var size := 128
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var band := 10
	var wood := Color(0.66, 0.55, 0.42, 1.0)
	img.fill_rect(Rect2i(0, 0, size, band), wood.lightened(0.16))
	img.fill_rect(Rect2i(0, size - band, size, band), wood.darkened(0.22))
	img.fill_rect(Rect2i(0, 0, band, size), wood.lightened(0.06))
	img.fill_rect(Rect2i(size - band, 0, band, size), wood.darkened(0.12))
	return img


## Сплошная заливка: весь цвет задаётся тинтом элемента. Нужна там, где картинки
## нет и не будет, — тёмный проём открытой двери это не текстура, это дырка.
static func _flat() -> Image:
	var img := Image.create_empty(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	return img


static func _missing() -> Image:
	var img := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.85, 0.1, 0.7))
	img.fill_rect(Rect2i(0, 0, 32, 32), Color(0.15, 0.15, 0.18))
	img.fill_rect(Rect2i(32, 32, 32, 32), Color(0.15, 0.15, 0.18))
	return img


## --- примитивы --------------------------------------------------------------

## Прямоугольник с заворотом за край: узор, нарисованный «внахлёст», обязан
## продолжиться с другой стороны, иначе бесшовность ломается ровно на швах.
static func _wrapped_rect(img: Image, x: int, y: int, w: int, h: int, color: Color) -> void:
	var size := img.get_width()
	var size_y := img.get_height()
	for dx in w:
		var px := posmod(x + dx, size)
		for dy in h:
			img.set_pixel(px, posmod(y + dy, size_y), color)


static func _disc(img: Image, centre: Vector2, radius: float, color: Color) -> void:
	var r := int(ceilf(radius))
	var w := img.get_width()
	var h := img.get_height()
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if Vector2(dx, dy).length() > radius:
				continue
			var x := int(centre.x) + dx
			var y := int(centre.y) + dy
			if x < 0 or y < 0 or x >= w or y >= h:
				continue
			var dst := img.get_pixel(x, y)
			img.set_pixel(x, y, dst.blend(color))


## --- шум с точным периодом --------------------------------------------------

static func _grid(period: int, seed_value: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 2654435761 + period
	var out := PackedFloat32Array()
	out.resize(period * period)
	for i in period * period:
		out[i] = rng.randf()
	return out


## Билинейная выборка по замкнутой решётке: правый край берёт значения левого,
## поэтому текстура стыкуется сама с собой точно, а не приблизительно.
static func _sample(grid: PackedFloat32Array, period: int, fx: float, fy: float) -> float:
	var gx := fx * float(period)
	var gy := fy * float(period)
	var x0 := int(floorf(gx))
	var y0 := int(floorf(gy))
	var tx: float = smoothstep(0.0, 1.0, gx - float(x0))
	var ty: float = smoothstep(0.0, 1.0, gy - float(y0))
	var x1 := posmod(x0 + 1, period)
	var y1 := posmod(y0 + 1, period)
	x0 = posmod(x0, period)
	y0 = posmod(y0, period)
	var a: float = lerpf(grid[y0 * period + x0], grid[y0 * period + x1], tx)
	var b: float = lerpf(grid[y1 * period + x0], grid[y1 * period + x1], tx)
	return lerpf(a, b, ty)
