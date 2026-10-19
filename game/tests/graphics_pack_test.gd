extends SceneTree

@warning_ignore_start("integer_division")

const Fixture = preload("res://tests/indexed_png_test.gd")
const Pack = preload("res://src/assets/graphics_pack.gd")


func _initialize() -> void:
	_check_two_x_masters()
	_check_truecolor_pack()
	_check_visual_palette_swaps()
	_check_master_registration()
	_check_object_frames()
	_check_numbered_frames()
	var pack_root := "user://graphics-pack-test-%d" % Time.get_ticks_usec()
	assert(DirAccess.make_dir_recursive_absolute(pack_root) == OK)
	var png := FileAccess.open(pack_root.path_join("sprite.png"), FileAccess.WRITE)
	png.store_buffer(Fixture.FIXTURE.hex_decode())
	png.close()
	var manifest := {
		"format": "opensc2k-graphics", "version": 1, "name": "Independent test",
		"palette": "sprite.png", "scenario_palette": "sprite.png",
		"large_sprites": [{ "id": 1001, "png": "sprite.png" }, { "id": 1001, "png": "sprite.png" }],
		"small_medium_sprites": [{ "id": 1, "png": "sprite.png" }], "ui": {},
	}

	for field in Pack.UI_FIELDS:
		manifest.ui[field] = "sprite.png"

	_write_manifest(pack_root, manifest)
	var loaded := Pack.load_root(pack_root)
	assert(loaded.error.is_empty(), loaded.error)
	assert(Pack.load_root(pack_root.path_join("pack.json")).error.is_empty())
	assert(DirAccess.rename_absolute(pack_root.path_join("pack.json"), pack_root.path_join("manifest.json")) == OK)
	assert(not Pack.load_root(pack_root).error.is_empty(), "Retired manifest filename is not loaded")
	assert(DirAccess.rename_absolute(pack_root.path_join("manifest.json"), pack_root.path_join("pack.json")) == OK)
	assert(loaded.large_sprites.entries.size() == 2)
	assert(not loaded.small_medium_sprites.redraw_small_highway_ground)
	manifest.redraw_small_highway_ground = true
	_write_manifest(pack_root, manifest)
	var with_ground := Pack.load_root(pack_root)
	assert(with_ground.error.is_empty() and with_ground.small_medium_sprites.redraw_small_highway_ground)
	assert(Sc2SpriteArchive.combine([loaded.large_sprites, with_ground.small_medium_sprites]).redraw_small_highway_ground)
	var parsed := Sc2SpriteArchive.new()
	parsed.redraw_small_highway_ground = true
	assert(parsed.parse(PackedByteArray([0, 0])))
	assert(not parsed.redraw_small_highway_ground)
	manifest.redraw_small_highway_ground = 1
	_write_manifest(pack_root, manifest)
	assert(not Pack.load_root(pack_root).error.is_empty())
	manifest.erase("redraw_small_highway_ground")
	var sprite: Sc2SpriteArchive.SpriteEntry = loaded.large_sprites.find_sprite(1001)
	assert(sprite.duplicate_index == 1)
	assert(sprite.decode_indices().pixels == PackedInt32Array([-1, 1, 171, 172]))
	var indices := sprite.create_image(Sc2Palette.index_encoding())
	assert(indices.image.get_pixel(2, 0).r8 == 171)
	assert(indices.image.get_pixel(0, 0).a8 == 0)
	var returned: PackedInt32Array = sprite.decode_indices().pixels
	returned[1] = 9
	assert(sprite.decode_indices().pixels[1] == 1)
	var other := Sc2SpriteArchive.entry_from_indices(1001, 4, 1, returned)
	assert(sprite.pixel_hash() != other.pixel_hash())
	assert(Sc2SpriteArchive.entry_from_indices(1, 2, 1, PackedInt32Array([256, 0])) == null)
	assert(loaded.ui_images.toolbar_art.get_pixel(2, 0) == Color8(40, 80, 120))
	var assets := OriginalGameAssets.new()
	assert(loaded.apply_to(assets))
	assert(assets.large_sprites == loaded.large_sprites)
	var original_toolbar := assets.toolbar_art
	GameAssetSource.complete_toolbar(assets, pack_root)
	assert(assets.toolbar_art == original_toolbar, "Keep supplied DOS/Windows toolbar art")
	assets.toolbar_art = null
	GameAssetSource.complete_toolbar(assets, pack_root)
	assert(assets.toolbar_art.get_pixel(2, 0) == Color8(40, 80, 120))
	assert(assets.palette == loaded.palette and assets.large_sprites == loaded.large_sprites,
		"UI fallback must not replace the selected city palette or sprites")
	assert(Pack.load_toolbar(pack_root.path_join("absent")) == null)
	manifest.ui.toolbar_art = "../sprite.png"
	_write_manifest(pack_root, manifest)
	assert(Pack.load_toolbar(pack_root) == null, "Fallback must enforce pack-relative paths")
	manifest.ui.toolbar_art = "sprite.png"
	_write_manifest(pack_root, manifest)
	var standalone := GameAssetSource.load_source("", "folder", pack_root)
	assert(standalone.error.is_empty(), standalone.error)
	assert(standalone.assets.large_sprites.find_sprite(1001).decode_indices().pixels == sprite.decode_indices().pixels)

	for bad_path in ["../sprite.png", "/sprite.png", "res://sprite.png", "a\\sprite.png", "./sprite.png"]:
		manifest.palette = bad_path
		_write_manifest(pack_root, manifest)
		var bad := Pack.load_root(pack_root)
		assert(not bad.error.is_empty())
		assert(not bad.apply_to(assets))
		assert(assets.large_sprites == loaded.large_sprites)

	manifest.palette = "missing.png"
	_write_manifest(pack_root, manifest)
	assert(not Pack.load_root(pack_root).error.is_empty())
	manifest.palette = "sprite.png"
	manifest.large_sprites[0].id = 1.5
	_write_manifest(pack_root, manifest)
	assert(not Pack.load_root(pack_root).error.is_empty())
	manifest.large_sprites[0].id = 1001
	manifest.ui.erase("toolbar_art")
	_write_manifest(pack_root, manifest)
	assert(not Pack.load_root(pack_root).error.is_empty())
	manifest.partial = true
	manifest.erase("scenario_palette")
	manifest.small_medium_sprites = []
	_write_manifest(pack_root, manifest)
	var partial := Pack.load_root(pack_root)
	assert(partial.error.is_empty(), partial.error)
	assert(not GameAssetSource.load_source("", "folder", pack_root).error.is_empty(),
		"One sprite size group cannot activate without a base")
	var kept_small := assets.small_medium_sprites
	var kept_scenario := assets.scenario_palette
	var kept_toolbar := assets.toolbar_art
	assert(partial.apply_to(assets))
	assert(assets.small_medium_sprites == kept_small and assets.scenario_palette == kept_scenario and assets.toolbar_art == kept_toolbar)
	# Reject an incompatible palette before changing any active assets.
	var different := Sc2Palette.index_encoding()
	assets.palette = different
	var kept_large := assets.large_sprites
	assert(not Pack.load_root(pack_root).apply_to(assets))
	assert(assets.palette == different and assets.large_sprites == kept_large)
	manifest.large_sprites = []
	_write_manifest(pack_root, manifest)
	assert(not GameAssetSource.load_source("", "folder", pack_root).error.is_empty(), "UI-only packs cannot supply a city on first run")
	assert(Pack.load_root(pack_root).apply_to(assets))
	assert(assets.palette == different and assets.large_sprites == kept_large)
	manifest.ui = {}
	_write_manifest(pack_root, manifest)
	assert(not Pack.load_root(pack_root).error.is_empty(), "Empty partial packs are invalid")
	DirAccess.remove_absolute(pack_root.path_join("sprite.png"))
	DirAccess.remove_absolute(pack_root.path_join("pack.json"))
	DirAccess.remove_absolute(pack_root)
	print("PASS: graphics pack loading, duplicate IDs, indexed rendering, UI, invalid packs")
	quit()


func _write_manifest(pack_root: String, manifest: Dictionary) -> void:
	var file := FileAccess.open(pack_root.path_join("pack.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest))
	file.close()


func _check_master_registration() -> void:
	var palette := Sc2Palette.index_encoding()
	var decoded := IndexedImageResult.new()
	decoded.ok = true
	decoded.width = 160
	decoded.height = 96
	decoded.palette = palette
	decoded.pixels.resize(160 * 96)
	decoded.pixels.fill(1)
	var reader := func(_path: Variant) -> IndexedImageResult: return decoded
	var translucent := Image.create(160, 96, false, Image.FORMAT_RGBA8)
	translucent.fill(Color(0.2, 0.5, 0.8, 0.65))
	var rgba_reader := func(_path: Variant) -> Image: return translucent
	var record := {"id": 1112, "png": "master.png", "logical_size": [40, 24],
		"visual_registration": [32, 4, 4], "artwork_rgba": "full.png",
		"parcel": {"border": "077300ff", "surface": "asphalt_curb"}}
	var master := MasterSpriteSource.new()
	assert(master.load_records([record], reader, palette, rgba_reader), master.error)
	var context := CityGpuBuildContext.new()
	var city := CityState.from_document(EmptyCityTemplate.create(64))
	assert(context.prepare(city, palette, master.large, 2).is_empty(), "Native bridge must accept typed pack registration")
	assert(IsometricGeometry.maximum_sprite_size(master.large) == Vector2i(56, 24), "Bounds must include added bottom padding")
	for view in 3:
		var divisor := 4 >> view
		var archive: Sc2SpriteArchive = master.large if view == 2 else master.small_medium
		var id := view * 500 + 112
		assert(archive.parcel_styles[id] == PackedInt64Array([0x077300ff, 2]))
		assert(archive.visual_registration[id] == Vector3i(32 / divisor, 4 / divisor, 4 / divisor))
		assert(archive.high_resolution[id].image.get_pixel(80, 48).a8 == translucent.get_pixel(80, 48).a8)
	var normalized := record.duplicate(true)
	normalized.erase("visual_registration")
	var centered := MasterSpriteSource.new()
	assert(centered.load_records([normalized], reader, palette, rgba_reader, "centered-footprint-v1"), centered.error)
	for view in 3:
		var archive: Sc2SpriteArchive = centered.large if view == 2 else centered.small_medium
		var divisor := 4 >> view
		assert(archive.visual_registration[view * 500 + 112] == Vector3i(32 / divisor, 4 / divisor, 0))
	assert(not centered.load_records([record], reader, palette, rgba_reader, "centered-footprint-v1"), "Conflicting legacy offset accepted")
	assert(not centered.load_records([normalized], reader, palette, rgba_reader, "unknown"), "Unknown canvas convention accepted")
	normalized.logical_size = [36, 24]
	assert(not centered.load_records([normalized], reader, palette, rgba_reader, "centered-footprint-v1"), "Asymmetric view margins accepted")
	var classic := Sc2SpriteArchive.new()
	classic.entries.append(master.large.find_sprite(1112))
	classic.entries_by_id[1112] = classic.entries[0]
	assert(Sc2SpriteArchive.combine([master.large, classic]).visual_registration.is_empty(), "replacement pack leaked old registration")
	assert(Sc2SpriteArchive.combine([classic, master.large]).visual_registration[1112] == Vector3i(32, 4, 4))
	assert(Sc2SpriteArchive.combine([master.large, classic]).parcel_styles.is_empty(), "SC2K replacement retained RS parcel")
	assert(Sc2SpriteArchive.combine([classic, master.large]).parcel_styles.has(1112))
	assert(classic.parcel_styles.is_empty(), "combination modified source parcel metadata")
	assert(classic.visual_registration.is_empty(), "combining packs mutated the original archive")
	for invalid in [[31, 4, 4], [32, -4, 4], [32, 12, 4], [32, 4, 24], [32, 4.5, 4], [32, 4]]:
		var bad := record.duplicate(true)
		bad.visual_registration = invalid
		assert(not MasterSpriteSource.new().load_records([bad], reader, palette, rgba_reader))
	for spec in [{"border": "invalid!"}, {"surface": "lava"}, {"border": 1}, {"surface": 1}, []]:
		var bad := record.duplicate(true)
		bad.parcel = spec
		assert(not MasterSpriteSource.new().load_records([bad], reader, palette, rgba_reader))
	var network := record.duplicate(true)
	network.id = 1029
	assert(not MasterSpriteSource.new().load_records([network], reader, palette, rgba_reader))
	assert(not MasterSpriteSource.new().load_records([record], reader, palette), "RGBA requires a validated reader")
	assert(master.large.parse(PackedByteArray([0, 0])))
	assert(master.large.parcel_styles.is_empty(), "archive reload leaked parcel layer")
	assert(master.large.visual_registration.is_empty(), "archive reload leaked previous pack registration")


func _check_visual_palette_swaps() -> void:
	var indices := Image.create(12, 24, false, Image.FORMAT_RGBA8)
	indices.fill(Color8(0, 0, 0, 255))
	indices.set_pixel(3, 4, Color8(1, 1, 1, 255))
	var lamp := Image.create(12, 24, false, Image.FORMAT_RGBA8)
	lamp.set_pixel(3, 4, Color8(220, 170, 90, 255))
	var reads := {}
	var reader := func(path: String) -> Image:
		reads[path] = int(reads.get(path, 0)) + 1
		return lamp if path == "lamp.png" else indices
	var first := {"key": "person/0/0/0", "png": "base.png", "logical_size": [3, 6],
		"master_scale": 4, "palette_swap": ["00000000", "ae584580"], "lightmap": "lamp.png"}
	var second := first.duplicate(true)
	second.key = "person/1/0/0"
	second.palette_swap[1] = "66818dff"
	var shared := first.duplicate(true)
	shared.key = "person/2/0/0"
	var loaded := VisualArtwork.load_records([first, second, shared], reader)
	assert(loaded.error.is_empty(), loaded.error)
	assert(reads == {"base.png": 1, "lamp.png": 1}, "Base and lamps must only decode once")
	assert(loaded.frames[first.key].image.get_pixel(3, 4) == Color8(174, 88, 69, 128))
	assert(loaded.frames[second.key].image.get_pixel(3, 4) == Color8(102, 129, 141, 255))
	assert(loaded.frames[first.key].image.get_pixel(0, 0).a8 == 0)
	assert(loaded.frames[first.key].image == loaded.frames[shared.key].image)
	assert(loaded.frames[first.key].emission == loaded.frames[second.key].emission)
	assert(indices.get_pixel(3, 4) == Color8(1, 1, 1, 255), "Recoloring must not modify the source")
	for invalid in [[], ["00000000"], ["00000000", "zzzzzzzz"], ["00000000", "-0000001"],
		["00000000", "+0000001"], ["00000000", "0x000001"], ["00000000", 17], "bad"]:
		var bad := first.duplicate(true)
		bad.palette_swap = invalid
		var rejected := VisualArtwork.load_records([second, bad], reader)
		assert(not rejected.error.is_empty() and rejected.frames.is_empty())
	indices.set_pixel(3, 4, Color8(1, 2, 1, 255))
	assert(not VisualArtwork.load_records([first], reader).error.is_empty())
	indices.set_pixel(3, 4, Color8(1, 1, 1, 128))
	assert(not VisualArtwork.load_records([first], reader).error.is_empty())
	var plain := first.duplicate(true)
	plain.erase("palette_swap")
	assert(VisualArtwork.load_records([plain], reader).frames[plain.key].image == indices)


func _check_object_frames() -> void:
	var loader := MasterFrameAnimation.new()
	var images: Dictionary = {}
	for i in 4:
		var art := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		art.fill(Color8(30 + i * 20, 60, 90))
		images[str(i)] = art
		var light := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		light.set_pixel(1, 2, Color8(100 + i * 20, 80, 30))
		images["l" + str(i)] = light
	var reader := func(path: Variant) -> Image: return images.get(path)
	var spec := {"format": "rgba", "frames": ["0", "1", "2", "3"],
		"lightmaps": ["l0", "l1", "l2", "l3"], "fps": 8,
		"durations_ms": [125, 250, 125, 125], "playback": "ping_pong"}
	var result := loader.load_frames(spec, images["0"], images.l0, reader, 10000)
	assert(loader.error.is_empty(), loader.error)
	assert(result.frames == 8 and result.fps == 8)
	var from_json: Dictionary = JSON.parse_string(JSON.stringify(spec))
	assert(not loader.load_frames(from_json, images["0"], images.l0, reader, 10000).is_empty(), loader.error)
	var expected := [0, 1, 1, 2, 3, 2, 1, 1]
	for i in expected.size():
		assert(result.art.get_pixel(0, i * 4).r8 == 30 + expected[i] * 20)
		assert(result.light.get_pixel(1, i * 4 + 2).r8 == 100 + expected[i] * 20)
	for change in [{"frames": []}, {"frames": range(33)},
		{"fps": 6}, {"fps": 5.5}, {"fps": INF}, {"playback": "reverse"}, {"durations_ms": [125]},
		{"durations_ms": [0, 125, 125, 125]}, {"durations_ms": [126, 125, 125, 125]},
		{"durations_ms": [NAN, 125, 125, 125]}, {"durations_ms": [4000, 4000, 4000, 4000]},
		{"lightmaps": ["l0"]}, {"frames": ["1", "1", "2", "3"]},
		{"lightmaps": ["l1", "l1", "l2", "l3"]}, {"lightmaps": ["l0", "missing", "l2", "l3"]}]:
		var bad: Dictionary = spec.duplicate(true)
		bad.merge(change, true)
		assert(loader.load_frames(bad, images["0"], images.l0, reader, 10000).is_empty(), str(change))
		assert(not loader.error.is_empty())
	assert(loader.load_frames(spec, images["0"], images.l0, reader, 1).is_empty())
	images["2"].set_pixel(1, 2, Color.TRANSPARENT)
	assert(loader.load_frames(spec, images["0"], images.l0, reader, 10000).is_empty())
	images["2"].set_pixel(1, 2, Color.BLACK)
	result = loader.load_frames({"frames": ["0"]}, images["0"], null, reader, 10000)
	assert(result.frames == 2 and result.light == null)
	result = loader.load_frames({"frames": ["0", "1"], "fps": 5, "durations_ms": [200, 400]}, images["0"], images.l0, reader, 10000)
	assert(result.frames == 3 and result.fps == 5 and result.light.get_pixel(1, 6) == images.l0.get_pixel(1, 2))
	# Exercise the full master loader, all three derived views and pack-local geometry.
	var decoded := IndexedImageResult.new()
	decoded.ok = true
	decoded.width = 4
	decoded.height = 4
	decoded.palette = Sc2Palette.index_encoding()
	decoded.pixels.resize(16)
	decoded.pixels.fill(1)
	var indexed_reader := func(_path: Variant) -> IndexedImageResult: return decoded
	var source := MasterSpriteSource.new()
	var record := {"id": 1364, "png": "indexed.png", "logical_size": [1, 1], "artwork_rgba": "0", "animation": {"format": "rgba", "frames": ["0", "1"]}}
	assert(source.load_records([record], indexed_reader, decoded.palette, reader), source.error)
	assert(source.large.high_resolution[1364].frames == 2)
	assert(source.small_medium.high_resolution[364].animation == source.large.high_resolution[1364].animation)
	assert(source.small_medium.high_resolution[864].height == 1)
	record.animation.format = "unknown"
	assert(not source.load_records([record], indexed_reader, decoded.palette, reader))

	# A PNG can retain RGB under alpha zero; indexed decoding clears those bytes.
	var png_image := Image.new()
	assert(png_image.load_png_from_buffer(Fixture.FIXTURE.hex_decode()) == OK)
	png_image.convert(Image.FORMAT_RGBA8)
	var base := Image.create_from_data(4, 1, false, Image.FORMAT_RGBA8, png_image.get_data())
	base.set_pixel(0, 0, Color.TRANSPARENT)
	var png_reader := func(_path: Variant) -> Image: return png_image
	assert(not loader.load_frames({"frames": ["png"]}, base, null, png_reader, 1000).is_empty(), loader.error)
	base.set_pixel(1, 0, Color(0.1, 0.2, 0.3, 0.5))
	assert(loader.load_frames({"frames": ["png"]}, base, null, png_reader, 1000).is_empty())


func _check_numbered_frames() -> void:
	var files := {"TILE_001_001.png": true}
	var exists := func(path: String) -> bool: return files.has(path)
	var sequence := NumberedFrameSequence.new()
	var record := {"png": "indexed.png", "artwork_rgba": "TILE_001_001.png"}
	assert(not sequence.resolve(record, exists).has("animation"))
	files["TILE_001_002.png"] = true
	var resolved := sequence.resolve(record, exists)
	assert(resolved.animation.frames == ["TILE_001_001.png", "TILE_001_002.png"])
	assert(resolved.animation.fps == 8 and not record.has("animation"))
	files["TILE_001_003.png"] = true
	assert(sequence.resolve(record, exists).animation.frames.size() == 3)
	files.erase("TILE_001_002.png")
	assert(not sequence.resolve(record, exists).has("animation"), "A gap ends the contiguous sequence")
	files["TILE_001_002.png"] = true
	record.lightmap = "LIGHT_001_001.png"
	assert(not sequence.resolve(record, exists).animation.has("lightmaps"), "Static lightmap fallback")
	files["LIGHT_001_002.png"] = true
	assert(sequence.resolve(record, exists).is_empty(), "Missing animated lightmap accepted")
	files["LIGHT_001_003.png"] = true
	assert(sequence.resolve(record, exists).animation.lightmaps.size() == 3)
	files["LIGHT_001_004.png"] = true
	assert(sequence.resolve(record, exists).is_empty(), "Excess lightmap accepted")
	record.erase("lightmap")
	for number in range(4, 34):
		files["TILE_001_%03d.png" % number] = true
	assert(sequence.resolve(record, exists).is_empty(), "Unbounded sequence accepted")
	files.erase("TILE_001_033.png")
	assert(sequence.resolve(record, exists).animation.frames.size() == 32)
	record.animation = {"format": "rgba", "frames": ["explicit.png"]}
	assert(sequence.resolve(record, exists) == record, "Explicit legacy declaration takes precedence")

	# Actual disk discovery, decoding, shared view strips and 2 -> 3 -> still reload.
	var folder := "user://numbered-frames-%d" % Time.get_ticks_usec()
	assert(DirAccess.make_dir_recursive_absolute(folder) == OK)
	var palette_file := FileAccess.open(folder.path_join("palette.png"), FileAccess.WRITE)
	palette_file.store_buffer(Fixture.FIXTURE.hex_decode())
	palette_file.close()
	var master := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	master.fill(Color8(30, 60, 90))
	var indexed := IndexedImageResult.new()
	indexed.ok = true
	indexed.width = 4
	indexed.height = 4
	indexed.palette = Sc2Palette.index_encoding()
	indexed.pixels.resize(16)
	indexed.pixels.fill(1)
	# Use the real indexed fixture via a small valid indexed PNG encoder.
	var png := IndexedPng.encode(4, 4, indexed.pixels, indexed.palette)
	var master_file := FileAccess.open(folder.path_join("master.png"), FileAccess.WRITE)
	assert(png.ok, png.error)
	master_file.store_buffer(png.bytes)
	master_file.close()
	var pack_manifest := {"format": "opensc2k-graphics", "version": 1, "name": "Numbered test", "partial": true,
		"palette": "master.png", "master_sprites": [{"id": 1364, "png": "master.png", "logical_size": [1, 1], "artwork_rgba": "TILE_001_001.png"}]}
	_write_manifest(folder, pack_manifest)
	for number in range(1, 4):
		master.fill(Color8(30 * number, 60, 90))
		assert(master.save_png(folder.path_join("TILE_001_%03d.png" % number)) == OK)
		var pack := Pack.load_root(folder)
		assert(pack.error.is_empty(), pack.error)
		var hd: HdSprite = pack.large_sprites.high_resolution[1364]
		if number == 1:
			assert(hd.animation == null)
		else:
			assert(hd.frames == number and hd.fps == 8)
			assert(hd.animation.get_pixel(0, (number - 1) * 4).r8 == 30 * number)
			assert(pack.small_medium_sprites.high_resolution[364].animation == hd.animation)
	assert(DirAccess.remove_absolute(folder.path_join("TILE_001_002.png")) == OK)
	var static_pack := Pack.load_root(folder)
	assert(static_pack.error.is_empty() and static_pack.large_sprites.high_resolution[1364].animation == null)


func _check_truecolor_pack() -> void:
	var folder := "user://truecolor-pack-%d" % Time.get_ticks_usec()
	assert(DirAccess.make_dir_recursive_absolute(folder) == OK)
	var palette := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for index in 256:
		palette.set_pixel(index % 16, index / 16, Color8(index, 255 - index, 40))
	assert(palette.save_png(folder.path_join("palette.png")) == OK)
	var art := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			art.set_pixel(x, y, Color8(x * 7, y * 7, (x + y) * 3, 128 if x == 0 else 255))
	art.set_pixel(31, 31, Color.TRANSPARENT)
	assert(art.save_png(folder.path_join("TILE_1364_001.png")) == OK)
	var second := art.duplicate()
	second.set_pixel(10, 10, Color8(18, 34, 219))
	assert(second.save_png(folder.path_join("TILE_1364_002.png")) == OK)
	var light := art.duplicate()
	assert(light.save_png(folder.path_join("light.png")) == OK)
	var mask := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	mask.fill(Color8(200, 200, 200))
	assert(mask.save_png(folder.path_join("semantic.png")) == OK)
	var manifest := {"format": "opensc2k-graphics", "version": 1, "name": "TrueColor test", "partial": true,
		"pixel_format": "rgba8", "palette": "palette.png", "semantic_images": {"TILE_1364_001.png": "semantic.png"},
		"master_sprites": [{"id": 1364, "png": "TILE_1364_001.png", "logical_size": [8, 8], "lightmap": "light.png"}],
		"ui": {"toolbar_art": "TILE_1364_001.png"}}
	_write_manifest(folder, manifest)
	var pack := Pack.load_root(folder)
	assert(pack.error.is_empty(), pack.error)
	var hd: HdSprite = pack.large_sprites.high_resolution[1364]
	assert(hd.image.get_data() == art.get_data(), "More than 256 colors and partial alpha must remain exact")
	assert(hd.emission.get_data() == light.get_data(), "TrueColor emission must remain exact")
	assert(pack.ui_images.toolbar_art.get_data() == art.get_data(), "UI must bypass indexed rendering")
	assert(Pack.load_toolbar(folder).get_data() == art.get_data(), "RGBA toolbar fallback retains exact colors and alpha")
	assert(hd.frames == 2 and hd.fps == 8)
	assert(hd.animation.get_pixel(10, 42) == second.get_pixel(10, 10))
	assert(pack.large_sprites.find_sprite(1364).decode_indices().pixels.has(200), "Water semantics must survive RGB conversion")
	assert(pack.palette.animation_image(0).get_data() == pack.palette.animation_image(5).get_data(), "TrueColor must not cycle")
	assert(Sc2kfixSpriteFixes.extended_palette(pack.palette) == pack.palette, "Original-only palette corrections must not change TrueColor packs")
	var original := Sc2Palette.from_rgb_bytes(pack.palette.to_rgb_bytes())
	assert(original.animation_image(0).get_data() != original.animation_image(5).get_data(), "SC2K cycling must remain active")
	manifest.master_sprites[0].animation = {"format": "unsupported", "frames": ["TILE_1364_001.png", "TILE_1364_002.png"]}
	_write_manifest(folder, manifest)
	assert(not Pack.load_root(folder).error.is_empty(), "TrueColor must reject unsupported explicit animation formats")
	manifest.master_sprites[0].erase("animation")
	manifest.erase("pixel_format")
	_write_manifest(folder, manifest)
	assert(not Pack.load_root(folder).error.is_empty(), "Legacy indexed format must remain strict")
	manifest.pixel_format = "rgba8"
	manifest.semantic_images["TILE_1364_001.png"] = "../escape.png"
	_write_manifest(folder, manifest)
	assert(not Pack.load_root(folder).error.is_empty(), "Semantic masks must obey pack path validation")
	manifest.semantic_images.clear()
	_write_manifest(folder, manifest)
	assert(Pack.load_root(folder).error.is_empty(), "Simple TrueColor artwork must not require compatibility masks")
	mask.resize(16, 16)
	assert(mask.save_png(folder.path_join("semantic.png")) == OK)
	manifest.semantic_images["TILE_1364_001.png"] = "semantic.png"
	_write_manifest(folder, manifest)
	assert(not Pack.load_root(folder).error.is_empty(), "Mismatched logical masks must be rejected")


func _check_two_x_masters() -> void:
	var palette := Sc2Palette.index_encoding()
	var decoded := IndexedImageResult.new()
	decoded.ok = true
	decoded.palette = palette
	decoded.width = 80
	decoded.height = 48
	decoded.pixels.resize(80 * 48)
	decoded.pixels.fill(7)
	var reader := func(_path: Variant) -> IndexedImageResult: return decoded
	var record := {"id": 1112, "png": "master.png", "logical_size": [40, 24]}
	var master := MasterSpriteSource.new()
	assert(master.load_records([record], reader, palette, Callable(), "centered-footprint-v1", JSON.parse_string("2")), master.error)
	for view in 3:
		var divisor := 4 >> view
		var archive: Sc2SpriteArchive = master.large if view == 2 else master.small_medium
		var id := 112 + view * 500
		var entry := archive.find_sprite(id)
		assert(Vector2i(entry.width, entry.height) == Vector2i(40 / divisor, 24 / divisor))
		assert(archive.visual_registration[id] == Vector3i(32 / divisor, 4 / divisor, 0))
		assert(archive.high_resolution[id].image.get_size() == Vector2i(80, 48))
		assert(entry.decode_indices().pixels.count(7) == entry.width * entry.height)
	assert(not master.load_records([record], reader, palette), "2x pixels must not silently pass a 4x declaration")
	for bad in [0, 1, 3, 2.5, "2", null, true]:
		assert(not master.load_records([record], reader, palette, Callable(), "legacy", bad))
	var person := Image.create(6, 12, false, Image.FORMAT_RGBA8)
	person.fill(Color8(90, 130, 160))
	var images := {"person": person}
	var visual_reader := func(path: String) -> Image: return images.get(path)
	var rows := [{"key": "person/0/0/0", "png": "person", "logical_size": [3, 6], "master_scale": 2}]
	var visual := VisualArtwork.load_records(rows, visual_reader)
	assert(visual.error.is_empty(), visual.error)
	assert(visual.frames["person/0/0/0"].scale == 2 and visual.city_life_scale == 2)
	var sprites := CityLifeSprites.new()
	sprites.set_artwork(visual)
	var logical := sprites.sprite(true, 0, 0, 0)
	assert(logical.get_size() == Vector2i(3, 6) and sprites.master_image(logical).get_size() == Vector2i(6, 12))
	# Source raster changes must not shrink the displayed toolbar icons.
	for raster_scale in [2, 4]:
		var toolbar := CityToolbar.new()
		toolbar.toolbar_art = Image.create(865 * raster_scale, 23 * raster_scale, false, Image.FORMAT_RGBA8)
		toolbar.toolbar_art.fill_rect(Rect2i(raster_scale, raster_scale, 10 * raster_scale, 12 * raster_scale), Color.WHITE)
		var icon := toolbar._toolbar_icon(Rect2i(0, 0, 20, 20))
		assert(icon != null and icon.get_size() == Vector2(10, 12))
		toolbar.free()
	# Mask sampling preserves the bottom alignment at every resolution.
	var mask := Image.create(64, 72, false, Image.FORMAT_RGBA8)
	mask.set_pixel(1, 71, Color.RED)
	var sampled := CityNatureArtwork._logical_mask(mask, Vector2i(32, 36), 1, 2)
	assert(sampled.get_pixel(0, 35) == Color.RED)
