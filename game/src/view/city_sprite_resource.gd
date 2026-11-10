class_name CitySpriteResource
extends RefCounted
# cached indexed sprite pixels and their display texture

var image: Image
# Optional original hull/wake source when the display uses neutral foam.
var floating_source: Image
var model_reflection: WaterReflectionSprite
var native_size := Vector2i.ZERO
var texture: ImageTexture
var index_texture: ImageTexture
# the full-color art of the sprite at the size of `image`, or null
var artwork_image: Image
var artwork_texture: ImageTexture
var _waterline := PackedInt32Array()
var _light_source: Image
var _light_mask: Image
var _light_texture: ImageTexture
var _reflection: WaterReflectionSprite
var _reflection_palette: Sc2Palette
var _unlit_reflection_emission: Image


# Waterline rows for floating occlusion; display foam must not move the anchor.
func waterline() -> PackedInt32Array:
	if _waterline.is_empty() and image != null:
		_waterline = IsometricFloatingOcclusion.waterline(floating_source if floating_source != null else image)

	return _waterline


# Light pixels and reflected hulls depend on artwork, not the moving position.
func light_mask(source: Image, flip: bool) -> Image:
	if source != _light_source:
		_light_source = source
		_light_mask = CityBrightmaps.transform_mask(source, artwork_image if artwork_image != null else image, flip)
		_light_texture = ImageTexture.create_from_image(_light_mask) if _light_mask != null else null
		_reflection = null
	return _light_mask


func light_texture() -> ImageTexture:
	return _light_texture


func reflection(origin: Vector2i, level: int, palette: Sc2Palette, lights_enabled := true) -> WaterReflectionSprite:
	if _reflection == null or _reflection_palette != palette:
		# The moving compositor consumes large-view world pixels. HD display
		# rasters cover native_size; their texels are not extra world pixels.
		# Normalize the hull/wake and light mask together before finding contact.
		var source := _reflection_raster(floating_source if floating_source != null else image)
		var lights := _reflection_raster(_light_mask)
		_reflection = model_reflection if model_reflection!=null else WaterReflectionSprite.create(source, lights, Vector2i.ZERO, 0, palette)
		_reflection_palette = palette
	var result := WaterReflectionSprite.new()
	result.position = origin
	result.level = level
	result.image = _reflection.image
	# The native compositor needs a valid RGBA image even below the light cutoff.
	# Reuse a transparent mask; never erase the shared illuminated reflection.
	if not lights_enabled and (_unlit_reflection_emission == null or _unlit_reflection_emission.get_size() != _reflection.image.get_size()):
		_unlit_reflection_emission = Image.create(_reflection.image.get_width(), _reflection.image.get_height(), false, Image.FORMAT_RGBA8)
	result.emission = _reflection.emission if lights_enabled else _unlit_reflection_emission
	return result


func _reflection_raster(source: Image) -> Image:
	if source == null or native_size == Vector2i.ZERO or source.get_size() == native_size:
		return source
	var result := source.duplicate() as Image
	# Hull data contains palette indices: interpolating their numeric values
	# changes both color and the foam classification used by hull_columns.
	result.resize(native_size.x, native_size.y, Image.INTERPOLATE_NEAREST)
	return result
