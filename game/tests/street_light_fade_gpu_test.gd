extends "res://tests/support/scene_test_case.gd"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _check_light_atlas()
	await _check_draw_batches()
	await _check_fade_batches()
	await _check_soft_edges()
	for zoom in [0.1, 0.25, 0.5, 1.0]:
		await _check_zoom(zoom)
	print("PASS: per-light fades at 10/25/50/100 percent, invisible prefetch, cache and camera continuity")
	quit()


func _check_light_atlas() -> void:
	var templates := CityNightTemplates.new()
	templates.defer_updates = true
	var sources: Array[Image] = []
	var packed: Array[Texture2D] = []
	var pages := {}
	for index in 140:
		var size := Vector2i(64, 64) if index % 3 == 0 else Vector2i(9, 11)
		if index == 0:
			size = Vector2i.ONE
		var pixels := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
		pixels.fill(Color.from_rgba8((index * 17) % 255, (index * 31) % 255, 180, 123))
		pixels.set_pixelv(size / 2, Color.WHITE)
		sources.append(pixels)
		var texture := templates.texture(pixels) as AtlasTexture
		assert(texture != null and templates.texture(pixels) == texture)
		packed.append(texture)
		pages[texture.atlas.get_instance_id()] = true
	templates.flush()
	assert(pages.size() < 6, "Small lights were not batched into shared GPU pages")
	templates.clear()
	for index in packed.size():
		assert(packed[index].get_image().get_data() == sources[index].get_data(), "Page rollover/lookup eviction changed retained pixels")
	var ground := CityNightGround.new()
	ground._store(Vector2i.ZERO, {"texture": packed[0], "fixtures": packed[1], "signals": [], "origin": Vector2i.ZERO})
	assert(ground.texture_bytes == CityNightTemplates.PAGE_EDGE * CityNightTemplates.PAGE_EDGE * 4, "Atlas residency must count physical pages once")
	ground.free()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(128, 96)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.position = Vector2(3.25, 4.5)
	var material := ShaderMaterial.new()
	material.shader = CityNightGround.SHADER
	material.set_shader_parameter("strength", 0.7)
	sprite.material = material
	viewport.add_child(sprite)
	for filter in [CanvasItem.TEXTURE_FILTER_NEAREST, CanvasItem.TEXTURE_FILTER_LINEAR]:
		sprite.texture_filter = filter
		for zoom in [0.25, 0.5, 1.0, 1.3]:
			sprite.scale = Vector2.ONE * zoom
			sprite.texture = ImageTexture.create_from_image(sources[3])
			await RenderingServer.frame_post_draw
			var expected := viewport.get_texture().get_image().get_data()
			sprite.texture = packed[3]
			await RenderingServer.frame_post_draw
			var actual := viewport.get_texture().get_image().get_data()
			assert(actual.size() == expected.size())
			for byte in actual.size():
				assert(absi(int(actual[byte]) - int(expected[byte])) <= 1, "Atlas changed filtered ground-light pixels")
	viewport.queue_free()
	await process_frame


func _check_draw_batches() -> void:
	var views: Array[SubViewport] = []
	var receivers: Array[CityNightGround] = []
	var templates := CityNightTemplates.new()
	var images: Array[Texture2D] = []
	for index in 4:
		var pixels := Image.create(9, 11, false, Image.FORMAT_RGBA8)
		pixels.fill(Color.from_rgba8(40 + index * 50, 180 - index * 30, 100, 110))
		images.append(templates.texture(pixels))
	for variant in 2:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(256, 160)
		viewport.transparent_bg = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		views.append(viewport)
		var ground := CityNightGround.new()
		ground.fades = CityLightFade.new()
		ground.fades.advance(17.4)
		viewport.add_child(ground)
		receivers.append(ground)
		(ground.material as ShaderMaterial).set_shader_parameter("strength", 0.7)
		ground.fixtures.modulate.a = 0.6
		for index in 140:
			var tile := Vector2i(index % 20, index / 20)
			ground.fades.starts[tile] = 17.0 - (index % 10) * 0.1
			var origin := tile * Vector2i(7, 8)
			ground._store(tile, {"texture": images[index % 4], "fixtures": images[(index + 1) % 4], "origin": origin,
				"signals": [{"axis": index % 2, "origin": origin + Vector2i(3, 2), "lenses": [images[0], images[1], images[2]]}]})
			ground.visible_tiles.append(tile)
		ground.signal_tiles.assign(ground.visible_tiles)
		ground.sync_fade_clock()
	assert(receivers[1]._sync_draw_batches())
	var counters: Array = []
	for batch in receivers[1]._draw_batches:
		var count := [0]
		counters.append(count)
		for canvas: Node2D in batch:
			canvas.draw.connect(func() -> void: count[0] += 1)
	for step in 4:
		if step == 1:
			for ground in receivers:
				var edited: Dictionary = ground.cache[Vector2i(3, 0)].duplicate()
				edited.texture = images[3]
				ground._store(Vector2i(3, 0), edited)
				ground._release(Vector2i(4, 0))
				receivers[0].queue_redraw()
				receivers[0].fixtures.queue_redraw()
				receivers[0].signals.queue_redraw()
		elif step == 2:
			for ground in receivers:
				ground.clock = 7.0
				ground.fades.advance(0.3)
				ground.sync_fade_clock()
				ground.signals.queue_redraw()
			for batch in receivers[1]._draw_batches:
				batch[2].queue_redraw()
		elif step == 3:
			for ground in receivers:
				ground.visible_tiles.resize(30)
				ground._refresh_signals()
				ground.queue_redraw()
				ground.fixtures.queue_redraw()
			assert(receivers[1]._draw_batches.is_empty(), "Shrinking views retained stale light commands")
		await RenderingServer.frame_post_draw
		var expected := views[0].get_texture().get_image().get_data()
		var actual := views[1].get_texture().get_image().get_data()
		assert(actual == expected, "Grouped light commands changed layering, blending, signals or local edits")
		if step == 0:
			for count in counters:
				count[0] = 0
		elif step == 1:
			assert(counters[0][0] == 3 and counters[1][0] == 0 and counters[2][0] == 0,
				"A local light edit rebuilt unrelated command groups")
	for viewport in views:
		viewport.queue_free()
	await process_frame


func _check_fade_batches() -> void:
	var views: Array[SubViewport] = []
	var grounds: Array[CityNightGround] = []
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.8, 0.4, 0.1, 0.7))
	var texture := ImageTexture.create_from_image(image)
	for variant in 2:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(256, 160)
		viewport.transparent_bg = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		views.append(viewport)
		var ground := CityNightGround.new()
		ground.fades = CityLightFade.new()
		ground.fades.advance(17.0)
		viewport.add_child(ground)
		grounds.append(ground)
		(ground.material as ShaderMaterial).set_shader_parameter("strength", 0.7)
		for index in 140:
			var tile := Vector2i(index % 20, index / 20)
			ground._store(tile, {"texture": texture, "fixtures": texture, "origin": tile * Vector2i(10, 12), "signals": []})
			ground.visible_tiles.append(tile)
		ground._sync_draw_batches()
	for phase in 3:
		var view := Rect2(0, 0, 90 if phase == 0 else 256, 160)
		var reference := grounds[0]
		for tile: Vector2i in reference.unseen.keys():
			if reference.fades.peek(tile, 128, 0) != CityLightFade.UNSEEN or Rect2(reference.cache[tile].origin, Vector2(64, 64)).intersects(view):
				reference.fades.birth(tile, 128, 0)
				reference.unseen.erase(tile)
				reference._redraw_batch(tile)
		grounds[1].start_visible_fades(view)
		assert(reference.fades.starts == grounds[1].fades.starts and reference.fades.revision == grounds[1].fades.revision,
			"Grouped activation changed first-visible light timestamps")
		for ground in grounds:
			ground.fades.advance(0.3)
			ground.sync_fade_clock()
		await RenderingServer.frame_post_draw
		assert(views[0].get_texture().get_image().get_data() == views[1].get_texture().get_image().get_data(),
			"Grouped fade activation changed GPU pixels")
	for viewport in views:
		viewport.queue_free()
	await process_frame


func _check_zoom(zoom: float) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(128, 64)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var fades := CityLightFade.new()
	fades.advance(17.0) # Timestamps must survive the vertex color's >1 range.
	var ground := CityNightGround.new()
	ground.fades = fades
	ground.scale = Vector2.ONE * zoom
	viewport.add_child(ground)
	(ground.material as ShaderMaterial).set_shader_parameter("strength", 1.0)
	var first := Vector2i(30, 42)
	var second := Vector2i(31, 42)
	var light := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	light.fill_rect(Rect2i(0, 16, 32, 16), Color(0.8, 0.4, 0.1, 1))
	var lamp := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	lamp.fill_rect(Rect2i(0, 0, 32, 8), Color(0.2, 0.6, 0.9, 1))
	var entry := {"texture": ImageTexture.create_from_image(light), "fixtures": ImageTexture.create_from_image(lamp), "signals": [], "origin": Vector2i.ZERO}
	ground._store(first, entry)
	ground.visible_tiles.append(first)
	ground.sync_fade_clock()
	ground.hide()
	ground.start_visible_fades(Rect2(0, 0, 128, 64))
	await RenderingServer.frame_post_draw
	assert(fades.starts.is_empty(), "Hidden preloading consumed the fade")
	ground.show()
	ground.start_visible_fades(Rect2(1000, 1000, 128, 64))
	await RenderingServer.frame_post_draw
	assert(fades.starts.is_empty(), "Offscreen drawing consumed the fade")
	ground.start_visible_fades(Rect2(0, 0, 128, 64))
	var draws := [0]
	ground.draw.connect(func() -> void: draws[0] += 1)
	await process_frame
	await RenderingServer.frame_post_draw
	var dark := viewport.get_texture().get_image()
	assert(_pixel(dark, 8, 24, zoom).r < 0.01 and _pixel(dark, 8, 4, zoom).a < 0.01, "New light appeared instantly")
	var initial_draws: int = draws[0]
	fades.advance(CityLightFade.DURATION * 0.5)
	ground.sync_fade_clock()
	await RenderingServer.frame_post_draw
	var middle := viewport.get_texture().get_image()
	assert(_pixel(middle, 8, 24, zoom).r > 0.1 and _pixel(middle, 8, 24, zoom).r < 0.7, "Ground light did not fade")
	assert(_pixel(middle, 8, 4, zoom).a > 0.35 and _pixel(middle, 8, 4, zoom).a < 0.65, "Lamp did not fade with its receiver")
	assert(draws[0] == initial_draws, "Advancing the fade rebuilt the draw list")
	var later := entry.duplicate()
	later.origin = Vector2i(48, 0)
	ground._store(second, later)
	ground.visible_tiles.append(second)
	ground.start_visible_fades(Rect2(0, 0, 128, 64))
	ground.queue_redraw()
	ground.fixtures.queue_redraw()
	await RenderingServer.frame_post_draw
	var staggered := viewport.get_texture().get_image()
	assert(_pixel(staggered, 8, 4, zoom).a > 0.35 and _pixel(staggered, 56, 4, zoom).a < 0.01, "Lights share one global fade instead of individual arrival times")
	fades.advance(CityLightFade.DURATION)
	ground.sync_fade_clock()
	await RenderingServer.frame_post_draw
	var complete := viewport.get_texture().get_image()
	assert(_pixel(complete, 8, 4, zoom).a > 0.99 and _pixel(complete, 56, 4, zoom).a > 0.99)
	assert(ground.cache[first].texture == entry.texture, "Fade replaced a cached texture")
	# A fresh artwork-size cache must reuse the same world light history.
	var small := CityNightGround.new()
	small.fades = fades
	small.scale = Vector2.ONE * zoom
	small._store(first, entry)
	small.visible_tiles.append(first)
	viewport.add_child(small)
	(small.material as ShaderMaterial).set_shader_parameter("strength", 1.0)
	small.sync_fade_clock()
	ground.hide()
	await RenderingServer.frame_post_draw
	assert(_pixel(viewport.get_texture().get_image(), 8, 4, zoom).a > 0.99, "Switching artwork size restarted a completed light")
	var birth := fades.birth(first, 128, 0)
	var rotated := first
	for rotation in range(1, 5):
		rotated = CityRotationCommand.rotate_point(rotated, 128, true)
		assert(fades.birth(rotated, 128, rotation) == birth, "Rotation restarted the light")
	small._store(first, entry.duplicate())
	small.queue_redraw()
	small.fixtures.queue_redraw()
	await RenderingServer.frame_post_draw
	assert(_pixel(viewport.get_texture().get_image(), 8, 4, zoom).a > 0.99, "Refreshing an occlusion mask restarted the light")
	fades.reset()
	small.sync_fade_clock()
	small.queue_redraw()
	small.fixtures.queue_redraw()
	await RenderingServer.frame_post_draw
	assert(_pixel(viewport.get_texture().get_image(), 8, 4, zoom).a < 0.01, "A newly opened city inherited the previous light timestamps")
	viewport.queue_free()
	await process_frame


func _pixel(pixels: Image, x: int, y: int, zoom: float) -> Color:
	return pixels.get_pixel(floori(x * zoom), floori(y * zoom))


func _check_soft_edges() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(64, 64)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var background := ColorRect.new()
	background.size = Vector2(64, 64)
	background.color = Color(0.1, 0.1, 0.1)
	viewport.add_child(background)
	var pixels := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in range(y, 32):
			pixels.set_pixel(x, y, Color(0.3, 0.25, 0.2, 1))
	var sprite := Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(pixels)
	sprite.centered = false
	sprite.scale = Vector2.ONE * 2.0
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var material := ShaderMaterial.new()
	material.shader = CityNightGround.SHADER
	material.set_shader_parameter("strength", 1.0)
	sprite.material = material
	viewport.add_child(sprite)
	await RenderingServer.frame_post_draw
	var hard := viewport.get_texture().get_image()
	material.set_shader_parameter("edge_softness", 4.0)
	await RenderingServer.frame_post_draw
	var soft := viewport.get_texture().get_image()
	assert(soft.get_pixel(32, 32).r < hard.get_pixel(32, 32).r, "RS receiver edge was not feathered")
	assert(soft.get_pixel(22, 32).is_equal_approx(hard.get_pixel(22, 32)), "Soft light leaked into an occluder")
	assert(soft.get_pixel(48, 32).is_equal_approx(hard.get_pixel(48, 32)), "Edge feathering changed the pool center")
	viewport.queue_free()
	await process_frame
