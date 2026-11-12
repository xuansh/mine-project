extends Control

## Control.tscn 的根节点：主区视图状态机 + 全局 UI 协调（GDD 4.12）。
##
## 主区有三种视图，同一块 1547×802 区域里切换：
##   ORBIT    地球全景（选地点）        OrbitViewContainer
##   MINE     矿场（挖矿）              SubViewportContainer + MineField
##   UPGRADE  升级终端（技能树 CRT）    SubViewportContainer + SkillTreeLayer（矿场 3D 藏起来）
##
## 转场刻意做短（总时长 ≈ 0.3~0.45 秒）：前期会在地球与这两个节点之间频繁来回。

enum View { ORBIT, MINE, UPGRADE }

## 黑幕淡入 / 淡出单程时长
const FADE_TIME : float = 0.14
## 矿场相机缩放时长（"场景缩小"的观感来源）
const ZOOM_TIME : float = 0.18

## 矿场正交相机的取景高度：近景 = 正常游戏，远景 = 转场时的"拉远"
const MINE_SIZE_NEAR : float = 40.0
const MINE_SIZE_FAR : float = 130.0

@onready var _mine_view : SubViewportContainer = $SubViewportContainer
@onready var _orbit_container : SubViewportContainer = $OrbitViewContainer
@onready var _orbit : OrbitView = $OrbitViewContainer/SubViewport/OrbitView
@onready var _mine_field : Node = $SubViewportContainer/SubViewport/Node3D
@onready var _skill_tree_layer : CanvasLayer = $SubViewportContainer/SubViewport/SkillTreeLayer
@onready var _skill_tree : SkillTree = $SubViewportContainer/SubViewport/SkillTreeLayer/SkillTree
@onready var _bottom_bar : BottomBar = $HudLayer/BottomBar
@onready var _fade : ColorRect = %Fade

@export var _hud : Hud

var _view : View = View.ORBIT
## 转场期间锁输入，避免连点把状态机打乱
var _busy : bool = false
## 左栏地球小窗当前是否点亮（只在 ORBIT ↔ 其它 之间切时播 CRT 动画）
var _crt_on : bool = false
## 底栏数据源：换主场景就换它，底栏 UI 本身不认识业务
var _bar_source : Node = null

func _ready() -> void:
	_skill_tree.close_requested.connect(_on_skill_tree_close_requested)
	_hud.action_requested.connect(_on_hud_action_requested)
	_orbit.location_activated.connect(_on_location_activated)

	_bottom_bar.slot_activated.connect(_on_bottom_bar_slot_activated)
	Game.excavators_changed.connect(_refresh_bottom_bar)
	_bar_source = _mine_field

	# 启动即地球全景：左栏小窗直接收掉，不播动画（第一帧没有"关机"的语义）
	_hud.set_earth_crt_immediate(false)
	_apply_view(View.ORBIT)
	_fade.modulate.a = 0.0

# ---------------------------------------------------------------- 视图切换（GDD 4.12）

## 地球全景 → 矿场：先黑场，再让矿场相机从远景收到近景（"落进矿区"）
func go_to_mine() -> void:
	if _busy or _view == View.MINE:
		return
	_busy = true
	var tween := create_tween()
	tween.tween_property(_fade, "modulate:a", 1.0, FADE_TIME)
	tween.tween_callback(func() -> void:
		_apply_view(View.MINE)
		_set_mine_camera(MINE_SIZE_FAR))
	tween.tween_property(_fade, "modulate:a", 0.0, FADE_TIME)
	tween.parallel().tween_method(_set_mine_camera, MINE_SIZE_FAR, MINE_SIZE_NEAR, ZOOM_TIME)
	tween.tween_callback(func() -> void: _busy = false)

## 矿场 → 地球全景：先把矿场拉远（场景缩小），再黑场切走
func go_to_orbit() -> void:
	if _busy or _view == View.ORBIT:
		return
	_busy = true
	var tween := create_tween()
	if _view == View.MINE:
		tween.tween_method(_set_mine_camera, MINE_SIZE_NEAR, MINE_SIZE_FAR, ZOOM_TIME)
	tween.tween_property(_fade, "modulate:a", 1.0, FADE_TIME)
	tween.tween_callback(func() -> void: _apply_view(View.ORBIT))
	tween.tween_property(_fade, "modulate:a", 0.0, FADE_TIME)
	tween.tween_callback(func() -> void: _busy = false)

## 进升级终端：终端本身是满屏 CRT 面板，不做相机缩放，一次黑场就够
func go_to_upgrade() -> void:
	if _busy or _view == View.UPGRADE:
		return
	_busy = true
	var tween := create_tween()
	tween.tween_property(_fade, "modulate:a", 1.0, FADE_TIME)
	tween.tween_callback(func() -> void: _apply_view(View.UPGRADE))
	tween.tween_property(_fade, "modulate:a", 0.0, FADE_TIME)
	tween.tween_callback(func() -> void: _busy = false)

## 只改可见性与 HUD 状态，不带动画。所有转场都通过它落地
func _apply_view(view : View) -> void:
	_view = view
	_mine_view.visible = view != View.ORBIT
	_orbit_container.visible = view == View.ORBIT
	# 升级终端要一块纯黑底，所以把矿场 3D 藏掉，只留 CRT 面板
	_mine_field.visible = view == View.MINE
	_skill_tree_layer.visible = view == View.UPGRADE
	if view == View.UPGRADE:
		_skill_tree.open()
	else:
		_skill_tree.close()

	_orbit.set_active(view == View.ORBIT)
	_hud.set_exit_visible(view == View.MINE)

	# 在地球全景时右侧已经是地球，左栏小窗收起来；进矿场 / 终端时再点亮
	var want_crt : bool = view != View.ORBIT
	if want_crt != _crt_on:
		_crt_on = want_crt
		_hud.play_earth_crt(want_crt)

	_refresh_bottom_bar()

func _set_mine_camera(value : float) -> void:
	if _mine_field != null and _mine_field.has_method("set_camera_size"):
		_mine_field.call("set_camera_size", value)

# ---------------------------------------------------------------- 输入

func _unhandled_input(event : InputEvent) -> void:
	if _busy:
		return
	# 调试：升级终端里 Shift+R 复位改装（清空到根节点并原价退款）。
	# 只在 debug 构建生效，正式包既没有提示也不响应
	if OS.is_debug_build() and _view == View.UPGRADE and event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.shift_pressed \
				and (key.keycode == KEY_R or key.physical_keycode == KEY_R):
			get_viewport().set_input_as_handled()
			_skill_tree.debug_reset_skills()
			return
	# U 键保留为调试快捷入口，正式入口是地球上的「升级终端」节点
	if event.is_action_pressed("Toggle-SkillTree"):
		get_viewport().set_input_as_handled()
		if _view == View.UPGRADE:
			go_to_orbit()
		else:
			go_to_upgrade()
	elif event.is_action_pressed("ui_cancel"):
		if _view != View.ORBIT:
			get_viewport().set_input_as_handled()
			go_to_orbit()

func _on_hud_action_requested(id : StringName) -> void:
	match id:
		&"skill_tree":
			go_to_upgrade()
		&"exit_mine":
			go_to_orbit()
		_:
			pass

func _on_skill_tree_close_requested() -> void:
	go_to_orbit()

func _on_location_activated(location : LocationDefinition) -> void:
	if location.target_view == &"upgrade":
		go_to_upgrade()
	else:
		go_to_mine()

# ---------------------------------------------------------------- 底栏（GDD 4.11）

func _refresh_bottom_bar() -> void:
	if _bar_source == null or not _bar_source.has_method("get_inventory_slots"):
		return
	var context : String = _bar_source.call("get_inventory_context")
	var hint : String = _bar_source.call("get_inventory_hint")
	if _view == View.ORBIT:
		# 地球全景下底栏仍是"持有物"，只是地点导航在右侧地球上
		context = "地球轨道 · 机库"
		hint = "拖动地球转动 · 点黄色标记进入地点"
	_bottom_bar.show_inventory(context, hint, _bar_source.call("get_inventory_slots"))
	_bottom_bar.set_selected(_bar_source.call("get_selected_slot_index"))

func _on_bottom_bar_slot_activated(index : int) -> void:
	if _bar_source == null:
		return
	if _view != View.MINE:
		_bottom_bar.set_hint("派遣挖掘机要在矿场里 · 点地球上的黄色标记进入")
		return
	_bar_source.call("on_inventory_slot_activated", index)
	_refresh_bottom_bar()
