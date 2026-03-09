@tool
class_name AISettingsDialog
extends AcceptDialog

## Settings UI for GodotAI plugin.
## Provider tabs: Anthropic, OpenAI, OpenRouter.
## Shows API key fields, model dropdowns, temperature sliders.

signal settings_saved(settings: AISettings)

var _settings: AISettings = null
var _provider_manager: ProviderManager = null

# Sync guard: OptionButton and TabContainer mirror each other's selection.
# Without this flag, changing one triggers the other's callback, which triggers
# the first again, creating an infinite recursion loop.
var _syncing: bool = false

# General tab
var _font_size_spin: SpinBox
var _focus_chat_shortcut_btn: Button
var _send_code_shortcut_btn: Button
var _send_msg_shortcut_btn: Button
var _shortcut_capture_target: Button = null
var _shortcut_capture_original: String = ""

# Provider selector
var _provider_option: OptionButton

# Tab container (kept for 2-way sync with _provider_option)
var _tabs: TabContainer

# Anthropic tab
var _anthropic_key_field: LineEdit
var _anthropic_model_option: OptionButton
var _anthropic_refresh_btn: Button
var _anthropic_temp_slider: HSlider
var _anthropic_temp_label: Label
var _anthropic_tokens_spin: SpinBox

# OpenAI tab
var _openai_key_field: LineEdit
var _openai_model_option: OptionButton
var _openai_refresh_btn: Button
var _openai_temp_slider: HSlider
var _openai_temp_label: Label
var _openai_tokens_spin: SpinBox

# OpenRouter tab
var _openrouter_key_field: LineEdit
var _openrouter_model_field: LineEdit
var _openrouter_temp_slider: HSlider
var _openrouter_temp_label: Label
var _openrouter_tokens_spin: SpinBox

func _ready() -> void:
	title = "GodotAI Settings"
	min_size = Vector2i(820, 720)
	get_ok_button().text = "Save"
	add_cancel_button("Cancel")
	confirmed.connect(_on_save)
	canceled.connect(_populate_fields)
	_build_ui()

## Call once after creating the dialog to give it access to provider model lists.
func setup_provider_manager(pm: ProviderManager) -> void:
	_provider_manager = pm

## Populate the dialog from the given settings and show it.
## Also triggers model re-fetch if a provider has an API key but no cached models.
func open_with_settings(settings: AISettings) -> void:
	_settings = settings
	_populate_fields()
	_auto_fetch_models()
	popup_centered()

## Build the full settings UI programmatically.
## Tab 0 = General (shortcuts + font), tabs 1-3 = provider-specific settings.
func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(vbox)

	# Active provider row
	var provider_row := HBoxContainer.new()
	vbox.add_child(provider_row)
	var provider_lbl := Label.new()
	provider_lbl.text = "Active Provider:"
	provider_lbl.custom_minimum_size.x = 140
	provider_row.add_child(provider_lbl)
	_provider_option = OptionButton.new()
	_provider_option.add_item("Anthropic (Claude)", 0)
	_provider_option.add_item("OpenAI (ChatGPT)", 1)
	_provider_option.add_item("OpenRouter", 2)
	_provider_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_provider_option.item_selected.connect(_on_provider_option_selected)
	provider_row.add_child(_provider_option)

	vbox.add_child(HSeparator.new())

	# Tab container for provider-specific settings
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.tab_changed.connect(_on_tab_changed)
	vbox.add_child(_tabs)

	_tabs.add_child(_build_general_tab())
	_tabs.add_child(_build_anthropic_tab())
	_tabs.add_child(_build_openai_tab())
	_tabs.add_child(_build_openrouter_tab())

func _build_general_tab() -> Control:
	var container := VBoxContainer.new()
	container.name = "General"
	container.add_theme_constant_override("separation", 8)
	_font_size_spin = _add_spinbox_row(container, "Font Size:", 10, 48, 28)

	container.add_child(HSeparator.new())

	var sc_header := Label.new()
	sc_header.text = "Keyboard Shortcuts"
	sc_header.add_theme_font_size_override("font_size", 20)
	container.add_child(sc_header)

	_focus_chat_shortcut_btn = _add_shortcut_row(container, "Focus Chat:", "Ctrl+/")
	_send_code_shortcut_btn = _add_shortcut_row(container, "Send Selected Code:", "Ctrl+Shift+/")
	_send_msg_shortcut_btn = _add_shortcut_row(container, "Send Message:", "Ctrl+Enter")

	return container

## Build a shortcut capture row: label + button showing the current shortcut +
## Reset button. Pressing the shortcut button enters capture mode via
## _on_shortcut_button_pressed(), which makes _input() intercept the next keypress.
func _add_shortcut_row(parent: VBoxContainer, label_text: String, default_shortcut: String) -> Button:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size.x = 180
	row.add_child(lbl)
	var shortcut_btn := Button.new()
	shortcut_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shortcut_btn.pressed.connect(_on_shortcut_button_pressed.bind(shortcut_btn))
	row.add_child(shortcut_btn)
	var reset_btn := Button.new()
	reset_btn.text = "Reset"
	reset_btn.pressed.connect(func(): shortcut_btn.text = default_shortcut)
	row.add_child(reset_btn)
	return shortcut_btn

func _build_anthropic_tab() -> Control:
	var container := VBoxContainer.new()
	container.name = "Anthropic"
	container.add_theme_constant_override("separation", 8)

	_anthropic_key_field = _add_key_row(container, "API Key:")
	# Model dropdown populated in _populate_fields() via ProviderManager
	_anthropic_model_option = _add_model_dropdown(container, "Model:", [])
	_anthropic_refresh_btn = Button.new()
	_anthropic_refresh_btn.text = "Refresh"
	_anthropic_refresh_btn.pressed.connect(func(): _start_model_fetch("anthropic"))
	_anthropic_model_option.get_parent().add_child(_anthropic_refresh_btn)
	var temp_r := _add_temperature_row(container, "Temperature:",
		func(v): _anthropic_temp_label.text = "%.2f" % v)
	_anthropic_temp_slider = temp_r.slider
	_anthropic_temp_label = temp_r.label
	_anthropic_tokens_spin = _add_spinbox_row(container, "Max Tokens:", 1, 8192, 4096)

	return container

func _build_openai_tab() -> Control:
	var container := VBoxContainer.new()
	container.name = "OpenAI"
	container.add_theme_constant_override("separation", 8)

	_openai_key_field = _add_key_row(container, "API Key:")
	_openai_model_option = _add_model_dropdown(container, "Model:", [])
	_openai_refresh_btn = Button.new()
	_openai_refresh_btn.text = "Refresh"
	_openai_refresh_btn.pressed.connect(func(): _start_model_fetch("openai"))
	_openai_model_option.get_parent().add_child(_openai_refresh_btn)
	var temp_r := _add_temperature_row(container, "Temperature:",
		func(v): _openai_temp_label.text = "%.2f" % v)
	_openai_temp_slider = temp_r.slider
	_openai_temp_label = temp_r.label
	_openai_tokens_spin = _add_spinbox_row(container, "Max Tokens:", 1, 16384, 4096)

	return container

func _build_openrouter_tab() -> Control:
	var container := VBoxContainer.new()
	container.name = "OpenRouter"
	container.add_theme_constant_override("separation", 8)

	_openrouter_key_field = _add_key_row(container, "API Key:")

	# OpenRouter: free-text model field (supports any model string)
	var model_row := HBoxContainer.new()
	container.add_child(model_row)
	var lbl := Label.new()
	lbl.text = "Model:"
	lbl.custom_minimum_size.x = 140
	model_row.add_child(lbl)
	_openrouter_model_field = LineEdit.new()
	_openrouter_model_field.placeholder_text = "e.g. anthropic/claude-opus-4"
	_openrouter_model_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	model_row.add_child(_openrouter_model_field)

	var temp_r := _add_temperature_row(container, "Temperature:",
		func(v): _openrouter_temp_label.text = "%.2f" % v)
	_openrouter_temp_slider = temp_r.slider
	_openrouter_temp_label = temp_r.label
	_openrouter_tokens_spin = _add_spinbox_row(container, "Max Tokens:", 1, 16384, 4096)

	var hint := Label.new()
	hint.text = "Browse models at openrouter.ai/models"
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	container.add_child(hint)

	return container

# --- Shortcut capture ---

## Enter capture mode: record which button triggered it and change its label
## to "Press a key..." so _input() knows to intercept the next keypress.
func _on_shortcut_button_pressed(btn: Button) -> void:
	# Cancel any previous capture first
	if _shortcut_capture_target != null:
		_shortcut_capture_target.text = _shortcut_capture_original
		_shortcut_capture_target = null
	_shortcut_capture_original = btn.text
	_shortcut_capture_target = btn
	btn.text = "Press a key..."

## Capture mode handler: ignores modifier-only presses (Ctrl alone isn't a
## valid shortcut), Escape cancels without saving, any other key commits the
## new shortcut string and exits capture mode.
func _input(event: InputEvent) -> void:
	if _shortcut_capture_target == null:
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var key_event := event as InputEventKey
	# Ignore bare modifier-only presses
	if key_event.keycode in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]:
		return
	get_viewport().set_input_as_handled()
	if key_event.keycode == KEY_ESCAPE:
		_shortcut_capture_target.text = _shortcut_capture_original
	else:
		var shortcut_str := AISettings.event_to_shortcut_string(key_event)
		_shortcut_capture_target.text = shortcut_str if not shortcut_str.is_empty() else _shortcut_capture_original
	_shortcut_capture_target = null

# --- Tab / provider-option sync (3.2) ---

## Sync TabContainer to match the provider OptionButton selection.
## _syncing guard prevents infinite recursion with _on_tab_changed().
func _on_provider_option_selected(index: int) -> void:
	if _syncing:
		return
	_syncing = true
	_tabs.current_tab = index + 1  # General tab is at index 0
	_syncing = false

## Sync provider OptionButton to match the TabContainer selection.
## _syncing guard prevents infinite recursion with _on_provider_option_selected().
func _on_tab_changed(index: int) -> void:
	if _syncing:
		return
	if index < 1:
		return  # General tab — no provider to sync
	_syncing = true
	_provider_option.selected = index - 1
	_syncing = false

# --- Helpers ---

func _add_key_row(parent: VBoxContainer, label_text: String) -> LineEdit:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size.x = 140
	row.add_child(lbl)
	var field := LineEdit.new()
	field.secret = true
	field.placeholder_text = "sk-..."
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(field)
	return field

func _add_model_dropdown(parent: VBoxContainer, label_text: String, models: Array[String]) -> OptionButton:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size.x = 140
	row.add_child(lbl)
	var dropdown := OptionButton.new()
	for m in models:
		dropdown.add_item(m)
	dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(dropdown)
	return dropdown

## Returns {"slider": HSlider, "label": Label} — avoids fragile child-index access.
func _add_temperature_row(parent: VBoxContainer, label_text: String, on_change: Callable) -> Dictionary:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size.x = 140
	row.add_child(lbl)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 2.0
	slider.step = 0.01
	slider.value = 0.7
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var val_lbl := Label.new()
	val_lbl.text = "0.70"
	val_lbl.custom_minimum_size.x = 40
	row.add_child(val_lbl)
	slider.value_changed.connect(on_change)
	return {"slider": slider, "label": val_lbl}

func _add_spinbox_row(parent: VBoxContainer, label_text: String, min_val: int, max_val: int, default_val: int) -> SpinBox:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size.x = 140
	row.add_child(lbl)
	var spin := SpinBox.new()
	spin.min_value = min_val
	spin.max_value = max_val
	spin.value = default_val
	spin.step = 1
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spin)
	return spin

func _populate_model_dropdown(dropdown: OptionButton, models: Array[String], current: String) -> void:
	dropdown.clear()
	for m in models:
		dropdown.add_item(m)
	_set_dropdown_to(dropdown, current)

# --- Dynamic model fetching ---

## Trigger model fetches for providers that have an API key but haven't
## cached their model list yet. Called when the dialog opens so the
## models dropdown is always up-to-date.
func _auto_fetch_models() -> void:
	if not _provider_manager or not _settings:
		return
	var anthropic := _provider_manager.get_provider("anthropic")
	if anthropic and anthropic.is_configured() and not anthropic.has_cached_models():
		_start_model_fetch("anthropic")
	var openai := _provider_manager.get_provider("openai")
	if openai and openai.is_configured() and not openai.has_cached_models():
		_start_model_fetch("openai")

## Start an async model fetch: delegate to the provider, connect a one-shot
## signal for the result, and show "Loading..." on the refresh button.
func _start_model_fetch(provider_key: String) -> void:
	if not _provider_manager:
		return
	var provider := _provider_manager.get_provider(provider_key)
	if not provider or provider.is_fetching_models():
		return
	var btn: Button = _anthropic_refresh_btn if provider_key == "anthropic" else _openai_refresh_btn
	btn.text = "Loading..."
	btn.disabled = true
	provider.models_fetched.connect(
		func(models: Array[String]): _on_models_fetched(provider_key, models),
		CONNECT_ONE_SHOT
	)
	provider.fetch_models()

## Handle fetched models: repopulate the dropdown while preserving the
## user's current selection (even if it wasn't in the fetched list).
func _on_models_fetched(provider_key: String, models: Array[String]) -> void:
	var dropdown: OptionButton
	var btn: Button
	if provider_key == "anthropic":
		dropdown = _anthropic_model_option
		btn = _anthropic_refresh_btn
	else:
		dropdown = _openai_model_option
		btn = _openai_refresh_btn

	# Preserve the current selection even if it isn't in the fetched list.
	var current_model := ""
	if dropdown.selected >= 0 and dropdown.item_count > 0:
		current_model = dropdown.get_item_text(dropdown.selected)

	var all_models: Array[String] = []
	for m in models:
		all_models.append(m)
	if not current_model.is_empty() and not all_models.has(current_model):
		all_models.insert(0, current_model)

	_populate_model_dropdown(dropdown, all_models, current_model)
	btn.text = "Refresh"
	btn.disabled = false

# --- Populate / Save ---

## Populate all UI fields from the current AISettings. Also serves as the
## Cancel handler — restoring fields to their last-saved state.
func _populate_fields() -> void:
	if not _settings:
		return

	# Cancel any in-progress shortcut capture
	_shortcut_capture_target = null

	_font_size_spin.value = _settings.font_size
	_focus_chat_shortcut_btn.text = _settings.shortcut_focus_chat
	_send_code_shortcut_btn.text = _settings.shortcut_send_code
	_send_msg_shortcut_btn.text = _settings.shortcut_send_message

	# Active provider — sync both dropdown and tab without feedback loop
	var idx := ProviderManager.PROVIDER_KEYS.find(_settings.active_provider)
	if idx < 0:
		idx = 0
	_syncing = true
	_provider_option.selected = idx
	_tabs.current_tab = idx + 1  # General tab is at index 0
	_syncing = false

	# Populate model dropdowns using the full combined list (hardcoded + fetched + custom).
	if _provider_manager:
		var anthropic := _provider_manager.get_provider("anthropic")
		_populate_model_dropdown(_anthropic_model_option, anthropic.get_all_models(), _settings.anthropic_model)

		var openai := _provider_manager.get_provider("openai")
		_populate_model_dropdown(_openai_model_option, openai.get_all_models(), _settings.openai_model)

	# Anthropic
	_anthropic_key_field.text = _settings.anthropic_api_key
	_anthropic_temp_slider.value = _settings.anthropic_temperature
	_anthropic_tokens_spin.value = _settings.anthropic_max_tokens

	# OpenAI
	_openai_key_field.text = _settings.openai_api_key
	_openai_temp_slider.value = _settings.openai_temperature
	_openai_tokens_spin.value = _settings.openai_max_tokens

	# OpenRouter
	_openrouter_key_field.text = _settings.openrouter_api_key
	_openrouter_model_field.text = _settings.openrouter_model
	_openrouter_temp_slider.value = _settings.openrouter_temperature
	_openrouter_tokens_spin.value = _settings.openrouter_max_tokens

func _set_dropdown_to(dropdown: OptionButton, value: String) -> void:
	for i in dropdown.item_count:
		if dropdown.get_item_text(i) == value:
			dropdown.selected = i
			return
	dropdown.selected = 0

## Harvest all UI values into AISettings, persist to disk, and emit
## settings_saved so plugin.gd can update its provider cache and shortcuts.
func _on_save() -> void:
	if not _settings:
		_settings = AISettings.new()

	_settings.active_provider = ProviderManager.PROVIDER_KEYS[_provider_option.selected]
	_settings.font_size = int(_font_size_spin.value)
	_settings.shortcut_focus_chat = _focus_chat_shortcut_btn.text
	_settings.shortcut_send_code = _send_code_shortcut_btn.text
	_settings.shortcut_send_message = _send_msg_shortcut_btn.text

	_settings.anthropic_api_key = _anthropic_key_field.text.strip_edges()
	_settings.anthropic_model = _anthropic_model_option.get_item_text(_anthropic_model_option.selected)
	_settings.anthropic_temperature = _anthropic_temp_slider.value
	_settings.anthropic_max_tokens = int(_anthropic_tokens_spin.value)

	_settings.openai_api_key = _openai_key_field.text.strip_edges()
	_settings.openai_model = _openai_model_option.get_item_text(_openai_model_option.selected)
	_settings.openai_temperature = _openai_temp_slider.value
	_settings.openai_max_tokens = int(_openai_tokens_spin.value)

	_settings.openrouter_api_key = _openrouter_key_field.text.strip_edges()
	_settings.openrouter_model = _openrouter_model_field.text.strip_edges()
	_settings.openrouter_temperature = _openrouter_temp_slider.value
	_settings.openrouter_max_tokens = int(_openrouter_tokens_spin.value)

	# Register custom models that are not in any provider's known list.
	if _provider_manager:
		var anthropic := _provider_manager.get_provider("anthropic")
		if not _settings.anthropic_model.is_empty() and \
				not (_settings.anthropic_model in anthropic.get_available_models()):
			_settings.add_custom_model("anthropic", _settings.anthropic_model)

		var openai := _provider_manager.get_provider("openai")
		if not _settings.openai_model.is_empty() and \
				not (_settings.openai_model in openai.get_available_models()):
			_settings.add_custom_model("openai", _settings.openai_model)

		var openrouter := _provider_manager.get_provider("openrouter")
		if not _settings.openrouter_model.is_empty() and \
				not (_settings.openrouter_model in openrouter.get_available_models()):
			_settings.add_custom_model("openrouter", _settings.openrouter_model)

	# Save to disk immediately so settings survive an editor crash.
	_settings.save()
	settings_saved.emit(_settings)
