extends GameplayModule
## Sort — основной core игры. Игрок снимает предметы с кадра в лоток; три
## предмета одной категории закрываются сами и освобождают ячейки.
##
## Модуль знает только SortDefinition. Ни пекарни, ни Марго, ни кошелька, ни
## задач: он получает раскладку и возвращает LevelResult. Второй, третий и
## десятый Sort-уровни — это другой JSON и тот же самый файл.

const SCREEN := Vector2(1080, 1920)

## Верхняя полоса под заголовок и кнопку выхода. Поле начинается под ней:
## предмет, наполовину заехавший под HUD, нельзя ни увидеть, ни нажать.
const HUD_HEIGHT := 168.0
const TRAY_HEIGHT := 290.0
const TRAY_BOTTOM_PAD := 36.0
const EDGE_PAD := 26.0
const PLAY_TRAY_GAP := 22.0
## Насколько фон заходит под лоток. Лоток нарисован плашкой со скруглениями, и
## ровно по его верхней кромке под ним просвечивал бы пустой экран.
const BACKGROUND_UNDER_TRAY := 90.0
## Куда именно обучающая рука целится внутри предмета — доля его размера от
## центра. Не в середину: см. `_tutorial_targets`.
const HINT_AIM_OFFSET := Vector2(0.30, 0.30)

## Раскрытие зоны: затемнение уходит, и содержимое проявляется вслед за ним,
## по одному предмету. Дольше — и ход игрока повисает; короче — и связь между
## снятой коробкой и появившимися вещами не читается.
const ZONE_OPEN_SEC := 0.32
const ZONE_REVEAL_STEP := 0.07

const FLY_SEC := 0.30
const GROUP_FLASH_SEC := 0.30
const GROUP_VANISH_SEC := 0.24
const REFLOW_SEC := 0.20
## Разобранный фасад держится на экране — это и есть награда за уровень.
## Экрана результата у Sort нет: он бы перебил ровно тот кадр, ради которого
## всё и делалось.
const PAYOFF_SEC := 0.9
const FADE_OUT_SEC := 0.35

@onready var _background: Sprite2D = $Background
@onready var _board: Node2D = $Board
@onready var _tray_items: Node2D = $TrayItems
@onready var _tray: SortTray = $Tray
@onready var _fx: Node2D = $FX
@onready var _ui: CanvasLayer = $UI
@onready var _hud: Control = $UI/Hud

var context: LevelContext
var definition: LevelDefinition
var sort: SortDefinition

var play_rect: Rect2 = Rect2()
var tray_rect: Rect2 = Rect2()

var _state: SortState = SortState.new()
var _views: Dictionary = {}        ## instance_id -> SortItemView
var _zone_views: Dictionary = {}   ## zone_id -> SortZoneView (только закрытые)
var _tutorial: SortTutorial = null

var _title: Label
var _counter: Label
var _fail_panel: Control

var _input_locked: bool = false    ## проигрыш, победа, уход в мету
var _animations: int = 0           ## идущих схлопываний группы
var _picks: int = 0
var _refused: int = 0              ## тапов по придавленным предметам
var _zone_refused: int = 0         ## тапов по закрытым зонам
var _restarts: int = 0
var _tutorial_done: bool = false
var _started_msec: int = 0


func setup(ctx: LevelContext) -> void:
	context = ctx
	if ctx == null or ctx.definition == null or ctx.definition.sort == null:
		push_error("SortModule: уровень без SortDefinition")
		abandoned.emit()
		return
	definition = ctx.definition
	sort = definition.sort
	if not is_node_ready():
		await ready
	## Состояние поднимается первым: HUD и лоток рисуют по нему счётчик и
	## свободные ячейки, и построенные раньше него они читали бы пустоту.
	_state.setup(sort)
	_layout()
	_build_background()
	_tray.setup(tray_rect, sort.tray_size)
	_build_hud()
	_build_board()
	_build_tutorial()
	_started_msec = Time.get_ticks_msec()


## --- разметка ---------------------------------------------------------------

## Поле считается от экрана, а не от картинки фона. Фон кладётся по обрезке и
## на другом соотношении сторон уезжает за края вместе со всем, что было бы к
## нему привязано; поле же обязано целиком оставаться видимым и нажимаемым.
func _layout() -> void:
	var insets := SafeArea.insets(SCREEN)
	var top: float = float(insets["top"]) + HUD_HEIGHT
	var tray_top: float = SCREEN.y - float(insets["bottom"]) - TRAY_BOTTOM_PAD - TRAY_HEIGHT
	tray_rect = Rect2(EDGE_PAD, tray_top, SCREEN.x - EDGE_PAD * 2.0, TRAY_HEIGHT)
	play_rect = Rect2(EDGE_PAD, top, SCREEN.x - EDGE_PAD * 2.0,
		tray_top - PLAY_TRAY_GAP - top)


## Фон встаёт по игровому полю, а не по экрану: низ картинки прижат к лотку.
## Внизу кадра нарисовано то, на чём предметы лежат — ступени, пол, мостовая, —
## и при выравнивании по экрану эта часть уезжает под интерфейс. Тогда «на
## полу» становится негде, и предметы приходится вешать в воздухе.
func _build_background() -> void:
	var tex := Backdrop.load_texture(definition.art.background_path)
	if tex != null:
		Backdrop.cover_above(_background, tex, SCREEN, tray_rect.position.y + BACKGROUND_UNDER_TRAY)
	else:
		Backdrop.gradient(_background, definition.art.palette, SCREEN)


## --- HUD --------------------------------------------------------------------

func _build_hud() -> void:
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_TOP_WIDE)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(margin)
	SafeArea.apply(margin, 20)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)

	var back := UIKit.plate_button("‹", 40)
	back.custom_minimum_size = Vector2(96, 96)
	back.pressed.connect(func(): abandoned.emit())
	row.add_child(back)

	_title = UIKit.label(definition.title, 34)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_title)

	## Счётчик — единственная цифра на экране. Он отвечает на вопрос «сколько
	## ещё», который в Sort возникает сам собой: поле видно целиком, но пересчёт
	## двенадцати предметов глазами — работа, а не игра.
	_counter = UIKit.label("", 32)
	_counter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_counter)

	_build_fail_panel()
	_update_hud()


func _update_hud() -> void:
	if _counter != null:
		_counter.text = "%d / %d" % [sort.items.size() - _state.remaining(), sort.items.size()]
	_tray.set_free_slots(_state.tray_free())


## Проигрыш не уводит с уровня и не открывает экран отчёта: единственное, чего
## игрок хочет после переполненного лотка, — попробовать ещё раз, и кнопка
## должна быть ровно одна.
func _build_fail_panel() -> void:
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	box.visible = false
	_hud.add_child(box)
	box.position = Vector2((SCREEN.x - 760.0) * 0.5, SCREEN.y * 0.32)
	box.size = Vector2(760, 0)
	_fail_panel = box

	var plate := UIKit.plate(UIKit.PLATE)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(plate)
	var text := UIKit.plate_label(34)
	text.text = "Лоток переполнен. Попробуем ещё раз."
	text.custom_minimum_size = Vector2(690, 110)
	plate.add_child(text)

	var center := CenterContainer.new()
	box.add_child(center)
	var again := UIKit.plate_button("Заново", 34)
	again.custom_minimum_size = Vector2(320, 108)
	again.pressed.connect(restart)
	center.add_child(again)


## --- поле -------------------------------------------------------------------

func _build_board() -> void:
	for c in _board.get_children():
		c.queue_free()
	for c in _tray_items.get_children():
		c.queue_free()
	_views.clear()
	_zone_views.clear()
	_state.setup(sort)

	for inst in sort.items:
		var view := SortItemView.new()
		view.position = play_rect.position + inst.position * play_rect.size
		## Верхние слои завала рисуются поверх нижних и первыми же ловят тап:
		## иначе предмет, который лежит сверху, можно было бы «прокликать».
		view.z_index = inst.layer
		_board.add_child(view)
		view.setup(inst, context.items.get(inst.item_id), sort.category_color(inst.category),
			inst.size * play_rect.size.x)
		_views[inst.id] = view
		## Что лежит в закрытой зоне, игрок не видит: зона закрыта именно этим.
		view.visible = _state.is_zone_open_for(inst.id)
		_dim_blocked(inst.id)

	_build_zones()

	_input_locked = false
	_animations = 0
	if _fail_panel != null:
		_fail_panel.visible = false
	_tray.modulate.a = 1.0
	_tray_items.modulate.a = 1.0
	if _counter != null:
		_counter.modulate.a = 1.0
	_update_hud()


## Закрытые зоны рисуются поверх своего содержимого, но под тем, что на них
## стоит: коробки видны, а то, что под ними, — нет, и именно это игрок и должен
## прочитать с экрана.
func _build_zones() -> void:
	for zone in _state.closed_zones():
		var view := SortZoneView.new()
		view.z_index = 0
		_board.add_child(view)
		view.setup(Rect2(play_rect.position + zone.rect.position * play_rect.size,
			zone.rect.size * play_rect.size), zone.color, zone.label)
		_zone_views[zone.id] = view


## Зона открывается сама, как только с неё снято последнее, что её держало.
## Отдельной кнопки «открыть» нет намеренно: правило то же, что у придавленного
## предмета, и второе действие поверх него игроку пришлось бы объяснять.
func _refresh_zones() -> void:
	for zone_id in _zone_views.keys():
		if not _state.is_zone_open(String(zone_id)):
			continue
		var view: SortZoneView = _zone_views[zone_id]
		_zone_views.erase(zone_id)
		if is_instance_valid(view):
			view.open(ZONE_OPEN_SEC)
		_reveal_zone_items(String(zone_id))


## Содержимое открывшейся зоны проявляется по одному. Разом появившиеся четыре
## предмета читаются как подставленные движком; вразнобой — как то, что там и
## лежало, просто до него дошли руки.
func _reveal_zone_items(zone_id: String) -> void:
	var zone := sort.zone(zone_id)
	if zone == null:
		return
	var step := 0
	for id in zone.items:
		var view: SortItemView = _views.get(String(id))
		if view == null or view.visible:
			continue
		view.reveal(ZONE_OPEN_SEC, step * ZONE_REVEAL_STEP)
		step += 1


## Тап по закрытой зоне. Ход не проходит, но ответ игрок получает, и ответ
## показывает причину: подрагивает сама зона, подсвечивается то, что на ней
## стоит. Первый такой тап приносит единственную подсказку про зоны.
func _refuse_zone(zone: SortZone) -> void:
	var view: SortZoneView = _zone_views.get(zone.id)
	if view != null:
		view.refuse_feedback()
	for id in zone.blocked_by:
		var blocker: SortItemView = _views.get(String(id))
		if blocker != null and _state.on_board(String(id)):
			blocker.hint_flash()
	_zone_refused += 1
	if _tutorial != null and _zone_refused == 1:
		_tutorial.notify_event("first_locked_zone_attempt", _zone_targets(zone))


## Куда показывает рука в подсказке про зону: на то, что зону держит, а не на
## саму зону — нажимать надо туда.
func _zone_targets(zone: SortZone) -> Dictionary:
	var out := _tutorial_targets()
	for id in zone.blocked_by:
		var blocker: SortItemView = _views.get(String(id))
		if blocker != null and _state.on_board(String(id)):
			out["blocker"] = blocker.position + blocker.drawn_size() * HINT_AIM_OFFSET
			break
	return out


## Недоступный предмет приглушён. Молча не реагировать на тап нельзя: игрок
## решит, что не попал, и будет бить в то же место.
func _dim_blocked(instance_id: String) -> void:
	var view: SortItemView = _views.get(instance_id)
	if view == null or view.revealing:
		return
	view.modulate = Color.WHITE if _state.is_available(instance_id) else Color(0.62, 0.62, 0.66, 0.9)


func _refresh_blocked() -> void:
	for id in _views:
		if _state.on_board(String(id)):
			_dim_blocked(String(id))


func _build_tutorial() -> void:
	if context.tutorial_steps.is_empty():
		return
	_tutorial = SortTutorial.new()
	add_child(_tutorial)
	## Подсказка стоит вверху, под заголовком. Над лотком её ставить нельзя:
	## нижняя часть кадра — это пол, там лежит половина предметов, и объяснение
	## накрывало бы ровно то, что объясняет.
	_tutorial.setup(context.tutorial_steps, _fx, _hud, play_rect.position.y + 12.0)
	_tutorial.finished.connect(func(): _tutorial_done = true)
	_tutorial.notify_event("level_started", _tutorial_targets())


## Куда обучение показывает рукой. Точки живут здесь, а не в обучении: где
## лежит доступный предмет, знает только уровень.
##
## Показываем не первый по списку, а ближайший к середине поля. Порядок в
## данных — это порядок авторской записи, и первым там легко оказывается
## предмет у самого края: палец, ткнувший в угол экрана, читается как «нажми
## куда-нибудь там», а не как «нажми вот на это».
## blocked_id — предмет, по которому игрок только что не смог тапнуть. Тогда в
## целях появляется "blocker": рука показывает не на то, что игрок хотел взять,
## а на то, что ему мешает, — потому что нажимать надо именно туда.
func _tutorial_targets(blocked_id: String = "") -> Dictionary:
	var out := {"tray": _tray.slot_center(0)}
	var view := _hint_view()
	if view != null:
		## Целимся не в центр предмета, а в его правый нижний край. Рука и круг
		## от нажатия расходятся вниз-вправо от кончика пальца, и поставленный в
		## середину палец закрывает собой ровно то, на что показывает.
		out["item"] = view.position + view.drawn_size() * HINT_AIM_OFFSET
	if not blocked_id.is_empty():
		var blockers := _blockers_of(blocked_id)
		if not blockers.is_empty():
			var top: SortItemView = _views.get(String(blockers[0]))
			if top != null:
				out["blocker"] = top.position + top.drawn_size() * HINT_AIM_OFFSET
	return out


func _hint_view() -> SortItemView:
	var center := play_rect.get_center()
	var best: SortItemView = null
	var best_dist := INF
	for id in _state.available_ids():
		var view: SortItemView = _views.get(String(id))
		if view == null:
			continue
		var d: float = view.position.distance_to(center)
		if d < best_dist:
			best_dist = d
			best = view
	return best


## --- ввод -------------------------------------------------------------------

## Тап, а не нажатие мыши: в проекте включена эмуляция касаний от мыши,
## поэтому один обработчик обслуживает и телефон, и отладку на десктопе.
func _unhandled_input(event: InputEvent) -> void:
	if _input_locked:
		return
	if not (event is InputEventScreenTouch) or not event.pressed:
		return
	var world: Vector2 = get_canvas_transform().affine_inverse() * event.position
	var hit := _hit_test(world)
	if not hit.is_empty():
		_on_pick(hit)
		return
	## Мимо предметов — но, возможно, по закрытой зоне. Она ловит тап сама:
	## внутри неё ничего не нарисовано, и без этого тап по ящику с вещами
	## означал бы ровно ничего.
	var zone := _zone_at(world)
	if zone != null:
		_refuse_zone(zone)


## Верхние предметы забирают тап первыми. Внутри одного слоя выигрывает тот,
## чей центр ближе: перекрытие двух кругов иначе достаётся тому, кто просто
## позже добавлен в дерево.
func _hit_test(world: Vector2) -> String:
	var best := ""
	var best_layer := -9999
	var best_dist := INF
	for id in _views:
		if not _state.on_board(String(id)):
			continue
		var view: SortItemView = _views[id]
		## Спрятанное в закрытой зоне тап не ловит: его на экране нет, и
		## попадание по невидимому было бы попаданием наугад.
		if not view.visible:
			continue
		if not view.contains_point(world):
			continue
		var layer: int = view.instance.layer
		var dist: float = view.position.distance_to(world)
		if layer > best_layer or (layer == best_layer and dist < best_dist):
			best = String(id)
			best_layer = layer
			best_dist = dist
	return best


## Закрытая зона под точкой тапа, если она там есть.
func _zone_at(world: Vector2) -> SortZone:
	for zone_id in _zone_views:
		var view: SortZoneView = _zone_views[zone_id]
		if is_instance_valid(view) and view.contains_point(world):
			return sort.zone(String(zone_id))
	return null


func _on_pick(instance_id: String) -> void:
	var view: SortItemView = _views.get(instance_id)
	if view == null:
		return

	## Придавленный предмет отвечает отказом, а не сжатием: сжатие — это «взял»,
	## и одинаковая реакция на взятое и на невзятое врёт игроку о правилах.
	if _state.on_board(instance_id) and not _state.is_available(instance_id):
		_refuse(instance_id, view)
		return

	view.press_feedback()

	var res := _state.pick(instance_id)
	if not bool(res["ok"]):
		return

	_picks += 1
	_send_to_tray(view)
	## Зоны раньше приглушения: снятая коробка могла открыть целое место, и
	## появившиеся из него предметы должны сразу получить верный вид.
	_refresh_zones()
	_refresh_blocked()
	_update_hud()
	_notify_tutorial()

	var cleared: PackedStringArray = res["cleared"]
	if cleared.is_empty():
		_reflow_tray()
	else:
		_collapse_group(cleared)

	if bool(res["complete"]):
		_finish_success()
	elif bool(res["failed"]):
		_fail()


## Тап по накрытому предмету. Ход не проходит, но ответ игрок получает, и
## ответ этот показывает ПРИЧИНУ: качается придавленный, подсвечивается тот,
## кто его держит. Двойная блокировка подсвечивает обоих — иначе игрок уберёт
## одного и снова упрётся, не понимая, почему.
func _refuse(instance_id: String, view: SortItemView) -> void:
	view.refuse_feedback()
	for id in _blockers_of(instance_id):
		var blocker: SortItemView = _views.get(String(id))
		if blocker != null:
			blocker.hint_flash()
	_refused += 1
	if _tutorial != null and _refused == 1:
		_tutorial.notify_event("first_blocked_item_attempt", _tutorial_targets(instance_id))


## Кто прямо сейчас держит предмет: из накрывающих его берутся только те, что
## ещё лежат на поле. Ушедшие в лоток уже ничего не держат, и подсвечивать
## пустое место значит показывать не на того.
func _blockers_of(instance_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	var inst := sort.item(instance_id)
	if inst == null:
		return out
	for blocker in inst.blocked_by:
		if _state.on_board(String(blocker)):
			out.append(String(blocker))
	return out


func _notify_tutorial() -> void:
	if _tutorial == null:
		return
	var targets := _tutorial_targets()
	if _picks == 1:
		_tutorial.notify_event("first_item_picked", targets)
	elif _picks == 2:
		_tutorial.notify_event("second_item_picked", targets)
	if _state.tray_free() <= SortTray.WARN_FREE_SLOTS:
		_tutorial.notify_event("tray_warning", targets)


## --- лоток ------------------------------------------------------------------

func _send_to_tray(view: SortItemView) -> void:
	## Тот же самый узел переезжает в лоток. Поле и лоток стоят в одних
	## координатах, поэтому перенос ничего не сдвигает — а игрок видит, что в
	## ячейку легла именно та вещь, по которой он нажал.
	_board.remove_child(view)
	_tray_items.add_child(view)
	view.z_index = 0
	var index: int = _state.tray.find(view.instance.id)
	view.fly_to(_tray.slot_center(maxi(0, index)), _tray.slot_diameter, FLY_SEC)
	_settle_after(view, FLY_SEC)


func _settle_after(view: SortItemView, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	if is_instance_valid(view):
		view.settle(_tray.slot_diameter)


## Ячейки схлопываются: после закрытой группы оставшиеся предметы съезжают
## влево. Дырки в середине лотка врут о том, сколько места осталось.
func _reflow_tray() -> void:
	for i in _state.tray.size():
		var view: SortItemView = _views.get(String(_state.tray[i]))
		if view != null and view.get_parent() == _tray_items:
			view.slide_to(_tray.slot_center(i), REFLOW_SEC)


func _collapse_group(ids: PackedStringArray) -> void:
	_animations += 1
	for id in ids:
		var view: SortItemView = _views.get(String(id))
		if view != null:
			view.flash()
	await get_tree().create_timer(GROUP_FLASH_SEC).timeout
	if not is_inside_tree():
		return
	for id in ids:
		var view: SortItemView = _views.get(String(id))
		if view != null:
			view.vanish(GROUP_VANISH_SEC)
		_views.erase(String(id))
	await get_tree().create_timer(GROUP_VANISH_SEC).timeout
	if not is_inside_tree():
		return
	_reflow_tray()
	_update_hud()
	_animations -= 1


## --- проигрыш и перезапуск --------------------------------------------------

func _fail() -> void:
	_input_locked = true
	if _tutorial != null:
		_tutorial.stop()
	await _settle_animations()
	if not is_inside_tree():
		return
	_fail_panel.visible = true
	_fail_panel.modulate.a = 0.0
	_fail_panel.create_tween().tween_property(_fail_panel, "modulate:a", 1.0, 0.25)


## Та же раскладка, тот же seed. «Заново» обязано вернуть ровно тот уровень, на
## котором игрок ошибся, — иначе он не проверяет свою догадку, а играет заново
## во что-то другое. Мета при этом не трогается: проигрыш ничего не менял.
func restart() -> void:
	_restarts += 1
	_build_board()
	if _tutorial != null:
		_tutorial.notify_event("level_started", _tutorial_targets())


## --- победа -----------------------------------------------------------------

func _finish_success() -> void:
	_input_locked = true
	if _tutorial != null:
		_tutorial.stop()
	await _settle_animations()
	if not is_inside_tree():
		return

	## Лоток пуст и больше не нужен: он уходит, оставляя игроку чистый кадр.
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_tray, "modulate:a", 0.0, 0.3)
	tw.tween_property(_tray_items, "modulate:a", 0.0, 0.3)
	if _counter != null:
		tw.tween_property(_counter, "modulate:a", 0.0, 0.3)
	await tw.finished
	if not is_inside_tree():
		return

	await get_tree().create_timer(PAYOFF_SEC).timeout
	if not is_inside_tree():
		return
	await _fade_out()
	if is_inside_tree():
		finished.emit(_build_result())


func _fade_out() -> void:
	var veil := ColorRect.new()
	veil.color = Color(0, 0, 0, 0)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(veil)
	var tw := create_tween()
	tw.tween_property(veil, "color:a", 1.0, FADE_OUT_SEC)
	await tw.finished


func _settle_animations(timeout_sec: float = 3.0) -> void:
	var deadline := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while is_inside_tree() and _animations > 0 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


func _build_result() -> LevelResult:
	var r := LevelResult.new()
	r.level_id = definition.id
	r.task_id = definition.task_id
	r.success = true
	r.replay = context.replay
	r.quest_items = definition.quest_grants
	r.soft_currency = definition.rewards.coins_for(context.replay)
	r.xp = definition.rewards.xp_for(context.replay)
	r.stats = {
		"mode": "sort",
		"picks": _picks,
		"restarts": _restarts,
		"seconds": (Time.get_ticks_msec() - _started_msec) / 1000.0,
		## Обучение доиграно — мета по этому факту гасит подсказки навсегда.
		## Ставить флаг отсюда модуль не может: флаги не его дело.
		"tutorial_done": _tutorial_done,
	}
	return r


## --- отладка ----------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_S:
		debug_autoplay()


## Пройти уровень путём, который нашёл солвер: ровно те же тапы, что сделал бы
## игрок, и через тот же _on_pick. Прогон, который дёргал бы состояние напрямую,
## не проверял бы ничего из того, что видит игрок.
func debug_autoplay() -> void:
	var plan := SortSolver.solve(sort)
	if not bool(plan["solved"]):
		push_error("SortModule: уровень %s не решается — прогон невозможен" % definition.id)
		return
	for id in plan["path"]:
		if _input_locked or not is_inside_tree():
			return
		_on_pick(String(id))
		await get_tree().create_timer(0.05).timeout
