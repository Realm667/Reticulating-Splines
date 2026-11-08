shader_type canvas_item;
render_mode unshaded;

uniform sampler2D city_screen : hint_screen_texture, filter_linear, repeat_disable;
uniform float amount = 0.0;
uniform float clock = 0.0;

void fragment() {
	// Broad shearing bands cross the scene with each gust. The displacement is
	// bounded in physical pixels so close-up views never magnify the distortion.
	float wave = sin(UV.y * 14.0 - clock * 8.0) * 0.65
		+ sin((UV.x + UV.y) * 23.0 - clock * 11.0) * 0.35;
	vec2 offset = vec2(wave, wave * 0.18) * SCREEN_PIXEL_SIZE * amount * 3.0;
	vec2 uv = clamp(SCREEN_UV + offset, SCREEN_PIXEL_SIZE, vec2(1.0) - SCREEN_PIXEL_SIZE);
	vec3 center = texture(city_screen, uv).rgb;
	vec3 smear = texture(city_screen, uv - SCREEN_PIXEL_SIZE * vec2(2.5, 0.5)).rgb;
	COLOR = vec4(mix(center, smear, amount * 0.18), 1.0);
}
