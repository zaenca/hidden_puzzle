class_name SceneArt
extends Resource
## Визуал сцены уровня. Одна и та же SceneArt обслуживает ОБЕ фазы:
## puzzle собирает изображение, hidden object ищет в нём предметы.
##
## Два слоя намеренно разделены. background — «чистая» комната, её игрок
## собирает как пазл. objects_background — тот же кадр, но с подброшенными
## предметами; он проявляется на reveal. Так предметы не видны заранее по
## частям в лотке, а появление сцены поиска читается как событие.
##
## Пока финального арта нет, оба пути пустые и картинка генерируется
## PlaceholderArt по palette/seed/decor — проект остаётся запускаемым без ассетов.

@export var reference_size: Vector2i = Vector2i(1080, 1350)
@export var background: Texture2D = null
@export var background_path: String = ""
@export var objects_background_path: String = ""
@export var palette: String = "street"
@export var seed: int = 0
@export var clutter: int = 26        ## сколько отвлекающих форм подмешать
@export var decor: Array = []        ## [{rect:[x,y,w,h], color:"#rrggbb", shape:"rect"}]

func has_final_art() -> bool:
	return background != null or not background_path.is_empty()

## Есть ли отдельный слой с предметами. Если нет, hidden object работает
## по тому же изображению, что и пазл (поведение прежних уровней).
func has_objects_layer() -> bool:
	return not objects_background_path.is_empty()
