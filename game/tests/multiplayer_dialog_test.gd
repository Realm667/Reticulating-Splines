extends SceneTree

const AppFixture = preload("res://tests/support/app_fixture.gd")
var failures := 0
var app: CityApplication

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func settle() -> void:
	for frame in 12:
		await process_frame

func check_fit(window: Window, body: Control, description: String) -> void:
	var available := app.get_viewport().get_visible_rect().size
	check(window.size.y <= available.y - 68, description + " stays inside screen")
	var content_bottom := body.position.y + body.get_combined_minimum_size().y
	var scroll := body.get_parent() as ScrollContainer
	if window.size.y < available.y - 72:
		check(content_bottom <= scroll.size.y + 1, description + " does not clip the bottom action")
		# Short translations can reach the window's deliberate minimum height.
		if window.size.y > window.min_size.y + 2:
			check(scroll.size.y - content_bottom < 20, description + " has no empty lower area: %s / minimum %s / content %s" % [window.size, window.min_size, content_bottom])

func run() -> void:
	root.gui_embed_subwindows = true
	root.size = Vector2i(1440, 1000)
	app = load("res://main.tscn").instantiate()
	AppFixture.configure(app)
	root.add_child(app)
	await settle()
	for theme in ["dark", "light"]:
		AppUiTheme.select(theme)
		for locale in AppLocalization.codes():
			AppLocalization.select(locale)
			check(app.coop.launch.role.get_item_text(0) == "Host game", "role retains its source key for repeated language changes")
			check(app.coop.windows.menu.get_popup().get_item_text(0) == "Scoreboard", "menu retains its source key")
			check(app.coop.launch.goal_years.get_item_text(0) == tr("%d game years") % 1, "formatted option refreshes on language change")
			for role in [0, 1]:
				app.coop.launch.role.select(role)
				for mode in [0, 1, 2]:
					app.coop.mode_picker.select(mode)
					app.coop.launch.update()
					app.coop.open()
					await settle()
					check_fit(app.coop.panel, app.coop.lobby.get_parent(), "%s %s role %d mode %d" % [theme, locale, role, mode])
	var settled_size := app.coop.panel.size
	var settled_position := app.coop.panel.position
	for frame in 90:
		await process_frame
		check(app.coop.panel.size == settled_size and app.coop.panel.position == settled_position, "launch dialog geometry stays still")
	app.coop.panel.hide()
	app.coop.windows.seats.open()
	await settle()
	check_fit(app.coop.windows.seats.window, app.coop.windows.seats.body, "empty seat picker")
	app.coop.windows.seats.window.hide()
	app.coop.port.min_value = 0
	app.coop.port.value = 0
	app.coop.mode_picker.select(1)
	app.coop.host_document(Sc2xDocument.create_empty(32, "Drag check").document)
	app.coop.session.waiting_for_start = false
	app.coop.session.request({"kind": "speed", "speed": 2})
	await settle()
	app.map_view.selection_start = Vector2i(3, 3)
	app.map_view.selection_end = Vector2i(6, 6)
	app.preferences.visual_enhancements.weather_enabled = true
	app.preferences.visual_enhancements.weather_mode = 1
	app.preferences.visual_enhancements.pause_freezes = true
	var before := app.visual_environment.weather.clock
	app.visual_environment.process(0.25)
	check(app.visual_environment.weather.clock > before, "held tool does not freeze weather")
	check(app.visual_environment.network_snapshot().weather[20] == 0, "held tool does not send a pause to clients")
	check(not app.map_view.layers.environment_parameters.get("water_frozen", true), "held tool does not freeze water")
	app.coop.session.request({"kind": "speed", "speed": 1})
	app.visual_environment.process(0.25)
	check(app.visual_environment.network_snapshot().weather[20] == 1, "explicit host pause still freezes weather")
	app.map_view.selection_start = Vector2i(-1, -1)
	app.coop.windows.open_scoreboard()
	await settle()
	check_fit(app.coop.windows.scoreboard, app.coop.windows.score_rows, "scoreboard")
	check(app.coop.windows.scores.picker is HFlowContainer and app.coop.windows.scores.metric_picker is HFlowContainer, "both statistics selectors are wrapping tabs")
	app.coop.windows.scores.picker.select(6)
	app.coop.windows.scores.rebuild()
	await settle()
	check_fit(app.coop.windows.scoreboard, app.coop.windows.score_rows, "history")
	app.coop.windows.scoreboard.hide()
	app.coop.windows.open_chat()
	for collapsed in [true, false, true]:
		app.coop.windows.set_chat_collapsed(collapsed)
		await settle()
		var chat := app.coop.windows.chat
		var area := app.map_view.camera_view_rect
		check(chat.get_rect().end.y <= area.end.y, "chat remains above status bar after collapse or expansion")
		check(chat.get_rect().position.y >= area.position.y, "chat fits the visible map")
	app.coop.windows.preview_until = Time.get_ticks_msec() + 10000
	app.coop.windows.chat_preview.text = "Player: New message"
	await settle()
	check(app.coop.windows.chat.get_rect().end.y <= app.map_view.camera_view_rect.end.y, "collapsed message preview also fits")
	app.coop.windows.scoreboard.hide()
	var continuation := app.coop.windows.start_lobby
	var state := app.coop.session.make_state()
	state.lobby = {"waiting": true, "continuing": true, "can_start": false, "generation": 99}
	for locale in AppLocalization.codes():
		AppLocalization.select(locale)
		continuation.update(state)
		await settle()
		check_fit(continuation.window, continuation.body, "continuation " + locale)
		var item := continuation.roster.get_root().get_first_child()
		check(item.get_button_count(3) == 0 and item.get_button_count(4) == 0, "continuation cannot edit starting grants")
	continuation.window.hide()
	app.coop.leave()
	app.queue_free()
	await process_frame
	print("Multiplayer dialog checks: %d failures" % failures)
	quit(1 if failures else 0)
