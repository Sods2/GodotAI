@tool
class_name OpenRouterProvider
extends ProviderBase

## OpenRouter API provider — OpenAI-compatible format with 500+ models.
## Endpoint: https://openrouter.ai/api/v1/chat/completions

const API_HOST := "openrouter.ai"
const API_PATH := "/api/v1/chat/completions"
const APP_TITLE := "GodotAI"
const APP_URL := "https://github.com/godotai/godot-ai"

func _init() -> void:
	super()
	model = "anthropic/claude-opus-4"
	_sse_client.set_provider("openrouter")

func get_provider_name() -> String:
	return "OpenRouter"

func get_available_models() -> Array[String]:
	return [
		"anthropic/claude-opus-4",
		"anthropic/claude-sonnet-4",
		"openai/gpt-4o",
		"openai/gpt-4o-mini",
		"google/gemini-2.0-flash-001",
		"google/gemini-pro-1.5",
		"meta-llama/llama-3.3-70b-instruct",
		"mistralai/mistral-large",
		"deepseek/deepseek-r1",
		"qwen/qwen-2.5-coder-32b-instruct",
	]

func get_api_host() -> String:
	return API_HOST

func get_api_path() -> String:
	return API_PATH

func _build_request_body(messages: Array, system_prompt: String) -> Dictionary:
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

## OpenRouter requires HTTP-Referer and X-Title headers for attribution and
## routing, on top of the standard Authorization: Bearer token.
func _build_headers() -> PackedStringArray:
	return PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + api_key,
		"HTTP-Referer: " + APP_URL,
		"X-Title: " + APP_TITLE,
	])
