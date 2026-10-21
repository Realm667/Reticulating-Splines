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
	float falloff = 1.0 - smoothstep(0.0, reach, distance_to_center);
	COLOR = vec4(glow_color.rgb, strength * falloff * falloff);
}
