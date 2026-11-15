class_name AppTooltips
extends Node


func _ready() -> void:
	MenuMotion.watch(get_tree())
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
	var viewport := _embedding_viewport(popup)
	var available := float(viewport.size.x) if viewport is Window else viewport.get_visible_rect().size.x
	wrap_labels(popup, available / popup.content_scale_factor)
	popup.reset_size()
	popup.size_changed.connect(_reposition_popup.bind(weakref(popup)))
	_reposition_popup.call_deferred(weakref(popup))
	var effect := preload("res://src/ui/shared/frosted_tooltip.gd").new()
	popup.add_child(effect)


func _embedding_viewport(popup: PopupPanel) -> Viewport:
	var viewport := popup.get_parent().get_viewport()
	while not viewport.gui_embed_subwindows and viewport.get_parent() != null:
		viewport = viewport.get_parent().get_viewport()
	return viewport


func _reposition_popup(reference: WeakRef) -> void:
	var popup := reference.get_ref() as PopupPanel
	if popup == null or not popup.is_inside_tree() or not popup.visible:
		return
	var owner := popup.get_parent() as Control
	if owner == null or not popup.is_embedded():
		return
	# Godot positions the original, unwrapped text before this deferred setup.
	# After wrapping, fit the new size near its actual trigger instead of
	# retaining the distant position chosen for the original long line.
	var viewport := _embedding_viewport(popup)
	var area := viewport.get_final_transform() * viewport.get_visible_rect()
	var source := owner.get_viewport()
	var point := owner.get_local_mouse_position()
	if not Rect2(Vector2.ZERO, owner.size).has_point(point):
		point = owner.size * 0.5
	var anchor := source.get_final_transform() * (owner.get_global_transform_with_canvas() * point)
	if source != viewport and source is Window:
		anchor += Vector2(source.position)
	var offset: Vector2 = ProjectSettings.get_setting("display/mouse_cursor/tooltip_position_offset", Vector2(16, 16))
	offset *= popup.content_scale_factor
	var position := anchor + offset
	var extent := Vector2(popup.size)
	position.x = clampf(position.x, area.position.x, maxf(area.position.x, area.end.x - extent.x))
	if position.y + extent.y > area.end.y:
		position.y = anchor.y - offset.y - extent.y
	position.y = clampf(position.y, area.position.y, maxf(area.position.y, area.end.y - extent.y))
	popup.position = Vector2i(position.round())


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
