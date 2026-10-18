class_name ClassicCheatActions
extends RefCounted
## Explicit desktop cheat effects. Normal simulation and bond rules are unchanged.

@warning_ignore_start("integer_division")


static func allowed(document: Sc2File, session: CoopSession, mirrored := false) -> bool:
	return (document != null and not document.sc2x_extra_entries.has("multiplayer.json") and not mirrored
		and (session == null or not (session.active or session.hosting or session.connected or session.waiting_for_start)))


static func issue_expensive_bond(city: CityState) -> bool:
	var data := BondCommand._misc_data(city)
	if not data.ok:
		return false
	var count := BinaryData.read_u32_be(data.misc, Sc2MiscLayout.BONDS)
	if count >= BondCommand.MAX_BONDS or city.funds() > CityDebugActions.MAX_FUNDS - BondCommand.BOND_VALUE:
		return false
	var misc := data.misc.duplicate()
	var interest := 25
	for index in count:
		interest += BinaryData.read_u32_be(misc, Sc2MiscLayout.BOND_RATES + index * 4) & 0xffff
	BinaryData.write_u32_be(misc, Sc2MiscLayout.BOND_RATES + count * 4, 25)
	count += 1
	BinaryData.write_u32_be(misc, Sc2MiscLayout.BONDS, count)
	BinaryData.write_u32_be(misc, Sc2MiscLayout.FUNDS, city.funds() + BondCommand.BOND_VALUE)
	var budget := Sc2MiscLayout.BUDGETS + Sc2BudgetLayout.BONDS * Sc2BudgetLayout.RECORD_SIZE
	BinaryData.write_u32_be(misc, budget + Sc2BudgetLayout.CURRENT, count)
	BinaryData.write_u32_be(misc, budget + Sc2BudgetLayout.FUNDING, interest * 10000 / count)
	return data.chunk.set_decoded_payload(misc, true)


static func churches(city: CityState) -> int:
	if city == null or not city.is_valid():
		return 0
	var buildings := city.buildings.duplicate()
	var zones := city.zones.duplicate()
	var flags := city.tile_flags.duplicate()
	var misc := city.document.find_chunk("MISC").decoded_payload.duplicate()
	var edge := city.map_size
	var rotation := city.compass_rotation() & 3
	var count := 0
	for x in range(edge - 1):
		for y in range(edge - 1):
			if (zones[x * edge + y] & Sc2ZoneLayout.TYPE_MASK) not in [1, 2]:
				continue
			var indices := [x * edge + y, (x + 1) * edge + y, (x + 1) * edge + y + 1, x * edge + y + 1]
			var eligible := true
			for index: int in indices:
				var tile: int = buildings[index]
				var small := tile == BuildingTileIds.EMPTY or tile in range(BuildingTileIds.TREES_1, BuildingTileIds.TREES_7 + 1)
				small = small or tile in range(BuildingTileIds.DEVELOPED_FIRST, BuildingTileIds.RESIDENTIAL_1X1_LAST + 1)
				if (not small or (zones[index] & Sc2ZoneLayout.TYPE_MASK) not in [1, 2]
					or flags[index] & Sc2TileFlags.WATER or city.terrain[index] != 0 or city.text_overlays[index] != 0
					or city.altitude_words[index] != city.altitude_words[indices[0]]):
					eligible = false
					break
			if not eligible:
				continue
			var corners := [Sc2ZoneLayout.CORNER_BOTTOM_LEFT[rotation], Sc2ZoneLayout.CORNER_BOTTOM_RIGHT[rotation],
				Sc2ZoneLayout.CORNER_TOP_LEFT[rotation], Sc2ZoneLayout.CORNER_TOP_RIGHT[rotation]]
			for offset in 4:
				var index: int = indices[offset]
				var old_count := Sc2MiscLayout.TILE_COUNTS + buildings[index] * 4
				BinaryData.write_u32_be(misc, old_count, maxi(0, BinaryData.read_u32_be(misc, old_count) - 1))
				buildings[index] = BuildingTileIds.CHURCH
				zones[index] = corners[offset]
				flags[index] = (flags[index] & ~Sc2TileFlags.FLIPPED) | Sc2TileFlags.STRUCTURE_MASK
			count += 1
	if count == 0:
		return 0
	var church_count := Sc2MiscLayout.TILE_COUNTS + BuildingTileIds.CHURCH * 4
	BinaryData.write_u32_be(misc, church_count, BinaryData.read_u32_be(misc, church_count) + count * 4)
	city.replace_buildings(buildings)
	city.replace_zones(zones)
	city.replace_tile_flags(flags)
	city.document.find_chunk("MISC").set_decoded_payload(misc, true)
	return count
