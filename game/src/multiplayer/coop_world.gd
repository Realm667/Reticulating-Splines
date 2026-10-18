class_name CoopWorld
extends RefCounted
## Only the host owns this model. Every command is checked against its current city.

@warning_ignore_start("integer_division")

const STRUCTURAL := {"ALTM": 2, "XTER": 1, "XBLD": 1, "XZON": 1, "XUND": 1, "XTXT": 1}
var city: CityState
var engine: SimulationEngine
var controller: GameSpeedController
var revision := 0
var policy_revision := 0
var tile_versions := PackedInt64Array()
var undo_document: Sc2File
var undo_actor := ""
var undo_revision := -1
var dispatch_cycles := PackedInt32Array([0, 0, 0])
var dispatch_initialized := false
var dispatch_slot_points: Array[Dictionary] = [{}, {}, {}]
var dispatch_epoch := -1
var undo_dispatch_cycles := PackedInt32Array()
var undo_dispatch_initialized := false
var undo_dispatch_slot_points: Array[Dictionary] = []
var undo_dispatch_epoch := -1
var undo_damage_class := -1
var error := ""
var statistics: Dictionary = {}
var dispatch_owners: Dictionary = {}
var undo_statistics: Dictionary = {}
var undo_dispatch_owners: Dictionary = {}
var encoded_city := ""
var compression_cache: Dictionary = {}
var statistics_tiles: Dictionary = {}
var encoded_revision := -1
var encoded_policy := -1
var live_document := MultiplayerDocument.new()
var live_snapshot: Dictionary = {}
var live_revision := -1
var live_policy := -1
var newspaper_sequence := 0
var newspaper_paper := -1
var tree_growth_enabled := false


func open(document: Sc2File) -> bool:
	if document == null or not document.is_valid() or not document.is_sc2x() or document.map_size not in Sc2File.MAP_SIZES:
		error = "Multiplayer requires a valid SC2X city with a supported map size."
		return false
	error = document.compatibility_error()
	if not error.is_empty():
		return false
	city = CityState.from_document(document.duplicate_document())
	live_document = MultiplayerDocument.new()
	live_snapshot.clear()
	live_revision = -1
	live_policy = -1
	# Saved authentication/municipality data is restored by the session, never
	# sent to guests as an extra entry in the public display city.
	city.document.sc2x_extra_entries.erase("multiplayer.json")
	if not city.is_valid():
		error = city.load_error
		return false
	if city.document.sc2x_metadata.extensions.has("multiplayer_military") and not whole_number(city.document.sc2x_metadata.extensions.multiplayer_military, -1, 5):
		error = "Invalid saved military proposal."
		return false
	# Apply the upstream load repair once on the host, before publishing snapshots.
	CityNeighbors.repair_ocean_side(city)
	engine = SimulationEngine.new(city)
	controller = GameSpeedController.new(engine)
	Sc2xCheckpoint.restore_random(engine, city.document.sc2x_metadata)
	if Sc2xCheckpoint.has_saved_state(city.document.sc2x_metadata):
		error = Sc2xCheckpoint.restore(controller, city.document.sc2x_metadata)
	elif not engine.initialize_loaded_city():
		error = "Cannot initialize the city simulation."
	if not error.is_empty():
		return false
	controller.set_speed(GameSpeedController.Speed.PAUSED)
	dispatch_epoch = engine.dispatch_epoch
	tile_versions.resize(city.map_size * city.map_size)
	tile_versions.fill(0)
	return true


func advance(delta: float) -> void:
	if controller.speed == GameSpeedController.Speed.PAUSED:
		return
	var before := city.document.duplicate_document(true)
	var previous_age := city.age_in_days()
	# Continue annual accounting using existing funding while the mayor edits.
	# This does not enable Auto-Budget or change the single-player controller.
	if engine.pending_interaction == "annual_budget":
		var settled := controller.resolve_annual_budget(BudgetPhase.funding_values(city), city.auto_budget_enabled())
		capture_newspaper(settled)
		if not settled.ok:
			error = settled.error
			return
		policy_revision += 1
		revision += 1
	if engine.pending_interaction == "military_proposal":
		# Detach the decision from the calendar. Preserve it in the checkpoint until
		# this city's mayor answers; choosing nothing never declines the proposal.
		city.document.sc2x_metadata.extensions["multiplayer_military"] = engine.forced_military_base_type
		engine.forced_military_base_type = 0
		# Complete only the interrupted day via the public controller API. An empty
		# notice reserves no military site and leaves the stored decision unanswered.
		engine.pending_interaction = "military_notice"
		engine.pending_military_site = Rect2i()
		engine.pending_military_base_type = 0
		var completed := controller.resolve_military_notice()
		capture_newspaper(completed)
		if not completed.ok:
			error = completed.error
			return
		revision += 1
		policy_revision += 1
	elif engine.pending_interaction == "military_notice":
		var completed := controller.resolve_military_notice()
		capture_newspaper(completed)
		if not completed.ok:
			error = completed.error
			return
		revision += 1
		policy_revision += 1
	controller.terminal_blocked = false
	var pending := engine.pending_interaction
	var blocked := controller.interaction_blocked
	var result := controller.advance_time(minf(delta, 0.25) * 1000.0, Time.get_ticks_msec())
	var grown := ForestGrowth.advance(city, previous_age, tree_growth_enabled) if result.ok else PackedInt32Array()
	capture_newspaper(result)
	if not result.ok:
		error = result.error
		controller.set_speed(GameSpeedController.Speed.PAUSED)
	if result.base_ticks > 0 or not result.day_results.is_empty() or not result.launch_results.is_empty() or not grown.is_empty():
		revision += 1
		undo_document = null
		prune_dispatch()
		mark_changes(before, city.document)
	if pending != engine.pending_interaction or blocked != controller.interaction_blocked:
		policy_revision += 1


func capture_newspaper(result: SimulationTickResult) -> void:
	if result.newspaper_requested:
		newspaper_sequence += 1
		newspaper_paper = result.newspaper_paper


func snapshot(force_checkpoint := false, live := false) -> Dictionary:
	if live:
		if live_snapshot.is_empty() or live_revision != revision or live_policy != policy_revision:
			Sc2xCheckpoint.capture(controller, city.document.sc2x_metadata)
			live_snapshot = live_document.capture(city.document)
			live_revision = revision
			live_policy = policy_revision
		return snapshot_status().merged(live_snapshot)
	if force_checkpoint or encoded_city.is_empty() or encoded_revision != revision or encoded_policy != policy_revision:
		Sc2xCheckpoint.capture(controller, city.document.sc2x_metadata)
		var encoded := Sc2xDocument.encode(city.document, compression_cache)
		if not encoded.ok:
			return {"error": encoded.error}
		encoded_city = Marshalls.raw_to_base64(encoded.data)
		encoded_revision = revision
		encoded_policy = policy_revision
	return snapshot_status().merged({"city": encoded_city})


func snapshot_status() -> Dictionary:
	return {"type": "state", "revision": revision, "policy": policy_revision,
		"newspaper_sequence": newspaper_sequence, "newspaper_paper": newspaper_paper,
		"speed": controller.speed,
		"pending": "military_proposal" if city.document.sc2x_metadata.extensions.has("multiplayer_military") else engine.pending_interaction, "terminal": controller.terminal_blocked,
		"blocked": controller.interaction_blocked or city.document.sc2x_metadata.extensions.has("multiplayer_military"),
		"error": error, "dispatch_owners": dispatch_owners, "disaster": engine.active_disaster_type}


func command(actor: String, request: Dictionary) -> Dictionary:
	if not whole_number(request.get("revision"), 0, revision):
		return rejected("The city view is out of date. Wait for synchronization.")
	var kind: Variant = request.get("kind")
	if not kind is String:
		return rejected("Invalid command.")
	if kind == "undo":
		if undo_document == null or undo_actor != actor or undo_revision != revision:
			return rejected("Undo expired: another edit or simulation step occurred.")
		city = CityState.from_document(undo_document)
		city.disaster_damage_class = undo_damage_class
		dispatch_cycles = undo_dispatch_cycles
		dispatch_initialized = undo_dispatch_initialized
		dispatch_slot_points = undo_dispatch_slot_points
		dispatch_epoch = undo_dispatch_epoch

		statistics = undo_statistics
		dispatch_owners = undo_dispatch_owners
		engine.city = city
		Sc2xCheckpoint.restore(controller, city.document.sc2x_metadata)
		undo_document = null
		revision += 1
		tile_versions.fill(revision)
		return accepted("Your last edit was undone.")
	if kind != "build" and kind != "sign":
		return policy_command(request)
	return build(actor, request)


func build(actor: String, request: Dictionary) -> Dictionary:
	if not point_valid(request.get("start")) or not point_valid(request.get("finish")):
		return rejected("Invalid map position.")
	var start := point(request.start)
	var finish := point(request.finish)
	var seen := int(request.revision)
	# Protect the selected area even when the tool would produce no payload diff.
	for x in range(mini(start.x, finish.x), maxi(start.x, finish.x) + 1):
		for y in range(mini(start.y, finish.y), maxi(start.y, finish.y) + 1):
			if tile_versions[city.index_of(x, y)] > seen:
				return rejected("This area changed. Review it and try again.")
	Sc2xCheckpoint.capture(controller, city.document.sc2x_metadata)
	var candidate := CityState.copy_for_edit(city)
	candidate.disaster_damage_class = city.disaster_damage_class
	var random := SimRandom.new(engine.random.state)
	var lfsr := SimLfsrRandom.new(engine.lfsr_random.state)
	var edit: EditCommandResult
	if request.kind == "sign":
		if not request.get("text") is String or request.text.length() > 120:
			return rejected("A sign can contain at most 120 characters.")
		edit = SignCommand.set_sign(candidate, finish, request.text)
	else:
		for option in ["bridge", "connection", "confirmation", "team", "limit"]:
			if request.has(option) and not whole_number(request[option], 0, 2147483647):
				return rejected("Invalid construction choice.")
		if not whole_number(request.get("group"), 0, 14) or not whole_number(request.get("tool"), 0, 31):
			return rejected("Invalid tool.")
		var group := int(request.group)
		var tool := int(request.tool)
		if ToolCatalog.tool(group, tool) == null or not ToolAvailability.is_available(city, group, tool):
			return rejected("This tool is not available in the city.")
		if not request.get("path") is Array or request.path.size() > 512:
			return rejected("The tool path is too long.")
		var path: Array[Vector2i] = []
		for item in request.path:
			if not point_valid(item):
				return rejected("Invalid tool path.")
			var target := point(item)
			if tile_versions[city.index_of(target.x, target.y)] > seen:
				return rejected("This path changed. Review it and try again.")
			path.append(target)
		if path.is_empty():
			path.append(finish)
		var simple := SimpleEditFlow.apply_supported(candidate, group, tool, start, finish,
			path, random, request.get("underground") == true, false)
		if simple.handled:
			edit = simple.command
		elif BuildingCommand.supports_tool(group, tool):
			edit = BuildingCommand.apply(candidate, group, tool, finish, lfsr, random)
		elif NetworkCommand.supports_tool(group, tool):
			edit = NetworkCommand.apply(candidate, group, tool, start, finish,
				int(request.get("bridge", -1)), int(request.get("connection", -1)))
		elif HighwayCommand.supports_tool(group, tool):
			edit = HighwayCommand.apply(candidate, group, tool, start, finish,
				int(request.get("connection", -1)), int(request.get("bridge", -1)))
		elif TunnelCommand.supports_tool(group, tool):
			edit = TunnelCommand.apply(candidate, group, tool, start, int(request.get("confirmation", -1)))
		elif group in [8, 9, 10, 11]:
			edit = SimpleEditFlow.apply_zone(candidate, group, tool, start, finish,
				request.get("dragged") == true, false, -1).command
		elif DispatchCommand.supports_tool(group, tool):
			if dispatch_epoch != engine.dispatch_epoch:
				dispatch_cycles.fill(0)
				dispatch_epoch = engine.dispatch_epoch
			edit = DispatchCommand.apply(candidate, group, tool, finish, dispatch_cycles[tool], dispatch_slot_points[tool], engine.dispatch_capacity)
		else:
			return rejected("This tool is not yet available in Koop.")
	if edit is RouteEditResult and edit.bridge_selection_required:
		var choices: Array = []
		for bridge in edit.bridge_choices:
			choices.append({"label": bridge.name, "fields": {"bridge": bridge.type}})
		return choice_result("Choose a bridge. The host will check the site and cost again.", request, choices)
	if edit is RouteEditResult and edit.connection_selection_required:
		return choice_result("Connect to the neighboring city?", request,
			[{"label": "Connect and review total cost", "fields": {"connection": 1}},
			{"label": "Build without connection", "fields": {"connection": 0}}])
	if edit is TunnelEditResult and edit.confirmation_required:
		return choice_result("Build this tunnel?", request,
			[{"label": "Build — $%d" % edit.cost, "fields": {"confirmation": 1, "limit": edit.cost}}])
	if edit is BuildingEditResult and edit.stadium_team_selection_required:
		if not request.has("team"):
			var choices: Array = []
			for team in BuildingFacilities.stadium_team_choices(candidate):
				choices.append({"label": BuildingFacilities.stadium_team_name(candidate, team), "fields": {"team": team}})
			return choice_result("Choose the stadium team.", request, choices)
		edit = BuildingFacilities.assign_stadium_team(candidate, edit, int(request.team),
			BuildingFacilities.stadium_team_name(candidate, int(request.team)))
	if edit == null or not edit.ok:
		return rejected(edit.error if edit != null else "The edit could not be applied.")
	# A route proposal can stop at its first bridge. Quote the completed route,
	# including later dry segments and connections, only after all choices exist.
	if (request.has("bridge") or request.get("connection") == 1) and not request.has("limit"):
		return choice_result("Confirm the complete route cost.", request,
			[{"label": "Build — $%d" % edit.cost, "fields": {"limit": edit.cost}}])
	if request.has("limit") and edit.cost > int(request.limit):
		return rejected("The construction price changed. Select the site again to review it.")
	var changed := changed_tiles(city.document, candidate.document)
	for tile in changed:
		if tile_versions[tile] > seen:
			return rejected("Another player changed part of this building or terrain. Try again.")
	undo_document = city.document
	undo_actor = actor
	undo_dispatch_cycles = dispatch_cycles.duplicate()
	undo_dispatch_initialized = dispatch_initialized
	undo_dispatch_slot_points = ApplicationCityEdits._copy_slot_points(dispatch_slot_points)
	undo_dispatch_epoch = dispatch_epoch

	undo_statistics = statistics.duplicate(true)
	undo_dispatch_owners = dispatch_owners.duplicate(true)
	undo_damage_class = city.disaster_damage_class
	city = candidate
	engine.city = city
	engine.random.state = random.state
	engine.lfsr_random.state = lfsr.state
	if edit.power_usage_percent >= 0:
		engine.power_usage_percent = edit.power_usage_percent
	if edit.water_usage_percent >= 0:
		engine.water_usage_percent = edit.water_usage_percent
	if edit is RouteEditResult and edit.connection_built:
		engine.change_connection_count(edit.connection_kind(), 1)
	if edit is DispatchEditResult:
		dispatch_initialized = true
		dispatch_cycles[int(request.tool)] = edit.slot_index
		dispatch_slot_points[int(request.tool)][edit.slot_index] = edit.target
	revision += 1
	undo_revision = revision
	for tile in changed:
		tile_versions[tile] = revision
	# Signs and dispatch can change object tables without a structural byte.
	tile_versions[city.index_of(finish.x, finish.y)] = revision
	var stats: Dictionary = statistics.get(actor, {"builds": 0, "spent": 0})
	stats.builds += 1
	stats.spent += edit.cost
	statistics[actor] = stats
	if edit is DispatchEditResult:
		dispatch_owners[str(edit.thing_index)] = {"actor": actor.sha256_text(), "position": [finish.x, finish.y], "type": int(request.tool)}
	var response := accepted("Applied by the host. Cost: $%d." % edit.cost)
	var sounds: Array[int] = edit.sound_events.duplicate()
	if not edit.changed_ids.is_empty() and request.kind == "build":
		if int(request.group) == CityToolIds.Group.BULLDOZER and int(request.tool) in [1, 2, 3, 5, 6, 7]:
			sounds.append(ToolSoundRules.SOUND_TRACTOR)
		else:
			for sound in ToolSoundRules.success_events(int(request.group), int(request.tool)):
				if not sounds.has(sound):
					sounds.append(sound)
	response["sounds"] = sounds
	return response


func policy_command(request: Dictionary) -> Dictionary:
	if not whole_number(request.get("policy"), policy_revision, policy_revision):
		return rejected("City settings changed. Reopen Multiplayer and try again.")
	var result_error := ""
	var before := city.document.duplicate_document(true)
	match request.kind:
		"city_option":
			match request.get("option"):
				"auto_goto": city.set_auto_goto_enabled(request.get("enabled") == true)
				"sound": city.set_sound_enabled(request.get("enabled") == true)
				"music": city.set_music_enabled(request.get("enabled") == true)
				"newspaper_subscription": city.set_newspaper_subscription_enabled(request.get("enabled") == true)
				"newspaper_extras": city.set_newspaper_extras_enabled(request.get("enabled") == true)
				"newspaper_paper":
					if not whole_number(request.get("paper"), 0, NewsQueue.available_paper_count(city.city_status()) - 1):
						return rejected("Invalid city option.")
					city.document.set_misc_u32(Sc2MiscLayout.NEWSPAPER_CHOICE, int(request.paper))
				_: return rejected("Invalid city option.")
		"disaster":
			if not whole_number(request.get("disaster"), 1, 18) or not point_valid(request.get("point")):
				return rejected("Invalid disaster request.")
			result_error = engine.start_disaster(int(request.disaster), point(request.point)).error
		"no_disasters":
			if not city.set_no_disasters_enabled(request.get("enabled") == true):
				return rejected("Cannot change disaster settings.")
		"budget":
			if not request.get("values") is Array or request.values.size() != BudgetPhase.BUDGET_COUNT:
				return rejected("Invalid budget.")
			var values := PackedInt32Array()
			var current := BudgetPhase.funding_values(city)
			for index in request.values.size():
				var value: Variant = request.values[index]
				var maximum := 22 if index < 3 else 100
				if index in [3, 4]:
					values.append(current[index])
					continue
				if not whole_number(value, 0, maximum):
					return rejected("Invalid budget percentage.")
				values.append(int(value))
			if engine.pending_interaction == "annual_budget":
				result_error = controller.resolve_annual_budget(values, request.get("auto") == true).error
			else:
				result_error = BudgetPhase.set_funding(city, values, request.get("auto") == true).error
		"industry_tax":
			if not whole_number(request.get("industry"), 0, IndustryTaxCommand.INDUSTRY_COUNT - 1) or not whole_number(request.get("rate"), 0, IndustryTaxCommand.MAXIMUM_INDUSTRY_TAX):
				return rejected("Invalid industry tax rate.")
			result_error = IndustryTaxCommand.set_tax_rate(city, int(request.industry), int(request.rate), request.get("all") == true).error
		"ordinance":
			if not whole_number(request.get("ordinance"), 0, OrdinanceCommand.NAMES.size() - 1):
				return rejected("Invalid ordinance.")
			result_error = OrdinanceCommand.set_enabled(city, int(request.ordinance), request.get("enabled") == true).error
		"bond":
			result_error = BondCommand.issue(city, 1).error
		"repay":
			result_error = BondCommand.repay(city, 1).error
		"decision":
			if city.document.sc2x_metadata.extensions.has("multiplayer_military"):
				var proposal := MilitaryProposalPhase.resolve(city, request.get("accept") == true, engine.game_random, false, int(city.document.sc2x_metadata.extensions.multiplayer_military))
				if not proposal.ok:
					return rejected(proposal.error)
				city.document.sc2x_metadata.extensions.erase("multiplayer_military")
			elif engine.pending_interaction.is_empty() and not controller.interaction_blocked and not controller.terminal_blocked:
				return rejected("There is no decision to resolve.")
			match engine.pending_interaction:
				"military_proposal":
					result_error = controller.resolve_military_proposal(request.get("accept") == true).error
				"military_notice":
					result_error = controller.resolve_military_notice().error
				_:
					if controller.interaction_blocked:
						controller.acknowledge_game_over()

		"recall":
			result_error = DispatchCommand.recall_all(city).error
			dispatch_owners.clear()
			dispatch_cycles.fill(0)
			dispatch_initialized = false
			dispatch_slot_points = [{}, {}, {}]
		_:
			return rejected("Unknown command.")
	if not result_error.is_empty():
		return rejected(result_error)
	policy_revision += 1
	revision += 1
	undo_document = null
	mark_changes(before, city.document)
	return accepted("City settings updated.")


func mark_changes(before: Sc2File, after: Sc2File) -> void:
	for tile in changed_tiles(before, after):
		tile_versions[tile] = revision


static func changed_tiles(before: Sc2File, after: Sc2File) -> PackedInt32Array:
	var changed: Dictionary[int, bool] = {}
	for id: String in STRUCTURAL:
		var old := before.find_chunk(id).decoded_payload
		var current := after.find_chunk(id).decoded_payload
		if old == current:
			continue
		var stride: int = STRUCTURAL[id]
		for block in range(0, mini(old.size(), current.size()), 1024):
			var end := mini(block + 1024, mini(old.size(), current.size()))
			if old.slice(block, end) == current.slice(block, end):
				continue
			for index in range(block, end):
				if old[index] != current[index]:
					# SC2X overlays store the low and high bytes in separate planes.
					var tile: int = index % (before.map_size * before.map_size) if id == "XTXT" else index / stride
					changed[tile] = true
	return PackedInt32Array(changed.keys())


func point_valid(value: Variant) -> bool:
	return value is Array and value.size() == 2 and whole_number(value[0], 0, city.map_size - 1) and whole_number(value[1], 0, city.map_size - 1)


static func point(value: Array) -> Vector2i:
	return Vector2i(int(value[0]), int(value[1]))


static func whole_number(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= low and value <= high and float(value) == floorf(float(value))


static func rejected(message: String) -> Dictionary:
	return {"type": "result", "ok": false, "message": message}


static func accepted(message: String) -> Dictionary:
	return {"type": "result", "ok": true, "message": message}


static func choice_result(message: String, request: Dictionary, choices: Array) -> Dictionary:
	return {"type": "result", "ok": false, "message": message, "request": request, "choices": choices}


# JSON records use integer coordinates; Vector2i and integer dictionary keys
# must not be converted to strings when a cooperative session is saved.
func saved_dispatch_points() -> Array:
	var records: Array = []
	for group in dispatch_slot_points.size():
		for slot: int in dispatch_slot_points[group]:
			var position: Vector2i = dispatch_slot_points[group][slot]
			records.append([group, slot, position.x, position.y])
	return records


static func read_dispatch_points(value: Variant, map_size: int) -> Dictionary:
	var result: Array[Dictionary] = [{}, {}, {}]
	if not value is Array or value.size() > 1536:
		return {"error": "Invalid emergency service positions."}
	for record: Variant in value:
		if not record is Array or record.size() != 4:
			return {"error": "Invalid emergency service position."}
		if not whole_number(record[0], 0, 2) or not whole_number(record[1], 1, 2147483647) or not whole_number(record[2], 0, map_size - 1) or not whole_number(record[3], 0, map_size - 1):
			return {"error": "Invalid emergency service position."}
		var group := int(record[0])
		var slot := int(record[1])
		if result[group].has(slot):
			return {"error": "Duplicate emergency service position."}
		result[group][slot] = Vector2i(int(record[2]), int(record[3]))
	return {"points": result, "error": ""}

func prune_dispatch() -> void:
	var things := city.document.find_chunk("XTHG").decoded_payload
	for key: String in dispatch_owners.keys():
		var index := int(key)
		var unit: Dictionary = dispatch_owners[key]
		if index >= ThingData.count(things) or ThingData.read(things, index * ThingData.RECORD_SIZE) != [Sc2ThingLayout.Type.POLICE, Sc2ThingLayout.Type.FIRE, Sc2ThingLayout.Type.MILITARY][int(unit.type)]:
			dispatch_owners.erase(key)
			continue
		if ThingData.read(things, index * ThingData.RECORD_SIZE + 3) != int(unit.position[0]) or ThingData.read(things, index * ThingData.RECORD_SIZE + 4) != int(unit.position[1]):
			dispatch_owners.erase(key)
