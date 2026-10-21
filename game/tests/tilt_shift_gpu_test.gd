extends "res://tests/support/scene_test_case.gd"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(512, 320)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var surround := ColorRect.new()
	surround.size = Vector2(viewport.size)
	surround.color = Color.RED
	viewport.add_child(surround)
	var map := CityMapControl.new()
	map.position = Vector2(32, 24)
	map.size = Vector2(256, 192)
	viewport.add_child(map)
	var pixels := Image.create(256, 192, false, Image.FORMAT_RGBA8)
	for y in 192:
		for x in 256:
			pixels.set_pixel(x, y, Color.WHITE if (x % 4) < 2 else Color.BLACK)
	var artwork := TextureRect.new()
	artwork.texture = ImageTexture.create_from_image(pixels)
	artwork.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	artwork.size = map.size
	map.add_child(artwork)
	map.move_child(artwork, map.layers.overlay_layer.get_index())
	var marker := ColorRect.new()
	marker.position = Vector2(90, 4)
	marker.size = Vector2(8, 8)
	marker.color = Color.GREEN
	map.layers.overlay_layer.add_child(marker)
	var effect := CityTiltShift.new()
	var options := VisualEnhancementOptions.normalize({})
	options.tilt_shift_enabled = false
	effect.update(map, true, options)
	assert(effect.canvas == null, "Disabled effect must not allocate a screen pass")
	await RenderingServer.frame_post_draw
	var original := viewport.get_texture().get_image()
	options.tilt_shift_enabled = true
	options.tilt_shift_strength = 0.7
	effect.update(map, true, options)
	await RenderingServer.frame_post_draw
	var blurred := viewport.get_texture().get_image()
	assert(blurred.get_region(Rect2i(32, 90, 256, 50)).get_data() == original.get_region(Rect2i(32, 90, 256, 50)).get_data(),
		"The focus band must remain pixel-exact")
	for y in [28, 210]:
		var pixel := blurred.get_pixel(75, y)
		assert(pixel.r > 0.1 and pixel.r < 0.9, "Both edges must blur the resolved artwork")
		assert(absf(pixel.r - pixel.g) < 0.005, "Red interface pixels must not bleed into the map")
	assert(blurred.get_pixel(124, 30) == Color.GREEN, "Selection overlay must stay sharp")
	assert(blurred.get_pixel(31, 30) == Color.RED, "Interface outside the map must stay untouched")
	# The camera centers beside a sidebar, but artwork remains visible below
	# that sidebar. Its left-hand pixels need the same postprocessing pass.
	map.camera_view_rect = Rect2(64, 0, 192, 192)
	effect.update(map, true, options)
	await RenderingServer.frame_post_draw
	var sidebar := viewport.get_texture().get_image()
	assert(sidebar.get_region(Rect2i(32, 190, 80, 24)).get_data() == blurred.get_region(Rect2i(32, 190, 80, 24)).get_data(),
		"Camera centering beside the sidebar must not clip blur below it")
	assert(sidebar.get_pixel(124, 30) == Color.GREEN, "Selection must remain above the full-width blur")
	# Maximum strength must still blur regular pixel patterns instead of
	# aliasing back to the unblurred grid. Edge size moves the focus boundary.
	options.tilt_shift_strength = 1.0
	options.tilt_shift_edge = 0.1
	effect.update(map, true, options)
	await RenderingServer.frame_post_draw
	var narrow := viewport.get_texture().get_image()
	assert(narrow.get_pixel(75, 28).r > 0.1 and narrow.get_pixel(75, 28).r < 0.9)
	assert(narrow.get_region(Rect2i(32, 60, 256, 100)).get_data() == original.get_region(Rect2i(32, 60, 256, 100)).get_data())
	options.tilt_shift_edge = 0.45
	options.tilt_shift_transition = 1.0
	effect.update(map, true, options)
	await RenderingServer.frame_post_draw
	var broad := viewport.get_texture().get_image()
	assert(broad.get_region(Rect2i(40, 60, 60, 10)).get_data() != narrow.get_region(Rect2i(40, 60, 60, 10)).get_data())
	options.tilt_shift_edge = 0.28
	options.tilt_shift_transition = 0.75
	# New effects may be created after this pass. Reposition before selection,
	# after the late weather/light layer, without adding nodes each frame.
	var late := ColorRect.new()
	map.add_child(late)
	map.move_child(late, map.layers.overlay_layer.get_index())
	var retained := effect.canvas
	effect.update(map, true, options)
	assert(effect.canvas == retained and effect.canvas.get_index() > late.get_index())
	assert(effect.canvas.get_index() < map.layers.overlay_layer.get_index())
	for mode in [0, 1, 2]:
		options.tilt_shift_enabled = mode != 0
		options.tilt_shift_strength = 0.0 if mode == 1 else 0.7
		effect.update(map, mode != 2, options)
		assert(not effect.canvas.visible and effect.copy.copy_mode == BackBufferCopy.COPY_MODE_DISABLED)
		await RenderingServer.frame_post_draw
		assert(viewport.get_texture().get_image().get_data() == original.get_data(), "Off, zero strength and inactive views must restore exact pixels")
	# Resizing and display scaling keep the focus band tied to the map viewport.
	map.size = Vector2(192, 128)
	map.camera_view_rect = Rect2(48, 0, 144, 128)
	map.scale = Vector2(1.5, 1.5)
	artwork.size = map.size
	await RenderingServer.frame_post_draw
	var resized := viewport.get_texture().get_image()
	options.tilt_shift_enabled = true
	effect.update(map, true, options)
	await RenderingServer.frame_post_draw
	var scaled := viewport.get_texture().get_image()
	assert(effect.rect.size == map.size)
	assert(scaled.get_region(Rect2i(32, 90, 288, 50)).get_data() == resized.get_region(Rect2i(32, 90, 288, 50)).get_data())
	assert(scaled.get_region(Rect2i(40, 26, 60, 20)).get_data() != resized.get_region(Rect2i(40, 26, 60, 20)).get_data())
	map.queue_free()
	await process_frame
	assert(not is_instance_valid(effect.canvas), "Map owns and releases the effect nodes")
	viewport.queue_free()
	await process_frame
	print("PASS: tilt shift edges, exact focus band and off state, sharp interface, layer ordering, resize, scaling and cleanup")
	quit()
