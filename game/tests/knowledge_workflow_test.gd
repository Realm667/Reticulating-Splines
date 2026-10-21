extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 800)
	OS.set_environment("OPENSC2K_ASSET_SOURCE", "original")
	OS.set_environment("OPENSC2K_GRAPHICS_PACK", ProjectSettings.globalize_path("user://missing-test-art"))
	var path := "user://knowledge-%d.cfg" % OS.get_process_id()
	var app := (load("res://main.tscn") as PackedScene).instantiate() as CityApplication
	app.preferences.settings_path = path
	app.asset_state.reference_root = ProjectSettings.globalize_path("user://missing-test-originals")
	root.add_child(app)
	await process_frame
	app.set_process(false)
	app.main_menu.city_background.set_process(false)
	assert(app.city_session.activate_document(EmptyCityTemplate.create(128)))
	app.interface.hide_main_menu()
	app.frame.select_speed(GameSpeedController.Speed.PAUSED)
	app.tool_state.landscape_editor = false
	var knowledge := app.knowledge
	knowledge.set_process(false)
	knowledge.activated(true)
	assert(not knowledge.pending_start)
	var before: PackedByteArray = app.document_state.city.document.serialize().data
	knowledge._process(1)
	assert(knowledge.rules.elapsed == 0, "Pausing must not run down advice cooldowns")
	knowledge.card.show_entry("water")
	app.photo_mode.active = true
	knowledge._process(1)
	assert(not knowledge.card.visible)
	app.photo_mode.active = false
	knowledge._process(1)
	assert(knowledge.card.visible)
	knowledge._mute("water")
	assert(not knowledge.card.visible and knowledge.rules.muted.has("water"))
	var settings := ConfigFile.new()
	assert(settings.load(path + ".knowledge.cfg") == OK)
	assert(PackedStringArray(settings.get_value("tips", "muted")).has("water"))
	knowledge.card.show_entry("power")
	knowledge.suspended_card = true
	knowledge._preferences(1, false)
	knowledge._process(1)
	assert(not knowledge.card.visible and not knowledge.suspended_card, "Start/loading-only must immediately dismiss in-game advice")
	knowledge._preferences(0, true)
	assert(knowledge.mode == 0 and knowledge.top)
	knowledge.rules.reset()
	knowledge.rules.condition("power", true, 90, 1)
	knowledge._process(1)
	assert(not knowledge.card.visible)
	knowledge._preferences(2, false)
	knowledge.activated(true)
	assert(knowledge.rules.history.is_empty() and knowledge.rules.candidates.is_empty())
	knowledge.observe_host({"revision": 1, "view_owner": "a", "disaster": 1})
	knowledge.observe_host({"revision": 2, "view_owner": "a", "disaster": 0})
	assert(knowledge.rules.candidates.has("recovery"))
	knowledge.observe_host({"revision": 3, "view_owner": "b", "disaster": 1, "visiting": true})
	knowledge.observe_host({"revision": 4, "view_owner": "b", "disaster": 0, "visiting": true})
	assert(knowledge.rules.candidates.is_empty(), "A visited city must not inherit the player's disaster")
	knowledge.observe_host({"revision": 2, "view_owner": "b", "disaster": 1})
	assert(knowledge.host_revision == 4, "Older host results must not replace a published state")
	knowledge.activated(true)
	var city := app.document_state.city
	city.set_zone_id(10, 10, 2)
	# Ordinary edits withdraw diagnoses without dismissing readable/pinned cards.
	knowledge.card.show_entry("power")
	knowledge.card.pin.set_pressed_no_signal(true)
	knowledge.rules.condition("power", true, 90, 1)
	knowledge.stamp = city.mirror_signature(PackedStringArray(["XBLD", "XZON", "XUND", "XBIT", "MISC"]))
	city.set_zone_id(11, 10, 2)
	knowledge.invalidate_edits()
	assert(knowledge.card.visible and knowledge.card.pin.button_pressed)
	assert(not knowledge.card.context_valid and not knowledge.card.action_button.visible)
	assert(knowledge.rules.candidates.is_empty())
	knowledge.card.pin.set_pressed_no_signal(false)
	knowledge.card._process(1)
	assert(knowledge.card.visible, "An edit must retain the minimum reading time")
	app.map_view.city = city
	app.map_view.city_source = CityMapSource.new(CityIsometricRenderer.output_size_for_view(2, 128))
	knowledge.event_point = Vector2i(64, 64)
	knowledge.event_compass = city.compass_rotation()
	assert(knowledge._event_target() == Vector2i(64, 64))
	knowledge._action("event")
	assert(app.map_view.center_tile().distance_to(Vector2i(64, 64)) <= 1)
	knowledge.activated(true)
	assert(knowledge._event_target().x < 0, "City activation must clear old event locations")
	knowledge.window.open([], "power")
	assert(not knowledge.window.card.action_button.visible and not knowledge.window.card.close_button.visible)
	knowledge.window.hide()
	var inputs := KnowledgeRules.growth(city, Vector2i(10, 10))
	before = city.document.serialize().data
	for theme_id in AppUiTheme.IDS:
		AppUiTheme.select(theme_id)
		knowledge.card.show_entry("water")
		await process_frame
		await process_frame
		knowledge._layout()
		assert(root.get_visible_rect().encloses(knowledge.card.get_global_rect()), "Card must fit the viewport")
		app.city_menu_bar.help_menu_requested.emit(CityMenuBar.MENU_KNOWLEDGE)
		assert(knowledge.window.visible)
		knowledge.window.search.text = "zzzzzz-no-topic"
		knowledge.window.refresh()
		assert(knowledge.window.items.item_count == 0)
		assert(not knowledge.window.card.visible)
		knowledge.window.search.clear()
		knowledge.window.refresh()
		assert(knowledge.window.items.item_count == KnowledgeCatalog.ENTRIES.size())
		knowledge.window.hide()
		knowledge.growth_dialog.open(inputs)
		await process_frame
		assert(knowledge.growth_dialog.checks.get_child_count() == 5)
		knowledge.growth_dialog.hide()
	root.size = Vector2i(1920, 1080)
	AppUiTheme.select("classic_windows")
	app.preferences.ui_scale = 2.0
	app.settings.apply_ui_scale()
	await process_frame
	await process_frame
	app.query_choices.open_query(Vector2i(10, 10))
	await process_frame
	await process_frame
	assert(app.city_dialogs.query_dialog.growth_button.is_visible_in_tree())
	assert(root.get_visible_rect().encloses(app.city_dialogs.query_dialog.growth_button.get_global_rect()),
		"The growth-help link must stay reachable at 1080p / classic 2x")
	app.city_dialogs.query_dialog.growth_requested.emit()
	assert(knowledge.growth_dialog.visible and not app.city_dialogs.query_dialog.visible)
	knowledge.growth_dialog.hide()
	for language in AppLocalization.codes():
		AppLocalization.select(language)
		knowledge.window.open([], "water")
		await process_frame
		await process_frame
		var bounds := Rect2i(Vector2i.ZERO, Vector2i(root.get_visible_rect().size))
		assert(bounds.encloses(Rect2i(knowledge.window.position, knowledge.window.size)))
		knowledge.window.hide()
		knowledge.growth_dialog.open(inputs)
		await process_frame
		await process_frame
		assert(bounds.encloses(Rect2i(knowledge.growth_dialog.position, knowledge.growth_dialog.size)))
		assert(knowledge.growth_dialog.size.y <= 440, "The diagnosis must stay compact")
		knowledge.growth_dialog.hide()
	assert(city.document.serialize().data == before, "All knowledge actions must leave city data unchanged")
	var rows := VBoxContainer.new()
	root.add_child(rows)
	knowledge.loading(rows)
	assert(knowledge.loading_card.visible)
	for entry: Array in KnowledgeCatalog.ENTRIES:
		knowledge.rules.muted.append(entry[0])
	knowledge._show_loading_tip()
	assert(not knowledge.loading_card.visible, "Muting every topic must finish without looping")
	rows.free()
	app.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".knowledge.cfg"))
	AppUiTheme.select("dark")
	AppLocalization.select("en")
	await process_frame
	print("PASS knowledge workflow: lifecycle, photo, pause, preferences, host identity, themes, search, loading, unchanged city")
	quit()
