class_name CityTiltShift
extends RefCounted
## A final city-only pass. Hidden effects do not copy or sample the viewport.

const SHADER := preload("res://src/view/environment/tilt_shift.gdshader")
var canvas: Node2D
var copy: BackBufferCopy
var rect: ColorRect
var material: ShaderMaterial


func update(map: CityMapControl, active: bool, options: Dictionary) -> void:
	var enabled: bool = active and options.tilt_shift_enabled and options.tilt_shift_strength > 0.0
	if not enabled:
		if is_instance_valid(canvas):
			canvas.hide()
			copy.copy_mode = BackBufferCopy.COPY_MODE_DISABLED
		return
	if not is_instance_valid(canvas):
		canvas = Node2D.new()
		canvas.name = "CityTiltShift"
		map.add_child(canvas)
		copy = BackBufferCopy.new()
		canvas.add_child(copy)
		rect = ColorRect.new()
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		material = ShaderMaterial.new()
		material.shader = SHADER
		rect.material = material
		canvas.add_child(rect)
	# Keep precipitation, glow and any newly created map layers below this pass;
	# selections, tool previews and the rest of the interface remain above it.
	var overlay := map.layers.overlay_layer
	if overlay != null:
		var target := overlay.get_index() - (1 if canvas.get_index() < overlay.get_index() else 0)
		if canvas.get_index() != target:
			map.move_child(canvas, target)
	var bounds := map.camera._camera_rect().intersection(Rect2(Vector2.ZERO, map.size))
	# Camera centering excludes the sidebar's column, not the visible artwork
	# below it. The interface is drawn later, above this city-only pass.
	bounds.position.x = 0.0
	bounds.size.x = map.size.x
	rect.position = bounds.position
	rect.size = bounds.size
	copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	material.set_shader_parameter("strength", options.tilt_shift_strength)
	material.set_shader_parameter("edge_size", options.tilt_shift_edge)
	material.set_shader_parameter("transition", options.tilt_shift_transition)
	canvas.visible = bounds.has_area()
