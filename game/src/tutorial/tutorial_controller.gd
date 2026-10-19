class_name TutorialController
extends Node
## Personal learning companion. Observes published state; never runs a sim phase.
@warning_ignore_start("integer_division")

var app: CityApplication
var progress := TutorialProgress.new()
var facts := TutorialFacts.new()
var panel: TutorialPanel
var city: CityState
var events: Dictionary = {}
var lesson: Dictionary = {}
var goal_ready := false
var powered_fresh := false
var watered_fresh := false
var paused := false
var pending_chapter := 0
var pending_restore := ""
var selected_article := "controls"
var hint := 0
var dismissed: Array[String] = []
var advice: Array[String] = []
var _advice_candidate: Array[String] = []
var _advice_stable := 0
var _interval := 0.0
var _idle := 0.0
var _initial_rotation := 0
var _last_rotation := 0
var _lesson_age := 0
var _power_topology: Array = []
var _water_topology: Array = []
var _last_center := Vector2i(-1, -1)
var _navigating := false
var _persist_failed := false
var _extension := Vector2i(-1, -1)
var _service := Vector2i(-1, -1)


func _init(application: CityApplication) -> void:
	app = application


func _ready() -> void:
	progress.path = app.preferences.settings_path + ".tutorial.json"
	progress.load_store()
	panel = TutorialPanel.new(self)
	app.add_child(panel)
	app.scripting.observed.connect(observe)
	app.map_view.zoom_changed.connect(func(_percent: int): mark("zoom"))
	app.map_view.viewport_changed.connect(_camera_changed)
	app.city_dialogs.budget_dialog.visibility_changed.connect(func():
		if app.city_dialogs.budget_dialog.visible:
			mark("budget"))
	app.main_overlays.settings_dialog.visibility_changed.connect(func():
		if app.main_overlays.settings_dialog.visible:
			mark("settings"))
	app.city_menu_bar.help_menu_requested.connect(func(id: int):
		if id == CityMenuBar.MENU_LEARNING:
			open())
	app.main_menu.learning_requested.connect(open)
	set_process(true)


func available() -> bool:
	return city != null and city == app.document_state.city and not app.coop.active() and not app.tool_state.landscape_editor and not app.city_files.load_in_progress


func active() -> bool:
	return available() and (not lesson.is_empty() or int(progress.data.advisor) > 0)


func open() -> void:
	progress.data.invited = true
	_store()
	panel.show_page("home")


func activated() -> void:
	city = app.document_state.city
	progress.bind_city(app.document_state.current_save_path)
	events = {}
	dismissed.clear()
	advice.clear()
	facts = TutorialFacts.new()
	_initial_rotation = city.compass_rotation() if city != null else 0
	_last_rotation = _initial_rotation
	_last_center = Vector2i(-1, -1)
	_power_topology = []
	_water_topology = []
	powered_fresh = false
	watered_fresh = false
	lesson = TutorialCatalog.lesson(str(progress.record.get("current", "")))
	goal_ready = false
	panel.target = Vector2i(-1, -1)
	panel.hide()
	if not lesson.is_empty():
		_select(str(lesson.id), false)
	elif not bool(progress.data.invited) and available():
		# A single small invitation, never a modal or an automatic course start.
		progress.data.invited = true
		_store()
		panel.show_page("invitation")


func observe(type: String, detail: Dictionary) -> void:
	if type == "city.saved" and available():
		mark("save")
		_check_write(progress.saved_city(str(detail.get("path", ""))))
		return
	if not active():
		return
	match type:
		"tool.applied", "tool.undone":
			if type == "tool.undone" or detail.get("changed", false):
				powered_fresh = false
				watered_fresh = false
				_power_topology = []
				_water_topology = []
				var group := app.tool_state.selected_group
				if group >= 9 and group <= 11 and city.rci_demand()[group - 9] > 0:
					var command := app.tool_state.last_edit_command as ZoneEditResult
					if command != null and not command.tile_indices.is_empty():
						var index := int(command.tile_indices[0])
						_extension = Vector2i(index / city.map_size, index % city.map_size)
						mark("demand_zone")
				if group == CityToolIds.Group.DISPATCH:
					mark("dispatch")
		"sim.speed":
			if app.simulation_state.speed_controller.speed == GameSpeedController.Speed.PAUSED:
				mark("pause")
			elif app.simulation_state.speed_controller.speed == GameSpeedController.Speed.TURTLE:
				mark("turtle")
		"view.mode":
			var mode := CityViewMode.key(app.view_state.overlay_mode)
			mark("view:" + mode)
			if CityViewMode.is_data(app.view_state.overlay_mode):
				mark("data")
		"tool.selected":
			if app.tool_state.selected_group == CityToolIds.Group.PORTS:
				mark("ports")
			elif app.tool_state.selected_group == CityToolIds.Group.REWARDS:
				mark("rewards")


func observe_result(result: SimulationTickResult) -> void:
	if not active():
		return
	for day in result.day_results:
		if day.ok and day.complete:
			if "power" in day.applied:
				powered_fresh = true
				_power_topology = _topology()
			if "water" in day.applied:
				watered_fresh = true
				_water_topology = _topology()
	if app.simulation_state.simulation_engine.active_disaster_type > 0:
		mark("disaster")


func query(point: Vector2i) -> void:
	if not active() or city.index_of(point.x, point.y) < 0:
		return
	mark("query")
	if city.building_id(point.x, point.y) == 0 and city.terrain_id(point.x, point.y) == 0 and not city.is_water(point.x, point.y):
		mark("site")
	if city.building_id(point.x, point.y) in [BuildingTileIds.POLICE_STATION, BuildingTileIds.FIRE_STATION, BuildingTileIds.SCHOOL, BuildingTileIds.HOSPITAL]:
		mark("query_service")
		_service = point
	if city.building_id(point.x, point.y) in [BuildingTileIds.SMALL_PARK, BuildingTileIds.BIG_PARK]:
		mark("query_park")
	if app.tool_state.selected_subtool == CityToolIds.Query.TRIP_REACH:
		mark("trip")


func mark(event: String) -> void:
	if not active() or _navigating:
		return
	events[event] = true
	_idle = 0.0


func _camera_changed() -> void:
	if not active() or _navigating:
		return
	var center := app.map_view.center_tile()
	if _last_center.x >= 0 and center != _last_center and app.map_view.is_panning():
		mark("pan")
	_last_center = center


func _topology() -> Array:
	return city.mirror_signature(["XBLD", "XZON", "XUND", "XTER", "ALTM"])


func rotate_targets(counter_clockwise: bool) -> void:
	if city == null:
		return
	if _extension.x >= 0:
		_extension = CityRotationCommand.rotate_point(_extension, city.map_size, counter_clockwise)
	if _service.x >= 0:
		_service = CityRotationCommand.rotate_point(_service, city.map_size, counter_clockwise)
	panel.rotate_target(counter_clockwise)
	# The unfinished snapshot and its target coordinates belong to the old view.
	facts = TutorialFacts.new()
	powered_fresh = false
	watered_fresh = false
	goal_ready = false
	mark("rotated")
	_last_rotation = city.compass_rotation()
	panel.refresh_task()


func _process(delta: float) -> void:
	if panel == null:
		return
	panel.sync_layout()
	if not active() or (app.photo_mode != null and app.photo_mode.active):
		return
	if app.visual_preparation.busy or app.city_files.save_in_progress:
		return
	if facts.busy:
		facts.work()
	_interval += delta
	if _interval < 0.5:
		return
	_interval = 0.0
	var rotation := city.compass_rotation()
	if rotation != _last_rotation:
		mark("rotated")
		_last_rotation = rotation
	if not facts.busy and facts.signature != TutorialFacts.stamp(city):
		facts.begin(city)
		return
	if facts.busy:
		return
	# Topology edits invalidate supply evidence until a regular phase confirms it.
	if _power_topology != _topology():
		powered_fresh = false
	if _water_topology != _topology():
		watered_fresh = false
	var context := _context()
	if bool(progress.record.get("practice", false)):
		if int(facts.values.get("residential", 0)) > int(facts.values.get("powered", 0)):
			events.power_failure = true
		if int(facts.values.get("residential", 0)) > int(facts.values.get("watered", 0)):
			events.water_failure = true
	var previous := goal_ready
	goal_ready = not lesson.is_empty() and TutorialRules.complete(str(lesson.rule), facts.values, events, context)
	if goal_ready and not previous:
		_idle = 0.0
		panel.refresh_task()
	elif not goal_ready and previous:
		panel.refresh_task()
	if not goal_ready and DisplayServer.window_is_focused() and not app.frame._simulation_suspended(false):
		_idle += 0.5
	panel.update_status(status())
	var candidates := TutorialRules.advisor(facts.values, context, int(progress.data.advisor))
	if candidates == _advice_candidate:
		_advice_stable += 1
	else:
		_advice_candidate = candidates
		_advice_stable = 0
	# Stable for two observations. No popup or repeat notification.
	if _advice_stable >= 2 and advice != candidates:
		advice = candidates
		if panel.page == "advisor":
			panel.show_page("advisor", false)


func _context() -> Dictionary:
	var funding := BudgetPhase.funding_values(city)
	var report := BudgetReport.capture(city, funding)
	var extension := TutorialFacts.site_access(city, _extension) if _extension.x >= 0 else {}
	var service_budget: int = {BuildingTileIds.POLICE_STATION: Sc2BudgetLayout.POLICE, BuildingTileIds.FIRE_STATION: Sc2BudgetLayout.FIRE,
		BuildingTileIds.SCHOOL: Sc2BudgetLayout.SCHOOL, BuildingTileIds.HOSPITAL: Sc2BudgetLayout.HEALTH}.get(city.building_id(_service.x, _service.y), -1) if _service.x >= 0 else -1
	return {"available": available() and not facts.busy, "powered_fresh": powered_fresh,
		"watered_fresh": watered_fresh, "population": city.population(), "year": city.current_year(),
		"practice": bool(progress.record.get("practice", false)), "disaster": app.simulation_state.simulation_engine.active_disaster_type,
		"forecast": report.estimated_cash, "rotation_returned": city.compass_rotation() == _initial_rotation,
		"extension_ready": extension.get("rci", false) and extension.get("powered", false) and extension.get("transport", false),
		"service_funded": service_budget >= 0 and funding[service_budget] > 0,
		"budget_period": city.age_in_days() / CityCalendar.DAYS_PER_MONTH > _lesson_age / CityCalendar.DAYS_PER_MONTH}


func status() -> String:
	if not available():
		return tr("Learning is available in single-player cities.")
	if facts.busy or app.visual_preparation.busy:
		return tr("Checking the current city…")
	if goal_ready:
		return tr("Goal confirmed. Continue when you are ready.")
	if not lesson.is_empty() and str(lesson.rule) in ["powered", "watered", "repair_power", "repair_water", "population"]:
		if app.simulation_state.speed_controller.speed == GameSpeedController.Speed.PAUSED:
			return tr("The city is paused. Resume when you are ready to check the simulation.")
		if str(lesson.rule) in ["watered", "repair_water"] and watered_fresh:
			return tr(TutorialCatalog.ARTICLES.water[2])
		if str(lesson.rule) in ["powered", "repair_power"] and powered_fresh:
			return tr(TutorialCatalog.ARTICLES.power[1])
		return tr("Waiting for the regular simulation calculation. Building a connection alone is not enough.")
	return tr("Need help? Try the next hint.") if _idle >= 45 else tr("In progress")


func choose_lesson(id: String) -> void:
	if not available():
		panel.show_page("home")
		return
	_select(id)


func _select(id: String, checkpoint := true) -> void:
	lesson = TutorialCatalog.lesson(id)
	if lesson.is_empty():
		return
	progress.record.current = id
	progress.record.get_or_add("states", {})
	selected_article = str(lesson.article)
	goal_ready = false
	hint = 0
	_idle = 0.0
	_lesson_age = city.age_in_days()
	# Interaction objectives are specific to this visit, not an old city.
	events = {}
	_extension = Vector2i(-1, -1)
	_service = Vector2i(-1, -1)
	if progress.record.get("exercise", "") == "utilities_outage":
		events.power_failure = true
		events.water_failure = true
	_initial_rotation = city.compass_rotation()
	_last_rotation = _initial_rotation
	if checkpoint and bool(progress.record.get("practice", false)):
		_save_checkpoint(int(lesson.chapter))
	_store()
	panel.show_page("task")


func advance(state := "done") -> void:
	if lesson.is_empty() or (state == "done" and not goal_ready):
		return
	progress.record.states[lesson.id] = state
	var index := TutorialCatalog.LESSONS.find(lesson)
	if str(lesson.id) == "f4" or index == TutorialCatalog.LESSONS.size() - 1:
		end_course()
		return
	_select(str(TutorialCatalog.LESSONS[index + 1].id))


func end_course() -> void:
	progress.record.current = ""
	lesson = {}
	_store()
	panel.show_page("journal")


func set_advisor(mode: int) -> void:
	progress.data.advisor = clampi(mode, 0, 2)
	mark("advisor")
	_store()
	panel.show_page("advisor")


func answer(key: String, value: bool) -> void:
	var expected: bool = TutorialCatalog.QUESTIONS[key][1]
	if value == expected:
		mark("quiz:" + key)
		goal_ready = TutorialRules.complete(str(lesson.rule), facts.values, events, _context())
		panel.refresh_task()
	else:
		hint = 2
		panel.refresh_task()
		panel.update_status(tr("Read the explanation and try again."))


func show_tool() -> void:
	if not available() or lesson.is_empty():
		return
	var group := int(lesson.tool[0])
	# Focus identifies the tool; the player still selects and places it.
	var button: Button = app.city_toolbar.toolbar_buttons[group]
	button.grab_focus()
	var parent := button.get_parent()
	while parent != null and not parent is ScrollContainer:
		parent = parent.get_parent()
	if parent is ScrollContainer:
		parent.ensure_control_visible(button)
	app.status_label.text = tr(ToolCatalog.group(group).name)


func open_advice(key: String) -> void:
	if not available():
		return
	if key == "budget":
		app.budget.open_manual_budget()
		return
	var mode: CityViewMode.Mode = {"power": CityViewMode.Mode.POWER, "water": CityViewMode.Mode.WATER,
		"growth": CityViewMode.Mode.GROWTH, "disaster": CityViewMode.Mode.CITY}[key]
	app.menus.select_view(mode)
	var target_key: String = {"power": "unpowered_homes", "water": "dry_homes", "growth": "empty_zone", "disaster": "homes"}[key]
	var point: Vector2i = facts.targets.get(target_key, Vector2i(-1, -1))
	if point.x >= 0:
		_navigating = true
		app.map_view.center_on_tile(point)
		_navigating = false
		panel.target = point
		panel.target_building = city.building_id(point.x, point.y)
		panel.target_rotation = city.compass_rotation()


func show_place() -> void:
	if not available() or lesson.is_empty():
		return
	var key := "residential"
	if str(lesson.rule) == "site":
		key = "free"
	elif str(lesson.rule) in ["repair_power", "repair_water"]:
		key = "residential"
	var target: Vector2i = facts.targets.get(key, Vector2i(-1, -1))
	if str(lesson.rule) == "expand" and _extension.x >= 0:
		target = _extension
	if target.x >= 0:
		_navigating = true
		app.map_view.center_on_tile(target)
		_navigating = false
		panel.target = target
		panel.target_building = city.building_id(target.x, target.y)
		panel.target_rotation = city.compass_rotation()


func request_training(chapter: int, restore := "") -> void:
	if app.coop.active() or not app.asset_state.assets_ready:
		return
	pending_chapter = chapter
	pending_restore = restore
	var confirm := ConfirmationDialog.new()
	confirm.dialog_autowrap = true
	confirm.title = tr("Start a separate practice city?")
	confirm.dialog_text = tr("This replaces the current view. Unsaved changes can be saved first. Practice uses Easy, 1900 (2050 for late development), a flat 128×128 map and no automatic disasters. Prepared chapters include normally priced starting buildings.")
	if not restore.is_empty():
		confirm.dialog_text = tr("Return to your saved chapter start? Later practice changes will be replaced. You can save the current city first.")
	app.add_child(confirm)
	confirm.confirmed.connect(func():
		confirm.queue_free()
		app.city_files.request_city_exit("tutorial_city"))
	confirm.canceled.connect(confirm.queue_free)
	confirm.popup_centered(Vector2i(560, 240))


func start_training() -> void:
	if app.coop.active():
		return
	var restored_record := progress.record.duplicate(true) if not pending_restore.is_empty() else {}
	var document := Sc2File.load_path(pending_restore) if not pending_restore.is_empty() else TutorialTrainingCity.create(pending_chapter)
	if document == null or not document.is_valid():
		app.interface.show_error(tr("The practice city could not be opened."))
		return
	if not app.city_session.activate_document(document):
		return
	app.document_state.current_save_path = ""
	app.document_state.current_city_saved_once = false
	progress.key = ""
	progress.record = restored_record if not restored_record.is_empty() else {"practice": true, "states": {}, "exercise": "utilities_outage" if pending_chapter == 4 else ""}
	app.frame.select_speed(GameSpeedController.Speed.PAUSED)
	app.map_view.center_on_tile(Vector2i(45, 48))
	for entry in TutorialCatalog.LESSONS:
		if int(entry.chapter) == pending_chapter:
			_select(str(entry.id))
			break


func _save_checkpoint(chapter: int) -> void:
	var checkpoints: Dictionary = progress.record.get_or_add("checkpoints", {})
	var key := str(chapter)
	if checkpoints.has(key):
		return
	var folder := progress.path.get_base_dir().path_join("tutorial-checkpoints")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var path := folder.path_join("%s-%d.sc2" % [str(Time.get_ticks_usec()), chapter])
	var result := CityFileStore.save_copy(city.document, path, app.asset_state.reference_root)
	if result.ok:
		checkpoints[key] = path
	else:
		_check_write(ERR_FILE_CANT_WRITE)


func _store() -> void:
	_check_write(progress.write())


func _check_write(error: Error) -> void:
	if error != OK and not _persist_failed:
		_persist_failed = true
		app.interface.show_error(tr("Learning progress could not be saved. The city is still playable."))
