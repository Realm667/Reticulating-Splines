extends SceneTree
## Founding options, one-way conversion, UI dispatch and multiplayer authority.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 850)
	var app := load("res://main.tscn").instantiate() as CityApplication
	preload("res://tests/support/app_fixture.gd").configure(app, true)
	root.add_child(app)
	await process_frame
	app.set_process(false)
	var dialog := app.city_dialogs.new_city_dialog
	dialog.reset_fields("Test Mayor")
	assert(not dialog.setup_options().expanded)
	assert(dialog.game_type_input.is_item_disabled(1))
	dialog.rules_tabs.current_tab = 1
	assert(dialog.setup_options().expanded and dialog.terrain_options().native_maps)
	assert(not dialog.game_type_input.is_item_disabled(1))
	dialog.game_type_input.select(1)
	dialog.game_type_input.item_selected.emit(1)
	assert(dialog.region_edge() == 3 and dialog.region_size_input.visible)
	dialog.rules_tabs.current_tab = 0
	assert(dialog.region_edge() == 0 and dialog.game_type_input.selected == 0)
	assert(not dialog.region_size_input.visible and dialog.classic_size.visible)
	dialog.set_multiplayer_setup(true, true)
	assert(dialog.setup_options().expanded and dialog.rules_tabs.is_tab_disabled(0))
	assert(not dialog.game_type_input.visible and dialog.region_edge() == 0)
	dialog.reset_fields("Test Mayor")
	dialog.set_multiplayer_setup(false)
	assert(not dialog.setup_options().expanded and not dialog.terrain_options().native_maps)
	assert(not dialog.rules_tabs.is_tab_disabled(0) and not dialog.game_type_input.visible)
	for original: Sc2File in [EmptyCityTemplate.create(128), Sc2xDocument.create_empty(64, "Classic SC2X").document]:
		original.set_misc_u32(Sc2MiscLayout.NORMAL_POPULATION, 4000000)
		original.set_misc_i32(Sc2MiscLayout.FUNDS, 1000000)
		assert(app.city_session.activate_document(original))
		app.interface.hide_main_menu()
		app.frame.select_speed(GameSpeedController.Speed.PAUSED)
		ExpandedCity.open(app)
		await process_frame
		var confirmation: ConfirmationDialog
		for child in app.get_children():
			if child is ConfirmationDialog and child.visible:
				confirmation = child
		assert(confirmation != null and confirmation.size.x <= root.size.x and confirmation.size.y <= root.size.y)
		confirmation.hide()
		confirmation.queue_free()
		var before := original.content_snapshot()
		assert(app.reports.annual_review.city == null, "Classic does not record a chronicle")
		app.regions.pending_edge = 2
		assert(not app.regions.found_region(), "Classic cannot found a region through a stale request")
		app.regions.pending_edge = 0
		ExpandedCity.upgrade(app)
		assert(ExpandedRules.enabled(app.document_state.current_document), "Both legacy and Classic SC2X cities can switch")
		assert(before == original.content_snapshot(), "Conversion must preserve the Classic source")
		assert(app.city_dialogs.city_save_dialog.visible)
		app.city_dialogs.city_save_dialog.hide()
		assert(app.document_state.current_save_path.is_empty())
		assert(app.reports.annual_review.city == app.document_state.city)
	var city := app.document_state.city
	city.set_funds(1000000)
	city.document.set_misc_u32(Sc2MiscLayout.NORMAL_POPULATION, 4000000)
	NativeSimulationBridge.run("expanded.unlock", city, null, null, null)
	for kind in 8:
		var point := Vector2i(6 + kind * 6, 12)
		app.current_tool.select_tool_group(5)
		app.current_tool.select_subtool(9 + kind)
		assert(not NetworkCommand.supports_tool(5, 9 + kind), "Rewards cannot alias road slots")
		var result := app.city_edits.apply_map_selection(point, point, [point], false)
		assert(result.changed and ExpandedRules.at(city, point) == kind, "Actual UI dispatch places reward %d" % kind)
		var query := QueryInfo.inspect(city, point)
		assert(query.ok and query.kind == "expanded" and not query.lines.is_empty())
	var classic := Sc2xDocument.create_empty(64, "Multiplayer Expanded fixture").document
	assert(ExpandedRules.enable(classic).is_empty())
	var world := CoopWorld.new()
	assert(world.open(classic), world.error)
	world.city.set_funds(1000000)
	world.city.document.set_misc_u32(Sc2MiscLayout.NORMAL_POPULATION, 4000000)
	NativeSimulationBridge.run("expanded.unlock", world.city, null, null, null)
	var request := {"kind": "build", "revision": world.revision, "group": 5, "tool": 16,
		"start": [20, 20], "finish": [20, 20], "path": [[20, 20]], "dragged": false}
	var accepted := world.command("exp-fixture", request)
	assert(accepted.ok, str(accepted))
	assert(ExpandedRules.at(world.city, Vector2i(20, 20)) == 7)
	request.revision = world.revision
	assert(not world.command("exp-fixture", request).ok, "Host enforces uniqueness")
	app.regions.pending_edge = 2
	assert(app.regions.found_region(), "Expanded can found a region")
	assert(ExpandedRules.enabled(app.regions.campaign.template), "New regional cities inherit Expanded")
	app.queue_free()
	await process_frame
	print("PASS: founding options, legacy/SC2X conversion, eight UI tools, query and multiplayer authority")
	quit()
