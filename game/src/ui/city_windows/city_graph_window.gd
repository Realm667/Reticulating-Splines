class_name CityGraphWindow
extends Window

const GraphView = preload("res://src/view/city_graph_control.gd")

var graph_control: CityGraphControl
var series_buttons: Array[CheckBox] = []


func _ready() -> void:
	hide()
	close_requested.connect(hide)
	graph_control = get_node("Background/Margin/Column/ChartFrame/Chart")

	for child in $Background/Margin/Column/Controls/SeriesChoices.get_children():
		var check := child as CheckBox
		check.toggled.connect(_on_series_toggled.bind(series_buttons.size()))
		series_buttons.append(check)

	var scale_index := 0

	for child in $Background/Margin/Column/Controls/TimeScales.get_children():
		if child is CheckBox:
			child.pressed.connect(_on_time_scale_selected.bind(scale_index))
			scale_index += 1
	graph_control.theme_changed.connect(_refresh_series_icons)
	_refresh_series_icons.call_deferred()


func _refresh_series_icons() -> void:
	for series in series_buttons.size():
		var color := graph_control.series_color(series)
		var ink := "#182028" if color.get_luminance() > 0.4 else "#ffffff"
		var source := '<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 20 20"><rect x="1" y="1" width="18" height="18" rx="3" fill="#%s"/><path d="m5 10 3 3 7-7" fill="none" stroke="%s" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></svg>' % [color.to_html(false), ink]
		var image := Image.new()
		if image.load_svg_from_string(source) == OK:
			series_buttons[series].add_theme_icon_override("checked", ImageTexture.create_from_image(image))


func show_city(value: CityState) -> void:
	if value == null or graph_control == null:
		return

	graph_control.set_city(value)

	if visible:
		move_to_foreground()
	else:
		popup_centered(Vector2i(860, 560))


func refresh_city(value: CityState) -> void:
	if visible and graph_control != null:
		graph_control.set_city(value)


func _on_series_toggled(enabled: bool, series: int) -> void:
	graph_control.set_series_enabled(series, enabled)


func _on_time_scale_selected(scale: int) -> void:
	graph_control.set_time_scale(scale)
