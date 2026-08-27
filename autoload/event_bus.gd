extends Node
## Только «широкие» доменные события для UI. Осознанно короткий список:
## если у события один слушатель и он структурно рядом — это прямой сигнал,
## а не EventBus.

signal currency_changed(id: String, value: int)
signal inventory_changed(id: String, value: int)
signal inventory_selection_changed(item_id: String)   ## "" — рука пуста
signal quest_item_granted(id: String)
signal task_state_changed(task_id: String, state: int)
signal cooldown_started(action_id: String)
signal cooldown_finished(action_id: String)
signal shop_visual_changed(shop_id: String, slot_id: String, state_id: String)
signal narrative_requested(text: String)
signal toast(text: String)
