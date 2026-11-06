extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, detail: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + detail)

func command(world: SharedWorld, actor: String, request: Dictionary) -> Dictionary:
	request["revision"] = world.revision
	return world.command(actor, request)

func run() -> void:
	var pointer := Image.create(2, 1, false, Image.FORMAT_RGBA8)
	pointer.set_pixel(0, 0, Color.BLACK)
	var cursor_record := DesktopGraphics.Cursor.new(pointer, Vector2i.ZERO)
	var tinted := MultiplayerCursor.tinted(cursor_record, Color.GREEN)
	check(tinted.get_pixel(0, 0) == Color.GREEN and tinted.get_pixel(1, 0).a == 0, "black-only cursor takes player colour and retains transparency")
	check(pointer.get_pixel(0, 0) == Color.BLACK, "remote tint leaves local cursor pixels unchanged")
	check(MultiplayerCursor.valid_tool({"app":"city","group":1021.5}).is_empty(), "fractional tool identifiers rejected")
	var a := "a".repeat(48)
	var b := "b".repeat(48)
	var world := SharedWorld.new()
	check(world.open(Sc2xDocument.create_empty(32, "Market").document), "open")
	check(world.add_player(a).is_empty() and world.add_player(b).is_empty(), "players")
	check(command(world, a, {"kind": "land_buy", "start": [4, 4], "finish": [6, 6], "price": 90}).ok, "buy neutral")
	check(command(world, b, {"kind": "land_buy", "start": [3, 4], "finish": [3, 6]}).ok, "buyer has connecting territory")
	var before_a: int = world.municipalities[a].city.funds()
	var before_b: int = world.municipalities[b].city.funds()
	check(command(world, b, {"kind": "land_request", "start": [4, 4], "finish": [5, 5], "price": 40}).ok, "foreign land creates request")
	check(world.owners[4 * 32 + 4] == 1 and world.municipalities[a].city.funds() == before_a and world.municipalities[b].city.funds() == before_b, "request does not transfer or charge")
	check(not command(world, b, {"kind": "land_accept", "offer": "1"}).ok, "buyer cannot consent for owner")
	check(not command(world, a, {"kind": "land_withdraw", "offer": "1"}).ok, "owner cannot withdraw somebody else's request")
	check(command(world, a, {"kind": "land_accept", "offer": "1"}).ok, "owner consents")
	check(world.municipalities[a].city.funds() == before_a + 40 and world.municipalities[b].city.funds() == before_b - 40, "exact atomic money transfer")
	check(world.land_history.back().status == "Sold" and world.land_history.back().buyer == b, "seller gets completed record")
	check(not command(world, a, {"kind": "land_accept", "offer": "1"}).ok, "cannot accept twice")
	check(command(world, a, {"kind": "land_offer", "start": [6, 6], "finish": [6, 6], "price": 200}).ok, "offer")
	check(not command(world, b, {"kind": "land_withdraw", "offer": "2"}).ok, "other player cannot withdraw")
	check(command(world, a, {"kind": "land_withdraw", "offer": "2"}).ok, "seller withdraws")
	check(not command(world, b, {"kind": "land_accept", "offer": "2"}).ok, "withdraw wins before purchase")
	check(world.municipalities[b].city.funds() == before_b - 40, "failed accept cannot charge")
	world.owners[world.city.index_of(5, 6)] = 2
	check(command(world, b, {"kind": "land_request", "start": [6, 6], "finish": [6, 6], "price": 10}).ok, "second request")
	check(command(world, a, {"kind": "land_decline", "offer": "3"}).ok, "owner declines request")
	check(world.land_history.back().status == "Declined", "decline history")
	var record := world.saved_shared()
	var restored := SharedWorld.new()
	restored.open(world.template)
	check(restored.restore_shared(record).is_empty(), "restore market")
	check(restored.land_statistics == world.land_statistics and restored.land_history == world.land_history, "history and counters persist")
	record.erase("land_statistics")
	check(restored.restore_shared(record).is_empty() and MultiplayerStatistics.capture(restored, a).bought == null, "legacy totals remain unavailable")
	var owners: Array = []
	owners.resize(16)
	owners.fill(1)
	check(not MultiplayerMapOverlay.edge_visible(owners, 4, Vector2i(1, 1), 0), "no interior edge")
	check(MultiplayerMapOverlay.edge_visible(owners, 4, Vector2i(1, 0), 0), "exterior edge")
	var edges := 0
	for x in 4:
		for y in 4:
			for edge in 4:
				edges += int(MultiplayerMapOverlay.edge_visible(owners, 4, Vector2i(x, y), edge))
	check(edges == 16, "solid 4x4 parcel has sixteen exterior segments, no crossbars")
	var motion := MultiplayerMapOverlay.new()
	motion.segment_cache[Vector3i(0, 0, 0)] = {"bounds": Rect2i(0, 0, 10, 10)}
	motion.segment_cache[Vector3i(1, 0, 0)] = {"bounds": Rect2i(100, 100, 10, 10)}
	motion.invalidate_occlusion([Rect2i(2, 2, 5, 5)])
	check(motion.segment_cache.size() == 1 and motion.segment_cache.has(Vector3i(1, 0, 0)), "changed silhouette invalidates only intersecting boundary segments")
	var generation := motion.occlusion_generation
	motion.invalidate_occlusion([Rect2i(20, 20, 5, 5)])
	check(motion.occlusion_generation == generation, "unrelated scene edits preserve boundary cache")
	motion.receive([{"id": "a", "online": true, "cursor": [1.2, 3.4]}])
	motion.receive([{"id": "a", "online": true, "cursor": [2.2, 3.4]}])
	motion.step(1.0 / 60.0)
	check(motion.cursors.a.position.x > 1.2 and motion.cursors.a.position.x < 2.2, "subtile interpolation without overshoot")
	motion.receive([{"id": "a", "online": true, "cursor": [25.2, 3.4]}])
	check(is_equal_approx(motion.cursors.a.position.x, 25.2), "large jumps snap")
	motion.receive([])
	check(motion.cursors.is_empty(), "disconnected cursor disappears")
	MultiplayerText.setup()
	TranslationServer.set_locale("de")
	check(MultiplayerText.message("Buy 4 tiles for $40? Balance afterwards: $10.") == "4 Felder für $40 kaufen? Guthaben danach: $10.", "formatted German confirmation")
	check(TranslationServer.translate("Withdraw offer") == "Angebot zurückziehen", "German catalog")
	TranslationServer.set_locale("en")
	var body := VBoxContainer.new()
	root.add_child(body)
	var scores := MultiplayerScoreboard.new()
	scores.setup(body)
	var row := MultiplayerStatistics.capture(world, a)
	row.merge({"id": "a", "name": "Alice", "online": true, "host": true, "color": "46b4ff"})
	var other := row.duplicate()
	other.merge({"id": "b", "name": "Bob", "funds": 9}, true)
	scores.update([row, other], true, "a")
	scores.sort_key = "funds"
	scores.rebuild()
	check(scores.table.get_root().get_first_child().get_metadata(0) == "b", "numeric money sort")
	scores.table.get_root().get_first_child().select(0)
	scores.update([row, other], true, "a")
	check(scores.table.get_selected().get_metadata(0) == "b", "live refresh keeps selection")
	var selected := scores.table.get_selected()
	other["cursor"] = [3.5, 8.0]
	other["selection"] = [1, 2, 3]
	scores.update([row, other], true, "a")
	check(scores.table.get_selected() == selected, "presence changes retain existing selected statistic item")
	other.funds = 123456
	scores.update([row, other], true, "a")
	check(scores.table.get_selected().get_text(scores.columns.find("funds")) == MultiplayerScoreboard.money(123456), "financial changes still refresh selected statistics")
	scores.update([row, other], false, "a")
	check(not scores.columns.has("funds") and scores.summary.text.contains("Shared city"), "Koop totals separated from personal contributions")
	body.queue_free()
	await network_events()
	print("Multiplayer polish checks: %d failures" % failures)
	quit(1 if failures else 0)

func network_events() -> void:
	var host := CoopSession.new()
	var guest := CoopSession.new()
	root.add_child(host)
	root.add_child(guest)
	var events: Array = []
	var messages: Array = []
	host.player_event.connect(func(event: Dictionary) -> void: events.append(event))
	guest.chat_received.connect(func(entry: Dictionary) -> void: messages.append(entry))
	host.host(Sc2xDocument.create_empty(32, "Events").document, 0, "", "Host", "coop", false)
	host.send_chat("History")
	guest.join("127.0.0.1", host.server.get_local_port(), "", "Guest")
	for frame in 100:
		await create_timer(0.01).timeout
		if guest.connected and not messages.is_empty():
			break
	check(events.size() == 1 and events[0].kind == "joined", "one actual join event")
	check(messages.size() == 1 and messages[0].get("history", false), "replayed messages explicitly silent")
	host.chat_last_sent.clear()
	host.send_chat("Live")
	for frame in 100:
		await create_timer(0.01).timeout
		if messages.size() == 2:
			break
	check(messages.size() == 2 and not messages[1].get("history", false) and messages[1].id != messages[0].id, "new chat distinct from replay")
	guest.stop()
	for frame in 100:
		await create_timer(0.01).timeout
		if events.size() == 2:
			break
	check(events.size() == 2 and events[1].kind == "left", "voluntary leave correctly classified")
	host.stop()
	host.queue_free()
	guest.queue_free()
