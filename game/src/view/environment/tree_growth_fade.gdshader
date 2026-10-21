shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform sampler2D starts : repeat_disable, filter_nearest;
uniform mat3 screen_to_source;
uniform vec2 extent;
uniform float clock;
uniform float duration = 0.85;

void fragment() {
	vec4 previous = textureLod(screen_texture, SCREEN_UV, 0.0);
	if (previous.a > 0.0001) {
		previous.rgb /= previous.a;
	}
	vec2 source = (screen_to_source * vec3(SCREEN_UV / SCREEN_PIXEL_SIZE, 1.0)).xy;
	float start = texture(starts, source / extent).r;
	float opacity = start > 0.0 ? 1.0 - smoothstep(0.0, duration, clock - start) : 0.0;
	COLOR = previous * vec4(1.0, 1.0, 1.0, opacity);
}
