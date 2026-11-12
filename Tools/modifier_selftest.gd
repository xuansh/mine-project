extends SceneTree

## 改装终端 · 批次 1（数据层）自检。
##
## 跑法（在项目根目录）：
##   godot --headless --path . --script res://Tools/modifier_selftest.gd
##
## 只验证四件事，不碰 UI、不碰存档文件：
##   1. 聚合层把节点加成算对了（加算、减算、固定值三种）
##   2. 应用加成时不会污染原始 .tres（弹出副本）
##   3. Game 的解锁校验按「父节点 + 金币」判定
##   4. to_dict / apply_dict 往返不丢字段
##
## 通过则输出 [PASS]，任何一项不符输出 [FAIL] 并以退出码 1 结束。

const SOURCE := preload("res://Resources/Excavators/basic_mini_excavator.tres")

var _failed : int = 0
var _started : bool = false

## autoload 是在 _initialize 之后才挂到 root 上的，所以真正的检查放到首帧执行
func _process(_delta : float) -> bool:
	if _started:
		return true
	_started = true
	_run_all()
	return true

func _run_all() -> void:
	var game := root.get_node_or_null("/root/Game")
	if game == null:
		printerr("[FAIL] 拿不到 /root/Game，确认 project.godot 里 Game autoload 还在")
		quit(1)
		return

	# 自检会改写 Game 的内存状态，必须关掉自动存档，否则测试数据会盖掉玩家存档
	var saver := root.get_node_or_null("/root/SaveSystem")
	if saver != null:
		saver.autosave_enabled = false

	_test_aggregation(game)
	_test_no_pollution(game)
	_test_unlock_rules(game)
	_test_save_roundtrip(game)

	print("")
	if _failed == 0:
		print("[PASS] 批次 1 全部检查通过")
		quit(0)
	else:
		printerr("[FAIL] 共 %d 项不通过" % _failed)
		quit(1)

# ---------------------------------------------------------------- 1 聚合

func _test_aggregation(game) -> void:
	game.unlocked_skills = _ids([
		&"root",
		&"drill_attack",      # attack +15%
		&"drill_frequency",   # attack_interval -15%
		&"excavator_speed",   # speed +10%
		&"gearbox",           # speed +15%（同键应累加）
		&"fuel_tank",         # fuel_max +40（固定值）
		&"dual_fuel_line",    # fuel_burn -15%
		&"cargo_bay",         # cargo_max +10（固定值）
	])

	var mods = game.get_modifiers()
	print("—— 聚合结果 ——")
	print("attack           +%.0f%%" % (mods.get_pct(&"attack") * 100.0))
	print("attack_interval  -%.0f%%" % (mods.get_pct(&"attack_interval") * 100.0))
	print("excavator_speed  +%.0f%%" % (mods.get_pct(&"excavator_speed") * 100.0))
	print("fuel_max         +%.0f" % mods.get_flat(&"fuel_max"))
	print("cargo_max        +%.0f" % mods.get_flat(&"cargo_max"))

	var data : MineableData = mods.apply_to(SOURCE)
	print("—— 应用后 ——")
	print("attack      %.2f  (期望 9.20)" % data.attack)
	print("interval    %.2f  (期望 0.68)" % data.attack_interval)
	print("speed       %.2f  (期望 12.50)" % data.speed)
	print("total_fuel  %.2f  (期望 140.00)" % data.total_fuel)
	print("burn        %.2f  (期望 3.40)" % data.fuelConsumptionPerSecond)
	print("cargo_max   %d    (期望 30)" % data.cargo_max)

	_expect(data.attack, 9.2, "attack")
	_expect(data.attack_interval, 0.68, "attack_interval")
	_expect(data.speed, 12.5, "speed")
	_expect(data.total_fuel, 140.0, "total_fuel")
	_expect(data.fuelConsumptionPerSecond, 3.4, "fuel_consumption")
	_expect(float(data.cargo_max), 30.0, "cargo_max")

# ---------------------------------------------------------------- 2 不污染源

func _test_no_pollution(game) -> void:
	var mods = game.get_modifiers()
	var copy : MineableData = mods.apply_to(SOURCE)
	if copy == SOURCE:
		_fail("apply_to 返回了同一个对象，源资源会被污染")
		return
	if not is_equal_approx(SOURCE.attack, 8.0):
		_fail("源资源 attack 被改写为 %.2f，应为 8.00" % SOURCE.attack)
		return
	_pass("apply_to 返回副本，源 .tres 未被改写")

# ---------------------------------------------------------------- 4 解锁规则

func _test_unlock_rules(game) -> void:
	game.unlocked_skills = _ids([&"root"])
	game.coins = 0
	if game.can_unlock_skill(&"drill_attack"):
		_fail("金币为 0 时仍判定可解锁")
		return
	if game.can_unlock_skill(&"drill_frequency"):
		_fail("父节点未解锁时仍判定可解锁 drill_frequency")
		return

	game.coins = 1000
	if not game.can_unlock_skill(&"drill_attack"):
		_fail("金币充足、父节点已解锁，却判定不可解锁")
		return
	if not game.unlock_skill(&"drill_attack"):
		_fail("unlock_skill 失败")
		return
	if not game.is_skill_unlocked(&"drill_attack"):
		_fail("解锁后 is_skill_unlocked 仍为 false")
		return
	if game.coins != 920:
		_fail("扣费错误：期望剩余 920，实际 %d" % game.coins)
		return
	if game.can_unlock_skill(&"drill_attack"):
		_fail("重复解锁未被拦住")
		return
	_pass("解锁校验（父节点 / 金币 / 扣费 / 防重复）全部正确")

# ---------------------------------------------------------------- 4 存档往返

func _test_save_roundtrip(game) -> void:
	game.coins = 1234
	game.level = 7
	game.xp = 240
	game.xp_to_next = 2000
	game.best_depth = 138.0
	game.unlocked_skills = _ids([&"root", &"drill_attack", &"ore_value"])

	var snapshot : Dictionary = game.to_dict()
	game.apply_dict(snapshot)

	if game.coins != 1234 or game.level != 7 or game.best_depth != 138.0:
		_fail("to_dict / apply_dict 往返后基础字段不一致")
		return
	if game.unlocked_skills.size() != 3 or not game.is_skill_unlocked(&"ore_value"):
		_fail("to_dict / apply_dict 往返后解锁集合不一致")
		return
	_pass("存档快照往返无丢失")

# ---------------------------------------------------------------- 断言工具

## 转成强类型数组，避免无类型字面量赋给 Array[StringName] 时的转换歧义
func _ids(list : Array) -> Array[StringName]:
	var out : Array[StringName] = []
	for id in list:
		out.append(StringName(id))
	return out

func _expect(actual : float, expected : float, label : String) -> void:
	if absf(actual - expected) < 0.01:
		_pass("%s = %.2f" % [label, actual])
	else:
		_fail("%s = %.2f，期望 %.2f" % [label, actual, expected])

func _pass(message : String) -> void:
	print("  [ok] " + message)

func _fail(message : String) -> void:
	_failed += 1
	printerr("  [FAIL] " + message)
