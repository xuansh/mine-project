class_name SkillModifiers
extends RefCounted

## 已解锁技能节点聚合出的数值加成集合（GDD 4.10.3）。
##
## 聚合规则：同键直接累加，最终值 = (base + flat) × (1 ± pct)。
## 选择加算而非连乘：满树时连乘会指数级偏离第 5 章的平衡表。
##
## 这一层只做「算出加成」和「把加成写进数据副本」，不认识 UI，也不读存档。

## 百分比类键：值为 0.15 表示 +15%，减算类（interval / burn）按 1 − pct 处理
const MIN_ATTACK_INTERVAL : float = 0.05

var _pct : Dictionary[StringName, float] = {}
var _flat : Dictionary[StringName, float] = {}
var _flags : Dictionary[StringName, bool] = {}

## 走固定值加算的键（fuel_max / cargo_max 是绝对值加成，不是百分比）
## ore_value_flat 是「每格矿石价值 +N 金币」：它不改 MineableData，
## 由 MineableEntity 结算时直接读 get_flat()，所以这里只需要登记分流
static func is_flat_key(key : StringName) -> bool:
	return key == &"fuel_max" or key == &"cargo_max" or key == &"ore_value_flat"

## 只有开关语义、没有数值的键
static func is_flag_key(key : StringName) -> bool:
	return key == &"core" or key == &"hard_ore_unlock" or key == &"no_slow_dig"

# ---------------------------------------------------------------- 累加

func add_pct(key : StringName, value : float) -> void:
	if key == &"" or is_zero_approx(value):
		return
	_pct[key] = float(_pct.get(key, 0.0)) + value

func add_flat(key : StringName, value : float) -> void:
	if key == &"" or is_zero_approx(value):
		return
	_flat[key] = float(_flat.get(key, 0.0)) + value

func set_flag(key : StringName) -> void:
	if key == &"":
		return
	_flags[key] = true

## 按 effect_key 自动分流：flat 键走 add_flat，flag 键走 set_flag，其余走 add_pct
func add_by_key(key : StringName, value : float) -> void:
	if is_flag_key(key):
		set_flag(key)
	elif is_flat_key(key):
		add_flat(key, value)
	else:
		add_pct(key, value)

# ---------------------------------------------------------------- 读取

func get_pct(key : StringName) -> float:
	return float(_pct.get(key, 0.0))

func get_flat(key : StringName) -> float:
	return float(_flat.get(key, 0.0))

func has_flag(key : StringName) -> bool:
	return bool(_flags.get(key, false))

func is_empty() -> bool:
	return _pct.is_empty() and _flat.is_empty() and _flags.is_empty()

# ---------------------------------------------------------------- 应用

## 把加成写进一份 MineableData 副本并返回。
## 绝不改传入的那个资源：原 .tres 被所有机器共享，改它会让加成叠到每一台上
func apply_to(source : MineableData) -> MineableData:
	if source == null:
		return null
	var out := source.duplicate() as MineableData
	if out == null:
		return source

	out.attack = maxf(out.attack * (1.0 + get_pct(&"attack")), 0.0)
	out.attack_interval = maxf(out.attack_interval * _reduce(&"attack_interval"), MIN_ATTACK_INTERVAL)
	out.speed = maxf(out.speed * (1.0 + get_pct(&"excavator_speed")), 0.0)
	out.total_fuel = maxf(out.total_fuel + get_flat(&"fuel_max"), 0.0)
	out.fuelConsumptionPerSecond = maxf(out.fuelConsumptionPerSecond * _reduce(&"fuel_burn"), 0.0)
	out.cargo_max = maxi(out.cargo_max + roundi(get_flat(&"cargo_max")), 0)

	return out

## 减算类的乘数：0.15 → 0.85，钳在 [0, 1] 避免负油耗 / 负间隔
func _reduce(key : StringName) -> float:
	return clampf(1.0 - get_pct(key), 0.0, 1.0)
