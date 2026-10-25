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

const ASTEROID_OFFSETS := [
	[32,7],[32,13],[32,14],[32,16],[32,17],[32,20],[32,22],
	[33,14],[33,16],[33,19],[33,21],[33,22],[33,24],[33,30],
	[34,12],[34,16],[34,17],[34,19],[34,20],[34,22],[34,24],[34,25],[34,26],[34,27],[34,28],[34,29],[34,30],[34,31],
	[35,1],[35,2],[35,13],[35,16],[35,17],[35,18],[35,29],[35,32],[35,33],
	[36,1],[36,2],[36,3],[36,12],[36,14],[36,16],[36,19],[36,21],[36,23],[36,24],[36,29],
	[37,2],[37,4],[37,5],[37,20],[37,22],[37,23],[37,28],[37,31],[37,32],[37,33],
	[38,6],[38,8],[38,11],[38,23],[38,30],[39,0],[39,1],[39,3],[39,21],[40,2],[41,0],[41,1]
]
const SPECIAL_ASTEROID_OFFSETS := [[37,25],[36,26],[37,26],[38,26],[36,27],[37,27],[38,27]]

static func create_state() -> Dictionary:
	var bodies := []
	var gravity := []
	for row: Array in BODY_OFFSET_DATA:
		var body_hex := _offset_to_axial(row[2], row[3])
		bodies.append({"id": row[0], "name": row[1], "hex": body_hex, "full_gravity": row[4], "base": row[5], "owner":"neutral" if row[5] else ""})
		for i in range(6):
			gravity.append({"hex": body_hex + HexMathRef.DIRECTIONS[i], "acceleration": HexMathRef.DIRECTIONS[(i + 3) % 6], "weak": not row[4], "body_id": row[0]})
	var terra: Vector2i = bodies.filter(func(body): return body.id == "terra")[0].hex
	var bases := []
	for body: Dictionary in bodies:
		if body.base:
			bases.append({"id":"base-" + body.id,"name":"Base di " + body.name,"kind":"planetary","body_id":body.id,"owner":"shared","active":true,"defense":false})
	var asteroids: Array = ASTEROID_OFFSETS.map(func(cell): return _offset_to_axial(cell[0], cell[1]))
	var special_asteroids: Array = SPECIAL_ASTEROID_OFFSETS.map(func(cell): return _offset_to_axial(cell[0], cell[1]))
	return {
		"scenario": "grand-tour-2037", "ruleset": "updated-second-edition", "seed": 2037,
		"rng_state": 2037, "turn": 1, "segment": "P1", "phase": "astrogation", "commands": {},
		"pending_combat": {}, "ordnance": [], "asteroids": asteroids, "special_asteroids": special_asteroids, "next_entity_id": 1,
		"knowledge": {"P1":{"p2":true},"P2":{"p1":true}},
		"log": [], "events": [], "winner": "",
		"map_columns": 56, "map_rows": 35,
		"bodies": bodies, "bases": bases, "gravity": gravity,
		"ships": [_ship("p1", "P1", terra, 0), _ship("p2", "P2", terra, 1)]
	}

static func _ship(id: String, owner: String, position: Vector2i, base_side: int) -> Dictionary:
	return {"id": id, "owner": owner, "name": "Corvetta " + owner, "position": position,
		"velocity": Vector2i.ZERO, "fuel": 20, "fuel_spent": 0, "max_fuel": 20,
		"combat": 2, "commercial": false, "pending_gravity": [], "disabled_until_turn": 0,
		"destroyed": false, "overload_available": true, "visited_bodies": ["terra"],
		"landed_at": "terra", "base_side": base_side, "must_burn_after_takeoff": false,
		"heroic": false, "last_attack_key": "", "last_target_key": "", "previous_position": position,
		"type":"corvette", "cargo_capacity": 5, "inventory": {"mine":0,"torpedo":0,"nuke":0}, "launched_key":"", "must_change_after_launch":false}

static func _offset_to_axial(column: int, row: int) -> Vector2i:
	return Vector2i(column, row - (column - (column & 1)) / 2)
