extends SceneTree
## Retained surface banks must survive water/underground view transitions.

const DocumentState = preload("res://tests/support/document_state.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	OS.set_environment("OPENSC2K_CITY_RENDERER", "gpu")
	OS.set_environment("OPENSC2K_GRAPHICS_PACK", ProjectSettings.globalize_path("res://../ext/graphics"))
	OS.set_environment("OPENSC2K_DATA_PACK", ProjectSettings.globalize_path("res://../ext/data"))
	OS.set_environment("OPENSC2K_ASSET_SOURCE", "folder")
	var main := (load("res://main.tscn") as PackedScene).instantiate() as CityApplication
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.main_menu.city_background.set_process(false)
	for edge in [128, 512]:
		var document := EmptyCityTemplate.create(edge)
		var fixture := CityState.from_document(document)
		fixture.set_building_id(20, 20, 112)
		assert(main.city_session.activate_document(document))
		main.frame.select_speed(GameSpeedController.Speed.PAUSED)
		var before := DocumentState.capture(document)
		var prepare := main.visual_preparation
		prepare.begin()
		var surface := main.render_caches.region_cache
		var signature := surface.signature.duplicate()
		assert(prepare.owns(surface))
		for repeat in 3:
			main.menus.select_view(CityViewMode.Mode.UNDERGROUND)
			var underground := main.render_caches.region_cache
			assert(not prepare.owns(underground), "Underground view reconfigured a retained surface bank")
			assert(surface.signature == signature, "Water view invalidated prepared buildings")
			prepare.refresh()
			assert(main.render_caches.region_cache == underground, "Surface preparation replaced the visible underground cache")
			main.menus.set_underground_pipes_visible(repeat % 2 == 0)
			main.menus.select_view(CityViewMode.Mode.CITY)
			assert(main.render_caches.region_cache == surface, "Return to city did not restore the surface bank")
			assert(surface.display_city.building_id(20, 20) == 112, "Surface building missing after water view")
			assert(DocumentState.capture(document) == before, "View transition edited the city")
		prepare.reset()
	main.queue_free()
	await process_frame
	print("PASS: water/underground transitions preserve surface banks and buildings on 128/512 maps")
	quit()
