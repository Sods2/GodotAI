@tool
class_name ProviderBase
extends RefCounted

## Abstract base class for all LLM providers.
## Subclasses must implement get_api_host(), get_api_path(),
## _build_request_body(), _build_headers(), get_provider_name(),
## and get_available_models().
##
## The full streaming plumbing (HTTPStream, SSEClient, signal handlers) lives
## here so provider subclasses only contain API-specific logic.

signal response_token(text: String)
signal response_completed(full_text: String)
signal response_error(error: String)
signal models_fetched(models: Array[String])
signal models_fetch_failed(error: String)

var api_key: String = ""
var model: String = ""
var temperature: float = 0.7
var max_tokens: int = 4096

var _parent_node: Node = null
var _http_stream: HTTPStream = null
var _sse_client := SSEClient.new()
var _stream_completed := false

var _cached_models: Array[String] = []
var _custom_models: Array[String] = []
var _is_fetching_models: bool = false
var _models_http_request: HTTPRequest = null

func _init() -> void:
	_sse_client.token_received.connect(_on_token)
	_sse_client.stream_completed.connect(_on_stream_completed)
	_sse_client.stream_error.connect(_on_stream_error)

# ── Public API ──────────────────────────────────────────────────────────────

## Set the scene-tree node that HTTPStream child nodes will be parented to.
## Must be called before send_message().
func set_parent_node(node: Node) -> void:
	_parent_node = node

## Send a chat message with optional system prompt.
## messages: Array of {role: String, content: String} dicts.
func send_message(messages: Array, system_prompt: String = "") -> void:
	if not is_configured():
		response_error.emit("%s API key not set. Open Settings to add your key." % get_provider_name())
		return

	_sse_client.reset()
	_stream_completed = false

	var body := _build_request_body(messages, system_prompt)
	var body_json := JSON.stringify(body)
	var headers := _build_headers()

	_setup_stream()
	_http_stream.send_request(get_api_host(), get_api_path(), headers, body_json)

## Cancel an in-progress request.
func cancel() -> void:
	if _http_stream and is_instance_valid(_http_stream):
		_http_stream.cancel()

## Return true if a streaming request is currently in-flight.
func is_busy() -> bool:
	if not _http_stream or not is_instance_valid(_http_stream):
		return false
	var s := _http_stream._state
	return s != HTTPStream.State.IDLE and s != HTTPStream.State.DONE and s != HTTPStream.State.ERROR

## Return true if this provider has a valid API key set.
func is_configured() -> bool:
	return not api_key.is_empty()

## Return true if models have been fetched and cached.
func has_cached_models() -> bool:
	return not _cached_models.is_empty()

## Return true if a model fetch request is in-flight.
func is_fetching_models() -> bool:
	return _is_fetching_models

## Fetch available models from the API.
## Emits models_fetched with cached data immediately if available.
## Falls back to get_available_models() if not configured or path not implemented.
func fetch_models() -> void:
	if _is_fetching_models:
		return
	if not _cached_models.is_empty():
		models_fetched.emit(_cached_models)
		return
	var path := _get_models_path()
	if path.is_empty() or not is_configured() or not _parent_node:
		models_fetched.emit(get_available_models())
		return
	_is_fetching_models = true
	_models_http_request = HTTPRequest.new()
	_parent_node.add_child(_models_http_request)
	_models_http_request.request_completed.connect(_on_models_response)
	var url := "https://" + get_api_host() + path
	_models_http_request.request(url, _build_headers(), HTTPClient.METHOD_GET)

## Clear the cached model list so the next fetch_models() hits the API.
func clear_model_cache() -> void:
	_cached_models.clear()

## Set the list of user-defined custom models for this provider.
func set_custom_models(models: Array) -> void:
	_custom_models.clear()
	for m in models:
		_custom_models.append(str(m))

## Return all known models: hardcoded + API-fetched cache + user custom (deduped).
func get_all_models() -> Array[String]:
	var seen: Dictionary = {}
	var result: Array[String] = []
	var base := _cached_models if not _cached_models.is_empty() else get_available_models()
	for m in base:
		if not seen.has(m):
			seen[m] = true
			result.append(m)
	for m in _custom_models:
		if not seen.has(m):
			seen[m] = true
			result.append(m)
	return result

# ── Abstract overrides ───────────────────────────────────────────────────────

## Return the API hostname (no scheme, no trailing slash).
func get_api_host() -> String:
	push_error("ProviderBase.get_api_host() not implemented")
	return ""

## Return the API path (e.g. "/v1/messages").
func get_api_path() -> String:
	push_error("ProviderBase.get_api_path() not implemented")
	return ""

## Build the JSON-serialisable request body dict for this provider.
func _build_request_body(_messages: Array, _system_prompt: String) -> Dictionary:
	push_error("ProviderBase._build_request_body() not implemented")
	return {}

## Build the HTTP request headers for this provider.
func _build_headers() -> PackedStringArray:
	push_error("ProviderBase._build_headers() not implemented")
	return PackedStringArray()

## Return list of available model IDs for this provider.
func get_available_models() -> Array[String]:
	return []

## Return the human-readable display name for this provider.
func get_provider_name() -> String:
	return "Unknown"

## Return the API path for listing models (e.g. "/v1/models").
## Return "" to disable dynamic fetching for this provider.
func _get_models_path() -> String:
	return ""

## Parse the JSON response from the models API into a list of model IDs.
## Return [] to fall back to get_available_models().
func _parse_models_response(_json: Dictionary) -> Array[String]:
	return []

# ── Internal streaming plumbing ──────────────────────────────────────────────

func _setup_stream() -> void:
	if _http_stream and is_instance_valid(_http_stream):
		_http_stream.chunk_received.disconnect(_on_chunk)
		_http_stream.request_completed.disconnect(_on_http_done)
		_http_stream.request_failed.disconnect(_on_http_error)
		_http_stream.request_cancelled.disconnect(_on_http_cancelled)
		_http_stream.queue_free()

	_http_stream = HTTPStream.new()
	if _parent_node:
		_parent_node.add_child(_http_stream)
	_http_stream.chunk_received.connect(_on_chunk)
	_http_stream.request_completed.connect(_on_http_done)
	_http_stream.request_failed.connect(_on_http_error)
	_http_stream.request_cancelled.connect(_on_http_cancelled)

func _on_chunk(text: String) -> void:
	_sse_client.push_chunk(text)

func _on_token(text: String) -> void:
	response_token.emit(text)

func _on_stream_completed(full_text: String) -> void:
	_stream_completed = true
	response_completed.emit(full_text)

func _on_http_done() -> void:
	# Process any final incomplete SSE line that arrived without a trailing newline.
	_sse_client.flush()
	if _stream_completed:
		return
	# HTTP closed without an explicit stream-end event — emit partial text or error.
	var partial := _sse_client._full_text
	if not partial.is_empty():
		response_completed.emit(partial)
	else:
		response_error.emit("Connection closed unexpectedly")

func _on_http_cancelled() -> void:
	_stream_completed = true  # prevent _on_http_done from firing after cancel

func _on_stream_error(message: String) -> void:
	response_error.emit(message)

func _on_http_error(error: String) -> void:
	response_error.emit("Network error: " + error)

func _on_models_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_is_fetching_models = false
	if _models_http_request and is_instance_valid(_models_http_request):
		_models_http_request.queue_free()
		_models_http_request = null

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		models_fetch_failed.emit("HTTP error %d" % response_code)
		models_fetched.emit(get_available_models())
		return

	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		models_fetch_failed.emit("Invalid JSON response")
		models_fetched.emit(get_available_models())
		return

	var data = json.get_data()
	if not data is Dictionary:
		models_fetch_failed.emit("Unexpected response format")
		models_fetched.emit(get_available_models())
		return

	var parsed := _parse_models_response(data)
	if parsed.is_empty():
		parsed = get_available_models()
	_cached_models = parsed
	models_fetched.emit(_cached_models)
