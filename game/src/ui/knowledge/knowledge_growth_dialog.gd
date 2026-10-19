class_name KnowledgeGrowthDialog
extends QolDialog

signal action_requested(action: String)
var checks: VBoxContainer
var reason: Label
var explanation: Label
var action: Button
var selected_action := "land"


func _init() -> void:
	super()
	wrap_controls = false
	title = "Why is nothing growing here?"
	min_size = Vector2i(300, 240)
	size = Vector2i(410, 430)
	checks = VBoxContainer.new()
	column.add_child(checks)
	reason = label("")
	reason.custom_minimum_size.x = 260
	var actions := HFlowContainer.new()
	column.add_child(actions)
	action = button(actions, "Show land value", func() -> void:
		hide()
		action_requested.emit(selected_action))
	button(actions, "Explain the connection", func() -> void:
		explanation.visible = not explanation.visible)
	explanation = label("This is a snapshot of the current conditions, not a promise of growth next month.")
	explanation.custom_minimum_size.x = 260
	explanation.hide()
	button(column, "Close", hide)


func open(inputs: Dictionary) -> void:
	for child in checks.get_children():
		checks.remove_child(child)
		child.queue_free()
	for check: Array in KnowledgeRules.growth_rows(inputs):
		var split := HBoxContainer.new()
		checks.add_child(split)
		var name_label := Label.new()
		name_label.text = tr(check[0])
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_label.size_flags_stretch_ratio = 1.3
		split.add_child(name_label)
		var value := Label.new()
		value.text = tr(check[1])
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		split.add_child(value)
	selected_action = "land"
	action.text = "Show land value"
	if not bool(inputs.powered):
		reason.text = tr("Power is missing at this site.")
		selected_action = "power"
		action.text = "Open power view"
	elif int(inputs.needed_land_value) >= 0 and int(inputs.land_value) <= int(inputs.needed_land_value):
		reason.text = tr("Land value limits the next density level here.")
	elif not bool(inputs.visited):
		reason.text = tr("This tile is not currently visited for growth. Check access or query the building's anchor tile.")
		selected_action = "traffic"
		action.text = "Open view"
	elif not bool(inputs.can_advance):
		reason.text = tr("The current zoning or building density limits further expansion.")
	else:
		reason.text = tr("No blocker was found in these checks. Destination reachability and the next growth visit still matter.")
	explanation.hide()
	theme = AppUiTheme.current()
	var viewport_size := get_parent().get_viewport().get_visible_rect().size
	popup(Rect2i(Vector2i(maxf(8, viewport_size.x - 434), 65), Vector2i(minf(410, viewport_size.x - 24), minf(420, viewport_size.y - 100))))
