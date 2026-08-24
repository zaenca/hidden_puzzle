class_name EffectRunner
extends RefCounted
## Единственное место, где мир меняется. Эффекты декларативны и приходят
## из данных, поэтому новый тип изменения — это новый case здесь и новая
## строка в JSON, а не новый контроллер.

static func apply(effects: Array[MetaEffect], meta: MetaService) -> PackedStringArray:
	var narrative := PackedStringArray()
	for e in effects:
		match e.kind:
			MetaEffect.Kind.SET_VISUAL_STATE:
				meta.set_slot_state(e.shop_id, e.slot_id, e.state_id)
			MetaEffect.Kind.SET_SHOP_STATE:
				meta.set_shop_state(e.shop_id, e.state_id)
			MetaEffect.Kind.GRANT:
				meta.player.grant(e.id, e.amount)
			MetaEffect.Kind.CONSUME:
				meta.player.pay(e.id, e.amount)
			MetaEffect.Kind.UNLOCK_TASK:
				meta.set_flag("task_unlocked:" + e.task_id, true)
			MetaEffect.Kind.SET_FLAG:
				meta.set_flag(e.id, true)
			MetaEffect.Kind.NARRATIVE:
				narrative.append(e.text)
	return narrative
