extends "res://tests/city_gpu_geometry_test.gd"
## Production regional meshes, original masks and per-texel model reflections.

const WaterFixture = preload("res://tests/water_reflections_test.gd")
const State = preload("res://tests/support/document_state.gd")


func _run() -> void:
	assert(DisplayServer.get_name() != "headless")
	var pack := FixtureGraphics.pack()
	for archive: Sc2SpriteArchive in [pack.large_sprites,pack.small_medium_sprites]:
		CityNetworkModels.configure(archive,pack.palette,true)
	var city := CityState.from_document(EmptyCityTemplate.create(64))
	for id in range(14,112):
		var at := id-14
		var tile := Vector2i(7+(at%10)*5,7+(at/10)*5)
		city.set_building_id(tile.x,tile.y,id)
		city.set_building_corners(tile.x,tile.y,0x80)
	var cases := 0
	for turn in 4:
		var before := State.capture(city.document)
		for view in 3:
			var archive := pack.large_sprites if view==2 else pack.small_medium_sprites
			var bounds := Rect2i(Vector2i.ZERO,CityIsometricRenderer.output_size_for_view(view,city.map_size))
			await _compare(city,Sc2Palette.index_encoding(),archive,bounds,view,CityViewMode.Mode.CITY,CityGpuBuildContext.new())
			cases += 1
		assert(State.capture(city.document)==before)
		assert(CityRotationCommand.apply(city,true).ok)
	_check_model_water(pack)
	for archive: Sc2SpriteArchive in [pack.large_sprites,pack.small_medium_sprites]:
		CityNetworkModels.configure(archive,pack.palette,false)
	print("PASS: %d model CPU/GPU pixel and foreground pairs, all 98 types, three views, four city rotations; exact spatial bridge reflections"%cases)
	quit()


func _check_model_water(pack: GraphicsPack) -> void:
	var checked := 0
	for view in 3:
		var archive := pack.large_sprites if view==2 else pack.small_medium_sprites
		for bridge in [81,83,86,87,89,90,92,106,107]:
			for flip in [false,true]:
				var data := WaterFixture.fixture(view)
				# Keep tall cables well inside the receiver lake. Boundary rays are
				# intentionally rejected by the production water clipping code.
				data.request.edge=16
				for key in ["altitude","terrain","buildings","flags","zones","overlays","underground"]:
					data.request[key].resize(256)
					data.request[key].fill(0)
				data.request.terrain.fill(0x10)
				data.request.flags.fill(4)
				data.request.zones[119]=0x80
				var id: int = view*500+bridge
				var entry := archive.find_sprite(id)
				var heights := archive.network_model_heights[id]
				data.artwork[id]=entry.create_image(Sc2Palette.index_encoding()).image
				data.request.buildings[119]=bridge
				data.request.flags[119]=4 | (Sc2TileFlags.FLIPPED if flip else 0)
				data.request.model_heights={id:heights}
				var builder: NativeCityRegionBuilder=data.builder
				assert(str(builder.configure(data.request,data.artwork,0)).is_empty())
				var draws: Dictionary=builder.tile_draws(PackedInt32Array([7,7]))
				var origin:=Vector2i.ZERO
				for at in range(0,draws.records.size(),14):
					if draws.records[at+5]==id:
						origin=Vector2i(draws.records[at],draws.records[at+1])
				data.bounds=Rect2i(origin-Vector2i(16,16)/(4>>view),Vector2i(192,256)/(4>>view))
				var result: Dictionary=builder.water_reflections(data.bounds,data.indices,{}, {})
				assert(not result.has("error"))
				var matched:=0
				for y in entry.height:
					for x in entry.width:
						var original_x:=entry.width-1-x if flip else x
						var z:=heights[y*entry.width+original_x]
						if not is_finite(z) or roundi(2*z)<=0:
							continue
						var reflected: Vector2i=Vector2i(origin.x+x,origin.y+y+roundi(2*z))-data.bounds.position
						if not Rect2i(Vector2i.ZERO,data.bounds.size).has_point(reflected):
							continue
						if result.surface.get_pixelv(reflected).a==0:
							continue
						var pixel: Color=result.reflected.get_pixelv(reflected)
						assert(pixel.a>0 and pixel.g==1, "Model reflection lost spatial height: %d view %d flip %s source %s z %f destination %s pixel %s"%[bridge,view,flip,Vector2i(x,y),z,reflected,pixel])
						matched+=1
				assert(matched>0,"No model reflection samples")
				assert(result.emission.is_invisible())
				checked+=matched
	print("PASS: %d spatial reflection samples across 54 bridge/view/flip cases"%checked)
