class_name MineableEntity
extends CharacterBody3D

## 到点判定半径（水平距离，米）。到这个范围内就彻底停下
const ARRIVE_DISTANCE : float = 0.15

@export var mineable_data : MineableData
@onready var agent : NavigationAgent3D = $NavigationAgent3D

var _destination : Vector3
var _has_destination : bool = false

## 设置寻路目标（世界坐标）
func set_destination(destination : Vector3) -> void:
	_destination = destination
	_has_destination = true
	agent.target_position = destination

## 立即停下
func stop_moving() -> void:
	_has_destination = false
	velocity = Vector3.ZERO

func _physics_process(delta : float) -> void:
	var desired_velocity := Vector3.ZERO

	if _has_destination:
		var to_destination : Vector3 = _destination - global_position
		to_destination.y = 0.0
		var distance_to_destination : float = to_destination.length()

		# 只在这里用直线距离判“到点”。
		# 不能用 agent.is_navigation_finished()：导航网格在 y=1、
		# 车身在 y≈-0.15，垂直差已经大于 target_desired_distance，
		# agent 永远认为没到，会在终点附近每帧修正 -> 抖动。
		if distance_to_destination <= ARRIVE_DISTANCE:
			stop_moving()
		else:
			# 严格跟导航路径的下一个点走。
			# 不要用“朝终点的直线方向”去过滤它：绕墙时下一个路径点
			# 经常在侧方甚至身后，一过滤就会扔掉路径直接朝墙撞。
			var to_next : Vector3 = agent.get_next_path_position() - global_position
			to_next.y = 0.0

			# 只有路径点和自身重合（空路径/已站在该点）时才退回直线
			if to_next.length_squared() < 0.0001:
				to_next = to_destination

			var distance_to_next : float = to_next.length()
			var direction : Vector3 = to_next / distance_to_next

			var speed : float = 0.0
			if mineable_data != null:
				speed = mineable_data.speed

			# 本帧最多走到下一个路径点，绝不冲过它再折返
			var move_speed : float = minf(speed, distance_to_next / delta)
			desired_velocity = direction * move_speed

			# 车头朝行进方向
			var desired_angle : float = direction.signed_angle_to(Vector3.FORWARD, Vector3.DOWN)
			rotation.y = lerp_angle(rotation.y, desired_angle, delta * 0.5 * move_speed)

	velocity = lerp(velocity, desired_velocity, delta * 10.0)
	move_and_slide()
