extends SceneTree
## Optional thumbnails must not change the city, dirty state, or original formats.

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	AppPaths._root = OS.get_temp_dir().path_join("city-preview-test-%d" % OS.get_process_id())
	var preview := Image.create(96, 64, false, Image.FORMAT_RGBA8)
	preview.fill(Color.CORNFLOWER_BLUE)
	var png := preview.save_png_to_buffer()
	_test_saved_details(png)
	assert(CityPreviewStore.decode(png).get_data() == preview.get_data())
	assert(CityPreviewStore.decode(PackedByteArray([1, 2, 3])) == null)
	var oversized := png.duplicate()
	oversized[16] = 1
	assert(CityPreviewStore.decode(oversized) == null)
	var source := Sc2xDocument.create_empty(16, "Preview test").document
	source.sc2x_extra_entries["custom.dat"] = PackedByteArray([12, 34])
	var snapshot := source.content_snapshot()
	source.sc2x_extra_entries[CityPreviewStore.ENTRY] = png
	assert(source.content_snapshot() == snapshot, "Presentation must not mark the city dirty")
	var output := OS.get_temp_dir().path_join("preview-%d.sc2x" % OS.get_process_id())
	var prepared := CityFileStore.prepare(source, output, "")
	assert(prepared.ok, prepared.error)
	assert(not prepared.entries.members.has(CityPreviewStore.ENTRY), "Autosave drops stale preview")
	assert(prepared.entries.members["custom.dat"] == PackedByteArray([12, 34]))
	CityFileStore.attach_preview(prepared, preview)
	assert(prepared.entries.members.has(CityPreviewStore.ENTRY))
	assert(CityFileStore.write(prepared).ok)
	assert(CityPreviewStore.embedded(output).get_data() == preview.get_data())
	var loaded := Sc2File.load_path(output)
	assert(loaded.is_valid() and loaded.content_snapshot() == prepared.snapshot)
	assert(loaded.sc2x_extra_entries["custom.dat"] == PackedByteArray([12, 34]))
	var reader := CityPreviewJob.new()
	reader.path = output
	reader.run()
	assert(reader.saved_preview and reader.image != null, "Embedded image needs no graphics pack")
	assert(reader.details().city_name == "Preview test" and reader.details().map_size == 16)
	CityFileStore.attach_preview(prepared, null)
	assert(CityFileStore.write(prepared).ok)
	assert(CityPreviewStore.embedded(output) == null)
	source.sc2x_extra_entries[CityPreviewStore.ENTRY] = PackedByteArray([1, 2, 3])
	assert(CityFileStore.write_verified(output, source.serialize().data).ok)
	assert(CityPreviewStore.embedded(output) == null and Sc2File.load_path(output).is_valid(),
		"An invalid preview must not invalidate the city")
	DirAccess.remove_absolute(output)
	var original := EmptyCityTemplate.create()
	var original_bytes := original.serialize().data
	var legacy_path := output.get_basename() + "-legacy.sc2x"
	var legacy := CityFileStore.prepare(original, legacy_path, "")
	assert(legacy.ok and legacy.entries == null)
	CityFileStore.attach_preview(legacy, preview)
	assert(CityFileStore.write(legacy).ok)
	assert(CityPreviewStore.embedded(legacy_path) == null)
	assert(Sc2File.load_path(legacy_path).serialize().data == original_bytes)
	var legacy_reader := CityPreviewJob.new()
	var legacy_digest := FileAccess.get_sha256(legacy_path)
	legacy_reader.path = legacy_path
	legacy_reader.run()
	assert(not legacy_reader.details().multiplayer and legacy_reader.details().map_size == 128,
		"Legacy details do not require a graphics pack or a thumbnail")
	assert(FileAccess.get_sha256(legacy_path) == legacy_digest, "Reading legacy details leaves the file byte-exact")
	DirAccess.remove_absolute(legacy_path)
	prepared = CityFileStore.prepare(original, output.get_basename() + ".sc2", "")
	CityFileStore.attach_preview(prepared, preview)
	assert(prepared.entries == null and prepared.bytes == original_bytes)
	CityPreviewStore.store("original-digest", "graphics-a", preview)
	assert(CityPreviewStore.cached("original-digest", "graphics-a") != null)
	assert(CityPreviewStore.cached("changed-digest", "graphics-a") == null)
	assert(CityPreviewStore.cached("original-digest", "graphics-b") == null)
	DirAccess.remove_absolute(CityPreviewStore.cache_path("original-digest", "graphics-a"))
	var assets := LoadedAssetState.new()
	assets.palette = FixtureGraphics.pack().palette
	assets.large_sprites = MainMenuPresentation.copy_graphics(FixtureGraphics.pack().large_sprites)
	var job := CityPreviewJob.for_assets(assets)
	job.document = Sc2File.load_path("res://tests/fixtures/cities/generated-128.SC2")
	var before := job.document.serialize().data
	var started := Time.get_ticks_msec()
	job.start()
	while not job.finished():
		await process_frame
	job.join()
	assert(job.image != null)
	assert(job.image.get_width() <= 768 and job.image.get_height() <= 512)
	assert(job.image.get_used_rect().size.x > 0)
	assert(job.document.serialize().data == before, "Rendering must not alter city/RNG bytes")
	var frozen := CityPreviewJob.for_assets(assets)
	frozen.document = EmptyCityTemplate.create(32)
	var original_compass := frozen.document.misc_u32(Sc2MiscLayout.COMPASS)
	frozen.document = frozen.document.duplicate_document(true)
	frozen.background = Color.TRANSPARENT
	frozen.desired_compass = (int(original_compass) + 1) & 3
	frozen.grayscale = true
	frozen.start()
	while not frozen.finished():
		await process_frame
	frozen.join()
	assert(frozen.image != null and frozen.image.get_pixel(0, 0).a == 0, "Frozen city views preserve transparent space")
	var colored := false
	for y in frozen.image.get_height():
		for x in frozen.image.get_width():
			var color := frozen.image.get_pixel(x, y)
			assert(is_equal_approx(color.r, color.g) and is_equal_approx(color.g, color.b))
			colored = colored or color.a > 0
	assert(colored and frozen.document.misc_u32(Sc2MiscLayout.COMPASS) == frozen.desired_compass)
	var same := CityPreviewJob.for_assets(assets)
	same.prepare_graphics_key()
	assert(same.graphics_key == job.graphics_key)
	var fixture_path := "res://tests/fixtures/cities/generated-128.SC2"
	var fixture_digest := FileAccess.get_sha256(fixture_path)
	CityPreviewStore.store(fixture_digest, same.graphics_key, preview)
	same.path = fixture_path
	same.run()
	assert(same.image.get_data() == preview.get_data() and same.details().map_size == 128,
		"Cached images must retain freshly read saved values")
	DirAccess.remove_absolute(CityPreviewStore.cache_path(fixture_digest, same.graphics_key))
	print("PREVIEW 128: ", Time.get_ticks_msec() - started, " ms; ", job.image.get_size())
	var large := CityPreviewJob.for_assets(assets)
	large.document = EmptyCityTemplate.create(512)
	started = Time.get_ticks_msec()
	large.start()
	while not large.finished():
		await process_frame
	large.join()
	assert(large.image != null and large.image.get_width() <= 768 and large.image.get_height() <= 512)
	print("PREVIEW 512: ", Time.get_ticks_msec() - started, " ms; ", large.image.get_size())
	assets.large_sprites.visual_nature_enabled = not assets.large_sprites.visual_nature_enabled
	var changed := CityPreviewJob.for_assets(assets)
	changed.prepare_graphics_key()
	assert(changed.graphics_key != same.graphics_key, "Changed nature artwork invalidates cached preview")
	var cancelled := CityPreviewJob.for_assets(assets)
	cancelled.document = original
	cancelled.cancel()
	cancelled.run()
	assert(cancelled.image == null)
	assert(cancelled.details().is_empty())
	var dialog := FileDialogFactory.city_open()
	root.gui_embed_subwindows = true
	root.add_child(dialog)
	var memory := WindowLayoutMemory.new()
	root.add_child(memory)
	await process_frame
	assert(dialog is CityOpenDialog and dialog.preview_panel != null)
	dialog.popup_centered_ratio(0.8)
	dialog.set_process(false)
	dialog.current_path = ProjectSettings.globalize_path(fixture_path)
	dialog.selected_path = dialog.current_path
	dialog._job_path = dialog.current_path
	dialog.job = CityPreviewJob.new()
	dialog.job.path = dialog.current_path
	dialog.job.start()
	while not dialog.job.finished():
		await process_frame
	dialog._process(0.0)
	assert(dialog.displayed_details.map_size == 128 and not dialog.preview_details.text.is_empty(),
		"Completed workers publish their final details before being released")
	for extent in [Vector2i(900, 560), Vector2i(1100, 700), Vector2i(780, 520)]:
		dialog.size = extent
		dialog.preview_image.texture = ImageTexture.create_from_image(job.image)
		dialog.preview_status.text = "Preview unavailable. You can still open this city."
		for frame in 8:
			memory._process(0.25)
			await process_frame
		var settled := Rect2i(dialog.position, dialog.size)
		var minimum := dialog.get_contents_minimum_size()
		for frame in 20:
			memory._process(0.25)
			await process_frame
			assert(Rect2i(dialog.position, dialog.size) == settled, "City chooser must settle after resizing")
			assert(dialog.get_contents_minimum_size() == minimum, "Preview must not feed a new minimum back into the window")
	# Dynamic details must translate again, while user city names stay literal.
	dialog.set_process(false)
	dialog.displayed_details = {"city_name": "[b]Player city[/b]", "map_size": 4096, "multiplayer": false, "funds": -2500, "year": 2042}
	for locale in ["de", "es", "fr", "it", "ko", "pt_BR", "en"]:
		AppLocalization.select(locale)
		dialog._update_details()
		assert(dialog.preview_details.text.contains(dialog.tr("Year: %d") % 2042))
		assert(dialog.preview_name.text == "[b]Player city[/b]")
	dialog.selected_path = "previous.sc2"
	dialog.displayed_path = "previous.sc2"
	dialog.current_path = OS.get_temp_dir().path_join("not-a-city.txt")
	dialog._process(0.0)
	assert(dialog.displayed_details.is_empty() and dialog.preview_details.text.is_empty(),
		"Selection changes clear the previous city's details")
	dialog.hide()
	dialog.queue_free()
	memory.queue_free()
	await process_frame
	await _check_save_list()
	print("PASS: bounded city previews, optional SC2X thumbnail, unchanged original saves, cache invalidation and cancellation")
	quit()


func _test_saved_details(png: PackedByteArray) -> void:
	var source := Sc2xDocument.create_empty(16, "Multiplayer").document
	var misc := source.find_chunk("MISC")
	var bytes := misc.decoded_payload.duplicate()
	for field in [[Sc2MiscLayout.START_YEAR, 1900], [Sc2MiscLayout.CITY_DAYS, 601],
		[Sc2MiscLayout.FUNDS, -2500], [Sc2MiscLayout.BONDS, 3],
		[Sc2MiscLayout.NORMAL_POPULATION, 1234], [Sc2MiscLayout.ARCOLOGY_POPULATION, 2000]]:
		BinaryData.write_u32_be(bytes, field[0], field[1])
	assert(misc.set_decoded_payload(bytes))
	var before := source.serialize().data
	var info := CityPreviewInfo.from_document(source)
	assert(not info.multiplayer, "The filename/city name does not determine multiplayer")
	assert(info.year == 1902 and info.funds == -2500 and info.bank_debt == 30000 and info.population == 3234)
	assert(source.serialize().data == before, "Inspecting details cannot mutate city or random state")
	var metadata := source.sc2x_metadata.copy()
	metadata.map_size = 4096
	var members := {Sc2xDocument.METADATA_ENTRY: metadata.to_bytes(), "MISC.bin": bytes,
		CityPreviewStore.ENTRY: png}
	var path := OS.get_temp_dir().path_join("preview-details-%d.sc2x" % OS.get_process_id())
	for mode in ["single", "coop", "shared", "region", "invalid", "oversized"]:
		members.erase(CityPreviewInfo.MULTIPLAYER_ENTRY)
		if mode != "single":
			var session := {"version": 1, "members": {"private-token-a": {}, "private-token-b": {}}}
			if mode in ["shared", "region"]:
				session.shared = {"mode": mode}
			members[CityPreviewInfo.MULTIPLAYER_ENTRY] = JSON.stringify(session).to_utf8_buffer()
			if mode == "invalid":
				members[CityPreviewInfo.MULTIPLAYER_ENTRY] = "invalid".to_utf8_buffer()
			elif mode == "oversized":
				var large := PackedByteArray()
				large.resize(CityPreviewInfo.MAX_MULTIPLAYER_BYTES + 1)
				members[CityPreviewInfo.MULTIPLAYER_ENTRY] = large
		_write_header_archive(path, members)
		var digest := FileAccess.get_sha256(path)
		var job := CityPreviewJob.new()
		job.path = path
		job.run()
		info = job.details()
		assert(info.map_size == 4096 and info.year == 1902)
		assert(info.multiplayer == (mode != "single"))
		assert(info.has("funds") == (mode in ["single", "coop"]), "Never present the root budget as combined player finances")
		if mode in ["coop", "shared", "region"]:
			assert(info.mode == mode and info.players == 2)
		elif mode in ["invalid", "oversized"]:
			assert(info.mode == "unknown" and not info.has("players"))
		assert(not str(info).contains("private-token"))
		assert(job.image != null and job.document == null, "4096 terrain is not decoded for header details")
		assert(FileAccess.get_sha256(path) == digest)
	members.erase(CityPreviewStore.ENTRY)
	members.erase(CityPreviewInfo.MULTIPLAYER_ENTRY)
	members["MISC.bin"] = PackedByteArray([1, 2, 3])
	_write_header_archive(path, members)
	var partial := CityPreviewJob.new()
	partial.path = path
	partial.run()
	assert(partial.details().map_size == 4096 and not partial.details().has("funds"), "Missing values are not invented as zero")
	assert(partial.image == null and partial.document == null)
	DirAccess.remove_absolute(path)


func _write_header_archive(path: String, members: Dictionary) -> void:
	# Header-only fixture: intentionally no terrain planes. Inspecting a header
	# does not certify that the full city can be loaded by the normal reader.
	var zip := ZIPPacker.new()
	assert(zip.open(path) == OK)
	for name: String in members:
		assert(zip.start_file(name) == OK)
		assert(zip.write_file(members[name]) == OK)
		assert(zip.close_file() == OK)
	assert(zip.close() == OK)


func _check_save_list() -> void:
	var directory := OS.get_temp_dir().path_join("city-save-list-%d" % OS.get_process_id())
	assert(DirAccess.make_dir_recursive_absolute(directory.path_join("nested")) == OK)
	var paths: Array[String] = []
	for kind in ["city", "region", "multiplayer", "legacy"]:
		var document: Sc2File = EmptyCityTemplate.create(128) if kind == "legacy" else Sc2xDocument.create_empty(32, kind).document
		if kind == "region":
			document.sc2x_extra_entries[RegionCampaign.ENTRY] = "{}".to_utf8_buffer()
		if kind == "multiplayer":
			document.sc2x_extra_entries[CityPreviewInfo.MULTIPLAYER_ENTRY] = JSON.stringify({
				"version": 1, "members": {"host": {}}, "shared": {"mode": "region"},
			}).to_utf8_buffer()
		var path := directory.path_join(kind + ".sc2x")
		assert(CityFileStore.write_verified(path, document.serialize().data).ok)
		paths.append(path)
	var cloud := CloudSync.new()
	root.add_child(cloud)
	cloud.account = {"id": "test"}
	cloud.queue = CloudQueue.new()
	cloud.status = "connected"
	cloud.saves = [{"id": "cloud-city", "deleted_at": null}]
	cloud.queue.state.bindings[paths[0]] = {"enabled": true, "save_id": "cloud-city", "revision": "1"}
	assert(cloud.local_availability(paths[0]) == 1 and cloud.local_availability(paths[1]) == 0)
	cloud.saves[0].deleted_at = "2026-11-08"
	assert(cloud.local_availability(paths[0]) == 0)
	cloud.saves[0].deleted_at = null
	cloud.status = "offline"
	assert(cloud.local_availability(paths[0]) == 1 and cloud.local_availability(paths[1]) == -1)
	cloud.status = "connected"
	var dialog := FileDialogFactory.city_open() as CityOpenDialog
	root.gui_embed_subwindows = true
	root.add_child(dialog)
	dialog.bind_cloud(cloud)
	assert(dialog.display_mode == FileDialog.DISPLAY_LIST and dialog.save_list.native_list != null)
	dialog.current_dir = directory
	dialog.popup_centered(Vector2i(1200, 720))
	var list := dialog.save_list
	var deadline := Time.get_ticks_msec() + 10000
	while (list._rows.size() < 5 or list._task >= 0 or not list._rows.any(func(row: Dictionary) -> bool: return row.has("region"))) and Time.get_ticks_msec() < deadline:
		list._process(0.2)
		await process_frame
	assert(list._task < 0 and list._rows.size() >= 5, "Detailed list metadata did not finish")
	for row in list._rows:
		if row.directory:
			continue
		assert(row.modified > 0)
		assert(row.multiplayer == (row.name == "multiplayer.sc2x"))
		assert(row.region == (row.name in ["region.sc2x", "multiplayer.sc2x"]))
	var first := list.get_root().get_first_child()
	assert(DirAccess.dir_exists_absolute(directory.path_join(first.get_text(0))), "Folders stay above files")
	var item := first
	while item != null and item.get_text(0) != "city.sc2x":
		item = item.get_next()
	assert(item != null and item.get_text(4) == list.tr("Yes"))
	item.select(0)
	list._selected()
	assert(dialog.current_file == "city.sc2x", "The detailed list must select the native file, not a sorted row index")
	list._sort(1, MOUSE_BUTTON_LEFT)
	assert(dialog.current_file == "city.sc2x")
	dialog.display_mode = FileDialog.DISPLAY_THUMBNAILS
	list._process(0.2)
	assert(not list.visible and list.native_list.visible, "Thumbnail browsing remains available")
	dialog.display_mode = FileDialog.DISPLAY_LIST
	list._process(0.2)
	var folder := list.get_root().get_first_child()
	while folder != null and folder.get_text(0) != "nested":
		folder = folder.get_next()
	assert(folder != null)
	folder.select(0)
	list._selected()
	list._activated()
	assert(dialog.current_dir.trim_suffix("/") == directory.path_join("nested"), "Double-click must retain native folder navigation")
	cloud.account = {}
	cloud.changed.emit()
	assert(cloud.local_availability(paths[0]) == -1, "Signing out clears account-specific availability")
	for locale in ["de", "es", "fr", "it", "ko", "pt_BR", "en"]:
		AppLocalization.select(locale)
		list._translate()
		assert(list.get_column_title(1) == list.tr("Date modified"))
	dialog.hide()
	dialog.queue_free()
	cloud.queue_free()
	await process_frame
	for path in paths:
		DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(directory.path_join("nested"))
	DirAccess.remove_absolute(directory)
	print("PASS: detailed city file list, legacy saves, region/multiplayer metadata, native selection, dates and account-scoped cloud availability")
