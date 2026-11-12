shader_type canvas_item;
render_mode unshaded;

uniform sampler2D city_screen : hint_screen_texture, filter_nearest, repeat_disable;
uniform vec2 canvas_size = vec2(1.0);
uniform vec2 glow_center = vec2(0.0);
// Numeric sRGB colors, also used on linear HDR canvases below.
uniform vec4 glow_color = vec4(1.0);
uniform vec4 core_color = vec4(1.0);
uniform float core_factor = 1.0;
uniform bool linear_canvas = false;
uniform float strength = 0.0;
uniform float radius = 0.9;

vec3 to_srgb(vec3 c) {
	return mix(c * 12.92, 1.055 * pow(max(c, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void fragment() {
	vec2 center = glow_center + vec2(glow_center.x < 0.5 ? -0.045 : 0.045, 0.0);
	vec2 d = (UV - center) * canvas_size / max(1.0, min(canvas_size.x, canvas_size.y));
	d *= 0.679 * 0.9 / max(radius, 0.01);
	float distance_to_center = length(d);
	vec2 veil_pos = d / vec2(0.52, 0.35);
	vec2 core_pos = d / vec2(0.13, 0.16);
	float veil = exp(-dot(veil_pos, veil_pos) * 1.45);
	float core = exp(-dot(core_pos, core_pos) * 1.7);
	float angle = atan(-d.y, max(abs(d.x), 0.001));
	float rays = 0.0;
	for (int i = 0; i < 4; i++) {
		float fi = float(i);
		float axis = -0.70 + fi * 0.42;
		float offset = (angle - axis) / (0.075 + fi * 0.018);
		rays += exp(-offset * offset) * exp(-distance_to_center * (2.0 + fi * 0.28)) * smoothstep(0.04, 0.20, distance_to_center);
	}
	vec3 light = glow_color.rgb * (veil * 0.32 + rays * 0.055) + core_color.rgb * core * 0.30 * core_factor;
	// Existing 25% per-event brightness with 100% intensity matches the preview.
	light = clamp(light * strength * 4.0, vec3(0.0), vec3(0.85));
	vec3 sampled = texture(city_screen, SCREEN_UV).rgb;
	vec3 base = linear_canvas ? to_srgb(sampled) : sampled;
	float luminance = dot(base, vec3(0.2126, 0.7152, 0.0722));
	float protection = 1.0 - 0.88 * smoothstep(0.32, 0.94, luminance);
	vec3 result = base + max(vec3(0.0), vec3(1.0) - base) * light * protection;
	COLOR = vec4(linear_canvas ? to_linear(result) : result, 1.0);
}
