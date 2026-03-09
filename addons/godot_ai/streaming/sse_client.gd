@tool
class_name SSEClient
extends RefCounted

## Server-Sent Events (SSE) parser.
## Feed raw HTTP chunks via push_chunk(); emits token_received for each content delta.
##
## Usage:
##   var sse = SSEClient.new()
##   sse.token_received.connect(_on_token)
##   sse.stream_completed.connect(_on_done)
##   # For each http chunk:
##   sse.push_chunk(raw_text)

signal token_received(text: String)
signal stream_completed(full_text: String)
signal stream_error(message: String)

var _buffer := ""
var _full_text := ""
var _provider := ""  # "anthropic" | "openai" | "openrouter"
var _completed := false

## Select the token extraction branch for incoming SSE events.
## "anthropic" triggers content_block_delta parsing; anything else
## uses OpenAI-style choices[0].delta.content parsing.
func set_provider(provider_name: String) -> void:
	_provider = provider_name

## Clear buffer and completion state so this client can be reused
## for a new request without creating a fresh instance.
func reset() -> void:
	_buffer = ""
	_full_text = ""
	_completed = false

## Process any remaining incomplete line in the buffer (call at stream end).
## Handles the case where the final SSE event arrives without a trailing newline.
func flush() -> void:
	if not _buffer.is_empty() and _buffer.begins_with("data:"):
		var data := _buffer.substr(5).strip_edges()
		_buffer = ""
		_handle_data_line(data)
	else:
		_buffer = ""

## Feed a raw text chunk from the HTTP stream.
func push_chunk(raw: String) -> void:
	_buffer += raw
	_process_buffer()

## Process complete lines from the buffer using SSE line-based parsing.
## The SSE protocol delivers events as line groups separated by blank lines;
## this splits on newlines and handles each complete "data:" line.
func _process_buffer() -> void:
	# SSE lines are separated by \n; events separated by \n\n
	while "\n" in _buffer:
		var newline_pos := _buffer.find("\n")
		var line := _buffer.left(newline_pos).strip_edges()
		_buffer = _buffer.substr(newline_pos + 1)

		if line.begins_with("data:"):
			var data := line.substr(5).strip_edges()
			_handle_data_line(data)

## Handle a single SSE data payload: strips the "data: " prefix (already done
## by caller), checks for the "[DONE]" sentinel that signals stream end,
## then delegates to the provider-specific token extractor.
func _handle_data_line(data: String) -> void:
	if data == "[DONE]":
		if not _completed:
			_completed = true
			stream_completed.emit(_full_text)
		return

	if data.is_empty():
		return

	var json := JSON.new()
	var err := json.parse(data)
	if err != OK:
		return

	var obj = json.get_data()
	if not obj is Dictionary:
		return

	# Detect API-level error embedded in the stream (e.g. rate limit, invalid key).
	if obj.has("error"):
		var api_err = obj.get("error")
		var msg: String
		if api_err is Dictionary:
			msg = str(api_err.get("message", "Unknown API error"))
		else:
			msg = str(api_err)
		stream_error.emit(msg)
		return

	var token := ""
	match _provider:
		"anthropic":
			token = _extract_anthropic_token(obj)
		"openai", "openrouter":
			token = _extract_openai_token(obj)

	if not token.is_empty():
		_full_text += token
		token_received.emit(token)

## Extract text from an Anthropic SSE event.
## Only content_block_delta events with delta.type=="text_delta" carry text;
## other event types (message_start, content_block_start, ping) are ignored.
func _extract_anthropic_token(obj: Dictionary) -> String:
	# Anthropic streaming event types:
	# content_block_delta -> delta.type == "text_delta" -> delta.text
	# message_stop -> stream is finished (Anthropic does NOT send [DONE])
	var event_type = obj.get("type", "")
	if event_type == "content_block_delta":
		var delta = obj.get("delta", {})
		if delta.get("type", "") == "text_delta":
			return delta.get("text", "")
	elif event_type == "message_stop":
		if not _completed:
			_completed = true
			stream_completed.emit(_full_text)
	return ""

## Extract text from an OpenAI/OpenRouter SSE event.
## Token lives at choices[0].delta.content; may be null/missing on the
## first chunk (role-only) and last chunk, so the null check is required.
func _extract_openai_token(obj: Dictionary) -> String:
	# OpenAI/OpenRouter: choices[0].delta.content
	var choices = obj.get("choices", [])
	if choices.size() > 0:
		var delta = choices[0].get("delta", {})
		var content = delta.get("content", null)
		if content != null:
			return str(content)
	return ""
