extends "res://tests/support/scene_test_case.gd"
## Check actual paper/ink composition, especially transparent sprite margins.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	assert(DisplayServer.get_name() != "headless")
	var viewport := SubViewport.new()
	viewport.size = Vector2i(128, 32)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var paper := ColorRect.new()
	paper.color = Color(0.8, 0.6, 0.4)
	paper.size = Vector2(viewport.size)
	viewport.add_child(paper)
	var ink := Image.create(128, 32, false, Image.FORMAT_RGBA8)
	ink.fill_rect(Rect2i(0, 0, 32, 32), Color(0.05, 0.2, 0.1, 0.0))
	ink.fill_rect(Rect2i(32, 0, 32, 32), Color.WHITE)
	ink.fill_rect(Rect2i(64, 0, 32, 32), Color.BLACK)
	ink.fill_rect(Rect2i(96, 0, 32, 32), Color(0, 0, 0, 0.5))
	var photo := TextureRect.new()
	photo.texture = ImageTexture.create_from_image(ink)
	photo.size = Vector2(viewport.size)
	photo.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var material := ShaderMaterial.new()
	material.shader = preload("res://src/ui/newspaper/paper_ink.gdshader")
	photo.material = material
	viewport.add_child(photo)
	for frame in 4:
		await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	assert(_distance(image.get_pixel(16, 16), paper.color) < 0.025, "Transparent margins must leave paper intact")
	assert(_distance(image.get_pixel(48, 16), paper.color) < 0.025, "White photo areas must reveal paper")
	assert(_distance(image.get_pixel(80, 16), Color.BLACK) < 0.025, "Black ink must darken the paper")
	assert(_distance(image.get_pixel(112, 16), Color(0.4, 0.3, 0.2)) < 0.025, "Half-covered ink must retain half the paper light")
	assert(image.get_pixel(16, 16).a > 0.99, "Printing must not punch holes through opaque paper")
	photo.modulate = Color(1, 1, 1, 0)
	for frame in 2:
		await RenderingServer.frame_post_draw
	image = viewport.get_texture().get_image()
	assert(_distance(image.get_pixel(80, 16), paper.color) < 0.025, "Faded-out photos must not leave a dark rectangle")
	photo.modulate = Color(1, 1, 1, 0.5)
	for frame in 2:
		await RenderingServer.frame_post_draw
	image = viewport.get_texture().get_image()
	assert(_distance(image.get_pixel(80, 16), Color(0.4, 0.3, 0.2)) < 0.025, "Photo ink must follow the newspaper opening fade")
	viewport.free()
	await process_frame
	print("PASS: printed paper preserves alpha margins and grain, white highlights and black/soft ink")
	quit()


func _distance(left: Color, right: Color) -> float:
	return maxf(absf(left.r - right.r), maxf(absf(left.g - right.g), absf(left.b - right.b)))
