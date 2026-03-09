@tool
class_name ContextBuilder
extends RefCounted

## Builds a system prompt from the current editor state.
## Gathers: current script text, cursor position, open scripts, scene tree.

## Build the full system prompt to send with each message.
## Pass include_hints=false on follow-up messages to avoid resending ~250 tokens of hints.
static func build_system_prompt(editor_interface: EditorInterface, include_hints: bool = true) -> String:
	var parts: PackedStringArray = []

	# Base GDScript hints — skip on follow-up turns to save tokens
	if include_hints:
		parts.append(GDScriptHints.get_system_hints())

	# Current script context
	var script_context := _get_current_script_context(editor_interface)
	if not script_context.is_empty():
		parts.append(script_context)

	# Scene context
	var scene_context := _get_scene_context(editor_interface)
	if not scene_context.is_empty():
		parts.append(scene_context)

	return "\n\n".join(parts)

## Collect the active script's full source, cursor position, and file path
## so the LLM has the exact editing context the user is looking at.
static func _get_current_script_context(editor_interface: EditorInterface) -> String:
	if editor_interface == null:
		return ""

	var script_editor := editor_interface.get_script_editor()
	if script_editor == null:
		return ""

	var current_script := script_editor.get_current_script()
	if current_script == null:
		return ""

	var script_path := current_script.resource_path
	var script_source := current_script.source_code

	var result := "## Currently Open Script\n"
	result += "File: `%s`\n\n" % script_path
	result += "```gdscript\n%s\n```" % script_source

	# Try to get cursor position from the active editor
	var base_editor := script_editor.get_current_editor()
	if base_editor:
		# The editor is a ScriptEditorBase; get the code edit within
		var code_edit := _find_code_edit(base_editor)
		if code_edit:
			var line := code_edit.get_caret_line()
			var col := code_edit.get_caret_column()
			result += "\n\nCursor position: line %d, column %d" % [line + 1, col + 1]

	return result

## Recursively search for the active CodeEdit widget.
## Godot's EditorInterface doesn't expose the CodeEdit directly; we must
## walk the ScriptEditor's widget subtree to locate it.
static func _find_code_edit(node: Node) -> CodeEdit:
	if node is CodeEdit:
		return node as CodeEdit
	for child in node.get_children():
		var found := _find_code_edit(child)
		if found:
			return found
	return null

## Build a text description of the currently edited scene tree.
## Limited to 3 levels deep to keep token usage predictable — unbounded
## recursion on complex scenes could produce enormous context strings.
static func _get_scene_context(editor_interface: EditorInterface) -> String:
	if editor_interface == null:
		return ""

	var edited_scene := editor_interface.get_edited_scene_root()
	if edited_scene == null:
		return ""

	var result := "## Current Scene\n"
	result += "Root node: `%s` (%s)\n\n" % [edited_scene.name, edited_scene.get_class()]
	result += "Scene tree (first 3 levels):\n"
	result += _describe_node(edited_scene, 0, 3)

	return result

static func _describe_node(node: Node, depth: int, max_depth: int) -> String:
	if depth >= max_depth:
		return ""
	var indent := "  ".repeat(depth)
	var result := "%s- %s (%s)\n" % [indent, node.name, node.get_class()]
	if depth < max_depth:
		for child in node.get_children():
			result += _describe_node(child, depth + 1, max_depth)
	return result

## Get the text currently selected in the script editor (for "send selected code").
static func get_selected_code(editor_interface: EditorInterface) -> String:
	if editor_interface == null:
		return ""

	var script_editor := editor_interface.get_script_editor()
	if script_editor == null:
		return ""

	var base_editor := script_editor.get_current_editor()
	if not base_editor:
		return ""

	var code_edit := _find_code_edit(base_editor)
	if code_edit and code_edit.has_selection():
		return code_edit.get_selected_text()

	return ""

## Insert text at the current cursor position in the script editor.
static func insert_at_cursor(editor_interface: EditorInterface, text: String) -> bool:
	if editor_interface == null:
		return false

	var script_editor := editor_interface.get_script_editor()
	if script_editor == null:
		return false

	var base_editor := script_editor.get_current_editor()
	if not base_editor:
		return false

	var code_edit := _find_code_edit(base_editor)
	if code_edit:
		code_edit.insert_text_at_caret(text)
		return true

	return false
