extends SceneTree
## Region economy, archive validation and generation determinism.

var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: " + message)


func run() -> void:
	_test_starts()
	_test_economy()
	_test_scaffold()
	_test_archive()
	_test_archive_calendar()
	if "--rules-only" not in OS.get_cmdline_user_args():
		_test_offers()
		_test_purchase_terrain()
		_test_real_connections()
		_test_boundary_edits()
	print("region_campaign_test: %d failures" % failures)
	quit(0 if failures == 0 else 1)


func _test_starts() -> void:
	for edge in RegionRules.SIZES:
		check(RegionRules.start_positions(edge, edge + 1, 42).is_empty(), "grid enforces player limit")
		check(RegionRules.start_positions(edge, 0, 42).is_empty(), "zero players rejected")
		for players in range(1, edge + 1):
			var starts := RegionRules.start_positions(edge, players, 42)
			check(starts == RegionRules.start_positions(edge, players, 42), "starts deterministic")
			check(starts.size() == players, "all players receive start")
			for index in starts.size():
				check(RegionRules.contains(edge, starts[index]), "start inside grid")
				check(starts.count(starts[index]) == 1, "starts do not overlap")
			if players == 2:
				check((starts[0] - starts[1]).length_squared() == 2 * (edge - 1) * (edge - 1), "two players start at opposite corners")
		var solo_positions := {}
		for seed_value in 64:
			solo_positions[RegionRules.start_positions(edge, 1, seed_value)[0]] = true
		check(solo_positions.size() > edge, "solo origin varies across grid")
	check(RegionRules.start_positions(5, 2, 1).is_empty(), "invalid grid rejected")
	check(not RegionRules.contains(3, Vector2i(3, 0)), "cannot expand beyond grid")
	check(not RegionRules.contains(3, Vector2i(-1, 0)), "cannot expand before grid")
	check(RegionRules.cell("broken") == Vector2i(-1, -1), "malformed coordinate rejected")


func _test_economy() -> void:
	check(RegionRules.purchase_price(16384, 0, 0) == 12000, "flat reference price")
	check(RegionRules.purchase_price(0, 16384, 0) == 6600, "sloped land discount")
	check(RegionRules.purchase_price(0, 0, 16384) == 3000, "water discount")
	check(RegionRules.purchase_price(65536, 0, 0) == 48000, "price scales with area")
	check(RegionRules.purchase_price(0, 0, 0) == -1, "empty landscape rejected")
	check(RegionRules.purchase_price(-1, 2, 0) == -1, "negative terrain count rejected")
	var allowed := RegionRules.purchase_check(14200, 0, 1000, 12000, 1)
	check(allowed.ok and allowed.available == allowed.required, "exact reserve threshold allowed")
	check(not RegionRules.purchase_check(14199, 0, 1000, 12000, 1).ok, "reserve cannot be spent")
	check(not RegionRules.purchase_check(24200, 10001, 1000, 12000, 1).ok, "new borrowing cannot finance purchase")
	check(not RegionRules.purchase_check(14200, 0, 1000, 12000, 2).ok, "all additional areas require reserve")
	check(not RegionRules.purchase_check(50000, -1, 0, 12000, 1).ok, "invalid debt rejected")
	var year := CityCalendar.DAYS_PER_YEAR
	check(RegionRules.administration_due(50, 50, 50 + year, year) == 1200, "annual administration rate")
	var accumulated := 0
	for day in range(51, 51 + year):
		accumulated += RegionRules.administration_due(50, day - 1, day, year)
	check(accumulated == 1200, "daily prorating has no rounding exploitation")
	check(RegionRules.administration_due(50, 50 + year, 50 + year, year) == 0, "settled day not charged twice")
	check(RegionRules.administration_due(50, 50, 49, year) == 0, "backwards clock not charged")
	check(RegionRules.administration_due(50, 50, 60, 0) == 0, "invalid calendar rejected")


func _document(edge := 32) -> Sc2File:
	var result := Sc2xDocument.create_empty(edge, "Region test")
	check(result.ok, "create valid regional document")
	return result.document


func _test_scaffold() -> void:
	var source := _document()
	var altitudes := source.find_chunk("ALTM").decoded_payload.duplicate()
	var flags := source.find_chunk("XBIT").decoded_payload.duplicate()
	for x in 32:
		for y in 32:
			var index := x * 32 + y
			var land := (x / 8 + y / 8) as int
			var packed := land | (10 << 5)
			altitudes[index * 2] = packed >> 8
			altitudes[index * 2 + 1] = packed & 255
			flags[index] = Sc2TileFlags.WATER | Sc2TileFlags.SALT_WATER if x >= 24 else 0
	source.find_chunk("ALTM").set_decoded_payload(altitudes, true)
	source.find_chunk("XBIT").set_decoded_payload(flags, true)
	var origin := Vector2i(2, 1)
	for x in 4:
		for y in 4:
			var position := Vector2i(x, y)
			var boundary := RegionTerrain._boundaries(source, position, origin, {})
			for side in [2, 3]:
				var neighbor: Vector2i = position + RegionRules.DIRECTIONS[side]
				if not RegionRules.contains(4, neighbor):
					continue
				var other := RegionTerrain._boundaries(source, neighbor, origin, {})
				for along in 32:
					for field in 4:
						check(boundary[(side * 32 + along) * 5 + field] == other[((side - 2) * 32 + along) * 5 + field], "canonical borders agree regardless of future purchase order")
	check(source.find_chunk("ALTM").decoded_payload == altitudes, "boundary sampling preserves source terrain")


func _test_archive() -> void:
	var first := _document()
	first.set_misc_i32(Sc2MiscLayout.FUNDS, 20000)
	var campaign := RegionCampaign.new()
	check(campaign.initialize_at(first, 3, 42, "owner", Vector2i(1, 1)).is_empty(), "initialize explicit origin")
	check(campaign.adjacent("owner", Vector2i(2, 1)), "cardinal expansion allowed")
	check(not campaign.adjacent("owner", Vector2i(2, 2)), "diagonal expansion disallowed")
	check(campaign.pack(first).is_empty(), "archive packs")
	var restored := RegionCampaign.new()
	check(restored.restore(first.duplicate_document(true)).is_empty(), "archive restores")
	check(restored.origin == Vector2i(1, 1) and restored.own_funds("owner") == 20000, "archive retains origin and treasury")
	check(not restored.template.sc2x_extra_entries.has(RegionCampaign.ENTRY), "origin reference contains no recursive archive")
	var pristine := first.duplicate_document(true)
	var base: Dictionary = JSON.parse_string(first.sc2x_extra_entries[RegionCampaign.ENTRY].get_string_from_utf8())
	for mutation in ["version", "size", "owner", "missing_players", "day", "revision", "future_settled", "alias", "offer_duplicate", "active_mismatch"]:
		var damaged := pristine.duplicate_document(true)
		var data := base.duplicate(true)
		match mutation:
			"version": data.version = 999
			"size": data.edge = 5
			"owner": data.slots["1,1"].owner = ""
			"missing_players":
				data.first_cells = {}
				data.active_cells = {}
			"day": data.day = -1
			"revision": data.revision = -1
			"future_settled": data.slots["1,1"].settled = data.day + 1
			"alias":
				data.slots["01,1"] = data.slots["1,1"]
				data.slots.erase("1,1")
				data.active = "01,1"
				data.first_cells.owner = "01,1"
				data.active_cells.owner = "01,1"
			"offer_duplicate": data.offers = ["1,1"]
			"active_mismatch": data.active_cells.owner = "0,0"
		damaged.sc2x_extra_entries[RegionCampaign.ENTRY] = JSON.stringify(data).to_utf8_buffer()
		check(not restored.restore(damaged).is_empty(), "malformed archive rejected: " + mutation)
		check(restored.origin == Vector2i(1, 1) and restored.own_funds("owner") == 20000, "failed restore is atomic: " + mutation)
	var wrong_template := pristine.duplicate_document(true)
	wrong_template.sc2x_extra_entries[RegionCampaign.TEMPLATE_ENTRY] = Sc2xDocument.encode(_document(64)).data
	check(not restored.restore(wrong_template).is_empty(), "template size mismatch rejected")
	var missing_template := pristine.duplicate_document(true)
	missing_template.sc2x_extra_entries.erase(RegionCampaign.TEMPLATE_ENTRY)
	check(not restored.restore(missing_template).is_empty(), "missing template rejected")


func _test_archive_calendar() -> void:
	var first := _document()
	first.set_misc_u32(Sc2MiscLayout.CITY_DAYS, 50)
	first.set_misc_i32(Sc2MiscLayout.FUNDS, 20000)
	var campaign := RegionCampaign.new()
	check(campaign.initialize_at(first, 3, 42, "owner", Vector2i(1, 1)).is_empty(), "calendar archive initialized")
	var passive := _document()
	passive.set_misc_u32(Sc2MiscLayout.CITY_DAYS, 50)
	passive.set_misc_i32(Sc2MiscLayout.FUNDS, 75)
	campaign.documents["2,1"] = passive
	campaign.owners["2,1"] = "owner"
	campaign.acquired["2,1"] = 50
	campaign.settled["2,1"] = 50
	check(campaign.pack(first).is_empty(), "calendar archive packs")
	var restored := RegionCampaign.new()
	check(restored.restore(first.duplicate_document(true)).is_empty(), "synchronized city calendars restore")
	var stable_documents := restored.documents.duplicate()
	var stable_settled := restored.settled.duplicate()
	var stable_active := restored.active_cells.duplicate()
	var stable_bytes := preload("res://tests/support/document_state.gd").capture(restored.documents["1,1"])
	for mutation in ["inactive_past", "inactive_future", "inactive_far_future", "region_past", "active_past", "active_far_future"]:
		var damaged := first.duplicate_document(true)
		if mutation.begins_with("inactive_"):
			var child := passive.duplicate_document(true)
			child.set_misc_u32(Sc2MiscLayout.CITY_DAYS, 49 if mutation == "inactive_past" else 51 if mutation == "inactive_future" else 300)
			var encoded := Sc2xDocument.encode(child)
			check(encoded.ok, "malformed calendar still has a structurally valid city archive")
			damaged.sc2x_extra_entries[RegionCampaign.PREFIX + "2-1.sc2x"] = encoded.data
		elif mutation == "region_past":
			var data: Dictionary = JSON.parse_string(damaged.sc2x_extra_entries[RegionCampaign.ENTRY].get_string_from_utf8())
			data.day = 49
			for id: String in data.slots:
				data.slots[id].acquired = 49
				data.slots[id].settled = 49
			damaged.sc2x_extra_entries[RegionCampaign.ENTRY] = JSON.stringify(data).to_utf8_buffer()
		else:
			damaged.set_misc_u32(Sc2MiscLayout.CITY_DAYS, 49 if mutation == "active_past" else 52)
		check(not restored.restore(damaged).is_empty(), "inconsistent calendar rejected: " + mutation)
		check(restored.documents == stable_documents and restored.settled == stable_settled and restored.active_cells == stable_active,
			"rejected calendar preserves campaign ownership and settlement: " + mutation)
		check(restored.current_day == 50 and restored.own_funds("owner") == 20075 and
			preload("res://tests/support/document_state.gd").capture(restored.documents["1,1"]) == stable_bytes,
			"rejected calendar preserves current day and all active city bytes: " + mutation)
	var ahead := first.duplicate_document(true)
	ahead.set_misc_u32(Sc2MiscLayout.CITY_DAYS, 51)
	check(RegionCampaign.new().restore(ahead).is_empty(), "one completed active day survives the barrier and single-player export")


func _test_offers() -> void:
	var source := _document()
	var first := RegionCampaign.new()
	var second := RegionCampaign.new()
	check(first.initialize_at(source.duplicate_document(true), 3, 941, "owner", Vector2i(1, 1)).is_empty(), "first offer campaign")
	check(second.initialize_at(source.duplicate_document(true), 3, 941, "owner", Vector2i(1, 1)).is_empty(), "second offer campaign")
	var a := first.offer(Vector2i(2, 1))
	var other := second.offer(Vector2i(1, 2))
	var b := second.offer(Vector2i(2, 1))
	check(a.ok and b.ok and other.ok, "terrain offers generated")
	if not a.ok or not b.ok:
		return
	check(a.price == b.price, "offer price independent of preview order")
	for id in ["ALTM", "XTER", "XBLD", "XBIT"]:
		check(a.document.find_chunk(id).decoded_payload == b.document.find_chunk(id).decoded_payload, "offer terrain deterministic: " + id)
	var revision := first.revision
	check(first.offer(Vector2i(2, 1)).document == a.document and first.revision == revision, "repeat offer reuses frozen terrain")
	check(not first.offer(Vector2i(3, 1)).ok, "offer outside finite grid rejected")
	check(not first.offer(Vector2i(1, 1)).ok, "owned area never offered")
	var active: Sc2File = first.documents["1,1"]
	check(first.pack(active).is_empty(), "preview included in archive")
	var restored := RegionCampaign.new()
	check(restored.restore(active.duplicate_document(true)).is_empty(), "preview archive restores")
	check(restored.offer(Vector2i(2, 1)).price == a.price, "saved offer price retained")


func _test_boundary_edits() -> void:
	var city := CityState.from_document(_document())
	RegionBoundary.stamp(city.document)
	var random := SimRandom.new(928)
	for turn in 4:
		var before := preload("res://tests/support/document_state.gd").capture(city.document)
		var random_before := random.state
		var point := Vector2i(1, 15)
		var result := TerrainCommand.apply_path(city, 0, 2, point, [point], random, true)
		check(not result.ok and result.error == RegionBoundary.ERROR, "border change rejected in each camera orientation")
		check(before == preload("res://tests/support/document_state.gd").capture(city.document), "rejected edit preserves all chunks and funds")
		check(random.state == random_before, "rejected edit preserves random state")
		check(city.native_cache == null, "rejected edit invalidates mutated native cache")
		var inner := Vector2i(15, 15)
		check(TerrainCommand.apply_path(city, 0, 2, inner, [inner], random, true).ok, "interior remains editable after rejected cached operation")
		check(CityRotationCommand.apply(city, true).ok, "camera rotation remains available")
	var snapshot := preload("res://tests/support/document_state.gd").capture(city.document)
	var water := LandscapeCommand.apply_path(city, 1, 1, [Vector2i(0, 16)], random, true)
	check(not water.ok and snapshot == preload("res://tests/support/document_state.gd").capture(city.document), "border flooding rejected atomically")
	check(LandscapeCommand.apply_path(city, 1, 0, [Vector2i(0, 16)], random, true).ok, "border trees remain allowed")
	var single := CityState.from_document(_document())
	check(TerrainCommand.apply_path(single, 0, 2, Vector2i(1, 15), [Vector2i(1, 15)], random, true).ok, "ordinary single-city boundary remains editable")


func _test_purchase_terrain() -> void:
	var source := _document()
	source.set_misc_i32(Sc2MiscLayout.FUNDS, 100000)
	source.set_misc_u32(Sc2MiscLayout.START_YEAR, 1900)
	source.set_misc_u32(Sc2MiscLayout.DIFFICULTY, 3)
	var campaign := RegionCampaign.new()
	check(campaign.initialize_at(source, 3, 8193, "owner", Vector2i(1, 1)).is_empty(), "initialize hard region")
	var offered := campaign.offer(Vector2i(2, 1))
	check(offered.ok, "hard region offer")
	if not offered.ok:
		return
	var original: Sc2File = offered.document.duplicate_document(true)
	var bought := campaign.purchase("owner", Vector2i(2, 1), campaign.current_day)
	check(bought.ok, "hard region purchase succeeds")
	if not bought.ok:
		return
	var child: Sc2File = bought.document
	for id in ["ALTM", "XTER", "XBLD", "XZON", "XBIT"]:
		check(child.find_chunk(id).decoded_payload == original.find_chunk(id).decoded_payload, "purchased terrain equals offered terrain: " + id)
	for offset in [Sc2MiscLayout.WATER_LEVEL, Sc2MiscLayout.HAS_OCEAN, Sc2MiscLayout.HAS_RIVER]:
		check(child.misc_u32(offset) == original.misc_u32(offset), "purchased landscape metadata equals offer")
	check(child.misc_u32(Sc2MiscLayout.BONDS) == 0 and child.misc_i32(Sc2MiscLayout.FUNDS) == 0, "purchase grants no founding money or debt")
	var budget := Sc2MiscLayout.BUDGETS + Sc2BudgetLayout.BONDS * Sc2BudgetLayout.RECORD_SIZE
	for offset in range(0, Sc2BudgetLayout.RECORD_SIZE, 4):
		check(child.misc_u32(budget + offset) == 0, "purchase clears synthetic hard founding bond budget")
	check(campaign.own_funds("owner") == 100000 - int(offered.price), "purchase deducts price exactly once")


func _put_connection(document: Sc2File, point: Vector2i, tile: int, marked := true) -> void:
	for turn in int(document.misc_u32(Sc2MiscLayout.COMPASS) & 3):
		point = CityRotationCommand.rotate_point(point, document.map_size, true)
	var index := point.x * document.map_size + point.y
	var buildings := document.find_chunk("XBLD").decoded_payload.duplicate()
	var overlays := document.find_chunk("XTXT").decoded_payload.duplicate()
	buildings[index] = tile
	OverlayData.set_marker(overlays, index, Sc2OverlayLayout.CONNECTION_MARKER if marked else 0)
	document.find_chunk("XBLD").set_decoded_payload(buildings, true)
	document.find_chunk("XTXT").set_decoded_payload(overlays, true)


func _test_real_connections() -> void:
	var tiles := BuildingTileIds
	# Each case contains the left/right network and expected commerce/industry.
	for spec in [
		[tiles.ROAD_STRAIGHT_1, tiles.ROAD_STRAIGHT_1, 1, 0],
		[tiles.RAIL_STRAIGHT_1, tiles.RAIL_STRAIGHT_1, 0, 1],
		[tiles.HIGHWAY_STRAIGHT_1, tiles.HIGHWAY_STRAIGHT_1, 0, 1],
		[tiles.ROAD_STRAIGHT_1, tiles.RAIL_STRAIGHT_1, 0, 0],
		[tiles.RAIL_STRAIGHT_1, tiles.HIGHWAY_STRAIGHT_1, 0, 0],
		[tiles.HIGHWAY_STRAIGHT_1, tiles.ROAD_STRAIGHT_1, 0, 0],
		[tiles.ROAD_RAIL_CROSSING_1, tiles.ROAD_STRAIGHT_1, 1, 0],
		[tiles.ROAD_RAIL_CROSSING_1, tiles.RAIL_STRAIGHT_1, 0, 1],
		[tiles.ROAD_RAIL_CROSSING_1, tiles.ROAD_RAIL_CROSSING_1, 1, 1],
		[tiles.HIGHWAY_ROAD_CROSSING_1, tiles.ROAD_STRAIGHT_1, 1, 0],
		[tiles.HIGHWAY_RAIL_CROSSING_1, tiles.RAIL_STRAIGHT_1, 0, 1],
		[tiles.ROAD_STRAIGHT_1, tiles.EMPTY, 0, 0],
	]:
		var first := _document()
		var neighbor := _document()
		first.sc2x_metadata.city_name = "West city"
		neighbor.sc2x_metadata.city_name = "East city"
		var campaign := RegionCampaign.new()
		check(campaign.initialize_at(first, 3, 42, "local", Vector2i(0, 1)).is_empty(), "network fixture starts")
		RegionBoundary.stamp(neighbor)
		campaign.documents["1,1"] = neighbor
		campaign.owners["1,1"] = "local"
		_put_connection(first, Vector2i(31, 12), spec[0])
		_put_connection(neighbor, Vector2i(0, 12), spec[1])
		# Markers facing empty grid cells or the outside world never count.
		_put_connection(first, Vector2i(0, 4), tiles.ROAD_STRAIGHT_1)
		_put_connection(neighbor, Vector2i(31, 4), tiles.RAIL_STRAIGHT_1)
		# Offset endpoints and missing markers do not form a connection.
		_put_connection(first, Vector2i(31, 18), tiles.ROAD_STRAIGHT_1)
		_put_connection(neighbor, Vector2i(0, 19), tiles.ROAD_STRAIGHT_1)
		_put_connection(first, Vector2i(31, 22), tiles.RAIL_STRAIGHT_1, false)
		_put_connection(neighbor, Vector2i(0, 22), tiles.RAIL_STRAIGHT_1)
		# A marker deeper than the two boundary rows is not an endpoint.
		_put_connection(first, Vector2i(29, 25), tiles.ROAD_STRAIGHT_1)
		_put_connection(neighbor, Vector2i(0, 25), tiles.ROAD_STRAIGHT_1)
		var names_before: Array = []
		for turn in 4:
			campaign.synchronize_neighbors()
			var expected := PackedInt64Array([spec[2], spec[3]])
			check(RegionCampaign.connection_counts(first) == expected, "matching network types count west-side bonuses: " + str(spec))
			check(RegionCampaign.connection_counts(neighbor) == expected, "matching network types count east-side bonuses: " + str(spec))
			var west: Dictionary = JSON.parse_string(first.sc2x_extra_entries[RegionCampaign.NEIGHBORS_ENTRY].get_string_from_utf8())
			var east: Dictionary = JSON.parse_string(neighbor.sc2x_extra_entries[RegionCampaign.NEIGHBORS_ENTRY].get_string_from_utf8())
			check(west.names[0] == "East city" and east.names[2] == "West city", "neighbor names use real world-side cities")
			if turn == 0:
				names_before = [west.names, east.names]
			else:
				check(names_before == [west.names, east.names], "saved neighbor names remain stable through independent camera rotations")
			check(CityRotationCommand.apply(CityState.from_document(first), true).ok, "west camera rotates")
			if turn % 2 == 0:
				check(CityRotationCommand.apply(CityState.from_document(neighbor), false).ok, "east camera rotates independently")
		# A valid marker one row inside is also a legitimate original-style exit.
		_put_connection(first, Vector2i(30, 8), tiles.ROAD_STRAIGHT_1)
		_put_connection(neighbor, Vector2i(1, 8), tiles.ROAD_STRAIGHT_1)
		campaign.synchronize_neighbors()
		check(RegionCampaign.connection_counts(first) == PackedInt64Array([spec[2] + 1, spec[3]]), "second boundary row is supported")
