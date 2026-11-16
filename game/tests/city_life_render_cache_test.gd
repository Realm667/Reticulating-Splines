extends SceneTree

const CityRotation = preload("res://src/tools/city/city_rotation_command.gd")

@warning_ignore_start("integer_division")


func _initialize() -> void:
	_check_stamp_pixels()
	_check_road_pixels()
	_check_local_invalidation()
	_check_zoom_banks()
	_check_source_invalidation()
	_check_dense_occlusion_invalidation()
	_check_retired_masks()
	_check_night_preparation()
	_check_surface_budget()
	_check_network_search()
	_check_geometry_changes()
	_check_path_segments()
	_check_path_invalidation()
	_check_local_tiles()
	_check_bounded_collection()
	_check_receiver_index()
	_check_atlas_pixels()
	_check_incremental_eviction()
	_check_publication_budget()
	print("PASS: exact city-life artwork/emission pixels, road coordinates, local occlusion invalidation and bounded light reuse")
	quit()


func _check_night_preparation() -> void:
	var app := CityApplication.new()
	app.map_view = CityMapControl.new()
	app.map_view.zoom_factor = 1.0
	var city := load("res://tests/city_life_test.gd").fixture() as CityState
	app.document_state.city = city
	app.visual_environment.night = 1.0
	var canvas := CityLifeCanvas.new()
	canvas.gpu_enabled = true
	var headlights := CityLifeHeadlights.new()
	headlights._published = true
	canvas._occlusion_signature = [city.document.get_instance_id(), app.static_render_state.epoch, null,
		app.static_render.city_view_size(), 0, city.compass_rotation()]
	canvas.road_layer = headlights
	canvas.add_child(headlights)
	var figure := CityLifeController.Figure.new()
	figure.tile = Vector2i(64, 64)
	figure.enter = 0
	figure.exit = 2
	figure.direction = 2
	for y in range(64, 67):
		canvas._light_occluders[Vector3i(64, y, 0)] = []
	canvas.prepare_lights(app, [figure], 100000)
	assert(canvas.lights.prepared_receivers == 1, "Nighttime headlight preparation did not progress")
	assert(headlights.groups.is_empty() and headlights.images.is_empty() and headlights.slots.is_empty(),
		"Night preparation must not change the published GPU receiver slots")
	var cached: Dictionary = canvas.lights.surfaces.values()[0]
	var reference := CityLifeLights.new().surface(city, figure.tile, figure.enter, figure.direction, Callable(), false)
	assert(cached.image.get_data() == reference.image.get_data())
	canvas._occlusion_signature[5] = (city.compass_rotation() + 1) % 4
	figure.tile = Vector2i(64, 65)
	canvas.prepare_lights(app, [figure], 100000)
	assert(canvas.lights.prepared_receivers == 1 and canvas.lights.surfaces.values()[0] == cached,
		"Preparation changed an inactive directional bank before render selected the new view")
	canvas.free()
	app.map_view.free()
	app.free()


func _check_retired_masks() -> void:
	var canvas := CityLifeCanvas.new()
	var mask := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	var key := Vector3i(1, 2, 0)
	canvas._occluders[key] = [{"image": mask, "origin": Vector2i.ZERO}]
	canvas._occluder_bounds[key] = Rect2i(0, 0, 256, 256)
	canvas.lights.surfaces[Vector4i(1, 2, 0, 0)] = {"image": mask, "occlusion_keys": [key]}
	canvas.invalidate_occlusion([Rect2i(0, 0, 1, 1)])
	assert(canvas._occluders.is_empty() and canvas.lights.surfaces.is_empty(), "Retirement retained stale lookup entries")
	assert(canvas._retired_masks.size() == 2)
	for index in 200:
		canvas._retire_masks([{"image": mask}])
		assert(canvas._retired_mask_bytes <= CityLifeCanvas.RETIRED_MASK_BYTES)
	var pending := canvas._retired_masks.size()
	canvas.release_retired_masks(0)
	assert(canvas._retired_masks.size() == pending - 1, "A zero allowance must release one image and yield")
	canvas.release_retired_masks(1000000)
	assert(canvas._retired_masks.is_empty() and canvas._retired_mask_bytes == 0)
	canvas.free()


func _check_dense_occlusion_invalidation() -> void:
	var canvas := CityLifeCanvas.new()
	var changes: Array[Rect2i] = []
	for index in 5000:
		var key := Vector3i(index / 100, index % 100, index % 2)
		canvas._occluder_bounds[key] = Rect2i((index / 100) * 32 - 800, (index % 100) * 24 - 1200, 64, 48)
		canvas._occluders[key] = []
		canvas._light_occluders[key] = []
		canvas.lights.visible_roads[key] = []
		canvas.lights.visible_roads[key + Vector3i(0, 0, 2)] = []
		canvas.lights.surfaces[Vector4i(key.x, key.y, key.z, 0)] = {"occlusion_keys": [key]}
	for index in 80:
		changes.append(Rect2i(index * 53 - 1000, index * 31 - 1300, 32, 48))
	changes.append(changes[0])
	var expected := canvas._occluder_bounds.duplicate()
	var started := Time.get_ticks_usec()
	for key in canvas._occluder_bounds:
		for changed in changes:
			if canvas._occluder_bounds[key].intersects(changed):
				expected.erase(key)
				break
	var reference_usec := Time.get_ticks_usec() - started
	started = Time.get_ticks_usec()
	canvas.invalidate_occlusion(changes)
	var indexed_usec := Time.get_ticks_usec() - started
	assert(canvas._occluder_bounds == expected, "Indexed publication changed exact mask invalidation")
	assert(canvas._occluders.size() == expected.size() and canvas._light_occluders.size() == expected.size())
	assert(canvas.lights.surfaces.size() == expected.size() and canvas.lights.visible_roads.size() == expected.size() * 2)
	for key in expected:
		assert(canvas.lights.surfaces.has(Vector4i(key.x, key.y, key.z, 0)) and canvas.lights.visible_roads.has(key))
	canvas.invalidate_occlusion(changes)
	assert(canvas._occluder_bounds == expected, "Repeated publication removed unrelated masks")
	print("OCCLUSION_INDEX reference_us=", reference_usec, " indexed_us=", indexed_usec)
	canvas.free()


func _check_path_invalidation() -> void:
	var city := load("res://tests/city_life_test.gd").fixture() as CityState
	var life := CityLifeController.new(null)
	life._sync_path_geometry(city)
	var near := Vector3i(64, 64, 4)
	var far := Vector3i(20, 20, 4)
	for key in [near, far]:
		life._paths[key] = CityLifePaths.Segment.new(city, Vector2i(key.x, key.y), 0, 2, false)
	var retained := life._paths.duplicate()
	city.set_tile_flag(64, 64, Sc2TileFlags.POWERED, true)
	assert(life._sync_path_geometry(city).is_empty())
	assert(life._paths == retained, "A power/status update discarded unchanged lane geometry")
	city.set_land_altitude(64, 65, 3)
	assert(life._sync_path_geometry(city).has(Vector2i(64, 64)))
	assert(not life._paths.has(near) and life._paths[far] == retained[far], "Local slope edits discarded distant paths or retained stale neighbors")
	var refreshed := CityLifePaths.Segment.new(city, Vector2i(64, 64), 0, 2, false)
	for step in 21:
		assert(refreshed.point(step / 20.0).is_equal_approx(CityLifePaths.point(city, Vector2i(64, 64), 0, 2, step / 20.0, false)))
	assert(CityRotation.apply(city, true).ok)
	life._sync_path_geometry(city)
	assert(life._paths.is_empty(), "Rotation retained paths in the previous coordinate space")
	# Catch-up shares buckets, but must retain the original eviction rate.
	for index in 5000:
		life._paths[Vector3i(index, 0, 0)] = refreshed
	life._advance(city, 0.01, false)
	assert(life._paths.size() == 5000 - 64, "Catch-up stopped pruning unoccupied paths")



func _check_atlas_pixels() -> void:
	var atlas := CityLifeAtlas.new()
	var sprites := CityLifeSprites.new()
	var lights := CityLifeLights.new()
	var bounds := Rect2i(-13, 27, 517, 193)
	var entries: Array[Dictionary] = []
	var occluder := Image.create(20, 130, false, Image.FORMAT_RGBA8)
	occluder.fill_rect(Rect2i(8, 2, 4, 120), Color.WHITE)
	for i in 120:
		var sprite := sprites.sprite(i % 4 == 3, i % 12, i % 4, i % 2, i % 3)
		entries.append({"sprite": sprite, "origin": bounds.position + Vector2i((i * 17) % 520 - 5, (i * 3) % 195 - 4),
			"opacity": [0.0, 0.31, 1.0][i % 3], "lamps": lights.lamp_mask(sprite, i % 3, i % 4),
			"occluders": [{"origin": Vector2i(50, 30), "image": occluder}]})
	for phase in 3:
		if phase == 1:
			entries.reverse()
		elif phase == 2:
			entries.clear()
		var expected := Image.create(bounds.size.x, bounds.size.y, false, Image.FORMAT_RGBA8)
		expected.fill(Color.TRANSPARENT)
		var lamps := expected.duplicate() as Image
		for entry in entries:
			_reference_stamp(expected, bounds.position, entry.sprite, entry.origin, entry.occluders, entry.opacity, lamps, entry.lamps)
		atlas.compose(bounds, entries, true)
		var actual := Image.create(bounds.size.x, bounds.size.y, false, Image.FORMAT_RGBA8)
		actual.fill(Color.TRANSPARENT)
		var actual_lamps := actual.duplicate() as Image
		for i in atlas.destinations.size():
			actual.blit_rect(atlas.image, atlas.sources[i], atlas.destinations[i].position)
			actual_lamps.blit_rect(atlas.emission, atlas.sources[i], atlas.destinations[i].position)
		assert(actual.get_data() == expected.get_data(), "Sparse artwork changed clipping, overlap order or fade pixels")
		assert(actual_lamps.get_data() == lamps.get_data(), "Sparse lamp pixels changed or retained old figures")


func _check_local_tiles() -> void:
	var city := load("res://tests/city_life_test.gd").fixture() as CityState
	var cache := CityLifeTiles.new()
	var bounds := Rect2i(0, 0, 5000, 4000)
	for step in 12:
		match step:
			1: city.set_building_id(64, 64, 0)
			2: city.set_building_id(64, 64, BuildingTileIds.HIGHWAY_BRIDGE)
			3: city.set_land_altitude(64, 64, 5)
			4: city.set_terrain_id(64, 64, 6)
			5: city.set_tile_flag(64, 64, Sc2TileFlags.FLIPPED, true)
			6: city.set_building_id(10, 10, 112)
			7: bounds = Rect2i(1800, 1000, 500, 1000)
			8: city.visible_altitude_levels = 3
			9: bounds = Rect2i(-1000, -1000, 100, 100)
			10: city = load("res://tests/city_life_test.gd").fixture() as CityState
			11: bounds = Rect2i(0, 0, 5000, 4000)
		var expected: Array[Vector2i] = []
		# Independent complete scan, including the same strict viewport edges.
		for x in city.map_size:
			for y in city.map_size:
				var tile := Vector2i(x, y)
				if CityLifePaths.ports(city, tile) != 0 and city.land_altitude(x, y) < city.visible_altitude_levels \
						and bounds.has_point(Vector2i(CityLifePaths.point(city, tile, 0, 2, 0.5, false))):
					expected.append(tile)
		assert(cache.collect(city, bounds) == expected, "Local road updates changed eligible tiles or spawn order at step %d" % step)
		assert(cache.collect(city, bounds) == expected, "Warm road reuse changed eligible tiles")


func _check_bounded_collection() -> void:
	var city := load("res://tests/city_life_test.gd").fixture() as CityState
	var bounds := Rect2i(0, 0, 5000, 4000)
	var roads := CityLifeTiles.new()
	var selected := roads.collect(city, bounds, 1)
	assert(roads.collecting and selected.is_empty(), "Cold discovery must yield before publishing a partial spawn list")
	city.set_building_id(64, 64, BuildingTileIds.EMPTY)
	var steps := 0
	while roads.collecting:
		selected = roads.collect(city, bounds, 1)
		steps += 1
		assert(steps < city.map_size * city.map_size)
	assert(selected == CityLifeTiles.new().collect(city, bounds), "Edits during collection left stale lanes or changed spawn order")
	var life := CityLifeController.new(null)
	life._viewport = bounds
	var original: CityLifeTiles
	for turn in 8:
		if turn == 6:
			city.set_land_altitude(64, 63, 4)
		life._collect_tiles(city)
		assert(life.tiles == CityLifeTiles.new().collect(city, bounds), "Retained direction ignored a hidden edit")
		if turn == 0:
			original = life._tile_cache
		elif turn == 4:
			assert(life._tile_cache == original, "Returning to a direction discarded its road cache")
		assert(CityRotation.apply(city, false).ok)
	assert(life._tile_caches.size() == 4)
	var ground := CityNightGround.new()
	var reference := CityNightGround.new()
	ground.bounds = bounds
	reference.bounds = bounds
	ground._collect(city, 1)
	assert(ground.collection_active, "Cold fixture discovery did not yield")
	steps = 0
	while ground.collection_active:
		ground._collect(city, 1)
		steps += 1
		assert(steps < city.map_size * city.map_size)
	reference._collect(city)
	assert(ground.visible_tiles == reference.visible_tiles, "Budgeted discovery changed light placement or priority")
	assert(ground.pending == reference.pending and ground.queued == reference.queued)
	var retained := ground.visible_tiles.duplicate()
	ground.bounds.position += Vector2i(128, 64)
	ground._collect(city, 1)
	assert(ground.collection_active and ground.visible_tiles == retained, "Discovery exposed a partial draw list")
	ground.reset()
	assert(not ground.collection_active and ground._collection_indices.is_empty())
	ground.free()
	reference.free()


func _check_receiver_index() -> void:
	var ground := CityNightGround.new()
	ground.resident = true
	var texture := ImageTexture.create_from_image(Image.create(1, 1, false, Image.FORMAT_RGBA8))
	for index in 5000:
		var tile := Vector2i(index / 50, index % 50)
		ground._store(tile, {"texture": texture, "fixtures": texture, "signals": [], "origin": tile * Vector2i(96, 40) - Vector2i(200, 300)})
	var changes: Array[Rect2i] = []
	for index in 80:
		changes.append(Rect2i((index * 117) % 9600 - 200, (index * 53) % 2000 - 300, 33, 65))
	for step in 3:
		if step == 1:
			var index := ground._receiver_grid
			ground._store(Vector2i.ZERO, ground.cache[Vector2i.ZERO].duplicate())
			assert(not ground._receiver_grid_dirty and ground._receiver_grid == index, "Pixel refresh rebuilt unchanged spatial geometry")
		elif step == 2:
			ground._release(Vector2i.ZERO)
			var moved: Dictionary = ground.cache[Vector2i.ONE].duplicate()
			moved.origin = Vector2i(-200, -300)
			ground._store(Vector2i.ONE, moved)
			ground._store(Vector2i(-1, -1), moved.duplicate())
		var expected := {}
		var started := Time.get_ticks_usec()
		for tile in ground.cache:
			for changed in changes:
				if Rect2i(ground.cache[tile].origin, Vector2i(64, 64)).intersects(changed):
					expected[tile] = true
					break
		var scan_usec := Time.get_ticks_usec() - started
		ground.dirty.clear()
		ground.pending.clear()
		ground.queued.clear()
		started = Time.get_ticks_usec()
		ground.invalidate_regions(changes)
		var indexed_usec := Time.get_ticks_usec() - started
		assert(ground.dirty == expected, "Spatial query missed or over-invalidated a moved/removed/boundary receiver")
		print("RECEIVER_INDEX step=%d scan_usec=%d indexed_usec=%d matches=%d" % [step, scan_usec, indexed_usec, expected.size()])
	ground.reset()
	ground.invalidate_regions(changes)
	assert(ground.dirty.is_empty())
	ground.free()


func _check_path_segments() -> void:
	var city := load("res://tests/city_life_test.gd").fixture() as CityState
	var tile := Vector2i(64, 64)
	for id in [BuildingTileIds.ROAD_CROSSROADS, BuildingTileIds.HIGHWAY_CURVE_1,
			BuildingTileIds.HIGHWAY_ONRAMP_1, BuildingTileIds.HIGHWAY_ROAD_CROSSING_1, BuildingTileIds.HIGHWAY_BRIDGE]:
		city.set_building_id(tile.x, tile.y, id)
		for shape in [0, 1, 6]:
			city.set_terrain_id(tile.x, tile.y, shape)
			for flipped in [false, true]:
				city.set_tile_flag(tile.x, tile.y, Sc2TileFlags.FLIPPED, flipped)
				for enter in 4:
					for exit in 4:
						for walking in [false, true]:
							var segment := CityLifePaths.Segment.new(city, tile, enter, exit, walking)
							for progress in [-0.1, 0.0, 0.1, 0.499, 0.5, 0.7, 1.0, 1.1]:
								assert(segment.point(progress) == CityLifePaths.point(city, tile, enter, exit, progress, walking),
									"Cached lane geometry must preserve exact positions, bends, grades and endpoint clamping")


func _check_geometry_changes() -> void:
	var city := load("res://tests/city_life_test.gd").fixture() as CityState
	var lights := CityLifeLights.new()
	lights.sync_geometry(city)
	assert(lights.geometry_reset)
	var tile := Vector2i(64, 64)
	var before := lights.surface(city, tile, 0, 2)
	var shear_before := lights.cached_sprite_shear(city, tile, 0, 2)
	city.set_building_id(10, 10, 112)
	lights.sync_geometry(city)
	assert(not lights.geometry_reset and lights.surface(city, tile, 0, 2).texture == before.texture,
		"Distant development must not rebuild unchanged road receivers")
	assert(lights.sprite_shears.has(Vector4i(64, 64, 0, 2)) and lights.cached_sprite_shear(city, tile, 0, 2) == shear_before,
		"Distant development must retain the road inclination")
	city.set_tile_flag(64, 64, Sc2TileFlags.POWERED, true)
	city.set_zone_id(64, 64, 2)
	assert(lights.sync_geometry(city).is_empty(), "Power and zoning colors do not alter road geometry")
	for change in ["slope", "height", "building", "flip", "corner"]:
		match change:
			"slope":
				city.set_terrain_id(64, 64, 6)
			"height":
				city.set_land_altitude(64, 64, 3)
			"building":
				city.set_building_id(64, 64, BuildingTileIds.HIGHWAY_CURVE_1)
			"flip":
				city.set_tile_flag(64, 64, Sc2TileFlags.FLIPPED, true)
			"corner":
				city.set_building_corners(64, 64, 0x80)
		assert(lights.sync_geometry(city).has(tile), "Changed geometry not detected: " + change)
		assert(not lights.sprite_shears.has(Vector4i(64, 64, 0, 2)), "Road edits must invalidate vehicle inclination")
		for enter in 4:
			var exit := (enter + 2) % 4
			assert(is_equal_approx(lights.cached_sprite_shear(city, tile, enter, exit),
				CityLifePaths.sprite_shear(city, tile, enter, exit)), "Cached inclination differs after " + change)
		var cached := lights.surface(city, tile, 0, 2)
		var fresh := CityLifeLights.new().surface(city, tile, 0, 2)
		assert(cached.image.get_data() == fresh.image.get_data(), "Local geometry update left stale road pixels: " + change)
	# An initially closed next tile becomes part of an existing headlight receiver.
	city.set_land_altitude(64, 64, 0)
	city.set_terrain_id(64, 64, 0)
	city.set_building_id(64, 64, BuildingTileIds.ROAD_STRAIGHT_1)
	city.set_building_id(64, 65, 0)
	lights.sync_geometry(city)
	before = lights.surface(city, tile, 0, 2)
	city.set_building_id(64, 65, BuildingTileIds.ROAD_STRAIGHT_1)
	lights.sync_geometry(city)
	var reopened := lights.surface(city, tile, 0, 2)
	assert(reopened.texture != before.texture)
	assert(reopened.image.get_data() == CityLifeLights.new().surface(city, tile, 0, 2).image.get_data())
	assert(NativeCityChanges.changed_cells(PackedByteArray([1, 2, 3, 4]), PackedByteArray([1, 8, 3, 9]), 2, 255) == PackedInt32Array([0, 1]))


func _check_stamp_pixels() -> void:
	var sprites := CityLifeSprites.new()
	var lights := CityLifeLights.new()
	var mask := Image.create(11, 9, false, Image.FORMAT_RGBA8)
	for y in mask.get_height():
		for x in mask.get_width():
			mask.set_pixel(x, y, Color(0.2, 0.4, 0.6, 0.1 if (x + y) % 3 == 0 else 0.0))
	var occluders: Array = [{"origin": Vector2i(-4, -2), "image": mask}, {"origin": Vector2i(3, 2), "image": mask}]
	var merged := CityLifeCanvas.merged_occluders(occluders)
	for y in range(-5, 15):
		for x in range(-8, 20):
			assert(CityLifeCanvas.hidden_at(Vector2i(x, y), occluders) == CityLifeCanvas.hidden_at(Vector2i(x, y), merged))
	for opacity in [0.0, 0.31, 1.0]:
		for offset in [Vector2i(-5, -4), Vector2i.ZERO, Vector2i(4, 5)]:
			var expected := Image.create(16, 12, false, Image.FORMAT_RGBA8)
			var actual := expected.duplicate() as Image
			var expected_lamps := expected.duplicate() as Image
			var actual_lamps := expected.duplicate() as Image
			for kind in 4:
				for direction in 4:
					var sprite := sprites.sprite(kind == 3, kind * 3, direction, direction % 2, mini(kind, 2))
					var lamps := lights.lamp_mask(sprite, kind, direction) if kind < 3 else null
					var origin := Vector2i(kind - 3, direction - 2)
					_reference_stamp(expected, offset, sprite, origin, occluders, opacity, expected_lamps, lamps)
					CityLifeCanvas.stamp(actual, offset, sprite, origin, merged, opacity, actual_lamps, lamps)
					assert(actual.get_data() == expected.get_data(), "Batch blits changed overlap, clipping or fade pixels")
					assert(actual_lamps.get_data() == expected_lamps.get_data(), "A later figure failed to replace the old lamp pixels")


func _reference_stamp(destination: Image, offset: Vector2i, sprite: Image, origin: Vector2i,
		occluders: Array, opacity: float, emission: Image, lamps: Image) -> void:
	# Original per-pixel replacement rule, including transparent lamp erasure.
	for y in sprite.get_height():
		for x in sprite.get_width():
			var color := sprite.get_pixel(x, y)
			var point := origin + Vector2i(x, y)
			var local := point - offset
			if color.a == 0.0 or not Rect2i(Vector2i.ZERO, destination.get_size()).has_point(local):
				continue
			if CityLifeCanvas.hidden_at(point, occluders):
				continue
			color.a *= opacity
			destination.set_pixelv(local, color)
			var lamp := lamps.get_pixel(x, y) if lamps != null else Color.TRANSPARENT
			lamp.a *= opacity
			emission.set_pixelv(local, lamp)


func _check_road_pixels() -> void:
	var city := load("res://tests/city_life_test.gd").fixture() as CityState
	var mask := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	mask.fill_rect(Rect2i(20, 0, 13, 64), Color.WHITE)
	var occluders: Array = [{"origin": Vector2i(2080, 1512), "image": mask}]
	for slope in [0, 1, 6]:
		city.set_terrain_id(64, 64, slope)
		var lights := CityLifeLights.new()
		for direction in 4:
			var tile := Vector2i(64, 64)
			var enter := (direction + 2) % 4
			var surface := lights.surface(city, tile, enter, direction,
				func(_tile: Vector2i, _enter: int) -> Array: return occluders)
			var expected := Image.create(96, 96, false, Image.FORMAT_RGBAF)
			var bounds := Rect2i(surface.origin, expected.get_size())
			for step in 3:
				for road: Dictionary in lights._road_patches(city, tile, enter):
					for y in road.image.get_height():
						for x in road.image.get_width():
							var color: Color = road.image.get_pixel(x, y)
							var point: Vector2i = road.origin + Vector2i(x, y)
							if color.a > 0.0 and bounds.has_point(point) and not CityLifeCanvas.hidden_at(point, occluders):
								expected.set_pixelv(point - bounds.position, color)
				if not CityLifePaths.connected(city, tile, direction):
					break
				tile += CityLifePaths.DIRECTIONS[direction]
				enter = (direction + 2) % 4
			assert(surface.image.get_data() == expected.get_data(), "Road blits changed numeric world coordinates or occlusion")


func _check_local_invalidation() -> void:
	var app := CityApplication.new()
	var canvas := CityLifeCanvas.new()
	app.city_life.canvas = canvas
	var near := Vector3i(1, 2, 0)
	var far := Vector3i(3, 4, 1)
	var near_surface := Vector4i(1, 2, 0, 1)
	var far_surface := Vector4i(3, 4, 1, 2)
	canvas._occluder_bounds.assign({near: Rect2i(0, 0, 64, 48), far: Rect2i(500, 500, 64, 48)})
	canvas._occluders.assign({near: [], far: []})
	canvas._light_occluders.assign({near: [], far: []})
	canvas.lights.visible_roads.assign({near: [], far: []})
	canvas.lights.surfaces.assign({near_surface: {"occlusion_keys": [far, near]}, far_surface: {"occlusion_keys": [far]}})
	var changed: Array[Rect2i] = [Rect2i(32, 16, 8, 8)]
	app.map_render._invalidate_region_foregrounds(changed, [])
	assert(canvas._occluders.size() == 2, "A palette-only publication invalidated silhouettes")
	app.map_render._invalidate_region_foregrounds(changed, changed)
	assert(not canvas._occluders.has(near) and canvas._occluders.has(far))
	assert(not canvas._light_occluders.has(near) and canvas._light_occluders.has(far))
	assert(not canvas.lights.visible_roads.has(near) and canvas.lights.visible_roads.has(far))
	assert(not canvas.lights.surfaces.has(near_surface) and canvas.lights.surfaces.has(far_surface),
		"A surface must depend on every queried road tile, including the tiles ahead")
	var regions := CityRegionCache.new()
	regions.region_edge = 256
	regions.divisor = 1
	regions.visible.assign([Vector2i.ZERO, Vector2i(1, 1)])
	regions.visible_keys.assign({Vector2i.ZERO: true, Vector2i(1, 1): true})
	canvas._sync_visible_regions(regions)
	regions.visible.assign([Vector2i.ZERO])
	regions.visible_keys.erase(Vector2i(1, 1))
	canvas._sync_visible_regions(regions)
	assert(canvas._occluders.is_empty() and canvas.lights.surfaces.is_empty(),
		"Regions that leave the viewport must release cached silhouettes and dependent lights")
	regions.resident = true
	regions.visible.assign([Vector2i(1, 1)])
	regions.visible_keys.assign({Vector2i(1, 1): true})
	canvas._occluders[far] = []
	canvas._occluder_bounds[far] = Rect2i(500, 500, 64, 48)
	canvas._sync_visible_regions(regions)
	regions.visible.clear()
	regions.visible_keys.clear()
	canvas._sync_visible_regions(regions)
	assert(canvas._occluders.has(far), "Resident silhouettes survive leaving the viewport")
	canvas.invalidate_occlusion([Rect2i(500, 500, 64, 48)])
	assert(not canvas._occluders.has(far), "Real edits invalidate resident silhouettes outside the viewport")
	canvas.free()
	app.free()


func _check_surface_budget() -> void:
	var city := load("res://tests/city_life_test.gd").fixture() as CityState
	var lights := CityLifeLights.new()
	var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	var texture := ImageTexture.create_from_image(image)
	for i in CityLifeLights.SURFACE_LIMIT:
		lights.surfaces[Vector4i(i, 0, 0, 0)] = {"retained": i, "image": image, "texture": texture}
	var oldest := lights.surface(city, Vector2i.ZERO, 0, 0)
	lights.surface(city, Vector2i(64, 64), 0, 2)
	assert(lights.surfaces.size() == CityLifeLights.SURFACE_LIMIT)
	assert(lights.surfaces[Vector4i.ZERO] == oldest and not lights.surfaces.has(Vector4i(1, 0, 0, 0)),
		"The cache must retain recently used light surfaces when it reaches its budget")

	lights.set_raster_scale(4)
	for i in CityLifeController.MAX_FIGURES:
		lights.surfaces[Vector4i(i, 0, 0, 0)] = {"image": image, "texture": null}
	oldest = lights.surface(city, Vector2i.ZERO, 0, 0, Callable(), false)
	lights.surface(city, Vector2i(64, 64), 0, 2, Callable(), false)
	assert(lights.surfaces.size() == CityLifeController.MAX_FIGURES and lights.surfaces.has(Vector4i.ZERO),
		"The direct GPU cache must fit an all-car working set without unbounded retention")
	assert(oldest.texture == null, "Direct array uploads must not allocate a duplicate texture")
	assert(lights.surface(city, Vector2i.ZERO, 0, 0).texture != null, "A later texture caller must upgrade the cached image lazily")


func _check_network_search() -> void:
	var city := CityState.from_document(EmptyCityTemplate.create(128))
	for id in 256:
		city.set_building_id(id / 16, id % 16, id)
	for area in [Rect2i(0, 0, 128, 128), Rect2i(3, 2, 7, 11), Rect2i(0, 15, 16, 1)]:
		var expected: Array[Vector2i] = []
		for x in range(area.position.x, area.end.x):
			for y in range(area.position.y, area.end.y):
				if CityLifePaths.ports(city, Vector2i(x, y)) != 0:
					expected.append(Vector2i(x, y))
		var actual: Array[Vector2i] = []
		for index in CityLifePaths.candidate_indices(city, area.position, area.end - Vector2i.ONE):
			var tile := Vector2i(index / city.map_size, index % city.map_size)
			if CityLifePaths.ports(city, tile) != 0:
				actual.append(tile)
		assert(actual == expected, "Packed search must preserve every network id and original spawn order")
	assert(CityLifePaths.candidate_indices(city, Vector2i(129, 0), Vector2i(127, 127)).is_empty())
	var app := CityApplication.new()
	city.set_building_id(0, 0, BuildingTileIds.BUS_DEPOT)
	city.set_building_id(127, 127, BuildingTileIds.BUS_DEPOT)
	city.set_building_id(127, 126, BuildingTileIds.ROAD_STRAIGHT_1)
	var expected_bus := {}
	for x in city.map_size:
		for y in city.map_size:
			if city.building_id(x, y) != BuildingTileIds.BUS_DEPOT:
				continue
			for dx in range(-CityLifeController.BUS_RADIUS, CityLifeController.BUS_RADIUS + 1):
				for dy in range(-CityLifeController.BUS_RADIUS, CityLifeController.BUS_RADIUS + 1):
					var tile := Vector2i(x + dx, y + dy)
					if dx * dx + dy * dy <= CityLifeController.BUS_RADIUS * CityLifeController.BUS_RADIUS and CityLifePaths.ports(city, tile) != 0:
						expected_bus[tile] = true
	app.city_life._refresh_bus_area(city)
	assert(app.city_life._bus_tiles == expected_bus, "Packed depot search changed decorative bus coverage at map edges")
	city.set_building_id(127, 127, 0)
	app.city_life._refresh_bus_area(city)
	assert(not app.city_life._bus_tiles.has(Vector2i(127, 126)), "A removed depot retained its coverage")
	app.free()


func _check_incremental_eviction() -> void:
	var canvas := CityLifeCanvas.new()
	canvas.source_bounds = Rect2i(0, 0, 100, 100)
	var visible := Vector3i(0, 0, 0)
	for i in 4200:
		var key := Vector3i(i, 0, 0)
		canvas._occluders[key] = []
		canvas._occluder_bounds[key] = Rect2i(0 if i == 0 else 2000 + i, 0, 64, 48)
		canvas.lights.roads[key] = []
	canvas._trim_working_set()
	assert(canvas._occluders.has(visible) and canvas.lights.roads.has(visible), "Eviction discarded visible masks")
	assert(canvas._occluders.size() == 4200 - 64, "A cache overflow caused a global clear")
	for i in 5:
		canvas._trim_working_set()
	assert(canvas._occluders.size() <= 4096 and canvas._occluders.size() > 4000)
	canvas.free()


func _check_publication_budget() -> void:
	var worker := CityRegionCache.RegionWorker.new()
	for i in 3:
		var region := CityGpuRegionResult.new()
		region.atlas_image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
		worker.outbox.append(region)
	assert(worker.take_regions(4, 64 * 64 * 4).size() == 1)
	assert(worker.has_regions(), "Byte budget dropped unpublished regions")
	assert(worker.take_regions(4, 1).size() == 1, "One indivisible upload must make progress")
	assert(worker.take_regions(4, 1).size() == 1 and not worker.has_regions())
	var budget := VisualWorkBudget.new()
	budget.begin_frame(0.04)
	assert(budget.allowance_usec < 1500)
	budget.upload_bytes = VisualWorkBudget.UPLOAD_LIMIT
	assert(not budget.available())


func _check_zoom_banks() -> void:
	var canvas := CityLifeCanvas.new()
	var source := RefCounted.new()
	var key := Vector3i(4, 5, 0)
	var medium: Array = [7, 1, source, 1, 2]
	var large: Array = [7, 1, source, 2, 2]
	canvas._select_occlusion_bank(medium, 1)
	canvas._occluders[key] = []
	canvas._occluder_bounds[key] = Rect2i(100, 100, 64, 48)
	var original := canvas.lights
	canvas._select_occlusion_bank(large, 1)
	assert(canvas._occluders.is_empty() and canvas.lights != original)
	canvas._select_occlusion_bank(medium, 1)
	assert(canvas._occluders.has(key) and canvas.lights == original, "Returning to an unchanged artwork size must reuse masks and receivers")
	var rotated := medium.duplicate()
	rotated.append(1)
	canvas._select_occlusion_bank(rotated, 1)
	assert(canvas.lights != original and canvas._occluders.is_empty(), "Different directions must not share projected masks")
	canvas._select_occlusion_bank(medium, 1)
	assert(canvas.lights == original and canvas._occluders.has(key), "Returning to a direction discarded its figure masks")
	canvas._select_occlusion_bank(large, 1)
	canvas.invalidate_occlusion([Rect2i(100, 100, 64, 48)])
	canvas._select_occlusion_bank(medium, 1)
	assert(not canvas._occluders.has(key), "Edits must also invalidate hidden artwork sizes")
	for i in 12:
		original.surfaces[Vector4i(i, 0, 0, 0)] = {}
	canvas._select_occlusion_bank(large, 1)
	canvas._trim_inactive_banks(0)
	assert(original.surfaces.size() == 4, "Inactive memory reclamation must be bounded per publication")
	canvas._trim_inactive_banks(0)
	assert(original.surfaces.is_empty())
	canvas._select_occlusion_bank(medium, 1)
	for i in 12:
		var overlapping := Vector3i(i, 0, 0)
		canvas._occluders[overlapping] = []
		canvas._occluder_bounds[overlapping] = Rect2i(100, 100, 64, 48)
	canvas._select_occlusion_bank(large, 1)
	canvas._trim_inactive_banks(0)
	canvas._select_occlusion_bank(medium, 1)
	assert(canvas._occluders.is_empty() and canvas._occluder_bounds.is_empty(),
		"Evicting overlapping inactive masks must tolerate neighbours removed in the same batch")
	canvas._select_occlusion_bank([8, 1, source, 1, 2], 1)
	assert(canvas._occlusion_banks.size() == 1 and canvas.lights != original, "A replacement city must not retain former artwork banks")
	canvas.free()


func _check_source_invalidation() -> void:
	var canvas := CityLifeCanvas.new()
	var sources: Array[RefCounted] = [RefCounted.new(), RefCounted.new(), RefCounted.new()]
	var signatures: Array[Array] = [[7, 1, sources[0], 1, 1, 0], [7, 1, sources[1], 2, 1, 0], [7, 1, sources[2], 1, 1, 1]]
	var key := Vector3i(64, 64, 0)
	var area := Rect2i(100, 100, 64, 48)
	for signature in signatures:
		canvas._select_occlusion_bank(signature, 1)
		canvas._occluders[key] = []
		canvas._occluder_bounds[key] = area
	# A new direction's initial publication cannot invalidate any retained bank.
	canvas.invalidate_occlusion([area], RefCounted.new())
	for signature in signatures:
		canvas._select_occlusion_bank(signature, 1)
		assert(canvas._occluders.has(key), "An unrelated source discarded a retained mask")
	# A hidden source can publish an edit while another view is selected.
	canvas.invalidate_occlusion([area], sources[0])
	for index in signatures.size():
		canvas._select_occlusion_bank(signatures[index], 1)
		assert(canvas._occluders.has(key) == (index != 0), "Source-local publication invalidated the wrong view")
	# The other orientation must observe its own later publication of that edit.
	canvas.invalidate_occlusion([area], sources[2])
	canvas._select_occlusion_bank(signatures[2], 1)
	assert(not canvas._occluders.has(key))
	canvas._select_occlusion_bank(signatures[1], 1)
	assert(canvas._occluders.has(key))
	canvas.invalidate_occlusion([area])
	assert(not canvas._occluders.has(key), "Unscoped invalidation must still clear every view")
	canvas.free()
