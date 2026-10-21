extends SceneTree
## Theme persistence, live switching, and lazy windows.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# Headless defaults to a 64px window, which cannot host literal classic 2x UI.
	root.size = Vector2i(1280, 800)
	var path := "user://theme-test-%d.cfg" % OS.get_process_id()
	assert(AppSettingsStore.load_values(path).ui_theme == "dark")
	assert(not AppSettingsStore.load_values(path).dark_underground)
	assert(AppSettingsStore.normalize_theme("invalid") == "dark")
	var config := ConfigFile.new()
	config.set_value("general", "ui_theme", "invalid")
	assert(config.save(path) == OK)
	assert(AppSettingsStore.load_values(path).ui_theme == "dark")
	OS.set_environment("OPENSC2K_ASSET_SOURCE", "original")
	OS.set_environment("OPENSC2K_GRAPHICS_PACK", ProjectSettings.globalize_path("user://missing-test-art"))
	var main := _create_main(path)
	await process_frame
	main.set_process(false)
	main.main_menu.city_background.set_process(false)
	assert(main.city_session.activate_document(EmptyCityTemplate.create(128)))
	main.map_view.city_source = CityMapSource.new(CityIsometricRenderer.output_size_for_view(2, 128))
	main.frame.select_speed(GameSpeedController.Speed.PAUSED)
	var before: PackedByteArray = main.document_state.city.document.serialize().data
	var shared_theme := main.theme
	for selected in [1, 2, 3, 4, 0, 4, 2, 1, 3]:
		main.settings.open_settings_dialog()
		var dialog: AppSettingsDialog = main.main_overlays.settings_dialog
		# a check box change applies at once and shows when Settings next opens
		var dark_underground := not main.preferences.dark_underground
		dialog.dark_underground_check.button_pressed = dark_underground
		assert(main.preferences.dark_underground == dark_underground)
		dialog.hide()
		main.settings.open_settings_dialog()
		assert(dialog.dark_underground_check.button_pressed == dark_underground)
		dialog.theme_selector.select(selected)
		dialog.theme_selector.item_selected.emit(selected)
		dialog.dark_underground_check.button_pressed = true
		main.settings.apply_settings()
		dialog.hide()
		await process_frame
		await process_frame
		assert(AppSettingsStore.load_values(path).dark_underground)
		assert(main.preferences.ui_theme == AppUiTheme.IDS[selected])
		assert(AppSettingsStore.load_values(path).ui_theme == main.preferences.ui_theme)
		assert(main.theme == shared_theme, "Retained windows keep the shared resource")
		assert(main.coop.windows.chat_log.get_theme_font("normal_font") == shared_theme.default_font,
			"An existing chat follows live theme changes")
		assert(dialog.translucent_menus_check.disabled == AppUiTheme.is_classic())
		assert(main.preferences.translucent_menus, "Retro themes preserve the modern transparency preference")
		assert(AppUiTheme.uses_translucency() == not AppUiTheme.is_classic())
		var workspace := main.city_workspace
		var dos := AppUiTheme.selected == "classic_dos"
		assert(workspace.dos_hscroll.visible == dos and workspace.dos_vscroll.visible == dos)
		assert(main.city_menu_bar.dos_city_line.visible == dos)
		if dos:
			var bar := workspace.dos_hscroll
			bar.value = (bar.max_value - bar.page) * 0.6
			var scroll_state := main.map_view.camera.scroll_state()
			assert(is_equal_approx(scroll_state.value.x, bar.value), "DOS scrollbar must control the real camera")
			workspace.set_editor_controls_visible(false)
			assert(not bar.visible and not workspace.dos_vscroll.visible)
			workspace.set_editor_controls_visible(true)
		var toolbar := main.city_toolbar
		assert(toolbar.layers_button.is_visible_in_tree() == AppUiTheme.is_classic())
		if AppUiTheme.is_classic():
			assert(toolbar.get_parent() is ScrollContainer)
			assert(main.map_view.layers.data_key_origin().x + main.map_view.global_position.x >= toolbar.get_global_rect().end.x,
				"The data legend must clear the floating classic palette")
			toolbar.show_layers()
			await process_frame
			assert(toolbar.layers_popup.visible)
			assert(toolbar.data_view_input.is_visible_in_tree())
			assert(toolbar.view_visibility_checks.buildings.is_visible_in_tree())
			var requests: Array = []
			var observe := func(visible: bool, layer: String) -> void: requests.append([visible, layer])
			toolbar.surface_visibility_requested.connect(observe)
			var buildings: CheckBox = toolbar.view_visibility_checks.buildings
			var previous := buildings.button_pressed
			buildings.button_pressed = not previous
			assert(requests.back() == [not previous, "buildings"])
			buildings.button_pressed = previous
			toolbar.surface_visibility_requested.disconnect(observe)
			toolbar.layers_popup.hide()
		else:
			var scroll := toolbar.get_parent() as ScrollContainer
			assert(scroll != null and scroll.is_visible_in_tree())
			assert(scroll.size.y > 0 and scroll.size.y <= main.size.y, "Toolbar stays accessible inside the viewport")
			assert(toolbar.data_view_input.is_visible_in_tree())
		assert(main.document_state.city.document.serialize().data == before)
		var late := FileDialogFactory.city_open()
		main.add_child(late)
		assert(
			late.theme.get_color("font_color", "Label") == AppUiTheme.file_dialog().get_color("font_color", "Label"),
			"New dialogs use the active theme",
		)
		late.free()
	main.scurk_workspace._ensure_scurk_editor()
	main.scurk_editor.show()
	var scurk_menu := main.scurk_editor.get_node("Panel/Content/Toolbar/Actions/Settings") as Button
	scurk_menu.pressed.emit()
	assert(main.main_overlays.settings_dialog.visible and main.scurk_editor.visible)
	main.main_overlays.settings_dialog.hide()
	var scurk_help := main.scurk_editor.get_node("Panel/Content/Toolbar/Actions/About") as Button
	scurk_help.pressed.emit()
	assert(main.main_overlays.about_dialog.visible and main.scurk_editor.visible)
	main.main_overlays.about_dialog.hide()
	assert(main.document_state.city.document.serialize().data == before)
	# Style selection follows the published texture mode, independent of renderer.
	# Actual CPU/GPU pixels belong to dark_underground_shader_test.
	for state in [[CityViewMode.Mode.UNDERGROUND, true, true], [CityViewMode.Mode.UNDERGROUND, false, false],
		[CityViewMode.Mode.CITY, true, false]]:
		main.render_caches.static_render_mode = state[0]
		main.map_view.base_palette_lookup_all = state[1]
		main.preferences.dark_underground = true
		main.menus.sync_map_style()
		assert(main.map_view.dark_underground == state[2])
		assert(main.map_view.layers._base_material.get_shader_parameter("dark_underground") == state[2])
		main.preferences.dark_underground = false
		main.menus.sync_map_style()
		assert(not main.map_view.dark_underground)
		assert(not main.map_view.layers._base_material.get_shader_parameter("dark_underground"))
	assert(main.document_state.city.document.serialize().data == before)
	main.free()
	await process_frame
	var restored := _create_main(path)
	await process_frame
	assert(restored.preferences.ui_theme == "classic_dos")
	assert(restored.preferences.dark_underground)
	restored.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	AppUiTheme.select("light")
	await process_frame
	print("PASS: theme save/cancel/reload, live and lazy themes, renderer flags and unchanged city")
	quit()


func _create_main(settings_path: String) -> CityApplication:
	var main := (load("res://main.tscn") as PackedScene).instantiate() as CityApplication
	main.asset_state.reference_root = ProjectSettings.globalize_path("user://missing-test-originals")
	main.preferences.settings_path = settings_path
	root.add_child(main)
	return main
