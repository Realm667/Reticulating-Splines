extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func settle() -> void:
	for frame in 20:
		await create_timer(0.01).timeout

func await_lobby_view(host: CoopSession, guest: CoopSession) -> void:
	# Ready refers to the displayed roster generation. A fixed sleep can race
	# the next state broadcast under parallel CPU/GPU validation load.
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		if guest.connected and int(guest.latest.get("lobby", {}).get("generation", -1)) == host.lobby_generation:
			return
		await create_timer(0.02).timeout
	check(false, "client received the current lobby generation")

func run() -> void:
	for mode in ["coop", "shared", "region"]:
		await lobby_case(mode)
		await continuation_case(mode)
	await compatibility_case()
	check(MultiplayerGoalHud.value({"funds": 50000, "debt": 20000}, "wealth") == 30000, "HUD subtracts all debt")
	check(MultiplayerGoalHud.value({"population": 321}, "population") == 321, "HUD population")
	print("Multiplayer lobby checks: %d failures" % failures)
	quit(1 if failures else 0)

func lobby_case(mode: String) -> void:
	var host := CoopSession.new()
	var guest := CoopSession.new()
	for node in [host, guest]:
		root.add_child(node)
	check(host.host(Sc2xDocument.create_empty(32, "Lobby").document, 0, "", "Host", mode).is_empty(), "host lobby " + mode)
	check(host.waiting_for_start and host.world.controller.speed == 1, "host paused before first guest")
	var before := host.world.city.document.serialize().data
	host.request({"kind": "speed", "speed": 5})
	host.request({"kind": "disaster", "disaster": 7, "point": [5, 5]})
	host.request({"kind": "lobby_ready", "ready": true})
	host.request({"kind": "lobby_start"})
	check(host.waiting_for_start, "cannot start alone")
	await settle()
	check(host.world.city.document.serialize().data == before, "lobby blocks clock and commands")
	guest.player_color = "c7a0ff"
	guest.join("127.0.0.1", host.server.get_local_port(), "", "Guest")
	await settle()
	check(guest.connected and guest.latest.get("lobby", {}).get("waiting", false), "guest receives lobby")
	check(host.members[guest.token].color == "c7a0ff", "exact guest colour retained")
	check(not host.lobby_ready.get(host.token, false), "new participant resets host readiness")
	if mode != "coop":
		host.request({"kind": "handicap", "seat": guest.token.sha256_text(), "funds": 15000, "tiles": 8 if mode == "shared" else 0})
		check(host.starts.handicaps[guest.token].funds == 15000 and host.lobby_ready.is_empty(), "host handicap resets readiness")
		guest.request({"kind": "handicap", "seat": guest.token.sha256_text(), "funds": 999999, "tiles": 0})
		await settle()
		check(host.starts.handicaps[guest.token].funds == 15000, "clients cannot grant themselves handicaps")
	await await_lobby_view(host, guest)
	host.request({"kind": "lobby_ready", "ready": true})
	guest.request({"kind": "lobby_ready", "ready": true})
	await settle()
	check(host.can_start_lobby(), "both ready permits start")
	guest.request({"kind": "lobby_start"})
	await settle()
	check(host.waiting_for_start, "guest cannot start")
	guest.request({"kind": "lobby_ready", "ready": false})
	await settle()
	host.request({"kind": "lobby_start"})
	check(host.waiting_for_start, "readiness withdrawal prevents start")
	var saved := host.city_checkpoint()
	check(saved.error.is_empty(), "save pre-start lobby")
	guest.stop()
	await settle()
	check(host.restore_embedded(saved.document).is_empty(), "restore pre-start game")
	check(host.waiting_for_start and host.lobby_ready.is_empty(), "save does not persist stale readiness")
	guest.join("127.0.0.1", host.server.get_local_port(), "", "Guest")
	await settle()
	await await_lobby_view(host, guest)
	host.request({"kind": "lobby_ready", "ready": true})
	guest.request({"kind": "lobby_ready", "ready": true})
	await settle()
	host.request({"kind": "lobby_start"})
	await settle()
	check(not host.waiting_for_start and not guest.latest.lobby.waiting, "both peers enter running game")
	check(host.world.controller.speed == 2 and int(guest.latest.speed) == 2, "shared initial speed")
	if mode != "coop":
		check(host.world.municipalities[guest.token].city.funds() == 15000, "saved handicap applied once at start")
		if mode == "shared":
			check(host.world.owners.count(2) == 9, "eight requested fields round up to a complete near-square 3x3 start")
	guest.request({"kind": "speed", "speed": 1})
	await settle()
	check(host.world.controller.speed == 2, "guest cannot pause host simulation")
	host.request({"kind": "speed", "speed": 4})
	await settle()
	check(host.world.controller.speed == 4 and int(guest.latest.speed) == 4, "host speed reaches clients without slowest-client veto")
	host.request({"kind": "speed", "speed": 2})
	if mode == "region":
		guest.request({"kind": "view_city", "seat": host.token.sha256_text()})
		await settle()
		check(guest.latest.visiting and guest.latest.view_owner == host.token.sha256_text(), "TCP guest spectates host city")
		var before_build := host.world.city.zones.duplicate()
		guest.request({"kind": "build", "group": 9, "tool": 0, "start": [7, 7], "finish": [7, 7]})
		await settle()
		check(host.world.city.zones == before_build, "remote spectator cannot change host city")
		host.goal.kind = "wealth"
		host.goal.target = 45000
		host.world.municipalities[guest.token].city.set_funds(50000)
		host.world.revision += 1
		await settle()
		check(not host.goal.blocked(), "target requires full holding year")
		host.world.municipalities[guest.token].city.set_age_in_days(host.world.municipalities[guest.token].city.age_in_days() + host.goal.hold_days)
		await settle()
		check(host.goal.blocked() and guest.latest.goal.winners[0].seat == guest.token.sha256_text(), "TCP victory reaches all players")
		check(host.world.controller.speed == int(host.requested_speed[host.token]), "victory dialog does not override host speed")
		guest.request({"kind": "continue_unscored"})
		await settle()
		check(host.goal.blocked(), "only host can release victory")
		host.request({"kind": "continue_unscored"})
		await settle()
		check(not host.goal.blocked() and guest.latest.goal.unscored, "host continues endless on both peers")
		var old_positions := host.starts.positions.duplicate(true)
		guest.request({"kind": "rematch"})
		await settle()
		check(not host.waiting_for_start, "guest cannot force a rematch")
		host.request({"kind": "rematch"})
		await settle()
		check(host.waiting_for_start and guest.latest.lobby.waiting and host.lobby_ready.is_empty(), "rematch returns everyone to unready lobby")
		await await_lobby_view(host, guest)
		host.request({"kind": "lobby_ready", "ready": true})
		guest.request({"kind": "lobby_ready", "ready": true})
		await settle()
		host.request({"kind": "lobby_start"})
		await settle()
		check(host.starts.positions[host.token].slot != old_positions[host.token].slot and host.starts.positions[guest.token].slot != old_positions[guest.token].slot, "real session rotates both starts")
		check(host.goal.winners.is_empty() and host.goal.holding.values().all(func(value: Dictionary) -> bool: return int(value.days) == 0), "rematch resets victory hold")
		var checkpoint := host.city_checkpoint()
		check(checkpoint.error.is_empty(), "competition checkpoint serializes")
		var verify := CoopSession.new()
		root.add_child(verify)
		verify.host(Sc2xDocument.create_empty(32, "Verify").document, 0, "", "Verify", "region")
		check(verify.restore_embedded(checkpoint.document, host.token).is_empty(), "competition rules and starts restore")
		check(verify.starts.previous == host.starts.previous and verify.goal.hold_days == CityCalendar.DAYS_PER_YEAR * 10, "repeated starts remain prohibited after reload")
		verify.stop()
		verify.queue_free()
	guest.stop()
	host.stop()
	guest.queue_free()
	host.queue_free()
	await process_frame


func compatibility_case() -> void:
	var host := CoopSession.new()
	var probe := MultiplayerCompatibility.new()
	root.add_child(host)
	root.add_child(probe)
	check(host.host(Sc2xDocument.create_empty(32, "Probe").document, 0, "secret", "Host").is_empty(), "probe host")
	var results: Array[String] = []
	probe.completed.connect(func(error: String) -> void: results.append(error))
	probe.check_host("127.0.0.1", host.server.get_local_port())
	var until := Time.get_ticks_msec() + 6000
	while results.is_empty() and Time.get_ticks_msec() < until:
		await create_timer(0.01).timeout
	check(results == [""], "real TCP compatibility before password or admission")
	check(host.channels.is_empty() and host.members.size() == 1 and host.seats.pending.is_empty(), "probe consumes no player seat")
	var response := {"type": "compatibility", "nonce": "test", "open": true, "protocol": CoopSession.PROTOCOL, "build": CoopSession.NETWORK_BUILD}
	check(MultiplayerCompatibility.response_error(response, "test").is_empty(), "matching simulation contract")
	response.build = "other"
	check(MultiplayerCompatibility.response_error(response, "test") == "Different game version", "incompatible build rejected")
	response.build = CoopSession.NETWORK_BUILD
	response.protocol = -1
	check(not MultiplayerCompatibility.response_error(response, "test").is_empty(), "incompatible protocol rejected")
	response.protocol = CoopSession.PROTOCOL
	response.open = false
	check(MultiplayerCompatibility.response_error(response, "test") == "Full", "full host explained")
	check(not MultiplayerCompatibility.response_error(response, "wrong").is_empty(), "mismatching probe rejected")
	probe.check_host("127.0.0.1", host.server.get_local_port())
	probe.cancel()
	await settle()
	check(results.size() == 1 and probe.channel == null, "cancel prevents late completion")
	host.stop()
	probe.queue_free()
	host.queue_free()


func continuation_case(mode: String) -> void:
	var host := CoopSession.new()
	var guest := CoopSession.new()
	var absent := CoopSession.new()
	var resumed := CoopSession.new()
	for node in [host, guest, absent, resumed]:
		root.add_child(node)
	host.host(Sc2xDocument.create_empty(32, "Continue").document, 0, "", "Original", mode, false)
	guest.join("127.0.0.1", host.server.get_local_port(), "", "Returning")
	absent.join("127.0.0.1", host.server.get_local_port(), "", "Absent")
	await settle()
	check(guest.connected and absent.connected, "continuation participants " + mode)
	host.request({"kind": "speed", "speed": 1})
	var original_actor := host.token
	var returning_actor := guest.token
	var absent_actor := absent.token
	var returning_identity := guest.credential
	host.goal.holding[returning_actor.sha256_text()] = {"days": 150, "since": 30}
	var goal_before := host.goal.saved().duplicate(true)
	var own: CoopWorld = host.world.municipalities[returning_actor] if host.world is SharedWorld else host.world
	own.city.set_funds(76543)
	var city_before := own.city.document.serialize().data
	var saved := host.city_checkpoint()
	check(saved.error.is_empty(), "running checkpoint " + mode)
	var names := host.members.duplicate(true)
	guest.stop()
	absent.stop()
	host.stop()
	resumed.credential = returning_identity
	resumed.host(Sc2xDocument.create_empty(32, "Temporary").document, 0, "", "Returning", "coop", false)
	var restored := resumed.restore_embedded(saved.document)
	check(restored.is_empty(), "returning player hosts save " + mode + ": " + restored)
	check(resumed.token == returning_actor and resumed.members[original_actor].name == names[original_actor].name, "host keeps own city and old host seat " + mode)
	check(resumed.continuing and resumed.waiting_for_start and resumed.world.controller.speed == 1, "running save opens paused continuation " + mode)
	check(JSON.parse_string(JSON.stringify(resumed.goal.saved())) == JSON.parse_string(JSON.stringify(goal_before)), "saved victory progress retained " + mode + " expected=" + JSON.stringify(goal_before) + " actual=" + JSON.stringify(resumed.goal.saved()))
	check(resumed.world.city.document.serialize().data == city_before, "host city retained " + mode)
	var again := resumed.city_checkpoint()
	var record: Dictionary = JSON.parse_string(again.document.sc2x_extra_entries["multiplayer.json"].get_string_from_utf8())
	check(record.started == true, "saving continuation does not become a new game")
	resumed.request({"kind": "speed", "speed": 5})
	await settle()
	check(resumed.world.city.document.serialize().data == city_before, "no simulation during continuation " + mode)
	resumed.request({"kind": "lobby_ready", "ready": true})
	resumed.request({"kind": "lobby_start"})
	check(resumed.waiting_for_start, "solo continuation also needs absence consent")
	resumed.request({"kind": "lobby_start", "allow_absent": true})
	check(not resumed.waiting_for_start, "saved match may continue with its host alone after consent")
	check(resumed.restore_embedded(again.document).is_empty(), "resaved continuation retains identity and original phase")
	host.join("127.0.0.1", resumed.server.get_local_port(), "", "Original")
	await await_lobby_view(resumed, host)
	check(host.token == original_actor, "original host reconnects to original city " + mode)
	resumed.request({"kind": "lobby_ready", "ready": true})
	host.request({"kind": "lobby_ready", "ready": true})
	await settle()
	resumed.request({"kind": "lobby_start"})
	check(resumed.waiting_for_start, "absent players require explicit continuation consent")
	resumed.request({"kind": "lobby_start", "allow_absent": true})
	check(not resumed.waiting_for_start and not resumed.continuing, "host continues when connected players are ready")
	check(resumed.world.city.funds() == 76543 and JSON.parse_string(JSON.stringify(resumed.goal.saved())) == JSON.parse_string(JSON.stringify(goal_before)), "continuation does not reset funds or victory clock")
	check(resumed.members.has(absent_actor) and resumed.seats.credentials.get(absent.credential.sha256_text()) == absent_actor, "absent seat and credential preserved")
	for node in [host, guest, absent, resumed]:
		node.stop()
		node.queue_free()
	await process_frame
