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
var _font_size: int = 28

# For streaming: the current trailing RichTextLabel being updated
var _streaming_label: RichTextLabel = null
var _streaming_text: String = ""

func _ready() -> void:
	add_theme_constant_override("separation", 4)

## Factory: create and populate a styled user message bubble.
static func create_user_message(text: String, font_size: int = 28) -> MessageDisplay:
	var msg := MessageDisplay.new()
	msg._role = Role.USER
	msg._font_size = font_size
	msg._build_user_message(text)
	return msg

## Factory: create an empty assistant bubble for streaming. Tokens will be
## appended via append_token(); call finish_streaming() when done.
static func create_assistant_placeholder(font_size: int = 28) -> MessageDisplay:
	var msg := MessageDisplay.new()
	msg._role = Role.ASSISTANT
	msg._font_size = font_size
	msg._is_streaming = true
	msg._streaming_text = ""
	msg._streaming_label = msg._make_rich_label()
	msg.add_child(msg._streaming_label)
	return msg

## Factory: render a completed assistant message from saved history.
## Bypasses the streaming path — goes straight through MarkdownParser.
static func create_assistant_message(text: String, font_size: int = 28) -> MessageDisplay:
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

	# Re-render with full parse (extracts code blocks)
	if _streaming_label and is_instance_valid(_streaming_label):
		_streaming_label.queue_free()
		_streaming_label = null

	_render_assistant_message(_full_text)

func _build_user_message(text: String) -> void:
	var header := _make_role_header("You")
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
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
	add_child(panel)

	var label := _make_rich_label()
	label.text = _escape_bbcode(text)
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
			block.set_code(segment.content, segment.language)
			block.insert_requested.connect(insert_code_requested.emit)
			add_child(block)
		else:
			if not segment.content.strip_edges().is_empty():
				var label := _make_rich_label()
				label.text = segment.content
				add_child(label)

func _make_role_header(name: String) -> Label:
	var lbl := Label.new()
	lbl.text = name
	match _role:
		Role.USER:
			lbl.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))
		Role.ASSISTANT:
			lbl.add_theme_color_override("font_color", Color(0.5, 1.0, 0.7))
	lbl.add_theme_font_size_override("font_size", _font_size)
	return lbl

func _make_rich_label() -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
		if child is Label:
			child.add_theme_font_size_override("font_size", new_size)
		elif child is RichTextLabel:
			child.add_theme_font_size_override("normal_font_size", new_size)
		elif child is PanelContainer:
			_apply_font_size_to_children(child, new_size)

## Escape BBCode brackets so user/assistant text can't inject markup
## (e.g. "[color=red]") into the RichTextLabel.
func _escape_bbcode(text: String) -> String:
	return text.replace("[", "[lb]")
