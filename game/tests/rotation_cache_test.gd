extends SceneTree
## Revisit all four directions, then compare edited retained regions with a fresh builder.
@warning_ignore_start("integer_division")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	OS.set_environment("OPENSC2K_CITY_RENDERER", "gpu")
	OS.set_environment("OPENSC2K_GRAPHICS_PACK", ProjectSettings.globalize_path("res://../ext/graphics"))
	OS.set_environment("OPENSC2K_DATA_PACK", ProjectSettings.globalize_path("res://../ext/data"))
	OS.set_environment("OPENSC2K_ASSET_SOURCE", "folder")
	var app := (load("res://main.tscn") as PackedScene).instantiate() as CityApplication
	root.add_child(app)
	await process_frame
	app.set_process(false)
	app.main_menu.city_background.set_process(false)
	var fixture := load("res://tests/city_life_test.gd").fixture() as CityState
	assert(app.city_session.activate_document(fixture.document))
	app.frame.select_speed(GameSpeedController.Speed.PAUSED)
	app.preferences.use_classic_zoom_graphics = true
	app.preferences.zoom_graphics = [0, 0, 0, 0, 0, 0]
	app.preferences.visual_enhancements = VisualEnhancementOptions.normalize({"life_cars_enabled": false,
		"life_people_enabled": false, "day_mode": 1, "day_hour": 0.0, "detail_lights_min_zoom": 0})
	app.visual_environment.configure()
	app.map_view.zoom_factor = 0.5
	app.map_view.center_on_tile(Vector2i(64, 64))
	var prepare := app.visual_preparation
	var city := app.document_state.city
	var saved: Dictionary = {}
	var archives: Array = []
	for turn in 8:
		await _settle(app)
		var direction := city.compass_rotation()
		var bank := app.render_caches.region_cache
		if turn < 4:
			saved[direction] = {"bank": bank, "entries": bank.entries.duplicate(), "builds": bank.completed_regions,
				"lights": app.visual_environment.night_lighting.ground}
			if turn == 0:
				archives = prepare.archives.duplicate()
		else:
			assert(bank == saved[direction].bank, "Rotation replaced an unchanged direction bank")
			assert(bank.completed_regions == saved[direction].builds, "Rotation rebuilt unchanged regions")
			for key in bank.entries:
				assert(bank.entries[key] == saved[direction].entries[key], "Warm direction lost region identity")
			assert(app.visual_environment.night_lighting.ground == saved[direction].lights,
				"Rotation discarded a prepared light receiver")
		assert(prepare.archives == archives, "Directions duplicated decoded artwork")
		app.camera_input.rotate_city(false)
	assert(prepare.directions.size() == 4)
	# A build, demolition and terrain change must reach each retained orientation.
	city.set_building_id(64, 64, BuildingTileIds.EMPTY)
	city.set_building_id(40, 40, BuildingTileIds.ROAD_CROSSROADS)
	city.set_land_altitude(80, 80, 4)
	city.set_terrain_id(80, 80, 1)
	app.map_render.refresh_map(false)
	for turn in 4:
		await _settle(app)
		var bank := app.render_caches.region_cache
		var before: Dictionary = saved[city.compass_rotation()].entries
		var reused := 0
		var updated := 0
		for key in bank.entries:
			if bank.entries[key] == before[key]:
				reused += 1
			else:
				updated += 1
		assert(reused > 0 and updated > 0, "Local edits must update only affected regions")
		_compare_fresh(app, bank)
		app.camera_input.rotate_city(true)
	await _settle(app)
	var active := app.render_caches.region_cache
	prepare._trim_banks(0)
	assert(active.ready(), "Memory eviction discarded the visible direction")
	for retained in prepare.directions.values():
		for bank in retained.banks:
			if bank != active and not bank._gpu_pending():
				assert(bank.entries.is_empty(), "Hidden direction escaped the shared memory limit")
	var previous := prepare.directions.values()
	prepare.reset()
	assert(prepare.directions.is_empty())
	for retained in previous:
		for bank in retained.banks:
			assert(bank.entries.is_empty() and bank.gpu_workers.is_empty())
	app.queue_free()
	await process_frame
	print("PASS: four-direction reuse, shared art, local build/demolition/terrain versus fresh pixels, shared eviction and teardown")
	quit()


func _settle(app: CityApplication) -> void:
	var started := Time.get_ticks_msec()
	while true:
		app.frame.process(0.016)
		var complete := app.visual_preparation.ready
		for index in app.visual_preparation.stages:
			complete = complete and app.visual_preparation.banks[index].prefetch_ready()
		for receiver in app.visual_environment.night_lighting.ground_views.values():
			complete = complete and receiver.pending.is_empty() and not receiver.discovery_active
		if complete:
			return
		assert(Time.get_ticks_msec() - started < 60000, "Direction did not settle")
		await process_frame


func _compare_fresh(app: CityApplication, cache: CityRegionCache) -> void:
	var context := CityGpuBuildContext.new()
	var city := CityViewFilter.surface_copy(app.document_state.city, app.view_state.surface_visibility)
	for entry: CityGpuRegionResult in cache.entries.values():
		var fresh := context.render(city, app.asset_state.palette_index_encoding, cache._sprites,
			entry.bounds, cache.view_size, CityViewMode.Mode.CITY, true, true, 1, -1, false, true)
		assert(fresh.ok)
		assert(entry.paint(entry.bounds).get_data() == fresh.paint(entry.bounds).get_data(),
			"Retained direction differs from freshly rendered city after edits")
