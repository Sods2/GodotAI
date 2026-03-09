@tool
extends EditorPlugin

## GodotAI - AI coding assistant for Godot.
## Main EditorPlugin entry point.
## Registers the chat panel, wires providers, loads settings.

const PANEL_NAME := "AI Chat"

var _chat_panel: ChatPanel
var _provider_manager: ProviderManager
var _settings: AISettings
var _parsed_focus_chat: Dictionary = {}
var _parsed_send_code: Dictionary = {}

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
	_chat_panel.setup(_provider_manager, _settings, get_editor_interface())
	_chat_panel.settings_saved.connect(_on_chat_settings_saved)

	_chat_panel.name = PANEL_NAME
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _chat_panel)

	_cache_shortcuts()

## Teardown: save settings to disk (batched here instead of per-change),
## remove the dock panel, and free all nodes to avoid leaks.
func _exit_tree() -> void:
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
	var selected := ContextBuilder.get_selected_code(get_editor_interface())
	if selected.is_empty():
		return
	_chat_panel.send_selected_code(selected)
