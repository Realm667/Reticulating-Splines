class_name AppTooltips
extends Node


func _ready() -> void:
	get_tree().node_added.connect(_node_added)


func _node_added(node: Node) -> void:
	if node is PopupPanel and node.theme_type_variation == &"TooltipPanel":
		_bind_popup.call_deferred(weakref(node))
	elif node is PanelContainer and node.theme_type_variation == &"TooltipPanel":
		_bind_panel.call_deferred(weakref(node))


func _bind_popup(reference: WeakRef) -> void:
	var popup := reference.get_ref() as PopupPanel
	if popup == null or not popup.is_inside_tree():
		return
	wrap_labels(popup, popup.get_parent().get_viewport().get_visible_rect().size.x / popup.content_scale_factor)
	popup.reset_size()
	var effect := preload("res://src/ui/shared/frosted_tooltip.gd").new()
	popup.add_child(effect)


func _bind_panel(reference: WeakRef) -> void:
	var panel := reference.get_ref() as PanelContainer
	if panel != null and panel.is_inside_tree():
		var available_width := panel.get_viewport_rect().size.x
		var layer := panel.get_parent() as CanvasLayer
		if layer != null and layer.custom_viewport is Viewport:
			# The frosted copy belongs to the popup node but draws in the outer viewport.
			available_width = layer.custom_viewport.get_visible_rect().size.x / maxf(panel.scale.x, 0.001)
		wrap_labels(panel, available_width)
		FrostedTooltipPanel.bind(panel)


static func wrap_labels(node: Node, available_width: float) -> void:
	# A compact reading measure of about 55 average characters, measured in
	# the actual font. UI scaling follows the font; the viewport is the cap.
	for child in node.get_children():
		if child is Label:
			var font: Font = child.get_theme_font("font")
			var font_size: int = child.get_theme_font_size("font_size")
			var measure: float = font.get_string_size("abcdefghijklmnopqrstuvwxyz", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x / 26.0 * 55.0
			var width := maxf(1.0, minf(measure, available_width - 32.0))
			# The translucent overlay copies an already constrained popup label.
			if child.custom_maximum_size.x > 0.0:
				width = minf(width, child.custom_maximum_size.x)
			var lines := child.tr(child.text).split("\n")
			var natural := 0.0
			for line in lines:
				natural = maxf(natural, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
			child.custom_minimum_size.x = minf(width, maxf(child.custom_minimum_size.x, ceilf(natural) + 2.0))
			child.custom_maximum_size.x = width
			child.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		else:
			wrap_labels(child, available_width)
