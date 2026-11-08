class_name CityStormGusts
extends RefCounted
## Brief wind-driven refraction of the map, below selection and interface.

const SHADER := preload("res://src/view/disasters/storm_gust.gdshader")
var canvas: Node2D
var copy: BackBufferCopy
var rect: ColorRect
var material: ShaderMaterial


static func strength_at(time: float) -> float:
	var cycle := floorf(time / 4.7)
	var phase := fposmod(time, 4.7) - 1.2 - (sin(cycle * 2.4) + 1.0) * 0.3
	return smoothstep(0.0, 0.3, phase) * (1.0 - smoothstep(0.5, 1.3, phase))


func update(map: CityMapControl, strength: float, time: float) -> void:
	var amount := strength * strength_at(time)
	if amount <= 0.001 or not map.is_visible_in_tree():
		if is_instance_valid(canvas):
			canvas.hide()
			copy.copy_mode = BackBufferCopy.COPY_MODE_DISABLED
		return
	if not is_instance_valid(canvas):
		canvas = Node2D.new()
		canvas.name = "StormGusts"
		map.add_child(canvas)
		copy = BackBufferCopy.new()
		canvas.add_child(copy)
		rect = ColorRect.new()
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		material = ShaderMaterial.new()
		material.shader = SHADER
		rect.material = material
		canvas.add_child(rect)
	var overlay := map.layers.overlay_layer
	var target := overlay.get_index() - (1 if canvas.get_index() < overlay.get_index() else 0)
	if canvas.get_index() != target:
		map.move_child(canvas, target)
	var bounds := map.camera._camera_rect().intersection(Rect2(Vector2.ZERO, map.size))
	bounds.position.x = 0.0
	bounds.size.x = map.size.x
	rect.position = bounds.position
	rect.size = bounds.size
	material.set_shader_parameter("amount", amount)
	material.set_shader_parameter("clock", time)
	copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	canvas.show()
