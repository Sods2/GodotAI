@tool
class_name DebugHandler
extends RefCounted

var _debugger

func _init(debugger) -> void:
	_debugger = debugger

func set_breakpoint(_ei: EditorInterface, params: Dictionary) -> Dictionary:
	var file: String = params.get("file", "")
	var line: int = params.get("line", 0)
	if file.is_empty() or line <= 0:
		return { "error": "file and line required" }
	_debugger.set_breakpoint_in_session(file, line, true)
	var has_session: bool = _debugger.has_active_session()
	var result := { "success": true, "file": file, "line": line, "applied": has_session }
	if not has_session:
		result["note"] = "Breakpoint stored; will apply when debug session starts (run the scene first)"
	return result

func remove_breakpoint(_ei: EditorInterface, params: Dictionary) -> Dictionary:
	var file: String = params.get("file", "")
	var line: int = params.get("line", 0)
	if file.is_empty() or line <= 0:
		return { "error": "file and line required" }
	_debugger.set_breakpoint_in_session(file, line, false)
	return { "success": true }

func list_breakpoints(_ei: EditorInterface, _params: Dictionary) -> Dictionary:
	return { "breakpoints": _debugger._breakpoints }

func get_stack_trace(_ei: EditorInterface, _params: Dictionary) -> Dictionary:
	if not _debugger.is_paused():
		return { "error": "not paused at breakpoint" }
	return { "frames": _debugger.get_stack_frames() }

func get_locals(_ei: EditorInterface, _params: Dictionary) -> Dictionary:
	if not _debugger.is_paused():
		return { "error": "not paused at breakpoint" }
	return { "locals": _debugger.get_locals() }

func step_over(_ei: EditorInterface, _params: Dictionary) -> Dictionary:
	if not _debugger.is_paused():
		return { "error": "not paused at breakpoint" }
	_debugger.send_debugger_command("next", [])
	return { "success": true }

func step_into(_ei: EditorInterface, _params: Dictionary) -> Dictionary:
	if not _debugger.is_paused():
		return { "error": "not paused at breakpoint" }
	_debugger.send_debugger_command("step", [])
	return { "success": true }

func step_out(_ei: EditorInterface, _params: Dictionary) -> Dictionary:
	if not _debugger.is_paused():
		return { "error": "not paused at breakpoint" }
	_debugger.send_debugger_command("finish", [])
	return { "success": true }

func continue_execution(_ei: EditorInterface, _params: Dictionary) -> Dictionary:
	if not _debugger.is_paused():
		return { "error": "not paused at breakpoint" }
	_debugger.send_debugger_command("continue", [])
	return { "success": true }
