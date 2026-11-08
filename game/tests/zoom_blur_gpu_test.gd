extends "res://tests/support/scene_test_case.gd"


func _initialize() -> void:
	_run.call_deferred()


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
	map.set_process(false)
	var pixels := Image.create(256, 192, false, Image.FORMAT_RGBA8)
	for y in 192:
		for x in 256:
			pixels.set_pixel(x, y, Color.WHITE if x % 4 < 2 else Color.BLACK)
	var artwork := TextureRect.new()
	artwork.texture = ImageTexture.create_from_image(pixels)
	artwork.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	artwork.size = map.size
	map.add_child(artwork)
	map.move_child(artwork, map.layers.overlay_layer.get_index())
	var marker := ColorRect.new()
	marker.position = Vector2(40, 4)
	marker.size = Vector2(8, 8)
	marker.color = Color.GREEN
	map.layers.overlay_layer.add_child(marker)
	var effect := map.zoom_blur
	effect.update(map)
	assert(effect.canvas == null, "An idle camera must not allocate a screen pass")
	await RenderingServer.frame_post_draw
	var original := viewport.get_texture().get_image()
	map.camera._zoom_anchor = Vector2(128, 96)
	map.camera._zoom_from = 1.0
	map.camera._zoom_to = 2.0
	map.camera._zoom_elapsed = CityMapCamera.ZOOM_TRANSITION_SECONDS * 0.5
	effect.update(map)
	await RenderingServer.frame_post_draw
	var blurred := viewport.get_texture().get_image()
	var edge := blurred.get_pixel(45, 110)
	assert(edge.r > 0.05 and edge.r < 0.95, "Zoom motion must soften resolved city pixels")
	assert(absf(edge.r - edge.g) < 0.005, "Adjacent red interface must not bleed into the city")
	assert(blurred.get_pixel(31, 110) == Color.RED, "Interface outside the map remains untouched")
	assert(blurred.get_pixel(75, 30) == Color.GREEN, "Tool overlays remain sharp")
	assert(absf(blurred.get_pixel(160, 120).r - original.get_pixel(160, 120).r) < 0.02,
		"The stationary zoom anchor must remain sharp")
	# Camera centering beside a sidebar must not leave its lower artwork sharp.
	map.camera_view_rect = Rect2(64, 0, 192, 192)
	effect.update(map)
	await RenderingServer.frame_post_draw
	assert(viewport.get_texture().get_image().get_data() == blurred.get_data())
	var retained := effect.canvas
	var late := ColorRect.new()
	late.size = Vector2(4, 4)
	late.color = Color.BLUE
	map.add_child(late)
	map.move_child(late, map.layers.overlay_layer.get_index())
	effect.update(map)
	assert(effect.canvas == retained and effect.canvas.get_index() > late.get_index())
	assert(effect.canvas.get_index() < map.layers.overlay_layer.get_index())
	late.hide()
	map.camera.cancel_zoom_animation()
	assert(not effect.canvas.visible and effect.copy.copy_mode == BackBufferCopy.COPY_MODE_DISABLED)
	await RenderingServer.frame_post_draw
	assert(viewport.get_texture().get_image().get_data() == original.get_data(), "Cancellation restores exact pixels immediately")
	# Retain the map-rectangle projection after a resize and non-integer scale.
	map.size = Vector2(192, 128)
	map.camera_view_rect = Rect2(48, 0, 144, 128)
	map.scale = Vector2(1.5, 1.5)
	artwork.size = map.size
	await RenderingServer.frame_post_draw
	var resized := viewport.get_texture().get_image()
	map.camera._zoom_anchor = Vector2(96, 64)
	map.camera._zoom_from = 2.0
	map.camera._zoom_to = 1.0
	map.camera._zoom_elapsed = CityMapCamera.ZOOM_TRANSITION_SECONDS * 0.5
	effect.update(map)
	await RenderingServer.frame_post_draw
	var scaled := viewport.get_texture().get_image()
	assert(scaled.get_region(Rect2i(40, 90, 50, 20)).get_data() != resized.get_region(Rect2i(40, 90, 50, 20)).get_data())
	assert(scaled.get_pixel(31, 110) == Color.RED)
	map.zoom_factor = 1.0
	assert(not effect.canvas.visible and effect.copy.copy_mode == BackBufferCopy.COPY_MODE_DISABLED)
	await RenderingServer.frame_post_draw
	assert(viewport.get_texture().get_image().get_data() == resized.get_data(), "Explicit camera loads restore exact pixels")
	map.queue_free()
	await process_frame
	await process_frame
	assert(not is_instance_valid(effect.canvas))
	viewport.queue_free()
	await process_frame
	print("PASS: radial zoom blur, stationary anchor, sharp UI, exact cancellation, resize, reverse zoom, layer order and cleanup")
	quit()
