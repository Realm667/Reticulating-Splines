class_name CityToolHoldMenu
extends PopupPanel

signal subtool_requested(index: int)

const PaletteView = preload("res://src/ui/shell/city_child_tool_palette.gd")

var palette: CityChildToolPalette


func _init() -> void:
	palette = PaletteView.new()
	palette.build()
	palette.custom_minimum_size = Vector2(280, 0)
	palette.subtool_requested.connect(_select_subtool)
	add_child(palette)
	close_requested.connect(hide)
	window_input.connect(_on_window_input)


func show_tools(
	group_index: int, city: CityState, icon_provider: Callable,
	selected_subtool: int, anchor: Rect2
) -> void:
	palette.show_tool_group(group_index, city, icon_provider)
	show_palette(selected_subtool, anchor)


func show_palette(selected_subtool: int, anchor: Rect2) -> void:
	# PopupPanel otherwise keeps the engine's dark default under a light theme.
	var panel := get_theme_stylebox("panel", "PopupPanel").duplicate() as StyleBox
	if panel is StyleBoxFlat:
		panel.bg_color.a = 1.0
	add_theme_stylebox_override("panel", panel)
	palette.show()
	palette.sync_selection(selected_subtool)
	var bounds := Rect2i(get_parent().get_viewport_rect())
	var content_height := 40
	for button: Button in palette.buttons.values():
		content_height += ceili(button.get_combined_minimum_size().y) + 3
	var width := maxi(300, ceili(palette.grid.get_combined_minimum_size().x) + 32)
	var requested := Vector2i(mini(width, bounds.size.x), mini(content_height, int(bounds.size.y * 0.7)))
	popup(fit_to_view(anchor, requested, bounds))
	_focus_selected.call_deferred(selected_subtool)


static func fit_to_view(anchor: Rect2, requested: Vector2i, bounds: Rect2i) -> Rect2i:
	var fitted := requested.min(bounds.size)
	var origin := Vector2i(int(anchor.end.x + 4), int(anchor.position.y))
	if origin.x + fitted.x > bounds.end.x:
		origin.x = int(anchor.position.x) - fitted.x - 4
	origin.x = clampi(origin.x, bounds.position.x, bounds.end.x - fitted.x)
	origin.y = clampi(origin.y, bounds.position.y, bounds.end.y - fitted.y)
	return Rect2i(origin, fitted)


func _focus_selected(index: int) -> void:
	# Embedded windows establish their viewport focus on the next frame.
	await get_tree().process_frame
	if not visible:
		return
	var button := palette.buttons.get(index) as Button
	if button == null or button.disabled:
		for candidate: Button in palette.buttons.values():
			if not candidate.disabled:
				button = candidate
				break
	if button != null and not button.disabled:
		button.grab_focus()
		palette.scroll.ensure_control_visible(button)


func _on_window_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		set_input_as_handled()
		hide()


func _select_subtool(index: int) -> void:
	hide()
	subtool_requested.emit(index)
