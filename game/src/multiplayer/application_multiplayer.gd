class_name ApplicationMultiplayer
extends RefCounted
## Connects the ordinary city tools to the shared host, while retaining a private view.

var app: CityApplication
var session: CoopSession
var panel: Window
var lobby: VBoxContainer
var player: LineEdit
var address: LineEdit
var port: SpinBox
var join_code: LineEdit
var use_current: CheckBox
var status: Label
var message: Label
var policy_at_open := 0
var original_document: Sc2File
var original_save_path := ""
var original_saved_snapshot := PackedByteArray()
var original_saved_once := false
var mirrored := false
var last_city_bytes := ""
var last_live_state: Dictionary = {}
var sign_dialog: ConfirmationDialog
var sign_text: LineEdit
var pending_sign: Dictionary = {}
var leave_dialog: ConfirmationDialog
var menu_button: MenuButton
var windows: MultiplayerWindows
var launch: MultiplayerLaunchMenu
var color_picker: ColorPickerButton
var mode_picker: OptionButton
var city_picker: OptionButton
var city_file: FileDialog
var pending_new_city := false
var pending_join: Dictionary = {}
var continuation_dialog: ConfirmationDialog
var selected_city_path := ""
var multiplayer_save_path := ""
var identity_signature := ""
var selection_revision := 0
var exit_action := ""
var ended_dialog: Window
var display_job: MultiplayerDisplayJob
var pending_display: Dictionary = {}
var display_revision := -1
var display_policy := -1
var display_prepare_usec := 0
var display_apply_usec := 0
var display_coalesced := 0


func _init(application: CityApplication) -> void:
	app = application


func active() -> bool:
	return session != null and session.active


func setup() -> void:
	session = CoopSession.new()
	session.environment_source = app.visual_environment.network_description
	session.environment_received.connect(app.visual_environment.receive_network_weather)
	app.add_child(session)
	session.state_received.connect(receive_state)
	session.interest_source = func() -> Dictionary:
		return MultiplayerInterest.local_view(app) if mirrored else {}
	session.summary_received.connect(func(summary: Dictionary) -> void:
		if mirrored:
			var current := windows.state.duplicate()
			current.merge(summary, true)
			windows.update_state(current))
	app.get_tree().process_frame.connect(poll_display)
	app.tree_exiting.connect(func() -> void:
		app.get_tree().process_frame.disconnect(poll_display)
		close_display())
	session.connection_changed.connect(func() -> void:
		if not session.active:
			close_display())
	session.session_ended.connect(func() -> void: MultiplayerCopyDialog.host_ended(self))
	session.cursor_source = func() -> Vector2:
		return MultiplayerMapOverlay.local_cursor(app) if mirrored and app.map_view.visible else Vector2(-1, -1)
	session.cursor_tool_source = func() -> Dictionary:
		var desktop := app.desktop_presentation
		var selection := desktop.cursor_selection(app.map_view, DisplayServer.screen_get_size(app.get_window().current_screen).x)
		return {"app": selection.app, "group": selection.group} if selection != null else {}
	session.selection_source = func() -> Array:
		if not mirrored or session.latest.get("visiting", false) or app.map_view.selection_start.x < 0:
			return []
		return app.map_view.selection_path.slice(0, 1024).map(func(point: Vector2i) -> Array: return [point.x, point.y])
	session.feedback.connect(show_message)
	session.action_sounds.connect(app.effects_audio.play_sound_ids)
	session.remote_action_sound.connect(play_remote_action)
	session.choice_requested.connect(show_choices)
	panel = Window.new()
	panel.theme = AppUiTheme.current()
	panel.title = "Multiplayer"
	panel.size = Vector2i(650, 650)
	panel.min_size = Vector2i(480, 240)
	panel.close_requested.connect(panel.hide)
	panel.hide()
	app.add_child(panel)
	var background := PanelContainer.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(background)
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	background.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	launch = MultiplayerLaunchMenu.new(self)
	launch.setup(body)
	MultiplayerDialogFit.bind(panel, body, 700)
	city_file = FileDialog.new()
	city_file.access = FileDialog.ACCESS_FILESYSTEM
	city_file.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	city_file.filters = PackedStringArray(["*.sc2x, *.sc2, *.SC2, *.sc2mp ; " + tr("Cities")])
	city_file.current_dir = AppPaths.path("cities")
	city_file.file_selected.connect(host_saved_city)
	app.add_child(city_file)
	status = label(body, "")
	status.hide()
	body.add_child(MultiplayerConnectivity.new(session))
	message = label(body, "")
	message.hide()
	sign_dialog = ConfirmationDialog.new()
	sign_dialog.theme = AppUiTheme.current()
	sign_dialog.title = "Shared sign"
	sign_text = LineEdit.new()
	sign_text.max_length = 120
	sign_text.custom_minimum_size.x = 400
	sign_dialog.add_child(sign_text)
	app.add_child(sign_dialog)
	sign_dialog.confirmed.connect(func() -> void:
		pending_sign["text"] = sign_text.text
		session.request(pending_sign.duplicate(true)))
	leave_dialog = ConfirmationDialog.new()
	leave_dialog.theme = AppUiTheme.current()
	leave_dialog.dialog_text = "Leave the session? Unsaved changes on the host will be lost.\nAs host, you will disconnect all other players."
	leave_dialog.confirmed.connect(func() -> void:
		var quitting := exit_action == "quit"
		leave()
		if quitting:
			finish_quit())
	leave_dialog.canceled.connect(func() -> void: exit_action = "")
	app.add_child(leave_dialog)
	windows = MultiplayerWindows.new(self)
	windows.setup()
	app.city_dialogs.city_save_dialog.canceled.connect(func() -> void: exit_action = "")
	menu_button = windows.menu
	app.main_menu.multiplayer_requested.connect(open)
	load_identity()


func refresh_language() -> void:
	if windows == null:
		return
	launch.update()
	windows.refresh_chat_heading()
	windows.update_land_tooltip()
	var scores := windows.scores
	scores.update(scores.rows, scores.picker.get_meta("shared", false), scores.self_id, scores.history)
	for column in 3:
		windows.start_lobby.roster.set_column_title(column, tr(["Player", "City", "Status"][column]))
	city_file.filters = PackedStringArray(["*.sc2x, *.sc2, *.SC2, *.sc2mp ; " + tr("Cities")])


func open() -> void:
	if active() and session.connected:
		windows.open_scoreboard()
		return
	lobby.show()
	launch.update()
	panel.popup_centered()


func remember_city() -> void:
	if active():
		return
	original_document = app.document_state.current_document
	original_save_path = app.document_state.current_save_path
	original_saved_snapshot = app.document_state.saved_city_snapshot.duplicate()
	original_saved_once = app.document_state.current_city_saved_once
	if original_document != null:
		if app.simulation_state.frame_simulation != null:
			app.simulation_state.frame_simulation.close()
			app.simulation_state.frame_simulation = null
		Sc2xCheckpoint.capture(app.simulation_state.speed_controller, original_document.sc2x_metadata)
		original_document = original_document.duplicate_document()


func start_host() -> void:
	if active() or not can_start():
		return
	if city_picker.selected == 1:
		if not selected_city_path.is_empty():
			host_saved_city(selected_city_path)
			return
		city_file.filters = PackedStringArray(["*.sc2x, *.sc2, *.SC2, *.sc2mp ; " + tr("Cities")])
		city_file.popup_centered_ratio(0.8)
		return
	remember_city()
	pending_new_city = true
	panel.hide()
	app.new_city.open_new_city_dialog()


func host_document(document: Sc2File) -> void:
	if not document.is_sc2x():
		var converted := Sc2xDocument.from_legacy(document)
		if not converted.ok:
			show_message(converted.error)
			return
		document = converted.document
	session.player_color = color_picker.color.to_html(false)
	session.host_land_price = int(launch.land_price.value)
	session.host_starter_tiles = 1024
	session.host_goal_kind = ["endless", "population", "wealth", "timed_score"][launch.goal_picker.selected]
	session.host_duration_years = int(launch.duration.value)
	session.host_goal_target = int(launch.goal_target.value)
	session.host_goal_years = [1, 3, 5, 10][launch.goal_years.selected]
	var result := session.host(document, int(port.value), join_code.text, player.text, ["coop", "shared", "region"][mode_picker.selected])
	if not result.is_empty():
		show_message(result)
		return
	pending_new_city = false
	if not launch.lan_only.button_pressed:
		session.publish_online(launch.auto_forward.button_pressed)
	save_identity()
	panel.hide()
	show_message("Game running on port %d. Choose a game speed." % int(port.value))


func host_saved_city(path: String, selected_seat := "") -> void:
	remember_city()
	selected_city_path = path
	multiplayer_save_path = "" if use_current.button_pressed else path
	if path.get_extension().to_lower() == "sc2mp":
		if selected_seat.is_empty():
			var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			session.ensure_credential()
			if saved is Dictionary and saved.get("members") is Dictionary and CoopSession.saved_seat(saved, session.credential).is_empty():
				confirm_host_seat(path, saved)
				return
		var error := session.resume_session(path, int(port.value), join_code.text, player.text, selected_seat)
		if not error.is_empty():
			show_message(error)
		elif not launch.lan_only.button_pressed:
			session.publish_online(launch.auto_forward.button_pressed)
		return
	var document := Sc2File.new()
	if not document.parse(FileAccess.get_file_as_bytes(path)):
		show_message(document.parse_error)
		return
	if document.sc2x_extra_entries.has("multiplayer.json") and selected_seat.is_empty():
		var saved: Variant = JSON.parse_string(document.sc2x_extra_entries["multiplayer.json"].get_string_from_utf8())
		session.ensure_credential()
		if saved is Dictionary and saved.get("members") is Dictionary and CoopSession.saved_seat(saved, session.credential).is_empty():
			confirm_host_seat(path, saved)
			return
	host_document(document)
	if session.hosting and document.sc2x_extra_entries.has("multiplayer.json"):
		var error := session.restore_embedded(document, selected_seat)
		if not error.is_empty():
			leave()
			show_message(error)


func start_join() -> void:
	if not can_start():
		return
	if not pending_join.is_empty():
		return
	var endpoint := address.text.strip_edges()
	var endpoint_port := int(port.value)
	if not launch.advanced.button_pressed and launch.join_tabs.current_tab == 0:
		var room := launch.internet_browser.selected_online
		var info: Dictionary = launch.internet_browser.discovery.results.get(room, {})
		if info.is_empty() or not info.open or info.build != CoopSession.NETWORK_BUILD:
			show_message("Select an Internet game first.")
			return
		endpoint = info.address
		endpoint_port = int(info.port)
	pending_join = {"address": endpoint, "port": endpoint_port, "code": join_code.text, "name": player.text}
	launch.action.disabled = true
	launch.compatibility_status.text = tr("Checking compatibility…")
	launch.compatibility.check_host(endpoint, endpoint_port)


func cancel_compatibility() -> void:
	if launch == null or launch.compatibility == null:
		return
	launch.compatibility.cancel()
	pending_join.clear()
	if launch.action != null:
		launch.action.disabled = false
	launch.compatibility_status.text = tr("Compatibility is checked before joining. Visual packs may differ.")


func compatibility_checked(error: String) -> void:
	var target := pending_join.duplicate()
	pending_join.clear()
	launch.action.disabled = false
	if target.is_empty() or not panel.visible or launch.role.selected != 1:
		return
	launch.compatibility_status.text = tr("Compatible") if error.is_empty() else tr(error)
	if not error.is_empty() or not can_start():
		return
	remember_city()
	session.player_color = color_picker.color.to_html(false)
	var result := session.join(target.address, target.port, target.code, target.name, "choose")
	show_message(result if not result.is_empty() else "Connecting to the host…")
	save_identity()


func confirm_host_seat(path: String, saved: Dictionary) -> void:
	if is_instance_valid(continuation_dialog):
		continuation_dialog.queue_free()
	continuation_dialog = ConfirmationDialog.new()
	continuation_dialog.theme = AppUiTheme.current()
	continuation_dialog.title = tr("Continue saved game")
	continuation_dialog.dialog_text = tr("This profile has no saved player seat. Choose the player whose city you will take over as host.")
	continuation_dialog.ok_button_text = tr("Approve takeover")
	var choices := OptionButton.new()
	for actor: Variant in saved.members:
		if actor is String and saved.members[actor] is Dictionary:
			choices.add_item(str(saved.members[actor].get("name", actor)))
			choices.set_item_metadata(choices.item_count - 1, actor)
	continuation_dialog.add_child(choices)
	app.add_child(continuation_dialog)
	continuation_dialog.confirmed.connect(func() -> void:
		if choices.selected >= 0:
			host_saved_city(path, str(choices.get_item_metadata(choices.selected))))
	continuation_dialog.popup_centered(Vector2i(560, 180))


static func city_fields(state: Dictionary) -> Dictionary:
	var result := {"document": state.get("document")}
	for key: String in state:
		if key.begins_with(MultiplayerDocument.PREFIX):
			result[key] = state[key]
	return result


func receive_state(state: Dictionary) -> void:
	# First activation and legacy archives retain the synchronous loading path.
	# Afterwards there is one immutable worker and one replaceable latest state.
	# Original-sized maps use the low-latency fast path; large maps move their
	# preparation off-thread rather than adding worker latency to tiny updates.
	if mirrored and state.get("document") is Dictionary and int(state.document.get("size", 0)) > 128:
		if not pending_display.is_empty():
			display_coalesced += 1
		pending_display = state
		return
	apply_display(state)


func close_display() -> void:
	if display_job != null:
		display_job.finish()
		display_job = null
	pending_display.clear()
	display_revision = -1
	display_policy = -1


func poll_display() -> void:
	if display_job != null:
		if not display_job.ready():
			return
		var ready := display_job
		display_job = null
		ready.finish()
		display_prepare_usec += ready.elapsed_usec
		# Never publish a prepared old city after the player changed views.
		if ready.state.get("view_owner") == session.latest.get("view_owner"):
			var began := Time.get_ticks_usec()
			apply_display(ready.state, ready)
			display_apply_usec += Time.get_ticks_usec() - began
		# At most one expensive commit per frame; the next job starts next frame.
		return
	if pending_display.is_empty() or not active() or not mirrored:
		return
	var state := pending_display
	pending_display = {}
	if last_live_state == city_fields(state):
		apply_display(state)
		return
	display_job = MultiplayerDisplayJob.new()
	display_job.start(state, last_live_state, app.document_state.current_document)


func apply_display(state: Dictionary, prepared: MultiplayerDisplayJob = null) -> void:
	if int(state.get("summary_sequence", -1)) < int(session.latest.get("summary_sequence", -1)):
		state = state.duplicate()
		for field: String in CoopSession.SUMMARY_FIELDS:
			if session.latest.has(field):
				state[field] = session.latest[field]
		state["summary_sequence"] = session.latest.summary_sequence
	var same_view: bool = windows.state.get("view_owner") == state.get("view_owner")
	windows.update_state(state)
	if not str(state.get("error", "")).is_empty():
		show_message(str(state.error))
	var live: bool = state.get("document") is Dictionary
	var unchanged: bool = last_live_state == city_fields(state) if live else last_city_bytes == state.get("city", "")
	if unchanged:
		display_revision = int(state.revision)
		display_policy = int(state.get("policy", 0))
		app.simulation_state.speed_controller.speed = int(state.get("speed", 1))
		app.frame.sync_speed_ui()
		refresh_budget_view()
		receive_newspaper(state)
		if app.knowledge != null:
			app.knowledge.observe_host(state)
		return
	var document := prepared.document if prepared != null else MultiplayerDocument.restore(state, last_live_state, app.document_state.current_document) if live else Sc2File.new()
	if document == null or (not live and not document.parse(Marshalls.base64_to_raw(state.city))) or not document.is_sc2x() or document.map_size not in Sc2File.MAP_SIZES:
		show_message("Invalid city state from the host. Leave the session and reconnect.")
		return
	last_city_bytes = str(state.get("city", ""))
	last_live_state = city_fields(state) if live else {}
	display_revision = int(state.revision)
	display_policy = int(state.get("policy", 0))
	if mirrored:
		# Camera-follow and audio choices belong to this player.
		var local_city := CityState.new()
		local_city.document = document
		local_city.set_auto_goto_enabled(app.document_state.city.auto_goto_enabled())
		local_city.set_sound_enabled(app.document_state.city.sound_enabled())
		local_city.set_music_enabled(app.document_state.city.music_enabled())
	if not mirrored:
		if not app.city_session.activate_document(document, null, tr("Multiplayer connected"), true):
			return
		if app.simulation_state.frame_simulation != null:
			app.simulation_state.frame_simulation.close()
			app.simulation_state.frame_simulation = null
		mirrored = true
		refresh_budget()
		panel.hide()
	else:
		var edit := EditCommandResult.new()
		edit.ok = true
		var previous := app.document_state.current_document
		var map_changed := false
		for index in document.chunks.size():
			var chunk := document.chunks[index]
			var old := previous.find_chunk(chunk.chunk_id)
			if old != null:
				chunk.mutation_revision = old.mutation_revision
			var changed: bool = chunk.chunk_id in prepared.edit.changed_ids if prepared != null else old == null or old.decoded_payload != chunk.decoded_payload
			# MISC may have local sound/camera preferences applied above.
			if chunk.chunk_id == "MISC" and old != null:
				changed = old.decoded_payload != chunk.decoded_payload
			if changed:
				chunk.mark_mutated()
				edit.changed_ids.append(chunk.chunk_id)
				edit.old_payloads[chunk.chunk_id] = old.decoded_payload if old != null else PackedByteArray()
				edit.new_payloads[chunk.chunk_id] = chunk.decoded_payload
				if chunk.chunk_id in ["ALTM", "XTER", "XBLD", "XZON", "XBIT", "XTXT", "XUND", "XLAB", "XTRF"] or (CityViewMode.is_data(app.view_state.overlay_mode) and chunk.chunk_id not in ["MISC", "XTHG", "XGRP", "CNAM"]):
					map_changed = true
			elif old != null:
				document.chunks[index] = old
		# Keep the display city's identity. Render caches and cosmetic clocks use it
		# to distinguish an edit from opening a different city.
		for field_name in ["chunks", "source_bytes", "sc2x_metadata", "sc2x_compat_labels",
				"sc2x_object_ids", "sc2x_object_kinds", "sc2x_object_names", "sc2x_extensions",
				"sc2x_text_orders", "sc2x_preserved", "sc2x_extra_entries", "sc2x_unsupported_features",
				"sc2x_converted_from", "large_version"]:
			previous.set(field_name, document.get(field_name))
		previous.rebuild_chunk_cache()
		app.document_state.city.resync_mirrors(edit.changed_ids)
		app.simulation_state.simulation_engine.clock.city_days = app.document_state.city.age_in_days()
		Sc2xCheckpoint.restore(app.simulation_state.speed_controller, previous.sc2x_metadata)
		if map_changed:
			app.static_render.refresh_after_city_edit(edit)
			if app.render_caches.region_cache == null:
				windows.map_overlay.segment_cache.clear()
				windows.map_overlay.occlusion_generation += 1
			if same_view:
				show_demolition(edit)
		app.moving_sprites.refresh_moving_things()
		app.interface.refresh_details()
	app.city_menu_bar.set_city_name(app.document_state.city.display_name(),
		DebugFileInfo.city_tooltip(app.document_state.city.display_name(), app.document_state.current_document))
	app.simulation_state.speed_controller.speed = int(state.get("speed", 1))
	app.frame.sync_speed_ui()
	refresh_budget_view()
	receive_newspaper(state)
	save_identity()
	if app.knowledge != null:
		app.knowledge.observe_host(state)


func apply_selection(start: Vector2i, finish: Vector2i, path: Array[Vector2i], dragged: bool) -> void:
	# A newly requested city can arrive before its prepared display transaction.
	# Never interpret coordinates from the previous city's still-visible map.
	if windows.state.get("view_owner") != session.latest.get("view_owner"):
		return
	if windows.land_action != "":
		windows.market.select_parcel(start, finish)
		return
	var group := app.tool_state.selected_group
	if group == CityToolIds.Group.QUERY:
		app.query_choices.open_query(finish)
		return
	if group == CityToolIds.Group.CENTERING:
		app.camera_input.center_map_on_tile(finish)
		return
	if session.latest.get("visiting", false):
		show_message("This city view is read-only. Return to your own city to make changes.")
		return
	var positions: Array = []
	for target in path:
		positions.append([target.x, target.y])
	var command := {"kind": "build", "group": group, "tool": app.tool_state.selected_subtool,
		"revision": display_revision if display_revision >= 0 else session.local_revision,
		"start": [start.x, start.y], "finish": [finish.x, finish.y], "path": positions,
		"dragged": dragged, "underground": app.view_state.overlay_mode == CityViewMode.Mode.UNDERGROUND}
	if dragged:
		command["revision"] = selection_revision
	if group == CityToolIds.Group.SIGNS:
		command["kind"] = "sign"
		pending_sign = command
		sign_text.max_length = mini(120, app.document_state.current_document.name_limit())
		sign_text.text = CitySignTable.text_at(app.document_state.city, finish)
		sign_dialog.popup_centered()
	else:
		session.request(command)


func bulldoze(point: Vector2i) -> void:
	if windows.state.get("view_owner") != session.latest.get("view_owner") or session.latest.get("visiting", false):
		return
	session.request({"kind": "build", "group": 0, "tool": 0, "start": [point.x, point.y],
		"finish": [point.x, point.y], "path": [[point.x, point.y]], "dragged": false,
		"revision": display_revision if display_revision >= 0 else session.local_revision})


func request_speed(value: int) -> void:
	if not session.hosting:
		return
	if value > GameSpeedController.Speed.PAUSED:
		app.simulation_state.resume_speed = value
	session.request({"kind": "speed", "speed": value})


func refresh_budget() -> void:
	policy_at_open = display_policy if display_policy >= 0 else session.local_policy
	budget_at_open = BudgetPhase.funding_values(app.document_state.city)

var budget_at_open := PackedInt32Array()
var newspaper_seen: Dictionary = {}

func refresh_budget_view() -> void:
	var dialog := app.city_dialogs.budget_dialog
	if not mirrored or not dialog.visible:
		return
	# Refresh confirmed ordinances and accounting without replacing draft funding,
	# Auto-Budget, focus, or the selected tab. Foreign funding edits keep the
	# original policy guard so stale drafts cannot silently overwrite them.
	var current := BudgetPhase.funding_values(app.document_state.city)
	if current.size() == budget_at_open.size():
		for index in [3, 4]:
			current[index] = budget_at_open[index]
	if current == budget_at_open:
		policy_at_open = display_policy if display_policy >= 0 else session.local_policy
	dialog.set_city(app.document_state.city)
	app.budget._update_bond_controls()

func receive_newspaper(state: Dictionary) -> void:
	if not mirrored or state.get("visiting", false):
		return
	var owner := str(state.get("view_owner", session.token))
	var sequence := int(state.get("newspaper_sequence", 0))
	var previous := int(newspaper_seen.get(owner, sequence))
	newspaper_seen[owner] = sequence
	if sequence > previous:
		app.reports.open_scheduled_newspaper(int(state.get("newspaper_paper", -1)))

func show_demolition(edit: EditCommandResult) -> void:
	if not edit.old_payloads.has("XBLD") or not edit.new_payloads.has("XBLD"):
		return
	var old: PackedByteArray = edit.old_payloads.XBLD
	var current: PackedByteArray = edit.new_payloads.XBLD
	var effects: Array[EffectEvent] = []
	var city := app.document_state.city
	var map := app.map_view
	var scale: float = map.camera._view_scale()
	var offset: Vector2 = map.camera._draw_offset(scale)
	for block in range(0, mini(old.size(), current.size()), 512):
		var end := mini(block + 512, mini(old.size(), current.size()))
		if old.slice(block, end) == current.slice(block, end):
			continue
		for tile in range(block, end):
			if old[tile] <= 13 or current[tile] > 13:
				continue
			@warning_ignore("integer_division")
			var point := Vector2i(tile / city.map_size, tile % city.map_size)
			if not map.camera_view_rect.grow(64).has_point(MultiplayerMapOverlay.project(city, Vector2(point)) * scale + offset):
				continue
			for frame in 4:
				effects.append(EffectEvent.new(point, 1392 + frame, Vector2i.ZERO, false, frame))
	if not effects.is_empty():
		app.effects_audio.show_effect_events(effects, [])


func send_decision(accepted: bool) -> void:
	session.request({"kind": "decision", "accept": accepted, "policy": policy_at_open})


func save(as_copy := false) -> void:
	if not session.hosting:
		show_message("The host saves the shared game.")
		return
	if as_copy or multiplayer_save_path.is_empty() or not multiplayer_save_path.ends_with(".sc2x"):
		app.city_files.open_save_dialog()
	else:
		save_to(multiplayer_save_path)


func save_to(path: String) -> void:
	if not path.to_lower().ends_with(".sc2x"):
		path = path.get_basename() + ".sc2x"
	var error := session.save_city(path)
	if not error.is_empty():
		exit_action = ""
		app.interface.show_error(MultiplayerText.message(error))
	if error.is_empty():
		multiplayer_save_path = path
		if exit_action == "quit":
			session.stop()
			finish_quit()
	show_message(error if not error.is_empty() else tr("Multiplayer game saved: %s") % path)


func confirm_leave() -> void:
	exit_action = ""
	leave_dialog.popup_centered()


func leave() -> void:
	session.stop()
	newspaper_seen.clear()
	mirrored = false
	last_city_bytes = ""
	last_live_state.clear()
	panel.hide()
	multiplayer_save_path = ""
	windows.close()
	if original_document != null:
		app.city_session.activate_document(original_document, null, tr("Left multiplayer"), true)
		app.document_state.current_save_path = original_save_path
		app.document_state.saved_city_snapshot = original_saved_snapshot
		app.document_state.current_city_saved_once = original_saved_once
	else:
		app.visual_preparation.reset()
		app.document_state.city = null
		app.document_state.current_document = null
		app.simulation_state.speed_controller = null
		app.simulation_state.simulation_engine = null
		app.map_render.refresh_map(false)
		app.interface.show_main_menu()


func show_message(text: String) -> void:
	text = MultiplayerText.message(text)
	message.text = text
	app.interface.show_status(text)


func show_choices(result: Dictionary) -> void:
	var dialog := AcceptDialog.new()
	dialog.theme = AppUiTheme.current()
	dialog.title = MultiplayerText.message(str(result.message))
	dialog.get_ok_button().text = "Cancel"
	var list := VBoxContainer.new()
	dialog.add_child(list)
	app.add_child(dialog)
	for choice: Variant in result.choices:
		if not choice is Dictionary or not choice.get("fields") is Dictionary:
			continue
		var command: Dictionary = result.request.duplicate(true)
		command.merge(choice.fields, true)
		button(list, MultiplayerText.message(str(choice.get("label", "Choose"))), func() -> void:
			session.request(command)
			dialog.queue_free())
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()


func load_identity() -> void:
	var config := ConfigFile.new()
	if config.load(AppPaths.path("multiplayer-client.cfg")) != OK:
		return
	var stored: String = str(config.get_value("client", "token", ""))
	if stored.length() == 48:
		session.token = stored
		session.credential = stored
	player.text = str(config.get_value("client", "name", "Mayor"))
	address.text = str(config.get_value("client", "address", "127.0.0.1"))
	port.value = float(config.get_value("client", "port", 20000))
	color_picker.color = Color(CoopSession.valid_color(config.get_value("client", "color", "46b4ff")))
	color_picker.color_changed.emit(color_picker.color)


func can_start() -> bool:
	if active():
		return not session.hosting
	if app.tool_state.landscape_editor:
		show_message("Finish creating the terrain with Start City first.")
		return false
	var error := Sc2xCheckpoint.save_error(app.simulation_state.speed_controller)
	if not error.is_empty():
		show_message(error)
		return false
	if player.text.strip_edges().is_empty() or player.text.length() > 32 or join_code.text.length() > 64:
		show_message("Use a player name of 1–32 characters and an optional password of at most 64 characters.")
		return false
	return true


func save_identity() -> void:
	var signature := str([session.credential, player.text, address.text, port.value, color_picker.color])
	if signature == identity_signature:
		return
	identity_signature = signature
	var config := ConfigFile.new()
	config.set_value("client", "token", session.credential)
	config.set_value("client", "name", player.text)
	config.set_value("client", "address", address.text)
	config.set_value("client", "port", int(port.value))
	config.set_value("client", "color", color_picker.color.to_html(false))
	config.save(AppPaths.path("multiplayer-client.cfg"))


static func label(parent: Node, text: String) -> Label:
	var control := Label.new()
	control.text = text
	control.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	control.custom_minimum_size.x = 120
	parent.add_child(control)
	return control


static func button(parent: Node, text: String, action: Callable) -> Button:
	var control := Button.new()
	control.text = text
	control.pressed.connect(action)
	parent.add_child(control)
	return control


static func field(parent: Node, title: String, value: String) -> LineEdit:
	label(parent, title)
	var control := LineEdit.new()
	control.text = value
	parent.add_child(control)
	return control


func request_exit(action: String) -> void:
	if exit_action == "quit":
		return
	if action != "quit":
		confirm_leave()
		return
	exit_action = "quit"
	if not session.hosting:
		leave_dialog.popup_centered()
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = tr("Quit multiplayer")
	dialog.dialog_text = tr("Save the multiplayer game before quitting? All connected players will be disconnected.")
	dialog.ok_button_text = tr("Save and quit")
	dialog.add_button(tr("Quit without saving"), false, "discard")
	app.add_child(dialog)
	dialog.confirmed.connect(func() -> void:
		dialog.queue_free()
		save())
	dialog.custom_action.connect(func(value: StringName) -> void:
		if value == &"discard":
			session.stop()
			finish_quit())
	dialog.canceled.connect(func() -> void:
		exit_action = ""
		dialog.queue_free())
	dialog.popup_centered()

var remote_audio_gate := WaveSoundGate.new()
var remote_audio_time := 0

func play_remote_action(event: Dictionary) -> void:
	if not mirrored or app.document_state.city == null or not event.get("point") is Array or event.point.size() != 2 or not event.get("sounds") is Array:
		return
	if session.latest.get("mode") == "region" and event.get("view_owner") != session.latest.get("view_owner"):
		return
	for coordinate: Variant in event.point:
		if not CoopWorld.whole_number(coordinate, 0, app.document_state.city.map_size - 1):
			return
	var map := app.map_view
	var point := MultiplayerMapOverlay.project(map.city, Vector2(event.point[0], event.point[1])) * map.camera._view_scale() + map.camera._draw_offset(map.camera._view_scale())
	var view := map.camera_view_rect
	if view.size == Vector2.ZERO:
		view = Rect2(Vector2.ZERO, map.size)
	var gain := remote_gain(point, view)
	if gain <= 0:
		return
	var sounds: Array[int] = []
	for value: Variant in event.sounds.slice(0, 32):
		if CoopWorld.whole_number(value, 500, 529):
			sounds.append(int(value))
	var now := Time.get_ticks_msec()
	remote_audio_gate.advance(now - remote_audio_time)
	remote_audio_time = now
	# Remote construction must never suppress the local player's own feedback.
	app.audio_controller.play_sound_events(SoundEvent.from_ids(sounds), app.document_state.city.sound_enabled(), app.view_state.overlay_mode, app.static_render.city_view_size(), false, gain, remote_audio_gate)

static func remote_gain(point: Vector2, view: Rect2) -> float:
	var nearest := point.clamp(view.position, view.end)
	var distance := point.distance_to(nearest) / maxf(1.0, view.size.x)
	return pow(maxf(0.0, 1.0 - distance / 2.0), 2)


func finish_quit() -> void:
	# Keep processing until the final ordered leave is acknowledged or times out.
	session.stop()
	while not session.retiring_channels.is_empty():
		await app.get_tree().process_frame
	app.get_tree().quit()
