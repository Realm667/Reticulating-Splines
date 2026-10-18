class_name AppUiThemeDefinitions
extends RefCounted

const LIGHT_ACCENT := Color("256a97")
const LIGHT_SELECTION := Color("dceaf3")


static func build(value: String, _files := false, translucent_menus := true) -> Theme:
	if value == "classic_mac":
		return AppUiMacTheme.build()
	if value in ["classic_windows", "classic_dos"]:
		return AppUiClassicTheme.build(value)
	var dark := value == "dark"
	var result := _website_theme(dark)
	result.set_color("default_color", "RichTextLabel", result.get_color("font_color", "Label"))

	for icon_name in ["checked", "unchecked", "checked_disabled", "unchecked_disabled"]:
		var border := Color("555c66") if dark else Color("383838")

		if "disabled" in icon_name:
			border = Color("848e9a") if dark else Color("606060")

		var icon := result.get_icon(icon_name, "CheckBox") if result.has_icon(icon_name, "CheckBox") \
				else ThemeDB.get_default_theme().get_icon(icon_name, "CheckBox")
		result.set_icon(icon_name, "CheckBox", _bordered_check_box(icon, border))

	# spinbox has separate arrow buttons; button icon colors do not reach them
	for direction in ["up", "down"]:
		for state in ["", "_hover", "_pressed", "_disabled"]:
			var ink := Color("e0e5eb") if dark else Color("303030")

			if state == "_disabled":
				ink.a = 0.45

			result.set_color(direction + state + "_icon_modulate", "SpinBox", ink)

		for state in ["", "_hovered", "_pressed", "_disabled"]:
			var background := Color("1a1a1a") if dark else Color("edf0f2")

			if state == "_hovered":
				background = Color("343a42") if dark else Color("e0e6eb")
			elif state == "_pressed":
				background = Color("3c4526") if dark else LIGHT_SELECTION

			result.set_stylebox(direction + "_background" + state, "SpinBox", create_box(background, Color.TRANSPARENT, 0, 0, 0))

	# map keys remain readable over city artwork, independent of the ui theme
	result.set_type_variation("MapLegend", "Panel")
	var legend := create_box(Color(0.06, 0.08, 0.12, 0.78 if translucent_menus else 1.0), Color.TRANSPARENT, 0, 12, 12)
	legend.set_corner_radius_all(6)
	result.set_stylebox("panel", "MapLegend", legend)
	result.set_color("font_color", "MapLegend", Color("eeeeee"))

	var tooltip := create_box(Color(0.03, 0.04, 0.05, 0.80 if translucent_menus else 1.0), Color.TRANSPARENT, 0, 7, 5)
	tooltip.set_corner_radius_all(3)
	result.set_stylebox("panel", "TooltipPanel", tooltip)
	result.set_color("font_color", "TooltipLabel", Color.WHITE)

	# godot's file toolbar and menubutton have their own native theme types
	for type_name in ["MenuButton", "FlatButton", "FlatMenuButton"]:
		if type_name != "MenuButton":
			result.set_type_variation(type_name, "Button")

		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
			result.set_stylebox(state, type_name, result.get_stylebox(state, "Button") if result.has_stylebox(state, "Button")
					else ThemeDB.get_default_theme().get_stylebox(state, "Button"))

		for color_name in result.get_color_list("Button"):
			result.set_color(color_name, type_name, result.get_color(color_name, "Button"))
		if type_name == "MenuButton":
			for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
				var box := _copy_style(result, type_name, state)
				box.content_margin_left = 3
				box.content_margin_right = 3
				result.set_stylebox(state, type_name, box)

	result.set_type_variation("ArtworkButton", "Button")

	for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		result.set_color("icon_" + state + "_color", "ArtworkButton", Color.WHITE)

	result.set_type_variation("HelpLabel", "Label")
	result.set_color("font_color", "HelpLabel", Color("ccd3db") if dark else Color("505050"))
	result.set_type_variation("WarningLabel", "Label")
	result.set_color("font_color", "WarningLabel", Color("ffcf70") if dark else Color("805000"))
	result.set_type_variation("ErrorLabel", "Label")
	result.set_color("font_color", "ErrorLabel", Color("ff7777") if dark else Color("d02020"))
	result.set_type_variation("SuccessLabel", "Label")
	result.set_color("font_color", "SuccessLabel", Color("64db99") if dark else Color("16803a"))

	result.set_color("error", "AppPalette", Color("ff7777") if dark else Color("d02020"))
	result.set_color("warning", "AppPalette", Color("ffcf70") if dark else Color("805000"))
	result.set_color("map_canvas", "AppPalette", Color("202830"))
	result.set_color("canvas", "AppPalette", Color("292d33") if dark else Color("edf0f2"))
	result.set_color("ink", "AppPalette", Color("e0e5eb") if dark else Color("252c34"))
	result.set_color("paper", "AppPalette", Color("1a1a1a") if dark else Color.WHITE)
	result.set_color("chart_accent", "AppPalette", Color("dcf85e") if dark else LIGHT_ACCENT)
	result.set_color("grid", "AppPalette", Color("41474f") if dark else Color("ccd3da"))
	result.set_color("border", "AppPalette", Color("555c66") if dark else Color("9aa4af"))

	# preserve scene layout padding while sharing the approved panel appearance
	for entry in [
		["PanelPadding0_0_0_0", 0, 0, 0, 0],
		["PanelPadding44_34_44_34", 44, 34, 44, 34],
		["PanelPadding5_2_5_2", 5, 2, 5, 2],
		["PanelPadding5_3_5_3", 5, 3, 5, 3],
		["PanelPadding8_8_8_8", 8, 8, 8, 8],
	]:
		result.set_type_variation(entry[0], "PanelContainer")
		var box := _copy_style(result, "PanelContainer", "panel")
		box.content_margin_left = entry[1]
		box.content_margin_top = entry[2]
		box.content_margin_right = entry[3]
		box.content_margin_bottom = entry[4]
		result.set_stylebox("panel", entry[0], box)

	result.set_type_variation("FloatingPanel", "PanelPadding8_8_8_8")
	var floating := _copy_style(result, "PanelPadding8_8_8_8", "panel")
	floating.shadow_color = Color(0, 0, 0, 0.5 if dark else 0.3)
	floating.shadow_size = 18
	floating.shadow_offset = Vector2(0, 6)
	result.set_stylebox("panel", "FloatingPanel", floating)
	result.set_type_variation("MainMenuPanel", "PanelContainer")
	var menu := _copy_style(result, "PanelPadding44_34_44_34", "panel")
	# the shared glass shader mixes these tints with the blurred city background
	menu.set_border_width_all(0)
	menu.bg_color.a = (0.68 if dark else 0.75) if translucent_menus else 1.0
	result.set_stylebox("panel", "MainMenuPanel", menu)

	result.set_type_variation("CityToolbarPanel", "Panel")
	var toolbar := _copy_style(result, "PanelPadding5_3_5_3", "panel")
	toolbar.bg_color.a = (0.78 if dark else 0.75) if translucent_menus else 1.0
	toolbar.border_width_left = 0
	toolbar.border_width_top = 0
	toolbar.border_width_bottom = 0
	result.set_stylebox("panel", "CityToolbarPanel", toolbar)

	result.set_type_variation("CityMenuBarPanel", "PanelContainer")
	var menu_bar := _copy_style(result, "PanelPadding5_2_5_2", "panel")
	menu_bar.border_width_top = 0
	menu_bar.border_width_left = 0
	menu_bar.border_width_right = 0
	result.set_stylebox("panel", "CityMenuBarPanel", menu_bar)

	result.set_type_variation("CityStatusBarPanel", "PanelContainer")
	var status_bar := _copy_style(result, "PanelPadding5_3_5_3", "panel")
	status_bar.border_width_bottom = 0
	status_bar.border_width_left = 0
	status_bar.border_width_right = 0
	result.set_stylebox("panel", "CityStatusBarPanel", status_bar)

	_apply_shared_layout(result, dark)
	# Explicit action roles keep their existing position and signal connections.
	for role in ["PrimaryButton", "SecondaryButton"]:
		result.set_type_variation(role, "Button")
		result.set_font("font", role, _website_font(600))
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			var box := _copy_style(result, "Button", state)
			if state != "disabled":
				box.bg_color = (Color("dcf85e") if dark else LIGHT_ACCENT) if role == "PrimaryButton" else Color("367074")
				if state == "hover":
					box.bg_color = box.bg_color.lightened(0.1)
				elif state in ["pressed", "hover_pressed"]:
					box.bg_color = box.bg_color.darkened(0.1)
				box.border_color = box.bg_color
			result.set_stylebox(state, role, box)
		for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
			result.set_color(color_name, role, Color("1a1a1a") if role == "PrimaryButton" and dark else Color.WHITE)

	result.set_type_variation("ToolbarArtworkButton", "ArtworkButton")
	# Neutral cool gray supports the matte edges of original toolbar art.
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var box := _copy_style(result, "Button", state)
		if state != "focus":
			box.bg_color = Color("717479")
			if state == "hover":
				box.bg_color = box.bg_color.lightened(0.12)
		result.set_stylebox(state, "ToolbarArtworkButton", box)

	# Icon-only category buttons need more artwork space than text buttons.
	# Keep the zoom/rotation buttons and their native icon sizing unchanged.
	result.set_type_variation("ToolbarCategoryButton", "ToolbarArtworkButton")
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var box := _copy_style(result, "ToolbarArtworkButton", state)
		box.set_content_margin_all(3)
		result.set_stylebox(state, "ToolbarCategoryButton", box)
	return result


static func _apply_shared_layout(result: Theme, dark: bool) -> void:
	# Common rhythm, readable fields and keyboard focus across both themes.
	for type_name in ["HBoxContainer", "VBoxContainer"]:
		result.set_constant("separation", type_name, 8)
	result.set_constant("h_separation", "GridContainer", 10)
	result.set_constant("v_separation", "GridContainer", 8)
	result.set_type_variation("DialogMargin", "MarginContainer")
	for side in ["left", "top", "right", "bottom"]:
		result.set_constant("margin_" + side, "DialogMargin", 12)
	result.set_type_variation("SectionHeading", "Label")
	result.set_font("font", "SectionHeading", result.get_font("title_font", "Window"))
	result.set_font_size("font_size", "SectionHeading", 16)
	result.set_color("font_color", "SectionHeading", result.get_color("ink", "AppPalette"))
	result.set_type_variation("InformationPanel", "PanelContainer")
	result.set_stylebox("panel", "InformationPanel", create_box(Color("355265") if dark else Color("dce8ee"), Color.TRANSPARENT, 0, 14, 14))
	result.set_type_variation("NavigationButton", "Button")
	result.set_font("font", "NavigationButton", _website_font(500))
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var active: bool = state in ["pressed", "hover_pressed"]
		var color := (Color("355265") if dark else Color("dce8ee")) if active else Color.TRANSPARENT
		if state == "hover":
			color = Color("343e49") if dark else Color("e0e7eb")
		var box := create_box(color, Color("dcf85e") if dark else LIGHT_ACCENT, 0, 12, 7)
		box.border_width_left = 3 if active else 0
		result.set_stylebox(state, "NavigationButton", box)
		result.set_color("font_" + state + "_color" if state != "normal" else "font_color", "NavigationButton", result.get_color("ink", "AppPalette"))
	result.set_type_variation("UtilityPanel", "PanelContainer")
	result.set_stylebox("panel", "UtilityPanel", create_box(result.get_color("canvas", "AppPalette"),
		result.get_color("border", "AppPalette"), 1, 14, 14))
	var focus := create_box(Color.TRANSPARENT, Color("dcf85e") if dark else LIGHT_ACCENT, 2, 0, 0)
	focus.set_corner_radius_all(3)
	for type_name in ["Button", "OptionButton", "LineEdit", "TextEdit", "ItemList", "Tree"]:
		result.set_stylebox("focus", type_name, focus)
	for type_name in ["CheckBox", "CheckButton", "TabBar", "TabContainer"]:
		result.set_stylebox("tab_focus" if type_name.begins_with("Tab") else "focus", type_name, focus)
	for type_name in ["Button", "OptionButton"]:
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			var box := _copy_style(result, type_name, state)
			box.content_margin_left = 8
			box.content_margin_right = 8
			box.content_margin_top = 5
			box.content_margin_bottom = 5
			result.set_stylebox(state, type_name, box)


# Website demo/04 palette. Only presentation changes; scene layouts stay intact.
static func _website_theme(dark: bool) -> Theme:
	var result := ThemeDB.get_default_theme().duplicate() as Theme
	var surface := (Color("292d33") if dark else Color("edf0f2"))
	var inset := (Color("1a1a1a") if dark else Color("ffffff"))
	var border := (Color("555c66") if dark else Color("9aa4af"))
	var ink := (Color("e0e5eb") if dark else Color("252c34"))
	var accent := Color("dcf85e") if dark else LIGHT_ACCENT
	var font := _website_font()
	var heading := _website_font(800)
	result.default_font = font
	result.default_font_size = 13
	for type_name in result.get_type_list():
		for font_name in result.get_font_list(type_name):
			if font_name == "mono_font":
				continue
			var weight := 700 if "bold" in font_name or "title" in font_name else 400
			result.set_font(font_name, type_name, _website_font(weight, "italics" in font_name))
		for size_name in result.get_font_size_list(type_name):
			result.set_font_size(size_name, type_name, 13)
		for color_name in result.get_color_list(type_name):
			if color_name.begins_with("font_") and not "outline" in color_name and not "shadow" in color_name:
				result.set_color(color_name, type_name, (Color("8b929b") if dark else Color("727d89")) if "disabled" in color_name else ink)
	# RichTextLabel can fall back to embedded engine fonts unless its slots are explicit.
	for slot in ["normal_font", "bold_font", "italics_font", "bold_italics_font"]:
		result.set_font(slot, "RichTextLabel", _website_font(700 if "bold" in slot else 400, "italics" in slot))
	result.set_font("title_font", "Window", heading)
	# Montserrat is wider than the former font. Keep all existing menu entries
	# and metric fields within the base viewport without moving them.
	result.set_font_size("font_size", "MenuButton", 12)
	# Keep Montserrat descenders inside each popup row, including fractional UI scales.
	result.set_constant("v_separation", "PopupMenu", 8)
	result.set_color("title_color", "Window", ink)
	result.set_color("title_outline_modulate", "Window", Color.TRANSPARENT)
	for type_name in ["Panel", "PanelContainer", "AcceptDialog", "PopupPanel", "PopupMenu", "TabContainer"]:
		var panel := _copy_style(result, type_name, "panel")
		panel.bg_color = surface
		panel.border_color = border
		panel.set_border_width_all(1)
		panel.set_corner_radius_all(0 if type_name in ["AcceptDialog", "PopupPanel", "PopupMenu"] else 3)
		result.set_stylebox("panel", type_name, panel)
	var container := create_box(surface, border, 1, 8, 8)
	container.set_corner_radius_all(3)
	result.set_stylebox("panel", "PanelContainer", container)
	var tab_panel := _copy_style(result, "TabContainer", "panel")
	tab_panel.set_content_margin_all(12)
	result.set_stylebox("panel", "TabContainer", tab_panel)
	for type_name in ["TabContainer", "TabBar"]:
		for state in ["tab_selected", "tab_unselected", "tab_hovered", "tab_disabled"]:
			var tab := _copy_style(result, type_name, state)
			tab.bg_color = (Color("343a42") if dark else Color("e0e6eb")) if state == "tab_hovered" else surface
			tab.border_color = accent if state == "tab_selected" else border
			tab.set_border_width_all(0)
			tab.border_width_bottom = 2 if state == "tab_selected" else 1
			tab.set_corner_radius_all(0)
			result.set_stylebox(state, type_name, tab)
		result.set_color("font_selected_color", type_name, accent if dark else LIGHT_ACCENT)
	for type_name in ["Button", "OptionButton"]:
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			var box := _copy_style(result, type_name, state)
			box.bg_color = inset
			box.border_color = border
			if state == "hover":
				box.bg_color = (Color("343a42") if dark else Color("e0e6eb"))
			elif state in ["pressed", "hover_pressed"]:
				box.bg_color = (Color("3c4526") if dark else LIGHT_SELECTION)
				box.border_color = accent
			elif state == "disabled":
				box.bg_color = surface
			box.set_border_width_all(1)
			box.set_corner_radius_all(3)
			result.set_stylebox(state, type_name, box)
			if type_name == "OptionButton" and state != "hover_pressed":
				result.set_stylebox(state + "_mirrored", type_name, box)
	for type_name in ["CheckBox", "CheckButton"]:
		for color_name in ["checkbox_checked_color", "checkbox_unchecked_color", "button_checked_color", "button_unchecked_color"]:
			result.set_color(color_name, type_name, Color.WHITE)
		for icon_name in result.get_icon_list(type_name):
			var icon := result.get_icon(icon_name, type_name)
			var checked := not "unchecked" in icon_name and "checked" in icon_name
			var tint := accent if checked else (Color("ccd3db") if dark else Color("4c5865"))
			if "disabled" in icon_name:
				tint = (Color("8b929b") if dark else Color("727d89"))
			if icon is DPITexture:
				result.set_icon(icon_name, type_name, _recolored_svg(icon, func(color: Color) -> Color:
					return tint if color.get_luminance() > 0.4 else (Color("1a1a1a") if dark else Color.WHITE), false))
	for type_name in ["LineEdit", "TextEdit"]:
		for state in ["normal", "read_only"]:
			var field := _copy_style(result, type_name, state)
			field.bg_color = inset
			field.border_color = border
			field.set_border_width_all(1)
			field.set_corner_radius_all(3)
			result.set_stylebox(state, type_name, field)
		result.set_color("caret_color", type_name, accent if dark else LIGHT_ACCENT)
		result.set_color("font_placeholder_color", type_name, (Color("ccd3db") if dark else Color("4c5865")))
		result.set_color("selection_color", type_name, Color("367074") if dark else LIGHT_SELECTION)
	for type_name in ["ItemList", "Tree"]:
		var panel := _copy_style(result, type_name, "panel")
		panel.bg_color = inset
		panel.border_color = border
		panel.set_border_width_all(1)
		panel.set_corner_radius_all(3)
		result.set_stylebox("panel", type_name, panel)
		for state in result.get_stylebox_list(type_name):
			if not ("selected" in state or state.begins_with("cursor") or state == "hovered"):
				continue
			var selection := create_box((Color("363f27") if dark else LIGHT_SELECTION), accent, 0, 4, 4)
			selection.border_width_left = 3
			result.set_stylebox(state, type_name, selection)
		result.set_color("font_selected_color", type_name, accent if dark else LIGHT_ACCENT)
		result.set_color("font_hovered_selected_color", type_name, accent if dark else LIGHT_ACCENT)
		result.set_color("guide_color", type_name, (Color("41474f") if dark else Color("ccd3da")))
	result.set_stylebox("hover", "PopupMenu", create_box((Color("363f27") if dark else LIGHT_SELECTION), accent, 0, 4, 4))
	for type_name in ["HSeparator", "VSeparator"]:
		var separator := StyleBoxLine.new()
		separator.color = (Color("41474f") if dark else Color("ccd3da"))
		separator.thickness = 1
		separator.vertical = type_name == "VSeparator"
		result.set_stylebox("separator", type_name, separator)
	for type_name in ["HSlider", "VSlider"]:
		for state in ["grabber_area", "grabber_area_highlight"]:
			var track := _copy_style(result, type_name, state)
			track.bg_color = accent
			track.border_color = accent
			result.set_stylebox(state, type_name, track)
		for icon_name in ["grabber", "grabber_highlight"]:
			result.set_icon(icon_name, type_name, _tinted_icon(result.get_icon(icon_name, type_name), accent))
	result.set_stylebox("background", "ProgressBar", create_box(inset, border, 1, 1, 1))
	result.set_stylebox("fill", "ProgressBar", create_box(accent, accent, 0, 0, 0))
	result.set_color("font_color", "ProgressBar", ink)
	for state in ["embedded_border", "embedded_unfocused_border"]:
		var window := _copy_style(result, "Window", state)
		window.bg_color = surface
		window.border_color = surface
		window.set_corner_radius_all(0)
		window.shadow_color = Color(0, 0, 0, 0.5 if dark else 0.3)
		window.shadow_size = 18
		window.shadow_offset = Vector2(0, 6)
		result.set_stylebox(state, "Window", window)
	if not dark:
		for type_name in ["FileDialog", "OptionButton", "LineEdit", "Tree", "Window", "SpinBox"]:
			for icon_name in result.get_icon_list(type_name):
				result.set_icon(icon_name, type_name, _tinted_icon(result.get_icon(icon_name, type_name), ink))
	return result


static func _website_font(weight := 400, italic := false) -> Font:
	var font := FontVariation.new()
	font.base_font = preload("res://assets/fonts/montserrat/Montserrat.ttf")
	font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	if italic:
		font.variation_transform = Transform2D(Vector2.RIGHT, Vector2(-0.2, 1.0), Vector2.ZERO)
	return AppLocalization.with_fallback(font, weight >= 600)


static func _copy_style(source: Theme, type_name: String, state: String) -> StyleBoxFlat:
	var style := source.get_stylebox(
		state,
		type_name,
	) if source.has_stylebox(state, type_name) else ThemeDB.get_default_theme().get_stylebox(state, type_name)

	return style.duplicate() as StyleBoxFlat


static func _tinted_icon(texture: Texture2D, color: Color) -> Texture2D:
	# keep a scalable icon sharp at every UI scale
	if texture is DPITexture:
		return _recolored_svg(texture, func(_color: Color) -> Color: return color, true)

	var image := texture.get_image()

	if image == null:
		return texture

	var maximum_alpha := 0.0

	for y in image.get_height():
		for x in image.get_width():
			maximum_alpha = maxf(maximum_alpha, image.get_pixel(x, y).a)

	if maximum_alpha == 0.0:
		return texture

	for y in image.get_height():
		for x in image.get_width():
			var pixel := color
			pixel.a *= image.get_pixel(x, y).a / maximum_alpha
			image.set_pixel(x, y, pixel)

	return ImageTexture.create_from_image(image)


# rewrites each SVG color through recolor. full_opacity scales the opacities so
# that the most opaque part is fully opaque, like a tint of the rasterized icon
static func _recolored_svg(texture: DPITexture, recolor: Callable, full_opacity: bool) -> DPITexture:
	var source := texture.get_source()
	var colors := RegEx.create_from_string("#([0-9a-fA-F]{6}|[0-9a-fA-F]{3})\\b")
	source = _replace_matches(source, colors, func(found: RegExMatch) -> String:
		return "#" + (recolor.call(Color.html(found.get_string())) as Color).to_html(false))

	if full_opacity:
		# the drawn icon gives the largest opacity, including parts without an
		# opacity of their own
		var image := texture.get_image()
		var maximum := 0.0

		for y in image.get_height():
			for x in image.get_width():
				maximum = maxf(maximum, image.get_pixel(x, y).a)

		if maximum > 0.0 and maximum < 1.0:
			var opacities := RegEx.create_from_string("(fill-opacity|stroke-opacity|opacity)=\"([0-9.]+)\"")
			source = _replace_matches(source, opacities, func(found: RegExMatch) -> String:
				return "%s=\"%s\"" % [found.get_string(1), minf(1.0, found.get_string(2).to_float() / maximum)])

	return DPITexture.create_from_string(source, texture.base_scale, texture.saturation, texture.color_map)


# outlines the square box so that it stays visible against the panel color
static func _bordered_check_box(texture: Texture2D, border: Color) -> Texture2D:
	if not texture is DPITexture:
		return texture

	var svg := texture as DPITexture
	var source := svg.get_source().replace("<rect ", "<rect stroke=\"#%s\" stroke-width=\"1\" " % border.to_html(false))

	return DPITexture.create_from_string(source, svg.base_scale, svg.saturation, svg.color_map)


static func _replace_matches(text: String, pattern: RegEx, replacement: Callable) -> String:
	var result := ""
	var end := 0

	for found in pattern.search_all(text):
		result += text.substr(end, found.get_start() - end) + str(replacement.call(found))
		end = found.get_end()

	return result + text.substr(end)


static func create_box(
	background: Color,
	border: Color,
	width: int,
	horizontal_margin := 5,
	vertical_margin := 3
) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border
	box.set_border_width_all(width)
	box.content_margin_left = horizontal_margin
	box.content_margin_top = vertical_margin
	box.content_margin_right = horizontal_margin
	box.content_margin_bottom = vertical_margin

	return box
