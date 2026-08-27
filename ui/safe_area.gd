class_name SafeArea
extends RefCounted
## Вырезы и системные полосы. На десктопе safe area == экран, поэтому отступы
## нулевые и разработка не отличается от мобильной сборки.

static func insets(viewport_size: Vector2) -> Dictionary:
	var zero := {"left": 0, "top": 0, "right": 0, "bottom": 0}
	var screen := DisplayServer.screen_get_size()
	if screen.x <= 0 or screen.y <= 0:
		return zero
	var safe := DisplayServer.get_display_safe_area()
	if safe.size.x <= 0 or safe.size.y <= 0:
		return zero
	var sx := viewport_size.x / float(screen.x)
	var sy := viewport_size.y / float(screen.y)
	return {
		"left": int(maxf(0.0, safe.position.x * sx)),
		"top": int(maxf(0.0, safe.position.y * sy)),
		"right": int(maxf(0.0, (screen.x - safe.end.x) * sx)),
		"bottom": int(maxf(0.0, (screen.y - safe.end.y) * sy)),
	}


## extra_bottom — место под то, что стоит поверх экрана по низу (полоса
## инвентаря). Отдельным параметром, а не общим extra: сверху столько отступа
## не нужно, и раздувать его симметрично значит терять пол-экрана.
static func apply(container: MarginContainer, extra: int = 24, extra_bottom: int = 0) -> void:
	var i := insets(container.get_viewport_rect().size)
	container.add_theme_constant_override("margin_left", int(i["left"]) + extra)
	container.add_theme_constant_override("margin_top", int(i["top"]) + extra)
	container.add_theme_constant_override("margin_right", int(i["right"]) + extra)
	container.add_theme_constant_override("margin_bottom", int(i["bottom"]) + extra + extra_bottom)
