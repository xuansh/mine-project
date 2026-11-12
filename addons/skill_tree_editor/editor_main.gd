@tool
extends Control

## 技能树可视化编辑器（编辑器插件主界面）。
##
## 用法：
##   1. 编辑器顶部主屏标签里点「技能树」
##   2. 左侧选节点 → 右侧改 名称 / 前置 / 花费 / 可升级次数 / 效果 / 描述
##   3. 点「保存」写回 .tres（每次保存前自动留一份 .bak）
##
## 分支的口径：**分支 = 根节点的直系子节点**。所以"一个技能属于哪个分支"
## 由它的前置节点决定——前置选「根」就是分支头，选别的节点就挂在那条链后面。
## 分支名 = 分支头节点的名称（终端左侧「分支索引」显示的就是它）。
##
## 修改一律直接落在内存里的 SkillTreeData，保存才落盘。支持撤销（快照式）。

const DEFAULT_PATH := "res://Resources/SkillTree/basic_skill_tree.tres"
const PreviewScript := preload("res://addons/skill_tree_editor/tree_preview.gd")
const Catalog := preload("res://addons/skill_tree_editor/effect_catalog.gd")

## 撤销栈上限
const UNDO_LIMIT : int = 60
## 自动布局：第一层半径 / 每层递增 / 同级兄弟的角度散开
const LAYOUT_BASE : float = 178.0
const LAYOUT_STEP : float = 104.0
const LAYOUT_SPREAD : float = 0.42

# ---------------------------------------------------------------- 状态

var _tree : SkillTreeData
var _path : String = DEFAULT_PATH
var _selected : StringName = &""
var _dirty : bool = false
var _suspend : bool = false
var _undo : Array[Dictionary] = []
var _pending_empty_save : bool = false
## 程序化选中 TreeItem 会再发 item_selected，用它挡掉回环
var _syncing_tree : bool = false

# ---------------------------------------------------------------- 控件

var _path_edit : LineEdit
var _struct : Tree
var _stats : Label
var _checks : Label
var _status : Label
var _preview : Control
var _save_btn : Button
var _undo_btn : Button
var _delete_btn : Button
var _form : GridContainer
var _form_box : VBoxContainer
var _confirm : ConfirmationDialog

var _f_id : LineEdit
var _f_title : LineEdit
var _f_parent : OptionButton
var _f_branch : Label
var _f_cost : SpinBox
var _f_level : SpinBox
var _f_level_hint : Label
var _f_kind : OptionButton
var _f_key : LineEdit
var _f_value : SpinBox
var _f_effect : LineEdit
var _f_desc : TextEdit
var _f_note : TextEdit
var _f_shape : OptionButton

# ---------------------------------------------------------------- 生命周期

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_open(_path)

# ---------------------------------------------------------------- 界面搭建

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	_build_toolbar(root)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 300
	root.add_child(split)

	_build_left(split)
	_build_right(split)

	_status = Label.new()
	_status.text = "就绪"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)

	_confirm = ConfirmationDialog.new()
	_confirm.confirmed.connect(_on_confirm)
	add_child(_confirm)

func _build_toolbar(root : VBoxContainer) -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	root.add_child(bar)

	var l := Label.new()
	l.text = "资源"
	bar.add_child(l)

	_path_edit = LineEdit.new()
	_path_edit.text = _path
	_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_path_edit.custom_minimum_size = Vector2(240, 0)
	bar.add_child(_path_edit)

	var open_btn := Button.new()
	open_btn.text = "打开"
	open_btn.pressed.connect(func() -> void: _request_open())
	bar.add_child(open_btn)

	_save_btn = Button.new()
	_save_btn.text = "保存"
	_save_btn.tooltip_text = "写回 .tres，保存前自动留一份 .bak"
	_save_btn.pressed.connect(_save)
	bar.add_child(_save_btn)

	bar.add_child(VSeparator.new())

	var new_branch := Button.new()
	new_branch.text = "新建分支"
	new_branch.tooltip_text = "在根节点下新建一个分支头节点"
	new_branch.pressed.connect(_new_branch)
	bar.add_child(new_branch)

	var new_node := Button.new()
	new_node.text = "新建节点"
	new_node.tooltip_text = "在当前选中节点下面挂一个子节点"
	new_node.pressed.connect(_new_child)
	bar.add_child(new_node)

	_delete_btn = Button.new()
	_delete_btn.text = "删除"
	_delete_btn.tooltip_text = "删除选中节点及其所有子节点"
	_delete_btn.pressed.connect(_delete)
	bar.add_child(_delete_btn)

	bar.add_child(VSeparator.new())

	var relayout := Button.new()
	relayout.text = "自动布局"
	relayout.tooltip_text = "按分支方向重算所有节点坐标（会覆盖手工摆的位置）"
	relayout.pressed.connect(_auto_layout)
	bar.add_child(relayout)

	_undo_btn = Button.new()
	_undo_btn.text = "撤销"
	_undo_btn.disabled = true
	_undo_btn.pressed.connect(_undo_last)
	bar.add_child(_undo_btn)

func _build_left(split : HSplitContainer) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	split.add_child(box)

	var head := Label.new()
	head.text = "结构"
	box.add_child(head)

	_struct = Tree.new()
	_struct.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_struct.custom_minimum_size = Vector2(260, 220)
	_struct.hide_root = true
	_struct.allow_reselect = true
	_struct.item_selected.connect(_on_tree_selected)
	box.add_child(_struct)

	_stats = Label.new()
	_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_stats)

	_checks = Label.new()
	_checks.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_checks.custom_minimum_size = Vector2(0, 60)
	box.add_child(_checks)

func _build_right(split : HSplitContainer) -> void:
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	split.add_child(right)

	_preview = PreviewScript.new()
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.custom_minimum_size = Vector2(0, 200)
	_preview.connect("node_clicked", func(id : StringName) -> void: _select(id))
	right.add_child(_preview)

	_form_box = VBoxContainer.new()
	_form_box.add_theme_constant_override("separation", 4)
	right.add_child(_form_box)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 260)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_form_box.add_child(scroll)

	_form = GridContainer.new()
	_form.columns = 2
	_form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_form.add_theme_constant_override("h_separation", 10)
	_form.add_theme_constant_override("v_separation", 6)
	scroll.add_child(_form)

	_build_form()

func _build_form() -> void:
	_f_id = LineEdit.new()
	_f_id.tooltip_text = "节点 ID，存档按它记录。改名会让旧存档里的这个节点失效"
	_f_id.text_submitted.connect(func(_t : String) -> void: _apply_id())
	_f_id.focus_exited.connect(_apply_id)
	_add_row("ID", _f_id)

	_f_title = LineEdit.new()
	_f_title.text_changed.connect(func(t : String) -> void: _apply_field("title", t))
	_f_title.focus_entered.connect(_push_undo)
	_add_row("名称", _f_title)

	_f_branch = Label.new()
	_f_branch.modulate = Color(0.72, 0.72, 0.72)
	_add_row("所属分支", _f_branch)

	_f_parent = OptionButton.new()
	_f_parent.item_selected.connect(_on_parent_picked)
	_add_row("前置节点", _f_parent)

	_f_cost = SpinBox.new()
	_f_cost.min_value = 0
	_f_cost.max_value = 999999
	_f_cost.step = 10
	_f_cost.suffix = " 金币"
	_f_cost.value_changed.connect(func(v : float) -> void: _apply_field("cost", int(v)))
	_add_row("解锁花费", _f_cost)

	var level_row := HBoxContainer.new()
	_f_level = SpinBox.new()
	_f_level.min_value = 1
	_f_level.max_value = 20
	_f_level.step = 1
	_f_level.value_changed.connect(func(v : float) -> void: _apply_field("max_level", int(v)))
	level_row.add_child(_f_level)
	_f_level_hint = Label.new()
	_f_level_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	level_row.add_child(_f_level_hint)
	_add_row("可升级次数", level_row)

	_f_kind = OptionButton.new()
	for item in Catalog.all():
		_f_kind.add_item(String(item["label"]))
	_f_kind.add_item("自定义效果键…")
	_f_kind.item_selected.connect(_on_kind_picked)
	_add_row("效果类型", _f_kind)

	_f_key = LineEdit.new()
	_f_key.placeholder_text = "自定义 effect_key，例如 dig_speed"
	_f_key.text_submitted.connect(func(_t : String) -> void: _apply_key())
	_f_key.focus_exited.connect(_apply_key)
	_add_row("效果键", _f_key)

	var value_row := HBoxContainer.new()
	_f_value = SpinBox.new()
	_f_value.min_value = -9999
	_f_value.max_value = 9999
	_f_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_f_value.value_changed.connect(_on_value_changed)
	value_row.add_child(_f_value)
	_add_row("效果数值", value_row)

	_f_effect = LineEdit.new()
	_f_effect.placeholder_text = "留空则按效果类型自动生成"
	_f_effect.text_changed.connect(func(t : String) -> void: _apply_field("effect_text", t))
	_f_effect.focus_entered.connect(_push_undo)
	_add_row("效果说明", _f_effect)

	_f_desc = TextEdit.new()
	_f_desc.custom_minimum_size = Vector2(0, 78)
	_f_desc.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_f_desc.text_changed.connect(func() -> void: _apply_field("description", _f_desc.text))
	_f_desc.focus_entered.connect(_push_undo)
	_add_row("描述", _f_desc)

	_f_note = TextEdit.new()
	_f_note.custom_minimum_size = Vector2(0, 58)
	_f_note.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_f_note.placeholder_text = "写给程序看的实现说明，游戏里不显示"
	_f_note.text_changed.connect(func() -> void: _apply_field("implement_note", _f_note.text))
	_f_note.focus_entered.connect(_push_undo)
	_add_row("实现备注", _f_note)

	_f_shape = OptionButton.new()
	_f_shape.add_item("方形")
	_f_shape.add_item("六边形")
	_f_shape.item_selected.connect(_on_shape_picked)
	_add_row("节点形状", _f_shape)

func _add_row(label_text : String, control : Control) -> void:
	var l := Label.new()
	l.text = label_text
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.custom_minimum_size = Vector2(84, 0)
	_form.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_form.add_child(control)

# ---------------------------------------------------------------- 读写资源

func _request_open() -> void:
	if _dirty:
		_ask("有未保存的修改，确定丢弃并重新打开？", func() -> void: _open(_path_edit.text))
		return
	_open(_path_edit.text)

func _open(path : String) -> void:
	path = path.strip_edges()
	if path.is_empty():
		path = DEFAULT_PATH
	var res := ResourceLoader.load(path)
	if res == null:
		_set_status("打不开：%s" % path, true)
		return
	if not (res is SkillTreeData):
		_set_status("不是技能树资源：%s" % path, true)
		return

	_tree = res
	_path = path
	_path_edit.text = path
	_dirty = false
	_undo.clear()
	_update_undo_btn()
	_preview.call("set_tree", _tree)
	_rebuild_structure()

	if _tree.get_node_data(_tree.root_id) != null:
		_select(_tree.root_id)
	else:
		_selected = &""
		_rebuild_structure()
		_clear_form()
	_set_status("已载入 %s（%d 个节点）" % [path.get_file(), _tree.nodes.size()])

func _save() -> void:
	if _tree == null:
		return
	# 空树保护：.tres 被整体清空是最容易发生的灾难，必须二次确认
	if _tree.nodes.is_empty() and not _pending_empty_save:
		_pending_empty_save = true
		_ask("这棵树目前一个节点都没有。确定要保存成空树吗？", _save)
		return
	_pending_empty_save = false

	_backup()

	var err := ResourceSaver.save(_tree, _path)
	if err != OK:
		_set_status("保存失败，错误码 %d：%s" % [err, _path], true)
		return

	_clear_dirty()
	EditorInterface.get_resource_filesystem().update_file(_path)
	_set_status("已保存 %s（%d 个节点，已留 .bak 备份）" % [_path.get_file(), _tree.nodes.size()])

## 保存前留一份备份，防止误操作把整棵树冲掉
func _backup() -> void:
	var abs_path := ProjectSettings.globalize_path(_path)
	if not FileAccess.file_exists(_path):
		return
	var bak := abs_path + ".bak"
	var dir := DirAccess.open(abs_path.get_base_dir())
	if dir != null:
		dir.copy(abs_path, bak)

func _mark_dirty() -> void:
	_dirty = true
	_save_btn.text = "保存 *"
	_undo_btn.disabled = _undo.is_empty()

func _clear_dirty() -> void:
	_dirty = false
	_save_btn.text = "保存"

func _update_undo_btn() -> void:
	_undo_btn.disabled = _undo.is_empty()

# ---------------------------------------------------------------- 结构树

func _rebuild_structure() -> void:
	_struct.clear()
	if _tree == null:
		return

	var hidden := _struct.create_item()
	var root_item := _make_item(hidden, _tree.root_id, true)
	var seen : Dictionary[StringName, bool] = {}
	seen[_tree.root_id] = true
	_append_children(root_item, _tree.root_id, seen)

	# 游离节点（没挂在根下面）单独列出来，否则会"看不见但存在"
	var orphans : Array[SkillNodeData] = []
	for node in _tree.nodes:
		if node != null and not seen.has(node.id):
			orphans.append(node)
	if not orphans.is_empty():
		var orphan_root := _struct.create_item(hidden)
		orphan_root.set_text(0, "⚠ 游离节点（未连到根）")
		orphan_root.set_selectable(0, false)
		for node in orphans:
			var item := _make_item(orphan_root, node.id, false)
			item.set_custom_color(0, Color(1.0, 0.62, 0.35))

	_refresh_stats()
	_refresh_checks()
	_highlight_in_tree()

func _make_item(parent : TreeItem, id : StringName, is_head : bool) -> TreeItem:
	var node := _tree.get_node_data(id)
	var text : String = id if node == null else node.title
	if node != null:
		if id == _tree.root_id:
			text = "%s    [根]" % node.title
		elif is_head:
			text = "%s    [分支]" % node.title
		else:
			text = node.title
		if node.max_level > 1:
			text += "   1/%d" % node.max_level
		text += "    · %d 金" % node.cost
	elif parent == null:
		text = "（找不到 %s）" % id

	var item := _struct.create_item(parent)
	item.set_text(0, text)
	item.set_metadata(0, id)
	if node != null and node.effect_key == &"":
		item.set_custom_color(0, Color(0.95, 0.75, 0.35))
	return item

func _append_children(parent_item : TreeItem, id : StringName, seen : Dictionary[StringName, bool]) -> void:
	var node := _tree.get_node_data(id)
	if node == null:
		return
	for child_id in node.children:
		if seen.has(child_id):
			continue
		seen[child_id] = true
		var child_is_head := id == _tree.root_id
		var item := _make_item(parent_item, child_id, child_is_head)
		_append_children(item, child_id, seen)

func _highlight_in_tree() -> void:
	if _selected == &"":
		return
	var item := _find_item(_struct.get_root(), _selected)
	if item == null:
		return
	_syncing_tree = true
	item.select(0)
	_syncing_tree = false

func _find_item(item : TreeItem, id : StringName) -> TreeItem:
	if item == null:
		return null
	if item.get_metadata(0) == id:
		return item
	for child in item.get_children():
		var found := _find_item(child, id)
		if found != null:
			return found
	return null

func _on_tree_selected() -> void:
	if _syncing_tree:
		return
	var item := _struct.get_selected()
	if item == null:
		return
	var id = item.get_metadata(0)
	if id != null:
		_select(StringName(id))

# ---------------------------------------------------------------- 选中与表单

func _select(id : StringName) -> void:
	if _tree == null or _tree.get_node_data(id) == null:
		return
	_selected = id
	_preview.call("set_highlight", id)
	_highlight_in_tree()
	_fill_form(id)

func _fill_form(id : StringName) -> void:
	var node := _tree.get_node_data(id)
	if node == null:
		_clear_form()
		return

	_suspend = true

	_f_id.text = String(node.id)
	_f_title.text = node.title
	_f_branch.text = _branch_label_of(node.id)
	_f_cost.value = node.cost
	_f_level.value = node.max_level
	_f_key.text = String(node.effect_key)
	_f_effect.text = node.effect_text
	_f_desc.text = node.description
	_f_note.text = node.implement_note
	_f_shape.selected = int(node.shape)

	_rebuild_parent_options(node.id)
	_apply_kind_to_spin(node.effect_key, node.effect_value)

	_f_level_hint.text = _level_hint(node)
	_f_level_hint.add_theme_color_override("font_color",
		Color(1.0, 0.78, 0.35) if node.max_level > 1 else Color(0.68, 0.68, 0.68))

	_delete_btn.disabled = node.id == _tree.root_id
	_suspend = false

func _clear_form() -> void:
	_suspend = true
	_f_id.text = ""
	_f_title.text = ""
	_f_branch.text = "—"
	_f_cost.value = 0
	_f_level.value = 1
	_f_key.text = ""
	_f_effect.text = ""
	_f_desc.text = ""
	_f_note.text = ""
	_f_level_hint.text = ""
	_f_parent.clear()
	_suspend = false

func _level_hint(node : SkillNodeData) -> String:
	if node.max_level <= 1:
		return "0 / 1"
	return "0 / %d　⚠ 多级升级运行时还没接" % node.max_level

## 父节点下拉：把所有候选节点按「分支 / 节点」标签列出来
func _rebuild_parent_options(id : StringName) -> void:
	_f_parent.clear()
	_f_parent.add_item("—（根节点，无前置）")
	_f_parent.set_item_metadata(0, &"")

	if id == _tree.root_id:
		_f_parent.disabled = true
		_f_parent.select(0)
		return
	_f_parent.disabled = false

	var current_parent := _tree.get_parent_of(id)
	var index := 1
	var picked := 0
	for node in _tree.nodes:
		if node == null or node.id == id:
			continue
		# 不能挂到自己的子树里，会成环
		if _in_subtree(node.id, id):
			continue
		var branch := _branch_label_of(node.id)
		_f_parent.add_item("%s ｜ %s" % [branch, node.title])
		_f_parent.set_item_metadata(index, node.id)
		if current_parent != null and current_parent.id == node.id:
			picked = index
		index += 1

	_f_parent.select(picked)

## 节点所属分支的显示名（00 总览 / 02 · 涡轮引擎 这种）
func _branch_label_of(id : StringName) -> String:
	if _tree == null:
		return "—"
	var heads := _branch_heads()
	for i in heads.size():
		if _in_subtree(id, heads[i].id):
			return "%02d · %s" % [i + 1, heads[i].title]
	return "根 · 无分支"

func _branch_heads() -> Array[SkillNodeData]:
	var out : Array[SkillNodeData] = []
	if _tree == null:
		return out
	var root := _tree.get_node_data(_tree.root_id)
	if root == null:
		return out
	for child_id in root.children:
		var node := _tree.get_node_data(child_id)
		if node != null:
			out.append(node)
	return out

func _in_subtree(candidate : StringName, root_id : StringName) -> bool:
	if candidate == root_id:
		return true
	var node := _tree.get_node_data(root_id)
	if node == null:
		return false
	for child_id in node.children:
		if _in_subtree(candidate, child_id):
			return true
	return false

# ---------------------------------------------------------------- 表单 → 数据

func _apply_field(field : String, value : Variant) -> void:
	if _suspend or _tree == null or _selected == &"":
		return
	var node := _tree.get_node_data(_selected)
	if node == null:
		return
	node.set(field, value)
	_mark_dirty()
	_refresh_row_text()
	_refresh_checks()
	_preview.queue_redraw()

func _apply_id() -> void:
	if _suspend or _tree == null or _selected == &"":
		return
	var node := _tree.get_node_data(_selected)
	if node == null or node.id == _tree.root_id:
		_f_id.text = String(node.id) if node != null else ""
		return

	var new_id := StringName(_f_id.text.strip_edges().replace(" ", "_"))
	if String(new_id).is_empty() or new_id == node.id:
		_f_id.text = String(node.id)
		return
	if _tree.get_node_data(new_id) != null:
		_set_status("ID「%s」已存在，换一个" % new_id, true)
		_f_id.text = String(node.id)
		return

	_push_undo()
	var old_id := node.id
	# children 里的引用、父节点的 children、选中态都要跟着改
	for other in _tree.nodes:
		if other == null:
			continue
		var idx := other.children.find(old_id)
		if idx >= 0:
			other.children[idx] = new_id
	node.id = new_id
	if _tree.root_id == old_id:
		_tree.root_id = new_id
	_selected = new_id
	_mark_dirty()
	_rebuild_structure()
	_fill_form(new_id)
	_set_status("ID 已改为 %s（旧存档里这个节点会失效）" % new_id, true)

func _apply_key() -> void:
	if _suspend or _tree == null or _selected == &"":
		return
	var node := _tree.get_node_data(_selected)
	if node == null:
		return
	var new_key := StringName(_f_key.text.strip_edges())
	if new_key == node.effect_key:
		return
	node.effect_key = new_key
	_mark_dirty()
	_suspend = true
	_sync_kind_from_key(new_key)
	_apply_kind_to_spin(new_key, node.effect_value)
	_suspend = false
	_refresh_row_text()
	_refresh_checks()
	_preview.queue_redraw()

func _on_parent_picked(index : int) -> void:
	if _suspend or _tree == null or _selected == &"":
		return
	var target = _f_parent.get_item_metadata(index)
	if target == null:
		return
	_reparent(_selected, StringName(target))

func _on_kind_picked(index : int) -> void:
	if _suspend or _tree == null or _selected == &"":
		return
	var node := _tree.get_node_data(_selected)
	if node == null:
		return

	var items := Catalog.all()
	var is_custom := index >= items.size()
	_f_key.editable = is_custom

	_push_undo()
	if is_custom:
		_f_key.grab_focus()
		return

	var item : Dictionary = items[index]
	node.effect_key = item["key"]
	node.effect_value = 0.15 if String(item["kind"]) == "pct" else (1.0 if String(item["kind"]) == "flat" else 1.0)
	_suspend = true
	_f_key.text = String(node.effect_key)
	_apply_kind_to_spin(node.effect_key, node.effect_value)
	_suspend = false
	_mark_dirty()
	_refresh_row_text()
	_refresh_checks()
	_preview.queue_redraw()

func _on_value_changed(value : float) -> void:
	if _suspend or _tree == null or _selected == &"":
		return
	var node := _tree.get_node_data(_selected)
	if node == null:
		return
	var kind := _kind_of(node.effect_key)
	if kind == "flag":
		return
	node.effect_value = value / 100.0 if kind == "pct" else value
	_mark_dirty()
	_refresh_row_text()
	_preview.queue_redraw()

func _on_shape_picked(index : int) -> void:
	_apply_field("shape", index)

## 把节点的键与值映射到「效果类型 / 效果键 / 效果数值」三个控件
func _apply_kind_to_spin(key : StringName, value : float) -> void:
	var kind := _kind_of(key)
	if kind == "pct":
		_f_value.suffix = " %"
		_f_value.step = 1
		_f_value.editable = true
		_f_value.value = value * 100.0
	elif kind == "flat":
		_f_value.suffix = " 点"
		_f_value.step = 1
		_f_value.editable = true
		_f_value.value = value
	else:
		_f_value.suffix = ""
		_f_value.step = 0.01
		_f_value.editable = false
		_f_value.value = value
	_sync_kind_from_key(key)

func _sync_kind_from_key(key : StringName) -> void:
	var items := Catalog.all()
	for i in items.size():
		if items[i]["key"] == key:
			_f_kind.select(i)
			_f_key.editable = false
			return
	_f_kind.select(items.size())
	_f_key.editable = true

func _kind_of(key : StringName) -> String:
	var item := Catalog.find(key)
	if item.is_empty():
		return "pct"
	return String(item["kind"])

func _refresh_row_text() -> void:
	if _tree == null or _selected == &"":
		return
	var item := _find_item(_struct.get_root(), _selected)
	if item == null:
		return
	var node := _tree.get_node_data(_selected)
	if node == null:
		return
	var is_head := _tree.get_parent_of(node.id) != null \
		and _tree.get_parent_of(node.id).id == _tree.root_id
	var text : String = node.title
	if node.id == _tree.root_id:
		text = "%s    [根]" % node.title
	elif is_head:
		text = "%s    [分支]" % node.title
	if node.max_level > 1:
		text += "   1/%d" % node.max_level
	text += "    · %d 金" % node.cost
	item.set_text(0, text)
	_f_branch.text = _branch_label_of(node.id)
	_f_level_hint.text = _level_hint(node)
	_suspend = true
	_f_cost.value = node.cost
	_suspend = false

# ---------------------------------------------------------------- 结构操作

func _new_branch() -> void:
	if _tree == null:
		return
	_push_undo()
	var id := _unique_id("branch")
	var node := _make_node(id, "新分支")
	_tree.nodes.append(node)
	var root := _tree.get_node_data(_tree.root_id)
	if root == null:
		_set_status("根节点不存在，先把根节点建出来", true)
		_undo.pop_back()
		return
	root.children.append(id)
	_after_structure_change(id)
	_set_status("已新建分支「%s」，改个名字再挂技能" % node.title)

func _new_child() -> void:
	if _tree == null:
		return
	if _selected == &"":
		_new_branch()
		return
	_push_undo()
	var id := _unique_id("skill")
	var node := _make_node(id, "新技能")
	_tree.nodes.append(node)
	var parent := _tree.get_node_data(_selected)
	parent.children.append(id)
	_auto_position(id)
	_after_structure_change(id)
	_set_status("已在「%s」下新建节点" % parent.title)

func _delete() -> void:
	if _tree == null or _selected == &"" or _selected == _tree.root_id:
		return
	var victims := _collect_subtree(_selected)
	var node := _tree.get_node_data(_selected)
	_ask("删除「%s」及其 %d 个子节点？" % [node.title if node != null else _selected, victims.size() - 1],
		func() -> void: _do_delete(victims))

func _do_delete(victims : Array[StringName]) -> void:
	_push_undo()
	for other in _tree.nodes:
		if other == null:
			continue
		for id in victims:
			other.children.erase(id)
	for i in range(_tree.nodes.size() - 1, -1, -1):
		var node := _tree.nodes[i]
		if node != null and victims.has(node.id):
			_tree.nodes.remove_at(i)

	var fallback := _tree.root_id
	_selected = fallback
	_mark_dirty()
	_rebuild_structure()
	_select(fallback)
	_preview.queue_redraw()
	_set_status("已删除 %d 个节点" % victims.size())

func _collect_subtree(root_id : StringName) -> Array[StringName]:
	var out : Array[StringName] = []
	var stack : Array[StringName] = [root_id]
	while not stack.is_empty():
		var id : StringName = stack.pop_back()
		if out.has(id):
			continue
		out.append(id)
		var node := _tree.get_node_data(id)
		if node != null:
			for child_id in node.children:
				stack.append(child_id)
	return out

func _reparent(node_id : StringName, new_parent_id : StringName) -> void:
	if _tree == null or node_id == _tree.root_id:
		return
	if new_parent_id == &"":
		return
	if node_id == new_parent_id or _in_subtree(new_parent_id, node_id):
		_set_status("不能挂到自己的子树里（会成环）", true)
		_fill_form(node_id)
		return
	var new_parent := _tree.get_node_data(new_parent_id)
	if new_parent == null:
		return

	_push_undo()
	var old_parent := _tree.get_parent_of(node_id)
	if old_parent != null and old_parent.id != new_parent_id:
		old_parent.children.erase(node_id)
	if not new_parent.children.has(node_id):
		new_parent.children.append(node_id)

	_mark_dirty()
	_rebuild_structure()
	_select(node_id)
	_preview.queue_redraw()
	_set_status("「%s」现在挂在「%s」后面（分支：%s）" % [
		_tree.get_node_data(node_id).title, new_parent.title, _branch_label_of(node_id)])

# ---------------------------------------------------------------- 自动布局

func _auto_layout() -> void:
	if _tree == null:
		return
	_push_undo()
	var heads := _branch_heads()
	var root := _tree.get_node_data(_tree.root_id)
	if root != null:
		root.position = Vector2.ZERO

	for i in heads.size():
		var angle := _branch_angle(i, heads.size())
		var dir := Vector2(cos(angle), sin(angle))
		_layout_branch(heads[i].id, dir, 1.0)

	_mark_dirty()
	_rebuild_structure()
	_select(_selected if _selected != &"" else _tree.root_id)
	_preview.queue_redraw()
	_set_status("已重排 %d 个分支的坐标" % heads.size())

## 四个分支默认朝四个斜角，多于四个就绕着均分
func _branch_angle(index : int, total : int) -> float:
	const BASE := [-PI * 0.75, PI * 0.75, -PI * 0.25, PI * 0.25]
	if total <= BASE.size() and index < BASE.size():
		return BASE[index]
	return TAU * float(index) / float(maxi(total, 1))

func _layout_branch(id : StringName, dir : Vector2, depth : float) -> void:
	var node := _tree.get_node_data(id)
	if node == null:
		return
	node.position = dir * (LAYOUT_BASE + (depth - 1.0) * LAYOUT_STEP)

	var kids : Array[SkillNodeData] = []
	for child_id in node.children:
		var child := _tree.get_node_data(child_id)
		if child != null:
			kids.append(child)
	if kids.is_empty():
		return

	var count := kids.size()
	for i in count:
		var t := 0.0
		if count > 1:
			t = float(i) / float(count - 1) - 0.5
		var child_dir := dir.rotated(t * LAYOUT_SPREAD * 2.0)
		_layout_branch(kids[i].id, child_dir, depth + 1.0)

## 新节点先摆到父节点外侧，避免所有新节点叠在原点
func _auto_position(id : StringName) -> void:
	var node := _tree.get_node_data(id)
	var parent := _tree.get_parent_of(id)
	if node == null or parent == null:
		return
	var dir := parent.position.normalized()
	if dir == Vector2.ZERO:
		dir = Vector2(-1, -1).normalized()
	node.position = parent.position + dir * 96.0

# ---------------------------------------------------------------- 撤销

func _push_undo() -> void:
	if _tree == null:
		return
	_undo.append(_snapshot())
	if _undo.size() > UNDO_LIMIT:
		_undo.pop_front()
	_undo_btn.disabled = _undo.is_empty()

func _undo_last() -> void:
	if _undo.is_empty() or _tree == null:
		return
	var snap : Dictionary = _undo.pop_back()
	_restore(snap)
	_mark_dirty()
	_rebuild_structure()
	if _tree.get_node_data(_selected) == null:
		_selected = _tree.root_id
	_select(_selected)
	_preview.call("set_tree", _tree)
	_preview.queue_redraw()
	_undo_btn.disabled = _undo.is_empty()
	_set_status("已撤销一步")

func _snapshot() -> Dictionary:
	var arr : Array = []
	for node in _tree.nodes:
		if node == null:
			continue
		var kids : Array = []
		for c in node.children:
			kids.append(String(c))
		arr.append({
			"id": String(node.id),
			"title": node.title,
			"description": node.description,
			"effect_key": String(node.effect_key),
			"effect_value": node.effect_value,
			"effect_text": node.effect_text,
			"implement_note": node.implement_note,
			"cost": node.cost,
			"max_level": node.max_level,
			"shape": int(node.shape),
			"position": node.position,
			"children": kids,
		})
	return { "root": String(_tree.root_id), "nodes": arr }

func _restore(snap : Dictionary) -> void:
	var rebuilt : Array[SkillNodeData] = []
	for entry in snap["nodes"]:
		var node := SkillNodeData.new()
		node.id = StringName(entry["id"])
		node.title = entry["title"]
		node.description = entry["description"]
		node.effect_key = StringName(entry["effect_key"])
		node.effect_value = entry["effect_value"]
		node.effect_text = entry["effect_text"]
		node.implement_note = entry["implement_note"]
		node.cost = entry["cost"]
		node.max_level = entry["max_level"]
		node.shape = entry["shape"]
		node.position = entry["position"]
		var kids : Array[StringName] = []
		for c in entry["children"]:
			kids.append(StringName(c))
		node.children = kids
		rebuilt.append(node)
	_tree.nodes = rebuilt
	_tree.root_id = StringName(snap["root"])

# ---------------------------------------------------------------- 校验与统计

func _refresh_stats() -> void:
	if _tree == null:
		_stats.text = "未载入"
		return
	var heads := _branch_heads()
	_stats.text = "节点 %d　分支 %d" % [_tree.nodes.size(), heads.size()]

func _refresh_checks() -> void:
	if _tree == null:
		_checks.text = ""
		return
	var issues := _validate()
	if issues.is_empty():
		_checks.text = "✓ 校验通过"
		_checks.add_theme_color_override("font_color", Color(0.55, 0.85, 0.55))
		return
	var text := "⚠ %d 个问题：\n" % issues.size()
	for i in mini(issues.size(), 6):
		text += "· %s\n" % issues[i]
	if issues.size() > 6:
		text += "…（还有 %d 条）" % (issues.size() - 6)
	_checks.text = text
	_checks.add_theme_color_override("font_color", Color(1.0, 0.72, 0.4))

func _validate() -> Array[String]:
	var issues : Array[String] = []
	if _tree == null:
		return issues
	if _tree.get_node_data(_tree.root_id) == null:
		issues.append("根节点 %s 不存在" % _tree.root_id)
	if _tree.nodes.is_empty():
		issues.append("一个节点都没有")
		return issues

	var seen : Dictionary[StringName, bool] = {}
	for node in _tree.nodes:
		if node == null:
			continue
		if seen.has(node.id):
			issues.append("ID 重复：%s" % node.id)
		seen[node.id] = true
		if node.title.strip_edges().is_empty():
			issues.append("%s：名称为空" % node.id)
		if node.effect_key == &"":
			issues.append("%s：没选效果类型" % node.title)
		if node.cost <= 0 and node.id != _tree.root_id:
			issues.append("%s：花费为 0（免费节点）" % node.title)
		if node.max_level > 1:
			issues.append("%s：可升级 %d 次，多级运行时尚未接入" % [node.title, node.max_level])
		for child_id in node.children:
			if _tree.get_node_data(child_id) == null:
				issues.append("%s：子节点 %s 不存在" % [node.title, child_id])

	# 可达性
	var reach : Dictionary[StringName, bool] = {}
	var stack : Array[StringName] = [_tree.root_id]
	while not stack.is_empty():
		var id : StringName = stack.pop_back()
		if reach.has(id):
			continue
		reach[id] = true
		var node := _tree.get_node_data(id)
		if node != null:
			for c in node.children:
				stack.append(c)
	for node in _tree.nodes:
		if node != null and not reach.has(node.id):
			issues.append("%s：从根节点走不到" % node.title)

	return issues

# ---------------------------------------------------------------- 工具

func _make_node(id : StringName, title : String) -> SkillNodeData:
	var node := SkillNodeData.new()
	node.id = id
	node.title = title
	node.description = ""
	node.effect_key = &""
	node.effect_value = 0.0
	node.cost = 0
	node.max_level = 1
	node.shape = SkillNodeData.Shape.SQUARE
	node.position = Vector2.ZERO
	return node

func _unique_id(prefix : String) -> StringName:
	var i := 1
	while true:
		var candidate := StringName("%s_%d" % [prefix, i])
		if _tree.get_node_data(candidate) == null:
			return candidate
		i += 1
	return StringName("%s_%d" % [prefix, i])

func _after_structure_change(id : StringName) -> void:
	_mark_dirty()
	_rebuild_structure()
	_select(id)
	_preview.call("set_tree", _tree)
	_preview.queue_redraw()

func _set_status(text : String, warn : bool = false) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color",
		Color(1.0, 0.66, 0.4) if warn else Color(0.62, 0.86, 0.62))

# ---------------------------------------------------------------- 对话框

var _confirm_action : Callable

func _ask(text : String, action : Callable) -> void:
	_confirm.dialog_text = text
	_confirm_action = action
	_confirm.popup_centered(Vector2i(420, 140))

func _on_confirm() -> void:
	if _confirm_action.is_valid():
		_confirm_action.call()
	_confirm_action = Callable()
