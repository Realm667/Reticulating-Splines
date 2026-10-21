class_name CitySunGlow
extends RefCounted
## Screen-space dawn/dusk glow, derived only from the existing visual day clock.

const SHADER := preload("res://src/view/environment/sun_glow.gdshader")
var rect: ColorRect
var material: ShaderMaterial


static func at_hour(hour: float, options: Dictionary) -> Dictionary:
	var result := {"center": Vector2.ZERO, "color": Color.WHITE, "strength": 0.0}
	if not options.day_enabled:
		return result
	var h := fposmod(hour, 24.0)
	var duration: float = options.day_glow_hours
	for event in ["sunrise", "sunset"]:
		if not options[event + "_enabled"]:
			continue
		var middle := 7.0 if event == "sunrise" else 19.0
		var progress := (h - middle) / duration + 0.5
		if progress <= 0.0 or progress >= 1.0:
			continue
		var start := Vector2(0.08, 0.52) if event == "sunrise" else Vector2(0.08, 0.08)
		var finish := Vector2(0.08, 0.08) if event == "sunrise" else Vector2(0.92, 0.52)
		result.center = start.lerp(finish, smoothstep(0.0, 1.0, progress))
		result.color = Color(0.65, 0.82, 1.0) if event == "sunrise" else Color(1.0, 0.61, 0.28)
		result.strength = float(options[event + "_strength"]) * smoothstep(0.0, 0.3, progress) * (1.0 - smoothstep(0.7, 1.0, progress))
		break
	return result


func update(map: CityMapControl, active: bool, options: Dictionary, hour: float, before: Node = null) -> void:
	var state := at_hour(hour, options) if active else {"strength": 0.0}
	if state.strength <= 0.0:
		if is_instance_valid(rect):
			rect.hide()
		return
	if not is_instance_valid(rect):
		rect = ColorRect.new()
		rect.name = "CitySunGlow"
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		material = ShaderMaterial.new()
		material.shader = SHADER
		rect.material = material
		map.add_child(rect)
	var overlay := before if is_instance_valid(before) else map.layers.overlay_layer
	var target := overlay.get_index() - (1 if rect.get_index() < overlay.get_index() else 0)
	if rect.get_index() != target:
		map.move_child(rect, target)
	var bounds := map.camera._camera_rect().intersection(Rect2(Vector2.ZERO, map.size))
	# Camera centering excludes the sidebar, but visible map below it does not.
	bounds.position.x = 0.0
	bounds.size.x = map.size.x
	rect.position = bounds.position
	rect.size = bounds.size
	material.set_shader_parameter("canvas_size", bounds.size)
	material.set_shader_parameter("glow_center", state.center)
	material.set_shader_parameter("glow_color", state.color)
	material.set_shader_parameter("strength", state.strength)
	material.set_shader_parameter("radius", options.day_glow_radius)
	rect.visible = bounds.has_area()
