extends SceneTree
## The complete Expanded document, tools, rotation and authored graphics path.

var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: " + message)


func _run() -> void:
	var document := Sc2xDocument.create_empty(64, "Expanded test").document
	var city := CityState.from_document(document)
	check(not ExpandedRules.available(city, 0), "Classic never offers Expanded rewards")
	var before := document.content_snapshot()
	NativeSimulationBridge.run("expanded.unlock", city, null, null, null)
	check(before == document.content_snapshot(), "Classic unlock is a no-op")
	check(ExpandedRules.enable(document).is_empty(), "Expanded conversion")
	city = CityState.from_document(document)
	check(city.is_valid(), city.load_error)
	city.set_funds(1000000)
	document.set_misc_u32(Sc2MiscLayout.NORMAL_POPULATION, 4000000)
	NativeSimulationBridge.run("expanded.unlock", city, null, null, null)
	var rng := SimRandom.new(123)
	var lfsr := SimLfsrRandom.new(17)
	var positions: Array[Vector2i] = [Vector2i(6, 6), Vector2i(16, 6), Vector2i(26, 6), Vector2i(36, 6),
		Vector2i(6, 20), Vector2i(16, 20), Vector2i(26, 20), Vector2i(36, 20)]
	for kind in 8:
		check(ToolAvailability.is_available(city, 5, 9 + kind), "reward unlocked")
		var state := ToolEditState.normal(city, CityViewMode.Mode.CITY, 5, 9 + kind)
		check(state.enabled and state.area == ExpandedRules.AREAS[kind], "tool cursor and dispatch")
		var cost := city.funds()
		var built := BuildingCommand.apply(city, 5, 9 + kind, positions[kind], lfsr, rng)
		check(built.ok, "place %s: %s" % [ExpandedRules.NAMES[kind], built.error])
		check(city.funds() == cost - ExpandedRules.COSTS[kind], "authoritative cost")
		check(built.tile_indices.size() == ExpandedRules.AREAS[kind] * ExpandedRules.AREAS[kind], "complete footprint")
		check(not ToolAvailability.is_available(city, 5, 9 + kind), "one instance")
		check(ExpandedRules.at(city, positions[kind]) == kind, "query anywhere in parcel")
		if kind == 7:
			check(BuildingCommand.undo(city, built, lfsr, rng).ok, "large reward undo")
			check(ExpandedRules.available(city, kind), "undo restores availability")
			check(BuildingCommand.apply(city, 5, 9 + kind, positions[kind], lfsr, rng).ok, "rebuild")
	check(rng.state == 123 and lfsr.state == 17, "placement does not consume Classic RNG")
	var records := ExpandedRules.render_records(city)
	for turn in 4:
		check(CityRotationCommand.apply(city, false).ok, "rotate large rewards")
		check(CityState.from_document(document).is_valid(), "rotated identity matches occupancy")
	check(records == ExpandedRules.render_records(city), "four turns restore footprints")
	var serialized := document.serialize()
	check(serialized.ok, "serialize Expanded SC2X")
	var loaded := Sc2File.new()
	check(loaded.parse(serialized.data), "parse Expanded SC2X")
	check(loaded.find_chunk("XEXP") != null, "extension survives save")
	var loaded_city := CityState.from_document(loaded)
	check(loaded_city.is_valid(), loaded_city.load_error)
	check(records == ExpandedRules.render_records(loaded_city), "all eight identities survive load")
	var removed := DemolishCommand.apply_path(city, 0, 0, [positions[7]], rng)
	check(removed.ok and removed.tile_indices.size() == 36, "demolition removes whole parcel")
	check(DemolishCommand.undo(city, removed, rng).ok, "demolition undo restores identity")
	var pack := FixtureGraphics.pack()
	ExpandedGraphics.apply(pack.large_sprites)
	ExpandedGraphics.apply(pack.small_medium_sprites)
	CityBrightmaps.load_archive(pack.large_sprites, "", "large")
	for view in 3:
		var archive := pack.large_sprites if view == 2 else pack.small_medium_sprites
		var builder := CityGpuBuildContext.new()
		var render_error := builder.prepare(city, pack.palette, archive, view)
		check(render_error.is_empty(), "render configured: " + render_error)
		var rendered := builder.builder.build(Rect2i(0, 0, 2112, 1920), -1)
		check(not rendered.has("error"), "native renderer accepts large rewards")
		for kind in 8:
			var id := ExpandedRules.FIRST_SPRITE + view * 500 + kind
			check(archive.find_sprite(id) != null and archive.visual_emission.has(id), "day and emission registered")
	if loaded.find_chunk("XEXP") != null:
		loaded.find_chunk("XEXP").set_decoded_payload(PackedByteArray([1]))
	check(not CityState.from_document(loaded).is_valid(), "malformed extension rejected")
	print("expanded_city_test: %d failures" % failures)
	quit(0 if failures == 0 else 1)
