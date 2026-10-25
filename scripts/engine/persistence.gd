class_name GamePersistence
extends RefCounted

const SAVE_PATH := "user://triplanetary-autosave.bin"
const SAVE_VERSION := 1

static func save_game(state: Dictionary) -> Error:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_var({"version": SAVE_VERSION, "state": state}, true)
	return OK

static func load_game() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH): return {}
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null: return {}
	var payload: Variant = file.get_var(true)
	if not payload is Dictionary or payload.get("version", 0) != SAVE_VERSION: return {}
	return payload.get("state", {}).duplicate(true)

static func round_trip(state: Dictionary) -> Dictionary:
	return bytes_to_var(var_to_bytes(state))

static func to_portable_json(state: Dictionary) -> String:
	return JSON.stringify({"format":"triplanetary-save","version":SAVE_VERSION,"state":_encode(state)}, "  ")

static func from_portable_json(text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary: return {}
	if parsed.get("format", "") != "triplanetary-save" or int(parsed.get("version", 0)) != SAVE_VERSION: return {}
	var decoded: Variant = _decode(parsed.get("state", {}))
	return decoded if decoded is Dictionary else {}

static func _encode(value: Variant) -> Variant:
	if value is Vector2i: return {"$type":"Vector2i","x":value.x,"y":value.y}
	if value is Dictionary:
		var out := {}
		for key in value: out[str(key)] = _encode(value[key])
		return out
	if value is Array:
		var out := []
		for item in value: out.append(_encode(item))
		return out
	return value

static func _decode(value: Variant) -> Variant:
	if value is Dictionary:
		if value.get("$type", "") == "Vector2i": return Vector2i(int(value.get("x", 0)), int(value.get("y", 0)))
		var out := {}
		for key in value: out[key] = _decode(value[key])
		return out
	if value is Array:
		var out := []
		for item in value: out.append(_decode(item))
		return out
	return value
