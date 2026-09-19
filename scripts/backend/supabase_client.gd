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
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"apikey: %s" % key,
	])
	var token := access_token.strip_edges()
	if not token.is_empty() and not token.begins_with("sb_publishable_"):
		headers.append("Authorization: Bearer %s" % token)
	return headers


func request_json(method: String, url: String, headers: PackedStringArray, body: String = "") -> Dictionary:
	return await _request_json(method, url, headers, body, true)


# Post-match leaderboard submit must not share the cancellable menu HTTPRequest.
# Ghost flush / cancel_pre_match_requests use the shared _http and would abort it.
func request_json_independent(method: String, url: String, headers: PackedStringArray, body: String = "") -> Dictionary:
	return await _request_json(method, url, headers, body, false)


func _request_json(method: String, url: String, headers: PackedStringArray, body: String, use_shared: bool) -> Dictionary:
	var result := {
		"ok": false,
		"status": 0,
		"data": null,
		"error": "unavailable",
		"godot_request_error": 0,
		"godot_http_result": -1,
	}
	if not is_ready():
		result.error = "not_configured"
		return result
	if use_shared:
		cancel()
	var http := HTTPRequest.new()
	http.timeout = 8.0
	_host.add_child(http)
	if use_shared:
		_http = http
	var err := http.request(url, headers, _http_method(method), body)
	result.godot_request_error = err
	if err != OK:
		http.queue_free()
		if use_shared:
			_http = null
		result.error = "godot_request_%s" % error_string(err)
		return result
	var completed: Array = await http.request_completed
	if is_instance_valid(http):
		http.queue_free()
	if use_shared:
		_http = null
	result.godot_http_result = int(completed[0])
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
