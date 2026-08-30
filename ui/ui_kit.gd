class_name UIKit
extends RefCounted
## Минимальный набор конструкторов UI. Строим код-первым: для placeholder-этапа
## это быстрее .tscn и не мешает заменить всё на нормальный theme позже.
## Крупные touch-таргеты — не меньше MIN_TOUCH по короткой стороне.

const MIN_TOUCH := 96
const BG_DARK := Color(0.09, 0.09, 0.12, 0.86)
const BG_PANEL := Color(0.14, 0.13, 0.16, 0.94)
const ACCENT := Color(0.98, 0.73, 0.25)
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
