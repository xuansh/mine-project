extends SceneTree

## 底栏 / 持有物（GDD 4.11）数据层自检。
##
## 跑法（在项目根目录）：
##   godot --headless --path . --script res://Tools/inventory_selftest.gd
##
## 只验证数据层五件事，不碰 UI：
##   1. 首次游玩兜底：空库存自动补一台起步机
##   2. 派遣 / 回库：deployed 状态切换与 idle 列表正确
##   3. 报废：remove_excavator 从库存里删掉条目（燃油耗尽流程）
##   4. 存档往返：excavators 按资源路径重建，读档后全部回库
##   5. 旧档兼容：没有 excavators 字段的存档也能回填且不丢起步机
##
## 通过则输出 [PASS]，任何一项不符输出 [FAIL] 并以退出码 1 结束。

var _failed : int = 0
var _started : bool = false

func _process(_delta : float) -> bool:
	if _started:
		return true
	_started = true
	_run_all()
	return true

func _run_all() -> void:
	var game := root.get_node_or_null("/root/Game")
	if game == null:
		printerr("[FAIL] 拿不到 /root/Game")
		quit(1)
		return

	var saver := root.get_node_or_null("/root/SaveSystem")
	if saver != null:
		saver.autosave_enabled = false

	_test_starter_grant(game)
	_test_deploy_roundtrip(game)
	_test_scrap(game)
	_test_save_roundtrip(game)
	_test_legacy_save(game)

	print("")
	if _failed == 0:
		print("[PASS] 持有物数据层全部检查通过")
		quit(0)
	else:
		printerr("[FAIL] 共 %d 项不通过" % _failed)
		quit(1)

# ---------------------------------------------------------------- 1 起步机

func _test_starter_grant(game) -> void:
	game.excavators.clear()
	game.ensure_starter_excavator()
	if game.excavators.size() != 1:
		_fail("空库存没补起步机，size = %d" % game.excavators.size())
		return
	var unit = game.excavators[0]
	if unit.data == null or unit.data.attack <= 0.0:
		_fail("起步机没有数据或攻击力非法")
		return
	if unit.deployed:
		_fail("起步机初始状态不应是出勤中")
		return
	_pass("空库存自动补一台起步机（%s）" % unit.display_name)

# ---------------------------------------------------------------- 2 派遣 / 回库

func _test_deploy_roundtrip(game) -> void:
	game.excavators.clear()
	game.add_excavator()
	game.add_excavator()

	var idle : Array[ExcavatorUnit] = game.get_idle_excavators()
	if idle.size() != 2:
		_fail("两台在库时 idle 数量 = %d，期望 2" % idle.size())
		return

	var unit = idle[0]
	game.set_excavator_deployed(unit, true)
	if unit.deployed != true:
		_fail("set_excavator_deployed(true) 未生效")
		return
	if game.get_idle_excavators().size() != 1:
		_fail("派遣后 idle 数量 = %d，期望 1" % game.get_idle_excavators().size())
		return

	game.set_excavator_deployed(unit, false)
	if game.get_idle_excavators().size() != 2:
		_fail("回库后 idle 数量 = %d，期望 2" % game.get_idle_excavators().size())
		return
	if game.excavators.size() != 2:
		_fail("回库不应改变库存总数，实际 %d" % game.excavators.size())
		return
	_pass("派遣 / 回库状态切换正确，库存总数不变")

# ---------------------------------------------------------------- 3 报废

func _test_scrap(game) -> void:
	game.excavators.clear()
	game.add_excavator()
	var unit = game.excavators[0]
	game.set_excavator_deployed(unit, true)

	if not game.remove_excavator(unit):
		_fail("remove_excavator 返回 false，出勤中的机器没被删掉")
		return
	if not game.excavators.is_empty():
		_fail("报废后库存还剩 %d 台，期望 0" % game.excavators.size())
		return
	if game.remove_excavator(unit):
		_fail("重复 remove_excavator 不该成功")
		return
	_pass("报废流程：出勤中的机器从库存移除，重复删除被拦住")

# ---------------------------------------------------------------- 4 存档往返

func _test_save_roundtrip(game) -> void:
	game.excavators.clear()
	game.add_excavator()
	game.add_excavator()
	var deployed = game.excavators[1]
	game.set_excavator_deployed(deployed, true)

	var snapshot : Dictionary = game.to_dict()
	game.apply_dict(snapshot)

	if game.excavators.size() != 2:
		_fail("存档往返后机器数量 = %d，期望 2" % game.excavators.size())
		return
	for unit in game.excavators:
		if unit.deployed:
			_fail("读档后仍有机器处于出勤状态，应全部回库")
			return
		if unit.data == null or unit.data.attack <= 0.0:
			_fail("读档后机器数据丢失")
			return
	_pass("存档往返：机器按路径重建，读档后全部回库")

# ---------------------------------------------------------------- 4 旧档兼容

func _test_legacy_save(game) -> void:
	var legacy : Dictionary = game.to_dict()
	legacy.erase("excavators")
	game.apply_dict(legacy)
	if game.excavators.is_empty():
		_fail("旧档（无 excavators 字段）没有补起步机")
		return
	_pass("旧档兼容：缺字段时自动回填起步机")

# ---------------------------------------------------------------- 断言工具

func _pass(message : String) -> void:
	print("  [ok] " + message)

func _fail(message : String) -> void:
	_failed += 1
	printerr("  [FAIL] " + message)
