extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 850)
	var app := load("res://main.tscn").instantiate() as CityApplication
	preload("res://tests/support/app_fixture.gd").configure(app, true)
	root.add_child(app)
	await process_frame
	app.set_process(false)
	var document := Sc2xDocument.create_empty(64, "Upgrade UI").document
	assert(ExpandedRules.enable(document).is_empty())
	document.set_misc_u32(Sc2MiscLayout.START_YEAR, 1950)
	document.set_misc_u32(Sc2MiscLayout.NORMAL_POPULATION, 100000)
	var city := CityState.from_document(document)
	city.set_funds(1000000)
	var built := BuildingCommand.apply(city, 13, 0, Vector2i(12, 12), SimLfsrRandom.new(1), SimRandom.new(1))
	assert(built.ok, built.error)
	assert(app.city_session.activate_document(document))
	app.interface.hide_main_menu()
	app.frame.select_speed(GameSpeedController.Speed.PAUSED)
	city = app.document_state.city
	# Loaded-city census may replace a synthetic population; retain the real saved peak gate.
	var bytes := document.find_chunk("XEXP").decoded_payload.duplicate()
	BinaryData.write_u32_be(bytes, 4, 100000)
	document.find_chunk("XEXP").set_decoded_payload(bytes)
	for locale: String in ["en", "de", "es", "fr", "it", "ko", "pt_BR"]:
		AppLocalization.select(locale)
		app.query_choices.open_query(Vector2i(12, 12))
		await process_frame
		var button := app.city_dialogs.query_dialog.upgrade_button
		assert(button.visible and not button.disabled, "upgrade available " + locale)
		assert(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(button.get_global_rect()), "upgrade reachable " + locale)
	app.city_dialogs.query_dialog.upgrade_button.pressed.emit()
	assert(BuildingUpgrades.info(city, Vector2i(12, 12)).target == 1, "real UI action")
	assert(app.city_dialogs.query_dialog.upgrade_button.disabled, "construction blocks second request")
	app.map_view.presentation.set_upgrade_city(city)
	assert(app.map_view.presentation.upgrade_markers.size() == 1)
	app.query_choices.close_query(false)
	document.set_misc_u32(Sc2MiscLayout.CITY_DAYS, 75)
	NativeSimulationBridge.run("milestones", city, null, null, null)
	app.map_view.presentation.set_upgrade_city(city)
	assert(int(app.map_view.presentation.upgrade_markers[0][3]) == 1, "completion updates marker without sprite changes")
	# A Shared snapshot keeps this city and its XUPG revision when only a foreign star changes.
	document.sc2x_metadata = document.sc2x_metadata.copy()
	document.sc2x_metadata.extensions["upgrade_view_markers"] = [[20, 20, BuildingTileIds.POLICE_STATION, 1, 0], ["bad", 0, 0, 0, 0]]
	app.map_view.presentation.set_upgrade_city(city)
	assert(app.map_view.presentation.upgrade_markers.size() == 2, "foreign snapshot invalidates marker cache; malformed metadata ignored")
	document.sc2x_metadata = document.sc2x_metadata.copy()
	document.sc2x_metadata.extensions["upgrade_view_markers"] = []
	app.map_view.presentation.set_upgrade_city(city)
	assert(app.map_view.presentation.upgrade_markers.size() == 1, "removed foreign marker does not persist")
	app.query_choices.open_query(Vector2i(12, 12))
	var funds := city.funds()
	var removed := DemolishCommand.apply_path(city, 0, 0, [Vector2i(12, 12)], SimRandom.new(1))
	assert(removed.ok)
	app.query_choices.run_upgrade()
	assert(city.funds() == funds - removed.cost, "stale query cannot spend on replaced parcel")
	app.queue_free()
	await process_frame
	print("building_upgrades_ui_test: PASS")
	quit()
