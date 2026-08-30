class_name LevelHUD
extends Control
## HUD гибридного уровня. Одна панель на обе фазы: меняется только содержимое
## нижней полосы (лоток пазла живёт в мире, список предметов — здесь).

const HINT_ICON := "res://art/ui_hand.png"

signal abandon_pressed
signal booster_pressed
signal narrative_finished
signal result_continue

var _title: Label
var _phase: Label
var _progress: Label
var _item_bar: HBoxContainer
var _item_panel: PanelContainer
var _booster: Button
var _narrative: Control
var _narrative_label: Label
var _result: Control
var _result_body: VBoxContainer
var _toast: Label

var _chips: Dictionary = {}
var _lines: PackedStringArray = PackedStringArray()
var _line_index: int = 0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()


func _build() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	SafeArea.apply(margin, 20)

	var root := VBoxContainer.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	# --- верхняя полоса ---
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)

	var back := UIKit.button("‹", 40)
	back.custom_minimum_size = Vector2(96, 96)
	back.pressed.connect(func(): abandon_pressed.emit())
	top.add_child(back)

	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(titles)
	_title = UIKit.label("", 34)
	_phase = UIKit.label("", 26, Color(0.85, 0.83, 0.8))
	titles.add_child(_title)
	titles.add_child(_phase)

	_progress = UIKit.label("", 30)
	_progress.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(_progress)

	# --- растяжка ---
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(spacer)

	_toast = UIKit.label("", 28, UIKit.ACCENT)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.modulate.a = 0.0
	root.add_child(_toast)

	# --- нижняя полоса: список искомых предметов + бустер ---
	## Полоса предметов стоит на нарисованной плашке — той же, что у уведомлений.
	_item_panel = UIKit.plate("res://art/ui/taskbar_notification.png")
	_item_panel.visible = false
	## Панель — подложка, а не кнопка: касание по ней должно доходить до уровня,
	## иначе перетащить предмет из полосы невозможно в принципе.
	_item_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_item_panel)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	_item_panel.add_child(bottom)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 150)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(scroll)

	_item_bar = HBoxContainer.new()
	_item_bar.add_theme_constant_override("separation", 10)
	scroll.add_child(_item_bar)

	## Подсказка в этой игре — курсор, который показывает, что делать. Кнопка
	## носит его же, а не лампочку: иначе иконка обещает одно, а даёт другое.
	_booster = UIKit.button("", 32)
	_booster.icon = Backdrop.load_texture(HINT_ICON)
	_booster.expand_icon = true
	_booster.custom_minimum_size = Vector2(120, 120)
	_booster.pressed.connect(func(): booster_pressed.emit())
	bottom.add_child(_booster)

	_build_narrative()
	_build_result()


func _build_narrative() -> void:
	_narrative = UIKit.full_screen_dim(0.62)
	_narrative.visible = false
	add_child(_narrative)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	_narrative.add_child(margin)
	SafeArea.apply(margin, 40)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_END
	box.add_theme_constant_override("separation", 20)
	margin.add_child(box)

	var panel := UIKit.panel()
	box.add_child(panel)
	_narrative_label = UIKit.label("", 34)
	_narrative_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_narrative_label.custom_minimum_size = Vector2(0, 200)
	panel.add_child(_narrative_label)

	var next := UIKit.button("Далее", 34)
	next.pressed.connect(_advance_narrative)
	box.add_child(next)


func _build_result() -> void:
	_result = UIKit.full_screen_dim(0.78)
	_result.visible = false
	add_child(_result)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result.add_child(margin)
	SafeArea.apply(margin, 40)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 20)
	margin.add_child(box)

	var panel := UIKit.panel()
	box.add_child(panel)
	_result_body = VBoxContainer.new()
	_result_body.add_theme_constant_override("separation", 10)
	panel.add_child(_result_body)

	var cont := UIKit.button("Продолжить", 36)
	cont.pressed.connect(func():
		_result.visible = false
		result_continue.emit())
	box.add_child(cont)


## --- API --------------------------------------------------------------------

func set_level_title(text: String) -> void:
	_title.text = text


func set_phase(text: String) -> void:
	_phase.text = text


func set_progress(done: int, total: int) -> void:
	_progress.text = "%d / %d" % [done, total]


## Счётчик частей игроку не нужен: пазл и так видно целиком, а «5 / 6» превращает
## сборку в отчёт о работе. В фазе поиска предметов счётчик остаётся — там
## сказать, сколько ещё искать, больше нечем.
func show_progress(on: bool) -> void:
	_progress.visible = on


func set_booster_count(n: int) -> void:
	_booster.text = "%d" % n
	_booster.disabled = n <= 0


func show_items(targets: Array[HOTarget], items: Dictionary) -> void:
	for c in _item_bar.get_children():
		c.queue_free()
	_chips.clear()
	for t in targets:
		var chip := UIKit.item_chip(items.get(t.item_id), t.item_id)
		_item_bar.add_child(chip)
		_chips[t.id] = chip
	_item_panel.visible = true


## Полоса предметов по item_id — для фазы уборки, где предмет не «цель поиска»,
## а то, что игрок тащит. Ключ здесь item_id: целей в этой фазе нет.
func show_item_row(item_ids: PackedStringArray, items: Dictionary) -> void:
	for c in _item_bar.get_children():
		c.queue_free()
	_chips.clear()
	for id in item_ids:
		var chip := UIKit.item_chip(items.get(String(id)), String(id))
		_item_bar.add_child(chip)
		_chips[String(id)] = chip
	_item_panel.visible = true


## Чип «ещё не найден»: предмет виден силуэтом, чтобы игрок знал, что искать,
## но не считал его уже своим. Загорается в тот момент, когда найден.
func set_chip_dim(key: String, dim: bool) -> void:
	var chip: Control = _chips.get(key)
	if chip == null:
		return
	if not dim:
		chip.pivot_offset = chip.size * 0.5
		chip.modulate = Color.WHITE
		chip.scale = Vector2(1.35, 1.35)
		chip.create_tween().tween_property(chip, "scale", Vector2.ONE, 0.3) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		return
	chip.modulate = Color(0.28, 0.28, 0.30, 0.75)


## Экранный прямоугольник чипа. Нужен подсказкам и прогону, чтобы понять, что
## предмет действительно ушёл из полосы.
func chip_rect(key: String) -> Rect2:
	var chip: Control = _chips.get(key)
	return chip.get_global_rect() if chip != null else Rect2()


## Предмет использован: чип сжимается и уходит.
func take_chip(key: String) -> void:
	var chip: Control = _chips.get(key)
	if chip == null:
		return
	_chips.erase(key)
	chip.pivot_offset = chip.size * 0.5
	var tw := chip.create_tween().set_parallel(true)
	tw.tween_property(chip, "modulate:a", 0.0, 0.22)
	tw.tween_property(chip, "scale", Vector2(0.55, 0.55), 0.22)
	tw.chain().tween_callback(chip.queue_free)


func hide_items() -> void:
	_item_panel.visible = false


func mark_found(target_id: String) -> void:
	var chip: Control = _chips.get(target_id)
	if chip == null:
		return
	chip.modulate = Color(0.4, 0.4, 0.4, 0.55)


func toast(text: String) -> void:
	_toast.text = text
	_toast.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(1.1)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.5)


func show_narrative(lines: PackedStringArray) -> void:
	_lines = lines
	_line_index = 0
	if _lines.is_empty():
		narrative_finished.emit()
		return
	_narrative.visible = true
	_narrative_label.text = _lines[0]


func _advance_narrative() -> void:
	_line_index += 1
	if _line_index >= _lines.size():
		_narrative.visible = false
		narrative_finished.emit()
		return
	_narrative_label.text = _lines[_line_index]


func show_result(result: LevelResult, items: Dictionary) -> void:
	for c in _result_body.get_children():
		c.queue_free()
	_result_body.add_child(UIKit.label("Уровень пройден", 40, UIKit.ACCENT))
	_result_body.add_child(UIKit.label("Монеты: +%d" % result.soft_currency, 32))
	_result_body.add_child(UIKit.label("Опыт: +%d" % result.xp, 32))
	if result.replay:
		_result_body.add_child(UIKit.label("Повтор: награда снижена, сюжетные предметы не выдаются", 24))
	if not result.quest_items.is_empty():
		_result_body.add_child(UIKit.label("Сюжетные предметы:", 30, UIKit.ACCENT))
		for item_id in result.quest_items:
			var it: ItemDefinition = items.get(item_id)
			_result_body.add_child(UIKit.label("• " + (it.display_name if it != null else item_id), 28))
	_result.visible = true
