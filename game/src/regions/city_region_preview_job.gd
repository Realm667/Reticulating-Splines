class_name CityRegionPreviewJob
extends CityPreviewJob
## Bounded full-color still plus aligned masks for the normal visual renderer.

@warning_ignore_start("integer_division")

var seasons: Image
var emission: Image
var water: WaterReflectionRegion
var city_snapshot: CityState
var extent := Vector2i.ZERO


static func create(assets: LoadedAssetState) -> CityRegionPreviewJob:
	var copy := CityPreviewJob.for_assets(assets)
	var result := CityRegionPreviewJob.new()
	result.palette = copy.palette
	result.sprites = copy.sprites
	result.sprites.building_variants.assign(assets.large_sprites.building_variants)
	result.sprites.building_mix_seed = assets.large_sprites.building_mix_seed
	result.sprites.building_original_weight = assets.large_sprites.building_original_weight
	result.sprites.visual_emission_artwork.assign(assets.large_sprites.visual_emission_artwork)
	result.sprites.visual_season_artwork.assign(assets.large_sprites.visual_season_artwork)
	result.sprites.visual_tree_shadows_enabled = assets.large_sprites.visual_tree_shadows_enabled
	return result


func render(city: CityState) -> Image:
	var base := super.render(city)
	if base == null or cancelled():
		return null
	city_snapshot = city
	extent = CityIsometricRenderer.output_size_for_view(CityIsometricRenderer.VIEW_LARGE, city.map_size)
	var reduction := IsometricImageRender.reduction_to_fit(extent, CityPreviewStore.MAX_SIZE)
	var context := CityGpuBuildContext.new()
	if not context.prepare(city, Sc2Palette.index_encoding(), sprites, CityIsometricRenderer.VIEW_LARGE,
			CityViewMode.Mode.CITY, true, true, true, 0, false).is_empty():
		return null
	seasons = Image.create(base.get_width(), base.get_height(), false, Image.FORMAT_RGBA8)
	emission = Image.create(base.get_width(), base.get_height(), false, Image.FORMAT_RGBA8)
	var water_images := {}
	# Larger bounded strips avoid hundreds of repeated native water/mask calls.
	# Still bounded independently of map size (at most 1024 x 256 pixels).
	var band_height := reduction * maxi(1, 256 / reduction)
	var band_width := reduction * maxi(1, 1024 / reduction)
	var masks := [[CityNatureArtwork.atlas_masks(sprites), seasons, false], [CityBrightmaps.atlas_masks(sprites), emission, true]]
	for top in range(0, extent.y, band_height):
		for left in range(0, extent.x, band_width):
			if cancelled():
				return null
			var bounds := Rect2i(left, top, mini(band_width, extent.x - left), mini(band_height, extent.y - top))
			var target := Vector2i(ceili(float(bounds.size.x) / reduction), ceili(float(bounds.size.y) / reduction))
			var destination := Vector2i(left / reduction, top / reduction)
			for pair in masks:
				var part: Image = context.builder.auxiliary_raster(bounds, pair[0], pair[2])
				if part != null:
					part.resize(target.x, target.y, Image.INTERPOLATE_NEAREST)
					(pair[1] as Image).blit_rect(part, Rect2i(Vector2i.ZERO, target), destination)
			if not sprites.water_reflections:
				continue
			var region := context.build_water(bounds, 1, sprites, CityViewMode.Mode.CITY)
			if region == null:
				continue
			for key in ["surface", "reflected", "emission", "seasons", "seabed", "lights"]:
				var data: Image = region.get(key)
				if data == null:
					continue
				if not water_images.has(key):
					water_images[key] = Image.create(base.get_width() + 6, base.get_height() + 6, false, data.get_format())
				var part := data.get_region(Rect2i(Vector2i.ONE * WaterReflectionRegion.PADDING, bounds.size))
				# Heights and palette indices are data, never interpolated colors.
				part.resize(target.x, target.y, Image.INTERPOLATE_NEAREST)
				(water_images[key] as Image).blit_rect(part, Rect2i(Vector2i.ZERO, target), destination + Vector2i(3, 3))
	if not water_images.is_empty():
		water = WaterReflectionRegion.from_native(water_images, Rect2i(Vector2i.ZERO, base.get_size()), reduction)
	return base
