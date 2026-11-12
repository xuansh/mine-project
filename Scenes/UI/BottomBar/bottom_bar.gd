class_name BottomBar
extends PanelContainer

## 底栏（GDD 4.8.1 / 4.11）：窗口级「持有物」栏，1547 × 278。
##
## 只负责展示槽位与转发点击，不认识任何业务——
## 显示什么由当前主舞台子场景决定（矿场 = 拥有的挖掘机，
## 以后的 NPC 任务场景 = 库存物品），control.gd 负责绑定与刷新。
##
## 槽位两态：READY「在库」（可点击选中）/ ACTIVE「出勤中」（暗态）。

signal slot_activated(index : int)

const SLOT_MIN_SIZE := Vector2(150, 150)

# 像素 HUD 色板（GDD 4.8）：近黑紫底 + 灰紫描边 + 唯一强调色工程黄
const COLOR_TEXT := Color(0.941176, 0.933333, 0.894118)
const COLOR_DIM := Color(0.627451, 0.596078, 0.709804)
const COLOR_ACCENT := Color(0.85098, 0.635294, 0.152941)
const COLOR_ACCENT_DIM := Color(0.431373, 0.352941, 0.117647)
const COLOR_BG := Color(0.070588, 0.062745, 0.101961)
const COLOR_BG_HOVER := Color(0.121569, 0.105882, 0.172549)
const COLOR_BORDER := Color(0.317647, 0.290196, 0.4)
const COLOR_BORDER_HOVER := Color(0.431373, 0.407843, 0.517647)

@export var font : Font
## 槽位图标（挖掘机像素图，AtlasTexture 已裁掉水印）
@export var slot_icon : Texture2D

var _slots : Array[InventorySlot] = []
var _selected : int = -1

@onready var _context_label : Label = %ContextLabel
@onready var _stats_label : Label = %StatsLabel
@onready var _slot_row : HBoxContainer = %SlotRow
@onready var _hint_label : Label = %HintLabel

func _ready() -> void:
	_apply_font(self)

# ---------------------------------------------------------------- 对外

## 整栏刷新。context = 场景标签，hint = 提示行，slots = 槽位列表
func show_inventory(context : String, hint : String, slots : Array[InventorySlot]) -> void:
	_context_label.text = context
	_hint_label.text = hint
	_slots = slots
	if _selected >= slots.size():
		_selected = -1
	_rebuild_slots()

## 高亮某个槽位（-1 = 无选中）
func set_selected(index : int) -> void:
	if index == _selected:
		return
	_selected = index
	_rebuild_slots()

## 只改提示行（选中 / 回收等即时反馈），不重建槽位
func set_hint(text : String) -> void:
	_hint_label.text = text

# ---------------------------------------------------------------- 槽位构建

func _rebuild_slots() -> void:
	for child in _slot_row.get_children():
		child.queue_free()
	for i in _slots.size():
		_slot_row.add_child(_build_slot(i, _slots[i]))
	_refresh_stats()

func _build_slot(index : int, slot : InventorySlot) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = SLOT_MIN_SIZE
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", _slot_style(slot, index == _selected, false))
	panel.gui_input.connect(_on_slot_input.bind(index))
	panel.mouse_entered.connect(_on_slot_hover.bind(panel, slot, index, true))
	panel.mouse_exited.connect(_on_slot_hover.bind(panel, slot, index, false))

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	panel.add_child(box)

	# 图标：占满剩余高度；出勤中的机器压暗，和暗琥珀描边呼应
	var icon := TextureRect.new()
	icon.texture = slot_icon
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_EXPAND_FILL
	icon.modulate = Color(1, 1, 1, 0.5) if slot.state == InventorySlot.State.ACTIVE else Color.WHITE
	box.add_child(icon)

	var name_label := Label.new()
	name_label.text = slot.title
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.add_theme_color_override("font_color", COLOR_ACCENT if index == _selected else COLOR_TEXT)
	name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	name_label.add_theme_constant_override("shadow_offset_x", 1)
	name_label.add_theme_constant_override("shadow_offset_y", 1)
	box.add_child(name_label)

	var status_label := Label.new()
	status_label.text = slot.status_text
	status_label.add_theme_font_size_override("font_size", 12)
	status_label.add_theme_color_override(
		"font_color",
		COLOR_ACCENT if slot.state == InventorySlot.State.ACTIVE else COLOR_DIM)
	box.add_child(status_label)

	_style_labels(panel)
	return panel

func _slot_style(slot : InventorySlot, selected : bool, hover : bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_BG_HOVER if (selected or hover) else COLOR_BG
	var border_color := COLOR_BORDER
	var border_width := 1
	if selected:
		border_color = COLOR_ACCENT
		border_width = 2
	elif slot.state == InventorySlot.State.ACTIVE:
		border_color = COLOR_ACCENT_DIM
		border_width = 2
	elif hover:
		border_color = COLOR_BORDER_HOVER
		border_width = 2
	style.set_border_width_all(border_width)
	style.border_color = border_color
	style.set_content_margin_all(8)
	return style

func _on_slot_input(event : InputEvent, index : int) -> void:
	if event is InputEventMouseButton \
			and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		slot_activated.emit(index)

func _on_slot_hover(panel : PanelContainer, slot : InventorySlot, index : int, entered : bool) -> void:
	panel.add_theme_stylebox_override("panel", _slot_style(slot, index == _selected, entered))

func _refresh_stats() -> void:
	var deployed := 0
	for slot in _slots:
		if slot.state == InventorySlot.State.ACTIVE:
			deployed += 1
	_stats_label.text = "在库 %d · 出勤 %d" % [_slots.size() - deployed, deployed]

# ---------------------------------------------------------------- 字体

## 与 hud.gd 同一套做法：把字体递归灌给每个文字控件
func _apply_font(node : Node) -> void:
	for child in node.get_children():
		if child is Label:
			child.add_theme_font_override("font", font)
		_apply_font(child)

func _style_labels(node : Node) -> void:
	_apply_font(node)
