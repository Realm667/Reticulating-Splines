shader_type canvas_item;
render_mode unshaded;

uniform sampler2D city_screen : hint_screen_texture, filter_linear, repeat_disable;
uniform float amount = 0.0;
uniform vec2 anchor = vec2(0.5);

void fragment() {
	vec2 extent = SCREEN_PIXEL_SIZE / max(fwidth(UV), vec2(0.000001));
	vec2 lo = SCREEN_UV - UV * extent + SCREEN_PIXEL_SIZE * 0.5;
	vec2 hi = lo + extent - SCREEN_PIXEL_SIZE;
	vec2 center = lo + anchor * (extent - SCREEN_PIXEL_SIZE);
	vec2 pixels = (SCREEN_UV - center) / SCREEN_PIXEL_SIZE * amount;
	// A small physical-pixel cap keeps high-DPI and large views equally subtle.
	pixels *= min(1.0, 2.25 / max(length(pixels), 0.000001));
	vec2 step_uv = pixels * SCREEN_PIXEL_SIZE;
	vec3 color = texture(city_screen, SCREEN_UV).rgb * 0.35;
	color += texture(city_screen, clamp(SCREEN_UV - step_uv, lo, hi)).rgb * 0.125;
	color += texture(city_screen, clamp(SCREEN_UV + step_uv, lo, hi)).rgb * 0.125;
	color += texture(city_screen, clamp(SCREEN_UV - step_uv * 0.5, lo, hi)).rgb * 0.20;
	color += texture(city_screen, clamp(SCREEN_UV + step_uv * 0.5, lo, hi)).rgb * 0.20;
	COLOR = vec4(color, 1.0);
}
