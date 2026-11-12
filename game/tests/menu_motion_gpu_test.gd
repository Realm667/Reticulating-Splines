extends "res://tests/support/scene_test_case.gd"
## Render the menu tail and exercise rapid reopen and owner destruction.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.gui_embed_subwindows = true
	root.size = Vector2i(640, 480)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.content_scale_factor = 1.0
	var background := ColorRect.new()
	background.color = Color.BLUE
	root.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var popup := PopupPanel.new()
	background.add_child(popup)
	var content := ColorRect.new()
	content.color = Color.RED
	content.custom_minimum_size = Vector2(160, 100)
	popup.add_child(content)
	MenuMotion.bind(popup)
	MenuMotion.bind(popup)
	var motion: MenuMotion
	var bindings := 0
	for child in popup.get_children():
		if child is MenuMotion:
			motion = child
			bindings += 1
	assert(bindings == 1, "A popup has one animation owner")
	popup.popup(Rect2i(50, 50, 180, 120))
	motion._tween.pause()
	motion._tween.custom_step(MenuMotion.SECONDS * 0.5)
	assert(content.modulate.a > 0.2 and content.modulate.a < 1.0, "Opening has an intermediate opacity")
	motion._tween.custom_step(MenuMotion.SECONDS)
	for frame in 3:
		await RenderingServer.frame_post_draw
	popup.hide()
	assert(motion._ghost != null, "Dismissed popup retains a short visual tail")
	assert(not popup.visible, "Fade-out releases popup input immediately")
	motion._tween.pause()
	motion._tween.custom_step(MenuMotion.SECONDS * 0.5)
	var tail := motion._ghost.get_child(0) as TextureRect
	assert(tail.mouse_filter == Control.MOUSE_FILTER_IGNORE and tail.modulate.a > 0.0 and tail.modulate.a < 1.0)
	for frame in 2:
		await RenderingServer.frame_post_draw
	var pixel := root.get_texture().get_image().get_pixel(90, 90)
	assert(pixel.r > 0.1 and pixel.b > 0.1, "The fading menu composites over the live background")
	popup.popup(Rect2i(50, 50, 180, 120))
	assert(motion._ghost == null and popup.visible, "Reopening cancels the old tail")
	motion._tween.pause()
	motion._tween.custom_step(MenuMotion.SECONDS * 2)
	for frame in 2:
		await RenderingServer.frame_post_draw
	popup.hide()
	await get_tree().create_timer(MenuMotion.SECONDS * 2).timeout
	assert(motion._ghost == null, "Completed fade removes its texture and layer")
	popup.popup(Rect2i(50, 50, 180, 120))
	for frame in 2:
		await RenderingServer.frame_post_draw
	popup.hide()
	background.queue_free()
	await process_frame
	await process_frame
	print("PASS: menu fade intermediate frames, compositing, immediate input release, reopen and cleanup")
	quit()
