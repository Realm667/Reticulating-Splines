class_name BuildingUpgrades
extends RefCounted
## Expanded facility construction, queried from the authoritative native rules.

@warning_ignore_start("integer_division")

const FEATURE := "rs.upgrades.v1"


static func ensure(document: Sc2File) -> void:
	if not ExpandedRules.enabled(document) or document.sc2x_metadata == null:
		return
	if document.find_chunk("XUPG") != null or FEATURE in document.sc2x_metadata.required_features:
		return
	var bytes := PackedByteArray()
	bytes.resize(24)
	bytes[0] = 85
	bytes[1] = 80
	bytes[2] = 71
	bytes[3] = 49
	BinaryData.write_u32_be(bytes, 8, document.misc_u32(Sc2MiscLayout.CITY_DAYS) / 25)
	BinaryData.write_u32_be(bytes, 20, document.misc_u32(Sc2MiscLayout.CITY_DAYS) / 300)
	var chunk := Sc2Chunk.new()
	chunk.chunk_id = "XUPG"
	chunk.set_decoded_payload(bytes)
	document.chunks.append(chunk)
	document.invalidate_chunk_cache()
	document.sc2x_metadata.required_features.append(FEATURE)


static func info(city: CityState, point: Vector2i) -> Dictionary:
	if city == null or not ExpandedRules.enabled(city.document):
		return {}
	for record: Array in view_markers(city):
		var area := NativeCityTools.building_area(int(record[2]))
		if Rect2i(int(record[0]), int(record[1]), area, area).has_point(point):
			return {}
	return NativeSimulationBridge.run("upgrades.info", city, null, null, null, {"point": point}).result


static func apply(city: CityState, point: Vector2i, identity: int, level: int) -> BuildingEditResult:
	return NativeToolEdit.run("tool.upgrade", city, {"point": point, "identity": identity, "level": level}, ["MISC", "XUPG"])


static func budget(city: CityState) -> Dictionary:
	return NativeSimulationBridge.run("upgrades.budget", city, null, null, null).result


static func details(value: Dictionary) -> String:
	if value.is_empty():
		return ""
	var lines: PackedStringArray = []
	lines.append(TranslationServer.translate("Upgrade level: %d / 2") % value.level)
	var effect := "Output and capacity"
	match int(value.tile):
		BuildingTileIds.POLICE_STATION, BuildingTileIds.FIRE_STATION:
			effect = "Service coverage strength"
		BuildingTileIds.STADIUM, BuildingTileIds.ZOO:
			effect = "Residential growth allowance"
		BuildingTileIds.BUS_DEPOT, BuildingTileIds.RAIL_STATION, BuildingTileIds.SUBWAY_STATION:
			effect = "Station transfer cost"
		BuildingTileIds.LIBRARY:
			effect = "Additional school capacity"
		BuildingTileIds.MUSEUM:
			effect = "Additional college capacity"
	var current := str(100 + 50 * int(value.level)) + "%"
	var future := str(150 + 50 * int(value.level)) + "%"
	if effect == "Station transfer cost":
		current = str(4 - int(value.level))
		future = str(3 - int(value.level))
	elif effect in ["Additional school capacity", "Additional college capacity"]:
		current = str(5 * int(value.level))
		future = str(5 + 5 * int(value.level))
	lines.append(TranslationServer.translate("%s: %s") % [TranslationServer.translate(effect), current])
	lines.append(TranslationServer.translate("Annual upkeep at current funding: $%.2f") % (float(value.upkeep) / 1000.0))
	if int(value.paid) == 0:
		lines.append(TranslationServer.translate("Upgrade inactive: additional upkeep was not paid."))
	if int(value.target) > 0:
		lines.append(TranslationServer.translate("Construction: level %d, %d days remaining.") % [value.target, value.remaining])
	elif int(value.level) < 2:
		lines.append(TranslationServer.translate("Next level: %s; cost $%d; %d months.") % [future, value.cost, int(value.days) / 25])
		lines.append(TranslationServer.translate("Annual upkeep after completion: $%.2f") % (float(value.next_upkeep) / 1000.0))
		lines.append(TranslationServer.translate("Requires a population peak of %s and year %d.") % [DisplayNumberFormat.format(25000 if int(value.level) == 0 else 100000), 1920 if int(value.level) == 0 else 1950])
	if int(value.get("life", -1)) >= 0:
		lines.append(TranslationServer.translate("Remaining power plant life: %d years; an upgrade does not extend it.") % value.life)
	lines.append(TranslationServer.translate("Existing service continues during construction. Power plant age is unchanged."))
	return "\n" + "\n".join(lines)


static func view_markers(city: CityState) -> Array[Array]:
	var result: Array[Array] = []
	if city == null or city.document.sc2x_metadata == null:
		return result
	var raw: Variant = city.document.sc2x_metadata.extensions.get("upgrade_view_markers", [])
	if not raw is Array or raw.size() > city.map_size * city.map_size:
		return result
	for record: Variant in raw:
		if not record is Array or record.size() != 5:
			continue
		if not _whole_number(record[0], 0, city.map_size - 1) or not _whole_number(record[1], 0, city.map_size - 1):
			continue
		if not _whole_number(record[2], 0, 255) or not _whole_number(record[3], 0, 2) or not _whole_number(record[4], 0, 2):
			continue
		result.append(record)
	return result


static func _whole_number(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and float(value) >= minimum and float(value) <= maximum
