class_name SimCityClassicImport
extends RefCounted
## One-way conversion of the big-endian Classic/Micropolis CTY layout.

@warning_ignore_start("integer_division")

const WIDTH := 120
const HEIGHT := 100
const MAP_OFFSET := 0x0c30
const FILE_SIZE := MAP_OFFSET + WIDTH * HEIGHT * 2
const TARGET_EDGE := 128
const ORIGIN := Vector2i(4, 14)
const WATER_LEVEL := 1
const T = preload("res://src/tools/shared/building_tile_ids.gd")
const SHAPES := [1, 0, 6, 7, 8, 9, 11, 10, 12, 13, 14]
const FACILITIES := {
	409: [T.HOSPITAL, 3], 418: [T.CHURCH, 2], 750: [T.COAL_POWER, 4],
	765: [T.FIRE_STATION, 3], 774: [T.POLICE_STATION, 3], 784: [T.STADIUM, 4],
	800: [T.STADIUM, 4], 816: [T.NUCLEAR_POWER, 4],
}


static func matches(path: String) -> bool:
	return path.get_extension().to_lower() == "cty"


static func read(path: String) -> Sc2File:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var length := file.get_length()
	if length != FILE_SIZE and length != FILE_SIZE + 128:
		return null
	var header := length - FILE_SIZE
	file.seek(header)
	var bytes := file.get_buffer(FILE_SIZE)
	if bytes.size() != FILE_SIZE:
		return null
	return convert_city(bytes, path.get_file().get_basename())


static func convert_city(bytes: PackedByteArray, city_name: String) -> Sc2File:
	if bytes.size() != FILE_SIZE:
		return null
	var template := EmptyCityTemplate.create(TARGET_EDGE)
	var terrain := template.find_chunk("XTER").decoded_payload.duplicate()
	var buildings := template.find_chunk("XBLD").decoded_payload.duplicate()
	var zones := template.find_chunk("XZON").decoded_payload.duplicate()
	var flags := template.find_chunk("XBIT").decoded_payload.duplicate()
	var altitude := template.find_chunk("ALTM").decoded_payload.duplicate()
	var facilities: Array[Vector3i] = []

	for x in TARGET_EDGE:
		for y in TARGET_EDGE:
			var source := Vector2i(x, y) - ORIGIN
			var inside := Rect2i(0, 0, WIDTH, HEIGHT).has_point(source)
			var sample := source.clamp(Vector2i.ZERO, Vector2i(WIDTH - 1, HEIGHT - 1))
			var word := _u16(bytes, MAP_OFFSET + (sample.x * HEIGHT + sample.y) * 2)
			var tile := word & 1023
			var index := x * TARGET_EDGE + y
			var network := _network(tile)
			var wet := (tile >= 2 and tile <= 20) or (network.y & Sc2TileFlags.WATER) != 0
			# Continue water through the padding where it reaches a Classic map edge.
			terrain[index] = TerrainTileIds.DEEP_WATER_FLAT if wet else TerrainTileIds.FLAT
			altitude[index * 2] = 0
			altitude[index * 2 + 1] = (WATER_LEVEL << Sc2AltitudeLayout.WATER_SHIFT) | (0 if wet else WATER_LEVEL)
			flags[index] = Sc2TileFlags.WATER if wet else 0
			if not inside:
				continue
			if network.x != 0:
				buildings[index] = network.x
				flags[index] |= network.y
			elif tile >= 21 and tile <= 43:
				buildings[index] = T.TREES_1 + (tile - 21) % 7
			elif tile >= 44 and tile <= 51 or tile >= 56 and tile <= 63:
				buildings[index] = T.RUBBLE_1 + (tile & 3)
			elif tile == 52:
				buildings[index] = T.RADIOACTIVE_WASTE
			elif tile >= 840 and tile <= 843:
				buildings[index] = T.SMALL_PARK
			else:
				var zoning := _zoning(tile)
				zones[index] = zoning.x
				if zoning.y != 0:
					buildings[index] = zoning.y
					zones[index] |= Sc2ZoneLayout.CORNERS_MASK
					flags[index] |= Sc2TileFlags.POWERABLE
				if FACILITIES.has(tile):
					facilities.append(Vector3i(x, y, tile))

	for site in facilities:
		var spec: Array = FACILITIES[site.z]
		_place_facility(Vector2i(site.x, site.y) - Vector2i.ONE, spec[0], spec[1], buildings, zones, flags)

	var counts := PackedInt32Array()
	counts.resize(256)
	for tile in buildings:
		counts[tile] += 1
	for id in counts.size():
		template.set_misc_u32(Sc2MiscLayout.TILE_COUNTS + id * 4, counts[id])
	template.set_misc_u32(Sc2MiscLayout.WATER_LEVEL, WATER_LEVEL)
	template.set_misc_u32(Sc2MiscLayout.START_YEAR, 1900)
	template.set_misc_u32(Sc2MiscLayout.CITY_CENTER_X, TARGET_EDGE / 2)
	template.set_misc_u32(Sc2MiscLayout.CITY_CENTER_Y, TARGET_EDGE / 2)
	var clock := clampi(_i32(bytes, 0x0b50), 0, 48 * (9999 - 1900) - 1)
	template.set_misc_u32(Sc2MiscLayout.CITY_DAYS,
		clock / 4 * CityCalendar.DAYS_PER_MONTH + (clock % 4) * CityCalendar.DAYS_PER_MONTH / 4)
	template.set_misc_i32(Sc2MiscLayout.FUNDS, _i32(bytes, 0x0ba4))
	template.set_misc_u32(Sc2MiscLayout.DIFFICULTY, clampi(_u16(bytes, 0x0b5e), 0, 2))
	template.set_misc_u32(Sc2MiscLayout.SIMULATION_SPEED, GameSpeedController.Speed.PAUSED)
	for plane in [["ALTM", altitude], ["XTER", terrain], ["XBLD", buildings], ["XZON", zones], ["XBIT", flags]]:
		if not template.find_chunk(plane[0]).set_decoded_payload(plane[1]):
			return null
	var converted := Sc2xDocument.from_new_city(template, city_name, "")
	if not converted.ok:
		return null
	var repair := FacilityRecordRepair.apply(CityState.from_document(converted.document))
	return converted.document if repair.ok else null


static func _network(tile: int) -> Vector2i:
	var base := (tile - 64) % 16 if tile >= 64 and tile <= 206 else -1
	var power := Sc2TileFlags.POWERABLE
	if base == 0 or base == 1 or base == 15 or tile in [79, 95] or (tile >= 828 and tile <= 831) or (tile >= 948 and tile <= 951):
		var horizontal := base == 0 or tile == 79 or (tile >= 828 and tile <= 831)
		return _bridge(T.ROAD_BRIDGE, horizontal)
	if base >= 2 and base <= 12:
		return Vector2i(T.ROAD_STRAIGHT_1 + SHAPES[base - 2], 0)
	if base == 13 or base == 14:
		return Vector2i(T.ROAD_POWER_CROSSING_2 if base == 13 else T.ROAD_POWER_CROSSING_1, power)
	if tile == 208 or tile == 209:
		var bridge := _bridge(T.POWER_BRIDGE, tile == 208)
		bridge.y |= power
		return bridge
	if tile >= 210 and tile <= 220:
		return Vector2i(T.POWER_LINE_STRAIGHT_1 + SHAPES[tile - 210], power)
	if tile == 221 or tile == 222:
		return Vector2i(T.RAIL_POWER_CROSSING_2 if tile == 221 else T.RAIL_POWER_CROSSING_1, power)
	if tile == 224 or tile == 225:
		return _bridge(T.RAIL_BRIDGE, tile == 224)
	if tile >= 226 and tile <= 236:
		return Vector2i(T.RAIL_STRAIGHT_1 + SHAPES[tile - 226], 0)
	if tile == 237 or tile == 238:
		return Vector2i(T.ROAD_RAIL_CROSSING_1 if tile == 237 else T.ROAD_RAIL_CROSSING_2, 0)
	return Vector2i.ZERO


static func _bridge(tile: int, horizontal: bool) -> Vector2i:
	return Vector2i(tile, Sc2TileFlags.WATER | (Sc2TileFlags.FLIPPED if horizontal else 0))


# The games use different lot sizes and artwork. Keep the original urban
# footprint and use 1x1 SC2000 equivalents for developed Classic zone cells.
static func _zoning(tile: int) -> Vector2i:
	if tile >= 240 and tile <= 404:
		var developed := tile >= 249
		return Vector2i(2 if tile >= 261 else 1, T.LOWER_CLASS_HOMES_1X1_1 + tile % 4 if developed else 0)
	if tile >= 423 and tile <= 611:
		return Vector2i(4 if tile >= 432 else 3, T.SMALL_OFFICE_BUILDING_1X1 if tile >= 432 else 0)
	if tile >= 612 and tile <= 692:
		return Vector2i(6 if tile >= 621 else 5, T.WAREHOUSE_1X1_1 if tile >= 621 else 0)
	if tile >= 693 and tile <= 708:
		return Vector2i(9, 0)
	if tile >= 709 and tile <= 744:
		return Vector2i(8, 0)
	return Vector2i.ZERO


static func _place_facility(origin: Vector2i, id: int, area: int, buildings: PackedByteArray,
		zones: PackedByteArray, flags: PackedByteArray) -> void:
	var far := origin + Vector2i(area - 1, area - 1)
	if not Rect2i(0, 0, TARGET_EDGE, TARGET_EDGE).has_point(origin) or not Rect2i(0, 0, TARGET_EDGE, TARGET_EDGE).has_point(far):
		return
	for x in range(origin.x, far.x + 1):
		for y in range(origin.y, far.y + 1):
			var index := x * TARGET_EDGE + y
			if buildings[index] != 0 or flags[index] & Sc2TileFlags.WATER:
				return
	for x in range(origin.x, far.x + 1):
		for y in range(origin.y, far.y + 1):
			var index := x * TARGET_EDGE + y
			buildings[index] = id
			zones[index] = 0
			flags[index] |= Sc2TileFlags.POWERABLE
	zones[origin.x * TARGET_EDGE + origin.y] = Sc2ZoneLayout.CORNER_BOTTOM_LEFT[0]
	zones[far.x * TARGET_EDGE + origin.y] = Sc2ZoneLayout.CORNER_BOTTOM_RIGHT[0]
	zones[far.x * TARGET_EDGE + far.y] = Sc2ZoneLayout.CORNER_TOP_LEFT[0]
	zones[origin.x * TARGET_EDGE + far.y] = Sc2ZoneLayout.CORNER_TOP_RIGHT[0]


static func _u16(bytes: PackedByteArray, offset: int) -> int:
	return (int(bytes[offset]) << 8) | bytes[offset + 1]


static func _i32(bytes: PackedByteArray, offset: int) -> int:
	var value := (_u16(bytes, offset) << 16) | _u16(bytes, offset + 2)
	return value - 0x100000000 if value >= 0x80000000 else value
