class_name MultiplayerAdmission
extends RefCounted
## Classify the first bounded frame before consuming a player slot.

var incoming: Array[Dictionary] = []


func close() -> void:
	for entry: Dictionary in incoming:
		entry.channel.close()
	incoming.clear()


func poll(session: CoopSession) -> void:
	if session.server.is_connection_available():
		var peer := session.server.take_connection()
		if incoming.size() >= 8:
			peer.disconnect_from_host()
		else:
			incoming.append({"channel": CityTcpChannel.new(peer, 65536), "until": Time.get_ticks_msec() + 10000, "reply": false})
	for entry: Dictionary in incoming.duplicate():
		var channel: CityTcpChannel = entry.channel
		var messages := channel.poll(1)
		if entry.reply:
			if channel.output.is_empty():
				channel.failed = true
		elif not messages.is_empty():
			var message: Dictionary = messages[0]
			if message.get("type") == "compatibility" and MultiplayerLanDiscovery.valid_nonce(message.get("nonce")):
				channel.send({"type": "compatibility", "nonce": message.nonce,
					"protocol": CoopSession.PROTOCOL, "build": CoopSession.NETWORK_BUILD,
					"open": session.channels.size() < CoopSession.MAX_PLAYERS - 1})
				entry.reply = true
				entry.until = Time.get_ticks_msec() + 1000
			elif message.get("type") == "reachability":
				if session.online != null and session.online.accept_probe(message):
					channel.send({"type": "reachability_ok", "nonce": message.nonce})
					entry.reply = true
					entry.until = Time.get_ticks_msec() + 1000
				else:
					channel.failed = true
			elif session.channels.size() < CoopSession.MAX_PLAYERS - 1:
				var id := session.next_peer
				session.next_peer += 1
				session.channels[id] = channel
				session.handshake_started[id] = Time.get_ticks_msec()
				session.received_messages[id] = messages
				incoming.erase(entry)
				continue
			else:
				channel.failed = true
		if channel.failed or Time.get_ticks_msec() >= entry.until:
			channel.close()
			incoming.erase(entry)
