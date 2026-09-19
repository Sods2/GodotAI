@tool
class_name ProfilerHandler
extends RefCounted

var _debugger

func _init(debugger) -> void:
	_debugger = debugger

func start_profiler(_ei: EditorInterface, _params: Dictionary) -> Dictionary:
	_debugger.start_profiler()
	return { "success": true }

func stop_profiler(_ei: EditorInterface, _params: Dictionary) -> Dictionary:
	var data: Array = _debugger.stop_profiler()
	return { "success": true, "frames": data }

func get_profiler_data(_ei: EditorInterface, _params: Dictionary) -> Dictionary:
	var data: Array = _debugger.get_profiler_data()
	return { "frames": data }
