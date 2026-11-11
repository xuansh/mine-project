extends CanvasLayer

## 升级面板（GDD 4.6 / 4.8）：全屏弹层，展示钻头 / 油箱 / 货舱 / 引擎四个改装方向。
## 等级与扣款走 Autoload Game，面板只负责展示、校验点击与刷新。

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

# ---- 色板（GDD 4.8：近黑底 #0E0B09、面板 #1A1512、唯一强调色工程黄 #D9A227）----
const COLOR_MASK := Color("0E0B09")
const COLOR_PANEL := Color("1A1512")
const COLOR_CARD := Color("221B16")
const COLOR_BORDER := Color("6E6459")
const COLOR_ACCENT := Color("D9A227")
const COLOR_ACCENT_TEXT := Color("2A1E05")
const COLOR_TEXT := Color("F2EEDF")
const COLOR_SUBTEXT := Color("8A7E70")
const COLOR_DISABLED_BG := Color("2C241E")
const COLOR_DISABLED_TEXT := Color("5C534A")

@onready var _panel : PanelContainer = $Dim/Center/Panel
@onready var _cards_box : VBoxContainer = $Dim/Center/Panel/Margin/Body/Cards
@onready var _coin_value : Label = $Dim/Center/Panel/Margin/Body/Header/CoinRow/CoinValue
@onready var _close_button : Button = $Dim/Center/Panel/Margin/Body/Header/CloseButton

var _group_order : Array[StringName] = []
## StringName -> Array[UpgradeDefinition]（嵌套类型化集合 GDScript 不支持，这里用裸字典）
var _group_defs : Dictionary = {}
## group -> { level: Label, stats: Dictionary[stat_key, Label], button: Button }
var _cards : Dictionary = {}


func _ready() -> void:
	if definitions.is_empty():
		_load_default_definitions()
	_aggregate_definitions()
	_apply_panel_style()
	_build_cards()

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
	_panel.add_theme_stylebox_override("panel", _make_box_style(COLOR_PANEL, COLOR_BORDER, 10))


func _build_cards() -> void:
	for group in _group_order:
		var defs : Array = _group_defs[group]
		_cards_box.add_child(_make_card(group, defs))


func _make_card(group : StringName, defs : Array) -> PanelContainer:
	var primary : UpgradeDefinition = defs[0]

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _make_box_style(COLOR_CARD, COLOR_BORDER, 8))

	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 18)
	card.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 20)
	margin.add_child(hbox)

	# 左侧：标题 / 等级 / 描述 / 数值行
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 6)
	hbox.add_child(info)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 12)
	info.add_child(title_row)

	var title := Label.new()
	title.text = primary.title
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", COLOR_TEXT)
	title_row.add_child(title)

	var level := Label.new()
	level.add_theme_font_size_override("font_size", 16)
	level.add_theme_color_override("font_color", COLOR_ACCENT)
	title_row.add_child(level)

	var desc := Label.new()
	desc.text = primary.description
	desc.add_theme_font_size_override("font_size", 14)
	desc.add_theme_color_override("font_color", COLOR_SUBTEXT)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(desc)

	var stats := VBoxContainer.new()
	stats.add_theme_constant_override("separation", 4)
	info.add_child(stats)

	var stat_labels : Dictionary[StringName, Label] = {}
	for def in defs:
		var stat_label := Label.new()
		stat_label.add_theme_font_size_override("font_size", 16)
		stat_label.add_theme_color_override("font_color", COLOR_TEXT)
		stats.add_child(stat_label)
		stat_labels[def.stat_key] = stat_label

	# 右侧：购买按钮
	var button := Button.new()
	button.custom_minimum_size = Vector2(180, 56)
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", COLOR_ACCENT_TEXT)
	button.add_theme_color_override("font_disabled_color", COLOR_DISABLED_TEXT)
	button.add_theme_stylebox_override("normal", _make_box_style(COLOR_ACCENT, COLOR_ACCENT, 6))
	button.add_theme_stylebox_override("disabled", _make_box_style(COLOR_DISABLED_BG, COLOR_DISABLED_BG, 6))
	button.pressed.connect(_on_buy_pressed.bind(group))
	hbox.add_child(button)

	_cards[group] = {
		"level": level,
		"stats": stat_labels,
		"button": button,
	}
	return card


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
	if not _cards.has(group):
		return
	var defs : Array = _group_defs[group]
	var card : Dictionary = _cards[group]
	var level := Game.get_group_level(group)

	card["level"].text = "Lv.%d" % level

	for def in defs:
		var label : Label = card["stats"][def.stat_key]
		var cur := _format_value(def, _value_of(def, level))
		if _is_maxed(def, level):
			label.text = "%s  ·  MAX" % cur
		else:
			var nxt := _format_value(def, _value_of(def, level + 1))
			label.text = "%s  →  %s" % [cur, nxt]

	var button : Button = card["button"]
	if _group_maxed(defs, level):
		button.text = "已满级"
		button.disabled = true
	else:
		var cost := _cost_of(defs[0] as UpgradeDefinition, level)
		button.text = "%d 金币" % cost
		button.disabled = Game.coins < cost


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

func _make_box_style(bg : Color, border : Color, radius : int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = border
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_right = radius
	style.corner_radius_bottom_left = radius
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
