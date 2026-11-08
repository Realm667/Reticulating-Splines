class_name ExpandedGraphics
extends RefCounted
## Shared authored artwork for both original and standalone graphics sources.

@warning_ignore_start("integer_division")

const ROOT := "res://assets/expanded/"
static var _entries: Array[Sc2SpriteArchive.SpriteEntry] = []
static var _lights: Dictionary[int, Image] = {}


static func _prepare() -> void:
	if not _entries.is_empty():
		return
	for kind in 8:
		var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + ExpandedRules.SLUGS[kind] + ".json"))
		var light := (load(ROOT + ExpandedRules.SLUGS[kind] + "-light.png") as Texture2D).get_image()
		for view in 3:
			var divisor := 4 >> view
			var width := int(source.width) / divisor
			var height := (int(source.height) + divisor - 1) / divisor
			var pixels := PackedInt32Array()
			pixels.resize(width * height)
			for y in height:
				for x in width:
					pixels[y * width + x] = int(source.indices[mini(int(source.height) - 1, y * divisor) * int(source.width) + x * divisor])
			var id := ExpandedRules.FIRST_SPRITE + view * 500 + kind
			_entries.append(Sc2SpriteArchive.entry_from_indices(id, width, height, pixels))
			var mask: Image = light.duplicate()
			mask.resize(width, height, Image.INTERPOLATE_NEAREST)
			_lights[id] = mask


static func apply(archive: Sc2SpriteArchive) -> void:
	if archive == null:
		return
	_prepare()
	for entry in _entries:
		if not archive.entries_by_id.has(entry.sprite_id):
			archive.entries.append(entry)
			archive.entries_by_id[entry.sprite_id] = entry
	lights(archive)


static func lights(archive: Sc2SpriteArchive) -> void:
	for id: int in _lights:
		if archive.entries_by_id.has(id):
			archive.visual_emission[id] = _lights[id]
