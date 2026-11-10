extends "res://tests/city_gpu_geometry_test.gd"
## Actual GPU atlas and data shader coverage, including every fractional color address.
const Q = preload("res://tests/quarter_terrain_test.gd")


func _run() -> void:
	assert(DisplayServer.get_name()!="headless")
	var pack := FixtureGraphics.pack()
	for archive: Sc2SpriteArchive in [pack.large_sprites,pack.small_medium_sprites]:
		CityNetworkModels.configure(archive,pack.palette,true)
	var city := Q.fixture()
	var shapes := preload("res://tests/model_combination_matrix_test.gd").planes()
	for tile in 36:
		for state in 4:
			var point := Vector2i(8+tile,12+state*4)
			var corners: Array=[]
			for height: float in shapes[(tile+state)%41]:
				corners.append(9+int(height/3))
			Q.set_corners(city,point,corners)
			city.set_underground_id(point.x,point.y,tile)
			city.set_tile_flag(point.x,point.y,Sc2TileFlags.PIPED,state&1!=0)
			city.set_tile_flag(point.x,point.y,Sc2TileFlags.WATERED,state&2!=0)
	# Shared edge elevations must also survive cliffs and the deeper crossing pipe.
	for x in range(8,45):
		var level: int=[8,9,32,64,120][x%5]
		Q.set_corners(city,Vector2i(x,40),[level,level,level,level])
		city.set_underground_id(x,40,2)
	for y in range(32,52):
		var level: int=[9,32,8,64,120][y%5]
		Q.set_corners(city,Vector2i(25,y),[level,level,level,level])
		city.set_underground_id(25,y,16)
		city.set_tile_flag(25,y,Sc2TileFlags.PIPED,true)
		city.set_tile_flag(25,y,Sc2TileFlags.WATERED,y%2==0)
	city.set_underground_id(25,40,32)
	var cases := 0
	for turn in 4:
		for view in 3:
			var archive := pack.large_sprites if view==2 else pack.small_medium_sprites
			for cut in [32,3]:
				city.visible_altitude_levels=cut
				var bounds := Rect2i(Vector2i.ZERO,CityIsometricRenderer.output_size_for_view(view,64))
				await _compare(city,Sc2Palette.index_encoding(),archive,bounds,view,CityViewMode.Mode.UNDERGROUND,CityGpuBuildContext.new())
				cases+=1
		assert(CityRotationCommand.apply(city,true).ok)
	print("PASS: %d complete underground CPU/GPU image pairs, all XUND forms and water states"%cases)
	await _data_shader()
	await _vehicle_pixels(pack.palette)
	quit()


func _vehicle_pixels(palette: Sc2Palette) -> void:
	var viewport := SubViewport.new()
	viewport.transparent_bg=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var canvas := CityDynamicSpriteCanvas.new()
	viewport.add_child(canvas)
	var models := VehicleModels.new()
	var reference := Sprite2D.new()
	reference.centered=false
	reference.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	viewport.add_child(reference)
	canvas.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	for zoom in [.5,1.0,2.0,3.0]:
		var expected := Image.create(768,384,false,Image.FORMAT_RGBA8)
		var visuals: Array[CityDynamicVisual]=[]
		# The real moving canvas chooses reduced native artwork when zoomed out.
		# Preserve its aligned 4-pixel grid instead of testing arbitrary odd crops.
		var divisor := 4 if zoom<1 else 1
		for kind in range(VehicleModels.Kind.AIRPLANE,VehicleModels.Kind.size()):
			for direction in 8:
				var frame := models.frame(kind,0,Vector2.UP.rotated(direction*PI/4),0,palette,divisor)
				var position := Vector2i(direction*96+8,(kind-VehicleModels.Kind.AIRPLANE)*96+8)
				var visual := CityDynamicVisual.new()
				visual.texture=ImageTexture.create_from_image(frame.image)
				visual.position=position
				visual.size=frame.image.get_size()
				visuals.append(visual)
				expected.blit_rect(frame.image,Rect2i(Vector2i.ZERO,frame.image.get_size()),position)
		reference.texture=ImageTexture.create_from_image(expected)
		viewport.size=Vector2i(Vector2(768,384)*zoom)
		canvas.set_visuals(visuals,zoom,Vector2.ZERO)
		reference.scale=Vector2.ONE*zoom
		canvas.hide()
		reference.show()
		await RenderingServer.frame_post_draw
		var pixels := viewport.get_texture().get_image()
		reference.hide()
		canvas.show()
		await RenderingServer.frame_post_draw
		assert(pixels.get_data()==viewport.get_texture().get_image().get_data(),"Aircraft and ship GPU pixels differ at zoom %s"%zoom)
	viewport.queue_free()
	await process_frame
	print("PASS: all 32 aircraft/ship model headings match the actual moving canvas at four zooms")


func _data_shader() -> void:
	assert(CityDataView.range_labels(CityViewMode.Mode.HEIGHT,true)==PackedStringArray(["0","32"]))
	assert(CityDataView.scale_color(CityViewMode.Mode.HEIGHT,31,true)==CityDataView.height_color(32))
	var viewport := SubViewport.new()
	viewport.size=Vector2i(64,64)
	viewport.disable_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var layer := MeshInstance2D.new()
	var material := ShaderMaterial.new()
	material.shader=CityDataView.GRID_SHADER
	layer.material=material
	viewport.add_child(layer)
	var city := Q.fixture()
	var point := Vector2i(20,20)
	Q.set_corners(city,point,[9,11,11,9])
	city.set_tile_flag(20,20,Sc2TileFlags.PIPED,true)
	city.set_tile_flag(20,20,Sc2TileFlags.WATERED,true)
	city.set_tile_flag(20,20,Sc2TileFlags.POWERABLE,true)
	city.set_tile_flag(20,20,Sc2TileFlags.POWERED,true)
	for id: String in CityDataView.CHUNKS.values():
		var chunk := city.document.find_chunk(id)
		var data := chunk.decoded_payload.duplicate()
		data.fill(173)
		chunk.set_decoded_payload(data)
	material.set_shader_parameter("map_edge",64.0)
	for mode: CityViewMode.Mode in CityViewMode.DATA_MODES:
		layer.mesh=CityDataView.create_mesh(city,mode)
		layer.position=Vector2(32,32)-VehicleModels.contact(city,Vector2(point))
		var fractional := mode==CityViewMode.Mode.HEIGHT
		material.set_shader_parameter("fractional_height",fractional)
		material.set_shader_parameter("tile_values",ImageTexture.create_from_image(CityDataView.value_image(city,mode)))
		material.set_shader_parameter("value_colors",ImageTexture.create_from_image(CityDataView.color_image(mode,fractional)))
		await RenderingServer.frame_post_draw
		var actual := viewport.get_texture().get_image().get_pixel(32,32)
		var expected := CityDataView.height_color(2.5) if fractional else CityDataView.color(CityDataView.value(city,mode,20,20),mode)
		assert(_color_error(actual,expected)<.02,"Quarter data shader: "+CityViewMode.key(mode))
	var colors := ImageTexture.create_from_image(CityDataView.color_image(CityViewMode.Mode.HEIGHT,true))
	material.set_shader_parameter("value_colors",colors)
	var values := Image.create(64,64,false,Image.FORMAT_RF)
	var texture := ImageTexture.create_from_image(values)
	material.set_shader_parameter("tile_values",texture)
	var samples := 0
	for wet in [false,true]:
		for step in (497 if wet else 513):
			var number := (64.0 if wet else 0.0)+step/16.0
			values.set_pixel(20,20,Color(number,0,0,1))
			texture.update(values)
			await RenderingServer.frame_post_draw
			var actual := viewport.get_texture().get_image().get_pixel(32,32)
			assert(_color_error(actual,CityDataView.height_color(number))<.02,"Fractional GPU height %s"%number)
			samples+=1
	viewport.queue_free()
	await process_frame
	print("PASS: all 11 data modes on quarter geometry and %d exact fractional land/depth color addresses"%samples)


func _color_error(a: Color, b: Color) -> float:
	return maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))
