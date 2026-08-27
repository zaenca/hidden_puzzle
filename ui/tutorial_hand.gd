class_name TutorialHand
extends Node2D
## Обучающая рука: показывает, куда нажать и как тащить.
##
## Node2D, а не Control, намеренно. Подсказка обязана стоять ровно на том, что
## объясняет: на кнопке диалога — и на части пазла, которая живёт в мировых
## координатах под камерой уровня. Control в CanvasLayer совпал бы с первым и
## разъехался бы со вторым.
##
## Начало координат ноды — КОНЧИК ПАЛЬЦА, а не угол картинки: вызывающему коду
## незачем знать, какого размера рука и куда у неё смещён указатель.

const TEXTURE_PATH := "res://art/ui_hand.png"
const TIP := Vector2(0.086, 0.02)   ## кончик пальца в долях картинки
const HEIGHT := 170.0               ## высота руки на экране, px

var _sprite: Sprite2D
var _tip_px: Vector2 = Vector2.ZERO
var _unit_scale: float = 1.0
var _rest_scale: Vector2 = Vector2.ONE   ## текущий масштаб покоя, со знаком отражения
var _tween: Tween

var _from: Vector2 = Vector2.ZERO
var _to: Vector2 = Vector2.ZERO
var _on_progress: Callable = Callable()


func _ready() -> void:
	z_index = 900
	var tex: Texture2D = load(TEXTURE_PATH)
	if tex == null:
		return
	_sprite = Sprite2D.new()
	_sprite.centered = false
	_sprite.texture = tex
	_unit_scale = HEIGHT / float(tex.get_height())
	_tip_px = Vector2(tex.get_width() * TIP.x, tex.get_height() * TIP.y)
	add_child(_sprite)
	## Ориентация ровно как на арте — рука не отражается никогда. Отражённая
	## рука меняет анатомию (правая становится левой), и это заметно сразу.
	_rest_scale = Vector2(_unit_scale, _unit_scale)
	_sprite.scale = _rest_scale
	_sprite.position = -_tip_px * _unit_scale
	modulate.a = 0.0


func _aim(at: Vector2) -> void:
	position = at


## --- «нажми сюда» -----------------------------------------------------------

func play_tap(at: Vector2) -> void:
	_kill()
	_aim(at)
	modulate.a = 0.0
	_tween = create_tween().set_loops()
	_tween.tween_property(self, "modulate:a", 1.0, 0.3)
	_tween.tween_property(_sprite, "scale", _rest_scale * 0.86, 0.14) \
		.set_trans(Tween.TRANS_SINE)
	_tween.tween_callback(_ripple)
	_tween.tween_property(_sprite, "scale", _rest_scale, 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_interval(0.75)


## Круг, расходящийся от кончика пальца. Без него «рука дёрнулась» читается как
## подрагивание, а не как нажатие.
func _ripple() -> void:
	var ring := Line2D.new()
	var pts := PackedVector2Array()
	for i in 25:
		var a := TAU * float(i) / 24.0
		pts.append(Vector2(cos(a), sin(a)))
	ring.points = pts
	ring.width = 4.0
	ring.default_color = Color(1.0, 0.92, 0.55, 0.9)
	ring.joint_mode = Line2D.LINE_JOINT_ROUND
	add_child(ring)

	var tw := ring.create_tween().set_parallel(true)
	tw.tween_method(func(r: float): ring.scale = Vector2(r, r), 8.0, 52.0, 0.55) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring, "modulate:a", 0.0, 0.55)
	tw.chain().tween_callback(ring.queue_free)


## --- «тащи отсюда сюда» -----------------------------------------------------

## on_progress(t) вызывается на всём пути: по нему вызывающий двигает то, что
## рука якобы тащит. Сама рука не знает, что именно едет вместе с ней.
func play_drag(from: Vector2, to: Vector2, on_progress: Callable = Callable()) -> void:
	_from = from
	_to = to
	_on_progress = on_progress
	_kill()
	_aim(_from)
	modulate.a = 0.0
	_step(0.0)

	_tween = create_tween().set_loops()
	_tween.tween_property(self, "modulate:a", 1.0, 0.3)
	_tween.tween_property(_sprite, "scale", _rest_scale * 0.88, 0.16)   # «взял»
	_tween.tween_method(_step, 0.0, 1.0, 0.95) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(_sprite, "scale", _rest_scale, 0.16)          # «отпустил»
	_tween.tween_property(self, "modulate:a", 0.0, 0.3)
	_tween.tween_callback(func(): _step(0.0))
	_tween.tween_interval(0.4)


func _step(t: float) -> void:
	position = _from.lerp(_to, t)
	if _on_progress.is_valid():
		_on_progress.call(t)


func stop() -> void:
	_kill()
	_on_progress = Callable()
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.2)
	tw.tween_callback(queue_free)


func _kill() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
