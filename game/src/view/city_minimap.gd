class_name CityMinimap
extends RefCounted
## City Map window images. The native library selects each tile color.

const MODES := [
	"structures",
	"zones",
	"roads",
	"rail",
	"traffic",
	"power",
	"water",
	"density",
	"growth",
	"crime",
	"police_power",
	"police_stations",
	"pollution",
	"land_value",
	"fire_power",
	"fire_stations",
	"schools",
	"colleges",
]


# one pixel per tile up to 1024 tiles. a larger map samples every second or
# fourth tile, since the map window never shows more than 1024 pixels
static func create_image(city: CityState, palette: Sc2Palette, mode := "structures", modern := false) -> Image:
	var map_edge: int = city.map_size if city != null else 128
	var image_edge := NativeCityMinimap.image_edge(map_edge)

	if city != null and city.is_valid() and palette != null and palette.is_valid():
		var colors := modern_palette(palette, mode) if modern else palette
		var image := NativeCityMinimap.create_image(_request(city, mode), colors.to_rgba_bytes())

		if image != null:
			return image

	return Image.create(image_edge, image_edge, false, Image.FORMAT_RGBA8)


# The native tile classification and all hit coordinates remain unchanged.
static func modern_palette(source: Sc2Palette, mode: String) -> Sc2Palette:
	var result := Sc2Palette.new()
	result.colors.assign(source.colors)
	result.colors[0] = Color("8295a1")
	result.colors[0x62] = Color("326c8b")
	result.colors[0x43] = Color("527960") if mode != "growth" else Color("87c77a")
	result.colors[0x35] = Color("998675")
	result.colors[0x3b] = Color("85b98a")
	result.colors[0x5c] = Color("7da8ce")
	result.colors[0x32] = Color("e0c675") if mode not in ["power", "water"] else Color("70c3b5")
	result.colors[0x1d] = Color("d38979")
	result.colors[0xff] = Color("e7efb1")
	for index in 13:
		result.colors[0x80 - index] = Color("839575").lerp(Color("b6ad95"), index / 12.0)
	for index in 16:
		result.colors[0x9b + index] = Color("326d83").lerp(Color("e66780"), index / 15.0)
	return result


# the palette index of one tile. tiles outside the map are 0
static func color_index(city: CityState, x: int, y: int, mode := "structures") -> int:
	if city == null or not city.is_valid():
		return 0

	return maxi(0, NativeCityMinimap.color_index(_request(city, mode), x, y))


static func _request(city: CityState, mode: String) -> Dictionary:
	var chunk_id := NativeCityMinimap.data_chunk(mode)
	var data := PackedByteArray()

	# a data map of an unexpected size reads as zero
	if not chunk_id.is_empty():
		var chunk := city.document.find_chunk(chunk_id)

		if chunk != null and chunk.decoded_payload.size() == city.document.decoded_size(chunk_id):
			data = chunk.decoded_payload

	return {"edge": city.map_size, "buildings": city.buildings, "zones": city.zones, "flags": city.tile_flags,
		"underground": city.underground, "altitude": city.altitude_words, "quarter_heights":city.quarter_heights,"mode": mode, "data": data}
