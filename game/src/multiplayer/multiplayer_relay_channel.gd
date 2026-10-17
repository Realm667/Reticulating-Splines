class_name MultiplayerRelayChannel
extends CityTcpChannel
## Same bounded framing as LAN, carried over a TLS WebSocket relay.

var wire := WebSocketPeer.new()
var ready := false
const CHUNK := 65536


func _init(url: String, authorization := "", receive_limit := MAX_FRAME) -> void:
	super(null, receive_limit)
	wire.inbound_buffer_size = MAX_FRAME + CHUNK
	wire.outbound_buffer_size = IO_BUDGET * 2
	wire.max_queued_packets = 128
	wire.heartbeat_interval = 20
	if not authorization.is_empty():
		wire.handshake_headers = PackedStringArray(["Authorization: Bearer " + authorization])
	failed = wire.connect_to_url(url) != OK


func poll(max_messages := 64) -> Array[Dictionary]:
	wire.poll()
	var state := wire.get_ready_state()
	if state == WebSocketPeer.STATE_CLOSED or state == WebSocketPeer.STATE_CLOSING:
		failed = true
	if not ready and Time.get_ticks_msec() - last_received > 15000:
		failed = true
	if failed or state != WebSocketPeer.STATE_OPEN:
		return []
	var budget := IO_BUDGET
	while wire.get_available_packet_count() > 0 and budget > 0 and input.size() < limit + 4:
		var packet := wire.get_packet()
		if wire.was_string_packet():
			var parser := JSON.new()
			if ready or parser.parse(packet.get_string_from_utf8()) != OK or not parser.data is Dictionary or not parser.data.get("type") is String or parser.data.type != "ready":
				failed = true
				break
			ready = true
			wire.set_no_delay(true)
		elif not ready or packet.size() > CHUNK:
			failed = true
			break
		else:
			input.append_array(packet)
			bytes_received += packet.size()
			budget -= packet.size()
		last_received = Time.get_ticks_msec()
	flush()
	return decode_messages(max_messages)


func flush() -> void:
	if failed or not ready or wire.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	if output.is_empty() and not ephemeral.is_empty():
		var messages := ephemeral.values()
		ephemeral.clear()
		for message: Dictionary in messages:
			send(message)
	var budget := IO_BUDGET
	while not output.is_empty() and budget > 0 and wire.get_current_outbound_buffered_amount() < IO_BUDGET:
		var count := mini(CHUNK, output.size())
		var error := wire.put_packet(output.slice(0, count))
		if error == ERR_OUT_OF_MEMORY or error == ERR_BUSY:
			break
		if error != OK:
			failed = true
			break
		output = output.slice(count)
		bytes_sent += count
		budget -= count


func close() -> void:
	wire.close()
	failed = true
