extends SceneTree
## Load every native fallback asset without original-game data.

@warning_ignore_start("integer_division")

func _initialize() -> void:
	var folder := "res://../packs/standalone-graphics/graphics"
	var started := Time.get_ticks_msec()
	var pack := GraphicsPack.load_root(folder)
	assert(pack.error.is_empty(), pack.error)
	assert(pack.large_sprites.entries.size() == 499)
	assert(pack.small_medium_sprites.entries.size() == 998)
	assert(pack.visual_artwork == null, "RS must use the shared Visual Enhancements artwork")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("pack.json")))
	var animated := 0
	for record: Dictionary in manifest.master_sprites:
		var id := int(record.id)
		var entry := pack.large_sprites.find_sprite(id)
		assert(entry.width == int(record.logical_size[0]) and entry.height == int(record.logical_size[1]))
		var art: HdSprite = pack.large_sprites.high_resolution[id]
		var expected := Image.load_from_file(folder.path_join(record.png))
		expected.convert(Image.FORMAT_RGBA8)
		assert(art.image.get_data() == expected.get_data(), "Native artwork changed during load")
		assert(art.emission.get_size() == expected.get_size())
		assert(pack.small_medium_sprites.find_sprite(id - 500).height == (entry.height + 1) / 2)
		assert(pack.small_medium_sprites.find_sprite(id - 1000).height == (entry.height + 3) / 4)
		if record.has("animation"):
			animated += 1
			assert(art.frames == 8 and art.animation.get_height() == expected.get_height() * 8)
			assert(art.emission_animation.get_size() == art.animation.get_size())
	assert(animated == 118)
	assert(pack.scurk_graphics.patterns.size() == 42)
	for pixel in pack.scurk_graphics.patterns[0]:
		assert(pixel == 255, "SCURK solid brush lost its selected-color instruction")
	for pixel in pack.scurk_graphics.patterns[2]:
		assert(pixel == 0, "SCURK empty brush lost its empty instruction")
	CitySeasonColors.prepare(pack.large_sprites, pack.palette)
	for id in [1006,1256,1257,1269,1270,1284,1248,1082]:
		assert(pack.large_sprites.visual_seasons.has(id), "Missing seasonal material mask: %d" % id)
	assert(pack.large_sprites.find_sprite(1029).decode_indices().pixels.has(161), "Road lacks traffic placement material")
	var assets := OriginalGameAssets.new()
	assets.visual_artwork = VisualArtwork.new() # A previous custom pack must not leak into RS.
	assert(pack.apply_to(assets))
	assert(assets.large_sprites == pack.large_sprites and assets.visual_artwork == pack.visual_artwork)
	var app := CityApplication.new()
	app.asset_state.asset_source = GameAssetSource.new()
	app.asset_state.asset_source.assets = assets
	var clouds := CityVisualClouds.new(app)
	for index in 6:
		assert(clouds.artwork_atlas(index) == CityCloudSituations.ATLASES[1 if index == 5 else index], "RS cloud differs from shared atlas")
	var sprites := CityLifeSprites.new()
	sprites.set_artwork(assets.visual_artwork)
	var shared := CityLifeSprites.new()
	for direction in 8:
		for variant in CityLifeSprites.VARIANTS:
			for kind in 3:
				assert(sprites.sprite(false, variant, direction, 0, kind).get_data() == shared.sprite(false, variant, direction, 0, kind).get_data())
		for variant in CityLifeSprites.COLORS.size():
			for phase in 2:
				assert(sprites.sprite(true, variant, direction, phase).get_data() == shared.sprite(true, variant, direction, phase).get_data())
	CityNatureArtwork.prepare(pack.large_sprites, pack.palette, assets.visual_artwork)
	assert(not pack.large_sprites.visual_nature.is_empty())
	for id: int in pack.large_sprites.visual_nature:
		assert(not pack.large_sprites.high_resolution.has(id), "RS contains a separate nature-effect replacement")
	app.free()
	print("PASS: complete native standalone pack; 499 masters, 998 derived views, shared Visual Enhancements, 118 animations, native pixels/masks, brush instructions, road/season materials. Load ms: ", Time.get_ticks_msec() - started)
	quit()
