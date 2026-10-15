@tool
class_name CodeBlock
extends PanelContainer

## Displays a code block with syntax highlighting, Copy and Insert at Cursor buttons.
## Used inside MessageDisplay to render fenced code blocks from AI responses.

signal insert_requested(code: String)

var _code: String = ""
var _language: String = ""
var _font_size: int = 18
var _code_label: TextEdit
var _lang_label: Label
var _copy_btn: Button
var _insert_btn: Button

func _ready() -> void:
	_build_ui()

## Store the code text and apply syntax highlighting for the given language.
## Safe to call before or after _build_ui(); highlighter is applied once the
## TextEdit exists (either here or at the end of _build_ui).
func set_code(code: String, language: String = "") -> void:
	_code = code
	_language = language
	if _code_label:
		_code_label.text = code
		_apply_highlighter(language)
	if _lang_label:
		_lang_label.text = language if not language.is_empty() else "code"

func set_font_size(font_size: int) -> void:
	_font_size = font_size
	_apply_font_size()

func _build_ui() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clip_contents = true
	custom_minimum_size.x = 0

	# Outer panel style
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.13, 0.13)
	style.border_color = Color(0.3, 0.3, 0.3)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(0)
	add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	header_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(header_panel)

	# Flow so Copy/Insert wrap under the lang label on narrow docks
	var header := HFlowContainer.new()
	header.add_theme_constant_override("h_separation", 4)
	header.add_theme_constant_override("v_separation", 2)
	header_panel.add_child(header)

	_lang_label = Label.new()
	_lang_label.text = _language if not _language.is_empty() else "code"
	_lang_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	_lang_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lang_label.clip_text = true
	_lang_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	header.add_child(_lang_label)

	_copy_btn = Button.new()
	_copy_btn.text = "Copy"
	_copy_btn.flat = true
	_copy_btn.pressed.connect(_on_copy)
	header.add_child(_copy_btn)

	_insert_btn = Button.new()
	_insert_btn.text = "Insert"
	_insert_btn.tooltip_text = "Insert at Cursor"
	_insert_btn.flat = true
	_insert_btn.pressed.connect(_on_insert)
	header.add_child(_insert_btn)

	# Wrap so long lines don't force the dock wider than ~190px
	_code_label = TextEdit.new()
	_code_label.text = _code
	_code_label.editable = false
	_code_label.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_code_label.scroll_fit_content_height = true
	_code_label.custom_minimum_size = Vector2(0, 40)
	_code_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code_label.add_theme_color_override("background_color", Color(0.13, 0.13, 0.13))
	_code_label.add_theme_constant_override("line_spacing", 2)
	vbox.add_child(_code_label)

	_apply_highlighter(_language)
	_apply_font_size()

## Apply syntax highlighting. Only GDScript is fully supported; unknown
## languages fall back to no highlighting (plain text).
func _apply_highlighter(language: String) -> void:
	if _code_label == null:
		return
	if language.to_lower() in ["gdscript", "gd"]:
		var h := CodeHighlighter.new()
		_setup_gdscript_highlighter(h)
		_code_label.syntax_highlighter = h
	else:
		_code_label.syntax_highlighter = null

func _setup_gdscript_highlighter(h: CodeHighlighter) -> void:
	h.number_color = Color(0.70, 0.80, 0.55)
	h.symbol_color = Color(0.75, 0.75, 0.75)
	h.function_color = Color(0.60, 0.85, 0.70)
	h.member_variable_color = Color(0.80, 0.70, 0.60)

	var keyword_color := Color(0.56, 0.75, 0.98)
	for kw in ["func", "var", "const", "if", "elif", "else", "for", "while", "return",
			"class", "class_name", "extends", "signal", "await", "pass", "break", "continue",
			"true", "false", "null", "self", "super", "static", "enum", "match",
			"not", "and", "or", "in", "is", "as", "preload", "load", "assert",
			"breakpoint", "yield", "master", "puppet", "remote", "remotesync",
			"sync", "master_sync", "puppet_sync", "void", "PI", "TAU", "INF", "NAN"]:
		h.add_keyword_color(kw, keyword_color)

	var type_color := Color(0.55, 0.90, 0.90)
	for t in ["int", "float", "bool", "String", "StringName", "NodePath", "Array",
			"Dictionary", "PackedStringArray", "PackedByteArray", "PackedInt32Array",
			"PackedFloat32Array", "PackedVector2Array", "PackedVector3Array",
			"PackedColorArray", "Vector2", "Vector2i", "Vector3", "Vector3i",
			"Vector4", "Vector4i", "Color", "Rect2", "Rect2i", "Transform2D",
			"Transform3D", "Basis", "Quaternion", "AABB", "Plane", "Projection",
			"RID", "Callable", "Signal", "Variant", "Object", "Node", "Node2D",
			"Node3D", "Control", "Resource", "RefCounted"]:
		h.add_keyword_color(t, type_color)

	var annotation_color := Color(0.85, 0.65, 0.30)
	for ann in ["@tool", "@export", "@export_range", "@export_enum", "@export_file",
			"@export_dir", "@export_multiline", "@export_group", "@export_subgroup",
			"@export_category", "@onready", "@warning_ignore", "@icon", "@static_unload",
			"@rpc", "@abstractmethod"]:
		h.add_keyword_color(ann, annotation_color)

	# Comments and strings (regions). Triple-quote before single-quote so
	# multiline strings are not split into three one-character regions.
	h.add_color_region("#", "", Color(0.50, 0.55, 0.50), true)
	h.add_color_region('"""', '"""', Color(0.90, 0.70, 0.55))
	h.add_color_region("\"", "\"", Color(0.90, 0.70, 0.55))
	h.add_color_region("'", "'", Color(0.90, 0.70, 0.55))

func _apply_font_size() -> void:
	if _lang_label:
		_lang_label.add_theme_font_size_override("font_size", _font_size)
	if _copy_btn:
		_copy_btn.add_theme_font_size_override("font_size", _font_size)
	if _insert_btn:
		_insert_btn.add_theme_font_size_override("font_size", _font_size)
	if _code_label:
		_code_label.add_theme_font_size_override("font_size", _font_size)

func _on_copy() -> void:
	DisplayServer.clipboard_set(_code)

func _on_insert() -> void:
	insert_requested.emit(_code)
