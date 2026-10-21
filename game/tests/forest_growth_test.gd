extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	assert(not VisualEnhancementOptions.normalize({}).tree_growth_enabled)
	var city := _fixture()
	var original := city.buildings.duplicate()
	city.set_age_in_days(8 * CityCalendar.DAYS_PER_YEAR)
	assert(ForestGrowth.advance(city, 0, false).is_empty() and city.buildings == original)
	var twin := CityState.from_document(city.document.duplicate_document())
	var changed := ForestGrowth.advance(city, 0, true)
	assert(not changed.is_empty())
	assert(ForestGrowth.advance(twin, 0, true) == changed and city.buildings == twin.buildings,
		"Identical calendar and tiles must give identical growth without random state")
	assert(city.building_id(8, 8) > BuildingTileIds.TREES_3, "Existing forests become denser")
	assert(city.building_id(7, 8) == BuildingTileIds.TREE_FIRST, "Established forests colonize adjacent free tiles")
	assert(city.building_id(6, 8) == 0, "Saplings cannot cascade across multiple tiles")
	assert(city.building_id(8, 7) == 0 and city.building_id(9, 8) == 0, "Water and zones remain protected")
	assert(city.building_id(8, 9) == 0x1d, "Roads remain intact")
	assert(city.building_id(10, 9) == 0, "Underground infrastructure remains protected")
	assert(ForestGrowth.advance(city, city.age_in_days(), true).is_empty(), "No growth on rendering frames or replayed dates")
	var saved := city.document.serialize()
	assert(saved.ok)
	var loaded := Sc2File.new()
	assert(loaded.parse(saved.data))
	assert(CityState.from_document(loaded).buildings == city.buildings, "Grown forest survives saving and loading")
	_check_shared()
	_check_presentation()
	print("PASS: deterministic optional saved forest growth, density, adjacent spread, protected land and shared ownership composition")
	quit()


func _check_presentation() -> void:
	var city := _fixture()
	var before := CityState.from_document(city.document.duplicate_document())
	var source := CityMapSource.new(Vector2i(2048, 2048))
	for x in 4:
		for y in 4:
			source.tiles.append(CityMapSource.TileEntry.new(Vector2(x * 512, y * 512), Vector2(512, 512), null))
	var fade := CityTreeGrowthFade.new()
	fade.observe(city, before, source, [1, 0], 512, true)
	assert(fade.pending.is_empty(), "Loading must not fade an existing city")
	city.set_age_in_days(8 * CityCalendar.DAYS_PER_YEAR)
	ForestGrowth.advance(city, 0, true)
	var saved := city.document.serialize().data
	fade.observe(city, before, source, [1, 0], 512, true)
	assert(not fade.pending.is_empty(), "Both denser forest and new saplings must arm visible regions")
	assert(CityTreeGrowthFade.grows(0, 6) and CityTreeGrowthFade.grows(6, 7))
	assert(not CityTreeGrowthFade.grows(7, 6) and not CityTreeGrowthFade.grows(6, 29))
	fade.advance(CityTreeGrowthFade.PENDING_SECONDS + 1.0)
	assert(fade.pending.is_empty(), "Unpublished regions must not leave unbounded pending work")
	fade.observe(city, before, source, [1, 0], 512, true)
	fade.observe(city, before, source, [1, 1], 512, true)
	assert(fade.pending.is_empty(), "A rotated/resized cache must not reuse old screen geometry")
	fade.observe(city, before, source, [1, 1], 512, false)
	assert(fade.pending.is_empty() and fade.active.is_empty(), "Disabled/editor views settle immediately")
	assert(city.document.serialize().data == saved, "The visual transition must not change save or simulation state")
	fade.free()


func _fixture() -> CityState:
	var city := CityState.from_document(EmptyCityTemplate.create(16))
	city.set_building_id(8, 8, BuildingTileIds.TREES_3)
	city.set_building_id(10, 8, BuildingTileIds.TREE_LAST)
	city.set_tile_flag(8, 7, Sc2TileFlags.WATER, true)
	city.set_zone_id(9, 8, 1)
	city.set_building_id(8, 9, 0x1d)
	city.set_underground_id(10, 9, 1)
	return city


func _check_shared() -> void:
	var document := Sc2xDocument.create_empty(32, "Forest test").document
	var seed_city := CityState.from_document(document)
	for x in range(8, 13):
		seed_city.set_building_id(x, 8, BuildingTileIds.TREE_LAST)
	var world := SharedWorld.new()
	assert(world.open(document))
	var host := "a".repeat(48)
	var guest := "b".repeat(48)
	assert(world.add_player(host).is_empty() and world.add_player(guest).is_empty())
	var guest_tile := world.city.index_of(10, 7)
	world.owners[guest_tile] = 2
	world.municipalities[guest].city.set_building_id(10, 7, 0x1d)
	world.city.set_age_in_days(8 * CityCalendar.DAYS_PER_YEAR)
	var before := world.revision
	world._grow_forest(0)
	assert(world.revision == before, "Host default leaves forests unchanged")
	world.tree_growth_enabled = true
	world._grow_forest(0)
	assert(world.revision > before)
	assert(world.municipalities[guest].city.building_id(10, 7) == 0x1d, "Growth cannot overwrite another municipality")
	var snapshot := world.snapshot_for(guest)
	var restored := Sc2File.new()
	assert(restored.parse(Marshalls.base64_to_raw(snapshot.city)))
	var view := CityState.from_document(restored)
	assert(view.building_id(8, 7) >= BuildingTileIds.TREE_FIRST and view.building_id(8, 7) <= BuildingTileIds.TREE_LAST,
		"Neutral forest growth reaches client snapshots")
	assert(view.building_id(10, 7) == 0x1d)
