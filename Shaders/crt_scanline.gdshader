shader_type canvas_item;

// 改装终端的 CRT 质感（GDD 4.10.6）：
// 扫描线 1px 亮 / 3px 暗交替，透明度约 8%，静止不滚动；
// 四周加一圈轻微暗角，模拟磷光屏的边缘衰减。
// 挂在最上层全屏 ColorRect 上，mouse_filter 必须是 IGNORE。

void fragment() {
	float scan_f = 0.0;
	if (mod(floor(FRAGCOORD.y), 4.0) < 1.0) {
		scan_f = 0.085;
	}

	vec2 centered = UV - vec2(0.5);
	float dist = length(centered * vec2(1.0, 0.88));
	float vig = smoothstep(0.62, 1.08, dist) * 0.40;

	COLOR = vec4(0.0, 0.0, 0.0, clamp(scan_f + vig, 0.0, 0.85));
}
