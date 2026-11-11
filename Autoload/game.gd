extends Node

## 金币变化时发出。total 为变化后的总数，delta 为本次变化量（可为负）
signal coins_changed(total : int, delta : int)

var time : float

## 当前金币。UI 只读它，改金币一律走 add_coins / spend_coins
var coins : int = 0

func tick(delta : float):
	time += delta

## 加金币。amount 为浮点（drop × value 可能是小数），四舍五入到整数
func add_coins(amount : float) -> void:
	var gained : int = roundi(amount)
	if gained <= 0:
		return
	coins += gained
	coins_changed.emit(coins, gained)

## 花金币，钱不够返回 false 且不扣
func spend_coins(amount : int) -> bool:
	if amount <= 0 or coins < amount:
		return false
	coins -= amount
	coins_changed.emit(coins, -amount)
	return true
