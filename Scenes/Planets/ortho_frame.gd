extends Camera3D

## 正交相机取景：用「世界宽 × 世界高」表达想看到的世界范围。
##
## Godot 的正交相机只有一个 size（默认表示可见高度），宽度 = size × 视口宽高比，
## 相机本身没法同时锁死宽和高。这个脚本按 fit 锁一个方向，
## 并且保证相机始终对准球心 —— 编辑器预览和游戏里的画面，位置和比例才会一致。

enum Fit {
	FIT_HEIGHT, ## 锁高度：size 恒定，星球大小不随视口比例变（UI 小组件推荐）
	FIT_WIDTH,  ## 锁宽度：size = frame_size.x / 视口宽高比
	CONTAIN,    ## 整块 frame_size 都可见，另一方向留空
	COVER,      ## 铺满 frame_size，另一方向被裁掉
}

## 想看到的世界尺寸（水平 × 垂直），单位与世界坐标一致
@export var frame_size : Vector2 = Vector2(1.05, 1.05):
	set(value):
		frame_size = value
		_apply()

@export var fit : Fit = Fit.FIT_HEIGHT:
	set(value):
		fit = value
		_apply()

@export_group("对准")
## 自动朝向目标（默认球心）。关掉就完全用你在编辑器里摆的角度
@export var auto_aim : bool = true
## 取景中心；球心在原点就是 Vector3.ZERO
@export var aim_target : Vector3 = Vector3.ZERO

func _ready() -> void:
	get_viewport().size_changed.connect(_apply)
	if auto_aim:
		_aim()
	_apply()

func _aim() -> void:
	# look_at 要求位置和目标不重合，重合时跳过
	if global_position.distance_to(aim_target) > 0.001:
		look_at(aim_target, Vector3.UP)

func _apply() -> void:
	if not is_node_ready():
		return
	var vp_size : Vector2 = get_viewport().get_visible_rect().size
	if vp_size.y <= 0.0:
		return

	var aspect : float = vp_size.x / vp_size.y
	# 统一口径：size 表示「可见高度」，宽度自动 = size × aspect
	keep_aspect = Camera3D.KEEP_HEIGHT

	match fit:
		Fit.FIT_HEIGHT:
			size = frame_size.y
		Fit.FIT_WIDTH:
			size = frame_size.x / aspect
		Fit.CONTAIN:
			size = maxf(frame_size.y, frame_size.x / aspect)
		Fit.COVER:
			size = minf(frame_size.y, frame_size.x / aspect)
