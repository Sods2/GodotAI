@tool
class_name InspectorHandler
extends RefCounted

const _Coerce = preload("res://addons/godot_mcp_bridge/handlers/value_coerce.gd")

func get_properties(editor_interface: EditorInterface, params: Dictionary) -> Dictionary:
	var root := editor_interface.get_edited_scene_root()
	if root == null:
		return {"error": "No scene open"}

	var node_path: String = params.get("path", ".")
	var node: Node
	if node_path == "." or node_path == "":
		node = root
	else:
		node = root.get_node_or_null(node_path)

	if node == null:
		return {"error": "Node not found: " + node_path}

	var props: Array[Dictionary] = []
	for prop in node.get_property_list():
		if prop["usage"] & PROPERTY_USAGE_EDITOR:
			var value = node.get(prop["name"])
			props.append({
				"name": prop["name"],
				"type": type_string(prop["type"]),
				"value": str(value)
			})

	return {"node": node_path, "properties": props}

func set_property(editor_interface: EditorInterface, params: Dictionary) -> Dictionary:
	var root := editor_interface.get_edited_scene_root()
	if root == null:
		return {"error": "No scene open"}

	var node_path: String = params.get("path", ".")
	var prop_name: String = params.get("property", "")
	var prop_value = params.get("value", null)

	var node: Node
	if node_path == "." or node_path == "":
		node = root
	else:
		node = root.get_node_or_null(node_path)

	if node == null:
		return {"error": "Node not found: " + node_path}

	var old_value = node.get(prop_name)

	# Determine the property's expected Variant type so a JSON value (e.g. a
	# Dictionary {"x":1,"y":2} for a Vector2) is coerced to the real type before
	# assignment. Prefer the declared type from the property list, falling back
	# to the current value's type.
	var target_type := typeof(old_value)
	for prop in node.get_property_list():
		if prop["name"] == prop_name:
			target_type = int(prop["type"])
			break
	var coerced = _Coerce.coerce(prop_value, target_type)

	var undo_redo := editor_interface.get_editor_undo_redo()
	undo_redo.create_action("Set Property: " + prop_name)
	undo_redo.add_do_property(node, prop_name, coerced)
	undo_redo.add_undo_property(node, prop_name, old_value)
	undo_redo.commit_action()

	# Verify the write actually landed rather than reporting a blind success.
	var actual = node.get(prop_name)
	if not _Coerce.values_match(actual, coerced):
		return {
			"success": false,
			"property": prop_name,
			"error": "Property did not accept the value (type mismatch or read-only property). Requested %s, node still holds %s." % [str(coerced), str(actual)],
			"requested": str(coerced),
			"value": str(actual)
		}

	return {"success": true, "property": prop_name, "value": str(actual)}

func import_asset(editor_interface: EditorInterface, params: Dictionary) -> Dictionary:
	var paths: Array = params.get("paths", [])
	var packed := PackedStringArray(paths)
	editor_interface.get_resource_filesystem().reimport_files(packed)
	return {"success": true, "paths": paths}

func read_resource(editor_interface: EditorInterface, params: Dictionary) -> Dictionary:
	var res_path: String = params.get("path", "")
	var res = ResourceLoader.load(res_path)
	if res == null:
		return {"error": "Resource not found: " + res_path}
	var properties := []
	for prop in res.get_property_list():
		var pname: String = prop["name"]
		if pname.begins_with("_") or pname == "script" or pname == "resource_path" or pname == "resource_name":
			continue
		var usage: int = prop.get("usage", 0)
		if usage & PROPERTY_USAGE_EDITOR == 0 and usage & PROPERTY_USAGE_STORAGE == 0:
			continue
		var val = res.get(pname)
		if val is Object or val is Array or val is Dictionary:
			val = str(val)
		properties.append({"name": pname, "value": val})
	return {"type": res.get_class(), "path": res_path, "properties": properties}

func write_resource(editor_interface: EditorInterface, params: Dictionary) -> Dictionary:
	var res_path: String = params.get("path", "")
	var properties: Dictionary = params.get("properties", {})
	var res = ResourceLoader.load(res_path)
	if res == null:
		return {"error": "Resource not found: " + res_path}
	# Coerce JSON values to each property's real Variant type so composite types
	# (Vector2, Color, …) are not silently dropped the way a raw Dictionary would.
	var type_map := {}
	for prop in res.get_property_list():
		type_map[prop["name"]] = int(prop["type"])
	for key in properties:
		var target_type: int = type_map.get(key, typeof(res.get(key)))
		res.set(key, _Coerce.coerce(properties[key], target_type))
	var err := ResourceSaver.save(res, res_path)
	if err != OK:
		return {"error": "Failed to save resource: " + str(err)}
	return {"success": true}
