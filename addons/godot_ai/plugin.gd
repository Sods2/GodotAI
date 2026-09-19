@tool
extends EditorPlugin

## GodotAI - AI coding assistant for Godot.
## Main EditorPlugin entry point.
## Registers the chat panel, wires providers, loads settings.

const PANEL_NAME := "AI Chat"

## Bundled godot_mcp_bridge editor plugin (shipped alongside GodotAI). GodotAI
## auto-enables it so agentic editor tools work with no extra install.
const BRIDGE_PLUGIN_NAME := "godot_mcp_bridge"
const BRIDGE_PLUGIN_CFG := "res://addons/godot_mcp_bridge/plugin.cfg"

var _chat_panel: ChatPanel
var _provider_manager: ProviderManager
var _settings: AISettings
var _parsed_focus_chat: Dictionary = {}
var _parsed_send_code: Dictionary = {}
var _proxy_pid: int = -1

## Initialize the plugin: create ProviderManager (must be in tree for HTTP),
## create ChatPanel with injected dependencies, connect settings_saved to
## keep shortcut cache in sync, and register the dock panel.
func _enter_tree() -> void:
	_settings = AISettings.new()
	_settings.load()

	_provider_manager = ProviderManager.new()
	add_child(_provider_manager)
	_provider_manager.apply_settings(_settings)

	_chat_panel = ChatPanel.new()
	_chat_panel.setup(_provider_manager, _settings, EditorInterface)
	_chat_panel.set_proxy_controls(start_claude_proxy, stop_claude_proxy, is_claude_proxy_running)
	_chat_panel.settings_saved.connect(_on_chat_settings_saved)

	_chat_panel.name = PANEL_NAME
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _chat_panel)

	_cache_shortcuts()

	# Deferred so it runs after the editor's own plugin-loading pass completes.
	call_deferred("_auto_enable_bridge")

## Enable the bundled godot_mcp_bridge plugin so the agentic editor tools work out of
## the box. Respects the MCP toggle and no-ops if the bridge addon isn't present or is
## already enabled. Not disabled on exit — external MCP clients may also rely on it.
func _auto_enable_bridge() -> void:
	if not _settings or not _settings.mcp_tools_enabled:
		return
	if not FileAccess.file_exists(BRIDGE_PLUGIN_CFG):
		return
	if EditorInterface.is_plugin_enabled(BRIDGE_PLUGIN_NAME):
		return
	EditorInterface.set_plugin_enabled(BRIDGE_PLUGIN_NAME, true)

## Teardown: save settings to disk (batched here instead of per-change),
## remove the dock panel, and free all nodes to avoid leaks.
func _exit_tree() -> void:
	stop_claude_proxy()
	if _chat_panel:
		remove_control_from_docks(_chat_panel)
		_chat_panel.queue_free()
		_chat_panel = null

	if _provider_manager:
		_provider_manager.queue_free()
		_provider_manager = null

	if _settings:
		_settings.save()
		_settings = null

func _cache_shortcuts() -> void:
	_parsed_focus_chat = AISettings.parse_shortcut(_settings.shortcut_focus_chat)
	_parsed_send_code = AISettings.parse_shortcut(_settings.shortcut_send_code)

func _on_chat_settings_saved(_s: AISettings) -> void:
	_cache_shortcuts()

## Global shortcut handler. Uses _shortcut_input() instead of _input() because
## it fires before UI controls consume the event, so shortcuts work even when
## a TextEdit or other input node has focus.
func _shortcut_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var key_event := event as InputEventKey
	if AISettings.matches_event(key_event, _parsed_focus_chat):
		if _chat_panel and _chat_panel._input_field:
			_chat_panel._input_field.grab_focus()
			get_viewport().set_input_as_handled()
	elif AISettings.matches_event(key_event, _parsed_send_code):
		_send_selected_code_to_chat()
		get_viewport().set_input_as_handled()

func _send_selected_code_to_chat() -> void:
	if not _chat_panel:
		return
	var selected := ContextBuilder.get_selected_code(EditorInterface)
	if selected.is_empty():
		return
	_chat_panel.send_selected_code(selected)

## Launches tools/claude_proxy.py as a background process.
## Returns "" on success, or an error string on failure.
func start_claude_proxy() -> String:
	if _proxy_pid > 0:
		return ""
	var proxy_res_path: String = get_script().resource_path.get_base_dir().path_join("tools/claude_proxy.py")
	var script_path := ProjectSettings.globalize_path(proxy_res_path)
	if not FileAccess.file_exists(proxy_res_path):
		return "Proxy script not found at " + proxy_res_path
	var python_cmd := "python3"
	if OS.get_name() == "Windows":
		var output := []
		var exit_code := OS.execute("where", PackedStringArray(["python3"]), output)
		if exit_code != 0:
			OS.execute("where", PackedStringArray(["python"]), output)
			python_cmd = "python"
	else:
		var output := []
		var exit_code := OS.execute("which", PackedStringArray(["python3"]), output)
		if exit_code != 0:
			return "python3 not found. Install Python 3 to use the built-in proxy."
	var pid := OS.create_process(python_cmd, PackedStringArray([script_path]))
	if pid <= 0:
		return "Failed to start proxy process."
	_proxy_pid = pid
	return ""

## Stops the running proxy process if one was started by the plugin.
func stop_claude_proxy() -> void:
	if _proxy_pid <= 0:
		return
	OS.kill(_proxy_pid)
	_proxy_pid = -1

## Returns true if the proxy was started by this plugin and has not been stopped.
func is_claude_proxy_running() -> bool:
	return _proxy_pid > 0
