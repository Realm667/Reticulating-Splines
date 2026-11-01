shader_type canvas_item;
render_mode unshaded;

// Per-draw vertex color carries grayscale, softness, unused, opacity.
varying vec4 snapshot_style;

void vertex() {
	snapshot_style = COLOR;
}

vec4 premultiplied(vec4 color) {
	return vec4(color.rgb * color.a, color.a);
}

void fragment() {
	vec2 step_uv = TEXTURE_PIXEL_SIZE * 0.75;
	vec4 center = premultiplied(texture(TEXTURE, UV));
	vec4 soft = center * 4.0;
	soft += (premultiplied(texture(TEXTURE, UV + vec2(step_uv.x, 0.0)))
		+ premultiplied(texture(TEXTURE, UV - vec2(step_uv.x, 0.0)))
		+ premultiplied(texture(TEXTURE, UV + vec2(0.0, step_uv.y)))
		+ premultiplied(texture(TEXTURE, UV - vec2(0.0, step_uv.y)))) * 2.0;
	soft += premultiplied(texture(TEXTURE, UV + step_uv)) + premultiplied(texture(TEXTURE, UV - step_uv))
		+ premultiplied(texture(TEXTURE, UV + vec2(step_uv.x, -step_uv.y)))
		+ premultiplied(texture(TEXTURE, UV + vec2(-step_uv.x, step_uv.y)));
	vec4 color = mix(center, soft / 16.0, snapshot_style.g);
	vec3 rgb = color.a > 0.00001 ? color.rgb / color.a : vec3(0.0);
	float gray = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
	COLOR = vec4(mix(rgb, vec3(gray), snapshot_style.r), color.a * snapshot_style.a);
}
