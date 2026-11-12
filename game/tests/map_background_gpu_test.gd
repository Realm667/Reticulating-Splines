extends "res://tests/support/scene_test_case.gd"
## Persisted backdrop selection and ambient-only transitions in the real canvas.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var path := "user://map-background-test-%d.cfg" % OS.get_process_id()
	assert(AppSettingsStore.load_values(path).map_background == "classic")
	var dialog := (load("res://src/ui/settings/app_settings_dialog.tscn") as PackedScene).instantiate() as AppSettingsDialog
	root.add_child(dialog)
	assert(dialog.map_background_selector.item_count == AppSettingsStore.MAP_BACKGROUNDS.size())
	for i in AppSettingsStore.MAP_BACKGROUNDS.size():
		dialog.map_background_selector.select(i)
		var style: String = AppSettingsStore.MAP_BACKGROUNDS[i]
		assert(dialog.selected_values().map_background == style)
		var options := AppSettingsStore.SaveOptions.new()
		options.map_background = style
		assert(AppSettingsStore.save_values(0.5, 0.5, false, path, options) == OK)
		assert(AppSettingsStore.save_values(0.5, 0.4, false, path) == OK)
		assert(AppSettingsStore.load_values(path).map_background == style)
	assert(AppSettingsStore.normalize_map_background("invalid") == "classic")
	dialog.free()
	DirAccess.remove_absolute(path)
	for hdr in [false, true]:
		await _check(hdr)
	print("PASS: backdrop persistence, ambient day/night blend, fixed/paused stability, artificial-light independence, cleared city, sharp overlays and bounded gradient cache in SDR/HDR")
	quit()


func _check(hdr: bool) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(512, 336)
	viewport.use_hdr_2d = hdr
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var background := CityMapBackground.new()
	background.size = Vector2(viewport.size)
	background.theme = AppUiTheme.current()
	viewport.add_child(background)
	var map := CityMapControl.new()
	viewport.add_child(map)
	map.hide()
	map.city = CityState.from_document(EmptyCityTemplate.create(128))
	background.map = map
	var overlay := ColorRect.new()
	overlay.color = Color(0.6, 0.5, 0.3)
	overlay.position = Vector2(40, 40)
	overlay.size = Vector2(30, 30)
	viewport.add_child(overlay)
	background.style = "day_night"
	var day := await _capture(viewport, map, 0.0)
	var night := await _capture(viewport, map, 1.0)
	var dusk := await _capture(viewport, map, 0.5)
	for point in [Vector2i(12, 12), Vector2i(120, 280), Vector2i(260, 165), Vector2i(500, 320)]:
		var a := day.get_pixelv(point)
		var b := night.get_pixelv(point)
		var middle := dusk.get_pixelv(point)
		assert(a.get_luminance() > b.get_luminance() + 0.04)
		assert(b.b > b.r and b.get_luminance() > 0.03, "Night must remain visible and blue")
		assert(middle.get_luminance() > b.get_luminance() and middle.get_luminance() < a.get_luminance())
	assert(day.get_pixel(50, 50) == night.get_pixel(50, 50), "UI/foreground must not be recolored")
	assert((await _capture(viewport, map, 0.5)).get_data() == dusk.get_data(), "Fixed or paused ambient state must be stable")
	map.layers.environment_parameters["environment_night"] = 1.0
	assert((await _capture(viewport, map, 0.0)).get_data() == day.get_data(), "Rain and daytime lights must not darken the background")
	for hour in [5.0, 6.5, 7.0, 12.0, 18.0, 19.0, 21.0]:
		var ambient: float = CityVisualEnvironment.light_at_hour(hour).night
		await _capture(viewport, map, ambient)
		assert(is_equal_approx(background._night, ambient), "Reuse the map's clock without another phase")
	assert(background._fills.size() == 2, "Time changes must not allocate new gradient textures")
	map.city = null
	assert((await _capture(viewport, map, 1.0)).get_data() == day.get_data(), "Cleared city must not retain night")
	for style: String in AppSettingsStore.MAP_BACKGROUNDS:
		if style == "day_night":
			continue
		background.style = style
		assert(not background.is_processing(), "Static backgrounds need no frame callback")
		var before := await _capture(viewport, map, 0.0)
		assert((await _capture(viewport, map, 1.0)).get_data() == before.get_data())
	viewport.free()


func _capture(viewport: SubViewport, map: CityMapControl, ambient: float) -> Image:
	map.layers.environment_parameters["environment_ambient_night"] = ambient
	for frame in 3:
		await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()
