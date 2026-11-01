class_name RegionOverviewModel
extends RefCounted
## Presentation adapters only; authority and save geography stay in RegionWorld.

@warning_ignore_start("integer_division")


static func multiplayer(state: Dictionary, own_id: String) -> Dictionary:
	var result: Dictionary = state.get("region_campaign", {}).duplicate(true)
	var expanded := not result.is_empty()
	if not expanded:
		result = {"edge": MultiplayerStarts.GRID, "cells": [], "active": [-1, -1], "occupied_only": true}
	var viewed: String = state.get("view_owner", own_id)
	var fallback_slot := 0
	for player: Dictionary in state.get("roster", []):
		if not expanded:
			var slot := clampi(int(state.get("starts", {}).get(player.id, {}).get("slot", fallback_slot)), 0, MultiplayerStarts.GRID * MultiplayerStarts.GRID - 1)
			fallback_slot += 1
			result.cells.append({"cell": [slot / MultiplayerStarts.GRID, slot % MultiplayerStarts.GRID], "owner": player.id, "region": slot + 1,
				"own": player.id == own_id, "name": player.city, "population": player.get("population", 0), "seat_active": true})
		for entry: Dictionary in result.cells:
			if entry.get("owner") != player.id:
				continue
			entry["color"] = player.get("color", "46b4ff")
			entry["player"] = player.name
			entry["status"] = player.get("seat_status", "reserved")
			if entry.get("seat_active", false) and player.id == viewed:
				result.active = entry.cell
	result["competitive"] = true
	result["expansion"] = expanded
	return result


static func neighbors(city: CityState) -> Dictionary:
	var data := SimNationWindowControl.snapshot(city)
	if not data.ok:
		return {}
	var cells := [{"cell": [1, 1], "name": data.city_name, "population": data.display_population, "own": true}]
	for neighbor: SimNationWindowControl.Neighbor in data.neighbors:
		var position: Vector2i = Vector2i.ONE + RegionRules.DIRECTIONS[(neighbor.index + 2) & 3]
		cells.append({"cell": [position.x, position.y], "name": CityNeighbors.city_name(city, neighbor.index),
			"population": neighbor.population, "own": false})
	return {"edge": 3, "active": [1, 1], "cells": cells, "occupied_only": true}


static func can_visit(item: Dictionary) -> bool:
	return not item.get("owner", "").is_empty() and item.get("seat_active", false)
