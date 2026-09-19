extends RefCounted

const ConfigScript := preload("res://scripts/backend/supabase_config.gd")

var _host: Node
var _http: HTTPRequest = null


func _init(host: Node) -> void:
	_host = host


func cancel() -> void:
	if _http != null and is_instance_valid(_http):
		_http.cancel_request()


func is_ready() -> bool:
	return ConfigScript.is_configured() and _host != null


func auth_headers(access_token: String = "") -> PackedStringArray:
	var key := ConfigScript.anon_key()
	var token := access_token if not access_token.is_empty() else key
	return PackedStringArray([
		"Content-Type: application/json",
		"apikey: %s" % key,
		"Authorization: Bearer %s" % token,
	])


func request_json(method: String, url: String, headers: PackedStringArray, body: String = "") -> Dictionary:
	var result := {
		"ok": false,
		"status": 0,
		"data": null,
		"error": "unavailable",
	}
	if not is_ready():
		result.error = "not_configured"
		return result
	cancel()
	_http = HTTPRequest.new()
	_http.timeout = 8.0
	_host.add_child(_http)
	var err := _http.request(url, headers, _http_method(method), body)
	if err != OK:
		_http.queue_free()
		_http = null
		result.error = "request_failed"
		return result
	var completed: Array = await _http.request_completed
	if _http != null and is_instance_valid(_http):
		_http.queue_free()
	_http = null
	var status := int(completed[1])
	var raw: PackedByteArray = completed[3]
	result.status = status
	var text := raw.get_string_from_utf8()
	var parsed: Variant = null
	if not text.is_empty():
		var json := JSON.new()
		if json.parse(text) == OK:
			parsed = json.data
	result.data = parsed
	result.ok = status >= 200 and status < 300
	result.error = "" if result.ok else "http_%d" % status
	return result


func _http_method(method: String) -> HTTPClient.Method:
	match method:
		"POST":
			return HTTPClient.METHOD_POST
		"PATCH":
			return HTTPClient.METHOD_PATCH
		"PUT":
			return HTTPClient.METHOD_PUT
		"DELETE":
			return HTTPClient.METHOD_DELETE
		_:
			return HTTPClient.METHOD_GET
