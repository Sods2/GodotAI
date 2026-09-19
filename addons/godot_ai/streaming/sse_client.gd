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

# Streaming tool calls, keyed by content-block / choice index.
# Each entry: {id: String, name: String, args_str: String}. The arguments JSON
# arrives incrementally (Anthropic input_json_delta / OpenAI function.arguments),
# so it's accumulated as a string and parsed in get_tool_calls().
var _tool_calls_by_index := {}

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
	_tool_calls_by_index = {}

## Return the tool calls accumulated during the stream, as
## [{id: String, name: String, input: Dictionary}]. Empty if the model requested none.
func get_tool_calls() -> Array:
	var indices := _tool_calls_by_index.keys()
	indices.sort()
	var result: Array = []
	for i in indices:
		var tc: Dictionary = _tool_calls_by_index[i]
		var input := {}
		var args_str: String = tc.get("args_str", "")
		if args_str.strip_edges() != "":
			var json := JSON.new()
			if json.parse(args_str) == OK and json.get_data() is Dictionary:
				input = json.get_data()
		result.append({"id": tc.get("id", ""), "name": tc.get("name", ""), "input": input})
	return result

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
	# content_block_start -> content_block.type == "tool_use" begins a tool call
	# content_block_delta -> delta.type == "text_delta" -> delta.text
	#                     -> delta.type == "input_json_delta" -> tool argument fragment
	# message_stop -> stream is finished (Anthropic does NOT send [DONE])
	var event_type = obj.get("type", "")
	if event_type == "content_block_start":
		var block = obj.get("content_block", {})
		if block.get("type", "") == "tool_use":
			_tool_calls_by_index[int(obj.get("index", 0))] = {
				"id": str(block.get("id", "")),
				"name": str(block.get("name", "")),
				"args_str": "",
			}
	elif event_type == "content_block_delta":
		var delta = obj.get("delta", {})
		var delta_type = delta.get("type", "")
		if delta_type == "text_delta":
			return delta.get("text", "")
		elif delta_type == "input_json_delta":
			var idx := int(obj.get("index", 0))
			if _tool_calls_by_index.has(idx):
				_tool_calls_by_index[idx]["args_str"] += str(delta.get("partial_json", ""))
	elif event_type == "message_stop":
		if not _completed:
			_completed = true
			stream_completed.emit(_full_text)
	return ""

## Extract text from an OpenAI/OpenRouter SSE event.
## Token lives at choices[0].delta.content; may be null/missing on the
## first chunk (role-only) and last chunk, so the null check is required.
func _extract_openai_token(obj: Dictionary) -> String:
	# OpenAI/OpenRouter: choices[0].delta.content for text,
	# choices[0].delta.tool_calls[] for incremental function calls.
	var choices = obj.get("choices", [])
	if choices.size() == 0:
		return ""
	var delta = choices[0].get("delta", {})

	var tool_calls = delta.get("tool_calls", null)
	if tool_calls is Array:
		for tc in tool_calls:
			var idx := int(tc.get("index", 0))
			if not _tool_calls_by_index.has(idx):
				_tool_calls_by_index[idx] = {"id": "", "name": "", "args_str": ""}
			if tc.has("id") and str(tc["id"]) != "":
				_tool_calls_by_index[idx]["id"] = str(tc["id"])
			var fn = tc.get("function", {})
			if fn.has("name") and str(fn["name"]) != "":
				_tool_calls_by_index[idx]["name"] = str(fn["name"])
			if fn.has("arguments"):
				_tool_calls_by_index[idx]["args_str"] += str(fn["arguments"])

	var content = delta.get("content", null)
	if content != null:
		return str(content)
	return ""
