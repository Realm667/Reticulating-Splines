extends "res://tests/support/scene_test_case.gd"

@warning_ignore_start("integer_division")
## Actual GPU output of the 16-unit path, including numeric LUTs and paged art.

const COMPACT := preload("res://src/view/map/palette_cycle_compact.gdshader")
const PAGED := preload("res://src/view/map/palette_cycle_pages_compact.gdshader")
var tables := CityMapShaderTables.new()
var clock := PaletteAnimationClock.new()
var palette := Sc2Palette.new()
var viewport: SubViewport
var material: ShaderMaterial
var reference: ShaderMaterial
var values: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for shader in [COMPACT, PAGED]:
		var samplers := 0
		for uniform in shader.get_shader_uniform_list():
			if uniform.type == TYPE_OBJECT:
				samplers += 1
		print("MAP_TEXTURE_BUDGET ", shader.resource_path, " custom_samplers=", samplers)
		assert(samplers <= 8, "Godot reserves eight of the sixteen macOS GL texture units; got %d custom samplers" % samplers)
	viewport = SubViewport.new()
	viewport.size = Vector2i(16, 8)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	for index in 256:
		palette.colors.append(Color.from_hsv(float(index) / 256.0, 0.8, 0.8))
	clock.update_textures(palette, 0.0)
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	for y in 8:
		for x in 8:
			image.set_pixel(x, y, Color8(10 + x * 30, 10 + x * 30, 10 + x * 30, 80 + y * 25))
	var source := ImageTexture.create_from_image(image)
	material = ShaderMaterial.new()
	material.shader = COMPACT
	reference = ShaderMaterial.new()
	reference.shader = CityMapConstants.PALETTE_CYCLE_SHADER
	for column in 2:
		var sprite := Sprite2D.new()
		sprite.centered = false
		sprite.position.x = column * 8
		sprite.texture = source
		sprite.material = material if column == 0 else reference
		viewport.add_child(sprite)
	_parameters({"palette_cycle_enabled": true, "palette_lookup_all": true})
	await _compare("Vanilla palette")
	# Palette colors must be resolved, rather than the encoded grey texels.
	var pixel := viewport.get_texture().get_image().get_pixel(0, 7)
	assert(absf(pixel.r - pixel.g) > 0.1)
	var profiles := CityVisualLuts.new()
	profiles.reload("")
	var options := VisualEnhancementOptions.normalize({})
	options.day_lut_strength = 1.0
	options.season_lut_strength = 1.0
	options.weather_lut_strength = 1.0
	profiles.advance_weather(2, 4.0, 4.0, true)
	_parameters(profiles.parameters(options, 7.0, Vector4(0.0, 0.0, 0.0, 1.0)))
	_parameters({"environment_enabled": true})
	await _compare("day/weather LUTs")
	# A different-sized custom LUT checks subrectangle scaling and edge texels.
	var custom := Image.create(4, 2, false, Image.FORMAT_RGB8)
	for y in 2:
		for x in 4:
			custom.set_pixel(x, y, Color(float(x / 2), float(y), float(x % 2)))
	_parameters({"environment_lut": ImageTexture.create_from_image(custom), "environment_lut_size": 2.0})
	await _compare("custom LUT")
	var mask := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	mask.fill(Color(1.0, 0.0, 0.0, 1.0))
	_parameters({"environment_season_mask": ImageTexture.create_from_image(mask), "environment_has_seasons": true})
	await _compare("masked seasons")
	var cover := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	cover.fill(Color.WHITE)
	_parameters({"cloud_enabled": true, "cloud_density": 1.0, "cloud_cover_cached": true,
		"cloud_cover_field": ImageTexture.create_from_image(cover), "cloud_shadow_strength": 0.4})
	await _compare("cached cloud shadows")
	_parameters({"dark_underground": true})
	await _compare("underground palette")
	_parameters({"dark_underground": false, "environment_enabled": false})
	# A palette update must reach existing materials without a new binding.
	var combined := clock.map_palette_texture
	clock.cycle_ticks += 1
	clock.update_textures(palette, 0.5, true, true)
	assert(clock.map_palette_texture == combined)
	await _compare("in-place palette animation")
	# A real array texture selects the paged shader, with all three page samplers.
	var art := Image.create(1024, 1024, false, Image.FORMAT_RGBA8)
	art.blit_rect(image, Rect2i(0, 0, 8, 8), Vector2i.ZERO)
	var pages := CityGpuTexturePages.new()
	assert(pages.publish({"edge": 1024, "indices": [0], "art": [art], "emission": [art], "seasons": [art]}))
	pages.apply(material)
	assert(material.shader == PAGED)
	pages.apply(material)
	assert(material.shader == PAGED, "Reuploading pages must retain the compact shader")
	assert(material.get_shader_parameter("map_palettes") == combined)
	# UVs of the small source are mapped into the page's top-left eight texels.
	var sprite := viewport.get_child(0) as Sprite2D
	sprite.texture = ImageTexture.create_from_image(art)
	sprite.region_enabled = true
	sprite.region_rect = Rect2(0, 0, 8, 8)
	_parameters({"environment_has_emission": false, "environment_has_seasons": false})
	await _compare("paged indexed atlas")
	# Literal-artwork quads must preserve RGBA and the same day/weather grading.
	for item: Sprite2D in viewport.get_children():
		item.modulate = Color8(2, 0, 0, 255)
	_parameters({"environment_enabled": true, "cloud_enabled": false})
	await _compare("paged literal artwork")
	# UI neighborhood previews use their own palette-only shader on all devices.
	_parameters({"environment_enabled": false, "cloud_enabled": false})
	material.shader = preload("res://src/ui/tools/query_palette.gdshader")
	material.set_shader_parameter("foreground_palette", clock.cycle_texture)
	for item: Sprite2D in viewport.get_children():
		item.modulate = Color.WHITE
		item.region_enabled = false
		item.texture = source
	await _compare("query preview palette")
	# Verify LUT cache identity and profile removal, rather than rebuilding per frame.
	var packed := tables.parameters(values)
	assert(tables.parameters(values).map_lut_tables == packed.map_lut_tables)
	values.erase("environment_lut")
	assert(tables.parameters(values).map_lut_tables != packed.map_lut_tables)
	viewport.queue_free()
	await process_frame
	print("PASS: eight-sampler city shaders, Vanilla color, LUTs, cloud shadows, underground, live palette and paged GPU atlas")
	quit()


func _parameters(changes: Dictionary) -> void:
	values.merge(changes, true)
	for key in changes:
		material.set_shader_parameter(key, changes[key])
		reference.set_shader_parameter(key, changes[key])
	material.set_shader_parameter("map_palettes", clock.map_palette_texture)
	reference.set_shader_parameter("animated_palette", clock.cycle_texture)
	reference.set_shader_parameter("dark_underground_palette", clock.underground_cycle_texture)
	for key in tables.parameters(values):
		material.set_shader_parameter(key, tables.parameters(values)[key])


func _compare(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	for y in 8:
		for x in 8:
			var a := image.get_pixel(x, y)
			var b := image.get_pixel(x + 8, y)
			assert(maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) < 0.012 and absf(a.a - b.a) < 0.005,
				"%s differs at %d/%d: %s vs %s" % [label, x, y, a, b])
