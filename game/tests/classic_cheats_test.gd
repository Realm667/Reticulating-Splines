extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _key(letter: String, pressed := true) -> InputEventKey:
	var event := InputEventKey.new()
	event.unicode = letter.unicode_at(0)
	event.keycode = letter.to_upper().unicode_at(0)
	event.physical_keycode = event.keycode
	event.pressed = pressed
	return event


func _run() -> void:
	_check_input()
	_check_singleplayer()
	_check_bonds()
	_check_churches()
	print("PASS: direct desktop cheat input, multiplayer rejection, safe bonds and church footprints")
	quit()


func _check_input() -> void:
	for code in ClassicCheatInput.CODES:
		var input := ClassicCheatInput.new()
		var matches: Array[String] = []
		var now := 1
		for letter in code.to_upper():
			assert(input.feed(_key(letter), now))
			if not input.completed.is_empty():
				matches.append(input.completed)
			input.feed(_key(letter, false), now + 10)
			now += 100
		assert(matches == [code] or (code == "pirntopsguzzardo" and matches == ["pirn", "topsguzzardo"]))
		assert(input.released.is_empty(), "Successful codes must not trigger shortcuts")
	for code in ["vers", "memy", "test", "porn", "klatu verata nictu", "joke", "hell"]:
		var input := ClassicCheatInput.new()
		for letter in code:
			input.feed(_key(letter), 1)
			assert(input.completed.is_empty())
	var input := ClassicCheatInput.new()
	assert(input.feed(_key("g"), 100))
	assert(input.feed(_key("g", false), 120))
	input.expire(100 + ClassicCheatInput.FIRST_KEY_MSEC)
	assert(input.released.size() == 2 and input.released[0].pressed and not input.released[1].pressed)
	input.clear()
	assert(input.feed(_key("d"), 0))
	var held := _key("d")
	held.echo = true
	assert(not input.feed(held, 100) and input.released.size() == 1)
	input.clear()
	assert(input.feed(_key("c"), 0))
	assert(not input.feed(_key("x"), 50) and input.buffer.is_empty() and input.released.size() == 1)
	input.clear()
	var modified := _key("c")
	modified.ctrl_pressed = true
	assert(not input.feed(modified, 0) and input.pending.is_empty())
	assert(not input.feed(_key("c"), 0, true), "Only vaudeville is a SCURK code")
	assert(input.feed(_key("v"), 0, true))
	input.clear()
	input.expire(9999)
	assert(input.released.is_empty(), "Focus changes discard pending keys")


func _check_singleplayer() -> void:
	var document := EmptyCityTemplate.create(128)
	var session := CoopSession.new()
	assert(ClassicCheatActions.allowed(document, null))
	assert(ClassicCheatActions.allowed(document, session))
	for flag in ["active", "hosting", "connected", "waiting_for_start"]:
		session.set(flag, true)
		assert(not ClassicCheatActions.allowed(document, session), flag)
		session.set(flag, false)
	assert(not ClassicCheatActions.allowed(document, session, true))
	document.sc2x_extra_entries["multiplayer.json"] = "{}".to_utf8_buffer()
	assert(not ClassicCheatActions.allowed(document, null))
	assert(not ClassicCheatActions.allowed(null, null))
	session.free()


func _check_bonds() -> void:
	var city := CityState.from_document(EmptyCityTemplate.create(128))
	var funds := city.funds()
	assert(ClassicCheatActions.issue_expensive_bond(city))
	assert(city.funds() == funds + 10000)
	assert(city.document.misc_u32(Sc2MiscLayout.BONDS) == 1)
	assert(city.document.misc_u32(Sc2MiscLayout.BOND_RATES) == 25)
	var budget := Sc2MiscLayout.BUDGETS + Sc2BudgetLayout.BONDS * Sc2BudgetLayout.RECORD_SIZE
	assert(city.document.misc_u32(budget + Sc2BudgetLayout.CURRENT) == 1)
	assert(city.document.misc_u32(budget + Sc2BudgetLayout.FUNDING) == 250000)
	var repaid := BondCommand.repay(city, BondCommand.CONFIRMATION_CONFIRMED)
	assert(repaid.ok and repaid.changed and city.funds() == funds)
	for i in 50:
		assert(ClassicCheatActions.issue_expensive_bond(city))
	var before := city.document.find_chunk("MISC").decoded_payload.duplicate()
	assert(not ClassicCheatActions.issue_expensive_bond(city))
	assert(city.document.find_chunk("MISC").decoded_payload == before)
	city.document.set_misc_u32(Sc2MiscLayout.BONDS, 0)
	city.set_funds(CityDebugActions.MAX_FUNDS)
	assert(not ClassicCheatActions.issue_expensive_bond(city) and city.funds() == CityDebugActions.MAX_FUNDS)


func _check_churches() -> void:
	for rotation in 4:
		var city := CityState.from_document(EmptyCityTemplate.create(128))
		city.document.set_misc_u32(Sc2MiscLayout.COMPASS, rotation)
		# Include two map boundaries and one site rejected because it has water.
		for origin in [Vector2i.ZERO, Vector2i(126, 126), Vector2i(10, 10)]:
			for x in range(origin.x, origin.x + 2):
				for y in range(origin.y, origin.y + 2):
					city.set_zone_id(x, y, 1)
					city.set_terrain_id(x, y, 0)
					city.set_tile_flag(x, y, Sc2TileFlags.WATER, false)
		city.set_tile_flag(10, 10, Sc2TileFlags.WATER, true)
		assert(ClassicCheatActions.churches(city) == 2)
		assert(city.buildings[10 * 128 + 10] == BuildingTileIds.EMPTY)
		assert(city.zones[0] == Sc2ZoneLayout.CORNER_BOTTOM_LEFT[rotation])
		assert(city.zones[129] == Sc2ZoneLayout.CORNER_TOP_LEFT[rotation])
		assert(city.document.misc_u32(Sc2MiscLayout.TILE_COUNTS + BuildingTileIds.CHURCH * 4) == 8)
		assert(ClassicCheatActions.churches(city) == 0)
		var restored := CityState.from_document(city.document)
		assert(restored.buildings == city.buildings and restored.zones == city.zones and restored.tile_flags == city.tile_flags)
