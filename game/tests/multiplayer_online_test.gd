extends SceneTree

var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: " + message)


func run() -> void:
	check_activity_cities()
	await check_activity_restore()
	var valid := {"id": "a".repeat(32), "city": "City", "host": "Host", "build": CoopSession.NETWORK_BUILD,
		"mode": "coop", "phase": "lobby", "players": 2, "locked": true, "open": true, "address": "203.0.113.5", "port": 20000}
	check(not MultiplayerLanBrowser.validated_game(valid).is_empty(), "public metadata accepted")
	check(MultiplayerLanBrowser.validated_game(valid).address == "203.0.113.5", "directory supplies direct endpoint")
	for address in ["relay:abc", "https://example.com", "", "127.0.0.999"]:
		var invalid := valid.duplicate()
		invalid.address = address
		check(MultiplayerLanBrowser.validated_game(invalid).is_empty(), "invalid endpoint rejected")
	for key in valid:
		var invalid := valid.duplicate()
		invalid[key] = []
		check(MultiplayerLanBrowser.validated_game(invalid).is_empty(), "invalid field rejected: " + key)
	var listener := TCPServer.new()
	check(listener.listen(0, "127.0.0.1") == OK, "local websocket fixture listens")
	var channel := MultiplayerRelayChannel.new("ws://127.0.0.1:%d" % listener.get_local_port(), "", 65536)
	var server := WebSocketPeer.new()
	server.inbound_buffer_size = 262144
	server.outbound_buffer_size = 262144
	var accepted := false
	var until := Time.get_ticks_msec() + 3000
	while server.get_ready_state() != WebSocketPeer.STATE_OPEN and Time.get_ticks_msec() < until:
		channel.poll()
		if not accepted and listener.is_connection_available():
			check(server.accept_stream(listener.take_connection()) == OK, "websocket accepts")
			accepted = true
		if accepted:
			server.poll()
		await process_frame
	check(server.get_ready_state() == WebSocketPeer.STATE_OPEN, "websocket handshake")
	server.send_text('{"type":"ready"}')
	var body := JSON.stringify({"type": "test", "value": "x".repeat(65500)}).to_utf8_buffer()
	var framed := PackedByteArray()
	framed.resize(4)
	framed.encode_u32(0, body.size())
	framed.append_array(body)
	server.put_packet(framed.slice(0, 32768))
	server.put_packet(framed.slice(32768))
	var received: Array[Dictionary] = []
	until = Time.get_ticks_msec() + 3000
	while received.is_empty() and Time.get_ticks_msec() < until:
		server.poll()
		received.append_array(channel.poll())
		await process_frame
	check(received.size() == 1 and received[0].value.length() == 65500, "fragmented frame near host receive limit")
	channel.send({"type": "reply", "value": 42})
	until = Time.get_ticks_msec() + 3000
	while server.get_available_packet_count() == 0 and Time.get_ticks_msec() < until:
		channel.poll()
		server.poll()
		await process_frame
	check(server.get_available_packet_count() > 0, "outbound frame arrives")
	if server.get_available_packet_count() > 0:
		var packet := server.get_packet()
		check(packet.decode_u32(0) == packet.size() - 4, "length prefix preserved")
		check(JSON.parse_string(packet.slice(4).get_string_from_utf8()).value == 42, "payload preserved")
	server.put_packet("x".repeat(65537).to_utf8_buffer())
	until = Time.get_ticks_msec() + 2000
	while not channel.failed and Time.get_ticks_msec() < until:
		server.poll()
		channel.poll()
		await process_frame
	check(channel.failed, "oversized relay packet rejected")
	channel.close()
	server.close()
	listener.stop()
	await check_admission()
	print("Multiplayer online tests: %d failure(s)" % failures)
	quit(1 if failures else 0)


func check_activity_cities() -> void:
	var host := CoopSession.new()
	var online := MultiplayerOnline.new()
	online.session = host
	host.hosting = true
	host.waiting_for_start = false
	host.session_id = "a".repeat(32)
	host.world = CoopWorld.new()
	check(host.world.open(Sc2xDocument.create_empty(128, "Activity fixture").document), "activity fixture opens")
	host.world.city.document.set_misc_u32(Sc2MiscLayout.NORMAL_POPULATION, 1234)
	var first := online.activity_cities()
	check(first.size() == 1 and first[0].population == 1234, "co-op reports one city")
	online.room = "different-public-room"
	online.secret = "different-public-token"
	host.world.city.document.set_misc_u32(Sc2MiscLayout.NORMAL_POPULATION, 800)
	check(online.activity_cities()[0].id == first[0].id and online.activity_cities()[0].population == 800, "rehosting preserves ID and reports decline")
	host.waiting_for_start = true
	check(online.activity_cities().is_empty(), "lobby omits city reports")
	host.waiting_for_start = false
	host.hosting = false
	check(online.activity_cities().is_empty(), "joining clients never report cities")
	host.hosting = true
	for shared: SharedWorld in [SharedWorld.new(), RegionWorld.new()]:
		check(shared.open(Sc2xDocument.create_empty(128, "Municipal fixture").document), "municipal fixture opens")
		check(shared.add_player("b".repeat(48)).is_empty(), "first municipality")
		check(shared.add_player("c".repeat(48)).is_empty(), "second municipality")
		host.world = shared
		shared.municipalities[shared.actors[0]].city.document.set_misc_u32(Sc2MiscLayout.NORMAL_POPULATION, 100)
		shared.municipalities[shared.actors[1]].city.document.set_misc_u32(Sc2MiscLayout.NORMAL_POPULATION, 200)
		var cities := online.activity_cities()
		check(cities.size() == 2 and cities[0].id != cities[1].id and cities[0].population + cities[1].population == 300, "each municipality has distinct ID and own population")
		var saved_starts := host.starts.saved()
		host.starts = MultiplayerStarts.new()
		host.starts.restore(saved_starts)
		check(online.activity_cities() == cities, "restored round preserves city identities")
		host.starts.round_number += 1
		check(online.activity_cities()[0].id != cities[0].id, "new rematch counts newly founded municipalities")
	online.free()
	host.free()


func check_activity_restore() -> void:
	var host := CoopSession.new()
	var restored := CoopSession.new()
	root.add_child(host)
	root.add_child(restored)
	host.set_process(false)
	restored.set_process(false)
	check(host.host(Sc2xDocument.create_empty(128, "Saved activity city").document, 0, "", "Host", "shared", false).is_empty(), "saved activity host starts")
	host.waiting_for_start = false
	var online := MultiplayerOnline.new()
	online.session = host
	var before := online.activity_cities()
	var checkpoint := host.city_checkpoint()
	check(checkpoint.error.is_empty(), "activity city checkpoint saves")
	var selected_seat := host.token
	host.stop()
	check(restored.host(checkpoint.document, 0, "", "Restored host", "shared", false).is_empty(), "restored activity host starts")
	check(restored.restore_embedded(checkpoint.document, selected_seat).is_empty(), "activity checkpoint restores")
	restored.waiting_for_start = false
	online.session = restored
	check(online.activity_cities() == before, "actual save and restore retains city ID and population")
	restored.stop()
	online.free()
	host.queue_free()
	restored.queue_free()
	await process_frame


func check_admission() -> void:
	var host := CoopSession.new()
	root.add_child(host)
	host.set_process(false)
	host.server = TCPServer.new()
	check(host.server.listen(0, "127.0.0.1") == OK, "probe listener")
	host.online = MultiplayerOnline.new()
	host.online.checking = true
	host.online.probe_nonce = "a".repeat(64)
	host.online.deadline = Time.get_ticks_msec() + 8000
	for id in range(1, CoopSession.MAX_PLAYERS):
		host.channels[id] = CityTcpChannel.new()
	for nonce in ["b".repeat(64), "a".repeat(64), "a".repeat(64)]:
		var socket := StreamPeerTCP.new()
		socket.connect_to_host("127.0.0.1", host.server.get_local_port())
		var peer := CityTcpChannel.new(socket)
		peer.send({"type": "reachability", "nonce": nonce})
		var replies: Array[Dictionary] = []
		var expected: bool = nonce == host.online.probe_nonce
		var until := Time.get_ticks_msec() + 1500
		while not peer.failed and replies.is_empty() and Time.get_ticks_msec() < until:
			host.admission.poll(host)
			replies.append_array(peer.poll())
			await process_frame
		check((not replies.is_empty()) == expected, "only current nonce receives a proof, even at player capacity")
		if expected:
			check(replies[0].get("type") == "reachability_ok" and replies[0].get("nonce") == nonce, "probe proof matches nonce")
		peer.close()
	check(host.channels.size() == 7 and host.identities.is_empty(), "probe does not alter player slots or identities")
	host.online.checking = true
	host.online.completed(HTTPRequest.RESULT_SUCCESS, 503, PackedStringArray(), "not json".to_utf8_buffer())
	check(host.online.reachability == "unavailable", "server failure is not host unreachable")
	host.online.checking = true
	host.online.completed(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), '{"version":2,"status":"unreachable"}'.to_utf8_buffer())
	check(host.online.reachability == "unreachable", "negative external test is distinct")
	host.online.free()
	host.online = null
	host.channels.clear()
	host.server.stop()
	host.queue_free()
	await process_frame
