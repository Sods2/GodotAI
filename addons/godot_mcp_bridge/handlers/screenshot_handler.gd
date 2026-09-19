@tool
class_name ScreenshotHandler
extends RefCounted

func capture_viewport(editor_interface: EditorInterface) -> Dictionary:
	# Capture the editor's rendered viewport using its texture
	var base_control := editor_interface.get_base_control()
	if base_control == null:
		return {"error": "Could not get editor base control"}
	var viewport := base_control.get_viewport()
	if viewport == null:
		return {"error": "Could not get editor viewport"}
	var texture := viewport.get_texture()
	if texture == null:
		return {"error": "Viewport texture not ready — try again after a frame"}
	var image := texture.get_image()
	if image == null or image.is_empty():
		return {"error": "Could not capture viewport texture — rendering may not be ready"}
	var png_buffer := image.save_png_to_buffer()
	var base64_str := Marshalls.raw_to_base64(png_buffer)
	return {
		"success": true,
		"format": "png",
		"data": base64_str,
		"width": image.get_width(),
		"height": image.get_height()
	}


func capture_game(editor_interface: EditorInterface) -> Dictionary:
	if not editor_interface.is_playing_scene():
		return {"error": "No game is currently running — start a scene first with godot_run_scene"}

	# Godot runs the game as a separate OS process. Since 4.4 the editor can
	# embed that process's window (GameView / EmbeddedProcess), but embedding a
	# window is not the same as rendering into a SubViewport, so there is no
	# texture here to read. Only accept a SubViewport that could actually be
	# the game — the 2D and 3D workspaces each own one, and returning those
	# yields a picture of an editor viewport (or a 2x2 stub) presented as if it
	# were the game.
	var main_screen := editor_interface.get_editor_main_screen()
	if main_screen != null:
		var game_vp := _find_game_subviewport(main_screen)
		if game_vp != null:
			var texture := game_vp.get_texture()
			if texture != null:
				var image := texture.get_image()
				if image != null and not image.is_empty():
					var png_bytes := image.save_png_to_buffer()
					return {
						"success": true,
						"format": "png",
						"data": Marshalls.raw_to_base64(png_bytes),
						"width": image.get_width(),
						"height": image.get_height()
					}

	return {"error": "The running game cannot be captured directly — Godot runs it as a separate process, so the editor holds no texture for it. Use godot_take_screenshot instead: it captures the editor window, which includes the game when the Game tab is selected."}


# Find a SubViewport that plausibly belongs to the running game, ignoring the
# editor's own workspace viewports.
func _find_game_subviewport(node: Node) -> SubViewport:
	for child in node.get_children():
		if child is SubViewport:
			var viewport := child as SubViewport
			if not _is_editor_viewport(viewport) and viewport.size.x >= 64 and viewport.size.y >= 64:
				return viewport
		var result := _find_game_subviewport(child)
		if result != null:
			return result
	return null


# True when the viewport belongs to the 2D or 3D editing workspace.
func _is_editor_viewport(node: Node) -> bool:
	var ancestor: Node = node
	while ancestor != null:
		var cls: String = ancestor.get_class()
		if cls.begins_with("Node3DEditor") or cls.begins_with("CanvasItemEditor"):
			return true
		ancestor = ancestor.get_parent()
	return false
