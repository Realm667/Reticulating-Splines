class_name CityEdgeProfile
extends RefCounted
## Tiny display-only height strip for the two exposed faces of the map.

var _signature: Array = []
var _texture: ImageTexture
var image: Image


func texture_for(city: CityState) -> Texture2D:
	if city == null:
		return null
	var signature := [city.get_instance_id(), city.chunk_revision("ALTM"), city.chunk_revision("XTER"),
		city.chunk_revision("XBIT"), city.compass_rotation()]
	if signature == _signature:
		return _texture
	_signature = signature
	var edge := city.map_size
	image = Image.create(edge, 2, false, Image.FORMAT_RGBAF)
	for face in 2:
		for along in edge:
			var tile := Vector2i(edge - 1, along) if face == 0 else Vector2i(along, edge - 1)
			# CityRotation already rotates the tile arrays into view coordinates.
			# Applying compass rotation here a second time samples a different edge.
			image.set_pixel(along, face, Color(city.land_altitude(tile.x, tile.y) / 31.0,
				city.water_altitude(tile.x, tile.y) / 31.0, float(city.is_water(tile.x, tile.y)), 1))
	# Smooth along the whole visible perimeter, including the shared front corner.
	# This is a rendering profile only; the actual land/water heights stay intact.
	var weights := [1.0, 4.0, 6.0, 4.0, 1.0]
	for face in 2:
		for along in edge:
			var perimeter := along if face == 0 else 2 * (edge - 1) - along
			var surface := 0.0
			for tap in 5:
				var sample_index := clampi(perimeter + tap - 2, 0, 2 * (edge - 1))
				var sample_face := 0 if sample_index < edge else 1
				var sample_along := sample_index if sample_face == 0 else 2 * (edge - 1) - sample_index
				surface += image.get_pixel(sample_along, sample_face).r * weights[tap] / 16.0
			var pixel := image.get_pixel(along, face)
			pixel.a = surface
			image.set_pixel(along, face, pixel)
	if _texture != null and _texture.get_width() == edge:
		_texture.update(image)
	else:
		_texture = ImageTexture.create_from_image(image)
	return _texture
