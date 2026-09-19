@tool
extends Node

const _ProtocolScript = preload("res://addons/godot_mcp_bridge/protocol.gd")
const _SceneHandlerScript = preload("res://addons/godot_mcp_bridge/handlers/scene_handler.gd")
const _InspectorHandlerScript = preload("res://addons/godot_mcp_bridge/handlers/inspector_handler.gd")
const _ScriptHandlerScript = preload("res://addons/godot_mcp_bridge/handlers/script_handler.gd")
const _RunHandlerScript = preload("res://addons/godot_mcp_bridge/handlers/run_handler.gd")
const _ScreenshotHandlerScript = preload("res://addons/godot_mcp_bridge/handlers/screenshot_handler.gd")
const _SignalHandlerScript = preload("res://addons/godot_mcp_bridge/handlers/signal_handler.gd")
const _AnimationHandlerScript = preload("res://addons/godot_mcp_bridge/handlers/animation_handler.gd")
const _DebugHandlerScript = preload("res://addons/godot_mcp_bridge/handlers/debug_handler.gd")
const _ProfilerHandlerScript = preload("res://addons/godot_mcp_bridge/handlers/profiler_handler.gd")

var editor_interface: EditorInterface
var _tcp_server: TCPServer
var _client: StreamPeerTCP = null
var _protocol = null
var _last_message_time: float = 0.0
const _CLIENT_TIMEOUT_SEC: float = 30.0

# Handlers (populated in _ready)
var _scene_handler
var _inspector_handler
var _script_handler
var _run_handler
var _screenshot_handler
var _signal_handler
var _animation_handler
var _debug_handler
var _profiler_handler
var _debugger_ref = null

# Deferred responses: Array of {id, type, frames_waited, extra}
# Used for data that arrives asynchronously from _capture() callbacks
var _deferred_requests: Array = []
const _DEFERRED_MAX_FRAMES: int = 60  # ~1s at 60fps before giving up (allows round-trip for get_stack_dump)

func _ready() -> void:
	_ensure_handlers()

# Instantiate the per-request handlers. Called from both _ready() and start():
# on a freshly imported project the node can begin listening before _ready()
# has run, which would leave every handler null and fail every request with
# "Nonexistent function ... in base 'Nil'". Idempotent, so the second call is a
# no-op.
func _ensure_handlers() -> void:
	if _scene_handler != null:
		return
	_protocol = _ProtocolScript.new()
	_scene_handler = _SceneHandlerScript.new()
	_inspector_handler = _InspectorHandlerScript.new()
	_script_handler = _ScriptHandlerScript.new()
	_run_handler = _RunHandlerScript.new()
	_screenshot_handler = _ScreenshotHandlerScript.new()
	_signal_handler = _SignalHandlerScript.new()
	_animation_handler = _AnimationHandlerScript.new()

func set_debugger(debugger) -> void:
	_debug_handler = _DebugHandlerScript.new(debugger)
	_debugger_ref = debugger

func set_profiler_handler(debugger) -> void:
	_profiler_handler = _ProfilerHandlerScript.new(debugger)

func start(port: int = 6008) -> void:
	_ensure_handlers()
	_tcp_server = TCPServer.new()
	var err := _tcp_server.listen(port, "127.0.0.1")
	if err != OK:
		push_error("[Claude Bridge] Failed to listen on port %d: %s" % [port, error_string(err)])

func stop() -> void:
	if _client:
		_client.disconnect_from_host()
		_client = null
	if _tcp_server:
		_tcp_server.stop()
		_tcp_server = null

func _process_deferred() -> void:
	if _deferred_requests.is_empty() or _client == null:
		return
	var completed: Array = []
	for i in range(_deferred_requests.size()):
		var req: Dictionary = _deferred_requests[i]
		req.frames_waited += 1
		var result = _check_deferred(req)
		if result != null:
			_send(_client, _protocol.encode_response(req.id, result))
			completed.append(i)
	# Remove completed in reverse order to preserve indices
	for i in range(completed.size() - 1, -1, -1):
		_deferred_requests.remove_at(completed[i])

func _check_deferred(req: Dictionary) -> Variant:
	var t: String = req.type
	var waited: int = req.frames_waited
	if t == "stack_trace":
		var frames: Array = _debugger_ref.get_stack_frames() if _debugger_ref != null else []
		if not frames.is_empty() or waited >= _DEFERRED_MAX_FRAMES:
			return {"frames": frames}
	elif t == "locals":
		var locals: Array = _debugger_ref.get_locals() if _debugger_ref != null else []
		if not locals.is_empty() or waited >= _DEFERRED_MAX_FRAMES:
			return {"locals": locals}
	elif t == "game_screenshot":
		if _debugger_ref != null and _debugger_ref.has_game_screenshot():
			return _debugger_ref.consume_game_screenshot()
		if waited >= _DEFERRED_MAX_FRAMES:
			return {"error": "The running game did not return a screenshot. The game-side capture autoload may be missing — disable and re-enable the Claude Bridge plugin to reinstall it."}
	elif t == "output":
		# Wait a minimum number of frames for output to accumulate, then return
		if waited >= 5:
			var since_line: int = req.get("since_line", 0)
			var all_lines: Array = _debugger_ref.get_output_lines() if _debugger_ref != null else []
			var output: Array = all_lines.slice(since_line) if since_line > 0 and since_line < all_lines.size() else all_lines
			return {"output": output, "total_lines": all_lines.size()}
	elif t == "profiler_data":
		var data: Array = _debugger_ref.get_profiler_data() if _debugger_ref != null else []
		if not data.is_empty() or waited >= _DEFERRED_MAX_FRAMES:
			return {"frames": data}
	return null

func _process(_delta: float) -> void:
	if _tcp_server == null:
		return

	# Process any deferred responses first
	_process_deferred()

	# Accept new connection, replacing stale client if needed
	if _tcp_server.is_connection_available():
		if _client != null:
			var idle_time := Time.get_ticks_msec() / 1000.0 - _last_message_time
			if idle_time > _CLIENT_TIMEOUT_SEC:
				print("[Claude Bridge] Dropping stale client (idle %.1fs)" % idle_time)
				_client.disconnect_from_host()
				_client = null
		if _client == null:
			_client = _tcp_server.take_connection()
			_protocol = _ProtocolScript.new()  # Fresh parser for new connection
			_last_message_time = Time.get_ticks_msec() / 1000.0
			print("[Claude Bridge] Client connected")

	if _client == null:
		return

	# Poll to update connection status (required in Godot 4)
	_client.poll()

	# Check client still connected
	if _client.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		print("[Claude Bridge] Client disconnected")
		_client = null
		return

	# Read available data
	var available := _client.get_available_bytes()
	if available > 0:
		var data := _client.get_data(available)
		if data[0] == OK:
			_last_message_time = Time.get_ticks_msec() / 1000.0
			var messages: Array = _protocol.feed(data[1])
			for msg in messages:
				_handle_message(msg)

func _handle_message(msg: Dictionary) -> void:
	# Guarantee handlers exist before dispatch. Godot can reload @tool scripts
	# after a fresh project finishes importing, which resets instance state to
	# null while the socket stays open — without this every call would fail with
	# "Nonexistent function ... in base 'Nil'". Idempotent, so it is a cheap
	# null-check once handlers are set.
	_ensure_handlers()

	var id = msg.get("id", null)
	var method: String = msg.get("method", "")
	var params: Dictionary = msg.get("params", {})

	var result = null
	var error_msg = ""

	match method:
		"editor.status":
			result = _handle_editor_status()
		"scene.get_tree":
			result = _scene_handler.get_tree(editor_interface, params)
		"scene.get_selected":
			result = _scene_handler.get_selected(editor_interface)
		"scene.add_node":
			result = _scene_handler.add_node(editor_interface, params)
		"scene.remove_node":
			result = _scene_handler.remove_node(editor_interface, params)
		"scene.reparent_node":
			result = _scene_handler.reparent_node(editor_interface, params)
		"scene.open":
			result = _scene_handler.open_scene(editor_interface, params)
		"scene.save":
			result = _scene_handler.save_scene(editor_interface)
		"inspector.get_properties":
			result = _inspector_handler.get_properties(editor_interface, params)
		"inspector.set_property":
			result = _inspector_handler.set_property(editor_interface, params)
		"script.get_current":
			result = _script_handler.get_current(editor_interface)
		"script.get_open":
			result = _script_handler.get_open(editor_interface)
		"script.get_selected_code":
			result = _script_handler.get_selected_code(editor_interface)
		"script.insert_at_cursor":
			result = _script_handler.insert_at_cursor(editor_interface, params)
		"run.play":
			result = _run_handler.play(editor_interface, params)
		"run.stop":
			result = _run_handler.stop(editor_interface)
		"run.is_running":
			result = _run_handler.is_running(editor_interface)
		"run.get_output":
			if _debugger_ref != null:
				_deferred_requests.append({"id": id, "type": "output", "frames_waited": 0, "since_line": params.get("since_line", 0)})
				return  # Response will be sent by _process_deferred()
			else:
				result = _run_handler.get_output(params)
		"screenshot.viewport":
			result = _screenshot_handler.capture_viewport(editor_interface)
		"scene.rename_node":
			result = _scene_handler.rename_node(editor_interface, params)
		"scene.duplicate_node":
			result = _scene_handler.duplicate_node(editor_interface, params)
		"scene.move_node":
			result = _scene_handler.move_node(editor_interface, params)
		"signal.list":
			result = _signal_handler.list_signals(editor_interface, params)
		"signal.connect":
			result = _signal_handler.connect_signal(editor_interface, params)
		"signal.disconnect":
			result = _signal_handler.disconnect_signal(editor_interface, params)
		"signal.list_connections":
			result = _signal_handler.list_connections(editor_interface, params)
		"script.create_and_attach":
			result = _script_handler.create_and_attach(editor_interface, params)
		"script.detach":
			result = _script_handler.detach_script(editor_interface, params)
		"script.get_for_node":
			result = _script_handler.get_script_for_node(editor_interface, params)
		"animation.list":
			result = _animation_handler.list_animations(editor_interface, params)
		"animation.get":
			result = _animation_handler.get_animation(editor_interface, params)
		"animation.create":
			result = _animation_handler.create_animation(editor_interface, params)
		"screenshot.game":
			# The game captures itself and replies over the debugger, so the
			# answer arrives a few frames later; see game_capture.gd. A
			# debugger session outlives the game, so ask the editor whether a
			# game is actually running rather than trusting the session.
			if not editor_interface.is_playing_scene():
				result = _screenshot_handler.capture_game(editor_interface)
			elif _debugger_ref != null and _debugger_ref.request_game_screenshot():
				_deferred_requests.append({"id": id, "type": "game_screenshot", "frames_waited": 0})
				return
			else:
				result = _screenshot_handler.capture_game(editor_interface)
		"resource.import":
			result = _inspector_handler.import_asset(editor_interface, params)
		"resource.read":
			result = _inspector_handler.read_resource(editor_interface, params)
		"resource.write":
			result = _inspector_handler.write_resource(editor_interface, params)
		"debug.set_breakpoint":
			if _debug_handler != null:
				result = _debug_handler.set_breakpoint(editor_interface, params)
			else:
				error_msg = "Debug handler not initialized"
		"debug.remove_breakpoint":
			if _debug_handler != null:
				result = _debug_handler.remove_breakpoint(editor_interface, params)
			else:
				error_msg = "Debug handler not initialized"
		"debug.list_breakpoints":
			if _debug_handler != null:
				result = _debug_handler.list_breakpoints(editor_interface, params)
			else:
				error_msg = "Debug handler not initialized"
		"debug.get_stack_trace":
			if _debug_handler != null:
				if _debugger_ref != null and _debugger_ref.is_paused():
					_deferred_requests.append({"id": id, "type": "stack_trace", "frames_waited": 0})
					return  # Response will be sent by _process_deferred()
				else:
					result = _debug_handler.get_stack_trace(editor_interface, params)
			else:
				error_msg = "Debug handler not initialized"
		"debug.get_locals":
			if _debug_handler != null:
				if _debugger_ref != null and _debugger_ref.is_paused():
					_deferred_requests.append({"id": id, "type": "locals", "frames_waited": 0})
					return  # Response will be sent by _process_deferred()
				else:
					result = _debug_handler.get_locals(editor_interface, params)
			else:
				error_msg = "Debug handler not initialized"
		"debug.step_over":
			if _debug_handler != null:
				result = _debug_handler.step_over(editor_interface, params)
			else:
				error_msg = "Debug handler not initialized"
		"debug.step_into":
			if _debug_handler != null:
				result = _debug_handler.step_into(editor_interface, params)
			else:
				error_msg = "Debug handler not initialized"
		"debug.step_out":
			if _debug_handler != null:
				result = _debug_handler.step_out(editor_interface, params)
			else:
				error_msg = "Debug handler not initialized"
		"debug.continue_execution":
			if _debug_handler != null:
				result = _debug_handler.continue_execution(editor_interface, params)
			else:
				error_msg = "Debug handler not initialized"
		"profiler.start":
			if _profiler_handler != null:
				result = _profiler_handler.start_profiler(editor_interface, params)
			else:
				error_msg = "Profiler handler not initialized"
		"profiler.stop":
			if _profiler_handler != null:
				result = _profiler_handler.stop_profiler(editor_interface, params)
			else:
				error_msg = "Profiler handler not initialized"
		"profiler.get_data":
			if _profiler_handler != null:
				if _debugger_ref != null and _debugger_ref.is_profiler_active():
					_deferred_requests.append({"id": id, "type": "profiler_data", "frames_waited": 0})
					return  # Response will be sent by _process_deferred()
				else:
					result = _profiler_handler.get_profiler_data(editor_interface, params)
			else:
				error_msg = "Profiler handler not initialized"
		_:
			error_msg = "Unknown method: " + method

	if error_msg != "":
		_send(_client, _protocol.encode_error(id, -32601, error_msg))
	else:
		_send(_client, _protocol.encode_response(id, result))

func _handle_editor_status() -> Dictionary:
	# Godot 4.7 reports a single empty path when no scene is open; skip those
	# so callers can treat an empty list as "nothing open".
	var open_scenes: Array[String] = []
	for scene_path in EditorInterface.get_open_scenes():
		if scene_path != "":
			open_scenes.append(scene_path)
	return {
		"connected": true,
		"open_scenes": open_scenes,
		"is_playing": EditorInterface.is_playing_scene(),
		"project_path": ProjectSettings.globalize_path("res://")
	}

func _send(peer: StreamPeerTCP, data: PackedByteArray) -> void:
	if peer and peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		peer.put_data(data)
