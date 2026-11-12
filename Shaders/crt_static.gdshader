shader_type canvas_item;

// 老电视「无信号」屏（GDD 4.12.3 左栏地球小窗）。
//
// 刻意不做真实电视那种亮白雪花——那和深紫 + 工程黄的像素 HUD 完全不是一个色系。
// 这里走「低信号」调子：底子压到比面板稍暗，噪点是暗冷灰紫，只有极少数颗粒
// 会闪一下工程黄；再叠扫描线、缓慢上滚的暗带和四角压暗，整体是"熄了灯的显示器"。

uniform vec4 base_color : source_color = vec4(0.051, 0.043, 0.071, 1.0);
uniform vec4 noise_color : source_color = vec4(0.376, 0.361, 0.435, 1.0);
uniform vec4 spark_color : source_color = vec4(0.851, 0.635, 0.153, 1.0);
uniform float density : hint_range(40.0, 400.0) = 120.0;
uniform float flicker_speed : hint_range(1.0, 40.0) = 12.0;
uniform float noise_strength : hint_range(0.0, 1.0) = 0.55;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	// 颗粒按"像素格"取随机值。格子约 2~3 个屏幕像素，看起来是像素雪花而非白噪
	vec2 grid = floor(UV * vec2(density, density * 0.55));
	float t = floor(TIME * flicker_speed);
	float n = hash(grid + vec2(t * 17.13, t * 7.71));
	float n2 = hash(grid + vec2((t + 1.0) * 17.13, (t + 1.0) * 7.71));
	float grain = mix(n, n2, fract(TIME * flicker_speed));

	// 只有约三成格子亮起来，且亮度都给不满：暗部保持大块，不糊成一片白
	float level = smoothstep(0.62, 0.98, grain) * noise_strength;
	vec3 col = mix(base_color.rgb, noise_color.rgb, level);

	// 极少数颗粒闪一下工程黄，像接触不良的信号尖峰
	float spark = step(0.992, hash(grid.yx * 1.73 + vec2(t * 3.71, t * 9.13)));
	col = mix(col, spark_color.rgb, spark * level * 1.6);

	// 扫描线：细，且几乎只压暗不发光
	col *= 0.93 + 0.07 * sin(UV.y * 640.0);

	// 一条暗带缓慢上滚（比亮带更收敛，不抢画面）
	float band = 1.0 - smoothstep(0.0, 0.34, abs(fract(UV.y + TIME * 0.07) - 0.5));
	col += noise_color.rgb * 0.045 * band;

	// 四角压暗：玻璃管的球面感
	vec2 v = (UV - 0.5) * vec2(1.0, 0.62);
	col *= 1.0 - clamp(dot(v, v) * 1.15, 0.0, 0.55);

	COLOR = vec4(col, 1.0);
}
