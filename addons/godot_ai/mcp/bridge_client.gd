@tool
class_name GodotBridgeClient
extends JsonRpcTcpClient

## Client for the godot-mcp editor bridge (the `godot_mcp_bridge` addon), which runs
## a JSON-RPC TCP server on 127.0.0.1:6008 exposing live editor operations
## (add node, set property, run scene, …). GodotAI connects here to let the AI act
## on the editor via tool calls.
##
## The bridge accepts one client at a time and drops idle clients after ~30s;
## connect_and_wait() transparently reconnects on the next call. Because call_method()
## tracks a single in-flight request id, callers must await each call before starting
## the next (the agent loop runs tools sequentially, which satisfies this).

const DEFAULT_PORT := 6008

var _next_id: int = 1
var _waiting_id: int = -1
var _last_response: Dictionary = {}

func _init() -> void:
	configure("127.0.0.1", DEFAULT_PORT)

## Quick availability probe for the settings UI. Returns true if the bridge accepts
## a connection within the timeout.
func probe(timeout_sec: float = 0.6) -> bool:
	return await connect_and_wait(timeout_sec)

## Call a bridge JSON-RPC method and await its response.
## Returns {"result": <value>} on success or {"error": <message/dict>} on failure.
func call_method(method: String, params: Dictionary, timeout_sec: float = 15.0) -> Dictionary:
	if not await connect_and_wait(1.0):
		return {"error": "MCP bridge not reachable on %s:%d (is the godot_mcp_bridge addon enabled?)" % [host, port]}

	var id := _next_id
	_next_id += 1
	_waiting_id = id
	_last_response = {}

	if not send_message({"jsonrpc": "2.0", "id": id, "method": method, "params": params}):
		_waiting_id = -1
		close()  # Force a fresh socket on the next call.
		return {"error": "Failed to send request to MCP bridge"}

	var elapsed := 0.0
	while _waiting_id == id and elapsed < timeout_sec:
		await get_tree().create_timer(0.05).timeout
		elapsed += 0.05

	if _waiting_id == id:
		# Timed out — the socket may be stale (e.g. dropped for idleness). Reset it.
		_waiting_id = -1
		close()
		return {"error": "MCP bridge timed out after %.0fs" % timeout_sec}

	return _last_response

func _on_message(msg: Dictionary) -> void:
	var id = msg.get("id", null)
	if id == null or int(id) != _waiting_id:
		return
	if msg.has("error"):
		_last_response = {"error": msg["error"]}
	else:
		_last_response = {"result": msg.get("result", null)}
	_waiting_id = -1
