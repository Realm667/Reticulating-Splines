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
	await _environment_parity()
	print("PASS: 96 spatial aircraft/ship effect poses, three native sizes, graded signal masks and all shared option dispatches")
	quit()


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
			var changed := options.duplicate()
			match field[2]:
				"bool": changed[field[0]]=not options[field[0]]
				"number": changed[field[0]]=field[5]
				"choice": changed[field[0]]=field[4].size()-1
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
			mode[field[0]]=values
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
