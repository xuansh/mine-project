class_name SkillTree
extends Control

## 2D 升级树界面。节点布局与连线由 SkillNodeData 数据驱动，
## 目前只做展示与选中，升级扣费/生效留给后续系统。

signal close_requested
signal skill_selected(skill_id : StringName)

const TreeNodeScript := preload("res://Scenes/UI/SkillTree/skill_tree_node.gd")

const BACKGROUND_COLOR := Color("0b0806")
const STAR_SEED : int = 20261111

@export var tree_data : SkillTreeData

## 原型阶段：只有根节点是激活的。接入升级系统后改由存档 / Game 提供
var _unlocked : Array[StringName] = [&"root"]

var _nodes : Dictionary = {}
var _selected_id : StringName = &""
var _stars : Array[Vector4] = []
var _glow_texture : GradientTexture2D
var _fade_tween : Tween

@onready var _tree_area : Control = %TreeArea
@onready var _status_label : Label = %StatusLabel
@onready var _name_label : Label = %NameLabel
@onready var _effect_label : Label = %EffectLabel
@onready var _desc_label : Label = %DescLabel
@onready var _cost_label : Label = %CostLabel
@onready var _action_button : Button = %ActionButton
@onready var _close_button : Button = %CloseButton

func _ready() -> void:
	_make_stars()
	_make_glow_texture()

	if tree_data == null:
		push_error("SkillTree: 未配置 tree_data")
		return
	if not tree_data.is_valid():
		push_error("SkillTree: root_id 在 nodes 里找不到")
		return

	_build_nodes()
	_connect_ui()

	resized.connect(_layout_nodes)
	_tree_area.resized.connect(_layout_nodes)
	_layout_nodes()

	_select(tree_data.root_id)

# ---------------------------------------------------------------- 开关

func open() -> void:
	visible = true
	modulate.a = 0.0
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "modulate:a", 1.0, 0.16)
	if _selected_id == &"" and tree_data != null:
		_select(tree_data.root_id)

func close() -> void:
	visible = false
	modulate.a = 1.0
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()

## 当前选中的节点 id，升级系统/外部 UI 可以用它做联动
func get_selected_id() -> StringName:
	return _selected_id

# ---------------------------------------------------------------- 构建

func _build_nodes() -> void:
	for node_data in tree_data.nodes:
		if node_data == null:
			continue
		var node := TreeNodeScript.new() as SkillTreeNode
		node.name = "Node_" + String(node_data.id)
		_tree_area.add_child(node)
		node.setup(node_data, _state_for(node_data.id))
		node.pressed.connect(_on_node_pressed)
		_nodes[node_data.id] = node

func _connect_ui() -> void:
	_close_button.pressed.connect(_on_close_pressed)
	_action_button.pressed.connect(_on_action_pressed)

func _state_for(node_id : StringName) -> SkillTreeNode.State:
	if _unlocked.has(node_id):
		return SkillTreeNode.State.UNLOCKED
	var parent := tree_data.get_parent_of(node_id)
	if parent != null and _unlocked.has(parent.id):
		return SkillTreeNode.State.AVAILABLE
	return SkillTreeNode.State.LOCKED

func _layout_nodes() -> void:
	if _tree_area == null:
		return
	var center := _tree_area.size * 0.5
	for node_id in _nodes:
		var node : SkillTreeNode = _nodes[node_id]
		if node.data == null:
			continue
		node.position = center + node.data.position - node.size * 0.5
	queue_redraw()

# ---------------------------------------------------------------- 选中与详情

func _on_node_pressed(node_id : StringName) -> void:
	_select(node_id)

func _select(node_id : StringName) -> void:
	if not _nodes.has(node_id):
		return
	_selected_id = node_id
	for key in _nodes:
		var node : SkillTreeNode = _nodes[key]
		node.set_selected(key == node_id)
	_update_detail(node_id)
	skill_selected.emit(node_id)

func _update_detail(node_id : StringName) -> void:
	var data := tree_data.get_node_data(node_id)
	if data == null:
		return

	_name_label.text = data.title
	_effect_label.text = data.get_effect_text()
	_desc_label.text = data.description

	var state := _state_for(node_id)
	match state:
		SkillTreeNode.State.UNLOCKED:
			_status_label.text = "●  已激活"
			_status_label.add_theme_color_override("font_color", Color("7bd6a4"))
			_cost_label.visible = false
			_action_button.text = "已激活"
			_action_button.disabled = true
		SkillTreeNode.State.AVAILABLE:
			_status_label.text = "○  可解锁"
			_status_label.add_theme_color_override("font_color", data.accent_color)
			_cost_label.visible = true
			if data.cost > 0:
				_cost_label.text = "解锁消耗   %d 金币" % data.cost
			else:
				_cost_label.text = "解锁消耗   ——"
			_action_button.text = "解锁（升级系统待接入）"
			_action_button.disabled = true
		_:
			_status_label.text = "·  未解锁"
			_status_label.add_theme_color_override("font_color", Color("7c6f5c"))
			_cost_label.visible = true
			_cost_label.text = "需要先激活前置节点"
			_action_button.text = "不可用"
			_action_button.disabled = true

func _on_close_pressed() -> void:
	close_requested.emit()

func _on_action_pressed() -> void:
	# TODO: 接入 Game.spend_coins + 存档里的已解锁节点，再刷新 _state_for
	pass

# ---------------------------------------------------------------- 绘制

func _draw() -> void:
	_draw_backdrop()
	_draw_links()

func _draw_backdrop() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND_COLOR)

	# 树中心的暖色辉光。先画在星星下面，避免把星点糊掉
	if _glow_texture != null:
		var center := size * Vector2(0.47, 0.5)
		var glow_size := Vector2(size.x * 1.0, size.y * 1.15)
		draw_texture_rect(_glow_texture, Rect2(center - glow_size * 0.5, glow_size), false)

	for star in _stars:
		var color := Color(0.92, 0.86, 0.72, star.w)
		draw_circle(Vector2(star.x * size.x, star.y * size.y), star.z, color)

func _draw_links() -> void:
	for node_id in _nodes:
		var parent_node : SkillTreeNode = _nodes[node_id]
		if parent_node.data == null:
			continue
		for child_id in parent_node.data.children:
			if not _nodes.has(child_id):
				continue
			var child_node : SkillTreeNode = _nodes[child_id]
			var from := parent_node.position + parent_node.size * 0.5 + _tree_area.position
			var to := child_node.position + child_node.size * 0.5 + _tree_area.position
			var color := child_node.data.accent_color
			if child_node.state == SkillTreeNode.State.LOCKED:
				color = color.darkened(0.55)

			draw_line(from, to, Color(color, 0.10), 14.0, true)
			draw_line(from, to, Color(color, 0.24), 6.0, true)
			draw_line(from, to, Color(color, 0.85), 2.5, true)

func _make_stars() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = STAR_SEED
	for i in 110:
		_stars.append(Vector4(
			rng.randf(),
			rng.randf(),
			rng.randf_range(0.6, 1.7),
			rng.randf_range(0.04, 0.20)
		))

## 径向渐变贴图：比叠几层圆更平滑，不会出现一圈圈的色阶
func _make_glow_texture() -> void:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	gradient.colors = PackedColorArray([
		Color(0.44, 0.29, 0.11, 0.16),
		Color(0.42, 0.27, 0.10, 0.06),
		Color(0.40, 0.26, 0.10, 0.0),
	])
	_glow_texture = GradientTexture2D.new()
	_glow_texture.gradient = gradient
	_glow_texture.width = 512
	_glow_texture.height = 512
	_glow_texture.fill = GradientTexture2D.FILL_RADIAL
	_glow_texture.fill_from = Vector2(0.5, 0.5)
	_glow_texture.fill_to = Vector2(1.0, 0.5)
