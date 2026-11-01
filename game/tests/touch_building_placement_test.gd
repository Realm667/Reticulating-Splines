extends SceneTree
## The first touch previews only; confirmation uses the existing charged command.

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 850)
	var app := load("res://main.tscn").instantiate() as CityApplication
	preload("res://tests/support/app_fixture.gd").configure(app, true)
	root.add_child(app)
	await process_frame
	app.set_process(false)
	var document: Sc2File = Sc2xDocument.create_empty(128, "Touch building fixture").document
	document.set_misc_i32(Sc2MiscLayout.FUNDS, 100000)
	assert(app.city_session.activate_document(document))
	app.interface.hide_main_menu()
	app.frame.select_speed(GameSpeedController.Speed.PAUSED)
	app.current_tool.select_tool_group(CityToolIds.Group.SERVICES)
	app.current_tool.select_subtool(CityToolIds.Services.FIRE_STATION)
	var map := app.map_view
	map.navigation.allowed = Callable()
	map.zoom_factor = 1.0
	assert(map.edit_enabled and map.touch_placement_tool >= 0 and map.placement_ghost_provider.is_valid())
	map.center_on_tile(Vector2i(64, 64))
	var point := map.camera._camera_rect().get_center()
	var before := document.serialize().data as PackedByteArray
	var funds := app.document_state.city.funds()
	_contact(map, point, true)
	var drag := InputEventScreenDrag.new()
	drag.index = 3
	drag.position = point + Vector2(32, 16)
	map.interaction._gui_input(drag)
	_contact(map, drag.position, false)
	var selected := map.navigation.placement_tile()
	assert(selected.x >= 0 and document.serialize().data == before and app.document_state.city.funds() == funds,
		"Previewing cannot mutate the city or charge money")
	var ghost: CityDynamicVisual = map.placement_ghost_provider.call(selected)
	assert(ghost != null and ghost.texture != null and ghost.size.x > 32 and ghost.size.y > 0,
		"Fixed buildings must supply their actual graphical footprint")
	assert(map.placement_ghost_provider.call(selected).texture == ghost.texture, "Dragging reuses the decoded artwork")
	_contact(map, point, true)
	assert(app.document_state.city.funds() == funds)
	_contact(map, point, false)
	assert(app.document_state.city.building_id(selected.x, selected.y) == BuildingTileIds.FIRE_STATION)
	var price := int(ToolCatalog.tool(CityToolIds.Group.SERVICES, CityToolIds.Services.FIRE_STATION).cost)
	assert(app.document_state.city.funds() == funds - price, "Confirmation executes the existing building charge exactly once")
	assert(map.navigation.placement_tile().x < 0)
	app.current_tool.select_tool_group(CityToolIds.Group.ROADS)
	assert(map.touch_placement_tool < 0, "Road selection must restore direct one-finger drawing")
	app.queue_free()
	await process_frame
	print("PASS touch building: retained real-art preview, no early mutation, one normal charged placement")
	quit()


func _contact(map: CityMapControl, point: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 3
	event.position = point
	event.pressed = pressed
	map.interaction._input(event)
	map.interaction._gui_input(event)
