@tool
class_name MarkdownParser
extends RefCounted

## Converts a subset of Markdown to Godot BBCode for use in RichTextLabel.
## Supports: headers, bold, italic, inline code, fenced code blocks, lists, blockquotes.
##
## Code blocks are extracted separately so the caller can render them as widgets.

## Compiled once and reused across all calls to _parse_line().
static var _list_regex: RegEx

## Represents a parsed segment: either rich text (BBCode) or a code block.
class Segment:
	var is_code_block: bool = false
	var content: String = ""   # BBCode text or raw code
	var language: String = ""  # code block language hint

## Parse markdown text into a list of Segments.
static func parse(markdown: String) -> Array[Segment]:
	var segments: Array[Segment] = []
	var lines := markdown.split("\n")
	var i := 0
	var text_buffer := ""

	while i < lines.size():
		var line := lines[i]

		# Fenced code block
		if line.begins_with("```"):
			# Flush pending text
			if not text_buffer.is_empty():
				var seg := Segment.new()
				seg.is_code_block = false
				seg.content = _parse_inline(text_buffer.strip_edges())
				segments.append(seg)
				text_buffer = ""

			var lang := line.substr(3).strip_edges()
			i += 1
			var code_lines: PackedStringArray = []
			while i < lines.size() and not lines[i].begins_with("```"):
				code_lines.append(lines[i])
				i += 1
			# skip closing ```
			if i < lines.size():
				i += 1

			var seg := Segment.new()
			seg.is_code_block = true
			seg.language = lang
			seg.content = "\n".join(code_lines)
			segments.append(seg)
			continue

		text_buffer += line + "\n"
		i += 1

	if not text_buffer.is_empty():
		var seg := Segment.new()
		seg.is_code_block = false
		seg.content = _parse_inline(text_buffer.strip_edges())
		segments.append(seg)

	return segments

## Convert markdown to BBCode string (no code block extraction).
## Useful for streaming partial text.
static func to_bbcode(markdown: String) -> String:
	var lines := markdown.split("\n")
	var result := ""
	var in_code_block := false
	var code_buffer := ""

	for line in lines:
		if line.begins_with("```"):
			if in_code_block:
				result += "[code]%s[/code]\n" % code_buffer.strip_edges().replace("[", "[lb]")
				code_buffer = ""
				in_code_block = false
			else:
				in_code_block = true
			continue

		if in_code_block:
			code_buffer += line + "\n"
			continue

		result += _parse_line(line) + "\n"

	if in_code_block and not code_buffer.is_empty():
		result += "[code]%s[/code]\n" % code_buffer.strip_edges().replace("[", "[lb]")

	return result.strip_edges()

## Convert a single markdown line to BBCode.
## Handles block-level elements: headings (#/##/###), blockquotes (>),
## unordered/ordered lists, and horizontal rules (---/***/___).
## Anything else falls through to inline parsing.
static func _parse_line(line: String) -> String:
	# Headers
	if line.begins_with("### "):
		return "[b][color=#aaaaff]%s[/color][/b]" % _parse_inline(line.substr(4))
	if line.begins_with("## "):
		return "[b][color=#aaaaff][font_size=16]%s[/font_size][/color][/b]" % _parse_inline(line.substr(3))
	if line.begins_with("# "):
		return "[b][color=#aaaaff][font_size=18]%s[/font_size][/color][/b]" % _parse_inline(line.substr(2))

	# Blockquote
	if line.begins_with("> "):
		return "[indent][color=#888888]%s[/color][/indent]" % _parse_inline(line.substr(2))

	# Unordered list
	if line.begins_with("- ") or line.begins_with("* "):
		return "  • " + _parse_inline(line.substr(2))

	# Ordered list (simple: starts with digit + ". ")
	if not _list_regex:
		_list_regex = RegEx.new()
		_list_regex.compile("^(\\d+)\\. (.+)$")
	var m := _list_regex.search(line)
	if m:
		return "  %s. %s" % [m.get_string(1), _parse_inline(m.get_string(2))]

	# Horizontal rule
	if line == "---" or line == "***" or line == "___":
		return "[color=#444444]────────────────────────[/color]"

	return _parse_inline(line)

## Parse inline markdown formatting character-by-character.
## Scans for ** (bold), * (italic), ` (inline code), and *** (bold+italic).
## Escapes literal "[" to "[lb]" first to prevent BBCode injection from
## user-provided or LLM-generated text.
static func _parse_inline(text: String) -> String:
	# Process inline markdown: bold, italic, inline code
	var result := ""
	var i := 0
	var s := text

	while i < s.length():
		# Inline code: `...`
		if s[i] == "`":
			var end := s.find("`", i + 1)
			if end != -1:
				var code := s.substr(i + 1, end - i - 1)
				result += "[code]%s[/code]" % code.replace("[", "[lb]")
				i = end + 1
				continue

		# Bold+Italic: ***...***
		if s.substr(i, 3) == "***":
			var end := s.find("***", i + 3)
			if end != -1:
				result += "[b][i]%s[/i][/b]" % s.substr(i + 3, end - i - 3)
				i = end + 3
				continue

		# Bold: **...**
		if s.substr(i, 2) == "**":
			var end := s.find("**", i + 2)
			if end != -1:
				result += "[b]%s[/b]" % s.substr(i + 2, end - i - 2)
				i = end + 2
				continue

		# Italic: *...*
		if s[i] == "*":
			var end := s.find("*", i + 1)
			if end != -1:
				result += "[i]%s[/i]" % s.substr(i + 1, end - i - 1)
				i = end + 1
				continue

		# Fallthrough: plain character — escape [ to prevent BBCode injection.
		var ch := s[i]
		result += "[lb]" if ch == "[" else ch
		i += 1

	return result
