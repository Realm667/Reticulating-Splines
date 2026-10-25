extends "res://tests/support/scene_test_case.gd"
## Exercise actual mixed-family atlas quads, not a manually tagged stand-in.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	assert(DisplayServer.get_name() != "headless")
	var original := FixtureGraphics.pack()
	var rs := GraphicsPack.load_root("res://../packs/standalone-graphics/graphics")
	assert(rs.error.is_empty(), rs.error)
	var mixer := BuildingVariants.new()
	mixer.packs = [{"large": rs.large_sprites, "small": rs.small_medium_sprites, "weight": 100, "families": {}}]
	var options := BuildingVariants.normalize({"enabled": true, "original_weight": 0, "rs_weight": 100})
	mixer.prepare_families(original.large_sprites, original.small_medium_sprites, options)
	for mixed in [false, true]:
		for view in 3:
			var archive := (rs.large_sprites if view == 2 else rs.small_medium_sprites)
			if mixed:
				archive = mixer.apply_to(original.large_sprites if view == 2 else original.small_medium_sprites, options)
			CityBrightmaps.load_archive(archive, "", "large" if view == 2 else "small_medium")
			for building in [202, 220]:
				await _check(archive, original.palette, building, view, mixed)
	print("PASS: RS pump and power-plant frames animate in actual native GPU atlases, standalone/mixed, all three views")
	quit()


func _check(archive: Sc2SpriteArchive, palette: Sc2Palette, building: int, view: int, mixed: bool) -> void:
	var city := CityState.from_document(EmptyCityTemplate.create(128))
	city.set_building_id(64, 64, building)
	city.set_building_corners(64, 64, 0x80)
	var context := CityGpuBuildContext.new()
	assert(context.prepare(city, palette, archive, view).is_empty())
	var records: PackedInt64Array = context.builder.tile_draws(PackedInt32Array([64,64])).records
	var position := Vector2i.ZERO
	var found := false
	for at in range(0, records.size(), CityGpuBuildContext.RECORD_SIZE):
		if records[at + 5] % 500 == building:
			position = Vector2i(records[at], records[at + 1])
			assert((records[at + 5] >= BuildingVariants.FIRST) == mixed)
			found = true
	assert(found)
	var bounds := Rect2i(position - Vector2i(24,24), Vector2i(192,192))
	var result := context.render(city, palette, archive, bounds, view, CityViewMode.Mode.CITY, true, true, 0, -1, true, true)
	assert(result.ok, result.error)
	var viewport := SubViewport.new()
	viewport.size = bounds.size
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var mesh := MeshInstance2D.new()
	var geometry := ArrayMesh.new()
	geometry.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, result.gpu_arrays, [], {}, Mesh.ARRAY_FLAG_USE_2D_VERTICES)
	mesh.mesh = geometry
	mesh.texture = ImageTexture.create_from_image(result.atlas_image)
	mesh.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var material := ShaderMaterial.new()
	material.shader = CityMapControl.PALETTE_CYCLE_SHADER
	material.set_shader_parameter("artwork_view_divisor", float(4 >> view))
	mesh.material = material
	viewport.add_child(mesh)
	var first: PackedByteArray
	var differs := false
	for phase in 8:
		material.set_shader_parameter("artwork_animation_seconds", float(phase) / 8.0)
		await RenderingServer.frame_post_draw
		var pixels := viewport.get_texture().get_image().get_data()
		if phase == 0:
			first = pixels
		else:
			differs = differs or pixels != first
	assert(differs, "Frozen RS animation: building %d view %d mixed %s" % [building, view, mixed])
	viewport.queue_free()
	await process_frame
