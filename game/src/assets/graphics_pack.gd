class_name GraphicsPack
extends RefCounted

const Png = preload("res://src/assets/indexed_png.gd")
const UI_FIELDS := ["toolbar_art", "industry_icons", "city_map_icons", "simnation_sprites", "forest_protest_image"]

var error := ""
var pack_name := ""
var partial := false
var import_revision := ImportedPackRevision.NOT_IMPORTED
var source_platform := ""
var palette: Sc2Palette
var scenario_palette: Sc2Palette
var large_sprites := Sc2SpriteArchive.new()
var small_medium_sprites := Sc2SpriteArchive.new()
var ui_images: Dictionary[String, Image] = {}
var scurk_graphics: ScurkGraphics
var city_ui_graphics: CityUiGraphics
var desktop_graphics: DesktopGraphics
var scenario_graphics: ScenarioGraphics
var visual_artwork: VisualArtwork
var _truecolor := false
var _semantic_images: Dictionary = {}
var _root := ""
var _progress := Callable()
var _files_read := 0
var _file_count := 1


static func load_root(root: String, progress := Callable()) -> GraphicsPack:
	var pack := GraphicsPack.new()
	pack._progress = progress
	pack._root = (root.get_base_dir() if root.get_file() == "pack.json" else root).simplify_path()
	pack._load()

	return pack


static func load_toolbar(root: String) -> Image:
	# Read only the UI strip: loading a second city atlas would waste memory and
	# must never replace the selected pack's palette or sprites.
	var pack := GraphicsPack.new()
	pack._root = (root.get_base_dir() if root.get_file() == "pack.json" else root).simplify_path()
	var path := pack._root.path_join("pack.json")
	if not FileAccess.file_exists(path):
		return null
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		return null
	var manifest: Dictionary = json.data
	if manifest.get("format") != "opensc2k-graphics" or manifest.get("version") != 1:
		return null
	var ui: Variant = manifest.get("ui", {})
	if not ui is Dictionary or not ui.has("toolbar_art"):
		return null
	# PNG decoding preserves the strip's own colors for indexed and RGBA packs.
	return pack._read_rgba_png(ui.toolbar_art)


func apply_to(assets: OriginalGameAssets) -> bool:
	if not error.is_empty():
		return false

	var has_large := not large_sprites.entries.is_empty()
	var has_small := not small_medium_sprites.entries.is_empty()

	# one palette for both sizes; replacing half the art mustn't recolor the other half
	# all city sprites use one indexed palette. do not recolor a retained archive
	# when a partial pack only replaces the other size group
	if partial and has_large != has_small and assets.palette != null and assets.palette.colors != palette.colors:
		return _fail("This partial pack needs both city sprite size groups to change the active palette.")

	if not partial or has_large or has_small:
		assets.palette = palette

	if scenario_palette != null:
		assets.scenario_palette = scenario_palette

	if not partial or has_large:
		assets.large_sprites = large_sprites

	if not partial or has_small:
		assets.small_medium_sprites = small_medium_sprites

	if scurk_graphics != null:
		assets.scurk_graphics = scurk_graphics

	if city_ui_graphics != null:
		assets.city_ui_graphics = city_ui_graphics

	if desktop_graphics != null:
		assets.desktop_graphics = desktop_graphics

	if scenario_graphics != null:
		assets.scenario_graphics = scenario_graphics
	if visual_artwork != null or not partial:
		assets.visual_artwork = visual_artwork

	for field in ui_images:
		assets.set(field, ui_images[field])

	return true


func _load() -> void:
	var manifest_path := _root.path_join("pack.json")

	if not FileAccess.file_exists(manifest_path):
		_fail("Missing pack.json")

		return

	var json := JSON.new()

	if json.parse(FileAccess.get_file_as_string(manifest_path)) != OK or not json.data is Dictionary:
		_fail("pack.json must contain a JSON object")

		return

	var manifest: Dictionary = json.data


	if manifest.get("format") != "opensc2k-graphics" or manifest.get("version") != 1:
		_fail("Unsupported graphics pack format or version")

		return

	if not manifest.get("name") is String or str(manifest.name).strip_edges().is_empty():
		_fail("Graphics pack name is required")

		return

	var pixel_format: Variant = manifest.get("pixel_format", "indexed")
	if pixel_format not in ["indexed", "rgba8"] or not manifest.get("semantic_images", {}) is Dictionary:
		_fail("Unsupported graphics pack format or version")
		return
	_truecolor = pixel_format == "rgba8"
	_semantic_images = manifest.get("semantic_images", {})
	if _truecolor and not manifest.has("master_sprites"):
		_fail("Unsupported graphics pack format or version")
		return
	pack_name = manifest.name
	import_revision = ImportedPackRevision.read(manifest)
	source_platform = str(manifest.get("source_platform", ""))

	if import_revision == ImportedPackRevision.INVALID:
		_fail("import_revision must be a whole number that is not negative")

		return

	var partial_value: Variant = manifest.get("partial", false)

	if not partial_value is bool:
		_fail("partial must be a boolean")
		return

	partial = partial_value
	var redraw: Variant = manifest.get("redraw_small_highway_ground", false)

	if not redraw is bool:
		_fail("redraw_small_highway_ground must be a boolean")

		return

	large_sprites.redraw_small_highway_ground = redraw
	small_medium_sprites.redraw_small_highway_ground = redraw
	if manifest.get("master_sprites") is Array:
		var numbered := NumberedFrameSequence.new()
		for i in manifest.master_sprites.size():
			if not manifest.master_sprites[i] is Dictionary:
				continue
			if _truecolor and manifest.master_sprites[i].get("animation") is Dictionary:
				if manifest.master_sprites[i].animation.get("format", "rgba") != "rgba":
					_fail("Unsupported graphics pack format or version")
					return
			manifest.master_sprites[i] = numbered.resolve(manifest.master_sprites[i], _has_png)
			if _truecolor and manifest.master_sprites[i].get("animation") is Dictionary:
				manifest.master_sprites[i].animation.format = "rgba"
			if not error.is_empty():
				return
			if not numbered.error.is_empty():
				print_verbose(numbered.error)
				_fail("Unsupported graphics pack format or version")
				return
	_file_count = maxi(1, _count_images(manifest))
	var palette_image := _read_palette(manifest.get("palette"))

	if not error.is_empty():
		return

	palette = palette_image.palette
	palette.cycles_enabled = not _truecolor
	if not partial or manifest.has("scenario_palette"):
		var scenario_image := _read_palette(manifest.get("scenario_palette"))

		if not error.is_empty():
			return

		scenario_palette = scenario_image.palette

	if manifest.has("master_sprites"):
		if manifest.has("large_sprites") or manifest.has("small_medium_sprites"):
			_fail("Unsupported graphics pack format or version")
			return
		var masters := MasterSpriteSource.new()
		if not masters.load_records(manifest.master_sprites, _read_png, palette, _read_rgba_png, manifest.get("master_canvas", "legacy"), manifest.get("master_scale", MasterSpriteSource.SCALE)):
			_fail(masters.error if error.is_empty() else error)
			return
		large_sprites = masters.large
		small_medium_sprites = masters.small_medium
		large_sprites.redraw_small_highway_ground = redraw
		small_medium_sprites.redraw_small_highway_ground = redraw
	else:
		if not _load_sprites(manifest.get("large_sprites", []), large_sprites):
			return

		if not _load_sprites(manifest.get("small_medium_sprites", []), small_medium_sprites):
			return

	var ui: Variant = manifest.get("ui")

	if partial and not manifest.has("ui"):
		ui = {}

	if not ui is Dictionary:
		_fail("ui must be an object")

		return

	for field in ui:
		if not field in UI_FIELDS:
			_fail("Unknown UI image: %s" % field)

			return

	for field in UI_FIELDS:
		if partial and not ui.has(field):
			continue

		var decoded := _read_png(ui.get(field))

		if not error.is_empty():
			return

		ui_images[field] = decoded.render_image()

	if manifest.has("scurk"):
		scurk_graphics = ScurkGraphics.load_manifest(manifest.scurk, _read_png, palette)

		if error.is_empty() and not scurk_graphics.error.is_empty():
			_fail(scurk_graphics.error)

	if error.is_empty() and manifest.has("city_ui"):
		city_ui_graphics = CityUiGraphics.load_manifest(manifest.city_ui, _read_png, palette)

		if error.is_empty() and not city_ui_graphics.error.is_empty():
			_fail(city_ui_graphics.error)

	if error.is_empty() and manifest.has("desktop"):
		desktop_graphics = DesktopGraphics.load_manifest(manifest.desktop, _read_png, palette)

		if error.is_empty() and not desktop_graphics.error.is_empty():
			_fail(desktop_graphics.error)

	if error.is_empty() and manifest.has("scenario_pictures"):
		if scenario_palette == null:
			_fail("scenario_palette is required for scenario pictures")
			return

		scenario_graphics = ScenarioGraphics.load_manifest(manifest.scenario_pictures, _read_png, scenario_palette)

		if error.is_empty() and not scenario_graphics.error.is_empty():
			_fail(scenario_graphics.error)

	if error.is_empty() and manifest.has("visual_artwork"):
		visual_artwork = VisualArtwork.load_records(manifest.visual_artwork, _read_rgba_png)
		if error.is_empty() and not visual_artwork.error.is_empty():
			_fail(visual_artwork.error)

	if (error.is_empty()
			and large_sprites.entries.is_empty()
			and small_medium_sprites.entries.is_empty()
			and ui_images.is_empty()
			and scurk_graphics == null
			and city_ui_graphics == null
			and desktop_graphics == null
			and scenario_graphics == null
			and visual_artwork == null):
		_fail("Graphics pack contains no assets")


func _load_sprites(records: Variant, archive: Sc2SpriteArchive) -> bool:
	if not records is Array or (records.is_empty() and not partial):
		return _fail("Sprite lists must be nonempty arrays")

	var duplicate_counts: Dictionary[int, int] = {}

	for record in records:
		if not record is Dictionary:
			return _fail("Sprite record must be an object")

		var identifier: Variant = record.get("id")

		if not (identifier is int or identifier is float):
			return _fail("Sprite id must be an integer")

		if identifier != int(identifier) or identifier < 0 or identifier > 65535:
			return _fail("Sprite id must be 0 through 65535")

		var decoded := _read_png(record.get("png"))

		if not error.is_empty():
			return false

		if decoded.palette.colors != palette.colors:
			return _fail("Sprite palette differs from the pack palette: %s" % record.png)

		var entry := Sc2SpriteArchive.entry_from_indices(int(identifier), decoded.width, decoded.height, decoded.pixels)
		entry.duplicate_index = int(duplicate_counts.get(entry.sprite_id, 0))
		duplicate_counts[entry.sprite_id] = entry.duplicate_index + 1
		archive.entries.append(entry)
		archive.entries_by_id[entry.sprite_id] = entry

	return true


func _has_png(relative_path: String) -> bool:
	var path := _png_path(relative_path)
	if path.is_empty():
		return false
	var exists := FileAccess.file_exists(_root.path_join(path))
	return exists


func _read_palette(relative_path: Variant) -> IndexedImageResult:
	if not _truecolor:
		return _read_png(relative_path)
	var source := _read_rgba_png(relative_path)
	if source == null:
		return null
	if source.get_size() != Vector2i(16, 16):
		_fail("Invalid PNG pixels or palette")
		return null
	var result := IndexedImageResult.new()
	result.ok = true
	result.palette = Sc2Palette.new()
	for y in 16:
		for x in 16:
			var color := source.get_pixel(x, y)
			color.a = 1.0
			result.palette.colors.append(color)
	return result


func _read_png(relative_path: Variant) -> IndexedImageResult:
	if _truecolor:
		var source := _read_rgba_png(relative_path)
		if source == null:
			return null
		var semantic: Image
		if _semantic_images.has(relative_path):
			semantic = _read_rgba_png(_semantic_images[relative_path])
			if semantic == null:
				return null
		var result := TrueColorPackImage.decode(source, palette, semantic)
		if not result.ok:
			_fail(result.error)
			return null
		return result
	_report_progress()
	var path := _png_path(relative_path)
	if path.is_empty():
		return null
	var decoded := Png.load_path(_root.path_join(path))
	if not decoded.ok:
		_fail("%s: %s" % [path, decoded.error])
		return null
	return decoded


func _read_rgba_png(relative_path: Variant) -> Image:
	_report_progress()
	var path := _png_path(relative_path)
	if path.is_empty():
		return null
	var bytes := FileAccess.get_file_as_bytes(_root.path_join(path))
	if bytes.size() < 24 or bytes.slice(0, 8) != PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10]):
		_fail("Cannot read visual artwork PNG: %s" % path)
		return null
	var header := StreamPeerBuffer.new()
	header.data_array = bytes.slice(16, 24)
	header.big_endian = true
	var width := header.get_u32()
	var height := header.get_u32()
	if width < 1 or height < 1 or width > 8192 or height > 8192:
		_fail("Visual artwork PNG dimensions must be 1 through 8192: %s" % path)
		return null
	var image := Image.new()
	if bytes.is_empty() or image.load_png_from_buffer(bytes) != OK:
		_fail("Cannot read visual artwork PNG: %s" % path)
		return null
	image.convert(Image.FORMAT_RGBA8)
	return image


func _png_path(relative_path: Variant) -> String:
	if not relative_path is String or relative_path.is_empty():
		_fail("PNG path must be a nonempty string")

		return ""

	var path: String = relative_path

	if path.is_absolute_path() or path.contains(":") or path.contains("\\"):
		_fail("PNG paths must be relative and use forward slashes")

		return ""

	for component in path.split("/"):
		if component in ["", ".", ".."]:
			_fail("PNG paths must not contain empty, dot, or parent components")

			return ""

	if path.get_extension().to_lower() != "png":
		_fail("Graphics files must be PNG")

		return ""
	return path


static func _count_images(value: Variant) -> int:
	if value is String:
		return int(value.get_extension().to_lower() == "png")
	var count := 0
	if value is Dictionary or value is Array:
		for child in (value.values() if value is Dictionary else value):
			count += _count_images(child)
	return count


func _report_progress() -> void:
	if _progress.is_valid():
		_progress.call(clampf(float(_files_read) / _file_count, 0.0, 1.0))
	_files_read += 1


func _fail(message: String) -> bool:
	error = message

	return false
