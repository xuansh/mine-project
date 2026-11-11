class_name MineableEntity
extends CharacterBody3D

## 挖掉一格时发出。ore 为这一格的矿石数据（可能为 null），value 为掉落价值
signal ore_mined(cell : Vector3i, ore : Oredata, value : float)

## 每攻击一下矿石就发一次，用来做受击反馈 / 挖掘进度条
signal ore_damaged(cell : Vector3i, hp_left : float, hp_max : float)

## 矿石被挖完时发出掉落价值。后面接背包 / 金币 / 统计直接连这里
signal drop_gained(ore_name : String, value : float)

enum State { MOVING, MINING }

## 攻击间隔的兜底值：mineable_data 里没配时用它
const DEFAULT_ATTACK_INTERVAL : float = 0.8

@export var mineable_data : MineableData

## 矿石所在的 GridMap。MineField 的 _ready 里会塞进来
@export var gridmap : GridMap

## 格子里的矿对应哪份 Oredata：下标 = GridMap 的 item id。MineField 的 _ready 里会塞进来
@export var ore_datas : Array[Oredata] = []

## 前进方向（世界坐标）
@export var forward_dir : Vector3 = Vector3(-1, 0, 0)

## 车头前方多远开始判定“有矿”。不要大于一个格子的边长，否则会隔着格子挖
@export var probe_distance : float = 1.8

## 兜底挖掘耗时（秒）。只有查不到矿石数据、或攻击力 <= 0 时才会用
@export var dig_time : float = 1.5

var _state : State = State.MOVING
var _dig_timer : float = 0.0
var _attack_timer : float = 0.0
var _dig_cell : Vector3i = Vector3i.ZERO
var _target_ore : Oredata
var _target_hp : float = 0.0
var _target_hp_max : float = 0.0

func _physics_process(delta : float) -> void:
	match _state:
		State.MOVING:
			_process_moving(delta)
		State.MINING:
			_process_mining(delta)

func _process_moving(delta : float) -> void:
	var direction : Vector3 = forward_dir.normalized()

	# 前方一格有矿就停下开挖
	if gridmap != null:
		var cell_ahead : Vector3i = _cell_ahead(direction)
		if gridmap.get_cell_item(cell_ahead) != GridMap.INVALID_CELL_ITEM:
			_start_mining(cell_ahead)
			return

	var speed : float = 0.0
	if mineable_data != null:
		speed = mineable_data.speed

	velocity = lerp(velocity, direction * speed, delta * 10.0)

	# 车头朝行进方向
	var desired_angle : float = direction.signed_angle_to(Vector3.FORWARD, Vector3.DOWN)
	rotation.y = lerp_angle(rotation.y, desired_angle, delta * 2.5)

	move_and_slide()

func _process_mining(delta : float) -> void:
	velocity = lerp(velocity, Vector3.ZERO, delta * 10.0)
	move_and_slide()

	# 目标格被别的东西清掉了，放弃这次挖掘，别对着空气挥拳
	if gridmap != null and gridmap.get_cell_item(_dig_cell) == GridMap.INVALID_CELL_ITEM:
		_abort_mining()
		return

	# 没有矿石数据 / 攻击力时退回旧的固定耗时挖掘，保证不会卡死
	if _target_ore == null or _attack_damage() <= 0.0:
		_dig_timer -= delta
		if _dig_timer <= 0.0:
			_finish_mining()
		return

	# 按攻击间隔一下一下打，血扣到 0 就挖完
	_attack_timer -= delta
	while _attack_timer <= 0.0:
		_attack()
		if _state != State.MINING:
			return
		_attack_timer += _attack_interval()

## 把“车头前方 probe_distance 处”换算成格子坐标
func _cell_ahead(direction : Vector3) -> Vector3i:
	var probe : Vector3 = global_position + direction * probe_distance
	# 锁定在车身所在的这一层，别因为高度换算到别的 y 层
	probe.y = global_position.y
	return gridmap.local_to_map(gridmap.to_local(probe))

## 查这个格子对应哪份矿石数据
func _ore_at(cell : Vector3i) -> Oredata:
	if gridmap == null:
		return null
	var item : int = gridmap.get_cell_item(cell)
	if item == GridMap.INVALID_CELL_ITEM:
		return null
	if item < 0 or item >= ore_datas.size():
		return null
	return ore_datas[item]

func _attack_damage() -> float:
	if mineable_data == null:
		return 0.0
	return maxf(mineable_data.attack, 0.0)

func _attack_interval() -> float:
	var interval : float = DEFAULT_ATTACK_INTERVAL
	if mineable_data != null and mineable_data.attack_interval > 0.0:
		interval = mineable_data.attack_interval
	return maxf(interval, 0.05)

func _start_mining(cell : Vector3i) -> void:
	_state = State.MINING
	_dig_cell = cell
	_target_ore = _ore_at(cell)
	_dig_timer = dig_time
	# 0 表示到达后立刻打第一下
	_attack_timer = 0.0
	velocity = Vector3.ZERO

	if _target_ore != null:
		_target_hp_max = maxf(_target_ore.hp, 0.0)
		_target_hp = _target_hp_max
	else:
		_target_hp_max = 0.0
		_target_hp = 0.0

func _attack() -> void:
	_target_hp = maxf(_target_hp - _attack_damage(), 0.0)
	ore_damaged.emit(_dig_cell, _target_hp, _target_hp_max)
	if _target_hp <= 0.0:
		_finish_mining()

func _finish_mining() -> void:
	var ore : Oredata = _target_ore
	var value : float = 0.0
	if ore != null:
		# 一格收益 = 掉落数量 × 单价
		value = ore.drop * ore.value

	if gridmap != null:
		gridmap.set_cell_item(_dig_cell, GridMap.INVALID_CELL_ITEM)

	ore_mined.emit(_dig_cell, ore, value)

	if ore != null:
		print("[挖掘] 挖完 %s（耐久 %.0f），掉落 %.1f，金币 +%d" % [ore.ore_name, _target_hp_max, ore.drop, roundi(value)])
		Game.add_coins(value)
		# 后面要接背包 / 统计时连这个信号即可
		drop_gained.emit(ore.ore_name, value)

	_reset_target()

func _abort_mining() -> void:
	_reset_target()

func _reset_target() -> void:
	_target_ore = null
	_target_hp = 0.0
	_target_hp_max = 0.0
	_dig_timer = 0.0
	_attack_timer = 0.0
	_state = State.MOVING
