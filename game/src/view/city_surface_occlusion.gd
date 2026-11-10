class_name CitySurfaceOcclusion
extends RefCounted
## Ground below a moving object is a receiver, not a foreground silhouette.


static func is_surface(sprite_id: int) -> bool:
	var id := posmod(sprite_id, 500)
	return (id >= 256 and id <= 299) \
		or (id >= BuildingTileIds.ROAD_STRAIGHT_1 and id <= BuildingTileIds.RAIL_LAST) \
		or id in [BuildingTileIds.ROAD_RAIL_CROSSING_1, BuildingTileIds.ROAD_RAIL_CROSSING_2,
			BuildingTileIds.RAIL_BRIDGE, BuildingTileIds.RAIL_BRIDGE_PYLON,
			BuildingTileIds.RUNWAY, BuildingTileIds.RUNWAY_CROSSING, BuildingTileIds.TARMAC]


static func maximum_height(city: CityState, command: CityStaticCommand) -> float:
	var id := posmod(command.sprite_id, 500)
	var tile := IsometricFloatingOcclusion.depth_tile(command.depth_order, city.map_size)
	if id in [BuildingTileIds.RAIL_BRIDGE, BuildingTileIds.RAIL_BRIDGE_PYLON]:
		return city.water_altitude(tile.x, tile.y) + 1.0
	if not city.quarter_heights.is_empty():
		var index := city.index_of(tile.x,tile.y)*4
		if index >= 0:
			var top := float(maxi(maxi(city.quarter_heights[index],city.quarter_heights[index+1]),maxi(city.quarter_heights[index+2],city.quarter_heights[index+3])))/4.0
			return maxf(top,city.water_altitude(tile.x,tile.y)) if city.is_water(tile.x,tile.y) else top
	var shape := id - 256 if id >= 256 and id <= 268 else city.terrain_id(tile.x, tile.y) & 15
	var raised := shape < IsometricConstants.TERRAIN_SURFACE_CORNER_MASKS.size() \
		and IsometricConstants.TERRAIN_SURFACE_CORNER_MASKS[shape] != 0
	var height := float(city.land_altitude(tile.x, tile.y) + int(raised))
	if id == 269:
		return city.land_altitude(tile.x, tile.y)
	return maxf(height, city.object_altitude(tile.x, tile.y))


static func at_or_below(city: CityState, command: CityStaticCommand, altitude: float,
		supports := PackedInt32Array()) -> bool:
	return altitude >= 0.0 and (supports.has(command.depth_order)
		or maximum_height(city, command) <= altitude + 0.00001)


static func below(city: CityState, command: CityStaticCommand, altitude: float,
		supports := PackedInt32Array()) -> bool:
	return is_surface(command.sprite_id) and at_or_below(city, command, altitude, supports)


static func with_ground_neighbors(city: CityState, supports: PackedInt32Array) -> PackedInt32Array:
	var result := supports.duplicate()
	for order in supports:
		var tile := IsometricFloatingOcclusion.depth_tile(order, city.map_size)
		for step: Vector2i in CityLifePaths.DIRECTIONS:
			var neighbor := tile + step
			if city.index_of(neighbor.x, neighbor.y) < 0:
				continue
			# The same ground profile beside a lane is part of its receiver.
			# Do not exempt an unrelated higher cliff or a different slope.
			if city.land_altitude(tile.x, tile.y) != city.land_altitude(neighbor.x, neighbor.y) \
					or city.terrain_id(tile.x, tile.y) != city.terrain_id(neighbor.x, neighbor.y) \
					or city.is_water(tile.x, tile.y) != city.is_water(neighbor.x, neighbor.y):
				continue
			if not city.quarter_heights.is_empty():
				var first := city.index_of(tile.x,tile.y)*4
				var second := city.index_of(neighbor.x,neighbor.y)*4
				if city.quarter_heights.slice(first,first+4) != city.quarter_heights.slice(second,second+4):
					continue
			if city.is_water(tile.x, tile.y) and city.water_altitude(tile.x, tile.y) != city.water_altitude(neighbor.x, neighbor.y):
				continue
			var next := (neighbor.x + neighbor.y) * city.map_size + neighbor.y
			if not result.has(next):
				result.append(next)
	return result


static func train_supports(city: CityState, orders: PackedInt32Array) -> PackedInt32Array:
	var result := orders.duplicate()
	for order in orders:
		var tile := IsometricFloatingOcclusion.depth_tile(order, city.map_size)
		for direction in 4:
			var neighbor: Vector2i = tile + CityLifePaths.DIRECTIONS[direction]
			var opposite := (direction + 2) % 4
			if not (_rail_ports(city, tile) & (1 << direction)) or not (_rail_ports(city, neighbor) & (1 << opposite)):
				continue
			if not is_equal_approx(_rail_edge_height(city, tile, direction), _rail_edge_height(city, neighbor, opposite)):
				continue
			var next := (neighbor.x + neighbor.y) * city.map_size + neighbor.y
			if not result.has(next):
				result.append(next)
	return with_ground_neighbors(city, result)


static func _rail_ports(city: CityState, tile: Vector2i) -> int:
	if city.index_of(tile.x, tile.y) < 0:
		return 0
	var id := city.building_id(tile.x, tile.y)
	if id >= BuildingTileIds.RAIL_FIRST and id <= BuildingTileIds.RAIL_CROSSROADS:
		return CityLifePaths.ROAD_PORTS[id - BuildingTileIds.RAIL_FIRST]
	if id >= BuildingTileIds.RAIL_SLOPE_5 and id <= BuildingTileIds.RAIL_SLOPE_8:
		return 10 if (id - BuildingTileIds.RAIL_SLOPE_5) % 2 == 0 else 5
	if id in [BuildingTileIds.RAIL_BRIDGE, BuildingTileIds.RAIL_BRIDGE_PYLON]:
		return 10 if city.is_flipped(tile.x, tile.y) else 5
	if id in [BuildingTileIds.RAIL_POWER_CROSSING_1, BuildingTileIds.RAIL_POWER_CROSSING_2]:
		return 5 if id == BuildingTileIds.RAIL_POWER_CROSSING_1 else 10
	if id in [BuildingTileIds.ROAD_RAIL_CROSSING_1, BuildingTileIds.ROAD_RAIL_CROSSING_2]:
		return 10 if id == BuildingTileIds.ROAD_RAIL_CROSSING_1 else 5
	return 0


static func _rail_edge_height(city: CityState, tile: Vector2i, direction: int) -> float:
	if city.building_id(tile.x, tile.y) in [BuildingTileIds.RAIL_BRIDGE, BuildingTileIds.RAIL_BRIDGE_PYLON]:
		return city.water_altitude(tile.x, tile.y) + 1.0
	return CityLifePaths.edge_height(city, tile, direction)
