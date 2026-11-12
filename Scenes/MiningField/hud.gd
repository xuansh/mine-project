class_name Hud
extends Control

## 游戏内 HUD（参考复古像素太空 HUD 的布局）：
## 左侧状态栏（掘进深度 / 机体油量 / 货舱收益 / 导航目标）
## + 左下功能按钮列 + 右上「矿报」牌 + 右下大按钮。
## 数据来源：MineField.excavator_spawned 转发挖掘机信号，Game 单例管金币。

signal action_requested(id : StringName)

## 货舱字段还没接入实体（GDD 4.5），先用占位容量
const CARGO_MAX_PLACEHOLDER := 20

@onready var _coin_label : Label = %CoinLabel
@onready var _depth_label : Label = %DepthLabel
@onready var _cargo_bar : HudSegmentBar = %CargoBar
@onready var _cargo_label : Label = %CargoLabel
@onready var _income_label : Label = %IncomeLabel
@onready var _coin_cell_label : Label = %CoinCellLabel
@onready var _skill_label : Label = %SkillLabel
@onready var _best_label : Label = %BestLabel
@onready var _lv_label : Label = %LvLabel
@onready var _xp_bar : HudSegmentBar = %XpBar

var _excavator : MineableEntity
var _spawn_x : float = 0.0
var _income : float = 0.0
var _cargo_count : int = 0
var _cargo_max : int = CARGO_MAX_PLACEHOLDER

@export var mine_field : Node

## HUD 全局字体：换这个资源，HUD 里所有文字一起换。
## 留空则用项目默认字体。
@export var font : Font:
	set(value):
		font = value
		if is_node_ready() and not Engine.is_editor_hint():
			_apply_font()

func _ready() -> void:
	_apply_font()

	mine_field.excavator_spawned.connect(_on_excavator_spawned)

	Game.coins_changed.connect(_on_coins_changed)
	_coin_label.text = _format_coins(Game.coins)

	Game.stats_changed.connect(_refresh_stats)
	_refresh_stats()

	_cargo_bar.set_values(0.0, float(_cargo_max))

	%BtnSkill.pressed.connect(func() -> void: action_requested.emit(&"skill_tree"))

## 把 font 递归灌给每一个文字控件（Label / Button / RichTextLabel 都吃 "font" 这个主题项）。
## 只改字形不动 font_size，各控件原有的字号设置保持不变。
func _apply_font() -> void:
	_apply_font_to(self)

func _apply_font_to(node : Node) -> void:
	for child in node.get_children():
		if child is Control:
			if font != null:
				child.add_theme_font_override("font", font)
			else:
				child.remove_theme_font_override("font")
		_apply_font_to(child)

func _process(_delta : float) -> void:
	if is_instance_valid(_excavator):
		# 原型只有一层矿，深度先用「离出生点的推进距离」表达（P3 深度即进度）
		var advanced := absf(_excavator.global_position.x - _spawn_x)
		_depth_label.text = "%dM" % roundi(advanced)
		Game.report_depth(advanced)

# ---------------------------------------------------------------- 挖掘机数据

func _on_excavator_spawned(excavator : MineableEntity) -> void:
	if is_instance_valid(_excavator):
		_excavator.drop_gained.disconnect(_on_drop_gained)

	_excavator = excavator
	_spawn_x = excavator.global_position.x
	_income = 0.0
	_cargo_count = 0

	excavator.drop_gained.connect(_on_drop_gained)

	var fuel := excavator.get_fuel_state()
	_refresh_cargo()


func _on_drop_gained(_ore_name : String, value : float) -> void:
	_income += value
	_cargo_count += 1
	_refresh_cargo()


func _refresh_cargo() -> void:
	_cargo_bar.set_values(float(_cargo_count), float(_cargo_max))
	_cargo_label.text = "%d/%d" % [_cargo_count, _cargo_max]
	_income_label.text = "累计收益 %d" % roundi(_income)

# ---------------------------------------------------------------- 金币

func _on_coins_changed(total : int, _delta : int) -> void:
	_coin_label.text = _format_coins(total)
	_coin_cell_label.text = _format_coins(total)

# ---------------------------------------------------------------- 玩家成长

func _refresh_stats() -> void:
	_coin_cell_label.text = _format_coins(Game.coins)
	_skill_label.text = str(Game.skill_points)
	_best_label.text = "%dM" % roundi(Game.best_depth)
	_lv_label.text = "LV %d" % Game.level
	_xp_bar.set_values(float(Game.xp), float(Game.xp_to_next))

func _format_coins(amount : int) -> String:
	var digits : String = str(absi(amount))
	var out := ""
	for i in range(digits.length()):
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += ","
		out += digits[i]
	return ("-" + out) if amount < 0 else out
