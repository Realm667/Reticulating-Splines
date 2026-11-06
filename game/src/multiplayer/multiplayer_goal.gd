class_name MultiplayerGoal
extends RefCounted
## Read-only victory evaluation; only the host controls the simulation speed.
@warning_ignore_start("integer_division")

var kind := "endless"
var target := 10000
var winners: Array = []
var unscored := false
var holding: Dictionary = {}
var hold_days := CityCalendar.DAYS_PER_YEAR * 10
var rule := "leadership"
var leader := ""
var tied := false
var duration_days := CityCalendar.DAYS_PER_YEAR * 10
var start_age := -1
var elapsed_days := 0
var end_year := 0
var final_scores: Dictionary = {}

func begin(world: CoopWorld) -> void:
	if kind == "timed_score" and start_age < 0:
		start_age = world.city.age_in_days()
		end_year = world.city.founding_year() + (start_age + duration_days) / CityCalendar.DAYS_PER_YEAR

func advance(world: CoopWorld, delta: float) -> void:
	if kind != "timed_score" or start_age < 0 or not winners.is_empty() or unscored or not world is SharedWorld:
		world.advance(delta)
		return
	var regional: bool = world is RegionWorld and world.campaign != null
	var current_day: int = world.campaign.current_day if regional else world.city.age_in_days()
	var remaining := maxi(0, start_age + duration_days - current_day)
	if remaining == 0:
		return
	# A long frame can run several days. Use the existing day boundary to take
	# the final snapshot exactly on the deadline, then restore the host's speed.
	var previous := {}
	for actor: String in world.actors:
		var child: CoopWorld = world.municipalities[actor]
		previous[actor] = [child.controller.pause_at_day, child.controller.speed]
		var deadline := start_age + duration_days if regional else child.city.age_in_days() + remaining
		child.controller.pause_at_day = mini(deadline, child.controller.pause_at_day) if child.controller.pause_at_day >= 0 else deadline
	world.advance(delta)
	for actor: String in world.actors:
		var child: CoopWorld = world.municipalities[actor]
		child.controller.pause_at_day = previous[actor][0]
		if child.controller.speed != int(previous[actor][1]) and int(previous[actor][0]) < 0:
			child.controller.set_speed(int(previous[actor][1]))

func reset_clock(world: CoopWorld) -> void:
	start_age = -1
	elapsed_days = 0
	final_scores.clear()
	leader = ""
	tied = false
	end_year = world.city.founding_year() + (world.city.age_in_days() + duration_days) / CityCalendar.DAYS_PER_YEAR

static func score_units(population: int, net_wealth: int) -> int:
	# Thousandths of a point: compare exact integers, never rounded UI values.
	return population * 10 + net_wealth

static func points(units: int) -> String:
	var fraction := "%03d" % (absi(units) % 1000)
	while fraction.ends_with("0"):
		fraction = fraction.left(-1)
	var separator := "," if TranslationServer.get_locale().begins_with("de") else "."
	return ("−" if units < 0 else "") + MultiplayerScoreboard.number(absi(units) / 1000) + (separator + fraction if not fraction.is_empty() else "")

static func score_help() -> String:
	return TranslationServer.translate("1 point per 100 residents + 1 point per $1,000 net wealth (funds minus debt). Highest score at the deadline wins; ties share victory. Late cities are unranked.")


static func standing(goal: Dictionary, players: Array, identity: String) -> String:
	var kind: String = goal.get("kind", "endless")
	if kind == "endless" or goal.get("unscored", false):
		return ""
	var ranked := players.filter(func(row: Dictionary) -> bool: return row.get("ranked", true))
	if ranked.is_empty():
		return ""
	var best: int = MultiplayerGoalHud.value(ranked[0], kind)
	for row: Dictionary in ranked:
		best = maxi(best, MultiplayerGoalHud.value(row, kind))
	var leaders := ranked.filter(func(row: Dictionary) -> bool: return MultiplayerGoalHud.value(row, kind) == best)
	var text: String = TranslationServer.translate("Tied lead") if leaders.size() > 1 else TranslationServer.translate("Leader: %s") % str(leaders[0].name)
	for row: Dictionary in ranked:
		if row.id == identity and MultiplayerGoalHud.value(row, kind) < best:
			text += " · " + TranslationServer.translate("Your gap: %s") % MultiplayerGoalHud.number(best - MultiplayerGoalHud.value(row, kind), kind)
	if not goal.get("winners", []).is_empty() or kind == "timed_score":
		return text
	if best < int(goal.get("target", 1)):
		return text + "\n" + TranslationServer.translate("Below target · no time earned")
	if goal.get("rule", "continuous") == "leadership":
		if leaders.size() > 1:
			return text + "\n" + TranslationServer.translate("Tied · leadership clock paused")
		var days := int(goal.get("holding", {}).get(leaders[0].id, {}).get("days", 0))
		return text + "\n" + TranslationServer.translate("Sole lead · %d days remaining") % maxi(0, int(goal.get("hold_days", 0)) - days)
	return text + "\n" + TranslationServer.translate("Target reached")


static func score_breakdown(row: Dictionary) -> String:
	var population := int(row.get("population", 0)) * 10
	var funds := int(row.get("funds", 0))
	var debt := int(row.get("debt", 0))
	return TranslationServer.translate("Points: residents %s + funds %s − debt %s = %s") % [points(population), points(funds), points(debt), points(score_units(int(row.get("population", 0)), funds - debt))] + "\n" + TranslationServer.translate("Starting funds count. Land purchases reduce funds; sales increase funds. Land itself adds no points.")


func blocked() -> bool:
	return not winners.is_empty() and not unscored

func evaluate(world: CoopWorld, members: Dictionary, loans: MultiplayerLoans = null) -> bool:
	if not world is SharedWorld or kind == "endless" or not winners.is_empty() or unscored:
		return false
	if kind == "timed_score":
		return evaluate_timed(world, members, loans)
	var best := -9223372036854775807
	var leaders: Array[String] = []
	for actor: String in world.actors:
		if not members[actor].get("ranked", true):
			continue
		var score := world_value(world, actor, loans)
		if score > best:
			best = score
			leaders = [actor.sha256_text()]
		elif score == best:
			leaders.append(actor.sha256_text())
	leader = leaders[0] if leaders.size() == 1 and best >= target else ""
	tied = leaders.size() > 1 and best >= target
	for actor: String in world.actors:
		if not members[actor].get("ranked", true):
			continue
		var city: CityState = world.municipalities[actor].city
		var day: int = world.campaign.current_day if world is RegionWorld and world.campaign != null else city.age_in_days()
		var value := world_value(world, actor, loans)
		var key := actor.sha256_text()
		if rule == "leadership":
			if not holding.has(key):
				holding[key] = {"since": day, "days": 0}
			var elapsed := maxi(0, day - int(holding[key].since))
			holding[key].since = day
			if key == leader:
				holding[key].days = mini(hold_days, int(holding[key].days) + elapsed)
		else:
			if value < target:
				holding.erase(key)
				continue
			if not holding.has(key):
				holding[key] = {"since": day, "days": 0}
			holding[key].days = maxi(0, day - int(holding[key].since))
		if int(holding[key].days) < hold_days:
			continue
		var tile: int = world.owners.find(world.actors.find(actor) + 1)
		var point := Vector2i(city.map_size / 2, city.map_size / 2)
		if tile >= 0:
			point = Vector2i(tile / city.map_size, tile % city.map_size)
		winners.append({"seat": actor.sha256_text(), "name": members[actor].name, "city": city.city_name(),
			"value": value, "point": [point.x, point.y], "color": members[actor].get("color", "46b4ff")})
	return not winners.is_empty()

func evaluate_timed(world: SharedWorld, members: Dictionary, loans: MultiplayerLoans) -> bool:
	if start_age < 0:
		return false
	var current_day: int = world.campaign.current_day if world is RegionWorld and world.campaign != null else world.city.age_in_days()
	elapsed_days = clampi(current_day - start_age, 0, duration_days)
	var best := -9223372036854775807
	var leaders: Array[String] = []
	var scores := {}
	for actor: String in world.actors:
		if not members[actor].get("ranked", true):
			continue
		var value := world_value(world, actor, loans)
		scores[actor.sha256_text()] = value
		if value > best:
			best = value
			leaders = [actor]
		elif value == best:
			leaders.append(actor)
	leader = leaders[0].sha256_text() if leaders.size() == 1 else ""
	tied = leaders.size() > 1
	if elapsed_days < duration_days or leaders.is_empty():
		return false
	final_scores = scores
	for actor: String in leaders:
		var city: CityState = world.municipalities[actor].city
		var tile: int = world.owners.find(world.actors.find(actor) + 1)
		var point := Vector2i(city.map_size / 2, city.map_size / 2) if tile < 0 else Vector2i(tile / city.map_size, tile % city.map_size)
		winners.append({"seat": actor.sha256_text(), "name": members[actor].name, "city": city.city_name(),
			"value": best, "point": [point.x, point.y], "color": members[actor].get("color", "46b4ff")})
	return true

func city_value(city: CityState, actor: String, loans: MultiplayerLoans) -> int:
	if kind == "population":
		return city.population()
	var wealth := city.funds() - city.document.misc_u32(Sc2MiscLayout.BONDS) * BondCommand.BOND_VALUE - (loans.debt(actor) if loans != null else 0)
	return score_units(city.population(), wealth) if kind == "timed_score" else wealth

func world_value(world: SharedWorld, actor: String, loans: MultiplayerLoans) -> int:
	if world is RegionWorld and world.campaign != null:
		var population: int = world.population_for(actor)
		if kind == "population":
			return population
		var wealth: int = world.campaign.own_funds(actor) - world.campaign.own_debt(actor) - (loans.debt(actor) if loans != null else 0)
		return score_units(population, wealth) if kind == "timed_score" else wealth
	return city_value(world.municipalities[actor].city, actor, loans)

func saved() -> Dictionary:
	return {"kind": kind, "target": target, "winners": winners.duplicate(true), "unscored": unscored,
		"duration_days": duration_days, "start_age": start_age, "elapsed_days": elapsed_days, "end_year": end_year, "final_scores": final_scores.duplicate(),
		"rule": rule, "leader": leader, "tied": tied, "hold_days": hold_days, "holding": holding.duplicate(true)}

static func valid(data: Variant, size: int) -> bool:
	if data == null:
		return true
	if not data is Dictionary or not data.get("kind") in ["endless", "population", "wealth", "timed_score"] or not CoopWorld.whole_number(data.get("target"), 1, 2147483647) or not data.get("winners") is Array or data.winners.size() > 8 or not data.get("unscored") is bool:
		return false
	if not CoopWorld.whole_number(data.get("hold_days", 0), 0, CityCalendar.DAYS_PER_YEAR * 10) or not data.get("holding", {}) is Dictionary or data.get("holding", {}).size() > 8:
		return false
	if data.get("rule", "continuous") not in ["continuous", "leadership"]:
		return false
	for key: Variant in data.get("holding", {}):
		var entry: Variant = data.holding[key]
		if not key is String or key.length() != 64 or not entry is Dictionary or not CoopWorld.whole_number(entry.get("since"), 0, 2147483647) or not CoopWorld.whole_number(entry.get("days"), 0, 2147483647):
			return false
	if data.kind == "timed_score":
		if not CoopWorld.whole_number(data.get("duration_days"), CityCalendar.DAYS_PER_YEAR, CityCalendar.DAYS_PER_YEAR * 100) or int(data.duration_days) % CityCalendar.DAYS_PER_YEAR != 0:
			return false
		if not CoopWorld.whole_number(data.get("start_age"), -1, 2147453647) or not CoopWorld.whole_number(data.get("elapsed_days"), 0, int(data.duration_days)) or not CoopWorld.whole_number(data.get("end_year"), 0, 2147483647):
			return false
		if not data.get("final_scores") is Dictionary or data.final_scores.size() > 8:
			return false
		for key: Variant in data.final_scores:
			if not key is String or key.length() != 64 or not CoopWorld.whole_number(data.final_scores[key], -9007199254740991, 9007199254740991):
				return false
		if not data.winners.is_empty() and (int(data.start_age) < 0 or int(data.elapsed_days) != int(data.duration_days) or data.final_scores.is_empty()):
			return false
	for winner: Variant in data.winners:
		if not winner is Dictionary or not winner.get("name") is String or not winner.get("city") is String or not winner.get("seat") is String or not winner.get("point") is Array or winner.point.size() != 2:
			return false
		for axis in winner.point:
			if not CoopWorld.whole_number(axis, 0, size - 1):
				return false
	return true

func restore(data: Variant) -> void:
	if data == null:
		return
	duration_days = int(data.get("duration_days", CityCalendar.DAYS_PER_YEAR * 10))
	start_age = int(data.get("start_age", -1))
	elapsed_days = int(data.get("elapsed_days", 0))
	end_year = int(data.get("end_year", 0))
	final_scores = data.get("final_scores", {}).duplicate()
	rule = data.get("rule", "continuous")
	leader = data.get("leader", "")
	tied = data.get("tied", false)
	kind = data.kind
	target = int(data.target)
	winners = data.winners.duplicate(true)
	unscored = data.unscored
	# Old saved matches retain the victory rule agreed when they were started.
	hold_days = int(data.get("hold_days", 0))
	holding = data.get("holding", {}).duplicate(true)
