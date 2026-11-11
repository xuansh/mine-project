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
@onready var _fuel_bar : HudSegmentBar = %FuelBar
@onready var _fuel_label : Label = %FuelLabel
@onready var _cargo_bar : HudSegmentBar = %CargoBar
@onready var _cargo_label : Label = %CargoLabel
@onready var _income_label : Label = %IncomeLabel

var _excavator : MineableEntity
var _spawn_x : float = 0.0
var _income : float = 0.0
var _cargo_count : int = 0
var _cargo_max : int = CARGO_MAX_PLACEHOLDER

@export var mine_field : Node

## HUD 全局字体：改这一个属性，HUD 里所有文字（含以后新增的）一起换。
## 留空则沿用项目默认字体。
@export var font : Font:
	set(value):
		font = value
		_apply_font()

func _ready() -> void:
	_apply_font()

	mine_field.excavator_spawned.connect(_on_excavator_spawned)

	Game.coins_changed.connect(_on_coins_changed)
	_coin_label.text = _format_coins(Game.coins)

	_cargo_bar.set_values(0.0, float(_cargo_max))
	_fuel_bar.set_values(0.0, 1.0)

	%BtnSkill.pressed.connect(func() -> void: action_requested.emit(&"skill_tree"))
	%BtnUpgrade.pressed.connect(func() -> void: action_requested.emit(&"upgrade"))

## 把 font 灌进根节点的 Theme：Theme 沿节点树向下继承，
## HUD 里所有 Label / Button / 动态新建的文字都会用它；
## 各控件单独设的 font_size 覆盖不受影响。
func _apply_font() -> void:
	if Engine.is_editor_hint():
		return  # 编辑器里不改 theme，免得把运行时 Theme 存进场景文件
	if font == null:
		return
	if theme == null:
		theme = Theme.new()
	theme.default_font = font

func _process(_delta : float) -> void:
	if is_instance_valid(_excavator):
		# 原型只有一层矿，深度先用「离出生点的推进距离」表达（P3 深度即进度）
		var advanced := absf(_excavator.global_position.x - _spawn_x)
		_depth_label.text = "%dM" % roundi(advanced)

# ---------------------------------------------------------------- 挖掘机数据

func _on_excavator_spawned(excavator : MineableEntity) -> void:
	if is_instance_valid(_excavator):
		_excavator.fuel_changed.disconnect(_on_fuel_changed)
		_excavator.drop_gained.disconnect(_on_drop_gained)
		_excavator.fuel_empty.disconnect(_on_fuel_empty)

	_excavator = excavator
	_spawn_x = excavator.global_position.x
	_income = 0.0
	_cargo_count = 0

	excavator.fuel_changed.connect(_on_fuel_changed)
	excavator.drop_gained.connect(_on_drop_gained)
	excavator.fuel_empty.connect(_on_fuel_empty)

	var fuel := excavator.get_fuel_state()
	_on_fuel_changed(fuel.x, fuel.y)
	_refresh_cargo()

func _on_fuel_changed(current : float, max_fuel : float) -> void:
	_fuel_bar.set_values(current, max_fuel)
	_fuel_label.text = "%d/%d" % [roundi(current), roundi(max_fuel)]

func _on_drop_gained(_ore_name : String, value : float) -> void:
	_income += value
	_cargo_count += 1
	_refresh_cargo()

func _on_fuel_empty() -> void:
	_fuel_label.text = "燃油耗尽"

func _refresh_cargo() -> void:
	_cargo_bar.set_values(float(_cargo_count), float(_cargo_max))
	_cargo_label.text = "%d/%d" % [_cargo_count, _cargo_max]
	_income_label.text = "累计收益 %d" % roundi(_income)

# ---------------------------------------------------------------- 金币

func _on_coins_changed(total : int, _delta : int) -> void:
	_coin_label.text = _format_coins(total)

func _format_coins(amount : int) -> String:
	var digits : String = str(absi(amount))
	var out := ""
	for i in range(digits.length()):
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += ","
		out += digits[i]
	return ("-" + out) if amount < 0 else out
