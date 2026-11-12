class_name OrbitView
extends Node3D

## 地球全景（GDD 4.12）：主区的"世界地图"。
##
## 一颗地球 + 表面若干黄色标记点（矿场 1 号 / 升级终端）。
## 交互约定（v0.11）：
##   - 地球**不自转**，靠玩家按住左键拖动来转（带一点惯性，松手后缓缓停下）
##   - 标记点本身就是点击目标；名称标签默认隐藏，鼠标悬浮在点上才出现
##   - 点中标记点 → 发 location_activated，由 control 播转场
##
## 独立 SubViewport + own_world_3d，和矿场互不抢环境与相机。

signal location_activated(location : LocationDefinition)

## 标记方块的世界尺寸（正交相机 size 2.2 时约 20px）
const MARKER_MESH_SIZE : float = 0.055
## 2D 命中半径（px）：比视觉稍大一圈，点起来不费劲
const MARKER_HIT_RADIUS : float = 18.0
## 拖动灵敏度（弧度 / 像素）
const DRAG_SENSITIVITY : float = 0.007
## 俯仰角上限，避免把地球翻到背面朝上
const PITCH_LIMIT : float = 1.15
## 松手后的惯性衰减（越大停得越快）
const INERTIA_DAMP : float = 5.0
## 按下到松开移动超过这个距离就算拖动，不触发进入
const CLICK_SLOP : float = 8.0

# 像素 HUD 色板（GDD 4.8）
const COLOR_TEXT := Color(0.941176, 0.933333, 0.894118)
const COLOR_ACCENT := Color(0.85098, 0.635294, 0.152941)
const COLOR_BG := Color(0.043137, 0.039216, 0.070588, 0.88)
const COLOR_MUTED := Color(0.647059, 0.627451, 0.560784)

const DEFAULT_LOCATIONS := [
	preload("res://Datas/Locations/pit_01.tres"),
	preload("res://Datas/Locations/upgrade_terminal.tres"),
]

## 可进入的地点。留空时用上面两份默认配置
@export var locations : Array[LocationDefinition] = []

@export_group("相机")
## 全景取景高度（正交 size），地球约占 45% 画面
@export var camera_size_orbit : float = 2.2

@onready var _camera : Camera3D = $Camera3D
## 地球实例（earth.gd），无类型引用以便动态改 spinning
@onready var _earth = $Earth
@onready var _marker_root : Control = $Labels/Markers

## 旋转枢纽：地球网格挂在这下面，拖动只转它（大气环各向同性，不用跟着转）
var _pivot : Node3D
var _ball : Node3D

## 每个地点：{"location", "anchor", "mesh", "label"}
var _entries : Array[Dictionary] = []
var _active : bool = false

var _yaw : float = 0.0
var _pitch : float = 0.0
var _yaw_velocity : float = 0.0
var _dragging : bool = false
var _drag_travel : float = 0.0
var _pressed_index : int = -1
var _hover_index : int = -1

func _ready() -> void:
	# 地球实例自带的相机是给左栏小窗调的取景，全景用自己这台
	var inner_camera := _earth.get_node_or_null("Camera3D")
	if inner_camera != null:
		inner_camera.queue_free()

	# 关掉地球自己的自转：全景由玩家拖，不自己转
	_earth.spinning = false
	_build_pivot()

	if locations.is_empty():
		for location in DEFAULT_LOCATIONS:
			locations.append(location)

	_camera.size = camera_size_orbit
	_camera.current = true
	_build_markers()
	set_active(false)

## 把地球网格塞进一个枢轴节点，拖动时只改这个节点的欧拉角
func _build_pivot() -> void:
	_pivot = Node3D.new()
	_pivot.name = "SpinPivot"
	_earth.add_child(_pivot)

	_ball = _earth.get_node_or_null("MeshInstance3D") as Node3D
	if _ball == null:
		push_warning("OrbitView: Earth 实例里找不到 MeshInstance3D")
		return
	_ball.reparent(_pivot, false)

## control 切换视图时调用。关掉时不更新标签位置，省掉每帧的投影计算
func set_active(value : bool) -> void:
	_active = value
	if not value:
		_hover_index = -1
		_pressed_index = -1
		_dragging = false
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	for entry in _entries:
		(entry["label"] as Control).visible = false
	if value:
		_camera.size = camera_size_orbit
		_apply_spin()

func _process(delta : float) -> void:
	if not _active:
		return

	# 松手后的惯性：慢慢停下，不做无限打转
	if not _dragging and absf(_yaw_velocity) > 0.0001:
		_yaw += _yaw_velocity
		_yaw_velocity = lerpf(_yaw_velocity, 0.0, clampf(INERTIA_DAMP * delta, 0.0, 1.0))
		_apply_spin()

	var mouse_pos := _marker_root.get_local_mouse_position()
	var inside := Rect2(Vector2.ZERO, _marker_root.size).has_point(mouse_pos)
	_update_hover(_marker_at(mouse_pos) if (inside and not _dragging) else -1)

	var viewport_size := _marker_root.size
	for entry in _entries:
		var anchor : Node3D = entry["anchor"]
		var label : Control = entry["label"]
		var index : int = entry["index"]

		var world_pos := anchor.global_position
		# 转到球背面的地点直接藏起来（相机朝 -Z，basis.z · 方向 > 0 即在背后）
		var behind := _camera.global_transform.basis.z.dot(world_pos - _camera.global_position) > 0.0
		if behind:
			label.visible = false
			continue

		var screen_pos := _camera.unproject_position(world_pos)
		if not Rect2(Vector2.ZERO, viewport_size).grow(64.0).has_point(screen_pos):
			label.visible = false
			continue

		# 标签压在点的上方，居中对齐
		var label_size := label.size if label.size.x > 0.0 else label.get_combined_minimum_size()
		label.position = Vector2(
			clampf(screen_pos.x - label_size.x * 0.5, 6.0, maxf(6.0, viewport_size.x - label_size.x - 6.0)),
			screen_pos.y - label_size.y - 18.0)
		label.visible = index == _hover_index

		# 悬浮的点微微胀大，给一点“能点”的反馈
		var mesh : Node3D = entry["mesh"]
		var target_scale := 1.55 if index == _hover_index else 1.0
		mesh.scale = mesh.scale.lerp(Vector3.ONE * target_scale, clampf(14.0 * delta, 0.0, 1.0))

func _apply_spin() -> void:
	if _pivot == null:
		return
	_pivot.rotation = Vector3(_pitch, _yaw, 0.0)

# ---------------------------------------------------------------- 输入：拖动 / 点击

func _unhandled_input(event : InputEvent) -> void:
	if not _active:
		return

	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			_dragging = true
			_drag_travel = 0.0
			_yaw_velocity = 0.0
			_pressed_index = _marker_at(button.position)
		else:
			_dragging = false
			# 位移很小 + 还停在同一颗点上，才算点击（拖完松手不该误进场景）
			if _pressed_index >= 0 and _drag_travel < CLICK_SLOP \
					and _marker_at(button.position) == _pressed_index:
				_activate(_pressed_index)
			_pressed_index = -1
		return

	var motion := event as InputEventMouseMotion
	if motion != null and _dragging:
		_drag_travel += motion.relative.length()
		_yaw -= motion.relative.x * DRAG_SENSITIVITY
		_pitch = clampf(_pitch - motion.relative.y * DRAG_SENSITIVITY, -PITCH_LIMIT, PITCH_LIMIT)
		# 只记水平速度：竖直拖到顶时不该继续甩
		_yaw_velocity = -motion.relative.x * DRAG_SENSITIVITY * 0.6
		_apply_spin()

## 命中测试：屏幕坐标最近的、且没转到背面的标记点，返回 -1 表示没点中
func _marker_at(screen_pos : Vector2) -> int:
	var best := -1
	var best_distance := MARKER_HIT_RADIUS
	for entry in _entries:
		var anchor : Node3D = entry["anchor"]
		var world_pos := anchor.global_position
		if _camera.global_transform.basis.z.dot(world_pos - _camera.global_position) > 0.0:
			continue
		var distance := _camera.unproject_position(world_pos).distance_to(screen_pos)
		if distance < best_distance:
			best_distance = distance
			best = entry["index"]
	return best

func _update_hover(index : int) -> void:
	if index == _hover_index:
		return
	_hover_index = index
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if index >= 0 else Input.CURSOR_ARROW)

func _activate(index : int) -> void:
	if index < 0 or index >= _entries.size():
		return
	location_activated.emit(_entries[index]["location"])

# ---------------------------------------------------------------- 标记构建

func _build_markers() -> void:
	if _ball == null:
		return

	for i in locations.size():
		var location : LocationDefinition = locations[i]
		if location == null:
			continue
		# 锚点挂在球体网格下，跟着拖动一起转
		var anchor := Node3D.new()
		anchor.name = "Anchor_" + String(location.id)
		_ball.add_child(anchor)
		var normal := location.surface_dir.normalized()
		anchor.position = normal * location.surface_radius
		# 让方块的长轴沿着球面法线"立"着，像插在球面上的一颗钉子
		var ref := Vector3.FORWARD if absf(normal.dot(Vector3.UP)) > 0.95 else Vector3.UP
		var right := ref.cross(normal).normalized()
		anchor.basis = Basis(right, normal, right.cross(normal).normalized())
		var mesh := _build_marker_mesh()
		mesh.position = Vector3(0.0, MARKER_MESH_SIZE * 0.5, 0.0)
		anchor.add_child(mesh)

		var label := _build_marker_label(location)
		_marker_root.add_child(label)

		_entries.append({
			"index": i,
			"location": location,
			"anchor": anchor,
			"mesh": mesh,
			"label": label,
		})

func _build_marker_mesh() -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(MARKER_MESH_SIZE * 0.62, MARKER_MESH_SIZE, MARKER_MESH_SIZE * 0.62)
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = COLOR_ACCENT
	mat.emission_enabled = true
	mat.emission = COLOR_ACCENT
	mat.emission_energy_multiplier = 3.2
	mesh.material_override = mat
	return mesh

## 标签：默认隐藏，悬浮才显示。工程黄描边 + 近黑底，和左栏 HUD 同一套语言
func _build_marker_label(location : LocationDefinition) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.visible = false

	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_BG
	style.border_color = COLOR_ACCENT
	style.set_border_width_all(2)
	style.set_content_margin_all(8)
	style.content_margin_left = 10
	style.content_margin_right = 10
	panel.add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 0)
	panel.add_child(box)

	var title := Label.new()
	title.text = location.display_name
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", COLOR_ACCENT)
	box.add_child(title)

	if not location.sub_label.is_empty():
		var sub := Label.new()
		sub.text = location.sub_label
		sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sub.add_theme_font_size_override("font_size", 12)
		sub.add_theme_color_override("font_color", COLOR_MUTED)
		box.add_child(sub)

	return panel
