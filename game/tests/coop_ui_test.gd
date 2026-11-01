extends SceneTree

const AppFixture = preload("res://tests/support/app_fixture.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)


func run() -> void:
	root.gui_embed_subwindows = true
	var main: CityApplication = load("res://main.tscn").instantiate()
	AppFixture.configure(main)
	root.add_child(main)
	await process_frame
	await process_frame
	check(main.asset_state.assets_ready, "assets loaded")
	check(main.coop.menu_button.disabled, "Multiplayer menu is disabled outside a session")
	var view := Rect2(100, 50, 500, 300)
	check(ApplicationMultiplayer.remote_gain(Vector2(200, 100), view) == 1.0, "visible remote sound has full gain")
	check(ApplicationMultiplayer.remote_gain(Vector2(700, 100), view) > ApplicationMultiplayer.remote_gain(Vector2(1000, 100), view), "remote sound falls off smoothly outside view")
	check(ApplicationMultiplayer.remote_gain(Vector2(1700, 100), view) == 0.0, "distant remote sound is silent")
	var heard: Array = []
	main.coop.session.action_sounds.connect(func(events: Array[int]) -> void: heard.append(events))
	main.coop.session.play_result_sounds({"ok": true, "sounds": [500]}, 987654)
	main.coop.session.play_result_sounds({"ok": true, "sounds": [500]}, 987654)
	main.coop.session.play_result_sounds({"ok": false, "sounds": [500]}, 987655)
	check(heard.size() == 1, "own confirmed action plays exactly once, rejected action never")
	check(main.main_menu.visible, "normal startup menu")
	main.main_menu.get_node("Center/Panel/Content/Multiplayer").pressed.emit()
	await process_frame
	check(main.coop.panel.visible, "Multiplayer button opens lobby")
	main.coop.port.min_value = 0
	main.coop.port.value = 0
	main.coop.start_host()
	await process_frame
	check(main.city_dialogs.new_city_dialog.visible, "host opens complete new-city dialog")
	main.new_city.cancel_new_city()
	main.coop.host_document(Sc2xDocument.create_empty(128, "UI test").document)
	await process_frame
	check(main.coop.active() and main.coop.mirrored, "host activates a playable city")
	check(not main.coop.menu_button.disabled, "Multiplayer menu enables for an active session")
	check(not main.main_menu.visible and not main.coop.panel.visible, "city gets input ownership")
	check(main.document_state.city != main.coop.session.world.city, "host display is isolated from authoritative model")
	check(main.simulation_state.frame_simulation == null, "display has no independent simulation worker")
	check(main.coop.session.waiting_for_start, "UI host waits in pre-game lobby")
	# Running-game UI regressions; the two-peer lobby transition has its own test.
	main.coop.session.waiting_for_start = false
	main.coop.session.publish()
	await process_frame
	var display_document := main.document_state.current_document
	main.visual_environment.process(0.0)
	main.visual_environment.weather.clock = 123.0
	# Exercise the region cache even on a headless runner; the GPU run uses its GPU backend.
	main.static_render.invalidate_rendered_city()
	main.map_render.refresh_region_map(true)
	main.tool_state.selected_group = 9
	main.tool_state.selected_subtool = 0
	main.city_edits.apply_map_selection(Vector2i(20, 20), Vector2i(20, 20), [Vector2i(20, 20)], false)
	check(main.coop.session.world.revision == 1, "ordinary map selection reaches host")
	for frame in 60:
		if main.coop.session.local_revision == main.coop.session.world.revision:
			break
		await process_frame
	check(main.document_state.city.funds() == main.coop.session.world.city.funds(), "host display updates funds")
	check(main.document_state.current_document == display_document, "snapshot retains display document identity")
	check(main.document_state.city.chunk_revision("XZON") > 0, "received zone increments render revision")
	check(main.render_caches.region_cache.display_city.zones == main.document_state.city.zones, "zone immediately reaches rendered snapshot without a building")
	main.visual_environment.process(0.0)
	check(main.visual_environment.weather.clock == 123.0, "city snapshot does not reset weather clock")
	var guest := CoopSession.new()
	root.add_child(guest)
	guest.join("127.0.0.1", main.coop.session.server.get_local_port(), main.coop.join_code.text, "Guest")
	for _frame in 100:
		await create_timer(0.01).timeout
		if guest.connected:
			break
	check(guest.connected, "second player joins the UI-hosted city")
	var remote_sounds: Array = []
	main.coop.session.remote_action_sound.connect(func(event: Dictionary) -> void: remote_sounds.append(event))
	guest.request({"kind": "build", "group": 9, "tool": 0, "start": [25, 25], "finish": [25, 25], "path": [[25, 25]]})
	for _frame in 100:
		await create_timer(0.01).timeout
		if main.coop.session.world.revision == 2 and main.coop.session.local_revision == 2 and guest.local_revision == 2:
			break
	check(main.coop.session.world.revision == 2, "guest builds while host has its own camera")
	check(remote_sounds.size() == 1 and not remote_sounds[0].sounds.is_empty(), "guest construction emits positioned sound on host")
	check(main.document_state.city.zones == main.coop.session.world.city.zones, "guest edit reaches host view")
	check(main.render_caches.region_cache.display_city.zones == main.document_state.city.zones, "guest zone reaches renderer")
	await rendering_cases(main)
	await weather_cases(main, guest)
	main.reports.on_windows_menu(0)
	check(main.city_dialogs.budget_dialog.visible, "budget opens normal city dialog")
	var budget_dialog := main.city_dialogs.budget_dialog
	budget_dialog.tabs.current_tab = 3
	budget_dialog.controls[0].value = 13
	for ordinance in [0, 1]:
		budget_dialog.ordinance_control.ordinance_checks[ordinance].button_pressed = true
		check(budget_dialog.visible and budget_dialog.tabs.current_tab == 3, "ordinance confirmation keeps budget and selected tab open")
		check(budget_dialog.controls[0].value == 13, "confirmed ordinances preserve draft funding")
	main.coop.session.world.newspaper_sequence += 1
	main.coop.session.publish()
	check(main.city_dialogs.newspaper_dialog.visible, "host-confirmed newspaper event reaches the player's UI")
	main.city_dialogs.newspaper_dialog.hide()
	main.coop.session.publish()
	check(not main.city_dialogs.newspaper_dialog.visible, "same newspaper event is not shown twice")
	main.camera_input.center_map_on_tile(Vector2i(26, 26))
	await process_frame
	main.coop.session.request({"kind":"build", "group":CityToolIds.Group.WATER, "tool":CityToolIds.Water.PUMP, "start":[26,26], "finish":[26,26], "path":[], "dragged":false})
	main.coop.session.publish()
	check(main.document_state.city.building_id(26,26) > 13, "demolition fixture built through authority")
	var enhanced: bool = main.preferences.visual_enhancements.disaster_enabled
	main.preferences.visual_enhancements.disaster_enabled = false
	main.coop.bulldoze(Vector2i(26,26))
	main.coop.session.publish()
	check(main.document_state.city.building_id(26,26) <= 13 and main.map_view.presentation.transient_effect_count() > 0, "confirmed demolition produces visible local dust")
	main.preferences.visual_enhancements.disaster_enabled = enhanced
	var funding := BudgetPhase.funding_values(main.document_state.city)
	funding[0] = 11
	main.city_dialogs.budget_dialog.open_budget(funding, false, true)
	main.budget.commit_budget()
	main.city_dialogs.budget_dialog.hide()
	check(BudgetPhase.funding_values(main.coop.session.world.city)[0] == 11, "shared budget UI applies tax")
	main.coop.save_to("user://coop-ui.sc2x")
	check(FileAccess.file_exists("user://coop-ui.sc2x"), "UI saves normal city with session")
	main.autosave.directory = OS.get_user_data_dir().path_join("multiplayer-autosave")
	check(main.autosave.save_now(), "host starts complete multiplayer autosave")
	main.autosave.close()
	var automatic := Sc2File.load_path(main.autosave.last_path)
	check(automatic.is_valid() and automatic.sc2x_extra_entries.has("multiplayer.json"), "autosave includes session identities")
	main.menus.on_options_menu(ApplicationMenus.MENU_SOUND_EFFECTS)
	var local_sound := main.document_state.city.sound_enabled()
	main.coop.session.publish()
	check(main.document_state.city.sound_enabled() == local_sound, "local audio choice survives server snapshot")
	if DisplayServer.get_name() != "headless":
		main.coop.open()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://coop-menu.png")
	main.coop.windows.open_chat()
	main.coop.windows.chat_input.text_submitted.emit("Hello from the host")
	check(main.coop.windows.chat_log.get_parsed_text().contains("Hello from the host"), "chat window displays message")
	main.coop.windows.chat.hide()
	check(main.coop.menu_button.get_index() == main.city_menu_bar.newspaper_menu.get_index() + 1, "multiplayer menu follows Newspaper")
	guest.stop()
	guest.queue_free()
	main.coop.leave()
	check(main.coop.menu_button.disabled, "Multiplayer menu disables after leaving")
	await process_frame
	check(not main.city_menu_bar.debug_menu.disabled and not main.city_menu_bar.windows_menu.get_popup().is_item_disabled(0), "leaving multiplayer restores local administrative menus")
	check(not main.coop.active() and main.main_menu.visible, "leave returns to singleplayer menu")
	check(not main.visual_preparation.busy and main.visual_preparation.banks.is_empty(), "leave releases pending visual banks before clearing the city")
	main.coop.mode_picker.select(1)
	main.coop.port.value = 0
	main.coop.host_document(Sc2xDocument.create_empty(128, "Land UI").document)
	main.coop.session.request({"kind": "rename_city", "name": "Renamed lobby city"})
	check(main.city_menu_bar.city_label.text == "Renamed lobby city", "lobby rename updates persistent city header")
	main.coop.session.waiting_for_start = false
	main.coop.session.publish()
	main.coop.windows.select_land("land_buy")
	check(main.city_toolbar.land_mode and main.coop.windows.land_button.button_pressed, "dedicated land mode")
	check(not main.city_toolbar.toolbar_buttons[9].button_pressed and not main.city_toolbar.hold_menu.visible, "land buying never activates Residential or leaves its flyout open")
	check(main.map_view.selection_mode == "rectangle", "land mode enables rectangle input")
	main.coop.windows.land_offer_price = 20
	main.coop.apply_selection(Vector2i(4, 4), Vector2i(5, 5), [], true)
	check(main.coop.session.world.owners[4 * 128 + 4] == 1, "land input reaches authoritative purchase")
	main.coop.windows.open_scoreboard()
	check(main.coop.windows.scores.table.columns == 5, "Shared overview fits without horizontal scrolling")
	main.coop.session.goal.kind = "wealth"
	main.coop.session.goal.target = 50000
	main.coop.session.publish()
	await process_frame
	main.coop.windows.tick()
	await process_frame
	var hud := main.coop.windows.goal_hud
	var visible_map := Rect2(main.map_view.global_position + main.map_view.camera_view_rect.position, main.map_view.camera_view_rect.size)
	check(visible_map.encloses(hud.panel.get_global_rect()), "victory HUD fits inside the visible map below menu bar")
	check(hud.panel.visible and hud.rows.get_child_count() > 0 and hud.rows.get_child(0).get_child(0).get_child(0).value == 40, "live wealth progress displayed")
	check(hud.rows.get_child(0).size.y > 0, "goal values and holding duration remain visible")
	check(hud.title.size.x > 0 and hud.title.size.y >= hud.title.get_line_height() and not hud.title.text.is_empty(), "goal heading has readable layout bounds")
	hud.panel.custom_minimum_size.x = 400
	main.coop.windows.tick()
	check(visible_map.encloses(hud.panel.get_global_rect()), "goal HUD remains within map with larger theme minimum")
	hud.panel.custom_minimum_size.x = 0
	var annual := main.coop.session.latest.duplicate(true)
	annual.pending = "annual_budget"
	annual.blocked = true
	annual.policy = int(annual.policy) + 1
	main.coop.windows.update_state(annual)
	await process_frame
	check(main.city_dialogs.budget_dialog.visible and main.simulation_state.annual_budget_pending, "pending annual budget opens visibly instead of silently stopping growth")
	main.city_dialogs.budget_dialog.hide()
	main.coop.windows.update_state(main.coop.session.latest)
	main.coop.windows.scoreboard.hide()
	main.coop.request_exit("quit")
	check(not main.coop.windows.scoreboard.visible, "OS quit never opens scoreboard")
	for child in main.get_children():
		if child is ConfirmationDialog and child.title == main.coop.tr("Quit multiplayer"):
			child.canceled.emit()
	check(main.coop.active() and main.coop.exit_action.is_empty(), "cancel quit preserves connected session")
	main.coop.windows.open_chat()
	main.coop.windows.tick()
	check(main.coop.windows.chat.position.x >= main.map_view.camera_view_rect.position.x, "chat clear of sidebar")
	var entry := {"id": "test-message", "name": "Guest", "sender": "other", "text": "unique chat"}
	main.coop.windows.receive_chat(entry)
	main.coop.windows.receive_chat(entry)
	check(main.coop.windows.chat_log.get_parsed_text().count("unique chat") == 1, "chat de-duplicates deliveries")
	main.coop.session.request({"kind": "land_offer", "start": [4, 4], "finish": [4, 4], "price": 20})
	main.coop.windows.open_offers()
	await process_frame
	var parcel: Dictionary = main.coop.session.latest.offers[0]
	main.coop.windows.market.review(parcel)
	await process_frame
	check(main.coop.windows.market.map_detail.visible and main.coop.windows.map_overlay.highlight == parcel.tiles, "trade decisions open directly on the exact real-time parcel")
	main.coop.windows.market.show_on_map(parcel)
	check(main.coop.windows.map_overlay.highlight == parcel.tiles, "map highlights the exact trade parcel")
	main.coop.windows.market.close_map()
	main.current_tool.select_tool_group(9)
	check(not main.city_toolbar.land_mode and not main.coop.windows.land_button.button_pressed, "normal tool exits land mode")
	main.coop.leave()
	await process_frame
	await readonly_city(main)
	await readonly_city(main, true)
	await client_rights_and_end(main)
	main.queue_free()
	await process_frame
	print("Koop UI checks: %d failures" % failures)
	quit(1 if failures else 0)


func rendering_cases(main: CityApplication) -> void:
	for renderer in ["region", "whole"]:
		if renderer == "whole":
			main.preferences.city_renderer = "cpu"
			main.static_render.invalidate_rendered_city()
			main.map_render.refresh_map()
		var target := Vector2i(30, 30) if renderer == "region" else Vector2i(35, 35)
		main.tool_state.selected_group = CityToolIds.Group.ROADS
		main.tool_state.selected_subtool = 0
		main.city_edits.apply_map_selection(target, target, [target], false)
		for _frame in 100:
			await process_frame
			if main.render_caches.static_display_city.building_id(target.x, target.y) != 0:
				break
		check(main.render_caches.static_display_city.building_id(target.x, target.y) != 0, renderer + " shows road without another edit")
		var road := main.document_state.city.building_id(target.x, target.y)
		main.coop.bulldoze(target)
		var cleared := main.coop.session.world.city.building_id(target.x, target.y)
		check(cleared != road, renderer + " road demolition accepted")
		for _frame in 100:
			await process_frame
			if main.render_caches.static_display_city.building_id(target.x, target.y) == cleared:
				break
		check(main.render_caches.static_display_city.building_id(target.x, target.y) == cleared, renderer + " shows demolition rubble without another edit")


func weather_cases(main: CityApplication, guest: CoopSession) -> void:
	var received: Array[Dictionary] = []
	guest.environment_received.connect(func(value: Dictionary) -> void: received.append(value))
	var weather := main.visual_environment.weather
	main.preferences.visual_enhancements.weather_enabled = true
	main.preferences.visual_enhancements.weather_mode = 2
	main.preferences.visual_enhancements.weather_fixed = CityVisualWeather.Kind.HEAVY_SNOW
	main.visual_environment.process(1.0)
	for _frame in 60:
		await create_timer(0.01).timeout
		if not received.is_empty():
			break
	check(not received.is_empty(), "weather packets arrive independently of city changes")
	if received.is_empty():
		return
	var state: Dictionary = received.back()
	check(int(state.kind) == CityVisualWeather.Kind.HEAVY_SNOW, "guest receives host weather choice")
	check(not state.has("weather") and not state.has("clouds"), "network excludes animated particles, cloud positions and audio cues")
	var remote := CityVisualWeather.new(main)
	remote.remote_kind = int(state.kind)
	main.preferences.visual_enhancements.weather_fixed = CityVisualWeather.Kind.SUNNY
	remote.process(0.1, 10.0, true, 1.0)
	check(remote.kind == CityVisualWeather.Kind.HEAVY_SNOW and remote.snow > 0.0, "host atmosphere overrides local choice and season")
	var before := remote.clock
	remote.process(0.1, 0.1, true, 1.0)
	check(is_equal_approx(remote.clock, before + 0.1), "local animation advances without network packets")
	remote.process(0.1, 0.1, true, 1.0, true)
	check(is_equal_approx(remote.clock, before + 0.1), "host pause freezes local weather clocks")
	await cloud_front_cases(main)
	remote.reset()
	if remote.layer != null:
		remote.layer.queue_free()
	check(weather.clock >= 123.0, "weather keeps advancing across edits")


func cloud_front_cases(main: CityApplication) -> void:
	var environment := main.visual_environment
	var speed := main.simulation_state.speed_controller.speed
	main.simulation_state.speed_controller.speed = GameSpeedController.Speed.TURTLE
	main.map_view.interaction.panning = true
	check(not main.frame._simulation_suspended(), "camera drag never suspends multiplayer simulation")
	check(environment.network_snapshot().weather[20] == 0, "camera drag must not broadcast a weather pause")
	main.simulation_state.speed_controller.speed = GameSpeedController.Speed.PAUSED
	check(environment.network_snapshot().weather[20] == 1, "real pause is still sent during camera drag")
	main.map_view.interaction.panning = false
	main.simulation_state.speed_controller.speed = speed
	var options := main.preferences.visual_enhancements
	options.cloud_enabled = true
	options.cloud_mode = CityCloudSituations.Type.CIRRUS + 1
	options.weather_fixed = CityVisualWeather.Kind.DRY_STORM
	options.weather_strength = 0.6
	environment.process(1.0)
	var clouds := environment.clouds
	clouds.situations.current = CityCloudSituations.Type.STRATUS
	clouds.situations.target = CityCloudSituations.Type.FOG
	clouds.situations.blend = 0.4
	clouds.situations.hold_clock = 730.0
	clouds.situations.duration = 90.0
	clouds.fog = 0.15
	clouds.fog_overlay.drift = Vector2(23, 41)
	clouds.storminess = 0.7
	clouds.precipitation_readiness = 0.25
	var state := environment.network_snapshot()
	environment.receive_network_weather(state)
	check(environment.remote_weather == state, "complete host atmosphere passes packet validation")
	var invalid := state.duplicate(true)
	invalid.clouds[5] = 99
	environment.receive_network_weather(invalid)
	check(environment.remote_weather == state, "invalid cloud type cannot enter the renderer")
	invalid = state.duplicate(true)
	invalid.weather[20] = 2
	environment.receive_network_weather(invalid)
	check(environment.remote_weather == state, "invalid pause flag rejected")
	invalid = state.duplicate(true)
	invalid.clouds[7] = NAN
	environment.receive_network_weather(invalid)
	check(environment.remote_weather == state, "nonfinite cloud transition rejected")
	environment.remote_weather.clear()
	var remote_clouds := CityVisualClouds.new(main)
	remote_clouds.remote_state = state.clouds
	remote_clouds.process(0.1, 0.1, true, Color.WHITE, 0.0, CityVisualWeather.Kind.DRY_STORM)
	check(remote_clouds.situations.current == CityCloudSituations.Type.STRATUS and remote_clouds.situations.target == CityCloudSituations.Type.FOG, "host cloud types override guest fixed type")
	check(is_equal_approx(remote_clouds.situations.blend, 0.4), "late join receives cloud atlas transition")
	check(remote_clouds.field == CityCloudSituations.ATLASES[CityCloudSituations.Type.STRATUS], "guest uses host atlas")
	check(is_equal_approx(float(remote_clouds.parameters.cloud_type_blend), smoothstep(0.0, 1.0, 0.4)), "shader receives synchronized blend")
	check(is_equal_approx(remote_clouds.precipitation_readiness, 0.25), "host cloud cover controls guest precipitation")
	check(remote_clouds.fog_overlay.drift == Vector2(23, 41), "low mist receives host world phase")
	var remote := CityVisualWeather.new(main)
	remote.remote_state = state.weather
	remote.process(1.0, 1.0, true, 1.0)
	check(remote.kind == CityVisualWeather.Kind.DRY_STORM and remote.rain == 0.0 and remote.snow == 0.0, "synchronized dry storm has no residual precipitation")
	var audio := main.audio_controller
	var background := audio.background_audio
	audio.set_background_audio(true)
	var sound_enabled := main.document_state.city.sound_enabled()
	main.document_state.city.set_sound_enabled(true)
	remote.remote_state[20] = 0
	remote.process(1.0, 1.0, true, 1.0)
	check(remote.audio.wind_gain > 0.0 and remote.audio.rain_gains == Vector2.ZERO, "guest dry storm uses wind without rain audio")
	var wind_gain := remote.audio.wind_gain
	remote.process(1.0, 1.0, true, 1.0, true)
	check(remote.audio.wind_gain == wind_gain and is_instance_valid(remote.audio.wind_player) and remote.audio.wind_player.stream_paused, "guest pause freezes existing wind ambience")
	remote.process(0.1, 0.1, false, 1.0)
	check(remote.rain == 0.0 and remote.snow == 0.0 and remote.tint == Color.WHITE, "guest can disable local weather effects")
	remote.reset()
	if remote.layer != null:
		remote.layer.queue_free()
	audio.set_background_audio(background)
	main.document_state.city.set_sound_enabled(sound_enabled)
	for layer in [remote_clouds.layer, remote_clouds.fog_overlay.layer, remote_clouds.fog_overlay.height_viewport]:
		if layer != null:
			layer.queue_free()

func readonly_city(main: CityApplication, expansion := false) -> void:
	main.coop.mode_picker.select(2)
	main.coop.launch.region_expansion.button_pressed = expansion
	main.coop.port.value = 0
	main.coop.host_document(Sc2xDocument.create_empty(32, "Own city").document)
	var guest := CoopSession.new()
	root.add_child(guest)
	guest.join("127.0.0.1", main.coop.session.server.get_local_port(), main.coop.join_code.text, "Other mayor")
	for frame in 200:
		await create_timer(0.01).timeout
		if guest.connected:
			break
	check(guest.connected, "Region UI peer connected")
	if not guest.connected:
		guest.queue_free()
		main.coop.leave()
		return
	if expansion:
		var deadline := Time.get_ticks_msec() + 5000
		while int(guest.latest.get("lobby", {}).get("generation", -1)) != main.coop.session.lobby_generation and Time.get_ticks_msec() < deadline:
			await create_timer(0.01).timeout
		main.coop.session.request({"kind": "lobby_ready", "ready": true})
		guest.request({"kind": "lobby_ready", "ready": true})
		while not main.coop.session.can_start_lobby() and Time.get_ticks_msec() < deadline:
			await create_timer(0.01).timeout
		main.coop.session.request({"kind": "lobby_start"})
		check(main.coop.session.world.campaign != null, "real lobby creates expanded region before UI review")
	var other: CoopWorld = main.coop.session.world.municipalities[guest.token]
	other.city.document.set_city_name("Visited city")
	other.city.set_funds(12345)
	other.revision += 1
	main.coop.session.world.revision += 1
	main.coop.session.waiting_for_start = false
	main.coop.session.publish()
	main.reports.on_windows_menu(0)
	main.reports.on_windows_menu(5)
	var regions := main.regions
	check(regions.window.visible and not main.city_dialogs.simnation_window.visible, "Neighbors opens the common overview")
	regions._sync_navigation()
	check(regions.mini.visible and regions.mini_grid.state.cells.size() == 2, "Competitive Region uses sidebar grid even without expansion")
	var rival_cell := Vector2i(-1, -1)
	for entry: Dictionary in regions.summary().cells:
		if entry.owner == guest.token.sha256_text():
			rival_cell = Vector2i(entry.cell[0], entry.cell[1])
	check(rival_cell.x >= 0, "rival is present in shared region map")
	regions._select(rival_cell)
	check(not regions.open_button.disabled and regions.buy_button.visible == expansion, "rival can be visited; land purchasing is available only in expanded regions")
	regions.open_button.pressed.emit()
	await process_frame
	main.coop.windows.tick()
	check(main.document_state.city.city_name() == "Visited city" and main.document_state.city.funds() == 12345, "visited city data drives local reports")
	check(not main.city_dialogs.budget_dialog.visible, "own budget closes on visit")
	main.reports.on_windows_menu(0)
	check(not main.city_dialogs.budget_dialog.visible and main.city_menu_bar.debug_menu.disabled, "visitor administrative UI is disabled")
	check(main.coop.windows.goal_hud.home.visible and main.coop.windows.goal_hud.visit_frame.visible, "visit frame and return button shown even without a goal")
	main.coop.windows.competition.open_regions()
	check(regions.return_button.visible and regions.neighbor_details.text.contains("Visited city"), "overview follows visited city and exposes return action")
	check(regions.grid.state.active == [rival_cell.x, rival_cell.y], "viewed region is highlighted")
	regions.window.hide()
	other.city.document.sc2x_metadata.extensions["multiplayer_military"] = 2
	other.revision += 1
	main.coop.session.world.revision += 1
	main.coop.session.publish()
	await process_frame
	check(not main.city_dialogs.military_dialog.visible and main.coop.windows.state.pending == "", "owner decision is never mirrored to spectators")
	main.coop.session.request({"kind": "debug", "action": "add_funds", "value": 1000})
	check(other.city.funds() == 12345, "even host visit is read-only")
	regions.return_button.pressed.emit()
	check(not main.coop.session.latest.get("visiting", false), "overview returns to own authoritative city")
	main.reports.on_windows_menu(0)
	main.coop.session.request({"kind": "speed", "speed": 5})
	var day := main.coop.session.world.city.age_in_days()
	for frame in 8:
		main.coop.session.world.advance(0.1)
	check(main.coop.session.world.city.age_in_days() > day and not main.frame._simulation_suspended(), "open budget never suspends multiplayer")
	guest.stop()
	guest.queue_free()
	main.coop.leave()
	await process_frame
	check(not main.city_menu_bar.debug_menu.disabled and not main.city_menu_bar.windows_menu.get_popup().is_item_disabled(0), "leaving multiplayer restores local administrative menus")


func client_rights_and_end(main: CityApplication) -> void:
	var host := CoopSession.new()
	root.add_child(host)
	host.host(Sc2xDocument.create_empty(32, "End notice").document, 0, "", "Host", "coop", false)
	main.coop.session.join("127.0.0.1", host.server.get_local_port(), "", "Client")
	var deadline := Time.get_ticks_msec() + 5000
	while not main.coop.mirrored and Time.get_ticks_msec() < deadline:
		await create_timer(0.01).timeout
	check(main.coop.mirrored, "client UI connected")
	if main.coop.mirrored:
		main.coop.windows.tick()
		var popup := main.city_menu_bar.windows_menu.get_popup()
		check(popup.is_item_disabled(popup.get_item_index(7)), "Windows Debug item is disabled for client in own city")
		main.reports.on_windows_menu(7)
		main.debug_overlay.toggle()
		check(not main.debug_overlay.is_open and not main.debug_overlay._window.visible, "client cannot open debug by menu or alternate path")
		host.stop()
		deadline = Time.get_ticks_msec() + 5000
		while not is_instance_valid(main.coop.ended_dialog) and Time.get_ticks_msec() < deadline:
			await create_timer(0.01).timeout
		check(is_instance_valid(main.coop.ended_dialog) and main.coop.ended_dialog.visible and main.document_state.current_document != null, "visible host-end notice retains city for save or retry")
		if is_instance_valid(main.coop.ended_dialog):
			main.coop.ended_dialog.queue_free()
			main.coop.ended_dialog = null
	main.coop.leave()
	host.stop()
	host.queue_free()
	await process_frame
