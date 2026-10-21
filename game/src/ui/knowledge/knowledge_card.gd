class_name KnowledgeCard
extends PanelContainer
## One nonmodal card, also reused inside the loader and knowledge window.

signal action_requested(action: String)
signal dismissed
signal mute_requested(id: String)
var id := ""
var column: VBoxContainer
var heading: Label
var summary: Label
var details: Label
var action_button: Button
var close_button: Button
var pin: CheckButton
var controls: HFlowContainer
const READING_SECONDS := 45.0
var context_valid := true
var library := false
var age := 0.0
var embedded := false
var body: VBoxContainer
var scroll: ScrollContainer
var unbounded_body := false
var contextual := false


func _init() -> void:
	theme_type_variation = "UtilityPanel"
	mouse_filter = Control.MOUSE_FILTER_STOP
	column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	add_child(column)
	var top := HBoxContainer.new()
	column.add_child(top)
	var label := Label.new()
	label.text = "Tips & Knowledge"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(label)
	close_button = Button.new()
	close_button.text = "×"
	close_button.tooltip_text = "Close"
	close_button.pressed.connect(func() -> void:
		hide()
		dismissed.emit())
	top.add_child(close_button)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	column.add_child(scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	scroll.add_child(body)
	heading = _label("")
	heading.theme_type_variation = "SectionHeading"
	summary = _label("")
	details = _label("")
	details.hide()
	controls = HFlowContainer.new()
	column.add_child(controls)
	action_button = _button("Open view", func() -> void:
		var entry := KnowledgeCatalog.entry(id)
		if not entry.is_empty():
			action_requested.emit(entry[4]))
	pin = CheckButton.new()
	pin.text = "Keep open"
	controls.add_child(pin)
	var menu := MenuButton.new()
	menu.text = "…"
	menu.tooltip_text = "Tip options"
	menu.get_popup().add_item("Hide this topic", 0)
	menu.get_popup().id_pressed.connect(func(_value: int) -> void:
		mute_requested.emit(id)
		hide())
	controls.add_child(menu)


func _label(text: String) -> Label:
	var result := Label.new()
	result.text = text
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(result)
	return result


func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	controls.add_child(button)
	return button


func show_entry(value: String, _full := false) -> void:
	var entry := KnowledgeCatalog.entry(value)
	if entry.is_empty():
		return
	id = value
	context_valid = true
	controls.show()
	heading.text = _heading(entry)
	summary.text = tr(entry[2])
	details.text = tr(entry[3])
	details.visible = not str(entry[3]).is_empty()
	summary.show()
	action_button.visible = not library and not str(entry[4]).is_empty()
	action_button.text = {"water": "Open water view", "power": "Open power view", "land": "Show land value", "budget": "Open budget", "event": "Go to event"}.get(entry[4], "Open view")
	close_button.visible = not library
	pin.set_pressed_no_signal(false)
	age = 0.0
	show()


func _process(delta: float) -> void:
	if is_visible_in_tree():
		var body_height := body.get_combined_minimum_size().y
		scroll.custom_minimum_size.y = body_height if unbounded_body else minf(body_height, 110.0 if embedded else 200.0)
	if embedded or not visible or pin.button_pressed:
		return
	var focus := get_viewport().gui_get_focus_owner()
	if get_global_rect().has_point(get_global_mouse_position()) or (focus != null and is_ancestor_of(focus)):
		return
	age += delta
	if age >= READING_SECONDS:
		hide()


func set_context_valid(value: bool) -> void:
	context_valid = value
	var entry := KnowledgeCatalog.entry(id)
	if entry.is_empty():
		return
	heading.text = _heading(entry)
	action_button.visible = value and not library and not str(entry[4]).is_empty()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and heading != null and not id.is_empty():
		var entry := KnowledgeCatalog.entry(id)
		heading.text = _heading(entry)
		summary.text = tr(entry[2])
		details.text = tr(entry[3])


func _heading(entry: Array) -> String:
	if contextual and context_valid and id == "power":
		return tr("Some buildings lack power")
	if contextual and context_valid and id == "water":
		return tr("Some buildings lack water")
	return tr(entry[1])
