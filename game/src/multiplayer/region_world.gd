class_name RegionWorld
extends SharedWorld
## Separate complete maps and municipal simulations, with host-validated visits.

var region_versions: Dictionary = {}

func add_player(actor: String) -> String:
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
	if request.get("kind") in ["build", "sign"]:
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
	for actor: String in actors:
		var child: CoopWorld = municipalities[actor]
		if child.controller.speed == GameSpeedController.Speed.PAUSED:
			continue
		var previous := child.revision
		var before := child.city.document.duplicate_document(true)
		child.tree_growth_enabled = tree_growth_enabled
		child.advance(delta)
		if child.revision != previous:
			revision += 1
			mark_changed(actor, before)
	city = municipalities[host_actor].city
	engine = municipalities[host_actor].engine
	controller = municipalities[host_actor].controller

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
	result.revision = revision
	result["mode"] = "region"
	result["view_owner"] = viewed.sha256_text()
	result["visiting"] = viewed != actor
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
	var result := super.saved_shared()
	result["mode"] = "region"
	return result

func restore_shared(data: Dictionary) -> String:
	var error := super.restore_shared(data)
	if error.is_empty():
		for actor: String in actors:
			var versions := PackedInt64Array()
			versions.resize(city.map_size * city.map_size)
			versions.fill(revision)
			region_versions[actor] = versions
	return error
