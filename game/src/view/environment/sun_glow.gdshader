shader_type canvas_item;
render_mode unshaded, blend_add;

uniform vec2 canvas_size = vec2(1.0);
uniform vec2 glow_center = vec2(0.0);
uniform vec4 glow_color : source_color = vec4(1.0);
uniform float strength = 0.0;
uniform float radius = 0.9;

void fragment() {
	// A circular, soft radial gradient in screen pixels, independent of zoom.
	float distance_to_center = length((UV - glow_center) * canvas_size);
	float reach = max(1.0, min(canvas_size.x, canvas_size.y) * radius);
	float distance_ratio = distance_to_center / reach;
	float falloff = 1.0 - smoothstep(0.0, 1.0, distance_ratio);
	// White luminous core, colored middle and a broad, feathered outer edge.
	float core = 1.0 - smoothstep(0.0, 0.65, distance_ratio);
	vec3 tint = mix(glow_color.rgb, vec3(1.0), core * core);
	COLOR = vec4(tint, (1.0 - pow(1.0 - clamp(strength, 0.0, 1.0), 4.0)) * falloff * falloff);
}
