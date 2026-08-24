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
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.modulate.a = 0.0
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_toast)
	## Геометрия — строго после add_child. Без родителя его размер равен нулю,
	## offsets считаются от нуля, и якорь по правому краю уносит ноду за экран.
	_anchor_box(_toast, Control.PRESET_TOP_WIDE, 0, 140, 0, 200)

	if not OS.is_debug_build():
		return

	var toggle := UIKit.button("⚙", 30)
	toggle.custom_minimum_size = Vector2(84, 84)
	toggle.pressed.connect(func(): _debug_panel.visible = not _debug_panel.visible)
	root.add_child(toggle)
	_anchor_box(toggle, Control.PRESET_TOP_RIGHT, -104, 1180, -20, 1264)

	_debug_panel = UIKit.panel(Color(0.1, 0.1, 0.14, 0.96))
	_debug_panel.visible = false
	root.add_child(_debug_panel)
	_anchor_box(_debug_panel, Control.PRESET_TOP_RIGHT, -470, 1270, -20, 1270)

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


## Якоря + offsets явно, вместо position/size. Control пересчитывает offsets от
## размера родителя, поэтому вызывать это можно только когда нода уже в дереве.
func _anchor_box(c: Control, preset: int, l: float, t: float, r: float, b: float) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = l
	c.offset_top = t
	c.offset_right = r
	c.offset_bottom = b


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
