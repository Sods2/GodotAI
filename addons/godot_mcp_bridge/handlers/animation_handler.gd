@tool
class_name AnimationHandler
extends RefCounted

func list_animations(editor_interface: EditorInterface, params: Dictionary) -> Dictionary:
	var root = editor_interface.get_edited_scene_root()
	if not root:
		return {"error": "No scene open"}
	var node_path: String = params.get("path", "")
	var node: Node = root.get_node_or_null(node_path)
	if not node:
		return {"error": "Node not found: " + node_path}
	if not node is AnimationPlayer:
		return {"error": "Node is not an AnimationPlayer: " + node_path}
	var player: AnimationPlayer = node as AnimationPlayer
	var animations: Array = []
	for anim_name in player.get_animation_list():
		var anim: Animation = player.get_animation(anim_name)
		animations.append({
			"name": anim_name,
			"length": anim.length,
			"track_count": anim.get_track_count()
		})
	return {"node": node_path, "animations": animations}

func get_animation(editor_interface: EditorInterface, params: Dictionary) -> Dictionary:
	var root = editor_interface.get_edited_scene_root()
	if not root:
		return {"error": "No scene open"}
	var node_path: String = params.get("path", "")
	var anim_name: String = params.get("animation_name", "")
	var node: Node = root.get_node_or_null(node_path)
	if not node:
		return {"error": "Node not found: " + node_path}
	if not node is AnimationPlayer:
		return {"error": "Node is not an AnimationPlayer: " + node_path}
	var player: AnimationPlayer = node as AnimationPlayer
	if not player.has_animation(anim_name):
		return {"error": "Animation not found: " + anim_name}
	var anim: Animation = player.get_animation(anim_name)
	var tracks: Array = []
	for i in range(anim.get_track_count()):
		var track_type = anim.track_get_type(i)
		var keys: Array = []
		for k in range(anim.track_get_key_count(i)):
			keys.append({
				"time": anim.track_get_key_time(i, k),
				"value": str(anim.track_get_key_value(i, k))
			})
		tracks.append({
			"index": i,
			"type": str(track_type),
			"path": str(anim.track_get_path(i)),
			"keys": keys
		})
	return {
		"name": anim_name,
		"length": anim.length,
		"loop_mode": anim.loop_mode,
		"tracks": tracks
	}

func create_animation(editor_interface: EditorInterface, params: Dictionary) -> Dictionary:
	var root = editor_interface.get_edited_scene_root()
	if not root:
		return {"error": "No scene open"}
	var node_path: String = params.get("path", "")
	var anim_name: String = params.get("animation_name", "")
	var length: float = params.get("length", 1.0)
	var loop_mode: int = params.get("loop_mode", 0)
	var node: Node = root.get_node_or_null(node_path)
	if not node:
		return {"error": "Node not found: " + node_path}
	if not node is AnimationPlayer:
		return {"error": "Node is not an AnimationPlayer: " + node_path}
	var player: AnimationPlayer = node as AnimationPlayer
	var anim = Animation.new()
	anim.length = length
	anim.loop_mode = loop_mode
	var tracks_data: Array = params.get("tracks", [])
	for track_data in tracks_data:
		var track_idx: int = anim.add_track(Animation.TYPE_VALUE)
		anim.track_set_path(track_idx, track_data.get("path", ""))
		for key_data in track_data.get("keys", []):
			anim.track_insert_key(track_idx, key_data.get("time", 0.0), key_data.get("value", null))
	var lib: AnimationLibrary
	if player.has_animation_library(""):
		lib = player.get_animation_library("")
	else:
		lib = AnimationLibrary.new()
		player.add_animation_library("", lib)
	var undo_redo = editor_interface.get_editor_undo_redo()
	undo_redo.create_action("Create Animation")
	undo_redo.add_do_method(lib, "add_animation", anim_name, anim)
	undo_redo.add_undo_method(lib, "remove_animation", anim_name)
	undo_redo.commit_action()
	return {"success": true, "animation_name": anim_name, "track_count": tracks_data.size()}
