extends SceneTree
@warning_ignore_start("integer_division")

var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: " + label)


func run() -> void:
	_test_randomizers()
	_test_coast_relief()
	_test_spilling_lake()
	_test_neighbors()
	print("region_terrain_test: %d failures" % failures)
	quit(1 if failures else 0)


func _test_randomizers() -> void:
	var features := {}
	var layouts := {}
	var settings := {}
	var combination := false
	for seed_value in 160:
		var random := RandomNumberGenerator.new()
		random.seed = seed_value
		var options := RegionTerrain._random_options(64, random)
		layouts[options.layout] = true
		combination = combination or options.features.size() > 1
		for feature: String in options.features:
			features[feature] = true
		for group: Array in RegionTerrain.EXCLUSIVE_FEATURES:
			var count := 0
			for feature: String in group:
				count += int(feature in options.features)
			check(count <= 1, "feature combination respects ordinary dialog exclusions")
		if options.features.any(func(feature: String) -> bool: return feature in ["island", "islands", "canyon"]):
			check(not options.river, "island/canyon excludes river")
		settings[Vector3i(options.hills, options.water, options.trees)] = true
	check(layouts.size() == NewCityTerrain.LAYOUTS.size(), "all normal layouts reachable")
	check(features.size() == NewCityTerrain.LAYOUTS.size() - 1 and combination, "all additional features and combinations reachable")
	check(settings.size() > 150, "independent hills water and trees randomizers")


func _fixture(edge: int, coast := true) -> Sc2File:
	var document: Sc2File = Sc2xDocument.create_empty(edge, "Terrain fixture").document
	document.set_misc_u32(Sc2MiscLayout.WATER_LEVEL, 6)
	var altitude := document.find_chunk("ALTM").decoded_payload.duplicate()
	var flags := document.find_chunk("XBIT").decoded_payload.duplicate()
	for x in edge:
		for y in edge:
			var index := x * edge + y
			var height := clampi(4 + floori((x - edge * 0.35 - sin(y * 0.12) * 3.0) * 0.5), 0, 25) if coast else 12
			var packed := height | (6 << 5)
			altitude[index * 2] = packed >> 8
			altitude[index * 2 + 1] = packed & 255
			flags[index] = Sc2TileFlags.WATER | Sc2TileFlags.SALT_WATER if height < 6 else 0
	document.find_chunk("ALTM").set_decoded_payload(altitude, true)
	document.find_chunk("XBIT").set_decoded_payload(flags, true)
	return document


func _test_coast_relief() -> void:
	var document := _fixture(64, false)
	var altitude := document.find_chunk("ALTM").decoded_payload.duplicate()
	var flags := document.find_chunk("XBIT").decoded_payload.duplicate()
	var boundaries := PackedInt32Array()
	for side in 4:
		for along in 64:
			boundaries.append_array(PackedInt32Array([5, 6, 1, 1, 0]))
			var point := RegionTerrain._edge_point(side, along, 0, 64)
			var index := point.x * 64 + point.y
			altitude[index * 2 + 1] = (altitude[index * 2 + 1] & 224) | 5
			flags[index] = Sc2TileFlags.WATER | Sc2TileFlags.SALT_WATER
	document.find_chunk("ALTM").set_decoded_payload(altitude, true)
	document.find_chunk("XBIT").set_decoded_payload(flags, true)
	var original := document.duplicate_document(true)
	RegionTerrain._water_relief(document, boundaries, altitude, flags, 3742)
	var depths := {}
	var carved := 0
	for along in range(16, 48):
		for depth in range(1, 32):
			var sample := RegionTerrain._sample(document, Vector2i(depth, along))
			if sample[2] == 0:
				depths[depth] = true
				break
			check(sample[1] == 6 and sample[0] < 6, "sea is continuous at common level with submerged bed")
			carved += int(RegionTerrain._sample(original, Vector2i(depth, along))[0] > sample[0])
	check(carved > 100, "water continuation lowers actual terrain")
	check(depths.size() >= 3, "coast reach varies instead of a parallel fixed-width strip")
	_validate(document, boundaries)


func _test_spilling_lake() -> void:
	var water := PackedInt32Array()
	var heights := PackedInt32Array()
	var fixed := PackedInt32Array()
	var salt := PackedByteArray()
	for values in [water, heights, fixed, salt]:
		values.resize(32 * 32)
	water.fill(-1)
	heights.fill(8)
	fixed.fill(-1)
	for x in range(8, 24):
		for y in range(8, 24):
			var index := x * 32 + y
			heights[index] = 3 if y < 20 else 4
			water[index] = 4 if x < 16 else 6
			salt[index] = int(x < 16)
	var shoreline := 8 * 32 + 8
	fixed[shoreline] = 0
	# A separate enclosed lake must not be lowered to the ocean level.
	water[3 * 32 + 3] = 6
	heights[3 * 32 + 3] = 4
	var before := heights.duplicate()
	RegionTerrain._drain_open_basins(water, heights, fixed, salt, 32)
	for x in range(16, 24):
		for y in range(8, 24):
			var index := x * 32 + y
			check(water[index] == (4 if y < 20 else -1), "an open lake drains to the connected lower body, exposing land at that level")
			check(salt[index] == 1, "drained lake joins the ocean salinity")
	check(water[shoreline] == 4 and fixed[shoreline] == 0, "fixed neighboring shoreline is unchanged")
	check(water[3 * 32 + 3] == 6 and heights == before, "closed inland lakes and all terrain heights are preserved")
	var drained := water.duplicate()
	RegionTerrain._drain_open_basins(water, heights, fixed, salt, 32)
	check(water == drained, "drainage is idempotent")


func _test_neighbors() -> void:
	var template := _fixture(64)
	var neighbors := {}
	var before := {}
	for side in 4:
		var neighbor := template.duplicate_document(true)
		var altitude := neighbor.find_chunk("ALTM").decoded_payload.duplicate()
		var flags := neighbor.find_chunk("XBIT").decoded_payload.duplicate()
		for x in 64:
			for y in 64:
				var source := Vector2i(63 - x, y) if side % 2 == 0 else Vector2i(x, 63 - y)
				var sample := RegionTerrain._sample(template, source)
				var index := x * 64 + y
				var packed := sample[0] | (sample[1] << 5)
				altitude[index * 2] = packed >> 8
				altitude[index * 2 + 1] = packed & 255
				flags[index] = Sc2TileFlags.WATER | Sc2TileFlags.SALT_WATER if sample[2] else 0
		neighbor.find_chunk("ALTM").set_decoded_payload(altitude, true)
		neighbor.find_chunk("XBIT").set_decoded_payload(flags, true)
		for turn in side:
			check(CityRotationCommand.apply(CityState.from_document(neighbor), true).ok, "neighbor camera rotation")
		neighbors[side] = neighbor
		before[side] = neighbor.serialize(true).data
	var template_before := template.serialize(true).data
	var first := RegionTerrain.generate(template, Vector2i.ZERO, Vector2i.ZERO, 9337, neighbors)
	var repeated := RegionTerrain.generate(template, Vector2i.ZERO, Vector2i.ZERO, 9337, neighbors)
	check(first.ok and repeated.ok, "four rotated neighbors and hills generate successfully")
	if first.ok and repeated.ok:
		check(first.document.serialize(true).data == repeated.document.serialize(true).data, "offer generation deterministic")
		_validate(first.document, RegionTerrain._boundaries(template, Vector2i.ZERO, Vector2i.ZERO, neighbors))
	for side in 4:
		check(neighbors[side].serialize(true).data == before[side], "existing neighbor remains byte-identical")
	check(template.serialize(true).data == template_before, "origin template remains byte-identical")


func _validate(document: Sc2File, boundaries: PackedInt32Array) -> void:
	var edge := document.map_size
	for side in 4:
		for along in edge:
			var offset := (side * edge + along) * 5
			var actual := RegionTerrain._sample(document, RegionTerrain._edge_point(side, along, 0, edge))
			check(actual[0] == boundaries[offset] and actual[2] == boundaries[offset + 2], "exact shared land/water boundary")
			if actual[2]:
				check(actual[1] == boundaries[offset + 1] and actual[3] == boundaries[offset + 3], "matching water surface and salinity")
	for x in edge:
		for y in edge:
			var actual := RegionTerrain._sample(document, Vector2i(x, y))
			if x > 0 and y > 0 and x + 1 < edge and y + 1 < edge and actual[2]:
				check(actual[0] < actual[1], "interior water always above actual terrain")
			if x + 1 < edge:
				check(absi(actual[0] - RegionTerrain._sample(document, Vector2i(x + 1, y))[0]) <= 1, "graded east slope")
			if y + 1 < edge:
				check(absi(actual[0] - RegionTerrain._sample(document, Vector2i(x, y + 1))[0]) <= 1, "graded south slope")
