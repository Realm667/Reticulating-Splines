extends "res://tests/support/scene_test_case.gd"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for hdr in [false, true]:
		await _check_artwork(hdr)
		await _check_water(hdr)
		await _check_strata(hdr)
		await _check_strata_water_join(hdr)
	for spec in [[1.0, false, false], [1.5, false, false], [4.0, false, false], [4.0, true, true]]:
		await _check_strata_bottom(spec[0], spec[1], spec[2])
	print("PASS: artwork preserves effects and emission, depth water, terrain-following strata and disabled fallbacks in SDR/HDR")
	quit()


func _check_artwork(hdr: bool) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(96, 16)
	viewport.use_hdr_2d = hdr
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var pixels := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	pixels.fill(Color(1, 0.1, 0.05, 1))
	var material := ShaderMaterial.new()
	material.shader = load("res://src/view/map/palette_cycle.gdshader")
	material.set_shader_parameter("environment_lut_linear_canvas", hdr)
	material.set_shader_parameter("environment_enabled", true)
	material.set_shader_parameter("environment_night", 1.0)
	var marks := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	marks.fill(Color(0, 0, 1, 1))
	var materials: Array[ShaderMaterial] = []
	for index in 6:
		var sprite := Polygon2D.new()
		sprite.polygon = PackedVector2Array([Vector2.ZERO, Vector2(16, 0), Vector2(16, 16), Vector2(0, 16)])
		sprite.position.x = index * 16
		sprite.texture = ImageTexture.create_from_image(pixels)
		var shader := material.duplicate() as ShaderMaterial
		if index == 1:
			sprite.color = Color(0, 1, 1, 1) # Added emission layer.
		elif index == 2:
			sprite.color = Color(2.0 / 255.0, 0, 0, 1) # Full-color enhancement artwork.
		elif index == 3:
			shader.set_shader_parameter("environment_has_emission", true)
			shader.set_shader_parameter("environment_emission", ImageTexture.create_from_image(marks))
		elif index == 4:
			sprite.color = Color(1, 1, 0, 1) # Fullbright overlay.
		elif index == 5:
			var nature := Image.create(16, 16, false, Image.FORMAT_RGBA8)
			nature.fill(Color(1, 0.2, 0, 1))
			shader.set_shader_parameter("environment_has_seasons", true)
			shader.set_shader_parameter("environment_season_mask", ImageTexture.create_from_image(nature))
			shader.set_shader_parameter("nature_forests_enabled", true)
		sprite.material = shader
		materials.append(shader)
		viewport.add_child(sprite)
	await process_frame
	await RenderingServer.frame_post_draw
	var original := viewport.get_texture().get_image()
	for shader in materials:
		shader.set_shader_parameter("artwork_color_strength", 1.0)
	await RenderingServer.frame_post_draw
	var reduced := viewport.get_texture().get_image()
	var a := original.get_pixel(8, 8)
	var b := reduced.get_pixel(8, 8)
	assert(b.r - b.g < (a.r - a.g) * 0.8, "Original artwork must become less saturated")
	for index in range(1, 6):
		assert(original.get_region(Rect2i(index * 16, 0, 16, 16)).get_data() == reduced.get_region(Rect2i(index * 16, 0, 16, 16)).get_data(),
			"Color filter altered enhancement or light layer %d" % index)
	viewport.queue_free()
	await process_frame


func _check_strata(hdr: bool) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(128, 64)
	viewport.use_hdr_2d = hdr
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var shader := Shader.new()
	shader.code = 'shader_type canvas_item;\n#include "res://src/view/environment/environment_color.gdshaderinc"\n#include "res://src/view/water/water_color.gdshaderinc"\n#include "res://src/view/environment/map_edges.gdshaderinc"\nvoid vertex() { float rise = (10.0 - UV.y * 4.0) * 0.75; edge_grid = vec2(15.5 - rise, UV.x * 15.0 - rise); }\nvoid fragment() { COLOR = vec4(map_edge_color(vec3(0.4), 0.4).rgb, 1.0); }'
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("map_strata_enabled", true)
	material.set_shader_parameter("map_edge_size", 16.0)
	material.set_shader_parameter("environment_lut_linear_canvas", hdr)
	var profile := Image.create(16, 2, false, Image.FORMAT_RGBAF)
	profile.fill(Color(10.0 / 31.0, 0, 0, 10.0 / 31.0))
	var texture := ImageTexture.create_from_image(profile)
	material.set_shader_parameter("map_edge_profile", texture)
	var rect := ColorRect.new()
	rect.size = Vector2(128, 64)
	rect.material = material
	viewport.add_child(rect)
	await process_frame
	await RenderingServer.frame_post_draw
	var flat := viewport.get_texture().get_image()
	for x in 16:
		for y in 2:
			profile.set_pixel(x, y, Color(10.0 / 31.0, 0, 0, (10.0 + x * 0.5) / 31.0))
	texture.update(profile)
	await RenderingServer.frame_post_draw
	var sloped := viewport.get_texture().get_image()
	var changed := 0
	for x in 128:
		if flat.get_pixel(x, 32) != sloped.get_pixel(x, 32):
			changed += 1
	assert(changed > 64, "Strata must bend with the surface profile instead of staying horizontal")
	await RenderingServer.frame_post_draw
	assert(viewport.get_texture().get_image().get_data() == sloped.get_data(), "Geological variation must not animate")
	material.set_shader_parameter("map_strata_enabled", false)
	await RenderingServer.frame_post_draw
	var disabled := viewport.get_texture().get_image()
	assert(disabled.get_pixel(16, 16) == disabled.get_pixel(112, 48), "Disabled strata restore the authored flat face")
	viewport.queue_free()
	await process_frame


func _check_water(hdr: bool) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(64, 16)
	viewport.use_hdr_2d = hdr
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var shader := Shader.new()
	shader.code = 'shader_type canvas_item;\n#include "res://src/view/environment/environment_color.gdshaderinc"\n#include "res://src/view/water/water_color.gdshaderinc"\nvoid fragment() { COLOR = vec4(water_depth_color(vec3(0.0, 0.0, 1.0), UV.x < 0.5 ? 1.0 : 12.0, UV.x < 0.5 ? 0.0 : 20.0), 1.0); }'
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("water_depth_enabled", true)
	material.set_shader_parameter("environment_lut_linear_canvas", hdr)
	var rect := ColorRect.new()
	rect.size = Vector2(64, 16)
	rect.material = material
	viewport.add_child(rect)
	await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	assert(image.get_pixel(8, 8).get_luminance() > image.get_pixel(48, 8).get_luminance() + 0.05)
	material.set_shader_parameter("water_depth_enabled", false)
	await RenderingServer.frame_post_draw
	image = viewport.get_texture().get_image()
	assert(image.get_pixel(8, 8) == image.get_pixel(48, 8), "Disabling depth colors restores the same authored color")
	viewport.queue_free()
	await process_frame


func _check_strata_water_join(hdr: bool) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(128, 64)
	viewport.use_hdr_2d = hdr
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var shader := Shader.new()
	shader.code = 'shader_type canvas_item;\n#include "res://src/view/environment/environment_color.gdshaderinc"\n#include "res://src/view/water/water_color.gdshaderinc"\n#include "res://src/view/environment/map_edges.gdshaderinc"\nuniform float marker;\nvoid vertex() { float rise = (10.0 - UV.y * 8.0) * 0.75; edge_grid = vec2(15.5 - rise, UV.x * 15.0 - rise); }\nvoid fragment() { COLOR = vec4(map_edge_color(marker < 0.3 ? vec3(0.1, 0.2, 0.9) : vec3(0.6, 0.3, 0.1), marker).rgb, 1.0); }'
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("map_strata_enabled", true)
	material.set_shader_parameter("water_depth_enabled", true)
	material.set_shader_parameter("map_edge_size", 16.0)
	material.set_shader_parameter("environment_lut_linear_canvas", hdr)
	var profile := Image.create(16, 2, false, Image.FORMAT_RGBAF)
	for x in 16:
		for face in 2:
			var land := 4.0 if x < 8 else 7.0
			profile.set_pixel(x, face, Color(land / 31.0, 12.0 / 31.0, 1, (4.0 + x * 0.2) / 31.0))
	material.set_shader_parameter("map_edge_profile", ImageTexture.create_from_image(profile))
	var rect := ColorRect.new()
	rect.size = viewport.size
	rect.material = material
	viewport.add_child(rect)
	material.set_shader_parameter("marker", 0.4)
	await process_frame
	await RenderingServer.frame_post_draw
	var land_sprite := viewport.get_texture().get_image()
	material.set_shader_parameter("marker", 0.25)
	await RenderingServer.frame_post_draw
	var water_sprite := viewport.get_texture().get_image()
	assert(land_sprite.get_data() == water_sprite.get_data(),
		"The continuous wall profile must cross authored soil/water sprite boundaries without a color seam")
	assert(land_sprite.get_pixel(64, 2) != land_sprite.get_pixel(64, 62),
		"The joined wall must still distinguish water above from sediments below")
	viewport.queue_free()
	await process_frame


func _check_strata_bottom(zoom: float, hd: bool, hdr: bool) -> void:
	# Use the actual jagged sprite contour and the production indexed/artwork
	# shader paths. A corner exposes both faces, including the shared tip.
	var pack := FixtureGraphics.pack()
	var archive := pack.large_sprites
	CitySeasonColors.prepare(archive, pack.palette)
	var entry := archive.find_sprite(1269)
	var pixels: Image = entry.create_image(pack.palette).image
	var viewport := SubViewport.new()
	viewport.size = Vector2i(ceil(32 * zoom), ceil(32 * zoom))
	viewport.transparent_bg = true
	viewport.use_hdr_2d = hdr
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.scale = Vector2.ONE * zoom
	sprite.texture = ImageTexture.create_from_image(pixels)
	if hd:
		sprite.modulate = Color(2.0 / 255.0, 0, 0, 1)
	var material := ShaderMaterial.new()
	material.shader = load("res://src/view/map/palette_cycle.gdshader")
	material.set_shader_parameter("map_edge_size", 16.0)
	material.set_shader_parameter("environment_lut_linear_canvas", hdr)
	material.set_shader_parameter("environment_has_seasons", true)
	material.set_shader_parameter("environment_season_mask", ImageTexture.create_from_image(archive.visual_seasons[1269]))
	material.set_shader_parameter("edge_canvas_to_grid", Basis(
		Vector3(1.0 / (32 * zoom), -1.0 / (32 * zoom), 0),
		Vector3(1.0 / (16 * zoom), 1.0 / (16 * zoom), 0),
		Vector3(15.0625 - entry.height / 16.0, 16.0625 - entry.height / 16.0, 1)))
	var profile := Image.create(16, 2, false, Image.FORMAT_RGBAF)
	profile.fill(Color(4.0 / 31.0, 0, 0, 4.0 / 31.0))
	material.set_shader_parameter("map_edge_profile", ImageTexture.create_from_image(profile))
	sprite.material = material
	viewport.add_child(sprite)
	await process_frame
	await RenderingServer.frame_post_draw
	var original := viewport.get_texture().get_image()
	material.set_shader_parameter("map_strata_enabled", true)
	await RenderingServer.frame_post_draw
	var corrected := viewport.get_texture().get_image()
	var blended := 0
	for x in range(2, viewport.size.x - 2):
		var edge_y := (entry.height - 2.0 - absf((x + 0.5) / zoom - 16.0) * 0.5) * zoom
		for y in range(floori(edge_y) - 2, ceili(edge_y) + 3):
			var alpha := corrected.get_pixel(x, y).a
			var expected := clampf((edge_y - y - 0.5) / 1.5 + 0.5, 0, 1)
			assert(absf(alpha - expected) < 0.06,
				"Strata bottom must follow a continuous antialiased contour: zoom=%s hd=%s point=%s alpha=%s expected=%s" % [zoom, hd, Vector2i(x, y), alpha, expected])
			if alpha > 0.05 and alpha < 0.95:
				blended += 1
	assert(blended > viewport.size.x / 2, "The bottom edge must retain subpixel coverage at integer and fractional zoom")
	material.set_shader_parameter("map_strata_enabled", false)
	await RenderingServer.frame_post_draw
	assert(viewport.get_texture().get_image().get_data() == original.get_data(), "Disabling strata restores the original sprite contour exactly")
	viewport.queue_free()
	await process_frame
