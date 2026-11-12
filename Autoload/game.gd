extends Node

## 金币变化时发出。total 为变化后的总数，delta 为本次变化量（可为负）
signal coins_changed(total : int, delta : int)

## 升级等级变化时发出。group 为升级分组名，level 为购买后的等级
signal upgrades_changed(group : StringName, level : int)

var time : float

func _ready() -> void:
	# 兜底起步机：读档在 SaveSystem._ready 里做，读到档会覆盖这里的初始状态
	ensure_starter_excavator()

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

# ---------------------------------------------------------------- 玩家成长

## 等级 / 经验 / 技能点 / 最深纪录变化时发出（金币走 coins_changed，不在这条里）
signal stats_changed

## 当前等级，从 1 开始
var level : int = 1
## 当前经验，升到 xp_to_next 即升级并清零进位
var xp : int = 0
## 升下一级所需经验，每次升级 ×1.5
var xp_to_next : int = 100
## 可用技能点（技能树消耗）
var skill_points : int = 0
## 历史最深掘进纪录（米），只增不减
var best_depth : float = 0.0

## 加经验，够数自动连升（一次性加很多也正确）
func add_xp(amount : float) -> void:
	var gained := roundi(amount)
	if gained <= 0:
		return
	xp += gained
	while xp >= xp_to_next:
		xp -= xp_to_next
		level += 1
		xp_to_next = roundi(float(xp_to_next) * 1.5)
	stats_changed.emit()

## 加技能点（amount 可为负，代表消耗）
func add_skill_points(amount : int) -> void:
	if amount == 0:
		return
	skill_points += amount
	stats_changed.emit()

## 汇报当前掘进深度，超过历史纪录才更新并广播
func report_depth(depth : float) -> void:
	if depth > best_depth:
		best_depth = depth
		stats_changed.emit()

# ---------------------------------------------------------------- 改装终端（GDD 4.10）

## 已解锁 / 已安装的节点变化时发出（扣费与存档都挂这里）
signal skills_changed

## 存档格式版本。以后字段不兼容时靠它做迁移
const SAVE_VERSION : int = 1

## 技能树数据源。改装终端与效果聚合都读这一份，保证「一份数据两种读法」
var skill_tree_data : SkillTreeData = preload("res://Resources/SkillTree/basic_skill_tree.tres")

## 已解锁节点 id，顺序无关
var unlocked_skills : Array[StringName] = []

func is_skill_unlocked(skill_id : StringName) -> bool:
	return unlocked_skills.has(skill_id)

## 取节点数据（带空树保护）。UI 与聚合层都从这里拿，别各自去碰 skill_tree_data
func get_skill_data(skill_id : StringName) -> SkillNodeData:
	if skill_tree_data == null:
		return null
	return skill_tree_data.get_node_data(skill_id)

func get_skill_cost(skill_id : StringName) -> int:
	var data := get_skill_data(skill_id)
	return data.cost if data != null else 0

func get_unlocked_count() -> int:
	return unlocked_skills.size()

func get_skill_total() -> int:
	return skill_tree_data.nodes.size() if skill_tree_data != null else 0

## 查这个节点对应的机制是否已实现（GDD 4.10.3 批次 2 的四个键）
## 未就绪的节点在终端里照常显示，但不可购买，也不隐藏
func is_skill_pending(skill_id : StringName) -> bool:
	var data := get_skill_data(skill_id)
	return data != null and _is_mechanic_pending(data.effect_key)

## 依赖尚未实现的机制：硬岩判定 / 稀有度 / 转向 / 挖掘减速
static func _is_mechanic_pending(effect_key : StringName) -> bool:
	return effect_key == &"hard_ore_unlock" \
		or effect_key == &"rare_value" \
		or effect_key == &"turn_speed" \
		or effect_key == &"no_slow_dig"

## 三态判定的唯一口径（GDD 4.10.4）：父节点已解锁 + 未买过 + 金币够
func can_unlock_skill(skill_id : StringName) -> bool:
	if is_skill_unlocked(skill_id):
		return false
	if is_skill_pending(skill_id):
		return false
	var data := get_skill_data(skill_id)
	if data == null:
		return false
	return is_skill_parent_unlocked(skill_id) and coins >= data.cost

## 父节点是否已解锁（给 UI 区分「未解锁」和「钱不够」用）
func is_skill_parent_unlocked(skill_id : StringName) -> bool:
	if skill_tree_data == null:
		return false
	var parent := skill_tree_data.get_parent_of(skill_id)
	return parent == null or is_skill_unlocked(parent.id)

## 扣费并解锁。费用从节点数据读，调用方不用自己算
func unlock_skill(skill_id : StringName) -> bool:
	if not can_unlock_skill(skill_id):
		return false
	var cost := get_skill_cost(skill_id)
	if cost > 0 and not spend_coins(cost):
		return false
	unlocked_skills.append(skill_id)
	skills_changed.emit()
	return true

## 复位改装：清空已解锁节点（只留根节点），把已花的金币原路退回。
## 返回退回的金币数。给「换流派重走一遍」和自测用。
## 只动改装，不动金币结余以外的进度（深度 / 等级 / 机器都保留）
func reset_skills() -> int:
	var keep : Array[StringName] = []
	if skill_tree_data != null and skill_tree_data.get_node_data(skill_tree_data.root_id) != null:
		keep.append(skill_tree_data.root_id)

	var refund : int = 0
	for skill_id in unlocked_skills:
		if keep.has(skill_id):
			continue
		if skill_tree_data != null:
			var data := skill_tree_data.get_node_data(skill_id)
			if data != null:
				refund += data.cost

	unlocked_skills = keep
	if refund > 0:
		coins += refund
		coins_changed.emit(coins, refund)
	skills_changed.emit()
	return refund

## 由已解锁节点聚合出加成集合。空集合时返回空对象，调用方用 is_empty() 判断
func get_modifiers() -> SkillModifiers:
	var mods := SkillModifiers.new()
	if skill_tree_data == null:
		return mods
	for node_data in skill_tree_data.nodes:
		if node_data == null or not is_skill_unlocked(node_data.id):
			continue
		mods.add_by_key(node_data.effect_key, node_data.effect_value)
	return mods

# ---------------------------------------------------------------- 持有物（GDD 4.11）

## 拥有的挖掘机变化时发出（入手 / 派遣 / 回库），底栏与 HUD 都挂这里
signal excavators_changed

## 首台挖掘机的数据源。同一型号共享一份 .tres，加成在生成实体时快照
const DEFAULT_EXCAVATOR := preload("res://Resources/Excavators/basic_mini_excavator.tres")

## 玩家拥有的全部挖掘机。deployed 的照旧留在数组里，UI 用状态区分「在库 / 出勤」
var excavators : Array[ExcavatorUnit] = []

## 首次游玩兜底：没有存档、或存档里一台机器都没有时，送一台起步机
func ensure_starter_excavator() -> void:
	if excavators.is_empty():
		add_excavator()

## 入手一台挖掘机并广播。data 缺省用起步机，名字缺省按序号生成
func add_excavator(data : MineableData = null, display_name : String = "") -> ExcavatorUnit:
	var unit := ExcavatorUnit.new(data if data != null else DEFAULT_EXCAVATOR, display_name)
	if display_name == "":
		unit.display_name = "小型挖掘机 %02d" % (excavators.size() + 1)
	excavators.append(unit)
	excavators_changed.emit()
	return unit

## 当前在库（可派遣）的机器
func get_idle_excavators() -> Array[ExcavatorUnit]:
	var idle : Array[ExcavatorUnit] = []
	for unit in excavators:
		if unit != null and not unit.deployed:
			idle.append(unit)
	return idle

## 标记 deployed 并广播。派遣与回库都走这里，别直接改 unit.deployed
func set_excavator_deployed(unit : ExcavatorUnit, value : bool) -> void:
	if unit == null or unit.deployed == value:
		return
	unit.deployed = value
	excavators_changed.emit()

## 移除一台机器（燃油耗尽销毁）。库存里也要删，否则槽位会永远卡在「出勤中」
func remove_excavator(unit : ExcavatorUnit) -> bool:
	if unit == null:
		return false
	var index := excavators.find(unit)
	if index < 0:
		return false
	excavators.remove_at(index)
	excavators_changed.emit()
	return true

# ---------------------------------------------------------------- 存档

## 存档快照。只放需要跨会话保留的字段，UI 状态一律不入档
func to_dict() -> Dictionary:
	var ids := PackedStringArray()
	for id in unlocked_skills:
		ids.append(String(id))
	var exc := PackedStringArray()
	for unit in excavators:
		if unit != null and unit.data != null and unit.data.resource_path != "":
			exc.append(unit.data.resource_path)
	return {
		"version": SAVE_VERSION,
		"coins": coins,
		"level": level,
		"xp": xp,
		"xp_to_next": xp_to_next,
		"best_depth": best_depth,
		"unlocked_skills": ids,
		"excavators": exc,
	}

## 读档回填。缺字段一律走默认值，兼容旧档与手改坏的档
func apply_dict(data : Dictionary) -> void:
	coins = int(data.get("coins", 0))
	level = maxi(int(data.get("level", 1)), 1)
	xp = maxi(int(data.get("xp", 0)), 0)
	xp_to_next = maxi(int(data.get("xp_to_next", 100)), 1)
	best_depth = maxf(float(data.get("best_depth", 0.0)), 0.0)

	unlocked_skills.clear()
	var ids = data.get("unlocked_skills", PackedStringArray())
	if ids is PackedStringArray or ids is Array:
		for id in ids:
			var skill_id := StringName(str(id))
			if skill_id != &"" and not unlocked_skills.has(skill_id):
				unlocked_skills.append(skill_id)

	# 挖掘机按资源路径重建。出勤状态不入档（GDD 4.11）：读档后全部回库
	excavators.clear()
	var exc = data.get("excavators", PackedStringArray())
	if exc is PackedStringArray or exc is Array:
		for path in exc:
			var res := load(str(path)) as MineableData
			add_excavator(res if res != null else DEFAULT_EXCAVATOR)
	if excavators.is_empty():
		ensure_starter_excavator()

	coins_changed.emit(coins, 0)
	stats_changed.emit()
	skills_changed.emit()
	excavators_changed.emit()
