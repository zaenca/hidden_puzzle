extends Node
## Точка входа. Держит корень экранов и debug-оверлей.

@onready var _screen_root: Node2D = $ScreenRoot
@onready var _overlay: CanvasLayer = $Overlay

var _toast: Label
var _debug_panel: Control
var _inventory: InventoryBar
var _notification: TaskNotification
var _journal: TaskJournal
var _wallet: WalletBar
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
	Game.screen_changed.connect(_on_screen_changed)
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

	## Инвентарь — в оверлее, а не в сцене экрана: он переживает переходы
	## карта ↔ локация, поэтому и предмет «в руке» не теряется на переходе.
	_inventory = InventoryBar.new()
	_inventory.name = "InventoryBar"
	root.add_child(_inventory)
	_inventory.set_active(false)
	Game.attach_inventory(_inventory)

	## Плашка «задание выполнено» — тоже в оверлее и по той же причине: задача
	## закрывается ровно на стыке экранов, и в сцене это событие некому поймать.
	_notification = TaskNotification.new()
	_notification.name = "TaskNotification"
	root.add_child(_notification)
	_notification.set_active(false)

	## Журнал заданий — тоже в оверлее: путь игрока не принадлежит ни карте, ни
	## локации, и в сцене его пришлось бы собирать заново на каждом переходе.
	_journal = TaskJournal.new()
	_journal.name = "TaskJournal"
	root.add_child(_journal)
	_journal.set_active(false)

	## Кошелёк — тоже в оверлее: деньги не принадлежат экрану, и собранный в
	## сцене счёт пришлось бы повторять в карте, локации и магазине.
	_wallet = WalletBar.new()
	_wallet.name = "WalletBar"
	root.add_child(_wallet)
	_wallet.set_active(false)

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
	## Заставка и разговор с мэром — одна сцена завязки: игрок в ней ничего не
	## решает, а на две кнопки она делилась только потому, что внутри две сцены.
	col.add_child(_debug_button("Интро", func():
		_debug_panel.visible = false
		Game.replay_intro()))
	col.add_child(_debug_button("Пекарня: фасад + хозяйка", func():
		_debug_panel.visible = false
		Game.open_intro("bakery_facade")))
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


## На уровне снизу стоит лоток пазла и список искомых предметов — инвентарь
## туда не помещается и там не нужен. Он ждёт возвращения в мету вместе с
## наградой, которую ещё не показал.
func _on_screen_changed(screen: int) -> void:
	var in_meta := screen == Game.Screen.MAP or screen == Game.Screen.SHOP
	if _inventory != null:
		_inventory.set_active(in_meta)
	if _notification != null:
		_notification.set_active(in_meta)
	## Журнал держится там, где игрок решает, чем заняться, — на карте и в
	## локации. На уровне слева вверху стоит выход, и вторая кнопка в том же
	## углу читалась бы как второй выход.
	if _journal != null:
		_journal.set_active(in_meta)
	if _wallet != null:
		_wallet.set_active(in_meta)


func _show_toast(text: String) -> void:
	_toast.text = text
	_toast.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(1.2)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.5)
