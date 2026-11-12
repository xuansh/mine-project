@tool
extends RefCounted

## 效果类型目录（编辑器下拉用）。
##
## 注意：这里只是**编辑期的提示**——真正决定怎么算的是
## `Datas/Stats/skill_modifiers.gd` 里的三张表（百分比 / 固定值 / 开关）。
## 新增一个效果键时，如果想让它真的生效，要把键登记到那三张表之一。
##
## 字段说明：
##   key      效果键，写进 SkillNodeData.effect_key
##   label    下拉里显示的名字
##   kind     pct = 百分比加成；flat = 固定值加算；flag = 开关（数值无意义）
##   reduce   true 表示"值越大效果越好，但表现为减法"（如攻击间隔、油耗）
##   template 自动生成的效果文案，%s 会被替换成数值
##   pending  true 表示依赖的机制还没做，终端里会标「系统未就绪」

static func all() -> Array:
	return [
		{ "key": &"attack", "label": "挖掘伤害（百分比）", "kind": "pct", "reduce": false,
			"template": "单次伤害 +%s", "pending": false },
		{ "key": &"attack_interval", "label": "攻击间隔（百分比，越大越快）", "kind": "pct", "reduce": true,
			"template": "攻击间隔 −%s", "pending": false },
		{ "key": &"excavator_speed", "label": "移动速度（百分比）", "kind": "pct", "reduce": false,
			"template": "挖掘机速度 +%s", "pending": false },
		{ "key": &"fuel_max", "label": "油箱容量（固定值）", "kind": "flat", "reduce": false,
			"template": "油箱容量 +%s", "pending": false },
		{ "key": &"fuel_burn", "label": "燃油消耗（百分比减）", "kind": "pct", "reduce": true,
			"template": "燃油消耗 −%s", "pending": false },
		{ "key": &"cargo_max", "label": "货舱容量（固定值）", "kind": "flat", "reduce": false,
			"template": "货舱容量 +%s", "pending": false },
		{ "key": &"ore_value", "label": "矿石价值（百分比）", "kind": "pct", "reduce": false,
			"template": "矿石价值 +%s", "pending": false },
		{ "key": &"ore_value_flat", "label": "矿石价值（增加数值）", "kind": "flat", "reduce": false,
			"template": "每格矿石价值 +%s 金币", "pending": false },
		{ "key": &"idle_burn", "label": "原地开挖油耗（百分比减）", "kind": "pct", "reduce": true,
			"template": "原地开挖油耗 −%s", "pending": false },
		{ "key": &"tough_ore_damage", "label": "高耐久矿伤害（百分比）", "kind": "pct", "reduce": false,
			"template": "高耐久矿伤害 +%s", "pending": false },
		{ "key": &"rare_value", "label": "稀有矿价值（百分比）", "kind": "pct", "reduce": false,
			"template": "稀有矿价值 +%s", "pending": true },
		{ "key": &"turn_speed", "label": "转向耗时（百分比减）", "kind": "pct", "reduce": true,
			"template": "转向耗时 −%s", "pending": true },
		{ "key": &"hard_ore_unlock", "label": "硬岩开采（开关）", "kind": "flag", "reduce": false,
			"template": "解锁硬岩开采，不再被硬岩卡死", "pending": true },
		{ "key": &"no_slow_dig", "label": "挖掘不减速（开关）", "kind": "flag", "reduce": false,
			"template": "挖掘期间不再减速", "pending": true },
		{ "key": &"core", "label": "分支起点（开关）", "kind": "flag", "reduce": false,
			"template": "解锁后续改装分支", "pending": false },
	]

## 按 key 找条目，找不到返回空字典（= 自定义键）
static func find(key : StringName) -> Dictionary:
	for item in all():
		if item["key"] == key:
			return item
	return {}

## 把 effect_value 按效果类型格式化成文案里的数值部分
static func format_value(key : StringName, value : float) -> String:
	var item := find(key)
	if item.is_empty():
		return str(snappedf(value, 0.01))
	match String(item["kind"]):
		"pct":
			return "%d%%" % roundi(absf(value) * 100.0)
		"flag":
			return ""
		_:
			return str(roundi(absf(value)))

## 自动效果文案（和 SkillNodeData.get_effect_text 的兜底逻辑对齐）
static func auto_text(key : StringName, value : float) -> String:
	var item := find(key)
	if item.is_empty():
		return "自定义效果（%s）" % String(key)
	var body : String = item["template"]
	if String(item["kind"]) == "flag":
		return body
	return body % format_value(key, value)
