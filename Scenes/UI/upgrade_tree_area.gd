class_name UpgradeTreeArea
extends Control

## 升级面板的节点树区域：中心核心 + 四向改装节点，
## 连线与布局由这里统一管理，购买逻辑留给 upgrade_panel.gd。

signal buy_requested(group : StringName)

const GroupNodeScript := preload("res://Scenes/UI/upgrade_group_node.gd")

## 四向布局：与技能树的方向一致（左上钻头 / 右上货舱 / 左下引擎 / 右下油箱）
const GROUP_OFFSETS := {
	&"drill": Vector2(-210, -120),
	&"cargo": Vector2(210, -120),
	&"engine": Vector2(-210, 120),
	&"fuel": Vector2(210, 120),
}
const GROUP_ACCENTS := {
	&"drill": Color("d9a227"),
	&"cargo": Color("e09540"),
	&"engine": Color("3fbfa5"),
	&"fuel": Color("5a8fd0"),
}

var _core : UpgradeGroupNode
var _nodes : Dictionary = {}

func _ready() -> void:
	resized.connect(_layout)

## group_title 形如 { &"drill": "钻头", ... }
func setup(group_titles : Dictionary) -> void:
	for child in get_children():
		child.queue_free()
	_nodes.clear()

	_core = GroupNodeScript.new()
	_core.setup(&"core", "挖掘核心", Color(0.9098039, 0.76862746, 0.41568628), true)
	add_child(_core)

	for group in group_titles:
		var node := GroupNodeScript.new() as UpgradeGroupNode
		node.setup(group, group_titles[group], GROUP_ACCENTS.get(group, Color("d9a227")))
		add_child(node)
		node.pressed.connect(func(g : StringName) -> void: buy_requested.emit(g))
		_nodes[group] = node

	_layout()

func update_node(group : StringName, level : int, price_text : String, state : UpgradeGroupNode.State) -> void:
	if _nodes.has(group):
		(_nodes[group] as UpgradeGroupNode).update_state(level, price_text, state)

# ---------------------------------------------------------------- 布局与连线

func _layout() -> void:
	if _core == null:
		return
	var center := size * 0.5
	_core.position = center - _core.size * 0.5
	for group in _nodes:
		var node : UpgradeGroupNode = _nodes[group]
		var offset : Vector2 = GROUP_OFFSETS.get(group, Vector2(0, -160))
		node.position = center + offset - node.size * 0.5
	queue_redraw()

func _draw() -> void:
	if _core == null:
		return
	var from := _core.position + _core.size * 0.5
	for group in _nodes:
		var node : UpgradeGroupNode = _nodes[group]
		var to := node.position + node.size * 0.5
		var col : Color = GROUP_ACCENTS.get(group, Color("d9a227"))
		# 硬边双层连线，和技能树的连线画法同源
		draw_line(from, to, Color(col, 0.15), 8.0, false)
		draw_line(from, to, Color(col, 0.8), 2.0, false)
