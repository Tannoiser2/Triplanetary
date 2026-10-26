class_name ReplayRules
extends RefCounted

static func record(state: Dictionary, label: String) -> void:
	if not state.has("replay_frames"): state.replay_frames = []
	state.replay_frames.append({
		"index": state.replay_frames.size(),
		"label": label,
		"turn": state.turn,
		"segment": state.segment,
		"phase": state.phase,
		"winner": state.get("winner", ""),
		"rng_state": state.get("rng_state", 0),
		"ships": state.ships.duplicate(true),
		"ordnance": state.get("ordnance", []).duplicate(true),
		"bases": state.get("bases", []).duplicate(true),
		"special_asteroids": state.get("special_asteroids", []).duplicate(true),
		"log": state.log.duplicate(true)
	})

static func describe(frame: Dictionary) -> String:
	var lines := ["FOTOGRAMMA %d · %s" % [int(frame.get("index", 0)) + 1, frame.get("label", "")], "Giorno %d · %s · %s" % [frame.get("turn", 0), frame.get("segment", ""), String(frame.get("phase", "")).to_upper()]]
	for ship: Dictionary in frame.get("ships", []):
		var condition: String = "distrutta" if ship.get("destroyed", false) else ("a terra: " + ship.get("landed_at", "") if ship.get("landed_at", "") != "" else "pos %s · v%s" % [ship.get("position", Vector2i.ZERO), ship.get("velocity", Vector2i.ZERO)])
		lines.append("%s · fuel %d · %s" % [ship.get("name", ship.get("id", "?")), ship.get("fuel", 0), condition])
	var log: Array = frame.get("log", [])
	if not log.is_empty(): lines.append("\nUltimo evento: " + str(log.back()))
	return "\n".join(lines)
