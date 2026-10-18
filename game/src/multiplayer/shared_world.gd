class_name SharedWorld
extends CoopWorld
## One physical terrain, separate municipal simulations and budgets.
## Each municipality simulates only its own infrastructure and zoned buildings.

const LAND_PRICE := 10
var land_price := LAND_PRICE
var starter_tiles := 0
var land_allowance: Dictionary = {}
const TILE_CHUNKS := {"ALTM": 2, "XTER": 1, "XBLD": 1, "XZON": 1, "XUND": 1, "XBIT": 1}
var municipalities: Dictionary = {}
var actors: Array[String] = []
var owners := PackedInt32Array()
# -1 public corridor, 0 unreserved, positive values reserve for an owner index.
var protection := PackedInt32Array()
var template: Sc2File
var offers: Dictionary = {}
var next_offer := 1
var land_history: Array = []
var land_statistics: Dictionary = {}
var host_actor := ""
var snapshot_cache: Dictionary = {}
var composed_revision := -1
var composed_chunks: Dictionary = {}
var composition_sources: Dictionary = {}
var composition_owners := PackedInt32Array()
var composition_protection := PackedInt32Array()
var municipal_compression: Dictionary = {}
var live_documents: Dictionary = {}
var shared_live_document := MultiplayerDocument.new()
var record_cache: Dictionary = {}
var record_signature: Array = []
var record_overlay_cache: Dictionary = {}
var restored_empty_corridors: Dictionary = {}


func open(document: Sc2File) -> bool:
	if not super.open(document):
		return false
	template = document.duplicate_document()
	template.sc2x_extra_entries.erase("multiplayer.json")
	owners.resize(city.map_size * city.map_size)
	owners.fill(0)
	protection.resize(owners.size())
	protection.fill(0)
	return true


func add_player(actor: String) -> String:
	if municipalities.has(actor):
		return ""
	if actors.size() >= 8:
		return "The shared map already has eight municipalities."
	var document := template.duplicate_document()
	# Imported development belongs to the initial municipality. Guests get fresh
	# accounts and the same natural terrain, never a copy of the host's debts/assets.
	if not actors.is_empty():
		document = EmptyCityTemplate.create(template.map_size)
		var starting_year := city.founding_year() if city.founding_year() in NewCitySetup.STARTING_YEARS else 1900
		var fresh := NewCitySetup.create(document, document.city_name(), "Mayor", clampi(city.difficulty(), 1, 3), starting_year, SimRandom.new(actors.size() + 1))
		if not fresh.ok:
			return fresh.error
		document = Sc2xDocument.from_new_city(fresh.document, "City %d" % (actors.size() + 1), "Mayor").document
		for id in ["ALTM", "XTER", "XBIT"]:
			document.find_chunk(id).set_decoded_payload(template.find_chunk(id).decoded_payload.duplicate())
		var natural := template.find_chunk("XBLD").decoded_payload.duplicate()
		for index in natural.size():
			if natural[index] > 13:
				natural[index] = 0
		document.find_chunk("XBLD").set_decoded_payload(natural)
		for field in [Sc2MiscLayout.START_YEAR, Sc2MiscLayout.DIFFICULTY, Sc2MiscLayout.NO_DISASTERS]:
			document.set_misc_u32(field, template.misc_u32(field))
	var child := CoopWorld.new()
	if not child.open(document):
		return child.error
	child.city.set_age_in_days(city.age_in_days())
	child.engine.clock.city_days = city.age_in_days()
	child.controller.accumulator_msec = controller.accumulator_msec
	child.controller.subtick_counter = controller.subtick_counter
	municipalities[actor] = child
	land_statistics[actor] = {"bought": 0, "sold": 0}
	land_allowance[actor] = mini(starter_tiles, city.map_size * city.map_size / 4) * land_price
	actors.append(actor)
	revision += 1
	snapshot_cache.clear()
	if host_actor.is_empty():
		host_actor = actor
		city = child.city
		engine = child.engine
		controller = child.controller
		for tile in owners.size():
			if child.city.buildings[tile] > 13 or child.city.zones[tile] != 0 or child.city.underground[tile] != 0:
				owners[tile] = 1
	return ""


func set_shared_speed(value: int) -> void:
	for child: CoopWorld in municipalities.values():
		child.controller.set_speed(value)
	snapshot_cache.clear()


func advance(delta: float) -> void:
	if controller.speed == GameSpeedController.Speed.PAUSED:
		return
	var previous_age := city.age_in_days()
	var changed := false
	var emergency := false
	for child: CoopWorld in municipalities.values():
		emergency = emergency or child.engine.active_disaster_type != 0
	for actor: String in actors:
		var child: CoopWorld = municipalities[actor]
		if emergency and child.engine.active_disaster_type == 0:
			continue
		var before := child.revision
		var before_policy := child.policy_revision
		var before_error := child.error
		var before_document := child.city.document.duplicate_document(true)
		child.tree_growth_enabled = false # Grow the composed physical map once below.
		child.advance(delta)
		if child.revision != before:
			for tile: int in changed_tiles(before_document, child.city.document):
				tile_versions[tile] = revision + 1
		# Decisions and errors must invalidate the shared snapshot even when the
		# simulation produced no map edit during this advance.
		changed = changed or child.revision != before or child.policy_revision != before_policy or child.error != before_error
	city = municipalities[host_actor].city
	engine = municipalities[host_actor].engine
	controller = municipalities[host_actor].controller
	if changed:
		revision += 1
	_grow_forest(previous_age)


func _grow_forest(previous_age: int) -> void:
	if not ForestGrowth.due(city, previous_age, tree_growth_enabled):
		return
	# Reuse the authoritative composition so forests can cross ownership borders
	# without growing over another municipality's buildings or infrastructure.
	snapshot_for(host_actor, true)
	var document := city.document.duplicate_document()
	for id: String in TILE_CHUNKS:
		document.find_chunk(id).set_decoded_payload(composed_chunks[id])
	var landscape := CityState.from_document(document)
	var grown := ForestGrowth.advance(landscape, previous_age, true)
	if grown.is_empty():
		return
	var sources: Array[PackedByteArray] = []
	sources.append(template.find_chunk("XBLD").decoded_payload.duplicate())
	for actor: String in actors:
		sources.append(municipalities[actor].city.buildings.duplicate())
	var touched := {}
	for tile in grown:
		var owner := owners[tile]
		if protection[tile] == -1:
			owner = 1
		sources[owner][tile] = landscape.buildings[tile]
		touched[owner] = true
		tile_versions[tile] = revision + 1
	for owner: int in touched:
		if owner == 0:
			ForestGrowth.apply_buildings(CityState.from_document(template), sources[0])
		else:
			var child: CoopWorld = municipalities[actors[owner - 1]]
			ForestGrowth.apply_buildings(child.city, sources[owner])
			child.revision += 1
			child.undo_document = null
			for tile in grown:
				if owners[tile] == owner:
					child.tile_versions[tile] = child.revision
	# Neutral terrain comes from the template, not a municipal source buffer.
	composed_chunks.erase("XBLD")
	composition_sources.erase("XBLD")
	revision += 1


func command(actor: String, request: Dictionary) -> Dictionary:
	if not municipalities.has(actor):
		return rejected("No municipality is assigned to this player.")
	if not whole_number(request.get("revision"), 0, revision):
		return rejected("Invalid map revision.")
	if request.get("kind") in ["land_buy", "land_request", "land_offer", "land_accept", "land_withdraw", "land_decline", "land_counter"]:
		return land_command(actor, request)
	if request.get("kind") == "recall":
		for municipality: CoopWorld in municipalities.values():
			var things := municipality.city.document.find_chunk("XTHG").decoded_payload.duplicate()
			var text := municipality.city.text_overlays.duplicate()
			for key: String in municipality.dispatch_owners.keys():
				if municipality.dispatch_owners[key].actor == actor.sha256_text():
					remove_dispatch(things, text, int(key))
					municipality.dispatch_owners.erase(key)
			municipality.city.document.find_chunk("XTHG").set_decoded_payload(things)
			municipality.city.document.find_chunk("XTXT").set_decoded_payload(text)
			municipality.city.resync_mirrors(["XTXT"])
			municipality.revision += 1
		revision += 1
		return accepted("Your emergency units were recalled.")
	var child: CoopWorld = municipalities[actor]
	var local := request.duplicate(true)
	local.revision = child.revision
	if request.get("kind") == "disaster" and point_valid(request.get("point")):
		var target := point(request.point)
		if owners[city.index_of(target.x, target.y)] != actors.find(actor) + 1:
			return rejected("Manual disasters can only be started in your own municipality.")
	if request.get("kind") == "build" and request.get("group") == CityToolIds.Group.DISPATCH:
		return help_disaster(actor, request)
	if request.get("kind") in ["build", "sign"]:
		if not point_valid(request.get("start")) or not point_valid(request.get("finish")):
			return rejected("Invalid map position.")
		var area := selected_tiles(request)
		var owner := actors.find(actor) + 1
		var public_network: bool = request.get("kind") == "build" and request.get("tool") == 0 and request.get("group") in [CityToolIds.Group.ROADS, CityToolIds.Group.POWER]
		for tile: int in area:
			if owners[tile] != owner and not (public_network and protection[tile] == -1):
				return rejected("Buy this land before building here.")
			if tile_versions[tile] > int(request.revision):
				return rejected("This area changed. Review it before building.")
		for path_point: Variant in request.get("path", []):
			if not point_valid(path_point) or (owners[city.index_of(int(path_point[0]), int(path_point[1]))] != owner and not (public_network and protection[city.index_of(int(path_point[0]), int(path_point[1]))] == -1)):
				return rejected("The complete path must stay on your own land.")
		var before := child.city.document.duplicate_document()
		var before_stats := child.statistics.duplicate(true)
		var before_revision := child.revision
		var before_versions := child.tile_versions.duplicate()
		var before_dispatch := child.dispatch_owners.duplicate(true)
		var result := child.command(actor, local)
		if not result.get("ok", false):
			return result
		var changed := changed_tiles(before, child.city.document)
		for tile: int in changed:
			if owners[tile] != owner and not (public_network and protection[tile] == -1):
				child.city = CityState.from_document(before)
				child.engine.city = child.city
				Sc2xCheckpoint.restore(child.controller, before.sc2x_metadata)
				child.statistics = before_stats
				child.revision = before_revision
				child.tile_versions = before_versions
				child.dispatch_owners = before_dispatch
				child.undo_document = null
				return rejected("The complete building or terrain edit must fit on your land.")
		if public_network:
			share_public_network(child, changed)
		statistics[actor] = child.statistics.get(actor, {})
		revision += 1
		for tile: int in changed:
			tile_versions[tile] = revision
		return result
	if request.get("kind") == "undo":
		return rejected("Undo is unavailable after ownership transactions in Shared.")
	if request.get("kind") == "decision" and request.get("accept") == true and (child.engine.pending_interaction == "military_proposal" or child.city.document.sc2x_metadata.extensions.has("multiplayer_military")):
		var land_error := military_land_error(actor)
		if not land_error.is_empty():
			return rejected(land_error)
	var result := child.command(actor, local)
	if result.get("ok", false):
		revision += 1
	return result


func help_disaster(actor: String, request: Dictionary) -> Dictionary:
	if not point_valid(request.get("finish")) or not whole_number(request.get("tool"), 0, 2):
		return rejected("Invalid emergency service target.")
	var target := point(request.finish)
	var owner := owners[city.index_of(target.x, target.y)]
	if owner == 0:
		return rejected("This land has no municipality to assist.")
	var receiver: CoopWorld = municipalities[actors[owner - 1]]
	return deploy_help(actor, receiver, request)


func deploy_help(actor: String, receiver: CoopWorld, request: Dictionary) -> Dictionary:
	var target := point(request.finish)
	var sender: CoopWorld = municipalities[actor]
	if receiver != sender and receiver.engine.active_disaster_type == 0:
		return rejected("Emergency assistance is available during a disaster.")
	var available := DispatchCommand.availability(sender.city)
	if not available.ok:
		return rejected(available.error)
	var tool := int(request.tool)
	var capacity: int = [available.police, available.fire, available.military][tool]
	if sender.engine.active_disaster_type != 0:
		capacity = sender.engine.dispatch_capacity[tool]
	if capacity <= 0:
		return rejected("Your city has no available units of this type.")
	var deployed := 0
	for municipality: CoopWorld in municipalities.values():
		for unit: Dictionary in municipality.dispatch_owners.values():
			if unit.actor == actor.sha256_text() and int(unit.type) == tool:
				deployed += 1
	if deployed >= capacity:
		return rejected("Your available units are already deployed. Recall them before redeploying.")
	var candidate := CityState.copy_for_edit(receiver.city)
	var existing := 0
	var things := candidate.document.find_chunk("XTHG").decoded_payload
	var type: int = [Sc2ThingLayout.Type.POLICE, Sc2ThingLayout.Type.FIRE, Sc2ThingLayout.Type.MILITARY][tool]
	for record in ThingData.count(things):
		if ThingData.read(things, record * ThingData.RECORD_SIZE) == type:
			existing += 1
	var capacity_override := Vector3i.ONE * (existing + 1)
	var edit := DispatchCommand.apply(candidate, CityToolIds.Group.DISPATCH, tool, target, existing, {}, capacity_override)
	if not edit.ok:
		return rejected(edit.error)
	receiver.city = candidate
	receiver.engine.city = candidate
	receiver.revision += 1
	receiver.dispatch_owners[str(edit.thing_index)] = {"actor": actor.sha256_text(), "position": [target.x, target.y], "type": tool}
	revision += 1
	return accepted("Emergency service deployed.")


func selected_tiles(request: Dictionary) -> PackedInt32Array:
	var result := PackedInt32Array()
	var first := point(request.start)
	var last := point(request.finish)
	for x in range(mini(first.x, last.x), maxi(first.x, last.x) + 1):
		for y in range(mini(first.y, last.y), maxi(first.y, last.y) + 1):
			result.append(city.index_of(x, y))
	return result


func land_command(actor: String, request: Dictionary) -> Dictionary:
	var child: CoopWorld = municipalities[actor]
	if request.kind in ["land_withdraw", "land_decline"]:
		var key := str(request.get("offer", ""))
		if not offers.has(key):
			return rejected("This offer is no longer available.")
		var record: Dictionary = offers[key]
		var initiator: String = record.get("initiator", record.get("buyer", record.seller))
		if (request.kind == "land_withdraw" and actor != initiator) or (request.kind == "land_decline" and (actor != record.get("awaiting", record.seller))):
			return rejected("Only the responsible player can change this land entry.")
		finish_land_entry(key, "Withdrawn" if request.kind == "land_withdraw" else "Declined")
		revision += 1
		return accepted("Land entry updated. No money was charged.")
	if request.kind == "land_counter":
		var key := str(request.get("offer", ""))
		if not offers.has(key) or not whole_number(request.get("price"), 0, 2147483647):
			return rejected("This offer is no longer available.")
		var record: Dictionary = offers[key]
		if record.get("reservation", false):
			return rejected("Reserved land has a fixed field price payable to the game.")
		if actor != record.seller and record.get("buyer", actor) != actor:
			return rejected("Only the responsible player can change this land entry.")
		var buyer: String = record.get("buyer", actor)
		if buyer == record.seller:
			var updated := record.duplicate(true)
			updated.price = int(request.price)
			finish_land_entry(key, "Withdrawn")
			offers[str(next_offer)] = updated
			next_offer += 1
			revision += 1
			return accepted("Offer price updated. Previous confirmations are no longer valid.")
		var next := record.duplicate(true)
		next["buyer"] = buyer
		next["initiator"] = actor
		next["awaiting"] = buyer if actor == record.seller else record.seller
		next["price"] = int(request.price)
		finish_land_entry(key, "Withdrawn")
		offers[str(next_offer)] = next
		next_offer += 1
		revision += 1
		return accepted("Counteroffer sent. The other player must confirm the new price.")
	if request.kind == "land_accept":
		var key := str(request.get("offer", ""))
		if not offers.has(key):
			return rejected("This offer is no longer available.")
		var offer: Dictionary = offers[key]
		if offer.has("buyer"):
			if actor != offer.get("awaiting", offer.seller):
				return rejected("Only the owner can approve this purchase request.")
			actor = offer.buyer
			child = municipalities[actor]
		if offer.get("reservation", false):
			return accept_reservation(key, actor)
		if offer.seller == actor:
			return rejected("You already own this land.")
		for tile: int in offer.tiles:
			if owners[tile] != actors.find(offer.seller) + 1:
				return rejected("Land ownership changed; nothing was charged.")
		var rule_error := MultiplayerLandRules.transfer_error(self, offer.seller, actor, offer.tiles)
		if not rule_error.is_empty():
			return rejected(rule_error)
		if child.city.funds() < int(offer.price):
			return rejected("Insufficient funds.")
		var seller: CoopWorld = municipalities[offer.seller]
		if seller.city.funds() + int(offer.price) > 2147483647:
			return rejected("The seller's balance would exceed the supported limit.")
		if seller.engine.active_disaster_type != 0 or child.engine.active_disaster_type != 0:
			return rejected("Finish disaster response before transferring a municipality's land.")
		var transfer := SharedLandTransfer.stage(seller.city, child.city, offer.tiles)
		if not transfer.error.is_empty():
			return rejected(transfer.error)
		child.city = transfer.buyer
		child.engine.city = child.city
		seller.city = transfer.seller
		seller.engine.city = seller.city
		child.city.set_funds(child.city.funds() - int(offer.price))
		seller.city.set_funds(seller.city.funds() + int(offer.price))
		for tile: int in offer.tiles:
			owners[tile] = actors.find(actor) + 1
			protection[tile] = 0
			tile_versions[tile] = revision + 1
		child.undo_document = null
		seller.undo_document = null
		child.revision += 1
		seller.revision += 1
		city = municipalities[host_actor].city
		record_land_spending(actor, "bought", int(offer.price))
		record_land_spending(offer.seller, "sold", int(offer.price))
		finish_land_entry(key, "Sold", actor)
		revision += 1
		return land_success("Land purchased from its owner.", offer.tiles)
	if not point_valid(request.get("start")) or not point_valid(request.get("finish")):
		return rejected("Invalid land selection.")
	var tiles := selected_tiles(request)
	if request.has("tiles"):
		if not request.tiles is Array or request.tiles.is_empty() or request.tiles.size() > owners.size():
			return rejected("Invalid land selection.")
		var unique := {}
		for value: Variant in request.tiles:
			if not whole_number(value, 0, owners.size() - 1) or unique.has(int(value)):
				return rejected("Invalid land selection.")
			unique[int(value)] = true
		tiles = PackedInt32Array(request.tiles)
	if request.kind == "land_buy":
		if not request.get("include_water", false) is bool:
			return rejected("Invalid land selection.")
		tiles = PackedInt32Array(MultiplayerLandRules.purchasable(city, owners, protection, actors.find(actor) + 1, Array(tiles), request.get("include_water", false)))
		if tiles.is_empty():
			return accepted("No purchasable tiles selected. Nothing was charged.")
	if request.kind == "land_request" and owners[tiles[0]] == 0:
		return request_reservation(actor, Array(tiles))
	var expected_owner := 0 if request.kind == "land_buy" else int(owners[tiles[0]]) if request.kind == "land_request" else actors.find(actor) + 1
	if request.kind == "land_request" and (expected_owner == 0 or expected_owner == actors.find(actor) + 1):
		return rejected("Select land belonging to another player to send a purchase request.")
	for tile: int in tiles:
		if owners[tile] != expected_owner:
			return rejected("The entire selection must have the same owner. Nothing was charged.")
	var price := tiles.size() * land_price
	if price > 2147483647:
		return rejected("This land purchase exceeds the supported transaction limit. Select a smaller area.")
	if request.kind == "land_request":
		var seller: String = actors[expected_owner - 1]
		var rule_error := MultiplayerLandRules.transfer_error(self, seller, actor, Array(tiles))
		if not rule_error.is_empty():
			return rejected(rule_error)
		if whole_number(request.get("price"), 0, 2147483647):
			price = int(request.price)
		if not whole_number(request.get("price"), 0, 2147483647):
			return choice_result("Send a purchase request for %d tiles at $%d? The owner must approve before any transfer." % [tiles.size(), price], request,
				[{"label": "Send request", "fields": {"price": price}}])
		if child.city.funds() < price:
			return rejected("Insufficient funds.")
		for record: Dictionary in offers.values():
			if record.get("buyer") == actor and record.tiles == Array(tiles):
				return rejected("This purchase request is already open.")
		if offers.size() >= 256:
			return rejected("Close an existing land entry before creating another.")
		offers[str(next_offer)] = {"seller": seller, "buyer": actor, "tiles": Array(tiles), "price": price}
		next_offer += 1
		revision += 1
		return accepted("Purchase request sent. The owner can review it in Land offers.")
	if request.kind == "land_offer":
		if offers.size() >= 256:
			return rejected("Close an existing land entry before creating another.")
		if not whole_number(request.get("price"), 0, 2147483647):
			return rejected("Invalid offer price.")
		for tile: int in tiles:
			if protection[tile] not in [0, actors.find(actor) + 1]:
				return rejected("Another player's reservation and public corridors cannot be traded.")
		price = int(request.price)
		offers[str(next_offer)] = {"seller": actor, "tiles": Array(tiles), "price": price}
		next_offer += 1
		revision += 1
		return accepted("Land offer published. Another player can accept it.")
	var allowance := mini(int(land_allowance.get(actor, 0)), price)
	var payment := price - allowance
	if child.city.funds() < payment:
		return rejected("Insufficient funds.")
	record_land_spending(actor, "bought", payment)
	land_allowance[actor] = int(land_allowance.get(actor, 0)) - allowance
	child.city.set_funds(child.city.funds() - payment)
	for tile: int in tiles:
		owners[tile] = actors.find(actor) + 1
		tile_versions[tile] = revision + 1
	revision += 1
	return land_success("Land purchased.", Array(tiles))

func land_success(message: String, tiles: Array) -> Dictionary:
	var center := Vector2.ZERO
	for tile: int in tiles:
		center += Vector2(tile / city.map_size, tile % city.map_size)
	center /= maxi(1, tiles.size())
	return accepted(message).merged({"sounds": [ToolSoundRules.SOUND_ZONE], "sound_point": [roundi(center.x), roundi(center.y)]})


func reservation_error(seller: String, buyer: String, tiles: Array) -> String:
	var reservation := actors.find(seller) + 1
	if reservation <= 0 or seller == buyer or not municipalities.has(buyer):
		return "Select another player's reserved land."
	for tile: int in tiles:
		if owners[tile] != 0 or protection[tile] != reservation:
			return "The reservation changed; nothing was charged."
	if MultiplayerLandRules.connected(tiles, owners, actors.find(buyer) + 1, city.map_size).size() != tiles.size():
		return "This parcel does not connect to the buyer's city."
	return ""


func request_reservation(buyer: String, tiles: Array) -> Dictionary:
	var index := int(protection[tiles[0]])
	if index <= 0 or index > actors.size():
		return rejected("Select another player's reserved land.")
	var seller: String = actors[index - 1]
	var error := reservation_error(seller, buyer, tiles)
	if not error.is_empty():
		return rejected(error)
	var price := tiles.size() * land_price
	if price > 2147483647 or municipalities[buyer].city.funds() < price:
		return rejected("Insufficient funds.")
	for record: Dictionary in offers.values():
		if record.get("buyer") == buyer and record.tiles == tiles:
			return rejected("This purchase request is already open.")
	if offers.size() >= 256:
		return rejected("Close an existing land entry before creating another.")
	offers[str(next_offer)] = {"seller": seller, "buyer": buyer, "tiles": tiles.duplicate(), "price": price, "reservation": true}
	next_offer += 1
	revision += 1
	return accepted("Reservation release requested. The buyer pays the game only after approval.")


func accept_reservation(key: String, buyer: String) -> Dictionary:
	var offer: Dictionary = offers[key]
	var error := reservation_error(offer.seller, buyer, offer.tiles)
	if not error.is_empty():
		return rejected(error)
	# Price and consent cannot be changed by a client-supplied amount or counteroffer.
	var price: int = offer.tiles.size() * land_price
	if price != int(offer.price):
		return rejected("The field price changed; send a new request.")
	var child: CoopWorld = municipalities[buyer]
	if child.city.funds() < price:
		return rejected("Insufficient funds.")
	child.city.set_funds(child.city.funds() - price)
	for tile: int in offer.tiles:
		owners[tile] = actors.find(buyer) + 1
		protection[tile] = 0
		tile_versions[tile] = revision + 1
	child.undo_document = null
	child.revision += 1
	record_land_spending(buyer, "bought", price)
	finish_land_entry(key, "Sold", buyer)
	revision += 1
	return land_success("Reservation released and land purchased. Payment went to the game.", offer.tiles)


func snapshot_for(actor: String, live := false) -> Dictionary:
	var cache_key := actor + (":live" if live else ":archive")
	if snapshot_cache.get(cache_key, {}).get("revision", -1) == revision:
		return snapshot_cache[cache_key].duplicate()
	var child: CoopWorld = municipalities.get(actor, municipalities[host_actor])
	var result := child.snapshot_status()
	Sc2xCheckpoint.capture(child.controller, child.city.document.sc2x_metadata)
	var document := MultiplayerDocument.view_copy(child.city.document) if live else child.city.document.duplicate_document()
	if composed_revision != revision:
		var ownership_changed := owners != composition_owners or protection != composition_protection
		for id: String in TILE_CHUNKS:
			var sources: Array = []
			for player: String in actors:
				sources.append(municipalities[player].city.document.find_chunk(id).decoded_payload)
			if not ownership_changed and sources == composition_sources.get(id) and composed_chunks.has(id):
				continue
			var previous_sources: Array = composition_sources.get(id, [])
			var incremental := not ownership_changed and composed_chunks.has(id) and previous_sources.size() == sources.size()
			var data: PackedByteArray = composed_chunks[id].duplicate() if incremental else template.find_chunk(id).decoded_payload.duplicate()
			var stride: int = TILE_CHUNKS[id]
			for block in range(0, owners.size(), 512):
				var end := mini(block + 512, owners.size())
				var dirty := not incremental
				if incremental:
					for index in sources.size():
						if sources[index].slice(block * stride, end * stride) != previous_sources[index].slice(block * stride, end * stride):
							dirty = true
							break
				if not dirty:
					continue
				for tile in range(block, end):
					var owner := owners[tile] - 1
					if protection[tile] == -1:
						owner = 0
					if owner >= 0:
						for byte in stride:
							data[tile * stride + byte] = sources[owner][tile * stride + byte]
			composed_chunks[id] = data
			# Simulation may mutate a packed buffer in place. Keep an immutable
			# comparison copy so an unchanged revision never hides a changed plane.
			composition_sources[id] = sources.map(func(data: PackedByteArray) -> PackedByteArray: return data.duplicate())
		composition_owners = owners.duplicate()
		composition_protection = protection.duplicate()
		var signature: Array = [hash(owners)]
		for player: String in actors:
			for id in ["XTXT", "XTHG", "XMIC", "XLAB"]:
				signature.append(hash(municipalities[player].city.document.find_chunk(id).decoded_payload))
		if signature != record_signature:
			record_signature = signature
			record_cache.clear()
		composed_revision = revision
	for id: String in composed_chunks:
		document.find_chunk(id).expected_decoded_size = composed_chunks[id].size()
		document.find_chunk(id).set_decoded_payload(composed_chunks[id])
	if not record_cache.has(actor):
		compose_records(document, actor)
		var records := {}
		for id in ["XTXT", "XTHG", "XMIC", "XLAB"]:
			records[id] = document.find_chunk(id).decoded_payload
		record_cache[actor] = records
	else:
		for id: String in record_cache[actor]:
			document.find_chunk(id).expected_decoded_size = record_cache[actor][id].size()
			document.find_chunk(id).set_decoded_payload(record_cache[actor][id])
	if live:
		if not live_documents.has(actor):
			live_documents[actor] = MultiplayerDocument.new()
		var common_ids: Array = TILE_CHUNKS.keys().filter(func(id: String) -> bool: return id != "XTXT")
		result.merge(live_documents[actor].capture(document, shared_live_document, common_ids))
	else:
		if not municipal_compression.has(actor):
			municipal_compression[actor] = {}
		var encoded := Sc2xDocument.encode(document, municipal_compression[actor])
		if not encoded.ok:
			return {"error": encoded.error}
		result.city = Marshalls.raw_to_base64(encoded.data)
	result.revision = revision
	result["mode"] = "shared"
	result["land_price"] = land_price
	result["land_allowance"] = int(land_allowance.get(actor, 0))
	result["owners"] = Array(owners)
	result["protection"] = Array(protection)
	result["owner_ids"] = actors.map(func(value: String) -> String: return value.sha256_text())
	result["dispatch_owners"] = {}
	result["disasters"] = []
	for owner: String in actors:
		var municipality: CoopWorld = municipalities[owner]
		for key: String in municipality.dispatch_owners:
			result.dispatch_owners[owner.sha256_text() + key] = municipality.dispatch_owners[key]
		if municipality.engine.active_disaster_type != 0:
			var location := owners.find(actors.find(owner) + 1)
			for tile in owners.size():
				if owners[tile] == actors.find(owner) + 1 and OverlayData.marker_at(municipality.city.text_overlays, tile) != 0:
					location = tile
					break
			result.disasters.append({"owner": owner.sha256_text(), "type": municipality.engine.active_disaster_type,
				"point": [location / city.map_size, location % city.map_size]})
	snapshot_cache[cache_key] = result.duplicate()
	return result


func compose_records(document: Sc2File, viewing_actor: String) -> void:
	# Moving records change often; tile references only depend on overlay bytes
	# and record counts. Reuse the remapped planes while those inputs are stable.
	var overlay_key: Array = [owners.duplicate(), actors.duplicate()]
	for actor: String in actors:
		var source: Sc2File = municipalities[actor].city.document
		overlay_key.append(source.find_chunk("XTXT").decoded_payload.duplicate())
		overlay_key.append(source.find_chunk("XLAB").decoded_payload.duplicate())
		overlay_key.append(source.find_chunk("XMIC").decoded_payload.size())
		overlay_key.append(source.find_chunk("XTHG").decoded_payload.size())
	var cached: Dictionary = record_overlay_cache.get(viewing_actor, {})
	var reuse: bool = cached.get("key") == overlay_key
	var text := document.find_chunk("XTXT").decoded_payload.duplicate()
	var things := document.find_chunk("XTHG").decoded_payload.duplicate()
	var facilities := document.find_chunk("XMIC").decoded_payload.duplicate()
	var labels := document.find_chunk("XLAB").decoded_payload.duplicate()
	var next_sign := maxi(Sc2OverlayLayout.EXTRA_SIGN, labels.size() / Sc2LabelLayout.RECORD_SIZE)
	for actor: String in actors:
		if actor == viewing_actor:
			continue
		var child: CoopWorld = municipalities[actor]
		var source_text := child.city.text_overlays
		var source_things := child.city.document.find_chunk("XTHG").decoded_payload
		var source_facilities := child.city.document.find_chunk("XMIC").decoded_payload
		var source_labels := child.city.document.find_chunk("XLAB").decoded_payload
		var thing_base := ThingData.count(things)
		var facility_base := facilities.size() / Sc2MicrosimLayout.RECORD_SIZE
		var existing_low := thing_base * ThingData.RECORD_SIZE
		var source_low := ThingData.count(source_things) * ThingData.RECORD_SIZE
		var expanded := things.slice(0, existing_low)
		expanded.append_array(source_things.slice(0, source_low))
		var high := things.slice(existing_low) if ThingData.split_planes(things) else PackedByteArray()
		high.resize(existing_low)
		expanded.append_array(high)
		high = source_things.slice(source_low) if ThingData.split_planes(source_things) else PackedByteArray()
		high.resize(source_low)
		expanded.append_array(high)
		for record in ThingData.count(source_things):
			var label_offset := (record + thing_base) * ThingData.RECORD_SIZE + Sc2ThingLayout.Field.LABEL
			var link := ThingData.read(expanded, label_offset)
			if OverlayData.is_thing(link):
				ThingData.write(expanded, label_offset, OverlayData.thing_id(OverlayData.thing_record(link) + thing_base))
			elif OverlayData.is_facility(link):
				ThingData.write(expanded, label_offset, OverlayData.facility_id(OverlayData.facility_record(link) + facility_base))
		things = expanded
		facilities.append_array(source_facilities)
		if reuse:
			continue
		var signs := {}
		for tile in owners.size():
			if owners[tile] != actors.find(actor) + 1:
				continue
			var marker := OverlayData.marker_at(source_text, tile)
			var facility := OverlayData.facility_at(source_text, tile)
			var object := OverlayData.object(source_text, tile) if OverlayData.is_layered(source_text) else OverlayData.read(source_text, tile)
			OverlayData.set_marker_at(text, tile, marker if not OverlayData.is_facility(marker) and not OverlayData.is_thing(marker) and not OverlayData.is_sign(marker) else 0)
			if OverlayData.is_layered(text):
				OverlayData.set_facility(text, tile, 0)
				OverlayData.set_object(text, tile, 0)
			if OverlayData.is_facility(facility):
				OverlayData.write(text, tile, OverlayData.facility_id(OverlayData.facility_record(facility) + facility_base))
			if OverlayData.is_thing(object):
				OverlayData.write(text, tile, OverlayData.thing_id(OverlayData.thing_record(object) + thing_base))
			var sign_id := OverlayData.read(source_text, tile)
			if OverlayData.is_sign(sign_id):
				if not signs.has(sign_id):
					signs[sign_id] = next_sign
					labels.resize((next_sign + 1) * Sc2LabelLayout.RECORD_SIZE)
					for byte in Sc2LabelLayout.RECORD_SIZE:
						labels[next_sign * Sc2LabelLayout.RECORD_SIZE + byte] = source_labels[sign_id * Sc2LabelLayout.RECORD_SIZE + byte]
					next_sign += 1
				OverlayData.write(text, tile, signs[sign_id])
	if reuse:
		text = cached.text
		labels = cached.labels
	else:
		record_overlay_cache[viewing_actor] = {"key": overlay_key, "text": text.duplicate(), "labels": labels.duplicate()}
	for pair in [["XTXT", text], ["XTHG", things], ["XMIC", facilities], ["XLAB", labels]]:
		var chunk := document.find_chunk(pair[0])
		chunk.expected_decoded_size = pair[1].size()
		chunk.set_decoded_payload(pair[1])


func snapshot(_force_checkpoint := false, live := false) -> Dictionary:
	return snapshot_for(host_actor, live) if not host_actor.is_empty() else super.snapshot(false, live)


func saved_shared() -> Dictionary:
	var cities := {}
	for actor: String in actors:
		var child: CoopWorld = municipalities[actor]
		var checkpoint_error := Sc2xCheckpoint.save_error(child.controller)
		if not checkpoint_error.is_empty():
			return {"error": checkpoint_error}
		cities[actor] = {"state": child.snapshot(true), "statistics": child.statistics,
			"dispatch": Array(child.dispatch_cycles), "dispatch_owners": child.dispatch_owners,
			"dispatch_initialized": child.dispatch_initialized, "dispatch_points": child.saved_dispatch_points()}
	return {"protection": Array(protection), "owners": Array(owners), "actors": actors, "host": host_actor,
		"land_price": land_price, "starter_tiles": starter_tiles, "land_allowance": land_allowance,
		"cities": cities, "offers": offers, "next_offer": next_offer,
		"land_history": land_history, "land_statistics": land_statistics,
		"template": Marshalls.raw_to_base64(Sc2xDocument.encode(template).data)}


func restore_shared(data: Dictionary) -> String:
	if not data.get("actors") is Array:
		return "Invalid shared municipalities."
	if not whole_number(data.get("land_price", LAND_PRICE), 0, 1000) or not whole_number(data.get("starter_tiles", 0), 0, 1024) or not data.get("land_allowance", {}) is Dictionary:
		return "Invalid saved land purchase rules."
	for actor: Variant in data.get("land_allowance", {}):
		if not data.get("actors", []).has(actor) or not whole_number(data.land_allowance[actor], 0, 1024000):
			return "Invalid saved land purchase rules."
	if not data.get("actors") is Array or data.actors.is_empty() or data.actors.size() > 8 or not data.get("cities") is Dictionary or not data.get("owners") is Array or data.owners.size() != owners.size():
		return "Invalid shared municipalities."
	if not data.get("host") is String or not data.actors.has(data.host):
		return "Invalid shared host."
	var restored := {}
	for actor: Variant in data.actors:
		if not actor is String or actor.length() != 48 or restored.has(actor) or not data.cities.get(actor) is Dictionary:
			return "Invalid municipality identity."
		var record: Dictionary = data.cities[actor]
		if not record.get("state") is Dictionary or not record.state.get("city") is String:
			return "Missing municipality city."
		if not record.get("statistics") is Dictionary or not record.get("dispatch_owners") is Dictionary or not record.get("dispatch") is Array or record.dispatch.size() != 3:
			return "Invalid municipality service state."
		for cycle: Variant in record.dispatch:
			if not whole_number(cycle, 0, 2147483647):
				return "Invalid municipality dispatch cycle."
		var document := Sc2File.new()
		var child := CoopWorld.new()
		if not document.parse(Marshalls.base64_to_raw(record.state.city)) or document.map_size != city.map_size or not child.open(document):
			return "Invalid municipality checkpoint."
		child.statistics = record.get("statistics", {})
		child.dispatch_owners = record.get("dispatch_owners", {})
		child.dispatch_cycles = PackedInt32Array(record.get("dispatch", [0, 0, 0]))
		var dispatch := CoopWorld.read_dispatch_points(record.get("dispatch_points", []), city.map_size)
		if not dispatch.error.is_empty():
			return dispatch.error
		child.dispatch_slot_points = dispatch.points
		child.dispatch_initialized = record.get("dispatch_initialized") == true
		restored[actor] = child
	for owner: Variant in data.owners:
		if not whole_number(owner, 0, restored.size()):
			return "Invalid land owner."
	var restored_template := Sc2File.new()
	if not data.get("template") is String or not restored_template.parse(Marshalls.base64_to_raw(data.template)) or restored_template.map_size != city.map_size:
		return "Invalid shared terrain."
	if not data.get("offers") is Dictionary or not whole_number(data.get("next_offer"), 1, 2147483647):
		return "Invalid land offers."
	for key: Variant in data.offers:
		var offer: Variant = data.offers[key]
		if not key is String or not offer is Dictionary or not restored.has(offer.get("seller")) or not whole_number(offer.get("price"), 0, 2147483647) or not offer.get("tiles") is Array or offer.tiles.is_empty() or offer.tiles.size() > owners.size():
			return "Invalid land offer."
		if offer.has("buyer") and (not restored.has(offer.buyer) or offer.buyer == offer.seller):
			return "Invalid land request buyer."
		if not offer.get("reservation", false) is bool:
			return "Invalid land reservation request."
		if offer.get("reservation", false) and (not offer.has("buyer") or offer.get("awaiting", offer.seller) != offer.seller or offer.get("initiator", offer.buyer) != offer.buyer or int(offer.price) != offer.tiles.size() * int(data.get("land_price", LAND_PRICE))):
			return "Invalid land reservation request."
		for field in ["initiator", "awaiting"]:
			if offer.has(field) and offer[field] not in [offer.seller, offer.get("buyer", "")]:
				return "Invalid land request buyer."
		var unique := {}
		for tile: Variant in offer.tiles:
			if not whole_number(tile, 0, owners.size() - 1) or unique.has(int(tile)):
				return "Invalid land offer area."
			unique[int(tile)] = true
	if not data.get("land_history", []) is Array or data.get("land_history", []).size() > 128 or not data.get("land_statistics", {}) is Dictionary:
		return "Invalid land history."
	for entry: Variant in data.get("land_history", []):
		if not entry is Dictionary or not entry.get("id") is String or not restored.has(entry.get("seller")) or not entry.get("status") in ["Sold", "Withdrawn", "Declined", "Ownership changed"] or not whole_number(entry.get("price"), 0, 2147483647) or not entry.get("tiles") is Array or entry.tiles.is_empty() or entry.tiles.size() > owners.size():
			return "Invalid land history."
		if entry.has("buyer") and not restored.has(entry.buyer):
			return "Invalid land request buyer."
		for tile: Variant in entry.tiles:
			if not whole_number(tile, 0, owners.size() - 1):
				return "Invalid land history."
	for actor: Variant in data.get("land_statistics", {}):
		var counters: Variant = data.land_statistics[actor]
		if not restored.has(actor) or not counters is Dictionary:
			return "Invalid land statistics."
		for field in ["bought", "sold"]:
			if counters.get(field) != null and not whole_number(counters[field], 0, 9007199254740991):
				return "Invalid land statistics."
	land_history = data.get("land_history", []).duplicate(true)
	land_statistics = data.get("land_statistics", {}).duplicate(true)
	land_price = int(data.get("land_price", LAND_PRICE))
	starter_tiles = int(data.get("starter_tiles", 0))
	land_allowance = data.get("land_allowance", {}).duplicate()
	municipalities = restored
	actors.assign(data.actors)
	var saved_protection: Variant = data.get("protection", [])
	if not saved_protection is Array or (not saved_protection.is_empty() and saved_protection.size() != owners.size()):
		return "Invalid land protection map."
	for value: Variant in saved_protection:
		if not whole_number(value, -1, data.actors.size()):
			return "Invalid land protection map."
	owners = PackedInt32Array(data.owners)
	protection.resize(owners.size())
	protection.fill(0)
	if not saved_protection.is_empty():
		protection = PackedInt32Array(saved_protection)
	# Older starts marked entire sector seams as public corridors. Empty seams
	# must not imprison a city in its starting sector. Built shared infrastructure
	# remains public; private ownership and other players' reservations are intact.
	restored_empty_corridors.clear()
	for tile in protection.size():
		if protection[tile] != -1 or owners[tile] != 0:
			continue
		var developed := false
		for child: CoopWorld in municipalities.values():
			developed = developed or child.city.buildings[tile] > 13 or child.city.zones[tile] != 0 or child.city.underground[tile] != 0
		if not developed:
			protection[tile] = 0
			restored_empty_corridors[tile] = true
	host_actor = data.host
	template = restored_template
	offers = data.get("offers", {})
	next_offer = int(data.get("next_offer", 1))
	city = municipalities[host_actor].city
	engine = municipalities[host_actor].engine
	controller = municipalities[host_actor].controller
	statistics.clear()
	for actor: String in actors:
		statistics[actor] = municipalities[actor].statistics.get(actor, {"builds": 0, "spent": 0})
	snapshot_cache.clear()
	return ""


static func remove_dispatch(things: PackedByteArray, text: PackedByteArray, record: int) -> void:
	var offset := record * ThingData.RECORD_SIZE
	var x := ThingData.read(things, offset + Sc2ThingLayout.Field.X)
	var y := ThingData.read(things, offset + Sc2ThingLayout.Field.Y)
	var edge := int(sqrt(OverlayData.count(text)))
	if x >= 0 and y >= 0 and x < edge and y < edge:
		OverlayData.lift_object(text, things, record, x * edge + y, 0)
	ThingData.write(things, offset, 0)


func military_land_error(actor: String) -> String:
	var child: CoopWorld = municipalities[actor]
	# Preview with copied city/random state: a civic proposal must obey the same
	# ownership rule as a player's building, without consuming a random draw.
	var candidate := CityState.copy_for_edit(child.city)
	var random := GameLcgRandom.new(child.engine.game_random.state)
	var proposal := MilitaryProposalPhase.resolve(candidate, true, random, false, int(child.city.document.sc2x_metadata.extensions.get("multiplayer_military", child.engine.forced_military_base_type)))
	if not proposal.ok:
		return proposal.error
	for tile: int in changed_tiles(child.city.document, candidate.document):
		if owners[tile] != actors.find(actor) + 1:
			return "The proposed military base extends outside your land. Buy its land first or decline the proposal."
	return ""


func record_land_spending(actor: String, field: String, amount: int) -> void:
	# Missing old counters remain unavailable: do not invent earlier spending.
	if land_statistics.get(actor, {}).get(field) != null:
		land_statistics[actor][field] += amount


func finish_land_entry(key: String, status: String, buyer := "") -> void:
	var record: Dictionary = offers[key].duplicate(true)
	record["id"] = key
	record["status"] = status
	if not buyer.is_empty():
		record["buyer"] = buyer
	land_history.append(record)
	if land_history.size() > 128:
		land_history.pop_front()
	offers.erase(key)
	# Overlapping offers must never survive a transfer with obsolete ownership.
	if status == "Sold":
		for other: String in offers.keys():
			for tile: int in offers[other].tiles:
				var entry: Dictionary = offers[other]
				var seller_index := actors.find(entry.seller) + 1
				var changed := (owners[tile] != 0 or protection[tile] != seller_index) if entry.get("reservation", false) else owners[tile] != seller_index
				if changed:
					finish_land_entry(other, "Ownership changed")
					break

# Common road/wire corridors stay neutral. Players pay for their own additions;
# nobody can bulldoze, zone, sell, or terraform these shared access routes.
func share_public_network(source: CoopWorld, changed: PackedInt32Array) -> void:
	var public_tiles: Array[int] = []
	for tile: int in changed:
		if protection[tile] == -1:
			public_tiles.append(tile)
	if public_tiles.is_empty():
		return
	var destinations: Array[Sc2File] = []
	for child: CoopWorld in municipalities.values():
		if child != source:
			destinations.append(child.city.document)
	for document: Sc2File in destinations:
		for id: String in TILE_CHUNKS:
			var payload := document.find_chunk(id).decoded_payload.duplicate()
			var input := source.city.document.find_chunk(id).decoded_payload
			var stride: int = TILE_CHUNKS[id]
			for tile: int in public_tiles:
				for byte in stride:
					payload[tile * stride + byte] = input[tile * stride + byte]
			document.find_chunk(id).set_decoded_payload(payload)
	for child: CoopWorld in municipalities.values():
		if child == source:
			continue
		child.city.resync_mirrors(PackedStringArray(TILE_CHUNKS.keys()))
		child.revision += 1
		child.undo_document = null
	snapshot_cache.clear()
