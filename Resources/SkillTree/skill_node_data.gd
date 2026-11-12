@tool
class_name SkillNodeData
extends Resource

## 升级树里的一个节点。只存数据，不负责显示。
## 升级系统接入后，从 effect_key / effect_value 读取效果。

enum Shape {
	SQUARE,
	HEXAGON,
}

@export var id : StringName = &""
@export var title : String = "未命名节点"
@export_multiline var description : String = ""

## 给升级系统读的效果键，例如 dig_speed / ore_value / core
@export var effect_key : StringName = &""
## 效果幅度，0.1 表示 +10%
@export var effect_value : float = 0.0

## 详情面板里显示的效果文案。**留空**时按 effect_key 自动生成（见 get_effect_text）
## 想让效果说法完全自己定就填这里，插件里叫「效果说明」
@export_multiline var effect_text : String = ""

## 实现备注：写清"这个效果到底该怎么算"，只给程序看，任何界面都不显示
@export_multiline var implement_note : String = ""

## 解锁消耗（占位，目前不扣钱）
@export var cost : int = 0
@export var max_level : int = 1

@export var accent_color : Color = Color("d9a227")
@export var shape : Shape = Shape.SQUARE

## 相对树中心的偏移，由 SkillTree 统一摆放，整棵树会自动居中
@export var position : Vector2 = Vector2.ZERO

## 子节点 id，技能树按它画连线
@export var children : Array[StringName] = []

## 详情面板里显示的一行效果说明。
## 手填了 effect_text 就用手填的（插件里叫「效果说明」），否则按 effect_key 自动生成
func get_effect_text() -> String:
	if not effect_text.strip_edges().is_empty():
		return effect_text
	match effect_key:
		&"excavator_speed":
			return "挖掘机速度 +%d%%" % roundi(effect_value * 100.0)
		&"ore_value":
			return "矿石价值 +%d%%" % roundi(effect_value * 100.0)
		&"ore_value_flat":
			return "每格矿石价值 +%d 金币" % roundi(effect_value)
		&"core":
			return "解锁后续改装分支"
		&"attack":
			return "单次伤害 +%d%%" % roundi(effect_value * 100.0)
		&"attack_interval":
			return "攻击间隔 −%d%%" % roundi(effect_value * 100.0)
		&"hard_ore_unlock":
			return "解锁硬岩开采，不再被硬岩卡死"
		&"tough_ore_damage":
			return "高耐久矿伤害 +%d%%" % roundi(effect_value * 100.0)
		&"turn_speed":
			return "转向耗时 −%d%%" % roundi(effect_value * 100.0)
		&"no_slow_dig":
			return "挖掘期间不再减速"
		&"rare_value":
			return "稀有矿价值 +%d%%" % roundi(effect_value * 100.0)
		&"cargo_max":
			return "货舱容量 +%d" % roundi(effect_value)
		&"fuel_max":
			return "油箱容量 +%d" % roundi(effect_value)
		&"fuel_burn":
			return "燃油消耗 −%d%%" % roundi(effect_value * 100.0)
		&"idle_burn":
			return "原地开挖油耗 −%d%%" % roundi(effect_value * 100.0)
		_:
			return "暂无效果说明"
