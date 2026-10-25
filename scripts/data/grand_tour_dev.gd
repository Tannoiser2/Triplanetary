class_name GrandTourDev
extends RefCounted

const HexMathRef = preload("res://scripts/engine/hex.gd")

# Coordinate odd-q calibrate sulla plancia A4 ruotata in senso orario.
# La conversione ad assiali mantiene esatti vicinato, vettori e distanze.
const BODY_OFFSET_DATA := [
	["venus", "Venere", 15, 9, true, true],
	["sol", "Sol", 18, 15, true, false],
	["mercury", "Mercurio", 15, 18, true, false],
	["terra", "Terra", 24, 26, true, true],
	["luna", "Luna", 22, 26, false, false],
	["mars", "Marte", 34, 5, true, true],
	["ceres", "Ceres", 39, 9, true, false],
	["callisto", "Callisto", 39, 11, true, true],
	["clandestine", "Clandestine", 39, 24, true, false],
	["jupiter", "Giove", 47, 15, true, false],
	["io", "Io", 48, 16, false, false],
	["ganymede", "Ganimede", 48, 19, true, false]
]

static func create_state() -> Dictionary:
	var bodies := []
	var gravity := []
	for row: Array in BODY_OFFSET_DATA:
		var body_hex := _offset_to_axial(row[2], row[3])
		bodies.append({"id": row[0], "name": row[1], "hex": body_hex, "full_gravity": row[4], "base": row[5]})
		for i in range(6):
			gravity.append({"hex": body_hex + HexMathRef.DIRECTIONS[i], "acceleration": HexMathRef.DIRECTIONS[(i + 3) % 6], "weak": not row[4], "body_id": row[0]})
	var terra: Vector2i = bodies.filter(func(body): return body.id == "terra")[0].hex
	return {
		"scenario": "grand-tour-2037", "ruleset": "updated-second-edition", "seed": 2037,
		"rng_state": 2037, "turn": 1, "segment": "P1", "phase": "astrogation", "commands": {},
		"pending_combat": {}, "log": [], "events": [], "winner": "",
		"map_columns": 56, "map_rows": 35,
		"bodies": bodies, "gravity": gravity,
		"ships": [_ship("p1", "P1", terra, 0), _ship("p2", "P2", terra, 1)]
	}

static func _ship(id: String, owner: String, position: Vector2i, base_side: int) -> Dictionary:
	return {"id": id, "owner": owner, "name": "Corvetta " + owner, "position": position,
		"velocity": Vector2i.ZERO, "fuel": 20, "fuel_spent": 0, "max_fuel": 20,
		"combat": 2, "commercial": false, "pending_gravity": [], "disabled_until_turn": 0,
		"destroyed": false, "overload_available": true, "visited_bodies": ["terra"],
		"landed_at": "terra", "base_side": base_side, "must_burn_after_takeoff": false,
		"heroic": false, "last_attack_key": "", "last_target_key": "", "previous_position": position}

static func _offset_to_axial(column: int, row: int) -> Vector2i:
	return Vector2i(column, row - (column - (column & 1)) / 2)
