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
		var group := CanvasGroup.new()
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
		assert(absf(rendered.get_pixel(4, 28).a - 0.5) < 0.02,
			"The real city fades even when its indexed shaders replace vertex alpha")
		map.region_backdrop._set_live_opacity(1.0)
		for frame in 3:
			await RenderingServer.frame_post_draw
		assert(viewport.get_texture().get_image().get_pixel(4, 28).a > 0.99,
			"Disabling the temporary grouping pass restores the original full-opacity city")
		viewport.queue_free()
		await process_frame
	print("PASS region snapshot grayscale, 33/66 opacity, soft blur and real-color endpoints in SDR/HDR")
	quit()
