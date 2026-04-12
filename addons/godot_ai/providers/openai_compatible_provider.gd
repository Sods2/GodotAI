@tool
class_name OpenAICompatibleProvider
extends ProviderBase

## OpenAI-compatible provider for local AI servers (Ollama, LM Studio, llama.cpp, vLLM).
## All of these expose the same OpenAI chat completions wire format, so one class
## handles all of them — the only difference is the base URL.
##
## Default endpoint: http://localhost:11434/v1 (Ollama)
## No API key required for Ollama; optional for proxies that need one.

const DEFAULT_ENDPOINT := "http://localhost:11434/v1"

## Full base URL including scheme, host, port, and path prefix (e.g. "/v1").
## Call set_endpoint_url() to update — it re-parses all components.
var endpoint_url: String = DEFAULT_ENDPOINT

var _parsed_host := "localhost"
var _parsed_port := 11434
var _parsed_use_ssl := false
var _parsed_base_path := "/v1"

func _init() -> void:
	super()
	model = "llama3.2"
	_sse_client.set_provider("openai")  # OpenAI wire format
	_parse_endpoint()

func get_provider_name() -> String:
	return "Local (Ollama / LM Studio)"

## Update the endpoint URL and re-parse its components.
func set_endpoint_url(url: String) -> void:
	endpoint_url = url
	_parse_endpoint()

## Parse endpoint_url into host, port, ssl flag, and base path components.
## Handles both http:// and https:// schemes, with or without explicit port numbers.
func _parse_endpoint() -> void:
	var url := endpoint_url.strip_edges()
	if url.is_empty():
		return

	_parsed_use_ssl = url.begins_with("https://")
	url = url.trim_prefix("https://").trim_prefix("http://")

	# Split into host[:port] and /base_path
	var slash_pos := url.find("/")
	var host_port := url.left(slash_pos) if slash_pos != -1 else url
	_parsed_base_path = url.substr(slash_pos) if slash_pos != -1 else ""

	# Split host from optional port
	var colon_pos := host_port.find(":")
	if colon_pos != -1:
		_parsed_host = host_port.left(colon_pos)
		_parsed_port = int(host_port.substr(colon_pos + 1))
	else:
		_parsed_host = host_port
		_parsed_port = 443 if _parsed_use_ssl else 80

func get_api_host() -> String:
	return _parsed_host

func get_api_path() -> String:
	return _parsed_base_path + "/chat/completions"

func get_api_port() -> int:
	return _parsed_port

func get_api_use_ssl() -> bool:
	return _parsed_use_ssl

## Local providers require a valid endpoint URL, not an API key.
## Ollama needs no key; api_key is only used when a proxy requires one.
func is_configured() -> bool:
	return not endpoint_url.is_empty()

## No hardcoded fallback — only show models actually fetched from the local server.
func get_available_models() -> Array[String]:
	return []

## Path for listing installed models. Appended to base path so it resolves correctly
## regardless of the configured endpoint prefix (e.g. /v1/models).
func _get_models_path() -> String:
	return _parsed_base_path + "/models"

## Parse the models list response. Handles both OpenAI-compat format
## ({"data": [{id: "..."}]}) and Ollama native format ({"models": [{model: "..."}]}).
func _parse_models_response(json: Dictionary) -> Array[String]:
	var result: Array[String] = []

	# OpenAI-compat: {"data": [{id: "model-name"}, ...]}
	var data = json.get("data", [])
	if data is Array and not data.is_empty():
		for item in data:
			if item is Dictionary and item.has("id"):
				result.append(str(item["id"]))

	# Ollama native: {"models": [{model: "name:tag"}, ...]}
	if result.is_empty():
		var models = json.get("models", [])
		if models is Array:
			for item in models:
				if item is Dictionary:
					var id: String = str(item.get("model", item.get("name", "")))
					if not id.is_empty():
						result.append(id)

	result.sort()
	return result

func _build_request_body(messages: Array, system_prompt: String) -> Dictionary:
	var full_messages: Array = []
	if not system_prompt.is_empty():
		full_messages.append({"role": "system", "content": system_prompt})
	full_messages.append_array(messages)
	return {
		"model": model,
		"max_tokens": max_tokens,
		"temperature": temperature,
		"stream": true,
		"messages": full_messages,
	}

func _build_headers() -> PackedStringArray:
	var headers := PackedStringArray(["Content-Type: application/json"])
	# API key is optional — only add if the user configured one (e.g. for a proxy).
	if not api_key.is_empty():
		headers.append("Authorization: Bearer " + api_key)
	return headers
