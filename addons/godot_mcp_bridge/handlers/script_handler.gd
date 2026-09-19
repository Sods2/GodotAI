@tool
class_name ScriptHandler
extends RefCounted

func get_current(editor_interface: EditorInterface) -> Dictionary:
	var script_editor := editor_interface.get_script_editor()
	if script_editor == null:
		return {"error": "Script editor not available"}

	var current_script := script_editor.get_current_script()
	if current_script == null:
		return {"script": null}

	var result := {
		"path": current_script.resource_path,
		"source": current_script.source_code,
		"cursor_line": 0,
		"cursor_column": 0
	}

	var base_editor := script_editor.get_current_editor()
	if base_editor:
		var code_edit := _find_code_edit(base_editor)
		if code_edit:
			result["cursor_line"] = code_edit.get_caret_line() + 1
			result["cursor_column"] = code_edit.get_caret_column() + 1

	return result

func get_open(editor_interface: EditorInterface) -> Dictionary:
	var script_editor := editor_interface.get_script_editor()
	if script_editor == null:
		return {"scripts": []}

	var scripts: Array[String] = []
	for script in script_editor.get_open_scripts():
		scripts.append(script.resource_path)

	return {"scripts": scripts}

func get_selected_code(editor_interface: EditorInterface) -> Dictionary:
	var script_editor := editor_interface.get_script_editor()
	if script_editor == null:
		return {"text": ""}

	var base_editor := script_editor.get_current_editor()
	if not base_editor:
		return {"text": ""}

	var code_edit := _find_code_edit(base_editor)
	if code_edit and code_edit.has_selection():
		return {"text": code_edit.get_selected_text()}

	return {"text": ""}

func insert_at_cursor(editor_interface: EditorInterface, params: Dictionary) -> Dictionary:
	var text: String = params.get("text", "")
	var script_editor := editor_interface.get_script_editor()
	if script_editor == null:
		return {"error": "Script editor not available"}

	var base_editor := script_editor.get_current_editor()
	if not base_editor:
		return {"error": "No editor open"}

	var code_edit := _find_code_edit(base_editor)
	if code_edit:
		code_edit.insert_text_at_caret(text)
		return {"success": true}

	return {"error": "Could not find code editor"}

# Recursively find CodeEdit widget (Godot doesn't expose it directly)
func _find_code_edit(node: Node) -> CodeEdit:
	if node is CodeEdit:
		return node as CodeEdit
	for child in node.get_children():
		var found := _find_code_edit(child)
		if found:
			return found
	return null

func create_and_attach(editor_interface: EditorInterface, params: Dictionary) -> Dictionary:
	var root = editor_interface.get_edited_scene_root()
	if not root:
		return {"error": "No scene open"}
	var node_path: String = params.get("node_path", "")
	var node: Node = root.get_node_or_null(node_path)
	if not node:
		return {"error": "Node not found: " + node_path}
	var script_path: String = params.get("script_path", "")
	if script_path.is_empty():
		return {"error": "script_path is required"}
	var template: String = params.get("template", "")
	if template.is_empty():
		template = "extends " + node.get_class() + "\n\n"
	var file = FileAccess.open(ProjectSettings.globalize_path(script_path), FileAccess.WRITE)
	if not file:
		return {"error": "Could not create file: " + script_path}
	file.store_string(template)
	file = null
	var script = load(script_path)
	if not script:
		return {"error": "Could not load script: " + script_path}
	var old_script = node.get_script()
	var undo_redo = editor_interface.get_editor_undo_redo()
	undo_redo.create_action("Create and Attach Script")
	undo_redo.add_do_property(node, "script", script)
	undo_redo.add_undo_property(node, "script", old_script)
	undo_redo.commit_action()
	return {"success": true, "script_path": script_path}

func detach_script(editor_interface: EditorInterface, params: Dictionary) -> Dictionary:
	var root = editor_interface.get_edited_scene_root()
	if not root:
		return {"error": "No scene open"}
	var node_path: String = params.get("node_path", "")
	var node: Node = root.get_node_or_null(node_path)
	if not node:
		return {"error": "Node not found: " + node_path}
	var old_script = node.get_script()
	if old_script == null:
		return {"error": "Node has no script attached"}
	var undo_redo = editor_interface.get_editor_undo_redo()
	undo_redo.create_action("Detach Script")
	undo_redo.add_do_property(node, "script", null)
	undo_redo.add_undo_property(node, "script", old_script)
	undo_redo.commit_action()
	return {"success": true}

func get_script_for_node(editor_interface: EditorInterface, params: Dictionary) -> Dictionary:
	var root = editor_interface.get_edited_scene_root()
	if not root:
		return {"error": "No scene open"}
	var node_path: String = params.get("path", "")
	var node: Node = root.get_node_or_null(node_path)
	if not node:
		return {"error": "Node not found: " + node_path}
	var script = node.get_script()
	if script == null:
		return {"script": null}
	return {"script_path": script.resource_path, "class_name": script.get_global_name()}
