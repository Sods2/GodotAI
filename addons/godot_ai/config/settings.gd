@tool
class_name AISettings
extends RefCounted

## Stores and loads plugin settings using ConfigFile.
## Settings are persisted to user://godot_ai_settings.cfg.

const SETTINGS_PATH := "user://godot_ai_settings.cfg"

const SECTION_GENERAL := "general"
const SECTION_ANTHROPIC := "anthropic"
const SECTION_OPENAI := "openai"
const SECTION_OPENROUTER := "openrouter"
const SECTION_LOCAL := "local"
const SECTION_SHORTCUTS := "shortcuts"
const SECTION_CUSTOM_MODELS := "custom_models"

var _config := ConfigFile.new()

# Custom models (keyed by provider key, value is Array[String])
var custom_models: Dictionary = {}

# General
var active_provider: String = "anthropic"
var font_size: int = 28

# Shortcuts
var shortcut_focus_chat: String = "Ctrl+/"
var shortcut_send_code: String = "Ctrl+Shift+/"
var shortcut_send_message: String = "Ctrl+Enter"

# Anthropic
var anthropic_api_key: String = ""
var anthropic_model: String = "claude-opus-4-6"
var anthropic_temperature: float = 0.7
var anthropic_max_tokens: int = 4096

# OpenAI
var openai_api_key: String = ""
var openai_model: String = "gpt-4o"
var openai_temperature: float = 0.7
var openai_max_tokens: int = 4096

# OpenRouter
var openrouter_api_key: String = ""
var openrouter_model: String = "anthropic/claude-opus-4"
var openrouter_temperature: float = 0.7
var openrouter_max_tokens: int = 4096

# Local (Ollama / LM Studio / llama.cpp / custom OpenAI-compatible server)
var local_endpoint_url: String = "http://localhost:11434/v1"
var local_api_key: String = ""
var local_model: String = "llama3.2"
var local_temperature: float = 0.7
var local_max_tokens: int = 4096
var local_server_preset: String = "ollama"

## Load settings from disk. Missing keys fall back to defaults, numeric values
## are clamped to valid ranges, and unknown provider names reset to "Anthropic".
func load() -> void:
	var err := _config.load(SETTINGS_PATH)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		push_warning("GodotAI: Failed to load settings: %s" % error_string(err))
		return

	var loaded_provider: String = _config.get_value(SECTION_GENERAL, "active_provider", active_provider)
	active_provider = loaded_provider if loaded_provider in ["anthropic", "openai", "openrouter", "local"] else "anthropic"
	font_size = clampi(int(_config.get_value(SECTION_GENERAL, "font_size", 28)), 10, 48)

	anthropic_api_key = _config.get_value(SECTION_ANTHROPIC, "api_key", "")
	anthropic_model = _config.get_value(SECTION_ANTHROPIC, "model", anthropic_model)
	anthropic_temperature = clampf(float(_config.get_value(SECTION_ANTHROPIC, "temperature", anthropic_temperature)), 0.0, 2.0)
	anthropic_max_tokens = clampi(int(_config.get_value(SECTION_ANTHROPIC, "max_tokens", anthropic_max_tokens)), 1, 65536)

	openai_api_key = _config.get_value(SECTION_OPENAI, "api_key", "")
	openai_model = _config.get_value(SECTION_OPENAI, "model", openai_model)
	openai_temperature = clampf(float(_config.get_value(SECTION_OPENAI, "temperature", openai_temperature)), 0.0, 2.0)
	openai_max_tokens = clampi(int(_config.get_value(SECTION_OPENAI, "max_tokens", openai_max_tokens)), 1, 65536)

	openrouter_api_key = _config.get_value(SECTION_OPENROUTER, "api_key", "")
	openrouter_model = _config.get_value(SECTION_OPENROUTER, "model", openrouter_model)
	openrouter_temperature = clampf(float(_config.get_value(SECTION_OPENROUTER, "temperature", openrouter_temperature)), 0.0, 2.0)
	openrouter_max_tokens = clampi(int(_config.get_value(SECTION_OPENROUTER, "max_tokens", openrouter_max_tokens)), 1, 65536)

	local_endpoint_url = _config.get_value(SECTION_LOCAL, "endpoint_url", local_endpoint_url)
	local_api_key = _config.get_value(SECTION_LOCAL, "api_key", "")
	local_model = _config.get_value(SECTION_LOCAL, "model", local_model)
	local_temperature = clampf(float(_config.get_value(SECTION_LOCAL, "temperature", local_temperature)), 0.0, 2.0)
	local_max_tokens = clampi(int(_config.get_value(SECTION_LOCAL, "max_tokens", local_max_tokens)), 1, 65536)
	local_server_preset = _config.get_value(SECTION_LOCAL, "server_preset", local_server_preset)

	shortcut_focus_chat = _config.get_value(SECTION_SHORTCUTS, "focus_chat", "Ctrl+/")
	shortcut_send_code = _config.get_value(SECTION_SHORTCUTS, "send_code", "Ctrl+Shift+/")
	shortcut_send_message = _config.get_value(SECTION_SHORTCUTS, "send_message", "Ctrl+Enter")

	custom_models = {}
	for key in ["anthropic", "openai", "openrouter", "local"]:
		var saved = _config.get_value(SECTION_CUSTOM_MODELS, key, [])
		if saved is Array and not saved.is_empty():
			custom_models[key] = saved

## Write all settings to disk. Setting a config key to null (for empty custom
## model lists) erases it from the file, keeping the config clean.
func save() -> void:
	_config.set_value(SECTION_GENERAL, "active_provider", active_provider)
	_config.set_value(SECTION_GENERAL, "font_size", font_size)

	_config.set_value(SECTION_ANTHROPIC, "api_key", anthropic_api_key)
	_config.set_value(SECTION_ANTHROPIC, "model", anthropic_model)
	_config.set_value(SECTION_ANTHROPIC, "temperature", anthropic_temperature)
	_config.set_value(SECTION_ANTHROPIC, "max_tokens", anthropic_max_tokens)

	_config.set_value(SECTION_OPENAI, "api_key", openai_api_key)
	_config.set_value(SECTION_OPENAI, "model", openai_model)
	_config.set_value(SECTION_OPENAI, "temperature", openai_temperature)
	_config.set_value(SECTION_OPENAI, "max_tokens", openai_max_tokens)

	_config.set_value(SECTION_OPENROUTER, "api_key", openrouter_api_key)
	_config.set_value(SECTION_OPENROUTER, "model", openrouter_model)
	_config.set_value(SECTION_OPENROUTER, "temperature", openrouter_temperature)
	_config.set_value(SECTION_OPENROUTER, "max_tokens", openrouter_max_tokens)

	_config.set_value(SECTION_LOCAL, "endpoint_url", local_endpoint_url)
	_config.set_value(SECTION_LOCAL, "api_key", local_api_key)
	_config.set_value(SECTION_LOCAL, "model", local_model)
	_config.set_value(SECTION_LOCAL, "temperature", local_temperature)
	_config.set_value(SECTION_LOCAL, "max_tokens", local_max_tokens)
	_config.set_value(SECTION_LOCAL, "server_preset", local_server_preset)

	_config.set_value(SECTION_SHORTCUTS, "focus_chat", shortcut_focus_chat)
	_config.set_value(SECTION_SHORTCUTS, "send_code", shortcut_send_code)
	_config.set_value(SECTION_SHORTCUTS, "send_message", shortcut_send_message)

	for key in ["anthropic", "openai", "openrouter", "local"]:
		if custom_models.has(key) and not custom_models[key].is_empty():
			_config.set_value(SECTION_CUSTOM_MODELS, key, custom_models[key])
		else:
			_config.set_value(SECTION_CUSTOM_MODELS, key, null)

	var err := _config.save(SETTINGS_PATH)
	if err != OK:
		push_warning("GodotAI: Failed to save settings: %s" % error_string(err))

## Adds a custom model for a provider if it is not already stored.
func add_custom_model(provider_key: String, model_name: String) -> void:
	if model_name.is_empty():
		return
	if not custom_models.has(provider_key):
		custom_models[provider_key] = []
	if not (model_name in custom_models[provider_key]):
		custom_models[provider_key].append(model_name)

## Parses a shortcut string like "Ctrl+Shift+/" into a dict with keycode and modifier bools.
## "ctrl" matches ctrl-or-meta (cross-platform: Ctrl on Windows/Linux, Cmd on Mac).
static func parse_shortcut(shortcut_str: String) -> Dictionary:
	var result := {"keycode": KEY_NONE, "ctrl": false, "shift": false, "alt": false}
	if shortcut_str.is_empty():
		return result
	var parts := shortcut_str.split("+")
	# All parts except the last are modifier names
	for i in range(parts.size() - 1):
		match parts[i].strip_edges().to_lower():
			"ctrl", "cmd", "meta": result["ctrl"] = true
			"shift": result["shift"] = true
			"alt": result["alt"] = true
	result["keycode"] = _string_to_keycode(parts[-1].strip_edges())
	return result

## Returns true when a key event matches a parsed shortcut dict from parse_shortcut().
## "ctrl" in the parsed dict matches ctrl-or-meta for cross-platform compatibility.
static func matches_event(event: InputEventKey, parsed: Dictionary) -> bool:
	if parsed.is_empty() or parsed.get("keycode", KEY_NONE) == KEY_NONE:
		return false
	if event.keycode != parsed["keycode"]:
		return false
	var ctrl_or_cmd := event.ctrl_pressed or event.meta_pressed
	if parsed["ctrl"] != ctrl_or_cmd:
		return false
	if parsed["shift"] != event.shift_pressed:
		return false
	if parsed["alt"] != event.alt_pressed:
		return false
	return true

## Converts a pressed InputEventKey into a shortcut string like "Ctrl+Shift+/".
## Treats Ctrl and Meta (Cmd on Mac) as the same "Ctrl" modifier for cross-platform parity.
static func event_to_shortcut_string(event: InputEventKey) -> String:
	var parts: Array[String] = []
	if event.ctrl_pressed or event.meta_pressed:
		parts.append("Ctrl")
	if event.shift_pressed:
		parts.append("Shift")
	if event.alt_pressed:
		parts.append("Alt")
	var key_name := OS.get_keycode_string(event.keycode)
	if not key_name.is_empty():
		parts.append(key_name)
	return "+".join(parts)

## Convert a key name string to its Godot keycode. Tries single-char unicode
## first, then named keys (Return, Escape, etc.), then OS.find_keycode_from_string().
static func _string_to_keycode(key_str: String) -> int:
	# Single printable character — keycode equals its Unicode value in Godot 4
	if key_str.length() == 1:
		return key_str.unicode_at(0)
	# Named keys as returned by OS.get_keycode_string()
	match key_str.to_lower():
		"escape": return KEY_ESCAPE
		"tab": return KEY_TAB
		"backspace": return KEY_BACKSPACE
		"return", "enter": return KEY_ENTER
		"space": return KEY_SPACE
		"delete": return KEY_DELETE
		"home": return KEY_HOME
		"end": return KEY_END
		"page up", "pageup": return KEY_PAGEUP
		"page down", "pagedown": return KEY_PAGEDOWN
		"up": return KEY_UP
		"down": return KEY_DOWN
		"left": return KEY_LEFT
		"right": return KEY_RIGHT
		"f1": return KEY_F1
		"f2": return KEY_F2
		"f3": return KEY_F3
		"f4": return KEY_F4
		"f5": return KEY_F5
		"f6": return KEY_F6
		"f7": return KEY_F7
		"f8": return KEY_F8
		"f9": return KEY_F9
		"f10": return KEY_F10
		"f11": return KEY_F11
		"f12": return KEY_F12
	# Fallback: use Godot's built-in reverse lookup for any key name
	# (handles "Slash", "Semicolon", "BracketLeft", etc.)
	var keycode := OS.find_keycode_from_string(key_str)
	if keycode != KEY_NONE:
		return keycode
	return KEY_NONE
