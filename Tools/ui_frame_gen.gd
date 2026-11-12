extends SceneTree

# 依据 AI 母版配色重绘的九宫格边框（像素严格对齐，可调参）
const S := 128
const OUT_W := 3          # 外框线宽
const IN_INSET := 10      # 内框内缩
const IN_W := 2           # 内框线宽
const ARM := 40           # 角标臂长
const OUT := "D:/Work/Godot/mine-project/Assets/Textures/UI_Frame_HUD.png"

const C_FILL := Color8(11, 10, 18)     # #0B0A12
const C_INNER := Color8(42, 36, 56)    # #2A2438
const C_LIGHT := Color8(139, 132, 168) # #8B84A8
const C_AMBER := Color8(217, 162, 39)  # #D9A227

func hstroke(img: Image, x0: int, x1: int, y: int, w: int, color: Color) -> void:
	for x in range(x0, x1 + 1):
		for t in w:
			img.set_pixel(x, y + t, color)

func vstroke(img: Image, y0: int, y1: int, x: int, w: int, color: Color) -> void:
	for y in range(y0, y1 + 1):
		for t in w:
			img.set_pixel(x + t, y, color)

func _initialize() -> void:
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	img.fill(C_FILL)

	# 外框
	var e0 := S - OUT_W
	hstroke(img, 0, S - 1, 0, OUT_W, C_LIGHT)
	hstroke(img, 0, S - 1, e0, OUT_W, C_LIGHT)
	vstroke(img, 0, S - 1, 0, OUT_W, C_LIGHT)
	vstroke(img, 0, S - 1, e0, OUT_W, C_LIGHT)

	# 内框
	var a := IN_INSET
	var b := S - IN_INSET - IN_W
	hstroke(img, a, b + IN_W - 1, a, IN_W, C_INNER)
	hstroke(img, a, b + IN_W - 1, b, IN_W, C_INNER)
	vstroke(img, a, b + IN_W - 1, a, IN_W, C_INNER)
	vstroke(img, a, b + IN_W - 1, b, IN_W, C_INNER)

	# 四角角标：沿内框把靠角的臂长段提亮
	var a1 := a + ARM
	var b1 := b - ARM
	hstroke(img, a, a1, a, IN_W, C_LIGHT)
	vstroke(img, a, a1, a, IN_W, C_LIGHT)
	hstroke(img, b1, b + IN_W - 1, a, IN_W, C_LIGHT)
	vstroke(img, a, a1, b, IN_W, C_LIGHT)
	hstroke(img, a, a1, b, IN_W, C_LIGHT)
	vstroke(img, b1, b + IN_W - 1, a, IN_W, C_LIGHT)
	hstroke(img, b1, b + IN_W - 1, b, IN_W, C_LIGHT)
	vstroke(img, b1, b + IN_W - 1, b, IN_W, C_LIGHT)

	# 四角琥珀铆点
	var dot := 4
	var gap := IN_INSET - OUT_W
	var d := OUT_W + (gap - dot) / 2
	for p in [[d, d], [S - d - dot, d], [d, S - d - dot], [S - d - dot, S - d - dot]]:
		for y in dot:
			for x in dot:
				img.set_pixel(p[0] + x, p[1] + y, C_AMBER)

	img.save_png(OUT)
	print("saved ", OUT, " margin_needed=", IN_INSET + ARM + IN_W, " amber at ", d)

	for y in 34:
		var s := ""
		for x in 60:
			var c := img.get_pixel(x, y)
			if c == C_AMBER: s += "*"
			elif c == C_LIGHT: s += "#"
			elif c == C_INNER: s += "+"
			else: s += "."
		print("%2d|%s|" % [y, s])
	quit()
