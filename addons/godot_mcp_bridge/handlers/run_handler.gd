@tool
class_name RunHandler
extends RefCounted

var _output_lines: Array[String] = []

func play(editor_interface: EditorInterface, params: Dictionary) -> Dictionary:
	var scene_path: String = params.get("scene", "")
	_output_lines.clear()
	if scene_path != "":
		if not FileAccess.file_exists(scene_path):
			return {"error": "Scene file not found: " + scene_path}
		if not (scene_path.ends_with(".tscn") or scene_path.ends_with(".scn")):
			return {"error": "Not a scene file: " + scene_path}
		if not scene_path.begins_with("res://"):
			return {"error": "Scene path must use res:// format, got: " + scene_path}
		editor_interface.get_resource_filesystem().scan()
		editor_interface.play_custom_scene(scene_path)
	else:
		if editor_interface.get_edited_scene_root() == null:
			return {"error": "No scene is currently open — open a scene or specify a scene path"}
		editor_interface.play_current_scene()
	return {"success": true, "note": "Scene launch requested. Use godot_is_running to verify it started."}

func stop(editor_interface: EditorInterface) -> Dictionary:
	editor_interface.stop_playing_scene()
	return {"success": true, "output": _output_lines}

func is_running(editor_interface: EditorInterface) -> Dictionary:
	return {"running": editor_interface.is_playing_scene()}

func get_output(params: Dictionary = {}) -> Dictionary:
	var since_line: int = params.get("since_line", 0)
	var all_output: Array = _output_lines.duplicate()
	if since_line > 0 and since_line < all_output.size():
		all_output = all_output.slice(since_line)
	return {"output": all_output, "total_lines": _output_lines.size()}
