@tool
class_name MessageDisplay
extends VBoxContainer

## Renders a single chat message (user or assistant).
## Streaming lifecycle: create_assistant_placeholder() creates an empty bubble,
## append_token() adds raw text as it arrives, finish_streaming() re-renders
## the accumulated text through MarkdownParser for proper formatting.

signal insert_code_requested(code: String)

enum Role { USER, ASSISTANT }

var _role: Role = Role.USER
var _full_text: String = ""
var _is_streaming: bool = false
var _font_size: int = 18

# For streaming: the current trailing RichTextLabel being updated
var _streaming_label: RichTextLabel = null
var _streaming_text: String = ""

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Do not clip — that cut user bubbles mid-word after the narrow-dock pass.
	clip_contents = false
	custom_minimum_size.x = 0
	add_theme_constant_override("separation", 4)

## Factory: create and populate a styled user message bubble.
static func create_user_message(text: String, font_size: int = 18) -> MessageDisplay:
	var msg := MessageDisplay.new()
	msg._role = Role.USER
	msg._font_size = font_size
	msg._build_user_message(text)
	return msg

## Factory: create an empty assistant bubble for streaming. Tokens will be
## appended via append_token(); call finish_streaming() when done.
static func create_assistant_placeholder(font_size: int = 18) -> MessageDisplay:
	var msg := MessageDisplay.new()
	msg._role = Role.ASSISTANT
	msg._font_size = font_size
	msg._is_streaming = true
	msg._streaming_text = ""
	var header := msg._make_role_header("Assistant")
	msg.add_child(header)
	msg._streaming_label = msg._make_rich_label()
	msg.add_child(msg._streaming_label)
	return msg

## Factory: render a completed assistant message from saved history.
## Bypasses the streaming path — goes straight through MarkdownParser.
static func create_assistant_message(text: String, font_size: int = 18) -> MessageDisplay:
	var msg := MessageDisplay.new()
	msg._role = Role.ASSISTANT
	msg._font_size = font_size
	msg._full_text = text
	msg._render_assistant_message(text)
	return msg

## Append a raw token during streaming. Uses to_bbcode() for lightweight
## formatting without full markdown parsing on every token.
func append_token(token: String) -> void:
	_streaming_text += token
	if _streaming_label:
		_streaming_label.text = MarkdownParser.to_bbcode(_streaming_text)

## End streaming: discard the raw BBCode label and re-render the full text
## through MarkdownParser.parse() which extracts code blocks into CodeBlock widgets.
func finish_streaming() -> void:
	_is_streaming = false
	_full_text = _streaming_text

	# Clear all children (header + streaming label) before full re-render.
	# Free immediately — queue_free left ghosts that survived a following Clear.
	while get_child_count() > 0:
		var child := get_child(0)
		remove_child(child)
		child.free()
	_streaming_label = null

	_render_assistant_message(_full_text)

func _build_user_message(text: String) -> void:
	_full_text = text
	var header := _make_role_header("You")
	add_child(header)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.145, 0.169, 0.204, 1.0)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.clip_contents = false
	add_child(panel)

	var label := _make_rich_label()
	label.text = _escape_bbcode(text)
	# Keep full user text visible; wrap instead of clipping.
	label.clip_contents = false
	panel.add_child(label)

## Walk the Segment array from MarkdownParser and create a RichTextLabel for
## prose segments or a CodeBlock widget for fenced code segments.
func _render_assistant_message(text: String) -> void:
	var header := _make_role_header("Assistant")
	add_child(header)

	var segments := MarkdownParser.parse(text)
	for segment in segments:
		if segment.is_code_block:
			var block := CodeBlock.new()
			block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			block.set_font_size(_font_size)
			block.set_code(segment.content, segment.language)
			block.insert_requested.connect(insert_code_requested.emit)
			add_child(block)
		else:
			if not segment.content.strip_edges().is_empty():
				var label := _make_rich_label()
				label.text = segment.content
				add_child(label)

func _make_role_header(name: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var lbl := Label.new()
	lbl.text = name
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	match _role:
		Role.USER:
			lbl.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		Role.ASSISTANT:
			lbl.add_theme_color_override("font_color", Color(0.5, 1.0, 0.7))
	lbl.add_theme_font_size_override("font_size", _font_size)
	row.add_child(lbl)

	var copy_btn := Button.new()
	copy_btn.text = "Copy"
	copy_btn.flat = true
	copy_btn.focus_mode = Control.FOCUS_NONE
	copy_btn.tooltip_text = "Copy message"
	copy_btn.add_theme_font_size_override("font_size", _font_size)
	copy_btn.pressed.connect(_on_copy_message)
	if _role == Role.USER:
		# Copy on the left, "You" right-aligned on the right
		row.add_child(copy_btn)
		row.move_child(copy_btn, 0)
	else:
		row.add_child(copy_btn)
	return row

func _on_copy_message() -> void:
	var text := _full_text
	if text.is_empty() and _is_streaming:
		text = _streaming_text
	if text.is_empty():
		return
	DisplayServer.clipboard_set(text)

func _make_rich_label() -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Default RichTextLabel is not selectable — only code blocks (TextEdit) were copyable.
	label.selection_enabled = true
	label.context_menu_enabled = true
	label.add_theme_font_size_override("normal_font_size", _font_size)
	label.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	return label

## Propagate font size to all existing child controls (labels, code blocks),
## not just future ones, so settings changes are visible immediately.
func update_font_size(new_size: int) -> void:
	_font_size = new_size
	_apply_font_size_to_children(self, new_size)
	if _streaming_label and is_instance_valid(_streaming_label):
		_streaming_label.add_theme_font_size_override("normal_font_size", new_size)

func _apply_font_size_to_children(node: Node, new_size: int) -> void:
	for child in node.get_children():
		if child is CodeBlock:
			child.set_font_size(new_size)
		elif child is Label:
			child.add_theme_font_size_override("font_size", new_size)
		elif child is RichTextLabel:
			child.add_theme_font_size_override("normal_font_size", new_size)
		elif child is TextEdit:
			child.add_theme_font_size_override("font_size", new_size)
		elif child is Button:
			child.add_theme_font_size_override("font_size", new_size)
		# Recurse into containers so nested code-block widgets are reached
		if child.get_child_count() > 0 and not (child is CodeBlock):
			_apply_font_size_to_children(child, new_size)

## Escape BBCode brackets so user/assistant text can't inject markup
## (e.g. "[color=red]") into the RichTextLabel.
func _escape_bbcode(text: String) -> String:
	return text.replace("[", "[lb]")
