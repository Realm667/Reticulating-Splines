class_name CloudTransport
extends Node
## One request node per operation allows UI reads while a chunk upload runs.
## Redirects are forbidden: bearer credentials never follow another origin.

const DEFAULT_ENDPOINT := "https://rs.realm667.com/cloud-saves/api/cloud/v1"
var endpoint := DEFAULT_ENDPOINT
var token := ""


static func valid_endpoint(value: String) -> bool:
	var pattern := RegEx.new()
	pattern.compile("^(https://[A-Za-z0-9.-]+(?::[0-9]{1,5})?|http://(?:127\\.0\\.0\\.1|localhost):[0-9]{1,5})(?:/[A-Za-z0-9_-]+)*/?$")
	return pattern.search(value) != null


func request(method: int, route: String, body: Variant = null, binary := false) -> Dictionary:
	if not valid_endpoint(endpoint) or not route.begins_with("/") or route.contains(".."):
		return {"ok": false, "error": "invalid_endpoint", "code": 0}
	var http := HTTPRequest.new()
	http.timeout = 30.0
	http.max_redirects = 0
	http.body_size_limit = Sc2xDocument.MAX_ARCHIVE_BYTES if binary else 4 * 1024 * 1024
	http.use_threads = true
	add_child(http)
	var headers := PackedStringArray(["Accept: application/json"])
	if not token.is_empty():
		headers.append("Authorization: Bearer " + token)
	var payload := PackedByteArray()
	if body is PackedByteArray:
		headers.append("Content-Type: application/octet-stream")
		payload = body
	elif body != null:
		headers.append("Content-Type: application/json")
		payload = JSON.stringify(body).to_utf8_buffer()
	var result := http.request_raw(endpoint.trim_suffix("/") + route, headers, method, payload)
	if result != OK:
		http.queue_free()
		return {"ok": false, "error": "offline", "code": 0}
	var reply: Array = await http.request_completed
	http.queue_free()
	if reply[0] != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "error": "offline", "code": 0}
	var code := int(reply[1])
	if binary and code >= 200 and code < 300:
		return {"ok": true, "error": "", "code": code, "bytes": reply[3]}
	var data: Variant = JSON.parse_string(reply[3].get_string_from_utf8())
	if not data is Dictionary:
		return {"ok": false, "error": "invalid_response", "code": code}
	data["ok"] = code >= 200 and code < 300
	data["error"] = str(data.get("error", "" if data.ok else "request_failed"))
	data["code"] = code
	return data
