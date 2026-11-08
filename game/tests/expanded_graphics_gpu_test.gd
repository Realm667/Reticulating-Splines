extends "res://tests/support/scene_test_case.gd"
## Actual reward quads and brightmaps in both tilesets and all three views.

@warning_ignore_start("integer_division")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	assert(DisplayServer.get_name() != "headless")
	var document := Sc2xDocument.create_empty(64, "Expanded GPU fixture").document
	assert(ExpandedRules.enable(document).is_empty())
	document.set_misc_u32(Sc2MiscLayout.NORMAL_POPULATION, 4000000)
	var city := CityState.from_document(document)
	city.set_funds(1000000)
	var cells := PackedInt32Array()
	for kind in 8:
		var point := Vector2i(8 + (kind % 4) * 12, 12 + (kind / 4) * 18)
		var built := BuildingCommand.apply(city, 5, 9 + kind, point, SimLfsrRandom.new(1), SimRandom.new(1))
		assert(built.ok, built.error)
		cells.append_array(built.tile_indices)
	for index in cells:
		city.tile_flags[index] |= Sc2TileFlags.POWERED
	city.document.find_chunk("XBIT").set_decoded_payload(city.tile_flags)
	var original := FixtureGraphics.pack()
	var rs := GraphicsPack.load_root("res://../packs/standalone-graphics/graphics")
	assert(rs.error.is_empty(), rs.error)
	for pack in [original, rs]:
		for view in 3:
			var archive: Sc2SpriteArchive = pack.large_sprites if view == 2 else pack.small_medium_sprites
			ExpandedGraphics.apply(archive)
			CityBrightmaps.load_archive(archive, "", "large" if view == 2 else "small_medium")
			var context := CityGpuBuildContext.new()
			assert(context.prepare(city, pack.palette, archive, view).is_empty())
			for kind in 8:
				await _check(city, pack.palette, archive, context, kind, view)
	print("PASS: all eight reward GPU quads, day/night/power, RS/SC2K and three views")
	quit()


func _check(city: CityState, palette: Sc2Palette, archive: Sc2SpriteArchive, context: CityGpuBuildContext,
		kind: int, view: int) -> void:
	var sites := ExpandedRules.render_records(city)
	var anchor := Vector2i(sites[kind * 4 + 1], sites[kind * 4 + 2] + sites[kind * 4 + 3] - 1)
	var records: PackedInt64Array = context.builder.tile_draws(PackedInt32Array([anchor.x, anchor.y])).records
	var position := Vector2i.ZERO
	var found := false
	for at in range(0, records.size(), CityGpuBuildContext.RECORD_SIZE):
		if records[at + 5] == ExpandedRules.FIRST_SPRITE + view * 500 + kind:
			position = Vector2i(records[at], records[at + 1])
			found = true
	assert(found, "Missing reward draw %d view %d" % [kind, view])
	var bounds := Rect2i(position - Vector2i(8, 8), Vector2i(216, 144))
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
	material.set_shader_parameter("environment_emission", ImageTexture.create_from_image(result.emission_image))
	material.set_shader_parameter("environment_has_emission", true)
	mesh.material = material
	viewport.add_child(mesh)
	await RenderingServer.frame_post_draw
	var day := viewport.get_texture().get_image()
	assert(not day.is_invisible())
	material.set_shader_parameter("environment_enabled", true)
	material.set_shader_parameter("environment_night", 1.0)
	material.set_shader_parameter("environment_tint", Vector3(0.28, 0.34, 0.52))
	await RenderingServer.frame_post_draw
	var night := viewport.get_texture().get_image()
	assert(day.get_data() != night.get_data(), "Day/night must differ")
	material.set_shader_parameter("environment_has_emission", false)
	await RenderingServer.frame_post_draw
	var unlit := viewport.get_texture().get_image()
	assert(night.get_data() != unlit.get_data(), "Reward brightmap produced no GPU light")
	viewport.queue_free()
	await process_frame
