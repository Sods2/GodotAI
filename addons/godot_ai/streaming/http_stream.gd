@tool
class_name HTTPStream
extends Node

## HTTPClient wrapper for chunked/streaming HTTP responses.
## Poll _process() to receive chunks as they arrive.
##
## Usage:
##   var stream = HTTPStream.new()
##   add_child(stream)
##   stream.chunk_received.connect(_on_chunk)
##   stream.request_completed.connect(_on_done)
##   stream.request_failed.connect(_on_error)
##   stream.request_cancelled.connect(_on_cancelled)
##   stream.send_request("api.anthropic.com", "/v1/messages", headers, body)

signal chunk_received(text: String)
signal request_completed()
signal request_failed(error: String)
signal request_cancelled()

enum State { IDLE, CONNECTING, REQUESTING, READING, DONE, ERROR }

const CONNECTION_TIMEOUT := 10.0  ## seconds to wait for TCP connection + TLS
const READ_TIMEOUT := 30.0        ## seconds of idle (no data) before giving up

var _client := HTTPClient.new()
var _state := State.IDLE
var _host := ""
var _port := 443
var _use_ssl := true
var _path := ""
var _headers: PackedStringArray = []
var _body := ""
var _response_body := PackedByteArray()
var _response_code := 0
var _error_reading := false
var _elapsed := 0.0

## Start a streaming HTTP POST request using HTTPClient in incremental mode.
## Uses low-level HTTPClient (not HTTPRequest) so the response body can be
## read chunk-by-chunk via _process() as it arrives, rather than waiting for
## the full response — essential for streaming LLM responses.
func send_request(host: String, path: String, headers: PackedStringArray, body: String) -> void:
	if _state != State.IDLE and _state != State.DONE and _state != State.ERROR:
		push_warning("HTTPStream: request already in progress")
		return

	_host = host
	_path = path
	_headers = headers
	_body = body
	_response_body.clear()
	_response_code = 0
	_error_reading = false
	_elapsed = 0.0
	_state = State.CONNECTING

	_client = HTTPClient.new()
	_use_ssl = true
	_port = 443

	var err := _client.connect_to_host(_host, _port, TLSOptions.client())
	if err != OK:
		_state = State.ERROR
		request_failed.emit("Failed to connect: %s" % error_string(err))

## Cancel the in-progress request and close the underlying TCP connection.
## Uses close() rather than just disconnecting signals because HTTPClient
## holds an open socket that must be torn down to free the resource.
func cancel() -> void:
	if _state == State.IDLE or _state == State.DONE or _state == State.ERROR:
		return
	_client.close()
	_state = State.IDLE
	request_cancelled.emit()

func _process(delta: float) -> void:
	# State machine: CONNECTING -> REQUESTING -> READING -> DONE / ERROR
	if _state == State.IDLE or _state == State.DONE or _state == State.ERROR:
		return

	_elapsed += delta
	_client.poll()
	var status := _client.get_status()

	match _state:
		State.CONNECTING:
			if _elapsed > CONNECTION_TIMEOUT:
				_state = State.ERROR
				_client.close()
				request_failed.emit("Connection timed out")
				return
			match status:
				HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING:
					pass  # still connecting
				HTTPClient.STATUS_CONNECTED:
					_elapsed = 0.0
					_state = State.REQUESTING
					var err := _client.request(HTTPClient.METHOD_POST, _path, _headers, _body)
					if err != OK:
						_state = State.ERROR
						_client.close()
						request_failed.emit("Failed to send request: %s" % error_string(err))
				_:
					_state = State.ERROR
					_client.close()
					request_failed.emit("Connection failed (status %d)" % status)

		State.REQUESTING:
			match status:
				HTTPClient.STATUS_REQUESTING:
					pass  # waiting for response headers
				HTTPClient.STATUS_BODY, HTTPClient.STATUS_CONNECTED:
					_response_code = _client.get_response_code()
					if _response_code >= 400:
						_error_reading = true
					_elapsed = 0.0
					_state = State.READING
				_:
					_state = State.ERROR
					_client.close()
					request_failed.emit("Request failed (status %d)" % status)

		State.READING:
			if _elapsed > READ_TIMEOUT:
				_state = State.ERROR
				_client.close()
				request_failed.emit("Read timed out")
				return
			match status:
				HTTPClient.STATUS_BODY:
					if _client.has_response():
						var chunk := _client.read_response_body_chunk()
						if chunk.size() > 0:
							# Reset timer on each chunk — we want a per-chunk idle
							# timeout, not a cap on total request duration.
							_elapsed = 0.0
							# Accumulate error body so the full message is available
							# before emitting, rather than streaming partial errors.
							if _error_reading:
								_response_body.append_array(chunk)
							else:
								chunk_received.emit(chunk.get_string_from_utf8())
				HTTPClient.STATUS_CONNECTED, HTTPClient.STATUS_DISCONNECTED:
					_state = State.DONE
					_client.close()
					if _error_reading:
						var body := _response_body.get_string_from_utf8()
						request_failed.emit("HTTP %d: %s" % [_response_code, body])
					else:
						request_completed.emit()
				_:
					_state = State.ERROR
					_client.close()
					request_failed.emit("Stream read error (status %d)" % status)
