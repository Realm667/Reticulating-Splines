extends SceneTree
## Read-only evidence, bounded work and local progress isolation.
@warning_ignore_start("integer_division")

const DocumentState = preload("res://tests/support/document_state.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var ids := {}
	for lesson in TutorialCatalog.LESSONS:
		assert(not ids.has(lesson.id))
		ids[lesson.id] = true
		assert(TutorialCatalog.ARTICLES.has(lesson.article))
		for prerequisite in lesson.requires:
			assert(not TutorialCatalog.lesson(prerequisite).is_empty())
	var document := EmptyCityTemplate.create(512)
	var city := CityState.from_document(document)
	city.set_zone_id(25, 25, 1)
	city.set_building_id(25, 25, BuildingTileIds.LOWER_CLASS_HOMES_1X1_1)
	city.set_tile_flag(25, 25, Sc2TileFlags.PIPED, true)
	var before := DocumentState.capture(document)
	var facts := TutorialFacts.new()
	facts.begin(city)
	var slices := 0
	var scan_usec := 0
	var longest_slice := 0
	while facts.busy:
		facts.work(700)
		slices += 1
		scan_usec += facts.last_slice_usec
		longest_slice = maxi(longest_slice, facts.last_slice_usec)
	assert(slices > 1, "Large-map inspection must yield")
	print("512x512 learning scan: ", slices, " slices, mean ", scan_usec / slices, " us, max ", longest_slice, " us")
	assert(facts.values.homes == 1 and facts.values.piped == 1 and facts.values.watered == 0)
	assert(not TutorialRules.complete("watered", facts.values, {}, {"watered_fresh": true}))
	assert(not TutorialRules.complete("powered", {"target_powered": 1}, {}, {"powered_fresh": false}))
	assert(TutorialRules.complete("powered", {"target_powered": 1}, {}, {"powered_fresh": true}))
	assert(not TutorialRules.complete("park", {"park": 1}, {"query": true}, {}))
	assert(TutorialRules.advisor(facts.values, {"available": false}, 2).is_empty())
	assert(TutorialRules.advisor(facts.values, {"available": true}, 0).is_empty())
	var advice := TutorialRules.advisor(facts.values, {"available": true, "powered_fresh": true, "watered_fresh": true, "disaster": 1, "forecast": -1}, 2)
	assert(advice.slice(0, 3) == ["disaster", "power", "water"])
	assert(DocumentState.capture(document) == before, "Tutorial inspection changed the city")
	# A snapshot must not mix a later edit into its remaining rows.
	facts.begin(city)
	city.set_zone_id(26, 26, 1)
	city.set_building_id(26, 26, BuildingTileIds.LOWER_CLASS_HOMES_1X1_1)
	while facts.busy:
		facts.work()
	assert(facts.values.homes == 1 and facts.signature != TutorialFacts.stamp(city))
	_check_progress()
	_check_regular_simulation()
	for chapter in [0, 2, 4, 9, 10]:
		var practice := TutorialTrainingCity.create(chapter)
		assert(practice != null and practice.is_valid())
		var model := CityState.from_document(practice)
		assert(model.no_disasters_enabled() and model.difficulty() == 1)
		assert(model.current_year() == (2050 if chapter == 10 else 1900))
		assert(model.funds() <= 20000)
		assert(model.is_water(25, 40))
		if chapter >= 2:
			facts.begin(model)
			while facts.busy:
				facts.work()
			assert(facts.values.power > 0 and facts.values.residential > 0 and facts.values.road > 0)
			if chapter >= 3:
				assert(facts.values.pump > 0)
	print("PASS: tutorial evidence, city isolation, snapshots, priority, persistence and practice cities")
	quit()


func _check_progress() -> void:
	var folder := "user://tutorial-test"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var first := folder.path_join("first.sc2")
	var copy := folder.path_join("renamed.sc2")
	var older := folder.path_join("older.sc2")
	for entry in [[first, "city-one"], [copy, "city-one"], [older, "city-zero"]]:
		var file := FileAccess.open(entry[0], FileAccess.WRITE)
		file.store_string(entry[1])
		file.close()
	var store := TutorialProgress.new()
	store.path = folder.path_join("progress.json")
	store.bind_city(first)
	store.record = {"current": "b5", "states": {"a1": "done"}}
	assert(store.write() == OK)
	store.record.current = "c4"
	assert(store.write() == OK, "Atomic replacement of an existing record failed")
	var restored := TutorialProgress.new()
	restored.path = store.path
	restored.load_store()
	restored.bind_city(copy)
	assert(restored.record.current == "c4", "Renaming or copying a save loses the binding")
	restored.bind_city(older)
	assert(restored.record.is_empty(), "An older city inherited a newer active objective")
	restored.record = {"current": "a1"}
	assert(restored.saved_city(older) == OK)
	restored.bind_city(first)
	assert(restored.record.current == "c4", "Save As overwrote another snapshot's progress")
	var file := FileAccess.open(store.path, FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	var recovered := TutorialProgress.new()
	recovered.path = store.path
	recovered.load_store()
	assert(recovered.data.records.is_empty())
	file = FileAccess.open(store.path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 1, "advisor": {}, "hidden": 12, "records": {"bad": [], FileAccess.get_sha256(first): {"current": [], "states": "bad", "checkpoints": false}}}))
	file.close()
	recovered.load_store()
	recovered.bind_city(first)
	assert(recovered.record.current == "" and recovered.record.states.is_empty())
	assert(recovered.data.advisor == 0 and recovered.data.hidden.is_empty())


func _check_regular_simulation() -> void:
	var first := CityState.from_document(TutorialTrainingCity.create(3))
	var second := CityState.from_document(TutorialTrainingCity.create(3))
	var observed := SimulationEngine.new(first, 71, 73, 79)
	var control := SimulationEngine.new(second, 71, 73, 79)
	var facts := TutorialFacts.new()
	var power := false
	var water := false
	for day in 72:
		var result := observed.advance_day()
		var baseline := control.advance_day()
		assert(result.ok and baseline.ok)
		power = power or "power" in result.applied
		water = water or "water" in result.applied
		facts.begin(first)
		while facts.busy:
			facts.work()
		TutorialRules.advisor(facts.values, {"available": true, "powered_fresh": power, "watered_fresh": water}, 2)
		TutorialRules.complete("watered", facts.values, {}, {"watered_fresh": water})
		assert(DocumentState.capture(first.document) == DocumentState.capture(second.document))
		assert(observed.random.state == control.random.state and observed.lfsr_random.state == control.lfsr_random.state and observed.game_random.state == control.game_random.state)
	assert(power and water)
	print("Prepared supply after regular development: homes=", facts.values.homes, " power=", facts.values.target_powered, " water=", facts.values.target_watered)
	assert(facts.values.target_powered > 0, "Prepared settlement has no actual power")
	assert(facts.values.target_watered > 0, "Prepared settlement has no actual water")
	assert(facts.values.homes > 0 and first.population() > 0, "Practice must permit normal development")
	# The light observer uses precisely the original transport/power boundary rules.
	for point in [Vector2i(45, 48), Vector2i(45, 47), Vector2i(39, 47), Vector2i(0, 0), Vector2i(1, 1), Vector2i(127, 127)]:
		var local := TutorialFacts.site_access(first, point)
		var native: Dictionary = NativeSimulationBridge.run("growth_inputs", first, null, null, null, {"point": point}).result
		if native.rci:
			assert(local.powered == native.powered)
			if first.building_id(point.x, point.y) < BuildingTileIds.DEVELOPED_FIRST:
				assert(local.transport == native.transport)
