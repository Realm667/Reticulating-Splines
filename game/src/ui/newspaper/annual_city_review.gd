class_name AnnualCityReview
extends RefCounted
## Read-only observer of completed years. The archive contains presentation data only.

@warning_ignore_start("integer_division")

const ENTRY := "annual-review.json"
const VERSION := 1
const DAYS := CityCalendar.DAYS_PER_YEAR
const MAX_EVENTS := 12
const DISPLAY_EVENTS := 3
const FACILITIES := [
	BuildingTileIds.HOSPITAL, BuildingTileIds.POLICE_STATION, BuildingTileIds.FIRE_STATION,
	BuildingTileIds.SCHOOL, BuildingTileIds.COLLEGE, BuildingTileIds.WATER_TREATMENT,
	BuildingTileIds.DESALINIZATION, BuildingTileIds.COAL_POWER, BuildingTileIds.NUCLEAR_POWER,
	BuildingTileIds.SOLAR_POWER, BuildingTileIds.MICROWAVE_POWER, BuildingTileIds.FUSION_POWER,
	BuildingTileIds.PLYMOUTH_ARCOLOGY, BuildingTileIds.FOREST_ARCOLOGY, BuildingTileIds.DARCO_ARCOLOGY,
	BuildingTileIds.LAUNCH_ARCOLOGY,
]

var city: CityState
var year := -1
var population_start := -1
var events: Array[Dictionary] = []
var latest: Dictionary = {}
var _previous_day := -1
var _previous_population := -1
var _budget_year := -1
var _budget_total := 0
var _unpublished := false


func attach(value: CityState) -> void:
	city = value
	year = -1
	population_start = -1
	events.clear()
	latest = {}
	_previous_day = -1
	_previous_population = -1
	_budget_year = -1
	_unpublished = false
	if city == null:
		return
	year = city.current_year()
	if city.age_in_days() % DAYS == 0:
		population_start = city.population()
	var raw: PackedByteArray = city.document.sc2x_extra_entries.get(ENTRY, PackedByteArray())
	if raw.is_empty() or raw.size() > 8192:
		return
	var data: Variant = JSON.parse_string(raw.get_string_from_utf8())
	if not data is Dictionary or data.get("version") != VERSION:
		return
	if data.get("year") == year:
		population_start = _population(data.get("start"))
		events = _valid_events(data.get("events"), year)
	var archive: Variant = data.get("latest")
	if archive is Dictionary and archive.get("year") == year - 1:
		latest = {"year": year - 1, "start": _population(archive.get("start")),
			"end": _population(archive.get("end")), "events": _valid_events(archive.get("events"), year - 1).slice(0, DISPLAY_EVENTS)}
		var budget: Variant = archive.get("budget")
		if _whole_number(budget) and absf(float(budget)) <= 4294967295.0:
			latest.budget = int(budget)


func prepare() -> void:
	_previous_day = city.age_in_days()
	_previous_population = city.population()
	var document := city.document
	if document.misc_u32(Sc2MiscLayout.YEAR_END) == 0 or city.current_month() not in [1, 12]:
		return
	var closing_year := city.current_year() - int(city.current_month() == 1)
	if _budget_year == closing_year:
		return
	var report := BudgetReport.capture(city, BudgetPhase.funding_values(city), false)
	if report.year_to_date.size() != Sc2BudgetLayout.COUNT:
		return
	_budget_total = 0
	for amount in report.year_to_date:
		_budget_total += amount
	_budget_year = closing_year


func observe(tick: SimulationTickResult) -> bool:
	var published := false
	for day in tick.day_results:
		if not day.ok:
			continue
		var day_year := city.founding_year() + day.day / DAYS
		if day_year > year:
			var closing_population := _previous_population if _previous_day == day.day - 1 else -1
			latest = {"year": day_year - 1, "start": population_start if day_year == year + 1 else -1,
				"end": closing_population, "events": _headline_events() if day_year == year + 1 else []}
			year = day_year
			population_start = closing_population
			events.clear()
			_unpublished = true

		var budget := day.phase_results.get("budget") as BudgetPhase.Result
		if budget != null and budget.settled_year:
			if latest.get("year") != day_year - 1:
				latest = {"year": day_year - 1, "start": -1, "end": -1, "events": []}
			if _budget_year == day_year - 1:
				latest.budget = _budget_total
			_unpublished = true

		if _unpublished and (day.complete or (budget != null and budget.settled_year)):
			_unpublished = false
			_store()
			published = true

		var disaster := day.phase_results.get("disaster_start") as DisasterStartResult
		if disaster != null:
			record_disaster(disaster, day.day)
	# Preserve the first year's population even if the player saves before any event.
	if not tick.day_results.is_empty() and population_start >= 0 and not city.document.sc2x_extra_entries.has(ENTRY):
		_store()
	return published


func record_disaster(result: DisasterStartResult, day: int) -> void:
	if not result.ok or not result.started or result.disaster_type <= 0:
		return
	var point := DisasterFocus.find_point(city)
	if not _valid_point(point) and not result.damage_points.is_empty():
		point = result.damage_points[0]
	_record("disaster", result.disaster_type, point, day)


func record_building(result: BuildingEditResult) -> void:
	if result.tile_id in FACILITIES and not result.free_mode and result.site.has_area():
		_record("building", result.tile_id, result.site.position, city.age_in_days())


func undo_building(result: BuildingEditResult) -> void:
	for index in range(events.size() - 1, -1, -1):
		var item := events[index]
		if (item.kind == "building" and item.id == result.tile_id and item.day == city.age_in_days()
				and point_in_current_view(item) == result.site.position):
			events.remove_at(index)
			_store()
			return


func point_in_current_view(item: Dictionary) -> Vector2i:
	var point := Vector2i(item.x, item.y)
	if not _valid_point(point):
		return Vector2i(-1, -1)
	for turn in posmod(city.compass_rotation() - int(item.rotation), 4):
		point = CityRotationCommand.rotate_point(point, city.map_size, true)
	return point


func edition() -> Dictionary:
	if latest.get("year") == city.current_year() - 1:
		return latest
	return {"year": city.current_year() - 1, "start": -1, "end": -1, "events": []}


func _record(kind: String, id: int, point: Vector2i, day: int) -> void:
	if city.founding_year() + day / DAYS != year:
		return
	if not _valid_point(point):
		point = Vector2i(-1, -1)
	var item := {"kind": kind, "id": id, "day": day, "month": day % DAYS / CityCalendar.DAYS_PER_MONTH,
		"x": point.x, "y": point.y, "rotation": city.compass_rotation()}
	if item in events:
		return
	if events.size() == MAX_EVENTS:
		var oldest_building := -1
		for index in events.size():
			if events[index].kind == "building":
				oldest_building = index
				break
		if oldest_building < 0 and kind == "building":
			return
		events.remove_at(maxi(0, oldest_building))
	events.append(item)
	_store()


func _headline_events() -> Array[Dictionary]:
	var selected: Array[Dictionary] = []
	for kind in ["disaster", "building"]:
		for item in events:
			if selected.size() < DISPLAY_EVENTS and item.kind == kind:
				selected.append(item)
	selected.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return left.day < right.day)
	return selected


func _store() -> void:
	if city.document.is_sc2x():
		city.document.sc2x_extra_entries[ENTRY] = JSON.stringify({"version": VERSION, "year": year,
			"start": population_start, "events": events, "latest": latest}).to_utf8_buffer()


func _valid_events(value: Variant, event_year: int) -> Array[Dictionary]:
	var valid: Array[Dictionary] = []
	if not value is Array:
		return valid
	for item in value.slice(0, MAX_EVENTS):
		if not item is Dictionary or item.get("kind") not in ["building", "disaster"]:
			continue
		var id: Variant = item.get("id")
		var day: Variant = item.get("day")
		if not _whole_number(id) or not _whole_number(day):
			continue
		if day < 0 or day > city.age_in_days() or city.founding_year() + int(day) / DAYS != event_year:
			continue
		if (item.kind == "building" and int(id) not in FACILITIES) or (item.kind == "disaster" and (id < 1 or id > 32)):
			continue
		var point := Vector2i(-1, -1)
		var x: Variant = item.get("x")
		var y: Variant = item.get("y")
		var rotation: Variant = item.get("rotation")
		if (_whole_number(x) and _whole_number(y) and _whole_number(rotation)
				and x >= 0 and y >= 0 and x < city.map_size and y < city.map_size and rotation >= 0 and rotation < 4):
			point = Vector2i(int(x), int(y))
		valid.append({"kind": item.kind, "id": int(id), "day": int(day), "month": int(day) % DAYS / CityCalendar.DAYS_PER_MONTH,
			"x": point.x, "y": point.y, "rotation": int(rotation) if point.x >= 0 else 0})
	return valid


func _valid_point(point: Vector2i) -> bool:
	return city.index_of(point.x, point.y) >= 0


static func _whole_number(value: Variant) -> bool:
	return value is int or (value is float and is_finite(value) and floorf(value) == value)


static func _population(value: Variant) -> int:
	return int(value) if _whole_number(value) and value >= 0 and value <= 0xffffffff else -1
