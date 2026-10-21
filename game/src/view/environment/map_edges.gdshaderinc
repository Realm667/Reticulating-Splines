uniform bool map_strata_enabled = false;
uniform float map_edge_size = 128.0;
uniform sampler2D map_edge_profile : filter_nearest, repeat_disable;
uniform mat3 edge_canvas_to_grid = mat3(1.0);
varying vec2 edge_grid;

float edge_layer_hash(float layer) {
	return fract(sin(layer * 127.1 + 311.7) * 43758.5453);
}

float edge_layer_boundary(float layer) {
	// Adjacent boundaries remain ordered, but their spacing varies from 3 to
	// 21 logical pixels. Absolute layer IDs avoid a repeating stripe sequence.
	return layer * 12.0 + (edge_layer_hash(layer) - 0.5) * 9.0;
}

bool map_edge_slope(float mask, float elevation) {
	if (!map_strata_enabled || elevation < 0.0 || mask < 0.67 || mask > 0.83) { return false; }
	// Restore the base-height grid coordinate of this vertical face. An outer
	// slope spans 0.75 tiles above its base; the next inland face is one tile
	// behind it. Directional material tags keep the opposite face untouched.
	float face = (mask < 0.75 ? edge_grid.x : edge_grid.y) + elevation * 0.75;
	return face > map_edge_size - 1.375 && face < map_edge_size - 0.375;
}

float edge_surface(float along, float face) {
	// Cubic reconstruction keeps the smoothed diagonal profile continuous between
	// tiles, without turning each individual tile into a flat horizontal terrace.
	float position = along - 0.5;
	float index = floor(position);
	float t = fract(position);
	float a = texture(map_edge_profile, vec2((index - 0.5) / map_edge_size, face)).a;
	float b = texture(map_edge_profile, vec2((index + 0.5) / map_edge_size, face)).a;
	float c = texture(map_edge_profile, vec2((index + 1.5) / map_edge_size, face)).a;
	float d = texture(map_edge_profile, vec2((index + 2.5) / map_edge_size, face)).a;
	return 31.0 * (b + 0.5 * t * (c - a + t * (2.0 * a - 5.0 * b + 4.0 * c - d + t * (3.0 * (b - c) + d - a))));
}

float map_edge_coverage(float mask) {
	if (!map_strata_enabled || mask <= 0.35 || mask >= 0.45) { return 1.0; }
	// Trim the authored jagged bottom one logical pixel inside the common
	// altitude-zero boundary. Coverage is one screen pixel wide at any zoom;
	// the existing projection joins both faces without per-tile seams.
	float rise = map_edge_size - 0.5 - max(edge_grid.x, edge_grid.y);
	float width = max(fwidth(rise), 0.00001);
	return clamp((rise - 1.0 / 16.0) / width + 0.5, 0.0, 1.0);
}

vec4 map_edge_color(vec3 original, float mask) {
	bool soil = mask > 0.35 && mask < 0.45;
	bool water = mask > 0.2 && mask < 0.3;
	if ((!soil || !map_strata_enabled) && (!water || !water_depth_enabled)) { return vec4(original, mask); }
	// Inverse isometric projection of a vertical face. One altitude level
	// displaces both grid coordinates by 12 / 16. This also works at the corner.
	float rise = map_edge_size - 0.5 - max(edge_grid.x, edge_grid.y);
	float altitude = rise / 0.75;
	float along = min(edge_grid.x, edge_grid.y) + rise + 0.5;
	bool right_face = edge_grid.x >= edge_grid.y;
	vec3 profile = texture(map_edge_profile, vec2(along / map_edge_size, right_face ? 0.25 : 0.75)).rgb;
	float land = round(profile.r * 31.0);
	float surface = edge_surface(along, right_face ? 0.25 : 0.75);
	float level = round(profile.g * 31.0);
	// Sprite silhouettes extend a fraction of a logical pixel beyond the
	// ideal wall. Grade those boundary texels too, instead of leaking blue.
	vec3 fallback = water ? water_depth_color(original, 0.0, 0.0) : original;
	if (altitude < -0.15 || altitude > 32.1 || along < 0.0 || along > map_edge_size) { return vec4(fallback, mask); }
	// Land and water sprites are stacked at integer tile heights. Reclassify
	// their shared wall with the same continuous profile as the strata, so
	// the material boundary cannot cut vertical steps through curved layers.
	if (map_strata_enabled && water_depth_enabled && profile.b > 0.5) {
		soil = altitude <= surface;
		land = surface;
		mask = soil ? 0.4 : 0.25;
		// Procedural grading must not retain the different brightness of the
		// original land/water artwork at the now invisible sprite boundary.
		original = environment_lut_linear_canvas ? lut_linear(vec3(0.4)) : vec3(0.4);
	}
	vec3 color;
	if (soil) {
		float below_surface = (surface - altitude) * 12.0;
		// Fixed low-frequency variation: no animation or simulation RNG. Distance
		// from the common corner keeps both faces joined at the same layer phase.
		float distance = map_edge_size - along;
		float warp = sin(distance * 0.37 + sin(distance * 0.11) * 1.7) * 1.25;
		warp += sin(distance * 0.17 + below_surface * 0.035) * 0.6;
		float depth = below_surface + warp;
		float layer = floor(depth / 12.0);
		if (depth < edge_layer_boundary(layer)) { layer -= 1.0; }
		else if (depth >= edge_layer_boundary(layer + 1.0)) { layer += 1.0; }
		float stone = edge_layer_hash(layer + 97.0);
		color = mix(vec3(0.36, 0.29, 0.23), vec3(0.64, 0.58, 0.43), stone);
		// Occasional grey or pale deposits break up the brown sequence without
		// introducing a fixed colour order or changing any simulation state.
		if (stone < 0.16) { color = vec3(0.38, 0.37, 0.32); }
		else if (stone > 0.88) { color = vec3(0.68, 0.63, 0.49); }
		float grain = fract(sin(dot(floor(vec2(along * 16.0, altitude * 12.0)), vec2(12.9898, 78.233))) * 43758.5453);
		color *= 0.96 + grain * 0.08;
	} else {
		// Do not treat inland waterfalls as the exposed map boundary.
		if (profile.b < 0.5 || altitude < land - 0.15 || altitude > level + 0.15) { return vec4(fallback, mask); }
		float depth = max(level - altitude, 0.0);
		vec3 graded = water_depth_color(original, depth, 3.0);
		color = environment_lut_linear_canvas ? lut_srgb(graded) : graded;
		color *= 0.78 + 0.22 * exp(-depth * 0.4);
		color = mix(color, vec3(0.36, 0.59, 0.66), (1.0 - smoothstep(0.0, 0.13, depth)) * 0.3);
	}
	color *= right_face ? 0.88 : 1.0;
	return vec4(environment_lut_linear_canvas ? lut_linear(color) : color, mask);
}
