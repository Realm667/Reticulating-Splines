extends SceneTree
## The opt-in renderer must preserve source assets, city state and fallback art.
@warning_ignore_start("integer_division")
const State = preload("res://tests/support/document_state.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var pack := FixtureGraphics.pack()
	var total := 0
	var started := Time.get_ticks_msec()
	for archive: Sc2SpriteArchive in [pack.large_sprites, pack.small_medium_sprites]:
		var original := archive.entries_by_id.duplicate()
		assert(CityNetworkModels.configure(archive, pack.palette, true))
		assert(archive.network_model_entries.size() == (98 if archive == pack.large_sprites else 196))
		assert(archive.network_model_meshes < 98, "Equal geometry must share a record")
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
	_check_geometry()
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
		for i in model.mesh.parts.size():
			for j in model.mesh.parts[i].vertices.size():
				var p: Vector3 = model.mesh.parts[i].vertices[j]
				var q: Vector3 = flipped.parts[i].vertices[j]
				# Two-tile composites mirror around their own 64-pixel canvas.
				assert(is_equal_approx(NetworkModelGeometry.project(p).x + NetworkModelGeometry.project(q).x, 32.0*(model.footprint-1)))
				assert(is_equal_approx(NetworkModelGeometry.project(p).y, NetworkModelGeometry.project(q).y))
	# Fixed endpoint heights cover each distinct grade direction.
	for first in [16, 31, 46, 97]:
		for turn in 4:
			var heights := NetworkModelGeometry.profile(first+turn)
			assert(heights.count(12.0) == 2 and heights.count(0.0) == 2)
	assert(library.meshes.size() < 98)
	var closed: Dictionary=NetworkModelGeometry.build(BuildingTileIds.RAISING_BRIDGE_CLOSED)
	var opened: Dictionary=NetworkModelGeometry.build(BuildingTileIds.RAISING_BRIDGE_OPEN)
	for i in closed.parts.size():
		for j in closed.parts[i].vertices.size():
			assert(opened.parts[i].vertices[j].is_equal_approx(closed.parts[i].vertices[j]+Vector3(0,0,12)))


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
