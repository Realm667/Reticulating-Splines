class_name CityZoomBlur
extends RefCounted
## A short city-only radial blur during the existing camera zoom animation.

const SHADER := preload("res://src/view/environment/zoom_blur.gdshader")
var canvas: Node2D
var copy: BackBufferCopy
var rect: ColorRect
var material: ShaderMaterial


func stop() -> void:
	if is_instance_valid(canvas):
		canvas.hide()
		copy.copy_mode = BackBufferCopy.COPY_MODE_DISABLED


func update(map: CityMapControl) -> void:
	var amount := map.camera.zoom_blur_amount()
	if amount <= 0.0 or not map.is_visible_in_tree():
		stop()
		return
	if not is_instance_valid(canvas):
		canvas = Node2D.new()
		canvas.name = "CityZoomBlur"
		map.add_child(canvas)
		copy = BackBufferCopy.new()
		canvas.add_child(copy)
		rect = ColorRect.new()
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		material = ShaderMaterial.new()
		material.shader = SHADER
		rect.material = material
		canvas.add_child(rect)
	# Resolve weather, light and tilt shift together, below sharp tool overlays.
	var overlay := map.layers.overlay_layer
	var target := overlay.get_index() - (1 if canvas.get_index() < overlay.get_index() else 0)
	if canvas.get_index() != target:
		map.move_child(canvas, target)
	var bounds := map.camera._camera_rect().intersection(Rect2(Vector2.ZERO, map.size))
	bounds.position.x = 0.0
	bounds.size.x = map.size.x
	if not bounds.has_area():
		stop()
		return
	rect.position = bounds.position
	rect.size = bounds.size
	material.set_shader_parameter("amount", amount)
	material.set_shader_parameter("anchor", (map.camera.zoom_anchor() - bounds.position) / bounds.size)
	copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	canvas.show()
