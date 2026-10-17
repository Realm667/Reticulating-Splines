extends SceneTree

var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: " + message)


func run() -> void:
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
