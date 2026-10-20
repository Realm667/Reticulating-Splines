extends "res://tests/support/scene_test_case.gd"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(64, 24)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var sprites := CityLifeSprites.new()
	var pixels := Image.create(64, 24, false, Image.FORMAT_RGBA8)
	CityLifeCanvas.stamp(pixels, Vector2i.ZERO, sprites.sprite(false, 0, 1, 0), Vector2i(3, 3), [])
	CityLifeCanvas.stamp(pixels, Vector2i.ZERO, sprites.sprite(true, 2, 0, 0), Vector2i(20, 8), [])
	CityLifeCanvas.stamp(pixels, Vector2i.ZERO, sprites.sprite(false, 0, 1, 0, CityLifeSprites.Vehicle.TRUCK), Vector2i(32, 3), [])
	CityLifeCanvas.stamp(pixels, Vector2i.ZERO, sprites.sprite(false, 0, 1, 0, CityLifeSprites.Vehicle.BUS), Vector2i(48, 3), [])
	var artwork := Sprite2D.new()
	artwork.centered = false
	artwork.texture = ImageTexture.create_from_image(pixels)
	var material := ShaderMaterial.new()
	material.shader = preload("res://src/view/city_life/city_life.gdshader")
	artwork.material = material
	viewport.add_child(artwork)
	await process_frame
	await RenderingServer.frame_post_draw
	var original := viewport.get_texture().get_image()
	assert(original.get_pixel(0, 0).a == 0.0)
	assert(original.get_pixel(24, 6).a == 0.0)
	var car := original.get_pixel(7, 5)
	assert(car.a > 0.9 and car.r > car.b, "RGBA car colors must survive the palette-based map pipeline")
	assert(original.get_pixel(36, 6).a > 0.9 and original.get_pixel(52, 6).a > 0.9,
		"Truck cargo and bus body must survive GPU rendering")
	var cloud_field := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	cloud_field.fill(Color.WHITE)
	material.set_shader_parameter("cloud_field", ImageTexture.create_from_image(cloud_field))
	material.set_shader_parameter("cloud_enabled", true)
	material.set_shader_parameter("cloud_density", 1.0)
	await RenderingServer.frame_post_draw
	var shadow := viewport.get_texture().get_image()
	assert(shadow.get_pixel(7, 5).r < car.r, "Cloud shadows must also shade city-life figures")
	assert(shadow.get_pixel(36, 6).r < original.get_pixel(36, 6).r)
	assert(shadow.get_pixel(52, 6).r < original.get_pixel(52, 6).r)
	assert(shadow.get_pixel(0, 0).a == 0.0)
	material.set_shader_parameter("cloud_enabled", false)
	material.set_shader_parameter("environment_enabled", true)
	material.set_shader_parameter("environment_tint", Vector3(0.3, 0.4, 0.6))
	await RenderingServer.frame_post_draw
	var night := viewport.get_texture().get_image()
	assert(night.get_pixel(7, 5).r < car.r)
	assert(night.get_pixel(0, 0).a == 0.0, "Night grading must preserve sprite transparency")
	viewport.queue_free()
	await process_frame
	await _check_inclines()
	await _check_headlight_batches(false)
	await _check_headlight_batches(true)
	await _check_headlight_batches(false, 2)
	await _check_headlight_batches(false, 4)
	await _check_sparse_artwork(false)
	await _check_sparse_artwork(true)
	await _check_instances(false, 540)
	await _check_instances(true)
	await _check_hd_subpixel_motion(1)
	await _check_hd_subpixel_motion(2)
	await _check_hd_subpixel_motion(4)
	await _check_hd_subpixel_motion(1, true)
	await _check_hd_subpixel_motion(2, true)
	print("PASS: GPU city-life colors, transparent background, cloud shadows and environment lighting")
	quit()


func _check_hd_subpixel_motion(raster_scale: int, walking := false) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(128, 64)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var canvas := CityLifeCanvas.new()
	canvas.scale = Vector2.ONE * 4
	canvas.source_bounds = Rect2i(0, 0, 32, 16)
	viewport.add_child(canvas)
	var sprites := CityLifeSprites.new()
	if raster_scale > 1:
		var person := Image.create(3 * raster_scale, 6 * raster_scale, false, Image.FORMAT_RGBA8)
		person.fill(Color.WHITE)
		var reader := func(_path: String) -> Image: return person
		var authored := VisualArtwork.load_records([{
			"key": "person/0/0/0", "png": "person.png",
			"logical_size": [3, 6], "master_scale": raster_scale,
		}], reader)
		assert(authored.error.is_empty(), authored.error)
		sprites.set_artwork(authored)
	canvas.gpu = CityLifeGpu.new()
	canvas.gpu.prepare(sprites, canvas.lights)
	var sprite := sprites.sprite(walking, 0, 0 if walking else 1, 0)
	var figure := CityLifeController.Figure.new()
	figure.position = Vector2(12.25, 7)
	figure.previous_position = figure.position - Vector2.RIGHT
	figure.has_previous_position = true
	var entries: Array[Dictionary] = [{"figure": figure, "sprite": sprite, "origin": Vector2i(6, 3), "opacity": 1.0, "occluders": []}]
	canvas.gpu.render(canvas, entries)
	assert(is_equal_approx(canvas.gpu.buffers[0][3], 6.25), "HD origin was rounded to the original grid")
	var previous := -1.0
	for fraction in [0.0, 0.25, 0.5, 0.75, 1.0]:
		(canvas.gpu.groups[0].material as ShaderMaterial).set_shader_parameter("interpolation", fraction)
		await RenderingServer.frame_post_draw
		var pixels := viewport.get_texture().get_image()
		var weight := 0.0
		var center := 0.0
		for y in pixels.get_height():
			for x in pixels.get_width():
				var alpha := pixels.get_pixel(x, y).a
				weight += alpha
				center += x * alpha
		assert(weight > 0)
		center /= weight
		if previous >= 0:
			assert(absf(center - previous - 1.0) < 0.05, "HD vehicle did not advance one high-resolution pixel per quarter step")
		previous = center
	# The same control disables interpolation and restores native-pixel placement.
	var shader := canvas.gpu.groups[0].material as ShaderMaterial
	shader.set_shader_parameter("smooth_movement", false)
	shader.set_shader_parameter("interpolation", 0.0)
	await RenderingServer.frame_post_draw
	var disabled := viewport.get_texture().get_image().get_data()
	shader.set_shader_parameter("interpolation", 0.5)
	await RenderingServer.frame_post_draw
	assert(viewport.get_texture().get_image().get_data() == disabled, "Disabled smoothing still interpolated figures")
	viewport.queue_free()
	await process_frame


func _check_sparse_artwork(hdr: bool) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(768, 512)
	viewport.transparent_bg = true
	viewport.use_hdr_2d = hdr
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var canvas := CityLifeCanvas.new()
	viewport.add_child(canvas)
	var bounds := Rect2i(-19, 17, 327, 199)
	var entries: Array[Dictionary] = []
	var sprites := CityLifeSprites.new()
	var lights := CityLifeLights.new()
	var pixels := Image.create(bounds.size.x, bounds.size.y, false, Image.FORMAT_RGBA8)
	var emission := pixels.duplicate() as Image
	for i in 100:
		var sprite := sprites.sprite(i % 4 == 3, i % 12, i % 8, i % 2, i % 3)
		var origin := bounds.position + Vector2i((i * 17) % 330 - 5, (i * 3) % 200 - 4)
		var lamps := lights.lamp_mask(sprite, i % 3, i % 8)
		var opacity: float = [0.0, 0.31, 1.0][i % 3]
		entries.append({"sprite": sprite, "origin": origin, "lamps": lamps, "opacity": opacity, "occluders": []})
		CityLifeCanvas.stamp(pixels, bounds.position, sprite, origin, [], opacity, emission, lamps)
	canvas.atlas.compose(bounds, entries, true)
	var reference := Sprite2D.new()
	reference.centered = false
	reference.texture = ImageTexture.create_from_image(pixels)
	reference.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	reference.material = canvas.material.duplicate()
	viewport.add_child(reference)
	for item: CanvasItem in [canvas, reference]:
		var shader := item.material as ShaderMaterial
		shader.set_shader_parameter("environment_enabled", true)
		shader.set_shader_parameter("environment_tint", Vector3(0.3, 0.4, 0.6))
		shader.set_shader_parameter("environment_night", 0.7)
		shader.set_shader_parameter("vehicle_has_emission", true)
		shader.set_shader_parameter("vehicle_emission", canvas.emission_texture if item == canvas else ImageTexture.create_from_image(emission))
	for zoom in [0.5, 1.0, 2.0]:
		canvas.scale = Vector2.ONE * zoom
		reference.scale = canvas.scale
		canvas.position = Vector2(0.375, 0.125)
		reference.position = canvas.position
		canvas.hide()
		reference.show()
		await RenderingServer.frame_post_draw
		var expected := viewport.get_texture().get_image()
		reference.hide()
		canvas.show()
		canvas.queue_redraw()
		await RenderingServer.frame_post_draw
		assert(viewport.get_texture().get_image().get_data() == expected.get_data(),
			"Sparse GPU artwork differs at zoom %s, HDR %s" % [zoom, hdr])
	viewport.queue_free()
	await process_frame


func _check_headlight_batches(hdr: bool, raster_scale := 1) -> void:
	var city := CityState.from_document(EmptyCityTemplate.create(128))
	for x in range(57, 73):
		for y in range(57, 73):
			city.set_building_id(x, y, BuildingTileIds.ROAD_CROSSROADS)
			city.set_land_altitude(x, y, 0)
			city.set_terrain_id(x, y, 0)
	var figures: Array = []
	for i in (6 if raster_scale > 1 else 130):
		var figure := CityLifeController.Figure.new()
		figure.id = i
		@warning_ignore("integer_division")
		figure.tile = Vector2i(58 + i % 13, 58 + i / 13)
		figure.direction = i % 8
		figure.enter = (figure.direction + 2) % 4
		figure.exit = figure.direction
		if figure.direction >= 4:
			var rotation := (figure.direction - 1) % 4
			figure.enter = rotation
			figure.exit = (rotation + 1) % 4
			city.set_building_id(figure.tile.x, figure.tile.y, BuildingTileIds.ROAD_CURVE_1 + rotation)
		figure.vehicle_kind = i % 3
		figure.progress = 0.2 + (i % 3) * 0.3
		figure.visibility = 0.2 + (i % 3) * 0.3
		figure.position = CityLifePaths.point(city, figure.tile, figure.enter, figure.exit, figure.progress, false)
		figures.append(figure)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(512, 320)
	viewport.transparent_bg = true
	viewport.use_hdr_2d = hdr
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var batch := CityLifeHeadlights.new()
	batch.raster_scale = raster_scale
	viewport.add_child(batch)
	var lights := CityLifeLights.new()
	lights.set_raster_scale(raster_scale)
	var offset := Vector2i(CityLifePaths.point(city, Vector2i(64, 64), 0, 2, 0.5, false)) - Vector2i(256, 150)
	for phase in 3:
		if phase == 1:
			offset += Vector2i(7, 3)
			for figure: CityLifeController.Figure in figures:
				figure.progress = 0.75
				figure.position = CityLifePaths.point(city, figure.tile, figure.enter, figure.exit, figure.progress, false)
		elif phase == 2:
			for i in 5:
				figures.pop_front()
			figures[0].id = 900
			figures[0].tile += Vector2i.RIGHT
			figures[0].position = CityLifePaths.point(city, figures[0].tile, figures[0].enter, figures[0].exit, figures[0].progress, false)
		var reference := Node2D.new()
		viewport.add_child(reference)
		var scale_value: float = [0.5, 1.0, 2.0][phase]
		reference.scale = Vector2.ONE * scale_value
		batch.scale = reference.scale
		# Avoid sampling exactly between two HD receiver texels: Sprite2D and
		# QuadMesh interpolate opposite UV directions at that undefined boundary.
		reference.position = Vector2(0.375, 0.1875) if raster_scale > 1 else Vector2(0.375, 0.125)
		batch.position = reference.position
		for figure: CityLifeController.Figure in figures:
			var surface := lights.surface(city, figure.tile, figure.enter, figure.direction)
			var sprite := Sprite2D.new()
			sprite.centered = false
			sprite.texture = surface.texture
			if raster_scale > 1:
				var decoded := Image.create(surface.image.get_width(), surface.image.get_height(), false, Image.FORMAT_RGBAF)
				for y in decoded.get_height():
					for x in decoded.get_width():
						var encoded: Color = surface.image.get_pixel(x, y)
						if encoded.a <= 0:
							continue
						var u := (encoded.r8 << 4) | (encoded.g8 >> 4)
						var v := ((encoded.g8 & 15) << 8) | encoded.b8
						var world: Vector2 = Vector2(u, v) / 512.0 - Vector2(4, 4) + surface.world_origin
						decoded.set_pixel(x, y, Color(world.x, world.y, 0, 1))
				sprite.texture = ImageTexture.create_from_image(decoded)
			sprite.scale = Vector2.ONE / raster_scale
			sprite.position = Vector2(surface.origin - offset)
			var shader := ShaderMaterial.new()
			shader.shader = preload("res://src/view/city_life/city_life_road_light.gdshader")
			shader.set_shader_parameter("night", 0.65)
			shader.set_shader_parameter("vehicle_world", CityLifeLights.vehicle_world(city, figure))
			shader.set_shader_parameter("forward", CityLifePaths.forward(figure.direction))
			shader.set_shader_parameter("front", float([3, 4, 5][figure.vehicle_kind]))
			shader.set_shader_parameter("opacity", figure.opacity())
			shader.set_shader_parameter("smooth_receiver", raster_scale > 1)
			sprite.material = shader
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if raster_scale > 1 else CanvasItem.TEXTURE_FILTER_NEAREST
			reference.add_child(sprite)
		batch.hide()
		await RenderingServer.frame_post_draw
		var expected := viewport.get_texture().get_image()
		reference.hide()
		batch.set_night(0.65)
		var previous_bounds := batch.groups[0].multimesh.custom_aabb if not batch.groups.is_empty() else AABB()
		var previous_buffer := batch.groups[0].multimesh.buffer if not batch.groups.is_empty() else PackedFloat32Array()
		if phase == 0:
			var first: CityLifeController.Figure = figures[0]
			var prepared := lights.surface(city, first.tile, first.enter, first.direction, Callable(), false)
			assert(not batch.prepare_surface(first, prepared), "Preparation must not allocate an unbounded texture array")
			batch._add_group()
			assert(batch.prepare_surface(first, prepared))
			assert(not batch.prepare_surface(first, prepared), "An unchanged receiver must not be uploaded twice")
			assert(batch.images[batch.slots[first.id]] == prepared.image, "Daytime preparation must retain uploaded receiver images")
			# Cold first-night receivers can be transferred over several frames
			# while no incomplete geometry is visible. Final pixels stay exact.
			for i in figures.size():
				var figure: CityLifeController.Figure = figures[i]
				if not batch.slots.has(figure.id) and batch.free_slots.is_empty():
					batch._add_group()
				batch.prepare_surface(figure, lights.surface(city, figure.tile, figure.enter, figure.direction, Callable(), false))
				if i % 8 == 7:
					await process_frame
			assert(not batch._published and not batch._pending_upload)
			for group in batch.groups:
				assert(group.multimesh.buffer.count(0.0) == group.multimesh.buffer.size(),
					"Staging receivers must not publish partial light geometry")
		batch.render(city, figures, lights, offset, Callable(), {}, true)
		assert(batch._pending_upload, "Initial and warm uploads should leave the body publication frame")
		batch.set_interpolation(0.0)
		if phase > 0:
			assert(batch.groups[0].multimesh.buffer == previous_buffer, "A deferred batch must remain complete")
			assert(batch.groups[0].multimesh.custom_aabb == previous_bounds, "Deferred geometry must retain its matching culling bounds")
			assert(batch.groups[0].material.get_shader_parameter("interpolation") == 1.0, "Old lights must stay at the new body's starting position")
		else:
			assert(not batch._published, "First-night staging must keep the initial empty geometry")
		await process_frame
		batch.set_interpolation(1.0)
		assert(not batch._pending_upload and batch._published, "Receiver uploads must finish on the next presentation frame")
		for group in batch.groups.size():
			var box := batch.groups[group].multimesh.custom_aabb
			var transforms := batch.buffers[group]
			assert(box.size.z > 0.0, "Empty batches must not re-enable automatic bounds")
			for slot in CityLifeHeadlights.GROUP_SIZE:
				var at := slot * CityLifeHeadlights.STRIDE
				if transforms[at] == 0.0 or transforms[at + 5] == 0.0:
					continue
				var corner := Vector3(transforms[at + 3], transforms[at + 7], 0.0)
				assert(box.has_point(corner) and box.has_point(corner + Vector3(transforms[at] * 96, transforms[at + 5] * 96, 0)),
					"Explicit culling bounds must include every receiver after zoom, movement and slot reuse")
		batch.show()
		await RenderingServer.frame_post_draw
		var actual := viewport.get_texture().get_image()
		if actual.get_data() != expected.get_data():
			var differing := 0
			var maximum := 0.0
			for y in actual.get_height():
				for x in actual.get_width():
					var a := actual.get_pixel(x, y)
					var b := expected.get_pixel(x, y)
					var delta := maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b)))
					if delta > 0:
						differing += 1
						maximum = maxf(maximum, delta)
			print("Headlight difference: pixels=%d maximum=%s scale=%d" % [differing, maximum, raster_scale])
		assert(actual.get_data() == expected.get_data(), "Batched headlights differ from individual lights: hdr=%s phase=%d" % [hdr, phase])
		assert(batch.groups.size() == (1 if raster_scale > 1 else 3) and batch.slots.size() == figures.size())
		reference.free()
	batch.render(city, figures, lights, offset + Vector2i.ONE, Callable(), {}, true)
	assert(batch._pending_upload and batch._pending_origin_shift == -batch.scale,
		"Deferred lights must compensate for the new camera origin")
	await process_frame
	batch.set_interpolation(1.0)
	assert(not batch._pending_upload and batch._pending_origin_shift == Vector2.ZERO)
	viewport.queue_free()
	await process_frame
	print("PASS: batched headlights match individual GPU pixels at three zooms, including HDR, fades, movement and slot reuse")


func _check_instances(hdr: bool, count := 150) -> void:
	var viewport := SubViewport.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.size = Vector2i(400, 300)
	viewport.transparent_bg = true
	viewport.use_hdr_2d = hdr
	root.add_child(viewport)
	var canvas := CityLifeCanvas.new()
	canvas.source_bounds = Rect2i(0, 0, 400, 300)
	viewport.add_child(canvas)
	var sprites := CityLifeSprites.new()
	canvas.gpu = CityLifeGpu.new()
	canvas.gpu.prepare(sprites, canvas.lights)
	var entries: Array[Dictionary] = []
	var mask := Image.create(400, 300, false, Image.FORMAT_RGBA8)
	mask.fill_rect(Rect2i(90, 0, 5, 300), Color.WHITE)
	for i in count:
		var figure := CityLifeController.Figure.new()
		figure.id = i
		figure.tile = Vector2i(i, 0)
		var walking := i % 4 == 3
		var sprite := sprites.sprite(walking, i % 18, i % 8, i % 2, 0 if walking else i % 3)
		var point := Vector2i(3 + (i * 23) % 370, 3 + (i * 17) % 260)
		figure.position = point
		canvas._occluder_bounds[Vector3i(i, 0, 0)] = Rect2i(point, Vector2i(64, 48))
		entries.append({"figure":figure,"sprite":sprite,"origin":point,"opacity":1.0,"occluders":[{"origin":Vector2i.ZERO,"image":mask}]})
	var reference := Sprite2D.new()
	reference.centered = false
	reference.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	viewport.add_child(reference)
	for phase in (4 if count > CityLifeGpu.MASK_LAYERS else 3):
		if phase == 1:
			entries.reverse()
			var original_pages := canvas.gpu.masks.duplicate()
			var signature := canvas._occlusion_signature
			canvas.gpu._select_mask_bank([7, 1, null, 2, 1])
			assert(canvas.gpu.masks[0] != original_pages[0])
			canvas.gpu._select_mask_bank(signature)
			assert(canvas.gpu.masks == original_pages, "Zoom must restore the existing GPU mask pages")
		elif phase == 2:
			mask.fill_rect(Rect2i(90, 0, 5, 300), Color.TRANSPARENT)
			mask = mask.duplicate()
			for entry in entries:
				entry.occluders = [{"origin":Vector2i.ZERO,"image":mask}]
		elif phase == 3:
			mask.fill_rect(Rect2i(120, 0, 8, 300), Color.WHITE)
			mask = mask.duplicate()
			for index in entries.size():
				var entry := entries[index]
				entry.figure.tile = Vector2i(1000 + index, 0)
				entry.occluders = [{"origin": Vector2i.ZERO, "image": mask}]
				canvas._occluder_bounds[Vector3i(1000 + index, 0, 0)] = Rect2i(entry.origin, Vector2i(64, 48))
		var pixels := Image.create(400, 300, false, Image.FORMAT_RGBA8)
		for entry in entries:
			CityLifeCanvas.stamp(pixels, Vector2i.ZERO, entry.sprite, entry.origin, entry.occluders)
		reference.texture = ImageTexture.create_from_image(pixels)
		if phase == 0:
			canvas._occlusion_signature = [7, 1, null, 1, 1]
			var steps := 0
			while not canvas.gpu.prepare_masks(canvas, entries, 250):
				steps += 1
				assert(steps <= entries.size(), "Budgeted mask preparation failed to progress")
				await process_frame
			assert(steps > 0 and canvas.gpu.groups.is_empty(), "Cold masks must prepare before publishing a new draw")
		canvas.gpu.render(canvas, entries)
		assert(canvas.gpu.mask_slots.size() <= CityLifeGpu.MASK_CAPACITY and canvas.gpu.cropped.size() <= CityLifeGpu.MASK_CAPACITY)
		if phase == 1:
			assert(canvas.gpu.upload_bytes <= canvas.gpu.groups.size() * CityLifeGpu.GROUP * 96, "Cross-group depth sorting must reuse global mask slots without image uploads")
		for zoom in [0.5, 0.75, 1.0, 1.5, 2.0, 3.0]:
			canvas.scale = Vector2.ONE * zoom
			reference.scale = canvas.scale
			canvas.hide()
			reference.show()
			await RenderingServer.frame_post_draw
			var expected := viewport.get_texture().get_image()
			assert(not expected.is_invisible(), "GPU reference viewport did not render")
			reference.hide()
			canvas.show()
			await RenderingServer.frame_post_draw
			var actual := viewport.get_texture().get_image()
			assert(actual.get_data() == expected.get_data(), "Instanced figures differ: phase %s zoom %s HDR %s" % [phase, zoom, hdr])
		# Repeated draws reuse the same world mask pages and upload only small streams.
		canvas.gpu.render(canvas, entries)
		assert(canvas.gpu.upload_bytes <= canvas.gpu.groups.size() * CityLifeGpu.GROUP * 96)
	# Interpolation reads the previous published position without changing movement.
	for entry in entries:
		entry.figure.previous_position = entry.figure.position - Vector2(4,0)
		entry.figure.has_previous_position = true
	canvas.gpu.render(canvas, entries)
	for group in canvas.gpu.groups:
		(group.material as ShaderMaterial).set_shader_parameter("interpolation",0.5)
	canvas.scale = Vector2.ONE
	reference.scale = Vector2.ONE
	var interpolated := Image.create(400,300,false,Image.FORMAT_RGBA8)
	for entry in entries:
		CityLifeCanvas.stamp(interpolated,Vector2i.ZERO,entry.sprite,entry.origin-Vector2i(2,0),entry.occluders)
	reference.texture = ImageTexture.create_from_image(interpolated)
	canvas.hide()
	reference.show()
	await RenderingServer.frame_post_draw
	var midpoint := viewport.get_texture().get_image()
	canvas.show()
	reference.hide()
	await RenderingServer.frame_post_draw
	assert(viewport.get_texture().get_image().get_data() == midpoint.get_data(), "Interpolated figures or world masks slipped")
	var light_output := Node2D.new()
	viewport.add_child(light_output)
	canvas.gpu.blend = 1.0
	canvas.gpu.sync_emission(light_output)
	var pixels := Image.create(400,300,false,Image.FORMAT_RGBA8)
	var lamps := pixels.duplicate()
	for entry in entries:
		var index: int = entry.figure.id
		var light := canvas.lights.lamp_mask(entry.sprite,index%3,index%8) if index%4!=3 else null
		CityLifeCanvas.stamp(pixels,Vector2i.ZERO,entry.sprite,entry.origin,entry.occluders,1.0,lamps,light)
	reference.texture = ImageTexture.create_from_image(pixels)
	var emission_material := ShaderMaterial.new()
	emission_material.shader = CityNightLighting.EMISSION
	emission_material.set_shader_parameter("has_emission",true)
	emission_material.set_shader_parameter("emission",ImageTexture.create_from_image(lamps))
	reference.material = emission_material
	canvas.hide()
	light_output.hide()
	reference.show()
	await RenderingServer.frame_post_draw
	var expected_lamps := viewport.get_texture().get_image()
	reference.hide()
	light_output.show()
	await RenderingServer.frame_post_draw
	assert(viewport.get_texture().get_image().get_data() == expected_lamps.get_data(), "Instanced emissions changed foreground coverage")
	print("PASS: instanced figure pixels, mask invalidation, interpolation and emissions in HDR %s" % hdr)
	viewport.queue_free()
	await process_frame


func _check_inclines() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(160, 120)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var canvas := CityLifeCanvas.new()
	canvas.scale = Vector2.ONE * 2
	canvas.source_bounds = Rect2i(0, 0, 80, 60)
	viewport.add_child(canvas)
	var sprites := CityLifeSprites.new()
	canvas.gpu = CityLifeGpu.new()
	canvas.gpu.prepare(sprites, canvas.lights)
	var reference := Sprite2D.new()
	reference.centered = false
	reference.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	viewport.add_child(reference)
	for kind in 3:
		var sprite := sprites.sprite(false, 0, 1, 0, kind)
		var figure := CityLifeController.Figure.new()
		figure.position = Vector2(25, 30)
		var entries: Array[Dictionary] = [{"figure": figure, "sprite": sprite, "origin": Vector2i(20, 20), "opacity": 1.0, "occluders": []}]
		for shear in [-0.75, 0.0, 0.75]:
			entries[0].shear = shear
			reference.texture = ImageTexture.create_from_image(sprite)
			reference.transform = Transform2D(Vector2(2, 2 * shear), Vector2(0, 2), Vector2(40, 40 - 2 * shear * floorf(sprite.get_width() * 0.5)))
			canvas.hide()
			reference.show()
			await RenderingServer.frame_post_draw
			var expected := viewport.get_texture().get_image()
			canvas.gpu.render(canvas, entries)
			reference.hide()
			canvas.show()
			await RenderingServer.frame_post_draw
			var actual := viewport.get_texture().get_image()
			assert(actual.get_data() == expected.get_data(), "Sloped vehicle differs from projected source artwork: kind=%d shear=%s" % [kind, shear])
	viewport.queue_free()
	await process_frame
	print("PASS: cars, trucks and buses follow uphill/downhill projection without replacing their artwork")
