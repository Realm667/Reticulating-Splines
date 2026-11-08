class_name CityRiotBoundaries
extends Node2D
## Treatment markers draw over buildings; the actual people retain occlusion.

var points: Array[Vector3] = []


func show_markers(map: CityMapControl, values: Array[Vector3]) -> void:
	points = values
	visible = not points.is_empty()
	if not visible:
		return
	var zoom := map.camera._view_scale()
	position = map.camera._draw_offset(zoom)
	scale = Vector2.ONE * zoom
	var overlay := map.layers.overlay_layer
	var target := overlay.get_index() - (1 if get_index() < overlay.get_index() else 0)
	if get_index() != target:
		map.move_child(self, target)
	queue_redraw()


func _draw() -> void:
	for point in points:
		var center := Vector2(point.x, point.y)
		var edge := PackedVector2Array([
			center + Vector2(-16, 0), center + Vector2(0, -8),
			center + Vector2(16, 0), center + Vector2(0, 8), center + Vector2(-16, 0),
		])
		draw_polyline(edge, Color(0.92, 0.64, 0.24, point.z * 0.85), 1.0)
