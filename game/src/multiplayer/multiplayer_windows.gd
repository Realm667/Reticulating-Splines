class_name MultiplayerWindows
extends RefCounted
## Local windows and map annotations; they never mutate the authoritative city.

var owner_ref: WeakRef
var coop: ApplicationMultiplayer:
	get:
		return owner_ref.get_ref()
var menu: MenuButton
var scoreboard: Window
var score_rows: VBoxContainer
var chat: PanelContainer
var scores := MultiplayerScoreboard.new()
var seats: MultiplayerSeatWindow
var competition: MultiplayerCompetitionWindows
var start_lobby: MultiplayerStartLobby
var goal_hud: MultiplayerGoalHud
var market: MultiplayerLandMarket
var map_overlay := MultiplayerMapOverlay.new()
var land_button: Button
var land_options: VBoxContainer
var allowance_label: Label
var include_water := false
var pending_builds: Dictionary = {}
var displayed_round := 0
var chat_seen: Dictionary = {}
var event_seen: Dictionary = {}
var admin_seen: Dictionary = {}
var map_state_generation := 0
var displayed_map_generation := -1
var tones: Dictionary = {}
var chat_log: RichTextLabel
var chat_input: LineEdit
var chat_title: Label
var chat_toggle: Button
var chat_jump: Button
var chat_entry: HBoxContainer
var chat_preview: Label
var chat_collapsed := false
var chat_grip: Control
var remote_cursor := MultiplayerCursor.new()
var chat_height := 184.0
var chat_resize_y := -1.0
var chat_resize_height := 184.0
var preview_until := 0
var unread := 0
var players: Array = []
var state: Dictionary = {}
var overlay: Control
var land_tool_buttons: Array[Button] = []
var land_action := ""
var land_offer_price := -1
var known_disasters: Array = []
var alarm: AudioStreamPlayer
var own_disaster := 0
var decision_key := ""
var decision_dialog: AcceptDialog


func _init(owner: ApplicationMultiplayer) -> void:
	owner_ref = weakref(owner)


func setup() -> void:
	MultiplayerText.setup()
	coop.session.command_sent.connect(func(id: int, command: Dictionary) -> void:
		if command.get("kind") in ["build", "land_buy"] and command.get("start") is Array and command.get("finish") is Array:
			pending_builds[id] = command.duplicate(true).merged({"until": Time.get_ticks_msec() + 10000, "confirmed": -1})
			# This bounds only cosmetic previews, never the reliable command queue.
			if pending_builds.size() > 256:
				pending_builds.erase(pending_builds.keys()[0])
			if is_instance_valid(overlay):
				overlay.queue_redraw())
	coop.session.command_resolved.connect(func(id: int, result: Dictionary) -> void:
		if not pending_builds.has(id):
			return
		if not result.get("ok", false) or result.has("choices"):
			pending_builds.erase(id)
		else:
			pending_builds[id].confirmed = int(result.get("revision", -1)))
	var row := coop.app.city_menu_bar.newspaper_menu.get_parent()
	menu = MenuButton.new()
	menu.text = "Multiplayer"
	menu.disabled = true
	row.add_child(menu)
	row.move_child(menu, coop.app.city_menu_bar.newspaper_menu.get_index() + 1)
	var popup := menu.get_popup()
	var titles := ["Scoreboard", "Chat", "Host / Join game", "Release disconnect pause", "Leave game", "Buy land", "Offer land", "Land trade", "Player seats", "Neighbouring cities", "Rematch · rotate starts", "Request land"]
	for id in [0, 1, 8, 9, 10, 2, 3, 4, 5, 6, 11, 7]:
		if id in [2, 5]:
			popup.add_separator()
		popup.add_item(titles[id], id)
	popup.id_pressed.connect(func(id: int) -> void:
		match id:
			0:
				open_scoreboard()
			1:
				open_chat()
			2:
				coop.open()
			3:
				coop.session.release_disconnect_pause()
			4:
				coop.confirm_leave()
			5:
				select_land("land_buy")
			6:
				select_land("land_offer")
			11:
				select_land("land_request")
			7:
				open_offers()
			8:
				seats.open()
			9:
				competition.open_regions()
			10:
				coop.session.request({"kind": "rematch"})
	)
	scoreboard = make_window("Scoreboard")
	score_rows = content(scoreboard)
	scoreboard.size = Vector2i(1080, 520)
	scores.setup(score_rows)
	score_rows.minimum_size_changed.connect(func() -> void: fit_content.call_deferred(scoreboard, score_rows, 1080))
	market = MultiplayerLandMarket.new(self)
	seats = MultiplayerSeatWindow.new(self)
	competition = MultiplayerCompetitionWindows.new(self)
	start_lobby = MultiplayerStartLobby.new(self)
	goal_hud = MultiplayerGoalHud.new(self)
	chat = PanelContainer.new()
	chat.z_index = 2
	chat.theme = AppUiTheme.current()
	chat.theme_type_variation = "TooltipPanel"
	chat.mouse_filter = Control.MOUSE_FILTER_STOP
	coop.app.map_view.add_child(chat)
	FrostedTooltipPanel.bind(chat)
	chat.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	chat.grow_vertical = Control.GROW_DIRECTION_BEGIN
	chat.offset_left = 8
	chat.offset_right = 408
	chat.offset_top = -184
	chat.offset_bottom = -8
	chat.hide()
	var chat_body := VBoxContainer.new()
	chat.add_child(chat_body)
	var heading := HBoxContainer.new()
	chat_body.add_child(heading)
	var title := ApplicationMultiplayer.label(heading, "Chat")
	chat_title = title
	title.theme_type_variation = "TooltipLabel"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hide_button := Button.new()
	hide_button.text = "−"
	hide_button.tooltip_text = "Hide chat"
	heading.add_child(hide_button)
	chat_toggle = hide_button
	hide_button.pressed.connect(func() -> void: set_chat_collapsed(not chat_collapsed))
	chat_log = RichTextLabel.new()
	chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat_log.selection_enabled = true
	chat_log.scroll_following = true
	chat_log.get_v_scroll_bar().value_changed.connect(func(value: float) -> void:
		var scroll := chat_log.get_v_scroll_bar()
		chat_log.scroll_following = value >= scroll.max_value - scroll.page - 2)
	chat_body.add_child(chat_log)
	var chat_color := func() -> void:
		var panel_type := "UtilityPanel" if AppUiTheme.is_classic() else "TooltipPanel"
		if chat.theme_type_variation != panel_type:
			chat.theme_type_variation = panel_type
		chat_log.add_theme_font_override("normal_font", AppUiTheme.current().default_font)
		chat_log.add_theme_color_override("default_color", AppUiTheme.current().get_color("font_color", "TooltipLabel"))
	chat.theme_changed.connect(chat_color)
	chat_color.call()
	chat_preview = ApplicationMultiplayer.label(chat_body, "")
	chat_preview.autowrap_mode = TextServer.AUTOWRAP_OFF
	chat_preview.clip_text = true
	chat_preview.hide()
	chat_jump = ApplicationMultiplayer.button(chat_body, "", func() -> void:
		chat_log.scroll_following = true
		chat_log.get_v_scroll_bar().value = chat_log.get_v_scroll_bar().max_value
		unread = 0
		refresh_chat_heading())
	chat_jump.hide()
	chat_entry = HBoxContainer.new()
	chat_body.add_child(chat_entry)
	chat_input = LineEdit.new()
	chat_input.max_length = 500
	chat_input.placeholder_text = "Message…"
	chat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_entry.add_child(chat_input)
	var send := ApplicationMultiplayer.button(chat_entry, "➤", func() -> void: chat_input.text_submitted.emit(chat_input.text))
	send.tooltip_text = "Send message"
	chat_input.text_submitted.connect(func(text: String) -> void:
		coop.session.send_chat(text)
		chat_input.clear())
	chat_input.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			chat_input.release_focus()
			chat_input.accept_event())
	var grip := Control.new()
	chat_grip = grip
	grip.custom_minimum_size.y = 5
	grip.mouse_default_cursor_shape = Control.CURSOR_VSIZE
	chat_body.add_child(grip)
	chat_body.move_child(grip, 0)
	grip.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			chat_resize_y = chat.get_global_mouse_position().y if event.pressed else -1.0
			chat_resize_height = chat_height
		if event is InputEventMouseMotion and chat_resize_y >= 0:
			chat_height = clampf(chat_resize_height + chat_resize_y - chat.get_global_mouse_position().y, 150, 380))
	coop.session.chat_received.connect(receive_chat)
	coop.session.player_event.connect(receive_player_event)
	coop.session.presence_received.connect(func(value: Array) -> void:
		players = value
		map_overlay.receive(value)
		overlay.queue_redraw())
	overlay = Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	coop.app.map_view.add_child(overlay)
	overlay.draw.connect(draw_markers)
	coop.app.map_view.viewport_changed.connect(overlay.queue_redraw)
	alarm = AudioStreamPlayer.new()
	var wave := AudioStreamWAV.new()
	wave.format = AudioStreamWAV.FORMAT_16_BITS
	wave.mix_rate = 22050
	var samples := PackedByteArray()
	samples.resize(22050)
	for index in 11025:
		var frequency := 660.0 if index < 5512 else 880.0
		var envelope := sin(PI * fmod(float(index), 5512.0) / 5512.0)
		samples.encode_s16(index * 2, int(sin(TAU * frequency * index / 22050.0) * envelope * 6000.0))
	wave.data = samples
	alarm.stream = wave
	coop.app.add_child(alarm)
	for kind in ["chat", "joined", "left"]:
		var player := AudioStreamPlayer.new()
		player.max_polyphony = 4
		player.stream = cue(kind)
		coop.app.add_child(player)
		tones[kind] = player
	land_button = Button.new()
	land_button.icon = preload("res://assets/ui/buy_land.svg")
	land_button.theme_type_variation = "ArtworkButton"
	land_button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	land_button.custom_minimum_size = Vector2(32, 32)
	land_button.toggle_mode = true
	land_button.tooltip_text = tr("Land trade")
	land_button.hide()
	var signs := coop.app.city_toolbar.toolbar_buttons[CityToolIds.Group.SIGNS]
	signs.get_parent().add_child(land_button)
	signs.get_parent().move_child(land_button, signs.get_index())
	land_button.pressed.connect(func() -> void: select_land("land_buy"))
	land_options = VBoxContainer.new()
	var palette := coop.app.city_toolbar.child_palette
	palette.get_parent().add_child(land_options)
	palette.get_parent().move_child(land_options, palette.get_index() + 1)
	MultiplayerLandPalette.setup(self, land_options)
	land_options.hide()
	var tree := coop.app.get_tree()
	tree.process_frame.connect(tick)
	coop.app.tree_exiting.connect(func() -> void: tree.process_frame.disconnect(tick), CONNECT_ONE_SHOT)


func make_window(title: String) -> Window:
	var window := Window.new()
	window.title = title
	window.theme = AppUiTheme.current()
	window.size = Vector2i(680, 400)
	window.min_size = Vector2i(420, 240)
	window.visible = false
	window.close_requested.connect(window.hide)
	coop.app.add_child(window)
	return window


func content(window: Window) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	window.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_FILL
	scroll.add_child(body)
	MultiplayerDialogFit.bind(window, body, window.size.x)
	return body


func open_scoreboard() -> void:
	if state.get("lobby", {}).get("waiting", false):
		start_lobby.update(state)
		return
	if not state.get("goal", {}).get("winners", []).is_empty() and not state.goal.get("unscored", false):
		competition.ending.popup_centered()
		return
	refresh_scores()
	scoreboard.popup_centered()


func update_state(value: Dictionary) -> void:
	menu.disabled = not coop.active()
	if not coop.session.hosting:
		seats.window.hide()
	if state.get("view_owner") != value.get("view_owner"):
		if is_instance_valid(decision_dialog):
			decision_dialog.hide()
		coop.app.city_dialogs.budget_dialog.hide()
		coop.app.city_dialogs.military_dialog.hide()
		coop.app.simulation_state.military_proposal_pending = false
		coop.app.city_dialogs.ordinance_window.hide()
		coop.app.city_dialogs.industry_window.hide()
	if state.is_empty():
		chat.show()
	state = value
	map_overlay.receive_ownership(value)
	map_state_generation += 1
	allowance_label.text = tr("Remaining land allowance: %s · Price per tile: %s") % [MultiplayerScoreboard.money(value.get("land_allowance", 0)), MultiplayerScoreboard.money(value.get("land_price", 0))]
	players = value.get("roster", players)
	map_overlay.receive(players)
	land_button.visible = value.get("mode") == "shared"
	land_button.get_parent().columns = 3 if land_button.visible else 2
	market.refresh(value)
	for entry: Dictionary in value.get("admin_history", []):
		if not admin_seen.has(entry.id):
			admin_seen[entry.id] = true
			var notice := tr("Administration · %s · %s: %s (%s → %s)") % [entry.name, entry.city, tr(entry.action), MultiplayerText.message(entry.before), MultiplayerText.message(entry.after)]
			if entry.action == "Starting funds":
				notice = tr("Host set starting funds for %s to %s.") % [entry.city, MultiplayerScoreboard.money(int(entry.after))]
			elif entry.action == "Starting territory":
				notice = tr("Host set starting territory for %s to %s.") % [entry.city, entry.after]
			append_status(notice)
			coop.show_message(notice)
	competition.update(value)
	start_lobby.update(value)
	goal_hud.update(value, coop.session.token.sha256_text())
	for id in [5, 6, 7, 11]:
		menu.get_popup().set_item_disabled(menu.get_popup().get_item_index(id), value.get("mode") != "shared")
	menu.get_popup().set_item_disabled(menu.get_popup().get_item_index(9), value.get("mode") != "region")
	menu.get_popup().set_item_disabled(menu.get_popup().get_item_index(10), not coop.session.hosting or value.get("goal", {}).get("winners", []).is_empty())
	if scoreboard.visible:
		refresh_scores()
	overlay.queue_redraw()
	var pending: String = str(value.get("pending", ""))
	var active_disaster := int(value.get("disaster", 0))
	if active_disaster != 0 and own_disaster == 0:
		coop.app.effects_audio.play_sound_ids([520])
		coop.show_message(tr("Disaster in your city: deploy emergency services from the normal toolbar."))
	own_disaster = active_disaster
	if pending == "annual_budget":
		coop.show_message(tr("The annual budget awaits confirmation under Windows → Budget."))
	var key := pending + str(value.get("view_owner", "")) if value.get("blocked", false) and not value.get("visiting", false) else ""
	if key != decision_key:
		decision_key = key
		if is_instance_valid(decision_dialog):
			decision_dialog.queue_free()
		if pending == "military_proposal" and not value.get("visiting", false):
			coop.refresh_budget()
			coop.app.budget.open_military_proposal()
		elif pending == "annual_budget":
			open_annual_budget.call_deferred()
		elif not key.is_empty() and pending != "annual_budget":
			decision_dialog = AcceptDialog.new()
			decision_dialog.dialog_text = tr("Acknowledge the military administration notice to continue.") if pending == "military_notice" else tr("The simulation has a final notice. Acknowledge it to continue viewing the city.")
			coop.app.add_child(decision_dialog)
			var policy: int = int(value.get("policy", 0))
			decision_dialog.confirmed.connect(func() -> void: coop.session.request({"kind": "decision", "accept": true, "policy": policy}))
			decision_dialog.popup_centered()
	var disasters: Array = value.get("disasters", [])
	for disaster: Dictionary in disasters:
		if disaster.owner == coop.session.token.sha256_text() or known_disasters.has(disaster.owner):
			continue
		var name := tr("Neighbouring city")
		if disaster.has("city"):
			name = disaster.city
		for item: Dictionary in players:
			if item.get("id") == disaster.owner and not disaster.has("city"):
				name = str(item.name)
		coop.show_message(tr("Disaster at %s — area (%d, %d). Your emergency services can help.") % [name, int(disaster.point[0]), int(disaster.point[1])])
		if coop.app.document_state.city != null and coop.app.document_state.city.sound_enabled():
			alarm.volume_db = linear_to_db(clampf(float(coop.app.preferences.effects_volume), 0.0, 1.0))
			alarm.play()
	known_disasters.clear()
	for disaster: Dictionary in disasters:
		known_disasters.append(disaster.owner)


func refresh_scores() -> void:
	scores.update(players, state.get("mode") in ["shared", "region"], coop.session.token.sha256_text(), state.get("history", {}))


func open_chat() -> void:
	unread = 0
	menu.get_popup().set_item_text(1, "Chat")
	chat.show()
	set_chat_collapsed(false)
	chat_input.grab_focus()


func receive_chat(entry: Dictionary) -> void:
	var id := str(entry.get("id", ""))
	if not id.is_empty() and chat_seen.has(id):
		return
	chat_seen[id] = true
	if chat_seen.size() > 512:
		chat_seen.erase(chat_seen.keys()[0])
	if not entry.get("history", false) and entry.get("sender") != coop.session.token.sha256_text():
		play_cue("chat")
		chat.show()
	if not entry.get("history", false) and (chat_collapsed or not chat_log.scroll_following):
		unread += 1
	chat_preview.text = str(entry.get("name", "")) + ": " + str(entry.get("text", ""))
	preview_until = Time.get_ticks_msec() + 5000
	refresh_chat_heading()
	chat_log.push_color(Color(CoopSession.valid_color(entry.get("color"))))
	chat_log.add_text(str(entry.get("name", "")) + ": ")
	chat_log.pop()
	chat_log.add_text(str(entry.get("text", "")) + "\n")
	if chat_log.get_line_count() > 250:
		chat_log.remove_paragraph(0)
	if not chat.visible:
		unread += 1
		menu.get_popup().set_item_text(1, "Chat (%d)" % unread)


func draw_markers() -> void:
	if coop == null or not coop.active() or not coop.mirrored:
		return
	var map := coop.app.map_view
	var scale: float = map.camera._view_scale()
	var offset: Vector2 = map.camera._draw_offset(scale)
	var font := ThemeDB.fallback_font
	if state.get("mode") == "shared":
		var boundaries := map_overlay.boundaries(coop.app, state)
		overlay.draw_set_transform(offset, 0.0, Vector2.ONE * scale)
		for id: String in boundaries:
			for item: Dictionary in players:
				if item.get("id") == id.trim_suffix(":reserved") and not boundaries[id].is_empty():
					overlay.draw_multiline(boundaries[id], Color(CoopSession.valid_color(item.get("color")), 0.25 if id.ends_with(":reserved") else 0.8), 1.5 / scale, true)
		if Time.get_ticks_msec() < map_overlay.highlight_until:
			for tile: int in map_overlay.highlight:
				@warning_ignore("integer_division")
				var polygon := CityIsometricRenderer.terrain_surface_polygon(map.city, tile / map.city.map_size, tile % map.city.map_size)
				overlay.draw_colored_polygon(polygon, Color(1, 0.95, 0.45, 0.22))
				var outline := polygon.duplicate()
				outline.append(outline[0])
				overlay.draw_polyline(outline, Color(1, 0.95, 0.45, 0.8), 1.0 / scale)
				overlay.draw_line(polygon[0].lerp(polygon[1], 0.25), polygon[3].lerp(polygon[2], 0.25), Color(1, 0.95, 0.45, 0.45), 1.0 / scale)
		overlay.draw_set_transform(Vector2.ZERO)
	for item: Dictionary in players:
		if item.get("id") == coop.session.token.sha256_text() or not map_overlay.cursors.has(item.id):
			continue
		if state.get("mode") == "region" and item.get("view_owner") != state.get("view_owner"):
			continue
		for selected: Array in item.get("selection", []):
			var tile := Vector2i(int(selected[0]), int(selected[1]))
			var shape := CityIsometricRenderer.terrain_surface_polygon(map.city, tile.x, tile.y)
			var projected := PackedVector2Array()
			for point: Vector2 in shape:
				projected.append(point * scale + offset)
			overlay.draw_colored_polygon(projected, Color(CoopSession.valid_color(item.get("color")), 0.18))
		var center := MultiplayerMapOverlay.project(map.city, map_overlay.cursors[item.id].position) * scale + offset
		var color := Color(CoopSession.valid_color(item.get("color")))
		var bounds := map.camera_view_rect.grow(-3)
		if not bounds.has_point(center):
			continue
		var icon := remote_cursor.artwork(coop.app.desktop_presentation.graphics, item.get("cursor_tool", {}), color)
		var icon_extent := Vector2(16, 18)
		if not icon.is_empty():
			var pixel := maxi(1, roundi(DisplayServer.screen_get_scale())) / maxf(0.01, ScreenPixels.scale)
			var texture: Texture2D = icon.texture
			icon_extent = texture.get_size() * pixel
			var rect := Rect2(center - Vector2(icon.hotspot) * pixel, icon_extent)
			overlay.draw_texture_rect(texture, rect, false)
		else:
			var arrow := PackedVector2Array([center, center + Vector2(2, 17), center + Vector2(6, 12), center + Vector2(12, 12), center])
			overlay.draw_colored_polygon(arrow, color)
			overlay.draw_polyline(arrow, Color(0.06, 0.08, 0.10, 0.85), 1.0, true)
		var idle := float(Time.get_ticks_msec() - int(map_overlay.cursors[item.id].moved)) / 1000.0
		var alpha := clampf(3.0 - idle, 0.0, 1.0)
		if alpha <= 0:
			continue
		var text := str(item.get("name", ""))
		var extent := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14) + Vector2(12, 6)
		var anchor := center + Vector2(icon_extent.x + 4, -4)
		if anchor.x + extent.x > bounds.end.x:
			anchor.x = center.x - extent.x - 8
		anchor = anchor.clamp(bounds.position, bounds.end - extent)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.06, 0.075, 0.09, 0.85 * alpha)
		style.set_corner_radius_all(4)
		overlay.draw_style_box(style, Rect2(anchor, extent))
		color = color.lerp(Color.WHITE, 0.3)
		color.a = alpha
		overlay.draw_string(font, anchor + Vector2(6, 3 + font.get_ascent(14)), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)
	for unit: Dictionary in state.get("dispatch_owners", {}).values():
		var target := Vector2i(int(unit.position[0]), int(unit.position[1]))
		var polygon := CityIsometricRenderer.terrain_surface_polygon(map.city, target.x, target.y)
		for item: Dictionary in players:
			if item.get("id") != unit.get("actor"):
				continue
			var outline := PackedVector2Array()
			for point in polygon:
				outline.append(point * scale + offset)
			if not outline.is_empty():
				outline.append(outline[0])
				overlay.draw_polyline(outline, Color(CoopSession.valid_color(item.get("color"))), 3.0, true)
				if target == map.hover_tile:
					overlay.draw_string_outline(font, outline[0] + Vector2(8, -8), str(item.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, Color.BLACK)
					overlay.draw_string(font, outline[0] + Vector2(8, -8), str(item.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(CoopSession.valid_color(item.get("color"))))
	var preview_budget := 1024
	for id: int in pending_builds.keys():
		var pending: Dictionary = pending_builds[id]
		if not coop.session.connected or Time.get_ticks_msec() > int(pending.until) or (int(pending.confirmed) >= 0 and coop.display_revision >= int(pending.confirmed)) or pending.get("view_owner", "") != state.get("view_owner", ""):
			pending_builds.erase(id)
			continue
		if preview_budget <= 0:
			continue
		var a := Vector2i(int(pending.start[0]), int(pending.start[1]))
		var b := Vector2i(int(pending.finish[0]), int(pending.finish[1]))
		var sites: Array[Rect2i] = []
		var group := int(pending.get("group", -1))
		var tool := int(pending.get("tool", -1))
		if BuildingSites.supports_tool(group, tool):
			var path: Array = pending.get("path", [])
			if path.is_empty():
				path = [pending.finish]
			for point: Array in path.slice(0, preview_budget):
				sites.append(BuildingSites.footprint(Vector2i(int(point[0]), int(point[1])), int(ToolCatalog.tool(group, tool).area)))
		else:
			sites.append(Rect2i(Vector2i(mini(a.x, b.x), mini(a.y, b.y)), Vector2i(absi(a.x-b.x)+1, absi(a.y-b.y)+1)))
		for site in sites:
			preview_budget -= 1
			var polygon := PackedVector2Array()
			for point: Vector2 in [Vector2(site.position)-Vector2.ONE*0.5, Vector2(site.end.x,site.position.y)-Vector2.ONE*0.5, Vector2(site.end)-Vector2.ONE*0.5, Vector2(site.position.x,site.end.y)-Vector2.ONE*0.5]:
				polygon.append(MultiplayerMapOverlay.project(map.city, point) * scale + offset)
			if not Rect2(polygon[0], Vector2.ZERO).expand(polygon[1]).expand(polygon[2]).expand(polygon[3]).intersects(map.camera_view_rect):
				continue
			overlay.draw_colored_polygon(polygon, Color(1.0, 0.9, 0.3, 0.18))
			polygon.append(polygon[0])
			overlay.draw_polyline(polygon, Color(1.0, 0.9, 0.3, 0.8), 2.0, true)
	competition.draw_fireworks()


func open_annual_budget() -> void:
	# receive_state activates the incoming city after updating these windows.
	if coop.mirrored and coop.active() and state.get("pending") == "annual_budget":
		coop.refresh_budget()
		coop.app.budget.open_budget_dialog(BudgetPhase.funding_values(coop.app.document_state.city), true)

func close() -> void:
	menu.disabled = true
	start_lobby.window.hide()
	goal_hud.panel.hide()
	goal_hud.home.hide()
	goal_hud.visit_frame.hide()
	competition.close()
	market.close_map()
	if is_instance_valid(market.notification):
		market.notification.hide()
	seats.window.hide()
	chat.hide()
	chat_log.clear()
	chat_seen.clear()
	unread = 0
	set_chat_collapsed(false)
	event_seen.clear()
	displayed_round = 0
	pending_builds.clear()
	map_overlay.cursors.clear()
	map_overlay.cached_key.clear()
	map_overlay.highlight.clear()
	if is_instance_valid(market.detail):
		market.detail.hide()
	if is_instance_valid(market.map_detail):
		market.map_detail.queue_free()
	var minimap := coop.app.city_dialogs.city_map_window.map_control
	minimap.preview.set_ownership({}, 0)
	if minimap.has_meta("ownership_legend"):
		minimap.get_meta("ownership_legend").clear()
	displayed_map_generation = -1
	coop.app.city_menu_bar.debug_menu.disabled = false
	var popup := coop.app.city_menu_bar.windows_menu.get_popup()
	for id in [0, 1, 3, 7, CityMenuBar.MENU_CONSOLE]:
		popup.set_item_disabled(popup.get_item_index(id), false)
	market.initialized = false
	admin_seen.clear()
	market.known.clear()
	market.signature = ""
	if is_instance_valid(market.window):
		market.window.hide()
	cancel_land()
	land_button.hide()
	land_button.get_parent().columns = 2
	scoreboard.hide()
	players.clear()
	state.clear()
	known_disasters.clear()
	own_disaster = 0
	decision_key = ""
	if is_instance_valid(decision_dialog):
		decision_dialog.queue_free()
	land_action = ""
	unread = 0
	menu.get_popup().set_item_text(1, "Chat")
	overlay.queue_redraw()


func select_land(action: String) -> void:
	if state.get("mode") != "shared":
		coop.show_message(tr("Land trading is available in Shared mode."))
		return
	coop.app.current_tool.select_tool_group(CityToolIds.Group.QUERY)
	land_action = action
	update_land_tooltip()
	land_offer_price = -1
	coop.app.city_toolbar.land_mode = true
	coop.app.city_toolbar.hold_menu.hide()
	land_options.show()
	for index in land_tool_buttons.size():
		land_tool_buttons[index].set_pressed_no_signal(index == (2 if action == "land_offer" else 0) + (1 if include_water else 0))
	for button in coop.app.city_toolbar.toolbar_buttons:
		button.set_pressed_no_signal(false)
	land_button.set_pressed_no_signal(true)
	coop.app.current_tool.update_edit_state()
	coop.show_message(tr("Select neutral tiles to buy at the displayed price. Owned tiles are skipped.") if action == "land_buy" else tr("Select land belonging to another player to send a purchase request.") if action == "land_request" else tr("Select a parcel to review its owner, price and available trade action."))


func open_offers() -> void:
	market.open()


func cancel_land() -> void:
	land_action = ""
	land_options.hide()
	coop.app.city_toolbar.land_mode = false
	coop.app.city_toolbar.child_palette.show()
	if is_instance_valid(land_button):
		land_button.set_pressed_no_signal(false)


func tick() -> void:
	if not coop.active() or not coop.mirrored:
		return
	var round_id := int(state.get("round", 1))
	var own_start: Dictionary = state.get("starts", {}).get(coop.session.token.sha256_text(), {})
	if round_id != displayed_round and not state.get("lobby", {}).get("waiting", false) and not own_start.is_empty():
		displayed_round = round_id
		coop.app.camera_input.center_map_on_tile(Vector2i(int(own_start.point[0]), int(own_start.point[1])))
	map_overlay.step(coop.app.get_process_delta_time())
	chat_preview.visible = chat_collapsed and Time.get_ticks_msec() < preview_until
	var view: Rect2 = coop.app.map_view.camera_view_rect
	if view.size == Vector2.ZERO:
		view = Rect2(Vector2.ZERO, coop.app.map_view.size)
	var minimap := coop.app.city_dialogs.city_map_window.map_control
	if coop.app.city_dialogs.city_map_window.visible and displayed_map_generation != map_state_generation:
		displayed_map_generation = map_state_generation
		minimap.preview.set_ownership(state, coop.app.document_state.city.map_size)
		if not minimap.has_meta("ownership_legend"):
			var legend := RichTextLabel.new()
			legend.fit_content = true
			legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			minimap.add_child(legend)
			minimap.set_meta("ownership_legend", legend)
		var legend: RichTextLabel = minimap.get_meta("ownership_legend")
		legend.clear()
		if state.get("mode") == "shared":
			legend.add_text(tr("City territories") + ": ")
			legend.tooltip_text = tr("Solid: owned land. Hatched: reserved expansion. Grey: public road and power corridors.")
			for player: Dictionary in players:
				legend.push_color(Color.from_string(player.get("color", "ffffff"), Color.WHITE))
				legend.add_text("● " + str(player.name) + " · " + str(player.city) + "   ")
				legend.pop()
	view = view.intersection(Rect2(Vector2.ZERO, coop.app.map_view.size))
	if is_instance_valid(market.map_detail):
		market.map_detail.position = view.position + Vector2(12, 12)
		market.map_detail.custom_minimum_size.x = minf(360, maxf(0, view.size.x - 24))
		market.map_detail.size = Vector2(market.map_detail.custom_minimum_size.x, market.map_detail.get_combined_minimum_size().y)
	goal_hud.layout(view)
	var visiting: bool = state.get("visiting", false)
	coop.app.city_menu_bar.debug_menu.disabled = not coop.session.hosting or visiting
	var debug_popup := coop.app.city_menu_bar.windows_menu.get_popup()
	debug_popup.set_item_disabled(debug_popup.get_item_index(7), not coop.session.hosting or visiting)
	if not coop.session.hosting or visiting:
		coop.app.debug_overlay._window.hide()
		coop.app.debug_overlay.is_open = false
	var window_menu := coop.app.city_menu_bar.windows_menu.get_popup()
	window_menu.set_item_disabled(window_menu.get_item_index(CityMenuBar.MENU_CONSOLE), visiting or not coop.session.hosting)
	if visiting or not coop.session.hosting:
		coop.app.console_window.hide()
	for id in [0, 1, 3]:
		var index := window_menu.get_item_index(id)
		if index >= 0:
			window_menu.set_item_disabled(index, visiting)
	if visiting:
		coop.app.city_dialogs.budget_dialog.hide()
		coop.app.city_dialogs.military_dialog.hide()
		coop.app.simulation_state.military_proposal_pending = false
		coop.app.city_dialogs.ordinance_window.hide()
		coop.app.city_dialogs.industry_window.hide()
	if chat.get_parent() == coop.app.map_view:
		chat.offset_left = view.position.x + 8
		chat.offset_right = minf(chat.offset_left + 400, view.end.x - 8)
		layout_chat(view)
	overlay.queue_redraw()


func receive_player_event(event: Dictionary) -> void:
	var id := str(event.get("id", ""))
	if event_seen.has(id):
		return
	event_seen[id] = true
	if event_seen.size() > 256:
		event_seen.erase(event_seen.keys()[0])
	var kind := str(event.get("kind"))
	var text := tr("%s joined the game.") if kind == "joined" else (tr("%s left the game.") if kind == "left" else tr("%s lost the connection."))
	if kind == "taken_over":
		text = tr("%s took over an unoccupied player seat.")
	text = text % str(event.get("name", ""))
	append_status(text)
	coop.show_message(text)
	play_cue("joined" if kind == "joined" else "left")


func play_cue(kind: String) -> void:
	var city := coop.app.document_state.city
	if city == null or not city.sound_enabled():
		return
	var player: AudioStreamPlayer = tones[kind]
	player.volume_db = linear_to_db(clampf(float(coop.app.preferences.effects_volume), 0.0, 1.0))
	player.play()


static func cue(kind: String) -> AudioStreamWAV:
	var wave := AudioStreamWAV.new()
	wave.format = AudioStreamWAV.FORMAT_16_BITS
	wave.mix_rate = 22050
	var data := PackedByteArray()
	data.resize(17640 if kind == "chat" else 8820)
	for index in (8820 if kind == "chat" else 4410):
		var time := index / 22050.0
		var frequency := (880.0 if index < 4410 else 1318.5) if kind == "chat" else (523.25 if (index < 2205) == (kind == "joined") else 783.99)
		var envelope := pow(sin(PI * fmod(float(index), 2205.0) / 2205.0), 2)
		data.encode_s16(index * 2, int(sin(TAU * frequency * time) * envelope * (7600 if kind == "chat" else 3800)))
	wave.data = data
	return wave


func dock_chat(in_lobby: bool) -> void:
	var victory := is_instance_valid(competition.ending) and competition.ending.visible
	var embedded := in_lobby or victory
	var target: Node = start_lobby.body if in_lobby else competition.end_rows if victory else coop.app.map_view
	if chat.get_parent() == target:
		return
	chat.reparent(target, false)
	chat.custom_minimum_size.y = 160 if embedded else 0
	chat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat.size_flags_vertical = Control.SIZE_FILL
	chat.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT if embedded else Control.PRESET_BOTTOM_LEFT)
	chat.show()
	tick()

func fit_content(window: Window, body: Control, width := 680) -> void:
	var fitter: MultiplayerDialogFit = window.get_meta("multiplayer_fit")
	fitter.preferred_width = width
	fitter.schedule()


func preview_land(start: Vector2i, finish: Vector2i) -> void:
	var city := coop.app.document_state.city
	var owners: Array = state.get("owners", [])
	if city == null or owners.size() != city.map_size * city.map_size:
		coop.app.map_view.clear_selection_price()
		return
	var selected: Array = []
	for x in range(maxi(0, mini(start.x, finish.x)), mini(city.map_size - 1, maxi(start.x, finish.x)) + 1):
		for y in range(maxi(0, mini(start.y, finish.y)), mini(city.map_size - 1, maxi(start.y, finish.y)) + 1):
			selected.append(x * city.map_size + y)
	var owner: int = state.get("owner_ids", []).find(coop.session.token.sha256_text()) + 1
	var eligible := MultiplayerLandRules.purchasable(city, owners, state.get("protection", []), owner, selected, include_water)
	var count := eligible.size()
	map_overlay.highlight = eligible
	map_overlay.highlight_until = Time.get_ticks_msec() + 500
	var total := count * int(state.get("land_price", 0))
	var allowance := mini(total, int(state.get("land_allowance", 0)))
	var payment := total - allowance
	coop.app.map_view.set_selection_price(payment, payment <= city.funds())
	coop.app.status_label.text = tr("Land: %d tiles · Total %s · Allowance %s · City funds %s") % [count, MultiplayerScoreboard.money(total), MultiplayerScoreboard.money(allowance), MultiplayerScoreboard.money(payment)]
	coop.app.status_label.theme_type_variation = "" if payment <= city.funds() else "ErrorLabel"


func append_status(text: String) -> void:
	chat_log.push_font_size(13)
	chat_log.push_color(Color(0.8, 0.82, 0.85))
	chat_log.push_italics()
	# Segment literal names rather than interpreting player-supplied rich text.
	var offset := 0
	while offset < text.length():
		var nearest := text.length()
		var match_player: Dictionary = {}
		for player: Dictionary in players:
			var name := str(player.get("name", ""))
			var found := text.find(name, offset) if not name.is_empty() else -1
			if found >= 0 and found < nearest:
				nearest = found
				match_player = player
		chat_log.add_text(text.substr(offset, nearest - offset))
		if match_player.is_empty():
			break
		chat_log.push_color(Color(CoopSession.valid_color(match_player.get("color"))))
		chat_log.add_text(match_player.name)
		chat_log.pop()
		offset = nearest + str(match_player.name).length()
	chat_log.add_text("\n")
	chat_log.pop()
	chat_log.pop()
	chat_log.pop()

func set_chat_collapsed(value: bool) -> void:
	chat_collapsed = value
	chat_grip.visible = not value
	if value:
		chat_resize_y = -1.0
	chat_log.visible = not value
	chat_entry.visible = not value
	chat_toggle.text = "+" if value else "−"
	chat_toggle.tooltip_text = tr("Open chat") if value else tr("Collapse chat")
	if not value and chat_log.scroll_following:
		unread = 0
	refresh_chat_heading()

func layout_chat(view: Rect2) -> void:
	var height := chat.get_combined_minimum_size().y
	if not chat_collapsed:
		height = maxf(height, minf(chat_height, view.size.y - 16))
	chat.offset_bottom = view.end.y - coop.app.map_view.size.y - 8
	chat.offset_top = chat.offset_bottom - height


func refresh_chat_heading() -> void:
	chat_title.text = tr("Chat") + (" · %d" % unread if unread > 0 else "")
	chat_jump.text = tr("↓ %d new messages") % unread
	chat_jump.visible = unread > 0 and not chat_collapsed

func update_land_tooltip() -> void:
	land_button.tooltip_text = (tr("Sell land") if land_action == "land_offer" else tr("Buy land")) + " · " + (tr("Include water") if include_water else tr("Land only"))
