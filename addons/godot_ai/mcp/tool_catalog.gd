@tool
class_name ToolCatalog
extends RefCounted

## Canonical catalog of editor tools the AI can call, mapped to godot_mcp_bridge
## JSON-RPC methods. Each tool is stored in a provider-agnostic shape and converted
## to Anthropic's `tools` / OpenAI's `tools` formats on demand.
##
## Tool shape:
##   { name, method, description, scope ("safe"|"all"), destructive: bool,
##     schema: <JSON Schema object for the arguments> }
##
## "safe" tools are exposed by default; "all" also includes the wider set. The
## `destructive` flag drives the confirmation prompt in the chat panel.

## Name of the synthetic LSP diagnostics tool (served locally, not via the bridge).
const LSP_DIAGNOSTICS_TOOL := "get_gdscript_diagnostics"

static func _obj(props: Dictionary, required: Array = []) -> Dictionary:
	return {"type": "object", "properties": props, "required": required}

static func _str(desc: String) -> Dictionary:
	return {"type": "string", "description": desc}

static func _int(desc: String) -> Dictionary:
	return {"type": "integer", "description": desc}

## Every bridge-backed tool. Filtered by scope in get_mcp_tools().
static func _all_mcp_tools() -> Array:
	return [
		# ── Read-only inspection (safe) ────────────────────────────────────────
		{
			"name": "editor_status", "method": "editor.status", "scope": "safe", "destructive": false,
			"description": "Get editor status: the currently edited scene and whether the game is running.",
			"schema": _obj({}),
		},
		{
			"name": "get_scene_tree", "method": "scene.get_tree", "scope": "safe", "destructive": false,
			"description": "Get the node tree of the currently edited scene (names, types, and node paths).",
			"schema": _obj({
				"max_depth": _int("How many levels deep to descend. Default 10."),
				"type_filter": _str("Optional class name to filter nodes by (e.g. \"Node2D\")."),
			}),
		},
		{
			"name": "get_selected_nodes", "method": "scene.get_selected", "scope": "safe", "destructive": false,
			"description": "Get the nodes currently selected in the editor's scene tree.",
			"schema": _obj({}),
		},
		{
			"name": "get_node_properties", "method": "inspector.get_properties", "scope": "safe", "destructive": false,
			"description": "Get the properties of a node in the current scene.",
			"schema": _obj({"path": _str("Node path relative to the scene root, or \".\" for the root.")}, ["path"]),
		},
		{
			"name": "get_current_script", "method": "script.get_current", "scope": "safe", "destructive": false,
			"description": "Get the source of the script currently open in the script editor.",
			"schema": _obj({}),
		},
		{
			"name": "get_open_scripts", "method": "script.get_open", "scope": "safe", "destructive": false,
			"description": "List the scripts currently open in the script editor.",
			"schema": _obj({}),
		},
		{
			"name": "get_selected_code", "method": "script.get_selected_code", "scope": "safe", "destructive": false,
			"description": "Get the text currently selected in the script editor.",
			"schema": _obj({}),
		},
		{
			"name": "list_node_signals", "method": "signal.list", "scope": "safe", "destructive": false,
			"description": "List the signals a node exposes.",
			"schema": _obj({"path": _str("Node path relative to the scene root. Omit for the scene root.")}),
		},
		{
			"name": "is_scene_running", "method": "run.is_running", "scope": "safe", "destructive": false,
			"description": "Check whether the project/scene is currently running.",
			"schema": _obj({}),
		},
		{
			"name": "get_run_output", "method": "run.get_output", "scope": "safe", "destructive": false,
			"description": "Get stdout/stderr output from the running game since a given line number.",
			"schema": _obj({"since_line": _int("Return output starting at this line index. Default 0.")}),
		},
		{
			"name": "list_signal_connections", "method": "signal.list_connections", "scope": "safe", "destructive": false,
			"description": "List existing signal connections on a node (and, by default, its descendants).",
			"schema": _obj({
				"path": _str("Node path relative to the scene root. Omit for the scene root."),
				"recursive": {"type": "boolean", "description": "Include descendant nodes. Default true."},
			}),
		},
		{
			"name": "list_animations", "method": "animation.list", "scope": "safe", "destructive": false,
			"description": "List the animations on an AnimationPlayer node (name, length, track count).",
			"schema": _obj({"path": _str("Node path of the AnimationPlayer.")}, ["path"]),
		},
		{
			"name": "get_animation", "method": "animation.get", "scope": "safe", "destructive": false,
			"description": "Get the tracks and keyframes of one animation on an AnimationPlayer.",
			"schema": _obj({
				"path": _str("Node path of the AnimationPlayer."),
				"animation_name": _str("Name of the animation to read."),
			}, ["path", "animation_name"]),
		},
		{
			"name": "read_resource", "method": "resource.read", "scope": "safe", "destructive": false,
			"description": "Read a resource file's properties (e.g. a .tres/.res) from res://.",
			"schema": _obj({"path": _str("res:// path of the resource to read.")}, ["path"]),
		},
		{
			"name": "take_viewport_screenshot", "method": "screenshot.viewport", "scope": "safe", "destructive": false,
			"description": "Capture the editor viewport as a PNG (base64). Includes the running game when the Game tab is selected.",
			"schema": _obj({}),
		},
		{
			"name": "take_game_screenshot", "method": "screenshot.game", "scope": "safe", "destructive": false,
			"description": "Capture the running game's viewport as a PNG (base64) when available; otherwise returns guidance to use take_viewport_screenshot.",
			"schema": _obj({}),
		},

		# ── Mutations (safe, reversible via the editor's undo history) ──────────
		{
			"name": "add_node", "method": "scene.add_node", "scope": "safe", "destructive": false,
			"description": "Add a new node to the current scene.",
			"schema": _obj({
				"type": _str("Node class to instantiate (e.g. \"Sprite2D\", \"CharacterBody2D\")."),
				"name": _str("Name for the new node. Defaults to the type name."),
				"parent": _str("Path of the parent node. Defaults to the scene root (\".\")."),
				"properties": {"type": "object", "description": "Optional initial property values to set on the node."},
			}, ["type"]),
		},
		{
			"name": "set_node_property", "method": "inspector.set_property", "scope": "safe", "destructive": false,
			"description": "Set a property on a node in the current scene.",
			"schema": _obj({
				"path": _str("Node path relative to the scene root, or \".\" for the root."),
				"property": _str("Property name (e.g. \"position\", \"visible\")."),
				"value": {"description": "New value. Vectors/colors may be given as objects like {\"x\":1,\"y\":2}."},
			}, ["path", "property", "value"]),
		},
		{
			"name": "rename_node", "method": "scene.rename_node", "scope": "safe", "destructive": false,
			"description": "Rename a node in the current scene.",
			"schema": _obj({
				"path": _str("Node path relative to the scene root."),
				"new_name": _str("New name for the node."),
			}, ["path", "new_name"]),
		},
		{
			"name": "reparent_node", "method": "scene.reparent_node", "scope": "safe", "destructive": false,
			"description": "Move a node to a new parent in the current scene.",
			"schema": _obj({
				"path": _str("Node path of the node to move."),
				"new_parent": _str("Node path of the new parent, or \".\" for the root."),
			}, ["path", "new_parent"]),
		},
		{
			"name": "move_node", "method": "scene.move_node", "scope": "safe", "destructive": false,
			"description": "Reorder a node among its siblings in the current scene.",
			"schema": _obj({
				"path": _str("Node path of the node to move."),
				"index": _int("New zero-based index among its siblings."),
			}, ["path", "index"]),
		},
		{
			"name": "insert_code_at_cursor", "method": "script.insert_at_cursor", "scope": "safe", "destructive": false,
			"description": "Insert code at the cursor position in the currently open script.",
			"schema": _obj({"text": _str("The code to insert.")}, ["text"]),
		},
		{
			"name": "create_and_attach_script", "method": "script.create_and_attach", "scope": "safe", "destructive": false,
			"description": "Create a new GDScript file and attach it to a node in the current scene.",
			"schema": _obj({
				"node_path": _str("Node path to attach the script to."),
				"script_path": _str("res:// path for the new script (e.g. \"res://player.gd\")."),
				"template": _str("Optional initial file contents. Defaults to an \"extends <Class>\" stub."),
			}, ["node_path", "script_path"]),
		},
		{
			"name": "connect_signal", "method": "signal.connect", "scope": "safe", "destructive": false,
			"description": "Connect a signal from one node to a method on another node.",
			"schema": _obj({
				"from_path": _str("Node path emitting the signal."),
				"signal_name": _str("Name of the signal to connect."),
				"to_path": _str("Node path receiving the connection."),
				"method": _str("Method name on the target node to call."),
			}, ["from_path", "signal_name", "to_path", "method"]),
		},
		{
			"name": "run_scene", "method": "run.play", "scope": "safe", "destructive": false,
			"description": "Run the project (or a specific scene) in debug mode.",
			"schema": _obj({"scene": _str("Optional res:// scene path. Omit to run the main scene.")}),
		},
		{
			"name": "stop_scene", "method": "run.stop", "scope": "safe", "destructive": false,
			"description": "Stop the running game.",
			"schema": _obj({}),
		},

		# ── Debugging (safe, reversible) ───────────────────────────────────────
		{
			"name": "set_breakpoint", "method": "debug.set_breakpoint", "scope": "safe", "destructive": false,
			"description": "Set a breakpoint at a line in a script. Applies when the game runs (run_scene). Use get_open_scripts/get_current_script to find the file path.",
			"schema": _obj({
				"file": _str("res:// path of the script (e.g. \"res://player.gd\")."),
				"line": _int("1-based line number to break on."),
			}, ["file", "line"]),
		},
		{
			"name": "remove_breakpoint", "method": "debug.remove_breakpoint", "scope": "safe", "destructive": false,
			"description": "Remove a previously set breakpoint.",
			"schema": _obj({
				"file": _str("res:// path of the script."),
				"line": _int("1-based line number of the breakpoint to remove."),
			}, ["file", "line"]),
		},
		{
			"name": "list_breakpoints", "method": "debug.list_breakpoints", "scope": "safe", "destructive": false,
			"description": "List all currently set breakpoints.",
			"schema": _obj({}),
		},
		{
			"name": "get_stack_trace", "method": "debug.get_stack_trace", "scope": "safe", "destructive": false,
			"description": "Get the call stack while paused at a breakpoint. Errors if the game isn't paused.",
			"schema": _obj({}),
		},
		{
			"name": "get_local_variables", "method": "debug.get_locals", "scope": "safe", "destructive": false,
			"description": "Get local variables in the current frame while paused at a breakpoint.",
			"schema": _obj({}),
		},
		{
			"name": "debug_step_over", "method": "debug.step_over", "scope": "safe", "destructive": false,
			"description": "Step over the current line while paused at a breakpoint.",
			"schema": _obj({}),
		},
		{
			"name": "debug_step_into", "method": "debug.step_into", "scope": "safe", "destructive": false,
			"description": "Step into a function call while paused at a breakpoint.",
			"schema": _obj({}),
		},
		{
			"name": "debug_step_out", "method": "debug.step_out", "scope": "safe", "destructive": false,
			"description": "Step out of the current function while paused at a breakpoint.",
			"schema": _obj({}),
		},
		{
			"name": "debug_continue", "method": "debug.continue_execution", "scope": "safe", "destructive": false,
			"description": "Resume execution while paused at a breakpoint.",
			"schema": _obj({}),
		},

		# ── Destructive (safe scope, but prompts for confirmation) ─────────────
		{
			"name": "remove_node", "method": "scene.remove_node", "scope": "safe", "destructive": true,
			"description": "Remove a node from the current scene.",
			"schema": _obj({"path": _str("Node path of the node to remove.")}, ["path"]),
		},

		# ── Wider set (only when tool scope is \"all\") ─────────────────────────
		{
			"name": "duplicate_node", "method": "scene.duplicate_node", "scope": "all", "destructive": false,
			"description": "Duplicate a node (and its children) in the current scene.",
			"schema": _obj({"path": _str("Node path of the node to duplicate.")}, ["path"]),
		},
		{
			"name": "open_scene", "method": "scene.open", "scope": "all", "destructive": false,
			"description": "Open a scene file in the editor.",
			"schema": _obj({"path": _str("res:// path of the scene to open.")}, ["path"]),
		},
		{
			"name": "save_scene", "method": "scene.save", "scope": "all", "destructive": false,
			"description": "Save the currently edited scene.",
			"schema": _obj({}),
		},
		{
			"name": "get_script_for_node", "method": "script.get_for_node", "scope": "all", "destructive": false,
			"description": "Get the source of the script attached to a node.",
			"schema": _obj({"node_path": _str("Node path to read the script from.")}, ["node_path"]),
		},
		{
			"name": "disconnect_signal", "method": "signal.disconnect", "scope": "all", "destructive": true,
			"description": "Disconnect a signal connection between two nodes.",
			"schema": _obj({
				"from_path": _str("Node path emitting the signal."),
				"signal_name": _str("Name of the signal."),
				"to_path": _str("Node path receiving the connection."),
				"method": _str("Method name the signal is connected to."),
			}, ["from_path", "signal_name", "to_path", "method"]),
		},
		{
			"name": "detach_script", "method": "script.detach", "scope": "all", "destructive": true,
			"description": "Detach the script from a node (does not delete the file).",
			"schema": _obj({"node_path": _str("Node path to detach the script from.")}, ["node_path"]),
		},
		{
			"name": "create_animation", "method": "animation.create", "scope": "all", "destructive": false,
			"description": "Create a new value-track animation on an AnimationPlayer.",
			"schema": _obj({
				"path": _str("Node path of the AnimationPlayer."),
				"animation_name": _str("Name for the new animation."),
				"length": {"type": "number", "description": "Animation length in seconds. Default 1.0."},
				"loop_mode": _int("Loop mode: 0 none, 1 linear, 2 ping-pong. Default 0."),
				"tracks": {"type": "array", "description": "Optional value tracks: [{path, keys:[{time, value}]}]."},
			}, ["path", "animation_name"]),
		},
		{
			"name": "write_resource", "method": "resource.write", "scope": "all", "destructive": true,
			"description": "Set properties on an existing resource file and save it back to res://.",
			"schema": _obj({
				"path": _str("res:// path of the resource to write."),
				"properties": {"type": "object", "description": "Property name/value pairs to set on the resource."},
			}, ["path", "properties"]),
		},
		{
			"name": "import_resources", "method": "resource.import", "scope": "all", "destructive": false,
			"description": "(Re)import asset files into the project.",
			"schema": _obj({
				"paths": {"type": "array", "items": {"type": "string"}, "description": "res:// paths of the assets to import."},
			}, ["paths"]),
		},
		{
			"name": "start_profiler", "method": "profiler.start", "scope": "all", "destructive": false,
			"description": "Start the performance profiler on the running game.",
			"schema": _obj({}),
		},
		{
			"name": "stop_profiler", "method": "profiler.stop", "scope": "all", "destructive": false,
			"description": "Stop the profiler and return the collected frame data.",
			"schema": _obj({}),
		},
		{
			"name": "get_profiler_data", "method": "profiler.get_data", "scope": "all", "destructive": false,
			"description": "Get the profiler frame data collected so far.",
			"schema": _obj({}),
		},
	]

## Return canonical tools enabled for the given scope ("safe" includes only safe
## tools; "all" includes everything).
static func get_mcp_tools(scope: String = "safe") -> Array:
	var result: Array = []
	for tool in _all_mcp_tools():
		if scope == "all" or tool["scope"] == "safe":
			result.append(tool)
	return result

## The synthetic LSP diagnostics tool (handled inside GodotAI, not via the bridge).
static func lsp_diagnostics_tool() -> Dictionary:
	return {
		"name": LSP_DIAGNOSTICS_TOOL, "method": "", "scope": "safe", "destructive": false,
		"description": "Get GDScript errors and warnings for the currently open script, from Godot's language server.",
		"schema": _obj({}),
	}

## Look up a canonical tool by name across every scope (plus the LSP tool).
static func find(tool_name: String) -> Dictionary:
	if tool_name == LSP_DIAGNOSTICS_TOOL:
		return lsp_diagnostics_tool()
	for tool in _all_mcp_tools():
		if tool["name"] == tool_name:
			return tool
	return {}

## Bridge JSON-RPC method for a tool name, or "" if it isn't bridge-backed.
static func method_for(tool_name: String) -> String:
	var tool := find(tool_name)
	return tool.get("method", "")

## Whether a tool needs a confirmation prompt before running.
static func is_destructive(tool_name: String) -> bool:
	return find(tool_name).get("destructive", false)

# ── Provider format conversion ────────────────────────────────────────────────

## Convert canonical tools to Anthropic's `tools` format.
static func to_anthropic(tools: Array) -> Array:
	var result: Array = []
	for tool in tools:
		result.append({
			"name": tool["name"],
			"description": tool["description"],
			"input_schema": tool["schema"],
		})
	return result

## Convert canonical tools to OpenAI's `tools` (function-calling) format.
## Shared by OpenAI, OpenRouter, and OpenAI-compatible local servers.
static func to_openai(tools: Array) -> Array:
	var result: Array = []
	for tool in tools:
		result.append({
			"type": "function",
			"function": {
				"name": tool["name"],
				"description": tool["description"],
				"parameters": tool["schema"],
			},
		})
	return result
