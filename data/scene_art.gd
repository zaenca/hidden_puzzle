class_name SceneArt
extends Resource
## Визуал сцены уровня. Одна и та же SceneArt обслуживает ОБЕ фазы:
## puzzle собирает это изображение, hidden object ищет в нём предметы.
##
## Пока финального арта нет, background == null и картинка генерируется
## PlaceholderArt по palette/seed/decor. Как только появится PNG — достаточно
## заполнить background_path, остальной пайплайн не меняется.

@export var reference_size: Vector2i = Vector2i(1080, 1350)
@export var background: Texture2D = null
@export var background_path: String = ""
@export var palette: String = "street"
@export var seed: int = 0
@export var clutter: int = 26        ## сколько отвлекающих форм подмешать
@export var decor: Array = []        ## [{rect:[x,y,w,h], color:"#rrggbb", shape:"rect"}]

func has_final_art() -> bool:
	return background != null or not background_path.is_empty()
