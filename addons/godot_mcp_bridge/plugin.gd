@tool
extends EditorPlugin

const _DebuggerScript = preload("res://addons/godot_mcp_bridge/debugger_plugin.gd")
const _BridgeServerScript = preload("res://addons/godot_mcp_bridge/bridge_server.gd")

# Screenshotting the running game requires code inside the game process, which
# means an autoload. Registering one writes an [autoload] entry to
# project.godot; set the editor setting below to false to opt out.
const _AUTOLOAD_NAME := "ClaudeBridgeGameCapture"
const _AUTOLOAD_PATH := "res://addons/godot_mcp_bridge/game_capture.gd"
const _GAME_CAPTURE_SETTING := "claude_bridge/enable_game_capture"

var _bridge_server
var _debugger_plugin

func _enter_tree() -> void:
	# Skip bridge in headless/export mode
	if DisplayServer.get_name() == "headless":
		return

	_debugger_plugin = _DebuggerScript.new()
	_debugger_plugin.set_editor_interface(EditorInterface)
	add_debugger_plugin(_debugger_plugin)

	_bridge_server = _BridgeServerScript.new()
	_bridge_server.editor_interface = EditorInterface
	add_child(_bridge_server)
	_bridge_server.set_debugger(_debugger_plugin)
	_bridge_server.set_profiler_handler(_debugger_plugin)
	_bridge_server.start()
	_sync_game_capture_autoload()
	print("[Claude Bridge] Started on port 6008")

func _exit_tree() -> void:
	if _bridge_server:
		_bridge_server.stop()
		_bridge_server.queue_free()
		_bridge_server = null
	if _debugger_plugin:
		remove_debugger_plugin(_debugger_plugin)
		_debugger_plugin = null
	print("[Claude Bridge] Stopped")


# Bring the autoload in line with the setting, adding or removing only when it
# actually differs.
#
# This runs on editor start rather than from _enable_plugin(), which fires only
# when the plugin checkbox is ticked — a project that already lists the plugin
# as enabled never calls it, so an existing install would otherwise never gain
# the autoload. Being idempotent keeps project.godot from churning each
# session, which removing it in _exit_tree() would have caused.
func _sync_game_capture_autoload() -> void:
	var present := ProjectSettings.has_setting("autoload/" + _AUTOLOAD_NAME)
	if _game_capture_enabled():
		if not present:
			add_autoload_singleton(_AUTOLOAD_NAME, _AUTOLOAD_PATH)
	elif present:
		remove_autoload_singleton(_AUTOLOAD_NAME)

func _disable_plugin() -> void:
	if ProjectSettings.has_setting("autoload/" + _AUTOLOAD_NAME):
		remove_autoload_singleton(_AUTOLOAD_NAME)


# Whether to install the game-side capture autoload. Defaults to true and is
# stored per user in the editor settings, so opting out does not require
# editing anything the project tracks.
func _game_capture_enabled() -> bool:
	var settings := EditorInterface.get_editor_settings()
	if settings == null:
		return true
	if not settings.has_setting(_GAME_CAPTURE_SETTING):
		settings.set_setting(_GAME_CAPTURE_SETTING, true)
	return bool(settings.get_setting(_GAME_CAPTURE_SETTING))
