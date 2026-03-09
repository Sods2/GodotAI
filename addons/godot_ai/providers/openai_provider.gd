@tool
class_name OpenAIProvider
extends ProviderBase

## OpenAI / ChatGPT API provider.
## Endpoint: https://api.openai.com/v1/chat/completions
##
## Reasoning models (o1, o3-mini) use a non-streaming path because they do not
## support stream:true, temperature, or a system role message.

const API_HOST := "api.openai.com"
const API_PATH := "/v1/chat/completions"

var _is_non_streaming := false
var _raw_response := ""

func _init() -> void:
	super()
	model = "gpt-4o"
	_sse_client.set_provider("openai")

func get_provider_name() -> String:
	return "OpenAI (ChatGPT)"

func get_available_models() -> Array[String]:
	return [
		"gpt-4o",
		"gpt-4o-mini",
		"gpt-4-turbo",
		"gpt-4",
		"gpt-3.5-turbo",
		"o1",
		"o1-mini",
		"o3-mini",
	]

func _get_models_path() -> String:
	return "/v1/models"

func _parse_models_response(json: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var data = json.get("data", [])
	if data is Array:
		for item in data:
			if item is Dictionary and item.has("id") and _is_chat_model(str(item["id"])):
				result.append(str(item["id"]))
	result.sort()
	return result

## Filter the models list to chat-capable models only, excluding image
## generation (dall-e), embeddings, TTS, and whisper models.
func _is_chat_model(id: String) -> bool:
	return id.begins_with("gpt-") or id.begins_with("o1") or id.begins_with("o3") \
		or id.begins_with("o4") or id.begins_with("chatgpt-")

func get_api_host() -> String:
	return API_HOST

func get_api_path() -> String:
	return API_PATH

## Detect reasoning models (o1/o3) before delegating — they don't support
## streaming, so the base-class flow collects raw chunks instead of SSE events.
func send_message(messages: Array, system_prompt: String = "") -> void:
	_is_non_streaming = _is_reasoning_model()
	_raw_response = ""
	super(messages, system_prompt)

## Build the request body. Reasoning models omit temperature (unsupported),
## use max_completion_tokens instead of max_tokens, and disable streaming.
func _build_request_body(messages: Array, system_prompt: String) -> Dictionary:
	if _is_non_streaming:
		# Reasoning models: no stream, no temperature, no system role, different token param.
		return {
			"model": model,
			"max_completion_tokens": max_tokens,
			"messages": messages,
		}

	var full_messages := []
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
	return PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + api_key,
	])

# ── Reasoning-model non-streaming overrides ──────────────────────────────────

## For non-streaming reasoning models, accumulate raw response bytes here
## instead of feeding them to SSEClient — the full parse happens in _on_http_done().
func _on_chunk(text: String) -> void:
	if _is_non_streaming:
		_raw_response += text
	else:
		super._on_chunk(text)

## For non-streaming responses, parse the accumulated JSON body and extract
## choices[0].message.content, then emit it as a single completed response.
func _on_http_done() -> void:
	if not _is_non_streaming:
		super._on_http_done()
		return
	# Parse the accumulated response body as a standard chat completion object.
	var json := JSON.new()
	if json.parse(_raw_response) == OK:
		var data = json.get_data()
		if data is Dictionary:
			var choices = data.get("choices", [])
			if choices.size() > 0:
				var content = choices[0].get("message", {}).get("content", "")
				if not content.is_empty():
					_stream_completed = true
					response_completed.emit(content)
					return
	response_error.emit("Failed to parse reasoning model response")

## OpenAI's reasoning models follow the "o1"/"o3" naming convention.
func _is_reasoning_model() -> bool:
	return model.begins_with("o1") or model.begins_with("o3")
