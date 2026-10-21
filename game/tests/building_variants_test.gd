extends SceneTree
## Generated local MIF families: selection, persistence, fallbacks and both painters.
@warning_ignore_start("integer_division")
var folder := "user://building-variants-%d" % Time.get_ticks_usec()
const IDS := [13,112,124,132,147,183,198,208,209,214,215,224]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	assert(DirAccess.make_dir_recursive_absolute(folder) == OK)
	var graphics := FixtureGraphics.pack()
	var a := _write("a.mif", 174)
	var b := _write("b.mif", 120)
	var same := ScurkMif.from_archives([graphics.large_sprites,graphics.small_medium_sprites])
	assert(same.save_path(folder.path_join("same.mif")).ok)
	var options := BuildingVariants.normalize({"enabled":true,"packs":[{"path":a},{"path":b}]})
	var loaded := BuildingVariants.new()
	loaded.load_options(options)
	loaded.prepare_families(graphics.large_sprites,graphics.small_medium_sprites,options)
	assert(loaded.packs.size() == 2 and loaded.decoded_bytes < BuildingVariants.MAX_DECODED_BYTES)
	assert(loaded.packs[0].families.size() == IDS.size())
	var large := loaded.apply_to(graphics.large_sprites,options)
	var small := loaded.apply_to(graphics.small_medium_sprites,options)
	assert(large.building_variants.size() == IDS.size() and small.building_variants.size() == IDS.size()*2)
	assert(large.find_sprite(1112) == graphics.large_sprites.find_sprite(1112))
	CityBrightmaps.load_archive(large,"","large")
	for id: int in large.entries_by_id:
		if id >= BuildingVariants.FIRST:
			assert(not large.visual_emission.has(id), "A replacement inherited an original light mask")
	var reverse := options.duplicate(true)
	reverse.packs.reverse()
	var reordered := BuildingVariants.new()
	reordered.load_options(reverse)
	reordered.prepare_families(graphics.large_sprites,graphics.small_medium_sprites,reverse)
	assert(reordered.apply_to(graphics.large_sprites,reverse).building_variants == large.building_variants)
	var save := AppSettingsStore.SaveOptions.new()
	save.building_mix = options
	assert(AppSettingsStore.save_values(0,0,false,folder.path_join("settings.cfg"),save) == OK)
	assert(AppSettingsStore.load_values(folder.path_join("settings.cfg")).building_mix == options)
	_check_painters(large,small)
	_check_rotations(large)
	var restricted := options.duplicate(true)
	restricted.categories = [0]
	var only_homes := BuildingVariants.new()
	only_homes.load_options(restricted)
	only_homes.prepare_families(graphics.large_sprites,graphics.small_medium_sprites,restricted)
	var homes := only_homes.apply_to(graphics.large_sprites,restricted)
	assert(homes.building_variants.has(1112) and not homes.building_variants.has(1124))
	for spec in [{"enabled":false,"packs":[{"path":a}]},
		{"enabled":true,"packs":[{"path":folder.path_join("missing.mif")}]},
		{"enabled":true,"packs":[{"path":folder.path_join("same.mif")}]}]:
		var normalized := BuildingVariants.normalize(spec)
		var fallback := BuildingVariants.new()
		fallback.load_options(normalized)
		fallback.prepare_families(graphics.large_sprites,graphics.small_medium_sprites,normalized)
		assert(fallback.apply_to(graphics.large_sprites,normalized).building_variants.is_empty())
	# Missing small artwork rejects the whole family instead of changing at zoom.
	var partial := ScurkMif.load_path(a)
	partial.overrides.entries_by_id.erase(112)
	loaded.packs[0].mif = partial
	loaded.packs[0].families.clear()
	loaded.prepare_families(graphics.large_sprites,graphics.small_medium_sprites,options)
	assert(not loaded.packs[0].families.has(112))
	var dialog := BuildingMixDialog.new()
	root.add_child(dialog)
	dialog.open(options)
	dialog.add_paths(PackedStringArray([a,a]))
	dialog.add_paths(PackedStringArray([folder,folder.path_join("missing.mif"),folder.path_join("settings.cfg")]))
	assert(dialog.options.packs.size() == 2)
	assert(dialog.options.original_weight == 50 and dialog.options.packs[0].weight == 50)
	dialog.queue_free()
	await process_frame
	print("PASS: building family mixing, palette indices, weights, persistence, order, missing/incomplete/identical sets, CPU/GPU and menu")
	quit()


func _write(name: String, color: int) -> String:
	var archive := Sc2SpriteArchive.new()
	for view in 3:
		for building in IDS:
			var base := (FixtureGraphics.pack().large_sprites if view == 2 else FixtureGraphics.pack().small_medium_sprites).find_sprite(view*500+building)
			var pixels := PackedInt32Array()
			pixels.resize(base.width*(base.height+3))
			pixels.fill(color)
			pixels[0] = -1
			var entry := Sc2SpriteArchive.entry_from_indices(view*500+building,base.width,base.height+3,pixels)
			archive.entries.append(entry)
			archive.entries_by_id[entry.sprite_id] = entry
	var path := folder.path_join(name)
	assert(ScurkMif.from_archives([archive]).save_path(path).ok)
	return path


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
