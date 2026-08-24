class_name PlaceholderArt
extends RefCounted
## Генерация временного арта. Ключевая идея: искомые предметы ЗАПЕКАЮТСЯ
## в фон уровня — ровно как это будет с финальным PNG. Поэтому:
##   * jigsaw собирает изображение, В КОТОРОМ уже лежат предметы;
##   * после reveal под пазлом та же картинка пиксель-в-пиксель;
##   * hidden object ищет по цвету и форме, а не по невидимым хитбоксам.
## Когда появится настоящий арт, SceneArt.background_path перекроет генерацию,
## и ни одна другая система не изменится.

const OUTLINE := Color(0, 0, 0, 0.35)


static func build_scene_texture(art: SceneArt, targets: Array[HOTarget], items: Dictionary) -> Texture2D:
	if not art.background_path.is_empty() and ResourceLoader.exists(art.background_path):
		return load(art.background_path)
	if art.background != null:
		return art.background

	var w: int = art.reference_size.x
	var h: int = art.reference_size.y
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)

	_fill_gradient(img, Palette.top(art.palette), Palette.bottom(art.palette))

	var rng := RandomNumberGenerator.new()
	rng.seed = art.seed if art.seed != 0 else hash(art.palette)

	_draw_decor(img, art)
	_draw_clutter(img, art, rng)

	for t in targets:
		var item: ItemDefinition = items.get(t.item_id)
		var color := item.color if item != null else Color.MAGENTA
		var shape := item.shape if item != null else "rect"
		var r := _denorm(t.bounds(), w, h)
		draw_shape(img, r, color, shape, true)

	return ImageTexture.create_from_image(img)


static func item_icon(item: ItemDefinition, size: int = 72) -> Texture2D:
	if item != null and item.icon != null:
		return item.icon
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var color := item.color if item != null else Color.MAGENTA
	var shape := item.shape if item != null else "rect"
	draw_shape(img, Rect2i(6, 6, size - 12, size - 12), color, shape, true)
	return ImageTexture.create_from_image(img)


static func flat_texture(size: Vector2i, top: Color, bottom: Color) -> Texture2D:
	var img := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	_fill_gradient(img, top, bottom)
	return ImageTexture.create_from_image(img)


## --- рисование --------------------------------------------------------------

static func draw_shape(img: Image, rect: Rect2i, color: Color, shape: String, outline: bool = false) -> void:
	if rect.size.x <= 0 or rect.size.y <= 0:
		return
	match shape:
		"circle":
			_ellipse(img, rect, color)
		"triangle":
			_triangle(img, rect, color)
		"cross":
			var tw := maxi(3, rect.size.x / 3)
			var th := maxi(3, rect.size.y / 3)
			_rect(img, Rect2i(rect.position.x, rect.position.y + (rect.size.y - th) / 2, rect.size.x, th), color)
			_rect(img, Rect2i(rect.position.x + (rect.size.x - tw) / 2, rect.position.y, tw, rect.size.y), color)
		_:
			_rect(img, rect, color)
	if outline:
		_outline_rect(img, rect)


static func _fill_gradient(img: Image, top: Color, bottom: Color) -> void:
	var h := img.get_height()
	var w := img.get_width()
	for y in h:
		var t := float(y) / maxf(1.0, float(h - 1))
		img.fill_rect(Rect2i(0, y, w, 1), top.lerp(bottom, t))


static func _draw_decor(img: Image, art: SceneArt) -> void:
	var w: int = art.reference_size.x
	var h: int = art.reference_size.y
	for entry in art.decor:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var raw: Array = entry.get("rect", [0, 0, 0.1, 0.1])
		var r := _denorm(Rect2(raw[0], raw[1], raw[2], raw[3]), w, h)
		var c := Color.html(String(entry.get("color", "#777777")))
		draw_shape(img, r, c, String(entry.get("shape", "rect")), false)


static func _draw_clutter(img: Image, art: SceneArt, rng: RandomNumberGenerator) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var shapes := ["rect", "circle", "triangle", "cross"]
	for i in art.clutter:
		var base := Palette.clutter_color(art.palette, rng.randi_range(0, 8))
		var c := base.lerp(Color(rng.randf(), rng.randf(), rng.randf()), 0.18)
		c.a = 1.0
		var sw := rng.randi_range(int(w * 0.05), int(w * 0.16))
		var sh := rng.randi_range(int(h * 0.03), int(h * 0.10))
		var x := rng.randi_range(0, maxi(1, w - sw))
		var y := rng.randi_range(int(h * 0.08), maxi(1, h - sh))
		draw_shape(img, Rect2i(x, y, sw, sh), c, shapes[rng.randi_range(0, shapes.size() - 1)], true)


static func _rect(img: Image, rect: Rect2i, color: Color) -> void:
	var clipped := _clip(img, rect)
	if clipped.size.x > 0 and clipped.size.y > 0:
		img.fill_rect(clipped, color)


static func _ellipse(img: Image, rect: Rect2i, color: Color) -> void:
	var cx := rect.position.x + rect.size.x * 0.5
	var cy := rect.position.y + rect.size.y * 0.5
	var rx := maxf(1.0, rect.size.x * 0.5)
	var ry := maxf(1.0, rect.size.y * 0.5)
	var clipped := _clip(img, rect)
	for y in range(clipped.position.y, clipped.position.y + clipped.size.y):
		for x in range(clipped.position.x, clipped.position.x + clipped.size.x):
			var dx := (x + 0.5 - cx) / rx
			var dy := (y + 0.5 - cy) / ry
			if dx * dx + dy * dy <= 1.0:
				img.set_pixel(x, y, color)


static func _triangle(img: Image, rect: Rect2i, color: Color) -> void:
	var clipped := _clip(img, rect)
	var top_x := rect.position.x + rect.size.x * 0.5
	for y in range(clipped.position.y, clipped.position.y + clipped.size.y):
		var t := float(y - rect.position.y) / maxf(1.0, float(rect.size.y))
		var half := rect.size.x * 0.5 * t
		var x0 := int(top_x - half)
		var x1 := int(top_x + half)
		for x in range(maxi(x0, clipped.position.x), mini(x1, clipped.position.x + clipped.size.x)):
			img.set_pixel(x, y, color)


static func _outline_rect(img: Image, rect: Rect2i) -> void:
	var t := 2
	_rect(img, Rect2i(rect.position.x, rect.position.y, rect.size.x, t), OUTLINE)
	_rect(img, Rect2i(rect.position.x, rect.position.y + rect.size.y - t, rect.size.x, t), OUTLINE)
	_rect(img, Rect2i(rect.position.x, rect.position.y, t, rect.size.y), OUTLINE)
	_rect(img, Rect2i(rect.position.x + rect.size.x - t, rect.position.y, t, rect.size.y), OUTLINE)


static func _clip(img: Image, rect: Rect2i) -> Rect2i:
	return rect.intersection(Rect2i(0, 0, img.get_width(), img.get_height()))


static func _denorm(r: Rect2, w: int, h: int) -> Rect2i:
	return Rect2i(int(r.position.x * w), int(r.position.y * h), maxi(1, int(r.size.x * w)), maxi(1, int(r.size.y * h)))
