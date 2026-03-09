@tool
class_name CodeBlock
extends PanelContainer

## Displays a code block with syntax highlighting, Copy and Insert at Cursor buttons.
## Used inside MessageDisplay to render fenced code blocks from AI responses.

signal insert_requested(code: String)

var _code: String = ""
var _language: String = ""
var _code_label: TextEdit
var _lang_label: Label

func _ready() -> void:
	_build_ui()

## Store the code text and apply syntax highlighting for the given language.
## Called after _build_ui() has created the TextEdit widget.
func set_code(code: String, language: String = "") -> void:
	_code = code
	_language = language
	if _code_label:
		_code_label.text = code
		_apply_highlighter(language)
	if _lang_label:
		_lang_label.text = language if not language.is_empty() else "code"

func _build_ui() -> void:
	# Outer panel style
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.13, 0.13)
	style.border_color = Color(0.3, 0.3, 0.3)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(0)
	add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	add_child(vbox)

	# Header: PanelContainer so the StyleBoxFlat is actually rendered (HBoxContainer has no "panel" slot).
	var header_panel := PanelContainer.new()
	var header_style := StyleBoxFlat.new()
	header_style.bg_color = Color(0.18, 0.18, 0.18)
	header_style.set_content_margin(SIDE_LEFT, 8)
	header_style.set_content_margin(SIDE_RIGHT, 8)
	header_style.set_content_margin(SIDE_TOP, 4)
	header_style.set_content_margin(SIDE_BOTTOM, 4)
	header_panel.add_theme_stylebox_override("panel", header_style)
	vbox.add_child(header_panel)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 4)
	header_panel.add_child(header)

	_lang_label = Label.new()
	_lang_label.text = _language if not _language.is_empty() else "code"
	_lang_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	_lang_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_lang_label)

	var copy_btn := Button.new()
	copy_btn.text = "Copy"
	copy_btn.flat = true
	copy_btn.pressed.connect(_on_copy)
	header.add_child(copy_btn)

	var insert_btn := Button.new()
	insert_btn.text = "Insert at Cursor"
	insert_btn.flat = true
	insert_btn.pressed.connect(_on_insert)
	header.add_child(insert_btn)

	# Code text area — highlighter applied later via set_code()
	_code_label = TextEdit.new()
	_code_label.text = _code
	_code_label.editable = false
	_code_label.wrap_mode = TextEdit.LINE_WRAPPING_NONE
	_code_label.scroll_fit_content_height = true
	_code_label.custom_minimum_size.y = 40
	_code_label.add_theme_color_override("background_color", Color(0.13, 0.13, 0.13))
	_code_label.add_theme_constant_override("line_spacing", 2)
	vbox.add_child(_code_label)

## Apply syntax highlighting. Only GDScript is fully supported; unknown
## languages fall back to no highlighting (plain text).
func _apply_highlighter(language: String) -> void:
	if language.to_lower() in ["gdscript", "gd"]:
		var h := CodeHighlighter.new()
		_setup_gdscript_highlighter(h)
		_code_label.syntax_highlighter = h
	else:
		_code_label.syntax_highlighter = null

func _setup_gdscript_highlighter(h: CodeHighlighter) -> void:
	var keyword_color := Color(0.56, 0.75, 0.98)
	for kw in ["func", "var", "const", "if", "elif", "else", "for", "while", "return",
			"class", "extends", "signal", "await", "pass", "break", "continue",
			"true", "false", "null", "self", "static", "enum", "match",
			"not", "and", "or", "in", "is", "as"]:
		h.add_keyword_color(kw, keyword_color)
	var annotation_color := Color(0.85, 0.65, 0.30)
	for ann in ["@tool", "@export", "@onready", "@static_unload"]:
		h.add_keyword_color(ann, annotation_color)

func _on_copy() -> void:
	DisplayServer.clipboard_set(_code)

func _on_insert() -> void:
	insert_requested.emit(_code)
