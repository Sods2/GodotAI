@tool
extends RefCounted

# Convert a JSON-decoded value (bool/int/float/String/Array/Dictionary) into the
# Godot Variant type a property expects. The MCP bridge receives every value as
# JSON, so a Vector2 arrives as {"x":1,"y":2} (a Dictionary) and a Color as
# {"r":..} or "#rrggbb". Assigning those straight to a typed property silently
# no-ops, so coerce first and the assignment actually takes.
static func coerce(value, type: int):
	match type:
		TYPE_BOOL:
			return bool(value)
		TYPE_INT:
			return int(value)
		TYPE_FLOAT:
			return float(value)
		TYPE_STRING:
			return str(value)
		TYPE_STRING_NAME:
			return StringName(str(value))
		TYPE_VECTOR2:
			return _vec2(value)
		TYPE_VECTOR2I:
			var v := _vec2(value)
			return Vector2i(roundi(v.x), roundi(v.y))
		TYPE_VECTOR3:
			return _vec3(value)
		TYPE_VECTOR3I:
			var v := _vec3(value)
			return Vector3i(roundi(v.x), roundi(v.y), roundi(v.z))
		TYPE_VECTOR4:
			return _vec4(value)
		TYPE_VECTOR4I:
			var v := _vec4(value)
			return Vector4i(roundi(v.x), roundi(v.y), roundi(v.z), roundi(v.w))
		TYPE_COLOR:
			return _color(value)
		TYPE_RECT2:
			return _rect2(value)
		TYPE_RECT2I:
			var r := _rect2(value)
			return Rect2i(roundi(r.position.x), roundi(r.position.y), roundi(r.size.x), roundi(r.size.y))
		_:
			return value


static func _num(value, key: String, idx: int, def: float) -> float:
	if value is Dictionary:
		return float(value.get(key, def))
	if value is Array and idx < value.size():
		return float(value[idx])
	return def


static func _vec2(value) -> Vector2:
	if value is Vector2:
		return value
	return Vector2(_num(value, "x", 0, 0.0), _num(value, "y", 1, 0.0))


static func _vec3(value) -> Vector3:
	if value is Vector3:
		return value
	return Vector3(_num(value, "x", 0, 0.0), _num(value, "y", 1, 0.0), _num(value, "z", 2, 0.0))


static func _vec4(value) -> Vector4:
	if value is Vector4:
		return value
	return Vector4(_num(value, "x", 0, 0.0), _num(value, "y", 1, 0.0), _num(value, "z", 2, 0.0), _num(value, "w", 3, 0.0))


static func _color(value) -> Color:
	if value is Color:
		return value
	if value is String:
		return Color.html(value)
	if value is Dictionary:
		return Color(
			float(value.get("r", 0.0)),
			float(value.get("g", 0.0)),
			float(value.get("b", 0.0)),
			float(value.get("a", 1.0))
		)
	if value is Array and value.size() >= 3:
		var a := 1.0 if value.size() < 4 else float(value[3])
		return Color(float(value[0]), float(value[1]), float(value[2]), a)
	return Color()


static func _rect2(value) -> Rect2:
	if value is Rect2:
		return value
	if value is Dictionary:
		if value.has("position") or value.has("size"):
			return Rect2(_vec2(value.get("position", {})), _vec2(value.get("size", {})))
		var w := float(value.get("w", value.get("width", 0.0)))
		var h := float(value.get("h", value.get("height", 0.0)))
		return Rect2(float(value.get("x", 0.0)), float(value.get("y", 0.0)), w, h)
	if value is Array and value.size() >= 4:
		return Rect2(float(value[0]), float(value[1]), float(value[2]), float(value[3]))
	return Rect2()


# Loose equality with float tolerance, for verifying that a write took effect.
static func values_match(a, b) -> bool:
	if typeof(a) != typeof(b):
		return a == b
	match typeof(a):
		TYPE_FLOAT:
			return is_equal_approx(a, b)
		TYPE_VECTOR2, TYPE_VECTOR3, TYPE_VECTOR4, TYPE_COLOR, TYPE_QUATERNION:
			return a.is_equal_approx(b)
		_:
			return a == b
