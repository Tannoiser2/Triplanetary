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
