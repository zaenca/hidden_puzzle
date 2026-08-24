extends Node
## Единственная точка мутации кошелька и инвентаря.
## Правила выдачи здесь не живут — это дело меты. Здесь только «сколько есть»
## и «списать/начислить».

const CURRENCIES := ["coins", "hard", "xp"]

var currencies: Dictionary = {"coins": 0, "hard": 0, "xp": 0}
var items: Dictionary = {}   ## quest items, материалы, бустеры — всё по id


func amount_of(id: String) -> int:
	if currencies.has(id):
		return int(currencies[id])
	return int(items.get(id, 0))


func can_pay(id: String, n: int) -> bool:
	return amount_of(id) >= n


func pay(id: String, n: int) -> bool:
	if n <= 0:
		return true
	if not can_pay(id, n):
		return false
	_write(id, amount_of(id) - n)
	return true


func grant(id: String, n: int = 1) -> void:
	if n == 0:
		return
	_write(id, amount_of(id) + n)
	if not currencies.has(id):
		var def: ItemDefinition = ContentDB.item(id)
		if def != null and def.is_quest():
			EventBus.quest_item_granted.emit(id)


func has_all(id_to_amount: Dictionary) -> bool:
	for id in id_to_amount:
		if not can_pay(id, int(id_to_amount[id])):
			return false
	return true


func _write(id: String, value: int) -> void:
	if currencies.has(id):
		currencies[id] = maxi(0, value)
		EventBus.currency_changed.emit(id, currencies[id])
	else:
		var v := maxi(0, value)
		if v == 0:
			items.erase(id)
		else:
			items[id] = v
		EventBus.inventory_changed.emit(id, v)


## --- save -------------------------------------------------------------------

func save_data() -> Dictionary:
	return {"currencies": currencies.duplicate(), "items": items.duplicate()}


func load_data(d: Dictionary) -> void:
	currencies = {"coins": 0, "hard": 0, "xp": 0}
	for k in d.get("currencies", {}):
		currencies[k] = int(d["currencies"][k])
	items.clear()
	for k in d.get("items", {}):
		items[String(k)] = int(d["items"][k])


func reset(starting: Dictionary = {}) -> void:
	currencies = {"coins": 0, "hard": 0, "xp": 0}
	items.clear()
	for k in starting:
		_write(String(k), int(starting[k]))
