extends Node

## 金币变化时发出。total 为变化后的总数，delta 为本次变化量（可为负）
signal coins_changed(total : int, delta : int)

## 升级等级变化时发出。group 为升级分组名，level 为购买后的等级
signal upgrades_changed(group : StringName, level : int)

var time : float

## 当前金币。UI 只读它，改金币一律走 add_coins / spend_coins
var coins : int = 0

## 各升级分组已购买次数（等级）。key = 分组名，value = 等级（0 表示未购买）
var upgrade_levels : Dictionary[StringName, int] = {}

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

## 取某分组当前等级，没买过返回 0
func get_group_level(group : StringName) -> int:
	return upgrade_levels.get(group, 0)

## 给某分组升一级并广播。扣款由调用方先通过 spend_coins 校验
func add_group_level(group : StringName) -> void:
	upgrade_levels[group] = get_group_level(group) + 1
	upgrades_changed.emit(group, upgrade_levels[group])
