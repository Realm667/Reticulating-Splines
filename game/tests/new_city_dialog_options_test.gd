extends SceneTree

var preview_requests := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var dialog := preload("res://src/ui/startup/new_city_terrain_dialog.tscn").instantiate() as NewCityTerrainDialog
	root.add_child(dialog)
	await process_frame
	dialog.reset_fields("Test Mayor")
	dialog.preview_requested.connect(func() -> void: preview_requests += 1)
	assert(dialog.rules_tabs.current_tab == 0 and not dialog.setup_options().expanded)
	assert(dialog.classic_size.visible and not dialog.size_input.visible and not dialog.game_type_input.visible)
	assert(not dialog.mayor_name_input.visible)
	var terrain := dialog.terrain_options()
	assert(terrain.size == 128 and not terrain.native_maps and not terrain.smooth_slopes)
	assert(terrain.features.is_empty() and dialog.year_input.item_count == 4 and dialog.difficulty_input.item_count == 3)
	for key in dialog.feature_inputs:
		assert(not dialog.feature_inputs[key].visible)
	# Hidden Expanded controls cannot leak into Classic generation.
	dialog.size_input.select(dialog.size_input.get_item_index(512))
	dialog.feature_inputs.bay.set_pressed_no_signal(true)
	assert(dialog.terrain_options().size == 128 and dialog.terrain_options().features.is_empty())
	dialog.hills_input.value = 7
	dialog.city_name_input.text = "Test City"
	dialog.year_input.select(3)
	dialog.difficulty_input.select(2)
	dialog.rules_tabs.current_tab = 1
	assert(dialog.setup_options().expanded and dialog.size_input.visible and dialog.game_type_input.visible)
	assert(dialog.mayor_name_input.visible and not dialog.classic_size.visible)
	for index in dialog.size_input.item_count:
		assert(dialog.size_input.get_item_id(index) >= 128 and not dialog.size_input.is_item_disabled(index))
	for key in dialog.feature_inputs:
		assert(dialog.feature_inputs[key].visible and not dialog.feature_inputs[key].tooltip_text.is_empty())
	dialog.size_input.select(dialog.size_input.get_item_index(256))
	dialog.hills_input.value = 11
	dialog.water_input.value = 13
	dialog.trees_input.value = 21
	dialog.feature_inputs.branch.button_pressed = true
	dialog.feature_inputs.bay.button_pressed = true
	terrain = dialog.terrain_options()
	assert(terrain.size == 256 and terrain.native_maps and terrain.smooth_slopes)
	assert(terrain.ocean and terrain.river and terrain.features == ["branch", "bay"])
	terrain.features.clear()
	assert(dialog.terrain_options().features == ["branch", "bay"])
	dialog.game_type_input.select(1)
	dialog.game_type_input.item_selected.emit(1)
	assert(dialog.region_edge() == 3)
	dialog.rules_tabs.current_tab = 0
	assert(dialog.region_edge() == 0 and not dialog.region_size_input.visible)
	assert(dialog.terrain_options().hills == 7 and dialog.terrain_options().features.is_empty())
	assert(not dialog.river_input.disabled)
	dialog.rules_tabs.current_tab = 1
	terrain = dialog.terrain_options()
	assert(terrain.size == 256 and terrain.hills == 11 and terrain.water == 13 and terrain.trees == 21)
	assert(terrain.features == ["branch", "bay"], "Each tab retains its terrain settings")
	assert(dialog.region_edge() == 0, "Returning to Expanded does not silently found a region")
	var setup := dialog.setup_options()
	assert(setup.city_name == "Test City" and setup.mayor_name == "Test Mayor")
	assert(setup.starting_year == 2050 and setup.difficulty == 3)
	assert(preview_requests > 0)
	var landscape := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	dialog.show_preview(landscape, landscape, "Ready")
	assert(dialog.candidate_valid and not dialog.done_button.disabled)
	dialog.invalidate()
	assert(not dialog.candidate_valid and dialog.done_button.disabled)
	dialog.reset_fields("Reset Mayor")
	assert(dialog.preview_view.texture == null and dialog.landscape_background.texture == null)
	assert(not dialog.setup_options().expanded and dialog.terrain_options().features.is_empty())
	dialog.rules_tabs.current_tab = 1
	assert(dialog.terrain_options().size == 128 and dialog.terrain_options().features.is_empty())
	dialog.free()
	print("PASS: Classic/Expanded tabs, original options, isolated terrain settings, creation guards and preview state")
	quit()
