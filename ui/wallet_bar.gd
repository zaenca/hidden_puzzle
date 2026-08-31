class_name WalletBar
extends Control
## Кошелёк: монета, счёт и кнопка «пополнить» на нарисованной плашке.
##
## Живёт в оверлее Boot по той же причине, что журнал и полоса предметов: деньги
## не принадлежат экрану. Кошелёк, собранный в сцене, пришлось бы повторять в
## карте, локации и магазине — и однажды они разошлись бы в цифре.
##
## Счёт обновляется по событию, а не по опросу: между начислением и следующим
## кадром игрок успевает увидеть старую сумму, и это читается как «награду не
## дали».

const PLATE := "res://art/ui/taskbar_notification.png"
const COIN := "res://art/ui/coin.png"
const PLUS := "res://art/ui/coinplus.png"

const SIZE := Vector2(320, 108)
const EDGE := 24.0        ## отступ от края экрана, поверх safe area
const ICON := Vector2(66, 66)
const PLUS_SIZE := Vector2(62, 62)
const PATCH := 34
## Поля внутри плашки. Рамка нарисована по краю картинки, и содержимое, положенное
## во весь прямоугольник, ложится прямо на неё: монета и плюс наезжали на золото.
const PAD_X := 26
const PAD_Y := 14

const TEXT := Color(0.24, 0.16, 0.07)

var _plate: NinePatchRect
var _amount: Label
var _plus: TextureButton


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	_refresh()
	EventBus.currency_changed.connect(_on_currency_changed)


func _build() -> void:
	## NinePatchRect, а не PanelContainer: плашка тянется под свой размер, а
	## содержимое кладётся поверх, и от контейнера тут ничего не нужно.
	_plate = NinePatchRect.new()
	_plate.texture = Backdrop.load_texture(PLATE)
	_plate.patch_margin_left = PATCH
	_plate.patch_margin_right = PATCH
	_plate.patch_margin_top = PATCH
	_plate.patch_margin_bottom = PATCH
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_plate)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", PAD_X)
	margin.add_theme_constant_override("margin_right", PAD_X)
	margin.add_theme_constant_override("margin_top", PAD_Y)
	margin.add_theme_constant_override("margin_bottom", PAD_Y)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)

	var coin := TextureRect.new()
	coin.texture = Backdrop.load_texture(COIN)
	coin.custom_minimum_size = ICON
	coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	## Мип-мапы: исходник монеты — тысяча пикселей, а на экране она 66, и без
	## них уменьшение берёт один пиксель из шестнадцати — золото рассыпается
	## в зерно и читается как мыло.
	coin.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(coin)

	## Тёмная буква без обводки: плашка кремовая, светлый текст с контуром —
	## набор для арта под ним, не для бумаги. Без переноса: счёт растёт до
	## четырёх знаков, и перенос сложил бы его пополам вместо сжатия плашки.
	_amount = Label.new()
	_amount.add_theme_font_size_override("font_size", 36)
	_amount.add_theme_color_override("font_color", TEXT)
	_amount.autowrap_mode = TextServer.AUTOWRAP_OFF
	_amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_amount.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_amount.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_amount.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_amount)

	## Кнопка ведёт в магазин валюты, которого ещё нет. Показываем её всё равно:
	## место под покупку монет закладывается сразу, иначе оно потом отнимет
	## ширину у счёта, который к тому времени уже привыкли видеть.
	_plus = TextureButton.new()
	_plus.texture_normal = Backdrop.load_texture(PLUS)
	_plus.ignore_texture_size = true
	_plus.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	_plus.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_plus.custom_minimum_size = PLUS_SIZE
	_plus.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_plus.pressed.connect(_on_plus)
	row.add_child(_plus)


## Размер берём у вьюпорта: контейнер оверлея выставляет себе якоря до входа в
## дерево и остаётся нулевым, а по нулевому родителю растягиваться некуда.
func _fit_to_screen() -> void:
	var screen := get_viewport_rect().size
	var inset := SafeArea.insets(screen)
	position = Vector2.ZERO
	size = screen
	_plate.size = SIZE
	_plate.position = Vector2(
		screen.x - SIZE.x - int(inset["right"]) - EDGE,
		int(inset["top"]) + EDGE)


func set_active(on: bool) -> void:
	visible = on
	if on:
		_fit_to_screen()
		_refresh()


func _on_currency_changed(id: String, _value: int) -> void:
	if id == "coins":
		_refresh()


func _refresh() -> void:
	if _amount != null:
		_amount.text = str(PlayerState.amount_of("coins"))


## Заглушка: магазина валюты в слайсе нет, и молчащая кнопка читалась бы как
## сломанная.
func _on_plus() -> void:
	EventBus.toast.emit("Магазин монет скоро откроется")


## --- для headless-прогона ---------------------------------------------------

func shown_amount() -> String:
	return _amount.text if _amount != null else ""
