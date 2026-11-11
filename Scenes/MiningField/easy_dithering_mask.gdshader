shader_type canvas_item;

// The texture to receive the effect.
uniform sampler2D screen_texture: hint_screen_texture, filter_linear_mipmap, repeat_enable;
// Defines an additional color that should be turned transparent.
uniform vec4 transparent_color: source_color = vec4(0.0);
// Defines the distance theshold for the transparent color.
uniform float transparent_color_threshold: hint_range(0.0, 1.0) = 0.0;
// Defines the origin point of the zoom effect relative to the texture size.
uniform vec2 zoom_center = vec2(0.5, 0.5);
// Adjusts the number of times the texture should get mirrored.
uniform int layers = 5;
// Adjusts the alpha/transparency of each layer relative to the last.
uniform float opacity = 0.5;
// Adjusts the boost given to the colors of the input texture.
uniform float original_opacity_mod: hint_range(0.0, 1.0) = 0.0;
// Adjusts the magnification of each layer relative to the last.
uniform float zoom = 0.25;
// Range between 0 and 1 of how much to use a normalized vector from the zoom origin.
uniform float normalization: hint_range(0.0, 1.0) = 1.0;
// Range between -1 and 1 of how much to zoom the normalized vector relative to the texture size.
uniform float normalized_scale: hint_range(-1.0, 1.0) = 0.01;

uniform float color_cycle_time = 6.0;
uniform lowp vec4 colors[6]: source_color;
uniform float color_layer_gap: hint_range(0.0, 1.0) = 0.0;

// Adjust UV per new scale and pivot
vec2 adj_uv(vec2 a_uv, float a_scale, vec2 a_pivot){
	return a_pivot + (a_uv - a_pivot) * pow(a_scale, -1.0);
}

void fragment() {
	vec4 original_color = texture(screen_texture, UV);
	float transparent_color_distance = distance(original_color, transparent_color) / 2.0;
	original_color.a = mix(0.0, original_color.a, float(transparent_color_distance > transparent_color_threshold));
	COLOR = original_color;
	float time = mod(TIME, color_cycle_time);
	float time_ratio = time / color_cycle_time;
	float color_ratio = 1.0 / float(colors.length());
	for (int iter = 1; iter < layers + 1; iter++){
		float f_index = mod(time_ratio - (color_layer_gap * float(iter)), 1.0) / color_ratio;
		float f_remainder = mod(f_index, 1.0);
		vec4 prior_color = colors[int(floor(f_index))];
		vec4 next_color;
		next_color = colors[int(ceil(f_index))];
		if (int(ceil(f_index)) < colors.length()){
			next_color = colors[int(ceil(f_index))];
		} else {
			next_color = colors[0];
		}
		vec2 adjusted_uv = adj_uv(UV, 1.0 + (zoom * float(iter)), zoom_center);
		vec2 adjusted_vector = adjusted_uv - UV;
		vec2 zoom_vector = (zoom_center - UV);
		vec2 normalized_vector = normalize(zoom_vector) * float(iter) * normalized_scale;
		zoom_vector = mix(adjusted_vector, normalized_vector, normalization);
		vec4 sample_color = texture(screen_texture, zoom_vector + UV);
		float transparent_color_distance = distance(sample_color, transparent_color) / 2.0;
		sample_color.a = mix(0.0, sample_color.a, float(transparent_color_distance > transparent_color_threshold));
		sample_color = sample_color * mix(prior_color, next_color, f_remainder);
		float opacity_mod = 1.0 - (original_color.a * original_opacity_mod);
		COLOR = mix(COLOR, sample_color, sample_color.a * pow(opacity, float(iter)) * opacity_mod);
	}
}
