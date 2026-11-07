shader_type canvas_item;
render_mode unshaded, blend_mul;

// Transparent texels must leave the paper unchanged in multiply blending.
void fragment() {
	vec4 ink = texture(TEXTURE, UV);
	COLOR = vec4(mix(vec3(1.0), ink.rgb, ink.a), 1.0);
}
