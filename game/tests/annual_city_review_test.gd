extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(920, 620)
	var document := Sc2xDocument.create_empty(128, "Annual review fixture").document
	var city := CityState.from_document(document)
	var journal := AnnualCityReview.new()
	var first_year := city.founding_year()
	document.set_misc_u32(Sc2MiscLayout.NORMAL_POPULATION, 100)
	journal.attach(city)
	city.set_age_in_days(CityCalendar.DAYS_PER_YEAR - 1)
	document.set_misc_u32(Sc2MiscLayout.NORMAL_POPULATION, 135)
	var building := BuildingEditResult.new()
	building.ok = true
	building.tile_id = BuildingTileIds.FIRE_STATION
	building.site = Rect2i(12, 18, 3, 3)
	journal.record_building(building)
	assert(journal.events.is_empty(), "Routine service buildings are not historical milestones")
	building.tile_id = BuildingTileIds.MAYOR_HOUSE
	journal.record_building(building)
	assert(journal.events.size() == 1)
	journal.undo_building(building)
	assert(journal.events.is_empty())
	journal.record_building(building)
	var disaster := DisasterStartResult.new()
	disaster.ok = true
	disaster.started = true
	disaster.disaster_type = 1
	disaster.damage_points.append(Vector2i(42, 52))
	journal.record_disaster(disaster, city.age_in_days())
	document.set_misc_u32(Sc2MiscLayout.YEAR_END, 1)
	city.set_auto_budget_enabled(false)
	var month := Sc2MiscLayout.BUDGETS + Sc2BudgetLayout.MONTHS
	document.set_misc_i32(month, 9000)
	document.set_misc_i32(month + Sc2BudgetLayout.MONTH_FUNDING, 10)

	var app := load("res://main.tscn").instantiate() as CityApplication
	preload("res://tests/support/app_fixture.gd").configure(app, true)
	root.add_child(app)
	await process_frame
	app.set_process(false)
	assert(app.city_session.activate_document(document))
	app.reports.prepare_annual_review()
	var engine := app.simulation_state.simulation_engine
	var pending := engine.advance_day()
	assert(pending.ok and not pending.complete)
	_observe(app, pending)
	assert(app.city_status_bar.annual_review_seconds == 0.0)
	app.reports.prepare_annual_review()
	var settled := engine.resolve_annual_budget(BudgetPhase.funding_values(app.document_state.city), true)
	assert(settled.ok and (settled.phase_results["budget"] as BudgetPhase.Result).settled_year)
	_observe(app, settled)
	assert(app.city_status_bar.annual_review_seconds > 0.0)
	var edition := app.reports.annual_review.edition()
	assert(edition.year == first_year and edition.start == 100 and edition.end == 135 and edition.budget == 100)
	assert(edition.events.size() == 2)
	assert(edition.statistics.has("developed") and edition.statistics.has("funds"))
	app.reports.refresh_newspaper_menu()
	var menu := app.city_menu_bar.newspaper_menu.get_popup()
	assert(menu.get_item_index(CityMenuBar.MENU_ANNUAL_REVIEW) >= 0)
	app.city_status_bar.annual_review_requested.emit()
	var dialog := app.reports.annual_newspaper
	assert(dialog.visible)
	AppLocalization.select("de")
	await process_frame
	assert(dialog.size.x < root.size.x and dialog.size.y < root.size.y)
	dialog.hide()
	app.reports.on_newspaper_menu(CityMenuBar.MENU_ANNUAL_REVIEW)
	assert(dialog.visible)
	dialog.hide()

	var archive := Sc2xDocument.encode(document)
	var reloaded := Sc2File.new()
	assert(archive.ok and reloaded.parse(archive.data))
	journal.attach(CityState.from_document(reloaded))
	var saved := journal.edition()
	assert(saved.budget == 100 and saved.events.size() == 2)
	assert(saved.statistics == edition.statistics, "Year-end measurements must survive SC2X save/load")
	assert(journal.editions().size() == 1)
	var migration := reloaded.sc2x_extra_entries[AnnualCityReview.ENTRY]
	var old_archive: Dictionary = JSON.parse_string(migration.get_string_from_utf8())
	old_archive.version = 1
	old_archive.erase("history")
	old_archive.latest.erase("statistics")
	reloaded.sc2x_extra_entries[AnnualCityReview.ENTRY] = JSON.stringify(old_archive).to_utf8_buffer()
	journal.attach(CityState.from_document(reloaded))
	assert(journal.editions().size() == 1 and journal.editions()[0].budget == 100,
		"The previous annual edition must migrate into the chronicle")
	assert(not journal.editions()[0].has("statistics"), "Old years must not receive invented measurements")
	assert(journal.point_in_current_view(saved.events[0]) == Vector2i(42, 52)
		or journal.point_in_current_view(saved.events[1]) == Vector2i(42, 52))
	var source := journal.point_in_current_view(saved.events[0])
	reloaded.set_misc_u32(Sc2MiscLayout.COMPASS, (journal.city.compass_rotation() + 1) % 4)
	assert(journal.point_in_current_view(saved.events[0]) == CityRotationCommand.rotate_point(source, 128, true))
	for completed_year in range(2, 14):
		var observed_city := journal.city
		observed_city.set_age_in_days(completed_year * CityCalendar.DAYS_PER_YEAR - 1)
		journal.prepare()
		observed_city.set_age_in_days(completed_year * CityCalendar.DAYS_PER_YEAR)
		var next_year := SimulationDayResult.new()
		next_year.ok = true
		next_year.complete = true
		next_year.day = observed_city.age_in_days()
		var next_tick := SimulationTickResult.new()
		next_tick.day_results.append(next_year)
		journal.observe(next_tick)
	assert(journal.editions().size() == 10 and journal.history.size() == 10)
	assert(journal.editions().front().year == first_year + 3 and journal.editions().back().year == first_year + 12)
	var ten_years := Sc2xDocument.encode(reloaded)
	var reopened := Sc2File.new()
	assert(ten_years.ok and reopened.parse(ten_years.data))
	journal.attach(CityState.from_document(reopened))
	assert(journal.history.size() == 10)
	var measured_document := Sc2xDocument.create_empty(128, "Statistics fixture").document
	var measured_city := CityState.from_document(measured_document)
	measured_city.set_funds(34567)
	measured_document.set_misc_u32(Sc2MiscLayout.BONDS, 2)
	measured_document.set_misc_u32(Sc2MiscLayout.CITY_VALUE, 200000)
	measured_city.set_building_id(10, 10, BuildingTileIds.ROAD_STRAIGHT_1)
	measured_city.set_building_id(11, 10, BuildingTileIds.MAYOR_HOUSE)
	measured_city.set_building_id(12, 10, BuildingTileIds.TREES_1)
	measured_city.set_building_id(13, 10, BuildingTileIds.RUBBLE_1)
	journal.attach(measured_city)
	var measured := journal._capture_statistics()
	assert(measured.developed == 2 and measured.tiles == 128 * 128)
	assert(measured.funds == 34567 and measured.debt == 20000 and measured.city_value == 200000)
	assert(journal._valid_statistics({"developed": -1, "tiles": 1, "funds": "missing", "unemployment": 500}).is_empty())
	# Keep more than the old three-headline limit, preserving disasters and landmarks.
	for month_index in 6:
		measured_city.set_age_in_days(month_index * CityCalendar.DAYS_PER_MONTH)
		journal.record_disaster(disaster, measured_city.age_in_days())
	assert(journal._headline_events().size() == 6)
	var legacy := EmptyCityTemplate.create()
	var legacy_city := CityState.from_document(legacy)
	legacy_city.set_age_in_days(600)
	journal.attach(legacy_city)
	var older := journal.edition()
	assert(older.start == -1 and older.end == -1 and not older.has("budget") and older.events.is_empty())
	app.queue_free()
	await process_frame
	print("PASS: annual newspaper settlement, pending budget, event location, archive and old-save fallback")
	quit()


func _observe(app: CityApplication, day: SimulationDayResult) -> void:
	var tick := SimulationTickResult.new()
	tick.day_results.append(day)
	app.reports.observe_annual_review(tick)
