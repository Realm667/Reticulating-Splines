class_name ForestGrowth
extends RefCounted
## Optional saved forest growth. Uses only calendar/coordinates and the previous
## year's tile state, never the simulation's random generators.

@warning_ignore_start("integer_division")


static func due(city: CityState, previous_age: int, enabled: bool) -> bool:
	return enabled and city != null and previous_age >= 0 and city.age_in_days() / CityCalendar.DAYS_PER_YEAR > previous_age / CityCalendar.DAYS_PER_YEAR


static func advance(city: CityState, previous_age: int, enabled: bool) -> PackedInt32Array:
	var changed := PackedInt32Array()
	if not due(city, previous_age, enabled):
		return changed
	var first_year := previous_age / CityCalendar.DAYS_PER_YEAR + 1
	var last_year := city.age_in_days() / CityCalendar.DAYS_PER_YEAR
	for elapsed_year in range(first_year, last_year + 1):
		var before := city.buildings.duplicate()
		var after := before.duplicate()
		var year := city.founding_year() + elapsed_year
		for x in city.map_size:
			for y in city.map_size:
				var index := x * city.map_size + y
				var tile := int(before[index])
				if tile != 0 and (tile < BuildingTileIds.TREE_FIRST or tile >= BuildingTileIds.TREE_LAST):
					continue
				if (city.tile_flags[index] & Sc2TileFlags.WATER) != 0 or city.terrain[index] > TerrainTileIds.RAISED or (city.zones[index] & Sc2ZoneLayout.TYPE_MASK) != 0:
					continue
				if tile >= BuildingTileIds.TREE_FIRST and tile < BuildingTileIds.TREE_LAST:
					# One density step every four years, distributed across the map.
					if posmod(year + x + 3 * y, 4) == 0:
						after[index] = tile + 1
				elif tile == 0 and city.underground[index] == 0 and posmod(year + 3 * x + 5 * y, 8) == 0:
					# An established adjacent forest can colonize a free tile once
					# every eight years. New saplings cannot spread in the same pass.
					for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
						var neighbor := city.index_of(x + offset.x, y + offset.y)
						if neighbor >= 0 and before[neighbor] >= BuildingTileIds.TREES_3 and before[neighbor] <= BuildingTileIds.TREE_LAST:
							after[index] = BuildingTileIds.TREE_FIRST
							break
				if after[index] != tile:
					changed.append(index)
		if after != before:
			apply_buildings(city, after)
	return changed


static func apply_buildings(city: CityState, after: PackedByteArray) -> void:
	var counts := PackedInt64Array()
	counts.resize(256)
	for index in after.size():
		if city.buildings[index] != after[index]:
			counts[city.buildings[index]] -= 1
			counts[after[index]] += 1
	var mask := 0xffff if city.map_size == 128 else 0xffffffff
	for tile in counts.size():
		if counts[tile] != 0:
			var offset := Sc2MiscLayout.TILE_COUNTS + tile * 4
			city.document.set_misc_u32(offset, (city.document.misc_u32(offset) + counts[tile]) & mask)
	city.document.find_chunk("XBLD").set_decoded_payload(after)
	city.resync_mirrors(["XBLD"])
