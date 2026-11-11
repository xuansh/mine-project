extends Node3D

const GLOWING_QIU = preload("uid://w2uu0r7hx8ed")
const COAL_ORE := preload("res://Resources/Oredata/coal_data.tres")
const RAY_LENGTH : float = 2000.0

@onready var csg_ground: CSGBox3D = $BackgroundRegion3D/CSGGround
@onready var line: MeshInstance3D = $BackgroundRegion3D/CSGGround2/用于放置挖掘机的线
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

## 已经生成的挖掘机，同一时间只保留一台
var _excavator : MineableEntity

func _ready() -> void:
	# 还没来得及在检查器里配矿表时，先只塞煤，保证能跑
	if ore_datas.is_empty():
		ore_datas.append(COAL_ORE)

	var cells := Vector2i(ground_size / Vector2(gridmap.cell_size.x, gridmap.cell_size.z))
	var half := cells / 2
	for x in range(-half.x, half.x):
		for z in range(-half.y, half.y):
			gridmap.set_cell_item(Vector3i(x, 0, z), ore_item)
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

	_spawn_excavator(_spawn_points[best_index])

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

func _spawn_excavator(spawn_position : Vector3) -> void:
	if excavator_scene == null:
		push_warning("MineField: 没有配置 excavator_scene，无法生成挖掘机")
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

	_excavator = excavator
	print("[生成] 挖掘机出现在 (%.2f, %.2f, %.2f)" % [spawn_position.x, spawn_position.y, spawn_position.z])

# ---------------------------------------------------------------- 工具

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
