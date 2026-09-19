@tool
class_name BridgeProtocol
extends RefCounted

# Encode a JSON-RPC response with Content-Length framing
static func encode_response(id: Variant, result: Variant) -> PackedByteArray:
	var msg := {"jsonrpc": "2.0", "id": id, "result": result}
	var json_str := JSON.stringify(msg)
	var body_bytes := json_str.to_utf8_buffer()
	var header := "Content-Length: %d\r\n\r\n" % body_bytes.size()
	var out := PackedByteArray()
	out.append_array(header.to_ascii_buffer())
	out.append_array(body_bytes)
	return out

static func encode_error(id: Variant, code: int, message: String) -> PackedByteArray:
	var msg := {"jsonrpc": "2.0", "id": id, "error": {"code": code, "message": message}}
	var json_str := JSON.stringify(msg)
	var body_bytes := json_str.to_utf8_buffer()
	var header := "Content-Length: %d\r\n\r\n" % body_bytes.size()
	var out := PackedByteArray()
	out.append_array(header.to_ascii_buffer())
	out.append_array(body_bytes)
	return out

# Feed raw bytes, returns array of parsed JSON-RPC request dicts
# Maintains internal buffer for partial reads
var _buffer: PackedByteArray = PackedByteArray()

func feed(data: PackedByteArray) -> Array[Dictionary]:
	_buffer.append_array(data)
	var messages: Array[Dictionary] = []

	while true:
		var buf_str := _buffer.get_string_from_utf8()
		var header_end := buf_str.find("\r\n\r\n")
		if header_end == -1:
			break

		var header := buf_str.substr(0, header_end)
		var content_length := -1
		for line in header.split("\r\n"):
			if line.begins_with("Content-Length: "):
				content_length = int(line.substr(16))
				break

		if content_length == -1:
			# Malformed, skip past header
			_buffer = _buffer.slice(header_end + 4)
			continue

		var msg_start := header_end + 4
		var total_needed := msg_start + content_length
		if _buffer.size() < total_needed:
			break  # Incomplete body, wait for more data

		var body := _buffer.slice(msg_start, total_needed).get_string_from_utf8()
		_buffer = _buffer.slice(total_needed)

		var json := JSON.new()
		if json.parse(body) == OK:
			messages.append(json.get_data())

	return messages
