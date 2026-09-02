class_name RoomElement
extends Resource
## Всё, что лежит НА поверхности: окно, дверь, ниша, полка, плинтус, трещина,
## пятно, паутина. Один класс на все виды намеренно: с точки зрения отрисовки
## это одно и то же — прямоугольник в координатах поверхности, натянутый на её
## перспективу. Различаются они порядком слоя и тем, нужна ли им тень.
##
## rect нормализован К ПОВЕРХНОСТИ, а не к экрану: [0.15, 0.18, 0.27, 0.30] —
## это «15% от левого края стены, 18% от её верха». Один и тот же элемент можно
## переставить по стене, не пересчитывая ничего в экранных пикселях.

## Порядок слоёв. Пол рисуется первым, стены поверх него, элементы поверх стен.
## Числа с запасом между слоями: контент может встать между ними своим `layer`.
const LAYER_FLOOR := 0
const LAYER_FLOOR_DECAL := 10
const LAYER_WALL := 20
## Потолок поверх стен: стены могут быть достроены выше своей высоты, и потолок
## обязан их накрыть, а не встать под ними.
const LAYER_CEILING := 25
const LAYER_WALL_DECAL := 30
const LAYER_TRIM := 40
const LAYER_STRUCTURE := 50
## Мебель поверх проёмов: шкаф, задвинутый к двери, обязан её закрывать.
## Внутри этого слоя предметы сортируются по глубине — ближний поверх дальнего.
const LAYER_FURNITURE := 52
const LAYER_FURNITURE_SPAN := 8
const LAYER_FOREGROUND := 70

## Как элемент стоит в комнате.
##   surface — прямоугольник на поверхности: окно, дверь, трещина, плинтус;
##   stand   — предмет на полу: вертикальный, повёрнут к зрителю, уменьшается
##             с удалением. Ни на одной плоскости комнаты он не лежит, поэтому
##             прямоугольником на поверхности его не описать.
const PLACE_SURFACE := "surface"
const PLACE_STAND := "stand"

@export var id: String = ""
@export var type: String = "decal"     ## window / door / arch / niche / shelf / decal / trim
@export var surface: String = "left_wall"
@export var rect: Rect2 = Rect2(0.2, 0.2, 0.2, 0.2)

## --- предмет на полу (placement = stand) ------------------------------------
@export var placement: String = PLACE_SURFACE
## Точка пола, на которой предмет стоит, в координатах пола. Не «центр», а
## именно основание: мебель растёт вверх от точки, где её поставили.
@export var anchor: Vector2 = Vector2(0.5, 0.5)
## Габарит предмета В ЕДИНИЦАХ КОМНАТЫ, а не в долях экрана. Шкаф высотой 1.9 —
## это метр девяносто в любой комнате и на любом шаблоне геометрии; доля экрана
## означала бы, что в тесной кладовой он вырастает до потолка.
@export var size: Vector2 = Vector2(1.0, 1.0)
## Поставлен игроком в редакторе, а не написан в контенте руками. Различие
## нужно только сохранению: рукописные элементы переписывать не хочется.
@export var placed_in_editor: bool = false


func stands() -> bool:
	return placement == PLACE_STAND

@export var material_id: String = ""
@export var texture_path: String = ""
@export var generator: String = ""

@export var tint: Color = Color.WHITE
@export var opacity: float = 1.0
## Поворот В ПЛОСКОСТИ ПОВЕРХНОСТИ, а не на экране: наклонённая трещина обязана
## наклоняться вместе со стеной, иначе она читается как наклейка на стекле.
@export var rotation_deg: float = 0.0
@export var flip_h: bool = false
@export var flip_v: bool = false
@export var layer: int = LAYER_WALL_DECAL

## --- «встроенность»: то, что отличает окно от наклейки ----------------------
## Мягкая тень вокруг проёма: элемент утоплен в стену, значит по краям от него
## стена затенена. Число — насколько тень шире самого элемента, в долях его
## размера. Ноль — тени нет.
@export var shadow: float = 0.0
@export var shadow_offset: Vector2 = Vector2(0.0, 0.02)
@export var shadow_color: Color = Color(0, 0, 0, 0.45)
## Внутренняя тень по краям самого проёма — глубина откоса. 0 — выключена.
@export var inset: float = 0.0
## Наличник вокруг проёма. Число — ширина в долях размера элемента.
@export var frame: float = 0.0
@export var frame_material_id: String = ""
@export var frame_texture_path: String = ""
@export var frame_generator: String = ""
@export var frame_tint: Color = Color.WHITE

## --- связь с состоянием мира ------------------------------------------------
## Элемент виден не всегда. Условия читаются из флагов и состояний слотов,
## которые собирающему комнату передают снаружи: сама комната ни про
## MetaService, ни про сейв не знает.
@export var visible_if_flag: String = ""
@export var hidden_if_flag: String = ""
@export var slot_id: String = ""       ## слот локации, к которому привязан вид
@export var slot_state: String = ""    ## показывать только в этом его состоянии


func has_art() -> bool:
	return not texture_path.is_empty() or not generator.is_empty() or not material_id.is_empty()


## Виден ли элемент при таком состоянии мира. flags и slot_states приходят
## снаружи — это и есть вся связь комнаты с метой.
func is_visible(flags: Dictionary, slot_states: Dictionary) -> bool:
	if not visible_if_flag.is_empty() and not bool(flags.get(visible_if_flag, false)):
		return false
	if not hidden_if_flag.is_empty() and bool(flags.get(hidden_if_flag, false)):
		return false
	if not slot_id.is_empty() and not slot_state.is_empty():
		if String(slot_states.get(slot_id, "")) != slot_state:
			return false
	return true
