class_name Backdrop
extends RefCounted
## Фон экрана «по обрезке»: картинка накрывает экран целиком, лишнее уходит за
## край. Приём нужен карте, локации магазина и интро одинаково, но важно в нём
## не «как растянуть», а какой прямоугольник в итоге занял арт: rect'ы
## кликабельных объектов нормализованы к КАРТИНКЕ, а не к экрану, и считать их
## от чего-то другого — значит промахиваться хитбоксами мимо нарисованного.


## Текстура по пути из данных или null, если файла нет. Отсутствие арта —
## нормальная ситуация: экран обязан остаться играбельным на градиенте.
static func load_texture(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


## Кладёт текстуру на весь экран и возвращает её прямоугольник.
static func cover(sprite: Sprite2D, tex: Texture2D, screen: Vector2) -> Rect2:
	sprite.centered = false
	sprite.texture = tex
	var tex_size := Vector2(tex.get_size())
	var s: float = maxf(screen.x / tex_size.x, screen.y / tex_size.y)
	sprite.scale = Vector2(s, s)
	sprite.position = (screen - tex_size * s) * 0.5
	return Rect2(sprite.position, tex_size * s)


## Вписать картинку целиком и вернуть её прямоугольник. Нужно там, где арт —
## не декорация, а само игровое поле: в локации по объектам комнаты кликают, и
## обрезка по экрану уносит часть из них за край вместе с их хитбоксами.
## Полосы по краям закрывает подложка сцены.
static func fit(sprite: Sprite2D, tex: Texture2D, screen: Vector2) -> Rect2:
	sprite.centered = false
	sprite.texture = tex
	var tex_size := Vector2(tex.get_size())
	var s: float = minf(screen.x / tex_size.x, screen.y / tex_size.y)
	var size := tex_size * s
	sprite.scale = Vector2(s, s)
	sprite.position = (screen - size) * 0.5
	return Rect2(sprite.position, size)


## То же покрытие, но арт прижат к низу, а не отцентрован. Нужно там, где на
## картинке нарисован интерфейс: рамка диалога стоит внизу, и при центрировании
## её срезает первым же окном, чей формат шире 9:16. Сверху у таких сцен небо —
## его обрезать не жалко.
static func cover_bottom(sprite: Sprite2D, tex: Texture2D, screen: Vector2) -> Rect2:
	sprite.centered = false
	sprite.texture = tex
	var tex_size := Vector2(tex.get_size())
	var s: float = maxf(screen.x / tex_size.x, screen.y / tex_size.y)
	var size := tex_size * s
	sprite.scale = Vector2(s, s)
	sprite.position = Vector2((screen.x - size.x) * 0.5, screen.y - size.y)
	return Rect2(sprite.position, size)


## Покрытие с прижатием низа картинки к заданной черте, а не к низу экрана.
##
## Нужно там, где часть экрана занята интерфейсом, а низ кадра — это игровое
## место. У входа в пекарню внизу нарисованы ступени и мостовая: при обычном
## `cover` они уезжают под лоток, и предметы «на полу» приходится вешать на
## дверь. Здесь картинка сдвигается вверх ровно настолько, чтобы её низ встал
## на `bottom`; сверху при этом срезается то, что и так фон.
##
## Масштаб берётся наибольшим из двух: покрыть ширину экрана и покрыть высоту
## до `bottom`. Иначе картинка, которая ниже этой черты, оставила бы под собой
## пустую полосу в видимой части экрана.
static func cover_above(sprite: Sprite2D, tex: Texture2D, screen: Vector2, bottom: float) -> Rect2:
	sprite.centered = false
	sprite.texture = tex
	var tex_size := Vector2(tex.get_size())
	var s: float = maxf(screen.x / tex_size.x, bottom / tex_size.y)
	var size := tex_size * s
	sprite.scale = Vector2(s, s)
	sprite.position = Vector2((screen.x - size.x) * 0.5, bottom - size.y)
	return Rect2(sprite.position, size)


## Запасной фон без арта — градиент по палитре во весь экран.
static func gradient(sprite: Sprite2D, palette: String, screen: Vector2) -> void:
	sprite.centered = false
	sprite.texture = PlaceholderArt.flat_texture(
		Vector2i(int(screen.x), int(screen.y)), Palette.top(palette), Palette.bottom(palette))
	sprite.scale = Vector2.ONE
	sprite.position = Vector2.ZERO
