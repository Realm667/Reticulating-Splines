class_name CityPreviewJob
extends RefCounted
## Owns a city and rendering context; produces a bounded, static whole-map view.

@warning_ignore_start("integer_division")

var document: Sc2File
var path := ""
var palette: Sc2Palette
var sprites: Sc2SpriteArchive
var graphics_key := ""
var task_id := -1
var image: Image
var saved_preview := false
var _mutex := Mutex.new()
var _cancelled := false
var _fraction := 0.0
var _details: Dictionary = {}


static var _fingerprints: Dictionary[String, String] = {}
static var _fingerprint_mutex := Mutex.new()
var _graphics_identity := ""


static func for_assets(assets: LoadedAssetState) -> CityPreviewJob:
	var result := CityPreviewJob.new()
	if assets.palette != null:
		result.palette = Sc2Palette.new()
		result.palette.colors.assign(assets.palette.colors)
		result.palette.cycles_enabled = assets.palette.cycles_enabled
		result.palette.static_cycle_indices = assets.palette.static_cycle_indices.duplicate()
		result.palette.is_index_encoding = assets.palette.is_index_encoding
	if assets.large_sprites != null:
		var source := assets.large_sprites
		result.sprites = MainMenuPresentation.copy_graphics(source)
		result.sprites.draw_building_ground = source.draw_building_ground
		result.sprites.visual_registration.assign(source.visual_registration)
		result.sprites.parcel_styles.assign(source.parcel_styles)
		result._graphics_identity = "%s|%s|%s|%s|%s|%s" % [source.get_instance_id(), source.visual_revision,
			assets.palette.to_rgba_bytes().hex_encode().sha256_text() if assets.palette != null else "",
			assets.active_scurk_path, source.visual_nature_enabled, source.visual_terrain_enabled]
	return result


# Hash the loaded graphics once per revision, on the worker. The persistent key
# follows actual pixels, including external pack edits and custom SCURK artwork.
func prepare_graphics_key() -> void:
	if sprites == null or palette == null or not graphics_key.is_empty():
		return
	_fingerprint_mutex.lock()
	graphics_key = _fingerprints.get(_graphics_identity, "") if not _graphics_identity.is_empty() else ""
	_fingerprint_mutex.unlock()
	if not graphics_key.is_empty():
		return
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(palette.to_rgba_bytes())
	hash.update(var_to_bytes([sprites.draw_building_ground, sprites.redraw_small_highway_ground,
		sprites.visual_registration, sprites.parcel_styles, sprites.visual_nature_enabled, sprites.visual_terrain_enabled]))
	var entries := sprites.entries_by_id.duplicate()
	entries.merge(sprites.visual_nature)
	var ids := entries.keys()
	ids.sort()
	for id in ids:
		var entry: Sc2SpriteArchive.SpriteEntry = entries[id]
		hash.update(var_to_bytes([id, entry.width, entry.height, entry.encoded_pixels, entry._direct_indices]))
	ids = sprites.high_resolution.keys()
	ids.sort()
	for id in ids:
		var artwork: HdSprite = sprites.high_resolution[id]
		hash.update(var_to_bytes([id, artwork.height, artwork.image.get_size(), artwork.image.get_format()]))
		hash.update(artwork.image.get_data())
	graphics_key = hash.finish().hex_encode()
	if not _graphics_identity.is_empty():
		_fingerprint_mutex.lock()
		if _fingerprints.size() > 32:
			_fingerprints.clear()
		_fingerprints[_graphics_identity] = graphics_key
		_fingerprint_mutex.unlock()


func start() -> void:
	task_id = WorkerThreadPool.add_task(run)


func cancel() -> void:
	_mutex.lock()
	_cancelled = true
	_mutex.unlock()


func cancelled() -> bool:
	_mutex.lock()
	var value := _cancelled
	_mutex.unlock()
	return value


func fraction() -> float:
	_mutex.lock()
	var value := _fraction
	_mutex.unlock()
	return value


func _progress(value: float) -> void:
	_mutex.lock()
	_fraction = value
	_mutex.unlock()


func finished() -> bool:
	return task_id >= 0 and WorkerThreadPool.is_task_completed(task_id)


func join() -> void:
	if task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(task_id)
		task_id = -1


func run() -> void:
	var digest := ""
	if cancelled():
		return
	if not path.is_empty():
		var archive := CityPreviewInfo.archive(path)
		_set_details(CityPreviewInfo.from_archive(archive))
		image = CityPreviewStore.decode(archive.get("data", {}).get(CityPreviewStore.ENTRY, PackedByteArray()))
		if image != null:
			saved_preview = true
			return
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null or file.get_length() > Sc2xDocument.MAX_ARCHIVE_BYTES:
			return
		file.close()
		# Legacy formats need their reader; native SC2X details need no terrain.
		if archive.is_empty():
			document = Sc2File.load_path(path)
			_set_details(CityPreviewInfo.from_document(document))
		if cancelled() or palette == null or sprites == null:
			return
		prepare_graphics_key()
		digest = FileAccess.get_sha256(path)
		image = CityPreviewStore.cached(digest, graphics_key)
		if image != null or cancelled():
			return
		if details().get("map_size", 0) > 512:
			return
		if document == null:
			document = Sc2File.load_path(path)
	else:
		_set_details(CityPreviewInfo.from_document(document))
	if cancelled() or document == null or not document.is_valid() or palette == null or sprites == null:
		return
	var city := CityState.from_document(document)
	if not city.is_valid() or city.map_size > 512:
		return
	prepare_graphics_key()
	image = render(city)
	if not path.is_empty():
		if cancelled() or FileAccess.get_sha256(path) != digest:
			image = null
		elif image != null:
			CityPreviewStore.store(digest, graphics_key, image)


func details() -> Dictionary:
	_mutex.lock()
	var value := _details.duplicate()
	_mutex.unlock()
	return value


func _set_details(value: Dictionary) -> void:
	_mutex.lock()
	_details = value
	_mutex.unlock()


func render(city: CityState) -> Image:
	var context := CityGpuBuildContext.new()
	var artwork := not sprites.high_resolution.is_empty()
	var error := context.prepare(city, palette, sprites, CityIsometricRenderer.VIEW_LARGE,
		CityViewMode.Mode.CITY, true, true, true, 0, false, true, 0, true, artwork, 0)
	if not error.is_empty() or cancelled():
		return null
	var extent := CityIsometricRenderer.output_size_for_view(CityIsometricRenderer.VIEW_LARGE, city.map_size)
	var reduction := IsometricImageRender.reduction_to_fit(extent, CityPreviewStore.MAX_SIZE)
	var output_size := Vector2i(ceili(float(extent.x) / reduction), ceili(float(extent.y) / reduction))
	var output := Image.create(output_size.x, output_size.y, false, Image.FORMAT_RGBA8)
	# Whole factors keep band placement exact. No full-resolution output is allocated.
	var band_height := reduction * maxi(1, 64 / reduction)
	for top in range(0, extent.y, band_height):
		if cancelled():
			return null
		var bounds := Rect2i(0, top, extent.x, mini(band_height, extent.y - top))
		var painted := context.raster_artwork(bounds, Color("18242c"), 1) if artwork else context.raster(bounds, Color("18242c"))
		if painted.has("error"):
			return null
		var band: Image = painted.image
		band.resize(output_size.x, ceili(float(bounds.size.y) / reduction), Image.INTERPOLATE_LANCZOS)
		output.blit_rect(band, Rect2i(Vector2i.ZERO, band.get_size()), Vector2i(0, top / reduction))
		_progress(float(bounds.end.y) / extent.y)
	return output
