extends "res://tests/city_gpu_geometry_test.gd"
## Every water form through the production Models/atlas path, without city edits.
@warning_ignore_start("integer_division")
const Q = preload("res://tests/quarter_terrain_test.gd")
const State = preload("res://tests/support/document_state.gd")


static func shapes() -> Array[int]:
	var result: Array[int] = []
	for limits in [[0x10,0x1f],[0x20,0x40],[0x40,0x46]]:
		for shape in range(limits[0],limits[1]):
			result.append(shape)
	return result


static func fixture(quarter: bool) -> CityState:
	var city := Q.fixture() if quarter else CityState.from_document(Sc2xDocument.create_empty(64,"Water models").document)
	for shape in shapes().size():
		for phase in 4:
			var n := shape*4+phase
			var tile := Vector2i(3+(n%15)*4,3+(n/15)*4)
			var corners: Array = [[12,12,12,12],[12,13,13,12],[12,16,16,12],[12,20,20,12]][phase]
			if quarter:
				Q.set_corners(city,tile,corners)
			else:
				city.set_land_altitude(tile.x,tile.y,3)
			city.set_water_altitude(tile.x,tile.y,4)
			city.set_tile_flag(tile.x,tile.y,Sc2TileFlags.WATER,true)
			city.set_terrain_id(tile.x,tile.y,shapes()[shape])
	return city


func _run() -> void:
	assert(DisplayServer.get_name()!="headless")
	var pack := FixtureGraphics.pack()
	var cases := 0
	for quarter in [false,true]:
		var city := fixture(quarter)
		for archive: Sc2SpriteArchive in [pack.large_sprites,pack.small_medium_sprites]:
			CitySeasonColors.prepare(archive,pack.palette)
			CityNetworkModels.configure(archive,pack.palette,true)
		for turn in 4:
			var original := State.capture(city.document)
			for view in 3:
				var archive := pack.large_sprites if view==2 else pack.small_medium_sprites
				var bounds := Rect2i(Vector2i.ZERO,CityIsometricRenderer.output_size_for_view(view,64))
				await _compare(city,Sc2Palette.index_encoding(),archive,bounds,view,CityViewMode.Mode.CITY,CityGpuBuildContext.new())
				cases+=1
				# Hidden water must expose the actual land rather than keep a cap.
				if turn==0:
					var hidden := CityViewFilter.surface_copy(city,{"water":false})
					await _compare(hidden,Sc2Palette.index_encoding(),archive,bounds,view,CityViewMode.Mode.CITY,CityGpuBuildContext.new())
					cases+=1
			assert(State.capture(city.document)==original,"Model rendering must preserve every saved byte")
			assert(CityRotationCommand.apply(city,true).ok)
		await _animation(city,pack)
	for archive: Sc2SpriteArchive in [pack.large_sprites,pack.small_medium_sprites]:
		CityNetworkModels.configure(archive,pack.palette,false)
		CitySeasonColors.prepare(archive,pack.palette)
	print("PASS: %d exact native CPU/GPU water-model pairs; all 53 forms, four profiles, rotations, hidden-water and palette/flow animation"%cases)
	quit()


func _animation(city: CityState, pack: GraphicsPack) -> void:
	var archive := pack.large_sprites
	var context := CityGpuBuildContext.new()
	assert(context.prepare(city,Sc2Palette.index_encoding(),archive,2).is_empty())
	var tile := Vector2i(3+(shapes().find(0x3e)*4%15)*4,3+(shapes().find(0x3e)*4/15)*4)
	var records := context.tile_draws([tile])
	assert(records.records.size()==14)
	var image: Image = records.images[records.records[4]]
	assert(image.has_meta("quarter_model"),"The waterfall is spatial artwork")
	var changed := 0
	var map0 := pack.palette.animation_index_map(0)
	var map1 := pack.palette.animation_index_map(5)
	for pixel in image.get_data().size()/4:
		var color := image.get_pixel(pixel%image.get_width(),pixel/image.get_width())
		if color.a8!=0 and pack.palette.color(map0[color.r8])!=pack.palette.color(map1[color.r8]):
			changed+=1
	assert(changed>0,"Indexed falling water retains its actual SC2000 animation addresses")
	var bounds := Rect2i(Vector2i(records.records[0],records.records[1]),image.get_size())
	var region := CityGpuRegionRenderer.render(city,Sc2Palette.index_encoding(),archive,bounds,2,CityViewMode.Mode.CITY,true,true,context,1,-1)
	assert(region.ok)
	var viewport := SubViewport.new()
	viewport.size=bounds.size
	viewport.transparent_bg=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var canvas := MeshInstance2D.new()
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,region.gpu_arrays,[],{},Mesh.ARRAY_FLAG_USE_2D_VERTICES)
	canvas.mesh=mesh
	canvas.texture=ImageTexture.create_from_image(region.atlas_image)
	canvas.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	var material := ShaderMaterial.new()
	material.shader=CityMapControl.PALETTE_CYCLE_SHADER
	material.set_shader_parameter("palette_lookup_all",true)
	material.set_shader_parameter("palette_cycle_enabled",true)
	material.set_shader_parameter("animated_palette",ImageTexture.create_from_image(pack.palette.animation_image(0)))
	canvas.material=material
	viewport.add_child(canvas)
	await RenderingServer.frame_post_draw
	var first := viewport.get_texture().get_image()
	material.set_shader_parameter("animated_palette",ImageTexture.create_from_image(pack.palette.animation_image(5)))
	await RenderingServer.frame_post_draw
	var second := viewport.get_texture().get_image()
	assert(first.get_data()!=second.get_data(),"Native GPU palette animation must run on model faces")
	# Spatial masks also retain the optional flowing-water enhancement.
	material.set_shader_parameter("environment_has_seasons",true)
	material.set_shader_parameter("environment_season_mask",ImageTexture.create_from_image(context.season_atlas))
	material.set_shader_parameter("artwork_animation_seconds",0.0)
	await RenderingServer.frame_post_draw
	var flowing := viewport.get_texture().get_image()
	material.set_shader_parameter("artwork_animation_seconds",0.4)
	await RenderingServer.frame_post_draw
	var later := viewport.get_texture().get_image()
	var mask := context.builder.auxiliary_raster(bounds,archive.visual_seasons,false)
	var moving := 0
	var caps := 0
	for y in bounds.size.y:
		for x in bounds.size.x:
			var kind := mask.get_pixel(x,y).b8
			var different := not flowing.get_pixel(x,y).is_equal_approx(later.get_pixel(x,y))
			if kind==64:
				moving+=int(different)
			else:
				assert(not different,"Flow must leave horizontal caps and soil stationary")
				caps+=int(kind==153)
	assert(moving>0 and caps>0,"Falling faces animate below a quiet water cap")
	viewport.queue_free()
	await process_frame
