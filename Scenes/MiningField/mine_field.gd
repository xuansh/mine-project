extends Node3D


@onready var csg_ground: CSGBox3D = $BackgroundRegion3D/CSGGround
@export var gridmap : GridMap
@export var ore_item : int = 0
@export var ground_size : Vector2 = Vector2(50, 50)   # 和 CSGBox3D 的 size.xz 一致

func _ready() -> void:
	var cells := Vector2i(ground_size / Vector2(gridmap.cell_size.x, gridmap.cell_size.z))
	var half := cells / 2
	for x in range(-half.x, half.x):
		for z in range(-half.y, half.y):
			gridmap.set_cell_item(Vector3i(x, 0, z), ore_item)
