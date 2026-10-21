class_name BuildingVariants
extends RefCounted
## Local SCURK artwork families. Their IDs never enter the city or simulation.

const FIRST := 3000000
const SPAN := 1500
const MAX_PACKS := 8
const MAX_FILE_BYTES := 16 * 1024 * 1024
const MAX_DECODED_BYTES := 64 * 1024 * 1024
const CATEGORIES := ["Residential", "Commercial", "Industrial", "Education", "Public services", "Recreation", "Ports", "Power plants", "Rewards"]
var packs: Array[Dictionary] = []
var notices := PackedStringArray()
var decoded_bytes := 0


static func normalize(value: Variant) -> Dictionary:
	var source: Dictionary = value if value is Dictionary else {}
	var result := {"enabled": bool(source.get("enabled", false)), "seed": clampi(int(source.get("seed", 0)), 0, 2147483647),
		"original_weight": clampi(int(source.get("original_weight", 50)), 0, 100), "categories": [], "packs": []}
	var categories: Variant = source.get("categories", range(CATEGORIES.size()))
	if categories is Array:
		for category in categories:
			if category is int and category >= 0 and category < CATEGORIES.size() and not result.categories.has(category):
				result.categories.append(category)
	var choices: Variant = source.get("packs", [])
	if choices is Array:
		for choice in choices:
			if not choice is Dictionary or not choice.get("path", "") is String:
				continue
			var path := str(choice.path).strip_edges()
			if path.is_empty() or result.packs.any(func(p: Dictionary) -> bool: return p.path == path):
				continue
			result.packs.append({"path": path, "enabled": bool(choice.get("enabled", true)), "weight": clampi(int(choice.get("weight", 50)), 0, 100)})
			if result.packs.size() == MAX_PACKS:
				break
	return result


static func category(id: int) -> int:
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


func load_options(options: Dictionary) -> void:
	packs.clear()
	notices.clear()
	decoded_bytes = 0
	if not options.enabled:
		return
	var known := {}
	for choice: Dictionary in options.packs:
		if not choice.enabled or choice.weight == 0:
			continue
		var file := FileAccess.open(choice.path, FileAccess.READ)
		if file == null or file.get_length() > MAX_FILE_BYTES:
			notices.append(TranslationServer.translate("Unavailable tile set: %s") % str(choice.path).get_file())
			continue
		var bytes := file.get_buffer(file.get_length())
		file.close()
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(bytes)
		var identity := hash.finish().hex_encode()
		if known.has(identity):
			known[identity].weight = maxi(int(known[identity].weight),int(choice.weight))
			continue
		var mif := ScurkMif.new()
		if not mif.parse(bytes):
			notices.append(TranslationServer.translate("Invalid tile set: %s") % str(choice.path).get_file())
			continue
		var size := 0
		for entry: Sc2SpriteArchive.SpriteEntry in mif.overrides.entries:
			size += entry.width * entry.height * 8
		if decoded_bytes + size > MAX_DECODED_BYTES:
			notices.append(TranslationServer.translate("Tile set memory limit reached."))
			continue
		decoded_bytes += size
		var record := {"id": identity, "mif": mif, "weight": choice.weight, "families": {}, "path": choice.path}
		known[identity] = record
		packs.append(record)
	packs.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.id < b.id)


func uses_dos_colors() -> bool:
	return packs.any(func(pack: Dictionary) -> bool: return pack.mif.uses_dos_colors())


func prepare_families(large: Sc2SpriteArchive, small: Sc2SpriteArchive, options: Dictionary) -> void:
	for pack: Dictionary in packs:
		pack.families.clear()
		var skipped := 0
		for building in range(13,256):
			if category(building) < 0 or not options.categories.has(category(building)):
				continue
			var family := []
			var different := false
			for view in 3:
				var id := view * 500 + building
				var base := (large if view == 2 else small).find_sprite(id)
				var entry: Sc2SpriteArchive.SpriteEntry = pack.mif.overrides.find_sprite(id)
				if base == null or entry == null or base.width != entry.width or entry.height > 1024:
					family.clear()
					break
				var decoded := entry.decode_indices()
				if not decoded.ok:
					family.clear()
					break
				different = different or base.height != entry.height or decoded.pixels != base.decode_indices().pixels
				family.append(entry)
			if family.size() == 3 and different:
				pack.families[building] = family
			elif pack.mif.overrides.find_sprite(1000+building) != null:
				skipped += 1
		if skipped > 0:
			notices.append(TranslationServer.translate("%s: %d unchanged or incomplete building families skipped.") % [str(pack.path).get_file(),skipped])


func apply_to(base: Sc2SpriteArchive, options: Dictionary) -> Sc2SpriteArchive:
	if packs.is_empty():
		return base
	var result := Sc2SpriteArchive.combine([base])
	result.building_mix_seed = options.seed
	result.building_original_weight = options.original_weight
	for index in packs.size():
		var pack := packs[index]
		for building: int in pack.families:
			for entry: Sc2SpriteArchive.SpriteEntry in pack.families[building]:
				if not base.entries_by_id.has(entry.sprite_id):
					continue
				var id := FIRST + index * SPAN + entry.sprite_id
				var variant := Sc2SpriteArchive.entry_from_indices(id,entry.width,entry.height,entry.decode_indices().pixels)
				result.entries.append(variant)
				result.entries_by_id[id] = variant
				var choices: PackedInt64Array = result.building_variants.get(entry.sprite_id,PackedInt64Array())
				choices.append(id)
				choices.append(pack.weight)
				result.building_variants[entry.sprite_id] = choices
	return result
