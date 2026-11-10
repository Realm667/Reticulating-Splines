class_name RegionCampaign
extends RefCounted
## Authoritative region state. Child archives never contain a parent region archive.

@warning_ignore_start("integer_division")

const ENTRY := "region.json"
const ADMIN_ENTRY := "region-administration.json"
const NEIGHBORS_ENTRY := "region-neighbors.json"
const PREFIX := "region-city-"
const TEMPLATE_ENTRY := "region-template.sc2x"
const MAX_TOTAL_BYTES := 384 * 1024 * 1024
var edge := 3
var seed_value := 1
var origin := Vector2i.ZERO
var template: Sc2File
var name := ""
var documents: Dictionary[String, Sc2File] = {}
var owners: Dictionary[String, String] = {}
var acquired: Dictionary[String, int] = {}
var settled: Dictionary[String, int] = {}
var first_cells: Dictionary[String, String] = {}
var active_cells: Dictionary[String, String] = {}
var offers: Dictionary[String, Sc2File] = {}
var current_day := 0
var revision := 0
var multiplayer := false
var _neighbor_signature: Array = []


func initialize(first: Sc2File, size: int, random_seed: int, owner: String) -> String:
	if not documents.is_empty() or first == null or not first.is_sc2x() or size not in RegionRules.SIZES or owner.is_empty():
		return "Invalid region configuration."
	edge = size
	seed_value = random_seed
	origin = RegionRules.start_positions(edge, 1, seed_value)[0]
	template = clean_copy(first)
	name = first.city_name()
	current_day = first.misc_u32(Sc2MiscLayout.CITY_DAYS)
	var id := RegionRules.key(origin)
	documents[id] = first
	owners[id] = owner
	first_cells[owner] = id
	active_cells[owner] = id
	acquired[id] = current_day
	settled[id] = current_day
	clear_neighbors(first)
	RegionBoundary.stamp(first)
	synchronize_neighbors()
	return ""


func initialize_at(first: Sc2File, size: int, random_seed: int, owner: String, position: Vector2i) -> String:
	if not RegionRules.contains(size, position):
		return "Invalid region coordinates."
	var error := initialize(first, size, random_seed, owner)
	if not error.is_empty():
		return error
	var previous := RegionRules.key(origin)
	var id := RegionRules.key(position)
	if previous != id:
		documents.erase(previous)
		owners.erase(previous)
		acquired.erase(previous)
		settled.erase(previous)
		documents[id] = first
		owners[id] = owner
		acquired[id] = current_day
		settled[id] = current_day
		first_cells[owner] = id
		active_cells[owner] = id
	origin = position
	synchronize_neighbors()
	return ""


func adjacent(owner: String, position: Vector2i) -> bool:
	for direction: Vector2i in RegionRules.DIRECTIONS:
		if owners.get(RegionRules.key(position + direction), "") == owner:
			return true
	return false


func offer(position: Vector2i) -> Dictionary:
	var id := RegionRules.key(position)
	if not RegionRules.contains(edge, position) or owners.has(id):
		return failure("This city area is not available.")
	if not offers.has(id):
		var neighbors := {}
		for side in RegionRules.DIRECTIONS.size():
			var neighbor := RegionRules.key(position + RegionRules.DIRECTIONS[side])
			if documents.has(neighbor):
				neighbors[side] = documents[neighbor]
		var generated := RegionTerrain.generate(template, position, origin, seed_value, neighbors)
		if not generated.get("ok", false):
			return generated
		var document: Sc2File = generated.document
		if not document.is_sc2x():
			var converted := Sc2xDocument.from_new_city(document, "New City", "Mayor")
			if not converted.ok:
				return failure(converted.error)
			document = converted.document
		if ExpandedRules.enabled(template):
			var expanded_error := ExpandedRules.enable(document)
			if not expanded_error.is_empty():
				return failure(expanded_error)
		if QuarterTerrain.enabled(template):
			var quarter_error:=QuarterTerrain.enable(CityState.from_document(document))
			if not quarter_error.is_empty():
				return failure(quarter_error)
		offers[id] = document
		revision += 1
	var report := terrain_price(offers[id])
	report["ok"] = true
	report["error"] = ""
	report["document"] = offers[id]
	report["revision"] = revision
	return report


static func terrain_price(document: Sc2File) -> Dictionary:
	var terrain := document.find_chunk("XTER").decoded_payload
	var flags := document.find_chunk("XBIT").decoded_payload
	var counts := {"flat": 0, "slope": 0, "water": 0}
	for index in terrain.size():
		if flags[index] & Sc2TileFlags.WATER:
			counts.water += 1
		elif (terrain[index] & TerrainTileIds.SHAPE_MASK) != TerrainTileIds.FLAT:
			counts.slope += 1
		else:
			counts.flat += 1
	counts["price"] = RegionRules.purchase_price(counts.flat, counts.slope, counts.water)
	return counts


func own_funds(owner: String) -> int:
	var total := 0
	for id: String in documents:
		if owners[id] == owner:
			total += documents[id].misc_i32(Sc2MiscLayout.FUNDS)
	return total


func own_debt(owner: String) -> int:
	var total := 0
	for id: String in documents:
		if owners[id] == owner:
			total += documents[id].misc_u32(Sc2MiscLayout.BONDS) * BondCommand.BOND_VALUE
	return total


func own_count(owner: String) -> int:
	var total := 0
	for value: String in owners.values():
		total += int(value == owner)
	return total


func commitments(owner: String) -> int:
	var total := 0
	for id: String in documents:
		if owners[id] == owner:
			var city := CityState.from_document(documents[id])
			var report := BudgetReport.capture(city, BudgetPhase.funding_values(city))
			total += maxi(0, -report.ytd_cash)
	return total


func purchase(owner: String, position: Vector2i, day: int, external_debt := 0) -> Dictionary:
	var id := RegionRules.key(position)
	if not RegionRules.contains(edge, position) or owners.has(id) or not adjacent(owner, position) or not offers.has(id):
		return failure("Choose an available city area next to your own territory.")
	var price := int(terrain_price(offers[id]).price)
	var check := RegionRules.purchase_check(own_funds(owner), own_debt(owner) + external_debt,
		commitments(owner), price, own_count(owner))
	if not check.ok:
		return failure("Insufficient own funds for the purchase and administration reserve.")
	var source := documents[active_cells[owner]]
	# Founding expects the legacy name chunk. SC2X offers store their name in
	# metadata, so copy only the generated terrain into a fresh founding template.
	var terrain := EmptyCityTemplate.create(source.map_size)
	for chunk_id: String in RegionTerrain.CHUNKS:
		terrain.find_chunk(chunk_id).set_decoded_payload(offers[id].find_chunk(chunk_id).decoded_payload, true)
	var founded := NewCitySetup.create(terrain, "New City", source.sc2x_metadata.mayor_name,
		clampi(source.misc_u32(Sc2MiscLayout.DIFFICULTY), 1, 3),
		int(source.misc_u32(Sc2MiscLayout.START_YEAR)), SimRandom.new(seed_value ^ (position.x * 31 + position.y + 1)))
	if not founded.ok:
		return failure(founded.error)
	var converted := Sc2xDocument.from_new_city(founded.document, "New City", source.sc2x_metadata.mayor_name)
	if not converted.ok:
		return failure(converted.error)
	var fresh := converted.document
	fresh.set_misc_i32(Sc2MiscLayout.FUNDS, 0)
	fresh.set_misc_u32(Sc2MiscLayout.BONDS, 0)
	for offset in range(0, BondCommand.MAX_BONDS * 4, 4):
		fresh.set_misc_u32(Sc2MiscLayout.BOND_RATES + offset, 0)
	for offset in range(0, Sc2BudgetLayout.RECORD_SIZE, 4):
		fresh.set_misc_u32(Sc2MiscLayout.BUDGETS + Sc2BudgetLayout.BONDS * Sc2BudgetLayout.RECORD_SIZE + offset, 0)
	fresh.set_misc_u32(Sc2MiscLayout.CITY_DAYS, day)
	clear_neighbors(fresh)
	RegionBoundary.stamp(fresh)
	# No mutation until generation and all money checks have succeeded.
	if not collect_funds(owner, source):
		return failure("The regional treasury exceeds the supported balance.")
	source.set_misc_i32(Sc2MiscLayout.FUNDS, source.misc_i32(Sc2MiscLayout.FUNDS) - price)
	documents[id] = fresh
	owners[id] = owner
	acquired[id] = day
	settled[id] = day
	offers.erase(id)
	revision += 1
	update_administration(id, day)
	synchronize_neighbors()
	return {"ok": true, "error": "", "document": fresh, "price": price, "cell": id}


func collect_funds(owner: String, active_document: Sc2File) -> bool:
	var total := own_funds(owner)
	if total < -2147483648 or total > 2147483647:
		return false
	var found := false
	for id: String in documents:
		found = found or (owners[id] == owner and documents[id] == active_document)
	if not found:
		return false
	for id: String in documents:
		if owners[id] == owner:
			var value := total if documents[id] == active_document else 0
			if documents[id].misc_i32(Sc2MiscLayout.FUNDS) != value:
				documents[id].set_misc_i32(Sc2MiscLayout.FUNDS, value)
	return true


func advance(day: int) -> void:
	if day < current_day:
		return
	for id: String in documents:
		var document := documents[id]
		var city := CityState.from_document(document)
		if id not in active_cells.values():
			# Inactive cities retain their development. Only the existing budget phase
			# runs at month boundaries; no growth/traffic/land-value phases are executed.
			var random := SimRandom.new(document.sc2x_metadata.process_random)
			var previous := city.age_in_days()
			for month_day in range((previous / CityCalendar.DAYS_PER_MONTH + 1) * CityCalendar.DAYS_PER_MONTH,
				day + 1, CityCalendar.DAYS_PER_MONTH):
				city.set_age_in_days(month_day)
				var result := BudgetPhase.run(city, random, true)
				if not result.ok:
					break
			city.set_age_in_days(day)
			document.sc2x_metadata.process_random = random.state
		if first_cells.get(owners[id]) != id:
			var due := RegionRules.administration_due(acquired[id], settled[id], day, CityCalendar.DAYS_PER_YEAR)
			if due > 0:
				city.set_funds(maxi(-2147483648, city.funds() - due))
		settled[id] = day
		update_administration(id, day)
	current_day = day
	synchronize_neighbors()


func update_administration(id: String, day: int) -> void:
	var additional: bool = first_cells.get(owners[id]) != id
	var year_start := day / CityCalendar.DAYS_PER_YEAR * CityCalendar.DAYS_PER_YEAR
	var ytd := RegionRules.administration_due(acquired[id], maxi(acquired[id], year_start), day,
		CityCalendar.DAYS_PER_YEAR) if additional else 0
	documents[id].sc2x_extra_entries[ADMIN_ENTRY] = JSON.stringify({"annual": RegionRules.ANNUAL_ADMINISTRATION if additional else 0,
		"ytd": ytd, "acquired": acquired[id], "settled": day}).to_utf8_buffer()


static func administration_report(document: Sc2File) -> Dictionary:
	var result := {"annual": 0, "ytd": 0, "estimated": 0, "remaining": 0}
	if not document.sc2x_extra_entries.has(ADMIN_ENTRY):
		return result
	var data: Variant = JSON.parse_string(document.sc2x_extra_entries.get(ADMIN_ENTRY, PackedByteArray()).get_string_from_utf8())
	if not data is Dictionary or int(data.get("annual", 0)) <= 0:
		return result
	var day := document.misc_u32(Sc2MiscLayout.CITY_DAYS)
	var year_end := document.misc_u32(Sc2MiscLayout.YEAR_END) != 0 and day % CityCalendar.DAYS_PER_YEAR == 0
	var year_start := maxi(0, day - int(year_end)) / CityCalendar.DAYS_PER_YEAR * CityCalendar.DAYS_PER_YEAR
	var acquired_day := int(data.get("acquired", day))
	result.annual = RegionRules.ANNUAL_ADMINISTRATION
	result.ytd = RegionRules.administration_due(acquired_day, maxi(acquired_day, year_start), day, CityCalendar.DAYS_PER_YEAR)
	result.estimated = RegionRules.ANNUAL_ADMINISTRATION if year_end else RegionRules.administration_due(
		acquired_day, maxi(acquired_day, year_start), year_start + CityCalendar.DAYS_PER_YEAR, CityCalendar.DAYS_PER_YEAR)
	# Fees are already charged daily. Only the unpaid remainder belongs in the
	# year-end balance; the annual settlement must never charge them a second time.
	result.remaining = 0 if year_end else maxi(0, result.estimated - result.ytd)
	return result


static func clear_neighbors(document: Sc2File) -> void:
	for side in CityNeighbors.COUNT:
		for offset in range(0, CityNeighbors.STRIDE, 4):
			document.set_misc_u32(Sc2MiscLayout.NEIGHBORS + side * CityNeighbors.STRIDE + offset, 0)


static func clean_copy(document: Sc2File) -> Sc2File:
	var copy := document.duplicate_document(true)
	for entry: String in copy.sc2x_extra_entries.keys():
		if entry == ENTRY or entry == TEMPLATE_ENTRY or entry == "multiplayer.json" or entry.begins_with(PREFIX):
			copy.sc2x_extra_entries.erase(entry)
	return copy


func pack(active_document: Sc2File) -> String:
	var active_id := ""
	for id: String in documents:
		if documents[id] == active_document:
			active_id = id
	if active_id.is_empty():
		return "The current city is not part of this region."
	var members: Dictionary[String, PackedByteArray] = {}
	var slots := {}
	var total := 0
	for id: String in documents:
		slots[id] = {"owner": owners[id], "acquired": acquired[id], "settled": settled[id]}
		if id != active_id:
			var encoded := Sc2xDocument.encode(clean_copy(documents[id]))
			if not encoded.ok:
				return encoded.error
			members[PREFIX + id.replace(",", "-") + ".sc2x"] = encoded.data
			total += encoded.data.size()
	for id: String in offers:
		var encoded := Sc2xDocument.encode(clean_copy(offers[id]))
		if not encoded.ok:
			return encoded.error
		members[PREFIX + "offer-" + id.replace(",", "-") + ".sc2x"] = encoded.data
		total += encoded.data.size()
	var base := Sc2xDocument.encode(clean_copy(template))
	if not base.ok:
		return base.error
	if total + base.data.size() > MAX_TOTAL_BYTES:
		return "The region exceeds the supported save size."
	members[TEMPLATE_ENTRY] = base.data
	members[ENTRY] = JSON.stringify({"version": RegionRules.VERSION, "edge": edge, "seed": str(seed_value),
		"origin": RegionRules.key(origin), "name": name, "active": active_id, "first_cells": first_cells,
		"active_cells": active_cells, "day": current_day, "revision": revision, "multiplayer": multiplayer,
		"slots": slots, "offers": offers.keys()}).to_utf8_buffer()
	for entry: String in active_document.sc2x_extra_entries.keys():
		if entry == ENTRY or entry == TEMPLATE_ENTRY or entry.begins_with(PREFIX):
			active_document.sc2x_extra_entries.erase(entry)
	active_document.sc2x_extra_entries.merge(members, true)
	return ""


func restore(active_document: Sc2File) -> String:
	var data: Variant = JSON.parse_string(active_document.sc2x_extra_entries.get(ENTRY, PackedByteArray()).get_string_from_utf8())
	if not data is Dictionary or data.get("version") != RegionRules.VERSION or not _whole(data.get("edge")) or int(data.get("edge", 0)) not in RegionRules.SIZES:
		return "Unsupported or invalid region save."
	if not data.get("seed") is String or not data.seed.is_valid_int() or str(int(data.seed)) != data.seed:
		return "Unsupported or invalid region save."
	if not data.get("slots") is Dictionary or not data.get("offers") is Array or not data.get("first_cells") is Dictionary or not data.get("active_cells") is Dictionary:
		return "Invalid region ownership data."
	var loaded: Dictionary[String, Sc2File] = {}
	var previews: Dictionary[String, Sc2File] = {}
	var size := int(data.edge)
	var day: Variant = data.get("day")
	var saved_revision: Variant = data.get("revision")
	if not _whole(day) or not _whole(saved_revision) or day < 0 or day > 2147483647 or saved_revision < 0:
		return "Invalid region city data."
	var member_bytes := 0
	for entry: String in active_document.sc2x_extra_entries:
		if entry == TEMPLATE_ENTRY or entry.begins_with(PREFIX):
			member_bytes += active_document.sc2x_extra_entries[entry].size()
	if member_bytes > MAX_TOTAL_BYTES:
		return "The region exceeds the supported save size."
	if data.slots.is_empty() or data.slots.size() + data.offers.size() > size * size or not data.slots.has(data.get("active", "")):
		return "Invalid region city count."
	var base := _read_member(active_document, TEMPLATE_ENTRY)
	if base == null or base.map_size != active_document.map_size:
		return "Invalid region terrain reference."
	for id: Variant in data.slots:
		if not _coordinate(id, size):
			return "Invalid region coordinates."
		var slot: Variant = data.slots[id]
		if not slot is Dictionary or not slot.get("owner") is String or slot.owner.is_empty() or not _whole(slot.get("acquired")) or not _whole(slot.get("settled")):
			return "Invalid region ownership data."
		if not data.first_cells.has(slot.owner) or not data.active_cells.has(slot.owner):
			return "Invalid region ownership data."
		var child: Sc2File = active_document if id == data.active else _read_member(active_document, PREFIX + id.replace(",", "-") + ".sc2x")
		if child == null or child.map_size != active_document.map_size or int(slot.acquired) < 0 or int(slot.settled) < int(slot.acquired) or int(slot.settled) > int(day):
			return "Invalid region city data."
		var city_day := child.misc_u32(Sc2MiscLayout.CITY_DAYS)
		# Inactive budgets are settled exactly to the committed regional day.
		# Active cities may be one completed day ahead at the multiplayer barrier;
		# an explicit single-player export preserves that valid checkpoint too.
		var latest_day := int(day) + int(data.active_cells[slot.owner] == id)
		if city_day < int(day) or city_day > latest_day:
			return "Invalid region city data."
		loaded[id] = child
	for id: Variant in data.offers:
		if not _coordinate(id, size) or loaded.has(id) or previews.has(id):
			return "Invalid region offer."
		var child := _read_member(active_document, PREFIX + "offer-" + id.replace(",", "-") + ".sc2x")
		if child == null or child.map_size != active_document.map_size:
			return "Invalid region offer."
		previews[id] = child
	for owner: Variant in data.first_cells:
		if not owner is String or not loaded.has(data.first_cells[owner]) or not loaded.has(data.active_cells.get(owner, "")):
			return "Invalid region player data."
		if data.slots[data.first_cells[owner]].owner != owner or data.slots[data.active_cells[owner]].owner != owner:
			return "Invalid region player data."
	if data.first_cells.size() != data.active_cells.size() or not _coordinate(data.get("origin"), size):
		return "Invalid region player data."
	if data.active_cells.get(data.slots[data.active].owner) != data.active:
		return "Invalid region player data."
	edge = size
	seed_value = int(data.get("seed", "1"))
	origin = RegionRules.cell(data.origin)
	name = str(data.get("name", ""))
	template = base
	documents = loaded
	offers = previews
	owners.clear()
	acquired.clear()
	settled.clear()
	for id: String in loaded:
		owners[id] = data.slots[id].owner
		acquired[id] = int(data.slots[id].acquired)
		settled[id] = int(data.slots[id].settled)
	first_cells.assign(data.first_cells)
	active_cells.assign(data.active_cells)
	current_day = int(data.get("day", 0))
	revision = int(data.get("revision", 0))
	multiplayer = bool(data.get("multiplayer", false))
	for document: Sc2File in documents.values():
		RegionBoundary.stamp(document)
	synchronize_neighbors()
	return ""


func synchronize_neighbors() -> void:
	var signature: Array = []
	for id: String in documents:
		var document := documents[id]
		signature.append_array([id, document.get_instance_id(), document.city_name(),
			document.misc_u32(Sc2MiscLayout.COMPASS), document.misc_u32(Sc2MiscLayout.NORMAL_POPULATION),
			document.misc_u32(Sc2MiscLayout.ARCOLOGY_POPULATION), document.misc_u32(Sc2MiscLayout.CITY_VALUE)])
		for chunk_id: String in ["XBLD", "XTXT", "XBIT"]:
			signature.append(document.find_chunk(chunk_id).mutation_revision)
	if signature == _neighbor_signature:
		return
	_neighbor_signature = signature
	for id: String in documents:
		var document := documents[id]
		var names := ["", "", "", ""]
		var counts := PackedInt64Array([0, 0])
		var incoming := []
		for side in 4:
			var neighbor: Sc2File = documents.get(RegionRules.key(RegionRules.cell(id) + RegionRules.DIRECTIONS[side]))
			var slot := (side + 2) % 4
			var base := Sc2MiscLayout.NEIGHBORS + slot * CityNeighbors.STRIDE
			var population := 0
			var value := 0
			var shore := 0
			for along in document.map_size:
				var point := RegionTerrain._edge_point(side, along, 0, document.map_size)
				shore += int(RegionTerrain._sample(document, point)[3] != 0)
			if neighbor != null:
				names[slot] = neighbor.city_name()
				population = neighbor.misc_u32(Sc2MiscLayout.NORMAL_POPULATION) + neighbor.misc_u32(Sc2MiscLayout.ARCOLOGY_POPULATION)
				value = neighbor.misc_u32(Sc2MiscLayout.CITY_VALUE)
				for along in document.map_size:
					var local_network := _edge_network(document, side, along)
					var remote_network := _edge_network(neighbor, (side + 2) % 4, along)
					var shared := local_network & remote_network
					counts[0] += int((shared & 1) != 0)
					counts[1] += int((shared & 6) != 0)
					if (remote_network & ~local_network) != 0:
						incoming.append({"side": side, "along": along, "network": remote_network & ~local_network,
							"name": neighbor.city_name()})
			# These fields describe actual cities; SimNation does not invent growth.
			for pair in [[0, 0 if shore * 2 >= document.map_size else 1], [4, population], [8, value], [12, 0]]:
				if document.misc_u32(base + pair[0]) != pair[1]:
					document.set_misc_u32(base + pair[0], pair[1])
		document.sc2x_extra_entries[NEIGHBORS_ENTRY] = JSON.stringify({"names": names,
			"connections": [counts[0], counts[1]], "incoming": incoming}).to_utf8_buffer()


static func incoming_connections(document: Sc2File) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var bytes: PackedByteArray = document.sc2x_extra_entries.get(NEIGHBORS_ENTRY, PackedByteArray())
	if bytes.is_empty():
		return result
	var parser := JSON.new()
	if parser.parse(bytes.get_string_from_utf8()) != OK:
		return result
	var data: Variant = parser.data
	if not data is Dictionary or not data.get("incoming") is Array:
		return result
	for entry: Variant in data.incoming:
		if not entry is Dictionary:
			continue
		var side := int(entry.get("side", -1))
		var along := int(entry.get("along", -1))
		var network := int(entry.get("network", 0)) & 7
		if side < 0 or side > 3 or along < 0 or along >= document.map_size or network == 0:
			continue
		var point := RegionTerrain._edge_point(side, along, 0, document.map_size)
		for turn in int(document.misc_u32(Sc2MiscLayout.COMPASS) & 3):
			point = CityRotationCommand.rotate_point(point, document.map_size, true)
		result.append({"point": point, "network": network, "name": str(entry.get("name", ""))})
	return result


static func connection_counts(document: Sc2File) -> PackedInt64Array:
	if not document.sc2x_extra_entries.has(RegionBoundary.ENTRY):
		return PackedInt64Array()
	if not document.sc2x_extra_entries.has(NEIGHBORS_ENTRY):
		return PackedInt64Array([0, 0])
	var data: Variant = JSON.parse_string(document.sc2x_extra_entries.get(NEIGHBORS_ENTRY, PackedByteArray()).get_string_from_utf8())
	if data is Dictionary and data.get("connections") is Array and data.connections.size() == 2:
		return PackedInt64Array([int(data.connections[0]), int(data.connections[1])])
	return PackedInt64Array([0, 0])


static func _edge_network(document: Sc2File, side: int, along: int) -> int:
	var buildings := document.find_chunk("XBLD").decoded_payload
	var overlays := document.find_chunk("XTXT").decoded_payload
	var mask := 0
	for depth in 2:
		var point := RegionTerrain._edge_point(side, along, depth, document.map_size)
		for turn in int(document.misc_u32(Sc2MiscLayout.COMPASS) & 3):
			point = CityRotationCommand.rotate_point(point, document.map_size, true)
		var index := point.x * document.map_size + point.y
		if OverlayData.marker(overlays, index) != Sc2OverlayLayout.CONNECTION_MARKER:
			continue
		var tile := int(buildings[index])
		if NetworkTileMembership.surface_road(tile):
			mask |= 1
		if NetworkTileMembership.rail(tile):
			mask |= 2
		if (tile >= BuildingTileIds.HIGHWAY_STRAIGHT_1 and tile <= BuildingTileIds.HIGHWAY_POWER_CROSSING_2) or (tile >= BuildingTileIds.HIGHWAY_SLOPE_1 and tile <= BuildingTileIds.REINFORCED_HIGHWAY_BRIDGE):
			mask |= 4
	return mask


static func _read_member(parent: Sc2File, entry: String) -> Sc2File:
	var bytes: PackedByteArray = parent.sc2x_extra_entries.get(entry, PackedByteArray())
	if bytes.is_empty() or bytes.size() > MAX_TOTAL_BYTES:
		return null
	var child := Sc2File.new()
	if not child.parse(bytes) or not child.is_sc2x() or child.sc2x_extra_entries.has(ENTRY):
		return null
	for nested: String in child.sc2x_extra_entries:
		if nested == TEMPLATE_ENTRY or nested.begins_with(PREFIX):
			return null
	return child


static func _whole(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))


static func _coordinate(value: Variant, size: int) -> bool:
	return value is String and RegionRules.contains(size, RegionRules.cell(value)) and RegionRules.key(RegionRules.cell(value)) == value


static func failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
