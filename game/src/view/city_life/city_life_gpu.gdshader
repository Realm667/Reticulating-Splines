shader_type canvas_item;
render_mode unshaded;
#include "res://src/view/environment/environment_color.gdshaderinc"
#include "res://src/view/clouds/cloud_field.gdshaderinc"
uniform sampler2D artwork : source_color, filter_nearest, repeat_disable;
uniform sampler2D lamps : source_color, filter_nearest, repeat_disable;
uniform sampler2D parameters : filter_nearest, repeat_disable;
uniform sampler2DArray masks : filter_nearest, repeat_disable;
uniform sampler2DArray masks_second : filter_nearest, repeat_disable;
uniform sampler2DArray masks_third : filter_nearest, repeat_disable;
uniform float interpolation = 1.0;
uniform bool smooth_movement = true;
uniform float artwork_scale = 1.0;
uniform bool emission_only = false;
uniform bool vehicle_has_emission = false;
varying flat float mask_layer;
varying vec2 sprite_pixel;
varying flat vec4 source_rect;
varying vec2 world_pixel;
varying vec2 cloud_ground_grid;
varying flat vec2 mask_origin;
varying flat float opacity;
varying flat float road_shear;
void vertex() {
	float slot = float(INSTANCE_ID);
	vec4 rect = texelFetch(parameters, ivec2(int(slot), 0), 0);
	vec4 world = texelFetch(parameters, ivec2(int(slot), 1), 0);
	vec4 mask = texelFetch(parameters, ivec2(int(slot), 2), 0);
	road_shear = texelFetch(parameters, ivec2(int(slot), 3), 0).x;
	vec2 shift = smooth_movement ? world.zw * (1.0 - interpolation) : round(world.xy) - world.xy;
	// Extend the lower/right raster edge by one texel. The fragment clips it;
	// half-scale pixel centers on that edge must still sample the last texel.
	vec2 logical_size = rect.zw / artwork_scale;
	VERTEX = (VERTEX * (logical_size + vec2(1.0)) + shift) / logical_size;
	// QuadMesh vertical UVs run opposite to image rows.
	vec2 sprite_uv = vec2(UV.x, 1.0 - UV.y);
	world_pixel = world.xy + shift + sprite_uv * (logical_size + vec2(1.0));
	source_rect = rect;
	sprite_pixel = sprite_uv * (logical_size + vec2(1.0));
	float incline = road_shear * (sprite_pixel.x - floor(logical_size.x * 0.5));
	VERTEX.y += incline / logical_size.y;
	world_pixel.y += incline;
	mask_origin = mask.xy;
	mask_layer = mask.z;
	opacity = mask.w;
	cloud_ground_grid = cloud_grid_at((MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy);
}
float mask_coverage(vec2 uv) {
	vec3 point = vec3(uv, mod(mask_layer, 256.0));
	if (mask_layer < 256.0) return texture(masks, point).r;
	if (mask_layer < 512.0) return texture(masks_second, point).r;
	return texture(masks_third, point).r;
}
void fragment() {
	// Match image-rectangle sampling at exact half-resolution texel boundaries.
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec2 pixel = floor(sprite_pixel * artwork_scale - vec2(0.0001));
#else
	// Vulkan nearest sampling resolves an exact half-size boundary toward
	// the next texel. Stabilize interpolated integers on that same side.
	vec2 pixel = floor(sprite_pixel * artwork_scale + vec2(0.0001));
#endif
	if (any(lessThan(pixel, vec2(0.0))) || any(greaterThanEqual(pixel, source_rect.zw))) discard;
	vec2 source_uv = (source_rect.xy + pixel + vec2(0.5)) / vec2(textureSize(artwork, 0));
	vec4 color = texture(artwork, source_uv);
	if (color.a <= 0.0) discard;
	vec2 raster_pixel = floor(pixel / artwork_scale);
	// Masks remain in world space after the sprite and its lamp pixels tilt.
	vec2 mask_pixel = world_pixel - sprite_pixel + raster_pixel;
	mask_pixel.y += road_shear * (raster_pixel.x - sprite_pixel.x);
	vec2 mask_uv = (mask_pixel - mask_origin + vec2(0.5)) / 128.0;
	if (all(greaterThanEqual(mask_uv, vec2(0.0))) && all(lessThan(mask_uv, vec2(1.0))) && mask_coverage(mask_uv) > 0.0) discard;
	vec4 light = texture(lamps, source_uv);
	if (emission_only) {
		// Preserve the original emission pass: unlit opaque art covers rear lights.
		COLOR = vec4(light.rgb * light.a * opacity, color.a * opacity);
	} else {
		vec3 shaded = environment_color(cloud_shadow(color.rgb, cloud_ground_grid), source_uv);
		if (vehicle_has_emission && environment_enabled) shaded = mix(shaded, light.rgb, light.a * environment_night);
		COLOR = vec4(shaded, color.a * opacity);
	}
}
