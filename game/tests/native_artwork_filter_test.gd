extends "res://tests/support/scene_test_case.gd"
## Native replacement pixels must survive camera zoom, reduced views and HD mixing.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	assert(DisplayServer.get_name() != "headless", "This regression requires GPU pixel readback")
	var source := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	for y in 8:
		for x in 8:
			source.set_pixel(x, y, Color.RED if x < 4 else Color.BLUE)
	var texture := ImageTexture.create_from_image(source)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(160, 32)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var material := ShaderMaterial.new()
	material.shader = CityMapControl.PALETTE_CYCLE_SHADER
	var page := Image.create(1024, 1024, false, Image.FORMAT_RGBA8)
	page.blit_rect(source, Rect2i(0, 0, 8, 8), Vector2i.ZERO)
	var pages := Texture2DArray.new()
	assert(pages.create_from_images([page]) == OK)
	# Two adjacent sprites in one atlas/material: native stays sharp, actual HD
	# remains filtered. No pack-wide toggle may change the second sprite.
	for variant in 6:
		var divisor: int = [1, 2, 4][variant % 3]
		var paged := variant >= 3
		material.shader = load("res://src/view/map/palette_cycle_pages.gdshader") if paged else CityMapControl.PALETTE_CYCLE_SHADER
		if paged:
			material.set_shader_parameter("region_atlas_edge", 1024.0)
			material.set_shader_parameter("region_atlas_pages", pages)
		material.set_shader_parameter("artwork_view_divisor", float(divisor))
		for zoom in [1.0, 1.5, 2.0, 4.0]:
			var nodes: Array[MeshInstance2D] = []
			for density in [1, 2]:
				var mesh := MeshInstance2D.new()
				var quad := QuadMesh.new()
				quad.size = Vector2.ONE * 8.0 / (divisor * density)
				mesh.mesh = quad
				if paged:
					var arrays := quad.surface_get_arrays(0)
					var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
					for index in uvs.size():
						uvs[index] *= 8.0 / 1024.0
					arrays[Mesh.ARRAY_TEX_UV] = uvs
					var page_mesh := ArrayMesh.new()
					page_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
					mesh.mesh = page_mesh
				mesh.texture = texture
				mesh.material = material
				mesh.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				mesh.self_modulate = Color8(2, 0, 0)
				mesh.scale = Vector2.ONE * divisor * zoom
				mesh.position = Vector2(8 + (density - 1) * 80, 0) + quad.size * mesh.scale * 0.5
				viewport.add_child(mesh)
				nodes.append(mesh)
			await RenderingServer.frame_post_draw
			var image := viewport.get_texture().get_image()
			for x in int(8 * zoom):
				var expected := Color.RED if x < 4 * zoom else Color.BLUE
				assert(image.get_pixel(8 + x, 2) == expected,
					"Native artwork interpolated at divisor %d zoom %s pixel %d" % [divisor, zoom, x])
			if zoom == 4.0:
				var blended := image.get_pixel(95, 2)
				assert(blended.r > 0.1 and blended.b > 0.1, "HD artwork lost its smooth filter")
			for node in nodes:
				node.queue_free()
			await process_frame
	viewport.queue_free()
	await process_frame
	print("PASS: native pixel edges at 3 view divisors and 4 zooms in single/paged atlases; HD/native mixing retains separate filtering")
	quit()
