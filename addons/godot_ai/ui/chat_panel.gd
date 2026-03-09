@tool
class_name ChatPanel
extends Control

## Main chat panel shown in the Godot editor right dock.
## Contains: toolbar (settings, clear, provider/model selector),
##           scrollable message history, and input area.

signal settings_saved(settings: AISettings)

const HISTORY_DIR := "user://godot_ai_history"

var _provider_manager: ProviderManager = null
var _settings: AISettings = null
var _settings_dialog: AISettingsDialog = null
var _editor_interface: EditorInterface = null

# Chat state
var _messages: Array = []  # Array of {role, content}
var _current_assistant_display: MessageDisplay = null
var _is_waiting: bool = false
var _hints_sent: bool = false  # GDScript hints included only on first message per conversation
var _welcome_label: Label = null

# Thinking indicator
var _thinking_timer: Timer = null
var _thinking_label: Label = null
var _thinking_dot_count: int = 0

# UI nodes
var _message_list: VBoxContainer
var _scroll_container: ScrollContainer
var _input_field: TextEdit
var _send_button: Button
var _cancel_button: Button
var _provider_option: OptionButton
var _model_option: OptionButton
var _status_label: Label

## Inject dependencies after construction. Separate from _ready() because
## _ready() fires before the caller has connected providers and settings.
func setup(provider_manager: ProviderManager, settings: AISettings, editor_interface: EditorInterface) -> void:
	_provider_manager = provider_manager
	_settings = settings
	_editor_interface = editor_interface

	_provider_manager.response_token.connect(_on_token)
	_provider_manager.response_completed.connect(_on_completed)
	_provider_manager.response_error.connect(_on_error)

	_refresh_provider_ui()

func _ready() -> void:
	_build_ui()
	_refresh_provider_ui()
	_load_history()

func _build_ui() -> void:
	# UI built in code (no .tscn) for simpler plugin distribution — no scene loader needed.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)

	# --- Toolbar (vertical layout for narrow right dock) ---
	var toolbar := VBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 2)
	vbox.add_child(toolbar)

	# Row 1: Settings + Clear + Status (above dropdowns)
	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 4)
	toolbar.add_child(action_row)

	_status_label = Label.new()
	_status_label.text = ""
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	action_row.add_child(_status_label)

	var settings_btn := Button.new()
	settings_btn.text = "Settings"
	settings_btn.pressed.connect(_on_settings_pressed)
	action_row.add_child(settings_btn)

	var clear_btn := Button.new()
	clear_btn.text = "Clear"
	clear_btn.pressed.connect(_on_clear_pressed)
	action_row.add_child(clear_btn)

	# Row 2: Provider
	var provider_row := HBoxContainer.new()
	provider_row.add_theme_constant_override("separation", 4)
	toolbar.add_child(provider_row)

	var provider_lbl := Label.new()
	provider_lbl.text = "Provider:"
	provider_lbl.custom_minimum_size.x = 70
	provider_row.add_child(provider_lbl)

	_provider_option = OptionButton.new()
	_provider_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_provider_option.add_item("Anthropic", 0)
	_provider_option.add_item("OpenAI", 1)
	_provider_option.add_item("OpenRouter", 2)
	_provider_option.item_selected.connect(_on_provider_changed)
	provider_row.add_child(_provider_option)

	# Row 3: Model
	var model_row := HBoxContainer.new()
	model_row.add_theme_constant_override("separation", 4)
	toolbar.add_child(model_row)

	var model_lbl := Label.new()
	model_lbl.text = "Model:"
	model_lbl.custom_minimum_size.x = 70
	model_row.add_child(model_lbl)

	_model_option = OptionButton.new()
	_model_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_model_option.item_selected.connect(_on_model_changed)
	model_row.add_child(_model_option)

	vbox.add_child(HSeparator.new())

	# --- Message history ---
	_scroll_container = ScrollContainer.new()
	_scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(_scroll_container)

	_message_list = VBoxContainer.new()
	_message_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_message_list.add_theme_constant_override("separation", 12)
	_scroll_container.add_child(_message_list)

	_welcome_label = Label.new()
	_welcome_label.text = "GodotAI is ready. Open a script and ask a question.\n\nTip: Ctrl/Cmd+Enter to send."
	_welcome_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	_welcome_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_welcome_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_welcome_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_message_list.add_child(_welcome_label)

	vbox.add_child(HSeparator.new())

	# --- Input area ---
	var input_row := HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 6)
	vbox.add_child(input_row)

	_input_field = TextEdit.new()
	_input_field.placeholder_text = "Ask GodotAI a question... (Ctrl/Cmd+Enter to send)"
	_input_field.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_input_field.custom_minimum_size.y = 36
	_input_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input_field.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_input_field.gui_input.connect(_on_input_gui_input)
	_input_field.text_changed.connect(_on_input_text_changed)
	input_row.add_child(_input_field)

	var btn_col := VBoxContainer.new()
	input_row.add_child(btn_col)

	_send_button = Button.new()
	_send_button.text = "Send"
	_send_button.custom_minimum_size = Vector2(70, 0)
	_send_button.pressed.connect(_on_send_pressed)
	btn_col.add_child(_send_button)

	_cancel_button = Button.new()
	_cancel_button.text = "Cancel"
	_cancel_button.custom_minimum_size = Vector2(70, 0)
	_cancel_button.visible = false
	_cancel_button.pressed.connect(_on_cancel_pressed)
	btn_col.add_child(_cancel_button)

## Save history and disconnect provider signals to avoid dangling references.
## Also frees the settings dialog since it's not part of the scene tree hierarchy.
func _exit_tree() -> void:
	_save_history()
	_stop_thinking_indicator()
	if _provider_manager:
		if _provider_manager.response_token.is_connected(_on_token):
			_provider_manager.response_token.disconnect(_on_token)
		if _provider_manager.response_completed.is_connected(_on_completed):
			_provider_manager.response_completed.disconnect(_on_completed)
		if _provider_manager.response_error.is_connected(_on_error):
			_provider_manager.response_error.disconnect(_on_error)
	if _settings_dialog:
		_settings_dialog.queue_free()
		_settings_dialog = null

# --- Editor font size ---

func _get_editor_font_size() -> int:
	return _settings.font_size if _settings else 28

# --- Thinking indicator ---

func _start_thinking_indicator() -> void:
	_thinking_dot_count = 0
	_thinking_label = Label.new()
	_thinking_label.text = "Thinking"
	_thinking_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	_message_list.add_child(_thinking_label)

	if not _thinking_timer:
		_thinking_timer = Timer.new()
		_thinking_timer.wait_time = 0.4
		_thinking_timer.timeout.connect(_on_thinking_tick)
		add_child(_thinking_timer)
	_thinking_timer.start()
	_scroll_to_bottom()

func _stop_thinking_indicator() -> void:
	if _thinking_timer:
		_thinking_timer.stop()
	if _thinking_label and is_instance_valid(_thinking_label):
		_thinking_label.queue_free()
		_thinking_label = null

func _on_thinking_tick() -> void:
	_thinking_dot_count = (_thinking_dot_count + 1) % 4
	if _thinking_label and is_instance_valid(_thinking_label):
		_thinking_label.text = "Thinking" + ".".repeat(_thinking_dot_count)

# --- Message layout ---

func _add_message_to_list(display: MessageDisplay, role: MessageDisplay.Role) -> void:
	var wrapper := HBoxContainer.new()
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_message_list.add_child(wrapper)

	display.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.add_child(display)

# --- Input ---

func _on_input_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		var parsed := AISettings.parse_shortcut(_settings.shortcut_send_message if _settings else "Ctrl+Enter")
		if AISettings.matches_event(event as InputEventKey, parsed):
			_on_send_pressed()
			get_viewport().set_input_as_handled()

func _on_input_text_changed() -> void:
	var line_height := _input_field.get_line_height()
	var line_count := _input_field.get_line_count()
	var clamped := clampi(line_count, 2, 10)
	_input_field.custom_minimum_size.y = line_height * clamped

func _on_send_pressed() -> void:
	var text := _input_field.text.strip_edges()
	if text.is_empty() or _is_waiting:
		return
	_input_field.text = ""
	_input_field.custom_minimum_size.y = 36
	_send_message(text)

## Orchestrate sending a user message: display it, build context with GDScript hints
## (only on the first message to avoid redundant token cost), and forward to provider.
func _send_message(user_text: String) -> void:
	if not _provider_manager:
		return

	# Remove welcome label on first message
	if _welcome_label:
		_welcome_label.queue_free()
		_welcome_label = null

	# Display user message
	var user_display := MessageDisplay.create_user_message(user_text, _get_editor_font_size())
	_add_message_to_list(user_display, MessageDisplay.Role.USER)

	# Add to conversation history
	_messages.append({"role": "user", "content": user_text})

	# Show animated thinking indicator in message area
	_start_thinking_indicator()

	_set_waiting(true)
	_scroll_to_bottom()

	# Build context and send — include GDScript hints only on the first message
	var system_prompt := ""
	if _editor_interface:
		system_prompt = ContextBuilder.build_system_prompt(_editor_interface, not _hints_sent)

	_provider_manager.send_message(_messages.duplicate(), system_prompt)

## Lazily create the assistant placeholder on the first token so that empty
## responses (e.g. immediate errors) leave no orphan bubble in the UI.
func _on_token(token: String) -> void:
	if _current_assistant_display == null:
		# First token: stop thinking indicator and create assistant placeholder
		_stop_thinking_indicator()
		_current_assistant_display = MessageDisplay.create_assistant_placeholder(_get_editor_font_size())
		_current_assistant_display.insert_code_requested.connect(_on_insert_code)
		_add_message_to_list(_current_assistant_display, MessageDisplay.Role.ASSISTANT)
	_current_assistant_display.append_token(token)
	_scroll_to_bottom()

## Finalize streaming: re-render through MarkdownParser, append to history,
## persist to disk, and re-enable the input field.
func _on_completed(full_text: String) -> void:
	_stop_thinking_indicator()
	if _current_assistant_display:
		_current_assistant_display.finish_streaming()
	_messages.append({"role": "assistant", "content": full_text})
	_save_history()
	_current_assistant_display = null
	_hints_sent = true
	_set_waiting(false)
	_scroll_to_bottom()

## Handle provider errors. Rolls back the user message from history if the
## provider never responded, so the next send starts from a clean state.
func _on_error(error: String) -> void:
	_stop_thinking_indicator()
	if _current_assistant_display:
		_current_assistant_display.append_token("\n\n[Error: %s]" % error)
		_current_assistant_display.finish_streaming()
		_current_assistant_display = null
	else:
		# No tokens received yet — create a display for the error
		var error_display := MessageDisplay.create_assistant_placeholder(_get_editor_font_size())
		error_display.append_token("[Error: %s]" % error)
		error_display.finish_streaming()
		_add_message_to_list(error_display, MessageDisplay.Role.ASSISTANT)
	# Remove the pending user message so the next send starts from a clean state
	if not _messages.is_empty() and _messages.back().get("role") == "user":
		_messages.pop_back()
	_set_waiting(false)
	_set_status("Error")

## Stop the active stream and roll back any partial state: finishes the
## assistant bubble (if any) and removes the unanswered user message.
func _on_cancel_pressed() -> void:
	_stop_thinking_indicator()
	if _provider_manager:
		_provider_manager.cancel()
	if _current_assistant_display:
		_current_assistant_display.finish_streaming()
	_current_assistant_display = null
	# Remove the pending user message so the next send starts from a clean state
	if not _messages.is_empty() and _messages.back().get("role") == "user":
		_messages.pop_back()
	_set_waiting(false)

func _on_clear_pressed() -> void:
	_stop_thinking_indicator()
	_messages.clear()
	_current_assistant_display = null
	for child in _message_list.get_children():
		child.queue_free()
	_welcome_label = null  # freed by the loop above if still present
	_hints_sent = false
	_set_status("")
	_delete_history()

func _on_settings_pressed() -> void:
	if not _settings_dialog:
		_settings_dialog = AISettingsDialog.new()
		add_child(_settings_dialog)
		_settings_dialog.settings_saved.connect(_on_settings_saved)
		_settings_dialog.setup_provider_manager(_provider_manager)
	_settings_dialog.open_with_settings(_settings)

## Apply new settings and propagate font size to all existing message widgets,
## not just future ones, so the user sees the change immediately.
func _on_settings_saved(settings: AISettings) -> void:
	_settings = settings
	if _provider_manager:
		_provider_manager.apply_settings(settings)
	_refresh_provider_ui()
	settings_saved.emit(settings)
	var font_size := _get_editor_font_size()
	for wrapper in _message_list.get_children():
		for child in wrapper.get_children():
			if child is MessageDisplay:
				child.update_font_size(font_size)

func _on_provider_changed(index: int) -> void:
	if _provider_manager:
		_provider_manager.set_active_provider(ProviderManager.PROVIDER_KEYS[index])
	_refresh_model_dropdown()

func _on_model_changed(index: int) -> void:
	if not _provider_manager:
		return
	var provider := _provider_manager.get_active_provider()
	if provider:
		provider.model = _model_option.get_item_text(index)

func _on_insert_code(code: String) -> void:
	if _editor_interface:
		var success := ContextBuilder.insert_at_cursor(_editor_interface, code)
		if not success:
			_set_status("No script editor open — code copied to clipboard")
			DisplayServer.clipboard_set(code)

func _refresh_provider_ui() -> void:
	if not _provider_manager or not _provider_option:
		return
	var active := _provider_manager.get_active_provider_name()
	var idx := ProviderManager.PROVIDER_KEYS.find(active)
	_provider_option.selected = max(0, idx)
	_refresh_model_dropdown()

## Rebuild the model dropdown from the provider's known models. If the current
## model isn't in the list (e.g. a custom model), append it so it stays selected.
func _refresh_model_dropdown() -> void:
	if not _provider_manager or not _model_option:
		return
	var provider := _provider_manager.get_active_provider()
	if not provider:
		return
	_model_option.clear()
	for m in provider.get_all_models():
		_model_option.add_item(m)
	# Select the current model; append it if not in the list
	var found := false
	for i in _model_option.item_count:
		if _model_option.get_item_text(i) == provider.model:
			_model_option.selected = i
			found = true
			break
	if not found and not provider.model.is_empty():
		_model_option.add_item(provider.model)
		_model_option.selected = _model_option.item_count - 1

func _set_waiting(waiting: bool) -> void:
	_is_waiting = waiting
	_send_button.visible = not waiting
	_cancel_button.visible = waiting
	_input_field.editable = not waiting
	if not waiting:
		_set_status("")

func _set_status(text: String) -> void:
	if _status_label:
		_status_label.text = text

# --- Chat history persistence ---

## Build a filesystem-safe path for this project's chat history.
## Sanitizes the project name because it may contain characters invalid in filenames.
func _get_history_path() -> String:
	var project_name: String = ProjectSettings.get_setting("application/config/name", "unnamed")
	# Sanitize: keep only alphanumeric, hyphens, and underscores
	var safe_name := ""
	for ch in project_name:
		if ch.is_valid_identifier() or ch == "-":
			safe_name += ch
		else:
			safe_name += "_"
	if safe_name.is_empty():
		safe_name = "unnamed"
	return HISTORY_DIR + "/" + safe_name + ".json"

## Persist conversation to disk. Called after each completed response and
## on _exit_tree() so history survives editor restarts.
func _save_history() -> void:
	if _messages.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(HISTORY_DIR)
	var file := FileAccess.open(_get_history_path(), FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(_messages, "\t"))

## Restore conversation from disk on startup. Called from _ready() (not setup())
## so _message_list already exists from _build_ui().
func _load_history() -> void:
	var path := _get_history_path()
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return
	var parsed := JSON.parse_string(file.get_as_text())
	if not parsed is Array:
		return
	_messages = parsed
	_restore_messages_ui()

## Rebuild the UI from saved history. Unlike the live streaming path, this
## renders complete messages directly through MarkdownParser (no token-by-token).
func _restore_messages_ui() -> void:
	if _messages.is_empty():
		return
	# Remove welcome label
	if _welcome_label:
		_welcome_label.queue_free()
		_welcome_label = null
	var font_size := _get_editor_font_size()
	for entry in _messages:
		var role: String = entry.get("role", "")
		var content: String = entry.get("content", "")
		if role == "user":
			var display := MessageDisplay.create_user_message(content, font_size)
			_add_message_to_list(display, MessageDisplay.Role.USER)
		elif role == "assistant":
			var display := MessageDisplay.create_assistant_message(content, font_size)
			display.insert_code_requested.connect(_on_insert_code)
			_add_message_to_list(display, MessageDisplay.Role.ASSISTANT)
	_hints_sent = true

func _delete_history() -> void:
	var path := _get_history_path()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

# --- Send selected code ---

## Paste editor selection into the input field wrapped in a GDScript code fence.
## The user can then add their question before sending.
func send_selected_code(code: String) -> void:
	if _is_waiting or code.is_empty():
		return
	_input_field.text = "Selected code:\n```gdscript\n%s\n```\n\n" % code
	_on_input_text_changed()
	_input_field.set_caret_line(_input_field.get_line_count() - 1)
	_input_field.set_caret_column(0)
	_input_field.grab_focus()

## Scroll to the bottom after one frame — layout hasn't been computed yet
## at call time, so we wait for the engine to resolve sizes.
func _scroll_to_bottom() -> void:
	await get_tree().process_frame
	if _scroll_container:
		_scroll_container.scroll_vertical = _scroll_container.get_v_scroll_bar().max_value
