class_name ExcavatorUnit
extends RefCounted

## 底栏「持有物」里的一台挖掘机（GDD 4.11）。
##
## data 指向共享的 MineableData 资源（同一型号的机器共享同一份 .tres，
## 加成在实体生成时快照，所以库存里放引用是安全的）。
## deployed 是运行态，不入档——读档后所有机器一律回库。

## 这台机器的数值来源
var data : MineableData

## 底栏槽位上显示的名字，如「小型挖掘机 01」
var display_name : String = "挖掘机"

## true = 已派遣到矿区作业（此时底栏槽位显示「出勤中」，不可再派遣）
var deployed : bool = false

func _init(p_data : MineableData = null, p_name : String = "") -> void:
	data = p_data
	if p_name != "":
		display_name = p_name

## 槽位副标题：一眼能看懂的数值摘要
func summary() -> String:
	if data == null:
		return ""
	return "攻击 %.0f · 油箱 %.0f · 货舱 %d" % [data.attack, data.total_fuel, data.cargo_max]
