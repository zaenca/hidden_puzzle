class_name SortState
extends RefCounted
## Правила Sort без единой ноды: где лежит каждый предмет, что доступно, что
## происходит после тапа.
##
## Отдельно от сцены намеренно. Ровно эти правила проверяет валидатор, когда
## доказывает, что уровень проходим, и ровно их прогоняет headless-тест —
## логика, живущая внутри Node2D, обоим была бы недоступна.

enum Place { BOARD, TRAY, CLEARED }

var definition: SortDefinition

## instance_id -> Place
var places: Dictionary = {}
## Порядок ячеек лотка. Предмет встаёт рядом со «своими»: разбросанные по
## лотку одинаковые предметы игрок не видит как пару, и лоток перестаёт
## отвечать на единственный вопрос, который к нему есть, — «сколько до тройки».
var tray: Array[String] = []


func setup(def: SortDefinition) -> void:
	definition = def
	reset()


func reset() -> void:
	places.clear()
	tray.clear()
	if definition == null:
		return
	for i in definition.items:
		places[i.id] = Place.BOARD


## --- запросы ----------------------------------------------------------------

func place_of(instance_id: String) -> int:
	return int(places.get(instance_id, Place.CLEARED))


func on_board(instance_id: String) -> bool:
	return place_of(instance_id) == Place.BOARD


## Предмет доступен, если он ещё на поле, всё, что его накрывает, уже ушло, и
## зона, в которой он лежит, открыта.
## «Ушло» — значит не на поле: предмет, лежащий в лотке, физически из завала
## уже вынут, и ждать его окончательного исчезновения незачем.
func is_available(instance_id: String) -> bool:
	if not on_board(instance_id):
		return false
	var inst := definition.item(instance_id)
	if inst == null:
		return false
	for blocker in inst.blocked_by:
		if on_board(String(blocker)):
			return false
	var zone := definition.zone_of(instance_id)
	if zone != null and not is_zone_open(zone.id):
		return false
	return true


## Зона открыта, когда с неё снято всё, что её держало. Правило то же, что у
## предмета под блокером, и намеренно: игрок уже знает «убери верхнее», и
## второе правило про то же самое ему пришлось бы учить заново.
func is_zone_open(zone_id: String) -> bool:
	var zone := definition.zone(zone_id)
	if zone == null:
		return true
	for blocker in zone.blocked_by:
		if on_board(String(blocker)):
			return false
	return true


## Доступно ли место, где лежит предмет. Предмет вне зон доступен всегда — про
## него этот вопрос просто не задаётся.
func is_zone_open_for(instance_id: String) -> bool:
	var zone := definition.zone_of(instance_id)
	return zone == null or is_zone_open(zone.id)


## Зоны, которые прямо сейчас закрыты. Нужно сцене — нарисовать их крышки — и
## валидатору, который доказывает, что каждая из них однажды откроется.
func closed_zones() -> Array[SortZone]:
	var out: Array[SortZone] = []
	for z in definition.zones:
		if not is_zone_open(z.id):
			out.append(z)
	return out


func available_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for i in definition.items:
		if is_available(i.id):
			out.append(i.id)
	return out


func board_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for i in definition.items:
		if on_board(i.id):
			out.append(i.id)
	return out


func remaining() -> int:
	var n := 0
	for id in places:
		if int(places[id]) != Place.CLEARED:
			n += 1
	return n


func is_complete() -> bool:
	return remaining() == 0


## Проигрыш ровно один: лоток полон, а тройка не сложилась. Отдельно от него
## стоит тупик (`is_stuck`) — там лоток ещё не полон, но брать уже нечего.
func is_failed() -> bool:
	if is_complete():
		return false
	if definition.fail_on_full_tray and tray.size() >= definition.tray_size:
		return true
	return is_stuck()


## Поле кончилось раньше лотка: доступных предметов нет, а незакрытые остались.
## Для уровня без блокировок недостижимо, но с ними это самый частый способ
## сделать уровень непроходимым — и валидатор ловит его именно здесь.
func is_stuck() -> bool:
	return not is_complete() and available_ids().is_empty()


func tray_free() -> int:
	return maxi(0, definition.tray_size - tray.size())


## --- ход --------------------------------------------------------------------

## Единственная мутация состояния. Возвращает, что случилось:
##   ok        — ход принят
##   cleared   — id предметов закрывшейся группы (пусто, если группы нет)
##   category  — категория закрывшейся группы
##   peak      — сколько ячеек лоток занял на этом ходу ДО схлопывания группы
##   complete  — поле разобрано
##   failed    — лоток переполнен или поле встало
func pick(instance_id: String) -> Dictionary:
	var out := {"ok": false, "cleared": PackedStringArray(), "category": "",
		"peak": tray.size(), "complete": false, "failed": false}
	if definition == null or is_failed() or is_complete():
		return out
	if not is_available(instance_id):
		return out
	if tray.size() >= definition.tray_size:
		return out

	var inst := definition.item(instance_id)
	places[instance_id] = Place.TRAY
	tray.insert(_insert_index(inst.category), instance_id)
	out["ok"] = true
	## Ровно этот момент игрок и видит как «лоток почти полон»: третий предмет
	## сначала занимает ячейку и только потом уносит группу с собой. Замер
	## после схлопывания занижал бы тесноту уровня на целую ячейку.
	out["peak"] = tray.size()

	var group := _full_group(inst.category)
	if not group.is_empty():
		for id in group:
			places[String(id)] = Place.CLEARED
			tray.erase(String(id))
		out["cleared"] = group
		out["category"] = inst.category

	out["complete"] = is_complete()
	out["failed"] = is_failed()
	return out


## Место новичка в лотке: сразу за последним предметом его категории, а если
## таких нет — в конец.
func _insert_index(category: String) -> int:
	var idx := tray.size()
	for i in range(tray.size() - 1, -1, -1):
		var inst := definition.item(tray[i])
		if inst != null and inst.category == category:
			idx = i + 1
			break
	return idx


func _full_group(category: String) -> PackedStringArray:
	var same := PackedStringArray()
	for id in tray:
		var inst := definition.item(String(id))
		if inst != null and inst.category == category:
			same.append(String(id))
	if same.size() < definition.group_size:
		return PackedStringArray()
	return same.slice(0, definition.group_size)


## --- снимки для солвера -----------------------------------------------------

func snapshot() -> Dictionary:
	return {"places": places.duplicate(), "tray": tray.duplicate()}


func restore(snap: Dictionary) -> void:
	places = (snap["places"] as Dictionary).duplicate()
	tray = (snap["tray"] as Array).duplicate()


## Ключ состояния для мемоизации. Лоток внутри одной категории не различим,
## поэтому в ключ идёт отсортированный список — иначе солвер считал бы разными
## состояния, отличающиеся только порядком двух одинаковых банок.
func key() -> String:
	var cleared := PackedStringArray()
	for id in places:
		if int(places[id]) == Place.CLEARED:
			cleared.append(String(id))
	cleared.sort()
	var bag := tray.duplicate()
	bag.sort()
	return "|".join(cleared) + "#" + "|".join(bag)
