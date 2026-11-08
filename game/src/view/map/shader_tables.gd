class_name CityMapShaderTables
extends RefCounted
## Fit city materials into eight custom texture units (16 total on macOS GL).
## LUT images only change on profile reload. PaletteAnimationClock owns the
## tiny animated two-row palette so no atlas is read back or rebound each frame.

const LUT_KEYS := ["environment_day_luts", "environment_season_luts", "environment_weather_luts", "environment_lut"]
var _sources: Array = []
var _parameters: Dictionary = {}


func parameters(values: Dictionary) -> Dictionary:
	var sources: Array = []
	for key in LUT_KEYS:
		sources.append(values.get(key))
	if sources == _sources and not _parameters.is_empty():
		return _parameters
	_sources = sources
	var images: Array[Image] = []
	var width := 1
	var height := 0
	for source: Texture2D in sources:
		var image := source.get_image() if source != null else Image.create(1, 1, false, Image.FORMAT_RGB8)
		image.convert(Image.FORMAT_RGB8)
		images.append(image)
		width = maxi(width, image.get_width())
		height += image.get_height()
	var atlas := Image.create(width, height, false, Image.FORMAT_RGB8)
	var rects := PackedVector4Array()
	var y := 0
	for image in images:
		atlas.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i(0, y))
		rects.append(Vector4(0.0, float(y) / height, float(image.get_width()) / width, float(image.get_height()) / height))
		y += image.get_height()
	_parameters = {"map_lut_tables": ImageTexture.create_from_image(atlas), "map_lut_rects": rects}
	return _parameters


static func palette_image(surface: Image, underground: Image) -> Image:
	var result := Image.create(256, 2, false, Image.FORMAT_RGBA8)
	for row in 2:
		var source := surface if row == 0 or underground == null else underground
		if source != null:
			result.blit_rect(source, Rect2i(0, 0, 256, 1), Vector2i(0, row))
	return result
