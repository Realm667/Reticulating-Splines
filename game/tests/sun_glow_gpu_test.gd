extends "res://tests/support/scene_test_case.gd"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for hdr in [false, true]:
		await _check(hdr)
	print("PASS: radial dawn/dusk hue, motion, smooth fade, sidebar coverage, sharp overlays, off/resize and cleanup in SDR/HDR")
	quit()


func _check(hdr: bool) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(400, 300)
	viewport.use_hdr_2d = hdr
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var outside := ColorRect.new()
	outside.color = Color.RED
	outside.size = Vector2(viewport.size)
	viewport.add_child(outside)
	var map := CityMapControl.new()
	map.position = Vector2(20, 20)
	map.size = Vector2(360, 260)
	map.camera_view_rect = Rect2(80, 0, 280, 260)
	viewport.add_child(map)
	var ground := ColorRect.new()
	ground.color = Color(0.1, 0.1, 0.1)
	ground.size = map.size
	map.add_child(ground)
	map.move_child(ground, map.layers.overlay_layer.get_index())
	var marker := ColorRect.new()
	marker.position = Vector2(25, 65)
	marker.size = Vector2(10, 10)
	marker.color = Color.GREEN
	map.layers.overlay_layer.add_child(marker)
	var options := VisualEnhancementOptions.normalize({})
	var glow := CitySunGlow.new()
	glow.update(map, true, options, 12.0)
	assert(glow.rect == null, "Midday must not allocate an effect pass")
	await RenderingServer.frame_post_draw
	var original := viewport.get_texture().get_image()
	glow.update(map, true, options, 7.0)
	await RenderingServer.frame_post_draw
	var dawn := viewport.get_texture().get_image()
	var left := dawn.get_pixel(55, 110)
	assert(left.b > left.r and left.r > original.get_pixel(55, 110).r)
	assert(dawn.get_pixel(55, 110) != original.get_pixel(55, 110), "Map below sidebar must receive the same glow")
	assert(dawn.get_pixel(365, 260) == original.get_pixel(365, 260))
	assert(dawn.get_pixel(48, 88) == Color.GREEN, "Map overlay must remain sharp and untinted")
	assert(dawn.get_pixel(10, 110) == Color.RED, "Effect must stay inside city view")
	assert(absf(dawn.get_pixel(80, 100).b - dawn.get_pixel(100, 80).b) < 0.005, "Radial distance must use pixels, not stretched UV axes")
	glow.update(map, true, options, 6.01)
	await RenderingServer.frame_post_draw
	var entering := viewport.get_texture().get_image().get_pixel(55, 110)
	assert(entering.b < left.b, "Beginning of dawn must fade in")
	glow.update(map, true, options, 19.0)
	await RenderingServer.frame_post_draw
	var dusk := viewport.get_texture().get_image().get_pixel(300, 100)
	assert(dusk.r > dusk.g and dusk.g > dusk.b)
	glow.update(map, true, options, 18.5)
	await RenderingServer.frame_post_draw
	var early := viewport.get_texture().get_image()
	glow.update(map, true, options, 19.5)
	await RenderingServer.frame_post_draw
	var late := viewport.get_texture().get_image()
	assert(early.get_data() == late.get_data(), "Dusk stays anchored to the upper right")
	glow.advance_weather(false, 0.75)
	glow.update(map, true, options, 19.0)
	await RenderingServer.frame_post_draw
	var fading := viewport.get_texture().get_image().get_pixel(300, 100)
	assert(fading.r > original.get_pixel(300, 100).r and fading.r < dusk.r)
	glow.advance_weather(false, 0.75)
	glow.update(map, true, options, 19.0)
	assert(not glow.rect.visible)
	glow.advance_weather(true, 1.5)
	glow.update(map, true, options, 19.0)
	assert(glow.rect.visible)
	glow.update(map, false, options, 7.0)
	await RenderingServer.frame_post_draw
	assert(viewport.get_texture().get_image().get_data() == original.get_data())
	options.day_enabled = false
	glow.update(map, true, options, 7.0)
	assert(not glow.rect.visible)
	options.day_enabled = true
	map.size = Vector2(300, 200)
	map.camera_view_rect = Rect2(80, 0, 220, 200)
	glow.update(map, true, options, 7.0)
	assert(glow.rect.size == map.size)
	assert(glow.material.get_shader_parameter("canvas_size") == map.size)
	map.queue_free()
	await process_frame
	await process_frame
	assert(not is_instance_valid(glow.rect))
	viewport.queue_free()
	await process_frame
	await process_frame
