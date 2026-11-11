class_name UpgradeGroupNode
extends Control

## 升级面板里的一个改装节点。样式与技能树节点同源：
## 直角像素双层框 + 硬边文字，点击整块购买。

signal pressed(group : StringName)

enum State {
	OK,      # 金币足够，可购买
	POOR,    # 金币不足
	MAXED,   # 已满级
}

const COLOR_FILL := Color("221d30")
const COLOR_CORE_FILL := Color("181420")
const COLOR_FRAME_DARK := Color("221c30")
const COLOR_TEXT := Color(0.941176, 0.933333, 0.894118)
const COLOR_DIM := Color(0.54902, 0.52549, 0.627451)
const COLOR_MAXED := Color("7bd6a4")

const SIZE := Vector2(176, 96)
const CORE_SIZE := 96.0

var group : StringName = &""
var is_core : bool = false
var state : State = State.POOR

var _title : String = ""
var _level_text : String = ""
var _price_text : String = ""
var _accent : Color = Color("d9a227")
var _box : StyleBoxFlat
var _scale_tween : Tween

func _ready() -> void:
	if is_core:
		size = Vector2(CORE_SIZE, CORE_SIZE)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		size = SIZE
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = size
	pivot_offset = size * 0.5

	_box = StyleBoxFlat.new()
	_box.bg_color = COLOR_FILL
	_box.set_corner_radius_all(0)
	_box.set_border_width_all(2)
	_box.shadow_color = COLOR_FRAME_DARK
	_box.shadow_size = 2

	if not is_core:
		mouse_entered.connect(_on_mouse_entered)
		mouse_exited.connect(_on_mouse_exited)
		gui_input.connect(_on_gui_input)

func setup(node_group : StringName, title : String, accent : Color, core : bool = false) -> void:
	group = node_group
	_title = title
	_accent = accent
	is_core = core
	if is_inside_tree():
		_ready()

func update_state(level : int, price_text : String, node_state : State) -> void:
	_level_text = "Lv.%d" % level
	_price_text = price_text
	state = node_state
	queue_redraw()

# ---------------------------------------------------------------- 绘制

func _draw() -> void:
	if is_core:
		_draw_hexagon()
		_draw_text()
		return

	match state:
		State.OK:
			_box.border_color = _accent
		State.POOR:
			_box.border_color = Color(0.29, 0.27, 0.37)
		State.MAXED:
			_box.border_color = COLOR_MAXED
	draw_style_box(_box, Rect2(Vector2.ZERO, size))
	_draw_text()

func _draw_text() -> void:
	var font := get_theme_font("font")
	var width := size.x
	var title_color := COLOR_TEXT
	var level_color := _accent
	var price_color := _accent

	if is_core:
		draw_string(font, Vector2(0, size.y * 0.5 + 6.0), _title,
			HORIZONTAL_ALIGNMENT_CENTER, width, 16, title_color)
		return

	match state:
		State.POOR:
			title_color = COLOR_DIM
			level_color = COLOR_DIM
			price_color = COLOR_DIM
		State.MAXED:
			level_color = COLOR_TEXT
			price_color = COLOR_MAXED

	draw_string(font, Vector2(0, 30.0), _title,
		HORIZONTAL_ALIGNMENT_CENTER, width, 15, title_color)
	draw_string(font, Vector2(0, 54.0), _level_text,
		HORIZONTAL_ALIGNMENT_CENTER, width, 16, level_color)
	draw_string(font, Vector2(0, 80.0), _price_text,
		HORIZONTAL_ALIGNMENT_CENTER, width, 14, price_color)

func _draw_hexagon() -> void:
	var points := _hex_points(size.x * 0.5 - 3.0)
	draw_colored_polygon(points, COLOR_CORE_FILL)
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, Color(_accent, 0.28), 5.0, false)
	draw_polyline(outline, _accent, 2.0, false)

func _hex_points(radius : float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var center := size * 0.5
	for i in 6:
		var angle : float = -PI * 0.5 + TAU * float(i) / 6.0
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points

# ---------------------------------------------------------------- 交互

func _on_mouse_entered() -> void:
	_tween_scale(1.05)

func _on_mouse_exited() -> void:
	_tween_scale(1.0)

func _on_gui_input(event : InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			pressed.emit(group)

func _tween_scale(target : float) -> void:
	if _scale_tween != null and _scale_tween.is_valid():
		_scale_tween.kill()
	_scale_tween = create_tween()
	_scale_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_scale_tween.tween_property(self, "scale", Vector2.ONE * target, 0.12)
