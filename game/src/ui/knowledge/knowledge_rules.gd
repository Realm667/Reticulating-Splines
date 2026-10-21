class_name KnowledgeRules
extends RefCounted
## Read-only selection from complete, published results. No RNG or map scans.

const COOLDOWN := 180.0
const LIFETIME := 180.0
var elapsed := 0.0
var last_shown := -COOLDOWN
var candidates: Dictionary = {}
var streaks: Dictionary = {}
var history: Array[String] = []
var shown_at: Dictionary = {}
var muted := PackedStringArray()


func reset() -> void:
	elapsed = 0.0
	last_shown = -COOLDOWN
	candidates.clear()
	streaks.clear()
	history.clear()
	shown_at.clear()


func advance(delta: float) -> void:
	elapsed += maxf(delta, 0.0)
	for id: String in candidates.keys():
		if elapsed - float(candidates[id].time) > LIFETIME:
			candidates.erase(id)


func condition(id: String, present: bool, priority: int, stable := 2) -> void:
	if not present:
		streaks.erase(id)
		candidates.erase(id)
		return
	streaks[id] = int(streaks.get(id, 0)) + 1
	if int(streaks[id]) >= stable and not muted.has(id):
		candidates[id] = {"priority": priority, "time": elapsed}


func observe(result: SimulationTickResult, budget_forecast: Variant = null) -> void:
	if not result.ok:
		return
	for day in result.day_results:
		if not day.ok:
			continue
		for phase: PhaseResult in day.phase_results.values():
			if not phase.ok or not phase.complete:
				continue
			if phase is PowerPhase.Result:
				condition("power", phase.consumers > phase.supplied_consumers, 90)
			elif phase is WaterPhase.Result:
				condition("water", phase.consumers > phase.watered_consumers, 80)
			elif phase is GrowthResult and phase.rci_complete:
				condition("vacant", phase.rci_tiles > 0 and phase.started_construction == 0
					and phase.completed_construction == 0 and phase.population_added == 0, 40, 3)
			elif phase is BudgetPhase.Result:
				if budget_forecast != null:
					condition("budget", int(budget_forecast) < 0, 60)
			elif phase is MicrosimAnnualPhase.Result:
				condition("age", not phase.expired_power_records.is_empty(), 85, 1)
			elif phase is RciAftermathPhase.Result:
				if phase.invention_index >= 0:
					condition("unlock", true, 35, 1)
			elif phase is MilestonePhase.Result:
				if phase.reward_id >= 0 or phase.military_proposal_pending:
					condition("unlock", true, 35, 1)
			elif phase is DisasterStartResult:
				condition("recovery", phase.started, 100, 1)
			elif phase is ScenarioPhase.Result:
				if phase.active and not phase.unmet.is_empty() and phase.remaining_months <= 12:
					condition("scenario", true, 50, 1)
	# Existing modal reports take precedence; do not duplicate their event.
	if not result.notice_ids.is_empty() or result.newspaper_requested or not result.game_over_events.is_empty():
		for id in ["age", "unlock", "recovery"]:
			candidates.erase(id)


func take() -> String:
	if elapsed - last_shown < COOLDOWN:
		return ""
	var chosen := ""
	var priority := -1
	for id: String in candidates:
		if muted.has(id) or elapsed - float(shown_at.get(id, -COOLDOWN * 3.0)) < COOLDOWN * 3.0:
			continue
		if id == "vacant" and (candidates.has("power") or candidates.has("water")):
			continue
		if int(candidates[id].priority) > priority:
			chosen = id
			priority = int(candidates[id].priority)
	if not chosen.is_empty():
		candidates.erase(chosen)
		record(chosen)
	return chosen


func record(id: String) -> void:
	last_shown = elapsed
	shown_at[id] = elapsed
	history.erase(id)
	history.push_front(id)
	if history.size() > 24:
		history.resize(24)


static func growth(city: CityState, point: Vector2i) -> Dictionary:
	if city == null or city.index_of(point.x, point.y) < 0:
		return {}
	return NativeSimulationBridge.run("growth_inputs", city, null, null, null, {"point": point}).result


static func growth_rows(inputs: Dictionary) -> Array:
	if not bool(inputs.get("rci", false)):
		return []
	var needed := int(inputs.needed_land_value)
	return [
		["Power supply", "Available" if inputs.powered else "Missing"],
		["Transport access", ("Available" if inputs.transport else "Missing") if int(inputs.building) < BuildingTileIds.DEVELOPED_FIRST else "Not checked"],
		["Demand", "Positive" if int(inputs.class_demand) > 0 else "Not positive"],
		["Land value", ("Sufficient" if int(inputs.land_value) > needed else "Too low") if needed >= 0 else "No density threshold"],
		["Destination reachability", "Not checked"],
	]


static func growth_title(inputs: Dictionary) -> String:
	if int(inputs.get("building", 0)) < BuildingTileIds.DEVELOPED_FIRST:
		return "Why is this zone not developing?"
	if int(inputs.get("status", 0)) == 2:
		return "Why is this building abandoned?"
	return "What needs attention here?"
