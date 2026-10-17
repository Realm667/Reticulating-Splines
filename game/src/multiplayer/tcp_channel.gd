class_name CityTcpChannel
extends RefCounted
## Length-prefixed UTF-8 JSON. Reads and writes never wait for a complete frame.

const MAX_FRAME := 4 * 1024 * 1024
const IO_BUDGET := 256 * 1024
var socket: StreamPeerTCP
var input := PackedByteArray()
var output := PackedByteArray()
var limit := MAX_FRAME
var failed := false
var last_received := Time.get_ticks_msec()
var low_latency := false
var bytes_sent := 0
var bytes_received := 0
var ephemeral: Dictionary = {}


func send_latest(message: Dictionary) -> void:
	# Cursor/environment updates supersede older unsent values. Reliable commands
	# retain their order; never splice a new frame into a partially sent frame.
	if message.get("type") == "summary" and ephemeral.has("summary"):
		message = message.duplicate()
		message.values = ephemeral.summary.values.merged(message.values, true)
	ephemeral[str(message.type)] = message


func _init(peer: StreamPeerTCP = null, receive_limit := MAX_FRAME) -> void:
	socket = peer
	limit = receive_limit


func send(message: Dictionary) -> bool:
	return send_encoded(JSON.stringify(message).to_utf8_buffer())


func send_encoded(body: PackedByteArray) -> bool:
	if body.size() > MAX_FRAME or output.size() + body.size() + 4 > MAX_FRAME * 2:
		failed = true
		return false
	var header := PackedByteArray()
	header.resize(4)
	header.encode_u32(0, body.size())
	output.append_array(header)
	output.append_array(body)
	return true


func poll(max_messages := 64) -> Array[Dictionary]:
	var messages: Array[Dictionary] = []
	socket.poll()
	if socket.get_status() == StreamPeerTCP.STATUS_CONNECTING:
		if Time.get_ticks_msec() - last_received > 10000:
			failed = true
		return messages
	if socket.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		failed = true
		return messages
	if not low_latency:
		socket.set_no_delay(true)
		low_latency = true
	flush()
	var available := mini(socket.get_available_bytes(), mini(IO_BUDGET, maxi(0, limit + 4 - input.size())))
	if available > 0:
		var received := socket.get_partial_data(available)
		if received[0] != OK:
			failed = true
			return messages
		input.append_array(received[1])
		bytes_received += received[1].size()
		last_received = Time.get_ticks_msec()
	return decode_messages(max_messages)


func decode_messages(max_messages: int) -> Array[Dictionary]:
	var messages: Array[Dictionary] = []
	# Bound reads rather than rejecting a backlog of individually valid frames.
	var started := Time.get_ticks_usec()
	for _index in max_messages:
		if not messages.is_empty() and Time.get_ticks_usec() - started >= 2000:
			break
		if input.size() < 4:
			break
		var size := input.decode_u32(0)
		if size < 2 or size > limit:
			failed = true
			break
		if input.size() < size + 4:
			break
		var parser := JSON.new()
		if parser.parse(input.slice(4, size + 4).get_string_from_utf8()) != OK or not parser.data is Dictionary:
			failed = true
			break
		messages.append(parser.data)
		input = input.slice(size + 4)
	if Time.get_ticks_msec() - last_received > 60000:
		failed = true
	return messages


func close() -> void:
	socket.disconnect_from_host()
	failed = true


func flush() -> void:
	if not failed and output.is_empty() and not ephemeral.is_empty():
		var messages := ephemeral.values()
		ephemeral.clear()
		for message: Dictionary in messages:
			send(message)
	if failed or output.is_empty() or socket.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return
	var sent := socket.put_partial_data(output.slice(0, IO_BUDGET))
	if sent[0] != OK:
		failed = true
		return
	output = output.slice(int(sent[1]))
	bytes_sent += int(sent[1])
