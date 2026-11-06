class_name MultiplayerGoalHud
extends RefCounted
## Per-city target and leadership progress; presentation only.
@warning_ignore_start("integer_division")

var panel: PanelContainer
var title: Label
var owner_ref: WeakRef
var home: Button
var visit_frame: Panel
var rows: VBoxContainer
var signature := ""
var timer: Label
var row_controls: Dictionary = {}
var row_order: Array = []
var regional_rows := false

func _init(windows: MultiplayerWindows) -> void:
	owner_ref = weakref(windows)
	panel = PanelContainer.new()
	panel.z_index = 2
	panel.theme = AppUiTheme.current()
	windows.coop.app.map_view.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	var body := VBoxContainer.new()
	panel.add_child(body)
	var heading := HBoxContainer.new()
	body.add_child(heading)
	var goal_icon := TextureRect.new()
	goal_icon.texture = preload("res://src/multiplayer/icons/goal.svg")
	goal_icon.custom_minimum_size = Vector2(20, 20)
	goal_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	goal_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	heading.add_child(goal_icon)
	title = ApplicationMultiplayer.label(heading, "")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.custom_minimum_size.x = 0
	var stats := ApplicationMultiplayer.button(heading, "Statistics", windows.open_scoreboard)
	stats.icon = preload("res://src/multiplayer/icons/statistics.svg")
	stats.add_theme_constant_override("icon_max_width", 18)
	for icon_state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
		stats.add_theme_color_override(icon_state, Color.WHITE)
	stats.tooltip_text = tr("Open scoreboard")
	home = ApplicationMultiplayer.button(windows.coop.app.map_view, "Return to your city", func() -> void:
		windows.coop.session.request({"kind": "view_city", "seat": windows.coop.session.token.sha256_text()}))
	home.z_index = 3
	home.hide()
	visit_frame = Panel.new()
	visit_frame.z_index = 1
	visit_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	windows.coop.app.map_view.add_child(visit_frame)
	var glow := StyleBoxFlat.new()
	glow.bg_color = Color.TRANSPARENT
	glow.border_color = Color(0.4, 0.75, 1.0, 0.55)
	glow.set_border_width_all(2)
	glow.shadow_color = Color(0.3, 0.7, 1.0, 0.22)
	glow.shadow_size = 6
	visit_frame.add_theme_stylebox_override("panel", glow)
	visit_frame.hide()
	timer = ApplicationMultiplayer.label(body, "")
	timer.hide()
	title.clip_text = true
	rows = VBoxContainer.new()
	rows.add_theme_constant_override("separation", 3)
	body.add_child(rows)
	panel.hide()

func layout(view: Rect2) -> void:
	panel.size = Vector2(minf(420, maxf(0, view.size.x - 16)), panel.get_combined_minimum_size().y)
	panel.position = Vector2(view.end.x - panel.size.x - 8, view.position.y + 8)
	visit_frame.position = view.position + Vector2(3, 3)
	visit_frame.size = view.size - Vector2(6, 6)
	home.size = home.get_combined_minimum_size()
	home.position = view.end - home.size - Vector2(12, 12)

static func value(player: Dictionary, kind: String) -> int:
	if kind == "timed_score":
		return int(player.get("points", MultiplayerGoal.score_units(int(player.get("population", 0)), int(player.get("funds", 0)) - int(player.get("debt", 0)))))
	return int(player.get("population", 0)) if kind == "population" else int(player.get("funds", 0)) - int(player.get("debt", 0))

func update(state: Dictionary, _actor: String) -> void:
	home.visible = state.get("visiting", false)
	visit_frame.visible = home.visible
	panel.visible = state.get("mode") in ["shared", "region"] and not state.get("lobby", {}).get("waiting", false)
	if not panel.visible:
		return
	var goal: Dictionary = state.get("goal", {})
	var kind: String = goal.get("kind", "endless")
	var endless: bool = kind == "endless" or goal.get("unscored", false)
	var visible_players: Array = []
	for player: Dictionary in state.get("roster", []):
		visible_players.append([player.id, player.name, player.get("city"), player.get("color"), player.get("ranked", true), value(player, kind)])
	var key := JSON.stringify([goal, visible_players, state.get("mode"), state.get("view_owner"), TranslationServer.get_locale()])
	if key == signature:
		return
	signature = key
	title.text = tr("Endless game · no scoring") if goal.get("unscored", false) else tr("Endless game") if endless else "%s · %s" % [tr("Population") if kind == "population" else tr("Net wealth"), number(int(goal.get("target", 1)), kind)]
	var timed := kind == "timed_score" and not endless
	if timed:
		title.text = tr("Points after game time")
	title.text = tr("Game goal") + ": " + title.text
	timer.visible = timed
	if timed:
		var remaining := maxi(0, int(goal.get("duration_days", 0)) - int(goal.get("elapsed_days", 0)))
		timer.text = tr("End year %d · %d years, %d days remaining") % [int(goal.get("end_year", 0)), remaining / CityCalendar.DAYS_PER_YEAR, remaining % CityCalendar.DAYS_PER_YEAR]
		timer.tooltip_text = MultiplayerGoal.score_help()
	title.tooltip_text = title.text
	var regional: bool = state.get("mode") == "region"
	var order: Array = []
	if not endless or regional:
		for player: Dictionary in state.get("roster", []):
			order.append(player.id)
	if order != row_order or regional != regional_rows:
		for child in rows.get_children():
			rows.remove_child(child)
			child.queue_free()
		row_controls.clear()
		row_order = order
		regional_rows = regional
		for id: String in order:
			row_controls[id] = create_row(id, regional)
	if endless and state.get("mode") != "region":
		panel.tooltip_text = title.text
		return
	var target := maxi(1, int(goal.get("target", 1)))
	if timed:
		target = 1
		for player: Dictionary in state.get("roster", []):
			if player.get("ranked", true):
				target = maxi(target, value(player, kind))
	var required := maxi(1, int(goal.get("hold_days", 300)))
	for player: Dictionary in state.get("roster", []):
		var current := value(player, kind)
		var ranked: bool = player.get("ranked", true)
		var days := mini(required, int(goal.get("holding", {}).get(player.id, {}).get("days", 0)))
		var color := Color.from_string(player.get("color", "46b4ff"), Color.WHITE) if ranked else Color(0.5, 0.5, 0.5)
		var controls: Dictionary = row_controls[player.id]
		var row: Control = controls.row
		var text: Label = controls.text
		var amount: Label = controls.amount
		var progress: ProgressBar = controls.progress
		var leadership: ProgressBar = controls.leadership
		progress.value = 0.0 if endless else clampf(float(current) / target, 0, 1) * 100.0
		progress.get_theme_stylebox("fill").bg_color = Color(color, 0.6)
		leadership.visible = not endless and not timed and ranked and (current >= target or days > 0)
		leadership.value = float(days) / required * 100.0
		leadership.get_theme_stylebox("fill").bg_color = Color(color, 1.0)
		if regional:
			var visit: Button = controls.visit
			visit.tooltip_text = tr("Visit city") + ": " + str(player.city)
			visit.disabled = player.id == state.get("view_owner")
		text.text = str(player.name)
		amount.text = "%s / %s" % [number(current, kind), number(target, kind)]
		if days > 0 and goal.get("rule", "continuous") == "leadership":
			amount.text = tr("Leadership: %s / %d years") % [String.num(float(days) / CityCalendar.DAYS_PER_YEAR, 1).replace(".", ",") if TranslationServer.get_locale().begins_with("de") else String.num(float(days) / CityCalendar.DAYS_PER_YEAR, 1), required / CityCalendar.DAYS_PER_YEAR]
		elif days > 0:
			amount.text = tr("Target held: %d / %d game days") % [days, required]
		if timed:
			amount.text = tr("%s points") % MultiplayerGoal.points(current)
		if not ranked:
			amount.text = tr("Unranked")
		amount.visible = not endless
		text.offset_right = -6 if endless else -maxf(6, amount.get_minimum_size().x + 12)

		if endless:
			text.text = player.name
		text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var status := tr("Below target") if current < target else tr("Tied lead") if goal.get("tied", false) else tr("Leading") if goal.get("leader", "") == player.id else tr("Overtaken")
		if goal.get("rule", "continuous") == "continuous":
			status = tr("Below target") if current < target else tr("Target reached")
		row.tooltip_text = status + "\n" + "%s: %s / %s\n%s" % [player.name, number(current, kind), number(target, kind), (tr("Leadership: %d / %d game days") if goal.get("rule", "continuous") == "leadership" else tr("Target held: %d / %d game days")) % [days, required] if ranked else tr("Unranked · city founded after the start")]
		if timed:
			row.tooltip_text = str(player.name) + ": " + tr("%s points") % MultiplayerGoal.points(current) + "\n" + tr("Bar relative to the leading positive score.")
		elif endless:
			row.tooltip_text = str(player.name) + " · " + str(player.get("city", ""))
	if endless:
		panel.tooltip_text = title.text
		return
	if timed:
		panel.tooltip_text = MultiplayerGoal.score_help()
		return
	if goal.get("rule", "continuous") == "continuous":
		panel.tooltip_text = tr("Stay at or above the target for one full game year. Dropping below resets the timer.")
		return
	panel.tooltip_text = tr("Reach the target and accumulate %d years as sole leader. Earned time is kept.") % (required / CityCalendar.DAYS_PER_YEAR)


func create_row(id: String, regional: bool) -> Dictionary:
	var line := HBoxContainer.new()
	rows.add_child(line)
	var row := Control.new()
	row.custom_minimum_size.y = 20
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(row)
	var controls := {"row": row}
	if regional:
		var windows: MultiplayerWindows = owner_ref.get_ref()
		var visit := ApplicationMultiplayer.button(line, "", func() -> void:
			windows.coop.session.request({"kind": "view_city", "seat": id}))
		visit.icon = preload("res://src/multiplayer/icons/visit.svg")
		visit.add_theme_constant_override("icon_max_width", 16)
		for style_name in ["normal", "hover", "pressed", "disabled"]:
			var compact := visit.get_theme_stylebox(style_name).duplicate()
			compact.content_margin_top = 0
			compact.content_margin_bottom = 0
			visit.add_theme_stylebox_override(style_name, compact)
		controls.visit = visit
	controls.progress = bar(row, Color.WHITE, 0.0)
	controls.leadership = bar(row, Color.WHITE, 0.0, true)
	for key: String in ["amount", "text"]:
		var label := Label.new()
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		label.offset_right = -6
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_constant_override("outline_size", 0)
		label.add_theme_color_override("font_color", Color.WHITE)
		label.add_theme_font_size_override("font_size", 14)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if key == "amount":
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		else:
			label.offset_left = 6
			label.clip_text = true
		row.add_child(label)
		controls[key] = label
	return controls


static func bar(parent: Control, color: Color, fraction: float, transparent := false) -> ProgressBar:
	var result := ProgressBar.new()
	result.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result.show_percentage = false
	result.value = fraction * 100
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(4)
	result.add_theme_stylebox_override("fill", fill)
	var background := StyleBoxFlat.new()
	background.set_corner_radius_all(4)
	background.bg_color = Color.TRANSPARENT if transparent else Color(0.08, 0.1, 0.12, 0.9)
	result.add_theme_stylebox_override("background", background)
	parent.add_child(result)
	return result

static func number(amount: int, kind: String) -> String:
	return MultiplayerGoal.points(amount) if kind == "timed_score" else MultiplayerScoreboard.money(amount) if kind == "wealth" else MultiplayerScoreboard.number(amount)
