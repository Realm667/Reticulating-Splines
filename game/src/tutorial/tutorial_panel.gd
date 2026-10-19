class_name TutorialPanel
extends PanelContainer
## Docked, scrollable learning UI. It never blocks the whole city.

var controller: TutorialController
var page := "home"
var collapsed := false
var left_side := false
var target := Vector2i(-1, -1)
var target_building := -1
var target_rotation := 0
var _column: VBoxContainer
var _body: VBoxContainer
var _scroll: ScrollContainer
var _status: Label
var _heading: Label
var _marker: Control
var _last_layout := ""
var _suppressed := false
var _restore_visible := false


func _init(owner_controller: TutorialController) -> void:
	controller = owner_controller


func _ready() -> void:
	theme_type_variation = "FloatingPanel"
	_column = VBoxContainer.new()
	add_child(_column)
	var header := HFlowContainer.new()
	_column.add_child(header)
	_heading = Label.new()
	_heading.text = "Learning & city adviser"
	header.add_child(_heading)
	_button(header, "Collapse", func():
		collapsed = not collapsed
		_last_layout = ""
		_scroll.visible = not collapsed)
	_button(header, "Move panel", func():
		left_side = not left_side
		_last_layout = "")
	_button(header, "Close", hide)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_column.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_body)
	_marker = Control.new()
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	controller.app.map_view.add_child(_marker)
	_marker.draw.connect(_draw_target)
	visibility_changed.connect(func():
		_last_layout = ""
		controller.app.city_workspace._sync_camera_rect.call_deferred())
	item_rect_changed.connect(controller.app.city_workspace._sync_camera_rect.call_deferred)
	hide()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		var was_visible := visible
		show_page(page, false)
		visible = was_visible


func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = _wrap(tr(text))
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _wrap(value: String) -> String:
	var font := get_theme_font("font", "Button")
	var font_size := get_theme_font_size("font_size", "Button")
	var line := ""
	var result := ""
	for character in value:
		if character == "\n":
			result += line + "\n"
			line = ""
			continue
		if font.get_string_size(line + character, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > 285:
			var space := line.rfind(" ")
			if space > 0:
				result += line.substr(0, space) + "\n"
				line = line.substr(space + 1)
			else:
				result += line + "\n"
				line = ""
		line += character
	return result + line


func _text(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(label)
	return label


func _row() -> HFlowContainer:
	var row := HFlowContainer.new()
	_body.add_child(row)
	return row


func show_page(value: String, focus := true) -> void:
	page = value
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	_status = null
	collapsed = false
	_scroll.show()
	show()
	_last_layout = ""
	var navigation := _row()
	for entry in [["Start", "home"], ["Lesson", "task"], ["Learning journal", "journal"], ["Reference", "reference"], ["City adviser", "advisor"]]:
		_button(navigation, entry[0], show_page.bind(entry[1]))
	match page:
		"invitation":
			_text(tr("Would you like to learn how to build a city? You can return through Help at any time."))
			_button(_body, "Learn to play", show_page.bind("home"))
			_button(_body, "Not now", hide)
		"home":
			_home()
		"task":
			_task()
		"journal":
			_journal()
		"reference":
			_reference()
		"advisor":
			_advisor()
	_scroll.scroll_vertical = 0
	if focus:
		_focus_first.call_deferred()


func _focus_first() -> void:
	if not is_inside_tree() or not is_visible_in_tree():
		return
	var buttons := _body.find_children("*", "Button", true, false)
	if not buttons.is_empty():
		buttons[0].grab_focus()


func _home() -> void:
	_text(tr("Learn by building a separate practice city, or use the adviser in your current city. No hidden money or faster growth."))
	_button(_body, "Start the guided course", controller.request_training.bind(0))
	_button(_body, "Quick start: first settlement", controller.request_training.bind(1))
	_button(_body, "Use the current city", controller.choose_lesson.bind("a1")).disabled = not controller.available()
	if not controller.lesson.is_empty():
		_button(_body, "Continue lesson", show_page.bind("task"))
	_text(tr("Advanced practice chapters"))
	for chapter in range(6, TutorialCatalog.CHAPTERS.size()):
		_button(_body, str(TutorialCatalog.CHAPTERS[chapter]), controller.request_training.bind(chapter))
	if not controller.available():
		_text(tr("Learning is available in single-player cities."))


func _task() -> void:
	var lesson := controller.lesson
	if lesson.is_empty():
		_text(tr("Choose a lesson in the journal or start a practice city."))
		return
	_text(tr(TutorialCatalog.CHAPTERS[int(lesson.chapter)]))
	_text(tr(str(lesson.title)))
	_status = _text(controller.status())
	for id: String in lesson.requires:
		var prerequisite := TutorialCatalog.lesson(id)
		var state: String = controller.progress.record.get("states", {}).get(id, "open")
		if state != "done":
			_button(_body, tr("Foundation: %s") % tr(str(prerequisite.title)), controller.choose_lesson.bind(id))
	var paragraphs: Array = TutorialCatalog.ARTICLES[str(lesson.article)]
	for index in mini(controller.hint + 1, paragraphs.size()):
		_text(tr(str(paragraphs[index])))
	if controller.available() and str(lesson.article) == "controls":
		for action_id in ["camera_up", "camera_down", "camera_left", "camera_right", "zoom_in", "zoom_out", "rotate_clockwise", "speed_pause", "speed_turtle"]:
			var action := ControlActions.find(action_id)
			if action != null:
				var bindings := PackedStringArray()
				for binding in controller.app.controls.bindings().for_action(action_id):
					bindings.append(binding.display_text())
				if not bindings.is_empty():
					_text(tr(action.label) + ": " + ", ".join(bindings))
	if controller.available() and str(lesson.rule) in ["powered", "watered", "repair_power", "repair_water"]:
		var water := str(lesson.rule) in ["watered", "repair_water"]
		var values := controller.facts.values
		for check in [["Residential target", int(values.get("residential", 0)) > 0],
			["Water source" if water else "Power source", int(values.get("pump" if water else "power", 0)) > 0],
			["Confirmed supply", controller.goal_ready]]:
			_text((tr("Completed") if check[1] else tr("Open")) + " · " + tr(check[0]))
	var hint_row := _row()
	_button(hint_row, "Next hint", func():
		controller.hint = mini(controller.hint + 1, 2)
		refresh_task())
	_button(hint_row, "Show tool", controller.show_tool)
	_button(hint_row, "Show location", controller.show_place)
	_button(hint_row, "More information", func():
		controller.selected_article = str(lesson.article)
		show_page("reference"))
	var rule := str(lesson.rule)
	if controller.available() and rule in ["quiz:demand", "expand"]:
		var demand := controller.city.rci_demand()
		for index in 3:
			_text(tr(["Residential", "Commercial", "Industrial"][index]) + ": " + str(demand[index]))
	if rule.begins_with("quiz:") or rule == "budget":
		var key := rule.trim_prefix("quiz:") if rule != "budget" else "forecast"
		_text(tr(str(TutorialCatalog.QUESTIONS[key][0])))
		var answers := _row()
		_button(answers, "Yes", controller.answer.bind(key, true))
		_button(answers, "No", controller.answer.bind(key, false))
	if str(lesson.article) in ["budget", "bonds"]:
		_button(_body, "Open Budget", controller.app.budget.open_manual_budget)
	if rule == "save":
		_button(_body, "Save City As", controller.app.city_files.open_save_dialog)
	if rule == "advisor":
		_button(_body, "Choose adviser preferences", show_page.bind("advisor"))
	if rule == "settings":
		_button(_body, "Settings", controller.app.settings.open_settings_dialog)
	if rule == "photo":
		_button(_body, "Photo mode", controller.app.photo_mode.open)
	if rule in ["repair_power", "repair_water", "disaster_start", "late"]:
		_button(_body, "Start this practice chapter", controller.request_training.bind(int(lesson.chapter)))
	if rule == "finish":
		_button(_body, "I am ready to build independently", func():
			controller.mark("finish")
			controller.goal_ready = true
			refresh_task())
	if controller.available() and controller.app.simulation_state.speed_controller.speed == GameSpeedController.Speed.PAUSED:
		_button(_body, "Resume at Turtle speed", controller.app.frame.select_speed.bind(GameSpeedController.Speed.TURTLE))
	var actions := _row()
	_button(actions, "Continue", controller.advance).disabled = not controller.goal_ready
	_button(actions, "Later", controller.advance.bind("later"))
	_button(actions, "Skip", controller.advance.bind("skipped"))
	_button(actions, "End tutorial", controller.end_course)
	var checkpoint: String = controller.progress.record.get("checkpoints", {}).get(str(lesson.chapter), "")
	if not checkpoint.is_empty() and FileAccess.file_exists(checkpoint):
		_button(_body, "Return to chapter start", controller.request_training.bind(int(lesson.chapter), checkpoint))


func refresh_task() -> void:
	if page == "task" and visible:
		var scroll := _scroll.scroll_vertical
		var was_collapsed := collapsed
		show_page("task", false)
		collapsed = was_collapsed
		_scroll.visible = not collapsed
		_scroll.set_deferred("scroll_vertical", scroll)


func update_status(value: String) -> void:
	if is_instance_valid(_status):
		_status.text = value


func _journal() -> void:
	var states: Dictionary = controller.progress.record.get("states", {})
	var chapter := -1
	for entry in TutorialCatalog.LESSONS:
		if int(entry.chapter) != chapter:
			chapter = int(entry.chapter)
			_text(tr(TutorialCatalog.CHAPTERS[chapter]))
			_button(_body, "Start this practice chapter", controller.request_training.bind(chapter)).disabled = controller.app.coop.active()
		var state: String = states.get(entry.id, "open")
		var label: String = {"done": tr("Completed"), "skipped": tr("Skipped"), "later": tr("Later"), "open": tr("Open")}.get(state, tr("Open"))
		_text("%s · %s" % [label, tr(str(entry.title))])
		_button(_body, "Review lesson", controller.choose_lesson.bind(str(entry.id))).disabled = not controller.available()


func _reference() -> void:
	var chooser := OptionButton.new()
	_body.add_child(chooser)
	var keys := TutorialCatalog.ARTICLES.keys()
	for key: String in keys:
		chooser.add_item(tr(_article_title(key)))
	chooser.select(maxi(0, keys.find(controller.selected_article)))
	chooser.item_selected.connect(func(index: int):
		controller.selected_article = keys[index]
		show_page("reference"))
	for paragraph: String in TutorialCatalog.ARTICLES[controller.selected_article]:
		_text(tr(paragraph))
	if controller.selected_article == "controls":
		_button(_body, "Settings", controller.app.settings.open_settings_dialog)


func _article_title(key: String) -> String:
	return {"controls": "Orientation", "query": "Query", "settlement": "Your first settlement",
		"power": "Power", "water": "Water", "growth": "Growth", "budget": "Budget", "bonds": "Bonds",
		"saving": "Saving", "adviser": "City adviser", "transport": "Transport", "services": "City services",
		"environment": "Environment", "disaster": "Disaster practice", "late": "Late development", "rs": "Reticulating Splines"}[key]


func _advisor() -> void:
	var choices := OptionButton.new()
	for label in ["Off", "Important only", "All hints"]:
		choices.add_item(tr(label))
	choices.select(int(controller.progress.data.advisor))
	_body.add_child(choices)
	choices.item_selected.connect(controller.set_advisor)
	_text(tr("Advice reads the current city. It never changes buildings, money or speed."))
	if not controller.available():
		_text(tr("Learning is available in single-player cities."))
		return
	var count := 0
	for key: String in controller.advice:
		if key in controller.dismissed or key in controller.progress.data.hidden:
			continue
		_text(tr(_article_title(key)))
		var values := controller.facts.values
		match key:
			"power":
				_text(tr("Homes without power: %d") % int(values.get("unpowered_homes", 0)))
			"water":
				_text(tr("Homes without water: %d") % int(values.get("dry_homes", 0)))
			"budget":
				_text(tr("Projected annual balance: %s") % BudgetReport.currency(BudgetReport.capture(controller.city, BudgetPhase.funding_values(controller.city)).estimated_cash))
			"growth":
				_text(tr("Unbuilt zone tiles: %d") % int(values.get("empty_zone", 0)))
		_text(tr(str(TutorialCatalog.ARTICLES[key][0])))
		var row := _row()
		_button(row, "Show relevant view", controller.open_advice.bind(key))
		_button(row, "More information", func():
			controller.selected_article = key
			show_page("reference"))
		_button(row, "Dismiss for this session", func():
			controller.dismissed.append(key)
			show_page("advisor"))
		_button(row, "Hide this topic", func():
			controller.progress.data.hidden.append(key)
			controller._store()
			show_page("advisor"))
		count += 1
		if count == 3:
			break
	if count == 0:
		_text(tr("No confirmed advice to show. Simulation-dependent checks may still be pending."))
	_button(_body, "Restore hidden topics", func():
		controller.progress.data.hidden = []
		controller.dismissed.clear()
		controller._store()
		show_page("advisor"))


func sync_layout() -> void:
	var app := controller.app
	var obscured := (app.photo_mode != null and app.photo_mode.active) or app.coop.active()
	if obscured:
		if not _suppressed:
			_restore_visible = visible
			_suppressed = true
		hide()
		_marker.hide()
		return
	if _suppressed:
		_suppressed = false
		visible = _restore_visible
	_marker.visible = visible and target.x >= 0
	if _marker.visible:
		_marker.queue_redraw()
	var viewport := app.get_viewport_rect().size
	var menu := app.main_menu.visible or controller.city == null
	z_index = 860 if menu else 0
	var narrow := viewport.x < 1100 or collapsed
	var layout := "%s:%s:%s:%s:%s" % [menu, narrow, collapsed, left_side, viewport]
	if layout == _last_layout:
		return
	_last_layout = layout
	if collapsed and not controller.lesson.is_empty():
		var completed: int = controller.progress.record.get("states", {}).values().count("done")
		_heading.text = _wrap(tr(str(controller.lesson.title)) + " · %d/%d" % [completed, TutorialCatalog.LESSONS.size()])
	else:
		_heading.text = tr("Learning & city adviser")
	var destination: Node = app if menu else app.city_workspace.get_node("Page" if narrow else "Page/Content")
	if get_parent() != destination:
		reparent(destination)
	custom_minimum_size = Vector2.ZERO
	size_flags_horizontal = Control.SIZE_FILL
	size_flags_vertical = Control.SIZE_FILL
	if menu:
		set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		size = Vector2(minf(600, viewport.x - 32), minf(650, viewport.y - 32))
		position = (viewport - size) * 0.5
	elif narrow:
		destination.move_child(self, maxi(0, destination.get_child_count() - 2))
		custom_minimum_size.y = 48 if collapsed else minf(230, viewport.y * 0.45)
	else:
		destination.move_child(self, 0 if left_side else destination.get_child_count() - 1)
		custom_minimum_size.x = 340
		size_flags_vertical = Control.SIZE_EXPAND_FILL
	app.city_workspace._sync_camera_rect.call_deferred()


func rotate_target(counter_clockwise: bool) -> void:
	if target.x < 0 or controller.city == null:
		return
	target = CityRotationCommand.rotate_point(target, controller.city.map_size, counter_clockwise)
	target_rotation = controller.city.compass_rotation()


func _draw_target() -> void:
	var app := controller.app
	if not visible or controller.city == null or target.x < 0:
		return
	if controller.city.compass_rotation() != target_rotation or controller.city.building_id(target.x, target.y) != target_building:
		target = Vector2i(-1, -1)
		return
	var polygon := CityIsometricRenderer.tile_polygon(app.map_view.city, target.x, target.y)
	var scale := app.map_view.camera._view_scale()
	var offset := app.map_view.camera._draw_offset(scale)
	for index in polygon.size():
		polygon[index] = polygon[index] * scale + offset
	if polygon.size() == 4:
		if not app.map_view.camera_view_rect.has_point((polygon[0] + polygon[2]) * 0.5):
			return
		polygon.append(polygon[0])
		_marker.draw_polyline(polygon, Color.WHITE, 3.0)
