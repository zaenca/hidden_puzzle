class_name TaskResolver
extends RefCounted
## Пересчёт состояний задач. Чистая функция от (контент + состояние игрока),
## поэтому состояние задачи никогда не «разъезжается» с сейвом.

static func compute(task: MetaTaskDefinition, meta: MetaService) -> int:
	var current: int = meta.task_states.get(task.id, MetaService.TaskState.LOCKED)
	if current == MetaService.TaskState.COMPLETED:
		return MetaService.TaskState.COMPLETED
	if current == MetaService.TaskState.APPLYING:
		return MetaService.TaskState.APPLYING

	for r in task.unlock:
		if not requirement_met(r, meta):
			return MetaService.TaskState.LOCKED

	var action: MetaActionDefinition = meta.db.action(task.action_id)
	if action != null and _all_met(action.requirements, meta):
		return MetaService.TaskState.READY_TO_APPLY

	for level_id in task.level_ids:
		if meta.completed_levels.has(level_id):
			return MetaService.TaskState.IN_PROGRESS

	return MetaService.TaskState.AVAILABLE


static func requirement_met(r: Requirement, meta: MetaService) -> bool:
	match r.kind:
		Requirement.Kind.ITEM:
			return meta.player.amount_of(r.id) >= r.amount
		Requirement.Kind.TASK:
			return meta.task_state_name(r.id) == r.state
		Requirement.Kind.LEVEL:
			return meta.completed_levels.has(r.id)
		Requirement.Kind.FLAG:
			return bool(meta.flags.get(r.id, false))
	return false


static func missing(reqs: Array[Requirement], meta: MetaService) -> Array[Requirement]:
	var out: Array[Requirement] = []
	for r in reqs:
		if not requirement_met(r, meta):
			out.append(r)
	return out


static func _all_met(reqs: Array[Requirement], meta: MetaService) -> bool:
	for r in reqs:
		if not requirement_met(r, meta):
			return false
	return true
