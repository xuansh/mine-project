class_name UpgradePanel
extends CanvasLayer

## 升级面板（GDD 4.6 / 4.8）：全屏弹层，节点树样式。
## 中心「挖掘核心」向四向发散出钻头 / 货舱 / 引擎 / 油箱四个改装节点，
## 点节点花金币购买，等级与扣款走 Autoload Game，面板只负责展示、校验点击与刷新。

## 升级定义列表。留空时自动加载默认的五份 .tres，改数值去 Resource 不改这里
@export var definitions : Array[UpgradeDefinition] = []

## 调试快捷键：开关面板。接入 HUD 按钮后可在检查器清空或删除 _input 里这段
@export var debug_toggle_key : Key = KEY_U

const DEFAULT_DEFINITION_PATHS := [
	"res://Resources/Upgrades/drill_attack.tres",
	"res://Resources/Upgrades/drill_interval.tres",
	"res://Resources/Upgrades/fuel_tank.tres",
	"res://Resources/Upgrades/cargo_bay.tres",
	"res://Resources/Upgrades/engine.tres",
]

# ---- 色板（像素 HUD 风：深紫夜底 #0B0A12、面板 #181420、灰紫描边 #6E6884、唯一强调色工程黄 #D9A227）----
const COLOR_MASK := Color("0b0a12")
const COLOR_PANEL := Color("181420")
const COLOR_FRAME_DARK := Color("221c30")
const COLOR_BORDER := Color("6e6884")
const COLOR_ACCENT := Color("D9A227")
const COLOR_ACCENT_TEXT := Color("2A1E05")
const COLOR_TEXT := Color("F0EEE4")
const COLOR_SUBTEXT := Color("9a94ac")
const COLOR_DISABLED_BG := Color("1b1726")
const COLOR_DISABLED_TEXT := Color("6b667d")

@onready var _panel : PanelContainer = $Dim/Center/Panel
@onready var _tree_area : UpgradeTreeArea = $Dim/Center/Panel/Margin/Body/TreeArea
@onready var _coin_value : Label = $Dim/Center/Panel/Margin/Body/Header/CoinRow/CoinValue
@onready var _close_button : Button = $Dim/Center/Panel/Margin/Body/Header/CloseButton

var _group_order : Array[StringName] = []
## StringName -> Array[UpgradeDefinition]（嵌套类型化集合 GDScript 不支持，这里用裸字典）
var _group_defs : Dictionary = {}


func _ready() -> void:
	if definitions.is_empty():
		_load_default_definitions()
	_aggregate_definitions()
	_apply_panel_style()
	_build_tree()

	_close_button.pressed.connect(close_panel)
	Game.coins_changed.connect(_on_coins_changed)
	Game.upgrades_changed.connect(_on_upgrades_changed)

	refresh_all()
	visible = false


# ---------------------------------------------------------------- 对外接口

## 打开面板并刷新一次数据
func open_panel() -> void:
	refresh_all()
	visible = true


func close_panel() -> void:
	visible = false


func toggle_panel() -> void:
	if visible:
		close_panel()
	else:
		open_panel()


# ---------------------------------------------------------------- 定义聚合

func _load_default_definitions() -> void:
	for path in DEFAULT_DEFINITION_PATHS:
		var def := load(path) as UpgradeDefinition
		if def != null:
			definitions.append(def)


func _aggregate_definitions() -> void:
	for def in definitions:
		if def.group == &"":
			continue
		if not _group_defs.has(def.group):
			_group_defs[def.group] = []
			_group_order.append(def.group)
		_group_defs[def.group].append(def)


# ---------------------------------------------------------------- 面板搭建

func _apply_panel_style() -> void:
	_panel.add_theme_stylebox_override("panel", _make_box_style(COLOR_PANEL, COLOR_BORDER))


func _build_tree() -> void:
	var titles := {}
	for group in _group_order:
		titles[group] = (_group_defs[group][0] as UpgradeDefinition).title
	_tree_area.setup(titles)
	_tree_area.buy_requested.connect(_on_buy_pressed)


# ---------------------------------------------------------------- 数值与成本

## 等级 level 时的数值：递增封顶 max，递减（如攻击间隔）贴到 max 为止
func _value_of(def : UpgradeDefinition, level : int) -> float:
	var raw := def.base_value + def.increment * level
	if def.increment >= 0.0:
		return minf(raw, def.max_value)
	return maxf(raw, def.max_value)


func _is_maxed(def : UpgradeDefinition, level : int) -> bool:
	return is_equal_approx(_value_of(def, level), _value_of(def, level + 1))


func _group_maxed(defs : Array, level : int) -> bool:
	for def in defs:
		if not _is_maxed(def, level):
			return false
	return true


## cost(n) = base_cost × cost_growth^n，n 为已购买次数
func _cost_of(def : UpgradeDefinition, level : int) -> int:
	return roundi(def.base_cost * pow(def.cost_growth, level))


func _format_value(def : UpgradeDefinition, value : float) -> String:
	return String.num(value, def.decimals) + def.unit


# ---------------------------------------------------------------- 刷新与购买

func refresh_all() -> void:
	_coin_value.text = _format_coins(Game.coins)
	for group in _group_order:
		_refresh_card(group)


func _refresh_card(group : StringName) -> void:
	if not _group_defs.has(group):
		return
	var defs : Array = _group_defs[group]
	var level := Game.get_group_level(group)

	var node_state : UpgradeGroupNode.State
	var price_text : String
	if _group_maxed(defs, level):
		node_state = UpgradeGroupNode.State.MAXED
		price_text = "已满级"
	else:
		var cost := _cost_of(defs[0] as UpgradeDefinition, level)
		price_text = "%d 金币" % cost
		node_state = UpgradeGroupNode.State.OK if Game.coins >= cost else UpgradeGroupNode.State.POOR

	_tree_area.update_node(group, level, price_text, node_state)


func _on_buy_pressed(group : StringName) -> void:
	var defs : Array = _group_defs[group]
	var level := Game.get_group_level(group)
	if _group_maxed(defs, level):
		return
	var cost := _cost_of(defs[0] as UpgradeDefinition, level)
	if not Game.spend_coins(cost):
		return
	Game.add_group_level(group)


func _on_coins_changed(total : int, _delta : int) -> void:
	_coin_value.text = _format_coins(total)
	for group in _group_order:
		_refresh_card(group)


func _on_upgrades_changed(_group : StringName, _level : int) -> void:
	refresh_all()


# ---------------------------------------------------------------- 输入

func _input(event : InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if visible:
			close_panel()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == debug_toggle_key:
			toggle_panel()
			get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- 工具

func _make_box_style(bg : Color, border : Color) -> StyleBoxFlat:
	# 像素风：直角 + 2px 描边 + 外圈暗色定界，模拟参考图的双层框
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = border
	style.shadow_color = COLOR_FRAME_DARK
	style.shadow_size = 2
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style


func _format_coins(amount : int) -> String:
	var digits : String = str(absi(amount))
	var out := ""
	for i in range(digits.length()):
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += ","
		out += digits[i]
	return ("-" + out) if amount < 0 else out
