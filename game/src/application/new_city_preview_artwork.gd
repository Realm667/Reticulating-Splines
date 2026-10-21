class_name NewCityPreviewArtwork
extends RefCounted
## Bounded, detached preview images prepared by the terrain worker.
@warning_ignore_start("integer_division")

static func seasons(city: CityState, sprites: Sc2SpriteArchive, view: int, maximum: Vector2i, progress: Callable) -> Image:
	var context := CityGpuBuildContext.new()
	var error := context.prepare(city, Sc2Palette.index_encoding(), sprites, view,
		CityViewMode.Mode.CITY, true, true, true, 0, false)
	if not error.is_empty():
		return null
	var size := CityIsometricRenderer.output_size_for_view(view, city.map_size)
	var reduction := IsometricImageRender.reduction_to_fit(size, maximum)
	var output_size := Vector2i(ceili(float(size.x) / reduction), ceili(float(size.y) / reduction))
	var output := Image.create(output_size.x, output_size.y, false, Image.FORMAT_RGBA8)
	var band_height := reduction * maxi(1, 128 / reduction)
	for top in range(0, size.y, band_height):
		var band := Rect2i(0, top, size.x, mini(band_height, size.y - top))
		var image: Image = context.builder.auxiliary_raster(band, sprites.visual_seasons, false)
		if image == null:
			return null
		if reduction > 1:
			image.resize(output_size.x, ceili(float(band.size.y) / reduction), Image.INTERPOLATE_NEAREST)
		output.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i(0, top / reduction))
		progress.call(0.65 + float(band.end.y) / size.y * 0.3)
	return output


static func preview_palette(source: Sc2Palette) -> Sc2Palette:
	var result := Sc2Palette.new()
	result.colors.assign(source.colors)
	result.cycles_enabled = source.cycles_enabled
	result.static_cycle_indices = source.static_cycle_indices.duplicate()
	# At overview scale individual wave geometry is subpixel. Preserve the
	# palette animation with the same cool water colors as the minimap.
	var water := CityWaterLayer.blue_indices(source)
	for index in water.size():
		if water[index] == 0:
			continue
		var brightness := source.color(index).v
		result.colors[index] = Color("315b70").lerp(Color("6096a4"), brightness)
	return result


static func minimap(city: CityState) -> Image:
	# Bounded topographic overview, using the same summer greens and cool
	# water family as the enhanced landscape instead of palette neon colors.
	var edge := mini(city.map_size, 512)
	var image := Image.create(edge, edge, false, Image.FORMAT_RGB8)
	for y in edge:
		var tile_y := mini(city.map_size - 1, int((y + 0.5) * city.map_size / edge))
		for x in edge:
			var tile_x := mini(city.map_size - 1, int((x + 0.5) * city.map_size / edge))
			var index := tile_y * city.map_size + tile_x
			var height := city.land_altitude(tile_x, tile_y)
			var color := Color("3f7586")
			if not city.is_water(tile_x, tile_y):
				color = Color("889267").lerp(Color("c4c0a1"), clampf(height / 31.0, 0, 1))
				if city.buildings[index] >= 6 and city.buildings[index] <= 13:
					color = Color("41684b").lerp(Color("698259"), (city.buildings[index] - 6) / 7.0)
				var slope := height - city.land_altitude(maxi(0, tile_x - 1), maxi(0, tile_y - 1))
				color = color.lightened(minf(slope * 0.055, 0.2)) if slope > 0 else color.darkened(minf(-slope * 0.055, 0.2))
			image.set_pixel(x, y, color)
	return image
