class_name MultiplayerStartLobby
extends RefCounted
## The host owns readiness and start; this window only submits requests.

var owner_ref: WeakRef
var windows: MultiplayerWindows:
	get:
		return owner_ref.get_ref()
var window: Window
var roster: Tree
var summary: Label
var ready: Button
var start: Button
var own_ready := false
var hint: Label
var leave_button: Button
var body: VBoxContainer
var waiting := false
var roster_signature := ""
var handicap_dialog: Window
const EDIT_ICON := preload("res://src/multiplayer/icons/edit_cell.svg")

func _init(owner: MultiplayerWindows) -> void:
	owner_ref = weakref(owner)
	window = windows.make_window("Game lobby")
	window.size = Vector2i(660, 430)
	window.min_size = Vector2i(400, 300)
	body = windows.content(window)
	window.visibility_changed.connect(func() -> void:
		if is_instance_valid(windows.chat):
			windows.dock_chat(window.visible and waiting))
	summary = ApplicationMultiplayer.label(body, "")
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(MultiplayerConnectivity.new(windows.coop.session))
	roster = Tree.new()
	roster.hide_root = true
	roster.select_mode = Tree.SELECT_SINGLE
	roster.cell_selected.connect(func() -> void:
		var row := roster.get_selected()
		if row != null and roster.get_selected_column() == 1 and row.is_editable(1):
			roster.edit_selected.call_deferred()
		elif row != null and row.get_metadata(roster.get_selected_column()) == true and roster.get_selected_column() in [3, 4] and windows.coop.session.hosting:
			edit_handicap(str(row.get_metadata(0))))
	roster.button_clicked.connect(func(row: TreeItem, column: int, _id: int, _mouse: int) -> void:
		if column == 1 and row.is_editable(1):
			row.select(1)
			roster.edit_selected.call_deferred()
		elif column in [3, 4] and windows.coop.session.hosting:
			edit_handicap(str(row.get_metadata(0))))
	roster.mouse_exited.connect(roster.queue_redraw)
	roster.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			roster.queue_redraw())
	roster.draw.connect(draw_edit_hover)
	roster.item_edited.connect(func() -> void:
		var row := roster.get_edited()
		if row != null and roster.get_edited_column() == 1 and row.is_editable(1):
			windows.coop.session.request({"kind": "rename_city", "name": row.get_text(1)})
			roster_signature = "")
	roster.columns = 5
	roster.column_titles_visible = true
	roster.scroll_horizontal_enabled = false
	roster.size_flags_vertical = Control.SIZE_FILL
	roster.set_column_title(0, tr("Player"))
	roster.set_column_title(1, tr("City"))
	roster.set_column_title(2, tr("Status"))
	for column in 5:
		roster.set_column_clip_content(column, true)
	body.add_child(roster)
	hint = ApplicationMultiplayer.label(body, "")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var actions := HBoxContainer.new()
	body.add_child(actions)
	ready = ApplicationMultiplayer.button(actions, "Ready", func() -> void:
		windows.coop.session.request({"kind": "lobby_ready", "ready": not own_ready}))
	start = ApplicationMultiplayer.button(actions, "Start game", func() -> void:
		windows.coop.session.request({"kind": "lobby_start"}))
	leave_button = ApplicationMultiplayer.button(actions, "Leave game", windows.coop.confirm_leave)

func update(state: Dictionary) -> void:
	var lobby: Dictionary = state.get("lobby", {})
	waiting = lobby.get("waiting", false)
	if not waiting:
		window.hide()
		return
	var session := windows.coop.session
	window.title = tr("Game lobby")
	for column in 5:
		roster.set_column_title(column, tr(["Player", "City", "Status", "Starting funds", "Starting land"][column]))
	hint.text = tr("At least two players must join. Everyone confirms Ready; the host then starts the game. Changes to the player list reset readiness.") + "\n" + tr("Fields with a pencil can be edited.")
	start.text = tr("Start game")
	leave_button.text = tr("Leave game")
	var mode := tr("Co-op") if state.get("mode", "coop") == "coop" else tr("Competitive Region") if state.get("mode") == "region" else tr("Competitive Shared")
	var goal: Dictionary = state.get("goal", {})
	var target := tr("Endless game") if goal.get("kind", "endless") == "endless" else "%s: %s" % [tr("Population") if goal.kind == "population" else tr("Net wealth"), MultiplayerGoalHud.number(int(goal.target), goal.kind)]
	if goal.get("kind") == "timed_score":
		target = tr("Points after game time") + " · " + tr("%d game years · End year %d") % [int(goal.duration_days) / CityCalendar.DAYS_PER_YEAR, int(goal.end_year)]
	summary.text = "%s · %s\n%s" % [mode, target, tr("Simulation and construction begin together after the host starts.")]
	if goal.get("kind") == "timed_score":
		summary.text += "\n" + MultiplayerGoal.score_help()
	elif state.get("mode", "coop") != "coop" and goal.get("kind", "endless") != "endless":
		summary.text += "\n" + (tr("Accumulate %d years as sole leader. Earned time is kept. Late cities are unranked.") % (int(goal.get("hold_days", 3000)) / CityCalendar.DAYS_PER_YEAR) if goal.get("rule") == "leadership" else tr("Stay at or above the target for one full game year. Dropping below resets the timer."))
	var signature := TranslationServer.get_locale() + JSON.stringify(state.get("start_preview", {})) + JSON.stringify(state.get("roster", []).map(func(player: Dictionary) -> Array: return [player.id, player.name, player.city, player.online, player.get("ready", false), player.color, player.get("handicap", {})]))
	if signature != roster_signature and not editing_city():
		roster_signature = signature
		roster.clear()
		var root := roster.create_item()
		for player: Dictionary in state.get("roster", []):
			var row := roster.create_item(root)
			row.set_text(0, player.name)
			row.set_custom_color(0, Color.from_string(player.color, Color.WHITE))
			row.set_text(1, player.city)
			row.set_metadata(0, player.id)
			row.set_text(3, MultiplayerScoreboard.money(player.get("handicap", {}).get("funds", player.funds)))
			row.set_text(4, str(player.get("handicap", {}).get("tiles", 0)) if int(player.get("handicap", {}).get("tiles", 0)) > 0 else tr("Automatic"))
			var area: Dictionary = state.get("start_preview", {}).get(player.id, {})
			if not area.is_empty() and state.get("mode") == "shared":
				row.set_text(4, tr("%d land · %d water") % [area.land, area.water])
			row.set_text(2, tr("Offline") if not player.online else tr("Ready") if player.get("ready", false) else tr("Not ready"))
			row.set_custom_color(2, Color("66cf79") if player.get("ready", false) and player.online else Color("ff9c40"))
			for column in 5:
				row.set_tooltip_text(column, row.get_text(column))
			if player.id == session.token.sha256_text():
				own_ready = player.get("ready", false)
				row.set_editable(1, true)
				mark_editable(row, 1, tr("Click your city name to rename it before the game starts."))
			if session.hosting and state.get("mode") != "coop":
				mark_editable(row, 3, tr("Change starting funds"))
				if state.get("mode") == "shared":
					mark_editable(row, 4, tr("Change starting territory"))
	ready.text = tr("Not ready") if own_ready else tr("Ready")
	start.visible = session.hosting
	start.disabled = not lobby.get("can_start", false)
	roster.custom_minimum_size.y = maxi(80, roster.get_root().get_child_count() * 28 + 32)
	if window.visible:
		windows.fit_content.call_deferred(window, body, 760)
	if not window.visible:
		show_if_waiting.call_deferred()

func mark_editable(row: TreeItem, column: int, tip: String) -> void:
	row.set_metadata(column, true)
	row.set_custom_bg_color(column, Color(0.5, 0.65, 0.75, 0.12))
	row.set_tooltip_text(column, tip)
	row.add_button(column, EDIT_ICON, column, false, tip)


func draw_edit_hover() -> void:
	var point := roster.get_local_mouse_position()
	var row := roster.get_item_at_position(point)
	var column := roster.get_column_at_position(point)
	if row == null or column < 0:
		return
	var editable: Variant = row.get_metadata(column)
	if not editable is bool or not editable:
		return
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.5, 0.65, 0.75, 0.08)
	style.border_color = Color(0.6, 0.75, 0.85, 0.65)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	roster.draw_style_box(style, roster.get_item_area_rect(row, column).grow(-1))


func show_if_waiting() -> void:
	if waiting and windows.coop.active():
		roster.custom_minimum_size.y = maxi(80, roster.get_root().get_child_count() * 28 + 32)
		window.popup_centered()
		windows.fit_content.call_deferred(window, body, 760)


func editing_city() -> bool:
	# Tree's built-in text editor is an internal popup, not a public is_editing API.
	for child in roster.get_children(true):
		if child is Window and child.visible:
			return true
	return false


func edit_handicap(seat: String) -> void:
	if is_instance_valid(handicap_dialog) and handicap_dialog.visible:
		return
	var dialog := windows.make_window("Starting handicap")
	handicap_dialog = dialog
	var box := windows.content(dialog)
	var player: Dictionary = {}
	for entry: Dictionary in windows.players:
		if entry.id == seat:
			player = entry
	if player.is_empty():
		dialog.queue_free()
		return
	ApplicationMultiplayer.label(box, str(player.name) + " · " + str(player.city))
	ApplicationMultiplayer.label(box, "Starting funds")
	var funds := LineEdit.new()
	funds.text = MultiplayerScoreboard.money(int(player.get("handicap", {}).get("funds", player.funds)))
	var money_row := HBoxContainer.new()
	box.add_child(money_row)
	funds.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	money_row.add_child(funds)
	var money_value := func() -> int:
		var number := funds.text.replace("$", "").replace(".", "").replace(",", "").replace(" ", "")
		return clampi(number.to_int(), 0, 2147483647) if number.is_valid_int() else int(player.get("handicap", {}).get("funds", player.funds))
	for delta in [-1000, 1000]:
		var step := ApplicationMultiplayer.button(money_row, "−" if delta < 0 else "+", func() -> void: funds.text = MultiplayerScoreboard.money(clampi(money_value.call() + delta, 0, 2147483647)))
		step.tooltip_text = MultiplayerScoreboard.money(delta)
	funds.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and event.keycode in [KEY_UP, KEY_DOWN]:
			funds.text = MultiplayerScoreboard.money(clampi(money_value.call() + (1000 if event.keycode == KEY_UP else -1000), 0, 2147483647))
			funds.accept_event())
	funds.focus_exited.connect(func() -> void: funds.text = MultiplayerScoreboard.money(money_value.call()))
	ApplicationMultiplayer.label(box, "Starting territory")
	var size_choice := OptionButton.new()
	for name in ["Very small", "Small", "Medium · standard", "Large", "Generous", "Custom…"]:
		size_choice.add_item(tr(name))
	var scales := [50, 75, 100, 125, 150]
	var saved: Dictionary = player.get("handicap", {})
	size_choice.select(5 if int(saved.get("tiles", 0)) > 0 else maxi(0, scales.find(int(saved.get("scale", 100)))))
	size_choice.disabled = windows.state.get("mode") != "shared"
	box.add_child(size_choice)
	var tiles := SpinBox.new()
	tiles.min_value = 1
	tiles.max_value = windows.coop.app.document_state.city.map_size ** 2 / 32
	tiles.value = maxi(1, int(saved.get("tiles", 0)))
	box.add_child(tiles)
	var explanation := ApplicationMultiplayer.label(box, "")
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var refresh := func() -> void:
		tiles.visible = size_choice.selected == 5 and not size_choice.disabled
		var count := int(tiles.value) if tiles.visible else roundi(MultiplayerStartParcel.standard(windows.coop.app.document_state.city.map_size) * scales[mini(4, size_choice.selected)] / 100.0)
		explanation.text = tr("Free starting territory: %d land equivalents. Two water tiles count as one land tile. Treasury unchanged.") % count
		if size_choice.disabled:
			explanation.text = tr("Each Region player has a separate city map.")
		elif windows.coop.session.hosting:
			var session := windows.coop.session
			var actor := session.seats.find_seat(seat)
			var original := session.starts.handicaps.duplicate(true)
			var original_preview := session.starts.preview.duplicate(true)
			session.starts.handicaps[actor] = {"funds": money_value.call(), "tiles": count, "scale": 100}
			var error := session.starts.prepare(session.world, session.members, false)
			var area: Dictionary = session.starts.preview.get(seat, {})
			session.starts.handicaps = original
			session.starts.preview = original_preview
			if not error.is_empty():
				explanation.text = MultiplayerText.message(error)
			elif not area.is_empty():
				explanation.text += "\n" + tr("%d land · %d water · %d reserved tiles") % [area.land, area.water, area.reserved]
	size_choice.item_selected.connect(func(_index: int) -> void: refresh.call())
	tiles.value_changed.connect(func(_value: float) -> void: refresh.call())
	refresh.call()
	ApplicationMultiplayer.button(box, "Apply", func() -> void:
		windows.coop.session.request({"kind": "handicap", "seat": seat, "funds": money_value.call(), "tiles": int(tiles.value) if size_choice.selected == 5 else 0, "scale": scales[mini(4, size_choice.selected)]})
		dialog.queue_free())
	dialog.popup_centered()
