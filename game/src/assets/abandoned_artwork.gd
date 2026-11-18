class_name AbandonedArtwork
extends RefCounted
## Display-only families. The city stores the abandoned tile and its zone.
## Columns are residential, commercial and industrial sprites of the same size.
const SOURCES := {
	138: [112, 124, 132], 139: [120, 130, 135],
	170: [140, 149, 158], 171: [142, 153, 160],
	172: [145, 156, 162], 173: [147, 157, 165],
	196: [174, 178, 188], 197: [176, 183, 192],
}
const FIRST := BuildingVariants.FIRST + BuildingVariants.SPAN
const END := FIRST + 3 * BuildingVariants.SPAN


static func weathered(color: Color) -> Color:
	var value := color.get_luminance() * 0.84
	if color.g > color.r * 1.08 and color.g > color.b * 1.12:
		return Color(minf(value * 1.13, 1.0), value * 0.81, value * 0.49, color.a)
	return Color(value, value, value, color.a)


static func _static_index(index: int) -> bool:
	return not (index >= Sc2Palette.FAST_CYCLE_START and index < Sc2Palette.FAST_CYCLE_START + Sc2Palette.FAST_CYCLE_COUNT) \
		and not (index >= Sc2Palette.SLOW_CYCLE_START and index < Sc2Palette.SLOW_CYCLE_START + Sc2Palette.SLOW_CYCLE_COUNT)


static func palette_map(palette: Sc2Palette) -> PackedByteArray:
	var lookup := PackedByteArray()
	for color in palette.colors:
		var target := weathered(color)
		var gray := target.r == target.b
		var nearest := 0
		var best := INF
		for index in palette.colors.size():
			if not _static_index(index):
				continue
			var candidate := palette.colors[index]
			var distance := Vector3(candidate.r - target.r, candidate.g - target.g, candidate.b - target.b).length_squared()
			if gray and not (candidate.r8 == candidate.g8 and candidate.g8 == candidate.b8):
				distance += 4.0
			elif not gray and not (candidate.r > candidate.g and candidate.g > candidate.b):
				distance += 4.0
			if distance < best:
				best = distance
				nearest = index
		lookup.append(nearest)
	return lookup


static func apply(base: Sc2SpriteArchive, lookup: PackedByteArray, share: int, images: Dictionary) -> Sc2SpriteArchive:
	if base == null or not base.is_valid():
		return base
	var result := Sc2SpriteArchive.combine([base])
	result.building_variants.assign(base.building_variants)
	result.building_mix_seed = base.building_mix_seed
	result.building_original_weight = base.building_original_weight
	result.abandoned_percent = share
	for view in 3:
		for tile: int in SOURCES:
			var id := view * 500 + tile
			var standard := base.find_sprite(id)
			if standard == null:
				continue
			var family := PackedInt64Array()
			for sector in 3:
				var source_id := view * 500 + int(SOURCES[tile][sector])
				var source := base.find_sprite(source_id)
				if source == null:
					continue
				var footprint := base.visual_registration.get(source_id, Vector3i(source.width, 0, 0)) as Vector3i
				var lot := base.visual_registration.get(id, Vector3i(standard.width, 0, 0)) as Vector3i
				if footprint.x != lot.x:
					continue
				var decoded := source.decode_indices()
				if not decoded.ok:
					continue
				var pixels := decoded.pixels.duplicate()
				for i in pixels.size():
					if pixels[i] >= 0:
						pixels[i] = lookup[pixels[i]]
				var alias := FIRST + sector * BuildingVariants.SPAN + id
				var entry := Sc2SpriteArchive.entry_from_indices(alias, source.width, source.height, pixels)
				result.entries.append(entry)
				result.entries_by_id[alias] = entry
				family.append_array(PackedInt64Array([alias, 1]))
				if base.visual_registration.has(source_id):
					result.visual_registration[alias] = footprint
				if base.parcel_styles.has(source_id):
					var parcel := base.parcel_styles[source_id].duplicate()
					parcel[0] = weathered(Color.hex(parcel[0])).to_rgba32()
					result.parcel_styles[alias] = parcel
				if base.high_resolution.has(source_id):
					result.high_resolution[alias] = _still(base.high_resolution[source_id], images)
			if not family.is_empty():
				result.building_variants[id] = family
	return result if result.entries.size() > base.entries.size() else base


## Several zooms can share the same source image, but use different logical heights.
static func _still(hd: HdSprite, images: Dictionary) -> HdSprite:
	if not images.has(hd.image):
		var image := hd.image.duplicate() as Image
		image.convert(Image.FORMAT_RGBA8)
		for y in image.get_height():
			for x in image.get_width():
				image.set_pixel(x, y, weathered(image.get_pixel(x, y)))
		images[hd.image] = image
	var still := HdSprite.new()
	still.image = images[hd.image]
	still.height = hd.height
	return still
