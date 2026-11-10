extends Camera3D

## 地面平面的世界高度，射线打空时用它兜底（CSG/碰撞体没生效也不至于整个点击失效）
@export var ground_height : float = 0.5

## 挖掘机节点
@export var excavator_path : NodePath = ^"../CharacterBody3D"

## 射线长度。原来写 100 太短，稍微点远一点就打空
const RAY_LENGTH : float = 2000.0

@onready var _excavator : MineableEntity = get_node_or_null(excavator_path) as MineableEntity

func _unhandled_input(event : InputEvent) -> void:
	if not event.is_action_pressed("Mouse-LeftClick"):
		return

	if _excavator == null:
		push_warning("Camera3D: 找不到挖掘机节点 %s" % excavator_path)
		return

	# 用事件自带的坐标：SubViewport 里运行时这是子视口坐标，不会被主界面干扰
	var mouse_event := event as InputEventMouseButton
	if mouse_event == null:
		return
	var mouse_position : Vector2 = mouse_event.position
	var from : Vector3 = project_ray_origin(mouse_position)
	var ray_dir : Vector3 = project_ray_normal(mouse_position)
	var to : Vector3 = from + ray_dir * RAY_LENGTH

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_bodies = true
	# 别让射线打中挖掘机自己，否则目标点会落在自己头顶上
	var exclude : Array[RID] = [_excavator.get_rid()]
	query.exclude = exclude

	var result := get_world_3d().direct_space_state.intersect_ray(query)

	var target : Vector3
	if result.is_empty():
		# 兜底：直接和地平面求交
		if absf(ray_dir.y) < 0.0001:
			return
		var t : float = (ground_height - from.y) / ray_dir.y
		if t <= 0.0:
			return
		target = from + ray_dir * t
		print("[点击] 射线没命中任何碰撞体，改用地面平面兜底")
	else:
		target = result.position

	# 落点可能在导航网格外（地面边缘），统一吸附到最近的导航网格点
	var navigation_map : RID = get_world_3d().navigation_map
	var snapped : Vector3 = NavigationServer3D.map_get_closest_point(navigation_map, target)

	_excavator.set_destination(snapped)
