shader_type canvas_item;

// PS1 / low-poly 风格后处理（参考复古低模渲染图）：
// 1) 低色阶量化（posterize）—— 明暗只有有限的几档，出现硬色带
// 2) 4x4 有序抖动（Bayer dither）—— 色带之间撒出颗粒过渡，PS1 味的关键
// 3) 可选额外像素化 + 低饱和，整体压向参考图那种哑光灰调
//
// 用法：挂在覆盖 SubViewportContainer 的全屏 ColorRect 上，
// 采样屏幕已有内容（即 SubViewport 渲染出的 3D 画面）。

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform int color_levels : hint_range(2, 32) = 10;    // 每个通道的色阶数，越小越"cheap"
uniform float dither_strength : hint_range(0.0, 1.0) = 0.45; // 抖动强度，0 关闭颗粒
uniform float pixel_size : hint_range(1.0, 8.0) = 1.0;       // 额外像素化倍数，1 = 关闭（分辨率交给 stretch_shrink）
uniform float saturation : hint_range(0.0, 1.5) = 0.85;      // 参考图的低饱和哑光感

const float BAYER4 : float[16] = float[16](
	 0.0,  8.0,  2.0, 10.0,
	12.0,  4.0, 14.0,  6.0,
	 3.0, 11.0,  1.0,  9.0,
	15.0,  7.0, 13.0,  5.0
);

void fragment() {
	vec2 screen_res = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 uv = UV;

	// 额外像素化：把采样点吸附到更大的网格上
	if (pixel_size > 1.0) {
		vec2 grid = screen_res / pixel_size;
		uv = (floor(UV * grid) + 0.5) / grid;
	}

	vec3 col = texture(screen_tex, uv).rgb;

	// 低饱和，向参考图的哑光灰调靠拢
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(luma), col, saturation);

	// 4x4 有序抖动：先按抖动矩阵扰动，再量化出硬色带
	ivec2 p = ivec2(floor(FRAGCOORD.xy / max(pixel_size, 1.0)));
	int idx = (p.x % 4) * 4 + (p.y % 4);
	float d = BAYER4[idx] / 16.0 - 0.5;
	col += d * dither_strength / float(color_levels);

	// 色阶量化
	col = floor(col * float(color_levels) + 0.5) / float(color_levels);
	col = clamp(col, 0.0, 1.0);

	COLOR = vec4(col, 1.0);
}
