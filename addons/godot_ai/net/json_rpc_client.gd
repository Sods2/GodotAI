@tool
class_name JsonRpcTcpClient
extends Node

## Base TCP client that speaks JSON-RPC 2.0 with LSP-style Content-Length framing
## (`Content-Length: N\r\n\r\n<json body>`). Both the Godot MCP bridge (port 6008)
## and Godot's built-in language server (port 6005) use this exact wire format, so
## the MCP and LSP clients share this transport.
##
## Subclasses override _on_message() to handle incoming messages. This node must be
## in the scene tree so _process() can pump the socket each frame.

var host: String = "127.0.0.1"
var port: int = 0

var _peer: StreamPeerTCP = null
var _recv_buffer: PackedByteArray = PackedByteArray()

## Set the target host and port before connecting.
func configure(target_host: String, target_port: int) -> void:
	host = target_host
	port = target_port

## True only when the socket is fully established.
func is_socket_connected() -> bool:
	if _peer == null:
		return false
	_peer.poll()
	return _peer.get_status() == StreamPeerTCP.STATUS_CONNECTED

## Attempt to connect, waiting up to timeout_sec for the handshake to complete.
## Returns true if connected. Safe to call repeatedly — reuses an existing
## connection and reconnects a dropped one.
func connect_and_wait(timeout_sec: float = 1.0) -> bool:
	if is_socket_connected():
		return true
	if _peer == null:
		_peer = StreamPeerTCP.new()
	var status := _peer.get_status()
	if status == StreamPeerTCP.STATUS_NONE or status == StreamPeerTCP.STATUS_ERROR:
		_recv_buffer = PackedByteArray()
		if _peer.connect_to_host(host, port) != OK:
			return false
	var elapsed := 0.0
	while elapsed < timeout_sec:
		_peer.poll()
		match _peer.get_status():
			StreamPeerTCP.STATUS_CONNECTED:
				return true
			StreamPeerTCP.STATUS_ERROR:
				return false
		await get_tree().create_timer(0.05).timeout
		elapsed += 0.05
	return is_socket_connected()

## Close the connection and clear the receive buffer. The next connect_and_wait()
## will establish a fresh socket.
func close() -> void:
	if _peer:
		_peer.disconnect_from_host()
		_peer = null
	_recv_buffer = PackedByteArray()

## Send a JSON-RPC message dict with Content-Length framing. Returns false if the
## socket isn't connected or the write fails.
func send_message(msg: Dictionary) -> bool:
	if not is_socket_connected():
		return false
	var body := JSON.stringify(msg).to_utf8_buffer()
	var header := ("Content-Length: %d\r\n\r\n" % body.size()).to_ascii_buffer()
	var out := PackedByteArray()
	out.append_array(header)
	out.append_array(body)
	return _peer.put_data(out) == OK

func _process(_delta: float) -> void:
	if _peer == null:
		return
	_peer.poll()
	if _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return
	var available := _peer.get_available_bytes()
	if available > 0:
		var data := _peer.get_data(available)
		if data[0] == OK:
			_recv_buffer.append_array(data[1])
			_drain_buffer()

## Parse as many complete Content-Length framed messages as the buffer holds,
## dispatching each to _on_message(). Mirrors the bridge's framing (protocol.gd).
func _drain_buffer() -> void:
	while true:
		var buf_str := _recv_buffer.get_string_from_utf8()
		var header_end := buf_str.find("\r\n\r\n")
		if header_end == -1:
			return

		var header := buf_str.substr(0, header_end)
		var content_length := -1
		for line in header.split("\r\n"):
			if line.begins_with("Content-Length:"):
				content_length = int(line.substr(len("Content-Length:")).strip_edges())
				break

		if content_length == -1:
			# Malformed header — skip past it to avoid getting stuck.
			_recv_buffer = _recv_buffer.slice(header_end + 4)
			continue

		var msg_start := header_end + 4
		var total_needed := msg_start + content_length
		if _recv_buffer.size() < total_needed:
			return  # Body not fully arrived yet.

		var body := _recv_buffer.slice(msg_start, total_needed).get_string_from_utf8()
		_recv_buffer = _recv_buffer.slice(total_needed)

		var json := JSON.new()
		if json.parse(body) == OK:
			var parsed = json.get_data()
			if parsed is Dictionary:
				_on_message(parsed)

## Override in subclasses to handle an incoming JSON-RPC message.
func _on_message(_msg: Dictionary) -> void:
	pass
