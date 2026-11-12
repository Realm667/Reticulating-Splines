class_name CityLibraryTable
extends Tree
## Draw one continuous row rule, including action-button cells such as the star.


func _init() -> void:
	add_theme_constant_override("draw_guides", 0)
	hide_folding = true


static func format_timestamp(value: Variant) -> String:
	if value == null:
		return "—"
	var raw := str(value).strip_edges()
	if raw.is_empty():
		return "—"
	if not (value is int or value is float or raw.is_valid_float()):
		return raw
	var seconds := float(value)
	if not is_finite(seconds) or seconds <= 0.0:
		return "—"
	var date := Time.get_datetime_dict_from_unix_time(int(seconds) + Time.get_time_zone_from_system().bias * 60)
	var day := "%04d-%02d-%02d" % [date.year, date.month, date.day]
	match TranslationServer.get_locale().get_slice("_", 0):
		"de": day = "%02d.%02d.%04d" % [date.day, date.month, date.year]
		"es", "fr", "it", "pt": day = "%02d/%02d/%04d" % [date.day, date.month, date.year]
		"ko": day = "%04d.%02d.%02d" % [date.year, date.month, date.day]
	return "%s %02d:%02d" % [day, date.hour, date.minute]


func _draw() -> void:
	var root := get_root()
	if root == null:
		return
	var panel := get_theme_stylebox("panel")
	var start := panel.get_content_margin(SIDE_LEFT)
	var color := get_theme_color("guide_color")
	var item := root.get_first_child()
	while item != null:
		var area := get_item_area_rect(item)
		if area.has_area() and area.position.y >= 0 and area.end.y < size.y - panel.get_content_margin(SIDE_BOTTOM):
			draw_line(Vector2(start, floorf(area.end.y) - 0.5), Vector2(minf(area.end.x, size.x - panel.get_content_margin(SIDE_RIGHT)), floorf(area.end.y) - 0.5), color, 1.0)
		item = item.get_next()
