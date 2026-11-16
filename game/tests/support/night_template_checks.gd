extends RefCounted
## Equivalent roads reuse templates; local edits and silhouettes stay independent.


static func run(app: CityApplication) -> void:
	var original := app.document_state.city
	var city := CityState.from_document(EmptyCityTemplate.create(128))
	app.document_state.city = city
	var ground := CityNightGround.new()
	var a := Vector2i(30, 30)
	var b := Vector2i(90, 90)
	for tile in [a, b]:
		for x in range(tile.x - 1, tile.x + 2):
			for y in range(tile.y - 1, tile.y + 2):
				city.set_land_altitude(x, y, 0)
				city.set_terrain_id(x, y, 0)
		for axis in 2:
			ground.masker._occluders[Vector3i(tile.x, tile.y, axis)] = []
	for id in [BuildingTileIds.ROAD_STRAIGHT_1, BuildingTileIds.ROAD_STRAIGHT_2,
		BuildingTileIds.ROAD_CURVE_1, BuildingTileIds.ROAD_CROSSROADS,
		BuildingTileIds.HIGHWAY_STRAIGHT_1, BuildingTileIds.HIGHWAY_ROAD_CROSSING_1,
		BuildingTileIds.HIGHWAY_ONRAMP_1, BuildingTileIds.HIGHWAY_ONRAMP_2,
		BuildingTileIds.HIGHWAY_ONRAMP_3, BuildingTileIds.HIGHWAY_ONRAMP_4,
		BuildingTileIds.HIGHWAY_SLOPE_1, BuildingTileIds.HIGHWAY_CURVE_1,
		BuildingTileIds.HIGHWAY_INTERSECTION, BuildingTileIds.HIGHWAY_BRIDGE]:
		for shape in [0, 1, 2, 3, 4]:
			for tile in [a, b]:
				city.set_building_id(tile.x, tile.y, id)
				city.set_terrain_id(tile.x, tile.y, shape)
				ground.roads.roads.clear()
			assert(ground._has_sources(city, a) == not ground.sources(city, a).is_empty())
			var first := ground._build(app, a)
			_check_fixture_reference(app, ground, a, first)
			var count := ground.templates.receivers.size()
			var fixture_count := ground.templates.fixture_cache.size()
			var second := ground._build(app, b)
			_check_fixture_reference(app, ground, b, second)
			assert(ground.templates.receivers.size() == count, "Translated road rebuilt its template")
			assert(ground.templates.fixture_cache.size() == fixture_count, "Translated road rebuilt identical street furniture")
			assert(first.texture == second.texture, "Identical road light did not share its GPU texture")
			assert(first.fixtures.get_image().get_data() == second.fixtures.get_image().get_data(), "Translated lamp geometry changed")
			assert(second.origin - first.origin == Vector2i(0, 960), "Template changed world placement")
			_check_mask_window(app, ground, a)
	# A neighboring facade changes only the local receiver's light profile.
	for tile in [a, b]:
		city.set_building_id(tile.x, tile.y, BuildingTileIds.ROAD_STRAIGHT_1)
		city.set_terrain_id(tile.x, tile.y, 0)
	ground.roads.roads.clear()
	var plain := ground._build(app, a)
	var entrance_id := int(ground.profiles.entrances.keys()[0])
	city.set_building_id(b.x + 1, b.y, entrance_id)
	assert(ground._has_sources(city, b) == not ground.sources(city, b).is_empty())
	var shop := ground._build(app, b)
	assert(shop.texture.get_image().get_data() != plain.texture.get_image().get_data(), "Entrance profile reused plain street lighting")
	city.set_building_id(b.x + 1, b.y, 0)
	# One opaque foreground must not poison a shared template for another tile.
	var cover := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	cover.fill(Color.WHITE)
	for axis in 2:
		ground.masker._occluders[Vector3i(a.x, a.y, axis)] = [{"origin": plain.origin, "image": cover}]
	assert(ground._build(app, a).texture.get_image().is_invisible())
	_check_fixture_reference(app, ground, a, ground._build(app, a))
	assert(ground._build(app, b).texture == plain.texture)
	# Lower and upper crossing decks have independent foreground masks.
	city.set_building_id(b.x, b.y, BuildingTileIds.HIGHWAY_ROAD_CROSSING_1)
	ground.roads.roads.clear()
	var crossing := ground._build(app, b)
	ground.masker._occluders[Vector3i(b.x, b.y, 0)] = [{"origin": crossing.origin, "image": cover}]
	var lower: Image = ground._build(app, b).texture.get_image()
	assert(not lower.is_invisible(), "Masking one deck removed both crossing approaches")
	assert(lower.get_data() != crossing.texture.get_image().get_data(), "Crossing deck mask had no effect")
	# Lookup limits must not invalidate texture references retained by visible tiles.
	for index in range(CityNightTemplates.LIMIT + 8):
		ground.profiles.street.intensity = float(index + 1) / 512.0
		ground._build(app, b)
	assert(ground.templates.receivers.size() <= CityNightTemplates.LIMIT)
	assert(ground.templates.textures.size() <= CityNightTemplates.LIMIT)
	assert(ground.templates.fixture_cache.size() <= CityNightTemplates.LIMIT)
	assert(not plain.texture.get_image().is_invisible())
	ground.reset()
	assert(ground.templates.receivers.is_empty() and ground.templates.textures.is_empty() and ground.templates.fixture_cache.is_empty())
	ground.free()
	app.document_state.city = original
	print("PASS: shared road/highway templates, grades, local entrances, independent crossing masks and bounded lookup caches")


static func _check_fixture_reference(app: CityApplication, ground: CityNightGround, tile: Vector2i, entry: Dictionary) -> void:
	var reference := CityNightFixtures.build(app, tile, entry.origin,
		CityNightFixtures.street_layout(app.document_state.city, tile, int(ground.profiles.street.spacing)),
		ground.masker, Callable(), ground.roads.raster_scale)
	assert(reference.fixtures.get_image().get_data() == entry.fixtures.get_image().get_data(), "Cached street furniture changed exact reference pixels")
	assert(reference.signals.size() == entry.signals.size())
	for index in reference.signals.size():
		var expected: Dictionary = reference.signals[index]
		var actual: Dictionary = entry.signals[index]
		assert(expected.origin == actual.origin and expected.axis == actual.axis)
		for lens in expected.lenses.size():
			assert(expected.lenses[lens].get_image().get_data() == actual.lenses[lens].get_image().get_data(), "Cached traffic signals changed pixels or lens order")


static func _check_mask_window(app: CityApplication, ground: CityNightGround, tile: Vector2i) -> void:
	var city := app.document_state.city
	var cover := Image.create(512, 512, false, Image.FORMAT_RGBA8)
	for stripe in range(0, 512, 7):
		cover.fill_rect(Rect2i(stripe, 0, 3, 512), Color.WHITE)
	var full: Dictionary[int, Array] = {}
	for axis in 2:
		var center := Vector2i(CityLifePaths.point(city, tile, axis, axis + 2, 0.5, false))
		full[axis] = [{"origin": center - Vector2i(256, 384), "image": cover}]
		ground.masker._occluders[Vector3i(tile.x, tile.y, axis)] = full[axis]
	var reference := ground._build(app, tile)
	ground.templates.fixture_cache.clear()
	for axis in 2:
		var center := Vector2i(CityLifePaths.point(city, tile, axis, axis + 2, 0.5, false))
		var window := Rect2i(center - Vector2i(64, 60), Vector2i(128, 128))
		ground.masker._occluders[Vector3i(tile.x, tile.y, axis)] = CityLifeCanvas.merged_occluders(full[axis], window)
	var clipped := ground._build(app, tile)
	assert(reference.texture.get_image().get_data() == clipped.texture.get_image().get_data(), "Mask window changed a road receiver")
	assert(reference.fixtures.get_image().get_data() == clipped.fixtures.get_image().get_data(), "Mask window exposed a pole or lamp")
	assert(reference.signals.size() == clipped.signals.size())
	for index in reference.signals.size():
		for lens in 3:
			assert(reference.signals[index].lenses[lens].get_image().get_data() == clipped.signals[index].lenses[lens].get_image().get_data(), "Mask window exposed a traffic signal")
	ground.templates.fixture_cache.clear()
	for axis in 2:
		ground.masker._occluders[Vector3i(tile.x, tile.y, axis)] = []
