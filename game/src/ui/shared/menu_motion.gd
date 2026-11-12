class_name MenuMotion
extends Node
## Short presentation-only transitions. Dismissal releases input immediately.

const SECONDS := 0.10
var _window: Window
var _tween: Tween
var _ghost: CanvasLayer
var _controls: Array[Control] = []
var _opened := false
var _copy: SubViewport
var _embedder: Viewport
var _copy_rect := Rect2()
var _copy_ready := false


static func watch(tree: SceneTree) -> void:
	if tree.has_meta("menu_motion_watch"):
		return
	tree.set_meta("menu_motion_watch", true)
	tree.node_added.connect(func(node: Node) -> void:
		if _is_menu(node):
			_bind_later.call_deferred(weakref(node)))
	_bind_existing(tree.root)


static func _is_menu(node: Node) -> bool:
	return node is PopupMenu or (node is PopupPanel and node.theme_type_variation != &"TooltipPanel")


static func _bind_existing(node: Node) -> void:
	for child in node.get_children(true):
		_bind_existing(child)
	if _is_menu(node):
		_bind_later.call_deferred(weakref(node))


static func _bind_later(reference: WeakRef) -> void:
	var window := reference.get_ref() as Window
	if window != null and window.is_inside_tree():
		bind(window)


static func bind(window: Window) -> void:
	if window.has_meta("menu_motion"):
		return
	window.set_meta("menu_motion", true)
	var motion := MenuMotion.new()
	motion._window = window
	window.add_child(motion)
	window.about_to_popup.connect(motion._opening)
	window.visibility_changed.connect(motion._visibility_changed)
	motion.tree_exiting.connect(motion._dispose)


func _opening() -> void:
	_opened = true
	_finish_tail()
	if _tween != null:
		_tween.kill()
	_controls.clear()
	for child in _window.get_children(true):
		if child is Control:
			_controls.append(child)
	if not is_inside_tree():
		return
	_set_opacity(0.2)
	_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_method(_set_opacity, 0.2, 1.0, SECONDS)
	_begin_copy.call_deferred()


func _begin_copy() -> void:
	if not is_inside_tree() or not _window.visible or not _window.is_embedded() or DisplayServer.get_name() == "headless":
		return
	var ancestor := _window.get_parent()
	while ancestor != null and not (ancestor is Viewport and ancestor.gui_embed_subwindows):
		ancestor = ancestor.get_parent()
	_embedder = ancestor as Viewport
	if _embedder == null:
		return
	_copy_rect = Rect2(Vector2(_window.position), Vector2(_window.size))
	_copy = SubViewport.new()
	_copy.size = _window.size
	_copy.transparent_bg = true
	_copy.disable_3d = true
	_copy.world_2d = World2D.new()
	_copy.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_tree().root.add_child(_copy)
	var crop := AtlasTexture.new()
	crop.atlas = _window.get_texture()
	crop.region = Rect2(Vector2.ZERO, _copy_rect.size)
	var image := TextureRect.new()
	image.texture = crop
	image.size = _copy_rect.size
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_copy.add_child(image)
	var pending := _copy
	await RenderingServer.frame_post_draw
	if is_instance_valid(self) and _copy == pending:
		_copy_ready = true


func _set_opacity(value: float) -> void:
	for control in _controls:
		if is_instance_valid(control):
			control.modulate.a = value


func _visibility_changed() -> void:
	if _window.visible:
		return
	if not _opened:
		return
	_opened = false
	if not is_inside_tree() or not _window.is_inside_tree():
		return
	if _tween != null:
		_tween.kill()
	_set_opacity(1.0)
	_clear_ghost()
	# Keep the last rendered crop on the GPU. After hide(), Window no longer
	# reports itself embedded; its saved viewport and crop remain valid.
	if not _copy_ready or not is_instance_valid(_copy) or not is_instance_valid(_embedder):
		_clear_copy()
		return
	_copy.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_ghost = CanvasLayer.new()
	_ghost.layer = 100
	_embedder.add_child(_ghost)
	var tail := TextureRect.new()
	tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tail.texture = _copy.get_texture()
	tail.position = _copy_rect.position
	tail.size = _copy_rect.size
	tail.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_ghost.add_child(tail)
	_tween = _embedder.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_property(tail, "modulate:a", 0.0, SECONDS)
	_tween.tween_callback(_finish_tail)


func _clear_copy() -> void:
	if is_instance_valid(_copy):
		_copy.queue_free()
	_copy = null
	_copy_ready = false
	_embedder = null


func _finish_tail() -> void:
	_clear_ghost()
	_clear_copy()


func _clear_ghost() -> void:
	if is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null


func _dispose() -> void:
	if _tween != null:
		_tween.kill()
	_finish_tail()
