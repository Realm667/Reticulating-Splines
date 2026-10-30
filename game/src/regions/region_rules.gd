class_name RegionRules
extends RefCounted
## Versioned rules shared by local regions and the authoritative multiplayer host.

@warning_ignore_start("integer_division")

const VERSION := 1
const SIZES := [2, 3, 4]
const DEFAULT_SIZE := 3
const ANNUAL_ADMINISTRATION := 1200
const DIRECTIONS := [Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1)]


static func contains(edge: int, position: Vector2i) -> bool:
	return edge in SIZES and position.x >= 0 and position.y >= 0 and position.x < edge and position.y < edge


static func key(position: Vector2i) -> String:
	return "%d,%d" % [position.x, position.y]


static func cell(value: String) -> Vector2i:
	var parts := value.split(",")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return Vector2i(-1, -1)
	return Vector2i(int(parts[0]), int(parts[1]))


static func start_positions(edge: int, players: int, seed_value: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if edge not in SIZES or players < 1 or players > edge:
		return result
	var random := RandomNumberGenerator.new()
	random.seed = seed_value
	if players == 1:
		result.append(Vector2i(random.randi_range(0, edge - 1), random.randi_range(0, edge - 1)))
		return result
	var best := {"minimum": -1, "sum": -1, "sets": []}
	_find_starts(edge, players, 0, [], best)
	var selected: Array = best.sets[random.randi_range(0, best.sets.size() - 1)].duplicate()
	while not selected.is_empty():
		result.append(selected.pop_at(random.randi_range(0, selected.size() - 1)))
	return result


static func _find_starts(edge: int, count: int, first: int, chosen: Array, best: Dictionary) -> void:
	if chosen.size() == count:
		var minimum := 2147483647
		var total := 0
		for i in chosen.size():
			for j in range(i + 1, chosen.size()):
				var difference: Vector2i = chosen[i] - chosen[j]
				var distance := difference.length_squared()
				minimum = mini(minimum, distance)
				total += distance
		if minimum > int(best.minimum) or (minimum == int(best.minimum) and total > int(best.sum)):
			best.minimum = minimum
			best.sum = total
			best.sets = [chosen.duplicate()]
		elif minimum == int(best.minimum) and total == int(best.sum):
			best.sets.append(chosen.duplicate())
		return
	for index in range(first, edge * edge - (count - chosen.size()) + 1):
		chosen.append(Vector2i(index / edge, index % edge))
		_find_starts(edge, count, index + 1, chosen, best)
		chosen.pop_back()


static func purchase_price(flat: int, slope: int, water: int) -> int:
	var tiles := flat + slope + water
	if tiles <= 0 or mini(flat, mini(slope, water)) < 0:
		return -1
	# Flat: 100%, slopes: 55%, water: 25%. $12,000 for a flat 128 map.
	return maxi(1, (12000 * (flat * 100 + slope * 55 + water * 25)) / (16384 * 100))


static func purchase_check(funds: int, debt: int, commitments: int, price: int, additional_after: int) -> Dictionary:
	if mini(debt, mini(commitments, mini(price, additional_after))) < 0:
		return {"ok": false, "available": 0, "required": 0, "shortfall": 0}
	var available := funds - debt - commitments
	var required := price + additional_after * ANNUAL_ADMINISTRATION
	return {"ok": available >= required, "available": available, "required": required,
		"shortfall": maxi(0, required - available)}


static func administration_due(acquired_day: int, settled_day: int, current_day: int, days_per_year: int) -> int:
	if days_per_year <= 0 or current_day <= settled_day or current_day <= acquired_day:
		return 0
	# Cumulative totals prevent rounding gains from splitting periods or loading.
	var previous := maxi(acquired_day, settled_day) - acquired_day
	var elapsed := current_day - acquired_day
	return elapsed * ANNUAL_ADMINISTRATION / days_per_year - previous * ANNUAL_ADMINISTRATION / days_per_year
