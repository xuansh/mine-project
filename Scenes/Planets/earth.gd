extends Node3D

## 行星：缓慢自转 + 大气自发光环的开关。
## 光环本体是 AtmosphereRim / AtmosphereHalo 两个球壳（材质用 Shaders/atmosphere_glow.gdshader），
## 发光靠 WorldEnvironment 的 Glow 溢出，颜色/强度直接改 shader 参数即可。

@export_group("自转")
## 自转角速度（弧度/秒）。0.12 ≈ 52 秒转一圈；给负数就是反向转
@export var spin_speed : float = 0.12
## 自转轴，默认绕世界 Y 轴（模拟极轴）
@export var spin_axis : Vector3 = Vector3.UP
## 关掉就停转（展示/暂停用）
@export var spinning : bool = true

@export_group("大气")
## 关掉就是一颗裸星球
@export var atmosphere_visible : bool = true:
	set(value):
		atmosphere_visible = value
		_apply_atmosphere()

@onready var earth : MeshInstance3D = $MeshInstance3D
@onready var _atmosphere_rim : MeshInstance3D = $AtmosphereRim
@onready var _atmosphere_halo : MeshInstance3D = $AtmosphereHalo

func _ready() -> void:
	_apply_atmosphere()

func _process(delta: float) -> void:
	if not spinning:
		return
	# 只转球体本身：大气环各向同性，转不转看不出区别，
	# 这样挂在根节点下的相机和灯光就不会被一起转走。
	earth.rotate(spin_axis.normalized(), spin_speed * delta)

func _apply_atmosphere() -> void:
	if not is_node_ready():
		return
	_atmosphere_rim.visible = atmosphere_visible
	_atmosphere_halo.visible = atmosphere_visible
