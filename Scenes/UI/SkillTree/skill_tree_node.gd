class_name SkillTreeNode
extends Control

## 改装树上的一个节点。图形全部用 _draw 画出来，不依赖美术资源。
## 琥珀单色 CRT（GDD 4.10.6）：不使用 SkillNodeData.accent_color，
## 所有节点统一走琥珀色板，只有状态区分明暗。

signal pressed(node_id : StringName)

enum State {
	LOCKED,
	AVAILABLE,
	UNLOCKED,
}

const COLOR_AMBER := Color("D9A227")
const COLOR_AMBER_DIM := Color("6E5A1E")
const COLOR_AMBER_DEEP := Color("4A3D22")
const COLOR_CELL := Color("12100B")
const COLOR_CELL_OFF := Color("0E0C09")
const COLOR_LOCK_LINE := Color("332B19")
const COLOR_LABEL := Color("F0EEE4")
const COLOR_LABEL_LOCKED := Color("6B6047")
const COLOR_LABEL_PENDING := Color("6E5A1E")
const COLOR_LINE_OFF := Color("2A2438")

const SQUARE_SIZE : float = 64.0
const HEXAGON_SIZE : float = 88.0
const LABEL_WIDTH : float = 164.0

var data : SkillNodeData
var state : State = State.LOCKED
var is_selected : bool = false
## 效果依赖的机制尚未实现（GDD 4.10.3 批次 2）：可读不可买，右上角带 ! 标记
var is_pending : bool = false

var _box : StyleBoxFlat
var _label : Label
var _scale_tween : Tween

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_ALL

	_box = StyleBoxFlat.new()
	_box.set_corner_radius_all(0)
	_box.set_border_width_all(2)
	_box.shadow_size = 0

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", 14)
	add_child(_label)

	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	focus_entered.connect(_on_focus_changed)
	focus_exited.connect(_on_focus_changed)

func setup(node_data : SkillNodeData, node_state : State, pending : bool = false) -> void:
	data = node_data
	state = node_state
	is_pending = pending

	var side : float = HEXAGON_SIZE if data.shape == SkillNodeData.Shape.HEXAGON else SQUARE_SIZE
	size = Vector2(side, side)
	custom_minimum_size = size
	pivot_offset = size * 0.5
	tooltip_text = "%s\n%s" % [data.title, data.get_effect_text()]

	_refresh()
	_layout_label()

func set_state(node_state : State) -> void:
	state = node_state
	_refresh()

func set_selected(value : bool) -> void:
	is_selected = value
	queue_redraw()

# ---------------------------------------------------------------- 绘制

func _draw() -> void:
	if data == null:
		return

	var accent := _accent_color()
	if data.shape == SkillNodeData.Shape.HEXAGON:
		_draw_hexagon(accent)
	else:
		_box.border_color = accent
		draw_style_box(_box, Rect2(Vector2.ZERO, size))

	_draw_icon(accent)

	if is_pending:
		_draw_pending_badge()

	if is_selected or has_focus():
		var radius : float = maxf(size.x, size.y) * 0.5 + 8.0
		draw_arc(size * 0.5, radius, 0.0, TAU, 48, Color(COLOR_AMBER.r, COLOR_AMBER.g, COLOR_AMBER.b, 0.7), 2.0, false)

func _draw_hexagon(accent : Color) -> void:
	var points := _hex_points(size.x * 0.5 - 3.0)
	var fill := COLOR_CELL_OFF if state == State.LOCKED else COLOR_CELL
	draw_colored_polygon(points, fill)

	var outline := points.duplicate()
	outline.append(points[0])
	var line_color := accent if state != State.LOCKED else COLOR_LOCK_LINE
	draw_polyline(outline, Color(line_color, 0.10), 10.0, false)
	draw_polyline(outline, Color(line_color, 0.24), 4.0, false)
	draw_polyline(outline, line_color, 2.0, false)

## 未就绪标记：右上角琥珀小方块 + 感叹号
func _draw_pending_badge() -> void:
	var rect := Rect2(Vector2(size.x - 14.0, -7.0), Vector2(14.0, 14.0))
	draw_rect(rect, COLOR_AMBER)
	var font := ThemeDB.fallback_font
	draw_string(font, rect.position + Vector2(3.5, 11.0), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COLOR_CELL)

func _draw_icon(accent : Color) -> void:
	var center := size * 0.5
	var scale_factor : float = minf(size.x, size.y) / 64.0
	var ink := accent.lightened(0.38)
	if state == State.LOCKED:
		ink = ink.darkened(0.45)
	elif is_pending:
		ink = COLOR_AMBER_DIM

	match data.effect_key:
		&"excavator_speed":
			_draw_speed(center, scale_factor, ink)
		&"ore_value":
			_draw_coin(center, scale_factor, ink)
		_:
			_draw_core(center, scale_factor, ink)

## 速度表：半圈刻度 + 指针 + 速度线
func _draw_speed(center : Vector2, s : float, ink : Color) -> void:
	var dial_center := center + Vector2(0.0, 5.0) * s
	draw_arc(dial_center, 15.0 * s, PI, TAU, 24, ink, 3.0 * s, true)
	draw_line(dial_center, dial_center + Vector2(9.0, -10.0) * s, ink.lightened(0.35), 2.4 * s, true)
	draw_circle(dial_center, 3.2 * s, ink)
	draw_line(center + Vector2(-20.0, -3.0) * s, center + Vector2(-12.0, -3.0) * s, Color(ink, 0.75), 2.0 * s, true)
	draw_line(center + Vector2(-19.0, 5.0) * s, center + Vector2(-11.0, 5.0) * s, Color(ink, 0.55), 2.0 * s, true)

## 金币：外圈 + 内圈 + 一点高光
func _draw_coin(center : Vector2, s : float, ink : Color) -> void:
	draw_circle(center, 16.5 * s, ink.darkened(0.4))
	draw_circle(center, 13.5 * s, ink)
	draw_circle(center, 9.0 * s, ink.darkened(0.2))
	draw_arc(center, 9.0 * s, -2.5, -0.9, 12, Color(1, 1, 1, 0.5), 1.6 * s, true)

## 核心：双层菱形宝石
func _draw_core(center : Vector2, s : float, ink : Color) -> void:
	var outer := PackedVector2Array([
		center + Vector2(0.0, -18.0) * s,
		center + Vector2(15.0, 0.0) * s,
		center + Vector2(0.0, 18.0) * s,
		center + Vector2(-15.0, 0.0) * s,
	])
	draw_colored_polygon(outer, ink)
	var inner := PackedVector2Array([
		center + Vector2(0.0, -9.0) * s,
		center + Vector2(7.5, 0.0) * s,
		center + Vector2(0.0, 9.0) * s,
		center + Vector2(-7.5, 0.0) * s,
	])
	draw_colored_polygon(inner, ink.darkened(0.32))
	draw_line(center + Vector2(-6.0, -7.0) * s, center + Vector2(0.0, -13.0) * s, Color(1, 1, 1, 0.55), 1.4 * s, true)

func _hex_points(radius : float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var center := size * 0.5
	for i in 6:
		var angle : float = -PI * 0.5 + TAU * float(i) / 6.0
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points

## 琥珀单色：按状态明暗，不再读每个节点的 accent_color
func _accent_color() -> Color:
	match state:
		State.LOCKED:
			return COLOR_LOCK_LINE
		State.UNLOCKED:
			return COLOR_AMBER
		_:
			return COLOR_AMBER_DIM if is_pending else COLOR_AMBER

func _refresh() -> void:
	if _box != null:
		_box.bg_color = COLOR_CELL_OFF if state == State.LOCKED else COLOR_CELL
		_box.border_color = _accent_color()
	if _label != null and data != null:
		_label.text = data.title
		var label_color := COLOR_LABEL
		if state == State.LOCKED:
			label_color = COLOR_LABEL_LOCKED
		elif is_pending:
			label_color = COLOR_LABEL_PENDING
		_label.add_theme_color_override("font_color", label_color)
	queue_redraw()

func _layout_label() -> void:
	if _label == null:
		return
	_label.position = Vector2((size.x - LABEL_WIDTH) * 0.5, size.y + 8.0)
	_label.size = Vector2(LABEL_WIDTH, 20.0)

# ---------------------------------------------------------------- 交互

func _gui_input(event : InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			grab_focus()
			pressed.emit(data.id)
	elif event.is_action_pressed("ui_accept"):
		accept_event()
		pressed.emit(data.id)

func _on_mouse_entered() -> void:
	_tween_scale(1.06)

func _on_mouse_exited() -> void:
	_tween_scale(1.0)

func _on_focus_changed() -> void:
	queue_redraw()

func _tween_scale(target : float) -> void:
	if _scale_tween != null and _scale_tween.is_valid():
		_scale_tween.kill()
	_scale_tween = create_tween()
	_scale_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_scale_tween.tween_property(self, "scale", Vector2.ONE * target, 0.12)
