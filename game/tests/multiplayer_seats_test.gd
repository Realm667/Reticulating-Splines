extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func settle() -> void:
	for frame in 15:
		await create_timer(0.01).timeout

func run() -> void:
	var host := CoopSession.new()
	var old := CoopSession.new()
	var replacement := CoopSession.new()
	for node in [host, old, replacement]:
		root.add_child(node)
	check(host.host(Sc2xDocument.create_empty(32, "Seat test").document, 0, "", "Host", "shared", false).is_empty(), "host")
	var port := host.server.get_local_port()
	old.join("127.0.0.1", port, "", "First")
	await settle()
	check(old.connected, "first owner joined")
	var actor := old.token
	var credential := old.credential
	check(actor != credential, "city seat independent of personal credential")
	var child: CoopWorld = host.world.municipalities[actor]
	var funds := child.city.funds()
	child.statistics[actor] = {"builds": 4, "spent": 100}
	old.channels[0].close()
	await settle()
	check(not host.disconnected_pause and host.members[actor].seat_status == "reserved", "loss reserves seat without pausing")
	old.join("127.0.0.1", port, "", "First")
	await settle()
	check(old.connected and old.token == actor and child.city.funds() == funds, "authenticated reconnect preserves city")
	host.release_disconnect_pause()
	old.stop()
	await settle()
	check(not host.disconnected_pause and host.members[actor].seat_status == "unoccupied", "voluntary leave does not impose disconnect pause")
	host.world.offers["sample"] = {"seller": actor, "tiles": [0], "price": 10}
	var lobbies: Array = []
	replacement.seat_lobby_received.connect(func(data: Dictionary) -> void: lobbies.append(data))
	replacement.join("127.0.0.1", port, "", "Successor", "choose")
	await settle()
	check(not replacement.connected and not lobbies.is_empty(), "newcomer cannot control a city before choice")
	replacement.channels[0].send({"type": "seat_choice", "seat": actor.sha256_text()})
	await settle()
	var peer: int = host.seats.pending.keys()[0]
	check(not replacement.connected and host.members[actor].name == "First", "request requires host approval")
	host.seats.decide(peer, false)
	await settle()
	check(not replacement.connected, "denial grants no authority")
	replacement.channels[0].send({"type": "seat_choice", "seat": actor.sha256_text()})
	await settle()
	host.seats.decide(peer, true)
	await settle()
	check(replacement.connected and replacement.token == actor, "approved city takeover")
	check(host.world.municipalities[actor] == child and child.city.funds() == funds, "same city and treasury retained")
	check(host.members[actor].name == "Successor" and child.statistics.get(actor, {}).is_empty(), "successor personal contributions separate")
	check(host.seats.history.back().statistics.builds == 4, "predecessor contributions retained in history")
	check(host.world.offers.is_empty(), "predecessor land commitments withdrawn")
	check(not host.seats.credentials.has(credential.sha256_text()), "old credential revoked")
	old.join("127.0.0.1", port, "", "First", "choose")
	await settle()
	check(not old.connected and host.world.actors.size() == 2, "former owner cannot reclaim transferred city")
	var checkpoint := host.city_checkpoint()
	check(checkpoint.error.is_empty(), "seat save checkpoint")
	var record: Dictionary = JSON.parse_string(checkpoint.document.sc2x_extra_entries["multiplayer.json"].get_string_from_utf8())
	check(MultiplayerSeats.validate(record.seats, record.members).is_empty(), "valid persisted association")
	var invalid: Dictionary = record.seats.duplicate(true)
	invalid.credentials["invalid"] = actor
	check(not MultiplayerSeats.validate(invalid, record.members).is_empty(), "malformed credential rejected")
	old.stop()
	replacement.stop()
	host.stop()
	var new_host := CoopSession.new()
	root.add_child(new_host)
	new_host.host(checkpoint.document, 0, "", "New host", "shared", false)
	var own_identity := new_host.credential
	check(not new_host.restore_embedded(checkpoint.document).is_empty(), "unknown host must explicitly select takeover")
	check(new_host.restore_embedded(checkpoint.document, record.host).is_empty(), "another host resumes complete save")
	check(new_host.credential == own_identity and new_host.members[new_host.token].name == "New host", "hosting does not impersonate old host credential")
	check(new_host.world.municipalities[actor].city.funds() == funds, "other saved treasury retained")
	check(new_host.seats.credentials.get(replacement.credential.sha256_text()) == actor, "successor can reconnect after host change")
	new_host.stop()
	for node in [host, old, replacement, new_host]:
		node.queue_free()
	print("Multiplayer seat checks: %d failures" % failures)
	quit(1 if failures else 0)
