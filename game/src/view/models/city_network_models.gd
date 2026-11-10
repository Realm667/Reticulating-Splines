class_name CityNetworkModels
extends RefCounted
## Optional local rendering resources. City documents and simulation remain read-only.

const Geometry = preload("res://src/view/models/network_model_geometry.gd")
const Raster = preload("res://src/view/models/network_model_raster.gd")
const ADMISSION_PATH := "res://assets/data/network_model_sources.json"
const VERSION := 3
static var _admission: Dictionary = {}


static func fingerprint(entry: Sc2SpriteArchive.SpriteEntry) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(entry.decode_indices().pixels.to_byte_array())
	return context.finish().hex_encode()


static func configure(archive: Sc2SpriteArchive, palette: Sc2Palette, enabled: bool) -> bool:
	if archive == null or palette == null:
		return false
	var previous := archive.network_model_signature
	if enabled:
		prepare(archive, palette)
	var changed := previous != archive.network_model_signature or archive.visual_models_enabled != enabled
	archive.visual_models_enabled = enabled
	if changed:
		archive.visual_revision += 1
	return changed


static func prepare(archive: Sc2SpriteArchive, palette: Sc2Palette) -> void:
	archive.network_model_palette=palette
	if _admission.is_empty():
		var content: Variant = JSON.parse_string(FileAccess.get_file_as_string(ADMISSION_PATH))
		if content is Dictionary:
			_admission = content.get("sprites", {})
	var source_key: Array = [VERSION, palette.to_rgba_bytes()]
	var ids: Array[int] = []
	var hd_hashes: Dictionary[int, String] = {}
	for id: int in archive.entries_by_id:
		if id % 500 < 14 or id % 500 > 111 or id >= 1500:
			continue
		ids.append(id)
	ids.sort()
	for id in ids:
		var entry: Sc2SpriteArchive.SpriteEntry = archive.entries_by_id[id]
		var hd := archive.high_resolution.get(id) as HdSprite
		if hd != null:
			hd_hashes[id] = hd.image.get_data().hex_encode().sha256_text()
		source_key.append([id,entry.pixel_hash(),entry.width,entry.height,hd_hashes.get(id, "")])
	var signature := var_to_bytes(source_key).hex_encode().sha256_text()
	if signature == archive.network_model_signature:
		return
	var entries: Dictionary[int, Sc2SpriteArchive.SpriteEntry] = {}
	var heights: Dictionary[int, PackedFloat32Array] = {}
	var library := Geometry.Library.new(Geometry.build, Geometry.template)
	for id in ids:
		var entry: Sc2SpriteArchive.SpriteEntry = archive.entries_by_id[id]
		var choices: Dictionary = _admission.get(str(id), {})
		var allowed: Dictionary = choices.get(fingerprint(entry), {})
		if allowed.is_empty() or entry.width != int(allowed.width) or entry.height != int(allowed.height):
			continue
		if archive.high_resolution.has(id):
			if hd_hashes[id] != str(allowed.get("hd_hash", "")):
				continue
		var source := Image.create(entry.width,entry.height,false,Image.FORMAT_RGBA8)
		# Only admitted original SC2000 pixels guide materials. Other compatible
		# sets use the same SC2000-derived procedural materials and geometry.
		if allowed.get("reference", false):
			source = entry.create_image(palette).image
		var model: Dictionary = library.acquire(id % 500)
		var recipe: Dictionary = {"parts":model.mesh.parts,"footprint":model.footprint,"ports":model.ports}
		var result: Dictionary = Raster.render(id % 500,source,palette,id / 500,recipe)
		var replacement: Sc2SpriteArchive.SpriteEntry = result.entry
		replacement.sprite_id = id
		entries[id] = replacement
		heights[id] = result.height
	archive.network_model_entries = entries
	archive.network_model_heights = heights
	archive.network_model_signature = signature
	archive.network_model_revision += 1
	archive.network_model_meshes = library.meshes.size()


static func copy_state(source: Sc2SpriteArchive, target: Sc2SpriteArchive) -> void:
	# Prepared entries and metadata are immutable after publication.
	target.network_model_palette=source.network_model_palette
	target.network_model_entries = source.network_model_entries
	target.network_model_heights = source.network_model_heights
	target.network_model_signature = source.network_model_signature
	target.network_model_revision = source.network_model_revision
	target.network_model_meshes = source.network_model_meshes
	target.visual_models_enabled = source.visual_models_enabled
