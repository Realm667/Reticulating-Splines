extends "res://tests/city_life_gpu_test.gd"
## Real instanced GPU frames must equal CPU stamps of the rigid model raster.


func _run() -> void:
	var viewport:=SubViewport.new()
	viewport.size=Vector2i(256,192)
	viewport.transparent_bg=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var canvas:=CityLifeCanvas.new()
	canvas.source_bounds=Rect2i(0,0,256,192)
	viewport.add_child(canvas)
	var sprites:=CityLifeSprites.new()
	canvas.gpu=CityLifeGpu.new()
	canvas.gpu.prepare(sprites,canvas.lights)
	var library:=VehicleModels.new()
	var pack:=FixtureGraphics.pack()
	var entries: Array[Dictionary]=[]
	var mask:=Image.create(256,192,false,Image.FORMAT_RGBA8)
	mask.fill_rect(Rect2i(83,0,2,192),Color.WHITE)
	for kind in VehicleModels.Kind.AIRPLANE:
		for direction in 4:
			var index:=entries.size()
			var figure:=CityLifeController.Figure.new()
			figure.id=index
			figure.tile=Vector2i(index,0)
			figure.direction=direction
			var frame:=library.frame(kind,kind,CityLifePaths.forward(direction),[-12,0,6,12][direction],pack.palette)
			var origin:=Vector2i(8+direction*45,8+kind*24)
			figure.position=Vector2(origin)+frame.anchor
			canvas._occluder_bounds[Vector3i(index,0,0)]=Rect2i(origin,Vector2i(64,48))
			entries.append({"figure":figure,"sprite":frame.image,"origin":origin,"opacity":1.0,"occluders":[{"origin":Vector2i.ZERO,"image":mask}]})
	var reference:=Sprite2D.new()
	reference.centered=false
	reference.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	reference.material=_pixel_reference_material()
	viewport.add_child(reference)
	var pixels:=Image.create(256,192,false,Image.FORMAT_RGBA8)
	for entry in entries:
		CityLifeCanvas.stamp(pixels,Vector2i.ZERO,entry.sprite,entry.origin,entry.occluders)
	reference.texture=ImageTexture.create_from_image(pixels)
	canvas.gpu.render(canvas,entries)
	var previous_height:=canvas.gpu.artwork.get_height()
	var visits: Array[Dictionary]=[]
	for i in 1030:
		var visit: Dictionary=entries[0].duplicate()
		visit.sprite=entries[0].sprite.duplicate()
		visit.sprite.set_meta("vehicle_model_lamps",entries[0].sprite.get_meta("vehicle_model_lamps"))
		visits.append(visit)
	canvas.gpu._include_entries(visits)
	assert(canvas.gpu.artwork.get_height()>previous_height,"Previously viewed model poses grow the atlas without moving live source rectangles")
	canvas.gpu.render(canvas,entries)
	for zoom in [.5,1.0,2.0,3.0]:
		canvas.scale=Vector2.ONE*zoom
		reference.scale=canvas.scale
		canvas.hide()
		reference.show()
		await RenderingServer.frame_post_draw
		var expected:=viewport.get_texture().get_image()
		reference.hide()
		canvas.show()
		await RenderingServer.frame_post_draw
		assert(expected.get_data()==viewport.get_texture().get_image().get_data(),"Rigid vehicle GPU pixels differ at zoom %s"%zoom)
	assert(canvas.gpu.rectangles.has(entries[0].sprite.get_instance_id()),"Model rasters must be uploaded into the persistent GPU atlas")
	viewport.queue_free()
	await process_frame
	print("PASS: 24 rigid vehicle/train poses match CPU/GPU pixels at four zooms with foreground occlusion")
	quit()
