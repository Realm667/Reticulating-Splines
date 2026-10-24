class_name VisualArtwork
extends RefCounted
## Optional independent artwork for cosmetic environment and city-life rendering.

const CLOUDS := ["cumulus", "stratus", "altostratus", "cirrus", "cirrocumulus"]
const VEHICLES := ["car", "truck", "bus"]
const MAX_DECODED_BYTES := 768 * 1024 * 1024

class Frame extends RefCounted:
	var image: Image
	var emission: Image
	var season_mask: Image
	var logical_size := Vector2i.ZERO
	var scale := 4

var error := ""
var frames: Dictionary[String, Frame] = {}
var _decoded_bytes := 0
var city_life_scale := 1


static func load_records(records: Variant, read_image: Callable) -> VisualArtwork:
	var artwork := VisualArtwork.new()
	artwork._load(records, read_image)
	return artwork


func _load(records: Variant, read_image: Callable) -> void:
	if not records is Array or records.is_empty() or records.size() > 2000:
		_fail("visual_artwork must be a nonempty array of at most 2000 records")
		return

	var images: Dictionary[String, Image] = {}
	var recolored: Dictionary[String, Image] = {}
	for record: Variant in records:
		if not record is Dictionary or not record.get("key") is String:
			_fail("Visual artwork records require a string key")
			return
		var key: String = record.key
		if not _valid_key(key) or frames.has(key):
			_fail("Invalid or repeated visual artwork key: %s" % key)
			return
		var size: Variant = record.get("logical_size")
		if not size is Array or size.size() != 2 or not _whole(size[0], 1, 2048) or not _whole(size[1], 1, 2048):
			_fail("Visual artwork logical_size must contain two positive whole dimensions")
			return
		if not _whole(record.get("master_scale"), 1, 4) or int(record.master_scale) not in [1, 2, 4]:
			_fail("Unsupported graphics pack format or version")
			return
		var frame := Frame.new()
		frame.logical_size = Vector2i(size[0], size[1])
		frame.scale = int(record.master_scale)
		if key.begins_with("person/") or key.begins_with("vehicle/"):
			city_life_scale = maxi(city_life_scale, frame.scale)
		if key.begins_with("woodland/") and frame.logical_size != Vector2i(32, 36):
			_fail("Woodland artwork must retain its 32 by 36 logical frame")
			return
		if key.begins_with("person/") and frame.logical_size != Vector2i(3, 6):
			_fail("Pedestrian artwork must retain its 3 by 6 logical frame")
			return
		frame.image = _image(record.get("png"), read_image, images)
		if frame.image == null:
			return
		if record.has("palette_swap"):
			frame.image = _palette_image(frame.image, record.palette_swap, record.png, recolored)
			if frame.image == null:
				return
		if frame.image.get_size() != frame.logical_size * frame.scale:
			_fail("Visual artwork dimensions differ from logical_size times master_scale: %s" % key)
			return
		for field: String in ["lightmap", "season_mask"]:
			if not record.has(field):
				continue
			var mask := _image(record[field], read_image, images)
			if mask == null:
				return
			if mask.get_size() != frame.image.get_size():
				_fail("Visual artwork mask dimensions differ: %s" % key)
				return
			if field == "lightmap":
				frame.emission = mask
			else:
				frame.season_mask = mask
		frames[key] = frame


func _palette_image(source: Image, values: Variant, path: String, cache: Dictionary[String, Image]) -> Image:
	if not values is Array or values.is_empty() or values.size() > 256:
		_fail("palette_swap must contain 1 to 256 RGBA hex colors")
		return null
	var colors := PackedByteArray()
	var names := PackedStringArray()
	for value: Variant in values:
		if not value is String or value.length() != 8:
			_fail("palette_swap colors must be eight hexadecimal digits")
			return null
		for character: String in value:
			if not character in "0123456789abcdefABCDEF":
				_fail("palette_swap colors must be eight hexadecimal digits")
				return null
		names.append(value.to_lower())
		colors.append_array(value.hex_decode())
	var key := path + "|" + ",".join(names)
	if cache.has(key):
		return cache[key]
	var bytes := source.get_width() * source.get_height() * 4
	if _decoded_bytes + bytes > MAX_DECODED_BYTES:
		_fail("Visual artwork exceeds the decoded image budget")
		return null
	var rgba := source
	if rgba.get_format() != Image.FORMAT_RGBA8:
		rgba = source.duplicate()
		rgba.convert(Image.FORMAT_RGBA8)
	var indices := rgba.get_data()
	var output := PackedByteArray()
	output.resize(bytes)
	for at in range(0, bytes, 4):
		var index := int(indices[at])
		if indices[at + 1] != index or indices[at + 2] != index or indices[at + 3] != 255 or index >= values.size():
			_fail("Palette source must contain opaque grayscale indices within palette_swap")
			return null
		for channel in 4:
			output[at + channel] = colors[index * 4 + channel]
	var image := Image.create_from_data(source.get_width(), source.get_height(), false, Image.FORMAT_RGBA8, output)
	_decoded_bytes += bytes
	cache[key] = image
	return image


func _image(path: Variant, read_image: Callable, images: Dictionary[String, Image]) -> Image:
	if not path is String or path.is_empty():
		_fail("Visual artwork PNG path must be a nonempty string")
		return null
	if not images.has(path):
		var image: Image = read_image.call(path)
		if image == null or image.is_empty():
			_fail("Cannot read visual artwork PNG: %s" % path)
			return null
		_decoded_bytes += image.get_width() * image.get_height() * 4
		if _decoded_bytes > MAX_DECODED_BYTES:
			_fail("Visual artwork exceeds the decoded image budget")
			return null
		images[path] = image
	return images[path]


static func _valid_key(key: String) -> bool:
	var parts := key.split("/")
	if parts.size() == 2:
		return ((parts[0] == "cloud" and parts[1] in CLOUDS)
			or (parts[0] == "ground" and _index(parts[1], 1256, 1268)))
	if parts.size() != 4:
		return false
	match parts[0]:
		"vehicle":
			return parts[1] in VEHICLES and _index(parts[2], 0, 17) and _index(parts[3], 0, 7)
		"person":
			return _index(parts[1], 0, 5) and _index(parts[2], 0, 7) and _index(parts[3], 0, 1)
		"woodland":
			return _index(parts[1], 1, 7) and _index(parts[2], 0, 15) and _index(parts[3], 0, 7)
	return false


static func _index(value: String, low: int, high: int) -> bool:
	return value.is_valid_int() and str(int(value)) == value and int(value) >= low and int(value) <= high


static func _whole(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and value >= low and value <= high and value == int(value)


func _fail(message: String) -> void:
	error = message
	frames.clear()
