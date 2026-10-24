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
	http.process_mode = Node.PROCESS_MODE_ALWAYS
	# Browsers decompress gzip before Godot reads the body, then still report
	# Content-Encoding: gzip. Inflating that JSON again drops the response.
	if OS.has_feature("web"):
		http.accept_gzip = false
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
	var parsed_ok := true
	if not text.is_empty():
		var json := JSON.new()
		if json.parse(text) == OK:
			parsed = json.data
		else:
			parsed_ok = false
	result.data = parsed
	result.ok = status >= 200 and status < 300 and parsed_ok
	if result.ok:
		result.error = ""
	elif not parsed_ok:
		result.error = "invalid_json"
	else:
		result.error = "http_%d" % status
	if not result.ok:
		result.body_text = _public_body(text)
		result.content_type = _content_type_label(headers)
		result.authorization = _authorization_label(headers)
		result.apikey = "present" if _has_header(headers, "apikey") else "missing"
	return result


func _has_header(headers: PackedStringArray, name: String) -> bool:
	var prefix := name.to_lower() + ":"
	for header in headers:
		if str(header).strip_edges().to_lower().begins_with(prefix):
			return true
	return false


func _header_value(headers: PackedStringArray, name: String) -> String:
	var prefix := name.to_lower() + ":"
	for header in headers:
		var text := str(header).strip_edges()
		if text.to_lower().begins_with(prefix):
			return text.substr(prefix.length()).strip_edges()
	return ""


func _content_type_label(headers: PackedStringArray) -> String:
	var value := _header_value(headers, "Content-Type").to_lower()
	if value.begins_with("application/json"):
		return "application/json"
	if value.is_empty():
		return "missing"
	return "other"


func _authorization_label(headers: PackedStringArray) -> String:
	var value := _header_value(headers, "Authorization")
	if value.is_empty():
		return "missing"
	if value.to_lower().begins_with("bearer ") and value.length() > 7:
		return "bearer"
	return "other"


func _public_body(text: String) -> String:
	var clean := text.strip_edges()
	if clean.is_empty():
		return ""
	var jwt := RegEx.new()
	if jwt.compile("eyJ[A-Za-z0-9_\\-]+(?:\\.[A-Za-z0-9_\\-]+){1,2}") == OK:
		clean = jwt.sub(clean, "[redacted]", true)
	if clean.contains("sb_secret") or clean.to_lower().contains("service_role"):
		return "[redacted]"
	if clean.length() > 800:
		clean = clean.substr(0, 800)
	return clean


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
