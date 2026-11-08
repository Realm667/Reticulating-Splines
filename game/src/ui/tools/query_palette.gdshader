shader_type canvas_item;
render_mode unshaded;
uniform sampler2D foreground_palette : source_color, filter_nearest, repeat_disable;
varying vec4 preview_tint;
void vertex() {
	preview_tint = COLOR;
}
void fragment() {
	vec4 encoded = texture(TEXTURE, UV);
	vec3 color = texture(foreground_palette, vec2((round(encoded.r * 255.0) + 0.5) / 256.0, 0.5)).rgb;
	COLOR = vec4(color, encoded.a) * preview_tint;
}
