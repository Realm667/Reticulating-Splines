extends "res://tests/support/scene_test_case.gd"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for mesh in [false, true]:
		for zoom in [0.5, 1.0, 2.0]:
			await _check(mesh, zoom)
	await _check(true, 1.0, true)
	print("PASS: tree growth compositing, CPU/GPU regions, staggered arrivals, pan/zoom, subsequent edits and bounded cleanup")
	quit()


func _check(use_mesh: bool, zoom: float, hdr := false) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256, 128)
	viewport.transparent_bg = true
	viewport.use_hdr_2d = hdr
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var base := ColorRect.new()
	base.color = Color(0.1, 0.2, 0.8)
	base.size = Vector2(256, 128)
	viewport.add_child(base)
	var fade := CityTreeGrowthFade.new()
	viewport.add_child(fade)
	var layers := CityMapLayers.new(null)
	var city := CityState.from_document(EmptyCityTemplate.create(16))
	var before := _source(Color(0.8, 0.2, 0.1), use_mesh)
	var after := _source(base.color, use_mesh)
	var half := CityMapSource.new(after.size)
	if use_mesh:
		half.meshes.assign([after.meshes[0], before.meshes[1]])
	else:
		half.tiles.assign([after.tiles[0], before.tiles[1]])
	fade.observe(city, null, before, [1], 32, true)
	fade.advance(17.0)
	fade.scale = Vector2.ONE * zoom
	fade.position = Vector2(13, 9)
	await RenderingServer.frame_post_draw
	var target := _sample(viewport, fade, Vector2(8, 8))
	fade.pending[Vector2i.ZERO] = 30.0
	fade.capture(before, half, layers)
	fade.advance(0.0)
	assert(fade.active.size() == 1 and fade.retained_bytes > 0)
	await RenderingServer.frame_post_draw
	var original := _sample(viewport, fade, Vector2(8, 8))
	assert(original.r > target.r + 0.3 and original.b < target.b - 0.3, "The old region must cover new saplings at the start")
	fade.advance(CityTreeGrowthFade.DURATION * 0.5)
	await RenderingServer.frame_post_draw
	var middle := _sample(viewport, fade, Vector2(8, 8))
	var expected := original.lerp(target, 0.5)
	assert(absf(middle.r - expected.r) < 0.035 and absf(middle.b - expected.b) < 0.035, "The finished old/new region images must blend evenly")
	fade.pending[Vector2i(1, 0)] = 30.0
	fade.capture(half, after, layers)
	fade.advance(0.0)
	await RenderingServer.frame_post_draw
	assert(absf(_sample(viewport, fade, Vector2(40, 8)).r - original.r) < 0.035, "Late regions must start their own fade")
	# Camera motion changes only the transform; it must not rebuild or restart.
	var node: CanvasItem = fade.active[Vector2i.ZERO].node
	fade.position += Vector2(5, 3)
	fade.scale *= 0.75
	fade.advance(0.0)
	await RenderingServer.frame_post_draw
	assert(absf(_sample(viewport, fade, Vector2(8, 8)).r - middle.r) < 0.035)
	assert(fade.active[Vector2i.ZERO].node == node)
	# A second growth keeps the existing old image and converges to the latest.
	fade.pending[Vector2i.ZERO] = 30.0
	fade.capture(half, before, layers)
	assert(fade.active[Vector2i.ZERO].node == node and fade.active.size() == 2)
	fade.advance(CityTreeGrowthFade.DURATION)
	assert(fade.active.is_empty() and fade.retained_bytes == 0 and not fade.visible)
	await RenderingServer.frame_post_draw
	assert(absf(_sample(viewport, fade, Vector2(8, 8)).b - target.b) < 0.035)
	# A non-growth edit immediately removes the obsolete overlay.
	fade.pending[Vector2i.ZERO] = 30.0
	fade.capture(before, after, layers)
	fade.capture(after, before, layers)
	assert(fade.active.is_empty())
	fade.reset()
	assert(fade.pending.is_empty())
	viewport.queue_free()
	await process_frame


func _sample(viewport: SubViewport, fade: CityTreeGrowthFade, point: Vector2) -> Color:
	return viewport.get_texture().get_image().get_pixelv(Vector2i(fade.position + point * fade.scale))


func _source(color: Color, use_mesh: bool) -> CityMapSource:
	var source := CityMapSource.new(Vector2i(256, 128))
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(color)
	var texture := ImageTexture.create_from_image(image)
	for x in 2:
		var position := Vector2(x * 32, 0)
		if use_mesh:
			var mesh := ArrayMesh.new()
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2.ZERO, Vector2(32, 0), Vector2(32, 32), Vector2(0, 32)])
			arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN])
			arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			source.meshes.append(CityMapSource.MeshEntry.new(position, mesh, texture, 1))
		else:
			source.tiles.append(CityMapSource.TileEntry.new(position, Vector2(32, 32), texture))
	return source
