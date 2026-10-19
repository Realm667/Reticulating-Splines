extends SceneTree

const DocumentState = preload("res://tests/support/document_state.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var rules := KnowledgeRules.new()
	var phase := WaterPhase.Result.new()
	phase.ok = true
	phase.consumers = 20
	phase.watered_consumers = 10
	var day := SimulationDayResult.new()
	day.ok = true
	day.phase_results["water"] = phase
	var tick := SimulationTickResult.new()
	tick.ok = true
	tick.day_results.append(day)
	rules.observe(tick)
	assert(rules.take().is_empty(), "One unserved scan is not a stable shortage")
	phase.complete = false
	rules.observe(tick)
	assert(rules.take().is_empty(), "Partial phases must not produce advice")
	phase.complete = true
	rules.observe(tick)
	assert(rules.take() == "water")
	rules.observe(tick)
	assert(rules.take().is_empty(), "Cooldown must suppress repeated notices")
	phase.watered_consumers = 20
	rules.observe(tick)
	assert(not rules.candidates.has("water") and not rules.streaks.has("water"))
	rules.reset()
	rules.condition("power", true, 90, 1)
	rules.condition("vacant", true, 40, 1)
	assert(rules.take() == "power")
	rules.reset()
	rules.condition("water", true, 80, 1)
	rules.advance(KnowledgeRules.LIFETIME + 1)
	assert(rules.take().is_empty(), "Expired candidates must be dropped")
	rules.reset()
	rules.muted.append("water")
	rules.condition("water", true, 80, 1)
	assert(rules.take().is_empty())
	rules.condition("age", true, 85, 1)
	tick.notice_ids.append(42)
	rules.observe(tick)
	assert(not rules.candidates.has("age"), "Existing event notices take precedence")
	_test_contexts()
	for edge in [128, 512]:
		var city := CityState.from_document(EmptyCityTemplate.create(edge))
		var point := Vector2i(edge - 2, edge - 2)
		city.set_zone_id(point.x, point.y, 2)
		var before: Array = DocumentState.capture(city.document)
		var inputs := KnowledgeRules.growth(city, point)
		assert(inputs.rci and not inputs.powered)
		assert(KnowledgeRules.growth_rows(inputs).size() == 5)
		assert(KnowledgeRules.growth(city, Vector2i(-1, 0)).is_empty())
		assert(DocumentState.capture(city.document) == before, "Advice must not mutate the city")
	var card := KnowledgeCard.new()
	root.add_child(card)
	card.position = Vector2(100, 100)
	card.size = Vector2(390, 0)
	card.show_entry("water")
	card.more.pressed.emit()
	assert(card.details.visible)
	card.show_entry("start")
	assert(not card.details.visible and card.controls.visible)
	card.pin.set_pressed_no_signal(true)
	card._process(30)
	assert(card.summary.visible)
	card.pin.set_pressed_no_signal(false)
	card._process(30)
	assert(not card.summary.visible)
	card.queue_free()
	await process_frame
	print("PASS knowledge: stable phases, repair, expiry, priority, cooldown, muting, no mutation, card controls")
	quit()


func _test_contexts() -> void:
	var rules := KnowledgeRules.new()
	var day := SimulationDayResult.new()
	day.ok = true
	var tick := SimulationTickResult.new()
	tick.ok = true
	tick.day_results.append(day)
	var power := PowerPhase.Result.new()
	power.ok = true
	power.consumers = 2
	power.supplied_consumers = 1
	day.phase_results = {"power": power}
	rules.observe(tick)
	rules.observe(tick)
	assert(rules.take() == "power")
	power.supplied_consumers = 2
	rules.observe(tick)
	assert(not rules.streaks.has("power"))
	rules.reset()
	var growth := GrowthResult.new()
	growth.ok = true
	growth.rci_tiles = 2
	day.phase_results = {"growth": growth}
	for index in 4:
		rules.observe(tick)
	assert(rules.take().is_empty(), "Partial RCI scan must not diagnose stagnation")
	growth.rci_complete = true
	for index in 3:
		rules.observe(tick)
	assert(rules.take() == "vacant")
	growth.started_construction = 1
	rules.observe(tick)
	assert(not rules.streaks.has("vacant"))
	rules.reset()
	var budget := BudgetPhase.Result.new()
	budget.ok = true
	budget.funds_before = 20000
	budget.funds_after = 10000
	day.phase_results = {"budget": budget}
	rules.observe(tick, 500)
	rules.observe(tick, 500)
	assert(rules.take().is_empty(), "Spending cash does not prove a forecast deficit")
	rules.observe(tick, -500)
	rules.observe(tick, -500)
	assert(rules.take() == "budget")
	rules.observe(tick, 0)
	assert(not rules.streaks.has("budget"))
	rules.reset()
	var invention := RciAftermathPhase.Result.new()
	invention.ok = true
	day.phase_results = {"invention": invention}
	rules.observe(tick)
	assert(rules.take().is_empty())
	invention.invention_index = 0
	rules.observe(tick)
	assert(rules.take() == "unlock")
	rules.reset()
	var milestone := MilestonePhase.Result.new()
	milestone.ok = true
	milestone.reward_id = 1
	day.phase_results = {"milestone": milestone}
	rules.observe(tick)
	assert(rules.take() == "unlock")
	rules.reset()
	var annual := MicrosimAnnualPhase.Result.new()
	annual.ok = true
	day.phase_results = {"annual": annual}
	rules.observe(tick)
	assert(rules.take().is_empty())
	annual.expired_power_records.append(PowerPlantExpiry.new(0, 0, Vector2i.ZERO))
	rules.observe(tick)
	assert(rules.take() == "age")
	annual.expired_power_records.clear()
	rules.observe(tick)
	assert(not rules.streaks.has("age"))
	rules.reset()
	var disaster := DisasterStartResult.new()
	disaster.ok = true
	day.phase_results = {"disaster": disaster}
	rules.observe(tick)
	assert(rules.take().is_empty())
	disaster.started = true
	rules.observe(tick)
	assert(rules.take() == "recovery")
	rules.reset()
	var scenario := ScenarioPhase.Result.new()
	scenario.ok = true
	scenario.active = true
	scenario.unmet.append("population")
	scenario.remaining_months = 100
	day.phase_results = {"scenario": scenario}
	rules.observe(tick)
	assert(rules.take().is_empty(), "No recurring deadline warning years before the deadline")
	scenario.remaining_months = 6
	rules.observe(tick)
	assert(rules.take() == "recovery")
	rules.reset()
	rules.record("power")
	rules.advance(181)
	rules.record("water")
	rules.advance(360)
	rules.condition("power", true, 90, 1)
	assert(rules.take() == "power", "Each topic has its own repeat cooldown")
