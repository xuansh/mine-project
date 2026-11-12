@tool
extends Control

## 技能树缩略预览（只读）。按节点的 position 原样画一遍四向树，
## 用和终端一致的琥珀单色，方便在编辑器里直接看布局对不对。

signal node_clicked(id : StringName)

const COLOR_BG := Color("0B0A12")
const COLOR_CASE := Color("2A2438")
const COLOR_LINK_OFF := Color("3A3020")
const COLOR_LINK_ON := Color("8A6A20")
const COLOR_NODE_OFF := Color("141020")
const COLOR_NODE_ON := Color("2A2210")
const COLOR_EDGE := Color("D9A227")
const COLOR_EDGE_DIM := Color("6E5A1E")
const COLOR_TEXT := Color("F0EEE4")
const COLOR_MUTED := Color("8C8264")

const NODE_W : float = 26.0
const NODE_H : float = 18.0
const PAD : float = 34.0

var tree_data : SkillTreeData
var highlight : StringName = &""

var _scale : float = 1.0
var _origin : Vector2 = Vector2.ZERO
var _hit : Dictionary = {}

func _ready() -> void:
	custom_minimum_size = Vector2(0, 220)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

func set_tree(data : SkillTreeData) -> void:
	tree_data = data
	queue_redraw()

func set_highlight(id : StringName) -> void:
	highlight = id
	queue_redraw()

# ---------------------------------------------------------------- 绘制

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_BG)
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_CASE, false, 1.0)

	if tree_data == null or tree_data.nodes.is_empty():
		_draw_center_text("（空树）", COLOR_MUTED)
		return

	_fit()
	_draw_links()
	_draw_nodes()

func _draw_center_text(text : String, color : Color) -> void:
	var font := get_theme_default_font()
	var fs := 12
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, Vector2((size.x - w) * 0.5, size.y * 0.5), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)

## 把数据坐标压进控件：算包围盒 → 求缩放 → 记下映射参数
func _fit() -> void:
	var min_v := Vector2(INF, INF)
	var max_v := Vector2(-INF, -INF)
	for node in tree_data.nodes:
		if node == null:
			continue
		min_v = min_v.min(node.position)
		max_v = max_v.max(node.position)

	var span := (max_v - min_v)
	var usable := size - Vector2(PAD, PAD) * 2.0
	if span.x < 1.0 and span.y < 1.0:
		_scale = 1.0
		_origin = size * 0.5
		return
	_scale = minf(usable.x / maxf(span.x, 1.0), usable.y / maxf(span.y, 1.0))
	# 半径只有 1 个节点时别放太大
	_scale = minf(_scale, 1.0)
	_origin = size * 0.5 - (min_v + max_v) * 0.5 * _scale

func _to_screen(pos : Vector2) -> Vector2:
	return _origin + pos * _scale

func _draw_links() -> void:
	for node in tree_data.nodes:
		if node == null:
			continue
		for child_id in node.children:
			var child := tree_data.get_node_data(child_id)
			if child == null:
				continue
			var color := COLOR_LINK_ON if child_id == highlight else COLOR_LINK_OFF
			draw_line(_to_screen(node.position), _to_screen(child.position), color, 1.5)

func _draw_nodes() -> void:
	var font := get_theme_default_font()
	_hit.clear()

	for node in tree_data.nodes:
		if node == null:
			continue
		var p := _to_screen(node.position)
		var rect := Rect2(p - Vector2(NODE_W, NODE_H) * 0.5, Vector2(NODE_W, NODE_H))
		var is_on := node.id == highlight
		var is_root := node.id == tree_data.root_id

		if is_root:
			# 根节点画成菱形，和终端里的方块/六边形区分开
			var pts := PackedVector2Array([
				p + Vector2(0, -10), p + Vector2(10, 0), p + Vector2(0, 10), p + Vector2(-10, 0)
			])
			draw_colored_polygon(pts, COLOR_EDGE if is_on else COLOR_EDGE_DIM)
		else:
			draw_rect(rect, COLOR_NODE_ON if is_on else COLOR_NODE_OFF)
			draw_rect(rect, COLOR_EDGE if is_on else COLOR_EDGE_DIM, false, 1.0)

		_hit[node.id] = rect

		# 标签：只给根、分支头、当前选中画，避免糊成一团
		if is_on or is_root or _is_branch_head(node.id):
			var label : String = node.title
			if node.max_level > 1:
				label += "  0/%d" % node.max_level
			var fs := 11
			var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var x := clampf(p.x - w * 0.5, 2.0, maxf(size.x - w - 2.0, 2.0))
			var y := p.y + NODE_H * 0.5 + 12.0
			draw_string(font, Vector2(x, y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
				COLOR_TEXT if is_on else COLOR_MUTED)

func _is_branch_head(id : StringName) -> bool:
	if tree_data == null:
		return false
	var parent := tree_data.get_parent_of(id)
	return parent != null and parent.id == tree_data.root_id

# ---------------------------------------------------------------- 交互

func _gui_input(event : InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	for id in _hit:
		if (_hit[id] as Rect2).grow(4.0).has_point(mb.position):
			node_clicked.emit(id)
			accept_event()
			return
