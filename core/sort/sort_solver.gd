class_name SortSolver
extends RefCounted
## Доказательство, что Sort-уровень проходим, и путь, которым он проходится.
##
## Нужен трижды: валидатору — чтобы непроходимый уровень не доехал до игрока;
## headless-прогону — чтобы пройти уровень без человека; отладке — чтобы
## увидеть, каким порядком уровень вообще решается.
##
## Перебор с мемоизацией по состоянию. Сначала пробуются ходы, дополняющие
## пару в лотке: почти любой честный уровень решается именно так, и полный
## перебор нужен только там, где раскладка действительно хитрая.

const DEFAULT_NODE_LIMIT := 120000


## Возвращает {solved, path, max_tray, nodes, exhausted}.
##   path      — порядок тапов, который разбирает поле целиком
##   max_tray  — сколько ячеек лотка этот путь занимал в пике
##   exhausted — перебор упёрся в лимит узлов, а не доказал непроходимость
static func solve(def: SortDefinition, node_limit: int = DEFAULT_NODE_LIMIT) -> Dictionary:
	var state := SortState.new()
	state.setup(def)
	var seen := {}
	var path := PackedStringArray()
	var stats := {"nodes": 0, "limit": node_limit, "max_tray": 0, "exhausted": false}
	var solved := _search(state, seen, path, stats)
	return {
		"solved": solved,
		"path": path,
		"max_tray": int(stats["max_tray"]),
		"nodes": int(stats["nodes"]),
		"exhausted": bool(stats["exhausted"]),
	}


static func _search(state: SortState, seen: Dictionary, path: PackedStringArray,
		stats: Dictionary) -> bool:
	if state.is_complete():
		return true
	if state.is_failed():
		return false

	stats["nodes"] = int(stats["nodes"]) + 1
	if int(stats["nodes"]) > int(stats["limit"]):
		stats["exhausted"] = true
		return false

	var k := state.key()
	if seen.has(k):
		return false
	seen[k] = true

	for id in _ordered_moves(state):
		var snap := state.snapshot()
		var res := state.pick(String(id))
		if not bool(res["ok"]):
			continue
		stats["max_tray"] = maxi(int(stats["max_tray"]), state.tray.size())
		path.append(String(id))
		if _search(state, seen, path, stats):
			return true
		path.resize(path.size() - 1)
		state.restore(snap)
		if bool(stats["exhausted"]):
			return false
	return false


## Порядок перебора: сперва то, что закрывает или почти закрывает группу.
## Это не эвристика ради скорости — это порядок, которым играет человек, и
## найденный путь получается похожим на человеческое прохождение.
static func _ordered_moves(state: SortState) -> PackedStringArray:
	var in_tray := {}
	for id in state.tray:
		var inst := state.definition.item(String(id))
		if inst != null:
			in_tray[inst.category] = int(in_tray.get(inst.category, 0)) + 1

	var moves := state.available_ids()
	var scored := []
	for id in moves:
		var inst := state.definition.item(String(id))
		var have := int(in_tray.get(inst.category, 0))
		## Чем ближе категория к полной группе, тем раньше её пробуем.
		scored.append({"id": String(id), "score": have})
	scored.sort_custom(func(a, b): return int(a["score"]) > int(b["score"]))

	var out := PackedStringArray()
	for entry in scored:
		out.append(String(entry["id"]))
	return out
