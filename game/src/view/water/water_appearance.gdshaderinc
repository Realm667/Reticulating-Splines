// All patterns use map pixels, never screen or region coordinates.
float water_hash(vec2 cell) {
	return fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
}

float water_field(vec2 world) {
	vec2 cell = floor(world / 96.0);
	vec2 blend = smoothstep(vec2(0.0), vec2(1.0), fract(world / 96.0));
	float a = mix(water_hash(cell), water_hash(cell + vec2(1.0, 0.0)), blend.x);
	float b = mix(water_hash(cell + vec2(0.0, 1.0)), water_hash(cell + vec2(1.0)), blend.x);
	// Continuous low-frequency variation avoids visible polygon-like color bands.
	return mix(a, b, blend.y) - 0.5;
}

// Value noise and its analytic gradient. Three drifting scales avoid the
// repeating lattice of a few interfering sine waves, without extra texture taps.
vec3 water_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	vec2 du = 6.0 * f * (1.0 - f);
	float a = water_hash(cell);
	float b = water_hash(cell + vec2(1.0, 0.0));
	float c = water_hash(cell + vec2(0.0, 1.0));
	float d = water_hash(cell + vec2(1.0));
	return vec3(mix(mix(a, b, u.x), mix(c, d, u.x), u.y),
	 du.x * mix(b - a, d - c, u.y), du.y * mix(c - a, d - b, u.x));
}

// Lighting and reflected silhouettes use the same moving surface gradient.
vec3 water_swell(vec2 world, float clock, float rain, float coast, float axis) {
	clock *= 1.65;
	vec2 plane = vec2(world.x, world.y * 2.0);
	vec3 broad = water_noise(plane * 0.025 + vec2(clock * 0.055, clock * 0.035));
	vec3 small = water_noise(plane * 0.067 + vec2(-clock * 0.095, clock * 0.065) + vec2(19.3, 7.1));
	vec3 fine = water_noise(plane * 0.16 + vec2(clock * 0.13, -clock * 0.10) + vec2(3.7, 31.8));
	float detail = 1.0 - smoothstep(2.0, 8.0, length(fwidth(world)));
	vec2 normal = broad.yz * 0.48 + small.yz * 0.34 + fine.yz * 0.18 * detail;
	float exposure = mix(0.55, 1.0, smoothstep(2.0, 24.0, coast)) * (axis > 0.0 ? 0.65 : 1.0);
	float glint = smoothstep(0.25, 0.65, dot(normal, vec2(0.6, -0.8))) * detail;
	float light = dot(normal, vec2(-0.6, 0.8)) * 0.12 + glint * 0.055;
	return vec3(light, normal.x * 6.0, glint) * exposure * (1.0 + rain * 0.35);
}

float water_surf(vec2 world, float coast, float clock, float rain) {
	// Advancing crests travel toward the shore, then fade on the same contour.
	// Distance is from terrain only; object silhouettes cannot produce surf.
	float phase = coast * 0.53 + clock * 1.35 + 0.18 * sin(world.x * 0.027 + world.y * 0.039);
	float crest = smoothstep(0.68, 0.98, sin(phase));
	float broken = smoothstep(-0.65, 0.6, sin(world.x * 0.19 + world.y * 0.23 + sin(clock * 0.37)));
	float wash = (1.0 - smoothstep(1.5, 5.0, coast)) * (0.5 + 0.5 * sin(phase - 0.6));
	float band = smoothstep(0.3, 2.0, coast) * (1.0 - smoothstep(12.0, 24.0, coast));
	return (crest * broken * band * 0.24 + wash * 0.055) * (1.0 + rain * 0.25);
}

// The same optical transmission is used on top and falling water. Falling
// faces blend this substrate over their existing palette/frame animation.
vec4 water_substrate(vec4 bottom, float depth, vec2 world) {
	float transmission = 0.42 * exp(-depth * 0.48) * bottom.a;
	float grain = water_field(world * 3.0) * 0.04;
	float face = 0.48 + 0.64 * bottom.g;
	vec3 substrate = mix(vec3(0.40, 0.36, 0.25), vec3(0.28, 0.37, 0.39), clamp(depth / 6.0, 0.0, 1.0));
	return vec4(substrate * (face + grain), transmission);
}

vec3 water_body(vec3 original, vec4 bottom, float depth, vec2 world, bool show_bottom) {
	float shallows = exp(-depth * 0.55) * bottom.a;
	vec3 color = water_body_tone(original, shallows, water_field(world));
	if (show_bottom) {
		vec4 substrate = water_substrate(bottom, depth, world);
		color = mix(color, substrate.rgb, substrate.a);
	}
	return color;
}
