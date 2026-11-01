extends "res://tests/support/scene_test_case.gd"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for hdr in [false, true]:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(104, 48)
		viewport.transparent_bg = true
		viewport.use_hdr_2d = hdr
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		image.fill(Color.RED)
		for y in range(8, 16):
			for x in 16:
				image.set_pixel(x, y, Color.BLACK if (x + y) % 2 == 0 else Color.WHITE)
		var texture := ImageTexture.create_from_image(image)
		var material := ShaderMaterial.new()
		material.shader = CityRegionBackdrop.SNAPSHOT_SHADER
		var styles := [Color(1, 1, 0, 0.33), Color(1, 1, 0, 0.66), Color(0, 0, 0, 1),
			Color(1, 1, 0, 0.33), Color(1, 0, 0, 0.33)]
		for index in styles.size():
			var rect := TextureRect.new()
			rect.texture = texture
			rect.material = material
			rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			rect.position.x = index * 20
			rect.modulate = styles[index]
			viewport.add_child(rect)
		var group := Node2D.new()
		group.position.y = 24
		viewport.add_child(group)
		var map := CityMapControl.new()
		map.size = Vector2(16, 16)
		group.add_child(map)
		var indexed := ColorRect.new()
		indexed.size = Vector2(16, 16)
		var indexed_material := ShaderMaterial.new()
		var indexed_shader := Shader.new()
		indexed_shader.code = "shader_type canvas_item; render_mode unshaded; void fragment() { COLOR = vec4(1.0, 0.0, 0.0, 1.0); }"
		indexed_material.shader = indexed_shader
		indexed.material = indexed_material
		map.add_child(indexed)
		map.region_backdrop._set_live_opacity(0.5)
		for frame in 3:
			await RenderingServer.frame_post_draw
		var rendered := viewport.get_texture().get_image()
		var resting := rendered.get_pixel(4, 4)
		var hovered := rendered.get_pixel(24, 4)
		assert(absf(resting.a - 0.33) < 0.02 and absf(hovered.a - 0.66) < 0.02,
			"Region snapshot opacity must stay independent of grayscale and HDR")
		assert(absf(resting.r - resting.g) < 0.01 and absf(resting.g - resting.b) < 0.01)
		var real := rendered.get_pixel(44, 4)
		assert(real.r > 0.95 and real.g < 0.01 and real.a > 0.99, "Real city colors remain unchanged")
		assert(rendered.get_pixel(68, 10).r > rendered.get_pixel(88, 10).r + 0.1,
			"Light snapshot blur softens the pixel pattern")
		assert(rendered.get_pixel(18, 4).a == 0.0, "Snapshot blur cannot fill transparent surrounding space")
		assert(rendered.get_pixel(4, 28).a == 0.0 and not map.visible,
			"Preparation and the still-image fade must hide live screen-reading passes completely")
		map.region_backdrop._set_live_opacity(1.0)
		for frame in 3:
			await RenderingServer.frame_post_draw
		assert(viewport.get_texture().get_image().get_pixel(4, 28).a > 0.99,
			"Completing the still-image fade reveals the original full-opacity city")
		viewport.queue_free()
		await process_frame
	await _effect_still(FixtureGraphics.pack())
	await _effect_still(GraphicsPack.load_root("res://../packs/standalone-graphics/graphics"))
	print("PASS region snapshot effects, grayscale, 33/66 opacity, soft blur and real-color endpoints in SDR/HDR")
	quit()


func _effect_still(graphics: GraphicsPack) -> void:
	var assets := LoadedAssetState.new()
	assets.palette = graphics.palette
	assets.large_sprites = MainMenuPresentation.copy_graphics(graphics.large_sprites)
	CityBrightmaps.load_archive(assets.large_sprites, "", "large")
	CitySeasonColors.prepare(assets.large_sprites, assets.palette)
	assets.large_sprites.water_reflections = true
	assets.large_sprites.water_indices = CityWaterLayer.blue_indices(assets.palette)
	var document: Sc2File = Sc2xDocument.create_empty(32, "Effect still").document
	var city := CityState.from_document(document)
	for x in 32:
		for y in 32:
			city.set_land_altitude(x, y, 3)
			if x >= 10 and x < 22 and y >= 10 and y < 22:
				city.set_land_altitude(x, y, 0)
				city.set_water_altitude(x, y, 3)
				city.set_tile_flag(x, y, Sc2TileFlags.WATER, true)
				city.set_terrain_id(x, y, TerrainTileIds.DEEP_WATER_FLAT)
	city.set_building_id(6, 6, BuildingTileIds.POLICE_STATION)
	city.set_building_corners(6, 6, 0x80)
	var before := preload("res://tests/support/document_state.gd").capture(document)
	var job := CityRegionPreviewJob.create(assets)
	job.document = document
	job.background = Color.TRANSPARENT
	job.run()
	assert(job.image != null, "A regional still must produce its artwork")
	assert(job.water != null, "A regional still must produce enhanced water masks")
	var options := VisualEnhancementOptions.normalize({"day_enabled": false, "weather_enabled": false,
		"cloud_enabled": false, "season_enabled": true, "season_mode": 2, "season_fixed": 3, "tilt_shift_enabled": true})
	var snapshot := CityRegionSnapshot.new()
	snapshot.begin(root, job, options, {})
	assert(not snapshot.presentation.map.layers.water_layer.nodes.is_empty(), "The still must use the normal water pass")
	var image: Image
	for frame in 3:
		await RenderingServer.frame_post_draw
		image = snapshot.poll()
	assert(image != null and image.get_size() == job.image.get_size())
	var changed := 0
	var water_changed := 0
	for y in image.get_height():
		for x in image.get_width():
			var source := job.image.get_pixel(x, y)
			var actual := image.get_pixel(x, y)
			if source.a == 0.0:
				assert(actual.a == 0.0, "Postprocessing must never replace transparent city margins")
			elif actual.a > 0.9:
				changed += int(Vector3(source.r, source.g, source.b).distance_to(Vector3(actual.r, actual.g, actual.b)) > 0.1)
				if job.water.surface.get_pixel(x + 3, y + 3).a > 0.5:
					water_changed += int(Vector3(source.r, source.g, source.b).distance_to(Vector3(actual.r, actual.g, actual.b)) > 0.05)
	assert(changed > 1000 and water_changed > 100, "Frozen neighbors retain seasonal terrain and enhanced water instead of raw palette art")
	snapshot.close()
	await process_frame
	options.day_enabled = true
	options.day_mode = 1
	options.day_hour = 0.0
	var night := CityRegionSnapshot.new()
	night.begin(root, job, options, {})
	var dark: Image
	for frame in 3:
		await RenderingServer.frame_post_draw
		dark = night.poll()
	var darker := 0
	for y in dark.get_height():
		for x in dark.get_width():
			if image.get_pixel(x, y).a > 0.9:
				darker += int(dark.get_pixel(x, y).v < image.get_pixel(x, y).v - 0.1)
	assert(darker > 1000, "Night lighting must remain visible in frozen neighbors")
	night.close()
	assert(preload("res://tests/support/document_state.gd").capture(document) == before, "Baking a still must not change the city or saved random state")
	await process_frame
