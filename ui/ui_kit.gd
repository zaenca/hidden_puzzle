class_name UIKit
extends RefCounted
## Минимальный набор конструкторов UI. Строим код-первым: для placeholder-этапа
## это быстрее .tscn и не мешает заменить всё на нормальный theme позже.
## Крупные touch-таргеты — не меньше MIN_TOUCH по короткой стороне.

const MIN_TOUCH := 96
const BG_DARK := Color(0.09, 0.09, 0.12, 0.86)
const BG_PANEL := Color(0.14, 0.13, 0.16, 0.94)
const ACCENT := Color(0.98, 0.73, 0.25)
## Нарисованная плашка — единственная подложка под текст в игре: и уведомление о
## задаче, и полоса предметов, и реплики в диалоге стоят на ней. Всё, что говорит
## с игроком словами, обязано стоять на ней же, иначе интерфейс распадается на
## две разные игры — нарисованную и служебную.
const PLATE := "res://art/ui/taskbar_notification.png"

## Текст поверх нарисованной кремовой плашки.
const PLATE_TEXT := Color(0.24, 0.16, 0.07)


static func label(text: String, size: int = 34, color: Color = Color(0.95, 0.94, 0.92)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("outline_size", 5)
	return l


static func button(text: String, size: int = 34) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, MIN_TOUCH)
	b.add_theme_font_size_override("font_size", size)
	b.focus_mode = Control.FOCUS_NONE
	return b


static func panel(color: Color = BG_PANEL) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.corner_radius_top_left = 18
	sb.corner_radius_top_right = 18
	sb.corner_radius_bottom_left = 18
	sb.corner_radius_bottom_right = 18
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	p.add_theme_stylebox_override("panel", sb)
	return p


## Панель на нарисованной плашке. StyleBoxTexture растягивает её по 9-slice,
## поэтому одна картинка обслуживает и короткую строку, и полосу предметов —
## рамка и скругления при этом не плывут.
static func plate(texture_path: String, margin: int = 36) -> PanelContainer:
	var p := PanelContainer.new()
	var tex := Backdrop.load_texture(texture_path)
	if tex == null:
		return panel()
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.texture_margin_left = margin
	sb.texture_margin_right = margin
	sb.texture_margin_top = margin
	sb.texture_margin_bottom = margin
	sb.content_margin_left = 26
	sb.content_margin_right = 26
	sb.content_margin_top = 18
	sb.content_margin_bottom = 18
	p.add_theme_stylebox_override("panel", sb)
	return p


## Текст на нарисованной плашке: тёмная буква без обводки и по центру в обе
## стороны. Отдельным конструктором, потому что таких мест уже три — заставка,
## брифинг уровня, уведомление о задаче, — и расходиться им нельзя. Центр по
## вертикали здесь не украшение: панель держит высоту под три строки, и прижатая
## к верху короткая фраза оставляет под собой пустое кремовое поле.
static func plate_label(size: int = 34) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", PLATE_TEXT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## --- пропуск сцены ----------------------------------------------------------

const SKIP_SIZE := Vector2(268, 104)
const SKIP_PATCH := 34   ## поля 9-slice: перекрывают рамку и скругление
const SKIP_EDGE := 24    ## отступ от края экрана, поверх safe area


## Кнопка «Пропустить» в правом верхнем углу — одна на заставку и на диалог.
## Пропуск ищут в одном месте, поэтому вид и положение у него общие: сцена
## сообщает только, что именно считать пропуском.
##
## Добавляет себя в root сама: якоря и offsets Control пересчитывает от размера
## родителя, и выставлять их до add_child значит считать их от нуля.
static func add_skip_button(root: Control, action: Callable, text: String = "Пропустить") -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = SKIP_SIZE
	b.add_theme_font_size_override("font_size", 30)
	## Тёмная буква без обводки: плашка кремовая, а светлый текст с чёрным
	## контуром — набор для арта под ним, не для бумаги.
	for slot in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(slot, PLATE_TEXT)
	var tex := Backdrop.load_texture(PLATE)
	if tex != null:
		for style in ["normal", "hover", "pressed", "focus", "disabled"]:
			b.add_theme_stylebox_override(style, _skip_box(tex))
	b.pressed.connect(action)

	root.add_child(b)
	## Отступ от safe area, а не от края экрана: под вырезом кнопка видна, но не
	## нажимается, и игрок остаётся в сцене, из которой только что попросился.
	var inset := SafeArea.insets(root.get_viewport_rect().size)
	var right := int(inset["right"]) + SKIP_EDGE
	var top := int(inset["top"]) + SKIP_EDGE
	b.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	b.offset_left = -(SKIP_SIZE.x + right)
	b.offset_top = top
	b.offset_right = -right
	b.offset_bottom = top + SKIP_SIZE.y
	return b


static func _skip_box(tex: Texture2D) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.texture_margin_left = SKIP_PATCH
	sb.texture_margin_right = SKIP_PATCH
	sb.texture_margin_top = SKIP_PATCH
	sb.texture_margin_bottom = SKIP_PATCH
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	return sb


static func full_screen_dim(alpha: float = 0.72) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0.04, 0.04, 0.06, alpha)
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	return r


static func item_chip(item: ItemDefinition, item_id: String) -> Control:
	var box := VBoxContainer.new()
	## Полоса предметов не реагирует на тап сама: и в поиске, и в уборке решение
	## принимает уровень, а Control со STOP просто съел бы касание.
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.custom_minimum_size = Vector2(120, 0)

	var icon := TextureRect.new()
	icon.texture = PlaceholderArt.item_icon(item)
	icon.custom_minimum_size = Vector2(84, 84)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(icon)

	## Подпись тёмная и без обводки: полоса стоит на кремовой плашке, а светлый
	## текст с чёрным контуром рассчитан на арт под ним, не на бумагу.
	var name_label := Label.new()
	name_label.text = item.display_name if item != null else item_id
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.add_theme_color_override("font_color", PLATE_TEXT)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size = Vector2(120, 0)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name_label)
	return box
