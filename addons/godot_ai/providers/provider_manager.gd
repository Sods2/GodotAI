@tool
class_name ProviderManager
extends Node

## Routes AI requests to the active provider.
## Holds references to all providers and manages their lifecycle.
## Must be added to the scene tree so HTTPStream nodes can run _process().

signal response_token(text: String)
signal response_completed(full_text: String)
signal response_error(error: String)

const PROVIDER_KEYS: Array[String] = ["anthropic", "openai", "openrouter"]

var _providers: Dictionary = {}   # String -> ProviderBase
var _active_provider_name := "anthropic"
var _active_provider: ProviderBase = null
var _settings: AISettings = null

func _init() -> void:
	_providers["anthropic"] = AnthropicProvider.new()
	_providers["openai"] = OpenAIProvider.new()
	_providers["openrouter"] = OpenRouterProvider.new()

## Registers all providers as children so their HTTPStream nodes can use the
## scene tree, then restores settings if the plugin reloads mid-session.
func _enter_tree() -> void:
	for key in _providers:
		_providers[key].set_parent_node(self)

	_active_provider = _providers[_active_provider_name]
	_connect_active_provider()

	# Re-apply settings if available (handles editor dock rebuild / script reload)
	if _settings:
		apply_settings(_settings)

## Switch the active provider. Cancels any in-flight request on the old provider
## and rewires signal connections so callers always hear from the current one.
func set_active_provider(name: String) -> void:
	if not _providers.has(name):
		push_warning("ProviderManager: unknown provider '%s'" % name)
		return
	if _active_provider and _active_provider.is_busy():
		_active_provider.cancel()
	_disconnect_active_provider()
	_active_provider_name = name
	_active_provider = _providers[name]
	_connect_active_provider()

func get_active_provider() -> ProviderBase:
	return _active_provider

func get_active_provider_name() -> String:
	return _active_provider_name

func get_provider(name: String) -> ProviderBase:
	return _providers.get(name, null)

func get_all_provider_names() -> Array[String]:
	var names: Array[String] = []
	for key in _providers:
		names.append(key)
	return names

## Push API keys, model, temperature, and max_tokens to each provider.
## Clears a provider's model cache when its API key changes so stale lists
## from a previous key aren't shown in the dropdown.
func apply_settings(settings: AISettings) -> void:
	_settings = settings
	set_active_provider(settings.active_provider)

	var anthropic: AnthropicProvider = _providers["anthropic"]
	if settings.anthropic_api_key != anthropic.api_key:
		anthropic.clear_model_cache()
	anthropic.api_key = settings.anthropic_api_key
	anthropic.model = settings.anthropic_model
	anthropic.temperature = settings.anthropic_temperature
	anthropic.max_tokens = settings.anthropic_max_tokens
	anthropic.set_custom_models(settings.custom_models.get("anthropic", []))

	var openai: OpenAIProvider = _providers["openai"]
	if settings.openai_api_key != openai.api_key:
		openai.clear_model_cache()
	openai.api_key = settings.openai_api_key
	openai.model = settings.openai_model
	openai.temperature = settings.openai_temperature
	openai.max_tokens = settings.openai_max_tokens
	openai.set_custom_models(settings.custom_models.get("openai", []))

	var openrouter: OpenRouterProvider = _providers["openrouter"]
	openrouter.api_key = settings.openrouter_api_key
	openrouter.model = settings.openrouter_model
	openrouter.temperature = settings.openrouter_temperature
	openrouter.max_tokens = settings.openrouter_max_tokens
	openrouter.set_custom_models(settings.custom_models.get("openrouter", []))

## Forward a chat request to the active provider after a basic guard check.
func send_message(messages: Array, system_prompt: String = "") -> void:
	if not _active_provider:
		response_error.emit("No provider selected.")
		return
	_active_provider.send_message(messages, system_prompt)

func cancel() -> void:
	if _active_provider:
		_active_provider.cancel()

func is_active_provider_configured() -> bool:
	if not _active_provider:
		return false
	return _active_provider.is_configured()

# ── Signal routing ───────────────────────────────────────────────────────────

## Wire the active provider's signals to ProviderManager's own signals so
## callers (e.g. ChatPanel) don't need a direct reference to the provider.
func _connect_active_provider() -> void:
	if not _active_provider:
		return
	_active_provider.response_token.connect(response_token.emit)
	_active_provider.response_completed.connect(response_completed.emit)
	_active_provider.response_error.connect(response_error.emit)

## Remove signal connections from the outgoing provider before switching,
## preventing stale forwarding from a provider that is no longer active.
func _disconnect_active_provider() -> void:
	if not _active_provider:
		return
	if _active_provider.response_token.is_connected(response_token.emit):
		_active_provider.response_token.disconnect(response_token.emit)
	if _active_provider.response_completed.is_connected(response_completed.emit):
		_active_provider.response_completed.disconnect(response_completed.emit)
	if _active_provider.response_error.is_connected(response_error.emit):
		_active_provider.response_error.disconnect(response_error.emit)
