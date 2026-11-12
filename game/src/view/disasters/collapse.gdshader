shader_type canvas_item;
render_mode unshaded;
#include "res://src/view/environment/environment_color.gdshaderinc"

uniform sampler2D artwork : source_color, filter_nearest, repeat_disable;
uniform sampler2D foreground : filter_nearest, repeat_disable;
uniform bool has_foreground = false;
uniform vec2 extent;
uniform vec2 art_size;
uniform vec2 art_origin;
uniform vec2 ground;
uniform float footprint = 1.0;
uniform float age = 0.0;
uniform float seed = 0.0;
uniform int kind = 0;
uniform bool water = false;
uniform bool violent = false;
uniform bool motion = true;
uniform float strength = 1.0;

vec4 over(vec4 a, vec4 b) {
	float alpha = b.a + a.a * (1.0 - b.a);
	return vec4((b.rgb * b.a + a.rgb * a.a * (1.0 - b.a)) / max(alpha, 0.00001), alpha);
}
vec4 art(vec2 p) {
	if (p.x < 0.0 || p.y < 0.0 || p.x >= art_size.x || p.y >= art_size.y) { return vec4(0.0); }
	return texture(artwork, p / art_size);
}
void fragment() {
	vec2 p = UV * extent;
	float collapse = smoothstep(0.12, kind == 2 ? 0.65 : 0.42, age);
	float sink = kind == 0 || !motion ? 0.0 : collapse * min(art_size.y * 0.22, kind == 2 ? 28.0 : 10.0);
	vec2 source = p - art_origin - vec2(0.0, floor(sink));
	vec4 ink = art(source);
	// Clip at the two front 2:1 edges; do not squeeze or distort the old sprite.
	float front = art_origin.y + art_size.y - abs(p.x - art_origin.x - art_size.x * 0.5) * 0.5;
	if (kind > 0 && p.y > front) { ink.a = 0.0; }
	ink.a *= 1.0 - smoothstep(kind == 0 ? 0.08 : 0.24, kind == 2 ? 0.66 : 0.44, age);
	vec2 q = p - ground;
	float f = clamp(age / (kind == 2 ? 2.2 : 1.1), 0.0, 1.0);
	float dust = smoothstep(0.0, 0.10, age) * (1.0 - smoothstep(0.28, 1.0, f)) * strength;
	float spread = min(footprint, 4.0);
	float growth = kind == 2 ? clamp(age / 0.7, 0.0, 1.0) : f;
	float rise = kind == 2 ? min(art_size.y * 0.38, 64.0) : 18.0;
	for (int i = 0; i < 7; i++) {
		float id = float(i), angle = id * 2.4 + seed;
		vec2 center = vec2(cos(angle) * (5.0 + growth * 12.0) * spread,
			sin(angle) * 4.0 * spread - growth * (water ? 8.0 : rise) * (0.35 + id * 0.1));
		vec2 radius = vec2(6.0 + growth * 12.0,
			4.0 + growth * (kind == 2 ? min(art_size.y * 0.24, 36.0) : 11.0)) * vec2(sqrt(spread), 1.0);
		float puff = 1.0 - smoothstep(0.30, 1.0, length((q - center) / radius));
		vec3 color = water ? vec3(0.57, 0.72, 0.75) : (violent ? vec3(0.42, 0.39, 0.35) : vec3(0.66, 0.62, 0.53));
		color *= 0.90 + 0.10 * sin(id * 3.0 + q.y * 0.13);
		ink = over(ink, vec4(color, puff * dust * 0.74));
		if (kind == 2 && motion) {
			float flight = clamp((age - 0.12) / 0.65, 0.0, 1.0);
			vec2 at = vec2(cos(angle) * flight * 22.0 * sqrt(spread), sin(angle) * flight * 7.0 - sin(flight * 3.14159) * (12.0 + id * 2.0));
			vec2 chip = floor(q - at);
			vec4 sample_color = art(art_size * vec2(0.2 + mod(id * 0.17, 0.6), 0.3 + mod(id * 0.13, 0.4)) + chip);
			sample_color.a *= step(abs(chip.x), 1.5) * step(abs(chip.y), 1.0) * sin(flight * 3.14159) * strength;
			ink = over(ink, sample_color);
		}
	}
	if (water) {
		float ring = abs(length(q / vec2(1.0, 0.5)) - (5.0 + f * 26.0) * sqrt(spread));
		ink = over(ink, vec4(0.47, 0.66, 0.71, (1.0 - smoothstep(0.4, 1.5, ring)) * dust * 0.3));
	}
	ink.rgb = environment_color(ink.rgb, UV);
	if (violent && kind == 2) { ink.rgb += vec3(0.16, 0.07, 0.015) * (1.0 - smoothstep(0.0, 0.12, age)) * strength; }
	if (has_foreground) { ink.a *= 1.0 - texture(foreground, UV).a; }
	COLOR = ink;
}
