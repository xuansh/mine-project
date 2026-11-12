class_name SkillTree
extends Control

## 改装终端（GDD 4.10）：琥珀单色 CRT 界面。
## 三分栏：左分支索引 / 中四向树 / 右详情。
## 节点布局与连线由 SkillNodeData 数据驱动，解锁状态、扣费与数值效果统一走 Game。

signal close_requested
signal skill_selected(skill_id : StringName)

const TreeNodeScript := preload("res://Scenes/UI/SkillTree/skill_tree_node.gd")

## CRT 色板（GDD 4.10.6，全部取自布局验证稿 terminal_preview.html）
const COLOR_OUT := Color("05040A")        # 屏外底色
const COLOR_FILL := Color("0B0A12")       # 屏内底色
const COLOR_CASE := Color("8B84A8")       # 机框描边
const COLOR_CASE_IN := Color("2A2438")    # 机框内描边 / 分隔线
const COLOR_AMBER := Color("D9A227")      # 荧光主色
const COLOR_AMBER_DIM := Color("6E5A1E")  # 暗态荧光
const COLOR_AMBER_DEEP := Color("4A3D22") # 断电线路
const COLOR_TEXT := Color("F0EEE4")       # 正文
const COLOR_MUTED := Color("8C8264")      # 次要文字
const COLOR_UNAFFORD := Color("8A6A20")   # 余额不足（色板无红，用暗琥珀）

const CASE_INSET : float = 16.0           # 机框距主区边缘
const CORNER_INSET : float = 8.0          # L 角标距机框边缘
const CORNER_ARM : float = 32.0           # L 角标臂长
const RIVET_SIZE : float = 3.0            # 铆点边长
const CONTENT_MARGIN : float = 26.0       # 内容左右边距
const TOP_DIVIDER_Y : float = 74.0        # 顶栏分隔线

## 详情面板的五种状态。后两种只在 UI 层派生，不写进节点数据
enum DetailState {
	UNLOCKED,     ## 已安装
	INSTALLABLE,  ## 可安装且钱够
	UNAFFORDABLE, ## 可安装但钱不够
	LOCKED,       ## 前置未安装
	PENDING,      ## 效果依赖的机制还没做
}

@export var tree_data : SkillTreeData

var _nodes : Dictionary = {}
var _selected_id : StringName = &""
var _fade_tween : Tween
var _blink_time : float = 0.0

## 状态栏一行会临时改成操作反馈（复位 / 余额不足），到点自动还原
const PROMPT_DEFAULT : String = "> 选择节点以查看改装详情"
const PROMPT_RESET_HINT : String = "> 选择节点以查看改装详情 · SHIFT+R 复位改装"
var _prompt_default : String = PROMPT_DEFAULT
var _prompt_until : int = 0

## 分支索引：head 节点（root 的直接子节点）顺序即分支顺序
class BranchRow:
	var head_id : StringName
	var head_title : String = ""
	var panel : PanelContainer
	var count_label : Label
	var normal_box : StyleBoxFlat
	var active_box : StyleBoxFlat

var _branch_rows : Array[BranchRow] = []

@onready var _tree_area : Control = %TreeArea
@onready var _status_label : Label = %StatusLabel
@onready var _name_label : Label = %NameLabel
@onready var _effect_label : Label = %EffectLabel
@onready var _desc_label : Label = %DescLabel
@onready var _parent_value : Label = %ParentValue
@onready var _branch_value : Label = %BranchValue
@onready var _action_button : Button = %ActionButton
@onready var _cost_chip : VBoxContainer = %CostChip
@onready var _cost_main : Label = %CostMain
@onready var _cost_sub : Label = %CostSub
@onready var _esc_button : Button = %EscButton
@onready var _branch_list : VBoxContainer = %BranchList
@onready var _balance_top : Label = %BalanceValue
@onready var _node_top : Label = %NodeValue
@onready var _cursor_rect : ColorRect = %CursorRect
@onready var _prompt_label : Label = $StatusBar/PromptLabel
@onready var _balance_value : Label = $DetailPanel/Content/Meta/BalanceRow/BalanceValue

func _ready() -> void:
	if tree_data == null:
		push_error("SkillTree: 未配置 tree_data")
		return
	if not tree_data.is_valid():
		push_error("SkillTree: root_id 在 nodes 里找不到")
		return

	_build_nodes()
	_build_branch_rows()
	_connect_ui()

	resized.connect(_layout_nodes)
	_tree_area.resized.connect(_layout_nodes)
	_layout_nodes()

	Game.coins_changed.connect(_on_coins_changed)
	_select(tree_data.root_id)

	# 复位快捷键只在 debug 构建里存在：正式包不给提示，也不响应按键
	_prompt_default = PROMPT_RESET_HINT if OS.is_debug_build() else PROMPT_DEFAULT
	_prompt_label.text = _prompt_default

func _process(delta : float) -> void:
	# 光标 █ 0.5 秒闪烁（GDD 4.10.6），steps 硬切不渐变
	_blink_time += delta
	if _cursor_rect != null:
		_cursor_rect.visible = fmod(_blink_time, 1.0) < 0.5

	# 操作反馈到点还原
	if _prompt_until > 0 and Time.get_ticks_msec() >= _prompt_until:
		_prompt_until = 0
		_prompt_label.text = _prompt_default
		_prompt_label.add_theme_color_override("font_color", COLOR_MUTED)

## 调试用：复位改装并把退款金额打到状态栏。
## 按键本身在 control.gd 的 _unhandled_input 里（终端在 SubViewport 内，收不到窗口级按键）
func debug_reset_skills() -> void:
	var refund := Game.reset_skills()
	_refresh_states()
	_set_prompt("已复位改装 · 退回 %s 金币" % _format_coins(refund), COLOR_AMBER, 2.5)

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
	# 金币可能在矿区里变了，每次打开都按最新状态重刷
	_refresh_states()

func close() -> void:
	visible = false
	modulate.a = 1.0
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()

## 当前选中的节点 id，外部 UI 可以用它做联动
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
		node.setup(node_data, _state_for(node_data.id), Game.is_skill_pending(node_data.id))
		node.pressed.connect(_on_node_pressed)
		_nodes[node_data.id] = node

func _connect_ui() -> void:
	_esc_button.pressed.connect(_on_close_pressed)
	_action_button.pressed.connect(_on_action_pressed)

func _state_for(node_id : StringName) -> SkillTreeNode.State:
	if Game.is_skill_unlocked(node_id):
		return SkillTreeNode.State.UNLOCKED
	if Game.is_skill_parent_unlocked(node_id):
		return SkillTreeNode.State.AVAILABLE
	return SkillTreeNode.State.LOCKED

## 解锁 / 扣费后统一重刷：节点三态 + 连线颜色 + 分支计数 + 当前详情 + 顶部统计
func _refresh_states() -> void:
	for node_id in _nodes:
		var node : SkillTreeNode = _nodes[node_id]
		node.set_state(_state_for(node_id))
	_refresh_branch_counts()
	_update_top_stats()
	if _selected_id != &"":
		_update_detail(_selected_id)
	queue_redraw()

func _layout_nodes() -> void:
	if _tree_area == null:
		return
	# 树包围盒 x∈[-414,324] 重心偏左上，整体右移下移做视觉配平（与布局稿一致）
	var center := _tree_area.size * 0.5 + Vector2(40.0, 12.0)
	for node_id in _nodes:
		var node : SkillTreeNode = _nodes[node_id]
		if node.data == null:
			continue
		node.position = center + node.data.position - node.size * 0.5
	queue_redraw()

# ---------------------------------------------------------------- 分支索引

func _branch_heads() -> Array[SkillNodeData]:
	var heads : Array[SkillNodeData] = []
	var root := tree_data.get_node_data(tree_data.root_id)
	if root == null:
		return heads
	for child_id in root.children:
		var head := tree_data.get_node_data(child_id)
		if head != null:
			heads.append(head)
	return heads

## 某分支子树的节点数（含分支头，不含 root）
func _branch_total(head_id : StringName) -> int:
	var total := 0
	var stack : Array[StringName] = [head_id]
	while not stack.is_empty():
		var id : StringName = stack.pop_back()
		total += 1
		var data := tree_data.get_node_data(id)
		if data != null:
			for child_id in data.children:
				stack.append(child_id)
	return total

## 某分支子树里已解锁的数量
func _branch_unlocked(head_id : StringName) -> int:
	var count := 0
	var stack : Array[StringName] = [head_id]
	while not stack.is_empty():
		var id : StringName = stack.pop_back()
		if Game.is_skill_unlocked(id):
			count += 1
		var data := tree_data.get_node_data(id)
		if data != null:
			for child_id in data.children:
				stack.append(child_id)
	return count

## 节点所属分支头（沿父链向上）。root 返回空 id
func _head_of(node_id : StringName) -> StringName:
	var current := node_id
	while true:
		var parent := tree_data.get_parent_of(current)
		if parent == null:
			return &""
		if parent.id == tree_data.root_id:
			return current
		current = parent.id
	return &""

func _branch_label(head_id : StringName) -> String:
	var index := _branch_index_of(head_id)
	return "%02d · %s" % [index + 1, tree_data.get_node_data(head_id).title]

func _branch_index_of(head_id : StringName) -> int:
	for i in _branch_rows.size():
		if _branch_rows[i].head_id == head_id:
			return i
	return -1

func _build_branch_rows() -> void:
	for child in _branch_list.get_children():
		child.queue_free()
	_branch_rows.clear()

	var rows : Array = []
	rows.append([&"", "00", "总览"])
	var index := 1
	for head in _branch_heads():
		rows.append([head.id, "%02d" % index, head.title])
		index += 1

	for row in rows:
		var head_id : StringName = row[0]
		var no_text : String = row[1]
		var title_text : String = row[2]

		var panel := PanelContainer.new()
		var normal := StyleBoxFlat.new()
		normal.bg_color = Color(0, 0, 0, 0)
		normal.content_margin_left = 13.0
		normal.content_margin_top = 9.0
		normal.content_margin_right = 10.0
		normal.content_margin_bottom = 9.0
		var active := normal.duplicate() as StyleBoxFlat
		active.bg_color = Color(COLOR_AMBER.r, COLOR_AMBER.g, COLOR_AMBER.b, 0.10)
		active.border_width_left = 3
		active.border_color = COLOR_AMBER
		panel.add_theme_stylebox_override("panel", normal)

		var hbox := HBoxContainer.new()
		hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(hbox)

		var name_label := Label.new()
		name_label.text = "%s %s" % [no_text, title_text]
		name_label.add_theme_font_size_override("font_size", 15)
		name_label.add_theme_color_override("font_color", COLOR_MUTED)
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(name_label)

		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(spacer)

		var count_label := Label.new()
		count_label.add_theme_font_size_override("font_size", 13)
		count_label.add_theme_color_override("font_color", COLOR_AMBER_DIM)
		count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(count_label)

		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		var branch_row := BranchRow.new()
		branch_row.head_id = head_id
		branch_row.head_title = title_text
		branch_row.panel = panel
		branch_row.count_label = count_label
		branch_row.normal_box = normal
		branch_row.active_box = active
		panel.gui_input.connect(_on_branch_row_input.bind(head_id))
		_branch_list.add_child(panel)
		_branch_rows.append(branch_row)

	_refresh_branch_counts()
	_refresh_branch_highlight()

func _refresh_branch_counts() -> void:
	if tree_data == null:
		return
	var total_all := tree_data.nodes.size()
	var unlocked_all := 0
	for node in tree_data.nodes:
		if node != null and Game.is_skill_unlocked(node.id):
			unlocked_all += 1
	for row in _branch_rows:
		if row.head_id == &"":
			row.count_label.text = "%d / %d" % [unlocked_all, total_all]
		else:
			row.count_label.text = "%d / %d" % [_branch_unlocked(row.head_id), _branch_total(row.head_id)]

func _refresh_branch_highlight() -> void:
	var selected_head := _head_of(_selected_id)
	for row in _branch_rows:
		var is_on : bool = (row.head_id == selected_head) \
			or (row.head_id == &"" and selected_head == &"" and _selected_id == tree_data.root_id)
		row.panel.add_theme_stylebox_override("panel", row.active_box if is_on else row.normal_box)
		var label : Label = row.panel.get_child(0).get_child(0)
		label.add_theme_color_override("font_color", COLOR_TEXT if is_on else COLOR_MUTED)

func _on_branch_row_input(event : InputEvent, head_id : StringName) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			var target := head_id if head_id != &"" else tree_data.root_id
			_select(target)

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
	_refresh_branch_highlight()
	skill_selected.emit(node_id)

func _update_detail(node_id : StringName) -> void:
	var data := tree_data.get_node_data(node_id)
	if data == null:
		return

	_name_label.text = data.title
	_effect_label.text = data.get_effect_text()
	_desc_label.text = data.description

	# 元信息四行
	var parent := tree_data.get_parent_of(node_id)
	_parent_value.text = parent.title if parent != null else "——"

	var cost := Game.get_skill_cost(node_id)
	var head_id := _head_of(node_id)
	_branch_value.text = "总览" if head_id == &"" else _branch_label(head_id)
	_balance_value.text = "%s" % _format_coins(Game.coins)

	match _detail_state_for(node_id):
		DetailState.UNLOCKED:
			_set_status("●  已安装", COLOR_AMBER)
			_set_action("已安装", false)
		DetailState.INSTALLABLE:
			_set_status("○  可安装", COLOR_AMBER)
			_set_action("安 装", true, cost, COLOR_TEXT)
		DetailState.UNAFFORDABLE:
			_set_status("·  余额不足", COLOR_UNAFFORD)
			# 差多少直接写在按钮上，省得玩家自己在两行数字之间做减法
			_set_action("余额不足", false, cost, COLOR_MUTED, cost - Game.coins)
		DetailState.PENDING:
			_set_status("!  系统未就绪", COLOR_AMBER_DIM)
			_set_action("系统未就绪", false)
		_:
			_set_status("·  未解锁", COLOR_MUTED)
			_set_action("不可用", false, cost, COLOR_MUTED)

## UI 派生的五态（GDD 4.10.4）。判定顺序：已装 → 前置 → 机制 → 钱
func _detail_state_for(node_id : StringName) -> DetailState:
	if Game.is_skill_unlocked(node_id):
		return DetailState.UNLOCKED
	if not Game.is_skill_parent_unlocked(node_id):
		return DetailState.LOCKED
	if Game.is_skill_pending(node_id):
		return DetailState.PENDING
	if Game.coins >= Game.get_skill_cost(node_id):
		return DetailState.INSTALLABLE
	return DetailState.UNAFFORDABLE

func _update_top_stats() -> void:
	_balance_top.text = _format_coins(Game.coins)
	_node_top.text = "%d / %d" % [Game.get_unlocked_count(), Game.get_skill_total()]

func _set_status(text : String, color : Color) -> void:
	_status_label.text = text
	_status_label.add_theme_color_override("font_color", color)

## 状态栏临时提示。hold 秒后自动回到默认提示
func _set_prompt(text : String, color : Color, hold : float) -> void:
	_prompt_label.text = text
	_prompt_label.add_theme_color_override("font_color", color)
	_prompt_until = Time.get_ticks_msec() + int(hold * 1000.0)

## 按钮正文 + 右侧费用。费用压在按钮上而不是元信息行里——这是玩家唯一要看的数
## deficit > 0 时在费用下补一行「还差 N」
func _set_action(text : String, enabled : bool, cost : int = -1, cost_color : Color = COLOR_TEXT, deficit : int = 0) -> void:
	_action_button.text = text
	_action_button.disabled = not enabled

	if cost < 0:
		_cost_chip.visible = false
		return
	_cost_chip.visible = true
	_cost_main.text = "%s 金币" % _format_coins(cost)
	_cost_main.add_theme_color_override("font_color", cost_color)
	_cost_sub.visible = deficit > 0
	if deficit > 0:
		_cost_sub.text = "还差 %s" % _format_coins(deficit)
		_cost_sub.add_theme_color_override("font_color", COLOR_AMBER)

## 千分位，与 HUD 的显示口径保持一致
func _format_coins(amount : int) -> String:
	var digits := str(absi(amount))
	var out := ""
	for i in range(digits.length()):
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += ","
		out += digits[i]
	return ("-" + out) if amount < 0 else out

func _on_coins_changed(_total : int, _delta : int) -> void:
	_update_top_stats()
	if _selected_id != &"":
		_update_detail(_selected_id)
	_refresh_branch_counts()

func _on_close_pressed() -> void:
	close_requested.emit()

## 唯一购买入口：校验与扣费都在 Game 里，这里只管刷新
func _on_action_pressed() -> void:
	if _selected_id == &"":
		return
	if not Game.unlock_skill(_selected_id):
		return
	_refresh_states()

# ---------------------------------------------------------------- 绘制

func _draw() -> void:
	_draw_backdrop()
	_draw_links()

## CRT 机框：屏外底色 → 屏内填充 → 双层描边 → L 角标 → 铆点 → 顶栏分隔线
func _draw_backdrop() -> void:
	var full := Rect2(Vector2.ZERO, size)
	draw_rect(full, COLOR_OUT)

	var case_rect := Rect2(Vector2.ONE * CASE_INSET, size - Vector2.ONE * CASE_INSET * 2.0)
	draw_rect(case_rect, COLOR_FILL)
	draw_rect(case_rect, COLOR_CASE, false, 3.0)

	var inner := Rect2(Vector2.ONE * (CASE_INSET + 7.0), size - Vector2.ONE * (CASE_INSET + 7.0) * 2.0)
	draw_rect(inner, COLOR_CASE_IN, false, 2.0)

	# 四角 L 形角标
	var inset := CASE_INSET + CORNER_INSET
	var arm := CORNER_ARM
	var w := size.x - inset * 2.0
	var h := size.y - inset * 2.0
	var corner := Color(COLOR_CASE, 1.0)
	var t := 2.0
	draw_line(Vector2(inset, inset), Vector2(inset + arm, inset), corner, t)
	draw_line(Vector2(inset, inset), Vector2(inset, inset + arm), corner, t)
	draw_line(Vector2(inset + w, inset), Vector2(inset + w - arm, inset), corner, t)
	draw_line(Vector2(inset + w, inset), Vector2(inset + w, inset + arm), corner, t)
	draw_line(Vector2(inset, inset + h), Vector2(inset + arm, inset + h), corner, t)
	draw_line(Vector2(inset, inset + h), Vector2(inset, inset + h - arm), corner, t)
	draw_line(Vector2(inset + w, inset + h), Vector2(inset + w - arm, inset + h), corner, t)
	draw_line(Vector2(inset + w, inset + h), Vector2(inset + w, inset + h - arm), corner, t)

	# 四角琥珀铆点
	draw_rect(Rect2(Vector2(CASE_INSET + 4.0, CASE_INSET + 4.0), Vector2.ONE * RIVET_SIZE), COLOR_AMBER)
	draw_rect(Rect2(Vector2(size.x - CASE_INSET - 4.0 - RIVET_SIZE, CASE_INSET + 4.0), Vector2.ONE * RIVET_SIZE), COLOR_AMBER)
	draw_rect(Rect2(Vector2(CASE_INSET + 4.0, size.y - CASE_INSET - 4.0 - RIVET_SIZE), Vector2.ONE * RIVET_SIZE), COLOR_AMBER)
	draw_rect(Rect2(Vector2(size.x - CASE_INSET - 4.0 - RIVET_SIZE, size.y - CASE_INSET - 4.0 - RIVET_SIZE), Vector2.ONE * RIVET_SIZE), COLOR_AMBER)

	# 顶栏底部分隔线
	draw_line(Vector2(CONTENT_MARGIN, TOP_DIVIDER_Y), Vector2(size.x - CONTENT_MARGIN, TOP_DIVIDER_Y), COLOR_CASE_IN, 2.0)

## 连线：三线叠画，硬边不抗锯齿。断电线路（前置未解锁）用暗琥珀
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
			var dim := child_node.state == SkillTreeNode.State.LOCKED
			var color := COLOR_AMBER_DEEP if dim else COLOR_AMBER
			var width_scale := 0.7 if dim else 1.0

			draw_line(from, to, Color(color, 0.10), 10.0 * width_scale, false)
			draw_line(from, to, Color(color, 0.24), 4.0 * width_scale, false)
			draw_line(from, to, Color(color, 0.85), 2.0 * width_scale, false)
