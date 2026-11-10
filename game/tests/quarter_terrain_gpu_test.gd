extends "res://tests/city_gpu_geometry_test.gd"
## Real regional atlas, fractional terrain and matching infrastructure silhouettes.
const QuarterFixture = preload("res://tests/quarter_terrain_test.gd")


func _run() -> void:
	assert(DisplayServer.get_name()!="headless")
	var pack:=FixtureGraphics.pack()
	for archive: Sc2SpriteArchive in [pack.large_sprites,pack.small_medium_sprites]:
		CityNetworkModels.configure(archive,pack.palette,true)
	var city:=QuarterFixture.fixture()
	for shape in 5:
		var tile:=Vector2i(20+shape*3,20)
		var heights: Array=[[9,9,9,9],[8,10,10,8],[8,12,12,8],[8,16,16,8],[24,24,24,24]][shape]
		QuarterFixture.set_corners(city,tile,heights)
		if shape<3:
			city.set_building_id(tile.x,tile.y,29 if shape!=1 else 14)
	for height in [2,4]:
		var anchor:=Vector2i(8+height*4,40)
		for x in 2:
			for y in 2:
				QuarterFixture.set_corners(city,anchor+Vector2i(x,y),[8+x*height,8+(x+1)*height,8+(x+1)*height,8+x*height])
		assert(HighwayCommand.apply(city,6,1,anchor,anchor).ok)
	for id in [44,93,63,108,64]:
		var tile:=Vector2i(8+[44,93,63,108,64].find(id)*4,30)
		QuarterFixture.set_corners(city,tile,[9,9,9,9])
		city.set_building_id(tile.x,tile.y,id)
	var bank:=Vector2i(38,30)
	QuarterFixture.set_corners(city,bank,[0,8,8,0])
	city.set_water_altitude(bank.x,bank.y,1)
	city.set_tile_flag(bank.x,bank.y,Sc2TileFlags.WATER,true)
	city.set_terrain_id(bank.x,bank.y,0x33)
	var cases:=0
	var context:=CityGpuBuildContext.new()
	assert(context.prepare(city,Sc2Palette.index_encoding(),pack.large_sprites,2).is_empty())
	var drawings:=context.tile_draws([Vector2i(20,20),Vector2i(23,20)])
	var foreground:=CityGpuBuildContext.foreground_commands(drawings.records,false,drawings.images)
	assert(foreground.any(func(command: CityStaticCommand) -> bool: return command.model_image!=null),"Use the actual custom model silhouette for moving figures")
	for turn in 4:
		for view in 3:
			var archive:=pack.large_sprites if view==2 else pack.small_medium_sprites
			var bounds:=Rect2i(Vector2i.ZERO,CityIsometricRenderer.output_size_for_view(view,city.map_size))
			await _compare(city,Sc2Palette.index_encoding(),archive,bounds,view,CityViewMode.Mode.CITY,CityGpuBuildContext.new())
			cases+=1
		assert(CityRotationCommand.apply(city,true).ok)
	print("PASS: %d exact CPU/GPU quarter-terrain, cliff and infrastructure pairs"%cases)
	quit()
