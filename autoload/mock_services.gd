extends Node
## Точки интеграции рекламы и покупок БЕЗ SDK. Реальные Ads/IAP подключаются
## заменой тела этих функций — вызывающий код не меняется.

signal ad_completed(placement: String, success: bool)
signal purchase_completed(product: String, success: bool)


## Mock rewarded ad: всегда успешен, мгновенно.
func show_rewarded_ad(placement: String) -> bool:
	print("[MockAds] rewarded ad: %s -> success" % placement)
	ad_completed.emit(placement, true)
	EventBus.toast.emit("Реклама просмотрена (mock)")
	return true


func is_ad_available(_placement: String) -> bool:
	return true


## Mock IAP: hard currency просто начисляется (debug-меню).
func purchase(product: String, hard_amount: int) -> bool:
	PlayerState.grant("hard", hard_amount)
	print("[MockIAP] %s -> +%d hard" % [product, hard_amount])
	purchase_completed.emit(product, true)
	return true
