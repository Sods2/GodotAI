@tool
class_name ContextBuilder
extends RefCounted

## Builds a system prompt from the current editor state.
## Gathers: current script text, cursor position, open scripts, scene tree.

## Build the full system prompt to send with each message.
## Pass include_hints=false on follow-up messages to avoid resending ~250 tokens of hints.
static func build_system_prompt(include_hints: bool = true) -> String:
	var parts: PackedStringArray = []

	# Base GDScript hints — skip on follow-up turns to save tokens
	if include_hints:
		parts.append(GDScriptHints.get_system_hints())

	# Current script context
	var script_context := _get_current_script_context()
	if not script_context.is_empty():
		parts.append(script_context)

	# Scene context
	var scene_context := _get_scene_context()
	if not scene_context.is_empty():
		parts.append(scene_context)

	return "\n\n".join(parts)

## Collect the active script's full source, cursor position, and file path
## so the LLM has the exact editing context the user is looking at.
static func _get_current_script_context() -> String:
	if not Engine.is_editor_hint():
		return ""

	var script_editor := EditorInterface.get_script_editor()
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
static func _get_scene_context() -> String:
	if not Engine.is_editor_hint():
		return ""

	var edited_scene := EditorInterface.get_edited_scene_root()
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
static func get_selected_code() -> String:
	if not Engine.is_editor_hint():
		return ""

	var script_editor := EditorInterface.get_script_editor()
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
## Converts indentation to match the target file (tabs vs spaces) and
## inserts a blank line before the code when needed.
static func insert_at_cursor(text: String) -> bool:
	if not Engine.is_editor_hint():
		return false

	var script_editor := EditorInterface.get_script_editor()
	if script_editor == null:
		return false

	var base_editor := script_editor.get_current_editor()
	if not base_editor:
		return false

	var code_edit := _find_code_edit(base_editor)
	if code_edit == null:
		return false

	var adapted := _adapt_indentation(text, code_edit)
	adapted = _ensure_blank_line_before(adapted, code_edit)
	code_edit.insert_text_at_caret(adapted)
	return true

## Detect whether the target script uses tabs or spaces, then convert
## leading indentation on every line of `text` to match.
static func _adapt_indentation(text: String, code_edit: CodeEdit) -> String:
	var use_tabs := _detect_use_tabs(code_edit)
	var space_size := _get_indent_size()
	var lines := text.split("\n")
	var result: PackedStringArray = []
	for line in lines:
		result.append(_convert_line_indent(line, use_tabs, space_size))
	return "\n".join(result)

## Prefer the file's own indentation. Fall back to the editor setting
## text_editor/behavior/indent/type (0 = Tabs, 1 = Spaces). Default tabs.
static func _detect_use_tabs(code_edit: CodeEdit) -> bool:
	var tab_lines := 0
	var space_lines := 0
	for i in code_edit.get_line_count():
		var line := code_edit.get_line(i)
		if line.is_empty():
			continue
		if line.begins_with("\t"):
			tab_lines += 1
		elif line.begins_with(" "):
			space_lines += 1
	if tab_lines > 0 or space_lines > 0:
		return tab_lines >= space_lines

	var settings := EditorInterface.get_editor_settings()
	if settings and settings.has_setting("text_editor/behavior/indent/type"):
		# 0 = Tabs, 1 = Spaces
		return int(settings.get_setting("text_editor/behavior/indent/type")) == 0
	return true

static func _get_indent_size() -> int:
	var settings := EditorInterface.get_editor_settings()
	if settings and settings.has_setting("text_editor/behavior/indent/size"):
		return maxi(int(settings.get_setting("text_editor/behavior/indent/size")), 1)
	return 4

## Convert leading whitespace on one line to tabs or spaces.
## Tabs count as one indent level; runs of `space_size` spaces count as one.
static func _convert_line_indent(line: String, use_tabs: bool, space_size: int) -> String:
	var i := 0
	var levels := 0
	var extra_spaces := 0
	while i < line.length():
		var c := line[i]
		if c == "\t":
			levels += 1
			extra_spaces = 0
			i += 1
		elif c == " ":
			extra_spaces += 1
			if extra_spaces >= space_size:
				levels += 1
				extra_spaces = 0
			i += 1
		else:
			break
	var content := line.substr(i)
	if use_tabs:
		return "\t".repeat(levels) + " ".repeat(extra_spaces) + content
	return " ".repeat(levels * space_size + extra_spaces) + content

## Insert a separating blank line when the caret sits after non-empty content.
static func _ensure_blank_line_before(text: String, code_edit: CodeEdit) -> String:
	var caret_line := code_edit.get_caret_line()
	var caret_col := code_edit.get_caret_column()
	var need_blank := false

	if caret_col > 0:
		# Mid-line insert: start on a new blank line after the current content.
		need_blank = true
	elif caret_line > 0:
		var prev := code_edit.get_line(caret_line - 1)
		if not prev.strip_edges().is_empty():
			need_blank = true

	if not need_blank:
		return text

	# One newline ends the previous line (if mid-line) / separates; second makes blank.
	if caret_col > 0:
		return "\n\n" + text
	return "\n" + text
