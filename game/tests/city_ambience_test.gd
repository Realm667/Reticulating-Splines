extends SceneTree

const DocumentState = preload("res://tests/support/document_state.gd")
const Settings = preload("res://src/ui/settings/app_settings_store.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	assert(AudioServer.get_driver_name() == "Dummy")
	var app := (load("res://main.tscn") as PackedScene).instantiate() as CityApplication
	root.add_child(app)
	await process_frame
	app.set_process(false)
	app.main_menu.city_background.set_process(false)
	assert(app.city_session.activate_document(EmptyCityTemplate.create(128)))
	app.main_menu.hide()
	app.audio_controller.application_has_focus = true
	var city := app.document_state.city
	city.set_sound_enabled(true)
	var map := app.map_view
	map.city = city
	var mix := app.frame.city_ambience
	var falls := Vector2i(64, 64)
	var road := falls + Vector2i(2, 0)
	assert(city.set_building_id(66, 66, BuildingTileIds.LOWER_CLASS_HOMES_1X1_1))
	var bank := falls + Vector2i(-2, 1)
	assert(city.set_terrain_id(falls.x, falls.y, TerrainTileIds.WATERFALL))
	assert(city.set_terrain_id(bank.x, bank.y, TerrainTileIds.SHORE_FLAT))
	assert(city.set_tile_flag(bank.x, bank.y, Sc2TileFlags.SALT_WATER, true))
	assert(city.set_building_id(road.x, road.y, BuildingTileIds.ROAD_STRAIGHT_1))
	map.zoom_factor = 1.0
	map.source_center = CityAmbience._tile_position(city, falls)
	mix.process(0.4, false)
	assert(mix.root == null, "Existing installations opt into the additional audio")
	var snapshot := DocumentState.capture(city.document)
	var engine := app.simulation_state.simulation_engine
	var rng := [engine.random.state, engine.lfsr_random.state, engine.game_random.state]
	app.preferences.city_ambience_enabled = true
	mix.process(0.4, false)
	assert(mix.beds.size() == CityAmbience.BEDS.size(), "Loaded beds: %s (map city: %s, overlay: %s)" % [mix.beds.keys(), map.city, app.view_state.overlay_mode])
	assert(mix.beds.falls.gain > 0.12 and mix.beds.falls.player.playing)
	assert(mix.beds.shore.gain > 0.0 and mix.beds.shore.player.playing)
	assert(mix.beds.shore.target_pan < 0.0 and mix.beds.street.target_pan > 0.0)
	assert(mix.beds.wind.gain < 0.001)
	var falls_gain: float = mix.beds.falls.gain
	var falls_player: AudioStreamPlayer2D = mix.beds.falls.player
	assert((falls_player.stream as AudioStreamOggVorbis).loop)
	app.preferences.city_ambience_volume = 0.23
	mix.process(0.0, false)
	assert(is_equal_approx(falls_player.volume_linear, falls_gain * 0.23))
	assert(mix.beds.falls.player == falls_player)

	# Real presentation positions, varied footsteps and periodic shoreline accents.
	var figure := CityLifeController.Figure.new()
	figure.walking = true
	figure.position = map.source_center + Vector2(-100.0, 0.0)
	figure.visibility = 1.0
	app.city_life.figures.append(figure)
	var view := CityAmbience._listening_area(map)
	assert(mix._figures(view, 1.0).z > 0.0 and mix.shots.size() == 1)
	var walker: CityAmbience.Voice = mix.shots[0]
	assert(walker.figure == figure)
	mix.process(0.10, false)
	assert(walker.target_pan < 0.0)
	figure.position.x += 200.0
	mix.process(0.10, false)
	assert(walker.target_pan > 0.0)
	var shore: Vector3 = mix._terrain_sources(city, falls, view).shore
	mix.elapsed = mix.next_wave
	mix._place_events({"shore": shore}, 1.0)
	assert(mix.source_cooldown.has("wave") and mix.shots.size() == 2)
	mix._place_events({"shore": shore}, 1.0)
	assert(mix.shots.size() == 2, "A single wave opportunity should not stack voices")

	var weather := app.visual_environment.weather
	weather.rain = 0.8
	app.visual_environment.clouds.precipitation_readiness = 1.0
	mix.process(0.5, false)
	assert(mix.beds.wet_street.target > 0.0 and is_zero_approx(mix.beds.street.target))
	map.zoom_factor = 0.1
	mix.process(0.08, false)
	assert(mix.beds.falls.gain > 0.0, "Zoom abruptly cut the near waterfall")
	for i in 14:
		mix.process(0.25, false)
	assert(mix.height > 0.99 and mix.beds.wind.gain > 0.04)
	assert(mix.beds.falls.gain < falls_gain * 0.08)
	assert(mix.distant_filter.cutoff_hz < 750.0)
	assert(mix.beds.distant.target > 0.0 and mix.beds.distant.player.bus == CityAmbience.FAR_BUS)

	for i in 12:
		mix._shot("step_1", str(i), map.source_center, 0.2, 300.0, 1.0)
	assert(mix.shots.size() == CityAmbience.MAX_SHOTS)
	app.audio_controller.application_has_focus = false
	mix.process(0.0, false)
	assert(mix.shots.is_empty() and not mix.beds.wind.player.playing)
	app.audio_controller.background_audio = true
	mix.process(1.0, false)
	assert(mix.beds.wind.player.playing)
	app.preferences.city_ambience_enabled = false
	mix.process(0.0, false)
	assert(not mix.beds.wind.player.playing and not mix.root.visible)
	assert(DocumentState.capture(city.document) == snapshot)
	assert([engine.random.state, engine.lfsr_random.state, engine.game_random.state] == rng)

	var path := "user://city-ambience-test.cfg"
	var options := Settings.SaveOptions.new()
	options.city_ambience_enabled = true
	options.city_ambience_volume = 0.23
	assert(Settings.save_values(0.8, 0.8, false, path, options) == OK)
	var saved := Settings.load_values(path)
	assert(saved.city_ambience_enabled and is_equal_approx(saved.city_ambience_volume, 0.23))
	var dialog := app.main_overlays.settings_dialog
	dialog.set_city_ambience(true, 0.23)
	assert(dialog.city_ambience_slider.editable and dialog.selected_values().city_ambience_enabled)
	assert(is_equal_approx(dialog.selected_values().city_ambience_volume, 0.23))
	dialog.city_ambience_check.button_pressed = false
	assert(not dialog.city_ambience_slider.editable and not dialog.selected_values().city_ambience_enabled)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("PASS: spatial ambience, pan, zoom, water, rain, voice cap, focus, silence, settings and unchanged simulation")
	app.queue_free()
	await process_frame
	quit()
