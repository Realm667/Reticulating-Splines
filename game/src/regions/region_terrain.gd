class_name RegionTerrain
extends RefCounted
## Deterministic region landscapes. Neither the origin nor neighbors are mutated.

@warning_ignore_start("integer_division")

const GENERATOR_VERSION := 1
const CHUNKS := ["ALTM", "XTER", "XBLD", "XZON", "XBIT", "XTXT", "MISC"]
const RIVER_LAYOUTS := ["classic", "meander", "delta", "crossing", "branch", "rejoin", "valley"]
const OCEAN_LAYOUTS := ["delta", "peninsula", "bay", "island", "islands", "cliffs"]


static func generate(template: Sc2File, position: Vector2i, origin: Vector2i,
		seed_value: int, neighbors: Dictionary) -> Dictionary:
	if template == null or not template.is_valid() or template.map_size not in Sc2File.MAP_SIZES:
		return {"ok": false, "error": "Invalid region terrain template."}
	var edge := template.map_size
	for side: Variant in neighbors:
		if not side is int or side < 0 or side > 3 or not neighbors[side] is Sc2File:
			return {"ok": false, "error": "Invalid neighboring city."}
		var neighbor: Sc2File = neighbors[side]
		if not neighbor.is_valid() or neighbor.map_size != edge:
			return {"ok": false, "error": "Neighboring city sizes do not match."}
	var random := RandomNumberGenerator.new()
	# Stable per-cell mixing independent of visit order and simulation random states.
	random.seed = seed_value ^ ((position.x + 1) * 73856093) ^ ((position.y + 1) * 19349663)
	var options := NewCityTerrain.Options.new()
	options.size = edge
	options.layout = NewCityTerrain.LAYOUTS[random.randi_range(0, NewCityTerrain.LAYOUTS.size() - 1)]
	options.ocean = options.layout in OCEAN_LAYOUTS or random.randi_range(0, 2) == 0
	options.river = options.layout in RIVER_LAYOUTS and random.randi_range(0, 1) == 1
	options.hills = random.randi_range(0, 47)
	options.water = random.randi_range(0, 47)
	options.trees = random.randi_range(0, 47)
	options.smooth_slopes = true
	var document := EmptyCityTemplate.create(edge)
	var generated := NewCityTerrain.generate(document, options.ocean, options.river,
		options.hills, options.water, options.trees, SimRandom.new(random.randi_range(1, 2147483646)),
		GameLcgRandom.new(random.randi_range(1, 2147483646)), options.layout, [], true)
	if not generated.ok:
		return {"ok": false, "error": generated.error}
	var boundaries := _boundaries(template, position, origin, neighbors)
	var chunks := {}
	for id: String in CHUNKS:
		chunks[id] = document.find_chunk(id).decoded_payload
	var response: Dictionary = NativeSimulation.run({"op": "region.terrain",
		"city": {"map_size": edge, "large_version": document.large_version,
			"disaster_damage_class": -1, "chunks": chunks},
		"randoms": PackedInt64Array([1, 1, 1]), "scripts": [null, null, null], "budget": 0,
		"args": {"boundaries": boundaries, "sea_level": template.misc_u32(Sc2MiscLayout.WATER_LEVEL)}})
	if not response.get("ok", false):
		return {"ok": false, "error": str(response.get("error", "Region terrain generation failed."))}
	for id: String in response.written:
		if not document.find_chunk(id).set_decoded_payload(response.written[id], true):
			return {"ok": false, "error": "Cannot store generated region terrain."}
	return {"ok": true, "error": "", "document": document, "layout": options.layout,
		"generator_version": GENERATOR_VERSION}


static func _boundaries(template: Sc2File, position: Vector2i, origin: Vector2i,
		neighbors: Dictionary) -> PackedInt32Array:
	var result := PackedInt32Array()
	var edge := template.map_size
	var offset := position - origin
	for side in 4:
		for along in edge:
			var source: Sc2File = neighbors.get(side, template)
			var point := _edge_point(side, along, 0, edge)
			var inner := _edge_point(side, along, 1, edge)
			var neighboring := neighbors.has(side)
			if neighboring:
				point = _edge_point((side + 2) % 4, along, 0, edge)
				inner = _edge_point((side + 2) % 4, along, 1, edge)
			else:
				# Canonical shared edge/corner anchors, derived once from the first
				# map. Reflection changes only the boundary scaffold, not interiors.
				if posmod(offset.x, 2) == 1:
					point.x = edge - 1 - point.x
					inner.x = edge - 1 - inner.x
				if posmod(offset.y, 2) == 1:
					point.y = edge - 1 - point.y
					inner.y = edge - 1 - inner.y
			var sample := _sample(source, point)
			var previous := _sample(source, inner)
			var slope := int(sample[0]) - int(previous[0]) if neighboring else int(previous[0]) - int(sample[0])
			result.append_array(PackedInt32Array([sample[0], sample[1], sample[2], sample[3], slope]))
	return result


static func _edge_point(side: int, along: int, depth: int, edge: int) -> Vector2i:
	match side:
		0: return Vector2i(depth, along)
		1: return Vector2i(along, depth)
		2: return Vector2i(edge - 1 - depth, along)
		_: return Vector2i(along, edge - 1 - depth)


static func _sample(document: Sc2File, point: Vector2i) -> PackedInt32Array:
	# Saved coordinates rotate with the camera. Compass zero is region geography.
	for turn in int(document.misc_u32(Sc2MiscLayout.COMPASS) & 3):
		point = CityRotationCommand.rotate_point(point, document.map_size, true)
	var index := point.x * document.map_size + point.y
	var altitude := document.find_chunk("ALTM").decoded_payload
	var flags := document.find_chunk("XBIT").decoded_payload
	var packed := (int(altitude[index * 2]) << 8) | int(altitude[index * 2 + 1])
	return PackedInt32Array([packed & 31, (packed >> 5) & 31,
		int((flags[index] & Sc2TileFlags.WATER) != 0), int((flags[index] & Sc2TileFlags.SALT_WATER) != 0)])
