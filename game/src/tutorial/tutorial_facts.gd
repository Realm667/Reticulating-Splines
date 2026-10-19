class_name TutorialFacts
extends RefCounted
## Bounded scan of immutable tile snapshots. Never writes into the city.
@warning_ignore_start("integer_division")

var values: Dictionary = {}
var targets: Dictionary = {}
var signature: Array = []
var busy := false
var scanned := 0
var last_slice_usec := 0
var _edge := 0
var _buildings := PackedByteArray()
var _zones := PackedByteArray()
var _flags := PackedByteArray()
var _terrain := PackedByteArray()
var _pending: Dictionary = {}
var _points: Dictionary = {}


static func stamp(city: CityState) -> Array:
	return city.mirror_signature(["XBLD", "XZON", "XBIT", "XUND", "XTER", "ALTM"])


func begin(city: CityState) -> void:
	signature = stamp(city)
	_edge = city.map_size
	_buildings = city.buildings.duplicate()
	_zones = city.zones.duplicate()
	_flags = city.tile_flags.duplicate()
	_terrain = city.terrain.duplicate()
	_pending = {"power": 0, "pump": 0, "road": 0, "rail": 0, "connected_rail": 0, "homes": 0,
		"residential": 0, "jobs": 0, "powered": 0, "watered": 0, "piped": 0,
		"unpowered_homes": 0, "dry_homes": 0, "empty_zone": 0, "free": 0, "services": 0, "park": 0,
		"target_powered": 0, "target_watered": 0, "target_piped": 0}
	_points = {}
	scanned = 0
	busy = true


func work(budget_usec := 700) -> bool:
	if not busy:
		return false
	var started := Time.get_ticks_usec()
	while scanned < _buildings.size():
		_scan(scanned)
		scanned += 1
		if scanned % 32 == 0 and Time.get_ticks_usec() - started >= budget_usec:
			break
	last_slice_usec = Time.get_ticks_usec() - started
	if scanned == _buildings.size():
		values = _pending
		targets = _points
		busy = false
		return true
	return false


func _add(key: String, index: int) -> void:
	_pending[key] += 1
	if not _points.has(key):
		_points[key] = Vector2i(index / _edge, index % _edge)


func _scan(index: int) -> void:
	var building := int(_buildings[index])
	var zone := int(_zones[index]) & 15
	var flags := int(_flags[index])
	if building >= BuildingTileIds.HYDRO_POWER_1 and building <= BuildingTileIds.COAL_POWER:
		_add("power", index)
	if building == BuildingTileIds.WATER_PUMP:
		_add("pump", index)
	if NetworkTileMembership.surface_road(building):
		_add("road", index)
	if NetworkTileMembership.rail(building):
		_add("rail", index)
		var point := Vector2i(index / _edge, index % _edge)
		for offset in [Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN]:
			var neighbor: Vector2i = point + offset
			if neighbor.x >= 0 and neighbor.y >= 0 and neighbor.x < _edge and neighbor.y < _edge and NetworkTileMembership.rail(_buildings[neighbor.x * _edge + neighbor.y]):
				_add("connected_rail", index)
				break
	if building in [BuildingTileIds.FIRE_STATION, BuildingTileIds.POLICE_STATION, BuildingTileIds.SCHOOL, BuildingTileIds.HOSPITAL]:
		_add("services", index)
	if building in [BuildingTileIds.SMALL_PARK, BuildingTileIds.BIG_PARK]:
		_add("park", index)
	if building == 0 and zone == 0 and _terrain[index] == 0 and not (flags & Sc2TileFlags.WATER):
		_add("free", index)
	if zone in [3, 4, 5, 6]:
		_add("jobs", index)
	if zone < 1 or zone > 6:
		return
	if building < BuildingTileIds.ROAD_STRAIGHT_1:
		_add("empty_zone", index)
	if zone not in [1, 2]:
		return
	if not _points.has("residential") and (building < BuildingTileIds.ROAD_STRAIGHT_1 or building >= BuildingTileIds.DEVELOPED_FIRST):
		var point := Vector2i(index / _edge, index % _edge)
		var supplied := (flags & Sc2TileFlags.POWERED) != 0
		for offset in [Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN]:
			var neighbor: Vector2i = point + offset
			if (offset.x < 0 and point.x <= 1) or (offset.y < 0 and point.y <= 1):
				continue
			if neighbor.x >= 0 and neighbor.y >= 0 and neighbor.x < _edge and neighbor.y < _edge:
				supplied = supplied or (_flags[neighbor.x * _edge + neighbor.y] & Sc2TileFlags.POWERED) != 0
		_pending.target_powered = 1 if supplied else 0
		_pending.target_watered = 1 if flags & Sc2TileFlags.WATERED else 0
		_pending.target_piped = 1 if flags & Sc2TileFlags.PIPED else 0
		_points.residential = Vector2i(index / _edge, index % _edge)
	_pending.residential += 1
	if flags & Sc2TileFlags.POWERED:
		_add("powered", index)
	if flags & Sc2TileFlags.WATERED:
		_add("watered", index)
	if flags & Sc2TileFlags.PIPED:
		_add("piped", index)
	var occupied := (building >= 0x70 and building <= 0x7b) or (building >= 0x8c and building <= 0x93) or (building >= 0xae and building <= 0xb1)
	if occupied:
		_add("homes", index)
		if not flags & Sc2TileFlags.POWERED:
			_add("unpowered_homes", index)
		if not flags & Sc2TileFlags.WATERED:
			_add("dry_homes", index)


# Read the same immediate access conditions as growth::has_power and
# trip::find_transport, without copying a whole city or drawing any RNG.
static func site_access(city: CityState, point: Vector2i) -> Dictionary:
	if city.index_of(point.x, point.y) < 0:
		return {}
	var powered := city.is_powered(point.x, point.y)
	for offset in [Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN]:
		var neighbor: Vector2i = point + offset
		if (offset.x < 0 and point.x <= 1) or (offset.y < 0 and point.y <= 1):
			continue
		if city.index_of(neighbor.x, neighbor.y) >= 0:
			powered = powered or city.is_powered(neighbor.x, neighbor.y)
	var transport := false
	for dx in range(-3, 4):
		for dy in range(-3, 4):
			if (dx == 0 and dy == 0) or absi(dx) + absi(dy) > 3:
				continue
			var neighbor := point + Vector2i(dx, dy)
			if city.index_of(neighbor.x, neighbor.y) < 0:
				continue
			var tile := city.building_id(neighbor.x, neighbor.y)
			transport = transport or NetworkTileMembership.surface_road(tile) or tile in [BuildingTileIds.BUS_DEPOT, BuildingTileIds.RAIL_STATION, BuildingTileIds.SUBWAY_STATION]
	return {"powered": powered, "transport": transport, "rci": city.zone_id(point.x, point.y) in [1, 2, 3, 4, 5, 6]}
