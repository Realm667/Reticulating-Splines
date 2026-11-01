extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func run() -> void:
	var a := "a".repeat(48)
	var b := "b".repeat(48)
	var world := RegionWorld.new()
	world.expansion_enabled = true
	world.region_edge = 2
	world.region_seed = 20261030
	check(world.open(Sc2xDocument.create_empty(32, "Region expansion").document), "open")
	check(world.add_player(a).is_empty() and world.add_player(b).is_empty(), "two players")
	check(not world.add_player("c".repeat(48)).is_empty(), "2x2 rejects third player")
	world.municipalities[b].city.set_funds(23456)
	world.municipalities[b].city.document.set_misc_u32(Sc2MiscLayout.DIFFICULTY, 2)
	var starts := MultiplayerStarts.new()
	var members := {a: {"name": "A"}, b: {"name": "B"}}
	var error := starts.prepare(world, members)
	check(error.is_empty(), "start campaign: " + error)
	if world.campaign == null:
		finish()
		return
	var campaign := world.campaign
	var first := RegionRules.cell(campaign.active_cells[a])
	var rival := RegionRules.cell(campaign.active_cells[b])
	var rival_document := campaign.documents[campaign.active_cells[b]]
	var generated := RegionTerrain.generate(campaign.template, rival, campaign.origin, campaign.seed_value, {})
	check(generated.ok, "starting landscape reference")
	if generated.ok:
		for field: int in [Sc2MiscLayout.WATER_LEVEL, Sc2MiscLayout.HAS_OCEAN, Sc2MiscLayout.HAS_RIVER]:
			check(rival_document.misc_u32(field) == generated.document.misc_u32(field), "starting landscape metadata copied")
		for tile in 256:
			check(rival_document.misc_u32(Sc2MiscLayout.TILE_COUNTS + tile * 4) == generated.document.misc_u32(Sc2MiscLayout.TILE_COUNTS + tile * 4), "starting terrain tile count " + str(tile))
	check(rival_document.misc_i32(Sc2MiscLayout.FUNDS) == 23456 and rival_document.misc_u32(Sc2MiscLayout.DIFFICULTY) == 2, "terrain copy preserves individual city finances and difficulty")
	check(first.distance_squared_to(rival) == 2, "opposite 2x2 starts")
	check(not world.add_player("d".repeat(48)).is_empty(), "no late seats")
	var target := Vector2i(first.x, rival.y)
	var offer := world.region_command(a, {"kind": "region_offer", "cell": [target.x, target.y]}, 0)
	check(offer.ok, "persistent terrain offer")
	if not offer.ok:
		finish()
		return
	var quote: Dictionary = offer.region_offer
	var request := {"kind": "region_buy", "cell": [target.x, target.y], "quote_revision": quote.quote_revision}
	world.municipalities[a].city.set_funds(int(quote.price) + 1200)
	check(not world.region_command(a, request, 10000).ok, "player debt prevents purchase")
	world.municipalities[a].city.document.set_misc_u32(Sc2MiscLayout.BONDS, 1)
	check(not world.region_command(a, request, 0).ok, "bank debt prevents purchase")
	world.municipalities[a].city.document.set_misc_u32(Sc2MiscLayout.BONDS, 0)
	var rival_cash := campaign.own_funds(b)
	world.municipalities[a].engine.pending_interaction = "annual_budget"
	check(not world.region_command(a, request, 0).ok and campaign.own_count(a) == 1, "pending annual budget blocks purchase before mutation")
	world.municipalities[a].engine.pending_interaction = ""
	var bought := world.region_command(a, request, 0)
	check(bought.ok, "cash and reserve purchase: " + str(bought))
	check(campaign.own_funds(a) == 1200 and campaign.own_funds(b) == rival_cash, "private treasury debited exactly once")
	check(not world.region_command(b, request, 0).ok, "cannot double-buy area")
	check(not world.region_command(b, {"kind": "region_switch", "cell": [target.x, target.y]}, 0).ok, "cannot switch to rival city")
	check(not world.region_command(b, {"kind": "region_snapshot", "cell": [target.x, target.y]}, 0).ok, "frozen city snapshots require ownership")
	var frozen := world.region_command(a, {"kind": "region_snapshot", "cell": [target.x, target.y]}, 0)
	check(frozen.ok and frozen.has("region_snapshot"), "owner can retrieve a static city snapshot")
	if frozen.has("region_snapshot"):
		var snapshot_doc := Sc2File.new()
		check(snapshot_doc.parse(Marshalls.base64_to_raw(frozen.region_snapshot.document)), "frozen snapshot decodes")
		check(not snapshot_doc.sc2x_extra_entries.has(RegionCampaign.ENTRY), "snapshot omits the full private campaign")
	var original_id: String = campaign.active_cells[a]
	var purchased_id := RegionRules.key(target)
	campaign.documents[original_id].set_misc_i32(Sc2MiscLayout.FUNDS, 2147483647)
	campaign.documents[purchased_id].set_misc_i32(Sc2MiscLayout.FUNDS, 1)
	var before_revision := world.revision
	check(not world.region_command(a, {"kind": "region_switch", "cell": [target.x, target.y]}, 0).ok, "overflow prevents city switch")
	check(campaign.active_cells[a] == original_id and world.revision == before_revision
		and world.municipalities[a].city.document == campaign.documents[original_id]
		and campaign.documents[original_id].misc_i32(Sc2MiscLayout.FUNDS) == 2147483647
		and campaign.documents[purchased_id].misc_i32(Sc2MiscLayout.FUNDS) == 1, "overflow leaves active city and every balance unchanged")
	campaign.documents[original_id].set_misc_i32(Sc2MiscLayout.FUNDS, 1200)
	campaign.documents[purchased_id].set_misc_i32(Sc2MiscLayout.FUNDS, 0)
	check(world.region_command(a, {"kind": "region_switch", "cell": [target.x, target.y]}, 0).ok, "switch own new city")
	check(world.municipalities[a].city.funds() == 1200, "own aggregate funds available after switch")
	check(not world.command(a, {"kind": "city_option", "option": "sound", "enabled": false,
		"revision": world.revision, "policy": world.municipalities[a].policy_revision,
		"view_cell": [first.x, first.y]}).ok, "queued command cannot target previous city")
	var goal := MultiplayerGoal.new()
	goal.kind = "wealth"
	check(goal.world_value(world, a, null) == 1200, "wealth aggregates cities")
	var own_details := world.region_command(a, {"kind": "region_offer", "cell": [target.x, target.y]}, 0)
	check(own_details.ok and own_details.get("region_city", {}).get("own", false), "own city details authorized")
	if own_details.has("region_city"):
		check(own_details.region_city.budget.projected_cash == -1200, "own forecast includes annual administration")
		check(not str(own_details.region_city.preview).is_empty(), "own city preview generated on request")
	var denied_details := world.region_command(b, {"kind": "region_offer", "cell": [target.x, target.y]}, 0)
	check(not denied_details.ok and not denied_details.has("region_city"), "foreign city budget and preview request denied")
	var public_state := world.snapshot_region(b, a, true)
	for item: Dictionary in public_state.region_campaign.cells:
		check(not item.has("budget") and not item.has("preview"), "per-frame overview contains no private budget or image payload")
	var public_doc := MultiplayerDocument.restore(public_state)
	check(public_doc != null, "public snapshot decodes")
	check(public_doc != null and not public_doc.sc2x_extra_entries.has(RegionCampaign.ADMIN_ENTRY), "visitor cannot inspect administration metadata")
	check(public_state.region_campaign.funds == rival_cash, "overview exposes recipient finances only")
	var private_doc: Sc2File = world.municipalities[a].city.document
	private_doc.sc2x_extra_entries[RegionCampaign.ENTRY] = "secret".to_utf8_buffer()
	private_doc.sc2x_extra_entries[RegionCampaign.TEMPLATE_ENTRY] = "secret".to_utf8_buffer()
	private_doc.sc2x_extra_entries[RegionCampaign.PREFIX + "0-0.sc2x"] = "secret".to_utf8_buffer()
	var wire := MultiplayerDocument.new().capture(private_doc)
	var sanitized := MultiplayerDocument.restore(wire)
	check(sanitized != null and not sanitized.sc2x_extra_entries.has(RegionCampaign.ENTRY)
		and not sanitized.sc2x_extra_entries.has(RegionCampaign.TEMPLATE_ENTRY)
		and not sanitized.sc2x_extra_entries.has(RegionCampaign.PREFIX + "0-0.sc2x"), "private campaign archives never enter public snapshots")
	private_doc.sc2x_extra_entries.erase(RegionCampaign.ENTRY)
	private_doc.sc2x_extra_entries.erase(RegionCampaign.TEMPLATE_ENTRY)
	private_doc.sc2x_extra_entries.erase(RegionCampaign.PREFIX + "0-0.sc2x")
	var build := {"kind": "sign", "text": "Owned city", "start": [8, 8], "finish": [8, 8], "revision": world.revision}
	check(world.command(a, build).ok, "edit purchased city")
	check(campaign.documents[campaign.active_cells[a]] == world.municipalities[a].city.document, "edited document pointer synchronized")
	var state := world.saved_shared()
	check(not state.has("error"), "campaign checkpoint save")
	var restored := RegionWorld.new()
	check(restored.open(world.template), "restore base")
	error = restored.restore_shared(JSON.parse_string(JSON.stringify(state)))
	check(error.is_empty(), "campaign restore: " + error)
	if error.is_empty():
		check(restored.campaign.own_count(a) == 2, "all own cities retained")
		check(restored.campaign.own_funds(a) == campaign.own_funds(a), "treasury roundtrip")
		check(restored.campaign.active_cells == campaign.active_cells, "active cities roundtrip")
		check(restored.region_command(a, {"kind": "region_switch", "cell": [first.x, first.y]}, 0).ok, "switch restored original city")
	var exported := MultiplayerSingleplayer.from_world(world, a)
	check(exported.error.is_empty(), "single-player region export")
	if exported.error.is_empty():
		var copy := RegionCampaign.new()
		check(copy.restore(exported.document).is_empty(), "export archive valid")
		check(copy.documents.size() == 2 and copy.own_count(ApplicationRegions.LOCAL_OWNER) == 2 and not copy.multiplayer, "export contains own cities only")
	var before_admin := campaign.own_funds(a)
	campaign.advance(campaign.current_day + CityCalendar.DAYS_PER_YEAR)
	check(campaign.own_funds(a) == before_admin - RegionRules.ANNUAL_ADMINISTRATION, "one additional area pays annual administration")
	check(campaign.own_funds(b) == rival_cash, "rival starter area exempt from administration")
	clock_case()
	await network_case()
	finish()

func clock_case() -> void:
	var world := RegionWorld.new()
	world.expansion_enabled = true
	world.region_edge = 2
	world.region_seed = 77
	var a := "c".repeat(48)
	var b := "d".repeat(48)
	check(world.open(Sc2xDocument.create_empty(32, "Shared calendar").document), "calendar base")
	world.add_player(a)
	world.add_player(b)
	check(world.prepare_campaign(RegionRules.start_positions(2, 2, 77)).is_empty(), "calendar campaign")
	var campaign := world.campaign
	var own := RegionRules.cell(campaign.active_cells[a])
	var rival := RegionRules.cell(campaign.active_cells[b])
	var extra := Vector2i(own.x, rival.y)
	check(campaign.offer(extra).ok, "calendar passive-city offer")
	world.municipalities[a].city.set_funds(100000)
	check(campaign.purchase(a, extra, 0).ok, "calendar passive city")
	var passive := campaign.documents[RegionRules.key(extra)]
	for id: String in campaign.documents:
		campaign.documents[id].set_misc_u32(Sc2MiscLayout.CITY_DAYS, 299)
		campaign.settled[id] = 299
	campaign.current_day = 299
	for actor: String in world.actors:
		var child: CoopWorld = world.municipalities[actor]
		child.engine.clock.city_days = 299
		child.city.document.set_misc_u32(Sc2MiscLayout.YEAR_END, 1)
		child.city.set_auto_budget_enabled(actor == a)
		child.controller.set_speed(GameSpeedController.Speed.CHEETAH)
		child.controller.simulation_ready = true
	var fast: CoopWorld = world.municipalities[a]
	var slow: CoopWorld = world.municipalities[b]
	var cash := campaign.own_funds(a)
	world.advance(0.001)
	check(slow.engine.pending_interaction == "annual_budget", "calendar genuinely waits for annual schedule")
	check(campaign.current_day == 299 and passive.misc_u32(Sc2MiscLayout.CITY_DAYS) == 299,
		"unfinished annual schedule cannot advance passive accounting")
	check(fast.city.age_in_days() == 300 and slow.city.age_in_days() == 300, "active dates stop at shared boundary")
	world.advance(0.25)
	check(slow.engine.pending_interaction.is_empty() and campaign.current_day == 300, "annual resolution completes exactly the pending day")
	check(fast.city.age_in_days() == 300 and slow.city.age_in_days() == 300, "budget resolution does not run an extra day")
	check(passive.misc_u32(Sc2MiscLayout.CITY_DAYS) == 300 and campaign.own_funds(a) == cash - 4,
		"passive budget and daily administration settled once")
	check(fast.controller.speed == 4 and slow.controller.speed == 4, "temporary barrier preserves running speed")
	check(slow.engine.start_disaster(7, Vector2i(16, 16)).ok, "calendar tornado begins")
	var disaster_day := slow.city.age_in_days()
	var moving_before := slow.city.document.find_chunk("XTHG").decoded_payload.duplicate()
	for tick in 6:
		world.advance(0.2)
		check(absi(fast.city.age_in_days() - slow.city.age_in_days()) <= 1, "disaster cannot split regional dates")
	check(slow.engine.active_disaster_type != 0 and slow.city.age_in_days() == disaster_day,
		"disaster retains its day while other city waits")
	check(slow.city.document.find_chunk("XTHG").decoded_payload != moving_before, "disaster movement continues at calendar barrier")
	check(campaign.current_day == disaster_day and passive.misc_u32(Sc2MiscLayout.CITY_DAYS) == disaster_day,
		"inactive cities do not jump ahead during disaster")
	check(not world.region_command(a, {"kind": "region_switch", "cell": [extra.x, extra.y]}, 0).ok,
		"ahead city cannot discard its completed day by switching")
	var ahead_save := world.saved_shared()
	check(not ahead_save.has("error"), "one-day-ahead active city can be saved")
	var continued := RegionWorld.new()
	check(continued.open(world.template), "ahead checkpoint base")
	var continue_error := continued.restore_shared(JSON.parse_string(JSON.stringify(ahead_save)))
	check(continue_error.is_empty(), "one-day-ahead multiplayer checkpoint restores: " + continue_error)
	if continue_error.is_empty():
		check(continued.campaign.current_day == disaster_day
			and continued.municipalities[a].city.age_in_days() == disaster_day + 1
			and continued.municipalities[b].city.age_in_days() == disaster_day,
			"restore preserves committed date and legitimate active lead")
	var exported := MultiplayerSingleplayer.from_world(world, a)
	check(exported.error.is_empty(), "ahead city exports to single-player region")
	if exported.error.is_empty():
		var exported_region := RegionCampaign.new()
		check(exported_region.restore(exported.document).is_empty(), "single-player export accepts its preserved one-day lead")
	var deadline := MultiplayerGoal.new()
	deadline.kind = "timed_score"
	deadline.start_age = disaster_day
	deadline.duration_days = 1
	var members := {a: {"name": "A"}, b: {"name": "B"}}
	check(not deadline.evaluate(world, members), "ahead host cannot finish regional competition early")
	slow.engine.active_disaster_type = 0
	for tick in 32:
		deadline.advance(world, 0.2)
		if campaign.current_day == disaster_day + 1:
			break
	check(campaign.current_day == disaster_day + 1 and fast.city.age_in_days() == campaign.current_day
		and slow.city.age_in_days() == campaign.current_day, "timed deadline lets every city finish the same day")
	check(deadline.evaluate(world, members), "competition scores the committed regional day")
	for tick in 64:
		world.advance(0.2)
		check(absi(fast.city.age_in_days() - slow.city.age_in_days()) <= 1, "resume maintains day barrier")
		check(fast.engine.clock.city_days == fast.city.age_in_days() and slow.engine.clock.city_days == slow.city.age_in_days(),
			"native clocks match city documents")
		if campaign.current_day >= disaster_day + 2 and fast.city.age_in_days() == campaign.current_day:
			break
	check(campaign.current_day >= disaster_day + 2, "all cities resume after disaster")
	check(world.region_command(a, {"kind": "region_switch", "cell": [extra.x, extra.y]}, 0).ok, "synchronized city switch")
	check(world.municipalities[a].engine.clock.city_days == campaign.current_day
		and world.municipalities[a].city.age_in_days() == campaign.current_day, "switched city resumes exact regional date")

func wait_for(predicate: Callable, message: String) -> void:
	var deadline := Time.get_ticks_msec() + 8000
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await create_timer(0.02).timeout
	check(predicate.call(), message)

func network_case() -> void:
	var host := CoopSession.new()
	var guest := CoopSession.new()
	root.add_child(host)
	root.add_child(guest)
	host.host_region_expansion = true
	host.host_region_edge = 2
	check(host.host(Sc2xDocument.create_empty(32, "Network region").document, 0, "", "Host", "region").is_empty(), "network host")
	guest.join("127.0.0.1", host.server.get_local_port(), "", "Guest")
	await wait_for(func() -> bool: return guest.connected and guest.latest.get("lobby", {}).get("generation", -1) == host.lobby_generation, "expanded lobby delivered")
	check(guest.latest.get("lobby", {}).get("region_expansion", false) and guest.latest.lobby.player_limit == 2, "lobby rules replicated")
	host.request({"kind": "lobby_ready", "ready": true})
	guest.request({"kind": "lobby_ready", "ready": true})
	await wait_for(func() -> bool: return host.can_start_lobby(), "both players ready")
	host.request({"kind": "lobby_start"})
	host.request({"kind": "speed", "speed": 1})
	await wait_for(func() -> bool: return guest.latest.has("region_campaign"), "region overview delivered")
	if not guest.latest.has("region_campaign"):
		guest.stop()
		host.stop()
		guest.queue_free()
		host.queue_free()
		return
	var world: RegionWorld = host.world
	var actor := guest.token
	var own := RegionRules.cell(world.campaign.active_cells[actor])
	var other := RegionRules.cell(world.campaign.active_cells[host.token])
	var cell := [own.x, other.y]
	var results: Array[Dictionary] = []
	guest.command_resolved.connect(func(_id: int, result: Dictionary) -> void: results.append(result))
	guest.request({"kind": "region_offer", "cell": cell})
	await wait_for(func() -> bool: return not results.is_empty(), "remote offer acknowledgement")
	if not results.is_empty() and results.back().get("ok", false):
		var quote: Dictionary = results.back().region_offer
		check(not str(quote.get("preview", "")).is_empty(), "remote terrain preview")
		world.municipalities[actor].city.set_funds(int(quote.price) + 1200)
		results.clear()
		guest.request({"kind": "region_buy", "cell": cell, "quote_revision": quote.quote_revision})
		await wait_for(func() -> bool: return not results.is_empty(), "remote purchase acknowledgement")
		check(not results.is_empty() and results.back().ok, "remote purchase succeeds")
		results.clear()
		guest.request({"kind": "region_switch", "cell": cell})
		await wait_for(func() -> bool: return not results.is_empty() and guest.latest.get("region_campaign", {}).get("active") == cell, "remote switch publishes current city")
		if guest.latest.get("region_campaign", {}).get("active") != cell:
			printerr("SWITCH DETAIL: " + str({"reply": results, "host": world.campaign.active_cells[actor], "guest": guest.latest.get("region_campaign", {}), "target": cell, "connected": guest.connected}))
		check(not results.is_empty() and results.back().ok, "remote switch succeeds")
		results.clear()
		guest.request({"kind": "region_offer", "cell": cell})
		await wait_for(func() -> bool: return not results.is_empty(), "remote own-city details acknowledged")
		check(not results.is_empty() and results.back().get("region_city", {}).get("cell") == cell,
			"remote own-city coordinates normalized for overview selection")
		results.clear()
		guest.request({"kind": "city_option", "option": "sound", "enabled": false})
		await wait_for(func() -> bool: return not results.is_empty(), "remote command after switch acknowledged")
		check(not results.is_empty() and results.back().ok, "JSON coordinates permit commands in new active city")
	else:
		check(false, "remote offer succeeds")
	var checkpoint := host.city_checkpoint()
	check(checkpoint.error.is_empty(), "full multiplayer city checkpoint")
	guest.stop()
	if checkpoint.error.is_empty():
		var restore_error := host.restore_embedded(checkpoint.document)
		check(restore_error.is_empty(), "full session continuation: " + restore_error)
		if restore_error.is_empty():
			check(host.world is RegionWorld and host.world.campaign != null and host.world.campaign.own_count(actor) == 2,
				"session continuation retains additional city and owner")
	host.stop()
	guest.queue_free()
	host.queue_free()

func finish() -> void:
	print("Multiplayer region expansion: %d failures" % failures)
	quit(1 if failures else 0)
