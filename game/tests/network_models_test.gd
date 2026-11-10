extends SceneTree
## The opt-in renderer must preserve source assets, city state and fallback art.
@warning_ignore_start("integer_division")
const State = preload("res://tests/support/document_state.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_material_cache()
	var pack := FixtureGraphics.pack()
	var total := 0
	var started := Time.get_ticks_msec()
	for archive: Sc2SpriteArchive in [pack.large_sprites, pack.small_medium_sprites]:
		var original := archive.entries_by_id.duplicate()
		assert(CityNetworkModels.configure(archive, pack.palette, true))
		assert(archive.network_model_entries.size() == (102 if archive == pack.large_sprites else 204))
		assert(archive.network_model_meshes < 102, "Equal geometry must share a record")
		var revision := archive.visual_revision
		assert(not CityNetworkModels.configure(archive, pack.palette, true))
		assert(archive.visual_revision == revision, "Unchanged settings must retain model resources")
		for id: int in archive.network_model_entries:
			var entry := archive.find_sprite(id)
			assert(entry != original[id])
			assert(entry.width == original[id].width, "Native horizontal registration changed")
			var pixels := entry.decode_indices().pixels
			var heights := archive.network_model_heights[id]
			assert(heights.size() == pixels.size())
			var opaque := 0
			for i in pixels.size():
				if pixels[i] >= 0:
					assert(is_finite(heights[i]) and heights[i] >= 0)
					opaque += 1
			assert(opaque > 0, "Empty model: %d" % id)
			total += 1
		var clone := MainMenuPresentation.copy_graphics(archive)
		assert(clone.find_sprite(1029 if archive == pack.large_sprites else 29) == archive.find_sprite(1029 if archive == pack.large_sprites else 29))
		var images := {}
		var key := 1029 if archive == pack.large_sprites else 29
		var modeled := CityIsometricRenderer.sprite_image(archive, pack.palette, images, key, false)
		assert(CityNetworkModels.configure(archive, pack.palette, false))
		assert(archive.entries_by_id == original)
		assert(archive.find_sprite(key) == original[key])
		assert(CityIsometricRenderer.sprite_image(archive, pack.palette, images, key, false) != modeled)
	_check_fallback(pack)
	_check_highway_surfaces(pack)
	_check_geometry()
	_check_crossing_clearance()
	_check_shared_road_poses(pack)
	_check_options()
	var city := CityState.from_document(EmptyCityTemplate.create(16))
	var before := State.capture(city.document)
	for id in range(14, 112):
		city.set_building_id(id % 12 + 2, id / 12 + 2, id)
	before = State.capture(city.document)
	CityNetworkModels.configure(pack.large_sprites, pack.palette, true)
	CityNetworkModels.configure(pack.small_medium_sprites, pack.palette, true)
	preload("res://tests/support/moving_surface_checks.gd").check_life(pack)
	preload("res://tests/support/moving_surface_checks.gd").check_traffic(pack)
	var context := CityGpuBuildContext.new()
	assert(context.prepare(city, pack.palette, pack.large_sprites, 2).is_empty())
	assert(State.capture(city.document) == before, "Models mutated the city")
	await _check_application()
	print("PASS: %d native model rasters, shared geometry, opt-in restoration, custom fallback, immutable city (%d ms)" % [total, Time.get_ticks_msec()-started])
	quit()


func _check_shared_road_poses(pack: GraphicsPack) -> void:
	var library := NetworkModelGeometry.Library.new(NetworkModelGeometry.build,NetworkModelGeometry.template)
	assert(library.acquire(29).mesh==library.acquire(30).mesh,"Both road axes must share their actual base mesh")
	for id in range(29,35):
		var model: Dictionary=library.acquire(id)
		var recipe := {"parts":model.mesh.parts,"ports":model.ports,"footprint":model.footprint,"pose_turns":model.pose_turns}
		for view in 3:
			var source := Image.create(32,64,false,Image.FORMAT_RGBA8)
			var shared := NetworkModelRaster.render(id,source,pack.palette,view,recipe)
			var direct := NetworkModelRaster.render(id,source,pack.palette,view)
			assert(shared.image.get_data()==direct.image.get_data(),"Sharing a rotated road mesh must preserve native pixels and its material orientation")
	for plane: PackedFloat32Array in preload("res://tests/model_combination_matrix_test.gd").planes():
		for id in [29,30]:
			var model: Dictionary=library.acquire(id,plane)
			var recipe := {"parts":model.mesh.parts,"ports":model.ports,"footprint":model.footprint,"pose_turns":model.pose_turns}
			var source := Image.create(32,64,false,Image.FORMAT_RGBA8)
			assert(NetworkModelRaster.render(id,source,pack.palette,2,recipe).image.get_data()==NetworkModelRaster.render(id,source,pack.palette,2,NetworkModelGeometry.build(id,plane)).image.get_data(),"Shared road poses must preserve every supported grade")


func _check_crossing_clearance() -> void:
	for id in [67,68,71,72,79,80]:
		for corners in [PackedFloat32Array([0,0,0,0]),PackedFloat32Array([0,3,3,0]),PackedFloat32Array([3,0,0,3])]:
			var recipe := NetworkModelGeometry.build(id,corners)
			var sides := {}
			for part: Dictionary in recipe.parts:
				if part.role!="pole":
					continue
				for vertex: Vector3 in part.vertices:
					var coordinate := vertex.x if id%2 else vertex.y
					assert(absf(coordinate)>.44,"Crossing posts must stay outside the road and train corridor")
					sides[signf(coordinate)]=true
			assert(sides.size()==2,"The crossing cables need a support at both sides")


func _check_highway_surfaces(pack: GraphicsPack) -> void:
	var cases := 0
	var ids: Array = range(BuildingTileIds.HIGHWAY_STRAIGHT_1,BuildingTileIds.HIGHWAY_POWER_CROSSING_2+1)
	ids.append_array(range(BuildingTileIds.HIGHWAY_ONRAMP_1,BuildingTileIds.REINFORCED_HIGHWAY_BRIDGE+1))
	for id: int in ids:
		var entry: Sc2SpriteArchive.SpriteEntry=pack.large_sprites.entries_by_id[1000+id]
		var source: Image=entry.create_image(pack.palette).image
		var plain := Image.create(source.get_width(),source.get_height(),false,Image.FORMAT_RGBA8)
		var raster := NetworkModelRaster.render(id,source,pack.palette)
		var expected := NetworkModelRaster.render(id,plain,pack.palette)
		for i in raster.roles.size():
			# Crossings retain their independently drawn road/rail underneath.
			if raster.height[i]>=12 and raster.roles[i]==1:
				var point := Vector2i(i%raster.image.get_width(),i/raster.image.get_width())
				assert(raster.image.get_pixelv(point)==expected.image.get_pixelv(point),"Projected railings or shadows leaked onto highway pavement: %s"%id)
		if id in [BuildingTileIds.HIGHWAY_STRAIGHT_1,BuildingTileIds.HIGHWAY_STRAIGHT_2] or id>=BuildingTileIds.HIGHWAY_ONRAMP_1:
			for view in 3:
				var divisor := 4>>view
				var small := source.duplicate()
				small.resize(source.get_width()/divisor,ceili(float(source.get_height())/divisor),Image.INTERPOLATE_NEAREST)
				var empty := Image.create(small.get_width(),small.get_height(),false,Image.FORMAT_RGBA8)
				assert(NetworkModelRaster.render(id,small,pack.palette,view).image.get_data()==NetworkModelRaster.render(id,empty,pack.palette,view).image.get_data(),"Highway joins must not inherit projected sprite structure at any artwork size")
				cases+=1
	print("PASS: highway pavement is independent of projected sprite structure; %d native size cases"%cases)


func _check_fallback(pack: GraphicsPack) -> void:
	var archive := Sc2SpriteArchive.new()
	var source := pack.large_sprites.entries_by_id[1029]
	var pixels := source.decode_indices().pixels.duplicate()
	pixels[pixels.find(161)] = 160
	var custom := Sc2SpriteArchive.entry_from_indices(1029, source.width, source.height, pixels)
	archive.entries = [custom]
	archive.entries_by_id[1029] = custom
	CityNetworkModels.configure(archive, pack.palette, true)
	assert(archive.network_model_entries.is_empty())
	assert(archive.find_sprite(1029) == custom, "Unknown art must remain untouched")
	archive.entries = [source]
	archive.entries_by_id[1029] = source
	var hd := HdSprite.new()
	hd.image = Image.create(source.width*2, source.height*2, false, Image.FORMAT_RGBA8)
	hd.image.fill(Color.MAGENTA)
	hd.height = source.height
	archive.high_resolution[1029] = hd
	CityNetworkModels.configure(archive, pack.palette, true)
	assert(archive.network_model_entries.is_empty(), "Custom HD must keep its own art")


func _check_geometry() -> void:
	var library := NetworkModelGeometry.Library.new(NetworkModelGeometry.build, NetworkModelGeometry.template)
	for id in range(14, 112):
		var model: Dictionary = library.acquire(id)
		assert(not model.mesh.parts.is_empty())
		assert(NetworkModelGeometry.TEMPLATES.has(model.mesh.template))
		assert(library.acquire(id).mesh == model.mesh)
		var flipped := NetworkModelGeometry.build(id, PackedFloat32Array(), true)
		var posed := NetworkModelGeometry.posed_parts(model.mesh.parts,model.pose_turns)
		for i in posed.size():
			for j in posed[i].vertices.size():
				var p: Vector3 = posed[i].vertices[j]
				var q: Vector3 = flipped.parts[i].vertices[j]
				# Two-tile composites mirror around their own 64-pixel canvas.
				assert(is_equal_approx(NetworkModelGeometry.project(p).x + NetworkModelGeometry.project(q).x, 32.0*(model.footprint-1)))
				assert(is_equal_approx(NetworkModelGeometry.project(p).y, NetworkModelGeometry.project(q).y))
	# Fixed endpoint heights cover each distinct grade direction.
	for first in [16, 31, 46, 59, 97]:
		for turn in 4:
			var heights := NetworkModelGeometry.profile(first+turn)
			assert(heights.count(12.0) == 2 and heights.count(0.0) == 2)
	assert(library.meshes.size() < 98)
	var closed: Dictionary=NetworkModelGeometry.build(BuildingTileIds.RAISING_BRIDGE_CLOSED)
	var opened: Dictionary=NetworkModelGeometry.build(BuildingTileIds.RAISING_BRIDGE_OPEN)
	for i in closed.parts.size():
		for j in closed.parts[i].vertices.size():
			assert(opened.parts[i].vertices[j].is_equal_approx(closed.parts[i].vertices[j]+Vector3(0,0,12)))
	_check_truss_clearance()
	_check_open_highway_joins()


func _check_open_highway_joins() -> void:
	for id in [BuildingTileIds.HIGHWAY_STRAIGHT_1,BuildingTileIds.HIGHWAY_STRAIGHT_2,
			BuildingTileIds.HIGHWAY_SLOPE_1,BuildingTileIds.HIGHWAY_SLOPE_2,
			BuildingTileIds.HIGHWAY_SLOPE_3,BuildingTileIds.HIGHWAY_SLOPE_4]:
		var model := NetworkModelGeometry.build(id)
		for part: Dictionary in model.parts:
			if part.role!="pavement":
				continue
			var vertices: PackedVector3Array=part.vertices
			var normal := (vertices[1]-vertices[0]).cross(vertices[2]-vertices[0])
			if absf(normal.z)>.0001:
				continue
			# Vertical walls may run along the road, never across a connected end.
			assert(absf(normal.y if model.ports==5 else normal.x)<.0001,"An internal highway end wall would draw over the adjoining road surface: %s"%id)
	print("PASS: straight and graded highway joins have no transverse end walls")


func _check_truss_clearance() -> void:
	var passages := 0
	for id in [BuildingTileIds.HIGHWAY_BRIDGE,BuildingTileIds.REINFORCED_HIGHWAY_BRIDGE]:
		for flipped in [false,true]:
			var bridge := NetworkModelGeometry.build(id,PackedFloat32Array(),flipped)
			for kind in [VehicleModels.Kind.CAR,VehicleModels.Kind.TRUCK,VehicleModels.Kind.BUS]:
				for forward: Vector2 in [Vector2.UP,Vector2.DOWN]:
					var vehicle := VehicleModels.geometry(kind,forward,0)
					var body := AABB(vehicle.parts[0].vertices[0],Vector3.ZERO)
					for part: Dictionary in vehicle.parts:
						for vertex: Vector3 in part.vertices:
							body=body.expand(vertex)
					for lane in [0.0,1.0]:
						# Sweep both lane offsets, whole bodies and extra roof clearance.
						var low := Vector3(lane+body.position.x-.14,-1.5+body.position.y,24+body.position.z)
						var high := Vector3(lane+body.end.x+.14,.5+body.end.y,24+body.end.z+.75)
						if flipped:
							low=Vector3(low.y+1,low.x-1,low.z)
							high=Vector3(high.y+1,high.x-1,high.z)
						var passage := AABB(low,high-low)
						for part: Dictionary in bridge.parts:
							if part.role not in ["truss","truss_hanger"]:
								continue
							var bounds := AABB(part.vertices[0],Vector3.ZERO)
							for vertex: Vector3 in part.vertices:
								bounds=bounds.expand(vertex)
							assert(not passage.intersects(bounds),"Bridge member obstructs a complete moving vehicle body: bridge %s, flip %s, kind %s, lane %s"%[id,flipped,kind,lane])
						passages+=1
	print("PASS: %d swept car/truck/bus passages are clear of bridge members in both orientations"%passages)


func _check_options() -> void:
	assert(not VisualEnhancementOptions.normalize({}).models_enabled)
	assert(VisualEnhancementOptions.normalize({"models_enabled": true}).models_enabled)
	for preset in 5:
		assert(VisualEnhancementOptions.preset(preset, {"models_enabled": true}).models_enabled)
		assert(not VisualEnhancementOptions.preset(preset, {}).models_enabled)
	var options := AppSettingsStore.SaveOptions.new()
	options.visual_enhancements = VisualEnhancementOptions.normalize({"models_enabled":true})
	assert(AppSettingsStore.save_values(.5,.5,false,"user://model-settings.cfg",options)==OK)
	assert(AppSettingsStore.load_values("user://model-settings.cfg").visual_enhancements.models_enabled)


func _check_application() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate() as CityApplication
	preload("res://tests/support/app_fixture.gd").configure(main,true)
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.main_menu.city_background.set_process(false)
	assert(main.city_session.activate_document(load("res://tests/city_life_test.gd").fixture().document))
	main.frame.select_speed(GameSpeedController.Speed.PAUSED)
	var before := State.capture(main.document_state.city.document)
	var engine := main.simulation_state.simulation_engine
	var random_before := [engine.random.state,engine.lfsr_random.state,engine.game_random.state]
	main.preferences.visual_enhancements.models_enabled=true
	main.visual_environment.configure()
	main.visual_preparation.begin()
	for index in main.visual_preparation.VARIANTS:
		var archive: Sc2SpriteArchive=main.visual_preparation.archives[index]
		var source:=main.static_render.original_archive_for_view(index/2)
		assert(archive.visual_models_enabled and archive.find_sprite(29+(index/2)*500)==source.network_model_entries[29+(index/2)*500])
	main.settings.open_settings_dialog()
	var dialog:=main.main_overlays.settings_dialog
	dialog.tabs.current_tab=dialog.visual_tab.get_index()
	var control:=dialog.visual_tab.controls.models_enabled as CheckBox
	assert(control.button_pressed)
	control.button_pressed=false
	assert(not main.preferences.visual_enhancements.models_enabled)
	assert(not main.asset_state.large_sprites.visual_models_enabled)
	assert(not AppSettingsStore.load_values(main.preferences.settings_path).visual_enhancements.models_enabled)
	assert(State.capture(main.document_state.city.document)==before)
	assert([engine.random.state,engine.lfsr_random.state,engine.game_random.state]==random_before)
	main.free()
	await process_frame


func _check_material_cache() -> void:
	var palette := FixtureGraphics.pack().palette
	var original := NetworkModelRaster.materials(palette,29)
	NetworkModelRaster.materials(palette,29).surface[0]=-2
	assert(NetworkModelRaster.materials(palette,29)==original,"A caller must not mutate another worker's material swatches")
	var replacement := Sc2Palette.new()
	replacement.colors.assign(palette.colors)
	assert(NetworkModelRaster.materials(replacement,29)==original,"Equivalent palettes reuse the same material result")
	replacement.colors.fill(Color.BLACK)
	var black := NetworkModelRaster.materials(replacement,29)
	for role: String in black:
		assert(black[role]==PackedInt32Array([0,0,0]),"A changed palette must invalidate the matching cache")
	for sample in 16:
		replacement.colors.fill(Color.from_hsv(sample/16.0,1,1))
		NetworkModelRaster.materials(replacement,29)
	assert(NetworkModelRaster._material_cache.size()<=NetworkModelRaster.MATERIAL_CACHE_LIMIT,"The shared material cache must remain bounded")
