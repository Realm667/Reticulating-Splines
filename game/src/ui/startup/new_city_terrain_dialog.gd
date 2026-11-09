class_name NewCityTerrainDialog
extends ColorRect

signal cancel_requested
signal build_requested
signal preview_requested
signal terrain_regeneration_requested

const NewCity = preload("res://src/model/new_city_setup.gd")
const NewTerrain = preload("res://src/model/new_city_terrain.gd")
const LAYOUTS = NewTerrain.LAYOUTS
const RIVER_FEATURES := ["delta", "meander", "crossing", "branch", "rejoin", "valley"]
const OCEAN_FEATURES := ["bay", "delta", "peninsula", "island", "islands", "cliffs"]
const EXCLUSIVE_GROUPS := [["island", "islands", "peninsula"],
	[
		"plateau",
		"ridge",
		"rolling",
		"basin",
	], ["valley", "canyon", "basin"], ["lake", "lakes"], ["plateau", "island"], ["plateau", "islands"]]
const FEATURE_TOOLTIPS := {
	"ocean": "Put ocean along the edge of the map.",
	"river": "Put a river across the map.",
	"bay": "Cut a bay into the coast.",
	"meander": "Make the river bend from side to side.",
	"branch": "Split the river into two branches.",
	"rejoin": "Split the river around land, then join it again.",
	"crossing": "Add a second river that flows into the first river.",
	"delta": "Split the river into channels where it flows into the ocean.",
	"lake": "Add one lake.",
	"lakes": "Add two lakes.",
	"plateau": "Raise a large area of high, flat land.",
	"ridge": "Add a long line of high land across the map.",
	"valley": "Put the river in a low valley between higher land.",
	"rolling": "Make low, smooth hills across the map.",
	"basin": "Make a low area with higher land around it.",
	"canyon": "Cut a deep, narrow canyon across the map. A canyon replaces the river.",
	"cliffs": "Put steep, high land along the coast.",
	"island": "Put the land on one island in the ocean. An island has no river.",
	"islands": "Put the land on two islands in the ocean. Islands have no river.",
	"peninsula": "Make a strip of land that goes out into the ocean.",
}

var city_name_input: LineEdit
var rules_tabs: TabBar
var rules_description: Label
var classic_size: Label
var _active_rules := -1
var _multiplayer_setup := false
var _terrain_settings: Array[NewTerrain.Options] = [NewTerrain.Options.new(), NewTerrain.Options.new()]
var game_type_input: OptionButton
var game_type_label: Label
var region_size_input: OptionButton
var region_size_label: Label
var mayor_name_input: LineEdit
var difficulty_input: OptionButton
var year_input: OptionButton
var size_input: OptionButton
var feature_inputs: Dictionary = {}
var generating := false
var generation_revision := 0
var _dragging := false
var _peek := false
var _drag_offset := Vector2.ZERO
var _busy_overlay: BusyOverlay
var _busy_spinner: Control
var done_button: Button
var candidate_valid := false
var visual_preview: NewCityPreviewPresentation
var landscape_background: TextureRect
var ocean_input: CheckBox
var river_input: CheckBox
var hills_input: HSlider
var water_input: HSlider
var trees_input: HSlider
var preview_view: TextureRect
var preview_status: Label
var preview_timer: Timer
var terrain_icons: Dictionary = {}
var control_graphics: CityUiGraphics

@onready var panel: PanelContainer = $Center/NewCityDialog


func _ready() -> void:
	hide()
	landscape_background = TextureRect.new()
	landscape_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	landscape_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	landscape_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	landscape_background.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	landscape_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(landscape_background)
	move_child(landscape_background, 0)
	city_name_input = get_node("Center/NewCityDialog/Content/Body/Fields/CityFields/CityNameRow/CityNameInput")
	mayor_name_input = get_node("Center/NewCityDialog/Content/Body/Fields/CityFields/MayorNameInput")
	difficulty_input = get_node("Center/NewCityDialog/Content/Body/Fields/CityFields/DifficultyInput")
	year_input = get_node("Center/NewCityDialog/Content/Body/Fields/CityFields/YearInput")
	size_input = get_node("Center/NewCityDialog/Content/Body/Fields/CityFields/SizeInput")
	ocean_input = get_node("Center/NewCityDialog/Content/Body/Fields/TerrainFields/OceanRow/OceanInput")
	river_input = get_node("Center/NewCityDialog/Content/Body/Fields/TerrainFields/OceanRow/RiverInput")
	hills_input = get_node("Center/NewCityDialog/Content/Body/Fields/TerrainFields/HillsInputGroup/HillsInput")
	water_input = get_node("Center/NewCityDialog/Content/Body/Fields/TerrainFields/WaterInputGroup/WaterInput")
	trees_input = get_node("Center/NewCityDialog/Content/Body/Fields/TerrainFields/TreesInputGroup/TreesInput")
	var hills_value: Label = get_node("Center/NewCityDialog/Content/Body/Fields/TerrainFields/HillsInputGroup/HillsValue")
	var water_value: Label = get_node("Center/NewCityDialog/Content/Body/Fields/TerrainFields/WaterInputGroup/WaterValue")
	var trees_value: Label = get_node("Center/NewCityDialog/Content/Body/Fields/TerrainFields/TreesInputGroup/TreesValue")
	preview_view = get_node("Center/NewCityDialog/Content/Body/Preview/PreviewFrame/TerrainPreview")
	preview_status = get_node("Center/NewCityDialog/Content/Body/Preview/PreviewStatus")
	preview_timer = get_node("PreviewTimer")
	done_button = $Center/NewCityDialog/Content/Buttons/Start
	_build_region_fields()
	var feature_titles := {"meander": "Meandering River", "delta": "River Delta", "peninsula": "Peninsula",
		"crossing": "Intersecting rivers", "branch": "Forked River",
		"rejoin": "Split and rejoin river", "bay": "Ocean bay", "island": "Single Island", "islands": "Two islands", "plateau": "Plateau",
		"ridge": "Mountain Ridge",
		"valley": "River Valley", "rolling": "Rolling Hills", "basin": "Basin", "canyon": "Canyon", "cliffs": "Coastal Cliffs",
		"lake": "Single Lake", "lakes": "Two Lakes"}
	for key in feature_titles:
		var check := CheckBox.new()
		check.text = feature_titles[key]
		$Center/NewCityDialog/Content/Body/Fields/TerrainFields/OceanRow.add_child(check)
		feature_inputs[key] = check
		check.toggled.connect(_feature_changed.bind(key))
	var feature_grid: GridContainer = $Center/NewCityDialog/Content/Body/Fields/TerrainFields/OceanRow
	var ordered_checks := [ocean_input, feature_inputs.bay, river_input, feature_inputs.meander,
		feature_inputs.branch, feature_inputs.rejoin, feature_inputs.crossing, feature_inputs.delta,
		feature_inputs.lake, feature_inputs.lakes, feature_inputs.plateau, feature_inputs.ridge, feature_inputs.valley,
		feature_inputs.rolling,
		feature_inputs.basin, feature_inputs.canyon, feature_inputs.cliffs,
		feature_inputs.island, feature_inputs.islands, feature_inputs.peninsula]
	for index in ordered_checks.size():
		feature_grid.move_child(ordered_checks[index], index)
	ocean_input.tooltip_text = FEATURE_TOOLTIPS.ocean
	_compact_feature_rows()
	theme_changed.connect(_compact_feature_rows)
	_refresh_feature_constraints()
	ocean_input.minimum_size_changed.connect(_align_features_label)
	_align_features_label()
	visibility_changed.connect(_visibility_changed)
	resized.connect(_clamp_panel)
	_build_busy_overlay()
	$Center/NewCityDialog/Content/Body/Fields/CityFields/CityNameRow/RandomName.pressed.connect(_random_name)
	var title_bar: DialogTitleBar = $Center/NewCityDialog/Content/TitleBar
	title_bar.title_label.text = "New City"
	title_bar.close_requested.connect(cancel_requested.emit)
	size_input.item_selected.connect(func(_index: int) -> void: preview_requested.emit())
	ocean_input.toggled.connect(_feature_changed.bind("ocean"))
	river_input.toggled.connect(_feature_changed.bind("river"))

	for pair in [[hills_input, hills_value], [water_input, water_value], [trees_input, trees_value]]:
		var slider: HSlider = pair[0]
		var label: Label = pair[1]
		label.text = str(roundi(slider.value))
		slider.value_changed.connect(_slider_changed.bind(label))

	$Center/NewCityDialog/Content/Body/Preview/Regenerate.pressed.connect(terrain_regeneration_requested.emit)
	$Center/NewCityDialog/Content/Buttons/Cancel.pressed.connect(cancel_requested.emit)
	$Center/NewCityDialog/Content/Buttons/Start.pressed.connect(build_requested.emit)
	terrain_icons["Hills"] = get_node("Center/NewCityDialog/Content/Body/Fields/TerrainFields/HillsRow/TerrainPreview")
	terrain_icons["Water"] = get_node("Center/NewCityDialog/Content/Body/Fields/TerrainFields/WaterRow/TerrainPreview")
	terrain_icons["Trees"] = get_node("Center/NewCityDialog/Content/Body/Fields/TerrainFields/TreesRow/TerrainPreview")
	hills_input.tooltip_text = "The height of the hills."
	water_input.tooltip_text = "The sea level and the number of streams. With terrain features, rivers are wider and there is more ocean."
	trees_input.tooltip_text = "The number of tree groups."
	set_control_graphics(control_graphics)
	_rules_changed(0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_node_ready():
		panel.modulate.a = 1.0
		_busy_overlay.modulate.a = 1.0
		color.a = 0.22
		_peek = false
		_dragging = false


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if not event.pressed or panel.get_global_rect().has_point(event.position):
				_peek = event.pressed
				panel.modulate.a = 0.0 if _peek else 1.0
				_busy_overlay.modulate.a = panel.modulate.a
				color.a = 0.0 if _peek else 0.22
				get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			var title: DialogTitleBar = $Center/NewCityDialog/Content/TitleBar
			if (event.pressed
					and title.get_global_rect().has_point(event.position)
					and not title.close_button.get_global_rect().has_point(event.position)):
				_dragging = true
				_drag_offset = event.position - panel.global_position
				get_viewport().set_input_as_handled()
			elif not event.pressed and _dragging:
				_dragging = false
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging:
		panel.global_position = event.position - _drag_offset
		_clamp_panel()
		get_viewport().set_input_as_handled()
	if _peek:
		get_viewport().set_input_as_handled()


func reset_fields(default_mayor: String) -> void:
	game_type_input.select(0)
	region_size_input.select(1)
	_region_type_changed(0)
	preview_view.texture = null
	landscape_background.texture = null
	if is_instance_valid(visual_preview):
		visual_preview.queue_free()
		visual_preview = null
	_terrain_settings = [NewTerrain.Options.new(), NewTerrain.Options.new()]
	_active_rules = -1
	_multiplayer_setup = false
	rules_tabs.set_tab_disabled(0, false)
	rules_tabs.set_block_signals(true)
	rules_tabs.current_tab = 0
	rules_tabs.set_block_signals(false)
	_rules_changed(0)
	city_name_input.text = "New City"
	mayor_name_input.text = default_mayor
	difficulty_input.select(0)
	year_input.select(0)
	reset_features()
	ocean_input.button_pressed = NewTerrain.DEFAULT_OCEAN
	river_input.button_pressed = NewTerrain.DEFAULT_RIVER
	hills_input.value = NewTerrain.DEFAULT_HILLS
	water_input.value = NewTerrain.DEFAULT_WATER
	trees_input.value = NewTerrain.DEFAULT_TREES


func focus_city_name() -> void:
	city_name_input.grab_focus()
	city_name_input.select_all()


func _build_region_fields() -> void:
	var fields := city_name_input.get_parent().get_parent()
	var label := Label.new()
	label.text = "Game type"
	game_type_label = label
	game_type_input = OptionButton.new()
	game_type_input.add_item("Single city")
	game_type_input.add_item("Region (Expanded)")
	region_size_label = Label.new()
	region_size_label.text = "Region size"
	region_size_input = OptionButton.new()
	for edge in RegionRules.SIZES:
		region_size_input.add_item("%d × %d" % [edge, edge], edge)
	region_size_input.select(1)
	var controls := [label, game_type_input, region_size_label, region_size_input]
	for index in controls.size():
		fields.add_child(controls[index])
		fields.move_child(controls[index], index)
	classic_size = Label.new()
	classic_size.text = "128 × 128"
	fields.add_child(classic_size)
	fields.move_child(classic_size, size_input.get_index() + 1)
	var content := $Center/NewCityDialog/Content
	rules_tabs = TabBar.new()
	rules_tabs.focus_mode = Control.FOCUS_ALL
	rules_tabs.add_tab("Classic")
	rules_tabs.add_tab("Expanded")
	rules_tabs.tab_alignment = TabBar.ALIGNMENT_CENTER
	rules_tabs.tab_changed.connect(_rules_changed)
	content.add_child(rules_tabs)
	content.move_child(rules_tabs, 1)
	rules_description = Label.new()
	rules_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rules_description.theme_type_variation = "HelpLabel"
	content.add_child(rules_description)
	content.move_child(rules_description, 2)
	game_type_input.item_selected.connect(_region_type_changed)


func _rules_changed(index: int) -> void:
	if _active_rules >= 0 and _active_rules != index:
		_terrain_settings[_active_rules] = terrain_options()
	_active_rules = index
	var expanded := index == 1
	var terrain := _terrain_settings[index]
	for item in size_input.item_count:
		size_input.set_item_disabled(item, not expanded and size_input.get_item_id(item) != 128)
	size_input.select(size_input.get_item_index(terrain.size if expanded else 128))
	ocean_input.set_pressed_no_signal(terrain.ocean)
	river_input.set_pressed_no_signal(terrain.river)
	hills_input.set_value_no_signal(terrain.hills)
	water_input.set_value_no_signal(terrain.water)
	trees_input.set_value_no_signal(terrain.trees)
	for key in feature_inputs:
		feature_inputs[key].set_pressed_no_signal(expanded and key in terrain.features)
		feature_inputs[key].visible = expanded
	size_input.visible = expanded
	classic_size.visible = not expanded
	$Center/NewCityDialog/Content/Body/Preview/ExpandedFeatures.visible = expanded
	mayor_name_input.visible = expanded
	$Center/NewCityDialog/Content/Body/Fields/CityFields/MayorNameLabel.visible = expanded
	$Center/NewCityDialog/Content/Body/Fields/CityFields/CityNameRow/RandomName.visible = expanded
	game_type_input.visible = expanded and not _multiplayer_setup
	game_type_label.visible = game_type_input.visible
	game_type_input.set_item_disabled(1, not expanded)
	if not expanded:
		game_type_input.select(0)
	rules_description.text = ("Classic features plus larger maps, regions, additional terrain types, metropolis rewards, building upgrades and a ten-year city chronicle."
		if expanded else "Original city rules, 128 × 128 tiles and classic terrain generation.")
	_region_type_changed(game_type_input.selected)
	_refresh_feature_constraints()
	preview_requested.emit()
	_center_panel.call_deferred()


func _region_type_changed(index: int) -> void:
	var region := _active_rules == 1 and not _multiplayer_setup and index == 1
	region_size_label.visible = region
	region_size_input.visible = region


func region_edge() -> int:
	return region_size_input.get_selected_id() if _active_rules == 1 and not _multiplayer_setup and game_type_input.selected == 1 else 0


func set_multiplayer_setup(value: bool, region_campaign := false) -> void:
	# Competitive Region is configured in the lobby for all players together.
	_multiplayer_setup = value
	rules_tabs.set_tab_disabled(0, value and region_campaign)
	if value:
		game_type_input.select(0)
	if value and region_campaign:
		rules_tabs.current_tab = 1
	game_type_input.visible = _active_rules == 1 and not value
	game_type_label.visible = game_type_input.visible
	_region_type_changed(game_type_input.selected)


func setup_options() -> SetupOptions:
	var options := SetupOptions.new()
	options.expanded = _active_rules == 1
	options.city_name = city_name_input.text
	options.mayor_name = mayor_name_input.text
	options.difficulty = difficulty_input.get_selected_id()
	options.starting_year = year_input.get_selected_id()
	return options


func terrain_options() -> NewCityTerrain.Options:
	var options := NewCityTerrain.Options.new()
	options.features.assign(selected_features())
	options.smooth_slopes = _active_rules == 1
	options.size = size_input.get_selected_id()
	options.ocean = ocean_input.button_pressed
	options.river = river_input.button_pressed
	options.hills = roundi(hills_input.value)
	options.water = roundi(water_input.value)
	options.trees = roundi(trees_input.value)
	return OriginalCompatibility.terrain_options(options, _active_rules != 1)


func show_preview(landscape: Image, minimap: Image, status: String, artwork := false) -> void:
	if visual_preview == null:
		landscape_background.texture = (HdArtworkTexture.create(landscape, landscape.get_size()) if artwork
			else PixelArtTexture.wrap(ImageTexture.create_from_image(landscape)))
	preview_view.texture = PixelArtTexture.wrap(ImageTexture.create_from_image(minimap))
	candidate_valid = true
	done_button.disabled = false
	preview_status.text = status


func _slider_changed(value: float, label: Label) -> void:
	label.text = str(roundi(value))
	preview_requested.emit()


func set_control_graphics(graphics: CityUiGraphics) -> void:
	control_graphics = graphics

	for label in terrain_icons:
		var role: String = { "Hills": "hills", "Water": "water_amount", "Trees": "trees_amount" }[label]
		var image: Image = null if graphics == null else graphics.terrain_icon(role)
		var view: TextureRect = terrain_icons[label]
		view.texture = null
		view.visible = image != null

		if image != null:
			image.convert(Image.FORMAT_RGBA8)
			var background := image.get_pixel(0, 0)

			for y in image.get_height():
				for x in image.get_width():
					if image.get_pixel(x, y).is_equal_approx(background):
						image.set_pixel(x, y, Color.TRANSPARENT)

			view.texture = PixelArtTexture.wrap(ImageTexture.create_from_image(image))


func invalidate() -> void:
	candidate_valid = false
	generation_revision += 1
	done_button.disabled = true
	preview_status.text = "Settings changed. Click Regenerate Terrain."


func _random_name() -> void:
	var selected := selected_features()
	var feature := "classic"
	for key in ["islands", "island", "lake", "lakes", "plateau", "ridge", "valley", "rolling", "basin", "canyon", "cliffs", "delta",
		"peninsula", "bay", "meander", "rejoin", "branch", "crossing"]:
		if key in selected:
			feature = key
			break
	city_name_input.text = CityNameGenerator.generate(feature)


func selected_features() -> Array[String]:
	var result: Array[String] = []
	if _active_rules != 1:
		return result
	for key in feature_inputs:
		if feature_inputs[key].button_pressed:
			result.append(key)
	return result


func reset_features() -> void:
	for check in feature_inputs.values():
		check.set_pressed_no_signal(false)
	_feature_changed(false, "")


func _feature_changed(enabled: bool, key: String) -> void:
	if enabled:
		for group in EXCLUSIVE_GROUPS:
			if key in group:
				for other in group:
					if other != key:
						feature_inputs[other].set_pressed_no_signal(false)
		if key in ["island", "islands", "canyon"]:
			river_input.set_pressed_no_signal(false)
			for dependent in RIVER_FEATURES:
				feature_inputs[dependent].set_pressed_no_signal(false)
		if key == "river" or key in RIVER_FEATURES:
			feature_inputs.canyon.set_pressed_no_signal(false)
		if key in RIVER_FEATURES:
			river_input.set_pressed_no_signal(true)
		if key in OCEAN_FEATURES:
			ocean_input.set_pressed_no_signal(true)
	elif key in ["ocean", "river"]:
		for dependent in (OCEAN_FEATURES if key == "ocean" else RIVER_FEATURES):
			feature_inputs[dependent].set_pressed_no_signal(false)
	_refresh_feature_constraints()
	preview_requested.emit()


func _refresh_feature_constraints() -> void:
	var island_key := "island" if feature_inputs.island.button_pressed else "islands"
	var island: bool = feature_inputs[island_key].button_pressed
	var canyon: bool = feature_inputs.canyon.button_pressed
	var river_blocker: String = "Canyon" if canyon else (feature_inputs[island_key].text if island else "")
	river_input.disabled = not river_blocker.is_empty()
	river_input.tooltip_text = _feature_tooltip("river", river_blocker)
	for key in feature_inputs:
		var reason := ""
		if (island or canyon) and key in RIVER_FEATURES:
			reason = river_blocker
		for group in EXCLUSIVE_GROUPS:
			if key in group:
				for other in group:
					if other != key and feature_inputs[other].button_pressed:
						reason = feature_inputs[other].text
		var check: CheckBox = feature_inputs[key]
		check.disabled = not reason.is_empty()
		check.tooltip_text = _feature_tooltip(key, reason)


# the feature description, then why it is unavailable or what it also enables
func _feature_tooltip(key: String, blocker: String) -> String:
	var lines: Array[String] = [FEATURE_TOOLTIPS[key]]

	if not blocker.is_empty():
		lines.append("Unavailable while %s is selected. Clear it first." % blocker)
	else:
		if key in RIVER_FEATURES:
			lines.append("Also enables River.")

		if key in OCEAN_FEATURES:
			lines.append("Also enables Ocean.")

	return "\n".join(lines)


func _build_busy_overlay() -> void:
	_busy_overlay = BusyOverlay.new("Generating…")
	add_child(_busy_overlay)
	_busy_spinner = _busy_overlay.spinner


func set_generating(value: bool) -> void:
	generating = value
	_busy_overlay.visible = value
	if value:
		preview_status.text = "Generating…"
		_busy_overlay.show_city(tr("Generating…"), null, "", -1.0)


func update_generation_progress(fraction: float) -> void:
	if generating and _busy_overlay.city_progress != null:
		_busy_overlay.city_progress.show_progress(tr("Generating…"), "", fraction)


func _visibility_changed() -> void:
	panel.modulate.a = 1.0
	_busy_overlay.modulate.a = 1.0
	color.a = 0.22
	_peek = false
	_dragging = false
	if visible:
		panel.reset_size()
		panel.position = ((size - panel.size) * 0.5).round()
		_center_panel.call_deferred()


func _center_panel() -> void:
	panel.reset_size()
	panel.position = ((size - panel.size) * 0.5).round()
	_clamp_panel()


func _clamp_panel() -> void:
	if panel == null:
		return
	panel.position = panel.position.clamp(Vector2.ZERO, (size - panel.size).max(Vector2.ZERO)).round()


func _align_features_label() -> void:
	var label: Label = $Center/NewCityDialog/Content/Body/Fields/TerrainFields/FeaturesLabel
	label.custom_minimum_size.y = ocean_input.get_combined_minimum_size().y


func _compact_feature_rows() -> void:
	for check in ocean_input.get_parent().get_children():
		for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
			var style: StyleBox = check.get_theme_stylebox(state).duplicate()
			style.content_margin_top = 1
			style.content_margin_bottom = 1
			check.add_theme_stylebox_override(state, style)


class SetupOptions extends RefCounted:
	var expanded := false
	var city_name := ""
	var mayor_name := ""
	var difficulty := 0
	var starting_year := 0

func set_visual_preview(result: NewCityTerrainSession.PreviewResult, palette: Sc2Palette, sprites: Sc2SpriteArchive, view_size: int, options: Dictionary, indexed: Image = null, prepared: Dictionary = {}) -> void:
	if is_instance_valid(visual_preview):
		remove_child(visual_preview)
		visual_preview.queue_free()
	landscape_background.texture = null
	visual_preview = NewCityPreviewPresentation.new()
	add_child(visual_preview)
	move_child(visual_preview, 1)
	visual_preview.setup(result, palette, sprites, view_size, options, indexed, prepared)
