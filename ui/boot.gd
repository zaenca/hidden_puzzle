extends Node
## Точка входа. Держит корень экранов и debug-оверлей.

@onready var _screen_root: Node2D = $ScreenRoot
@onready var _overlay: CanvasLayer = $Overlay

var _toast: Label
var _debug_panel: Control
var _autoplay: AutoplayDriver = null


var _dbg_lines: PackedStringArray = PackedStringArray()


## Диагностика в файл: консольный вывод при перенаправлении буферизуется,
## а зависший старт иначе не отладить.
func _dbg(msg: String) -> void:
	if not OS.is_debug_build():
		return
	_dbg_lines.append(msg)
	var f := FileAccess.open("res://boot_log.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_dbg_lines))
		f.close()


func _ready() -> void:
	_dbg("ready; args=%s; user_args=%s" % [OS.get_cmdline_args(), OS.get_cmdline_user_args()])
	Game.attach(_screen_root)
	_build_overlay()
	EventBus.toast.connect(_show_toast)
	_dbg("overlay ok")
	Game.boot()
	_dbg("Game.boot ok; screen=%d" % Game.screen)

	if _wants_autoplay():
		_dbg("autoplay start")
		# Ссылку надо держать: RefCounted-драйвер иначе освобождается сразу
		# после вызова, и корутина не возобновляется.
		_autoplay = AutoplayDriver.new()
		_autoplay.run(get_tree())
	else:
		_dbg("autoplay NOT requested")


func _wants_autoplay() -> bool:
	return OS.get_cmdline_user_args().has("--autoplay") or OS.get_cmdline_args().has("--autoplay")


func _build_overlay() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(root)

	_toast = UIKit.label("", 30, UIKit.ACCENT)
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.position = Vector2(0, 140)
	_toast.size = Vector2(1080, 60)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.modulate.a = 0.0
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_toast)

	if not OS.is_debug_build():
		return

	var toggle := UIKit.button("⚙", 30)
	toggle.custom_minimum_size = Vector2(84, 84)
	toggle.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	toggle.position = Vector2(1080 - 100, 1180)
	toggle.pressed.connect(func(): _debug_panel.visible = not _debug_panel.visible)
	root.add_child(toggle)

	_debug_panel = UIKit.panel(Color(0.1, 0.1, 0.14, 0.96))
	_debug_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_debug_panel.position = Vector2(1080 - 470, 1270)
	_debug_panel.size = Vector2(450, 0)
	_debug_panel.visible = false
	root.add_child(_debug_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_debug_panel.add_child(col)
	col.add_child(UIKit.label("DEBUG", 26, UIKit.ACCENT))
	col.add_child(_debug_button("Сброс прогресса", func(): Game.hard_reset()))
	col.add_child(_debug_button("+50 ◆ hard", func(): MockServices.purchase("debug_pack", 50)))
	col.add_child(_debug_button("+3 💡 бустера", func(): PlayerState.grant("booster_hint", 3)))
	col.add_child(_debug_button("Перемотать 10 мин", func():
		TimeService.fast_forward(600)
		EventBus.toast.emit("Время +10 минут")))
	col.add_child(_debug_button("Сохранить", func():
		SaveService.save_game()
		EventBus.toast.emit("Сохранено")))
	col.add_child(UIKit.label("В уровне: S — собрать пазл, F — найти всё", 20))


func _debug_button(text: String, action: Callable) -> Button:
	var b := UIKit.button(text, 24)
	b.custom_minimum_size = Vector2(0, 70)
	b.pressed.connect(action)
	return b


func _show_toast(text: String) -> void:
	_toast.text = text
	_toast.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(1.2)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.5)
