class_name RegionWorld
extends SharedWorld
## Separate complete maps and municipal simulations, with host-validated visits.

var region_versions: Dictionary = {}
var expansion_enabled := false
var region_edge := 3
var region_seed := 1
var campaign: RegionCampaign
var city_worlds: Dictionary = {}
var foreign_documents: Dictionary = {}

func sync_campaign() -> void:
	if campaign == null:
		return
	for actor: String in actors:
		campaign.documents[campaign.active_cells[actor]] = municipalities[actor].city.document

func player_limit() -> int:
	return region_edge if expansion_enabled else CoopSession.MAX_PLAYERS

func prepare_campaign(positions: Array[Vector2i]) -> String:
	if campaign != null:
		return ""
	if not expansion_enabled or positions.size() != actors.size() or actors.size() > player_limit():
		return "Invalid region configuration."
	var next := RegionCampaign.new()
	var first: Sc2File = municipalities[actors[0]].city.document
	var error := next.initialize_at(first.duplicate_document(true), region_edge, region_seed, actors[0], positions[0])
	if not error.is_empty():
		return error
	next.multiplayer = true
	var worlds := {}
	for index in actors.size():
		var actor := actors[index]
		var id := RegionRules.key(positions[index])
		var source: Sc2File = municipalities[actor].city.document
		var document := next.documents[id] if index == 0 else source.duplicate_document(true)
		if index > 0:
			var offer := next.offer(positions[index])
			if not offer.ok:
				return offer.error
			# All contestants receive the same starting funds and difficulty as their
			# lobby city, but a geographically consistent independent landscape.
			for chunk_id: String in ["ALTM", "XTER", "XBIT", "XBLD"]:
				document.find_chunk(chunk_id).set_decoded_payload(offer.document.find_chunk(chunk_id).decoded_payload.duplicate())
			for field: int in [Sc2MiscLayout.WATER_LEVEL, Sc2MiscLayout.HAS_OCEAN, Sc2MiscLayout.HAS_RIVER]:
				document.set_misc_u32(field, offer.document.misc_u32(field))
			for tile in 256:
				var field := Sc2MiscLayout.TILE_COUNTS + tile * 4
				document.set_misc_u32(field, offer.document.misc_u32(field))
			document.sc2x_metadata.phase_state.clear()
			next.offers.erase(id)
		RegionCampaign.clear_neighbors(document)
		var child := CoopWorld.new()
		if not child.open(document):
			return child.error
		RegionCampaign.clear_neighbors(child.city.document)
		RegionBoundary.stamp(child.city.document)
		next.documents[id] = child.city.document
		next.owners[id] = actor
		next.first_cells[actor] = id
		next.active_cells[actor] = id
		next.acquired[id] = next.current_day
		next.settled[id] = next.current_day
		worlds[id] = child
	campaign = next
	campaign.synchronize_neighbors()
	city_worlds = worlds
	for actor: String in actors:
		municipalities[actor] = city_worlds[campaign.active_cells[actor]]
	refresh_host()
	revision += 1
	return ""

func refresh_host() -> void:
	city = municipalities[host_actor].city
	engine = municipalities[host_actor].engine
	controller = municipalities[host_actor].controller

func campaign_summary(actor: String) -> Dictionary:
	if campaign == null:
		return {}
	sync_campaign()
	var cells: Array = []
	for x in campaign.edge:
		for y in campaign.edge:
			var position := Vector2i(x, y)
			var id := RegionRules.key(position)
			var owner: String = campaign.owners.get(id, "")
			if owner.is_empty():
				continue
			var entry := {"cell": [x, y], "owner": owner.sha256_text() if not owner.is_empty() else "", "own": owner == actor,
				"seat_active": campaign.active_cells.get(owner, "") == id,
				"available": owner.is_empty() and campaign.adjacent(actor, position)}
			if campaign.documents.has(id):
				entry["name"] = campaign.documents[id].city_name()
				entry["population"] = CityState.from_document(campaign.documents[id]).population()
			cells.append(entry)
	var active := RegionRules.cell(campaign.active_cells[actor])
	return {"expansion": true, "edge": campaign.edge, "active": [active.x, active.y], "cells": cells,
		"funds": campaign.own_funds(actor), "debt": campaign.own_debt(actor), "revision": campaign.revision,
		"administration": maxi(0, campaign.own_count(actor) - 1) * RegionRules.ANNUAL_ADMINISTRATION}

func population_for(actor: String) -> int:
	var total := 0
	for id: String in campaign.documents:
		if campaign.owners[id] == actor:
			total += CityState.from_document(campaign.documents[id]).population()
	return total

func region_command(actor: String, request: Dictionary, player_debt: int) -> Dictionary:
	if campaign == null or not municipalities.has(actor):
		return rejected("Regional expansion is not enabled for this game.")
	sync_campaign()
	var value: Variant = request.get("cell")
	if not value is Array or value.size() != 2 or not whole_number(value[0], 0, campaign.edge - 1) or not whole_number(value[1], 0, campaign.edge - 1):
		return rejected("Invalid region coordinates.")
	var position := Vector2i(int(value[0]), int(value[1]))
	var id := RegionRules.key(position)
	match request.get("kind"):
		"region_snapshot":
			if campaign.owners.get(id, "") != actor or not campaign.documents.has(id):
				return rejected("This city area does not belong to you.")
			var document := RegionCampaign.clean_copy(campaign.documents[id])
			var encoded := Sc2xDocument.encode(document)
			if not encoded.ok:
				return rejected(encoded.error)
			var result := accepted("")
			result["region_snapshot"] = {"cell": value, "document": Marshalls.raw_to_base64(encoded.data)}
			return result
		"region_offer":
			if campaign.owners.has(id):
				if campaign.owners[id] != actor:
					return rejected("This city area does not belong to you.")
				var document := campaign.documents[id]
				var model := CityState.from_document(document)
				var budget := BudgetReport.capture(model, BudgetPhase.funding_values(model))
				var administration := RegionCampaign.administration_report(document)
				var result := accepted("")
				# Full previews and private budgets travel only in this explicit
				# owner-authorized reply, never in shared/per-frame summaries.
				result["region_city"] = {"cell": value, "name": document.city_name(), "population": model.population(), "own": true,
					"preview": Marshalls.raw_to_base64(ApplicationRegions.terrain_preview(document).save_png_to_buffer()),
					"budget": {"projected_cash": budget.estimated_cash - int(administration.estimated)}}
				return result
			if not campaign.adjacent(actor, position):
				return rejected("Choose an available city area next to your own territory.")
			var offer := campaign.offer(position)
			if not offer.ok:
				return rejected(offer.error)
			var result := accepted("")
			result["region_offer"] = {"cell": value, "price": offer.price, "flat": offer.flat, "slope": offer.slope,
				"water": offer.water, "quote_revision": campaign.revision}
			result.region_offer["preview"] = Marshalls.raw_to_base64(ApplicationRegions.terrain_preview(offer.document).save_png_to_buffer())
			return result
		"region_buy":
			var checkpoint_error := Sc2xCheckpoint.save_error(municipalities[actor].controller)
			if not checkpoint_error.is_empty():
				return rejected(checkpoint_error)
			if not whole_number(request.get("quote_revision"), campaign.revision, campaign.revision):
				return rejected("This region changed. Review the offer before buying.")
			var purchased := campaign.purchase(actor, position, campaign.current_day, player_debt)
			if not purchased.ok:
				return rejected(purchased.error)
			municipalities[actor].revision += 1
			municipalities[actor].undo_document = null
			revision += 1
			return accepted("City area purchased.")
		"region_switch":
			if campaign.owners.get(id) != actor:
				return rejected("This city area does not belong to you.")
			var funds := campaign.own_funds(actor)
			if funds < -2147483648 or funds > 2147483647:
				return rejected("The regional treasury exceeds the supported balance.")
			var previous: CoopWorld = municipalities[actor]
			if previous.city.age_in_days() != campaign.current_day:
				return rejected("Wait until the region's cities reach the same day before switching.")
			var error := Sc2xCheckpoint.save_error(previous.controller)
			if not error.is_empty():
				return rejected(error)
			Sc2xCheckpoint.capture(previous.controller, previous.city.document.sc2x_metadata)
			if not city_worlds.has(id):
				var child := CoopWorld.new()
				if not child.open(campaign.documents[id]):
					return rejected(child.error)
				RegionCampaign.clear_neighbors(child.city.document)
				city_worlds[id] = child
			var next: CoopWorld = city_worlds[id]
			var previous_document := campaign.documents[id]
			campaign.documents[id] = next.city.document
			if not campaign.collect_funds(actor, next.city.document):
				campaign.documents[id] = previous_document
				return rejected("The regional treasury exceeds the supported balance.")
			next.city.set_age_in_days(campaign.current_day)
			next.controller.set_speed(previous.controller.speed)
			campaign.active_cells[actor] = id
			municipalities[actor] = next
			campaign.synchronize_neighbors()
			next.engine.clock.city_days = campaign.current_day
			next.engine.random.state = next.city.document.sc2x_metadata.process_random
			previous.undo_document = null
			next.undo_document = null
			next.revision += 1
			revision += 1
			region_versions[actor].fill(revision)
			refresh_host()
			return accepted("City view changed.")
	return rejected("Invalid region command.")

func add_player(actor: String) -> String:
	if expansion_enabled and (campaign != null or actors.size() >= player_limit()):
		return "No new player seats are available in this region."
	var error := super.add_player(actor)
	if error.is_empty():
		var versions := PackedInt64Array()
		versions.resize(city.map_size * city.map_size)
		region_versions[actor] = versions
		land_allowance[actor] = 0
	return error

func command(actor: String, request: Dictionary) -> Dictionary:
	if not municipalities.has(actor) or not whole_number(request.get("revision"), 0, revision):
		return rejected("Invalid region command.")
	if campaign != null and request.has("view_cell"):
		var active := RegionRules.cell(campaign.active_cells[actor])
		var viewed_cell: Variant = request.view_cell
		if not viewed_cell is Array or viewed_cell.size() != 2 or not whole_number(viewed_cell[0], active.x, active.x) or not whole_number(viewed_cell[1], active.y, active.y):
			return rejected("Your city view changed. Review the target before acting.")
	var viewing := actor
	for candidate: String in actors:
		if candidate.sha256_text() == request.get("view_owner"):
			viewing = candidate
	if viewing != actor:
		return rejected("This city view is read-only. Return to your own city to make changes.")
	if request.get("kind") == "recall":
		return super.command(actor, request)
	if request.get("kind") == "build" and request.get("group") == CityToolIds.Group.DISPATCH:
		if not point_valid(request.get("finish")) or not whole_number(request.get("tool"), 0, 2):
			return rejected("Invalid emergency service target.")
		return deploy_help(actor, municipalities[viewing], request)
	if str(request.get("kind", "")).begins_with("land_"):
		return rejected("Region cities own their entire map. Land trading is available in Shared mode.")
	var child: CoopWorld = municipalities[actor]
	sync_campaign()
	if campaign != null:
		var funds := child.city.funds()
		if not campaign.collect_funds(actor, child.city.document):
			return rejected("The regional treasury exceeds the supported balance.")
		if funds != child.city.funds():
			child.undo_document = null
	if request.get("kind") == "upgrade" and int(request.revision) != revision:
		return rejected("The city view is out of date. Wait for synchronization.")
	if request.get("kind") in ["build", "sign", "upgrade"]:
		if not point_valid(request.get("start")) or not point_valid(request.get("finish")):
			return rejected("Invalid map position.")
		var versions: PackedInt64Array = region_versions[actor]
		for tile: int in selected_tiles(request):
			if versions[tile] > int(request.revision):
				return rejected("This area changed. Review it before building.")
	var before := child.city.document.duplicate_document(true)
	var local := request.duplicate(true)
	local.revision = child.revision
	var result := child.command(actor, local)
	if result.get("ok", false):
		sync_campaign()
		revision += 1
		mark_changed(actor, before)
		statistics[actor] = child.statistics.get(actor, {})
		city = municipalities[host_actor].city
		engine = municipalities[host_actor].engine
		controller = municipalities[host_actor].controller
	return result

func advance(delta: float) -> void:
	# Cities continue independently; absent owners never acquire an AI mayor.
	# A city waiting for a budget/decision remains blocked by its normal rules.
	var barrier := -1
	if campaign != null:
		barrier = minimum_day() + 1
	for actor: String in actors:
		var child: CoopWorld = municipalities[actor]
		if child.controller.speed == GameSpeedController.Speed.PAUSED:
			continue
		if barrier >= 0 and child.city.age_in_days() >= barrier and child.engine.active_disaster_type == 0 and child.engine.pending_day_schedule == null:
			continue
		var previous := child.revision
		var previous_policy := child.policy_revision
		var previous_error := child.error
		var before := child.city.document.duplicate_document(true)
		child.tree_growth_enabled = tree_growth_enabled
		var old_target := child.controller.pause_at_day
		var old_speed := child.controller.speed
		if barrier >= 0:
			child.day_barrier = barrier
			child.controller.pause_at_day = mini(old_target, barrier) if old_target >= 0 else barrier
		child.advance(delta)
		if barrier >= 0:
			child.day_barrier = -1
			# Only undo our own temporary stop. A genuine simulation error or an
			# earlier debug/victory target keeps its original stopping semantics.
			if child.error.is_empty() and child.controller.speed == GameSpeedController.Speed.PAUSED and child.city.age_in_days() >= barrier and (old_target < 0 or barrier < old_target):
				child.controller.set_speed(old_speed)
			child.controller.pause_at_day = old_target
		if child.revision != previous or child.policy_revision != previous_policy or child.error != previous_error:
			revision += 1
			mark_changed(actor, before)
	city = municipalities[host_actor].city
	engine = municipalities[host_actor].engine
	controller = municipalities[host_actor].controller
	if campaign != null:
		sync_campaign()
		var day := minimum_day()
		if day > campaign.current_day:
			campaign.advance(day)
			for actor: String in actors:
				campaign.collect_funds(actor, municipalities[actor].city.document)
				municipalities[actor].revision += 1
			revision += 1

func minimum_day() -> int:
	var day := 2147483647
	for actor: String in actors:
		var child: CoopWorld = municipalities[actor]
		# Native advances the displayed date before asking for the annual budget.
		# That day's schedule is not committed until its interaction is resolved.
		var completed := child.city.age_in_days() - int(child.engine.pending_day_schedule != null)
		day = mini(day, completed)
	return day

func mark_changed(actor: String, before: Sc2File) -> void:
	var versions: PackedInt64Array = region_versions[actor]
	for tile: int in changed_tiles(before, municipalities[actor].city.document):
		versions[tile] = revision
	region_versions[actor] = versions

func snapshot_for(actor: String, live := false) -> Dictionary:
	return snapshot_region(actor, actor, live)

func snapshot_region(actor: String, viewed: String, live := false) -> Dictionary:
	if not municipalities.has(viewed):
		viewed = actor
	var child: CoopWorld = municipalities[viewed]
	var own: CoopWorld = municipalities[actor]
	var result := child.snapshot(false, live)
	if viewed != actor:
		var public_document := RegionCampaign.clean_copy(child.city.document)
		public_document.sc2x_extra_entries.erase(RegionCampaign.ADMIN_ENTRY)
		if live:
			if not foreign_documents.has(viewed):
				foreign_documents[viewed] = MultiplayerDocument.new()
			result = child.snapshot_status().merged(foreign_documents[viewed].capture(public_document))
		else:
			var encoded := Sc2xDocument.encode(public_document)
			if not encoded.ok:
				return {"error": encoded.error}
			result = child.snapshot_status().merged({"city": Marshalls.raw_to_base64(encoded.data)})
	result.revision = revision
	result["mode"] = "region"
	result["view_owner"] = viewed.sha256_text()
	result["visiting"] = viewed != actor
	if campaign != null:
		result["region_campaign"] = campaign_summary(actor)
	var availability := DispatchCommand.availability(own.city)
	result["assistance_available"] = [availability.police, availability.fire, availability.military] if availability.ok else [0, 0, 0]
	result["dispatch_owners"] = child.dispatch_owners.duplicate(true)
	result["disasters"] = []
	result["disaster"] = own.engine.active_disaster_type
	if viewed != actor:
		result.erase("newspaper_sequence")
		result.erase("newspaper_paper")
		result["pending"] = ""
		result["blocked"] = false
		result["terminal"] = false
	for owner: String in actors:
		var municipality: CoopWorld = municipalities[owner]
		if municipality.engine.active_disaster_type != 0:
			var location := Vector2i(city.map_size / 2, city.map_size / 2)
			for tile in municipality.city.buildings.size():
				if OverlayData.marker_at(municipality.city.text_overlays, tile) != 0:
					location = Vector2i(tile / city.map_size, tile % city.map_size)
					break
			result.disasters.append({"owner": owner.sha256_text(), "type": municipality.engine.active_disaster_type,
				"city": municipality.city.city_name(), "point": [location.x, location.y]})
	return result

func saved_shared() -> Dictionary:
	sync_campaign()
	var result := super.saved_shared()
	if result.has("error"):
		return result
	result["mode"] = "region"
	result["expansion_enabled"] = expansion_enabled
	result["region_edge"] = region_edge
	result["region_seed"] = str(region_seed)
	if campaign != null:
		for child: CoopWorld in city_worlds.values():
			if child not in municipalities.values():
				child.engine.clock.city_days = child.city.age_in_days()
				child.engine.random.state = child.city.document.sc2x_metadata.process_random
			var error := Sc2xCheckpoint.save_error(child.controller)
			if not error.is_empty():
				return {"error": error}
			Sc2xCheckpoint.capture(child.controller, child.city.document.sc2x_metadata)
		var original_entries := city.document.sc2x_extra_entries.duplicate()
		var error := campaign.pack(city.document)
		if not error.is_empty():
			return {"error": error}
		var encoded := Sc2xDocument.encode(city.document)
		city.document.sc2x_extra_entries.assign(original_entries)
		if not encoded.ok:
			return {"error": encoded.error}
		result["region_archive"] = Marshalls.raw_to_base64(encoded.data)
		var services := {}
		for id: String in city_worlds:
			var child: CoopWorld = city_worlds[id]
			services[id] = {"statistics": child.statistics, "dispatch": Array(child.dispatch_cycles),
				"dispatch_owners": child.dispatch_owners, "dispatch_initialized": child.dispatch_initialized,
				"dispatch_points": child.saved_dispatch_points()}
		result["region_services"] = services
	return result

func restore_shared(data: Dictionary) -> String:
	var error := super.restore_shared(data)
	if error.is_empty():
		if not data.get("expansion_enabled", false) is bool or int(data.get("region_edge", 3)) not in RegionRules.SIZES:
			return "Invalid region configuration."
		expansion_enabled = data.get("expansion_enabled", false)
		region_edge = int(data.get("region_edge", 3))
		region_seed = int(data.get("region_seed", "1"))
		if expansion_enabled and actors.size() > player_limit():
			return "Invalid region player data."
		if data.has("region_archive"):
			if not expansion_enabled or not data.region_archive is String or data.region_archive.length() > RegionCampaign.MAX_TOTAL_BYTES * 2:
				return "Invalid region city data."
			var document := Sc2File.new()
			if not document.parse(Marshalls.base64_to_raw(data.region_archive)):
				return "Invalid region city data."
			var restored := RegionCampaign.new()
			error = restored.restore(document)
			if not error.is_empty():
				return error
			if not restored.multiplayer or restored.edge != region_edge or restored.active_cells.size() != actors.size():
				return "Invalid region player data."
			for actor: String in actors:
				if not restored.active_cells.has(actor):
					return "Invalid region player data."
				var id: String = restored.active_cells[actor]
				if municipalities[actor].city.age_in_days() != restored.documents[id].misc_u32(Sc2MiscLayout.CITY_DAYS):
					return "Invalid region city data."
				restored.documents[id] = municipalities[actor].city.document
				city_worlds[id] = municipalities[actor]
			for owner: String in restored.owners.values():
				if owner not in actors:
					return "Invalid region player data."
			campaign = restored
			if not data.get("region_services", {}) is Dictionary:
				return "Invalid municipality service state."
			for id: Variant in data.get("region_services", {}):
				var service: Variant = data.region_services[id]
				if not id is String or not campaign.documents.has(id) or not service is Dictionary or not service.get("statistics") is Dictionary or not service.get("dispatch_owners") is Dictionary or not service.get("dispatch") is Array or service.dispatch.size() != 3:
					return "Invalid municipality service state."
				for cycle: Variant in service.dispatch:
					if not whole_number(cycle, 0, 2147483647):
						return "Invalid municipality dispatch cycle."
				var dispatch := CoopWorld.read_dispatch_points(service.get("dispatch_points", []), city.map_size)
				if not dispatch.error.is_empty():
					return dispatch.error
				if id not in city_worlds:
					var child := CoopWorld.new()
					if not child.open(campaign.documents[id]):
						return child.error
					RegionCampaign.clear_neighbors(child.city.document)
					city_worlds[id] = child
					campaign.documents[id] = child.city.document
				var child: CoopWorld = city_worlds[id]
				child.statistics = service.statistics
				child.dispatch_owners = service.dispatch_owners
				child.dispatch_cycles = PackedInt32Array(service.dispatch)
				child.dispatch_slot_points = dispatch.points
				child.dispatch_initialized = service.get("dispatch_initialized") == true
			campaign.synchronize_neighbors()
		for actor: String in actors:
			var versions := PackedInt64Array()
			versions.resize(city.map_size * city.map_size)
			versions.fill(revision)
			region_versions[actor] = versions
	return error
