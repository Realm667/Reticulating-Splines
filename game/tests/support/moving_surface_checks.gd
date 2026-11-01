extends RefCounted
## Real artwork and native static records, sampled across complete tile steps.

@warning_ignore_start("integer_division")


const DIRECTIONS := [Vector2i.UP, Vector2i(1, -1), Vector2i.RIGHT, Vector2i.ONE,
	Vector2i.DOWN, Vector2i(-1, 1), Vector2i.LEFT, Vector2i(-1, -1)]


static func check_life(graphics: GraphicsPack) -> void:
	var app := application(graphics)
	app.map_view = CityMapControl.new()
	var sprites := CityLifeSprites.new()
	for view in [2, 1, 0]:
		app.visual_preparation.preparing_view = view
		var directions := [0, 1, 2, 3] if view == 2 else [view]
		for direction in directions:
			for ramp in [false, true]:
				var city := route(direction, false, ramp)
				prepare(app, graphics, city, view)
				var canvas := CityLifeCanvas.new()
				var masks := canvas._candidates(app, Vector2i(16, 16), direction)
				for walking in [false, true]:
					var sprite := sprites.sprite(walking, 0, (direction + 2) % 4, 0)
					for frame in 17:
						var point := CityLifePaths.point(city, Vector2i(16, 16), direction, (direction + 2) % 4, frame / 16.0, walking)
						var origin := Vector2i(point.round()) - Vector2i(sprite.get_width() / 2, sprite.get_height() - 1)
						assert(CityLifeCanvas.visible_sprite(sprite, origin, masks).get_data() == sprite.get_data(),
							"Ground cut a %s at view %d direction %d ramp %s frame %d" % ["pedestrian" if walking else "car", view, direction, ramp, frame])
				canvas.free()
	# A real foreground building must still hide the figure; this is not a
	# blanket disabling of masks. Existing bridge tests cover tower openings.
	var city := route(0, false, false)
	city.set_building_id(16, 17, 158)
	city.set_building_corners(16, 17, 0x80)
	app.visual_preparation.preparing_view = 2
	prepare(app, graphics, city, 2)
	var canvas := CityLifeCanvas.new()
	var masks := canvas._candidates(app, Vector2i(16, 16), 0)
	var hidden := 0
	var sprite := sprites.sprite(false, 0, 2, 0)
	for frame in 17:
		var point := CityLifePaths.point(city, Vector2i(16, 16), 0, 2, frame / 16.0, false)
		var origin := Vector2i(point.round()) - Vector2i(sprite.get_width() / 2, sprite.get_height() - 1)
		hidden += int(CityLifeCanvas.visible_sprite(sprite, origin, masks).get_data() != sprite.get_data())
	assert(hidden > 0, "The foreground building must still cover passing cars")
	canvas.free()
	app.map_view.free()
	app.free()


static func check_traffic(graphics: GraphicsPack) -> void:
	var app := application(graphics)
	for direction in 4:
		for kind in [0, 1, 2]:
			var city := route(direction, true, kind == 2, kind == 1)
			prepare(app, graphics, city, 2)
			for type in [10, 11]:
				check_body(app, graphics.large_sprites, city, 2, type, CityLifePaths.DIRECTIONS[direction], direction)
	for view in [2, 1, 0]:
		var directions := range(8) if view == 2 else [view * 2]
		for direction in directions:
			var city := route(0, false, false)
			prepare(app, graphics, city, view)
			var archive := graphics.large_sprites if view == 2 else graphics.small_medium_sprites
			for type in [1, 2]:
				if view < IsometricConstants.THING_MINIMUM_VIEW[type]:
					continue
				# Ground-level takeoff, a fractional climb and ordinary low flight.
				for height in [0, 1, 4] if view == 2 else [0]:
					check_body(app, archive, city, view, type, DIRECTIONS[direction], direction, height)
	# Higher foreground ground must still cover a low aircraft. Sample both
	# front edges: the aircraft silhouette need not overlap each hill's top.
	var hidden := 0
	for tile in [Vector2i(16, 17), Vector2i(17, 16), Vector2i(17, 17)]:
		var city := route(0, false, false)
		city.set_land_altitude(tile.x, tile.y, 1)
		prepare(app, graphics, city, 2)
		write_thing(city, 1, {"type": 1, "x": 16, "y": 16, "z": 0, "direction": 2, "px": 8, "py": 8})
		var motion := CityTrafficMotion.new()
		motion.observe(city, VisualEnhancementOptions.normalize({}))
		for source in CityIsometricRenderer.dynamic_draw_commands(city, graphics.large_sprites):
			if source.shadow:
				continue
			var resource := app.moving_sprites.dynamic_sprite_resource(graphics.large_sprites, source.sprite_id, source.flip, 1)
			var position := source.position + Vector2i(motion.display_offset(source, 1).round())
			var mask := app.moving_sprites._dynamic_occluder_image(graphics.large_sprites, 1, position, resource.native_size,
				source.depth_order, false, 1, null, -1, PackedInt32Array(), false, false, motion.aircraft_altitude(1, city))
			hidden += CityIsometricRenderer.occlude_dynamic_with_mask(resource.image, mask, position).occluded_pixels
	assert(hidden > 0, "Higher terrain must still cover a low-flying aircraft")
	app.free()


static func check_body(app: CityApplication, archive: Sc2SpriteArchive, city: CityState,
		view: int, type: int, step: Vector2i, direction: int, height := 0) -> void:
	var divisor: int = IsometricGeometry.view_configuration(view).divisor
	for smooth in [false, true]:
		city.set_text_overlay_id(16 + step.x, 16 + step.y, 0)
		write_thing(city, 1, {"type": type, "x": 16, "y": 16, "z": height,
			"direction": direction, "px": 8, "py": 8})
		var motion := CityTrafficMotion.new()
		if smooth:
			motion.observe(city, VisualEnhancementOptions.normalize({}))
		city.set_text_overlay_id(16, 16, 0)
		write_thing(city, 1, {"x": 16 + step.x, "y": 16 + step.y, "z": height + int(height == 1)})
		if smooth:
			motion.observe(city, VisualEnhancementOptions.normalize({}))
		var bodies := 0
		for source in CityIsometricRenderer.dynamic_draw_commands(city, archive, view):
			if source.shadow:
				continue
			bodies += 1
			var resource := app.moving_sprites.dynamic_sprite_resource(archive, source.sprite_id, source.flip, divisor)
			assert(resource != null)
			for frame in 17 if smooth else 1:
				var command := motion.draw_command(source, divisor, city.map_size)
				var position := Vector2i((Vector2(source.position * divisor) + motion.display_offset(source, divisor)).round())
				var supports := command.train_support_orders
				if source.train and supports.is_empty():
					supports = PackedInt32Array([command.depth_order])
				var mask := app.moving_sprites._dynamic_occluder_image(archive, divisor, position, resource.native_size,
					command.depth_order, source.train, 1, null, -1, supports, false, false, motion.aircraft_altitude(1, city))
				var result := CityIsometricRenderer.occlude_dynamic_with_mask(resource.image, mask, position)
				assert(result.occluded_pixels == 0, "Ground cut %d pixels from type %d view %d direction %d height %d smooth %s frame %d" % [result.occluded_pixels, type, view, direction, height, smooth, frame])
				motion.advance(0.01875 if source.train else 0.0125)
		assert(bodies == 1, "The regression fixture must draw the moving body")
	city.set_text_overlay_id(16 + step.x, 16 + step.y, 0)


static func application(graphics: GraphicsPack) -> CityApplication:
	assert(graphics.error.is_empty(), graphics.error)
	var app := CityApplication.new()
	app.asset_state.palette = graphics.palette
	app.asset_state.palette_index_encoding = Sc2Palette.index_encoding()
	app.asset_state.large_sprites = graphics.large_sprites
	app.asset_state.small_medium_sprites = graphics.small_medium_sprites
	return app


static func write_thing(city: CityState, record: int, values: Dictionary) -> void:
	var chunk := city.document.find_chunk("XTHG")
	var data := chunk.decoded_payload.duplicate()
	for field in values:
		ThingData.write(data, record * CityState.THING_RECORD_SIZE + ThingRecord.FIELDS.find(field), values[field])
	assert(chunk.set_decoded_payload(data))
	var thing := city.thing(record)
	city.set_text_overlay_id(thing.x, thing.y, OverlayData.thing_id(record))


static func prepare(app: CityApplication, graphics: GraphicsPack, city: CityState, view: int) -> void:
	app.document_state.city = city
	var archive := graphics.large_sprites if view == 2 else graphics.small_medium_sprites
	var divisor: int = IsometricGeometry.view_configuration(view).divisor
	var context := CityGpuBuildContext.new()
	assert(context.prepare(city, Sc2Palette.index_encoding(), archive, view,
		CityViewMode.Mode.CITY, true, true, true, 0, false).is_empty())
	var records := context.draw_records(Rect2i(Vector2i(360, 520) / divisor, Vector2i(400, 400) / divisor))
	app.moving_sprites.set_static_occlusion_commands(CityGpuBuildContext.foreground_commands(records.records), view)


static func route(direction: int, rail: bool, ramp: bool, bridge := false) -> CityState:
	var city := CityState.from_document(EmptyCityTemplate.create(32))
	var axis := direction % 2
	for x in 32:
		for y in 32:
			var coordinate := x if axis == 1 else y
			city.set_land_altitude(x, y, 1 if ramp and coordinate > 16 else 0)
			city.set_terrain_id(x, y, (3 if axis == 1 else 4) if ramp and coordinate == 16 else 0)
	for coordinate in range(10, 23):
		var tile := Vector2i(coordinate, 16) if axis == 1 else Vector2i(16, coordinate)
		var id := (BuildingTileIds.RAIL_STRAIGHT_2 if axis == 1 else BuildingTileIds.RAIL_STRAIGHT_1) if rail \
			else (BuildingTileIds.ROAD_STRAIGHT_2 if axis == 1 else BuildingTileIds.ROAD_STRAIGHT_1)
		if ramp and coordinate == 16:
			id = (BuildingTileIds.RAIL_SLOPE_1 if axis == 1 else BuildingTileIds.RAIL_SLOPE_2) if rail \
				else (BuildingTileIds.ROAD_SLOPE_1 if axis == 1 else BuildingTileIds.ROAD_SLOPE_2)
		if bridge:
			id = BuildingTileIds.RAIL_BRIDGE_PYLON if coordinate % 2 == 0 else BuildingTileIds.RAIL_BRIDGE
			city.set_water_altitude(tile.x, tile.y, 3)
			city.set_tile_flag(tile.x, tile.y, Sc2TileFlags.WATER, true)
			city.set_tile_flag(tile.x, tile.y, Sc2TileFlags.FLIPPED, axis == 1)
			city.set_terrain_id(tile.x, tile.y, TerrainTileIds.SURFACE_WATER_OPEN)
		city.set_building_id(tile.x, tile.y, id)
	return city
