extends "res://tests/support/scene_test_case.gd"

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _check_emission_weather(false)
	await _check_emission_weather(true)
	await _check_building_power()
	await _check_hd_environment()
	await _check_terrain_elevation()
	await _check_terrain_elevation(true)
	await _check_terrain_elevation(false, true)
	await _check_terrain_elevation(true, true)
	await _check_hd_animation_masks()
	await _check_object_frame_timing()
	await _check_dispatch_lights()
	await _check_power_warnings()
	await _check_framed_power_warning(false)
	await _check_framed_power_warning(true)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(16, 16)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var pixels := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	pixels.fill(Color(0.55, 0.6, 0.45))
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(pixels)
	var material := ShaderMaterial.new()
	material.shader = preload("res://src/view/map/palette_cycle.gdshader")
	sprite.material = material
	viewport.add_child(sprite)
	await process_frame
	await RenderingServer.frame_post_draw
	var original := viewport.get_texture().get_image().get_pixel(4, 4)
	material.set_shader_parameter("environment_enabled", true)
	material.set_shader_parameter("environment_tint", Vector3(0.86, 0.93, 1.04))
	await RenderingServer.frame_post_draw
	var morning := viewport.get_texture().get_image()
	assert(morning.get_pixel(4, 4).r < original.r)
	assert(morning.get_pixel(4, 4).b >= original.b)
	assert(morning.get_pixel(4, 4).is_equal_approx(morning.get_pixel(12, 12)), "Lighting introduced a spatial gradient")
	material.set_shader_parameter("environment_tint", Vector3(1.06, 0.83, 0.57))
	await RenderingServer.frame_post_draw
	var evening := viewport.get_texture().get_image().get_pixel(4, 4)
	assert(evening.r >= original.r and evening.b < original.b)
	var emission := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	emission.fill(Color(0.9, 0.15, 0.05, 0.5))
	material.set_shader_parameter("environment_emission", ImageTexture.create_from_image(emission))
	material.set_shader_parameter("environment_has_emission", true)
	material.set_shader_parameter("environment_night", 1.0)
	material.set_shader_parameter("environment_tint", Vector3(0.28, 0.34, 0.52))
	await RenderingServer.frame_post_draw
	var lit := viewport.get_texture().get_image().get_pixel(4, 4)
	assert(lit.r > lit.b and lit.r > original.r * 0.28, "Colored, partial-strength emission was lost")
	material.set_shader_parameter("environment_enabled", false)
	await RenderingServer.frame_post_draw
	assert(viewport.get_texture().get_image().get_pixel(4, 4).is_equal_approx(original))
	material.set_shader_parameter("environment_enabled", true)
	material.set_shader_parameter("environment_tint", Vector3.ONE)
	material.set_shader_parameter("environment_has_emission", false)
	var natural_mask := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	natural_mask.fill_rect(Rect2i(0, 0, 8, 16), Color(1, 0, 0, 1))
	material.set_shader_parameter("environment_season_mask", ImageTexture.create_from_image(natural_mask))
	material.set_shader_parameter("environment_has_seasons", true)
	material.set_shader_parameter("environment_seasons", Vector4(0, 0, 0, 1))
	await RenderingServer.frame_post_draw
	var winter := viewport.get_texture().get_image()
	assert(winter.get_pixel(4, 4).r > original.r and winter.get_pixel(4, 4).b > original.b)
	assert(winter.get_pixel(12, 4).is_equal_approx(original), "Season colors reached unmasked artwork")
	material.set_shader_parameter("environment_seasons", Vector4(0, 1, 0, 0))
	await RenderingServer.frame_post_draw
	assert(viewport.get_texture().get_image().get_pixel(4, 4).is_equal_approx(original))
	material.set_shader_parameter("environment_has_seasons", false)
	material.set_shader_parameter("environment_tint", Vector3(0.28, 0.34, 0.52))
	await RenderingServer.frame_post_draw
	var dark := viewport.get_texture().get_image().get_pixel(4, 4)
	material.set_shader_parameter("environment_ambient_lift", 0.5)
	await RenderingServer.frame_post_draw
	var filled := viewport.get_texture().get_image().get_pixel(4, 4)
	assert(filled.r > dark.r and filled.b > dark.b, "Night fill failed to recover surface detail")
	pixels.fill(Color.BLACK)
	sprite.texture = ImageTexture.create_from_image(pixels)
	await RenderingServer.frame_post_draw
	assert(viewport.get_texture().get_image().get_pixel(4, 4).r == 0.0, "Night fill lifted black to grey")
	viewport.queue_free()
	await process_frame
	await _check_weather_layer()
	await _check_rain_depth()
	await _check_zone_seasons()
	await _check_parcel_border(false)
	await _check_parcel_border(true)
	await _check_night_glow(false)
	await _check_night_glow(true)
	await _check_artwork_window_glow(false)
	await _check_artwork_window_glow(true)
	await _check_water_palette_motion()
	await _check_city_life_glow(false)
	await _check_city_life_glow(true)
	await _check_street_fixtures(false)
	await _check_street_fixtures(true)
	await _check_street_fixtures(false, 4)
	await _check_street_fixtures(true, 4)
	print("PASS: GPU uniform morning/evening tint, colored graded brightmaps and original pixels when disabled")
	quit()


func _check_power_warnings() -> void:
	var pack := GraphicsPack.load_root("res://../ext/graphics")
	assert(pack.error.is_empty(), pack.error)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(64, 32)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	viewport.add_child(sprite)
	var material := ShaderMaterial.new()
	material.shader = preload("res://src/view/map/palette_cycle.gdshader")
	sprite.material = material
	material.set_shader_parameter("palette_lookup_all", true)
	material.set_shader_parameter("palette_cycle_enabled", true)
	material.set_shader_parameter("environment_enabled", true)
	material.set_shader_parameter("environment_tint", Vector3(0.1, 0.2, 0.3))
	material.set_shader_parameter("environment_has_seasons", true)
	material.set_shader_parameter("environment_seasons", Vector4(0, 0, 0, 1))
	for archive: Sc2SpriteArchive in [pack.large_sprites, pack.small_medium_sprites]:
		CitySeasonColors.prepare(archive, pack.palette)
		for id in [386, 886, 1386]:
			var entry := archive.find_sprite(id)
			if entry == null:
				continue
			var mask: Image = archive.visual_seasons[id]
			var indices := entry.decode_indices().pixels
			sprite.texture = ImageTexture.create_from_image(entry.create_image(Sc2Palette.index_encoding()).image)
			material.set_shader_parameter("environment_season_mask", ImageTexture.create_from_image(mask))
			var clock := PaletteAnimationClock.new()
			for tick in 8:
				clock.cycle_ticks = tick
				var first := pack.palette.animation_image(tick)
				var next := pack.palette.animation_image(tick + 1)
				for blend in [0.0, 0.5, 1.0]:
					clock.update_textures(pack.palette, blend, false)
					material.set_shader_parameter("animated_palette", clock.cycle_texture)
					await process_frame
					await RenderingServer.frame_post_draw
					var actual := viewport.get_texture().get_image()
					for y in entry.height:
						for x in entry.width:
							var index: int = indices[y * entry.width + x]
							var pixel := actual.get_pixel(x, y)
							if index < 0:
								assert(pixel.a == 0.0 and mask.get_pixel(x, y).a == 0.0, "Warning silhouette changed")
								continue
							var expected := first.get_pixel(index, 0).lerp(next.get_pixel(index, 0), blend)
							assert(abs(pixel.r8 - expected.r8) <= 2 and abs(pixel.g8 - expected.g8) <= 2
								and abs(pixel.b8 - expected.b8) <= 2 and pixel.a8 == 255,
								"Power warning %d lost its fullbright palette blend at tick %d" % [id, tick])
	viewport.queue_free()
	await process_frame
	print("PASS: all power-warning sizes blend resolved palette colors and stay fullbright at night with lighting disabled")


func _check_dispatch_lights() -> void:
	var pack := GraphicsPack.load_root("res://../ext/graphics")
	assert(pack.error.is_empty(), pack.error)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(32, 80)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	viewport.add_child(sprite)
	var material := ShaderMaterial.new()
	material.shader = preload("res://src/view/map/palette_cycle.gdshader")
	sprite.material = material
	for archive: Sc2SpriteArchive in [pack.large_sprites, pack.small_medium_sprites]:
		CityDispatchLights.prepare(archive, pack.palette)
		for id: int in CityDispatchLights.HEADS:
			var entry := archive.find_sprite(id)
			if entry == null:
				continue
			var original: Image = entry.create_image(pack.palette).image
			var mask: Image = archive.visual_emission[id]
			var head_height: int = CityDispatchLights.HEADS[id][2]
			sprite.texture = ImageTexture.create_from_image(original)
			material.set_shader_parameter("environment_emission", ImageTexture.create_from_image(mask))
			material.set_shader_parameter("environment_has_emission", true)
			material.set_shader_parameter("environment_enabled", false)
			await process_frame
			await RenderingServer.frame_post_draw
			var day := viewport.get_texture().get_image()
			material.set_shader_parameter("environment_enabled", true)
			material.set_shader_parameter("environment_tint", Vector3(0.28, 0.34, 0.52))
			material.set_shader_parameter("environment_night", 1.0)
			await RenderingServer.frame_post_draw
			var night := viewport.get_texture().get_image()
			for y in entry.height:
				for x in entry.width:
					var a := day.get_pixel(x, y)
					var b := night.get_pixel(x, y)
					assert(a.a8 == b.a8, "Marker lighting changed its silhouette")
					if a.a == 0.0:
						continue
					if y < head_height:
						assert(abs(a.r8 - b.r8) <= 1 and abs(a.g8 - b.g8) <= 1 and abs(a.b8 - b.b8) <= 1,
							"Dispatch symbol lost original shading or brightness at night")
					else:
						assert(mask.get_pixel(x, y).a == 0.0, "Dispatch post was included in the light mask")
						assert(b.r <= a.r * 0.28 + 0.01 and b.g <= a.g * 0.34 + 0.01 and b.b <= a.b * 0.52 + 0.01)
	# Do not apply standard coordinates to changed SCURK artwork; authored masks win.
	var changed := Sc2SpriteArchive.new()
	var entry := pack.large_sprites.find_sprite(1382)
	var pixels: PackedInt32Array = entry.decode_indices().pixels.duplicate()
	pixels[0] = 5
	changed.entries_by_id[1382] = Sc2SpriteArchive.entry_from_indices(1382, entry.width, entry.height, pixels)
	CityDispatchLights.prepare(changed, pack.palette)
	assert(changed.visual_emission.is_empty())
	changed.visual_emission[1382] = Image.create(32, 70, false, Image.FORMAT_RGBA8)
	var custom: Image = changed.visual_emission[1382]
	CityDispatchLights.prepare(changed, pack.palette)
	assert(changed.visual_emission[1382] == custom)
	viewport.queue_free()
	await process_frame
	print("PASS: nine dispatch heads preserve daytime colors at night; posts stay dark and custom artwork is respected")


func _check_night_glow(hdr: bool) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(128, 96)
	viewport.transparent_bg = true
	viewport.use_hdr_2d = hdr
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var app := CityApplication.new()
	var map := CityMapControl.new()
	map.size = Vector2(viewport.size)
	app.map_view = map
	viewport.add_child(map)
	var pixels := Image.create(128, 96, false, Image.FORMAT_RGBA8)
	pixels.fill(Color(0.2, 0.3, 0.4))
	var light := Image.create(128, 96, false, Image.FORMAT_RGBA8)
	light.fill_rect(Rect2i(60, 44, 8, 8), Color(1.0, 0.35, 0.1, 0.5))
	map.city_source = CityMapSource.whole(ImageTexture.create_from_image(pixels))
	map.city_source.emission = ImageTexture.create_from_image(light)
	map.source_center = Vector2(64, 48)
	map.layers._sync_base_layer()
	var options := VisualEnhancementOptions.normalize({"night_ground": 0.0, "night_glow": 100.0})
	var lighting := app.visual_environment.night_lighting
	lighting.process(true, 1.0, options)
	for i in 4:
		await RenderingServer.frame_post_draw
	var on := viewport.get_texture().get_image()
	await _check_night_mesh_reuse(viewport, map, lighting, pixels, light, options)
	lighting.process(true, 0.0, options)
	await RenderingServer.frame_post_draw
	var off := viewport.get_texture().get_image()
	var delta := on.get_pixel(58, 48) - off.get_pixel(58, 48)
	assert(delta.r > 0.01 and delta.r > delta.g * 1.5, "Graded, colored emission produced no local glow outside its sharp core")
	assert(on.get_pixel(10, 10).is_equal_approx(off.get_pixel(10, 10)), "Glow added a full-screen veil: hdr=%s on=%s off=%s" % [hdr, on.get_pixel(10, 10), off.get_pixel(10, 10)])
	# Repeated updates must keep both weather and tool markers above the glow.
	var marker := ColorRect.new()
	marker.color = Color.GREEN
	marker.position = Vector2(56, 40)
	marker.size = Vector2(16, 16)
	for target in [map.layers.overlay_layer, app.visual_environment.weather]:
		if target is CityVisualWeather:
			target.rain = 0.5
			target._sync_layer(true)
			target.layer.show()
			target.layer.add_child(marker)
		else:
			target.add_child(marker)
		await RenderingServer.frame_post_draw
		var marker_pixel := viewport.get_texture().get_image().get_pixel(58, 48)
		for frame in 4:
			lighting.process(true, 1.0, options)
			await RenderingServer.frame_post_draw
			assert(viewport.get_texture().get_image().get_pixel(58, 48).is_equal_approx(marker_pixel), "Night glow covered weather or tool overlays")
		marker.get_parent().remove_child(marker)
	# Clouds can appear after the lights, and each artwork size adds a new
	# receiver node. An opaque cloud patch must cover emission in SDR and HDR.
	var cloud := ColorRect.new()
	cloud.color = Color.TRANSPARENT
	cloud.size = map.size
	map.add_child(cloud)
	app.visual_environment.clouds.layer = cloud
	cloud.add_child(marker)
	map.move_child(cloud, lighting.output.get_index())
	for zoom in [0.25, 0.1, 0.25]:
		map.zoom_factor = zoom
		lighting.process(true, 1.0, options)
		for frame in 4:
			await RenderingServer.frame_post_draw
		assert(viewport.get_texture().get_image().get_pixel(64, 48).is_equal_approx(Color.GREEN),
			"Night lights painted over cloud cover at zoom %s, HDR=%s" % [zoom, hdr])
		assert(lighting.ground.get_index() < cloud.get_index())
	cloud.remove_child(marker)
	marker.free()
	cloud.free()
	app.visual_environment.clouds.layer = null
	map.zoom_factor = 1.0
	app.visual_environment.weather.layer.hide()
	lighting.process(true, 1.0, options)
	var cover := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	cover.fill(Color.WHITE)
	lighting._add_texture(ImageTexture.create_from_image(cover), null, Vector2(56, 40), Vector2(16, 16))
	for i in 4:
		await RenderingServer.frame_post_draw
	assert(viewport.get_texture().get_image().get_data() == off.get_data(), "Hidden windows leaked through foreground geometry")
	assert(lighting.ground.visible == false)
	lighting.process(false, 1.0, options)
	assert(not lighting.output.visible)
	for buffer in lighting.buffers:
		assert(buffer.render_target_update_mode == SubViewport.UPDATE_DISABLED)
	viewport.queue_free()
	app.free()
	await process_frame


func _check_water_palette_motion() -> void:
	var palette := FixtureGraphics.pack().palette
	var viewport := SubViewport.new()
	viewport.size = Vector2i(9, 1)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var image := Image.create(9, 1, false, Image.FORMAT_RGBA8)
	for index in 9:
		var color := 200 + index if index < 8 else 195
		image.set_pixel(index, 0, Color8(color, color, color))
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(image)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var material := ShaderMaterial.new()
	material.shader = CityMapControl.PALETTE_CYCLE_SHADER
	material.set_shader_parameter("palette_lookup_all", true)
	material.set_shader_parameter("palette_cycle_enabled", true)
	sprite.material = material
	viewport.add_child(sprite)
	var clock := PaletteAnimationClock.new()
	var frames: Array[Image] = []
	for state in [Vector2(7, 0.0), Vector2(7, 0.5), Vector2(7, 0.99), Vector2(8, 0.0)]:
		clock.cycle_ticks = int(state.x)
		clock.update_textures(palette, 0.0, false, false, state.y)
		material.set_shader_parameter("animated_palette", clock.cycle_texture)
		await RenderingServer.frame_post_draw
		frames.append(viewport.get_texture().get_image())
	assert(frames[0].get_data() != frames[1].get_data(), "Vanilla water remained frozen between palette ticks")
	assert(frames[0].get_pixel(8, 0) == frames[2].get_pixel(8, 0), "Water smoothing changed the power-warning cycle")
	for index in 8:
		var delta := frames[2].get_pixel(index, 0) - frames[3].get_pixel(index, 0)
		assert(maxf(absf(delta.r), maxf(absf(delta.g), absf(delta.b))) < 0.02, "Water flashes when the palette cycle wraps")
	viewport.queue_free()
	await process_frame


func _check_artwork_window_glow(hdr: bool) -> void:
	# Title-screen windows are rasterized at 1x/2x/4x, but retain their logical
	# map bounds. Exercise the same tile publication and glow-copy path.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(400, 300)
	viewport.transparent_bg = true
	viewport.use_hdr_2d = hdr
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var app := CityApplication.new()
	var map := CityMapControl.new()
	map.size = Vector2(viewport.size)
	app.map_view = map
	viewport.add_child(map)
	map.source_center = map.size / 2.0
	var light := Image.create(160, 120, false, Image.FORMAT_RGBA8)
	light.fill_rect(Rect2i(36, 26, 8, 8), Color.WHITE)
	var options := VisualEnhancementOptions.normalize({"night_ground": 0.0, "night_glow": 100.0})
	var lighting := app.visual_environment.night_lighting
	for density in [1, 2, 4]:
		var art := Image.create(160 * density, 120 * density, false, Image.FORMAT_RGBA8)
		art.fill(Color.BLACK)
		var source := CityMapSource.new(Vector2i(viewport.size))
		var tile := CityMapSource.TileEntry.new(Vector2(20, 20), Vector2(160, 120),
			ImageTexture.create_from_image(art), CityDynamicSpriteCanvas.ARTWORK_TAG)
		tile.emission = ImageTexture.create_from_image(light)
		source.tiles.append(tile)
		map.city_source = source
		for pan in [Vector2.ZERO, Vector2(10, 6)]:
			map.source_center = map.size / 2.0 + pan
			lighting.process(true, 1.0, options)
			for frame in 4:
				await RenderingServer.frame_post_draw
			assert(lighting.copies[0].size == tile.size, "Glow stretched a menu artwork window to its texture size")
			var image := viewport.get_texture().get_image()
			var lamp := Vector2i(Vector2(60, 50) - pan)
			assert(image.get_pixelv(lamp).r > 0.1, "Menu glow missed its actual lamp")
			assert(image.get_pixel(180, 140).r < 0.001, "Displaced menu glow leaked into the water")
	viewport.queue_free()
	app.free()
	await process_frame


func _check_city_life_glow(hdr: bool) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(800, 400)
	viewport.transparent_bg = true
	viewport.use_hdr_2d = hdr
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var app := CityApplication.new()
	var map := CityMapControl.new()
	map.size = Vector2(viewport.size)
	map.city_source = CityMapSource.new(Vector2i(5000, 5000))
	app.map_view = map
	viewport.add_child(map)
	var figures := CityLifeCanvas.new()
	app.city_life.canvas = figures
	var sprites := CityLifeSprites.new()
	var lamps := CityLifeLights.new()
	var lighting := app.visual_environment.night_lighting
	var options := VisualEnhancementOptions.normalize({"night_ground": 0.0, "night_glow": 100.0})
	for zoom in [0.5, 1.0]:
		map.zoom_factor = zoom
		for phase in 4:
			# Pan the viewport and repack, grow, shrink, then hide the vehicle atlas.
			var bounds := Rect2i(1234 + phase * 17, 2345 - phase * 11, 640, 256)
			map.source_center = bounds.get_center()
			var pixels := Image.create(640, 256, false, Image.FORMAT_RGBA8)
			var emission := pixels.duplicate() as Image
			var entries: Array[Dictionary] = []
			var count: int = [3, 40, 2, 2][phase]
			for i in count:
				var sprite := sprites.sprite(false, i % 12, i % 4, 0, i % 3)
				var mask := lamps.lamp_mask(sprite, i % 3, i % 4)
				@warning_ignore("integer_division")
				var origin := bounds.position + Vector2i((i % 10) * 64 + 61, (i / 10) * 64 + 25)
				var opacity := 1.0 if i % 2 == 0 else 0.5
				entries.append({"sprite": sprite, "origin": origin, "lamps": mask, "opacity": opacity, "occluders": []})
				CityLifeCanvas.stamp(pixels, bounds.position, sprite, origin, [], opacity, emission, mask)
			if phase == 0:
				figures.atlas.compose(bounds, entries, true)
			figures.visible = phase != 3
			lighting.process(true, 1.0, options)
			# Match ApplicationFrame: vehicle geometry updates after lighting.
			figures.source_bounds = bounds
			figures.atlas.compose(bounds, entries, true)
			# Avoid nearest-sampling ties when comparing differently packed textures.
			lighting.scene.position += Vector2(0.125, 0.125)
			var reference := Sprite2D.new()
			reference.centered = false
			reference.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			reference.texture = ImageTexture.create_from_image(pixels)
			reference.position = bounds.position
			var material := ShaderMaterial.new()
			material.shader = CityNightLighting.EMISSION
			material.set_shader_parameter("has_emission", true)
			material.set_shader_parameter("emission", ImageTexture.create_from_image(emission))
			reference.material = material
			lighting.scene.add_child(reference)
			reference.visible = figures.visible
			lighting.life.hide()
			for frame in 4:
				await RenderingServer.frame_post_draw
			var expected := viewport.get_texture().get_image()
			var expected_emission := lighting.buffers[0].get_texture().get_image()
			reference.hide()
			lighting.process(true, 1.0, options)
			lighting.scene.position += Vector2(0.125, 0.125)
			for frame in 4:
				await RenderingServer.frame_post_draw
			assert(lighting.buffers[0].get_texture().get_image().get_data() == expected_emission.get_data(),
				"Vehicle glow emission left its world position: hdr=%s zoom=%s phase=%d" % [hdr, zoom, phase])
			assert(viewport.get_texture().get_image().get_data() == expected.get_data(),
				"Vehicle glow leaked onto empty terrain: hdr=%s zoom=%s phase=%d" % [hdr, zoom, phase])
			reference.free()
	figures.free()
	viewport.queue_free()
	app.free()
	await process_frame
	print("PASS: vehicle glow stays at world positions at 50/100 percent through atlas repacking, panning and hiding; HDR=", hdr)


func _check_night_mesh_reuse(viewport: SubViewport, map: CityMapControl, lighting: CityNightLighting,
		pixels: Image, light: Image, options: Dictionary) -> void:
	var original := map.city_source
	var geometry := QuadMesh.new()
	geometry.size = Vector2(128, 96)
	var texture := ImageTexture.create_from_image(pixels)
	var emission := ImageTexture.create_from_image(light)
	var first := CityMapSource.MeshEntry.new(Vector2(64, 48), geometry, texture, 1)
	first.immutable = true
	first.emission = emission
	var source := CityMapSource.new(Vector2i(128, 96))
	source.meshes.append(first)
	map.city_source = source
	lighting.process(true, 1.0, options)
	for changed in [false, true]:
		var item_id := lighting.copies[0].get_instance_id()
		var next := CityMapSource.new(source.size)
		var entry := first
		if changed:
			entry = CityMapSource.MeshEntry.new(Vector2(60, 46), geometry, texture, 1)
			entry.immutable = true
			entry.emission = null
		next.meshes.append(entry)
		map.city_source = next
		lighting.process(true, 1.0, options)
		assert(lighting.copies[0].get_instance_id() == item_id, "Region updates must retain light canvas items")
		for frame in 4:
			await RenderingServer.frame_post_draw
		var cached := viewport.get_texture().get_image()
		lighting.source = null
		lighting.process(true, 1.0, options)
		for frame in 4:
			await RenderingServer.frame_post_draw
		assert(viewport.get_texture().get_image().get_data() == cached.get_data(),
			"Reused night geometry must exactly match a fresh rebuild after emission and position changes")
	var retained_id := lighting.copies[0].get_instance_id()
	for count in [3, 1, 2]:
		var next := CityMapSource.new(source.size)
		for index in count:
			next.meshes.append(first)
		map.city_source = next
		lighting.process(true, 1.0, options)
		assert(lighting.copies[0].get_instance_id() == retained_id, "Panning must retain existing light nodes")
		for index in lighting.copies.size():
			var copy := lighting.copies[index] as MeshInstance2D
			assert(copy.visible == (index < count))
			assert(copy.mesh == (first.mesh if index < count else null), "Hidden pool slots retain geometry or visible slots lose it")
	map.city_source = original
	lighting.process(true, 1.0, options)
	for frame in 4:
		await RenderingServer.frame_post_draw


func _check_street_fixtures(hdr: bool, raster_scale := 1) -> void:
	var viewport := SubViewport.new()
	var zoom := 4 if raster_scale > 1 else 1
	viewport.size = Vector2i(96, 80) * zoom
	viewport.use_hdr_2d = hdr
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var background := ColorRect.new()
	background.size = Vector2(viewport.size)
	background.color = Color(0.08, 0.09, 0.12)
	viewport.add_child(background)
	await RenderingServer.frame_post_draw
	var before := viewport.get_texture().get_image()
	var app := CityApplication.new()
	app.document_state.city = load("res://tests/city_life_test.gd").fixture()
	var ground := CityNightGround.new()
	ground.roads.set_raster_scale(raster_scale)
	ground.scale = Vector2.ONE * zoom
	viewport.add_child(ground)
	var tile := Vector2i(64, 64)
	for axis in 2:
		ground.masker._occluders[Vector3i(tile.x, tile.y, axis)] = []
	var surface := ground._build(app, tile)
	ground.position = (Vector2(16, 8) - Vector2(surface.origin)) * zoom
	ground.cache[tile] = surface
	ground.visible_tiles = [tile]
	(ground.material as ShaderMaterial).set_shader_parameter("strength", 0.45)
	ground.queue_redraw()
	ground.fixtures.queue_redraw()
	ground._refresh_signals()
	await RenderingServer.frame_post_draw
	var after := viewport.get_texture().get_image()
	var red := 0
	var green := 0
	var warm := 0
	for y in after.get_height():
		for x in after.get_width():
			var pixel := after.get_pixel(x, y)
			red += int(pixel.r > 0.6 and pixel.r > pixel.g * 2.0)
			green += int(pixel.g > 0.6 and pixel.g > pixel.r * 1.5)
			warm += int(pixel.r > before.get_pixel(x, y).r + 0.08 and pixel.r > pixel.b * 1.3)
	assert(red >= 2 and green >= 2, "Junction lamps are missing red or green output on the GPU")
	assert(warm > 50, "Street light pools remain too small or dim to read: hdr=%s warm=%d red=%d green=%d" % [hdr, warm, red, green])
	var redraws := {"ground": 0, "fixtures": 0, "signals": 0}
	ground.draw.connect(func(): redraws.ground += 1)
	ground.fixtures.draw.connect(func(): redraws.fixtures += 1)
	ground.signals.draw.connect(func(): redraws.signals += 1)
	ground.clock = 6.0
	ground.signals.queue_redraw()
	await RenderingServer.frame_post_draw
	assert(viewport.get_texture().get_image().get_data() != after.get_data(), "Cosmetic signal phase failed to change visible lenses")
	assert(redraws.ground == 0 and redraws.fixtures == 0 and redraws.signals == 1, "Signal animation rebuilt static drawing commands")
	ground.hide()
	await RenderingServer.frame_post_draw
	assert(viewport.get_texture().get_image().get_data() == before.get_data(), "Disabled street lighting left fixtures behind")
	viewport.queue_free()
	app.free()
	await process_frame


func _check_weather_layer() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256, 192)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var app := CityApplication.new()
	var map := CityMapControl.new()
	map.size = Vector2(viewport.size)
	app.map_view = map
	viewport.add_child(map)
	var pixels := Image.create(256, 192, false, Image.FORMAT_RGBA8)
	pixels.fill(Color(0.2, 0.3, 0.15))
	map.city_source = CityMapSource.whole(ImageTexture.create_from_image(pixels))
	map.source_center = Vector2(128, 96)
	map.layers._sync_base_layer()
	# The map can also publish direct draw commands before a texture layer
	# exists. This path must not draw over the precipitation child.
	map.layers.base_layer.hide()
	map.layers.base_layer = null
	map.queue_redraw()
	var marker := ColorRect.new()
	marker.color = Color(0.1, 0.9, 0.2)
	marker.size = Vector2(12, 12)
	marker.position = Vector2(100, 80)
	map.layers.overlay_layer.add_child(marker)
	app.preferences.visual_enhancements = VisualEnhancementOptions.normalize({"weather_mode": 2})
	var weather := app.visual_environment.weather
	weather.process(5.0, 0.0, true, 1.0)
	await RenderingServer.frame_post_draw
	var sunny := viewport.get_texture().get_image()
	for kind in [CityVisualWeather.Kind.LIGHT_RAIN, CityVisualWeather.Kind.HEAVY_RAIN, CityVisualWeather.Kind.LIGHT_SNOW, CityVisualWeather.Kind.HEAVY_SNOW]:
		app.preferences.visual_enhancements.weather_fixed = kind
		weather.process(5.0, 0.0, true, 3.0)
		if kind in [CityVisualWeather.Kind.LIGHT_SNOW, CityVisualWeather.Kind.HEAVY_SNOW]:
			assert(weather.snow > 0.0 and weather.rain == 0.0, "Winter snow did not reach the particle shader")
		await RenderingServer.frame_post_draw
		var rendered := viewport.get_texture().get_image()
		assert(rendered.get_pixel(104, 84).is_equal_approx(sunny.get_pixel(104, 84)), "Weather covered a tool overlay")
		var changed := 0
		for y in range(16, 176):
			for x in range(16, 240):
				if not rendered.get_pixel(x, y).is_equal_approx(sunny.get_pixel(x, y)):
					changed += 1
		assert(changed > 100 and changed < 20000, "Weather particles are absent or cover the entire city: %d" % changed)
	# Fixed summer snow reaches the GPU; both precipitation types have smaller
	# screen footprints in the overview and remain visible at every zoom level.
	for kind in [CityVisualWeather.Kind.HEAVY_RAIN, CityVisualWeather.Kind.HEAVY_SNOW]:
		app.preferences.visual_enhancements.weather_fixed = kind
		var footprints: Array[float] = []
		for zoom in CityMapConstants.ZOOM_LEVELS:
			map.zoom_factor = zoom
			weather.process(5.0, 0.0, true, 1.0)
			weather.clock = 9.25
			weather._sync_layer(true)
			await RenderingServer.frame_post_draw
			var rendered := viewport.get_texture().get_image()
			footprints.append(_particle_width(rendered, sunny))
		assert(footprints.back() > footprints.front() + 0.1, "Precipitation did not scale with map zoom")
	map.zoom_factor = 1.0
	weather._sync_layer(true)
	var original_center := map.source_center
	for kind in [CityVisualWeather.Kind.HEAVY_RAIN, CityVisualWeather.Kind.HEAVY_SNOW]:
		app.preferences.visual_enhancements.weather_fixed = kind
		weather.process(5.0, 0.0, true, 1.0)
		await RenderingServer.frame_post_draw
		var stationary := viewport.get_texture().get_image().get_data()
		weather.process(60.0, 60.0, true, 1.0, true)
		await RenderingServer.frame_post_draw
		assert(viewport.get_texture().get_image().get_data() == stationary, "Paused precipitation changed GPU pixels")
		map.source_center += Vector2(120, 80)
		weather._sync_layer(true)
		await RenderingServer.frame_post_draw
		assert(viewport.get_texture().get_image().get_data() != stationary, "Frozen precipitation did not respond to camera panning")
		map.source_center = original_center
		weather._sync_layer(true)
		await RenderingServer.frame_post_draw
		assert(viewport.get_texture().get_image().get_data() == stationary, "Returning the camera changed the precipitation field")
	var pan_before_zoom := weather.camera_pan
	map.zoom_factor = 2.0
	map.source_center += Vector2(20, 10)
	weather._sync_layer(true)
	assert(weather.camera_pan.is_equal_approx(pan_before_zoom), "Anchored zoom introduced a false parallax pan")
	map.zoom_factor = 1.0
	map.source_center = original_center
	weather.reset()
	weather._sync_layer(true)
	assert(weather.camera_pan == Vector2.ZERO, "New city inherited the previous camera drift")
	weather.flash = 1.0
	weather.rain = 0.0
	weather.snow = 0.0
	weather.lightning.origin = Vector2(0.0, 0.0)
	weather.lightning.spread = 0.5
	weather._sync_layer(true)
	await RenderingServer.frame_post_draw
	var discharge := viewport.get_texture().get_image()
	assert(discharge.get_pixel(30, 30).r > sunny.get_pixel(30, 30).r, "Lightning was hidden behind the city")
	assert(discharge.get_pixel(30, 30).r > discharge.get_pixel(220, 160).r, "Lightning lost its spatial origin")
	assert(discharge.get_pixel(104, 84).is_equal_approx(sunny.get_pixel(104, 84)), "Lightning covered the tool overlay")
	# With fixed illumination, a dry storm has no moving particle pixels.
	for time in [0.37, 5.9, 28.1]:
		weather.clock = time
		weather._sync_layer(true)
		await RenderingServer.frame_post_draw
		assert(viewport.get_texture().get_image().get_data() == discharge.get_data(), "Dry lightning revealed moving precipitation")
	weather.flash = 0.0
	app.preferences.visual_enhancements.weather_fixed = CityVisualWeather.Kind.SUNNY
	weather.process(5.0, 0.0, true, 1.0)
	await RenderingServer.frame_post_draw
	assert(viewport.get_texture().get_image().get_data() == sunny.get_data(), "Sunny changed original city pixels")
	viewport.queue_free()
	app.free()
	await process_frame


func _check_zone_seasons() -> void:
	var pack := FixtureGraphics.pack()
	var archive := pack.large_sprites
	CitySeasonColors.prepare(archive, pack.palette)
	var viewport := SubViewport.new()
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var material := ShaderMaterial.new()
	material.shader = preload("res://src/view/map/palette_cycle.gdshader")
	material.set_shader_parameter("environment_has_seasons", true)
	sprite.material = material
	viewport.add_child(sprite)
	for id in range(1291, 1300):
		var entry := archive.find_sprite(id)
		var pixels: Image = entry.create_image(pack.palette).image
		viewport.size = pixels.get_size()
		sprite.texture = ImageTexture.create_from_image(pixels)
		var mask: Image = archive.visual_seasons[id]
		material.set_shader_parameter("environment_season_mask", ImageTexture.create_from_image(mask))
		material.set_shader_parameter("environment_enabled", false)
		await RenderingServer.frame_post_draw
		var original := viewport.get_texture().get_image()
		material.set_shader_parameter("environment_enabled", true)
		for season in 4:
			var weights := Vector4.ZERO
			weights[season] = 1.0
			material.set_shader_parameter("environment_seasons", weights)
			await RenderingServer.frame_post_draw
			var colored := viewport.get_texture().get_image()
			var changed := 0
			for y in pixels.get_height():
				for x in pixels.get_width():
					if pixels.get_pixel(x, y).a <= 0.0:
						continue
					var different := not colored.get_pixel(x, y).is_equal_approx(original.get_pixel(x, y))
					if mask.get_pixel(x, y).g > 0.0 and season != 1:
						changed += int(different)
					else:
						assert(not different, "Season changed zone markings or original summer colors")
			assert(season == 1 or changed > 20, "Zoned ground retained brown soil in a seasonal view")
	viewport.queue_free()
	await process_frame


func _check_rain_depth() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256, 192)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var background := ColorRect.new()
	background.size = Vector2(viewport.size)
	background.color = Color.BLACK
	viewport.add_child(background)
	await RenderingServer.frame_post_draw
	var empty := viewport.get_texture().get_image()
	# Isolate each production rain plane to measure its visible footprint.
	var source: String = CityVisualWeather.PARTICLES.code
	var shader := Shader.new()
	shader.code = source.substr(0, source.find("void fragment()")) + \
		"uniform float test_depth; void fragment() { COLOR = vec4(vec3(1.0), rain_layer(UV * extent, test_depth)); }"
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("extent", Vector2(viewport.size))
	material.set_shader_parameter("rain", 1.0)
	material.set_shader_parameter("clock", 9.25)
	var rain := ColorRect.new()
	rain.size = Vector2(viewport.size)
	rain.material = material
	viewport.add_child(rain)
	var widths: Array[float] = []
	for depth in 3:
		material.set_shader_parameter("test_depth", float(depth))
		await RenderingServer.frame_post_draw
		widths.append(_particle_width(viewport.get_texture().get_image(), empty))
	assert(widths[1] > widths[0] + 0.1 and widths[2] > widths[1] + 0.1,
		"Rain planes lack distinct distant, middle and soft foreground footprints: %s" % [widths])
	viewport.queue_free()
	await process_frame


func _particle_width(rendered: Image, background: Image) -> float:
	var covered := 0
	var adjacent := 0
	for y in range(16, 176):
		for x in range(16, 239):
			if rendered.get_pixel(x, y).r - background.get_pixel(x, y).r > 0.03:
				covered += 1
				if rendered.get_pixel(x + 1, y).r - background.get_pixel(x + 1, y).r > 0.03:
					adjacent += 1
	assert(covered > 60, "Precipitation disappeared at a map zoom level")
	return float(adjacent) / maxf(covered, 1.0)


# The upstream literal-art tag must keep full-color pixels when palette lookup
# is on, while participating in the package's environmental grading.
func _check_hd_environment() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(8, 8)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var pixels := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	pixels.fill(Color(0.4, 0.6, 0.8))
	var palette := Image.create(256, 1, false, Image.FORMAT_RGBA8)
	palette.fill(Color.RED)
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(pixels)
	sprite.self_modulate = CityDynamicSpriteCanvas.ARTWORK_TAG
	var material := ShaderMaterial.new()
	material.shader = CityMapControl.PALETTE_CYCLE_SHADER
	material.set_shader_parameter("palette_lookup_all", true)
	material.set_shader_parameter("palette_cycle_enabled", true)
	material.set_shader_parameter("animated_palette", ImageTexture.create_from_image(palette))
	sprite.material = material
	viewport.add_child(sprite)
	await process_frame
	await RenderingServer.frame_post_draw
	var original := viewport.get_texture().get_image()
	var pixel := original.get_pixel(4, 4)
	assert(pixel.b > 0.7 and pixel.g > 0.5 and pixel.r < 0.5, "HD art must retain its literal colors")
	material.set_shader_parameter("environment_enabled", true)
	material.set_shader_parameter("environment_night", 1.0)
	material.set_shader_parameter("environment_tint", Vector3(0.2, 0.3, 0.4))
	await RenderingServer.frame_post_draw
	var night := viewport.get_texture().get_image().get_pixel(4, 4)
	assert(night.r < pixel.r * 0.3 and night.g < pixel.g * 0.4 and night.b < pixel.b * 0.5,
		"HD art must follow the same night lighting as indexed sprites")
	material.set_shader_parameter("environment_enabled", false)
	await RenderingServer.frame_post_draw
	assert(viewport.get_texture().get_image().get_data() == original.get_data(), "Disabling effects must restore HD pixels")
	viewport.queue_free()
	await process_frame


func _check_terrain_elevation(paged := false, indexed := false) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(32, 16)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var art := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	art.fill(Color(0.4, 0.6, 0.3))
	var soil := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	soil.fill_rect(Rect2i(0, 0, 4, 8), Color(0, 1, 0, 1))
	var material := ShaderMaterial.new()
	material.shader = preload("res://src/view/map/palette_cycle_pages.gdshader") if paged else CityMapControl.PALETTE_CYCLE_SHADER
	material.set_shader_parameter("environment_has_seasons", true)
	material.set_shader_parameter("environment_season_mask", ImageTexture.create_from_image(soil))
	material.set_shader_parameter("terrain_elevation_enabled", true)
	if paged:
		var art_pages := Texture2DArray.new()
		var soil_pages := Texture2DArray.new()
		art_pages.create_from_images([art])
		soil_pages.create_from_images([soil])
		material.set_shader_parameter("region_atlas_edge", 8.0)
		material.set_shader_parameter("region_atlas_pages", art_pages)
		material.set_shader_parameter("region_season_pages", soil_pages)
	var sprites: Array[Sprite2D] = []
	material.set_shader_parameter("terrain_elevation_range", Vector2(0, 8))
	for height in [2, 6]:
		var sprite := Sprite2D.new()
		sprite.centered = false
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.texture = ImageTexture.create_from_image(art)
		sprite.material = material
		sprite.position.x = sprites.size() * 8
		sprite.self_modulate = Color((54.0 if indexed else 53.0) / 255.0, height / 255.0, 0, 1)
		viewport.add_child(sprite)
		sprites.append(sprite)
	for zoom in [1, 2]:
		for sprite in sprites:
			sprite.scale = Vector2.ONE * zoom
			sprite.position.x = sprites.find(sprite) * 8 * zoom
		await process_frame
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		var low := image.get_pixel(2 * zoom, 2 * zoom)
		var high := image.get_pixel(10 * zoom, 2 * zoom)
		assert(high.r > low.r and high.g > low.g and high.b > low.b, "Terrain elevation must rise monotonically in every color channel")
		assert(high.get_luminance() > low.get_luminance() * 1.10, "Four levels must remain distinguishable in a modest-height city")
		assert(absf(low.r / low.g - high.r / high.g) < 0.025, "Elevation changed the terrain hue")
		assert(image.get_pixel(6 * zoom, 2 * zoom).is_equal_approx(image.get_pixel(14 * zoom, 2 * zoom)), "Elevation affected unmasked paths or water")
	material.set_shader_parameter("terrain_elevation_enabled", false)
	await RenderingServer.frame_post_draw
	var disabled := viewport.get_texture().get_image()
	assert(disabled.get_pixel(4, 4).is_equal_approx(disabled.get_pixel(20, 4)), "Disabled terrain shading retained a height tint")
	material.set_shader_parameter("terrain_elevation_enabled", true)
	material.set_shader_parameter("dark_underground", true)
	await RenderingServer.frame_post_draw
	var underground := viewport.get_texture().get_image()
	assert(underground.get_pixel(4, 4).is_equal_approx(underground.get_pixel(20, 4)), "Surface elevation changed underground tones")
	viewport.queue_free()
	await process_frame
	print("PASS: terrain elevation preserves hue, masks, zoom and underground fallback; paged=", paged)


func _check_hd_animation_masks() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(8, 8)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var pixels := Image.create(8, 24, false, Image.FORMAT_RGBA8)
	pixels.fill(Color.WHITE)
	var masks := Image.create(8, 24, false, Image.FORMAT_RGBA8)
	masks.fill_rect(Rect2i(0, 2, 8, 8), Color.RED)
	masks.fill_rect(Rect2i(0, 14, 8, 8), Color.BLUE)
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(pixels)
	sprite.region_enabled = true
	sprite.region_rect = Rect2(0, 2, 8, 8)
	# Native HD animation tag, two frames at 8 FPS, padded stride of 12 rows.
	sprite.self_modulate = Color(64.0 / 255.0, 2.0 / 255.0, 0, 12.0 / 255.0)
	var material := ShaderMaterial.new()
	material.shader = CityMapControl.PALETTE_CYCLE_SHADER
	material.set_shader_parameter("environment_enabled", true)
	material.set_shader_parameter("environment_night", 1.0)
	material.set_shader_parameter("environment_has_emission", true)
	material.set_shader_parameter("environment_emission", ImageTexture.create_from_image(masks))
	sprite.material = material
	viewport.add_child(sprite)
	await process_frame
	await RenderingServer.frame_post_draw
	var first := viewport.get_texture().get_image().get_pixel(4, 4)
	assert(first.r > 0.9 and first.b < 0.1, "HD frame zero must sample its own light mask")
	material.set_shader_parameter("artwork_animation_seconds", 0.125)
	await RenderingServer.frame_post_draw
	var second := viewport.get_texture().get_image().get_pixel(4, 4)
	assert(second.b > 0.9 and second.r < 0.1, "HD animation must advance the emission UV together with its artwork")
	material.shader = CityNightLighting.EMISSION
	material.set_shader_parameter("has_emission", true)
	material.set_shader_parameter("emission", ImageTexture.create_from_image(masks))
	material.set_shader_parameter("artwork_animation_seconds", 0.125)
	await RenderingServer.frame_post_draw
	var glow := viewport.get_texture().get_image().get_pixel(4, 4)
	assert(glow.b > 0.9 and glow.r < 0.1, "Bloom must use the same animated lightmap frame as the city artwork")
	# Native grid UVs are distances, not atlas coordinates. They cannot occlude lights.
	sprite.self_modulate = Color(48.0 / 255.0, 0, 0, 1)
	await RenderingServer.frame_post_draw
	assert(viewport.get_texture().get_image().is_invisible(), "The HD grid erased underlying emission")
	viewport.queue_free()
	await process_frame


func _check_building_power() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(16, 8)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var art := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	art.fill(Color(0.4, 0.6, 0.8))
	var mask := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	mask.fill(Color(1.0, 0.5, 0.1))
	var texture := ImageTexture.create_from_image(art)
	var light := ImageTexture.create_from_image(mask)
	var material := ShaderMaterial.new()
	var sprites: Array[Sprite2D] = []
	for i in 2:
		var sprite := Sprite2D.new()
		sprite.centered = false
		sprite.position.x = i * 8
		sprite.texture = texture
		sprite.material = material
		viewport.add_child(sprite)
		sprites.append(sprite)
	for tags in [[255, 128], [2, 130], [64, 192], [65, 193]]:
		for i in 2:
			sprites[i].self_modulate = Color(float(tags[i]) / 255.0, 1.0 / 255.0, 0.0, 1.0)
		material.shader = CityMapControl.PALETTE_CYCLE_SHADER
		material.set_shader_parameter("environment_enabled", true)
		material.set_shader_parameter("environment_night", 1.0)
		material.set_shader_parameter("environment_tint", Vector3(0.2, 0.3, 0.4))
		material.set_shader_parameter("environment_has_emission", true)
		material.set_shader_parameter("environment_emission", light)
		await process_frame
		await RenderingServer.frame_post_draw
		var night := viewport.get_texture().get_image()
		assert(night.get_pixel(4, 4).r > 0.9 and night.get_pixel(12, 4).r < 0.1,
			"One unpowered building must not disable its powered neighbor sharing the same atlas")
		material.set_shader_parameter("environment_enabled", false)
		await RenderingServer.frame_post_draw
		var day := viewport.get_texture().get_image()
		assert(day.get_pixel(4, 4).is_equal_approx(day.get_pixel(12, 4)), "Power changed daytime art")
		material.shader = preload("res://src/view/environment/night_emission.gdshader")
		material.set_shader_parameter("has_emission", true)
		material.set_shader_parameter("emission", light)
		await RenderingServer.frame_post_draw
		var glow := viewport.get_texture().get_image()
		assert(glow.get_pixel(4, 4).r > 0.9 and glow.get_pixel(12, 4).r == 0.0, "Unpowered window left a glow")
		assert(glow.get_pixel(12, 4).a == 1.0, "Unpowered building must still hide lights behind it")
	viewport.queue_free()
	await process_frame
	print("PASS: per-building power gates indexed, HD and animated lights and glow; day art and occlusion preserved")


func _check_object_frame_timing() -> void:
	var images := {}
	var colors := [Color.RED, Color.GREEN, Color.BLUE, Color.YELLOW]
	for i in 4:
		var frame := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		frame.fill(colors[i])
		images[str(i)] = frame
	var loader := MasterFrameAnimation.new()
	var reader := func(path: Variant) -> Image: return images.get(path)
	var result := loader.load_frames({"frames": ["0", "1", "2", "3"], "lightmaps": ["0", "1", "2", "3"],
		"durations_ms": [125, 250, 125, 125], "playback": "ping_pong"}, images["0"], images["0"], reader, 100000)
	assert(loader.error.is_empty(), loader.error)
	# Native atlas layout: two padding rows on each side, plus outer padding.
	var art := Image.create(8, result.frames * 12 + 4, false, Image.FORMAT_RGBA8)
	var lights := Image.create(8, result.frames * 12 + 4, false, Image.FORMAT_RGBA8)
	for i in result.frames:
		art.blit_rect(result.art, Rect2i(0, i * 8, 8, 8), Vector2i(0, 2 + i * 12))
		lights.blit_rect(result.light, Rect2i(0, i * 8, 8, 8), Vector2i(0, 2 + i * 12))
	var viewport := SubViewport.new()
	viewport.size = Vector2i(8, 8)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.texture = ImageTexture.create_from_image(art)
	sprite.region_enabled = true
	sprite.region_rect = Rect2(0, 2, 8, 8)
	sprite.self_modulate = Color(64.0 / 255.0, result.frames / 255.0, 0, 12.0 / 255.0)
	var material := ShaderMaterial.new()
	sprite.material = material
	viewport.add_child(sprite)
	var expected := [0, 1, 1, 2, 3, 2, 1, 1, 0]
	for shader in [CityMapControl.PALETTE_CYCLE_SHADER, CityNightLighting.EMISSION]:
		material.shader = shader
		material.set_shader_parameter("environment_enabled", true)
		material.set_shader_parameter("environment_night", 1.0)
		material.set_shader_parameter("environment_has_emission", true)
		material.set_shader_parameter("environment_emission", ImageTexture.create_from_image(lights))
		material.set_shader_parameter("has_emission", true)
		material.set_shader_parameter("emission", ImageTexture.create_from_image(lights))
		for i in expected.size():
			material.set_shader_parameter("artwork_animation_seconds", i * 0.125 + 0.01)
			await process_frame
			await RenderingServer.frame_post_draw
			var pixel := viewport.get_texture().get_image().get_pixel(4, 4)
			assert(pixel.is_equal_approx(colors[expected[i]]), "Object frame timing and bloom must agree: %d %s" % [i, pixel])
	viewport.queue_free()
	await process_frame


func _check_parcel_border(hdr: bool) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(16, 8)
	viewport.use_hdr_2d = hdr
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var pixels := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	pixels.fill(Color("82a174"))
	var material := ShaderMaterial.new()
	material.shader = CityMapControl.PALETTE_CYCLE_SHADER
	material.set_shader_parameter("environment_lut_linear_canvas", hdr)
	for tag in [55, 2]:
		var sprite := Sprite2D.new()
		sprite.centered = false
		sprite.position.x = 0 if tag == 55 else 8
		sprite.texture = ImageTexture.create_from_image(pixels)
		sprite.self_modulate = Color(tag / 255.0, 0, 0, 1)
		sprite.material = material
		viewport.add_child(sprite)
	await RenderingServer.frame_post_draw
	var day := viewport.get_texture().get_image()
	material.set_shader_parameter("environment_enabled", true)
	material.set_shader_parameter("environment_tint", Vector3(0.28, 0.34, 0.52))
	material.set_shader_parameter("environment_weather", Vector3(0.65, 0.7, 0.75))
	material.set_shader_parameter("environment_night", 1.0)
	await RenderingServer.frame_post_draw
	var night := viewport.get_texture().get_image()
	assert(night.get_pixel(4, 4).is_equal_approx(day.get_pixel(4, 4)), "Parcel category color changed with night/weather")
	assert(night.get_pixel(12, 4).get_luminance() < day.get_pixel(12, 4).get_luminance() * 0.7, "Ordinary building artwork lost environmental lighting")
	viewport.queue_free()
	await process_frame


func _check_framed_power_warning(hdr: bool) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(8, 8)
	viewport.use_hdr_2d = hdr
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var pixels := Image.create(8, 24, false, Image.FORMAT_RGBA8)
	pixels.fill_rect(Rect2i(0, 0, 8, 12), Color.RED)
	pixels.fill_rect(Rect2i(0, 12, 8, 12), Color.GREEN)
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(pixels)
	sprite.region_enabled = true
	sprite.region_rect = Rect2(0, 2, 8, 8)
	sprite.self_modulate = Color(50.0 / 255.0, 2.0 / 255.0, 0, 12.0 / 255.0)
	var material := ShaderMaterial.new()
	material.shader = CityMapControl.PALETTE_CYCLE_SHADER
	material.set_shader_parameter("environment_lut_linear_canvas", hdr)
	material.set_shader_parameter("environment_enabled", true)
	material.set_shader_parameter("environment_tint", Vector3(0.1, 0.1, 0.1))
	material.set_shader_parameter("environment_weather", Vector3(0.2, 0.2, 0.2))
	material.set_shader_parameter("palette_cycle_enabled", true)
	var lookup := Image.create(256, 1, false, Image.FORMAT_RGBA8)
	lookup.fill(Color.BLUE)
	material.set_shader_parameter("animated_palette", ImageTexture.create_from_image(lookup))
	sprite.material = material
	viewport.add_child(sprite)
	await process_frame
	for tick in 3:
		material.set_shader_parameter("artwork_animation_seconds", tick * 0.125)
		await RenderingServer.frame_post_draw
		var shown := viewport.get_texture().get_image().get_pixel(4, 4)
		assert(shown.b < 0.01, "Frame warning was recolored by the legacy palette")
		assert((shown.r if tick % 2 == 0 else shown.g) > 0.95, "Frame warning lost animation or fullbright lighting")
	viewport.queue_free()
	await process_frame
	print("PASS: literal power-warning frames retain fullbright and loop independently of palette; HDR=", hdr)


func _check_emission_weather(hd: bool) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(16, 8)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var pixels := Image.create(16, 8, false, Image.FORMAT_RGBA8)
	pixels.fill(Color(0.6, 0.55, 0.4))
	var mask := Image.create(16, 8, false, Image.FORMAT_RGBA8)
	mask.fill_rect(Rect2i(0, 0, 4, 8), Color(1.0, 0.75, 0.3, 0.35))
	mask.fill_rect(Rect2i(4, 0, 4, 8), Color(1.0, 0.75, 0.3, 1.0))
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(pixels)
	if hd:
		sprite.modulate = Color(2.0 / 255.0, 0, 0, 1)
	var material := ShaderMaterial.new()
	material.shader = preload("res://src/view/map/palette_cycle.gdshader")
	material.set_shader_parameter("environment_enabled", true)
	material.set_shader_parameter("environment_tint", Vector3(0.28, 0.34, 0.52))
	material.set_shader_parameter("environment_emission", ImageTexture.create_from_image(mask))
	material.set_shader_parameter("environment_has_emission", true)
	material.set_shader_parameter("environment_night", 1.0)
	var profiles := CityVisualLuts.new()
	profiles.reload("")
	material.set_shader_parameter("environment_weather_luts", profiles.atlases.weather)
	sprite.material = material
	viewport.add_child(sprite)
	await RenderingServer.frame_post_draw
	var clear := viewport.get_texture().get_image()
	material.set_shader_parameter("environment_weather", Vector3(0.4, 0.45, 0.5))
	material.set_shader_parameter("environment_weather_lut_weights_a", Vector4(0, 0, 1, 0))
	material.set_shader_parameter("environment_weather_lut_strength", 1.0)
	await RenderingServer.frame_post_draw
	var rain := viewport.get_texture().get_image()
	for x in [2, 6]:
		assert(rain.get_pixel(x, 4).is_equal_approx(clear.get_pixel(x, 4)), "Rain dimmed a full or partial brightmap")
	assert(rain.get_pixel(12, 4).r < clear.get_pixel(12, 4).r - 0.02, "Rain stopped darkening unlit walls")
	material.set_shader_parameter("environment_night", 0.0)
	await RenderingServer.frame_post_draw
	var unlit := viewport.get_texture().get_image()
	assert(unlit.get_pixel(2, 4).is_equal_approx(unlit.get_pixel(12, 4)), "Disabled brightmaps still excluded weather")
	viewport.queue_free()
	await process_frame
