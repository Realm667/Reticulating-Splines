class_name RegionTerrain
extends RefCounted
## Deterministic region landscapes. Neither the origin nor neighbors are mutated.

@warning_ignore_start("integer_division")

const GENERATOR_VERSION := 2
const CHUNKS := ["ALTM", "XTER", "XBLD", "XZON", "XBIT", "XTXT", "MISC"]
const RIVER_LAYOUTS := ["classic", "meander", "delta", "crossing", "branch", "rejoin", "valley"]
const OCEAN_LAYOUTS := ["delta", "peninsula", "bay", "island", "islands", "cliffs"]
const EXCLUSIVE_FEATURES := [["island", "islands", "peninsula"], ["plateau", "ridge", "rolling", "basin"],
	["valley", "canyon", "basin"], ["lake", "lakes"], ["plateau", "island", "islands"]]


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
	var options := _random_options(edge, random)
	var document := EmptyCityTemplate.create(edge)
	var generated := NewCityTerrain.generate(document, options.ocean, options.river,
		options.hills, options.water, options.trees, SimRandom.new(random.randi_range(1, 2147483646)),
		GameLcgRandom.new(random.randi_range(1, 2147483646)), options.layout, options.features, true)
	if not generated.ok:
		return {"ok": false, "error": generated.error}
	var boundaries := _boundaries(template, position, origin, neighbors)
	var original_altitude := document.find_chunk("ALTM").decoded_payload.duplicate()
	var original_water := document.find_chunk("XBIT").decoded_payload.duplicate()
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
	_water_relief(document, boundaries, original_altitude, original_water, random.randi())
	return {"ok": true, "error": "", "document": document, "layout": options.layout,
		"features": options.features, "generator_version": GENERATOR_VERSION}


static func _random_options(edge: int, random: RandomNumberGenerator) -> NewCityTerrain.Options:
	var options := NewCityTerrain.Options.new()
	options.size = edge
	options.layout = NewCityTerrain.LAYOUTS[random.randi_range(0, NewCityTerrain.LAYOUTS.size() - 1)]
	if options.layout != "classic":
		options.features.append(options.layout)
	# Choose independent compatible features just as the ordinary dialog allows.
	# Shuffle with the cell RNG, never Array.shuffle's global random state.
	var candidates: Array = NewCityTerrain.LAYOUTS.slice(1)
	for index in range(candidates.size() - 1, 0, -1):
		var other := random.randi_range(0, index)
		var item: String = candidates[index]
		candidates[index] = candidates[other]
		candidates[other] = item
	for candidate: String in candidates:
		if random.randi_range(0, 4) != 0 or candidate in options.features:
			continue
		var compatible := true
		for selected: String in options.features:
			for group: Array in EXCLUSIVE_FEATURES:
				if selected in group and candidate in group:
					compatible = false
			if (selected in ["island", "islands", "canyon"] and candidate in RIVER_LAYOUTS) or (candidate in ["island", "islands", "canyon"] and selected in RIVER_LAYOUTS):
				compatible = false
		if compatible:
			options.features.append(candidate)
	options.ocean = random.randi_range(0, 1) == 1
	options.river = random.randi_range(0, 1) == 1
	for feature: String in options.features:
		options.ocean = options.ocean or feature in OCEAN_LAYOUTS
		options.river = options.river or feature in RIVER_LAYOUTS
	if "island" in options.features or "islands" in options.features or "canyon" in options.features:
		options.river = false
	options.hills = random.randi_range(NewCityTerrain.MIN_SLIDER, NewCityTerrain.MAX_SLIDER)
	options.water = random.randi_range(NewCityTerrain.MIN_SLIDER, NewCityTerrain.MAX_SLIDER)
	options.trees = random.randi_range(NewCityTerrain.MIN_SLIDER, NewCityTerrain.MAX_SLIDER)
	options.smooth_slopes = true
	return options


static func _water_relief(document: Sc2File, boundaries: PackedInt32Array,
		original_altitude: PackedByteArray, original_water: PackedByteArray, seed_value: int) -> void:
	var edge := document.map_size
	var count := edge * edge
	var altitude := document.find_chunk("ALTM").decoded_payload.duplicate()
	var flags := document.find_chunk("XBIT").decoded_payload.duplicate()
	var buildings := document.find_chunk("XBLD").decoded_payload.duplicate()
	var terrain := document.find_chunk("XTER").decoded_payload.duplicate()
	var heights := PackedInt32Array()
	var floors := PackedInt32Array()
	var fixed := PackedInt32Array()
	var water := PackedInt32Array()
	var salt := PackedByteArray()
	for values in [heights, floors, fixed, water, salt]:
		values.resize(count)
	fixed.fill(-1)
	water.fill(-1)
	for index in count:
		heights[index] = altitude[index * 2 + 1] & 31
	for side in 4:
		for along in edge:
			var point := _edge_point(side, along, 0, edge)
			var index := point.x * edge + point.y
			fixed[index] = (side * edge + along) * 5
			floors[index] = heights[index]
	# Distance envelope from the immutable border: carving cannot introduce a
	# height jump or force a correction into an existing neighboring city.
	for index in count:
		if index >= edge:
			floors[index] = maxi(floors[index], floors[index - edge] - 1)
		if index % edge > 0:
			floors[index] = maxi(floors[index], floors[index - 1] - 1)
	for index in range(count - 1, -1, -1):
		if index + edge < count:
			floors[index] = maxi(floors[index], floors[index + edge] - 1)
		if index % edge + 1 < edge:
			floors[index] = maxi(floors[index], floors[index + 1] - 1)
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 1.0 / maxf(8.0, edge * 0.16)
	noise.fractal_octaves = 3
	var changed := PackedInt32Array()
	var seeds: Array[PackedInt32Array] = []
	for level in 32:
		seeds.append(PackedInt32Array())
	# Continue water through an actual basin/channel. Noise changes its reach
	# and lateral course continuously, rather than stamping a constant strip.
	for side in 4:
		for along in edge:
			var offset := (side * edge + along) * 5
			if boundaries[offset + 2] == 0:
				continue
			var level := boundaries[offset + 1]
			var reach := maxf(4.0, minf(edge * 0.42, 96.0) * (0.8 + 0.55 * noise.get_noise_2d(along, side * edge)))
			for depth in range(1, mini(edge - 1, ceili(reach))):
				var shift := roundi(noise.get_noise_2d(depth * 1.3, along + side * edge) * depth * 0.35)
				var point := _edge_point(side, clampi(along + shift, 1, edge - 2), depth, edge)
				var index := point.x * edge + point.y
				if fixed[index] >= 0:
					continue
				var blend := smoothstep(reach * 0.55, reach, float(depth))
				var bed := maxi(0, level - 1 - int((1.0 - blend) * 2.0))
				var target := maxi(floors[index], roundi(lerpf(bed, heights[index], blend)))
				if target < heights[index]:
					heights[index] = target
					changed.append(index)
	# Preserve the ordinary generator's inland lakes and streams, with real beds.
	var sea := int(document.misc_u32(Sc2MiscLayout.WATER_LEVEL))
	for index in count:
		if fixed[index] >= 0:
			var offset := fixed[index]
			if boundaries[offset + 2] != 0:
				seeds[boundaries[offset + 1]].append(index * 2 + boundaries[offset + 3])
			continue
		if (original_water[index] & Sc2TileFlags.WATER) == 0:
			continue
		var saline := int((original_water[index] & Sc2TileFlags.SALT_WATER) != 0)
		var level := sea if saline else (((original_altitude[index * 2] << 8) | original_altitude[index * 2 + 1]) >> 5) & 31
		if not saline and level > 0:
			var target := maxi(floors[index], level - 1)
			if target < heights[index]:
				heights[index] = target
				changed.append(index)
		seeds[level].append(index * 2 + saline)
	# Lower surrounding banks to a one-level grade; fixed border floors win.
	var cursor := 0
	while cursor < changed.size():
		var index := changed[cursor]
		cursor += 1
		for neighbor in _cardinal(index, edge):
			var target := maxi(floors[neighbor], heights[index] + 1)
			if fixed[neighbor] < 0 and heights[neighbor] > target:
				heights[neighbor] = target
				changed.append(neighbor)
	# Flood only connected terrain below its water surface. Lower basins are
	# resolved first so different inland water levels remain distinct.
	for level in 32:
		var pending: PackedInt32Array = seeds[level]
		cursor = 0
		while cursor < pending.size():
			var entry := pending[cursor]
			cursor += 1
			var index := entry >> 1
			if water[index] >= 0:
				continue
			if fixed[index] >= 0:
				var offset := fixed[index]
				if boundaries[offset + 2] == 0 or boundaries[offset + 1] != level:
					continue
			elif heights[index] >= level:
				continue
			water[index] = level
			salt[index] = entry & 1
			for neighbor in _cardinal(index, edge):
				if water[neighbor] < 0:
					pending.append(neighbor * 2 + (entry & 1))
		seeds[level] = PackedInt32Array()
	var counts := PackedInt32Array()
	counts.resize(256)
	var inland_water := false
	var ocean_water := false
	for index in count:
		var packed := (altitude[index * 2] << 8) | altitude[index * 2 + 1]
		if fixed[index] < 0:
			packed = (packed & ~1023) | heights[index] | (maxi(0, water[index]) << 5)
			flags[index] &= ~(Sc2TileFlags.WATER | Sc2TileFlags.SALT_WATER)
			if water[index] >= 0:
				flags[index] |= Sc2TileFlags.WATER
				if salt[index]:
					flags[index] |= Sc2TileFlags.SALT_WATER
		if water[index] >= 0:
			buildings[index] = 0
			inland_water = inland_water or (flags[index] & Sc2TileFlags.SALT_WATER) == 0
			ocean_water = ocean_water or (flags[index] & Sc2TileFlags.SALT_WATER) != 0
		counts[buildings[index]] += 1
		altitude[index * 2] = packed >> 8
		altitude[index * 2 + 1] = packed & 255
	# The existing slope table is authoritative. Ghost heights preserve the
	# matching mountain slope across each fixed edge; no terrain tool is invoked.
	for index in count:
		var point := Vector2i(index / edge, index % edge)
		var mask := 0
		for adjacent in 8:
			var near: Vector2i = point + TerrainEditConstants.NEIGHBOR_OFFSETS[adjacent]
			var height: int
			if near.x >= 0 and near.y >= 0 and near.x < edge and near.y < edge:
				height = heights[near.x * edge + near.y]
			else:
				var side := 0 if near.x < 0 else 2 if near.x >= edge else 1 if near.y < 0 else 3
				var along := clampi(near.y if side % 2 == 0 else near.x, 0, edge - 1)
				var offset := (side * edge + along) * 5
				height = clampi(boundaries[offset] - clampi(boundaries[offset + 4], -1, 1), 0, 31)
			if height > heights[index]:
				mask |= TerrainEditConstants.NEIGHBOR_MASKS[adjacent]
		var shape: int = TerrainEditConstants.TERRAIN_SHAPES[mask]
		if shape == TerrainEditConstants.RAISE_BASIN:
			shape = TerrainTileIds.RAISED
		if fixed[index] >= 0 and boundaries[fixed[index] + 2] != 0 and water[index] <= heights[index]:
			continue # Retain the native surface-water edge tile of legacy rivers.
		terrain[index] = shape if water[index] < 0 else shape + (0x20 if water[index] - heights[index] == 1 else 0x10)
	for pair in [["ALTM", altitude], ["XBIT", flags], ["XTER", terrain], ["XBLD", buildings]]:
		document.find_chunk(pair[0]).set_decoded_payload(pair[1], true)
	for tile in 256:
		document.set_misc_u32(Sc2MiscLayout.TILE_COUNTS + tile * 4, counts[tile])
	document.set_misc_u32(Sc2MiscLayout.HAS_OCEAN, int(ocean_water))
	document.set_misc_u32(Sc2MiscLayout.HAS_RIVER, int(inland_water))


static func _cardinal(index: int, edge: int) -> PackedInt32Array:
	var result := PackedInt32Array()
	if index >= edge:
		result.append(index - edge)
	if index + edge < edge * edge:
		result.append(index + edge)
	if index % edge > 0:
		result.append(index - 1)
	if index % edge + 1 < edge:
		result.append(index + 1)
	return result


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
