extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var bytes := PackedByteArray()
	bytes.resize(SimCityClassicImport.FILE_SIZE)
	bytes[0x0b53] = 48
	bytes[0x0ba6] = 0x30
	bytes[0x0ba7] = 0x39
	_tile(bytes, 4, 8, 66 | 0x8000)
	_tile(bytes, 5, 8, 80)
	_tile(bytes, 6, 8, 67)
	_tile(bytes, 8, 8, 226)
	_tile(bytes, 9, 8, 210)
	_tile(bytes, 11, 8, 261)
	_tile(bytes, 12, 8, 432)
	_tile(bytes, 13, 8, 621)
	_tile(bytes, 15, 8, 750 | 1024)
	_tile(bytes, 20, 8, 2)
	_tile(bytes, 21, 8, 21)
	var original := "user://Classic import fixture %s.CTY" % Crypto.new().generate_random_bytes(6).hex_encode()
	var output := FileAccess.open(original, FileAccess.WRITE)
	assert(output != null)
	var header := PackedByteArray()
	header.resize(128)
	output.store_buffer(header)
	output.store_buffer(bytes)
	output.close()
	var checksum := FileAccess.get_sha256(original)
	assert(SimCityClassicImport.convert_city(bytes.slice(1), "Truncated") == null)
	var imported := SimCityClassicImport.read(original)
	assert(imported != null and imported.is_sc2x())
	assert(imported.city_name() == original.get_file().get_basename())
	var city := CityState.from_document(imported)
	assert(city.funds() == 12345 and city.current_year() == 1901)
	assert(city.building_id(8, 22) == BuildingTileIds.ROAD_STRAIGHT_2)
	assert(city.building_id(9, 22) == BuildingTileIds.ROAD_BRIDGE and city.is_water(9, 22))
	assert(city.building_id(10, 22) == BuildingTileIds.ROAD_STRAIGHT_1)
	assert(city.building_id(12, 22) == BuildingTileIds.RAIL_STRAIGHT_2)
	assert(city.building_id(13, 22) == BuildingTileIds.POWER_LINE_STRAIGHT_2)
	assert(city.zone_id(15, 22) == 2 and city.zone_id(16, 22) == 4 and city.zone_id(17, 22) == 6)
	assert(city.building_id(18, 21) == BuildingTileIds.COAL_POWER and city.building_id(21, 24) == BuildingTileIds.COAL_POWER)
	assert(city.is_water(24, 22) and city.water_altitude(24, 22) > city.land_altitude(24, 22))
	assert(city.building_id(25, 22) == BuildingTileIds.TREES_1)
	assert(city.text_overlay_id(18, 21) != 0)
	var app := load("res://main.tscn").instantiate() as CityApplication
	preload("res://tests/support/app_fixture.gd").configure(app, true)
	root.add_child(app)
	await process_frame
	app.set_process(false)
	var read := app.city_files._read_city(original)
	assert(read.error.is_empty() and read.classic_source == original)
	app.city_files._activate_read_city(read)
	var saved := app.document_state.current_save_path
	assert(saved.get_file().get_extension() == "sc2x")
	assert(Sc2File.load_path(saved).is_valid())
	var first_copy := FileAccess.get_sha256(saved)
	var another := app.city_files._read_city(original)
	assert(app.city_files._save_classic_import(another))
	assert(another.document.source_path != saved and FileAccess.get_sha256(saved) == first_copy)
	assert(FileAccess.get_sha256(original) == checksum)
	app.queue_free()
	await process_frame
	print("PASS: CTY layout, map conversion, normal city activation, verified local copy and collision handling")
	quit()


func _tile(bytes: PackedByteArray, x: int, y: int, tile: int) -> void:
	var offset := SimCityClassicImport.MAP_OFFSET + (x * SimCityClassicImport.HEIGHT + y) * 2
	bytes[offset] = tile >> 8
	bytes[offset + 1] = tile & 255
