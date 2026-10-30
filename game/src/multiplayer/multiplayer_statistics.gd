class_name MultiplayerStatistics
extends RefCounted
## Read-only snapshots; displayed values never change the simulation.

static func capture(world: CoopWorld, actor: String) -> Dictionary:
	var own: CoopWorld = world.municipalities[actor] if world is SharedWorld else world
	var city := own.city
	if world is RegionWorld and world.campaign != null:
		var combined := capture(own, actor)
		for id: String in world.campaign.documents:
			if world.campaign.owners[id] != actor or id == world.campaign.active_cells[actor]:
				continue
			var other: CoopWorld = world.city_worlds.get(id)
			if other == null:
				other = CoopWorld.new()
				other.city = CityState.from_document(world.campaign.documents[id])
			var row := capture(other, actor)
			for field: String in ["population", "funds", "balance", "debt", "land", "built", "residential", "commercial", "industrial", "builds", "spent", "units"]:
				combined[field] += row[field]
		return combined
	var result := {"city": city.city_name(), "population": city.population(), "funds": city.funds(),
		"balance": BudgetReport.capture(city, BudgetPhase.funding_values(city)).ytd_cash,
		"debt": city.document.misc_u32(Sc2MiscLayout.BONDS) * BondCommand.BOND_VALUE,
		"builds": own.statistics.get(actor, {}).get("builds", 0),
		"spent": own.statistics.get(actor, {}).get("spent", 0),
		"land": 0, "built": 0, "residential": 0, "commercial": 0, "industrial": 0,
		"bought": null, "sold": null, "units": 0, "aid": 0}
	var owners: PackedInt32Array = world.owners if world is SharedWorld and not world is RegionWorld else PackedInt32Array()
	var owner: int = world.actors.find(actor) + 1 if not owners.is_empty() else 0
	var cached: Dictionary = own.statistics_tiles.get(owner, {})
	var counts: Dictionary
	if cached.get("buildings") == city.buildings and cached.get("zones") == city.zones and cached.get("owners") == owners:
		counts = cached.counts
	elif cached.has("counts") and cached.buildings.size() == city.buildings.size() and cached.zones.size() == city.zones.size() and cached.owners.size() == owners.size():
		# Packed slices compare in native code. A single building must not force
		# a GDScript scan of every tile in every recipient's statistics table.
		counts = cached.counts.duplicate()
		for begin in range(0, city.buildings.size(), 512):
			var end := mini(begin + 512, city.buildings.size())
			if cached.buildings.slice(begin, end) == city.buildings.slice(begin, end) and cached.zones.slice(begin, end) == city.zones.slice(begin, end) and (owners.is_empty() or cached.owners.slice(begin, end) == owners.slice(begin, end)):
				continue
			for tile in range(begin, end):
				var before: bool = owners.is_empty() or cached.owners[tile] == owner
				var after: bool = owners.is_empty() or owners[tile] == owner
				if before == after and cached.buildings[tile] == city.buildings[tile] and cached.zones[tile] == city.zones[tile]:
					continue
				if before:
					adjust(counts, cached.buildings[tile], cached.zones[tile], -1)
				if after:
					adjust(counts, city.buildings[tile], city.zones[tile], 1)
	else:
		counts = {"land": 0, "built": 0, "residential": 0, "commercial": 0, "industrial": 0}
		for tile in city.buildings.size():
			if world is SharedWorld and not world is RegionWorld and owners[tile] != owner:
				continue
			counts.land += 1
			if city.buildings[tile] > 13:
				counts.built += 1
			var zone := int(city.zones[tile]) & 15
			if zone in [1, 2]:
				counts.residential += 1
			elif zone in [3, 4]:
				counts.commercial += 1
			elif zone in [5, 6]:
				counts.industrial += 1
	if counts != cached.get("counts") or cached.get("buildings") != city.buildings or cached.get("zones") != city.zones or cached.get("owners") != owners:
		own.statistics_tiles[owner] = {"buildings": city.buildings.duplicate(), "zones": city.zones.duplicate(), "owners": owners.duplicate(), "counts": counts}
	result.merge(counts, true)
	if world is SharedWorld:
		result.bought = world.land_statistics.get(actor, {}).get("bought")
		result.sold = world.land_statistics.get(actor, {}).get("sold")
		for municipality: String in world.municipalities:
			for unit: Dictionary in world.municipalities[municipality].dispatch_owners.values():
				if unit.get("actor") == actor.sha256_text():
					result.units += 1
					if municipality != actor:
						result.aid += 1
	else:
		for unit: Dictionary in world.dispatch_owners.values():
			if unit.get("actor") == actor.sha256_text():
				result.units += 1
	return result


static func adjust(counts: Dictionary, building: int, zone: int, amount: int) -> void:
	counts.land += amount
	if building > 13:
		counts.built += amount
	match zone & 15:
		1, 2:
			counts.residential += amount
		3, 4:
			counts.commercial += amount
		5, 6:
			counts.industrial += amount
