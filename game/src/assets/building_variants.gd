class_name BuildingVariants
extends RefCounted
## Fixed SC2000 + bundled RS artwork families. IDs never enter city saves.

const FIRST := 3000000
const SPAN := 1500
const CATEGORIES := ["Residential", "Commercial", "Industrial", "Education", "Public services", "Recreation", "Ports", "Power plants", "Rewards"]
var packs: Array[Dictionary] = []
var notices := PackedStringArray()
var _bundled: GraphicsPack
var _bundled_root := ""


static func normalize(value: Variant) -> Dictionary:
	var source: Dictionary = value if value is Dictionary else {}
	# Legacy MIF paths are discarded; they cannot become mix sources.
	var result := {"enabled": bool(source.get("enabled", false)), "seed": clampi(int(source.get("seed", 0)), 0, 2147483647),
		"original_weight": clampi(int(source.get("original_weight", 50)), 0, 100),
		"rs_weight": clampi(int(source.get("rs_weight", 50)), 0, 100), "categories": []}
	var categories: Variant = source.get("categories", range(CATEGORIES.size()))
	if categories is Array:
		for item in categories:
			if item is int and item >= 0 and item < CATEGORIES.size() and not result.categories.has(item):
				result.categories.append(item)
	return result


static func supports_source(source: GameAssetSource) -> bool:
	return source != null and source.error.is_empty() and source.import_revision >= ImportedPackRevision.UNRECORDED \
		and not source.source_platform.is_empty() and source.assets != null \
		and source.assets.palette != null and source.assets.palette.cycles_enabled


static func category(id: int) -> int:
	# Connected runways/piers and small hydro/wind plants retain SC2000 art.
	# Per-tile variants would break continuous markings, edges and plant groups.
	if id in [198,199,200,221,222,223]:
		return -1
	if (id >= 112 and id <= 123) or (id >= 140 and id <= 147) or (id >= 174 and id <= 177):
		return 0
	if (id >= 124 and id <= 131) or (id >= 148 and id <= 157) or (id >= 178 and id <= 187):
		return 1
	if (id >= 132 and id <= 135) or (id >= 158 and id <= 165) or (id >= 188 and id <= 193):
		return 2
	if id in [212,214,217,245]:
		return 3
	if id in [209,210,211,216,220,233,235,236,237,244,247,250]:
		return 4
	if id in [13,213,215,218,248]:
		return 5
	if (id >= 221 and id <= 232) or id in [234,238,239,240,241,242,246,249]:
		return 6
	if id >= 198 and id <= 207:
		return 7
	if id in [208,219,243] or (id >= 251 and id <= 255):
		return 8
	return -1


func load_options(options: Dictionary, source: GameAssetSource) -> void:
	packs.clear()
	notices.clear()
	if not options.enabled:
		return
	if not supports_source(source):
		notices.append(TranslationServer.translate("Select imported SC2000 graphics in Data to mix them with Reticulating Splines."))
		return
	if options.rs_weight == 0:
		return
	var folder := PackLibrary.bundled_folder("graphics")
	if _bundled == null or _bundled_root != folder:
		_bundled = GraphicsPack.load_root(folder)
		_bundled_root = folder
	if not _bundled.error.is_empty():
		notices.append(TranslationServer.translate("The Reticulating Splines graphics pack is unavailable."))
		_bundled = null
		return
	packs.append({"large": _bundled.large_sprites, "small": _bundled.small_medium_sprites,
		"weight": options.rs_weight, "families": {}})


func prepare_families(large: Sc2SpriteArchive, small: Sc2SpriteArchive, options: Dictionary) -> void:
	for pack: Dictionary in packs:
		pack.families.clear()
		for building in range(13,256):
			if category(building) < 0 or not options.categories.has(category(building)):
				continue
			var family := []
			for view in 3:
				var id := view * 500 + building
				var base := (large if view == 2 else small).find_sprite(id)
				var archive: Sc2SpriteArchive = pack.large if view == 2 else pack.small
				var entry := archive.find_sprite(id)
				if base == null or entry == null or base.width != entry.width or entry.height > 1024 or not entry.decode_indices().ok:
					family.clear()
					break
				family.append({"entry": entry, "archive": archive})
			if family.size() == 3:
				pack.families[building] = family


func apply_to(base: Sc2SpriteArchive, options: Dictionary) -> Sc2SpriteArchive:
	if packs.is_empty():
		return base
	var result := Sc2SpriteArchive.combine([base])
	result.building_mix_seed = options.seed
	result.building_original_weight = options.original_weight
	for pack: Dictionary in packs:
		for building: int in pack.families:
			for item: Dictionary in pack.families[building]:
				var entry: Sc2SpriteArchive.SpriteEntry = item.entry
				if not base.entries_by_id.has(entry.sprite_id):
					continue
				var id := FIRST + entry.sprite_id
				var variant := Sc2SpriteArchive.entry_from_indices(id, entry.width, entry.height, entry.decode_indices().pixels)
				result.entries.append(variant)
				result.entries_by_id[id] = variant
				result.building_variants[entry.sprite_id] = PackedInt64Array([id, pack.weight])
				# RGB art, animation, light masks and registration travel together.
				var archive: Sc2SpriteArchive = item.archive
				if archive.high_resolution.has(entry.sprite_id):
					result.high_resolution[id] = archive.high_resolution[entry.sprite_id]
				if archive.visual_registration.has(entry.sprite_id):
					result.visual_registration[id] = archive.visual_registration[entry.sprite_id]
				if archive.parcel_styles.has(entry.sprite_id):
					result.parcel_styles[id] = archive.parcel_styles[entry.sprite_id]
	return result
