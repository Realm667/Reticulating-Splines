class_name MainMenuPresentation
extends RefCounted
## A detached presentation context. It never enters the scene tree, loads settings,
## activates a player document, advances simulation, or receives save/quit events.

var app := CityApplication.new()
var map: CityMapControl
var needs_render := false
var artwork_window: MainMenuCityBackground.ArtworkWindow
var render_view := CityIsometricRenderer.VIEW_LARGE


func _init(parent: Control, city: CityState, controller: GameSpeedController,
		palette: Sc2Palette, sprites: Sc2SpriteArchive, options: Dictionary, view_size := CityIsometricRenderer.VIEW_LARGE, elevation: CityTerrainElevation = null) -> void:
	render_view = view_size
	if elevation != null:
		app.visual_environment.terrain_elevation = elevation
	app.frame = MenuFrame.new(app)
	app.static_render = MenuStaticRender.new(app)
	app.static_render.view_size = view_size
	app.visual_environment.source_coordinate_scale = CityIsometricRenderer.view_configuration(view_size).divisor
	var rendering := MenuMapRender.new(app)
	rendering.refresh_requested.connect(func() -> void: needs_render = true)
	app.map_render = rendering
	app.asset_state.palette = palette
	app.asset_state.palette_index_encoding = Sc2Palette.index_encoding()
	var graphics := copy_graphics(sprites)
	if view_size == CityIsometricRenderer.VIEW_LARGE:
		app.asset_state.large_sprites = graphics
	else:
		app.asset_state.small_medium_sprites = graphics
	app.preferences.visual_enhancements = options.duplicate()
	app.visual_environment.reload_brightmaps(false)
	map = CityMapControl.new()
	map.name = "MenuCityView"
	map.show_behind_parent = true
	parent.add_child(map)
	map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map.set_process(false)
	map.set_process_input(false)
	map.set_process_unhandled_input(false)
	map.signs_visible = false
	app.map_view = map
	app.document_state.city = city
	app.simulation_state.speed_controller = controller
	app.simulation_state.simulation_engine = controller.engine
	# The background keeps its existing private simulation controller. Rendering
	# consumes it without changing its speed, document, random state or save path.
	graphics.visual_city_life_traffic = bool(options.life_cars_enabled)
	app.visual_environment.configure()


static func copy_graphics(source: Sc2SpriteArchive) -> Sc2SpriteArchive:
	var copy := Sc2SpriteArchive.new()
	copy.high_resolution.assign(source.high_resolution)
	copy.entries.assign(source.entries)
	copy.entries_by_id.assign(source.entries_by_id)
	copy.redraw_small_highway_ground = source.redraw_small_highway_ground
	copy.visual_emission.assign(source.visual_emission)
	copy.visual_seasons.assign(source.visual_seasons)
	copy.visual_nature.assign(source.visual_nature)
	copy.visual_nature_masks.assign(source.visual_nature_masks)
	copy.visual_nature_enabled = source.visual_nature_enabled
	copy.visual_terrain_enabled = source.visual_terrain_enabled
	copy.visual_revision = source.visual_revision
	CityNetworkModels.copy_state(source, copy)
	copy.water_reflections = source.water_reflections
	copy.water_indices = source.water_indices
	copy.visual_city_life_traffic = source.visual_city_life_traffic
	return copy


func set_options(options: Dictionary) -> void:
	if app.preferences.visual_enhancements == options:
		return
	app.preferences.visual_enhancements = options.duplicate()
	app.visual_environment.configure()


func reload_visual_assets() -> void:
	app.visual_environment.reload_brightmaps(false)
	app.visual_environment.profiles.reload(app.preferences.visual_enhancements.lut_folder)
	app.visual_environment._load_custom_lut(app.preferences.visual_enhancements.lut_path)
	needs_render = true


func publish(image: Image, texture: ImageTexture, city: CityState, commands: Array[CityStaticCommand]) -> void:
	app.render_caches.static_city_image = image
	app.render_caches.static_display_city = city
	app.render_caches.static_render_mode = CityViewMode.Mode.CITY
	app.static_render_state.epoch += 1
	app.moving_sprites.set_static_occlusion_commands(commands, render_view)
	var source := CityMapSource.new(image.get_size())
	source.texture = texture
	artwork_window = null
	map.set_city_view(city, source, null, true)


# Keep the indexed picture for masks and animation; HD replaces only the
# current camera window. It uses the same environmental shader and view transform.
func set_artwork_window(window: MainMenuCityBackground.ArtworkWindow) -> void:
	if window == artwork_window or map.city_source == null:
		return
	artwork_window = window
	var source := CityMapSource.new(map.city_source.size, map.city_source.texture)
	if window != null:
		source.tiles.append(CityMapSource.TileEntry.new(Vector2(window.bounds.position), Vector2(window.bounds.size),
			window.texture, CityDynamicSpriteCanvas.ARTWORK_TAG))
	map.city_source = source
	map.layers._sync_base_layer()


func animate(palette: ImageTexture) -> void:
	map.animated_palette_texture = palette
	map.layers._sync_base_material()
	app.moving_sprites.refresh_moving_things(render_view)


func advance(delta: float, offset: Vector2, zoom: float) -> void:
	map.zoom_factor = zoom / maxf(0.001, map.map_pixel_ratio)
	map.source_center = (map.size / 2.0 - offset) / zoom
	map.layers._sync_base_layer()
	map.advance_artwork_animation(delta)
	app.visual_environment.process(delta)
	app.city_life.process(delta)
	app.moving_sprites.process(delta)
	map.queue_redraw()


func close() -> void:
	app.visual_environment.weather.reset()
	map.free()
	app.free()


class MenuFrame extends ApplicationFrame:
	func _simulation_suspended(_include_camera_pan := true) -> bool:
		return app.simulation_state.speed_controller.interaction_blocked or app.simulation_state.speed_controller.terminal_blocked


class MenuStaticRender extends ApplicationStaticRender:
	var view_size := CityIsometricRenderer.VIEW_LARGE
	# Keep the published picture and its occlusion/masks until the worker replaces it.
	func invalidate_rendered_city() -> void:
		state.epoch += 1
		clear_dynamic_composition_cache()

	func city_view_size() -> int:
		return view_size


class MenuMapRender extends ApplicationMapRender:
	signal refresh_requested

	func refresh_map(_force := true) -> void:
		refresh_requested.emit()
