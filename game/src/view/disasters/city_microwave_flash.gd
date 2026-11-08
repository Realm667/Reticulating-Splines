class_name CityMicrowaveFlash
extends RefCounted
## A brief blue-white exposure over the complete game viewport.

const SHADER := preload("res://src/view/disasters/microwave_flash.gdshader")
var canvas: CanvasLayer
var copy: BackBufferCopy
var rect: ColorRect
var material: ShaderMaterial


static func envelope(age: float) -> float:
	return smoothstep(0.0, 0.08, age) * (1.0 - smoothstep(0.12, 0.30, age))


func update(host: Node, amount: float) -> void:
	if amount <= 0.001:
		if is_instance_valid(canvas):
			canvas.hide()
			copy.copy_mode = BackBufferCopy.COPY_MODE_DISABLED
		return
	if not is_instance_valid(canvas):
		canvas = CanvasLayer.new()
		canvas.name = "MicrowaveFlash"
		canvas.layer = 100
		host.add_child(canvas)
		copy = BackBufferCopy.new()
		canvas.add_child(copy)
		rect = ColorRect.new()
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		material = ShaderMaterial.new()
		material.shader = SHADER
		rect.material = material
		canvas.add_child(rect)
	rect.size = host.get_viewport().get_visible_rect().size
	material.set_shader_parameter("amount", clampf(amount, 0.0, 1.0))
	copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	canvas.show()
