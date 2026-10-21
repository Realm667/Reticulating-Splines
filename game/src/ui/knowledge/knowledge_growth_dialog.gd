class_name KnowledgeGrowthDialog
extends QolDialog

signal action_requested(action: String)
var checks: VBoxContainer
var reason: Label
var explanation: Label
var action: Button
var selected_action := "land"
var findings_scroll: ScrollContainer


func _init() -> void:
	super()
	wrap_controls = false
	title = "What needs attention here?"
	min_size = Vector2i(300, 240)
	size = Vector2i(410, 430)
	checks = VBoxContainer.new()
	column.add_child(checks)
	reason = label("")
	reason.custom_minimum_size.x = 260
	findings_scroll = ScrollContainer.new()
	findings_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	findings_scroll.custom_minimum_size.y = 110
	findings_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(findings_scroll)
	reason.reparent(findings_scroll)
	reason.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	title = KnowledgeRules.growth_title(inputs)
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
	var findings := PackedStringArray()
	var empty := int(inputs.building) < BuildingTileIds.DEVELOPED_FIRST
	if not bool(inputs.powered):
		findings.append(tr("Connect this site to a working power supply."))
		selected_action = "power"
		action.text = "Open power view"
	if empty and not bool(inputs.transport):
		findings.append(tr("No nearby transport access was found. Add a road or a suitable station within three grid steps."))
		if selected_action != "power":
			selected_action = "traffic"
			action.text = "Open view"
	if int(inputs.class_demand) <= 0:
		findings.append(tr("Demand is weak. More zoning alone will not help; check taxes and existing connections."))
	if int(inputs.needed_land_value) >= 0 and int(inputs.land_value) <= int(inputs.needed_land_value):
		findings.append(tr("Land value is too low for the next density level. Check water supply and local pollution."))
	elif not bool(inputs.can_advance):
		findings.append(tr("The zoning or current building size limits further expansion."))
	if not empty and not bool(inputs.visited):
		findings.append(tr("This tile is part of a larger building. Query its anchor tile to check further development."))
	if findings.is_empty():
		findings.append(tr("Power and the checked local conditions allow development. A successful route and a later growth visit are still needed."))
	findings.append(tr("The full route to a suitable destination has not been checked."))
	reason.text = "\n\n".join(findings)
	explanation.hide()
	theme = AppUiTheme.current()
	var viewport_size := get_parent().get_viewport().get_visible_rect().size
	popup(Rect2i(Vector2i(maxf(8, viewport_size.x - 434), 65), Vector2i(minf(410, viewport_size.x - 24), minf(420, viewport_size.y - 100))))
