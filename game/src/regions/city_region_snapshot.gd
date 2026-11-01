class_name CityRegionSnapshot
extends RefCounted
## One disposable GPU still. No city activation, simulation tick or user settings.

var viewport: SubViewport
var presentation: MainMenuPresentation
var frames := 0
var coverage: Image


func begin(parent: Node, job: CityRegionPreviewJob, values: Dictionary, atmosphere: Dictionary) -> void:
	viewport = SubViewport.new()
	coverage = job.image
	viewport.disable_3d = true
	viewport.transparent_bg = true
	viewport.world_2d = World2D.new()
	viewport.size = job.image.get_size()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	parent.add_child(viewport)
	var holder := Control.new()
	holder.size = viewport.size
	viewport.add_child(holder)
	var options := values.duplicate(true)
	options.merge({"tree_growth_enabled": false, "life_cars_enabled": false, "life_people_enabled": false,
		"traffic_vehicles_enabled": false, "pause_freezes": true, "idle_saving_enabled": false}, true)
	if options.day_mode == 0:
		options.day_mode = 1
		options.day_hour = float(atmosphere.get("day_phase", 0.5)) * 24.0
	if options.weather_mode != 2 and atmosphere.get("weather") is Array and not atmosphere.weather.is_empty():
		options.weather_mode = 2
		options.weather_fixed = int(atmosphere.weather[0])
	var controller := GameSpeedController.new(SimulationEngine.new(job.city_snapshot))
	controller.speed = GameSpeedController.Speed.PAUSED
	presentation = MainMenuPresentation.new(holder, job.city_snapshot, controller, job.palette, job.sprites, options)
	presentation.app.visual_environment.precomputed_preview = true
	presentation.app.visual_environment.season_phase = float(atmosphere.get("season_phase", 1.0))
	presentation.map.show_behind_parent = false
	presentation.publish(job.image, ImageTexture.create_from_image(job.image), job.city_snapshot, [])
	var map := presentation.map
	map.base_palette_lookup_all = false
	map.city_source.size = job.extent
	map.city_source.seasons = ImageTexture.create_from_image(job.seasons)
	map.city_source.emission = ImageTexture.create_from_image(job.emission)
	if job.water != null:
		var tile := CityMapSource.TileEntry.new(Vector2.ZERO, Vector2(job.extent), null)
		tile.water = job.water
		map.city_source.tiles.append(tile)
	map.animated_palette_texture = ImageTexture.create_from_image(job.palette.animation_image(0))
	map.layers._tiled_source = null
	var zoom := minf(float(viewport.size.x) / job.extent.x, float(viewport.size.y) / job.extent.y)
	presentation.advance(0.0, Vector2.ZERO, zoom)


func poll() -> Image:
	# Two complete render frames include newly published masks and water.
	frames += 1
	if frames < 3:
		return null
	var image := viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	# Postprocessing can cover the viewport. Preserve only the original city
	# coverage, never its rectangular clear space, in neighboring areas.
	var pixels := image.get_data()
	var mask := coverage.get_data()
	for index in range(3, pixels.size(), 4):
		pixels[index] = mini(pixels[index], mask[index])
	image.set_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8, pixels)
	return image


func close() -> void:
	if presentation != null:
		presentation.close()
		presentation = null
	if is_instance_valid(viewport):
		viewport.queue_free()
	viewport = null
	coverage = null
