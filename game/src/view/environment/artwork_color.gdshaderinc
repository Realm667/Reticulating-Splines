// Applied only to indexed base artwork, before authored enhancement colors.
// Emission masks subsequently restore their original light colors.
uniform float artwork_color_strength : hint_range(0.0, 1.0) = 0.0;

vec3 artwork_color(vec3 original) {
	if (artwork_color_strength <= 0.0) { return original; }
	vec3 color = environment_lut_linear_canvas ? lut_srgb(original) : original;
	float luminance = dot(color, vec3(0.2126, 0.7152, 0.0722));
	vec3 restrained = mix(vec3(luminance), color, 0.40);
	vec3 result = mix(color, restrained, artwork_color_strength);
	return environment_lut_linear_canvas ? lut_linear(result) : result;
}
