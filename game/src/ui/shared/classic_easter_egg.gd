class_name ClassicEasterEgg
extends Control
## A transient overlay: never creates map objects or save data.

var arcology: Texture2D
var elapsed := 0.0
var permitted: Callable


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _process(delta: float) -> void:
	elapsed += delta
	if elapsed > 8.0 or not permitted.is_valid() or not permitted.call():
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var center := Vector2(size.x * 0.5 + sin(elapsed * 3.0) * 50.0, size.y * 0.48)
	if arcology != null:
		var height := minf(220.0, size.y * 0.3)
		var dimensions := arcology.get_size() * height / arcology.get_height()
		var step := sin(elapsed * 8.0) * 18.0
		center.y -= absf(step)
		draw_texture_rect(arcology, Rect2(center - dimensions * Vector2(0.5, 1.0), dimensions), false)
		for side in [-1, 1]:
			var hip := center + Vector2(side * 18, -5)
			var foot := center + Vector2(side * 35 + step, 32)
			draw_line(hip, foot, Color.WHITE, 5.0)
			draw_line(foot, foot + Vector2(side * 16, 0), Color.BLACK, 7.0)
	else:
		center.y = lerpf(-80.0, size.y + 90.0, elapsed / 8.0)
		var canopy := PackedVector2Array()
		for i in 17:
			var angle := PI + PI * float(i) / 16.0
			canopy.append(center + Vector2(cos(angle) * 48.0, sin(angle) * 30.0 - 35.0))
		draw_colored_polygon(canopy, Color(0.9, 0.15, 0.1))
		for side in [-1, 1]:
			draw_line(center + Vector2(side * 48, -35), center + Vector2(side * 8, 6), Color.WHITE, 2)
			draw_line(center + Vector2(0, 15), center + Vector2(side * 12, 36), Color.DARK_BLUE, 5)
		draw_rect(Rect2(center - Vector2(5, 0), Vector2(10, 21)), Color.YELLOW)
		draw_rect(Rect2(center - Vector2(4, 9), Vector2(8, 8)), Color.BISQUE)
