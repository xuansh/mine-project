// UI 贴图换色（保留原图明暗，把颜色重映射到自己的配色）
// 用法：给用到贴图样式（StyleBoxTexture / 普通纹理）的 Control 挂这个 ShaderMaterial。
// 原理：按亮度把原图分三段 —— 最暗→dark_color，主体→mid_color，最亮→light_color，
//      描边/高光/阴影的位置全部保留，只换色相，像素硬边不会糊。
// 注意：ShaderMaterial 只影响挂它的那个控件自己的绘制，子节点（HUD 文字、卡片）不会被染色。
shader_type canvas_item;

// 原图最暗 / 最亮的亮度（校准用）。原图没用到纯白，所以上限通常是 0.6~0.7 而不是 1.0
uniform float lum_low : hint_range(0.0, 1.0) = 0.0;
uniform float lum_high : hint_range(0.0, 1.0) = 0.65;
// 亮度分界：低于它走 dark→mid，高于它走 mid→light。调大 = 主体色占得更多
uniform float mid_point : hint_range(0.05, 0.95) = 0.66;

// 最暗处（原图的黑色描边）
uniform vec4 dark_color : source_color = vec4(0.020, 0.031, 0.051, 1.0);
// 主体色（原图的蓝色填充）—— 面板底色
uniform vec4 mid_color : source_color = vec4(0.059, 0.098, 0.196, 1.0);
// 最亮处（原图的青色高光）—— 描边 / 高光色
uniform vec4 light_color : source_color = vec4(0.310, 0.722, 1.0, 1.0);

// 0 = 完全保留原图颜色，1 = 完全换成上面三段色
uniform float amount : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec4 src = texture(TEXTURE, UV);
	vec4 vcol = COLOR;

	// 感知亮度（人眼对绿最敏感，所以不是简单取平均）
	float lum = dot(src.rgb, vec3(0.299, 0.587, 0.114));
	float t = clamp((lum - lum_low) / max(lum_high - lum_low, 0.001), 0.0, 1.0);

	float a = clamp(t / max(mid_point, 0.001), 0.0, 1.0);
	vec3 ramp = mix(dark_color.rgb, mid_color.rgb, a);
	float b = clamp((t - mid_point) / max(1.0 - mid_point, 0.001), 0.0, 1.0);
	ramp = mix(ramp, light_color.rgb, b);

	COLOR = vec4(mix(src.rgb, ramp, amount), src.a * vcol.a);
}
