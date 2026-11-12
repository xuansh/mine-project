extends Node3D

const GLOWING_QIU = preload("uid://w2uu0r7hx8ed")
const COAL_ORE := preload("res://Resources/Oredata/coal_data.tres")
const RAY_LENGTH : float = 2000.0

@onready var csg_ground: CSGBox3D = $BackgroundRegion3D/CSGGround
@onready var line: MeshInstance3D = $BackgroundRegion3D/CSGGround2/用于放置挖掘机的线
@onready var _camera: Camera3D = $Camera3D
@export var gridmap : GridMap
@export var ore_item : int = 0
@export var ground_size : Vector2 = Vector2(50, 50)   # 和 CSGBox3D 的 size.xz 一致
@export var qiu_offset : float = 0.0

## 矿石表：下标 = GridMap 的 item id。留空时自动用下面的 COAL_ORE 兜底
@export var ore_datas : Array[Oredata] = []

## 点击小球附近的吸附半径（水平世界距离）。点得比这个远就不生成
@export var spawn_snap_radius : float = 3.0

## 挖掘机生成高度（小球本身的 y 是抬高的，生成时贴地）
@export var spawn_height : float = 0.0

## 射线打空时的地面兜底高度（CSGGround 顶面在 y = 0.5）
@export var ground_height : float = 0.5

## 生成用的挖掘机场景
@export var excavator_scene : PackedScene = preload("res://Scenes/MineableEntity/basic_mini_excavator.tscn")

## 所有可吸附的落脚点（每个小球一个），来自 _ready 里生成的小球
var _spawn_points : Array[Vector3] = []

## 挖掘机生成时广播，HUD 靠它接油量/掉落信号
signal excavator_spawned(excavator : MineableEntity)

## 机器回库时广播（挖空一行 / 燃油耗尽），底栏与提示行靠它刷新（GDD 4.11）
signal excavator_returned(unit : ExcavatorUnit, reason : String)

## 已经生成的挖掘机，同一时间只保留一台
var _excavator : MineableEntity

## 当前在场机器对应的库存条目（GDD 4.11）。回收时置回「在库」
var _deployed_unit : ExcavatorUnit

## 底栏里被点选、等待派遣的机器。null = 未选中（派第一台在库的）
var _selected_unit : ExcavatorUnit

## 矿区格子包围盒（x/z）。生成机器时塞给实体做「走到头」判定
var _field_bounds : Rect2i = Rect2i()

func _ready() -> void:
	# 还没来得及在检查器里配矿表时，先只塞煤，保证能跑
	if ore_datas.is_empty():
		ore_datas.append(COAL_ORE)

	var cells := Vector2i(ground_size / Vector2(gridmap.cell_size.x, gridmap.cell_size.z))
	var half := cells / 2
	for x in range(-half.x, half.x):
		for z in range(-half.y, half.y):
			gridmap.set_cell_item(Vector3i(x, 0, z), ore_item)

	# 场地包围盒：回收判定要用（机器走出包围盒 = 这一行走到头）
	_field_bounds = _compute_field_bounds(gridmap)
	var dict = get_z_bounds(gridmap)
	var min_z = dict['min_z']
	var max_z = dict['max_z']
	for i in range(min_z - 1, max_z):
		var local_pos = gridmap.map_to_local(Vector3i(0, 0, i))
		var node = GLOWING_QIU.instantiate() as Node3D
		line.add_child(node)
		node.global_position.z = gridmap.to_global(local_pos).z + qiu_offset
		# 小球只用来标位置，真正的落脚点在地面上（y = spawn_height）
		_spawn_points.append(Vector3(node.global_position.x, spawn_height, node.global_position.z))

	# 挖掘机现在改成点击生成。场景里如果还留着预置的，清掉，免得出现两台
	for child in get_children():
		if child is MineableEntity:
			child.queue_free()

# ---------------------------------------------------------------- 转场（GDD 4.12）

## 正交相机的取景高度。数值越大画面越"缩小"，转场靠它在 40 ↔ 130 之间推拉
func set_camera_size(value : float) -> void:
	if _camera != null:
		_camera.size = value

# ---------------------------------------------------------------- 点击生成

func _unhandled_input(event : InputEvent) -> void:
	if is_instance_valid(_excavator):
		return
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			_try_spawn_at_screen_point(mouse_event.position)

## 屏幕坐标 → 地面点 → 吸附到最近的小球 → 生成挖掘机
func _try_spawn_at_screen_point(screen_position : Vector2) -> void:
	var click_point = _screen_to_ground(screen_position)
	if click_point == null:
		return

	var best_index : int = -1
	var best_distance : float = INF
	for i in _spawn_points.size():
		var point : Vector3 = _spawn_points[i]
		var distance : float = Vector2(point.x - click_point.x, point.z - click_point.z).length()
		if distance < best_distance:
			best_distance = distance
			best_index = i

	if best_index < 0:
		print("[生成] 场上没有可用的落脚点")
		return
	if best_distance > spawn_snap_radius:
		print("[生成] 点得太远了，最近的小球也差 %.2f（吸附半径 %.2f）" % [best_distance, spawn_snap_radius])
		return

	# 派遣的是底栏里的具体一台机器（GDD 4.11）：
	# 选中了就派选中的，没选中就自动派第一台在库的——保留旧的手感
	var unit := _pick_excavator()
	if unit == null:
		print("[派遣] 底栏没有可派遣的挖掘机")
		return
	_spawn_excavator(_spawn_points[best_index], unit)

## 屏幕坐标投到地面上。打不到地面返回 null
func _screen_to_ground(screen_position : Vector2):
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null

	var from : Vector3 = camera.project_ray_origin(screen_position)
	var direction : Vector3 = camera.project_ray_normal(screen_position)

	var query := PhysicsRayQueryParameters3D.create(from, from + direction * RAY_LENGTH)
	query.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		return hit.position

	# 兜底：和地面平面求交（CSG 碰撞没生效时也不至于点不动）
	if absf(direction.y) < 0.0001:
		return null
	var t : float = (ground_height - from.y) / direction.y
	if t <= 0.0:
		return null
	return from + direction * t

## 选一台机器派遣：优先底栏选中的，否则第一台在库的
func _pick_excavator() -> ExcavatorUnit:
	if _selected_unit != null and not _selected_unit.deployed:
		return _selected_unit
	var idle := Game.get_idle_excavators()
	return idle[0] if not idle.is_empty() else null

func _spawn_excavator(spawn_position : Vector3, unit : ExcavatorUnit) -> void:
	if excavator_scene == null:
		push_warning("MineField: 没有配置 excavator_scene，无法生成挖掘机")
		return
	if unit == null or unit.deployed:
		return

	var excavator := excavator_scene.instantiate() as MineableEntity
	if excavator == null:
		push_warning("MineField: excavator_scene 的根节点不是 MineableEntity")
		return

	add_child(excavator)
	excavator.global_position = spawn_position
	# 出生就面朝前进方向（默认 -X）
	excavator.rotation.y = excavator.forward_dir.signed_angle_to(Vector3.FORWARD, Vector3.DOWN)
	excavator.gridmap = gridmap
	excavator.ore_datas = ore_datas
	excavator.field_bounds = _field_bounds

	# 挖空一行 / 油耗尽 → 自动回库（GDD 4.11）
	excavator.row_finished.connect(_on_excavator_row_finished)
	excavator.fuel_empty.connect(_on_excavator_fuel_empty)

	Game.set_excavator_deployed(unit, true)
	_deployed_unit = unit
	_selected_unit = null

	_excavator = excavator
	excavator_spawned.emit(excavator)
	print("[派遣] %s 出现在 (%.2f, %.2f, %.2f)" % [unit.display_name, spawn_position.x, spawn_position.y, spawn_position.z])

# ---------------------------------------------------------------- 回收（GDD 4.11）

## 这一行走到头：把机器收回落进底栏
func _on_excavator_row_finished() -> void:
	_retire_excavator("本行已挖空，%s 回库", true)

## 油耗尽：机器直接销毁（GDD 4.11.3），库存里那一台也一并移除
func _on_excavator_fuel_empty() -> void:
	_retire_excavator("燃油耗尽，%s 报废", false)

## keep_unit = true 回库（槽位变回在库）；false = 报废销毁（库存条目也删）
func _retire_excavator(reason_format : String, keep_unit : bool) -> void:
	var unit := _deployed_unit
	_deployed_unit = null
	if _excavator != null:
		_excavator.row_finished.disconnect(_on_excavator_row_finished)
		_excavator.fuel_empty.disconnect(_on_excavator_fuel_empty)
		if not _excavator.is_out_of_fuel():
			# 油耗尽的机器在 _die() 里已经 queue_free，这里只收走正常回库的
			_excavator.queue_free()
	_excavator = null

	if unit != null:
		var reason : String = reason_format % unit.display_name
		if keep_unit:
			Game.set_excavator_deployed(unit, false)
		else:
			Game.remove_excavator(unit)
		excavator_returned.emit(unit, reason)
		print("[回收] " + reason)

# ---------------------------------------------------------------- 底栏数据源（GDD 4.11）

## control.gd 绑定底栏时调用：本场景实现这组协议，底栏 UI 不认识业务

func get_inventory_context() -> String:
	return "一号坑 · 挖掘机"

func get_inventory_hint() -> String:
	if _deployed_unit != null:
		return "%s 正在矿区作业 · 挖完这一行会自动回库" % _deployed_unit.display_name
	if _selected_unit != null:
		return "已选中 %s · 点击矿区发光小球附近派遣" % _selected_unit.display_name
	if Game.get_idle_excavators().is_empty():
		return "没有可派遣的挖掘机 · 等待在库机器回库"
	return "点击底栏选中机器（不选则自动派第一台），再点矿区发光小球附近派遣"

func get_inventory_slots() -> Array[InventorySlot]:
	var slots : Array[InventorySlot] = []
	for unit in Game.excavators:
		if unit == null:
			continue
		var slot := InventorySlot.new()
		slot.title = unit.display_name
		slot.subtitle = unit.summary()
		slot.payload = unit
		if unit.deployed:
			slot.state = InventorySlot.State.ACTIVE
			slot.status_text = "出勤中"
		else:
			slot.state = InventorySlot.State.READY
			slot.status_text = "在库 · 点击选中"
		slots.append(slot)
	return slots

## 当前选中机器在底栏里的下标，-1 = 未选中
func get_selected_slot_index() -> int:
	return Game.excavators.find(_selected_unit)

## 底栏槽位被点击：在库的设为选中，出勤中的只提示
func on_inventory_slot_activated(index : int) -> void:
	if index < 0 or index >= Game.excavators.size():
		return
	var unit := Game.excavators[index]
	if unit == null:
		return
	if unit.deployed:
		print("[底栏] %s 正在矿区作业" % unit.display_name)
		return
	_selected_unit = unit
	print("[底栏] 已选中 %s" % unit.display_name)

# ---------------------------------------------------------------- 工具

## 统计 used cells 的 x/z 包围盒（含端点）。回收判定「走出场地」用
func _compute_field_bounds(grid_map : GridMap) -> Rect2i:
	var used := grid_map.get_used_cells()
	if used.is_empty():
		return Rect2i()
	var min_pos := Vector2i(used[0].x, used[0].z)
	var max_pos := min_pos
	for cell in used:
		min_pos.x = mini(min_pos.x, cell.x)
		min_pos.y = mini(min_pos.y, cell.z)
		max_pos.x = maxi(max_pos.x, cell.x)
		max_pos.y = maxi(max_pos.y, cell.z)
	return Rect2i(min_pos, max_pos - min_pos + Vector2i.ONE)

## 某个 GridMap item id 对应的矿石数据，查不到返回 null
func get_ore_data(item : int) -> Oredata:
	if item < 0 or item >= ore_datas.size():
		return null
	return ore_datas[item]

func get_z_bounds(grid_map: GridMap) -> Dictionary:
	var cells = grid_map.get_used_cells()
	if cells.is_empty():
		return {"min_z": 0, "max_z": 0}

	var min_z = cells[0].z
	var max_z = cells[0].z

	for cell in cells:
		min_z = min(min_z, cell.z)
		max_z = max(max_z, cell.z)

	return {"min_z": min_z, "max_z": max_z}
