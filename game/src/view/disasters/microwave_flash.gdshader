shader_type canvas_item;
render_mode unshaded;

uniform sampler2D city_screen : hint_screen_texture, filter_nearest, repeat_disable;
uniform float amount = 0.0;

void fragment() {
	vec3 scene = texture(city_screen, SCREEN_UV).rgb;
	vec3 cold = scene * (vec3(1.0) + amount * vec3(-0.06, 0.015, 0.08));
	vec3 exposure = (vec3(1.0) - cold) * vec3(0.24, 0.55, 1.0) * amount * 0.20;
	COLOR = vec4(clamp(cold + exposure, vec3(0.0), vec3(1.0)), 1.0);
}
