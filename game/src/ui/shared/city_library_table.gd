class_name CityLibraryTable
extends Tree
## Draw one continuous row rule, including action-button cells such as the star.


func _init() -> void:
	add_theme_constant_override("draw_guides", 0)
	hide_folding = true


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
