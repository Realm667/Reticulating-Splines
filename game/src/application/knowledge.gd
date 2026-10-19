class_name ApplicationKnowledge
extends Node
## Local presentation only. Never changes city bytes, speed or random state.

var app: CityApplication
var rules := KnowledgeRules.new()
var card: KnowledgeCard
var window: KnowledgeWindow
var start_card: KnowledgeCard
var mode := 2
var top := false
var pending_start := false
var city: CityState
var layout_elapsed := 0.0
var poll_elapsed := 0.0
var stamp: Array = []
var loading_card: KnowledgeCard
var load_index := 18
var suspended_card := false
var growth_dialog: KnowledgeGrowthDialog
var introduction_shown := false
var host_view := ""
var host_revision := -1
var host_disaster := 0


func _init(application: CityApplication) -> void:
	app = application


func _ready() -> void:
	var config := ConfigFile.new()
	if config.load(_path()) == OK:
		mode = clampi(int(config.get_value("tips", "mode", 2)), 0, 2)
		top = bool(config.get_value("tips", "top", false))
		rules.muted = PackedStringArray(config.get_value("tips", "muted", PackedStringArray()))
	var layer := CanvasLayer.new()
	layer.layer = 70
	add_child(layer)
	card = _card(layer)
	card.contextual = true
	card.visibility_changed.connect(func() -> void:
		if card.visible:
			_layout.call_deferred())
	card.hide()
	window = KnowledgeWindow.new()
	app.add_child(window)
	window.action_requested.connect(_action)
	window.mute_requested.connect(_mute)
	window.preferences_changed.connect(_preferences)
	window.reset_requested.connect(func() -> void:
		rules.muted.clear()
		_save())
	window.tips_mode.select(mode)
	window.position_choice.select(int(top))
	growth_dialog = KnowledgeGrowthDialog.new()
	app.add_child(growth_dialog)
	growth_dialog.action_requested.connect(_action)
	app.city_menu_bar.help_menu_requested.connect(func(id: int) -> void:
		if id == CityMenuBar.MENU_KNOWLEDGE:
			open())
	var query := app.city_dialogs.query_dialog
	query.growth_requested.connect(show_growth)
	app.main_overlays.busy_overlay.knowledge_requested = loading
	var settings_fields := app.main_overlays.settings_dialog.tabs.get_node("General/Fields")
	if settings_fields != null:
		var label := Label.new()
		label.text = "Tips & Knowledge"
		settings_fields.add_child(label)
		var button := Button.new()
		button.text = "Configure tips"
		button.pressed.connect(func() -> void:
			app.main_overlays.settings_dialog.hide()
			open())
		settings_fields.add_child(button)
	var new_dialog := app.city_dialogs.new_city_dialog
	start_card = _card(new_dialog.get_node("Center/NewCityDialog/Content/Body/Preview"))
	start_card.embedded = true
	start_card.visibility_changed.connect(func() -> void:
		new_dialog.preview_view.get_parent().custom_minimum_size.y = 160 if start_card.visible else 320)
	new_dialog.visibility_changed.connect(func() -> void:
		if new_dialog.visible:
			start_card.show_entry("bonds" if new_dialog.difficulty_input.selected == 2 else "start")
			start_card.visible = mode != 0 and not rules.muted.has(start_card.id)
			introduction_shown = start_card.visible
			start_card.action_button.hide()
			start_card.pin.hide())
	new_dialog.difficulty_input.item_selected.connect(func(index: int) -> void:
		if new_dialog.visible and mode != 0:
			start_card.show_entry("bonds" if index == 2 else "start")
			start_card.visible = not rules.muted.has(start_card.id)
			start_card.action_button.hide())


func _card(parent: Node) -> KnowledgeCard:
	var result := KnowledgeCard.new()
	parent.add_child(result)
	result.action_requested.connect(_action)
	result.mute_requested.connect(_mute)
	return result


func _mute(id: String) -> void:
	if not rules.muted.has(id):
		rules.muted.append(id)
	if card.id == id:
		card.hide()
		suspended_card = false
	_save()


func _path() -> String:
	return app.preferences.settings_path + ".knowledge.cfg"


func _save() -> void:
	var config := ConfigFile.new()
	config.set_value("tips", "mode", mode)
	config.set_value("tips", "top", top)
	config.set_value("tips", "muted", rules.muted)
	var error := config.save(_path())
	if error != OK:
		app.interface.show_error(tr("Cannot save tip preferences: %s") % error_string(error))


func _preferences(value: int, upper: bool) -> void:
	mode = value
	top = upper
	if mode < 2:
		card.hide()
		suspended_card = false
	if mode == 0:
		start_card.hide()
		if loading_card != null:
			loading_card.hide()
	_save()


func activated(loaded: bool) -> void:
	city = app.document_state.city
	rules.reset()
	stamp = []
	card.hide()
	window.hide()
	growth_dialog.hide()
	pending_start = not loaded and not introduction_shown and not app.coop.active()
	if not loaded and introduction_shown:
		rules.record(start_card.id)
	elif loaded and loading_card != null and loading_card.is_visible_in_tree():
		rules.record(loading_card.id)
	introduction_shown = false
	suspended_card = false
	host_revision = -1
	host_view = ""
	host_disaster = 0


func loading(parent: VBoxContainer) -> void:
	if loading_card == null:
		loading_card = _card(parent)
		loading_card.embedded = true
		loading_card.pin.hide()
		loading_card.action_button.hide()
		var next := Button.new()
		next.text = "Another tip"
		next.pressed.connect(func() -> void:
			load_index = (load_index + 1) % KnowledgeCatalog.ENTRIES.size()
			_show_loading_tip())
		loading_card.controls.add_child(next)
	_show_loading_tip()


func _show_loading_tip() -> void:
	var entry: Array = KnowledgeCatalog.ENTRIES[load_index]
	var initial_index := load_index
	# Loading knowledge must never claim a problem exists in the new city.
	while rules.muted.has(entry[0]):
		load_index = (load_index + 1) % KnowledgeCatalog.ENTRIES.size()
		if load_index == initial_index:
			loading_card.hide()
			return
		entry = KnowledgeCatalog.ENTRIES[load_index]
	loading_card.show_entry(entry[0])
	loading_card.action_button.hide()
	loading_card.visible = mode != 0 and not rules.muted.has(entry[0])


func observe(result: SimulationTickResult) -> void:
	if app.coop.active() or city == null or city != app.document_state.city:
		return
	var forecast: Variant = null
	for day in result.day_results:
		for phase: PhaseResult in day.phase_results.values():
			if day.ok and phase.ok and phase.complete and phase is BudgetPhase.Result:
				forecast = BudgetReport.capture(city, BudgetPhase.funding_values(city)).estimated_cash
	rules.observe(result, forecast)
	stamp = city.mirror_signature(PackedStringArray(["XBLD", "XZON", "XUND", "XBIT", "MISC"]))
	if card.id in ["power", "water", "vacant"] and not rules.streaks.has(card.id):
		card.hide()
		suspended_card = false


func invalidate_edits() -> void:
	if city == null or stamp.is_empty():
		return
	if city.mirror_signature(PackedStringArray(["XBLD", "XZON", "XUND", "XBIT", "MISC"])) != stamp:
		rules.candidates.clear()
		rules.streaks.clear()
		stamp = []
		card.hide()
		suspended_card = false


func observe_host(state: Dictionary) -> void:
	# Called only after the received display transaction is applied, never from a
	# network callback while an older city's tiles are still on screen.
	var view := str(state.get("view_owner", ""))
	if view != host_view:
		rules.reset()
		card.hide()
		growth_dialog.hide()
		host_view = view
		host_revision = -1
		host_disaster = 0
	var revision := int(state.get("revision", -1))
	if revision <= host_revision:
		return
	host_revision = revision
	var disaster := int(state.get("disaster", 0))
	if bool(state.get("visiting", false)):
		# Region summaries carry the player's own disaster, not the visited city.
		disaster = 0
		host_disaster = 0
	# Summaries contain a confirmed disaster state, but no complete power/water
	# phase results. Do not fabricate shortage diagnoses from usage percentages.
	if host_disaster > 0 and disaster == 0:
		rules.condition("recovery", true, 70, 1)
	host_disaster = disaster


func _process(delta: float) -> void:
	poll_elapsed += delta
	if poll_elapsed < 0.1:
		return
	delta = poll_elapsed
	poll_elapsed = 0.0
	if city != app.document_state.city:
		activated(true)
	var blocked := city == null or app.tool_state.landscape_editor or app.main_menu.visible
	blocked = blocked or app.city_dialogs.blocks_simulation() or app.main_overlays.blocks_simulation()
	blocked = blocked or (app.photo_mode != null and app.photo_mode.active) or window.visible
	for popup in app.get_viewport().get_embedded_subwindows():
		if popup.visible:
			blocked = true
			break
	if blocked:
		suspended_card = suspended_card or card.visible
		card.hide()
		return
	if mode == 0:
		return
	if suspended_card:
		suspended_card = false
		card.show()
	if pending_start:
		pending_start = false
		var id := "bonds" if city.funds() <= 0 else "start"
		if not rules.muted.has(id):
			card.show_entry(id)
			rules.record(id)
	var running := app.simulation_state.speed_controller != null and app.simulation_state.speed_controller.speed != GameSpeedController.Speed.PAUSED
	if app.coop.active():
		var confirmed := app.coop.windows.state
		running = int(confirmed.get("speed", GameSpeedController.Speed.PAUSED)) != GameSpeedController.Speed.PAUSED
		running = running and not bool(confirmed.get("blocked", false)) and not bool(confirmed.get("terminal", false))
	if running:
		rules.advance(delta)
	var collapsed := card.age >= 20.0 and not card.expanded and not card.pin.button_pressed
	if mode == 2 and (not card.visible or collapsed):
		var id := rules.take()
		if not id.is_empty():
			card.show_entry(id)
	layout_elapsed += delta
	if card.visible and layout_elapsed >= 0.1:
		layout_elapsed = 0.0
		_layout()


func _layout() -> void:
	card.theme = AppUiTheme.current()
	var viewport := app.get_viewport().get_visible_rect().size
	var width := minf(390.0, viewport.x - 32.0)
	card.custom_minimum_size.x = width
	card.size = Vector2(width, 0)
	var bottom := app.city_status_bar.get_global_rect().position.y - 12.0
	var y := app.city_menu_bar.get_global_rect().end.y + 12.0 if top else bottom - card.size.y
	card.position = Vector2(viewport.x - width - 16.0, maxf(app.city_menu_bar.get_global_rect().end.y + 8.0, y))


func open() -> void:
	window.open(rules.history, card.id if not card.id.is_empty() else "start")


func show_growth() -> void:
	if city == null or app.tool_state.active_query_result == null:
		return
	if app.coop.active() and (app.coop.display_revision != int(app.coop.session.latest.get("revision", -1))):
		return
	if app.coop.active() and host_view != str(app.coop.session.latest.get("view_owner", "")):
		return
	var inputs := KnowledgeRules.growth(city, app.tool_state.active_query_result.point)
	if not bool(inputs.get("rci", false)):
		return
	app.query_choices.close_query(false)
	growth_dialog.open(inputs)


func _action(action: String) -> void:
	if action == "demand":
		window.open(rules.history, "demand")
		return
	if city == null:
		return
	window.hide()
	var modes := {"water": CityViewMode.Mode.WATER, "power": CityViewMode.Mode.POWER,
		"growth": CityViewMode.Mode.GROWTH, "land": CityViewMode.Mode.LAND_VALUE,
		"traffic": CityViewMode.Mode.TRAFFIC, "pollution": CityViewMode.Mode.POLLUTION}
	if modes.has(action):
		app.menus.select_view(modes[action])
	elif action == "budget":
		app.reports.on_windows_menu(0)
	elif action == "ordinances":
		app.reports.on_windows_menu(1)
	elif action == "graphs":
		app.reports.on_windows_menu(4)
	elif action == "scenario":
		app.reports.on_windows_menu(CityMenuBar.MENU_SCENARIO_GOALS)
