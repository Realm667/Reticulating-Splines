class_name MultiplayerLanDiscovery
extends Node
## Bounded IPv4 LAN discovery. No credentials, city data or gameplay commands.

signal results_changed
signal search_finished

const MAGIC := "reticulating-splines-lan"
const VERSION := 1
const FIRST_PORT := 20001
const PORT_COUNT := 8
const SEARCH_MSEC := 4000
const RESULT_MSEC := 15000
const MAX_PACKET := 1400
const MAX_RESULTS := 64
var responder: PacketPeerUDP
var seeker: PacketPeerUDP
var description_source: Callable
var results: Dictionary = {}
var searching := false
var nonce := ""
var deadline := 0
var next_probe := 0
var probes := 0
var targets := PackedStringArray(["255.255.255.255", "127.0.0.1"])
var ports: Array[int] = []
var response_times: Dictionary = {}
var rate_epoch := 0
var response_count := 0


func _init() -> void:
	for index in PORT_COUNT:
		ports.append(FIRST_PORT + index)
	set_process(false)


func advertise(source: Callable) -> Error:
	stop_advertising()
	for port in ports:
		var socket := PacketPeerUDP.new()
		var error := socket.bind(port, "0.0.0.0", 16384)
		if error == OK:
			responder = socket
			description_source = source
			set_process(true)
			return OK
	return ERR_CANT_OPEN


func stop_advertising() -> void:
	if responder != null:
		responder.close()
	responder = null
	description_source = Callable()
	response_times.clear()
	set_process(searching or not results.is_empty())


func search() -> Error:
	cancel_search()
	results.clear()
	results_changed.emit()
	seeker = PacketPeerUDP.new()
	var error := seeker.bind(0, "0.0.0.0", 65536)
	if error != OK:
		seeker.close()
		seeker = null
		return error
	seeker.set_broadcast_enabled(true)
	nonce = Crypto.new().generate_random_bytes(16).hex_encode()
	searching = true
	deadline = Time.get_ticks_msec() + SEARCH_MSEC
	next_probe = 0
	probes = 0
	set_process(true)
	return OK


func cancel_search(clear_results := false) -> void:
	if seeker != null:
		seeker.close()
	seeker = null
	searching = false
	nonce = ""
	if clear_results:
		results.clear()
	set_process(responder != null or not results.is_empty())


func _exit_tree() -> void:
	cancel_search(true)
	stop_advertising()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if responder != null:
		poll_requests(now)
	if searching:
		if now >= deadline:
			cancel_search()
			search_finished.emit()
		else:
			if probes < 3 and now >= next_probe:
				var query := JSON.stringify({"magic": MAGIC, "version": VERSION, "type": "query", "nonce": nonce}).to_utf8_buffer()
				for address in targets:
					for port in ports:
						if seeker.set_dest_address(address, port) == OK:
							seeker.put_packet(query)
				probes += 1
				next_probe = now + 1000
			poll_offers(now)
	var expired := false
	for key: String in results.keys():
		if now - int(results[key].seen) >= RESULT_MSEC:
			results.erase(key)
			expired = true
	if expired:
		results_changed.emit()
	if responder == null and not searching and results.is_empty():
		set_process(false)


func poll_requests(now: int) -> void:
	if now - rate_epoch >= 1000:
		rate_epoch = now
		response_count = 0
		response_times.clear()
	for index in mini(16, responder.get_available_packet_count()):
		var packet := responder.get_packet()
		var address := responder.get_packet_ip()
		var port := responder.get_packet_port()
		var query := decode(packet)
		if query.is_empty() or query.type != "query":
			continue
		var endpoint := address + ":" + str(port)
		if response_count >= 16 or now - int(response_times.get(endpoint, -1000)) < 500:
			continue
		var info: Dictionary = description_source.call()
		if info.is_empty():
			continue
		info.merge({"magic": MAGIC, "version": VERSION, "type": "offer", "nonce": query.nonce}, true)
		var encoded := JSON.stringify(info).to_utf8_buffer()
		if encoded.size() > MAX_PACKET:
			continue
		response_count += 1
		response_times[endpoint] = now
		if responder.set_dest_address(address, port) == OK:
			responder.put_packet(encoded)


func poll_offers(now: int) -> void:
	for index in mini(32, seeker.get_available_packet_count()):
		var packet := seeker.get_packet()
		var address := seeker.get_packet_ip()
		accept_offer(packet, address, now)


func accept_offer(packet: PackedByteArray, address: String, now: int) -> void:
	var info := decode(packet)
	if not searching or info.is_empty() or info.nonce != nonce or info.type != "offer":
		return
	if not address.is_valid_ip_address() or not valid_nonce(info.get("session")):
		return
	for field in ["host", "city", "build", "mode", "phase"]:
		if not info.get(field) is String or info[field].length() > 128:
			return
	if not info.mode in ["coop", "shared", "region"] or not info.phase in ["lobby", "running"]:
		return
	if not valid_integer(info.get("port"), 1, 65535) or not valid_integer(info.get("players"), 1, 8):
		return
	if not info.get("locked") is bool or not info.get("open") is bool:
		return
	var key: String = info.session + ":" + str(int(info.port))
	if not results.has(key) and results.size() >= MAX_RESULTS:
		return
	# The datagram sender is the endpoint; never trust an advertised host address.
	# Prefer the LAN address over loopback if both routes discover the same process.
	if address.begins_with("127.") and results.has(key):
		address = results[key].address
	results[key] = {"address": address, "port": int(info.port), "host": plain_name(info.host),
		"city": plain_name(info.city), "mode": info.mode, "phase": info.phase,
		"build": info.build, "players": int(info.players), "locked": info.locked,
		"open": info.open, "seen": now}
	results_changed.emit()


static func decode(packet: PackedByteArray) -> Dictionary:
	if packet.is_empty() or packet.size() > MAX_PACKET:
		return {}
	var parser := JSON.new()
	if parser.parse(packet.get_string_from_utf8()) != OK or not parser.data is Dictionary:
		return {}
	var data: Dictionary = parser.data
	if not data.get("magic") is String or not data.get("type") is String or not valid_nonce(data.get("nonce")):
		return {}
	if not valid_integer(data.get("version"), VERSION, VERSION):
		return {}
	return data if data.magic == MAGIC else {}


static func valid_nonce(value: Variant) -> bool:
	if not value is String or value.length() != 32:
		return false
	for character in value:
		if not character in "0123456789abcdef":
			return false
	return true


static func valid_integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value == floor(value) and value >= minimum and value <= maximum


static func plain_name(value: String) -> String:
	var result := ""
	for character in value:
		if character.unicode_at(0) >= 32 and character.unicode_at(0) != 127:
			result += character
	return result.strip_edges().left(64)
