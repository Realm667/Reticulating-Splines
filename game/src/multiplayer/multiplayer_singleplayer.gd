class_name MultiplayerSingleplayer
extends RefCounted
## Explicit copy conversion. Source archives and multiplayer identities stay private.

static func metadata(document: Sc2File) -> Dictionary:
	var bytes: PackedByteArray = document.sc2x_extra_entries.get("multiplayer.json", PackedByteArray())
	if bytes.is_empty():
		return {}
	var parser := JSON.new()
	return parser.data if parser.parse(bytes.get_string_from_utf8()) == OK and parser.data is Dictionary else {}

static func clean(document: Sc2File) -> Sc2File:
	var copy := document.duplicate_document()
	copy.sc2x_extra_entries.erase("multiplayer.json")
	for key: String in copy.sc2x_metadata.extensions.keys():
		if key.begins_with("multiplayer_"):
			copy.sc2x_metadata.extensions.erase(key)
	copy.source_path = ""
	return copy

static func convert(document: Sc2File, actor := "") -> Dictionary:
	var data := metadata(document)
	if data.is_empty():
		return {"error": "Invalid multiplayer save."}
	if not data.has("shared"):
		CityActivityIdentity.ensure(document, ("rs-activity-city-v1:" + str(data.get("session", "")) + ":coop").sha256_text())
		return {"error": "", "document": clean(document)}
	if not data.shared is Dictionary:
		return {"error": "Invalid multiplayer save."}
	var world: SharedWorld = RegionWorld.new() if data.shared.get("mode") == "region" else SharedWorld.new()
	if not world.open(document):
		return {"error": world.error}
	var error := world.restore_shared(data.shared)
	if not error.is_empty():
		return {"error": error}
	CityActivityIdentity.ensure_world(world, str(data.get("session", "")), int(data.get("starts", {}).get("round", 1)))
	return from_world(world, actor if not actor.is_empty() else world.host_actor)

static func from_world(world: CoopWorld, actor: String) -> Dictionary:
	if not world is SharedWorld:
		var copy := clean(world.city.document)
		Sc2xCheckpoint.capture(world.controller, copy.sc2x_metadata)
		return {"error": "", "document": copy}
	if not world.municipalities.has(actor):
		return {"error": "Choose a city from this save."}
	if world is RegionWorld:
		var own: CoopWorld = world.municipalities[actor]
		var copy := clean(own.city.document)
		Sc2xCheckpoint.capture(own.controller, copy.sc2x_metadata)
		if world.campaign != null:
			world.sync_campaign()
			var source: RegionCampaign = world.campaign
			var retained := RegionCampaign.new()
			retained.edge = source.edge
			retained.seed_value = source.seed_value
			retained.origin = source.origin
			retained.template = RegionCampaign.clean_copy(source.template)
			retained.name = copy.city_name()
			retained.current_day = source.current_day
			retained.first_cells[ApplicationRegions.LOCAL_OWNER] = source.first_cells[actor]
			retained.active_cells[ApplicationRegions.LOCAL_OWNER] = source.active_cells[actor]
			for id: String in source.documents:
				if source.owners[id] != actor:
					continue
				var document := copy if id == source.active_cells[actor] else clean(RegionCampaign.clean_copy(source.documents[id]))
				if world.city_worlds.has(id):
					Sc2xCheckpoint.capture(world.city_worlds[id].controller, document.sc2x_metadata)
				retained.documents[id] = document
				retained.owners[id] = ApplicationRegions.LOCAL_OWNER
				retained.acquired[id] = source.acquired[id]
				retained.settled[id] = source.settled[id]
			var error := retained.pack(copy)
			if not error.is_empty():
				return {"error": error}
		return {"error": "", "document": copy}
	# snapshot_for composes each tile/record once according to its owner. It does
	# not add populations of multiple copies of the same physical terrain.
	var metadata_before := {}
	for id: String in world.actors:
		metadata_before[id] = world.municipalities[id].city.document.sc2x_metadata.copy()
	var snapshot: Dictionary = world.snapshot_for(world.host_actor)
	for id: String in world.actors:
		world.municipalities[id].city.document.sc2x_metadata = metadata_before[id]
	var merged := Sc2File.new()
	if not snapshot.has("city") or not merged.parse(Marshalls.base64_to_raw(snapshot.city)):
		return {"error": "Cannot compose the shared city."}
	merged = clean(merged)
	# Merging several municipalities creates a distinct city. Repeating the same
	# conversion retains a stable identity without borrowing the host city's ID.
	var identities := PackedStringArray()
	for id: String in world.actors:
		identities.append(CityActivityIdentity.ensure(world.municipalities[id].city.document))
	identities.sort()
	CityActivityIdentity.replace(merged, ("rs-merged-city-v1:" + ":".join(identities)).sha256_text())
	var cash := 0
	var rates: Array[int] = []
	for child: CoopWorld in world.municipalities.values():
		cash += child.city.funds()
		var misc := child.city.document.find_chunk("MISC").decoded_payload
		var count := mini(BondCommand.MAX_BONDS, BinaryData.read_u32_be(misc, Sc2MiscLayout.BONDS))
		for index in count:
			rates.append(BinaryData.read_u32_be(misc, Sc2MiscLayout.BOND_RATES + index * 4))
	# The ordinary single-player format has 50 bank bond slots. Settle overflow
	# at face value, retaining net assets, rather than dropping external debt.
	cash -= maxi(0, rates.size() - BondCommand.MAX_BONDS) * BondCommand.BOND_VALUE
	if cash < -2147483648 or cash > 2147483647:
		return {"error": "Combined funds exceed the single-player limit."}
	var chunk := merged.find_chunk("MISC")
	var misc := chunk.decoded_payload.duplicate()
	BinaryData.write_u32_be(misc, Sc2MiscLayout.FUNDS, cash & 0xffffffff)
	BinaryData.write_u32_be(misc, Sc2MiscLayout.BONDS, mini(rates.size(), BondCommand.MAX_BONDS))
	for index in BondCommand.MAX_BONDS:
		BinaryData.write_u32_be(misc, Sc2MiscLayout.BOND_RATES + index * 4, rates[index] if index < rates.size() else 0)
	chunk.set_decoded_payload(misc, true)
	# Rebuild derived city-wide totals from the merged physical map on first
	# single-player load. Host tax/funding/ordinance settings remain authoritative.
	merged.sc2x_metadata.phase_state.clear()
	return {"error": "", "document": merged}
