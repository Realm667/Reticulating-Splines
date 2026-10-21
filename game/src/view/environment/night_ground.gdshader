shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;
uniform float strength = 0.0;
uniform float edge_softness = 0.0;
uniform float fade_clock = -1.0;
uniform float fade_duration = 1.0;
varying float light_birth;
void vertex() {
	light_birth = COLOR.r;
}
void fragment() {
	vec4 light = texture(TEXTURE, UV);
	// Inward feathering keeps the occlusion mask authoritative: no light is
	// added to a fully hidden pixel or to adjacent grass/building surfaces.
	if (edge_softness > 0.0 && light.a > 0.0) {
		vec2 step_uv = TEXTURE_PIXEL_SIZE * edge_softness;
		float coverage = light.a * 4.0;
		coverage += texture(TEXTURE, UV + vec2(step_uv.x, 0.0)).a;
		coverage += texture(TEXTURE, UV - vec2(step_uv.x, 0.0)).a;
		coverage += texture(TEXTURE, UV + vec2(0.0, step_uv.y)).a;
		coverage += texture(TEXTURE, UV - vec2(0.0, step_uv.y)).a;
		light.a = min(light.a, coverage / 8.0);
	}
	float fade = fade_clock < 0.0 ? 1.0 : smoothstep(0.0, fade_duration, fade_clock - light_birth);
	COLOR = vec4(light.rgb * light.a * strength * fade, 0.0);
}
