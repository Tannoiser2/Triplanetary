class_name Persistence
extends RefCounted
## Salvataggi locali (user://, su Web diventa IndexedDB) e formato JSON portabile.

const SLOT_PATH := "user://triplanetary_%s.json"
const FORMAT := "triplanetary-save"
const VERSION := 2

static func save_slot(state: Dictionary, slot := "auto") -> Error:
	var f := FileAccess.open(SLOT_PATH % slot, FileAccess.WRITE)
	if f == null: return FileAccess.get_open_error()
	f.store_string(to_json(state))
	return OK

static func has_slot(slot := "auto") -> bool:
	return FileAccess.file_exists(SLOT_PATH % slot)

static func load_slot(slot := "auto") -> Dictionary:
	if not has_slot(slot): return {}
	return from_json(FileAccess.get_file_as_string(SLOT_PATH % slot))

static func slot_summary(slot := "auto") -> String:
	var st := load_slot(slot)
	if st.is_empty(): return ""
	var info := Scenarios.info(st.scenario)
	return "%s · giorno %d" % [info.get("title", st.scenario), int(st.turn)]

static func to_json(state: Dictionary) -> String:
	var clean := state.duplicate(true)
	clean.fx = []; clean.moves = []
	return JSON.stringify({"format": FORMAT, "version": VERSION, "state": _encode(clean)})

static func from_json(text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary or parsed.get("format", "") != FORMAT or int(parsed.get("version", 0)) != VERSION: return {}
	var st: Variant = _decode(parsed.state)
	if not st is Dictionary: return {}
	_fix_numbers(st)
	return st

static func _encode(v: Variant) -> Variant:
	if v is Vector2i: return {"$v": [v.x, v.y]}
	if v is Dictionary:
		var out := {}
		for k in v: out[str(k)] = _encode(v[k])
		return out
	if v is Array:
		var out2 := []
		for x in v: out2.append(_encode(x))
		return out2
	if v is Color: return v.to_html()
	return v

static func _decode(v: Variant) -> Variant:
	if v is Dictionary:
		if v.has("$v") and v.size() == 1: return Vector2i(int(v["$v"][0]), int(v["$v"][1]))
		var out := {}
		for k in v: out[k] = _decode(v[k])
		return out
	if v is Array:
		var out2 := []
		for x in v: out2.append(_decode(x))
		return out2
	return v

## JSON restituisce float: riporta a interi i campi numerici che il motore confronta con ==.
static func _fix_numbers(v: Variant) -> void:
	if v is Dictionary:
		for k in v.keys():
			var x: Variant = v[k]
			if x is float and x == floorf(x) and absf(x) < 1e15: v[k] = int(x)
			else: _fix_numbers(x)
	elif v is Array:
		for i in range(v.size()):
			var y: Variant = v[i]
			if y is float and y == floorf(y) and absf(y) < 1e15: v[i] = int(y)
			else: _fix_numbers(y)
