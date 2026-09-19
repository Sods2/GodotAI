@tool
class_name SceneHandler
extends RefCounted

const _Coerce = preload("res://addons/godot_mcp_bridge/handlers/value_coerce.gd")

func get_tree(editor_interface: EditorInterface, params: Dictionary) -> Dictionary:
	var root := editor_interface.get_edited_scene_root()
	if root == null:
		return {"error": "No scene open"}
	var max_depth: int = params.get("max_depth", 10)
	var type_filter: String = params.get("type_filter", "")
	return {
		"scene_path": root.scene_file_path,
		"root": _describe_node(root, 0, max_depth, type_filter, root)
	}

func _describe_node(node: Node, depth: int, max_depth: int, type_filter: String = "", scene_root: Node = null) -> Dictionary:
	var node_path: String
	if scene_root == null or node == scene_root:
		node_path = "."
	else:
		node_path = str(scene_root.get_path_to(node))
	var result := {
		"name": node.name,
		"type": node.get_class(),
		"path": node_path,
		"children": []
	}
	if depth < max_depth:
		for child in node.get_children():
			var child_result := _describe_node(child, depth + 1, max_depth, type_filter, scene_root)
			if type_filter == "" or child.is_class(type_filter) or child_result["children"].size() > 0:
				result["children"].append(child_result)
	return result

func get_selected(editor_interface: EditorInterface) -> Dictionary:
	var root := editor_interface.get_edited_scene_root()
	var selection := editor_interface.get_selection()
	var selected := selection.get_selected_nodes()
	var nodes: Array[Dictionary] = []
	for node in selected:
		var node_path: String
		if root != null and node != root:
			node_path = str(root.get_path_to(node))
		else:
			node_path = "."
		nodes.append({
			"name": node.name,
			"type": node.get_class(),
			"path": node_path
		})
	return {"selected": nodes}

func add_node(editor_interface: EditorInterface, params: Dictionary) -> Dictionary:
	var root := editor_interface.get_edited_scene_root()
	if root == null:
		return {"error": "No scene open"}

	var node_type: String = params.get("type", "Node")
	var node_name: String = params.get("name", node_type)
	var parent_path: String = params.get("parent", ".")

	var parent: Node
	if parent_path == "." or parent_path == "":
		parent = root
	else:
		parent = root.get_node_or_null(parent_path)

	if parent == null:
		return {"error": "Parent node not found: " + parent_path}

	var new_node: Node
	if ClassDB.class_exists(node_type):
		new_node = ClassDB.instantiate(node_type)
	else:
		return {"error": "Unknown node type: " + node_type}

	new_node.name = node_name

	# Apply any initial properties. Values arrive as JSON, so coerce each to the
	# property's real Variant type (Vector2, Color, …) before assigning. The node
	# is not in the tree yet, so a direct set is fine and needs no undo entry.
	var applied_properties: Array = []
	var properties = params.get("properties", null)
	if properties is Dictionary:
		for key in properties:
			var target_type := typeof(new_node.get(key))
			for prop in new_node.get_property_list():
				if prop["name"] == key:
					target_type = int(prop["type"])
					break
			new_node.set(key, _Coerce.coerce(properties[key], target_type))
			applied_properties.append(key)

	var undo_redo := editor_interface.get_editor_undo_redo()
	undo_redo.create_action("Add Node: " + node_name)
	undo_redo.add_do_method(parent, "add_child", new_node)
	undo_redo.add_do_method(new_node, "set_owner", root)
	undo_redo.add_undo_method(parent, "remove_child", new_node)
	undo_redo.commit_action()

	var rel_path: String = str(root.get_path_to(new_node))
	return {"success": true, "path": rel_path, "properties_applied": applied_properties}

func remove_node(editor_interface: EditorInterface, params: Dictionary) -> Dictionary:
	var root := editor_interface.get_edited_scene_root()
	if root == null:
		return {"error": "No scene open"}

	var node_path: String = params.get("path", "")
	var node := root.get_node_or_null(node_path)
	if node == null:
		return {"error": "Node not found: " + node_path}

	var parent := node.get_parent()
	var undo_redo := editor_interface.get_editor_undo_redo()
	undo_redo.create_action("Remove Node: " + node.name)
	undo_redo.add_do_method(parent, "remove_child", node)
	undo_redo.add_undo_method(parent, "add_child", node)
	undo_redo.add_undo_method(node, "set_owner", root)
	undo_redo.commit_action()

	return {"success": true}

func reparent_node(editor_interface: EditorInterface, params: Dictionary) -> Dictionary:
	var root := editor_interface.get_edited_scene_root()
	if root == null:
		return {"error": "No scene open"}

	var node_path: String = params.get("path", "")
	var new_parent_path: String = params.get("new_parent", ".")

	var node := root.get_node_or_null(node_path)
	if node == null:
		return {"error": "Node not found: " + node_path}

	var new_parent: Node
	if new_parent_path == "." or new_parent_path == "":
		new_parent = root
	else:
		new_parent = root.get_node_or_null(new_parent_path)

	if new_parent == null:
		return {"error": "New parent not found: " + new_parent_path}

	node.reparent(new_parent)
	var rel_path: String = str(root.get_path_to(node))
	return {"success": true, "new_path": rel_path}

func open_scene(editor_interface: EditorInterface, params: Dictionary) -> Dictionary:
	var scene_path: String = params.get("path", "")
	if scene_path == "":
		return {"error": "path is required"}
	if not FileAccess.file_exists(scene_path):
		return {"error": "Scene file not found: " + scene_path}
	editor_interface.open_scene_from_path(scene_path)
	var open_scenes := editor_interface.get_open_scenes()
	if scene_path not in open_scenes:
		return {"error": "Failed to open scene: " + scene_path}
	return {"success": true, "open_scenes": Array(open_scenes)}

func save_scene(editor_interface: EditorInterface) -> Dictionary:
	editor_interface.save_scene()
	return {"success": true}

func rename_node(editor_interface: EditorInterface, params: Dictionary) -> Dictionary:
	var root := editor_interface.get_edited_scene_root()
	if root == null:
		return {"error": "No scene open"}

	var node := root.get_node_or_null(params.get("path", ""))
	if node == null:
		return {"error": "Node not found: " + params.get("path", "")}

	var old_name: String = node.name
	var new_name: String = params.get("new_name", "")
	if new_name == "":
		return {"error": "new_name is required"}

	var undo_redo := editor_interface.get_editor_undo_redo()
	undo_redo.create_action("Rename Node")
	undo_redo.add_do_property(node, "name", new_name)
	undo_redo.add_undo_property(node, "name", old_name)
	undo_redo.commit_action()

	var rel_path: String = str(root.get_path_to(node))
	return {"success": true, "old_name": old_name, "new_name": new_name, "new_path": rel_path}

func duplicate_node(editor_interface: EditorInterface, params: Dictionary) -> Dictionary:
	var root := editor_interface.get_edited_scene_root()
	if root == null:
		return {"error": "No scene open"}

	var node := root.get_node_or_null(params.get("path", ""))
	if node == null:
		return {"error": "Node not found: " + params.get("path", "")}

	var parent := node.get_parent()
	if parent == null:
		return {"error": "Cannot duplicate root node"}

	var dup := node.duplicate()
	if params.has("new_name"):
		dup.name = params.get("new_name")

	var undo_redo := editor_interface.get_editor_undo_redo()
	undo_redo.create_action("Duplicate Node")
	undo_redo.add_do_method(parent, "add_child", dup)
	undo_redo.add_do_method(dup, "set_owner", root)
	undo_redo.add_undo_method(parent, "remove_child", dup)
	undo_redo.commit_action()

	var rel_path: String = str(root.get_path_to(dup))
	return {"success": true, "path": rel_path}

func move_node(editor_interface: EditorInterface, params: Dictionary) -> Dictionary:
	var root := editor_interface.get_edited_scene_root()
	if root == null:
		return {"error": "No scene open"}

	var node := root.get_node_or_null(params.get("path", ""))
	if node == null:
		return {"error": "Node not found: " + params.get("path", "")}

	var parent := node.get_parent()
	if parent == null:
		return {"error": "Cannot move root node"}

	var old_index: int = node.get_index()
	var new_index: int = params.get("index", 0)

	var undo_redo := editor_interface.get_editor_undo_redo()
	undo_redo.create_action("Move Node")
	undo_redo.add_do_method(parent, "move_child", node, new_index)
	undo_redo.add_undo_method(parent, "move_child", node, old_index)
	undo_redo.commit_action()

	return {"success": true, "new_index": new_index}
