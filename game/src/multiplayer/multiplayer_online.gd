class_name MultiplayerOnline
extends Node
## Discovery only: ongoing games do not depend on the directory being available.

const DEFAULT_URL := "https://rs.realm667.com"
const API := "/api/multiplayer/v2"
var session: CoopSession
var room := ""
var secret := ""
var registered := false
var closing := false
var pending := false
var deleting := false
var next_update := 0
var last_update := 0
var signature := ""
var failed_reported := false
var http := HTTPClient.new()
var request_sent := false
var response_started := false
var response_code := 0
var response_body := PackedByteArray()
var deadline := 0
var endpoint_path := ""
var request_body := ""
var metadata_check := 0


static func base_url() -> String:
	var configured := OS.get_environment("RS_MULTIPLAYER_URL").trim_suffix("/")
	if configured.begins_with("https://") or configured.begins_with("http://127.0.0.1:") or configured.begins_with("http://localhost:"):
		return configured
	return DEFAULT_URL


static func websocket_url(path: String) -> String:
	# Explicit legacy endpoints only; never selected from the directory.
	return base_url().replace("https://", "wss://").replace("http://", "ws://") + "/api/multiplayer/v1" + path


func start(owner: CoopSession) -> void:
	session = owner
	http.read_chunk_size = 8192
	room = Crypto.new().generate_random_bytes(16).hex_encode()
	secret = Crypto.new().generate_random_bytes(32).hex_encode()
	announce()


func _exit_tree() -> void:
	http.close()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if pending:
		if now >= deadline or http.poll() != OK:
			completed(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())
			return
		var status := http.get_status()
		if status == HTTPClient.STATUS_CONNECTED and not request_sent:
			var method := HTTPClient.METHOD_DELETE if deleting else HTTPClient.METHOD_PUT
			var headers := PackedStringArray(["Content-Type: application/json", "Authorization: Bearer " + secret])
			request_sent = true
			if http.request(method, endpoint_path, headers, request_body) != OK:
				completed(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())
			return
		if http.has_response() and not response_started:
			response_code = http.get_response_code()
			response_started = true
		if status == HTTPClient.STATUS_BODY:
			response_body.append_array(http.read_response_body_chunk())
			if response_body.size() > 8192:
				completed(HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED, 0, PackedStringArray(), PackedByteArray())
		elif response_started and status in [HTTPClient.STATUS_CONNECTED, HTTPClient.STATUS_DISCONNECTED]:
			completed(HTTPRequest.RESULT_SUCCESS, response_code, PackedStringArray(), response_body)
		elif status in [HTTPClient.STATUS_CANT_RESOLVE, HTTPClient.STATUS_CANT_CONNECT, HTTPClient.STATUS_CONNECTION_ERROR, HTTPClient.STATUS_TLS_HANDSHAKE_ERROR, HTTPClient.STATUS_DISCONNECTED]:
			completed(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())
	elif now >= metadata_check:
		metadata_check = now + 1000
		tick()


func finish() -> void:
	closing = true
	# Complete any in-flight registration before deleting it.
	if not pending:
		announce()


func tick() -> void:
	if pending or closing:
		return
	var now := Time.get_ticks_msec()
	if now >= next_update or (registered and now - last_update >= 5000 and JSON.stringify(description()) != signature):
		announce()


func announce() -> void:
	deleting = closing
	var info := description() if not deleting else {}
	signature = JSON.stringify(info)
	request_body = "" if deleting else JSON.stringify({"version": 2, "game": info})
	last_update = Time.get_ticks_msec()
	next_update = last_update + 60000
	pending = true
	http.close()
	request_sent = false
	response_started = false
	response_code = 0
	response_body = PackedByteArray()
	deadline = last_update + 8000
	var url := base_url()
	var secure := url.begins_with("https://")
	var authority := url.trim_prefix("https://").trim_prefix("http://")
	var slash := authority.find("/")
	var prefix := ""
	if slash >= 0:
		prefix = authority.substr(slash)
		authority = authority.left(slash)
	var host := authority
	var port := 443 if secure else 80
	var colon := authority.rfind(":")
	if colon > authority.rfind("]"):
		host = authority.left(colon)
		port = authority.substr(colon + 1).to_int()
	host = host.trim_prefix("[").trim_suffix("]")
	endpoint_path = prefix + API + "/games/" + room
	if http.connect_to_host(host, port, TLSOptions.client() if secure else null) != OK:
		completed(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())


func completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	pending = false
	http.close()
	if deleting:
		# Unreachable directories expire listings automatically after three minutes.
		queue_free()
		return
	var parser := JSON.new()
	var success: bool = result == HTTPRequest.RESULT_SUCCESS and code == 200
	if success:
		success = parser.parse(body.get_string_from_utf8()) == OK and parser.data is Dictionary
	if success:
		success = parser.data.get("version") == 2 and parser.data.get("id") == room
	if success:
		if not registered:
			session.feedback.emit("Game is visible online.")
		registered = true
		failed_reported = false
	else:
		registered = false
		if not closing and not failed_reported:
			failed_reported = true
			session.feedback.emit("Online listing unavailable. Direct connections still work.")
	if closing:
		announce()


func description() -> Dictionary:
	var data := session.lan_description()
	data.erase("session")
	return data
