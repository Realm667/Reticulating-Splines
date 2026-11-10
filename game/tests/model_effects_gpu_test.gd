extends "res://tests/support/scene_test_case.gd"
## Material semantics and the production effect dispatcher for sprites and Models.
const State = preload("res://tests/support/document_state.gd")
const Fixture = preload("res://tests/support/app_fixture.gd")
const Q = preload("res://tests/quarter_terrain_test.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	assert(DisplayServer.get_name()!="headless")
	var pack := FixtureGraphics.pack()
	var library := VehicleModels.new()
	for view in 3:
		for supplied in [false,true]:
			var recipe := UndergroundModels.geometry(450 if supplied else 334,PackedFloat32Array([0,3,3,0]))
			recipe.materials=UndergroundModels.materials(pack.palette)
			var raster := NetworkModelRaster.render(0,Image.create(32,64,false,Image.FORMAT_RGBA8),pack.palette,view,recipe)
			var indices: PackedInt32Array=raster.entry.decode_indices().pixels
			var animated := 0
			for index: int in indices:
				animated+=int(index in range(200,208))
			assert((animated>0)==supplied,"Only supplied spatial pipes carry animated water")
	for divisor in [1,2,4]:
		for direction in 8:
			var forward := Vector2.UP.rotated(direction*PI/4)
			for kind in [VehicleModels.Kind.AIRPLANE,VehicleModels.Kind.HELICOPTER]:
				var body := library.frame(kind,0,forward,0,pack.palette,divisor)
				var shadow := library.frame(kind,0,forward,0,pack.palette,divisor,true)
				assert(not shadow.image.is_invisible())
				assert(not body.lamps.is_invisible(),"Spatial aircraft retain their navigation lights")
				for part: Dictionary in shadow.recipe.parts:
					for vertex: Vector3 in part.vertices:
						assert(vertex.z==0,"Aircraft shadows must project the current body onto the receiver")
			for kind in [VehicleModels.Kind.SHIP,VehicleModels.Kind.SAILBOAT]:
				var boat := library.frame(kind,0,forward,0,pack.palette,divisor)
				assert(not boat.reflection.is_invisible())
				assert(boat.indexed.get_data()!=boat.water_indexed.get_data(),"Enhanced water exposes the live surface under the wake")
				assert(boat.floating_source.get_data()!=boat.indexed.get_data(),"Foam must not move floating occlusion contacts")
				if kind==VehicleModels.Kind.SHIP:
					assert(not boat.reflection_lamps.is_invisible())
	for archive: Sc2SpriteArchive in [pack.large_sprites,pack.small_medium_sprites]:
		CityNetworkModels.configure(archive,pack.palette,true)
		CityBrightmaps.load_archive(archive,"user://missing-model-effect-catalog","large")
		assert(not archive.network_model_emission.is_empty())
		for id: int in archive.network_model_emission:
			var entry := archive.find_sprite(id)
			var mask: Image=archive.visual_emission[id]
			assert(mask.get_size()==Vector2i(entry.width,entry.height))
			assert(not mask.is_invisible())
	var quarter := Q.fixture()
	_check_quarter_receivers(quarter)
	var edge := CityEdgeProfile.new()
	Q.set_corners(quarter,Vector2i(63,20),[12,13,14,12])
	edge.texture_for(quarter)
	assert(is_equal_approx(edge.image.get_pixel(20,0).r*31,27.0/8))
	Q.set_corners(quarter,Vector2i(63,20),[12,13,15,12])
	edge.texture_for(quarter)
	assert(is_equal_approx(edge.image.get_pixel(20,0).r*31,28.0/8),"Quarter-only boundary edits invalidate sediment profiles")
	var elevation := CityTerrainElevation.new()
	Q.set_corners(quarter,Vector2i(20,20),[100,101,102,103])
	var before := elevation.range_for(quarter)
	Q.set_corners(quarter,Vector2i(20,20),[100,101,102,127])
	assert(elevation.range_for(quarter)!=before,"Quarter-only height edits invalidate the natural terrain shading range")
	quarter.set_building_id(20,20,BuildingTileIds.ROAD_JUNCTION_1)
	for view in 3:
		var archive := pack.large_sprites if view==2 else pack.small_medium_sprites
		var variants := QuarterNetworkModels.new()
		for rise in [0,1,2,4,8]:
			Q.set_corners(quarter,Vector2i(20,20),[8,8+rise,8+rise,8])
			var prepared := variants.prepare(quarter,archive,pack.palette,view)
			assert(not prepared.emission.is_empty(),"Graded traffic signals retain geometry-aligned light masks")
	await _terrain_seasons(pack)
	await _quarter_fog()
	await _fractional_shading()
	await _pipe_overlay(pack.palette)
	await _environment_parity()
	print("PASS: 96 spatial aircraft/ship effect poses, three native sizes, graded signal masks and all shared option dispatches")
	quit()


func _check_quarter_receivers(city: CityState) -> void:
	var tile := Vector2i(20,20)
	city.set_building_id(tile.x,tile.y,BuildingTileIds.ROAD_STRAIGHT_1)
	var lighting := CityNightGround.new()
	var baseline := lighting.sources(city,tile).size()
	var neighbor := tile+Vector2i.RIGHT
	city.set_building_id(neighbor.x,neighbor.y,int(lighting.profiles.entrances.keys()[0]))
	Q.set_corners(city,tile,[13,13,13,13])
	Q.set_corners(city,neighbor,[13,13,13,13])
	assert(lighting.sources(city,tile).size()==baseline+1)
	Q.set_corners(city,neighbor,[14,14,14,14])
	assert(lighting.sources(city,tile).size()==baseline,"Entrance lights cannot bridge a quarter-height mismatch")
	lighting.free()
	var traffic := CityLifeController.new(null)
	Q.set_corners(city,tile,[13,14,14,13])
	traffic._advance(city,0)
	traffic._paths[Vector3i(20,20,0)]=CityLifePaths.Segment.new(city,tile,0,2,false)
	Q.set_corners(city,tile,[13,15,15,13])
	traffic._advance(city,0)
	assert(traffic._paths.is_empty(),"Quarter-only terrain edits invalidate cosmetic vehicle paths")


func _quarter_fog() -> void:
	var city := Q.fixture()
	var fog := CityVisualFog.new(null)
	var tile := Vector2i(20,20)
	var viewport := SubViewport.new()
	viewport.size=Vector2i.ONE
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var rectangle := ColorRect.new()
	rectangle.size=Vector2.ONE
	var material := ShaderMaterial.new()
	material.shader=CityVisualFog.HEIGHT_SHADER
	material.set_shader_parameter("fog_has_quarters",true)
	material.set_shader_parameter("fog_edge",64)
	material.set_shader_parameter("fog_ceiling",3.5)
	rectangle.material=material
	viewport.add_child(rectangle)
	for values in [[13,13,13,13],[12,13,13,12],[12,16,16,12],[20,12,12,20]]:
		Q.set_corners(city,tile,values)
		fog._sync_terrain(city)
		material.set_shader_parameter("fog_altitudes",fog.altitude_texture)
		material.set_shader_parameter("fog_terrain",fog.terrain_texture)
		material.set_shader_parameter("fog_flags",fog.flags_texture)
		material.set_shader_parameter("fog_quarters",fog.quarter_texture)
		var height: float = (float(values[0])+float(values[2]))/8.0
		var flat := Vector2(tile)-Vector2.ONE*height*.75
		material.set_shader_parameter("fog_mask_to_tiles",CityVisualClouds.shader_basis(Transform2D(0,flat-Vector2.ONE*.5)))
		await RenderingServer.frame_post_draw
		var expected := 1-smoothstep(2,5,height)
		assert(absf(viewport.get_texture().get_image().get_pixel(0,0).r-expected)<.012,"Fog must follow the actual fractional terrain plane")
	for shape in [0x10,0x3e,0x3f]:
		Q.set_corners(city,tile,[0,0,0,0])
		city.set_water_altitude(tile.x,tile.y,4)
		city.set_terrain_id(tile.x,tile.y,shape)
		city.set_tile_flag(tile.x,tile.y,Sc2TileFlags.WATER,shape!=0x3f)
		fog._sync_terrain(city)
		var height := 0.0 if shape==0x3f else (5.0 if shape==0x3e else 4.0)
		var flat := Vector2(tile)-Vector2.ONE*height*.75
		material.set_shader_parameter("fog_mask_to_tiles",CityVisualClouds.shader_basis(Transform2D(0,flat-Vector2.ONE*.5)))
		await RenderingServer.frame_post_draw
		assert(absf(viewport.get_texture().get_image().get_pixel(0,0).r-(1-smoothstep(2,5,height)))<.012,"Quarter fog must use water and waterfall caps while reserved dry codes remain land")
	Q.set_corners(city,tile,[13,14,14,13])
	fog._sync_terrain(city)
	var texture := fog.quarter_texture
	var data := texture.get_image().get_data()
	fog.height_signature=[1]
	Q.set_corners(city,tile,[13,15,15,13])
	fog._sync_terrain(city)
	assert(fog.quarter_texture==texture and texture.get_image().get_data()!=data and fog.height_signature.is_empty(),"Quarter-only edits refresh resident fog terrain and invalidate its projected mask")
	viewport.queue_free()
	await process_frame


func _fractional_shading() -> void:
	var viewport := SubViewport.new()
	viewport.size=Vector2i(128,24)
	viewport.transparent_bg=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var pixels := Image.create(8,8,false,Image.FORMAT_RGBA8)
	pixels.fill(Color(.6,.65,.4))
	var soil := Image.create(8,8,false,Image.FORMAT_RGBA8)
	soil.fill(Color(0,1,0,1))
	var material := ShaderMaterial.new()
	material.shader=CityMapControl.PALETTE_CYCLE_SHADER
	material.set_shader_parameter("environment_has_seasons",true)
	material.set_shader_parameter("environment_season_mask",ImageTexture.create_from_image(soil))
	material.set_shader_parameter("terrain_elevation_enabled",true)
	material.set_shader_parameter("terrain_elevation_range",Vector2(0,8))
	for row in 3:
		for fraction in 16:
			var sprite := Sprite2D.new()
			sprite.centered=false
			sprite.position=Vector2(fraction*8,row*8)
			sprite.texture=ImageTexture.create_from_image(pixels)
			sprite.material=material
			sprite.self_modulate=Color8([53,54,57][row],3,2+fraction*4 if row==2 else fraction,255)
			viewport.add_child(sprite)
	await RenderingServer.frame_post_draw
	var result := viewport.get_texture().get_image()
	for row in 3:
		assert(result.get_pixel(124,row*8+4).r>result.get_pixel(4,row*8+4).r,"Terrain shading must preserve sixteenth-level means through packed vertex colors")
		for fraction in 16:
			assert(result.get_pixel(fraction*8+4,row*8+4).is_equal_approx(result.get_pixel(fraction*8+4,4)),"Indexed, artwork and waterfall height tags must decode the same fractional mean")
	viewport.queue_free()
	await process_frame


func _pipe_overlay(palette: Sc2Palette) -> void:
	var viewport := SubViewport.new()
	viewport.size=Vector2i(16,16)
	viewport.transparent_bg=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var sprite := Sprite2D.new()
	sprite.centered=false
	sprite.self_modulate=Color8(52,0,0,255)
	var pixels := Image.create(16,16,false,Image.FORMAT_RGBA8)
	pixels.fill(Color8(200,0,0,255))
	sprite.texture=ImageTexture.create_from_image(pixels)
	var material := ShaderMaterial.new()
	material.shader=CityMapControl.PALETTE_CYCLE_SHADER
	material.set_shader_parameter("animated_palette",ImageTexture.create_from_image(palette.animation_image(0)))
	sprite.material=material
	viewport.add_child(sprite)
	await RenderingServer.frame_post_draw
	assert(viewport.get_texture().get_image().is_invisible(),"Unresolved indexed CPU/GPU comparisons must not receive a decoded flow overlay")
	material.set_shader_parameter("palette_cycle_enabled",true)
	await RenderingServer.frame_post_draw
	var first := viewport.get_texture().get_image()
	assert(not first.is_invisible(),"The production palette pass must show supplied pipe flow")
	material.set_shader_parameter("animated_palette",ImageTexture.create_from_image(palette.animation_image(5)))
	await RenderingServer.frame_post_draw
	assert(first.get_data()!=viewport.get_texture().get_image().get_data(),"Supplied pipe flow must retain its original palette cycle")
	pixels.fill(Color8(16,0,0,255))
	sprite.texture=ImageTexture.create_from_image(pixels)
	await RenderingServer.frame_post_draw
	assert(viewport.get_texture().get_image().is_invisible(),"Dry pipe texels cannot acquire a water-flow overlay")
	viewport.queue_free()
	await process_frame


func _terrain_seasons(pack: GraphicsPack) -> void:
	var city := Q.fixture()
	var tile := Vector2i(20,20)
	Q.set_corners(city,tile,[12,13,13,12])
	var archive := pack.large_sprites
	var context := CityGpuBuildContext.new()
	var center := Vector2i(VehicleModels.contact(city,Vector2(tile)))
	var bounds := Rect2i(center-Vector2i(48,48),Vector2i(96,96))
	var region := context.render(city,pack.palette,archive,bounds,2,CityViewMode.Mode.CITY,true,true,0,-1,true,true)
	assert(region.error.is_empty())
	var has_fraction := false
	for color: Color in region.gpu_arrays[Mesh.ARRAY_COLOR]:
		has_fraction=has_fraction or (color.r8==54 and color.g8==3 and color.b8==2)
	assert(has_fraction,"The actual native model draw must publish the exact mean of its four quarter corners")
	var mask := context.builder.auxiliary_raster(bounds,{},false)
	var ground := 0
	for y in mask.get_height():
		for x in mask.get_width():
			ground+=int(mask.get_pixel(x,y).g>.5)
	assert(ground>100,"Dry model ground needs geometry-sized season and nature masks")
	var viewport := SubViewport.new()
	viewport.size=bounds.size
	viewport.transparent_bg=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var sprite := Sprite2D.new()
	sprite.centered=false
	sprite.texture=ImageTexture.create_from_image(region.paint(bounds))
	var material := ShaderMaterial.new()
	material.shader=CityMapControl.PALETTE_CYCLE_SHADER
	material.set_shader_parameter("palette_lookup_all",true)
	material.set_shader_parameter("palette_cycle_enabled",true)
	material.set_shader_parameter("environment_enabled",true)
	material.set_shader_parameter("animated_palette",ImageTexture.create_from_image(pack.palette.animation_image(0)))
	material.set_shader_parameter("environment_season_mask",ImageTexture.create_from_image(mask))
	material.set_shader_parameter("environment_has_seasons",true)
	material.set_shader_parameter("environment_seasons",Vector4(0,1,0,0))
	sprite.material=material
	viewport.add_child(sprite)
	await RenderingServer.frame_post_draw
	var summer := viewport.get_texture().get_image()
	material.set_shader_parameter("environment_seasons",Vector4(0,0,0,1))
	await RenderingServer.frame_post_draw
	var winter := viewport.get_texture().get_image()
	assert(summer.get_data()!=winter.get_data(),"Winter must reach the actual dry model raster on the GPU")
	viewport.queue_free()
	await process_frame


func _environment_parity() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate() as CityApplication
	Fixture.configure(main,true)
	root.add_child(main)
	await process_frame
	main.main_menu.city_background.set_process(false)
	var city := CityState.from_document(EmptyCityTemplate.create(32))
	for x in 32:
		for y in 32:
			city.set_land_altitude(x,y,3)
	assert(main.city_session.activate_document(city.document))
	main.frame.select_speed(GameSpeedController.Speed.PAUSED)
	var saved := State.capture(city.document)
	var snapshots: Array[Dictionary]=[]
	for enabled in [false,true]:
		var options := VisualEnhancementOptions.normalize({"models_enabled":enabled,"day_mode":1,"day_hour":0.0,
			"season_mode":2,"season_fixed":3,"weather_mode":2,"weather_fixed":2,"pause_freezes":true})
		main.preferences.visual_enhancements=options
		main.visual_environment.configure()
		await Fixture.wait_for_visuals(main)
		var mode: Dictionary={}
		for field: Array in VisualEnhancementOptions.FIELDS:
			if field[0] in ["models_enabled","tree_growth_enabled"] or field[2]=="path":
				continue
			var samples: Array=[]
			match field[2]:
				"bool": samples=[false,true]
				"number": samples=[field[4],field[5]]
				"choice": samples=range(field[4].size())
			for sample: Variant in samples:
				var changed := options.duplicate()
				changed[field[0]]=sample
				main.preferences.visual_enhancements=changed
				# Compare the same instant of each transition, independently of how
				# long the preceding native model preparation took.
				main.visual_environment.weather.reset()
				main.visual_environment.clouds.reset()
				main.visual_environment.profiles.reset()
				main.visual_environment.configure()
				var values: Dictionary={}
				for key: String in main.map_view.layers.environment_parameters:
					var value: Variant=main.map_view.layers.environment_parameters[key]
					if not value is Object:
						values[key]=value
				mode[str(field[0])+":"+str(sample)]=values
				opts_restore(main,options)
		snapshots.append(mode)
	for field: String in snapshots[0]:
		for key: String in snapshots[0][field]:
			assert(snapshots[0][field][key]==snapshots[1][field].get(key),
				"Effect dispatch differs for %s / %s: %s <> %s"%[field,key,snapshots[0][field][key],snapshots[1][field].get(key)])
	assert(State.capture(city.document)==saved,"Effect and Models switches cannot alter a city or its RNG")
	main.queue_free()
	await process_frame


func opts_restore(main: CityApplication, options: Dictionary) -> void:
	main.preferences.visual_enhancements=options
	main.visual_environment.configure()
