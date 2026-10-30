class_name MultiplayerStarts
extends RefCounted
## Equal dry-land grants in separated sectors. No money or simulation RNG is used.
@warning_ignore_start("integer_division")

const GRID := 4
var previous: Dictionary = {}
var positions: Dictionary = {}
var round_number := 1
var assigned := false
var handicaps: Dictionary = {}
var preview: Dictionary = {}
var parcel_cache: Dictionary = {}
var cache_key := ""

func prepare(world: SharedWorld, members: Dictionary, commit := true) -> String:
	if assigned:
		return ""
	if world is RegionWorld and world.expansion_enabled:
		return prepare_region(world, members, commit)
	var next_key := str(world.city.document.get_instance_id()) + ":" + str(hash(world.owners))
	if next_key != cache_key:
		cache_key = next_key
		parcel_cache.clear()
	var size := world.city.map_size
	var width := size / GRID
	var protected := PackedInt32Array()
	protected.resize(world.owners.size())
	var chosen := {}
	var used: Array[int] = []
	var amount := MultiplayerStartParcel.standard(size)
	var water_ratio := -1.0
	for offset in world.actors.size():
		var actor: String = world.actors[(offset + round_number - 1) % world.actors.size()]
		var handicap: Dictionary = handicaps.get(actor, {})
		var requested := int(handicap.get("tiles", 0))
		if requested == 0:
			requested = maxi(1, roundi(amount * int(handicap.get("scale", 100)) / 100.0))
		var best: Dictionary = {}
		var score := -INF
		for slot in GRID * GRID:
			if used.has(slot) or previous.get(actor, []).has(slot):
				continue
			var candidate := {"slot": slot, "tiles": [], "reserve": [], "land": 0, "water": 0, "center": Vector2i(slot / GRID * width + width / 2, slot % GRID * width + width / 2)} if world is RegionWorld else cached_parcel(world, slot, requested)
			if candidate.is_empty():
				continue
			var spacing := float(size * size)
			for other: Dictionary in chosen.values():
				spacing = minf(spacing, Vector2(candidate.center).distance_squared_to(other.center))
			var ratio := float(candidate.water) / maxi(1, candidate.tiles.size())
			var value := spacing - (absf(ratio - water_ratio) * size * size * 8 if water_ratio >= 0 else ratio * size * size)
			if value > score:
				best = candidate
				score = value
		if best.is_empty():
			return "Not enough connected land for these starts and reserved expansion areas. Adjust handicaps or generate new terrain."
		used.append(best.slot)
		chosen[actor] = best
		if water_ratio < 0:
			water_ratio = float(best.water) / maxi(1, best.tiles.size())
	preview.clear()
	for actor: String in chosen:
		var parcel: Dictionary = chosen[actor]
		preview[actor.sha256_text()] = {"land": parcel.land, "water": parcel.water, "tiles": parcel.tiles.size(), "reserved": parcel.reserve.size()}
	if not commit:
		return ""
	world.protection = protected if not world is RegionWorld else world.protection
	for actor: String in world.actors:
		var candidate: Dictionary = chosen[actor]
		var history: Array = previous.get(actor, []).duplicate()
		history.append(candidate.slot)
		previous[actor] = history
		var handicap: Dictionary = handicaps.get(actor, {})
		var grant: int = candidate.tiles.size()
		var point: Vector2i = candidate.center
		if not world is RegionWorld:
			var owner := world.actors.find(actor) + 1
			for tile: int in candidate.tiles:
				world.owners[tile] = owner
			for tile: int in candidate.reserve:
				world.protection[tile] = owner
		var municipality: CoopWorld = world.municipalities[actor]
		if handicap.has("funds"):
			municipality.city.set_funds(int(handicap.funds))
			municipality.revision += 1
		positions[actor] = {"slot": candidate.slot, "point": [point.x, point.y], "tiles": 0 if world is RegionWorld else grant, "land": candidate.land, "water": candidate.water, "reserved": candidate.reserve.size()}
		members[actor]["ranked"] = true
		world.land_allowance[actor] = 0
	world.revision += 1
	world.tile_versions.fill(world.revision)
	world.snapshot_cache.clear()
	assigned = true
	return ""

func prepare_region(world: RegionWorld, members: Dictionary, commit: bool) -> String:
	if world.actors.size() > world.player_limit():
		return "No new player seats are available in this region."
	var cells := RegionRules.start_positions(world.region_edge, world.actors.size(), world.region_seed)
	preview.clear()
	for index in world.actors.size():
		preview[world.actors[index].sha256_text()] = {"cell": [cells[index].x, cells[index].y], "land": 0, "water": 0, "tiles": 0, "reserved": 0}
	if not commit:
		return ""
	var error := world.prepare_campaign(cells)
	if not error.is_empty():
		return error
	for index in world.actors.size():
		var actor := world.actors[index]
		var child: CoopWorld = world.municipalities[actor]
		if handicaps.get(actor, {}).has("funds"):
			child.city.set_funds(int(handicaps[actor].funds))
			child.revision += 1
		var point := world.city.map_size / 2
		positions[actor] = {"slot": cells[index].x * GRID + cells[index].y, "point": [point, point], "tiles": 0,
			"land": 0, "water": 0, "reserved": 0, "cell": [cells[index].x, cells[index].y]}
		members[actor]["ranked"] = true
	assigned = true
	world.revision += 1
	return ""


func public_positions() -> Dictionary:
	var result := {}
	for actor: String in positions:
		result[actor.sha256_text()] = positions[actor].duplicate(true)
	return result

func saved() -> Dictionary:
	return {"handicaps": handicaps.duplicate(true), "round": round_number, "assigned": assigned, "previous": previous.duplicate(true), "positions": positions.duplicate(true)}

static func valid(data: Variant, members: Dictionary, size: int) -> bool:
	if not data is Dictionary or not CoopWorld.whole_number(data.get("round"), 1, 2147483647) or not data.get("assigned") is bool or not data.get("previous") is Dictionary or not data.get("positions") is Dictionary:
		return false
	if not data.get("handicaps", {}) is Dictionary:
		return false
	for actor: Variant in data.get("handicaps", {}):
		var handicap: Variant = data.handicaps[actor]
		if not members.has(actor) or not handicap is Dictionary or not CoopWorld.whole_number(handicap.get("funds"), 0, 2147483647) or not CoopWorld.whole_number(handicap.get("tiles", 0), 0, size * size / 16):
			return false
		if not CoopWorld.whole_number(handicap.get("scale", 100), 50, 150) or int(handicap.get("scale", 100)) not in [50, 75, 100, 125, 150]:
			return false
	for actor: Variant in data.previous:
		if not members.has(actor) or not data.previous[actor] is Array or data.previous[actor].size() > GRID * GRID:
			return false
		var seen := {}
		for slot: Variant in data.previous[actor]:
			if not CoopWorld.whole_number(slot, 0, GRID * GRID - 1) or seen.has(int(slot)):
				return false
			seen[int(slot)] = true
	for actor: Variant in data.positions:
		var item: Variant = data.positions[actor]
		if not members.has(actor) or not item is Dictionary or not CoopWorld.whole_number(item.get("slot"), 0, GRID * GRID - 1) or not CoopWorld.whole_number(item.get("tiles"), 0, size * size) or not item.get("point") is Array or item.point.size() != 2:
			return false
		for value: Variant in item.point:
			if not CoopWorld.whole_number(value, 0, size - 1):
				return false
	return true

func restore(data: Dictionary) -> void:
	handicaps = data.get("handicaps", {}).duplicate(true)
	round_number = int(data.round)
	assigned = data.assigned
	previous = data.previous.duplicate(true)
	for actor: String in previous:
		previous[actor] = previous[actor].map(func(slot: Variant) -> int: return int(slot))
	positions = data.positions.duplicate(true)

func repair_reserved_corridors(world: SharedWorld) -> void:
	if world is RegionWorld or not assigned:
		return
	# Reconstruct only recorded start parcels on their original terrain. Keep
	# purchased land, public seams and already-built shared roads untouched.
	var terrain := CityState.from_document(world.template)
	var original := PackedInt32Array()
	original.resize(world.owners.size())
	for tile in original.size():
		if terrain.buildings[tile] > 13 or terrain.zones[tile] != 0 or terrain.underground[tile] != 0:
			original[tile] = 1
	var changed := false
	for actor: String in positions:
		var start: Dictionary = positions[actor]
		if not start.has("land") or not start.has("water"):
			continue
		var parcel := MultiplayerStartParcel.legacy_make(terrain, original, int(start.slot), int(start.land) + int(start.water) / 2)
		if parcel.is_empty() or parcel.land != start.land or parcel.water != start.water or [parcel.center.x, parcel.center.y] != start.point:
			continue
		var owner := world.actors.find(actor) + 1
		for tile: int in parcel.reserve:
			if world.owners[tile] != 0 or (world.protection[tile] != -1 and not world.restored_empty_corridors.has(tile)):
				continue
			var built := false
			for city: CoopWorld in world.municipalities.values():
				built = built or city.city.buildings[tile] > 13 or city.city.zones[tile] != 0 or city.city.underground[tile] != 0
			if not built:
				world.protection[tile] = owner
				changed = true
	if changed:
		world.revision += 1
		world.tile_versions.fill(world.revision)
		world.snapshot_cache.clear()

func cached_parcel(world: SharedWorld, slot: int, amount: int) -> Dictionary:
	var key := str(slot) + ":" + str(amount)
	if not parcel_cache.has(key):
		parcel_cache[key] = MultiplayerStartParcel.make(world.city, world.owners, slot, amount)
	return parcel_cache[key]
