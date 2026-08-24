class_name UIKit
extends RefCounted
## Минимальный набор конструкторов UI. Строим код-первым: для placeholder-этапа
## это быстрее .tscn и не мешает заменить всё на нормальный theme позже.
## Крупные touch-таргеты — не меньше MIN_TOUCH по короткой стороне.

const MIN_TOUCH := 96
const BG_DARK := Color(0.09, 0.09, 0.12, 0.86)
const BG_PANEL := Color(0.14, 0.13, 0.16, 0.94)
const ACCENT := Color(0.98, 0.73, 0.25)


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


static func full_screen_dim(alpha: float = 0.72) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0.04, 0.04, 0.06, alpha)
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	return r


static func item_chip(item: ItemDefinition, item_id: String) -> Control:
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.custom_minimum_size = Vector2(120, 0)

	var icon := TextureRect.new()
	icon.texture = PlaceholderArt.item_icon(item)
	icon.custom_minimum_size = Vector2(84, 84)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(icon)

	var name_label := label(item.display_name if item != null else item_id, 22)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size = Vector2(120, 0)
	box.add_child(name_label)
	return box
