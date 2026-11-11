class_name HudSegmentBar
extends Control

## 分段式像素状态条（对应参考图 19/32 那种一格一格的条）。
## 不依赖贴图，全靠 _draw 画方块，格子数、颜色都可调。

@export var current : float = 1.0:
	set(value):
		current = maxf(value, 0.0)
		queue_redraw()
@export var max_value : float = 1.0:
	set(value):
		max_value = maxf(value, 0.001)
		queue_redraw()
@export_range(1, 40) var segments : int = 20:
	set(value):
		segments = maxi(value, 1)
		queue_redraw()
@export var fill_color : Color = Color("d9a227"):
	set(value):
		fill_color = value
		queue_redraw()
@export var empty_color : Color = Color(0.16, 0.14, 0.22, 1.0):
	set(value):
		empty_color = value
		queue_redraw()

func _init() -> void:
	custom_minimum_size = Vector2(0, 14)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_values(new_current : float, new_max : float) -> void:
	current = new_current
	max_value = new_max

func _draw() -> void:
	var gap := 2.0
	var seg_width := (size.x - gap * float(segments - 1)) / float(segments)
	var lit := 0
	if max_value > 0.0:
		lit = roundi(current / max_value * float(segments))
	for i in segments:
		var rect := Rect2(float(i) * (seg_width + gap), 0.0, seg_width, size.y)
		draw_rect(rect, fill_color if i < lit else empty_color)
