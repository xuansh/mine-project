// 行星大气边缘光（自发光光环）
// 用法：套一个比行星本体略大的同款球壳，材质指到本 shader。
// 正面朝向镜头处完全不发光，只有掠射角（球体边缘）发光，于是得到"一圈自发光"；
// 配合 WorldEnvironment 的 Glow，超过 1.0 的部分会自动溢出成柔光晕。
shader_type spatial;
render_mode blend_add, unshaded, cull_back, depth_draw_never, shadows_disabled, fog_disabled;

// 光环颜色。偏蓝最像大气；换暖色就是恒星/熔岩行星
uniform vec4 glow_color : source_color = vec4(0.42, 0.76, 1.0, 1.0);
// 越大光环越细（贴紧边缘）；越小越糊、越往外漫
uniform float rim_power : hint_range(1.0, 8.0) = 3.2;
// 亮度（HDR 值）。大于 1 才会被 Glow 拾取并溢出
uniform float rim_strength : hint_range(0.0, 12.0) = 2.4;
// 球心区域的压暗程度：1 = 中心全黑只剩边缘，0 = 整颗球都发光
uniform float core_fade : hint_range(0.0, 1.0) = 0.85;

void fragment() {
	// facing：1 = 正对镜头，0 = 球体轮廓边缘
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float edge = 1.0 - facing;

	// 菲涅尔衰减 + 中心压暗，保证本体中间不透光
	float rim = pow(edge, rim_power) * smoothstep(0.0, max(core_fade, 0.001), edge);

	ALBEDO = glow_color.rgb * rim_strength;
	ALPHA = clamp(rim, 0.0, 1.0) * glow_color.a;
}
