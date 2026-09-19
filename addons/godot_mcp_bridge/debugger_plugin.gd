@tool
extends EditorDebuggerPlugin

var _breakpoints: Array = []  # Array of {file, line}
var _stack_frames: Array = []  # Array of {file, line, function, id}
var _locals: Array = []        # Array of {name, value}
var _is_paused: bool = false
var _active_session: EditorDebuggerSession = null
var _profiler_data: Array = []  # Collected profiler frames
var _profiler_active: bool = false
var _output_lines: Array[String] = []  # Game print() output
var _editor_interface: EditorInterface = null
var _capture_logged: bool = false
var _output_panel_start: int = 0  # Text length at session start
var _game_screenshot: Dictionary = {}   # Latest reply from the game's capture autoload
var _game_screenshot_pending: bool = false

func set_editor_interface(ei: EditorInterface) -> void:
	_editor_interface = ei

func _setup_session(session_id: int) -> void:
	var session := get_session(session_id)
	if session == null:
		return
	_active_session = session
	session.started.connect(_on_session_started.bind(session_id))
	session.stopped.connect(_on_session_stopped.bind(session_id))
	session.breaked.connect(_on_session_breaked)
	session.continued.connect(_on_session_continued)

func _has_capture(capture: String) -> bool:
	var c := capture
	if c == "output" or c == "stack_dump" or c == "stack_frame_vars" \
		or c == "debug" or c == "claude_bridge" or c == "servers" or c == "scripts":
		return true
	return false

func _on_session_started(session_id: int) -> void:
	var session := get_session(session_id)
	if session == null:
		return
	_active_session = session
	_is_paused = false
	_stack_frames = []
	_locals = []
	_output_lines.clear()
	_capture_logged = false
	# Record current output panel length so we only return new output
	_output_panel_start = _get_output_panel_text().length()
	# Apply any pre-set breakpoints to the new session
	for bp in _breakpoints:
		session.set_breakpoint(bp.file, bp.line, true)

func _on_session_stopped(session_id: int) -> void:
	_is_paused = false
	_stack_frames = []
	_locals = []
	_active_session = null

func _on_session_breaked(can_debug: bool) -> void:
	_is_paused = true
	_stack_frames = []
	_locals = []

func _on_session_continued() -> void:
	_is_paused = false
	_stack_frames = []
	_locals = []

func _capture(message: String, data: Array, session_id: int) -> bool:
	var msg := message
	if not _capture_logged:
		_capture_logged = true
		print("[Claude Bridge] Capture active (first message: %s)" % msg)
	# Diagnostics: log relevant capture messages with data type info
	if msg == "stack_dump" or msg == "stack_frame_vars" or msg == "output" \
		or msg.begins_with("servers:") or msg.begins_with("scripts:"):
		var type_info := ""
		for i in range(min(data.size(), 3)):
			type_info += type_string(typeof(data[i])) + " "
		print("[Claude Bridge] _capture: msg=%s data_size=%d types=[%s]" % [msg, data.size(), type_info.strip_edges()])

	# Native debugger: stack dump sent automatically when breaking or in response to get_stack_dump
	if msg == "stack_dump":
		_stack_frames = []
		if data.size() > 0 and data[0] is Dictionary:
			# Custom/legacy format: array of dicts
			for frame in data:
				if frame is Dictionary:
					_stack_frames.append(frame)
		else:
			# Godot native flat format: [file, line, func, file, line, func, ...]
			var i := 0
			while i + 2 < data.size():
				_stack_frames.append({
					"file": str(data[i]),
					"line": int(data[i + 1]),
					"function": str(data[i + 2]),
					"id": i / 3
				})
				i += 3
		# Auto-request locals for the top frame
		if _active_session != null and not _stack_frames.is_empty():
			_active_session.send_message("get_stack_frame_vars", [0])
		return false  # Let built-in debugger handle it too

	# Native debugger: locals response for a stack frame
	# Godot 4 format: [locals_count, name0, val0, ..., members_count, name0, val0, ..., globals_count, name0, val0, ...]
	if msg == "stack_frame_vars":
		_locals = []
		var idx: int = 0
		while idx < data.size():
			var section_count: int = int(data[idx])
			idx += 1
			for i in range(section_count):
				if idx + 1 < data.size():
					_locals.append({
						"name": str(data[idx]),
						"value": str(data[idx + 1])
					})
				idx += 2
		return false

	# Game print() output
	# Godot 4 format: [PackedStringArray(messages), PackedInt32Array(types)]
	if msg == "output":
		if data.size() >= 1:
			var messages = data[0]
			if messages is PackedStringArray:
				for text in messages:
					var line: String = str(text).strip_edges()
					if line != "":
						_output_lines.append(line)
			elif messages is Array:
				for text in messages:
					var line: String = str(text).strip_edges()
					if line != "":
						_output_lines.append(line)
			else:
				# Unexpected format: stringify everything
				for item in data:
					var line: String = str(item).strip_edges()
					if line != "":
						_output_lines.append(line)
		return false

	# Legacy custom messages (kept for backwards compatibility)
	if msg == "claude_bridge:stack_dump":
		_stack_frames = []
		for frame in data:
			if frame is Dictionary:
				_stack_frames.append(frame)
		return true
	# Screenshot captured inside the running game by game_capture.gd.
	if msg == "claude_bridge:screenshot":
		_game_screenshot = data[0] if data.size() > 0 and data[0] is Dictionary else {"error": "Malformed screenshot payload from the game"}
		_game_screenshot_pending = false
		return true
	if msg == "claude_bridge:locals":
		_locals = []
		for local in data:
			if local is Dictionary:
				_locals.append(local)
		return true

	# Profiler frame data from built-in profilers (servers + scripts)
	if msg == "servers:profile_frame" or msg == "scripts:profile_frame":
		var frame_info := {}
		frame_info["profiler"] = "servers" if msg.begins_with("servers:") else "scripts"
		if data.size() >= 2:
			var names = data[0]
			var values = data[1]
			var entries: Array = []
			if names is PackedStringArray:
				for j in range(names.size()):
					entries.append({
						"name": names[j],
						"value": float(values[j]) if j < values.size() else 0.0
					})
			frame_info["entries"] = entries
		else:
			frame_info["raw_size"] = data.size()
		_profiler_data.append(frame_info)
		return true

	return false

func get_stack_frames() -> Array:
	if not _stack_frames.is_empty():
		return _stack_frames
	# Fallback: read from the editor's debugger UI
	var frames = _read_stack_from_editor_ui()
	if frames.is_empty() or frames[0].get("line", 0) == 0:
		return []  # Not ready yet — let deferred polling retry
	return frames

func get_locals() -> Array:
	if not _locals.is_empty():
		return _locals
	# Fallback: read from the editor's debugger UI
	return _read_locals_from_editor_ui()

func is_paused() -> bool:
	return _is_paused

func get_output_lines() -> Array:
	# If _capture received output lines, use those
	if not _output_lines.is_empty():
		return _output_lines.duplicate()
	# Fallback: read from the editor's Output panel (EditorLog)
	var full_text := _get_output_panel_text()
	if full_text.length() > _output_panel_start:
		var new_text := full_text.substr(_output_panel_start)
		var lines: Array = []
		for line in new_text.split("\n"):
			var trimmed := line.strip_edges()
			if trimmed != "":
				lines.append(trimmed)
		return lines
	return []

func set_breakpoint_in_session(file: String, line: int, enabled: bool) -> void:
	# Track breakpoints locally
	if enabled:
		var already := false
		for bp in _breakpoints:
			if bp.file == file and bp.line == line:
				already = true
				break
		if not already:
			_breakpoints.append({"file": file, "line": line})
	else:
		for i in range(_breakpoints.size() - 1, -1, -1):
			if _breakpoints[i].file == file and _breakpoints[i].line == line:
				_breakpoints.remove_at(i)

	if _active_session != null:
		_active_session.set_breakpoint(file, line, enabled)

	# Set visual breakpoint in the editor gutter
	_set_visual_breakpoint(file, line, enabled)

func _set_visual_breakpoint(file: String, line: int, enabled: bool) -> void:
	if _editor_interface == null:
		return
	var script_editor = _editor_interface.get_script_editor()
	if script_editor == null:
		return
	# Open the script so it can receive the visual breakpoint
	var script = load(file)
	if script == null:
		return
	# edit_script() makes the script the current tab, so get_current_editor() returns it
	_editor_interface.edit_script(script, line)
	var current_editor = script_editor.get_current_editor()
	if current_editor == null:
		return
	var base = current_editor.get_base_editor()
	if base is CodeEdit:
		(base as CodeEdit).set_line_as_breakpoint(line - 1, enabled)  # CodeEdit uses 0-indexed lines

func has_active_session() -> bool:
	return _active_session != null

func send_debugger_command(command: String, args: Array = []) -> void:
	if _active_session != null:
		_active_session.send_message(command, args)

func is_profiler_active() -> bool:
	return _profiler_active

func start_profiler() -> void:
	_profiler_data = []
	_profiler_active = true
	if _active_session != null:
		_active_session.toggle_profiler("servers", true, [])
		_active_session.toggle_profiler("scripts", true, [])

func stop_profiler() -> Array:
	_profiler_active = false
	if _active_session != null:
		_active_session.toggle_profiler("servers", false, [])
		_active_session.toggle_profiler("scripts", false, [])
	return _profiler_data.duplicate()

func get_profiler_data() -> Array:
	if not _profiler_data.is_empty():
		return _profiler_data.duplicate()
	# Fallback: basic performance metrics available without game-side capture
	return [_get_performance_snapshot()]

func _get_performance_snapshot() -> Dictionary:
	return {
		"profiler": "performance",
		"entries": [
			{"name": "fps", "value": Performance.get_monitor(Performance.TIME_FPS)},
			{"name": "process_time_ms", "value": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0},
			{"name": "physics_process_time_ms", "value": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0},
			{"name": "static_memory_mb", "value": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0},
			{"name": "object_count", "value": Performance.get_monitor(Performance.OBJECT_COUNT)},
			{"name": "nodes_count", "value": Performance.get_monitor(Performance.OBJECT_NODE_COUNT)},
			{"name": "render_draw_calls", "value": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)},
		]
	}

# --- Editor UI reading (fallback for built-in messages that bypass _capture) ---

func _get_editor_base() -> Control:
	if _editor_interface != null:
		return _editor_interface.get_base_control()
	return EditorInterface.get_base_control()

func _get_output_panel_text() -> String:
	var base := _get_editor_base()
	if base == null:
		return ""
	# Strategy 1: parent class is "EditorLog" (Godot 4.x prior to 4.5)
	var rtl := _find_node_of_class(base, "RichTextLabel", "EditorLog")
	if rtl != null:
		return rtl.get_parsed_text()
	# Strategies 2-4: traverse once and try progressively broader matches
	var all_children := _get_all_children(base)
	# Strategy 2: parent node NAME contains "log" or "output" (case-insensitive)
	for child in all_children:
		if child is RichTextLabel and child.get_parent() != null:
			var parent_name: String = child.get_parent().name
			if parent_name.containsn("log") or parent_name.containsn("output"):
				return child.get_parsed_text()
	# Strategy 3: find the tab labelled "Output" in any TabContainer
	for child in all_children:
		if child is TabContainer:
			for tab_idx in range(child.get_tab_count()):
				if child.get_tab_title(tab_idx).containsn("output"):
					var tab_control: Control = child.get_tab_control(tab_idx)
					if tab_control != null:
						for sub in _get_all_children(tab_control):
							if sub is RichTextLabel:
								return sub.get_parsed_text()
	# Strategy 4: largest RichTextLabel with any content (last resort)
	var best_rtl: RichTextLabel = null
	var best_len: int = 0
	for child in all_children:
		if child is RichTextLabel:
			var text: String = child.get_parsed_text()
			if text.length() > best_len:
				best_rtl = child
				best_len = text.length()
	if best_rtl != null:
		return best_rtl.get_parsed_text()
	return ""

func _get_script_editor_line() -> int:
	# When paused at a breakpoint, the script editor cursor is at the exact line
	var script_editor = _editor_interface.get_script_editor() if _editor_interface != null else null
	if script_editor == null:
		script_editor = EditorInterface.get_script_editor()
	if script_editor == null:
		return 0
	var editor = script_editor.get_current_editor()
	if editor == null:
		return 0
	var base = editor.get_base_editor()
	if base is CodeEdit:
		return (base as CodeEdit).get_caret_line() + 1  # CodeEdit is 0-indexed
	return 0

func _read_stack_from_editor_ui() -> Array:
	var base := _get_editor_base()
	if base == null:
		return []
	var debugger := _find_node_of_class(base, "ScriptEditorDebugger")
	if debugger == null:
		return []
	# Get current editor line — valid when paused at a breakpoint
	var editor_line := _get_script_editor_line()
	# Strategy 1: find first Tree in the "Stack Trace" tab (Godot 4.5+, 1-column format)
	var stack_tree := _find_stack_trace_tree(debugger)
	if stack_tree != null:
		var frames := _extract_stack_frames(stack_tree)
		if not frames.is_empty():
			# Patch any frame with line=0 using the script editor position (top frame)
			if editor_line > 0 and frames[0].get("line", 0) == 0:
				frames[0]["line"] = editor_line
			return frames
	# Strategy 2 (fallback): scan all Trees, check any column for a file path
	var frames := []
	for child in _get_all_children(debugger):
		if not (child is Tree):
			continue
		var root: TreeItem = child.get_root()
		if root == null:
			continue
		var first := root.get_first_child()
		if first == null:
			continue
		var cols: int = child.get_columns()
		var file_col: int = -1
		for c in range(cols):
			if _looks_like_file_path(first.get_text(c)):
				file_col = c
				break
		if file_col == -1:
			continue
		var item := first
		while item != null:
			var frame := {}
			if cols >= 3:
				frame["function"] = item.get_text(0)
				frame["file"] = item.get_text(1)
				frame["line"] = item.get_text(2).to_int()
			elif cols == 2:
				if file_col == 1:
					frame["function"] = item.get_text(0)
					frame["file"] = item.get_text(1)
				else:
					frame["file"] = item.get_text(0)
					frame["function"] = item.get_text(1)
			else:
				frame = _extract_single_column_frame(item)
			frame["id"] = frames.size()
			frames.append(frame)
			item = item.get_next()
		# Patch line=0 on top frame using script editor position
		if not frames.is_empty() and editor_line > 0 and frames[0].get("line", 0) == 0:
			frames[0]["line"] = editor_line
		if not frames.is_empty():
			return frames
	return frames

# Read stack variables from the debugger's EditorDebuggerInspector.
#
# Its edited object (EditorDebuggerRemoteObject/-Objects) exposes the current
# frame's variables as properties named "Locals/x", "Members/y" and
# "Globals/z". The debugger session's own stack_frame_vars message never
# reaches _capture() — Godot routes unprefixed core messages to the built-in
# debugger, not to EditorDebuggerPlugin captures — so this is the only path
# that works.
func _read_locals_from_debugger_inspector(debugger: Node) -> Array:
	for child in _get_all_children(debugger):
		if not child.get_class().containsn("debuggerinspector"):
			continue
		if not child.has_method("get_edited_object"):
			continue
		var obj = child.get_edited_object()
		if obj == null:
			continue
		var locals := []
		for prop in obj.get_property_list():
			var prop_name: String = str(prop.get("name", ""))
			var slash := prop_name.find("/")
			if slash <= 0:
				continue  # "script" and other object bookkeeping
			var scope := prop_name.substr(0, slash)
			if not (scope == "Locals" or scope == "Members" or scope == "Globals"):
				continue
			locals.append({
				"name": prop_name.substr(slash + 1),
				"value": str(obj.get(prop_name)),
				"scope": scope,
			})
		# Several inspectors exist (the expression evaluator has one too);
		# use the first that actually holds frame variables.
		if not locals.is_empty():
			return locals
	return []

func _read_locals_from_editor_ui() -> Array:
	var base := _get_editor_base()
	if base == null:
		return []
	var debugger := _find_node_of_class(base, "ScriptEditorDebugger")
	if debugger == null:
		return []
	# Strategy 1: the debugger's own inspector. Godot shows stack variables in
	# an EditorDebuggerInspector, not a Tree, so the Tree scan below never sees
	# them. Verified on 4.5.1, 4.6.3 and 4.7.2.
	var from_inspector := _read_locals_from_debugger_inspector(debugger)
	if not from_inspector.is_empty():
		return from_inspector
	# Strategy 2: scan all Trees in the debugger, skip stack trees and known non-locals trees
	var locals := []
	for child in _get_all_children(debugger):
		if not (child is Tree):
			continue
		var root: TreeItem = child.get_root()
		if root == null:
			continue
		var first := root.get_first_child()
		if first == null:
			continue
		var cols: int = child.get_columns()
		# Skip stack trees: any item text contains a res:// path
		var is_stack := false
		for c in range(cols):
			if _looks_like_stack_entry(first.get_text(c)):
				is_stack = true
				break
		if is_stack:
			continue
		# Skip trees with only one column (locals need name + value)
		if cols < 2:
			continue
		# Skip trees where the first item has no name, is a profiler header, or is a timestamp (Errors panel)
		var first_text: String = first.get_text(0).strip_edges()
		if first_text.is_empty() or first_text == "Time" or _looks_like_timestamp(first_text):
			continue
		var item := first
		while item != null:
			var name_text: String = item.get_text(0).strip_edges()
			var val_text: String = ""
			if cols >= 2:
				val_text = item.get_text(1).strip_edges()
			# Skip any item that looks like a stack entry (safety net)
			if name_text != "" and not _looks_like_stack_entry(name_text):
				locals.append({"name": name_text, "value": val_text})
			item = item.get_next()
		if not locals.is_empty():
			return locals
	return locals

func _find_node_of_class(root: Node, class_name_str: String, parent_class: String = "") -> Node:
	for child in _get_all_children(root):
		if child.get_class() == class_name_str or child.is_class(class_name_str):
			if parent_class == "":
				return child
			# Check ancestors up to 6 levels. Godot reorganizes the editor's
			# container hierarchy between releases (4.6 turned bottom panels into
			# docks and added an "hb" level; 4.7 reshuffled again), so leave
			# headroom above the 3 levels the deepest known layout needs.
			var ancestor: Node = child.get_parent()
			for _i in range(6):
				if ancestor == null:
					break
				if ancestor.get_class() == parent_class or ancestor.is_class(parent_class):
					return child
				ancestor = ancestor.get_parent()
	return null

func _get_all_children(node: Node) -> Array:
	var result: Array = []
	var stack: Array = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		for child in current.get_children():
			result.append(child)
			stack.append(child)
	return result

func _looks_like_file_path(text: String) -> bool:
	var t := text.strip_edges()
	return t.begins_with("res://") or t.ends_with(".gd") or t.ends_with(".cs") or t.ends_with(".tscn")

# Returns true if text looks like a stack entry (contains a res:// path in any format)
func _looks_like_stack_entry(text: String) -> bool:
	var t := text.strip_edges()
	# Covers "res://file.gd", "0 - res://file.gd:8 - at function: _ready", etc.
	return t.find("res://") != -1

# Returns true if text looks like a timestamp (e.g. "0:00:00:221" from the Errors panel)
func _looks_like_timestamp(text: String) -> bool:
	var t := text.strip_edges()
	var parts := t.split(":")
	if parts.size() < 3:
		return false
	for part in parts:
		if not part.is_valid_int():
			return false
	return true

# Find the first Tree node inside the "Stack Trace" tab of the debugger (the stack tree)
func _find_stack_trace_tree(debugger: Node) -> Tree:
	for child in _get_all_children(debugger):
		if child is TabContainer:
			for tab_idx in range(child.get_tab_count()):
				if child.get_tab_title(tab_idx).containsn("stack"):
					var tab_control: Control = child.get_tab_control(tab_idx)
					if tab_control == null:
						continue
					for sub in _get_all_children(tab_control):
						if sub is Tree:
							return sub
	return null

# Extract stack frames from a Tree, handling 1-col, 2-col, and 3-col formats
func _extract_stack_frames(tree: Tree) -> Array:
	var frames := []
	var root: TreeItem = tree.get_root()
	if root == null:
		return frames
	var cols: int = tree.get_columns()
	var item := root.get_first_child()
	while item != null:
		var frame := {}
		if cols >= 3:
			frame["function"] = item.get_text(0)
			frame["file"] = item.get_text(1)
			frame["line"] = item.get_text(2).to_int()
		elif cols == 2:
			if _looks_like_file_path(item.get_text(1)):
				frame["function"] = item.get_text(0)
				frame["file"] = item.get_text(1)
			else:
				frame["file"] = item.get_text(0)
				frame["function"] = item.get_text(1)
		else:
			frame = _extract_single_column_frame(item)
		frame["id"] = frames.size()
		frames.append(frame)
		item = item.get_next()
	return frames

# Parse a single-column stack entry.
# Handles Godot 4.5 format: "0 - res://node_2d.gd:8 - at function: _ready"
# and fallback format: "res://file.gd:line"
func _parse_single_column_stack_entry(text: String) -> Dictionary:
	var t := text.strip_edges()
	var frame := {"file": t, "function": "", "line": 0}
	# Godot 4.5: "N - res://file.gd:line - at function: func_name"
	var re := RegEx.new()
	re.compile(r"^\d+\s*-\s*(res://[^:]+):(\d+)\s*-\s*at function:\s*(.+)$")
	var m := re.search(t)
	if m != null:
		frame["file"] = m.get_string(1)
		frame["line"] = m.get_string(2).to_int()
		frame["function"] = m.get_string(3).strip_edges()
		return frame
	# Fallback: "res://file.gd:line"
	var colon_idx := t.rfind(":")
	if colon_idx > 0:
		var after_colon := t.substr(colon_idx + 1)
		if after_colon.is_valid_int():
			frame["file"] = t.substr(0, colon_idx)
			frame["line"] = after_colon.to_int()
	return frame

# Extract a stack frame from a single-column TreeItem.
# Tries metadata, then tooltip, then get_text() parsing — in that order.
func _extract_single_column_frame(item: TreeItem) -> Dictionary:
	# Strategy A: metadata — Godot's ScriptEditorDebugger stores frame info as a Dictionary
	var meta = item.get_metadata(0)
	if meta is Dictionary:
		if meta.has("file") and meta.has("line"):
			return {
				"file": str(meta["file"]),
				"line": int(meta["line"]),
				"function": str(meta.get("function", meta.get("func", "")))
			}
	# Strategy B: tooltip may contain the full formatted string
	var tooltip: String = item.get_tooltip_text(0)
	if tooltip != "" and tooltip.find("res://") != -1:
		var parsed := _parse_single_column_stack_entry(tooltip)
		if parsed.get("line", 0) != 0:
			return parsed
	# Strategy C: fall back to parsing get_text(0)
	return _parse_single_column_stack_entry(item.get_text(0))


# --- game screenshots -------------------------------------------------------
# The capture happens in the game process; see game_capture.gd for why.

# Returns false when there is no debugger session to ask.
func request_game_screenshot() -> bool:
	_game_screenshot = {}
	if _active_session == null:
		return false
	_game_screenshot_pending = true
	_active_session.send_message("claude_bridge:capture_request", [])
	return true

func has_game_screenshot() -> bool:
	return not _game_screenshot.is_empty()

# Hands over the pending reply and clears it, so a later request cannot be
# answered with a stale frame.
func consume_game_screenshot() -> Dictionary:
	var shot := _game_screenshot
	_game_screenshot = {}
	_game_screenshot_pending = false
	return shot
