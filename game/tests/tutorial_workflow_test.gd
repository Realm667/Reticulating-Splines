extends SceneTree
## Real application integration, with synthetic cities and no user profile.

const DocumentState = preload("res://tests/support/document_state.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	OS.set_environment("OPENSC2K_CITY_RENDERER", "gpu")
	OS.set_environment("OPENSC2K_GRAPHICS_PACK", ProjectSettings.globalize_path("res://../ext/graphics"))
	OS.set_environment("OPENSC2K_DATA_PACK", ProjectSettings.globalize_path("res://../ext/data"))
	OS.set_environment("OPENSC2K_ASSET_SOURCE", "folder")
	var main := (load("res://main.tscn") as PackedScene).instantiate() as CityApplication
	main.preferences.settings_path = "user://tutorial-workflow.cfg"
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.main_menu.city_background.set_process(false)
	assert(main.tutorial != null)
	var tutorial := main.tutorial
	tutorial.open()
	tutorial.panel.sync_layout()
	assert(tutorial.panel.z_index > main.main_menu.z_index, "Learning entry is hidden behind the main menu")
	tutorial.panel.hide()
	AppLocalization.select("de")
	assert(not tutorial.panel.visible, "Changing language reopened a closed learning panel")
	AppLocalization.select("en")
	assert(main.city_session.activate_document(TutorialTrainingCity.create(0)))
	main.frame.select_speed(GameSpeedController.Speed.PAUSED)
	main.visual_preparation.reset()
	var before := DocumentState.capture(main.document_state.current_document)
	var random := main.simulation_state.simulation_engine.random.state
	tutorial.choose_lesson("b5")
	tutorial.facts.begin(main.document_state.city)
	while tutorial.facts.busy:
		tutorial.facts.work()
	assert(not tutorial.goal_ready)
	tutorial.mark("query")
	tutorial.show_tool()
	tutorial.show_place()
	assert(main.simulation_state.simulation_engine.random.state == random)
	assert(DocumentState.capture(main.document_state.current_document) == before)
	# Native no-window layout: themes, long languages and a small logical view.
	for theme_id in ["light", "dark", "classic_windows", "classic_dos", "classic_mac"]:
		AppUiTheme.select(theme_id)
		for locale in ["en", "de", "ko"]:
			AppLocalization.select(locale)
			for size in [Vector2i(960, 540), Vector2i(1600, 1000)]:
				root.size = size
				tutorial.panel.show_page("task")
				for frame in 5:
					await process_frame
				assert(tutorial.panel.size.x <= main.size.x and tutorial.panel.size.y <= main.size.y)
				assert(main.map_view.camera_view_rect.has_area())
	# Completion is never taken from the previous document.
	tutorial.events["quiz:bond"] = true
	tutorial.choose_lesson("d5")
	assert(not tutorial.events.has("quiz:bond"))
	tutorial.answer("bond", true)
	assert(tutorial.goal_ready)
	tutorial.advance()
	assert(tutorial.progress.record.states.d5 == "done")
	await _utilities_and_save(main)
	_check_rotation_and_restart(main)
	_check_repairs_and_lessons(main)
	assert(main.city_session.activate_document(TutorialTrainingCity.create(0)))
	assert(tutorial.lesson.is_empty() and tutorial.events.is_empty())
	main.queue_free()
	await process_frame
	await process_frame
	print("PASS: tutorial application integration, no simulation edits, themes, languages and city switches")
	quit()


func _check_rotation_and_restart(main: CityApplication) -> void:
	var tutorial := main.tutorial
	tutorial.pending_chapter = 9
	tutorial.pending_restore = ""
	tutorial.start_training()
	main.visual_preparation.reset()
	tutorial._extension = Vector2i(45, 48)
	tutorial.query(Vector2i(42, 54))
	assert(tutorial._service == Vector2i(42, 54), "Practice fire station was not queried")
	for rotation in 4:
		var extension := CityRotationCommand.rotate_point(tutorial._extension, 128, false)
		var service := CityRotationCommand.rotate_point(tutorial._service, 128, false)
		main.camera_input.rotate_city(false)
		assert(tutorial._extension == extension and tutorial._service == service, "Tracked coordinates did not rotate")
		assert(tutorial.city.building_id(service.x, service.y) == BuildingTileIds.FIRE_STATION, "Rotated service points to a different building")
	assert(tutorial._extension == Vector2i(45, 48), "Four rotations did not restore the target")
	assert(tutorial.events.get("rotated", false), "Rotation was not observed")
	# Restoring geometry must retain the player's completed/skipped journal.
	tutorial.progress.record.states = {"a1": "done", "b1": "skipped"}
	var checkpoint: String = tutorial.progress.record.checkpoints["9"]
	var original_funds := CityState.from_document(Sc2File.load_path(checkpoint)).funds()
	tutorial.city.set_funds(123)
	tutorial.pending_restore = checkpoint
	tutorial.start_training()
	assert(tutorial.city.funds() == original_funds, "Chapter city was not restored")
	assert(tutorial.progress.record.states == {"a1": "done", "b1": "skipped"}, "Chapter restoration lost journal progress")
	assert(not tutorial.powered_fresh and not tutorial.watered_fresh, "Restored chapter inherited supply evidence")
	tutorial.pending_restore = ""


func _check_repairs_and_lessons(main: CityApplication) -> void:
	var tutorial := main.tutorial
	tutorial.pending_chapter = 4
	tutorial.start_training()
	main.visual_preparation.reset()
	_scan(tutorial)
	assert(not TutorialRules.complete("repair_power", tutorial.facts.values, tutorial.events, tutorial._context()), "Disconnected power exercise passed")
	_apply(main, CityToolIds.Group.POWER, 0, Vector2i(38, 47), Vector2i(45, 47))
	_apply(main, CityToolIds.Group.POWER, 0, Vector2i(38, 46), Vector2i(62, 46))
	_apply(main, CityToolIds.Group.POWER, 0, Vector2i(54, 46), Vector2i(54, 52))
	assert(not tutorial.powered_fresh, "New wires are not evidence of a completed supply phase")
	_days(main, 72)
	_scan(tutorial)
	assert(TutorialRules.complete("repair_power", tutorial.facts.values, tutorial.events, tutorial._context()), "Repaired power was not accepted: " + str(tutorial.facts.values))
	tutorial.goal_ready = true
	tutorial.advance()
	assert(tutorial.lesson.id == "e2", "Power lesson did not advance to water")
	assert(not TutorialRules.complete("repair_water", tutorial.facts.values, tutorial.events, tutorial._context()), "Disconnected water exercise passed")
	_apply(main, CityToolIds.Group.WATER, 0, Vector2i(31, 47), Vector2i(52, 47))
	assert(not tutorial.watered_fresh)
	for day in 180:
		_days(main, 1)
		_scan(tutorial)
		if TutorialRules.complete("repair_water", tutorial.facts.values, tutorial.events, tutorial._context()):
			break
	assert(TutorialRules.complete("repair_water", tutorial.facts.values, tutorial.events, tutorial._context()), "Repaired water was not accepted: " + str(tutorial.facts.values))
	tutorial.choose_lesson("t2")
	_apply(main, CityToolIds.Group.RAIL, 0, Vector2i(75, 50), Vector2i(75, 50))
	_scan(tutorial)
	assert(not TutorialRules.complete("rail", tutorial.facts.values, tutorial.events, tutorial._context()), "Isolated rail passed")
	_apply(main, CityToolIds.Group.RAIL, 0, Vector2i(75, 50), Vector2i(80, 50))
	_scan(tutorial)
	assert(TutorialRules.complete("rail", tutorial.facts.values, tutorial.events, tutorial._context()), "Connected railway was not accepted")
	# Every quiz is reachable and incorrect answers cannot grant completion.
	for lesson in TutorialCatalog.LESSONS:
		if not str(lesson.rule).begins_with("quiz:"):
			continue
		tutorial.choose_lesson(str(lesson.id))
		var key := str(lesson.rule).trim_prefix("quiz:")
		var correct: bool = TutorialCatalog.QUESTIONS[key][1]
		tutorial.answer(key, not correct)
		assert(not tutorial.goal_ready)
		tutorial.answer(key, correct)
		assert(tutorial.goal_ready)
		tutorial.advance()
		assert(tutorial.progress.record.states[lesson.id] == "done")


func _apply(main: CityApplication, group: int, subtool: int, start: Vector2i, finish: Vector2i) -> void:
	main.tool_state.selected_group = group
	main.tool_state.selected_subtool = subtool
	var result := main.city_edits.apply_map_selection(start, finish, [], start != finish)
	assert(result.get("changed", false), str(result))


func _days(main: CityApplication, count: int) -> void:
	for day in count:
		var tick := SimulationTickResult.new()
		tick.ok = true
		tick.day_results.append(main.simulation_state.simulation_engine.advance_day())
		assert(tick.day_results[0].ok)
		main.tutorial.observe_result(tick)


func _scan(tutorial: TutorialController) -> void:
	tutorial.facts.begin(tutorial.city)
	while tutorial.facts.busy:
		tutorial.facts.work()


func _utilities_and_save(main: CityApplication) -> void:
	AppLocalization.select("en")
	var tutorial := main.tutorial
	assert(main.city_session.activate_document(TutorialTrainingCity.create(3)))
	main.visual_preparation.reset()
	main.frame.select_speed(GameSpeedController.Speed.PAUSED)
	tutorial.choose_lesson("b5")
	assert(not tutorial.powered_fresh)
	for index in 22:
		var tick := SimulationTickResult.new()
		tick.ok = true
		tick.day_results.append(main.simulation_state.simulation_engine.advance_day())
		assert(tick.day_results[0].ok)
		tutorial.observe_result(tick)
	assert(tutorial.powered_fresh and tutorial.watered_fresh)
	tutorial.facts.begin(tutorial.city)
	while tutorial.facts.busy:
		tutorial.facts.work()
	assert(TutorialRules.complete("powered", tutorial.facts.values, tutorial.events, tutorial._context()))
	# A real save event binds the record; a load gets its course back, not readiness.
	tutorial.choose_lesson("f1")
	var path := "user://tutorial-workflow-saved.sc2"
	assert(CityFileStore.save_copy(tutorial.city.document, path, main.asset_state.reference_root).ok)
	tutorial.observe("city.saved", {"path": path})
	assert(tutorial.events.get("save", false))
	assert(main.city_session.activate_document(Sc2File.load_path(path), null, "", true))
	assert(tutorial.lesson.id == "f1" and not tutorial.goal_ready)
	assert(not tutorial.events.has("save"))
	main.visual_preparation.reset()
	# Photo mode is purely presentation. Learning input and markers disappear.
	tutorial.panel.show_page("task")
	main.photo_mode.open()
	tutorial.panel.sync_layout()
	assert(not tutorial.panel.visible)
	main.photo_mode.close()
	tutorial.panel.sync_layout()
	assert(tutorial.panel.visible)
	main.coop.session.active = true
	tutorial.panel.sync_layout()
	assert(not tutorial.active() and not tutorial.panel.visible)
	tutorial.mark("query")
	assert(not tutorial.events.has("query"))
	main.coop.session.active = false
	tutorial.panel.sync_layout()
	assert(tutorial.panel.visible)
	await process_frame
