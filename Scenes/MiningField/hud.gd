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

## 左栏地球小窗：CRT 开关机动画的操作对象（GDD 4.12）
@onready var _earth_view : Control = %EarthView
@onready var _earth_screen : Control = %SubViewportContainer
@onready var _earth_viewport : SubViewport = %SubViewport
@onready var _earth_caption : Control = %EarthCaption
@onready var _no_signal : Control = %NoSignal
@onready var _crt_flash : ColorRect = %CrtFlash

var _crt_tween : Tween

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
	%BtnExit.pressed.connect(func() -> void: action_requested.emit(&"exit_mine"))

# ---------------------------------------------------------------- 左栏地球小窗（GDD 4.12）

## 「退」按钮只在矿场里显示（在地球全景时本来就在外面了）
func set_exit_visible(on : bool) -> void:
	%BtnExit.visible = on

## 瞬切小窗状态（启动时用）。不播动画，避免第一帧先亮再关
func set_earth_crt_immediate(power_on : bool) -> void:
	if _crt_tween != null and _crt_tween.is_valid():
		_crt_tween.kill()
	if not is_node_ready():
		return
	_earth_screen.visible = power_on
	_earth_screen.scale = Vector2.ONE
	_earth_caption.visible = power_on
	_earth_caption.modulate.a = 1.0
	# 关机后屏幕显示"无信号"雪花，而不是一片空
	_no_signal.visible = not power_on
	_no_signal.scale = Vector2.ONE
	_no_signal.modulate.a = 1.0
	_crt_flash.modulate.a = 0.0
	_set_earth_rendering(power_on)

## 小窗关掉时停掉地球 SubViewport 的渲染，别让一颗看不见的星球继续吃 GPU
func _set_earth_rendering(on : bool) -> void:
	_earth_viewport.render_target_update_mode = \
		SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED

## 古早电视关机 / 开机：纵向先压成一条亮线，再横向收成一个点，
## 关机后接通"无信号"雪花屏；开机则反过来，从一条亮线展开成地球。
## 时长刻意压到 0.2~0.3 秒——这两个视图会被频繁来回切，动画拖长就烦
func play_earth_crt(power_on : bool) -> void:
	if not is_node_ready():
		return
	if _crt_tween != null and _crt_tween.is_valid():
		_crt_tween.kill()

	# 收缩必须围绕屏幕中心，否则会往左上角缩
	var screen_size := _earth_screen.size
	if screen_size.x <= 0.0 or screen_size.y <= 0.0:
		screen_size = _earth_view.size
	_earth_screen.pivot_offset = screen_size * 0.5
	_no_signal.pivot_offset = screen_size * 0.5

	_crt_tween = create_tween()
	_crt_tween.set_trans(Tween.TRANS_QUAD)

	if power_on:
		# 先让雪花噪点闪掉，再从一条亮线展开
		_crt_tween.tween_property(_no_signal, "modulate:a", 0.0, 0.05)
		_crt_tween.tween_callback(func() -> void:
			_no_signal.visible = false
			_earth_screen.visible = true
			_earth_screen.scale = Vector2(0.02, 0.035)
			_earth_caption.visible = true
			_earth_caption.modulate.a = 0.0
			_crt_flash.modulate.a = 0.85
			_set_earth_rendering(true))
		_crt_tween.tween_property(_earth_screen, "scale", Vector2(1.0, 0.035), 0.08)
		_crt_tween.tween_property(_earth_screen, "scale", Vector2.ONE, 0.11) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_crt_tween.parallel().tween_property(_crt_flash, "modulate:a", 0.0, 0.14)
		_crt_tween.parallel().tween_property(_earth_caption, "modulate:a", 1.0, 0.16)
	else:
		_crt_flash.modulate.a = 0.0
		_crt_tween.tween_property(_crt_flash, "modulate:a", 0.9, 0.07)
		_crt_tween.parallel().tween_property(_earth_screen, "scale", Vector2(1.0, 0.035), 0.14) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		_crt_tween.parallel().tween_property(_earth_caption, "modulate:a", 0.0, 0.10)
		_crt_tween.tween_property(_earth_screen, "scale", Vector2(0.02, 0.035), 0.07)
		_crt_tween.parallel().tween_property(_crt_flash, "modulate:a", 0.0, 0.10)
		_crt_tween.tween_callback(func() -> void:
			_earth_screen.visible = false
			_earth_caption.visible = false
			_set_earth_rendering(false)
			# 画面收成一个点之后，雪花"啪"地一下铺满：接上没有信号的死频道
			_no_signal.visible = true
			_no_signal.modulate.a = 1.0
			_no_signal.scale = Vector2(1.0, 0.10))
		_crt_tween.tween_property(_no_signal, "scale", Vector2.ONE, 0.09) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

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
