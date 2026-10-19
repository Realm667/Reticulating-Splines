class_name TutorialRules
extends RefCounted
## No rule calls simulation code or advances a random generator.


static func complete(rule: String, facts: Dictionary, events: Dictionary, context: Dictionary) -> bool:
	if rule.begins_with("quiz:"):
		return events.get(rule, false)
	match rule:
		"camera":
			return events.get("pan", false) and events.get("zoom", false)
		"rotation":
			return events.get("rotated", false) and context.get("rotation_returned", false)
		"speed":
			return events.get("pause", false) and events.get("turtle", false)
		"query":
			return events.get("query", false)
		"site":
			return events.get("site", false)
		"power", "pump", "road":
			return facts.get(rule, 0) > 0
		"rail":
			return facts.get("connected_rail", 0) >= 2
		"piped":
			return facts.get("target_piped", 0) > 0
		"park":
			return facts.get("park", 0) > 0 and events.get("query_park", false)
		"zones":
			return facts.get("residential", 0) > 0 and facts.get("jobs", 0) > 0
		"powered", "watered":
			return context.get(rule + "_fresh", false) and facts.get("target_" + rule, 0) > 0
		"population":
			return facts.get("homes", 0) > 0 and context.get("population", 0) > 0
		"underground":
			return events.get("view:underground", false) and events.get("view:city", false)
		"expand":
			return events.get("demand_zone", false) and context.get("extension_ready", false) and context.get("powered_fresh", false)
		"budget":
			return events.get("budget", false) and events.get("quiz:forecast", false)
		"period":
			return events.get("budget", false) and context.get("budget_period", false)
		"repair_power":
			return context.get("practice", false) and events.get("power_failure", false) and context.get("powered_fresh", false) and facts.get("target_powered", 0) > 0 and facts.get("unpowered_homes", 0) == 0
		"repair_water":
			return context.get("practice", false) and events.get("water_failure", false) and context.get("watered_fresh", false) and facts.get("target_watered", 0) > 0 and facts.get("dry_homes", 0) == 0
		"diagnose":
			return events.get("data", false) and events.get("query", false)
		"save":
			return events.get("save", false)
		"advisor", "finish", "settings", "photo":
			return events.get(rule, false)
		"traffic":
			return events.get("view:traffic", false) and events.get("trip", false)
		"coverage":
			return events.get("view:police_power", false) and events.get("view:fire_power", false)
		"service":
			return context.get("service_funded", false) and events.get("budget", false) and events.get("query_service", false)
		"environment":
			return events.get("view:pollution", false) and events.get("view:land_value", false)
		"disaster_start":
			return context.get("practice", false) and events.get("disaster", false)
		"dispatch":
			return context.get("practice", false) and events.get("pause", false) and events.get("dispatch", false)
		"late":
			return context.get("practice", false) and context.get("year", 0) >= 2050
		"late_tools":
			return events.get("ports", false) and events.get("rewards", false)
	return false


static func advisor(facts: Dictionary, context: Dictionary, mode: int) -> Array[String]:
	var result: Array[String] = []
	if mode == 0 or not context.get("available", false):
		return result
	if context.get("disaster", 0) > 0:
		result.append("disaster")
	if context.get("powered_fresh", false) and facts.get("unpowered_homes", 0) > 0:
		result.append("power")
	if context.get("watered_fresh", false) and facts.get("dry_homes", 0) > 0:
		result.append("water")
	if context.get("forecast", 0) < 0:
		result.append("budget")
	if mode == 2 and facts.get("empty_zone", 0) > 0:
		result.append("growth")
	return result
