extends SceneTree
## Fixed sources, native RS art and lights, legacy settings, stable choices and UI.
@warning_ignore_start("integer_division")
var folder := "user://building-variants-%d" % Time.get_ticks_usec()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	assert(DirAccess.make_dir_recursive_absolute(folder) == OK)
	var graphics := FixtureGraphics.pack()
	var original := GameAssetSource.new()
	original.assets = OriginalGameAssets.new()
	assert(graphics.apply_to(original.assets))
	original.import_revision = ImportedPackRevision.UNRECORDED
	original.source_platform = "Windows"
	assert(BuildingVariants.supports_source(original))
	var rs := GraphicsPack.load_root("res://../packs/standalone-graphics/graphics")
	assert(rs.error.is_empty(), rs.error)
	var loaded := BuildingVariants.new()
	loaded._bundled = rs
	loaded._bundled_root = PackLibrary.bundled_folder("graphics")
	var options := BuildingVariants.normalize({"enabled":true,"seed":17,"original_weight":40,"rs_weight":60,
		"packs":[{"path":"must-never-be-opened.mif","weight":100}]})
	assert(not options.has("packs"))
	assert(BuildingVariants.normalize({"enabled":true,"packs":[{"path":"old.mif"}]}).rs_weight == 50)
	loaded.load_options(options,original)
	loaded.prepare_families(graphics.large_sprites,graphics.small_medium_sprites,options)
	assert(loaded.packs.size() == 1 and loaded.packs[0].families.size() > 50)
	var large := loaded.apply_to(graphics.large_sprites,options)
	var small := loaded.apply_to(graphics.small_medium_sprites,options)
	assert(large.find_sprite(1112) == graphics.large_sprites.find_sprite(1112))
	assert(large.building_original_weight == 40)
	for id in [198,199,200,221,222,223]:
		for view in 3:
			var archive := large if view == 2 else small
			var sprite_id: int = view * 500 + id
			assert(not archive.building_variants.has(sprite_id))
			assert(archive.find_sprite(sprite_id) == (graphics.large_sprites if view == 2 else graphics.small_medium_sprites).find_sprite(sprite_id))
	for pair in [[large,rs.large_sprites],[small,rs.small_medium_sprites]]:
		var mixed: Sc2SpriteArchive = pair[0]
		var own: Sc2SpriteArchive = pair[1]
		CityBrightmaps.load_archive(mixed,"","large" if mixed == large else "small_medium")
		for id: int in mixed.building_variants:
			var v := BuildingVariants.FIRST + id
			assert(mixed.building_variants[id] == PackedInt64Array([v,60]))
			assert(mixed.high_resolution[v] == own.high_resolution[id])
			assert(mixed.visual_emission[v].get_size() == Vector2i(mixed.find_sprite(v).width,mixed.find_sprite(v).height))
			assert(mixed.high_resolution[v].emission == own.high_resolution[id].emission)
			assert(mixed.high_resolution[v].animation == own.high_resolution[id].animation)
		for view in ([2] if mixed == large else [0,1]):
			var request := CityGpuBuildContext.artwork_request(mixed, view * 500)
			for original_id: int in mixed.building_variants:
				var variant_id := BuildingVariants.FIRST + original_id
				if original_id / 500 != view:
					assert(not request.hd_sprites.has(variant_id))
					continue
				assert(request.hd_sprites[variant_id] == own.high_resolution[original_id].image)
				if own.high_resolution[original_id].animation != null:
					assert(request.hd_animations[variant_id] == own.high_resolution[original_id].animation)
					assert(request.hd_frames[variant_id] == own.high_resolution[original_id].frames)
	_check_painters(large,small)
	_check_rotations(large)
	var save := AppSettingsStore.SaveOptions.new()
	save.building_mix = options
	assert(AppSettingsStore.save_values(0,0,false,folder.path_join("settings.cfg"),save) == OK)
	assert(AppSettingsStore.load_values(folder.path_join("settings.cfg")).building_mix == options)
	var restricted := options.duplicate(true)
	restricted.categories = [0]
	loaded.prepare_families(graphics.large_sprites,graphics.small_medium_sprites,restricted)
	var homes := loaded.apply_to(graphics.large_sprites,restricted)
	assert(homes.building_variants.has(1112) and not homes.building_variants.has(1124))
	# An incomplete family must fall back at every zoom.
	var partial := Sc2SpriteArchive.combine([rs.small_medium_sprites])
	partial.entries_by_id.erase(112)
	loaded.packs[0].small = partial
	loaded.prepare_families(graphics.large_sprites,graphics.small_medium_sprites,options)
	assert(not loaded.packs[0].families.has(112))
	for spec in [{"enabled":false},{"enabled":true,"rs_weight":0},{"enabled":true,"rs_weight":0,"original_weight":0}]:
		var normalized := BuildingVariants.normalize(spec)
		loaded.load_options(normalized,original)
		assert(loaded.apply_to(graphics.large_sprites,normalized) == graphics.large_sprites)
	original.import_revision = ImportedPackRevision.NOT_IMPORTED
	loaded.load_options(options,original)
	assert(loaded.packs.is_empty() and not loaded.notices.is_empty())
	assert(not BuildingVariants.supports_source(null))
	var dialog := BuildingMixPanel.new()
	root.add_child(dialog)
	dialog.show_values(options)
	assert(not dialog.has_method("add_paths"))
	var applied := []
	dialog.applied.connect(func(value: Dictionary) -> void: applied.append(value))
	dialog.options.rs_weight = 25
	assert(applied.is_empty())
	(dialog.body.get_child(-1) as Button).pressed.emit()
	assert(applied.size() == 1 and applied[0].rs_weight == 25 and not applied[0].has("packs"))
	assert(applied[0].seed == options.seed + 1)
	(dialog.body.get_child(-1) as Button).pressed.emit()
	assert(applied[1].seed == options.seed + 2)
	dialog.options.enabled = false
	(dialog.body.get_child(-1) as Button).pressed.emit()
	assert(applied[2].seed == options.seed + 2)
	dialog.show_values({},PackedStringArray(),false)
	assert((dialog.body.get_child(0) as CheckBox).disabled)
	dialog.queue_free()
	await process_frame
	print("PASS: fixed SC2000+RS sources, native artwork/emission/animation, migration, weights, zoom/rotation, CPU/GPU, fallbacks and staged menu")
	quit()


func _check_painters(large: Sc2SpriteArchive, small: Sc2SpriteArchive) -> void:
	var city := CityState.from_document(EmptyCityTemplate.create(128))
	var tiles := PackedInt32Array()
	for x in range(50,78,4):
		city.set_building_id(x,64,183)
		city.set_building_corners(x,64,0x80)
		tiles.append(x)
		tiles.append(64)
	var chosen: Array[int] = []
	for view in 3:
		var sprites := large if view == 2 else small
		var context := CityGpuBuildContext.new()
		assert(context.prepare(city,Sc2Palette.index_encoding(),sprites,view).is_empty())
		var records: PackedInt64Array = context.builder.tile_draws(tiles).records
		var found: Array[int] = []
		for at in range(0,records.size(),CityGpuBuildContext.RECORD_SIZE):
			if records[at+5] % 500 == 183:
				found.append(records[at+5]-view*500)
		assert(found.size() == 7)
		if view == 0:
			chosen = found
		else:
			assert(chosen == found,"Zoom changed the selected family")
		var bounds := Rect2i(Vector2i(records[0],records[1])-Vector2i(8,8),Vector2i(250,160))
		var gpu := context.render(city,Sc2Palette.index_encoding(),sprites,bounds,view,CityViewMode.Mode.CITY,true,true,0,-1,true,true)
		assert(gpu.ok,gpu.error)
		var cpu := CityRegionRenderer.render(city,Sc2Palette.index_encoding(),sprites,bounds,view)
		assert(cpu.ok,cpu.error)
		var painted := CityGpuDrawList.paint(CityGpuDrawList.from_records(gpu.draw_records,gpu.draw_images).draws,bounds,Color.TRANSPARENT)
		assert(painted.get_data() == cpu.image.get_data(),"CPU and GPU use different variant pixels")
		var before := context.tile_builds
		context.render(city,Sc2Palette.index_encoding(),sprites,bounds,view,CityViewMode.Mode.CITY,true,true,0,context.atlas_revision,false,true)
		assert(context.tile_builds == before,"Unchanged render rebuilt variant tiles")


func _check_rotations(sprites: Sc2SpriteArchive) -> void:
	var city := CityState.from_document(EmptyCityTemplate.create(128))
	var positions: Array[Vector2i] = []
	for x in range(50,78,4):
		for dx in 3:
			for dy in 3:
				var point := Vector2i(x+dx,60+dy)
				positions.append(point)
				city.set_building_id(point.x,point.y,183)
		city.set_building_corners(x,60,0x10)
		city.set_building_corners(x+2,60,0x20)
		city.set_building_corners(x+2,62,0x40)
		city.set_building_corners(x,62,0x80)
	var baseline: Array[int] = []
	for turn in 4:
		var context := CityGpuBuildContext.new()
		assert(context.prepare(city,Sc2Palette.index_encoding(),sprites,2).is_empty())
		var choices: Array[int] = []
		for object in 7:
			var tiles := PackedInt32Array()
			for i in range(object*9,object*9+9):
				tiles.append(positions[i].x)
				tiles.append(positions[i].y)
			var records: PackedInt64Array = context.builder.tile_draws(tiles).records
			for at in range(0,records.size(),CityGpuBuildContext.RECORD_SIZE):
				if records[at+5] % 500 == 183:
					choices.append(records[at+5])
		assert(choices.size() == 7,"Multi-cell buildings must draw once each")
		if turn == 0:
			baseline = choices
		else:
			assert(choices == baseline,"City rotation changed the building variants")
		assert(CityRotationCommand.apply(city,false).ok)
		for i in positions.size():
			positions[i] = CityRotationCommand.rotate_point(positions[i],128,false)
