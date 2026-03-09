@tool
class_name AnthropicProvider
extends ProviderBase

## Claude API provider (Anthropic).
## Endpoint: https://api.anthropic.com/v1/messages

const API_HOST := "api.anthropic.com"
const API_PATH := "/v1/messages"
const ANTHROPIC_VERSION := "2023-06-01"

## Tell SSEClient to use Anthropic's event format (content_block_delta)
## instead of OpenAI's choices[0].delta.content structure.
func _init() -> void:
	super()
	model = "claude-opus-4-6"
	_sse_client.set_provider("anthropic")

func get_provider_name() -> String:
	return "Anthropic (Claude)"

func get_available_models() -> Array[String]:
	return [
		"claude-opus-4-6",
		"claude-sonnet-4-6",
		"claude-haiku-4-5-20251001",
		"claude-opus-4-5",
		"claude-sonnet-4-5",
	]

func _get_models_path() -> String:
	return "/v1/models?limit=1000"

func _parse_models_response(json: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var data = json.get("data", [])
	if data is Array:
		for item in data:
			if item is Dictionary and item.has("id"):
				result.append(str(item["id"]))
	result.sort()
	return result

func get_api_host() -> String:
	return API_HOST

func get_api_path() -> String:
	return API_PATH

## Anthropic places the system prompt as a top-level "system" key rather than
## a {"role":"system"} entry in the messages array (which it does not support).
func _build_request_body(messages: Array, system_prompt: String) -> Dictionary:
	var body := {
		"model": model,
		"max_tokens": max_tokens,
		"temperature": temperature,
		"stream": true,
		"messages": messages,
	}
	if not system_prompt.is_empty():
		body["system"] = system_prompt
	return body

## Anthropic uses x-api-key (not "Authorization: Bearer") and requires an
## anthropic-version header to pin the API contract.
func _build_headers() -> PackedStringArray:
	return PackedStringArray([
		"Content-Type: application/json",
		"x-api-key: " + api_key,
		"anthropic-version: " + ANTHROPIC_VERSION,
	])
