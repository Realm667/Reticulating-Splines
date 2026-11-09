class_name SharedLandTransfer
extends RefCounted
## Stage both sides before transferring a complete parcel, including its facilities.


static func stage(seller: CityState, buyer: CityState, tiles: Array) -> Dictionary:
	var selected := {}
	for tile: int in tiles:
		selected[tile] = true
	for tile: int in tiles:
		@warning_ignore("integer_division")
		var point := Vector2i(tile / seller.map_size, tile % seller.map_size)
		var building := seller.buildings[tile]
		var area := NativeCityTools.building_area(building)
		if area > 1:
			var site := NativeCityTools.find_building_site(seller.buildings, seller.zones, point, building, area, seller.compass_rotation(), seller.map_size)
			for x in range(site.position.x, site.end.x):
				for y in range(site.position.y, site.end.y):
					if not selected.has(seller.index_of(x, y)):
						return {"error": "The parcel must include each building's complete footprint."}
		var object := OverlayData.object(seller.text_overlays, tile)
		if OverlayData.is_thing(object):
			return {"error": "Wait for moving objects to leave this parcel or recall its emergency units."}
	var from := seller.document.duplicate_document()
	var to := buyer.document.duplicate_document()
	for id: String in SharedWorld.TILE_CHUNKS:
		var source := from.find_chunk(id).decoded_payload.duplicate()
		var target := to.find_chunk(id).decoded_payload.duplicate()
		var stride: int = SharedWorld.TILE_CHUNKS[id]
		for tile: int in tiles:
			for byte in stride:
				target[tile * stride + byte] = source[tile * stride + byte]
			if id in ["XZON", "XUND"] or (id == "XBLD" and source[tile] > 13):
				source[tile] = 0
		from.find_chunk(id).set_decoded_payload(source)
		to.find_chunk(id).set_decoded_payload(target)
	var source_text := from.find_chunk("XTXT").decoded_payload.duplicate()
	var target_text := to.find_chunk("XTXT").decoded_payload.duplicate()
	var source_facilities := from.find_chunk("XMIC").decoded_payload.duplicate()
	var target_facilities := to.find_chunk("XMIC").decoded_payload.duplicate()
	var source_labels := from.find_chunk("XLAB").decoded_payload
	var target_labels := to.find_chunk("XLAB").decoded_payload.duplicate()
	var facilities := {}
	var signs := {}
	for tile: int in tiles:
		var marker := OverlayData.marker_at(source_text, tile)
		var facility := OverlayData.facility_at(source_text, tile)
		OverlayData.set_marker_at(target_text, tile, marker)
		OverlayData.set_facility(target_text, tile, 0)
		OverlayData.set_object(target_text, tile, 0)
		if OverlayData.is_facility(facility):
			var record := OverlayData.facility_record(facility)
			if not facilities.has(record):
				@warning_ignore("integer_division")
				var next := target_facilities.size() / Sc2MicrosimLayout.RECORD_SIZE
				facilities[record] = next
				target_facilities.append_array(source_facilities.slice(record * Sc2MicrosimLayout.RECORD_SIZE, (record + 1) * Sc2MicrosimLayout.RECORD_SIZE))
				for byte in Sc2MicrosimLayout.RECORD_SIZE:
					source_facilities[record * Sc2MicrosimLayout.RECORD_SIZE + byte] = 0
			OverlayData.set_facility(target_text, tile, OverlayData.facility_id(facilities[record]))
		var sign_id := OverlayData.read(source_text, tile)
		if OverlayData.is_sign(sign_id):
			if not signs.has(sign_id):
				@warning_ignore("integer_division")
				var next := maxi(Sc2OverlayLayout.EXTRA_SIGN, target_labels.size() / Sc2LabelLayout.RECORD_SIZE)
				if next >= Sc2OverlayLayout.EXTRA_THING:
					return {"error": "The buyer's sign table is full."}
				signs[sign_id] = next
				target_labels.resize((next + 1) * Sc2LabelLayout.RECORD_SIZE)
				for byte in Sc2LabelLayout.RECORD_SIZE:
					target_labels[next * Sc2LabelLayout.RECORD_SIZE + byte] = source_labels[sign_id * Sc2LabelLayout.RECORD_SIZE + byte]
			OverlayData.write(target_text, tile, signs[sign_id])
		OverlayData.set_marker_at(source_text, tile, 0)
		OverlayData.set_facility(source_text, tile, 0)
		OverlayData.set_object(source_text, tile, 0)
	for entry in [[from, "XTXT", source_text], [to, "XTXT", target_text], [from, "XMIC", source_facilities], [to, "XMIC", target_facilities], [to, "XLAB", target_labels]]:
		var chunk: Sc2Chunk = entry[0].find_chunk(entry[1])
		chunk.expected_decoded_size = entry[2].size()
		chunk.set_decoded_payload(entry[2])
	var upgrade_error := transfer_upgrades(from, to, selected, facilities)
	if not upgrade_error.is_empty():
		return {"error": upgrade_error}
	var from_city := CityState.from_document(from)
	var to_city := CityState.from_document(to)
	# Counts are immediately available to budget/dispatch, before the next census.
	for municipality: CityState in [from_city, to_city]:
		var counts := PackedInt32Array()
		counts.resize(256)
		for building: int in municipality.buildings:
			counts[building] += 1
		for building in counts.size():
			municipality.document.set_misc_u32(Sc2MiscLayout.TILE_COUNTS + building * 4, counts[building])
	return {"error": "", "seller": from_city, "buyer": to_city}


static func transfer_upgrades(source: Sc2File, target: Sc2File, selected: Dictionary, facilities: Dictionary) -> String:
	var from := source.find_chunk("XUPG")
	if from == null:
		return ""
	var to := target.find_chunk("XUPG")
	var kept := from.decoded_payload.slice(0, 24)
	var received := to.decoded_payload.duplicate() if to != null else PackedByteArray()
	for offset in range(24, from.decoded_payload.size(), 40):
		var record := from.decoded_payload.slice(offset, offset + 40)
		var x := BinaryData.read_u32_be(record, 4)
		var y := BinaryData.read_u32_be(record, 8)
		if not selected.has(x * source.map_size + y):
			kept.append_array(record)
			continue
		if to == null:
			return "Building upgrades require Expanded rules."
		var next := BinaryData.read_u32_be(received, 4) + 1
		if next > 4294967295:
			return "Invalid building upgrade identity."
		BinaryData.write_u32_be(received, 4, next)
		BinaryData.write_u32_be(record, 0, next)
		var facility := BinaryData.read_u32_be(record, 36)
		if OverlayData.is_facility(facility):
			BinaryData.write_u32_be(record, 36, OverlayData.facility_id(int(facilities[OverlayData.facility_record(facility)])))
		received.append_array(record)
	from.expected_decoded_size = -1
	from.set_decoded_payload(kept)
	if to != null:
		to.expected_decoded_size = -1
		to.set_decoded_payload(received)
	return ""
