extends Node

## Runs inside the *running game*, not the editor.
##
## The editor cannot read the game's pixels: Godot runs the game as a separate
## OS process, and since 4.4 it embeds that process's window rather than
## rendering it into a SubViewport, so there is no texture on the editor side.
## The only way to screenshot the game is to capture it from within the game
## and send the image back over the debugger connection.
##
## The plugin registers this script as an autoload so it is present in the game
## process. Godot routes debugger messages prefixed with a registered capture
## name to that capture; unprefixed core messages go to the built-in debugger
## instead, which is why the "claude_bridge" prefix matters here.

const CAPTURE_PREFIX := "claude_bridge"
const REPLY_MESSAGE := "claude_bridge:screenshot"

func _ready() -> void:
	# Only meaningful when launched from the editor with a debugger attached.
	# In an exported build this leaves no trace beyond an idle node.
	if not EngineDebugger.is_active():
		return
	EngineDebugger.register_message_capture(CAPTURE_PREFIX, _on_debugger_message)

func _exit_tree() -> void:
	if EngineDebugger.is_active() and EngineDebugger.has_capture(CAPTURE_PREFIX):
		EngineDebugger.unregister_message_capture(CAPTURE_PREFIX)

# Returning true marks the message handled. The prefix is stripped before it
# reaches us, so "claude_bridge:capture_request" arrives as "capture_request".
func _on_debugger_message(message: String, _data: Array) -> bool:
	if message == "capture_request":
		# Deferred so the reply is not built inside the debugger's own poll.
		_capture_and_send.call_deferred()
		return true
	return false

func _capture_and_send() -> void:
	# A viewport texture is only readable after the frame has been drawn.
	await RenderingServer.frame_post_draw

	var viewport := get_viewport()
	if viewport == null:
		_send({"error": "The running game has no viewport to capture"})
		return
	var texture := viewport.get_texture()
	if texture == null:
		_send({"error": "The game viewport has no texture yet — try again in a moment"})
		return
	var image := texture.get_image()
	if image == null or image.is_empty():
		_send({"error": "The game viewport texture was empty"})
		return

	_send({
		"success": true,
		"format": "png",
		"data": Marshalls.raw_to_base64(image.save_png_to_buffer()),
		"width": image.get_width(),
		"height": image.get_height(),
	})

func _send(payload: Dictionary) -> void:
	EngineDebugger.send_message(REPLY_MESSAGE, [payload])
