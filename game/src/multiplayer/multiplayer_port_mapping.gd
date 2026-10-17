class_name MultiplayerPortMapping
extends Node
## Router calls run off the main thread. Only mappings carrying our random marker
## may be renewed or removed; a pre-existing mapping is never replaced.

signal changed
var state := "checking"
var port := 0
var marker := ""
var device: UPNPDevice
var worker: Thread
var closing := false
var owned := false
var renew_at := 0
var last_result := -1


func start(value: int) -> void:
	port = value
	marker = "RS-" + Crypto.new().generate_random_bytes(12).hex_encode()
	launch("create")


func launch(operation: String) -> void:
	worker = Thread.new()
	if worker.start(work.bind(operation)) != OK:
		worker = null
		state = "unavailable"
		changed.emit()


func finish() -> void:
	closing = true
	if worker == null:
		if owned:
			launch("remove")
		else:
			queue_free()


func _process(_delta: float) -> void:
	if worker != null and not worker.is_alive():
		var result: Dictionary = worker.wait_to_finish()
		worker = null
		owned = result.get("owned", false)
		state = result.get("state", "unavailable")
		last_result = result.get("result", -1)
		renew_at = Time.get_ticks_msec() + 1800000
		changed.emit()
		if closing:
			finish()
	elif worker == null and owned and Time.get_ticks_msec() >= renew_at:
		launch("renew")


func _exit_tree() -> void:
	# Shutdown cannot abandon a running router operation. Normal leave cleans up
	# asynchronously; an abrupt process crash is covered by the one-hour lease.
	if worker != null:
		var result: Dictionary = worker.wait_to_finish()
		owned = result.get("owned", false)
		worker = null
	if owned:
		work("remove")


func work(operation: String) -> Dictionary:
	if operation == "create":
		device = discover_gateway()
		if device == null or not device.is_valid_gateway():
			return {"state": "unavailable"}
	var entry := mapping()
	var ours: bool = entry.get("NewPortMappingDescription", "") == marker and entry.get("NewInternalClient", "") == device.igd_our_addr and entry.get("NewInternalPort", "") == str(port)
	if operation == "remove":
		if ours:
			device.delete_port_mapping(port, "TCP")
		return {"state": "closed"}
	if operation == "create" and entry.get("errorCode", "") != "714":
		return {"state": "existing" if entry.has("NewInternalPort") else "unavailable"}
	if operation == "renew" and not ours:
		return {"state": "unavailable"}
	# Do not fall back to a permanent lease on gateways that reject expiry.
	var result := device.add_port_mapping(port, port, marker, "TCP", 3600)
	return {"state": "mapped" if result == UPNP.UPNP_RESULT_SUCCESS else "unavailable", "owned": result == UPNP.UPNP_RESULT_SUCCESS or ours, "result": result}


func mapping() -> Dictionary:
	var url := device.igd_control_url
	if not url.begins_with("http://"):
		return {}
	var authority := url.trim_prefix("http://").get_slice("/", 0)
	var host := authority.get_slice(":", 0)
	var target_port := authority.get_slice(":", 1).to_int() if authority.contains(":") else 80
	var path := url.substr(7 + authority.length())
	var client := HTTPClient.new()
	client.read_chunk_size = 4096
	if client.connect_to_host(host, target_port) != OK:
		return {}
	var until := Time.get_ticks_msec() + 2000
	var sent := false
	var received := false
	var data := PackedByteArray()
	while Time.get_ticks_msec() < until:
		if client.poll() != OK:
			break
		var status := client.get_status()
		if status == HTTPClient.STATUS_CONNECTED and not sent:
			var service := device.igd_service_type
			var body := '<?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body><u:GetSpecificPortMappingEntry xmlns:u="%s"><NewRemoteHost></NewRemoteHost><NewExternalPort>%d</NewExternalPort><NewProtocol>TCP</NewProtocol></u:GetSpecificPortMappingEntry></s:Body></s:Envelope>' % [service.xml_escape(), port]
			sent = true
			if client.request(HTTPClient.METHOD_POST, path, PackedStringArray(['Content-Type: text/xml; charset="utf-8"', 'SOAPAction: "%s#GetSpecificPortMappingEntry"' % service]), body) != OK:
				break
		if client.has_response():
			received = true
		if status == HTTPClient.STATUS_BODY:
			data.append_array(client.read_response_body_chunk())
			if data.size() > 8192:
				break
		elif received and status in [HTTPClient.STATUS_CONNECTED, HTTPClient.STATUS_DISCONNECTED]:
			client.close()
			return parse_mapping(data)
		elif status in [HTTPClient.STATUS_CANT_CONNECT, HTTPClient.STATUS_CANT_RESOLVE, HTTPClient.STATUS_CONNECTION_ERROR, HTTPClient.STATUS_DISCONNECTED]:
			break
		OS.delay_msec(5)
	client.close()
	return {}


static func parse_mapping(data: PackedByteArray) -> Dictionary:
	var parser := XMLParser.new()
	if parser.open_buffer(data) != OK:
		return {}
	var result := {}
	var key := ""
	while parser.read() == OK:
		if parser.get_node_type() == XMLParser.NODE_ELEMENT:
			key = parser.get_node_name().get_slice(":", parser.get_node_name().get_slice_count(":") - 1)
		elif parser.get_node_type() == XMLParser.NODE_TEXT and key in ["NewInternalClient", "NewInternalPort", "NewPortMappingDescription", "errorCode"]:
			result[key] = parser.get_node_data().strip_edges()
		elif parser.get_node_type() == XMLParser.NODE_ELEMENT_END:
			key = ""
	return result


func discover_gateway() -> UPNPDevice:
	var upnp := UPNP.new()
	if upnp.discover(1500, 2) != UPNP.UPNP_RESULT_SUCCESS:
		return null
	return upnp.get_gateway()
