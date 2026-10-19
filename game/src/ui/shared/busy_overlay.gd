class_name BusyOverlay
extends Control
# a small centered box with a spinner and a message. it covers its parent and
# takes the pointer input while it is visible

const LoadingSpinner = preload("res://src/ui/shared/loading_spinner.gd")

var spinner: Control
var label: Label
var city_progress: ProgressOverlay
var city_preview: TextureRect
var city_logo: TextureRect
var knowledge_requested: Callable


func _init(message := "") -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := PanelContainer.new()
	box.theme_type_variation = "PanelPadding8_8_8_8"
	center.add_child(box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	spinner = LoadingSpinner.new()
	spinner.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(spinner)
	label = Label.new()
	label.text = message
	label.custom_minimum_size = Vector2(140, 48)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	hide()


func show_message(message: String) -> void:
	if city_progress != null:
		city_progress.hide()
	get_child(0).show()
	label.text = message
	show()


func show_city(title: String, image: Image, detail := "Loading city…", fraction := -1.0) -> void:
	if city_progress == null:
		city_progress = preload("res://src/ui/shared/progress_overlay.tscn").instantiate()
		add_child(city_progress)
		city_progress.get_node("Shade").color = AppUiTheme.current().get_color("canvas", "AppPalette")
		var rows: VBoxContainer = city_progress.get_node("Center/Panel/Rows")
		city_logo = TextureRect.new()
		city_logo.texture = preload("res://assets/branding/reticulating-splines-logo.png")
		city_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		city_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		city_logo.texture_filter = Control.TEXTURE_FILTER_LINEAR
		rows.add_child(city_logo)
		rows.move_child(city_logo, 0)
		city_preview = TextureRect.new()
		city_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		city_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		city_preview.texture_filter = Control.TEXTURE_FILTER_LINEAR
		rows.add_child(city_preview)
		rows.move_child(city_preview, 1)
		city_progress.title_label.theme_type_variation = &"SectionHeading"
		city_progress.title_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		city_progress.title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		city_progress.get_node("Center/Panel").add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		resized.connect(_layout_city)
	city_progress.get_node("Shade").color = AppUiTheme.current().get_color("canvas", "AppPalette")
	get_child(0).hide()
	city_preview.texture = ImageTexture.create_from_image(image) if image != null else null
	city_preview.visible = image != null
	_layout_city()
	city_progress.show_progress(title, detail, fraction)
	if knowledge_requested.is_valid():
		knowledge_requested.call(city_progress.get_node("Center/Panel/Rows"))
		_layout_city()
	show()


func _layout_city() -> void:
	if city_progress == null:
		return
	var width := minf(size.x * 0.65, 768)
	var panel: PanelContainer = city_progress.get_node("Center/Panel")
	panel.custom_minimum_size.x = width
	city_logo.custom_minimum_size.y = minf(size.x * 0.3, 420) / 2.4
	city_logo.custom_minimum_size.x = 0
	city_preview.custom_minimum_size.y = minf(size.y * 0.4, 380)
	if knowledge_requested.is_valid():
		city_logo.custom_minimum_size.y = minf(city_logo.custom_minimum_size.y, size.y * 0.12)
		city_preview.custom_minimum_size.y = minf(city_preview.custom_minimum_size.y, maxf(64.0, size.y * 0.2))
	panel.reset_size()
